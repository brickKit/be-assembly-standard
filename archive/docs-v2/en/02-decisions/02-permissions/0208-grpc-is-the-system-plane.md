[English](0208-grpc-is-the-system-plane.md) · [中文](../../../zh/02-decisions/02-permissions/0208-grpc-is-the-system-plane.md)

# 0208 gRPC is the system plane; people use REST

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

Two planes, separated by transport:

| Plane | Transport | Caller | What travels on it |
|---|---|---|---|
| system | gRPC between components | always a system principal: another component of the project, named by the `be-caller` metadata | master data with `data_scopes: none`; system protocols (try, confirm and cancel of a reservation, creating a task, checking a period); completion by ID (`BatchGet`, [0304](../03-contracts-and-data/0304-batch-get-takes-at-most-500-ids.md)) for IDs the caller legitimately holds |
| user | REST (and the mobile BFF's GraphQL) | a person, by their token | everything filtered by the person's data scope |

A system call without `be-caller` answers `UNAUTHENTICATED` / `MISSING_CALLER`. The user's `sub` and delegation chain travel as `be-actor-sub` and `be-actor-act` for audit only, never to grant access. User-facing rpcs already in contracts stay (contracts only grow) and answer `UNAUTHENTICATED` with reason `TOKEN_INVALID` (domain `be`) from the runtime in every component. A component that needs data for a user from another component calls that component's REST API with the user's token, through the SDK's user-plane client.

## Why

One rule that any developer, human or AI, can follow: people use REST, components use gRPC. The security boundary then is the transport, so a scoped read cannot be made by accident with the component's own identity, which sees more rows than the user. gRPC also carries the hard parts of calls between components (deadlines, retries with a budget, keepalive, connection rotation) in its specification, so every language gets them by configuration.

## What this rules out

- A gRPC method that returns rows filtered by the calling user's scope, or that trusts `be-actor-sub` to decide access
- Using the component's system identity (gRPC, or a system client) on a path that serves a user's request: the answer silently contains more rows than the user may see
- A browser or the mobile app calling gRPC directly
- A future agent fetching a user's data with a system identity: it acts through a delegated token on REST ([0210](0210-delegation-and-impersonation.md))

## Revisit only if

Browsers must call the proto contracts directly (serve them with a connect handler beside gRPC), or components run across a trust boundary, which turns the reserved service token on `authorization` into a requirement.

Full analysis: [14-system-rpc.md, Choice](../../04-foundations/14-system-rpc.md#choice).
