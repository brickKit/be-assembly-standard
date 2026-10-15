[English](0101-no-imports-between-components.md) · [中文](../../../zh/02-decisions/01-architecture/0101-no-imports-between-components.md)

# 0101 Components never import each other

**Status**: revised for 3.0.0 (family contract packages added); decided, lands with the 3.0.0 sweep.

## Decision

A component's code never imports another component's code. Exactly three kinds of package may cross a component boundary as code:

| Kind | Example | What it may contain |
|---|---|---|
| an official SDK | `be-sdk-go`, `be-sdk-python`, `be-sdk-ts` | the runtime that implements the component protocol ([0109](0109-language-neutral-component-protocol.md)) |
| a component's published generated contract package | `gen/<domain>/<name>` | pure `protoc` output: message types and client stubs, no logic |
| a slot family's contract package | `contract-infra-authz`, `contract-infra-iam` | generated code and contract files only, no logic, no defaults |

Everything else goes over gRPC or HTTP through the contracts, also when both components are hosted in the same shell. The protocol's vectors and schemas, which the SDKs copy from `be-protocol`, are test data, not code, and do not count as a fourth kind.

## Why

Every component must start on its own, and a shell may only turn N processes into one. Once two components share code nothing breaks and nothing warns (the merged system even gets faster) until the day they have to run apart and can't; the cost then is a rewrite. Generated contract packages are imported, not copied, because two copies of the same generated code in one process register the same proto types twice and the process panics at start. A family contract belongs to no member: every member implements it and every consumer calls it, so it has to live in a package of its own with the same properties as the other two. `make gates` scans every component's imports.

## What this rules out

- "They're in the same shell anyway, just call the function directly": skipping gRPC between members of a shell
- A shared `models` / `common` / `utils` / `types` package that two components both import
- Importing another component's business, repository or service packages to reuse a helper
- Copying another component's `.proto` into your own repo to generate your own stubs (vendoring) instead of importing its `gen` package
- Importing one slot member's own `gen` package instead of the family contract package; a family contract package that carries logic or default behaviour
- Reading another component's tables to avoid an API call (see [0102](0102-one-schema-per-component.md))

## Revisit only if

Never for business code. A fourth shared category would need the same properties as the three above: no business logic, no component semantics, and safe to have exactly once per process.

Full analysis: [27-shells.md, Choice](../../04-foundations/27-shells.md#choice); family contracts in [20-authorization-provider.md, Choice](../../04-foundations/20-authorization-provider.md#choice).
