# 阶段计划：按依赖顺序重建其余组件

> 2026-11-10 起，按 `f-plan`。维护者 2026-11-10 确认底层先行第 6 项的门槛（底层六项全部通过），并定下一阶段“按依赖顺序重建”。依据：[重建计划](rebuild-plan.md)“顺序”第 3 项的后半（主数据 → 交易、库存与财务 → 支撑组件 → 分析与前端）。推进方式照根 `AGENTS.md`：连续推进，每个任务做完写记录、更新交接、提交；仓库的新建、改名、挪分支先列动作等维护者确认（C0）。

## 范围

组件索引里“当前重建”的 25 个组件已实现 12 个（`infra/iam-casdoor`、`infra/authz`、`infra/audit`、`infra/print`、`mdm/org`、`mdm/currency`、`mdm/partner`、`mdm/product`、`erp/sales`、`erp/inventory`、`erp/credit`、`erp/billing`），这一阶段做其余 13 个：

| 组件 | 必需依赖（组件索引） | 仓库现状 | 语言 |
| --- | --- | --- | --- |
| `mdm/employee` | `mdm/org`、身份、授权 | 无仓库 | Go |
| `erp/purchase` | 四个主数据、身份、授权 | `brickKit/erp-purchase`（2026-11-10 建，维护者同意） | Go |
| `erp/payment` | `mdm/partner`、`mdm/org`、`mdm/currency`、身份、授权 | 无仓库 | Go |
| `erp/finance` | `mdm/org`、`mdm/partner`、`mdm/currency`、身份、授权 | 旧代码 v2.0.0 在 `main` | Go |
| `erp/costing` | `erp/inventory`、`mdm/product`、`mdm/org`、`mdm/currency`、身份、授权 | 无仓库 | Go |
| `crm/opportunity` | `mdm/partner`、身份、授权 | 旧代码 v2.0.0 在 `main` | Go |
| `infra/workflow` | 身份、授权 | 旧代码 v2.0.1 在 `main` | Go |
| `infra/notification` | 身份、授权 | 旧代码 v2.0.0 在 `main` | Go |
| `infra/attachment` | 身份、授权 | 无仓库（端口已登记） | Go |
| `integration/im-dingtalk` | — | 旧代码 v2.0.0 在 `main` | Go |
| `infra/bff-mobile` | 身份 | 旧代码 2.0.0（TypeScript）在 `main` | Go（A108） |
| `frontend/pc` | 身份 | `frontend-standard` 旧代码 v1.0.1，改名后复用（D17） | 前端技术栈（协议 20） |
| `frontend/mobile` | `infra/bff-mobile`、身份 | 无仓库 | 前端技术栈（协议 20） |

语言是 AI 按锁定的技术栈与 A108 的初判，每个组件开工时按它的边界卡核对；与边界卡不一致的先问。远期、留位、评估的组件不在这一阶段。

## 任务

每个组件按改动的循环做（意图 → 考设计 → 契约 → 先写红的测试 → 实现 → 核对 → 发布），新组件照[改动配方](../../docs/zh/01-conventions/11-change-recipes.md)的“新组件”与标准布局（`make layout-check`）；旧仓库里的 2.x 代码只作参考（D59），不迁移。

