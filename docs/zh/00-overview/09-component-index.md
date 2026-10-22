# 组件索引

> 由 `make docs-index`（`infra/scripts/component-index.py`）从[组件货架](03-catalog.md)、[边界卡](../07-components/README.md)与各组件的 `component.yaml` 生成，不要手改。

按组件 ID 找到它的边界卡、仓库里的文档与实现状态；“被谁必需依赖”是改它会影响到的组件（只算必需依赖，可选依赖与缺件行为见边界卡）。
业务词先查[术语表](07-glossary.md)，它给出所属组件；跨组件的业务过程见[业务流程](../08-flows/README.md)。

**实现**一列：已按新设计重建的组件写版本，打开“组件文档”里的 `AGENTS.md` 从代码地图开始；“设计中”的组件已在仓库里写好 `docs/design.md`、代码还没有；没有版本的只有设计（边界卡与协议）。

## 基础与通用能力

| 组件 ID | 能力 | 范围 | 实现 | 边界卡 | 组件文档 | 必需依赖 | 被谁必需依赖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `infra/iam-casdoor` | 身份认证适配（Casdoor） | 当前重建 | 3.0.4 | [infra.md](../07-components/infra.md#infraiam-casdoor) | [BRICKKIT](../../../components/infra/iam-casdoor/BRICKKIT.md) · [AGENTS](../../../components/infra/iam-casdoor/AGENTS.md) · [design](../../../components/infra/iam-casdoor/docs/design.md) | — | 身份族的全部 51 个使用者（见边界卡） |
| `infra/iam-keycloak` | 身份认证适配（Keycloak） | 远期 | — | [infra.md](../07-components/infra.md#infraiam-keycloak) | — | — | 身份族的全部 51 个使用者（见边界卡） |
| `infra/authz` | 授权：权限目录、授予、视图与核验 | 当前重建 | 3.0.5 | [infra.md](../07-components/infra.md#infraauthz) | [BRICKKIT](../../../components/infra/authz/BRICKKIT.md) · [AGENTS](../../../components/infra/authz/AGENTS.md) · [design](../../../components/infra/authz/docs/design.md) | 身份（`infra/iam-*`） | 46 个组件（几乎全部业务组件，见各边界卡） |
| `infra/authz-static` | 授权的静态配置成员 | 远期 | — | — | — | — | — |
| `infra/authz-openfga` | 授权的关系图成员（OpenFGA） | 远期 | — | — | — | — | — |
| `infra/workflow` | 统一待办（不含流程引擎） | 当前重建 | — | [infra.md](../07-components/infra.md#infraworkflow) | — | 身份（`infra/iam-*`）、`infra/authz` | — |
| `infra/notification` | 通知意图、偏好与通道路由 | 当前重建 | — | [infra.md](../07-components/infra.md#infranotification) | — | 身份（`infra/iam-*`）、`infra/authz` | — |
| `infra/attachment` | 附件元数据、处理状态与授权协作 | 当前重建 | — | [infra.md](../07-components/infra.md#infraattachment) | — | 身份（`infra/iam-*`）、`infra/authz` | `hrm/expense` |
| `infra/print` | 单据与标签渲染 | 当前重建 | 设计中 | [infra.md](../07-components/infra.md#infraprint) | [design](../../../components/infra/print/docs/design.md) | 身份（`infra/iam-*`）、`infra/authz` | — |
| `infra/audit` | 业务审计的集中保存与查询；兼任独立证据存储 | 当前重建 | 3.0.3 | [infra.md](../07-components/infra.md#infraaudit) | [BRICKKIT](../../../components/infra/audit/BRICKKIT.md) · [AGENTS](../../../components/infra/audit/AGENTS.md) · [design](../../../components/infra/audit/docs/design.md) | 身份（`infra/iam-*`）、`infra/authz` | — |
| `infra/bff-mobile` | 移动端展示聚合 | 当前重建 | — | [infra.md](../07-components/infra.md#infrabff-mobile) | — | 身份（`infra/iam-*`） | `frontend/mobile` |
| `infra/dlq-monitor` | 死信观察、处理与审计 | 远期 | — | [infra.md](../07-components/infra.md#infradlq-monitor) | — | 身份（`infra/iam-*`）、`infra/authz` | — |

## 主数据

| 组件 ID | 能力 | 范围 | 实现 | 边界卡 | 组件文档 | 必需依赖 | 被谁必需依赖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `mdm/partner` | 业务伙伴：共有身份、客户／供应商／员工往来／关联方角色、正式联络资料、伙伴银行账户 | 当前重建 | 3.0.5 | [mdm.md](../07-components/mdm.md#mdmpartner) | [BRICKKIT](../../../components/mdm/partner/BRICKKIT.md) · [AGENTS](../../../components/mdm/partner/AGENTS.md) · [design](../../../components/mdm/partner/docs/design.md) | `mdm/org`、身份（`infra/iam-*`）、`infra/authz` | `crm/activity`、`crm/case`、`crm/customer`、`crm/lead`、`crm/opportunity`、`erp/billing`、`erp/contract`、`erp/credit`、`erp/finance`、`erp/intercompany`、`erp/payment`、`erp/purchase`、`erp/sales`、`erp/tax` |
| `mdm/product` | 产品、物料、单位换算、批次与序列追踪政策 | 当前重建 | 3.0.5 | [mdm.md](../07-components/mdm.md#mdmproduct) | [BRICKKIT](../../../components/mdm/product/BRICKKIT.md) · [AGENTS](../../../components/mdm/product/AGENTS.md) · [design](../../../components/mdm/product/docs/design.md) | `mdm/org`、身份（`infra/iam-*`）、`infra/authz` | `erp/contract`、`erp/costing`、`erp/inventory`、`erp/maintenance`、`erp/manufacturing`、`erp/planning`、`erp/purchase`、`erp/quality`、`erp/sales`、`erp/tax`、`erp/warehouse` |
| `mdm/org` | 法人、部门、岗位、汇报关系、地点、工作日历 | 当前重建 | 3.0.4 | [mdm.md](../07-components/mdm.md#mdmorg) | [BRICKKIT](../../../components/mdm/org/BRICKKIT.md) · [AGENTS](../../../components/mdm/org/AGENTS.md) · [design](../../../components/mdm/org/docs/design.md) | 身份（`infra/iam-*`）、`infra/authz` | `crm/case`、`erp/asset`、`erp/billing`、`erp/budget`、`erp/consolidation`、`erp/contract`、`erp/costing`、`erp/credit`、`erp/finance`、`erp/intercompany`、`erp/inventory`、`erp/maintenance`、`erp/manufacturing`、`erp/payment`、`erp/planning`、`erp/purchase`、`erp/sales`、`erp/tax`、`hrm/attendance`、`hrm/expense`、`hrm/leave`、`hrm/recruitment`、`mdm/employee`、`mdm/partner`、`mdm/product`、`prj/project` |
| `mdm/employee` | 员工、任职、员工与账号的映射 | 当前重建 | — | [mdm.md](../07-components/mdm.md#mdmemployee) | — | `mdm/org`、身份（`infra/iam-*`）、`infra/authz` | `crm/commission`、`crm/customer`、`hrm/appraisal`、`hrm/attendance`、`hrm/expense`、`hrm/leave`、`prj/timesheet` |
| `mdm/currency` | 币种、汇率类型与汇率 | 当前重建 | 3.0.5 | [mdm.md](../07-components/mdm.md#mdmcurrency) | [BRICKKIT](../../../components/mdm/currency/BRICKKIT.md) · [AGENTS](../../../components/mdm/currency/AGENTS.md) · [design](../../../components/mdm/currency/docs/design.md) | 身份（`infra/iam-*`）、`infra/authz` | `crm/commission`、`erp/asset`、`erp/billing`、`erp/budget`、`erp/consolidation`、`erp/contract`、`erp/costing`、`erp/credit`、`erp/finance`、`erp/payment`、`erp/purchase`、`erp/sales`、`hrm/expense`、`prj/project` |

## 交易与库存

| 组件 ID | 能力 | 范围 | 实现 | 边界卡 | 组件文档 | 必需依赖 | 被谁必需依赖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `erp/sales` | 报价、计价与销售订单；实物与服务共同基础 | 当前重建 | 设计中 | [erp-trade.md](../07-components/erp-trade.md#erpsales) | [design](../../../components/erp/sales/docs/design.md) | `mdm/partner`、`mdm/product`、`mdm/org`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | `erp/intercompany` |
| `erp/purchase` | 采购申请、订单与到货 | 当前重建 | — | [erp-trade.md](../07-components/erp-trade.md#erppurchase) | — | `mdm/partner`、`mdm/product`、`mdm/org`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | `erp/intercompany` |
| `erp/inventory` | 库存数量、预占与物理变动（唯一写入者） | 当前重建 | 设计中 | [erp-trade.md](../07-components/erp-trade.md#erpinventory) | [design](../../../components/erp/inventory/docs/design.md) | `mdm/product`、`mdm/org`、身份（`infra/iam-*`）、`infra/authz` | `erp/costing`、`erp/manufacturing`、`erp/planning`、`erp/quality`、`erp/warehouse` |
| `erp/contract` | 客户合同、客户与供应商的框架协议、订阅与周期出账计划（D70） | 远期 | — | [erp-trade.md](../07-components/erp-trade.md#erpcontract) | — | `mdm/partner`、`mdm/product`、`mdm/org`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/intercompany` | 公司间规则、对开单据与内部往来对账（D72） | 远期 | — | [erp-trade.md](../07-components/erp-trade.md#erpintercompany) | — | `erp/sales`、`erp/purchase`、`mdm/partner`、`mdm/org`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/planning` | 补货规则（再订货点、安全库存）、需求预测与物料需求计划（D71） | 远期 | — | [erp-trade.md](../07-components/erp-trade.md#erpplanning) | — | `erp/inventory`、`mdm/product`、`mdm/org`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/warehouse` | 可选的复杂仓库作业（波次、拣货、复核、打包） | 远期 | — | [erp-trade.md](../07-components/erp-trade.md#erpwarehouse) | — | `erp/inventory`、`mdm/product`、身份（`infra/iam-*`）、`infra/authz` | — |

## 财务与结算

| 组件 ID | 能力 | 范围 | 实现 | 边界卡 | 组件文档 | 必需依赖 | 被谁必需依赖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `erp/finance` | 总账、应收应付（含预收、预付、员工借款）、付款认领、核销、外币重估与期末暂估、维度目录与递延、会计期间；应付内部的供应商票据匹配 | 当前重建 | — | [erp-finance.md](../07-components/erp-finance.md#erpfinance) | — | `mdm/org`、`mdm/partner`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | `erp/consolidation` |
| `erp/credit` | 信用政策、额度与信用占用 | 当前重建 | 设计中 | [erp-finance.md](../07-components/erp-finance.md#erpcredit) | [design](../../../components/erp/credit/docs/design.md) | `mdm/partner`、`mdm/org`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/costing` | 存货计价与成本子账；暂估、到岸成本、工单成本与差异、退货冲回 | 当前重建 | — | [erp-finance.md](../07-components/erp-finance.md#erpcosting) | — | `erp/inventory`、`mdm/product`、`mdm/org`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/billing` | 客户账单与商业发票 | 当前重建 | 设计中 | [erp-finance.md](../07-components/erp-finance.md#erpbilling) | [design](../../../components/erp/billing/docs/design.md) | `mdm/partner`、`mdm/org`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/payment` | 收付款业务与银行／渠道对账 | 当前重建 | — | [erp-finance.md](../07-components/erp-finance.md#erppayment) | — | `mdm/partner`、`mdm/org`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/consolidation` | 集团结构、抵销、外币报表折算与合并报表（D72） | 远期 | — | [erp-finance.md](../07-components/erp-finance.md#erpconsolidation) | — | `erp/finance`、`mdm/org`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/tax` | 税计算 | 远期 | — | [erp-finance.md](../07-components/erp-finance.md#erptax) | — | `mdm/org`、`mdm/partner`、`mdm/product`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/budget` | 预算编制与控制，占用沿用预占分支 | 远期 | — | [erp-finance.md](../07-components/erp-finance.md#erpbudget) | — | `mdm/org`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | — |

## 生产与资产

| 组件 ID | 能力 | 范围 | 实现 | 边界卡 | 组件文档 | 必需依赖 | 被谁必需依赖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `erp/manufacturing` | BOM、生产工单与工序 | 远期 | — | [erp-production.md](../07-components/erp-production.md#erpmanufacturing) | — | `erp/inventory`、`mdm/product`、`mdm/org`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/quality` | 检验与不合格品 | 远期 | — | [erp-production.md](../07-components/erp-production.md#erpquality) | — | `erp/inventory`、`mdm/product`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/maintenance` | 设备维护与备件 | 远期 | — | [erp-production.md](../07-components/erp-production.md#erpmaintenance) | — | `mdm/product`、`mdm/org`、身份（`infra/iam-*`）、`infra/authz` | — |
| `erp/asset` | 固定资产、折旧、盘点与处置 | 远期 | — | [erp-production.md](../07-components/erp-production.md#erpasset) | — | `mdm/org`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | — |

## 客户关系

| 组件 ID | 能力 | 范围 | 实现 | 边界卡 | 组件文档 | 必需依赖 | 被谁必需依赖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `crm/lead` | 线索获取、去重与转化 | 远期 | — | [crm.md](../07-components/crm.md#crmlead) | — | `mdm/partner`、身份（`infra/iam-*`）、`infra/authz` | — |
| `crm/customer` | 销售归属、共享、公海与关系 | 远期 | — | [crm.md](../07-components/crm.md#crmcustomer) | — | `mdm/partner`、`mdm/employee`、身份（`infra/iam-*`）、`infra/authz` | — |
| `crm/opportunity` | 商机生命周期与预测 | 当前重建 | — | [crm.md](../07-components/crm.md#crmopportunity) | — | `mdm/partner`、身份（`infra/iam-*`）、`infra/authz` | — |
| `crm/activity` | 跟进、拜访与活动时间线 | 远期 | — | [crm.md](../07-components/crm.md#crmactivity) | — | `mdm/partner`、身份（`infra/iam-*`）、`infra/authz` | — |
| `crm/campaign` | 营销活动与归因 | 远期 | — | [crm.md](../07-components/crm.md#crmcampaign) | — | 身份（`infra/iam-*`）、`infra/authz` | — |
| `crm/case` | 客户服务、工单与服务目标 | 远期 | — | [crm.md](../07-components/crm.md#crmcase) | — | `mdm/partner`、`mdm/org`、身份（`infra/iam-*`）、`infra/authz` | — |
| `crm/commission` | 佣金规则与结算 | 远期 | — | [crm.md](../07-components/crm.md#crmcommission) | — | `mdm/employee`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | — |

## 人事与薪资

| 组件 ID | 能力 | 范围 | 实现 | 边界卡 | 组件文档 | 必需依赖 | 被谁必需依赖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `hrm/attendance` | 考勤、排班与加班 | 远期 | — | [hrm.md](../07-components/hrm.md#hrmattendance) | — | `mdm/employee`、`mdm/org`、身份（`infra/iam-*`）、`infra/authz` | — |
| `hrm/leave` | 请假与余额 | 远期 | — | [hrm.md](../07-components/hrm.md#hrmleave) | — | `mdm/employee`、`mdm/org`、身份（`infra/iam-*`）、`infra/authz` | — |
| `hrm/expense` | 费用报销与审批 | 远期 | — | [hrm.md](../07-components/hrm.md#hrmexpense) | — | `mdm/employee`、`mdm/org`、`mdm/currency`、`infra/attachment`、身份（`infra/iam-*`）、`infra/authz` | — |
| `hrm/recruitment` | 招聘流程 | 远期 | — | [hrm.md](../07-components/hrm.md#hrmrecruitment) | — | `mdm/org`、身份（`infra/iam-*`）、`infra/authz` | — |
| `hrm/appraisal` | 绩效目标与评价 | 远期 | — | [hrm.md](../07-components/hrm.md#hrmappraisal) | — | `mdm/employee`、身份（`infra/iam-*`）、`infra/authz` | — |
| `hrm/payroll-core` | 共用薪资模型（组件还是共用库，随第一个国家实现决定） | 远期 | — | — | — | — | — |

## 项目与分析

| 组件 ID | 能力 | 范围 | 实现 | 边界卡 | 组件文档 | 必需依赖 | 被谁必需依赖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `prj/project` | 项目计划、估算、成本的分析归集；按里程碑或按工时与费用出账 | 远期 | — | [prj.md](../07-components/prj.md#prjproject) | — | `mdm/org`、`mdm/currency`、身份（`infra/iam-*`）、`infra/authz` | — |
| `prj/timesheet` | 工时与审批（归集在项目） | 远期 | — | [prj.md](../07-components/prj.md#prjtimesheet) | — | `mdm/employee`、身份（`infra/iam-*`）、`infra/authz` | — |
| `ana/bi` | 数据集、指标与内置报表 | 远期（是否进入当前重建，随重建计划确认） | — | [ana.md](../07-components/ana.md#anabi) | — | 身份（`infra/iam-*`）、`infra/authz` | — |
| `ana/search` | 全局搜索索引与查询 | 远期 | — | [ana.md](../07-components/ana.md#anasearch) | — | 身份（`infra/iam-*`）、`infra/authz` | — |
| `ana/ai` | 业务 AI 能力 | 留位 | — | [ana.md](../07-components/ana.md#anaai) | — | — | — |

## 外部渠道与集成

| 组件 ID | 能力 | 范围 | 实现 | 边界卡 | 组件文档 | 必需依赖 | 被谁必需依赖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `integration/im-dingtalk` | 钉钉消息与回调 | 当前重建 | — | — | — | — | — |
| `integration/edi` | 供应链数据交换 | 远期 | — | — | — | — | — |
| `integration/print-agent` | 客户现场的打印代理 | 远期 | — | — | — | — | — |

## 使用入口

| 组件 ID | 能力 | 范围 | 实现 | 边界卡 | 组件文档 | 必需依赖 | 被谁必需依赖 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `frontend/pc` | PC 办公入口 | 当前重建 | — | [frontend.md](../07-components/frontend.md#frontendpc) | — | 身份（`infra/iam-*`） | — |
| `frontend/mobile` | 移动外勤入口 | 当前重建 | — | [frontend.md](../07-components/frontend.md#frontendmobile) | — | `infra/bff-mobile`、身份（`infra/iam-*`） | — |
| `frontend/terminal` | 仓库终端入口 | 远期 | — | [frontend.md](../07-components/frontend.md#frontendterminal) | — | 身份（`infra/iam-*`） | — |
| `frontend/advanced` | 行业或高级交互入口 | 远期 | — | [frontend.md](../07-components/frontend.md#frontendadvanced) | — | — | — |

## 外壳

已按新设计重建的外壳与它们编进的成员（外壳只把几个成员合进一个进程，见[部署与运行](../04-foundations/01-deployment-and-runtime.md)）。成员的版本是外壳编进的版本，可能落后于组件自己的最新版本。

| 外壳 | 版本 | 编进的成员 | 文档 |
| --- | --- | --- | --- |
| `be/go-core` | 3.0.19 | `test/probe-go@3.2.19`、`test/probe-go2@3.2.19`、`test/probe-go3@3.2.19`、`test/probe-go4@3.2.19` | [BRICKKIT](../../../shell/be/go-core/BRICKKIT.md) · [AGENTS](../../../shell/be/go-core/AGENTS.md) |
| `be/go-infra` | 3.0.25 | `test/probe-go@3.2.19`、`test/probe-go2@3.2.19`、`test/probe-go3@3.2.19`、`test/probe-go4@3.2.19`、`infra/iam-casdoor@3.0.3`、`infra/authz@3.0.4`、`infra/audit@3.0.3`、`mdm/org@3.0.3`、`mdm/currency@3.0.4`、`mdm/partner@3.0.4`、`mdm/product@3.0.4` | [BRICKKIT](../../../shell/be/go-infra/BRICKKIT.md) · [AGENTS](../../../shell/be/go-infra/AGENTS.md) |
| `be/py-render` | 3.0.19 | `test/probe-py@3.2.19`、`test/probe-py2@3.2.19` | [BRICKKIT](../../../shell/be/py-render/BRICKKIT.md) · [AGENTS](../../../shell/be/py-render/AGENTS.md) |

## 事件

已重建组件在 `component.yaml` 的 `events` 里声明的发布与订阅（`brickkit deps` 给出同一张表）。订阅项以 `*` 结尾时匹配以它前面那一段开头的全部事件。

- 订阅者一栏的“—”是“已重建的组件都没有声明订阅它”；还没重建的组件将来是否订阅，看它们的边界卡与协议。
- 订阅者不是全部受影响的组件：完整状态事件的载荷通常也是发布方来源方法（`SourceService`）返回的数据，经来源方法读它的依赖方同样受影响，看上面各表的“被谁必需依赖”。

| 事件 | 发布者 | 订阅者 |
| --- | --- | --- |
| `mdm.currency.changed.v1` | `mdm/currency` | — |
| `mdm.exchange_rate.published.v1` | `mdm/currency` | — |
| `mdm.legal_entity.changed.v1` | `mdm/org` | — |
| `mdm.org_unit.changed.v1` | `mdm/org` | — |
| `mdm.partner.changed.v1` | `mdm/partner` | — |
| `mdm.partner_role.changed.v1` | `mdm/partner` | — |
| `mdm.product.changed.v1` | `mdm/product` | — |
| `mdm.product_category.changed.v1` | `mdm/product` | — |
| `mdm.rate_type.changed.v1` | `mdm/currency` | — |
