[English](0022-shells-are-project-code.md) · [中文](0022-shells-are-project-code.zh.md)

# 0022 Shells are project code: one shell, one image, one member list

## Decision

A shell is code of this project, not a separate repository: it lives in `shell/<scope>/<name>/` and is created with `brickkit new --shell`. The shells are `be/go-core`, `be/go-infra`, `be/go-backoffice` and `be/py-render`, released with tags `<scope>-<name>/<version>`. One shell is one image with one member list: `shell.members` in its `component.yaml` lists the exact member versions compiled in, and its code registers exactly those members — no more, no fewer. Which members a deployment actually hosts is chosen in the deploy file (`members:` under the shell's entry). A shell only turns N processes into one: the launcher logic lives in the SDK, each member's migration still runs from that member's own image, and a shell never mixes languages.

## Why

Which components share a process is a deployment choice of this project, so the shell sits next to `brickkit.yaml` and `deploy.yaml` and changes with them in one commit. The member list is a promise about what is inside the image: a member version that is not compiled in cannot be hosted, and `brickkit up` checks the image's member label. Keeping the launcher in the SDK keeps each shell down to a list of members, so it cannot grow logic of its own.

## What this rules out

- A separate Git repository per shell, or launcher code copied into each shell
- Business logic, routes, data access or calls between members in shell code
- Members calling each other in-process because they share a shell ([0001](0001-no-imports-between-components.md))
- "Upgrade `erp/sales` without touching the shell" — a new member version means bumping, rebuilding and releasing the shell
- A shell whose registered members differ from its `shell.members`
- Mixing Go and Python members in one shell; putting the TypeScript BFF or the frontend in a shell
- Running members' migrations from the shell

`brickkit up --ignore-shells` runs every member on its own and is how the project checks that each component still starts by itself.

## Revisit only if

The same shells have to be shared by several projects; they would then move to their own repositories.
