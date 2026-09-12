# BrickEnterprise Testing Standard

This specification defines everything about "testing" in this project: what types of tests exist, what each type tests and doesn't test, when to write it, how to write it, what tool runs it, and what a component's test infrastructure should look like. **This is the only testing specification to follow** — before writing code, before writing a test, confirm which section of this document covers what you're about to do, then follow it. Where the data a test needs comes from, and how components collaborate on data, is a separate specification: [`05-data-construction-standard.md`](05-data-construction-standard.md).

There is exactly one goal: **make the tests an AI writes actually catch regressions, instead of looking numerous while guarding nothing.** A test that fails this goal is worse than no test at all — it creates the illusion that "this is covered."

---

## 1. Overview of the Testing System

This project's testing splits into two main lines (backend / frontend), plus a set of cross-cutting categories (not owned by any single component, but equally mandatory):

| Type | Short name | Belongs to | What it tests | Who writes it | When to write it |
|---|---|---|---|---|---|
| Contract test | **L1** | Backend | No breaking change in the contract itself; every rpc is callable across processes | The component itself | The moment the contract is written |
| Business-rule test | **L2** | Backend | **The spec**: invariants, legal state-machine transitions, idempotency, business conclusions at boundary cases | The component itself | Before the implementation |
| Unit test | **L3** | Backend | Branches of **this specific implementation**: error paths, nulls, concurrency, whether the SQL is assembled correctly | The component itself | After the implementation |
| Integration test | **L4** | Backend | Real PG / real NATS / real gRPC end-to-end; migrations rerun cleanly; cross-component calls hit real dependencies | The component itself | After the implementation is complete |
| Unit/logic test | **FE-1** | Frontend | Pure functions, composables, stores — network requests mocked out | The component itself | Add it as soon as it's written |
| Component test | **FE-2** | Frontend | Shared components reused across multiple business pages | The component itself | Add it as soon as it's written |
| End-to-end test | **FE-3** | Frontend | Real browser + real backend, covering a complete business flow | The component itself | Once the page has stabilized |
| Visual regression test | **FE-4** | Frontend | Consistent spacing/density/component usage across pages | The component itself | Same batch as FE-3 |
| Permission/data-scope boundary test | — | Backend, cross-cutting | "Can see your own data, can't see someone else's" | The component itself | Mandatory once `data_scopes` is declared |
| Event contract test | — | Assembly layer, cross-cutting | `events/*.json` is additive-only, never deletes or changes | Automatically compared by a gate | Every time an event contract changes |
| SDK concurrency-correctness test | — | Language base library, cross-cutting | Multiple instances concurrently using the same SDK primitive (Outbox pump, idempotency-table operations) don't misbehave | `be-sdk-*` itself | At least one per cross-cutting primitive |
| Cross-component test | — | Backend, cross-cutting tooling | This component really calling its strong dependencies, no longer mocked or skipped | The component itself, run via `make test-cross` | Required for every component with a strong-dependency edge |

**Four overarching principles, running through the whole document:**

1. **Spec before implementation**: an L2 test is written before the implementation, and tests "what this feature should do," not "what this code does." Writing the implementation first and adding tests afterward inevitably produces "tests that describe the existing implementation" — that guards against regression, but guards against nothing when the requirement was misunderstood from the start.
2. **Real over simulated**: prefer real Postgres/NATS/gRPC over a mock wherever possible. The most a mock can prove is "the call happened" — it can never prove "the call's result was correct," and "was the result correct" is the entire reason a test exists.
3. **Whatever criterion can be mechanized, must be mechanized**: any rule that relies on "a human remembering to check it" must, if it's possible to express as a `make` gate or a script check, be expressed that way — no human can hold every rule in their head across dozens of components; a gate can.
4. **A test is a specification document, not a production metric**: one layer re-testing something another layer already tests isn't "extra safety" — it's one more place that now needs to be kept in sync in the future, and won't be. Each layer tests only the part that's actually its job.

---

## 2. The Test-Driven Development Flow

### 2.1 The order a feature goes through, from design to delivery

