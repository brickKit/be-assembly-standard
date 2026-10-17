# 实验第 1 步：仓库动作清单（待用户确认）

> 2026-10-17 起草。依据 [rebuild-plan.md](rebuild-plan.md) 的原则与 [experiment-plan.md](experiment-plan.md) 第 1 步“列出挪分支、改名、新建、注册表追加、`.gitmodules` 变化，以及要删的本机旧镜像，确认后执行”。只动实验用到的仓库；其余仓库在各自重建时再动。现状是 2026-10-17 查到的：所列仓库的工作区都干净、与远端一致。

## A. 旧代码挪到 `legacy/` 分支，主分支重新开始（15 个仓库）

做法照 `be-acceptance` 已有的先例：从旧代码的最新提交建 `legacy/v<旧主版本>` 并推送；主分支在原历史上加**一个**提交“Restart main for the final design”，删掉旧文件，只留说明新设计与 `legacy/` 分支的 README。**不改写历史、不强推**；旧标签全部保留。

| 仓库 | 旧代码取自 | 新分支 | 说明 |
| --- | --- | --- | --- |
| `infra-iam-casdoor` | `main`（v2.0.0） | `legacy/v2` | |
| `infra-authz` | `main`（v2.0.1） | `legacy/v2` | |
| `mdm-customer`（改名后 `mdm-partner`） | `main`（v2.0.1） | `legacy/v2` | 改名见 B |
| `mdm-product` | `main`（v2.0.0） | `legacy/v2` | |
| `erp-sales` | `main`（v2.0.0） | `legacy/v2` | |
| `erp-inventory` | `main`（v2.0.0） | `legacy/v2` | |
| `infra-print` | `main`（2.0.0） | `legacy/v2` | |
| `be-go-core`、`be-go-infra`、`be-py-render` | `main`（没有标签） | `legacy/v1` | 计划已定 |
| `be-sdk-go`、`be-sdk-python` | **`stage-b`**（比 `main` 多 36、21 个提交，已推送） | `legacy/v0` | 最新的旧代码在 `stage-b`；`stage-b` 分支原样保留 |
| `be-protocol` | `main`（v1.0.0-rc.2，冻结前的旧规范） | `legacy/v1` | 旧版本是 1.0.0 的预发布 |
| `contract-infra-authz` | `main`（v2.0.0-rc.2） | `legacy/v2` | 计划说按预发布标签定分支名 |
| `contract-infra-iam` | `main`（v1.0.0-rc.2） | `legacy/v1` | 同上 |

**不动**：`be-acceptance`（设计阶段已重启主分支，旧代码在 `legacy/v0`）；`be-ops`（计划：先评估，能用注册表加脚本解决就不动）；`be-sdk-ts`（A108）；`be-go-backoffice`；当前装配里其余旧组件（`erp-finance`、`infra-workflow`、`infra-notification`、`integration-im-dingtalk`、`infra-bff-mobile`、`crm-opportunity`、`frontend-standard`），到各自重建时再动。

## B. 改名（1 个，按用户 2026-10-15 的授权不再单独确认）

`mdm-customer` → `mdm-partner`（D20）。GitHub 保留旧名的跳转，旧标签与 `go get` 的旧路径照常可用。

## C. 新建仓库（5 个）

`infra-audit`、`mdm-org`、`mdm-currency`、`erp-credit`、`erp-billing`：在 `brickKit` 组织下新建，**公开**（与现有仓库一致），主分支只有一个说明 README 的初始提交；内容从第 2 步之后按计划逐步写。探针放在 `be-acceptance` 的子目录（0-03），不建仓库。

## D. 注册表（本仓库 `registry/`）

- 追加端口与 schema：`mdm/currency`、`mdm/partner`、`erp/credit`、`erp/billing`、探针 `test/probe-go`、`test/probe-py`。`mdm/org`、`infra/audit` 与沿用的组件已经登记过，不改。
- `mdm/customer` 的行标为退役（身份列只追加、不删除），`mdm/partner` 另起新行。
- `schemas.tsv` 按协议 14 增加“属主角色”“运行角色”两列（每个组件两个角色）；已有行补值，身份列不改。
- 修 `registry/README` 里指向已不存在的 `07-registries.md` 的链接。
- 改完跑注册表检查。

## E. 本仓库的子模块（`.gitmodules`）

- 新增 5 个子模块：`components/infra/audit`、`components/mdm/org`、`components/mdm/currency`、`components/erp/credit`、`components/erp/billing`，指向 C 新建的仓库。
- 已有子模块的**指针暂不移动**：根项目的 `brickkit.yaml` 还钉着旧的 2.x 装配，指针一动它就跑不起来；第 8 步实验装配时再随 `brickkit upgrade` 一起移动。`mdm-customer` 的路径改成 `components/mdm/partner` 也放到那时。
- 子模块只经 `git submodule` 命令改（项目约定）。

## F. 删除的本机旧镜像

- Docker：`brickenterprise/*`（旧的 2.x 组件与旧外壳，约 23 个标签）与实验桩的 `demo-*`。旧装配以后如果要跑，可以从旧标签重新构建。
- minikube 节点里的同一批旧镜像；Podman 里的 `demo-*`。
- 保留基础镜像（postgres、nats、golang、python、alpine 等）与 `make up` 的基础资源。

## 执行顺序与可撤回性

B 改名 → A 挪分支与重启主分支 → C 新建 → D 注册表 → E 子模块 → F 镜像。除改名外都可以撤回：新分支可删、重启提交可回退、新仓库可删、本仓库的改动是普通提交；镜像删了可以重建。每做完一组在本页记录结果。
