[English](AGENTS.md) · [中文](AGENTS.zh.md)

# be-assembly-standard

The AI guide to this project: what it is, the rules every component here follows, where to look. The component table at the end is maintained by brickkit.

> **Document language is not conversation language.** The formal documents are written in English so that an AI reads them efficiently. The maintainer of this project communicates only in Chinese, so every reply to them is in Chinese, whatever language the file, the code or the last tool output is in. Decide the reply language before writing the first word; checking it after writing has proved unreliable.

## Overview

- **What this is.** BrickEnterprise: an arsenal of ERP/CRM components plus the standard assembly template that puts them together with brickKit. It is also where brickKit's features are proved on real machines; a platform bug found here is reproduced and reported to brickKit, never worked around inside a component.
- **Nine domains**, and a component ID is `<domain>/<name>` (repository `<domain>-<name>`): `infra`, `integration`, `mdm` (master data), `crm`, `erp`, `hrm`, `prj`, `ana`, `frontend`.
- **Three hubs** hold the rest together. `mdm/*` is read by everyone and calls no one. `erp/inventory` is the only writer of physical stock movements. `erp/finance` is mostly commanded and listens to events. CRM and ERP have no synchronous edge between them, only events; inventory and finance have no edge at all, the same upstream (such as `erp/sales`) triggers both side by side.
- **Where things live.**
  - `components/<scope>/<name>/`: one Git submodule per component; `.gitmodules` records the exact commit of each.
  - `shell/<scope>/<name>/`: the shells (`be/go-core`, `be/go-infra`, `be/go-backoffice`, `be/py-render`); each is its own repository, checked out as a Git submodule like a component, so that other assembly projects reuse it ([0022](docs/en/02-decisions/01-architecture/0022-one-repository-per-shell.md)).
  - `tools/`: `be-sdk-go`, `be-sdk-python`, `be-sdk-ts` (the runtime every component builds on), `be-ops` (assembly-time generation: database setup script, permission and data-scope registries), `be-acceptance` (the gates behind `make gates`).
  - `registry/` (ports, schemas, permission keys, data scopes), `config/` (component values, `vars.yaml` for shared ones), `infra/` (the base resources `make up` starts), `docs/en/` (conventions, decisions, seed data; [index](docs/en/README.md)), mirrored file for file in Chinese by `docs/zh/`.
- **Two principles that never bend.**
  1. **Every component is a complete brickKit component and runs on its own.** Every call to another component goes over real gRPC or HTTP, every port in `extraPorts` really listens, and `brickkit up --focus <id>` starts it with nothing but what it depends on. "They end up in the same shell, so call the function directly" breaks this, and the component can never be deployed on its own again.
  2. **Merging happens only at deployment.** A shell turns N processes into one and does nothing else.

## Conventions

One line each; the file linked is the rule in full. A request that breaks one is put to the person, quoting the file.

