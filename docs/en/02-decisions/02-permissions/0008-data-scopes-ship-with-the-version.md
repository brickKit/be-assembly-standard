[English](0008-data-scopes-ship-with-the-version.md) · [中文](../../../zh/02-decisions/02-permissions/0008-data-scopes-ship-with-the-version.md)

# 0008 Data scopes ship with the version

## Decision

Which rows a user may see — by organisation, owner, warehouse, legal entity and so on — is declared in the component's `assembly.yaml` under `data_scopes` and enforced in its code. It changes by releasing a new version, never at runtime. The `data_scopes` section is mandatory: a component that needs none writes `data_scopes: none`, and omitting it is an error. What a user may *do* (functional permissions) is a separate mechanism that administrators change at runtime in `infra/authz`.

## Why

SAP, Odoo and PostgreSQL row-level security all ship row rules with the code; the one runtime-editable system, Salesforce, pays with a materialised sharing table that takes hours to recompute in a large organisation. "Sales see only their own customers" is company policy, not a daily switch, and rules in code can be reviewed, diffed and rolled back. A security default must fail closed, so leaving the section out cannot mean "none".

## What this rules out

- An admin screen for editing who can see which rows
- A runtime toggle such as "let department A see department B's orders"
- Fetching everything and filtering in the caller — paging is wrong at once (20 rows fetched, 12 filtered, the user sees 8)
- Omitting `data_scopes` because the component "doesn't need it"
- Using `SystemClient` on a user's request path — it bypasses data scopes with no error

Sharing one record with someone (moving a customer to another salesperson) is a business feature: change the record's `owner_id`.

## Revisit only if

A customer must change row rules between releases more often than the release cadence can follow.
