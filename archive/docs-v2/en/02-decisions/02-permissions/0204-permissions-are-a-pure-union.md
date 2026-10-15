[English](0204-permissions-are-a-pure-union.md) · [中文](../../../zh/02-decisions/02-permissions/0204-permissions-are-a-pure-union.md)

# 0204 Permissions are a pure union, with no Deny

**Status**: revised for 3.0.0 (intersection only along a delegation chain); decided, lands with the 3.0.0 sweep.

## Decision

Inside one principal, permissions are the union of everything granted to it: the keys of its roles, the highest level any of its roles gives a key, the dimension values of all of them, its shares and relations. There is no Deny rule and no rule ordering. An exception for one person is a role with one member.

The only intersection is along a delegation chain ([0210](0210-delegation-and-impersonation.md)): when one principal acts for another, the effective permissions are the delegate's union intersected with each ceiling on the chain, like a permission boundary. A ceiling only narrows; it never denies something a grant gives inside its bounds, and it has no order.

## Why

Under a pure union, "why can this person do this" always has exactly one kind of answer: the grant that gives it. Kubernetes RBAC has no Deny for this reason; the Deny-before-Allow evaluation order is what makes AWS IAM policies hard to reason about. A ceiling on a delegation keeps that property: the explanation is still one grant plus "and the ceiling allows it", and grants still only ever widen what is visible.

## What this rules out

- "Everyone in sales except Bob"; "deny export for interns"
- Negative permissions, blacklists, priority or ordering between rules
- A Deny column in `registry/permissions.tsv` or in the bundle
- Using a ceiling profile as a Deny list for an ordinary user who acts for nobody

To express "everything except X", give the user a role that does not include X.

## Revisit only if

A regulatory requirement can only be stated as a prohibition that overrides every grant, and no split of roles can express it.

Full analysis: [20-authorization-provider.md, Choice](../../04-foundations/20-authorization-provider.md#choice).