- **Configuration**: keys are upper-snake environment variable names; shared connection keys are `PG_*`, `NATS_URL`, `S3_URL`, `OTEL_BASE_URL`, `AUTHZ_BUNDLE_URL`, `IAM_JWKS_URL`; nothing ends in `_ENDPOINT` ([04-configuration.md](docs/en/01-conventions/04-configuration.md)).
- **Where values live**: a value shared by several components is written once in `config/vars.yaml` and referenced as `$var:NAME`; a component's own values go in `config/<scope>-<name>.yaml`; secrets are only ever `${NAME}` ([04-configuration.md](docs/en/01-conventions/04-configuration.md#where-values-live)).
- **Workflow**: seven steps, contracts before business-rule tests before code, documents before code ([01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md)); answer the questions in [Before writing code](docs/en/01-conventions/01-development-workflow.md#before-writing-code) every time.
- **Backend**: one locked stack per language, one module entry, everything through `rt`, merge-safe by construction ([02-backend.md](docs/en/01-conventions/02-backend.md)).
- **Frontend**: Vue 3, AntDV + vxe-table on PC, wot-design-uni on mobile, tokens as CSS variables, third-party UI only inside the ui-kits ([03-frontend.md](docs/en/01-conventions/03-frontend.md)).
- **Testing**: layers L1–L4 and FE-1–FE-4; never change a test to make it pass ([06-testing.md](docs/en/01-conventions/06-testing.md)).
- **Data**: seed data for people, test data for tests, two physical databases (`brickkit_db`, `brickkit_test_db`); a dependency that lacks a capability is fixed at the source ([05-data.md](docs/en/01-conventions/05-data.md)).
- **Registries**: ports, schemas, roles and permission keys are copied from `registry/`, never invented; `ports.tsv`, `schemas.tsv` and `permissions.tsv` are append-only: a row is never edited, removed or recycled ([07-registries.md](docs/en/01-conventions/07-registries.md#append-only)).
- **Submodule map**: `.gitmodules` and the submodule pointers say which repository and which exact commit each component and shell is built from; they change only through `git submodule` commands, and a pointer is committed together with the `brickkit upgrade` that needs it ([01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#releasing)).
- **Two manifests per component**: `component.yaml` holds only what brickKit reads; this project's own keys (`permissions`, `data_scopes`, `menus`, and other project metadata such as `domain` or `tier`) go in the sibling `assembly.yaml`, read by be-ops ([02-backend.md](docs/en/01-conventions/02-backend.md#repository-layout)). Which shell hosts a component is chosen in the deploy file ([0022](docs/en/02-decisions/01-architecture/0022-one-repository-per-shell.md)).
- **Versions**: every change gets a bump, versions are exact, components are on `2.x` and shells on `1.x`; a Go component carries two tags on one commit (`2.0.0` for brickKit, `v2.0.0` for Go) and its module path ends in `/v2`; a shell is released from its own repository with only the bare tag (`1.0.0`); propagate with `make bump-version` ([01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#versions)).
- **Commits and releases**: Chinese messages written to a file and committed with `git commit -F`, annotated tags, release in the order `bump-version` prints ([01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#releasing)).
- **Business logic**: design it yourself first, read a reference only where stuck, never copy ([10-reference-implementations.md](docs/en/01-conventions/10-reference-implementations.md)).
- **AI-sized code**: patterns only where they help an AI read the code; limits on function, file and session size ([09-ai-development.md](docs/en/01-conventions/09-ai-development.md)).
- **Documents**: English canonical, same `##` sections in both languages; project documents are two mirrored trees `docs/en/` and `docs/zh/` (`make docs-mirror`), root and component documents keep brickKit's `.zh.md` suffix; formal documents never link into `dev/` or `archive/` (`make docs-boundary`) ([08-documentation.md](docs/en/01-conventions/08-documentation.md)).
- **Decisions**: [docs/en/02-decisions/](docs/en/02-decisions/README.md) says why the project is shaped this way and what not to propose; a decision wins over a convention.
- **Containers are off by default**: base resources from `make up` may stay up; component containers go down with `brickkit down` after verification ([01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#running-it-for-real)).

## Where to look

| What you are doing (words you'd search for) | Read first |
|---|---|
| a new requirement, a feature, "where should this go", "is this a good idea", a change across components | the `brickkit-plan-change` skill ([SKILL.md](.claude/skills/brickkit-plan-change/SKILL.md)), then [docs/en/02-decisions/](docs/en/02-decisions/README.md); a planned component may already have its ID, ports and schema reserved in `registry/` |
| starting work on a component; what order to do things in; how much to do in one session | [01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#the-seven-step-loop), [09-ai-development.md](docs/en/01-conventions/09-ai-development.md#how-much-in-one-session) |
| writing a new component; editing `component.yaml`; the repository layout | the `brickkit-component` skill ([SKILL.md](.claude/skills/brickkit-component/SKILL.md)), [02-backend.md](docs/en/01-conventions/02-backend.md#repository-layout) |
| which port, schema, database role or permission key to use | [07-registries.md](docs/en/01-conventions/07-registries.md) |
| naming a config key; reading a config value; connecting to PostgreSQL, NATS or object storage; a database password | [04-configuration.md](docs/en/01-conventions/04-configuration.md), [04-configuration.md](docs/en/01-conventions/04-configuration.md#database-roles), [02-backend.md](docs/en/01-conventions/02-backend.md#the-runtime-is-the-only-way-in) |
| which framework or library; writing `main`; the module entry | [02-backend.md](docs/en/01-conventions/02-backend.md#stack), [02-backend.md](docs/en/01-conventions/02-backend.md#module-entry), [0003](docs/en/02-decisions/01-architecture/0003-locked-stack-per-language.md) |
| adding an endpoint; who can call it; a permission key | [02-backend.md](docs/en/01-conventions/02-backend.md#permissions) |
| making a table show only some rows to some people ("sales sees only their own orders", "a warehouse keeper sees one warehouse") | [02-backend.md](docs/en/01-conventions/02-backend.md#data-scopes), [0008](docs/en/02-decisions/02-permissions/0008-data-scopes-ship-with-the-version.md), [0009](docs/en/02-decisions/02-permissions/0009-no-row-level-security.md) |
| calling another component; showing data another component owns | [02-backend.md](docs/en/01-conventions/02-backend.md#calling-other-components) |
| adding a table, a migration or a partition | [02-backend.md](docs/en/01-conventions/02-backend.md#database) |
| publishing or consuming an event; a write across components; a timeout or a compensation | [02-backend.md](docs/en/01-conventions/02-backend.md#events-and-cross-component-writes) |
| changing a contract: renaming a field, removing an rpc or an event | [02-backend.md](docs/en/01-conventions/02-backend.md#contracts), [0011](docs/en/02-decisions/03-contracts-and-data/0011-contracts-are-additive-only.md) |
| amounts, prices, money fields; paging a list | [0010](docs/en/02-decisions/03-contracts-and-data/0010-money-as-strings-lists-by-cursor.md) |
| adding a cache; Redis; making the permission check faster | [0004](docs/en/02-decisions/02-permissions/0004-no-redis.md), [0005](docs/en/02-decisions/02-permissions/0005-local-permission-bundle.md) |
| a shell exits at start: a member "not registered" / not compiled into this shell; a shell member mismatch | the shell-registry row of [Pitfalls](#pitfalls) below; for errors `brickkit` itself prints, the `brickkit-troubleshoot` skill |
| putting several components in one process; a shell; which members a shell hosts | [0022](docs/en/02-decisions/01-architecture/0022-one-repository-per-shell.md), the `brickkit-component` skill (shells), [01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#running-it-for-real) (teardown check) |
| which test to write, in which layer; a test is red and I'm stuck | [06-testing.md](docs/en/01-conventions/06-testing.md), [When stuck](docs/en/01-conventions/06-testing.md#when-stuck) |
| running tests against real dependencies | [06-testing.md](docs/en/01-conventions/06-testing.md#cross-component-tests), [06-testing.md](docs/en/01-conventions/06-testing.md#running-tests) |
| demo data; test accounts; how to log in | [docs/en/03-seed-data.md](docs/en/03-seed-data.md) |
| designing seed or test data; a dependency doesn't have the data I need | [05-data.md](docs/en/01-conventions/05-data.md) |
| a frontend page, the component library, theme, menus, buttons only some users see | [03-frontend.md](docs/en/01-conventions/03-frontend.md) |
| how should this business logic work; which open-source ERP to read | [10-reference-implementations.md](docs/en/01-conventions/10-reference-implementations.md) |
| several reasonable ways to do one feature; "let the customer choose" | [10-reference-implementations.md](docs/en/01-conventions/10-reference-implementations.md#slot-family-signal), [0012](docs/en/02-decisions/01-architecture/0012-variants-become-slot-families.md) |
| whether to use a design pattern; a file or function getting long | [09-ai-development.md](docs/en/01-conventions/09-ai-development.md#when-to-use-a-design-pattern) |
| writing, splitting or translating a document; a component's documents | [08-documentation.md](docs/en/01-conventions/08-documentation.md) |
| bumping a version; releasing; tagging; "ship it" | the `version-bump-ship` skill ([SKILL.md](.claude/skills/version-bump-ship/SKILL.md)), [01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#versions) |
| how to install or deploy; who creates the database; secrets; Kubernetes; another environment | the `brickkit-deploy` skill ([SKILL.md](.claude/skills/brickkit-deploy/SKILL.md)); each component's `components/<scope>/<name>/BRICKKIT.md`, section "Before you deploy"; [07-registries.md](docs/en/01-conventions/07-registries.md#schemas-and-roles) (`make db-init`) |
| debugging one component in an IDE; running only one component | [01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#running-it-for-real), the `brickkit-deploy` skill |
| adding, removing or upgrading a component in the project; why a component isn't starting | the `brickkit-assemble` skill ([SKILL.md](.claude/skills/brickkit-assemble/SKILL.md)) |
| a `brickkit` command printed an error or an `error_code` | the `brickkit-troubleshoot` skill ([SKILL.md](.claude/skills/brickkit-troubleshoot/SKILL.md)); flags: `brickkit <command> --help` |
| "why not React / Java / RLS / a Deny rule / a config center…" | [docs/en/02-decisions/](docs/en/02-decisions/README.md) |
| what one component does; changing one component | the component table below, then `components/<scope>/<name>/BRICKKIT.md` (what it owns) and its `AGENTS.md` (how to change it) |

Not here? The component table below, then the component's `AGENTS.md`.

## Pitfalls

The mistakes that hold for every component. Most of them look correct, pass the tests, and show no symptom until much later.

| Never | Symptom | Why |
|---|---|---|
| `SET ROLE` / `SET search_path` without `LOCAL` | The next borrower of the pooled connection runs its queries in your schema: no error, no crash, another component's data read and written | Without `LOCAL` the setting outlives the transaction. Use `besdk.WithTx` ([02-backend.md](docs/en/01-conventions/02-backend.md#database)) |
| Read `os.Getenv` / `os.environ` in module code | Standalone everything is green; merged into a shell, members overwrite each other's `PG_SCHEMA` and every other key, and a module silently uses another's schema | One process has one environment. Configuration comes only from `rt.Config` ([02-backend.md](docs/en/01-conventions/02-backend.md#merge-safety)) |
| Initialise anything process-wide in a module: `otel.SetTracerProvider`, `logging.basicConfig`, signal handlers, the default Prometheus registry, `gin.SetMode` | Merged: the last initialiser wins, every trace lands under one service name, one module's debug mode leaks stack traces for all; the default registry panics on the second module | Use `rt.Logger`, `rt.Tracer`, `rt.Meter`, `rt.Registry` ([02-backend.md](docs/en/01-conventions/02-backend.md#merge-safety)) |
| `log.Fatal` / `os.Exit` / `sys.exit`, or `gin.New()` / `sql.Open()` / `Listen` in a module | One module's recoverable error takes the whole shell down; `gin.New()` silently loses the SDK's middleware: request IDs, tracing, RED metrics, the access log, panic recovery and error mapping | Return an error; `besdk.NewGinEngine(rt)`, `rt.DB`; the caller listens ([02-backend.md](docs/en/01-conventions/02-backend.md#merge-safety)) |
| Import another component's code, share a models package, or copy its generated contract code | Nothing breaks until the day a component must run alone and can't; copied generated code panics at start once caller and callee share a shell | Only `be-sdk-*` and the imported `gen/<domain>/<name>` package cross a boundary ([0001](docs/en/02-decisions/01-architecture/0001-no-imports-between-components.md)) |
| Dial an injected `*_ENDPOINT` value as it is | It always starts with `http://`, gRPC ports included; the dial fails with an error about name resolution. With port name `""` a gRPC call reaches the HTTP port: TCP connects, then a protocol error | Use `rt.Config.Endpoint(dep, "grpc")` ([02-backend.md](docs/en/01-conventions/02-backend.md#the-runtime-is-the-only-way-in)) |
| Treat an absent optional dependency as an empty value, or index the environment for it | The variable doesn't exist at all; indexing crashes at start | `Endpoint` returns `ok == false`; the module degrades ([02-backend.md](docs/en/01-conventions/02-backend.md#the-runtime-is-the-only-way-in)) |
| Name a config key `*_ENDPOINT`, `COMPONENT_ID`, `COMPONENT_VERSION`, `PORT` or `BRICKKIT_SERVED_MEMBERS*` | The platform's value wins with only a warning; `up` is green and the component never gets your value | Those names belong to the platform ([04-configuration.md](docs/en/01-conventions/04-configuration.md#key-names)) |
| Check the database, NATS, authz or another component in `/healthz` | One downstream hiccup marks every upstream unhealthy and restarts it; in a shell every member restarts at once | `/healthz` reports only that this process is alive ([02-backend.md](docs/en/01-conventions/02-backend.md#health-check-and-image)) |
| Base the image on `scratch` or distroless | The component logs "ready" and the platform reports it unhealthy forever | The health check runs through `/bin/sh` and `wget` ([02-backend.md](docs/en/01-conventions/02-backend.md#health-check-and-image)) |
| Register a business route with bare `r.GET` / `@app.get`, or an unwrapped resolver | The endpoint has no permission check at all, with zero symptom | The permission key is part of the route registration; `make gates` scans for it ([02-backend.md](docs/en/01-conventions/02-backend.md#permissions)) |
| Use `besdk.SystemClient` on a path that serves a user request | The response silently contains more rows than the user may see | It carries the component's identity and bypasses data scopes; only `Start()` and event handlers ([02-backend.md](docs/en/01-conventions/02-backend.md#calling-other-components)) |
| Omit `data_scopes` from `assembly.yaml` | be-ops rejects the component | Deliberate: a security setting may not default to off. No scoping is written `data_scopes: none` ([0008](docs/en/02-decisions/02-permissions/0008-data-scopes-ship-with-the-version.md)) |
| Combine `owner` OR `org` with one operand left at "match all" | The whole condition matches everything; every user sees every row | Both operands must come from the caller's real scope ([02-backend.md](docs/en/01-conventions/02-backend.md#data-scopes)) |
| Rename or reuse a released permission key | Every role granted it silently loses it; after an upgrade users suddenly can't use a button | Keys are persistent identifiers; retire one with the `deprecated` column ([07-registries.md](docs/en/01-conventions/07-registries.md#append-only)) |
| Check only `features` in the frontend, not `permissions` | The menu item is visible and opens a full-page 403 | `features` says what is installed, `permissions` what this user may do ([03-frontend.md](docs/en/01-conventions/03-frontend.md#features-permissions-and-menus)) |
| Write this project's keys (`permissions`, `data_scopes`, `menus`, and other project metadata such as `domain` or `tier`) into `component.yaml` | `brickkit lint` and `brickkit add` reject the whole manifest: `MANIFEST_INVALID`, `unknown field`; the component can't be added or started | `component.yaml` has no extension fields; those keys belong in `assembly.yaml` ([02-backend.md](docs/en/01-conventions/02-backend.md#repository-layout)) |
| Move a registered port, rename a schema, or allocate a `1xxxx` port | Every dependent and every shell hosting the component breaks; a schema rename is a data migration; a `1xxxx` port collides with brickKit's host mapping for `mode: debug` / `local` | [07-registries.md](docs/en/01-conventions/07-registries.md#ports) |
| Claim a queue row or an idempotency key with a plain `SELECT` and then a write | Two replicas publish every outbox row twice; two concurrent requests both execute | Claim atomically: `FOR UPDATE SKIP LOCKED`, `INSERT … ON CONFLICT DO NOTHING` ([02-backend.md](docs/en/01-conventions/02-backend.md#database)) |
| Pass money as a float, or page a `List` with `offset` | Amounts lose precision between languages; deep pages get slow and skip rows | Decimal strings and cursors ([0010](docs/en/02-decisions/03-contracts-and-data/0010-money-as-strings-lists-by-cursor.md)) |
| Change a test to make it pass: comment it out, `t.Skip`, loosen the assertion | Everything is green and guards nothing | Fix the implementation; a wrong test is changed in its own commit, saying why ([06-testing.md](docs/en/01-conventions/06-testing.md#red-green-and-the-iron-rule)) |
| Change a forked component's `metadata.id` | With a new ID every dependent's `<ID>_ENDPOINT` variable disappears | A fork keeps its `metadata.id` but versions normally: every change bumps `metadata.version`, and dependents move their pins with `brickkit upgrade` / `make bump-version`; only its repository and directory names may differ ([01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#releasing)) |
| Let the members a shell's `main` registers (its registry) differ from `shell.members` in its `component.yaml`, or a Go shell's `go.mod` from either | A member to host that isn't registered: the shell exits at start and every member in it is down. A member version `go.mod` doesn't require: the image runs other code than the project believes, with no error | The JSON says what to host, the binary decides what exists; `make bump-version` rewrites `shell.members` and `go.mod` together ([0022](docs/en/02-decisions/01-architecture/0022-one-repository-per-shell.md)) |
| Expect `deploy.local.yaml` to merge with `deploy.yaml` | With local mode on, edits to `deploy.yaml` have no effect; the team's later changes never reach your copy, and `up` refuses once the component set differs | It replaces `deploy.yaml` wholesale. `brickkit up --focus` turns local mode on and `--all` leaves it on. `brickkit local status` shows the switch; `brickkit local off` before editing `deploy.yaml`, or `brickkit local refresh` after, which lists your old changes to re-apply ([01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#running-it-for-real)) |
| Address authz or iam by a shell's service name, or leave `AUTHZ_BUNDLE_URL` / `IAM_JWKS_URL` at an old version after they release | Every protected route in every component answers `503` or `403` while `/healthz` stays green | Use the members' own service names in `config/vars.yaml` and change them when authz or iam releases; `make gates` (`service-hostname-scan`) fails while they disagree with `brickkit.yaml` ([04-configuration.md](docs/en/01-conventions/04-configuration.md#dependency-addresses)) |
| Release a Go component `2.x` with only the brickKit tag, or with a module path without `/v2` | The shell's Go build can't fetch the member: `unknown revision v2.0.0`, or "module path must match major version" | Go needs the `v` tag and the major version in the path; brickKit's tag has no `v` ([01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#versions)) |
| Change code without bumping `metadata.version`, or change a released version in place | `brickkit build` skips the existing image and the container keeps running the old code, all green | The image tag is the version ([01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#versions)) |
| `brickkit remove --force` a component with uncommitted or unpushed work | `--force` deletes the source directory and the work with it. Without it, `remove` stops before writing anything; a component registered as a Git submodule stops with `SUBMODULE_GUARD` | Commit and push the component, deregister the submodule (`git submodule deinit -f <path>`, `git rm <path>`), then run `brickkit remove` again ([01-development-workflow.md](docs/en/01-conventions/01-development-workflow.md#releasing)) |

<!-- brickkit:managed:begin lang=en -->
<!-- maintained by brickkit (init, add, remove, upgrade, skills update): edits between these markers are overwritten -->

## BrickKit

This project is assembled with [BrickKit](https://github.com/brickKit/brickKit): each component describes itself in its own `component.yaml`; the `brickkit` CLI resolves the graph, generates the deployment files and exits. There is no registry, config server or gateway to look for.

- `brickkit.yaml` lists the components at exact versions (it is the lock file); `deploy.yaml` says how they run (`deploy.local.yaml` replaces it on your machine while local mode is on); `config/<scope>-<name>.yaml` holds each component's environment variables, `config/vars.yaml` the shared values.
- `brickkit add` / `remove` / `upgrade` keep the three layers in step: never hand-edit one and forget another.
- Config keys are the environment variable names the component's `configSchema` declares; secrets are `${VAR}` or `file://.secrets/…`, never plaintext.
- A health check checks only its own process. To work on one component, run `brickkit up` in its directory; `brickkit up --all` runs everything again.
- Task skills are in `.claude/skills/brickkit-*`; for flags ask `brickkit <command> --help`.

## Components

A component's documentation is `BRICKKIT.md` (translations `BRICKKIT.<lang>.md`) in its source directory when a local source holds this version, otherwise in `.brickkit/manifests/<id>/<version>/`; its contracts are in `.brickkit/artifacts/<service name>/` (the ID and the version joined by `-`, with every `/` and `.` as `-`: `erp/backend` 1.0.0 → `erp-backend-1-0-0`). To change a component, read its own `AGENTS.md`.

| Component | Version | What it does | Docs | Home |
|---|---|---|---|---|
<!-- brickkit:managed:end -->
