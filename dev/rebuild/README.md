# 重建阶段的工作区

> 2026-10-15 建立：终局设计已冻结并迁成正式文档（`docs/zh/`），设计阶段的工作区归档在 `archive/design-2026-10/`。本目录放重建阶段仍在进行的工作；工作结束后整体归档。

## 这里有什么

| 文件 | 内容 |
| --- | --- |
| [migration-plan.md](migration-plan.md) | 正式文档迁移的动作与进度（协议 21） |
| [migration-map.md](migration-map.md) | 承接表：旧文档每一节的去处 |
| [be-protocol-carry.md](be-protocol-carry.md) | 线协议细节的承接清单，重建 `be-protocol` 时逐条重审写入 |
| [rebuild-plan.md](rebuild-plan.md) | 仓库复用、`legacy/` 分支、改名与新建的清单与顺序；每一步动仓库前先列动作请用户确认（改名除外） |
| [implementation-checks.md](implementation-checks.md) | 冻结时列出、交给实现阶段核对的项 |
| [experiment-plan.md](experiment-plan.md) | 代表部署实验（D41）的实施计划（待用户审） |
| [step1-repo-actions.md](step1-repo-actions.md) | 实验第 1 步的仓库动作清单与执行结果（2026-10-17 已执行） |
| [step2-plan.md](step2-plan.md) | 实验第 2 步（`be-protocol` 子集与 Go SDK）的任务、取舍与进度 |
| [step3-plan.md](step3-plan.md) | 实验第 3 步（Python SDK 子集、外壳启动器、两种语言的探针与一致性剖面）的任务、取舍与进度 |
| [step4-plan.md](step4-plan.md) | 实验第 4 步（三个外壳、资源采集、负载驱动、报告生成，D 行的底价与通信细分）的任务、取舍与进度 |
| [experiment-report.md](experiment-report.md) | 实验报告（给维护者与客户）；第 4 步起按行填写 |
| [step5-plan.md](step5-plan.md) | 实验第 5 步（身份适配、授权、审计与两个契约包）的计划，2026-10-19 定稿 |
| [step5-contracts.md](step5-contracts.md) | 第 5 步的契约（系统面的方法、信封与记录字节、定稿时补的设计） |
| [step6-plan.md](step6-plan.md) | 实验第 6 步（主数据四个）的计划、决定与进度（2026-10-20 起草） |
| [step7-plan.md](step7-plan.md) | 实验第 7 步（销售、库存、信用、出账、打印）的范围、决定、任务与进度；同时是文档结构实验的 R2（2026-10-22 起） |
| [step10-plan.md](step10-plan.md) | 实验第 10 步（套件 B，附加对照）的计划：B1–B7 怎样搭、缺的工具、时长、要维护者定的两件事（2026-10-27 起草） |
| [step11-plan.md](step11-plan.md) | 实验第 11 步（套件 C，故障与运维）的计划：从外部注入故障（容器、基础资源、数据库里临时的触发器）、每次之后的不变量、缺的工具、时长（2026-10-29 起草） |
| [doc-structure-plan.md](doc-structure-plan.md) | 文档结构实验（2026-10-22 起）：内容类型 × 层、初步结构、给 BrickKit 的 FRR-010–012、R0–R3 的轮次；题库在 `dev/routing-tests/structure-questions.md` |

## 现在在哪里

