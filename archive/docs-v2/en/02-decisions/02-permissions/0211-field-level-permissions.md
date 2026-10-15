[English](0211-field-level-permissions.md) · [中文](../../../zh/02-decisions/02-permissions/0211-field-level-permissions.md)

# 0211 Field-level permission is a key, enforced at the source

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

A field that only some people may see (a customer's credit limit, a product's standard cost, an order's pricing details) is guarded by a permission key of `type: field`, declared with its columns in the owning component's `resources` field sets (a read key and, where needed, an edit key).

- **The owning component masks**, before the answer leaves it: a masked field is `null` and is listed in `_masked`.
- A write to a masked field answers `403` with reason `FIELD_FORBIDDEN`.
- Sorting, filtering or aggregating by a field masked for the caller is refused (`SORT_FORBIDDEN`): an order of rows or a total would leak what the mask hides.
- A field is visible only where its row is: `field(P, K, r) = visible(P, K, r) AND P holds the field key`.
- Events are the system plane and carry fields unmasked; they are never shown to people as they are.

## Why

Masking at the source is the only place that cannot be bypassed: a BFF, a frontend or a downstream component that masks can always be skipped by another caller. A field key is just a key, so roles, levels, delegation ceilings and explanations already cover it, with no second mechanism. Refusing sort and filter on masked fields closes the side channel that a "hidden" column used for ordering opens.

## What this rules out

- Masking in the frontend, the BFF or the calling component instead of in the owner
- A separate field-permission table or configuration per component
- Sorting or filtering by a field the caller cannot see; totals that include it
- Showing an event payload to a person as it is
- A field key that widens which rows are visible

## Revisit only if

A field must be visible on some rows and not others for the same person by a rule that the row-level scope cannot express.

Full analysis: [20-authorization-provider.md, Port contract](../../04-foundations/20-authorization-provider.md#port-contract).
