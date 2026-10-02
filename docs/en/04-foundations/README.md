[English](README.md) · [中文](../../zh/04-foundations/README.md)

# Foundations

Why each piece underneath the components is what it is: the database, identifiers, time and money, transactions, events, calls, jobs, identity, authorization, telemetry, configuration, shells. One document per key choice. Each says what we chose, the contract that makes it replaceable, which other implementations exist, when we would switch, and exactly what a switch touches. The reader is whoever changes the SDKs, a shell, `infra/`, `tools/be-ops` or `tools/be-acceptance`, or proposes to replace one of these pieces.

## Reading order

| You are | Read |
|---|---|
| writing or changing a component | [the conventions](../01-conventions/README.md). They say how to use each piece; open a foundations document only when a convention links to one, or when you want to know why |
| changing an official SDK, a shell, the base resources in `infra/`, `be-ops` or `be-acceptance` | this README, then the document for the piece you are changing, then the decisions it lists |
| proposing "replace X", "add a cache / queue / engine", "support database Y" | the [port table](#ports) below, then that port's document: its **When to switch** and **How to switch** sections say whether the request is a configuration change, a new adapter, a new slot-family member, or out of scope |
| writing a component in a language other than Go, Python or TypeScript | [02-languages-and-component-protocol.md](02-languages-and-component-protocol.md), then the conventions |

A decision wins over a foundations document: when the two disagree, the decision is right until it is changed ([the decision index](../02-decisions/README.md)).

## How this folder divides the work

The same subject appears in three places, each answering a different question. Nothing is written twice.

| Folder | Holds | Does not hold |
|---|---|---|
| [`02-decisions/`](../02-decisions/README.md) | the conclusion in one sentence, two or three sentences of why, what it rules out, when to reopen it; it links to the foundations section with the full analysis | comparisons of options, port contracts, test lists |
| `04-foundations/` (this folder) | the choice, the port contract, the alternatives, why this one, why not the others, when and how to switch, the conformance tests; its **Decision records** section links the decisions it supports | the "rules out" list (it links the decision instead), coding rules for using an API (it links the convention instead) |
| [`01-conventions/`](../01-conventions/README.md) | how to use it: which API, how to write it, the mistakes to avoid | why it was chosen (it links here instead) |

## The eleven sections

Every foundations document except this README has exactly these `##` sections, in this order, in both languages. A fixed shape lets an AI jump straight to the part it needs, and lets `make docs-mirror` check the pair.

| No. | Section | Chinese heading | What goes in it |
|---|---|---|---|
| 1 | Scope | 范围 | the question the document answers, and what it leaves to which other document |
| 2 | Choice | 选择 | what we use, in a few lines, followed by a **Status** line: in place, decided (lands with the 3.0.0 component sweep), or later |
| 3 | Port contract | 端口契约 | the contract at the wire, database or protocol level: keys, URL schemes, table shapes, headers, message fields, status codes, error reasons. Never one language's API: a component may be written in any language |
| 4 | Alternatives | 备选方案 | the mainstream options, with honest strengths and weaknesses |
| 5 | Why this choice | 为什么选它 | the reasons that decided it |
| 6 | Why not the others | 为什么不选其他 | for each alternative, the concrete thing it lacks or breaks |
| 7 | When to switch | 什么时候换 | the observable trigger that would justify a switch |
| 8 | How to switch | 怎么换 | exactly what a switch touches: a configuration value, a pin, an adapter, a slot-family member. Never "rewrite the logic" |
| 9 | Conformance tests | 一致性测试 | the suite every implementation must pass, and the tests to write red first |
| 10 | Decision records | 相关决策 | the decisions this document supports (linked), and new or revised decisions planned (plain text, unlinked until they exist) |
| 11 | Known limits | 已知限制 | what the choice does not do, stated plainly, including a port that has only one adapter |

## Status words

| Word | Means |
|---|---|
| **In place** | running today in the released components and SDKs |
| **Decided** | the design is settled; the code lands with the 3.0.0 component sweep and the SDK release that accompanies it |
| **Later** | named and designed far enough to keep the contract open; built when the trigger in its **When to switch** section occurs |

## Files

| File | Answers | Document |
|---|---|---|
| `README.md` | this index, the port table, the section shape | written |
| [01-ports-and-adapters.md](01-ports-and-adapters.md) | what makes something a port; how an adapter is chosen; how conformance suites are laid out; how SDK and protocol versions move; how a single-adapter port is labelled | written |
| [02-languages-and-component-protocol.md](02-languages-and-component-protocol.md) | free language choice per component; the language-neutral component protocol and its black-box conformance suite; the official SDKs; a shell merges members of one language | written |
| [03-database.md](03-database.md) | the PostgreSQL dialect family, the version promise, compatible distributions, schema and role isolation, pools per member, pooler rules, role timeouts, entry points for HA and backup | written |
| [04-identifiers-and-numbering.md](04-identifiers-and-numbering.md) | UUIDv7 keys, references as text, partition keys derived from ids, cursors, document numbers including gap-free voucher numbers | written |
| [05-time-and-calendars.md](05-time-and-calendars.md) | instants and business dates, the legal entity's business time zone, UTC sessions, business dates in events, fiscal periods and years | written |
| [06-money-quantity-units.md](06-money-quantity-units.md) | money, price and rate columns, currency pairing, ISO 4217, rounding and allocation, cross-language vectors, units of measure | written |
| [07-tenancy.md](07-tenancy.md) | tenant = deployment, the legal-entity dimension, `tenant_id` and `aud`, noisy neighbours | written |
| [08-schema-evolution.md](08-schema-evolution.md) | migration tooling and guards, expand/contract, coexisting versions, backfills, forward-only | written |
| [09-data-lifecycle.md](09-data-lifecycle.md) | hot, warm, cold and destroyed data, legal hold, the cold store and cold query adapters, partition windows | written |
| [10-local-transactions.md](10-local-transactions.md) | isolation, timeouts, retries, lock order, advisory locks, no network inside a transaction | written |
| [11-consistency-across-components.md](11-consistency-across-components.md) | outbox and inbox, sagas, reconcilers, holds | written |
| [12-event-bus.md](12-event-bus.md) | the queue choice and the broker port: JetStream by default, a PostgreSQL queue adapter | written |
| [13-event-contracts.md](13-event-contracts.md) | the envelope (CloudEvents), naming, aggregate streams, schema evolution | written |
| [14-system-rpc.md](14-system-rpc.md) | the gRPC system plane between components | written |
| [15-user-api-and-errors.md](15-user-api-and-errors.md) | the REST user plane and the error model (AIP-193 mapping, the reason registry) | written |
| [16-deadlines-and-retries.md](16-deadlines-and-retries.md) | time budgets, retry budgets, bulkheads | written |
| [17-caching.md](17-caching.md) | caching, and why there is no Redis | written |
| [18-edge.md](18-edge.md) | the edge and the gateway | written |
| [19-background-jobs.md](19-background-jobs.md) | the jobs port and scheduling | written |
| [20-authorization-provider.md](20-authorization-provider.md) | the authorization provider contract, the resource contract, the slot family and its conformance suite | written |
| [21-identity-provider.md](21-identity-provider.md) | the IAM slot, token shape, JWKS, the platform-owned `sub`, directory events, the Keycloak member | written |
| [22-object-storage.md](22-object-storage.md) | the S3 port, a bucket per component, the blob client, attachments, presigned URLs, the cold store | written |
| [23-observability.md](23-observability.md) | propagation, per-member resources, metrics, log fields, audit versus application logs | written |
| [24-config-and-secrets.md](24-config-and-secrets.md) | the environment-variable configuration surface, brickKit's value forms, the secret port and rotation | written |
| [25-search.md](25-search.md) | the per-component `q` helper, the global search slot family | written |
| [26-i18n-data.md](26-i18n-data.md) | translatable master data, standard codes, the server-side language | written |
| [27-shells.md](27-shells.md) | merge safety: the checklist and the four shell invariants | written |

## Ports

A port is a contract at the infrastructure boundary with a conformance suite; the criteria are in [01-ports-and-adapters.md](01-ports-and-adapters.md#choice). Suites live under `tools/be-acceptance/conformance/<suite>/`. "Single-adapter port" means the value is one set of semantics and a suite, not the ability to swap.

| Port | What a component sees (wire level) | Default | Other implementations | Suite | Status | Document |
|---|---|---|---|---|---|---|
| Component protocol | configuration from environment variables, `/healthz`, token verification, event envelope, outbox and inbox tables, idempotency, data scopes, log and metric fields | be-sdk-go, be-sdk-python, be-sdk-ts (the official implementations) | an implementation in any language that passes the suite | `component` (black box, against a running container) | Decided | [02](02-languages-and-component-protocol.md) |
| Database engine | the PostgreSQL wire protocol and a capability list; the `PG_*` keys | PostgreSQL ≥ 14 (16 for NOINHERIT shell grants) | managed PostgreSQL; Citus 12+ for scale-out; KingbaseES and HighGo to be measured | `db` | PostgreSQL in place; suite decided | [03](03-database.md) |
| Store and local transactions | every transaction sets its role, `search_path` and timeouts locally; retries on serialization failure and deadlock | the SDK's PostgreSQL dialect layer | none: it follows the engine | `store` | Decided | [10](10-local-transactions.md) |
| Event bus | the outbox table, the event envelope, the scheme of the bus address | NATS JetStream | PostgreSQL queue (built in phase 06); Kafka (later) | `bus` | Decided (core NATS in place today) | [12](12-event-bus.md), [13](13-event-contracts.md) |
| Background jobs | job declarations; lease and slot tables in the component's own schema | native PostgreSQL tables | none, single-adapter port (River and DBOS are references, not adapters) | `jobs` | Decided | [19](19-background-jobs.md) |
| System RPC | gRPC between components, identity metadata, deadlines, `google.rpc.Status` with a reason | gRPC in each official SDK, connections reused | a connect-go server (wire compatible with gRPC) | `rpc` | gRPC in place; reuse and deadlines decided | [14](14-system-rpc.md), [16](16-deadlines-and-retries.md) |
| User API | REST, one permission key per route, RFC 9457 problem details carrying a reason | the locked HTTP stack of each language | none, single-adapter port | `userapi` | Decided | [15](15-user-api-and-errors.md) |
| Cache | nothing on the wire: in-process only | in-process LRU with TTL | none: there is no cache server | `cache` | Decided | [17](17-caching.md) |
| Edge | `edge_routes` in `assembly.yaml`, turned into routes by be-ops | Traefik file provider | Kubernetes Ingress or Gateway API, nginx | `edge` (golden route tables plus end-to-end) | Decided | [18](18-edge.md) |
| Telemetry | OTLP, W3C `traceparent`, `service.name` = the member's component ID | OTLP to an OpenTelemetry Collector | any OTLP backend, swapped in the collector | `telemetry` | export in place; propagation decided | [23](23-observability.md) |
| Object storage | the S3 API at `S3_URL`, one bucket and one credential per component | RustFS | MinIO, AWS S3, Alibaba Cloud OSS | `blob` | address in place; client decided | [22](22-object-storage.md) |
| Cold store | the format and manifest of frozen data in object storage | `s3-parquet` | `none` (explicit degradation); Iceberg (later) | `lifecycle` | Decided | [09](09-data-lifecycle.md) |
| Cold query | reading frozen rows back | `none` (answers a declared "range is cold" error) | `scan` (decided); Trino (later) | `lifecycle` | Decided | [09](09-data-lifecycle.md) |
| Secret source | how a secret value is read and re-read for rotation without restart | environment variable | a mounted file re-read on change; OpenBao (later) | `secret` | environment in place; file decided | [24](24-config-and-secrets.md) |
| Authorization provider (slot family) | the provider contract, the bundle under `AUTHZ_URL`, the resource-contract endpoints every component serves | `infra/authz` | `infra/authz-static`, `infra/authz-openfga` (both built in phase 06); Cedar or OPA (later) | `authz` | `infra/authz` in place; family decided | [20](20-authorization-provider.md) |
| Identity provider (slot family) | OIDC discovery, token exchange shaped like RFC 8693, JWKS at `IAM_JWKS_URL`, a platform-owned `sub`, directory events | `infra/iam-casdoor` | `infra/iam-keycloak` (second); a generic OIDC + SCIM member (third) | `iam` | Casdoor member in place; family decided | [21](21-identity-provider.md) |
| Global search (slot family) | a projection fed by events, filtered by the caller's access | none yet | `infra/search-*` members | `search` | Later | [25](25-search.md) |

Shared semantics are not a port and have no suite: every official SDK must produce the same result from the same JSON vectors. Protocol-wide vectors live in `vectors/` of the `brickKit/be-protocol` repository ([02](02-languages-and-component-protocol.md#repository-layout-of-be-protocol)), beside the protocol text, its schemas and the reference DDL of the platform tables. A slot family's vectors live in its family contract repository and are canonical there: authorization decisions in `vectors/decision/` of `contract-infra-authz` (`contracts/infra/authz`, locking its `EVALUATION.md`), tokens in `vectors/tokens/` of `contract-infra-iam` (`contracts/infra/iam`); be-protocol cites them by tag and never copies them. Suites and SDK unit tests read each set from a pinned tag.

| Vectors | Checks | Document |
|---|---|---|
| `money` | parsing, formatting, rounding, allocation, tax lines | [06](06-money-quantity-units.md) |
| `calendar` | instant plus time zone to business date | [05](05-time-and-calendars.md) |
| `numbering` | number formats and series scoping | [04](04-identifiers-and-numbering.md) |
| `errors` | problem bodies, code mapping, log levels, SQLSTATE mapping | [15](15-user-api-and-errors.md) |
| `envelope` | event envelope headers, names, ids, aggregate cursors | [13](13-event-contracts.md) |
| `idempotency` | key decisions and request fingerprints | [11](11-consistency-across-components.md) |
| `config` | configuration keys, value forms, endpoints | [24](24-config-and-secrets.md) |
| `redaction` | secret and personal-data redaction in logs | [23](23-observability.md) |
| `search` (proposed, not yet written) | `q` normalisation: folding, width, pinyin, initials, escaping, ranking | [25](25-search.md) |
| i18n fallback (proposed) | the language fallback chain over `name_i18n` | [26](26-i18n-data.md) |
| `decision` (in `contract-infra-authz`) | authorization decisions from a bundle, a token and a record's facts | [20](20-authorization-provider.md) |
| `tokens` (in `contract-infra-iam`) | access-token and subject-token verification | [21](21-identity-provider.md) |
