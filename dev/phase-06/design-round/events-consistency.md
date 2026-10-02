# 事件与一致性：至少一次送达、快照回读回填、TCC 可靠性、幂等重放绑定——分析与设计提案

> 开发文档，只给本项目自己用；正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件文档）不得链接本文件。
> 写于 2026-10-02（06b 设计轮）。只读调研，未改任何代码、未提交。行号以写作时各仓库工作区为准（全部组件已在各自 2.x 发布 tag 上，工作区干净；be-sdk-go/python/ts 都在 v0.5.0）。
> 为确认"迁移步骤拿到哪些配置"读过 brickKit 源码仓库的 `docs/en/05-migration/README.md`（迁移命令用组件自己的镜像、和主服务完全相同的配置跑一次，成功后才启动组件）——见 §2.3 的建流位置。

## 0. 结论

四个议题共用两样东西，先定这两样，四个议题才不会各说各话：

- **一个信封**：事件多带 `event_id`（UUIDv7，也是 JetStream 的 `Nats-Msg-Id`）、`occurred_at`、`producer`；`causation_id` / `hop_count` / `traceparent` 由 SDK 从 ctx 自动派生（今天**没有任何组件填过这三个字段**，防环是死代码，§2.1.4）。消费侧只有一种去重语义：**按 (subject, aggregate_id) 的 version 单调**，用一张不分区的 `event_cursor` 表原子判重。
- **一个幂等模型**：`command_idempotency` 由 SDK 独占，主键 `(caller, idempotency_key)`——**键按调用者分命名空间**；同一调用者同一个键，命令名、目标聚合、请求指纹三者必须一致，否则 `InvalidArgument`；保留 30 天后清理。事件消费的"幂等"就是上面的 version 单调，命令的"幂等"就是这一张表，两者不混。

四个议题的推荐：

1. **至少一次送达**：JetStream **pull durable，每个 (组件, subject) 一个**，副本之间竞争消费、外壳里各成员各有各的 durable。流按 subject 的第一段建（`BE_MDM`、`BE_ERP`、`BE_SALES`……加一个 `BE_DLQ`），配置只由 subject 决定，所以任何组件都能"没有就建、有就不碰"，**不需要平台级配置、不需要组件间协调**；建流发生在 brickKit 原生的迁移步骤里（启动时再兜一次）。outbox pump 改成 JetStream 发布、拿到 PubAck 才标 `PUBLISHED`。失败 Nak 退避重投，超过次数 SDK 自己转 `dlq.<durable>.<subject>`。**迁移捷径**：be-sdk-go v0.6.0 让旧的 `besdk.Consume` / `StartOutboxPump` 签名直接跑在 JetStream 上，并用事务级 advisory lock 修掉分区 inbox 的并发重复（§2.1.2 的真 bug），所以**只升 SDK 就能让所有 Go 组件先拿到至少一次**，再按组件节奏迁到新 API。
2. **只靠事件建的快照**：一条通用规则——①快照行带上游聚合 version，事件、读穿透、回填三条写入路径共用一个带 `WHERE version < $v` 的 Upsert，字段不全的事件不新建行；②**能读穿透的地方读穿透**（缺失或陈旧就 BatchGet），③**只有读穿透不被允许的地方（枢纽的热路径）才在安装时回填**（Start 里用 SystemClient 翻上游 `List`，游标可续跑）；④JetStream 补上停机期间的空洞。SDK 给一个 `Snapshot[T]` 帮手。顺带发现 inventory 的 `product_tracking_snapshots`、opportunity 的 `customer_snapshots` **只写不读**，finance 缺快照时额度按 0 = "不限额"（fail-open）。
3. **TCC/saga**：inventory 的预留加**可选的** TTL（`hold_seconds`，0 = 不过期，旧调用方行为不变）+ 新 rpc `HoldReservation`（TCC 的 Confirm）+ 清扫任务；sales 用**订单行本身当 saga 日志**（新状态 `CONFIRMING`，写在调 `Reserve` 之前），对账任务按订单状态向前推进或退回，补偿重试从"请求里 sleep 循环"改成持久状态驱动；`sales_order_reconciliation_queue` 退役。**不做通用 saga 引擎**（09 号约定的判据：今天只有 sales 一个 TCC 调用方，说不出第二个实现）。
4. **幂等重放绑定**：SDK 的 `besdk.Idempotent` / `IdemLookup` / `IdemClaim` / `IdemComplete`；所有手写的 claim/lookup 删掉。逐个组件核对，**可被利用的越权读有三处**（opportunity 用公开种子键读别部门商机、finance 读别的法人的凭证、inventory 的入库重放绕过仓库授权），**命令错配的静默"成功"有五处**（finance 期间关/反关、inventory 撤销预留换目标、workflow 关待办换目标、mdm 两个组件的更新键挪作他用、sales 的系统派生键可被用户抢注）。

发布：be-sdk-go、be-sdk-python 各 v0.6.0（be-sdk-ts 不需要改）；13 个后端组件全部要发一个版本（sales、inventory、finance、notification、iam 是 2.1.0，其余是补丁）。建议**全部在外壳 T21–T24 之前做完**，否则外壳要重建一轮。§7 是 13 个要拍板的点。

## 1. 统一模型（四个议题共用）

### 1.1 事件信封

| 字段 | 今天 | 之后 | 谁填 |
|---|---|---|---|
| `event_id` | 无 | UUIDv7；同时作 JetStream `Nats-Msg-Id` | SDK（写 outbox 时生成） |
| `subject` / `aggregate_id` / `version` | 有（`events.go:15-24`） | 不变；`version` 是**聚合版本**，同一 (subject, aggregate) 必须严格递增 | 业务代码 |
| `occurred_at` | 无（只有 outbox 行的 `created_at`） | 新增 | SDK |
| `producer` | 无 | 组件 ID | SDK（从 rt） |
| `traceparent` | `X-Trace-Id`，**从没人填** | W3C traceparent | SDK（从 ctx 的 span） |
| `causation_id` | 有字段，**从没人填** | 引起它的那条事件的 `event_id` | SDK（从 ctx 里"正在处理的事件"） |
| `hop_count` | 有字段，**从没人填，恒为 0** | 来源事件 +1 | SDK（同上） |
| `delivery` | 无 | 只读，第几次投递（JetStream `NumDelivered`） | SDK |

Header 名沿用 `X-` 前缀，新增 `X-Event-Id`、`X-Occurred-At`、`X-Producer`、`traceparent`；读取时兼容旧的 `X-Trace-Id`。缺 `X-Event-Id` 的旧事件，SDK 用 `subject|aggregate_id|version` 的哈希派生一个，语义等同今天的 inbox 键。

### 1.2 消费去重：一种语义、一张表

今天的语义是"同一 (subject, aggregate_id) 只接受严格更大的 version"（`events.go:121-132`），所有现有消费者都依赖它，也都没问题（逐个核对过：快照类、`erp.inventory.adjusted.v1` 每条流水一个聚合、`finance.credit.rejected.v1` 每张单一次、`integration.im.result.v1` 每条记录版本递增）。**保留这一种语义，不加"每条都处理"的第二种模式**——今天说不出用它的消费者（09 号约定："说不出第二个实现就别抽象"）。

换掉的是实现：分区的 `event_inbox` 换成不分区的 `event_cursor`，一条语句原子判重：

```sql
CREATE TABLE event_cursor (
    subject      TEXT        NOT NULL,
    aggregate_id TEXT        NOT NULL,
    version      BIGINT      NOT NULL,
    event_id     TEXT        NOT NULL,
    seen_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (subject, aggregate_id)
);
CREATE INDEX event_cursor_seen ON event_cursor (seen_at);

-- 判重 = 推进游标；没有返回行就是重复或旧版本，跳过
INSERT INTO event_cursor (subject, aggregate_id, version, event_id) VALUES ($1, $2, $3, $4)
ON CONFLICT (subject, aggregate_id) DO UPDATE
   SET version = EXCLUDED.version, event_id = EXCLUDED.event_id, seen_at = now()
 WHERE event_cursor.version < EXCLUDED.version
RETURNING 1;
```

并发的同一条事件：后到者的 `INSERT … ON CONFLICT` 等先到者的行锁；先到者提交，后到者的 `WHERE` 为假、不返回行 → 跳过；先到者回滚（handler 出错），后到者插入成功 → 处理。不依赖分区键、不需要先 `SELECT max`。

表的大小 = 聚合数（每条流水一个聚合的 subject 例外，约等于事件数）。`seen_at` 超过 30 天的行由 SDK 的维护循环批量删除：那时 JetStream 早已不会再投递它（流保留 7 天，§2.3），真正的"不倒退"由业务表自己的 version 守卫兜底（快照表本来就有，§3）。

### 1.3 命令幂等：一张表、一个帮手

```sql
CREATE TABLE command_idempotency (
    caller          TEXT        NOT NULL,             -- user:<sub> | system
    idempotency_key TEXT        NOT NULL,
    command         TEXT        NOT NULL,             -- 用权限键：erp.sales.confirm
    target          TEXT        NOT NULL DEFAULT '',  -- 命令作用的聚合 id；建类命令为空
    request_hash    BYTEA       NOT NULL,             -- 规范化 JSON 的 sha256
    status          TEXT        NOT NULL DEFAULT 'CLAIMED',  -- CLAIMED | DONE
    result          JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (caller, idempotency_key)
);
CREATE INDEX command_idempotency_expires ON command_idempotency (expires_at);
```

规则：

