[English](../../en/04-foundations/13-event-contracts.md) · [中文](13-event-contracts.md)

# 事件契约

事件在线上是什么样：放在消息头里的 CloudEvents 信封，subject 命名，每个消费者游标都依赖的聚合类型与版本，两种消费模式，契约文件及其演进，载荷必须带什么、绝不能带什么，以及能有多大。读者是要新增或修改事件的人、写消费者的人，以及要在一种新语言里实现信封的人。

## 范围

- **在本文：** 消息头、subject 名、聚合类型与版本、状态消费和序列消费、`contracts/events/*.json`、schema 演进、载荷规则与大小。
- **不在本文：** 事件怎么存储和投递（[12-event-bus.md](12-event-bus.md)）；outbox 和消费者游标（[11-consistency-across-components.md](11-consistency-across-components.md)）；与所有其他契约共用的字段类型，例如金额、日期和标识符（[06-money-quantity-units.md](06-money-quantity-units.md)、[05-time-and-calendars.md](05-time-and-calendars.md)、[04-identifiers-and-numbering.md](04-identifiers-and-numbering.md)）。

## 选择

- **CloudEvents 1.0 的 binary 模式：** 信封放在名为 `ce-*` 的消息头里，载荷就是业务 JSON 对象，别无其他。NATS、Kafka 和 PostgreSQL 队列都能携带消息头，所以信封不随 broker 改变。
- **每个事件声明它的聚合类型**，同一聚合类型的所有 subject 共用一个严格递增的聚合版本。
- **默认状态模式：** 消费者把自己的投影推到聚合在收到的版本时的状态，并跳过一切更旧的。序列模式先保留。
- **注册表就是每个组件里的契约文件** `contracts/events/*.json`，在构建时由门禁检查。没有运行期的 schema 注册中心。
- **schema 只增不减**；破坏性变更是一个新的 subject 版本，和旧的并排发布。

**状态**：已定；随组件协议和 3.0.0 统一升级落地。今天信封走的是 `X-` 头（`X-Aggregate-Id`、`X-Version`、`X-Trace-Id`、`X-Causation-Id`、`X-Hop-Count`），没有生产者填 trace、causation 或 hop 字段，也没有事件声明它的聚合类型。

## 端口契约

### 消息头

| 消息头 | 值 | 由谁填 |
|---|---|---|
| `ce-specversion` | `1.0` | 运行时 |
| `ce-id` | 事件 ID，一个 UUIDv7；同时也是 broker 用来去重的消息 ID | 运行时，在写 outbox 行时 |
| `ce-source` | 生产组件的 ID（`erp/sales`）；外壳里是成员的 ID | 运行时 |
| `ce-type` | subject（`sales.order.created.v1`） | 生产者 |
| `ce-time` | `occurred_at`，UTC 的 RFC 3339 | 运行时 |
| `ce-subject` | 聚合 ID | 生产者 |
| `ce-dataschema` | `<组件 ID>@<版本>/contracts/events/<文件>#<subject>`：载荷 schema 所在的位置，是一个引用，不是要去抓取的 URL | 运行时 |
| `content-type` | `application/json` | 运行时 |
| `ce-aggregatetype` | 声明的聚合类型（`erp.sales.order`） | 运行时，取自契约 |
| `ce-aggregateversion` | 这次变更之后聚合的版本，十进制整数 | 生产者 |
| `ce-causationid` | 产生这个事件时正在处理的那个事件的 `ce-id`；来自请求时为空 | 运行时，取自上下文 |
| `ce-hopcount` | 起因事件的跳数加 1；来自请求时为 0。超过 10 时消息进死信 | 运行时，取自上下文 |
| `ce-legalentity` | 交易单据的法人；这类事件必填，缺了它的事件消费方直接送进死信 | 运行时，取自 payload |
| `ce-sequence` | 为序列模式保留：在 outbox 里维护的按聚合计数器，独立于业务版本 | 暂不设置 |
| `ce-tenantid` | 保留：一个部署就是一个租户，所以不设置 | 不设置 |
| `traceparent`、`tracestate` | 生产 span 的 W3C trace context（[23-observability.md](23-observability.md)） | 运行时 |

- 消息头名字一律小写。CloudEvents 扩展属性的名字只能是小写字母和数字，所以没有下划线。
- **不读旧信封。** 所有生产者和消费者在同一次 3.0.0 统一升级里换到这个信封，所以只带 `X-` 头或缺 `ce-id` 的消息属于违反契约，直接进死信。
- 信封里别无其他：业务数据绝不放进消息头，信封也绝不在载荷里重复一遍。

### subject 命名

