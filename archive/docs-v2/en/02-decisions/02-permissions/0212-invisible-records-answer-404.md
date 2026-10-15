[English](0212-invisible-records-answer-404.md) · [中文](../../../zh/02-decisions/02-permissions/0212-invisible-records-answer-404.md)

# 0212 A record the caller cannot see answers 404, for reads and commands

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

| Situation | Read | Command |
|---|---|---|
| the record does not exist | `404 NOT_FOUND` | `404 NOT_FOUND` |
| the record exists, but no rule, share or relation makes it visible to the caller | `404 NOT_FOUND`, indistinguishable from the row above | `404 NOT_FOUND`, indistinguishable |
| visible, but the action needs a key the caller lacks (a record shared for viewing only) | — | `403 MISSING_PERMISSION` |
| visible and allowed, but the state forbids it | — | `400 FAILED_PRECONDITION` with the component's reason |

`403` therefore always means "you can see it, but you may not do this". A command checks visibility before it looks up its idempotency key, so a replay by someone who cannot see the record answers like a mismatch, not with the stored result.

## Why

A different answer for "exists but hidden" lets anyone probe which ids exist, by reading or by trying a command on them; GitHub and most mainstream APIs answer 404 for exactly this reason. Making commands answer the same as reads closes the probe that the earlier "403 for an out-of-scope command" left open, and gives the frontend one meaning per status.

## What this rules out

- `403` for a record outside the caller's scope, on a read or a command
- Error details, timing paths or reasons that tell "hidden" apart from "absent"
- Returning a stored idempotent result to a caller who cannot see the record

## Revisit only if

A legal or audit requirement obliges the system to tell a user that a record exists but is withheld.

Full analysis: [15-user-api-and-errors.md, Status codes for access](../../04-foundations/15-user-api-and-errors.md#status-codes-for-access).
