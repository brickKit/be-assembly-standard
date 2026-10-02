[English](0109-language-neutral-component-protocol.md) · [中文](../../../zh/02-decisions/01-architecture/0109-language-neutral-component-protocol.md)

# 0109 The rules live in a language-neutral component protocol, checked by a black-box suite

**Status**: decided; lands with the 3.0.0 sweep (be-protocol v1.0.0, SDKs v0.6.0).

## Decision

Everything a component must do to be a proper member of this project is written once, at the wire, table and configuration-key level, as the **component protocol**: configuration, process lifecycle and health, token verification and permissions, data scopes, the system and user planes, the error model, deadlines, database identity and transactions, migrations, events with outbox and cursor, idempotency, background jobs, object storage, telemetry fields and the obligations of shell members.

| Piece | Home | What it holds |
|---|---|---|
| The protocol | its own repository, `brickKit/be-protocol`, versioned on its own from v1.0.0 | the specification text (English canonical, Chinese mirror), JSON Schemas, the reference DDL of the platform tables, semantic vectors, the fixture component's contracts; no code |
| The black-box suite | `tools/be-acceptance/conformance/component/` | cases run against a running container, whatever its language, with fake IdP, authz and peers and a real PostgreSQL and bus |
| The official SDKs | `be-sdk-go`, `be-sdk-python`, `be-sdk-ts` | reference implementations of the protocol with the same nouns in all three; each ships the fixture component `widget` and runs the suite on it |

- Each rule is **MUST** (the suite tests it), **SHOULD** (the suite warns) or **INTERNAL** (invisible from outside, such as "no network call inside a transaction"; the official SDKs hold it with their own tests, a component in another language says in its `AGENTS.md` how it holds it, and review checks).
- **A component's release needs a green report** for its exact version and image digest; `make gates` checks that the report exists.
- **No SDK behaviour the specification does not define.** A change goes specification and schema first, then vectors, then a suite case seen red against a broken fixture, then the three SDKs, then the tag.
- **A minor protocol version only adds optional surface**; a change that makes a conforming component non-conforming is a major.
- Infrastructure ports below the protocol (database, bus, jobs, cache, secrets, telemetry and the rest) each have a suite of their own under `tools/be-acceptance/conformance/<port>/`.

## Why

Components may be written in any language ([0105](0105-any-language-one-protocol.md)), so a rule that lives inside one SDK cannot be the rule. Testing a running container is the only check that applies equally to Go, Python, TypeScript and a language nobody has chosen yet. Three SDKs that pass the same suite with the same fixture are equivalent by evidence, not by intent; and the specification and its vectors share one version number, so an SDK cannot drift ahead of what is written.

## What this rules out

- A rule that exists only in an SDK's code or documentation; an SDK feature that the specification does not describe
- Releasing a component without a green report for its current version and image
- A per-language variant of a protocol rule (different header names, table shapes or error reasons in one SDK)
- Vectors or schemas copied into an SDK by hand instead of synchronised from a `be-protocol` tag
- A suite case written after the implementation and never seen failing

## Revisit only if

A rule that matters cannot be observed from outside and so stays INTERNAL in too many places to review reliably, or the cost of keeping three SDKs equivalent outweighs what free language choice gives the project.

Full analysis: [02-languages-and-component-protocol.md, Choice](../../04-foundations/02-languages-and-component-protocol.md#choice); the port criteria in [01-ports-and-adapters.md, Choice](../../04-foundations/01-ports-and-adapters.md#choice).
