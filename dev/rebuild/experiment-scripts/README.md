# 实验的脚本

代表部署实验（[实验计划](../experiment-plan.md)）各步用的脚本。每个脚本开头的注释写了它做什么、怎样用；这里只是按步骤的目录。读 `.env` 的脚本只把值读进环境变量、不打印。正式测量时运行器用 `be-acceptance` 某个标签的快照（`CONF=<快照>/conformance`），改工具时改在主工作树。

## 第 4 步：全面复测与性能跟进

从会话的草稿目录复制过来留底，脚本里的路径指向当时的草稿目录（`/tmp/claude-1000/…/scratchpad`），其中 `accenv.sh`、`itenv.sh` 只把 `.env` 里的密钥读进环境变量；换一次会话要先改这些路径。

| 脚本 | 做什么 |
| --- | --- |
| `checkall.sh`、`checkall-resume.sh` | 全面复测的 11 个阶段（协议、两个 SDK、验收、外壳、三个格的剖面、15 格固定速率测量）；`-resume` 只续跑测量 |
| `checkall_watch.py` | 复测的监视：问题立即报、预期上限只计数、每 5 分钟进度、结束报告；`--from-now` 供重挂 |
| `frb006deploy.sh` | FRB-006 的升级部署测试：旧版本建 D-H2、`brickkit upgrade` 三个外壳、核对与新建一致、部署测量剖面 |
| `profile_py.py` | 在 cProfile 下跑 Python 探针（调用方），负载驱动打 100/s |
| `cpu_per_request.py` | 调用方每个请求的 CPU 毫秒（读 `/proc`） |
| `variants.sh` | `sniffio`、`httptools` 的对比（已做，结果在 4-03） |
| `variants2.sh`、`plugin/uvloop_policy.py` | `uvloop`、aiohttp 的对比与兼容性的集成测试（T4.6c，待跑） |
| `gobench.sh` | Go SDK 的基准（`grpcx/bench_test.go`）在 `main` 与 `perf/httpx` 上的对比与 CPU 剖析（T4.6c，待跑） |

## 第 8、9 步：业务链与探针的格

| 脚本 | 做什么 |
| --- | --- |
| `cell-chain.sh` | 从空库起一个业务链的格：建、准备、构建、起、安装认领、种子两遍、L3（`SEED=0` 只到安装认领）；按格的 `row` 选引擎，按格的标记起连接池、切有根 Podman 或集群里的基础资源 |
| `runner9.sh` | 一批业务链的格依次跑完：空库空闲、带种子起格、基线、场景、结果摘要（默认与同一批的第一格比）、空闲、预热、负载、停；第 10 步的选项见开头注释 |
| `probe9.sh` | 一批探针的格：起格、空闲、每一跳每种操作的负载、停 |
| `round8.sh` | 第 8 步的测量轮 |
| `cluster-on.sh`、`cluster-create.sh`、`bin/kubectl` | K 行的 minikube 节点：起到 Pod 能解析宿主机为止；建（删除重建）profile `bek`，含全部宿主机端口；`kubectl` 转给 `minikube -p bek kubectl --` |
| `r8-summary.py`、`r8-compare.py`、`r8-empty-summary.py` | 第 8 步的表 |
| `r9-summary.py` | 第 9、10 步的表（组件、基础资源、平台、服务基础资源的 Docker；运行器的输出与归档的数据都能读） |
| `night9b.sh`、`night9c.sh`、`night9d.sh` | 第 9 步的第二夜、探针整批、S 层重测 |

## 第 10 步：套件 B

| 脚本 | 做什么 |
| --- | --- |
| `night10a.sh` | 探针整批接着 B1、B2（第 9 步与第 10 步各一批） |
| `night10b.sh` | B5：负载与数据加倍 |
| `night10c.sh`、`cap/` | B3、B4：整套放进限内存的 slice（`setup.sh`、`revert.sh` 由维护者以 root 执行；`limit.sh` 设上限，`sample.sh` 采 slice） |
| `night10d.sh`、`rootful/` | B6：有根 Podman（`setup.sh`、`revert.sh` 由维护者以 root 执行） |
| `night10e.sh`、`base-cluster/` | B7：基础资源放进集群（`base.yaml`、`casdoor.yaml`，`base-cluster.sh` 导出 Casdoor、起停集群里的基础资源与 Docker 里的） |
| `pybuild/` | 容器里的 Python 构建：三个变体的 Dockerfile、`build.sh`、`run.sh`（step10-plan 5.5） |

## 第 11 步：套件 C

| 脚本 | 做什么 |
| --- | --- |
| `runner11.sh` | 一批格依次跑完套件 C：起格与基线、整格的背景负载（`load -series`）、按顺序注入故障（`be-acceptance` 的 `conformance/faults/`，以及 `ops11.sh` 的 R3–R5）、每次之后的不变量（`cells invariants`）、停格；`FAULTS` 选故障，`sh:<命令>` 在两项之间跑本目录的一条命令 |
| `ops11.sh` | 在运行着的格上做运维动作：`burst`（R3，一阵出账与打印）、`upgrade`（R4，库存 3.0.9 连同依赖它的销售、出账；外壳格升 `be/go-core` 3.0.38）、`split`（R5，外壳拆回单跑再合回；任一方向的 L3 场景失败，这一项就失败）、`conns`（连接按角色与库） |
| `probes11.sh` | 把 K 格里一个组件的启动与就绪探针换成 BrickKit 的默认值或每 1 秒的一组，等滚出新 Pod（11-01 第 8 节） |
| `night11.sh` | D、K 两行的 S、H、X 六格，每行一批，约 7.5 小时 |
| `summary11.py` | 把 `runner11.sh` 的输出汇总成一份 Markdown：每格每项的结果、不变量、测试记下的计时、这一项期间背景负载失败的请求与 `processing` 的秒数（不计与故障无关的 `list.order` 404） |
| `burst11.py` | R3 的数字：每格那一阵出账打印的 300 次（成功、p50、p95），以及背景负载每秒 p95 在这一阵之前 5 分钟与期间的中位数、期间的最高 |

