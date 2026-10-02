[English](24-config-and-secrets.md) · [中文](../../zh/04-foundations/24-config-and-secrets.md)

# Configuration and secrets

How a component receives its configuration and its secrets, how values are written in the project, and how a secret is rotated. For whoever adds a configuration key, handles a password or a private key, or is asked to plug in Vault, a cloud secret manager or a configuration centre.

## Scope

- the configuration surface every component exposes, whatever its language;
- the value forms brickKit understands and where each one ends up on Docker and Kubernetes;
- how values are parsed and validated at start, standalone and in a shell;
- the secret source port: reading a secret, re-reading it, rotating it without a restart;
- where secrets live on a developer machine.

Not covered: which keys exist and how they are named ([04-configuration.md](../01-conventions/04-configuration.md); the full catalogue of protocol keys, with types and defaults, is `be-protocol` `schemas/config-keys.yaml`, chapter P2); deployment mechanics per target (the `brickkit-deploy` skill).

## Choice

- **Configuration arrives only as environment variables**, each declared in the component's `configSchema`. There is no configuration server and no runtime configuration API; brickKit generates the values and exits.
- **Values are written in brickKit's forms**: a literal, `$var:NAME`, `${NAME}`, `file://path`, `{existingSecret: name, key: key}`.
- **Parsing is strict**: a value of the wrong type stops the start and names the key; nothing falls back silently; a module never panics on configuration. A shell collects every member's configuration errors and reports them together before serving.
- **A secret source port in the SDK**: a secret is read through it at the moment of use, not copied once at start. Sources: environment (default), a mounted file re-read when it changes, OpenBao later. The database pool asks for the password on every new connection, so a password can rotate without a restart.
- **Kubernetes**: External Secrets Operator plus `existingSecret`, no code.
- **Developer machines**: a SOPS-encrypted secrets file committed to Git, decrypted locally into `.env`, instead of a plaintext `.env` alone.

**Status**: in place: the environment-variable surface, brickKit's value forms, the Docker 0600 env files and Kubernetes Secrets. Decided (the 3.0.0 sweep and its SDK release): strict parsing, the collected shell errors, the secret source port with the environment and file sources, the per-connection password, SOPS on developer machines. Later: the OpenBao source. Rotation without restart also needs secrets delivered as files, which brickKit 1.1.0 does not generate (see **Known limits**).

## Port contract

**The configuration surface.**