- **键按调用者分命名空间**（主键含 `caller`）。别人的键对我来说是一个没用过的新键：读不到别人的结果，也抢注不了系统派生的键（§5.1 sales 那一条），也不给"这个键存在"的探测信号。
- 同一调用者同一个键：`command`、`target`、`request_hash` 任一不同 → `ErrIdempotencyMismatch`（`InvalidArgument`，HTTP 400）。
- 重放只在**调用方完成对 target 的授权检查之后**发生（SDK 帮手的调用位置由组件决定，§5.3 写清楚顺序）；建类命令没有 target，重放结果要再走一遍组件自己的范围内读取。
- `caller` 由 `besdk.CallerOf(ctx)` 给：有验过签的 Claims 是 `user:<sub>`，否则 `system`。gRPC 上的服务身份由 `identity-permissions.md` 决定，定下来以后 `system` 细化成 `svc:<component-id>`，表结构不变。
- 保留 30 天（`expires_at`），SDK 维护循环清理。超过 30 天再用同一个键，等同新命令：确认 / 取消类命令会被状态机挡住，建类命令会再建一条——契约里写明"键在 30 天内有效"。
- 和第 1.2 节的关系：事件 handler 里调别的组件的写命令，用**从事件派生的确定性键**（如 `crm-won:<opportunity_id>`），落在 `system` 命名空间；重投 = 同键重试，天然幂等。

## 2. 议题一：至少一次送达

### 2.1 现状与证据

#### 2.1.1 SDK

- Go `Consume` 走核心订阅 `nc.Subscribe`（`tools/be-sdk-go/events.go:65`）；handler 出错只记日志、不重投（`events.go:67-71`）；注释自己写明这是范围外的待决问题（`events.go:49-54`）。消费者离线期间发布的事件直接丢失。
- 没有 queue group：同一组件起两个副本，**两个副本各收一份、各处理一次**（Python 的注释也写了这一点，`be-sdk-python/besdk/events.py:41-46`）。
- DLQ 只有 `hop_count > 5` 一条路径（`events.go:99-102`），转发到 `dlq.<subject>`（`events.go:158-174`），用核心发布，没有人订阅。
- outbox pump：认领是原子的（`outbox.go:109-125`，`FOR UPDATE SKIP LOCKED`），但发布用核心 `nc.PublishMsg`（`outbox.go:167`）——**没有订阅者时也返回成功**，行被标成 `PUBLISHED`，事件就没了。
- Python：`consume` 只有签名，`raise NotImplementedError`（`be-sdk-python/besdk/events.py:49`）；pump 是裸 `SELECT … WHERE status = 'PENDING'`（`be-sdk-python/besdk/outbox.py:103-106`），没有认领——**违反项目易错点表"Claim a queue row … with a plain SELECT"那一条**，两个副本会把每条发两遍。目前只有 `infra/print` 用它（`infra_print/module.py:35`），单副本，没触发过。
- TS：没有 NATS，是刻意的（`be-sdk-ts/src/runtime.ts:7-8`，bff-mobile 零 NATS 依赖）。
- 基础设施：`make up` 起的 NATS 已经开着 JetStream（`infra/docker-compose.infra.yml:55`，`--jetstream --store_dir /data`），nats-server 2.10，be-sdk-go 用的 nats.go v1.53.1 带 `jetstream` 包，nats-py 2.11.0 也支持 JetStream。**换协议不需要动基础设施。**

#### 2.1.2 inbox 去重在真实表上不成立（新发现，严重）

- 9 个有 inbox 的组件（workflow、authz、print、bff 没有），`event_inbox` 都按 `created_at` 周分区，唯一索引是 `(idempotency_key, created_at)`：如 `erp/inventory/migrations/002_create_outbox_inbox.up.sql:42-64`；其余组件同构（sales `002:60`、finance `002:64`、opportunity `002:67`、notification `002:56`、iam `002:57`、im-dingtalk `002:55`、customer `002:66`、product `002:67`）。
- `created_at DEFAULT now()` 是各自事务的开始时间，两个并发事务几乎不可能相同，所以**唯一索引拦不住两条并发的同键插入**。这正是 `docs/en/01-conventions/02-backend.md` Database 一节写过的坑（"INSERT cannot detect a duplicate whose partition key differs"）。
- SDK 在插入前的 `SELECT max(version)`（`events.go:123-132`）看不到对方未提交的行。于是两个副本、或者 JetStream 的重投与仍在跑的第一次投递，**会把同一条事件的业务逻辑执行两遍**。
- R51 的修复和它的测试只在 SDK 自己的探针表上成立：探针表是 `idempotency_key TEXT PRIMARY KEY`、**不分区**（`tools/be-sdk-go/events_test.go:31-37`），测试 `TestHandleOne_并发重复投递撞inbox唯一键时静默跳过不报错`（`events_test.go:216`）证明不了真实组件的行为。
- 次要：`SELECT max(version) … WHERE subject = $1 AND aggregate_id = $2` 没有可用索引（只有 `event_inbox_idem`），每条事件扫全部分区，随时间线性变慢。
- 今天没爆出来，是因为核心 NATS 没有重投、每个组件只有一个副本。**一接 JetStream 重投就会变成真问题**，所以 §1.2 的 `event_cursor` 不是可选优化，是前提。

#### 2.1.3 保留与清理

迁移注释承诺"已发布成功超过 30 天可清理"（`erp/inventory/migrations/002_create_outbox_inbox.up.sql:2`），但各组件的 `partition` 包只建未来分区、从不 DETACH / DROP（如 `erp/inventory/backend/internal/partition/partition.go:28`）。outbox 与 inbox 无限增长，且这段"建周分区"的代码在每个组件里各抄了一份。

#### 2.1.4 信封字段没人填

`grep HopCount|CausationID|TraceID` 全部组件后端（不含测试与生成代码）结果为空：**没有任何生产者填过这三个字段**。`hop_count > 5` 进 DLQ 的防环（`events.go:99-102`）永远不会触发；trace 在事件边界断开。原因是 `PublishOutbox(tx, schema, ev)`（`outbox.go:19`）不接 ctx，拿不到"正在处理哪条事件"。

#### 2.1.5 生产者与消费者全表

| 组件 | 版本 | 发布（经 outbox） | 消费 | 丢事件的后果 |
|---|---|---|---|---|
| mdm/customer | 2.0.1 | `mdm.customer.created/updated/disabled.v1`（`repo/write.go:69`） | — | 下游快照缺行或过期（§3） |
| mdm/product | 2.0.0 | `mdm.product.created/updated/disabled.v1`（`repo/write.go:74`） | — | 同上 |
| erp/inventory | 2.0.0 | `erp.inventory.adjusted.v1`（`repo/movement.go:236`） | `mdm.product.created/updated.v1`（`consumer/consumer.go:33`） | finance 漏记存货凭证；快照缺行（但快照没人读，§3） |
| erp/sales | 2.0.0 | `sales.order.created/cancelled/shipped.v1`（`repo/write.go:201,304,378`） | `finance.credit.rejected.v1`、`mdm.customer.created/updated.v1`、`infra.workflow.task.completed.v1`、`crm.opportunity.won.v1`（`consumer/consumer.go:33-37`） | 超额度的单不被挂起；人工处理完的异常单恢复不了；赢单不转订单（`consumer.go:187-191` 注释自认） |
| erp/finance | 2.0.0 | `finance.credit.rejected.v1`、`finance.voucher.posted.v1`（`repo/autoentry.go:150`、`repo/entry.go:219`） | `sales.order.created.v1`、`erp.inventory.adjusted.v1`、`mdm.customer.created/updated.v1`（`consumer/consumer.go:28-31`） | **漏记应收与收入凭证**、已用额度少算 |
| crm/opportunity | 2.0.0 | `crm.opportunity.won/lost/stage_changed.v1`（`repo/write.go:90`） | `mdm.customer.created/updated.v1`、`sales.order.created.v1`（`consumer/consumer.go:31-35`） | 赢单商机回填不了订单号 |
| infra/workflow | 2.0.1 | `infra.workflow.task.created/completed/cancelled/overdue.v1`（`repo/tasks.go:139`、`actions.go:60,190`、`overdue.go:69`） | — | 通知发不出；sales 的异常单恢复不了 |
| infra/notification | 2.0.0 | `infra.notification.dispatch.im/email.v1`、`.sent/.failed.v1`（`consumer/consumer.go:186,200,347,357`） | `infra.workflow.task.created.v1`、`infra.iam.user.created/updated/disabled.v1`、`integration.im.result.v1`（`consumer.go:39-43`） | 待办不通知；联系人缺失 |
| integration/im-dingtalk | 2.0.0 | `integration.im.result.v1`（`consumer/consumer.go:301`） | `infra.notification.dispatch.im.v1`（`consumer.go:30,44`） | 通知记录卡在中间状态 |
| infra/iam-casdoor | 2.0.0 | `infra.iam.user.*.v1`（`service/webhook.go:102-104,152`） | `infra.authz.user_role.changed.v1`（`consumer/consumer.go:20-23`） | **被踢的人 refresh token 不作废**（只在 `change_type=kicked` 时作废，`consumer.go:45-55`），安全相关 |
| infra/authz | 2.0.1 | `infra.authz.user_role.changed.v1`（outbox pump `module/module.go:66`） | — | 同上 |
| infra/print（Python） | 2.0.0 | `infra.print.rendered.v1`（`infra_print/repo/jobs.py:51`） | — | 旁路审计事件 |
| infra/bff-mobile（TS） | 2.0.0 | — | — | — |

另外两处会和"重投"冲突、需要在迁移时一起改：

- sales 的赢单 handler 在 inbox 事务里做网络调用（BatchGet / Reserve / 建待办），事务一直开着（`erp/sales/backend/internal/consumer/consumer.go:183-191`）。JetStream 的 AckWait 默认 30 秒，几次 5 秒超时就会被当成没确认而重投。
- im-dingtalk 在 inbox 事务里调钉钉发消息（`integration/im-dingtalk/backend/internal/consumer/consumer.go:106`），事务提交失败就会在重投时**再发一遍**；回查结果用进程内 goroutine（`consumer.go:121`），进程一停这条记录就永远停在 `ACCEPTED`。

