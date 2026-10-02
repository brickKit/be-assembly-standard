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
