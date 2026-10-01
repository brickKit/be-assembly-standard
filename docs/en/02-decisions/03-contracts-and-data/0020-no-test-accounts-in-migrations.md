[English](0020-no-test-accounts-in-migrations.md) · [中文](../../../zh/02-decisions/03-contracts-and-data/0020-no-test-accounts-in-migrations.md)

# 0020 No test accounts in migrations

## Decision

Migrations contain only product baseline data that every deployment needs, such as a default warehouse or a default legal entity with its chart of accounts. Test users, roles, passwords and demo data are created only by the seed tools a developer runs by hand (`make seed` in a component, `make seed-data` in this project), never by any deployment or CI step. The first real administrator is set by the deployer: `infra/authz` takes the identity's `sub` in its `BOOTSTRAP_ADMIN_SUB` configuration key and, at start, grants that subject the administrator role, idempotently.

## Why

Migrations run on every deployment, including each customer's production system. An account baked into a migration is a backdoor with a public password and every permission, installed in every customer's system.

## What this rules out

- "Create `dev.superuser` in a migration so it works out of the box"
- A default `admin` / `admin` account or any hard-coded credential
- Demo customers, orders or other sample data in a migration
- Running the seed tools from a deployment, an image entrypoint or CI against a real environment
- Enabling the password grant type on a production IAM application to make test logins easier

## Revisit only if

Never for identities and credentials.
