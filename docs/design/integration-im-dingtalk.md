# integration-im-dingtalk · 钉钉通道适配器 设计计划

| 项 | 值 |
|---|---|
| 组件 ID | `integration/im-dingtalk` |
| 仓库名 | `integration-im-dingtalk` |
| 端口 | HTTP `8207` / gRPC `9207` ← 抄 `registry/ports.tsv` |
| schema / role | `integration_im_dingtalk` / `integration_im_dingtalk_rw`（归档 `integration_im_dingtalk_archive`） |
| 语言 | Go |
| 框架栈 | Gin + `database/sql`+`pgx stdlib` + `sqlc` + `golang-migrate`（设计书 §12.4） |
| 合并部署时进 | 外壳三 `go-infra` |
| 装配角色 | **`channel:im`**（族内成员：钉钉 / 企业微信 / 飞书 / Slack / Teams，**可多装并存**，不互斥） |
| 阶段 | 第三阶段（族里第一个建的成员） |

> 规范源是设计书 **§6.9**：所有 `integration-*` 适配器职责一致——**只监听事件 + 调外部 API + 发回调事件，严禁包含业务逻辑**。
> ⚠️ 本组件是 `channel:im` 族第一个成员，**它长什么样，后面四个就得长什么样**（§5.11：族内契约面必须完全一致）。
> 所以本文件里凡是写"族级"的地方，都不是本组件的自由，是给后来者立的规矩。

## 1. 边界

**归我：**

- **消费 IM 派发事件**：从 `infra-notification` 收到"发这条消息给这个手机号"。
- **手机号 → 钉钉 userid 的解析**：钉钉的工作通知 API 认 userid，不认手机号（§1.1 解释为什么落在我这里）。
- **钉钉的密钥与 access_token**：AppKey/AppSecret 从 `configSchema` 注入，token 缓存与刷新我自己管。
- **调钉钉开放平台 API 发工作通知**，并把结果发回调事件。

**不归我：**

| 什么 | 归谁 | 为什么 |
|---|---|---|
| **"该不该发这条通知"** | `infra-notification` | §6.9：适配器**严禁包含业务逻辑**。我收到派发事件就发，不判断 |
| **"发给谁"的决策与用户偏好** | `infra-notification` | 同上。我只认 payload 里给的收件人 |
| 文案渲染 | `infra-notification` | 我收到的是渲染好的文本（它的设计计划 §9 第 1 条已定） |
| 重试策略 | `infra-notification` | §6.7 第二件事就是"重试逻辑不要重复写"。**我只报告成败，重不重试它定**（§4 有一个重要例外） |
| 站内信、邮件、短信 | 各自的适配器 / `infra-notification` | 我只管钉钉这一个通道 |

**`data_scopes: none`** ——本组件没有面向用户的数据，只有运维排障用的投递记录。

### 1.1 为什么"手机号 → userid"落在我这里，而不是在 `infra-notification`

**因为它是钉钉特有的**。`infra-notification` 面对的是"所有 IM 通道"，而每家认的收件人标识都不一样：钉钉认 userid、Slack 认 member ID、飞书认 open_id。**把任何一家的解析逻辑放进通知中心，都会让通知中心长出对具体平台的知识**——而那正是 §6.9 要拆开的东西。

所以族级契约是：**`infra-notification` 只给稳定的自然标识（手机号/邮箱），各适配器自己翻译成本平台的 id。**

⚠️ 这条也是 `infra-iam-casdoor` 设计计划 §9 第 3 条的落点：本阶段的登录方式里**没有钉钉**（那份计划 §1.1 定的范围是账密 + 微信 + QQ + Google），所以拿不到 unionid，只能靠手机号匹配。

## 2. 拥有的数据

| 表 | 分区键 | 粒度 | 说明 |
|---|---|---|---|
| `dingtalk_user_map` | 不分区 | — | 手机号 → 钉钉 `userid` 的缓存 + `resolved_at`。**钉钉那个查询接口有频控，不能每发一条查一次** |
| `dingtalk_token` | 不分区 | — | access_token 与 `expires_at`。**单行**。落库而不是只放内存，是因为重启后重新申请会撞频控 |
| `delivery_attempts` | `attempted_at` | 月 | 每次真实调用的结果（请求 id、错误码、耗时）。纯排障用 |
| `command_idempotency` | 不分区 | — | 按 `record_id` 幂等，防重复发同一条消息 |
| `event_outbox` / `event_inbox` | `created_at` | 周 | 标准两张 |