```
① Design the business logic     Write down clearly what to do and why
② Check a reference implementation   Design your own version first; only look at how a real project does it for the parts you can't work out — don't imagine it out of thin air
③ Write the contract            .proto / .openapi.yaml / events/*.json — turn the design into executable types
④ Write the L2 tests            Invariants, state-transition tables, property tests — ⚠️ before the implementation, testing the spec
⑤ Write the implementation      Red → green → refactor, one rule per round, one commit per round
⑥ Add L3 tests                  Boundaries, error paths, concurrency — after the implementation, testing this implementation
⑦ Integrate + run the gates     Real PG / real NATS / grpcurl, run every gate
```

⚠️ **Neither of these two orderings — ③ before ④, ④ before ⑤ — may be reversed:**

- **Contract before test**: a test needs to reference the types the contract generates. Without a contract you can only test `map[string]any`, and that kind of test is entirely voided the moment the implementation is refactored.
- **Test before implementation**: this is the only line separating "spec" from "implementation." A test written after the implementation inevitably describes whatever code was already written — it can guard against future breakage, but it can never guard against "this code never matched the requirement, from day one."

### 2.2 Red-Green-Refactor: one cycle per session, one commit per cycle

```
1. Write one failing test (or a small group of closely-related ones)
2. Run it, confirm it's red — ⚠️ and confirm the reason it's red is "the feature isn't implemented yet," not a bug in the test itself, a compile failure, or a misconfigured mock
3. Write the minimum implementation to make it green
4. Run the full test suite, confirm nothing else turned red
5. Refactor (optional); rerun the full suite afterward
6. Commit: one sentence stating what business conclusion this round locked in — not "which files changed"
```

### 2.3 Iron Rule: Never Change a Test Just to Make It Pass

This is the single most commonly violated rule, and violators always find a reason that sounds plausible ("this assertion was too strict," "the actual behavior is actually correct"). The decision table:

| Situation | What to do |
|---|---|
| The test is red because the implementation is wrong | Fix the implementation. **This is the default case, with no exceptions** |
| The test is red because the test itself really is wrong (it asserted an incorrect business conclusion) | Stop first, and state in one sentence exactly where and why the original assertion was wrong. Changing a test gets its **own separate commit** — never mixed in with an implementation change |
| **An L2 business-rule test is blocking you** | **It is almost always the implementation, or the understanding of the requirement, that's wrong — not the test.** L2 is the spec — when it's in the way, the design is what needs to change; fix the design first, then come back and change the test. Never do it the other way around |

**Three things that must never be done**: commenting out a test, adding `t.Skip` or an equivalent skip marker, loosening an assertion so it happens to pass. What these three share: they degrade a gate from "actually catches something" to "decoration" — and once one gate is decoration, nobody can trust any other gate's green either.

### 2.4 Stuck on the Same Cycle for Three Rounds With No Green: Three Escape Routes, in Order

| # | Route | What to actually do |
|---|---|---|
| 1 | **Cut the step smaller** | Three rounds without green usually isn't "hard" — it's this one step trying to solve two or three things at once. Split the test into smaller assertions, get one green at a time |
| 2 | **Go look at a reference implementation** | This is exactly the moment §2.1's "look only when you can't work it out" applies. Read it, come back, think it through yourself, then write it — **never copy it verbatim** |
| 3 | **Stop and state exactly what's stuck** | State "what I expected / what actually happened / what I've tried / which layer I suspect the problem is in," and hand it to a human to judge |

Route 3 is not a failure — it is the correct action. Once a problem can't be clearly stated, that's when to stop, not when to grit through and route around it. Route around it once, and next time someone hits something similar they'll copy that same shortcut — the rule is effectively dead within a couple of instances.

---

## 3. Backend Testing: The Four Layers in Detail (L1–L4)

### 3.1 L1 · Contract Test

