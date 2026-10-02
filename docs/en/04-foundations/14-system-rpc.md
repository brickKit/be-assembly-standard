[English](14-system-rpc.md) · [中文](../../zh/04-foundations/14-system-rpc.md)

# System RPC

How components call each other synchronously: gRPC as the system plane, who the caller is on it, which kinds of call it may carry, how connections are reused and balanced, the metadata every call carries, message sizes, compression, streaming, contract versions, and calls between members of one shell. For whoever adds an rpc, calls another component, implements the component protocol in a new language, or proposes another protocol.

## Scope

- **In:** component-to-component synchronous calls, on the wire and in the contract.
- **Out:** what people (browsers, the mobile BFF, external systems) call: [15-user-api-and-errors.md](15-user-api-and-errors.md). Deadlines and retries in detail: [16-deadlines-and-retries.md](16-deadlines-and-retries.md). The error details carried in a status: [15](15-user-api-and-errors.md#port-contract). Service identity tokens: [21-identity-provider.md](21-identity-provider.md). Usage rules in code: [02-backend.md](../01-conventions/02-backend.md#calling-other-components).

## Choice

- **gRPC (HTTP/2 with protobuf) is the system plane.** Every caller on it is a system principal: another component of the same project network. People never call gRPC; data that is filtered by the user's data scope is read and written only over REST.
- **Three kinds of rpc are allowed on it:** data with `data_scopes: none` (master data); system protocols (try, confirm and cancel of a reservation, creating a task, checking a period); completion by ID (`BatchGet`) for IDs the caller legitimately holds, at most 500 per call.
- **User-facing rpcs already in contracts stay** (contracts only grow) and answer `UNAUTHENTICATED` the same way in every component.
- **Connections are reused** per (member, dependency, port), with keepalive; servers rotate connections every 5 minutes so load spreads on Kubernetes.
- **4 MiB messages, no compression, no streaming, packages versioned `<domain>.<name>.v<n>`.**
- **Addresses come from brickKit's injected endpoints**, always with the port name `grpc`.

**Status**: gRPC between components is in place. Connection reuse, keepalive, deadlines, the uniform identity interceptor and the metadata set are decided and land with the component protocol and the 3.0.0 sweep. Today every call dials a new connection and closes it; no call carries a deadline, trace context or caller identity; user-facing rpcs answer `UNAUTHENTICATED`, `INTERNAL` or succeed depending on the component.

## Port contract

### Addressing

- brickKit injects `<ID>_ENDPOINT` for each declared dependency, always prefixed with `http://`, gRPC ports included. The runtime strips the scheme and uses the extra port named `grpc` ([02-backend.md](../01-conventions/02-backend.md#the-runtime-is-the-only-way-in)). Dialling the HTTP port by mistake connects at TCP and then fails with a protocol error.
- An optional dependency that is absent has no variable at all; the caller degrades.
- No registry, no service discovery beyond these variables.

### Request metadata

| Key | Value | Set by | Used for |
|---|---|---|---|
| `grpc-timeout` | the caller's remaining budget | caller runtime | the callee's deadline ([16](16-deadlines-and-retries.md)) |
| `traceparent`, `tracestate` | W3C trace context | caller runtime | one trace across hops ([23](23-observability.md)) |
| `x-request-id` | the inbound request's ID, or a new one | caller runtime | log correlation |
| `be-caller` | the calling component's ID; in a shell, the calling member's | caller runtime | logs, audit, per-caller limits |
| `be-actor-sub` | the platform `sub` of the user whose request led to this call, read from the context **at call time**; absent for background work | caller runtime | audit only ("received by") |
| `be-actor-act` | the delegation chain (the token's `act` claim) as JSON, when the user acts through a delegate | caller runtime | audit only |
| `authorization` | reserved for a service token (`sub: svc:<component ID>`) once components run across a trust boundary | — | the extension point in [21](21-identity-provider.md) |

`be-caller` and `be-actor-sub` are trusted exactly as far as the network is: anything that can reach a gRPC port can already call it. They are recorded, never used to grant access. Because connections are shared, nothing about the user is captured when a connection is dialled.

### Server requirements

- Interceptor order, unary and streaming alike: panic recovery → identity (mark the call as a system principal, read `be-caller` and `be-actor-sub`) → deadline floor (10 s when the caller sent no `grpc-timeout`) → batch limit → error-detail normalisation ([15](15-user-api-and-errors.md#port-contract)) → RED metrics → tracing.
- A call without `be-caller` answers `UNAUTHENTICATED` / `MISSING_CALLER`.
- A user-facing rpc kept for compatibility answers `UNAUTHENTICATED` from the runtime, before any component code runs.
- `max receive message size` 4 MiB, set explicitly.
- Keepalive: `max connection age` 5 min with 30 s grace; minimum client ping interval 20 s; pings without active calls refused.
- Each member of a shell has its own gRPC server on its own port with its own interceptor chain.

### Client requirements

- One connection per (member, dependency, port), created lazily, reused by every call, closed at stop.
- Keepalive: ping after 30 s idle on an active call, 10 s timeout; no pings without active calls.
- A service config generated from each method's `idempotency_level` ([16](16-deadlines-and-retries.md#port-contract)).
- Interceptor order: default deadline → outbound concurrency limit → metadata → client RED metrics → the transaction guard ([10](10-local-transactions.md#port-contract)).

### Contract rules

- Package `<domain>.<name>.v<n>`; changes only add ([0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)); `buf breaking` runs in `make contract-check`.
- Every method declares `option idempotency_level`: `NO_SIDE_EFFECTS` for reads, `BatchGet` and `GetStatus`; `IDEMPOTENT` for every write that takes an `idempotency_key`. A gate checks it (planned `idempotency-level-scan`).
- Every aggregate root offers `BatchGet`, limited to 500 IDs per call (the limit is declared as a method option); more fail with `INVALID_ARGUMENT` / `BATCH_TOO_LARGE`. Every cross-component write offers `GetStatus` by key ([11](11-consistency-across-components.md#command-idempotency-callee)).
- Money as decimal strings, lists by cursor ([0301](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md)).
- No streaming rpcs. A large result is written to object storage and announced by an event (claim check).

### Load balancing

- **Docker:** one container per component or shell; nothing to balance.
- **Kubernetes with `replicas > 1`:** brickKit generates one ClusterIP Service per component, and kube-proxy balances per TCP connection. A reused HTTP/2 connection would stay on one pod forever; the server's 5-minute connection age sends `GOAWAY`, the client reconnects and lands on a pod chosen afresh, so load evens out within about five minutes. No mesh, no xDS.
- **Later:** a headless Service per gRPC port with client-side `round_robin` over DNS, once brickKit can generate one (v1.1.0 generates only the ClusterIP Service).

### Inside a shell

- Members call each other over the network exactly as standalone: the injected endpoint points at the shell's service and the member's port, which resolves back to the same container (about 0.1 ms on Docker).
- No in-process transport: it would skip serialisation and interceptors, so a member would behave differently merged and standalone ([0101](../02-decisions/01-architecture/0101-no-imports-between-components.md), [0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)).
- Connections and limits are per member, so `be-caller` names the real caller and one member's burst cannot use another's budget ([27-shells.md](27-shells.md)).
- A shell restart takes every member down at once; callers see one shared blip, which deadlines and the retry budget absorb.

## Alternatives

| | gRPC (chosen) | REST + OpenAPI between components | Connect-RPC | Twirp | GraphQL | Messaging only | Service mesh (Linkerd, Istio) |
|---|---|---|---|---|---|---|---|
| Contract | proto, strongly typed, breaking-change checks | OpenAPI | proto, the same files as gRPC | proto | SDL | event schemas | — (adds to a protocol) |
| Deadlines, retries, balancing | built into the protocol and its service config | hand-made | deadlines yes; retries and balancing hand-made | none | hand-made | n/a | in the sidecar |
| Languages | generated clients for nearly every language | every language | Go and TypeScript mature, Python young | Go first | TypeScript mature | every language | every language |
| Browser can call it | no (needs gRPC-Web) | yes | yes | yes | yes | no | — |
| Debugging | `grpcurl` | `curl` | `curl` | `curl` | tools | broker tools | — |
| Cost here | none new | weaker typing between components | a second wire format | missing features | a schema layer | every read becomes asynchronous | a sidecar per pod; a shell is one application to it |

## Why this choice

- **The protocol carries the hard parts**: deadlines (`grpc-timeout`), retries with a budget, keepalive and load balancing are specified once and implemented by every gRPC library, so a component in any language gets them by configuration rather than code.
- **Typed contracts with breaking-change checks** fit "contracts only grow".
- **One rule a weaker model can follow:** people use REST, components use gRPC. The security boundary is the transport.

## Why not the others

- **Connect-RPC:** its advantage, browsers calling the same proto, is exactly what the system plane forbids; its Python implementation is young. It stays an escape hatch: a connect-go server also speaks the gRPC wire protocol.
- **Twirp:** no deadlines, no retries, no balancing.
- **REST between components:** every deadline, retry and type check would be ours to build in every language.
- **GraphQL:** useful only where a client aggregates many sources, which is the mobile BFF's job, not a component's.
- **Messaging only:** a user waiting for "out of stock" cannot wait on an event ([11](11-consistency-across-components.md#choice)).
- **A mesh:** a sidecar per pod, against "no gateway, no mesh", and a shell is one application to it, so member identity is lost.

## When to switch

- **Browsers must call proto directly** (which reopens the system-plane decision): serve the same contracts with a connect-go handler.
- **Several nodes with partial failures** (some replicas bad, others good): client-side balancing over a headless Service, then outlier detection.
- **Components across a trust boundary** (another organisation's network, untrusted peers): service tokens on `authorization`, then mutual TLS.

## How to switch

- **Connect-go:** the server handler changes inside the SDK; clients and contracts do not.
- **Headless balancing:** a deployment change plus the client target `dns:///<service>:<port>` with `round_robin` in the generated service config; no component code.
- **Service tokens:** the identity provider issues client-credential tokens, the identity interceptor verifies them; the metadata key and the component API stay as they are.

## Conformance tests

Planned suite `tools/be-acceptance/conformance/rpc/`, run against each official SDK; most cases are red today.

- a hundred calls to one dependency use one connection;
- a call without a deadline receives the default; the callee sees the caller's remaining budget;
- only `NO_SIDE_EFFECTS` and `IDEMPOTENT` methods are retried, only on `UNAVAILABLE`; once the retry budget is spent, retries stop;
- an `ErrorInfo` crosses gRPC → REST → gRPC unchanged ([15](15-user-api-and-errors.md));
- `traceparent`, `x-request-id`, `be-caller` and `be-actor-sub` reach the callee; in a shell, `be-caller` is the calling member;
- a message above 4 MiB fails clearly on both sides;
- after the server's maximum connection age the client reconnects without a failed call;
- a user-facing rpc called without a user answers `UNAUTHENTICATED`, not `INTERNAL`.

Component tests written red first: erp/inventory and crm/opportunity user-facing rpcs answer `UNAUTHENTICATED` (today `INTERNAL`); mdm/customer and mdm/product refuse gRPC writes without a user (today they succeed); after the shells are assembled, sales → inventory `Reserve` inside one shell records the confirming user as the actor. Gate: a method with an `idempotency_key` but no `IDEMPOTENT` fails, seen red on a sample first.

## Decision records

- [0101 Components never import each other](../02-decisions/01-architecture/0101-no-imports-between-components.md) and [0108 One shell, one repository](../02-decisions/01-architecture/0108-one-repository-per-shell.md): calls stay on the network inside a shell.
- [0107 Authz and IAM addresses are shared variables](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md): which calls declare a dependency.
- [0301](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md) and [0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md): field and evolution rules.
- Planned, not yet numbered: "gRPC is the system protocol between components" (in the permissions folder); "a `BatchGet` takes at most 500 IDs" (in the contracts folder).

## Known limits

- **The system plane trusts the network.** gRPC ports are never routed through the edge, and Kubernetes deployments apply a network policy; across a trust boundary service tokens are required first.
- **`be-actor-sub` is not verified**; it is good for audit, not for decisions.
- **Rebalancing after a scale-up takes up to about five minutes** with ClusterIP Services.
- **No streaming and a 4 MiB cap**: bulk transfers go through object storage.
- **A shell restart is one failure for all its members.**
