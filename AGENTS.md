# be-assembly-standard

给 AI 的项目导读：这是什么项目、每个组件都遵守的规则、做什么去看哪里。文件末尾的组件表由 BrickKit 维护。

> **与维护者交流一律用中文**，不论正在读的文件、代码或上一次工具输出是什么语言。落笔前先定回复的语言；写完再检查已被证明不可靠。代码（标识符、注释、日志、错误信息）与提交信息用英文（D74）。

## 项目概述

- **这是什么**：BrickEnterprise，ERP 为主、加入 CRM 的组件货架，加上用 BrickKit 把它们装配起来的标准装配项目。它也是 BrickKit 功能在真实机器上的验证场：在这里发现的平台问题，写出复现报给 BrickKit，绝不在组件里绕过去。
- **现在处于哪个阶段**：终局设计已冻结（2026-10-15），正式文档是 `docs/zh/`。现有的组件代码（2.x）只作参考，按新设计从零重建（D59）；重建的范围、顺序与仓库处理见 `dev/rebuild/`。先做代表部署实验（D41），再重建当前范围。
- **两份组件清单别混淆**：文件末尾由 BrickKit 维护的组件表，列的是现在装配着的旧设计（2.x）组件与版本；新设计的组件、范围与边界以[组件全景](docs/zh/00-overview/03-catalog.md)与[边界卡](docs/zh/07-components/README.md)为准。设计改动按新设计回答，不按旧组件表。
- **组件 ID** 是 `<领域>/<名字>`（仓库 `<领域>-<名字>`）；领域、边界与依赖方向见[领域与边界](docs/zh/00-overview/02-domains-and-boundaries.md)，全部组件见[组件全景](docs/zh/00-overview/03-catalog.md)与[边界卡](docs/zh/07-components/README.md)。
- **东西放在哪里**：
  - `components/<scope>/<name>/`：每个组件一个 Git 子模块；`shell/<scope>/<name>/`：外壳，同样是子模块；`.gitmodules` 记下每个的确切提交。
  - `tools/`：`be-sdk-go`、`be-sdk-python`、`be-sdk-ts`（组件运行时）、`be-ops`（装配时生成）、`be-acceptance`（参考模型与文档检查）。
  - `registry/`（端口、schema、权限键等）、`config/`（组件配置，`vars.yaml` 放共享值）、`infra/`（`make up` 启动的基础资源）、`docs/zh/`（正式文档，[索引](docs/zh/README.md)）、`dev/`（进行中的工作）、`archive/`（归档，现行内容不引用）。
