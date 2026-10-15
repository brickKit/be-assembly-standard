# 规范

本目录是开发与维护时要遵守的规则：工程规范、测试与验证、文档、图与表、AI 导航。规则冲突时，决定记录（`02-decisions/`）优先于规范；规范优先于单个组件自己的约定。

| 文件 | 回答什么 |
| --- | --- |
| [01-engineering.md](01-engineering.md) | 规则归谁（平台、项目、组件）；必须重审的规范；共享语义；可配置与可定制；有限的业务设置；配置生效与密钥轮换；版本与升级；客户交付版本的维护；AI 用于开发的边界 |
| [02-testing-and-validation.md](02-testing-and-validation.md) | 三种验证；每类对象最少要证明什么；代表部署对照实验；组合变更的必测情形；证据；独立复核与冻结 |
| [validation/authorization-matrix.md](validation/authorization-matrix.md) | 权限与授权的验收反例（PA01–PA39） |
| [validation/data-and-consistency-matrix.md](validation/data-and-consistency-matrix.md) | 数据、事务与恢复的验收反例（DT01–DT30） |
| [03-documentation.md](03-documentation.md) | 文档写给谁、放在哪个区域与哪一层、组件的文档、写法、拆分、语言（D67）、与代码一起维护、检查 |
| [04-diagrams-and-tables.md](04-diagrams-and-tables.md) | 按问题选图与表；意图类与事实类；每层放什么；格式；状态迁移表、决策表与时序图的写法；怎样不过时、怎样变成测试；排查时给 AI 的运行时视图 |
| [05-ai-navigation.md](05-ai-navigation.md) | 入口怎样路由；术语表；生成的索引；从决定到代码的追踪链；组件仓库的标准布局与代码地图；每次会话读多少；局部的 AI 说明；怎样检验导航 |

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
| 后端、前端、数据、注册表、参考实现的具体约定 | 在整理协议与迁移时并入（现行规范见根 `AGENTS.md` 的约定一节） |

## 已知风险与待定

- 后端、前端、数据、注册表、AI 开发与参考实现的现行规范（英文正式文档 `docs/en/01-conventions/` 中的 02、03、05、07、09、10），按[协议 21](../06-protocols/21-verification-and-migration.md#正式文档迁移)的承接表逐节确定去处：并入本目录、并入协议，或被新设计取代。
