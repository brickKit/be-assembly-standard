# 组件货架

本页是全部组件的目录：身份、能力与范围。谁与谁替换、并存或协作见[选择方式、关系与客户组合](04-selection.md)；每个组件的数据、不变量、依赖与缺件行为见它的边界卡（[边界卡目录](../07-components/README.md)）。

## 怎样读

- **组件 ID** 写作 `<领域>/<名称>`，仓库名把 `/` 换成 `-`（例如 `erp/sales` 的仓库是 `erp-sales`）。身份是持久标识，只追加不复用（协议 19）。
- **范围**：**当前重建**是近期按新设计实现、用于代表部署实验与部署矩阵的组件；**远期**参与全局设计、按路线开发；**留位**只保留身份与契约位置；**评估**尚未决定是否开发。
- 注册了身份不等于已经实现；现有代码只作参考（D59），全部组件按新设计重建。

## 基础与通用能力

| 组件 ID | 能力 | 范围 | 选型说明 |
| --- | --- | --- | --- |
| `infra/iam-casdoor` | 身份认证适配（Casdoor） | 当前重建 | [身份](guides/identity.md) |
| `infra/iam-keycloak` | 身份认证适配（Keycloak） | 远期 | [身份](guides/identity.md) |
| `infra/authz` | 授权：权限目录、授予、视图与核验 | 当前重建 | [授权](guides/authorization.md) |
| `infra/authz-static` | 授权的静态配置成员 | 远期 | [授权](guides/authorization.md) |
| `infra/authz-openfga` | 授权的关系图成员（OpenFGA） | 远期 | [授权](guides/authorization.md) |
| 策略引擎成员（ID 未分配） | 授权的属性／策略引擎成员 | 评估 | [授权](guides/authorization.md) |
| `infra/workflow` | 统一待办（不含流程引擎） | 当前重建 | [支撑能力](guides/supporting-capabilities.md) |
| `infra/notification` | 通知意图、偏好与通道路由 | 当前重建 | [支撑能力](guides/supporting-capabilities.md) |
| `infra/attachment` | 附件元数据、处理状态与授权协作 | 当前重建 | [附件与存储](guides/files-and-attachments.md) |
| `infra/print` | 单据与标签渲染 | 当前重建 | [支撑能力](guides/supporting-capabilities.md) |
| `infra/audit` | 业务审计的集中保存与查询；兼任独立证据存储 | 当前重建 | [支撑能力](guides/supporting-capabilities.md) |
| `infra/bff-mobile` | 移动端展示聚合 | 当前重建 | [支撑能力](guides/supporting-capabilities.md) |
| `infra/dlq-monitor` | 死信观察、处理与审计 | 远期 | [支撑能力](guides/supporting-capabilities.md) |

## 主数据

| 组件 ID | 能力 | 范围 | 选型说明 |
| --- | --- | --- | --- |
| `mdm/partner` | 业务伙伴：共有身份、客户／供应商／员工往来／关联方角色、正式联络资料、伙伴银行账户 | 当前重建 | [业务与渠道](guides/business-and-channels.md) |
| `mdm/product` | 产品、物料、单位换算、批次与序列追踪政策 | 当前重建 | [业务与渠道](guides/business-and-channels.md) |
| `mdm/org` | 法人、部门、岗位、汇报关系、地点、工作日历 | 当前重建 | [业务与渠道](guides/business-and-channels.md) |
| `mdm/employee` | 员工、任职、员工与账号的映射 | 当前重建 | [业务与渠道](guides/business-and-channels.md) |
| `mdm/currency` | 币种、汇率类型与汇率 | 当前重建 | [财务与结算](guides/finance-and-settlement.md) |

## 交易与库存

| 组件 ID | 能力 | 范围 | 选型说明 |
| --- | --- | --- | --- |
| `erp/sales` | 报价、计价与销售订单；实物与服务共同基础 | 当前重建 | [业务与渠道](guides/business-and-channels.md) |
| `erp/purchase` | 采购申请、订单与到货 | 当前重建 | [业务与渠道](guides/business-and-channels.md) |
| `erp/inventory` | 库存数量、预占与物理变动（唯一写入者） | 当前重建 | [业务与渠道](guides/business-and-channels.md) |
| `erp/contract` | 客户合同、框架协议、订阅与周期出账计划（D70） | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `erp/intercompany` | 公司间规则、对开单据与内部往来对账（D72） | 远期 | [财务与结算](guides/finance-and-settlement.md) |
| `erp/planning` | 补货规则（再订货点、安全库存）、需求预测与物料需求计划（D71） | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `erp/warehouse` | 可选的复杂仓库作业（波次、拣货、复核、打包） | 远期 | [业务与渠道](guides/business-and-channels.md) |

## 财务与结算

