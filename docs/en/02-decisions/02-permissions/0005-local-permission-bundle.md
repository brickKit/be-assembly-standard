[English](0005-local-permission-bundle.md) · [中文](0005-local-permission-bundle.zh.md)

# 0005 Permissions are checked against a local bundle

## Decision

`infra/authz` publishes the whole role → permission-key policy at `GET /authz/bundle`. The SDK in every process fetches it about every 15 seconds (a conditional GET, mostly answered `304`) into an in-process map, and a permission check is a lookup in that map. No component holds a permission table or a copy of the roles, and no component asks authz per request. The SDK's route functions take the permission key as a required argument, so calling one without a key does not compile; `make gates` rejects routes registered with the bare framework methods.

## Why

This is the standard local-PDP shape (OPA, Istio): the decision happens in memory with no network hop. Asking an authorization service on every request puts a network call on every request; keeping a replica in each component turns a lookup into a distributed cache-invalidation problem, with tables, migrations and event consumers in every component. Changes, including role changes and forced logouts, take effect within about 15 seconds. If authz becomes unreachable the last bundle stays in use; before the first bundle arrives business requests get `503` while `/healthz` stays healthy.

## What this rules out

- A roles or permissions table inside a business component, or syncing roles to components by events
- "Ask authz whether this user can do X" on each request
- Putting authz reachability into `/healthz` — one authz hiccup would restart every module of a shell
- A permission cache in Redis ([0004](0004-no-redis.md))
- A central authorization service such as SpiceDB, OpenFGA or a Zanzibar clone
- Registering a route with the bare framework `GET` / `POST` instead of the permission-key version

## Revisit only if

The policy no longer fits comfortably in memory in each process, or a requirement needs changes to take effect faster than the poll interval and shortening the interval cannot meet it.
