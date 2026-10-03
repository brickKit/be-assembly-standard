[English](24-config-and-secrets.md) · [中文](../../zh/04-foundations/24-config-and-secrets.md)

# Configuration and secrets

How a component receives its configuration and its secrets, how values are written in the project, and how a secret is rotated. For whoever adds a configuration key, handles a password or a private key, or is asked to plug in Vault, a cloud secret manager or a configuration centre.

## Scope

- the configuration surface every component exposes, whatever its language;
- the value forms brickKit understands, including `$endpoint:` for another component's address, and where each one ends up on Docker and Kubernetes;
- how values are parsed and validated at start, standalone and in a shell;
- secrets: delivered as files, read at the moment of use, re-read when they change, rotated without a restart;
- where secrets live on a developer machine.

Not covered: which keys exist and how they are named ([04-configuration.md](../01-conventions/04-configuration.md); the full catalogue of protocol keys, with types and defaults, is `be-protocol` `schemas/config-keys.yaml`, chapter P2); deployment mechanics per target (the `brickkit-deploy` skill).

## Choice

- **Configuration arrives only through environment variables**, each declared in the component's `configSchema`. There is no configuration server and no runtime configuration API; brickKit generates the values and exits.
- **No secret value is ever in an environment variable.** Every key declared `secret: true`, protocol or the component's own, is also declared `mount: file` and named with the suffix `_FILE`, and no other key ends in `_FILE` (be-protocol P2.12) (`PG_PASSWORD_FILE`, `PG_OWNER_PASSWORD_FILE`, `S3_SECRET_ACCESS_KEY_FILE`, `APP_TOKEN_SIGNING_KEY_FILE`): brickKit writes the value into a file mounted into the container, and the variable holds that file's path.
- **The SDK reads a secret file at the moment of use and re-reads it when it changes** (modification time and size, compared at most 30 s apart). The database pool reads the password for every new connection, so a password rotates without a restart; signing keys rotate with an overlap in the JWKS.
- **Values are written in brickKit's forms**: a literal, `$var:NAME`, `${NAME}`, `file://path`, `$endpoint:<component ID>[:<port>][/<path>]`, `{existingSecret: name, key: key}`. Another component's address that is not a declared dependency (a slot-family member) is always `$endpoint:`, never written by hand ([0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)).
- **The protocol block of each `configSchema` is generated.** be-ops writes the protocol keys a component's profiles need, with the catalogue's type, default, `secret` and `mount` flags, from `be-protocol` `schemas/config-keys.yaml`; a gate fails when the block is not current. brickKit declined `configSchema` fragments (FR06-014): a released `component.yaml` must describe itself completely, so the copy is made by a generator before release, not by a reference at read time.
- **Parsing is strict**: a value of the wrong type stops the start and names the key; nothing falls back silently; a module never panics on configuration. A shell collects every member's configuration errors and reports them together before serving.
- **Kubernetes**: External Secrets Operator plus `existingSecret`, mounted as a file like any other secret; no code.
- **Developer machines**: a SOPS-encrypted secrets file committed to Git, decrypted locally into `.env`, instead of a plaintext `.env` alone.

**Status**: in place: the environment-variable surface, brickKit's value forms, the Docker 0600 env files and Kubernetes Secrets. brickKit 1.2 added `$endpoint:` and 1.3 added secrets delivered as files (`mount: file`), the two mechanisms this design needs from the platform. Decided (the 3.0.0 sweep and its SDK release): every secret as a `_FILE` key, the file re-read in all three SDKs, the generated protocol block, family addresses as `$endpoint:` references, strict parsing, the collected shell errors, SOPS on developer machines. Later: an OpenBao source.

## Port contract

**The configuration surface.**

