[English](0209-authz-is-a-slot-family.md) · [中文](../../../zh/02-decisions/02-permissions/0209-authz-is-a-slot-family.md)

# 0209 Authorization is a slot family with one contract and one suite

**Status**: decided; lands with the 3.0.0 sweep (`infra/authz-static` and `infra/authz-openfga` built in phase 06).

## Decision

The authorization provider is a slot family (`slot:authz`, [0104](../01-architecture/0104-variants-become-slot-families.md)). Exactly one member is installed; every component reaches it through `AUTHZ_URL` ([0107](../01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)).

- **Two contracts**, in the family repository `contract-infra-authz`: the provider contract `infra.authz.v2` (bundle, changefeed, tuples, check, explain, delegations, `ResolveClaims`, admin REST) that every member implements, and the resource contract (`_authz/check`, `_authz/explain`, `_shares`) that the SDK mounts in every component declaring resources.
- **The family repository holds the code and the vectors.** It is checked out at `contracts/infra/authz` (github.com/brickKit/contract-infra-authz). Go code is generated there with `make gen` and committed under `gen/go` before tag `v2.0.0` (`github.com/brickKit/contract-infra-authz/v2/gen/go/infra/authz/v2`, a family contract package, [0101](../01-architecture/0101-no-imports-between-components.md)); the Python and TypeScript SDKs copy `proto/` and `schemas/` from a pinned tag and generate privately. The meaning of a bundle is the repository's `EVALUATION.md`, and the decision vectors that lock it are canonical in its `vectors/`; be-protocol cites them by tag and keeps only protocol-wide vectors.
- **List/Can consistency is part of the contract**: a row is in a list for key K if and only if a single-record check for K says visible.
- **Capabilities are negotiated in the bundle.** Core (claims, keys, levels, values, field keys, stale, revision, catalogue sync, `/api/me/access`, basic explain, time limits) is mandatory; the rest (`admin_write`, `sharing`, `relation_sync`, `check`, `graph`, `delegation`, `agents`, `impersonation`, `access_review`, `explain_paths`, `conditions`) is optional, and a missing one degrades explicitly (`501` / `CAPABILITY_UNAVAILABLE`, an empty projection, hidden entry points). A component declares `requires_capabilities`; assembly fails when the installed member's `provides_capabilities` does not cover them.
- **The members**, all built in phase 06, in this order: `infra/authz` (native, default) → `infra/authz-static` (a policy file, no database) → `infra/authz-openfga` (ReBAC, adds `graph`). Cedar or OPA only on a real ABAC need, and only for actions; conditions never take part in row visibility.
- **Every member passes** `tools/be-acceptance/conformance/authz/`. Switching members moves the assignments through the NDJSON export and import that the family contract defines; an import into a member lacking a capability reports every row it cannot hold and stops.

## Why

Authorization models differ for real (role-and-level for most ERP customers, relationship graphs for collaboration-heavy ones, policy languages for ABAC), so the position meets both conditions of a slot family once no component depends on a member. A second and third real member, built early, are what force the contract to be honest; the suite is what makes "replaceable" a test rather than a claim. Explicit degradation means a smaller member is a visible choice, not a silent loss of protection.

## What this rules out

- A component depending on `infra/authz` or any other member, or calling a member-specific API outside the family contract
- A capability assumed rather than declared: code that relies on `sharing` or `graph` without `requires_capabilities`
- A member that silently drops what it cannot hold (shares into a static member) instead of refusing
- An admin screen built against one member's private API; the admin UI is generated from the family contract only
- A list filter whose result disagrees with `_authz/check` for the same key
- ABAC conditions deciding which rows a list returns

## Revisit only if

A customer's model cannot be expressed behind the two contracts even with a new optional capability, or the family converges in practice on one member and nobody needs another (the suite then stays as a regression test).

Full analysis: [20-authorization-provider.md, Choice](../../04-foundations/20-authorization-provider.md#choice) and [When to switch](../../04-foundations/20-authorization-provider.md#when-to-switch).
