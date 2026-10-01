[English](configuration.md) · [中文](configuration.zh.md)

# Configuration conventions

## Key names

A configuration key is an environment variable name: upper case, words joined by underscores. Component code reads it from its runtime config object, never from the process environment.

Never use these names; the platform reserves them and skips or rejects them:

- `COMPONENT_ID`, `COMPONENT_VERSION`, `PORT`, `BRICKKIT_SERVED_MEMBERS`, `BRICKKIT_SERVED_MEMBERS_CONFIG` (exact names)
- any name ending in `_ENDPOINT` (the platform injects dependency addresses under such names)

Keys owned by a single component are named `<domain noun>_<meaning>`, for example `DEFAULT_WAREHOUSE_ID`. Keys shared by several components use the names in the next section and are never renamed per component.

## Shared connection keys

Connection details are ordinary configuration items declared in each component's `configSchema`; the platform injects nothing on their behalf.

| Key | Meaning | Value comes from | Secret |
|---|---|---|---|
| `PG_HOST` | PostgreSQL host | `$var:PG_HOST` | no |
| `PG_PORT` | PostgreSQL port | `$var:PG_PORT` | no |
| `PG_DATABASE` | PostgreSQL database name | `$var:PG_DATABASE` | no |
| `PG_USER` | Login role of this component | literal, the `role` column of `registry/schemas.tsv` (`<schema>_rw`) | no |
| `PG_PASSWORD` | Password of that role | `${<REPO>_DB_PASSWORD}` | yes |
| `PG_SCHEMA` | Schema owned by this component | literal, copied from `registry/schemas.tsv` | no |
| `NATS_URL` | Event bus URL | `$var:NATS_URL` | no |
| `S3_URL` | Object storage URL (full URL) | `$var:S3_URL` | no |
| `OTEL_BASE_URL` | Telemetry collector base URL; empty disables export | `$var:OTEL_BASE_URL` | no |
| `AUTHZ_BUNDLE_URL` | Permission bundle address | `$var:AUTHZ_BUNDLE_URL` | no |
| `IAM_JWKS_URL` | Identity provider signing-key address | `$var:IAM_JWKS_URL` | no |

## Where values live

- `config/vars.yaml` holds values shared by several components, written once. A component refers to one as `$var:NAME`.
- `config/<scope>-<name>.yaml` holds one component's own values. When a component needs a value different from the shared one, it writes a literal there instead of `$var:`.
- The `vars:` section of a deploy file (`deploy.<env>.yaml`) overrides `config/vars.yaml` per environment or topology; it wins on conflict.
- Secrets are written only as `${NAME}`. The value lives in `.env` or in the process environment, never in a tracked file.

## Database roles

Every component has its own login role. `PG_USER` is the `role` column of `registry/schemas.tsv` (`<schema>_rw`, for example `erp_sales_rw`). `PG_PASSWORD` is `${<REPO>_DB_PASSWORD}`, where `<REPO>` is the repository name in upper snake case: `erp-sales` gives `PG_PASSWORD: ${ERP_SALES_DB_PASSWORD}`. `PG_SCHEMA` stays the schema name (`erp_sales`), copied from `registry/schemas.tsv`, never invented.

A shell logs in with its own role `shell_<name>` (for example `shell_go_core`, password `${SHELL_GO_CORE_PASSWORD}`) and, for each member, switches to that member's role with `SET LOCAL ROLE <member>_rw`. The switch is always transaction-scoped.

## Dependency addresses

Strong and weak dependency addresses are injected by brickKit as `<ID>_ENDPOINT`; code reads them through the runtime config's endpoint accessor.

The permission bundle and the identity key set are deliberately not dependency edges. Pinning an exact version on them would force every component to release whenever authz or iam releases. Their addresses are plain configuration: `$var:AUTHZ_BUNDLE_URL` and `$var:IAM_JWKS_URL`.

A shell service is named `<scope>-<name>-<version with dots as dashes>`, so `be/go-infra@1.0.0` is reached as `be-go-infra-1-0-0`. These values appear in `config/vars.yaml` and are overridden in the deploy file's `vars:` when the topology changes.
