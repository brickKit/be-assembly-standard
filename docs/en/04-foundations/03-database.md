[English](03-database.md) · [中文](../../zh/04-foundations/03-database.md)

# Database

Which database engine the project runs on, what "the database is replaceable" means exactly, how each component is isolated inside the one database, and how connections are pooled and bounded. Read it before changing the SDK's database layer, a shell's pool, `be-ops`'s generated database script or `infra/postgres`, or before promising a customer a particular database.

## Scope

This document covers the engine and its version promise, compatible distributions, the dialect layer in the SDK, schema and role isolation, the database identity a component takes from configuration, pools and the per-member bulkhead in a shell, connection poolers, role-level guardrails, and pointers for high availability and backup. It leaves to other documents:

- what happens inside one transaction (isolation, timeouts, retries, lock order, advisory locks): [10-local-transactions.md](10-local-transactions.md);
- migrations, expand/contract and coexisting versions: the schema evolution document (planned, file 08);
- partitions, retention and frozen data: the data lifecycle document (planned, file 09);
- primary keys and document numbers: [04-identifiers-and-numbering.md](04-identifiers-and-numbering.md);
- how a component uses the database day to day: [02-backend.md](../01-conventions/02-backend.md#database) and [04-configuration.md](../01-conventions/04-configuration.md#database-roles).

## Choice

- **The PostgreSQL dialect family.** PostgreSQL 14 or later is supported; 16 or later is required once shells use NOINHERIT grants. The base resources run `postgres:16-alpine`.
- **"Replaceable" means another engine that speaks the PostgreSQL wire protocol and passes the database suite.** There is no multi-dialect abstraction in the SDK. The mechanisms every component needs (role switching, partitions, queue claims, advisory locks, error classification, platform tables) live once, in the SDK's PostgreSQL dialect layer; business SQL stays in each component's repository layer.
- **One database, one schema and one role per component** ([0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)).
- **The identity comes from configuration only.** The role is `PG_USER`, the schema is `PG_SCHEMA`; both are required, neither has a default, and neither is derived from the other. Migrations contain no role or schema names.
- **Every access goes through the SDK's store handle**, which switches role and `search_path` inside each transaction. The outbox pump, consumers and lifecycle jobs go through it as well, so a shell's login role needs no privileges of its own.
- **Pools are bounded**, and in a shell every member has its own budget inside the shared pool.
- **Migration role and runtime role are separate**: the runtime role can read and write rows but cannot drop a table.
- **A connection pooler is optional**; when used, it runs in transaction mode and migrations bypass it.
- **Out-of-band services** (Casdoor, Keycloak) connect with roles of their own, never as a superuser.

**Status**: PostgreSQL 16, schema-and-role isolation and transaction-scoped switching are in place. The identity taken only from `PG_USER` is in place in three components (iam, sales, opportunity); the store handle, bounded pools, the per-member bulkhead, role guardrails, the role split, NOINHERIT grants, separate roles for Casdoor and Keycloak, and the database suite are decided and land with the 3.0.0 sweep.

## Port contract

The engine port is "the PostgreSQL wire protocol plus this capability list". The SDK side of it is the configuration surface and what each transaction does.

### Configuration keys

| Key | Required | Default | Meaning |
|---|---|---|---|
| `PG_HOST`, `PG_PORT`, `PG_DATABASE` | yes | — | where the database is ([04-configuration.md](../01-conventions/04-configuration.md#shared-connection-keys)) |
| `PG_USER` | yes | none | the role every transaction switches to; standalone it is also the login role |
| `PG_PASSWORD` | yes | — | secret, `${<REPO>_DB_PASSWORD}` |
| `PG_SCHEMA` | yes | none | the schema the component owns; the only entry on its `search_path` |
| `PG_POOL_MAX` | no | 10 | standalone: the pool's maximum open connections. In a shell: this member's concurrency limit inside the shared pool |
| `PG_POOL_MIN_IDLE` | no | 2 | idle connections kept open |
| `PG_CONN_MAX_LIFETIME` | no | 30m | a connection is closed and replaced after this long, so failovers and DNS changes are picked up |
| `PG_CONN_MAX_IDLE_TIME` | no | 5m | an idle connection is closed after this long |
| `PG_POOL_ACQUIRE_TIMEOUT` | no | 5s | the longest wait for a connection; capped by the caller's remaining deadline |
| `PG_MIGRATION_HOST`, `PG_MIGRATION_PORT` | no | `PG_HOST`, `PG_PORT` | where migrations connect; set them when `PG_HOST` points at a pooler |

The optional keys are declared in each component's `configSchema`. A shell has its own `PG_POOL_MAX`: the size of its one physical pool, default the smaller of the sum of its members' `PG_POOL_MAX` and 40.

### What every transaction does

```sql
BEGIN;
SET LOCAL ROLE <PG_USER>;
SET LOCAL search_path TO <PG_SCHEMA>;
-- per-transaction timeouts: see 10-local-transactions.md
...
COMMIT;
```

Nothing is ever set at session level: a `SET` without `LOCAL` stays on the pooled connection and the next borrower runs in your schema. The session time zone is UTC and is never changed ([05-time-and-calendars.md](05-time-and-calendars.md)).

### What the SDK checks at start

- **Capabilities**: `server_version_num >= 140000`, declarative partitioning, `FOR UPDATE SKIP LOCKED`. A missing one stops the start and names the capability.
- **Identity**: inside a transaction as `PG_USER`, the role has `USAGE` and `CREATE` on `PG_SCHEMA`, and no table in the schema has another owner. A failure is logged at ERROR and exported as a metric; it does not stop the module, and it is never part of `/healthz`.
- **Shell**: when a member's configuration names a `PG_HOST`, `PG_PORT` or `PG_DATABASE` different from the shell's, the shell refuses to start and names the member and the key. Otherwise the member would silently use the shell's database.

### Capability list

| Capability | Used for |
|---|---|
| `SET LOCAL ROLE`, `SET LOCAL search_path` | per-member identity on a shared pool |
| `GRANT … WITH INHERIT FALSE, SET TRUE` (PostgreSQL 16) | a shell login role that can switch to a member's role but holds none of its privileges |
| RANGE and LIST declarative partitioning, `pg_partition_tree`, `ATTACH PARTITION` | tables that grow without bound |
| `FOR UPDATE SKIP LOCKED` | outbox, job and webhook queues |
| `pg_advisory_xact_lock` | logical locks; transaction-scoped only |
| transactional DDL, `CREATE INDEX CONCURRENTLY` | migrations |
| `INSERT … ON CONFLICT … RETURNING` | idempotency claims, upserts |
| `uuid`, `NUMERIC`, `timestamptz`, `date`, `JSONB` (opaque storage only) | column types |
| SQLSTATE 23505, 40001, 40P01, 55P03, 57014 | error classification in the SDK |

### Roles

| Role | Login | Owns | Used by |
|---|---|---|---|
| `PG_USER` | yes | the tables in `PG_SCHEMA`, because the migrations run as this role and own what they create | the component: its migrations and the running service |
| shell login role | yes | nothing | a shell; a member of every hosted `PG_USER`, NOINHERIT |
| `casdoor_rw` and similar | yes | its own schema only | an out-of-band service |

No role or schema name is derived in code or written into a migration: both come from `PG_USER` and `PG_SCHEMA`. `be-ops` generates the roles, the grants and these role-level guardrails, which act as a backstop for any session, including a forgotten tool:

```sql
ALTER ROLE <login role> SET statement_timeout = '30s';
ALTER ROLE <login role> SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE <login role> SET lock_timeout = '5s';
```

They apply to the role that logs in. After `SET ROLE` PostgreSQL does not apply the target role's settings, so inside a shell only the per-transaction values from [10-local-transactions.md](10-local-transactions.md) take effect.

### Pools and the bulkhead

- One pool per process. In a shell the pool belongs to the shell, and each member reaches it through a limit of its own `PG_POOL_MAX` concurrent connections.
- A member that has used its whole budget waits up to `PG_POOL_ACQUIRE_TIMEOUT` (or the caller's remaining deadline, if shorter) and then fails with `RESOURCE_EXHAUSTED` and the reason `DB_POOL_EXHAUSTED` ([15-user-api-and-errors.md](15-user-api-and-errors.md)), confined to that member. The other members are unaffected.
- One task holds at most one connection at a time; a nested transaction is refused ([10-local-transactions.md](10-local-transactions.md)). With bounded pools, holding two connections at once is how a pool starves itself.
- A connection budget gate in `be-ops` adds up `PG_POOL_MAX` for every process in the deploy file plus reserves for migrations, Casdoor and Keycloak, and fails when the total exceeds `max_connections - superuser_reserved_connections`.

### Poolers

- Optional. When used: transaction mode only, PgBouncer 1.21 or later with `max_prepared_statements > 0`. Otherwise turn off the statement cache in every driver.
- Runtime code takes transaction-scoped advisory locks only; a gate scans for session-level `pg_advisory_lock` calls.
- Migrations connect directly to PostgreSQL through `PG_MIGRATION_HOST` / `PG_MIGRATION_PORT`, because golang-migrate holds a session-level advisory lock. brickKit gives the migration container exactly the service's environment, so separate keys are the only way to point the two at different hosts.

## Alternatives

| Engine | Strengths | Weaknesses for us |
|---|---|---|
| **PostgreSQL 14+**, including managed services (RDS, Aurora PostgreSQL, Cloud SQL, AlloyDB, Azure Flexible Server, Alibaba Cloud RDS for PostgreSQL, PolarDB for PostgreSQL) | has every mechanism listed above; the widest ecosystem (CloudNativePG, Patroni, pgBackRest) | one writer; scale-out needs partitions, read replicas or a sharding extension |
| MySQL 8, MariaDB, TiDB, OceanBase (MySQL mode) | familiar to many operations teams; TiDB scales out | a schema is a database; no `SET LOCAL ROLE`; DDL is not transactional; partitioned tables take no foreign keys |
| CockroachDB | distributed, strongly consistent | no advisory locks, SERIALIZABLE only, different partitioning; the free core edition ended in 2024 |
| YugabyteDB (YSQL) | high PostgreSQL compatibility, Apache-2.0, multi-region | advisory locks, some DDL and partitioning must be checked one by one; heavy |
| **Citus 12+** (a PostgreSQL extension) | schema-based sharding: each schema lives whole on one worker, which is exactly what 0102 already enforces | a coordinator node; some extensions and DDL are restricted |
| KingbaseES (PostgreSQL mode), HighGo | on the Chinese domestic-software (Xinchuang) list; kernels derived from PostgreSQL | version mapping, NOINHERIT syntax and extensions must be measured |
| openGauss, GaussDB, Vastbase | on the Xinchuang list | forked from PostgreSQL 9.2: partition syntax, roles and functions differ |
| A database per component | strongest isolation | no shared pool for a shell; rejected by 0102 |
| Poolers: PgBouncer, PgCat, Supavisor, Odyssey, the CloudNativePG pooler | fewer backend connections | session state is not kept in transaction mode |

## Why this choice

- Every isolation and coordination mechanism here is native PostgreSQL: transaction-scoped role switching, declarative partitions, `SKIP LOCKED`, transaction-scoped advisory locks, transactional DDL.
- It has the widest coverage of managed services and of PostgreSQL-derived domestic distributions, so "which database will the customer allow" usually has an answer inside the family.
- Its scale-out route, Citus schema-based sharding, needs no component change, because components already never touch each other's schemas.
- Keeping the mechanisms in one SDK layer means qualifying a new engine is one suite run, not a review of every component.

## Why not the others

- **MySQL family**: no transaction-scoped role switch, so the identity model of 0102 would need a new mechanism; non-transactional DDL makes a failed migration half-applied; partitioned tables lose foreign keys; and every repository layer would be ported.
- **CockroachDB**: no advisory locks, SERIALIZABLE only (hot rows such as stock balances abort constantly), and a commercial licence.
- **openGauss and its derivatives**: the 9.2 fork differs exactly where the SDK's dialect layer lives; expected to need SDK changes, not promised.
- **A multi-dialect abstraction**: there is one real dialect today; an abstraction written before the second would be shaped by guesses ([09-ai-development.md](../01-conventions/09-ai-development.md#when-to-use-a-design-pattern)), and an ORM is ruled out by [0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md).
- **A database per component**: costs the shared pool that makes a shell one process, and later changes are data migrations ([0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)).

## When to switch

- **Writes on the single database become the bottleneck** (measured, after partitioning and read replicas): move to Citus schema-based sharding.
- **A customer mandates a Xinchuang database**: run the database suite against the candidates, read the capability matrix, choose the engine that passes.
- **One component needs a storage capability PostgreSQL lacks**, or must use another database instance: reopen 0102 for that component; it gets its own store through its own configuration, and in a shell its own pool.
- **Connection count becomes the limit** (many processes against one instance): add a pooler in transaction mode.

## How to switch

- **Another engine in the family**: point the shared `PG_*` values in `config/vars.yaml` at the new instance, run `make db-init` (the script be-ops generates) against it, run the database suite. No component change.
- **Citus**: install the extension on the coordinator and workers, enable schema-based sharding so each component schema becomes a distributed schema, run the suite. No component change.
- **A pooler**: point `PG_HOST` / `PG_PORT` at the pooler and `PG_MIGRATION_HOST` / `PG_MIGRATION_PORT` at PostgreSQL itself.
- **A managed service**: as "another engine in the family"; take the role-creation script from be-ops instead of relying on the service's default superuser.
- **Outside the family** (MySQL, CockroachDB): not a switch. It is a new dialect layer in every official SDK plus a port of each component's repository layer, planned like a project.

## Conformance tests

Suite `tools/be-acceptance/conformance/db/`, parameterised by a DSN, run against an engine to qualify it. It has three layers:

1. the SDK's transaction semantics from the store suite (`conformance/store`, listed in [10-local-transactions.md](10-local-transactions.md#conformance-tests));
2. one probe SQL per capability in the list above;
3. the L4 tests of three components with different shapes: erp/sales, erp/finance, infra/iam-casdoor.

The output is an engine-by-capability matrix with three verdicts: works, degraded, fails. The CI matrix runs PostgreSQL 14, 16 and 17, the same as the store suite (18 joins it once the SDKs are tested on it); KingbaseES, HighGo, YugabyteDB and Citus are each run once and recorded. Engine tiers today:

| Tier | Engines |
|---|---|
| supported | PostgreSQL 14 and later; managed PostgreSQL services |
| likely, to be measured | KingbaseES, HighGo; Citus 12+ as the scale-out route |
| unverified, expected to need SDK changes | openGauss, GaussDB, Vastbase; YugabyteDB |
| not supported | CockroachDB; MySQL, OceanBase (MySQL mode), DM |

Tests to write red first:

- SDK: a member that exceeds its `PG_POOL_MAX` waits and then gets `RESOURCE_EXHAUSTED` / `DB_POOL_EXHAUSTED`, while another member keeps working; the pool sets its maximum and lifetime; a shell's physical pool is the smaller of the members' sum and the shell's cap; `PG_MIGRATION_HOST` wins over `PG_HOST`; a missing `PG_USER` or `PG_SCHEMA` fails naming the key, and the role is never derived from the schema; a NOINHERIT shell login role can still run the outbox pump and consumers; a member whose `PG_HOST` differs from the shell's stops the shell.
- SDK, reproduce first: two members on one physical connection sending identical SQL text against platform tables of different shapes must not fail with "cached plan must not change result type".
- be-ops: login roles carry the three timeouts; the connection budget gate fails and lists the processes when the total exceeds `max_connections`.
- be-acceptance: a session-level advisory lock in runtime code fails the scan; a migration containing `OWNER TO`, `GRANT`, `CREATE SCHEMA`, `SET ROLE`, a qualified name or a role name fails the migration identity scan; code that derives a role from a schema name, or defaults `PG_SCHEMA` to a literal, fails the identity literal scan.
- infra: the Casdoor role is not a superuser.

## Decision records

- [0102](../02-decisions/01-architecture/0102-one-schema-per-component.md): one database, one schema and role per component. A revision is planned: Citus schema-based sharding and a separate pool per member as its reopen conditions, and the split between owner role and runtime role.
- [0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md): no ORM, hand-written SQL, so business SQL stays in each component's repository layer.
- [0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md): the database server is infrastructure, not a component.
- Planned, not yet numbered: "the database target is the PostgreSQL dialect family, qualified by the database suite".

## Known limits

- **Only the PostgreSQL family.** Leaving it means a new dialect layer in each official SDK and a port of every component's repository layer: business SQL uses `ON CONFLICT`, `RETURNING`, `ANY($1)`, intervals and `JSONB` freely.
- **The Xinchuang distributions are not measured yet**; none is promised until the suite has run against it.
- **One writer.** Scale-out goes through Citus, which is designed for, not tested.
- **Every process draws on one `max_connections`.** The budget gate keeps the sum honest; it cannot make the server bigger.
- **The statement cache on a shared pool** with members on different SDK versions is unverified: until the reproduction above has run, platform SQL names its columns and never uses `*`.
- **High availability and backup are operations** (the operations documents, `05-operations/`, are not written yet). Pointers: CloudNativePG on Kubernetes (with its pooler and point-in-time recovery); pgBackRest or WAL-G on a single machine. Point-in-time recovery is the only real undo for deleted data.