### 2.2 方案

#### 2.2.1 送达方式

| | (a) JetStream pull durable，每 (组件, subject) 一个 | (b) JetStream push + queue group | (c) 每组件一个 durable，多 filter subject | (d) 保持核心 NATS，靠定时对账补 |
|---|---|---|---|---|
| 离线期间的事件 | 保留，上线后补收 | 保留 | 保留 | 丢，等对账 |
| 副本竞争消费 | 天然（同一 durable 多个拉取者） | 要配 deliver group | 天然 | 无，副本重复处理 |
| 外壳里多成员 | 每个成员自己的 durable，互不影响 | 同左 | 同左 | — |
| 一个 subject 坏消息卡住别的 subject | 不会 | 不会 | **会**（同一 durable 的 MaxAckPending 共用） | — |
| 失败重投 / 退避 / DLQ | `Nak` + `BackOff` + `MaxDeliver` | 同左 | 同左 | 无 |
| nats.go 新 API 的推荐方向 | 是（`jetstream` 包以 pull 为主） | 旧 API | 是 | — |
| 改动量 | SDK 内部；组件只改注册方式 | 同左 | 同左 | 每个消费者都要写对账 |

(d) 等于每个组件为每个上游自己实现一遍对账，不可接受。(c) 少几个 durable，代价是故障隔离，不值。选 **(a)**。

#### 2.2.2 流由谁、按什么粒度建

| | (i) SDK 按 subject 第一段建，"没有就建、有就不碰"（推荐） | (ii) be-ops 从登记表生成，`make nats-init` | (iii) 每个生产者组件一个流 | (iv) 全项目一个流 |
|---|---|---|---|---|
| 配置来源 | 只由 subject 决定：`BE_<第一段大写>`，subjects `["<第一段>.>"]` | `registry/streams.tsv` | 生产者的组件 ID | 一个固定定义 |
| 族 subject（多个适配器都发 `integration.im.result.v1`） | 没问题（流跟着 subject 走，不跟组件走） | 没问题 | **冲突**：两个流不能覆盖同一个 subject | 没问题 |
| 历史遗留的 `sales.*`、`finance.*`（不带 `erp.`） | 各成一个流，无害 | 登记表里写两行 | — | — |
| `brickkit up --focus` 一个组件、NATS 是新的 | 能跑 | 要先跑 `make nats-init` | 消费者先起时没有流 | 能跑 |
| 运维按域调保留期 | 可以（SDK 从不覆盖已有配置） | 可以 | 可以 | 不能分域 |
| 生产环境禁止组件建流 | 运维预建，SDK 发现已存在就继续；没有又建不了 → 迁移步骤失败、报清楚 | 天然 | 同 (i) | 同 (i) |
| 与项目先例 | 组件自描述；但 PG 的 schema/role 是 `make db-init` 建的 | 与 `db-init` 对称 | — | — |

PG 的 schema 由运维建，是因为建 role 需要超级权限、组件不该有；NATS 的流没有这层权限问题（dev 环境无鉴权，生产由账号权限决定）。(i) 让每个组件在 brickKit 的模型里"自己就能跑"，又给运维留了接管的口子。选 **(i)**，作为一条新决策记下来（§7 第 1 点）。

**在哪一步建**：brickKit 的迁移步骤用组件自己的镜像、和主服务相同的配置（含 `NATS_URL`）跑一次，成功才启动组件；外壳里每个成员的迁移也从成员自己的镜像跑（0108）。所以在 `migrate.Main` 里 ensure 流与本组件的 durable：配置错误在部署时就失败，不是运行时悄悄退化。启动时再 ensure 一次，兜住"NATS 数据被清空了"这种开发环境常态。

#### 2.2.3 失败处理

| 情形 | 做法 |
|---|---|
| handler 返回普通 error / panic | 事务回滚，`NakWithDelay(BackOff[n])`；默认 `MaxDeliver=8`，`BackOff = 1s, 10s, 1m, 5m, 15m, 30m, 1h` |
| handler 返回 `besdk.Permanent(err)`（解析失败、契约不符） | 直接进 DLQ，`Term()`，不重投 |
| 最后一次投递仍失败 | SDK 发布到 `dlq.<durable>.<原 subject>`（流 `BE_DLQ`，保留 30 天），带 `X-Dlq-Reason`、`X-Dlq-Consumer`、`X-Delivery`，然后 `Term()` |
| `hop_count > 5` | 同上进 DLQ（保留现有规则，§2.1.4 修好以后才真的生效） |
| handler 跑得久 | SDK 每 `AckWait/3` 发一次 `InProgress()`；但长事务本身仍是问题，见下面 `Run` |
| 提交成功、ack 丢了 | 重投，`event_cursor` 判重跳过 |

DLQ 的 subject 带消费者名：一条消息在 finance 失败、在 opportunity 成功，重放时只该给 finance。把 DLQ 里的消息重放回原 subject 也安全：其他消费者靠 `event_cursor` 跳过；重放时 `Nats-Msg-Id` 加后缀，避开发布去重窗口。

**两种 handler**：

- `Apply(ctx, tx, ev)`：只做本地写，和 `event_cursor` 同一个事务（今天所有消费者都是这种，除了下面两个）。
- `Run(ctx, ev)`：有外部副作用（网络调用、发 IM），在事务外执行；成功后 SDK 用一个短事务推进游标。并发重复时可能执行两次，所以 handler 必须按业务键幂等（sales 赢单用 `crm-won:<id>` 系列键，§4；im-dingtalk 用 `record_id + attempt`）。今天就有两个真实用户（sales 赢单、im-dingtalk 派发），够格成为 SDK 的一部分。

#### 2.2.4 durable 的命名与生命周期

- 名字：`<组件 ID 把 / 换成 _>__<subject 把 . 换成 _>`，如 `erp_finance__sales_order_created_v1`。同一组件单跑、进外壳、多副本，用的是同一个 durable——外壳拆回单跑不丢位置。
- 首次创建时从哪开始：默认 `DeliverAll`（流里还留着的都收，靠 version 单调去重）。新装的组件会补收最近 7 天的事件——对快照是好事，对 finance 是"补记新装前 7 天的订单"，要拍板（§7 第 3 点）。
- `InactiveThreshold = 30 天`：组件被移出项目 30 天后它的 durable 自动消失，不用人清。
- 测试：沿用踩坑记录 E2 的做法（测试私有 subject），派生出的 durable 名天然不同；SDK 再给测试一个 `Ephemeral` 选项，不在开发 NATS 里留垃圾。

#### 2.2.5 发布路径

pump 改成 `js.PublishMsg(…, WithMsgID(event_id))`，拿到 PubAck 才标 `PUBLISHED`；流不存在、NATS 不可用都会报错，行留在 `PENDING` 下一轮再试（今天的核心发布在没人订阅时也"成功"，这一点反过来了）。认领超时重发（`outbox.go:39` 的 30 秒）造成的重复，由流的去重窗口（设成 10 分钟）按 `Nats-Msg-Id` 丢掉。JetStream 发布同时也投给核心订阅者，所以**生产者先升级、消费者后升级**的混合状态完全可用。

### 2.3 推荐

(a) + (i) + §2.2.3–2.2.5。默认值：每个域流 `max_age = 7d`、`max_bytes = 1GiB`、`discard = old`、`duplicate_window = 10m`、文件存储、单副本；`BE_DLQ` 保留 30 天。`max_bytes` 是按 06b 两次把根分区写满的教训加的上限。

### 2.4 SDK API

**Go（be-sdk-go v0.6.0）**

```go
// 信封（§1.1）
type Event struct {
	ID          string    // SDK 生成（UUIDv7），= Nats-Msg-Id
	Subject     string
	AggregateID string
	Version     int64
	OccurredAt  time.Time // SDK 填
	Producer    string    // SDK 填
	TraceParent string    // SDK 从 ctx 填
	CausationID string    // SDK 从 ctx 填
	HopCount    int       // SDK 从 ctx 填
	Payload     []byte
	Delivery    int       // 只读
}

// 生产：在 WithTx 的事务里调；ctx 用来派生 causation/hop/trace
func (rt *Runtime) Publish(ctx context.Context, tx *sql.Tx, ev Event) error

// 消费
type Subscription struct {
	Subject    string
	Apply      func(ctx context.Context, tx *sql.Tx, ev Event) error // 二选一
	Run        func(ctx context.Context, ev Event) error             // 二选一
	MaxDeliver int             // 0 = 默认 8
	Backoff    []time.Duration // nil = 默认
	StartFrom  StartFrom       // 默认 StartAll；只在首次创建 durable 时生效
}

// 一个组件的事件声明：放在 backend/module/events.go 一个文件里，迁移入口和 Start 都读它
type EventsSpec struct {
	Publishes []string       // 本组件发布的 subject（建流用，也是 gate 对照 contracts/events 的依据）
	Subscribe []Subscription
}

// Start 里调一次，阻塞到 ctx 取消：outbox pump + 全部消费者 + event_cursor / outbox 分区的维护
func (rt *Runtime) RunEvents(ctx context.Context, role, schema string, spec EventsSpec) error

func Permanent(err error) error // 标记重投也没用，直接进 DLQ

// 迁移入口：多一个选项，迁移步骤里 ensure 流与 durable
migrate.Main(migrations.FS, migrate.WithEvents(module.Events))
```

`role` / `schema` 参数和 `WithTx` 保持一致；它们会不会折进 rt，由 `sdk-redesign.md` 定。

