# 10-07 有根与无根 Podman（B6）

计划：[step10-plan.md](../step10-plan.md) 第 1 节 B6、第 4 节 2。问题：P 行一直用无根 Podman（容器的网络经用户态的 pasta 转发），换成有根 Podman（root 的 `podman.socket`，网络走内核的网桥与 NAT）开销差多少。Docker 照常跑基础资源（与每一行一样），组件在 Podman 里。无根与有根挨着跑，同一批，只在这一批内比。

## 1. 结论

**有根把 Podman 自己的开销降到约五分之一，整套每千次少 9–10%，延迟低 1–3 毫秒；但组件与数据库各多 3–9%，省下的一部分是记账换了地方。**

每千次请求的 CPU 秒（7 次/秒）与延迟：

| 格 | 组件 | 基础资源（其中 PostgreSQL） | Podman 的平台 | Docker（基础资源的守护进程） | 合计 | p50 / p95（ms） |
| --- | --- | --- | --- | --- | --- | --- |
| P9-S（单跑，无根） | 28.8 | 36.6（31.5） | 13.1 | 8.4 | 86.9 | 23.3 / 54.5 |
| P9-S-root（单跑，有根） | 30.0 | 37.6（33.5） | 2.9 | 8.4 | 78.9（少 9%） | 21.9 / 51.5 |
| P9-H（外壳，无根） | 21.8 | 35.5（30.4） | 12.9 | 8.5 | 78.7 | 23.2 / 52.1 |
| P9-H-root（外壳，有根） | 22.8 | 37.2（33.1） | 2.4 | 8.5 | 70.9（少 10%） | 21.8 / 50.1 |

- **Podman 自己**：无根时每个容器一个 conmon、一个 rootlessport，再加一个 pasta 在用户态转发全部网络，负载时 0.09 核、每千次 13 秒；有根时只剩 conmon（网络由内核的网桥与 NAT 做，没有 pasta、rootlessport），0.02 核、每千次 2.4–2.9 秒，少 78–81%。常驻内存 136 → 85 MiB（单跑），外壳格 56 对 64 MiB（容器少，本来就小）。
- **但组件与数据库多了**：组件每千次多 4–5%（28.8 → 30.0、21.8 → 22.8），PostgreSQL 多 6–9%（31.5 → 33.5、30.4 → 33.1）。原因推测：有根时容器之间、容器到宿主机端口的包在内核的网桥、veth 与 NAT 里处理，这部分 CPU 不归任何进程名，一部分以软中断的形式记在当时在跑的进程（常是收包的容器）的 cgroup 上；无根时这些工作在 pasta 里，记在 Podman 的平台上。所以平台少的 10 秒里约 2–3 秒挪到了组件与数据库上，净省 8 秒左右。内核里没有记到任何 cgroup 的那部分这次量不到（采样只读进程与容器的 cgroup），合计的“少 9–10%”可能略高估。
- **延迟**：p50 低 1.4 ms（23.3 → 21.9、23.2 → 21.8），p95 低 2–3 ms，各操作的 p95 也都持平或略低：少了用户态转发那一跳。开具到订单完成 p50 3.4–3.6 ms，不变。
- **对照**：Docker 那一份（基础资源的守护进程）四格都是每千次 8.4–8.5 秒，空闲 0.058–0.059 核，说明这一批的条件稳定。
- **正确性**：四格的 6 300 次请求全部成功，订单全部完成，结果摘要彼此相同。
- 同一批里外壳对单跑：组件少 24%（21.8 对 28.8），Podman 的平台几乎不变（12.9 对 13.1：pasta 一个进程转发全部流量，容器少了它不少）。

对选择的含义（给维护者）：有根更省、更快，但要 root 运行容器引擎，安全上退了一步；无根的代价约是整套每千次 8 秒、p50 1.4 ms。这次的负载下两种都远没到上限。

## 2. 测了什么

| 批 | 时间 | 内容 | 电源模式 |
| --- | --- | --- | --- |
| b6 | 2026-10-29 13:44–17:10 | P9-S、P9-S-root、P9-H、P9-H-root 依次（`night10d.sh` → `runner9.sh`；格写 `podman: rootful` 的发给 root 的 `podman.socket`）：每格空库起格与空闲 10 分钟、带种子起格（两遍与 L3）、基线（2 万张订单）、场景、结果摘要、空闲 10 分钟、预热 5 分钟、7 次/秒 20 个用户测 15 分钟 | performance，接电源，全程未变 |

开跑前检查过 root 的 Podman 可达（`podman info` 报 `rootless=false`）；P9-S-root 起格后核对过：12 个容器在 root 的 Podman 里，用户的 Podman 里没有。采样按进程名找 Podman 的进程（conmon、pasta、rootlessport、netavark、aardvark-dns、podman、catatonit），不管属于哪个用户，所以 root 的 conmon 也算进去了。

机器：16:58:42–16:58:55 有一次 13 秒的远程会话，落在 P9-H-root 的测量窗口里（`notes.txt`），只占宿主机的 CPU。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| 机器 | 同 9-01（i5-12450H，14 GiB） |
| 容器引擎 | Podman 5.7.0（无根：pasta 网络；有根：netavark 网桥，`rootful/setup.sh` 把 root 的 `podman.socket` 开给 docker 组、`DOCKER-USER` 放行 `podman+` 网桥）；基础资源在 Docker 29.9.2 |
| 组件 | P6.32 之后的版本，同 [10-05](10-05-memory-cap.md) |
| 工具 | `be-acceptance` v1.0.8 的快照；汇总 `experiment-scripts/r9-summary.py`、`experiment-scripts/breakdown.py --mem` |

## 4. 影响

- kb：记录 26（四种运行形态）补一组：有根与无根 Podman，同一批。
- 测完 B6 后由维护者执行 `rootful/revert.sh` 还原（不重启 Docker，可以随时做）。
- 没有量的：内核里没有记到 cgroup 的网络开销（要整机的 CPU 计数或 `perf` 才看得到）；更高负载下的差别。

## 5. 原始数据

`experiment-data/10-07/night10d/`：`night.log`、`notes.txt`；`b6/status.log`；每格的起格日志、`empty/idle.json`、`run/`（`idle.json`、`mix.json`、`driver.json`）、`digest.json`、`compare.log`；`b6/summary.md`（`r9-summary.py`；“platform”是 Podman 的进程，“docker”是基础资源的 Docker 守护进程）、`b6/breakdown.txt`（`breakdown.py --mem`，每个容器）。合计是组件、基础资源、平台与 Docker 四项相加。
