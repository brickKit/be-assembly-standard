# BrickEnterprise 中文设计工作区

> 状态：第 1 轮设计审查与客户展示文档细化，尚未冻结。开始日期：2026-10-12。

这里为 ERP 为主、CRM 为辅的组件化产品重新整理整体设计、底层机制、项目规范和客户选型说明。长期蓝图覆盖完整组件货架；近期实现范围围绕当前阶段的升级和部署验证确定。所有正文只用中文，专业名称和代码标识符保留通常写法。

用户已授权重新审查现有理念、组件边界、技术选择和推进计划。已有实现、旧决策和 SDK 草案都是需要核对的输入；新的推荐在审查完成前标为建议，不自动成为已批准的规则。

**持续规模前提：默认以小公司规模开发；长期根据客户业务、并发、资源、历史与监控需求，提供配置、专项组件及部署升级路线。用户暂时没有统一规模计划，已多次答复，不再重复询问统一并发量、单据量或年限，也不把缺少统一数字当作设计阻塞。**完整原话在[任务简报](work/00-brief.md#本次终局审查的规模前提重申)。

最新[终局文档审查](work/rounds/06-final-goal-document-audit.md)确认总体方向合理，但作业恢复、List／Can 语义、审计保存资格和局部投影有具体设计反例，导入／期初及引用生命周期等仍缺规格；不应认为全部底层已完整。该报告不批准实现或冻结，后续按[覆盖清单](work/03-checklist.md)收敛。

## 两条阅读路线

面向客户：先读[项目主体与全景](00-project-overview.md)，按[能力分图与替换关系](components/selection-map.md)逐层展示，再进入[替换与定制指南](replacements/README.md)比较方案、仓库、场景和部署；需要完整目录时读[组件货架与仓库](components/catalog.md)，选定组合后读[部署与资源](03-deployment-and-resources.md)。只有“已实现且对应验证通过”的选项可以作为已交付能力介绍。

面向设计与开发：先读[任务简报](work/00-brief.md)、[用户决定](work/02-decisions.md)和[交接](work/handoff.md)，再按[覆盖与验收清单](work/03-checklist.md)选择议题。每轮同时更新问题、证据、受影响文档和交接。

换到 Claude Code 或其他新会话时，直接从[未完细节与接续安排](work/04-next-steps.md)继续：包含当前候选状态、下一件具体工作、全项目 C01–C44 的细化缺口、工作区注意事项和可复制任务说明。

## 文档地图

| 文档 | 回答什么 |
| --- | --- |
| [项目主体](00-project-overview.md) | 产品目标、装配方式、长期与近期范围 |
| [组件边界与 DDD](01-component-boundaries.md) | 业务领域、限界上下文、事务边界怎样落成组件 |
| [权限与身份](02-security-and-permissions.md) | 安全边界、可替换权限方案、全路径的数据访问控制 |
| [授权求值候选规格](security/01-authorization-evaluation.md) | 完整授予的结构、读取／动作／字段公式、列表契约与 AE01–AE17 独立预期；尚未冻结 |
| [可信身份候选规格](security/02-trusted-identity-and-attributes.md) | 用户／服务／责任主体、跨组件调用模式、属性权威、凭据演进与 TI01–TI22 独立预期；尚未冻结 |
| [接受与撤销候选规格](security/03-authorization-acceptance-and-revocation.md) | 读取窗口、持久接受、严格提交屏障、恢复与 AT01–AT22 独立预期；含待测起始参数，尚未冻结 |
| [管理与任职候选规格](security/04-authorization-administration-and-appointments.md) | 完整授出上限、角色版本／批量计划、任职／交接／收紧及 AM01–AM20 独立预期；尚未冻结 |
| [共享与委托候选规格](security/05-sharing-delegation-and-impersonation.md) | 机构共享／个人委托、团队继承、只读扮演、有限再委托及 SD01–SD22 独立预期；尚未冻结 |
| [共同安全契约候选规格](security/06-security-contracts-and-capabilities.md) | 类型化结构、接口与属主、资源／副作用声明、能力准入／兼容及 SC01–SC24 独立预期；正式编码与真实验证待补 |
| [部署与资源](03-deployment-and-resources.md) | 单跑、外壳、混合、多副本的成本与验证 |
| [数据与生命周期](04-data-and-lifecycle.md) | 数据归属、共享语义、冷热分层与查询 |
| [事务与消息](05-transactions-and-messaging.md) | 用户响应、业务完成、故障恢复与 MQ |
| [工程与项目规范](06-engineering-conventions.md) | 契约、配置、发布、Fork、文档与 AI 工作边界 |
| [验证体系](07-validation.md) | 怎样证明设计、实现、替换和真实部署成立；覆盖 12 项组合变更／失败恢复场景 |
| [权限验收矩阵](validation/authorization-matrix.md) | 兼任、越权、字段、新鲜度、审批和替换的具体正反场景 |
| [推进路线](08-roadmap.md) | 设计迭代、冻结、当前升级、未来货架扩展及完成后的成果总结计划 |
| [底层推荐基线](09-foundation-baseline.md) | 全局理论复审的推荐、取舍、可以定下的原则与冻结前阻塞 |
| [数据与一致性矩阵](validation/data-and-consistency-matrix.md) | 冷热、并发、预占、增量事实、关账与恢复的 30 项具体反例 |
| [组件货架](components/catalog.md) | 原始 60 个候选条目、后续新增方向及当前状态 |
| [能力分图与替换关系](components/selection-map.md) | 从项目全景逐层展示组件，区分替换、并存、协作、策略和 Fork，并定位仓库与选型专篇 |
| [替换指南](replacements/README.md) | 选择、取舍、适配成本、共同切换流程与失败恢复 |
| [身份方案](replacements/identity.md) | Casdoor／Keycloak／通用适配的组件、仓库、场景、部署与切换 |
| [权限类型与授权组件](replacements/authorization.md) | 角色／范围／条件／字段／共享／关系怎样组合，标准／静态／OpenFGA／策略引擎路线怎样选择和替换 |
| [财务与结算选型](replacements/finance-and-settlement.md) | 存货成本、资金执行与财务账簿的责任、替换和恢复 |
| [报表与分析选型](replacements/analytics-and-reporting.md) | 内置报表、自助 BI、口径与权限适配的取舍和验收 |
| [附件与存储选型](replacements/files-and-attachments.md) | 附件业务、物理访问、纯存储门面及迁移／恢复的取舍 |
| [业务组件停用与退出](replacements/component-lifecycle.md) | 停止新业务后，旧单据、依赖和历史查阅怎样承接 |

## 状态与权威

| 状态 | 含义 |
| --- | --- |
| 用户已定 | 用户明确给出的目标或限制；来源记在工作文件 |
| 待审建议 | 已写出方案和理由，需要继续审查或用户裁定 |
| 既有实现 | 已有代码或版本；不等于适合新设计 |
| 已验证 | 有明确对象、版本、条件、命令和结果的证据 |
| 计划选项 | 需要以后实现或验证；不当作已有能力 |
| 待确认／不适用 | 缺前提，或者有明确不采用的理由 |

一份决定的当前结论只维护一处。工作记录保存来源与变化，正文解释最终方向与适用条件。知识库是中立参考，项目可以独立选择，但要写明目标、依据与代价。

2026-10-13 全局复审记录见[本轮报告](work/rounds/04-global-foundation-audit.md)。本轮审查已有全部 38 份中文设计／工作文档，新增推荐基线、数据一致性矩阵与报告；发现的理论阻塞不包装为已复现运行故障。基础版按小到中型定位，业务组合、负载、资源及延迟分开选择，具体前提已持续记录。

后续[交叉复审与外部反馈判断](work/rounds/05-cross-review-and-feedback.md)按业务链复核整体，记录真实知识库说明冲突及 PR，不将项目取舍变成平台 bug。整体成果报告等约定任务完成和实际验收后准备，当前仍未冻结，未提交成功案例。

## 收敛与文档迁移

每轮审查围绕明确问题寻找反例和证据。停止条件是关键风险闭环、覆盖与验收完整、完成独立复核并得到用户确认，不以轮数或文档数量判定。

中文稿冻结后，先核对旧文档的每一项仍需保留的内容都有新去处，再归档旧 `docs`，生成中英双语版本并更新全部现行入口、链接和检查。正式内容不得依赖归档；历史来源只留在归档工作记录和 Git 中。详细步骤见[推进路线](08-roadmap.md)。
