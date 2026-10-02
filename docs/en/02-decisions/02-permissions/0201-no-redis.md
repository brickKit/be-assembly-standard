[English](0201-no-redis.md) · [中文](../../../zh/02-decisions/02-permissions/0201-no-redis.md)

# 0201 No Redis, no cache server

**Status**: revised for 3.0.0 (caches live only in process, through the SDK); decided, lands with the 3.0.0 sweep.

## Decision

The project runs no Redis and no other cache server. A cache lives inside one member's process and is created through the SDK's cache helper, with a capacity limit, a TTL, single-flight loading, metrics and event-driven invalidation. Anything that must be shared between replicas or survive a restart is a table in the component's own schema, not a cache.

## Why

Everything Redis is usually brought in for is already covered: identity is a stateless JWT, permissions are an in-process bundle ([0202](0202-local-permission-bundle.md)), data owned by other components is kept as a local snapshot refreshed by events, concurrency is a row lock, a transaction-level advisory lock or a job lease, idempotency keys are a table, and rate limiting belongs to the edge. Customers deploy on one machine with limited resources; every additional base service is one more thing to install, back up, secure and watch. A cache created per member is merge-safe by construction: a shell behaves exactly like its members run alone.

## What this rules out

- "Add a cache layer" / "put Redis in front of this query"
- Sessions or refresh tokens stored in Redis
- Distributed locks, counters or sequence numbers in Redis
- Caching permissions, bundles or authorization decisions in Redis, or caching a `Can` answer across requests anywhere: a revoked share would keep working until the entry expires
- A package-level map or an unbounded cache in a module instead of the SDK's helper
- Rate limiting in application code backed by Redis
- Redis as a message queue (events go over the bus, [0106](../01-architecture/0106-infrastructure-is-not-a-component.md))

## Revisit only if

A measured workload cannot be served by PostgreSQL plus in-process memory, with the numbers written down, and the case covers more than one component; or, with several replicas, the business judges the window between the replicas' caches (at most one TTL) unacceptable for a named read.

Full analysis: [17-caching.md, Choice](../../04-foundations/17-caching.md#choice).
