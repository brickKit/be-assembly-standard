# 重建阶段的工作区

> 2026-10-15 建立：终局设计已冻结并迁成正式文档（`docs/zh/`），设计阶段的工作区归档在 `archive/design-2026-10/`。本目录放重建阶段仍在进行的工作；工作结束后整体归档。新会话先读“现在在哪里”。

## 现在在哪里

- **代表部署实验（D41）做完了**（2026-10-17 至 11-02）。结论在[实验报告](experiment-report.md)（最后是“结论汇总”与“限制与未测”），已提炼进正式文档：[部署模式](../../docs/zh/00-overview/guides/deployment-modes.md)、决定 D80（默认无根 Podman）与 A112–A114（默认全部单跑、不加连接池代理、NATS；维护者 2026-11-02 复核）、各篇的修订（[第 14 步计划](step14-plan.md)第 3 节）。复盘：[整个实验](retro-experiment.md)、[第 12 步](retro-step12.md)、[第 13 步](retro-step13.md)。
- **下一步：底层先行**（[重建计划](rebuild-plan.md)“顺序”第 3 项，路线第 3 步开头）：事务与消息、登录与身份、权限、审计与整套恢复、冷热数据，以及 Python 补到代表组件需要的剖面；各项的验证门槛在[实验计划](experiment-plan.md)的“实验之后：底层先行”，实验留给各项的待测在重建计划里列着。之后按依赖顺序重建业务组件。**进入它是换阶段，等维护者确认**（要改根 `AGENTS.md` 的“推进方式”一行）。
- 设计冻结与正式文档迁移已完成（[migration-plan.md](migration-plan.md)）。待复核的 AI 选择只剩 A109（驻留期起始值，`docs/zh/02-decisions/09-ai-choices.md`）。

### 实验各步

| 步 | 做了什么 | 计划 | 记录 |
| --- | --- | --- | --- |
| 0 | 机制的最小复现（外壳取成员、一个仓库多个组件、全部本机进程、Podman、minikube、两个版本、两个副本、两个 PostgreSQL、有根 Podman、连接池代理） | [实验计划](experiment-plan.md) | 0-01–0-12 |
| 1 | 仓库动作（15 个重启、5 个新建、改名） | [step1-repo-actions.md](step1-repo-actions.md) | — |
| 2、3 | `be-protocol` 子集、Go 与 Python 的 SDK、外壳启动器、探针与一致性剖面 | [step2](step2-plan.md)、[step3](step3-plan.md) | — |
| 4 | 三个外壳、资源采集、负载驱动；D 行的底价与通信细分 | [step4-plan.md](step4-plan.md) | 4-02、4-03、4-04 |
| 5 | 身份、授权、审计与两个契约包 | [step5-plan.md](step5-plan.md)、[契约](step5-contracts.md) | 5-01、5-02 |
| 6、6b | 主数据四个；丰富的种子数据 | [step6](step6-plan.md)、[step6b](step6b-seed-plan.md) | 6-01、6-02 |
| 7 | 交易链五个组件、L3 场景、负载驱动的业务链；文档结构实验 R2 | [step7-plan.md](step7-plan.md) | 7-01 |
| 8 | 套件 A 的 D 行 | [step8-plan.md](step8-plan.md) | 8-01 |
| 9 | 套件 A 的其余 5 行与探针 | [step9-plan.md](step9-plan.md) | 9-01、9-02 |
| 10 | 套件 B（B1–B7）与 LD、LP 的外壳列 | [step10-plan.md](step10-plan.md) | 10-01–10-10 |
| 11 | 套件 C（故障与运维） | [step11-plan.md](step11-plan.md) | 11-01、11-03 |
| 12 | 套件 D（多版本兼容） | [step12-plan.md](step12-plan.md) | 12-01 |
| 13 | 套件 E（多实例与多数据库） | [step13-plan.md](step13-plan.md) | 13-01 |
| 14 | 报告、部署模式说明、设计修订、给 BrickKit 的建议；之后 FRR-023 的复测（真重启三次） | [step14-plan.md](step14-plan.md) | `experiment-data/14-01-reboot/` |

