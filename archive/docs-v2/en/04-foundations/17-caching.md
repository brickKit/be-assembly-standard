[English](17-caching.md) · [中文](../../zh/04-foundations/17-caching.md)

# Caching

Where data is kept closer to its reader than the owner's table, and why the project runs no cache server. For whoever is about to add a cache, a snapshot or Redis, or wants to know why a value is a few seconds old.

## Scope

Every way of answering a read without asking the data's owner at that moment:

- in-process caches inside one member (display names, lookups);
- the permission bundle and the identity key set (JWKS) every process holds;
- snapshots of another component's data, kept as tables in the reader's own schema and refreshed by events;
- the authorization projection (`besdk_authz_acl`) each component keeps in its own schema ([20-authorization-provider.md](20-authorization-provider.md));
- summary tables for reports.

Not covered: HTTP caching at the gateway (planned `18-edge.md`), browser caching, PostgreSQL's own buffers.

## Choice

**There is no cache server. A cache lives inside one member's process, through the SDK, with a capacity limit, a TTL, single-flight loading, metrics and event-driven invalidation.** Anything that must be shared between replicas or survive a restart is a table in the component's own schema, not a cache.

Every need the project has, and where it is met:

| Need | Where it lives | Invalidation | Shared cache needed? |
|---|---|---|---|
| Permission bundle | process memory, one per process (one per shell) | conditional GET with `ETag` every 15 s, plus the `infra.authz.changed.v1` poke | no |
| JWKS | process memory | refetch when a token carries an unknown `kid`, rate-limited | no |
| Master-data snapshots (customer, product) | a table in the reader's schema | events from the owner | no |
| Authorization projection | `besdk_authz_acl` in the component's schema | changefeed pull plus poke | no |
| Display names from `BatchGet` | optional in-process cache, TTL 30 s | event from the owner, or TTL | no |
| Rate limiting | the edge (planned `18-edge.md`); application quotas as PostgreSQL counting windows | window end | no on one machine; with several gateway instances the limit is split per instance |
| Sessions | stateless JWT; refresh tokens in iam's PostgreSQL | rotation | no |
| Idempotency keys | `besdk_idempotency` table | retention period | no |
| Distributed locks | row locks, transaction-level advisory locks, job leases ([10-local-transactions.md](10-local-transactions.md), [19-background-jobs.md](19-background-jobs.md)) | transaction end, lease expiry | no |
| Third-party access tokens (DingTalk) | a row in the component's schema plus an in-process mutex; refresh across replicas under a transaction-level advisory lock | expiry | no |
| Hot reads and reports | summary tables | events or scheduled jobs | no |

**Status**: in place for the bundle, JWKS, snapshots and summary tables. Decided for the SDK cache helper, its metrics, the global-map gate and the conformance suite (they land with the 3.0.0 sweep); until then a component that needs an in-process cache writes a bounded one per module and never a package-level map.

## Port contract

The cache is a port with one adapter (in-process). The contract is the behaviour every SDK implements, in any language:

- **Identity.** A cache has a name unique within its component, a maximum entry count and a TTL. All three are required; an unbounded cache is not allowed.
- **Operations.** get, set, delete, flush. A get on a missing or expired entry calls the loader; concurrent gets for the same missing key call the loader once and share the result (single flight). A loader error is returned to every waiter and is not cached.
- **Eviction.** Least recently used beyond the entry count; expiry by TTL measured from the set.
- **Invalidation.** A cache may be bound to an event subject; on each event the entry for the event's aggregate id is deleted (or the whole cache flushed, if the binding says so). Invalidation is best effort and the TTL is the upper bound of staleness.
- **Isolation.** One instance per member. In a shell two members with a cache of the same name see two different caches. A cache never lives in a package-level or global variable.
- **Metrics** (Prometheus, with the `component` label every series carries, see [23-observability.md](23-observability.md)): `be_cache_hits_total{name}`, `be_cache_misses_total{name}`, `be_cache_evictions_total{name}`, `be_cache_entries{name}`.
- **Never cached across requests.** Authorization decisions: a local permission decision, a remote `Check` answer and a resource-level `_authz/check` answer are remembered for the current request at most. A cached decision keeps allowing after a revocation, and the saving is one in-memory lookup.

