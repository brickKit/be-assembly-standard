# 阅读来源与内容承接

> 本文件是工作记录。未来正式正文不得依赖这些本机路径、旧工作区或归档。有效语义先迁入新正文，来源留在归档／Git。

## 本地输入

| 输入 | 位置／版本 | 阅读与承接状态 |
| --- | --- | --- |
| 原始总体蓝图 | [原始设计书](../../archive/pre-v1/BrickEnterprise%20设计书.md) | 3799 行；重点读取目的、边界、货架、替换与部署推进，60 个货架条目全部列入新目录；全书其他细节仍需逐章承接检查 |
| 总阶段计划 | [阶段 06](../../dev/phase-06/plan.md) | 历史路线与当前接续分别处理 |
| 已有设计答复 | [用户答复](../../dev/phase-06/design-round/answers.md) | 新目标允许重审，旧明确答复未自动反转 |
| SDK 重设计 | [设计](../../dev/phase-06/design-round/sdk-redesign.md) | 协议、SDK、试点、迁移与外壳路线作为候选基线 |
| 实施停点 | [S1 状态](../../dev/phase-06/batches/06b-stage-b-status.md) | 区分主会话核验、通道报告与未做 |
| 现行约定／决策／底层目录 | [文档入口](../../docs/zh/README.md) | 目录和相关条款已读，全文逐议题再核对 |
| 注册身份 | [端口册](../../registry/ports.tsv)、[schema 册](../../registry/schemas.tsv) | 现有身份事实；新稿不重新发明端口或改旧行 |
| 知识库 | `/home/zhijie/Desktop/github/knowledge-base`，`16eb7a5e44088576de8368a25b01ac2420fd942d` | 读取 AGENTS、ERP／CRM、DDD、设计流程、测试、消息和冷热数据相关部分 |
| BrickKit | `/home/zhijie/Desktop/github/brickKit`，`6085c375640c19b72ea07cf29c62ef23d0c4c38e` | 读取 AGENTS、原则、组件设计和新版测试指南相关部分 |

## 第 1 轮专题来源

| 来源 | 读取范围与用途 |
| --- | --- |
| 旧 `dev/phase-06/design-round/foundations-data-platform.md` | 第 8 节，承接附件元数据、父记录授权与 SDK 存储端口 |
| 旧 `dev/phase-06/design-round/identity-permissions.md` 与 `authz-architecture.md` | 系统角色保护、最后一个管理员保护、superuser 补键相关项；用于界定 Q42 的普通业务角色范围，不重问已定系统机制 |
| 知识库 `zh/05-application-capabilities/09-files-and-attachments.md` | 元数据与处理状态相关部分，核对附件职责 |
| 知识库 `zh/12-frontend/01-frontend-architecture/00-decisions.md` 及同目录对比 | D5 与相关比较项，为 Q39／D34 比较构建时集成与运行时组合 |
| 知识库 `zh/04-identity-and-access/01-authorization/00-decisions.md` | D12，为 Q40／D35 比较集中与分级授权管理；本项目将使用权与授予上限分别设计 |
| 知识库 `zh/04-identity-and-access/01-authorization/11-delegation-and-temporary-access.md` | 速览与约束，为 Q41 区分普通业务授予与依赖委托人当前权限的代办；未将所有授予统一成撤销链 |
| 知识库 `zh/05-application-capabilities/02-workflow-orchestration/00-decisions.md` | D4，为 Q43／D38 比较组织职责审批任务的重新解析与人工改派；D6，为 Q44／D39 区分提醒／升级与申请到期，分别检查任务、业务与授权权威 |
| 知识库 `zh/01-architecture/02-architecture-styles/00-decisions.md` 与项目现行 `docs/zh/04-foundations/27-shells.md` | 架构风格 D1 及外壳范围／不变量，为 Q45 比较部署单元成本、扩展与故障；项目保持真实组件契约，不套用进程内模块协作 |
| 知识库 `zh/02-deployment-and-delivery/06-cicd/04-artifact-management/00-decisions.md` 与 BrickKit `docs/zh/09-patterns/03-test-types-and-acceptance.md` | 制品管理 D6 与 T31，为 Q47 明确无公网交付闭包与真实断网验收；不继承示例 LTS 节奏、工具名或容量数字，也不据此声明 CLI 全流程已验证 |
| 知识库 `zh/09-reliability-and-observability/01-observability/00-decisions.md` 与现行项目 `docs/zh/04-foundations/23-observability.md` | 可观测性 D2 与现行选择／状态，为 Q48 比较精简与完整部署，保留共同遥测语义及必需审计；不继承具体保存天数、序列数量或中央回传方式 |
| 当前 `components/erp/sales/component.yaml`、`components/erp/inventory/BRICKKIT.zh.md` 与 `components/erp/finance/BRICKKIT.zh.md`，知识库 `zh/05-application-capabilities/15-inventory-and-batches.md` | 销售依赖、库存与财务定位、库存速览／变体及成本段；用于 Q49／D44、Q50／D45 与 Q51 的边界比较。知识库不直接裁定本项目 WMS 是否独立；当前库存数量流水不带金额，财务库存记账金额为占位，不能套用示例认定已有真实成本实现 |
| 知识库 `zh/05-application-capabilities/14-ledger-and-accounts.md`、`zh/16-practices/01-scenarios/01-enterprise-applications/05-accounting.md` 与 `zh/16-practices/01-scenarios/03-finance-and-payments/03-reconciliation.md` | 记账、财务与清结算速览及特点，为 Q52 区分账簿权威、实际资金执行和对账。既有权限要求继续适用；未采用平台分润模型、默认结算周期、整数金额或金融业务假设 |
| 知识库 `zh/05-application-capabilities/16-pricing-and-billing.md` | 出账／补差、税与计价快照相关段，为 Q53／D48 和 Q54 参考生命周期与依据；具体来源、应收形成、组件归属和法定税务规则独立判断，不照搬周期或场景税率 |