| 组件 ID | 能力 | 范围 | 选型说明 |
| --- | --- | --- | --- |
| `erp/finance` | 总账、应收应付（含预收、预付、员工借款）、付款认领、核销、外币重估与期末暂估、维度目录与递延、会计期间；应付内部的供应商票据匹配 | 当前重建 | [财务与结算](guides/finance-and-settlement.md) |
| `erp/credit` | 信用政策、额度与信用占用 | 当前重建 | [财务与结算](guides/finance-and-settlement.md) |
| `erp/costing` | 存货计价与成本子账；暂估、到岸成本、工单成本与差异、退货冲回 | 当前重建 | [财务与结算](guides/finance-and-settlement.md) |
| `erp/billing` | 客户账单与商业发票 | 当前重建 | [财务与结算](guides/finance-and-settlement.md) |
| `erp/payment` | 收付款业务与银行／渠道对账 | 当前重建 | [财务与结算](guides/finance-and-settlement.md) |
| `erp/consolidation` | 集团结构、抵销、外币报表折算与合并报表（D72） | 远期 | [财务与结算](guides/finance-and-settlement.md) |
| `erp/tax` | 税计算 | 远期 | [财务与结算](guides/finance-and-settlement.md) |
| `erp/budget` | 预算编制与控制，占用沿用预占分支 | 远期 | [财务与结算](guides/finance-and-settlement.md) |

## 生产与资产

| 组件 ID | 能力 | 范围 | 选型说明 |
| --- | --- | --- | --- |
| `erp/manufacturing` | BOM、生产工单与工序 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `erp/quality` | 检验与不合格品 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `erp/maintenance` | 设备维护与备件 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `erp/asset` | 固定资产、折旧、盘点与处置 | 远期 | [业务与渠道](guides/business-and-channels.md) |

## 客户关系

| 组件 ID | 能力 | 范围 | 选型说明 |
| --- | --- | --- | --- |
| `crm/lead` | 线索获取、去重与转化 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `crm/customer` | 销售归属、共享、公海与关系 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `crm/opportunity` | 商机生命周期与预测 | 当前重建 | [业务与渠道](guides/business-and-channels.md) |
| `crm/activity` | 跟进、拜访与活动时间线 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `crm/campaign` | 营销活动与归因 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `crm/case` | 客户服务、工单与服务目标 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `crm/commission` | 佣金规则与结算 | 远期 | [业务与渠道](guides/business-and-channels.md) |

## 人事与薪资

