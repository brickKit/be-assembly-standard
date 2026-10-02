# 设计轮决策清单（汇总三份分析的拍板点）

来源：`identity-permissions.md` §8（I1–I10）、`data-layer.md` §7（D1–D10）、`events-consistency.md` §7（E1–E13）。"推荐"是控制者的建议；用户可以整体按推荐，也可以逐条改。标 ★ 的是业务口径或方向性的，最值得用户亲自看。

## 一、总方向

| # | 问题 | 推荐 | 备选 |
|---|---|---|---|
| E11 | 时机 | 全部在组外壳（T21–T24）之前做完 | 先组外壳，之后整体再升一轮 |
| D9 | 这一轮的版本号 | 有新行为或收窄契约的用 minor（2.1.0），只修 bug 的用 patch；写进约定 | 一律 patch |
| — | SDK 形态 | 按"可整体重写"设计，结论汇总进 `sdk-redesign.md`（下一步写），三门语言对齐 | — |

## 二、权限（identity-permissions.md）

| # | 问题 | 推荐 | 备选 |
|---|---|---|---|
| ★I1 | 数据权限的"授权"集中到 authz（角色 × 权限键挂档位 own/subtree/all，仓库、法人等维度值也挂在角色上，随 bundle 下发），新决策 0207 修订 0205 | 做 | 不做：各组件授权表规范化 + 补审计，"只能动自己的单子"仍表达不了 |
| I2 | 档位要不要 `dept`（只本部门、不含下级） | 先不要，需求出现再加 | 现在就加 |
| I3 | `/api/tenant/features` | 收窄成登录前必需的最少信息，其余并进要登录的 `/api/me/access` | 只改文档承认它公开 |
| I4 | 首个管理员 | 本地开发靠 `.env` 的 `BOOTSTRAP_ADMIN_SUB`，种子不再直接写库 | 保留种子直接写库 |
| I5 | mdm 的 gRPC 写接口收紧为 Unauthenticated | 收紧（实现前 grep 调用方） | 维持 |
| ★I6 | bff 的 8 个 `infra.bff-mobile.*` 键 | 只留一个 `infra.bff-mobile.use` 作渠道开关，resolver 直接用下游的键 | 保留 8 个，移动端单独授权 |
| I7 | inventory / finance 的本地授权表与管理接口 | 没有生产数据，2.1.0 直接删（只增规则的破例写明） | 过渡一版，3.0.0 再删 |
| I8 | 资源维度唯一归属（`warehouse` 只能 inventory 拥有） | `data-scopes.tsv` 加列，be-ops 校验 | 不加 |
| ★I9 | finance 信用敞口接口跨法人汇总 | 按 `legal_entity` 维限定 | 单法人场景下维持 |
| I10 | JWT 的 `org_id` 与 `org` 维撞名 | iam 加 `tenant_id`，`org_id` 标弃用 | 维持 |
| — | refresh token 能当 access token 用（安全） | 一期立即修：签发加 `typ`、三个 SDK 校验 | — |

## 二·续、权限架构 v2（authz-architecture.md，按"分享必做、完整优先、槽位族验证替换"重做）

整体：可见性 = (档位 × 维度规则) ∪ 共享 ∪ 关系派生；一个主体内纯并集，只沿委托链取交集（类似 permission boundary）。契约分两层：provider 契约 `infra.authz.v2`（槽位族每个成员都实现）+ 资源契约（SDK 在每个组件挂 `_authz/check`、`_authz/explain`、`_shares`）。列表过滤默认本地投影（`besdk_authz_acl` 表经 changefeed 同步）+ 图类型才远程 ListObjects。槽位族：`infra/authz`（原生，默认全能力）→ `infra/authz-static`（证明可替换与显式降级）→ `infra/authz-openfga` → cedar/OPA（有真实需求才建）；一致性测试 `be-acceptance/authzconf/`。上面 I1–I10 按新架构重答：只有 I2 改为"现在就加 `dept` 档"，其余维持。

| # | 问题 | 推荐 | 备选 |
|---|---|---|---|
| ★A1 | 被共享一张单据但没有对应 view 键的人能否打开 | 查看类可以顺带，动作类（确认、取消、关闭）永远要角色键；各组件在 `relations.grants` 显式声明 | 一律还要角色键（Salesforce 式） |
| ★A2 | 谁能共享 | 持有该类型的 share 键，且自己至少有要授出的那一级，不能转授高于自己的级别 | 只有负责人能共享 |
| A3 | 看不见的记录对命令也答 404（不再 403） | 改 | 维持 R62 |
| ★A4 | AI 代理的边界 | 默认只读 + 起草；不可逆动作的键标 `delegable: false`，由人在 workflow 确认；共享与授权管理永远不能下放 | — （要你定"永不下放"清单口径） |
| ★A5 | 生产环境"以他人身份查看" | 允许但只读，单独键 `infra.authz.impersonate`，日志带 `act` 并通知被查看的人 | 只在开发环境开 |
| ★A6 | openfga 成员什么时候建 | **06 内建**（控制者改判：用户明确要多实现互换验证，第二个真实实现越早越能逼出契约偏差）；顺序 static → openfga | 等 prj/project 或阶段 07 |
| — | 先决条件 | 删掉 iam → authz 依赖边（槽位族成员不能被依赖，brickKit 09-patterns）；族契约放新仓库 `contract-infra-authz`（**需新建 GitHub 仓库，先征得同意**） | — |