**兼容层（同在 v0.6.0，标 Deprecated，组件迁完后在 v0.7.0 删除）**

- `Consume(ctx, nc, db, role, schema, subject, fn)`：内部改为 JetStream durable（名字由 `schema` + subject 派生），handler 出错 Nak 重投；去重仍用旧的 `event_inbox`，但在 `SELECT max` 之前取 `pg_advisory_xact_lock(hashtext(subject || '|' || aggregate_id))`，把同一聚合的并发处理串行化——**不改表就修掉 §2.1.2**。advisory lock 是 PG 专有的，只用在过渡期。
- `StartOutboxPump(...)`：内部改为 JetStream 发布，`Nats-Msg-Id = <schema>:<outbox id>`（旧表没有 `event_id` 列，这个值在重试之间稳定）。
- `PublishOutbox(tx, schema, ev)`：行为不变（没有 ctx，信封派生字段仍为空）。

外壳的 `go.mod` 取成员里最高的 SDK 版本，所以兼容层必须对没改代码的 2.0.x 成员完全正确——这正是它的设计目标。

**Python（be-sdk-python v0.6.0）**

```python
@dataclass(frozen=True)
class Subscription:
    subject: str
    apply: Callable[[asyncpg.Connection, Event], Awaitable[None]] | None = None
    run: Callable[[Event], Awaitable[None]] | None = None
    max_deliver: int = 8
    backoff: tuple[float, ...] = (1, 10, 60, 300, 900, 1800, 3600)
    start_from: StartFrom = StartFrom.ALL

@dataclass(frozen=True)
class EventsSpec:
    publishes: tuple[str, ...] = ()
    subscribe: tuple[Subscription, ...] = ()

async def publish(rt: Runtime, conn: asyncpg.Connection, ev: Event) -> None
async def run_events(rt: Runtime, role: str, schema: str, spec: EventsSpec) -> None
def permanent(err: Exception) -> Exception
```

`start_outbox_pump` 同 Go 改成原子认领 + JetStream 发布（修掉 §2.1.1 的裸 `SELECT`）。`consume` 的 `NotImplementedError` 删掉，换成 `run_events`。

**TS（be-sdk-ts）**：不加。bff-mobile 没有 NATS、没有数据库是既定设计（`runtime.ts:7-8`）。

### 2.5 各组件改动与版本

所有 Go 组件的改法相同：`go.mod` 升 v0.6.0；新迁移把 `event_inbox` 换成 `event_cursor`（旧表保留到下一个版本再删，迁移只增不改）、给 `event_outbox` 加 `event_id`、`occurred_at`、`producer`、`traceparent` 四列；`module.go` 里的 pump、各 `consumer.Start`、`partition` 包里的周分区维护，合并成一个 `rt.RunEvents(…, module.Events)`；`cmd/migrate/main.go` 加 `migrate.WithEvents`。版本号由 §3–§5 的其它改动一起决定，汇总在 §6。

各组件特有的改动：

| 组件 | 特有改动 |
|---|---|
| erp/sales | 赢单 handler 改成 `Run`（不再占着 inbox 事务做网络调用）；失败返回 error 让 JetStream 重投 = 重试，不再"永远返回 nil 只开待办"（`consumer.go:192-209`）；重投耗尽进 DLQ 时再开异常待办 |
| integration/im-dingtalk | 派发 handler 改成 `Run`；`confirmLater` 的回查改成持久化：`ACCEPTED` 记录由一个按 `next_poll_at` 扫描的循环推进，进程重启不丢 |
| infra/iam-casdoor | 无特有改动；它是至少一次送达最直接的受益者（踢人事件不再丢） |
| infra/print（Python） | 升 be-sdk-python v0.6.0；pump 修复随 SDK 走 |
| 其余 | 只有通用改法 |

### 2.6 先写的红测试

SDK（真 PG、真 NATS JetStream；在 v0.5.0 上跑红）：

- `TestConsume_分区inbox上并发重复投递只执行一次`：用和组件一模一样的分区表与唯一索引做 fixture（不是今天 `events_test.go:31-37` 的不分区探针表），两个 goroutine 同时处理同一事件 → 业务 fn 只被调一次。**这条在今天的 SDK 上就是红的**，先单独提交。
- `TestConsume_handler出错后重投并最终成功`
- `TestConsume_消费者离线期间发布的事件上线后收到`
- `TestConsume_超过MaxDeliver进DLQ且带消费者名与原因`
- `TestConsume_Permanent错误直接进DLQ不重投`
- `TestConsume_两个副本共享durable每条只处理一次`
- `TestConsume_外壳里两个成员订阅同一subject各收一份`
- `TestPump_没有流时保持PENDING不标PUBLISHED`
- `TestPump_认领超时重发被MsgID去重`
- `TestPublish_在handler里发布自动带causation与hop加一`
- `TestEnsureStreams_已存在的流配置不被覆盖`
- `TestRun_事务外执行成功后才推进游标`
- `TestEventCursor_旧版本与重复都不返回行`
- Python：`test_pump_两个实例并发只发布一次`（今天红）、`test_run_events_handler出错后重投`。

组件（各自在升 SDK 之前先跑红）：

- erp/sales：`TestOpportunityWon_建单失败后事件重投重试成功`。
- integration/im-dingtalk：`TestDispatch_提交失败重投不重复调钉钉发送`、`TestConfirm_进程重启后ACCEPTED记录继续回查`。
- erp/finance：`TestSalesOrderCreated_finance离线期间的订单上线后补记`（集成测试，真 JetStream）。

## 3. 议题二：只靠事件建的快照

### 3.1 现状与证据

| 组件 | 快照表 | 来源 | 谁读、怎么读 | 缺行 / 过期时 |
|---|---|---|---|---|
| erp/sales（2.0.0） | `customer_snapshots.credit_limit` | `mdm.customer.created/updated.v1`（`consumer.go:34-35`）+ **确认时用 BatchGet 结果刷新**（`tcc/confirm.go:279-296`、`repo/write.go:414-423`） | 确认链第③步预判 | 已修好：刷新按 version 单调。剩一个边角：`updated` 不带 `credit_limit` 时，从没见过的客户会按额度 0、**带着上游 version** 建行（`repo/snapshot.go:26-39`），之后同 version 的刷新是空操作——要等下一次上游变更才纠正。mdm/customer 实际总是带这个字段（`mdm/customer/backend/internal/repo/write.go:76-80`），所以目前不触发 |
| erp/finance（2.0.0） | `customer_credit_snapshots`（`credit_limit`、`name`） | `mdm.customer.created/updated.v1`（`consumer.go:30-31`、`repo/snapshot.go:21-42`） | 过账时判超限（`repo/autoentry.go:80-95`）；应收台账显示客户名（`repo/arledger.go:71-73`，`LEFT JOIN … COALESCE(s.name, '')`） | **查不到额度按 0，而 0 的含义是"没配额度、不拦"**（`repo/credit.go:94-105` + `autoentry.go:84-85`）：finance 后装、或者漏了客户事件，这个客户**永远不会被判超限**（fail-open）；客户名为空，要等下一条 `updated` |
| erp/inventory（2.0.0） | `product_tracking_snapshots.tracking_type` | `mdm.product.created/updated.v1`（`consumer/consumer.go:33`、`repo/snapshot.go:17-32`） | **没有人读**：全组件只有写入和一个"仅供测试"的读取函数（`repo/snapshot.go:34-46`）。设计文档说"带序列号的产品没填序列号，由应用代码在事件窗口内拦"（`docs/design.md:131`），**这段应用代码不存在** | 不影响任何行为——它本来就没被用 |
| crm/opportunity（2.0.0） | `customer_snapshots.name` | `mdm.customer.created/updated.v1`（`repo/snapshot.go:10-24`） | **没有人读**（只有 upsert；商机自己的 `customer_name` 是建档时的快照，`repo/opportunity.go:81`） | 同上 |
| infra/notification（2.0.0） | `user_contacts`（手机、邮箱、显示名、停用） | `infra.iam.user.created/updated/disabled.v1`（`consumer.go:40-42`、`repo/contacts.go:43-66`） | 待办通知查收件人（`consumer.go:83`） | 查不到返回零值（`repo/contacts.go:18-34`），手机号为空 → 通知转永久失败。**通知中心后装时，所有已有用户都收不到通知**，直到他们改一次资料 |

上游能提供什么：

- mdm/customer、mdm/product 都有 `List`（游标分页，**默认只给最近 90 天**，回填要显式传 `created_after` 为最早时间，`mdm/customer/contracts/mdm/customer/v1/customer.proto:116-130`）和 `BatchGet`；`Customer.version` 已在契约里（`customer.proto:43`）。
- infra/iam-casdoor 只有 `BatchGetUsers`，`User` 消息**没有 `version`、没有 `disabled`**（`infra/iam-casdoor/contracts/infra/iam/v1/iam.proto:33-48`），读穿透写不出版本守卫。
- 依赖边：inventory、finance、notification 都**没有声明任何依赖**（各自 `component.yaml` 的 `dependencies.components: []`）。inventory 是刻意的（`erp/inventory/docs/design.md:83`：不想让枢纽进同步调用链）。没有边就拿不到地址，读穿透和回填都做不了。

### 3.2 方案

