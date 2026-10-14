# 设计地图

> 完整设计由哪些文档组成、每份到了什么状态、还缺什么设计。每一轮复查从这里开始，结束时更新这里。任务先后顺序在[接续清单](04-next-steps.md)，用户决定在[决定台账](02-decisions.md)，问题在[问题台账](issues.md)。

## 状态的含义

| 状态 | 条件 |
| --- | --- |
| 未写 | 需要的设计还没有文档，只在下文“仍待设计的部分”或问题台账中登记 |
| 候选 | 已写成，但自上次重大修改后没有经过独立的整体复查 |
| 已复查 | 一次独立的整体通读（另一会话或另一视角）没有发现阻塞问题；遗留问题已登记 |
| 可冻结 | 已复查；所覆盖 C 项没有未关闭的阻塞问题；需要用户裁定的点已裁定；验证方式已写明 |

文档修改后，状态回到“候选”，直到下一次复查。“可冻结”是进入正式文档迁移（[路线](../08-roadmap.md#中文稿与正式文档的切换)）和开发的前提。

## 一轮复查怎么做

1. 从本页选定范围：一组文档，或一个横切主题（例如“全部文档里的权限出口”）。
2. 完整通读范围内的文档，对照决定台账与相关 C 项；发现的问题登记到问题台账，写清在哪、为什么、影响什么。
3. 修改文档；同一份文档被多次增补、已经难读时，整体重写而不是继续追加。
4. 更新本页：状态、最近整体复查、遗留问题；“仍待设计的部分”中已写成的条目改成文档行。
5. 在 `rounds/` 写一份本轮记录，在[证据记录](evidence.md)写一段摘要（读了什么、改了什么、跑了什么）。

每轮收尾自问：

- 本轮新发现和实际证据是否已记录，而不是只重述认可？
- 修改是否影响别的上下文、权限、数据、部署、替换说明或验收？
- 有无将建议、实现、测试与容量承诺混淆？
- 有无新增多处同一规则；是否需要整体重写？
- 所有重要信息是否已进入新正文，或明确列为尚待承接？

## 设计文档

> 2026-10-13 作者对全部文档做了一轮横切复查（[rounds/09](rounds/09-author-cross-review.md)），不计为独立复查。2026-10-14 第一轮独立复查（[rounds/10](rounds/10-independent-review.md)）：复查后没有再修改、且复查者认为可标“已复查”的文档已标“已复查”；2026-10-14 第二轮独立复查（[rounds/11](rounds/11-second-independent-review.md)）：其结论中可标“已复查”、且本轮之后只做了一般项修正的文档已标“已复查”；安全 03、04、10，协议 02、15，权限主文档与基础能力卡按重要发现（I52–I57）修正后仍为“候选”，等第三轮复查。2026-10-14 第三轮独立复查（[rounds/12](rounds/12-third-review.md)）：安全 04 与权限主文档标“已复查”（累计 55 份）；安全 03、10，协议 02、15 与基础能力卡按重要发现（I59–I61）修正后仍为“候选”，等第四轮只看这些改动的聚焦复查。2026-10-14 第四轮聚焦复查（[rounds/13](rounds/13-fourth-review.md)）：协议 05 与权限主文档维持“已复查”；安全 03、10，协议 02、15 与相关卡片按重要发现（I63–I66）修正后仍为“候选”，等第五轮只看 IU01–IU06 的修正。2026-10-14 第五轮聚焦复查（[rounds/14](rounds/14-fifth-review.md)）：协议 14 与检查 34 确认无新问题；协议 02、15，安全 03、10，D64 与相关卡片按重要发现（I67–I70）修正后仍为“候选”，等第六轮只看 IV01–IV04 的修正。2026-10-14 第六轮聚焦复查（[rounds/15](rounds/15-sixth-review.md)）：核心机制稳定，故障与恢复的边缘按用户裁定 D65 与复查建议简化（I71–I76）；协议 02、05、06、15，安全 03、10 与相关卡片仍为“候选”，等第七轮只看这次简化。2026-10-14 第七轮聚焦复查（[rounds/16](rounds/16-seventh-review.md)）：问题仍在收敛，按两条总规则（协议 14 的库内计数与纪元、协议 15 的高可用切换中不能丢的写入）修正（I77–I81）；相关文档仍为“候选”，等第八轮只看这两条规则及其引用。2026-10-14 第八轮聚焦复查（[rounds/17](rounds/17-eighth-review.md)）：重要项未收敛；按用户裁定 D66（高可用整体同步，底层预留、后期启用）与作者的计数全量盘点修正（I82–I85）。边界卡中的领域卡未单独列在本表，随目录页一起记录。

| 文档 | 回答什么 | 主要覆盖 | 状态 | 最近整体复查 | 遗留问题 |
| --- | --- | --- | --- | --- | --- |
| [工作区入口](../README.md) | 阅读路线、文档索引 | C41 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | — |
| [项目主体](../00-project-overview.md) | 产品是什么、装配全景、设计原则 | C01 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I01 |
| [组件边界](../01-component-boundaries.md) | 边界方法、数据归属、业务伙伴、组织与员工、库存与仓储、销售类型 | C01–C03、C05 | 候选 | rounds/06 | I02、I03、I26、I31 |
| [权限主文档](../02-security-and-permissions.md) | 权限语义、执行推荐、管理与任职、审计范围 | C06–C11、C35 | 已复查 | rounds/06、rounds/12 | I09、I19、I28、I29、I62 |
| [部署与资源](../03-deployment-and-resources.md) | 部署形态、规模阶梯、外壳风险、维护窗口、网络前提 | C31–C34 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I16、I24 |
| [数据与生命周期](../04-data-and-lifecycle.md) | 数据归属、库选择、冷热分层、跨层查询、灾难恢复 | C12、C17–C23、C37、C44 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I17、I20、I21、I25、I31、I33 |
| [事务与消息](../05-transactions-and-messaging.md) | 本地事务、预占、跨组件协调、消息运输、用户响应 | C13–C16、C26 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I15、I22、I23、I27、I30 |
| [工程规范](../06-engineering-conventions.md) | 规则归属、定制层级、配置与密钥、版本与客户维护、AI 文档 | C04、C29、C39、C41 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I26、I34 |
| [验证体系](../07-validation.md) | 证据规则、代表性部署实验 | C30、C40 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I11、I13、I16 |
| [路线](../08-roadmap.md) | 范围线、切换正式文档的步骤 | C42 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | — |
| [底层基线](../09-foundation-baseline.md) | 各方面的推荐组合与冻结条件 | 全部 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I19–I26 |
| [货架清单](../components/catalog.md) | 长期货架条目、仓库与实现状态 | C01 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | — |
| [选择关系图](../components/selection-map.md) | 能力分图、单选／多选／协作的标注 | C01、C05、C41 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | — |
| [全货架边界卡](../components/README.md) | 每个组件的边界卡（11 个领域文件）、新增与退役身份、当前重建范围候选、组合闭包、五项检查 | C01–C05 | 已复查（基础能力卡的 IAM、授权、审计、附件四张与员工卡、组织卡在第三、四轮后修正，随第五轮复查） | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正）、[rounds/13](rounds/13-fourth-review.md) | I01–I06、I26 |
| [选型指南](../replacements/README.md) | 选配与替换的共同协议 | C05 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | — |
| [报表与分析](../replacements/analytics-and-reporting.md) | 内置报表与自助 BI | C25 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | — |
| [授权选型](../replacements/authorization.md) | 授权模型与成员方案 | C07–C11 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I18 |
| [业务与渠道](../replacements/business-and-channels.md) | 业务定制、算法差异、渠道组合 | C04、C05、C28 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I05、I06 |
| [组件生命周期](../replacements/component-lifecycle.md) | 停用、历史查阅与退出 | C05、C21 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | — |
| [数据与存储选型](../replacements/data-and-storage.md) | 数据库、对象存储与冷查询的选择 | C12、C22、C23 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I17 |
| [附件与存储](../replacements/files-and-attachments.md) | 附件职责与 SDK 存储适配 | C24 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I04 |
| [财务与结算](../replacements/finance-and-settlement.md) | 成本、收付款、出账、税务、票据、账簿 | C13、C17、C18、C28 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I23 |
| [前端](../replacements/frontend.md) | 按入口选择与构建发布 | C38 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I07 |
| [身份](../replacements/identity.md) | 身份方案与替换 | C06 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I14 |
| [消息](../replacements/messaging.md) | 运输适配器比较 | C15 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I22 |
| [运行与部署选型](../replacements/runtime-and-deployment.md) | SDK、外壳与运行方式 | C30–C33 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I11、I12 |
| [支撑能力](../replacements/supporting-capabilities.md) | 边缘、观测、审批、通知、打印 | C27、C35 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I29 |
| [安全 01 求值](../security/01-authorization-evaluation.md) | 完整授予、读取／动作／字段、三类列表 | C08、C09 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I18、I28 |
| [安全 02 身份](../security/02-trusted-identity-and-attributes.md) | 可信身份、调用模式、属性来源、凭据 | C06、C16、C36 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I14、I19 |
| [安全 03 时间](../security/03-authorization-acceptance-and-revocation.md) | 默认有界本地授权与可选严格路径（持久接受、提交屏障）、输出期限、内容水位 | C10 | 候选（2026-10-13 按 D57 整份改写，未经独立复查） | 写成时自查；参考模型已运行 | I19 |
| [安全 04 管理](../security/04-authorization-administration-and-appointments.md) | 管理上限、角色版本、任职生命周期 | C07、C11 | 已复查 | rounds/12 | I19 |
| [安全 05 共享与委托](../security/05-sharing-delegation-and-impersonation.md) | 共享、委托、扮演 | C08、C11 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | — |
| [安全 06 共同契约](../security/06-security-contracts-and-capabilities.md) | 共同结构、接口属主、能力准入 | C06–C11、C16、C30、C36 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I18、I19、I28 |
| [安全 07 有限表达](../security/07-finite-expressions-containment-and-queries.md) | 有限原子、包含证明、求交、查询编译 | C07–C09、C11 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I18、I19 |
| [安全 08 状态与变更](../security/08-state-and-change-protocol.md) | 通用生命周期、生效点、有效段 = 记录 ∩ 来源、影响闭包、受保护操作、最后管理员、安装认领、恢复、紧急访问 | C07、C10、C11 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I19 |
| [安全 09 正式编码](../security/09-encoding-and-profiles.md) | 基本类型、规范编码与摘要、全部安全结构的字段表、视图核验、错误分类、能力目录、profile | C06–C11、C16、C30、C36 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I18、I19、I20 |
| [安全 10 成员能力与切换](../security/10-providers-and-member-switching.md) | 记录为权威、引擎为索引；外部产品已核实能力；能力矩阵；静态成员；成员切换协议 | C05、C07–C11 | 候选（未经独立复查） | 写成时自查；等价核验模型已运行 | — |
| [协议 01 后台工作](../protocols/01-background-work.md) | 工作项状态、认领与接管、副作用种类、死信与暂停、cron 时间槽与夏令时、补跑与水位、清理资格 | C26、C14、C32 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I27 |
| [协议 02 本地副本](../protocols/02-projections.md) | 投影用途、行状态、来源契约、接收规则、取回、对账、回填、墓碑 | C14、C25、C30 | 候选（未经独立复查） | 写成时自查；投影修复模型已运行 | I30、I22 |
| [协议 03 审计保存](../protocols/03-audit-durability.md) | 必需审计、第一落点、读取与拒绝、转运回执、删除资格、积压、装配 | C35、C14 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I29 |
| [协议 04 订单预占](../protocols/04-order-reservation.md) | 参加方、分支状态机、命令、确认过程、同步与恢复、取消与修订、消耗 | C13、C14 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I23 |
| [协议 05 出账核销成本](../protocols/05-billing-settlement-and-costing.md) | 增量事实规则、出账认领、信用转换、核销、成本、应付匹配 | C13、C14、C17、C18、C28 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I23、I22 |
| [协议 06 期间关闭](../protocols/06-period-close.md) | 关账批次、封存与覆盖、迟到单据、重开 | C14、C17 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I23 |
| [协议 07 跨组件引用](../protocols/07-references.md) | 两类引用、声明、生命周期、资格检查、合并与别名、解析结果、修复、擦除 | C44、C03 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I31 |
| [协议 08 扩展字段](../protocols/08-extension-fields.md) | 可扩展实体、字段定义、存储、演进、边界、出口、配额 | C20 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I33 |
| [协议 09 审批与流程](../protocols/09-approval-and-workflow.md) | 三方分工、审批依据、流程选择、决定提交、放行核对、修订重审、版本迁移、重分配、截止、待办、引擎契约 | C27 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | — |
| [协议 10 外部集成](../protocols/10-external-integration.md) | 适配器、对外命令、回调、事实、对账、凭据、通知、打印、开放接口 | C28、C27 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | — |
| [协议 11 冷热转层](../protocols/11-tiering.md) | 转层资格、单元目录、封存与写屏障、复制校验发布、释放、保全与销毁、跨层读取、解冻、恢复核对 | C22、C23 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I17、I21 |
| [协议 12 附件与对象存储](../protocols/12-attachments-and-object-storage.md) | 对象属主与凭据、上传与最终键、扫描、下载授权、清除与保全、对账、后端更换 | C24 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I04 |
| [协议 13 搜索报表与数据集](../protocols/13-search-reports-and-datasets.md) | 数据集、指标、水位、授权、导出与订阅、自助 BI、搜索、资源隔离 | C25 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | — |
| [协议 14 数据基础](../protocols/14-data-foundations.md) | 数据库使用、身份与唯一、单号、时间与期间、金额与单位、游标与筛选、迁移与兼容 | C12、C17–C19、C21 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | — |
| [协议 15 备份与恢复](../protocols/15-backup-and-recovery.md) | 恢复组、证据存储、发件表保留、恢复流程、局部修复、高可用、演练 | C37 | 候选（未经独立复查） | 写成时自查；一致性恢复模型已运行 | I25 |
| [协议 16 客户上线](../protocols/16-go-live-and-import.md) | 导入机制、期初事实、批次激活、切点、试迁移与签字 | C43 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I32 |
| [协议 17 运行与资源](../protocols/17-runtime-and-resources.md) | 资源声明、外壳预算、过载与故障、启停、多副本、引擎矩阵、观测、容量测量、维护升级 | C31–C35 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I16、I24 |
| [协议 18 SDK 与一致性](../protocols/18-sdk-and-conformance.md) | 组件协议、套件与报告、语义向量、官方 SDK、准入、版本对应 | C30 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | — |
| [协议 19 配置密钥注册表发布](../protocols/19-config-secrets-registries-release.md) | 配置、密钥轮换、注册表、版本与产物、供应链、客户基线 | C29、C36、C39 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | I34、I08、I26 |
| [协议 20 前端](../protocols/20-frontend.md) | 入口与模块、会话、显示规则、断网草稿、旧客户端、多语言、浏览器安全 | C38 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I07 |
| [协议 21 验证映射与迁移](../protocols/21-verification-and-migration.md) | 证据四层、预期登记、模型清单、C 项验证映射、冻结报告、正式文档迁移 | C40–C42 | 已复查 | [rounds/11](rounds/11-second-independent-review.md)（第二轮；一般项已修正） | I13、I34 |
| [权限验收矩阵](../validation/authorization-matrix.md) | PA01–PA36 | C06–C11 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | — |
| [数据与一致性矩阵](../validation/data-and-consistency-matrix.md) | DT01–DT30 | C12–C23、C37 | 已复查 | [rounds/10](rounds/10-independent-review.md)（第一轮独立复查） | — |

## 仍待设计的部分

> 2026-10-13 重写：原“待补的设计”表（从接续清单迁入）的条目已由安全 01–10 与协议 01–20 写成候选，各自的剩余事项并入下文 C 项表的“剩余”。本节只列仍没有设计文档的部分。

| 部分 | 内容 | 去处 |
| --- | --- | --- |
| 逐组件的声明 | 资源定义（操作、字段、维度、可扩展性）、引用字段、数据类别与保留类别、数据集、导入模板与期初类型、资源预算、关键字段与流程、对外适配器的能力声明 | 随边界卡与各组件设计；协议给出了声明的格式 |
| 依赖实验的取值 | 默认部署组合与引擎、资源与容量、冷读取与中文检索方案、备份工具与恢复时间、扫描引擎 | 代表部署实验（D41，接续清单第 8 项） |
| 正式交付前的承诺 | 支持期与并存基线数、修复时效、各地区税务与单号的法定要求 | 正式交付前与用户确认 |

### 安全候选尚未证明的内容

> 2026-10-13 从接续清单迁入。

| 已形成的候选 | 本次细化内容 | 尚未证明 |
| --- | --- | --- |
| [完整授予与求值](../security/01-authorization-evaluation.md) | 读取、动作、字段、三类列表，AE01–AE17 | schema／API、包含及查询生成、真实字段出口和 SDK 等价 |
| [可信身份与属性](../security/02-trusted-identity-and-attributes.md) | 用户／服务／履职／代办、来源、凭据，TI01–TI22 | 真实凭据签发／轮换、入口保护、属性新鲜度、IAM 已知问题修复 |
| [接受与撤销时间](../security/03-authorization-acceptance-and-revocation.md) | 默认有界本地授权（有效期从发出核验请求按单调时钟起算、事务内截止检查、撤权上界、authz 不可用的分级行为）与可选严格路径，AT01–AT55；有界本地授权模型已运行 | 操作分类与路径声明的编码、视图核验接口、真正原子守卫、依赖域闭包、B 档参与者完整登记与恢复、参数实测 |
| [管理与任职](../security/04-authorization-administration-and-appointments.md) | 管理上限、角色绑定、批量计划、任职与交接，AM01–AM20 | 包含算法／预算、完整管理状态机、模板／操作清单、实际联动 |
| [共享／委托／扮演](../security/05-sharing-delegation-and-impersonation.md) | 机构共享／个人来源、派生段、有限链、会话／副作用／通知，SD01–SD22 | 正式源类型／资格证明和链编码、共享治理、profile／通知落点及真实验收 |
| [有限表达／包含／查询](../security/07-finite-expressions-containment-and-queries.md) | 段的有限原子与规范化、逐维包含与单维拆分、委托求交、查询编译与命中位图字段、预算，FX01–FX24；参考模型已运行 | 关系原子与投影、正式编码、三语言向量、PostgreSQL 与预算实测 |
| [状态与变更协议](../security/08-state-and-change-protocol.md) | 通用生命周期与生效点、有效段 = 记录 ∩ 来源、闭包只记账、受保护操作与部署所有者确认、最后管理员、安装认领、恢复、紧急访问，CP01–CP24；参考模型已运行 | 逐字段编码、部署所有者凭据的形式与保管、身份系统不可用时紧急访问的认证路径、profile 默认值 |
| [正式编码与能力 profile](../security/09-encoding-and-profiles.md) | 基本类型与规范形式、RFC 8785 摘要、引用、定义、段与原子、各类记录、变更协议、视图核验与随机数、严格路径、错误分类、能力目录与准入、profile，EN01–EN20；编码检查已运行 | 生成 protobuf 与 JSON Schema、三语言共同向量、视图分片的负载实测、reason 最终命名、能力命名与版本规则 |
| [成员能力与切换](../security/10-providers-and-member-switching.md) | 记录为权威、引擎为索引；六种外部产品的已核实能力；能力矩阵；静态成员；切换协议与摘要等价核验，PV01–PV31；模型已运行 | 运行中成员的黑盒一致性套件、`related` 原子到引擎模型的映射、策略引擎可翻译子集的正式定义、静态记录文件签名、身份成员的切换协议 |
| [共同结构／接口／能力](../security/06-security-contracts-and-capabilities.md) | 类型化记录、接口属主、资源／副作用、能力路径与兼容，SC01–SC24 | 逐字段正式编码、有限算法／预算、状态／DDL／profile、精确版本矩阵及真实证明 |

以上 AE／TI／AT／AM／SD／SC／FX／CP／EN／PV 都是验收预期，没有运行 SDK、真实数据库或业务链路。`work/checks/` 中的参考模型只演算文档中的协议与坏变体，不能叫合规通过。

## 覆盖要求 C01–C44

写清对象与能力、设计结果、最少要证明的行为、责任层、命令／环境、证据状态、不适用理由或剩余问题。规范存在、测试存在、执行通过分别维护；一行不能只因已有同名测试就完成。

> 2026-10-13 重写“当前状态”列：每行改为“已定方向；设计在哪里；剩余”，去掉被后来协议取代的旧表述；改写前的原文见[证据记录](evidence.md)本日“设计地图重写”一段所述的提交。

| 编号 | 方面／对象 | 必须设计或证明的结果 | 当前状态 | 主文档 |
| --- | --- | --- | --- | --- |
| C01 | 长期货架与客户组合 | 完整业务范围、最小组合、选配闭包与缺件行为 | 原始 60 条目已承接；服务销售可不装库存（D44）；每个组件的边界卡与客户组合闭包见[全货架边界卡](../components/README.md)。剩余：能力声明格式在组件设计时细化；当前重建范围随第 8 项计划确认 | [主体](../00-project-overview.md) |
| C02 | DDD 与组件边界 | 术语、数据、变化与不变量对应明确；边界可调整 | 方法与热点已写；库存核心与复杂仓储分开（D45）；边界卡写明数据、不变量与依赖，五项检查结论见边界卡目录页。剩余：契约细化随组件设计 | [边界](../01-component-boundaries.md) |
| C03 | 主数据归属 | 业务伙伴／客户供应商角色／联系人／产品／法人／组织／人员归属和合并 | 伙伴、正式联络资料、组织与员工、人工合并已定（D04–D06、D20–D22）；引用、合并与别名见[协议 07](../protocols/07-references.md)；主数据边界卡（[mdm](../components/mdm.md)）给出 `mdm/partner`、`mdm/employee`、`mdm/currency`。剩余：各主数据的详细模型随组件设计 | [边界](../01-component-boundaries.md) |
| C04 | Fork 与客户偏离 | 来源、版本、兼容范围、合并／安全修复和迁移责任 | 团队与 AI 统一维护、客户决定升级（D55）；客户版本清单（工程规范）、Fork 规则与基线（[协议 19](../protocols/19-config-secrets-registries-release.md)）。剩余：交付工具与实际验证 | [规范](../06-engineering-conventions.md) |
| C05 | 替换与适配 | 配置、调用、状态、权限、部署和失败恢复成本有界 | 停用保留受限查阅、完全卸载走专项迁移（D54）；12 个选型专篇点名对象与仓库；成员切换（安全 10）、适配器替换（协议 10）、存储路线更换（协议 11、12）、流程引擎更换（协议 09）已有协议；每张边界卡写明替换入口。剩余：组件级退出协议；运行验收 | [替换](../replacements/README.md) |
| C06 | 身份与令牌 | 正确主体、受众／类型／撤销、目录／会话迁移 | 可信身份候选（安全 02）；浏览器与移动端会话见[协议 20](../protocols/20-frontend.md#登录与会话)。剩余：TI01–TI22 未运行；登录与停用时间的 profile；I14 未修复 | [身份候选](../security/02-trusted-identity-and-attributes.md) |
| C07 | 功能授权 | 每个入口权限声明，公开与内部例外明确 | 管理上限与角色绑定（安全 04）、包含证明（安全 07）、受保护操作（安全 08）、编码与准入（安全 09），参考模型已运行。剩余：AM01–AM20 未运行；动作清单随组件声明；SDK 未验 | [管理候选](../security/04-authorization-administration-and-appointments.md) |
| C08 | 数据与对象范围 | 列表／详情／命令／共享／组织／法人语义一致 | 完整段与列表契约（安全 01）、共享治理（安全 05）、有限原子与查询编译（安全 07），参考模型已运行。剩余：AE 与 SD 未运行；关系原子的投影、真实层验收；I28 未闭环 | [求值候选](../security/01-authorization-evaluation.md) |
| C09 | 字段与批量动作 | 掩码、写限制、排序／筛选／导出不越权 | 字段公式、查询字段资格、旧／新状态守卫（安全 01）；命中位图逐行字段（安全 07）；受限字段的筛选排序（[协议 14](../protocols/14-data-foundations.md#列表游标排序与筛选)）。剩余：I18 的正式字段与批量契约随编码（安全 09）与 SDK 共同契约（协议 18）落实；AE 未运行 | [求值候选](../security/01-authorization-evaluation.md) |
| C10 | 授权一致性 | 修订、撤销、缓存、投影故障与 provider 回退 | 按 D57 改写的安全 03：默认有界本地授权与可选严格路径（AT01–AT55），模型已运行；成员切换（安全 10）。剩余：操作分类与路径声明的编码、视图核验接口、原子守卫、B 档参与者登记、参数实测 | [时间候选](../security/03-authorization-acceptance-and-revocation.md) |
| C11 | 委托、扮演、职责分离 | 上限、链、时效、审批资格与审计 | 共享、委托、扮演（安全 05），委托逐维求交（安全 07），审批的职责分离与代理链（[协议 09](../protocols/09-approval-and-workflow.md#决定的提交)）。剩余：SD01–SD22 未运行；源类型与链的编码随安全 09 生成；通知落点 | [共享／委托候选](../security/05-sharing-delegation-and-impersonation.md) |
| C12 | 数据库适配 | 方言、驱动、锁、迁移、角色、分区与恢复兼容 | PostgreSQL 标准与分离形态（数据正文）；数据库使用规则与身份登记（[协议 14](../protocols/14-data-foundations.md)），模型已运行。剩余：外壳分池实测（协议 17 规则）；组件库迁到独立实例的切点与旧写路径退出按数据正文的步骤实测；跨方言按需专项；引擎兼容实测 | [数据](../04-data-and-lifecycle.md) |
| C13 | 事务与并发 | 隔离／重试／锁、版本标记、库存和记账不变量 | 短本地事务与约束／锁序（事务正文、协议 14）；预占（协议 04）、出账核销成本（协议 05）、关账（协议 06），模型已运行。剩余：API 与表结构随组件设计；DT 未执行 | [事务](../05-transactions-and-messaging.md) |
| C14 | 事件与跨组件流程 | Outbox／Inbox、重复／乱序、补偿、对账、人工恢复 | 持久协调与事件分类（事务正文）；投影（协议 02）、增量事实（协议 05）、发件表保留与消费者进度（协议 15）、对外命令（协议 10）。剩余：正式事件契约随组件；DT 未执行 | [事务](../05-transactions-and-messaging.md) |
| C15 | MQ 与队列 | 广播／竞争、持久、重放、死信、停机和迁移 | JetStream 默认、PG 队列为第二适配器；多运输按业务链分开、缺口、死信与长期业务唯一性（事务正文、消息选型）；恢复时重建消息流（协议 15）。剩余：保留窗口取值随实验；适配器未验 | [消息](../replacements/messaging.md) |
| C16 | 同步调用与错误 | 预算、取消、重试条件、错误映射和敏感信息 | 方法准入、用户代理与系统命令、上下文传播（安全 02）；时限、重试、熔断（协议 17）；错误分类（安全 09）。剩余：SDK 绑定（协议 18）与真实调用验证 | [身份候选](../security/02-trusted-identity-and-attributes.md) |
| C17 | 时间、日历、法人 | 业务日期、时区、期间、迟到单据和会计年度 | 每法人一个正式账簿（D51）；时刻、业务日期、法人时区、期间、工作日历（协议 14）；迟到单据（协议 06）。剩余：13 期与 4-4-5 期间模式；工作日历属主随边界卡 | [数据](../04-data-and-lifecycle.md) |
| C18 | 金额、数量、汇率、单位 | 精度、舍入、分摊、币种与多语言一致 | 表示、精度、舍入、分摊、汇率快照、单位（协议 14），模型已运行；税计算与电子开票分别选配（D49）。剩余：税额依据与地区验收；报价、出账与票据金额的核对；币种与汇率主数据属主；三语言向量 | [数据](../04-data-and-lifecycle.md) |
| C19 | ID、单号、分页、过滤 | 唯一、连续要求、游标、排序／筛选和升级 | 身份与身份登记、连续序列、游标与筛选（协议 14），模型已运行。剩余：DT01–DT02 等未执行；各国单号的法定要求 | [数据](../04-data-and-lifecycle.md) |
| C20 | 数据建模与自定义字段 | 不变量、扩展字段、索引、审计与上限 | I33：字段稳定身份、类型与演进、权限、配额、索引及各出口承接（[协议 08](../protocols/08-extension-fields.md)），模型已运行。剩余：逐实体声明；有限设置不替代扩展契约 | [数据](../04-data-and-lifecycle.md) |
| C21 | 迁移与版本兼容 | 旧数据／在途状态、并存、回填、承诺的回滚 | 扩展与收缩、升级路径、持久格式版本（协议 14）；含义变化按破坏性处理（协议 19）；共同切换（替换总则）；恢复代次隔离旧执行者（协议 15）；维护窗口中失败时按备份恢复（协议 17）。剩余：升级中的实测；实验重建不用于客户 | [数据](../04-data-and-lifecycle.md) |
| C22 | 热温冷与保留 | 终态、可变历史、保全、搬运校验、销毁 | 转层资格、单元目录、写屏障、代次发布、读取租约、保全与销毁（[协议 11](../protocols/11-tiering.md)），模型已运行。剩余：Parquet 规范结构与跨语言摘要向量随协议 18 | [数据](../04-data-and-lifecycle.md) |
| C23 | 冷查询与数据治理 | 完整结果、排序分页、权限、导出／解冻与恢复 | 定位索引、目录快照读取、完整或明确不完整、当前授权、解冻（[协议 11](../protocols/11-tiering.md#读取)）。剩余：冷读取端口的实现与预算待实验 | [数据](../04-data-and-lifecycle.md) |
| C24 | 文件与附件 | 桶、凭据、权限、预签名、内容校验和生命周期 | 标准物理访问走 SDK 适配（D53）；对象属主与凭据、内容绑定、下载授权与暴露窗口、引用／清除／保全与对账（[协议 12](../protocols/12-attachments-and-object-storage.md)），模型已运行。剩余：后端接口子集待一致性套件实测 | [附件与存储](../replacements/files-and-attachments.md) |
| C25 | 搜索、报表、分析 | 投影新鲜度、范围与字段、重建、交易资源隔离 | 内置基础报表、自助 BI 选配（D52）；数据集、指标、完整水位、查询时授权、订阅、BI 路线、搜索（[协议 13](../protocols/13-search-reports-and-datasets.md)），模型已运行。剩余：报表目录与数据集清单随边界卡 | [报表与分析](../replacements/analytics-and-reporting.md) |
| C26 | 后台任务与缓存 | 多实例认领、租约、恢复、时间槽、负载和失效 | 工作项状态、认领与接管、副作用种类、时间槽与夏令时（[协议 01](../protocols/01-background-work.md)），作业恢复模型已运行（I27）；多副本单执行者与缓存默认不用（协议 17）。剩余：SDK 与数据库未验 | [验证](../07-validation.md) |
| C27 | 审批、通知、打印 | 能力边界、路由、模板、通道、副作用与替换 | 待办与流程分开（D19）等九项决定；审批见[协议 09](../protocols/09-approval-and-workflow.md)，通知与打印见[协议 10](../protocols/10-external-integration.md#通知)，模型已运行。剩余：统一待办与可选引擎的组件身份随边界卡 | [支撑](../replacements/supporting-capabilities.md) |
| C28 | 外部集成与开放 API | 回调、凭据、幂等、查询结果、版本／配额和失败 | 收付款独立（D47）、税与开票分别选配（D49）；对外命令、回调、对账、凭据、开放接口（[协议 10](../protocols/10-external-integration.md)），模型已运行。剩余：各外部系统的能力声明随适配器设计 | [业务与渠道](../replacements/business-and-channels.md) |
| C29 | 配置与密钥 | 权威源、schema、缺省／校验、文件轮换与运行变化 | 有限业务设置归所属组件（D32）；配置声明与候选快照生效、密钥分类轮换（[协议 19](../protocols/19-config-secrets-registries-release.md)），模型已运行。剩余：ST08–ST09 未执行；有限设置的存储模型随组件 | [规范](../06-engineering-conventions.md) |
| C30 | 多语言与 SDK | 同协议、语义向量、黑盒、语言 API 与入口 | 组件协议的层级与章节、套件的五种结果与自检、语义向量、功能矩阵与准入（[协议 18](../protocols/18-sdk-and-conformance.md)），模型已运行。剩余：套件与向量未运行 | [验证](../07-validation.md) |
| C31 | 单跑与外壳 | 同版成员等价、身份／配置／数据／资源不串扰 | 组件独立开发、外壳优先候选、测后定案（D40）；共进程信任（部署正文）；外壳预算合并（[协议 17](../protocols/17-runtime-and-resources.md)），模型已运行。剩余：四骨架真实组装与拆回待验 | [部署](../03-deployment-and-resources.md) |
| C32 | 多副本与故障隔离 | 无重复副作用，预算与异常不拖垮其他成员 | 认领与代次（协议 01）；多副本规则、预算与过载（协议 17）。剩余：真实多副本矩阵未执行 | [部署](../03-deployment-and-resources.md) |
| C33 | 部署引擎与环境 | 目标支持、迁移、真实请求、事件、升级、收尾 | Podman 重点候选（D40）；维护窗口（D25）；引擎矩阵的代表格（协议 17）。剩余：代表矩阵与恢复待验 | [部署](../03-deployment-and-resources.md) |
| C34 | 性能与容量 | 可配置预算、尾延迟、业务完成、压力与长期资源 | 实验先于重建（D41）；完整部署矩阵与性能基线用重建后的约 20 个组件运行（路线的开发五步），完整基线原排期保留；测量协议与预算模板（协议 17）。剩余：实验计划（接续清单第 8 项）；资源与容量未测 | [部署](../03-deployment-and-resources.md) |
| C35 | 可观测与运维 | 日志、追踪、指标、审计、告警真实可用与脱敏 | 按风险的审计（D28）、两档观测（D43）；审计保存（[协议 03](../protocols/03-audit-durability.md)，I29 模型已运行）；观测输出、业务健康指标与必需告警（协议 17）。剩余：资源成本与故障诊断实测；实现未验 | [支撑](../replacements/supporting-capabilities.md) |
| C36 | 安全与供应链 | 最小权限、漏洞、入口、依赖、敏感信息与来源 | 服务凭据、事件来源与外壳限制（安全 02）；密钥轮换与供应链（协议 19）；浏览器安全（协议 20）。剩余：TI 未运行；扫描、签名与来源证明工具；I14 未修复 | [身份候选](../security/02-trusted-identity-and-attributes.md) |
| C37 | 备份恢复／HA | 范围、恢复目标、真实恢复和必要切换 | 整套一致性恢复优先（D26）；恢复组、独立证据存储、按消费者进度补发、十步流程与演练（[协议 15](../protocols/15-backup-and-recovery.md)），模型已运行。剩余：工具与恢复时间待实测；演练未执行 | [数据](../04-data-and-lifecycle.md) |
| C38 | 前端基础接入 | 登录、契约、权限、缺件、错误、多端、多语言和体验 | 入口分别选择（D17）、断网草稿（D24）、构建时组合（D34）；入口与模块、服务端会话、显示规则、草稿、旧客户端（[协议 20](../protocols/20-frontend.md)），模型已运行。剩余（I86–I89，第 7 批整理协议 20 时处理）：`token_stale` 在服务端会话下的处理；菜单与导航的唯一来源与 be-ops 菜单聚合的去留；技术栈与视觉交互按 D59 复核或声明沿用（待用户决定），原生移动与 Uni-app 的对应；入口与页面模块的仓库划分、共享代码包与构建工具（随实施计划）；会话存储与边缘令牌缓存实现（第 8 项实验）；原生移动与仓库终端的具体技术；可选离线采集（远期） | [前端](../replacements/frontend.md) |
| C39 | 构建、发布、交付 | 精确来源、版本、产物、安装／升级与离线承诺 | 稳定维护与客户自主升级（D55）、精确基线（D58）、联网优先（D42）；版本、产物、供应链、基线与升级（协议 19）。剩余：支持期、交付工具、升级矩阵 | [规范](../06-engineering-conventions.md) |
| C40 | 测试与检查器 | 全目标映射、套件自测、空／部分执行不假通过 | PA 36 项、DT 30 项、ST 12 项预期与记录格式；各安全候选与协议的独立预期（34 个前缀、703 条，编号检查已运行）及参考模型（`work/checks/08–32`）；套件的结果规则（协议 18）；验证映射与从预期到测试的规则（[协议 21](../protocols/21-verification-and-migration.md)）。剩余：覆盖报告工具；具体命令与版本绑定；运行证据 | [验证](../07-validation.md) |
| C41 | 文档与 AI 工作流 | 两类读者、唯一来源、读取／变更边界与事实可追溯 | 客户与开发路线、货架与 12 个选型专篇、边界卡；全套文档检查见 rounds/06；正式文档的目标结构（协议 21）。剩余：迁移与业务证据 | [规范](../06-engineering-conventions.md) |
| C42 | 正式文档迁移 | 所有有效内容承接、双语语义核对、现行归档引用清零 | 切换步骤（路线）与迁移协议：承接表、提取、英文正文、中文镜像、归档、入口与工具、收尾检查（[协议 21](../protocols/21-verification-and-migration.md#正式文档迁移)）。剩余：用户确认冻结后执行；尚未迁移 | [路线](../08-roadmap.md) |
| C43 | 客户导入、期初与上线切点 | 模板／来源身份、预检确认、权限／幂等、部分失败、期初流水和余额、试迁移与对账 | I32：导入机制、期初事实、批次激活与对账、切点与试迁移（[协议 16](../protocols/16-go-live-and-import.md)），模型已运行。剩余：各组件的模板与期初类型；平台导入工具的实施排期保留 | [审查 R06](rounds/06-final-goal-document-audit.md#r06首次上线期初事实和业务导入未纳入完整覆盖p1i32) |
| C44 | 跨组件引用生命周期 | 类型／范围、引用资格、历史快照、停用／合并／删除、别名／墓碑、稳定定位与修复责任 | I31：两类引用、资格检查、合并与别名、解析结果、修复与擦除（[协议 07](../protocols/07-references.md)），模型已运行。剩余：各组件引用字段的声明随边界卡 | [审查 R05](rounds/06-final-goal-document-audit.md#r05跨组件引用没有完整生命周期p1i31) |
