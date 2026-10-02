[English](../../../en/02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md) · [中文](0302-contracts-are-additive-only.md)

# 0302 契约只做加法

**状态**：为 3.0.0 修订（对外 REST 的版本策略、reason 目录）；已决定，随 3.0.0 统一升级落地。

## 决策

已发布的契约（`.proto`、OpenAPI、`contracts/events/*.json`、`contracts/errors.yaml`）只增不减：新字段、新 RPC、新端点、新事件 subject、新错误 reason。字段永不删除、改名、改类型或改编号，subject 和 reason 永不删除或复用，字段的含义永不改变。新字段对现有消费方的逻辑而言必须是可选的。每个组件里的 `make contract-check`（proto、OpenAPI）和本项目的 `make gates`（事件）在出现破坏性变更时失败。

**破坏性变更**由人决定，并发布在旧契约旁边，从不替换它：

| 契约 | 新的大版本 |
|---|---|
| REST | 新路径前缀 `/<domain>/<name>/v2/…`，与旧路径并存；旧操作带 `Deprecation` 和 `Sunset` 头答复，过了下线日期才删除 |
| gRPC | 新的带版本包 `<domain>.<name>.v2`，与 `v1` 并存 |
| 事件 | 新 subject 版本（`….v2`），与旧的并存发布 |

对外 API 开放后，这些规则就是对外部调用方公开的承诺。

## 理由

消费方（包括客户 Fork，以及以后客户的其他系统）会继续对着旧版本运行，并忽略它们不认识的字段。破坏性变更迫使每个消费方同步修改、同步发布；漏改的事件消费方会在运行时失败，而不是构建时。路径前缀加 `Deprecation` 和 `Sunset`，让外部调用方看得见变化要来，并按自己的节奏迁移。

## 挡下什么

- "把这个字段改个名""把它的类型改成 int""复用这个 tag 编号"
- "把废弃的字段 / RPC / subject / reason 删掉"
- 把一个已有的可选字段改成必填
- 名字不变，却改变已有字段的含义或单位
- 用请求头或查询参数而不是新路径前缀做 REST 的破坏性变更；在 `Sunset` 日期之前删除旧操作

## 何时重新讨论

永不原地修改。错得无法修补的契约，按上表在旧契约旁边出一个新大版本。3.0.0 的一次性重建（[0305](0305-one-shot-baseline-rebuild-for-3-0-0.md)）是唯一的例外，并且列明了它打破的每一处。

完整分析：[15-user-api-and-errors.md，版本策略](../../04-foundations/15-user-api-and-errors.md#版本策略)；事件见 [13-event-contracts.md，演进](../../04-foundations/13-event-contracts.md#演进)。
