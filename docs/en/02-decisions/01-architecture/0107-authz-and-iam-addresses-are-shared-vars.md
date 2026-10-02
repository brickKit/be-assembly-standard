[English](0107-authz-and-iam-addresses-are-shared-vars.md) · [中文](../../../zh/02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)

# 0107 Authorization and identity are reached through shared variables, never through dependencies

**Status**: revised for 3.0.0 (`AUTHZ_URL` replaces `AUTHZ_BUNDLE_URL`; `IAM_ISSUER` and `TENANT_ID` added; no edge to any family member); decided, lands with the 3.0.0 sweep.

## Decision

No component declares a dependency edge on a member of the authorization family ([0209](../02-permissions/0209-authz-is-a-slot-family.md)) or of the identity family. Every contract of these two families is reached through shared variables, set once in `config/vars.yaml` and referenced as `$var:NAME`:

| Key | What it addresses |
|---|---|
| `AUTHZ_URL` | the installed authz member: bundle, changefeed, check, tuple writes, `ResolveClaims`, everything the family contract defines |
| `IAM_JWKS_URL` | the installed IAM member's signing keys |
| `IAM_ISSUER` | the expected `iss` of every token; it names the platform, not the IdP |
| `TENANT_ID` | the expected `aud` of every token ([0308](../03-contracts-and-data/0308-tenant-is-the-deployment.md)) |

The host is the member's own versioned service name (`infra-authz-<version>`, `infra-iam-casdoor-<version>`), which resolves standalone, inside a shell and on Kubernetes, so no deploy file overrides it; it changes only when that member releases, and `make gates` fails while it disagrees with `brickkit.yaml` (see [configuration conventions](../../01-conventions/04-configuration.md#dependency-addresses)). This holds for the members themselves: the edge from `infra/iam-casdoor` to `infra/authz` is removed, and iam calls authz through `AUTHZ_URL`.

## Why

Dependencies are pinned to exact versions, so an edge from every component to authz and iam would force every component to release whenever either releases. Both positions are slot families: an edge names one implementation (`INFRA_IAM_CASDOOR_ENDPOINT`) and a slot member must not be depended on, so switching members would touch every component. Components verify tokens locally with the published keys and decide permissions against a local bundle ([0202](../02-permissions/0202-local-permission-bundle.md)), so they need no start order from the platform.

## What this rules out

- Adding any authz or IAM family member under `dependencies.components`, including from another family member
- Building an authz or IAM address from an injected `*_ENDPOINT` variable, or keeping `AUTHZ_BUNDLE_URL`
- A literal authz or JWKS URL in one component's `config/<scope>-<name>.yaml` when the shared value applies
- Calling the IAM component on each request to validate a token
- Expecting the platform to start authz or iam before the components that use them
- Addressing authz or iam by a shell's service name: it exists only on Docker with the member merged, and changes with every release of that shell
- Enabling Kubernetes `networkPolicy` without opening these calls in the deploy file (`egress.allowTo` for the authz and iam Pods, `allowFrom` for their ingress): the generated policies follow dependency edges only, so every protected route answers `503`

## Revisit only if

brickKit offers a kind of dependency on a slot (by position, not by member) that neither pins an exact version nor names the implementation in the injected variable.

Full analysis: [20-authorization-provider.md, Port contract](../../04-foundations/20-authorization-provider.md#port-contract) and [21-identity-provider.md, Port contract](../../04-foundations/21-identity-provider.md#port-contract).
