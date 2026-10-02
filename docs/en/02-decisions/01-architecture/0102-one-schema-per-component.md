[English](0102-one-schema-per-component.md) · [中文](../../../zh/02-decisions/01-architecture/0102-one-schema-per-component.md)

# 0102 One database, one schema per component

**Status**: revised for 3.0.0 (identity from configuration only, separate owner and runtime roles, the store handle, platform tables, NOINHERIT shells, the archive schema removed in favour of a cold tier in the component's own bucket); decided, lands with the 3.0.0 sweep.

## Decision

All components share one database of the PostgreSQL dialect family: PostgreSQL 14 or later for a standalone component, 16 or later for a shell (its NOINHERIT grants), or another engine that speaks its wire protocol and passes the database suite `tools/be-acceptance/conformance/db/`. Each component owns one schema and two roles, an owner role and a runtime role, taken from `registry/schemas.tsv`, keeps its migration state table inside its own schema, and never reads, writes or joins another component's schema. Data owned by another component is fetched through that component's API (`BatchGet` for lists of ids, [0304](../03-contracts-and-data/0304-batch-get-takes-at-most-500-ids.md)).

- **The identity comes from configuration only.** The owner role is `PG_OWNER_USER`, the runtime role is `PG_USER`, the schema is `PG_SCHEMA`; all three are required, none has a default, and none is derived from another. Migrations contain no role or schema name.
- **The owner role and the runtime role are separate.** The owner (`PG_OWNER_USER` / `PG_OWNER_PASSWORD`, a login role) owns the tables and does all DDL; migrations and the platform migration log in as it. The runtime role `PG_USER` has DML only and is not a member of the owner role; the running service uses only it. The few DDL steps needed at run time (partitions ahead, seal guards, dropping expired platform partitions) go through `SECURITY DEFINER` functions the owner creates. A documented limitation: brickKit gives the migration container the service's environment, so the service also receives the owner credentials; the SDK never uses them, and once brickKit FR06-013 (migration-only variables) lands only the migration container receives them.
- **Every access goes through the SDK's store handle**, which sets the role, `search_path` and timeouts with `SET LOCAL` inside each transaction; the outbox pump, consumers and jobs use it too.
- **SDK-owned tables** (`besdk_*`) live in the component's own schema, created by the SDK's platform migration; component SQL never touches them.
- **A shell's login role owns nothing**: it is granted every hosted member's runtime role `PG_USER` (never an owner role) `WITH INHERIT FALSE, SET TRUE` and can act only after `SET LOCAL ROLE`.
- **No archive schema.** The former per-component `<schema>_archive` is removed. Hot and warm rows stay in the component's own tables; cold data leaves the database only into the cold tier in the component's own bucket, under `cold/<table>/…`, with the component's own credential, and only that component reads or writes it ([09-data-lifecycle.md](../../04-foundations/09-data-lifecycle.md)).

## Why

One database with a schema per component lets a shell share one physical pool across its members while each member's role remains a permission wall: the shell borrows a connection and switches to the member's role with `SET LOCAL ROLE`, which resets at commit. A database per component cannot share a pool, and changing that once data exists is a data migration. Taking the identity only from configuration, and switching it per transaction in one SDK layer, means a module can never borrow another member's schema by accident, and NOINHERIT means the shell itself cannot touch a table even by mistake. Separating the owner from the runtime role means runtime SQL (an injection, a statement an AI wrote wrongly) cannot `DROP` or `ALTER` a table. An archive schema only moved old rows into a second schema with its own drift and routing; open files in the component's own bucket keep the same ownership wall without growing the database. Migration tools default to one state table in `public`; left there, components overwrite each other's migration history.

## What this rules out

- A separate database per component, or "give this component its own Postgres instance"
- Cross-schema `JOIN`s, views over another component's tables, a report that queries another component's schema directly
- Foreign keys from one component's tables to another's
- Leaving the migration state table (`schema_migrations`, `_yoyo_migration`) in `public`
- `SET ROLE` / `SET search_path` without `LOCAL` on a pooled connection: the next borrower inherits it and silently reads another component's data
- Deriving the role from the schema (`<schema>_rw`), defaulting `PG_SCHEMA`, or writing a role or schema name into a migration
- The running service logging in as, or switching to, the owner role; a runtime role that is a member of the owner; `SET ROLE` in component code
- A per-component archive schema (`<schema>_archive`) or any second schema for old data; a cold-data bucket shared between components, or one component reading another's cold files
- Component SQL that reads or writes a `besdk_*` table; a module opening its own pool beside the store handle
- Inventing a schema or role name instead of copying it from `registry/schemas.tsv`

## Revisit only if

- A component needs a storage capability PostgreSQL cannot provide, or must use another database instance. It then gets its own store through its own configuration, and in a shell its own pool; it still never reads another component's data directly.
- Writes on the single database become the measured bottleneck after partitioning and read replicas. The route is Citus schema-based sharding, which needs no component change because components never touch each other's schemas.

Full analysis: [03-database.md, Choice](../../04-foundations/03-database.md#choice).
