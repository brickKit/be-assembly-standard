[English](0509-edge-only-routes.md) · [中文](../../../zh/02-decisions/05-runtime/0509-edge-only-routes.md)

# 0509 The edge only routes; authentication and authorization stay in the services

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

The edge (Traefik by default) sits between a browser, the mobile app or an external system and a component's REST port. It handles traffic and nothing that decides who may do what:

| | What |
|---|---|
| **The edge does** | TLS; routing by longest path prefix; a body limit per route; edge timeouts derived from the route deadline; coarse per-IP rate limits; starting the trace and the request ID; stripping internal and spoofable headers (`X-Request-Id`, `traceparent`, every `be-*` header, untrusted `X-Forwarded-*`); a CORS allow-list only for a separate origin |
| **The edge does not** | authenticate as the only gate, authorize, apply data scopes, route on business content, retry a request that has a body, or cache API responses |
| **The edge never routes** | gRPC ports; `/healthz`, `/readyz`, `/metrics`, `/_be/info`; internal paths a component leaves out of `edge_routes` (`/authz/bundle`, the JWKS, the Casdoor webhook) |

- Every service verifies the token itself against the local JWKS and decides the route's permission key, data scopes and visibility itself, whether or not an edge is in front of it.
- A route's `auth: required | none` in `edge_routes` documents intent and drives the end-to-end tests; the service still enforces it.
- Answers the edge produces itself (404, 413, 429, 502, 503, 504) carry the platform problem body with `domain: be` (`RATE_LIMITED`, `UPSTREAM_UNAVAILABLE`, `UPSTREAM_TIMEOUT`).

## Why

"Every component runs on its own" includes running without our gateway in front of it: if the token were checked only at the edge, bypassing the edge or deploying a component alone would open everything. Verifying in every service is cheap (a local JWKS and a local permission bundle, [0202](../02-permissions/0202-local-permission-bundle.md)) and gives defence in depth. Keeping business decisions out of the edge also keeps the gateway infrastructure rather than a component ([0106](../01-architecture/0106-infrastructure-is-not-a-component.md)): an official image plus generated configuration, swapped by choosing another generator.

## What this rules out

- Checking the token only at the gateway (Traefik ForwardAuth, a JWT plugin) and trusting a header the gateway sets
- Permission keys, data scopes, field masks or quotas evaluated at the edge
- Routing on request bodies or business values
- Routing gRPC, `/healthz`, `/readyz`, `/metrics` or `/_be/info` to the outside
- Retrying a non-idempotent request at the edge; caching API responses at the edge

## Revisit only if

A customer's security architecture requires an authentication layer at the gateway as well: it is added in front of the edge, never instead of verification in the services. Rate limits per API key, when the external API opens, are traffic handling and need no revisit.

Full analysis: [18-edge.md, Choice](../../04-foundations/18-edge.md#choice).
