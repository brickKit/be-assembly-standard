# 10-04 容器里的 Python 构建：alpine、slim 与 python-build-standalone

计划：[step10-plan.md](../step10-plan.md) 5.5。起因：[9-02](9-02-probes-all-rows.md) 里本机进程的 Python 每一跳少约 20% CPU，查出是解释器的构建不同。探针镜像用官方 alpine，生产的 Python 组件（`infra/print`、`be/py-render`）用官方 slim，本机用 uv 装的 python-build-standalone（下称 pbs）。要回答的是：镜像里换成 pbs 比现在的 slim 省多少，值不值得改锁定的技术栈。

## 1. 结论

**slim 已经拿到了大部分收益：pbs 比 slim 只再少 2–5% 的 CPU；alpine 比 slim 多 19–28%。** 两个 Python 探针互相调用，200 次/秒，每千次请求两个探针合计的 CPU 秒（每个变体两遍的平均，括号里是两遍各自偏离平均多少）：

| 操作 | slim（现在的生产） | alpine（探针镜像） | pbs |
| --- | --- | --- | --- |
| gRPC 回显 1 KiB | 1.954（±0.1%） | 2.326（±3.0%），+19% | 1.908（±0.9%），−2.4% |
| HTTP 回显 1 KiB | 1.503（±0.2%） | 1.813（±3.3%），+21% | 1.426（±1.6%），−5.1% |
| 写入（发件表） | 3.473（±0.6%） | 4.436（±1.8%），+28% | 3.319（±0.3%），−4.4% |
| 写入并转发 | 6.014（±1.8%） | 7.233（±0.9%），+20% | 5.773（±0.9%），−4.0% |

- 延迟跟着 CPU 走：p50 pbs 比 slim 低 0.06–0.09 毫秒（约 2–4%），alpine 比 slim 高 0.25–0.45 毫秒（11–16%）。
- 空闲：两个探针合计 slim 0.032 核、pbs 0.032、alpine 0.039；不含页缓存的内存 slim 138.5 MiB、pbs 129.9、alpine 135.2。
- 镜像：slim 302 MB，pbs 397 MB（多 95 MB），alpine 198 MB。

**判断（给维护者定）**：pbs 的 2–5% 超出了这一批的波动，但很小；锁定的技术栈“新版本优点明显才换”，所以建议**生产继续用 slim**，不换。代价是镜像大 95 MB、构建多一步（`uv python install`，跟着 python-build-standalone 的发布走，不跟官方镜像）。Python 组件在本项目里只有打印与渲染外壳，都不在每个请求的路径上；Python 组件变多、变热时再复测。

**对已有结论的影响**：探针镜像用 alpine，所以 9-02 等记录里“容器里的 Python 探针”的 CPU 比生产的 slim 高约两成，Go 与 Python 的对比要按这个折算，或把探针换成 slim 后再比。本机进程与容器的差别（9-02 的约 20%）基本就是 alpine 与 pbs 的差别：这一批里 pbs 比 alpine 少 18–25%。

## 2. 测了什么

| 批 | 时间 | 内容 | 电源模式 |
| --- | --- | --- | --- |
| pybuild | 2026-10-29 02:50–03:41 | 格 D9-probe-pyonly（两个 Python 探针互相调用，D 行）；变体按 alpine、slim、pbs、pbs、slim、alpine 各跑两遍（对称排，批内的漂移看得出）；每遍起格、空闲 2 分钟，再两个方向各四种操作，200 次/秒、预热 10 秒、测 30 秒（`pybuild/run.sh` → `probe9.sh`）；每遍之前把两个探针的镜像标到这个变体，结束时标回原镜像 | performance，接电源，全程未变 |

每遍 8 项、每项 6 000 次请求，全部成功。GNOME 的文件索引（`localsearch-3`，nice 19）在第 1 遍（alpine）的 02:56 前一直占着一个核，之后停掉；第 1 遍比第 6 遍（同是 alpine）高 2–7%，可能有它的份，所以 alpine 的波动比其他两个变体大。即使只看第 6 遍，alpine 也比 slim 多 15–26%，结论不变。机器上没有别的工作（远程会话 00:37 已断开）。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| 机器 | 同 9-01（i5-12450H，14 GiB，Docker 29.9.2） |
| slim | `python:3.15.0-slim-trixie`：CPython 3.15.0，glibc，GCC 14.2.0，`--enable-optimizations`（PGO）与 `--with-lto` |
| alpine | `python:3.15.0-alpine`：CPython 3.15.0，musl，GCC 15.2.0，只有 `--with-lto`，没有 PGO |
| pbs | `debian:trixie-slim` 上用 uv 0.13.1 装 python-build-standalone 的 CPython 3.15.0：Clang 23.1.3，PGO、完整 LTO、BOLT、mimalloc、tail-call 解释器（与本机 uv 装的同一构建） |
| 探针 | `test/probe-py` 3.2.19 的同一份源码，三个变体各一个镜像（`pybuild/build.sh`；不写 `PORT`，BrickKit 1.10.1 注入） |
| 工具 | `be-acceptance` v1.0.8 的快照；汇总 `experiment-scripts/pybuild/summary.py` |

## 4. 影响

- kb：新的实测记录（容器里 CPython 的构建：官方 alpine、官方 slim、python-build-standalone），连同原始数据与脚本。
- 技术栈：建议不改（见第 1 节），作为提议写进交接，等维护者定。
- 探针：Python 探针镜像是否改用 slim，让探针的数字贴近生产，作为提议一起给维护者。

## 5. 原始数据

`experiment-data/10-04/pybuild/`：`night.log`；每遍 `<n>-<变体>/status.log`、`run1/D9-probe-pyonly/idle.json` 与两个方向各操作的 `result.json`（`resources.containers.<容器>.cgroup.cpu_seconds_per_1000`、`driver.latency_ms`）；`summary.md` 由 `pybuild/summary.py` 生成。镜像的构建：`experiment-scripts/pybuild/`（三个 Dockerfile、`build.sh`、`run.sh`）。
