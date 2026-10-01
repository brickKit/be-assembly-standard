[English](08-documentation.md) · [中文](../../zh/01-conventions/08-documentation.md)

# Documentation conventions

How this project's documents are laid out, written, split and translated. The primary reader is an AI doing development work here, of any capability: write for the weaker model. The secondary reader is the human maintainer, who reads the Chinese translations.

## Formal and development areas

| Area | Where | Holds | Rules |
|---|---|---|---|
| **Formal** | root `AGENTS.md`, `README.md`, `docs/en/` and its mirror `docs/zh/` (conventions, decisions, seed data), every component's and shell's documents | conclusions that hold now | English primary with a Chinese version (see [Language](#language)); never links into `dev/` or `archive/` |
| **Development** | `dev/` | plans, test records, routing tests, work in progress | Chinese only; may link anywhere; archived when the work it serves is done |
| **Archive** | `archive/` | frozen documents of earlier work | never edited, never linked from formal documents |

**`make docs-boundary`** fails when a formal document links into `dev/` or `archive/`. It is part of `make gates` and of the pre-commit hook.

A formal document holds what is true now. How it got there (what happened, in which order, which bug led to which rule) is history: it lives in Git, in the release notes of a tag, and in `dev/` while the work is going on. A formal document carries no version history and no incident narrative; a rule that came from an incident keeps its symptom and its reason, and drops the story.

## Language

- **English is canonical.** Every formal document has a Chinese version; where it lives depends on the kind of document.
- **Project documents are two mirrored trees.** `docs/en/` holds the English documents and `docs/zh/` the Chinese ones, file for file: the same relative paths and the same file names, with no `.zh` suffix (`docs/en/01-conventions/02-backend.md` / `docs/zh/01-conventions/02-backend.md`). Why: there are many of them, grouped into numbered topic folders, and with two identical trees a link from one document to another is the same text in both languages.
- In the trees, the first line of each file links its counterpart: `docs/en/01-conventions/02-backend.md` starts with `[English](02-backend.md) · [中文](../../zh/01-conventions/02-backend.md)`, and the Chinese file with `[English](../../en/01-conventions/02-backend.md) · [中文](02-backend.md)`.
- **Root documents and component documents follow brickKit's suffix rule**: the translation sits next to the primary as `<name>.zh.md` (`AGENTS.md` / `AGENTS.zh.md`, `BRICKKIT.md` / `BRICKKIT.zh.md`, a component's `docs/design.md` / `docs/design.zh.md`), and the first line links the two: `[English](AGENTS.md) · [中文](AGENTS.zh.md)`. Why: `brickkit lint` finds a translation by that suffix, and `brickkit add` and `brickkit publish` carry a component's documents by it. `BRICKKIT.md` has no relative links at all (it is read alone in other projects' caches).
- Both versions have the same `##` sections in the same order. A change edits both in the same commit; when they drift, the English one is right.
- Parity is in the prose, not in every byte: check that relative links resolve from both files. A link to a section of a Chinese document uses the Chinese heading's anchor.
- **`make docs-mirror`** fails when the two trees differ: a file on one side only, a pair with a different number of `##` sections, or a first line that does not link the counterpart. It is part of `make gates` and of the pre-commit hook.
- `dev/` is Chinese only. Code comments are Chinese. Conversation with the maintainer is always in Chinese, whatever language the file under discussion is in.

## Project documents

| Document | Answers |
|---|---|
| `AGENTS.md` | what the project is, its conventions (one line each, linked here), where to look for what, the pitfalls that hold for every component. Loaded every session, so it stays an index; the component table at its end is maintained by brickKit |
| `README.md` | the human entry point: what this is, quick start, where the documents are |
| `docs/en/README.md` | the index of the tree: what each folder holds and the order to read them in |
| `docs/en/01-conventions/` | the rules in detail (this folder) |
| `docs/en/02-decisions/` | the decisions that constrain future changes, in four topic folders |
| `docs/en/03-seed-data.md` | what demo data exists and how to log in |
| `docs/zh/` | the same tree in Chinese |

