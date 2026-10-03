[English](18-edge.md) · [中文](../../zh/04-foundations/18-edge.md)

# Edge

Everything between a browser, the mobile app or an external system and a component's REST port: where routes come from, what the edge does to a request on the way in and out, what it must never do, and how one set of declarations becomes Traefik container labels on Docker and Podman and brickKit Ingress paths on Kubernetes. For whoever adds a public path, changes the gateway, plans the external API, or proposes moving authentication to the gateway.

## Scope

- **In:** TLS termination; routing by path prefix; how be-ops turns route declarations into deploy-entry fields; body limits, timeouts and coarse rate limits at the edge; the request ID and the start of a trace; stripping headers a client must not set; CORS; where API keys will be rate-limited; HTTP caching at the edge; the BFF policy; reaching object storage from a browser.
- **Out:** token verification and authorization, which stay in every service ([21-identity-provider.md](21-identity-provider.md), [20-authorization-provider.md](20-authorization-provider.md)); the shape of user requests and errors ([15-user-api-and-errors.md](15-user-api-and-errors.md)); route deadlines and server timeouts ([16-deadlines-and-retries.md](16-deadlines-and-retries.md)); gRPC, which never passes the edge ([14-system-rpc.md](14-system-rpc.md)); trace propagation inside the system ([23-observability.md](23-observability.md)); how deployment files are generated (`brickkit docs 01-three-layers/03-deploy-yaml`).

## Choice

- **Routes are derived, never hand-written.** Each component declares its public path prefixes in `edge_routes` in its `assembly.yaml`, and every path of its OpenAPI contract lies under one of them. be-ops turns the declarations into fields of the deploy entries brickKit already reads, so brickKit resolves every service name and version itself:
  - **Kubernetes**: the entry's `expose: true`, `hostname`, `tlsSecret` and `paths` (the declared prefixes). brickKit generates one Ingress per component (named `<scope>-<name>`, switched to the new version only after its rollout), matching by path segment, so `/erp/sales` never takes `/erp/salesman`.
  - **Docker and Podman**: Traefik router `labels` on the entry. The rule is bounded by path segment, ``Host(`app.example.com`) && PathRegexp(`^/erp/sales(/|$)`)``, never a bare `PathPrefix`, which compares strings. Traefik joins the project network named by the deploy file's top-level `network:` and discovers the containers through its Docker provider; the labels travel with the container.
  - A gate fails when the generated fields disagree with the declarations, or an OpenAPI path lies outside every declared prefix.
- **Traefik is the default edge**: already deployed by `make up` (3.2 or later), small, discovers labelled containers, has OpenTelemetry tracing built in. On Kubernetes any Ingress controller that merges the Ingresses of one host works (Traefik, nginx-ingress, HAProxy).
- **The edge does**: TLS; routing by longest path prefix; a body limit per route; edge timeouts derived from the route deadline; coarse per-IP rate limits; starting the trace and the request ID; stripping internal and spoofable headers; a CORS allow-list only for a separate origin.
- **The edge does not**: authenticate as the only gate, authorize, apply data scopes, route on business content, retry a non-idempotent request, or cache API responses. Every service verifies the token itself, so bypassing the edge or deploying a component alone never weakens security ([0509](../02-decisions/05-runtime/0509-edge-only-routes.md)).
- **Never routed**: gRPC ports; `/healthz`, `/readyz`, `/metrics`, `/_be/info`; internal paths a component leaves out of `edge_routes` on purpose (`/authz/bundle`, the JWKS, the Casdoor webhook).
- **BFF**: the mobile app keeps `infra/bff-mobile`; the PC frontend calls each component's REST directly and completes names with the owner's `BatchGet`; there is no PC BFF.
- **Same origin by default**: the frontend and the APIs share one host name through the edge, so no CORS. Static assets are served by the frontend's own container with cache headers; the edge caches nothing.

**Status**: in place: Traefik v3.0 with the Docker and file providers (`infra/traefik/`), the project network in `deploy.yaml`, and `edge_routes` declared by all fourteen components. Nothing reads `edge_routes` yet, and the edge applies no middleware at all (no limits, no timeouts, no header stripping). brickKit 1.3 added the two platform pieces this design uses: `paths` on a deploy entry (path routing on one host name on Kubernetes) and member `expose` through a shell; it generates no gateway on Docker by design and recommends Traefik labels. Decided (lands with the 3.0.0 sweep): Traefik 3.2 or later, the be-ops generator for `paths` and labels, the middleware set, the freshness gate. Later: rate limits per API key (with the external API), a global rate limit across edge instances, a Gateway API generator.

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

