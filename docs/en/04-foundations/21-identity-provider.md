[English](21-identity-provider.md) · [中文](../../zh/04-foundations/21-identity-provider.md)

# Identity provider

Who authenticates a person, what token the platform issues, who owns the user id, and how the identity provider behind it can be swapped. For whoever touches login, token verification, the user directory, or plans to replace Casdoor.

## Scope

- the login flow between the browser, the identity provider (IdP) and the platform;
- the application token: its claims, its signing keys (JWKS), its verification rules in every SDK;
- the platform-owned user id (`sub`) and its links to IdP accounts;
- directory events (user created, updated, disabled, deleted) and user lookup;
- the IAM slot family, its family contract and its conformance suite;
- the shapes reserved for service accounts and delegation tokens.

Not covered: what a person may do once identified ([20-authorization-provider.md](20-authorization-provider.md)); tenancy (`tenant_id`, `aud`, one deployment per customer: [07-tenancy.md](07-tenancy.md)).

## Choice

- **The IdP only authenticates.** The installed IAM member exchanges the IdP's ID token for the **platform's own application token**, which every component verifies locally against the published keys.
- **The platform owns `sub`.** The token's `sub` is a platform user id (UUIDv7). The IdP's subject is stored only in the member's link table, so changing IdP never rewrites an `owner_id`, a role assignment or an audit row.
- **Standards only between the frontend and the IdP**: OIDC discovery, authorization code with PKCE, a token exchange shaped like RFC 8693. No vendor path in the frontend or in a contract field.
- **A slot family** with contract `infra.iam.v1` in its own repository, `contract-infra-iam`, and suite `iamconf`. Members, in order: `infra/iam-casdoor` (default), `infra/iam-keycloak` (second, built in phase 06), a generic OIDC + SCIM member (third).
- **No component depends on a member.** Components read `IAM_URL` and fetch the JWKS under it ([0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)); the IAM member itself reaches authz only through `AUTHZ_URL` and `AUTHZ_GRPC_URL`, never through a dependency edge.