## 三、数据层（data-layer.md）

| # | 问题 | 推荐 | 备选 |
|---|---|---|---|
| D1 | 库身份：SDK 提供绑定身份的 `Store`（角色、schema 必填不互推），测试统一走 `besdktest`；模块不再直接拿 `rt.DB` | 同意 | — |
| ★D2 | 冷热生命周期："在线即挂载"——取消 `<schema>_archive` 与冷热路由；过保留期后技术表删除、业务表默认保留，配了对象存储的冻结后再删 | 同意 | 保留 archive schema 与冷热路由 |
| ★D3 | 主数据（客户、产品）列表默认 90 天窗口 | 去掉，当 bug 修 | 保留 |
| D4 | 冻结存储 | 第一版只定义接口 + NDJSON.gz 的 S3 实现；冻结数据只能经运维命令恢复；各表在线保留期由组件作者给默认值、项目可覆盖 | 用户逐表拍 |
| ★D5 | 数据库目标 | 官方承诺 PG ≥ 14 与 PG 兼容发行版；人大金仓、瀚高列为"待实测"，不承诺 | 现在就实测信创库 |
| D6 | 队列认领收进 SDK（`ClaimBatch`） | 现在就收（已有 iam webhook、workflow 超期两份手写） | 等第三个使用者 |
| ★D7 | finance 开会计年度 | 这一轮做"开会计年度"命令（管理接口 + 第四季度提醒） | 继续每年发一份迁移 |
| D8 | BatchGet 上限 | 默认 500，写进契约（proto 选项），新决策 0304；sales 的 BatchGetOrder 先消除 N+1 | — |
| D10 | 测试库分区止血 | 已做（控制者 2026-10-02 补到 11-23 + test-db-init 过渡步骤） | — |

## 四、事件与一致性（events-consistency.md）

| # | 问题 | 推荐 | 备选 |
|---|---|---|---|
| E1 | JetStream 流怎么建 | SDK 按 subject 第一段"没有就建、有就不碰"，放在迁移步骤里 | be-ops 登记表 + `make nats-init` |
| E2 | 流默认值 | 域流 7 天 / 1 GiB / 丢旧，DLQ 30 天 | — |
| ★E3 | 新装组件的 durable 从哪开始 | `DeliverAll`（补收流里剩下的，新装的 finance 会补记装之前 7 天的订单） | `DeliverNew` |
| E4 | 幂等键命名空间 | 主键含调用者（不同调用者用同一个键互不影响），并绑定命令名、目标、请求指纹 | 调用者不同报错 |
| E5 | 幂等键保留期 | 30 天，写进契约 | — |
| ★E6 | 只写不读的两张快照 | inventory 用它实现批次 / 序列号校验；opportunity 的删掉 | inventory 的也删 |
| ★E7 | finance 缺客户额度快照时 | 记"待补判"、补判时再发 `credit.rejected`（不误挂新客户的单） | 缺快照就当超限 |
| ★E8 | 崩溃留下的"确认到一半"的订单 | 对账时推进成 CONFIRMED | 退回 DRAFT 并释放预留 |
| E9 | 预留期限 | sales 用 900 秒，inventory 上限 3600 秒；无期限的旧预留只出排查清单 | — |
| E10 | 历史 subject 不带 `erp.`（`sales.*`、`finance.*`） | 不改（契约只增，一个第一段一个流即可吸收） | 双发迁移 |
| E12 | `event_cursor`、`command_idempotency` 不分区（靠保留期有界） | 同意，写成 02-backend.md 的明文例外 | — |
| E13 | DLQ 谁来看 | 先加 `make dlq-ls` / `make dlq-replay` | 等 `infra/dlq-monitor` 组件 |
| — | finance 不消费 `sales.order.cancelled.v1`（取消的单不冲销应收、额度只增不减） | 当 bug 修进这一轮 | — |

## 五、底层审查第二轮（foundations-communication.md、foundations-data-platform.md、data-lifecycle-v2.md）

### 必须在组外壳（T21–T24）之前定的（会改表结构或契约）

