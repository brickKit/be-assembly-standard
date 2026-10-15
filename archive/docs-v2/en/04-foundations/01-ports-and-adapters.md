[English](01-ports-and-adapters.md) · [中文](../../zh/04-foundations/01-ports-and-adapters.md)

# Ports and adapters

What makes a piece of infrastructure a port, how the implementation behind it is chosen, how its conformance suite is organised, how the SDKs and their contracts are versioned, and how a port with only one implementation is labelled honestly. Read it before adding a port, an adapter or a suite, or before arguing that something should or should not be replaceable.

## Scope

This document holds the rules shared by every port. Each port's own contract, alternatives and switch procedure are in its own document; the list is the [port table](README.md#ports). Slot families as an assembly concept (one component per variant, chosen when the project is assembled) are decided in [0104](../02-decisions/01-architecture/0104-variants-become-slot-families.md); this document covers how such a family is proved replaceable. The language-neutral component protocol, which every component implements whatever its language, is the subject of [02-languages-and-component-protocol.md](02-languages-and-component-protocol.md); here it appears only as one more contract with a suite.

## Choice

Hexagonal ports and adapters, at the infrastructure boundary only. Business logic (an order's state machine, a compensation order) is never a port: when it is wrong it is rewritten. Infrastructure and cross-component mechanisms are designed once, behind a contract and a conformance suite.

Something is a port when all three hold:

1. It is infrastructure or a mechanism shared across components, not business.
2. Mainstream platforms really implement it in more than one reasonable way, and a second implementation can be **named today**.
3. Switching implementations changes no component code: only an adapter inside the SDK, a slot-family member, or project configuration.

This is the same test as "no abstraction without a second implementation" in [09-ai-development.md](../01-conventions/09-ai-development.md#when-to-use-a-design-pattern), applied to infrastructure: the second implementation is named, so the abstraction pays.

An implementation behind a port is one of three kinds:

| Kind | Where it lives | Chosen by | Examples |
|---|---|---|---|
| **SDK adapter** | compiled into every official SDK, registered by URL scheme or by a config value | a shared configuration value | event bus, secret source, cold store |
| **Slot-family member** | a component of its own, all members with one contract | which member the project installs (`brickkit add` / `remove`) plus shared address keys filled with `$endpoint:<member>` | authorization provider, identity provider, global search |
| **Product behind a standard protocol** | no code of ours: an official image behind the PostgreSQL wire protocol, the S3 API or OTLP | the address in shared configuration | database engine, object storage, telemetry backend |

Every port has four things: a contract at the wire level, a default implementation, named alternatives, and a suite under `tools/be-acceptance/conformance/<suite>/`.

**Status**: the criteria and the suite layout are decided. Most suites are decided but not written; the port table records each one's state.

## Port contract

What every port's document must specify in its own **Port contract** section, and the rules every adapter follows.

**A port contract is written at the wire level.** Components may be written in any language that passes the component protocol suite, so a contract is never one SDK's function signatures. It names:

- the configuration keys and, where the adapter is picked by address, the URL schemes (`nats://…`, `postgres://…`);
- the wire formats: table shapes, headers or metadata keys, message fields, status codes, error reasons;
- the capability list, and for every optional capability what an adapter without it does: a declared error or a documented fallback, chosen per capability and never silent;
- the observable signals an operator relies on (metric and log field names), when they are part of the contract.

**How an adapter is chosen at runtime.** The scheme of a shared address key decides, for example `nats://…` or `postgres://…?schema=…` for the event bus (the key itself is defined in [12-event-bus.md](12-event-bus.md)). When the key is absent the SDK falls back to the older key the port replaced. A component never imports or names an adapter; adapters are compiled into each official SDK and registered by scheme. In a shell there is one adapter instance per process and one handle per member ([27-shells.md](27-shells.md)).

**An adapter that lacks a capability fails loudly.** It refuses to start, naming the capability, when the capability is required; when it is optional it answers the error the contract declares for it. A silent no-op is a bug: the symptom is a feature that "works" in tests against the default adapter and quietly does nothing in production.

**A slot-family contract lives in its own repository**, never in a member's: `contract-infra-authz`, `contract-infra-iam`. Members depend on the contract, never on each other, and no component depends on a member ([0104](../02-decisions/01-architecture/0104-variants-become-slot-families.md)).

**A slot family is addressed through brickKit's `$endpoint:`, never through a dependency.** Each consumer declares the family's address keys in its `configSchema` (`AUTHZ_URL`, `AUTHZ_GRPC_URL`); the project fills them once in `config/vars.yaml` with a reference naming the installed member (`$endpoint:infra/authz`, `$endpoint:infra/authz:grpc`). The consumer's manifest never names a member, so swapping the member touches no component; brickKit still knows the edge (start-along, focus runs, `networkPolicy`, `graph`) without imposing a start order. A missing member leaves an optional key absent, and the consumer degrades ([0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)).

### Versions

- **Wire contracts change by adding only**, the same rule as [0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md): a header, field, table column, reason or scheme once released is never renamed, retyped or reused. A field that must change meaning becomes a new field.
- **The official SDKs release a contract change together, at the same version number.** "SDK vX.Y" means the same wire behaviour in Go, Python and TypeScript, so a project can mix languages without a compatibility table.
- **Within one major version an SDK is backward compatible for module code.** A shell builds all its members against one SDK version, and every component and shell of one language pins that same version (planned gate `sdk-version-scan`), so an SDK minor that breaks a module's code breaks every shell hosting it. An API is deprecated in one minor and removed only in a later one, once no component in the project still uses it; building every shell proves that.
- **Platform tables the SDK creates in each component's schema** (outbox, inbox, job leases, number series) evolve by expand and contract, because a member standalone and the same member in a shell may run different SDK versions against the same schema for a while. Platform SQL names its columns and never selects `*`.
- **A suite is versioned with `be-acceptance`.** An SDK's release notes name the suite version it passes.
- **The component protocol is versioned in its own repository**, `brickKit/be-protocol` (checked out at `tools/be-protocol`): the specification text, schemas, the reference DDL of the platform tables, the semantic vectors and the fixture contracts, starting at v1.0.0. A minor version only adds optional surface; a behaviour that becomes required needs a major. `be-acceptance` and the official SDKs pin one protocol version.

## Alternatives

| Approach | Strengths | Weaknesses |
|---|---|---|
| **Ports with conformance suites** (hexagonal; contract first, then a black-box suite every implementation runs) | replaceability becomes a test result; the contract is language-neutral; one place per port | a suite to write and keep green for each adapter |
| No abstraction: one implementation, used directly | least code; nothing to keep in step | a later switch rewrites every component; the second implementation is never proved possible |
| A generic multi-backend abstraction (ORM dialects, a portable messaging API) | many backends "for free" | the common denominator hides each backend's guarantees; leaks at the edges; an ORM is ruled out by [0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md) |
| A sidecar runtime (Dapr building blocks) | swapping a backend is a YAML change; polyglot by design | one more process per component and per call hop; its own component model beside brickKit's; a shell can no longer be one process |
| Configuration switches inside one implementation | no extra components | every customer's variant in one codebase; ruled out by [0104](../02-decisions/01-architecture/0104-variants-become-slot-families.md) |

## Why this choice

- **Infrastructure has to be right once; business logic may be rewritten.** That asymmetry is why ports exist only below the business layer.
- **A suite is what makes "replaceable" true.** Without one, a second implementation is a claim; with one, it is a test run in CI against every adapter.
- **Components may be written in any language**, so the contract has to live on the wire. An SDK is one implementation of it, not the definition.
- **It is AI-friendly.** One document, one contract and one suite per port: an AI changing the event bus reads three things, not every component.

## Why not the others

- **No abstraction** fails our own criterion: for every port in the table a second implementation is named and wanted (a PostgreSQL queue for small installs, Keycloak for customers who already run it).
- **A generic abstraction layer** gives up exactly the guarantees the components rely on: transaction-scoped role switching, `SKIP LOCKED`, JetStream's acknowledgement semantics. And an ORM is excluded by 0103.
- **Dapr** turns every call into two hops, adds a process per component, and cannot be merged into a shell. It also duplicates what brickKit already does at assembly time.
- **Configuration switches** are the pattern 0104 rejects: one codebase holding every customer's variant.

## When to switch

These are the triggers for changing the set of ports, not the implementation behind one (each port's own document has those):

- **Promote to a port** when a second implementation becomes nameable and a customer or a test setup needs it. Write the contract and the suite first, then the second adapter.
- **Demote a port** when its alternatives converge in practice on one implementation and nobody needs another ([0104](../02-decisions/01-architecture/0104-variants-become-slot-families.md), "Revisit only if"). The suite stays as a regression test; the label becomes "single-adapter port".
- **Turn an SDK adapter into a slot family** when the implementation needs its own process, its own release cycle or its own database, as the authorization provider does.

## How to switch

Switching the implementation behind any port:

1. Read the port's **How to switch** section: it says whether the switch is a configuration value, a slot-family member or an infrastructure product.
2. Run the port's suite against the target. A red suite stops the switch.
3. Change the shared value once in `config/vars.yaml` (or the `vars:` of a deploy file for one environment). For a slot family, swap the member with `brickkit remove` / `brickkit add` and change the member ID in the family's `$endpoint:` references, one line per key (`AUTHZ_URL: $endpoint:infra/authz-static`); brickKit computes the address, follows the member's version and shell, and opens `networkPolicy` ([0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)).
4. Component code is not touched. If it would have to be, the port's contract is incomplete: fix the contract, not the components.

Adding a new adapter:

1. Write it in every official SDK, or state in the port table which languages have it. An adapter missing from Python leaves Python components on the default.
2. Register its scheme or config value; add it to the suite's CI matrix.
3. See the suite go red against a deliberately broken fake adapter before trusting its green.
4. Add it to the port's document (**Alternatives**, **How to switch**) and to the port table.

## Conformance tests

Layout: `tools/be-acceptance/conformance/<suite>/`, one folder per port, named by its short port name (`db`, `store`, `bus`, `jobs`, `rpc`, `userapi`, `authz`, `iam`, …); the component protocol suite is `conformance/component/`. The informal names `dbconf`, `authzconf`, `iamconf` and `compconf` mean `conformance/db`, `conformance/authz`, `conformance/iam` and `conformance/component`. Shared semantic vectors (money, time, numbering, request fingerprints, …) are not a suite: they live in `vectors/` of the `brickKit/be-protocol` repository, and the suites and each SDK's unit tests read them from there.

Each suite has up to three layers:

| Layer | What | Runs against |
|---|---|---|
| **Vectors** | JSON golden cases from be-protocol's `vectors/`: inputs and the expected result. Every official SDK reads the same files and must produce identical results | each SDK's own test runner |
| **Adapter black box** | real infrastructure for each adapter, the same cases for every adapter | a disposable instance (`testcontainers`) or the one `make up` starts |
| **Component black box** | a running container, through its public ports only; language-blind | the image `brickkit build` produced |

Rules:

- An adapter that does not declare a capability is tested for its declared error or fallback. A suite that skips it is broken.
- A new suite is seen red once, against a broken fake, before its green counts ([06-testing.md](../01-conventions/06-testing.md#red-green-and-the-iron-rule)).
- A suite that finds nothing to test fails; it never skips quietly. A silent skip reads as green for months while verifying nothing.
- The component protocol suite (`conformance/component`) is the gate for a component in a new language: passing it is what lets the component join the project and run standalone.

## Decision records

- [0104 A slot family needs several reasonable implementations and no dependency edge](../02-decisions/01-architecture/0104-variants-become-slot-families.md): when a variant becomes a slot family, with one family contract and one suite per family; this document adds how a family is proved replaceable.
- [0109 The rules live in a language-neutral component protocol](../02-decisions/01-architecture/0109-language-neutral-component-protocol.md): the component protocol and its black-box suite; the per-port suites under `tools/be-acceptance/conformance/<port>/` follow this document's criteria and layout.
- [0106 Infrastructure is not a component](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md): the event bus is swapped through an SDK adapter chosen by URL scheme, which is more than a setting and less than a migration.
- [0103 One locked stack inside each language](../02-decisions/01-architecture/0103-locked-stack-per-language.md): one locked stack inside each language, which is the official SDK's own.
- [0105 Any language, one protocol](../02-decisions/01-architecture/0105-any-language-one-protocol.md): any language whose implementation passes the component protocol suite may join; the memory cost of a JVM is a documented caveat.

## Known limits

- **Single-adapter ports are labelled as such**: background jobs, the user API, the cache. Their value is one set of semantics and a suite, not swapping. A document that implies otherwise is wrong.
- **Replaceable within a family only.** The database port is the PostgreSQL dialect family; leaving it means porting each component's repository layer ([03-database.md](03-database.md#known-limits)).
- **An adapter exists per language.** Until an adapter is written in every official SDK, components in the missing language stay on the default.
- **A shell merges members of one language only**, and only languages that have an official SDK and a shell launcher. A component in another language runs standalone.
- **Most suites are not written yet**; until a suite exists, the alternatives in that port's table are designed for, not proved.
