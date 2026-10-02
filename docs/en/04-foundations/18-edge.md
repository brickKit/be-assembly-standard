[English](18-edge.md) · [中文](../../zh/04-foundations/18-edge.md)

# Edge

Everything between a browser, the mobile app or an external system and a component's REST port: where routes come from, what the edge does to a request on the way in and out, what it must never do, and how the same route table becomes Traefik configuration on Docker and Ingress or Gateway API objects on Kubernetes. For whoever adds a public path, changes the gateway, plans the external API, or proposes moving authentication to the gateway.

## Scope

- **In:** TLS termination; routing by path prefix; the neutral route table and its generators; body limits, timeouts and coarse rate limits at the edge; the request ID and the start of a trace; stripping headers a client must not set; CORS; where API keys will be rate-limited; HTTP caching at the edge; the BFF policy; reaching object storage from a browser.
- **Out:** token verification and authorization, which stay in every service ([21-identity-provider.md](21-identity-provider.md), [20-authorization-provider.md](20-authorization-provider.md)); the shape of user requests and errors ([15-user-api-and-errors.md](15-user-api-and-errors.md)); route deadlines and server timeouts ([16-deadlines-and-retries.md](16-deadlines-and-retries.md)); gRPC, which never passes the edge ([14-system-rpc.md](14-system-rpc.md)); trace propagation inside the system ([23-observability.md](23-observability.md)); how deployment files are generated (`brickkit docs 01-three-layers/03-deploy-yaml`).

## Choice

- **Routes are derived, never hand-written.** Each component declares its public paths in `edge_routes` in its `assembly.yaml`. be-ops reads every declaration plus the exact versions in `brickkit.yaml` and writes one neutral route table, `build/edge/routes.json`. A generator per target renders it: the Traefik file provider on Docker and Podman; Ingress (or Gateway API `HTTPRoute`) objects on Kubernetes. A gate fails when the generated table disagrees with `brickkit.yaml`.
- **Traefik is the default edge**: already deployed by `make up`, small, watches its file provider, has OpenTelemetry tracing built in.
- **The edge does**: TLS; routing by longest path prefix; a body limit per route; edge timeouts derived from the route deadline; coarse per-IP rate limits; starting the trace and the request ID; stripping internal and spoofable headers; a CORS allow-list only for a separate origin.
- **The edge does not**: authenticate as the only gate, authorize, apply data scopes, route on business content, retry a non-idempotent request, or cache API responses. Every service verifies the token itself, so bypassing the edge or deploying a component alone never weakens security ([0509](../02-decisions/05-runtime/0509-edge-only-routes.md)).
- **Never routed**: gRPC ports; `/healthz`, `/readyz`, `/metrics`, `/_be/info`; internal paths a component leaves out of `edge_routes` on purpose (`/authz/bundle`, the JWKS, the Casdoor webhook).
- **BFF**: the mobile app keeps `infra/bff-mobile`; the PC frontend calls each component's REST directly and completes names with the owner's `BatchGet`; there is no PC BFF.
- **Same origin by default**: the frontend and the APIs share one host name through the edge, so no CORS. Static assets are served by the frontend's own container with cache headers; the edge caches nothing.

**Status**: in place: Traefik v3.0 with the Docker and file providers (`infra/traefik/`), and `edge_routes` declared by all fourteen components. Nothing reads `edge_routes` yet: the file provider directory is empty, so browser-to-component routing has no generated artifact, and the edge applies no middleware at all (no limits, no timeouts, no header stripping). Decided (lands with the 3.0.0 sweep): the route table, the Traefik and Kubernetes Ingress generators, the middleware set, the freshness gate. Later: rate limits per API key (with the external API), a global rate limit across edge instances, a Gateway API generator.

## Port contract

### Declaration