强制字段全部符合 §11.2.1。

**终态列表**：`delivery_attempts` 写入即终态。

⚠️ **`dingtalk_user_map` 要有过期策略**：人离职、换手机号之后钉钉那边的 userid 会失效，而缓存不会自己知道。做法是**发送失败且错误码是"用户不存在"时，删掉这一行并重查一次**——不要靠定时全量刷新（那会把频控吃光）。

⚠️ **手机号是个人信息**：`dingtalk_user_map` 里存的是明文手机号（要拿它去调 API，没法哈希）。这张表的访问只在本组件内，**不许开任何对外查询接口**，也不进任何事件 payload。

## 3. 契约面

**gRPC（`integration.im.v1.ImChannelService`）：**

⚠️ **包名是族级 `integration.im`，不是 `integration.im.dingtalk`。** 五个 IM 适配器实现**同一份** proto（§5.11 族内契约面必须一致）。装了哪几个是装配期的事，调用方不该因为换了通道就改 import 路径。

| rpc | 类型 | 幂等键 | 说明 |
|---|---|---|---|
| `BatchGetDeliveryStatus` | 读 | — | §3.8 强制的 `batchGet`：按 `record_id[]` 查投递结果，排障用 |
| `GetChannelHealth` | 读 | — | 外部平台当前可不可达、token 还有多久过期。**给运维看，不给业务判断用** |

⚠️ **没有任何"发消息"的 rpc，这是刻意的。** 给了它，`infra-notification` 或业务组件就可能同步调我——而**对 `channel:*` 族成员建依赖边，等于要求这个通道必须装**，族的可装可不装当场失效（同 `slot:iam` 那条硬约束的道理，§5.11）。发消息**只能**通过事件进来。

**对外 REST 路径前缀：** `/integration/im/**`（族级前缀）

| 路径 | 权限键 | 说明 |
|---|---|---|
| `GET /admin/deliveries` | `integration.im.admin` | 排障：某条通知发出去没有、钉钉返回了什么 |
| `POST /admin/token/refresh` | `integration.im.admin` | 手动强制刷 access_token（应急用） |

⚠️ **没有 webhook 回调入口**：钉钉的工作通知是**单向推送**，不需要回调地址。将来若接入"用户在钉钉里点了同意"这类交互式卡片，那是一个新的、需要单独设计的入口（§9 第 3 条）。

## 4. 事件

**消费：**

| subject | 来自 | 做什么 | 幂等与乱序怎么处理 |
|---|---|---|---|
| `infra.notification.dispatch.im.v1` | `infra-notification` | ⭐ **先看 `target_adapters` 里有没有 `dingtalk`，没有就直接丢弃**（见下方 ⚠️）；有则解析 userid → 调钉钉 → 发结果事件 | 幂等键 `record_id`，claim-first 声明；重复投递不会发出第二条消息 |

⚠️ **"先看是不是找我的"这一步不能省。** `channel:im` 族的五个适配器**订阅同一个 subject**，而 NATS 核心是**广播**——每个跑着的适配器都会收到每一条派发事件（阶段二踩坑记录 E1 记的正是这个语义：`besdk.Consume` 用的是 `nc.Subscribe` 不是 `QueueSubscribe`）。**漏掉这个过滤的症状是：装了三个 IM 通道的客户，每条通知收到三遍。**

**发布：**

| subject | 分级 | 何时发 | payload 要点 |
|---|---|---|---|
| `integration.im.result.v1` | 核心 | 一次投递尝试结束（成功或失败） | `record_id`、`adapter: "dingtalk"`、`success`、`error_code`、`retryable` |

⚠️ **subject 是族级 `integration.im.result.v1`，不是 `integration.im.dingtalk.result.v1`**，`adapter` 放进 payload。理由：`infra-notification` 只消费**一条** subject 就能处理全部 IM 通道，**加一个适配器不需要改它**。如果按实现名分 subject，每加一个通道都要去改通知中心的消费列表——族就白分了。

