# 长期组件货架与当前实现

> 状态：原始第 5 章的 60 个条目全部承接为审查候选，后续方向另列。候选名称不是已经批准的组件边界，也不是本轮全部开工清单。
>
> 按 D59，文中“已有”“已实现”“当前实现”指旧版代码；终局设计按新设计重建，旧代码只作参考，不作约束。
>
> 2026-10-13：每个组件的边界卡（数据、不变量、依赖、缺件、替换、验证故事）见[全货架边界卡](README.md)；新增与退役的候选身份、当前重建范围的候选也在那里。

## 如何看这张货架

先看客户需要的能力，再看它的数据、事务、依赖、替换和运行方式。仓库前缀是分类；真实限界上下文在边界卡中确定。注册预留不等于已实现，源码存在不等于新设计验收通过。端口和 schema 仍从现有注册表读取，本表不重新分配。

长期货架不能因当前重建范围而删成当前组件数量。每个条目的客户故事、上下文、拥有的数据、不变量、必需／可选依赖、缺件行为、替换路径、资源和验收写在[边界卡](README.md)中。

## 仓库与替换关系怎样对应

每个最终组件由自己的仓库维护。下表“已接入源码”的地址核对自项目子模块来源，仅表示仓库已接入，不代表目标版或所有部署形态已验收；“规划名”按组件 ID 的命名约定列出，不宣称仓库已创建。新增能力未分配正式 ID 时不提前编造仓库名，见后续方向表。

完整货架回答有哪些能力与仓库；[能力分图与替换关系](selection-map.md)回答哪些互相替换、并存或协作；选型专篇比较优劣势、使用场景、部署与迁移。销售、库存、财务等协作组件不列为互相替代，SDK 适配器与基础资源也不冒充组件仓库。

现行源码与未来划分分开：伙伴主数据、前端入口等新方向尚未落成最终仓库，原条目保留承接与迁移责任。Fork 的来源和独立版本须记录，不能仅因仓库不同就判定已可互换。

## 基础与通用能力

