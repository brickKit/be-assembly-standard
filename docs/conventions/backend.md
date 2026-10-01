[English](backend.md) · [中文](backend.zh.md)

# Backend conventions

How Go and Python components (and the TypeScript BFF, where noted) are written in this project. Configuration keys and values are in [configuration.md](configuration.md); ports and schemas in [registries.md](registries.md); the reasons behind the choices in [../decisions/README.md](../decisions/README.md).

## Two principles

1. **Every component is a complete brickKit component and runs on its own.** Every call to another component goes over real gRPC or HTTP, every port in `extraPorts` really listens, and `brickkit up --focus <id>` brings the component up with nothing but what it depends on.
2. **Merging happens only at deployment.** A shell turns N processes into one and does nothing else: no business logic, no shared tables, no shared schema, no merged API port, no component importing another.

"They end up in the same shell anyway, so call the function directly" breaks the first principle, and once the boundary is gone inside a shell, the component can never be deployed on its own again.

## Stack

The stack is fixed; it is not chosen per component.

| | Go | Python |
|---|---|---|
| HTTP | Gin, through `besdk.NewGinEngine(rt)` | FastAPI, through `besdk.new_fastapi_app(rt)`; one programmatic uvicorn `Server`, one process, one event loop |
| SQL | `database/sql` + `pgx/v5/stdlib` + `sqlc` | `asyncpg` + hand-written SQL |
| gRPC | `grpc-go` | `grpc.aio` |
| Migrations | `golang-migrate`, raw `.sql` | `yoyo-migrations`, raw `.sql` |

Never: Echo, Fiber, chi or a bare `ServeMux`; GORM; `lib/pq`; Flask or Django; synchronous `grpc`; SQLAlchemy; alembic; gunicorn or more than one worker. The migration tool is the same within a language, so every component of that language carries the same migrate entrypoint in its image and the same migration targets in its Makefile.

The TypeScript BFF (`infra/bff-mobile`) runs on Node and never enters a shell. The frontend is Vue 3: Ant Design Vue 4 + vxe-table on PC, Uni-app + wot-design-uni on mobile. Every `package.json` pins exact versions; the frontend rules are in [frontend.md](frontend.md).

**Choosing a library version**: where you are free to choose, match what the system already has; where a dependency chain forces a newer version, follow it.

## Repository layout

```
<repo>/
├── component.yaml              read by brickKit
├── assembly.yaml               read by be-ops: permissions, data_scopes, menus
├── contracts/                  <name>.proto, <name>.openapi.yaml, events/<name>.events.json
├── gen/<domain>/<name>/        generated contract package, its own Go module (Go only)
├── backend/
│   ├── module/module.go        the only entry point: New(ctx, rt)
│   ├── cmd/server/main.go      one line: besdk.RunStandalone(module.New)
│   └── internal/{http,grpc,…}
├── migrations/                 001_<name>.up.sql / .down.sql
├── Dockerfile
└── Makefile
```

Python: `backend/app/module.py` (`create_module`), `backend/app/main.py` (one line), REST handlers in `backend/app/http/`, gRPC handlers in `backend/app/grpc/`. The BFF keeps its resolver map in `src/resolvers/` and nothing else there.

## Module entry

```go
// backend/module/module.go
func New(ctx context.Context, rt *besdk.Runtime) (*besdk.Module, error)

// backend/cmd/server/main.go
besdk.RunStandalone(module.New)
```

```python
# backend/app/module.py
async def create_module(rt: Runtime) -> Module: ...
# backend/app/main.py
besdk.run_standalone(create_module)
```

The module returns its HTTP handler (built with `besdk.NewGinEngine(rt)`), its gRPC registration and its `Start` / `Stop` functions. Migrations are not part of the module: `component.yaml` declares the migration command, and brickKit runs it from the component's own image before the service starts (`Module.Migrations` is no longer read by the SDK; leave it empty). It never listens on a port: `RunStandalone` does when the component runs on its own, the shell does when it is merged. Both call the same `New`.

A shell is `shell.Main("<name>", shell.Registry{...})` in Go and `besdk.shell_runner.main(name, registry)` in Python. The registry maps each member's ID to its `New`, and lists exactly the members in the shell's `shell.members`. brickKit runs every member's migration with that member's own image before the shell starts, so each member still has its own image.

## The runtime is the only way in

Everything a module needs arrives in `rt`; module code reads nothing from the process.

