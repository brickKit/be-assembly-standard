[English](07-tenancy.md) · [中文](../../zh/04-foundations/07-tenancy.md)

# Tenancy

What a tenant is in this project, how one tenant's data is kept apart from another's, how several companies inside one customer are represented, and what tokens and events carry so that a later change of model stays additive. Read it before adding a column that identifies a company or a customer, before proposing a multi-tenant SaaS offer, or before changing how tokens are checked for their audience.

## Scope

- **In:** the definition of tenant and legal entity; tenant = deployment; what each deployment owns; the legal-entity column, its events and its data-scope dimension; the tenant fields in tokens and the keys that check them; the fields reserved for a pooled model; noisy neighbours inside one deployment; operating many tenants.
- **Out:** how tokens are verified in full ([21-identity-provider.md](21-identity-provider.md)); a legal entity's business time zone and fiscal calendar ([05-time-and-calendars.md](05-time-and-calendars.md)); document numbers scoped per legal entity ([04-identifiers-and-numbering.md](04-identifiers-and-numbering.md)); how a data-scope dimension is evaluated ([20-authorization-provider.md](20-authorization-provider.md)); event headers ([13-event-contracts.md](13-event-contracts.md)); retention per tenant ([09-data-lifecycle.md](09-data-lifecycle.md)).

**Terms.** A **tenant** is a customer whose data no other customer may ever see. A **legal entity** is a company inside one customer: legal entities share master data and may trade with each other, but each one has its own books, numbering and calendar.

## Choice

- **One tenant is one deployment** (the "silo" model): one brickKit project instance with its own database, NATS, buckets and identity-provider organisation (or its own identity provider). No table has a `tenant_id` column.
- **Several companies inside a tenant are legal entities, a row dimension.** Every transaction-document table carries `legal_entity_id TEXT NOT NULL`, and so do warehouses. Master data (customers, products) is shared across the tenant's legal entities by default.
- **Legal entities are master data owned by mdm/org**, a new component built in this round before the other components move to 3.0.0. There is no transitional shared variable listing legal entities.
- **Every transactional event carries its legal entity**, in the payload and the `ce-legalentity` header. A consumer dead-letters such an event without one; it never books it into a `default` entity.
- **`legal_entity` is a data-scope dimension**: roles are given legal-entity values, and list queries filter by them ([20](20-authorization-provider.md)).
- **Tokens name the deployment**: `aud` must contain `TENANT_ID`, `iss` must equal `IAM_ISSUER`, and the `tenant_id` claim is set (`org_id` is deprecated). A token signed for one deployment is refused by another, even when both use the same identity provider.
- **The pooled model is reserved, not built**: the `ce-tenantid` event header and `tenant_key` in `lifecycle.yaml` exist and stay unset.

**Status**: decided; lands with the 3.0.0 sweep (legal-entity columns, events, `TENANT_ID` and `IAM_ISSUER` checks, mdm/org). Today there is one tenant and one legal entity: the token's `org_id` is a constant, only erp/finance has a `legal_entity_id` column and it defaults to `'default'` when an event lacks one, and no SDK checks `aud` or `iss`. The seed data gains a second legal entity, 「本地测试」华南子公司, with the sweep, so the dimension has real data to test against ([05-data.md](../01-conventions/05-data.md)).

## Port contract

### Tenant identity

| Item | Where | Value | Rule |
|---|---|---|---|
| `TENANT_ID` | shared key in `config/vars.yaml`, referenced as `$var:TENANT_ID` by every component with protected routes | the deployment's tenant identifier | required; it is the expected `aud` |
| `IAM_ISSUER` | shared key | the IAM member's issuer URL | required; the expected `iss` |
| `aud` claim | every access token | contains `TENANT_ID` | a token without it is answered `401` |
| `tenant_id` claim | every access token | equals `TENANT_ID` | read by components that log or audit the tenant; `org_id` is deprecated |
| `ce-tenantid` | event header | not set | reserved for a pooled model ([13](13-event-contracts.md)) |
| `tenant_key` | `lifecycle.yaml` | `none` | reserved: in a pooled model it names the tenant column ([09](09-data-lifecycle.md)) |

### What a deployment owns

| Resource | Per tenant | Shared between tenants |
|---|---|---|
| PostgreSQL | its own database (or server); roles created by its own `make db-init` | never |
| NATS | its own server or account; streams `BE_*` are per deployment | never |
| Object storage | its own buckets, one per component ([22](22-object-storage.md)) | never |
| Identity | its own IdP organisation or IdP; its own `IAM_ISSUER` and signing keys | an IdP server may be shared; tokens still cannot cross, because of `aud` |
| Edge | its own hostname and routes | — |
| Secrets | its own `.secrets/` or secret store | never |