| | (A) gRPC 读穿透 + 按需回填（推荐） | (B) 生产者另发"状态流"，按聚合压实 | (C) 事件流长期保留、新消费者从头重放 |
|---|---|---|---|
| 做法 | 缺失 / 陈旧时 BatchGet；枢纽热路径不许读穿透的地方，Start 里翻上游 `List` 回填 | 上游每次变更再发一条 `mdm.customer.state.v1.<id>` 进 `MaxMsgsPerSubject=1`、不过期的流；新消费者 `DeliverAll` 就拿到全量 | 域流不设 `max_age` |
| 依赖边 | 消费者要声明（`optional: true`） | 不需要 | 不需要 |
| 上游要改 | 只在缺 version 的地方加字段（iam） | 每个被快照的上游都要多发一种事件、加契约 | 无 |
| 能替换组件吗 | 替换品实现同一份 `List` / `BatchGet` 契约即可 | 替换品还得发状态流 | — |
| 存储 | 无 | 每个聚合一条消息常驻 NATS | 无限增长 |
| 上游宕机时 | 回填 / 读穿透失败，降级 | 不受影响 | 不受影响 |
| 复杂度 | 一个 SDK 帮手 | SDK 帮手 + 每个上游的新事件 | 最低，但不可持续 |

(C) 不可持续。(B) 最优雅：枢纽不用加任何边。但它要求每个被快照的上游都多发一种事件，而且今天真正需要"全量"的快照只有一个（inventory，而且它还没被使用）。按 09 号约定，先做 (A)；等出现第二个"枢纽要全量快照"的需求，再回来做 (B)。

### 3.3 推荐：通用规则

1. **快照行必须带上游聚合 version。** 事件、读穿透、回填三条写入路径**共用一个** Upsert，带 `WHERE 本地.version < 传入.version`。等号是空操作，所以三条路径怎么交错都不会倒退。
2. **字段不全的事件只更新已有行，不新建行**（修掉 sales 的边角）。新建只来自完整状态：完整事件、BatchGet、List。
3. **能读穿透的地方就读穿透**：缺行，或者设了 `StaleAfter` 而行比它旧，就 BatchGet，写回，再返回。允许读穿透的地方是事件 handler（SystemClient 在那里是允许的）和非枢纽组件的用户请求路径。上游缺席（可选依赖没装）或不可用时，把缺失的 id 交给调用方决定：安全相关（额度）按 fail-closed 处理，展示相关（名字）降级。
4. **只有读穿透不被允许、或者需要全量的地方才回填**：枢纽的热路径（inventory 的入库），或者要在列表里展示全部行的视图。回填在 `Start()` 里用 SystemClient 按游标翻 `List`（从最早时间开始），进度写进 `snapshot_sync`，中断可以续跑，完成后记下时间。**先订阅事件，再开始回填**，交错由规则 1 处理。
5. **停机期间的空洞由 JetStream 补**（§2）；超过流保留期（7 天）的空洞、进了 DLQ 的事件，靠第 3 / 4 条兜底。可选的定期全量核对（例如每天一次 `List`）留给真的需要它的快照，默认不开。
6. **不读的快照删掉。** 快照表 = 一条同步链路 + 一个可能过期的副本，没人读就是纯成本。

依赖边的用法：读穿透、回填要用的上游声明成 `optional: true` 依赖，只在事件 handler、`Start()`、后台循环里用 SystemClient 拨号，不进用户请求的同步链路。inventory 的设计文档担心的是"枢纽进调用链"；这种用法不进调用链，和它的担心不冲突。这一点需要在 inventory 的设计文档里写明（§7 第 6 点）。

### 3.4 SDK API

**Go**

```go
type Versioned[T any] struct {
	ID      string
	Version int64
	Row     T
}

type Snapshot[T any] struct {
	Name       string   // snapshot_sync 里的名字，如 "customer_credit"
	Upstream   string   // 依赖 ID；必须在 component.yaml 声明（可 optional）
	Subjects   []string // 维护它的事件
	FromEvent  func(ev Event) (v Versioned[T], full bool, err error)                          // full=false 只更新已有行
	Upsert     func(ctx context.Context, tx *sql.Tx, v Versioned[T], allowInsert bool) error   // 组件自己的 SQL，必须带 version 守卫
	Load       func(ctx context.Context, tx *sql.Tx, ids []string) (map[string]Versioned[T], error)
	Fetch      func(ctx context.Context, conn *grpc.ClientConn, ids []string) ([]Versioned[T], error)               // BatchGet
	ListPage   func(ctx context.Context, conn *grpc.ClientConn, cursor string) ([]Versioned[T], string, error)      // nil = 不回填
	StaleAfter time.Duration // 0 = 只在缺行时读穿透
}

func (s *Snapshot[T]) Subscriptions() []Subscription                                      // 放进 EventsSpec.Subscribe
func (s *Snapshot[T]) Backfill(ctx context.Context, rt *Runtime, role, schema string) error // Start 里调；可续跑；ListPage 为 nil 时直接返回
func (s *Snapshot[T]) Get(ctx context.Context, rt *Runtime, role, schema string, ids []string,
	opt GetOptions) (found map[string]Versioned[T], missing []string, err error)            // opt.ReadThrough=false 时只读本地
```

SDK 拥有的表（每个用到快照的组件在自己的迁移里建）：