`edge_routes` in `assembly.yaml` (this project's file, read by be-ops, never by brickKit):

| Field | Required | Meaning |
|---|---|---|
| `path` | yes | a prefix ending in `/**`, under the component's own prefix (`/erp/sales/**`), or a reserved family or platform prefix (`/api/iam/…`, `/integration/im/**`, `/graphql`); the frontend's `/**` is the fallback |
| `auth` | yes | `required` or `none`; documents intent and drives the end-to-end tests; the service still enforces it |
| `body_limit` | no | bytes; default 1 MiB, the same default as the server ([16](16-deadlines-and-retries.md#the-budget-hop-by-hop)) |
| `timeout` | no | seconds; default: the longest `x-be-deadline-seconds` among the component's OpenAPI operations under this prefix (10 s when none) plus 5 s |
| `rate` | no | requests per second per client IP and burst, overriding the edge default for this prefix |

A component's resource-contract paths (`/{domain}/{name}/_authz/*`, `/_shares/*`, `/_lifecycle/*`) are under its prefix and so travel with it ([20](20-authorization-provider.md#port-contract)).

### The route table

`build/edge/routes.json`, generated, never edited:

```json
{
  "version": 1,
  "source": { "brickkit_yaml_sha256": "…" },
  "routes": [
    { "path": "/erp/sales/", "component": "erp/sales", "version": "3.0.0",
      "service": "erp-sales-3-0-0", "port": 8084,
      "auth": "required", "body_limit": 1048576, "timeout_s": 20,
      "rate": { "per_ip_rps": 100, "burst": 200 } }
  ]
}
```

- `service` is the member's own versioned service name, which resolves standalone, inside a shell and on Kubernetes ([0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md), [27](27-shells.md#port-contract)); never a shell's name. A version bump changes the table, which is why it is generated.
- Matching is by longest prefix; the fallback `/` comes last.
- Two installed components claiming the same prefix fail generation and both are named.
- A component whose `mode` keeps it from running contributes no route.

### Edge settings

One project file (planned `infra/edge.yaml`, read by be-ops) holds what is not per route: host names and TLS (certificate files or ACME on Docker, `tlsSecret` or cert-manager on Kubernetes), the generator, default rate limits, trusted proxies in front of the edge, the CORS allow-list, the object-storage host name. Defaults:

| Setting | Default |
|---|---|
| rate, every route | 100 requests/s per client IP, burst 200 |
| rate, `/api/iam/*` | 10 requests/s per client IP, burst 20 (login and token endpoints) |
| client read timeout | 30 s for the whole request (as the server, [16](16-deadlines-and-retries.md)) |
| idle connection | 120 s |
| CORS | off; an allow-list of origins only when a separate origin exists (an H5 subdomain, a partner) |

### What the edge does to every request

| Direction | Action |
|---|---|
| in | drop client-supplied `X-Request-Id`, `traceparent`, `tracestate`, `baggage` and every `be-*` header; replace `X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Host` with its own values (keeping only those from trusted proxies) |
| in | start a trace when edge tracing is on; the service then uses the trace id as the request ID ([23](23-observability.md#port-contract)) |
| in | refuse a body above the route's `body_limit` with 413, a rate above the route's `rate` with 429, an unknown path with 404 |
| out | wait for response headers at most the route's `timeout_s`, then 504; never retry a request that has a body |
| out | keep `X-Request-Id`, `Retry-After`, `Deprecation`, `Sunset` and `X-Data-As-Of` from the service unchanged |

Answers the edge produces itself (404, 413, 429, 502, 503, 504) carry the platform problem body ([15](15-user-api-and-errors.md#the-error-body)) served by a static error service, `domain: be`, reasons `NOT_FOUND`, `BODY_TOO_LARGE` and the three edge reasons of the platform table: `RATE_LIMITED` (`RESOURCE_EXHAUSTED`, 429), `UPSTREAM_UNAVAILABLE` (`UNAVAILABLE`, 502 and 503), `UPSTREAM_TIMEOUT` (`DEADLINE_EXCEEDED`, 504).

### Object storage through the edge

A browser uploads and downloads files with presigned URLs ([22-object-storage.md](22-object-storage.md#presigned-urls)). The edge forwards a separate host name (for example `files.<host>`) to the store with the `Host` header unchanged, no authentication and no body limit: the signature is the authorization, and it covers the host. Storage never shares the API host name, because a path prefix in front of the store would break the signature.

### Targets

| Target | Generator | What it writes |
|---|---|---|
| Docker, Podman | `traefik-file` (default) | `infra/traefik/dynamic/routes.yml`: routers, services and middlewares (`buffering` for the body limit, `ratelimit`, `headers`, the error service); Traefik watches the directory, so a regeneration needs no restart |
| Kubernetes | `k8s-ingress` | Ingress objects for the shared host name with one path rule per route, plus the controller's own objects for limits (Traefik `Middleware`, or ingress-nginx annotations), applied beside brickKit's generated manifests |
| Kubernetes | `gateway-api` (later) | `HTTPRoute` objects; limits through the implementation's policies |

brickKit 1.1.0 generates an Ingress only for a component with `expose: true` and one host name per component; it cannot share one host name among components by path. Until it can (a feature request is planned), be-ops writes these objects and the deployment applies them.

## Alternatives

| | Traefik (chosen) | nginx | Envoy Gateway | APISIX / Kong | Caddy | Cloud API gateway / load balancer |
|---|---|---|---|---|---|---|
| Footprint on one machine | small | smallest | medium | medium (needs etcd or PostgreSQL) | small | none on the machine |
| Dynamic configuration | Docker, file and Kubernetes providers, watched | reload | xDS, Gateway API | admin API | API, file | console or API |
| Rate limiting | per instance, in memory | `limit_req`, per instance | local, plus global with an extra service | plugins, several backends | plugin | built in, global |
| Kubernetes | IngressRoute, Ingress, Gateway API | ingress-nginx | Gateway API native | Ingress, CRDs | community | the cloud's |
| OpenTelemetry | built in | module | built in | plugin | built in | varies |
| Fits | one machine to a small cluster | customers who standardise on nginx | multi-node with global limits | API products with portals | small sites | customers already on a cloud |

Two policy questions with their own options:

| Question | Option | For | Against |
|---|---|---|---|
| Where is the token checked | in every service (chosen) | standalone deployment stays secure; defence in depth | every service verifies (cheap: local JWKS) |
| | only at the edge (ForwardAuth, JWT plugin) | one place | bypassing the edge or deploying a component alone opens everything |
| BFF | one for mobile only (chosen) | the phone needs aggregation and smaller payloads | the PC makes several calls per page |
| | one per channel, PC included | one call per page | a second aggregation layer to keep in step with every component |

## Why this choice

- **Derived beats hand-written**: brickKit's own design principles name hand-written gateway configuration as the example of a second copy that silently goes stale when a version changes. Versioned service names make that failure certain here.
- **Security does not depend on the edge.** "Every component runs on its own" includes running without our gateway in front of it.
- **The gateway is infrastructure, not a component** ([0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)): an official image plus generated configuration, swapped by choosing another generator.
- **Traefik is already there**, watches its file provider and needs no reload, and covers the whole middleware set in its free edition.

## Why not the others

- **nginx**: the smallest, but configuration changes need a reload and limits are per instance just the same; kept as a generator for customers who require it.
- **Envoy Gateway**: its advantage, global rate limiting, needs an extra rate-limit service and only pays off with several edge instances.
- **APISIX or Kong**: built for selling APIs (portals, consumer management); they add a configuration store and make the gateway something to operate, not configure.
- **Caddy**: simple, but weaker Kubernetes support and no built-in rate limiting.
- **A cloud gateway**: fine in front of the edge for a customer on that cloud, never instead of the generated routes, because it would be configured by hand.
- **Authentication only at the edge**: breaks principle 1.
- **A PC BFF**: one more layer that every component change has to reach, for a saving of a few parallel calls.

## When to switch

- **Several edge instances and a limit that must hold across them** (abuse, a contractual quota): a global rate limiter, which means Envoy Gateway with its rate-limit service or the cloud's gateway in front.
- **The external API opens** ([15](15-user-api-and-errors.md#versioning)): rate limits per API key at the edge; quotas stay in the service, counted in PostgreSQL windows against the key, without Redis ([0201](../02-decisions/02-permissions/0201-no-redis.md)).
- **A customer standardises on nginx or on a Gateway API controller**: that generator.
- **brickKit can share a host name by path**: generate Kubernetes routing through brickKit instead of be-ops.

## How to switch

- **Another gateway product**: set the generator in the edge settings and regenerate. The route table, the declarations and every component stay as they are; the end-to-end suite must pass against the new edge.
- **A global limiter**: add the limiter service to the infrastructure and point the generator's rate middleware at it; routes keep their `rate` values.
- **API keys**: the rate middleware gains a key source (the API key's identifier, once its shape is fixed in the authorization contract, [20](20-authorization-provider.md)); routes and components unchanged.

## Conformance tests

Planned suite `tools/be-acceptance/conformance/edge/`, run against each generator:

- **golden route tables**: a fixed set of `assembly.yaml` files and a `brickkit.yaml` produce exactly the expected `routes.json`, and each generator produces its expected files; after a version bump the service names follow;
- **end to end**, through the edge: an `auth: required` route without a token answers 401 (from the service); an unknown path 404; a body over the limit 413; a burst over the rate 429; every response carries `X-Request-Id`; a client-supplied `X-Request-Id` or `be-caller` never reaches the service or its logs; `/healthz`, `/metrics` and the gRPC ports are unreachable from outside; a presigned upload through the storage host name succeeds.

Tests written red first: be-ops "generates Traefik dynamic configuration from `assembly.yaml`" (no generator exists) and "a component upgrade changes the service name"; project end-to-end: "the login endpoint answers 429 per IP above its rate", "a body over the limit answers 413", "a forged `X-Request-Id` never reaches the logs". Gate (planned `edge-routes-fresh`): the generated table disagrees with `brickkit.yaml`; seen red on a stale table first.

## Decision records

- [0106 Infrastructure is not a component](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md): the gateway is an official image plus configuration.
- [0107 Authz and IAM addresses are shared variables](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md): member service names, never a shell's.
- [0108 One repository per shell](../02-decisions/01-architecture/0108-one-repository-per-shell.md): the BFF and the frontend never enter a shell.
- [0201 No Redis](../02-decisions/02-permissions/0201-no-redis.md): rate limits live at the edge; quotas in PostgreSQL.
- [0208 gRPC is the system plane; people use REST](../02-decisions/02-permissions/0208-grpc-is-the-system-plane.md): only REST is routed; gRPC ports never pass the edge.
- [0509 The edge only routes; authentication and authorization stay in the services](../02-decisions/05-runtime/0509-edge-only-routes.md): this document is its full analysis.
- Planned, not yet numbered: "edge routes are generated from declarations".

## Known limits

- **Rate limits count per edge instance**; with two instances a client gets twice the limit until a global limiter exists.
- **A family-level prefix admits one member**: `/integration/im/**` is declared by the IM member, so two IM members installed together collide until each declares its own sub-prefix.
- **Kubernetes routing is generated outside brickKit** until brickKit can share a host name by path.
- **The Traefik dashboard is insecure** (`api.insecure: true`) and for development only; production protects or disables it.
- **Nothing is generated today**: until the generator lands, a public path reaches a component only through ad-hoc configuration.