### 4.1 ⭐ `retryable` 这个字段是适配器与通知中心的分工线

重试策略归 `infra-notification`（§6.7），但**"这个错误值不值得重试"只有我知道**——钉钉返回的错误码是钉钉特有的：

| 钉钉返回 | `retryable` | 为什么 |
|---|---|---|
| 网络超时、`系统繁忙`、限流 | `true` | 外部临时故障 |
| `用户不存在` / `不在企业内` | **`false`** | 重试一万次也一样。⚠️ 同时删掉 `dingtalk_user_map` 里那一行（§2） |
| AppKey/AppSecret 无效 | **`false`** | 配置错了，重试只会刷屏。要让运维看见 |
| access_token 过期 | `true`，**但我先自己刷一次再报** | 这是我自己的责任，不该消耗通知中心的重试次数 |

**分工是：我判断"是不是值得重试"，它决定"要不要真的重试、隔多久、重试几次"。** 两边都判会得到互相打架的结果；都不判就会出现"给离职员工重试 5 次"。

## 5. 依赖

**强依赖**：无。
**弱依赖**：无。

**明确不依赖：**

| 谁 | 为什么不建依赖边 |
|---|---|
| `infra-notification` | 我消费它的事件、发结果事件回去，**双向都是事件**。同步调它没有任何理由 |
| `infra-iam-casdoor` | ⭐ 我**不**去查用户手机号——手机号由 `infra-notification` 放进派发事件的 payload 里给我。它自己持有 iam 的事件快照（它的设计计划 §2 的 `user_contacts`）。**我多一条到 iam 的边，就等于给 `slot:iam` 加了一个依赖方** |
| 钉钉开放平台 | 它是**外部 SaaS**，不是组件也不是基础资源。地址与密钥走 `configSchema`（`dingtalkAppKey`/`dingtalkAppSecret`/`dingtalkAgentId`/`dingtalkBaseUrl`） |

**零出边**（对组件而言）。唯一的对外调用是钉钉的公网 API。

## 6. 在同步图与三枢纽里的位置

**我不在同步图里**：零出边，且 §3 刻意不提供发消息的 rpc，所以也没有入边。我完全活在事件图的末梢——**是整条通知链路的终点**。

与 §1.4 的"CRM 与 ERP 零同步边"无关（我是 integration 层，两边都不碰）。与三枢纽无关。

⚠️ **我是全系统少数几个"会主动访问公网"的组件之一**。这一点在**客户本地私有化部署**（§9.4）下要写进部署手册：**装了这个组件就意味着这台机器需要能出网到钉钉**，而客户可能是完全内网的。这是装配期就该问清楚的事，不是运行时才发现（§9 第 2 条）。

## 7. 分区与归档策略

| 数据 | 热 | 归档条件 | 归档去哪 |
|---|---|---|---|
| `delivery_attempts` | 最近 **1 个月** | 超过 1 个月的整月分区 | `integration_im_dingtalk_archive` |
| `dingtalk_user_map` | 永远热 | 不归档（失效行是**删**，不是归档，见 §2） | — |
| `dingtalk_token` | 单行 | 不归档 | — |
| `command_idempotency` | 最近 90 天 | 超过 90 天直接删 | 不归档 |
| `event_outbox` / `event_inbox` | 已发布 30 天内 | 超过 30 天 | 清理（§11.7） |

⚠️ **归档窗口是全系统最短的（1 个月）**：投递尝试是纯排障数据，价值只在"刚出问题那几天"。**权威的通知历史在 `infra-notification` 那边**，不在我这里——两边都长期留是重复。

## 8. 参考实现

> 完整调研过程见 [`_调研记录/03-阶段三.md`](./_调研记录/03-阶段三.md) 的「integration-im-dingtalk」一节。下表是精炼版。

