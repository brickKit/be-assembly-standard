[English](0007-permissions-are-a-pure-union.md) · [中文](../../../zh/02-decisions/02-permissions/0007-permissions-are-a-pure-union.md)

# 0007 Permissions are a pure union, with no Deny

## Decision

A user's permissions are the union of the permissions of their roles. There is no Deny rule and no rule ordering. An exception for one person is a role with one member.

## Why

Under a pure union, "why can this person do this" always has exactly one answer: the role that grants it. Kubernetes RBAC has no Deny for this reason; the Deny-before-Allow evaluation order is what makes AWS IAM policies hard to reason about.

## What this rules out

- "Everyone in sales except Bob"; "deny export for interns"
- Negative permissions, blacklists, priority or ordering between rules
- A Deny column in `registry/permissions.tsv` or in the bundle

To express "everything except X", give the user a role that does not include X.

## Revisit only if

A regulatory requirement can only be stated as a prohibition that overrides every grant, and no split of roles can express it.
