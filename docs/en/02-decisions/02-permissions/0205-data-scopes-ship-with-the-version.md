[English](0205-data-scopes-ship-with-the-version.md) · [中文](../../../zh/02-decisions/02-permissions/0205-data-scopes-ship-with-the-version.md)

# 0205 Data-scope rules ship with the version

**Status**: rewritten in place for 3.0.0 (rules in the version, assignments in authz); decided, lands with the 3.0.0 sweep.

## Decision

The **rules** that decide which rows a key can reach are part of the component's code and contract, and change only by releasing a new version:

- which dimensions a resource type has (`owner`, `org`, and resource dimensions such as `warehouse` or `legal_entity`), and how they combine: `owner` and `org` OR'ed, resource dimensions AND'ed;
- which levels apply (`own`, `dept`, `subtree`, `all`);
- which relations a resource type has, what each grants, and whether it can be shared.

They are declared in `assembly.yaml` under `data_scopes` and `resources` and enforced by the SDK's canonical predicate in the component's queries. `data_scopes` is mandatory: a component that needs none writes `data_scopes: none`, and omitting it is an error.

**Assignments** (which level and which values a role gets for a key, which records are shared with whom) are runtime data in authz, edited by administrators ([0207](0207-scope-assignments-live-in-authz.md)). What a user may *do* (functional permissions) is the same kind of runtime data.

## Why

SAP, Odoo and PostgreSQL row-level security all ship row rules with the code: a rule in code can be reviewed, diffed, tested and rolled back, and it is the same for every customer on that version. What does change daily is who gets which level and which values, so that part is data. A security default must fail closed, so leaving the section out cannot mean "none".

## What this rules out

- Editing a rule at runtime: "let the `org` dimension also match the customer's region", a configurable formula, a rule written in an admin screen
- Fetching everything and filtering in the caller: paging is wrong at once (20 rows fetched, 12 filtered, the user sees 8)
- Filtering a list in a way that disagrees with the single-record check for the same key (List/Can consistency)
- Omitting `data_scopes` because the component "doesn't need it"
- Using the component's system identity on a user's request path: it bypasses data scopes with no error ([0208](0208-grpc-is-the-system-plane.md))

## Revisit only if

A customer must change row rules, not assignments, between releases more often than the release cadence can follow.

Full analysis: [20-authorization-provider.md, Choice](../../04-foundations/20-authorization-provider.md#choice).
