[English](0505-cloudevents-envelope-and-aggregate-cursor.md) · [中文](../../../zh/02-decisions/05-runtime/0505-cloudevents-envelope-and-aggregate-cursor.md)

# 0505 The envelope is CloudEvents in binary mode; consumers keep one cursor per aggregate stream

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

- **The envelope is CloudEvents 1.0 in binary mode**: message headers named `ce-*` (`ce-id` a UUIDv7, `ce-source`, `ce-type` = the subject, `ce-time`, `ce-subject` = the aggregate ID, `ce-dataschema`, `ce-aggregatetype`, `ce-aggregateversion`, `ce-causationid`, `ce-hopcount`, `ce-legalentity` on transactional documents) plus `content-type` and W3C `traceparent`. The payload is the business JSON object and nothing else. The runtime fills every header it can derive; a message without the envelope goes to the dead letters.
- **Every event declares its aggregate type** in its contract (`x-aggregate-type`), and all subjects of one aggregate type share one strictly increasing aggregate version.
- **A consumer's cursor is keyed by `(consumer, aggregate_type, aggregate_id)`**, in `besdk_event_cursor` in its own schema, and advances in the same transaction as the handler's write. Older versions are skipped.
- **State mode is the default**: a handler is written as "bring my projection to the aggregate's state at version v". Sequence mode (every change in order) is reserved.
- **Loops are cut**: an event with `ce-hopcount` above 10 goes to the dead letters.
- **The registry is the contract file** in each component (`contracts/events/*.json`), checked at build time; no runtime schema registry.

## Why

The envelope must survive a change of broker ([0106](../01-architecture/0106-infrastructure-is-not-a-component.md)); CloudEvents names are the neutral choice and have bindings for every broker we name, and every bus we use carries headers. A cursor per subject breaks when events of one aggregate arrive on different subjects out of order: finance receiving `cancelled` before `created` would book a receivable for a cancelled order. Keyed by aggregate stream, the later version wins whatever the arrival order, and the final state after any reordering and duplication equals the in-order result. Before 3.0.0, the envelope travelled in `X-` headers that no producer filled completely, and no event declared its aggregate type.

## What this rules out

- `X-` headers, or the envelope repeated inside the payload; business data in headers
- A cursor or inbox keyed by subject, or by event id alone
- A handler written as "apply this change" that misbehaves when an older version arrives after a newer one
- A consumer that relies on the broker's order for correctness
- A runtime schema registry service

## Revisit only if

The first consumer appears that needs every change in order (build sequence mode for it), or an external party subscribes (generate AsyncAPI from the contract files; nothing on the wire changes).

Full analysis: [13-event-contracts.md, Choice](../../04-foundations/13-event-contracts.md#choice); the cursor in [11-consistency-across-components.md, Consumer cursor](../../04-foundations/11-consistency-across-components.md#consumer-cursor).
