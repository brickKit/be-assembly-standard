[English](23-observability.md) · [中文](../../zh/04-foundations/23-observability.md)

# Observability

How a request is followed across components, how each component reports metrics and logs, and how the audit trail differs from application logs. For whoever touches tracing, metrics, log fields or levels, the observability stack, or audit.

## Scope

- trace context propagation over HTTP, gRPC and events;
- the identity every signal carries (which component, which version, which instance), standalone and in a shell;
- metrics: exposition, labels, the shell's aggregated endpoint;
- application logs: format, fields, levels, which errors are logged at which level, redaction;
- correlation ids: request id, trace id, causation id;
- audit logs, which are business data and travel a different path;
- the observability stack and how it is swapped.

Not covered: dashboards, alert rules and on-call procedures (planned `05-operations/`); the job metrics themselves ([19-background-jobs.md](19-background-jobs.md)).

## Choice

- **OpenTelemetry** for traces, with the OTel metrics API wired to the same Prometheus registry; **W3C Trace Context and Baggage** on every hop.
- **Prometheus pull** for metrics, so metrics work without a collector; every series carries the `component` label; a shell exposes one aggregated `/metrics`.
- **Logs are JSON lines on stdout**, nothing else; the collector picks them up from the container runtime and sends them to Loki.
- **Each member has its own telemetry identity**: in a shell, `service.name` is the member's component ID, never the shell's.
- **Logging levels are decided by the SDK** from the error's status, not by each component.
- **Audit goes through the outbox** to `infra/audit`, in the same transaction as the business write.
- **Backend-neutral**: OTLP is the port; Tempo, Loki, Prometheus and Grafana are the default stack, all pinned to exact image versions.

**Status**: in place: stdout JSON logs with `component_id`, `trace_id`, `span_id`; one Prometheus registry per module with `http_requests_total` and `http_request_duration_seconds`; OTLP export to `OTEL_BASE_URL` (empty disables it). Decided (the 3.0.0 sweep and its SDK release): propagation (today every hop starts a new root trace), per-member resources, the `component` label and the shell's aggregated endpoint, `LOG_LEVEL`, SDK-owned log levels, automatic redaction in every SDK, the audit path, the log pipeline into Loki, pinned images.

## Port contract

**Propagation.**

| Hop | Carrier | Rule |
|---|---|---|
| HTTP in | `traceparent`, `tracestate`, `baggage` headers | extracted; the server span is a child of the caller's span. An inbound `traceparent` with the sampled flag 0 is propagated (the trace ID is kept and children are unsampled), but its spans are neither recorded nor exported; `trace_id` still appears in the logs and problem bodies |
| HTTP out (user plane, see [15-user-api-and-errors.md](15-user-api-and-errors.md)) | same headers, plus `X-Request-Id` | injected |
| gRPC in and out ([14-system-rpc.md](14-system-rpc.md)) | the same keys in metadata | extracted and injected on every call |
| Event publish | the envelope's trace context ([13-event-contracts.md](13-event-contracts.md)) | the producer's span context is written into the message |
| Event consume | — | the consumer starts a **new trace with a span link** to the producer's span, not a child span (OpenTelemetry messaging conventions): long asynchronous chains would otherwise grow one unbounded trace |

The propagator and the OTLP exporter are the only process-wide telemetry. Both belong to the platform side, the standalone launcher or the shell, never to a module: a module neither installs them nor shuts them down. Every instrumentation (HTTP server, gRPC server and client, outbound HTTP, consumers) is given the member's tracer provider, meter provider and the propagator explicitly, never the process globals. The global tracer provider is only a fallback and carries the shell's own ID as `service.name`, so a span with that name reveals an instrumentation that was missed.

**Correlation.** `X-Request-Id` is the id a client sees and may quote. When a request arrives without one, the first service sets it to the trace id. It is propagated on outbound calls. Every log line carries `trace_id`; events carry `ce-causationid` ([13-event-contracts.md](13-event-contracts.md)).

**Resource attributes**, per member: `service.name` = the component ID (`erp/sales`), `service.version` = the component version, `service.namespace` = the component's domain (the first segment of its ID, `erp`), `service.instance.id` = the container or Pod, `deployment.environment.name` = `DEPLOY_ENV` (default `dev`; the OpenTelemetry semantic-conventions name from 1.27, formerly `deployment.environment`). In a shell each member has its own tracer provider and meter provider with these attributes; the exporter is shared and only the shell shuts it down, after every member has stopped. Stopping one member flushes only that member's own span queue.

