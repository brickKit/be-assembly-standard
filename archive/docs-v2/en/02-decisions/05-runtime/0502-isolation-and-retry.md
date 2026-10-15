[English](0502-isolation-and-retry.md) · [中文](../../../zh/02-decisions/05-runtime/0502-isolation-and-retry.md)

# 0502 READ COMMITTED with an explicit ladder; retry only serialization failures and deadlocks

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

- **Every transaction runs at READ COMMITTED by default.** One transaction may ask for REPEATABLE READ or SERIALIZABLE; the default never changes.
- **Each invariant names its tool**, the first rung of a fixed ladder that expresses it: a constraint; a conditional update; row locks taken in a fixed order; a transaction-level advisory lock whose key includes the component's schema; SERIALIZABLE for that one transaction, with the reason in a comment at the call site.
- **Rows are locked in a fixed order** (primary key or business key), and duplicates in a request are rejected before locking.
- **Every transaction sets its own timeouts with `SET LOCAL`**: `statement_timeout` `min(5 s, remaining deadline)`, `lock_timeout` 2 s, `idle_in_transaction_session_timeout` 30 s, and on PostgreSQL 17 or later `transaction_timeout`. Role-level settings are only a backstop.
- **The runtime retries `40001` and `40P01` only**, by re-running the whole body in a new transaction: at most 3 attempts, `10 ms · 2^n` with jitter, then `ABORTED` / `TX_CONFLICT`. A lock or statement timeout is not retried at this level.
- **Advisory locks are transaction-level only.**

## Why

The hot spots of an ERP (one stock-balance row per product and warehouse, the periods of one legal entity) are contended. Under READ COMMITTED a conditional update on them waits and proceeds against the newest row; a stricter global level turns the same contention into aborts and retries that users feel as latency. A named rung per invariant can be reviewed against that invariant instead of trusting a global level. Timeouts set per transaction behave the same standalone and in a shell, where a member role's settings never apply after `SET ROLE`. Automatic retry is safe only because the body cannot reach the network ([0501](0501-no-network-inside-a-transaction.md)). Before 3.0.0, multi-item reservations locked rows in request order and could deadlock, and nothing was retried.

## What this rules out

- Raising the default isolation level "to be safe"
- Locking several rows in the order the request lists them
- `pg_advisory_lock` or any session-level lock; an advisory key without the schema
- `SET` without `LOCAL`, or relying on `ALTER ROLE … SET` for timeouts
- A retry loop in component code around a transaction, or retrying a `LOCK_TIMEOUT` without the same idempotency key a layer higher

## Revisit only if

A measured, repeated class of anomaly appears that no rung of the ladder can express.

Full analysis: [10-local-transactions.md, The isolation ladder](../../04-foundations/10-local-transactions.md#the-isolation-ladder) and [Choice](../../04-foundations/10-local-transactions.md#choice).
