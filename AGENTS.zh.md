[English](AGENTS.md) · [中文](AGENTS.zh.md)

# be-assembly-standard

本项目的 AI 指南：项目是什么、这里每个组件都遵守的规则、该去哪里找。组件表由 brickkit 维护，只在英文版 [AGENTS.md](AGENTS.md) 末尾。

> **文档语言不等于对话语言。** 正式文档用英文写，是为了让 AI 读得高效。本项目的维护者只用中文交流，所以给他的每一条回复都用中文，不管正在讨论的文件、代码或上一条工具输出是什么语言。落笔第一个字之前就定下回复语言；写完再检查，已经证明靠不住。

## 概览

- **这是什么。** BrickEnterprise：一套 ERP/CRM 组件库，加上用 brickKit 把它们装配起来的标准组装模板。这里也是 brickKit 各项功能真机验证的地方；在这里发现的平台 bug，写复现报给 brickKit，绝不在组件里绕过去。
- **九个领域**，组件 ID 是 `<领域>/<名字>`（仓库名 `<领域>-<名字>`）：`infra`、`integration`、`mdm`（主数据）、`crm`、`erp`、`hrm`、`prj`、`ana`、`frontend`。
- **三个中枢**把其余组件串起来。`mdm/*` 被所有组件读，自己不调用任何组件。`erp/inventory` 是实物库存变动的唯一写入者。`erp/finance` 基本只接受命令、监听事件。CRM 与 ERP 之间没有同步调用边，只有事件；库存与财务之间没有任何边，由同一个上游（比如 `erp/sales`）并排触发。
- **东西在哪。**
  - `components/<scope>/<name>/`：每个组件一个 Git 子模块；`.gitmodules` 记录每个组件的确切提交。
  - `shell/<scope>/<name>/`：外壳（`be/go-core`、`be/go-infra`、`be/go-backoffice`、`be/py-render`）；每个都是独立仓库，像组件一样以 Git 子模块检出，供别的装配项目复用（[0108](docs/zh/02-decisions/01-architecture/0108-one-repository-per-shell.md)）。
  - `tools/`：`be-sdk-go`、`be-sdk-python`、`be-sdk-ts`（每个组件依托的运行时库）、`be-ops`（组装期生成：建库脚本、权限与数据范围登记表）、`be-acceptance`（`make gates` 背后的门禁）。
  - `registry/`（端口、schema、权限键、数据范围）、`config/`（组件配置值，共享值在 `vars.yaml`）、`infra/`（`make up` 启动的基础资源）、`docs/zh/`（约定、决策、种子数据、底层选择：每块基础设施为什么是这样、怎么更换；[索引](docs/zh/README.md)），与英文的 `docs/en/` 逐文件对应。
- **两条不可违背的原则。**
  1. **每个组件都是完整的 brickKit 组件，能单独运行。** 调用其他组件一律走真实的 gRPC 或 HTTP，`extraPorts` 里的每个端口都真的监听，`brickkit up --focus <id>` 只带着它的依赖就能把它起来。"反正最后在同一个外壳里，直接调函数吧"就破坏了这一条，这个组件从此再也不能单独部署。
  2. **合并只发生在部署层。** 外壳把 N 个进程变成 1 个，除此之外什么都不做。

## 约定

每条一行；链接的文件是完整规则。请求违反其中一条时，引用那个文件，交给人决定。

