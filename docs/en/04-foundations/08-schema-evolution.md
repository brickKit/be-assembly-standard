[English](08-schema-evolution.md) · [中文](../../zh/04-foundations/08-schema-evolution.md)

# Schema evolution

How a component's tables change over time: the migration tools, the guards around a migration run, what a migration file may contain, how two versions of one component share a schema, how large backfills run, why production only rolls forward, and the one-time baseline rebuild for 3.0.0. Read it before writing a migration that alters an existing table, before changing an SDK's migration entry, or before proposing another migration tool.

## Scope

- **In:** the migration tool per language; the migration entry every component exposes; its timeouts, retries and blocker report; the forbidden statements; the platform migration the SDK runs after the component's own; expand and contract, with the file-header markers; coexisting versions; backfills; rollback; baselines, including the 3.0.0 rebuild.
- **Out:** how contracts (APIs, events) evolve: [0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md), [13-event-contracts.md](13-event-contracts.md#evolution), [15-user-api-and-errors.md](15-user-api-and-errors.md). Partition windows, retention and frozen data: [09-data-lifecycle.md](09-data-lifecycle.md). Who the database identity is: [03-database.md](03-database.md). Writing a migration day to day: [02-backend.md](../01-conventions/02-backend.md#database).

## Choice

- **Plain SQL files, one tool per language**: golang-migrate (Go), yoyo-migrations (Python), node-pg-migrate (TypeScript). The tool's state table lives in the component's own schema.
- **A migration runs from the component's own image**, through `migration.command` in `component.yaml`, before the service starts and on every `brickkit up` (a Kubernetes Job before the Deployment). It must therefore be idempotent.
- **The SDK's migration entry adds guards**: short lock waits with retries, a long statement limit, and a report naming whoever blocks it.
- **After the component's migrations the SDK runs its platform migration**: the `besdk_*` tables, the current partition window, the event streams and durables.
- **Change by expand and contract.** Additive changes may ship at any time; destructive changes are declared in the file header and ship only after every older version is gone.
- **A column is never renamed and never changes meaning**, the same rule as for contracts.
- **Large backfills run as resumable SDK jobs**, never inside a migration.
- **Production only rolls forward.** `down` files exist for development and tests.
- **3.0.0 is a one-time exception**: every component replaces its released migrations with a new baseline, because no production data exists anywhere yet. Afterwards released migration files are frozen again.

**Status**: decided. The guards, the markers, the platform migration and the rebuilt baselines land with the 3.0.0 sweep; the gate for contract migrations and the migration lint come later. Today golang-migrate and yoyo are in place and every migration runs twice idempotently in tests, but a migration has no lock timeout, there is no expand/contract rule, and backfills are written by hand.

## Port contract

### The migration entry

| Item | Contract |
|---|---|
| Command | the image's `migration.command`; for the official SDKs one binary with a subcommand, `[./component, migrate, up]` |
| Connection | logs in as the owner `PG_OWNER_USER` (password `PG_OWNER_PASSWORD`), straight to PostgreSQL: `PG_MIGRATION_HOST` / `PG_MIGRATION_PORT` when set, so a transaction-mode pooler is bypassed ([03](03-database.md#configuration-keys)). The runtime role `PG_USER` has DML only and cannot run DDL ([03](03-database.md#roles)) |
| Session settings | `lock_timeout = 5s`, `statement_timeout = 15min`. The migration connection is a dedicated, unpooled session, closed after use: session-level settings, the tool's session-level `search_path` and its session-level advisory lock are allowed on it, the one exception to "nothing at session level" ([03](03-database.md#what-every-transaction-does)). The migration lock is per schema: two components migrating one database at once both succeed |
| Lock wait | on a lock timeout, back off and retry three times; then fail naming the migration, the lock waited for, and the blocker's pid and the first 200 characters of its SQL |
| State table | in the component's schema; its name is the tool's (`schema_migrations_<PG_SCHEMA>`, the `_yoyo_*` tables, `pgmigrations_<PG_SCHEMA>`, listed in be-protocol P11). The official SDKs' state tables are exempt from the `lifecycle.yaml` declaration below; a runtime that is not an official SDK declares its tool's state tables as `class: platform` |
| Database newer than the image | the migration entry logs a warning and exits 0, so brickKit's multi-version chain (lower versions first, then higher, on every `up`) works; the **service** entry refuses to start |
| Exit code | 0 on success, non-zero on any failure |

### What a migration file may contain

- **Forbidden**: `OWNER TO`, `GRANT`, `REVOKE`, `CREATE SCHEMA`, `CREATE ROLE`, `ALTER ROLE`, any `SET`, schema-qualified names, any role or schema name literal, and child partitions with date literals. Names resolve through the `search_path` the SDK sets. The planned `migration-identity-scan` fails on each of these.
- **Required shapes from 3.0.0**: own primary keys are `uuid` (UUIDv7, generated by the application, [04](04-identifiers-and-numbering.md)), except a strictly monotonic counter (`BIGINT GENERATED ALWAYS AS IDENTITY`) and a reference table keyed by a standard code; money, price and rate columns at the precisions of [06](06-money-quantity-units.md), each amount paired with a currency; `legal_entity_id` on transaction documents ([07](07-tenancy.md)); business dates as `DATE` ([05](05-time-and-calendars.md)). `BIGSERIAL` primary keys and `NUMERIC(18,2)` money columns fail the same scan.
- **Partitioned tables**: a migration creates only the parent (`CREATE TABLE … PARTITION BY RANGE (…)`); the SDK creates the partitions from `lifecycle.yaml` ([09](09-data-lifecycle.md)).
- **No platform tables**: a component never creates or touches a `besdk_*` table (planned `platform-table-scan`).
- **Every table is declared** in `migrations/lifecycle.yaml` (planned `lifecycle-scan`); the `besdk_*` tables and the official migration state tables are exempt.
- **No test accounts** ([0303](../02-decisions/03-contracts-and-data/0303-no-test-accounts-in-migrations.md)).

### The platform migration

Run by the SDK right after the component's migrations, in the same migration step and as the owner, in this order, each step idempotent:

1. create or upgrade the `besdk_*` tables and the platform functions (the `SECURITY DEFINER` functions through which the runtime role maintains partitions, [09](09-data-lifecycle.md)) to the reference DDL in the protocol's `ddl/`, recording the level in `besdk_platform_version` ([02](02-languages-and-component-protocol.md));
2. create the current partition window from `lifecycle.yaml`, so the component can write on the day it is installed;
3. ensure the event streams and this component's durable consumers exist ([12](12-event-bus.md)).

Platform tables evolve by expand and contract as well: the same component may run on two SDK versions at once, standalone beside a shell, against one schema ([01](01-ports-and-adapters.md#versions)).

### Expand and contract

| Change | Class | How it ships |
|---|---|---|
| add a table | expand | any time |
| add a nullable column, or one with a constant default | expand | any time |
| add an index | expand | `CREATE INDEX CONCURRENTLY`, alone in its own file marked `-- be:no-transaction` |
| add a constraint | expand | `ADD CONSTRAINT … NOT VALID`; `VALIDATE CONSTRAINT` in a later file |
| make a column `NOT NULL` | expand, then contract | add it nullable; backfill; set `NOT NULL` in a contract file |
| drop a column or a table; change a type | contract | header `-- be:contract after=<version>` |
| rename a column; change what a column means | never | add a new column, move readers and writers, then drop the old one by contract |

A contract file starts with its marker, naming the last version that still needs the old shape:

```sql
-- be:contract after=3.2.0
ALTER TABLE sales_orders DROP COLUMN legacy_note;
```

```sql
-- be:no-transaction
CREATE INDEX CONCURRENTLY sales_orders_customer_idx ON sales_orders (customer_id);
```

**The rule**: a contract migration ships only when no version at or below `after` still runs against the schema. The planned `contract-migration-scan` reads `brickkit.yaml`, where coexisting versions are listed, and fails while any of them is at or below `after`.

### Coexisting versions

Two versions of one component meet one schema in three ways:

| When | Who runs on the newer schema |
|---|---|
| brickKit's multi-version chain | both versions migrate on every `up`, the lower first; the older entry finds a newer database and does nothing |
| a rolling update on Kubernetes | old Pods keep serving after the migration Job has run |
| a shell and a standalone run side by side | the same component on two SDK versions, sharing platform tables |

So version N's code must run correctly on version N+1's schema. Expand guarantees it; contract waits until N is gone.

### Backfills

- **Declared as a job**: a name, a batch statement (or function) and a cursor column. It runs as a `singleton` job ([19](19-background-jobs.md)), one batch per transaction, with progress in the platform table `besdk_backfill (name PRIMARY KEY, cursor, done, updated_at)`. A crash resumes from the cursor; two replicas never run it twice; once `done`, it never runs again.
- **Reads handle both shapes** until the backfill is done; the release after it ships the contract migration.
- **Migrations backfill only bounded reference data.** A planned check uses the classes in `lifecycle.yaml` to tell bounded tables from large ones.

### Rollback

- **Forward only in production.** A fix is a new migration.
- **`down` files** serve `make db-reset` and the L4 rule that a migration is run down and up at least once ([06-testing.md](../01-conventions/06-testing.md#l4-integration-tests)).
- **Rolling the application back** to the previous image works because the previous version runs on the expanded schema.
- **Deleted or corrupted data** is recovered by point-in-time recovery, an operations procedure (the operations documents are not written yet).

### Baselines and the 3.0.0 rebuild

- **Normally, a released migration file is frozen**: never edited except for changes with no effect; there is no squashing; a new install runs every file from the first.
- **3.0.0, once**: each component deletes its migrations and writes a new `0001_init` with the shapes above, without platform tables; mdm/org and mdm/currency start on such a baseline. The demo and test databases are recreated (`make db-reset` per component, `make test-db-init`) and reseeded.
- **The criteria**, recorded in a decision: no production data exists in any installation; it happens once; a later case needs a new decision of its own.

## Alternatives

| Tool or method | What it does | Strengths | Weaknesses |
|---|---|---|---|
| golang-migrate, yoyo, node-pg-migrate (chosen) | ordered plain SQL files, a state table | simple; any reader, human or AI, can review SQL | no built-in safety lint; no expand/contract support |
| goose | SQL or Go-function migrations, `-- +goose NO TRANSACTION` | handles `CONCURRENTLY` cleanly | Go functions would make migrations code |
| Atlas | declarative schema plus diff, migration lint | detects destructive changes | generated DDL is reviewed after the fact; some features are commercial |
| Flyway, Liquibase | versioned SQL (Flyway) or changesets (Liquibase) | mature, many databases | a JVM in every migration image; Liquibase's changesets are not plain SQL |
| pgroll, Reshape | zero-downtime expand/contract through versioned schemas and views | automates the dual-shape period | create schemas and switch `search_path`, which conflicts with one schema per component and the per-transaction `search_path` |
| Squawk | lints PostgreSQL migrations for unsafe operations | catches `NOT NULL` without default, non-concurrent indexes, missing lock timeouts | a lint only; complements a tool |
| Expand/contract (parallel change) | add, migrate readers and writers, remove later | the mainstream practice (Stripe, GitHub) | needs discipline and a gate |

## Why this choice

- **Plain SQL is readable by everyone**, which matters most when an AI writes and a person reviews; one tool per language keeps one way of doing it ([0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md)).
- **Coexisting versions are native to brickKit**, so the check for "is the old version gone" belongs where brickKit lists the versions: `brickkit.yaml`.
- **The lock guard stops the classic outage**: an `ALTER TABLE` that is fast in itself queues behind a long transaction for its exclusive lock, and every later query queues behind it.
- **Backfills as jobs** keep migrations short, which matters because a failed Kubernetes migration Job (`backoffLimit: 0`) stops the deployment until the next `up`.

## Why not the others

- **goose**: Go-function migrations break "migrations are plain SQL" and would not exist in Python or TypeScript; its no-transaction marker is the idea we borrow.
- **Atlas**: declarative diffs produce DDL nobody wrote; the lint idea is borrowed as Squawk-class checks instead.
- **Flyway and Liquibase**: a JVM inside every Go, Python and TypeScript migration image, for no capability the plain tools lack.
- **pgroll and Reshape**: versioned schemas break one schema per component ([0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)) and the SDK's `SET LOCAL search_path`.

## When to switch

- **Reviews miss unsafe DDL**, recorded as incidents: add a declarative lint (Atlas lint or similar) beside the tools, not instead of them.
- **A tool is abandoned or blocks a needed feature**: change that language's cell in 0103, for every component of the language at once.
- **A table too large for expand/contract** (a rewrite would take hours even concurrently): evaluate a versioned-schema tool, which needs a revised 0102 first.

## How to switch

- **Another tool within one language**: an SDK release. Component files stay plain SQL; the SDK copies the old state table's version into the new tool's table once; the 0103 cell changes.
- **Turning on the contract gate or the lint**: a `make gates` change; components change nothing until they write a contract migration.
- This is not a port with adapters: there is one tool per language.

## Conformance tests

- **Component protocol suite** ([02](02-languages-and-component-protocol.md)): migrating twice exits 0 both times; on a fresh database the component can write the moment migration ends; every `besdk_*` table matches the reference DDL column by column; with a random schema and roles every table is owned by `PG_OWNER_USER`, `PG_USER` holds `SELECT, INSERT, UPDATE, DELETE` on each and cannot create a table, and nothing exists outside the schema.
- **SDK, red first**: a migration blocked by a long transaction retries after `lock_timeout` and finally fails naming the blocker; a `-- be:no-transaction` file with `CREATE INDEX CONCURRENTLY` succeeds (reproduce first in each tool: golang-migrate runs a multi-statement file as one implicit transaction); an older version's `up` on a newer schema does nothing; a backfill resumes after a crash, runs once across two replicas, and never runs again after `done`.
- **be-acceptance**: `migration-identity-scan` fails on each forbidden statement, on `BIGSERIAL` keys and on `NUMERIC(18,2)` money; later, `contract-migration-scan` fails while an older version at or below `after` coexists and passes once it is retired, and the lint fails on `NOT NULL` without a default.
- **Component L4**: the previous release's image writes successfully to the schema after this release's expand migrations.

## Decision records

- [0305 The 3.0.0 rebuild may replace released migrations, once, with no compatibility layers](../02-decisions/03-contracts-and-data/0305-one-shot-baseline-rebuild-for-3-0-0.md): the baseline rebuild and its criteria.
- [0306 Own keys are UUIDv7; document numbers come from the SDK](../02-decisions/03-contracts-and-data/0306-uuidv7-own-keys.md): the key shape every new baseline uses, and its two exceptions.
- [0302 Contracts change by adding only](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md): the schema follows the same rule; contract migrations are the controlled exception.
- [0102 One database, one schema per component](../02-decisions/01-architecture/0102-one-schema-per-component.md): the state table lives in the component's schema; versioned-schema tools are ruled out.
- [0103 One locked stack inside each language](../02-decisions/01-architecture/0103-locked-stack-per-language.md): the migration tool is one cell per language, node-pg-migrate for TypeScript.
- [0508 Background work runs only through the SDK's Jobs](../02-decisions/05-runtime/0508-background-work-only-through-jobs.md): backfills are jobs.
- [0303 No test accounts in migrations](../02-decisions/03-contracts-and-data/0303-no-test-accounts-in-migrations.md).
- Planned, not yet numbered: "schemas change by expand and contract, guarded by the coexisting versions in `brickkit.yaml`; production rolls forward only".

## Known limits

- **The contract gate and the lint are not built yet.** Until they are, a reviewer checks that a contract migration's `after` version is retired everywhere.
- **`CONCURRENTLY` under each tool is unverified** until the reproduction has run.
- **No long work in a migration**: on Kubernetes a failed migration Job stops the deployment until the next `up`.
- **Forward only means data mistakes need point-in-time recovery**; `down` files never run in production.
- **The 3.0.0 rebuild discards migration history**: a 2.x database cannot be upgraded in place to 3.0.0; it is recreated.
