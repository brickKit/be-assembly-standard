# 实验档案

> 代表部署实验（[计划](../experiment-plan.md)）每一项测试的完整记录，给以后查细节用。每项测完立刻写，结构见计划的“记录与报告”。原始输出在 [`../experiment-data/`](../experiment-data/)。给人看的结论在报告（`../experiment-report.md`，测到可以汇总时建立）。

## 索引

| 编号 | 测什么 | 在哪一格 | 日期 | 结果 | 记录 |
| --- | --- | --- | --- | --- | --- |
| 0-01 | `GOPRIVATE` 让 Go 绕过公共代理与校验和库 | 第 0 步 | 2026-10-16 | 部分通过；决定改为不重用版本号（A110），后一半不再补验 | [0-01-goprivate.md](0-01-goprivate.md) |
| 0-02 | 同一版本号删掉重发：BrickKit 的发布与两层缓存 | 第 0 步 | 2026-10-16 | 通过；发现缓存静默给出旧内容，成为改用新号（A110）的理由；v1.5.0 复测改为报 `VERSION_CHANGED`（FRR-002） | [0-02-reused-version-brickkit.md](0-02-reused-version-brickkit.md) |
| 0-03 | 一个仓库放多个组件（探针） | 第 0 步 | 2026-10-16 | 通过；v1.4.1 时 `add` 加不进子目录组件；v1.5.0 复测：写 `repo` 的安装源后 `add` 一条命令写好三层（FRR-003） | [0-03-monorepo-components.md](0-03-monorepo-components.md) |
| 0-04 | Go 外壳承载成员；成员版本不一致时被拒 | 第 0 步 | 2026-10-17 | 通过；BrickKit 拦下三种不一致，“编进的代码与声明不符”只有外壳启动器能拦（协议 17 已要求）；C3b 报错不够直接（FRR-004）；v1.6.0 复测：报错写出本地仓库的版本与两条出路；v1.6.1 复测：`up` 对只写 `image`、旁边有 `Dockerfile` 的组件给出警告（FRB-001） | [0-04-go-shell-members.md](0-04-go-shell-members.md) |
| 0-05 | 全部组件与外壳 `mode: local`（`target: docker`，基础资源在 Docker） | 第 0 步 | 2026-10-17 | 通过；看护行为与文档一致；`local` 不跑迁移且提示给出镜像路径（FRR-005），端口被占时先误报“listening”（FRB-002）；Go 的 `go run` 常驻；v1.7.0、v1.7.1 复测：端口先查、本机进程与本机外壳的成员都从源码迁移（FRB-002、FRR-005、FRB-003） | [0-05-all-local.md](0-05-all-local.md) |
| 0-06 | 本机进程与 Podman 混合（无根，`target: podman`） | 第 0 步 | 2026-10-17 | 通过；三种布局都通，无根 Podman 的 `host-gateway`（pasta，169.254.1.2）可用；没有 BrickKit 的问题 | [0-06-local-podman.md](0-06-local-podman.md) |
| 0-07 | minikube 跑 BrickKit 生成的 K8s 清单（含外壳） | 第 0 步 | 2026-10-17 | 通过（v1.7.2）；部署、迁移 Job、拆回、拒绝 `local`/`debug` 与错 context 都正常；v1.7.1 时调用外壳成员的地址在 K8s 上不可达（FRB-004），v1.7.2 改为写成员名后复测通过 | [0-07-minikube.md](0-07-minikube.md) |
| 0-08 | 同一组件两个版本并存（`requiredBy`） | 第 0 步 | 2026-10-17 | 通过；`add` 自动保留兼容版本、外壳编进的版本之外的版本单独运行；迁移按版本串行；迁移顺序保护有效 | [0-08-two-versions.md](0-08-two-versions.md) |
| 0-09 | 同一组件两个副本 | 第 0 步 | 2026-10-17 | K8s 上通过（PDB、两个端点、迁移只跑一次、删副本不中断）；Docker、Podman 下 `replicas` 被忽略，套件 E 的 E1–E4 改在 K8s 两格（FRR-006） | [0-09-two-replicas.md](0-09-two-replicas.md) |
| 0-10 | 两个 PostgreSQL 实例 | 第 0 步 | 2026-10-17 | 通过；分实例完全靠配置覆盖；单跑、外壳、本机外壳下每个组件都连到自己的实例；特殊字符的密码在三条注入路径上一致 | [0-10-two-postgres.md](0-10-two-postgres.md) |
| 0-11 | Podman 有根与无根 | 第 0 步 | 2026-10-17 | 无根通过（0-06）；有根下 BrickKit 流程与到宿主机进程都正常，但与同机的 Docker 冲突：容器之间不通（已证实：Docker 的 FORWARD DROP 加 `br_netfilter`），健康检查全绿；B6 改在没有 Docker 的条件下跑 | [0-11-podman-rootful.md](0-11-podman-rootful.md) |
| 0-12 | 连接池代理的事务模式与 `SET LOCAL`、pgx 的预编译语句 | 第 0 步 | 2026-10-17 | 通过；`SET LOCAL ROLE`（`INHERIT FALSE`）、`SET LOCAL` 超时、事务级应用锁、`SKIP LOCKED` 都成立；禁止的写法实测泄漏；pgx 默认模式要求 PgBouncer 开 `max_prepared_statements` | [0-12-pooler-transaction-mode.md](0-12-pooler-transaction-mode.md) |
| 4-02 | 三个外壳按标签编进成员；部署好的格里通过剖面；重做 0-04 的 C4、C5 | D·H2（探针） | 2026-10-18 | 通过；C4 由 BrickKit 拒绝、C5 由外壳启动器拒绝；途中补了 P4.26 与三处 SDK 缺口；升级共用成员的外壳失败（FRB-006） | [4-02-shells.md](4-02-shells.md) |
| 4-03 | 全面复测：全部测试与 15 格固定速率测量，按操作设合理上限 | 第 4 步（全部 D 格） | 2026-10-18 | 找出并修好六处问题（Nagle、大事件逐条上传、PostgreSQL 队列跟不上积压、低负载下的轮询延迟、Python 的 HTTP 开销、对象存储累积），五处功能测试全过、只有测量看得出；三类预期上限写进报告；协议 P1.19、P6.28、P6.29 | [4-03-full-check.md](4-03-full-check.md) |
| 4-04 | D 行的结果：性能跟进之后的复测、电源模式、后台任务的唤醒 | 第 4 步（D 行全部格） | 2026-10-18 | T4.6c 的修复全格兑现；同一份代码 performance 下延迟与每次操作的 CPU 约为 power-saver 的 0.6 倍，从此记下电源模式；relay 全部格 p50 约 250 ms，修为提交后唤醒（P7.21） | [4-04-d-row.md](4-04-d-row.md) |
