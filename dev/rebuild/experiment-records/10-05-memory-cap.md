# 10-05 整套放进 6 GiB、4 GiB 内存（B3、B4）

计划：[step10-plan.md](../step10-plan.md) 第 1 节 B3、B4，第 4 节 1，第 5 节的“B3、B4：整套放进限内存的 slice”。问题：一台 4 GiB、6 GiB 内存的机器放不放得下整套（组件、基础资源、平台），负载下先坏的是什么。不用虚拟机（维护者 2026-10-28 定）：Docker 的全部容器放进一个 systemd slice，给它设内存上限。参照与限额放在同一批里，只在这一批内比。

## 1. 结论

**4 GiB 放得下，什么也没坏：让出去的只是页缓存。** 六格的 6 300 次请求全部成功，结果摘要彼此相同，没有 OOM、没有容器被杀或重启；延迟与 CPU 和不限时一样。

| 格（D 行） | slice 上限 | slice 峰值 | 交换峰值 | 内存压力峰值（some / full，10 秒均值） | 这一格里触发上限的次数 | 请求 p50 / p95（ms） | 每千次 CPU 秒（组件 / 基础资源 / 平台） |
| --- | --- | --- | --- | --- | --- | --- | --- |
| D9-H（外壳） | 不限 | 5 653 MiB | 27 MiB | 0 / 0 | 0 | 22.6 / 51.1 | 23.7 / 38.2 / 11.3 |
| D9-S（单跑） | 不限 | 5 792 MiB | 27 MiB | 0 / 0 | 0 | 22.8 / 50.8 | 29.8 / 37.0 / 16.1 |
| D9-H-m6 | 5 300 MiB | 5 297 MiB | 32 MiB | 0 / 0 | 886 | 22.5 / 50.7 | 23.9 / 38.7 / 11.3 |
| D9-S-m6 | 5 300 MiB | 5 299 MiB | 28 MiB | 0 / 0 | 673 | 22.8 / 50.7 | 29.8 / 38.3 / 16.1 |
| D9-H-m4 | 3 300 MiB | 3 300 MiB | 45 MiB | 0.36% / 0.36% | 14 979 | 22.4 / 50.9 | 23.7 / 37.8 / 11.3 |
| D9-S-m4 | 3 300 MiB | 3 299 MiB | 68 MiB | 0.45% / 0.18% | 19 009 | 22.8 / 51.2 | 29.9 / 38.5 / 16.1 |

- slice 的上限是预算减去 Docker 自己（dockerd、containerd、shim 与 docker-proxy，约 0.7 GiB，在 slice 外）：6 GiB → 5 300 MiB，4 GiB → 3 300 MiB；交换最多 1 GiB。
- **不限时整套的容器峰值 5.5–5.7 GiB**，所以 6 GiB 刚好卡在边上、4 GiB 要让出约 2.4 GiB。让出去的是页缓存：负载时 PostgreSQL 的容器内存（含页缓存）从 3.0–3.3 GiB 降到 1.6–1.9 GiB，NATS 从 0.6–0.7 GiB 降到 0.11–0.17 GiB，RustFS 0.6 → 0.5–0.6 GiB；不含页缓存的部分（`anon`）不变（PostgreSQL 外壳格约 0.8 GiB、单跑约 0.56 GiB，NATS 约 20 MiB）。
- 4 GiB 下内核一直在回收（一格里触发上限 1.5–1.9 万次，6 GiB 时 670–890 次），但内存压力的峰值不到 0.5%，交换只用了 45–68 MiB；延迟（p95 50.9–51.2 对 50.8–51.1 ms）看不出差别；每千次 CPU 与不限时相差不超过 5%（基础资源 37.0–38.7 秒），且不随上限单调变化（外壳格 4 GiB 的 37.8 反而最低），按波动看待，这一批没有同一格的重复。
- **这一批没有找到“先坏的是什么”**：4 GiB 离坏还远。整套不能被回收的部分约 1.2 GiB（基础资源与组件的 `anon`：外壳格 0.93 + 0.24 GiB，单跑 0.68 + 0.38 GiB），加上 slice 外的 Docker 约 0.7 GiB，估计到 2–2.5 GiB 才开始挤进程的内存。要找坏点得再降上限（3 GiB、2 GiB）；`limit.sh` 只许免密设 4G、6G 与不限（`/etc/sudoers.d/be-cap` 固定了这三条），加档要维护者改 sudoers，作为提议，未做。
- 同一批里外壳省的：组件 CPU 每千次 23.7 对 29.8 秒（少 20%），平台 11.3 对 16.1 秒（少 30%）；PostgreSQL 的 `anon` 外壳格多约 250 MiB（810 对 553 MiB），与 [10-02](10-02-postgres-backend-memory.md) 一致。

