[English](13-event-contracts.md) · [中文](../../zh/04-foundations/13-event-contracts.md)

# Event contracts

What an event is on the wire: the CloudEvents envelope in message headers, subject naming, the aggregate type and version every consumer's cursor relies on, the two consumption modes, the contract file and how it evolves, what the payload must and must not carry, and how large it may be. For whoever adds or changes an event, writes a consumer, or implements the envelope in a new language.

## Scope

- **In:** headers, subject names, aggregate type and version, state and sequence consumption, `contracts/events/*.json`, schema evolution, payload rules and size.
- **Out:** how events are stored and delivered ([12-event-bus.md](12-event-bus.md)); the outbox and the consumer cursor ([11-consistency-across-components.md](11-consistency-across-components.md)); field types shared with every other contract, such as money, dates and identifiers ([06-money-quantity-units.md](06-money-quantity-units.md), [05-time-and-calendars.md](05-time-and-calendars.md), [04-identifiers-and-numbering.md](04-identifiers-and-numbering.md)).

## Choice

- **CloudEvents 1.0 in binary mode:** the envelope is in message headers named `ce-*`, the payload is the business JSON object and nothing else. NATS, Kafka and the PostgreSQL queue all carry headers, so the envelope does not change with the broker.
- **Every event declares its aggregate type**, and every subject of that aggregate type carries one strictly increasing aggregate version.
- **State mode by default:** a consumer brings its projection to the aggregate's state at the received version and skips anything older. Sequence mode is reserved.
- **The registry is the contract file in each component**, `contracts/events/*.json`, checked by gates at build time. No runtime schema registry.
- **Schemas only grow**; a breaking change is a new subject version published beside the old one.

**Status**: decided; lands with the component protocol and the 3.0.0 sweep. Today the envelope travels in `X-` headers (`X-Aggregate-Id`, `X-Version`, `X-Trace-Id`, `X-Causation-Id`, `X-Hop-Count`), no producer fills the trace, causation or hop fields, and no event declares its aggregate type.

## Port contract

### Headers

| Header | Value | Filled by |
|---|---|---|
| `ce-specversion` | `1.0` | the runtime |
| `ce-id` | the event ID, a UUIDv7; also the broker's message ID for duplicate suppression | the runtime, when the outbox row is written |
| `ce-source` | the producing component's ID (`erp/sales`); in a shell, the member's ID | the runtime |
| `ce-type` | the subject (`sales.order.created.v1`) | the producer |
| `ce-time` | `occurred_at`, RFC 3339 in UTC | the runtime |
| `ce-subject` | the aggregate ID | the producer |
| `ce-dataschema` | `<component ID>@<version>/contracts/events/<file>#<subject>`: where the payload's schema is, as a reference, not a URL to fetch | the runtime |
| `content-type` | `application/json` | the runtime |
| `ce-aggregatetype` | the contract's `x-aggregate-type` (`erp.sales.order`) | the runtime, from the contract |
| `ce-aggregateversion` | the aggregate's version after this change, a decimal integer | the producer |
| `ce-causationid` | the `ce-id` of the event being handled when this one was produced; empty when it came from a request | the runtime, from the context |
| `ce-hopcount` | the causing event's hop count plus 1; 0 from a request. Above 10 the message goes to the dead letters | the runtime, from the context |
| `ce-legalentity` | the legal entity of a transaction document; required on the events whose contract entry says `x-transaction-document: true`, and a consumer dead-letters one without it | the runtime, from the payload |
| `ce-sequence` | reserved for sequence mode: a per-aggregate counter kept in the outbox, separate from the business version | not set yet |
| `ce-tenantid` | reserved: one deployment is one tenant, so it is not set | not set |
| `traceparent`, `tracestate` | W3C trace context of the producing span ([23-observability.md](23-observability.md)) | the runtime |

- Header names are lowercase. CloudEvents extension names are lowercase letters and digits only, which is why there are no underscores.
- **No older envelope is read.** Every producer and consumer moves to this envelope in the same 3.0.0 sweep, so a message with only `X-` headers or without `ce-id` is a contract violation and goes to the dead letters.
- Nothing else in the envelope: business data never goes in headers, and the envelope is never repeated inside the payload.

### Subjects

