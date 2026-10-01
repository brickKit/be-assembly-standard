[English](05-data.md) · [中文](../../zh/01-conventions/05-data.md)

# Data conventions

Where the data in this project comes from. There are two independent paths, seed data for people and test data for automated tests, and one principle behind both: cover as many scenarios as possible, and when a dependency lacks something, fix it at the source. What is seeded today is listed in [../03-seed-data.md](../03-seed-data.md).

## Two paths, never shared

| Path | Used by | How it is made | Lifetime | Shared? |
|---|---|---|---|---|
| **Test data** | every automated test: L1–L4, FE-1–FE-4 | created fresh on each run, made unique with a timestamp or random suffix | never cleaned up; it may pile up, the next run gets a new suffix | **never**: no test depends on a row another test or another run left behind |
| **Cross-component test data** | cross-component tests | the test calls the dependency's real gRPC or REST API and creates the shape it needs there | same as test data | same as test data |
| **Seed data** (`make seed`) | people: exploring, demos, a new component with data from day one | fixed `idempotency_key`, claim-first; a rerun creates nothing new | persistent; removed with `make seed-clean` or `make db-reset` | components may look up and reuse each other's seed data; a test never depends on it |

Wiping seed data never turns a test red, and a test never changes the data a person is exploring. Mixed, "why did this test turn red" has two unrelated causes with two unrelated investigations.

**They are two physical databases** in the same PostgreSQL instance: tests use `brickkit_test_db` (`TEST_PG_DSN`, created and refreshed by `make test-db-init`), the running project uses `brickkit_db`. Both have the same schemas; their data never meets. Some tests write to reference rows a migration seeds (a default warehouse, a default legal entity); in a shared database every test run would change the demo data, whether or not a container is running.

**No throwaway database.** Partitioned tables and `SET LOCAL ROLE` / `search_path` don't fit an embedded engine, and swapping the database contradicts "integration means real infrastructure". The answer to slow, cross-contaminating fixtures is disposable data: a unique suffix and no cleanup. That is the long-term shape, not a stopgap.

## Cover as many scenarios as possible

- **Seed data aims at many and complete**: every state of every state machine, every branch, every failure path, every data-scope dimension has data that triggers it. Volume and variety are the point.
- **Test data aims at few and exact**: the least data that verifies one assertion. The exception is property tests, whose many random inputs are there to hit edges, not to look complete.
- The floor is the same for both: **no component has only happy-path data or assertions.**

## When a dependency lacks what you need

**In a test.** The test needs a dependency to hold some shape of data (a customer with zero credit limit, a disabled product, an opportunity in a given stage):

1. Create it through the dependency's real API, in the test.
2. If the dependency's contract has no way to create that shape, **add the capability to the dependency first** (additively, as any contract change), then create the data through it. Don't work around it, don't skip the scenario.
3. Writing into another component's database with raw SQL is not allowed in tests. It couples the test to the other component outside its contract; the contract can change and the test will never say so.

**In seed data.** A downstream component that needs a combination the upstream seed doesn't have (a disabled customer in the South China department) adds it to the upstream component's seed script itself. It doesn't make do downstream, and it doesn't wait. The data is fake, variations cost nothing, and rich upstream data is what gives downstream something to choose from.

## Seed data rules

Seed data also serves testing: walking through the running system with real-looking data is how a whole chain is checked by a person, and that counts as much as automated tests. The data is fake from start to finish, which is a freedom: push richness towards its upper bound.

**What seed data must serve, at once**: every branch and failure path can be triggered; one component plus its dependencies can be checked on its own; the full chain of one component works before it ships; the whole project works from every angle (permission boundaries, events, compensation) before it ships; and a person opening any page finds something to look at.

**What "lots of data" does not give you by itself**:

- **Data-scope dimensions exist for real**: several departments, owners, warehouses and legal entities, with test accounts in each. Data all owned by one all-powerful account makes data scoping invisible.
- **Enough rows to page**: a list with cursor paging and five rows never shows a second page.
- **Spread in time**: rows across past dates (set absolutely, `now() - interval`, so reruns don't drift), so "last N days" queries, trends and partition maintenance have something to work on.
- **Negative cases**: disabled records, zero stock, overdue balances, rejected requests.
- **Discoverable**: [../03-seed-data.md](../03-seed-data.md) lists what each component seeds, how much and who owns it. Update it in the same commit as the seed.

**Ownership and collaboration**:

- **Each component owns its seed data** (`make seed` in its own repository). A central script only works when everything runs together, and a component started alone would have nothing.
- **A component's `make seed` first runs the seeds of everything it declares as a dependency**, required or optional alike, then its own part. Run against one component, it produces a complete set. A dependency that isn't reachable is skipped, not a failure.
- **The handoff is the component's own idempotency table.** A seed script loads data; it doesn't print IDs. Whoever needs an ID looks it up by the fixed `idempotency_key`. With `psql`, use `-tA -q`, or the `SET` acknowledgement ends up in the captured value.
- **A seed script that links to another component's seeded rows puts the linked row's real ID into its own idempotency key.** Those IDs change on every clean and reseed; a key built from a position stays bound to the first round's IDs, and the link silently points at rows that no longer exist.
- **Seed data is a light contract.** An identifier another component looks up is only ever added to, never deleted or given a new meaning.
- **Redundancy is fine.** Two components may both seed a "manufacturing customer"; reusing what exists is cheaper than coordinating ownership.
- **Delete is not reset.** A component with an append-only table (a ledger, a locked accounting period) has no `make seed-clean`, only `make db-reset` (`migrate down`, then `up`): row-by-row deletion can't restore it, and sequences don't roll back. A component whose rows can be deleted safely may have both; prefer `seed-clean`, which leaves other data alone.
- **Negative paths come from real business failures.** When a component deliberately exposes no write API for something (an exception task, a notification record), seed it by making a real business flow fail (an order over the credit limit), never by forging the write the contract forbids.
- Every human-readable name in seed data starts with `「本地测试」`, so it is recognisable on any screen; `seed-clean` finds its own rows by that prefix plus the fixed keys.
- `grpcurl` prints proto fields in lower camel case (`reservationId`); hand-written REST JSON uses snake case. Check the real output before parsing a field with an underscore.

**Credentials never go into anything that runs on every deployment.**

- Reference data every deployment needs (a default warehouse, a default legal entity and chart of accounts, units of measure) belongs in a migration: it is part of the product.
- Test accounts, test roles and test applications belong only in `make seed`, which runs by hand and never in a deployment or CI flow. A test account in a migration is a backdoor with a known password in every customer's system.
- The first administrator of a real deployment comes from configuration: the deployer puts their own identity in infra/authz's bootstrap setting, and the component grants the admin role idempotently at start. That is a different thing from the all-permissions test role local work needs.

## Test data rules

- Generation and lifetime: unique suffix, no cleanup (the first section).
- Consumer tests that trigger the consumer themselves use a private subject and a unique `aggregate_id` ([06-testing.md](06-testing.md#l4-integration-tests)).
- A shape of data the dependency's contract can't produce: [When a dependency lacks what you need](#when-a-dependency-lacks-what-you-need).
- Test data ignores the seed-only concerns (paging, time spread, discoverability); it matches its own assertion and nothing else.
