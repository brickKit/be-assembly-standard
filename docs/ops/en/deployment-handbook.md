# BrickEnterprise Deployment Handbook

*[中文](../zh/deployment-handbook.md)*

> **For deployment staff. This is the only document you need.** No need to read the design book, no need to read any component documentation — wherever you need to look elsewhere, this handbook will name the section explicitly.
>
> If something this handbook doesn't cover, or following it doesn't work: **that's a bug in this handbook, not in you**. Write it down and send it back — we'll fix it (see `docs/README.md`'s "every document can be changed").

## What this handbook currently covers

| Section | Status |
|---|---|
| 1. Host preparation | ✅ Ready |
| 2. Base resources (10 out-of-band containers) | ✅ Ready (`make up` implemented) |
| 3. Database: who creates what | ✅ Ready |
| 4. Business components: what to prepare before deploying | ✅ Ready (all 14 components out-docked, real-machine verified) |
| 5. Shell-merged deployment / K8s | ✅ Ready (all 12 topology×environment base combinations real-machine verified, shell+K8s is now a native capability — full selection guidance in [`deployment-selection-guide.md`](deployment-selection-guide.md), this section only gives the key conclusions) |
| 6. Upgrades and rollback | 🔜 Once there's a first real customer |

---

## 1. Host preparation

### 1.1 Software

| Requirement | How to confirm |
|---|---|
| Docker Engine ≥ 24 | `docker --version` |
| Docker Compose v2 (**not the old standalone `docker-compose`**) | `docker compose version` |
| Current user can use docker (in the `docker` group, or via sudo) | `docker info` doesn't error with a permission issue |

### 1.2 ⚠️ Host ports must be free — this is the most common first pitfall

**If any of the ports below is already in use, the corresponding container simply won't come up.** And the symptom usually points somewhere else: Compose reports `port is already allocated`, or worse — the container comes up but is actually talking to someone else's service.

```bash
# One command to check them all (any output = a conflict)
for p in 5432 4222 8222 80 443 28080 8000 9000 3000 3100 3200 4317 4318 13133 29090; do
  ss -ltn 2>/dev/null | grep -q ":$p " && echo "in use: $p"
done
```

| Port | Used by | Required? |
|---|---|---|
| 5432 | PostgreSQL | ✅ |
| 4222, 8222 | NATS (client / monitoring) | ✅ |
| 80, 443, 28080 | Traefik (HTTP / HTTPS / Dashboard) | ✅ |
| 8000 | Casdoor | ✅ |
| 9000 | RustFS object storage | ✅ |
| 3000, 3100, 3200, 4317, 4318, 13133, 29090 | Observability stack | ❌ Only if you enable observability |
| 9001 / 28081 / 29092 / 5672,15672 | MinIO / Keycloak / Kafka / RabbitMQ swap-ins | ❌ Only if you swap an implementation |

**If there's a conflict**: first find out who's holding it (`docker ps` for another project's containers; `ss -ltnp` for the process), stop it, or ask us to change the port.
⚠️ **Do not change the ports in the compose files yourself** — the port registry (`registry/ports.tsv`) is globally unique and **append-only**; changing it on your own will collide later when installing components, and the error at that point will point at the component, not the port.

### 1.3 Disk and network

- All data lands in named Docker volumes (`pg_data` / `nats_data` / `rustfs_data` …) — **do not run `docker volume prune`**
- A local deployment **doesn't need outbound internet access** at runtime, but **the first install needs to pull images** — you'll need one window of connectivity (or a pre-pulled `docker load` offline bundle)

---

## 2. Base resources

### 2.1 Three steps to bring them up

```bash
# ① Create the shared network
make net

# ② Prepare the password file
cp .env.example .env
#    ⚠️ Fill in real values line by line — don't leave any change_me in place.
#    This file is not committed to Git, but it stays on the customer's machine —
#    it IS this system's password book.

# ③ One command to bring up the default 5 containers
#    (a full preflight check runs first; only starts if everything passes;
#    anything already healthy is skipped)
make up
```

`make up` runs in three phases internally: preflight → start → re-check — the table you see at the end, once §2.1 has fully run, is the same one `make check` prints. **If the preflight finds even one default resource "wrong" (image/port/health mismatch, or a port already taken), it holds back the whole thing and starts nothing** — there's no "half-started" state.

After `make up`, you can check status independently at any time:

```bash
make check     # checks only the default 5
make status    # the raw docker compose ps view
make down      # stop everything (data is not deleted)
```

⚠️ **`make up` will not fix a "wrong" resource for you, and it will not stop/remove any container for you.** The error message will name who and what's wrong; once you've fixed it, just rerun `make up` — it's idempotent against containers that are already healthy (won't restart or rebuild them).

⚠️ **You don't need to worry about `--env-file .env` yourself** — the `make` targets already wire it in. You only need to remember it if you're bypassing the `Makefile` and hand-writing your own `docker compose` commands; the symptom of forgetting it is:

```
required variable POSTGRES_PASSWORD is missing a value
```

This looks like `.env` was written wrong, but it's actually Compose looking in `infra/.env` instead (Compose treats "the directory containing the first `-f` file" as the project directory). **Don't try to "fix" this with `--project-directory .` either** — relative mounts like `./traefik/traefik.yml` and `./casdoor/conf` would then also resolve against the repo root, and Docker silently creates an empty directory for a mount source that doesn't exist there — so Traefik comes up `healthy` with an empty config and just routes nothing.

### 2.2 The default 5 containers

| Container | What it is | What healthy looks like |
|---|---|---|
| `be-postgres` | PostgreSQL 16, the one and only database for the whole system | `docker inspect -f '{{.State.Health.Status}}' be-postgres` → `healthy` |
| `be-nats` | Event bus (JetStream enabled) | Same as above |
| `be-traefik` | API gateway | Same as above; dashboard at <http://localhost:28080> |
| `be-casdoor` | Login and identity (**first boot takes roughly 30–60 seconds** — it creates 44 tables) | `curl -fsS http://localhost:8000/api/health` → 200 |
| `be-rustfs` | Object storage | Same as above |

### 2.3 The observability stack (optional, all-or-nothing)

```bash
make obs-up      # turn on
make obs-down    # turn off
```

**Everything still works without it** — components silently drop telemetry when they can't reach an OTel endpoint; it never blocks business logic (design book §7.5). Feel free to skip it on resource-constrained customer machines.

⚠️ **`be-otel` / `be-loki` / `be-tempo` have no Docker-level health check** (their images have no shell, so an in-container self-check is physically not possible). `make obs-up` returns as soon as they enter a running state — **that does not mean they can already receive data**. To confirm, check from the host side:

```bash
curl -fsS http://localhost:13133/            # otel-collector
curl -fsS http://localhost:3100/ready        # loki (see ⚠️ below)
curl -fsS http://localhost:3200/ready        # tempo
```

⚠️ **`be-loki` returns 503 from `/ready` for roughly the first 15 seconds after starting** (`"Ingester not ready: waiting for 15s after being ready"`) — **this is Loki's own normal behavior, not a failure**; check again in a moment and it'll be `ready`.

### 2.4 Swap-ins (replacing a default implementation)

```bash
make minio-up      # object storage → MinIO (auto-checks whether rustfs is still running and blocks if so)
make keycloak-up   # identity → Keycloak (auto-checks casdoor)
make kafka-up      # event bus → Kafka
make rabbitmq-up   # event bus → RabbitMQ
make nginx-up      # gateway → Nginx
# the matching make <name>-down turns each off
```

| Swap | Command | ⚠️ |
|---|---|---|
| Object storage → MinIO | `make minio-up` | Same "storage" mutual-exclusion group as `rustfs` — the two cannot run at once |
| Identity → Keycloak | `make keycloak-up` | Same "iam" mutual-exclusion group as `casdoor` |
| Event bus → Kafka / RabbitMQ | `make kafka-up` / `make rabbitmq-up` | Same "mq" mutual-exclusion group as `nats`. ⚠️ **This is not as simple as "swap a container"** — it also requires changing every component's manifest. **Don't do this yourself — ask the development team** |
| Gateway → Nginx | `make nginx-up` | Same "gateway" mutual-exclusion group as `traefik` |

⚠️ **You don't need to manually stop the old one first.** `make <swap-in>-up` automatically checks whether another member of the same mutual-exclusion group is running, and errors out directly if so (it won't stop it for you) — the error message names who's running and which command to use to turn it off. See §6's troubleshooting table.