### What be-ops generates

be-ops reads every installed component's `edge_routes`, sorts the prefixes, refuses two components claiming the same prefix (naming both), and writes these fields into each deploy file (`deploy.yaml`, every `deploy.<env>.yaml`); it owns exactly these fields and the `traefik.*` label keys, and leaves everything else in the entry alone. A component whose `mode` keeps it from running contributes nothing.

| Target | Fields written on the component's entry | Example for `erp/sales`, prefix `/erp/sales/**` |
|---|---|---|
| Kubernetes | `expose: true`, `hostname` and `tlsSecret` from the edge settings, `paths` | `paths: [/erp/sales]` |
| Docker, Podman | `labels`: one router per prefix, its service on the component's main port, the shared middleware chain, the route's own limits | see below |

```yaml
# deploy.yaml (generated fields of one entry; target: docker)
- id: erp/sales
  labels:
    traefik.enable: "true"
    traefik.http.routers.erp-sales-0.rule: Host(`app.example.com`) && PathRegexp(`^/erp/sales(/|$)`)
    traefik.http.routers.erp-sales-0.priority: "10"              # the prefix length: longest prefix wins
    traefik.http.routers.erp-sales-0.service: erp-sales
    traefik.http.routers.erp-sales-0.middlewares: be-edge@file,erp-sales-0-limits
    traefik.http.middlewares.erp-sales-0-limits.buffering.maxRequestBodyBytes: "1048576"
    traefik.http.services.erp-sales.loadbalancer.server.port: "8084"
```

- Router and service names are `<scope>-<name>`, never versioned, and Traefik reaches the container by its address on the project network: an upgrade changes no label. On Kubernetes brickKit puts the versioned Service behind the Ingress itself.
- **Shell members.** A member's own `labels` do not apply while a shell hosts it, so be-ops writes the member's routers on the member's entry (used when it runs alone) and also on the shell's entry with the member's port as the service port (used while the shell runs); only one of the two containers exists at a time. On Kubernetes a member's `expose`, `hostname` and `paths` work through the shell: the member gets its own Ingress pointing at its own Service, which selects the shell's Pod ([27](27-shells.md#port-contract)).
- **Same host, one certificate.** On Kubernetes every entry sharing the edge host name carries the same `tlsSecret`; brickKit refuses the same path under one host twice, naming both components.
- The frontend declares `/**`: its entry gets no `paths` on Kubernetes (the whole host, "everything else") and the lowest router priority on Docker.

### Edge settings

One project file (planned `infra/edge.yaml`, read by be-ops) holds what is not per route: host names and TLS (certificate files or ACME on Docker, `tlsSecret` or cert-manager on Kubernetes), default rate limits, trusted proxies in front of the edge, the CORS allow-list, the object-storage host name. be-ops renders the shared middleware chain `be-edge` from it (header stripping, the request ID, the default rate limit, the error service): on Docker as a Traefik file-provider file with no service name in it, so it never goes stale; on Kubernetes as the deploy file's `k8s.ingressAnnotations`, which brickKit writes onto every Ingress. Defaults:

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

| Target | What be-ops writes | What brickKit generates from it | Limits |
|---|---|---|---|
| Docker, Podman | Traefik router `labels` on each entry; `infra/traefik/dynamic/edge.yml` with the `be-edge` chain | container labels, as written; the project network is `external` and checked before `up` | per route, in the labels (`buffering`, `ratelimit`) |
| Kubernetes | `expose`, `hostname`, `tlsSecret`, `paths` on each entry; `k8s.ingressAnnotations` for the shared chain | one Ingress per component, named `<scope>-<name>`; `appProtocol` on Service ports from the declared `protocol` | the controller's own objects referenced by the shared annotations (Traefik `Middleware`, or ingress-nginx annotations); the same for every route |
| Kubernetes | `gateway-api` (later) | `HTTPRoute` objects written by be-ops | the implementation's policies |

Every user-plane path is served under its own prefix: the edge never rewrites a path, so the request reaches the component as the browser sent it.

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

