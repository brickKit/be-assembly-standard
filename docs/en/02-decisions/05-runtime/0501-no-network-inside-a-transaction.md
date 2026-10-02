[English](0501-no-network-inside-a-transaction.md) · [中文](../../../zh/02-decisions/05-runtime/0501-no-network-inside-a-transaction.md)

# 0501 No network call inside a transaction

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

While a unit of work holds an open database transaction, it makes no network call: no gRPC, no user-plane HTTP, no third-party HTTP, no direct publish to the bus. The only ways for a transaction to cause an effect outside the database are two rows written in the same transaction:

| Exit | Runs | Contract |
|---|---|---|
| an outbox row | the event is published after commit | [0506](0506-at-least-once-delivery-and-streams.md) |
| a job-queue row | the command runs after commit, outside any transaction, retried with backoff, escalated when it keeps failing | [0508](0508-background-work-only-through-jobs.md) |

So a remote side effect required after a business change is always a queued command, never "call it after commit and hope". The official SDKs enforce this: every outbound call refuses to start inside a transaction (`INTERNAL` / `NETWORK_IN_TX`), and opening a second transaction in the same unit of work fails (`INTERNAL` / `NESTED_TX`). For a component in another language it is an INTERNAL protocol rule its author shows how to hold ([0109](../01-architecture/0109-language-neutral-component-protocol.md)).

## Why

A network call inside a transaction holds row locks for the downstream's latency, so every other request on those rows queues behind it; a retried body repeats the call; an event handler that outlives the bus's acknowledgement wait is redelivered and runs twice. With bounded pools, a second connection held while waiting for the first is how a pool deadlocks. Writing the effect as a row in the same transaction makes it exist if and only if the business change committed. Before 3.0.0, three consumers called other components while holding a transaction, and three remote calls were made "after commit, best effort".

## What this rules out

- Calling another component, an IM service or any HTTP endpoint between `BEGIN` and `COMMIT`
- Publishing to the bus directly instead of through the outbox
- A best-effort call after commit with nothing to retry it when it fails
- Opening a nested transaction, or holding two connections in one unit of work
- Disabling the guard "for this one handler"

## Revisit only if

Never for the rule itself. A step that truly needs a synchronous remote answer before commit (a reservation the user waits for) is designed as try-confirm-cancel with an idempotency key, outside the transaction.

Full analysis: [10-local-transactions.md, Port contract](../../04-foundations/10-local-transactions.md#port-contract); the asynchronous exits in [11-consistency-across-components.md, Choice](../../04-foundations/11-consistency-across-components.md#choice).