## 2. 测了什么

| 批 | 时间 | 内容 | 电源模式 |
| --- | --- | --- | --- |
| b34 | 2026-10-29 03:41–08:46 | D9-H、D9-S（不限）、D9-H-m6、D9-S-m6、D9-H-m4、D9-S-m4 依次（`night10c.sh` → `runner9.sh`，`CAP_RESET=1`）；每格：设上限、整格每 5 秒采样 slice（`cap/sample.sh`）、空库起格与空闲 10 分钟、带种子起格（两遍与 L3）、基线（2 万张订单）、场景、结果摘要、空闲 10 分钟、预热 5 分钟、7 次/秒 20 个用户测 15 分钟、停格前记下每个容器的状态 | performance，接电源，全程未变 |

开跑前检查过：基础资源在 `be-cap.slice` 里，上限能免密设置；结束时上限回到不限。机器上没有别的工作（系统日志里只有 `limit.sh` 的 sudo 与一次 13 秒的远程会话：08:23:09–08:23:22，落在 D9-S-m4 的 7 次/秒窗口里，只占宿主机的 CPU，见 `notes.txt`；GNOME 文件索引 02:56 起停着）。

每格 slice 的第一个采样在设上限的同一刻取，带着上一格留下的页缓存（D9-H-m4 第一个样本 4 415 MiB），5 秒后回收到上限以内；表里的峰值去掉了每格的前两个样本。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| 机器 | 同 9-01（i5-12450H，14 GiB，Docker 29.9.2，cgroup v2，Docker 的 cgroup 驱动是 systemd） |
| 组件 | P6.32 之后的版本（同 [10-03](10-03-outbox-idle-poll.md) 的 D9-S）；外壳 `be/go-infra` 3.0.36、`be/go-core` 3.0.36、`be/py-render` 3.0.26 |
| 上限 | `be-cap.slice`（`cap/setup.sh`：Docker 的 `cgroup-parent`）；`MemoryMax` 5300M／3300M、`MemorySwapMax` 1G（`cap/limit.sh`） |
| 工具 | `be-acceptance` v1.0.8 的快照；汇总 `experiment-scripts/r9-summary.py`、`experiment-scripts/breakdown.py --mem` |

## 4. 影响

- 实验报告：“整套最小要多少内存”的回答是“4 GiB 放得下，不坏；更小的没量”；部署文档里的最小内存可以按 4 GiB 写（含 Docker 自己），6 GiB 能留出页缓存。
- kb：记录 26、27 补一组（整套在限内存下的表现，外壳与单跑同一批）。
- 维护者 2026-10-29 定不加 3 GiB、2 GiB 两档；`cap/revert.sh` 在全部测量跑完后由维护者执行（它会重启 Docker）。

## 5. 原始数据

`experiment-data/10-05/night10c/`：`night.log`、`notes.txt`；`b34/status.log`；每格的 `cap.log`（设的上限）、`cap.tsv`（每 5 秒：slice 的内存、交换、`memory.events` 的 high、max、oom、oom_kill，内存压力 some 与 full 的 10 秒均值）、`containers.txt`（停格前每个容器的状态、退出码、是否 OOM、重启次数）、起格日志、`empty/idle.json`、`run/`（`idle.json`、`mix.json`、`driver.json`）、`digest.json`、`compare.log`；`b34/summary.md`（`r9-summary.py`）、`b34/breakdown.txt`（`breakdown.py --mem`，每个容器的核数、每千次 CPU、内存与 `anon`）。表里的峰值由 `cap.tsv` 去掉前两个样本后取最大值；`memory.events` 是 slice 一直累加的计数，“这一格里触发上限的次数”是这一格最后一个样本减第一个样本。