## 第 12 步：套件 D

| 脚本 | 做什么 |
| --- | --- |
| `runner12.sh` | 每格从零起格（探针格不灌种子）、跑 `be-acceptance` 的套件 D 测试（`TESTS`，默认 `compat`）、存测试输出与每个容器的日志、停格 |
| `runner12r.sh` | 其余各行的套件 D：没有 `also:` 的格跑 V4（`compat/test_pairs.py`），有的跑 V1（扩展测试、再 `brickkit up` 一次、旧版本的迁移再跑一次；K 行用 `port-forward` 给旧版本宿主机端口） |
| `smoke12.sh` | 其余各行的冒烟：P、L、LD、LP、K 的 V4，P、K 的 V1；K 行最后跑（它的节点占用各组件的宿主机端口） |
| `v1.sh`、`v1b.sh` | D12-V1、D12-V1b 上的 V1：默认版本与旧版本并排，扩展测试，再换到收缩迁移的版本或再跑一次迁移 |
| `p121check.sh` | G5（P1.21）发版后的真机核对：D12-H-a35 跑交易链，D12-py-a35 跑 Python 探针的成对测试 |
| `night12f5a.sh` | F5：只换 SDK 版本时探针的基础代价（空闲 300 秒，Go alpha.23 对 alpha.37、Python a20 对 a33） |
| `chain-release.py` | 连锁发布：全部重建的组件按依赖顺序换到新 SDK，依赖跟着刚发的版本走；每个组件自己的说明文件、`brickkit release --notes-file`、发完核对标签说明不是路径（第 12、13 步用） |

## 第 13 步：套件 E

| 脚本 | 做什么 |
| --- | --- |
| `runner13.sh` | 一批格依次跑完套件 E：起格（种子与 L3 场景）、基线、不变量；背景负载下依次做 `STEPS`（`scenarios`、`faults:<-k>`、`e4`、`e7`、`sh:<命令>`），每步之后不变量；停格前用 `cell-logs.sh` 存日志 |
| `podman-preflight.sh` | P、LP 两行起格前（`cell-chain.sh` 的第一段）：在用户的 systemd 里确认 `podman` 能建用户命名空间——VS Code 等 snap 里的终端可能放开了机器上别处不允许的东西（第 14 步、整个实验的复盘 K2）；`PODMAN_PREFLIGHT_WRAP="aa-exec -p unprivileged_userns --"` 让它变红 |
| `cell-logs.sh` | 停格前存下一个格的日志：每个容器或 Pod 的日志（按格的行选引擎）、`replica-counts.sh` 的逐副本计数、大于 256 KiB 的压缩；各运行器与 `cell-chain.sh` 都调用它，手工停格前也先跑它（第 13 步复盘 J4） |
| `replica-counts.sh` | 从存下的日志算每个容器、Pod 或进程服务的请求：全部、用户面（`/api`）、系统面（gRPC） |
| `holders.py` | 负载期间每 2 秒采样运行中工作项的持有进程，看每个副本都认领过工作 |
| `postgres2.sh` | E5 的第二个 PostgreSQL 实例 `be-postgres-2`（基础资源同一镜像与参数，宿主机 5433）；`cell-chain.sh` 在格用到它时先起 |
| `e7_rollback.py` | E7：业务库回退到 T、审计库不回退（协议 15 恢复的第 1–3 步），核对并算出审计损失 |

## 底层先行第 4 项：整套恢复的演练

演练脚本不在这里，在各次的数据目录里（`foundations-04-data/t8e`、`t9e`、`t10e`、`t11`、`t13e` 的 `drill.sh`）；共用的格是 `experiment-cells/R4-X`、`R4-G`。

- 演练脚本新加的**每一个**步骤（帮助程序、对外部产品的改动、调用的每个接口、核对的查询），先在开着的格上单独跑一遍，再整轮跑：整轮要先重建格（约 10 分钟），T9e–T11 有五次、T13e 有四次失败是脚本自己的步骤错了，T13e 第 2 次失败的正是没有试跑的一步（第 4 项复盘 R5、R9）。
- 签发者换了凭据或信任根（`be-ops trust`）之后，在格里 `brickkit up` 把新文件送进容器（BrickKit 复制 `file://` 的密钥），之前先等格里的容器都健康：暂停过的容器刚恢复时被判不健康，`up --wait` 会拒绝（复盘 R10）。
- 演练改了不在恢复组内的东西（Casdoor 里的账号）时，开头与结尾都复原，不靠上一次跑完：上一次可能中途停下。

## 整套系统换一个 SDK 版本

| 脚本 | 做什么 |
| --- | --- |
| `sdk-unify.py` | 全部依赖 `be-sdk-go/v3` 的组件按依赖顺序换到同一个 SDK 版本（同一个库在整个系统只用一个版本）：每个升最后一位、改依赖钉的版本、换 SDK、单元与集成测试、设计文档的实现状态一行、lint、提交、发布；`--dry-run` 只打印顺序与版本；失败停在那一个，修好后 `--from <ID>` 接着做。探针、外壳、组件索引与上层仓库的提交仍按手做（脚本开头写着）。第 4 项手工复制脚本做了四次（复盘 R4） |
