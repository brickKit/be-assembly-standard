[English](../../../en/02-decisions/05-runtime/0501-no-network-inside-a-transaction.md) · [中文](0501-no-network-inside-a-transaction.md)

# 0501 事务里不发网络调用

**状态**：已决定，随 3.0.0 统一升级落地。

## 决策

一个工作单元持有打开的数据库事务期间，不发任何网络调用：不走 gRPC、不走用户面 HTTP、不调第三方 HTTP、不直接往总线发布。事务要在数据库之外产生效果，只有两条路，都是在同一个事务里写的一行：

| 出口 | 什么时候执行 | 契约 |
|---|---|---|
| 一行 outbox | 提交后发布事件 | [0506](0506-at-least-once-delivery-and-streams.md) |
| 一行任务队列 | 提交后在事务外执行命令，按退避重试，一直失败就升级处理 | [0508](0508-background-work-only-through-jobs.md) |

所以，业务变更之后必须发生的远程副作用永远是一条入队的命令，从不是"提交后调一下，碰运气"。官方 SDK 强制这一条：事务里任何出站调用都拒绝开始（`INTERNAL` / `NETWORK_IN_TX`），同一工作单元里再开第二个事务也失败（`INTERNAL` / `NESTED_TX`）。对其他语言的组件，这是一条 INTERNAL 协议规则，由作者说明怎么守住（[0109](../01-architecture/0109-language-neutral-component-protocol.md)）。

## 理由

事务里发网络调用，会在下游的耗时内一直持有行锁，于是这些行上的其他请求全都排在它后面；重试事务体会把调用再发一遍；事件 handler 超过总线的确认等待时间就会被重投、执行两次。连接池有上限时，等第一条连接时再占第二条，正是池子自己死锁的方式。把效果写成同一事务里的一行，它就当且仅当业务变更提交时才存在。3.0.0 之前，有三个消费者在持有事务时调用别的组件，还有三处远程调用是"提交后尽力而为"。

## 挡下什么

- 在 `BEGIN` 和 `COMMIT` 之间调用别的组件、IM 服务或任何 HTTP 端点
- 绕过 outbox 直接往总线发布
- 提交后尽力而为地调一下，失败了也没有东西重试
- 开嵌套事务，或在一个工作单元里同时持有两条连接
- "就这一个 handler"关掉守卫

## 何时重新讨论

规则本身永不重新讨论。真正需要在提交前拿到同步远程答复的步骤（用户等着的预留），按 try-confirm-cancel 设计，带幂等键，放在事务之外。

完整分析：[10-local-transactions.md，端口契约](../../04-foundations/10-local-transactions.md#端口契约)；异步出口见 [11-consistency-across-components.md，选择](../../04-foundations/11-consistency-across-components.md#选择)。