| 项目 | 版本/commit | 看的模块 | 借鉴了什么 | 许可证（已复核） | 用法 |
|---|---|---|---|---|---|
| 钉钉开放平台 | 📋 开工前填 | 工作通知（`asyncsend_v2`）、手机号查 userid、access_token 获取与频控 | **本组件全部的对接面。** 🔍 三件事必须核实：① 手机号查 userid 的接口名与权限要求；② 工作通知需不需要 `agent_id`（企业内部应用）；③ access_token 的有效期与并发申请限制 | 闭源平台 | 借鉴实际应用 |
| Novu | 📋 开工前填 | provider 的接口形状（`sendMessage` 的入参出参、错误分类） | **错误分类的思路**——尤其"哪些算永久失败"，对应本文件 §4.1 那张表 | MIT | 借鉴逻辑 |
| Apache Camel | — | Enterprise Integration Patterns 里的 Message Translator / Channel Adapter | **名字的出处**：`channel_adapter` 这个角色定位（把外部协议翻译成内部消息）是 EIP 的标准模式，不是我们发明的。确认了"适配器不该含业务逻辑"是这个模式的题中之义 | Apache-2.0 | 借鉴实际应用 |

**明确没有参考的**：企业微信 / 飞书 / Slack 的 SDK。**不是没查，是刻意留到建那几个成员时再看**——现在照着它们设计会有两种坏结果：要么把族级契约做成三家的最小公倍数（过度设计），要么按钉钉一家定死（后面三家进不来）。**族级契约现在只按"发一条文本给一个人"这个最小交集定**，等真建第二个成员时再按 R-4 复核一次（§9 第 4 条）。

**要避免它的什么：**

| 项目 | 它的做法 | 我们为什么不这么做 |
|---|---|---|
| 多数通知库 | 适配器内部自带重试与退避 | 重试归 `infra-notification`（§6.7）。两处都重试会得到"重试次数相乘"——外面 3 次、里面 3 次，实际发 9 次 |
| 常见做法 | 每个通道一个 subject，通知中心逐个订阅 | 加一个通道要改通知中心。族级 subject + `target_adapters` 过滤（§4） |
| 常见做法 | 适配器直接查用户中心拿收件人标识 | 那会给 `slot:iam` 加依赖方（§5）。收件人由派发事件带进来 |

**读完之后，这里有没有「多种实现都合理、只是适配客户不同」的分歧？**

**有，而且它已经是族了，不需要新增**——`channel:im` 五个成员（钉钉/企业微信/飞书/Slack/Teams）正是"每一种都合理、只是客户不同"的教科书例子：国内企业用钉钉或企业微信，海外用 Slack 或 Teams。**这也是它满足 §5.11 硬约束的原因：没有任何组件对某个具体适配器建依赖边**（§3 刻意不给发消息 rpc、§5 零出边），所以装哪几个纯粹是 `brickkit.yaml` 的事。

**本组件内部无新分歧。**

## 9. 待决问题

| # | 问题 | 什么时候能有答案 | 答案 |
|---|---|---|---|
| 1 | 钉钉三件事的实际形态（接口名/权限/频控/`agent_id`），见 §8 第一行的 🔍 | 开工前查钉钉文档 + 申请一个测试企业 | 📋 ⚠️ **阶段三计划要求真调钉钉沙盒/测试群，不是 mock**，所以这条必须在 Task 9 之前落实到一个可用的测试企业 |
| 2 | 客户内网部署时出不了网怎么办 | 阶段三 Task 9 写部署文档时 | 📋 方向：**装配期就要问清楚**。若不能出网，正确做法是不装这个组件（`channel:*` 本来就可装可不装），而不是让它装上去一直失败 |
| 3 | 交互式卡片（用户在钉钉里直接点"同意"）要不要做？ | 阶段五按客户反馈定 | 📋 本阶段不做。⚠️ 做的话需要一个 webhook 入口 + 把钉钉的回调翻译成 `infra-workflow` 的审批动作——**那会让我第一次持有"业务动作"的语义**，要重新审 §6.9 的边界 |
| 4 | 族级契约（proto + 两条 subject）现在只按钉钉一家定，能不能容下企业微信/飞书/Slack？ | 阶段六建第二个成员时 | 📋 现在的对策：契约只按"发一条文本给一个自然标识"的最小交集定；`AGENTS.md` 记一条"加字段前先问另外四家能不能实现"（同 `infra-iam-casdoor` §9 第 4 条的做法） |
