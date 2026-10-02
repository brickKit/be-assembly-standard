[English](0504-error-model-and-reason-catalogue.md) · [中文](../../../zh/02-decisions/05-runtime/0504-error-model-and-reason-catalogue.md)

# 0504 One error object, identified by a reason from a catalogue

**Status**: decided; lands with the 3.0.0 sweep, before the 06c frontend work that depends on it.

## Decision

- **One error object crosses every plane unchanged.** On REST it is RFC 9457 problem details (`application/problem+json`) carrying the members of Google AIP-193's `ErrorInfo`: `type`, `title`, `status`, `code` (the gRPC code name), `reason`, `domain`, `detail`, `metadata` (strings only), `violations`, `instance`, `request_id`, `trace_id`. On gRPC it is `google.rpc.Status` with `ErrorInfo`; on the BFF's GraphQL it is `extensions`. The runtime maps both directions.
- **`domain` + `reason` identify the error.** Each component declares its reasons in `contracts/errors.yaml`, append-only, with a message template in every frontend language. Platform reasons use `domain: be` and ship with the component protocol; a component never raises one of them in its own domain.
- **The frontend translates**; the server's `detail` is in the deployment's default language, for logs and debugging.
- **An internal error never leaks**: `INTERNAL`, `UNKNOWN` and `DATA_LOSS` always answer `reason: INTERNAL`, `domain: be`, a generic `detail` and the `trace_id`; the original goes only to the log. Component code cannot opt out.
- **Log levels follow the status**, decided by the SDK, not by each component.

## Why

A reason raised in inventory reaches the browser through sales' REST answer, or the phone through the BFF, without being reinvented at each hop. Machine reasons make errors testable (a test asserts `CUSTOMER_CODE_TAKEN`, not a sentence) and translatable where the user's language already lives. The internal case is owned by the runtime's mapping, so nothing internal can leak by construction. Before 3.0.0, an error body was `{"error": "<message in Chinese>"}` and `INTERNAL` errors carried the raw database message to the browser.

## What this rules out

- An `error` string field, or any second error shape, on any plane
- A reason that is not in the component's catalogue; renaming, removing or reusing a reason (retire it with `deprecated: true`)
- A server-translated message as the only identity of an error
- Database messages, stack traces or secrets in `detail` or `metadata`; personal data in `metadata` beyond what the user sent
- A component raising a `be` reason under its own domain, or mapping a dependency's meaningful reason to a vaguer one of its own

## Revisit only if

Server-side text is needed beyond notifications and print: add `LocalizedMessage` and a matching problem member, as an addition.

Full analysis: [15-user-api-and-errors.md, The error body](../../04-foundations/15-user-api-and-errors.md#the-error-body) and [The reason catalogue](../../04-foundations/15-user-api-and-errors.md#the-reason-catalogue).
