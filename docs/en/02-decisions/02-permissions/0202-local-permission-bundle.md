[English](0202-local-permission-bundle.md) · [中文](../../../zh/02-decisions/02-permissions/0202-local-permission-bundle.md)

# 0202 Permissions are decided locally, against a bundle and a projection

**Status**: revised for 3.0.0 (bundle v2 and the local projection of direct grants); decided, lands with the 3.0.0 sweep.

## Decision

Every access decision is made inside the component's own process, from two local sources:

| Source | Holds | How it arrives |
|---|---|---|
| the bundle, `GET {AUTHZ_URL}/authz/v2/bundle` | roles → keys, levels, dimension values, field keys, ceilings, delegations, `stale_since` | a conditional GET every 15 s (mostly `304`) and on every poke, into an in-process map |
| the projection, `besdk_authz_acl` in the component's own schema | the direct grants (shares, relations) on the resource types the component declares | the provider's changefeed, pulled every 5 s and on every poke |

A permission check is a lookup in the bundle; a list is one static parameterised SQL predicate over the component's own rows and its projection ([0206](0206-no-row-level-security.md)). A request reaches the authz provider in only two cases: a resource type declared `derivation: graph`, and a single read whose consistency token is ahead of the projection. No component holds a permission table or a copy of the roles. The SDK's route registration takes the permission key as a required argument; `make gates` rejects routes registered with the bare framework methods.

## Why

This is the standard local-decision-point shape (OPA, Istio): the decision happens in memory or in the component's own database, with no network hop on the hot path. Asking an authorization service on every request puts a network call on every request and makes every component as slow and as available as authz. Materialising only direct grants, and expanding the subject side (roles, department ancestors, delegators) per request, means moving a person changes a token, not a projection row. Changes take effect within about 15 seconds for the bundle and 5 for the projection; the consistency token closes the gap for the writer. If authz becomes unreachable the last bundle and the projection stay in use; before the first bundle arrives protected routes answer `503` while `/healthz` stays healthy.

## What this rules out

- A roles or permissions table inside a business component, or syncing roles to components by events
- "Ask authz whether this user can do X" on each request, outside the two cases above
- Putting authz reachability into `/healthz`: one authz hiccup would restart every member of a shell
- A permission cache in Redis ([0201](0201-no-redis.md)); caching a decision across requests
- A Zanzibar-style service (SpiceDB, OpenFGA) as a direct dependency of business components or on the hot path; OpenFGA may sit behind a slot member ([0209](0209-authz-is-a-slot-family.md))
- Registering a route with the bare framework `GET` / `POST` instead of the permission-key version

## Revisit only if

The bundle no longer fits comfortably in memory in each process, or a requirement needs changes to take effect faster than the poll interval and the poke together can meet.

Full analysis: [20-authorization-provider.md, Choice](../../04-foundations/20-authorization-provider.md#choice).
