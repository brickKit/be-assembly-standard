[English](12-event-bus.md) · [中文](../../zh/04-foundations/12-event-bus.md)

# Event bus

Which message broker carries events between components, what delivery it promises, how streams, consumers and dead letters are laid out, how history is replayed, how back-pressure works, and the broker port that lets the same components run on NATS JetStream, on a PostgreSQL queue, or later on Kafka. For whoever changes how events are published or consumed, operates the bus, or proposes another broker.

## Scope

- **In:** the broker choice; delivery semantics; streams, durable consumers, acknowledgement, redelivery and dead letters; replay; back-pressure; client connection settings; best-effort signals; the broker port and its adapters.
- **Out:** what an event looks like (headers, naming, contract files, schema evolution): [13-event-contracts.md](13-event-contracts.md). The outbox and the consumer cursor that make delivery effectively-once: [11-consistency-across-components.md](11-consistency-across-components.md). How a component declares what it publishes and consumes: [02-backend.md](../01-conventions/02-backend.md#events-and-cross-component-writes).

## Choice

- **NATS JetStream is the default adapter** (NATS 2.10 or later, already started by `make up`).
- **Delivery is at least once.** Effects in the consumer's database are effectively once, because the cursor advances in the same transaction as the write ([11](11-consistency-across-components.md#consumer-cursor)). Exactly-once is not promised.
- **The producer's outbox is the source of truth for replay**; the broker's retention is a transport buffer.
- **A PostgreSQL queue adapter is built now, as the second adapter**, with the conformance suite: for small installations that do not want to run NATS, for tests, and to prove the port is real. **A Kafka adapter is built when a customer brings Kafka.** RabbitMQ and Pulsar adapters are not planned.
- **The adapter is chosen by the scheme of one shared address**, `EVENT_BUS_URL`; components do not change.

**Status**: decided; lands with the component protocol and the 3.0.0 sweep. Today events travel over core NATS: no persistence, no redelivery, every replica receives every message, and a publish with no subscriber "succeeds" and is lost. JetStream is already enabled on the server.

## Port contract

### Choosing the adapter

| `EVENT_BUS_URL` | Adapter | Status |
|---|---|---|
| `nats://host:4222` | JetStream | default |
| `postgres://host:5432/<db>?schema=be_bus` | PostgreSQL queue | decided, built in phase 06 |
| `kafka://broker1:9092,broker2:9092` | Kafka | later |

`EVENT_BUS_URL` is a new shared key in `config/vars.yaml`, referenced as `$var:EVENT_BUS_URL` ([04-configuration.md](../01-conventions/04-configuration.md#shared-connection-keys)). When it is absent the SDK uses `NATS_URL`; at least one of the two must be set. A scheme the runtime has no adapter for (`kafka://` today) fails the start, naming the scheme, with a non-zero exit code that is not 78 (be-protocol P12.12). The official SDKs ship `nats://` first; the PostgreSQL queue adapter follows. Every component of a project uses the same adapter: two adapters would be two separate buses.

### Operations every adapter provides

| Operation | Semantics |
|---|---|
| ensure stream | create the stream if missing; never change an existing one |
| publish | store a message with its ID; success means stored durably; the same ID within the duplicate window is stored once |
| ensure durable | create the durable consumer if missing; never update an existing one |
| consume | deliver to a named durable consumer with a subject filter; replicas sharing the durable compete, each message to one of them; a message not acknowledged within `ack_wait` is delivered again |
| ack / nak with delay / terminate / in progress | done; redeliver after a delay; never redeliver; extend the acknowledgement deadline |
| delivery count | how many times this message was delivered |
| notify / on notify | a best-effort signal: not stored, not redelivered, may be lost |

### Streams

- **One stream per first subject segment**: name `BE_<FIRST SEGMENT IN CAPITALS>`, subjects `<first segment>.>`. Today: `BE_ERP`, `BE_MDM`, `BE_CRM`, `BE_INFRA`, `BE_INTEGRATION`, and `BE_SALES`, `BE_FINANCE` for the older subjects without the `erp.` prefix. Dead letters: `BE_DLQ`, subjects `dlq.>`.
- **Created by whoever needs it first**, "create if missing, never touch if present", in the component's migration step (which brickKit runs with the component's own image and configuration before the component starts) and again at start. Operators may pre-create a stream and tune it; a component that finds no stream and may not create one fails its migration with a clear error.
- **Defaults:** `max_age` 7 days, `max_bytes` 1 GiB, `discard: old`, `duplicate_window` 10 minutes, file storage, 1 replica (3 on a NATS cluster, set by the operator). `BE_DLQ`: 30 days.
- A stream follows the subject, not the producing component, so several members of a slot family can publish one subject (`integration.im.result.v1`), and every relation owner can publish `infra.authz.relation.sync.v1` ([13](13-event-contracts.md#subjects)).

### Durable consumers

- **One pull durable per (component, subject)**, named `<component ID with / as _>__<subject with every . as __>`: `erp_finance__sales__order__created__v1` (be-protocol P12.5). The same name standalone, in a shell and on every replica, so moving a member in or out of a shell keeps its position. The derivation is injective: a component ID contains no `_`, and no subject segment contains `__` or starts or ends with `_` ([13](13-event-contracts.md#subjects)), so the name splits back uniquely at every `__`; `crm.lead.stage_changed.v1` and `crm.lead_stage.changed.v1` keep distinct names (`…__crm__lead__stage_changed__v1`, `…__crm__lead_stage__changed__v1`).
- **Created only if absent, never updated.** At start the SDK looks the durable up and creates it only when it is missing; an existing durable is left as it is, even when its settings differ (an operator may have tuned it). No blind "add or update" call is used (nats-py's `add_consumer` updates silently); changing an existing durable is an operator's act.
- **First creation delivers everything still in the stream** (`DeliverAll`): a newly installed consumer catches up on up to 7 days of events. A newly installed finance therefore books orders confirmed in the 7 days before it was installed.
- `ack_wait` 30 s, the real timer for a message whose handler neither acknowledged nor nak'ed it; `max_ack_pending` 256; up to 4 messages handled at once per subscription, also bounded by the member's connection budget ([10](10-local-transactions.md#port-contract)); `inactive_threshold` 30 days, so a removed component's durables disappear by themselves.
- **Redelivery timing and the delivery limit belong to the SDK, not the server.** The durable is created with no server-side `BackOff` and with `MaxDeliver` -1 (unlimited).

  | Key | Default | Used by the SDK as |
  |---|---|---|
  | `EVENTS_BACKOFF` | `1s,10s,1m,5m,15m,30m,1h` when neither the key nor the subscription sets one | the `NakWithDelay` schedule: the delay of the nak after the n-th failed delivery |
  | `EVENTS_MAX_DELIVER` | `8` when neither the key nor the subscription sets one | the delivery limit: a message received with `NumDelivered` > `EVENTS_MAX_DELIVER` is not handled; the SDK writes it to the dead letters, then terminates it |

  The keys have no catalogue default. A subscription may declare its own values; precedence is the key when it is set (present in the configuration), then the subscription's value, then the built-in value above (be-protocol P12.5).
- **The last allowed delivery** is an ordinary one: a delivery with count `d = EVENTS_MAX_DELIVER` that fails is nak'ed like any other. The message is dead-lettered at its next receipt (`d > EVENTS_MAX_DELIVER`), before the handler runs. So a message is handled at most `EVENTS_MAX_DELIVER` times.
- **Acknowledge after the handler's transaction committed.** On error: nak with the next delay of `EVENTS_BACKOFF`. On a permanent error (unparsable, contract violation): publish to the dead-letter subject, then terminate. While a handler runs: "in progress" every 10 s (a third of `ack_wait`).

### Dead letters

- Subject `dlq.<durable>.<original subject>`, with headers `be-dlq-reason`, `be-dlq-consumer`, `be-dlq-delivery` added to the original ones. The durable is in the subject because a message may fail in one consumer and succeed in another; only the failing one gets it back.
- The dead-letter message's ID (`Nats-Msg-Id` on NATS) is `dlq:<durable>:<seq>`, `<seq>` being the original's stream sequence, so a dead-lettering repeated after a crash between the write and the terminate is stored once.
- A message goes there when it is received with a delivery count above `EVENTS_MAX_DELIVER`, on a permanent error, or when its hop count exceeds 10 ([13](13-event-contracts.md)). The original is terminated only after the dead letter is stored.
- `make dlq-ls` and `make dlq-replay` (planned) list and replay them. A replay publishes to the original subject with a suffixed message ID to pass the duplicate window; other consumers skip it through their cursor.
- `be_dlq_messages_total{subject,consumer}`, with an alert-rule template.

### Replay

- **Within stream retention:** a temporary consumer starting at a point in time.
- **Beyond retention:** `make events-replay COMPONENT=<id> SUBJECT=<subject> SINCE=<time>` (planned) reads the producer's outbox and republishes with suffixed message IDs; consumers deduplicate through their cursor. Replay therefore does not depend on which broker is in use. The outbox keeps rows 14 days after publication; older history is not replayed as events: a new consumer backfills from the producer's `List`, and from its published datasets where the range is cold.

### Publishing

- The outbox pump claims rows with `FOR UPDATE SKIP LOCKED` ([02-backend.md](../01-conventions/02-backend.md#database)), publishes with message ID = the row's `id`, and marks a row `PUBLISHED` only after the broker acknowledged storing it. No stream, or no broker, leaves the row `PENDING` for the next round.
- A row whose claim expired is published again; the duplicate window drops the copy.
- Up to 256 acknowledgements in flight; polling adapts from every 200 ms while busy to every 2 s while idle, so a shell of many members does not spin.

### Client settings

- Reconnect forever, every 2 s with jitter; keep retrying when the broker is not up yet at start; the connection is named after the member's component ID; disconnects, reconnects and asynchronous errors are logged with the member's logger.
- In a shell: one connection per process; durables and subscriptions carry each member's ID ([27-shells.md](27-shells.md)).

### Best-effort signals

Signals such as the authorization provider's "bundle changed" (`infra.authz.changed.v1`) are marked `x-signal: true` in the producer's events contract ([13](13-event-contracts.md#the-contract-file)): no outbox row, no durable, not listed in `component.yaml` `events.publishes`. They go through notify: core NATS publish on JetStream; `LISTEN`/`NOTIFY` on the PostgreSQL queue; a short-retention topic on Kafka. They may be lost, and every user of one also polls.

### PostgreSQL queue adapter

Tables in the schema `be_bus`, which belongs to the infrastructure like NATS does; `make db-init` creates it and grants every component's role `SELECT, INSERT, UPDATE, DELETE` on these tables. Components still never read each other's schemas ([0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)).

- **Connection**: the adapter connects with the component's own `PG_USER` and `PG_PASSWORD_FILE`, so a component on the queue bus declares the database keys even when it has no tables of its own.
- **Partitions**: the adapter maintains the partitions of `be_bus.message` only through `SECURITY DEFINER` functions owned by the `NOLOGIN` role `be_bus_owner`, the same pattern as the lifecycle functions ([09](09-data-lifecycle.md)); no component role holds DDL rights on `be_bus`. The project's database setup also creates a DEFAULT partition of `be_bus.message`, so a publish never fails for want of a partition.

```sql
CREATE TABLE be_bus.message (
    stream       TEXT        NOT NULL,
    seq          BIGINT      GENERATED ALWAYS AS IDENTITY,
    tx_id        XID8        NOT NULL DEFAULT pg_current_xact_id(),
    msg_id       TEXT        NOT NULL,
    subject      TEXT        NOT NULL,
    headers      JSONB       NOT NULL,
    data         BYTEA       NOT NULL,
    published_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (seq, published_at)
) PARTITION BY RANGE (published_at);          -- retention = dropping old partitions

CREATE TABLE be_bus.msg_id (                   -- the duplicate window, unpartitioned
    stream     TEXT        NOT NULL,
    msg_id     TEXT        NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (stream, msg_id)
);

CREATE TABLE be_bus.durable (
    name         TEXT PRIMARY KEY,
    stream       TEXT        NOT NULL,
    filter       TEXT        NOT NULL,
    last_tx_id   XID8,
    last_seq     BIGINT,
    last_active  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE be_bus.delivery (                 -- in flight and waiting for redelivery
    durable       TEXT        NOT NULL,
    seq           BIGINT      NOT NULL,
    num_delivered INT         NOT NULL DEFAULT 0,
    next_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    lease_until   TIMESTAMPTZ,
    PRIMARY KEY (durable, seq)
);
```

- **Publish:** insert into `msg_id` with `ON CONFLICT DO NOTHING`; only when that inserted, insert the message, in the same short transaction.
- **Fan-out:** under a row lock on its `durable` row, a consumer copies the next matching messages into `delivery` and advances `(last_tx_id, last_seq)`. It reads only messages whose `tx_id` is older than every transaction still running (`tx_id < pg_snapshot_xmin(pg_current_snapshot())`), so a publisher that committed later with a lower `seq` is never skipped.
- **Consume:** claim `delivery` rows with `next_at <= now()` and an expired lease using `FOR UPDATE SKIP LOCKED`; ack deletes the row; nak sets `next_at` and increments `num_delivered`; in progress extends `lease_until`; terminate deletes it. A lease that runs out (`ack_wait`) makes the row claimable again.
- **Same semantics as JetStream:** the adapter keeps no delivery limit and no backoff of its own; the SDK reads `num_delivered` as the delivery count, naks with the `EVENTS_BACKOFF` delays, and applies the same `EVENTS_MAX_DELIVER` check and the same dead-letter message ID (deduplicated through `msg_id`). A durable row is inserted only if absent and never updated.
- **Notify:** `NOTIFY be_bus, '<subject>'` wakes consumers; signals use the same channel.

### Kafka adapter (later)

One topic per stream, one consumer group per durable; delayed redelivery through retry topics; dead letters to a topic per durable. Message ID dedupe through the producer's idempotence plus the consumer cursor.

## Alternatives

| | NATS JetStream | Kafka (KRaft) | Redpanda | RabbitMQ (quorum queues, streams) | Pulsar | PostgreSQL queue (ours; pgmq, River, Graphile Worker, pg-boss as references) |
|---|---|---|---|---|---|---|
| On one machine | one Go binary, tens of MB | JVM, GB scale | one C++ binary, memory-hungry | Erlang, moderate | several services, heavy | nothing new: the database already runs |
| Retention and replay | by age and size, from any point in time | log retention, by offset | as Kafka | streams yes; queues delete on consume | tiered storage | as long as partitions are kept |
| Order | per stream; redelivery reorders | per partition; rebalance and retries reorder | as Kafka | per queue | per partition | by `seq`; `SKIP LOCKED` reorders |
| Competing consumers, redelivery, dead letters | durable plus nak backoff plus max deliver; dead letters by us | consumer groups; retry topics by us | as Kafka | native dead-letter exchanges, TTL, delays | native | by us (simple) |
| Duplicate suppression | message ID within a window | idempotent producer only | as Kafka | none | yes | unique key within a window |
| Clients | mature in Go, Python, TypeScript, Rust, Java, .NET, C | mature everywhere | Kafka clients | mature everywhere | Go and Python thinner | any PostgreSQL driver |
| Throughput on one node | ~100k messages/s | millions | millions | 10k–100k | millions | thousands (write amplification) |

## Why this choice

- **JetStream:** already deployed; light on one machine; streams, durables, nak with backoff and a duplicate window match exactly the semantics we need; core NATS carries the best-effort signals on the same connection; clients exist for every mainstream language, which matters once components may be written in any of them.
- **The outbox as source of truth** makes replay independent of the broker and of its retention.
- **A PostgreSQL queue as the second adapter** adds no dependency, fits the smallest installation, doubles as a test bus, and proves that nothing above the port depends on JetStream.
- **Our own queue tables rather than a library:** the tables and statements are the contract, so every language implements the same thing.

## Why not the others

- **Kafka:** a JVM at GB scale for a single-machine first target, and partitions plus consumer groups add operations for no semantic gain here. Built as an adapter when a customer already runs it.
- **Redpanda:** lighter than Kafka but still heavy in memory, with the same model.
- **RabbitMQ:** classic queues delete on consume, so replay is weak; streams help but are a second model inside one product.
- **Pulsar:** several services to run.
- **pgmq** needs a database extension, which PostgreSQL-compatible distributions may lack and least-privilege roles cannot install; **River** is Go only; **Graphile Worker** and **pg-boss** are Node only.
- **"Exactly once" from the broker** (a duplicate window plus double acknowledgement) removes only duplicates between broker and client within the window; it does not cover our database. The cursor does.

## When to switch

- **A customer standardises on Kafka** and requires all integration on it: build and use the Kafka adapter.
- **A minimal installation** (one small machine, no NATS) or a test environment: the PostgreSQL queue.
- **Measured load above ~50,000 messages/s on one stream:** split that stream by subject mapping into partitions with one durable each; still JetStream.
- **High availability across machines** becomes a requirement: a three-node NATS cluster with stream replicas 3; no component change.

## How to switch

1. Run `tools/be-acceptance/conformance/bus/` against the target adapter; red stops the switch.
2. Set `EVENT_BUS_URL` once in `config/vars.yaml` (or in one environment's `vars:`). Every component moves together.
3. Restart the components; streams and durables are created on the new bus by the migration step.
4. To carry history over, replay from the outboxes (`make events-replay`); consumers skip what they already applied.

No component code, contract or pin changes.

## Conformance tests

Planned suite `tools/be-acceptance/conformance/bus/`, the same cases for every adapter:

- a consumer restarted after downtime receives what was published meanwhile;
- two instances of one durable each handle a message once;
- nak redelivers after the delay taken from `EVENTS_BACKOFF`; a message neither acknowledged nor nak'ed is redelivered after `ack_wait`;
- a message received with a delivery count above `EVENTS_MAX_DELIVER` is not handled; it is in the dead-letter subject once, with message ID `dlq:<durable>:<seq>`, the consumer and the reason, and is not delivered again;
- ensure durable creates a missing durable and leaves an existing one with other settings unchanged;
- terminate stops redelivery;
- one message ID within the window is stored once;
- ensure stream is idempotent and does not overwrite an existing configuration;
- "in progress" prevents redelivery of a slow message;
- headers round-trip unchanged;
- a payload above the limit fails with a clear error;
- one consumer receives in publish order when nothing fails;
- notify is neither stored nor redelivered;
- two shell members subscribing to one subject each receive a copy.

SDK tests written red first: reconnects and resumes after the broker was down for 3 minutes; waits at start when the broker is not up yet; a slow handler does not block another subject; failure logs carry the member's component ID; the pump backs off to 2 s when idle; the suite is seen red against a fake adapter that drops acknowledgements. Project test: replay from an 8-day-old outbox applies nothing twice.

## Decision records

- [0106 Infrastructure is not a component](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md): the bus stays infrastructure and is swapped through an SDK adapter chosen by the URL scheme, which is more than a setting and must pass the suite.
- [0506 At-least-once delivery; streams by first subject segment](../02-decisions/05-runtime/0506-at-least-once-delivery-and-streams.md): this document is its full analysis: at-least-once delivery, streams by first subject segment, the outbox as the source of truth for replay.
- [0505 CloudEvents envelope; one cursor per aggregate stream](../02-decisions/05-runtime/0505-cloudevents-envelope-and-aggregate-cursor.md): the envelope every adapter carries unchanged.
- [0102 One database, one schema per component](../02-decisions/01-architecture/0102-one-schema-per-component.md): the `be_bus` schema belongs to the infrastructure, not to a component.

## Known limits

- **`discard: old` with a 1 GiB cap:** a consumer offline longer than the retention loses events from the stream; it recovers by replay from the outbox, and an alert fires when a consumer's lag or pending count nears the limit.
- **No ordering guarantee** from any adapter; correctness comes from the cursor ([13](13-event-contracts.md)).
- **Message size:** NATS rejects messages above `max_payload`, 8 MB in `infra/nats/nats.conf`, headers included. Events are kept small ([13](13-event-contracts.md#port-contract)).
- **One NATS server in the first deployment shape** is a single point of failure for asynchronous flows; synchronous requests keep working and outboxes fill until it returns.
- **The PostgreSQL queue** handles thousands of messages per second and adds write load to the shared database.
- **The Kafka adapter does not exist yet.** The project's infrastructure list still names Kafka and RabbitMQ as alternatives for the bus; until an adapter exists they are not usable.