**What it tests**: that the contract itself has no breaking change (compared automatically by a tool, e.g. `buf breaking` for `.proto`); that every single rpc is genuinely callable across processes (compiling isn't enough — a server must actually be started and a client must actually hit it once).

**What it doesn't test**: business behavior — L1 doesn't care at all whether a call's result is correct, only that "this endpoint exists, is reachable, and its fields haven't been broken."

**When to write it**: the moment the contract is written, without waiting for the implementation.

### 3.2 L2 · Business-Rule Tests — the Most Important of the Four Layers

**What it tests**: **the spec.** Specifically, four kinds of things:

- **Invariants**: properties that must hold at all times ("total inventory can never be negative," "available + reserved must always equal total").
- **Legal state-machine transitions**: which state transitions are allowed, and which aren't ("a completed reservation can't be cancelled again").
- **Idempotency**: replaying the same command with the same `idempotency_key` N times must produce a result identical to executing it once.
- **Business conclusions at boundary cases**: what "should happen" at boundaries like quantity zero, amount zero, an empty list.

**What it doesn't test**: implementation detail — which function got called, which table was used, how the internals are organized. An L2 test should still pass unmodified if the feature's entire implementation were torn down and rewritten in a different language, using a different data structure — as long as the externally observable behavior still matches the spec.

**The one-sentence criterion for which side of the line something falls on**:

> **If this feature's implementation were deleted entirely and rewritten from scratch in a different language, should this test still hold?**
> Should still hold → L2. Should not still hold (because it's testing some specific detail of this particular implementation) → L3.

Example (for an inventory-style component like `erp-inventory`):

```go
// L2: this is the spec. Swap the implementation from Go to Rust, from row-level locking to
// optimistic locking — it must still hold regardless.
func TestProperty_库存总数永不为负(t *testing.T) { /* property test, attacked with random operation sequences */ }
func TestProperty_available_reserved_之和恒等于total(t *testing.T) { /* … */ }
func Test状态机_已完结的预留不能再取消(t *testing.T) { /* transition edge */ }
func TestProperty_Reserve严格幂等(t *testing.T) { /* retry the same key n times, result must be identical */ }
```

```go
// L3: this is testing "this particular implementation." Change how the conditional update is
// written, and this test should change along with it — it is not the spec.
func Test条件更新_RowsAffected为0时返回库存不足错误(t *testing.T) { /* … */ }
func TestReserve_产品ID为空时返回InvalidArgument(t *testing.T) { /* … */ }
```

**⚠️ Mandatory requirement: L2 for a core transactional component must use property-based testing** (Example-only tests are not sufficient). "Core transactional component" means one touching inventory, funds, payroll, commissions — anywhere "getting it wrong once is a real business incident." The approach: a human defines the invariants, and a testing framework generates a large volume of random boundary inputs to attack the implementation (`rapid`/`gopter` for Go, `hypothesis` for Python). Example-only tests will never catch bugs that "only trigger under a specific sequence of operations" — and that class of bug is exactly the kind AI-generated code is most prone to leaving behind.

**⚠️ Idempotency tests must cover concurrency, not just "replay it once"**: when a command claims to be idempotent, the real risk was never "replaying it twice in sequence" — it's "two concurrent requests arriving with the same key at the same time." A correct claim-first idempotent implementation is an atomic `INSERT ... ON CONFLICT DO NOTHING` that only performs the real write once the claim succeeds; if the implementation instead "checks whether a row exists first, then inserts if it doesn't," two concurrent requests can both land in the "not found yet" window and each believe it's the one that should execute, each doing the work once. An L2 idempotency test must include a case where "multiple goroutines/coroutines call concurrently with the same key, and only one actually executes" — testing serial replay alone is not enough.

**⚠️ A permission/data-scope boundary test must verify "can't see someone else's," not just "can see what's rightfully mine"**: for any component that declares `data_scopes`, the common mistake is covering only two situations — "a person with permission can see the data" and "a person with zero permission sees nothing at all." **Neither situation proves the scope-filtering logic itself is correct**: code that incorrectly returns the entire table would still pass the "zero-permission user" test (it never even gets that far) and would also pass the "authorized user" test perfectly normally — both tests green, and the bug is still there. **The correct approach: really create two rows of data with different ownership (different `owner`/`org`/`warehouse`…), query using one of those identities, and assert that the response contains none of the other identity's data.** This is the only test shape that actually proves scope filtering works for this class of component — without it, the scope-filtering logic has effectively never been verified at all.

### 3.3 L3 · Unit Tests

**What it tests**: specific branches of this particular implementation — error paths, null pointers/empty strings, concurrent write conflicts, whether the SQL is assembled correctly, every `if` branch of parameter validation.

**What it doesn't test**: business conclusions already covered by L2 — repeating them here isn't extra safety, it's one more place that will need updating in the future, and typically only one of the two copies actually gets updated.

**When to write it**: after the implementation is done, or written alongside the implementation during the red-green cycle (e.g., the moment an `if err != nil` branch is written, immediately pair it with a test).

### 3.4 L4 · Integration Tests

**What it tests**: end-to-end, under real Postgres / real NATS / real gRPC; that database migrations rerun cleanly (the same `up` migration run twice in a row must both succeed — this is migration idempotency, not business-logic idempotency); that the health-check endpoint only reports whether this process itself is alive, checking no dependency at all (otherwise one dependency hiccupping drags down the reported health of every upstream component too).

**What it doesn't test**: every branch of business rules — that's L2's job; L4 runs slowly and failures are hard to localize, so stuffing business-branch testing into this layer only makes it both slow and hard to maintain.

**⚠️ Any component with a "down migration" must have had at least one real-machine run of `migrate down` then `up` — code review alone cannot judge whether a down script is correct.** Down migrations run in reverse version order, and a down script is easy to write under the assumption that "the table an earlier version created no longer exists by this point" — but the real order is exactly the opposite: an earlier version's table only gets cleaned up once its own down script runs, later. This class of problem only surfaces from actually executing `migrate down` once — code review can't catch it. Any component that offers `db-reset` (`migrate down` then `up`) as its way of wiping data must have had that command itself verified on real hardware before shipping.

**⚠️ Consumer tests have two rules of their own:**

1. **When constructing/publishing an event yourself to trigger a consumer, use a test-private subject, not a real production subject.** If a real container is actually running on the same machine and subscribed to that same production subject, the broadcast-style subscription mechanism delivers the message to both the real container and the test's temporary subscriber at once — whichever claims the dedup-table row first is the one whose output ends up in the database, and an assertion may end up reading someone else's result instead of the one this test actually triggered. The fix: swap the subject for a test-private name carrying a timestamp/random number (e.g. `test.<base>.<nanosecond-timestamp>`); the consumer logic itself should never branch on the subject for business purposes, which makes this swap entirely safe. **This applies only to "a test publishing an event itself to trigger a consumer."** A test that verifies "the business logic really did publish to the correct production subject" must use the real subject — it cannot get away with a private subject either.
2. **When a dedup table does monotonic deduplication on `(subject, aggregate_id, version)`, a test must use a unique `aggregate_id`, never a fixed string.** Once dedup logic takes effect it's permanent (that combination being "already processed" gets persisted) — if `aggregate_id` is a hardcoded literal, the second time the test suite runs, that combination has already been "processed," and the consumer function never actually gets invoked again. An assertion then reads the "never processed" initial state, which looks like the feature is broken, when really it's a test-data design problem. The fix: generate a unique suffix for `aggregate_id` per test instance too — the same principle as L4 integration testing's general rule of "build fresh data every time, with a unique suffix."

**⚠️ Never use a mock to verify that a cross-component call "happened."** A test like "verify the inventory service was called" stays green under both of two real failure scenarios — "called it, but passed the wrong arguments" and "called it, but didn't handle the error it returned." It can only prove a code path executed, never any business outcome. What actually happens between components belongs to L4's job (really starting two processes to verify it); a mock, or dependency injection, is only for testing a component's own internal call relationships.

**⚠️ L4 integration tests' data rule is "build it fresh every time, with a unique suffix, no cleanup" — never reuse a shared fixed dataset, and never introduce a throwaway/embedded database** (the H2/Testcontainers style of approach). The full reasoning, how to produce the data shape a cross-component test needs, and the complete seed-data strategy, are in [`05-data-construction-standard.md`](05-data-construction-standard.md).

---

## 4. Cross-Component Testing: Making One Component's Tests Hit Real Dependencies

Cross-component integration tests (this component really calling its strong dependencies) are, by default, easy to end up skipped in daily use, blocked by conditions like missing environment variables — the test environment itself can't reach a dependency component's internal port, so writing the test is wasted effort, and cross-component verification ends up only running once, whenever someone manually wires up the network by hand.

`make test-cross REPO=<repo>` solves exactly this: it reads the strong dependencies this component declares, spins up a lightweight forwarding container for each one, bridges each dependency's address onto the host the test runs on (the test process itself still runs on the host, so the host's build cache and concurrency/race detection all work normally), and automatically tears down the forwarding containers when done.

**How to use it:**

- Only "this component together with its strong-dependency tree" needs to be running — the whole assembly doesn't need to be up together. That's exactly what local testing means: only this one component's own tests run, hitting real strong dependencies, and whether any other component happens to be running has no effect on the result.
- Supports filtering, to run only tests matching a given name.
- **The scope is "this component calling its dependencies" (the synchronous call direction).** "Another component consuming events this component emits" is an entirely different thing (it involves the event bus, and can compete with a real container running on the same machine for messages) — it is not covered by this tool and needs to be handled separately (see §3.4's two consumer-test rules).
- **Naming convention**: a newly written cross-component test's name should reflect "which component this is testing interaction with," so it can be paired with a filter argument to run only the batch "between these two specific components" (the full naming convention is in §8).

For how the data a cross-component test needs is produced, see [`05-data-construction-standard.md`](05-data-construction-standard.md) §3.

---

## 5. Extended Testing Categories

Beyond the stable four layers L1–L4, the following categories are equally mandatory — not "optional bonus points":

### 5.1 Permission/Data-Scope Boundary Tests

"No token should be rejected" and "a token with no permission should be rejected" are both the responsibility of the authentication middleware itself — test them once at the language base-library level, no need to re-verify per component. But **a gate must confirm that every externally facing endpoint really does go through this middleware layer** — no bare route may bypass it.

The one thing genuinely only each component can verify for itself is the scope-filtering logic behind "can see my own data, can't see someone else's" (since this logic is hand-written per component, not shared middleware) — full criterion in §3.2. Any component that declares a data-scope dimension must have at least one test of that shape; this is checked automatically by an assembly-layer gate (reading the component's data-scope declaration, and checking whether the test files contain a case shaped like "over-privileged/out-of-scope access gets rejected").

### 5.2 Event-Contract Breaking-Change Detection

An event's schema can only evolve additively — adding a field or adding a new event type is fine; deleting an existing field, changing an existing field's type, or deleting an existing event subject are all disallowed. An assembly-layer gate automatically compares each component's event-contract files against their historical versions and flags violations.

### 5.3 SDK Concurrency-Correctness Tests

The language base library shared by every component has cross-cutting capabilities (event-delivery polling, idempotency-table operations, connection-pool management…) whose correctness under "multiple instances running at once" is a class of problem the single-component view of L1–L4 simply cannot catch — L1–L4 all assume "only one process instance is running," and can never surface a problem like "two instances racing for the same batch of unprocessed events, each believing it's the one that should handle them." The requirement for this class of primitive: at least one test case of "multiple instances concurrently using the same primitive," verifying the result is processed exactly once — not duplicated, not missed.

### 5.4 Frontend Visual Regression Testing

See §6.4, FE-4.

---

## 6. Frontend Testing: The Four Layers in Detail (FE-1 – FE-4)

The frontend's layering criteria follow the same thinking as the backend's — just with different tools: spec separated from implementation, shared things prioritized over feature-specific ones, real environments preferred over simulated ones.

### 6.1 FE-1 · Unit/Logic Tests

**What it tests**: pure functions, composables, state stores (`store`) — network requests entirely mocked out.

**Criterion**: this layer tests "given this input, does the logic itself compute the right thing" — it doesn't care about a real network round-trip, and doesn't care about UI rendering.

### 6.2 FE-2 · Component Tests

**What it tests**: shared UI components reused across multiple business pages (tables, form templates, generic cards, that kind of thing). Breaking a shared component simultaneously breaks every page that references it, so this class of component's tests naturally outrank a one-off component that belongs to a single business page alone.

### 6.3 FE-3 · End-to-End Tests

**What it tests**: real browser + real backend (the full assembly actually running), covering a complete business flow — not one isolated UI interaction. PC and mobile can share the same end-to-end tooling, distinguished by different device profiles, without needing two entirely separate toolchains.

**⚠️ When to start writing them**: once a page's interaction shape has largely stabilized, add them in a batch. While a page is still being heavily reworked, every UI change would drag along a rewrite of the end-to-end test's selectors and assertions — investing in end-to-end tests at that stage has poor ROI. This isn't "forgot to write them" — it's deliberately sequenced after the page stabilizes. **The skeleton and directory convention should be decided ahead of time**, so that once real writing starts, it's a matter of filling it in, not designing it from scratch.

**Criterion**: name a test after "the business flow it verifies," not "which button it clicked" — that's what makes it possible to filter, by name, for "every end-to-end test related to this one business flow." Otherwise this layer's filterability exists in name only.

**⚠️ Must get explicit user agreement before running — never run it on your own initiative.** This criterion isn't about any one specific tool (Playwright/Cypress/Selenium/Puppeteer are all the same in this respect) — what's expensive isn't "which framework is being used," it's the fact itself that "the AI needs to actually drive a real browser, and debug selectors or diagnose failures via screenshots or by reading the rendered DOM" — swapping in any comparable tool costs roughly the same order of magnitude. Before doing anything, tell the user the specific scope intended for this run (which business flow, which pages/assertions it covers), then wait for the user to confirm whether to run it now, and at what scope — whether to run it at all, and how far to run it, is the user's call to make. The same applies to §6.4's visual regression tests, since they run inside the same end-to-end flow.

**The cost mainly comes from the "write/debug" phase, not the "run" phase**: running an already-written, stable test suite once produces a text-form test report (which cases passed, which failed, which assertion they failed on) — a cost comparable to an ordinary unit test. What actually burns tokens is writing a test for the first time — repeatedly taking screenshots to confirm a selector is right, and repeatedly taking screenshots to diagnose why something failed. Ways to reduce this cost:

- Prefer an accessibility-tree snapshot (structured text) to confirm page elements, rather than screenshotting the whole page every time just to "look" at it;
- On failure, look at the plain-text error stack trace and trace file first, and reach for a screenshot only once that doesn't resolve it;
- Have a human record the key interaction paths where possible, cutting down on rounds of the AI blindly guessing at selectors through trial and error.

### 6.4 FE-4 · Visual Regression Tests

**What it tests**: whether spacing, density, and component usage are consistent across different pages. The approach is to take a screenshot comparison in passing, at key pages, as the end-to-end test flow walks through them — not to spin up a separate browser run just for a standalone "pure screenshot" test suite. Visual regression is one assertion style within an end-to-end test, not an independent test type. The baseline updates alongside UI changes.

⚠️ The pre-run user-confirmation requirement is exactly the same as §6.3's (the same browser flow), not repeated here. Visual regression **necessarily** involves screenshots — that follows from its own definition, and no choice of tool avoids it — but the comparison step itself is an automated pixel-level diff, producing a text result like "pass/fail + percentage difference"; it doesn't require an AI to use visual understanding to look through images one by one. The only step that genuinely needs visual-understanding capability is the one after a comparison fails — judging whether that difference is a real bug or an expected UI change.

### 6.5 Frontend Contract Drift: Eliminated by Mechanism, Not by Writing More Tests

Hand-written frontend type definitions (with a comment saying "matches the backend contract exactly," but no mechanism actually guaranteeing that) should not rely on repeatedly adding tests to catch drift — that turns a problem that could be eliminated at the source into a maintenance tax that never gets fully paid off. The correct approach is to **build a mechanism that auto-generates frontend types and request functions from the backend contract** (`.openapi.yaml`/the GraphQL schema): the type checker itself then catches every drift at compile time, and once set up, every new endpoint costs nothing extra — there's no need to run a separate test just to answer "has the contract drifted."

---

## 7. Component Test Infrastructure: Layout, Commands, How to Debug

A component's tests shouldn't be a pile of scattered files — there should be uniform, predictable infrastructure, so that anyone (or any AI) opening a component they've never seen before immediately knows how to run the tests and how to debug them.

### 7.1 Three Run Granularities: When to Use Which

Regardless of language — backend Go/Python, frontend TypeScript — the same three granularities apply; only the commands differ:

| Granularity | When to run it | Backend command | Frontend command |
|---|---|---|---|
| **① Full suite** | Before a deployment, at the end of a phase, a full acceptance pass on the whole assembly | Every gate + `make test` in every component | Run every frontend package's tests at once, from the root |
| **② Whole component** | A component/a feature has just been finished | `make test`; `make test-cross REPO=<x>` to also run the cross-component L4 tests (§4) | Run tests for a single frontend package |
| **③ A subset within a component** | Iterating on a new feature, wanting to confirm "this part isn't broken yet" | Filter by name/regex, run only the matches | Filter by file/pattern; in watch mode, dependency-aware auto-rerun of only the relevant tests |

③ needs no extra tooling — all three languages' native test runners already support filtering by name/path, provided test names are themselves predictable (see §8). If naming is inconsistent, this granularity exists in name only, and finding a test becomes a manual file-hunting exercise.

### 7.2 Commands Every Component Should Have

| Command | What it does | When to use it |
|---|---|---|
| `make test` | Runs this component's full L2 + L3 tests (with concurrency/race detection enabled) | Day-to-day development, at the end of every red-green cycle |
| `make migrate-idempotent` | The same database migration run twice in a row must both succeed | Every time a migration file changes |
| `make contract-check` | Breaking-contract-change detection | Every time the contract changes |
| `make smoke` | Really starts just this one component (together with its strong-dependency tree), hits it once over each real protocol (HTTP + gRPC), confirms the health check turns healthy | Before every real-machine verification |
| `make test-cross REPO=<this component's repo name>` (run from the assembly-layer root) | Localized cross-component L4 tests, see §4 | When there's a strong-dependency edge and you want to verify the real call chain |
| `make seed` | Seeds a dataset covering various states/branches/permission dimensions (if this component has seed data) | Local exploration, demos, manually verifying a new feature |
| `make seed-clean` or `make db-reset` | Undoes/resets seed data — which one to use, see [`05-data-construction-standard.md`](05-data-construction-standard.md) | When a clean slate is needed |

**These commands must genuinely exist and genuinely run** — a component whose docs merely say "there should be tests," with no single command that runs them with one keystroke, has no test infrastructure at all, in effect.

### 7.3 How to Wire Up Real Infrastructure When Needed

L4 integration tests and consumer tests need real Postgres / NATS, and these should point at a database/message channel dedicated to automated testing, physically separate from the one used for human exploration/demos — full reasoning is in [`05-data-construction-standard.md`](05-data-construction-standard.md) §1.

### 7.4 The Basics of Debugging

- **Run just one test, or a small handful**: all three languages' native test runners support filtering by name/path, provided test names are themselves predictable (see §8).
- **Filtering a cross-component test**: `make test-cross` supports a filter argument to run only cases matching a given name, and combined with the cross-component naming convention, this can run just the batch "between these two specific components."
- **When a gate fails, read the output first — no need to read the code first**: whenever a gate fails, its output directly states which criterion was violated and which file is involved — the entire point of a gate is to let someone locate the problem without reading code line by line; reading the code is what happens after a gate has pointed at the problem, not the first step of diagnosing it.
- **The full process for getting stuck is in §2.4.**

---

## 8. Test Naming and Discoverability Conventions

Predictable naming is the precondition for "running just a small handful of tests" to actually work — if naming is inconsistent, filtering exists in name only, and finding a test becomes manual file-hunting.

| Convention | Applies to | Purpose |
|---|---|---|
| A test's name directly describes the business conclusion or implementation branch, no numbering | Ordinary L2/L3 tests | The name alone tells you what it tests, no need to open the file |
| Property tests are marked distinctly (e.g. carrying the word `Property`) | L2 property tests | Signals to the reader "this assertion is backed by random-input attacks, not a single example" |
| A cross-component test's name reflects "who the other component is" (e.g. a camelCase form of the other component's name) | Cross-component L4 tests | Pairs with `make test-cross`'s filter argument to run only the tests between two specific components |
| An end-to-end test is named after "the business flow it verifies," not "which button it clicked" | Frontend FE-3/FE-4 | Pairs with a filter argument to select by business flow |

⚠️ These conventions are mandatory only for **newly written** tests — there is no requirement to go back and rename existing ones. Renaming has no real benefit and no urgency; rename it in passing if you happen to be touching it, but it doesn't need its own dedicated task.

**Seed-data discoverability**: see [`05-data-construction-standard.md`](05-data-construction-standard.md).

---

## 9. Human Review: The Testing-Related Part

No human can read every line of every component's implementation across the whole system, so review concentrates only on **what's irreversible and what a gate itself cannot guard.** The one item directly related to testing:

> **Whether the invariant checklist for L2 business-rule tests is complete.** The reviewer only checks "have every invariant this component should have actually been listed" — not how any of them is implemented. **A gate can never catch a missing invariant** — a gate only ever runs the tests that have already been written down; an invariant nobody ever thought of doesn't get verified just because every gate is green.

**What does not need human review**: business code line by line, L3 unit tests, build scripts — these are covered by gates and by L2; a real problem here will turn red in a gate or an existing test, and doesn't need a human eyeballing it in advance.
