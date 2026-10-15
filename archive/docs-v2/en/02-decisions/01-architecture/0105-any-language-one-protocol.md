[English](0105-any-language-one-protocol.md) · [中文](../../../zh/02-decisions/01-architecture/0105-any-language-one-protocol.md)

# 0105 Any language, one protocol

**Status**: rewritten for 3.0.0 (the ban on Java and C# is lifted); decided, lands with the 3.0.0 sweep.

## Decision

A component may be written in any language. What makes it a member of the project is the language-neutral component protocol ([0109](0109-language-neutral-component-protocol.md)), not its language:

| A component in | Joins the project and runs standalone | Joins a shell |
|---|---|---|
| a language with an official SDK (Go, Python, TypeScript) | when its conformance report for the current version is green | when that SDK also has a shell launcher (Go and Python today; [0108](0108-one-repository-per-shell.md)) |
| any other language | when its conformance report for the current version is green | not until its language has an official SDK and a shell launcher |

A component in another language writes `protocol` and `language` in its `assembly.yaml`, chooses its stack and records it in its `AGENTS.md` ([0103](0103-locked-stack-per-language.md)), and is reviewed against the protocol's INTERNAL rules, because the source-scanning gates know only the official languages.

**A caveat, not a ban.** A JVM or CLR process keeps roughly 256–512 MiB resident and starts in seconds. A component in such a language says so in the "Before you deploy" section of its `BRICKKIT.md`, and raises its `healthCheck.startPeriodSeconds` and memory request to match.

## Why

Components are meant to be replaceable and to use the ecosystem that fits the requirement. A rule that lives in one language's SDK cannot be checked for a component written in another; a black-box suite run against the container holds every language to the same rules. The single-machine memory budget is real, but it is a deployment trade-off the customer should see, not a reason to forbid a language. A shell is one process with one runtime, so merging stays limited to languages with an SDK and a launcher; that limit costs only memory, never correctness.

## What this rules out

- Merging members of different languages into one process: a sidecar inside a shell, an embedded runtime, a Python member in a Go shell
- A component in any language without a green conformance report for its current version and image
- A special case for one component's language inside an official SDK
- A JVM or CLR component whose `BRICKKIT.md` is silent about its memory and start-up cost
- A second component in a new language before [0103](0103-locked-stack-per-language.md) has a column for it

## Revisit only if

The protocol cannot express a capability that a language's ecosystem requires, or too many rules that matter can only be held as INTERNAL rules that the suite cannot test.

Full analysis: [02-languages-and-component-protocol.md, Choice](../../04-foundations/02-languages-and-component-protocol.md#choice).