| # | 要做到什么 | 依据 | 依赖 | 验收 | 状态 |
| --- | --- | --- | --- | --- | --- |
| C0 | 仓库动作：旧代码挪到 `legacy/`、主分支重新开始、改名、新建、注册表追加、`.gitmodules`（下面“C0 的动作”） | 重建计划的原则 1–4 | — | 维护者确认后执行，结果写在本节末尾 | ✅ 2026-11-10（维护者“执行”；新仓库在各自开工时建） |
| C1 | `mdm/employee`：员工、任职、员工与账号的映射；种子数据（每个法人有员工、够翻页） | 边界卡 `mdm.md`、协议 14 | C0 | 组件的 L1–L2 与集成测试、改坏检查；真机格从空库到 L3 | ✅ 2026-11-10：`mdm/employee` 3.0.3、`infra/authz` 3.0.48（关联的确认、按人判断、任职绑定），全系统 be-sdk-go alpha.121；子计划 [c1-employee-plan.md](c1-employee-plan.md) |
| C2 | `erp/purchase`：采购的单据链（申请、订单、收货、退货），与库存、开票的事件 | 边界卡 `erp.md`、业务流程 | C0 | 同上；采购到入库的 L3 场景 | ✅ 2026-11-10：`erp/purchase` 3.0.1，格 C2-P 从空库到 L3（子计划 [c2-purchase-plan.md](c2-purchase-plan.md)；源头补了 `mdm/partner` 3.0.40、`erp/inventory` 3.0.37、`mdm/product` 3.0.38、`infra/iam-casdoor` 3.0.44） |
| C3 | `erp/payment`：收付款、核销；对外支付走对外命令（第 13 章） | 边界卡、协议 15 的对外命令 | C0 | 同上；收款核销开票的 L3 | 进行中：子计划 [c3-payment-plan.md](c3-payment-plan.md)（P0 起草；仓库等建） |
| C4 | `erp/finance`：总账、凭证、期间与关账；消费开票、付款、库存的过账事件 | 边界卡、业务流程 | C2、C3 | 同上；从订单到凭证的 L3 | ⬜ |
| C5 | `erp/costing`：存货成本（消费库存移动） | 边界卡 | C0 | 同上 | ⬜ |
| C6 | `crm/opportunity`：商机到销售订单 | 边界卡 `crm.md` | C0 | 同上；商机赢单到订单的 L3 | ⬜ |
| C7 | `infra/workflow`：统一待办（不含流程引擎） | 边界卡 `infra.md`、支撑能力指南 | C0 | 同上；待办的数据范围（协议的安全 07） | ⬜ |
| C8 | `infra/notification`：通知意图、偏好与通道路由 | 同上 | C0 | 同上 | ⬜ |
| C9 | `infra/attachment`：附件元数据、处理状态与授权协作 | 同上 | C0 | 同上 | ⬜ |
| C10 | `integration/im-dingtalk`：钉钉投递（外部系统用模拟器） | 边界卡 | C8 | 同上；外部调用走对外命令或幂等 | ⬜ |
| C11 | `infra/bff-mobile`：移动端展示聚合（Go，gqlgen 挂在 Gin 上，A108） | 边界卡、协议 20 | C1–C8 中它聚合的组件 | 同上 | ⬜ |
| C12 | `frontend/pc` | 协议 20、前端技术栈 | 要显示的组件 | FE-1–FE-4 | ⬜ |
| C13 | `frontend/mobile` | 同上 | C11 | FE-1–FE-4 | ⬜ |
| C14 | 阶段收尾：全部组件的真机格（单跑与外壳两格）从空库到 L3、整套恢复演练、`make gates` 与 `make version-check`；复盘 | 实验计划的格 | 全部 | 两格与演练通过；复盘写好 | ⬜ |

每个组件开工的第一步列出它需要、而已重建的源头组件还没做的能力（C1 发现 `mdm/org` 的岗位、`mdm/partner` 的员工往来与供应商角色都还答“能力不支持”），先回源头补，再做组件本身。C1–C3、C5–C9 只依赖已重建的组件与 C0，可以按编号顺序一个一个做（一次一个组件，做完发布再下一个）。每个组件开工前用 `brickkit-plan-change` 的思路核对边界与已有决定，有要维护者定的业务问题时一次问一个。

**全局约束**：

- 全部 Go 组件用系统里同一个 be-sdk-go 版本（现在 alpha.119；有新版本时 `sdk-unify.py` 一起换）。
- 新组件的种子数据照“种子数据要丰富到下游直接用”；测试数据进测试库。
- 每个组件发布后，依赖它的外壳与格跟着换（pin-check 会点出）。
- 长任务（全部集成测试、真机格、演练）放后台配监视（`f-longrun`）；格脚本用 `experiment-scripts/cellenv.sh`，失败时不关格（第 6 项复盘 P3、P4）。

**完成标准**：13 个组件都发布、在组件索引里有版本；C14 的格与演练通过；容器关掉；走不通的尝试留下的东西清理掉。

## C0 的动作（维护者 2026-11-10 确认“执行”）

