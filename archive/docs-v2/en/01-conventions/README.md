[English](README.md) · [中文](../../zh/01-conventions/README.md)

# Project conventions

The rules every component, shell and tool in this project follows. brickKit's skills (`.claude/skills/brickkit-*`) describe the platform for any project; these files say how this project uses it. Where the two overlap, the overlap is deliberate: the readers differ.

## Files

| File | Read it when you are |
|---|---|
| [01-development-workflow.md](01-development-workflow.md) | starting work on a component; ordering the steps; running it for real; bumping a version; releasing |
| [02-backend.md](02-backend.md) | writing Go or Python backend code: stack, module entry, `rt`, permissions, data scopes, calls to other components, SQL, events, health check |
| [03-frontend.md](03-frontend.md) | writing frontend code: stack, design tokens, ui-kits, page templates, the PC skeleton, preferences, features and permissions, i18n |
| [04-configuration.md](04-configuration.md) | naming a config key; wiring PostgreSQL, NATS, object storage, authz or iam; filling `config/` |
| [05-data.md](05-data.md) | designing seed data or test data; a dependency lacks the data or the capability you need |
| [06-testing.md](06-testing.md) | choosing which test to write and in which layer; running tests; stuck on a red test |
| [07-registries.md](07-registries.md) | choosing a port, a schema, a database role or a permission key |
| [08-documentation.md](08-documentation.md) | writing, splitting or translating a document; component documents; decision records |
| [09-ai-development.md](09-ai-development.md) | deciding whether to use a design pattern; sizing files, functions and sessions; what a human reviews; rewriting instead of patching |
| [10-reference-implementations.md](10-reference-implementations.md) | designing business logic; finding several reasonable designs for one feature |
| [../03-seed-data.md](../03-seed-data.md) | looking for the demo data and the test accounts |

## How these files relate to the others

- **Decisions** say why the project is shaped the way it is and what not to propose: [../02-decisions/README.md](../02-decisions/README.md). When a rule here contradicts a decision, the decision wins and this file gets fixed.
- **A component's own rules** live in its `AGENTS.md` and `docs/design.md`. They add what is specific to that component and never repeat what is here.
- **Platform behaviour** (commands, flags, error codes) belongs to brickKit: the skills, and `brickkit <command> --help`.

## When nothing here matches

These files are the closed set of project-wide rules. Before concluding that no rule covers what you are doing, check each file's headings; then check the decision index; then the component's own `AGENTS.md`.