| 候选身份 | 仓库定位 | 能力范围 | 当前事实 | 注册状态 | 定制／替换入口 |
| --- | --- | --- | --- | --- | --- |
| `infra/iam-casdoor` | [infra-iam-casdoor](https://github.com/brickKit/infra-iam-casdoor)（已接入源码） | 身份认证与平台用户适配 | 项目已锁定 2.0.0 | 已有预留 | [选型与适配](../replacements/identity.md) |
| `infra/authz` | [infra-authz](https://github.com/brickKit/infra-authz)（已接入源码） | 权限目录、授予与授权策略 | 项目已锁定 2.0.1 | 已有预留 | [选型与适配](../replacements/authorization.md) |
| `infra/iam-keycloak` | `infra-iam-keycloak`（规划名） | 另一种身份提供方适配 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/identity.md) |
| `infra/bff-mobile` | [infra-bff-mobile](https://github.com/brickKit/infra-bff-mobile)（已接入源码） | 跨组件展示聚合 | 项目已锁定 2.0.0 | 已有预留 | [选型与适配](../replacements/supporting-capabilities.md) |
| `infra/workflow` | [infra-workflow](https://github.com/brickKit/infra-workflow)（已接入源码） | 现有轻量审批／异常待办；新设计待办与流程分开，具体去处待审 | 项目已锁定 2.0.1，尚未按新方向重构 | 已有预留 | [选型与适配](../replacements/supporting-capabilities.md) |
| `infra/notification` | [infra-notification](https://github.com/brickKit/infra-notification)（已接入源码） | 通知意图、偏好与通道路由 | 项目已锁定 2.0.0 | 已有预留 | [选型与适配](../replacements/supporting-capabilities.md) |
| `infra/attachment` | `infra-attachment`（规划名） | 附件元数据与用户访问，向父记录所属组件检查授权 | 原始规划，未实现 | 已有预留 | [附件与存储](../replacements/files-and-attachments.md) |
| `infra/storage` | `infra-storage`（规划名） | 纯物理转发由 SDK 适配器承担；有独立治理价值时再审 | 原始规划，未实现；纯转发形态退出标准开发货架 | 已有预留，不回收身份或注册值 | [附件与存储](../replacements/files-and-attachments.md) |
| `infra/print` | [infra-print](https://github.com/brickKit/infra-print)（已接入源码） | 单据与标签渲染 | 项目已锁定 2.0.0 | 已有预留 | [选型与适配](../replacements/supporting-capabilities.md) |
| `infra/audit` | `infra-audit`（规划名） | 业务审计与查询 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/supporting-capabilities.md) |
| `infra/dlq-monitor` | `infra-dlq-monitor`（规划名） | 死信观察、处理与审计 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/supporting-capabilities.md) |

## 外部渠道与集成

| 候选身份 | 仓库定位 | 能力范围 | 当前事实 | 注册状态 | 定制／替换入口 |
| --- | --- | --- | --- | --- | --- |
| `integration/im-dingtalk` | [integration-im-dingtalk](https://github.com/brickKit/integration-im-dingtalk)（已接入源码） | 钉钉消息与回调 | 项目已锁定 2.0.0 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/im-wechat-work` | `integration-im-wechat-work`（规划名） | 企业微信消息与回调 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/im-feishu` | `integration-im-feishu`（规划名） | 飞书消息与回调 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/im-slack` | `integration-im-slack`（规划名） | Slack 消息与回调 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/im-teams` | `integration-im-teams`（规划名） | Teams 消息与回调 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/payment-stripe` | `integration-payment-stripe`（规划名） | Stripe 支付适配 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/payment-paypal` | `integration-payment-paypal`（规划名） | PayPal 支付适配 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/payment-alipay` | `integration-payment-alipay`（规划名） | 支付宝适配 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/payment-wechat-pay` | `integration-payment-wechat-pay`（规划名） | 微信支付适配 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/esign-docusign` | `integration-esign-docusign`（规划名） | DocuSign 电子签适配 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/esign-pandadoc` | `integration-esign-pandadoc`（规划名） | PandaDoc 电子签适配 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/esign-esign` | `integration-esign-esign`（规划名） | e签宝适配 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/email` | `integration-email`（规划名） | 邮件服务通道 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/sms` | `integration-sms`（规划名） | 短信服务通道 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `integration/edi` | `integration-edi`（规划名） | 供应链数据交换 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |

## 主数据

| 候选身份 | 仓库定位 | 能力范围 | 当前事实 | 注册状态 | 定制／替换入口 |
| --- | --- | --- | --- | --- | --- |
| `mdm/customer` | [mdm-customer](https://github.com/brickKit/mdm-customer)（已接入源码） | 企业客户身份与基础资料 | 项目已锁定 2.0.1 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `mdm/supplier` | `mdm-supplier`（规划名） | 供应商基础资料 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `mdm/product` | [mdm-product](https://github.com/brickKit/mdm-product)（已接入源码） | 产品、物料、单位与追踪政策 | 项目已锁定 2.0.0 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `mdm/org` | `mdm-org`（规划名） | 组织候选：已定同一组件拥有法人、部门、岗位与汇报关系；员工／任职归独立能力 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |

客户／供应商基础身份已定统一为业务伙伴主数据，内部区分角色及角色资料。mdm/customer 与 mdm/supplier 两个原条目的有效能力由新边界承接，不据此继续保留两份共有身份权威；候选身份为 `mdm/partner`（[边界卡](mdm.md#mdmpartner)），两个原身份标为退役、不复用；按 D59 不承担旧契约的兼容迁移。

正式联络基础资料同样归伙伴主数据，CRM 的跟进／私人关系记录与采购特有记录分别保留；联系人模型、独立组件必要性和历史迁移另审，不新增员工／IAM 通用人员库。

## 客户关系

| 候选身份 | 仓库定位 | 能力范围 | 当前事实 | 注册状态 | 定制／替换入口 |
| --- | --- | --- | --- | --- | --- |
| `crm/lead` | `crm-lead`（规划名） | 线索获取、去重与转化 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `crm/customer` | `crm-customer`（规划名） | 销售归属、共享、公海与关系 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `crm/opportunity` | [crm-opportunity](https://github.com/brickKit/crm-opportunity)（已接入源码） | 商机生命周期与预测 | 项目已锁定 2.0.0 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `crm/activity` | `crm-activity`（规划名） | 跟进、拜访与活动时间线 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `crm/campaign` | `crm-campaign`（规划名） | 营销活动与归因 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `crm/case` | `crm-case`（规划名） | 客户服务、工单与服务目标 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `crm/commission` | `crm-commission`（规划名） | 佣金规则与结算 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |

## 企业资源

| 候选身份 | 仓库定位 | 能力范围 | 当前事实 | 注册状态 | 定制／替换入口 |
| --- | --- | --- | --- | --- | --- |
| `erp/sales` | [erp-sales](https://github.com/brickKit/erp-sales)（已接入源码） | 报价、计价与销售订单；已定标准销售统一实物／服务基础 | 项目已锁定 2.0.0；无库存服务组合待设计实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `erp/purchase` | `erp-purchase`（规划名） | 采购申请、订单与到货 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `erp/inventory` | [erp-inventory](https://github.com/brickKit/erp-inventory)（已接入源码） | 库存事实、预占与物理移动 | 项目已锁定 2.0.0 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `erp/finance` | [erp-finance](https://github.com/brickKit/erp-finance)（已接入源码） | 会计、应收应付、期间与对账；新方向包含应付内部的供应商票据受理／匹配 | 项目已锁定 2.0.0；新应付写入流程未实现 | 已有预留 | [选型与适配](../replacements/finance-and-settlement.md) |
| `erp/manufacturing` | `erp-manufacturing`（规划名） | BOM、生产工单、工序与 MRP | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `erp/asset` | `erp-asset`（规划名） | 资产、折旧、盘点与处置 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `erp/quality` | `erp-quality`（规划名） | 检验与不合格品 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `erp/maintenance` | `erp-maintenance`（规划名） | 设备维护与备件 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |

## 人事与薪资

| 候选身份 | 仓库定位 | 能力范围 | 当前事实 | 注册状态 | 定制／替换入口 |
| --- | --- | --- | --- | --- | --- |
| `hrm/attendance` | `hrm-attendance`（规划名） | 考勤、排班与加班 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `hrm/leave` | `hrm-leave`（规划名） | 请假与余额 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `hrm/expense` | `hrm-expense`（规划名） | 费用报销与审批 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `hrm/recruitment` | `hrm-recruitment`（规划名） | 招聘流程 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `hrm/appraisal` | `hrm-appraisal`（规划名） | 绩效目标与评价 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `hrm/payroll-core` | `hrm-payroll-core`（规划名） | 共用薪资模型，是否独立待审 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `hrm/payroll-cn` | `hrm-payroll-cn`（规划名） | 中国薪资适配候选 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `hrm/payroll-us` | `hrm-payroll-us`（规划名） | 美国薪资适配候选 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `hrm/payroll-es` | `hrm-payroll-es`（规划名） | 西班牙薪资适配候选 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |

## 项目

| 候选身份 | 仓库定位 | 能力范围 | 当前事实 | 注册状态 | 定制／替换入口 |
| --- | --- | --- | --- | --- | --- |
| `prj/project` | `prj-project`（规划名） | 项目计划、里程碑与成本 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |
| `prj/timesheet` | `prj-timesheet`（规划名） | 工时、审批与项目归集 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |

## 分析

| 候选身份 | 仓库定位 | 能力范围 | 当前事实 | 注册状态 | 定制／替换入口 |
| --- | --- | --- | --- | --- | --- |
| `ana/bi` | `ana-bi`（规划名） | 分析投影、报表与展示；交付与内部能力边界待审 | 原始规划，未实现 | 已有预留 | [报表与分析](../replacements/analytics-and-reporting.md) |
| `ana/ai` | `ana-ai`（规划名） | 远期分析设想；本轮只留位子 | 本轮只留位子，暂不开发 | 已有预留 | [选型与适配](../replacements/business-and-channels.md) |

## 前端

| 候选身份 | 仓库定位 | 能力范围 | 当前事实 | 注册状态 | 定制／替换入口 |
| --- | --- | --- | --- | --- | --- |
| `frontend/standard` | [frontend-standard](https://github.com/brickKit/frontend-standard)（已接入源码） | 标准 PC／移动业务入口 | 源码存在，未进入当前项目锁 | 已有预留 | [选型与适配](../replacements/frontend.md) |
| `frontend/advanced` | `frontend-advanced`（规划名） | 行业／高级交互与可视化候选 | 原始规划，未实现 | 已有预留 | [选型与适配](../replacements/frontend.md) |

已定按 PC、移动、仓库终端等使用入口分别选择、组合与替换。表中两个原始产品条目继续保留能力承接记录；不能据此推导它们仍是整套部署互斥的最终边界。现有 standard 的拆分、共享代码、身份与版本迁移尚未实施。

## 后续设计新增的方向

授权的新增候选已有设计名称，但尚未作为当前源码子模块或已验收成员接入；它们不属于前面的原始 60 条目，列在这里避免目录遗漏：

| 设计候选身份 | 仓库定位 | 可以接替的能力 | 状态与选择入口 |
| --- | --- | --- | --- |
| `infra/authz-static` | `infra-authz-static`（规划名） | 在满足客户必需能力时接替所选授权 provider | 计划；[授权模型与组件](../replacements/authorization.md) |
| `infra/authz-openfga` | `infra-authz-openfga`（规划名） | 以关系图适配承接相同授权契约，范围／字段等仍需共同实现 | 计划；[授权模型与组件](../replacements/authorization.md) |
| 策略引擎成员 | 正式组件 ID／仓库未分配 | 在共同语义与查询／字段、状态迁移满足时成为另一 provider | 长期评估，不承诺本轮开发；[策略路线](../replacements/authorization.md#哪些组件可以相互替换) |

| 方向 | 当前设计事实 | 边界卡与候选身份 |
| --- | --- | --- |
| 法人、组织、币种与汇率 | 已定法人和组织同组件；会计期间归财务 | `mdm/org`、`mdm/currency`，见[主数据](mdm.md) |
| 独立基础员工与任职 | 第 1 轮用户已定，HR 扩展与 IAM 分别拥有自己的职责 | `mdm/employee`，见[主数据](mdm.md#mdmemployee) |
| 独立信用管理 | 额度政策、信用占用与授信判断独立于财务记账 | `erp/credit`，见[财务与结算](erp-finance.md#erpcredit) |
| 可选复杂仓储 | 仓库任务与库存核心分开维护和替换；库存保持数量写入权威 | `erp/warehouse`，见[交易与库存](erp-trade.md#erpwarehouse) |
| 独立存货成本 | 计价与成本子账独立选配与替换 | `erp/costing`，见[财务与结算](erp-finance.md#erpcosting) |
| 独立收付款 | 资金收付与银行／渠道对账独立于核销与总账 | `erp/payment`、`integration/bank-<格式>`，见[财务与结算](erp-finance.md#erppayment)与[集成](integration.md) |
| 独立客户出账 | 客户账单与商业发票独立，承接多种业务来源 | `erp/billing`，见[财务与结算](erp-finance.md#erpbilling) |
| 税计算与合规电子开票 | 两种能力分别选配与替换 | `erp/tax`、`integration/einvoice-<地区>` |
| 静态与关系图授权 | authz-static、authz-openfga 已在原升级计划 | 见[基础能力](infra.md#infraauthz-staticinfraauthz-openfga)与安全 10 |
| 通用身份／目录适配 | 原设计的 OIDC／目录方向 | 与 IAM 成员同一契约；身份在选定后登记 |
| 数据治理与冷查询 | 原后续分析提出的治理职责 | 由各属主组件的单元目录与冷读取端口承担（协议 11），不设独立组件 |
| 搜索与多种分析实现 | 长期投影／查询方向 | `ana/search`；数据集与报表归 `ana/bi`，见[分析](ana.md) |
| 其他业务算法实现 | 常见合理差异主动设计明确替换点 | 写在各卡的“替换与 Fork” |
| 统一待办与可选流程引擎 | 两种能力分开；简单流程由业务组件管理 | `infra/workflow` 改为统一待办；引擎适配在选定产品后登记 |
| 统一业务伙伴主数据 | 共享基础身份、区分客户／供应商角色、维护正式联络资料 | `mdm/partner`，承接 `mdm/customer`、`mdm/supplier` |
| 现场打印 | 协议 10 提出的现场打印代理 | `integration/print-agent` |

这些候选身份在正式迁移时登记，不意味着已经新建仓库。任何新增、删除、合并都要说明原货架能力的新去处，不能在重构中漏掉用户的长期目标。

## 客户组合的审查样板

- 精简进销存：确认最小身份／权限、主数据、销售、库存及必要财务能力，通知／打印／CRM 能否按需加入。
- CRM 与销售协作：客户关系、商机与 ERP 可分别启用，消息与权限、共享和回款视图都有明确行为。
- 多法人集团：法人、目录、币种、期间、范围、汇总与多个国家业务实现能够组合。
- 制造与维护：BOM、生产、领料、库存、质量和财务不变量不依赖错误的既有边界。
- 人事与项目：人员、任职、考勤、薪资、工时和报销的归属与国家选择明确。

样板是待验证的组合，不是已经上线的产品套餐。先做成功和失败故事，再决定必选闭包、缺件降级、部署组合与测量参数。
