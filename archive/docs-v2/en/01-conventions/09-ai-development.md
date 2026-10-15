[English](09-ai-development.md) · [中文](../../zh/01-conventions/09-ai-development.md)

# AI development conventions

An AI writing the code fails differently from a human and pays different costs. It starts every session with no memory of the last, inside a bounded context window; it can't "come back to that file, I remember roughly how it works"; and rewriting a whole file can be cheaper for it than carefully adding a fourth patch to three earlier ones. The rules below follow from that.

## When to use a design pattern

A pattern is never mandatory; where one fits, use it. One test decides:

> **Can an AI in a brand-new session get a new rule right after reading only a few files?**

The reader to optimise for is the AI: it starts from zero, has a bounded context, can't see runtime state, and won't eventually remember where that file was.

| Helps | Why |
|---|---|
| **Small files, one responsibility each** | every file touched is read in full: three lines in a 600-line file cost 600 lines of context |
| **One registry in one place** | one file listing every rule shows the whole set; scattered, the AI finds them by search, and a missed one is a missed update |
| **Explicit over implicit** | reflection-based registration, auto-discovering decorators and naming-convention scans are invisible to static reading |
| **One file per case, the file name is the case** | `rule_volume_discount.go` says which file to touch before it is opened |
| **State transitions in one table** | the most common AI mistake is an entry point that forgot a precondition; one declared table makes that impossible |

| Hurts | Why |
|---|---|
| **Deep inheritance, layers of abstract base classes** | one method means four files; by the third jump the AI guesses |
| **Metaprogramming, reflection, dynamic dispatch** | the path that runs can't be inferred statically |
| **Abstraction "in case we extend it later"** | one more file to jump to, for nothing today |
| **A pattern spread over several packages** | the AI updates package A and misses package B |

A pattern's value is turning one long piece of logic into a few short structured files, never spreading the logic over the codebase. Keep a pattern inside one package.

**Signals worth stopping for**:

| Signal | Symptom | Reach for |
|---|---|---|
| A `switch` / `if-elif` past 5 branches and growing | each new case edits a long function and risks the others | Strategy: one file per case, registered in a table |
| A function past 150 lines, a file past 600 | every change reads the whole file | split by responsibility first, then see which pattern the pieces resemble |
| The same flow several times, differing in a step or two | three copies, one gets the fix | Template Method or Chain of Responsibility |
| A transition's legality checked in more than one place | one entry point misses a check, data lands in an impossible state, nothing errors | an explicit state machine, every edge declared once |

**When not to**:

| Situation | Why not |
|---|---|
| Plain CRUD on a simple resource | written directly is the clearest it gets |
| Two branches, no third in sight | `if a {} else {}` beats an interface, two implementations and a registry |
| "In case we need it later" | abstract when a second real implementation exists; only then is the seam known |

The last one is the easiest to break, because leaving room always sounds right. The test: **can you name the second implementation right now?** If not, don't abstract.

**File layout once a pattern is applied**:

```
backend/internal/pricing/
├── pricing.go             interface + registry + order: this file shows every rule
├── rule_base_price.go     one rule, one file
├── rule_customer_tier.go
├── rule_volume_discount.go
└── pricing_test.go        a test per rule, plus a property test over the chain
```

The split is right if a new session adding a discount rule reads `pricing.go` and one `rule_*.go`, creates one file and adds one registry line: two files read, none modified. It is wrong if it must edit another rule's file (the chain's order or data flow isn't clean) or jump three layers to find the interface (too many layers).

## Patterns already decided here

These need no new judgment; their branch count and growth are known.

