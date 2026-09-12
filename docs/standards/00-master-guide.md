# BrickEnterprise Master Guide

> **This document is the long-lived framework and specification, not a task list.** Read it once and you have the entire skeleton of the project:
> which base resources to run, how ports and schemas are allocated, what each of the 62 components is, how the repositories are organized,
> what steps building a component goes through, how many phases there are, roughly what each phase does, and which disciplines run through the whole thing.
>
> **What step N of phase M actually does lives in that phase's own plan file** — those files are written one phase at a time, after
> the previous phase ships, feedback comes in, and (if needed) the Design Book gets updated.

**Goal:** on top of the brickKit platform, in the order "prove the platform first → then run a closed business loop → then build shells → then finish stocking the shelves," build an arsenal of 58 deliverable components, 5 shells, 2 delivery-critical-path tools (`be-ops` / `be-acceptance`), 3 language base libraries, and a one-command-managed base-resource environment.

**Architecture:** each component is its own Git repository plus a pure brickKit component that can be `brickkit up`'d standalone; this repository (`be-assembly-standard`) is both the standard assembly template and the arsenal index (using git submodules to remember every component repo's address and exact commit). Base resources are all Docker-deployed, split into "brickKit base resources (shape A)" and "out-of-band containers (shape B)," managed uniformly by this repository's `Makefile`. Merged deployment (a shell) only ever appears **as a delivery-time deployment choice**, after the platform is proven and the closed loop runs — it never reaches back to shape how development happens.

**Tech stack:** Go 1.22+ (skeleton and blood vessels), Python 3.11+ (brain and complex organs), TypeScript / Vue3 / Uni-app (skin and nerves), PostgreSQL 16, NATS 2.10 (JetStream), Traefik v3, Casdoor, RustFS, gRPC / Protobuf, OpenTelemetry, Docker Compose v2+.

**Specification source (single source of truth):** [`BrickEnterprise 设计书.md`](../../BrickEnterprise%20设计书.md) (the Design Book).
Always cite it with a section number (e.g. §3.5.1.1). **Where this document conflicts with the Design Book, the Design Book wins — then come back and fix this document.**
Platform-side behavior is governed by the 14 specification documents under the brickKit repo's `design/` (cited like `004 §3.9`).

---

## Document Map

```
be-assembly-standard/
├── BrickEnterprise 设计书.md          ← Design Book, the specification's single source of truth. Change the design here first
├── AGENTS.md                          ← AI assistant guide (index + prohibitions). CLAUDE.md is one line, @AGENTS.md
├── brickkit.yaml                      ← Assembly manifest's source of truth (one of the two in §9.1)
├── Makefile                           ← The sole entry point for base resources
├── registry/                          ← Port registry / schema registry / permission-key registry (check before writing any component.yaml)
├── docs/
│   ├── README.md                      ← ⭐ Triages by reader (deployer / developer / architect / customer). **The human entry point**
│   ├── ops/
│   │   └── 部署手册.md                ← The one document a deployer needs, self-contained; the five DB layers are in its §3
│   ├── standards/                     ← The always-valid regulatory documents (not phase-specific, not an execution plan)
│   │   ├── 00-master-guide.md            ← This file. Framework + specification + phase overview
│   │   ├── 01-documentation-standard.md  ← ⭐ How documentation should be organized, when to split, which two readers a component's docs serve
│   │   ├── 02-reference-implementation-standard.md ← ⭐ How to consult a real-world reference responsibly; recognizing a slot-family signal
│   │   ├── 03-ai-development-standard.md ← ⭐ Design-pattern judgment, session sizing, what a human reviews, rewrite vs. patch
│   │   ├── 04-testing-standard.md        ← ⭐ How tests are layered, the red-green rhythm, what to do when stuck — the single source of truth for everything testing-related
│   │   └── 05-data-construction-standard.md ← ⭐ The single source of truth for how seed data + test data are designed and how components collaborate on them
│   ├── plans/
│   │   ├── 01-阶段一-地基与第一块砖.md  ← Phase 1's complete task list
│   │   └── (02, 03… each written only once that phase is about to start)
│   ├── zh/                            ← The Chinese mirror of every Tier-1 document (AGENTS.md plus all six files under docs/standards/, this one included)
│   └── design/                        ← Component design plans, one per component, added incrementally as development proceeds
│       ├── README.md                  ← Index + when to write one, what it should look like
│       ├── _模板.md                   ← Template
│       └── mdm-customer.md            ← The first one, produced in Phase 1
├── components/<scope>/<name>/         ← Each component is a submodule
│                                        (each carries README.md + docs/手册.md + AGENTS.md + CLAUDE.md)
├── shells/{go,python}/                ← Shells, not under components/ (each carries an AGENTS.md)
└── tools/{be-ops,be-acceptance,be-sdk-go,…}/
```

### A component has four documents, none of which may be skipped

| # | File | Where | Reader | What it contains | When it's written |
|---|---|---|---|---|---|
| 1 | `docs/design/<repo>.md` | **the assembly repo** (this one) | whoever makes design decisions | **the component's design plan**: boundaries, tables it owns, contract surface, events, dependencies, partitioning/archival strategy, its place in the sync graph, open questions | **before** that component starts, revised as development proceeds |
| 2 | `README.md` | **root of the component repo** | whoever decides "should we install this, and how" | **basic information**: what it is, what it does, which base resources it needs, how to bring it up, how to use it, which open-source projects it drew on | first version when the skeleton is scaffolded; updated whenever functionality changes |
| 3 | `docs/手册.md` (manual) | **the component repo** | whoever has already installed it and wants to use it / change it | **the details**: exactly how to use each feature, the complete contract list, project structure, every config item, development and troubleshooting | grown incrementally as implementation proceeds |
| 4 | `AGENTS.md` + `CLAUDE.md` | **root of the component repo** | **the AI assistant** | **judgment criteria and prohibitions**: the component's identity, its boundaries (especially "not mine"), pitfalls and symptoms specific to it, self-checks before touching the code | skeleton written when the skeleton is scaffolded, calibrated once the task is finalized |

**Why four documents** (none of this is fussiness):

- Document 1 stays in the assembly repo, because **design decisions need to be readable side by side across components** — the only way to explain why `erp-sales` doesn't just query `mdm-customer`'s table directly is to lay the two design plans next to each other. It travels with the assembly repo; forking a component's repo out doesn't take it along.
- Documents 2, 3, and 4 must live **in the component's own repo**, because a component is an independent deliverable: when a customer receives the `erp-sales-acme` fork, they need to be able to run it from that directory alone.
- Documents 2 and 3 are split because **the readers are different**: the README is for someone deciding whether to install it, the manual is for someone who already has. Merging them into one forces both kinds of reader to skip past the other half.
- Document 4 is split from the first three because **AI and humans fail differently**. A human wouldn't write `grpc.Dial("http://host:9094")`, and wouldn't write `SET` where `SET LOCAL` was meant — these two don't deserve space in a README, but in the AI-facing document they must be **surfaced up front, with their symptom attached**. Conversely, an AI doesn't need the README's scene-setting and persuasion.

**Two hard rules for the AI-facing document** (breaking either degrades it into a second README):

1. **No "see above" / "as detailed in some section" references that require flipping back.** An AI may only ever receive a fragment of the file — every statement must be self-contained; pointing elsewhere requires a section number (`§13.3 Iron Rule 6`).
2. **Every prohibition carries its own "why" and "symptom if violated."** The symptom is the AI's only self-check anchor — the symptom for `SET` without `LOCAL` is "no error, no crash, just silently reading and writing someone else's data"; without writing that out, the AI has no way to notice it got this wrong.

**Structurally it's "index + leaves," never a whole-site digest:**

| Layer | File | Trait |
|---|---|---|
| Index | assembly repo root [`AGENTS.md`](../../AGENTS.md) | **Thin, stable, loaded every session.** Holds only the routing table (to do X → read Y), the most-common mistakes, the locked tables, the current phase, and things not to propose |
| Leaf | `components/<scope>/<name>/AGENTS.md` | **Self-contained.** Covers only this one component, assumes the reader hasn't read any other |
| Leaf | `shells/{go,python}/AGENTS.md` | The shell's four prohibitions + Iron Rules 2/5/6/**7** |

⚠️ **Deliberately not a "whole-site digest"** (brickKit itself has one, `AI-CONTEXT.md`). A digest covering 62 components is guaranteed to go stale, and a stale digest is worse than none — it reads as authoritative while actually being a six-month-old snapshot. In the index + leaves structure, whoever authors a piece is the one responsible for that piece.

For what exactly goes in each document and where the templates live, see **SOP-D** in §4.

---

## Global Constraints (implicitly included in every task)

Every item below is a hard constraint from the Design Book, quoted verbatim, not summarized. **Any task's implementation must satisfy this entire section at the same time.**

### A. The two non-negotiable development principles (§1.5)

1. **Every component is developed as a pure brickKit component and runs standalone.** Not one gRPC call is skipped; every gRPC port declared under `extraPorts` must actually `Listen`; every rpc in `contracts/*.proto` must be callable across processes (including `batchGet`); it must be possible to `brickkit up` this one component alone (together with its strong-dependency tree).
2. **Merging only ever happens at the deployment layer.** A shell may never let two component modules `import` each other directly, may never put two components' tables in the same schema, may never merge N modules' APIs into a single port, and may never contain any business logic of its own.

### B. Forbidden fields in `component.yaml`

- **An unknown key fails immediately, it is not silently ignored** (`002` §2.2.1). `asset` / `assembly_role` / `slot_name` / `edge_routes` / `menus` / `domain` / `tier` / `shell` / `requirements` / `expose` / `dependencies.strong|weak` / top-level `labels` **may never appear in `component.yaml`** — all of them go in the sibling `assembly.yaml`, declared under `artifacts` with `type: metadata` so they ship with the component (§3.5).
- **Versions must be exact**: `1.0.0` is fine; `^1.2` / `~1.2` / `1.2.x` / `latest` all fail immediately.
- **A component ID may appear only once within one `dependencies` block** (the variable name carries no version, so writing two versions silently overwrites one with the other; the CLI catches this at parse time).
- **There is no `role:{slot}` style dependency.** A dependency can only be an exact component ID plus an exact version.

### C. Platform-reserved variables (Appendix I)

`COMPONENT_ID`, `COMPONENT_VERSION`, **anything ending in `_ENDPOINT`**, and anything starting with `DATABASE_` / `REDIS_` / `MQ_` / `STORAGE_` / `SEARCH_` / `SMTP_` are all injected by the platform. A `configSchema` entry with one of these names is **skipped, with only a warning**.

This project therefore **locks** the following naming:

| Meaning | Must be named | Never named | Why |
|---|---|---|---|
| This component's PG schema | `pgSchema` | `databaseSchema` | `DATABASE_` is a reserved prefix |
| OTel Collector address | `otelBaseUrl` | `otelEndpoint` | `*_ENDPOINT` is a reserved suffix (§2.7.3) |
| JWT signature-verification public-key address | `iamJwksUrl` | `iamEndpoint` | Same reason, and business components never declare a dependency edge onto IAM |
| Enabled-component list (IAM adapter layer only) | `enabledComponents` | — | The value must be a **comma-separated string**; an array renders as `[a b c]` (§6.1) |

### D. Address format (§2.1)

**Component dependency addresses** (`{component-prefix}_ENDPOINT` and `{component-prefix}_{port-name}_ENDPOINT`) **always start with `http://`**, extra ports included:

```
ERP_SALES_ENDPOINT=http://erp-sales-1-0-0:8084          # deployment.port
ERP_SALES_GRPC_ENDPOINT=http://erp-sales-1-0-0:9094     # extraPorts, name: grpc
```

**There is no such thing as `grpc://`.** A gRPC client must `strings.TrimPrefix(v, "http://")` itself — `grpc.Dial("http://host:9094")` fails to connect, and the error points at name resolution, making the real cause extremely hard to guess. This goes into each language's base library, **done exactly once** (see Task 6 / Task 7).

⚠️⚠️ **But resource variables don't follow this format — `STORAGE_ENDPOINT` is the one trap:**

| Variable | Value | How the base library must handle it |
|---|---|---|
| `{component-prefix}_ENDPOINT` / `..._{port-name}_ENDPOINT` | `http://mdm-customer-1-0-0:9090` | **strip** the scheme (a gRPC client wants `host:port`) |
| **`STORAGE_ENDPOINT`** | `host.docker.internal:9000`, **bare host:port** | **add** the scheme (an S3 SDK wants a full URL) |
| `DATABASE_HOST`+`DATABASE_PORT`, `MQ_HOST`+`MQ_PORT` … | host and port split into two variables | concatenate them yourself |

**`STORAGE_ENDPOINT` is the only variable whose name contains `ENDPOINT` while its value carries no scheme** (verified against brickKit's actual `internal/inject/inject.go`: component addresses go through `fmt.Sprintf("http://%s:%d", ...)`, while storage goes through `hostPort(r)`, i.e. `host:port`). The base library needs **two separate functions** for these two cases — sharing one is guaranteed to get one of them wrong.

**Reading `*_ENDPOINT` must use `os.Getenv()` / `os.environ.get()`.** When a weak dependency is absent, that variable **doesn't exist at all** (not an empty string); using `os.environ["X"]` crashes at startup — this is a deliberate platform design (§3.6).

### E. Ports (§3.5.1.1)

- `deployment.port` and `extraPorts[].port` are **unique, pairwise, across all 62 components**, locked down by the "global port registry" (§2.1).
- **The HTTP main port** can still be changed at assembly time via `localPort`; **gRPC and other extra ports can never be changed after the fact** (the platform has no `localPort` for extra ports and explicitly skips them when rewriting addresses; two `local: true` components colliding on the same extra port makes `brickkit up`'s generation step fail hard).
- Conclusion: **a gRPC port has exactly one chance to be written correctly, in `component.yaml`.** The port registry must be finalized before the first brick is laid.

### F. Health checks (§12.3.6 / §12.3.7)

- `/healthz` **only checks that this process is alive**. Never check a database, a dependency component, or NATS.
- The default startup grace period is **60 seconds** (not 30). `startPeriodSeconds` only delays "declared dead," never "declared alive," so writing it larger costs nothing:

| Who | What to write |
|---|---|
| A Go monolithic component | **Nothing** (the default 60 is enough) |
| A Python component (`infra-print`, `hrm-payroll-es`, `crm-commission`, `erp-manufacturing`, `ana-bi`, `ana-ai`, `integration-edi`) | `120` |
| A Node component (`infra-bff-mobile`) | `90` |
| A shell image (in our own shell-compose, bypassing the platform) | `300` |

- **The image must contain `/bin/sh` plus `wget` or `curl`.** The platform's health check is `CMD-SHELL`; `FROM scratch` / `distroless` never works. The whole project uses an `alpine` / `debian-slim` base with `wget` installed.

### G. Data (Decision 3 / §13.3 Iron Rule 2 / §11.2.3)

- The whole system **shares a single Database `brickkit_db`**, with each component in its own schema plus its own PG Role.
- **Switching must use `SET LOCAL`, never `SET` without `LOCAL`**:

```sql
BEGIN;
SET LOCAL ROLE {component_role};
SET LOCAL search_path TO {component_schema};
-- business SQL
COMMIT;   -- SET LOCAL auto-reverts, connection returns to the pool clean
```

  Using `SET` without `LOCAL` means the next borrower of the connection, once it's returned to the shared pool, **inherits it as-is — component A's query lands on component B's table, no error, no crash, just silently reading and writing someone else's data.** This is the single worst landmine in this whole scheme, and the hardest one to trace.
- **Cross-schema JOINs are forbidden**; related data goes through gRPC `batchGet`.
- **A migration-state table must live in its own schema**, and its table name or primary key must carry the component's identity (Go side: `golang-migrate` with `x-migrations-table` + `search_path`; Python side: `yoyo-migrations` with `--schema` / the connection string's `schema` parameter). **Migration tools are split by language, but must be consistent within a language** — see §K. Writing to `public` by default would let 62 components' migration records collide.
- Every business table that could grow without bound is required to carry: `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`, `version BIGINT NOT NULL DEFAULT 1`, `status TEXT NOT NULL`.
- **A partitioned table's primary key must include the partition key** (Decision 59); archival uses `DETACH CONCURRENTLY` (PG 14+, Decision 60); an archived partition moves into that **component's own** `{component_schema}_archive`, **never a shared global archive schema** (§11.5.4).

### H. Events (§3.10 / §4.4 / §4.6)

- A producer **must** use the Outbox Pattern (write `event_outbox` in the local transaction, a background thread publishes to NATS).
- A consumer **must** be idempotent; the event header must carry `trace_id` / `causation_id` / `hop_count`, and `hop_count > 5` or a detected cycle goes straight to the DLQ.
- A consumer **must** validate `version`, only allowing state to advance monotonically (only update on strictly-greater).
- Schema evolution: **additive only, never delete or change**, consumers deserialize leniently.
- Event naming: `{domain}.{aggregate}.{action}.v{n}`, sharing the `{domain}.{aggregate}.{action}` pattern with permission keys and routing prefixes (§3.7).
- Every cross-component write endpoint carries an `idempotency_key`; the callee de-duplicates with a unique constraint.
- **Never compensate directly after a synchronous call times out** — call the downstream's `GetStatus` first; if `GetStatus` also times out, write to a local "pending reconciliation" table, backstopped by scheduled reconciliation (§4.5).
- Compensation failing more than 3 times → mark `SUSPENDED` + call `infra-workflow` to create a `type: exception` task (§4.4.4).

### I. CI gates (§3.11 + §13.3 Iron Rule 6)

Every component repo's `Makefile` must provide the following, all green before a tag may be cut:

| # | Target | What it guards |
|---|---|---|
| 1 | `make check-version` | `component.yaml`'s version and the git tag must never diverge |
| 2 | `make test` | Unit tests, race-clean |
| 3 | `make image` | Docker build; the image must contain `/bin/sh` + `wget` |
| 4 | `make migrate-idempotent` | The same migration run twice in a row must succeed both times |
| 5 | `make dag-check` | The strong-dependency graph has no cycles |
| 6 | `make contract-check` | `buf breaking` (proto) / `oasdiff` (OpenAPI), no breaking changes allowed |
| 7 | `make import-scan` | **Iron Rule 6**: this component may not `import` any other component repo (Go: `go list -deps`; Python: `grimp`) |
| 8 | `make smoke` | **Principle 1**: `brickkit up` this one component alone (with its strong-dependency tree), `curl` its HTTP, **`grpcurl` its gRPC**, `/healthz` turns healthy (Design Book §3.11 item 8 — an earlier version of this table missed it) |
| 9 | `make module-check` | **Iron Rule 7**: ① the exported signature of `backend/module/module.go` matches §K letter-for-letter; ② zero `os.Getenv`/`os.environ` outside `cmd/`; ③ zero `log.Fatal`/`os.Exit`/`sys.exit`; ④ zero `SetTracerProvider`/`basicConfig`/signal handlers/default Prometheus registry; ⑤ none of the libraries §12.4 forbids **for this component's language** appear in its dependencies (Go: echo/fiber/chi, gorm, lib/pq; Python: flask/django, synchronous `grpc`, sqlalchemy, alembic, gunicorn). **All of these are grep-level checks, but a human cannot reliably hold the line on them** |

### J. Delivery model (§9.4)

Entirely local-source, locally built, no remote private registry. **Signing is not universally enforced** (local sources aren't required to be signed, and shell images fall outside its coverage); supply-chain assurance instead comes from: ① every component directory maps to one git remote plus one tag (this repo's `.gitmodules` is exactly that table); ② build scripts are under version control; ③ the shell image's build/sign/verify flow is written into the delivery documentation.

### K. Unified tech stack and module entry point (§12.4 / §12.5 / §13.3 Iron Rule 7)

**This entire section's criterion is one sentence: everything that is 100% correct standalone and only breaks once merged into a shell lives here.**

- **The stack is not a choice — copy it cell-by-cell from Design Book §12.4**:
  - Go = **Gin** + `database/sql` + the `pgx/v5/stdlib` driver + **`sqlc`** (no GORM) + `grpc-go` + **`golang-migrate`**
  - Python = **FastAPI** + **a programmatic uvicorn `Server` (single process, single event loop; no gunicorn, no `workers > 1`)** + **`grpc.aio`** (no synchronous `grpc`) + **`asyncpg`** + hand-written SQL (no ORM) + **`yoyo-migrations`** (raw `.sql`, no alembic)
  - ⚠️ **The migration cell is "unified within a language"; every other cell is "unified across the whole project."** A shell never spans languages (§13.5), so a Go shell's launcher only ever needs to know `golang-migrate`, and a Python shell's launcher only ever needs to know `yoyo` — and "the migration-state table lives in each component's own schema" already guarantees no component reads another's migration table. **Mixing within a language is the real error** — that would force one shell's launcher to write two separate migration orchestration paths for its 22 modules. The reason for skipping alembic isn't "cross-language inconsistency" — it's that it buys us nothing (zero ORM means autogenerate is useless, and raw DDL can only be wrapped in `op.execute`)
  - Of these, Python's ASGI/WSGI, sync/async gRPC, DB driver, migration tool, and metrics-registry cells are **physically impossible to mix**; the Gin cell is a discipline lock (`gin.Engine` is just an `http.Handler`, so a mix would still compile)
- **A single entry point**: `backend/module/module.go` exports `New(ctx context.Context, rt *besdk.Runtime) (*besdk.Module, error)` (Python: `app/module.py`'s `async def create_module(rt: Runtime) -> Module`). `main` is exactly one line, `besdk.RunStandalone(module.New)`. **Standalone and merged call the same function** — this is the only shape in which §1.5's second principle can be enforced by a machine.
- **Zero `os.Getenv` / `os.environ` in module code**: dependency addresses go through `besdk.Endpoint()`, everything else goes through `rt.Config`. One process has exactly one `environ`; 22 modules' `PG_SCHEMA` and every `configSchema` entry would overwrite each other, **with no error** (§12.5.3). ⚠️ This **corrects an older version of this document's SOP-B, item B-8**.
- **Never touch a process-level singleton**: `otel.SetTracerProvider` / `logging.basicConfig` / signal handlers / **the default Prometheus registry** / connection pools all belong to the caller. Metrics always use the SDK-issued **one-registry-per-module**: using the default global registry means a Go `MustRegister` panic or a Python `Duplicated timeseries`, while running standalone it's 100% fine.
- **Never `log.Fatal` / `os.Exit` / `sys.exit`** — always return an error to the caller. One module hitting a recoverable error and exiting the process takes down **the entire group of 22 components**.

⚠️ **Addendum: "exact version" locks against writing a range (`^1.2`), it does not mandate always chasing latest** (Decision 119). §12.4 locks **framework choice** (Gin/FastAPI/sqlc…), not the exact patch number of every dependency; how to pick a specific version follows this rule:

> **Default to matching whatever the system already has; only upgrade when some version brings a feature you genuinely need.**

This project has already been bitten by exactly this once: PostgreSQL was initially chosen as `16-alpine`, while the local machine already had `postgres:15` installed — going back through the Design Book afterward turned up no reason that demanded 16 specifically; it was simply chosen without checking the system's actual state. ⚠️ **But `be-postgres` was already running on 16 with databases already created by the time this was noticed** — switching back to 15 for real would require a `pg_upgrade` or a dump/restore (verified: simply swapping the image and rebuilding the container throws `database files are incompatible with server`, since a v16 data directory can't be read by v15) — **paying a real migration cost for a principle only clarified after the fact isn't worth it, so 16 stays, and only the criterion itself gets written down to guide future choices.**

⚠️ **This rule does not apply when the dependency chain itself forces the version up.** `be-sdk-go`'s `go.mod` ends up at `go 1.25`, and that isn't us chasing new versions — it's that the **latest** versions of gin/grpc/otel/prometheus/nats.go all require `go >= 1.25` (the whole ecosystem has gradually raised its floor over the past year; checking recent releases of each of these libraries confirms this isn't an isolated case). Pinning old dependencies to get back to 1.22 buys nothing and only loses security patches; the local toolchain is already 1.26 anyway, so this match is automatic and free. **"Match what the system already has" in this case means accepting 1.25, not regressing to hunt down a set of dependencies that all still sit on 1.22.**