- 设计冻结、正式文档迁移已完成（[migration-plan.md](migration-plan.md)）；AI 选择 A99–A110 记在 `docs/zh/02-decisions/09-ai-choices.md`（A109 驻留期起始值待复核，其余已确认）。
- **代表部署实验（D41）进行中**：第 0–7 步已完成（第 6 步 2026-10-20 完成：主数据四个组件，[step6-plan.md](step6-plan.md)、[6-01](experiment-records/6-01-master-data-cells.md)；随后按用户要求补了种子数据，第 6b 步，[step6b-seed-plan.md](step6b-seed-plan.md)、[6-02](experiment-records/6-02-richer-seeds.md)）。第 4 步的 D 行结果见 [4-04](experiment-records/4-04-d-row.md)，第 5 步带真实安全组件的通信代价见 [5-02](experiment-records/5-02-security-cells.md)，都已写进[实验报告](experiment-report.md)。
- **文档结构实验**（2026-10-22 起，[doc-structure-plan.md](doc-structure-plan.md)）：R0 基线、R1 改结构与重考、R1b 压短根 `AGENTS.md` 已完成；R1 的尾巴与 R2（R2a 设计、R2b 设计与代码一致性，2026-10-22、23）都已完成；剩下 R3（定规则并反馈知识库与 BrickKit）。本轮的发布已推送（2026-10-22，用户同意）：`be-protocol` `v3.0.0-alpha.20`、`be-sdk-go` `v3.0.0-alpha.26`；`mdm/org` 3.0.4，`mdm/currency`、`mdm/partner`、`mdm/product` 3.0.5；`infra/authz` 3.0.5（包改名为 `authz/`）、`infra/audit` 3.0.3（包改名为 `audit/`）、`infra/iam-casdoor` 3.0.4；外壳 `be/go-infra` 3.0.25 编进 `mdm` 3.0.3/3.0.4、`infra/authz` 3.0.4、`infra/audit` 3.0.3、`infra/iam-casdoor` 3.0.3（之后只改了文档的版本没有再进外壳）。外壳 3.0.23 误带了 52MB 的构建产物，3.0.24 移除；用户同意保留历史、不改写。
- **第 7 步完成**（2026-10-23，[step7-plan.md](step7-plan.md)、[7-01](experiment-records/7-01-trading-chain.md)）：交易链五个组件（`erp/inventory`、`erp/credit` 3.0.2，`erp/sales`、`erp/billing`、`infra/print` 3.0.3）单跑（D7-S）与进外壳（D7-H：`be/go-infra` 3.0.26、`be/go-core` 3.0.24、`be/py-render` 3.0.22）都符合剖面；种子数据、L3 交易链（be-acceptance `conformance/scenarios`）、负载驱动的业务链（`load -flow`）、R2b（文档结构实验，10 题全对）都已完成。之后处理的小事、文档结构 R2c 与 R3、SDK 版本对齐（全部组件 be-sdk-go alpha.32，D7-H、D7-S 复跑通过）见 step7-plan 的“第 7 步之后处理的小事”。**正式的部署模式测试（第 8 步起的部署矩阵）等用户下令再开始**（2026-10-23）。**第 8 步的测量轮已做完**（2026-10-25，[step8-plan.md](step8-plan.md)、[8-01](experiment-records/8-01-d-row-chain.md)）：R8.1 三格结果摘要相同；R8.2、R8.3 两遍一致（不跑 R8.4），H2 外壳比单跑的组件 CPU 少 22–25%、常驻内存少 47–48%，延迟看不出差别；R8.2e 空库起格 47–55 秒。第 8 步还剩：实验报告的 D 行、性能发现交知识库；之后修 R8.2 发现的缺陷（下面“已知问题”）、给采样加不含页缓存的内存读数，再等用户下令开第 9 步（其余 5 行）。
- **第 9 步（其余运行形态）：整夜测量完成**（2026-10-27，[9-01](experiment-records/9-01-other-rows-chain.md)）：D9-S 与 P、K、L 三行的 S、H、X 共十格一次跑完，结果摘要都与 D8-S 相同；组件开销四种形态差不多，差在平台（Kubernetes 常驻约 2 GiB）；外壳在每种形态都省；本机进程 p50 多约 2 毫秒（测量的转发）。之前修的两个问题、“定义未到”不绑定变更键（D77）与冒烟见 [step9-plan.md](step9-plan.md) 第 8 节。基础资源各行都用同一套 Docker（用户定）。9-01 第 6 节的三处已查清并修好（2026-10-27）：SDK 审计转运积压时不连续（每组件每秒最多 100 条；`be-sdk-go` 3.0.0-alpha.35、`be-sdk-python` 3.0.0a31，全部组件与外壳发了新版本，见 9-01 第 7 节）、采样把 minikube 节点里的容器运行时重复计算（`be-acceptance` v1.0.2）、运行器停格时留下转发器。K 行已用修好的采样与新版本重测（R9.2，2026-10-27，9-01 的 5.5）：四格全过，K 行合计在同版本 D9-S 的 2–8% 之内。运行形态与外壳开销的实测已交 kb知识库（PR #40，记录 26、27；2026-10-28 追加探针与混合形态、PgBouncer 对照，新记录 28“PostgreSQL 队列还是 NATS”，分支在工作树 `../kb-wt-1027`）。LD、LP 两格（`LD9-S`、`LP9-S`，销售与库存在本机）与 P、K、L 三行的探针格（33 格，`probe9.sh`）的工具都已就绪、冒烟通过（2026-10-27）；途中修了签发者写成 `$endpoint` 让本机组件拒绝令牌（协议 19 已写明签发者是固定字符串）、`mode: local` 会话停不掉、K 行节点刚起时 Pod 里的 DNS 不可用（`cluster-on.sh`）。第二夜（2026-10-27 17:59 到 10-28 00:15，step9-plan 8.6）：LD9-S、LP9-S、P9-S 三格全过，写进 9-01 的 5.6（只与同一夜的 P9-S 比；LD 没有同批的参照，不作比较）。探针 L9-probe-S 起不来是探针自己的缺陷（变体的本机命令 `go run ../go`），修成 `go -C ../go run .`（探针 3.2.20、外壳 go-core 3.0.33、go-infra 3.0.34、`be-acceptance` v1.0.5）。**对比只在同一层、同一批里做**（用户 2026-10-28 定，step9-plan 8.7）：探针改为四种形态（D、P、K、L，D 行用新建的 `D9-probe-*`）的底价、S、H2 整批重测（`night9c.sh`），第二夜的探针（`r93`）只留作原始数据。整批跑完（r94，01:04–05:26）：33/36 格通过，D9-probe-S、P9-probe-S、K9-probe-S 起不来（探针变体的 Dockerfile 装的还是 v3.2.19；探针 3.2.21、外壳 go-core 3.0.34、go-infra 3.0.35 修好，`make pin-check` 补查 Dockerfile 与外壳 go.mod 里的探针模块）；S 层四种形态重测一批（r95，05:30–06:42，全过）。记录 [9-02](experiment-records/9-02-probes-all-rows.md) 已写：进程底价四种形态一样，每一跳的 CPU 容器三种形态差在 10% 以内。 容器数据与大缓存 2026-10-26 搬到数据盘 `/home/zhijie/data`（同一块 NVMe）。
- 第 7 步的经验（写种子与下游时照用）：组件写种子时引用[种子数据清单](../../docs/zh/03-seed-data.md)的“下游可以直接引用的数据”，缺的到上游种子里补；角色与授予照主数据的做法（be-sdk-go 的 `seed` 包），带上法人与部门的维度。待用户决定的事见下面“待用户决定”。测量一律在 performance 电源模式下、按小时算。
- 测量期间不在机器上跑任何测试、编译或剖析：会干扰数字，也会抢端口（4-03 记了一次）。 每一轮记下电源模式；运行脚本切到 performance 并在结束时恢复。
- 实验之后先做底层（权限、登录、冷热数据、事务、消息），再按 [rebuild-plan.md](rebuild-plan.md) 重建业务组件。

