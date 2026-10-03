[English](0509-edge-only-routes.md) · [中文](../../../zh/02-decisions/05-runtime/0509-edge-only-routes.md)

# 0509 The edge only routes; authentication and authorization stay in the services

**Status**: decided; lands with the 3.0.0 sweep. Revised for brickKit 1.3: the routes are generated into the deploy entries brickKit reads (`paths` on Kubernetes, Traefik `labels` on Docker and Podman) instead of into a separate route file.

## Decision

The edge (Traefik by default) sits between a browser, the mobile app or an external system and a component's REST port. It handles traffic and nothing that decides who may do what:

| | What |
|---|---|
| **The edge does** | TLS; routing by longest path prefix; a body limit per route; edge timeouts derived from the route deadline; coarse per-IP rate limits; starting the trace and the request ID; stripping internal and spoofable headers (`X-Request-Id`, `traceparent`, every `be-*` header, untrusted `X-Forwarded-*`); a CORS allow-list only for a separate origin |
| **The edge does not** | authenticate as the only gate, authorize, apply data scopes, route on business content, retry a request that has a body, or cache API responses |
| **The edge never routes** | gRPC ports; `/healthz`, `/readyz`, `/metrics`, `/_be/info`; OpenAPI operations marked `x-be-internal: true`, the provider plane that only other components call (authz `/authz/v2/*`, the iam JWKS under `/.well-known/*`), which are also exempt from the edge-route coverage gate; internal paths a component leaves out of `edge_routes` (the Casdoor webhook) |

- Every service verifies the token itself against the local JWKS and decides the route's permission key, data scopes and visibility itself, whether or not an edge is in front of it.
- A route's `auth: required | none` in `edge_routes` documents intent and drives the end-to-end tests; the service still enforces it.
- Answers the edge produces itself (404, 413, 429, 502, 503, 504) carry the platform problem body with `domain: be` (`RATE_LIMITED`, `UPSTREAM_UNAVAILABLE`, `UPSTREAM_TIMEOUT`).
- **Routes are generated, never hand-written.** be-ops reads each component's `edge_routes` and writes the route into that component's deploy entry: on Kubernetes the entry's `paths` (brickKit's Ingress per component, path-segment-bounded prefixes, one shared `hostname` and one `tlsSecret`); on Docker and Podman Traefik router `labels` with segment-bounded rules (``PathRegexp(`^/erp/sales(/|$)`)``, never a bare `PathPrefix`, which matches by string), read by Traefik 3.6 or later on the project's `network:` (Docker Engine 29 refuses the API version older releases ask for). Labels and Ingress back ends follow the versioned service name, so an upgrade changes no route.

## Why

"Every component runs on its own" includes running without our gateway in front of it: if the token were checked only at the edge, bypassing the edge or deploying a component alone would open everything. Verifying in every service is cheap (a local JWKS and a local permission bundle, [0202](../02-permissions/0202-local-permission-bundle.md)) and gives defence in depth. Keeping business decisions out of the edge also keeps the gateway infrastructure rather than a component ([0106](../01-architecture/0106-infrastructure-is-not-a-component.md)): an official image plus generated configuration, swapped by choosing another generator.

## What this rules out

- Checking the token only at the gateway (Traefik ForwardAuth, a JWT plugin) and trusting a header the gateway sets
- Permission keys, data scopes, field masks or quotas evaluated at the edge
- Routing on request bodies or business values
- Routing gRPC, `/healthz`, `/readyz`, `/metrics`, `/_be/info` or an `x-be-internal` operation to the outside
- Retrying a non-idempotent request at the edge; caching API responses at the edge
- A hand-written route, Ingress or Traefik rule for a component's user plane; a bare `PathPrefix` rule, which lets `/erp/sales` take `/erp/salesman`

## Revisit only if

A customer's security architecture requires an authentication layer at the gateway as well: it is added in front of the edge, never instead of verification in the services. Rate limits per API key, when the external API opens, are traffic handling and need no revisit.

Full analysis: [18-edge.md, Choice](../../04-foundations/18-edge.md#choice).