- **Configuration**: `rt.Config.String(key)`, `StringOr(key, def)`, `MustString(key)` (also `Int*`, `Bool*`), with the exact upper-snake key from `configSchema`.
- **Dependency addresses**: `rt.Config.Endpoint(dep, extra)` returns the address with `http://` removed and whether it exists; `MustEndpoint` for a required dependency. The platform always writes `http://` in front, gRPC ports included; dialling `http://host:9094` fails with an error that points at name resolution. For gRPC pass the port name: `Endpoint("mdm/customer", "grpc")`; with `""` you get the HTTP port, and gRPC fails with a protocol error while TCP connects fine.
- **An optional dependency that is absent has no variable at all.** `Endpoint` returns `ok == false`; the module degrades. Never index the environment directly.
- **Connections**: `rt.DB` and `rt.NATS`. `RunStandalone` or the shell builds them from the `PG_*` keys and `NATS_URL` (`besdk.PGDSN(cfg)`, `besdk.NATSURL(cfg)`); a module never opens its own pool.
- **Object storage**: `rt.Config.S3URL()`, a full URL.
- **Logging, tracing, metrics**: `rt.Logger`, `rt.Tracer`, `rt.Meter`, and `rt.Registry`, a Prometheus registry of the module's own.

Python mirrors these names in snake case (`rt.config.endpoint`, `must_endpoint`, `s3_url`, `besdk.pg_dsn`); TypeScript in camel case (`config.endpoint`, `mustEndpoint`).

## Merge safety

Three questions, all answered "no", before code is done:

1. **Does module code read the process environment** (`os.Getenv`, `os.environ`)? One process has one environment: after a merge, members overwrite each other's `PG_SCHEMA` and every other key, and a module silently reads and writes another component's schema.
2. **Does it initialise anything process-wide?** `otel.SetTracerProvider`, `logging.basicConfig`, signal handlers, the default Prometheus registry, `gin.SetMode` (a package variable: one module in debug mode puts every module in debug mode and leaks stack traces to clients). The last initialiser wins and everything stays green; the default registry panics on the second module. Use what `rt` provides.
3. **Does it exit the process** (`log.Fatal`, `os.Exit`, `sys.exit`)? One module's recoverable error takes the whole shell down. Return an error.

