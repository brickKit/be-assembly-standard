[English](0206-no-row-level-security.md) · [中文](../../../zh/02-decisions/02-permissions/0206-no-row-level-security.md)

# 0206 No row-level security; one sharing engine, in authz

**Status**: rewritten in place for 3.0.0 (sharing moves into authz and is projected by the SDK); decided, lands with the 3.0.0 sweep.

## Decision

Data-scope conditions are written into each query's SQL as the SDK's canonical predicate and passed as parameters. PostgreSQL row-level security is not used. There is exactly one sharing engine: the authorization provider holds shares and relations as tuples, and the SDK projects the direct ones into `besdk_authz_acl` in each component that declares resources. A component never writes a sharing table of its own. The `org` dimension matches the materialised path `dept_path` (exactly for `dept`, by prefix for `subtree`); no component keeps a copy of the organisation tree. Children of a record in another component are checked through their parent's `_authz/check`, one parent at a time.

## Why

Static parameterised SQL expresses every dimension the project has, and the rule stays in the one place a reviewer reads. RLS adds a second home for rules plus a silent trap: a table's owner bypasses RLS by default, so a policy can exist and filter nothing. Sharing is a real requirement, but one engine with one contract and a suite is safer than a share table hand-written in every component, and the projection keeps the list query local. A person with no department contributes no department entries to the predicate, so an empty path matches nothing (fail-closed).

## What this rules out

- "Enable RLS on this table"; `CREATE POLICY`
- A "share this record with user X" table and mechanism written inside a component
- A replica of the organisation tree, or recursive queries over one, to resolve "my department and below"
- Treating an empty `dept_path` as the root of the tree
- List filtering by visibility inherited across a parent in another component ("all attachments I may see"): check each parent instead
- Adding a `dept_path` column to tables that belong to no department (product categories, units of measure)

## Revisit only if

A real scope cannot be written as the canonical predicate with one-hop derivation and subject expansion, and no provider with the `graph` capability ([0209](0209-authz-is-a-slot-family.md)) is installed to answer it.

Full analysis: [20-authorization-provider.md, Port contract](../../04-foundations/20-authorization-provider.md#port-contract).
