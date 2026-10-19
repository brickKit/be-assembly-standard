| 格 | 进程 | 常驻内存 MiB | cgroup 内存 MiB | 空闲 CPU 核 |
| --- | --- | --- | --- | --- |

| 格 | 组件 MiB / 核 | 基础资源 MiB / 核 | 平台 MiB / 核 | 数据库连接（峰值） |
| --- | --- | --- | --- | --- |
| D-S | 272 / 0.065 | 4545 / 0.083 | 507 / 0.071 | 14 |
| D-S-pg | 265 / 0.089 | 4858 / 0.191 | 494 / 0.069 | 22 |
| D-S-pg-c4 | 266 / 0.174 | 4905 / 0.360 | 491 / 0.074 | 32 |

| 格 | 路径 | 操作 | 负载 | p50 ms | p99 ms | 吞吐 /s | 持续速率 /s | 每千次 CPU 秒（调用方 / 被调方） | 错误率 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D-S | probe-go → probe-go2 | big-event | 200 | 21.03 | 41.55 | 200 | — | 2.99 / 1.87 | 0.000 |
| D-S | probe-go → probe-go2 | big-event | 50 | 8.81 | 11.59 | 50 | — | 3.42 / 2.04 | 0.000 |
| D-S | probe-go → probe-go2 | relay | 200 | 7.10 | 10.12 | 200 | — | 1.60 / 1.89 | 0.000 |
| D-S | probe-go → probe-go2 | relay | 50 | 6.95 | 9.15 | 50 | — | 1.86 / 2.18 | 0.000 |
| D-S | probe-go → probe-go2 | write | 200 | 3.28 | 8.04 | 200 | — | 1.59 / 0.73 | 0.000 |
| D-S | probe-go → probe-go2 | write | 50 | 3.50 | 5.11 | 50 | — | 1.84 / 0.92 | 0.000 |
| D-S | probe-go2 → probe-py | big-event | 200 | 25.65 | 48.88 | 200 | — | 3.06 / 2.78 | 0.000 |
| D-S | probe-go2 → probe-py | big-event | 50 | 9.44 | 12.18 | 50 | — | 3.48 / 2.90 | 0.000 |
| D-S | probe-go2 → probe-py | relay | 200 | 9.14 | 17.19 | 200 | — | 1.68 / 3.60 | 0.000 |
| D-S | probe-go2 → probe-py | relay | 50 | 8.53 | 12.05 | 50 | — | 1.92 / 4.98 | 0.000 |
| D-S | probe-go2 → probe-py | write | 200 | 3.50 | 7.21 | 200 | — | 1.53 / 1.59 | 0.000 |
| D-S | probe-go2 → probe-py | write | 50 | 3.80 | 5.56 | 50 | — | 1.90 / 1.84 | 0.000 |
| D-S | probe-py → probe-py2 | big-event | 200 | 53.62 | 93.49 | 200 | — | 4.18 / 2.71 | 0.000 |
| D-S | probe-py → probe-py2 | big-event | 50 | 11.29 | 15.34 | 50 | — | 5.92 / 2.92 | 0.000 |
| D-S | probe-py → probe-py2 | relay | 200 | 14.92 | 32.99 | 200 | — | 3.79 / 3.79 | 0.000 |
| D-S | probe-py → probe-py2 | relay | 50 | 9.49 | 14.93 | 50 | — | 4.34 / 4.84 | 0.000 |
| D-S | probe-py → probe-py2 | write | 200 | 6.35 | 22.41 | 200 | — | 3.55 / 1.69 | 0.000 |
| D-S | probe-py → probe-py2 | write | 50 | 5.19 | 8.06 | 50 | — | 4.10 / 1.96 | 0.000 |
| D-S | probe-py2 → probe-go | big-event | 200 | 48.34 | 643.14 | 200 | — | 3.99 / 1.59 | 0.000 |
| D-S | probe-py2 → probe-go | big-event | 50 | 10.74 | 15.06 | 50 | — | 6.06 / 1.96 | 0.000 |
| D-S | probe-py2 → probe-go | relay | 200 | 11.62 | 28.88 | 200 | — | 3.75 / 1.97 | 0.000 |
| D-S | probe-py2 → probe-go | relay | 50 | 7.86 | 13.30 | 50 | — | 4.34 / 2.24 | 0.000 |
| D-S | probe-py2 → probe-go | write | 200 | 4.53 | 19.00 | 200 | — | 3.36 / 0.73 | 0.000 |
| D-S | probe-py2 → probe-go | write | 50 | 5.06 | 7.79 | 50 | — | 4.30 / 1.02 | 0.000 |
| D-S-pg | probe-go → probe-go2 | big-event | 200 | 31.82 | 62.22 | 200 | — | 2.98 / 2.13 | 0.000 |
| D-S-pg | probe-go → probe-go2 | big-event | 50 | 11.53 | 15.72 | 50 | — | 3.88 / 2.80 | 0.000 |
| D-S-pg | probe-go → probe-go2 | relay | 200 | 10.08 | 21.94 | 200 | — | 1.80 / 2.51 | 0.000 |
| D-S-pg | probe-go → probe-go2 | relay | 50 | 9.09 | 15.15 | 50 | — | 2.04 / 2.66 | 0.000 |
| D-S-pg | probe-go → probe-go2 | write | 200 | 5.09 | 10.66 | 200 | — | 1.61 / 1.18 | 0.000 |
| D-S-pg | probe-go → probe-go2 | write | 50 | 5.81 | 24.97 | 50 | — | 2.02 / 1.42 | 0.000 |
| D-S-pg | probe-go2 → probe-py | big-event | 200 | 2646.47 | 3576.46 | 200 | — | 3.06 / 2.40 | 0.000 |
| D-S-pg | probe-go2 → probe-py | big-event | 50 | 14.52 | 20.93 | 50 | — | 3.84 / 5.30 | 0.000 |
| D-S-pg | probe-go2 → probe-py | relay | 200 | 445.33 | 713.47 | 200 | — | 1.77 / 3.77 | 0.000 |
| D-S-pg | probe-go2 → probe-py | relay | 50 | 12.72 | 18.72 | 50 | — | 2.10 / 6.62 | 0.000 |
| D-S-pg | probe-go2 → probe-py | write | 200 | 20.83 | 43.90 | 200 | — | 1.68 / 2.06 | 0.000 |
| D-S-pg | probe-go2 → probe-py | write | 50 | 8.31 | 13.09 | 50 | — | 2.06 / 3.86 | 0.000 |
| D-S-pg | probe-py → probe-py2 | big-event | 200 | 2574.29 | 3465.15 | 200 | — | 4.24 / 2.42 | 0.000 |
| D-S-pg | probe-py → probe-py2 | big-event | 50 | 17.55 | 24.88 | 50 | — | 7.10 / 5.42 | 0.000 |
| D-S-pg | probe-py → probe-py2 | relay | 200 | 1021.74 | 1382.22 | 200 | — | 3.81 / 4.00 | 0.000 |
| D-S-pg | probe-py → probe-py2 | relay | 50 | 14.44 | 21.16 | 50 | — | 4.96 / 6.40 | 0.000 |
| D-S-pg | probe-py → probe-py2 | write | 200 | 42.30 | 75.03 | 200 | — | 3.64 / 2.11 | 0.000 |
| D-S-pg | probe-py → probe-py2 | write | 50 | 10.05 | 15.29 | 50 | — | 4.50 / 3.82 | 0.000 |
| D-S-pg | probe-py2 → probe-go | big-event | 200 | 77.40 | 180.32 | 200 | — | 4.18 / 1.93 | 0.000 |
| D-S-pg | probe-py2 → probe-go | big-event | 50 | 13.54 | 18.65 | 50 | — | 6.80 / 2.50 | 0.000 |
| D-S-pg | probe-py2 → probe-go | relay | 200 | 23.39 | 51.15 | 200 | — | 3.84 / 2.32 | 0.000 |
| D-S-pg | probe-py2 → probe-go | relay | 50 | 10.94 | 16.90 | 50 | — | 5.00 / 2.80 | 0.000 |
| D-S-pg | probe-py2 → probe-go | write | 200 | 17.42 | 45.86 | 200 | — | 3.51 / 1.13 | 0.000 |
| D-S-pg | probe-py2 → probe-go | write | 50 | 7.73 | 15.24 | 50 | — | 4.94 / 1.46 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | big-event | 200 | 30.61 | 59.57 | 200 | — | 3.10 / 2.46 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | big-event | 50 | 11.06 | 31.27 | 50 | — | 3.92 / 2.60 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | relay | 200 | 10.40 | 17.40 | 200 | — | 1.83 / 2.55 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | relay | 50 | 9.20 | 29.75 | 50 | — | 2.20 / 2.66 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | write | 200 | 6.19 | 12.06 | 200 | — | 1.73 / 1.20 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | write | 50 | 5.69 | 25.77 | 50 | — | 2.26 / 1.34 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | big-event | 200 | 39.57 | 78.71 | 200 | — | 3.23 / 4.38 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | big-event | 50 | 14.43 | 19.62 | 50 | — | 3.94 / 5.26 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | relay | 200 | 19.88 | 35.99 | 200 | — | 1.98 / 4.88 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | relay | 50 | 12.86 | 18.82 | 50 | — | 2.28 / 6.76 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | write | 200 | 10.28 | 16.98 | 200 | — | 1.82 / 4.23 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | write | 50 | 8.26 | 12.72 | 50 | — | 2.24 / 3.82 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | big-event | 200 | 98.97 | 185.96 | 200 | — | 4.52 / 4.24 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | big-event | 50 | 16.92 | 23.13 | 50 | — | 7.46 / 5.34 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | relay | 200 | 34.96 | 67.54 | 200 | — | 4.02 / 4.73 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | relay | 50 | 13.86 | 21.64 | 50 | — | 5.68 / 6.56 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | write | 200 | 27.47 | 60.96 | 200 | — | 3.92 / 3.69 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | write | 50 | 9.95 | 15.88 | 50 | — | 5.32 / 3.74 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | big-event | 200 | 75.99 | 186.61 | 200 | — | 4.31 / 2.32 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | big-event | 50 | 13.59 | 35.41 | 50 | — | 7.28 / 2.52 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | relay | 200 | 24.78 | 58.39 | 200 | — | 3.98 / 2.53 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | relay | 50 | 10.44 | 31.40 | 50 | — | 5.62 / 2.68 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | write | 200 | 17.14 | 51.53 | 200 | — | 3.88 / 1.27 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | write | 50 | 7.49 | 28.24 | 50 | — | 5.42 / 1.42 | 0.000 |
