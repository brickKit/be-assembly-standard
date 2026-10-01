[English](README.md) · [中文](README.zh.md)

# Decisions

The decisions that constrain future changes to this project. Each file gives the conclusion, a short reason, the requests it rules out, and when it is worth reopening. A request that conflicts with one of them is not refused silently and not done quietly: quote the decision and let a person decide.

## Numbering

- Numbers start at `0001` and are never reordered or reused, because other documents cite them.
- A new decision takes the next free number.
- A decision that is overturned keeps its file; a line `Superseded by NNNN` goes at its top, and the new decision links back to it.

## Index

| No. | Decision | Rules out |
|---|---|---|
| [0001](0001-no-imports-between-components.md) | Components never import each other; only `be-sdk-*` and generated contract packages are shared | Calling another component's function directly because they share a shell; a shared models package |
| [0002](0002-one-schema-per-component.md) | One database, one schema and role per component, migration state in its own schema | A database per component; cross-schema joins; reading another component's tables |
| [0003](0003-locked-stack-per-language.md) | One locked stack per language (Gin / FastAPI, no ORM, fixed migration tools) | Echo, GORM, Flask, alembic, gunicorn workers; per-component framework choices |
| [0004](0004-no-redis.md) | No Redis | Adding a cache, caching permissions in Redis, Redis sessions, distributed locks, Redis rate limiting |
| [0005](0005-local-permission-bundle.md) | Permissions are checked against a bundle pulled into memory | Permission tables in components; caching permissions in Redis; asking authz per request; authz in `/healthz` |
| [0006](0006-jwt-carries-identity-only.md) | The token carries identity only | Permissions or scopes in JWT claims |
| [0007](0007-permissions-are-a-pure-union.md) | Permissions are a pure union, no Deny | "Everyone except X"; deny rules; rule ordering |
| [0008](0008-data-scopes-ship-with-the-version.md) | Data scopes ship with the version; `data_scopes` is mandatory | An admin screen for row visibility; filtering after fetching; omitting `data_scopes` |
| [0009](0009-no-row-level-security.md) | No row-level security, no sharing engine; `dept_path` prefix for `org` | `CREATE POLICY`; record-sharing tables; copies of the org tree |
| [0010](0010-money-as-strings-lists-by-cursor.md) | Money is a decimal string; lists page by cursor | `double` amounts; `offset` / page numbers in `List` |
| [0011](0011-contracts-are-additive-only.md) | Contracts change by adding only | Renaming, retyping or deleting fields, RPCs or event subjects |
| [0012](0012-variants-become-slot-families.md) | A slot family needs several reasonable implementations **and** no dependency edge on the position; otherwise one default plus customer forks | A costing / picking slot family ("let customers choose FIFO or weighted-average costing" → default + fork); `if costingMethod == ...` per customer; "make the algorithm configurable" |
| [0013](0013-frontend-stack.md) | Vue 3; AntDV + vxe-table on PC; wot-design-uni on mobile; only tokens shared | React; Element Plus / Naive UI; one component library for both ends |
| [0014](0014-third-party-ui-only-in-ui-kit.md) | Third-party UI components appear only inside ui-kit | Importing AntDV / vxe directly in a page; mixing libraries for looks |
| [0015](0015-two-tier-navigation.md) | PC navigation is two-tier, console style, with in-app tabs | A multi-level tree menu; admin templates as a dependency; pages from a blank `<div>` |
| [0016](0016-four-user-preferences.md) | Users own four preferences | A layout-mode switch; per-user theme colour |
| [0017](0017-design-tokens-are-css-variables.md) | Design tokens are runtime CSS variables | Tokens as TS constants; hard-coded colours and spacing |
| [0018](0018-no-java-or-csharp.md) | No Java or C# | Spring Boot / .NET components; a fourth backend language |
| [0019](0019-infrastructure-is-not-a-component.md) | Event bus, object storage, gateway and observability are not components | An `infra/nats` or gateway component; swapping NATS for Kafka by a setting |
| [0020](0020-no-test-accounts-in-migrations.md) | No test accounts in migrations; the first admin comes from `BOOTSTRAP_ADMIN_SUB` | A default admin account; demo data in migrations |
| [0021](0021-authz-and-iam-addresses-are-shared-vars.md) | Polling the permission bundle and verifying tokens use shared variables, not dependencies; a real gRPC call to authz / iam declares its dependency as usual | A dependency edge on `infra/authz` or the IAM component just to fetch the bundle or verify tokens; calling their gRPC API without declaring the dependency |
| [0022](0022-shells-are-project-code.md) | Shells are project code: one shell, one image, one member list | A repository per shell; logic in a shell; upgrading a member without the shell |
