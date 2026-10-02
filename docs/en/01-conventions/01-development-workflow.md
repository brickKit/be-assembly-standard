[English](01-development-workflow.md) · [中文](../../zh/01-conventions/01-development-workflow.md)

# Development workflow

How a change moves from an idea to a released version in this project. The work is done by an AI and reviewed by a human, so the steps are cut to fit one session each, and a human reviews only what cannot be undone (see [09-ai-development.md](09-ai-development.md#what-a-human-reviews); how much fits in one session: [09-ai-development.md](09-ai-development.md#how-much-in-one-session)).

## The seven-step loop

Every component, and every feature inside one, goes through the same seven steps:

```
① Design the business logic      docs/design.md: boundary, data, contracts, events, dependencies
② Consult reference implementations  your own design first, a reference only where you are stuck
③ Write the contracts            contracts/*.proto, *.openapi.yaml, events/*.json
④ Write the business-rule tests  invariants, state transitions, idempotency (L2), before the code
⑤ Implement                      red → green → refactor, one rule per cycle, one commit per cycle
⑥ Add the unit tests             error paths, empty values, concurrency (L3), after the code
⑦ Integrate                      real PostgreSQL / NATS / gRPC, every gate, the documents
```

**③ before ④ and ④ before ⑤, never the other way round.** A test needs the types the contract generates; without them it tests a `map[string]any` and dies at the first refactor. A test written after the code describes the code that exists: it guards against regressions, never against a requirement misunderstood from the start.

Step ① is [08-documentation.md](08-documentation.md#component-documents), step ② is [10-reference-implementations.md](10-reference-implementations.md), steps ④–⑥ are [06-testing.md](06-testing.md).

**Documentation comes before code.** A changed boundary, contract or event is written into the component's `docs/design.md` first; a changed configuration or dependency into `BRICKKIT.md`; a new prohibition into `AGENTS.md`. The documents change in the same commit as the code.

## Commits

- One red-green cycle per commit. The message says which business conclusion the cycle locked in, not which files changed.
- A commit that changes a test is its own commit and says where the old assertion was wrong ([06-testing.md](06-testing.md#red-green-and-the-iron-rule)).
- Commit messages are written in Chinese, into a file, and committed with `git commit -F <file>`. Look at `git log --oneline -1` before tagging: a message with unbalanced quotes on the command line can fail silently and leave the tag on the previous commit.
- Tags are always annotated (`git tag -a`); `git push --follow-tags` skips lightweight tags without a word.

## Before writing code

Answer these before the first line, every time:

0. **Am I changing a test to make it pass?** By default the implementation changes. If the test is really wrong, stop and say where.
1. **Did I copy the port and the schema from `registry/`?** An invented one is always wrong ([07-registries.md](07-registries.md)).
2. **Am I letting two components know each other's code?** Calls go through gRPC or HTTP and `contracts/`; the only shared code is `be-sdk-*` and a component's generated contract package ([02-backend.md](02-backend.md#calling-other-components)).
3. **Would this still work with twenty other modules in the same process?** No `os.Getenv`, no process-level initialisation, no `log.Fatal` ([02-backend.md](02-backend.md#merge-safety)).
4. **Did I design this myself first and only then read a reference?** ([10-reference-implementations.md](10-reference-implementations.md#the-three-step-method))
5. **Am I packing several customers' variants into one component behind an `if`?** Branches that each serve a different, reasonable customer profile belong in a customer fork (or, in a position nothing depends on, a slot family), not behind a flag ([10-reference-implementations.md](10-reference-implementations.md#slot-family-signal)).
6. **Is the file already too long?** Past 150 lines per function, 600 per file, or 5 branches and growing: see [09-ai-development.md](09-ai-development.md#when-to-use-a-design-pattern).
7. **Which documents does this change touch?** Update them first.

## Running it for real

- **The one-command versions.** `make integrate ID=<scope>/<name>` brings a component (or a shell) into the project: `make dev-env db-init` when it has a database, `brickkit add` (or `brickkit upgrade` to `VERSION=`; the default is `2.0.0`, `1.0.0` for a shell), `config/<repo>.yaml` filled by the rules in [04-configuration.md](04-configuration.md#where-values-live), `make teardown-sync`, `brickkit lint --strict <id>` and `brickkit up --dry-run`. A required key whose value it cannot derive is listed and the run stops; give it with `bash infra/scripts/project-lock.sh -- python3 infra/scripts/config-fill.py <id> --set 'KEY=VALUE'` and run it again (a `secret: true` key accepts only a reference: `${VAR}`, `file://…` or `$var:NAME`). `make verify ID=<scope>/<name> [ROUTE='GET /path'] [FOCUS=1]` then runs it for real: `brickkit build`, only the component's dependency closure started (a generated `deploy.verify.yaml` that turns everything else off), migrations exited 0, `/healthz` 200, the protected route without a token 401 or 503 and with a real token 200 (when infra/authz and infra/iam-casdoor are in the project), `make test-cross`, a focus run with `FOCUS=1`, and `brickkit down` unless `KEEP=1` (only the value `1` turns either on; an interrupted run still stops the focus process and, unless `KEEP=1`, takes the containers down); it prints a table of PASS / FAIL / SKIP with a log file per check. For a shell it checks the hosted members at runtime instead. Both hold the project lock (`infra/scripts/project-lock.sh`), as do `make dev-env`, `db-init`, `test-db-init` and `permissions`: commands that change shared project state (`brickkit add` / `upgrade` / `build` / `up` / `down` / `local`, `config/`, the deploy files, `registry/`, `.env`) run one at a time, so parallel work waits instead of colliding. Run such a command by hand as `bash infra/scripts/project-lock.sh -- <command>`.
- **Build first.** `brickkit up` never builds. After a code change, `brickkit build <id>`; the image tag is `metadata.version`, so an unbumped version reuses the old image (bump, or `--force`).
- **One component at a time.** `brickkit up --focus <id>` starts the component from its source plus everything it needs; `brickkit up --all` goes back to the whole project. `--focus` writes the focus into `deploy.local.yaml` and turns local mode on (copying `deploy.yaml` the first time); `--all` clears the focus but leaves local mode on. While it is on, `up`, `down`, `status` and `build` read `deploy.local.yaml` only, so later edits to `deploy.yaml` have no effect: run `brickkit local off` before editing `deploy.yaml`, or `brickkit local refresh` after.
- **Then test against it.** `make test-cross ID=<scope>/<name>` runs the component's cross-component tests against the real dependency containers ([06-testing.md](06-testing.md#cross-component-tests)); `make tier0` after a component is added to the project.
- **Containers are off by default.** The base resources from `make up` (PostgreSQL, NATS, Casdoor…) may stay up; the project's component containers are for verification and demos. `brickkit down` when done (volumes are kept). A container left running serves a stale version after the next change, and competes with local tests for messages on the same NATS subject.
- **Teardown check.** Every component must still run on its own after shells merge them. `brickkit up --ignore-shells --dry-run` checks it without starting anything; `make teardown-up` / `make teardown-down` runs every member as its own container. Run it whenever a shell's member list changes. `brickkit add` and `upgrade` maintain only `deploy.yaml`; `make teardown-sync` brings `deploy.teardown.yaml` in line with it (`CHECK=1` only compares).
- **Debugging in an IDE** uses `mode: debug` in `deploy.local.yaml` (after `brickkit local on`); never in `deploy.yaml`.

## Versions

- **Every change gets a version bump**, including a change to tests or documents only. The version in `component.yaml`, the Git tag and the image content must always agree: `component.yaml` is copied into the image, and `brickkit build` skips a version whose image already exists.
- **Bump first, then work.** Raise `metadata.version` at the start, edit freely until it is released, and never change a released version in place.
- Versions are exact (`2.0.0`). Components are on the `2.x` line, shells on `1.x`.
- **Go components carry two tags on the same commit**: `2.0.0` for brickKit (no `v`) and `v2.0.0` for the Go toolchain. The module path ends in the major version (`…/v2`), and changes with it.
- **Shells** are repositories of their own, checked out here as Git submodules under `shell/<scope>/<name>/` ([0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)). A shell is released from the root of its own repository like a component, with the bare tag only (`1.0.0`): nothing imports a shell, so it gets no `v` tag.
- **Propagate with the tool, not by hand.** Write one plan file naming every component that really changed in this session, then `make bump-version PLAN=<file>` (prints the cascade, writes nothing) and `make bump-version PLAN=<file> APPLY=1`. It rewrites the dependents' `component.yaml` (their `dependencies` and a shell's `shell.members`) and the shells' `go.mod`. On the project side, `brickkit upgrade <id>@<version> --dry-run`, then without `--dry-run`; it keeps `brickkit.yaml`, the deploy files and `config/` in step. Finish with `brickkit up --dry-run`: it is the command that catches a version drift.
- One plan per batch: running the tool once per component bumps the same dependents twice.

## Releasing

For each component, in the order `bump-version` printed:

1. Its own tests and gates green.
2. Commit and push the component's repository (for a shell, the shell's repository).
3. `brickkit release --notes-file <file>`. The notes file lives outside the component directory (an untracked file fails the clean check). Notes lead with what a project must do (a key whose meaning changed, an endpoint removed), then what was added.
4. Go components, not shells: `git tag -a v<version> -F <the same notes>` and `git push origin v<version>`.

   Steps 2–4 are one command, run by whoever releases: `make ship DIR=components/<scope>/<name> NOTES=<file>` (a shell: `DIR=shell/be/<name>`; `DRY_RUN=1` previews it). It refuses a dirty tree or a branch other than `main`, pushes `main`, tags the contract package `gen/<domain>/<name>/v<x.y.z>` that the root `go.mod` requires when it is not published yet (and fails when a published one differs from `HEAD`), runs `brickkit release`, adds the `v` tag, checks that the release tag and the `v` tag both point at `HEAD` (an already-published contract tag may sit on an older commit; it is compared by content), and finishes with a fetch-and-build probe from a shell's point of view. It stops at the first failure and never force-pushes, deletes or moves anything already pushed; run it again after fixing the cause, and the steps already done pass.
5. `brickkit build <id>`. Images are built locally and never pushed.
6. In this repository: commit the submodule pointer (a shell's like a component's) and what `brickkit upgrade` changed, run it for real, `brickkit down`. After a release of infra/authz or infra/iam-casdoor, also change `AUTHZ_BUNDLE_URL` / `IAM_JWKS_URL` in `config/vars.yaml` to the new service name; `brickkit upgrade` does not touch `$var` values, and `make gates` fails until they match ([04-configuration.md](04-configuration.md#dependency-addresses)).

A shell comes after its members: when a member is released, `make bump-version` has already rewritten the shell's `shell.members` and `go.mod` in its submodule, and the shell then goes through the same steps in its own repository. Never release a shell from this repository (`brickkit release --path`) or tag it here.

The `version-bump-ship` skill walks this sequence and says when to stop and ask instead of continuing.

- A version made only for a test gets a local tag that is never pushed, and is deleted after the test.
- A new GitHub repository is created only when a file is ready to be pushed into it, and the human maintainer is told before any repository is created or deleted.
- `brickkit remove` stops before writing anything while the component's source has uncommitted or unpushed changes; never pass `--force` to get past that, it deletes the source and the work with it. A component registered as a Git submodule stops with `SUBMODULE_GUARD`: commit and push it, deregister it (`git submodule deinit -f <path>`, `git rm <path>`), then run `brickkit remove` again.
- A fork keeps the component's `metadata.id` (every dependent's address variable name is derived from it) but versions normally: every change bumps `metadata.version`, and dependents move their pins with `brickkit upgrade` / `make bump-version`.
- When the platform misbehaves, write a reproduction and report it to brickKit; never work around it inside a component.
