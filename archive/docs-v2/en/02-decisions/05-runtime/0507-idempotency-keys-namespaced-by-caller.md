[English](0507-idempotency-keys-namespaced-by-caller.md) · [中文](../../../zh/02-decisions/05-runtime/0507-idempotency-keys-namespaced-by-caller.md)

# 0507 Idempotency keys are namespaced by caller and bound to the command

**Status**: decided; lands with the 3.0.0 sweep.

## Decision

- **A command's idempotency key belongs to its caller.** The callee keys `besdk_idempotency` by `(caller, idempotency_key)`, where the caller is `user:<platform sub>`, `svc:<component ID>` (from `be-caller` on the system plane) or `system` (the component's own background work). Another caller's key is, for me, an unused key.
- **A key is bound to its command, its target and a fingerprint of the request**: SHA-256 over the request canonicalised with RFC 8785. The same key with another command, target or body fails with `INVALID_ARGUMENT` / `IDEMPOTENCY_MISMATCH`; a claim not yet completed answers `ABORTED` / `IDEMPOTENCY_IN_PROGRESS`; a completed one returns the stored result without executing again.
- **Claims are atomic** (`INSERT … ON CONFLICT DO NOTHING`), and a two-step command keeps its claim across the network call; a step that fails for certain releases the claim so the key can be retried.
- **Checks run in a fixed order**: validate arguments, authorize the target and its data scope, then look up or claim the key, then the state machine, then the write.
- **Keys are valid for 30 days**, written into every keyed command's contract. A key used by an event handler for a downstream command is derived from the event, so a redelivery is a retry with the same key. `Idempotency-Key` is the REST header form of the body's `idempotency_key`.

## Why

With a global key space, one caller can read another's result, take over a key the system derives (such as one from an opportunity ID), or learn whether a key exists. Binding the key to the command and a fingerprint turns an accidental reuse into an error instead of a silently wrong answer. Authorizing before the lookup keeps a replay from returning a result to someone who may no longer see the record ([0212](../02-permissions/0212-invisible-records-answer-404.md)).

## What this rules out

- A key space shared by all callers; trusting a key without the caller
- Returning a stored result for a request whose command, target or body differs
- Claiming a key with a plain `SELECT` followed by an insert
- Looking up the key before checking permission and data scope
- A retry, at any layer, with a new key for the same intent

## Revisit only if

A legitimate case appears in which two different callers must share one command's outcome; that is a business-level reference (an order number), not a shared idempotency key.

Full analysis: [11-consistency-across-components.md, Command idempotency (callee)](../../04-foundations/11-consistency-across-components.md#command-idempotency-callee).
