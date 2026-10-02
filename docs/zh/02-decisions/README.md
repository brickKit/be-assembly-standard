[English](../../en/02-decisions/README.md) · [中文](README.md)

# 决策

约束本项目后续改动的决策。每个文件写明结论、简短理由、会被它挡下的需求，以及在什么情况下值得重新讨论；最后一行链到 foundations 里给出完整分析的那一节（[04-foundations](../04-foundations/README.md)）。需求与其中某条冲突时，既不悄悄拒绝，也不悄悄照做：引用那条决策，交给人来决定。

## 编号

- 每个文件夹有自己的编号段，所以同一文件夹里的编号始终连续：`01-architecture/` 0101–0199，`02-permissions/` 0201–0299，`03-contracts-and-data/` 0301–0399，`04-frontend/` 0401–0499，`05-runtime/` 0501–0599。新增的文件夹 `NN-…` 用 `NN01`–`NN99`。
- 新决策取所在文件夹编号段里下一个空闲编号。
- 编号一经分配不复用，因为其他文档按编号引用。
- 被推翻的决策保留原文件，在顶部加一行 `Superseded by NNNN`，新决策反向链接到它。
- 阶段 06 结束之前，阶段 06 里写下或改过的决策直接原地改写、保留编号：下游还没有任何东西依赖它；重写时可以把文件改名以对应新标题（0105），并在同一次改动里更新所有指向它的链接。阶段 06 结束之后适用上一条。

## 文件夹

| 文件夹 | 放什么 |
|---|---|
| `01-architecture/` | 系统怎么切分、怎么组装：组件边界、schema、锁定的技术栈、槽位族、语言与组件协议、哪些不是组件、共享地址、外壳 |
| `02-permissions/` | 谁能做什么、能看到哪些行：不用 Redis、本地判定、只承载身份的 token、纯并集、数据范围及其分配、不用行级安全、系统面、authz 槽位族、委托、字段权限、看不见的记录答 404 |
| `03-contracts-and-data/` | 什么跨越边界、什么写进数据库：金额与分页、契约只做加法、迁移里不放测试账号、批量上限、3.0.0 重建、主键、业务日期、租户 |
| `04-frontend/` | 前端技术栈、ui-kit、导航、用户偏好、设计令牌 |
| `05-runtime/` | 运行中的组件怎么表现：事务、隔离与重试、截止时间、错误、事件信封与送达、幂等、后台工作、边缘做什么 |

新决策放进它所回答的问题对应的文件夹；都不合适时，在 `docs/en/02-decisions/` 和 `docs/zh/02-decisions/` 里同时新增一个带编号的文件夹。

## 索引

