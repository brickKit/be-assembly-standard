[English](README.md) · [中文](../../zh/02-decisions/README.md)

# Decisions

The decisions that constrain future changes to this project. Each file gives the conclusion, a short reason, the requests it rules out, and when it is worth reopening; its last line links the foundations section with the full analysis ([04-foundations](../04-foundations/README.md)). A request that conflicts with one of them is not refused silently and not done quietly: quote the decision and let a person decide.

## Numbering

- Each folder has its own number range, so a folder's numbers stay contiguous: `01-architecture/` 0101–0199, `02-permissions/` 0201–0299, `03-contracts-and-data/` 0301–0399, `04-frontend/` 0401–0499, `05-runtime/` 0501–0599. A new folder `NN-…` gets `NN01`–`NN99`.
- A new decision takes the next free number in its folder's range.
- Numbers are never reused, because other documents cite them.
- A decision that is overturned keeps its file; a line `Superseded by NNNN` goes at its top, and the new decision links back to it.
- Until phase 06 ends, a decision written or changed during phase 06 is rewritten in place and keeps its number: nothing downstream depends on it yet; a rewrite may rename the file to match its new title (0105), and every link to it is updated in the same change. From then on the rule above applies.

## Folders

| Folder | Holds |
|---|---|
| `01-architecture/` | how the system is cut and assembled: component boundaries, schemas, the locked stacks, slot families, languages and the component protocol, what is not a component, shared addresses, shells |
| `02-permissions/` | who may do what and see which rows: no Redis, local decisions, the identity-only token, the pure union, data scopes and their assignments, no row-level security, the system plane, the authz slot family, delegation, field permissions, 404 for invisible records |
| `03-contracts-and-data/` | what crosses a boundary and what goes into a database: money and paging, additive-only contracts, no test accounts in migrations, batch limits, the 3.0.0 rebuild, keys, business dates, tenancy |
| `04-frontend/` | the frontend stack, the ui-kits, navigation, user preferences, design tokens |
| `05-runtime/` | how a running component behaves: transactions, isolation and retry, deadlines, errors, the event envelope and delivery, idempotency, background work, what the edge does |

A new decision goes into the folder whose question it answers; when none fits, a new numbered folder is added to both `docs/en/02-decisions/` and `docs/zh/02-decisions/`.

## Index

