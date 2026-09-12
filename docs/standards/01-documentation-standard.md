# Documentation Standard

## 1. Scope and Authority

This document governs how documentation in this repository is structured, split, cross-referenced, and evolved over time. It applies to the project-level regulatory documents (`AGENTS.md`, the `docs/standards/*.md` family) and sets the cross-cutting design criteria that component-level documents (governed day-to-day by `00-master-guide.md`'s SOP-D) must also satisfy. It does not replace SOP-D's four-document checklist — it adds the judgment calls SOP-D doesn't cover: when a document should split, what growth signals a problem, and how a set of documents should talk to each other.

Primary reader: an AI assistant doing development work in this repository, at any capability level — treat a lower-effort or less capable model as the baseline this document is written for, not the exception. Secondary reader: the human maintainer, who reads the parallel `docs/zh/` companion of any bilingual document (§6).

Conflict priority is unchanged from `AGENTS.md`: Design Book > Master Guide > phase plans > `AGENTS.md`. This document sits alongside `00-master-guide.md` in that same tier.

## 2. Eight Rules

### 2.1 Separate durable state from historical narrative — always

A "current state" section answers "what is true right now" — current version numbers, current phase, current open questions. It must never accrete a chronological account of how things got there. Historical narrative — what happened, when, why, what was learned — belongs in a chronicle document (a phase plan, a retrospective, a pitfalls log) that nobody consults to find out what is true today.

**Symptom of violating this**: a "current state" table cell that grows every session, mixing today's facts with last month's debugging story, until finding "what version is X on" requires reading a multi-page paragraph.

### 2.2 No accretive content in a single cell or paragraph

Anything that grows by accretion — one new entry per session, per task, per component — needs its own addressable location: a dedicated file, a table with one row per unit, or a numbered list. It must never live inside a single table cell or a single run-on paragraph with no internal anchors.

**Symptom**: a table cell that used to be one sentence and is now several kilobytes of unstructured prose; nobody can jump to "the part about component X" without reading everything before it.

### 2.3 Split along the axis that minimizes forced multi-document reads

When content could plausibly belong to more than one document, don't split by surface topic similarity ("these both mention testing"). Split by the axis where a reader doing task A only ever needs document A, and a reader doing task B only ever needs document B — and put whatever both A and B genuinely need wherever it naturally belongs as a single copy, rather than duplicating it or forcing a second read.

**How to apply**: before splitting, list the tasks that will actually consult each candidate document. If most tasks need both, they are not two documents yet.

### 2.4 Routing tables trigger on keywords, not narrative problem descriptions

A routing-table entry should read close to what a reader would type into a search — "how do I test permission boundaries", not "concerns about verifying that authorization actually restricts access in the way intended". Always include an explicit fallback: if nothing in the routing table matches, check every `docs/standards/*.md` file — they are the closed set of always-valid regulatory documents.

**Symptom of violating this**: a routing-table row that reads like a summary of the problem's history rather than a lookup key.

### 2.5 Every long-lived reference document needs internal addressability

A document meant to be pointed at from elsewhere (`"see §12.4"`, `"see decision 105"`) must have stable, numbered anchors — numbered chapters/sections, or a table with a stable row key (a decisions table, for instance). Size alone is not the problem; the absence of anchors is. A 3000-line document with disciplined chapter numbers is more navigable than a 200-line document that is one undivided paragraph.

### 2.6 Redundancy is a deliberate, bounded choice

A small number of rules that are silently violated and hard to detect — the kind where the code looks correct, tests pass, and the bug only shows up in a way that's hard to connect back to the rule — are worth duplicating directly into the always-loaded entry point, even at the cost of also being documented in depth elsewhere. This is not "avoid duplication at all costs"; it is "duplicate on purpose, only for the few rules where missing them is expensive and hard to discover."

### 2.7 Documents that are typically needed together must cross-reference each other

Never rely on an AI inferring that a second document exists and is relevant. If task X routinely needs both document A and document B, A must say so and point to B, and vice versa.

### 2.8 The "one document, one job" test

Every document must be able to answer, in one sentence: what question does this answer, and for whom? If a document tries to serve two different questions or two different audiences — "here is what happened" and "here is the current specification", for instance — split it along §2.3's axis test.

## 3. When to Split a Document Into Its Own File

Split when all three hold:

1. The content has grown large enough that keeping it inline obscures the parent document's own primary purpose (§2.8's test starts failing for the parent).
2. The content answers a genuinely different question than its parent — not just a related topic (§2.3).
3. Splitting will not force routine tasks to read both the old and the new document (§2.3's axis test, applied to the split itself).

If these hold, split immediately. A prescriptive standard document describes current best practice, not a historical record — it can be freely rewritten. This is the same rule already applied when `04-testing-standard.md` and `05-data-construction-standard.md` were split out of `00-master-guide.md`.

## 4. Component Documents Serve Two Readers

Every component-level document — the four governed by this section: `docs/design/<repo>.md`, `README.md`, `docs/手册.md`, `AGENTS.md`+`CLAUDE.md` — must be checked against two distinct readers before it is considered finished:

1. **Someone actively developing or modifying this component right now** — needs precise, current, actionable detail: what the contract is, what the gotchas are, how to run its tests.
2. **Someone (human or AI) arriving cold to understand the overall project by reading into this one component** — needs enough self-contained context to make sense of why this component exists, what it depends on, and how it fits the whole, without first having read every other component's documents.

When writing or revising a component document, check both angles explicitly. A document that only serves reader 1 reads like a changelog with no context; a document that only serves reader 2 is too vague to actually develop against.

These four documents are not cleanup work done at the end — they are four concrete steps inside the development flow itself: the design document comes before implementation starts; the README and the agent-instructions files are written when the component's skeleton is scaffolded; the manual grows alongside the implementation. §4.1–§4.4 below are the concrete, fill-in-the-blank template for each one; §4.5 is the mechanical gate that checks all four are structurally complete.

### 4.1 The Design Document (`docs/design/<repo>.md`) — written before work starts, in the assembly repository

A component must have this document before any work on it begins. **Starting without it means design decisions get written straight into code, and six months later nobody knows why any of them were made.**

It must answer these nine questions:

| # | Question |
|---|---|
| 1 | **Boundary**: what belongs to this component, and — more usefully — what explicitly does not. Also: does this component need row-level data scoping? If yes, list the dimensions and which tables they apply to; if no, state why explicitly. |
| 2 | **Data owned**: the table list, which ones are partitioned, the partition key and granularity, which states are terminal. |
| 3 | **Contract surface**: the gRPC rpc list (must include a batch-get), the external REST paths, which endpoints need an idempotency key, which need a status-polling endpoint. Each REST path should be annotated with its permission key. |
| 4 | **Events**: which are published, which are consumed, and for each, whether it's a core transactional event or a side-channel analytics event. |
| 5 | **Dependencies**: which are strong (synchronous calls), which are weak (optional), and — just as important — **why this component does *not* depend on some other specific thing** a reader might expect it to. |
| 6 | **Position in the system's synchronous-call graph**: does adding this introduce a cycle, does it violate any cross-domain boundary rule your platform enforces. |
| 7 | **Partitioning and archival strategy**: what counts as hot data, how often it's archived, the list of terminal states. |
| 8 | **Reference implementations**: see the reference-implementation standard for the full template — which project's which module was consulted, what was borrowed, the license, and usage classification, plus whether reading revealed a "this should be a pluggable family" divergence (this must be filled in *before* implementation starts, not after). |
| 9 | **Open questions**: anything genuinely undecided yet, deferred to implementation or a later phase. |

⚠️ **This document is revised as development progresses — it is not frozen once written.** When implementation reveals the design was wrong, **update this document first**, then update the code. Doing it in the other order means this document goes stale within a week, and nobody reads it again after that.

### 4.2 The README (component repository root) — written when scaffolding the skeleton

For the reader deciding "should I install this, and how." Exactly seven sections, no more, no fewer:

```markdown
# <repo-name> · <name>

One sentence: what it is.

## What it does
A feature list, one line each. User-facing capability, not implementation detail.

## Base resources it needs
| Resource | Kind | Why | How to start it |
|---|---|---|---|
(List each base resource this component needs and how to bring it up.)

## How to run it
### As part of the full assembly (normal path)
### Standalone (development/debugging)
Both give copy-pasteable complete commands, with preconditions and expected output.

## How to use it
A minimal working example: one request over its primary protocol, one over its secondary protocol if it has one.
The full API reference lives in docs/手册.md.

## Configuration
| Env var | Where it comes from | Default | Description |
⚠️ Platform-injected reserved variables get their own clearly-labeled subsection:
   "injected by the platform, do not set manually."

## Reference implementations
| Project | Module consulted | What was borrowed | License | Usage |
Copied over from the design document's reference-implementation section — including cases
where reasoning, not code, was borrowed. Someone will ask "where did this algorithm come
from" six months from now, and an AI will need to know which module to go read.

## Boundaries and prohibitions
Carry over the "explicitly not my responsibility" items from the design document, plus
anything specific to this component.
```

### 4.3 The Manual (`docs/手册.md`) — grows alongside the implementation

For the reader who already has this component installed and needs to use or modify it. Exactly six sections:

```markdown
# <repo-name> Manual

## 1. Project structure
The directory tree, one sentence of responsibility per directory.

## 2. Feature reference
One subsection per feature: what it does → how to call it (full request/response
examples) → boundary conditions → what a failure returns → which other components/events
it relates to.
⚠️ For an idempotent endpoint, document exactly how the idempotency key is constructed;
   for one with a status-polling endpoint, document when to call it.

## 3. Complete contract listing
Every gRPC rpc, every REST path, every event (published and consumed listed separately).
This is an index into contracts/ — that directory is the source of truth.

## 4. Data model
The table list, partitioning strategy, which fields are denormalized summary copies,
archival rules.
⚠️ Do not paste the full DDL — that lives in migrations/, and a pasted copy will drift.

## 5. Development
How to run tests locally, how to change a contract, how to add a migration, what each
CI gate actually checks.

## 6. Troubleshooting
This component's own symptom-to-cause table. Point to the project-wide troubleshooting
reference for anything generic.
```

### 4.4 `AGENTS.md` + `CLAUDE.md` (component repository root) — skeleton at scaffold time, calibrated at the end

For the AI assistant. Follows the two hard rules any AI-facing document must follow: no "as mentioned above"-style backward references (an AI may only ever see a fragment of the file), and every prohibition carries both a reason and its observable symptom.

`CLAUDE.md` is exactly one line, `@AGENTS.md` — some tools read `CLAUDE.md` and not `AGENTS.md`, while `AGENTS.md` is the cross-tool convention several other AI coding tools read automatically. Keep both files present; write the content exactly once.

`AGENTS.md` has exactly six sections:

```markdown
# <repo-name> · AI Assistant Guide

One sentence: what it is, which domain, what role it plays.

## Identity card
| Field | Value |
Component ID / repo name / ports / schema+role / language / assembly role / phase.
⚠️ Ports and schema names are copied from the project's registries, never invented —
   changing one later means updating every dependent.

## Boundary
**Write "not my responsibility" first.** This is the one thing that stops someone,
six months from now, from stuffing something into this component that doesn't belong.
Every "not my responsibility" item states who it belongs to instead, and why.

## Contract surface and events
The rpc list plus the event list (published and consumed listed separately). This is an
index into contracts/ — that directory is the source of truth.
⚠️ Note which endpoints are deliberately not exposed over REST, and why.

## Dependencies, and why not some others
Three small tables: strong dependencies / weak dependencies / explicitly-not-a-dependency.
The third table is the one that actually carries design intent.

## This component's own pitfalls
| Never | Symptom | Source |
Only what's specific to **this** component. The rules common to the whole project live in
the assembly repository's root AGENTS.md — do not copy them here. Copying them is a promise
to maintain two copies, and the stale one is what makes an AI confidently write the wrong
thing.

## Self-check before changing code
Three to five items specific to this component. For example:
- Does the dependency I'm about to add introduce a cycle in the synchronous-call graph?
- Does this query cross a schema boundary it shouldn't?
```

⚠️ **The "this component's own pitfalls" section must never copy a project-wide prohibition into it.** The assembly repository's root `AGENTS.md` already carries the project-wide list; repeating any of it here creates two copies that will drift apart. This section is only for pitfalls that are only ever hit while working on *this specific* component.

### 4.5 The Structural Gate for All Four

Add one gate to the component's full acceptance run that performs only mechanical checks (content quality is a review concern, not a gate's job):