| # | 问题 | 推荐 |
|---|---|---|
| ★F1 | 部署形态 | 一个客户一套部署（私有化为主），客户内多公司走"法人"维度；不做多客户共用一套的 SaaS，但 token 与契约里预留 `tenant_id` / `tenant_key` |
| ★F2 | 集团多公司 | 在近期范围：订单、库存、商机等交易单据现在就加法人列 |
| ★F3 | 主键 | 12 个组件自有主键改 UUIDv7，单据号由 SDK 按法人+期间分配；要重建迁移基线、重置演示库/测试库，组件升 **3.0.0** |
| ★F4 | 多币种 / 海外 | 在范围：金额 `(19,4)`、单价 `(19,6)`，币种与金额成对；汇率归新组件 `mdm/currency` |
| ★F5 | 时区与会计年度 | 法人带业务时区（默认 Asia/Shanghai），业务日期用 DATE，SQL 禁用 `CURRENT_DATE`；开会计年度命令支持起始月 |
| ★F6 | IAM | 平台自有 `sub`（与 IdP 解耦），token 补 `iss`/`aud`/`jti`/`tenant_id`；第二实现 Keycloak，第三实现通用 OIDC+SCIM；族契约单独成仓库（**需新建 GitHub 仓库，先征得同意**） |
| ★F7 | 部署承诺 | 一期单机为主；K8s 多副本"可用不调优"，但设计按多副本正确来写（租约、按槽一次、MaxConnectionAge） |
| ★F8 | 财务凭证号 | 按期连续无缺口，维持每个法人串行过账，写明吞吐上限 |
| ★F9 | 文档重组 | 新建 `docs/{en,zh}/04-foundations/`（每个底层选择一篇，18 份），运维顺延到 `05-operations`；决策只留结论并链到 foundations；新开决策分组 `05-runtime/` |

### 方向性、有推荐即可

| # | 问题 | 推荐 |
|---|---|---|
| F10 | 事件总线第二个适配器 | 现在就建 PG 队列适配器 + 一致性套件；Kafka 等有客户再建 |
| F11 | 跨天多人长流程（采购到付款） | 现在不建引擎，第一个这样的流程出现时评估 DBOS，其次 Temporal |
| ★F12 | 对外开放 API（客户其他系统、第三方） | 待用户答：在路线图上则加 API key、配额、版本承诺 |
| F13 | 用户操作最长等待 | 普通 10 s，确认订单这类编排 15 s，导出异步 |
| F14 | 跨组件"几秒后才看到" | 接受，前端显示"同步中" |
| F15 | `resources.tsv` 的 kafka / rabbitmq | 删 rabbitmq；kafka 保留并标"适配器待建" |
| F16 | 保留期口径 | 组件作者按法规给默认值，部署时可覆盖但不低于法定下限；订单按涉税资料 10 年 |
| F17 | 冷数据体验 | P1 给"已归档：一键导出 / 申请解冻"，P2 再做列表里直接查 |
| F18 | 非财务数据到期 | 走审批销毁（留清册），财务数据按会计档案办法鉴定 |
| F19 | 自然人客户删除 | 保留期内"限制处理"，到期匿名化 |
| F20 | 电子会计档案归档包（DA/T 94） | 排进 finance 路线图 |
| F21 | `infra/data-governance` | P2 做 |
| F22 | 拼音 / 首字母搜索 | 一期必备，依赖 pg_trgm 等扩展并按能力探测降级 |
| F23 | 国密 SM2/SM4、等保 | 先列为能力项，有真实需求再做 |
| F24 | 附件病毒扫描 | 生产默认开，开发默认关 |
| F25 | 主数据多语言 | 要，不急 |
| F26 | 审计日志 | 保留 3 年可配，租户管理员可查自己的 |
| F27 | 迁移角色与运行期角色分开 | 要 |
| F28 | 开发机密钥 | 从明文 `.env` 换成 SOPS 加密文件 |

### 已确认的真 bug（随组件统一升级修，优先级最高）

- finance 过账日期取 `time.Now().UTC()` 且 DATE 与 timestamptz 比较：月末凭证记进下月、北京时间 0–8 点记到前一天、取的是消费事件时刻不是单据日期；sales 价格生效按 UTC 的 `CURRENT_DATE`。
- 全项目没有任何超时（数据库语句/锁/空闲、HTTP、gRPC keepalive、跨组件调用截止时间）；连接池无上限且外壳成员共用一个池；gRPC 每次调用现拨连接；NATS 断线约 2 分钟后永久失联。
- sales 的 `credit.rejected` 处理锁着订单行同步调 workflow（最长 5 秒）；库存多品预留按请求顺序加锁会死锁；全项目对 40001/40P01 不重试。
- `event_cursor` 按 (subject, aggregate) 建键会在"cancelled 先到 created 后到"时给已取消订单记应收——改为按聚合流建键。
- 外壳里成员后台循环失败后永久停止（单跑时会退出重启），两种形态行为不一致；trace 在每一跳都断。
