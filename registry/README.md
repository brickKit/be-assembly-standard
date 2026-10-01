[English](README.md) · [中文](README.zh.md)

# Registries

The project-wide tables a component copies from before writing its `component.yaml` or `assembly.yaml`. A port, a schema, a role or a permission key is never invented: it comes from here, or a new row is appended here first. The full rules are in [docs/en/01-conventions/07-registries.md](../docs/en/01-conventions/07-registries.md); this page only says what each file is.

## Files

| File | Holds | Rule |
|---|---|---|
| `ports.tsv` | every component's HTTP and gRPC port, every shell's own port, every out-of-band container's host port | append-only |
| `schemas.tsv` | every component's PostgreSQL schema and login role | append-only |
| `permissions.tsv` | every permission key: `key`, `title`, `type`, `owner_component`, `deprecated` | append-only; merged in by `be-ops permissions` |
| `data-scopes.tsv` | every data-scope dimension: `component`, `dimension`, `column`, `mode`, `tables` | derived; regenerate at will |

## Rules

- **Append-only** (`ports.tsv`, `schemas.tsv`, `permissions.tsv`): a moved port breaks every dependent and every shell that hosts the component; a renamed schema is a data migration; a renamed permission key silently strips it from every role that had it. A key is retired by filling `deprecated`, and its name is never reused.
- **`_infra-` rows** are out-of-band containers (PostgreSQL, NATS, Traefik, Casdoor, object storage, observability), not components. They share the host port space with the components, so they are registered too; mutually exclusive pairs (RustFS / MinIO, Traefik / Nginx) may share a port.
- **`_shell-` rows** are the shells' own ports, the `/healthz` in each shell's `component.yaml` (`deployment.port`). Shell IDs are `be/<name>`. A member hosted by a shell keeps its own service name and its own ports.
- Port groups, the `1xxxx` range brickKit reserves and the `2xxxx` range for out-of-band host ports: [07-registries.md](../docs/en/01-conventions/07-registries.md#ports).
- After any change, `make registry-check`.
