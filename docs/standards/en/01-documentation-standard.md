# Documentation Standard

*[中文](../zh/01-documentation-standard.md)*

## 1. Scope and Authority

This document governs how documentation in this repository is structured, split, cross-referenced, and evolved over time. It applies to the project-level regulatory documents (`AGENTS.md`, the `docs/standards/*.md` family) and sets the cross-cutting design criteria that component-level documents (governed day-to-day by `00-master-guide.md`'s SOP-D) must also satisfy. It does not replace SOP-D's four-document checklist — it adds the judgment calls SOP-D doesn't cover: when a document should split, what growth signals a problem, and how a set of documents should talk to each other.

Primary reader: an AI assistant doing development work in this repository, at any capability level — treat a lower-effort or less capable model as the baseline this document is written for, not the exception. Secondary reader: the human maintainer, who reads the parallel Chinese-language companion of any bilingual document (§6).

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

**One convention, applied for two different reasons.** A document earns a genuine second-language version either because an AI session reads it in full and English measurably reads faster, or because the shipped product's own end users need it in their language (the product supports English and Chinese, defaulting to English) — sometimes both at once. Either reason uses the same mechanism:

- **A multi-file documentation category** gets a nested `docs/<category>/{zh,en}/<file>.md` folder pair, both language versions sharing the identical filename: `docs/standards/en/00-master-guide.md` / `docs/standards/zh/00-master-guide.md`, `docs/design/en/_replaceability-map.md` / `docs/design/zh/_replaceability-map.md`, `docs/ops/en/deployment-handbook.md` / `docs/ops/zh/deployment-handbook.md`.
- **A single standalone file** not part of a larger category gets a flat sibling next to it, named `<name>.zh.md`: `AGENTS.md`/`AGENTS.zh.md` at the repo root (this one specifically cannot move into a folder — Claude Code's own tooling requires `AGENTS.md` to sit at the repo root), `docs/arsenal-maintenance-handbook.md`/`.zh.md`.

Both patterns carry the same discipline: **whichever language is edited first for a change, update its sibling in the same commit.** Each file links to its counterpart near the top (`*[English](...)*` / `*[中文](...)*`).

**Which language is canonical — the one to trust when the two drift, and the one a session edits first by default — depends on why the document needed a second language, not on which of the two patterns above it uses:**
- `AGENTS.md` and `docs/standards/*` are read by an AI session in full, where reading speed is the deciding factor — **English is canonical**.
- `docs/design/_replaceability-map.md` — the one document in `docs/design/` that goes through this system at all (see below) — and `docs/ops/`: canonical is whichever language was authored first for a given change; end users in either language are equally real, so there's no default direction, only "keep both in sync."

⚠️ **`00-master-guide.md` fails the "read start to end" test and is in the English-canonical group anyway.** Its own §W-4 still tells a session not to read it end-to-end — that hasn't changed. It earned English-canonical status on explicit instruction: the project maintainer judged the mirror-maintenance cost (this is the largest, most frequently edited document in the project) worth paying purely for AI reading/editing comfort, independent of whether the per-lookup speed gain is large. There's a secondary coherence argument too — every other standard cross-references this document by name and section (e.g. "Master Guide §4 SOP-R's R-2 table"), so keeping it English removes a language switch at exactly those junctions. The lesson generalizes: **"it's only consulted by section" is a factor to disclose when proposing a document join this system, not a veto** — once whoever pays the sync cost has said the cost is acceptable, that argument is settled.

**`docs/design/` is mostly developer-only material, and only one file in it goes through this system.** The 14 per-component design plans and the folder's own `README.md` are read almost entirely by whoever is developing or extending a component — real end users have no reason to read them — so they stay single Chinese files, same as any other developer-only document, not part of the `{zh,en}` system at all. **`_replaceability-map.md` is the one exception**: it answers "what can I swap out or customize, and what does that drag in" — a question real end users (anyone evaluating the product, not just its developers) genuinely need answered — so it alone keeps the `{zh,en}` pair. `docs/design/_模板.md` is an authoring template for whoever writes the *next* design plan, not reference content anyone reads, so it stays a single file with no language pair at all, exactly like the 14 plans it's a template for.

**What stays outside this system entirely, Chinese-only, un-migrated**: `docs/plans/`, `docs/retrospectives/`, `docs/design/_调研记录/` (the long-form research dossiers behind a phase's design plans — a phase's design plans themselves condense the relevant findings, so this is genuinely a different, rarely-revisited document), and `docs/dev/field-tested-pitfalls-log.md` (a historical record in substance — each entry documents something that already happened and was already fixed — even though it's actively grep'd for pitfall codes; it briefly had an English pair, collapsed back to Chinese-only once it was recognized as belonging in this category rather than the AI-reads-it-in-full one). These are execution-process narrative — written once (or, for the pitfalls log, appended to occasionally), cited by lookup rather than read wholesale as ongoing reference — and the cost of full bilingual parity for them isn't judged worth paying. **Historical records in any of these are never rewritten for a path change — only relocated if the file itself physically moves.**

⚠️ **A phase plan (`docs/plans/0N-*.md`) gets a forward-looking exception, not a retroactive one.** Phase 1–3's plans stay Chinese-only permanently — they are never retroactively translated purely for consistency (their translation cost is large relative to how rarely a shipped phase's plan is reopened). But while a phase is still active, its plan is the literal day-by-day task checklist a session works from — a far higher re-read frequency than a retrospective or research dossier ever gets, even though it becomes purely historical the moment the phase ships, exactly like the others. Because of that, **a new phase's plan may be authored directly in English with a Chinese mirror from the moment it's created**, at the authoring session's discretion, without first needing the case this section makes for `docs/standards/`/`docs/design/`/`docs/ops/`. Research dossiers and retrospectives do **not** get this exception even when procedurally paired with a phase plan — see the previous paragraph.

⚠️ **"Parity" means the prose, not the literal bytes of every relative link.** Two files in a `{zh,en}/` pair sit at the same depth from the repo root, so a link that resolves in one resolves in the other *only if what it points at is reachable at the same relative depth from both* — this must be re-verified after any structural move (a file relocating, a category gaining a language pair for the first time), not assumed to still hold. This is exactly what bit the September 2026 migration that first split `docs/standards/` into `{zh,en}/` pairs: the English files moved one directory deeper than their Chinese counterparts already sat at, and every relative link reaching outside the immediate folder needed its `../` count re-derived by hand, file by file.

## 7. The Regulatory Document Index

This is the closed set §2.4's fallback rule points at.

| Document | Chinese pair | What it governs |
|---|---|---|
| `AGENTS.md` | `AGENTS.zh.md` | Index, non-negotiables, routing table, the pitfalls-with-symptoms list |
| `docs/standards/en/00-master-guide.md` | `docs/standards/zh/00-master-guide.md` | Ports/schema registries, global constraints, all SOP-* series, phase overview |
| `docs/standards/en/01-documentation-standard.md` | `docs/standards/zh/01-documentation-standard.md` | This document |
| `docs/standards/en/02-reference-implementation-standard.md` | `docs/standards/zh/02-reference-implementation-standard.md` | How to consult a real-world reference implementation responsibly; recognizing a slot-family signal |
| `docs/standards/en/03-ai-development-standard.md` | `docs/standards/zh/03-ai-development-standard.md` | Design-pattern judgment, session sizing, what a human reviews, when to rewrite vs. patch — all specific to AI-driven development |
| `docs/standards/en/04-testing-standard.md` | `docs/standards/zh/04-testing-standard.md` | The complete testing specification: layers, TDD cycle, naming, infra |
| `docs/standards/en/05-data-construction-standard.md` | `docs/standards/zh/05-data-construction-standard.md` | Seed data vs. test data, cross-component data collaboration |
