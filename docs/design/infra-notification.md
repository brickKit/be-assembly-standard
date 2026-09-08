# infra-notification · 统一通知中心 设计计划

| 项 | 值 |
|---|---|
| 组件 ID | `infra/notification` |
| 仓库名 | `infra-notification` |
| 端口 | HTTP `8202` / gRPC `9202` ← 抄 `registry/ports.tsv` |
| schema / role | `infra_notification` / `infra_notification_rw`（归档 `infra_notification_archive`） |
| 语言 | Go |
| 框架栈 | Gin + `database/sql`+`pgx stdlib` + `sqlc` + `golang-migrate`（设计书 §12.4） |
| 合并部署时进 | 外壳三 `go-infra` |
| 装配角色 | `default` |
| 阶段 | 第三阶段 |

> 规范源是设计书 **§6.7**：接收业务组件的"通知意图"和系统告警，**根据用户通道偏好**，并发路由给下层
> **所有已装配的** `channel_adapter`。它要解决的三件事：密钥管理混乱、重试逻辑重复、无法实现用户级通道偏好。

## 1. 边界

**归我：**

- **意图 → 消息的翻译**：业务侧表达的是"张三有一条审批待办"，我决定这变成几条消息、发去哪些通道。
- **用户通道偏好**：谁想在哪收。这是 §6.7 点名要解决的三件事之一。
- **收件人联系方式快照**：`sub` → 手机号/邮箱，从 `infra-iam-casdoor` 的事件维护（§4）。
- **投递状态与重试**：发出去了没有、失败了重试几次、最终进不进 DLQ。**重试逻辑只在我这里写一遍**（§6.7 第二件事）。
- **通知历史**：谁在什么时候收到过什么。

**不归我：**

| 什么 | 归谁 | 为什么 |
|---|---|---|
| **调外部 API 的那一下**（钉钉/邮件/短信） | `integration-*` 适配器 | §6.9：适配器只监听事件 + 调外部 API + 发回调事件。**外部平台的密钥、SDK、限流全在适配器里**——这正是 §6.7 说的"密钥管理混乱"的解法：我一把外部密钥都不持有 |
| **"什么情况下该通知"** | 业务组件 / `infra-workflow` | 那是业务规则。我只在收到"请通知"的信号后才动 |
| 通知文案的业务措辞 | 触发方（放进事件 payload） | 我做的是模板渲染，不是决定"驳回时该说什么" |
| 用户身份、手机号的**权威值** | `infra-iam-casdoor` → Casdoor | 我持的是**快照**，权威源在那边（同 `erp-inventory` 持 `tracking_type` 快照的先例） |
| 站内信的前端展示 | `frontend-standard` | 我提供 REST 读接口，不管渲染 |

**数据权限**：`data_scopes` 一维——通知历史只该本人看得见。

```yaml
data_scopes:
  - { dimension: owner, column: recipient_sub, mode: equals, tables: [notification_records] }
```

⚠️ **这一维不是可选的**：通知内容里会出现单据标题、金额这类摘要，**看得到别人的通知等于绕过了业务组件的数据权限**。这是"悄悄读到别人数据"的又一条路径，只不过换了个入口。

## 2. 拥有的数据

| 表 | 分区键 | 粒度 | 说明 |
|---|---|---|---|
| `notification_records` | `created_at` | **月** | 每条通知一行：收件人、通道、内容快照、投递状态、重试次数。**§11.2.5 分区清单里点名的表** |
| `notification_preferences` | 不分区 | — | `sub` × 通知类别 → 开/关哪些通道。按用户数有界 |
| `user_contacts` | 不分区 | — | `sub` → 手机号/邮箱/显示名 + `version`。**iam 事件的快照**，按用户数有界 |
| `command_idempotency` | 不分区 | — | 幂等声明（claim-first，同 `erp-inventory` 先例） |
| `event_outbox` / `event_inbox` | `created_at` | 周 | 标准两张 |

强制字段全部符合 §11.2.1。

**终态列表**：`notification_records` 的 `SENT` / `FAILED_PERMANENT` / `SUPPRESSED`（被用户偏好挡掉）。活跃态：`PENDING` / `RETRYING`。

⚠️ **`notification_records` 是本组件唯一会无限增长的表**，也是它出现在 §11.2.5 而 `infra-workflow` 不在的原因：**一条待办可能触发多条通知**（多通道 × 多次提醒），量级是待办的几倍。按月分区、超期归档。

## 3. 契约面