现状 2026-11-10 查过：下列旧仓库的工作区干净、与远端一致，远端都还没有 `legacy/` 分支。

**A. 旧代码挪到 `legacy/` 分支，主分支重新开始**（照实验第 1 步的做法：从旧代码的最新提交建分支并推送；主分支在原历史上加一个提交 “Restart main for the final design”，删掉旧文件，只留说明新设计与 `legacy/` 分支的 README；不改写历史、不强推，旧标签保留）：

| 仓库 | 旧代码取自 | 新分支 |
| --- | --- | --- |
| `erp-finance` | `main`（v2.0.0） | `legacy/v2` |
| `crm-opportunity` | `main`（v2.0.0） | `legacy/v2` |
| `infra-workflow` | `main`（v2.0.1） | `legacy/v2` |
| `infra-notification` | `main`（v2.0.0） | `legacy/v2` |
| `integration-im-dingtalk` | `main`（v2.0.0） | `legacy/v2` |
| `infra-bff-mobile` | `main`（2.0.0，TypeScript） | `legacy/v2` |
| `frontend-standard`（改名后 `frontend-pc`） | `main`（v1.0.1） | `legacy/v1` |

**B. 改名**（维护者 2026-10-15 已授权，不再单独确认）：`frontend-standard` → `frontend-pc`（D17）；子模块路径 `components/frontend/standard` → `components/frontend/pc`。

**C. 新建仓库（6 个）**：`mdm-employee`、`erp-purchase`、`erp-payment`、`erp-costing`、`infra-attachment`、`frontend-mobile`，在 `brickKit` 组织下、公开（与现有仓库一致），主分支只有一个说明 README 的初始提交；各自在任务开工时才建，不提前建空仓库。

**D. 注册表**（`registry/`，只追加）：端口与 schema 追加 `mdm/employee`、`erp/payment`、`erp/costing`、`frontend/pc`、`frontend/mobile`（`erp/purchase`、`infra/attachment` 已有端口）；`frontend/standard` 的行标为退役；权限键在各组件的定义里登记（`make authz-keys-check`）。

**E. `.gitmodules`**：新建的仓库各加一个子模块；`frontend/standard` 换成 `frontend/pc`。子模块指针只经 `git submodule` 改。

### C0 的结果（2026-11-10）

- **A**：7 个仓库的旧代码各在新分支（推送）：`erp-finance` `legacy/v2` 在 `4a2ee5a`，`crm-opportunity` 在 `255a87a`，`infra-workflow` 在 `0f76e60`，`infra-notification` 在 `d207ce9`，`integration-im-dingtalk` 在 `ce794c9`，`infra-bff-mobile` 在 `b074a1f`，`frontend-pc` `legacy/v1` 在 `607a204`；各自的 `main` 加了一个 “Restart main for the final design” 提交，只留说明 README（指向边界卡与 `legacy/` 分支）。没有改写历史、没有强推，旧标签都在。
- **B**：GitHub 上 `frontend-standard` 改名为 `frontend-pc`（旧名跳转）；子模块路径 `components/frontend/standard` → `components/frontend/pc`（`git mv`，子模块名照 `mdm-partner` 的先例保留原名），远端地址改为 `frontend-pc`。现行内容里按旧名说现状的两处注释（`infra/scripts/test-db-init.sh`、`infra/traefik/traefik.yml`）改了；正式文档里“原 `frontend/standard` 拆成……”的设计说明照旧。
- **D**：`registry/ports.tsv` 追加 `mdm/employee` 8227/9227（go-infra）、`erp/payment` 8228/9228、`erp/costing` 8229/9229（go-core）、`frontend/pc`、`frontend/mobile`；`frontend/standard` 标为退役；`schemas.tsv` 追加三个 schema。`make registry-check` 过（75 个在用、4 个退役）。
- **检查跟着补的**：`version-check.sh` 原来把刚重启的仓库报成“HEAD 领先最新标签”；加一条：HEAD 就是重启那个提交的仓库不查（有了第一个 3.x 提交就照常查）。`make gates`、`make version-check` 全过。
- **C、E**：新仓库与它们的子模块在各自的任务开工时建。