**Status**: in place: `infra/iam-casdoor` 2.0.x exchanges a Casdoor ID token (field `casdoor_id_token`) for an RS256 token with `sub` (Casdoor's subject), `roles`, `dept_path`, `org_id`, TTL 600 s, refresh rotation, JWKS at `/.well-known/jwks.json`, Casdoor webhooks bridged to user events. Decided (the 3.0.0 sweep): everything else here. The access token does not yet carry `iss`, `aud`, `jti` or `typ`, and a refresh token passes verification as an access token; adding `typ: access` and rejecting `typ: refresh` is the first fix.

## Port contract

**Login configuration.** `GET /api/iam/login-config` (public) → `{issuer, discovery_url, client_id, scopes, pkce: "S256", end_session_supported}`. The frontend reads the IdP's `/.well-known/openid-configuration` from `discovery_url` and takes the authorization and token endpoints from it. `GET /api/tenant/features` (public) carries only what the login page needs before sign-in: `contract`, `tenant_id`, `capabilities`, `default_locale`, `locales`.

**Token exchange.** `POST /api/iam/token`, form-encoded:

| Field | Value |
|---|---|
| `grant_type` | `urn:ietf:params:oauth:grant-type:token-exchange` |
| `subject_token` | the IdP's ID token |
| `subject_token_type` | `urn:ietf:params:oauth:token-type:id_token` |
| `audience` | optional |

The answer carries `access_token`, `issued_token_type`, `token_type`, `expires_in`, `refresh_token`, `refresh_expires_in`. The Casdoor member also accepts the field `casdoor_id_token` until the 06c frontend has moved to the token exchange; it is then removed. `POST /api/iam/token/refresh` rotates the refresh token (the old one is invalid at once); `POST /api/iam/logout` revokes it.

**Token errors.** Every failure on these paths is problem+json ([15](15-user-api-and-errors.md#the-error-body)) with a reason of domain `infra/iam` (the family's ID, whichever member is installed) or a reserved `be` reason; `metadata.oauth_error` carries the RFC 6749 §5.2 code (`invalid_grant`, `invalid_request`, …) for OAuth-aware clients. There is no top-level `error` member.

**Application token claims:**

| Claim | Meaning |
|---|---|
| `iss` | the platform issuer, shared key `IAM_ISSUER`: a stable name, `urn:be:<TENANT_ID>:iam`, not an address; unchanged when the member is swapped |
| `aud` | the deployment, shared key `TENANT_ID` |
| `sub` | platform user id (UUIDv7); `svc:<id>` for a service account (reserved) |
| `typ` | `access` or `refresh` |
| `iat`, `nbf`, `exp`, `jti` | standard; access TTL 600 s, refresh 7 days |
| `tenant_id` | tenant / default legal entity; `org_id` is deprecated |
| `roles`, `dept_path` | resolved from the authorization provider's `ResolveClaims` at login and refresh; `dept_path` is **omitted** when the user has no department, never `""` or `"/"` |
| `act` | `{sub, kind: user|agent|svc}`, the acting party, nestable (RFC 8693 §4.1); `agent` is reserved |
| `ceil`, `dg` | ceiling profile codes and delegation grant id ([20-authorization-provider.md](20-authorization-provider.md)) |
| `azp` | the client (PC, mobile) |
| `locale` | the user's language, for server-side text |

**Signing keys.** The JWKS at `{IAM_URL}/.well-known/jwks.json` publishes one to three keys: the current key, the previous one during a rotation, and optionally the next one ahead of use; every key has a `kid` and an `alg`. The private keys are the secret files `APP_TOKEN_SIGNING_KEY_FILE` and `APP_TOKEN_NEXT_SIGNING_KEY_FILE`, re-read without a restart; the member records every public key it has signed with in its own schema, so the overlap survives restarts and replicas ([24](24-config-and-secrets.md#port-contract)).

**Verification, in every SDK and any language:**

- `alg` comes from the JWKS key and must be one of `RS256`, `ES256`, `EdDSA`; the token header cannot choose it.
- `kid` is required. An unknown `kid` refetches the JWKS, rate-limited, then fails.
- `iss` must equal `IAM_ISSUER`; `aud` must contain `TENANT_ID`; `exp` and `nbf` are checked.
- `typ` must be `access`; `refresh` and a missing `typ` are rejected.
- A token whose `iat` is before the bundle's `stale_since` for its `sub` answers `401` with reason `TOKEN_STALE` and `WWW-Authenticate: Bearer error="token_stale"`, and the frontend refreshes silently.

**Platform `sub` and identity links.** The member keeps `identity_links(idp, idp_issuer, idp_sub, user_id)` with one row per IdP account. The first login of an unknown IdP account creates a platform user. Linking to an existing user is by exact `(idp_issuer, idp_sub)` by default; automatic linking by e-mail is an opt-in with a security risk. The family defines an NDJSON export of the links so a new member can import them and keep every `sub`.

**Bootstrap administrator.** The platform `sub` exists only after a person's first login, so the first administrator is named by `BOOTSTRAP_ADMIN_LOGIN`: the IdP login name, or a verified e-mail address. At a login exchange the member matches it case-insensitively, binds it to that person's platform `sub` at most once per deployment, and publishes the directory event with `bootstrap_admin: true`; the authorization member grants its administrator role on that event. `BOOTSTRAP_ADMIN_LOGIN` replaces the former `BOOTSTRAP_ADMIN_SUB`.

**Directory events.** `infra.iam.user.created.v1`, `.updated.v1`, `.disabled.v1`, `.deleted.v1` (deleted is new). The payload carries at least `sub`, `display_name`, `email`, `phone`, `locale`, `im_accounts`, `status`. How a member learns of changes is its own business: Casdoor by webhook, Keycloak by polling admin events, the generic member by SCIM 2.0 inbound (`/scim/v2/Users`, `/scim/v2/Groups`).

**System RPC** (`infra.iam.v1.IamProvider`, reached through `IAM_GRPC_URL`; absent, the reads degrade): `BatchGetUsers` (sub list → display data) and `ListUsers` (core); `ListDepartments` and `ListMemberships` (capability `directory_departments`). There is no `GetTenantFeatures`: the installed components (today's `enabled_components`), keys and capabilities move to the authorization provider's authenticated `GET /api/me/access` ([20-authorization-provider.md](20-authorization-provider.md)); the public `/api/tenant/features` keeps only the login page's fields.

**Capabilities**, so the login page degrades by what the member declares: `password_login`, `social_cn` (DingTalk, WeCom, Feishu), `ldap`, `saml`, `scim_inbound`, `mfa`, `token_exchange_delegation`, `service_accounts`.

**Reserved, not built**: service accounts (`sub: svc:<id>` through client credentials, the extension point of the system plane, see [14-system-rpc.md](14-system-rpc.md)); token exchange for delegation (`act`, `ceil`, `dg`), with no branch for agents.

**Configuration.** Shared keys in `config/vars.yaml` (decided): `IAM_URL: $endpoint:infra/iam-casdoor` (the REST base; the JWKS is `{IAM_URL}/.well-known/jwks.json`), `IAM_GRPC_URL: $endpoint:infra/iam-casdoor:grpc` (its port named `grpc`), `IAM_ISSUER` (`urn:be:<TENANT_ID>:iam`), `TENANT_ID`, `BOOTSTRAP_ADMIN_LOGIN`. `IAM_JWKS_URL` retires: it was a second address for the same member. The member hands Casdoor its own webhook address as `$endpoint:infra/iam-casdoor/api/iam/webhooks/casdoor`, a reference to itself. Server metadata (RFC 8414 shape) is at `{IAM_URL}/.well-known/oauth-authorization-server`, relative to `IAM_URL` because the issuer is a name, not a URL. The IdP server (Casdoor, Keycloak) is infrastructure started by `make up`, not a component ([0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)), and logs in to its own schema with its own role, never as `postgres`.

## Alternatives

| IdP | Language, footprint | Licence | Standards | China ecosystem | Fits |
|---|---|---|---|---|---|
| **Casdoor** (default member) | Go, light | Apache-2.0 | OIDC, OAuth 2, SAML, LDAP; webhooks | DingTalk, WeCom, Feishu and WeChat login built in | small and medium customers in China |
| **Keycloak** (second member) | Java, about 0.5–1 GB of memory | Apache-2.0, CNCF | the widest: OIDC, SAML, LDAP / AD federation, standard token exchange (26.2 and later) | community plugins | large enterprises, customers with AD |
| Zitadel | Go | AGPL-3.0 from v3 | OIDC, SAML, multi-tenant organisations | weak | needs a licence review |
| Authentik | Python | MIT core | OIDC, SAML, LDAP outpost, SCIM out | weak | mid-sized, operations-friendly |
| Ory (Kratos + Hydra + Keto) | Go, several services | Apache-2.0 | headless: the login UI is ours to build | none | fully custom login |
| Logto | TypeScript | MPL-2.0 | OIDC, organisations first-class | weak | SaaS developer experience |
| The customer's own IdP (Entra ID, Okta, DingTalk unified identity) | — | — | OIDC + SCIM 2.0 | DingTalk speaks OIDC | enterprise customers, through the generic member |

Two architectural alternatives were also weighed: components verifying the IdP's token directly, and using the IdP's subject as the platform `sub`.

## Why this choice

- Changing IdP touches no business data: `sub` belongs to the platform, the token shape belongs to the family contract.
- Domestic social login comes with Casdoor; enterprise federation with Keycloak; a customer's own IdP with the generic member. One contract, three real scenarios.
- Standards only (discovery, PKCE, RFC 8693, SCIM) means the frontend and every component are written once.
- Local verification against JWKS keeps IAM off the request path ([0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)).

## Why not the others

- **Verifying the IdP's token in components**: roles and department claims would depend on each IdP's claim format, and every component would change with the IdP.
- **The IdP's subject as `sub`**: switching IdP rewrites every `owner_id`, assignment and audit row.
- **Zitadel**: AGPL from v3, and what it would prove is already proved by Keycloak.
- **Authentik, Logto**: weaker in the domestic ecosystem and they prove nothing Keycloak does not. **Ory**: headless, so the login UI would become ours to build and maintain.

## When to switch

| Member | Choose when |
|---|---|
| `infra/iam-casdoor` | the default: small and medium customers, domestic social login, one machine |
| `infra/iam-keycloak` | Active Directory or LDAP federation, SAML, a large enterprise; budget the JVM's memory on a single machine |
| generic OIDC + SCIM member | the customer already runs Entra ID, Okta or DingTalk unified identity and pushes users by SCIM |

## How to switch

1. Export the identity links from the old member (NDJSON) and import them into the new one, linking the new IdP's subjects to the existing platform `sub` values.
2. `brickkit add` the new member and `brickkit remove` the old one; no component changes its dependencies.
3. Change the member ID in `IAM_URL` and `IAM_GRPC_URL` in `config/vars.yaml` (`$endpoint:infra/iam-keycloak`, `$endpoint:infra/iam-keycloak:grpc`). `IAM_ISSUER` names the platform, not the IdP, and stays the same.
4. People sign in again: tokens signed by the old member's key stop verifying once its key is gone from the JWKS.
5. Run `iamconf` against the new member. The frontend does not change; it only reads discovery.

Today, before the platform `sub` exists, a switch means re-issuing tokens plus a `db-reset` of seed and test data; the cost grows with real data, which is why the platform `sub` lands first.

## Conformance tests

Suite `tools/be-acceptance/conformance/iam/` (`iamconf`). The suite brings its own test OIDC provider that issues ID tokens; the member under test is configured to federate to it, or runs against a real IdP container.

- discovery fields complete; token exchange accepts the RFC 8693 shape;
- issued tokens carry `iss`, `aud`, `jti`, `typ`, `tenant_id`;
- a refresh token used as an access token is rejected; a rotated refresh token is invalid at once;
- during a key rotation, tokens signed by the current and the previous key both verify;
- the same IdP account signing in twice gets the same `sub`; export then import of identity links keeps every `sub`;
- a disabled user's event is published within a bounded time and the next login is refused;
- an undeclared capability degrades explicitly.

SDK side, in every official SDK: reject `typ: refresh`; enforce the `alg` allowlist; check `iss` and `aud`. Frontend (FE-1): the login flow works against a non-Casdoor discovery document.

## Decision records

- [0203 The token carries identity only, and the platform owns `sub`](../02-decisions/02-permissions/0203-jwt-carries-identity-only.md): the token claims and the platform-owned `sub`.
- [0308 A tenant is a deployment](../02-decisions/03-contracts-and-data/0308-tenant-is-the-deployment.md): the tenant is the deployment: `aud` is `TENANT_ID`, `tenant_id` is reserved on the wire.
- [0107 Family addresses are `$endpoint:` references in shared variables](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md): `IAM_URL`, `IAM_GRPC_URL`, `IAM_ISSUER` and `TENANT_ID` are shared variables; the iam → authz edge is removed.
- [0210 Delegation and impersonation](../02-decisions/02-permissions/0210-delegation-and-impersonation.md): the token side of delegation, reserved for agents.
- [0104 A slot family needs several reasonable implementations and no dependency edge](../02-decisions/01-architecture/0104-variants-become-slot-families.md): `slot:iam`.
- [0106 Infrastructure is not a component](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md): the IdP servers.
- [0303 No test accounts in migrations](../02-decisions/03-contracts-and-data/0303-no-test-accounts-in-migrations.md): the first administrator comes from `BOOTSTRAP_ADMIN_LOGIN`, never from a migration or a seed.

## Known limits

- Revoking a person takes effect through the bundle's `stale_since` (about 15 s) or token expiry (600 s), not instantly.
- The generic OIDC + SCIM member does not exist yet; until then a customer's own IdP is federated through Keycloak.
- Chinese commercial cryptography (SM2 signing) is a listed capability only, built when a customer requires it.
- Keycloak is a JVM: on a single machine it costs noticeably more memory than Casdoor.
