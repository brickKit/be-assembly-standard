[English](0503-deadlines-and-retry-budgets.md) · [中文](../../../zh/02-decisions/05-runtime/0503-deadlines-and-retry-budgets.md)

# 0503 Every request has a shrinking deadline; retries are decided by the contract and capped by a budget

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

- **Every request has a deadline, and it only shrinks** as it travels: each hop gives its children less time than it has itself.
- **User-facing defaults**: an ordinary action 10 s; a declared orchestration such as confirming an order 15 s; exports are asynchronous jobs. One outbound call gets `min(3 s, remaining − 50 ms)` and is not sent with less than 50 ms left (`DEADLINE_EXCEEDED` / `DEADLINE_BUDGET_EXHAUSTED`); a database statement gets `min(5 s, remaining)`.
- **A gRPC method is retried only if its contract declares it free of side effects or idempotent** (`idempotency_level`), only on `UNAVAILABLE`, at most 3 attempts, through the service configuration every SDK generates from the contract.
- **A retry budget per connection** (gRPC retry throttling, about 10 % of normal traffic) stops retries when a dependency is broadly down; connections are per member, so one member's storm cannot spend another's budget.
- **Bulkheads instead of circuit breakers**: at most 64 concurrent outbound calls per (member, dependency), failing at once with `RESOURCE_EXHAUSTED` / `OUTBOUND_LIMIT`; a connection budget per member (`DB_POOL_EXHAUSTED`).
- **One layer retries.** Code never wraps a retry loop around a call that already retries; a higher layer that retries (a reconciler, a redelivered event) reuses the same idempotency key.

## Why

On one machine, with one instance of each component, there is nothing for a breaker to route around; what protects users is a bounded wait, which deadlines give, and bounded damage, which bulkheads give. The budget and connection rotation keep behaving correctly when replicas are added. When the contract decides what may be retried, nobody has to judge per call whether a retry is safe, and nested retries, which multiply (three layers of three attempts make 27 calls in an outage), cannot appear. Before 3.0.0 no timeout was set anywhere, and one hung dependency could hang login and the whole mobile path.

## What this rules out

- A call, statement, handler or job without a deadline; a child call given more time than its caller has
- Retrying a non-idempotent method, or retrying on any code other than `UNAVAILABLE`
- A component's own retry loop around a runtime call; hedging
- A circuit breaker library in a component; queueing calls when the bulkhead is full

## Revisit only if

Several nodes show partial failures (some replicas slow while others are fine): add an interceptor-level breaker or outlier detection with headless balancing. Or a fixed outbound limit measurably misfits a dependency: make that dependency's limit adaptive.

Full analysis: [16-deadlines-and-retries.md, Choice](../../04-foundations/16-deadlines-and-retries.md#choice).
