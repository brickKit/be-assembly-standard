[English](testing.md) · [中文](testing.zh.md)

# Testing conventions

What tests exist in this project, what each one tests and does not test, when it is written and how it runs. The goal is one thing: tests written by an AI must catch regressions, not look numerous while guarding nothing. A test that fails that goal is worse than none, because it makes something look covered. Where test data comes from is in [data.md](data.md).

## Layers at a glance

| Layer | Name | Tests | Written |
|---|---|---|---|
| **L1** | Contract | the contract has no breaking change; every rpc is really callable across processes | when the contract is written |
| **L2** | Business rule | the specification: invariants, legal state transitions, idempotency, conclusions at the edges | before the implementation |
| **L3** | Unit | this implementation's branches: error paths, empty values, concurrency, SQL assembly | after the implementation |
| **L4** | Integration | real PostgreSQL, NATS and gRPC; migrations rerun; calls to real dependencies | once the implementation is complete |
| **FE-1** | Frontend unit | pure functions, composables, stores; network mocked | as soon as the code exists |
| **FE-2** | Frontend component | shared components used by several pages | as soon as the code exists |
| **FE-3** | End-to-end | a real browser on the real backend, one complete business flow | once the page's interaction is stable |
| **FE-4** | Visual regression | spacing, density and component usage consistent across pages | with FE-3 |

Cross-cutting, equally mandatory: data-scope boundary tests (every component with a `data_scopes` dimension), event-contract compatibility (checked by `make gates`), concurrency correctness of SDK primitives (in `be-sdk-*`), and cross-component tests (every component with a required dependency).

Four principles run through all of it:

1. **Specification before implementation.** L2 says what the feature should do, not what the code does.
2. **Real over simulated.** A mock proves that a call happened, never that its result was right.
3. **What can be mechanised is mechanised.** A rule that relies on someone remembering it becomes a gate or a script.
4. **Each layer tests only its own part.** The same assertion in two layers is one more place to keep in sync, and it won't be.

## Red-green and the iron rule

One cycle:

1. Write one failing test (or a small group of closely related ones).
2. Run it and confirm it is red **because the feature does not exist yet**, not because of a compile error, a broken mock or a bug in the test.
3. Write the least code that turns it green.
4. Run the whole suite; nothing else turned red.
5. Refactor if useful, and run the suite again.
6. Commit, saying which business conclusion the cycle locked in.

**Never change a test to make it pass.**

| Situation | What to do |
|---|---|
| Red because the implementation is wrong | Fix the implementation. This is the default, without exceptions. |
| Red because the test asserts a wrong business conclusion | Stop, say in one sentence where and why the assertion is wrong, and change it in a commit of its own. |
| An L2 test is in the way | The implementation, or the understanding of the requirement, is almost always what's wrong. Fix the design first, then the test, never the other way round. |

Never comment a test out, never add `t.Skip` or an equivalent marker, never loosen an assertion until it passes. Each turns a gate into decoration, and once one gate is decoration no green can be trusted.

## When stuck

Three rounds on the same cycle without green: take these in order.

| # | Way out | What to do |
|---|---|---|
| 1 | **Cut the step smaller** | The step is usually solving two or three things at once. Split the test and turn one small assertion green at a time. |
| 2 | **Read a reference implementation** | Read it, come back, think it through, then write your own ([reference-implementations.md](reference-implementations.md)). Never copy. |
| 3 | **Stop and say what is stuck** | What you expected, what happened, what you tried, which layer you suspect. Hand it to a human. |

The third is the correct action, not a failure. A workaround taken once gets copied next time, and after two copies the rule is gone.

## L1 contract tests

The contract has no breaking change (`make contract-check`), and every rpc is called once across processes: a real server, a real client. L1 does not care whether the result is right, only that the endpoint exists, is reachable and its fields are intact.

## L2 business-rule tests

L2 tests invariants ("stock never goes negative", "available + reserved = total"), legal state transitions ("a completed reservation cannot be cancelled"), idempotency (the same `idempotency_key` N times gives the result of one) and business conclusions at the edges (zero quantity, zero amount, empty list).

**The test for which layer a test belongs to: if this feature's implementation were deleted and rewritten in another language, should the test still hold?** Yes → L2. No, because it checks a detail of this implementation → L3.

- **Core transactional components** (stock, money, payroll, commission: anywhere one mistake is a business incident) write L2 as **property tests**: a human states the invariants, the framework generates random inputs to attack them (`rapid` / `gopter` in Go, `hypothesis` in Python). Example-only tests never find the bug that needs a particular sequence of operations.
- **Idempotency tests include concurrency.** Several goroutines or coroutines send the same key at the same moment, and exactly one executes. Serial replay alone never catches "check, then insert".
- **Data-scope tests prove that someone else's data is invisible**, not only that your own is visible. Create two rows owned by different identities (owner, org, warehouse, legal entity), query as one, and assert that none of the other's rows come back. "An authorised user sees data" and "a user without permission sees nothing" both pass on code that returns the whole table.

## L3 unit tests

L3 tests the branches of this implementation: error paths, nil pointers and empty strings, concurrent write conflicts, SQL assembly, every validation branch. It does not repeat conclusions L2 already covers. Write it after the implementation, or alongside it: an `if err != nil` branch gets its test when it is written.

## L4 integration tests