- `<domain>.<聚合或组件>[.<更多>].<动作>.v<n>`：小写，每段由 `[a-z0-9_]` 组成，第一段是一个域（它决定流，[12](12-event-bus.md#流)），最后一段是 `v<n>`。例子：`erp.inventory.adjusted.v1`、`infra.workflow.task.completed.v1`、`crm.opportunity.stage_changed.v1`。
- **聚合类型是声明出来的，绝不从 subject 里解析：** `infra.notification.dispatch.im.v1` 就没法可靠地拆分。
- 旧 subject `sales.*` 和 `finance.*` 保留原名；契约只增不减，每个第一段就有自己的流。
- 一个 subject 由一个组件发布，或者由一个槽位族的每个成员发布（`integration.im.result.v1`）。

### 聚合类型与版本

- 同一个生产者的同一聚合类型的所有 subject，共用一个严格递增的 `aggregate_version`。行的业务版本（每次写入都加一）就符合要求，因为状态模式容忍跳号。
- 每个实例只会发出一个事件的聚合（针对一张订单的信用决定），声明一个自己的聚合类型（`erp.finance.credit_decision`），而不是借用别人的聚合类型、再把版本固定为 1。
- 消费者游标以 `(consumer, aggregate_type, aggregate_id)` 为键（[11](11-consistency-across-components.md#消费者游标)）。

### 消费模式

| 模式 | 消费者收到的 | 处理规则 | 状态 |
|---|---|---|---|
| `state` | 不一定是每个版本，可能迟到，但绝不比已有的旧 | "把我的投影推到版本 v 时的状态"；跳过更旧的版本是正确的 | 默认 |
| `sequence` | 每个版本，按顺序 | 遇到跳号就等：带延迟 nak，超过限度后回源读取或进死信 | 保留；为第一个真实消费者而建 |

### 契约文件

每个组件在 `contracts/events/<name>.events.json` 里列出它的事件：一段 `envelope` 描述和一个 `events` 数组。每个事件条目有：

| 键 | 含义 |
|---|---|
| `subject` | 同上 |
| `aggregate_type` | 声明的聚合类型（新增；必填） |
| `consumption` | `state`（默认）或 `sequence`（新增） |
| `grade` | `core`（业务关键：持久化、去重、可能进死信）或 `peripheral`（信息性的旁路事件） |
| `note` | 谁消费它、为什么，用文字写 |
| `payload` | 描述载荷的 JSON Schema（2020-12）对象 |

门禁（`make gates` 的一部分）：

- 只做加法：删字段、改类型或删 subject 会失败（已就位）；
- 每个事件都声明 `aggregate_type`（计划中）；
- 组件代码发布的 subject 与它契约文件里的恰好一致（计划中）。

### 载荷规则

- 一个 JSON 对象。未知字段被消费者忽略，缺失的可选字段取默认值：消费者宽松读取。
- **字段格式：** 金额和数量用十进制字符串，并配上币种或单位（[0301](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md)、[06](06-money-quantity-units.md)）；标识符用字符串（[04](04-identifiers-and-numbering.md)）；时刻用 UTC 的 RFC 3339；业务日期用 `YYYY-MM-DD`。
- **每个交易类事件都带 `legal_entity_id`**，以及它的消费者需要的业务日期（`document_date`、`posting_date`）。消费者按这些日期记账，绝不按自己处理事件的时间（[05-time-and-calendars.md](05-time-and-calendars.md)）。
- **为状态模式带够状态：** 事件带上消费者推到聚合在该版本时状态所需的内容，而不只是变更的名字。
- **事件是系统数据。** 载荷绝不原样展示给人：由事件生成的通知要按接收人脱敏，或者只带一个链接，因为价格这类字段可能对那个接收人隐藏（[20-authorization-provider.md](20-authorization-provider.md)）。
- **不带密钥，不带 token，个人数据只带消费者需要的最少部分。**
- **大小：** 64 KiB 以内是常态。更大的内容放进对象存储，事件只带一个指向它的引用（claim check；对象存储那篇文档计划作为第 22 篇）。broker 的硬上限是 8 MB，含消息头。

### 演进

- 新增字段或新 subject 永远允许。字段绝不删除、改名、改类型或赋予新含义（[0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)）。
- 破坏性变更是一个新 subject `….v2`。生产者在同一个事务里同时写 `v1` 和 `v2` 两行 outbox，直到没有消费者再读 `v1`；然后由人决定停掉 `v1`。版本放在 subject 里，绝不放在消息头里。

## 备选方案

| 方案 | 优点 | 缺点 |
|---|---|---|
| **CloudEvents binary 模式加 JSON 载荷，契约文件在构建时检查**（选用） | 消息头名字不绑定 broker，NATS 和 Kafka 都有标准绑定；载荷在任何工具、任何语言里都可读；不需要运行期服务 | schema 检查发生在构建时，而不是在线上 |
| CloudEvents structured 模式（信封放在 JSON 正文里） | 一整块，不需要消息头 | 每个消费者都要从正文里解析出信封；载荷不再是纯粹的业务对象 |
| 我们自己的 `X-` 头（今天） | 已经就位 | 名字不绑定任何标准；换个 broker 就没有意义 |
| Avro 或 Protobuf 载荷加运行期 schema 注册中心（Confluent） | 紧凑；发布时强制兼容性 | 多一个要跑的服务；调试时二进制载荷不可读；每种语言都要一个注册中心客户端 |
| 用 AsyncAPI 文档作为契约格式 | 标准的描述方式，有文档工具 | 描述的是通道，而不是我们的聚合规则；以后可以从我们的文件生成 |
| 事件溯源（事件作为记录系统） | 完整历史，可回放出任意状态 | 每个组件都要围绕事件存储重建；我们的状态在业务行上（[11](11-consistency-across-components.md)） |

## 为什么选它

- **信封必须在换 broker 后依然成立**（[12](12-event-bus.md)）；CloudEvents 的命名是中立的选择，并且对我们提到的 broker 都有已发布的绑定。
- **JSON 载荷**人能读、AI 能读、每种语言不用生成代码就能读，金额、日期和标识符的规则也和所有其他契约一样。
- **声明聚合类型**才让按聚合流设游标成为可能，有了它，跨 subject 乱序到达的事件也能被正确处理。
- **构建时检查**放在每个组件的仓库里，让注册表和代码在一起，不需要跑任何服务。

## 为什么不选其他

- **structured 模式**把传输数据混进业务对象，还让每个消费者都去解析它。
- **`X-` 头**没法有意义地带到 Kafka 或 PostgreSQL 队列上。
- **Avro/Protobuf 加注册中心**多出一个常驻服务和二进制载荷，换来的体积收益在我们的量级上用不着。
- **AsyncAPI** 会是同一件事的第二份描述；有外部方订阅时，可以从契约文件生成。
- **事件溯源**要重写每个组件的持久化，换来的好处我们已经从 outbox 和业务行上得到了。

## 什么时候换

- **有外部方订阅事件**（路线图上的对外 API）：从契约文件生成 AsyncAPI；线上什么都不变。
- **出现第一个需要按顺序拿到每一次变更的消费者**：为它建序列模式（`ce-sequence`、跳号处理）。
- **实测载荷成本变得重要**（在 ERP 的量级上不太可能）：二进制载荷是一个新的 subject 版本，带不同的 `content-type`。

## 怎么换

- 消息头名字由协议固定，不换。
- 载荷格式或 schema 的变更是一个新的 subject 版本（`.v2`），和旧的并排发布；消费者一个一个地迁；没有一刀切的切换日。
- 序列模式存在之后，按事件逐个通过声明 `consumption: sequence` 加上；同一 subject 的状态模式消费者不受影响。

## 一致性测试

计划中，放在 `tools/be-acceptance/conformance/bus/`（信封用例在每个适配器上跑）和组件协议套件里：

- 整套消息头在每个适配器上往返不变；
- 只带 `X-` 头或缺 `ce-id` 的消息进死信；
- 在处理函数里发布时，`ce-causationid` 设为被处理事件的 ID，`ce-hopcount` 加一；跳数超过 10 的进死信；
- 在一个生产者的 outbox 里，同一聚合类型的所有 subject 上，聚合版本严格递增；
- 门禁：没有 `aggregate_type` 的事件失败；删掉字段失败；代码里发布、契约里却没有的 subject 失败；
- **每个消费者一个性质测试**（[06-testing.md](../01-conventions/06-testing.md#l2-业务规则测试)）：打乱并重复的投递，最终状态与一次按序投递相同。

## 相关决策

- [0301 金额是十进制字符串；列表按游标分页](../02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md)：载荷里的金额。
- [0302 契约只做加法](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)：事件 schema 和 subject。
- 计划中、尚未编号："事件信封是 binary 模式的 CloudEvents，消费者游标以聚合流为键"。

## 已知限制

- **不保证顺序**：状态模式能容忍；严格顺序要等序列模式。
- **`ce-dataschema` 是一个引用**，不是可抓取的 URL：没有注册中心服务来解析它。
- **消息头计入 broker 的大小上限。**
- **旧的第一段**（`sales`、`finance`）和 `erp.inventory.*` 仍不一致；这是契约只做加法的代价。
- **`ce-tenantid` 只保留、不使用：** 池化的多租户部署要先用上它。
