# 规范

本目录是开发与维护时要遵守的规则：工程规范、测试与验证、文档、图与表、AI 导航，以及组件实现、种子与测试数据、参考实现、AI 编码习惯与开发流程。规则冲突时，决定记录（`02-decisions/`）优先于规范；规范优先于单个组件自己的约定。

| 文件 | 回答什么 |
| --- | --- |
| [01-engineering.md](01-engineering.md) | 规则归谁（平台、项目、组件）；必须重审的规范；共享语义；可配置与可定制；有限的业务设置；配置生效与密钥轮换；版本与升级；客户交付版本的维护；AI 用于开发的边界 |
| [02-testing-and-validation.md](02-testing-and-validation.md) | 三种验证；每类对象最少要证明什么；实现测试的分层与节奏；代表部署对照实验；组合变更的必测情形；证据；独立复核与冻结 |
| [validation/authorization-matrix.md](validation/authorization-matrix.md) | 权限与授权的验收反例（PA01–PA39） |
| [validation/data-and-consistency-matrix.md](validation/data-and-consistency-matrix.md) | 数据、事务与恢复的验收反例（DT01–DT30） |
| [03-documentation.md](03-documentation.md) | 文档写给谁、放在哪个区域与哪一层、组件的文档、写法、拆分、语言（D67）、与代码一起维护、检查 |
| [04-diagrams-and-tables.md](04-diagrams-and-tables.md) | 按问题选图与表；意图类与事实类；每层放什么；格式；图放在哪里；状态迁移表、决策表、流程的步骤与分支、模式的角色表的写法；怎样不过时、怎样变成测试；排查时给 AI 的运行时视图 |
| [05-ai-navigation.md](05-ai-navigation.md) | 入口怎样路由；术语表；生成的索引；从决定到代码的追踪链；组件仓库的标准布局与代码地图；每次会话读多少；局部的 AI 说明；怎样检验导航 |
| [06-component-implementation.md](06-component-implementation.md) | 后端组件的代码怎样写：仓库布局与入口、运行时是唯一入口、合并安全、健康检查与镜像、权限与资源、调用其他组件、数据库、事件与契约 |
| [07-seed-and-test-data.md](07-seed-and-test-data.md) | 种子数据与测试数据：两条路径、覆盖更多场景、依赖方缺数据时、种子的归属与清除、凭据不进部署、测试数据的规则 |
| [08-reference-implementations.md](08-reference-implementations.md) | 怎样参考成熟软件：三步法、许可、记录、每个组件看哪个项目、要绕开的弱点、几种做法都合理时 |
| [09-ai-coding.md](09-ai-coding.md) | 代码怎样写才便于 AI 修改：何时用设计模式、已定的模式、长函数的注释、人要审什么、整体重写 |
| [10-development-workflow.md](10-development-workflow.md) | 改动的循环（每次改动都走）、动手之前的自问、提交、真机运行、版本与发布 |
| [11-change-recipes.md](11-change-recipes.md) | 各类改动在改动的循环每一步要注意什么：加字段、加接口、加或改事件、调用别的组件、加表、新建组件 |

**按任务找**：

| 你要做的事 | 先读 |
| --- | --- |
| 加一个配置项、一个业务设置，或决定某件事是否可以让客户配置 | [工程规范：可配置与可定制](01-engineering.md#可配置与可定制) |
| 发版、升级、给某个客户维护旧版本 | [工程规范：版本与升级](01-engineering.md#版本与升级) |
| 写测试、决定要证明什么、冻结前的复核 | [测试与验证](02-testing-and-validation.md) |
| 权限或数据一致性的反例 | [验收矩阵](validation/authorization-matrix.md)、[数据与一致性矩阵](validation/data-and-consistency-matrix.md) |
| 写或拆一份文档、写组件的文档 | [文档规则](03-documentation.md) |
| 画图、写状态迁移表或决策表 | [图与表的规范](04-diagrams-and-tables.md) |
| 写 `AGENTS.md`、代码地图、术语表，或想知道一次会话该读什么 | [AI 导航与信息定位](05-ai-navigation.md) |
| 写后端组件的代码、合进外壳 | [组件实现约定](06-component-implementation.md) |
| 准备演示数据或测试数据 | [种子与测试数据](07-seed-and-test-data.md) |
| 设计业务逻辑、几种做法都合理 | [参考实现](08-reference-implementations.md) |
| 要不要用设计模式、文件太长、重写还是打补丁 | [AI 编码习惯](09-ai-coding.md) |
| 开始做一个组件、真机运行、升版本、发布 | [开发流程与发布](10-development-workflow.md) |
| 加字段、加接口、改事件、调用别的组件、加表 | [改动配方](11-change-recipes.md) |
| 前端的写法、主题与视觉 | [前端技术栈](../04-foundations/04-frontend-stack.md)、协议 20 |
| 配置键、注册表、端口与 schema | [协议 19](../06-protocols/19-config-secrets-registries-release.md) |