- End to end on real PostgreSQL, NATS and gRPC. `/healthz` reports only the process. Every migration runs twice in a row and succeeds both times.
- **A component with down migrations has run `migrate down` then `up` on a real database at least once**, and so has any `make db-reset` before it ships. Down scripts run in reverse order, and a down script that deletes reference rows an earlier table still points to only fails when it is executed; review does not catch it.
- **Consumer tests that publish their own triggering event use a private subject** (`test.<base>.<nanoseconds>`): a real container subscribed to the production subject would receive the same message, and the assertion might read its result. A test that checks *which* subject the code publishes to uses the real subject.
- **Consumer tests use a unique `aggregate_id`.** Deduplication on `(subject, aggregate_id, version)` is permanent; with a fixed ID the second run is swallowed as already processed.
- **Never use a mock to show that a cross-component call happened.** It stays green when the call sends wrong arguments or ignores the returned error. What happens between components is L4's job, with two real processes.
- Data is created fresh for each run with a unique suffix and never cleaned up; no shared fixed dataset, no embedded or throwaway database ([data.md](data.md#two-paths-never-shared)).

## Cross-component tests

A cross-component test makes this component really call its required dependencies. `make test-cross ID=<scope>/<name>` runs only this component's tests, with each dependency's address bridged to the host from the real dependency containers; the test process stays on the host, so build cache and race detection work as usual.

- Only this component and its dependency tree need to run: `brickkit up --focus <id>` first. That turns local mode on and `brickkit up --all` leaves it on, so edits to `deploy.yaml` take effect only after `brickkit local off` or `brickkit local refresh` ([development-workflow.md](development-workflow.md#running-it-for-real)).
- A name filter runs only the tests between two particular components; that is why cross-component tests are named after the other component (see the naming section below).
- The scope is the synchronous call direction. Another component consuming this component's events goes through the event bus and follows the consumer rules above.
- Data the test needs from a dependency is created through the dependency's real API, in the test ([data.md](data.md#when-a-dependency-lacks-what-you-need)).

## Gates and cross-cutting checks

- **Authentication** ("no token is rejected", "a token without the permission is rejected") is tested once in the SDK. A gate checks that every external route goes through it (no bare routes); each component only tests its own data-scope filtering.
- **Event contracts** only grow; `make gates` compares each component's event files with their history.
- **SDK primitives** used by many instances at once (the outbox pump, idempotency claims, the pool) have at least one test with several instances running concurrently, checking that each item is processed exactly once. L1–L4 all assume one process and cannot find these bugs.
- **A new gate is shown red once** against a deliberate violation placed where real code lives (nested directories included) before its green is trusted. A gate that never saw a violation may be scanning nothing.
- When a gate fails, read its output first; it names the rule and the file.

## Frontend tests

The same thinking with different tools: specification apart from implementation, shared things before one-off things, real environments before simulated ones.

- **FE-1** tests what the logic computes for a given input: pure functions, composables, stores, with network requests mocked.
- **FE-2** tests shared components (tables, page templates, generic cards). A broken shared component breaks every page that uses it, so these come before a single page's own components.
- **FE-3** runs a real browser against the real backend through a whole business flow. PC and mobile share the tooling with different device profiles. It is written once a page's interaction has stabilised; before that every UI change rewrites its selectors. Name each test after the business flow it verifies.
- **FE-4** is an assertion style inside FE-3: a screenshot comparison at key pages as the flow passes them, with an automatic pixel diff. The baseline changes with intended UI changes; only a failed comparison needs someone to look at images.
- **Ask the user before running FE-3 or FE-4.** State which flows and pages the run covers and wait for the go-ahead. The cost is in writing and debugging (screenshots to find selectors and diagnose failures), not in running a stable suite. Prefer the accessibility-tree snapshot over screenshots, read the text error and trace before taking a screenshot, and let a human record key paths where possible.
- **Contract drift is removed by generation, not by tests**: frontend types and request functions are generated from the contracts, so the type checker catches drift at compile time.

## Running tests

| Granularity | When | Backend | Frontend |
|---|---|---|---|
| **Everything** | before a deployment, before a release batch | `make gates`, `make lint`, `make test` in every component, `make tier0` after `brickkit up` | every package's tests from the root |
| **One component** | a component or a feature is finished | `make test`; `make test-cross ID=<scope>/<name>` for its cross-component tests | one package |
| **Part of a component** | iterating on a feature | `go test -run <name>`, `pytest -k <name>` | `vitest <pattern>`, watch mode |

Every component has these commands, and they really run:

| Command | Does |
|---|---|
| `make test` | all L2 and L3 tests, with race detection |
| `make migrate-idempotent` | every migration twice in a row |
| `make contract-check` | breaking-change check of the contracts |
| `make module-check` | the merge-safety rules of [backend.md](backend.md#merge-safety) |
| `make smoke` | `brickkit up --dry-run` from the project root: the graph including this component resolves and the files generate, nothing starts |
| `make seed`, `make seed-clean` or `make db-reset` | demo data and undoing it ([data.md](data.md#seed-data-rules)) |

L4 and consumer tests point at the test database, `TEST_PG_DSN` → `brickkit_test_db`, created and refreshed by `make test-db-init`; never at the demo database `brickkit_db`.

## Naming

| Rule | Applies to | Why |
|---|---|---|
| The name states the business conclusion or the branch; no numbering | L2, L3 | you know what it tests without opening it |
| Property tests carry `Property` in the name | L2 property tests | the reader knows random inputs back the assertion |
| A cross-component test names the other component | cross-component tests | a name filter runs the tests between two components |
| An end-to-end test names the business flow, not the button | FE-3, FE-4 | a filter selects by flow |

The rules apply to new tests; existing ones are renamed only when touched anyway.

## What a human reviews in tests

Only whether the list of invariants in the L2 tests is complete: every invariant this logic should have is written down. A gate runs only the tests that exist; an invariant nobody thought of is never checked, however green the gates are. Business code line by line, L3 tests and build scripts are left to the gates.