| Component | Where | Pattern | Why |
|---|---|---|---|
| erp/sales, erp/purchase | pricing and discounts | Strategy + Chain of Responsibility | pricing rules are the most customer-specific, most changed part; a fork adds a rule by adding a file |
| erp/sales | order state machine | explicit state table | transition legality in one place |
| erp/inventory | receipt and issue document types | Strategy | receive, issue, transfer, count and return validate differently and land in one ledger |
| erp/finance | business document → accounting voucher | Strategy, one translator per document type | a new document type is a new translator, the others untouched |
| infra/notification | channel routing | Strategy + registry | channels coexist and register according to which channel components are present |
| infra/print | rendering backend (PDF, ZPL) | Strategy | the two outputs share nothing but their inputs |
| hrm/payroll-es | pay item calculation | Strategy + topological sort | pay items depend on each other; the wrong order gives wrong numbers |
| every component | saga compensation steps | Command | each step reversible and persisted, so it resumes after a restart |
| be-ops | its outputs | one package per output, one interface | — |

## Comments on long business functions

A complex business function an AI writes, past 50 lines, carries a comment with its decision tree in plain language, and a Mermaid flowchart where the branching is not obvious. Review sends it back without one.

## How much in one session

| Unit | Size | Rule |
|---|---|---|
| **Session** | one task, or 2–4 red-green cycles of one task | at half the context, wrap up, commit, start a new session; the headroom is what lets the next one read the surrounding code |
| **Red-green cycle** | one test and the least code that turns it green | three rounds without green: the step is too big, cut it ([06-testing.md](06-testing.md#when-stuck)) |
| **Commit** | one cycle | a failure rolls back exactly to the last green state |

A new session reads, at its start, and no more:

1. the project `AGENTS.md` (loaded automatically);
2. the component's `AGENTS.md`: its boundaries and its own pitfalls;
3. the component's `docs/design.md`: why it is built this way;
4. only the current task of the plan it works from;
5. the source files about to change.

Not the whole of every convention file, not unrelated components. When a rule is needed, the "Where to look" table of `AGENTS.md` points at the exact file and section.

## What a human reviews

No human reads every line of a large AI-written codebase. Review goes where things are irreversible and where gates can't see:

| # | What | Why this | Where |
|---|---|---|---|
| 1 | **Contracts** | the least reversible thing: once consumed, it only grows | `contracts/` |
| 2 | **Migrations** | the next least: keys, partition keys and indexes are fixed at creation; changing them with data is a migration | `migrations/` |
| 3 | **The invariant list in L2 tests** | only whether every invariant is listed; a gate runs only tests that exist | `*_test.go`, `tests/` |
| 4 | **Boundaries and dependencies in `docs/design.md`** | a wrong boundary or one extra synchronous edge pollutes the whole architecture; the synchronous call graph stays acyclic | `docs/design.md` |
| 5 | **Gate output** | no code reading needed; a failing gate names the place | `make gates`, the component's gates |

Not reviewed: business code line by line, unit tests, build scripts, Dockerfiles. The gates and tests cover them; a real problem there turns something red.

## Rewriting instead of patching

When a piece of logic has drifted (an early judgment that didn't hold, several rounds of patches in different directions), the honest fix may be a rewrite, not another patch. For an AI a rewrite is often cheaper than holding three layers of history in mind to add a fourth.

**Rewrite when**:

- the same logic has been patched several times in different directions, and changing one line means replaying that history;
- the problem isn't a bug but a design judgment that turned out wrong; building on it compounds the drift;
- it is seed or demo data: fake, with no history to migrate, so a rewrite costs about the same as delete-and-recreate.

**How**:

1. Copy the file to a scratch location outside the repository, as a side-by-side reference only (Git already keeps every version).
2. Land the rewrite as **one commit** whose message says why it was rewritten.
3. Run every gate as usual; the bar doesn't drop for a rewrite. A rewrite touches more, which is a reason to verify more.
4. Delete the scratch copy.
5. If the rewrite came from a wrong direction, write it down where the next reader will look: a "looked right, was wrong" lesson in the component's `AGENTS.md` pitfalls, a changed design judgment in its `docs/design.md`.
