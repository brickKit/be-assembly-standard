# T7.8、T7.9 的原始数据（2026-10-23）

两个格各跑一次全流程（`cell-full.sh`）：建格、准备、构建、启动、安全初始化，`make seed-data` 两轮（第一轮之后等后台做完，第二轮之后比较各表的行数与版本号总和），L3 场景（be-acceptance 的 `conformance/scenarios`），剖面（最后，会停掉格）。

| 格 | 形态 | 版本 | 结果 |
| --- | --- | --- | --- |
| D7-S | 14 个组件全部单跑 | 交易链 `erp/inventory`、`erp/credit` 3.0.1，`erp/sales`、`erp/billing` 3.0.2，`infra/print` 3.0.2 | 种子约 2 分钟；重跑不变；L3 6 项通过；两个探针剖面符合 |
| D7-H | 三个外壳：`be/go-infra` 3.0.26（安全、主数据、Go 探针）、`be/go-core` 3.0.23（四个交易组件）、`be/py-render` 3.0.21（打印、Python 探针） | 同上 | 同上；三个外壳与两个探针剖面符合 |

**最终版本再跑一遍**（R2b 的修复之后，`final/`）：D7-S 用 `erp/inventory`、`erp/credit` 3.0.2，`erp/sales`、`erp/billing`、`infra/print` 3.0.3；D7-H 用 `be/go-core` 3.0.24、`be/py-render` 3.0.22（`be/go-infra` 3.0.26 不变）。两格各约 8 分钟：种子两轮、重跑不变、L3 6 项通过、剖面全部符合（D7-S 两个探针；D7-H 两个探针与三个外壳），种子的数字与上一轮相同。下面的文件表同样适用于 `final/D7-*/`。

| 文件 | 内容 |
| --- | --- |
| `D7-*/run.log` | 各阶段的开始与结束（D7-S 的第一次“重跑”失败是快照取早了，见计划的发现；之后从 `settle` 接着跑） |
| `D7-*/seed1.txt`、`seed2.txt` | 两轮种子的输出（身份组件建账号那一步在没有 `CASDOOR_URL` 时报错并被跳过，账号已在） |
| `D7-*/vsum1.txt`、`vsum2.txt`、`rerun.txt` | 两轮之间每张表的行数与 `sum(version)`，`rerun.txt` 是它们的差（空即相同） |
| `D7-*/scenarios.txt`、`profile.txt` | L3 与剖面的输出 |
| `D7-*/accounts.txt` | 每个测试账号在交易链各列表第一页看到的行数（`visibility.py`），出处写在文件开头 |
| `D7-H/profile-first-nc-missing.txt` | 第一次剖面：`be/py-render` 的镜像没有 `nc`，gRPC 端口的检查误报 |
| `D7-H/profile-on-restarted-cell.txt` | 停了再起的格上重跑剖面：日志里“就绪”两行、新进程没有请求指标，所以剖面只在新起的格上跑 |
| `cell-full.sh`、`full-watch.sh`、`vsum.sh`、`visibility.py` | 运行与监视的脚本（写在会话的临时目录里，路径按那里写） |
