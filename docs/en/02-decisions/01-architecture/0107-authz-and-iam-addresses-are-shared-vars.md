[English](0107-authz-and-iam-addresses-are-shared-vars.md) · [中文](../../../zh/02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)

# 0107 Family addresses are `$endpoint:` references in shared variables, never dependencies

**Status**: revised for 3.0.0, twice: `AUTHZ_URL` replaces `AUTHZ_BUNDLE_URL`, `IAM_ISSUER` and `TENANT_ID` are added, and no component has an edge to any family member; then, with brickKit 1.2, the address values are `$endpoint:` references instead of hand-written service names, every gRPC address has a key of its own, and the `service-hostname-scan` gate retires. Decided, lands with the 3.0.0 sweep.

## Decision

No component declares a dependency edge on a member of the authorization family ([0209](../02-permissions/0209-authz-is-a-slot-family.md)) or of the identity family. A component declares the family keys it reads in its `configSchema` and references the shared values as `$var:NAME`. The shared values live once in `config/vars.yaml`, and every address there is a brickKit `$endpoint:` reference to the installed member, never a hand-written host or port:

```yaml
# config/vars.yaml: who fills each slot is written here and nowhere else
AUTHZ_URL:      $endpoint:infra/authz
AUTHZ_GRPC_URL: $endpoint:infra/authz:grpc
IAM_URL:        $endpoint:infra/iam-casdoor
IAM_GRPC_URL:   $endpoint:infra/iam-casdoor:grpc
IAM_ISSUER:     urn:be:acme:iam
TENANT_ID:      acme
```

| Key | What it addresses |
|---|---|
| `AUTHZ_URL` | the installed authorization member's main port: bundle, changefeed, check, tuple writes, everything the family's REST contract defines |
| `AUTHZ_GRPC_URL` | the same member's extra port named `grpc`: `ResolveClaims` and the family's other rpcs |
| `IAM_URL` | the installed identity member's main port: OIDC discovery, the JWKS and the directory endpoints under it |
| `IAM_GRPC_URL` | the same member's extra port named `grpc` |
| `IAM_ISSUER` | the expected `iss` of every token; it names the platform, not the IdP, so it is a literal, not an address |
| `TENANT_ID` | the expected `aud` of every token ([0308](../03-contracts-and-data/0308-tenant-is-the-deployment.md)) |

- **brickKit computes every address**, by the same rule as a dependency's `*_ENDPOINT`: `http://<versioned service name>:<port>`, no trailing `/`. It follows the member's version on `brickkit upgrade`, points at the shell when a shell hosts the member, becomes a reachable local address for a component run with `mode: local` / `debug` or `--focus`, and opens Kubernetes `networkPolicy` between the two. The SDK strips the scheme from a `*_GRPC_URL` and dials `host:port`.
- **No port arithmetic.** A family's gRPC address is the member's own declared port named `grpc`, reached through its own key; it is never derived from the HTTP address.
- **Swapping a member is one line per key** in `config/vars.yaml` (plus `brickkit add` / `remove` of the members); no component file changes.
- **An absent member means an absent key.** When the referenced member does not run, an optional key is not injected and the component degrades; a required key stops `up` with an error naming the member that does not run.
- **No start order, and cycles are allowed.** A reference creates no `depends_on`: the authorization member reads `IAM_URL` and the identity member reads `AUTHZ_URL` and `AUTHZ_GRPC_URL`; both retry with backoff until the other answers. A member referring to itself is allowed too (the identity member hands Casdoor its webhook address, `$endpoint:infra/iam-casdoor/api/iam/webhooks/casdoor`).

## Why

Dependencies are pinned to exact versions, so an edge from every component to authz and iam would force every component to release whenever either releases. Both positions are slot families: an edge names one implementation (`INFRA_IAM_CASDOOR_ENDPOINT`), and switching members would touch every component. Components verify tokens locally with the published keys and decide permissions against a local bundle ([0202](../02-permissions/0202-local-permission-bundle.md)), so they need no start order from the platform.

Hand-written service names in `config/vars.yaml` were the first answer, and they failed the way any second copy does: every member release changed the name, a release once left 25 references stale, and the `service-hostname-scan` gate could only detect the drift, not prevent it. A `$endpoint:` reference is resolved by brickKit from `brickkit.yaml` at every `up`, so there is nothing to drift. Deriving the gRPC port as "HTTP port + 1000" was a second hidden convention that every member would have had to follow; a key per port makes the member's own declaration the only fact.

## What this rules out

- Adding any authz or IAM family member under `dependencies.components`, including from another family member
- A hand-written host, service name or port for a family member anywhere in `config/` or a deploy file's `vars:`; the address is always `$endpoint:<member ID>[:<port name>][/<path>]`
- Deriving a family's gRPC address from its HTTP address by arithmetic, building any family address from an injected `*_ENDPOINT` variable, or keeping `AUTHZ_BUNDLE_URL` or `IAM_JWKS_URL` (the JWKS is `{IAM_URL}/.well-known/jwks.json`)
- A literal family address in one component's `config/<scope>-<name>.yaml` when the shared value applies
- Calling the IAM component on each request to validate a token
- Expecting the platform to start authz or iam before the components that use them
- Naming a shell in `$endpoint:`: name the member, and brickKit points at the shell while it hosts the member
- Opening Kubernetes `networkPolicy` for these calls by hand: the `$endpoint:` reference already opens them

## Revisit only if

brickKit removes `$endpoint:` or changes what it resolves to, or a family gains a contract that needs the platform to start its member first (then it is a dependency, declared in `component.yaml`, and the family question is reopened under [0104](0104-variants-become-slot-families.md)).

Full analysis: [24-config-and-secrets.md, Port contract](../../04-foundations/24-config-and-secrets.md#port-contract), [20-authorization-provider.md, Port contract](../../04-foundations/20-authorization-provider.md#port-contract) and [21-identity-provider.md, Port contract](../../04-foundations/21-identity-provider.md#port-contract).
