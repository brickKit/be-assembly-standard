# AI-Driven Development Standard

An AI writing the implementation has a different failure profile and a different cost structure than a human engineer does. It starts every session with no memory of the last one and a bounded context window; it can't "come back to this file later, I remember roughly how it works"; and rewriting a whole file can be *cheaper* for it than carefully layering a fourth patch on top of three earlier ones, which is exactly backwards from the intuition a human engineer would have. None of the individual judgment calls in this document are unique to any one project's business domain — they follow directly from that difference, and apply to any codebase where an AI is doing most of the writing and a human is doing the reviewing.

## 1. When to Use a Design Pattern

Design patterns are never mandatory, but where one genuinely fits, it should be used. There is exactly one criterion:

> **Does it make this logic easier to read and extend, or harder?**

**Who has to find it easy is already decided: judge by whether an AI can understand it quickly.** A human reviewer can be assumed to already have a working knowledge of design patterns — that's not the constraint. The actual bottleneck is the AI: it starts every session from zero, has a bounded context window, cannot see runtime state, and won't "spend a while and eventually remember where that file was."

So "easier" has a concrete, testable definition:

> **Can an AI in a brand-new session get a new rule right, having read only a small number of files?**

### 1.1 What Helps an AI, What Hurts It

| Helps | Why |
|---|---|
| **Small files, single responsibility** | Every file an AI touches has to be read into context in full. Changing 3 lines in a 600-line file costs reading 600 lines; changing 3 lines in a 60-line file costs reading 60. |
| **A registry concentrated in one place** | One file listing every rule lets an AI see the *entire set* at a glance. Scattered across many files, it can only guess via search — and a guess that misses one is a missed update. |
| **Explicit over implicit** | An AI cannot infer runtime magic. Reflection-based registration, decorators that auto-discover things, naming-convention-based scanning — a human can patch over these with accumulated experience; an AI will simply miss them. |
| **One file per case, filename = the case** | A name like `rule_volume_discount.go` tells an AI which file to touch without reading the contents first. |
| **State transitions centralized into one table** | The single most common AI mistake is "one entry point forgot to check the precondition." Centralize every transition edge in one declared place and it becomes structurally impossible to miss one. |

| Hurts | Why |
|---|---|
| **Deep inheritance chains / many layers of abstract base classes** | Understanding one method means jumping through four files; an AI starts guessing by the third jump. |
| **Metaprogramming, reflection, dynamic dispatch** | An AI cannot statically infer which code path actually executes. |
| **Abstracting ahead of time "in case we need to extend this later"** | Every extra layer of indirection is one more file to jump to, for zero benefit today. |
| **A pattern spread across multiple packages** | An AI can't hold the whole picture at once, and will easily update package A while missing the matching change needed in package B. |

⚠️ **The last item matters especially**: a design pattern's benefit comes from "turning one long piece of logic into a handful of clearly structured short files" — **not** from "spreading the logic across the entire codebase." A pattern should stay contained inside one package.

### 1.2 Four Signals That a Pattern Is Worth Considering

Any one of these is worth stopping to consider:

| Signal | Symptom | What to reach for |
|---|---|---|
| **A `switch`/`if-elif` chain already past 5 branches, and still growing** | Adding one more case means editing an already-long function, risking touching a branch you didn't mean to | **Strategy**: one file per case, registered into a table |
| **A function past 150 lines, or a file past 600** | An AI has to read the whole file into context for every change; a human has to scroll for a while to even find the spot | Split by responsibility first, then see which pattern the resulting pieces resemble |
| **The same flow runs several times, differing only in a step or two in the middle** | Copy-pasted three times, then one copy gets a bugfix the other two don't | **Template Method** or **Chain of Responsibility** |
| **The legality of a state transition is checked in more than one place** | One entry point misses a precondition check, data ends up in a state it shouldn't be in, and nothing errors | **An explicit state machine**: every transition edge declared in one place |

### 1.3 Three Situations Where a Pattern Should *Not* Be Used

| Situation | Why not |
|---|---|
| **Plain CRUD on a simple resource** | Writing it directly is the clearest form it can take. A layer of abstraction just means one more file to flip to for the reader. |
| **Only two branches, with no foreseeable third one** | `if a {} else {}` is far easier to follow than a strategy interface, two implementations, and a registry. |
| **Abstracting ahead of time "in case we need to extend this later"** | The default judgment should be: don't split unless you have to. Glue cost is real; "later" often never arrives. Abstract once a second real implementation actually shows up — only then do you know which seam to cut along. The extra cost for an AI specifically: every layer of speculative abstraction is a file it must jump to and learn nothing useful from. |

⚠️ **This last one is the easiest to violate**, because "leaving room for future extension" always sounds correct. The test: **can you name, right now, exactly what the second implementation would concretely be?** If you can't, don't abstract yet.

### 1.4 File Organization Once a Pattern Is Applied

Half of a pattern's benefit comes from turning one long file into several short, structured ones — so actually split it when you apply one:

```
backend/internal/pricing/
├── pricing.go          # Interface + registry + execution order. Reading this one file tells you every rule that exists.
├── rule_base_price.go  # One rule, one file
├── rule_customer_tier.go
├── rule_volume_discount.go
├── rule_promotion.go
└── pricing_test.go     # One test per rule, plus a property test over the composed chain
```

