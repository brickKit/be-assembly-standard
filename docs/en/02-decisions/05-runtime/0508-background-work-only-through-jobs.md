[English](0508-background-work-only-through-jobs.md) · [中文](../../../zh/02-decisions/05-runtime/0508-background-work-only-through-jobs.md)

# 0508 Background work runs only through the SDK's Jobs

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

Every piece of work in a component that no request triggers is declared, in one place in the module, as one of the four kinds of the SDK's Jobs port or as a reconciler, and the SDK runs and supervises it:

| Kind | Semantics | State in the component's own schema |
|---|---|---|
| `every` | runs on every replica; work is claimed with `SKIP LOCKED` | — |
| `singleton` | at most one run at a time across all replicas, by lease (TTL 30 s, renewed every third) with an epoch as fencing token | `besdk_job_lease` |
| `cron` | each time slot runs once across all replicas, claimed with `INSERT … ON CONFLICT DO NOTHING`; evaluated in `BUSINESS_TIMEZONE` unless the job names its own zone | `besdk_job_slot` |
| `queue` | enqueued in the business transaction, executed at least once after commit, retried with backoff, dead-lettered to its `OnDead` handler | `besdk_job_queue` |
| reconciler | scans rows past their deadline in a non-final state, claims each with a lease, drives it forward or gives up into `SUSPENDED` with an exception task | `besdk_reconcile` |

- The module's start hook does one-time initialisation only and never starts a loop.
- A job that fails or panics is logged, counted and restarted with backoff; one job ending never stops another; standalone and shell behave the same.
- Every run has a timeout; per-job metrics use the `be_job_*`, `be_queue_*` and `be_reconcile_*` names.
- No Kubernetes CronJob, no `pg_cron`, no external scheduler.

## Why

Before 3.0.0 twelve components carried hand-copied loops, each with its own ticker; in a shell a member whose loop failed stayed stopped, while standalone the process exited and was restarted. One supervisor and three tables behave the same in both forms, in every language, and stay correct with several replicas without a leader. Enqueueing in the business transaction means an asynchronous command exists if and only if the business write committed ([0501](0501-no-network-inside-a-transaction.md)).

## What this rules out

- A ticker, goroutine, thread, `setInterval` or sleep loop in module code (gate `module-ticker-scan`)
- Starting a loop from the start hook
- "After commit, call it in the background" without a queue row
- An external scheduler or a database extension to run a component's jobs
- A job without a timeout, or whose failure stops the process or another job

## Revisit only if

Measured job volume exceeds what PostgreSQL absorbs (thousands of jobs a second: queued jobs move onto the bus), or the first long, multi-person, multi-day flow appears (evaluate a workflow engine, DBOS first, then Temporal).

Full analysis: [19-background-jobs.md, Choice](../../04-foundations/19-background-jobs.md#choice).
