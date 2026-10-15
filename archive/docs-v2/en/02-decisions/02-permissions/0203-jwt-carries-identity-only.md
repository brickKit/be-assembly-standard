[English](0203-jwt-carries-identity-only.md) · [中文](../../../zh/02-decisions/02-permissions/0203-jwt-carries-identity-only.md)

# 0203 The token carries identity only, and the platform owns `sub`

**Status**: revised for 3.0.0 (new identity claims, a platform-owned `sub`); decided, lands with the 3.0.0 sweep.

## Decision

The application token, issued by the installed IAM member after the IdP has authenticated the person, carries who the caller is and nothing else. Not a single permission key goes into a token; what each role may do comes from the bundle ([0202](0202-local-permission-bundle.md)).

| Claim | Meaning |
|---|---|
| `iss`, `aud` | the platform issuer (`IAM_ISSUER`) and the deployment (`TENANT_ID`); both are checked |
| `sub` | the **platform** user id, a UUIDv7; the IdP's own subject is kept only in the IAM member's link table |
| `typ` | `access` or `refresh`; only `access` is accepted on a request |
| `iat`, `nbf`, `exp`, `jti` | standard; access tokens live 600 s |
| `tenant_id` | the tenant ([0308](../03-contracts-and-data/0308-tenant-is-the-deployment.md)); `org_id` is retired |
| `roles`, `dept_path` | resolved from the authorization provider at login and refresh |
| `act`, `ceil`, `dg`, `azp` | the acting party, ceiling profile codes, delegation grant id, the client ([0210](0210-delegation-and-impersonation.md)); `ceil` holds profile codes, never keys |
| `locale` | the user's language, for server-side text |

Every SDK verifies the same way: `alg` from the JWKS key (`RS256`, `ES256` or `EdDSA`), `kid` required, `iss`, `aud`, `exp`, `nbf` and `typ` checked.

## Why

Identity grows with the number of users and policy with the number of roles, so each lives where it stays small. A super-administrator's full set of permission keys overflows the 8 KB header limit: login succeeds and every following request fails with `431`. Permissions inside a token also change only when the token expires. A platform-owned `sub` means a change of IdP never rewrites an `owner_id`, a role assignment or an audit row. Without `typ`, a refresh token passes as an access token; without `iss` and `aud`, a token from another deployment or issuer is accepted.

## What this rules out

- "Put the user's permissions / scopes into the JWT claims"
- Wildcards or compression schemes to make permission keys fit in a token
- Feature flags or data-scope rules inside the token
- Using the IdP's subject as the user id anywhere outside the IAM member's link table
- Accepting a token without `typ: access`, or one whose `iss` or `aud` does not match
- Deciding access on the frontend from token claims as if that were security

## Revisit only if

Never for permission keys. A new identity claim is fine when every IAM implementation the project supports can issue it.

Full analysis: [21-identity-provider.md, Port contract](../../04-foundations/21-identity-provider.md#port-contract).
