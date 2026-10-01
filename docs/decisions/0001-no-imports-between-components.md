[English](0001-no-imports-between-components.md) · [中文](0001-no-imports-between-components.zh.md)

# 0001 Components never import each other

## Decision

A component's code never imports another component's code. Exactly two kinds of package may cross a component boundary as code: the `be-sdk-*` libraries, and a component's published generated contract package (`gen/<domain>/<name>`: pure `protoc` output, message types and client stubs, no logic). Everything else goes over gRPC or HTTP through the contracts — also when both components are hosted in the same shell.

## Why

Every component must start on its own, and a shell may only turn N processes into one. Once two components share code nothing breaks and nothing warns — the merged system even gets faster — until the day they have to run apart and can't; the cost then is a rewrite. Generated contract packages are imported, not copied, because two copies of the same generated code in one process register the same proto types twice and the process panics at start. `make gates` scans every component's imports.

## What this rules out

- "They're in the same shell anyway, just call the function directly" — skipping gRPC between members of a shell
- A shared `models` / `common` / `utils` / `types` package that two components both import
- Importing another component's business, repository or service packages to reuse a helper
- Copying another component's `.proto` into your own repo to generate your own stubs (vendoring) instead of importing its `gen` package
- Reading another component's tables to avoid an API call (see [0002](0002-one-schema-per-component.md))

## Revisit only if

Never for business code. A third shared category would need the same properties as the two above: no business logic, no component semantics, and safe to have exactly once per process.
