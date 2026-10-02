[English](11-consistency-across-components.md) · [中文](../../zh/04-foundations/11-consistency-across-components.md)

# Consistency across components

How state stays correct when one business action touches two or more components: the outbox, consumer cursors keyed by aggregate stream, idempotent commands, sagas kept on the business row, reconcilers that move stuck flows forward, holds with expiry, and what a user may expect to read right after a write. For whoever designs a flow that crosses a component boundary, writes a consumer or a compensating step, or proposes a workflow engine.

## Scope

- **In:** every mechanism by which a change in one component causes, or must agree with, a change in another; failure, retry and recovery of such flows; read-your-writes expectations across components.
- **Out:** one transaction in one component ([10-local-transactions.md](10-local-transactions.md)); the broker, streams, durables and dead letters ([12-event-bus.md](12-event-bus.md)); the event envelope and contract files ([13-event-contracts.md](13-event-contracts.md)); synchronous calls on the wire ([14-system-rpc.md](14-system-rpc.md)); the job tables that carry asynchronous commands ([19-background-jobs.md](19-background-jobs.md)).

## Choice

Consistency is built in five layers. Each layer uses only the ones below it.

| Layer | What | Provided by |
|---|---|---|
| Local | ACID inside one component | [10-local-transactions.md](10-local-transactions.md) |
| Event | outbox → bus → consumer; at-least-once delivery made effectively-once by a cursor per aggregate stream | the event bus port ([12](12-event-bus.md), [13](13-event-contracts.md)) |
| Command | synchronous: gRPC with an idempotency key plus `GetStatus`; asynchronous: a job enqueued in the business transaction, executed after commit, retried, and escalated when it keeps failing | [14-system-rpc.md](14-system-rpc.md), [19-background-jobs.md](19-background-jobs.md) |
| Process (saga) | a state machine on the business row, with a deadline column, driven forward or back by a reconciler; each compensation is a command | the component's own code plus the reconciler contract below |
| People | exception tasks in infra/workflow; dead-letter tools | infra/workflow, `make dlq-ls` / `make dlq-replay` (planned) |

The rules that follow from it:

1. **A step the user waits for is synchronous** (try-confirm-cancel over gRPC): the user who clicks "confirm" must learn "out of stock" now. **Every side effect after that is asynchronous**, through an event or an enqueued command. "Call it after commit and hope" does not exist.
2. **A process lives in the component that starts it.** There is no central orchestrator component. Its state is the business row; other components see it only through `GetStatus` and events.
3. **A consumer's cursor is keyed by aggregate stream**, not by subject, so events of one aggregate on different subjects can never be applied out of order.
4. **Idempotency keys are namespaced by caller** and bound to the command, its target and a fingerprint of the request.
5. **Every in-flight state has a deadline**, and a reconciler acts on rows past it. A flow that cannot finish ends `SUSPENDED` with an exception task for a person.

**Status**: decided; lands with the component protocol and the 3.0.0 sweep. Today events go over core NATS without persistence, the consumer inbox deduplicates per subject and does not hold under concurrent delivery on partitioned tables, three remote calls are made "after commit, best effort", and recovery is written six different ways.

## Port contract

Tables and rules every implementation, in any language, creates and follows. The tables live in each component's own schema, carry the `besdk_` prefix and are created by the SDK's platform migration; component SQL never touches them. The normative DDL is in `ddl/` of the `brickKit/be-protocol` repository (`02-outbox.sql`, `03-event-cursor.sql`, `04-idempotency.sql`, `05-jobs.sql`), the requirements in its `spec/12-events.md`, `spec/13-idempotency.md` and `spec/14-background-jobs.md`.

### Outbox (producer)