Also never call `gin.New()` (the engine loses the SDK's middleware: request IDs, tracing, RED metrics, the access log, panic recovery and error mapping, with no error), `sql.Open()` or `Listen` from a module. `make module-check` checks all of this.

## Health check and image

- `/healthz` reports only that this process is alive. Never check the database, NATS, authz or another component in it: one downstream hiccup would mark every upstream unhealthy and restart them, and in a shell restart every member at once.
- `/healthz` answers both `GET` and `HEAD`. The SDK's engine registers both; don't register your own.
- Startup grace (`startPeriodSeconds`): Go components leave the default (60); Python 120; Node 90; shell images 300.
- The base image has `/bin/sh` and `wget` (`alpine` for Go, `python:3.12-slim`; be-sdk-python needs Python 3.12 or later for Python): the health check runs through a shell. On `scratch` or distroless the component logs "ready" and the platform reports it unhealthy forever. Check: `docker run --rm <image> sh -c 'wget --version'`.

## Permissions

- A permission key is `<domain>.<aggregate>.<action>` (`erp.sales.confirm`); its domain prefix equals the component's domain. Keys are declared in `assembly.yaml` under `permissions` (`key`, `title`, `type: page|action`); a `menus[].permission` must be one of the component's own keys. New keys are appended to `registry/permissions.tsv` and never renamed ([registries.md](registries.md#permission-keys)).
- **The permission key is part of the route registration.** Go: `besdk.GET(r, path, permKey, h)` (and `POST`, `PUT`, `PATCH`, `DELETE`); Python: `besdk.get(router, path, perm, handler)`; BFF: every resolver wrapped in `requirePermission(perm, resolver)`. A public route says so with `besdk.Public`; "any logged-in user" is `besdk.Authenticated`. A business route registered with Gin's bare `r.GET` or FastAPI's bare `@app.get` has no check at all and shows no symptom; `make gates` scans for it.
- The check is an in-process map lookup. The SDK polls infra/authz's bundle (`AUTHZ_BUNDLE_URL`) about every 15 seconds; no component holds a permission table, and the JWT carries only identity (`sub`, roles, `dept_path`, `org_id`), never permission keys. Until the bundle has loaded once, protected routes answer `503` while `/healthz` stays healthy. A token issued before the user's roles changed answers `401 token_stale`; the frontend refreshes the token silently and retries the request exactly once.
- Permissions are a pure union: there is no deny. "Everything except X" is a role without X.
- The frontend shows a route only when it is installed (`GET /api/tenant/features`), the user may use it (`GET /api/me/permissions`) and the user is logged in. Checking only the first gives a visible menu item that opens a full-page 403. Hiding something in the frontend is never the security boundary: the backend rejects the data ([frontend.md](frontend.md#features-permissions-and-menus)).

## Data scopes

- `assembly.yaml` always has a `data_scopes` section. A component without row-level scoping writes `data_scopes: none`; leaving the section out is an error in be-ops, deliberately: a security setting that defaults to "off" when omitted would be a silent leak.
- Dimensions in use: `org` (prefix match on `dept_path`, no copy of the org tree), `owner` (equals the caller's `sub`), and resource dimensions such as `warehouse` and `legal_entity` (the caller's granted IDs). be-ops collects them into `registry/data-scopes.tsv`.
- `besdk.ScopeOf(ctx)` gives the filter computed from the caller's token; repository methods take it and pass it as parameters of a static `sqlc` query. No PostgreSQL row-level security, no dynamic SQL.
- When a list combines `owner` and `org` with OR, both operands must come from the caller's real scope; one operand left at "match all" makes the whole condition match everything.
- Every component with a data scope has a test that creates rows owned by two different identities and asserts that one identity's query returns none of the other's rows ([testing.md](testing.md#l2-business-rule-tests)).

## Calling other components

- On a path that serves a user request, call with `besdk.UserClient(ctx, rt.Config, dep, "grpc")`: it forwards the caller's token, so the callee applies the caller's data scope.
- `besdk.SystemClient(rt.Config, dep, "grpc")` carries the component's own identity and bypasses data scopes. It is allowed only in `Start()` and in event handlers. On a user request path the response silently contains more data than the user may see; `make gates` scans for it.
- Related data comes through the owner's `batchGet`, never through a cross-schema JOIN. Every aggregate root offers `batchGet`.
- No component imports another. The only shared code is `be-sdk-*` and a component's generated contract package `gen/<domain>/<name>`, published as its own Go module and imported directly. Copying the generated code instead registers the same proto file twice in one process, and the second registration panics once caller and callee share a shell.
- A component that aggregates many others (the BFF, notification routing) declares every one of those dependencies `optional: true`; a single required one keeps it from starting wherever that component wasn't bought. A component the customer didn't buy is simply not added to the project.
- authz and iam are not dependency edges: their addresses are the configuration keys `AUTHZ_BUNDLE_URL` and `IAM_JWKS_URL` ([configuration.md](configuration.md#dependency-addresses)).

## Database

- Every component has its own schema and role. Switching is transaction-scoped, always: `besdk.WithTx(ctx, rt.DB, role, schema, fn)` (Python `with_tx`) runs `SET LOCAL ROLE` and `SET LOCAL search_path` inside the transaction. A `SET` without `LOCAL` stays on the pooled connection, and the next borrower runs its queries against your schema: no error, no crash.
- No JOIN across schemas.
- Migrations are raw SQL. The migration-state table lives in the component's own schema (`golang-migrate` with `x-migrations-table` and the `search_path`; `yoyo` with the schema parameter). Every migration can run twice in a row (`make migrate-idempotent`).
- A table that can grow without bound has `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `version BIGINT NOT NULL DEFAULT 1` and `status TEXT NOT NULL`, and is partitioned from the start. A partitioned table's primary key and unique indexes include the partition key; archived partitions are detached with `DETACH CONCURRENTLY` into the component's own `<schema>_archive`.
- Because a unique index on a partitioned table includes the partition key, `INSERT` cannot detect a duplicate whose partition key differs (two deliveries a few microseconds apart). Deduplicate with an explicit lookup on the business key, then insert, in one transaction.
- Rows that work as a queue (outbox, retries) are claimed atomically: `UPDATE … WHERE id IN (SELECT … FOR UPDATE SKIP LOCKED) RETURNING …`. A plain `SELECT` then `UPDATE` publishes every row twice as soon as two replicas poll.
- Money crosses every boundary as a decimal string, never a float. `List` endpoints page with a cursor and take no `offset`; list queries get a default time window (the SDK's `ListWindow`, the last 90 days) unless the caller narrows it.

## Events and cross-component writes

- A producer writes the event to its outbox in the same transaction as the business change (`besdk.PublishOutbox`), and a background pump publishes it to NATS.
- A consumer is idempotent and accepts only a strictly greater `version` per aggregate, so duplicates and reordering are harmless. Event headers carry `trace_id`, `causation_id` and `hop_count`; `hop_count > 5` or a detected cycle goes to the dead-letter queue.
- Event names are `<domain>.<aggregate>.<action>.v<n>`. Event schemas only grow: adding a field or a new event is fine; deleting a field, changing a type or removing a subject fails `make gates`. Consumers read leniently.
- Every cross-component write takes an `idempotency_key` and claims it first with an atomic `INSERT … ON CONFLICT DO NOTHING`, doing the real write only after the claim succeeds. "Check whether it exists, then insert" lets two concurrent requests both execute. The callee also offers `GetStatus`.
- After a synchronous call times out, never compensate straight away: call `GetStatus` first. If that also times out, record it in a local pending-reconciliation table for the scheduled reconciliation. A compensation that fails more than three times marks the transaction `SUSPENDED` and opens an exception task in infra/workflow.

## Contracts

- `contracts/` is the source of truth for the interface: `.proto` for gRPC, `.openapi.yaml` for external REST, `events/*.json` for events.
- Contracts only grow. `make contract-check` rejects breaking `.proto` / OpenAPI changes; `make gates` rejects breaking event changes.
- The frontend's types and request functions are generated from the contracts, never hand-written.