Put together, the rule is one sentence: **where you're free to choose, default to minimal change; where a dependency chain forces the move, follow it — never lock yourself to an old version just to keep a number fixed.**

---

---

## Part 1 · Base Resources and One-Command Management (do this first)

### 1.1 Full list of base resources

Base resources are **external services that aren't components** — we write no business code for them, just deploy the official images. **brickKit doesn't deploy them, and doesn't probe their reachability before startup** (`006` §8, §9.1). All deployed via Docker.

First separate the three shapes clearly (§2.7.0) — mixing them up is how you arrive at the wrong conclusion that "the gateway is a component":

| Shape | How the platform sees it | How it's declared | What changing the implementation costs |
|---|---|---|---|
| **A** brickKit base resource | Recognized, connection variables injected | `brickkit.yaml`'s `resources` | ⚠️ **Not just "change one field"** — see Design Book §2.7.3.1 |
| **B** out-of-band container | **Doesn't know it exists at all** | Our own `docker-compose.*.yml` | Change our compose file |
| **C** component | An ordinary component | `brickkit.yaml`'s `components` | Change which one is installed |

**Casdoor and Traefik can only be shape B**: the platform's resource `kind` is a closed enum (`database` / `cache` / `mq` / `storage` / `search` / `smtp`), with no `gateway` and no `iam` (`006` §2.1); Traefik has one more reason — **the platform's Manifest has no volumes field**, so there's nowhere to mount a gateway config file.

#### 1.1.1 Must be deployed by default (5 containers, missing even one and the system won't run)

| # | Resource | Shape | Declared as | Image | Host port | Health check | Volume |
|---|---|---|---|---|---|---|---|
| 1 | **PostgreSQL** | A | `kind: database, engine: postgresql` | `postgres:16-alpine` | 5432 | `pg_isready -h localhost -p 5432` | `pg_data:/var/lib/postgresql/data` |
| 2 | **NATS** | A | `kind: mq, engine: nats` | `nats:2.10-alpine` | 4222, 8222 | `wget -qO- http://localhost:8222/healthz` | `nats_data:/data` |
| 3 | **Traefik** | B | — (out-of-band) | `traefik:v3.0` | 80, 443, **28080** | `traefik healthcheck --ping` | config mount |
| 4 | **Casdoor** | B | — (out-of-band) | `casbin/casdoor:latest` | 8000 | `curl -f http://localhost:8000/api/health` | config mount |
| 5 | **RustFS** | A | `kind: storage, engine: s3` | `rustfs/rustfs:latest` | 9000 | `curl -f http://localhost:9000/health/live` | `rustfs_data:/data` |

Key configuration points:

- **PostgreSQL**: `POSTGRES_PASSWORD` must be set; `max_connections=300` (one pool per shell across 5 shells, enough headroom for the full component set). ⚠️ **The platform never creates a database, schema, or role** (`006` §9.5) — `brickkit up` only **prints** the CREATE statements. Actually provisioning them is done by a script `be-ops` produces, run once by ops (Task 4).
- **NATS**: must run `--jetstream`; `--store_dir /data`; `max_payload=8MB`.
- **Traefik**: enable the Docker Provider (reads container labels); a `ForwardAuth` middleware hooked up to Casdoor; **the Dashboard port moves from 8080 to 28080** (reason in §1.2).
- **Casdoor**: connects to PostgreSQL, using its own schema `casdoor`; `origin` set to the gateway address.
- **RustFS**: set access keys; mount a persistent volume for the data directory.

#### 1.1.2 Optional replacements (mutually exclusive with the default implementation — install only one per environment)

| Resource | Shape | Image | Replaces | Host port | When to use |
|---|---|---|---|---|---|
| **MinIO** | A | `minio/minio:latest` | RustFS | 9000, 9001 | Customer already has MinIO ops experience, or wants a management UI. `engine` is `s3` on both sides, **swapping the implementation is genuinely zero-change** |
| **Keycloak** | B | `quay.io/keycloak/keycloak:latest` | Casdoor | **28081** | Complex LDAP/AD domain, or very fine-grained RBAC/ABAC |
| **Kafka** | A | `confluentinc/cp-kafka:latest` | NATS | **29092** | Daily event volume in the tens of millions or beyond, needs stream processing. ⚠️ Swapping it means changing ~50 `component.yaml` files **plus** swapping the SDK driver (Design Book §2.7.3.1) |
| **RabbitMQ** | A | `rabbitmq:3.13-management` | NATS | 5672, 15672 | Customer already has RabbitMQ infrastructure. ⚠️ Same as above |
| **Nginx** | B | `nginx:1.25-alpine` | Traefik | 80, 443 | Customer already has Nginx ops experience, doesn't want dynamic service discovery |

⚠️ Only RabbitMQ has `MQ_VHOST` — NATS / Kafka resource bindings **never set this field** (an empty value is not injected).

#### 1.1.3 The full observability suite (shape B, bring the whole thing up together or not at all)

| Resource | Image | Host port | Purpose |
|---|---|---|---|
| **OTel Collector** | `otel/opentelemetry-collector-contrib:latest` | 4317, 4318, 13133 | Unified data-collection gateway |
| **Prometheus** | `prom/prometheus:latest` | **29090** | Metrics storage backend |
| **Loki** | `grafana/loki:latest` | 3100 | Log storage backend |
| **Tempo** | `grafana/tempo:latest` | 3200 | Trace storage backend |
| **Grafana** | `grafana/grafana:latest` | 3000 | Visualization |

⚠️ **None of these five is a component** (Decision 97): pure official images that must mount a `config.yaml`, and the Manifest has no volumes field. Observability gets **not a single line** in `brickkit.yaml`.

**Behavior when not brought up**: a component's `otelBaseUrl` is left empty → the OTel SDK configures a Blackhole Exporter → data is silently discarded, the system runs perfectly, **at zero cost**. This tier requires touching not a single line of `brickkit.yaml`.

#### 1.1.4 Explicitly excluded, do not deploy (§2.7.4)

| Resource | Why it isn't needed |
|---|---|
| **Redis** | JWTs are stateless (no session needed); local digest replicas (no centralized cache needed); PG row locks (no distributed lock needed); Traefik has built-in rate limiting. All four use cases are covered (Decision 71) |
| **Consul / etcd** | The routing table is aggregated at generation time (Decision 20), no runtime service discovery needed |
| **Zookeeper** | NATS doesn't need it; Kafka 3.x already has KRaft |
| **Elasticsearch** | No full-text search requirement currently; audit logs use PG partitioned tables |

### 1.2 ⚠️ Port conflicts and corrections (already written back into the Design Book)

The official default ports of out-of-band containers collide on two separate layers, and **the second layer can only be discovered by reading the platform's code.**

**Layer 1 · Colliding with our own component ports.** A shell must publish its ports to the host (`extra_hosts` pointing at `host-gateway`, §13.1), so component ports and out-of-band container ports live in the same host port space.

**Layer 2 · The entire `1xxxx` range belongs to the platform.** When brickKit maps `local: true` components and their dependencies onto host ports, it uses a fixed convention (`internal/compose/local.go`): prefer `10000 + container port`, falling back to an incrementing scan starting from `18080` if that's taken. So every one of our component ports has a corresponding `1xxxx` the platform will try to claim:

| Out-of-band container | Official default | Collides with (both layers) | Final |
|---|---|---|---|
| Traefik Dashboard | 8080 | `mdm-customer`'s HTTP; and `18080` is the platform's preferred mapping for 8080 | **28080** |
| Keycloak | 8080 | Same as above; and `18081` is the platform's preferred mapping for 8081 (`mdm-supplier`) | **28081** |
| Prometheus | 9090 | `mdm-customer`'s gRPC; and `19090` is the platform's preferred mapping for 9090 | **29090** |
| Kafka | 9092 | `mdm-product`'s gRPC; and `19092` is the platform's preferred mapping for 9092 | **29092** |

⚠️ **`18080` / `18081` / `19090` / `19092` are exactly the most natural spots to land on** when "moving the official default port out of the way" — that's exactly what this plan picked the first time, and all four landed squarely on the platform. **Conclusion: out-of-band containers always use the `2xxxx` range** — both above the upper bound of `10000 + component port` (max component port is 9221 → 19221) and well clear of the platform's actual scan range starting at `18080`.

**Consequent conclusion: `be-ops`'s global port registry (output 6) must also cover out-of-band container ports, and mark the entire `1xxxx` range as platform-reserved.** A registry covering only the 62 components' ports would never surface these — they only explode the first time a shell's ports are published to the host, or the first time a `local` component gets a debug mapping — by which point the gRPC ports are already written into 61 `component.yaml` files and can no longer be changed (§3.5.1.1). **Already written back into Design Book §2.7.1, §2.7.2③, §2.7.5, Appendix G, Decision 106.**

**Current state of this machine (verified 2026-09-02) and how you're handling it:**

| Conflict | Current state | Difference from the Design Book |
|---|---|---|
| :5432 | `my-postgres` running `postgres:15` | ⚠️ **Keeping `postgres:16-alpine` as-is**: this difference could in principle be aligned (PG16 has no feature this design depends on), but `be-postgres` is already running 16 with databases already created, and switching back to 15 requires a real data migration (`pg_upgrade`/dump-restore) — the version-selection criterion (see the §K addendum) only governs **future** version choices, it does not require unwinding a choice that's already live and already in effect |
| :9000-9001 | `my-rustfs` running `rustfs/rustfs:latest` | Right image, but not a container managed by this project's compose |
| :6379 | `my-redis` | Redis is a resource this project **explicitly excludes**; it occupying the port has no impact |

**Decided: `make check` / `make up` only detect and name the offending party — they never `stop` or `rm` any container outside this project.** Investigation and remediation are done by hand.

### 1.3 The Makefile contract

The Makefile lives at this repo's root and is **the sole entry point for base resources**. Design principle: keep the Makefile thin, with the actual criteria in one declarative table, `infra/resources.tsv`, which the check scripts read — adding a resource means one row in that table plus one block in a compose file; the Makefile itself doesn't change.

