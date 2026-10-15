[English](0308-tenant-is-the-deployment.md) · [中文](../../../zh/02-decisions/03-contracts-and-data/0308-tenant-is-the-deployment.md)

# 0308 A tenant is a deployment; companies are legal entities inside it

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

- **One customer, one deployment.** The project is deployed privately, one installation per customer. There is no multi-customer SaaS mode in which several customers share one database.
- **One customer, one fork of the project repository.** brickKit has no multi-customer concept: each customer's fork holds its own `brickkit.yaml` (its lock file, so versions move customer by customer), `config/`, secrets and deploy files; shared changes are merged from the upstream repository with Git ([07-tenancy.md](../../04-foundations/07-tenancy.md#operating-many-tenants)).
- **The tenant is reserved on the wire, not in the tables.** Tokens carry `tenant_id`, and `aud` is the deployment's `TENANT_ID` ([0203](../02-permissions/0203-jwt-carries-identity-only.md)); contracts may carry a tenant field. No table has a `tenant_id` column.
- **Several companies of one customer are legal entities**, a dimension inside the deployment, owned by `mdm/org`:
  - every transactional document carries `legal_entity_id`;
  - events about such documents carry it (`ce-legalentity`);
  - document numbers are scoped by legal entity and period ([0306](0306-uuidv7-own-keys.md));
  - each legal entity has its own calendar and functional currency ([0307](0307-business-dates-and-legal-entity-calendar.md), [0301](0301-money-as-strings-lists-by-cursor.md));
  - `legal_entity` is a data-scope dimension ([0205](../02-permissions/0205-data-scopes-ship-with-the-version.md)), so a report across legal entities is scoped like any other read.

## Why

Customers install the system on their own machines, so isolation between customers is the deployment itself, the strongest isolation there is. Group companies, on the other hand, are needed now and must share master data, users and roles inside one installation, which is what a legal-entity dimension gives. Reserving the tenant in tokens and contracts keeps a later shared mode additive, without paying for a `tenant_id` on every row and in every query today.

## What this rules out

- A `tenant_id` column, or tenant filtering in queries, in any component
- One deployment serving several unrelated customers
- A separate deployment per company of one group when the companies share master data
- A transactional document, or its event, without its legal entity

## Revisit only if

A shared, multi-customer offering becomes a product decision. The tenant fields reserved on the wire are the starting point; tables and queries then need a planned change of their own.

Full analysis: [07-tenancy.md, Choice](../../04-foundations/07-tenancy.md#choice).
