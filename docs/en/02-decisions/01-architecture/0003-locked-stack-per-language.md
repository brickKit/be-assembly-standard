[English](0003-locked-stack-per-language.md) · [中文](../../../zh/02-decisions/01-architecture/0003-locked-stack-per-language.md)

# 0003 One locked stack per language

## Decision

Every cell of the stack is fixed per language; components do not choose.

| Layer | Go | Python | TypeScript |
|---|---|---|---|
| HTTP | Gin | FastAPI on uvicorn: one process, one event loop | Apollo Server 4 (BFF only) |
| gRPC | `grpc-go` | `grpc.aio` | none |
| Database | `database/sql` + `pgx/v5/stdlib`, `sqlc`, hand-written SQL | `asyncpg`, hand-written SQL, Pydantic row mapping | never connects to a database |
| Migrations | `golang-migrate`, plain `.sql` files | `yoyo-migrations`, plain `.sql` files | — |
| Metrics | one Prometheus registry per module | one `CollectorRegistry` per module | — |
| Tests | `testing` + `testify` + `rapid` | `pytest` + `pytest-asyncio` + `hypothesis` | `vitest` |

No ORM anywhere. Every backend component exposes one module entry (`module.New` in Go, `create_module` in Python) that runs the same way standalone and inside a shell; the module gets its configuration, pool, logger and telemetry from the runtime and never reads the process environment, initialises process-wide state, or exits the process.

## Why

A shell runs many modules in one process. Some cells physically cannot be mixed there: a WSGI handler cannot use the shared async pool, synchronous gRPC cannot share the event loop, two pool types cannot both be handed to modules, and two modules on the default metrics registry crash the second one at start. Others start fine and go silently wrong: the last module to initialise logging or tracing wins for all of them. Gin is locked so that the SDK's middleware chain (tracing, request ids, error mapping, metrics) is written exactly once.

## What this rules out

- Echo, Fiber, chi or a bare `http.ServeMux` for a Go component
- GORM, SQLAlchemy ORM or any ORM; `pgxpool.Pool` as the module's pool type
- Flask or Django; synchronous `grpc`; gunicorn, or uvicorn with more than one worker
- alembic, or a second migration tool inside one language
- "This component would be simpler with library X" — per-component framework choices
- A `main` that opens its own pool, listens on its own port, installs signal handlers or initialises OTel

## Revisit only if

A library in the table is abandoned, or has a gap that no workaround covers. The cell then changes in the SDK for every component of that language at once — never for a single component.