均为局部读取，不声明全文迁移或实现通过；知识库推荐不自动成为项目约束。

## 外部一手依据

- [Martin Fowler：限界上下文](https://martinfowler.com/bliki/BoundedContext.html)：领域模型的统一语言、边界与上下文关系。
- [Microsoft：领域分析与微服务建模](https://learn.microsoft.com/en-us/azure/architecture/microservices/model/domain-analysis)：从业务能力、上下文和模型确定边界，并持续迭代。
- 2026-10-12 为 Q51 查询 [Odoo 19 库存估值](https://www.odoo.com/documentation/19.0/applications/finance/accounting/get_started/inventory_valuation.html)及[库存操作估值](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/inventory/inventory_valuation/operations_valuation.html)：库存实时估值与财务估值分工；不以 Odoo 17／18 的行为代替 19，也不照搬其会计时点为本项目规则。
- 同日查询 [Business Central 库存过账](https://learn.microsoft.com/en-us/dynamics365/business-central/design-details-inventory-posting)与[总账对账](https://learn.microsoft.com/en-us/dynamics365/business-central/design-details-reconciliation-with-the-general-ledger)：数量／价值分录及总账集成；[Dynamics 365 SCM 成本管理](https://learn.microsoft.com/en-us/dynamics365/supply-chain/cost-management/cost-management-home-page)：成本功能范围与工作区。只核对相关功能文档，未核对源码、采购授权或独立部署能力。
- 同日查询 [Microsoft Cash and bank management](https://learn.microsoft.com/en-us/dynamics365/finance/cash-bank-management/cash-bank-management)：银行账户、银行对账及收付款相关功能入口，为 Q52 提供功能划分参考，不据此认定独立微服务是行业统一要求。
- 同日查询 [Microsoft Accounts receivable](https://learn.microsoft.com/en-us/dynamics365/finance/accounts-receivable/accounts-receivable)与 [ERPNext Sales Invoice](https://docs.frappe.io/erpnext/sales-invoice)：应收／商业发票功能、业务来源和账务关系；ERPNext 重点读取来源、服务／项目及提交效果段。用于 Q53 比较独立出账与财务内部模块，不查询或承诺特定国家的税务合规。
- 同日查询 [Microsoft Tax Calculation](https://learn.microsoft.com/en-us/dynamics365/finance/localizations/global/global-tax-calcuation-service-overview)与[Electronic invoicing](https://learn.microsoft.com/en-us/dynamics365/finance/localizations/global/gs-e-invoicing-service-overview)：计算数据流、配置版本／适用范围与电子票据转换、签名、提交／响应功能；为 Q54 比较独立能力与地区一体组件，不照搬其配置、地区清单或云端服务。电子开票文档明确不支持本地部署，本项目没有采用或验证该服务。
- 同日查询 [Microsoft 应付发票匹配](https://learn.microsoft.com/en-us/dynamics365/finance/accounts-payable/accounts-payable-invoice-matching)及 [ERPNext Purchase Invoice](https://docs.frappe.io/erpnext/purchase-invoice)：应付匹配、供应商票据的来源、直接录入、应付与账务关系；ERPNext 重点读取登记、来源与提交效果段，为 Q55 比较财务内部与独立收票／匹配。知识库财务场景读取架构决策路径的应付／记账核心条目；不照搬模块化单体、库存写入或负债确认时点。
- 同日为 Q56 核对知识库财务场景的准则／账套问题，以及 [SAP 并行会计 2608](https://help.sap.com/docs/SAP_S4HANA_CLOUD/89d896ca9cd64318b1667df5ec00e4b2/fce0d25320cd4608e10000000a174cb4.html?locale=en-US&state=PRODUCTION&version=2608.500)相关用途段；搜索还读到并行账簿与附加科目的不同路径，不照搬厂商数量／配置。另读 [Oracle 24A 的法人特定辅助账簿说明](https://docs.oracle.com/en/cloud/saas/readiness/erp/24a/fins24a/24A-fin-wn-f31143.htm)了解不同会计表示；这是旧版本功能资料，未作为当前支持承诺，所链通用指南重定向到 26D 目录，未据目录标题认定已读正文。
- 同日为 Q57 核对原蓝图分析货架与报表负载规则、旧设计轮答复／决定，以及知识库 `12-bi-reporting.md` 的自助程度／交付分支和 `05-metrics-and-reporting.md` 的口径、缓存、订阅及迁移内容。查 [Metabase 全应用嵌入](https://www.metabase.com/docs/latest/embedding/full-app-embedding)与 [Superset 安全配置](https://superset.apache.org/admin-docs/security/)的官方正文，关注权限接入、许可条件和数据库安全边界；Superset 页面标为 Next，仅作功能／风险参考，正式选型必须固定发行版本复核。旧 `/docs/security/` 未返回正文，没有作为已读内容依据。未指定产品、购买许可或接入客户数据。
- 同日为 Q58 核对旧数据平台专题 §8 的组件桶／凭据、附件授权与 SDK 端口，及现行 0106 对基础资源的定位；知识库按应用能力 D8 路由，读文件专题速览、访问控制／删除及检查清单。核对 [Amazon S3 预签名 URL](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html)的重复使用、同 key 替换和凭据／到期语义，用于上传内容身份与撤权风险审查；未把 AWS 特定能力推定为 RustFS 已验证，未修改知识库或存储资源。
- 同日为 Q59 检查新旧问题／决定中的停用与历史条目，区分任职／角色停用与业务组件退出；查知识库说法／名字／决定索引，再读遗留系统现代化入口、D4 与迁移文章的速览、取舍及检查清单。项目允许维护窗口，不照搬该案例的持续同步或时间预算。[SAP 2023 Retention Warehouse 退役文档](https://help.sap.com/docs/SAP_S4HANA_ON-PREMISE/8dc87761757b490eb33ef3f608c2f4de/295cb0bdba784096bef0f3fe53924f9f.html?locale=en-US&state=PRODUCTION&version=2023.latest)的官方检索正文用于证明独立历史查阅是另一功能路径，未查询其当前价格／许可或采用其架构，也未认定达到具体法律要求。
- 同日为 Q60 核对旧 F12／P4、现行 0302 已有外部集成身份与契约新大版本／弃用路线，不重复询问。知识库按交付入口路由，读版本维护、多版本并存及客户部署的安全回移与检查清单；项目允许完整 Fork、正常联网交付，不采用该场景的统一核心禁止 Fork、季度／月数或强离线示例。查 [SemVer 2.0.0](https://semver.org/)官方正文与 [PostgreSQL 版本政策](https://www.postgresql.org/support/versioning/)官方检索正文，关注新功能与修复线及支持范围的区分，未借供应商周期设定本项目支持年限或建立维护分支。
- 同日维护决定确认后，核对新权限正文与旧 A5／F6 方向，查知识库授权入口、D14、权限测试／审计专题的速览、`Scope`／`Check` 集合一致性、坏变体与检查清单；再读 [OWASP 授权指南](https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html)每请求校验、业务需求优先和配置验证段。用于权限 36 项设计矩阵，不照搬性能／撤权数字、RLS 或错误映射，不声明全部 SDK／入口已通过。

具体产品、版本、性能和合规判断在专题深化时查官方资料与实际实现；本轮候选表不声称供应商产品已过本项目验收。

## 2026-10-13 全局复审来源增量

- 已有 38 份 tempDocs 逐篇理论复核；现行 `docs/en` 85 份清单／约束索引核对，重点读数据库、生命周期、本地与跨组件事务、0505–0507、租户、RLS 与内部 RPC 相关正文。全量旧书／正式规则迁移仍未完成，具体读取与反例在[复审报告](rounds/04-global-foundation-audit.md)。
- 知识库入口和冷热对比／D1–D9、事务对比／D1–D6、分布式事务 D1–D6；Saga 编排／补偿／持久状态／参与者章节、TCC 异常及检查项。作为中立参考，不机械承接月分区、统一删除窗口或共享 schema 事务。
- 查询 [PostgreSQL 18 分区](https://www.postgresql.org/docs/18/ddl-partitioning.html)、[隔离级别](https://www.postgresql.org/docs/18/transaction-iso.html)、[角色](https://www.postgresql.org/docs/18/sql-createrole.html)与锁／RLS 官方说明，用于唯一性、局部隔离及外壳角色边界；不据此要求项目立刻升级 PostgreSQL。
- 查询 [NATS 官方消费者文档源码](https://github.com/nats-io/nats.docs/blob/master/nats-concepts/jetstream/consumers.md)的 MaxDeliver／消息保留和 [JetStream](https://docs.nats.io/concepts/jetstream)确认机制；旧网址部分重定向到学习入口，不将重定向目录当完整原正文。
- 查询 [DuckDB Parquet](https://duckdb.org/docs/stable/data/parquet/overview)、[Iceberg spec](https://iceberg.apache.org/spec/)快照／原子元数据提交相关检索正文、[OpenFGA 一致性](https://openfga.dev/docs/interacting/consistency)。仅验证技术机制与风险，不认定产品提供全部授权／恢复保证，不指定新产品或仓库。
- 硬件只读 `lscpu`、`free -h`、`lsblk`、`df -h .`；最小 Python 反例按旧分隔编码重现，不是实际归档实现测试。两者的证据边界见 evidence。

再次闭合检查的局部来源：知识库 `zh/10-security/03-data-security/00-decisions.md` 的秘密管理 D8，以及 `zh/02-deployment-and-delivery/06-cicd/06-release-strategies/00-decisions.md` 的 D10–D11，用于轮换与切换阶段的独立判断，不继承默认密钥服务器、配置中心、示例周期或持续在线要求。查询 [PostgreSQL 18 数据库管理概述](https://www.postgresql.org/docs/18/manage-ag-overview.html)核对实例／数据库层级、连接目标和共同 WAL／恢复边界；查询 [RFC 7517](https://www.rfc-editor.org/rfc/rfc7517.html)核对 JWK Set／密钥标识，不由该规范推出项目轮换时限。仅查数据库备份索引未作为完整恢复协议正文证据。

## 2026-10-13 交叉复审来源

2026-10-13 反馈判断增量：按名字索引读取知识库分布式事务对比、D4 与 TCC 文章的速览、全局状态、参与者模型／接口、超时、误区及清单，核对入口与正文相反规则；查本地 feedback 和 GitHub 开放 PR 去重。已 fetch 的知识库 `origin/main` 仍为 `16eb7a5e`，反馈独立分支为 `3b0f3920`。BrickKit `6085c375` 的中文入口、组件设计、外壳开发、配置地址及注入／外壳相关源码和测试用于责任判别；3 项注入／JSON 测试已实际执行，不证明真实 gRPC 或整套部署。没有对供应商行为作新的未经核对的产品承诺。

## 原始章节承接表

| 原始内容 | 新正文去处 | 当前程度 |
| --- | --- | --- |
| 目的、按需装配、定制 | 项目主体、替换指南 | 目标已承接 |
| 总体架构、域地图、货架 | 边界与货架目录 | 全量名称与范围已承接，职责要重新审 |
| 契约、资产、Fork、数据消费 | 工程规范、边界、替换指南 | 范围已承接，旧字段与版本要求需核对 |
| 同步、事件、分布式流程 | 事务与消息 | 必须逐业务流程深化 |
| 基础设施细节、权限 | 权限与替换专题 | 目标已承接，具体语义待审 |
| 观测、AI 工作流、仓库治理 | 工程规范、验证、支撑能力 | 覆盖已登记，规则全文待承接 |
| 生命周期、冷热与查询 | 数据与生命周期 | 关键边界已写，全部表规则待审 |
| 语言、栈、前端 | 工程规范、运行／前端选择 | 原始与现行差异已标，需逐项裁定 |
| 外壳与部署演进 | 部署与资源、验证、路线 | 目标和风险已写，矩阵与预算待完成 |
| 图、登录、事件沙盘与客户示例 | 新正文对应图与业务故事 | 初步概念图已写，详细时序和样板待补 |

没有“全文已迁完”结论。正式切换前必须将此表细化到每项有效规则，并通过链接与归档边界检查。
