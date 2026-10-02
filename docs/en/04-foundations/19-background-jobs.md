[English](19-background-jobs.md) · [中文](../../zh/04-foundations/19-background-jobs.md)

# Background jobs

How work that no request triggers is declared, scheduled, supervised and observed, the same way in every language and in both standalone and shell form. For whoever writes a periodic loop, a nightly job, a retry or an asynchronous command.

## Scope

All work inside a component that does not run on behalf of an incoming request:

- periodic loops (the outbox pump, sweeps of expired reservations);
- work that must run in one place at a time (partition maintenance, data-lifecycle freezing, snapshot backfill);
- work tied to a time slot (a daily report, the fourth-quarter reminder to open the next fiscal year);
- asynchronous commands enqueued inside a business transaction (open an exception task, poll a delivery result, retry a compensation).

Not covered here: consuming events ([12-event-bus.md](12-event-bus.md)); the reconciler that drives stuck cross-component flows, which is built on these jobs ([11-consistency-across-components.md](11-consistency-across-components.md)); long, multi-person flows lasting days, for which a workflow engine is evaluated in the same document.

## Choice

- **One Jobs port, owned by the SDK, with four kinds**: `every`, `singleton`, `cron`, `queue`.
- **Declared in one place.** A module lists all its jobs and workers in one declaration (one file); its start hook does one-time initialisation only and never starts a loop.
- **Supervised by the SDK.** A job that fails or panics is logged, counted and restarted with backoff; one job ending never stops another; standalone and shell behave the same.
- **State lives in the component's own schema**, in three tables the SDK's platform migration creates. A standalone run and a shell run of the same component, side by side, coordinate through the same rows.
- **No Kubernetes CronJob, no `pg_cron`, no external scheduler.**

**Status**: decided; lands with the 3.0.0 sweep. Today twelve components carry hand-copied loops (twelve copies of a partition package, each with its own ticker); in a shell a member whose loop fails stays stopped, while standalone the process exits and is restarted. The Jobs port replaces all of them.

## Port contract

The contract is tables and behaviour, so that every SDK, in any language, implements the same thing (the component protocol, [02-languages-and-component-protocol.md](02-languages-and-component-protocol.md)).

**Declaration.** A job has a name unique within its component (used in metrics, leases and logs), a kind, an interval (`every`, `singleton`) or a schedule (`cron`), and a timeout for one run. A `cron` schedule is either a five-field cron expression (`0 2 * * *`) or `@every <duration>` (`@every 2s`). A worker for queued jobs has a kind, a concurrency, a maximum number of attempts, a backoff list, and a handler for jobs whose attempts are used up.

**Overrides.** `JOBS_OVERRIDES` (JSON keyed by job name, runtime-owned `be.*` jobs included) overrides a job's `interval`, `cron` or `enabled` per deployment; an unknown job name is logged at WARN and ignored (be-protocol P14.5).