| Check | Criterion |
|---|---|
| All four documents exist | The design document (in the assembly repo), README, manual, `AGENTS.md`, `CLAUDE.md` |
| README has all seven sections | Matched by heading name |
| Manual has all six sections | Same |
| Design document answers all nine questions | Same |
| `AGENTS.md` has all six sections | Same |
| `CLAUDE.md` points at `AGENTS.md` | Contains `@AGENTS.md` |
| **No backward-reference language in `AGENTS.md`** | Does not contain phrases equivalent to "as mentioned above" / "see above" / "as previously stated" |
| No placeholders | No `TBD` / `TODO` / "to be filled in" anywhere in the text |

## 5. Default Mode Is to Modify or Extend, Not Restructure

The default action is always to add to or edit an existing document. Splitting a document into a new file (§3), renaming a long-standing file, or reorganizing cross-references across many files is something the AI may propose — but only when §3's criteria are clearly met, or a genuine structural problem is found (the kind that motivated this document: an always-loaded file quietly growing past its own stated design intent). Propose it to the human; do not execute a wide-ripple restructuring unilaterally.

## 6. Language Policy

Two tiers:

- **Tier 1 — English-primary, with a Chinese mirror.** The default test is whether a document is actually read in full on a normal session, where reading speed matters: `AGENTS.md`, this document, `02-reference-implementation-standard.md`, `03-ai-development-standard.md`, `04-testing-standard.md`, `05-data-construction-standard.md`, `00-master-guide.md`. Both filename and content are English — when a document earns Tier 1, its filename converts along with its content; there is no permanent exception for a Chinese filename carrying English content. (`04-testing-standard.md` and `05-data-construction-standard.md` briefly had Chinese filenames with English content, right after their content was translated but before the filenames caught up — that inconsistent state was a to-do, not a stable outcome; renaming them to close the gap cost one cross-reference sweep across the project, which is cheap enough to redo whenever it's needed again. The whole set was renumbered once more after that, from split order to the read-priority order below (§7), which follows the actual component-build workflow: docs first (SOP-D), then check references (SOP-R), then pattern/session judgment (SOP-P) applies through implementation, then the test-driven implementation itself, then seed data last.)
  ⚠️ **`00-master-guide.md` is the one Tier-1 document that fails the "read in full" test and is there anyway.** Its own §W-4 still tells a session not to read it end-to-end — that hasn't changed, and by the letter of the test above it should sit in Tier 2. It moved to Tier 1 on explicit instruction: the project maintainer decided the mirror-maintenance cost (this is the largest, most frequently edited document in the project) is worth paying purely so the AI can read and edit it more comfortably, independent of whether the per-lookup speed gain is large. There is a real, if secondary, coherence argument too — every other Tier-1 standard cross-references this document by name and section (e.g. "Master Guide §4 SOP-R's R-2 table"), so keeping it English removes a language switch at exactly those junctions. The lesson generalizes: **don't let "it's only consulted by section" be the deciding vote against converting a document — that's a factor to disclose, not a veto**, once the person paying the sync cost has said the cost is acceptable.
- **Tier 2 — Chinese only, not converted.** Everything consulted by section/decision number rather than read end-to-end, where no one has asked for the exception above — the design book foremost among them — plus phase plans, retrospectives, the pitfalls log, component-level documents, and ops/maintenance handbooks. A large reference-by-section document defaults to Tier 2 regardless of which family it nominally belongs to, unless explicitly pulled into Tier 1 as above. Historical records in this tier are additionally never to be rewritten, only relocated.

⚠️ **A phase plan (`docs/plans/0N-*.md`) gets a forward-looking exception, not a retroactive one.** It is Tier 2 by default — Phase 1/2/3's plans stay Chinese, and are never retroactively translated purely for consistency (their translation cost is large relative to how rarely a shipped phase's plan is reopened, and the design book's precedent already establishes that "consulted by lookup" is a legitimate reason to stay Tier 2). But a phase plan differs from the rest of Tier 2 in one respect while its phase is still active: it is the literal, day-by-day task checklist a session works from for the entire duration of that phase — a far higher re-read frequency than a retrospective or a research dossier ever gets, even though it becomes purely historical the moment the phase ships, exactly like the others. Because of that, **a new phase's plan may be authored directly in English with a Chinese mirror from the moment it is created**, at the authoring session's discretion, without first having to clear the general Tier-1 bar the way `00-master-guide.md` needed an explicit exception to clear it. Phase 1/2/3 were written before this distinction existed and are grandfathered as Chinese-only; Phase 4 onward can start in English if the session judges that phase will be substantial enough to be read from repeatedly.
  Research/investigation dossiers (`docs/design/_调研记录/*.md` — the long-form record of the reference-implementation research behind a phase's design plans, condensed into that phase's design documents themselves) and retrospectives do **not** get this exception, even though they are procedurally paired with a phase plan. They are written once, near a phase's start or end, and cited occasionally afterward — that access pattern does not change while the phase is active, unlike the plan itself, so there is no forward-looking case for translating them; they stay Tier 2 going forward as well as retroactively.

**Chinese-mirror convention**: the AI's own working tree stays English-only — no Chinese files are interleaved next to the documents it reads day to day. Every Tier-1 document's Chinese version lives under `docs/zh/`, at the same relative path it would have from the repository root, just rooted under `docs/zh/` instead. So the Chinese version of `AGENTS.md` is `docs/zh/AGENTS.md`, and the Chinese version of `docs/standards/04-testing-standard.md` is `docs/zh/standards/04-testing-standard.md`. Content stays in exact parity with its English original — every edit to a Tier-1 document carries the same edit into its `docs/zh/` mirror in the same commit. `CLAUDE.md` has no mirror (it is a one-line `@AGENTS.md` include with no content of its own).

⚠️ **"Exact parity" means the prose, not the literal bytes of every relative link.** A mirror under `docs/zh/` sits one or more directories deeper than its English original, so any relative markdown link (`](docs/...)`, `](../...)`) needs its `../` depth adjusted to still resolve from the mirror's actual location — copying the file byte-for-byte silently breaks every relative link it contains. Verify this after any mirror update: pick a few links and confirm the path they resolve to actually exists.

## 7. The Regulatory Document Index

This is the closed set §2.4's fallback rule points at — it spans both tiers; §6 says which tier each row is in.

| Document | Tier | Chinese mirror | What it governs |
|---|---|---|---|
| `AGENTS.md` | 1 | `docs/zh/AGENTS.md` | Index, non-negotiables, routing table, the pitfalls-with-symptoms list |
| `docs/standards/00-master-guide.md` | 1 | `docs/zh/standards/00-master-guide.md` | Ports/schema registries, global constraints, all SOP-* series, phase overview |
| `docs/standards/01-documentation-standard.md` | 1 | `docs/zh/standards/01-documentation-standard.md` | This document |
| `docs/standards/02-reference-implementation-standard.md` | 1 | `docs/zh/standards/02-reference-implementation-standard.md` | How to consult a real-world reference implementation responsibly; recognizing a slot-family signal |
| `docs/standards/03-ai-development-standard.md` | 1 | `docs/zh/standards/03-ai-development-standard.md` | Design-pattern judgment, session sizing, what a human reviews, when to rewrite vs. patch — all specific to AI-driven development |
| `docs/standards/04-testing-standard.md` | 1 | `docs/zh/standards/04-testing-standard.md` | The complete testing specification: layers, TDD cycle, naming, infra |
| `docs/standards/05-data-construction-standard.md` | 1 | `docs/zh/standards/05-data-construction-standard.md` | Seed data vs. test data, cross-component data collaboration |
