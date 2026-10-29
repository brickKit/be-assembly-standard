# 第 10 步计划：套件 B，附加对照

> 2026-10-27 起草。依据：[实验计划](experiment-plan.md)的“套件 B：附加对照”与“步骤与检查点”第 10 步；第 8、9 步的格、数据与负载（[8-01](experiment-records/8-01-d-row-chain.md)、[9-01](experiment-records/9-01-other-rows-chain.md)）。测量要等第 9 步的第二夜（step9-plan 8.6）做完、用户下令、机器安静。

## 1. 要回答什么

第 8、9 步量出了“各形态、各拓扑花多少”。套件 B 回答“为什么是这么多、到哪里会不够”：

| 项 | 问题 | 和已有结果的关系 |
| --- | --- | --- |
| B1 | 外壳省下的是不是主要是数据库连接？单跑前面加一个事务模式的连接池代理，能不能追上外壳 | 记录 27：12 个进程合成 3 个，服务 CPU 少 14–28%、内存少 32–37%；不知道其中多少来自每个进程各自的连接池 |
| B2 | 只用 PostgreSQL（PostgreSQL 队列代替 NATS JetStream）省多少，积压与延迟付出多少 | 第 4 步在探针上量过 PostgreSQL 队列的唤醒与上限（4-04）；业务链上没有 |
| B3、B4 | 整套放进 4 GiB、6 GiB 内存能不能跑；先坏的是什么 | 9-01：Docker 单跑的整套有数据、空闲时约 6.0 GiB（含数据库页缓存；基础资源 4958、组件 504、平台 545 MiB），不含页缓存约 1.6 GiB（673、380、545 MiB） |
| B5 | 负载加倍（40 个用户、14 次/秒）与数据加倍时资源怎样增长；哪种拓扑先到瓶颈 | 第 8、9 步只有 7 次/秒一档 |
| B6 | Podman 有根对无根：无根网络（pasta）与卷权限的代价 | P 行全是无根；有根与同机的 Docker 冲突（0-11） |
| B7 | 基础资源放进集群对放在集群外：集群本身与基础资源各占多少 | 第 9 步 K 行的基础资源都在集群外（Docker） |

## 2. 每项怎样做

| 项 | 格 | 怎样搭 | 缺的工具 | 测量时长 |
| --- | --- | --- | --- | --- |
| B1 | D9-S 加连接池代理，对照 D8-H（或第 9 步的 H 列） | PgBouncer 事务模式放在 PostgreSQL 前，组件的 `PG_HOST`／端口指向它；协议要求的 `SET LOCAL`、预编译语句设置（0-12 已验证：pgx 默认模式要 PgBouncer 开 `max_prepared_statements`） | `infra/` 里加 PgBouncer 容器与配置；格里换数据库地址 | 约 1 小时（一格） |
| B2 | D9-S、D9-X 用 PostgreSQL 队列 | `cell.yaml` 写 `bus: pgqueue`（已支持）；NATS 照常起但不用，单独量它空闲时的开销以算“少一个进程省多少” | 业务链格里核对每个发事件的组件都走 `BUS_URL` | 约 2 小时（两格） |
| B3、B4 | 候选默认格 1–2 个（按 9-01：Docker 或 Podman 的 H 列） | 整套（组件、基础资源、平台）放进一台 4 GiB、6 GiB 内存的虚拟机，跑同样的业务链；记下能不能起来、负载下先坏的是什么（被杀的进程、超时、交换） | 一台限内存的虚拟机与在里面起格的脚本 | 每格约 1 小时，共约 2–4 小时 |
| B5 | D9-S、D9-X | 负载 14 次/秒、40 个用户；数据 4 万张订单、4,000 个产品、1,000 个客户 | 基线数据的规模参数（现在写死在 `cells/baseline.py`）；运行器的 `RATE`、`USERS` 已有 | 约 2.5 小时（两格，基线灌得更久） |
| B6 | P9-S，有根对无根 | 有根 Podman 跑整格；Docker 停掉（与有根 Podman 冲突），基础资源改由有根 Podman 运行 | 基础资源在 Podman 下起停的脚本 | 约 1.5 小时；期间 Docker 停着 |
| B7 | K9-X，基础资源在集群内 | PostgreSQL、NATS、对象存储、Casdoor 部署进 minikube（StatefulSet 或简单的 Deployment 加卷），组件改连集群内的地址 | 基础资源的集群清单 | 约 1.5 小时 |

