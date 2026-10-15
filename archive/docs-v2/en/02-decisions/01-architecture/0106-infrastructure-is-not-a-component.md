[English](0106-infrastructure-is-not-a-component.md) · [中文](../../../zh/02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)

# 0106 Infrastructure is not a component

**Status**: revised for 3.0.0 (the event bus is swapped through an SDK adapter chosen by URL scheme); decided, lands with the 3.0.0 sweep.

## Decision

The event bus (NATS JetStream), the object storage server (RustFS, through the S3 API), the gateway (Traefik), the observability stack, the identity provider servers (Casdoor, Keycloak) and the OpenFGA server are infrastructure that runs outside the component graph (`make up`; the observability stack with `make obs-up`). They are not brickKit components and never appear in `brickkit.yaml`. Components reach them through shared configuration keys written once in `config/vars.yaml` (`EVENT_BUS_URL`, falling back to `NATS_URL`; `S3_URL`; `OTEL_BASE_URL`), see [configuration conventions](../../01-conventions/04-configuration.md).

How each is replaced follows its port ([01-ports-and-adapters.md](../../04-foundations/01-ports-and-adapters.md#choice)):

| Infrastructure | Replaced by |
|---|---|
| object storage, telemetry backend, database engine | a product behind the same standard protocol: change the address and credentials |
| event bus | an adapter compiled into every official SDK, chosen by the scheme of `EVENT_BUS_URL` (`nats://` JetStream by default; `postgres://…?schema=be_bus` the PostgreSQL queue, built in phase 06; `kafka://` reserved). An adapter is admitted only when it passes `tools/be-acceptance/conformance/bus/` |
| IdP server, OpenFGA server | the slot-family member that fronts it ([0209](../02-permissions/0209-authz-is-a-slot-family.md), [21](../../04-foundations/21-identity-provider.md#choice)) |

## Why

None of these contains any code of ours: each is an official image plus a configuration file. Wrapping one in a component adds a repository to version and release that holds nothing, and puts infrastructure into the dependency graph where every component would depend on it. As configuration, pointing at another instance is one value. The bus is the one place where a product switch needs code, so that code lives once in the SDKs behind a conformance suite; a component never knows which adapter it runs on, and every component of a project uses the same one.

## What this rules out

- An `infra/nats`, `infra/gateway`, `infra/otel-collector`, `infra/grafana` or `infra/openfga-server` component
- "Put the gateway in `brickkit.yaml` so it starts with everything else"
- A component declaring a dependency edge on the event bus, the storage server or an IdP server
- "Swap NATS for Kafka by changing a setting" before a Kafka adapter exists and passes the bus suite; two components of one project on different bus adapters
- A component importing a bus client or adapter package directly instead of publishing through the SDK
- Reading a product-specific address variable (`MINIO_*`, `RUSTFS_*`) in component code

## Revisit only if

We write real code that has to run as part of one of them (for example a custom gateway plugin with its own release cycle). That code becomes a component; the infrastructure itself still does not.

Full analysis: [01-ports-and-adapters.md, Choice](../../04-foundations/01-ports-and-adapters.md#choice); the bus in [12-event-bus.md, Choice](../../04-foundations/12-event-bus.md#choice).
