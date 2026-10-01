[English](registries.md) · [中文](registries.zh.md)

# Registries

`registry/` holds the project-wide tables a component copies from before writing its `component.yaml` or `assembly.yaml`. A port, a schema, a role or a permission key is never invented: it comes from here, or a new row is appended here first.

## The tables

| File | Holds | Rule |
|---|---|---|
| `registry/ports.tsv` | every component's HTTP and gRPC port, every shell's own port, every out-of-band container's host port | append-only |
| `registry/schemas.tsv` | every component's PostgreSQL schema and role | append-only |
| `registry/permissions.tsv` | every permission key: `key`, `title`, `type`, `owner_component`, `deprecated` | append-only; aggregated by be-ops |
| `registry/data-scopes.tsv` | every data-scope dimension: `component`, `dimension`, `column`, `mode`, `tables` | derived; regenerate at will |

The component → repository map is `.gitmodules`: each component is a Git submodule under `components/<scope>/<name>/`, and this repository records the exact commit of each.

## Append-only

`ports.tsv`, `schemas.tsv` and `permissions.tsv` only ever get new rows.

- **A port can't be moved once a dependent exists.** Every dependent reaches the component at the port it declares; members of one shell share one network namespace, so two members on the same port collide in one process. A changed port is a change in every dependent and every shell that might host it.
- **A schema can't be renamed once data is in it**: that is a data migration.
- **A permission key can't be renamed once released.** Every role granted the old key silently loses it, with no error; the symptom is users who suddenly can't use a button after an upgrade. A key is retired by filling its `deprecated` column, and its name is never reused.
- After any change, `make registry-check`.

## Ports

**Allocation**: ports are always copied from `ports.tsv`, never computed. They come in groups; inside a group the n-th component gets the group's HTTP base + n and the group's gRPC base + n, with the bases shown below (8080 ↔ 9090, 8100 ↔ 9100, 8200 ↔ 9200, 8300 ↔ 9300, 8400 ↔ 9400). The `shell` column of `ports.tsv` names the group.

| Group | HTTP | gRPC |
|---|---|---|
| Go core transactions and master data | 8080–8087 | 9090–9097 |
| Go back-office | 8100–8115 | 9100–9115 |
| Go infrastructure and integrations | 8200–8223 | 9200–9223 |
| Python domain engines | 8300–8307 | 9300–9307 |
| Python rendering and EDI | 8400–8401 | 9400–9401 |
| Standalone (BFF) | 8500 | — |
| Frontends | 80 | — |

- Rows starting with `_shell-` are the shells' own ports (their health check), not any member's.
- Rows starting with `_infra-` are out-of-band containers (PostgreSQL, NATS, Traefik, Casdoor, object storage, observability), not components. They live in the same host port space as the components, so they are registered too.
- **Shared ports, the only exceptions**: the frontend slot family shares 80 (only one is ever installed); mutually exclusive out-of-band pairs share a port (RustFS / MinIO on 9000, Traefik / Nginx on 80). `make registry-check` allows exactly these.
- Every port is unique across all components, including slot members that never run together and blueprints that aren't built yet: a reserved row costs nothing, a collision found late costs every dependent.
- **The `1xxxx` range belongs to brickKit.** For `mode: debug` and `mode: local`, brickKit maps container ports to the host at `10000 + port` (5432 → 15432, 8080 → 18080) and falls back to counting up from `18080`. Never allocate a `1xxxx` port. Out-of-band containers keep their default ports where those collide with nothing (PostgreSQL 5432, NATS 4222, Casdoor 8000); a default or `exposePort` host port that would collide with a component port or the `1xxxx` range moves to `2xxxx` (Traefik dashboard 28080, Keycloak 28081, Prometheus 29090, Kafka 29092, the frontend 28090, the BFF 28500). All of them are recorded in `ports.tsv`.

## Schemas and roles

| Object | Rule | Example |
|---|---|---|
| Databases | `brickkit_db` for the running project, `brickkit_test_db` for tests | — |
| Component schema | repository name with `-` → `_` | `mdm-customer` → `mdm_customer` |
| Archive schema | `<schema>_archive` | `mdm_customer_archive` |
| Component role | `<schema>_rw`, a login role, password `${<REPO>_DB_PASSWORD}` | `mdm_customer_rw`, `${MDM_CUSTOMER_DB_PASSWORD}` |
| Shell login role | `shell_<name>`, a member of each hosted component's role | `shell_go_core` |

- brickKit never creates a database, schema or role. `make db-init` runs the script be-ops generates from these tables and the shells' member lists (`CREATE SCHEMA`, roles, grants); it is idempotent. `make test-db-init` does the same for the test database.
- How the role and password reach the component: [configuration.md](configuration.md#database-roles).
- Every shell member has a row in `schemas.tsv`; be-ops refuses a shell whose member has none.
- No schema: `infra/bff-mobile` (never connects to the database), the frontends, and blueprints not being built. Non-component schemas: `casdoor` (the Casdoor image's own), `keycloak` (when that slot member is used).

## Permission keys

- A key is `<domain>.<aggregate>.<action>`; its prefix equals the owning component's domain, and keys are unique across the project. Declaring and registering keys in code: [backend.md](backend.md#permissions).
- `be-ops permissions --root .` reads every component's `assembly.yaml` and merges new keys into `permissions.tsv`. It only adds: a key no component declares any more (and not marked `deprecated`) prints a warning and stays; retiring it is a manual tombstone in the `deprecated` column.
- After adding keys, refresh the permission catalog infra/authz is configured with. A key missing there never reaches the permission list, and every check on it fails.
- `data-scopes.tsv` is produced the same way from the `data_scopes` sections. It exists so that a customer security review or a delivery acceptance reads one table instead of every component.
