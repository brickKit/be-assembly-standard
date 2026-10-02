[English](../../en/04-foundations/12-event-bus.md) · [中文](12-event-bus.md)

# 事件总线

组件之间的事件由哪个消息 broker 承载、它承诺什么样的投递、流、消费者和死信怎么布局、历史怎么回放、背压怎么工作，以及 broker 端口：有了它，同一批组件可以跑在 NATS JetStream 上、PostgreSQL 队列上，以后也可以跑在 Kafka 上。读者是要改事件发布或消费方式的人、运维总线的人，以及要提议换一个 broker 的人。

## 范围

- **在本文：** broker 的选择；投递语义；流、持久消费者、确认、重投与死信；回放；背压；客户端连接参数；尽力而为的信号；broker 端口及其适配器。
- **不在本文：** 事件长什么样（消息头、命名、契约文件、schema 演进）：[13-event-contracts.md](13-event-contracts.md)。让投递在效果上只发生一次的 outbox 和消费者游标：[11-consistency-across-components.md](11-consistency-across-components.md)。组件怎么声明它发布和消费什么：[02-backend.md](../01-conventions/02-backend.md#事件与跨组件写入)。

## 选择

- **NATS JetStream 是默认适配器**（NATS 2.10 或更高，`make up` 已经起好）。
- **投递是至少一次。** 消费者数据库里的效果是只发生一次，因为游标和写入在同一个事务里推进（[11](11-consistency-across-components.md#消费者游标)）。不承诺精确一次。
- **生产者的 outbox 是回放的事实来源**；broker 的保留只是传输缓冲。
- **PostgreSQL 队列适配器现在就建，作为第二个适配器**，带一致性套件：给不想跑 NATS 的小型安装用，给测试用，也用来证明这个端口是真的。**Kafka 适配器等客户带着 Kafka 来时再建。** 不计划 RabbitMQ 和 Pulsar 适配器。
- **适配器由一个共享地址的 scheme 选定**，即 `EVENT_BUS_URL`；组件不变。

**状态**：已定；随组件协议和 3.0.0 统一升级落地。今天事件走的是 core NATS：不持久化，不重投，每个副本都收到每条消息，没有订阅者时发布也"成功"，消息就丢了。服务端已经开启了 JetStream。

## 端口契约

### 选择适配器

| `EVENT_BUS_URL` | 适配器 | 状态 |
|---|---|---|
| `nats://host:4222` | JetStream | 默认 |
| `postgres://host:5432/<db>?schema=be_bus` | PostgreSQL 队列 | 已定，阶段 06 建 |
| `kafka://broker1:9092,broker2:9092` | Kafka | 以后 |

`EVENT_BUS_URL` 是 `config/vars.yaml` 里新增的共享键，以 `$var:EVENT_BUS_URL` 引用（[04-configuration.md](../01-conventions/04-configuration.md#共享连接键)）。没有它时 SDK 用 `NATS_URL`。一个项目的所有组件用同一个适配器：两个适配器就是两条互不相通的总线。

### 每个适配器提供的操作

| 操作 | 语义 |
|---|---|
| ensure stream | 流不存在就创建；绝不修改已有的流 |
| publish | 连同消息 ID 存下一条消息；成功意味着已持久存储；去重窗口内同一个 ID 只存一次 |
| consume | 按 subject 过滤投递给一个具名的持久消费者；共用这个 durable 的副本互相竞争，每条消息只给其中一个 |
| ack / 带延迟的 nak / terminate / in progress | 处理完毕；延迟后重投；永不重投；延长确认截止时间 |
| delivery count | 这条消息被投递了几次 |
| notify / on notify | 尽力而为的信号：不存储，不重投，可能丢失 |

### 流

- **按 subject 的第一段一个流**：名字是 `BE_<第一段的大写>`，subjects 是 `<第一段>.>`。今天有：`BE_ERP`、`BE_MDM`、`BE_CRM`、`BE_INFRA`、`BE_INTEGRATION`，以及给不带 `erp.` 前缀的旧 subject 用的 `BE_SALES`、`BE_FINANCE`。死信：`BE_DLQ`，subjects 是 `dlq.>`。
- **谁先需要谁创建**，"不存在就创建，存在就绝不碰"，在组件的迁移步骤里做（brickKit 在组件启动前用组件自己的镜像和配置运行它），启动时再做一次。运维可以预先建好流并调参；组件找不到流、又没有创建权限时，迁移失败并给出清楚的错误。
- **默认值：** `max_age` 7 天，`max_bytes` 1 GiB，`discard: old`，`duplicate_window` 10 分钟，文件存储，1 个副本（NATS 集群上为 3，由运维设定）。`BE_DLQ`：30 天。
- 流跟着 subject 走，而不是跟着生产组件走，所以一个槽位族的多个成员可以发布同一个 subject（`integration.im.result.v1`）。

### 持久消费者

- **每个（组件，subject）一个 pull 型 durable**，命名为 `<组件 ID，/ 换成 _>__<subject，. 换成 _>`：`erp_finance__sales_order_created_v1`。单跑、外壳里、每个副本上都是同一个名字，所以成员搬进或搬出外壳都保留它的位置。
- **首次创建会投递流里还留着的全部消息**（`DeliverAll`）：新装的消费者会补上最多 7 天的事件。所以新装的 finance 会记账它安装前 7 天内确认的订单。
- `ack_wait` 30 秒；`max_deliver` 8；重投退避 1 秒、10 秒、1 分钟、5 分钟、15 分钟、30 分钟、1 小时；`max_ack_pending` 256；每个订阅同时最多处理 4 条消息，同时受成员的连接预算约束（[10](10-local-transactions.md#端口契约)）；`inactive_threshold` 30 天，所以被移除组件的 durable 会自己消失。
- **处理函数的事务提交之后再确认。** 出错时：按下一档退避延迟 nak。永久性错误（无法解析、违反契约）时：先发布到死信 subject，再 terminate。处理函数运行期间：每 10 秒发一次 "in progress"（`ack_wait` 的三分之一）。

### 死信

- subject 是 `dlq.<durable>.<原 subject>`，在原有消息头之外加上 `be-dlq-reason`、`be-dlq-consumer`、`be-dlq-delivery`。durable 放在 subject 里，是因为一条消息可能在一个消费者里失败、在另一个里成功；只有失败的那个会拿回它。
- 消息在三种情况下进死信：尝试了 `max_deliver` 次之后，遇到永久性错误时，或者跳数超过 10 时（[13](13-event-contracts.md)）。
- `make dlq-ls` 和 `make dlq-replay`（计划中）列出和回放死信。回放时发布到原 subject，消息 ID 加后缀以绕过去重窗口；其他消费者靠自己的游标跳过它。
- `be_dlq_messages_total{subject,consumer}`，附带告警规则模板。

### 回放

- **在流的保留期内：** 用一个从某个时间点开始的临时消费者。
- **超出保留期：** `make events-replay COMPONENT=<id> SUBJECT=<subject> SINCE=<time>`（计划中）读生产者的 outbox，用加了后缀的消息 ID 重新发布；消费者靠游标去重。所以回放不取决于用的是哪个 broker。outbox 在发布后保留 14 天；更早的历史不再按事件回放：新消费者从生产者的 `List` 回填，范围已转冷时读它发布的数据集。

### 发布

- outbox 推送泵用 `FOR UPDATE SKIP LOCKED` 认领行（[02-backend.md](../01-conventions/02-backend.md#数据库)），以消息 ID = 行的 `id` 发布，只有在 broker 确认已存下之后才把行标为 `PUBLISHED`。没有流或没有 broker 时，行留在 `PENDING`，等下一轮。
- 认领已过期的行会再发布一次；去重窗口丢掉这份副本。
- 最多 256 个确认在途；轮询自适应，忙时每 200 毫秒一次，闲时每 2 秒一次，所以有很多成员的外壳也不会空转。

### 客户端参数

- 永远重连，每 2 秒一次并加抖动；启动时 broker 还没起来就一直重试；连接以成员的组件 ID 命名；断开、重连和异步错误用成员的 logger 记日志。
- 外壳里：每个进程一条连接；durable 和订阅带上各成员的 ID（[27-shells.md](27-shells.md)）。

### 尽力而为的信号

授权提供方的"bundle 已变更"这类信号走 notify：在 JetStream 上是 core NATS publish；在 PostgreSQL 队列上是 `LISTEN`/`NOTIFY`；在 Kafka 上是一个短保留期的 topic。它们可能丢失，所以每个使用方同时也轮询。

### PostgreSQL 队列适配器

表在 schema `be_bus` 里，它和 NATS 一样属于基础设施；`make db-init` 创建它，并给每个组件的角色授予这些表上的 `SELECT, INSERT, UPDATE, DELETE`。组件之间仍然绝不读对方的 schema（[0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)）。

```sql
CREATE TABLE be_bus.message (
    stream       TEXT        NOT NULL,
    seq          BIGINT      GENERATED ALWAYS AS IDENTITY,
    tx_id        XID8        NOT NULL DEFAULT pg_current_xact_id(),
    msg_id       TEXT        NOT NULL,
    subject      TEXT        NOT NULL,
    headers      JSONB       NOT NULL,
    data         BYTEA       NOT NULL,
    published_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (seq, published_at)
) PARTITION BY RANGE (published_at);          -- 保留 = 删掉旧分区

CREATE TABLE be_bus.msg_id (                   -- 去重窗口，不分区
    stream     TEXT        NOT NULL,
    msg_id     TEXT        NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (stream, msg_id)
);

CREATE TABLE be_bus.durable (
    name         TEXT PRIMARY KEY,
    stream       TEXT        NOT NULL,
    filter       TEXT        NOT NULL,
    last_tx_id   XID8,
    last_seq     BIGINT,
    last_active  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE be_bus.delivery (                 -- 在途的和等待重投的
    durable       TEXT        NOT NULL,
    seq           BIGINT      NOT NULL,
    num_delivered INT         NOT NULL DEFAULT 0,
    next_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    lease_until   TIMESTAMPTZ,
    PRIMARY KEY (durable, seq)
);
```

- **发布：** 用 `ON CONFLICT DO NOTHING` 插入 `msg_id`；只有插入成功时才插入消息，两步在同一个短事务里。
- **扇出：** 消费者在自己那行 `durable` 的行锁下，把接下来匹配的消息复制进 `delivery`，并推进 `(last_tx_id, last_seq)`。它只读 `tx_id` 比所有仍在运行的事务都老的消息（`tx_id < pg_snapshot_xmin(pg_current_snapshot())`），所以较晚提交、`seq` 却较小的发布者绝不会被跳过。
- **消费：** 用 `FOR UPDATE SKIP LOCKED` 认领 `next_at <= now()` 且租约已过期的 `delivery` 行；ack 删除该行；nak 设置 `next_at` 并把 `num_delivered` 加一；in progress 延长 `lease_until`；terminate 删除该行。
- **通知：** `NOTIFY be_bus, '<subject>'` 唤醒消费者；信号用同一个频道。

### Kafka 适配器（以后）

每个流一个 topic，每个 durable 一个 consumer group；延迟重投靠重试 topic；死信进每个 durable 各自的 topic。消息 ID 去重靠生产者的幂等性加上消费者游标。

## 备选方案

| | NATS JetStream | Kafka（KRaft） | Redpanda | RabbitMQ（quorum queues、streams） | Pulsar | PostgreSQL 队列（自建；参考 pgmq、River、Graphile Worker、pg-boss） |
|---|---|---|---|---|---|---|
| 单机上 | 一个 Go 二进制，几十 MB | JVM，GB 级 | 一个 C++ 二进制，吃内存 | Erlang，中等 | 多个服务，重 | 不新增任何东西：数据库已经在跑 |
| 保留与回放 | 按时长和大小，可从任意时间点开始 | 日志保留，按 offset | 同 Kafka | streams 可以；queues 消费即删除 | 分层存储 | 分区留多久就有多久 |
| 顺序 | 按流；重投会打乱 | 按分区；rebalance 和重试会打乱 | 同 Kafka | 按队列 | 按分区 | 按 `seq`；`SKIP LOCKED` 会打乱 |
| 竞争消费者、重投、死信 | durable 加 nak 退避加 max deliver；死信由我们做 | consumer group；重试 topic 由我们做 | 同 Kafka | 原生死信 exchange、TTL、延迟 | 原生 | 由我们做（简单） |
| 去重 | 窗口内按消息 ID | 只有幂等生产者 | 同 Kafka | 无 | 有 | 窗口内唯一键 |
| 客户端 | Go、Python、TypeScript、Rust、Java、.NET、C 都成熟 | 各语言都成熟 | Kafka 客户端 | 各语言都成熟 | Go 和 Python 较薄 | 任何 PostgreSQL 驱动 |
| 单节点吞吐 | 约 10 万条/秒 | 数百万 | 数百万 | 1 万–10 万 | 数百万 | 数千（写放大） |

## 为什么选它

- **JetStream：** 已经部署；单机上轻；流、durable、带退避的 nak 和去重窗口正好对上我们要的语义；core NATS 在同一条连接上承载尽力而为的信号；每种主流语言都有客户端，一旦组件可以用其中任何一种写，这一点就很重要。
- **outbox 作为事实来源**，让回放不取决于 broker，也不取决于它的保留期。
- **PostgreSQL 队列作为第二个适配器**，不新增依赖，适合最小的安装，兼作测试总线，并证明端口之上没有任何东西依赖 JetStream。
- **用自己的队列表而不是一个库：** 表和语句就是契约，所以每种语言实现的都是同一件事。

## 为什么不选其他

- **Kafka：** 首要目标是单机，它却是 GB 级的 JVM；分区加 consumer group 增加了运维，在这里换不来语义上的好处。等客户已经在跑它时，作为适配器来建。
- **Redpanda：** 比 Kafka 轻，但内存仍然重，模型相同。
- **RabbitMQ：** 经典队列消费即删除，所以回放弱；streams 有帮助，但那是一个产品里的第二套模型。
- **Pulsar：** 要跑多个服务。
- **pgmq** 需要数据库扩展，PostgreSQL 兼容发行版可能没有，最小权限角色也装不了；**River** 只有 Go；**Graphile Worker** 和 **pg-boss** 只有 Node。
- **broker 的"精确一次"**（去重窗口加双重确认）只去掉窗口内 broker 和客户端之间的重复；它管不到我们的数据库。游标管得到。

## 什么时候换

- **客户统一用 Kafka**，要求所有集成都走它：建 Kafka 适配器并使用。
- **最小安装**（一台小机器，没有 NATS）或测试环境：PostgreSQL 队列。
- **实测单个流的负载超过约每秒 50,000 条消息：** 用 subject 映射把这个流拆成多个分区，每个分区一个 durable；仍然是 JetStream。
- **跨机器的高可用**成为需求：三节点 NATS 集群，流副本数 3；组件不变。

## 怎么换

1. 对目标适配器跑 `tools/be-acceptance/conformance/bus/`；红就停止切换。
2. 在 `config/vars.yaml`（或某个环境的 `vars:`）里设一次 `EVENT_BUS_URL`。所有组件一起切换。
3. 重启组件；迁移步骤会在新总线上创建流和 durable。
4. 要把历史带过去，就从各 outbox 回放（`make events-replay`）；消费者跳过已经应用过的。

组件代码、契约和版本锁定都不变。

## 一致性测试

计划中的套件 `tools/be-acceptance/conformance/bus/`，每个适配器跑同样的用例：

- 停机后重启的消费者能收到期间发布的消息；
- 同一个 durable 的两个实例，每条消息只被处理一次；
- nak 后在延迟到期时重投；超过 `max_deliver` 后，消息出现在死信 subject 里，带着消费者和原因；
- terminate 停止重投；
- 窗口内同一个消息 ID 只存一次；
- ensure stream 是幂等的，不会覆盖已有配置；
- "in progress" 能防止慢消息被重投；
- 消息头往返不变；
- 超过上限的载荷失败，并给出清楚的错误；
- 没有失败时，一个消费者按发布顺序收到消息；
- notify 既不存储也不重投；
- 订阅同一个 subject 的两个外壳成员各自收到一份。

先写成红的 SDK 测试：broker 停了 3 分钟后能重连并续上；启动时 broker 还没起来就等待；慢的处理函数不阻塞另一个 subject；失败日志带成员的组件 ID；推送泵空闲时退避到 2 秒；对一个会丢确认的假适配器跑套件能看到红。项目测试：从 8 天前的 outbox 回放，不会把任何东西应用两次。

## 相关决策

- [0106 基础设施不是组件](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)：总线仍是基础设施。计划修订：总线通过一个按 URL scheme 选择的 SDK 适配器替换，这不只是一项配置，必须通过一致性套件。
- [0102 每个组件一个 schema](../02-decisions/01-architecture/0102-one-schema-per-component.md)：`be_bus` schema 属于基础设施，不属于某个组件。
- 计划中、尚未编号："事件至少投递一次；流按 subject 第一段创建"；"outbox 是回放的事实来源"。

## 已知限制

- **`discard: old` 加 1 GiB 上限：** 离线时间超过保留期的消费者会从流里丢失事件；它靠从 outbox 回放恢复，消费者的滞后或待确认数接近上限时会触发告警。
- 任何适配器都**不保证顺序**；正确性来自游标（[13](13-event-contracts.md)）。
- **消息大小：** NATS 拒绝超过 `max_payload` 的消息，`infra/nats/nats.conf` 里是 8 MB，含消息头。事件要保持小（[13](13-event-contracts.md#端口契约)）。
- **第一种部署形态里只有一台 NATS 服务器**，它是异步流程的单点故障；同步请求照常工作，outbox 不断积压，直到它恢复。
- **PostgreSQL 队列**每秒处理数千条消息，并给共享数据库增加写入负载。
- **Kafka 适配器还不存在。** 项目的基础设施清单仍把 Kafka 和 RabbitMQ 列为总线的备选；在有适配器之前它们不可用。