The compose project name is uniformly `be-infra`, and every container attaches to the same external network `be-net` (the §13.8.3 iron rule: all three compose files must attach to the same external network, or Traefik's Docker Provider can't see the shell's routing labels — the symptom being a gateway 404 with every container healthy).

| Target | Behavior |
|---|---|
| `make help` | List every target (default target) |
| `make net` | Idempotently create the external network `be-net` |
| **`make check`** | **One-shot query**: for each default resource, check five things — is the container present, is the image tag right, are the published ports right, is it healthy, is it on `be-net`. When a port is held by a container/process outside this project, **name that container or PID**. Table output; exit 0 if all green, exit 1 if any red |
| `make check-all` | Same, plus whichever optional resources are currently enabled |
| **`make up`** | **Bring up all default resources in one shot**: run a full **preflight check** first, and only start once everything passes (to avoid a half-up state). Already-healthy-and-correct resources are **skipped**; missing ones are brought up; **anything present but with the wrong image/port fails immediately, untouched, not a single byte changed** |
| `make down` | Stop all of this project's containers (**volumes untouched**) |
| `make status` | `docker compose ps` plus a health-status summary |
| `make logs SVC=<service>` | Tail one service's logs |
| **`make <res>-up`** | Bring up one optional resource. `res` ∈ `minio` / `keycloak` / `kafka` / `rabbitmq` / `nginx` / `obs`. **Mutual-exclusion check before starting**: `minio-up` errors if RustFS is already running |
| **`make <res>-down`** | Bring down one optional resource |
| `make nuke` | Stop and **delete volumes**. Requires a second confirmation (typing `yes-delete-my-data`) |
| `make db-init` | Run the database-provisioning script `be-ops` produces (CREATE DATABASE / SCHEMA / ROLE / grants). Idempotent |
| `make arsenal-check` | Arsenal self-consistency check (submodule structure vs. `brickkit.yaml`'s enable/disable state), see §3.4 |
| `make arsenal-restore` | Restore the submodule structure to match `brickkit.yaml`, see §3.4 |

The full observability suite is **one single profile, `obs`** (§2.7.3: bring the whole thing up together or not at all) — there is no target to turn on just Prometheus by itself.

Mutual-exclusion groups (checked on `make <res>-up`):

| Group | Members |
|---|---|
| `storage` | `rustfs` (default), `minio` |
| `mq` | `nats` (default), `kafka`, `rabbitmq` |
| `iam` | `casdoor` (default), `keycloak` |
| `gateway` | `traefik` (default), `nginx` |

Only after **Phase 4** does the Makefile gain `make up-all` / `make down-all`, wrapping the start/stop chain of the three compose files from §13.8.3 (`brickkit down` can't stop a shell, and a delivery site will absolutely hit "thought it was shut down cleanly, but the shell is still running and holding the ports"). Shells don't exist before then — see **Phase 4**.

---

## Part 2 · The Three Global Registries

> This section only covers the three that need **hand-written initial content**. Two more are **generated** by `be-ops` from every component's `assembly.yaml`;
> there's nothing to enumerate yet, see §2.4 outputs 9/10 and Design Book Chapter 14:
> `registry/permissions.tsv` (the permission-key registry, **append-only**, same tier as `ports.tsv`),
> `registry/data-scopes.tsv` (the master data-scope table, purely derived, safe to regenerate anytime).

### 2.1 Global port registry (`be-ops` output 6's initial content)

**This table is the sole source for `component.yaml`'s `deployment.port` and `extraPorts`. gRPC ports have no after-the-fact remedy — always check back here before writing one.**

Allocation rule: within-shell index `n` → HTTP `base+n`, gRPC `base+1000+n` (HTTP 8080 pairs with gRPC 9090, i.e. gRPC = HTTP + a 1010 offset).

#### Shell 1 · Go core transactions and master data (8, HTTP 8080–8087 / gRPC 9090–9097)

| # | Repo name | Component ID | HTTP | gRPC |
|---|---|---|---|---|
| 1 | `mdm-customer` | `mdm/customer` | 8080 | 9090 |
| 2 | `mdm-supplier` | `mdm/supplier` | 8081 | 9091 |
| 3 | `mdm-product` | `mdm/product` | 8082 | 9092 |
| 4 | `mdm-org` | `mdm/org` | 8083 | 9093 |
| 5 | `erp-sales` | `erp/sales` | 8084 | 9094 |
| 6 | `erp-purchase` | `erp/purchase` | 8085 | 9095 |
| 7 | `erp-inventory` | `erp/inventory` | 8086 | 9096 |
| 8 | `erp-finance` | `erp/finance` | 8087 | 9097 |

(8080 / 8081 / 8084+9094 exactly match the Design Book's §13.1/§3.5.1 examples; the rest follow the same sequence.)

#### Shell 2 · Go back-office and support (16, HTTP 8100–8115 / gRPC 9100–9115)

| # | Repo name | Component ID | HTTP | gRPC |
|---|---|---|---|---|
| 1 | `crm-lead` | `crm/lead` | 8100 | 9100 |
| 2 | `crm-customer` | `crm/customer` | 8101 | 9101 |
| 3 | `crm-opportunity` | `crm/opportunity` | 8102 | 9102 |
| 4 | `crm-activity` | `crm/activity` | 8103 | 9103 |
| 5 | `crm-campaign` | `crm/campaign` | 8104 | 9104 |
| 6 | `crm-case` | `crm/case` | 8105 | 9105 |
| 7 | `hrm-attendance` | `hrm/attendance` | 8106 | 9106 |
| 8 | `hrm-leave` | `hrm/leave` | 8107 | 9107 |
| 9 | `hrm-expense` | `hrm/expense` | 8108 | 9108 |
| 10 | `prj-project` | `prj/project` | 8109 | 9109 |
| 11 | `prj-timesheet` | `prj/timesheet` | 8110 | 9110 |
| 12 | `erp-asset` | `erp/asset` | 8111 | 9111 |
| 13 | `erp-quality` | `erp/quality` | 8112 | 9112 |
| 14 | `erp-maintenance` | `erp/maintenance` | 8113 | 9113 |
| 15 | `hrm-recruitment` | `hrm/recruitment` | 8114 | 9114 |
| 16 | `hrm-appraisal` | `hrm/appraisal` | 8115 | 9115 |

⚠️ **Correction 1 (already written back into Design Book §13.2)**: Shell 2 originally listed only 14 components, missing `hrm-recruitment` and `hrm-appraisal` (both Go, both plain CRUD, both `reserve`). They need ports too, or Phase 4b has nowhere to put them once it reaches them. The range has been expanded from 8100–8113 to **8100–8115**.

#### Shell 3 · Go infrastructure and external channels (22, HTTP 8200–8223 / gRPC 9200–9223)

| # | Repo name | Component ID | HTTP | gRPC |
|---|---|---|---|---|
| 1 | `infra-iam-casdoor` | `infra/iam-casdoor` | 8200 | 9200 |
| 2 | `infra-workflow` | `infra/workflow` | 8201 | 9201 |
| 3 | `infra-notification` | `infra/notification` | 8202 | 9202 |
| 4 | `infra-dlq-monitor` | `infra/dlq-monitor` | 8203 | 9203 |
| 5 | `infra-attachment` | `infra/attachment` | 8204 | 9204 |
| 6 | `infra-storage` | `infra/storage` | 8205 | 9205 |
| 7 | `infra-audit` | `infra/audit` | 8206 | 9206 |
| 8 | `integration-im-dingtalk` | `integration/im-dingtalk` | 8207 | 9207 |
| 9 | `integration-im-wechat-work` | `integration/im-wechat-work` | 8208 | 9208 |
| 10 | `integration-im-feishu` | `integration/im-feishu` | 8209 | 9209 |
| 11 | `integration-im-slack` | `integration/im-slack` | 8210 | 9210 |
| 12 | `integration-im-teams` | `integration/im-teams` | 8211 | 9211 |
| 13 | `integration-payment-stripe` | `integration/payment-stripe` | 8212 | 9212 |
| 14 | `integration-payment-paypal` | `integration/payment-paypal` | 8213 | 9213 |
| 15 | `integration-payment-alipay` | `integration/payment-alipay` | 8214 | 9214 |
| 16 | `integration-payment-wechat-pay` | `integration/payment-wechat-pay` | 8215 | 9215 |
| 17 | `integration-esign-docusign` | `integration/esign-docusign` | 8216 | 9216 |
| 18 | `integration-esign-pandadoc` | `integration/esign-pandadoc` | 8217 | 9217 |
| 19 | `integration-esign-esign` | `integration/esign-esign` | 8218 | 9218 |
| 20 | `integration-email` | `integration/email` | 8219 | 9219 |
| 21 | `integration-sms` | `integration/sms` | 8220 | 9220 |
| 22 | `infra-authz` | `infra/authz` | **8223** | **9223** |

⚠️ **`infra-authz` takes 8223 rather than 8222, and isn't inserted in the middle of the infra block — both are deliberate.**

① `ports.tsv` is append-only (§3.5.1.1); 8221 has already been given to `infra-iam-keycloak`, so a new component can only take the next free one — **never reshuffle already-published ports just to "look tidy."**
② **8222 is skipped because it's NATS's monitoring port** (§1.2's host-port table). At merged-deployment time Shell 3 publishes the whole 8200–8223 range to the host, and taking 8222 would collide with NATS on the spot.
⚠️ **This is exactly why the port registry must also cover out-of-band container ports** (Decision 99) — looking only at the component range 8200–8221, 8222 looks free.

⚠️ **Correction 2 (already written back into Design Book §13.2)**: Shell 3's component list originally said "6 infra + 15 `integration-*`," but `integration-edi` is Python and lives in Shell 5, leaving only 14 integration components → 6 + 14 = 20, one short of the "21" the text itself claimed. The missing one is the **`infra-iam-casdoor` adapter layer** — it's Go, ~500 lines, and wasn't captured by any shell list, yet §9.6.1 Tier 3 explicitly says "the Go shell holds 10 modules," and Tier 2's 13 components include exactly 10 Go ones (`mdm-customer`/`mdm-product`/`erp-sales`/`erp-inventory`/`erp-finance`/`crm-opportunity`/`infra-iam-casdoor`/`infra-workflow`/`infra-notification`/`integration-im-dingtalk`), which does count it. Adding it back makes 21 add up.

⚠️ **Follow-up to Correction 2 (found during the Phase 2 shipping retrospective, 2026-09-08)**: `infra-authz` had been missed the same way — it wasn't captured by any shell list either, and yet it really is Go, really does belong to Shell 3, and the port table above (8223/9223) really had already reserved a slot for it. Adding it back, Tier 2/Tier 3's Go portion is 11 components (not 10), and Shell 3's final shape is **8 infra + 14 integration = 22** (not 21). §9.6.1, §13.2, and Appendix H have all been cross-checked against each other (Appendix H's "Slice" column already had `infra-authz` checked off — the only thing that hadn't caught up was §9.6.1's numbers); these two historical correction notes in this section are kept exactly as they were written — they record "how it was discovered and fixed, at the time" — the newly-found gap gets its own new note rather than rewriting the old one.

#### Shell 4 · Python complex brains (5, HTTP 8300–8304 / gRPC 9300–9304)

| # | Repo name | Component ID | HTTP | gRPC |
|---|---|---|---|---|
| 1 | `hrm-payroll-es` | `hrm/payroll-es` | 8300 | 9300 |
| 2 | `crm-commission` | `crm/commission` | 8301 | 9301 |
| 3 | `erp-manufacturing` | `erp/manufacturing` | 8302 | 9302 |
| 4 | `ana-bi` | `ana/bi` | 8303 | 9303 |
| 5 | `ana-ai` | `ana/ai` | 8304 | 9304 |

#### Shell 5 · Python rendering and EDI (2, HTTP 8400–8401 / gRPC 9400–9401)

| # | Repo name | Component ID | HTTP | gRPC |
|---|---|---|---|---|
| 1 | `infra-print` | `infra/print` | 8400 | 9400 |
| 2 | `integration-edi` | `integration/edi` | 8401 | 9401 |

#### Standalone containers · never enter any shell (§13.5: cross-language can't merge, and neither can Nginx)

| Repo name | Component ID | Language | HTTP | gRPC | Notes |
|---|---|---|---|---|---|
| `infra-bff-mobile` | `infra/bff-mobile` | TypeScript | 8500 | — | GraphQL over HTTP, no gRPC exposed |
| `frontend-standard` | `frontend/standard` | TypeScript | 80 | — | An Nginx static container |
| `frontend-advanced` | `frontend/advanced` | TypeScript | 80 | — | Same slot as standard, never coexists with it |
| `frontend-{industry}` | `frontend/{industry}` | TypeScript | 80 | — | Same as above |
| `frontend-{customer}` | `frontend/{customer}` | TypeScript | 80 | — | Same as above (a fork, `metadata.id` matching the forked component, see §3.4.1) |

⚠️ **The one exception to globally-unique ports is the `slot:frontend` family**: all 4 frontend components use port 80, because the slot is mutually exclusive — they never assemble together — and each runs its own standalone Nginx container outside any shell. This exception must be written into `be-ops`'s port-registry validation logic, or the check will false-positive.

#### Slot replacements and blueprints

| Repo name | Component ID | HTTP | gRPC | Notes |
|---|---|---|---|---|
| `infra-iam-keycloak` | `infra/iam-keycloak` | 8221 | 9221 | A `slot:iam` replacement, mutually exclusive with `infra-iam-casdoor`. Even though mutually exclusive, it still gets its own port (§3.5.1.1 says "unique, pairwise, across all 62 components") |
| `hrm-payroll-core` | `hrm/payroll-core` | 8305 | 9305 | **Blueprint, not currently developed.** Port reserved |
| `hrm-payroll-cn` | `hrm/payroll-cn` | 8306 | 9306 | **Blueprint, not currently developed.** Port reserved |
| `hrm-payroll-us` | `hrm/payroll-us` | 8307 | 9307 | **Blueprint, not currently developed.** Port reserved |

#### Host ports for out-of-band containers and base resources (final corrected values, already written back into the Design Book)

| Resource | Host port | Default? | Difference from Design Book Appendix G |
|---|---|---|---|
| PostgreSQL | 5432 | ✅ | — |
| NATS | 4222, 8222 | ✅ | — |
| Traefik | 80, 443, **28080** | ✅ | Dashboard 8080 → **28080** |
| Casdoor | 8000 | ✅ | — |
| RustFS | 9000 | ✅ | — |
| MinIO | 9000, 9001 | ❌ | — |
| Keycloak | **28081** | ❌ | 8080 → **28081** |
| Kafka | **29092** | ❌ | 9092 → **29092** |
| RabbitMQ | 5672, 15672 | ❌ | — |
| Nginx | 80, 443 | ❌ | — |
| OTel Collector | 4317, 4318, 13133 | ❌ | — |
| Prometheus | **29090** | ❌ | 9090 → **29090** |
| Loki | 3100 | ❌ | — |
| Tempo | 3200 | ❌ | — |
| Grafana | 3000 | ❌ | — |

**Cross-checked:** every port in the table above is pairwise non-colliding with every component's HTTP (8080–8115, 8200–8221, 8300–8307, 8400–8401, 8500, 80) and gRPC (9090–9115, 9200–9221, 9300–9307, 9400–9401) ports.

⚠️ **Two platform-generated standalone containers need an `exposePort` (a host port), and these must also go in the port registry:**

| Component | In-container port | `exposePort` (host) | Why it needs to be exposed |
|---|---|---|---|
| `frontend-standard` | 80 | **28090** | The platform-generated compose can't join `be-net`, so Traefik's Docker Provider can't see it. It can only be published to the host, and reached via Traefik's **file provider** (Decision 107) |
| `infra-bff-mobile` | 8500 | **28500** | Same as above |

⚠️ **The entire `1xxxx` range is platform-reserved and may never be allocated in the port registry.** When brickKit maps `local: true` components and their dependencies onto host ports, it prefers `10000 + container port`, falling back to an incrementing scan from `18080` (`internal/compose/local.go`). Our largest component port is 9221, so the platform will actually use **18080–19221**. Out-of-band containers always use the `2xxxx` range (§1.2, Decision 106).

### 2.2 Global schema / role registry (`be-ops` output 2's initial content)

Naming rule (no exceptions):

| Object | Rule | Example |
|---|---|---|
| Database | One, system-wide | `brickkit_db` |
| Component schema | repo name with `-` → `_` | `mdm-customer` → `mdm_customer` |
| Component archive schema | `{schema}_archive` | `mdm_customer_archive` |
| Component PG Role | `{schema}_rw` | `mdm_customer_rw` |
| Shell login role | `shell_{shell-id}` | `shell_go_core` |

⚠️ **A component's Role is used only for `SET LOCAL ROLE` switching, never for login**, and therefore **never appears in `brickkit.yaml`** (§13.3 Iron Rule 2). `brickkit.yaml`'s `resources` holds only the 5 shell login roles (same host, different credentials).

The five shell login roles:

| Shell | Login role | Component schemas it covers |
|---|---|---|
| Shell 1 Go-Core | `shell_go_core` | The 8 in Shell 1 |
| Shell 2 Go-Backoffice | `shell_go_backoffice` | The 16 in Shell 2 |
| Shell 3 Go-Infra | `shell_go_infra` | The 22 in Shell 3 (including `infra_authz`; + `infra_iam_keycloak` if the slot is swapped) |
| Shell 4 Py-Brain | `shell_py_brain` | The 5 in Shell 4 |
| Shell 5 Py-Render | `shell_py_render` | The 2 in Shell 5 |

Two more non-component schemas: `casdoor` (for the official Casdoor image's own use), `keycloak` (used if the slot is swapped).

`infra-bff-mobile` **creates no schema** — it is forbidden from connecting to the DB directly (§6.5). Same for `frontend-*`.

### 2.3 Full component roster (62, not one missing)

Legend: **Phase** = which phase it starts in (see §5.1). **Language** follows Design Book §12.1. **Shell** follows the §2.1 port registry.

#### infra domain (11)

| # | Repo name | Assembly role | Language | Shell | HTTP/gRPC | schema | Phase |
|---|---|---|---|---|---|---|---|
| 1 | `infra-iam-casdoor` | `slot:iam` (Default) | Go | 3 | 8200/9200 | `infra_iam_casdoor` | **Phase 3** |
| 2 | `infra-iam-keycloak` | `slot:iam` (replacement) | Go | 3 | 8221/9221 | `infra_iam_keycloak` | Phase 6 |
| 3 | `infra-bff-mobile` | default | TypeScript | standalone | 8500/— | none (DB-direct forbidden) | **Phase 3** |
| 4 | `infra-workflow` | default | Go | 3 | 8201/9201 | `infra_workflow` | **Phase 3** |
| 5 | `infra-notification` | default | Go | 3 | 8202/9202 | `infra_notification` | **Phase 3** |
| 6 | `infra-attachment` | default | Go | 3 | 8204/9204 | `infra_attachment` | **Phase 5** |
| 7 | `infra-storage` | default | Go | 3 | 8205/9205 | `infra_storage` | **Phase 5** |
| 8 | `infra-print` | default | **Python** | 5 | 8400/9400 | `infra_print` | **Phase 3** |
| 9 | `infra-audit` | reserve | Go | 3 | 8206/9206 | `infra_audit` | Phase 6 |
| 10 | `infra-dlq-monitor` | default | Go | 3 | 8203/9203 | `infra_dlq_monitor` | **Phase 5** |
| 11 | `infra-authz` | default | Go | 3 | 8223/9223 | `infra_authz` | **Phase 3** |

#### integration domain (15)

| # | Repo name | Assembly role | Language | Shell | HTTP/gRPC | schema | Phase |
|---|---|---|---|---|---|---|---|
| 11 | `integration-im-dingtalk` | `channel:im` | Go | 3 | 8207/9207 | `integration_im_dingtalk` | **Phase 3** |
| 12 | `integration-im-wechat-work` | `channel:im` | Go | 3 | 8208/9208 | `integration_im_wechat_work` | Phase 6 |
| 13 | `integration-im-feishu` | `channel:im` | Go | 3 | 8209/9209 | `integration_im_feishu` | Phase 6 |
| 14 | `integration-im-slack` | `channel:im` | Go | 3 | 8210/9210 | `integration_im_slack` | Phase 6 |
| 15 | `integration-im-teams` | `channel:im` | Go | 3 | 8211/9211 | `integration_im_teams` | Phase 6 |
| 16 | `integration-payment-stripe` | `channel:payment` | Go | 3 | 8212/9212 | `integration_payment_stripe` | Phase 6 |
| 17 | `integration-payment-paypal` | `channel:payment` | Go | 3 | 8213/9213 | `integration_payment_paypal` | Phase 6 |
| 18 | `integration-payment-alipay` | `channel:payment` | Go | 3 | 8214/9214 | `integration_payment_alipay` | Phase 6 |
| 19 | `integration-payment-wechat-pay` | `channel:payment` | Go | 3 | 8215/9215 | `integration_payment_wechat_pay` | Phase 6 |
| 20 | `integration-esign-docusign` | `channel:esign` | Go | 3 | 8216/9216 | `integration_esign_docusign` | Phase 6 |
| 21 | `integration-esign-pandadoc` | `channel:esign` | Go | 3 | 8217/9217 | `integration_esign_pandadoc` | Phase 6 |
| 22 | `integration-esign-esign` | `channel:esign` | Go | 3 | 8218/9218 | `integration_esign_esign` | Phase 6 |
| 23 | `integration-email` | `channel:email` | Go | 3 | 8219/9219 | `integration_email` | Phase 6 |
| 24 | `integration-sms` | `channel:sms` | Go | 3 | 8220/9220 | `integration_sms` | Phase 6 |
| 25 | `integration-edi` | reserve | **Python** | 5 | 8401/9401 | `integration_edi` | Phase 6 |

#### mdm master-data domain (4, read-only hubs)

| # | Repo name | Assembly role | Language | Shell | HTTP/gRPC | schema | Phase |
|---|---|---|---|---|---|---|---|
| 26 | `mdm-customer` | default | Go | 1 | 8080/9090 | `mdm_customer` | **Phase 1** |
| 27 | `mdm-supplier` | default | Go | 1 | 8081/9091 | `mdm_supplier` | **Phase 5** |
| 28 | `mdm-product` | default | Go | 1 | 8082/9092 | `mdm_product` | **Phase 2** |
| 29 | `mdm-org` | default | Go | 1 | 8083/9093 | `mdm_org` | **Phase 5** |

#### crm customer-relationship domain (7, flexible/tolerant)

| # | Repo name | Assembly role | Language | Shell | HTTP/gRPC | schema | Phase |
|---|---|---|---|---|---|---|---|
| 30 | `crm-lead` | optional | Go | 2 | 8100/9100 | `crm_lead` | Phase 6 |
| 31 | `crm-customer` | optional | Go | 2 | 8101/9101 | `crm_customer` | Phase 6 |
| 32 | `crm-opportunity` | optional | Go | 2 | 8102/9102 | `crm_opportunity` | **Phase 3** |
| 33 | `crm-activity` | optional | Go | 2 | 8103/9103 | `crm_activity` | Phase 6 |
| 34 | `crm-campaign` | optional | Go | 2 | 8104/9104 | `crm_campaign` | Phase 6 |
| 35 | `crm-case` | optional | Go | 2 | 8105/9105 | `crm_case` | Phase 6 |
| 36 | `crm-commission` | reserve | **Python** | 4 | 8301/9301 | `crm_commission` | Phase 6 |

#### erp enterprise-resource domain (8, strict / strongly consistent)

| # | Repo name | Assembly role | Language | Shell | HTTP/gRPC | schema | Phase |
|---|---|---|---|---|---|---|---|
| 37 | `erp-sales` | optional | Go | 1 | 8084/9094 | `erp_sales` | **Phase 2** |
| 38 | `erp-purchase` | optional | Go | 1 | 8085/9095 | `erp_purchase` | Phase 6 |
| 39 | `erp-inventory` | optional | Go | 1 | 8086/9096 | `erp_inventory` | **Phase 2** |
| 40 | `erp-finance` | optional | Go | 1 | 8087/9097 | `erp_finance` | **Phase 2** |
| 41 | `erp-manufacturing` | optional | **Python** | 4 | 8302/9302 | `erp_manufacturing` | Phase 6 |
| 42 | `erp-asset` | optional | Go | 2 | 8111/9111 | `erp_asset` | Phase 6 |
| 43 | `erp-quality` | optional | Go | 2 | 8112/9112 | `erp_quality` | Phase 6 |
| 44 | `erp-maintenance` | optional | Go | 2 | 8113/9113 | `erp_maintenance` | Phase 6 |

#### hrm human-resources domain (9, including 3 blueprints)

| # | Repo name | Assembly role | Language | Shell | HTTP/gRPC | schema | Phase |
|---|---|---|---|---|---|---|---|
| 45 | `hrm-attendance` | optional | Go | 2 | 8106/9106 | `hrm_attendance` | Phase 6 |
| 46 | `hrm-leave` | optional | Go | 2 | 8107/9107 | `hrm_leave` | Phase 6 |
| 47 | `hrm-expense` | optional | Go | 2 | 8108/9108 | `hrm_expense` | Phase 6 |
| 48 | `hrm-recruitment` | reserve | Go | 2 | 8114/9114 | `hrm_recruitment` | Phase 6 |
| 49 | `hrm-appraisal` | reserve | Go | 2 | 8115/9115 | `hrm_appraisal` | Phase 6 |
| 50 | `hrm-payroll-core` | **blueprint** | Python | 4 | 8305/9305 | `hrm_payroll_core` | **not developed** |
| 51 | `hrm-payroll-cn` | **blueprint** | Python | 4 | 8306/9306 | `hrm_payroll_cn` | **not developed** |
| 52 | `hrm-payroll-us` | **blueprint** | Python | 4 | 8307/9307 | `hrm_payroll_us` | **not developed** |
| 53 | `hrm-payroll-es` | `slot:payroll` optional | **Python** | 4 | 8300/9300 | `hrm_payroll_es` | Phase 6 |

⚠️ `hrm-payroll-es` **embeds its own payroll-engine functionality** (a pay-item dictionary, pay-cycle calculation, payslip data structures) — it does **not** depend on `hrm-payroll-core` (Decision 64).

#### prj project-management domain (2)

| # | Repo name | Assembly role | Language | Shell | HTTP/gRPC | schema | Phase |
|---|---|---|---|---|---|---|---|
| 54 | `prj-project` | optional | Go | 2 | 8109/9109 | `prj_project` | Phase 6 |
| 55 | `prj-timesheet` | optional | Go | 2 | 8110/9110 | `prj_timesheet` | Phase 6 |

#### ana data-analytics domain (2, held in reserve)

| # | Repo name | Assembly role | Language | Shell | HTTP/gRPC | schema | Phase |
|---|---|---|---|---|---|---|---|
| 56 | `ana-bi` | reserve | **Python** | 4 | 8303/9303 | `ana_bi` | Phase 6 |
| 57 | `ana-ai` | reserve | **Python** | 4 | 8304/9304 | `ana_ai` | Phase 6 |

#### frontend domain (4)

| # | Repo name | Assembly role | Language | Shell | HTTP | schema | Phase |
|---|---|---|---|---|---|---|---|
| 58 | `frontend-standard` | `slot:frontend` (Default) | TypeScript (Vue3 + Uni-app) | standalone | 80 | none | **Phase 3** |
| 59 | `frontend-advanced` | `slot:frontend` (replacement) | TypeScript | standalone | 80 | none | 🔜 future |
| 60 | `frontend-{industry}` | `slot:frontend` (replacement) | TypeScript | standalone | 80 | none | 🔜 future |
| 61 | `frontend-{customer}` | `customer_fork` `slot:frontend` | TypeScript | standalone | 80 | none | 📋 forked on demand |

#### Non-component asset repositories (not among the 62)

| Repo name | Purpose | Phase |
|---|---|---|
| `brickKit` | The platform itself (already exists) | — |
| `be-assembly-standard` | Product root / standard assembly template / arsenal index (**this repo**, already exists) | — |
| **`be-ops`** | **Required (delivery-critical path)** the assembly generator, 11 outputs, see §2.4 | **Phase 1** |
| **`be-acceptance`** | **Required (delivery-critical path)** acceptance tests: the 20 platform acceptance cases + business closed loop + teardown gate + import scan | **Phase 1** |
| `be-shell-go` | The Go shell launcher (our own adaptation, not under `components/`) | **Phase 4** |
| `be-shell-python` | The Python shell launcher (same) | **Phase 4** |
| **`be-sdk-go`** | **Required (delivery-critical path)** the Go cross-cutting base library, SOP-L's 14 capabilities | **Phase 1** |
| **`be-sdk-python`** | **Required** the Python cross-cutting base library | **Phase 3** |
| **`be-sdk-ts`** | **Required** the TS cross-cutting base library (only half of one: no `withTx` / no hot-cold routing, plus GraphQL-specific limits) | **Phase 3** |
| `be-assembly-{customer}` | A customer's backend assembly manifest | at the first customer |

**Count check**: 62 = infra 11 + integration 15 + mdm 4 + crm 7 + erp 8 + hrm 9 + prj 2 + ana 2 + frontend 4 ✓
59 need building (62 − 3 blueprints); of those, **Phases 1–3** build 14, **Phase 5** builds 5, and **Phase 6** builds 37 (= 44 remaining − 3 blueprints − 3 future/on-demand frontends) ✓

### 2.4 `be-ops`'s 11 outputs (Decisions 89 / 93, 115–118)

Everything the platform deliberately doesn't do, and that the work itself doesn't go away — all of it lives here. `be-ops` **is not a brickKit component** (not in `brickkit.yaml`) — it's our own command-line tool that reads every component's `assembly.yaml` and produces:

| # | Output | Replaces what the platform doesn't do | Which phase |
|---|---|---|---|
| 1 | **The gateway routing table (three exits)**: components inside a shell → the shell-compose service's `labels` (Traefik's Docker Provider); **platform-generated standalone containers → Traefik file-provider dynamic config, pointing at `http://<host>:<exposePort>`**; K8s → out-of-band Ingress manifests | The platform doesn't do path routing (§6.3); **and the platform-generated compose can't join `be-net`, so the Docker Provider can't see those containers** (Decision 107) | **Phase 3** |
| 2 | **The database-provisioning script**: `CREATE DATABASE` + per-component `CREATE SCHEMA` / `{schema}_archive` / `CREATE ROLE` / grants + the 5 shell login roles | The platform only prints the CREATE statements (§2.7.2) | **Phase 1** |
| 2b | **`resources`' `bindings`**: every component that declares a resource dependency needs a `componentId` entry; in a merged deployment this is **5 PostgreSQL entries** (same host, 5 shell login roles), each with its own set of bindings | **Declaring a resource dependency without a binding makes `up` fail outright** (`006` §4.4). 62 hand-written components are guaranteed to miss one | **Phase 1** (alongside output 5) |
| 3 | **The feature list**: assembly result → written into the IAM adapter layer's `config.enabledComponents` (a **comma-separated string**) | The platform gives components no view of "what's currently assembled" (§6.1) | **Phase 3** |
| 4 | **Shell-merge configuration**: which components go in which shell, port allocation, migration execution order. **What it generates against is each component's `module.New`** (§K / Design Book §12.5.1) — without that single entry point, there's nothing for this output to generate | The platform provides no support for merged deployment (§13.6) | **Phase 4** |
| 5 | **`brickkit.yaml` generation**: including `assembly.yaml` schema validation, `slot` mutual-exclusion validation, `channel` multi-select validation | The platform has no concept of an assembly role (§3.3) | **Phase 1** |
| 6 | **The global port registry**: pairwise-unique HTTP + gRPC ports across 62 components **plus out-of-band container ports** (already written back into the Design Book, see §7) | The platform only errors on a `local: true` collision (§3.5.1.1) | **Phase 1** |
| 7 | **Per-shell environment-variable table**: a same-shell dependency → `http://127.0.0.1:<port>`; **a cross-shell/standalone-container dependency → `http://<host address>:<port>`** | **The platform only injects into the containers it generates itself, and after merging those containers don't exist** (§13.8) | **Phase 4** |
| 8 | **shell-compose's `depends_on`**: start order between shells | The platform only sequences the containers it generates itself (§13.8) | **Phase 4** |
| **9** | **The permission-key registry**: aggregating the `permissions` section of all 62 `assembly.yaml` files → `registry/permissions.tsv` (`key / title / type / owner_component / deprecated`), fed into `infra-authz`'s `config.permissionCatalog` (a **comma-separated string**). Three checks: `menus[].permission` must be in this component's own list, **the key prefix must equal this component's domain**, and no global duplicates | The platform has no concept of permissions; but "assigning a permission" through iam/authz requires first knowing what keys exist — the first link in that chain can only be generated by us (Design Book §14.1.2) | **Phase 1** (build the empty table + validation first) / **Phase 3** (feed authz) |
| **10** | **The master data-scope table**: scanning the `data_scopes` section of all 62 `assembly.yaml` files → `registry/data-scopes.tsv`. ⚠️ **Omitting this section is an error** — a component that doesn't need it must explicitly write `data_scopes: none` | Delivery acceptance and customer security review need "one master data-scope table for the whole system," or the only option is inspecting components one at a time; and if "omitted" meant "none," a missed config would be a silent leak (Design Book §14.2.2) | **Phase 1** |
| **11** | **`authzBundleUrl` injection**: filling `infra-authz`'s address into every component's `configSchema.authzBundleUrl` (alongside outputs 5 / 7) | Business components **declare no dependency** on authz (same as `iamJwksUrl` in §6.1), so the address can only be filled in by us | **Phase 3** |

**Three iron rules for the generator (must be written into `be-ops`'s implementation and tests):**

1. **`labels` values must be strings.** Docker labels and K8s annotations both accept only strings, and the platform **does no automatic conversion**. Booleans and numbers are always quoted on output: `"true"` / `"8080"`.
   ⚠️ **Three more key groups belong to the platform, and writing them fails immediately**: `brickkit.io/*`, `com.docker.compose.*`, `app`. Our own `prometheus.io/*` and `traefik.http.*` are safe, but the generator must explicitly block those three groups (Design Book §5.10).
2. **A component the customer hasn't purchased must be removed from `brickkit.yaml` entirely — never written as `enabled: false`.** A missing entry → a strong dependent fails at parse time, a weak dependent warns and continues without injecting `*_ENDPOINT`; `enabled: false` → it doesn't start, and **everything below it cascades into not starting**. Writing "not purchased" as `enabled: false` would take out downstream master data along with it.
3. **An aggregating component's dependencies must all be `optional: true`.** `infra-bff-mobile` needs to call `batchGet` on every business component, and `infra-notification` needs to call every channel adapter — those dependency lists run to dozens of entries. **Write even one as a strong dependency, and the whole BFF fails to start the moment the customer hasn't purchased that component.**

---

## Part 3 · Repository Topology and the Submodule Arsenal Index

### 3.1 Directory structure

```
be-assembly-standard/                    ← this repo = product root + arsenal index
├── BrickEnterprise 设计书.md            ← Design Book, the specification's source of truth
├── brickkit.yaml                        ← assembly manifest (the second source of truth, §9.1)
├── Makefile                             ← base resources' sole entry point (Part 1)
├── AGENTS.md / CLAUDE.md
├── docs/
│   ├── README.md                        ← triages by reader, the human entry point
│   ├── ops/部署手册.md                  ← the one document a deployer needs
│   ├── standards/00-master-guide.md        ← this file
│   └── design/<repo>.md                 ← component design plans, one per component
├── infra/                               ← compose file #1 of three + check scripts
│   ├── resources.tsv                    ← the declarative resource table (single source of truth)
│   ├── docker-compose.infra.yml         ← the default 5 + optional replacements (profiles)
│   ├── docker-compose.observability.yml ← the observability suite (profile: obs)
│   ├── traefik/traefik.yml
│   ├── casdoor/conf/app.conf
│   └── scripts/
│       ├── check.sh                     ← implements make check
│       ├── up.sh                        ← implements make up (with a full preflight)
│       ├── optional.sh                  ← implements make <res>-up/down (with mutual-exclusion checks)
│       └── arsenal.sh                   ← implements make arsenal-check/restore
├── components/                          ← 【removed from .gitignore】one submodule per component
│   ├── mdm/customer/                    → git@github.com:brickKit/mdm-customer.git
│   ├── mdm/product/                     → git@github.com:brickKit/mdm-product.git
│   ├── erp/sales/                       → git@github.com:brickKit/erp-sales.git
│   ├── ...                              (per the §2.3 master table, added once that tier starts)
│   └── .archived/                       ← brickkit sync's archive area (still in .gitignore)
├── shells/                              ← shells, not under components/
│   ├── go/                              → git@github.com:brickKit/be-shell-go.git
│   └── python/                          → git@github.com:brickKit/be-shell-python.git
├── tools/
│   ├── be-ops/                          → git@github.com:brickKit/be-ops.git
│   ├── be-acceptance/                   → git@github.com:brickKit/be-acceptance.git
│   ├── be-sdk-go/                       → git@github.com:brickKit/be-sdk-go.git
│   ├── be-sdk-python/                   → git@github.com:brickKit/be-sdk-python.git   (added only in Phase 3)
│   └── be-sdk-ts/                       → git@github.com:brickKit/be-sdk-ts.git       (added only in Phase 3)
└── .gitmodules                          ← the "component → repo → exact commit" map
```

### 3.2 Why submodules, and how this satisfies the Design Book

Design Book §3.4.1 requires: "**The 'customer → component repo' map the lead maintainer keeps is the single source of truth, not optional.** For whoever takes this over six months from now, this table is the only thing that can tell them which exact code a given customer's `erp/sales@1.0.0` actually is."

`.gitmodules` **is exactly that table**, and beats a hand-written one on three counts: git-native maintenance, exact commit SHAs, and full recovery in one command, `git clone --recurse-submodules`.

**Why not `brickkit add --repo`:** it relies on a **marketplace-registered Git address** (`publish --git-url`, defaulting to the component directory's `origin`), and Design Book §9.4.1 is explicit that we're following an "entirely local-source, no marketplace distribution" delivery model. With no marketplace, `--repo` has no URL to use. Once marketplace distribution is on the table, `--repo` can become a supplement to submodules (the two don't conflict — a submodule records the same URL).

**The directory path and the repo name differing is expected:** the platform's convention is a source directory of `components/<scope>/<name>` (`003` §116), while the repo name is the flat `mdm-customer` (§5.0). `.gitmodules` records both sides.

### 3.3 ⚠️ The friction between submodules and `brickkit sync` (a discipline that must be established)

`brickkit sync` moves an unstarted component's source — **the whole directory, `.git` included** — with `os.Rename` into `components/.archived/` (`004` §3.9). From this repo's point of view, that's "a gitlink disappears from path A, and an untracked directory appears at path B."

This is precisely the mistake the feature brickKit is currently building will catch. The design confirmed in the brickKit repo (`docs/superpowers/specs/2026-09-02-commit-gate-restore-design.md`) will provide:

- **`brickkit restore`** — restores yaml and directory structure back to the last commit's state, node by node, changing only the `enabled` field
- **`brickkit restore --check`** — the check: **are the yaml and directory structure self-consistent in this commit**. Reads the index (`git show :<config file>` + `git ls-files --cached --stage`); the main check is "yaml says it should run, but the structure is in the archive" → hard-block, exit 1
- **`brickkit init --hooks`** — installs a `pre-commit` hook (located via `git rev-parse --git-path hooks`, correctly handling worktrees / submodules / `core.hooksPath`)

**⚠️ The currently installed CLI has no `restore` command yet** (verified: `brickkit restore` reports "unknown command"). So:

| Period | Use this |
|---|---|
| **Right now** | This repo's own `make arsenal-check` / `make arsenal-restore` + our own `pre-commit` hook (same check, see Task 5) |
| **Once `brickkit restore` ships** | Switch to `brickkit init --hooks`, **delete our own**, to avoid two sets of checks diverging |

**Development discipline (three rules, none optional):**

1. Locally, writing `enabled: false` at the top level to focus on fewer components, followed by `brickkit sync` archiving them — **allowed, and encouraged** (exactly the usage pattern you described).
2. **Before committing, `enabled` must be restored and `sync` re-run to restore the structure.** `make arsenal-restore` does both in one command.
3. The `pre-commit` hook hard-blocks if you forgot step 2, and prints the way out.

⚠️ **Two more operational prohibitions (§9.4.2), even more dangerous under a submodule structure:**

- **`brickkit remove` deletes the archived source directory along with everything else.** If the submodule directory has unpushed changes, this is **data loss**. Confirm the directory is clean (commit & push first) before running `remove`.
- **`components/.archived/` starts with a `.`, hidden by default in file managers.** Look here first when source code seems to be missing.

### 3.4 The criteria for `make arsenal-check` / `arsenal-restore`

Kept consistent with brickKit's own design (to be swapped out once the official version ships, hence deliberately copying the same state table):

| `brickkit.yaml`'s enable/disable state | Where the structure is | Behavior |
|---|---|---|
| should run | active (`components/<scope>/<name>`) | allow |
| should run | **archived (`components/.archived/...`)** | **block** (the one primary check — this is exactly the mistake being guarded against) |
| should run | **both places** | **block** (violates "one component ID, one source directory") |
| should run | neither | allow (the source was never added to the repo, not our concern) |
| shouldn't run | active | allow (sync just hasn't run yet, that's fine) |
| shouldn't run | archived | allow (`enabled: false` committed together = a declared intent) |
| shouldn't run | **both places** | **block** |
| shouldn't run | neither | allow |
| not declared in yaml | either | **always allow** (out of scope for this check) |

Short-circuit condition (to keep this free): `git ls-files --cached --stage -- components/` returning empty → exit 0 immediately.

### 3.5 The standard steps for a repository-creation checkpoint

At each checkpoint, whoever's executing does these three steps in order:

**Step A (before the checkpoint, done by the executor alone)**: build the directory and initial files, but **don't `git init`**.

**Step B (the checkpoint — stop and wait)**: print the following, listing the directories and repo names, then **stop**:

```
⏸ Checkpoint: a Git repository needs to be created by hand

I've already prepared the following directories and initial files:
  <directory list>

Please create these repositories under github.com/brickKit/ (empty repos, no README /
.gitignore / license — otherwise the first push will be rejected due to diverging history):
  <repo name list>

Once they're ready, reply "done" and I will:
  1. In each component directory, git init + first commit + set remote + push
  2. Come back to this repo and git submodule add to wire them in
  3. Move on to the next task
```

**Step C (once you reply "done", done by the executor)**: for every component directory, run:

```bash
# using mdm-customer as the example
cd components/mdm/customer
git init -b main
git add -A
git commit -m "chore: component skeleton (component.yaml / assembly.yaml / contracts / migrations / Makefile / Dockerfile)"
git remote add origin git@github.com:brickKit/mdm-customer.git
git push -u origin main
cd -

# back in this repo, wire it in as a submodule
git submodule add git@github.com:brickKit/mdm-customer.git components/mdm/customer
git add .gitmodules components/mdm/customer
git commit -m "chore: onboard mdm-customer into the arsenal"
git push
```

⚠️ **`git submodule add` requires the target path not already be a git repository, unless it's the exact one being added.** Because by Step C that directory is already its own git repo and already pushed, `submodule add` registers it as a gitlink directly rather than re-cloning — that's the intended behavior. If it reports "already exists in the index," first `git rm -r --cached components/mdm/customer`, then add.

#### 3.5.1 Every repo you'll need to create by hand, and when you'll be asked

**8 non-component repositories** (the 62 component repos are created once their tier starts, see §2.3). **Order may not be moved earlier**: each one needs "Step A's files" ready before the repo gets created — **an empty repo created ahead of time sits idle for months, and an idle repo only accumulates a stale README.**

| Repo name | Directory | When you'll be asked to create it | What's in it |
|---|---|---|---|
| `be-assembly-standard` | this repo | already exists | Product root + arsenal index |
| `be-ops` | `tools/be-ops/` | **CP-1** (Phase 1 Task 6) | The assembly generator, 8 outputs (§2.4) |
| `be-acceptance` | `tools/be-acceptance/` | **CP-1** | The 20 platform acceptance cases + business closed loop + teardown gate + import scan |
| `be-sdk-go` | `tools/be-sdk-go/` | **CP-1** | SOP-L's 14 cross-cutting capabilities + `Runtime`/`Module`/`RunStandalone`/`NewGinEngine` (§K) |
| `mdm-customer` | `components/mdm/customer/` | **CP-2** (Phase 1 Task 11) | The first brick |
| `be-sdk-python` | `tools/be-sdk-python/` | **Phase 3** (before the first Python component) | The Python counterpart, **one-to-one** with `be-sdk-go` |
| `be-sdk-ts` | `tools/be-sdk-ts/` | **Phase 3** | Only half of one: no `withTx`, no hot-cold routing, plus GraphQL-depth limits (§5.10) |
| `be-shell-go` | `shells/go/` | **Phase 4** | The shell launcher: wires up `module.New`, runs migrations, `Listen`s, holds process-level singletons (§12.5) |
| `be-shell-python` | `shells/python/` | **Phase 4** | Same, the Python version |

⚠️ **`be-sdk-python` must come after `be-sdk-go` — this isn't a scheduling call, it's a design one.** The two SDKs' public APIs need to **map one-to-one** (same names, same parameter order, same semantics), or anyone switching between the two languages has to relearn it every time, and an AI will paste Go-style code straight into Python. **Get the Go version solid, exercised by real components first**, then model the Python version on it — doing it the other way guarantees the two diverge.

⚠️ **Never create a repository ahead of time "because we might share it later."** The only criterion is: **is there already a file, written and ready, waiting to be pushed, right now.** If not, don't create it — `.gitmodules` is the "component → repo → exact commit" map Design Book §3.4.1 calls for, and adding a gitlink that points at an empty repo makes whoever takes this over six months from now think there's something there.

---

## Part 4 · The Component Development Standard Procedures (SOPs)

Seven SOPs. **Read SOP-W first — it drives the rhythm of every other one**:

| SOP | What it governs | When to read it |
|---|---|---|
| **SOP-W** | **The AI-driven development loop**: the seven-step cycle, four test layers, red-green rhythm, how much to build per session, what to do when stuck, what the five things a human reviews are | **Read this before starting work** |
| **SOP-D** | A component's four documents (design plan / README / manual / AGENTS.md) | Document 1, before touching anything |
| **SOP-R** | The three-step method for consulting real-world ERPs + which project to look at for which domain | Between design and implementation |
| **SOP-B / SOP-F** | The 14-step output checklist for a backend / frontend component | The main line |
| **SOP-P** | Whether to use a design pattern (judged by whether the AI can quickly understand it) | Judged once, before writing the implementation |
| **SOP-L** | The language base library's 14 cross-cutting capabilities | Done exactly once per language |

From Part 5 onward, each component's task only states its own **parameters and differences** — the process always refers back to this section. **This section is written once and applies uniformly to all 58 components in the project.**

### SOP-W · The AI-Driven Development Loop (**drives the rhythm of SOP-B/F, read this first**)

SOP-B / SOP-F describe "the 14 things a component needs to produce." **SOP-W describes "how to build them step by step"** — how much to do in one session, how many layers of testing, when to commit, what to do when the AI gets stuck.

**This whole scheme is designed for the "AI writes, human reviews" pairing**, and its shape follows from two constraints:

| Constraint | What it implies |
|---|---|
| Every AI session starts fresh, with limited context | Tasks must be cut down to "what fits in one session"; every session needs a fixed reading list at the start |
| A human cannot read 58 components' implementations line by line | A human only reviews what's **irreversible** (contracts, migrations, the invariant checklist); everything else relies on gates — so the gates must actually be able to stop something |

#### W-1 · The seven-step cycle (once per component)

```
① Design the business logic     docs/design/<repo>.md               ← 01-documentation-standard.md §4.1
② Check reference implementations  design your own first → consult only where stuck  ← SOP-R's three-step method
③ Contracts                    contracts/*.proto + events/*.json    ← the design's executable form
④ Write business-rule tests    invariants / state-machine transition tables / property tests  ← ⚠️ before implementation, tests the spec
⑤ Implement                    red → green → refactor, one rule per round  ← one commit per round
⑥ Add unit tests                boundaries, error paths, concurrency  ← after implementation, tests this implementation
⑦ Integrate + gate + document   real PG / real NATS / grpcurl / make all
```

⚠️ **③ must come before ④, and ④ before ⑤ — neither order may be reversed.**

- Contracts before tests: tests need to import the types the contract generates; without a contract, all you can test is a `map[string]any`, and that kind of test is dead the moment you refactor
- Tests before implementation: **this is the boundary between "spec" and "implementation."** Writing the implementation first and adding tests afterward always produces "tests that describe the existing implementation" — they guard against regressions, but not against "the implementation misunderstood the requirement from the start"

#### W-2 · Four test layers (full detail in [`04-testing-standard.md`](04-testing-standard.md) §3)

Tests split into L1 contract / L2 business rule (the spec, written before implementation, not a word of which should change during refactoring) / L3 unit (this implementation's branches) / L4 integration (real PG/NATS/gRPC). Core transactional components' L2 must use property-based tests; mocking to test "a cross-component call happened" is forbidden. **The complete layering criteria, example code, and the criterion for a consumer test's private subject are in [`04-testing-standard.md`](04-testing-standard.md) §3.**

#### W-3 · The red-green-refactor rhythm (full detail in [`04-testing-standard.md`](04-testing-standard.md) §2)

One "red-green-refactor" cycle per session, one commit per cycle; **the single most important prohibition is never changing a test just to make it pass** — if the implementation is wrong, fix the implementation (the default case); if a test really is wrong, that's its own separate commit explaining exactly where the original assertion was wrong — an L2 test standing in the way is almost always a wrong implementation or a wrong understanding. **The complete six-step rhythm and the "change the test vs. change the implementation" decision table are in [`04-testing-standard.md`](04-testing-standard.md) §2.**

#### W-4 · How much to build in one session (full criteria in [`03-ai-development-standard.md`](03-ai-development-standard.md) §2)

The sizing criteria for a session / a red-green cycle / a commit, what a new session should always read first, and what it doesn't need to read — none of this is domain-specific, it applies to any component, and is written once in [`03-ai-development-standard.md`](03-ai-development-standard.md) §2, not repeated here.

#### W-5 · The three ways out when an AI gets stuck (full detail in [`04-testing-standard.md`](04-testing-standard.md) §2.4)

"Stuck" (the same red-green cycle, three rounds in, still not green) — try, in order: ① cut this step smaller ② consult a reference implementation (SOP-R's second step — read it, think it through yourself, then write it, never copy) ③ stop and clearly state what's blocking, hand it to a human — **never route around it** (never comment out a test / add `t.Skip` / loosen an assertion). **Full explanation in [`04-testing-standard.md`](04-testing-standard.md) §2.4.**

#### W-6 · The five things a human review actually looks at (the criteria themselves are in [`03-ai-development-standard.md`](03-ai-development-standard.md) §3)

The full reasoning for "why only these five, why business code doesn't need a line-by-line review" is domain-independent and lives entirely in [`03-ai-development-standard.md`](03-ai-development-standard.md) §3. Here, only where each of the five actually lands in this project:

| # | What's reviewed | Where it lands in this project |
|---|---|---|
| 1 | Contracts | `contracts/`. Once a contract has a consumer, it can only be extended in a backward-compatible way (Decision 19, §3.4 Iron Rule 3) |
| 2 | Migrations | `migrations/`. Partition keys, primary keys, and indexes are fixed when the table is created; changing them after data exists is a migration (§11.2) |
| 3 | The invariant checklist | Whether the invariant checklist inside the L2 business-rule tests is complete |
| 4 | The design document's boundaries/dependencies | `docs/design/*.md` section 1 (boundaries) and section 5 (dependencies) — a mis-drawn boundary, or one extra sync edge, is the one mistake that can pollute the entire architecture diagram (§4.2: the sync graph must be acyclic, zero sync edges between CRM and ERP) |
| 5 | Gate output | `make all`'s 8 ✓ checkmarks |

#### W-7 · Seed data and cross-component test grouping (full spec in [`05-data-construction-standard.md`](05-data-construction-standard.md) and [`04-testing-standard.md`](04-testing-standard.md))

The complete strategy for the two paths — seed data (`make seed`, for humans to explore/demo) and automated test data — ownership, richness criteria, `db-reset` vs. `seed-clean`, cross-component collaboration, security boundaries — is written entirely in [`05-data-construction-standard.md`](05-data-construction-standard.md), not repeated here. Cross-component test grouping is in [`04-testing-standard.md`](04-testing-standard.md) §4. What follows is only the historical record of this pattern being verified on real hardware in this project.

✅ **Pattern verified** (`mdm-customer`/`mdm-product@1.0.4`): both are dependency-chain leaves (zero strong dependencies), the simplest possible sample of this pattern — `make -C components/mdm/customer seed` runs standalone, producing 5 customers covering both `ACTIVE`/`DISABLED` states plus one contact; `mdm-product` likewise covers all three `TrackingType` values. Verified on real hardware: idempotent (ids stable across repeated runs), precisely cleanable (0 residue after `seed-clean`). The root `infra/seed-data/seed.sh` now just calls these two components' own `make seed` rather than reimplementing it. ⚠️ Two criteria corrected during implementation (the original text was too idealized):
  - **The root orchestrator's "order-insensitivity" doesn't hold** — downstream steps like inventory/opportunities need real customer/product ids, so the orchestration script must finish `make seed` for those before moving on, not "call things in any order." What's actually order-insensitive is only that the `seed` targets don't depend on each other (all idempotent, any of them can run first) — not that "the orchestration script may call them in any order."
  - **A component's own `seed.sh` and an orchestration script that needs its output ids hand off through that component's own `command_idempotency` table** — a component's `seed` only cares about loading the data, not about printing ids in some agreed format; whoever needs those ids looks them up themselves: `SET search_path TO <schema>; SELECT result_id FROM command_idempotency WHERE idempotency_key = '<fixed key>'` (use `psql -tA -q` for clean output — **missing `-q` mixes the `SET` command's own acknowledgment into the captured variable**, a real pitfall hit during implementation).
  - ✅ The criterion for identity-type seed data (`infra/iam-casdoor`+`infra/authz` chained calls) has been verified: both components got their own `seed`/`seed-clean`, with `infra-authz` independently querying Casdoor for the `sub` of the test user `infra-iam-casdoor` created (not consuming a parameter passed from the other side) — same as a real strong-dependency chain, each side runs standalone and still works. Found along the way, a real asymmetric Casdoor API bug: `delete-application` given only `{owner,name}` returns `status:ok data:"Unaffected"` (looks successful, deleted nothing) — you must `get-application` for the full object first and pass that whole object back; `delete-user`, in contrast, really does only need `{owner,name}`.
  - ✅ **The criterion for a real strong-dependency chained call has also been verified** (`crm-opportunity@1.0.5`): a genuine strong dependency on `mdm-customer`/`mdm-product` (declared as plain strings in `component.yaml`, with `CreateOpportunity` really calling gRPC `BatchGet` to validate), the `Makefile`'s `seed` target chain-calls them plus the identity exception, and `make -C components/crm/opportunity seed` run standalone gets the full data set (5 opportunities covering every status). ⚠️ Run standalone, the WON opportunity's auto-order-creation trips `erp-sales`'s real TCC compensation and creates an exception task, because `erp-inventory` has no inventory — this is **correct behavior by design** (`crm-opportunity` doesn't depend on `erp-inventory`; `product_id` is an opaque foreign key to it, and stocking real products with inventory has no single owner, left to the orchestration layer), not a regression; the full demo effect of "inventory pre-stocked, order truly `CONFIRMED`" is guaranteed by the orchestration script `infra/seed-data/seed.sh` running steps in the right order (customer/product → inventory → opportunity). Found along the way, two real bugs (logged as pitfalls C18/C19): the hand-written `authzBundleUrl`/`iamJwksUrl` literals for 13 components in `brickkit.yaml` had all 25 references missed when `infra-authz`/`infra-iam-casdoor` were version-bumped (the `dependency-version-scan` gate can't catch this kind of drift — it doesn't scan hand-written strings in the `config` section); a real Casdoor test application, once logged into for real, returns a `get-application` response containing illegal JSON control characters, requiring `strict=False` on both `json.load` call sites.
  - ✅ **The criterion "a zero-dependency component is self-contained + probes for weak connections" has also been verified** (`erp-inventory@1.0.9`): this component explicitly does not depend on `mdm-product` (`product_id` is an opaque foreign key), so `make seed` has two steps — ① always generate a complete self-contained demo dataset with self-assigned ids (two warehouses + receiving/shipping/count-surplus/count-shortfall/in-transit reservation, runs standalone even with an empty `dependencies.components`); ② probe `mdm-product`'s `command_idempotency` table for whether its seed data exists, and if so, opportunistically stock inventory against those real product ids too — establishing no formal dependency edge, purely a dev-tooling-level "connect if you can" — replacing what used to be raw SQL left in the `infra/seed-data` orchestration layer. This is also the first real sample of this section's new "delete is not reset" criterion: this component has no `seed-clean` (`inventory_movements` is append-only), only `make db-reset`, verified on real hardware that after `migrate down` then `up`, balances/movements zero out and `warehouses`' `BIGSERIAL` sequence genuinely restarts from 1, all without restarting the container. Found along the way, two real bugs: Receive/Adjust are declared in the gRPC interface, but the service layer always calls `besdk.ScopeOf(ctx)`, and Claims are only populated by the REST-side `besdk.RequirePermission` middleware — calling either method directly via grpcurl is guaranteed to panic (the same pre-existing criterion as C11; the seed script switched to REST plus a real Bearer token to work around it); grpcurl's default protojson encoding turns underscored proto field names (`reservation_id`) into camelCase (`reservationId`), a different naming convention from the hand-written REST JSON (logged as pitfall C20). **A more important discovery**: `003_seed_warehouses.down.sql`'s `DELETE` collides with the `inventory_balances` foreign key when `migrate down` runs it in reverse order — this path had never once been run on real hardware in this repo's history (the `migrate-idempotent` gate only tests `up`), and `make db-reset` reproduced it on its very first real run, now fixed (logged as pitfall C21). `infra/seed-data/seed.sh`'s inventory step now just calls this component's own `make seed`. ⚠️ **A third discovery, more telling than the first two**: after two full real-hardware rounds of `make seed-data-clean`→`make seed-data` (specifically verifying whether the reset/clean cycle itself is stable), the second round's WON opportunity unexpectedly took the compensation path again — the root cause was that the probing step's `idempotency_key` was fixed by position (`seed-inv-recv-real-$i`); once `mdm-product` was cleaned and reseeded its product ids necessarily changed, but this component has no `seed-clean` (`command_idempotency` doesn't get cleared along with it), so claim-first idempotency kept the fixed key permanently bound to the "first round"'s now-gone old id, and the new id silently never got any inventory. Changing `idempotency_key` to carry the actually-resolved product id (`seed-inv-recv-real-$PID`) means a changed id naturally produces a brand-new key, and the problem disappears (logged as pitfall C22). **This discovery itself confirms the new criterion added to this section**: when a seed script probes a component whose data's ids rotate on clean/reseed, the linking action's idempotency key must include that linked object's real id — never a position-based value unrelated to the id.
  - ✅ **The second real sample of the "delete is not reset" criterion, and for an even stronger reason** (`erp-finance@1.0.6`): this component designed `make seed` from scratch — 5 `PostManualEntry` manual vouchers (covering 5 accounts + single-line/four-line multi-line entries + one real sample that's been through `ReverseEntry` awaiting reversal) + a three-state accounting-period lifecycle demo (`close→lock` as a terminal state, `close→reopen` round trip, `close`-only) + `legal_entity_access` authorizing `dev.superuser`/`dev.finance.viewer` (the same criterion as `erp-inventory`'s `warehouse_access`). This component doesn't decline `seed-clean` merely on the existing "the ledger table is append-only" reasoning — it has an even harder reason: `LockPeriod` is this contract's **only terminal state** — once a period is locked, none of `ClosePeriod`/`ReopenPeriod`/`LockPeriod` can ever turn it back, so row-by-row `DELETE` is physically incapable of cleanly restoring a locked period's state. Verified on real hardware via `make db-reset`: `entries`/`ar_ledger`/`legal_entity_access` all zero out, all 12 accounting periods return to the default `OPEN`, and the `entry_no_seq` sequence genuinely restarts from 1. Along the way, this component **preemptively fixed** a C21-class down-migration-collides-with-a-foreign-key-on-reverse-order bug before it ever occurred: `003_seed_accounts_and_periods.down.sql`'s `DELETE` would collide with `finance_journal_entries`, not yet deleted, when `migrate down` reaches it — this time, learning from C21, the fix was reasoned out purely by reviewing the down file's execution order **before** ever running `migrate down` on real hardware, changed to an empty file ahead of time, then verified successfully once for real (logged as pitfall C23). ⚠️ An additional finding (not a bug, an environment-state fact): `PostManualEntry`/`ReverseEntry` don't accept a caller-supplied business date — a voucher always lands in whichever accounting period contains "the moment the script runs." The seed script originally planned to pick 2026-01/02/03 to demo all three period states, but on real hardware those months already carried real `LOCKED`/`CLOSED` history left over from Task 6's manual verification (predating this script, and predating the test/demo database split) — switched to 2026-04/05/07, confirmed `OPEN`, so the script never fights with another period's operation regardless of the database's historical state.
  - ✅ **`crm-opportunity` redone — the first real trigger of "downstream can, and should, push richness demands back upstream"** (`crm-opportunity@1.0.6`): opportunities went from 5 to 10 — `seed-opp-1..5` kept exactly as-is (created by `dev.superuser`, append-only), and new `seed-opp-6..10` switched to a real JWT for `dev.sales.east` (the East China branch) to call `CreateOpportunity`/`MarkWon`/`MarkLost` (`dept_id`/`dept_path`/`owner_id` are snapshotted from the caller's `besdk.ScopeOf(ctx)` at creation time — you must genuinely switch to that identity's token to call it, not create it and patch in the ownership fields afterward). Verified on real hardware: pulling `ListOpportunities` with `dev.sales.east`'s token shows only `seed-opp-6..10` — the five under `dev.superuser` (no department ownership) are entirely invisible — the org-dimension data-scope boundary of "East China sales can't see other departments' opportunities" now has a real opportunity sample you can log in and experience, not something that exists only inside automated tests. `seed-opp-9` is the second `WON` opportunity (won under the East China identity), verifying that "ownership follows through the won-opportunity-to-order conversion" holds beyond `dev.superuser`'s name too: the order `erp-sales` generates correctly carries the East China department path in `owner_id`/`dept_path`. This round also filled in a time spread (`seed-opp-6..10` backfilled to look like "steadily progressing over the last 2–25 days," using `now() - interval` for absolute values rather than `created_at - interval`, so re-running doesn't drift earlier and earlier — the same criterion already verified for `mdm-customer`/`erp-finance`). ⚠️ **A genuine "downstream pushing back on upstream" scenario was reproduced on real hardware during this** (not a design discussion): the first real run of `seed-opp-9` left its order stuck in `DRAFT`, with `infra-workflow` genuinely producing an exception task — the root cause was that `erp-inventory`'s probe-for-`mdm-product`-seed-data step still used the old range `1 2 3 4` from back when there were only 5 products, while `mdm-product` had by this round expanded to 12, and `seed-opp-9`'s chosen product #7 fell outside the probed range, so `Reserve` found no balance and fell through to TCC compensation — a completely correct existing design path, just not the intended demo this time: the goal here was a genuinely clean confirmed order, not a deliberate compensation demo. Changing `erp-inventory/scripts/seed.sh`'s probe range to `1 2 3 4 5 6 7 8 9 10 11 12` (covering all of `mdm-product`'s current seed products), then `seed-clean` to undo the half-stuck opportunity/order and reseeding, both `WON` opportunities (`dev.superuser`/`dev.sales.east`) got clean `CONFIRMED` orders (logged as pitfall C24). Finally, the cleanup logic that used to live in `infra/seed-data/clean.sh` (reverse-look-up every order from the seeded customer ids and clean them all together) moved into this component's own `scripts/seed-clean.sh` (look up this component's own seeded `WON` opportunity ids → look up `erp_sales.command_idempotency`'s `crm-won:<opportunity_id>` key to get the real order id → delete precisely — more precise than the old fuzzy scan by customer id) — this is one of the preconditions for deleting `infra/seed-data/`, now done; verified on real hardware running the whole `make seed-data-clean`→`make seed-data` cycle from zero, with both `WON` opportunities' order cleanup/rebuild both correct. ⚠️ **This also incidentally resolved `infra-workflow`'s own seed-data question**: this component's `CreateTask`/`CloseTask`/`CancelTask` explicitly expose no REST (the proto's own top comment names exactly why: "the only way a human could create a task is 'a human pretending to be some business component,' and that's exactly a path around the business rules") — a seed script directly grpcurl-faking a `CreateTask` is precisely what that design prohibition exists to block, and it's wrong to route around a component's own architectural security boundary just to "generate some data." The right approach was adding an 11th opportunity, `seed-opp-11`: place an order with qty=100 (the real pricing engine, applying the GLOBAL rule, multiplies out to roughly ¥10000, well past the limit — ⚠️ real pitfall hit: `erp-sales`'s pricing engine ignores an opportunity line's `quoted_unit_price` and genuinely re-queries `pricelist_items`; qty=10 on the first attempt only produced a ¥1000 order, nowhere near enough to trip the credit check) under the low-credit sample customer with a ¥5000 limit (one `mdm-customer` deliberately seeded for exactly this purpose) as a `WON` opportunity — on winning, `erp-sales` genuinely refuses to confirm (the order stays in `DRAFT`), and `createOpportunityExceptionTask` genuinely creates an `infra-workflow` exception task, with `assignee_sub`/`assignee_dept_path` correctly carrying East China ownership — so `infra-workflow` needs no `make seed` of its own, and still gets one real, correctly-org/owner-scoped exception task to look at. This is the first sample of the new criterion: "produce negative-path data via a real business failure, rather than faking it by writing straight into the database."

#### W-8 · Extended test categories (full detail in [`04-testing-standard.md`](04-testing-standard.md) §5)

Permission/data-scope boundary tests, breaking-event-contract-change detection, and localized cross-component testing have all been promoted and wired into `make gates`/`make test-cross`; frontend visual regression has moved to SOP-F's FE-4; the first SDK concurrency-correctness test has been verified feasible (`be-sdk-go`), the other languages still need it. **Full explanation in [`04-testing-standard.md`](04-testing-standard.md) §5.**

#### W-9 · Three run granularities (full detail in [`04-testing-standard.md`](04-testing-standard.md) §7.1)

Full-suite / one-component-complete / a-subset-within-a-component — the same three granularities apply to backend and frontend alike, just with different commands (`make gates`/`pnpm test`, `make test`/`pnpm --filter`, `go test -run`/`vitest <pattern>`). **Full comparison table in [`04-testing-standard.md`](04-testing-standard.md) §7.1.**

#### W-10 · Allowing a wholesale rewrite, not just incremental patching (full criteria and process in [`03-ai-development-standard.md`](03-ai-development-standard.md) §4)

When a wholesale rewrite beats patching, and exactly what process to follow — none of this is domain-specific, and it's written once in [`03-ai-development-standard.md`](03-ai-development-standard.md) §4, not repeated here.

✅ **A verified example**: the seed-data-richness overhaul (the history W-7's paragraphs above link to) is the real-world validation of "seed-data-class judgment calls get a looser rewrite bar" — "adding data" to a component was, most of the time, not a few lines appended to the end of the existing `seed.sh`, but redesigning the whole `seed.sh` around the new criteria. That's the expected way to do this work, not "failed to control the blast radius."

---

### SOP-B · Backend components (Go / Python)

Every backend component repo's file structure (§8.3):

```
<repo>/
├── component.yaml            # what the platform reads. Not one field name may be invented
├── assembly.yaml             # read only by be-ops. The platform never parses this
├── contracts/
│   ├── <name>.proto          # gRPC contract
│   ├── <name>.openapi.yaml   # HTTP contract (external REST)
│   └── events/
│       └── <name>.events.json # event schema
├── backend/                  # business code
│   ├── module/module.go      # ⭐ the sole entry point, New(ctx, rt). Both the shell and main only know this one (§K)
│   ├── cmd/server/main.go    # exactly one line, besdk.RunStandalone(module.New)
│   ├── internal/...
│   └── ...
├── migrations/
│   ├── 001_<...>.up.sql      # raw SQL. Go uses golang-migrate, Python uses yoyo, both raw .sql
│   └── 001_<...>.down.sql
├── Dockerfile                # the base image must contain /bin/sh + wget
├── Makefile                  # the 9 gate targets from §I
└── README.md
```

For a Python component the equivalent locations are `backend/app/module.py` (`create_module`) and `backend/app/main.py` (one line, `besdk.run_standalone(create_module)`).

⚠️ **Phase 3 Task 3 addendum**: the Python-side counterparts to the Go-side `backend/internal/http` and `backend/internal/grpc` directories are **`backend/app/http` and `backend/app/grpc`** — these two directory names had never been documented before (`infra-print` was this project's first Python component, and this only got written down while implementing the Python version of `make gates`'s scanning in Task 3) — now locked in: REST handlers go in `backend/app/http/`, gRPC handlers in `backend/app/grpc/`. These two directories are also the danger zones for both the `SystemClient` misuse scan (§14.2.6) and the bare-route scan (§14.1.7); the criteria are the same as the Go version, except Python has no `go/ast` to use, so it falls back to line-by-line regex (see the precision ceiling documented in the code comments of `tools/be-acceptance/gates/bareginscan.go`/`systemclientscan.go`).

The TS side's `infra-bff-mobile` (a GraphQL BFF, not part of any shell, see §12.4.3) gets one more convention: **the resolver map always lives under `src/resolvers/`, and nothing else goes in that directory.** This is both the danger zone for the `SystemClient` misuse scan and the scope of the bare-resolver scan (the check: a resolver field's value must be wrapped in `requirePermission(perm, resolver)`, never a bare arrow function/`function`) — this closes open question #1 in `docs/design/infra-bff-mobile.md`.

**15 steps, order fixed** (TDD: contract first, tests first):

- [ ] **B-0 Copy the tech stack, don't pick your own**: against the lock-in table in Global Constraint §K / Design Book §12.4, copy this component's language's column cell-by-cell into the skeleton's dependency list. **This step takes two minutes, and saves "discovering some component used Flask on shell-day"** — by which point the implementation is already finished

- [ ] **B-1 Build the repo skeleton's directories and files** (no `git init` yet, wait for the checkpoint). **At the same time, write SOP-D's documents 2 and 4** (the README's 7 sections, `AGENTS.md`'s 6 sections + `CLAUDE.md`); document 1, the design plan, should already exist before this SOP starts
- [ ] **B-1.5 Go through SOP-R**: actually read the modules listed in the design plan's section 8, "reference implementations," before writing the contract. **This step may not be skipped** — edge cases a domain model designed in a vacuum missed don't surface until three months after a customer goes live
- [ ] **B-2 Write `contracts/`**: `.proto` + `events/*.events.json` (+ `.openapi.yaml` for externally-REST components).
      Every aggregate root **must** provide `batchGet` (§3.8, the only legal way for the BFF layer to avoid N+1).
      Every cross-component write endpoint **must** carry an `idempotency_key`, and **must** provide `GetStatus` (§4.5, Schrödinger's timeout).
- [ ] **B-3 Write `component.yaml`**: copy ports from the §2.1 port registry, and `pgSchema`'s default from §2.2. Check Global Constraints B / C / E / F.
- [ ] **B-4 Write `assembly.yaml`**: `asset` / `domain` / `tier` / `edge_routes` / `menus` / `data.schema` / `data.role` / `shell`.
- [ ] **B-5 Write migrations**: partitioned tables are built in the migration (Decision 51); the required fields (§G); a partitioned table's primary key includes the partition key; **the migration-state table lives in this component's own schema**.
- [ ] **B-6 Write failing tests** (tests first, implementation second): **layered per SOP-W's W-2** — this step writes the **L2 business-rule tests** (invariants, state-machine transitions, idempotency), with L3 unit tests left for after B-9. Cover: `/healthz`, every gRPC rpc, `batchGet`, Outbox writes, consumer idempotency.
      Core transactional components (`erp-inventory` / `hrm-payroll-es` / `erp-finance`) **must** introduce property-based tests (Go: `rapid` / `gopter`; Python: `hypothesis`), with a human defining the invariants (e.g. "total inventory can never go negative") and the framework generating random boundary inputs to attack the AI-generated code (§8.0, Decision 49).
- [ ] **B-7 Run the tests, confirm they're all red** (if nothing's red, the tests weren't written correctly)
- [ ] **B-8 Write the minimal implementation**: implement `module.New`, hand back the HTTP handler (a Gin engine) and `RegisterGRPC`, **with the caller doing the `Listen`** — that's `besdk.RunStandalone` standalone, or the shell when merged (§K, Design Book §12.5.1); zero hard-coded addresses in the code; dependency addresses go through `besdk.Endpoint()` (it strips the scheme), **everything else goes through `rt.Config`, zero `os.Getenv` in module code** (§12.5.3); **never touch a process-level singleton, never `log.Fatal`** (§12.5.2). **Before writing this, judge once against SOP-P whether a design pattern belongs here** — `erp-sales`'s pricing, `erp-finance`'s voucher translation, and `infra-notification`'s channel routing have already been decided (SOP-P's P-2 table).
- [ ] **B-9 Run the tests, confirm all green**, then **add the L3 unit tests** (boundaries, error paths, concurrency, whether the SQL is assembled correctly). ⚠️ The L3/L2 boundary: would this test still hold if the implementation were deleted and rewritten in another language — yes → L2, no → L3 (W-2)
- [ ] **B-10 Write the `Dockerfile`**: base `alpine` (Go) / `python:3.11-slim` (Python), with `wget` installed, plus this language's migration tool (Go: `golang-migrate`; Python: `pip install yoyo-migrations`, §K); after `make image`, `docker run --rm <img> sh -c 'wget --version'` must succeed.
- [ ] **B-11 Write the `Makefile`**: all 9 gate targets from §I, fully implemented.
- [ ] **B-12 Run all 9 gates, confirm all green** (gate 9, `make module-check`, guards Iron Rule 7)
- [ ] **B-13 `brickkit up` it standalone and run the six acceptance checks** (see the six-item acceptance table in [`01-Phase 1`](../plans/01-阶段一-地基与第一块砖.md) §2. **Rerun every time a component is added**, §9.6.1 Tier 4)
- [ ] **B-14 commit + push + tag `v<version>`** (the tag must match `component.yaml`'s `version`, §9.1)

### SOP-F · Frontend Components (TypeScript)

Frontend component repo structure (§2.3):

```
frontend-standard/
├── component.yaml            # port: 80, deployment.type: container (the platform has no "static" type)
├── assembly.yaml             # assembly_role: slot, slot_name: frontend
├── apps/
│   ├── pc-web/               # a Vue3 SPA
│   │   └── src/{modules,layouts,router,App.vue}
│   │       # layouts/ holds the §12.6.7 skeleton: service selector / favorites bar / tabs / ⌘K
│   │       #          / org switcher / a flat in-service sidebar
│   └── mobile/               # Uni-app
│       └── {pages,manifest.json}
├── packages/
│   ├── shared-types/         # generated from the contracts
│   ├── api-client/           # generated from the contracts
│   ├── design-tokens/        # ⭐ the only UI asset shared by both ends. Pure data, zero framework imports:
│   │                         #    primary color/color-ramp rules/spacing/font sizes/line height/border radius (§12.6.1.1)
│   ├── ui-kit-pc/            # ⭐ the sole exit point for third-party PC components (AntDV + vxe-table)
│   │                         #    ① AntDV tokens → vxe CSS variables (one source of truth for the theme)
│   │                         #    ② registering AntDV controls as vxe cell renderers
│   │                         #    ③ exports <BeTable>, pages may never use <vxe-grid> directly
│   │                         #    ④ page-level templates <BeListPage>/<BeDetailPage>/
│   │                         #      <BeFormPage>/<BeSettingsPage> (§12.6.7)
│   ├── ui-kit-mobile/        # ⭐ the sole exit point for third-party mobile components (wot-design-uni)
│   ├── shell/                # ⭐ the app skeleton (§12.6.7): service selector / favorites bar /
│   │                         #    in-app tabs / ⌘K command palette / org switcher
│   └── feature-flags/        # dynamic feature routing
├── docker/Dockerfile         # packages the build output into an Nginx image
├── Makefile
└── README.md
```

**Frontend iron rules (§5.9 / §6.4 / §12.6 / Decision 75):**

1. **Never hard-code core business logic**: calculating money, deducting inventory, and core state-machine transitions always happen on the backend.
2. **Own all form-interaction logic outright**: regex validation, field show/hide linkage, debounce/throttle, local draft caching (offline protection). Reject "calling a backend endpoint just to show/hide one field."
3. **Dry-run mode**: complex linkage (e.g. estimating a total price in real time from customer tier + product) **must debounce a call to the backend's `DryRun` / `Validate` endpoint** for the result — never re-implement the backend's formula on the frontend.
4. **Never hand-write `fetch('/api/sales')`** — always use the SDK `packages/api-client` generates from the contract (§3.9).
5. **A route is visible only when `features ∩ permissions ∩ logged-in`, all three layers required** (Design Book §14.1.8). Layer 1, `GET /api/tenant/features`, is **assembly-level** (was this installed in this environment); layer 2, `GET /api/me/permissions`, is **user-level** (can this specific person). Buttons use `v-be-auth="'erp.sales.approve'"` (from `ui-kit-pc`).
    ⚠️ **The symptom of checking feature but not permission is "the menu item is visible, and clicking it lands on a full-page 403"** — an older version of the Design Book conflated the two.
    ⚠️ **Frontend visibility is never a security boundary** (Decision 8): a user editing their local code can always make a hidden menu item appear and navigate to it, and what they'll see at that point is an **empty shell**, because every data request gets rejected by the backend. So the correct goal isn't preventing them from seeing the screen — it's **letting them see it and still get no data**.
    ⚠️ Matching discipline: these two endpoints **only ever return what that user can see** — never send down the full set for the frontend to filter, which would leak "which modules this company purchased."
6. **Language and framework locked**: a Vue3 SPA on PC, Uni-app (Vue3) on mobile, TypeScript throughout, **React firmly excluded** (Decision 79). Contract-generated hooks use `@tanstack/vue-query` (an older version of Design Book §3.9 said "React Query Hooks" — corrected). Neither the frontend nor `infra-bff-mobile` **ever enters a shell** (§13.5), so the TS side has no §K-style module entry contract.
7. Every date picker **defaults to "the last 90 days" selected** (§11.4.4, to prevent an unconscious full-table scan).
8. **The UI layer is locked cell-by-cell** (Design Book §12.6, Decision 111): PC = **Ant Design Vue v4 + vxe-table**, mobile = **wot-design-uni** (fallback `uni-ui`), charts = **ECharts + `vue-echarts`**. **Exact versions — no `^` / `~` / `latest` allowed in `package.json`.**
   ⚠️ **Using different component libraries on the two ends is a design choice, not a compromise** (§12.6.1.1): mobile is card lists / QR scanning / two approval buttons, PC is dense tables and multi-level cascading long forms — **sharing components buys almost nothing to begin with**. So `packages/` splits into `design-tokens` (the only thing shared by both ends, pure data) + `ui-kit-pc` + `ui-kit-mobile`. **Share the tokens, not the components** — doing the reverse gets you a hard-to-use mobile experience and a PC experience constrained by mobile's limitations, both at once.
9. **Third-party UI components may only appear inside `packages/ui-kit-pc` / `ui-kit-mobile`.** Business pages must never `import` a third party directly — swapping the implementation means changing one file, not 40 pages. The **only** valid reason to mix libraries is something AntDV genuinely can't do (a Gantt chart, an approval-flow designer, rich text, a code editor, a big-screen dashboard) — **looks are never a reason** (§12.6.3). ⚠️ **The table is the one exception**: its API surface is too large for a thin wrapper to stay fully faithful — `ui-kit-pc` exports `<BeTable>` covering 80% of usage, and every remaining escape hatch **must get one line logged in `ui-kit-pc/README.md`**, with the test being "this list must stay countable" (§12.6.6 step 4).
10. **The theme has exactly one source of truth**: AntDV's seed token is the source, derived into vxe's `--vxe-ui-*`; `theme.algorithm` and `VxeUI.setTheme()` **must be switched together, inside the same function**. ⚠️ The symptom of not wiring these together is **no error, it runs fine, every ERP table just looks pasted into the page** (§12.6.2).
11. **Visual direction: "restrained professional"**: only change the seed token's primary color, turn on `compactAlgorithm`, use the system font stack (no self-selected font that needs a network fetch or embedding), and business pages **may never hard-code a color value or a spacing number** (all values live in `packages/design-tokens`). ⚠️ **"Good-looking" in this project concretely means "consistent"** — with 62 components' pages generated by an AI in batches, what ruins the look isn't an unadventurous palette, it's "this page uses 16px spacing, the next page uses 20px" (§12.6.5).
12. **The app skeleton is built in-house**, but per SOP-R's three-step method, read `vue-vben-admin`'s layout / router+access / request pieces (Decision 112, §12.6.4). **Only read its implementation technique, never copy its navigation shape** — the shape is fixed in the next rule.
13. **The skeleton shape is locked: AWS-Console-style two-tier navigation** (Design Book §12.6.7, Decision 113). A top-bar "▾Services" dropdown (an overlay, doesn't leave the current page) + a **favorites bar** + a ⌘K command palette + an **org/legal-entity switcher**; **in-app tabs** below the top bar; an in-service sidebar **forced flat, 3–5 items, never collapsible**, with a fixed "Component Settings" at the bottom.
    ⚠️ **Never spread this into a left-hand multi-level tree**: the menu is aggregated at generation time from 62 `assembly.yaml` files, **every customer's installed component set is different so that tree has a different shape for every customer**, leaving an AI generating a page with no idea which level it belongs on.
    ⚠️ **Three things must change when copying AWS**: it has no in-app tabs (an unsaved ERP outbound-shipment form would get eaten by a browser refresh), its in-service menu depth is inconsistent, and its Region switcher becomes our org/legal-entity switcher.
14. **Business pages may never start from a blank `<div>` and lay out from scratch**: always start from a page-level template in `ui-kit-pc` — `<BeListPage>` / `<BeDetailPage>` / `<BeFormPage>` / `<BeSettingsPage>`, pick a template, fill in the slots.
    ⚠️ This is the reinforced version of iron rule 11, aimed at **AWS Console's single most-criticized flaw**: every page does its own thing, and twenty services end up looking like twenty different products. **Our disease is identical — 62 components' pages are generated by an AI in batches.**
15. **Only four preferences belong to the user** (Design Book §12.6.8, Decision 114): favorited components, light/dark/follow-system, standard/compact density, language; table column width/order is a fifth, but **purely local, never synced**. Primary color / logo / watermark / grayscale are **assembly-time configuration**, and **layout-mode switching doesn't exist**.
    ⚠️ **`packages/design-tokens` must be runtime-writable CSS variables, never TS constants compiled into the bundle.** Both light/dark and compact need to switch tokens at runtime, and writing them as constants makes that physically impossible — **and by the time this is noticed, dozens of pages are already written.** This is the one item in the entire frontend design with real time pressure, and must be locked in before the first page is written.

16. **A `401 token_stale` must trigger a silent refresh and exactly one retry** (Design Book §14.1.6): when `packages/api-client` receives a 401 with `error="token_stale"` → silently refresh → retry the original request with the new token, **only once** (to prevent an infinite loop). This is the frontend half of "a role change also takes effect in ~15 seconds"; without it, a role change has to wait out the token's TTL.

#### F-Testing · Frontend Test Layering (full detail in [`04-testing-standard.md`](04-testing-standard.md) §6)

FE-1 (unit) / FE-2 (component) are already in use; FE-3 (end-to-end, Playwright) / FE-4 (visual regression) are explicitly deferred to a single pass once frontend feature work is basically done — the skeleton is already fixed, ready to fill in then. The right fix for contract drift is building `packages/api-client` (types generated from the contract), not chasing it with more tests — that's a one-time build cost, still pending. **Full layering criteria, current-state check, and skeleton design in [`04-testing-standard.md`](04-testing-standard.md) §6.**

### SOP-L · Language Base Libraries (done exactly once per language)

The following logic is **implemented exactly once per language**, and every component imports it rather than rewriting it:

| Capability | Why it must live in the base library |
|---|---|
| `endpoint(dep, extra)` — reads a **component address** `*_ENDPOINT` and `TrimPrefix("http://")`s it | §D: `grpc.Dial("http://host:9094")` fails to connect, and the error points at name resolution, extremely hard to trace |
| `storageEndpoint()` — reads `STORAGE_ENDPOINT` and **adds** the scheme | §D: the one variable whose name contains `ENDPOINT` but whose value is bare `host:port`. **Opposite direction** from the previous one — sharing one function guarantees one side breaks |
| `withTx(ctx, fn)` — `BEGIN; SET LOCAL ROLE; SET LOCAL search_path; ...; COMMIT` | §G: `SET` without `LOCAL` leaks data across components with no error |
| Outbox writes + a push thread | §H: a producer must use the Outbox |
| Event-header inject/extract (`trace_id` / `causation_id` / `hop_count`) + cycle-guard discard | §H: `hop_count > 5` goes straight to the DLQ |
| Consumer idempotency + monotonic `version` validation | §H: immune to reordering and duplicates |
| OTel SDK initialization (`otelBaseUrl` empty → Blackhole Exporter) | §7.5: an unreachable collector must fail silently, never block a business thread |
| List APIs auto-inject a time window (default: last 90 days) + cursor pagination | §11.4: business code always just writes `SELECT * FROM sales_orders` |
| `batchGet` auto hot-cold routing (hot table first, fall back to `{schema}_archive` on a miss) | §11.6.1: business code never writes `if archived` |
| Structured JSON logging + automatic trace-context injection + PII redaction + 2KB payload truncation | §7.3 |
| RED metrics auto-exposed (Rate / Errors / Duration), 15s scrape interval | §7.4 |
| **Functional permission checks**: `GET /authz/bundle` pulled conditionally every 15s → an **in-process memory map**; `besdk.GET/POST(r, path, permKey, h)` registration is itself the authorization check; a `stale_since` hit → `401 token_stale` | Design Book §14.1: **zero permission tables in any component**. Missing a permKey fails to compile; degrades fail-static, returning `503` at startup if the bundle hasn't loaded yet while `/healthz` stays healthy as usual |
| **Data-scope resolution**: computing a `ScopeFilter` from the JWT's `dept_path`/`sub` plus the `data_scopes` config, placed into `ctx`, consumed by repository methods | Design Book §14.2.3: the five tiers degrade to a pure function, **no org-tree replica needed** |
| **Two calling identities**: `UserClient` (forwards the JWT) / `SystemClient` (the component's own identity, bypasses data scoping) | Design Book §14.2.6: misusing `SystemClient` on a user-request path = data scoping bypassed entirely, with **no error**. `make gates` scans for this: `SystemClient` may only appear inside `Start()` and event handlers |

⚠️ **The base library is not a "shared model package."** It holds only the cross-cutting capabilities above, all business-agnostic. **Never** extract a shared model package for two components to use together — contracts live in `contracts/`, code is never shared (§13.3 Iron Rule 6).

#### L-1 · `Runtime` / `Module` / `RunStandalone`: the base library's three most important types

The table above is "cross-cutting capability" — these three types are **structure**: they decide whether a shell can plug a module in at all (Design Book §12.5, §13.3 Iron Rule 7).

```go
package besdk

// Runtime is everything the caller hands the module. The module fetches nothing on its own.
//   Standalone: filled by RunStandalone (reads process env vars, opens its own pool, connects its own NATS)
//   Merged: filled by the shell launcher (this module's slice of the env map, the shell's one global pool, a shared NATS connection)
type Runtime struct {
    ComponentID      string
    ComponentVersion string
    Config           Config          // ⭐ the module's only entry point for config. No os.Getenv
    DB               *sql.DB         // ⭐ the shell's single pool, when merged (Iron Rule 2)
    NATS             *nats.Conn
    Logger           *slog.Logger    // already injected with component_id and trace context
    Tracer           trace.Tracer
    Meter            metric.Meter
    Registry         *prometheus.Registry // ⭐ one per module, not the default global one
    HTTPPort         int             // from component.yaml, not an environment variable (§13.8.1)
    ExtraPorts       map[string]int  // {"grpc": 9090}
}

// Module is everything the module hands back. The module itself never Listens, never registers
// anything globally, never installs a signal handler.
type Module struct {
    HTTPHandler  http.Handler                 // ⭐ the shell is completely unaware of Gin
    RegisterGRPC func(*grpc.Server)
    Migrations   fs.FS                        // the shell runs these in topological order (Iron Rule 5)
    Start        func(context.Context) error  // a background loop. Must accept ctx, return on cancel
    Stop         func(context.Context) error
}

// RunStandalone is the entire standalone-deployment assembly, and also the **only place in the
// whole project allowed to read process environment variables**.
// It does: Bootstrap (OTel/logging, once per process) → fill Runtime → call newModule →
// run migrations → Listen on HTTP and every extraPort → install signal handlers → graceful shutdown.
func RunStandalone(newModule func(context.Context, *Runtime) (*Module, error))

// NewGinEngine hands back a Gin engine with every middleware already wired: OTel, request-id,
// error → gRPC status mapping, PII-redacted logging, RED metrics, /healthz, /metrics.
// ⚠️ A component may never call gin.New() itself — missing one piece of middleware produces no
// error, that component just permanently has no tracing from then on.
func NewGinEngine(rt *Runtime) *gin.Engine
```

The Python side is symmetric: `Runtime` (a dataclass), `Module` (a dataclass, `asgi_app: FastAPI`), `run_standalone(create_module)`, `new_fastapi_app(rt) -> FastAPI`.

#### L-2 · The "process-level singletons" the base library must intercept on the module's behalf

| Thing | How the base library provides it | What happens if a module does it itself |
|---|---|---|
| OTel provider | `Bootstrap()` once per process; a module uses `rt.Tracer` | `SetTracerProvider`: **whichever `init` runs last wins**, all 22 modules' traces end up under one `service.name`, and **everything stays green** |
| The logging root | `rt.Logger` already derived | `logging.basicConfig()` is process-level — whoever calls it first wins, and the other 20 modules' log format is overridden |
| Prometheus registry | `rt.Registry`, **one per module** | Using the default global registry: Go `MustRegister` **panics**, Python throws `Duplicated timeseries`. 100% fine standalone, crashes the moment a second module comes up in the shell |
| Signal handlers | installed by `RunStandalone`; installed by the shell in a merged deployment | 5 `uvicorn.Server`s fighting over SIGTERM, `docker stop` can't shut down cleanly |
| **Gin's package-level globals** (`gin.SetMode` / `gin.DefaultWriter`) | set once in `Bootstrap`; `NewGinEngine` never touches it | these are **package-level variables**, not engine fields. One module calling `gin.SetMode(gin.DebugMode)` puts **the other 21 modules into debug mode too** (panic stack traces sent straight to the client). It looks like "setting my own engine," which is exactly why it's the easiest one to get wrong |
| Connection pool | `rt.DB` | Iron Rule 2: a module privately calling `sql.Open()` is already ruled out |
| Process environment variables | `rt.Config` (the only place that reads env is inside `RunStandalone`) | `PG_SCHEMA` and every `configSchema` entry overwrite each other across 22 modules, **with no error** — a module reads and writes data against someone else's schema (§12.5.3) |
| Process exit | return an error to the caller | one `log.Fatal` call, and **the entire group of 22 components is gone** |

---

### SOP-R · Reference-Implementation Discipline (check real-world projects before writing a line)

**Every component's business logic should start by looking at how a mature real-world ERP/CRM does it.** This isn't modesty — an ERP's domain model was hammered out over decades of real pitfalls, and an order state machine, an inventory ledger, or an accounting voucher designed from scratch will almost certainly miss edge cases — ones that don't surface until three months after a customer goes live.

**The complete methodology** (the three-step method, why closed-source products are worth consulting too, the licensing criterion, how to record what was consulted, how to recognize a "slot-family" signal) is domain-independent, applies to any component, and is written once in [`02-reference-implementation-standard.md`](02-reference-implementation-standard.md), not repeated here. What's left here is this project's own specific part: **R-2, which project's which piece to look at for which domain.**

#### R-2 · Which project's which piece, for which domain

| Our component | First-choice reference | What to look at | License | What to avoid |
|---|---|---|---|---|
| `mdm-product` | **Odoo** `addons/product` | The `uom.uom` table design plus conversion factors, the `tracking` (none/lot/serial) enum | LGPL-3 | — |
| `mdm-customer` / `mdm-supplier` | **Odoo** `addons/base` (`res.partner`) | The trade-off of one partner table covering customer/supplier/contact | LGPL-3 | `res.partner` crams company, individual, address, and bank account all into one table — **we deliberately split these apart** (the three-way test: different data ownership) |
| `erp-inventory` | **ERPNext** `stock` (Stock Ledger Entry) | The core design of **an immutable ledger with balances as a projection**; batch/serial tracking | GPL-3 | — |
| ↑ same | **Odoo** `addons/stock` | The `stock.move` state machine, `stock.quant`'s reservation semantics | LGPL-3 | quant's double-write under high concurrency relies on a database lock — we use a conditional update directly instead (§4.4) |
| `erp-sales` / `erp-purchase` | **Odoo** `addons/sale` / `purchase` | The order state machine's states and transition edges, the quote→order→ship→invoice separation | LGPL-3 | Pricing logic scattered across multiple `_compute`s — we centralize it in one pricing module (Decision 69) |
| ↑ pricing | **metasfresh** pricing | The rule model for price lists / discount tiers / promotions | GPL-2/3 | The rule engine is over-configurable — nobody at a delivery site ends up configuring it |
| `erp-finance` | **Tryton** `account` | The rigor of double-entry bookkeeping, accounting periods and period-close (**this is where Tryton beats Odoo**) | GPL-3 | — |
| ↑ same | **ERPNext** `accounts` | Accounting Dimensions, numbering (naming series) | GPL-3 | — |
| `erp-manufacturing` | **Odoo** `addons/mrp` | Multi-level BOM expansion, work orders and operation reporting | LGPL-3 | MRP calculation is tightly coupled to business objects, hard to test independently |
| `crm-lead` / `crm-opportunity` | **EspoCRM** / **SuiteCRM** | The Lead→Opportunity conversion flow, stages and win rates, the funnel | GPL-3 / AGPL-3 | — |
| `crm-customer` | **Twenty** | Modeling ownership/assignment and the public/private pool concept | AGPL-3 | — |
| `crm-activity` | **EspoCRM** activities | The unified activity model for visits/calls/schedules | GPL-3 | — |
| `infra-workflow` | **Camunda** / **Flowable** | **Only the "task aggregation and to-do list" layer** | Apache-2.0 | ⚠️ **Never bring in a BPMN engine** — Design Book §6.6 explicitly forbids workflow from containing business rules (Decision 27) |
| `infra-print` | **Odoo**'s report engine (QWeb) | Separating templates from data, template version management | LGPL-3 | It's tied to wkhtmltopdf; we use WeasyPrint |
| ↑ ZPL barcode | **Zebra's official ZPL II Programming Guide** | The instruction set itself (a specification document, not code) | Vendor documentation | — |
| `infra-notification` | **Novu** | Notification intent → user channel preference → concurrent multi-channel routing | MIT | — |
| `infra-bff-mobile` | **Medusa**'s modularity + workflow SDK | The API shape of Saga orchestration (how compensation steps are declared) | MIT | — |
| `hrm-payroll-es` | Odoo's `hr_payroll` **structure** | How pay items declare dependencies and get calculated in order | LGPL-3 | ⚠️ Spain's IRPF / Seguridad Social **specific rules go by the official regulation**, never copy a tax-rate table from any open-source project — rates change yearly, and a copied one is guaranteed to be stale |
| `erp-quality` / `erp-maintenance` / `erp-asset` | The matching Odoo addons | Field design for routine CRUD and state machines | LGPL-3 | — |
| `frontend-*` **app skeleton** | **vue-vben-admin** | **Only three pieces**: `layout` (sidebar / multi-tab / breadcrumb organization), `router` + `access` (the timing and guard order of route and permission registration), the `request` wrapper (interceptors, error-code-to-message mapping, concurrent dedup) | MIT | ⚠️ **Never pull it in as a dependency** (Decision 112): its routing+permission layer is driven by a backend menu table or static routes with role codes, while ours is driven by `GET /api/tenant/features` feature flags — strip that layer out and all that's left is a layout, with the whole dependency tree still attached. **Read it, don't install it** |
| ↑ page patterns | **Ant Design Pro**'s page patterns (not its code — that's React) | The **information structure** of list/detail/form/multi-step-form pages: where the filter area goes, where bulk actions go, how the detail page's tabs switch | MIT | Copy zero lines of the React implementation; only look at its page-structure conventions |
| `frontend-*` **tables** | **vxe-table**'s official examples | Editable cells + putting a third-party control in an `#edit` slot, the configuration boundaries of virtual scroll and frozen columns | See §12.6.6 ⚠️ | ⚠️ **Some capabilities are commercial-tier** — check each one we plan to use against the free tier before starting, and write the conclusion into the design plan's section 8 |
| **Overall modularity trade-offs** | **Apache OFBiz** | Its entity model (`OrderHeader` / `OrderItem` / `InventoryItem` / `AcctgTrans`) is **extremely complete**; the `Service Engine`'s event triggering (SECA) | **Apache-2.0** ← **the only large ERP that can be copied directly** | Java plus heavy XML configuration, doesn't fit our Go/Python stack |

**Common chronic problems to avoid (shared by almost every open-source ERP, and the very reason this project exists):**

| Chronic problem | How we avoid it |
|---|---|
| Every module shares one process, one database, and can JOIN across tables — the boundary is a soft convention, broken daily | Independent processes + independent schemas + a **physical** PG-RBAC wall (Design Book §1.1, §1.2) |
| Customization via `_inherit` / monkey patches / hooks, all of which break on upgrade | Fork the whole repo + lock the contract (§3.4, Decision 25) |
| Everything metadata-driven (DocType / dynamic fields), no strong typing, neither AI nor an IDE can infer anything | Contract-first (Protobuf/OpenAPI) + a strongly-typed language |
| Reports scanning the raw transaction table directly, BI queries dragging down core business | Decision 61: reports must go through a summary table or `ana-bi` |
| Unbounded tables that eventually bury the system under its own historical data | Partition at table-creation time + automatic archival (Design Book Chapter 11) |

**The full methodology for R-3 (how to record what was consulted) and R-4 (how to recognize a slot-family signal) is in [`02-reference-implementation-standard.md`](02-reference-implementation-standard.md) §2/§4.** Applied to this project, a new slot family R-4 discovers needs to go through that standard's §4 step 1, "formal registration" — concretely, **go back to the Design Book and add the family** (§5.11.1, Decision 104): the family name, the slot's semantics, guaranteeing the contract surface is identical across every member of the family, which customer profile each member fits, and which one is installed by default; sync §5.13's component count + Appendix H; and append entries (never edit) to `registry/ports.tsv`/`schemas.tsv`.

---

### SOP-P · When to Use a Design Pattern (a criterion, not a preference)

**Using a design pattern is never mandatory, but where it fits, it must be used.** The complete criteria (the one-sentence standard, the concrete signals that help or hurt an AI, when to use one and when not to, how to organize the files once applied) are domain-independent, apply to any component, and are written once in [`03-ai-development-standard.md`](03-ai-development-standard.md) §1, not repeated here. What's left here is the handful of places this project has already decided to use one.

#### P-2 · Places this project has already decided to use a pattern

These don't need re-judging — just do them; their branch count and rate of extension are already predictable:

| Component | Location | Pattern | Why |
|---|---|---|---|
| `erp-sales` / `erp-purchase` | Pricing and discounts | **Strategy + chain of responsibility** | Pricing rules are the textbook case of "20% wildly customer-specific and frequently changing" (§1.1). A forked deployment will almost certainly need to add a rule — with a chain, adding a rule means adding a file |
| `erp-sales` | Order state machine | **An explicit state table** | The legality of a state transition must be centralized — scattered, it's guaranteed to miss one |
| `erp-inventory` | Inbound/outbound document types | **Strategy** | Receiving/shipping/transfer/count/return each have their own validation, but all land in the same ledger table |
| `erp-finance` | Translating business documents into accounting vouchers | **Strategy (one translator per document type)** | Its entire job is "translating business data into an accounting voucher" (Appendix I). Adding a document type = adding a translator, without touching the existing ones |
| `infra-notification` | Channel routing | **Strategy + registry** | Channels are a `channel` multi-select that coexist (Decision 26), and are **registered dynamically based on which environment variables exist** (§2.4 Iron Rule 3) |
| `infra-print` | Rendering backend (PDF / ZPL) | **Strategy** | The two output implementations share nothing in common, only their input arguments match |
| `hrm-payroll-es` | Pay-item calculation | **Strategy + topological sort** | Pay items depend on each other (social-security base → taxable income → IRPF); calculate them in the wrong order and the numbers are wrong |
| Every component | Saga compensation steps | **Command** | Every step must be reversible, and persistable to a `saga_transactions` table so it can resume after a restart |
| `be-ops` | The 11 outputs | **One package per output, one unified interface** | Already decided in this document's §2.4 |

---

### SOP-D · A Component's Four Documents (the full templates have been merged into [`01-documentation-standard.md`](01-documentation-standard.md) §4)

The four documents aren't a wrap-up chore — they're **four concrete steps in the development flow**: document 1 comes before SOP-B/F, documents 2 and 4 are written while scaffolding the skeleton, and document 3 grows in step with the implementation. **What exactly each one contains, what the template looks like, and how the gate checks it** is domain-independent, and has been merged in full into [`01-documentation-standard.md`](01-documentation-standard.md) §4 (which has subsections D-1 through D-4 plus a §4.5 gate table), not repeated here — the old D-1 table of "which of the nine questions maps to which Design Book section" had its specific section numbers (§3.1, §11.2, §14.2.2, etc.) replaced with generic phrasing in the new standard; which Design Book section actually applies in this project is still governed by the numbers cited elsewhere in this document.

---
## Part 5 · Phase Overview

**Order may not be changed** (Design Book §9.6, Decision 95). Each tier is a precondition for the next, and **building the shells must come after the arsenal is fully stocked** — a shell's pitfalls are structural: hit one at 13 components and you fix `be-ops`; hit the same one at 62 components and you're rewriting code across 61 manifests.

### 5.1 The seven phases at a glance

| Phase | Name | Component count | Goal, one line | Shipping condition | Plan file |
|---|---|---|---|---|---|
| **1** | Foundation and the first brick | 1 | The environment comes up in one command; the first brick can live on its own | `mdm-customer`'s six acceptance checks all green | [`01-Phase 1`](../plans/01-阶段一-地基与第一块砖.md) ✅ **shipped** |
| **2** | Prove the platform | +4 = 5 | Every promise brickKit makes actually holds | Design Book §9.6.2's **20-item platform acceptance list**, checked off one by one | [`02-Phase 2`](../plans/02-阶段二-验平台.md) ✅ written, all four design plans ready (not yet started) |
| **3** | Business closed loop | +9 = 14 | One business chain genuinely runs end to end, with authorization moving from stub to real | Appendix E's full chain + Saga compensation + timeout query + DLQ in/out + `infra-authz` live | to be written |
| **4** | Build the shells, verify teardown | 14 (merged into 2 shells) | Verify that "merging doesn't grind away componentness" | Merged-state closed loop all green + **teardown gate all green** + import scan all green + all three compose files start/stop in one command | to be written |
| **5** | Fill out the `default` set | +5 = 18 | Reach the minimum deliverable shape | Every component added reruns the six acceptance checks + the teardown gate | to be written |
| **6** | Stock the shelves to order | +37 = 55 | The arsenal is fully stocked | Same as above, one at a time | to be written |
| **7** | Full K8s form | —— | Fully torn apart, onto the cloud | One Deployment/Service per component | written only once a customer buys K8s |

Mapped to Design Book §9.6.1's tiers: Phase 1 = foundation + Tier 0, Phase 2 = Tier 1, Phase 3 = Tier 2, Phase 4 = Tier 3, Phase 5 = Tier 4a, Phase 6 = Tier 4b, Phase 7 = §13.4's Phase 3.

⚠️ **Each phase's plan is written only after the previous phase ships.** The process is fixed:

```
Phase N ships
  → retrospective: which assumptions didn't hold, where the Design Book and reality diverged
  → fix the Design Book first (if it can't be fixed yet, log a red case in be-acceptance instead)
  → then write Phase N+1's plan file
  → then write docs/design/<repo>.md for the components that phase touches
  → start work
```

**Never skip "fix the Design Book first."** Whatever gets routed around here becomes 61 separate workarounds by the time there are 62 components (§9.6.2).

⚠️ **The Design Book is the best possible split, made before any component had been implemented** (Decision 104). So every tier's retrospective should expect it to change, and the feedback usually takes one of these three shapes:

| Feedback shape | Symptom | Action |
|---|---|---|
| **A platform assumption doesn't hold** | The Design Book says the platform does X, testing shows it doesn't | Log a red case in `be-acceptance` first (even if it stays red), then go fix it in the brickKit repo. **Never work around it on the business side** (§9.6.2) |
| **A component boundary was drawn wrong** | Partway through implementation, a field/responsibility turns out to be in the wrong component, or two components need an edge the Design Book doesn't have | Fix the Design Book's domain map / dependency graph / §5.x responsibility table, then fix the code. **Be careful not to casually add a sync edge while doing this** — Design Book §4.2 requires the sync graph to be acyclic, with zero sync edges between CRM and ERP |
| **This should be a slot family** | Consulting multiple ERPs turns up multiple implementations of the same feature, **each one reasonable**, just fitting a different customer | Follow §4 SOP-R's **R-4**, four steps: register the new family in the Design Book first (§5.11.1) → sync the component count and port registry → confirm there's no dependency edge → then implement. **This is the main way the shelf grows** (Decision 104) |

**The end goal isn't "finish implementing the 62 in the Design Book" — it's this: we end up with our own default ERP, where every functional component can have multiple implementations, and a customer picks the one they need, even doing closed-source customization on top of whichever is closest to what they want — which is exactly what minimizes our own future customization time.**

### 5.2 Roughly what each phase does

#### Phase 1 · Foundation and the First Brick

Stand up the environment and the rules, then walk one simple brick through all of it.

- Two compose files for base resources (the default 5 + 5 replacements + the observability suite) plus a `Makefile` (one-command query / one-command bring-up / individual toggles)
- The global port registry and schema registry, on disk with self-consistency checks — **these two tables must be locked before the first `component.yaml` is written**, since gRPC ports have no after-the-fact remedy (§3.5.1.1)
- `components/` converted to git-submodule tracking, with an arsenal self-consistency gate
- Three non-component repos: `be-ops` (the assembly generator), `be-acceptance` (acceptance tests), `be-sdk-go` (the cross-cutting base library)
- One component, `mdm-customer`, taken all the way through SOP-D + SOP-B

**Why `mdm-customer` is the first brick**: it's a read-only hub with an empty `dependencies.components` (§2.6), so it can run standalone with no other component present — exactly what "one brick can live on its own" needs to prove.

#### Phase 2 · Prove the Platform

Add `mdm-product`, `erp-inventory`, `erp-finance`, `erp-sales` — four bricks.

**This tier's test subject is brickKit, not our business.** These four plus `mdm-customer` happen to form the shortest chain that includes a strong dependency, mutual gRPC calls, Saga compensation, and event aggregation — enough to pierce every assumption the platform makes with one vertical slice (§9.6.0). Design Book §9.6.2's 20 test cases all land in `be-acceptance` at this tier — **rerunning them after every platform upgrade is the regression suite.**

#### Phase 3 · Business Closed Loop

Add `infra-iam-casdoor`, `infra-authz`, `infra-workflow`, `infra-notification`, `integration-im-dingtalk`, `crm-opportunity`, `infra-print`, `infra-bff-mobile`, `frontend-standard` — nine bricks, rounding out the 14 in Design Book §5.13's "Slice" column (checked off in Appendix H's "Slice" column, which is exactly this list).

⚠️ **`infra-authz` was once missing from this list** (found when cross-checking §9.6.1/§14.3/Appendix H against each other during the Phase 2 shipping retrospective — the first was undercounted, the other two had always been right) — now corrected. This tier isn't only about the business chain running — **authorization itself must also move from Phase 2's fail-closed stub to `infra-authz`'s real bundle polling** — the endpoints Phase 2's five components marked `Public` need to go back and use real permission keys, or the "business closed loop" that runs is really a loop with authorization wide open, proving none of Chapter 14's promises.

The chain to prove: **CRM wins the deal → order created → inventory locked → receivable generated → approval → DingTalk notification → print the delivery-note PDF** (Appendix E). This tier also introduces the other two languages, so `be-sdk-python` and `be-sdk-ts` need to exist first.

⚠️ `infra-print` is Python; the reason it's in this slice isn't business need, it's that **Phase 4 needs it to prove the Python shell** (§9.6.1).

#### Phase 4 · Build the Shells, Verify Teardown

Merge the 14 components into **2 shells** (the Go shell holds 11 modules, the Python shell holds `infra-print`); `infra-bff-mobile` and `frontend-standard` stay standalone containers (cross-language can't merge, and neither can Nginx, §13.5).

This tier requires `be-ops` to complete outputs 4/7/8 (shell-merge configuration, **per-shell environment-variable tables**, cross-shell `depends_on`). Of these, **output 7 is the hole the Design Book explicitly calls out as the one that will really blow up at a delivery site**: the platform only injects into the containers it generates, and after merging those containers don't exist; a same-shell dependency points at `127.0.0.1`, **a cross-shell one must point at the host** (§13.8).

The core of shipping this phase is the **teardown gate**: strip out every `local: true`, `brickkit up` the fully-torn-apart form once, and the business closed loop must stay all green. **Failure here doesn't mean "the teardown has a bug" — it means "the moment of merging ground away componentness"** (§13.7).

#### Phase 5 · Fill Out the `default` Set

Add `infra-storage` → `infra-attachment` → `infra-dlq-monitor` → `mdm-supplier` → `mdm-org`, five bricks (ordered by dependency: storage must come before attachment).

All five have the assembly role `default` — "load-bearing for the system to run at all, mandatory by default" (§3.3). **They don't wait for a customer to ask.** Once this tier is done, the system has reached its minimum deliverable shape.

At the same time, split Phase 4's "temporary Go shell used for verification" per §13.2 into Shell 1/2/3 — **this is the first time cross-shell environment variables are genuinely exercised** (Phase 4 only ever verified Go↔Python).

#### Phase 6 · Stock the Shelves to Order

The remaining 37 components, **queued by customer-order priority, moved only once the first customer names one.**

⚠️ The 62 "✅ to develop" entries in Design Book Appendix H describe the arsenal's final shape — **they are not a start order.** Per Chapter 1's **optional-component test** (a customer would pay for it separately, or it would otherwise never get used → only then does it become its own brick), the other 4 IM channels, the 4 payment channels, the 3 e-signature channels, the 2 IAM replacements, and the 3 extra frontends should mostly stay queued. **Starting all of them now is spending money in exactly the way the optional-component test exists to prevent.**

Every time a component is named, the process is the same fixed eight steps: confirm scope → check the registries (ports and schemas are already allocated, **do not change them**) → write `docs/design/<repo>.md` → build the directory → stop and ask a human to create the repo → wire in the submodule → go through SOP-D/B/F → **rerun the six acceptance checks + the full gate suite**. Never batch step eight — if the teardown gate goes red, you need to know exactly which component caused it.

#### Phase 7 · Full K8s Form

⚠️ **Merged deployment is only for single-machine Docker delivery — going to K8s means tearing everything apart, there's no middle state** (Decision 88). `local: true` may only pair with `deploy.target: docker`; under a K8s target, the CLI fails immediately at the generation step.

This phase starts only once a customer has bought a K8s cluster. Its precondition is that Phase 4's teardown gate **has stayed green the whole time** — if it was ever allowed to go red along the way, this phase becomes a rewrite.

### 5.3 The three components that will never be developed

`hrm-payroll-core` / `hrm-payroll-cn` / `hrm-payroll-us` are `blueprint`s: the Design Book preserves the concept definition and contract skeleton, **currently not developed, not built, not delivered** (§3.3, Decision 65). Their ports are already reserved in the registry; once market validation activates one as `optional`, it joins the queue.

`frontend-advanced` / `frontend-{industry}` are marked "🔜 future"; `frontend-{customer}` is a **fork on demand** (copy `frontend-standard`'s directory and change the remote — not independently developed).

---

## Part 6 · Disciplines That Run Through the Whole Project (not tied to any one phase)

| # | Discipline | Frequency | Source |
|---|---|---|---|
| 1 | **The teardown gate**: strip every `local: true`, `brickkit up` the fully-torn-apart form once, business closed loop all green | **Weekly**, plus every time a merge-group relationship changes | §13.7, Decision 92 |
| 2 | **The import scan**: no component may import another component's repo | **Every CI run** | §13.3 Iron Rule 6, Decision 91 |
| 3 | **Platform-assumption regression**: rerun the 20 platform acceptance cases | **Every brickKit upgrade** | §9.6.2, Decision 96 |
| 4 | **When a platform problem is found**: log a case in `be-acceptance` first (even if red), then go fix it in the brickKit repo. **Never work around it on the business side** | every time it happens | §9.6.2 |
| 5 | **Restore the arsenal structure before committing**: `make arsenal-restore` | every commit (the pre-commit hook backstops this) | §3.3 |
| 5b | **Keep the four documents in sync**: boundary/contract/event changed → update `docs/design/<repo>.md` first; a feature changed → the README; usage or structure changed → `docs/手册.md`; a prohibition or judgment criterion changed → that repo's `AGENTS.md`. **Documentation comes first, code comes second** | every change | §4 SOP-D |
| 6 | **`commit & push` before `brickkit remove`** | every remove | §9.4.2 |
| 7 | **Contract changes go through `make contract-check`**: `buf breaking` / `oasdiff` catch breaking changes | every change to `contracts/` | §8.5, Decision 33 |
| 8 | **Any AI-generated complex business function over 50 lines** must carry a natural-language decision tree + a Mermaid flowchart comment, or it's bounced at local code review | every AI generation | §8.5, Decision 48 |
| 9 | **Property-based tests for core transactional components** (`erp-inventory` / `erp-finance` / `hrm-payroll-es` / `crm-commission`): a human defines the invariants, the framework generates random boundary inputs to attack them | every change to core logic | §8.0, Decision 49 |
| 10 | **The moment `brickkit restore` ships**: switch to `brickkit init --hooks`, delete our own `arsenal.sh`'s local backstop check, to avoid two sets diverging | one-time | §3.3 |

---

## Part 7 · Corrections and Extensions to the Design Book (four batches, **all already written back into the Design Book**)

**This section is for whoever takes this over six months from now**: the following are inconsistencies found in the Design Book during planning, **every one of which has already been fixed in the Design Book itself** — this section only keeps a changelog. The Design Book and this document are now consistent — **where they conflict, the Design Book wins, then come back and fix this document.**

### Corrections (6, all written back)

| # | What the Design Book originally said | Changed to | Why | Where it was written back |
|---|---|---|---|---|
| 1 | Appendix G / §2.7.1: Traefik Dashboard on 8080 | **28080** | Collides with Shell 1's `mdm-customer` HTTP on 8080, and a shell must publish its ports to the host (§13.1) — a real collision | §2.7.1's table + a new explanatory paragraph beneath it, §2.7.2③, §2.7.5's compose, Appendix G |
| 2 | Appendix G: Keycloak on 8080 / Prometheus on 9090 / Kafka on 9092 | **28081 / 29090 / 29092** | Same as above, colliding respectively with `mdm-customer`'s HTTP, `mdm-customer`'s gRPC, and `mdm-product`'s gRPC | Same as above |
| 3 | §13.2 listed 14 components for Shell 2 | **16** (adding `hrm-recruitment`, `hrm-appraisal`), range 8100–8113 → **8100–8115** | Both are Go, plain CRUD, `reserve` — the original text missed them. They need ports or Phase 4b has nowhere to put them | Shell 2's table in §13.2 + a new explanatory note beneath it |
| 4 | §13.2 listed Shell 3 as "6 infra + 15 integration = 21" | **7 infra** (adding `infra-iam-casdoor`) **+ 14 integration = 21**, port range spelled out as 8200~8220 | `integration-edi` is Python and lives in Shell 5, so integration is only 14; the missing one is `infra-iam-casdoor` (Go, ~500 lines, not captured by any shell list, but counted when §9.6.1 Tier 3 said "the Go shell holds 10 modules"). Adding it back makes 21 add up | Shell 3's table in §13.2 + a new explanatory note beneath it; and in passing, corrected the "holdout" table that had called Traefik/Casdoor "base resources" (they're shape-B out-of-band containers) |
| 5 | `opportunity.won.v1` has only **two** segments, while every other event in the book has three | **`crm.opportunity.won.v1`** | §3.7's naming scheme is `{domain}.{aggregate}.{action}`. The only window to rename it is "before it has a consumer" — once `erp-sales` starts consuming it, renaming means deleting the old subject (Decision 19: additive only, never delete or change) | §3.7 (a full event-name table plus two ⚠️ notes added), §4.3's event diagram, Appendix E's sandbox |
| 6 | Follow-up to Correction 4 (**found 2026-09-08, during the Phase 2 shipping retrospective**): `infra-authz` had been missed the same way — the same class of miss as `infra-iam-casdoor` at the time (Go, not captured by any shell list) — but Design Book §14.3 and Appendix H's "Slice" column had always been right (the latter was already checked); only §9.6.1/§13.2's numbers hadn't caught up | **Tier 2/Tier 3's Go portion is 14/11 (not 13/10); Shell 3's final shape is 8 infra + 14 integration = 22 (not 21)** | `infra-authz` is the actual authorization-checking component (Chapter 14) — if the "business closed loop" tier doesn't carry real authorization checks, what it verifies is really a loop with everything wide open, proving none of Chapter 14's promises — this miss isn't a port-counting issue, it's a **scope** issue | §9.6.1's Tier 2/Tier 3 rows, the note beneath Shell 3's table in §13.2 (the "10 modules"→"11 modules" spot corrected along with it); row 4's old note is kept exactly as written, never rewritten retroactively |

### Extensions (2, both written back)

| # | What the Design Book originally said | Extended to | Why | Where it was written back |
|---|---|---|---|---|
| 1 | §5.10: `be-sdk-events-go` (reserve, a Go event SDK) | **`be-sdk-go` / `be-sdk-python` / `be-sdk-ts`, required, SOP-L's 14 cross-cutting capabilities** | Events are only 3 of the 14. `Endpoint`'s scheme-stripping, `WithTx`'s `SET LOCAL`, and OTel's Blackhole degradation are exactly the kind of thing someone is guaranteed to get wrong if every component writes it separately — **and those two are precisely the "hardest landmines" the Design Book itself calls out**. It is not a "shared model package": zero business logic, zero component models, zero cross-component references, already added to the import-scan allowlist | A new "`be-sdk-*`" subsection under §5.10 (with a capability table), the `be-sdk-*` row in Appendix H, Decision 100 |
| 2 | §5.10 / §2.4: `be-ops`'s port registry (output 6) only covers the 62 components | **The port registry also covers out-of-band container host ports** | Once a shell publishes ports to the host, component ports and out-of-band container ports share the **same host port space**, and they really do collide (Corrections 1 and 2 were found exactly this way). A registry covering only the 62 components would never surface these four | §3.5.1.1 (including the one exception of the `slot:frontend` family sharing 80), §5.10 output 6, Appendix I "global port registry," Decision 99 |

### Second batch: reference-implementation discipline and design-pattern criteria (already written back)

| # | Design Book originally | Filled in as | Why | Written back where |
|---|---|---|---|---|
| 6 | No reference-implementation methodology anywhere in the book | New **§3.2.1, the three-step reference method**: design your own version against the four measuring sticks first → only look at how a real ERP does it for the parts you can't work out → come back and think it through yourself before writing it. Closed-source products are worth consulting too (you can't see the source, but "which features customers use daily and which they never touch" is more valuable than source code for the optional-component test) | Edge cases a domain model designed in a vacuum missed don't surface until three months after a customer goes live; but doing the steps in the wrong order doesn't work either — reading with an empty head just produces a copy, and our tech stack (Go) and our component boundaries (independent processes, independent schemas) are completely different from theirs anyway. Licensing gets only a short note: borrowing logic isn't a derivative work; the only thing to avoid is opening a source file and copying it line by line | §3.2.1, Decision 102 |
| 7 | No stance anywhere in the book on design patterns | "Not mandatory, but must be used where it fits" — judged by "does this make it easier or harder to read and extend," and explicitly **judged by whether an AI can quickly understand it** (a human is assumed to already have pattern literacy, so this isn't a constraint for them). The nine places already decided are listed in this document's §4, SOP-P | An AI starts every session fresh, with limited context, and can't see runtime state. So what helps it is small files + a centralized registry + explicit over implicit; what hurts it is deep inheritance + metaprogramming + empty abstraction. Conversely, forcing a pattern onto plain CRUD is a worse outcome | Decision 103 (the detail lives in this document's §4 SOP-P, since it gets filled in as work proceeds) |
| 8 | §5.11 only covered "what shape it should take once there are already multiple implementations," **not when to add a new one** | New **§5.11.1, when a new slot family is warranted**: the criterion isn't "we want to support several," it's "consulting multiple mature ERPs turns up several implementations of the same feature, **each one reasonable**, just fitting a different customer." Includes a four-step write-back process and five positive/negative examples | **This is how the shelf actually grows.** The end goal is "we have our own default ERP, but every functional component can have multiple implementations, and a customer picks what they need, even doing closed-source customization on the closest one" — the more a family matches a genuine real-world divergence, the closer a customer's fork starts to what they want, and the less customization time we spend later | §5.11.1, Decision 104; the detail lives in this document's §4 SOP-R, R-4 |

### Third batch: cross-checked line-by-line against brickKit's **code** (the last review before starting work)

The first two batches came from reading the Design Book and finding inconsistencies. This batch came from **reading brickKit's actual Go code** — wherever the documentation and the implementation diverge, the implementation wins.

| # | What we assumed | What the platform actually does | Evidence | What was changed |
|---|---|---|---|---|
| 9 | "Swapping a base-resource implementation only means changing `brickkit.yaml`'s `engine` field, zero changes to component code or manifests" | **`engine` matches literally, character for character.** A component writing `nats` against a project writing `kafka` → `up` blocks. Swapping the event bus means changing ~50 `component.yaml` files **plus** swapping the SDK driver (different client libraries); object storage really is a zero-change case. **This also settles what `engine` should say: name the capability where the protocol is compatible (storage → `s3`, default implementation RustFS), name the product where it isn't** (mq → `nats`, so the platform actively blocks a Kafka swap); the database says `postgresql`, and isn't in scope for swapping at all | `internal/config/validate.go`, `006` §2.2/§4.4 | New Design Book **§2.7.3.1** + **Decision 105**; 9 other reference points across §2.7.0/§2.7.1/§2.7.2/§3.4/§5.11/§6.2/Appendix I updated to match; Decision 86's reasoning rewritten |
| 10 | Moving out-of-band container ports to `18080` / `18081` / `19090` / `19092` would be safe | **The entire `1xxxx` range belongs to the platform**: when mapping `local: true` components and their dependencies to the host, it prefers `10000 + container port`, falling back to an incrementing scan from `18080`. Our four numbers **all collide exactly** | `internal/compose/local.go` (`hostPortOffset = 10000`, `hostPortBase = 18080`) | All four moved to `2xxxx`: **28080 / 28081 / 29090 / 29092**. Design Book §2.7.1's note rewritten + **Decision 106**; the port registry gained a "the `1xxxx` range may not be allocated" rule |
| 11 | "Platform-injected `*_ENDPOINT`s always start with `http://`" | **Only true for component addresses.** `STORAGE_ENDPOINT` is bare `host:port` — the one variable whose name contains `ENDPOINT` but whose value carries no scheme | `internal/inject/inject.go` (component addresses via `fmt.Sprintf("http://%s:%d")`, storage via `hostPort(r)`) | Design Book §2.1 gained a three-row comparison table; the master guide's §D updated to match; `be-sdk-*` gained `storageEndpoint()` (**adds** the scheme, opposite direction from `endpoint()`) |
| 12 | `bindings` are optional | **Declaring a resource dependency without a binding makes `up` block.** Every component needs a `componentId` entry; in a merged deployment this is **5 PostgreSQL resource entries** (same host, 5 shell login roles), each with its own set of bindings. `DATABASE_NAME` comes from the binding's `database` field, **the schema does not come from a binding** (it comes from `configSchema.pgSchema`) | `006` §3.1/§4.4, `internal/inject/inject.go` | Design Book §2.7.2① gained a paragraph; this document's §2.4 gained a new **output 2b** |
| 13 | `labels` values just need to be strings | **Three more key groups belong to the platform, and writing them fails immediately**: `brickkit.io/*`, `com.docker.compose.*`, `app` | `internal/manifest/labels.go` | Design Book §5.10's Generator Iron Rule 1 gained a table; this document updated to match. Our own `prometheus.io/*` and `traefik.http.*` are safe |
| **14** | The routing table has "two exits" — a standalone container goes through `brickkit.yaml`'s `components[].labels`, forwarded by the platform into the compose service | **⚠️ This doesn't work, and is the most serious finding of this whole review.** The platform-generated compose **builds its own non-external bridge network**, and there is no field in `brickkit.yaml` that can change that. Traefik's Docker Provider can only see containers on the same network → those routing labels **are never read at all**. Symptom: **the labels are written correctly, `docker inspect` shows them, and yet the gateway 404s while every container is healthy** | `internal/compose/compose.go` (`networks` hard-coded to a bridge network derived from the project name); `internal/config/config.go` has no networks field | Design Book §6.3.1 changed to **three exits** + §13.8.3's networking section rewritten + **Decision 107**. The two platform-generated containers switch to **`expose: true` + `exposePort` + Traefik's file provider**; `exposePort` added to the port registry (`frontend-standard` 28090, `infra-bff-mobile` 28500); `traefik.yml` gained a file provider. **Also logged as a platform improvement request** (`deploy.docker.externalNetworks`) |
| **15** | Connected to the above: `resources[].host` can be a container name (like `be-postgres`) | The platform-generated containers aren't on `be-net`, **and can't resolve our containers' names at all**. The only option is `host.docker.internal` — which is also exactly what brickKit `006` §10.4 recommends | Same as above | Design Book §13.8.3 gained a sentence |
| **16** | Storage's `engine` should say `minio` (S3-compatible) | Since `engine` is a free-form string compared only literally, **what this word says is purely a design decision.** Writing the product name means "swap the implementation" needlessly touches dozens of manifests; and we default to running RustFS, so declaring `minio` would be misleading anyway | `engine` is only checked for non-empty; `006` §2.1's example engines for storage are "minio, s3" | **Standardized on `engine: s3`** (the capability name). This also settles the criterion: **name the capability where the protocol is compatible** (storage → `s3`, swapping RustFS↔MinIO↔S3 is zero-change), **name the product where it isn't** (mq → `nats`, so a Kafka swap actively blocks, because that really is a migration). Design Book §2.7.3.1 gained a subsection + Decision 73/105 updated to match |

**Three more minor corrections:**

| Item | Content |
|---|---|
| `metadata` supports `license` / `vendor` / `apiDocs` | The platform's `manifest.Metadata` has these three fields. The `component.yaml` template gained `license: Apache-2.0` and `vendor` |
| The component-ID regex | `^[a-z0-9]([a-z0-9-]*[a-z0-9])?/[a-z0-9]([a-z0-9-]*[a-z0-9])?$` — **exactly one slash, lowercase letters/digits/hyphens only, no dots.** So the §2.3 table's `frontend/{industry}` / `frontend/{customer}` are only placeholders — the real thing has to be spelled like `frontend/retail` |
| `be-sdk-go`'s `envName` | The platform's `manifest.EnvPrefix` **only replaces `/` and `-`**. We had originally written an extra rule to also replace `.` — not wrong, exactly, but it would mislead a reader into thinking a component ID could contain a dot |

**Verified with no changes needed (recorded here to avoid re-checking next time):**

| Assumption | Verification result |
|---|---|
| `apiVersion: brickkit/v1` + `kind: Component` | ✓ hard-coded constants |
| `deployment.type` only accepts `container` | ✓ `DeploymentTypeContainer` is the only legal value |
| `artifacts[].type` can be a custom value (we use `metadata` to ship `assembly.yaml`) | ✓ both `type` and `format` are free-form strings; the platform enforces no enum, parses no content |
| The resource `kind` is the closed enum `database/cache/mq/storage/search/smtp` | ✓ and `cache`'s variable prefix is `REDIS_`, not `CACHE_` |
| Reserved variables: `COMPONENT_ID` / `COMPONENT_VERSION` / `*_ENDPOINT` / the `DATABASE_`·`REDIS_`·`MQ_`·`STORAGE_`·`SEARCH_`·`SMTP_` prefixes | ✓ letter-for-letter (a binding's `envPrefix` also becomes a reserved prefix) |
| `startPeriodSeconds` defaults to **60** (not 30) | ✓ `DefaultStartPeriodSeconds = 60`, and it's the only overridable timing parameter under `healthCheck` |
| The extra-port variable name `{prefix}_{PORT_NAME_UPPERCASE}_ENDPOINT` | ✓ |
| Versioned service name `mdm/customer` + `1.0.0` → `mdm-customer-1-0-0` | ✓ `/` and `.` become `-`, all lowercase |
| `local: true` generates no container, and skips the migration container too (warning only) | ✓ `localMigrationWarnings` |
| `localPort` only takes effect with `local: true`, and errors on collision | ✓ and setting it without `local: true` errors immediately |
| `brickkit up --config <file>` works | ✓ `--config` is a root persistent flag, inherited by subcommands |
| The local-source install layout `<path>/<scope>/<name>/component.yaml`, used in place, one directory per version | ✓ matches our submodule structure |
| The exact-version regex `^\d+\.\d+\.\d+$` | ✓ |
| The extra-port-name regex `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$` (we use `grpc`) | ✓ |
| `deploy` supports `target: docker\|k8s` plus a set of K8s options | ✓ also `networkPolicy` / `serviceAccount` / `podSecurity` / `ingressClass`, etc., used starting Phase 7 |
| `installer.requireSignature` exists, but local sources aren't bound by it | ✓ matches §9.4.1 |

### One more thing added to the Design Book (not a correction — an originally missing tier)

**§9.6.1's "Tier 4" split into "Tier 4a, fill out `default`" and "Tier 4b, stock the shelves,"** with a new table explaining why the 5 `default` components (`infra-storage` / `infra-attachment` / `infra-dlq-monitor` / `mdm-supplier` / `mdm-org`) can't wait for a customer to ask. Also clarified Tier 2's shipping condition of "the DLQ works both ways" — `infra-dlq-monitor` belongs to Tier 4a, while Tier 2 verifies **the platform SDK layer's dead-letter channel itself**, leaving the management UI to Tier 4a. Logged as new **Decision 101**.

### Fourth batch: unified tech stack and module entry point (already written back)

The starting question: **to merge N components into one shell, must same-language components use the same framework?** Yes — but unpacking that turned up "framework" as only the most superficial cell.

| # | Design Book originally | Filled in as | Why | Written back where |
|---|---|---|---|---|
| 17 | §13.5 had only one line, "only components of the same language **and same framework** can be merged," with nowhere in the book expanding on what "same framework" means; §12.1 still said "`sqlc` or `GORM`," leaving it open | New **§12.4, a unified tech stack per language**: a cell-by-cell lock-in table (HTTP framework / server / gRPC / DB driver / SQL layer / migrations / validation / metrics / logging / OTel / testing / image base), splitting divergence into three tiers — **physically impossible to combine / comes up but breaks silently / discipline**; of these, **the migration cell is "unified within a language," every other cell is "unified across the whole project"** (a shell never spans languages, so each shell's launcher only ever needs to know its own language's migration tool; Python uses `yoyo-migrations`, not alembic — with zero ORM, alembic's autogenerate is entirely useless) | Five cells are physical: ASGI and WSGI can't share an event loop, synchronous `grpc` can't reach a shared async pool, `*sql.DB` and `*pgxpool.Pool` can't be handed to each other, two migration tools mean two `schema_migrations`, and the default Prometheus registry **crashes outright** on a duplicate metric name. **The Gin cell, in contrast, is a discipline lock** (`gin.Engine` is just an `http.Handler`, so mixing would still compile) — **this distinction must be spelled out**, or someone will eventually assume FastAPI is also just a preference | New Design Book §12.4; §12.1's "or GORM" removed; §13.5's cost table rewritten and pointed at §12.4; **Decision 108** |
| 18 | **Nowhere in the book said what a shell should call to plug in a component** | New **§12.5, the module entry contract**: every backend component exports a single entry point, `module.New(ctx, rt) (*besdk.Module, error)` (Python: `create_module`), with `main` collapsed to one line, `besdk.RunStandalone(module.New)`, and **standalone and merged calling the exact same function**; the fields of the two types `Runtime`/`Module` locked down one by one | This was a genuine gap, not an inconsistency: without it, `be-ops`'s output 4 (shell-merge configuration) **has nothing to generate against**, and 62 components would each invent their own `main`, all of which would need rewriting the day of merging. More importantly — **the same entry point is the only shape in which §1.5's second principle can be enforced by a machine**, or §13.7's teardown gate would go red across the board the first time it actually ran, six months from now | New Design Book §12.5; §13.3 gained **Iron Rule 7**; §3.11 gained gate **9, `make module-check`**; this document gained Global Constraint **§K** + SOP-L's **L-1/L-2** + SOP-B's new **B-0**; **Decision 109** |
| 19 | §13.3 Iron Rule 1 and SOP-B's B-8: "config only comes from environment variables, read `*_ENDPOINT` with `os.Getenv()`" | **Zero `os.Getenv` in module code**: dependency addresses go through `besdk.Endpoint()`, everything else goes through `rt.Config`. The intent — never hard-code an address — hasn't changed; **what changed is who does the reading** | §13.8.2 already required "the shell holds a separate env map per module," but **one process has exactly one `environ`** — that requirement only holds if modules never touch `os.Getenv` themselves. What collides are exactly the ones without `_ENDPOINT`: `COMPONENT_ID`, `PG_SCHEMA`, and every entry in every `configSchema` (`pgSchema`/`batchSize`/`otelBaseUrl` are common names to collide on). **The symptom is a module reading and writing data against someone else's schema, with no error** — the second path into the pitfall behind Decision 3 | Design Book §12.5.3 (with a table of what collides and what doesn't) + §13.3 Iron Rule 7's first item; this document's §K + SOP-B's B-8 rewritten; **Decision 110** |
| 20 | §3.9: contract generation produces "TypeScript interfaces, **React Query hooks**" | `@tanstack/vue-query` | Directly conflicts with Decision 79, "React firmly excluded" — a leftover from an older wording | Design Book §3.9; this document's SOP-F Iron Rule 6 |

**How this batch differs from the first three**: the first three fixed "the Design Book contradicting itself" and "the documentation diverging from brickKit's implementation"; this batch fixed **an entire area that had never been written at all.** It had to be written now because it constrains **the skeleton of every single component's code** — and Phase 1's first brick (`mdm-customer`) had to be written against it. Phase 1 Tasks 6/7/11/16 were updated to match.

### Fifth batch: frontend UI-layer lock-in (already written back)

Same nature as the fourth batch: **another area that had never been written.** §12.2 only ever settled on "Vue3 + Uni-app" — the layer above it (component library / charts / app skeleton / visuals) had no position anywhere in the book, and §12.2's passing mention of `Element Plus` / `vxe-table` / `Ant Design Vue` was easy to mistake for an already-made choice.

| # | Design Book originally | Filled in as | Why | Written back where |
|---|---|---|---|---|
| 21 | Only settled on Vue3 + Uni-app; no position on a component library | New **§12.6, frontend UI-layer lock-in**: PC = **Ant Design Vue v4 + vxe-table**, mobile = **wot-design-uni**, charts = **ECharts + `vue-echarts`** | Using a different set on mobile is **by design** (mobile's shape is entirely different to begin with, so sharing components buys almost nothing); AntDV's DOM dependency just happens to also rule out "lazy reuse." **There's a structural consequence too: `packages/ui-kit` can't be a single package** — a shared ui-kit that imports AntDV drags it into the Uni-app side too (a mini-program target may well fail to compile at all). Split into `design-tokens` (the only thing shared by both ends, pure data) + `ui-kit-pc` + `ui-kit-mobile`: **share the tokens, not the components**. The key reason charts are locked to ECharts is **offline availability** (a private on-prem deployment has no external CDN) | New Design Book §12.6.1; §12.2 gained a closing line, "this section only fixes the language and framework, not the component library"; §5.9's iron rules gained a fifth item; **Decision 111** |
| 22 | —— | **§12.6.2**: AntDV and vxe-table are **two separate theme systems** (one a design token + `theme.algorithm`, the other CSS variables + `VxeUI.setTheme`), and must be wired together inside `packages/ui-kit`: ① derive the seed token into `--vxe-ui-*`, ② register AntDV controls as vxe cell renderers | **The symptom of not wiring them together is no error, it runs fine, every ERP table just looks pasted into the page** — the primary color, borders, and row height all mismatch, and the input inside an editable cell is vxe's own. This is the one item in this batch that directly ruins the visual result, and it belongs to the "the code looks completely correct" category | Design Book §12.6.2, §6.4 (`ui-kit`'s three responsibilities); this document's SOP-F Iron Rule 10 |
| 23 | —— | **§12.6.3, four criteria for mixing libraries**: only mix when AntDV genuinely **lacks the capability**; whatever gets mixed in must first go through `packages/ui-kit` as a wrapper, business pages must never `import` it directly; every mix gets one line logged in the design plan's section 8; **never mix "to look nicer"** | Without a criterion, "mix in when needed" turns into five libraries in one page a year later, with token systems that don't line up two by two — **the more you mix, the worse it looks.** `ui-kit`'s single-exit-point rule follows the same logic as `be-sdk-*`: swapping an implementation means changing one file, not 40 pages | Design Book §12.6.3; this document's SOP-F Iron Rule 9; AGENTS.md's "things not to propose" |
| 24 | —— | **§12.6.4, the app skeleton is built in-house** (never taken as a dependency on an admin template), **but read `vue-vben-admin`'s layout / router+access / request pieces per the three-step method**; **the R-2 table gained three frontend rows** (vben / Ant Design Pro's page patterns / vxe's official examples) | We have two constraints that land exactly on the layer a template is hardest to change: dynamic feature-flag routing (a template's routing+permission is driven by a backend menu table or static routes, and stripping that out leaves only a layout with the whole dependency tree still attached) and the Uni-app shared layer (no template covers this). And **the R-2 table originally had zero frontend rows**, meaning frontend had no reference-implementation discipline at all | Design Book §12.6.4; this document's SOP-R R-2 table gained 3 rows, SOP-F Iron Rule 12; **Decision 112** |
| 25 | —— | **§12.6.5, the "restrained professional" visual direction** + **§12.6.6, the vxe commercial-tier boundary must be checked item-by-item before work starts** | "As good-looking as possible," given 62 components generated by an AI in batches, **concretely means "consistent"** — what ruins the look isn't an unadventurous palette, it's "this page uses 16px spacing, the next page uses 20px." So `ui-kit` exports constants and pages are forbidden from hard-coding. And vxe's documentation marks some features `enterprise-version`, so **some capabilities are commercial-tier** — its status is "default choice, pending confirmation," and §12.6.6 was written as a **four-step closed loop** (check → decide → candidates if swapping → use `<BeTable>` from day one to pre-emptively lower the cost of swapping), not a one-line reminder; the later this is discovered, the harder it is to fix (once 40 pages are designed around a capability, swapping it means redrawing them) | Design Book §12.6.5 / §12.6.6; this document's SOP-F Iron Rule 11, SOP-R's R-2 vxe row; `docs/design/_模板.md`'s header |

---

---

---

## Part 8 · Known Risks and Open Questions

| # | Risk / open question | Impact | When to address it |
|---|---|---|---|
| 1 | **`brickkit restore` / `init --hooks` are not yet implemented** (verified: the current CLI reports "unknown command"; the design is confirmed and an implementation plan submitted in the brickKit repo) | Under a submodule structure, a `sync` mistake can only be backstopped by our own `arsenal.sh` | Already backstopped in Phase 1; swap it out per the discipline once the official version ships |
| 2 | **The environment-variable names for the RustFS / Kafka / Casdoor images were written from convention**, not yet verified against real hardware | `make up` might fail to come up because a variable name is wrong | Slotted into Phase 1 Task 1 step 8's calibration action |
| 3 | **This machine's `my-postgres` runs postgres:15, and port 5432 conflicts with this project**; `my-rustfs` holds 9000 | `make up` will error out at the preflight stage | Handled manually by you (an already-confirmed division of labor). `make check` names the offender |
| 4 | **`sales.*` / `finance.*` event names use the component's short name in their first segment rather than the domain name**, inconsistent with `erp.inventory.*` (the `opportunity.won.v1` case has already been corrected to `crm.opportunity.won.v1`) | Event schemas are additive-only, never delete or change (Decision 19) — once there's a consumer, this becomes unfixable | **There is currently no consumer at all — this is the only window where it can still be changed.** Already logged in Design Book §3.7 to stop anyone casually "unifying" it later; whether to unify is still open |
| 5 | **The shared connection pool has no bulkhead** (a known cost of Decision 3 / §13.3 Iron Rule 2): one module leaking a connection or running a long transaction makes the whole group wait | Fault isolation is weaker merged than fully torn apart | This cost was already paid the moment things merged, it isn't a bug. Moving to K8s (fully torn apart, Phase 3 in that sense) recovers automatically |
| 6 | **Signing is not universally enforced** (§9.4.1): fully local-source sources aren't required to be signed, and shell images fall outside its coverage | Supply-chain assurance has to come from elsewhere | Three alternative measures are already written into Global Constraint §J; the delivery documentation must be explicit about who builds the shell image, whose key signs it, and how a customer verifies it |
| 7 | **Phase 4's Go shell is a temporary shape** (1 process, 11 modules, including `infra-authz`); it isn't split into §13.2's three Go shells until Phase 5 | The split will be the first time cross-shell environment variables are genuinely exercised | Scheduled in Phase 5's plan; `be-ops` output 7's tests will hold the line |
| 8 | **`be-assembly-{customer}` and the "customer → component repo" map** haven't started yet | Must exist before the first real customer delivery | Kicked off when the first customer signs, following Phase 6's eight-step process |
| 11 | **brickKit's design documentation and its implementation diverge, in more than one place** | All 5 findings in the third-review batch came from "the documentation says one thing, the code does another." Going forward, whenever "does the platform do X" is a key assumption, **the code wins, and it gets logged as an assertion in `be-acceptance`** | Already in place: Design Book §9.6.2's 20 platform acceptance cases are exactly this mechanism. **New assumptions get a new case at the same time** — never just written into documentation alone |
| 10 | **Our own component license: proceeding with Apache-2.0** (not yet formally confirmed in writing, subject to change) | Every repo needs a `LICENSE`; changing licenses later needs every contributor's consent, so deciding early saves trouble | Three reasons for Apache-2.0: ① it lets a customer fork and close-source it, exactly the shape Design Book §3.2 calls for (GPL/AGPL would rule this out outright); ② it carries a patent grant, easing legal review on private deployments; ③ same license as Apache OFBiz, one less judgment call if we ever borrow its code directly. **Written into `LICENSE` as part of Phase 1's CP-1 repo creation**; switching to something else just needs a heads-up before then |
| 9 | **`docs/design/` currently only has one entry, `mdm-customer`** | Every subsequent component needs one before it starts | The first thing in every phase's plan is writing the design plan for the components that phase touches (§4 SOP-D) |
| 12 | **`vxe-table` is "the default choice, pending confirmation," not locked in.** Its official documentation marks some features `enterprise-version` / `enterprise-link`, and exactly which capabilities are free-tier **hasn't been checked** | We deliver on-prem. **Editable cells / virtual scroll / frozen columns** are the floor for an ERP table, and if any one of them turns out to be paid, it must be swapped | **Before `frontend-standard` starts in Phase 3**, work through Design Book §12.6.6's four-step closed loop: ① check every capability against that list → ② decide (all free → lock it in / a few paid ones → work around them / any floor-level capability paid → swap / or buy — buying requires first checking whether every customer needs their own license for a private deployment) → ③ swap candidates are AG Grid Community, RevoGrid, TanStack Table, **all needing the same checklist** (every serious table library puts its enterprise capabilities behind a paywall) → ④ use `ui-kit-pc`'s `<BeTable>` from day one, so swapping the engine means changing one package, not 40 pages. The conclusion goes in `docs/design/frontend-standard.md` section 8. ⚠️ The same class of timing risk as the port registry: **the later this is found, the harder it is to fix** |
| 13 | **The mobile component library `wot-design-uni` is not an official DCloud package**, and its compatibility with each platform's mini-program targets hasn't been tested | `apps/mobile` may hit component-compatibility issues compiling to WeChat / DingTalk mini-programs | When `apps/mobile` starts in Phase 3, first compile three to five key components (a form, upload, a QR-scan entry point, pull-to-refresh) against every target platform before building out pages. **The fallback is DCloud's official `uni-ui`** (one tier worse-looking, the most stable compatibility) — keep the fallback in the design plan, don't only write down the one that was picked |

