[English](README.md) · [中文](../zh/README.md)

# be-assembly-standard documentation

The project-level documents of this repository, in English. The number in front of each folder or file is the reading order. The Chinese documents live in `docs/zh/` and mirror this tree file for file: the same paths, the same file names, the same `##` sections, so a link between two documents is the same text in both trees.

The entry point is [`AGENTS.md`](../../AGENTS.md) at the repository root (for AI assistants) or [`README.md`](../../README.md) (for people); they say which document to open for which task. A component's own documents (`BRICKKIT.md`, `AGENTS.md`, `README.md`, `docs/`) live in the component's directory and keep brickKit's `.zh.md` suffix rule.

## Contents

| No. | Folder or file | What it holds |
|---|---|---|
| 01 | [Conventions](01-conventions/README.md) | The rules every component, shell and tool follows: workflow, backend, frontend, configuration, data, testing, registries, documents, AI-sized code, reference implementations |
| 02 | [Decisions](02-decisions/README.md) | Why the project is shaped this way and what not to propose, in four topic folders: architecture, permissions, contracts and data, frontend |
| 03 | [Seed data](03-seed-data.md) | The demo data, the test accounts, how to log in |

## Read order

1. **Starting work on a component**: [the development workflow](01-conventions/01-development-workflow.md), then the convention for what you are writing ([backend](01-conventions/02-backend.md), [frontend](01-conventions/03-frontend.md)), then [testing](01-conventions/06-testing.md).
2. **Before proposing a change to how the project works**: the [decision index](02-decisions/README.md). A decision wins over a convention.
3. **Exploring the running system**: [seed data](03-seed-data.md).