**gRPC（`infra.notification.v1.NotificationService`）：**

| rpc | 类型 | 幂等键 | 说明 |
|---|---|---|---|
| `BatchGetRecords` | 读 | — | §3.8 强制的 `batchGet` |
| `ListRecords` | 读 | — | 我的通知历史，**走 `ScopeFilter`** |
| `GetPreferences` / `SetPreferences` | 读 / 命令 | `sub` | 通道偏好 |

**对外 REST 路径前缀：** `/infra/notification/**`

| 路径 | 权限键 | 说明 |
|---|---|---|
| `GET /notifications` | `infra.notification.view` | 我的通知历史（站内信列表） |
| `GET /preferences` / `PUT /preferences` | `infra.notification.preference.edit` | 我的通道偏好 |
| `GET /admin/records` | `infra.notification.admin` | 排障用：查某条通知为什么没发出去 |

### 3.1 ⭐ 为什么没有 `Notify` 这个 rpc：唯一入口是事件

**看起来最自然的设计是给业务组件一个 `Notify(intent)` 同步接口。本组件刻意不提供它**，理由是一条硬约束加一条判断：

| 理由 | 说明 |
|---|---|
| **我是 `default` 但可被裁** | 任何同步调我的组件都要建依赖边。装配时若没装我，那条边就是缺失的弱依赖——**而"通知发不出去"绝不该让业务动作失败**。走事件天然没有这个问题 |
| **`infra-workflow` 根本不能同步调我** | 它的 §6.6 铁律三禁止反向同步调用，而待办通知恰恰是本阶段唯一的通知场景。既然主要来源只能走事件，再为别人开一个同步口就是**两套入口、两套幂等、两套重试** |

**所以：谁要通知，谁发自己的领域事件，我来消费。**

⚠️ **本阶段我只消费一条业务来源事件**（`infra.workflow.task.created.v1`），因为阶段三只有"审批待办"这一个通知场景。**这是刻意的 YAGNI**，不是遗漏：

> **泛化的触发点写死在这里**：当"我要消费的通知来源事件"**超过 5 条**时，改成通用意图事件（发布方统一发 `infra.notification.requested.v1`，payload 自带收件人与模板）。**在那之前不许提前抽象**——每多消费一条事件只是多一小段收件人提取逻辑，而通用意图事件要求所有发布方都改，是更贵的一步（判据同总纲 SOP-P：逻辑本身简单却硬套模式是更糟的结果）。

⚠️ **每多消费一条来源事件，就要多问一次"收件人从哪来"**——这段提取逻辑是本组件唯一贴近业务的地方，必须保持薄：只做"从 payload 里取 `assignee`"这种直取，**不许出现"如果金额大于 X 就抄送给主管"这类判断**（那是业务规则，属于触发方）。

## 4. 事件

**发布：**

| subject | 分级 | 何时发 | payload 要点 |
|---|---|---|---|
| `infra.notification.dispatch.im.v1` | 核心 | 决定要走 IM 通道发一条 | `record_id`、`target_adapters[]`（如 `["dingtalk"]`）、收件人**手机号**、渲染好的文本 |
| `infra.notification.dispatch.email.v1` | 核心 | 走邮件（阶段三无适配器，先留 subject） | 同上，收件人邮箱 |
| `infra.notification.sent.v1` | 旁路 | 某条通知最终成功 | `record_id`、通道。供审计与监控 |
| `infra.notification.failed.v1` | 旁路 | 重试耗尽、永久失败 | `record_id`、通道、最后一次错误 |

⚠️ **`target_adapters[]` 这个字段是给"一个通道类型下有多个适配器"准备的**：`channel:im` 族有 5 个成员（钉钉/企业微信/飞书/Slack/Teams），它们**都订阅同一个 `dispatch.im` subject**。而 NATS 核心是**广播**——每个跑着的适配器都会收到每一条（阶段二踩坑记录 E1 记的就是这个语义）。所以适配器收到后**先看 `target_adapters` 里有没有自己，没有就丢弃**。

> 这样做的好处是**加一个 IM 适配器不用改我**；代价是消息被多投递几次（都在同一台机器的内存总线上，可忽略）。⚠️ **别改成"每个适配器一个 subject"**——那我就要知道装了哪些适配器，等于把装配期的知识搬进运行时。

**消费：**