合计约 11–13 小时的测量，分三到四晚（每晚一组相关的项），每一晚之前先冒烟。

## 3. 已定的做法（AI 决定，供复核）

| 项 | 决定 | 理由 |
| --- | --- | --- |
| 流程 | 每格沿用第 9 步的完整流程（空库空闲、带种子起格、基线、摘要比较、空闲、预热、混合负载），结果摘要与 D8-S 比较（B5 数据加倍时另立参照） | 与套件 A 直接可比 |
| 遍数 | 每格一遍；差别在 10% 以内写“看不出差别” | 同第 9 步 |
| 版本 | 第 9 步第二夜之后的版本；需要改组件时照常升版本，不回头重测套件 A | 结论是对照，不追同一份二进制 |
| 先做的 | B1、B2、B5（只改配置与参数，工具小）；再 B7、B6；B3、B4 最后（要虚拟机） | 先拿便宜的、回答“外壳省的是什么”的 |

## 4. 要维护者定的（2026-10-28 都已定）

1. **B3、B4 的“整套内存上限”怎样做**：已定（用户 2026-10-28：不用虚拟机）。Docker 的全部容器（组件与基础资源）放进一个 systemd slice（`be-cap.slice`），给它设 `MemoryMax`：容器的页缓存记在各自的 cgroup 上，也在上限之内，所以量得到进程与页缓存争内存。Docker 自己（dockerd、containerd，约 0.5–0.7 GiB）不在 slice 里，上限取 4 GiB、6 GiB 减去它实测的用量。允许 1 GiB 交换（`MemorySwapMax=1G`，AI 定：小服务器通常有交换，“开始频繁交换”也是要看的一种坏法）。要维护者用 sudo 做一次：`/etc/docker/daemon.json` 加 `"cgroup-parent": "be-cap.slice"`、建 slice、重启 Docker（基础资源跟着重启）；测完改回。本机：cgroup v2，Docker 的 cgroup 驱动是 systemd（2026-10-28 核对）。
2. **B6 期间要停 Docker**（有根 Podman 与 Docker 冲突）：已定（用户 2026-10-28 同意）。那一晚停 Docker，基础资源改由有根 Podman 运行；停与恢复都由脚本做，不动数据盘上的 Docker 数据，测完恢复 Docker 与基础资源。

## 5. 进度

### 5.1 怎样搭（AI 定）

- **B1**：格写 `pooler: pgbouncer`（`be-acceptance` 的 `cells/spec.py`）。`cells prepare` 写 PgBouncer 的配置：事务模式，每个组件以自己的角色登录，由管理员角色查口令（`auth_query`）；按“库 + 角色”分池，每池 5 条后端连接（第 9 步外壳里每个成员约 6.5 条：go-core 4 个成员 26 条；单跑每个业务组件约 12 条，`experiment-data/9-01/r91/*/mix.json` 的 `db_connections`）；协议层预编译语句开（`max_prepared_statements = 200`，0-12）。运行连接 `PG_PORT` 6432 指向它，迁移经 `PG_MIGRATION_HOST`／`_PORT` 直连 5432（[数据库引擎与连接](../../docs/zh/04-foundations/05-database-engine.md)的要求；两种 SDK 与业务链 12 个组件都已支持）。`cell-chain.sh` 在准备之后起容器 `be-pgbouncer`（PgBouncer 1.26.0，按摘要固定镜像，挂在 `be-net`，宿主机端口 6432），停格时删掉；采样把它算进基础资源。
- **B2**：格写 `bus: pgqueue`（已支持）；NATS 照常起着不用，所以基础资源含 NATS 空闲的开销，记录里单列。
- **B5**：同时把负载与数据加倍分不出各自的影响，所以分开：每格先跑 7 次/秒、20 个用户，再在同一份数据上跑 14 次/秒、40 个用户（运行器的 `RATE2`、`USERS2`）；D9-S、D9-X 用第 8 步的基线，D9-S-x2、D9-X-x2 用两倍（格写 `baseline_scale: 2`：4 万张订单、4,000 个产品、1,000 个客户），两格的结果摘要在它们那一批里互相比（运行器默认）。脚本 `night10b.sh`，约 5.5 小时，另一晚。