### Legal entity

- **Column**: `legal_entity_id TEXT NOT NULL`, the legal entity's id in mdm/org, stored as a reference in text ([04](04-identifiers-and-numbering.md)). No default value.
- **Tables that carry it**: transaction documents and everything posted from them: sales orders, stock movements and reservations, opportunities, workflow tasks that reference a document, journal entries, receivable and payable ledgers. Warehouses carry it as their owner.
- **Tables that do not**: master data is tenant-wide by default. A component that needs "this customer is only for company A" adds an association table of its own; the master table does not change.
- **Uniqueness and numbering**: document numbers are unique per legal entity, `UNIQUE (legal_entity_id, <number column>)`, and numbered per legal entity and period ([04](04-identifiers-and-numbering.md)).
- **Events**: the payload has `legal_entity_id`; the runtime copies it into the `ce-legalentity` header ([13](13-event-contracts.md)). Missing on a transactional event: the consumer sends the message to the dead-letter subject.
- **Data scope**: dimension `legal_entity`. Values are assigned per role and key in the authorization provider and travel in the bundle; a component's list predicate ANDs it like any other resource dimension ([20](20-authorization-provider.md)). Cross-entity aggregates (credit exposure, for example) are computed per legal entity, never summed across entities the caller cannot see.
- **Attributes a component needs** (code, name, business time zone, fiscal-year start month, functional currency) come from mdm/org. Components keep a local copy through the SDK's snapshot helper and read the calendar through the SDK ([05](05-time-and-calendars.md)).

### Operating many tenants

- A SaaS operator runs one deployment per tenant. On Kubernetes that is one namespace per tenant; on Docker or Podman, one project directory per tenant.
- **One customer is one fork of the project repository.** brickKit has no multi-customer concept and will not get one (it declined that feature request): each customer's fork has its own `brickkit.yaml`, which is that customer's lock file (its own component versions, upgraded customer by customer), its own `config/`, secrets and deploy files, with `TENANT_ID`, `IAM_ISSUER`, database and bus addresses and hostnames in its own `config/vars.yaml`. Changes meant for every customer are made in the upstream repository and merged into each fork with Git.
- Several `-f deploy.<customer>.yaml` files in one repository still work, but they share one `brickkit.yaml` and so one set of versions; that is not the recommended shape.
- Upgrades, backups and restores happen per tenant. One tenant can stay on an older component version while another moves, because each has its own lock file.

### Noisy neighbours inside a tenant

Inside one deployment the neighbours are components, not tenants. They are bounded by: each member's connection budget, `PG_POOL_MAX` ([03](03-database.md)); per-transaction and per-role timeouts ([10](10-local-transactions.md)); stream size limits ([12](12-event-bus.md)); outbound bulkheads ([16](16-deadlines-and-retries.md)); `requests` in each `component.yaml`, turned into Kubernetes requests and limits.

## Alternatives

| Model | Isolation | Cost per tenant | Noisy neighbours | Used by |
|---|---|---|---|---|
| One deployment per tenant (silo, chosen) | strongest; upgrade, back up and restore per tenant | one set of processes (about 1–2 GB of memory for a set of shells) | none between tenants | SAP S/4HANA Cloud (a system per tenant), Dynamics 365 Finance and Operations (a database per environment), Odoo Online (a database per tenant), dedicated private clouds |
| One deployment, a database per tenant | strong | migrations run N times; a pool per database | shared compute | some SaaS products |
| One deployment, a schema per tenant | medium | components × tenants schemas | shared | early Rails SaaS |
| Row-level `tenant_id` (pooled) | weakest, enforced only by code | lowest | severe without quotas | Salesforce (`OrgId`), NetSuite, most small-business SaaS |
| A company column inside a tenant (not an alternative: the complement) | — | — | — | Odoo `company_id`, Dynamics `DataAreaId`, SAP `BUKRS`, ERPNext `company` |

## Why this choice

- **It is how mainstream ERP clouds isolate tenants**, and it matches the main way this product is sold: one private deployment per customer.
- **It needs no code**: one schema per component ([0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)) and "one brickKit project is one deployment" already give one tenant per deployment, and a fork of the project repository per customer gives each tenant its own lock file, configuration and deploy files, kept in step with upstream by Git.
- **Isolation, upgrades, backups and restores are per tenant**, and one tenant's load never slows another.
- **Legal entities now, not later**: group companies are in scope, and adding a column to partitioned transaction tables after they hold data means a backfill and rebuilt unique indexes. Adding it in the 3.0.0 baseline costs nothing.
- **`aud` and `iss` cost one comparison each** and close the one way tenants could leak into each other: two deployments trusting the same signing key.