**Export.** OTLP to `OTEL_BASE_URL` ([04-configuration.md](../01-conventions/04-configuration.md#shared-connection-keys)). Empty means no export and no error; the component still runs.

**Metrics.**

- Prometheus text format at `/metrics` on the member's HTTP port.
- Every series carries the constant label `component=<component ID>`, standalone too, so one query works in both forms.
- A shell serves one aggregated `/metrics` on its own port that merges every member's registry, each wrapped with its `component` label; the scrape target is the shell, one port per container.
- RED metrics are protocol names: `be_http_server_requests_total` and `be_http_server_duration_seconds` (labels `method`, the route template `route`, a numeric `status_code`), and `be_grpc_server_handled_total` / `be_grpc_server_duration_seconds` with the client-side pair. The 2.x names `http_requests_total` and `http_request_duration_seconds` are not kept (3.0.0 is a one-shot rebuild).
- Metric names the protocol defines start with `be_`, so a component in any language emits the same names; a component's own metrics start with its domain and name.

**Logs.** One JSON object per line on stdout.

| Field | Content |
|---|---|
| `time` | RFC 3339 UTC |
| `level` | `debug`, `info`, `warn`, `error` |
| `msg` | the event name or one sentence |
| `component_id`, `component_version` | the component, in a shell the member's own values |
| `trace_id`, `span_id` | from the active span |
| `request_id` | when the line belongs to a request |
| access log lines also | `sub` and `perm` (the permission key the route required), so a refused request can be traced to a person and a key; a 413 answered before the guard ran carries neither |

- **The access log** covers the user plane and the resource contract only. The operations endpoints (`/healthz`, `/readyz`, `/metrics`, `/_be/info`) are excluded; a runtime MAY log them at debug. An access-log line's level follows its status: 500 (`INTERNAL`, `UNKNOWN`, `DATA_LOSS`) is ERROR, 503 and 504 (`UNAVAILABLE`, `DEADLINE_EXCEEDED`) are WARN, everything else (2xx, 3xx, 4xx, 499, 501) is INFO.

- **Level**: the key `LOG_LEVEL` (`debug|info|warn|error`, default `info`), applied per member in a shell.
- **Which level an error gets**, decided by the SDK in its HTTP and gRPC error mapping, not by each component:

| Status (gRPC / HTTP) | Level |
|---|---|
| `INTERNAL`, `UNKNOWN`, `DATA_LOSS` / 500 | ERROR |
| `UNAVAILABLE`, `DEADLINE_EXCEEDED` / 503, 504 | WARN |
| `CANCELLED` (`REQUEST_CANCELLED`), including a cancel during shutdown | not logged as an error; its access-log line is INFO |
| caller errors: `INVALID_ARGUMENT`, `NOT_FOUND`, `PERMISSION_DENIED`, `FAILED_PRECONDITION` … / 4xx | INFO |

  ERROR means an operator must act. A caller's mistake is never ERROR.
- **Redaction** is automatic in every SDK's log handler, never in business code, checked by the shared vectors `redaction` so all languages mask the same way:
  - protected names: `phone`, `mobile`, `id_card`, `password`, `bank_card`, `email`, `token`, `secret`, `authorization`, `cookie`, `set-cookie`, `api_key`;
  - a field name is split into tokens: camelCase words, and `_`, `-`, `.` as separators, lower-cased. It matches when a protected name's tokens appear in it as one contiguous run of whole tokens (the last may carry a plural `s`): `phone_number`, `accessToken`, `user.email` match; `telephone`, `tokenizer` do not;
  - the matching field's value, of any type, is replaced by the string `"[REDACTED]"` and not walked further; values are never scanned, so personal data never goes into free text; the envelope fields are never touched;
  - a line is at most 2048 bytes, its terminating newline included, and stays one valid JSON object. The envelope fields are never cut: `time`, `level`, `msg`, `component_id`, `component_version`, `trace_id`, `span_id`, `request_id`, `truncated`. Every other string value may be cut, longest first, at a character boundary, ending in `…[TRUNCATED]`.
- No component sends logs over the network itself; stdout is the only output. The collector reads container logs (a file-log receiver on Docker, the Kubernetes log pipeline on Kubernetes) and forwards them to Loki.

**Audit logs** are not application logs:

| | Application log | Audit log |
|---|---|---|
| For | operators debugging | the business, auditors, the tenant's administrator |
| Content | anything useful, may be sampled | who, when, on what, which action, the before and after values, the full `act` chain when someone acted for someone else |
| Path | stdout → collector → Loki | an event in the outbox, written in the same transaction as the business change, subject `audit.<domain>.<name>.<action>.v1`; `infra/audit` stores it in an append-only, hash-chained table |
| Retention | 14 to 30 days | 3 years by default, configurable, never below the legal minimum of 6 months |
| Personal data | redacted | field-level diffs masked by field key ([20-authorization-provider.md](20-authorization-provider.md)) |

A rolled-back transaction leaves no audit record; a committed one always has one.

## Alternatives

| | Strengths | Weaknesses |
|---|---|---|
| OTel traces + Prometheus pull + stdout logs through the collector (chosen) | vendor-neutral; metrics work without a collector; logging never blocks on the network | three signals, three paths |
| Prometheus pull only, no tracing | simplest | cannot follow a request across components |
| OTLP push for every signal | one pipeline | without a collector nothing is visible; push metrics from a shell need per-member resources anyway |
| SDK sends logs straight to Loki | no collector for logs | a network hiccup blocks or drops logs in the request path |
| A vendor SDK (Datadog, Alibaba Cloud ARMS, Tencent Cloud APM) | rich features out of the box | ties every component to one vendor, per language |
| Other OTLP backends (SigNoz, OpenObserve, any vendor accepting OTLP) | full stacks behind the same protocol | not a code choice: they replace the default backend, see **How to switch** |

## Why this choice

- Vendor-neutral at the code level: every official SDK speaks OTLP and Prometheus, so the backend is a deployment decision.
- Metrics need no collector, and logs never depend on the network, which suits one machine with limited resources.
- Per-member identity makes a shell look exactly like the members run alone in Tempo, Prometheus and Loki.
- Levels decided centrally keep ERROR meaningful: one place maps status to level, so every component logs the same way.
- Audit through the outbox makes the audit trail exactly as consistent as the data it describes.

## Why not the others

- **No tracing**: a slow confirm-order that crosses sales, inventory and finance cannot be followed.
- **Push-only metrics**: a misconfigured collector would make everything invisible.
- **Logs from the SDK to Loki**: logging would join the request path and fail with the network.
- **Vendor SDKs**: one per language and per vendor, and a customer with another platform could not use them.

## When to switch

The customer already runs an observability platform (SigNoz, OpenObserve, a cloud APM, Datadog) that accepts OTLP: the backend changes, the components do not.

## How to switch

1. Change the OpenTelemetry Collector's exporters (and its log receiver if the platform collects logs itself); point `OTEL_BASE_URL` at the collector the platform provides, if any.
2. Keep Prometheus scraping, or let the collector scrape `/metrics` and forward.
3. No component, SDK or pin changes.

## Conformance tests

Suite `tools/be-acceptance/conformance/telemetry/` (decided), run against every official SDK:

- an inbound `traceparent` is continued, and an outbound user-plane call injects it;
- a gRPC client and server end up in one trace;
- an event consumer's span links to the producer's span;
- in a shell, two members' spans carry different `service.name` values; after an HTTP → gRPC → event chain no span carries the shell's own ID; stopping one member does not drop spans another member emits afterwards;
- the shell's aggregated `/metrics` carries the `component` label and registers no collector twice;
- `LOG_LEVEL=warn` suppresses info lines;
- the level mapping: a caller error logs INFO, an internal error ERROR, a cancel nothing;
- redaction vectors give the same output in every SDK;
- the component suite's `obs` profile checks the same from outside for every component: `CP-OBS-01` (an inbound `traceparent` parents the server span), `CP-OBS-02` (log fields, levels by code), `CP-OBS-03` (`/metrics` names and labels), `CP-OBS-04` (redaction), `CP-OBS-05` (`LOG_LEVEL`); in a shell, `CP-SHELL-04`, `CP-SHELL-09`, `CP-SHELL-10`;
- an audit event exists if and only if the business transaction committed.

Infrastructure: no `:latest` image in the infra and observability compose files. On a real machine: sales → inventory → finance appears in Tempo as one trace plus its links.

## Decision records

- [0103 One locked stack inside each language](../02-decisions/01-architecture/0103-locked-stack-per-language.md): one metrics registry per module.
- [0106 Infrastructure is not a component](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md): the observability stack runs outside the component graph.
- [0108 One shell, one repository, one image, one member list](../02-decisions/01-architecture/0108-one-repository-per-shell.md): per-member identity inside a shell.
- [0504 One error object, identified by a reason from a catalogue](../02-decisions/05-runtime/0504-error-model-and-reason-catalogue.md): log levels follow the status; internal errors are logged, never returned.
- Planned, not yet numbered: "audit records are business data and travel through the outbox".

## Known limits

- An asynchronous flow is several traces joined by links, not one tree.
- Prometheus scrapes one port per container; a shell must serve the aggregated endpoint, or only one member is visible.
- Log collection depends on the container runtime's log driver; logs written while the collector is down are read later only if the runtime keeps them.
- Audit becomes queryable only once `infra/audit` exists; until then the audit events stay in each producer's outbox, the source of truth for replay ([12-event-bus.md](12-event-bus.md)).
- Sampling, when enabled, applies per trace; a sampled-out request still has its logs and metrics.
