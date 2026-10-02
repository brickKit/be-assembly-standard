[English](../../../en/02-decisions/05-runtime/0506-at-least-once-delivery-and-streams.md) · [中文](0506-at-least-once-delivery-and-streams.md)

# 0506 事件至少送达一次；流按 subject 第一段划分

**状态**：已决定，随 3.0.0 统一升级落地。

## 决策

- **发布只经 outbox**：`besdk_outbox` 与业务变更在同一个事务里写入，泵在提交后发布，只有总线确认已持久化后才把这一行标为已发布。总线不可用时，行留着等待重试，永不丢弃。
- **送达至少一次。** 在消费者库里的效果实际上只发生一次，因为它的游标与写入在同一个事务里推进（[0505](0505-cloudevents-envelope-and-aggregate-cursor.md)）；带外部副作用的 handler 按业务键幂等。不承诺恰好一次。
- **生产者的 outbox 是回放的事实源**，发布后保留 14 天；broker 的保留期只是传输缓冲。更早的历史经生产者的 `List` 回填，不作为事件重放。
- **每个 subject 第一段一个流**（`BE_ERP`、`BE_MDM`……，以及给旧 subject 用的 `BE_SALES`、`BE_FINANCE`），由第一个需要它的人创建，"没有就建、有就不碰"，在迁移步骤里执行一次，启动时再执行一次。默认值：7 天、1 GiB、丢弃旧消息、10 分钟去重窗口；死信在 `BE_DLQ`，保留 30 天。
- **每个（组件，subject）一个 durable**，单跑、外壳内、每个副本都用同一个名字。新建的 durable 从流里还剩的全部消息开始（`DeliverAll`）。提交后才确认；出错时按退避 nak；投递 8 次之后、或遇到永久性错误时，消息进死信。
- **尽力而为的信号**（authz 的 poke）走 core NATS：可以丢，从不持久化。

## 理由

没有持久化时，没有订阅者在线的发布也"成功"然后丢失，每个副本还都收到每一条消息；这就是 3.0.0 之前的状态。至少一次加幂等消费者，是每个主流 broker 真正能保证的东西，而且不依赖 broker。按第一段划分的流跟随 subject 而不是生产者，所以一个槽位族的多个成员可以发布同一个 subject，运维也能在没有登记表的情况下预建并调优某个流。`DeliverAll` 让新装的消费者补收最近七天。

## 挡下什么

- 直接往总线发布，或删除尚未得到确认的 outbox 行
- 假设恰好一次送达的消费者，或没有幂等键的外部副作用
- 每个生产组件一个流、中心化的流登记表，或只能靠 `make nats-init` 建流
- 单跑与外壳、或各副本之间名字不同的 durable
- 重放早于 outbox 保留期的事件，而不是回填

## 何时重新讨论

某个客户统一用 Kafka（建 Kafka 适配器并通过总线套件），或某个流经测量的负载超过约每秒 50,000 条（按 subject 映射拆分，仍用 JetStream）时。

完整分析：[12-event-bus.md，选择](../../04-foundations/12-event-bus.md#选择)和[流](../../04-foundations/12-event-bus.md#流)。
