# 实验第 1 步：仓库动作清单（已执行）

> 2026-10-17 起草，用户当天确认“执行”，当天执行完毕（结果见末节）。依据 [rebuild-plan.md](rebuild-plan.md) 的原则与 [experiment-plan.md](experiment-plan.md) 第 1 步“列出挪分支、改名、新建、注册表追加、`.gitmodules` 变化，以及要删的本机旧镜像，确认后执行”。只动实验用到的仓库；其余仓库在各自重建时再动。现状是 2026-10-17 查到的：所列仓库的工作区都干净、与远端一致。

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

## 执行结果（2026-10-17）

| 组 | 结果 |
| --- | --- |
| B 改名 | `mdm-customer` → `mdm-partner`；旧名跳转有效 |
| A 挪分支与重启 | 15 个仓库都推送了 `legacy` 分支，指向预期的旧提交：组件 7 个 `legacy/v2`（`infra-iam-casdoor` 87d1cb3、`infra-authz` 7b3f823、`mdm-partner` e788477、`mdm-product` 51cff19、`erp-sales` 4937ee5、`erp-inventory` 4ffb7c2、`infra-print` 56f5996）；外壳 3 个 `legacy/v1`（`be-go-core` f599168、`be-go-infra` 43f3298、`be-py-render` 30d43c2）；`be-sdk-go` c0e4fbc、`be-sdk-python` d2bcb0e 取自 `stage-b`（`legacy/v0`，`stage-b` 原样保留）；`be-protocol` 7838476（`legacy/v1`）；`contract-infra-authz` 083a9e7（`legacy/v2`）、`contract-infra-iam` f9c19b9（`legacy/v1`）。主分支各加一个“Restart main for the final design”提交，只留新 README（原有 LICENSE 的 `mdm-partner`、`be-protocol` 保留 LICENSE），没有强推，旧标签不动 |
| C 新建 | `infra-audit`、`mdm-org`、`mdm-currency`、`erp-credit`、`erp-billing`：公开，主分支一个初始提交（只有 README，没有 LICENSE，与多数现有仓库一致） |
| D 注册表 | 追加 `mdm/partner`（8225/9225）、`mdm/currency`（8226/9226）、`erp/credit`（8088/9088）、`erp/billing`（8089/9089）、`test/probe-go`（8600/9600）、`test/probe-py`（8601/9601）与对应 schema；`mdm/customer` 标 `retired`。`make registry-check` 通过：在用 67 个组件、退役 1 个 |
| E 子模块 | 新增 5 个子模块；`components/mdm/customer` 的地址改指 `mdm-partner`；已有子模块的指针不动。加入后旧装配的 `brickkit lint --all` 输出与之前完全相同，`up --dry-run` 照常 |
| F 镜像 | Docker 删 41 个标签（镜像占用 15.17 GB → 12.29 GB）；Podman 删 7 个；minikube 节点里删 32 个；BrickKit 自己的 `brickkit-demo/*` 与基础镜像保留 |

**与清单不同的三处**：

1. **属主角色不单列**：清单写“`schemas.tsv` 增加属主、运行两列”。实际旧的 `be-ops` 检查与 `infra/scripts` 里的旧脚本都按 4 列读这张表，`be-ops` 这一步不动，所以改为规则：`role` 列就是运行角色，属主角色固定为 `<schema>_owner`，写进 `registry/README`。名字由 schema 推出，同样唯一。
2. **注册表检查换成脚本**：旧检查（在 `be-ops` 里）要求组件行数正好 62（旧设计的名录），追加任何新组件都会失败。`make registry-check` 改为调用 `infra/scripts/registry_check.py`：保留仍然成立的规则（端口两两不重复、80 端口的归属、schema 与运行角色的命名、两表对应、外壳列与登录角色对应），去掉“62 行”，加上退役行。符合计划“能用注册表加脚本解决就不动 `be-ops`”。
3. **`infra-print` 的 README** 在“的”与“边界卡”之间多了一个空格（第一个执行、发现后改了模板），不为此单独补提交，重写该仓库时一并改掉。

另外清理了 0-09 排查时留在 minikube 里的命名空间 `r007-base`。
