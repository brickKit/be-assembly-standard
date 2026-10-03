[English](0506-at-least-once-delivery-and-streams.md) · [中文](../../../zh/02-decisions/05-runtime/0506-at-least-once-delivery-and-streams.md)

# 0506 Events are delivered at least once; streams follow the first subject segment

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

- **Publishing goes only through the outbox**: `besdk_outbox` is written in the same transaction as the business change, and a pump publishes after commit, marking a row published only after the bus has confirmed it durably. When the bus is down rows wait and are retried; they are never dropped.
- **Delivery is at least once.** Effects in the consumer's database are effectively once because its cursor advances in the same transaction as its write ([0505](0505-cloudevents-envelope-and-aggregate-cursor.md)); a handler with an external side effect is idempotent on a business key. Exactly-once is not promised.
- **The producer's outbox is the source of truth for replay**, kept 14 days after publishing; the broker's retention is a transport buffer. Older history is backfilled through the producer's `List`, not replayed as events.
- **One stream per first subject segment** (`BE_ERP`, `BE_MDM`, …, `BE_SALES` and `BE_FINANCE` for the older subjects), created by whoever needs it first, "create if missing, never touch if present", in the migration step and again at start. Defaults: 7 days, 1 GiB, discard old, a 10-minute duplicate window; dead letters in `BE_DLQ` for 30 days.
- **One durable per (component, subject)**, with the same name standalone, in a shell and on every replica. A new durable starts with everything still in the stream (`DeliverAll`). Acknowledge after commit; nak with backoff on error, the last allowed delivery included; a message received again after its last allowed delivery (8 by default, `EVENTS_MAX_DELIVER` or the subscription's own value) goes to the dead letters before the handler runs, and so does one with a permanent error.
- **Best-effort signals** (the authz poke), marked `x-signal: true` in the events contract, travel on core NATS: may be lost, never persisted, no outbox row and no durable.

## Why

Without persistence, a publish with no subscriber online "succeeds" and is lost, and every replica receives every message; that was the state before 3.0.0. At-least-once with an idempotent consumer is what every mainstream broker can actually guarantee, and it does not depend on the broker. A stream per first segment follows the subject rather than the producer, so several members of a slot family can publish one subject, and an operator may pre-create and tune a stream without a registry. `DeliverAll` lets a newly installed consumer catch up on the last seven days.

## What this rules out

- Publishing to the bus directly, or deleting an outbox row that has not been confirmed
- A consumer that assumes exactly-once delivery, or an external side effect without an idempotency key
- A stream per producing component, a central stream registry, or `make nats-init` as the only way streams appear
- A durable name that differs between standalone and shell, or per replica
- Replaying events older than the outbox retention instead of backfilling

## Revisit only if

A customer standardises on Kafka (the Kafka adapter is built and passes the bus suite), or measured load on one stream exceeds about 50,000 messages a second (split it by subject mapping, still JetStream).

Full analysis: [12-event-bus.md, Choice](../../04-foundations/12-event-bus.md#choice) and [Streams](../../04-foundations/12-event-bus.md#streams).