**One test tells you whether the split actually worked**: hand a brand-new AI session — with zero context on this project — the task of adding one new discount rule.

**Signs it's correctly split**: it only needs to read `pricing.go` (to see the interface and registry) plus any one `rule_*.go` (to see the shape), then create one new file and add one line to the registry. **Two files read, zero files modified.**

**Signs it's split wrong**: it also has to edit some other rule's file (meaning the chain's execution order or data flow isn't clean), or it has to jump three layers deep just to find the interface definition (meaning there are too many layers of abstraction — see §1.1).

## 2. How Much to Build in One Working Session

| Unit | Size | Criterion |
|---|---|---|
| **One session** | One task, or 2–4 red-green cycles within a task | Once context is half consumed, wrap up, commit, and start a fresh session. Leaving headroom is what lets the next session actually read the surrounding code, instead of only being able to read what it wrote itself. |
| **One red-green cycle** | One test, plus the minimal implementation that turns it green | Three rounds without green means **this step is too big — cut it smaller** (see §4). |
| **One commit** | One red-green cycle | On failure, this lets you roll back precisely to "the last fully-green state." |

**A new session should always read, at its start** (reading more wastes context, reading less means guessing):

1. The repository root's always-loaded agent-instructions file (loaded automatically, no need to read it manually)
2. This specific unit of work's own agent-instructions file — its identity, its boundaries, its own known pitfalls
3. This unit's design document — why it's designed the way it is
4. **Only the current task** inside the active phase-plan document (not the whole document)
5. The specific source files about to be changed

**Should not be read**: the full design book (thousands of lines), the full master guide, anything belonging to an unrelated part of the system. When a specific rule is needed, use the routing table in the root agent-instructions file to find the exact section — don't read the whole source document speculatively.

## 3. What a Human Actually Needs to Review

No human can read every implementation line across a large, AI-written codebase. Review time should concentrate on **what is irreversible, and what a gate cannot catch**:

| # | What to review | Why this and not something else |
|---|---|---|
| 1 | **Contracts** | **The single least reversible thing.** Once a contract has a consumer, it can only be extended backward-compatibly. A mistake here costs every dependent. |
| 2 | **Migrations** | **The second least reversible thing.** A partition key, a primary key, an index — these are locked in at table-creation time; changing them once data exists is itself a migration. |
| 3 | **The invariant checklist inside business-rule tests** | Check only "is every invariant this logic needs actually listed" — not how any of them is implemented. **A gate can never catch a missing invariant**, because a gate only ever runs the tests that were already written down. |
| 4 | **A design document's boundary section and its dependency section** | A wrongly-drawn boundary, or one extra synchronous dependency edge that shouldn't exist, is the one mistake capable of contaminating an entire architecture diagram. |
| 5 | **Gate output** | No code-reading required. A failing gate's output tells you exactly where to look. |

**What does not need review**: business code line by line, ordinary unit tests, build scripts, Dockerfiles. These are covered by gates and by the tests already described above; if something is genuinely wrong here, a gate or an existing test will turn red.

## 4. Allowing a Wholesale Rewrite, Not Just Incremental Patches

Over the course of ongoing development, some piece of logic ends up in a state where — because an earlier judgment call didn't hold up, or because it drifted off course across several rounds of iteration — the honest fix isn't "patch the small part that's wrong." **An AI's cost structure for writing code is completely different from a human's** — rewriting an entire file can genuinely be cheaper for an AI than reconstructing three layers of history in its head and then carefully adding a fourth on top. There is no need to cling to "leave it alone if you can" — that's a rule of thumb that only makes sense for a human engineer.

**When a wholesale rewrite is the right call, instead of another patch:**

- The same piece of logic has already been patched several times in different directions, and now understanding the current state well enough to change even one line requires mentally layering multiple rounds of history first.
- The problem isn't a bug — it's the realization that **the original design judgment itself was wrong**. Continuing to build on that foundation only compounds the drift; a rewrite is coming eventually regardless, so doing it now is cheaper than doing it later on top of more accumulated dependents.
- **Seed/demo-style data deserves an even looser bar for rewriting**: this kind of content is inherently fake data with no "migrate historical records" burden attached, so a rewrite costs about the same as "delete and rebuild." If the current shape isn't the one actually wanted, redesigning its entire coverage in one pass is both faster and cleaner than adding to it piecemeal.

**Process:**

1. Before starting, copy the file being rewritten into a local scratch location (not committed to version control) purely as a side-by-side reference while writing the new version — not as an archival record (version control already keeps every old version; that history is one command away whenever it's needed).
2. The rewrite lands as **its own single commit**, with a message that explains *why* it was rewritten, not just *what* changed — this is what makes it possible, months later, to find exactly when and why a piece of logic was torn down and redone.
3. Run the component's full acceptance gates afterward exactly as normal. **The bar does not drop just because it was a rewrite rather than a patch** — a rewrite's risk of introducing a new bug is no lower than an incremental change, and the surface area touched is usually larger, which is a reason to verify more, not less.
4. Once verified and committed, delete the scratch reference copy — its job is done, and the real historical record already lives in version control.
5. If the rewrite was triggered by realizing an earlier direction was wrong, that's worth writing down somewhere durable: a technical lesson ("looked correct, was actually wrong") belongs in a pitfalls log; a design judgment that needs updating belongs in that component's design document — otherwise the next person will read the old document and rebuild the same wrong direction from it.