```sql
CREATE TABLE besdk_outbox (
    id                UUID        NOT NULL,             -- UUIDv7; becomes ce-id and the broker's message ID
    created_at        TIMESTAMPTZ NOT NULL,             -- derived from id
    subject           TEXT        NOT NULL,             -- ce-type
    aggregate_type    TEXT        NOT NULL,             -- declared in the event contract
    aggregate_id      TEXT        NOT NULL,             -- ce-subject
    aggregate_version BIGINT      NOT NULL,
    occurred_at       TIMESTAMPTZ NOT NULL,
    traceparent       TEXT        NOT NULL DEFAULT '',
    causation_id      TEXT        NOT NULL DEFAULT '',
    hop_count         INT         NOT NULL DEFAULT 0,
    headers           JSONB       NOT NULL DEFAULT '{}', -- other ce-* extensions, such as legalentity
    payload           JSONB       NOT NULL,
    status            TEXT        NOT NULL DEFAULT 'PENDING',  -- PENDING | SENDING | PUBLISHED
    attempts          INT         NOT NULL DEFAULT 0,
    next_attempt_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    claimed_until     TIMESTAMPTZ,
    published_at      TIMESTAMPTZ,
    last_error        TEXT        NOT NULL DEFAULT '',
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
```

- The row is inserted in the same transaction as the business change. A pump claims rows atomically, publishes, and marks `PUBLISHED` only after the broker confirmed it stored the message ([12-event-bus.md](12-event-bus.md#port-contract)).
- **The outbox is the source of truth for replay**; the broker is transport. Rows stay online 14 days after publication; older history is read from the producer's `List` or its published datasets ([12](12-event-bus.md)).
- All subjects of one `aggregate_type` share one strictly increasing `aggregate_version` ([13-event-contracts.md](13-event-contracts.md)).

### Consumer cursor

```sql
CREATE TABLE besdk_event_cursor (
    consumer       TEXT        NOT NULL DEFAULT '',   -- a projection name; '' is the component's default projection
    aggregate_type TEXT        NOT NULL,
    aggregate_id   TEXT        NOT NULL,
    version        BIGINT      NOT NULL,
    event_id       TEXT        NOT NULL,
    seen_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (consumer, aggregate_type, aggregate_id)
);

-- One statement decides "new or stale" and advances the cursor; no row returned = skip.
INSERT INTO besdk_event_cursor (consumer, aggregate_type, aggregate_id, version, event_id)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (consumer, aggregate_type, aggregate_id) DO UPDATE
   SET version = EXCLUDED.version, event_id = EXCLUDED.event_id, seen_at = now()
 WHERE besdk_event_cursor.version < EXCLUDED.version
RETURNING 1;
```

- **Not partitioned, on purpose**: a partition key in the primary key would let two concurrent deliveries both insert, which is exactly the failure of today's partitioned inbox. The table stays bounded by retention: rows unseen for 30 days are deleted.
- **Local handlers** run the statement above and the business write in **one transaction**. Concurrent duplicates serialize on the row: the second waits, then finds `version` no longer smaller and skips.
- **Handlers with an external side effect** (an IM message, a call to another component) run outside any transaction; the cursor advances in a short transaction after success. A concurrent duplicate may run twice, so such a handler is idempotent on a business key (for example an idempotency key derived from the event).
- **State mode (the default):** a handler is written as "bring my projection to the aggregate's state at version v". An older version is skipped. Example: finance receives `cancelled` (v3) before `created` (v2). With nothing booked yet it records "cancelled, not booked"; `created` (v2) is then skipped. The result is right, where a cursor per subject would have booked a receivable for a cancelled order.
- **Sequence mode** (every change, in order) is reserved and not built ([13-event-contracts.md](13-event-contracts.md)).
- Two independent projections in one component that both need every version use two `consumer` names.

### Command idempotency (callee)

```sql
CREATE TABLE besdk_idempotency (
    caller          TEXT        NOT NULL,   -- user:<platform sub> | svc:<component ID> | system
    idempotency_key TEXT        NOT NULL,
    command         TEXT        NOT NULL,   -- the permission key of the command, e.g. erp.sales.confirm
    target          TEXT        NOT NULL DEFAULT '',  -- the aggregate it acts on; empty for "create"
    request_hash    BYTEA       NOT NULL,   -- SHA-256 of the request canonicalised with RFC 8785 (JCS)
    status          TEXT        NOT NULL DEFAULT 'CLAIMED',  -- CLAIMED | DONE
    result          JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,   -- created_at + 30 days
    PRIMARY KEY (caller, idempotency_key)
);
```

- **Keys are namespaced by caller.** Another caller's key is, for me, an unused key: I cannot read its result, cannot take over a key the system derives (such as one derived from an opportunity ID), and learn nothing about whether it exists.
- **Same caller, same key:** a different `command`, `target` or `request_hash` fails with `INVALID_ARGUMENT` / `IDEMPOTENCY_MISMATCH`; a claim not yet completed answers `ABORTED` / `IDEMPOTENCY_IN_PROGRESS`; a completed one returns the stored result without executing again.
- **Two-step commands** (claim, a network call, then complete) keep `CLAIMED` across the call; a step that fails for certain deletes the claim, so the same key may be retried.
- **Order of checks** in a command: validate arguments, authorize the target and the data scope, then look up or claim the key, then check the state machine, then write ([02-backend.md](../01-conventions/02-backend.md#events-and-cross-component-writes)). A replay of a "create" command is read back through the component's own scoped read; out of scope answers like a mismatch.
- **Keys are valid for 30 days**; after that the same key is a new command. The contract of every command with a key says so.
- A key used by an event handler for a downstream command is derived from the event (`crm-won:<opportunity ID>`), so a redelivery is a retry with the same key.
- `GetStatus` by key is offered by every callee of a cross-component write; after a timeout the caller asks before it compensates ([02-backend.md](../01-conventions/02-backend.md#events-and-cross-component-writes)).

### Asynchronous commands

A remote side effect required after a business change is enqueued as a `queue` job **in the same transaction** ([19-background-jobs.md](19-background-jobs.md#port-contract)), with a `unique_key` when it must happen once. It runs after commit, outside any transaction, with the job's backoff; when attempts are exhausted its dead handler marks the business row and opens an exception task, itself through a queued command. Examples: opening the "credit rejected" task, releasing a reservation after a failed confirmation, polling an IM delivery result.

### Process state and the reconciler

- The business row holds the process state, including in-flight states (`CONFIRMING`) and a `deadline_at`. Legal transitions are declared in one table in the component ([09-ai-development.md](../01-conventions/09-ai-development.md#when-to-use-a-design-pattern)).
- A **reconciler** is a declared job that, every interval, selects candidates with the component's own SQL (non-terminal and `deadline_at < now()`), claims each one, calls its handler outside any transaction, and applies the outcome in a short transaction that re-checks the state machine. Its bookkeeping lives in a side table, so business tables gain no generic columns:

```sql
CREATE TABLE besdk_reconcile (
    name        TEXT        NOT NULL,   -- the reconciler's name
    item_id     TEXT        NOT NULL,
    attempts    INT         NOT NULL DEFAULT 0,
    next_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    lease_until TIMESTAMPTZ,
    last_error  TEXT        NOT NULL DEFAULT '',
    PRIMARY KEY (name, item_id)
);
-- claim: INSERT … ON CONFLICT (name, item_id) DO UPDATE SET lease_until = now() + $lease
--        WHERE (besdk_reconcile.lease_until IS NULL OR besdk_reconcile.lease_until < now())
--          AND besdk_reconcile.next_at <= now()
--        RETURNING attempts;
```

- Reaching a terminal state deletes the side row; otherwise `attempts` grows and `next_at` follows the backoff. Past the maximum the reconciler gives up: the row goes `SUSPENDED` and an exception task is enqueued.
- Metrics: `be_reconcile_pending{name}`, `be_reconcile_oldest_age_seconds{name}`, `be_reconcile_giveups_total{name}`. Together they answer "how many flows are stuck, and since when".
- Current and planned users: sales' `CONFIRMING`, hold and release flags; inventory's sweep of expired reservations; finance's credit checks waiting for a customer snapshot; the IM adapter's delivery polling; infra/workflow's overdue scan; iam's webhook delivery.

### Holds with expiry

A resource reserved by a try step carries an expiry chosen by the caller, so a caller that disappears never holds it forever; the confirm step clears the expiry. inventory's reservations follow this: `hold_seconds` on reserve (sales asks 900 s, inventory caps at 3,600 s), `HoldReservation` as the confirm, a sweep that releases expired holds and publishes an expiry event. A reservation without an expiry (older callers) is listed for people to review, never released automatically.

### Read-your-writes

1. **Within one component:** a command's response carries the new state and `version`; the page updates from the response without re-reading.
2. **Derived views in another component** (the receivables ledger after confirming an order, an opportunity's order number, notifications) are eventually consistent. A derived view's `List` and `Get` may return `X-Data-As-Of`: the `occurred_at` of the newest event that projection has processed ([15-user-api-and-errors.md](15-user-api-and-errors.md)). When the user has just written and the view is older, the frontend shows "syncing" and re-reads, for up to 10 s. Each consumer exports `be_consumer_lag_seconds{subject}`.
3. **A value that must be current** (available stock right after confirming) is asked of its owner synchronously, never read from a projection.
4. The authorization provider's consistency token is the same mechanism for permissions ([20-authorization-provider.md](20-authorization-provider.md)).

## Alternatives

| | Model | Extra service | Fit with this project (one machine first, a schema per component, shells, languages chosen per component) | What we take from it |
|---|---|---|---|---|
| Seata | AT (undo log plus global lock), TCC, saga state machine, XA | a Java coordinator | AT proxies the data source and rewrites SQL, against static SQL without an ORM; global locks bring single-database contention across components | TCC's three anomalies: empty rollback, idempotency, suspension (covered by `GetStatus`, keys and hold expiry) |
| Temporal / Cadence | workflow as deterministic code, replayed from history | a server cluster plus its database | runs on one machine but is another stateful service to operate and back up; determinism is an invisible trap for code written by AI | durable timers, retry policy per step, per-instance history |
| DBOS | durable workflows as a library, checkpoints in PostgreSQL | none | the closest fit; whether its tables can live in a component's schema and share our transactions must be verified | first candidate if an engine is ever needed |
| Restate | journaled durable execution | a single-binary server | another resident service | — |
| Dapr | sidecar with pub/sub, state and workflow | a sidecar per application | a shell merges members into one process with one app ID; a sidecar runs against "no gateway, no mesh" | the pub/sub abstraction is our bus port; the CloudEvents envelope |
| Axon | event sourcing, sagas, deadline manager | Axon Server (optional) | Java only | deadlines as a first-class part of a saga |
| Eventuate Tram | transactional outbox, consumer deduplication table, orchestrated sagas over messages | a CDC service (optional) | the closest to our mechanism | `received_messages` ≈ our cursor; saga instance ≈ our business row; command channel ≈ our queued commands |
| Two-phase commit (XA) | one global transaction | a transaction manager | blocks on coordinator failure; locks held across components | — |

## Why this choice

- **No new resident service**, and nothing in it depends on the language a component is written in: tables, statements and rules.
- **Merge-safe.** Every table is in the member's own schema; a component behaves the same standalone and in a shell.
- **Readable state.** After a crash the world is "an order stuck in `CONFIRMING` since 10:02", visible to the user, the operator and an AI, and moved on by one reconciler.
- **Failure has an owner at every layer**: the bus redelivers, the queue retries, the reconciler drives, a person receives a task. Nothing is "best effort".

## Why not the others

- **Seata AT** rewrites SQL and holds global locks; it contradicts static SQL and per-component schemas.
- **Temporal** adds a cluster and a determinism discipline for the sake of flows we do not have yet.
- **Dapr**'s sidecar conflicts with shells and with the no-mesh direction.
- **A generic saga engine or DSL of our own** has no second orchestration shape to justify it; the reusable part (durable timers, leases, retries, idempotent commands, escalation) is already in the jobs and reconciler contracts.
- **Two-phase commit** blocks every participant when the coordinator fails and keeps locks across components for the length of the slowest one.

## When to switch

A workflow engine is evaluated when one flow appears that spans at least three components and at least five steps, includes human waits measured in days, and needs per-instance history or migration of running instances to a new version (procure-to-pay, project milestone billing). Evaluate DBOS first (a library, native PostgreSQL, one machine), then Temporal (accepting a cluster to operate).

## How to switch

An engine replaces the **driver** only: the reconciler and the queued commands that move a flow. The business state tables, `GetStatus`, the events and every other component's contract stay as they are, because the process lives in the component that starts it and is visible only through them. The switch is one component at a time, starting with the one whose flow triggered it.

## Conformance tests

Planned suites `tools/be-acceptance/conformance/bus/` (cursor cases) and `tools/be-acceptance/conformance/jobs/` (queue and reconciler cases); component cases are written red before the sweep.

- Two subjects of one aggregate share one cursor: `cancelled` (v3) then `created` (v2) leaves "cancelled, not booked".
- An old version and a duplicate return no row from the cursor statement; concurrent duplicates run the business write once.
- Reconciler: two replicas handle one item once; a failing handler backs off and gives up at the maximum; a crash between handler and apply resumes on the next round.
- Queued command: rolled back with the business transaction; enqueued twice with one `unique_key`, executed once.
- Idempotency: replay returns the first result; a changed command, target or body fails with `IDEMPOTENCY_MISMATCH`; two callers with one key are independent; system and user namespaces are separate; concurrent first use executes once; an in-progress claim answers `IDEMPOTENCY_IN_PROGRESS`; a released claim can be retried; an expired key is new.
- **Property test template, one per consumer** ([06-testing.md](../01-conventions/06-testing.md#l2-business-rule-tests)): any shuffle with duplicates of a set of events ends in the same state as delivering them once, in order.
- erp/finance: `cancelled` arriving before `created` books no receivable.
- erp/sales: with infra/workflow unavailable, the "credit rejected" exception task exists once it recovers (red today: lost); a compensation interrupted by a restart continues (red today: it lived in a sleeping request).
- erp/sales and crm/opportunity: a user who sends a key the system derives does not affect the system's command; another caller's seed key returns nothing of theirs.

## Decision records

- [0101 Components never import each other](../02-decisions/01-architecture/0101-no-imports-between-components.md) and [0102 One database, one schema per component](../02-decisions/01-architecture/0102-one-schema-per-component.md): consistency is reached over the wire, with state in each component's own schema.
- [0501 No network call inside a transaction](../02-decisions/05-runtime/0501-no-network-inside-a-transaction.md): a remote side effect after commit goes through a queued command.
- [0505 CloudEvents envelope; one cursor per aggregate stream](../02-decisions/05-runtime/0505-cloudevents-envelope-and-aggregate-cursor.md): the consumer cursor is keyed by aggregate stream.
- [0506 At-least-once delivery; streams by first subject segment](../02-decisions/05-runtime/0506-at-least-once-delivery-and-streams.md): events are delivered at least once.
- [0507 Idempotency keys are namespaced by caller](../02-decisions/05-runtime/0507-idempotency-keys-namespaced-by-caller.md): idempotency keys are namespaced by caller.
- [0508 Background work runs only through the SDK's Jobs](../02-decisions/05-runtime/0508-background-work-only-through-jobs.md): queued commands and reconcilers run through the SDK's Jobs.
- [0302 Contracts change by adding only](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md): new process states (such as `CONFIRMING`) are additions to an enum.
- Planned, not yet numbered: "a process lives in the component that starts it, and its state is the business row"; "bounded tables without partitions" (the cursor, idempotency, reconcile and job tables, bounded by retention).

## Known limits

- **Sequence mode is not built**; a consumer that needs every change in order has to wait for it.
- **Cross-component views are only eventually consistent**; the frontend has to show "syncing".
- **Side-effecting handlers and reconciler handlers run at least once**; their idempotency on a business key is the component's responsibility.
- **A key reused after 30 days is a new command.** Confirm and cancel are stopped by the state machine; a "create" creates again.
- **Holds without an expiry**, from callers that do not pass one, are not released automatically.
