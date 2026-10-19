| 格 | 进程 | 常驻内存 MiB | cgroup 内存 MiB | 空闲 CPU 核 |
| --- | --- | --- | --- | --- |

| 格 | 组件 MiB / 核 | 基础资源 MiB / 核 | 平台 MiB / 核 | 数据库连接（峰值） |
| --- | --- | --- | --- | --- |
| D-S-pg | 268 / 0.096 | 1330 / 0.123 | 569 / 0.086 | 22 |
| D-S-pg-c4 | 262 / 0.159 | 3916 / 0.339 | 558 / 0.083 | 33 |

| 格 | 路径 | 操作 | 负载 | p50 ms | p99 ms | 吞吐 /s | 持续速率 /s | 每千次 CPU 秒（调用方 / 被调方） | 错误率 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D-S-pg | probe-go → probe-go2 | big-event | 200 | 37.46 | 75.90 | 200 | — | 3.11 / 2.21 | 0.000 |
| D-S-pg | probe-go → probe-go2 | big-event | 50 | 11.34 | 19.27 | 50 | — | 3.78 / 2.72 | 0.000 |
| D-S-pg | probe-go → probe-go2 | relay | 200 | 10.11 | 20.23 | 200 | — | 1.81 / 2.46 | 0.000 |
| D-S-pg | probe-go → probe-go2 | relay | 50 | 9.46 | 16.31 | 50 | — | 2.14 / 2.78 | 0.000 |
| D-S-pg | probe-go → probe-go2 | write | 200 | 5.65 | 11.77 | 200 | — | 1.82 / 1.30 | 0.000 |
| D-S-pg | probe-go → probe-go2 | write | 50 | 5.96 | 14.19 | 50 | — | 2.14 / 1.42 | 0.000 |
| D-S-pg | probe-go2 → probe-py | big-event | 200 | 2551.01 | 3432.10 | 200 | — | 3.09 / 2.45 | 0.000 |
| D-S-pg | probe-go2 → probe-py | big-event | 50 | 14.66 | 19.91 | 50 | — | 3.96 / 5.36 | 0.000 |
| D-S-pg | probe-go2 → probe-py | relay | 200 | 1660.65 | 2325.32 | 200 | — | 1.90 / 3.64 | 0.000 |
| D-S-pg | probe-go2 → probe-py | relay | 50 | 13.10 | 18.64 | 50 | — | 2.14 / 6.44 | 0.000 |
| D-S-pg | probe-go2 → probe-py | write | 200 | 34.02 | 66.01 | 200 | — | 1.73 / 2.08 | 0.000 |
| D-S-pg | probe-go2 → probe-py | write | 50 | 8.39 | 12.43 | 50 | — | 2.14 / 3.74 | 0.000 |
| D-S-pg | probe-py → probe-py2 | big-event | 200 | 3465.92 | 4695.00 | 200 | — | 4.29 / 2.23 | 0.000 |
| D-S-pg | probe-py → probe-py2 | big-event | 50 | 18.05 | 24.96 | 50 | — | 7.32 / 5.32 | 0.000 |
| D-S-pg | probe-py → probe-py2 | relay | 200 | 674.20 | 989.00 | 200 | — | 3.81 / 3.93 | 0.000 |
| D-S-pg | probe-py → probe-py2 | relay | 50 | 14.13 | 19.76 | 50 | — | 5.28 / 6.44 | 0.000 |
| D-S-pg | probe-py → probe-py2 | write | 200 | 39.32 | 74.33 | 200 | — | 3.77 / 2.11 | 0.000 |
| D-S-pg | probe-py → probe-py2 | write | 50 | 10.81 | 16.68 | 50 | — | 5.06 / 4.04 | 0.000 |
| D-S-pg | probe-py2 → probe-go | big-event | 200 | 105.99 | 244.49 | 200 | — | 4.30 / 1.90 | 0.000 |
| D-S-pg | probe-py2 → probe-go | big-event | 50 | 13.88 | 19.06 | 50 | — | 6.92 / 2.54 | 0.000 |
| D-S-pg | probe-py2 → probe-go | relay | 200 | 25.77 | 64.92 | 200 | — | 3.88 / 2.35 | 0.000 |
| D-S-pg | probe-py2 → probe-go | relay | 50 | 11.05 | 15.46 | 50 | — | 5.12 / 2.80 | 0.000 |
| D-S-pg | probe-py2 → probe-go | write | 200 | 21.42 | 53.64 | 200 | — | 3.80 / 1.11 | 0.000 |
| D-S-pg | probe-py2 → probe-go | write | 50 | 8.17 | 11.16 | 50 | — | 5.36 / 1.48 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | big-event | 200 | 31.18 | 66.92 | 200 | — | 3.14 / 2.51 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | big-event | 50 | 11.35 | 32.49 | 50 | — | 3.96 / 2.64 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | relay | 200 | 9.68 | 16.12 | 200 | — | 1.88 / 2.51 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | relay | 50 | 10.40 | 30.59 | 50 | — | 2.30 / 2.66 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | write | 200 | 6.22 | 12.13 | 200 | — | 1.76 / 1.23 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | write | 50 | 5.67 | 24.63 | 50 | — | 2.26 / 1.34 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | big-event | 200 | 40.59 | 77.89 | 200 | — | 3.22 / 4.34 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | big-event | 50 | 14.29 | 20.99 | 50 | — | 4.04 / 5.12 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | relay | 200 | 20.15 | 34.55 | 200 | — | 2.03 / 4.87 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | relay | 50 | 13.14 | 20.18 | 50 | — | 2.32 / 6.90 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | write | 200 | 10.03 | 17.25 | 200 | — | 1.88 / 4.09 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | write | 50 | 8.59 | 12.52 | 50 | — | 2.30 / 4.14 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | big-event | 200 | 383.14 | 1118.83 | 200 | — | 4.70 / 3.90 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | big-event | 50 | 17.34 | 24.13 | 50 | — | 7.72 / 5.46 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | relay | 200 | 44.48 | 101.38 | 200 | — | 4.16 / 4.67 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | relay | 50 | 13.92 | 21.82 | 50 | — | 5.60 / 6.54 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | write | 200 | 31.63 | 70.21 | 200 | — | 3.88 / 3.90 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | write | 50 | 10.58 | 16.36 | 50 | — | 5.44 / 4.02 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | big-event | 200 | 1602.49 | 5952.03 | 200 | — | 4.07 / 1.70 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | big-event | 50 | 14.96 | 21.95 | 50 | — | 7.76 / 2.60 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | relay | 200 | 33.72 | 85.92 | 200 | — | 4.09 / 2.60 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | relay | 50 | 11.44 | 29.64 | 50 | — | 5.88 / 2.80 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | write | 200 | 23.66 | 69.58 | 200 | — | 3.78 / 1.27 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | write | 50 | 8.69 | 28.31 | 50 | — | 5.92 / 1.44 | 0.000 |