- `<domain>.<name>.<event…>.v<N>`: at least 4 segments, every segment matching `[a-z][a-z0-9]*(_[a-z0-9]+)*` (lowercase, starts with a letter, no leading, trailing or double underscore), the first segment a domain (it selects the stream, [12](12-event-bus.md#streams)), the last `v<N>`. Examples: `erp.inventory.adjusted.v1`, `infra.workflow.task.completed.v1`, `crm.opportunity.stage_changed.v1`.
- **The aggregate type is declared, never parsed out of the subject:** `infra.notification.dispatch.im.v1` cannot be split reliably.
- The older subjects `sales.*` and `finance.*` keep their names; contracts only grow, and each first segment simply has its own stream.
- A subject is published by one component, or by every member of one slot family (`integration.im.result.v1`). The one documented exception is `infra.authz.relation.sync.v1`, published by every component that owns a relation ([20-authorization-provider.md](20-authorization-provider.md)).

### Aggregate type and version

- Every subject of one aggregate type, from one producer, shares one strictly increasing `aggregate_version`. The business version of the row (incremented on every write) qualifies, since state mode tolerates gaps.
- An aggregate that only ever emits one event per instance (a credit decision about one order) declares an aggregate type of its own (`erp.finance.credit_decision`) rather than borrowing another's with a fixed version 1.
- The consumer cursor is keyed by `(consumer, aggregate_type, aggregate_id)` ([11](11-consistency-across-components.md#consumer-cursor)).

### Consumption modes

| Mode | The consumer receives | Handler rule | Status |
|---|---|---|---|
| `state` | possibly not every version, possibly late, never older than what it has | "bring my projection to the state at version v"; skipping older versions is correct | default |
| `sequence` | every version, in order | gaps are waited for: nak with delay, then a read-through or dead letter after a limit | reserved; built for its first real consumer |

### The contract file

Each component lists its events in `contracts/events/<name>.events.json`: an `envelope` description and an `events` array. Each event entry has:

| Key | Meaning |
|---|---|
| `subject` | as above |
| `x-aggregate-type` | the declared aggregate type (new; required) |
| `x-consumption` | `state` (default) or `sequence` (new) |
| `x-transaction-document` | `true` when the event is about a transaction document: the payload schema must require `legal_entity_id`, and the runtime sets `ce-legalentity` from it (new; default `false`) |
| `grade` | `core` (business-critical: persisted, deduplicated, may reach dead letters) or `peripheral` (informational side events) |
| `note` | who consumes it and why, in prose |
| `payload` | a JSON Schema (2020-12) object for the payload |

The file's schema is `schemas/events-contract.schema.json` in be-protocol (P12.2); no other key is allowed in an event entry.

Gates (part of `make gates`):

- additive only: deleting a field, changing a type or removing a subject fails (in place today);
- every event declares `x-aggregate-type` (planned);
- the subjects a component's code publishes are exactly those in its contract file (planned);
- the `events:` block of `component.yaml` agrees with the contract file and the fixtures (planned `events-declaration-scan`, below).

**Declared to brickKit.** brickKit 1.3 reads an optional `events:` block in `component.yaml` and uses it only to show the flow (`brickkit graph` draws publisher-to-subscriber edges, `brickkit deps` lists who publishes and who subscribes, `brickkit lint` notes a subscription nobody in the project publishes); it never affects start order, what runs or what is injected, and it never connects to the bus. brickKit treats an event name as an opaque string, so the subjects above need no change.

```yaml
# component.yaml (erp/finance)
events:
  publishes:
    - finance.voucher.posted.v1            # generated from contracts/events/*.json, exact names only
  subscribes:
    - sales.order.created.v1
    - infra.workflow.task.completed.v1     # exact subjects; a trailing * only for a real prefix subscription
```

- be-ops generates the whole block, together with the protocol block of `configSchema` (be-protocol P12.16): `publishes` from the contract file, exactly its subjects (a slot-family member: the family's subjects); `subscribes` from `events.consumes` in the component's `conformance/fixtures.yaml`, every subject it consumes through a durable. Best-effort pokes ([12](12-event-bus.md#best-effort-signals)) are not listed.
- A subscription is an exact subject. brickKit's trailing-`*` prefix form is allowed only in `subscribes`, and only for a consumer that really subscribes by prefix; NATS `>` and a `*` in the middle of a name are never written.
- The gate `events-declaration-scan` compares the block with the contract and the fixtures; the component suite compares it with what the component really publishes and the durables it creates at start ([12](12-event-bus.md#durable-consumers)).
- Several members of one slot family publishing the same subject (`integration.im.result.v1`) is fine: brickKit matches by name, not by publisher.

### Payload rules

- A JSON object. Unknown fields are ignored by consumers, a missing optional field takes its default: consumers read leniently.
- **Field formats:** money and quantities as decimal strings paired with their currency or unit ([0301](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md), [06](06-money-quantity-units.md)); identifiers as strings ([04](04-identifiers-and-numbering.md)); instants in RFC 3339 UTC; business dates as `YYYY-MM-DD`.
- **Every transactional event carries `legal_entity_id`**, and the business dates its consumers need (`document_date`, `posting_date`). A consumer books by those dates, never by the time it processes the event ([05-time-and-calendars.md](05-time-and-calendars.md)).
- **Enough state for state mode:** an event carries what a consumer needs to reach the aggregate's state at that version, not just the name of the change.
- **Events are system data.** A payload is never shown to a person as it is: a notification built from an event is masked for its recipient or carries only a link, because a field such as a price may be hidden from that recipient ([20-authorization-provider.md](20-authorization-provider.md)).
- **No secrets, no tokens, as little personal data as the consumers need.**
- **Size:** up to 64 KiB is normal. The protocol's hard limit is 1 MiB, enforced at publish with a clear error (be-protocol P12.2); the broker's own limit is 8 MB including headers.
- **Larger than 64 KiB: claim check** ([22-object-storage.md](22-object-storage.md#large-results)). The producer writes the content as an object in its own bucket; the payload carries `{key, sha256, size}` of that object, never the bytes; the producer offers an rpc that returns a short-lived URL for that key. A consumer calls the rpc, downloads, and checks `size` and `sha256`; it never holds the producer's bucket credentials.

### Evolution

- Adding a field or a new subject is always allowed. A field is never removed, renamed, retyped or given a new meaning ([0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)).
- A breaking change is a new subject `….v2`. The producer writes both `v1` and `v2` outbox rows in the same transaction until no consumer reads `v1`; then a person decides to stop `v1`. The version lives in the subject, never in a header.

## Alternatives

| Approach | Strengths | Weaknesses |
|---|---|---|
| **CloudEvents binary mode plus JSON payload, contract files checked at build** (chosen) | broker-neutral header names with standard bindings for NATS and Kafka; payload readable in any tool and any language; no runtime service | schema checks happen at build, not on the wire |
| CloudEvents structured mode (envelope inside the JSON body) | one blob, no headers needed | every consumer parses the envelope out of the body; the payload is no longer the pure business object |
| Our own `X-` headers (today) | already in place | names tied to no standard; meaningless on another broker |
| Avro or Protobuf payloads plus a runtime schema registry (Confluent) | compact; compatibility enforced on publish | another service to run; binary payloads unreadable when debugging; a registry client in every language |
| AsyncAPI documents as the contract format | a standard description, tooling for documentation | describes channels rather than our aggregate rules; can be generated from our files later |
| Event sourcing (events as the system of record) | full history, replay of any state | every component rebuilt around event stores; our state lives on business rows ([11](11-consistency-across-components.md)) |

## Why this choice

- **The envelope must survive a change of broker** ([12](12-event-bus.md)); CloudEvents names are the neutral choice and have published bindings for the brokers we name.
- **JSON payloads** are readable by people, by AI and by every language without generated code, and the money, date and identifier rules are the same as in every other contract.
- **Declaring the aggregate type** is what makes a cursor per aggregate stream possible, and with it correct handling of events that arrive out of order across subjects.
- **Build-time checks** in each component's repository keep the registry where the code is, with no service to run.

## Why not the others

- **Structured mode** mixes transport data into the business object and makes every consumer parse it out.
- **`X-` headers** cannot be carried meaningfully to Kafka or a PostgreSQL queue.
- **Avro/Protobuf with a registry** adds a resident service and binary payloads for a size gain we do not need at our volumes.
- **AsyncAPI** would be a second description of the same thing; it can be generated from the contract files when an external party subscribes.
- **Event sourcing** would rewrite every component's persistence for benefits we get from the outbox and business rows.

## When to switch

- **An external party subscribes to events** (the external API on the roadmap): generate AsyncAPI from the contract files; nothing on the wire changes.
- **The first consumer that needs every change in order** appears: build sequence mode (`ce-sequence`, gap handling) for it.
- **Measured payload cost matters** (unlikely at ERP volumes): a binary payload is a new subject version with a different `content-type`.

## How to switch

- Header names are fixed by the protocol and do not switch.
- A payload format or schema change is a new subject version (`.v2`) published beside the old one; consumers move one at a time; no flag day.
- Sequence mode is added per event by declaring `x-consumption: sequence` once the mode exists; state-mode consumers of the same subject are unaffected.

## Conformance tests

Planned, in `tools/be-acceptance/conformance/bus/` (envelope cases run on every adapter) and in the component protocol suite:

- the full header set round-trips unchanged on every adapter;
- a message with only `X-` headers, or without `ce-id`, goes to the dead letters;
- publishing inside a handler sets `ce-causationid` to the handled event's ID and increments `ce-hopcount`; a hop count above 10 goes to the dead letters;
- the aggregate version is strictly increasing across all subjects of one aggregate type in a producer's outbox;
- gates: an event without `x-aggregate-type` fails; a subject that does not match the segment pattern fails; a removed field fails; a subject published in code but missing from the contract fails;
- **one property test per consumer** ([06-testing.md](../01-conventions/06-testing.md#l2-business-rule-tests)): shuffled and duplicated deliveries end in the same state as one in-order delivery.

## Decision records

- [0505 CloudEvents envelope; one cursor per aggregate stream](../02-decisions/05-runtime/0505-cloudevents-envelope-and-aggregate-cursor.md): this document is its full analysis.
- [0301 Money is a decimal string paired with a currency; lists page by cursor](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md): money in payloads.
- [0302 Contracts change by adding only](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md): event schemas and subjects.
- [0308 A tenant is a deployment](../02-decisions/03-contracts-and-data/0308-tenant-is-the-deployment.md): one deployment is one tenant, so `ce-tenantid` stays unset.

## Known limits

- **No ordering guarantee**: state mode tolerates it; strict order waits for sequence mode.
- **`ce-dataschema` is a reference**, not a fetchable URL: there is no registry service to resolve it.
- **Headers count against the broker's size limit.**
- **The older first segments** (`sales`, `finance`) stay inconsistent with `erp.inventory.*`; that is the price of additive-only contracts.
- **`ce-tenantid` is reserved, not used:** a pooled multi-tenant deployment would need it first.
