[English](../../../en/02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md) · [中文](0106-infrastructure-is-not-a-component.md)

# 0106 基础设施不是组件

**状态**：为 3.0.0 修订（事件总线通过按 URL scheme 选用的 SDK 适配器更换）；已决定，随 3.0.0 统一升级落地。

## 决策

事件总线（NATS JetStream）、对象存储服务器（RustFS，通过 S3 API 访问）、网关（Traefik）、可观测性栈、身份提供方服务器（Casdoor、Keycloak）和 OpenFGA 服务器，都是在组件图之外运行的基础设施（`make up` 启动；可观测性栈用 `make obs-up`）。它们不是 brickKit 组件，也从不出现在 `brickkit.yaml` 里。组件通过共享配置键访问它们，这些键在 `config/vars.yaml` 里只写一次（`EVENT_BUS_URL`，缺省时回退到 `NATS_URL`；`S3_URL`；`OTEL_BASE_URL`），见[配置约定](../../01-conventions/04-configuration.md)。

每一样怎么换，取决于它的端口（[01-ports-and-adapters.md](../../04-foundations/01-ports-and-adapters.md#选择)）：

| 基础设施 | 怎么换 |
|---|---|
| 对象存储、遥测后端、数据库引擎 | 换一个讲同一标准协议的产品：改地址和凭据 |
| 事件总线 | 编译进每个官方 SDK 的适配器，按 `EVENT_BUS_URL` 的 scheme 选用（默认 `nats://` 即 JetStream；`postgres://…?schema=be_bus` 是 PostgreSQL 队列，阶段 06 内建；`kafka://` 预留）。适配器只有通过 `tools/be-acceptance/conformance/bus/` 才能用 |
| IdP 服务器、OpenFGA 服务器 | 前面那个槽位族成员（[0209](../02-permissions/0209-authz-is-a-slot-family.md)、[21](../../04-foundations/21-identity-provider.md#选择)） |

## 理由

这些东西里没有一行我们自己的代码：每一个都是官方镜像加一份配置文件。把其中一个包成组件，只会多出一个需要打版本、发布却空无一物的仓库，还会把基础设施放进依赖图，让每个组件都依赖它。作为配置，指向另一个实例只是改一个值。总线是唯一一处换产品需要代码的地方，所以那份代码只在 SDK 里写一次，并由一致性套件把关；组件从不知道自己跑在哪个适配器上，同一项目的所有组件用同一个适配器。

## 挡下什么

- `infra/nats`、`infra/gateway`、`infra/otel-collector`、`infra/grafana` 或 `infra/openfga-server` 组件
- "把网关放进 `brickkit.yaml`，让它和其他东西一起启动"
- 组件对事件总线、存储服务器或 IdP 服务器声明依赖边
- 在 Kafka 适配器出现并通过总线套件之前，"改一个设置就把 NATS 换成 Kafka"；同一项目里两个组件用不同的总线适配器
- 组件直接 import 总线客户端或适配器包，而不是经 SDK 发布
- 在组件代码里读取某个产品专属的地址变量（`MINIO_*`、`RUSTFS_*`）

## 何时重新讨论

我们写了必须作为其中某一项的一部分运行的真正代码（比如一个有自己发布周期的自定义网关插件）时。那份代码会成为组件；基础设施本身仍然不是。

完整分析：[01-ports-and-adapters.md，选择](../../04-foundations/01-ports-and-adapters.md#选择)；总线见 [12-event-bus.md，选择](../../04-foundations/12-event-bus.md#选择)。
