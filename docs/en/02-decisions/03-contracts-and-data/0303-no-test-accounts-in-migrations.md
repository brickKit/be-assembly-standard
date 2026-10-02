[English](0303-no-test-accounts-in-migrations.md) · [中文](../../../zh/02-decisions/03-contracts-and-data/0303-no-test-accounts-in-migrations.md)

# 0303 No test accounts in migrations

**Status**: in place; the 3.0.0 revision (the first administrator named by IdP login in `BOOTSTRAP_ADMIN_LOGIN`, and the seed tools no longer write the first administrator into the database) is decided and lands with the 3.0.0 sweep.

## Decision

Migrations contain only product baseline data that every deployment needs, such as a default warehouse or a chart-of-accounts template. Test users, roles, passwords and demo data are created only by the seed tools a developer runs by hand (`make seed` in a component, `make seed-data` in this project), never by any deployment or CI step. The first real administrator is set by the deployer, by IdP login: the shared configuration key `BOOTSTRAP_ADMIN_LOGIN` names that person's IdP login name or e-mail address. A platform `sub` cannot be named in advance, because the platform issues it only at the person's first login ([0203](../02-permissions/0203-jwt-carries-identity-only.md)). At that first login the identity provider binds the login to the new platform `sub`, once per deployment, and publishes its directory event with `bootstrap_admin: true`; the authorization provider grants that subject the administrator role on it, idempotently. Local development uses the same key, set in the developer's own environment; the seed tools never write the first administrator into the database directly.

## Why

Migrations run on every deployment, including each customer's production system. An account baked into a migration is a backdoor with a public password and every permission, installed in every customer's system. One path for the first administrator, the same on a developer machine as in production, means that path is always tested.

## What this rules out

- "Create `dev.superuser` in a migration so it works out of the box"
- A default `admin` / `admin` account or any hard-coded credential
- Demo customers, orders or other sample data in a migration
- A seed step that inserts the first administrator's role assignment straight into authz's tables
- A `BOOTSTRAP_ADMIN_SUB` key, or any other way of naming the first administrator by a platform `sub` before that person has logged in
- Running the seed tools from a deployment, an image entrypoint or CI against a real environment
- Enabling the password grant type on a production IAM application to make test logins easier

## Revisit only if

Never for identities and credentials.

Rules in full: [05-data.md](../../01-conventions/05-data.md).