- A key is an environment variable name, declared in `configSchema` with its type, whether it is required, its default and whether it is `secret: true` ([04-configuration.md](../01-conventions/04-configuration.md#key-names)).
- Component code reads configuration only from the runtime the SDK hands it, never from the process environment ([02-backend.md](../01-conventions/02-backend.md#merge-safety)).
- In a shell, brickKit passes every member's configuration as one JSON value (`BRICKKIT_SERVED_MEMBERS_CONFIG`); the launcher gives each member only its own keys ([27-shells.md](27-shells.md)).

**Protocol keys that are easy to get wrong.** Not the full list; `be-protocol` `schemas/config-keys.yaml` is canonical for every name and default.

| Key | Default | Meaning |
|---|---|---|
| `PG_USER`, `PG_PASSWORD` (secret) | — | the runtime role: DML only, not a member of the owner role; the service's login role and the role every transaction switches to with `SET LOCAL ROLE`. In a shell, the shell's login role does `SET LOCAL ROLE` to each member's `PG_USER` ([03-database.md](03-database.md)) |
| `PG_OWNER_USER`, `PG_OWNER_PASSWORD` (secret) | — | the owner role: `LOGIN`, owns the tables, runs the migrations and the platform migration; never a literal, never used by the running service. Limitation: brickKit gives the migration container the service's environment, so the running process also receives both keys and the SDK ignores them, until brickKit FR06-013 (migration-only environment overrides) lands |
| `S3_PUBLIC_URL` | `S3_URL` | the address browsers use; presigned URLs are signed for it ([22-object-storage.md](22-object-storage.md)) |
| `DEFAULT_LOCALE` | `zh-CN` | the deployment's default language (BCP 47), shared: the `title` and `detail` of problem bodies, the fallback of server-side text ([26-i18n-data.md](26-i18n-data.md)) |
| `AUTHZ_URL`, `IAM_URL` | — | base URL of the installed authorization / identity member by the member's own service name, shared in `config/vars.yaml`, never a dependency edge. The family's gRPC port is derived from its `*_URL` by the rule in `be-protocol` P2 |
| `BOOTSTRAP_ADMIN_LOGIN` | — | the IdP login name or e-mail of the first administrator, shared; bound to the platform `sub` at that person's first login, because the platform `sub` cannot be known before. There is no `BOOTSTRAP_ADMIN_SUB` |
| `EVENTS_MAX_DELIVER` | `8` | the SDK-side dead-letter threshold: when a message's `NumDelivered` exceeds it, the SDK writes the dead-letter message and terminates the original; the server's `MaxDeliver` is `-1` ([12-event-bus.md](12-event-bus.md)) |
| `EVENTS_BACKOFF` | `1s,10s,1m,5m,15m,30m,1h` | the SDK's `NakWithDelay` schedule; the consumer has no server-side `BackOff` |

**Value forms**, written in `config/vars.yaml`, `config/<scope>-<name>.yaml` or a deploy file's `vars:`:

| Written | Meaning | Docker / Podman | Kubernetes |
|---|---|---|---|
| a literal | the value itself | `environment` in `compose.yaml` | `env.value` |
| `$var:NAME` | the shared value `NAME` from `config/vars.yaml` or the deploy file's `vars:` | as the resolved value | as the resolved value |
| `${NAME}` | from the process environment, then `.env`; generation fails if undefined (`${NAME:-}` allows empty) | expanded by compose at start; a `secret: true` item goes into `.brickkit/generated/env/<service>.env` (mode 0600) | expanded at generation; a `secret: true` item goes into a generated Secret, referenced by `secretKeyRef` |
| `file://.secrets/x` | the file's content, **read and inlined when deployment files are generated** | into the 0600 env file | into the generated Secret |
| `{existingSecret: name, key: key}` | a Kubernetes Secret managed elsewhere | not injected (warned) | `secretKeyRef` to it; brickKit never reads it |

**Parsing rules**, in every SDK:

- An integer, boolean or duration that does not parse stops the start with an error naming the key; a present but invalid value never falls back to the default.
- A missing required key stops the start, naming the key.
- In a shell all members' errors are collected and printed together, and the shell does not start; a module returns its error, never exits the process.

**Secret source.**

- A secret is read through the source when it is used, and the source answers with the current value or an error.
- **Environment source** (default): the value of the environment variable. It never changes while the process runs.
- **File source** (decided): when a secret's configured value is a runtime file reference, `@file:/run/secrets/<name>`, the source reads that file and re-reads it when its modification time changes. This is not brickKit's `file://`, which is inlined at generation time; `@file:` names a file mounted into the running container (a Kubernetes Secret volume, an OpenBao Agent sink, a compose secret).
- **OpenBao source** (later): AppRole or Kubernetes authentication, lease renewal, behind the same contract.
- The database pool reads `PG_PASSWORD` through the source for every new connection. Rotation: `ALTER ROLE … PASSWORD` → update the secret → new connections use the new password; old connections retire at `PG_CONN_MAX_LIFETIME` (default 30 min, see [03-database.md](03-database.md)).
- **Token signing keys** rotate by publishing two keys: the iam member signs with the current key and publishes current and previous in the JWKS (`APP_TOKEN_PREVIOUS_PUBLIC_KEY_PEM`), so tokens signed before the switch still verify ([21-identity-provider.md](21-identity-provider.md)).

**Developer machines** (decided): `secrets.enc.yaml`, encrypted with SOPS and an age key, is committed; each developer decrypts it into `.env` with their own key. Secret values are never printed, logged or pasted into a conversation.

## Alternatives

| Option | What it is | Licence | For this project |
|---|---|---|---|
| Environment variables + `.env` (in place) | the simplest possible | — | stays the default surface |
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
- A source read at the moment of use makes rotation possible without restarting a process, and without any component code knowing where the secret comes from.

## Why not the others

- **A configuration centre**: a runtime dependency of every component, a second source of truth beside `config/`, and "what runs" no longer equals "what is committed".
- **Calling Vault directly from components**: every component would learn a vendor API, and Vault's licence changed; OpenBao behind the source port gives the same result without that.
- **Plaintext `.env` only**: secrets have leaked from it into logs and conversations; an encrypted file in Git keeps them shared without exposure.

## When to switch

- A customer mandates a secret platform: on Kubernetes use External Secrets Operator with `existingSecret` (no change at all); elsewhere add an adapter for that platform behind the secret source port.
- A customer requires rotation without restart: use the file source with secrets mounted as files.

## How to switch

1. Kubernetes with External Secrets Operator: write `{existingSecret: <name>, key: <key>}` for the item in `config/<scope>-<name>.yaml`. Only items declared `secret: true` accept it.
2. File source: set the secret's value to `@file:/run/secrets/<name>` and make sure the file is mounted into the container.
3. A new source (OpenBao or another platform): implement the source contract inside each official SDK, run the secret conformance suite, then select it in configuration; no component code changes.

## Conformance tests

Suite `tools/be-acceptance/conformance/secret/` (decided): rotating the database password through the file source while requests run gives zero failed requests.

SDK tests in every official SDK, written red first:

- a present but invalid integer stops the start and names the key;
- a shell with two misconfigured members reports both errors at once and does not panic;
- after the secret file changes, the source returns the new value;
- after a password rotation new connections succeed and old ones retire at their maximum lifetime.

## Decision records

- [0106 Infrastructure is not a component](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md): shared connection keys written once in `config/vars.yaml`.
- [0107 Authorization and identity are reached through shared variables](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md): shared addresses as configuration.
- [0109 The rules live in a language-neutral component protocol](../02-decisions/01-architecture/0109-language-neutral-component-protocol.md): the configuration keys and strict parsing are part of the component protocol.
- Planned: none. "No configuration server" is brickKit's own design principle, recorded in the root `AGENTS.md`.

## Known limits

- An environment variable is visible to anyone who can inspect the container; secrets on Docker sit in 0600 files on the host.
- brickKit 1.1.0 delivers secrets only as environment variables (Docker env file, Kubernetes `secretKeyRef`); it does not mount them as files. Until it does, the file source needs a mount made outside brickKit's generated files, and rotation on a stock deployment is: update the value, regenerate, restart. A feature request to brickKit is planned.
- `file://` is read once, at generation time: changing the file changes nothing until the files are regenerated and the component restarted.
- `existingSecret` exists only on Kubernetes.
- A shell's members' configuration travels as one JSON value on the secret path; one member's secret is in the same value as the others'.
