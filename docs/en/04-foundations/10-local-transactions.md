[English](10-local-transactions.md) · [中文](../../zh/04-foundations/10-local-transactions.md)

# Local transactions

The rules for one PostgreSQL transaction inside one component: the isolation level, the timeouts every transaction sets, which errors are retried, the order locks are taken in, advisory locks, what may and may not happen inside a transaction, and the connection budget behind it. For whoever writes repository code, reviews it, implements the component protocol in a new language, or wants to change a default.

## Scope

- **In:** everything between `BEGIN` and `COMMIT` in one component's own schema; how the isolation tools are chosen per invariant; how database errors leave the transaction; long-running and batch transactions; the connection budget that bounds how many transactions run at once.
- **Out:** state that spans two components (events, commands, sagas, reconcilers): [11-consistency-across-components.md](11-consistency-across-components.md). The engine, its version promise, pool sizing and pooler rules: [03-database.md](03-database.md). Time budgets across a whole request: [16-deadlines-and-retries.md](16-deadlines-and-retries.md). How a repository is written day to day: [02-backend.md](../01-conventions/02-backend.md#database).

## Choice

1. **READ COMMITTED by default**, with explicit tools for each invariant, chosen from a fixed ladder (constraint, conditional update, ordered row locks, transaction-level advisory lock, SERIALIZABLE). A single transaction may ask for REPEATABLE READ or SERIALIZABLE; the default never changes.
2. **Every transaction sets its own timeouts with `SET LOCAL`**: `statement_timeout`, `lock_timeout`, `idle_in_transaction_session_timeout`, and on PostgreSQL 17 or later `transaction_timeout`. Role-level defaults are not relied on.
3. **Serialization failures (`40001`) and deadlocks (`40P01`) are retried automatically**, by re-running the whole transaction body; nothing else is retried at this level.
4. **Locks on several rows are taken in a fixed order** (primary key or business key), and duplicates in a request are rejected before locking.
5. **Advisory locks are transaction-level only**, and their key includes the component's schema.
6. **No network call inside a transaction.** The only ways to cause an effect outside the database from inside a transaction are an outbox row and a job-queue row, both written in the same transaction.
7. **No nested transactions.** One unit of work holds at most one connection at a time.
8. **Each component, and each member of a shell, has its own connection budget.**

**Status**: decided; lands with the component protocol and the 3.0.0 component sweep. Today transactions run at the database default with no timeout at all, no retry, and no guard against network calls; three consumers call other components while holding a transaction, and multi-item reservations lock rows in request order.

## Port contract

The contract is what reaches PostgreSQL, so that an implementation in any language behaves the same. Function names belong to each SDK.

**Every read-write transaction starts with exactly this sequence:**

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;            -- or the level the transaction asked for
SET LOCAL ROLE <PG_USER of this component>;      -- in a shell: the member's own PG_USER
SET LOCAL search_path TO <PG_SCHEMA>;
SET LOCAL application_name = '<component ID>';   -- in a shell: the member's ID
SET LOCAL statement_timeout = '<min(5s, remaining deadline)>';
SET LOCAL lock_timeout = '2s';
SET LOCAL idle_in_transaction_session_timeout = '30s';
SET LOCAL transaction_timeout = '<remaining deadline>';  -- PostgreSQL 17 or later only
```

- The role and the schema come from configuration (`PG_USER`, `PG_SCHEMA`), never from a name derived in code.
- `SET LOCAL` and never `SET`: without `LOCAL` the setting stays on the pooled connection and the next borrower inherits it ([02-backend.md](../01-conventions/02-backend.md#database)).
- **Why per transaction and not per role:** `ALTER ROLE … SET` is applied at login only. A shell logs in as its own role and then switches to each member with `SET LOCAL ROLE`, so a member role's defaults never apply inside a shell. Role-level settings on the login role are a backstop ([03-database.md](03-database.md)), not the mechanism.
- "Remaining deadline" is the caller's remaining budget ([16-deadlines-and-retries.md](16-deadlines-and-retries.md)). With no deadline the defaults above apply.

**Read snapshots** for reports that must see one moment across several queries: `BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY`, the same `SET LOCAL` lines, `statement_timeout` up to 30 s.

**How database errors leave a transaction:**

| SQLSTATE | Meaning | At this level | Surfaced as (code / reason, see [15](15-user-api-and-errors.md)) |
|---|---|---|---|
| `40001` | serialization failure | roll back, wait `10 ms · 2^n` ± jitter, re-run the body; at most 3 attempts | after the last attempt: `ABORTED` / `TX_CONFLICT` |
| `40P01` | deadlock detected | same as `40001` | same |
| `55P03` | lock not available (`lock_timeout`) | no retry | `ABORTED` / `LOCK_TIMEOUT` |
| `57014` | statement cancelled (`statement_timeout`) | no retry | `DEADLINE_EXCEEDED` / `STATEMENT_TIMEOUT` |
| `25P04` | transaction timeout (PostgreSQL 17+) | no retry | `DEADLINE_EXCEEDED` / `STATEMENT_TIMEOUT` |
| `25P03` | idle in transaction too long | the server closed the connection | `INTERNAL`: it is a bug in the component |
| `53300` | too many connections | no retry | `UNAVAILABLE` / `DB_TOO_MANY_CONNECTIONS` |
| `23505` | unique violation | no retry | the component maps it to its own reason, usually `ALREADY_EXISTS` |

A retry re-runs the body from the start in a new transaction. That is safe only because the body touches nothing but the transaction, which the next two rules guarantee. A caller that wants to retry a `LOCK_TIMEOUT` does so a layer higher, with the same idempotency key. Retries are counted in `be_tx_retries_total{component,reason}`.

**No network inside a transaction.** While a unit of work holds an open transaction, every outbound call the runtime offers (gRPC, user-facing HTTP, a direct publish to the bus) refuses to start and fails with `INTERNAL` / `NETWORK_IN_TX`: a programming error, surfaced in development and tests (in test builds it aborts the test). The only exits are:

- an outbox row: the event is published after commit ([12-event-bus.md](12-event-bus.md));
- a job-queue row: the command runs after commit, outside any transaction ([19-background-jobs.md](19-background-jobs.md)).

Symptom when broken: the row lock is held for the downstream's latency, so every other request on that row queues behind it; a retried body repeats the call; an event handler holding its transaction past the bus's acknowledgement wait is redelivered and runs twice.

**No nested transactions.** Opening a transaction while the same unit of work already holds one fails with `INTERNAL` / `NESTED_TX`. An event handler that writes locally receives the consumer's transaction instead of opening its own. Symptom when broken: once pools have an upper bound, a burst where every worker holds one connection and waits for a second deadlocks the whole pool.

**Advisory locks** are always transaction-level:

```sql
SELECT pg_advisory_xact_lock(hashtext(current_schema() || ':' || $1), hashtext($2));      -- waits, bounded by lock_timeout
SELECT pg_try_advisory_xact_lock(hashtext(current_schema() || ':' || $1), hashtext($2));  -- returns false instead of waiting
-- $1 = the lock name; $2 = '<part>|<part>…'
```

Session-level advisory locks (`pg_advisory_lock`) are never used: a lock taken on a pooled connection stays with whoever borrows it next, and transaction-mode poolers cannot carry it. The schema in the key keeps two shell members that use the same lock name from blocking each other, while one component running standalone and in a shell at once, which share a schema, still exclude each other.

**Long and batch transactions.**

- An event handler's local write is expected to finish within 1 s; longer runs log a warning and count in a metric.
- Backfills, freezes and bulk recalculations commit every 1,000 rows at most, and record progress so they resume.
- Migration DDL sets `lock_timeout = '5s'` and retries; partitions are created with `CREATE TABLE … (LIKE …)` followed by `ATTACH PARTITION`, which takes only `SHARE UPDATE EXCLUSIVE` on the parent. A plain `CREATE TABLE … PARTITION OF` needs `ACCESS EXCLUSIVE`; queued behind one long transaction it makes every later read and write of the table wait behind it, which looks like the whole component hanging.

**Connection budget.** Each component has the configuration key `PG_POOL_MAX` (default 10): the most connections it holds. In a shell each member keeps its own `PG_POOL_MAX` as a budget inside the shell's pool. A member that has used its budget waits up to `PG_POOL_ACQUIRE_TIMEOUT` (default 5 s) or its remaining deadline, whichever is shorter, and then fails with `RESOURCE_EXHAUSTED` / `DB_POOL_EXHAUSTED`; other members are unaffected. Pool sizing, lifetimes and pooler compatibility are in [03-database.md](03-database.md).

### The isolation ladder

Pick the first rung that expresses the invariant:

| Rung | Tool | Example in this project |
|---|---|---|
| 1 | a constraint: unique (partial) index, exclusion constraint, check | "no two price lists for one product overlap in time" |
| 2 | a conditional update: the check and the write in one `UPDATE … WHERE <condition> RETURNING` (a version column is one such condition) | stock never below zero; credit exposure accumulated atomically |
| 3 | row locks in a fixed order: `SELECT … FOR UPDATE ORDER BY <key>` | the accounting periods of one legal entity; several stock lines of one reservation, sorted by `(warehouse_id, product_id)` |
| 4 | a transaction-level advisory lock on a logical key, when no row exists to lock | "recalculate one customer's credit, one at a time" |
| 5 | `SERIALIZABLE` for this transaction, with the automatic retry | an invariant over several rows that rungs 1 to 4 cannot express |

Placement by domain:

- **Stock:** rung 2 plus ordered locking for multi-line requests.
- **Ledger:** period rows locked (rung 3), debit equals credit checked inside the transaction, reports through a read snapshot.
- **Credit:** finance's atomic update is the authority; the check sales does before confirming is advisory only.
- **Numbering:** gap-free numbers (accounting vouchers, numbered per period) take a row lock on the series as the serialization point; numbers that may have gaps use a sequence ([04-identifiers-and-numbering.md](04-identifiers-and-numbering.md)).

## Alternatives

| Approach | Who uses it | Strengths | Weaknesses |
|---|---|---|---|
| **READ COMMITTED plus explicit tools** (chosen) | common PostgreSQL OLTP practice | hot rows never abort: PostgreSQL re-evaluates the `WHERE` of a conditional update against the newest row version | each invariant needs the right rung; a report needs an explicit snapshot |
| REPEATABLE READ plus a global retry of the whole request | Odoo (retries on `40001`, `40P01`, `55P03`, up to 5 times) | every request sees one snapshot | concurrent updates of one hot row abort with `40001`; a retried request re-runs any side effect that is not in the transaction |
| SERIALIZABLE everywhere plus client retry loops | CockroachDB, Spanner-style systems | no anomalies to reason about | abort rate on hot rows (stock balances, periods); every caller must be retry-safe |
| A logical lock service beside the database | SAP S/4 enqueue server | locks visible across sessions and steps | another service; in PostgreSQL an advisory lock is the same thing without one |
| Optimistic concurrency only (version column, retry on mismatch) | many ORMs, ERPNext's `modified` check | no locks held | a hot row retries endlessly under contention; it is rung 2 of the ladder, not a whole policy |

## Why this choice

- **The two hot spots of an ERP** are `inventory_balances` (one row per product and warehouse) and accounting periods (one set per legal entity). Under READ COMMITTED a conditional update on them waits and then proceeds against the newest row; under REPEATABLE READ or SERIALIZABLE the same contention becomes aborts and retries, which users feel as latency.
- **The ladder is explicit and reviewable.** Each invariant names its rung, so a reviewer, human or AI, can check the tool against the invariant instead of trusting a global level.
- **Timeouts set per transaction work in both forms.** Standalone and in a shell the same `SET LOCAL` lines run; nothing depends on login-time role settings that a shell would silently skip.
- **Automatic retry is safe** because the body cannot reach the network and cannot open a second transaction.

## Why not the others

- **REPEATABLE READ with a global retry** turns contention on hot rows into aborts, and the retry repeats whatever the request did outside the transaction. It is safe only if nothing ever does, which is the rule we enforce anyway, so the global retry adds aborts and buys nothing.
- **SERIALIZABLE everywhere** has the same abort problem on hot rows, at a higher rate, and makes every caller in every language write retry loops.
- **A separate lock service** is another piece of infrastructure to run; a transaction-level advisory lock gives the same mutual exclusion inside the database.
- **Optimistic concurrency alone** spins under contention; it is kept as one rung, for rows that are rarely contended.

## When to switch

- **Per transaction, to SERIALIZABLE:** when an invariant spans several rows and no constraint, conditional update, ordered lock or advisory lock expresses it. Record why in a comment at the call site.
- **The default level:** not expected to change. A measured, repeated class of anomaly that the ladder cannot express would reopen it.
- **The timeout defaults:** when measurements show a legitimate statement class above 5 s (reports, exports), those move to a read snapshot or a background job; the default stays short.

## How to switch

- **Isolation of one transaction:** one option on the call that opens it. No migration, no configuration.
- **Timeouts of one transaction:** options on the same call, within the caller's remaining deadline; a longer statement timeout never outlives the deadline.
- **Connection budget:** `PG_POOL_MAX` in the component's `config/<scope>-<name>.yaml`.
- **The engine:** see [03-database.md](03-database.md). Changing the engine within the PostgreSQL dialect family changes no rule here.

## Conformance tests

Planned suite `tools/be-acceptance/conformance/store/`, run on PostgreSQL 14, 16 and 17 against each official SDK. Each case is written red first where today's behaviour fails it.

- Inside a transaction `SHOW statement_timeout` and `SHOW lock_timeout` return the defaults (red today: both are 0).
- With less than 5 s of deadline left, `statement_timeout` equals the remaining time.
- A write-skew under SERIALIZABLE is retried and its business effect happens once.
- A provoked deadlock (`40P01`) is retried and the transaction succeeds.
- A lock held by the test longer than `lock_timeout` fails the request with `ABORTED` / `LOCK_TIMEOUT` within about 2 s (observable from outside a running container).
- An outbound gRPC call inside a transaction fails with `NETWORK_IN_TX` (red today).
- Opening a transaction inside a transaction fails with `NESTED_TX`.
- With a pool of size 1, nothing set by `SET LOCAL` is visible after commit or rollback.
- A shell login role that switches with `SET LOCAL ROLE` does not receive the member role's `ALTER ROLE … SET` values (pins the PostgreSQL behaviour this design relies on; green today).
- Two shell members taking an advisory lock with the same name do not block each other.
- A member that exhausts its connection budget does not delay another member (red today).

Component tests written red before the sweep:

- erp/inventory: two orders reserving the same two products in opposite order, concurrently, both finish without a deadlock error (red today).
- erp/sales: while a credit-rejected order is being suspended, a slow infra/workflow (3 s) does not delay cancelling the same order beyond 500 ms (red today).
- erp/finance: the receivables summary and its detail lines come from one snapshot.

## Decision records

- [0501 No network call inside a transaction](../02-decisions/05-runtime/0501-no-network-inside-a-transaction.md): this document is its full analysis.
- [0502 READ COMMITTED with an explicit ladder](../02-decisions/05-runtime/0502-isolation-and-retry.md): the isolation ladder, the per-transaction timeouts and the retry of `40001` / `40P01`.
- [0102 One database, one schema per component](../02-decisions/01-architecture/0102-one-schema-per-component.md): each transaction runs as the component's role in its schema.
- [0206 No row-level security; one sharing engine, in authz](../02-decisions/02-permissions/0206-no-row-level-security.md): scoping is in static queries, so the transaction carries no per-user database identity.

## Known limits

- **Only the PostgreSQL dialect family.** Moving to another engine means porting each component's repository layer ([03-database.md](03-database.md)).
- **Gap-free voucher numbers serialize posting per legal entity.** Throughput is bounded at roughly tens to a hundred vouchers per second for one legal entity; other documents allow gaps and are not bounded this way.
- **Automatic retry covers only `40001` and `40P01`.** A lock timeout or a statement timeout reaches the caller.
- **`transaction_timeout` exists only from PostgreSQL 17**; on older servers a transaction is bounded by its statements and by the idle timeout.
- **`hashtext` collisions** between different lock names make two unrelated operations wait for each other; they never make an operation unsafe.
- **The network guard sees only calls made through the runtime.** A component that opens its own HTTP client bypasses it, which is one more reason everything a module uses comes from the runtime ([02-backend.md](../01-conventions/02-backend.md#the-runtime-is-the-only-way-in)); a gate that flags hand-built clients is planned.
