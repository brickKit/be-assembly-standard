[English](0304-batch-get-takes-at-most-500-ids.md) · [中文](../../../zh/02-decisions/03-contracts-and-data/0304-batch-get-takes-at-most-500-ids.md)

# 0304 A `BatchGet` takes at most 500 IDs, and the limit is part of the contract

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

Every aggregate root offers `BatchGet` on the system plane ([0208](../02-permissions/0208-grpc-is-the-system-plane.md)), for completing IDs the caller already holds (display names on a list, the lines of a document). One call takes at most 500 IDs. The limit is declared in the contract as a method option (`max_items`), enforced by the runtime's interceptor before component code runs, and a larger request fails with `INVALID_ARGUMENT` / `BATCH_TOO_LARGE`. The same limit applies to the authorization provider's `BatchCheck` and to a component's `_authz/check`. A caller with more IDs splits them; a component never resolves a list of IDs with one call per ID.

## Why

Without a limit, one request can ask a component to load an unbounded number of rows inside one deadline, and the cost lands on the callee, which cannot refuse it gracefully. 500 covers every page size the user interfaces use, with room, and stays far below the 4 MiB message limit for ordinary records. Declaring it in the contract means every language's client and server, and every reviewer, read the same number.

## What this rules out

- A `BatchGet` without `max_items`, or a limit that exists only in one component's code
- Resolving IDs one call at a time in a loop (N+1 over the network)
- Using `BatchGet` to enumerate or search records: that is a `List` with a cursor ([0301](0301-money-as-strings-lists-by-cursor.md))
- A server that silently truncates a request above the limit instead of refusing it

## Revisit only if

A measured caller needs more than 500 IDs per round trip on a hot path and splitting costs more than the callee's protection is worth; the limit then changes in the contract, as an addition, for that method.

Full analysis: [14-system-rpc.md, Choice](../../04-foundations/14-system-rpc.md#choice).