## Alternatives

| | In-process LRU (chosen) | Valkey / Redis | Memcached | PostgreSQL unlogged table | PostgreSQL table + `LISTEN`/`NOTIFY` |
|---|---|---|---|---|---|
| New service to run | none | one stateful service | one service | none | none |
| Shared between replicas | no | yes | yes | yes | yes |
| Survives a restart | no | optional | no | no (truncated after a crash) | yes |
| Invalidation | event or poke, TTL | TTL, pub/sub | TTL | sweep | `NOTIFY` |
| In a shell | safe when created per member | keys need a member prefix | keys need a member prefix | schema isolation | schema isolation |
| Cost of a read | memory lookup | network round trip | network round trip | a query | a query |

## Why this choice

- Customers deploy on one machine with limited resources; every extra base service has to be installed, backed up, secured and watched ([0201](../02-decisions/02-permissions/0201-no-redis.md)).
- Going through the table above, no need requires a cache shared between processes: each one already has a home in PostgreSQL or in process memory.
- Decision caches are the most error-prone cache there is: a revoked share or role keeps working until the entry expires. Keeping decisions uncached removes the whole class.
- Created per member, an in-process cache is merge-safe by construction: a shell behaves exactly like the members run alone.

## Why not the others

- **Valkey / Redis**: buys sharing between replicas that no current need asks for, at the price of a stateful service, a network hop on every read and a distributed invalidation problem. In a shell every key would need a member prefix to stay merge-safe.
- **Memcached**: the same costs as Redis with fewer guarantees.
- **PostgreSQL unlogged table**: loses its rows after a crash and needs a sweeper, and a read from it costs about as much as reading the owner's own table.
- **`LISTEN`/`NOTIFY`**: needs a long-lived session-level connection per listener, which a transaction-mode pooler does not give ([03-database.md](03-database.md)); the poke over NATS already does this job.

## When to switch

Both conditions of [0201](../02-decisions/02-permissions/0201-no-redis.md)'s revisit clause must hold: a measured workload cannot be served by PostgreSQL plus in-process memory, with the numbers written down, and the case covers more than one component. One more trigger is added: in a multi-replica deployment, the business judges the inconsistency window between the replicas' caches (at most one TTL) unacceptable for a named read.

## How to switch

1. Rewrite 0201 first; the decision wins over this document.
2. Add a Valkey adapter behind the same cache contract inside each official SDK. Nothing in component code changes: components only ever see the cache contract.
3. Add a shared key `CACHE_URL` in `config/vars.yaml`; its scheme (`redis://`) selects the adapter, and its absence keeps the in-process adapter.
4. Prefix every key with the member's component ID and the cache name, so members in one shell stay apart.
5. Run the cache conformance suite against the new adapter; it must pass the same cases as the in-process one.

## Conformance tests

Suite `tools/be-acceptance/conformance/cache/` (decided), run against every official SDK (layout in [01-ports-and-adapters.md](01-ports-and-adapters.md)):

- beyond the entry count, the least recently used entry is evicted;
- after the TTL the loader runs again, and concurrent misses for one key call it exactly once;
- after a bound event arrives, the next read calls the loader;
- in a shell, two members' caches with the same name do not see each other's entries;
- a loader error reaches every waiter and is not cached.

Gate `module-global-cache-scan` (decided) warns when module code uses a package-level map or concurrent map as a cache; it is shown red once against a deliberately bad sample before it is trusted ([06-testing.md](../01-conventions/06-testing.md#gates-and-cross-cutting-checks)).

## Decision records

- [0201 No Redis, no cache server](../02-decisions/02-permissions/0201-no-redis.md): this document carries its analysis: no cache server; caches live only in process, through the SDK.
- [0202 Permissions are decided locally](../02-decisions/02-permissions/0202-local-permission-bundle.md): the bundle is the one cache every process must hold.

## Known limits

- With several replicas, two replicas may answer the same read differently for up to one TTL.
- In a shell, each member's cache memory is counted separately but not enforced by the operating system; a member's entry limit is its budget.
- A cache starts empty after every restart; the first requests after a deploy pay the loader cost.
- Display names may be up to 30 seconds old; anything that must be exact is read from its owner or from a snapshot table.
