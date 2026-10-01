[English](README.md) · [中文](README.zh.md)

# be-assembly-standard

BrickEnterprise: an arsenal of ERP/CRM components and the standard project that assembles them with [brickKit](https://github.com/brickKit/brickKit), each component running on its own or merged into shells, on Docker or Kubernetes.

## Quick start

Prerequisites: Docker, the `brickkit` CLI, `make`, `curl`, `python3`. Clone with submodules (`git clone --recurse-submodules`, or `git submodule update --init` afterwards).

```bash
make up            # base resources: PostgreSQL, NATS, Casdoor, Traefik, RustFS
make dev-env       # write a random password for each database role into .env (adds missing ones only)
make db-init       # create the schemas, roles and grants (idempotent)
brickkit build     # build the images of the components in this project
brickkit up        # start every component listed in brickkit.yaml
make seed-data     # demo data and test accounts (log in as dev.superuser / DevSeed123!)
brickkit down      # stop the component containers when you are done (data is kept)
```

`make help` lists every target; `make check` says which base resource is missing or misconfigured. The demo data and the other test accounts are described in [docs/seed-data.md](docs/seed-data.md).

## Documentation

| Question | Read |
|---|---|
| I'm an AI (or briefing one): what is this project, what are the rules, where do I look | [AGENTS.md](AGENTS.md) |
| The rules every component follows: configuration, workflow, backend, frontend, testing, data, registries | [docs/conventions/](docs/conventions/README.md) |
| Why the project is shaped this way; what has been ruled out | [docs/decisions/](docs/decisions/README.md) |
| What demo data exists; how to log in | [docs/seed-data.md](docs/seed-data.md) |
| Deploying: what to prepare, which databases and roles to create, which secrets | each component's `BRICKKIT.md`, section "Before you deploy"; the `brickkit-deploy` skill in `.claude/skills/` |
| What one component does, and how to change it | the component table at the end of [AGENTS.md](AGENTS.md); then `components/<scope>/<name>/BRICKKIT.md` and its `AGENTS.md` |
| brickKit itself: commands, flags, error codes | `brickkit <command> --help`; the skills in `.claude/skills/brickkit-*` |

## Repository layout

```
brickkit.yaml           the components and their exact versions (the lock file)
deploy.yaml             how they run: target, shells, exposed ports
config/                 each component's values; vars.yaml for values shared by several
components/<scope>/<name>/   one Git submodule per component
shell/<scope>/<name>/   the shells: several components in one process, project code
tools/                  be-sdk-go, be-sdk-python, be-sdk-ts, be-ops, be-acceptance
registry/               ports, schemas, permission keys, data scopes
infra/                  the base resources make up starts, and the project's scripts
docs/                   conventions, decisions, seed data
```