| subject | 来自 | 做什么 | 幂等与乱序怎么处理 |
|---|---|---|---|
| `infra.workflow.task.created.v1` | `infra-workflow` | ⭐ 本阶段唯一的通知来源：取 `assignee` → 查偏好 → 建 `notification_records` → 发 dispatch | 幂等键 = 事件 id；inbox 去重 + `command_idempotency` 两层（同 `erp-finance` 先例） |
| `infra.iam.user.created.v1` / `.updated.v1` / `.disabled.v1` | `infra-iam-casdoor` | 维护 `user_contacts` 快照（手机号/邮箱/显示名） | 按 `version` 单调比较，旧的丢弃 |
| `integration.im.result.v1` | 任一 `channel:im` 适配器 | 更新 `notification_records` 的投递状态；失败且 `retryable=true` 才安排重试 | 幂等键 `record_id + adapter + attempt` |

⚠️ **最后一条是族级 subject（`integration.im.result.v1`），不是每个适配器一条。** 具体是谁发的放在 payload 的 `adapter` 字段里。这样**装第二、第三个 IM 通道时我一行都不用改**——否则每加一个适配器都要来改我的消费列表，`channel:im` 这个族就白分了。

⚠️ **`retryable` 由适配器判定、重试由我执行**，两边分工不能混（详见 `integration-im-dingtalk` 设计计划 §4.1）：只有适配器认得出"钉钉说这个人不在企业里"是永久失败，而只有我知道该隔多久重试第几次。**两边都判会打架，都不判会给离职员工重试五次。**

⚠️ **`user.disabled.v1` 必须消费**：人走了还继续给他发审批通知，是本组件最容易出的、**外部可见**的错。

## 5. 依赖

**强依赖**：无。
**弱依赖**：无。

**明确不依赖：**

| 谁 | 为什么不建依赖边 |
|---|---|
| `infra-iam-casdoor` | ⭐ 联系方式走**事件快照**，不同步调它。这条不只是偏好——`iam` 是 `slot:iam`，**对槽位建依赖边会当场废掉整个槽位机制**（§5.11 硬约束、`infra-iam-casdoor` 设计计划 §5） |
| `integration-*` 适配器 | 走 dispatch 事件。它们是 `channel:*` 族、可装可不装，同步调等于要求它们必须存在 |
| `infra-workflow` | 我消费它的事件，方向单向 |
| `infra-authz` | 同所有组件：`authzBundleUrl` 配置项，不是依赖边 |

**零出边。** 谁都不调，只消费事件、只发事件。

## 6. 在同步图与三枢纽里的位置

**我不在同步图里**——零出边，也没有任何组件对我建同步边（§3.1 解释了为什么不提供 `Notify` rpc）。我完全活在**事件图**上。

因此**不可能引入环**，也与 §1.4 的"CRM 与 ERP 零同步边"无关。

与三枢纽的关系：形态上最接近 `erp-finance`（**事件汇枢纽**）——只消费、不同步调人。区别是 `erp-finance` 消费完落业务账，我消费完发消息出去。

## 7. 分区与归档策略

| 数据 | 热 | 归档条件 | 归档去哪 |
|---|---|---|---|
| `notification_records` | 最近 **3 个月** | 超过 3 个月的整月分区，且状态为终态 | `infra_notification_archive` |
| `notification_preferences` | 永远热 | 不归档 | — |
| `user_contacts` | 永远热 | 不归档（人停用后保留，历史通知要能显示"发给过谁"） | — |
| `command_idempotency` | 最近 90 天 | 超过 90 天直接删 | 不归档 |

⚠️ **归档窗口比别的组件短（3 个月 vs 12 个月）**：通知是**过程数据**，价值随时间掉得比业务单据快得多，而它的增长最快。⚠️ 但仍然要判终态——**一条还在 `RETRYING` 的记录不能因为够老就被归档走**。

## 8. 参考实现

> 完整调研过程见 [`_调研记录/03-阶段三.md`](./_调研记录/03-阶段三.md) 的「infra-notification」一节。下表是精炼版。

