[English](0002-one-schema-per-component.md) · [中文](../../../zh/02-decisions/01-architecture/0002-one-schema-per-component.md)

# 0002 One database, one schema per component

## Decision

All components share one PostgreSQL database. Each component owns one schema and one role, both taken from `registry/schemas.tsv`, keeps its migration state table inside its own schema, and never reads, writes or joins another component's schema. Data owned by another component is fetched through that component's API (`batchGet` for lists of ids).

## Why

One database with a schema per component lets a shell share one connection pool across its members while each member's role remains a permission wall: the shell borrows a connection and switches to the member's role with `SET LOCAL ROLE`, which resets at commit. A database per component cannot share a pool, and changing that once data exists is a data migration. Migration tools default to one state table in `public`; left there, components overwrite each other's migration history. Migrations run from each component's own image, whether or not it is hosted in a shell.

## What this rules out

- A separate database per component, or "give this component its own Postgres instance"
- Cross-schema `JOIN`s, views over another component's tables, a report that queries another component's schema directly
- Foreign keys from one component's tables to another's
- Leaving the migration state table (`schema_migrations`, `_yoyo_migration`) in `public`
- `SET ROLE` / `SET search_path` without `LOCAL` on a pooled connection: the next borrower inherits it and silently reads another component's data
- Inventing a schema or role name instead of copying it from `registry/schemas.tsv`

## Revisit only if

A component needs a storage capability PostgreSQL cannot provide. It then gets its own store through its own configuration; it still never reads another component's data directly.
