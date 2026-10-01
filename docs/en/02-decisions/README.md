[English](README.md) · [中文](../../zh/02-decisions/README.md)

# Decisions

The decisions that constrain future changes to this project. Each file gives the conclusion, a short reason, the requests it rules out, and when it is worth reopening. A request that conflicts with one of them is not refused silently and not done quietly: quote the decision and let a person decide.

## Numbering

- Numbers start at `0001` and are never reordered or reused, because other documents cite them.
- A new decision takes the next free number.
- A decision that is overturned keeps its file; a line `Superseded by NNNN` goes at its top, and the new decision links back to it.
- Until phase 06 ends, a decision written or changed during phase 06 is rewritten in place and keeps its number: nothing downstream depends on it yet. From then on the rule above applies.
- Numbers run across all folders: moving a decision to another folder never changes its number or its file name.

## Folders

| Folder | Holds |
|---|---|
| `01-architecture/` | how the system is cut and assembled: component boundaries, schemas, the locked stacks, slot families, languages, what is not a component, shared addresses, shells |
| `02-permissions/` | who may do what and see which rows: no Redis, the local permission bundle, the identity-only token, the pure union, data scopes, no row-level security |
| `03-contracts-and-data/` | what crosses a boundary and what goes into a database: money and paging, additive-only contracts, no test accounts in migrations |
| `04-frontend/` | the frontend stack, the ui-kits, navigation, user preferences, design tokens |

A new decision goes into the folder whose question it answers; when none fits, a new numbered folder is added to both `docs/en/02-decisions/` and `docs/zh/02-decisions/`.

## Index

| No. | Decision | Rules out | Folder |
|---|---|---|---|
| [0001](01-architecture/0001-no-imports-between-components.md) | Components never import each other; only `be-sdk-*` and generated contract packages are shared | Calling another component's function directly because they share a shell; a shared models package | `01-architecture/` |
| [0002](01-architecture/0002-one-schema-per-component.md) | One database, one schema and role per component, migration state in its own schema | A database per component; cross-schema joins; reading another component's tables | `01-architecture/` |
| [0003](01-architecture/0003-locked-stack-per-language.md) | One locked stack per language (Gin / FastAPI, no ORM, fixed migration tools) | Echo, GORM, Flask, alembic, gunicorn workers; per-component framework choices | `01-architecture/` |
| [0004](01-architecture/0004-variants-become-slot-families.md) | A slot family needs several reasonable implementations **and** no dependency edge on the position; otherwise one default plus customer forks | A costing / picking slot family ("let customers choose FIFO or weighted-average costing" → default + fork); `if costingMethod == ...` per customer; "make the algorithm configurable" | `01-architecture/` |
| [0005](01-architecture/0005-no-java-or-csharp.md) | No Java or C# | Spring Boot / .NET components; a fourth backend language | `01-architecture/` |
| [0006](01-architecture/0006-infrastructure-is-not-a-component.md) | Event bus, object storage, gateway and observability are not components | An `infra/nats` or gateway component; swapping NATS for Kafka by a setting | `01-architecture/` |
| [0007](01-architecture/0007-authz-and-iam-addresses-are-shared-vars.md) | Polling the permission bundle and verifying tokens use shared variables, not dependencies; a real gRPC call to authz / iam declares its dependency as usual | A dependency edge on `infra/authz` or the IAM component just to fetch the bundle or verify tokens; calling their gRPC API without declaring the dependency | `01-architecture/` |
| [0008](01-architecture/0008-one-repository-per-shell.md) | One shell, one repository (a submodule under `shell/<scope>/<name>/`, released there with a bare `<version>` tag), one image, one member list | Shell code committed in this repository; releasing a shell from here; logic in a shell; upgrading a member without the shell | `01-architecture/` |
| [0009](02-permissions/0009-no-redis.md) | No Redis | Adding a cache, caching permissions in Redis, Redis sessions, distributed locks, Redis rate limiting | `02-permissions/` |
| [0010](02-permissions/0010-local-permission-bundle.md) | Permissions are checked against a bundle pulled into memory | Permission tables in components; caching permissions in Redis; asking authz per request; authz in `/healthz` | `02-permissions/` |
| [0011](02-permissions/0011-jwt-carries-identity-only.md) | The token carries identity only | Permissions or scopes in JWT claims | `02-permissions/` |
| [0012](02-permissions/0012-permissions-are-a-pure-union.md) | Permissions are a pure union, no Deny | "Everyone except X"; deny rules; rule ordering | `02-permissions/` |
| [0013](02-permissions/0013-data-scopes-ship-with-the-version.md) | Data scopes ship with the version; `data_scopes` is mandatory | An admin screen for row visibility; filtering after fetching; omitting `data_scopes` | `02-permissions/` |
| [0014](02-permissions/0014-no-row-level-security.md) | No row-level security, no sharing engine; `dept_path` prefix for `org` | `CREATE POLICY`; record-sharing tables; copies of the org tree | `02-permissions/` |
| [0015](03-contracts-and-data/0015-money-as-strings-lists-by-cursor.md) | Money is a decimal string; lists page by cursor | `double` amounts; `offset` / page numbers in `List` | `03-contracts-and-data/` |
| [0016](03-contracts-and-data/0016-contracts-are-additive-only.md) | Contracts change by adding only | Renaming, retyping or deleting fields, RPCs or event subjects | `03-contracts-and-data/` |
| [0017](03-contracts-and-data/0017-no-test-accounts-in-migrations.md) | No test accounts in migrations; the first admin comes from `BOOTSTRAP_ADMIN_SUB` | A default admin account; demo data in migrations | `03-contracts-and-data/` |
| [0018](04-frontend/0018-frontend-stack.md) | Vue 3; AntDV + vxe-table on PC; wot-design-uni on mobile; only tokens shared | React; Element Plus / Naive UI; one component library for both ends | `04-frontend/` |
| [0019](04-frontend/0019-third-party-ui-only-in-ui-kit.md) | Third-party UI components appear only inside ui-kit | Importing AntDV / vxe directly in a page; mixing libraries for looks | `04-frontend/` |
| [0020](04-frontend/0020-two-tier-navigation.md) | PC navigation is two-tier, console style, with in-app tabs | A multi-level tree menu; admin templates as a dependency; pages from a blank `<div>` | `04-frontend/` |
| [0021](04-frontend/0021-four-user-preferences.md) | Users own four preferences | A layout-mode switch; per-user theme colour | `04-frontend/` |
| [0022](04-frontend/0022-design-tokens-are-css-variables.md) | Design tokens are runtime CSS variables | Tokens as TS constants; hard-coded colours and spacing | `04-frontend/` |