- **两条不变的原则**（[产品](docs/zh/00-overview/01-product.md#两条不变的原则)）：
  1. **每个组件都是完整的 BrickKit 组件，能单独运行**：对其他组件的每次调用都走真实的网络调用，只带上它依赖的组件就能启动。“反正最后在同一个外壳里，直接调函数好了”违反这一条，组件就再也不能单独部署。
  2. **合并只发生在部署时**：外壳把几个进程合成一个，除此之外什么也不做。

## 项目约定

每条一行，链接的文件是完整规则。请求与某条约定冲突时，引用该文件向维护者提出。

- **决定优先**：[决定记录](docs/zh/02-decisions/README.md)说明项目为什么是现在这样、哪些方向不要再提；决定优先于规范，规范优先于单个组件的约定。
- **开发流程**：七步循环，契约先于业务规则测试，业务规则测试先于实现，文档先于代码（[开发流程与发布](docs/zh/01-conventions/10-development-workflow.md)）。
- **组件代码**：一个模块入口，一切经 SDK 的运行时，合并安全（[组件实现约定](docs/zh/01-conventions/06-component-implementation.md)）；每种语言一套锁定的技术栈（[组件协议与语言](docs/zh/04-foundations/07-component-protocol-and-languages.md)）。
- **测试**：L1–L4 按范围分层、FE-1–FE-4；绝不为了让测试通过而改测试（[测试与验证](docs/zh/01-conventions/02-testing-and-validation.md#实现测试的分层与节奏)）。
- **数据**：种子数据给人、测试数据给测试，两个物理库；依赖方缺能力时去源头补；凭据绝不进入部署（[种子与测试数据](docs/zh/01-conventions/07-seed-and-test-data.md)）。
- **配置与注册表**：配置键是大写下划线，组件只经 SDK 读取；共享值写一次、用引用；密钥只写引用；端口、schema、权限键从注册表抄，身份列只追加（[协议 19](docs/zh/06-protocols/19-config-secrets-registries-release.md)）。
- **权限**：每个操作在资源定义中登记，完整授予逐份判定，看不见答 404（[授权选型](docs/zh/00-overview/guides/authorization.md)、[安全协议](docs/zh/06-protocols/security/README.md)）。
- **跨组件**：经契约调用；业务写入与发件表同事务；事务内不发网络调用（[事务与消息](docs/zh/04-foundations/03-transactions-and-messaging.md)、[协议目录](docs/zh/06-protocols/README.md)）。
- **版本**：每次改动都升版本，版本精确；全部从 `3.0.0` 起，`X` 大版本、`Y` 阶段性变化（新功能、从开发进入正式）、`Z` 修复；用过的版本号绝不重复使用（[开发流程与发布的版本](docs/zh/01-conventions/10-development-workflow.md#版本)）。
- **提交与发布**：英文提交信息先写进文件再 `git commit -F`，带注释的标签，按依赖顺序发布（[开发流程与发布](docs/zh/01-conventions/10-development-workflow.md#提交)）。
- **子模块地图**：`.gitmodules` 与子模块指针只经 `git submodule` 命令改变，指针与需要它的 `brickkit upgrade` 一起提交。
- **参考实现**：先自己设计，卡住才看参考，绝不照抄（[参考实现](docs/zh/01-conventions/08-reference-implementations.md)）。
- **AI 友好的代码**：模式只用在帮助 AI 读懂的地方；越底层越要想性能、查市场上更好的做法，业务逻辑以看得懂优先；函数、文件与会话有大小上限（[AI 编码习惯](docs/zh/01-conventions/09-ai-coding.md)、[AI 导航](docs/zh/01-conventions/05-ai-navigation.md)）。
- **表达方式**：根据情况选图、表、代码、步骤、填好的样例或文字，哪种最好懂用哪种；意图类的图表先改再改代码，事实类从代码生成；用了设计模式画角色图（[图与表的规范](docs/zh/01-conventions/04-diagrams-and-tables.md)）。
- **文档**：开发完成前只写中文（D67），同一规则只写在一处；正式文档不链接 `dev/` 与 `archive/`（`make gates`）（[文档规则](docs/zh/01-conventions/03-documentation.md)）。
- **容器默认关着**：`make up` 的基础资源可以常开；组件容器验证完就 `brickkit down`。

## 查找路由

| 你要做的事（你会用的词） | 先读 |
| --- | --- |
| 新需求、新功能、“放在哪里”、“这样好不好”、跨组件的改动 | `brickkit-plan-change` 技能（[SKILL.md](.claude/skills/brickkit-plan-change/SKILL.md)），然后[领域与边界](docs/zh/00-overview/02-domains-and-boundaries.md)、[边界卡](docs/zh/07-components/README.md)与[决定记录](docs/zh/02-decisions/README.md) |
| 开始做一个组件；先做什么后做什么；一次会话做多少 | [开发流程与发布](docs/zh/01-conventions/10-development-workflow.md)、[AI 导航的每次会话读多少](docs/zh/01-conventions/05-ai-navigation.md#每次会话读多少) |
| 写新组件；改 `component.yaml`；仓库布局 | `brickkit-component` 技能（[SKILL.md](.claude/skills/brickkit-component/SKILL.md)），[组件实现约定](docs/zh/01-conventions/06-component-implementation.md#仓库布局与入口) |
| 用哪个端口、schema、数据库角色、权限键 | [协议 19 的注册表](docs/zh/06-protocols/19-config-secrets-registries-release.md#注册表) |
| 给配置键起名；读配置；连数据库、消息系统或对象存储；数据库密码 | [协议 19 的配置](docs/zh/06-protocols/19-config-secrets-registries-release.md#配置)、[协议 14 的数据库](docs/zh/06-protocols/14-data-foundations.md#数据库)、[组件实现约定的运行时](docs/zh/01-conventions/06-component-implementation.md#运行时是唯一入口) |
| 用哪个框架或库；写入口 | [组件协议与语言的锁定的技术栈](docs/zh/04-foundations/07-component-protocol-and-languages.md#锁定的技术栈) |
| 加一个接口；谁能调用；权限键；资源定义 | [安全 06](docs/zh/06-protocols/security/06-security-contracts-and-capabilities.md)、[安全 09a](docs/zh/06-protocols/security/09a-encoding-and-records.md) |
| 某个表只让一部分人看到一部分行（“销售只看自己的单”“库管只看一个仓库”） | [安全 07](docs/zh/06-protocols/security/07-finite-expressions-containment-and-queries.md)、[授权选型](docs/zh/00-overview/guides/authorization.md) |
| 调用别的组件；显示别的组件拥有的数据 | [组件实现约定的调用其他组件](docs/zh/01-conventions/06-component-implementation.md#调用其他组件)、[组件间调用与错误](docs/zh/04-foundations/08-calls-and-errors.md) |
| 加表、迁移、分区；身份、单号、日期、金额 | [协议 14](docs/zh/06-protocols/14-data-foundations.md) |
| 列表的分页、排序、筛选与关键字搜索；跨组件的全局搜索与报表 | [协议 14 的列表](docs/zh/06-protocols/14-data-foundations.md#列表游标排序与筛选)、[安全 07](docs/zh/06-protocols/security/07-finite-expressions-containment-and-queries.md)、[协议 13](docs/zh/06-protocols/13-search-reports-and-datasets.md) |
| 发布或消费事件；跨组件写入；超时与补偿；预占 | [事务与消息](docs/zh/04-foundations/03-transactions-and-messaging.md)、[协议 02](docs/zh/06-protocols/02-projections.md)、[协议 04](docs/zh/06-protocols/04-order-reservation.md) |
| 后台任务、定时任务、对账 | [协议 01](docs/zh/06-protocols/01-background-work.md) |
| 改契约：改字段名、删接口或事件 | [协议 19 的版本与产物](docs/zh/06-protocols/19-config-secrets-registries-release.md#版本与产物)、[原有决定 0302](docs/zh/02-decisions/10-earlier-decisions.md#0302-契约只做加法从新版本发布之后约束) |
| 加缓存；Redis；让权限检查更快 | [底层选择的缓存一行](docs/zh/04-foundations/README.md#推荐组合与改选条件)、[安全 03](docs/zh/06-protocols/security/03-authorization-acceptance-and-revocation.md) |
| 几个组件放进一个进程；外壳；外壳承载哪些成员；外壳启动时报成员未注册 | [协议 17 的外壳义务](docs/zh/06-protocols/17-runtime-and-resources.md#外壳义务)、[部署与运行](docs/zh/04-foundations/01-deployment-and-runtime.md)、`brickkit-component` 技能（外壳） |
| 写哪种测试、放哪一层；测试红了卡住 | [测试与验证](docs/zh/01-conventions/02-testing-and-validation.md#实现测试的分层与节奏)、[卡住时](docs/zh/01-conventions/02-testing-and-validation.md#卡住时) |
| 演示数据；测试账号；怎样登录；依赖方没有我要的数据 | [种子与测试数据](docs/zh/01-conventions/07-seed-and-test-data.md)、[种子数据清单](docs/zh/03-seed-data.md) |
| 前端页面、组件库、主题、菜单、只有部分用户看得到的按钮 | [前端技术栈](docs/zh/04-foundations/04-frontend-stack.md)、[协议 20](docs/zh/06-protocols/20-frontend.md) |
| 这段业务逻辑该怎样；看哪个开源 ERP；几种做法都合理 | [参考实现](docs/zh/01-conventions/08-reference-implementations.md)、[选择方式](docs/zh/00-overview/04-selection.md) |
| 要不要用设计模式；文件或函数太长；用了模式怎样画图；要不要为性能优化、有没有更好的做法 | [AI 编码习惯](docs/zh/01-conventions/09-ai-coding.md)、[图与表的模式与协作图](docs/zh/01-conventions/04-diagrams-and-tables.md#模式与协作图) |
| 写、拆或翻译文档；组件的文档；画图与表；用图、表还是样例 | [文档规则](docs/zh/01-conventions/03-documentation.md)、[图与表](docs/zh/01-conventions/04-diagrams-and-tables.md) |
| 升版本；发布；打标签；“发版” | [开发流程与发布的版本与发布](docs/zh/01-conventions/10-development-workflow.md#版本)、`brickkit-component` 技能（`brickkit release`）；版本传播工具随重建的工具重新提供 |
| 怎样安装或部署；谁建数据库；密钥；Kubernetes；另一个环境 | `brickkit-deploy` 技能（[SKILL.md](.claude/skills/brickkit-deploy/SKILL.md)）、[部署与运行](docs/zh/04-foundations/01-deployment-and-runtime.md)、各组件 `BRICKKIT.md` 的“部署前准备” |
| 上线、备份与恢复、升级与维护窗口、告警 | [运维手册](docs/zh/05-operations/README.md) |
| 只跑一个组件；在编辑器里调试 | [开发流程与发布的真机运行](docs/zh/01-conventions/10-development-workflow.md#真机运行)、`brickkit-deploy` 技能 |
| 往项目里加、删、升级组件；某个组件起不来 | `brickkit-assemble` 技能（[SKILL.md](.claude/skills/brickkit-assemble/SKILL.md)） |
| `brickkit` 命令报错或给出 `error_code` | `brickkit-troubleshoot` 技能（[SKILL.md](.claude/skills/brickkit-troubleshoot/SKILL.md)）；参数：`brickkit <命令> --help` |
| 可能与已有决定冲突的改动；“为什么不用 React／Java／行级安全／Deny／配置中心……” | [决定记录](docs/zh/02-decisions/README.md)（先读再提议；决定优先于规范） |
| 为什么选这个数据库、消息系统、事务模型、身份格式、金额格式；替换某个底层产品 | [底层选择](docs/zh/04-foundations/README.md) |
| 重建计划；仓库复用与 `legacy/` 分支；当前进度 | `dev/rebuild/`（开发区） |
| 某个组件做什么；改一个组件 | 下面的组件表，然后该组件的 `BRICKKIT.md`（它拥有什么）与 `AGENTS.md`（怎样改它）；新设计中的边界见[边界卡](docs/zh/07-components/README.md) |

这里没有时：先看[正式文档的索引](docs/zh/README.md)，再看组件表与组件自己的 `AGENTS.md`。

## 易错点

对每个组件都成立的错误。多数看起来对、测试也能过，很久之后才出症状。规则的完整写法在链接的文档中。

| 绝不 | 症状 | 为什么 |
| --- | --- | --- |
| 不带 `LOCAL` 的 `SET ROLE`、`SET search_path`；或按角色设置超时 | 下一个借到池中连接的人把查询打到你的 schema 上，不报错不崩溃；角色级的超时在 `SET ROLE` 后不生效 | 设置要在事务内并随事务结束（[协议 14 的数据库](docs/zh/06-protocols/14-data-foundations.md#数据库)） |
| 模块代码读进程环境 | 单跑全绿；合进外壳后成员互相覆盖 schema 名与其他键，模块静默读写了别人的 schema | 一个进程只有一份环境；配置只经运行时（[合并安全](docs/zh/01-conventions/06-component-implementation.md#合并安全)） |
| 在模块里初始化进程级的东西（全局追踪提供者、日志全局配置、信号处理、默认指标注册表、框架全局模式） | 合并后最后一个初始化的赢：全部追踪落在一个服务名下，一个模块的调试模式让所有模块泄露堆栈；默认注册表在第二个模块注册时崩溃 | 用运行时提供的（[合并安全](docs/zh/01-conventions/06-component-implementation.md#合并安全)） |
| 模块里退出进程，或绕过 SDK 自建 HTTP 引擎、连接池、监听 | 一个模块的可恢复错误拖垮整个外壳；自建引擎静默丢掉请求身份、追踪、指标、访问日志、崩溃恢复、错误映射与授权 | 返回错误；一切经 SDK（[合并安全](docs/zh/01-conventions/06-component-implementation.md#合并安全)） |
| 导入另一个组件的代码、共享模型包、复制别人的生成契约代码 | 平时什么都不坏，直到要单独部署时拆不动；复制的生成代码在调用方与被调方进同一个外壳时启动即崩溃 | 能跨边界的只有 SDK、被调方发布的契约包与族契约包（[原有决定 0101](docs/zh/02-decisions/10-earlier-decisions.md#0101-组件之间禁止导入代码)） |
| 把缺席的可选依赖当作空值 | 变量根本不存在，按下标取值在启动时崩溃 | 地址访问器返回“不存在”，模块按边界卡降级（[运行时是唯一入口](docs/zh/01-conventions/06-component-implementation.md#运行时是唯一入口)） |
| 配置键以 `_ENDPOINT` 结尾，或用平台保留名 | 平台的值优先，只打一条警告；启动全绿，组件永远拿不到你的值 | 这些名字属于平台（[协议 19 的配置](docs/zh/06-protocols/19-config-secrets-registries-release.md#配置)） |
| 在健康检查里查数据库、消息系统、授权或其他组件 | 下游一次抖动让所有上游被判不健康并重启；外壳里所有成员一起重启 | 健康检查只报告进程存活（[协议 17](docs/zh/06-protocols/17-runtime-and-resources.md)） |
| 基础镜像用 `scratch` 或 distroless | 组件日志说就绪，平台永远报不健康 | 健康检查经 `/bin/sh` 与 `wget` 执行（[组件实现约定](docs/zh/01-conventions/06-component-implementation.md#健康检查与镜像)） |
| 注册没有操作定义的路由、resolver 或任务 | 这个接口完全没有授权检查，而且毫无症状 | 操作定义是路由注册的一部分，检查会发现（[安全 06](docs/zh/06-protocols/security/06-security-contracts-and-capabilities.md)） |
| 把系统面的结果原样放进用户响应，或用服务身份代替用户取受范围约束的数据 | 响应静默多出用户不该看到的行或字段 | 按身份补全不是授权的例外：替用户读取走用户面并转发原凭据，系统结果先按用户的读取契约与字段许可裁剪（[调用其他组件](docs/zh/01-conventions/06-component-implementation.md#调用其他组件)、[安全 02](docs/zh/06-protocols/security/02-trusted-identity-and-attributes.md)） |
| 资源定义缺维度，或把空部门路径当作树的根 | 新建的无部门用户看到全部部门的行；缺维度被当作“全部” | 维度必须显式声明（[安全 09a](docs/zh/06-protocols/security/09a-encoding-and-records.md)）；没有部门的主体不贡献任何部门条件（[安全 07](docs/zh/06-protocols/security/07-finite-expressions-containment-and-queries.md)） |
| 改名或复用已发布的权限键、端口、schema | 被授予旧键的角色静默失去它；依赖方与外壳全部断开；schema 改名是一次数据迁移 | 注册表身份列只追加，退役是状态（[协议 19 的注册表](docs/zh/06-protocols/19-config-secrets-registries-release.md#注册表)） |
| 前端只检查 `features` 不检查 `permissions` | 菜单看得见，点进去整页被拒 | `features` 是部署启用了什么，`permissions` 是这个用户能做什么（[协议 20](docs/zh/06-protocols/20-frontend.md)） |
| 把本项目的键写进 `component.yaml` | `brickkit lint` 与 `add` 拒绝整个清单（`MANIFEST_INVALID`、`unknown field`） | `component.yaml` 没有扩展字段，项目的键在 `assembly.yaml`（[AI 导航的标准布局](docs/zh/01-conventions/05-ai-navigation.md#组件仓库的标准布局与代码地图)） |
| 先普通 `SELECT` 再写入来认领队列行或幂等键 | 两个副本把每条发件行发两次；两个并发请求都执行 | 原子认领：`FOR UPDATE SKIP LOCKED`、`INSERT … ON CONFLICT DO NOTHING`（[协议 01 的认领与接管](docs/zh/06-protocols/01-background-work.md)、[事务与消息](docs/zh/04-foundations/03-transactions-and-messaging.md#本地事务)） |
| 金额用浮点；列表用偏移量分页 | 金额在语言之间丢精度；深分页变慢并跳行 | 十进制字符串与游标（[协议 14](docs/zh/06-protocols/14-data-foundations.md)） |
| 为了让测试通过而改测试：注释掉、加跳过、放宽断言 | 全绿而什么都没守住 | 改实现；测试真错了，单独一次提交说明为什么（[一轮红绿与铁律](docs/zh/01-conventions/02-testing-and-validation.md#一轮红绿与铁律)） |
| 改 Fork 出来的组件的 ID | 所有依赖方的地址变量随之消失 | Fork 保留组件 ID，版本照常推进（[开发流程与发布](docs/zh/01-conventions/10-development-workflow.md#发布)） |
| 外壳的成员清单、编译进来的成员与依赖锁不一致，或偏离客户的交付基线 | 要承载的成员没编译进来或版本不同：外壳启动即退出，全部成员不可用；清单与依赖锁一起偏离客户基线：镜像跑的版本与项目以为的不同，启动不报错 | 三者由工具从客户基线一起生成（[部署与运行的外壳的风险](docs/zh/04-foundations/01-deployment-and-runtime.md#外壳的风险)、[协议 17 的外壳义务](docs/zh/06-protocols/17-runtime-and-resources.md#外壳义务)） |
| 以为 `deploy.local.yaml` 会与 `deploy.yaml` 合并 | 本地模式开着时改 `deploy.yaml` 不起作用，组件集合不同时 `up` 拒绝 | 它整体取代 `deploy.yaml`；先 `brickkit local off`，或改完 `brickkit local refresh`（[真机运行](docs/zh/01-conventions/10-development-workflow.md#真机运行)） |
| 在共享变量里手写授权或身份的版本化服务名 | 下一次发布后全部受保护路由答 503 或 403，健康检查照常绿 | 写成 `$endpoint:` 引用，BrickKit 算出当前地址（[协议 19 的配置](docs/zh/06-protocols/19-config-secrets-registries-release.md#配置)） |
| Go 组件只打 BrickKit 的裸标签；主版本 2 及以上时模块路径不带主版本 | 外壳的 Go 构建取不到成员：`unknown revision`，或“module path must match major version” | Go 需要 `v` 标签，主版本 2 起还要路径中的主版本（[工程规范的版本与升级](docs/zh/01-conventions/01-engineering.md#版本与升级)） |
| 删掉标签后用同一个版本号发新代码 | Go 构建取到同号的旧代码或 `SECURITY ERROR`；BrickKit 的缓存静默给出旧的组件清单 | Go 的公共代理与校验和库、BrickKit 的缓存都按“版本不可变”工作（[工程规范的版本与升级](docs/zh/01-conventions/01-engineering.md#版本与升级)） |
| 改了代码不升版本，或原地修改已发布的版本 | 构建跳过已有镜像，容器继续跑旧代码，全绿 | 镜像标签就是版本（[开发流程与发布的版本](docs/zh/01-conventions/10-development-workflow.md#版本)） |
| 对有未提交或未推送改动的组件 `brickkit remove --force` | 强制选项连同这些改动删掉源码 | 先提交推送、注销子模块，再移除（[开发流程与发布](docs/zh/01-conventions/10-development-workflow.md#发布)） |

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

组件的文档是 `BRICKKIT.md`（译本 `BRICKKIT.<语言>.md`）：本地源里正好是这个版本时在源码目录里，否则在 `.brickkit/manifests/<id>/<version>/`；契约在 `.brickkit/artifacts/<服务名>/`（ID 和版本用 `-` 连起来，其中的 `/` 和 `.` 也都换成 `-`：`erp/backend` 1.0.0 → `erp-backend-1-0-0`）。要改某个组件，读它自己的 `AGENTS.md`。

| 组件 | 版本 | 干什么 | 文档 | 主页 |
|---|---|---|---|---|
| mdm/customer | 2.0.1 | Customer names, tax IDs, credit limits, status, contacts and billing details. | BRICKKIT.md +zh | https://github.com/brickKit/mdm-customer |
| infra/authz | 2.0.1 | Permission key catalogue, roles as plain unions, the policy bundle served at /authz/bundle, and login-time claims. | BRICKKIT.md +zh | https://github.com/brickKit/infra-authz |
| infra/notification | 2.0.0 | Takes notification intents from business components and routes them to the installed channel adapters by each user's preferences. | BRICKKIT.md +zh | https://github.com/brickKit/infra-notification |
| infra/workflow | 2.0.1 | A light task inbox; business components register approval and exception tasks, and completion is reported back by event. | BRICKKIT.md +zh | https://github.com/brickKit/infra-workflow |
| mdm/product | 2.0.0 | SKUs, categories, unit-of-measure conversions, batch and serial tracking policies, and standard costs. | BRICKKIT.md +zh | https://github.com/brickKit/mdm-product |
| integration/im-dingtalk | 2.0.0 | The DingTalk member of the IM channel family; sends work notifications for IM dispatch events and publishes the delivery results. | BRICKKIT.md +zh | https://github.com/brickKit/integration-im-dingtalk |
| infra/print | 2.0.0 | A pure rendering service; a template ID plus JSON data becomes a PDF byte stream or a ZPL command stream, with no business logic. | BRICKKIT.md +zh | https://github.com/brickKit/infra-print |
| erp/inventory | 2.0.0 | Stock balances, movements and reservations, with oversell protection; the only writer of physical stock movements. | BRICKKIT.md +zh | https://github.com/brickKit/erp-inventory |
| erp/finance | 2.0.0 | Chart of accounts, general ledger entries, receivable and payable ledgers, period locks and reconciliation. | BRICKKIT.md +zh | https://github.com/brickKit/erp-finance |
| infra/iam-casdoor | 2.0.0 | A thin adapter in front of Casdoor; issues and refreshes application tokens, serves /api/tenant/features and bridges Casdoor webhooks. | BRICKKIT.md +zh | https://github.com/brickKit/infra-iam-casdoor |
| erp/sales | 2.0.0 | Sales quotations and the order lifecycle, pricing, and the compensating orchestration that reserves stock when an order is confirmed. | BRICKKIT.md +zh | https://github.com/brickKit/erp-sales |
| crm/opportunity | 2.0.0 | Opportunity lifecycle, sales funnel and win-forecast data; publishes won, lost and stage-changed events. | BRICKKIT.md +zh | https://github.com/brickKit/crm-opportunity |
| infra/bff-mobile | 2.0.0 | GraphQL backend-for-frontend for the mobile app; a schema cut to the pages, batched loading, no business logic and no database. | BRICKKIT.md +zh | https://github.com/brickKit/infra-bff-mobile |
<!-- brickkit:managed:end -->
