[English](0021-authz-and-iam-addresses-are-shared-vars.md) · [中文](0021-authz-and-iam-addresses-are-shared-vars.zh.md)

# 0021 The permission bundle and token keys are shared variables, not dependencies

## Decision

For the two things every component needs from authz and iam — polling the permission bundle and verifying tokens — components declare no dependency edge. They read the bundle address from `AUTHZ_BUNDLE_URL` and the identity provider's signing keys from `IAM_JWKS_URL`. Both are set once in `config/vars.yaml`, referenced as `$var:AUTHZ_BUNDLE_URL` / `$var:IAM_JWKS_URL` from each component's configuration, and overridden per topology in the deploy file's `vars:` (see [configuration conventions](../conventions/configuration.md#dependency-addresses)). A component that calls a business API of authz or iam over gRPC declares that dependency like any other — for example `infra/iam-casdoor` → `infra/authz` — and uses the injected `*_ENDPOINT` for that call only.

## Why

Dependencies are pinned to exact versions. With an edge from every component to authz and iam, every release of either would force every component to release. IAM is also a slot: a dependency edge names the implementation (`INFRA_IAM_CASDOOR_ENDPOINT`), so switching from Casdoor to another OIDC provider would touch every component. Components verify tokens locally with the published keys and tolerate authz not being up yet ([0005](0005-local-permission-bundle.md)), so they need no start order from the platform. A real business call is different: the caller needs that API's contract, so it depends on that exact version, like any other dependency.

## What this rules out

- Adding `infra/authz@x.y.z` or `infra/iam-casdoor@x.y.z` under `dependencies.components` only to fetch the bundle or to verify tokens
- Building the bundle or JWKS address from `INFRA_AUTHZ_ENDPOINT` or `INFRA_IAM_CASDOOR_ENDPOINT` instead of `AUTHZ_BUNDLE_URL` / `IAM_JWKS_URL`
- Calling authz's or iam's gRPC API without declaring the dependency (for example through `AUTHZ_BUNDLE_URL` with the path cut off)
- A literal bundle or JWKS URL in one component's `config/<scope>-<name>.yaml` when the shared value applies
- Calling the IAM component on each request to validate a token
- Expecting the platform to start authz or iam before components that only poll the bundle or verify tokens

## Revisit only if

brickKit offers a kind of dependency that neither pins an exact version nor names the implementation in the injected variable.
