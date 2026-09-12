# Arsenal Maintenance Handbook

> For **developers**: how to wire a component's source into this repository, how to focus on a handful of components day to day, and what to check before committing.
> For deployment, see [`docs/ops/部署手册.md`](ops/部署手册.md); for the pitfalls log, see [`docs/dev/field-tested-pitfalls-log.md`](dev/field-tested-pitfalls-log.md).

## Three Steps to Get Started on a New Machine

```bash
git clone --recurse-submodules git@github.com:brickKit/be-assembly-standard.git
cd be-assembly-standard
git config core.hooksPath .githooks     # ⚠️ this one is not distributed with the repo, must be run by hand
cp .env.example .env                    # fill in real values
make up                                 # bring up base resources
```

Already cloned but missing submodules: `git submodule update --init --recursive`

## The Day-to-Day Development Loop (Local Focus)

```bash
# 1. Keep only the components you're touching
#    Edit brickkit.yaml: write enabled: false for irrelevant top-level components
brickkit sync            # everything else moves into components/.archived/, so the IDE and grep both stay clean

# 2. Develop, test…

# 3. Restore the structure before committing (or pre-commit will block you)
make arsenal-restore     # restores enabled and the directory structure to match brickkit.yaml
git status               # double-check
git commit -m "..."
```

## Three Prohibitions

| Prohibition | Why |
|---|---|
| **`commit & push` before `brickkit remove`** | It **deletes the archived source directory along with everything else** (§9.4.2). If a submodule directory has unpushed changes, this is data loss |
| **Never change an already-allocated port or schema** | See the port registry in [`registry/README.md`](../registry/README.md); a gRPC port has no after-the-fact remedy |
| **Never change `metadata.id` or `version` in a forked component** | Doing so makes every dependent's `*_ENDPOINT` **disappear entirely** — the variable name the platform injects is derived from the component ID. The whole fork mechanism collapses on the spot (§3.4.1) |

## When Source Code Can't Be Found

Check `components/.archived/` first — it starts with a `.`, hidden by default in file managers (§9.4.2).

## Adding a Component to the Arsenal

See the Master Guide §3.5, "The Standard Steps for a Repository-Creation Checkpoint." Three steps: build the directory → stop and ask a human to create the repo → `git init` + push + `git submodule add`.

## How the pre-commit Gate Works

`.githooks/pre-commit` calls `infra/scripts/arsenal.sh check`. Its logic:

1. `components/` isn't tracked yet (the default state) → passes at zero cost
2. In the middle of a merge conflict → passes with a warning
3. `brickkit` isn't on `PATH` → passes with a warning
4. **If `brickkit restore --help` runs successfully, delegate straight to the official command** (`brickkit restore --check` / `brickkit restore`) — **this is the path actually taken today**; the local fallback implementation only takes over when the official command is unavailable
5. Fallback implementation: compute "which components should be running right now" from `brickkit up --dry-run`, then check each one that only one of `components/<id>` and `components/.archived/<id>` actually has source in it

Three ways out when it blocks you: `make arsenal-restore` (forgot to restore after a local-focus session) / commit `enabled: false` along with it (a declared intent) / `git commit --no-verify` (not recommended).