```sql
CREATE TABLE snapshot_sync (
    name         TEXT PRIMARY KEY,
    status       TEXT NOT NULL DEFAULT 'PENDING',  -- PENDING | RUNNING | DONE
    cursor       TEXT NOT NULL DEFAULT '',
    started_at   TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

快照表本身仍是组件自己的表、自己的 SQL：SDK 只管调用时机与 version 规则，不碰业务列。

**Python**：同构，`Snapshot` 是 dataclass，回调都是 `async`；目前没有 Python 消费者，先不实现，等第一个 Python 消费者出现再补（契约先写进 `docs/` 的 SDK 指南）。
**TS**：不加。

### 3.5 各组件改动与版本

| 组件 | 改动 | 依赖边 / 契约 |
|---|---|---|
| erp/sales → 2.1.0 | `customer_snapshots` 改用 `Snapshot` 帮手：事件路径与确认链共用一个 Upsert；确认链的 BatchGet 结果直接喂给它（`ReadThrough` 实际已经在做）；字段不全的事件不新建行 | 不变 |
| erp/finance → 2.1.0 | `customer_credit_snapshots` 改用帮手；**过账 handler 里读穿透**：缺行时 BatchGet 拿额度与名字。上游缺席时：额度未知不判超限，但记一条 Warn，并把这张单记进新表 `credit_check_pending`（等 mdm/customer 可用时补判）——把今天"缺快照 = 不限额"的静默放行变成可见的待办 | 新增 `mdm/customer` 可选依赖 |
| infra/notification → 2.1.0 | `user_contacts` 改用帮手；待办通知 handler 里读穿透 `BatchGetUsers` | 新增 `infra/iam-casdoor` 可选依赖；需要 iam 2.1.0 |
| infra/iam-casdoor → 2.1.0 | `User` 加 `version`、`disabled`（只增） | 契约只增 |
| erp/inventory → 2.1.0 | 二选一（§7 第 6 点）：(甲) 真的实现"按跟踪方式校验批次号 / 序列号"——`Receive` / `Adjust` / `ConfirmIssue` 读快照；快照靠回填 + 事件维护，不读穿透（枢纽热路径）；快照缺行时按"未知"放行并记 Warn。(乙) 删掉消费者和表，设计文档改成"不校验"。推荐 (甲)：这是库存的真实业务规则，而且设计文档已经承诺了 | (甲) 新增 `mdm/product` 可选依赖，只在 `Start()` 回填里用 |
| crm/opportunity → 2.0.1 | 删掉 `customer_snapshots` 的消费者（表留到下一个版本，迁移只增不改）；或者给列表页用上它（§7 第 6 点）。推荐删掉：商机的客户名就是建档快照，和订单一样 | 不变 |

### 3.6 先写的红测试

SDK：

- `TestSnapshot_回填拿到上游全部历史行`（上游 List 用假的 gRPC 服务）
- `TestSnapshot_回填中断后从游标续跑`
- `TestSnapshot_回填与事件交错version不倒退`
- `TestSnapshot_字段不全的事件不新建行`
- `TestSnapshot_读穿透缺行时BatchGet并写回`
- `TestSnapshot_上游缺席时返回missing不报错`

组件（在今天的代码上跑红）：

- erp/finance：`TestPostSalesOrder_客户快照缺失时读穿透拿到额度并判超限`（今天：额度 0、不判）、`TestARLedger_第一次过账就有客户名`、`TestPostSalesOrder_上游缺席时记进待补判表`。
- infra/notification：`TestTaskCreated_联系人快照缺失时从iam读穿透`。
- erp/sales：`TestCustomerSnapshot_不带额度的updated不新建行`。
- erp/inventory（如果选 (甲)）：`TestReceive_序列号管理的产品不带序列号被拒`、`TestBackfill_安装时拿到mdm已有产品的跟踪方式`。

## 4. 议题三：TCC/saga 可靠性

### 4.1 现状与证据

sales 的确认链（`erp/sales/backend/internal/tcc/confirm.go:35-89`）：①②③ 校验 → ④ `Reserve`（第 76 行）→ ⑤ `FinalizeConfirm` 落库 + 发事件（第 82 行）→ ⑤ 失败补偿 `CancelReservation`（第 86 行）。

| 缺口 | 证据 |
|---|---|
| 预留不过期 | `inventory_reservations` 没有过期列（`erp/inventory/migrations/001_create_inventory.up.sql:108-137`）；状态只有 RESERVED / CONFIRMED / CANCELLED |
| 进程停在 ④ 与 ⑤ 之间：孤儿预留，没有任何东西知道 | ④ 之前没有任何持久记录；sales 自己的设计文档也写了（`erp/sales/docs/design.md:160`） |
| 对账队列只写不读 | 只有 `EnqueueReconciliation`（`repo/write.go:395-410`）在"查状态也超时"时写（`confirm.go:131`）；全仓库没有读它的代码；迁移注释写着"真正的对账轮询留到阶段三"（`migrations/001_create_sales.up.sql:146-159`） |
| 补偿重试在请求里 sleep，进程一停就没了 | `compensateReserve` 原地循环 + `time.Sleep`（`confirm.go:172-215`，第 214 行）；计数持久化了，但"还要不要继续补偿"不持久 |
| `Reserve` 重放只回 id、不回状态 | `repo/reservation.go:57-58` 只返回 `reservation_id`；如果那份预留已经被撤销，调用方会拿一份死预留去落库 |
| 赢单路径失败不重试 | 核心 NATS 不重投（`consumer.go:187-191`）；§2 修好后变成"重投即重试" |
| 换新键重试会再预留一份 | 设计文档承认（`docs/design.md:160`）；只能靠过期或对账兜底 |
| 财务拒绝信用 | 已修（sales `d62a3b0`）：挂起 + 开待办，已发货的单不挂起（`consumer.go:65-101`） |

相邻但不在本议题：finance 不消费 `sales.order.cancelled.v1`（`erp/finance/backend/internal/consumer/consumer.go:28-31`），取消的单不冲销应收、不释放已用额度（§8）。

### 4.2 方案

**库存侧：要不要过期、怎么过期**

| | (a) 可选 TTL + `HoldReservation`（推荐） | (b) 一律 TTL，靠调用方续租 | (c) 不过期，只靠调用方对账 | (d) 库存反查订单状态 |
|---|---|---|---|---|
| 做法 | `Reserve` 带 `hold_seconds`（0 = 不过期，就是今天的行为）；调用方本地确认后调 `HoldReservation` 清掉过期时间（TCC 的 Confirm）；清扫任务释放过期的 | 每份预留都有期限，调用方定期续租 | 库存不变 | 库存定期问 sales "这单还在吗" |
| 旧调用方（sales 2.0.0） | 不受影响 | **已确认订单的预留会被释放**，发货失败 | — | — |
| 调用方消失 / 永远不回来 | 有 TTL 的预留会被释放 | 会 | **永远占着** | 能释放 |
| 依赖方向 | 不变 | 不变 | 不变 | **枢纽反向依赖上游**，违反"三个枢纽"的结构 |
| 枢纽自己守住"预留不会无限泄漏"这条不变量 | 是（对 opt-in 的调用方） | 是 | 否 | 是，但代价是依赖环 |

(d) 排除。(c) 让库存的正确性取决于每一个调用方都写对对账，而库存是要被将来的采购、项目等组件复用的枢纽。(b) 需要调用方常驻续租，比 Hold 复杂且不向后兼容。选 **(a)**。

**销售侧：saga 日志放在哪**

| | (甲) 订单行本身当 saga 日志，加状态 `CONFIRMING`（推荐） | (乙) 通用的 SDK 作业队列（outbox-command） | (丙) 通用 SDK saga 引擎 |
|---|---|---|---|
| 崩溃恢复靠什么 | 对账任务扫 `status = 'CONFIRMING'` 的旧订单 | 扫作业表 | 引擎的步骤日志 |
| 进行中的状态用户看得见吗 | 看得见（"确认中"），并发的取消被状态机挡住 | 看不见：订单还是 DRAFT，作业在另一张表 | 看不见 |
| 合法流转在哪里声明 | 订单状态机一处（09 号约定"State transitions in one table"） | 状态机 + 作业处理器两处 | 引擎的 DSL |
| 今天的真实用户 | sales 一个 | sales、im-dingtalk 回查（§2.5）——两个，但形状不同 | sales 一个 |
| 契约 | `OrderStatus` 枚举加一个值（只增） | 无 | 无 |

(丙) 说不出第二个实现，按 09 号约定不做。(乙) 的两个用户形状不同：一个是带补偿的多步编排，另一个是延迟轮询，硬抽成一个"作业队列"，两边都要将就。(甲) 让状态自己说明自己，崩溃后的世界就是"一张停在 CONFIRMING 的订单"，对 AI 和人都最好读。选 **(甲)**。im-dingtalk 的回查用它自己的 `next_poll_at` 扫描（§2.5），也是"状态在业务行上"，同一个模式，不需要 SDK 抽象。

**对账时向前推进还是退回**：④ 成功、⑤ 没做的单，对账时向前推进成 CONFIRMED。理由：用户发出的就是"确认"，信用已经在③校验过，预留也成功了；用户拿到的是超时 / 503，契约本来就说"带同一个键重试，结果可能已经发生"。退回会和用户的同键重试打架：重试拿到的是一份已经撤销的预留。§7 第 8 点。

### 4.3 推荐

**erp/inventory 2.1.0**

- 迁移：`inventory_reservations` 加 `expires_at TIMESTAMPTZ NULL`、`held_at TIMESTAMPTZ NULL`、`cancel_reason TEXT NOT NULL DEFAULT ''`；部分索引 `(expires_at) WHERE status = 'RESERVED' AND expires_at IS NOT NULL`。
- 契约（只增）：`ReserveRequest.hold_seconds`；`ReserveResponse.status`（重放时如实报当前状态）；新 rpc `HoldReservation(idempotency_key, reservation_id) → status`（状态内省语义：RESERVED → 清掉 `expires_at`、记 `held_at`，答 RESERVED；已经 CANCELLED（含过期）就如实答 CANCELLED 和 `cancel_reason`）；`GetReservationStatus` 的响应加 `cancel_reason`；新事件 `erp.inventory.reservation.expired.v1`。
- 清扫循环（每 30 秒）：`UPDATE … WHERE id IN (SELECT … WHERE status = 'RESERVED' AND expires_at < now() FOR UPDATE SKIP LOCKED LIMIT 100)`，按行释放 `reserved_qty`、置 CANCELLED + `cancel_reason = 'EXPIRED'`、进 outbox，和 `CancelReservation` 同一段释放代码。
- 配置：`RESERVATION_MAX_HOLD_SECONDS`（默认 3600），调用方传更大的值时截到上限。
- 没有 TTL 的旧预留：仓管的 REST 加一个"RESERVED 超过 N 天的预留"列表（只读），给人工排查。

**erp/sales 2.1.0**

- 订单状态机加 `CONFIRMING`：DRAFT → CONFIRMING → CONFIRMED / DRAFT / SUSPENDED。列：`reserve_key`、`reservation_id`、`confirm_started_at`、`hold_pending BOOLEAN`、`release_pending BOOLEAN`。
- `ConfirmOrder` 新流程：
  1. 幂等预查（`IdemLookup`，§5）；范围检查；①②③。
  2. **事务一**：锁单，DRAFT → CONFIRMING，记 `reserve_key = <键>:reserve`、`confirm_started_at`；`IdemClaim`（两段式，状态 CLAIMED）。
  3. `Reserve(hold_seconds = 900)`；超时就 `GetReservationStatus`（同今天）。
  4. **事务二**：CONFIRMING → CONFIRMED，写 `reservation_id`、`hold_pending = true`，进 outbox（`sales.order.created.v1`），`IdemComplete`。
  5. `HoldReservation`；成功就清 `hold_pending`；失败不管，交给对账。
  6. 任何一步明确失败：事务里 CONFIRMING → DRAFT，`IdemRelease`；有预留就置 `release_pending = true`，由对账释放。
- 对账循环（`internal/tcc/reconcile.go`，每 30 秒，`FOR UPDATE SKIP LOCKED`）：
  - CONFIRMING 且超过 2 分钟：`GetReservationStatus(reserve_key)` → RESERVED：向前推进（第 4、5 步）；NOT_FOUND / CANCELLED：退回 DRAFT 并 `IdemRelease`；再超时：下一轮。
  - `hold_pending`：`HoldReservation` → RESERVED：清标记；CANCELLED（过期了）：挂起订单，开异常待办（"预留已过期，需要重新预留或取消"）。
  - `release_pending`：`CancelReservation`；连续 3 次失败 → SUSPENDED + 异常待办（保留今天的三次规则，计数仍在 `compensation_attempts`）。请求里的 sleep 循环删掉。
- `sales_order_reconciliation_queue`：停止写入；表在下一个版本删除。
- 赢单路径：`Run` handler（§2.5），建单 + 确认走同一套状态机；失败返回 error，靠重投重试；重投耗尽进 DLQ 时开异常待办。
- 契约（只增）：`OrderStatus` 加 `CONFIRMING`；06c 的前端展示"确认中"。
- 下游 pin：`erp/inventory@2.1.0`。

### 4.4 SDK API

不加 saga 或作业抽象。SDK 只提供本议题用到的通用件，都在别的议题里定义：`IdemClaim` / `IdemComplete` / `IdemRelease`（§5，两段式命令）、`Subscription.Run`（§2）。周期循环的写法（ticker + 单轮失败只记日志 + ctx 取消返回）今天在每个组件的 `partition` 包里各抄了一份，是否收进 SDK 由 `sdk-redesign.md` 定。

### 4.5 先写的红测试

erp/inventory（真 PG）：

- `TestReserve_带hold_seconds到期后被清扫释放并发expired事件`
- `TestReserve_hold_seconds为0时永不过期`（守住旧调用方）
- `TestHoldReservation_清掉过期时间后不再被清扫`
- `TestHoldReservation_已过期答CANCELLED和原因`
- `TestReserve_重放如实返回当前状态`
- `TestSweep_两个副本并发清扫不重复释放`

erp/sales（真 PG + 假 inventory gRPC）：

- `TestConfirm_预留成功后停在落库前_对账向前推进为CONFIRMED`（用测试钩子在第 3、4 步之间返回）
- `TestConfirm_预留NOT_FOUND_对账退回DRAFT且同键可以重试`
- `TestConfirm_CONFIRMING期间同键重放答进行中`
- `TestConfirm_CONFIRMING期间取消被拒`
- `TestReconcile_Hold答已过期时挂起订单并开待办`
- `TestReconcile_释放预留连续三次失败挂起订单`
- `TestReconcile_两个副本不重复处理同一张单`

## 5. 议题四：幂等重放绑定（安全）

### 5.1 现状与证据

| 组件 | 认领方式 | 重放时核对了什么 | 可被利用的问题 |
|---|---|---|---|
| crm/opportunity 2.0.0 | claim-first（`repo/repo.go:66`） | **什么都没核对**：`runCommand` 拿键查 `result_id` 直接返回那条商机（`repo/write.go:37-43`） | ① `CreateOpportunity` 在 service 层没有范围检查（`service/service.go:166-219`），拿公开的种子键（`seed-opp-1`…）重放就能**读到别部门的商机**；② `Update` / `ChangeStage` / `MarkWon` / `MarkLost` 检查的是请求里的 id（`service.go:239,260,281,302`），重放返回的却是键对应的那条——**传自己的商机 id + 别人的键，读到别人的商机** |
| erp/finance 2.0.0 | claim-first（`repo/repo.go:73-104`） | 不核对命令、不核对目标（`lookupIdempotencyResult` 只按键查，`repo.go:97-104`） | ③ `PostManualEntry` 只校验**请求里的**法人（`repo/manual.go:33`），重放返回键对应的那张凭证（`manual.go:42-48`）——**读到别的法人的凭证**；④ `ReverseEntry` 重放（`manual.go:93-99`）发生在法人校验（`manual.go:106`）之前；⑤ 期间操作：关账的键拿去反关账，返回"CLOSED"当作成功（`repo/period.go:72-74`） |
| erp/inventory 2.0.0 | claim-first（`repo/repo.go:58-71`） | 不核对命令、目标（`repo.go:82-89`） | ⑥ `Receive` / `Adjust` 重放（`repo/movement.go:116-117`）在仓库授权（`movement.go:125`）之前：没有这个仓库权限的人也能拿到"成功"和一个 movement_id；⑦ `CancelReservation` 的键拿去撤另一份预留，返回第一份的状态（`repo/reservation.go:179-180`）——**调用方以为撤了，实际那份预留还占着库存**；⑧ 一个命令的键被另一个命令重放，`Reserve` 会把 movement_id 当 reservation_id 返回（`reservation.go:57-58`） |
| erp/sales 2.0.0 | claim-first | **核对了命令与订单**（`repo/repo.go:134-154`）；建单重放还核对调用者范围（`tcc/create.go:49-58`） | ⑨ 不核对请求体：同一个人同一个键换了客户 / 明细，静默拿回旧单；⑩ **系统派生键和用户键在同一个命名空间**：赢单用 `crm-won:<商机 id>`（`tcc/opportunity_won.go:74,136`），用户先用这个键调 REST 建单，商机赢单时就会拿回用户那张单当成转单结果 |
| infra/workflow 2.0.1 | claim-first（`repo/idempotency.go:14`） | 核对命令（`idempotency.go:51-61`），不核对目标 | ⑪ `CloseTask` / `CancelTask` 的键拿去关另一条待办，返回第一条（`repo/actions.go:127-133,168-173`）。只有组件间 gRPC 调用，没有用户越权，但同样是"以为关了" |
| mdm/customer 2.0.1、mdm/product 2.0.0 | **先查后插**（`mdm/customer/backend/internal/repo/write.go:14-20,27-38,95,109`；product `write.go:25-37,106,115`），违反 02-backend.md"claims it first with an atomic INSERT … ON CONFLICT" | 不核对命令、目标 | ⑫ 并发的同键请求，后提交的那个撞主键、整个事务回滚、拿到错误，而不是重放；⑬ `Update` 的键拿去 `SetStatus`，返回"成功"。mdm 是 `data_scopes: none`，越权读不成立 |
| infra/iam-casdoor 2.0.0 | 建了 `command_idempotency` 表，代码从没用（`migrations/002_create_outbox_inbox.up.sql`） | — | 死表 |
| infra/notification 2.0.0 | 已删表（`migrations/003_drop_unused_command_idempotency.up.sql`） | — | — |
| infra/print、infra/authz | 没有带键的写命令（print 是纯函数，`print.proto:13,51`） | — | — |
| infra/bff-mobile | 只透传（`src/resolvers/task.ts:97-104`） | — | — |

共同点：

- **所有表都没有保留期**，不分区、不清理，按写命令数无限增长。
- 七个组件各自手写了一份 claim / finalize / lookup，五种细节不同的变体。
- 种子键是固定的、写在公开脚本里（`components/crm/opportunity/scripts/seed.sh:2-7` 的 `seed-opp-1..10` 横跨 `dev.superuser` 与华东分部两个身份；`components/erp/sales/scripts/seed.sh:4` 同理），所以"猜不到别人的键"不是防线。

### 5.2 方案

| | (a) 命名空间 + 绑定（推荐） | (b) 只绑定，调用者不同报错 | (c) 各组件自己修 |
|---|---|---|---|
| 主键 | `(caller, key)` | `key`，`caller` 是绑定列 | 各自 |
| 别人的键 | 当作新键执行，读不到、也不报错 | `InvalidArgument` | — |
| 探测"这个键存在吗" | 不可能 | 可以（报错与否就是信号） | — |
| 抢注系统派生键（⑩） | 不可能（system 与 user 不同命名空间） | 抢注者让系统命令**失败**（拒绝服务） | — |
| 同一调用者换命令 / 目标 / 请求体 | `InvalidArgument` | 同左 | — |
| 代码 | SDK 一处 | SDK 一处 | 七处，下一个组件重犯 |

任务描述里写的是 (b)。(a) 在所有维度上都不比 (b) 差，并且多挡住两类问题，推荐 (a)（§7 第 4 点）。

### 5.3 推荐与 SDK API

**Go**

```go
type Command struct {
	Key     string // 客户端给的 idempotency_key
	Name    string // 用权限键：erp.sales.confirm
	Target  string // 命令作用的聚合 id；建类命令留空
	Request any    // 参与指纹的业务字段（不含键本身、不含时间戳）；SDK 规范化 JSON 后 sha256
}

