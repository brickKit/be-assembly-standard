[English](AGENTS.md) · [中文](AGENTS.zh.md)

# be/go-core

The AI guide to developing this shell. What it hosts and how to deploy it: `BRICKKIT.md`. Members, configuration and port: `component.yaml`.

## Code map

| Path | Owns |
|---|---|
| `main.go` | The whole program: `shell.Main("be-go-core", shell.Registry{...})`, one entry per member mapping its ID to its `module.New` |
| `go.mod` | The be-sdk-go version and, per member, its Go module at the exact version in `shell.members` |
| `go.sum` | Checksums for `go.mod` |
| `Dockerfile` | Two-stage build; the runtime stage is alpine with `/bin/sh` and `wget`, and holds `component.yaml` next to the binary |
| `component.yaml` | Members (`shell.members`), the shell's own configuration keys, port 8090, health check |
| `BRICKKIT.md` | What a project must know to deploy the shell |

| Task | Start here | Then |
|---|---|---|
| Add a member | `shell.members` in `component.yaml` | its `module.New` in the Registry in `main.go`, its module in `go.mod`, the Shell declaration in `BRICKKIT.md` |
| Move a member to a new version | `shell.members` | `go.mod`, then bump `metadata.version` and rebuild |
| Change the shell's own configuration | `configSchema` in `component.yaml` | Configuration in `BRICKKIT.md` |

## Build and test

```bash
go build -o /dev/null ./...        # compiles the shell and every registered member
brickkit build be/go-core           # the image, tagged with metadata.version; needs the shell in brickkit.yaml
brickkit lint --strict             # manifest and documents
```

Success: `go build` prints nothing; `brickkit build` records in the image the member versions it compiles in, which `brickkit up` checks; the container turns healthy and `GET /healthz` on port 8090 answers 200.

The shell has no tests of its own: the launcher and its failure contract are tested in be-sdk-go, and each member is tested in its own repository.

## Design decisions

- The shell is project code, not a repository of its own: which components share a process is this project's deployment choice, so it changes together with `brickkit.yaml` and the deploy file (project decision 0022, shells are project code).
- One shell is one image with one member list: `shell.members` names the exact member versions compiled in, and the Registry in `main.go` lists exactly those members.
- All launcher logic lives in the SDK (`shell.Main`), so this directory stays a list of members and cannot grow logic of its own.
- The shell never runs migrations: brickKit runs each member's migration from the member's own image before the shell starts.

## Pitfalls

| Never | Symptom | Why |
|---|---|---|
| Leave `shell.members` empty and expect the manifest to load | `brickkit lint` and `brickkit add` refuse it: `MANIFEST_INVALID`, "a shell must list at least one component compiled into it"; the shell cannot be added to the project or built with `brickkit build` | brickKit requires at least one compiled-in member. A deployment that hosts none of them is still legal: it is chosen in the deploy file, and the SDK then starts with `BRICKKIT_SERVED_MEMBERS_CONFIG` set to `[]` and serves only `/healthz` |
| Drop `COPY component.yaml` from the `Dockerfile`, or change the working directory | The container exits at once: "读外壳自己的 component.yaml 失败" | `shell.Main` reads its own port (8090) from `deployment.port` in `./component.yaml` |
| Run the shell without `AUTHZ_BUNDLE_URL` or `IAM_JWKS_URL` | The process exits at start with a message naming the missing key ("缺少权限地址配置") | The Go shell loads the permission bundle and the signing keys once for the whole process; without them every member would answer `403` / `503` on every protected route, so it refuses to start |

## Before changing code

1. Adding, removing or moving a member changes `shell.members`, the Registry in `main.go` and `go.mod` together, and the Shell declaration in `BRICKKIT.md`.
2. Every member has a row in `registry/schemas.tsv`; `make db-init` grants its role to `shell_go_core` and refuses a member without one.
3. A changed member list or member version means a new `metadata.version` for the shell and a rebuild; `brickkit up` stops a stale image with `IMAGE_STALE`.
4. Code here only registers members: no route, handler, query or call between members.
5. Run `brickkit lint --strict` and the build in Build and test before committing.

<!-- brickkit:managed:begin lang=en -->
<!-- maintained by brickkit (init, add, remove, upgrade, skills update): edits between these markers are overwritten -->

## BrickKit

This is a BrickKit component: `component.yaml` is all the platform reads. The rules it relies on:

- `configSchema` keys are the environment variable names the code reads. Never use a reserved name: `COMPONENT_ID`, `COMPONENT_VERSION`, `PORT`, `BRICKKIT_SERVED_MEMBERS`, `BRICKKIT_SERVED_MEMBERS_CONFIG`, or any `*_ENDPOINT`.
- Dependencies are exact versions. A dependency's address arrives as `<ID>_ENDPOINT`; an optional dependency that is absent has no variable at all, so read it with a fallback.
- `/healthz` checks only this process, never a dependency. The migration command runs from the same image and must fail on an argument it does not know.
- `BRICKKIT.md` travels to every project that uses this component and is read there without the repository: keep it in step with the code, with no relative links.
- Release: raise `metadata.version`, commit, push, `brickkit release`. `brickkit lint` checks the manifest and these docs.
- The full rules are in the `brickkit-component` skill (`.claude/skills/brickkit-component/SKILL.md` at the root of the project or repository where skills are installed; `brickkit skills update` installs it); for flags ask `brickkit <command> --help`.
<!-- brickkit:managed:end -->