- **第 11 步（套件 C，故障与运维）：测完；熔断已改（D79），还有两件等维护者定**（2026-10-31，[step11-plan.md](step11-plan.md) 第 8、9 节）→ [11-01](experiment-records/11-01-suite-c-faults.md)。`night11.sh` 2026-10-30 17:30–23:48（D、K 两行六格），K9-H 的 R5、R4 因格工具的缺陷（拆出后仍找外壳的 Service）补跑一次（`be-acceptance` v1.0.11，23:48–00:13）。70 项之后不变量全部成立，RS05、RS06、BL04 都照协议恢复；代价在可用性：参与方重启后同步确认停约 30 秒（`be-sdk-go` P4.11 熔断的打开期），K 行崩溃时请求挂住、同一 Pod 反复崩溃受 kubelet 退避（外壳格 22→34→53 秒），外壳格停授权 2.4 秒就拒写。实验报告已加“套件 C”一节，第三部分 D、K 两节加了“出事时”一行。熔断的打开期已定（D79，2026-10-31）：5 秒起、试探失败加倍到 30 秒；`be-protocol` alpha.28、`be-sdk-go` alpha.37、`be-sdk-python` a33，12 个组件与 3 个外壳连锁发布（iam-casdoor 3.0.11、authz 3.0.12、audit 3.0.9、org 3.0.10、currency 3.0.11、partner 3.0.13、product 3.0.13、inventory 3.0.10、credit 3.0.9、sales 3.0.15、billing 3.0.14、print 3.0.8；go-infra 3.0.37、go-core 3.0.39、py-render 3.0.28），62 个现行的格换到这些版本；复测 K9-S 的库存崩溃，`processing` 窗口 31 → 7 秒（11-01 第 7 节）。`ops11.sh` 的 R4、R5 写死了第 11 步的版本（库存 3.0.8 → 3.0.9、外壳 3.0.36/3.0.38），重跑前要改。还等维护者定：Kubernetes 上就绪探针与超时的建议；计划里没做的四项检查（发件表积压峰值、消息流不缺不重、部门投影追平、审计一致性）要不要补跑。R4 的版本：`erp/inventory` 3.0.9、`erp/sales` 3.0.14、`erp/billing` 3.0.13、`be/go-core` 3.0.38（3.0.37 被取代）、`be/py-render` 3.0.27。kb：实测记录 30“出事时的代价”与一份反馈（`docker kill` 模拟不了崩溃、一步中间的注入、负载下的不变量）在 knowledge-base PR #45，等审查。
- **第 10 步（套件 B）完成**（2026-10-30）（[step10-plan.md](step10-plan.md) 第 5 节）。各晚的测量取 `be-acceptance` **整个仓库**的快照（只拷 `conformance/` 会缺负载驱动的源码 `load/`，2026-10-29 第一次 night10f 因此失败；B1–B7 用 v1.0.8，之后用 v1.0.9），经 `experiment-scripts/night-wrap.sh` 启动（快照、电源模式、残留检查与启动命令写在它的开头）；维护者 2026-10-29 凌晨授权“能测就一直测下去，遇到问题就修”。
  - **已完成**：
    - B1、B2（2026-10-28 07:08–12:13，六格全过）→ [10-01](experiment-records/10-01-pooler-and-pgqueue.md)：PgBouncer 不省组件、只省 PostgreSQL 约 200 MiB 而合计多 9%（外壳省的是组件进程与平台）；PostgreSQL 队列与 NATS 看不出差别。结果摘要比 D8-S 多 16 条审计记录是货币种子“最近 60 天的工作日”随日期变，不是缺陷（5.3；运行器已改为默认与同一批第一格比）。
    - 外壳格 PostgreSQL 的内存 → [10-02](experiment-records/10-02-postgres-backend-memory.md)。
    - P6.32（空闲时发件转发器对空分区做编号事务；`be-protocol` alpha.27——alpha.26 不能用、`be-sdk-go` alpha.36、`be-sdk-python` a32，12 个组件与 3 个外壳连锁发布）：`night10f.sh` 2026-10-29 01:08–02:50 → [10-03](experiment-records/10-03-outbox-idle-poll.md)：空闲时 PostgreSQL 少 36–48%、组件少 31–35%，7 次/秒每千次整套少 17%，延迟与结果不变。
    - 容器里的 Python 构建：`pybuild/run.sh` 2026-10-29 02:50–03:41 → [10-04](experiment-records/10-04-python-builds.md)：pbs 比 slim 只少 2–5%，alpine 比 slim 多 19–28%。生产继续用 slim（AI 建议不换）；维护者 2026-10-29 同意 Python 探针镜像从 alpine 改成 slim（让探针的数字贴近生产）：已做（`test/probe-py`、`test/probe-py2` 3.2.20，`be-acceptance` v1.0.9：slim、装 wget、去掉 `ENV PORT`；顺带修了 `variants.py` 仍生成 Go 变体旧运行命令、使 `--check` 失败的问题；一致性测试 51 项通过；第 9 步单跑探针的 12 个格改到 3.2.20，D9-probe-S 冒烟通过）。之后的探针数字与 3.2.19（alpine）的不跨批比；`D9-probe-pyonly` 与 `pybuild/` 属于 10-04，仍是 3.2.19。
    - B3、B4：`night10c.sh` 2026-10-29 03:41–08:46，六格全过 → [10-05](experiment-records/10-05-memory-cap.md)：4 GiB 放得下、什么也没坏，让出的只是页缓存，延迟与 CPU 不变；坏点要更低的上限才找得到（维护者定不再加档）。
    - B5：`night10b.sh` 2026-10-29 08:47–13:44，四格全过 → [10-06](experiment-records/10-06-load-and-data-x2.md)：负载加倍核数只多约一半、每千次少约四分之一（底价摊薄）；数据加倍服务不变、数据库多 10–15%；延迟都不变。
    - B6：`night10d.sh` 2026-10-29 13:44–17:10，四格全过 → [10-07](experiment-records/10-07-rootful-podman.md)：有根时 Podman 自己的开销降到约五分之一，整套每千次少 9–10%，p50 低 1.4 ms；组件与数据库多 3–9%。
    - B7：`night10e.sh` 2026-10-29 17:10–18:57，两格全过 → [10-08](experiment-records/10-08-base-in-cluster.md)：集群内整套每千次少约 9%、延迟不变，但大半来自集群里的基础资源是新起的，真正因位置省的约 2–5%；集群内一格全程有远程会话。
    - kb：PR #40 追加了记录 10 的带日期一组、新记录 29（容器里的 CPython 构建）、记录 27 的“限内存时”与“负载加倍、数据加倍时”两组、记录 26 的“有根与无根 Podman”一组，2026-10-29。
  - **B1–B7 测完**（2026-10-29 18:57），kb 已补齐（PR #40，等审查），Python 探针已改 slim。
  - **LD、LP 的 H、X 列：测完**（`night10g.sh` 2026-10-30 01:38–08:33，八格全过）→ [10-10](experiment-records/10-10-ld-lp-shell-columns.md)：外壳省组件 CPU 约 20%、内存约 36%，混合约 11–13%、22%，与纯容器的行一样；本机进程这种形态本身整套只多 2–4%（多的是 Docker 为本机进程转发数据库流量），p50 多约 2.5 ms（测量的转发）。途中 FRB-010（BrickKit v1.10.2 修好，`experiment-data/10-09/frb010/`）。套件 A 的 18 格至此齐全。kb 记录 26 已补一组（knowledge-base PR #44，等审查；PR #40、#41 已于 2026-10-29 合并）。实验报告已更新（2026-10-30）：第一、二部分补上 10-03 到 10-10，第三部分按 6 种形态写（每种形态一节，三种拓扑合在一张表里，避免同样的部署步骤写 18 遍），套件 C–E 标“第 11–13 步”。**第 10 步完成，等维护者确认后进第 11 步**：照 [step11-plan.md](step11-plan.md) 做套件 C 的工具，冒烟后等维护者下令测量。
  - **后续要查**：Casdoor 的库导出有 557 MB（night10e 切换前导出，已移出仓库），大得反常，推测是多轮测试积下的令牌与记录，要看是哪张表、要不要定期清理。
  - **本机的系统设置已还原**（维护者 2026-10-29 晚执行了 `cap/revert.sh` 与 `rootful/revert.sh`：Docker 的 `cgroup-parent` 去掉、`be-cap.slice` 停了，基础资源回到 `system.slice`；root 的 `podman.socket` 停用、`DOCKER-USER` 清空）。GNOME 的文件索引（`localsearch-3`）2026-10-29 02:56–18:58 为测量停过：它递归索引整个 `$HOME`，包括 Docker 存储所在的 `/home/zhijie/data`；维护者同意把 `/home/zhijie/data` 加进它的忽略列表（`gsettings` 的 `org.freedesktop.Tracker3.Miner.Files ignored-directories`），已加，索引已恢复运行。以后再要限内存或有根 Podman，重新执行对应的 `setup.sh`。
