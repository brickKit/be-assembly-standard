[English](0014-no-row-level-security.md) · [中文](../../../zh/02-decisions/02-permissions/0014-no-row-level-security.md)

# 0014 No row-level security, no sharing engine

## Decision

Data-scope conditions are written into each query's SQL and passed as parameters (`sqlc` or hand-written SQL). PostgreSQL row-level security is not used, and there is no general record-sharing engine. The `org` dimension matches a prefix of the materialised path `dept_path`; no component keeps a copy of the organisation tree.

## Why

Static parameterised SQL expresses every dimension the project has, and the rule stays in the one place a reviewer reads. RLS adds a second home for rules plus a silent trap: a table's owner bypasses RLS by default, so a policy can exist and filter nothing. A general sharing engine is building Zanzibar, which does not fit a single-machine deployment.

## What this rules out

- "Enable RLS on this table"; `CREATE POLICY`
- A "share this record with user X" table and mechanism in every component
- A replica of the organisation tree, or recursive queries over one, to resolve "my department and below"
- Adding a `dept_path` column to tables that belong to no department (product categories, units of measure)

## Revisit only if

A real scope cannot be written as static parameterised SQL.
