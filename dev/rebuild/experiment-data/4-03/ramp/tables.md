| 格 | 进程 | 常驻内存 MiB | cgroup 内存 MiB | 空闲 CPU 核 |
| --- | --- | --- | --- | --- |

| 格 | 组件 MiB / 核 | 基础资源 MiB / 核 | 平台 MiB / 核 | 数据库连接（峰值） |
| --- | --- | --- | --- | --- |
| D-S | 264 / 0.062 | 4725 / 0.161 | 522 / 0.091 | 15 |
| D-S-pg | 258 / 0.095 | 2013 / 0.122 | 553 / 0.078 | 21 |

| 格 | 路径 | 操作 | 负载 | p50 ms | p99 ms | 吞吐 /s | 持续速率 /s | 每千次 CPU 秒（调用方 / 被调方） | 错误率 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D-S | probe-go → probe-go2 | write | ramp | — | — | — | 4325 | 0.72 / 0.28 | — |
| D-S | probe-go2 → probe-py | write | ramp | — | — | — | 4325 | 0.74 / 0.46 | — |
| D-S | probe-py → probe-py2 | write | ramp | — | — | — | 570 | 2.12 / 1.22 | — |
| D-S | probe-py2 → probe-go | write | ramp | — | — | — | 854 | 3.01 / 0.40 | — |
| D-S-pg | probe-go → probe-go2 | write | ramp | — | — | — | 4325 | 0.70 / 0.21 | — |
| D-S-pg | probe-go2 → probe-py | write | ramp | — | — | — | 4325 | 0.69 / 0.40 | — |
| D-S-pg | probe-py → probe-py2 | write | ramp | — | — | — | 570 | 2.10 / 1.03 | — |
| D-S-pg | probe-py2 → probe-go | write | ramp | — | — | — | 570 | 2.23 / 0.62 | — |