- **文档里的图（2026-10-24 交办，2026-10-25 完成）**：开发文档不放图（34 张换成步骤与表），客户读的 19 张图后补全关系，组件的 3 张随 `erp/sales` 3.0.7、`erp/billing` 3.0.5 发布；`make docs-diagrams` 进 `make gates`。经过与留下的事见 [diagrams-plan.md](diagrams-plan.md) 的“结果”。

## 推进方式与停点

2026-10-17 起连续推进（用户授权）：每项做完写记录、更新本文件、提交，直接做下一项；只在需要用户决定、需要 BrickKit 配合、仓库的新建改名删除时停下。每一步结束停下汇报，用户确认后进入下一步（计划的“步骤与检查点”）。

## 待用户决定

（目前没有。）

## 未推送、已知问题与外部往来

- **`be/go-core` 的历史改写过**（2026-10-23，用户同意）：3.0.20 误带了 55 MB 的构建产物，3.0.21 移除；之后从 3.0.20 起改写历史去掉它，3.0.21–3.0.24 的文件树、作者、时间与说明都不变，五个标签重新指向（远端的克隆从约 26 MB 变成 188 KB）。父仓库 `d4a34794` 之前的提交记的 go-core 指针（3.0.20–3.0.24 的旧提交）已不在远端；改写前的整个仓库备份在会话临时目录的 `gocore-rewrite/be-go-core-before-rewrite.bundle`（会话结束会清掉）。`be/go-infra` 3.0.23 的同类产物仍按当时的决定留在历史里。

