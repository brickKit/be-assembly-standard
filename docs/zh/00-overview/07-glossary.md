# 术语表

跨组件、全项目通用的概念（统一语言）。只在一个组件内使用的术语写在该组件的 `docs/design.md`；同一个词只在一层定义（[AI 导航的术语表](../01-conventions/05-ai-navigation.md#术语表)）。

**代码标识符**一列：协议中已经出现的记录、状态与字段按原样列出；其余是设计时定下的名字，组件实现时按它命名，改名必须同步本表与相关协议。容易混淆的概念各占一行，并在定义中写明区别。

## 部署与组件

| 业务叫法 | 定义 | 代码标识符 | 所属 | 所在文档 |
| --- | --- | --- | --- | --- |
| 部署 | 一个客户的一整套私有部署；一套部署就是一个客户，不存在“租户” | `deployment` | 平台 | [产品](01-product.md) |
| 组件 | 独立的仓库与版本，拥有自己的数据与契约，能单独运行 | `component`，ID 写作 `<领域>/<名字>` | 各组件 | [组件全景](03-catalog.md) |
| 外壳 | 把多个组件合进一个进程的部署形态；只合并部署，不提供共同事务或安全隔离 | `shell`、`shell.members` | 平台 | [部署与运行](../04-foundations/01-deployment-and-runtime.md) |
| 成员 | 外壳中的组件；或一个族（授权、身份）中可替换的具体实现 | `member` | 平台 | 安全 [10](../06-protocols/security/10-providers-and-member-switching.md)、[11](../06-protocols/security/11-identity-member-switching.md) |
| 客户基线 | 一个客户部署的精确组合：组件、SDK、外壳、基础资源的版本与产物摘要 | `baseline` | 交付 | [协议 19](../06-protocols/19-config-secrets-registries-release.md#客户基线与升级) |
| 入口 | 前端选择、构建与替换的单位（PC、移动、仓库终端） | `entry` | 前端 | [协议 20](../06-protocols/20-frontend.md) |
| 页面模块 | 入口内的一组页面，声明所需能力与菜单 | `page_module` | 前端 | 协议 20 |
| 启用的能力 | 这个部署实际启用了哪些组件与能力；部署时生成，不按用户变化 | `features` | 装配工具 | 协议 20 |
| 能力声明 | 组件或成员声明自己支持的能力与证据等级；装配准入据此检查 | `capability` | 各组件 | [安全 09b](../06-protocols/security/09b-capabilities-and-profiles.md) |
| 注册表 | 全局唯一的名字（组件 ID、端口、资源类型、权限键、事件类型等）；身份列只追加 | `registry/` | 项目 | 协议 19 |

## 身份与授权

| 业务叫法 | 定义 | 代码标识符 | 所属 | 所在文档 |
| --- | --- | --- | --- | --- |
| 平台主体 | 部署内稳定的身份；业务、授权、审计都引用它，换身份产品不变 | `PrincipalRef`（`kind`：`user`、`service`、`job`） | 身份 | [安全 02](../06-protocols/security/02-trusted-identity-and-attributes.md) |
| 外部身份 | 身份源中的账号，以 `(issuer, subject)` 精确映射到平台主体 | `(issuer, subject)` | 身份 | 安全 02、11 |
| 账号与员工的关联 | 哪些账号属于哪个员工；职责分离按员工判断“同一个人” | `account_employee_link` | `mdm/employee` | [安全 08](../06-protocols/security/08-state-and-change-protocol.md) |
| 任职 | 员工在某法人、部门、岗位上的一段任职；有安全含义的变化结束旧实例、生成新实例 | `appointment` | `mdm/employee` | [安全 04](../06-protocols/security/04-authorization-administration-and-appointments.md) |
| 授予 | 一份完整的授权：动作、范围（段）、条件与字段 | `grant` | `infra/authz` | [安全 01](../06-protocols/security/01-authorization-evaluation.md) |
| 段 | 授予的一个范围：每个授权维度一个原子的“与” | `segment`、`atoms` | `infra/authz` | [安全 07](../06-protocols/security/07-finite-expressions-containment-and-queries.md) |
| 资源定义 | 属主组件声明的资源类型、授权维度、字段与附件类别；只接受登记属主的提交 | `be.security.resource_definition` | 业务组件声明，`infra/authz` 保存 | [安全 09a](../06-protocols/security/09a-encoding-and-records.md) |
| 授权视图 | 组件本地用来求值的授权快照，带有效期与安全修订 | `authorization_view` | `infra/authz` 发行 | [安全 03](../06-protocols/security/03-authorization-acceptance-and-revocation.md) |
| 有界本地授权 | 默认路径：组件在视图有效期内本地判定，撤权有明确的上界 | `W_read`、`W_high` | 各组件 | 安全 03 |
| 无法证明 | 判断所需的事实不可得、过期或不相容；按保护处理，不当作拒绝后返回空 | `unprovable`、`AUTHORIZATION_UNPROVABLE` | 各组件 | 安全 03、09a |
| 管理职责单元 | 机构的授权管理边界：所管的法人、组织与人员，允许的管理动作，可授出的上限；管理者持有它，在上限内授予。易混：限定的是能授出什么，不自动限定被授予者能看到哪些行（那由资源的维度决定） | `management_unit` | `infra/authz` | [安全 04](../06-protocols/security/04-authorization-administration-and-appointments.md) |
| 生效点 | 授权组件中改变安全记录的那个本地事务；放宽只在这里检查通过才生效 | `effect_point` | `infra/authz` | 安全 08 |
| 收紧、放宽 | 收紧只减少访问，经生效点只检查谁有权收紧与最后管理员，不要证明；放宽须在生效点通过全部检查。易混：“收窄”是收紧的一种（内容缩小、身份不变） | `tighten`、`widen` | `infra/authz` | 安全 08 |
| 受保护暂停 | 记录暂不提供访问：安全处置（`security_hold`）或来源约束无法计算（`uncomputable`） | `held` | `infra/authz` | 安全 08 |
| 待恢复 | 可证明没有可用的授权管理员时部署所处的状态；只能经部署所有者的管理员恢复退出（管理员恢复进行中是另一个状态 `admin_recovery`） | `recovery_pending` | `infra/authz` | 安全 08 |
| 授权的恢复代次 | 授权成员切换、成员回退、管理员恢复与整套恢复推进的代次；易混：协议 14 的“部署恢复代次”是纪元的组成部分 | `authz.recovery` | `infra/authz` | 安全 03 |
| 委托、共享、只读扮演 | 个人委托（受托人代办）、机构共享（资源给接收人）、只读扮演（支持人员查看）；三者来源与撤销不同 | `delegation_edge`、`share`、`impersonation_session` | `infra/authz` | [安全 05](../06-protocols/security/05-sharing-delegation-and-impersonation.md) |

## 数据与一致性

| 业务叫法 | 定义 | 代码标识符 | 所属 | 所在文档 |
| --- | --- | --- | --- | --- |
| 属主 | 拥有某类数据、唯一能写它的组件 | `owner_component` | 各组件 | [领域与边界](02-domains-and-boundaries.md) |
| 发件表 | 与业务写入同事务记录要发布的事件；事件由它可靠地发出 | `outbox` | 各组件 | [协议 02](../06-protocols/02-projections.md) |
| 收件表 | 消费者按事件身份去重的记录 | `inbox` | 各组件 | 协议 02 |
| 投影 | 消费者保存的别的组件数据的副本；有版本、状态（完整、不完整、墓碑） | `projection`；`complete`、`incomplete`、`tombstone` | 消费者 | 协议 02 |
| 来源水位 | 消费者能证明“此刻之前来源的变更都已应用”的时刻；补取即探测 | `watermark`、`m_p` | 消费者 | 协议 02 |
| 发布位置 | 来源在计数行的锁内为发件行编的连续号，写作（实现实例，纪元，序号） | `publish_position` | 来源 | 协议 02 |
| 纪元 | 一个库的计数所属的阶段：（部署恢复代次，时间线）；库回退或切换时变化 | `epoch`、`current_db_epoch()` | 各库 | [协议 14](../06-protocols/14-data-foundations.md#库内计数与纪元) |
| 部署恢复代次 | 使库内容回退的操作推进的代次，权威计数在独立证据存储 | `deployment_recovery_generation` | 平台 | 协议 14、15 |
| 实现实例 | 来源或成员的一个具体实现；不同实例的计数不按数值比较 | `instance` | 来源、成员 | 协议 02、14 |
| 工作项 | 后台工作的一次执行单位，带租约、代次与副作用种类 | `work_item` | 各组件 | [协议 01](../06-protocols/01-background-work.md) |
| 结果未知 | 对外调用可能已执行、也可能没有；不重发，先查询 | `outcome_unknown`、`unknown` | 各组件 | 协议 01、10 |
| 幂等键 | 同一操作的所有尝试共用的键，对方据此去重 | `operation_id` | 各组件 | 协议 01 |
| 证据存储 | 恢复时不能丢的记录（收紧、销毁、对外终态、部署恢复代次与授权的恢复代次）；由审计组件兼任 | `evidence` | `infra/audit` | [协议 15](../06-protocols/15-backup-and-recovery.md) |
| 单号 | 给人看的编号，与记录身份分开 | `document_number` | 各组件 | 协议 14 |
| 记录身份 | 不复用的记录 ID（UUIDv7） | `id` | 各组件 | 协议 14 |

## 业务

| 业务叫法 | 定义 | 代码标识符 | 所属 | 所在文档 |
| --- | --- | --- | --- | --- |
| 业务伙伴 | 客户、供应商、员工往来、关联方等角色的共同主体 | `partner`、`partner_role` | `mdm/partner` | [主数据卡](../07-components/mdm.md) |
| 法人 | 记账与合规的单位；业务时区按法人配置 | `legal_entity` | `mdm/org` | 主数据卡、协议 14 |
| 业务日期 | 一个时刻在法人的 IANA 时区里的本地日期；单据与事件按它记账，“今天”由 SDK 按法人时区算出后作为参数传给 SQL，数据库会话的时区永远是 UTC | `bizdate`（SDK）、`/business-date`（`mdm/org`）、线协议 P5.29 | `mdm/org`（时区）、SDK | [协议 14 的时间、日历与期间](../06-protocols/14-data-foundations.md#时间日历与期间)、决定 0307 |
| 部门 | 法人下的一棵组织树；部门路径是授权的组织维度，按段比较 | `org_unit`、`dept_path` | `mdm/org` | 主数据卡、[安全 07](../06-protocols/security/07-finite-expressions-containment-and-queries.md) |
| 客户角色 | 业务伙伴在一个法人下作为客户的资格，有自己的启用、暂停、退役，与伙伴的状态分开；易混：伙伴本身没有“客户”属性，是否能卖给它看角色 | `partner_role`（`role`: `customer`） | `mdm/partner` | [主数据卡](../07-components/mdm.md#mdmpartner) |
| 资格查询 | 新单据引用一个对象之前向属主取的“此刻可用”的证据，带取证时刻，在有效期 W 内提交；每个属主各有一个（伙伴看伙伴与客户角色，产品看产品与按法人开通），法人等其他对象各自取证 | `PartnerService/CheckEligibility`（`mdm/partner`）、`ProductService/CheckEligibility`（`mdm/product`） | 各属主 | [协议 07 的资格引用的提交检查](../06-protocols/07-references.md#资格引用的提交检查) |
| 币种与汇率 | 币种的最小单位与舍入；汇率按类型与日期取不晚于该日的最近一条，单据保存汇率快照（值、日期、类型、记录身份与版本） | `currency`、`exchange_rate`、`RateService/EffectiveRate` | `mdm/currency` | 主数据卡、[协议 14](../06-protocols/14-data-foundations.md#金额数量汇率与单位) |
| 信用额度与信用占用 | 按伙伴、法人、币种的额度；已用 = 订单占用（确认的预占分支）+ 应收占用（未结清的账单），不超过额度 | `credit_limit`、`branch`（预占分支）、`receivable_exposure` | `erp/credit` | [财务卡](../07-components/erp-finance.md#erpcredit)、协议 04、05 |
| 发生时归属与当前责任 | 业务发生时的组织与现在负责的人或部门，分别保存；授权多用当前责任，指标可按发生时归属 | `occurred_org`、`current_owner` | 各业务组件 | [数据与生命周期](../04-foundations/02-data-and-lifecycle.md#发生时归属与当前责任) |
| 预占 | 订单确认时在库存与信用上保留的数量或金额，以分支表达；库存的可用量 = 在库 − 已预占；易混：出库是库存的实际减少，带分支的出库同时减在库与已预占，可用量不变 | `branch`；分支状态 `held`、`committed`、`consumed`、`released`、`expired`、`rejected`、`cancelled`（销售一侧的确认过程另有状态，见协议 04） | `erp/inventory`、`erp/credit` | [协议 04](../06-protocols/04-order-reservation.md) |
| 期初 | 上线切点之前的结果，以专门的业务类型进入，不伪造成新交易 | `opening` | 各业务组件 | [协议 16](../06-protocols/16-go-live-and-import.md) |
| 出账额度与认领 | 来源（订单、合同、项目）裁决每次可出账的额度，出账按认领模式向来源认领 | `billable`、`claim` | 来源组件、`erp/billing` | [协议 05](../06-protocols/05-billing-settlement-and-payment.md) |
| 增量事实 | 跨组件不可遗漏的事实，带产生方的序号与纪元，按事实身份去重 | `fact`、`fact_sequence` | 产生方 | 协议 05 |
| 会计事实契约 | 财务定义的共享契约：各来源按它发布会计事实，财务按过账规则键与科目映射生成凭证，不逐个认识来源 | `accounting_fact`、`posting_rule_key` | `erp/finance`（契约）；各来源 | [协议 05](../06-protocols/05-billing-settlement-and-payment.md) |
| 关账参与方 | 按参与方接口参加关账的会计事实来源：收到“请求封存”后在本地事务中封存并以增量事实回报覆盖点，提供按序号的补取；成本组件代理库存与制造参加 | `close_participant`；`unsealed`、`sealed`、`reopened` | 各来源 | [协议 06](../06-protocols/06-period-close.md) |
| 认领模式 | 一方拥有额度、另一方分次使用时的协调：先认领、再确认（在不可撤回的动作之前）、最后正式化，待确认的到期（`expired`）；出账、贷记、付款、预收放行四处共用 | `claim`；`pending`、`confirmed`、`expired`、`released`、`formalized` | 额度的属主 | [协议 05](../06-protocols/05-billing-settlement-and-payment.md) |
| 可用余额 | 未清项的未清余额减去认领中的金额；核销、冲销、调整、抵扣与新认领只能用它；订单的预收另受订单放行台账约束 | `amount − settled − pay_claimed` | `erp/finance` | 协议 05 |
| 付款认领 | 付款申请在审批前向财务的未清项认领额度，发出前确认，核销时按实付正式化；认领中的部分不能被核销、冲销或另作他用 | `payment_claim`；`pending`、`confirmed`、`formalized`、`released` | `erp/finance`、`erp/payment` | 协议 05 |
| 预收、预付 | 预收：带订单参考、尚未分配的客户资金；款到发货的交货向订单的放行台账（收款覆盖额、认领中、已放行）认领才放行。预付与员工借款分两阶段：先是只能被付款核销的申请，付款后形成已付余额，已付余额在票据匹配或报销批准时抵扣 | `prepayment`、`advance` | `erp/finance` | 协议 05 |
| 可贷记台账 | 退货单行上已出账、可开红字的额度；出账组件按认领模式认领后开出贷项 | `creditable`、`credit_claimed`、`credited` | `erp/sales` | 协议 05 |
| 收货计价依据、待定价 | 采购按收货行发布的单价与口径，是暂估成本的依据；超时未到时成本组件按政策取单价并标“待定价”；单价来源按政策价、计价依据、票据价的优先级替换 | `receipt_valuation_basis`；`pending_price` | `erp/purchase`；`erp/costing` | [协议 05b](../06-protocols/05b-inventory-costing.md) |
| 货主 | 库存维度之一：库存归谁所有（自有、寄售、存放在供应商处），与存放位置分开 | `stock_owner` | `erp/inventory` | [领域与边界](02-domains-and-boundaries.md) |
| 库存流水序号、计价序号 | 库存给每条流水编的两个连续序号，提交后在锁内分配：库存流水序号在整个库存范围内，供成本组件关账时取高点与补取；计价序号在“产品 + 法人”内，成本组件按它的顺序计价；易混：两条序列中同一产品的先后可以不同 | `inventory_seq`、`valuation_seq` | `erp/inventory` | [协议 05b](../06-protocols/05b-inventory-costing.md)、[协议 06](../06-protocols/06-period-close.md) |
| 核销 | 收付款与未清项的分配，在财务的本地事务内完成 | `settlement` | `erp/finance` | 协议 05 |
| 期间与关账批次 | 会计期间的状态与关账的协调；迟到单据顺延 | `period`；`open`、`closing`、`closed`、`reopened`、`pre_go_live` | `erp/finance` | [协议 06](../06-protocols/06-period-close.md) |
| 历史引用与资格引用 | 前者只记录当时的快照；后者要求被引用对象当前合格 | `historical_ref`、`eligibility_ref` | 引用方 | [协议 07](../06-protocols/07-references.md) |
| 扩展字段 | 客户在可扩展的实体上增加的字段，以字段 ID 为键 | `ext`、`x_<名字>` | 实体的属主 | [协议 08](../06-protocols/08-extension-fields.md) |
| 审批实例与审批依据 | 一次审批与它所针对的单据修订、依据摘要；放行由业务组件核对 | `approval_instance`、`basis_digest` | 流程管理方 | [协议 09](../06-protocols/09-approval-and-workflow.md) |
| 共享任务契约 | 流程管理方发布任务投影、统一待办订阅的契约；每种任务类型登记允许的流程管理方，由部署选定一个 | `task`、`task_type` | 流程管理方发布，`infra/workflow` 汇总 | 协议 09 |
| 一次性动作令牌 | IM 卡片按钮用的令牌，绑定任务、处理人、版本与渠道 | `action_token` | 任务所属组件 | [协议 10](../06-protocols/10-external-integration.md) |
| 对外命令 | 对外部系统的一次有副作用的调用，有业务参考号与状态 | `external_command`；`prepared`、`sending`、`unknown`、`accepted`、`manual` | 适配器 | 协议 10 |

## 数据生命周期、附件与分析

| 业务叫法 | 定义 | 代码标识符 | 所属 | 所在文档 |
| --- | --- | --- | --- | --- |
| 归档单元 | 按业务完整选出、整体转层的一组聚合 | `archive_unit`；`open`、`sealed`、`published`、`released`、`destroyed` | 数据的属主 | [协议 11](../06-protocols/11-tiering.md) |
| 保全 | 阻止清除与销毁的记录，与状态正交；由各属主保存 | `legal_hold` | 各属主 | 协议 11、12 |
| 附件类别 | 资源定义中声明的附件种类：大小、类型、敏感级别、保留类别 | `AttachmentCategory` | 父资源的属主声明 | [协议 12](../06-protocols/12-attachments-and-object-storage.md)、安全 09a |
| 访问凭证 | 父记录的属主为某用户申请、附件组件生成的短期凭证 | `access_grant` | `infra/attachment` | 协议 12 |
| 数据集 | 组件为报表、分析与搜索发布的读取契约 | `dataset` | 发布者；`ana/bi` 存储 | [协议 13](../06-protocols/13-search-reports-and-datasets.md) |
| 完整水位、授权列的新鲜度 | 数据集“截至何时完整”；受限用户查询时授权列最多容忍多旧 | `complete_watermark`、`F` | `ana/bi` | 协议 13 |

## 已知风险与待定

- 本表随组件设计补充；组件内的术语写在组件的 `docs/design.md`。
- 开发开始后，名字存在性检查核对“代码标识符”一列。