- **Derived beats hand-written**: brickKit's own design principles name hand-written gateway configuration as the example of a second copy that silently goes stale when a version changes. Versioned service names make that failure certain here, which is why the generated fields name no service: brickKit resolves it on Kubernetes, and Traefik finds the labelled container on Docker.
- **brickKit already owns the deployment files**: writing routes into the entries it reads keeps one generator of Ingresses and containers, instead of a second set of objects applied beside brickKit's.
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
- **A customer's cluster controller builds one load balancer per Ingress** (GKE's built-in one): it cannot merge the per-component Ingresses of one host; be-ops then writes one Ingress (or `HTTPRoute`) of its own for the host and the entries carry no `expose`.

## How to switch

- **Another gateway product**: on Kubernetes, any Ingress controller that merges one host's Ingresses: change `k8s.ingressClass` and the shared annotations; on Docker, a gateway with a Docker label provider gets its own label renderer in be-ops. The declarations and every component stay as they are; the end-to-end suite must pass against the new edge.
- **A global limiter**: add the limiter service to the infrastructure and point the generator's rate middleware at it; routes keep their `rate` values.
- **API keys**: the rate middleware gains a key source (the API key's identifier, once its shape is fixed in the authorization contract, [20](20-authorization-provider.md)); routes and components unchanged.

## Conformance tests

Planned suite `tools/be-acceptance/conformance/edge/`, run against each generator:

- **golden deploy fields**: a fixed set of `assembly.yaml` files and a deploy file produce exactly the expected `paths`, `labels` and annotations per target; a version bump changes no generated field; a shell member's routers appear on both its entry and the shell's;
- **end to end**, through the edge: an `auth: required` route without a token answers 401 (from the service); an unknown path 404; `/erp/salesman` is not routed to `erp/sales`; a body over the limit 413; a burst over the rate 429; every response carries `X-Request-Id`; a client-supplied `X-Request-Id` or `be-caller` never reaches the service or its logs; `/healthz`, `/metrics` and the gRPC ports are unreachable from outside; a presigned upload through the storage host name succeeds.

Tests written red first: be-ops "generates Traefik labels and Kubernetes `paths` from `assembly.yaml`" (no generator exists) and "a prefix is bounded by a path segment"; project end-to-end: "the login endpoint answers 429 per IP above its rate", "a body over the limit answers 413", "a forged `X-Request-Id` never reaches the logs". Gate (planned `edge-routes-fresh`): the generated fields of a deploy file disagree with the declarations, or an OpenAPI path lies outside every declared prefix; seen red on a stale deploy file first.

## Decision records

- [0106 Infrastructure is not a component](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md): the gateway is an official image plus configuration.
- [0107 Family addresses are `$endpoint:` references](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md): the same principle for addresses, brickKit resolves every service name.
- [0108 One repository per shell](../02-decisions/01-architecture/0108-one-repository-per-shell.md): the BFF and the frontend never enter a shell.
- [0201 No Redis](../02-decisions/02-permissions/0201-no-redis.md): rate limits live at the edge; quotas in PostgreSQL.
- [0208 gRPC is the system plane; people use REST](../02-decisions/02-permissions/0208-grpc-is-the-system-plane.md): only REST is routed; gRPC ports never pass the edge.
- [0509 The edge only routes; authentication and authorization stay in the services](../02-decisions/05-runtime/0509-edge-only-routes.md): this document is its full analysis, including that routes are generated into deploy entries.

## Known limits

- **Rate limits count per edge instance**; with two instances a client gets twice the limit until a global limiter exists.
- **A family-level prefix admits one member**: `/integration/im/**` is declared by the IM member, so two IM members installed together collide until each declares its own sub-prefix.
- **Per-route limits on Kubernetes are not per route.** brickKit writes `k8s.ingressAnnotations` onto every Ingress, so a route's own `body_limit` or `rate` cannot differ from the default there; on Docker the labels carry them. A per-entry annotation field in brickKit would close this (a feature request, once measured to matter).
- **One Ingress per component** needs a controller that merges the Ingresses of one host (nginx-ingress, Traefik and HAProxy do; GKE's built-in controller does not).
- **The generated labels live in the deploy files.** A personal `deploy.local.yaml` replaces `deploy.yaml` wholesale, so after regenerating, `brickkit local refresh` carries the new labels into it.
- **Traefik 3.1 and older cannot talk to Docker 29** (their Docker client is too old); the edge needs 3.2 or later.
- **The Traefik dashboard is insecure** (`api.insecure: true`) and for development only; production protects or disables it.
- **Nothing is generated today**: until the generator lands, a public path reaches a component only through ad-hoc configuration.
