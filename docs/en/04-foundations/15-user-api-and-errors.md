[English](15-user-api-and-errors.md) · [中文](../../zh/04-foundations/15-user-api-and-errors.md)

# User API and errors

The REST plane that people reach through the browser, the mobile BFF and, later, external systems: request and response headers, idempotency, paging, consistency hints, versioning, and the one error model shared by REST, gRPC and GraphQL, with a catalogue of reasons per component. For whoever adds a route, returns an error, builds the frontend's error handling, or plans the external API.

## Scope

- **In:** the shape of every user-facing HTTP exchange that is not business-specific; status codes; the error body and its gRPC and GraphQL forms; the reason catalogue; the versioning policy for internal and external callers.
- **Out:** which permission key a route requires and how it is declared ([02-backend.md](../01-conventions/02-backend.md#permissions)); the authorization provider and service accounts ([20-authorization-provider.md](20-authorization-provider.md)); tokens ([21-identity-provider.md](21-identity-provider.md)); deadlines ([16-deadlines-and-retries.md](16-deadlines-and-retries.md)); rate limits and routing at the edge (the edge document is planned as file 18); log levels for errors ([23-observability.md](23-observability.md)); the frontend's use of all this ([03-frontend.md](../01-conventions/03-frontend.md)).

## Choice

- **REST with OpenAPI 3** per component, under the component's prefix (`/erp/sales/orders`), JSON bodies, one permission key per route.
- **Errors are RFC 9457 problem details** (`application/problem+json`) carrying the fields of Google AIP-193's `ErrorInfo`: a machine `reason`, the `domain` that defines it, and string `metadata`. gRPC carries the same object as `google.rpc.Status` with `ErrorInfo`; GraphQL in `extensions`. One error crosses all three unchanged.
- **Each component declares its reasons** in `contracts/errors.yaml`, append-only, with message templates in every frontend language. The frontend translates; the server does not.
- **An internal error never leaks**: a generic message and the trace ID, the original only in the logs.
- **A record the caller cannot see answers 404, for reads and commands alike**; 403 means "you can see it, but you may not do this".
- **`Idempotency-Key`** is the header form of the body's `idempotency_key`.
- **Lists page by an opaque cursor**, with the field names already in the contracts.
- **Versions:** additive within a major; a breaking change is a new path prefix served beside the old one, announced with `Deprecation` and `Sunset`.

**Status**: REST with route permission keys is in place. The error model, the catalogue, the header set and the 404 rule are decided and land with the component protocol and the 3.0.0 sweep, before the 06c frontend work that depends on them. Today an error body is `{"error": "<message in Chinese>"}`, `INTERNAL` errors carry the raw database message to the browser, and an out-of-scope command answers 403.

## Port contract

### Request headers

| Header | Meaning |
|---|---|
| `Authorization: Bearer <token>` | the user's access token ([21](21-identity-provider.md)) |
| `Idempotency-Key` | for writes: one UUIDv7 per user action, reused on every retry of that action; equal to the body's `idempotency_key` when both are present, otherwise `400 IDEMPOTENCY_MISMATCH`; namespaced by caller and valid 30 days ([11](11-consistency-across-components.md#command-idempotency-callee)) |
| `X-Request-Id` | optional; generated when absent; echoed in the response |
| `traceparent` | W3C trace context, normally created at the edge ([23](23-observability.md)) |
| `X-Authz-Revision` | the authorization consistency token ([20](20-authorization-provider.md)) |

`Accept-Language` is not used to pick error text: the frontend renders text from the catalogue.

### Response headers

| Header | When |
|---|---|
| `X-Request-Id` | always |
| `X-Data-As-Of` | on reads of a view derived from another component's events: the `occurred_at` of the newest event applied, RFC 3339 ([11](11-consistency-across-components.md#read-your-writes)) |
| `Retry-After` | with 429 and 503 when the error carries a retry delay |
| `X-Authz-Consistency: stale` | when a list was filtered with an authorization projection that lags the requested revision ([20](20-authorization-provider.md)) |
| `Deprecation`, `Sunset`, `Link: <…>; rel="successor-version"` | on an operation scheduled for removal |

### Lists

- Request: `page_size` (capped per endpoint; above the cap it is lowered to the cap) and `cursor`. Response: the items and `next_cursor`, empty at the end. These are the names the contracts already use; the semantics follow AIP-158.
- The cursor is opaque: it encodes the sort key, the last ID and a hash of the filters. A cursor sent with different filters fails with `400 CURSOR_INVALID`.
- No `offset`, no exact totals ([0301](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md)).

### Status codes for access

| Situation | Read | Command |
|---|---|---|
| no token, or an invalid one | 401 `TOKEN_INVALID` | 401 |
| token issued before the user's roles changed | 401 `TOKEN_STALE`; the frontend refreshes and retries once | same |
| the route's permission key is missing | 403 `MISSING_PERMISSION`, `metadata.permission` names the key | same |
| the record does not exist | 404 `NOT_FOUND` | 404 |
| the record exists but the caller can see it through no rule, share or relation | 404 `NOT_FOUND`, indistinguishable from the row above | 404 |
| visible, but the action needs a key the caller lacks (for a record shared for viewing only) | — | 403 `MISSING_PERMISSION` |
| visible and allowed, but the state forbids it | — | 400 `FAILED_PRECONDITION` with the component's reason (`ORDER_NOT_DRAFT`) |
| the permission bundle has not loaded yet | 503 `AUTHZ_NOT_READY` | 503 |

### The error body

```json
{
  "type": "urn:be:erp/inventory:INSUFFICIENT_STOCK",
  "title": "Insufficient stock",
  "status": 400,
  "code": "FAILED_PRECONDITION",
  "reason": "INSUFFICIENT_STOCK",
  "domain": "erp/inventory",
  "detail": "Only 2 of product 0192… in stock, 5 requested",
  "metadata": { "product_id": "0192…", "requested": "5", "available": "2" },
  "violations": [ { "field": "items[0].qty", "reason": "MUST_BE_POSITIVE", "description": "…" } ],
  "instance": "/erp/sales/orders/0192…/confirm",
  "request_id": "…",
  "trace_id": "…"
}
```

| Field | Rule |
|---|---|
| `type` | `urn:be:<domain>:<reason>` |
| `title` | the reason's short title in the deployment's default language, from the catalogue |
| `status` | the HTTP status |
| `code` | the canonical gRPC code name |
| `reason`, `domain` | the identity of the error: the frontend looks up `domain` + `reason` in the catalogue |
| `detail` | the rendered message in the default language, for logs and debugging; shown to a user only when the frontend does not know the reason |
| `metadata` | string values only, the template's parameters; never personal data beyond what the user sent, never secrets |
| `violations` | field errors, from gRPC `BadRequest` |
| `instance` | the request path |
| `request_id`, `trace_id` | always present |

- **`INTERNAL`, `UNKNOWN` and `DATA_LOSS`** always answer `reason: INTERNAL`, `domain: be`, a generic `detail` and the `trace_id`; the original error goes only to the log. The runtime's mapping enforces this; component code cannot opt out.
- **Relaying a dependency's error:** keep its `reason` and `domain` when they mean something to the user (insufficient stock); map to a reason of your own only when you add meaning.

### gRPC form

Status code plus the default-language `detail` as the message, plus details: `ErrorInfo{reason, domain, metadata}` always; `BadRequest` for field violations; `PreconditionFailure`, `ResourceInfo` when useful; `RetryInfo` becomes `Retry-After`. `LocalizedMessage` is not used. The runtime maps both directions, so a component that calls another over gRPC and answers its own user over REST loses nothing.

| gRPC code | HTTP | gRPC code | HTTP |
|---|---|---|---|
| `INVALID_ARGUMENT`, `FAILED_PRECONDITION`, `OUT_OF_RANGE` | 400 | `RESOURCE_EXHAUSTED` | 429 |
| `UNAUTHENTICATED` | 401 | `CANCELLED` | 499 |
| `PERMISSION_DENIED` | 403 | `UNIMPLEMENTED` | 501 |
| `NOT_FOUND` | 404 | `UNAVAILABLE` | 503 |
| `ALREADY_EXISTS`, `ABORTED` | 409 | `DEADLINE_EXCEEDED` | 504 |
| `INTERNAL`, `UNKNOWN`, `DATA_LOSS` | 500 | | |

### GraphQL form (mobile BFF)

`errors[].extensions = { code, reason, domain, metadata, request_id, trace_id }`, copied from the downstream error.

### The reason catalogue

```yaml
# contracts/errors.yaml
domain: erp/inventory
reasons:
  - reason: INSUFFICIENT_STOCK
    code: FAILED_PRECONDITION
    http: 400
    params: [product_id, requested, available]
    title:   { en: "Insufficient stock", zh: "库存不足" }
    message: { en: "Only {available} of {product_id} in stock, {requested} requested",
               zh: "{product_id} 库存只有 {available}，需要 {requested}" }
    since: 3.0.0
    deprecated: false
```

- `reason` is `UPPER_SNAKE`, unique within the domain. Entries are **append-only**, like `registry/permissions.tsv`: never renamed, removed or reused; retired with `deprecated: true` ([07-registries.md](../01-conventions/07-registries.md#append-only)).
- The frontend generates its message tables from the catalogues of the installed components, the same way it generates types from the contracts. An unknown reason shows `title` or a generic message and is reported.
- **Platform reasons** use `domain: be` and ship with the component protocol (`schemas/errors-be.yaml` in the planned `brickKit/be-protocol` repository). This table is the complete set; a component never raises one of these names in its own domain:

| Reason | Code | Raised when |
|---|---|---|
| `INTERNAL` | `INTERNAL` | any internal error, original hidden |
| `TOKEN_STALE` | `UNAUTHENTICATED` | the token predates a role change |
| `MISSING_PERMISSION` | `PERMISSION_DENIED` | the caller lacks a permission key |
| `NOT_FOUND` | `NOT_FOUND` | the record does not exist or is not visible |
| `AUTHZ_NOT_READY` | `UNAVAILABLE` | the permission bundle has not loaded |
| `NOT_READY` | `UNAVAILABLE` | the process is not ready: no bundle yet, the database identity probe has not passed, or the migrations are behind the image (`/readyz`) |
| `TOKEN_INVALID` | `UNAUTHENTICATED` | no token, or one that fails verification (signature, `iss`, `aud`, `typ`, expiry) |
| `UNSUPPORTED_DELEGATION` | `UNAUTHENTICATED` | a token that acts through a kind of delegate the provider does not support |
| `MISSING_CALLER` | `UNAUTHENTICATED` | a system call without `be-caller` ([14](14-system-rpc.md)) |
| `OUT_OF_SCOPE` | `PERMISSION_DENIED` | a request parameter that is itself a scope value outside the caller's scope (`warehouse_id=7`) |
| `FIELD_FORBIDDEN` | `PERMISSION_DENIED` | a write to a field the caller may not see |
| `SORT_FORBIDDEN` | `INVALID_ARGUMENT` | sorting, filtering or aggregating by a field masked for the caller |
| `SHARE_NOT_ALLOWED` | `PERMISSION_DENIED` | a share the resource type or the caller may not make ([20](20-authorization-provider.md)) |
| `CAPABILITY_UNAVAILABLE` | `UNIMPLEMENTED` | the installed provider or adapter lacks a capability; `metadata.capability` names it |
| `IDEMPOTENCY_MISMATCH` | `INVALID_ARGUMENT` | a key reused with another command, target or body |
| `IDEMPOTENCY_IN_PROGRESS` | `ABORTED` | the first use of the key has not finished |
| `CURSOR_INVALID` | `INVALID_ARGUMENT` | a cursor that does not match the request |
| `BATCH_TOO_LARGE` | `INVALID_ARGUMENT` | more IDs than a batch allows |
| `LOCK_TIMEOUT` | `ABORTED` | a lock wait exceeded `lock_timeout` ([10](10-local-transactions.md#port-contract)) |
| `STATEMENT_TIMEOUT` | `DEADLINE_EXCEEDED` | a statement or transaction exceeded its timeout |
| `TX_CONFLICT` | `ABORTED` | serialization failures persisted after the automatic retries |
| `DB_POOL_EXHAUSTED` | `RESOURCE_EXHAUSTED` | the member's connection budget stayed full until its deadline |
| `OUTBOUND_LIMIT` | `RESOURCE_EXHAUSTED` | too many concurrent calls to one dependency ([16](16-deadlines-and-retries.md)) |
| `DEADLINE_BUDGET_EXHAUSTED` | `DEADLINE_EXCEEDED` | too little time left to start a call |
| `BODY_TOO_LARGE` | `INVALID_ARGUMENT` | the request body exceeds the route's limit; answered as HTTP 413 ([16](16-deadlines-and-retries.md)) |
| `RANGE_COLD` | `FAILED_PRECONDITION` | the requested time range is in cold storage; `metadata` gives the cold ranges and whether thawing or an export is possible |
| `UNIT_SEALED` | `FAILED_PRECONDITION` | a change to a sealed lifecycle unit; correct it with a new reversing document |

### Versioning

- **Within a major version, operations only grow** ([0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)); `make contract-check` rejects a breaking OpenAPI change.
- **A breaking change** (rare, decided by a person) publishes the new operations under a new prefix, `/<domain>/<name>/v2/…`, beside the old ones. The old ones answer with `Deprecation` and `Sunset` and are removed only after the sunset date.
- **External callers** (the external API is on the roadmap): the same rules are the published promise. Service accounts and API keys are principals in the authorization contract ([20](20-authorization-provider.md)); a rate limit per key is applied at the edge; a developer portal and quota screens come later.

## Alternatives

| Approach | Strengths | Weaknesses |
|---|---|---|
| **RFC 9457 carrying AIP-193 fields, with a reason catalogue** (chosen) | an IETF media type every HTTP client knows; extension members are allowed; the same reason as gRPC's `ErrorInfo`; testable and translatable | a catalogue to keep per component |
| A plain `{code, message, details}` body | simple | not a standard; each client invents its parsing |
| Google's JSON error (`{"error": {code, status, message, details}}`) | a 1:1 rendering of `google.rpc.Status` | tied to Google's gateway conventions; less known to generic HTTP tooling than RFC 9457 |
| RFC 9457 without a catalogue (free `type` URIs and `detail` text) | nothing to maintain | the frontend can only show server text; nothing to test reasons against |
| Server-side translation by `Accept-Language` | the client shows what it gets | every component maintains every language's text; the language switch is a frontend preference ([0404](../02-decisions/04-frontend/0404-four-user-preferences.md)) |
| GraphQL or OData for the whole user plane | flexible queries | route-level permission keys and the edge's per-path routing get much harder; a second query language in every component |

## Why this choice

- **One error object end to end:** a reason raised in inventory reaches the browser through sales' REST answer, or the phone through the BFF's GraphQL, without being re-invented at each hop.
- **Machine reasons make errors testable** (a test asserts `CUSTOMER_CODE_TAKEN`, not a sentence) and **translatable in the frontend**, which already owns the user's language.
- **Nothing internal leaks** by construction, because the runtime's mapping owns the `INTERNAL` case.
- **404 for invisible records** stops a command from probing whether a record exists.

## Why not the others

- **A home-grown body** would be one more shape for every client in every language to learn.
- **Google's JSON form** offers nothing RFC 9457 lacks once the AIP-193 fields are members of it.
- **Free-form problem details** leave the frontend with server text in one language.
- **Server-side translation** puts every language's text into every component and conflicts with language being a frontend preference. The server renders text only where no frontend is involved: notifications and printed documents, in the recipient's language.
- **GraphQL or OData everywhere** would trade per-route permission keys and simple routing for query flexibility no component needs; GraphQL stays in the mobile BFF.

## When to switch

- **The external API opens:** add API keys, quotas and the published version promise, without changing the error model or the paths.
- **Partners ask for client libraries:** generate them from the OpenAPI contracts.
- **Server-side text is needed beyond notifications and print:** add `LocalizedMessage` to the gRPC details and a matching problem member, as an addition.

## How to switch

- New error fields, headers or reasons are additions to the protocol and to the catalogues; clients that ignore them keep working.
- A breaking change to an operation is a new path prefix, as above; the error body itself is not expected to change.

## Conformance tests

Planned suite `tools/be-acceptance/conformance/userapi/`, black box against a running component:

- an `INTERNAL` error contains no original text and carries `trace_id` (red today);
- an `ErrorInfo` becomes the problem body and comes back as the same `ErrorInfo`; `BadRequest` becomes `violations`; `RetryInfo` becomes `Retry-After`;
- an invisible record answers 404 for a read and for a command; a missing key answers 403 `MISSING_PERMISSION`;
- `Idempotency-Key` and the body field are interchangeable; a mismatch answers 400 `IDEMPOTENCY_MISMATCH`;
- a cursor reused with other filters answers 400 `CURSOR_INVALID`; a `page_size` above the cap is lowered;
- every response carries `X-Request-Id`.

Gates (planned `error-catalog-scan`): a reason used in code but missing from the catalogue fails; a released reason removed from it fails. Component sample: mdm/customer answers `CUSTOMER_CODE_TAKEN` for a duplicate code. Frontend FE-1: an unknown reason falls back to `title` and is reported.

## Decision records

- [0301 Money is a decimal string; lists page by cursor](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md) and [0302 Contracts change by adding only](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md).
- [0204 Permissions are a pure union](../02-decisions/02-permissions/0204-permissions-are-a-pure-union.md) and [0205 Data scopes ship with the version](../02-decisions/02-permissions/0205-data-scopes-ship-with-the-version.md): what 403 and 404 are decided against.
- [0404 Four user preferences](../02-decisions/04-frontend/0404-four-user-preferences.md): the language is a frontend preference, so the frontend translates.
- Planned, not yet numbered: "the error model and the reason catalogue"; "a record the caller cannot see answers 404, for commands too"; "gRPC is the system protocol between components", whose other half is that REST is the user plane.

## Known limits

- **The catalogue is only as complete as its declarations**; the gate catches undeclared reasons in code, not reasons a component should have had.
- **`metadata` holds strings only**, as in AIP-193; numbers and dates are formatted by the producer.
- **No exact totals in lists.**
- **404 hides existence from the answer, not from timing**; equal-time responses are not attempted.
- **The external API is not built**: keys, quotas and the edge rate limit are designed, not implemented.
