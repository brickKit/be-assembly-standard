[English](0103-locked-stack-per-language.md) · [中文](../../../zh/02-decisions/01-architecture/0103-locked-stack-per-language.md)

# 0103 One locked stack inside each language

**Status**: revised for 3.0.0 (TypeScript row, admission rule for a new language); decided, lands with the 3.0.0 sweep.

## Decision

Inside each language every cell of the stack is fixed; a component of that language does not choose. The stack is the official SDK's own: a component gets it by building on that SDK.

| Layer | Go | Python | TypeScript |
|---|---|---|---|
| Runtime | Go 1.25 | CPython 3.13 | Node 24 LTS |
| HTTP | Gin | FastAPI on uvicorn: one process, one event loop | Fastify 5; the BFF's GraphQL is graphql-yoga 5 on Fastify |
| gRPC | `grpc-go` | `grpc.aio` | `@grpc/grpc-js` with ts-proto (`outputServices=grpc-js`) |
| Database | `database/sql` + `pgx/v5/stdlib`, `sqlc`, hand-written SQL | `asyncpg`, hand-written SQL, Pydantic row mapping | `pg` (node-postgres) 8, hand-written SQL, zod row validation |
| Migrations | `golang-migrate`, plain `.sql` files | `yoyo-migrations`, plain `.sql` files, entry in the SDK | `node-pg-migrate`, plain SQL files |
| Events | `nats.go` `jetstream` | `nats-py` JetStream | `@nats-io/jetstream` + `@nats-io/transport-node` |
| Decimal | `cockroachdb/apd/v3` | `decimal` | `decimal.js` |
| JWT | `golang-jwt/v5` + `keyfunc/v3` | PyJWT, always with `audience` | `jose` 6 |
| Outbound HTTP | `net/http` | `httpx` | `undici`, one Agent per dependency |
| Logs / metrics | `slog` / `client_golang`, one registry per module | `logging` with the SDK's JSON formatter / `prometheus-client`, one `CollectorRegistry` per module | `pino` / a Prometheus client, one registry per module |
| Traces | `otel-go` + `otelgrpc` | `opentelemetry-python` + gRPC interceptors | `@opentelemetry/sdk-trace-base`, no auto-instrumentation |
| Object storage | `aws-sdk-go-v2` | `aioboto3` | `@aws-sdk/client-s3` |
| UUIDv7 / pinyin | `google/uuid` / `go-pinyin` | `uuid6` / `pypinyin` | `uuid` 11 / `pinyin-pro` |
| Tests | `testing` + `testify` + `rapid` | `pytest` + `pytest-asyncio` + `hypothesis` | `vitest` + `fast-check` |
| Packages | Go modules | `pyproject`, exact versions | npm + `package-lock.json` |

No ORM anywhere. Every backend component exposes one entry, its `Spec` run by the SDK's `Main` (`besdk.Main` in Go, `besdk.main` in Python, `main` in TypeScript), which runs the same way standalone and inside a shell; the module gets its configuration, store, logger and telemetry from the runtime and never reads the process environment, initialises process-wide state, or exits the process.

**A new language.** While a language has one component, that component chooses its own stack and writes it in the "Stack" section of its `AGENTS.md` ([0105](0105-any-language-one-protocol.md)). Before a second component in the same language is added, the language gets a column in this table, and the project decides whether it gets an official SDK.

## Why

A shell runs many modules in one process. Some cells physically cannot be mixed there: a WSGI handler cannot use the shared async pool, synchronous gRPC cannot share the event loop, two pool types cannot both be handed to modules, and two modules on the default metrics registry crash the second one at start. Others start fine and go silently wrong: the last module to initialise logging or tracing wins for all of them. Locking the HTTP framework means the SDK's middleware chain (tracing, request ids, deadlines, error mapping, metrics) is written exactly once per language. For TypeScript, now a full backend language: Fastify's hooks hold that chain and give one instance per member; node-postgres can `SET LOCAL ROLE` and `search_path` per transaction where query builders and ORMs cannot; grpc-js is the maintained JavaScript gRPC with retry policy, retry throttling and connection-age rotation. Without a lock before the second component, one language holds two ways of writing the same thing, and its components can never share a shell.

## What this rules out

- Echo, Fiber, chi or a bare `http.ServeMux` for a Go component
- GORM, SQLAlchemy ORM, Prisma, Drizzle, Kysely or any ORM or query builder; `pgxpool.Pool` as the module's pool type; `porsager/postgres` with its statement cache
- Flask or Django; synchronous `grpc`; gunicorn, or uvicorn with more than one worker
- Express, Hono or NestJS; Apollo Server; `connect-node` for gRPC; OpenTelemetry auto-instrumentation in Node
- alembic, or a second migration tool inside one language
- "This component would be simpler with library X": per-component framework choices
- A second component in a language that has no column here
- A `main` that opens its own pool, listens on its own port, installs signal handlers or initialises OTel

## Revisit only if

A library in the table is abandoned, or has a gap that no workaround covers. The cell then changes in the SDK for every component of that language at once, never for a single component.

Full analysis: [02-languages-and-component-protocol.md, Choice](../../04-foundations/02-languages-and-component-protocol.md#choice); the shell constraints in [27-shells.md, Choice](../../04-foundations/27-shells.md#choice).
