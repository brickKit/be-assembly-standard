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
