[English](0210-delegation-and-impersonation.md) · [中文](../../../zh/02-decisions/02-permissions/0210-delegation-and-impersonation.md)

# 0210 Delegation and impersonation are bounded by the person acted for; agents are reserved only

**Status**: decided; the contract shapes land with the 3.0.0 sweep. Each mode works once the provider declares its capability (`delegation`, `impersonation`); agents are reserved, not built.

## Decision

When one principal acts for another, the effective permissions are the actor's own intersected with each ceiling on the chain ([0204](0204-permissions-are-a-pure-union.md)), **computed on every request, never snapshotted**: a person who loses a role loses it for everyone acting through them at once.

| Mode | Example | How it works |
|---|---|---|
| on behalf (`on_behalf`) | approver A is on leave from 1 to 7 October and hands `infra.workflow.task.act` to B | B keeps B's own token; when the bundle holds a delegation to B covering the key, the SDK adds A's subjects to B's for that key, within the date range |
| read-only impersonation (`act_as`) | support looks at the system as Zhang San to diagnose a problem | a token whose `act` names the real person and whose `ceil` allows reads only; needs the key `infra.authz.impersonate`, allowed in production; every access log line carries the `act` chain, and the person viewed is notified |
| AI agent | none | **reserved only**: `act.kind` admits `agent`, the bundle capability `agents` defaults to `false`, the profile and ceiling shapes are fixed, permission keys accept an optional `delegable` field that nothing fills or reads. A token with `act.kind: agent` answers `401 UNSUPPORTED_DELEGATION` |

A provider without the capability answers a token carrying `ceil` or `dg` with `401 UNSUPPORTED_DELEGATION` and hides the entry points. The chain travels to other components as `be-actor-act`, for audit.

## Why

Both human modes are everyday ERP needs (substitution during leave, support diagnosis), and both have the same safe shape as OAuth token exchange and a permission boundary: whoever acts can never exceed the person acted for, and the chain is recorded. Computing the intersection per request is what makes revocation immediate. Reserving the agent shapes now, without building them, keeps the contract additive when the project takes AI up later.

## What this rules out

- A delegated or impersonating session that can do more than the person acted for, or keeps rights after they are revoked
- Copying the delegator's permissions into the delegate's roles, or caching the effective set across requests
- Impersonation that can write, or that leaves no `act` in the logs, or that the viewed person never learns of
- Fetching a user's data for a delegate or an agent with a component's system identity ([0208](0208-grpc-is-the-system-plane.md))
- Building an agent branch now: a token-exchange path for agents, a "never delegable" key list, an `ana/ai` component

## Revisit only if

The project takes AI agents up (they then come in by addition, through the reserved shapes), or a regulator requires impersonation to be off in production.

Full analysis: [20-authorization-provider.md, Choice](../../04-foundations/20-authorization-provider.md#choice); the token side in [21-identity-provider.md, Port contract](../../04-foundations/21-identity-provider.md#port-contract).
