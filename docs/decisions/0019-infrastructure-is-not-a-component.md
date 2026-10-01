[English](0019-infrastructure-is-not-a-component.md) · [中文](0019-infrastructure-is-not-a-component.zh.md)

# 0019 Infrastructure is not a component

## Decision

The event bus (NATS), the object storage server (RustFS, through the S3 API), the gateway (Traefik) and the observability stack are infrastructure that runs outside the component graph (`make up`); they are not brickKit components and never appear in `brickkit.yaml`. Components reach them through shared configuration keys — `NATS_URL`, `S3_URL`, `OTEL_BASE_URL` — written once in `config/vars.yaml` (see [configuration conventions](../conventions/configuration.md)).

## Why

None of these contains any code of ours: each is an official image plus a configuration file. Wrapping one in a component adds a repository to version and release that holds nothing, and puts infrastructure into the dependency graph where every component would depend on it. As configuration, pointing at another instance is one value. Object storage is addressed through the S3 API, so RustFS, MinIO, S3 or OSS are swapped by changing `S3_URL` and credentials. Changing the event bus product is a migration — a different client library in the SDK — not a setting.

## What this rules out

- An `infra/nats`, `infra/gateway`, `infra/otel-collector` or `infra/grafana` component
- "Put the gateway in `brickkit.yaml` so it starts with everything else"
- A component declaring a dependency edge on the event bus or the storage server
- "Swap NATS for Kafka by changing a setting"
- Reading a product-specific address variable (`MINIO_*`, `RUSTFS_*`) in component code

## Revisit only if

We write real code that has to run as part of one of them (for example a custom gateway plugin with its own release cycle). That code becomes a component; the infrastructure itself still does not.