- A key is an environment variable name, declared in `configSchema` with its type, whether it is required, its default, whether it is `secret: true`, and for a secret `mount: file` ([04-configuration.md](../01-conventions/04-configuration.md#key-names)).
- Component code reads configuration only from the runtime the SDK hands it, never from the process environment ([02-backend.md](../01-conventions/02-backend.md#merge-safety)).
- In a shell, brickKit passes every member's configuration as one JSON value (`BRICKKIT_SERVED_MEMBERS_CONFIG`); the launcher gives each member only its own keys ([27-shells.md](27-shells.md)). A member's `mount: file` items are not in the JSON: the JSON holds the path, and the file is mounted into the shell's container at exactly the path it has when the member runs alone.

**Protocol keys that are easy to get wrong.** Not the full list; `be-protocol` `schemas/config-keys.yaml` is canonical for every name and default.

| Key | Default | Meaning |
|---|---|---|
| `PG_USER`, `PG_PASSWORD_FILE` (secret, file) | — | the runtime role: DML only, not a member of the owner role; the service's login role and the role every transaction switches to with `SET LOCAL ROLE`. In a shell, the shell's login role does `SET LOCAL ROLE` to each member's `PG_USER` ([03-database.md](03-database.md)) |
| `PG_OWNER_USER`, `PG_OWNER_PASSWORD_FILE` (secret, file) | — | the owner role: `LOGIN`, owns the tables, runs the migrations and the platform migration; never a literal, never used by the running service. brickKit gives the migration container exactly the service's environment and mounts (FR06-013, migration-only overrides, was declined on purpose), so the running container also holds the owner's password file; the SDK never reads it at run time |
| `PG_MIGRATION_HOST`, `PG_MIGRATION_PORT` | `PG_HOST`, `PG_PORT` | where migrations connect when `PG_HOST` is a transaction-mode pooler: straight to PostgreSQL. This is the pattern brickKit recommends for a migration that needs another connection: the component declares its own keys ([08-schema-evolution.md](08-schema-evolution.md#the-migration-entry)) |
| `AUTHZ_URL`, `AUTHZ_GRPC_URL`, `IAM_URL`, `IAM_GRPC_URL` | — | the installed authorization / identity member's main port and its port named `grpc`, written once in `config/vars.yaml` as `$endpoint:` references (`$endpoint:infra/authz:grpc`), never a dependency edge and never a hand-written address. Values are `http://host:port` with no trailing `/`; the SDK dials a `*_GRPC_URL` as `host:port` ([0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)) |
| `S3_PUBLIC_URL` | `S3_URL` | the address browsers use; presigned URLs are signed for it ([22-object-storage.md](22-object-storage.md)) |
| `DEFAULT_LOCALE` | `zh-CN` | the deployment's default language (BCP 47), shared: the `title` and `detail` of problem bodies, the fallback of server-side text ([26-i18n-data.md](26-i18n-data.md)) |
| `BOOTSTRAP_ADMIN_LOGIN` | — | the IdP login name or e-mail of the first administrator, shared; bound to the platform `sub` at that person's first login, because the platform `sub` cannot be known before. There is no `BOOTSTRAP_ADMIN_SUB` |
| `EVENTS_MAX_DELIVER` | `8` | the SDK-side dead-letter threshold: when a message's `NumDelivered` exceeds it, the SDK writes the dead-letter message and terminates the original; the server's `MaxDeliver` is `-1` ([12-event-bus.md](12-event-bus.md)) |
| `EVENTS_BACKOFF` | `1s,10s,1m,5m,15m,30m,1h` | the SDK's `NakWithDelay` schedule; the consumer has no server-side `BackOff` |
| `SHUTDOWN_GRACE` | `25s` | in-flight work allowed after `SIGTERM`; at least 5 s below the platform's stop grace period, which the component declares in `component.yaml` `deployment.stopGracePeriodSeconds` (default `30`) ([27-shells.md](27-shells.md#port-contract)) |

**Value forms**, written in `config/vars.yaml`, `config/<scope>-<name>.yaml` or a deploy file's `vars:`:

| Written | Meaning | Docker / Podman | Kubernetes |
|---|---|---|---|
| a literal | the value itself | `environment` in `compose.yaml` | `env.value` |
| `$var:NAME` | the shared value `NAME` from `config/vars.yaml` or the deploy file's `vars:` | as the resolved value | as the resolved value |
| `${NAME}` | from the process environment, then `.env`; generation fails if undefined (`${NAME:-}` allows empty) | expanded by compose at start; a `secret: true` item without `mount: file` goes into `.brickkit/generated/env/<service>.env` (mode 0600) | expanded at generation; a `secret: true` item goes into a generated Secret |
| `file://.secrets/x` | the file's content, **read when deployment files are generated**; relative to the project root, or absolute (`file:///etc/…`) | inlined into the env file, or written to the mounted secret file | into the generated Secret |
| `$endpoint:<ID>[@<version>][:<port>][/<path>]` | another component's address, `http://<versioned service name>:<port>` plus the path; computed by the same rule as `*_ENDPOINT`, following upgrades, shells and local runs; no start order, cycles allowed; absent when the referenced component does not run | as the resolved value | as the resolved value; `networkPolicy` opens the connection |
| `{existingSecret: name, key: key}` | a Kubernetes Secret managed elsewhere | not injected (warned) | mounted as a file for a `mount: file` item, in the same directory as the generated ones; `secretKeyRef` otherwise |

**Secrets delivered as files** (`secret: true` plus `mount: file`, every secret):

| | Docker / Podman | Kubernetes | `mode: local` / `debug` |
|---|---|---|---|
| where the file is | `/run/brickkit/secrets/<versioned service name>/<KEY>`, from `.brickkit/generated/secrets/<service>/`, a read-only directory mount | the same path, a projected volume of the generated Secret (and of any `existingSecret`) | the file's absolute path on the host |
| what the variable holds | the path | the path | the path |
| after the value changes | `up` rewrites the file; the container is not recreated | `up` updates the Secret; the kubelet syncs the file, usually within a minute; no restart, and no `brickkit.io/secret-digest` roll for file items | `up` rewrites the file |

- The file's content is the value byte for byte: no quoting, no escaping, no trailing newline added; binary is allowed.
- The migration container mounts what the main container mounts.
- `up --dry-run` writes no secret file: writing one would be deploying.
- On the host `.brickkit/generated/secrets/` is mode 0700; the files under it are readable by others, because the process in the container usually runs as neither root nor the host user.

**Parsing rules**, in every SDK:

- An integer, boolean or duration that does not parse stops the start with an error naming the key; a present but invalid value never falls back to the default.
- A missing required key stops the start, naming the key; so does a `_FILE` key whose file does not exist or cannot be read at start.
- In a shell all members' errors are collected and printed together, and the shell does not start; a module returns its error, never exits the process.

**Secret files at run time.**

- A secret is read through the SDK when it is used, and the SDK answers with the current content or an error; component code never opens the file itself.
- The SDK keeps the content and re-reads the file when its modification time or size changes, comparing them at most 30 s apart (a file-system watch may notice sooner); it never restarts for it and logs one INFO line naming the key per change. A text secret loses exactly one trailing newline; a component's own binary secret is handed over byte for byte. A read that fails after a change keeps the last good value, logs an ERROR naming the key, never the value, and counts `be_secret_reload_failures_total`.
- **Database credentials**: the pool reads `PG_PASSWORD_FILE` for every new connection. Rotation: `ALTER ROLE … PASSWORD` → change the value in `config/` → `up` → new connections use the new password; old connections retire at `PG_CONN_MAX_LIFETIME` (default 30 min, see [03-database.md](03-database.md)).
- **Token signing keys** rotate with an overlap in the JWKS, no restart: write the new private key to `APP_TOKEN_NEXT_SIGNING_KEY_FILE` and `up` (every replica publishes its public key within 30 s); at least an hour later move it to `APP_TOKEN_SIGNING_KEY_FILE`, clear the next key and `up`. The iam member records in its own schema the public key of every key it has signed with, and keeps publishing it for the access-token lifetime plus 60 s after it stopped signing, so tokens signed before the switch still verify (contract-infra-iam `TOKENS.md`, [21-identity-provider.md](21-identity-provider.md)). `APP_TOKEN_PREVIOUS_PUBLIC_KEY_PEM` retires.
- **An OpenBao source** (later): AppRole or Kubernetes authentication, lease renewal, behind the same read-at-use contract.

**Developer machines** (decided): `secrets.enc.yaml`, encrypted with SOPS and an age key, is committed; each developer decrypts it into `.env` with their own key. Secret values are never printed, logged or pasted into a conversation.

## Alternatives

| Option | What it is | Licence | For this project |
|---|---|---|---|
| Environment variables + `.env` (in place) | the simplest possible | — | stays the surface for everything but secret values |
| Secrets as files mounted by brickKit (`mount: file`, chosen) | the value in a file, the path in the variable; rewritten in place by `up` | — | every secret; rotation without restart on both targets |
| Kubernetes Secret + External Secrets Operator | syncs Vault, OpenBao or a cloud KMS into Kubernetes Secrets | Apache-2.0 | the recommended Kubernetes path, with `existingSecret`, no code |
| HashiCorp Vault | dynamic database credentials, leases | BUSL since 2023 | licence risk |
| OpenBao (Linux Foundation fork of Vault) | Vault-compatible API | MPL-2.0 | the first target for a direct source adapter |
| SOPS (CNCF) | encrypted files committed to Git | MPL-2.0 | replaces plaintext `.env` on developer machines |
| Cloud secret managers / KMS | managed | commercial | through External Secrets Operator |
| Configuration centres (Nacos, Apollo, Consul KV) | dynamic configuration served at run time | — | rejected: a configuration server is a runtime dependency brickKit's design excludes |

## Why this choice

- It follows brickKit: the CLI generates deployment files and exits; there is no configuration server to keep alive or to depend on at start.
- One surface for every language: an environment variable is the most portable contract there is.
- Strict parsing turns a typo into a start error that names the key, instead of a component quietly running on its default.
- A secret read from a file at the moment of use makes rotation possible without restarting a process, and keeps the value out of `docker inspect`, a Pod's env, process dumps and crash reports, without any component code knowing where the secret comes from.
- `$endpoint:` makes brickKit, which knows the versions and the topology, compute every address that is not a dependency; a hand-written address is a second copy of `brickkit.yaml` that goes stale on the next release.

## Why not the others

- **A configuration centre**: a runtime dependency of every component, a second source of truth beside `config/`, and "what runs" no longer equals "what is committed".
- **Calling Vault directly from components**: every component would learn a vendor API, and Vault's licence changed; OpenBao behind the SDK's read-at-use contract gives the same result without that.
- **Plaintext `.env` only**: secrets have leaked from it into logs and conversations; an encrypted file in Git keeps them shared without exposure.
- **Secrets in environment variables** (brickKit's default for `secret: true`): fixed at process start, so rotation needs a restart (on Kubernetes a `brickkit.io/secret-digest` roll), and visible to anything that can read the process environment.
- **A runtime file reference inside the value** (`@file:/run/secrets/<name>`, the earlier design): needed a mount made outside brickKit's generated files; `mount: file` gives the same re-readable file with the mount generated.

## When to switch

- A customer mandates a secret platform: on Kubernetes use External Secrets Operator with `existingSecret` (no change at all); elsewhere add an adapter for that platform behind the SDK's read-at-use contract.
- Another tool rotates a secret on Kubernetes (cert-manager, External Secrets Operator): point the item at its Secret with `existingSecret`; the file follows the rotation without an `up`.

## How to switch

1. Kubernetes with External Secrets Operator: write `{existingSecret: <name>, key: <key>}` for the item in `config/<scope>-<name>.yaml`. Only items declared `secret: true` accept it.
2. Rotation: change the value in `config/` (or in the external Secret) and run `up`; nothing restarts. Database passwords: `ALTER ROLE … PASSWORD` first, keeping the old one valid until `PG_CONN_MAX_LIFETIME` has passed.
3. A new source (OpenBao or another platform): implement the read-at-use contract inside each official SDK, run the secret conformance suite, then select it in configuration; no component code changes.

## Conformance tests

Suite `tools/be-acceptance/conformance/secret/` (decided): rotating the database password by rewriting its mounted file while requests run gives zero failed requests. The component suite checks (CP-CORE-14) that no secret value is in the environment, that every `secret: true` key is `mount: file` with a `_FILE` name, and that a replaced secret file is used without a restart; the gate `protocol-config-scan` checks that the generated protocol block of `configSchema` is current.

SDK tests in every official SDK, written red first:

- a present but invalid integer stops the start and names the key;
- a shell with two misconfigured members reports both errors at once and does not panic;
- after the secret file changes, the SDK returns the new value within 30 s, in Go, Python and TypeScript;
- a secret file that cannot be read after a change keeps the last good value, logs an ERROR without the value and counts `be_secret_reload_failures_total`;
- after a password rotation new connections succeed and old ones retire at their maximum lifetime.

## Decision records

- [0106 Infrastructure is not a component](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md): shared connection keys written once in `config/vars.yaml`.
- [0107 Family addresses are `$endpoint:` references in shared variables](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md): family addresses as configuration, computed by brickKit.
- [0109 The rules live in a language-neutral component protocol](../02-decisions/01-architecture/0109-language-neutral-component-protocol.md): the configuration keys and strict parsing are part of the component protocol.
- Planned: none. "No configuration server" is brickKit's own design principle, recorded in the root `AGENTS.md`.

## Known limits

- A non-secret environment variable is visible to anyone who can inspect the container. A secret file is readable by anyone who can enter the container, and on a Docker host by any local user who can traverse into `.brickkit/generated/secrets/` (the top directory is 0700, the files below it are not).
- Secrets as files are tested by brickKit on Docker and on Kubernetes only. Podman, and a host with SELinux enforcing (where the directory mount may need relabelling), are untested; a component that cannot read its file there is recorded for brickKit.
- The running service's container holds the owner's password file, because the migration container gets the same mounts; brickKit declined migration-only overrides (FR06-013). The SDK never reads it at run time.
- Rotation is not instant: up to the SDK's 30 s check, plus the kubelet's sync on Kubernetes (usually under a minute).
- `file://` is read at generation time: changing the source file changes nothing until the next `up`, which then rewrites the mounted file without a restart.
- `existingSecret` exists only on Kubernetes.
- A shell's non-file configuration travels as one JSON value on the secret path; secrets are files and are not in it.