## Why not the others

- **A database per tenant in one deployment**: one shared pool per process cannot be split across databases, and every migration runs once per tenant inside one deployment's start-up.
- **A schema per tenant**: this project already has a schema per component; per tenant, that multiplies into components × tenants schemas, migrations and roles.
- **Row-level `tenant_id`**: every table, every unique index and every query needs the tenant, and with no row-level security ([0206](../02-decisions/02-permissions/0206-no-row-level-security.md)) only the SDK and the gates would enforce it. Retrofitting it is a major version of every component.

## When to switch

- **A business model with thousands of small tenants**, each too small to pay for its own set of processes: measured as the infrastructure cost per tenant exceeding what the tenant pays. Only then is the pooled model worth evaluating.
- **A customer with many legal entities in different countries**: not a switch; legal entities already cover it, with a zone and currency each.

## How to switch

- **A new tenant**: a new deployment. Fork the project repository, write the tenant's `vars:` (`TENANT_ID`, `IAM_ISSUER`, addresses), run `make db-init` against its database, create its IdP organisation, `brickkit up`. No code or pin changes.
- **A new legal entity**: create it in mdm/org and give roles its value in the authorization provider. No deployment change.
- **To a pooled model**: not a configuration change. It is a major version of every component: declare `tenant_key` in `lifecycle.yaml`; add the tenant column to every table, primary key and unique index; have the SDK's store add the tenant predicate to every statement, with a gate and a suite to prove it; set `ce-tenantid`; take the tenant from the token's `tenant_id`. The fields reserved now keep the wire contracts additive when that happens.

## Conformance tests

- **Component protocol suite** (`tools/be-acceptance/conformance/component/`, [02](02-languages-and-component-protocol.md)): a token with the wrong `aud` gets `401`; a token with the wrong `iss` gets `401`; a transactional event without a legal entity goes to the dead-letter subject; the `scope` profile includes `legal_entity` values.
- **SDK, red first**: verification refuses a token whose `aud` lacks `TENANT_ID`, and one whose `iss` differs from `IAM_ISSUER`.
- **erp/sales**: a created order stores `legal_entity_id` and its event carries it.
- **erp/finance**: an event without a legal entity is refused, never booked to `default`; credit exposure is limited by the caller's `legal_entity` values.
- **be-acceptance**: a transaction-document table without `legal_entity_id` fails a planned scan (the table list comes from `lifecycle.yaml`).
- **Seed data**: two legal entities, and at least one role limited to one of them.

## Decision records

- [0308 A tenant is a deployment; companies are legal entities inside it](../02-decisions/03-contracts-and-data/0308-tenant-is-the-deployment.md): this document carries its analysis.
- [0102 One database, one schema per component](../02-decisions/01-architecture/0102-one-schema-per-component.md): why schemas cannot also be per tenant.
- [0206 No row-level security](../02-decisions/02-permissions/0206-no-row-level-security.md): why a pooled model would rest on the SDK alone.
- [0203 The token carries identity only, and the platform owns `sub`](../02-decisions/02-permissions/0203-jwt-carries-identity-only.md): the `aud`, `iss` and `tenant_id` claims.
- [0107 Family addresses are `$endpoint:` references in shared variables](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md): `IAM_ISSUER` and `TENANT_ID` are shared variables.
- [0205 Data scopes ship with the version](../02-decisions/02-permissions/0205-data-scopes-ship-with-the-version.md): `legal_entity_id` is one of the columns a component declares for its data scopes.
- [0307 Business dates follow the legal entity's calendar](../02-decisions/03-contracts-and-data/0307-business-dates-and-legal-entity-calendar.md): the legal entity's time zone and fiscal year.

## Known limits

- **No pooled SaaS.** Each tenant costs a full set of processes.
- **Master data is shared across a tenant's legal entities.** Restricting a customer or product to one company needs an association table in the owning component.
- **Intercompany transactions** (one legal entity selling to another) are business features of the ERP components, not designed here.
- **One user across tenants is several accounts**: each tenant has its own IdP organisation and its own platform `sub`.
- **How legal entities in mdm/org relate to departments in the IAM directory** is settled in mdm/org's own design.