- **配置**：键名是大写下划线的环境变量名；共享连接键是 `PG_*`、`NATS_URL`、`S3_URL`、`OTEL_BASE_URL`、`AUTHZ_BUNDLE_URL`、`IAM_JWKS_URL`；不得以 `_ENDPOINT` 结尾（[04-configuration.md](docs/zh/01-conventions/04-configuration.md)）。
- **值写在哪里**：多个组件共用的值在 `config/vars.yaml` 写一次，用 `$var:NAME` 引用；组件自己的值写在 `config/<scope>-<name>.yaml`；密钥只能写成 `${NAME}`（[04-configuration.md](docs/zh/01-conventions/04-configuration.md#值写在哪里)）。
- **流程**：七步循环，先契约、再业务规则测试、再代码，文档先于代码（[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md)）；每次都要回答[写代码之前](docs/zh/01-conventions/01-development-workflow.md#写代码之前)的那几个问题。
- **后端**：每种语言一套锁定的技术栈、一个模块入口、一切经 `rt`、写法本身保证合并安全（[02-backend.md](docs/zh/01-conventions/02-backend.md)）。
- **前端**：Vue 3，PC 端 AntDV + vxe-table，移动端 wot-design-uni，设计 token 是 CSS 变量，第三方 UI 组件只出现在 ui-kit 里（[03-frontend.md](docs/zh/01-conventions/03-frontend.md)）。
- **测试**：L1–L4 与 FE-1–FE-4 分层；绝不为了让测试通过而改测试（[06-testing.md](docs/zh/01-conventions/06-testing.md)）。
- **数据**：种子数据给人用，测试数据给测试用，两个物理库（`brickkit_db`、`brickkit_test_db`）；依赖方缺能力就在源头补（[05-data.md](docs/zh/01-conventions/05-data.md)）。
- **登记表**：端口、schema、角色、权限键都从 `registry/` 抄，绝不自己编；`ports.tsv`、`schemas.tsv`、`permissions.tsv` 只追加：已有的行绝不修改、删除或回收再用（[07-registries.md](docs/zh/01-conventions/07-registries.md#只追加)）。
- **子模块映射**：`.gitmodules` 与子模块指针记录每个组件和外壳来自哪个仓库、哪一个确切提交；只通过 `git submodule` 命令改动，指针与需要它的那次 `brickkit upgrade` 一起提交（[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#发布)）。
- **每个组件两份清单**：`component.yaml` 只放 brickKit 读的内容；本项目自己的键（`permissions`、`data_scopes`、`menus`，以及 `domain`、`tier` 这类项目自己的元数据）放在旁边的 `assembly.yaml`，由 be-ops 读取（[02-backend.md](docs/zh/01-conventions/02-backend.md#仓库结构)）。组件由哪个外壳托管，在部署文件里选（[0108](docs/zh/02-decisions/01-architecture/0108-one-repository-per-shell.md)）。
- **版本号**：每次改动都升版本，版本号是精确值，组件在 `2.x`、外壳在 `1.x`；Go 组件在同一个提交上打两个 tag（brickKit 用的 `2.0.0`、Go 用的 `v2.0.0`），模块路径以 `/v2` 结尾；外壳在它自己的仓库发布，只打裸 tag（`1.0.0`）；用 `make bump-version` 传播（[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#版本号)）。
- **提交与发布**：提交信息用中文、写进文件、`git commit -F`，tag 一律带注释，按 `bump-version` 打印的顺序发布（[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#发布)）。
- **业务逻辑**：先自己设计，卡住才看参考实现，绝不照抄（[10-reference-implementations.md](docs/zh/01-conventions/10-reference-implementations.md)）。
- **按 AI 的尺寸写代码**：只在帮 AI 读懂时才用模式；函数、文件、一次会话的大小都有上限（[09-ai-development.md](docs/zh/01-conventions/09-ai-development.md)）。
- **文档**：英文为准，两种语言 `##` 小节一致；项目文档是 `docs/en/` 与 `docs/zh/` 两棵镜像树（`make docs-mirror`），根目录文档和组件文档沿用 brickKit 的 `.zh.md` 后缀；正式文档不得链接 `dev/` 或 `archive/`（`make docs-boundary`）（[08-documentation.md](docs/zh/01-conventions/08-documentation.md)）。
- **决策**：[docs/zh/02-decisions/](docs/zh/02-decisions/README.md) 说明项目为什么是这个形状、哪些提议不要再提；决策与约定冲突时，决策为准。
- **容器默认关闭**：`make up` 起的基础资源可以常驻；组件容器在验证完后用 `brickkit down` 关掉（[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#真机运行)）。

## 去哪里找

| 你在做什么（你会搜的词） | 先读 |
|---|---|
| 新需求、新功能、"这个该放哪"、"这个主意好不好"、一个跨组件的改动 | `brickkit-plan-change` 技能（[SKILL.md](.claude/skills/brickkit-plan-change/SKILL.md)），再看 [docs/zh/02-decisions/](docs/zh/02-decisions/README.md)；规划中的组件可能已在 `registry/` 里预留了 ID、端口和 schema |
| 开始做一个组件；事情按什么顺序做；一次会话做多少 | [01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#七步循环)、[09-ai-development.md](docs/zh/01-conventions/09-ai-development.md#一次会话做多少) |
| 写一个新组件；改 `component.yaml`；仓库结构 | `brickkit-component` 技能（[SKILL.md](.claude/skills/brickkit-component/SKILL.md)）、[02-backend.md](docs/zh/01-conventions/02-backend.md#仓库结构) |
| 用哪个端口、schema、数据库角色或权限键 | [07-registries.md](docs/zh/01-conventions/07-registries.md) |
| 给配置键起名；读一个配置值；连 PostgreSQL、NATS 或对象存储；数据库密码 | [04-configuration.md](docs/zh/01-conventions/04-configuration.md)、[04-configuration.md](docs/zh/01-conventions/04-configuration.md#数据库角色)、[02-backend.md](docs/zh/01-conventions/02-backend.md#rt-是唯一入口) |
| 用哪个框架或库；写 `main`；模块入口 | [02-backend.md](docs/zh/01-conventions/02-backend.md#技术栈)、[02-backend.md](docs/zh/01-conventions/02-backend.md#模块入口)、[0103](docs/zh/02-decisions/01-architecture/0103-locked-stack-per-language.md) |
| 加一个接口；谁能调用它；权限键 | [02-backend.md](docs/zh/01-conventions/02-backend.md#权限) |
| 让一张表只给某些人看某些行（"销售只看自己的订单"、"仓管只看一个仓库"） | [02-backend.md](docs/zh/01-conventions/02-backend.md#数据范围)、[0205](docs/zh/02-decisions/02-permissions/0205-data-scopes-ship-with-the-version.md)、[0206](docs/zh/02-decisions/02-permissions/0206-no-row-level-security.md) |
| 调用另一个组件；展示别的组件拥有的数据 | [02-backend.md](docs/zh/01-conventions/02-backend.md#调用其他组件) |
| 加表、加迁移、加分区 | [02-backend.md](docs/zh/01-conventions/02-backend.md#数据库) |
| 发布或消费事件；跨组件写入；超时或补偿 | [02-backend.md](docs/zh/01-conventions/02-backend.md#事件与跨组件写入) |
| 改契约：改字段名、删 rpc 或删事件 | [02-backend.md](docs/zh/01-conventions/02-backend.md#契约)、[0302](docs/zh/02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md) |
| 金额、价格、钱的字段；列表分页 | [0301](docs/zh/02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md) |
| 加缓存；Redis；让权限检查更快 | [0201](docs/zh/02-decisions/02-permissions/0201-no-redis.md)、[0202](docs/zh/02-decisions/02-permissions/0202-local-permission-bundle.md) |
| 外壳启动即退出：某成员"未登记" / 没编译进本外壳；外壳成员不一致 | 下方[易错点](#易错点)里外壳 registry 那一行；`brickkit` 自己打印的错误看 `brickkit-troubleshoot` 技能 |
| 把几个组件放进一个进程；外壳；外壳托管哪些成员 | [0108](docs/zh/02-decisions/01-architecture/0108-one-repository-per-shell.md)、`brickkit-component` 技能（外壳部分）、[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#真机运行)（拆回验证） |
| 该写什么测试、放哪一层；测试红了、卡住了 | [06-testing.md](docs/zh/01-conventions/06-testing.md)、[卡住时](docs/zh/01-conventions/06-testing.md#卡住时) |
| 对着真实依赖跑测试 | [06-testing.md](docs/zh/01-conventions/06-testing.md#跨组件测试)、[06-testing.md](docs/zh/01-conventions/06-testing.md#运行测试) |
| 演示数据；测试账号；怎么登录 | [docs/zh/03-seed-data.md](docs/zh/03-seed-data.md) |
| 设计种子数据或测试数据；依赖方没有我要的数据 | [05-data.md](docs/zh/01-conventions/05-data.md) |
| 前端页面、组件库、主题、菜单、只有部分用户能看到的按钮 | [03-frontend.md](docs/zh/01-conventions/03-frontend.md) |
| 这段业务逻辑该怎么做；该看哪个开源 ERP | [10-reference-implementations.md](docs/zh/01-conventions/10-reference-implementations.md) |
| 同一个功能有几种都合理的做法；"让客户自己选" | [10-reference-implementations.md](docs/zh/01-conventions/10-reference-implementations.md#槽位族信号)、[0104](docs/zh/02-decisions/01-architecture/0104-variants-become-slot-families.md) |
| 要不要用设计模式；文件或函数越写越长 | [09-ai-development.md](docs/zh/01-conventions/09-ai-development.md#何时用设计模式) |
| 写、拆分或翻译文档；组件的文档 | [08-documentation.md](docs/zh/01-conventions/08-documentation.md) |
| 升版本；发布；打 tag；"ship it" | `version-bump-ship` 技能（[SKILL.md](.claude/skills/version-bump-ship/SKILL.md)）、[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#版本号) |
| 怎么安装或部署；谁来建数据库；密钥；Kubernetes；另一套环境 | `brickkit-deploy` 技能（[SKILL.md](.claude/skills/brickkit-deploy/SKILL.md)）；各组件的 `components/<scope>/<name>/BRICKKIT.md` 里 "Before you deploy" 一节；[07-registries.md](docs/zh/01-conventions/07-registries.md#schema-与角色)（`make db-init`） |
| 在 IDE 里调试一个组件；只跑一个组件 | [01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#真机运行)、`brickkit-deploy` 技能 |
| 在项目里加、删、升级组件；某个组件为什么没起来 | `brickkit-assemble` 技能（[SKILL.md](.claude/skills/brickkit-assemble/SKILL.md)） |
| 某条 `brickkit` 命令报错或打出 `error_code` | `brickkit-troubleshoot` 技能（[SKILL.md](.claude/skills/brickkit-troubleshoot/SKILL.md)）；参数：`brickkit <命令> --help` |
| 一个可能与已记录的决策冲突的改动；"为什么不用 React / Java / RLS / Deny 规则 / 配置中心……" | [docs/zh/02-decisions/](docs/zh/02-decisions/README.md)（提议前先读；决策与约定冲突时决策为准） |
| 为什么用这个数据库 / 队列 / 事务模型 / id / 金额格式；替换某块基础设施；有哪些实现、怎么换 | [docs/zh/04-foundations/README.md](docs/zh/04-foundations/README.md)（先看端口表，再看那一块的文档） |
| 上面某条一行约定的完整规则；上线、备份、轮换密钥、生产故障（运维文档，尚未编写：将放在 `docs/zh/05-operations/`） | 约定：[docs/zh/01-conventions/](docs/zh/01-conventions/)；决策：[docs/zh/02-decisions/](docs/zh/02-decisions/README.md)；运维：`docs/zh/05-operations/` 建好之前看 `brickkit-deploy` 技能 |
| 某个组件是做什么的；改某个组件 | 英文版 [AGENTS.md](AGENTS.md) 末尾的组件表，再看 `components/<scope>/<name>/BRICKKIT.md`（它拥有什么）和它的 `AGENTS.md`（怎么改它） |

这里没有？看组件表，再看那个组件的 `AGENTS.md`。

## 易错点

对每个组件都成立的错误。大多数看起来是对的、测试能过，很久以后才出症状。

| 绝不 | 症状 | 原因 |
|---|---|---|
| `SET ROLE` / `SET search_path` 不带 `LOCAL` | 下一个从连接池借到这条连接的人，查询落在你的 schema 上：不报错、不崩溃，读写的是别的组件的数据 | 不带 `LOCAL` 的设置会活过事务。用 `besdk.WithTx`（[02-backend.md](docs/zh/01-conventions/02-backend.md#数据库)） |
| 在模块代码里读 `os.Getenv` / `os.environ` | 单独运行全绿；合进外壳后，成员互相覆盖 `PG_SCHEMA` 和其他所有键，某个模块悄悄用上别人的 schema | 一个进程只有一份环境。配置只从 `rt.Config` 来（[02-backend.md](docs/zh/01-conventions/02-backend.md#合并安全)） |
| 在模块里做进程级初始化：`otel.SetTracerProvider`、`logging.basicConfig`、信号处理、默认 Prometheus registry、`gin.SetMode` | 合并后最后一个初始化的赢，所有 trace 落在同一个服务名下，一个模块的 debug 模式让所有模块都向客户端泄露堆栈；默认 registry 在第二个模块注册时 panic | 用 `rt.Logger`、`rt.Tracer`、`rt.Meter`、`rt.Registry`（[02-backend.md](docs/zh/01-conventions/02-backend.md#合并安全)） |
| 在模块里 `log.Fatal` / `os.Exit` / `sys.exit`，或 `gin.New()` / `sql.Open()` / `Listen` | 一个模块的可恢复错误拖垮整个外壳；`gin.New()` 悄悄丢掉 SDK 的整条中间件链：请求 ID、链路追踪、RED 指标、访问日志、panic 恢复和错误映射 | 返回错误；用 `besdk.NewGinEngine(rt)`、`rt.DB`；端口由调用方监听（[02-backend.md](docs/zh/01-conventions/02-backend.md#合并安全)） |
| import 另一个组件的代码、共用模型包、或复制它生成的契约代码 | 什么都不坏，直到某天组件必须单独运行而做不到；复制的生成代码在调用方与被调方进入同一个外壳时启动即 panic | 跨边界的代码只有 `be-sdk-*` 和被 import 的 `gen/<domain>/<name>` 包（[0101](docs/zh/02-decisions/01-architecture/0101-no-imports-between-components.md)） |
| 把注入的 `*_ENDPOINT` 值原样拿去拨号 | 它总以 `http://` 开头，gRPC 端口也一样；拨号失败，错误指向域名解析。端口名传 `""` 时 gRPC 打到 HTTP 端口：TCP 能连上，随后报协议错误 | 用 `rt.Config.Endpoint(dep, "grpc")`（[02-backend.md](docs/zh/01-conventions/02-backend.md#rt-是唯一入口)） |
| 把缺席的可选依赖当成空值，或直接按下标取环境变量 | 这个变量根本不存在；按下标取值启动即崩 | `Endpoint` 返回 `ok == false`，模块降级（[02-backend.md](docs/zh/01-conventions/02-backend.md#rt-是唯一入口)） |
| 配置键起名为 `*_ENDPOINT`、`COMPONENT_ID`、`COMPONENT_VERSION`、`PORT` 或 `BRICKKIT_SERVED_MEMBERS*` | 平台的值胜出，只给一条警告；`up` 全绿，组件永远拿不到你的值 | 这些名字属于平台（[04-configuration.md](docs/zh/01-conventions/04-configuration.md#键名)） |
| 在 `/healthz` 里检查数据库、NATS、authz 或其他组件 | 下游一抖，所有上游被判不健康并重启；在外壳里所有成员一起重启 | `/healthz` 只报告本进程活着（[02-backend.md](docs/zh/01-conventions/02-backend.md#健康检查与镜像)） |
| 镜像基于 `scratch` 或 distroless | 组件日志说"ready"，平台永远判它不健康 | 健康检查经 `/bin/sh` 和 `wget` 执行（[02-backend.md](docs/zh/01-conventions/02-backend.md#健康检查与镜像)） |
| 用裸 `r.GET` / `@app.get` 注册业务路由，或 resolver 不包一层 | 这个接口完全没有权限检查，零症状 | 权限键是路由注册的一部分；`make gates` 会扫（[02-backend.md](docs/zh/01-conventions/02-backend.md#权限)） |
| 在服务用户请求的路径上用 `besdk.SystemClient` | 返回结果悄悄多出用户无权看的行 | 它带的是组件自己的身份，绕过数据范围；只用于 `Start()` 和事件处理（[02-backend.md](docs/zh/01-conventions/02-backend.md#调用其他组件)） |
| `assembly.yaml` 里省略 `data_scopes` | be-ops 拒绝这个组件 | 有意为之：安全设置不能默认关闭。不需要行级范围就写 `data_scopes: none`（[0205](docs/zh/02-decisions/02-permissions/0205-data-scopes-ship-with-the-version.md)） |
| `owner` OR `org` 组合时有一个操作数停在"全匹配" | 整个条件匹配一切，每个用户都看到所有行 | 两个操作数都必须来自调用方真实的范围（[02-backend.md](docs/zh/01-conventions/02-backend.md#数据范围)） |
| 把空的 `dept_path` 当成部门树的根 | 新建、还没分部门的用户在每个按 `org` 限定的列表里看到所有部门的行 | 只有没分部门时 `dept_path` 才为空；SDK 给这种人的 `org` 维一个永远不匹配的哨兵（be-sdk-go / be-sdk-python / be-sdk-ts v0.5.0）。整棵树是根部门，或者 `/`（[02-backend.md](docs/zh/01-conventions/02-backend.md#数据范围)） |
| 改名或复用已发布的权限键 | 被授予它的每个角色悄悄失去它；升级后用户突然点不了某个按钮 | 权限键是持久标识；退役用 `deprecated` 列（[07-registries.md](docs/zh/01-conventions/07-registries.md#只追加)） |
| 前端只查 `features`，不查 `permissions` | 菜单项看得见，点进去是整页 403 | `features` 说装了什么，`permissions` 说这个用户能做什么（[03-frontend.md](docs/zh/01-conventions/03-frontend.md#功能权限与菜单)） |
| 把本项目的键（`permissions`、`data_scopes`、`menus`，以及 `domain`、`tier` 这类项目自己的元数据）写进 `component.yaml` | `brickkit lint` 和 `brickkit add` 拒绝整份清单：`MANIFEST_INVALID`、`unknown field`；组件加不进项目、也起不来 | `component.yaml` 没有扩展字段；这些键属于 `assembly.yaml`（[02-backend.md](docs/zh/01-conventions/02-backend.md#仓库结构)） |
| 挪动已登记的端口、给 schema 改名、或分配 `1xxxx` 端口 | 每个依赖方和托管它的外壳都坏掉；schema 改名就是数据迁移；`1xxxx` 端口与 brickKit 为 `mode: debug` / `local` 做的宿主机映射冲突 | [07-registries.md](docs/zh/01-conventions/07-registries.md#端口) |
| 用先 `SELECT` 再写的方式认领队列行或幂等键 | 两个副本把每条 outbox 记录发两遍；两个并发请求都执行了 | 原子认领：`FOR UPDATE SKIP LOCKED`、`INSERT … ON CONFLICT DO NOTHING`（[02-backend.md](docs/zh/01-conventions/02-backend.md#数据库)） |
| 用浮点数传金额，或 `List` 用 `offset` 分页 | 金额在语言之间丢精度；深翻页变慢且漏行 | 十进制字符串和游标（[0301](docs/zh/02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md)） |
| 为了让测试通过而改测试：注释掉、`t.Skip`、放宽断言 | 一切全绿，什么都没守住 | 改实现；测试确实错了，就单独一个提交改它，并说明原因（[06-testing.md](docs/zh/01-conventions/06-testing.md#红绿节奏与铁律)） |
| 改 Fork 组件的 `metadata.id` | 换了 ID，每个依赖方的 `<ID>_ENDPOINT` 变量整个消失 | Fork 保留 `metadata.id`，但版本照常走：每次改动都升 `metadata.version`，依赖方用 `brickkit upgrade` / `make bump-version` 移动版本钉；只有仓库名和目录名可以不同（[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#发布)） |
| 外壳 `main` 里登记的成员（它的 registry）与 `component.yaml` 的 `shell.members` 不一致，或 Go 外壳的 `go.mod` 与二者之一不一致 | 要托管的成员没登记：外壳启动即退出，里面所有成员一起下线。`go.mod` 没 require 的成员版本：镜像里跑的代码不是项目以为的那份，不报任何错 | JSON 说托管谁，二进制决定有谁；`make bump-version` 会同时改 `shell.members` 和 `go.mod`（[0108](docs/zh/02-decisions/01-architecture/0108-one-repository-per-shell.md)） |
| 以为 `deploy.local.yaml` 会和 `deploy.yaml` 合并 | 本地模式开着时，改 `deploy.yaml` 不起作用；团队后来的改动永远到不了你的副本，组件集合一不同 `up` 就拒绝 | 它整份替换 `deploy.yaml`。`brickkit up --focus` 会打开本地模式，`--all` 不会关掉。`brickkit local status` 显示开关；改 `deploy.yaml` 之前 `brickkit local off`，或改完之后 `brickkit local refresh`，它会列出你旧的改动供手工重放（[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#真机运行)） |
| 用外壳的服务名寻址 authz 或 iam，或者它们发版后 `AUTHZ_BUNDLE_URL` / `IAM_JWKS_URL` 还停在旧版本 | 每个组件的每条受保护路由都返回 `503` 或 `403`，而 `/healthz` 保持绿色 | `config/vars.yaml` 里用成员自己的服务名，authz 或 iam 发版时跟着改；与 `brickkit.yaml` 对不上时 `make gates`（`service-hostname-scan`）失败（[04-configuration.md](docs/zh/01-conventions/04-configuration.md#依赖地址)） |
| Go 组件发 `2.x` 时只打 brickKit 的 tag，或模块路径不带 `/v2` | 外壳的 Go 构建拉不到成员：`unknown revision v2.0.0`，或 "module path must match major version" | Go 需要带 `v` 的 tag 和路径里的主版本号；brickKit 的 tag 不带 `v`（[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#版本号)） |
| 改了代码不升 `metadata.version`，或原地改已发布的版本 | `brickkit build` 跳过已存在的镜像，容器继续跑旧代码，全绿 | 镜像 tag 就是版本号（[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#版本号)） |
| 组件有未提交或未推送的改动时 `brickkit remove --force` | `--force` 会连同这些改动删掉源码目录。不加它，`remove` 在写任何东西之前就停下；登记为 Git 子模块的组件会以 `SUBMODULE_GUARD` 停下 | 先提交并推送组件，再注销子模块（`git submodule deinit -f <path>`、`git rm <path>`），然后重跑 `brickkit remove`（[01-development-workflow.md](docs/zh/01-conventions/01-development-workflow.md#发布)） |