记录在 [experiment-records/](experiment-records/README.md)（索引），原始数据在 `experiment-data/<记录编号>/`，运行脚本在 [experiment-scripts/](experiment-scripts/README.md)，格在 `experiment-cells/`。

### 本目录的其他文件

| 文件 | 内容 |
| --- | --- |
| [rebuild-plan.md](rebuild-plan.md) | 仓库复用、`legacy/` 分支、改名与新建的清单与顺序；每一步动仓库前先列动作请用户确认（改名除外） |
| [implementation-checks.md](implementation-checks.md) | 冻结时列出、交给实现阶段核对的项 |
| [be-protocol-carry.md](be-protocol-carry.md) | 线协议细节的承接清单，重建 `be-protocol` 时逐条重审写入 |
| [migration-plan.md](migration-plan.md)、[migration-map.md](migration-map.md)、[review-migration.md](review-migration.md) | 正式文档迁移的动作、承接表与复查（已完成） |
| [doc-structure-plan.md](doc-structure-plan.md) | 文档结构实验（2026-10-22 至 23，R0–R3 都已完成）；题库在 `dev/routing-tests/` |
| [diagrams-plan.md](diagrams-plan.md) | 文档里的图（2026-10-25 完成：开发文档不放图，客户读的图后补全关系，`make docs-diagrams` 进 `make gates`） |

## 本机的环境

实验与重启测试留下的、以后还会碰到的设置（各自的经过在括号里的记录）：

- **`/etc/hosts` 有 `127.0.0.1 host.docker.internal`**（维护者 2026-11-01，第 12 步 G7）：让本机进程与容器用同一个名字访问对象存储；不要删。
- **无根 Podman 的开机自启**（2026-11-02，`experiment-data/14-01-reboot/`）：linger 已开、`podman-restart.service` 已启用；`~/.config/systemd/user/podman-restart.service.d/wait-network.conf` 让它等网络；`/etc/systemd/system/user@1000.service.d/data-disk.conf` 让用户的 systemd 等数据盘；AppArmor 的 `podman`、`passt` 配置是包里的原样，`usr.bin.pasta` 是原样加 BrickKit 的一条信号规则（enforce）。**AI 的终端在 VS Code 的 snap 里**，那里允许建用户命名空间：查 Podman 的问题、模拟开机或 ssh，用 `systemd-run --user --wait …`；P、LP 两行起格前 `cell-chain.sh` 会先跑 `podman-preflight.sh`。
- **数据盘** `/home/zhijie/data`：Docker 与 containerd 的根、Podman 的存储、Go 与 Python 的缓存都在上面；Docker 与用户的 systemd 都等它挂上。
- **还原过的设置**：维护者 2026-10-29 执行了 `cap/revert.sh` 与 `rootful/revert.sh`（Docker 的 `cgroup-parent` 去掉、`be-cap.slice` 停了；root 的 `podman.socket` 停用、`DOCKER-USER` 清空）。以后再要限内存或有根 Podman，重新执行对应的 `setup.sh`。GNOME 的文件索引忽略 `/home/zhijie/data`（`org.freedesktop.Tracker3.Miner.Files ignored-directories`）。
- **BrickKit**：CLI v1.11.3，本项目装的技能是 v1.11.3（`brickkit skills update`）。v1.11.1 起 `target: podman` 生成 `restart: always`，旧格升级后第一次 `up` 会重建每个组件容器；v1.10.3 起 compose 健康检查在启动阶段每秒一次（`start_interval: 1s`），D 行崩溃后的拉起读数在那之后变短，不与之前的比。
- **要查的**：Casdoor 的库导出有 557 MB（第 10 步 B7 切换前导出，已移出仓库），大得反常，推测是多轮测试积下的令牌与记录，要看是哪张表、要不要定期清理（[10-08](experiment-records/10-08-base-in-cluster.md)）。

## 推进方式与停点

2026-10-17 起连续推进（用户授权）：每项做完写记录、更新本文件、提交，直接做下一项；只在需要用户决定、需要 BrickKit 配合、仓库的新建改名删除时停下。每一步结束停下汇报，用户确认后进入下一步（计划的“步骤与检查点”）。

