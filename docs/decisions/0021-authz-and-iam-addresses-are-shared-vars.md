[English](0021-authz-and-iam-addresses-are-shared-vars.md) · [中文](0021-authz-and-iam-addresses-are-shared-vars.zh.md)

# 0021 The authz and iam addresses are shared variables, not dependencies

## Decision

No component declares `infra/authz` or the IAM component as a dependency. Components read the permission bundle address from `AUTHZ_BUNDLE_URL` and the identity provider's signing keys from `IAM_JWKS_URL`. Both are set once in `config/vars.yaml`, referenced as `$var:AUTHZ_BUNDLE_URL` / `$var:IAM_JWKS_URL` from each component's configuration, and overridden per topology in the deploy file's `vars:` (see [configuration conventions](../conventions/configuration.md#dependency-addresses)).

## Why

Dependencies are pinned to exact versions. With an edge from every component to authz and iam, every release of either would force every component to release. IAM is also a slot: a dependency edge names the implementation (`INFRA_IAM_CASDOOR_ENDPOINT`), so switching from Casdoor to another OIDC provider would touch every component. Components verify tokens locally with the published keys and tolerate authz not being up yet ([0005](0005-local-permission-bundle.md)), so they need no start order from the platform.

## What this rules out

- Adding `infra/authz@x.y.z` or `infra/iam-casdoor@x.y.z` under a component's `dependencies.components`
- Reading `INFRA_AUTHZ_ENDPOINT` or `INFRA_IAM_CASDOOR_ENDPOINT` in component code
- A literal authz or iam URL in one component's `config/<scope>-<name>.yaml` when the shared value applies
- Calling the IAM component on each request to validate a token
- Expecting the platform to start authz or iam before the other components

## Revisit only if

brickKit offers a kind of dependency that neither pins an exact version nor names the implementation in the injected variable.
