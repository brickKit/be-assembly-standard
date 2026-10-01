[English](../../../en/02-decisions/01-architecture/0019-infrastructure-is-not-a-component.md) · [中文](0019-infrastructure-is-not-a-component.md)

# 0019 基础设施不是组件

## 决策

事件总线（NATS）、对象存储服务（RustFS，经由 S3 API）、网关（Traefik）和可观测性全家桶是运行在组件图之外的基础设施（`make up`；可观测性全家桶用 `make obs-up`）；它们不是 brickKit 组件，也从不出现在 `brickkit.yaml` 里。组件通过共享配置键——`NATS_URL`、`S3_URL`、`OTEL_BASE_URL`——访问它们，这些值在 `config/vars.yaml` 中只写一次（见[配置约定](../../01-conventions/04-configuration.md)）。

## 理由

它们里面没有一行我们的代码：每一个都是官方镜像加一份配置文件。把它包成组件，就多了一个什么都不装、却要维护版本和发布的仓库，还把基础设施放进依赖图，让每个组件都依赖它。作为配置，指向另一个实例只是改一个值。对象存储按 S3 API 访问，所以 RustFS、MinIO、S3 或 OSS 之间切换只需改 `S3_URL` 和凭据。换事件总线产品则是一次迁移——SDK 要换客户端库——不是改一个设置。

## 挡下什么

- `infra/nats`、`infra/gateway`、`infra/otel-collector` 或 `infra/grafana` 组件
- "把网关放进 `brickkit.yaml`，让它跟其他东西一起启动"
- 组件对事件总线或存储服务声明依赖边
- "改一个设置就把 NATS 换成 Kafka"
- 在组件代码里读取带产品名的地址变量（`MINIO_*`、`RUSTFS_*`）

## 何时重新讨论

我们为其中某一项写了必须随它一起运行的真实代码时（比如有独立发布周期的自定义网关插件）。那份代码成为组件；基础设施本身仍然不是。
