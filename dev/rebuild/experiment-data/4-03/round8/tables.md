| 格 | 进程 | 常驻内存 MiB | cgroup 内存 MiB | 空闲 CPU 核 |
| --- | --- | --- | --- | --- |

| 格 | 组件 MiB / 核 | 基础资源 MiB / 核 | 平台 MiB / 核 | 数据库连接（峰值） |
| --- | --- | --- | --- | --- |
| D-S | 270 / 0.069 | 1916 / 0.086 | 535 / 0.065 | 15 |
| D-S-pg | 261 / 0.099 | 4692 / 0.707 | 514 / 0.071 | 22 |
| D-S-pg-c4 | 262 / 0.167 | 4713 / 0.336 | 515 / 0.068 | 34 |

| 格 | 路径 | 操作 | 负载 | p50 ms | p99 ms | 吞吐 /s | 持续速率 /s | 每千次 CPU 秒（调用方 / 被调方） | 错误率 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D-S | probe-go → probe-go2 | big-event | 200 | 21.03 | 44.46 | 200 | — | 2.98 / 1.88 | 0.000 |
| D-S | probe-go → probe-go2 | big-event | 50 | 8.64 | 11.40 | 50 | — | 3.40 / 2.06 | 0.000 |
| D-S | probe-go → probe-go2 | relay | 200 | 6.62 | 9.41 | 200 | — | 1.58 / 1.85 | 0.000 |
| D-S | probe-go → probe-go2 | relay | 50 | 7.08 | 9.19 | 50 | — | 1.82 / 2.20 | 0.000 |
| D-S | probe-go → probe-go2 | write | 200 | 2.73 | 5.24 | 200 | — | 1.46 / 0.68 | 0.000 |
| D-S | probe-go → probe-go2 | write | 50 | 3.61 | 5.48 | 50 | — | 2.02 / 0.96 | 0.000 |
| D-S | probe-go2 → probe-py | big-event | 200 | 25.01 | 50.97 | 200 | — | 3.07 / 2.73 | 0.000 |
| D-S | probe-go2 → probe-py | big-event | 50 | 9.40 | 11.61 | 50 | — | 3.54 / 2.86 | 0.000 |
| D-S | probe-go2 → probe-py | relay | 200 | 9.16 | 16.50 | 200 | — | 1.71 / 3.64 | 0.000 |
| D-S | probe-go2 → probe-py | relay | 50 | 8.39 | 11.24 | 50 | — | 1.88 / 4.58 | 0.000 |
| D-S | probe-go2 → probe-py | write | 200 | 3.22 | 5.20 | 200 | — | 1.54 / 1.62 | 0.000 |
| D-S | probe-go2 → probe-py | write | 50 | 3.86 | 5.69 | 50 | — | 1.86 / 1.86 | 0.000 |
| D-S | probe-py → probe-py2 | big-event | 200 | 50.38 | 105.12 | 200 | — | 4.05 / 2.71 | 0.000 |
| D-S | probe-py → probe-py2 | big-event | 50 | 11.49 | 15.66 | 50 | — | 5.96 / 3.00 | 0.000 |
| D-S | probe-py → probe-py2 | relay | 200 | 12.71 | 33.46 | 200 | — | 3.73 / 3.69 | 0.000 |
| D-S | probe-py → probe-py2 | relay | 50 | 9.33 | 12.78 | 50 | — | 4.02 / 4.48 | 0.000 |
| D-S | probe-py → probe-py2 | write | 200 | 7.20 | 24.59 | 200 | — | 3.48 / 1.70 | 0.000 |
| D-S | probe-py → probe-py2 | write | 50 | 5.23 | 9.08 | 50 | — | 4.08 / 1.96 | 0.000 |
| D-S | probe-py2 → probe-go | big-event | 200 | 43.47 | 85.33 | 200 | — | 4.03 / 1.67 | 0.000 |
| D-S | probe-py2 → probe-go | big-event | 50 | 10.45 | 16.00 | 50 | — | 6.00 / 1.94 | 0.000 |
| D-S | probe-py2 → probe-go | relay | 200 | 10.32 | 27.09 | 200 | — | 3.68 / 1.95 | 0.000 |
| D-S | probe-py2 → probe-go | relay | 50 | 7.60 | 11.68 | 50 | — | 4.06 / 2.20 | 0.000 |
| D-S | probe-py2 → probe-go | write | 200 | 6.04 | 20.91 | 200 | — | 3.37 / 0.72 | 0.000 |
| D-S | probe-py2 → probe-go | write | 50 | 4.96 | 8.64 | 50 | — | 4.16 / 0.98 | 0.000 |
| D-S-pg | probe-go → probe-go2 | big-event | 200 | 32.28 | 64.06 | 200 | — | 2.96 / 2.12 | 0.000 |
| D-S-pg | probe-go → probe-go2 | big-event | 50 | 11.43 | 14.96 | 50 | — | 3.64 / 2.64 | 0.000 |
| D-S-pg | probe-go → probe-go2 | relay | 200 | 9.82 | 16.73 | 200 | — | 1.71 / 2.42 | 0.000 |
| D-S-pg | probe-go → probe-go2 | relay | 50 | 8.97 | 29.53 | 50 | — | 1.96 / 2.58 | 0.000 |
| D-S-pg | probe-go → probe-go2 | write | 200 | 5.94 | 11.82 | 200 | — | 1.59 / 1.10 | 0.000 |
| D-S-pg | probe-go → probe-go2 | write | 50 | 5.63 | 24.29 | 50 | — | 1.98 / 1.36 | 0.000 |
| D-S-pg | probe-go2 → probe-py | big-event | 200 | 2650.90 | 3474.09 | 200 | — | 3.01 / 2.39 | 0.000 |
| D-S-pg | probe-go2 → probe-py | big-event | 50 | 14.59 | 18.81 | 50 | — | 3.78 / 5.10 | 0.000 |
| D-S-pg | probe-go2 → probe-py | relay | 200 | 686.11 | 928.88 | 200 | — | 1.73 / 3.62 | 0.000 |
| D-S-pg | probe-go2 → probe-py | relay | 50 | 12.21 | 17.23 | 50 | — | 2.06 / 6.04 | 0.000 |
| D-S-pg | probe-go2 → probe-py | write | 200 | 31.64 | 54.59 | 200 | — | 1.69 / 1.94 | 0.000 |
| D-S-pg | probe-go2 → probe-py | write | 50 | 8.80 | 12.75 | 50 | — | 2.06 / 4.04 | 0.000 |
| D-S-pg | probe-py → probe-py2 | big-event | 200 | 2492.15 | 3405.80 | 200 | — | 4.15 / 2.39 | 0.000 |
| D-S-pg | probe-py → probe-py2 | big-event | 50 | 17.20 | 22.83 | 50 | — | 6.94 / 5.30 | 0.000 |
| D-S-pg | probe-py → probe-py2 | relay | 200 | 188.56 | 269.00 | 200 | — | 3.73 / 3.90 | 0.000 |
| D-S-pg | probe-py → probe-py2 | relay | 50 | 13.62 | 20.14 | 50 | — | 4.74 / 6.38 | 0.000 |
| D-S-pg | probe-py → probe-py2 | write | 200 | 32.96 | 66.02 | 200 | — | 3.56 / 2.08 | 0.000 |
| D-S-pg | probe-py → probe-py2 | write | 50 | 10.84 | 17.08 | 50 | — | 5.02 / 4.16 | 0.000 |
| D-S-pg | probe-py2 → probe-go | big-event | 200 | 73.70 | 134.58 | 200 | — | 4.21 / 1.96 | 0.000 |
| D-S-pg | probe-py2 → probe-go | big-event | 50 | 13.57 | 32.05 | 50 | — | 6.76 / 2.52 | 0.000 |
| D-S-pg | probe-py2 → probe-go | relay | 200 | 23.94 | 52.82 | 200 | — | 3.78 / 2.37 | 0.000 |
| D-S-pg | probe-py2 → probe-go | relay | 50 | 10.07 | 15.46 | 50 | — | 4.86 / 2.68 | 0.000 |
| D-S-pg | probe-py2 → probe-go | write | 200 | 13.52 | 37.53 | 200 | — | 3.57 / 1.16 | 0.000 |
| D-S-pg | probe-py2 → probe-go | write | 50 | 7.60 | 16.34 | 50 | — | 4.84 / 1.54 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | big-event | 200 | 30.20 | 63.01 | 200 | — | 3.05 / 2.47 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | big-event | 50 | 11.16 | 32.09 | 50 | — | 3.94 / 2.70 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | relay | 200 | 10.51 | 17.41 | 200 | — | 1.82 / 2.54 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | relay | 50 | 9.05 | 28.94 | 50 | — | 2.22 / 2.64 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | write | 200 | 5.25 | 11.18 | 200 | — | 1.65 / 1.18 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | write | 50 | 5.73 | 26.13 | 50 | — | 2.22 / 1.36 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | big-event | 200 | 40.40 | 76.35 | 200 | — | 3.19 / 4.32 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | big-event | 50 | 14.32 | 20.04 | 50 | — | 4.02 / 5.12 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | relay | 200 | 25.99 | 352.46 | 200 | — | 1.88 / 4.64 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | relay | 50 | 32.45 | 45.61 | 50 | — | 2.40 / 7.06 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | write | 200 | 9.68 | 104.54 | 200 | — | 1.81 / 4.05 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | write | 50 | 8.25 | 12.41 | 50 | — | 2.26 / 3.74 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | big-event | 200 | 105.16 | 237.90 | 200 | — | 4.46 / 4.21 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | big-event | 50 | 17.51 | 24.70 | 50 | — | 7.36 / 5.68 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | relay | 200 | 34.91 | 72.26 | 200 | — | 3.98 / 4.68 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | relay | 50 | 13.50 | 20.30 | 50 | — | 5.32 / 6.26 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | write | 200 | 23.99 | 55.37 | 200 | — | 3.97 / 3.69 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | write | 50 | 10.12 | 16.05 | 50 | — | 5.08 / 3.88 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | big-event | 200 | 80.15 | 158.35 | 200 | — | 4.38 / 2.33 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | big-event | 50 | 14.42 | 34.89 | 50 | — | 7.48 / 2.48 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | relay | 200 | 27.80 | 56.83 | 200 | — | 4.05 / 2.55 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | relay | 50 | 11.34 | 30.86 | 50 | — | 5.54 / 2.74 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | write | 200 | 21.68 | 51.99 | 200 | — | 3.82 / 1.24 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | write | 50 | 7.86 | 28.67 | 50 | — | 5.00 / 1.42 | 0.000 |
