# 实验第 4 步的一次性脚本

全面复测（4-03）与性能跟进（T4.6c）用的脚本，从会话的草稿目录复制过来留底。脚本里的路径指向当时的草稿目录（`/tmp/claude-1000/…/scratchpad`），其中 `accenv.sh`、`itenv.sh` 只把 `.env` 里的密钥读进环境变量、不打印；换一次会话要先改这些路径。

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
