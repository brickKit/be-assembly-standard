# be/go-backoffice

## Purpose

Runs the CRM, HRM, project and back-office ERP Go components in one process, to save the memory and CPU of one runtime per component. Each member keeps its own ports, schema, role, migration and image; the shell only hosts them.

The components meant for this shell are the `go-backoffice` port group in `registry/ports.tsv`: crm/opportunity; later the other crm/*, hrm/* and prj/* components, erp/asset, erp/quality, erp/maintenance. It currently compiles in no members: each member is added when that component moves to brickKit v1.

- **Owns**: one Go process; one shared PostgreSQL pool and one NATS connection, opened with the shell's own login role; loading the permission bundle once; its own `/healthz` on port 8116.
- **Does not own**: any business logic, route, table or contract (each member owns its own); members' migrations (brickKit runs each from the member's own image before the shell starts); which members a deployment hosts (the project's deploy file chooses, from those compiled in).

## Before you deploy

- A PostgreSQL login role `shell_go_backoffice` with its password in the environment variable `SHELL_GO_BACKOFFICE_PASSWORD` (in `.env` locally). `make db-init` creates it and, for each member listed in `shell.members`, grants it that member's role (`GRANT <member>_rw TO shell_go_backoffice`), so the shell can switch to the member with `SET LOCAL ROLE`. With no members it creates only the login role.
- PostgreSQL and NATS reachable at start: the shell opens its connections even with no member hosted.
- The image built with `brickkit build`: the build records the compiled-in member versions, which `brickkit up` checks.

## Dependencies

None. The shell has no dependency edges of its own; each member keeps its own, and they are resolved for the member as if it ran alone. The permission bundle and the identity key set are configuration, not dependencies.

## Configuration

| Variable | Meaning |
|---|---|
| `PG_HOST` | PostgreSQL host; the shell opens one shared pool for all its members |
| `PG_PORT` | PostgreSQL port |
| `PG_DATABASE` | PostgreSQL database |
| `PG_USER` | The shell's own login role, never a member's role |
| `PG_PASSWORD` | Password of that login role (secret) |
| `NATS_URL` | Event bus URL; the shell opens one shared connection for all its members |
| `OTEL_BASE_URL` | Telemetry collector base URL; empty disables export |
| `AUTHZ_BUNDLE_URL` | Permission bundle address, loaded once for the whole process; required, the shell refuses to start without it |
| `IAM_JWKS_URL` | Identity provider signing-key address, loaded once for the whole process; required, the shell refuses to start without it |

These are the shell's own keys, read from the shell's process environment. A member's configuration never comes from here: brickKit passes it per member in `BRICKKIT_SERVED_MEMBERS_CONFIG`.

## Contracts

None. The shell's only interface is `/healthz` on port 8116, which reports that the process is alive and checks nothing else. Every member serves its own contracts on its own ports, at its own service name.

## Shell declaration

This component is a shell. Members compiled in (keep in step with shell.members in component.yaml): none yet. Members are added one at a time; each one is also registered in the shell's code and required at the same version in `go.mod`.