| 项目 | 版本/commit | 看的模块 | 借鉴了什么 | 许可证（已复核） | 用法 |
|---|---|---|---|---|---|
| Novu | 📋 开工前填 | Workflow/Step 模型、`subscriber` 与 channel preference 的数据结构 | **"用户级通道偏好"的建模**——它把偏好按 `subscriber × workflow × channel` 三维存，我们本阶段简化成 `sub × 类别 × 通道` | MIT | 借鉴逻辑 |
| Novu | 📋 开工前填 | provider 抽象层 | **反面**：它把 provider（外部平台）做成了内部插件。我们把它拆成独立的 `integration-*` 组件——因为**密钥要跟着适配器走**，塞进通知中心就回到 §6.7 要解决的"密钥管理混乱" | MIT | 借鉴逻辑 |
| ERPNext | 📋 开工前填 | `Notification` doctype + `Email Queue` 的重试与状态机 | 投递状态机（`Queued`/`Sending`/`Sent`/`Error`）与重试计数的落库方式 | GPL-3 | 借鉴逻辑 |
| 钉钉开放平台 | — | 工作通知的形态与限流口径 | **选配测试的素材**：企业 IM 的工作通知有严格频控，佐证"重试逻辑必须集中在一处"（§6.7 第二件事） | 闭源 | 借鉴实际应用 |

**明确没有参考的**：Kafka/RabbitMQ 之类**消息中间件**的重试与死信设计。**不是没查，是层次不同**——那是传输层的重试（`be-sdk` 的 Outbox/Inbox 已经在用），我这里的重试是**业务语义的重试**（"钉钉说这个人不在企业里"要不要重试？不要）。两者混在一起想会得出"让 NATS 帮我重试"的错误结论。

**要避免它的什么：**

| 项目 | 它的做法 | 我们为什么不这么做 |
|---|---|---|
| 多数通知中心 | 通知中心自己持有各平台密钥、内置 provider SDK | 正是 §6.7 点名要解决的"密钥管理混乱"。我们把密钥关进各自的 `integration-*` 组件 |
| 常见做法 | 业务组件直接调通知中心的同步接口 | §3.1：我可被裁、`infra-workflow` 又不能同步调人。走事件 |
| ERPNext | 通知条件用可执行表达式配置（`condition`） | 同 `infra-workflow` 拒绝它的理由：运行时字符串，AI 读不懂也测不了。**"什么情况下通知"归触发方** |

**读完之后，这里有没有「多种实现都合理、只是适配客户不同」的分歧？**

**有一条，判定为不建族。** 分歧是"**多通道到达策略**"：全通道并发发（钉钉+邮件+短信都发）/ 按优先级降级（钉钉发失败才发短信）/ 用户单选一个主通道。三种在现实中都有产品这么做，看起来符合"每一种都合理"。

**但按 R-4 第 3 步判：不建族。** 两条理由：

1. **它不满足"没有依赖边"以外的更前置条件——它根本不需要是一个组件。** 三种策略的差异只是本组件内部一段几十行的路由逻辑 + 偏好表多一列，属于总纲 SOP-P 说的"分歧小到只有几个分支"，**内部策略即可**；
2. 真要做成族，族成员之间的契约面（消费哪些事件、发哪些 dispatch 事件）**完全相同**，差别全在内部——那正是 Fork 点的定义，不是槽位的定义（阶段二复盘 §4 第 5 条的结论在这里同样成立）。

**本阶段实现"全通道并发发 + 用户可关某通道"**，把"按优先级降级"记进 `_可替换性地图.md` 作为本组件的第一个 Fork 点。

## 9. 待决问题

| # | 问题 | 什么时候能有答案 | 答案 |
|---|---|---|---|
| 1 | 通知模板放哪？本组件持有（渲染后发给适配器）还是适配器持有？ | 阶段三 Task 9 与 `integration-im-dingtalk` 一起定 | 📋 倾向**本组件渲染**：适配器要保持"只调 API"的薄度（§6.9），而且同一条通知发到不同通道时文案要一致 |
| 2 | 收件人手机号在 Casdoor 里可能为空（社交登录注册的用户没填手机号），这时审批通知发不出去 | 阶段三 Task 9 实测时 | 📋 对策方向：`notification_records` 记 `SUPPRESSED` + 原因，**在待办界面上显示"未能通知"**，而不是静默失败。⚠️ 与 `infra-iam-casdoor` §1.1 的"社交登录零角色"是同一类问题的两半 |
| 3 | 重试策略的具体参数（次数、退避曲线、什么错误算永久失败） | 阶段三实现时 | 📋 原则已定：**"这个人不在企业里"是永久失败不重试，"网络超时/限流"才重试**。⚠️ 区分不了的错误一律当可重试，但计入次数上限 |
| 4 | 系统告警（§6.7 提到的"和系统告警"）走不走本组件？ | 阶段五 `infra-dlq-monitor` 建成时 | 📋 本阶段不做。⚠️ 若要做，注意**告警的收件人不是业务用户而是运维**，偏好模型可能不通用 |