### 5.2 第一批：B1 + B2（2026-10-28，已完成）

对比只在同一批里做（用户 2026-10-28 定），所以参照与改动放进同一批：D9-S、D9-H、D9-X（参照），D9-S-pgb（B1），D9-S-pgq、D9-X-pgq（B2）。六格，流程同第 9 步（`runner9.sh`），约 5.5 小时。

- 安排（用户 2026-10-28 定）：第 9 步的探针整批（step9-plan 8.7）先跑，跑的时候只写代码与配置、不构建不起容器；探针跑完后冒烟，通过就自动开跑这一批（机器安静到约 13:30）；失败的格记下、不重试，其余各格照跑。
- 冒烟：D9-S-pgb 通过（00:46；每个组件的后端连接都限在 5 条以内，单跑时约 12 条）；D9-S-pgq、D9-X-pgq（06:43–07:07）除审计记录多 16 条外通过（5.3）；D9-H、D9-X 只是 P9-H、P9-X 换成 D 行，没有另外冒烟。
- 结果：07:08–12:13 跑完，六格全过，写进记录 [10-01](experiment-records/10-01-pooler-and-pgqueue.md)（原始数据 `experiment-data/10-01/b12/`）。

### 5.3 已查清：多 16 条审计记录是种子的日期窗口，不是缺陷

B2 的两格冒烟与第一批的六格都比 D8-S 的结果摘要多 16 条审计记录（112265 对 112249），业务各项都相同，第一批里走 JetStream 的 D9-S 也一样，所以与消息系统无关。原因：`mdm/currency` 的种子写“最近 60 天里每个工作日”的汇率（`cmd/seed/main.go`，8 个货币对、两个方向，每个工作日 16 条，每条一条审计记录），窗口里的工作日数随今天是星期几变：10-25 到 10-27 是 42 个，10-28 是 43 个。D8-S 的参照摘要生成于 10-25（42 个），之前各轮都在 42 个的日子里跑，所以一直相同。第一批的监视按这一条过滤，六格互相相同（都是 112265）。原始数据与查询在 `experiment-data/10-01/pgq-audit/`（D9-S 的明细在它的预热段里取，不在测量窗口内）。

已改（用户 2026-10-28 同意）：运行器默认与同一批的第一格比（`REF=first`；要和某个文件比时 `REF=<digest.json>`），符合“对比只在同一批里做”，也不再受日期影响。种子保持“相对今天”（演示数据要的是最近的汇率），不改。

### 5.4 剩下的测量（工具都已冒烟通过，等维护者下令与机器安静）

| 项 | 一晚的脚本 | 时长 | 本机要先有的设置 | 冒烟 |
| --- | --- | --- | --- | --- |
| B3、B4 | `night10c.sh` | 约 5.5 小时 | `cap/setup.sh`（已执行，平时不限） | D9-H-m4 通过 |
| B5 | `night10b.sh` | 约 5.5 小时 | 无 | D9-S-x2 通过 |
| B6 | `night10d.sh` | 约 3.7 小时 | `rootful/setup.sh`（已执行） | P9-S-root 通过 |
| B7 | `night10e.sh` | 约 2 小时 | 重建的 `bek`（已重建） | K9-X-cb 通过 |

每晚的快照取 `be-acceptance` **v1.0.8**：v1.0.7 修了采样把 Docker 容器的 cgroup 写死在 `system.slice` 下（B3、B4 的容器在 `be-cap.slice` 里，否则全读不到），却让 K 行读不到 Pod，v1.0.8 修好。B3、B4、B6 测完后，维护者用 `cap/revert.sh`、`rootful/revert.sh` 还原本机的设置。

**B3、B4：整套放进限内存的 slice**（第 4 节 1）