**Tables** (in the component's schema; components write no DDL for them):

```sql
CREATE TABLE besdk_job_lease (
    name       TEXT PRIMARY KEY,
    holder     TEXT        NOT NULL,   -- <component ID>/<instance id>
    epoch      BIGINT      NOT NULL DEFAULT 0,   -- fencing token, +1 on every takeover
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE besdk_job_slot (
    name       TEXT        NOT NULL,
    slot_at    TIMESTAMPTZ NOT NULL,   -- the scheduled instant of this slot
    holder     TEXT        NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    done_at    TIMESTAMPTZ,
    result     TEXT,
    PRIMARY KEY (name, slot_at)
);
CREATE TABLE besdk_job_queue (
    id           UUID        PRIMARY KEY,              -- UUIDv7
    kind         TEXT        NOT NULL,
    args         JSONB       NOT NULL,
    unique_key   TEXT,                                 -- optional de-duplication key
    run_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    attempts     INT         NOT NULL DEFAULT 0,
    max_attempts INT         NOT NULL,
    state        TEXT        NOT NULL DEFAULT 'ready', -- ready | running | done | dead
    lease_until  TIMESTAMPTZ,
    last_error   TEXT        NOT NULL DEFAULT '',
    traceparent  TEXT        NOT NULL DEFAULT '',
    causation_id TEXT        NOT NULL DEFAULT '',
    hop_count    INT         NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    finished_at  TIMESTAMPTZ
);
CREATE UNIQUE INDEX besdk_job_queue_unique ON besdk_job_queue (kind, unique_key)
    WHERE unique_key IS NOT NULL AND state <> 'done';   -- one live job per key; a done job frees the key
CREATE INDEX besdk_job_queue_due ON besdk_job_queue (kind, run_at) WHERE state IN ('ready', 'running');
```

**The four kinds:**

| Kind | Meaning | Mechanism | Typical users |
|---|---|---|---|
| `every` | runs on every replica, on its own timer; safe to run concurrently because the work it picks up is claimed atomically | a timer; work rows claimed with `FOR UPDATE SKIP LOCKED` | outbox pump, reservation sweep, overdue-task scan |
| `singleton` | at most one run at a time across all replicas and processes | take the lease with `UPDATE besdk_job_lease SET holder=$me, epoch=epoch+1, expires_at=now()+$ttl WHERE name=$n AND (expires_at < now() OR holder=$me) RETURNING epoch` (the row is created first with `INSERT … ON CONFLICT DO NOTHING`); renew every TTL/3; a lost lease cancels the running run; writes that must not happen twice check the epoch | partition maintenance, lifecycle freezing, snapshot backfill, cleanup of cursors and idempotency keys |
| `cron` | each time slot runs exactly once across all replicas | `INSERT INTO besdk_job_slot … ON CONFLICT DO NOTHING`; the process whose insert succeeds runs the slot and sets `done_at`; no leader; after downtime only the latest missed slot runs | daily report, fiscal-year reminder |
| `queue` | enqueued in the business transaction, executed at least once | the enqueue is an `INSERT` in the same transaction as the business write (rolled back with it), `ON CONFLICT DO NOTHING` when `unique_key` is set; workers claim `state='ready' AND run_at <= now()` rows with `FOR UPDATE SKIP LOCKED`, set `running` and `lease_until`, and run the handler **outside any transaction**; failure increments `attempts` and sets `run_at` from the backoff list; exhausted attempts set `dead` and call the dead handler in a transaction; a `running` row whose `lease_until` passed is claimable again | asynchronous commands, opening an exception task, polling a DingTalk delivery result |

- **Cron time zone.** A cron expression is evaluated in the deployment's business time zone, the shared key `BUSINESS_TIMEZONE` (default `Asia/Shanghai`, see [05-time-and-calendars.md](05-time-and-calendars.md)), unless the job declares another zone; there is no separate jobs time-zone key. A job that works per legal entity runs once per slot and computes each legal entity's business date inside the run.
- **Handlers are idempotent.** At least once means a handler may run twice; it deduplicates by `unique_key` or by a business key.
- **Retention.** `done` queue rows and old slot rows are deleted after a retention period by a `singleton` cleanup job. These tables are not partitioned; they stay bounded by retention, the same exception as the event cursor and command idempotency tables.

**Supervision.** Each job and worker runs on its own. An error or panic is logged with the member's logger at the level its cause deserves, counted, and the job restarts with exponential backoff from 1 s to 5 min. One job stopping never stops another. On shutdown runs are cancelled and given the grace period to finish. The same supervisor runs standalone and in a shell.

**Metrics** (every series also carries `component`): `be_job_runs_total{job,result}`, `be_job_duration_seconds{job}`, `be_job_last_success_timestamp_seconds{job}`, `be_queue_depth{kind,state}`, `be_queue_oldest_age_seconds{kind}`. The SDK ships alert-rule templates, for example "a singleton has not succeeded for three intervals".

**Operations endpoint** (optional, read-only): `GET /{domain}/{name}/_ops/jobs` lists jobs, last success, last error and queue depth; it requires the key `<domain>.<name>.ops`, which be-ops registers.

**In a shell.** The tables are in each member's own schema and `holder` names the member, so members never share leases, slots or queues ([27-shells.md](27-shells.md)).

## Alternatives

| | Kubernetes CronJob | `pg_cron` | River (Go) | Graphile Worker / pg-boss (Node) | Temporal Schedules | APScheduler / Celery beat | DBOS | SDK Jobs on PostgreSQL tables (chosen) |
|---|---|---|---|---|---|---|---|---|
| Single machine on Docker | brickKit does not generate it | extension, superuser needed, runs SQL only | yes | yes | needs a cluster | Celery needs a broker | yes | yes |
| Same in shell and standalone | no (a separate image, configuration injected twice) | no | yes | — | — | — | yes | yes |
| Enqueue inside the business transaction | — | — | yes | yes | — | — | yes | yes |
| Every language the same | — | — | Go only | Node only | yes | Python only | some languages | yes: tables and behaviour are the protocol |
| Singleton and once-per-slot | — | yes | leader election plus periodic jobs | yes | yes | needs an extra lock | yes | yes |

## Why this choice

- **Same behaviour in both forms.** The supervisor and the tables are the same standalone and in a shell, which removes today's split (a failed loop restarts the process standalone, stays dead in a shell).
- **Same behaviour in every language.** Components may be written in any language; a library tied to one language cannot be the contract. Tables plus semantics can.
- **Enqueue in the business transaction.** An asynchronous command exists if and only if the business write committed; there is no "after commit, best effort" gap.
- **Correct with several replicas** without a leader: leases for singletons, slot rows for cron, `SKIP LOCKED` for queues. One machine is the first target, multiple replicas must still be correct.
- **No new infrastructure**, and one place to look for every job of a component.

## Why not the others

- **Kubernetes CronJob**: brickKit does not generate it, it is a second image with its own configuration injection, and it does not exist on Docker, so the two targets would behave differently.
- **`pg_cron`**: needs an extension and a superuser, runs only SQL, and is not available on every PostgreSQL-compatible distribution the project targets ([03-database.md](03-database.md)).
- **River, Graphile Worker, pg-boss, APScheduler, Celery**: each is tied to one language; using one would give each language different semantics.
- **Temporal Schedules**: needs a Temporal cluster, which is only worth it together with a workflow engine ([11-consistency-across-components.md](11-consistency-across-components.md)).

## When to switch

- Measured job volume beyond what PostgreSQL absorbs in write amplification (thousands of jobs per second): queued jobs move onto the event bus ([12-event-bus.md](12-event-bus.md)).
- The first long, multi-person, multi-day flow appears: evaluate a workflow engine (DBOS first, then Temporal), as described in [11-consistency-across-components.md](11-consistency-across-components.md). DBOS could then become a second implementation of `queue`.

## How to switch

This is a **single-adapter port**, labelled honestly ([01-ports-and-adapters.md](01-ports-and-adapters.md)): its value is one set of semantics and one conformance suite, not interchangeability. A second adapter for `queue` would live inside the SDKs behind the same declaration; components keep their declarations unchanged, and because the tables belong to the SDK no component migration is needed.

## Conformance tests

Suite `tools/be-acceptance/conformance/jobs/` (decided), run against a fixture component built with each official SDK:

- two replicas: one `cron` slot runs exactly once (CP-JOBS-01: the platform cron job `be.cleanup` set to `@every 2s` through `JOBS_OVERRIDES`);
- two replicas: a `singleton` runs in one place at a time; a run whose lease is lost is cancelled;
- a job that panics restarts with backoff and is counted; one job stopping leaves the others running;
- `queue`: a rolled-back business transaction leaves no job; exhausted attempts call the dead handler; two replicas execute each job once under normal operation;
- shell: a member's failed job is restarted, not left stopped (red today).

Component tests written red before migration: finance "when one loop exits the others are cancelled"; inventory "two replicas maintain partitions concurrently without error" and "partition DDL blocked by a long transaction gives up within `lock_timeout` without blocking writes". Gate `module-ticker-scan` (decided) warns on timer loops in module code.

## Decision records

- [0508 Background work runs only through the SDK's Jobs](../02-decisions/05-runtime/0508-background-work-only-through-jobs.md): this document is its full analysis.
- [0501 No network call inside a transaction](../02-decisions/05-runtime/0501-no-network-inside-a-transaction.md): enqueueing in the business transaction is the asynchronous exit.
- [0102 One database, one schema per component](../02-decisions/01-architecture/0102-one-schema-per-component.md): the job tables live in the component's schema.
- [0108 One shell, one repository, one image, one member list](../02-decisions/01-architecture/0108-one-repository-per-shell.md): the launcher, and so the supervisor, lives in the SDK.

## Known limits

- One adapter; the port exists for uniform semantics, not for swapping.
- Cron precision is about a second; after downtime only the latest missed slot runs, so a job that must cover every missed day iterates the gap itself.
- A crashed singleton's work resumes only after its lease expires (up to one TTL).
- At least once: handlers must be idempotent.
- Throughput is bounded by PostgreSQL writes in the component's schema.