| No. | Decision | Rules out | Folder |
|---|---|---|---|
| [0101](01-architecture/0101-no-imports-between-components.md) | Components never import each other; only the official SDKs, generated contract packages and family contract packages are shared | Calling another component's function directly because they share a shell; a shared models package | `01-architecture/` |
| [0102](01-architecture/0102-one-schema-per-component.md) | One PostgreSQL-family database, one schema and role per component, identity from `PG_USER` / `PG_SCHEMA` only | A database per component; cross-schema joins; deriving the role from the schema; touching `besdk_*` tables | `01-architecture/` |
| [0103](01-architecture/0103-locked-stack-per-language.md) | One locked stack inside each language (Go, Python, TypeScript); a new language is locked before its second component | Echo, GORM, Express, Prisma, alembic; per-component framework choices | `01-architecture/` |
| [0104](01-architecture/0104-variants-become-slot-families.md) | A slot family needs several reasonable implementations **and** no dependency edge on the position; otherwise one default plus customer forks | A costing / picking slot family ("let customers choose FIFO or weighted-average costing" → default + fork); `if costingMethod == ...` per customer; "make the algorithm configurable" | `01-architecture/` |
| [0105](01-architecture/0105-any-language-one-protocol.md) | Any language, one protocol: a green conformance report admits a component; a shell needs the language's SDK and launcher | Mixing languages in one process; a component without a conformance report; a silent JVM memory cost | `01-architecture/` |
| [0106](01-architecture/0106-infrastructure-is-not-a-component.md) | Event bus, object storage, gateway, observability and IdP servers are not components; the bus is swapped by an SDK adapter chosen by URL scheme | An `infra/nats` or gateway component; swapping NATS for Kafka by a setting without an adapter | `01-architecture/` |
| [0107](01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md) | Family addresses (`AUTHZ_URL`, `AUTHZ_GRPC_URL`, `IAM_URL`, `IAM_GRPC_URL`) are `$endpoint:` references in `config/vars.yaml`, beside `IAM_ISSUER` and `TENANT_ID`; no component depends on a family member | A dependency edge on `infra/authz` or the IAM member; a hand-written member address; gRPC port = HTTP port + 1000; `AUTHZ_BUNDLE_URL` | `01-architecture/` |
| [0108](01-architecture/0108-one-repository-per-shell.md) | One shell, one repository (a submodule under `shell/<scope>/<name>/`, released there with a bare `<version>` tag), one image, one member list, one language and SDK version | Shell code committed in this repository; releasing a shell from here; logic in a shell; upgrading a member without the shell | `01-architecture/` |
| [0109](01-architecture/0109-language-neutral-component-protocol.md) | The rules live in the language-neutral component protocol (`be-protocol`), checked by a black-box suite; the SDKs are its reference implementations | A rule only an SDK knows; releasing without a green report; per-language protocol variants | `01-architecture/` |
| [0201](02-permissions/0201-no-redis.md) | No Redis, no cache server; caches live in process, through the SDK | Adding a cache server, Redis sessions, distributed locks, Redis rate limiting; caching decisions | `02-permissions/` |
| [0202](02-permissions/0202-local-permission-bundle.md) | Permissions are decided locally, against a bundle and a projection | Permission tables in components; asking authz per request; authz in `/healthz` | `02-permissions/` |
| [0203](02-permissions/0203-jwt-carries-identity-only.md) | The token carries identity only, and the platform owns `sub` | Permissions or scopes in JWT claims; the IdP subject as user id; tokens without `typ`, `iss`, `aud` | `02-permissions/` |
| [0204](02-permissions/0204-permissions-are-a-pure-union.md) | Permissions are a pure union, no Deny; only a delegation chain intersects | "Everyone except X"; deny rules; rule ordering | `02-permissions/` |
| [0205](02-permissions/0205-data-scopes-ship-with-the-version.md) | Data-scope rules ship with the version; `data_scopes` is mandatory | Editing row rules at runtime; filtering after fetching; omitting `data_scopes` | `02-permissions/` |
| [0206](02-permissions/0206-no-row-level-security.md) | No row-level security; one sharing engine, in authz, projected by the SDK | `CREATE POLICY`; share tables inside components; copies of the org tree | `02-permissions/` |
| [0207](02-permissions/0207-scope-assignments-live-in-authz.md) | Levels, dimension values, shares and delegations are runtime assignments in authz | Access tables inside components; `.admin` keys that widen a scope | `02-permissions/` |
| [0208](02-permissions/0208-grpc-is-the-system-plane.md) | gRPC is the system plane between components; people use REST | User-scoped data over gRPC; a system identity on a user's request path | `02-permissions/` |
| [0209](02-permissions/0209-authz-is-a-slot-family.md) | Authorization is a slot family with contract `infra.authz.v2`, capability negotiation and a suite | Depending on a member; assumed capabilities; silent degradation | `02-permissions/` |
| [0210](02-permissions/0210-delegation-and-impersonation.md) | Delegation and read-only impersonation are bounded by the person acted for; agents reserved only | Delegates exceeding the delegator; writing impersonation; building agents now | `02-permissions/` |
| [0211](02-permissions/0211-field-level-permissions.md) | Field-level permission is a key of `type: field`, masked at the source | Masking in the frontend or BFF; sorting by masked fields | `02-permissions/` |
| [0212](02-permissions/0212-invisible-records-answer-404.md) | A record the caller cannot see answers 404, for reads and commands | `403` for out-of-scope records; errors that tell hidden from absent | `02-permissions/` |
| [0301](03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md) | Money is a decimal string paired with a currency; lists page by cursor | `double` amounts; amounts without currency; `offset` / page numbers in `List` | `03-contracts-and-data/` |
| [0302](03-contracts-and-data/0302-contracts-are-additive-only.md) | Contracts change by adding only; a breaking change is a new major beside the old (REST: `/v2/` prefix with `Deprecation` / `Sunset`) | Renaming, retyping or deleting fields, RPCs, subjects or reasons | `03-contracts-and-data/` |
| [0303](03-contracts-and-data/0303-no-test-accounts-in-migrations.md) | No test accounts in migrations; the first admin comes from `BOOTSTRAP_ADMIN_LOGIN`, bound to the platform `sub` at first login | A default admin account; demo data in migrations; seeds writing the first admin | `03-contracts-and-data/` |
| [0304](03-contracts-and-data/0304-batch-get-takes-at-most-500-ids.md) | A `BatchGet` takes at most 500 IDs, declared in the contract | Unbounded batches; N+1 calls over the network | `03-contracts-and-data/` |
| [0305](03-contracts-and-data/0305-one-shot-baseline-rebuild-for-3-0-0.md) | The 3.0.0 rebuild may replace released migrations, once, with no compatibility layers | Using the exception again; shims "for one version" | `03-contracts-and-data/` |
| [0306](03-contracts-and-data/0306-uuidv7-own-keys.md) | Own keys are UUIDv7; document numbers come from the SDK, vouchers gap-free per period | `BIGSERIAL` keys; numbers built from ids | `03-contracts-and-data/` |
| [0307](03-contracts-and-data/0307-business-dates-and-legal-entity-calendar.md) | Business dates are `DATE` in the legal entity's time zone; fiscal start month per legal entity | `CURRENT_DATE` in SQL; dates from processing time | `03-contracts-and-data/` |
| [0308](03-contracts-and-data/0308-tenant-is-the-deployment.md) | A tenant is a deployment; companies are legal entities inside it | `tenant_id` columns; multi-customer SaaS; documents without a legal entity | `03-contracts-and-data/` |
| [0401](04-frontend/0401-frontend-stack.md) | Vue 3; AntDV + vxe-table on PC; wot-design-uni on mobile; only tokens shared | React; Element Plus / Naive UI; one component library for both ends | `04-frontend/` |
| [0402](04-frontend/0402-third-party-ui-only-in-ui-kit.md) | Third-party UI components appear only inside ui-kit | Importing AntDV / vxe directly in a page; mixing libraries for looks | `04-frontend/` |
| [0403](04-frontend/0403-two-tier-navigation.md) | PC navigation is two-tier, console style, with in-app tabs | A multi-level tree menu; admin templates as a dependency; pages from a blank `<div>` | `04-frontend/` |
| [0404](04-frontend/0404-four-user-preferences.md) | Users own four preferences | A layout-mode switch; per-user theme colour | `04-frontend/` |
| [0405](04-frontend/0405-design-tokens-are-css-variables.md) | Design tokens are runtime CSS variables | Tokens as TS constants; hard-coded colours and spacing | `04-frontend/` |
| [0501](05-runtime/0501-no-network-inside-a-transaction.md) | No network call inside a transaction; the only exits are an outbox row and a job-queue row | Calls between `BEGIN` and `COMMIT`; best effort after commit; nested transactions | `05-runtime/` |
| [0502](05-runtime/0502-isolation-and-retry.md) | READ COMMITTED with an explicit ladder; retry only `40001` / `40P01` | A stricter global level; locks in request order; session-level settings or locks | `05-runtime/` |
| [0503](05-runtime/0503-deadlines-and-retry-budgets.md) | Every request has a shrinking deadline; retries decided by the contract, capped by a budget | Calls without deadlines; retrying non-idempotent methods; nested retry loops; circuit breakers | `05-runtime/` |
| [0504](05-runtime/0504-error-model-and-reason-catalogue.md) | One error object (problem details with AIP-193 members), identified by a reason from a catalogue | An `error` string field; leaking internal errors; reasons outside the catalogue | `05-runtime/` |
| [0505](05-runtime/0505-cloudevents-envelope-and-aggregate-cursor.md) | The envelope is CloudEvents in binary mode; one cursor per aggregate stream | `X-` headers; cursors keyed by subject; relying on broker order | `05-runtime/` |
| [0506](05-runtime/0506-at-least-once-delivery-and-streams.md) | At-least-once delivery through the outbox; one stream per first subject segment | Publishing without the outbox; assuming exactly-once; per-component streams | `05-runtime/` |
| [0507](05-runtime/0507-idempotency-keys-namespaced-by-caller.md) | Idempotency keys are namespaced by caller and bound to command, target and fingerprint | A shared key space; replays with a different body; lookups before authorization | `05-runtime/` |
| [0508](05-runtime/0508-background-work-only-through-jobs.md) | Background work runs only through the SDK's Jobs; an external trigger only of the run-once entry, after moving out of the shell is measured insufficient | Tickers and loops in module code; external schedulers | `05-runtime/` |
| [0509](05-runtime/0509-edge-only-routes.md) | The edge only routes; authentication and authorization stay in the services; routes are generated into deploy entries (`paths`, Traefik `labels`) | Hand-written routes; a bare `PathPrefix`; token checks only at the gateway (ForwardAuth, a JWT plugin); authorization, data scopes or business routing at the edge; routing gRPC or `/healthz`, `/metrics`, `/_be/info` | `05-runtime/` |
