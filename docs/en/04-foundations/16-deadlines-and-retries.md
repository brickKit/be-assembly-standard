[English](16-deadlines-and-retries.md) · [中文](../../zh/04-foundations/16-deadlines-and-retries.md)

# Deadlines and retries

How much time one request may take at each hop, from the user's click through the edge, the component, its database and the components it calls; which failures are retried, by which layer, and how much retry traffic is allowed; and the bulkheads that keep one slow dependency from exhausting a whole component or shell. For whoever sets a timeout, writes a retry, adds a long-running route, or proposes a circuit breaker.

## Scope

- **In:** time budgets and how they propagate; HTTP server timeouts and body limits; the retry rule of every layer; retry budgets; concurrency limits and connection budgets as bulkheads.
- **Out:** the transaction-level timeouts and the `40001`/`40P01` retry in detail ([10-local-transactions.md](10-local-transactions.md)); event redelivery in detail ([12-event-bus.md](12-event-bus.md#durable-consumers)); job and reconciler backoff ([19-background-jobs.md](19-background-jobs.md), [11-consistency-across-components.md](11-consistency-across-components.md)); the edge's own timeouts and rate limits (the edge document is planned as file 18).

## Choice

- **Every request has a deadline, and it only shrinks** as it travels: each hop gives its children less time than it has itself. In brickKit's words, the timeout you set on a dependency must be shorter than the time your caller is willing to wait for you (`brickkit docs 09-patterns/04-service-calling`).
- **Defaults a user can live with:** an ordinary action 10 s; an orchestrated action such as confirming an order 15 s, declared on its route; exports are asynchronous.
- **Method retries are decided by the contract alone**: a gRPC method is retried only if it declares itself free of side effects or idempotent, and only on `UNAVAILABLE`.
- **A retry budget per connection** caps retry traffic at about 10 % of normal traffic and stops retries entirely when a dependency is broadly down.
- **Bulkheads instead of circuit breakers:** a concurrency limit per (member, dependency), a connection budget per member, and deadlines.
- **One layer retries.** Code never wraps a retry loop around a call that already retries.

**Status**: decided; lands with the component protocol and the 3.0.0 sweep. Today no timeout is set anywhere: not on HTTP servers, database statements, gRPC calls, or the BFF's downstream requests. One hung dependency can hang login and the whole mobile path.

## Port contract

### The budget, hop by hop

| Hop | Default | Rule |
|---|---|---|
| User waits | 10 s; 15 s for declared orchestrations; exports return 202 and finish as a job | a route that needs more than 10 s declares it in its OpenAPI operation as `x-be-deadline-seconds` (planned), so the edge, the server and the frontend read one number |
| Edge | route deadline + 5 s | configured from the same declaration (planned edge document) |
| Inbound HTTP | the route's deadline | the request context carries it from the first byte read |
| HTTP server | read header 5 s; read 30 s; write = route deadline + 5 s; idle 120 s; body at most 1 MiB unless the route declares more | the same values standalone and in a shell; files go to object storage through presigned URLs, never through a component's body |
| Inbound gRPC | the caller's `grpc-timeout`; 10 s when absent | [14](14-system-rpc.md#server-requirements) |
| One outbound call | `min(3 s, remaining − 50 ms)` | with less than 50 ms left the call is not sent: `DEADLINE_EXCEEDED` / `DEADLINE_BUDGET_EXHAUSTED`. A system rpc that legitimately needs longer (closing a period) declares it as a method option (planned) |
| Database statement | `min(5 s, remaining)`; lock wait 2 s; idle in transaction 30 s | set per transaction ([10](10-local-transactions.md#port-contract)) |
| Event handler | the bus's acknowledgement wait (30 s) minus 5 s | a local write is expected within 1 s; a handler with side effects reports progress every 10 s ([12](12-event-bus.md#durable-consumers)) |
| Job run, reconciler step | the timeout the job declares | [19](19-background-jobs.md#port-contract) |
| Frontend | route deadline + 5 s | then shows the action as unfinished; a retried write reuses its `Idempotency-Key` ([15](15-user-api-and-errors.md#request-headers)) |

Worked example, confirming an order (15 s): sales receives the request with 15 s; its own reads get `min(5 s, remaining)` each; the reservation call to inventory gets `min(3 s, remaining − 50 ms)` and arrives with `grpc-timeout` of at most 3 s; inventory's statements get `min(5 s, that remaining)`. Nothing below sales can outlive the user's wait.

### Retries, layer by layer

| Layer | Retried | How | Bound |
|---|---|---|---|
| Database transaction | `40001`, `40P01` | re-run the body, `10 ms · 2^n` ± jitter | 3 attempts ([10](10-local-transactions.md)) |
| gRPC, methods with `idempotency_level` `NO_SIDE_EFFECTS` or `IDEMPOTENT` | `UNAVAILABLE` | the service config below | 3 attempts, plus the retry budget |
| gRPC, other methods | only a request that never left the client (gRPC's transparent retry) | built into gRPC | once |
| REST calls a component makes for a user | `GET` on a reset connection | one immediate retry | once |
| Frontend writes | timeouts and 5xx | the same `Idempotency-Key` | as the page decides; never a new key |
| Events | handler errors | nak with backoff 1 s … 1 h | 8 deliveries, then dead letters ([12](12-event-bus.md#durable-consumers)) |
| Queued commands | handler errors | the worker's backoff list | its maximum attempts, then the dead handler ([19](19-background-jobs.md)) |
| Reconcilers | handler errors | per item backoff | its maximum attempts, then `SUSPENDED` and a task ([11](11-consistency-across-components.md)) |

The service config every SDK generates for the retryable methods of a dependency (the gRPC service-config JSON is the same in every language):

```json
{
  "methodConfig": [{
    "name": [{ "service": "erp.inventory.v1.InventoryService", "method": "GetReservationStatus" }],
    "retryPolicy": {
      "maxAttempts": 3,
      "initialBackoff": "0.05s",
      "maxBackoff": "0.5s",
      "backoffMultiplier": 2,
      "retryableStatusCodes": ["UNAVAILABLE"]
    }
  }],
  "retryThrottling": { "maxTokens": 10, "tokenRatio": 0.1 }
}
```

- `retryThrottling` is the retry budget. It is counted per connection, and connections are per member, so one member's retry storm cannot spend another member's budget ([27-shells.md](27-shells.md)).
- Hedging (sending a second copy before the first fails) is off.
- **Nested retries multiply.** Three layers of three attempts make 27 calls at the bottom during an outage, exactly when the dependency can least take them. A component never adds its own retry loop around a runtime call that already retries; a retry a layer higher (a reconciler, a redelivered event) uses the same idempotency key.

### Bulkheads

| Resource | Limit | When reached |
|---|---|---|
| Concurrent outbound calls per (member, dependency) | 64 | fail at once with `RESOURCE_EXHAUSTED` / `OUTBOUND_LIMIT`; never queue |
| Database connections per member | `PG_POOL_MAX` (default 10) | wait up to `PG_POOL_ACQUIRE_TIMEOUT` (5 s) or the remaining deadline, then `RESOURCE_EXHAUSTED` / `DB_POOL_EXHAUSTED` ([03-database.md](03-database.md)) |
| Messages handled at once per subscription | 4, and at most 256 unacknowledged per durable | the broker holds back further deliveries ([12](12-event-bus.md#durable-consumers)) |
| Cache memory per member | declared per cache | eviction ([17-caching.md](17-caching.md)) |

## Alternatives

| Approach | Who uses it | Strengths | Weaknesses |
|---|---|---|---|
| **Deadline budgets, contract-driven retries, retry budget, bulkheads** (chosen) | gRPC's own design; Google SRE practice | bounded worst case at every hop; built into every gRPC library; deterministic and testable | numbers to choose and keep consistent |
| Circuit breakers in code (Hystrix-style, resilience4j, gobreaker, Polly) | Netflix-era Java services, many .NET shops | fail fast while a dependency is bad | per-dependency tuning; half-open behaviour is hard to test; on one instance "open" says only what a deadline already says |
| Outlier detection in a proxy or mesh (Envoy, Istio) | Kubernetes platforms | ejects bad replicas without code | a sidecar per pod; a shell is one application to it |
| Hedged requests | Google's tail-latency work | cuts tail latency with replicas | doubles load; nothing to gain with one replica |
| Adaptive concurrency limits (Netflix concurrency-limits, Envoy adaptive concurrency) | large fleets | limits follow measured latency | needs steady traffic to learn; harder to reason about |
| A fixed timeout per call with no budget | most code by default | simple | children can outlive their caller; failures arrive after the user gave up, with no trace |

## Why this choice

- **One machine first:** with a single instance of each component there is nothing for a breaker to route around or a proxy to eject. What protects users is a bounded wait, which deadlines give, and bounded damage, which bulkheads give.
- **Correct with several replicas:** the retry budget and the connection-age rotation ([14](14-system-rpc.md#load-balancing)) keep behaving when replicas are added, without new configuration.
- **The contract decides what may be retried**, so no developer, human or AI, has to judge per call whether a retry is safe.
- **It is the same in every language**, because deadlines, retry policy and throttling are part of gRPC's specification rather than one library's API.

## Why not the others

- **Circuit breakers** add per-dependency tuning and states that tests rarely reach, to say "the dependency is down", which a deadline plus a retry budget already handles on one instance.
- **Mesh outlier detection** needs a sidecar per pod and loses member identity inside a shell.
- **Hedging** doubles the load on a single instance for no latency gain.
- **Adaptive limits** need traffic volumes we do not have to learn from; a fixed limit is predictable.
- **Fixed timeouts without a budget** are today's failure mode in its mildest form: calls finish after their caller stopped waiting.

## When to switch

- **Several nodes with partial failures observed** (some replicas slow or failing while others are fine): add an interceptor-level breaker or client-side outlier detection, together with headless balancing.
- **A read path with replicas and a measured tail-latency problem:** enable hedging for that read method only.
- **The fixed outbound limit measurably misfits** a dependency (it rejects under normal load, or never triggers before latency collapses): make the limit adaptive for that dependency.

## How to switch

All of these live inside the SDK's client chain or the generated service config: a new interceptor, a `hedgingPolicy` for one method, a different limiter. Component code, contracts and pins do not change; a route's deadline changes only through its declaration.

## Conformance tests

Planned, in `tools/be-acceptance/conformance/rpc/` and `tools/be-acceptance/conformance/userapi/`; red today unless noted.

- an inbound HTTP request has the route's deadline, and an outbound call inherits the remaining budget;
- with less than 50 ms left an outbound call is not sent and fails with `DEADLINE_BUDGET_EXHAUSTED`;
- a gRPC call without a deadline receives the default;
- only `NO_SIDE_EFFECTS` or `IDEMPOTENT` methods are retried, and only on `UNAVAILABLE`;
- after the retry budget is spent, no further retries happen;
- a client that sends headers slowly is disconnected after the read-header timeout;
- the 65th concurrent call to one dependency fails at once with `OUTBOUND_LIMIT`;
- in a shell, one member exhausting its connection budget leaves another member's latency unchanged.

Component tests written red first: infra/iam-casdoor's login fails within its deadline when infra/authz hangs (today it waits forever); infra/bff-mobile returns a GraphQL error within its budget when a downstream hangs (today it waits forever). Gate: `idempotency-level-scan` ([14](14-system-rpc.md#contract-rules)).

## Decision records

- [0201 No Redis](../02-decisions/02-permissions/0201-no-redis.md): no shared store for global limits; rate limiting across requests belongs to the edge.
- [0108 One shell, one repository](../02-decisions/01-architecture/0108-one-repository-per-shell.md): budgets and limits are per member inside a shell.
- Planned, not yet numbered: "deadlines and retry budgets" (in the planned runtime folder); "gRPC is the system protocol between components".

## Known limits

- **Limits are per process.** There is no global rate limit across replicas; that waits for the edge.
- **Asynchronous work has no end-to-end deadline:** an event or a queued command is bounded per attempt, and in total by its maximum attempts.
- **`x-be-deadline-seconds` and the per-method option are planned**; until they exist, a long route needs its deadline set in code and in the frontend separately.
- **The 3 s cap per call** may be too short for a heavy system call until that call declares its own.
- **Deadlines are relative durations** (`grpc-timeout`), so clocks need not agree between machines; absolute times are never sent.
