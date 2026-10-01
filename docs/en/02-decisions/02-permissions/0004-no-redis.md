[English](0004-no-redis.md) · [中文](0004-no-redis.zh.md)

# 0004 No Redis

## Decision

The project runs no Redis and no other cache server.

## Why

Everything Redis is usually brought in for is already covered: identity is a stateless JWT, permissions are an in-process map ([0005](0005-local-permission-bundle.md)), data owned by other components is kept as a local summary refreshed by events, concurrency is a PostgreSQL row lock, and rate limiting belongs to the gateway. Customers deploy on one machine with limited resources; every additional base service is one more thing to install, back up, secure and watch.

## What this rules out

- "Add a cache layer" / "put Redis in front of this query"
- Sessions or refresh tokens stored in Redis
- Distributed locks, counters or sequence numbers in Redis
- Caching permissions or bundles in Redis — slower than the in-process map it would replace
- Rate limiting in application code backed by Redis
- Redis as a message queue (events go over NATS)

## Revisit only if

A measured workload cannot be served by PostgreSQL plus in-process memory, with the numbers written down — and the case covers more than one component.
