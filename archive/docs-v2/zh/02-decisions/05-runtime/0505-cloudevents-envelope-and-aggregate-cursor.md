[English](../../../en/02-decisions/05-runtime/0505-cloudevents-envelope-and-aggregate-cursor.md) · [中文](0505-cloudevents-envelope-and-aggregate-cursor.md)

# 0505 信封是二进制模式的 CloudEvents；消费者按聚合流各记一个游标

**状态**：已决定，随 3.0.0 统一升级落地。

## 决策

- **信封是 CloudEvents 1.0 二进制模式**：名为 `ce-*` 的消息头（`ce-id` 是 UUIDv7，`ce-source`，`ce-type` 即 subject，`ce-time`，`ce-subject` 即聚合 ID，`ce-dataschema`，`ce-aggregatetype`，`ce-aggregateversion`，`ce-causationid`，`ce-hopcount`，交易单据还有 `ce-legalentity`），加上 `content-type` 和 W3C `traceparent`。payload 就是业务 JSON 对象，别无其他。能派生的头一律由运行时填写；没有信封的消息进死信。
- **每个事件都在契约里声明它的聚合类型**（`x-aggregate-type`），同一聚合类型的所有 subject 共用一个严格递增的聚合版本。
- **消费者的游标以 `(consumer, aggregate_type, aggregate_id)` 为键**，放在它自己 schema 的 `besdk_event_cursor` 里，与 handler 的写入在同一个事务里推进。比游标旧的版本直接跳过。
- **默认是状态模式**：handler 写成"把我的投影推进到该聚合第 v 版的状态"。序列模式（按序处理每一次变化）预留。
- **截断循环**：`ce-hopcount` 超过 10 的事件进死信。
- **注册表就是契约文件**，在每个组件里（`contracts/events/*.json`），构建时检查；没有运行时的 schema 注册服务。

## 理由

信封必须经得起换 broker（[0106](../01-architecture/0106-infrastructure-is-not-a-component.md)）；CloudEvents 的命名是中立的选择，对我们点名的每个 broker 都有绑定，我们用的每种总线也都能带头。按 subject 记游标，一旦同一聚合的事件经不同 subject 乱序到达就会出错：finance 先收到 `cancelled` 再收到 `created`，会给已取消的订单记一笔应收。按聚合流建键，无论到达顺序如何都是更新的版本胜出，任何乱序和重复之后的最终状态都等于按序处理的结果。3.0.0 之前，信封走 `X-` 头，没有哪个生产者把它填全，也没有哪个事件声明聚合类型。

## 挡下什么

- `X-` 头，或在 payload 里重复一遍信封；把业务数据放进头
- 按 subject、或只按事件 id 建键的游标或 inbox
- 写成"应用这次变化"、旧版本晚于新版本到达时就出错的 handler
- 靠 broker 的顺序来保证正确性的消费者
- 运行时的 schema 注册服务

## 何时重新讨论

出现第一个需要按序处理每一次变化的消费者（为它建序列模式），或外部方订阅事件（从契约文件生成 AsyncAPI；线上什么都不变）时。

完整分析：[13-event-contracts.md，选择](../../04-foundations/13-event-contracts.md#选择)；游标见 [11-consistency-across-components.md，消费者游标](../../04-foundations/11-consistency-across-components.md#消费者游标)。