- 工具（`experiment-scripts/cap/`）：`setup.sh`（root，维护者执行一次：Docker 的 `cgroup-parent` 改成 `be-cap.slice`、装 slice、`/etc/sudoers.d/be-cap` 只许免密执行 `limit.sh` 的三条固定命令、重启 Docker）、`revert.sh`（root，全部还原，并停掉空了的 slice）、`limit.sh <4G|6G|none>`（slice 的上限 = 预算减去 Docker 自己约 0.7 GiB：3300M、5300M；交换 1G）、`sample.sh`（每 5 秒记 slice 的内存、交换、`memory.events`、内存压力；slice 的路径向 systemd 查，它在 `be.slice` 下）。
- 格：D9-H-m6、D9-S-m6、D9-H-m4、D9-S-m4（cell.yaml 写 `memory_cap`）；`runner9.sh` 在 `CAP_RESET=1` 时每格设上限、整格采样、停格前记下每个容器的状态与退出码。
- 一晚：不限的 D9-H、D9-S 作参照，再 6 GiB、4 GiB 各两格；开跑前检查基础资源确实在 slice 里、上限能免密设置。
- 冒烟：维护者执行了 `setup.sh`（两次，中间还原过一次，两个脚本都验证过）。D9-H-m4（13:47–13:59，短参数）：整套在 3300M 里走完起格、基线、摘要与负载；峰值碰到上限（3299 MiB），交换最多 22 MiB，`memory.events` 的 max 3542 次（回收页缓存），没有 OOM，内存压力 0；负载 210 次全部成功，7 个容器都采到；格完上限自动回到不限。

- 结果：2026-10-29 03:41–08:46 六格全过，写进记录 [10-05](experiment-records/10-05-memory-cap.md)：4 GiB 放得下、什么也没坏，让出的只是页缓存；找坏点要更低的上限；维护者 2026-10-29 定不加档。

**B5：负载与数据加倍**（5.1）

- 一晚：`night10b.sh`。
- 冒烟：D9-S-x2（12:15–12:35，短参数）：两倍基线 766 秒（4,000 个产品、4 万张订单，0 失败），摘要设为同批参照，7 次/秒 210 次、14 次/秒 420 次全部成功；D9-X-x2 只是 D9-X 加倍数据，没有另外冒烟。

- 结果：2026-10-29 08:47–13:44 四格全过，写进记录 [10-06](experiment-records/10-06-load-and-data-x2.md)：负载加倍核数只多约一半、每千次少约四分之一；数据加倍服务不变、数据库多 10–15%；延迟都不变。

**B6：有根 Podman**（第 4 节 2）

- 做法改了（AI 定）：**不停 Docker**。第 0 步（0-11）证实有根 Podman 不通只因 Docker 把 FORWARD 默认设为丢弃，在 `DOCKER-USER` 里放行 Podman 的网桥即可；这样基础资源留在 Docker、与无根的 P 行一样，对比只差有根与无根一处，也不用停掉本机的 Docker（第 4 节的同意仍在，用不上）。
- 工具（`experiment-scripts/rootful/`）：`setup.sh`（root，维护者执行一次：root 的 `podman.socket` 组改为 docker 并启用、`/run/podman` 设为 0711、`DOCKER-USER` 加两条 `podman+` 的放行）、`revert.sh`（root：清掉有根 Podman 里的容器、网络与镜像，停用 socket、目录回 0700、删覆盖与两条规则）。
- 格：P9-S-root、P9-H-root（cell.yaml 写 `podman: rootful`）；`runner9.sh` 对这样的格设 `CONTAINER_HOST=unix:///run/podman/podman.sock`（podman 因此走有根的服务）。
- 一晚：P9-S、P9-S-root、P9-H、P9-H-root；开跑前检查有根 Podman 能连上。
- 冒烟：维护者执行了 `setup.sh`（第一次 `/run/podman` 仍是 0700、连不上，脚本补了 `chmod 0711` 后再执行）。P9-S-root（14:04–14:17，短参数）：镜像经远端的 `podman load` 导入、`podman compose` 跟着 `CONTAINER_HOST` 起在有根 Podman 里（无根里没有它的容器）、各段全过，负载 210 次全部成功，16 个容器与 Podman 的平台进程都采到，停格后有根 Podman 里无残留。

**B7：基础资源放进集群**（维护者同意删除重建 `bek`）