- **计划的步骤逐条标状态**（第 12 步复盘 I2）：每步计划的“步骤”一节，每条前面标 ✅（做完）或 ⬜（没做），做完一条当场改。交接的剩余清单从没标 ✅ 的条目抄，不凭记忆写。
- **进记录的运行当场存输出**（第 12 步复盘 I3、第 13 步复盘 J3、J4）：结论要写进记录的每次运行（含临时模块、格的副本上的命令、手动发的调用），输出当场写进 `experiment-data/<步>/`，命令写在同一处；只在终端里看过的不算数。记录里的计数与比例用命令从存下的数据算，不手数。停格前先跑 `experiment-scripts/cell-logs.sh`（各运行器已调用；手工停格时自己跑）。
- **测量**：一律在 performance 电源模式下、按小时算；每一轮记下电源模式，运行脚本切到 performance 并在结束时恢复。测量期间不在机器上跑任何测试、编译或剖析（会干扰数字，也会抢端口，4-03 记了一次）。测量取 `be-acceptance` **整个仓库**的快照（只拷 `conformance/` 会缺负载驱动的源码），经 `experiment-scripts/night-wrap.sh` 启动。
- **种子与下游**（第 7 步的经验）：组件写种子时引用[种子数据清单](../../docs/zh/03-seed-data.md)的“下游可以直接引用的数据”，缺的到上游种子里补；角色与授予照主数据的做法（`be-sdk-go` 的 `seed` 包），带上法人与部门的维度。
- **重跑套件 C 的升级（R4）**：`ops11.sh upgrade` 不写死版本，用 `UPGRADE_REFS` 给出比格里更新的发布（[11-03](experiment-records/11-03-suite-c-remaining-checks.md)）。

## 待用户决定

- 进入底层先行（换阶段）。
- 破坏性迁移的保险（第 12 步计划 9.1“还没定的”，不急）。
- 父仓库之后的提交（`git log origin/main..main`）：推送要维护者下令或授权。

## 未推送、已知问题与外部往来

- **推送**：子仓库（协议、SDK、验收、外壳、组件）的发布都已推送。父仓库 2026-11-02 推送到 `c755ccc9`（维护者下令）；之后的提交以 `git log origin/main..main` 为准。
- **给 BrickKit 的信箱** `brickkit-feedback/`（被 gitignore；规则在它的 `README.md`）：待办每条一个文件放在 `open/`，回复与复测写在同一个文件里，关闭后移到 `archive/`。现在没有待办：FRB-001–010、FRR-001–023 都已关闭（最后一条 FRR-023 于 2026-11-02 在 v1.11.3 复测通过）。下一个编号 FRB-011、FRR-024。
- **本项目的待办（来自 FRB-009）**：各组件、外壳与探针 Dockerfile 里的 `ENV PORT` 与注释“BrickKit injects PORT only for mode: local”已过时但无害，下次改动该组件时删掉（Python 探针与它的变体已在 3.2.20 删掉；Go 探针与它的变体还在）。
- **组件与外壳的 SDK**：组件与外壳在 `be-sdk-go` alpha.41、`be-sdk-python` a38；SDK 已到 alpha.42、a39（只给测试标了 CK-ID-01，行为不变），协议到 alpha.39（`COMPAT.md` 的“装配项目的正式文档”一列）。下次连锁发布时一起换。
- **改写过历史的仓库**（去掉误提交的二进制）：做法都一样——`git filter-repo` 只去掉那一个文件，只有含它的版本的文件树变了，其余文件树、作者、时间与说明都不变（说明里的旧哈希换成新哈希），分支与标签重新指向、强推；父仓库在改写之前记的指针已不在远端；改写前的整库备份放在当时会话的临时目录（会话结束会清掉）。
  - `be/go-core`（2026-10-23，用户同意）：3.0.20 误带 55 MB 的构建产物（3.0.21 移除），从 3.0.20 起改写，3.0.20–3.0.24 五个标签重新指向，远端克隆约 26 MB → 188 KB；父仓库 `d4a34794` 之前记的 3.0.20–3.0.24 指针悬空。
  - `be-acceptance`（2026-11-01，维护者同意）：探针 3.2.23 的提交误带 52 MB 的 `probes/go/go`，`main` 与 30 个标签重新指向，打包约 30 MB → 3.9 MiB；`legacy/v0`、`stage-b` 不变；父仓库此前记的 `1d205c5` 之后的指针悬空。`be/py-render` 3.0.29 的 `uv.lock` 按提交锁的探针因此取不到：3.0.30 重新锁定并发布，3.0.29 的说明写明改用新版本，实验格 `D12-H` 仍声明 3.0.29（本机已有镜像），下次用时换；Go 代理里 `probes/go/v3.2.23` 仍是带二进制的旧内容（没有东西依赖它）。
  - `be-sdk-go`（2026-11-01，维护者定：开发阶段只有我们自己用）：alpha.8、alpha.9 误带的 `grpcx.test`（48.6 MB），打包 24.5 → 1.6 MiB；alpha.10 起的模块内容不变（与组件的 `go.sum` 一致）；alpha.8、alpha.9 在 Go 代理里仍是旧内容，没有东西用。
  - `be/go-infra`（同上）：3.0.23 误带的 54.6 MB 产物，打包 25.6 MiB → 120 KiB；没进过 Go 代理。改写后 3.0.36 等版本指向的提交变了，**用改写前缓存的旧格**（例如 P9-H 的副本）`up` 会报“标签被移动过”，刷新缓存即可。
  - 2026-11-01 核对：各仓库历史里再没有误带的大文件；之后由提交钩子与 `make no-binaries` 拦（第 12 步复盘 I1）。
