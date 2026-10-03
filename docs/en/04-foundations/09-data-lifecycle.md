[English](09-data-lifecycle.md) · [中文](../../zh/04-foundations/09-data-lifecycle.md)

# Data lifecycle

How a component's rows age: from hot, through sealed and read-only, to frozen in open-format files in object storage, to destroyed once the law allows. Also how legal holds and erasure requests cut across all of it, and the ports that let the same components run with no cold tier, with Parquet files, or later with a lakehouse. Read it before adding a table, changing a retention period, writing a list query over a time range, or changing the SDK's lifecycle engine.

## Scope

- **In:** the tiers and the cross-cutting states; the eight table classes; the lifecycle contract `lifecycle.yaml` v1 and its deployment override; units and their state machine; the guarantees the SDK gives; the read path (default windows, `RANGE_COLD`, locate, export, thaw); the `/_lifecycle/*` resource contract; erasure across tiers; the cold format; partition windows; platform tables and their retention; the lifecycle ports and adapters; coordination with backups.
- **Out:** object storage itself, buckets and credentials ([22-object-storage.md](22-object-storage.md)); event replay ([12-event-bus.md](12-event-bus.md#replay)); migrations ([08-schema-evolution.md](08-schema-evolution.md)); fiscal calendars ([05-time-and-calendars.md](05-time-and-calendars.md)); backup and recovery procedures (operations documents, not written yet).

## Choice

- **Tiers in the same table.** Hot and warm rows stay attached to one native partitioned parent. Warm means sealed: read-only, with its digest linked into a chain. There is no `<schema>_archive` and no routing between schemas.
- **Cold data is an open format the component owns**: Parquet files plus a self-describing manifest, in the component's own bucket, with its own credential ([22](22-object-storage.md)). It can be queried through an adapter, exported, or thawed back into the database.
- **Destruction** happens only after the legal minimum has passed. Depending on the class it is automatic or reviewed (approved through a workflow task), and the destruction register is kept for ever.
- **Two states cut across the tiers**: a **legal hold** blocks destruction and erasure; **restricted processing** keeps rows the law requires while they are no longer used for anything else (PIPL article 47, GDPR article 18).
- **Every table is declared** in `migrations/lifecycle.yaml` as one of eight classes. A deployment may lengthen retention and postpone freezing, never go below what the component declares.
- **One engine per official SDK.** A pure planner produces the actions and an executor carries them out. It runs as a `singleton` job ([19](19-background-jobs.md)), takes a transaction-level advisory lock per step ([10](10-local-transactions.md)), and, because the runtime role has no DDL ([03](03-database.md#roles)), performs its run-time DDL (partitions ahead, seal guards, dropping expired platform and queue partitions) only through `SECURITY DEFINER` functions the owner creates in the platform migration. Detaching frozen business units concurrently runs in the migration step, as the owner, on its dedicated connection.
- **Infrastructure products sit behind SDK ports**, chosen by one configuration value: `Dialect`, `ColdStore`, `ColdQuery`, `DatasetPublisher`, `PiiProtector`. Components never name an adapter.
- **Partitions come from the declaration**: no date literals in migrations, and the window exists on the day a migration runs.
- **Governance is an ordinary component**, `infra/data-governance`: holds, data-subject requests, destruction approval, compliance reports. No component depends on it; without it, each component's `/_lifecycle/*` endpoints still place holds and run erasures.
- **Defaults chosen by the user**: component authors set retention from the law, deployments may lengthen it, and orders are kept 10 years as tax records. Cold data first offers "export or request a thaw", and listing straight into cold data comes later. Expired non-financial data is destroyed after review, while financial records follow the accounting-archive rules. For a natural-person customer, data is restricted during retention and anonymised after it. An electronic accounting archive package is on erp/finance's roadmap.

**Status**: decided. The whole contract is fixed at stage 0, with the 3.0.0 sweep: `lifecycle.yaml` v1, the platform tables, every `/_lifecycle/*` endpoint (unimplemented ones answer `501`), `RANGE_COLD`, `DATA_LIFECYCLE`, the `include_cold` list field. At stage 0 the engine implements the hot and warm tiers only, and the cold adapters are `none`. Later stages add adapters, never contract changes: stage 1 `s3-parquet` with freeze, verify, thaw, export and destruction review; stage 2 `scan`, the governance component and `watermark` datasets; stage 3, on demand, `iceberg`, `trino`, `debezium` and `crypto-shred`. Today twelve components carry copies of partition-maintenance code without locks, initial partitions are dated literals in migrations, the `<schema>_archive` convention still exists, and outbox and inbox tables have no contractual expiry.

## Port contract

### Tiers and states

| Tier or state | Where the rows are | Reads | Writes |
|---|---|---|---|
| hot | attached partitions inside the default window | default | normal |
| warm (sealed) | attached partitions, sealed by trigger, digest in the chain | on request (a range outside the default window) | refused: `FAILED_PRECONDITION` / `UNIT_SEALED` |
| cold | Parquet plus manifest in object storage; only the unit catalogue stays in the database | `RANGE_COLD`, or the cold query adapter, export, thaw | none |
| destroyed | gone; the register entry remains | — | — |
| legal hold (cross-cutting) | unchanged | unchanged | destruction and erasure blocked |
| restricted (cross-cutting) | unchanged | business screens and audit only; excluded from datasets and analytics | — |

### Table classes

| Class | What | Partitioned | Sealed | Cold | Expiry | Erasure default |
|---|---|---|---|---|---|---|
| `master` | mutable master data, bounded | no | no | no | kept | anonymise personal columns |
| `reference` | configuration, dictionaries, templates | no | no | no | kept | none: no personal columns (checked) |
| `document` | business documents with a state machine | by creation time, or row units | N months after closed | optional | per retention | per column: restrict or anonymise |
| `ledger` | append-only books | by time or period | immediately, or on a business signal (period locked) | optional, after a checkpoint | legal minimum, reviewed | **no personal columns allowed**, opaque subject ids only (checked) |
| `audit` | who did what, when | by time | immediately | optional | at least 6 months; default 3 years | actor id kept (restricted) |
| `queue` | work items with open states | by time | no | never | delete, but never a partition with open rows | delete |
| `snapshot` | local copies of others' data, rebuildable | any | no | never | any time | delete rows |
| `platform` | the SDK's own tables | SDK | — | never | SDK | SDK |

Invariants, checked when the declaration loads (a violation stops start-up naming it): `ledger` and `audit` rows are protected by a seal trigger from the moment their partition exists; a `ledger` column marked personal is an error; `queue` cannot be cold and `snapshot` cannot have a retention minimum; a cold table's `NUMERIC` columns all have a precision; an erasable cold table cannot use WORM storage.

### `lifecycle.yaml` v1

Beside the migrations, in the image; the SDK reads it at run time, be-ops and the gates at assembly time.

```yaml
lifecycle: v1
tenant_key: none
tables:
  sales_orders:
    class: document
    partition: {by: created_at, grain: month, ahead: 3}
    closed: {column: status, in: [COMPLETED, CANCELLED, CLOSED], at: updated_at}
    tiers: {hot: 90d, seal: 18mo after closed, cold: 5y after closed}
    retention: {min: 10y after closed, basis: "tax records, 10 years", end: review}
    erasure: {subject: customer, key: customer_id, columns: {customer_name: restrict}}
    dataset: {publish: true, exclude: [suspended_reason]}
  sales_order_items: {follows: sales_orders}
  customer_snapshots: {class: snapshot, erasure: {subject: customer, key: customer_id, action: delete}}
```

| Field | Values |
|---|---|
| `class` | one of the eight; sets defaults and invariants |
| `partition` | `{by, grain: week\|month\|year, ahead}` or `{by, kind: list, opened_by: command}`; absent = not partitioned |
| `closed` | `{column, in: [...], at: <column>}`, structured rather than SQL, so every SDK and cold adapter can evaluate it |
| `tiers.hot` / `seal` / `cold` | a duration or `none` / `immediate`, `on_signal`, `<n> after <anchor>`, `never` / `<n> after <anchor>`, `never` |
| `retention` | `min: <n> after <anchor>` or `forever`; `basis` (text, written into the destruction register); `end: keep\|destroy\|review` |
| anchors | `created`, `closed`, `sealed`, `fiscal_year_end` (the component supplies it; erp/finance from its fiscal years, others the calendar year) |
| `erasure` | `{subject, key, columns: {<col>: delete\|anonymize\|restrict}}` or `{subject, key, action: delete}` |
| `checkpoint` | a table that must hold the closing rows before the unit freezes (erp/finance `account_period_balances`) |
| `guard` | `{blocked_by: <name>}`, a named check the component implements, called before sealing or destroying |
| `follows` | same boundaries and same unit as the named table |
| `dataset` | `{publish, exclude, pseudonymize}` |
| `tenant_key` | a column name, or `none` ([07](07-tenancy.md)) |

**Deployment override**: one configuration key, `DATA_LIFECYCLE`, a YAML or JSON value in `config/vars.yaml`, with per-component additions in the component's own file:

```yaml
DATA_LIFECYCLE: |
  mode: on                 # on | dry-run | off
  cold_store: s3-parquet   # none | s3-parquet | iceberg
  cold_query: scan         # none | scan | trino
  publisher: none          # none | watermark | debezium
  pii: plain               # plain | crypto-shred
  tables: {sales_orders: {retention: {min: 15y after closed}}}
```

An override below the declared minimum stops start-up; an adapter name the SDK version does not implement stops start-up with "not supported by this SDK version". Object storage uses `S3_URL` and a per-component credential, `S3_ACCESS_KEY_ID_FILE` / `S3_SECRET_ACCESS_KEY_FILE`, limited to the component's own bucket; `LAKE_QUERY_URL` only with `trino`. One key holding a structure goes against brickKit's advice on configuration design; it is a deliberate exception, because flat keys could not express per-table overrides.

### Units and the state machine

A **unit** is one partition (with its `follows` partitions), or for an unpartitioned table the rows whose anchor falls in one month. Each step is one transaction under a step lock with `lock_timeout`, and resumes from `besdk_lifecycle_units.state` after a crash.

1. **Ensure ahead**: create partitions by boundary, never by name (an existing partition with other naming is adopted), `follows` tables in the same transaction; at migration time for the current window, then at run time for `ahead` through `besdk_ensure_range_partition` / `besdk_ensure_list_partition`. No DEFAULT partition.
2. **Seal**: lock the partition against writes (not reads); check every row is closed, or mark the unit `BLOCKED` with the reason and the first 100 ids (metric `be_lifecycle_blocked{table,reason}`); call the named guard; install the seal trigger through `besdk_seal_table` (row-level `UPDATE`/`DELETE`, statement-level `TRUNCATE`; a trigger, because privileges on a partition are not checked through its parent); link the unit's digest: `chain_n = SHA-256(chain_{n-1} ‖ unit_digest_n)`. `on_signal` seals inside the business transaction (erp/finance locking a period).
3. **Export** the still-attached sealed unit to Parquet; 4. **verify** by reading the objects back and recomputing the digest; 5. **switch reads**: mark the unit `COLD_PENDING_DROP` in one transaction, so reads get `RANGE_COLD` from then on and nothing is missed.
6. **Detach and drop**: `ALTER TABLE … DETACH PARTITION … CONCURRENTLY` in the migration step, as the owner, on its dedicated connection that never enters the pool (the statement cannot run inside a function or a transaction block; the parent needs only `SHARE UPDATE EXCLUSIVE`), then `DROP` the detached table. Row units delete in batches of 5,000. State `COLD`.
7. **Thaw**: recreate, load by column name (dropped columns ignored, new ones defaulted), add the boundary `CHECK`, recheck the digest, seal, attach; state `THAWED until <time>`; refreeze when it expires without exporting again.
8. **Destroy**: only units past `retention.min`, without a hold, with guards passing. `end: destroy` runs it; `end: review` produces a destruction list for approval. Every destruction is written to `besdk_lifecycle_log`, kept for ever.
9. **Expire** (`queue`, `platform`): delete partitions once no open row remains, without a cold tier, at run time through `besdk_drop_partition` (a plain `DETACH` under a short `lock_timeout`, then `DROP`).

### Guarantees

| # | The SDK guarantees |
|---|---|
| G1 | a migration run on any date leaves the component able to write that day; the window always covers `ahead` |
| G2 | one executor per schema and step at a time; different schemas never block each other; no DDL waits in the hot path |
| G3 | nothing is deleted before `retention.min` |
| G4 | `document`, `ledger` and `audit` rows never leave the database without a verified cold copy; with `cold_store: none` they stay warm |
| G5 | sealed units refuse `UPDATE`, `DELETE`, `TRUNCATE` (`UNIT_SEALED`) |
| G6 | the digest chain can be verified at any time; any change to a sealed unit is detected |
| G7 | a read over a time range returns everything or `RANGE_COLD`; never a silent truncation |
| G8 | cold reads apply the same data-scope predicate as hot reads; an adapter that cannot express it refuses |
| G9 | held data is never destroyed or erased |
| G10 | an erasure reaches every tier, dataset and later thaw, leaves a receipt, and is replayed after a point-in-time recovery |
| G11 | every action is logged and published as an event |
| G12 | every official SDK's planner produces identical actions from the shared vectors |

### Reading

- **Default window**: a list without a range reads the `hot` window; `master` and `reference` have none.
- **`RANGE_COLD`**: `FAILED_PRECONDITION`, HTTP 400, reason `RANGE_COLD`, `metadata` `online_from`, `cold_ranges`, `thaw_allowed`, `export_allowed` ([15](15-user-api-and-errors.md)). Every list request gains the optional field `include_cold` (default false), added once in the 3.0.0 contracts; with a cold query adapter, `include_cold: true` continues into cold data, and the cursor carries the tier, so paging crosses from hot to cold unseen.
- **By id**: BatchGet reads the table as before. To tell "does not exist" from "frozen", the SDK locates the unit from the UUIDv7 time bits ([04](04-identifiers-and-numbering.md)), with no cold index.

### Resource contract

Every component with a database mounts `/{domain}/{name}/_lifecycle/*` (OpenAPI in `be-protocol`, gRPC `be.lifecycle.v1`): `GET units?table=`, `POST units/{table}/{unit}:thaw {days}`, `POST exports {table, from, to, filter, format: parquet|csv}` (asynchronous; the result is a short-lived presigned URL under the component's `exports/` prefix), `GET verify`, `holds`, `erasures`, `destructions`. An endpoint not implemented yet answers `501` `CAPABILITY_UNAVAILABLE`. Permission keys, generated by be-ops: `<id>.lifecycle.read` (export, view units), `<id>.lifecycle.thaw`, `<id>.lifecycle.admin` (holds, erasure, destruction).

### The cold format

- Layout, inside the component's bucket ([22](22-object-storage.md#key-layout)): `cold/<table>/v<dataset version>/unit=<YYYY-MM>/tenant=<t>/part-NNNN.parquet` and `cold/<table>/_manifests/<unit>.json` (row count, digest, schema version, basis). Row groups of about 128 MB. Object keys include the content digest, so a repeated export overwrites idempotently.
- **Canonical digest**: each value in PostgreSQL's text output form (`\N` for null), fields separated by `0x1F`, rows by `0x1E`, rows in primary-key order, SHA-256 per unit. It is computed from PostgreSQL on export, from Parquet on verify and from the database again on thaw, and all three must match. Any third-party tool can recompute it.

### Erasure

- **Subjects** are listed in `registry/data-subjects.tsv` (append-only): `customer`, `contact`, `user`, `supplier`, `employee`, each with its owning component.
- **Flow**: `infra.governance.erasure.requested.v1 {request_id, subject, subject_id}` (or the component's own endpoint) → every component declaring that subject applies `delete`, `anonymize` (a stable pseudonym per subject, so reports still group) or `restrict`, per table and column, in one transaction → receipt `<domain>.<name>.lifecycle.erasure_completed.v1 {request_id, tables: [{table, action, rows, basis}]}`.
- **Cold tier**: `s3-parquet` rewrites affected files and issues a new manifest; `iceberg` writes delete files. The erasure ledger `besdk_erasures` stores opaque ids only and is mirrored, append-only, to the `_erasures/` prefix.
- **Known lag**: events may carry personal data for up to the outbox's 14 days plus the stream's 7; dead letters keep 30 days and are not rewritten. `crypto-shred` (stage 3) removes the lag by deleting a per-subject key.

### Partition windows and platform tables

- Boundaries are anchored in UTC (weeks from Monday 00:00, months from the 1st); names `<table>_YYYY_MM_DD`; the existence check reads boundaries from the catalogue; a partial overlap is skipped with a warning.
- erp/finance's list partitions per accounting period are created by its open-fiscal-year command through the SDK, never by a yearly migration ([05](05-time-and-calendars.md)).
- Platform retention: `besdk_outbox`, weekly partitions, dropped 14 days after every row is published; `besdk_event_cursor` and `besdk_idempotency`, rows older than 30 days deleted; `besdk_lifecycle_log`, kept for ever.
- Lifecycle tables: `besdk_lifecycle_units` (unit, bounds, state, rows, min and max id, unit and chain digests, manifest, times, blocked reason), `besdk_lifecycle_log` (append-only, sealed), `besdk_holds`, `besdk_erasures`, `besdk_exports`; reference DDL in `be-protocol`.

### Ports and adapters

| Port | Adapter | Stage | Fits |
|---|---|---|---|
| `Dialect` | `pg-native` | 0 | PostgreSQL 14+, managed PostgreSQL, compatible engines ([03](03-database.md)) |
| | `opengauss`, `kingbase` | on demand | domestic-database deliveries, once measured |
| `ColdStore` | `none` | 0 | small customers without object storage; also proves the degraded path |
| | `s3-parquet` | 1 | the default |
| | `iceberg` | 3 | a customer with a lakehouse, or zero-copy to Snowflake, Databricks, Doris; same data files as `s3-parquet` |
| `ColdQuery` | `none` | 0 | cold data only through export and thaw |
| | `scan` | 2 | the default: reads Parquet in-process with row-group pruning, only the component's own bucket |
| | `trino` | 3 | heavy historical querying, aggregates |
| `DatasetPublisher` | `none`, `watermark`, `debezium` | 0, 2, 3 | analytics (`ana/*`) reads published datasets, never business schemas |
| `PiiProtector` | `plain`, `crypto-shred` | 0, 3 | personal-data-heavy components such as future `hrm/*` |

Lifecycle events, through the outbox: `<domain>.<name>.lifecycle.sealed|frozen|thawed|destroyed|erasure_completed.v1`.

### Backups

After a point-in-time recovery the engine reconciles: a unit whose manifest matches is treated as verified and not exported again; objects with no matching unit are marked orphaned and deleted once older than the recovery window; erasures missing from the database are replayed from the `_erasures/` mirror. Object-storage retention must exceed the recovery window.

## Alternatives

| Option | Strengths | Weaknesses |
|---|---|---|
| Native partitions in one table, plus an open-format cold tier (chosen) | one schema, one read path; any engine reads the cold tier; a database switch moves only hot and warm | the engine, state machine and adapters are ours to build |
| An archive schema per component (the old convention) | cold rows still queryable by SQL | two schemas, DDL drift, routing, no space saved |
| pg_partman | mature; available on managed PostgreSQL | configuration outside the component's schema; a privileged background worker; its retention bypasses our guards |
| TimescaleDB | 90 %+ compression on append-only tables; continuous aggregates | TSL licence; few managed offerings; converting is a migration; compressed chunks are costly to erase |
| Citus columnar | warm-tier compression; schema sharding matches one schema per component | an extension dependency; append-only |
| Apache Iceberg as the only cold format | the open table standard; cheap row deletes | needs a catalogue service; Go writers are young |
| PostgreSQL lake extensions (pg_duckdb, pg_lake, parquet_s3_fdw) | one SQL over hot and cold | privileged extensions, rare on managed services; isolation left to the extension |
| Full-table CDC into an analytics store | real time, captures deletes | reads other components' schemas physically; no contract |
| Soft delete or an `active` flag (Odoo) | trivial | a recycle bin, not a lifecycle; no legal retention |

Mainstream products shaped the contract: SAP's archiving objects, archivability checks, residence versus retention and legal cases; SAP Data Aging's "current by default"; Salesforce Archive's searchable, restorable archive; ERPNext's per-field anonymisation; Dynamics 365's read-only long-term retention.

## Why this choice

- **One schema and one read path** per component: SAP Data Aging uses the same shape, and no mainstream product moves history into a shadow schema inside one database.
- **Open files** keep cold data readable by any engine, make a database switch cheaper, and serve analytics without a second copy.
- **Declarations, not code**: a new table needs one line, `class:`, and an AI only has to decide which class the table is.
- **Ports keep infrastructure replaceable without making it a component** ([0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)): a swap is one configuration value.
- **The corrected order** (seal, export, verify, switch, detach concurrently, drop) never leaves data readable nowhere and never queues every query behind an exclusive lock on the parent.

## Why not the others

- **Archive schemas**: they move the problem without solving it.
- **pg_partman**: its configuration table sits outside the component's schema, breaking [0102](../02-decisions/01-architecture/0102-one-schema-per-component.md), and it would bypass holds, checkpoints and verification. We borrow its pre-creation and boundary checks.
- **TimescaleDB**: a one-time conversion candidate for one huge table, not a runtime adapter.
- **Lake extensions and CDC**: both hand isolation to something outside the component.
- **DuckDB inside Go components**: needs cgo, and the images build without it; Python analytics components may embed it.

## When to switch

- **A customer already runs a lakehouse**, or erasures make rewriting Parquet costly: `cold_store: iceberg`.
- **Users query history often**: `cold_query: scan`, then `trino` when volumes need aggregates or cross-unit ordering.
- **Analytics starts** (`ana/*`): `publisher: watermark`; `debezium` for minute-level freshness.
- **A component holds heavy personal data** (HR): `pii: crypto-shred`.
- **One `ledger` or `audit` table passes about 1 TB online** and may not freeze: evaluate a one-time conversion of that table.
- **A domestic database delivery**: build and measure its `Dialect`.

## How to switch

1. Run `tools/be-acceptance/conformance/lifecycle/` against the target adapter combination; red stops the switch.
2. Change `DATA_LIFECYCLE` in `config/vars.yaml`; `brickkit up`.
3. If the adapter is newer than the SDK the components pin, each component takes the SDK patch release. No component code changes.

`s3-parquet` to `iceberg` registers the existing units in the catalogue once (the files stay), and back again the same way. Changing `cold_query` moves no data. Changing `Dialect` moves hot and warm data; the cold tier stays where it is.

## Conformance tests

Suite `tools/be-acceptance/conformance/lifecycle/`, run once per SDK through its widget, in five layers:

1. **Planner vectors** (`be-protocol` `vectors/lifecycle/`): declaration, overrides, time, units, holds and capabilities in; actions, blocked units and errors out; identical in every SDK.
2. **Engine black box** on real PostgreSQL with a simulated clock over 40 years, two replicas and two shell members at once: windows, seal refusals, states, online ranges; a crash injected at every transition gives the same end state.
3. **Cold round trip**, property-based over every column type the project uses: freeze, thaw, equal digests; a third-party reader (a DuckDB CLI container) recomputes the same digest from Parquet and manifest; WORM storage refuses an erasable table.
4. **Cold query**: identical rows from every adapter; `List(R, F)` before freezing equals after freezing (with cold query on) equals after thawing; `none` answers `RANGE_COLD` exactly for cold ranges.
5. **Erasure end to end** across hot, warm, cold, datasets and exports, including replay after a simulated recovery.

Red first: an override below the minimum fails to load; a `ledger` table with a personal column fails; `cold_store: none` never emits an export or deletes a business unit; sealing a unit with open rows marks it `BLOCKED`; an update to a sealed unit fails with `UNIT_SEALED`; a concurrent detach never makes a long read on the parent block new queries (red on the plain `DETACH`); the runtime role's own `CREATE TABLE … PARTITION OF` fails while the same partition created through `besdk_ensure_range_partition` succeeds; a full-range read during freezing never loses a row; migrating on any date leaves the outbox writable that day. Gate `lifecycle-scan`: every table in the migrations is declared; no personal column on `ledger`; cold `NUMERIC` columns have a precision.

## Decision records

- [0102 One database, one schema per component](../02-decisions/01-architecture/0102-one-schema-per-component.md): extended to every tier: a component's data is read and written only by that component, in its schema and in its own bucket.
- [0106 Infrastructure is not a component](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md): storage and query engines stay infrastructure, chosen behind SDK ports.
- [0104 A slot family needs several reasonable implementations and no dependency edge](../02-decisions/01-architecture/0104-variants-become-slot-families.md): governance is a plain component, not a family; the lifecycle adapters are SDK ports, not components.
- [0302 Contracts change by adding only](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md): published datasets follow it; `include_cold` is the one added list field.
- [0508 Background work runs only through the SDK's Jobs](../02-decisions/05-runtime/0508-background-work-only-through-jobs.md): the engine runs as a `singleton` job.
- Planned, not yet numbered: "the data lifecycle is declared per table and executed by the SDK"; "cold data is a component-owned open-format dataset"; "infrastructure products sit behind SDK ports as adapters, each passing one suite".

## Known limits

- **Stage 0 has no cold tier**: data stays warm until `s3-parquet` ships, so the database keeps growing until then.
- **Cold queries are limited** by the adapter: `scan` filters and orders within a unit; aggregates need `trino`.
- **Erasure lags in events and dead letters** (up to 14 + 7 days and 30 days) unless `crypto-shred` is used, and backups keep erased data until they expire.
- **Legal periods are drafted from mainland-China rules** (accounting archives 30 years from the day after the fiscal year ends, tax records 10 years, network logs at least 6 months) and need legal review before a delivery.
- **The PostgreSQL family only**, through `pg-native`; other dialects are measured before they are promised.
- **The governance component and the accounting archive package are not built yet.**
