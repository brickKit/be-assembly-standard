[English](../../../en/02-decisions/01-architecture/0101-no-imports-between-components.md) · [中文](0101-no-imports-between-components.md)

# 0101 组件之间禁止 import

**状态**：为 3.0.0 修订（新增族契约包）；已决定，随 3.0.0 统一升级落地。

## 决策

一个组件的代码绝不 import 另一个组件的代码。能以代码形式跨越组件边界的恰好三类包：

| 类别 | 例子 | 可以包含什么 |
|---|---|---|
| 官方 SDK | `be-sdk-go`、`be-sdk-python`、`be-sdk-ts` | 实现组件协议的运行时（[0109](0109-language-neutral-component-protocol.md)） |
| 组件发布的生成契约包 | `gen/<domain>/<name>` | 纯 `protoc` 产物：消息类型和客户端 stub，不含逻辑 |
| 槽位族的契约包 | `contract-infra-authz`、`contract-infra-iam` | 只有生成代码和契约文件，没有逻辑、没有默认行为 |

其余一律通过契约走 gRPC 或 HTTP——两个组件被放进同一个外壳时也一样。SDK 从 `be-protocol` 拷贝的协议向量和 schema 是测试数据，不是代码，不算第四类。

## 理由

每个组件都必须能单独启动，外壳只能把 N 个进程变成 1 个。两个组件一旦共享代码，不会出错也没有任何警告（合并后的系统甚至跑得更快），直到某天要把它们拆开部署时才发现拆不动，那时的代价是重写。生成契约包之所以直接 import 而不是复制一份，是因为同一份生成代码的两个副本进了同一个进程，会把同一批 proto 类型注册两次，进程启动即 panic。族契约不属于任何一个成员：每个成员都实现它，每个调用方都调用它，所以它必须放在一个独立的包里，并具备另外两类的同样性质。`make gates` 会扫描每个组件的 import。

## 挡下什么

- "反正在同一个外壳里，直接调函数就行"：外壳成员之间跳过 gRPC
- 两个组件共用的 `models` / `common` / `utils` / `types` 公共包
- 为了复用一个工具函数去 import 别的组件的业务、仓储或服务包
- 把别的组件的 `.proto` 复制到自己仓库里生成 stub（vendoring），而不是 import 它的 `gen` 包
- import 某一个槽位成员自己的 `gen` 包，而不是族契约包；族契约包里带逻辑或默认行为
- 为了省一次接口调用直接读别的组件的表（见 [0102](0102-one-schema-per-component.md)）

## 何时重新讨论

业务代码永远不重新讨论。若要新增第四类可共享的包，它必须与上面三类具备同样的性质：不含业务逻辑、没有组件语义、在一个进程里只有一份也安全。

完整分析：[27-shells.md，选择](../../04-foundations/27-shells.md#选择)；族契约见 [20-authorization-provider.md，选择](../../04-foundations/20-authorization-provider.md#选择)。