- 集群：`cluster-create.sh` 重建 `bek`（参数同第 9 步），另把宿主机 15432、14222、19000、18000 映射到节点 31432、31422、31900、31800：节点每次启动都绑定全部端口，而 Docker 的基础资源占着 5432 等，所以用另一组端口。
- 基础资源：`base-cluster/base.yaml`（PostgreSQL、NATS、RustFS，命名空间 be-base，与 compose 同镜像同配置，数据在 emptyDir；一个 Service `base` 按端口名分到各 Pod，另一个 NodePort）、`casdoor.yaml`；`base-cluster.sh` 的 `dump`（从 Docker 的 PostgreSQL 导出 Casdoor 的 schema）、`up`（导入镜像、密钥与配置、起三个、导入 Casdoor、起 Casdoor、核对宿主机端口）、`down`、`docker-stop`、`docker-start`。
- 格：K9-X-cb（`base: cluster`，v1.0.8：组件连 `base.be-base.svc.cluster.local`，采样把 be-base 的 Pod 记作 `base:*`，`r9-summary.py` 把它们算进基础资源、从集群平台里减去）；`cell-chain.sh`、`runner9.sh` 对这样的格改用新端口、到集群里读 Casdoor 的客户端密钥；`KEEP_CLUSTER=1` 让运行器结束时不停节点。
- 一晚：K9-X（基础资源在 Docker）→ 导出、停 Docker 的基础资源、起集群里的 → K9-X-cb（摘要与 K9-X 比）→ 换回；出错也换回（`trap`）。
- 冒烟（16:5x–17:09，短参数）：四个基础资源在集群里起来，Casdoor 的账号与密钥导入后可用；K9-X-cb 起格、基线、场景、摘要、负载全过（210 次全部成功），`base:*` 四个 Pod 都采到；之后 Docker 的基础资源回来、节点停。空库空闲段失败，查出 v1.0.7 的缺陷：minikube 节点的 systemd 在 `init.scope` 里，按进程取 cgroup 找不到节点下的 Pod（所有 K 行的格都会这样）；v1.0.8 改为往上取到容器自己的 scope，有测试。

### 5.5 容器里的 Python 构建（2026-10-28 加，AI 定）

9-02 里本机进程的 Python 每一跳少约 20% CPU，查出是解释器的构建不同：探针镜像用官方 `python:3.15.0-alpine`（musl、GCC 15.2，只开 LTO，没有 PGO），本机是 uv 装的 python-build-standalone（Clang 23.1，PGO、完整 LTO、BOLT、mimalloc、tail-call 解释器）。生产的 Python 组件（`infra/print`、`be/py-render`）用的是官方 `python:3.15.0-slim-trixie`（glibc、GCC 14.2，PGO 与 LTO），所以要回答的是：镜像里换成 python-build-standalone，比现在的 slim 省多少，值不值得改锁定的技术栈。

- 变体（`experiment-scripts/pybuild/`，`build.sh` 从同一份探针源码构建，每个变体按端口出两个镜像）：alpine（198 MB）、slim（302 MB）、pbs（Debian trixie slim 上装 python-build-standalone 3.15.0，397 MB）。
- 一批（`run.sh`，约 50 分钟）：格 D9-probe-pyonly（两个 Python 探针互相调用），变体按 alpine、slim、pbs、pbs、slim、alpine 各跑两遍（对称排，批内的漂移看得出）；每遍空闲 2 分钟，再四种操作 200 次/秒。每遍之前把 `test-probe-py:3.2.19`、`test-probe-py2:3.2.19` 标到这个变体（只在本机，原镜像留作 `:3.2.19-orig`，结束时标回，出错也标回）。
- 冒烟（17:43–17:46，短参数）：三个变体都起格、两条边各 250 次全部成功，原镜像已标回。第一次冒烟失败是变体镜像没写 `ENV PORT`（探针镜像自己写了，平台没注入），已补。
- 结果：2026-10-29 02:50–03:41 跑完，写进记录 [10-04](experiment-records/10-04-python-builds.md)：pbs 比 slim 只少 2–5% CPU，alpine 比 slim 多 19–28%；建议生产继续用 slim（待维护者定），探针镜像是否改用 slim 一起提给维护者。

### 5.6 外壳格里 PostgreSQL 的内存（2026-10-28，已查清）

