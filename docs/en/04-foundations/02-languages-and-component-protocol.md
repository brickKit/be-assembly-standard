[English](02-languages-and-component-protocol.md) · [中文](../../zh/04-foundations/02-languages-and-component-protocol.md)

# Languages and the component protocol

Each component may be written in any programming language. This document says what makes a component, in any language, a correct member of the project: the language-neutral component protocol, the black-box conformance suite that judges it, the official SDKs that implement it, and the two separate gates, "runs standalone" and "joins a shell". Read it before changing an official SDK or the suite, before writing a component in a language other than Go, Python or TypeScript, or before proposing a new language.

## Scope

- **In:** free language choice per component; the component protocol: what it covers, how it is versioned, where it lives; the black-box suite: what it runs against, how a component joins it, its report and gate; the two gates; the official SDKs and the stack each one locks; the shell launchers, summarised here for all languages; the path for a fourth language.
- **Out:** the detail of each area the protocol covers. That stays in the foundations document for the area (the table under [Port contract](#port-contract) points to each one). The shell invariants and the merge-safety checklist: [27-shells.md](27-shells.md). Rules shared by every port, and how SDK versions move: [01-ports-and-adapters.md](01-ports-and-adapters.md). How to write a component with an official SDK: [02-backend.md](../01-conventions/02-backend.md).

## Choice

- **Every component chooses its own language.** The rules a component must follow no longer live inside one language's SDK. They are the **component protocol**, defined at the level of wire formats, table shapes and configuration keys.
- **The protocol has its own repository**, `brickKit/be-protocol` (https://github.com/brickKit/be-protocol). It holds the specification text (English canonical, Chinese mirror), JSON schemas, the reference DDL of the platform tables, the semantic vectors and the contract of the fixture component. Its only code is a small Go module that embeds those files for the tests. It is versioned on its own, `MAJOR.MINOR`, starting at `v1.0.0` after release candidates. A minor version only adds optional surface.
- **Conformance is judged from outside.** The suite `tools/be-acceptance/conformance/component/` (informally "compconf") tests a **running container**: its ports, the tables it writes, the messages it publishes, its logs and its metrics. It never reads source code, so a Go, Python, TypeScript or fourth-language component is judged by the same cases.
- **The official SDKs are reference implementations.** `be-sdk-go`, `be-sdk-python` and `be-sdk-ts` implement the protocol with the same nouns in each language. No SDK may show behaviour that the specification does not state: the specification changes first.
- **Two gates, kept separate.** *Runs standalone*: a component in any language that passes its applicable suite profiles may enter `brickkit.yaml`. *Joins a shell*: only when its language has an official SDK **and** that SDK's shell launcher, because a shell is one process with one runtime and one SDK version ([27-shells.md](27-shells.md)).
- **One locked stack per language.** Before a language gets its second component, it gets a stack row in [0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md), and someone decides whether it gets an official SDK.
- **A JVM or CLR language is allowed.** Its memory and start-up cost is a caveat written in the component's `BRICKKIT.md`, section "Before you deploy". It is no longer a ban.

**Status**: decided. The `be-protocol` repository exists and its 1.0 text is being written (release candidates first). The SDKs move to v0.6.0 through release candidates: v0.6.0 freezes the API after the pilot components, and the same code is tagged v1.0.0 once the shells are verified on a real machine. Today the SDKs (v0.5.0) carry the rules as code and differ from each other: TypeScript has no database, events or idempotency. The suite does not exist yet, so no component has a conformance report.

## Port contract

### What the protocol covers

Twenty chapters, `P1`–`P20`. Each rule has a level. **MUST** rules are tested by the suite. **SHOULD** rules only give a warning. **INTERNAL** rules cannot be seen from outside (for example "no network call inside a transaction"): the official SDKs guard them with their own tests, and a fourth-language component is checked in review. A rule names its suite case `CP-<group>-<nn>`. Case IDs are stable and only ever added.

| Chapter | Covers | Detail in |
|---|---|---|
| P1 Process and lifecycle | two entries: the default command serves, `migration.command` migrates; start order (validate configuration, open ports, then connect in the background); exit code 78 on invalid configuration; `/healthz` answers only for the process; `/readyz` (SHOULD); SIGTERM drains within `SHUTDOWN_GRACE` (default 20 s); a fatal error exits non-zero; the image has `/bin/sh` and `wget` | [27](27-shells.md), [02-backend.md](../01-conventions/02-backend.md#health-check-and-image) |
| P2 Configuration | environment variables only; only keys the component declares in `configSchema`; strict types; the protocol keys listed in `schemas/config-keys.yaml` | [24](24-config-and-secrets.md) |
| P3 HTTP surface | three path classes (user API, operations endpoints, resource-contract endpoints); `X-Request-Id`; `traceparent`; per-route deadlines; server timeouts; 1 MiB body limit; `Idempotency-Key`; cursor paging | [15](15-user-api-and-errors.md) |
| P4 Errors | RFC 9457 problem details carrying AIP-193 `reason`, `domain`, `metadata`; the reason registry | [15](15-user-api-and-errors.md) |
| P5 Identity | JWT verification, `iss`, `aud`, `typ` | [21](21-identity-provider.md) |
| P6 Authorization | the bundle, data scopes, resource contract, projections | [20](20-authorization-provider.md) |
| P7–P9 Calls | the gRPC system plane, outbound HTTP, deadlines and retry budgets | [14](14-system-rpc.md), [16](16-deadlines-and-retries.md) |
| P10 Database | identity from `PG_OWNER_USER` (owner, migrations only), `PG_USER` (runtime, DML only) and `PG_SCHEMA`; `SET LOCAL` per transaction, timeouts, pools | [03](03-database.md), [10](10-local-transactions.md) |
| P11 Migrations and data shapes | migration guards, expand/contract, UUIDv7 keys, money precision, business dates, `legal_entity_id`, numbering | [08](08-schema-evolution.md), [04](04-identifiers-and-numbering.md), [05](05-time-and-calendars.md), [06](06-money-quantity-units.md), [07](07-tenancy.md) |
| P12–P15 Events, idempotency, background work, snapshots | outbox, envelope, cursors, replay, command idempotency, Jobs, local copies of others' data | [11](11-consistency-across-components.md), [12](12-event-bus.md), [13](13-event-contracts.md), [19](19-background-jobs.md) |
| P16 Data lifecycle | `lifecycle.yaml`, `RANGE_COLD`, `/_lifecycle/*` | [09](09-data-lifecycle.md) |
| P17 Object storage | one bucket and credential per component, presigned URLs | [22](22-object-storage.md) |
| P18 Observability | log fields, metric names with the `be_` prefix, propagation | [23](23-observability.md) |
| P19 Shell obligations | one language and one SDK version per shell; the four process-wide things; member checks | [27](27-shells.md) |
| P20 Self-description | `/_be/info`, the protocol version | below |

### Self-description

`GET /_be/info` on the main port. It is not routed through the edge, needs no authentication and contains no secret:

```json
{
  "component_id": "erp/sales", "component_version": "3.0.0",
  "protocol": "1.0",
  "sdk": { "name": "be-sdk-go", "version": "0.6.0" },
  "language": { "name": "go", "version": "1.25.11" },
  "profiles": ["core", "auth", "scope", "grpc", "outbound", "events-pub", "events-sub", "idempotency", "db", "jobs", "lifecycle"],
  "ports": { "http": 8085, "grpc": 9095 },
  "migrations": { "component": "0001", "platform": 3 },
  "members": null
}
```

On a shell, `members` is an array of the same objects, each without `members`. A component declares the protocol version it is tested against in `assembly.yaml`; the suite keeps one case set per protocol minor, so an older component is always tested against the version it declares:

```yaml
protocol: "1.0"
language: rust                 # only for a language without an official SDK
conformance:
  fixtures: conformance/fixtures.yaml
  skip:                        # only optional cases, each with a reason
    - { case: CP-OUT-04, reason: "no idempotent outbound method" }
```

### Repository layout of `be-protocol`

| Path | Holds |
|---|---|
| `spec/NN-<area>.md` (`00-reading-the-spec.md`, `01-process-and-lifecycle.md` … `20-self-description-and-versioning.md`), Chinese `spec/NN-<area>.zh.md` beside each | the specification, one file per chapter P1–P20 plus a reading guide, English canonical |
| `schemas/` | `config-keys.yaml`, `errors-be.yaml`, `conformance-cases.yaml`, and the JSON schemas of the problem body, the event envelope, event contracts, access-token claims, `lifecycle.yaml`, `DATA_LIFECYCLE`, `JOBS_OVERRIDES`, `errors.yaml`, the protocol keys of `assembly.yaml`, `/_be/info`, `fixtures.yaml` and the suite report |
| `ddl/` | the reference DDL of every `besdk_*` table and the platform functions (`01-platform-version.sql` … `10-lifecycle-functions.sql`); an SDK's platform migration must produce exactly these shapes. `be_bus.sql` is the PostgreSQL bus adapter's schema, created by the database initialisation, not by a component |
| `proto/`, `openapi/` | `be/v1/limits.proto` (`max_items`), `be/lifecycle/v1/lifecycle.proto`; the resource-contract fragments (`resource-authz.yaml`, `resource-lifecycle.yaml`) and the operations endpoints (`ops.yaml`) |
| `vectors/` | protocol-wide semantics as JSON input/output pairs: money, calendar, numbering, idempotency, envelope, errors, config, redaction; with `SHA256SUMS`. A `search` set is a proposal ([25](25-search.md)). Slot-family decision vectors are not here: they are canonical in the family contract repository (`contracts/infra/authz/vectors/decision/`), and the protocol cites the family's `EVALUATION.md` by tag (`v2.0.0`) |
| `fixtures/widget/`, `fixtures/peer/` | the contract and behaviour of the fixture component and of the fake peer it calls |
| `fs.go`, `go.mod` | the only code: embeds the files above for Go consumers |

`be-acceptance` pins one exact `be-protocol` version. `be-sdk-go` imports it in its tests. `be-sdk-python` and `be-sdk-ts` copy `vectors/` and `schemas/` from a tag and check `SHA256SUMS` (family decision vectors the same way, from the family contract's tag): this copies test data, not code ([0101](../02-decisions/01-architecture/0101-no-imports-between-components.md) is not affected). A change always goes in this order: specification and schema, then vectors, then a suite case seen red against a broken fixture, then all three SDKs, then the tag.

### The black-box suite

- **Real infrastructure:** the PostgreSQL started by `make up`, database `brickkit_test_db`, with a fresh random schema, a random owner role (`PG_OWNER_USER`, owns the tables), a random runtime role (`PG_USER`, DML only, not a member of the owner) and a shell login role granted the runtime role `WITH INHERIT FALSE, SET TRUE` for each run, all dropped afterwards; a throwaway `nats-server -js` per run.
- **Fakes inside the suite:** an identity provider (JWKS plus a token signer that also signs wrong-`iss`, wrong-`aud`, refresh and `HS256` tokens), an authorization provider speaking `contract-infra-authz` v2, a fake peer for every dependency (answering from the dependency's proto descriptors, recording metadata, deadlines and connection counts, able to hang or fail), and an OTLP receiver.
- **Configuration:** the `configSchema` defaults, overlaid with the suite's values (random database identity, fake addresses), overlaid with tuning keys any operator may set (`EVENTS_BACKOFF`, `EVENTS_MAX_DELIVER`, `GRPC_MAX_CONNECTION_AGE`, `JOBS_OVERRIDES`). The protocol keys are the testability interface: there is no test-mode switch.
- **Run:** migrate twice, then serve one or two replicas; for a shell, start it from `BRICKKIT_SERVED_MEMBERS_CONFIG`.

Profiles are selected from the manifests; a component does not declare them:

| Profile | Enabled when | Profile | Enabled when |
|---|---|---|---|
| `core`, `obs`, `err` | always | `events-pub` | its event contracts list a subject it publishes |
| `auth` | any non-public route | `events-sub` | it subscribes to any subject |
| `scope` | `data_scopes` is not `none`, or it declares resources | `idempotency` | any write takes an idempotency key |
| `grpc` | an `extraPorts` entry named `grpc` | `db`, `jobs`, `lifecycle` | `configSchema` has `PG_SCHEMA` |
| `outbound` | it has component dependencies | `blob` | `configSchema` has `S3_BUCKET` |
| `shell` | `component.yaml` has `shell.members`; each member's profiles are re-run in shell form | | |

`conformance/fixtures.yaml` tells the suite how to make the component act and how to observe the result: test users and their grants, how to create, read, list and command each resource, what each dependency answers, which events it produces and consumes, and an `observe.sql` that reads the component's own tables for effects with no public read API. It is data, not code, so a fourth-language component writes the same file.

**Report and gate.** The suite writes `compconf-report.json` (schema in `be-protocol`): suite version, protocol, component and version, image reference and digest, SDK, infrastructure versions, per-profile and per-case results, skipped cases with reasons. A failed MUST makes the run fail. `make conformance ID=<component> [SHELL=<shell>]` runs it locally. The planned gate `compconf-record-scan`, part of `make gates`, is offline: every component and shell in `brickkit.yaml` has a report for its exact version, whose image digest equals the local image's, from a suite no older than the minimum, with every required profile passed. A rebuilt image needs a new report.

### The two gates

| | Runs standalone | Joins a shell |
|---|---|---|
| Who | a component in any language | a component in a language with an official SDK and a shell launcher |
| Needs | a green suite report for its version; `protocol` in `assembly.yaml`; its stack written in its `AGENTS.md` | the above, built with the same SDK version as the shell's other members; the `shell` profile green; the shell's member checks ([27](27-shells.md)) |
| Source-scanning gates (`bare-route-scan`, `identity-literal-scan`, import checks) | official languages only; for another language, the suite plus a review against the INTERNAL list replace them | all apply |
| `compconf-record-scan` | applies | applies |

### Official SDKs

- **Same nouns.** The three SDKs use one set of names for the same concepts, cased per language (PascalCase, snake_case, camelCase). Adapters (bus, database dialect, cold store) live inside the SDK, chosen by a URL scheme or a configuration value, never imported by a component.
- **Each SDK ships the fixture component** `examples/widget` (`conformance/widget-go`, `-py`, `-ts`), defined once in `be-protocol` `fixtures/widget/`: one table per lifecycle class, a user API with an idempotent command and a two-phase command, gRPC methods with item limits, published and consumed events, a cron job, a worker and a reconciler. Every SDK runs the suite against it in CI. The same widget passing the same suite in three languages is the evidence that the SDKs are equivalent.
- **Broken variants** of the widget, selected by a build argument, each break exactly one rule: accepting refresh tokens, `/healthz` querying the database, no `ce-id`, claiming the outbox with a plain `SELECT`, writing without switching role, an unbounded pool, no deadline, leaking internal errors.
- Every SDK states the protocol version it implements in `/_be/info` and its README; `make vectors` syncs and runs the vectors, `make conformance` builds the widget and runs the suite.

The stack each official SDK locks ([0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md), to be revised with the TypeScript backend row):

| Layer | Go | Python | TypeScript |
|---|---|---|---|
| Runtime | Go 1.25 | CPython 3.14 | Node 24 LTS |
| HTTP | Gin | FastAPI on uvicorn, one event loop | Fastify 5 (the BFF's GraphQL: graphql-yoga 5 on Fastify) |
| gRPC | grpc-go | grpc.aio | @grpc/grpc-js with ts-proto generated code |
| Database | database/sql + pgx/v5, sqlc, hand-written SQL | asyncpg 0.31.0, hand-written SQL | pg (node-postgres) 8, hand-written SQL, zod row checks |
| Migrations | golang-migrate | yoyo-migrations with psycopg[binary] 3.3.6 | node-pg-migrate |
| Events | nats.go JetStream | nats-py JetStream | @nats-io/jetstream |
| Decimal | cockroachdb/apd v3 | `decimal` | decimal.js |
| JWT | golang-jwt v5 + keyfunc v3 | PyJWT (with `audience`) | jose 6 |
| Tracing | otel-go | opentelemetry-python | @opentelemetry/sdk-trace-base, no auto-instrumentation |
| Time zone data (MUST be embedded) | `time/tzdata` | the `tzdata` package | full ICU |
| Tests | testing + testify + rapid | pytest + hypothesis | vitest + fast-check |

Python: `pyarrow` only in the `besdk[cold]` extra; UUIDv7 from the standard library (`uuid.uuid7`, new in 3.14). Every SDK embeds its time zone data, so a business date never depends on the image's `/usr/share/zoneinfo`; the cross-language calendar vectors are re-checked whenever the tz data changes ([05](05-time-and-calendars.md)).

TypeScript gains database, migrations, events, idempotency and jobs in v0.6.0, so it can host any component, not only the BFF. The TypeScript choices are reasoned in [Why this choice](#why-this-choice).

### Shell launchers

Each official SDK ships the launcher for its language. The four invariants and the merge-safety checklist they implement are in [27-shells.md](27-shells.md).

| Language | Member version read from | Shell repositories |
|---|---|---|
| Go | Go build info | `be/go-core`, `be/go-infra`, `be/go-backoffice` |
| Python | `importlib.metadata` | `be/py-render` |
| TypeScript | the member package's `package.json` | none yet: the only TypeScript component, the BFF, never joins a shell ([0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)); the launcher is proved by the `shell` profile on two widget instances |

The same semantics in every language: read `BRICKKIT_SERVED_MEMBERS_CONFIG`; missing, empty or `null` is an error, `[]` means no members. A listed member that is not compiled in, or compiled at another version, exits 2 naming the member. A member whose database host, port or name, bus address, authorization address, `IAM_*` or `TENANT_ID` differs from the shell's exits 78. Then the launcher builds the four process-wide things once, builds a runtime per member, serves each member on its own ports, supervises all background work with the same supervisor as standalone, and serves `/healthz` and the aggregated `/metrics` on the shell's own port.

### A fourth language

1. **Choose a stack** and write it in the component's `AGENTS.md`, section "Stack". Put `protocol: "1.0"` and `language: <name>` in `assembly.yaml`.
2. **Implement in this order**; each step makes one more profile pass: `core`, `obs`, `err` → `auth` → `db` (identity, `SET LOCAL`, timeouts, pool, platform migration with the reference DDL) → `events-pub`, `events-sub` → `idempotency`, `jobs`, `lifecycle` → `scope`, `grpc`, `outbound`. Run the vectors (SHOULD); they are faster to work from than the text.
3. **Pass the suite**: the component may then run standalone.
4. **Review against the INTERNAL list**: no network call inside a transaction; no nested transaction; every database access in a transaction that starts with `SET LOCAL ROLE` and `search_path`, no session `SET`; transaction-level advisory locks with the protocol's key derivation; list SQL built from the evaluated scope predicate, never string-built `WHERE`; no authorization decision cached across requests; raw tokens never logged; only declared configuration keys read; all background work supervised; multi-row locks in a fixed order.
5. **Write the runtime cost**: a JVM or CLR process needs 256–512 MiB resident and starts in seconds. Raise `healthCheck.startPeriodSeconds` and `requests.memory` and say so in `BRICKKIT.md`, "Before you deploy". brickKit runs any language: images, migration containers and health checks are language-neutral, and `mode: local` starts a bare process through `local.runCommand`.
6. **Before the language's second component**: add its row to 0103 and decide on an official SDK. The bar for an official SDK: all vectors pass; its widget passes the component, bus and lifecycle suites; its launcher passes the `shell` profile; it ships a test package; `02-backend.md` has a section for it.

## Alternatives

| | Strengths | Weaknesses |
|---|---|---|
| Lock the languages (today's 0105) | one place for every rule; source-scanning gates cover all code | a component cannot use a better ecosystem; "replaceable" stops at the language |
| Protocol plus black-box suite, SDKs as reference implementations (chosen) | any language; one verdict for all; the suite doubles as the SDKs' regression test | a specification to maintain; INTERNAL rules need review outside official languages |
| A sidecar runtime (Dapr) | language-neutral building blocks: state, pub/sub, bindings | a second process per component; one app identity per sidecar, so members in a shell lose their identity; does not cover our schema, role and outbox rules |
| The WebAssembly component model | one sandboxed runtime for many languages | PostgreSQL, gRPC and NATS clients are immature in WASI; no mainstream ERP stack runs on it |
| One native core library bound into each language | one implementation of the hard parts | FFI per language; our images build without cgo; async models differ between runtimes |
| Conventions per language, no black-box suite | no specification to write | drift between languages goes unnoticed until production |

## Why this choice

- **The user's requirement (L1)**: each component may choose its language. Rules that live in one SDK make that language the reference; rules in a separate repository with a suite do not.
- **Judging behaviour, not code**, gives one verdict for every language and catches what reading code misses: a refresh token accepted, a pool without a limit.
- **Specification and vectors share one version number**, so all three SDKs and the suite agree on exactly which semantics they implement.
- **The TypeScript stack, against market options.** Fastify 5 over Hono, Express 5 or NestJS: its hooks (onRequest, preHandler, onSend, onError, onTimeout) hold the SDK's middleware chain, one instance per member isolates members, and it ships pino and JSON-schema validation; Hono targets the Web Request API and has weaker server-side controls on Node; Express has no hook model; NestJS brings a second way of doing everything. node-postgres over porsager/postgres, Kysely, Drizzle or Prisma: the SDK must `SET LOCAL ROLE` and `search_path` in every transaction, porsager caches prepared statements implicitly, the others are query builders or ORMs ([0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md) has no ORM), and Prisma cannot switch role per transaction. node-pg-migrate keeps plain SQL and its state table in the component's schema. grpc-js over connect-node: connect-node lacks service-config retries, retry budgets and server `MaxConnectionAge`.

## Why not the others

- **Locked languages**: the very restriction L1 removes.
- **Dapr**: costs a process per component on a single machine, and the shell's one-process merge would collapse members into one app identity.
- **WASM**: the drivers this project needs are not production-ready.
- **A native core**: breaks the cgo-free images, and one crash in the core takes every language with it.
- **Conventions without a suite**: what is not tested drifts; the 45 problems found in the v0.5.0 SDKs are that drift.

## When to switch

- **The protocol cannot express a capability** that a language ecosystem needs (the reopen condition of the rewritten 0105): extend the protocol in a minor if it is optional, in a major if it becomes required.
- **A language reaches its second component**: lock its stack (0103) and decide on an official SDK.
- **Several components in one non-official language strain memory on one machine**: build the official SDK and launcher, then a shell repository for that language.
- Merging two languages into one process is never a switch; see [Known limits](#known-limits).

## How to switch

- **A component in a new language**: follow [A fourth language](#a-fourth-language). It touches that component's repository, its `assembly.yaml` and `BRICKKIT.md`, and its test record; no other component changes.
- **A component rewritten in another language**: same component ID, contracts, schema and events; a new version with a new suite report. If its old language had a shell and the new one does not, the deploy file moves it out of the shell.
- **A protocol minor**: the change order under [Repository layout](#repository-layout-of-be-protocol); components keep the protocol they declare until they move up.
- **An official SDK for a new language**: the bar in step 6, then a shell repository for that language ([0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)).

## Conformance tests

- **The case catalogue** per profile is in `be-protocol` and the suite. Representative cases: migrating twice exits 0; a missing required key exits 78 naming it; `/healthz` stays 200 with PostgreSQL stopped; refresh, `alg: none`, wrong-`iss` and wrong-`aud` tokens get 401; the List and Check answers agree under random grants; a command with the bus stopped succeeds and its event is delivered exactly once after the bus returns; two replicas publish each outbox row once; with random identity every table is owned by `PG_OWNER_USER` and nothing exists outside the schema; a listed member not compiled in stops the shell naming it.
- **Red first.** The suite's self-test asserts that each broken widget variant fails exactly its own case. A green suite is trusted only after that.
- **Vectors**, outside any suite: every official SDK's unit tests read `be-protocol` `vectors/` and, for a slot family it consumes, the family contract's `vectors/`; a fourth language SHOULD.
- **Split of work with the other suites**, all under `tools/be-acceptance/conformance/<port>/`: `component` (this protocol, every component and shell); `authz` and `iam` (slot-family members, [20](20-authorization-provider.md), [21](21-identity-provider.md)); `bus` and `lifecycle` (adapters inside each SDK, run once per SDK through its widget, [12](12-event-bus.md), [09](09-data-lifecycle.md)); `db` (engines, [03](03-database.md)); `blob`, `secret`, `search` (their ports).
- **Shells**: the widget runs standalone and inside a shell, with identical black-box results.

## Decision records

- [0109 The rules live in a language-neutral component protocol, checked by a black-box suite](../02-decisions/01-architecture/0109-language-neutral-component-protocol.md): this document carries its analysis.
- [0105 Any language, one protocol](../02-decisions/01-architecture/0105-any-language-one-protocol.md): the two gates; the JVM/CLR caveat; no process mixes languages.
- [0103 One locked stack inside each language](../02-decisions/01-architecture/0103-locked-stack-per-language.md): the stack table above, with the TypeScript backend row, and the rule that a language's stack is locked before its second component.
- [0101 Components never import each other](../02-decisions/01-architecture/0101-no-imports-between-components.md): the official SDKs and family contract packages may cross a boundary; the protocol's vectors and schemas are copied test data, not code.
- [0108 One shell, one repository, one image, one member list](../02-decisions/01-architecture/0108-one-repository-per-shell.md): one SDK version per shell, and the launcher's start-up checks.
- [0104 A slot family needs several reasonable implementations and no dependency edge](../02-decisions/01-architecture/0104-variants-become-slot-families.md): the family contracts the protocol cites by major (`contract: authz/2.x`).

## Known limits

- **No process mixes languages.** A component in a language without a launcher always runs standalone.
- **INTERNAL rules are invisible to the suite.** Outside the official languages they rest on review, and the source-scanning gates do not run.
- **The suite needs real PostgreSQL and NATS** and takes minutes per component; it is run at release time, not on every save.
- **`/readyz` is not wired into probes** until brickKit supports readiness probes; it is a SHOULD.
- **TypeScript has a launcher but no shell repository**, because no TypeScript component joins a shell today.
- **A JVM or CLR component costs 256–512 MiB and seconds of start-up** per process; on one machine this is the main reason not to choose one.
- **Until `be-protocol` v1.0.0 is tagged**, the specification is a release candidate and may still change with the pilot components.