---

## 3. ⭐ Database: who creates what, what's automatic vs. what you do

This is the most important section of this handbook. **It breaks down into five layers, and only layers 3 and 4 need your hands — and only once.**

| # | What gets created | Who creates it | When | Do you do it? |
|---|---|---|---|---|
| 1 | The `brickkit_db` database | `infra/postgres/initdb/00-bootstrap.sql` | `be-postgres`'s **first** boot | ❌ Automatic |
| 2 | The `casdoor` / `keycloak` schemas | Same as above | Same as above | ❌ Automatic |
| 3 | **Each of the 62 components' own schema + `_archive` + PG role + grants** | The provisioning script `be-ops` generates | **Before installing any business component** | ✅ **You run this once** |
| 4 | **The 5 shell login roles** | Same as above | Same as above | ✅ Same as above |
| 5 | Each component's own business tables | That component's own migration | Every time the component starts | ❌ Automatic |

The concrete command for layers 3 and 4:

```bash
make db-init   # idempotent, safe to rerun; creates brickkit_db (the demo/production database),
               # not the brickkit_test_db that make test-db-init creates
```

What this does internally: runs `be-ops db-script` to generate a database-creation SQL script (schema + `_archive` + PG role + grants for all 62 components, plus the 5 shell login roles — every statement wrapped in `IF NOT EXISTS`/a `DO` block, so it's safe to rerun), then executes it using the 5 `SHELL_*_PASSWORD` variables from `.env` to set the shell login roles' passwords. **You must run this once before installing any business component**, and only after `.env` already has real values filled in (step ② of §2.1) — if the five `SHELL_*_PASSWORD` variables are still the `change_me_...` placeholders copied from `.env.example`, the roles get created with those literal placeholder strings as their passwords; changing `.env` afterward won't automatically propagate — you'd have to `ALTER ROLE` by hand.

### 3.1 Why this can't be fully automated in one step

Because **the platform (brickKit) itself never creates databases**: creating a database requires `CREATEDB` privilege, and giving every component's runtime account that privilege would mean granting elevated privileges platform-wide. So `brickkit up` only **prints** the statements that need to be created ahead of time; the actual work is done by our own tooling (design book §2.7.2).

Layers 1 and 2 can be automatic because they go through PostgreSQL's own official `docker-entrypoint-initdb.d` mechanism — **but that mechanism only runs once, and only when the data volume is empty**.

### 3.2 When the data volume isn't empty (e.g. a reinstall, or a different compose setup)

Layers 1 and 2 won't rerun. Apply them manually:

```bash
docker exec -i be-postgres psql -U postgres < infra/postgres/initdb/00-bootstrap.sql
```

The `CREATE DATABASE brickkit_db` line will report "already exists" — **that's fine, ignore it**; the two `CREATE SCHEMA IF NOT EXISTS` lines after it are idempotent.

### 3.3 Confirming this layer is in good shape

```bash
docker exec be-postgres psql -U postgres -lqt | cut -d\| -f1 | grep -w brickkit_db
docker exec be-postgres psql -U postgres -d brickkit_db -Atc \
  "select nspname from pg_namespace where nspname in ('casdoor','keycloak') order by 1"
```

Expected: the first command prints `brickkit_db`; the second prints two lines, `casdoor` / `keycloak`.

---

## 4. ⭐ Business components: what you must prepare before deploying

All 14 components are fully out-docked and real-machine verified. Before running `brickkit up`, **a handful of config items need real values supplied by you (the deployer) — the platform and the components will not generate these for you.** Missing one doesn't always mean "won't start": some will refuse to start outright (`brickkit up --dry-run` errors right away), while others will come up `healthy` while one specific feature silently breaks — without this checklist, it's genuinely hard to trace the symptom back to the cause.

### 4.1 The flow for bringing up business components

Once the 5 database layers in §3 are ready and `.env` is filled with real values per §4.2 below:

```bash
make db-init           # run once first (§3), idempotent
brickkit up --dry-run  # see what would start and in what order, without actually starting anything
brickkit up             # actually start everything
```

How a value in `.env` reaches a component: for every entry in a component's `config:` block in `brickkit.yaml` written as `"${SOME_VAR}"`, `brickkit up` substitutes it verbatim from `.env` when generating the compose file; anything not in `${...}` form (e.g. `defaultWarehouseId: "1"`) is a hardcoded business value and doesn't go through `.env` at all.

### 4.2 What genuinely needs real values — grouped by component

⚠️ **The list below only includes items where missing a value causes a startup failure, or causes a specific feature to silently break.** `component.yaml` has other fields with no `default:` that are nonetheless fine to leave unset (e.g. `iamJwksUrl`/`authzBundleUrl` — missing these just downgrades the corresponding authorization check to fail-closed 403/503, it doesn't block the component from starting; this repository has already wired both of these into `brickkit.yaml`, so you don't need to touch them). This distinction is itself one of this repository's own named pitfalls — "no `default:` in `configSchema`" does not mean "actually required"; the only reliable test is whether the code calls `MustString`/`Int` (which panics if unset).

| Component | Config item | `.env` variable | What it is, where it comes from |
|---|---|---|---|
| `erp/sales` | `defaultWarehouseId` | (not via `.env` — hardcoded `"1"` in `brickkit.yaml`) | A real warehouse ID that exists in `erp-inventory`. This repo's seed migration already seeds `id=1` (`WH-EAST`) — **installing this standard assembly as-is needs no change here**; if you've customized `erp-inventory`'s migration and this warehouse ID isn't `1`, update this to match |
| `integration/im-dingtalk` | `dingtalkAppKey`<br>`dingtalkAppSecret`<br>`dingtalkAgentId` | `DINGTALK_APP_KEY`<br>`DINGTALK_APP_SECRET`<br>`DINGTALK_AGENT_ID` | Real DingTalk "internal enterprise app" credentials (see the registration steps in §4.3). Leaving these as placeholders still lets the component start normally — only the step that actually calls the DingTalk API (work notifications) will fail |
| `infra/iam-casdoor` | `casdoorBaseUrl` | (not via `.env` — hardcoded in `brickkit.yaml`) | The address of the out-of-band Casdoor container. The standard assembly fixes this at `http://host.docker.internal:8000` (Casdoor is started by `docker-compose.infra.yml`, mapped to host port 8000) — **as long as you haven't changed Casdoor's host port mapping, leave this alone** |
| `infra/iam-casdoor` | `casdoorAdminPassword` | `CASDOOR_ADMIN_PASSWORD` | The **real password** for Casdoor's built-in `admin` account (see §4.4 — this item does not automatically change Casdoor's password for you; it's the reverse — it has to match Casdoor's real password) |
| `infra/iam-casdoor` | `webhookSharedSecret` | `WEBHOOK_SHARED_SECRET` | A shared secret you invent yourself (see §4.4) |
| `infra/iam-casdoor` | `appTokenSigningKeyPem` | `APP_TOKEN_SIGNING_KEY_PEM` | An RSA private key, PEM format, that you generate yourself (see §4.4 — this is the RSA key you asked about) |
| `frontend/standard` | `iamIssuerUrl` | (not via `.env` — hardcoded in `brickkit.yaml`) | Casdoor's **real public address as seen by the browser**. The repo currently ships a local-dev placeholder, `http://localhost:8000` — this must be swapped for the customer environment's real domain before going live (see §4.5) |
| `frontend/standard` | `casdoorClientId` | (not via `.env` — hardcoded in `brickkit.yaml`) | The OIDC public `client_id` of the `brickkit-app` Casdoor application (not a secret, but it must be looked up for real — don't guess it). **It's currently an empty string — this is a genuine gap you must fill in at deploy time**, and it can only be looked up after `infra-iam-casdoor` has started for the first time and bootstrapped `brickkit-app` into existence itself (see §4.5) |

### 4.3 How to get DingTalk credentials

Go to <https://open.dingtalk.com> and register with a phone number (a free personal-team account is enough — no real business license needed) → create an "internal enterprise application" → the app's detail page shows directly:

- **Client ID** (formerly AppKey) → goes in `DINGTALK_APP_KEY`
- **Client Secret** (formerly AppSecret) → goes in `DINGTALK_APP_SECRET`
- **AgentId** (numeric) → goes in `DINGTALK_AGENT_ID`

### 4.4 How to generate/verify `infra-iam-casdoor`'s three secrets

```bash
# ① webhookSharedSecret: any sufficiently random string — it's not tied to any
#    Casdoor app or org, purely a password this component and the Casdoor
#    webhook agree on between themselves.
openssl rand -base64 24

# ② appTokenSigningKeyPem: an RSA private key, PKCS8 PEM. ⚠️ You must generate
#    this key yourself — the component code deliberately does not auto-generate
#    one (in a merged deployment multiple modules share one process; auto-
#    generating would mean a new key on every restart, i.e. force-logging out
#    everyone on every restart).
#    Generate it once, use it long-term, guard it the way you'd guard a database
#    password:
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048
#    Paste the whole output straight into .env's APP_TOKEN_SIGNING_KEY_PEM —
#    wrap multi-line content in double quotes.
#    When you need to rotate it, see the `appTokenPreviousPublicKeyPem` item —
#    keep the old public key around for a while, and old tokens still verify
#    within their TTL, so it's not an instant logout for everyone
#    (see the full comment in component.yaml).

# ③ casdoorAdminPassword: this one is not "invent a password" — it's the
#    opposite, it has to match Casdoor's real admin password. The official
#    Casdoor image ships with the built-in account admin/123 (seed data from
#    first boot, not something this repo set). If you haven't logged into
#    Casdoor and changed that password, .env should say 123; if you HAVE
#    changed it via the Casdoor admin console (http://localhost:8000),
#    .env's CASDOOR_ADMIN_PASSWORD must be updated to match — the symptom of
#    a mismatch is "failed to log into the Casdoor admin API" in
#    infra-iam-casdoor's logs (it won't crash the component, but self-bootstrap
#    and gRPC BatchGetUsers both stay unavailable — see §6's troubleshooting
#    table).
```

### 4.5 Two exceptions with a real ordering dependency — no way around a manual step

**`frontend/standard`'s `casdoorClientId`** — this can only be looked up **after `infra-iam-casdoor` has genuinely started once**, because the `brickkit-app` Casdoor application is bootstrapped by `infra-iam-casdoor` itself inside `Start()`, not something that pre-exists. So a real deployment goes in two rounds:

1. Run `brickkit up` once (`frontend/standard`'s `casdoorClientId` is empty at this point, so the login page will be broken — every other component is unaffected).
2. Log into the Casdoor admin console (`http://<casdoorBaseUrl>`, credentials in §4.4) → Applications → find `brickkit-app` → copy the Client ID.
   - Or look it up via the API directly (you need a session cookie from logging in first — replace `<CASDOOR_ADMIN_PASSWORD>` with the real password):
     ```bash
     curl -c /tmp/casdoor-cookies.txt -s -X POST http://localhost:8000/api/login \
       -H "Content-Type: application/json" \
       -d '{"application":"app-built-in","organization":"built-in","username":"admin","password":"<CASDOOR_ADMIN_PASSWORD>","autoSignin":true,"type":"login"}'
     curl -b /tmp/casdoor-cookies.txt -s "http://localhost:8000/api/get-application?id=admin/brickkit-app" | grep -o '"clientId":"[^"]*"'
     ```
3. Put the `client_id` you found into `frontend/standard`'s `casdoorClientId` in `brickkit.yaml`, and `brickkit up` to redeploy just that one component.

**`infra-iam-casdoor`'s `webhookCallbackUrl`** — this repo already has the right value wired in for local development, but **deploying on a different machine, this value will very likely need recomputing**, because it's the gateway IP of the `be-net` Docker bridge network (not a fixed `172.18.0.1` — it depends on the order networks were created on that particular machine). Query command:

```bash
docker network inspect be-net --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}'
```

Take the gateway IP you get back, append `infra-iam-casdoor`'s host-mapped port (`8200` in the standard assembly) and the fixed path `/api/iam/webhooks/casdoor` — that's the value this item should hold.

### 4.6 Before a real customer deployment, confirm these local-dev placeholders have all been swapped

| Placeholder | Where | Swap it for |
|---|---|---|
| `CASDOOR_ADMIN_PASSWORD=123` | `.env` | A real customer environment should have Casdoor's admin password changed — update both sides together |
| `iamIssuerUrl: http://localhost:8000` | `brickkit.yaml` | The real domain, reachable from the browser, of the customer environment's Casdoor |
| The `172.18.0.1` in `webhookCallbackUrl` | `brickkit.yaml` | Look it up for real on the target machine using the command in §4.5 |
| The 5 `SHELL_*_PASSWORD` values | `.env` | Real random passwords (`openssl rand -base64 24`), and this must happen **before** `make db-init` — changing `.env` after the roles have already been created does not automatically sync to the already-created PG roles |

---

## 5. Shell-merged deployment / K8s

**⚠️ Deployment has two independent choices to make: topology (how components are grouped) and environment (where it runs). The two combine into 12 deployment forms, all real-machine verified.** This section only gives the most important conclusions and a quick-reference table; for what each form actually is, when to choose it, its benefits and costs, and the pitfalls hit during real-machine testing — the full write-up is in the dedicated [`deployment-selection-guide.md`](deployment-selection-guide.md). Read that first to decide which one you want, then come back here for how to operate it.

| Topology \ Environment | Local bare process | Docker | K8s | Docker + local hybrid |
|---|---|---|---|---|
| **Pure independent components** (no shells) | ✅ | ✅ | ✅ | ✅ |
| **Pure shells** (full `servedBy` merge) | ✅ | ✅ | ✅ | ✅ |
| **Component + shell mix** (this repo's current real form) | ✅ | ✅ | ✅ | ✅ |

**⚠️ The single most important thing to know: shell-merged deployment + K8s is now a brickKit-native, real-machine-verified capability.** Earlier documentation said "K8s means tearing every shell back apart into independent containers first — there's no partial-merge, partial-K8s middle ground." **That statement is now outdated**: merging into a shell now goes through brickKit's native `servedBy` field, which is fully compatible with K8s. `local: true` (bare-process debugging of a single component on the host, not `servedBy`) still cannot be combined with K8s — that restriction hasn't changed.

**This repo's current real deployment form** is "component + shell mix" (third row above) — the 11 Go components plus `infra/print` are merged into 4 shells (`go-core`/`go-backoffice`/`go-infra`/`py-render`); `infra/bff-mobile`/`frontend/standard` are structurally unable to merge (the former stays independent by design, the latter is a pure front-end SPA/H5 with no backend process to merge in the first place) and remain deployed independently. The "14 components" referenced in §3/§4 above is this same real form.

**How `servedBy` works, what to watch for in a K8s deployment, which multi-version-coexistence scenarios hold up, and which real bugs have been found and fixed over the years** — the complete write-up on all of these lives in [`deployment-selection-guide.md`](deployment-selection-guide.md); not repeated here.

### 5.1 Common configuration errors, quick reference

All of the errors below have been triggered on real hardware; every one is caught directly at the `brickkit up --dry-run` stage (no bad deployment file gets generated, and it never waits until an actual start attempt to fail) — the error code is uniformly `CONFIG_INVALID`:

| Misconfiguration | Error stage | What the error says |
|---|---|---|
| `servedBy` missing `@version` (format error) | Structural validation (earliest) | Points out the correct format, `<component-id>@<exact-version>` |
| `servedBy` pointing at itself | Structural validation | "cannot point at itself" |
| Shell A `servedBy`s shell B, and B itself `servedBy`s some other shell (chained nesting) | Structural validation | "a shell cannot be merged into another shell" — names **every single member** the offending shell has collected |
| A component declaring both `servedBy` and `local: true` at once | Structural validation | Explicitly states the two are semantically contradictory ("local means debugging on this machine; servedBy means the code is already baked into another shell's image") |
| The same `(component ID, exact version)` declared both independently and collected under some `servedBy` | Structural validation | Just the generic "duplicate declaration" error — not `servedBy`-specific logic |
| `servedBy` pointing at a component ID that doesn't exist anywhere in `brickkit.yaml` | Generation stage (later than structural validation — only reported after the dependency graph is resolved) | Points out the target doesn't exist, suggests checking for a typo in the ID/version |
| `servedBy` pointing at a shell that exists but is `enabled: false` or never started | Generation stage | Points out "there's nowhere for the code to run," suggests confirming the shell hasn't been disabled |
| `local: true` combined with `deploy.target: k8s` | Generation stage | Pods in the cluster can't reach a process on the developer's own machine — the error names the component and gives two actionable suggestions |
| `deploy.target: k8s` with `expose: true` but no `hostname` | Generation stage | K8s exposes services externally via Ingress + a domain name, unlike Docker's host-port mapping — `hostname` is required, not `exposePort` |

**If you hit one of these errors, don't assume it's an environment problem** — every one of the above is a static/generation-time validation on the `brickkit.yaml` declaration itself, independent of whether you're on Docker, K8s, or local — the error text always names the specific component and the specific reason; just fix it as described.

⚠️ **Shell-merged and fully-torn-apart states must never run against the same real infrastructure at the same time** — only one can be up at any given moment (they'd collide on ports, NATS broadcasts, and database state) — full reasoning in *BrickEnterprise Design Book* §13.9.

---

## 6. When something goes wrong, look here first

| Symptom | Most likely cause | How to confirm |
|---|---|---|
| `required variable XXX is missing a value` | **Compose didn't read `.env`** | Add `--env-file .env` (§2.1) |
| `port is already allocated` | A host port is taken | The command in §1.2 |
| `be-casdoor` keeps restarting, log says `password authentication failed` | `.env`'s `POSTGRES_PASSWORD` doesn't match what's in PG (e.g. you changed `.env` but didn't rebuild the `pg_data` volume) | `docker logs be-casdoor \| tail -20` |
| `be-casdoor` keeps restarting, log says `no schema has been selected to create in` | The `casdoor` schema was never created | Apply §3.2 manually |
| All containers `healthy`, but the gateway 404s | Traefik's routing config was never generated (component routing only exists from Phase 3 onward) | `curl http://localhost:28080/api/rawdata` |
| `infra-iam-casdoor` is `healthy`, but the log says "failed to log into the Casdoor admin API" | `.env`'s `CASDOOR_ADMIN_PASSWORD` doesn't match Casdoor's real admin password (§4.4) — won't crash the container, but self-bootstrap and `BatchGetUsers` stay permanently unavailable | Confirm Casdoor's current admin password, align `.env`, restart just that one container |
| `frontend/standard`'s login page won't open / an OIDC error | `casdoorClientId` is still empty, or `iamIssuerUrl` is still the local placeholder `localhost:8000` | §4.5/4.6 |
| Some container is `unhealthy` but its own logs say it came up fine | The health-check command doesn't actually work inside that image | `docker inspect -f '{{json .State.Health}}' <container> \| head -c 500` |
| `make check` reports "port in use: xxxx by a host process (insufficient permission to see the name…)" | **Normal, degraded-but-expected output — the script isn't broken.** The process holding the port doesn't belong to the current user (common when someone else started a container/service with root/sudo) — a non-root user simply can't see another user's process name; this is `ss`'s own permission model, not an error, just a column it can't fill in | Check it yourself per the hint: `sudo ss -ltnp \| grep :<port>`, or `sudo lsof -i :<port>` |
| `make check` shows all `○ missing` or a mix of `✓`, and yet the exit code is 0 | **This is intentional.** Only "wrong" (image/port/health mismatch, or a port taken) counts as `✗`; "not started yet" doesn't — that's exactly the expected state before the very first install | No action needed — run step ③ of §2.1 |
| `make check` fails, but what you see is `make: *** [Makefile:19: check] Error 2`, not `Error 1` | **Normal.** GNU Make's own error-code convention is "a failing recipe reports 2" — it doesn't pass through the script's internal `exit 1`. Both are non-zero; this doesn't affect whether you correctly read it as success/failure | No action needed |
| `make <swap-in>-up` reports "belongs to the same mutual-exclusion group as xxx…" | **Normal, intentional design.** Only one implementation of the same capability (storage/identity/event-bus/gateway) can be installed at a time — it won't auto-stop the old one for you | Follow the hint: `make <old-implementation>-down`, then retry `make <swap-in>-up` |
| `container be-nats is unhealthy`, and the log is nats-server's own usage text (`flag provided but not defined`) | **A configuration problem, not an environment problem on your end.** The image version in use has changed, and `command` now contains a flag only a different config file would recognize | Send this back to us; as a stopgap: `docker logs be-nats` to find the exact offending flag, cross-check against `docker run --rm nats:<version> --help` |
| `make up` hangs and eventually times out | Some container's health check never passes (`--wait` waits up to 180 seconds) | In a new terminal: `docker inspect -f '{{json .State.Health}}' <container>` to see the recent check output |
| `be-otel` / `be-loki` / `be-tempo` keep restarting or stay `unhealthy`, log says `exec: "/bin/sh": stat /bin/sh: no such file or directory` | Another face of expected behavior (this happens if you manually edited the compose file and added a healthcheck back in): these three images have no shell, so any `CMD-SHELL`-style health check will always fail this way | Don't add a healthcheck to these three services; use the host-side curl checks from §2.3 instead |
| `curl http://localhost:3100/ready` returns 503, `"Ingester not ready"` | Loki's normal single-binary-mode startup delay (roughly 15 seconds), not a failure | Wait 15–20 seconds and curl again |

**If you get stuck, stop and report it back — don't work around it.** In particular, don't change ports, remove health checks, or reach for a flag like `--project-directory` just to "get it running" — those changes will come back to bite you later, in the form of a completely unrelated-looking error while installing components.

---

## 7. A few terms you'll run into but don't need to fully understand

| Term | One-line meaning |
|---|---|
| Out-of-band container | Something run straight from an official image (PG / NATS / Traefik / Casdoor / RustFS). These are **not** in `brickkit.yaml` |
| Component | One of our own business bricks, declared in `brickkit.yaml`. Currently 14 of them |
| Shell | Merges multiple components into one process to save resources. Only exists from Phase 4 onward |
| Schema | A component's own isolated territory inside the database. **Cross-schema queries are strictly forbidden** — this is the authorization wall |
| `be-net` | The Docker network shared by every container. Without it, containers can't see each other |