type Prior struct {
	Found      bool
	InProgress bool            // 两段式命令认领了还没完成
	Result     json.RawMessage // IdemComplete 存进去的结果
}

var (
	ErrIdempotencyMismatch   error // 实现 GRPCStatus() → InvalidArgument；SDK 的 HTTP 映射 → 400
	ErrIdempotencyInProgress error // → Aborted；→ 409
)

func CallerOf(ctx context.Context) string // user:<sub> | system

// 一步式：在同一个 WithTx 事务里认领 → 执行 → 完成；重放时不调 do
func Idempotent[T any](ctx context.Context, tx *sql.Tx, c Command, do func() (T, error)) (res T, replayed bool, err error)

// 两段式（sales 的确认：认领与完成隔着网络调用）
func IdemLookup(ctx context.Context, tx *sql.Tx, c Command) (Prior, error)  // 只读预查；不一致 → ErrIdempotencyMismatch
func IdemClaim(ctx context.Context, tx *sql.Tx, c Command) (Prior, error)   // Found=false 即认领成功
func IdemComplete(ctx context.Context, tx *sql.Tx, c Command, result any) error
func IdemRelease(ctx context.Context, tx *sql.Tx, c Command) error          // 退回时删掉认领，同键可以重试
```

清理由 `RunEvents` 的维护循环顺带做（`DELETE … WHERE expires_at < now()`，每批 1000 行）；不跑事件的组件（目前没有带键写命令的组件不跑事件）不需要单独入口。保留期常量 30 天，`Command` 不开放覆盖——一个项目一个规则。

**调用顺序（写进 02-backend.md）**：参数校验 → 对 target 的授权与数据范围检查 → 幂等（预查或认领）→ 状态校验 → 业务写。建类命令的重放结果要再过一遍组件自己的范围内读取，不在范围内按 `ErrIdempotencyMismatch` 处理——在 (a) 下同一调用者才会命中，所以只有"调用者的范围变了"（换了部门）时才会触发。

**Python**

```python
@dataclass(frozen=True)
class Command:
    key: str
    name: str
    target: str = ""
    request: Any = None

class IdempotencyMismatch(InvalidArgument): ...
class IdempotencyInProgress(Aborted): ...