The project documents are an index plus leaves. The index (`AGENTS.md`) is thin and stable; each component's documents are self-contained and assume the reader has read no other component. There is deliberately no digest of all components: it would go stale, and a stale digest reads as authoritative.

## Component documents

Every component and every shell carries:

| File | Reader | Holds |
|---|---|---|
| `BRICKKIT.md` (+ `.zh.md`) | projects using the component, and their AIs | Purpose (what it owns, what it doesn't and who does), Before you deploy (databases and roles to create, secrets), Dependencies, Configuration (every required key), Contracts, Shell declaration |
| `AGENTS.md` (+ `.zh.md`, a project addition: brickKit itself does not translate `AGENTS.md`) | the AI changing the component | Code map, Build and test, Design decisions, Pitfalls (never / symptom / why), Before changing code, then the block brickKit maintains |
| `CLAUDE.md` | Claude Code | exactly `@AGENTS.md` |
| `README.md` (+ `.zh.md`) | people on GitHub | Use it in a project, Documentation (which file answers which question), Development |
| `docs/design.md` (+ `.zh.md`) | whoever changes the design | conclusions only: the boundary (and what is explicitly not this component's); the data it owns (tables, partitioning, terminal states); the contract surface (rpcs including `batchGet`, REST paths with permission keys, idempotent endpoints, status endpoints); events published and consumed; dependencies, and why not some expected one; its place in the synchronous call graph; partitioning and archival; data scopes or why none; reference implementations ([10-reference-implementations.md](10-reference-implementations.md#recording-what-was-consulted)); open questions |

- `brickkit lint --strict` checks the structure (run it as `make docs-check ID=<scope>/<name>`, or `ID=be/<name>` for a shell, not as a bare `brickkit lint` in the component directory: inside a project that walks up to `brickkit.yaml` and lints the whole project, and there is no flag to scope it to one component, so the target lints a temporary copy of the component outside the project), and must pass with zero warnings.
- **One fact, one home**: dependencies and configuration keys live in `component.yaml`, interfaces in `contracts/`, history in Git. Documents explain what those can't say.
- **Two readers** for every component document: someone changing this component now (needs exact, current detail) and someone arriving cold to understand the project through this component (needs enough context to see why it exists and how it fits). Check both before calling a document finished.
- **A component's `AGENTS.md` never copies a project-wide rule.** Its pitfalls are the ones only met while working on this component; a copy is a promise to keep two in step, and the stale one is what makes an AI confidently wrong.
- **A component's `AGENTS.zh.md` contains a translated `## BrickKit` section** mirroring the heading of the brickKit-maintained block at the end of `AGENTS.md` (the block itself stays only in the primary file): `brickkit lint` counts that block's `## BrickKit` among the primary's sections when it checks translation parity.
- **Rules for any AI-facing document**: no "see above" or "as mentioned before" (an AI may only see a fragment), and every prohibition carries its symptom and its reason (the symptom is the AI's only way to notice it got it wrong).
- `docs/design.md` exists before work starts and changes with the design: when implementation shows the design was wrong, the document changes first.
- The documents are part of the version: they change in the same commit as the code they describe.

## Decisions

`docs/en/02-decisions/` holds only the decisions that constrain future changes: a choice that, if forgotten, someone would undo or argue again. Each record states the decision and two or three sentences of why, and lives in the topic folder it belongs to (`01-architecture/`, `02-permissions/`, `03-contracts-and-data/`, `04-frontend/`). Each folder has its own number range (`01-architecture/` 0101–0199, `02-permissions/` 0201–0299, and so on), so a folder's numbers stay contiguous; a number is assigned once and never reused. Smaller decisions stay in the documents they shaped. The index and the format are in [../02-decisions/README.md](../02-decisions/README.md).

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
