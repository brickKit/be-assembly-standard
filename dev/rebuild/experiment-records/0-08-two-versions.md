# 0-08 同一组件两个版本并存

## 1. 结论

**通过**。BrickKit 的多版本共存按文档工作：`add` 自动把被依赖的旧版本留成兼容版本（`requiredBy`）、放进编进它的外壳，新版本单独运行；两个版本各有自己的版本化服务名、镜像、配置文件与迁移，调用方按自己声明的版本拿到地址；迁移按版本从旧到新串行。FRB-003 回复里补上的迁移顺序保护也实测有效：旧版本要从源码迁移、新版本在容器里迁移时，`--dry-run` 就拒绝并给出出路。没有发现 BrickKit 的问题。

## 2. 测了什么、为什么

计划第 0 步：“同一组件两个版本并存（BrickKit 多版本共存：`requiredBy`）”，对应套件 D（多版本兼容）的前提。要确认：两个版本怎样进入项目、部署文件与配置怎样写；两个版本能不能同时运行、调用方是否拿到各自声明的版本；外壳编进一个版本时另一个版本怎样运行；迁移顺序；以及 v1.7.1 起的迁移顺序保护（0-05 留到这里测）。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| BrickKit | CLI v1.7.2；Docker 29.7.1；基础资源 `be-postgres`、`be-nats` |
| alpha | 自己的 git 仓库（本机裸仓库 `remotes/demo-alpha`），标签 `0.1.0`、`0.2.0`，两版的 `/api/hello` 回答各自的版本；项目用 `baseUrl` 的 git 安装源取它（组件在仓库根目录，标签不带命名空间，所以不能用 `repo`） |
| 其余 | beta 依赖 alpha@0.1.0；gamma 依赖 alpha@0.2.0 与 beta，`/api/chain` 同时调两者；Go 外壳编进 alpha 0.1.0（从 0.1.0 标签的检出）与 beta；beta、gamma、外壳在本地源 |

## 4. 怎样跑

`r008-setup.sh` 建 alpha 的仓库与项目（开头清掉 BrickKit 对这个仓库的用户级缓存，因为每次重建都会把标签挪到新提交上）。`run008.sh`：

1. `add --local`，看三层文件；`build`；`up`，查地址、迁移顺序与调用。
2. alpha 0.1.0 挪出外壳，两个版本都单独运行。
3. 迁移顺序保护：在 `components/` 放 alpha 0.1.0 的检出，`upgrade demo/alpha@0.1.0` 让 0.1.0 成为默认版本（0.2.0 留给 gamma）；3a 让 alpha 0.1.0 以 `mode: local` 离开外壳；3b 让 Go 外壳 `mode: local`（0.1.0 从源码编进）；3c 对照：全部在容器。

## 5. 结果

| 步 | 结果 |
| --- | --- |
| `add --local` | 一条命令写好三层：`brickkit.yaml` 里 alpha 0.2.0 是默认版本，0.1.0 标 `requiredBy: [demo/beta, demo/shell]`；部署文件把 `demo/alpha@0.1.0` 嵌在外壳下，`demo/alpha`（0.2.0）在顶层；配置分 `demo-alpha.yaml` 与 `demo-alpha@0.1.0.yaml`。提示“外壳编进的是 0.1.0，所以 0.2.0 不在外壳里、单独运行”。`--yes` 时必填键自动引用 `vars.yaml` 里的同名变量 |
| `build` | alpha 两个版本都从各自的标签导出源码构建；外壳镜像标签 `demo/alpha@0.1.0,demo/beta@0.1.0` |
| 地址 | gamma 拿到 `DEMO_ALPHA_ENDPOINT=http://demo-alpha-0-2-0:8081`；外壳里的 beta 拿到 `http://demo-alpha-0-1-0:8081` |
| 调用 | gamma 的链路里，alpha 直接回答 0.2.0，经 beta 回答 0.1.0；`status` 列出两行 alpha（0.1.0 标“in shell”） |
| 迁移顺序 | compose 里 `demo-alpha-0-2-0-migration` 依赖 `demo-alpha-0-1-0-migration` 完成；外壳依赖 0.1.0 的迁移，alpha 0.2.0 依赖 0.2.0 的迁移 |
| 两个版本都单独运行 | 两个容器 `demo-alpha:0.1.0`、`demo-alpha:0.2.0` 同时 healthy，都监听 8081（各自的容器）；调用结果同上 |
| `upgrade demo/alpha@0.1.0`（降级） | 允许，标“downgrade”；0.1.0 变成默认版本并进外壳，0.2.0 留下标 `requiredBy: [demo/gamma]`、在顶层写成 `demo/alpha@0.2.0` |
| 3a：alpha 0.1.0 `mode: local` | `--dry-run` 就拒绝（`CONFIG_INVALID`）：“0.1.0 的迁移从源码跑、在容器之后，而更新的 0.2.0 先在容器里迁移”；出路：这次不跑 0.2.0（`mode: disable`），或这次让 0.1.0 用镜像 |
| 3b：Go 外壳 `mode: local` | 同样的拒绝，建议里写明“外壳成员要让外壳在容器里” |
| 3c：全部在容器 | 正常；迁移链同第一部分 |

## 6. 观察与异常

- 前一次尝试的第 3 部分因脚本问题失败（原始数据开头有说明）：重建远端仓库把标签挪到了新提交，BrickKit 的用户级缓存里还是旧提交，报 `VERSION_CHANGED` 拒绝运行。这是 FRR-002 的检测在真实情形下又一次起作用。
- 外壳只能编进成员的一个版本（Go 构建一个模块只有一个版本），另一个版本由 BrickKit 自动安排成单独运行，并在 `add` 时说明，不需要手工处理。
- 迁移顺序保护的第一条出路（对 0.2.0 写 `mode: disable`）会连带停掉必须依赖它的 gamma；出路是对的，但用的时候要知道这一点。
- 没有在 Kubernetes 上测两个版本。版本化服务名与成员地址的规则在 0-07 已验证，套件 D 再在 K8s 上跑。

## 7. 影响

- **套件 D（多版本兼容）**：发两组版本时，旧版本由 `requiredBy` 自动保留，不需要手写；外壳编进哪个版本决定了另一个版本单独运行，计划里的兼容格要把“多出一个进程”算进资源。
- **组件发布**：组件在仓库根目录时，使用方用 `baseUrl` 的安装源；探针那种子目录组件用 `repo`。
- 不需要改设计。

## 8. 原始数据

`dev/rebuild/experiment-data/0-08/run1.txt`（含 `run008.sh` 与生成脚本 `r008-setup.sh`；`r008-base.sh` 是改了路径的 `r006-setup.sh`）
