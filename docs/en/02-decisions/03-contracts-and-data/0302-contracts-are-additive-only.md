[English](0302-contracts-are-additive-only.md) · [中文](../../../zh/02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)

# 0302 Contracts change by adding only

**Status**: revised for 3.0.0 (external REST versioning, reason catalogues); decided, lands with the 3.0.0 sweep.

## Decision

Published contracts (`.proto`, OpenAPI, `contracts/events/*.json`, `contracts/errors.yaml`) only grow: new fields, new RPCs, new endpoints, new event subjects, new error reasons. A field is never deleted, renamed, retyped or renumbered, a subject or a reason is never removed or reused, and a field never changes meaning. A new field must be optional for the logic of existing consumers. `make contract-check` in each component (proto, OpenAPI) and `make gates` in this project (events) fail on a breaking change.

**A breaking change** is decided by a person and published beside the old contract, never in its place:

| Contract | New major |
|---|---|
| REST | a new path prefix `/<domain>/<name>/v2/…` served beside the old one; the old operations answer with `Deprecation` and `Sunset` headers and are removed only after the sunset date |
| gRPC | a new versioned package `<domain>.<name>.v2` beside `v1` |
| events | a new subject version (`….v2`) published beside the old one |

The same rules are the published promise to external callers once the external API opens.

## Why

Consumers, including customer forks and, later, other systems of the customer, keep running against older versions and ignore fields they do not know. A breaking change forces every consumer to change and release in lockstep, and an event consumer that misses it fails at runtime, not at build time. A path prefix with `Deprecation` and `Sunset` lets an external caller see the change coming and move in its own time.

## What this rules out

- "Rename this field", "change its type to int", "reuse this tag number"
- "Remove the deprecated field / RPC / subject / reason"
- Making an existing optional field required
- Changing what an existing field means or its unit while keeping its name
- A breaking REST change behind a header or a query parameter instead of a new path prefix; removing an old operation before its `Sunset` date

## Revisit only if

Never in place. A contract that is wrong beyond repair gets a new major beside the old one, as above. The one-time 3.0.0 rebuild ([0305](0305-one-shot-baseline-rebuild-for-3-0-0.md)) is the only exception, and it names every surface it breaks.

Full analysis: [15-user-api-and-errors.md, Versioning](../../04-foundations/15-user-api-and-errors.md#versioning); events in [13-event-contracts.md, Evolution](../../04-foundations/13-event-contracts.md#evolution).
