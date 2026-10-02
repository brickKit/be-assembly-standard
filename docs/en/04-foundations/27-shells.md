[English](27-shells.md) · [中文](../../zh/04-foundations/27-shells.md)

# Shells

What it takes for N components to share one process without noticing: which members a shell may hold, what is shared in the process and what never is, and the checklist every SDK feature passes before it is called merge-safe. For whoever changes a shell, the SDK's shell launcher, or adds a process-level feature to an SDK.

## Scope

- which components can be merged into one shell (one language);
- the shell invariants: the four things that are process-wide, and everything that is per member;
- the merge-safety checklist, item by item, with the test that proves each;
- when not to use a shell.

Not covered: how a shell repository is laid out, released and pinned ([0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md), the `brickkit-component` skill); how a deploy file chooses which members a shell hosts (the `brickkit-deploy` skill); the rules module code follows ([02-backend.md](../01-conventions/02-backend.md#merge-safety)).

## Choice

**A shell merges only components written in one language.** Each component may be written in its own language: what joins a project is the language-neutral component protocol and its black-box conformance suite ([02-languages-and-component-protocol.md](02-languages-and-component-protocol.md)). Merging is different: a shell compiles its members' code into one process with one runtime, so it exists only for a language that has an official SDK **and** that SDK's shell launcher. A component in any other language joins the project, passes conformance and runs standalone; it can be merged only once its language has both. Today: Go shells `be/go-core`, `be/go-infra`, `be/go-backoffice`; one Python shell `be/py-render`; TypeScript has no shell launcher, so the BFF runs on its own.

**A shell only turns N processes into one** (principle 2). It adds no routes, no logic and no calls between members; members still call each other over real HTTP or gRPC on their own ports ([0101](../02-decisions/01-architecture/0101-no-imports-between-components.md)). The launcher is SDK code; a shell repository is a member list ([0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)).

**The four shell invariants:**

1. **Exactly four things are process-wide**: the OpenTelemetry exporter and propagator (the launcher alone shuts the shared exporter down, after every member has stopped; stopping a member flushes only that member's own span queue); the permission bundle and the token verifier (JWKS); the physical database pool; the event-bus connection.
2. **Everything else is per member**: configuration, logger, tracer and meter providers, metrics registry, HTTP and gRPC servers, outbound connections, caches, jobs, authorization projection, advisory-lock keys.
3. **Each member has its own resource budget**: database connections, outbound concurrency, cache memory. One member exhausting its budget never starves another.
4. **Supervision behaves the same in both forms**: a member's failing background job is restarted with backoff in a shell exactly as standalone, and a member never stops or exits the process.

Running every member alone must give the same behaviour as running them merged; `brickkit up --ignore-shells` is how that is checked.

**Status**: in place: one repository and one member list per shell, one bundle and verifier per process, one metrics registry per member, members on their own ports with their own gRPC servers, transaction-scoped role switching. Decided (the 3.0.0 sweep and its SDK release): per-member connection budgets, per-member tracer providers, the aggregated `/metrics`, the SDK job supervisor, per-member outbound connections, collected configuration errors. Today a shell's spans all carry the shell's name, its pool is shared without limit (Go) or capped at 10 for everyone (Python), and a member whose loop fails stays stopped.

## Port contract

The shell launcher is part of each official SDK. What it promises, in any language:

- **Input.** brickKit passes `BRICKKIT_SERVED_MEMBERS` and `BRICKKIT_SERVED_MEMBERS_CONFIG` (one JSON value). The launcher starts exactly the members listed, each with only its own configuration keys; it refuses to start, naming the member, when a listed member is not compiled in or is compiled at another version, when a member's `PG_HOST`, `PG_PORT`, `PG_DATABASE`, `EVENT_BUS_URL`, `AUTHZ_URL`, `IAM_*` or `TENANT_ID` differs from the shell's (they back the four process-wide things), or when any member's configuration is invalid (all errors reported together).
- **Ports.** Each member listens on its own HTTP port and its own `extraPorts`, with its own gRPC server and interceptor chain. Addresses resolve by the member's own service name, which brickKit makes an alias of the shell ([04-configuration.md](../01-conventions/04-configuration.md#dependency-addresses)).
- **Database.** A shell requires PostgreSQL 16 or later; a standalone component keeps 14 as its floor. The shell logs in with its own `PG_USER`, a login role granted each member's runtime role `WITH INHERIT FALSE, SET TRUE`, so it holds none of their privileges. Per transaction it switches with `SET LOCAL ROLE` to the member's own runtime `PG_USER`, taken from the member's configuration and never derived from a schema name (never to an owner role, which the shell is never granted), sets a local `search_path` to the member's `PG_SCHEMA`, and sets `SET LOCAL application_name` to the member's ID, so `pg_stat_activity` counts each member's connections. Isolation between members is the SDK's job, not the database's: only the runtime's store issues `SET LOCAL ROLE`, and member code never issues `SET ROLE` (gate `identity-literal-scan`). The physical pool has the shell's `PG_POOL_MAX`; each member draws through a limit of its own `PG_POOL_MAX`, and what happens when that budget is used up is in [03-database.md](03-database.md).
- **Advisory locks** are transaction-scoped only, keyed by a hash of the member's schema plus the lock name and a hash of the lock's parts, so two members never contend on the same key ([10-local-transactions.md](10-local-transactions.md)).
- **Telemetry.** One tracer and meter provider per member with `service.name` = the member's component ID; every instrumentation (HTTP and gRPC servers and clients, outbound HTTP, consumers) is given the member's providers and the propagator explicitly, never the OpenTelemetry process globals, and the global tracer provider, a fallback only, carries the shell's own ID, so a span under that name reveals a missed instrumentation; one shared exporter, shut down only by the launcher after every member has stopped; one aggregated `/metrics` on the shell's port with a `component` label per member ([23-observability.md](23-observability.md)).
- **Health.** `/healthz` reports only that the process is alive; one member's dependency hiccup must not restart every member ([02-backend.md](../01-conventions/02-backend.md#health-check-and-image)).
- **Migrations** run from each member's own image before the shell starts, never inside the shell, each logging in with that member's own owner credentials (`PG_OWNER_USER` / `PG_OWNER_PASSWORD`, [08-schema-evolution.md](08-schema-evolution.md#the-migration-entry)); the shell's login role is never granted an owner role.

**The merge-safety checklist.** Every item an SDK feature touches is checked here before the feature is called merge-safe.

| Item | Risk in a shell | How it is kept safe | Proved by |
|---|---|---|---|
| Transaction identity | a `SET` without `LOCAL` leaks to the next borrower | `SET LOCAL ROLE`, `search_path` and `application_name`; a store bound to the member's identity; `SET ROLE` banned in member code | existing tests, store conformance |
| Transaction timeouts | a member role's `ALTER ROLE … SET` does not apply after `SET ROLE` | every transaction sets its timeouts with `SET LOCAL` | store conformance |
| Connection pool | one unlimited shared pool; one member exhausts it | pool sized by the shell, a budget per member | "a member out of budget does not affect another" |
| Advisory locks | the same key collides across members; a session lock leaks | keys include the member ID; transaction-level only | "two members' locks do not block each other" |
| No network inside a transaction | — | the in-transaction mark travels with the call, not the process | "a gRPC call inside a transaction is refused" |
| gRPC client | a process-wide connection pool makes `be-caller` another member | outbound connections belong to the member | "in a shell `be-caller` is the calling member" |
| gRPC server | — | one server and interceptor chain per member | in place |
| HTTP server | no timeouts | one server setup with read-header, read, write and idle timeouts, the same standalone | server timeout tests |
| Deadlines and retry budgets | one member's retry storm exhausts another's budget | budgets are per outbound connection, and connections are per member ([16-deadlines-and-retries.md](16-deadlines-and-retries.md)) | rpc conformance |
| NATS connection | one connection; after a long outage everyone is lost | one connection with unlimited reconnect; durable and subscription names carry the member ID ([12-event-bus.md](12-event-bus.md)) | consume tests with two members |
| Outbox pump | N members polling five times a second while idle | adaptive polling | idle pump test |
| Event cursors, idempotency tables | — | in the member's own schema | decided |
| Job leases and slots | a shell and a standalone run of the same component duplicate work | tables in the member's schema coordinate across processes ([19-background-jobs.md](19-background-jobs.md)) | jobs conformance |
| Background job failure | stops forever in a shell, restarts the process standalone | the SDK supervisor, same in both forms | "a member's failed job is restarted" (red today) |
| Caches | a package-level map shared by members | caches created per member, gate on global maps ([17-caching.md](17-caching.md)) | cache conformance |
| Traces | every span under the shell's name; one member's stop shuts the shared exporter | a tracer and meter provider per member, passed explicitly with the propagator; only the launcher shuts the exporter down | "each member's spans carry its own `service.name`" (red today) |
| Logs | the SDK logs through the process default logger and loses the member ID | the SDK logs only through the member's logger | "a consume failure is logged with the member's ID" |
| Metrics | the default registry panics on the second member | one registry per member, aggregated with a `component` label | in place, plus aggregation tests |
| Bundle and JWKS | — | one per process (invariant 1); the authorization projection is per member, in its own schema ([20-authorization-provider.md](20-authorization-provider.md)) | in place |
| Edge routes and shared addresses | pointing at the shell's name breaks on every shell release | always the member's own service name ([0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)) | edge route tests, `service-hostname-scan` |
| Blast radius | a shell restart takes every member down at once | durable consumers keep their position; reconcilers resume in-flight flows; retry budgets absorb the gap | the shell's real-machine test after assembly |

## Alternatives

| | Strengths | Weaknesses |
|---|---|---|
| Every component its own process (no shell) | full isolation, separate scaling | one runtime per component: memory on a single machine |
| One-language shell, members on their own ports (chosen) | one runtime for N members; nothing changes for callers | members scale and fail together |
| Several processes in one container (a supervisor) | one image | saves nothing in memory; hides crashes from the platform |
| Merging with in-process function calls | fewer network hops | breaks "every component runs alone"; the component can never be deployed separately again |
| A shell mixing languages (embedded interpreters, cgo or FFI bridges) | fewer containers | two runtimes in one process, process-wide state from both, a launcher per pair of languages |
| GraalVM native images for JVM components | lower JVM memory without merging | per-component build work; reflection-heavy frameworks need configuration |
| `mode: disable` for components not needed | zero cost | only for components that are really unused |

## Why this choice

- Customers deploy on one machine; a runtime's memory floor is mostly fixed per process, so N members in one runtime save most of it (brickKit's shell rationale).
- Nothing changes for callers or for the members' code: a member listens on its own port and is reached by its own name, so merging and splitting are deployment decisions only.
- One language per shell keeps one runtime, one SDK version (all members resolve the same SDK version) and one launcher, and makes the four invariants enforceable in code.

## Why not the others

- **In-process calls**: the component could never run alone again, which is principle 1; forbidden by [0101](../02-decisions/01-architecture/0101-no-imports-between-components.md).
- **A supervisor in one container**: the memory is not shared, so nothing is gained, and the platform no longer sees which component crashed.
- **A mixed-language shell**: one process would host two runtimes and two sets of process-wide state, the exact failure the invariants exist to prevent.

## When to switch

Run a component standalone, or in its own shell, instead of in a shared one, when:

- it must scale separately (a hot read path, a CPU-bound renderer);
- its failures must not take its neighbours down;
- its resource profile differs sharply from its neighbours' (heavy memory, long CPU-bound work on Python's single event loop);
- memory is not the constraint (a Kubernetes cluster sized for separate Pods).

A component in a language without a shell launcher always runs standalone; a JVM language costs noticeably more memory per process, which is the caveat to weigh before choosing it.

## How to switch

- Which compiled-in members a shell hosts is chosen in the deploy file, `members:` under the shell's entry; moving a member out is a deploy-file edit, then `brickkit up`.
- Adding a member to a shell, or moving a member to a new version, is a commit and a release of the shell's own repository, then the submodule pointer and `brickkit upgrade be/<name>@<version>` here ([0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)).
- `brickkit up --ignore-shells` runs every member on its own; it is the split-back check after any shell change ([01-development-workflow.md](../01-conventions/01-development-workflow.md#running-it-for-real)).
- Shells for a new language arrive with that language's official SDK and launcher, never with a single component.

## Conformance tests

- Every red test in the checklist above, in every official SDK that has a launcher.
- In the component protocol suite ([02-languages-and-component-protocol.md](02-languages-and-component-protocol.md)): a fixture component runs standalone and inside a shell, and the black-box results are identical.
- Gates: `make module-check` (no process environment, no process-wide initialisation, no exit in module code); the shell member check (registered members equal `shell.members` equals the module requirements); `service-hostname-scan`.
- After assembly, on a real machine: sales → inventory `Reserve` over loopback gRPC inside `be/go-core` records the confirming user as the operator; then `brickkit up --ignore-shells` gives the same results.

## Decision records

- [0105 Any language, one protocol](../02-decisions/01-architecture/0105-any-language-one-protocol.md): each component chooses its language; a shell merges members of one language that has an official SDK and a launcher; the JVM's memory cost is a documented caveat.
- [0109 The rules live in a language-neutral component protocol](../02-decisions/01-architecture/0109-language-neutral-component-protocol.md): the component protocol, including the obligations of shell members.
- [0108 One shell, one repository, one image, one member list](../02-decisions/01-architecture/0108-one-repository-per-shell.md): also one SDK version per shell, and the launcher's checks at start.
- [0508 Background work runs only through the SDK's Jobs](../02-decisions/05-runtime/0508-background-work-only-through-jobs.md): supervised the same standalone and in a shell.
- [0101 Components never import each other](../02-decisions/01-architecture/0101-no-imports-between-components.md)
- [0102 One database, one schema per component](../02-decisions/01-architecture/0102-one-schema-per-component.md)
- [0103 One locked stack inside each language](../02-decisions/01-architecture/0103-locked-stack-per-language.md): what makes the per-member invariants enforceable in code.
- [0107 Authorization and identity are reached through shared variables](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)

## Known limits

- Members in a shell scale together and fail together; one member that crashes the process takes all of them down.
- All members of a shell use one SDK version; a member that needs a newer SDK moves the whole shell.
- Per-member memory is counted, not enforced: the operating system sees one process.
- Python members share one event loop; a CPU-bound member delays the others.
- A component written in a language without a launcher cannot be merged at all, only run standalone.
