[English](20-authorization-provider.md) · [中文](../../zh/04-foundations/20-authorization-provider.md)

# Authorization provider

What decides who may do what and on which records, the two contracts behind it, and the slot family that can sit behind those contracts. For whoever adds a permission key, makes a list show only some rows, adds sharing, or wants to swap the authorization implementation.

## Scope

Two kinds of permission, plus what grows out of the second:

| | Name here | Carrier | Answers | Standard name |
|---|---|---|---|---|
| Functional permission | permission key (`erp.sales.confirm`) | RBAC: keys in roles, roles granted to people | may this person call this action at all? | function-level authorization (OWASP BFLA) |
| Data permission | data scope | RBAC assignment (a level and dimension values per role and key) combined with fixed attribute filtering (the columns each component declares in its version: `owner_id`, `dept_path`, `warehouse_id`, `legal_entity_id`) | on which rows? | object-level authorization (OWASP BOLA) |

On top of data permission: **record sharing** (this one record, to this person, role or department, optionally until a date), **relation-derived access** (team members, project members, the assignee of an open task), **delegation** (A's approvals handled by B for a week), **field-level permission** (cost and price columns), **time-limited grants**, and **audit and explain** ("why can't I see this").

Not authorization, and kept in component code: business invariants ("only a draft can be repriced") and separation of duties ("the creator cannot approve their own order"). Token issuance and the user directory are in [21-identity-provider.md](21-identity-provider.md).

## Choice

**One formula.** For a person P, a key K and a row r:

```
visible(P, K, r) =   rule(P, K, r)      -- level x dimensions: owner/org OR'ed, resource dimensions AND'ed
                   OR shared(P, r)      -- a direct grant on this record
                   OR derived(P, r)     -- one hop: team, project, open task
effective(P)     = union of P's own grants, intersected with each ceiling on a delegation chain
field(P, K, r)   = visible(P, K, r) AND P holds the field key
every grant carries [valid_from, valid_until), evaluated at read time
```

Inside one person it stays a pure union with no Deny ([0204](../02-decisions/02-permissions/0204-permissions-are-a-pure-union.md)); only a delegation chain intersects, like a permission boundary. Two properties are part of the contract: grants only ever widen what is visible, and **List/Can consistency**: a row is in a list for key K if and only if a single-record check for K says visible.

- **Two contracts.** The **provider contract** `infra.authz.v2`, implemented by every member of the authz slot, and the **resource contract**, mounted by the SDK in every component that declares resources. Rule attributes stay in the component that owns the row; authz holds only explicit grants and relations.
- **Decisions stay local.** Keys, levels, values, fields and ceilings come in the bundle; direct grants come into a projection table in the component's own schema; a list is one static parameterised SQL predicate. A request reaches the provider only for a declared graph type or when the projection is behind a consistency token.
- **The family**, all built in phase 06, in this order: `infra/authz` (native, default) → `infra/authz-static` (file, no database) → `infra/authz-openfga` (ReBAC). Cedar or OPA only on a real ABAC need, and only for actions. The family contract lives in its own repository, `contract-infra-authz` (checked out at `contracts/infra/authz`): the proto, the REST and event contracts, the error reasons, the meaning of a bundle (`EVALUATION.md`) and the decision vectors that lock it.
- **No component depends on a member.** Every call goes to the shared address `AUTHZ_URL`; the dependency edge from `infra/iam-casdoor` to `infra/authz` is removed.
- **Levels**: `own`, `dept` (the department only, without sub-departments), `subtree`, `all`; a custom set of department subtrees is a value of the `org` dimension.
- **Answers already settled**: sharing a record can carry the view right for that record but never an action key (confirm, cancel, close need a role key; each relation declares what it grants); sharing requires the type's share key and at least the level being granted; a record the caller cannot see answers `404` to reads and commands alike, and `403` only when it is visible but the action is not allowed (`OUT_OF_SCOPE` when the caller holds the action's key but this record is outside that key's scope, `MISSING_PERMISSION` when the caller does not hold the key); read-only impersonation in production needs `infra.authz.impersonate`, logs the `act` chain and notifies the person viewed.
- **AI agents are reserved, not built**: `act.kind` admits `agent`, the bundle capability `agents` defaults to `false`, the profile and ceiling shapes are fixed, permission keys accept an optional `delegable` field that nothing fills or reads yet. Enabling them later only adds.

**Status**: in place: `infra/authz` 2.0.x serves a v1 bundle (roles → keys, `stale_since`) at `/authz/bundle`, each component filters rows with its own scope code, and inventory and finance keep their own access tables. Decided: everything else in this document, the v2 design, landing with the 3.0.0 sweep, with `infra/authz-static` and `infra/authz-openfga` built in phase 06.

## Port contract

**Addressing.** The shared key `AUTHZ_URL` (in `config/vars.yaml`) is the base URL of the installed member, by the member's own service name ([0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)). It replaces `AUTHZ_BUNDLE_URL`, which the 3.0.0 sweep removes; there is no transition period.

**Identity claims** (issued by the IAM member, see [21-identity-provider.md](21-identity-provider.md); still not one key in a token, [0203](../02-decisions/02-permissions/0203-jwt-carries-identity-only.md)): `sub`, `typ`, `roles[]`, `dept_path`, `tenant_id` (`org_id` deprecated), `act` (`{sub, kind: user|agent|svc}`, nestable), `ceil[]` (ceiling profile codes), `dg` (delegation grant id), `azp`.

**Bundle v2.** `GET {AUTHZ_URL}/authz/v2/bundle`, conditional on `ETag`, polled every 15 s and on every poke:

```json
{ "contract": "authz/2.0", "revision": "18234",
  "capabilities": { "core": true, "admin_write": true, "sharing": true, "relation_sync": true, "check": true,
                    "graph": false, "list_objects": { "max_results": 1000 }, "delegation": true,
                    "agents": false, "impersonation": false, "access_review": true,
                    "explain_paths": true, "conditions": false },
  "roles":  { "dev_sales_rep": ["erp.sales.view", "erp.sales.cancel", "erp.sales.pricing.read"] },
  "grants": { "dev_sales_rep": { "levels": { "erp.sales.view": "subtree", "erp.sales.cancel": "own" } },
              "dev_east_mgr":  { "levels": { "erp.sales.view": "subtree" }, "values": { "org": ["/1/3/", "/1/7/"] } },
              "dev_wh_south":  { "values": { "warehouse": ["7"] }, "until": 1760000000 } },
  "profiles": {}, "delegations": [], "stale_since": { "u_123": 1759400000 },
  "revoked_grants": {}, "catalog_digest": "sha256:…" }
```

- Several roles give a key: the highest level wins; a key granted without a level is `own`. Values are unioned per key; `*` means all and is only ever granted explicitly.
- `until` is evaluated locally against the clock; expiry needs no event.
- A bundle whose `contract` is missing or not `authz/2.*` is refused and logged at ERROR; there is no v1 fallback.
- Unknown fields and unknown capability names are ignored.

**Provider service** `infra.authz.v2.AuthzProvider` (gRPC, the system plane, see [14-system-rpc.md](14-system-rpc.md)): `ResolveClaims` (iam at login and refresh), `GetBundle`, `ReadChanges` and `ReadTuples` (changefeed and snapshot), `WriteTuples` (idempotency key, actor, source component; returns the revision), `Check` and `BatchCheck` (≤ 500 items), `ListObjects` (capability `graph`, capped), `Explain`, `CreateDelegation`, `RevokeDelegation`.

**Tuples.** `{object: {type, id}, relation, subject, expires_at}`, subject one of `user:<sub>`, `role:<code>`, `dept:<path>`, `dept_tree:<path>`. Two sources:

| | Owned by authz | Owned by a component |
|---|---|---|
| What | shares, delegations | business relations: opportunity team, project members, the assignee's temporary viewer on a document |
| Written by | the owning component's `_shares` endpoint, which checks eligibility locally, then calls `WriteTuples` | the business transaction, through the outbox, subject `infra.authz.relation.sync.v1`, replacing the group for (type, id, relation, source) with a monotonic version |
| Accepted when | type and relation are in the catalogue and the writer's `be-caller` is the type's owner | the source is the registered owner and the version is newer |
| Admin may edit | yes (revoke, review) | no, read-only |

**Changefeed.** `GET {AUTHZ_URL}/authz/v2/changes?types=…&after=<revision>&limit=500` → `{changes: [{revision, op: upsert|delete, tuple}], next, watermark}`. An `after` the member cannot serve (older than its retention, or a revision it never issued, as after a switch of member) answers `410`; the SDK then rebuilds from `ReadTuples` and continues from the snapshot's revision. The poke `infra.authz.changed.v1` (core NATS, revision only, loss harmless) triggers an immediate pull.

**Consistency token.** `revision` is a monotonic int64 sent as a decimal string. A write returns it; the owning `_shares` waits for its own projection to reach it before answering. A request may carry `X-Authz-Revision: N`: projection at N or later → answer; behind → pull once, budget 300 ms; still behind → single reads fall back to provider `Check` with `at_least = N`, lists answer with `X-Authz-Consistency: stale`.

**Capabilities.** Core, which every member implements: claims, keys, levels, dimension values, field keys, stale, revision, catalogue sync, `/api/me/access`, basic explain, time-limited grants. Optional: `admin_write`, `sharing`, `relation_sync`, `check`, `graph`, `delegation`, `agents`, `impersonation`, `access_review`, `explain_paths`, `conditions`. A missing capability degrades explicitly:

| Missing | Backend | Frontend |
|---|---|---|
| `admin_write` | admin writes answer `501` | admin pages read-only, with a banner |
| `sharing` | `_shares` answers `501` with reason `CAPABILITY_UNAVAILABLE` and `metadata.capability = sharing` ([15](15-user-api-and-errors.md)); the projection stays empty | share entry points hidden |
| `check` | a single read behind the token answers not visible plus stale, no fallback | "try again shortly" |
| `graph` | graph ids empty, header `X-Authz-Degraded: graph` | notice |
| `delegation`, `agents`, `impersonation` | tokens carrying `ceil` or `dg` answer `401 UNSUPPORTED_DELEGATION` | entry points hidden |

A component lists `requires_capabilities` in `assembly.yaml`, a member lists `provides_capabilities`; gate `authz-capability-scan` fails at assembly when one is not a subset of the other.

**Resource contract** (REST, mounted by the SDK in each component that declares `resources`; `{prefix}` is `/{domain}/{name}`):

| Endpoint | Answers |
|---|---|
| `POST {prefix}/_authz/check` `{checks: [{key, type, id}]}` (≤ 500) | `{results: [{visible, allowed, reason}]}`: rule, share, relation, delegation and ceiling combined |
| `GET {prefix}/_authz/explain?key=&type=&id=` | `{decision, reasons: [{kind, source, detail}], missing: [...]}`; to the caller only their own side of the facts; full answer with `infra.authz.audit` |
| `GET {prefix}/_shares/{type}/{id}` | the record's shares; `404` when not visible |
| `POST {prefix}/_shares/{type}/{id}` `{subject, relation, expires_at?, idempotency_key}` | `{share, revision}`; `403 SHARE_NOT_ALLOWED`; `501 CAPABILITY_UNAVAILABLE` |
| `DELETE {prefix}/_shares/{type}/{id}/{share_id}` | `{revision}` |

Cross-component parents (attachments of an order, a task about a document) check the parent once through its `_authz/check` and then list the children; listing "all attachments I may see" across parents is not supported.

**Projection** (SDK platform migration, only in components that declare `resources`):

```sql
CREATE TABLE besdk_authz_acl (
    rtype TEXT NOT NULL, rid TEXT NOT NULL, relation TEXT NOT NULL, subject TEXT NOT NULL,
    expires_at TIMESTAMPTZ, revision BIGINT NOT NULL,
    PRIMARY KEY (rtype, rid, relation, subject));
CREATE INDEX besdk_authz_acl_subject ON besdk_authz_acl (rtype, subject, relation);
CREATE TABLE besdk_authz_cursor (scope TEXT PRIMARY KEY, revision BIGINT NOT NULL, rebuilt_at TIMESTAMPTZ);
```

**Subject set and the canonical predicate.** The SDK computes, per request, `S(P) = {user:<sub>} ∪ {role:<r>} ∪ {dept:<dept_path>} ∪ {dept_tree:<each ancestor of dept_path and itself>} ∪ S(each delegator whose on-behalf delegation covers this key)`. A person with no department contributes no `dept` entries, so empty arrays match nothing (fail-closed). Every list query carries the same predicate, all parameters from the SDK:

```sql
AND (
      ( @s_all OR o.owner_id = ANY(@s_owners) OR o.dept_path = ANY(@s_dept_exact)
        OR o.dept_path LIKE ANY(@s_dept_prefix) )
        -- a component with a resource dimension ANDs: (@s_wh_all OR o.warehouse_id = ANY(@s_wh_ids))
   OR ( @s_acl AND EXISTS (SELECT 1 FROM besdk_authz_acl a
          WHERE a.rtype = 'erp.sales.order' AND a.rid = o.id::text
            AND a.relation = ANY(@s_relations) AND a.subject = ANY(@s_subjects)
            AND (a.expires_at IS NULL OR a.expires_at > now())) )
   OR o.id::text = ANY(@s_graph_ids)        -- graph types only; otherwise an empty array
)
```

The SDK also offers the three branches separately so a slow query can be rewritten as `UNION ALL` merged on the same cursor; the semantics do not change. How a component writes this is in [02-backend.md](../01-conventions/02-backend.md#data-scopes).

**Declarations** in `assembly.yaml`, next to `data_scopes`: `permissions` entries gain `type: page|action|field` and the optional, unused `delegable`; a new `resources` block names each type (`<domain>.<name>.<aggregate>`, one owner, recorded in the append-only `registry/resource-types.tsv`), its table, its `view_key` (the key that decides whether a record of the type is visible at all, for lists and single reads; required), its keys, relations (`viewer: {grants: [...]}`, `editor: {includes: [viewer], grants: [...]}`, component-owned ones marked `owned_by: component`), its share rule (key, relations, subject kinds), field sets (columns, read key, edit key), one-hop `inherits`, and `derivation: direct|graph`. be-ops validates them and generates per-language constants for keys and types; gate `authzgen-fresh` fails when they are stale.

**Field-level permission.** A field key is a permission key of `type: field`. The owning component sets masked fields to `null` and lists them in `_masked`; a write to a masked field answers `403 FIELD_FORBIDDEN`; sorting, filtering or aggregating by a masked field is refused. Events are a system plane and are never shown to people unmasked.

**Events published by authz** (outbox, additive only): `infra.authz.tuple.changed.v1`, `infra.authz.scope_grant.changed.v1`, `infra.authz.delegation.changed.v1`, `infra.authz.role.changed.v1`, `infra.authz.user_role.changed.v1` (each with the actor and its `act` chain), and the poke `infra.authz.changed.v1`.

**Admin and self-service REST** (through the gateway; the admin UI is generated from the family contract only): roles, keys with levels, dimension values; profiles; `/api/me/delegations`, `/api/admin/delegations`; `/api/me/shares?direction=by_me|with_me`, `/api/admin/shares`; `/api/admin/keys/{key}/holders`, `/api/admin/access-review?type=&id=`; and `GET /api/me/access`, one answer with `sub`, `act`, department, installed components, capabilities, keys with levels, values, fields, ceilings, delegations to me and the revision. It replaces the separate features and permissions calls.

**Status codes.** `401 TOKEN_STALE` when the bundle marks the token stale (silent refresh follows); `503 AUTHZ_NOT_READY` before the first bundle arrives (`/healthz` stays green); `404 NOT_FOUND` when not visible, decided by the type's `view_key`; `403` when visible but not allowed: `OUT_OF_SCOPE` when the caller holds the route key but this record is outside that key's scope, `MISSING_PERMISSION` when the caller does not hold it ([15](15-user-api-and-errors.md#status-codes-for-access)).

**Error domain.** A reason a member raises in its own name uses the family's ID, `domain: infra/authz`, whichever member is installed, and is listed in the family contract's `errors.yaml`; this is the slot-family exception to "`domain` is the component ID" ([15](15-user-api-and-errors.md#the-error-body)), so the frontend keeps one table per family.

## Alternatives

| Model | Examples | Strengths | Weaknesses for this project |
|---|---|---|---|
| RBAC with levels and dimension values | RuoYi data scope, Dynamics privilege depth, ERPNext user permissions, SAP organisational fields | what ERP users already know; one SQL predicate per list | no sharing or relations on its own |
| ReBAC (Zanzibar family) | OpenFGA, SpiceDB | sharing, nesting, graph depth; standard consistency tokens | every row's owner and department would have to be written as tuples; `ListObjects` per list is the most expensive call |
| Policy language | Cedar, OPA | expressive conditions (amounts, time, IP) | conditions on visibility need partial evaluation into SQL, immature in both |
| Static file | a policy YAML | no database, trivial to run | no sharing, no admin UI |
| Database row-level security | PostgreSQL RLS | enforced below the application | session settings on pooled and shared connections, merging into shells, no explanation ([0206](../02-decisions/02-permissions/0206-no-row-level-security.md)) |
| Per-component access tables | today's inventory and finance | local and simple | scattered, no single "what can this person see", no audit |

## Why this choice

- It keeps three properties at once: the hot path never crosses the network ([0202](../02-decisions/02-permissions/0202-local-permission-bundle.md)), every component still runs alone, and a shell only merges processes.
- Attributes stay with the owner of the row and explicit grants stay in authz, so no business write needs a synchronous authz call and nothing is written twice.
- Only direct tuples are materialised; the subject side (roles, department ancestors, delegators) is expanded per request. Moving a person to another department changes a token, not a single projection row, so there is no recalculation storm.
- Any model fits behind the two contracts, and a missing capability is a visible, tested behaviour. It covers what RuoYi, ERPNext, Odoo, Salesforce and Dynamics offer for ERP access, and delegation and field-level permission besides.

## Why not the others

- **`ListObjects` on every list**: one network round trip per list, id sets of tens of thousands for people in large teams, cursor paging over the whole set, and a list that fails when authz is down.
- **Writing every row's attributes as tuples**: two or three tuple writes per business document, a dual-write consistency problem, and authz in the synchronous path of every write.
- **Policy conditions on visibility**: List/Can consistency would require translating policies into SQL; conditions are allowed on actions only.
- **Row-level security, per-component tables, Deny rules**: rejected in [0206](../02-decisions/02-permissions/0206-no-row-level-security.md) and [0204](../02-decisions/02-permissions/0204-permissions-are-a-pure-union.md); per-component tables are deleted from inventory and finance.

## When to switch

| Member | Fits | Proves |
|---|---|---|
| `infra/authz` (native, default) | almost every ERP / CRM customer; all capabilities except `graph`, one-hop derivation | the full contract on one PostgreSQL with no new base service |
| `infra/authz-static` | up to about ten users, demos, edge or offline sites, test fixtures; core only, policy file `AUTHZ_POLICY_FILE` | replaceability without touching frontend or SDK, and explicit degradation |
| `infra/authz-openfga` | collaboration-heavy customers: projects, folders, nested teams, cross-organisation sharing; adds `graph`, `list_objects`, Expand and ListUsers | ReBAC behind the same contract; consistency tokens map onto OpenFGA's consistency parameter. OpenFGA itself is infrastructure ([0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)) |
| Cedar or OPA (not built) | a customer with real ABAC rules on actions | policy languages fit behind the contract, actions only |

## How to switch

1. Install the new member and remove the old one with `brickkit add` / `brickkit remove`; no component changes its dependencies, because none depends on a member.
2. Point `AUTHZ_URL` in `config/vars.yaml` at the new member's own service name.
3. Run `make gates`: `authz-capability-scan` fails if an installed component requires a capability the new member does not provide.
4. Export the assignments (roles, levels, dimension values, shares, delegations) from the old member as NDJSON and import them into the new one, in the format the family contract `contract-infra-authz` defines; it is the same pattern as the identity-link export in [21](21-identity-provider.md#how-to-switch). Importing into `infra/authz-static` writes its policy file. The components' projections rebuild themselves from `ReadTuples` when the new member answers `410`.
5. Run the conformance suite against the new member before going live.

## Conformance tests

Suite `tools/be-acceptance/conformance/authz/` (`authzconf`), three layers; the decision vectors are not stored in the suite but read from `vectors/decision/` of the family contract repository, where they are canonical (`contracts/infra/authz`, pinned by tag). be-protocol holds only protocol-wide vectors and cites the family's `EVALUATION.md` by tag:

| Layer | Content | Asserts |
|---|---|---|
| Decision vectors `vectors/decision/*.json` (family repository) | bundle, claims, route key, row attributes, ACL rows, time, revision → decision, predicate parameters, subject set, field mask, reasons | every official SDK computes identical results: highest level, per-key evaluation, subject expansion, no department → empty arrays, delegation merge, ceiling intersection, expiry, a bundle without `contract: authz/2.*` refused |
| Provider black box `provider/` | the suite signs its own test tokens; the member is seeded with a fixture catalogue | core must pass; each declared optional capability must pass; each undeclared one must answer `501 CAPABILITY_UNAVAILABLE` with its name; an NDJSON export imported into another member gives the same decisions |
| End to end `e2e/` | the fixture component `conformance/widget` (resource type `conformance.widget.widget`), built with the real SDK, run against each member; randomised roles, levels, values, shares, delegations, expiry | List/Can consistency; visible immediately after sharing with the revision; gone after revocation and expiry; masked fields `null` and listed; sort by masked field refused |

The output is a capability matrix (member × capability × pass / degraded correctly / fail). The in-process fake provider used by component tests must pass core too, so the fixture cannot drift from the real members.

## Decision records

- [0209 Authorization is a slot family](../02-decisions/02-permissions/0209-authz-is-a-slot-family.md): this document is its full analysis: the family, its two contracts, capabilities and the suite.
- [0202 Permissions are decided locally](../02-decisions/02-permissions/0202-local-permission-bundle.md): decisions stay local, against the bundle and the projection.
- [0203 The token carries identity only, and the platform owns `sub`](../02-decisions/02-permissions/0203-jwt-carries-identity-only.md): the identity claims, never a key.
- [0204 Permissions are a pure union, with no Deny](../02-decisions/02-permissions/0204-permissions-are-a-pure-union.md): a pure union inside one principal; intersection only along a delegation chain.
- [0205 Data-scope rules ship with the version](../02-decisions/02-permissions/0205-data-scopes-ship-with-the-version.md) and [0207 Data-scope assignments live in authz](../02-decisions/02-permissions/0207-scope-assignments-live-in-authz.md): rules ship with the version; assignments live in authz.
- [0206 No row-level security; one sharing engine, in authz](../02-decisions/02-permissions/0206-no-row-level-security.md): no row-level security; one sharing engine, projected by the SDK.
- [0210 Delegation and impersonation](../02-decisions/02-permissions/0210-delegation-and-impersonation.md): delegation, impersonation, agents reserved.
- [0211 Field-level permission is a key](../02-decisions/02-permissions/0211-field-level-permissions.md): field-level permission.
- [0212 A record the caller cannot see answers 404](../02-decisions/02-permissions/0212-invisible-records-answer-404.md): 404 for records the caller cannot see.
- [0101 Components never import each other](../02-decisions/01-architecture/0101-no-imports-between-components.md): the family contract package is a third kind of package that crosses boundaries.
- [0104 A slot family needs several reasonable implementations and no dependency edge](../02-decisions/01-architecture/0104-variants-become-slot-families.md): `slot:authz`.
- [0107 Authorization and identity are reached through shared variables](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md): everything through `AUTHZ_URL`, no edge to any member.

## Known limits

- The projection is eventually consistent: about 0.1 s with the poke, up to 5 s without; the consistency token closes the gap for the writer and for links that carry it.
- The native member derives one hop only; deeper graphs need `infra/authz-openfga`, and its lists are capped (`RESOURCE_EXHAUSTED` beyond the cap).
- No list filtering across parents; children are checked through their parent.
- An import into a member that lacks a capability (`infra/authz-static` has no `sharing`) reports every row it cannot hold and stops; it never drops rows silently.
- Bundle size grows with roles, profiles and active delegations, not with people or records.
- Agents and service accounts are shapes in the contract only.
