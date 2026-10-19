| 格 | 进程 | 常驻内存 MiB | cgroup 内存 MiB | 空闲 CPU 核 |
| --- | --- | --- | --- | --- |

| 格 | 组件 MiB / 核 | 基础资源 MiB / 核 | 平台 MiB / 核 | 数据库连接（峰值） |
| --- | --- | --- | --- | --- |
| D-S-pg | 265 / 0.102 | 3199 / 0.128 | 498 / 0.075 | 22 |
| D-S-pg-c4 | 264 / 0.162 | 4778 / 0.339 | 482 / 0.071 | 33 |

| 格 | 路径 | 操作 | 负载 | p50 ms | p99 ms | 吞吐 /s | 持续速率 /s | 每千次 CPU 秒（调用方 / 被调方） | 错误率 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D-S-pg | probe-go → probe-go2 | big-event | 200 | 33.94 | 66.04 | 200 | — | 3.04 / 2.15 | 0.000 |
| D-S-pg | probe-go → probe-go2 | big-event | 50 | 11.46 | 31.05 | 50 | — | 3.86 / 2.76 | 0.000 |
| D-S-pg | probe-go → probe-go2 | relay | 200 | 9.87 | 16.01 | 200 | — | 1.75 / 2.48 | 0.000 |
| D-S-pg | probe-go → probe-go2 | relay | 50 | 9.14 | 27.60 | 50 | — | 2.10 / 2.70 | 0.000 |
| D-S-pg | probe-go → probe-go2 | write | 200 | 6.07 | 15.26 | 200 | — | 1.80 / 1.24 | 0.000 |
| D-S-pg | probe-go → probe-go2 | write | 50 | 5.94 | 10.91 | 50 | — | 2.10 / 1.46 | 0.000 |
| D-S-pg | probe-go2 → probe-py | big-event | 200 | 2523.15 | 3295.15 | 200 | — | 3.04 / 2.42 | 0.000 |
| D-S-pg | probe-go2 → probe-py | big-event | 50 | 13.94 | 19.19 | 50 | — | 3.78 / 4.98 | 0.000 |
| D-S-pg | probe-go2 → probe-py | relay | 200 | 538.58 | 623.94 | 200 | — | 1.77 / 3.81 | 0.000 |
| D-S-pg | probe-go2 → probe-py | relay | 50 | 12.59 | 18.19 | 50 | — | 2.06 / 6.54 | 0.000 |
| D-S-pg | probe-go2 → probe-py | write | 200 | 25.49 | 111.68 | 200 | — | 1.73 / 2.11 | 0.000 |
| D-S-pg | probe-go2 → probe-py | write | 50 | 8.49 | 12.64 | 50 | — | 2.14 / 3.92 | 0.000 |
| D-S-pg | probe-py → probe-py2 | big-event | 200 | 2511.35 | 3268.68 | 200 | — | 4.14 / 2.44 | 0.000 |
| D-S-pg | probe-py → probe-py2 | big-event | 50 | 17.70 | 24.55 | 50 | — | 7.20 / 5.52 | 0.000 |
| D-S-pg | probe-py → probe-py2 | relay | 200 | 444.35 | 643.18 | 200 | — | 3.80 / 4.00 | 0.000 |
| D-S-pg | probe-py → probe-py2 | relay | 50 | 13.62 | 19.96 | 50 | — | 4.78 / 6.52 | 0.000 |
| D-S-pg | probe-py → probe-py2 | write | 200 | 35.40 | 62.16 | 200 | — | 3.67 / 2.12 | 0.000 |
| D-S-pg | probe-py → probe-py2 | write | 50 | 10.27 | 15.34 | 50 | — | 4.80 / 3.94 | 0.000 |
| D-S-pg | probe-py2 → probe-go | big-event | 200 | 80.98 | 178.62 | 200 | — | 4.24 / 1.94 | 0.000 |
| D-S-pg | probe-py2 → probe-go | big-event | 50 | 15.88 | 35.94 | 50 | — | 8.56 / 2.86 | 0.000 |
| D-S-pg | probe-py2 → probe-go | relay | 200 | 22.74 | 52.47 | 200 | — | 3.84 / 2.37 | 0.000 |
| D-S-pg | probe-py2 → probe-go | relay | 50 | 10.17 | 18.72 | 50 | — | 4.92 / 2.76 | 0.000 |
| D-S-pg | probe-py2 → probe-go | write | 200 | 15.56 | 38.68 | 200 | — | 3.68 / 1.19 | 0.000 |
| D-S-pg | probe-py2 → probe-go | write | 50 | 7.60 | 13.59 | 50 | — | 4.90 / 1.48 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | big-event | 200 | 29.90 | 66.27 | 200 | — | 3.08 / 2.48 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | big-event | 50 | 11.02 | 30.97 | 50 | — | 3.88 / 2.58 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | relay | 200 | 9.45 | 15.94 | 200 | — | 1.80 / 2.54 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | relay | 50 | 8.84 | 29.74 | 50 | — | 2.16 / 2.58 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | write | 200 | 5.23 | 10.74 | 200 | — | 1.67 / 1.17 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | write | 50 | 5.62 | 26.00 | 50 | — | 2.24 / 1.34 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | big-event | 200 | 40.43 | 74.82 | 200 | — | 3.18 / 4.36 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | big-event | 50 | 14.17 | 18.70 | 50 | — | 4.02 / 5.12 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | relay | 200 | 22.06 | 40.44 | 200 | — | 1.96 / 4.97 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | relay | 50 | 13.07 | 19.94 | 50 | — | 2.28 / 6.44 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | write | 200 | 9.49 | 16.53 | 200 | — | 1.84 / 3.90 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | write | 50 | 8.18 | 13.14 | 50 | — | 2.18 / 3.72 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | big-event | 200 | 105.18 | 241.39 | 200 | — | 4.51 / 4.13 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | big-event | 50 | 17.76 | 25.41 | 50 | — | 7.68 / 5.62 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | relay | 200 | 37.81 | 73.74 | 200 | — | 4.10 / 4.72 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | relay | 50 | 14.80 | 22.16 | 50 | — | 5.58 / 6.98 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | write | 200 | 28.68 | 67.65 | 200 | — | 3.95 / 3.68 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | write | 50 | 10.37 | 15.76 | 50 | — | 5.32 / 4.04 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | big-event | 200 | 924.29 | 2452.33 | 200 | — | 4.76 / 2.66 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | big-event | 50 | 175.34 | 333.52 | 50 | — | 6.22 / 2.62 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | relay | 200 | 25.43 | 57.27 | 200 | — | 4.02 / 2.58 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | relay | 50 | 10.06 | 30.40 | 50 | — | 5.78 / 2.72 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | write | 200 | 19.48 | 50.71 | 200 | — | 3.77 / 1.24 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | write | 50 | 7.32 | 27.51 | 50 | — | 5.36 / 1.42 | 0.000 |
