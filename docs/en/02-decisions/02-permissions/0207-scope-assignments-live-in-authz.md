[English](0207-scope-assignments-live-in-authz.md) · [中文](../../../zh/02-decisions/02-permissions/0207-scope-assignments-live-in-authz.md)

# 0207 Data-scope assignments live in authz

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

Who gets which part of a rule ([0205](0205-data-scopes-ship-with-the-version.md)) is a runtime assignment held by the authorization provider, edited by administrators and delivered in the bundle:

| Assignment | Example | Where it is held |
|---|---|---|
| a level per role and key | `erp.sales.view: subtree`, `erp.sales.cancel: own` | the role's `levels` |
| dimension values per role | `warehouse: ["7"]`; a custom set of department subtrees as values of `org` | the role's `values` |
| a time limit | a warehouse grant until the end of the stocktake | `until` on the grant, evaluated locally |
| a share or a delegation | one order shared with a colleague; approvals handed over during leave | tuples and delegations in authz ([0206](0206-no-row-level-security.md), [0210](0210-delegation-and-impersonation.md)) |

Several roles giving one key: the highest level wins, values are unioned, `*` means all and is only ever granted explicitly; a key granted without a level is `own`. Each resource dimension has exactly one owning component, recorded in the registry and checked by be-ops. A component holds no authorization table and serves no assignment API.

## Why

Before 3.0.0, "which warehouses this keeper sees" lived in tables inside erp/inventory and erp/finance, each with its own admin endpoints, and "managers see everything" was expressed by extra `.admin` keys. Assignments in one place give one admin screen, one audit trail and one explanation of every decision, and they let a level such as "only my own orders" exist for any key, which per-component tables could not express. Rules stay in code; only who gets what moves to data.

## What this rules out

- A `warehouse_access`, `legal_entity_access` or similar table inside a business component, and the endpoints that edit it (removed in 3.0.0)
- A permission key that widens a scope (`*.admin` meaning "all rows"): the `all` level replaces it
- Two components both claiming one resource dimension
- Syncing assignments into components by events into tables of their own; the bundle and the projection are the only copies

## Revisit only if

An assignment depends on business data only the owning component has (an attribute of the row itself); that is a rule and belongs in the component's version, not here.

Full analysis: [20-authorization-provider.md, Port contract](../../04-foundations/20-authorization-provider.md#port-contract).