def caller_of(claims: Claims | None) -> str
async def idempotent(conn: asyncpg.Connection, cmd: Command, do: Callable[[], Awaitable[T]]) -> tuple[T, bool]
async def idem_lookup(conn, cmd) -> Prior
async def idem_claim(conn, cmd) -> Prior
async def idem_complete(conn, cmd, result) -> None
async def idem_release(conn, cmd) -> None
```

目前没有 Python 组件带键写命令，Python 版和 Go 同一版发布，保证"下一个 Python 组件不会自己再写一份"。

**TS**：不加存储 API（没有数据库）。bff 继续原样透传 `idempotency_key`；前端每个用户动作生成一个 UUIDv7，同一动作的重试复用它（06c 的前端约定）。

### 5.4 各组件改动与版本

全部：迁移把 `command_idempotency` 改成 §1.3 的形状（加列、换主键；旧行 `caller = 'legacy'`，新调用者永远命中不到它们——生产环境还没有数据，跨升级的同键重试会被当成新命令，可以接受）；删掉组件里手写的 claim / finalize / lookup；`ToStatus` 里加 `ErrIdempotencyMismatch` / `ErrIdempotencyInProgress` 的映射（或者直接靠 `GRPCStatus()`）。

| 组件 | 特有改动 | 版本 |
|---|---|---|
| crm/opportunity | `runCommand` 改成 `Idempotent`，`Target` = 商机 id，`Create` 带请求指纹 | 2.0.1 |
| erp/finance | 期间操作 `Target = <法人>/<期间>`；`ReverseEntry` 的 `Target` = 原凭证 id，幂等移到法人校验之后；`PostManualEntry` 的重放结果再按法人授权读一遍 | 2.1.0（和 §3 一起） |
| erp/inventory | `Receive` / `Adjust` 的幂等移到仓库授权之后；`Reserve` 带请求指纹（明细）；`CancelReservation` / `ConfirmIssue` / `HoldReservation` 的 `Target` = reservation_id；`GetReservationStatus` 按 `(system, key)` 查 | 2.1.0（和 §4 一起） |
| erp/sales | 四个命令改用 SDK（确认是两段式）；`crm-won:` 系列键自动落在 system 命名空间 | 2.1.0（和 §4 一起） |
| infra/workflow | 三个命令改用 SDK，`CloseTask` / `CancelTask` 的 `Target` = 任务 id | 2.0.2 |
| mdm/customer | 先查后插改成 SDK 认领；`Update` / `SetStatus` / `AddContact` 的 `Target` = 客户 id | 2.0.2 |
| mdm/product | 同上 | 2.0.1 |
| infra/iam-casdoor | 删掉死表的迁移留到下一个版本；这次只在 §3 里改契约 | 2.1.0（和 §3 一起） |

### 5.5 先写的红测试

SDK（真 PG）：

- `TestIdem_同键同命令同目标重放返回首次结果`
- `TestIdem_同键换命令InvalidArgument`
- `TestIdem_同键换目标InvalidArgument`
- `TestIdem_同键换请求体InvalidArgument`
- `TestIdem_不同调用者同键各自执行互不可见`
- `TestIdem_系统命名空间与用户命名空间隔离`
- `TestIdem_并发同键只执行一次后到者拿到重放`
- `TestIdem_两段式认领期间重放答进行中`
- `TestIdem_Release之后同键可以重来`
- `TestIdem_过期键被清理后当作新键`

组件（在今天的代码上跑红，越权的几条优先）：

- crm/opportunity：`TestCreate_用别人的公开种子键拿不到别人的商机`、`TestMarkWon_自己的商机配别人的键拿不到别人的商机`。
- erp/finance：`TestPostManualEntry_重放拿不到别的法人的凭证`、`TestReverseEntry_重放不绕过法人授权`、`TestClosePeriod的键用于Reopen答InvalidArgument`。
- erp/inventory：`TestReceive_重放不绕过仓库授权`、`TestCancelReservation_同键换预留答InvalidArgument`。
- erp/sales：`TestCreateOrder_用户抢注crm-won键不影响赢单转单`、`TestCreateOrder_同键换明细答InvalidArgument`。
- infra/workflow：`TestCloseTask_同键换待办答InvalidArgument`。
- mdm/customer、mdm/product：`TestCreate_并发同键只建一条且后到者拿到重放`。

## 6. 整体落地顺序

贴合 06b 现状：13 个后端组件都已发布 2.x（各自工作区干净、在 tag 上）；外壳 T21–T24 还是空壳（`shell/be/*/component.yaml` 的 `members: []`）。

1. **拍板**（§7），然后在 `docs/en/02-decisions/` 写新决策（中英镜像）：事件至少一次送达与建流方式；幂等键按调用者分命名空间；不分区但有保留期的 SDK 表算作"有界表"的例外。
2. **SDK**：be-sdk-go、be-sdk-python 各 v0.6.0。先提交 §2.6 第一条红测试（分区 inbox 并发重复，今天就红），再做兼容层，再做新 API（`Publish` / `RunEvents` / `Snapshot` / `Idempotent` 系列）。tag 与推送留给控制者。
3. **只升 SDK 也能马上得到的收益**：兼容层让 2.0.x 组件不改代码就是至少一次送达，并修掉并发重复。这一步不单独发组件版本，直接进第 4 步。
4. **组件按依赖顺序发版**（每个组件一个版本，三类改动一起做；Go 组件双 tag，`/v2` 模块路径不变）：
   - 第一批（上游、只被读）：mdm/customer 2.0.2、mdm/product 2.0.1、infra/authz 2.0.2（只升 SDK + 新表）、infra/iam-casdoor 2.1.0（`User.version` / `disabled`）。**authz 与 iam 发版后同一批改 `config/vars.yaml` 的 `AUTHZ_BUNDLE_URL` / `IAM_JWKS_URL`**，并核对 `brickkit.yaml` 里其它组件的字面量（`make gates` 的 `service-hostname-scan`）。
   - 第二批（枢纽与基础服务）：erp/inventory 2.1.0、erp/finance 2.1.0、infra/workflow 2.0.2、infra/notification 2.1.0、integration/im-dingtalk 2.0.1、infra/print 2.0.1（Python）。
   - 第三批（编排者）：erp/sales 2.1.0（pin inventory@2.1.0、customer@2.0.2、product@2.0.1、workflow@2.0.2）、crm/opportunity 2.0.1。
   - infra/bff-mobile：TS SDK 不变；只在它 pin 的组件版本变了时跟着改 pin（workflow@2.0.2）→ 2.0.1。
   - 每个组件：`brickkit upgrade` 进项目，真机 `make verify`，跑完 `brickkit down`。
5. **项目正式文档**（中英各一份，`make docs-mirror`、`make docs-boundary`）：`02-backend.md` 的 Events and cross-component writes（JetStream、DLQ、两种 handler、建流、调用顺序）与 Database（`event_cursor`、`command_idempotency`、保留期）；根 `AGENTS.md` 易错点表加两行：手写 `command_idempotency` SQL；在 inbox 事务里做网络调用。
6. **be-acceptance 门禁**：组件代码里出现 `command_idempotency` / `event_inbox` 的手写 SQL 即失败；`besdk.Consume(` 在 v0.7.0 之前只警告；每个 `Subscription` 至少有一个测试引用它的 subject。
7. **外壳 T21–T24**：`go.mod` 钉 be-sdk-go v0.6.0；外壳本身不需要知道事件。

## 7. 需要拍板的点

1. **建流方式**：SDK 按 subject 第一段"没有就建、有就不碰"（推荐），还是 be-ops 登记表 + `make nats-init`。
2. **流的默认值**：域流 7 天 / 1 GiB / 丢旧，DLQ 30 天。
3. **新 durable 从哪开始**：`DeliverAll`（推荐，补收流里剩下的）还是 `DeliverNew`。影响：新装的 finance 会补记装之前 7 天内确认的订单。
4. **幂等键命名空间**：主键含调用者（推荐，§5.2 (a)），还是任务描述里的"调用者不同报 InvalidArgument"（(b)）。
5. **幂等键保留期**：30 天（推荐），写进契约。
6. **两张只写不读的快照**：inventory 是实现批次 / 序列号校验（推荐，需要 `mdm/product` 可选依赖，只在 `Start()` 回填里用），还是删掉；opportunity 删掉（推荐）还是用到列表页。
7. **finance 缺额度时**：记"待补判"表、补判时再发 `credit.rejected`（推荐），还是缺快照就当作超限（fail-closed，会误挂起新客户的单）。
8. **孤儿确认**：对账时向前推进成 CONFIRMED（推荐），还是退回 DRAFT 并撤销预留。
9. **预留期限**：sales 用 900 秒，inventory 上限 3600 秒；没有期限的旧预留只做只读排查列表。
10. **历史 subject 命名**：`sales.*`、`finance.*` 不带 `erp.` 前缀，保持不改（推荐，契约只增；每个第一段一个流就把它吸收了），还是双发迁移。
11. **时机**：全部在外壳 T21–T24 之前做完（推荐），还是先组外壳、之后再整体升一轮。
12. **"无界表必须分区"的例外**：`event_cursor`、`command_idempotency` 不分区、靠保留期有界（推荐，分区键进主键会让去重失效，正是 §2.1.2 的问题），需要在 02-backend.md 写成明文例外。和 `data-layer.md` 的冷热数据结论对齐。
13. **DLQ 谁来看**：先给项目加 `make dlq-ls` / `make dlq-replay`（推荐），还是等一个 `infra/dlq-monitor` 组件。

## 8. 相邻发现（不在四个议题内，记下备查）

- finance 不消费 `sales.order.cancelled.v1`（`erp/finance/backend/internal/consumer/consumer.go:28-31`）：确认后取消的单不冲销应收、不释放已用额度，额度只增不减。
- `finance.credit.rejected.v1`、`infra.notification.sent/failed.v1` 的 `Version` 恒为 1（`autoentry.go:150`、`notification/.../consumer.go:347,357`）：按今天的聚合粒度没问题；§1.2 的规则要求"同一 (subject, aggregate) 严格递增"，写进事件约定，免得以后有人在长生命周期聚合上照抄。
- subject 第一段不统一：`erp.inventory.*` 带域，`sales.*`、`finance.*` 不带（opportunity 的注释已经记了，`crm/opportunity/backend/internal/consumer/consumer.go:33`）。
- 各组件的 `partition` 包把同一段"建未来周分区"的代码各抄了一份；收进 SDK 由 `sdk-redesign.md` 定。
- `event_inbox` 的 `max(version)` 查询没有索引，随时间线性变慢（§2.1.2）；兼容层期间可以给旧表补一个 `(subject, aggregate_id)` 索引。
- 和另外三份文档的接口：`CallerOf` 在 gRPC 上的服务身份 → `identity-permissions.md`；不分区表的保留与冷热 → `data-layer.md`；`RunEvents` 放在模块生命周期的哪里、`role` / `schema` 要不要折进 rt → `sdk-redesign.md`。