| 组件 ID | 能力 | 范围 | 选型说明 |
| --- | --- | --- | --- |
| `hrm/attendance` | 考勤、排班与加班 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `hrm/leave` | 请假与余额 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `hrm/expense` | 费用报销与审批 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `hrm/recruitment` | 招聘流程 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `hrm/appraisal` | 绩效目标与评价 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `hrm/payroll-core` | 共用薪资模型（组件还是共用库，随第一个国家实现决定） | 远期 | [业务与渠道](guides/business-and-channels.md#薪资按法人选择) |
| `hrm/payroll-cn`、`hrm/payroll-us`、`hrm/payroll-es` | 各国薪资实现，按法人选择 | 远期 | [业务与渠道](guides/business-and-channels.md#薪资按法人选择) |

## 项目与分析

| 组件 ID | 能力 | 范围 | 选型说明 |
| --- | --- | --- | --- |
| `prj/project` | 项目计划、估算、成本的分析归集；按里程碑或按工时与费用出账 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `prj/timesheet` | 工时与审批（归集在项目） | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `ana/bi` | 数据集、指标与内置报表 | 远期（是否进入当前重建，随重建计划确认） | [报表与分析](guides/analytics-and-reporting.md) |
| `ana/search` | 全局搜索索引与查询 | 远期 | [报表与分析](guides/analytics-and-reporting.md) |
| `ana/ai` | 业务 AI 能力 | 留位 | — |

## 外部渠道与集成

| 组件 ID | 能力 | 范围 | 选型说明 |
| --- | --- | --- | --- |
| `integration/im-dingtalk` | 钉钉消息与回调 | 当前重建 | [业务与渠道](guides/business-and-channels.md#im-通道) |
| `integration/im-wechat-work`、`integration/im-feishu`、`integration/im-slack`、`integration/im-teams` | 企业微信、飞书、Slack、Teams 消息与回调 | 远期 | [业务与渠道](guides/business-and-channels.md#im-通道) |
| `integration/payment-stripe`、`integration/payment-paypal`、`integration/payment-alipay`、`integration/payment-wechat-pay` | 支付通道适配 | 远期 | [业务与渠道](guides/business-and-channels.md#支付与电子签通道) |
| `integration/esign-docusign`、`integration/esign-pandadoc`、`integration/esign-esign` | 电子签适配 | 远期 | [业务与渠道](guides/business-and-channels.md#支付与电子签通道) |
| `integration/bank-<格式>` | 银行对账单与付款文件（例如 `bank-iso20022`） | 远期 | [财务与结算](guides/finance-and-settlement.md#收付款通道与财务) |
| `integration/einvoice-<地区>` | 各地区的合规电子开票（例如 `einvoice-es`、`einvoice-cn`） | 远期 | [财务与结算](guides/finance-and-settlement.md#税计算与合规电子开票) |
| `integration/email`、`integration/sms` | 邮件与短信投递 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `integration/edi` | 供应链数据交换 | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `integration/carrier-<承运商>` | 物流承运：面单、运单号与轨迹（D73） | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `integration/shop-<平台>` | 电商平台：订单转换与可售量同步（D73） | 远期 | [业务与渠道](guides/business-and-channels.md) |
| `integration/print-agent` | 客户现场的打印代理 | 远期 | [支撑能力](guides/supporting-capabilities.md) |

## 使用入口

| 组件 ID | 能力 | 范围 | 选型说明 |
| --- | --- | --- | --- |
| `frontend/pc` | PC 办公入口 | 当前重建 | [前端](guides/frontend.md) |
| `frontend/mobile` | 移动外勤入口 | 当前重建 | [前端](guides/frontend.md) |
| `frontend/terminal` | 仓库终端入口 | 远期 | [前端](guides/frontend.md) |
| `frontend/advanced` | 行业或高级交互入口 | 远期 | [前端](guides/frontend.md) |
| 客户与供应商门户（ID 未分配） | 外部人员登录、只看自己公司的数据；需要新的身份与授权模型（D73） | 评估 | — |
| 门店收银（ID 未分配） | 断网收款、收银班次与现金；与 D24 的在线确认提交冲突，单独设计（D73） | 评估 | — |
| 现场服务（ID 未分配） | 服务派工、上门、备件消耗；与服务工单（`crm/case`）、库存协作，单独设计 | 评估 | — |

## 新增与退役的身份

新增的身份在正式迁移时登记端口与 schema（协议 19）：`mdm/partner`、`mdm/employee`、`mdm/currency`、`erp/contract`、`erp/planning`、`erp/intercompany`、`erp/consolidation`、`erp/warehouse`、`erp/credit`、`erp/costing`、`erp/billing`、`erp/payment`、`erp/tax`、`erp/budget`、`integration/einvoice-<地区>`、`integration/bank-<格式>`、`integration/carrier-<承运商>`、`integration/shop-<平台>`、`integration/print-agent`、`infra/authz-static`、`infra/authz-openfga`、`ana/search`、`frontend/pc`、`frontend/mobile`、`frontend/terminal`。可选流程引擎的适配组件、通用 OIDC／目录适配在选定产品后登记。

| 退役的身份 | 去向 |
| --- | --- |
| `mdm/customer`、`mdm/supplier` | 由 `mdm/partner` 承接；身份保留、不复用 |
| `infra/storage` | 纯转发不进标准货架，物理访问由 SDK 存储适配器承担（D53）；身份保留、不复用 |
| `frontend/standard` | 拆为按入口的 `frontend/pc`、`frontend/mobile`、`frontend/terminal` |

`infra/workflow` 的身份保留，职责改为统一待办（D19）。治理与冷查询不设独立组件，由各属主组件的单元目录与冷读取端口承担（协议 11）。任何新增、删除、合并都写明原货架能力的新去处，不在重构中漏掉长期目标。

## 当前重建范围

近期按新设计重建下列组件，覆盖两条代表业务链与它们的支撑能力，用于代表部署实验与之后的完整部署矩阵：

- 报价 → 订单确认与预占 → 出库 → 出账 → 应收 → 收款与核销 → 关账；
- 采购 → 入库 → 暂估 → 票据匹配 → 成本调整（D63 加入采购）。

| 类别 | 组件 |
| --- | --- |
| 主数据 | `mdm/partner`、`mdm/product`、`mdm/org`、`mdm/employee`、`mdm/currency` |
| 基础 | `infra/iam-casdoor`、`infra/authz`、`infra/workflow`、`infra/notification`、`infra/print`、`infra/attachment`、`infra/audit`、`infra/bff-mobile` |
| 业务 | `erp/sales`、`erp/purchase`、`erp/inventory`、`erp/finance`、`erp/credit`、`erp/billing`、`erp/costing`、`erp/payment`、`crm/opportunity` |
| 渠道 | `integration/im-dingtalk` |
| 入口 | `frontend/pc`、`frontend/mobile` |

共 23 个后端组件与 2 个入口，另加外壳。确切范围（包括内置报表 `ana/bi` 是否同时进入）在重建计划的实施与实验计划中由用户确认。
