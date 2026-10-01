[English](0016-contracts-are-additive-only.md) · [中文](../../../zh/02-decisions/03-contracts-and-data/0016-contracts-are-additive-only.md)

# 0016 Contracts change by adding only

## Decision

Published contracts — `.proto`, OpenAPI and `events/*.json` — only grow: new fields, new RPCs, new endpoints, new event subjects. A field is never deleted, renamed, retyped or renumbered, a subject is never removed, and a field never changes meaning. A new field must be optional for the logic of existing consumers. `make contract-check` in each component (proto) and `make gates` in this project (events) fail on a breaking change.

## Why

Consumers, including customer forks, keep running against older versions and ignore fields they do not know. A breaking change forces every consumer to change and release in lockstep, and an event consumer that misses it fails at runtime, not at build time.

## What this rules out

- "Rename this field", "change its type to int", "reuse this tag number"
- "Remove the deprecated field / RPC / subject"
- Making an existing optional field required
- Changing what an existing field means or its unit while keeping its name

## Revisit only if

A contract is wrong beyond repair. Then a person decides on a major version: a new versioned package or subject is published next to the old one, consumers move over, and the old one is retired later — the old contract is never changed in place.