10-01 里外壳格 PostgreSQL 的内存最大，分不清是外壳还是时间。`experiment-scripts/pgmem.sh` 同一批起 D9-S、D9-H（带种子、灌基线），读每条后端连接的私有内存：外壳的一条连接为几个成员各缓存一套表，约是单跑的 2.4 倍，连接少了、总量反而多约 210 MiB。记录 [10-02](experiment-records/10-02-postgres-backend-memory.md)。外壳的连接池上限、连接的最长寿命可以再调，未量。

### 5.7 没做的小事

- 本机进程那一行的会话日志一格 60–80 MB：不改测量工具。要截短就得在工具里加一层读管道的进程，而 L 行的平台读数含看护会话，加的这一层可能算进去、让 L 行与之前的数据不可比；日志只占磁盘，归档时压缩（r94、r95 已这样做）。

### 5.8 空闲时数据库的工作大半是发件转发器空转（2026-10-28，已改 SDK，2026-10-29 量完）

查 PgBouncer 空闲也占 0.05 核时发现（5.7 之前的第 4 项）：一格单跑空闲 60 秒，数据库每秒约 1 650 条语句，其中发件表的编号与转发占 85–90%（编号与转发的语句 55 226 次、执行 2 508 ms；`begin`、`commit`、会话设置大多也属于它们）。原因：转发器每 250 ms 轮询一次，对每个分区做一个完整的编号事务（写计数行、锁、读纪元、挑行、更新、读待发布的行），发件表是空的也照做；8 个发事件的组件每个每秒约 17 个这样的事务。PgBouncer 空闲的 CPU、PostgreSQL 与组件空闲的 CPU 有相当一部分来自这里。

- 改法（维护者 2026-10-28 同意“现在改，改完再测 B3–B7”）：协议 P6.32（`be-protocol` 3.0.0-alpha.27）：轮询先用一条只读语句（走未编号与未发布两个部分索引）找出有行要转发的（流，分区），只对它们取租约、编号与读取；轮询间隔、提交后的唤醒（P6.29）与延迟不变。`be-sdk-go` 3.0.0-alpha.36、`be-sdk-python` 3.0.0a32，各有一条先红后绿的测试（空闲时轮询一次不写计数行；写一个事件后只出现那一个分区）。alpha.26 漏了重新生成向量的校验和，自己的检查不过，不能用；alpha.27 是它加上校验和。
- 连锁发布：12 个组件（iam-casdoor 3.0.10、authz 3.0.11、audit 3.0.8、org 3.0.9、currency 3.0.10、partner 3.0.12、product 3.0.12、inventory 3.0.8、credit 3.0.8、sales 3.0.13、billing 3.0.12、print 3.0.7）与外壳（go-infra 3.0.36、go-core 3.0.36、py-render 3.0.26），`make pin-check` 归零；第 9、10 步的 58 个格换到这些版本。billing 先发了 3.0.11，其可选依赖（对象写法）还是旧版本，pin-check 查出后补发 3.0.12、go-core 补发 3.0.36。py-render 的 `override-dependencies` 原把 Python SDK 钉在 a30（来源写 a31），这次一起改成 a32。
- 核对（只计数，不受机器负载影响）：同样一格单跑空闲 60 秒，语句从每秒约 1 650 条降到约 634 条（少 62%），发事件的组件每个每分钟约 10 980 → 3 344 条（少 70%）。剩下最多的是后台任务的领取轮询（每个组件每秒约 8.5 次，到期与过期租约一起查）；后台任务有按时间排定的，不能照搬“没有就跳过”，作为下一个候选，未改。
- 结果：`night10f.sh` 2026-10-29 01:08–02:50 跑完（第一次快照缺 `load/`，重跑），写进记录 [10-03](experiment-records/10-03-outbox-idle-poll.md)：空闲时 PostgreSQL 少 36–48%、组件少 31–35%，7 次/秒每千次合计少 17%，延迟与结果不变。
- 已知：`be-sdk-go` 的 `events/pgqueue.TestABacklogDoesNotSlowEachClaim`（积压 2 万条与 20 条的领取耗时之比）改前改后都时过时不过（改前 4 次 3 次失败），门槛对几毫秒的读数太紧；测试不改，待单独看。