- **未推送的提交**：父仓库 2026-10-29 晚按用户要求推送了第 10 步的全部测量与记录（10-03 到 10-08）、探针 3.2.20 与镜像约定；之后的提交是否推送等用户决定，以 `git log origin/main..main` 为准。子仓库（协议、SDK、验收、外壳、组件）的发布都已推送。
- **发布说明是空的（2026-10-20 发现）**：第 5、6、6b 步的发布脚本直接打注释标签，说明只有“mdm/org 3.0.2”一句，没有照[开发流程与发布](../../docs/zh/01-conventions/10-development-workflow.md)用 `brickkit release` 写发布说明；`brickkit upgrade` 把标签说明当作发布说明显示，使用方看不到改了什么。已发布的标签不改（版本不可变）；第 7 步起用 `brickkit release --notes <文件>` 发布（使用方必须做什么在前，新增在后），Go 的 `v` 标签用同一份说明。**2026-10-23 又犯了一次**：第 7 步 3.0.1 起的交易链、打印与两个外壳的十几个版本都是手打的标签（会话压缩后漏看了这一条），说明只有一行版本号；同样不改，下一次发布起照做（已记进 AI 的记忆）。
- **`tools/be-ops`、`tools/be-sdk-ts` 的 `stage-b` 分支**（2026-10-01 至 04，已推送、未发布）：设计冻结之前的阶段 B 实验（be-ops 的 O1、O2 生成器与门禁；be-sdk-ts v0.6 起步，钉 `be-protocol v1.0.0-rc`）。父仓库的指针停在各自 `main` 的发布版本（be-ops v0.2.0、be-sdk-ts v0.5.0）；2026-10-25 本机检出从 `stage-b` 切回指针。重建这两个工具时只作参考，按新设计从零写（D59）。
- **已修（2026-10-26）：Kubernetes 上授权组件永远不就绪；授权组件换了地址之后约一分钟不能写**：协议 P8.24、P4.27、P4.28，SDK `be-sdk-go` 3.0.0-alpha.33 与 `be-sdk-python` 3.0.0a29，全部组件与外壳发了新版本；`cell-chain.sh` 的两个绕法已去掉，换 IP 的回归 `MOVE=1` 在 D9-S 通过。经过与版本见 [step9-plan.md](step9-plan.md) 8.2。
- **已知、暂不处理**：旧的发布、接入与验证工具的测试失败，工具随重建重新提供，届时一并处理：`infra/scripts/tests/test_ship_dryrun.sh`（旧的 `ship.sh` 还调用旧 `be-acceptance` 的命令，迁移后已不存在）；`test_config_fill.py` 中 `integrate.sh` 的 4 项（伪造的 `brickkit` 报 v1.4.0，被版本检查拒绝）与 `test_verify_deploy.py`（`verify-component.sh`）——2026-10-18 在改动之前的提交上核实同样失败。
- **给 BrickKit 的收件箱** `brickkit-feedback/rebuild.md`：FRR-001 到 FRR-006、FRB-001 到 FRB-006 全部关闭（FRB-006 于 2026-10-18 在 v1.8.2 复测通过，升级后的部署与测量也通过）；FRB-007（升级把用户已移除、但旧外壳版本编进了的成员加回来）2026-10-18 新开、当天在 v1.8.3 复测通过并关闭；FRR-007（使用者移除过的成员因强依赖被升级加回来时提示一声）当天在 v1.8.4 实现、复测通过并关闭；2026-10-20 新开 FRR-008（依赖方的精确依赖没跟上时提醒两个版本会并存、报错点名依赖方；已在 v1.8.4 复现，脚本在 `experiment-data/6b/frr008/`）与 FRR-009（种子数据页补三条做法），当天在 v1.8.5 实现、复测通过并关闭；没有未回复的条目。 2026-10-23 新开的 FRB-008 与 FRR-010–013 在 v1.9.0、v1.9.1 复测通过并关闭（本项目这边的待办 2026-10-25 核对已完成）；2026-10-25 新开的 FRR-014（`release.goModule: true` 一次打平台与 Go 的两个标签并核对模块路径）、FRR-015（文档规范：规则与流程写成文字与表）、FRR-016（AI 指南的检验文档一页）在 v1.10.0 实现并复测：015、016 关闭；014 的第 3 步（外壳取到新成员）2026-10-27 在 SDK 换版本的一轮发布里通过，014 关闭。2026-10-28 新开的 FRB-009（容器与 Kubernetes 上不注入 `PORT`）当天在 v1.10.1 修复、复测通过并关闭（`experiment-data/10-01/frb009/`）；本项目的待办：各组件、外壳与探针 Dockerfile 里的 `ENV PORT` 与注释“BrickKit injects PORT only for mode: local”已过时但无害，下次改动该组件时删掉（Python 探针与它的变体已在 3.2.20 删掉；Go 探针与它的变体还在）。
- **知识库**（2026-10-25 核对）：PR #16–#34 全部已合并并处理；#40（实测与一份反馈）、#41（f-longrun 的结束标记）2026-10-29 已合并；2026-10-30 待审查的是 #44（记录 26 的 LD、LP 一组）。近几个：#27（NATS 的 backoff、授权漏序列、金额列 numeric 对 bigint）、#29（Typst 对 WeasyPrint）、#30（健康检查的 HEAD、批量任务的加锁顺序、版本号单一来源）、#31（项目案例：改动的循环与两次 AI 考试）、#33（实测：文档里的图对 AI 有没有用——本项目“图只放在客户读的文档里”的依据）、#34（知识库的盲测改用无头会话；考试查不出“文档自洽却不是用户要的”）。还没交的只剩下面“任务结束时”的草稿。
  - 第 7 步怎样用：
    - 设计出账与信用时，05.21 可作参考，以本项目的协议 04、05 与边界卡为准；
    - 各国的法规（发票系列、电子发票报送，例如西班牙的 Verifactu 已推迟到 2027）不归知识库管，知识库只管技术；设计各法人的编号与开票时查官方来源，写进本项目的文档。
    - NATS 消费者设 `BackOff` 时，服务端用它的第一个值代替 `AckWait`，且它只管确认超时、不管 `Nak`：第一个值按处理时间 p99 的 2–3 倍定（NATS 2.12 实测）；
    - 金额列是 `NUMERIC(p,s)` 时，写入多出的小数位会被悄悄舍入（远离零）：应用里先按业务规则舍入再写；扫几百万行的报表，`numeric` 的求和、排序约慢一倍，联机请求看不出差别（PostgreSQL 16 实测，见 PR #27）；
    - 运行时角色要能用迁移角色建的序列：`bigserial` 需要另授 `USAGE ON SEQUENCES`，identity 列不需要。
- **性能发现一律交给知识库**（用户 2026-10-18）：写成好读的结论，原始数据作为同编号的日志文件一起提交。

## 任务结束时：知识库反馈

2026-10-29 对照 kb 的现状核对过旧草稿：第 7、9、10 项已并入 PR #19，第 8 项进了 PR #20；第 2、4、5 项 kb 已经写了（uni-app 编出 App、Go 的 `time/tzdata`、按保留期清理）；第 6 项基本覆盖（子目录模块的标签与 v2 路径都写了，只是没合在一处），不交；第 3 项（项目文档的表达方式缺总的选择）连同第 10 步测量碰到的三种干扰（桌面文件索引、远程桌面会话、网络开销一边在用户态一边在内核）与 Python 镜像不用 Alpine 的 CPU 理由，写成一份反馈加进 PR #40（`feedback/inbox/2026-10-29-measuring-conditions-image-reasons-expression.md`）。剩下的只有一项：

1. Linux 的 `CLOCK_MONOTONIC` 在系统休眠期间停走（`CLOCK_BOOTTIME` 才计入）；知识库选主相关文档（07.06 选主、07.10 时间与时钟）按单调时钟计租约时没有提醒这一点。提交前先在 Linux 上验证。
