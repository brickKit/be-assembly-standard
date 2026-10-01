[English](documentation.md) · [中文](documentation.zh.md)

# Documentation conventions

How this project's documents are laid out, written, split and translated. The primary reader is an AI doing development work here, of any capability: write for the weaker model. The secondary reader is the human maintainer, who reads the Chinese translations.

## Formal and development areas

| Area | Where | Holds | Rules |
|---|---|---|---|
| **Formal** | root `AGENTS.md`, `README.md`, `docs/` (conventions, decisions, ops, `seed-data.md`), every component's and shell's documents | conclusions that hold now | English with a `.zh.md` translation; never links into `dev/` or `archive/` |
| **Development** | `dev/` | plans, test records, routing tests, work in progress | Chinese only; may link anywhere; archived when the work it serves is done |
| **Archive** | `archive/` | frozen documents of earlier work | never edited, never linked from formal documents |

**`make docs-boundary`** fails when a formal document links into `dev/` or `archive/`. It is part of `make gates` and of the pre-commit hook.

A formal document holds what is true now. How it got there (what happened, in which order, which bug led to which rule) is history: it lives in Git, in the release notes of a tag, and in `dev/` while the work is going on. A formal document carries no version history and no incident narrative; a rule that came from an incident keeps its symptom and its reason, and drops the story.

## Language

- **English is canonical.** Every formal document has a translation next to it named `<name>.zh.md` (`backend.md` / `backend.zh.md`, `AGENTS.md` / `AGENTS.zh.md`).
- The first line of both links the two: `[English](backend.md) · [中文](backend.zh.md)`. `BRICKKIT.md` follows brickKit's own rule instead (no relative links; it is read alone in other projects' caches).
- Both versions have the same `##` sections in the same order. A change edits both in the same commit; when they drift, the English one is right.
- Parity is in the prose, not in every byte: check that relative links resolve from both files.
- `dev/` is Chinese only. Code comments are Chinese. Conversation with the maintainer is always in Chinese, whatever language the file under discussion is in.

## Project documents

| Document | Answers |
|---|---|
| `AGENTS.md` | what the project is, its conventions (one line each, linked here), where to look for what, the pitfalls that hold for every component. Loaded every session, so it stays an index; the component table at its end is maintained by brickKit |
| `README.md` | the human entry point: what this is, quick start, where the documents are |
| `docs/conventions/` | the rules in detail (this directory) |
| `docs/decisions/` | the decisions that constrain future changes |
| `docs/ops/` | deploying and choosing a topology |
| `docs/seed-data.md` | what demo data exists and how to log in |

The project documents are an index plus leaves. The index (`AGENTS.md`) is thin and stable; each component's documents are self-contained and assume the reader has read no other component. There is deliberately no digest of all components: it would go stale, and a stale digest reads as authoritative.

## Component documents

Every component and every shell carries:

| File | Reader | Holds |
|---|---|---|
| `BRICKKIT.md` (+ `.zh.md`) | projects using the component, and their AIs | Purpose (what it owns, what it doesn't and who does), Before you deploy (databases and roles to create, secrets), Dependencies, Configuration (every required key), Contracts, Shell declaration |
| `AGENTS.md` (+ `.zh.md`) | the AI changing the component | Code map, Build and test, Design decisions, Pitfalls (never / symptom / why), Before changing code, then the block brickKit maintains |
| `CLAUDE.md` | Claude Code | exactly `@AGENTS.md` |
| `README.md` (+ `.zh.md`) | people on GitHub | Use it in a project, Documentation (which file answers which question), Development |
| `docs/design.md` (+ `.zh.md`) | whoever changes the design | conclusions only: the boundary (and what is explicitly not this component's); the data it owns (tables, partitioning, terminal states); the contract surface (rpcs including `batchGet`, REST paths with permission keys, idempotent endpoints, status endpoints); events published and consumed; dependencies, and why not some expected one; its place in the synchronous call graph; partitioning and archival; data scopes or why none; reference implementations ([reference-implementations.md](reference-implementations.md#recording-what-was-consulted)); open questions |

- `brickkit lint --strict` checks the structure (`make docs-check ID=<scope>/<name>` runs it inside a component), and must pass with zero warnings.
- **One fact, one home**: dependencies and configuration keys live in `component.yaml`, interfaces in `contracts/`, history in Git. Documents explain what those can't say.
- **Two readers** for every component document: someone changing this component now (needs exact, current detail) and someone arriving cold to understand the project through this component (needs enough context to see why it exists and how it fits). Check both before calling a document finished.
- **A component's `AGENTS.md` never copies a project-wide rule.** Its pitfalls are the ones only met while working on this component; a copy is a promise to keep two in step, and the stale one is what makes an AI confidently wrong.
- **Rules for any AI-facing document**: no "see above" or "as mentioned before" (an AI may only see a fragment), and every prohibition carries its symptom and its reason (the symptom is the AI's only way to notice it got it wrong).
- `docs/design.md` exists before work starts and changes with the design: when implementation shows the design was wrong, the document changes first.
- The documents are part of the version: they change in the same commit as the code they describe.

## Decisions

`docs/decisions/` holds only the decisions that constrain future changes: a choice that, if forgotten, someone would undo or argue again. Each record states the decision and two or three sentences of why. Numbers are assigned once and never reused. Smaller decisions stay in the documents they shaped. The index and the format are in [../decisions/README.md](../decisions/README.md).

## Writing rules

1. **Current state apart from history.** A "current state" section says what is true now and never accretes how it got there.
2. **Nothing accretes inside one cell or one paragraph.** Anything that gains an entry per task or per component gets its own addressable place: a file, a table with one row per unit, a numbered list.
3. **Split along the axis that avoids forced double reads.** Not by topic resemblance: list the tasks that will consult each candidate document; if most need both, they are one document.
4. **Routing tables are keyed by the words a requester uses** ("who can call this endpoint", "how do I test permission boundaries"), not by a summary of the problem, and always end with a fallback.
5. **Long-lived documents are addressable**: stable headings or table rows that can be linked to.
6. **Redundancy is deliberate and bounded.** The few rules that are broken silently and are expensive to discover are repeated in the always-loaded `AGENTS.md`, on purpose; nothing else is.
7. **Documents needed together point at each other.** Never rely on an AI inferring that a second document exists.
8. **One document, one job.** Each document says in one sentence what question it answers and for whom.

## Splitting and restructuring

Split a document when all three hold: the content hides the parent's own purpose; it answers a different question, not a related topic; and splitting won't force routine tasks to read both. A conventions file is a specification, not a record: rewrite it freely.

The default is to edit or extend an existing document. Splitting into new files, renaming long-standing files or reorganising links across many files is proposed to the human first, not executed unilaterally.