| 编号 | 决策 | 挡下什么 | 文件夹 |
|---|---|---|---|
| [0101](01-architecture/0101-no-imports-between-components.md) | 组件之间禁止 import，只共享官方 SDK、生成契约包和族契约包 | 因为同在一个外壳就直接调用对方的函数；公共 model 包 | `01-architecture/` |
| [0102](01-architecture/0102-one-schema-per-component.md) | 一个 PostgreSQL 方言族数据库，每个组件一个 schema 和角色，库身份只来自 `PG_USER` / `PG_SCHEMA` | 每个组件一个数据库；跨 schema JOIN；从 schema 推导角色；碰 `besdk_*` 表 | `01-architecture/` |
| [0103](01-architecture/0103-locked-stack-per-language.md) | 每种语言内部一套锁定的技术栈（Go、Python、TypeScript）；新语言在第二个组件之前锁栈 | Echo、GORM、Express、Prisma、alembic；组件自选框架 | `01-architecture/` |
| [0104](01-architecture/0104-variants-become-slot-families.md) | 槽位族需要多种合理实现，**并且**该位置没有依赖边；否则是一种默认实现加客户 Fork | 成本核算 / 拣货槽位族（"让客户选先进先出还是移动加权平均成本" → 默认实现 + Fork）；按客户堆 `if costingMethod == ...`；"把算法做成可配置" | `01-architecture/` |
| [0105](01-architecture/0105-any-language-one-protocol.md) | 任何语言，一份协议：一致性报告全绿即可进项目；进外壳需要该语言的 SDK 和启动器 | 一个进程里混用语言；没有一致性报告的组件；对 JVM 内存开销只字不提 | `01-architecture/` |
| [0106](01-architecture/0106-infrastructure-is-not-a-component.md) | 事件总线、对象存储、网关、可观测性、IdP 服务器不是组件；总线经按 URL scheme 选用的 SDK 适配器更换 | `infra/nats` 或网关组件；没有适配器就改一个设置把 NATS 换成 Kafka | `01-architecture/` |
| [0107](01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md) | authz 与 IAM 经 `AUTHZ_URL`、`IAM_JWKS_URL`、`IAM_ISSUER`、`TENANT_ID` 访问；任何组件都不依赖族成员 | 对 `infra/authz` 或 IAM 成员建依赖边；`AUTHZ_BUNDLE_URL` | `01-architecture/` |
| [0108](01-architecture/0108-one-repository-per-shell.md) | 一个外壳、一个仓库（以子模块挂在 `shell/<scope>/<name>/`，在那里发布，tag 是裸 `<版本>`）、一个镜像、一份成员清单、一门语言和一个 SDK 版本 | 把外壳代码提交在本仓库；在本仓库发布外壳；外壳里写逻辑；只升成员不升外壳 | `01-architecture/` |
| [0109](01-architecture/0109-language-neutral-component-protocol.md) | 规则写在语言中立的组件协议（`be-protocol`）里，由黑盒套件检查；SDK 是它的参考实现 | 只有 SDK 知道的规则；没有全绿报告就发版；按语言变体的协议 | `01-architecture/` |
| [0201](02-permissions/0201-no-redis.md) | 不用 Redis，不设缓存服务器；缓存只在进程内、经 SDK | 加缓存服务器、Redis 存会话、分布式锁、Redis 限流；缓存判定结果 | `02-permissions/` |
| [0202](02-permissions/0202-local-permission-bundle.md) | 权限在本地判定：对照 bundle 和投影 | 组件里建权限表；每个请求都问 authz；把 authz 放进 `/healthz` | `02-permissions/` |
| [0203](02-permissions/0203-jwt-carries-identity-only.md) | token 只承载身份，`sub` 归平台所有 | 把权限或 scope 塞进 JWT claims；用 IdP 的 subject 当用户 id；没有 `typ`、`iss`、`aud` 的 token | `02-permissions/` |
| [0204](02-permissions/0204-permissions-are-a-pure-union.md) | 权限是纯并集，没有 Deny；只有委托链取交集 | "除了某人以外所有人"；拒绝规则；规则优先级 | `02-permissions/` |
| [0205](02-permissions/0205-data-scopes-ship-with-the-version.md) | 数据范围的规则随版本发布；`data_scopes` 必填 | 运行时编辑行规则；查完再过滤；省略 `data_scopes` | `02-permissions/` |
| [0206](02-permissions/0206-no-row-level-security.md) | 不用行级安全；共享引擎只有一个，在 authz，由 SDK 投影 | `CREATE POLICY`；组件里自建共享表；组织树副本 | `02-permissions/` |
| [0207](02-permissions/0207-scope-assignments-live-in-authz.md) | 档位、维度取值、共享和委托是 authz 里的运行时分配 | 组件里的访问表；用 `.admin` 键扩大范围 | `02-permissions/` |
| [0208](02-permissions/0208-grpc-is-the-system-plane.md) | gRPC 是组件之间的系统面，人用 REST | 经 gRPC 传按用户范围过滤的数据；在用户请求路径上用系统身份 | `02-permissions/` |
| [0209](02-permissions/0209-authz-is-a-slot-family.md) | 授权是一个槽位族：契约 `infra.authz.v2`、能力协商、一致性套件 | 依赖某个成员；靠假设的能力；悄悄降级 | `02-permissions/` |
| [0210](02-permissions/0210-delegation-and-impersonation.md) | 委托与只读扮演不超过被代表的人；代理人只留位子 | 代理人权限超过委托人；能写入的扮演；现在就开发代理人 | `02-permissions/` |
| [0211](02-permissions/0211-field-level-permissions.md) | 字段级权限是 `type: field` 的键，在源头掩码 | 在前端或 BFF 掩码；按掩码字段排序 | `02-permissions/` |
| [0212](02-permissions/0212-invisible-records-answer-404.md) | 调用者看不见的记录答 404，读和命令都一样 | 对范围外的记录答 `403`；能区分"隐藏"和"不存在"的错误 | `02-permissions/` |
| [0301](03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md) | 金额是与币种成对的十进制字符串；列表按游标分页 | `double` 金额；不带币种的金额；`List` 里的 `offset` / 页码 | `03-contracts-and-data/` |
| [0302](03-contracts-and-data/0302-contracts-are-additive-only.md) | 契约只做加法；破坏性变更是与旧版并存的新大版本（REST：`/v2/` 前缀加 `Deprecation` / `Sunset`） | 改名、改类型、删除字段、RPC、subject 或 reason | `03-contracts-and-data/` |
| [0303](03-contracts-and-data/0303-no-test-accounts-in-migrations.md) | 测试账号不写进迁移；首个管理员来自 `BOOTSTRAP_ADMIN_LOGIN`，首次登录时绑定到平台 `sub` | 默认管理员账号；迁移里放演示数据；种子直接写首个管理员 | `03-contracts-and-data/` |
| [0304](03-contracts-and-data/0304-batch-get-takes-at-most-500-ids.md) | `BatchGet` 最多 500 个 ID，写在契约里 | 无上限的批量；跨网络的 N+1 | `03-contracts-and-data/` |
| [0305](03-contracts-and-data/0305-one-shot-baseline-rebuild-for-3-0-0.md) | 3.0.0 重建可以替换已发布的迁移，仅此一次，不做兼容层 | 再次援引这次破例；"只保留一个版本"的垫片 | `03-contracts-and-data/` |
| [0306](03-contracts-and-data/0306-uuidv7-own-keys.md) | 自有主键用 UUIDv7；单据号由 SDK 分配，凭证号按期无缺号 | `BIGSERIAL` 主键；由 id 拼出的单据号 | `03-contracts-and-data/` |
| [0307](03-contracts-and-data/0307-business-dates-and-legal-entity-calendar.md) | 业务日期是法人时区下的 `DATE`；会计年度起始月按法人设定 | SQL 里的 `CURRENT_DATE`；取自处理时刻的日期 | `03-contracts-and-data/` |
| [0308](03-contracts-and-data/0308-tenant-is-the-deployment.md) | 租户就是部署；公司是部署内的法人 | `tenant_id` 列；多客户 SaaS；缺少法人的单据 | `03-contracts-and-data/` |
| [0401](04-frontend/0401-frontend-stack.md) | Vue 3；PC 用 AntDV + vxe-table；移动端用 wot-design-uni；只共享设计令牌 | React；Element Plus / Naive UI；两端共用一套组件库 | `04-frontend/` |
| [0402](04-frontend/0402-third-party-ui-only-in-ui-kit.md) | 第三方 UI 组件只能出现在 ui-kit 中 | 页面里直接 import AntDV / vxe；为了好看混搭组件库 | `04-frontend/` |
| [0403](04-frontend/0403-two-tier-navigation.md) | PC 端采用控制台式两层导航，带应用内标签页 | 多级树形菜单；把 admin 模板当依赖；从空白 `<div>` 搭页面 | `04-frontend/` |
| [0404](04-frontend/0404-four-user-preferences.md) | 用户偏好只有四项 | 布局模式切换；每个用户自选主题色 | `04-frontend/` |
| [0405](04-frontend/0405-design-tokens-are-css-variables.md) | 设计令牌是运行时 CSS 变量 | 令牌写成 TS 常量；硬编码颜色和间距 | `04-frontend/` |
| [0501](05-runtime/0501-no-network-inside-a-transaction.md) | 事务里不发网络调用；出口只有一行 outbox 和一行任务队列 | `BEGIN` 与 `COMMIT` 之间的调用；提交后尽力而为；嵌套事务 | `05-runtime/` |
| [0502](05-runtime/0502-isolation-and-retry.md) | 默认 READ COMMITTED，配明确的阶梯；只重试 `40001` / `40P01` | 调高全局级别；按请求顺序加锁；会话级设置或锁 | `05-runtime/` |
| [0503](05-runtime/0503-deadlines-and-retry-budgets.md) | 每个请求都有只减不增的截止时间；重试由契约决定、受预算约束 | 没有截止时间的调用；重试非幂等方法；嵌套重试循环；熔断器 | `05-runtime/` |
| [0504](05-runtime/0504-error-model-and-reason-catalogue.md) | 一种错误对象（带 AIP-193 成员的 problem details），由目录里的 reason 标识 | `error` 字符串字段；泄露内部错误；目录外的 reason | `05-runtime/` |
| [0505](05-runtime/0505-cloudevents-envelope-and-aggregate-cursor.md) | 信封是二进制模式的 CloudEvents；按聚合流各记一个游标 | `X-` 头；按 subject 建键的游标；依赖 broker 的顺序 | `05-runtime/` |
| [0506](05-runtime/0506-at-least-once-delivery-and-streams.md) | 经 outbox 至少送达一次；每个 subject 第一段一个流 | 绕过 outbox 发布；假设恰好一次；按组件建流 | `05-runtime/` |
| [0507](05-runtime/0507-idempotency-keys-namespaced-by-caller.md) | 幂等键按调用方划分命名空间，绑定到命令、目标和指纹 | 共用的键空间；换了请求体的重放；授权之前就查键 | `05-runtime/` |
| [0508](05-runtime/0508-background-work-only-through-jobs.md) | 后台工作只经 SDK 的 Jobs | 模块代码里的 ticker 和循环；外部调度器 | `05-runtime/` |
| [0509](05-runtime/0509-edge-only-routes.md) | 边缘只做路由，认证和授权留在服务里 | 只在网关验 token（ForwardAuth、JWT 插件）；在边缘做授权、数据范围或按业务内容路由；路由 gRPC 或 `/healthz`、`/metrics`、`/_be/info` | `05-runtime/` |
