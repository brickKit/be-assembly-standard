[English](0022-one-repository-per-shell.md) · [中文](../../../zh/02-decisions/01-architecture/0022-one-repository-per-shell.md)

# 0022 One shell, one repository, one image, one member list

## Decision

Each shell is its own Git repository, like a component: `be/go-core`, `be/go-infra`, `be/go-backoffice` and `be/py-render` live in `brickKit/be-go-core`, `be-go-infra`, `be-go-backoffice` and `be-py-render`, and this project checks each out as a Git submodule at `shell/<scope>/<name>/`, where the `local-shells` source in `brickkit.yaml` finds it. A shell is released from the root of its own repository with `brickkit release --notes-file`; its tag is the bare version (`1.0.0`), with no `v` tag, because nothing imports a shell as a Go module or Python package. One shell is one image with one member list: `shell.members` in its `component.yaml` lists the exact member versions compiled in, and its code registers exactly those members, no more and no fewer. Adding a member or moving one to a new version is a commit and a release in the shell's repository, then a submodule pointer commit and `brickkit upgrade be/<name>@<version>` here. Which of the compiled-in members a deployment actually hosts is chosen in the deploy file (`members:` under the shell's entry). A shell only turns N processes into one: the launcher logic lives in the SDK, each member's migration still runs from that member's own image, and a shell never mixes languages.

## Why

The shells are reused by other assembly projects (customer projects, a clean starter project), and each of them needs the same image built from the same member list, so a shell cannot be code that lives inside one project. As a repository of its own it is released, pinned and upgraded exactly like a component, and the submodule pointer records which commit this project builds. The member list is a promise about what is inside the image: a member version that is not compiled in cannot be hosted, and `brickkit up` checks the image's member label. Keeping the launcher in the SDK keeps each shell down to a list of members, so it cannot grow logic of its own.

## What this rules out

- Shell code committed directly in this repository instead of in the shell's own repository; launcher code copied into each shell
- Releasing a shell from this repository with `brickkit release --path`, a `be-<name>/<version>` tag here, or a `v` tag on a shell
- Business logic, routes, data access or calls between members in shell code
- Members calling each other in-process because they share a shell ([0001](0001-no-imports-between-components.md))
- "Upgrade `erp/sales` without touching the shell": a new member version means bumping, releasing and rebuilding the shell
- A shell whose registered members differ from its `shell.members`
- Mixing Go and Python members in one shell; putting the TypeScript BFF or the frontend in a shell
- Running members' migrations from the shell

`brickkit up --ignore-shells` runs every member on its own and is how the project checks that each component still starts by itself.

## Revisit only if

No other project ever reuses a shell; the shells could then move back into this repository as project code.