- **发布说明**：第 5、6、6b 步与第 7 步 3.0.1 起的十几个版本是手打的标签，说明只有一行版本号；已发布的不改（版本不可变）。现在一律 `brickkit release --notes-file <文件>`（使用方必须做什么在前，新增在后），Go 的 `v` 标签用同一份说明；发完用 `git for-each-ref refs/tags/<版本> --format='%(contents:subject)'` 看一眼。2026-11-01 第 12 步误用 `--notes <文件>` 把路径写进了 65 个标签，当天换成正文（BrickKit v1.11.0 起拒绝这样用）。
- **`tools/be-ops`、`tools/be-sdk-ts` 的 `stage-b` 分支**（2026-10-01 至 04，已推送、未发布）：设计冻结之前的阶段 B 实验。父仓库的指针停在各自 `main` 的发布版本（be-ops v0.2.0、be-sdk-ts v0.5.0）。重建这两个工具时只作参考，按新设计从零写（D59）。
- **已知、暂不处理**：旧的发布、接入与验证工具的测试失败，工具随重建重新提供，届时一并处理：`infra/scripts/tests/test_ship_dryrun.sh`（旧 `ship.sh` 还调用旧 `be-acceptance` 的命令）；`test_config_fill.py` 中 `integrate.sh` 的 4 项（伪造的 `brickkit` 报 v1.4.0，被版本检查拒绝）与 `test_verify_deploy.py`——2026-10-18 在改动之前的提交上核实同样失败。
- **kb知识库**：本项目交的 PR 都已合并（截至 2026-11-02，最后是 #54、#55、#57）；性能发现一律交给它（用户 2026-10-18），写成好读的结论，原始数据与通用脚本一起提交。第 7 步查到、以后用得上的几条：设计出账与信用时 05.21 可作参考，以本项目的协议 04、05 与边界卡为准；各国的法规（发票系列、电子发票报送）不归 kb 管，查官方来源写进本项目的文档；NATS 消费者设 `BackOff` 时第一个值代替 `AckWait`、它只管确认超时，按处理时间 p99 的 2–3 倍定；金额列 `NUMERIC(p,s)` 写入多出的小数位会被悄悄舍入，应用里先按业务规则舍入；运行时角色要能用迁移角色建的序列时，`bigserial` 要另授 `USAGE ON SEQUENCES`，identity 列不需要。

## 任务结束时：知识库反馈

还没交的草稿只剩一项：Linux 的 `CLOCK_MONOTONIC` 在系统休眠期间停走（`CLOCK_BOOTTIME` 才计入）；kb 选主相关文档（07.06 选主、07.10 时间与时钟）按单调时钟计租约时没有提醒这一点。提交前先在 Linux 上验证。
