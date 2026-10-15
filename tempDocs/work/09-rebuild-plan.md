# 重建计划（草稿，执行前须用户确认）

> 2026-10-15 起草。依据 D59（按新设计从零重建）与用户 2026-10-15 的要求：“全部设计完毕以后，我们再看看哪些是可以重复利用的，然后把不可以利用的直接改仓库名，进行归档，然后去真实构建我们需要的仓库”。本页只列清单与原则，**不执行**：仓库的改名、归档与新建在设计冻结、用户确认本清单之后进行。

## 原则

1. **组件 ID 不变的，沿用仓库**：在原仓库上开新的主版本（组件 3.0.0、外壳 2.0.0，具体号随发布规则），新主版本的代码按新设计从零写，旧版本的标签与历史保留作参考。这样注册表中的身份、端口与 schema 不变（注册表只追加），外部引用不断。
2. **组件 ID 变了或被拆分的，旧仓库归档、新建仓库**：旧仓库在 GitHub 上改名为 `archived-<原名>` 并设为归档（只读），README 写明去向；新身份在注册表登记后新建仓库。
3. **工具与协议仓库沿用**：按协议 18、21 的分工重写内容（新主版本）。
4. 每一步执行前列出将要做的具体动作（改名、归档、新建、注册表追加、`.gitmodules` 变化），用户确认后再做；远端的改名与归档不可轻易撤回。

## 现有仓库的去向

| 现有仓库（子模块路径） | 组件 ID | 去向 | 说明 |
| --- | --- | --- | --- |
| `mdm-customer`（`components/mdm/customer`） | `mdm/customer` | 归档 | 由 `mdm/partner` 取代（D20）；新建 `mdm-partner` |
| `mdm-product` | `mdm/product` | 沿用，新主版本重建 | — |
| `erp-inventory` | `erp/inventory` | 沿用，新主版本重建 | 预占改为分支协议（协议 04） |
| `erp-finance` | `erp/finance` | 沿用，新主版本重建 | 信用、成本、出账、收付款拆到新组件（D03、D46–D48） |
| `erp-sales` | `erp/sales` | 沿用，新主版本重建 | — |
| `infra-authz` | `infra/authz` | 沿用，新主版本重建 | 安全 01–10 |
| `infra-iam-casdoor` | `infra/iam-casdoor` | 沿用，新主版本重建 | 安全 02、03、11，协议 20 |
| `infra-workflow` | `infra/workflow` | 沿用，新主版本重建 | 职责收窄为统一待办（D19、D68） |
| `infra-notification` | `infra/notification` | 沿用，新主版本重建 | — |
| `integration-im-dingtalk` | `integration/im-dingtalk` | 沿用，新主版本重建 | 动作令牌回调（协议 10） |
| `infra-print` | `infra/print` | 沿用，新主版本重建 | — |
| `infra-bff-mobile` | `infra/bff-mobile` | 沿用，新主版本重建 | — |
| `frontend-standard` | `frontend/standard` | 归档 | 拆为 `frontend-pc`、`frontend-mobile`（D17） |
| `crm-opportunity` | `crm/opportunity` | 沿用，新主版本重建 | — |
| `be-go-core`、`be-go-infra`、`be-go-backoffice`、`be-py-render`（`shell/be/*`） | 外壳 | 沿用 | 成员组合在代表部署实验后确定（D40）；先保留仓库，实验时再定是否增减外壳 |
| `be-sdk-go`、`be-sdk-python`、`be-sdk-ts` | SDK | 沿用，新主版本重建 | 协议 18 的共同契约与语义向量 |
| `be-protocol` | 组件协议 | 沿用，按协议 18 的章节重写 | 规则（必须、应当、内部）与语义向量 |
| `be-acceptance` | 验收与套件 | 沿用 | 迁入验收矩阵（PA、DT、ST）、一致性套件、参考模型与文档检查脚本 |
| `be-ops` | 装配时生成 | 沿用，评估后重写 | 权限与数据范围的注册改为资源定义（安全 09a）；菜单汇总退役（协议 20） |
| `contract-infra-authz`、`contract-infra-iam` | 契约仓库 | 沿用，新主版本 | 按安全 09a 与协议 18 的契约重写 |

## 当前重建范围需要新建的仓库

按[组件全景的当前重建范围](../final/00-overview/03-catalog.md)，以下组件没有现成仓库：

| 新仓库 | 组件 ID | 依据 |
| --- | --- | --- |
| `mdm-partner` | `mdm/partner` | D20、D21、D69 |
| `mdm-org` | `mdm/org` | D04、D05 |
| `mdm-employee` | `mdm/employee` | D06 |
| `mdm-currency` | `mdm/currency` | 主数据卡 |
| `erp-purchase` | `erp/purchase` | D63 |
| `erp-credit` | `erp/credit` | D03 |
| `erp-costing` | `erp/costing` | D46 |
| `erp-billing` | `erp/billing` | D48 |
| `erp-payment` | `erp/payment` | D47 |
| `infra-attachment` | `infra/attachment` | D53、协议 12 |
| `infra-audit` | `infra/audit` | 协议 03、15 |
| `ana-bi` | `ana/bi` | D52、协议 13 |
| `frontend-pc` | `frontend/pc` | D17 |
| `frontend-mobile` | `frontend/mobile` | D17 |

每个新身份先在 `registry/` 追加组件 ID、端口、schema 与数据库角色（协议 19 的注册表规则），再建仓库。

## 顺序

1. 设计冻结，用户确认冻结报告与本清单。
2. 代表部署实验（D41）：先在 SDK、协议、验收仓库补最小条件，用少量代表组件做部署对照。实验需要的组件按上表先行。
3. 按实验结果修订设计后，按依赖顺序重建当前范围：SDK 与协议 → 授权与身份 → 主数据 → 交易、库存与财务 → 支撑组件 → 分析与前端。
4. 用重建后的组件跑完整部署矩阵（路线第 4 步）。
5. 归档与改名：重建的新仓库可用后，再对被取代的旧仓库执行改名与归档，避免中途断掉参考。

## 待用户确认

- 原则 1（同 ID 沿用仓库、开新主版本）与原则 2（换 ID 归档、新建）。
- 归档仓库的命名（`archived-<原名>`）与是否在 GitHub 上设为只读。
- 外壳仓库在实验前是否先保留不动。
