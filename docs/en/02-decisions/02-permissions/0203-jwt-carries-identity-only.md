[English](0203-jwt-carries-identity-only.md) · [中文](../../../zh/02-decisions/02-permissions/0203-jwt-carries-identity-only.md)

# 0203 The token carries identity only

## Decision

A JWT carries who the user is — `sub`, `roles[]`, `dept_path`, `org_id` — and nothing else. Not a single permission key goes into a token; what each role may do comes from the bundle ([0202](0202-local-permission-bundle.md)).

## Why

Identity grows with the number of users and policy with the number of roles, so each lives where it stays small. A super-administrator's full set of permission keys overflows the 8 KB header limit: login succeeds and every following request fails with `431`. Permissions inside a token also change only when the token expires.

## What this rules out

- "Put the user's permissions / scopes into the JWT claims"
- Wildcards or compression schemes to make permission keys fit in a token
- Feature flags or data-scope rules inside the token
- Deciding access on the frontend from token claims as if that were security

## Revisit only if

Never for permission keys. A new identity claim is fine when every IAM implementation the project supports can issue it.
