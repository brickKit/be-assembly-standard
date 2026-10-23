# be-assembly-standard

给 AI 的项目导读。**与维护者交流一律用中文**，不论正在读的文件或工具输出是什么语言；代码（标识符、注释、日志、错误信息）与提交信息用英文（D74）。

> **怎样找东西**（先看这三行）
> - **一个名字**（业务词“资格”“汇率”“业务日期”，组件 ID、事件、权限键）：业务词查[术语表](docs/zh/00-overview/07-glossary.md)，组件查[组件索引](docs/zh/00-overview/09-component-index.md)（边界卡、仓库文档、实现版本、谁依赖它、事件）；已重建的组件接着读它的 `AGENTS.md`，从代码地图下到文件。
> - **一件事怎样做**：下面的“查找路由”；任何改动按[改动的循环](docs/zh/01-conventions/10-development-workflow.md#改动的循环)做，这一类改动（加字段、加接口、改事件、调用别的组件、加表、新组件）每步要注意的在[改动配方](docs/zh/01-conventions/11-change-recipes.md)；整条业务怎样走看[业务流程](docs/zh/08-flows/README.md)。
> - **一个现象**（报错、症状）：下面的“易错点”、`brickkit-troubleshoot` 技能、[运维手册](docs/zh/05-operations/README.md)。
>
> 全仓搜索用 `rg`（读根目录的 `.ignore`，跳过生成的契约代码与过程记录）。`COMPONENTS.md`（BrickKit 维护的组件表）是旧的 2.x 装配，新设计的组件以组件索引为准。

## 项目概述

- **这是什么**：BrickEnterprise，ERP 为主、加入 CRM 的组件货架，加上用 BrickKit 把它们装配起来的标准装配项目；也是 BrickKit 的真机验证场：平台问题写出复现报给 BrickKit，绝不在组件里绕过去。
- **现在处于哪个阶段**：终局设计已冻结（2026-10-15），正式文档在 `docs/zh/`（[索引](docs/zh/README.md)）。按新设计从零重建（D59），旧的 2.x 代码只作参考；进度与计划在 `dev/rebuild/`（开发区）。
- **组件 ID** 是 `<领域>/<名字>`，仓库 `<领域>-<名字>`；领域与边界见[领域与边界](docs/zh/00-overview/02-domains-and-boundaries.md)。
- **东西放在哪里**：`components/`、`shell/`（组件与外壳，各是 Git 子模块）；`tools/`（`be-sdk-go`、`be-sdk-python` 是组件运行时，`be-protocol` 是线协议与向量，`be-ops` 装配时生成，`be-acceptance` 参考模型与文档检查）；`registry/`（端口、schema、权限键）；`config/`、`infra/`（基础资源）；`dev/`（进行中的工作）；`archive/`（归档，现行内容不引用）。
- **两条不变的原则**（[产品](docs/zh/00-overview/01-product.md#两条不变的原则)）：每个组件都是完整的 BrickKit 组件、能单独运行，对其他组件的每次调用都走真实的网络调用（同在一个外壳里也一样）；合并只发生在部署时，外壳把几个进程合成一个，此外什么也不做。

## 项目约定

每条一行，链接是完整规则；请求与某条约定冲突时，引用它向维护者提出。

- **决定优先**：[决定记录](docs/zh/02-decisions/README.md)优先于规范，规范优先于单个组件的约定；BrickKit 技能写的是所有项目通用的做法，与本项目的规范不一致时以本项目为准（例如组件以组件索引为准，不以 `COMPONENTS.md`；版本按本项目的版本规则）。
- **开发流程**：每次改动（新组件、新功能、修改、修缺陷）都走同一个循环：意图（文档）→ 考设计 → 契约 → 先写红的测试 → 实现 → 核对 → 发布，这次没有内容的步跳过；各类改动在每步要注意的在改动配方（[改动的循环](docs/zh/01-conventions/10-development-workflow.md#改动的循环)）。
- **组件代码**：一个模块入口，一切经 SDK 的运行时，合并安全（[组件实现约定](docs/zh/01-conventions/06-component-implementation.md)）；每种语言一套锁定的技术栈（[组件协议与语言](docs/zh/04-foundations/07-component-protocol-and-languages.md)）。
- **测试**：L1–L4、FE-1–FE-4；绝不为了让测试通过而改测试（[测试与验证](docs/zh/01-conventions/02-testing-and-validation.md#实现测试的分层与节奏)）。
- **数据**：种子数据给人、测试数据给测试，两个物理库；依赖方缺能力时去源头补；凭据绝不进入部署（[种子与测试数据](docs/zh/01-conventions/07-seed-and-test-data.md)）。
- **配置与注册表**：配置键大写下划线、只经 SDK 读取；密钥只写引用；端口、schema 从注册表抄，权限键、资源与维度在组件定义里登记，身份只追加（[协议 19](docs/zh/06-protocols/19-config-secrets-registries-release.md)、[注册表的现状](registry/README.zh.md)）。
- **权限**：每个操作在组件定义的资源定义里登记；看不见答 404（[授权选型](docs/zh/00-overview/guides/authorization.md)、[安全协议](docs/zh/06-protocols/security/README.md)）。
- **跨组件**：经契约调用；业务写入与发件表同事务；事务内不发网络调用（[事务与消息](docs/zh/04-foundations/03-transactions-and-messaging.md)）。
- **版本**：每次改动都升版本，动手前先升；开发阶段（现在）每次只升最后一位，进入正式时升 `Y`；用过的版本号绝不再用（[版本](docs/zh/01-conventions/10-development-workflow.md#版本)）。
- **提交与发布**：英文提交信息先写进文件再 `git commit -F`，带注释的标签，按依赖顺序发布；子模块指针只经 `git submodule` 改，与需要它的 `brickkit upgrade` 一起提交（[提交](docs/zh/01-conventions/10-development-workflow.md#提交)）。
- **参考实现**：先自己设计，卡住才看参考，绝不照抄（[参考实现](docs/zh/01-conventions/08-reference-implementations.md)）。
- **AI 友好与性能**：模式只用在帮助读懂的地方；越底层越要想性能，业务逻辑以看得懂优先；函数、文件与会话有上限（[AI 编码习惯](docs/zh/01-conventions/09-ai-coding.md)）。
- **版本与选型**：新版本优点明显才换；选型先适配、再性能；优化不牺牲需求；同一个库在整个系统里只用一个版本，升级时全部组件一起换（[底层选择的原则](docs/zh/04-foundations/README.md#原则)）。
- **文档**：开发完成前只写中文（D67）；同一规则只写在一处；正式文档不链接 `dev/` 与 `archive/`；图表按情况选，意图类先改、事实类生成（[文档规则](docs/zh/01-conventions/03-documentation.md)、[图与表](docs/zh/01-conventions/04-diagrams-and-tables.md)）。
- **容器默认关着**：`make up` 的基础资源可以常开；组件容器验证完就 `brickkit down`。

## 查找路由

| 你要做的事（你会用的词） | 先读 |
| --- | --- |
| 新需求、“放在哪里”、“这样好不好”、跨组件的改动 | `brickkit-plan-change` 技能（[SKILL.md](.claude/skills/brickkit-plan-change/SKILL.md)）、[组件索引](docs/zh/00-overview/09-component-index.md)、[边界卡](docs/zh/07-components/README.md)、[决定记录](docs/zh/02-decisions/README.md) |
| 某个组件做什么；改它；跑它的测试；部署它前要准备什么 | [组件索引](docs/zh/00-overview/09-component-index.md) → 已重建的读它的 `AGENTS.md`、`BRICKKIT.md`、`docs/design.md`；没重建的读边界卡 |
| 整个业务怎样走；这一步在哪个组件；改这一步牵动谁 | [业务流程](docs/zh/08-flows/README.md) |
| 改了会影响谁：谁依赖这个组件、谁订阅这个事件 | [组件索引](docs/zh/00-overview/09-component-index.md)（被谁必需依赖、[事件](docs/zh/00-overview/09-component-index.md#事件)）；`brickkit deps <ID>` |
| 加字段、加接口、改事件、调用别的组件、加表 | [改动配方](docs/zh/01-conventions/11-change-recipes.md) |
| 开始做一个组件；先做什么；一次会话做多少 | [开发流程](docs/zh/01-conventions/10-development-workflow.md)、[每次会话读多少](docs/zh/01-conventions/05-ai-navigation.md#每次会话读多少) |
| 写新组件；仓库布局；改 `component.yaml` | [标准布局](docs/zh/01-conventions/05-ai-navigation.md#组件仓库的标准布局与代码地图)、`brickkit-component` 技能（[SKILL.md](.claude/skills/brickkit-component/SKILL.md)） |
| 端口、schema、数据库角色、权限键；配置键；读配置；连数据库或消息系统 | [协议 19](docs/zh/06-protocols/19-config-secrets-registries-release.md)、[协议 14 的数据库](docs/zh/06-protocols/14-data-foundations.md#数据库)、[运行时](docs/zh/01-conventions/06-component-implementation.md#运行时是唯一入口) |
| 框架与库 | [锁定的技术栈](docs/zh/04-foundations/07-component-protocol-and-languages.md#锁定的技术栈) |
| 谁能调用；权限键；资源定义 | [安全 06](docs/zh/06-protocols/security/06-security-contracts-and-capabilities.md)、[安全 09a](docs/zh/06-protocols/security/09a-encoding-and-records.md) |
| 只让一部分人看到一部分行（数据范围）；行级安全、RLS | [安全 07](docs/zh/06-protocols/security/07-finite-expressions-containment-and-queries.md)、[授权选型](docs/zh/00-overview/guides/authorization.md)；不用行级安全：[决定 0206](docs/zh/02-decisions/10-earlier-decisions.md#0206-不用行级安全共享引擎只在授权组件) |
| 调用别的组件；显示别的组件的数据 | [调用其他组件](docs/zh/01-conventions/06-component-implementation.md#调用其他组件)、[调用与错误](docs/zh/04-foundations/08-calls-and-errors.md) |
| 加表、迁移、分区；身份、单号、业务日期、金额；列表、分页、搜索 | [协议 14](docs/zh/06-protocols/14-data-foundations.md)；全局搜索与报表：[协议 13](docs/zh/06-protocols/13-search-reports-and-datasets.md) |
| 发布或消费事件；跨组件写入；补偿；预占 | [事务与消息](docs/zh/04-foundations/03-transactions-and-messaging.md)、[协议 02](docs/zh/06-protocols/02-projections.md)、[协议 04](docs/zh/06-protocols/04-order-reservation.md) |
| 后台任务、定时任务、对账 | [协议 01](docs/zh/06-protocols/01-background-work.md) |
| 改契约：改字段名、删接口或事件 | [版本与产物](docs/zh/06-protocols/19-config-secrets-registries-release.md#版本与产物)、[决定 0302](docs/zh/02-decisions/10-earlier-decisions.md#0302-契约只做加法从新版本发布之后约束) |
| SDK 怎样做某件事（幂等键、事务入口、发件表、迁移）；线协议条款 `P<章>.<序号>` | [`be-sdk-go` 的 AGENTS.md](tools/be-sdk-go/AGENTS.md)；条款在 [`tools/be-protocol/spec/`](tools/be-protocol/spec/00-reading.md)；项目层见[协议 18](docs/zh/06-protocols/18-sdk-and-conformance.md) |
| 缓存、Redis、让权限检查更快 | [底层选择](docs/zh/04-foundations/README.md#推荐组合与改选条件)、[安全 03](docs/zh/06-protocols/security/03-authorization-acceptance-and-revocation.md) |
| 外壳；几个组件放进一个进程；外壳报成员未注册 | [外壳义务](docs/zh/06-protocols/17-runtime-and-resources.md#外壳义务)、[部署与运行](docs/zh/04-foundations/01-deployment-and-runtime.md) |
| 写哪种测试；测试红了卡住 | [测试与验证](docs/zh/01-conventions/02-testing-and-validation.md#实现测试的分层与节奏)、[卡住时](docs/zh/01-conventions/02-testing-and-validation.md#卡住时) |
| 演示数据；测试账号；依赖方没有我要的数据 | [种子与测试数据](docs/zh/01-conventions/07-seed-and-test-data.md)、[种子数据清单](docs/zh/03-seed-data.md) |
| 前端、菜单、只有部分用户看得到的按钮 | [前端技术栈](docs/zh/04-foundations/04-frontend-stack.md)、[协议 20](docs/zh/06-protocols/20-frontend.md) |
| 业务逻辑该怎样；看哪个开源 ERP | [参考实现](docs/zh/01-conventions/08-reference-implementations.md)、[选择方式](docs/zh/00-overview/04-selection.md) |
| 设计模式；文件太长；要不要为性能优化 | [AI 编码习惯](docs/zh/01-conventions/09-ai-coding.md) |
| 写或拆文档；画图与表 | [文档规则](docs/zh/01-conventions/03-documentation.md)、[图与表](docs/zh/01-conventions/04-diagrams-and-tables.md) |
| 升版本；发布；打标签 | [版本与发布](docs/zh/01-conventions/10-development-workflow.md#版本)、`brickkit-component` 技能 |
| 安装或部署；谁建数据库；密钥；Kubernetes；只跑一个组件 | `brickkit-deploy` 技能（[SKILL.md](.claude/skills/brickkit-deploy/SKILL.md)）、[部署与运行](docs/zh/04-foundations/01-deployment-and-runtime.md)、[真机运行](docs/zh/01-conventions/10-development-workflow.md#真机运行)、组件 `BRICKKIT.md` 的“部署前准备” |
| 上线、备份与恢复、升级、告警 | [运维手册](docs/zh/05-operations/README.md) |
| 加、删、升级组件；组件起不来；`brickkit` 报错 | `brickkit-assemble`、`brickkit-troubleshoot` 技能；`brickkit <命令> --help` |
| “为什么不用 React／Java／行级安全／配置中心……”；可能与已有决定冲突 | [决定记录](docs/zh/02-decisions/README.md)（先读再提议） |
| 为什么选这个数据库、消息系统、金额格式；不改代码换底层 | [底层选择](docs/zh/04-foundations/README.md)、[可切换的底层](docs/zh/04-foundations/README.md#部署时可切换的底层实现) |

这里没有时：先看[正式文档的索引](docs/zh/README.md)与[组件索引](docs/zh/00-overview/09-component-index.md)。

## 易错点

对每个组件都成立、看起来对、测试也能过、很久之后才出症状的错误；完整规则在链接里。

| 绝不 | 症状 | 规则 |
| --- | --- | --- |
| 不带 `LOCAL` 的 `SET`、`set_config(…, false)`（含函数与 `DO` 块）；按角色设超时 | 下一个借到池中连接的成员继承设置，不报错；角色级超时在 `SET ROLE` 后不生效（SDK 拒绝能发现的） | [协议 14 的数据库](docs/zh/06-protocols/14-data-foundations.md#数据库)；线协议 P5.30、P5.31（`tools/be-protocol/spec/05-database.md`） |
| 模块代码读进程环境 | 合进外壳后成员互相覆盖 schema 名与配置，静默读写别人的 schema | [合并安全](docs/zh/01-conventions/06-component-implementation.md#合并安全) |
| 在模块里初始化进程级的东西（全局追踪、日志全局配置、信号处理、默认指标注册表） | 合并后最后一个赢；默认注册表在第二个成员注册时崩溃 | [合并安全](docs/zh/01-conventions/06-component-implementation.md#合并安全) |
| 模块里退出进程，或绕过 SDK 自建 HTTP 引擎、连接池、监听 | 一个模块拖垮整个外壳；静默丢掉身份、追踪、授权 | [合并安全](docs/zh/01-conventions/06-component-implementation.md#合并安全) |
| 导入另一个组件的代码、共享模型包、复制别人的生成代码 | 要单独部署时拆不动；复制的生成代码进同一个外壳时启动即崩溃 | [决定 0101](docs/zh/02-decisions/10-earlier-decisions.md#0101-组件之间禁止导入代码) |
| 把缺席的可选依赖当作空值 | 变量根本不存在，启动时崩溃 | [运行时](docs/zh/01-conventions/06-component-implementation.md#运行时是唯一入口) |
| 配置键以 `_ENDPOINT` 结尾，或用平台保留名 | 平台的值优先，组件永远拿不到你的值 | [协议 19 的配置](docs/zh/06-protocols/19-config-secrets-registries-release.md#配置) |
| 在健康检查里查数据库、消息系统或其他组件 | 下游一次抖动让上游全部被判不健康并重启 | [协议 17](docs/zh/06-protocols/17-runtime-and-resources.md) |
| 基础镜像用 `scratch` 或 distroless | 平台永远报不健康（健康检查经 `/bin/sh` 与 `wget`） | [健康检查与镜像](docs/zh/01-conventions/06-component-implementation.md#健康检查与镜像) |
| 注册没有操作定义的路由、resolver 或任务 | 这个接口没有授权检查，毫无症状 | [安全 06](docs/zh/06-protocols/security/06-security-contracts-and-capabilities.md) |
| 系统面的结果原样放进用户响应；用服务身份替用户取受范围约束的数据 | 响应静默多出不该看到的行或字段 | [调用其他组件](docs/zh/01-conventions/06-component-implementation.md#调用其他组件)、[安全 02](docs/zh/06-protocols/security/02-trusted-identity-and-attributes.md) |
| 资源定义缺维度；把空部门路径当作树的根 | 无部门的用户看到全部部门的行 | [安全 09a](docs/zh/06-protocols/security/09a-encoding-and-records.md)、[安全 07](docs/zh/06-protocols/security/07-finite-expressions-containment-and-queries.md) |
| 改名或复用已发布的权限键、端口、schema | 持有旧键的角色静默失去它；依赖方断开 | [协议 19 的注册表](docs/zh/06-protocols/19-config-secrets-registries-release.md#注册表) |
| 前端只检查 `features` 不检查 `permissions` | 菜单看得见，点进去整页被拒 | [协议 20](docs/zh/06-protocols/20-frontend.md) |
| 把本项目的键写进 `component.yaml` | `brickkit lint`、`add` 拒绝整个清单；权限、资源与维度写在组件定义里 | [标准布局](docs/zh/01-conventions/05-ai-navigation.md#组件仓库的标准布局与代码地图) |
| 先普通 `SELECT` 再写入来认领队列行或幂等键 | 两个副本各发一次；两个并发请求都执行 | [协议 01](docs/zh/06-protocols/01-background-work.md)、[本地事务](docs/zh/04-foundations/03-transactions-and-messaging.md#本地事务) |
| 金额用浮点；列表用偏移量分页 | 跨语言丢精度；深分页变慢并跳行 | [协议 14](docs/zh/06-protocols/14-data-foundations.md) |
| 为了让测试通过而改测试 | 全绿而什么都没守住 | [一轮红绿与铁律](docs/zh/01-conventions/02-testing-and-validation.md#一轮红绿与铁律) |
| 改 Fork 出来的组件的 ID | 依赖方的地址变量全部消失 | [发布](docs/zh/01-conventions/10-development-workflow.md#发布) |
| 外壳的成员清单、编进的成员与依赖锁不一致，或偏离客户基线 | 外壳启动即退出；或镜像跑的版本与项目以为的不同 | [外壳的风险](docs/zh/04-foundations/01-deployment-and-runtime.md#外壳的风险) |
| 以为 `deploy.local.yaml` 会与 `deploy.yaml` 合并 | 改 `deploy.yaml` 不起作用 | [真机运行](docs/zh/01-conventions/10-development-workflow.md#真机运行) |
| 在共享变量里手写授权或身份的版本化服务名 | 下次发布后受保护路由全部 503 或 403 | [协议 19 的配置](docs/zh/06-protocols/19-config-secrets-registries-release.md#配置)（写 `$endpoint:` 引用） |
| Go 组件只打裸标签；主版本 2 起模块路径不带主版本 | 外壳构建报 `unknown revision` 或路径不符 | [版本与升级](docs/zh/01-conventions/01-engineering.md#版本与升级) |
| 删掉标签后用同一个版本号发新代码 | 取到同号的旧代码或 `SECURITY ERROR`；BrickKit 缓存给出旧清单 | [版本与升级](docs/zh/01-conventions/01-engineering.md#版本与升级) |
| 改了代码不升版本，或原地改已发布的版本 | 构建跳过已有镜像，容器继续跑旧代码 | [版本](docs/zh/01-conventions/10-development-workflow.md#版本) |
| 对有未提交或未推送改动的组件 `brickkit remove --force` | 连同改动删掉源码 | [发布](docs/zh/01-conventions/10-development-workflow.md#发布) |

<!-- brickkit:managed:begin lang=zh -->
<!-- 由 brickkit 维护（init、add、remove、upgrade、skills update）：这对标记之间的改动会被覆盖 -->

## BrickKit

这个项目用 [BrickKit](https://github.com/brickKit/brickKit) 组装：每个组件在自己的 `component.yaml` 里描述自己；`brickkit` 命令行解出依赖图、生成部署文件后就退出。没有注册中心、配置中心、网关，不用去找。

- `brickkit.yaml` 列出组件和它们的精确版本（它就是锁文件）；`deploy.yaml` 写怎么运行（本地模式开着时，你机器上用 `deploy.local.yaml` 整份替换它）；`config/<scope>-<name>.yaml` 是每个组件的环境变量，`config/vars.yaml` 是共用的值。
- `brickkit add` / `remove` / `upgrade` 会让三层文件一起改：别手改一层、忘了另一层。
- 配置项的键就是组件 `configSchema` 声明的环境变量名；密钥写成 `${VAR}` 或 `file://.secrets/…`，不写明文。
- 健康检查只查自己这个进程。只想改一个组件时，在它的目录里 `brickkit up`；`brickkit up --all` 回到全部运行。
- 按任务分的技能在 `.claude/skills/brickkit-*`；参数问 `brickkit <命令> --help`；BrickKit 自己的文档（与装着的版本一致）用 `brickkit docs` 看（列出全部页；`brickkit docs 04-shell` 打印一页）。

## 组件

`COMPONENTS.md` 列出本项目的组件（现有 13 个），每个一行：ID、版本、干什么、带哪些文档、主页。它由 brickkit 维护；找一项任务归哪个组件时读它，或在里面按 ID、按 scope 搜。

组件的文档是 `BRICKKIT.md`（译本 `BRICKKIT.<语言>.md`）：本地源里正好是这个版本时在源码目录里，否则在 `.brickkit/manifests/<id>/<version>/`；契约在 `.brickkit/artifacts/<服务名>/`（ID 和版本用 `-` 连起来，其中的 `/` 和 `.` 也都换成 `-`：`erp/backend` 1.0.0 → `erp-backend-1-0-0`）。要改某个组件，读它自己的 `AGENTS.md`。
<!-- brickkit:managed:end -->
