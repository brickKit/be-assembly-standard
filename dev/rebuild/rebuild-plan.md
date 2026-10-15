# 重建计划（执行前每一步须用户确认）

> 2026-10-15 起草。依据 D59（按新设计从零重建）与用户 2026-10-15 的要求：“全部设计完毕以后，我们再看看哪些是可以重复利用的，然后把不可以利用的直接改仓库名，进行归档，然后去真实构建我们需要的仓库”。本页只列清单与原则，**不执行**：仓库的改名、归档与新建在设计冻结、用户确认本清单之后进行。
>
> 2026-10-15 设计冻结后用户补充：“所有的原仓库都可以复用么？反正不管可不可以，你都可以根据情况重新开始，只要把老的代码放到一个特定的 branch 就行。”据此原则改为全部复用原仓库，旧代码挪到固定分支，不再归档旧仓库。

## 原则

1. **全部原仓库复用，旧代码挪到固定分支**：每个原仓库把当前主分支的代码挪到分支 `legacy/v<旧主版本>`：组件 `legacy/v2`，外壳 `legacy/v1`，工具（SDK、`be-acceptance`、`be-ops`，旧版本都是 0.x）`legacy/v0`；主分支从零开始。版本从头算（A107，用户 2026-10-16 同意）：开发期 `0.x`，第一个正式版本 `1.0.0`；旧标签全部删除，本机旧镜像与 Go 模块缓存清空，Go 构建设 `GOPRIVATE=github.com/brickKit/*`。删除旧标签后，根项目 `brickkit.yaml` 钉住的 2.0.x 取不到，旧的整套装配不再启动（没有使用者，用户确认无妨）。
2. **组件 ID 变了的，改名后复用**：`mdm-customer` 改名为 `mdm-partner`（D20），`frontend-standard` 改名为 `frontend-pc`（D17）；GitHub 保留旧名的跳转。新 ID 在注册表追加，旧 ID 的行标为退役（注册表只追加、不删除）。拆分出来没有原仓库的（`frontend-mobile`）与全新的组件，新建仓库。
3. **工具与协议仓库复用**：按协议 18、21 的分工重写内容（新主版本），同样先把旧代码挪到 `legacy/` 分支。
4. 每一步执行前列出将要做的具体动作（挪分支、改名、新建、注册表追加、`.gitmodules` 变化），用户确认后再做；远端的改名不可轻易撤回。

## 现有仓库的去向

| 现有仓库（子模块路径） | 组件 ID | 去向 | 说明 |
| --- | --- | --- | --- |
| `mdm-customer`（`components/mdm/customer`） | `mdm/customer` → `mdm/partner` | 改名为 `mdm-partner` 后复用 | D20；旧代码挪到 `legacy/v2`；子模块路径改为 `components/mdm/partner` |
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
| `frontend-standard` | `frontend/standard` → `frontend/pc` | 改名为 `frontend-pc` 后复用 | D17；旧代码挪到 `legacy/v2`；`frontend-mobile` 新建 |
| `crm-opportunity` | `crm/opportunity` | 沿用，新主版本重建 | — |
| `be-go-core`、`be-go-infra`、`be-go-backoffice`、`be-py-render`（`shell/be/*`） | 外壳 | 沿用 | 成员组合在代表部署实验后确定（D40）；先保留仓库，实验时再定是否增减外壳 |
| `be-sdk-go`、`be-sdk-python`、`be-sdk-ts` | SDK | 沿用，新主版本重建 | 协议 18 的共同契约与语义向量 |
| `be-protocol` | 组件协议 | 沿用，按协议 18 的章节重写 | 规则（必须、应当、内部）与语义向量 |
| `be-acceptance` | 验收与套件 | 沿用 | 迁入验收矩阵（PA、DT、ST）、一致性套件、参考模型与文档检查脚本 |
| `be-ops` | 装配时生成 | 沿用，评估后重写 | 权限与数据范围的注册改为资源定义（安全 09a）；菜单汇总退役（协议 20） |
| `contract-infra-authz`、`contract-infra-iam` | 契约仓库 | 沿用，新主版本 | 按安全 09a 与协议 18 的契约重写 |

## 当前重建范围需要新建的仓库

按[组件全景的当前重建范围](../../docs/zh/00-overview/03-catalog.md)，以下组件没有现成仓库：

| 新仓库 | 组件 ID | 依据 |
| --- | --- | --- |
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
| `frontend-mobile` | `frontend/mobile` | D17 |

每个新身份先在 `registry/` 追加组件 ID、端口、schema 与数据库角色（协议 19 的注册表规则），再建仓库。

## 顺序

1. 设计冻结，用户确认冻结报告与本清单。
2. 代表部署实验（D41）：先在 SDK、协议、验收仓库补最小条件，用少量代表组件做部署对照。实验需要的组件按上表先行。具体计划见 [experiment-plan.md](experiment-plan.md)（待用户审）。
3. 按实验结果修订设计后，按依赖顺序重建当前范围：SDK 与协议 → 授权与身份 → 主数据 → 交易、库存与财务 → 支撑组件 → 分析与前端。
4. 用重建后的组件跑完整部署矩阵（路线第 4 步）。
5. 根项目切换：根项目在代表部署实验时就改为装配新组件（旧版本已取不到）；重建完成后各组件发布 `1.0.0`。`legacy/` 分支保留，不归档。

## 已确认

- 旧代码所在分支统一为 `legacy/v<旧主版本>`（用户 2026-10-15：“同意”）：组件 `legacy/v2`，外壳 `legacy/v1`；工具仓库的旧版本是 0.x，按同一原则是 `legacy/v0`（起初误写为 `legacy/v1`，迁移时核对标签后更正，用户 2026-10-15 确认）。
- 版本从头算、删除旧标签与旧镜像（用户 2026-10-16：“同意”；A107）。删除的清单在执行那一步列出确认。
- 仓库改名不需要再确认（用户 2026-10-15：“改名字你不需要我的确认”）：`mdm-customer` → `mdm-partner`、`frontend-standard` → `frontend-pc` 执行到时直接办理，事后在汇报中说明。

## 待用户确认

- 外壳仓库在代表部署实验前是否先保留不动（不挪分支，等实验确定成员组合再重写）。
- 挪分支、新建仓库、注册表追加与 `.gitmodules` 变化，仍按原则 4 每一步先列动作再确认。
