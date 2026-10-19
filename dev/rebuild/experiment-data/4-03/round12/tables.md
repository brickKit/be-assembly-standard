| 格 | 进程 | 常驻内存 MiB | cgroup 内存 MiB | 空闲 CPU 核 |
| --- | --- | --- | --- | --- |

| 格 | 组件 MiB / 核 | 基础资源 MiB / 核 | 平台 MiB / 核 | 数据库连接（峰值） |
| --- | --- | --- | --- | --- |
| D-S-pg | 266 / 0.093 | 3215 / 0.123 | 532 / 0.083 | 21 |
| D-S-pg-c4 | 262 / 0.169 | 4818 / 0.343 | 540 / 0.082 | 33 |

| 格 | 路径 | 操作 | 负载 | p50 ms | p99 ms | 吞吐 /s | 持续速率 /s | 每千次 CPU 秒（调用方 / 被调方） | 错误率 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D-S-pg | probe-go → probe-go2 | big-event | 200 | 54.46 | 102.61 | 200 | — | 3.03 / 1.94 | 0.000 |
| D-S-pg | probe-go → probe-go2 | big-event | 50 | 11.71 | 15.13 | 50 | — | 3.80 / 2.64 | 0.000 |
| D-S-pg | probe-go → probe-go2 | relay | 200 | 9.27 | 14.86 | 200 | — | 1.77 / 2.45 | 0.000 |
| D-S-pg | probe-go → probe-go2 | relay | 50 | 10.34 | 15.30 | 50 | — | 2.04 / 2.68 | 0.000 |
| D-S-pg | probe-go → probe-go2 | write | 200 | 6.37 | 13.66 | 200 | — | 1.80 / 1.17 | 0.000 |
| D-S-pg | probe-go → probe-go2 | write | 50 | 6.79 | 22.53 | 50 | — | 2.16 / 1.48 | 0.000 |
| D-S-pg | probe-go2 → probe-py | big-event | 200 | 2619.05 | 3377.86 | 200 | — | 3.09 / 2.43 | 0.000 |
| D-S-pg | probe-go2 → probe-py | big-event | 50 | 14.29 | 19.37 | 50 | — | 3.80 / 5.06 | 0.000 |
| D-S-pg | probe-go2 → probe-py | relay | 200 | 618.56 | 719.07 | 200 | — | 1.85 / 3.80 | 0.000 |
| D-S-pg | probe-go2 → probe-py | relay | 50 | 13.13 | 26.10 | 50 | — | 2.20 / 6.84 | 0.000 |
| D-S-pg | probe-go2 → probe-py | write | 200 | 21.71 | 46.07 | 200 | — | 1.75 / 2.07 | 0.000 |
| D-S-pg | probe-go2 → probe-py | write | 50 | 8.31 | 12.56 | 50 | — | 2.14 / 3.64 | 0.000 |
| D-S-pg | probe-py → probe-py2 | big-event | 200 | 2715.74 | 3493.36 | 200 | — | 4.33 / 2.43 | 0.000 |
| D-S-pg | probe-py → probe-py2 | big-event | 50 | 17.33 | 23.10 | 50 | — | 7.02 / 5.22 | 0.000 |
| D-S-pg | probe-py → probe-py2 | relay | 200 | 619.92 | 901.28 | 200 | — | 3.94 / 4.00 | 0.000 |
| D-S-pg | probe-py → probe-py2 | relay | 50 | 13.84 | 20.81 | 50 | — | 4.90 / 6.42 | 0.000 |
| D-S-pg | probe-py → probe-py2 | write | 200 | 39.28 | 67.53 | 200 | — | 3.77 / 2.12 | 0.000 |
| D-S-pg | probe-py → probe-py2 | write | 50 | 10.52 | 17.00 | 50 | — | 4.90 / 3.92 | 0.000 |
| D-S-pg | probe-py2 → probe-go | big-event | 200 | 69.36 | 139.86 | 200 | — | 4.33 / 1.94 | 0.000 |
| D-S-pg | probe-py2 → probe-go | big-event | 50 | 14.29 | 23.42 | 50 | — | 7.36 / 2.60 | 0.000 |
| D-S-pg | probe-py2 → probe-go | relay | 200 | 40.01 | 1636.96 | 200 | — | 4.06 / 2.62 | 0.000 |
| D-S-pg | probe-py2 → probe-go | relay | 50 | 29.12 | 58.53 | 50 | — | 5.54 / 2.86 | 0.000 |
| D-S-pg | probe-py2 → probe-go | write | 200 | 18.83 | 1913.72 | 200 | — | 3.51 / 0.95 | 0.000 |
| D-S-pg | probe-py2 → probe-go | write | 50 | 7.69 | 16.85 | 50 | — | 5.08 / 1.46 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | big-event | 200 | 30.03 | 58.87 | 200 | — | 3.15 / 2.44 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | big-event | 50 | 11.08 | 30.41 | 50 | — | 4.00 / 2.64 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | relay | 200 | 10.39 | 17.48 | 200 | — | 1.91 / 2.56 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | relay | 50 | 9.17 | 29.33 | 50 | — | 2.28 / 2.68 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | write | 200 | 5.61 | 11.88 | 200 | — | 1.82 / 1.25 | 0.000 |
| D-S-pg-c4 | probe-go → probe-go2 | write | 50 | 5.84 | 26.32 | 50 | — | 2.32 / 1.36 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | big-event | 200 | 39.82 | 76.38 | 200 | — | 3.27 / 4.32 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | big-event | 50 | 14.41 | 19.65 | 50 | — | 4.02 / 5.28 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | relay | 200 | 22.29 | 40.67 | 200 | — | 2.05 / 4.95 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | relay | 50 | 13.56 | 20.21 | 50 | — | 2.34 / 6.96 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | write | 200 | 10.06 | 16.42 | 200 | — | 1.91 / 4.20 | 0.000 |
| D-S-pg-c4 | probe-go2 → probe-py | write | 50 | 8.39 | 13.02 | 50 | — | 2.30 / 3.70 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | big-event | 200 | 93.93 | 192.74 | 200 | — | 4.59 / 4.31 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | big-event | 50 | 17.99 | 27.60 | 50 | — | 7.92 / 5.64 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | relay | 200 | 34.05 | 69.18 | 200 | — | 4.18 / 4.70 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | relay | 50 | 13.46 | 19.77 | 50 | — | 5.40 / 6.24 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | write | 200 | 22.13 | 51.98 | 200 | — | 4.07 / 3.83 | 0.000 |
| D-S-pg-c4 | probe-py → probe-py2 | write | 50 | 10.66 | 16.06 | 50 | — | 5.62 / 3.90 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | big-event | 200 | 2299.36 | 7050.95 | 200 | — | 3.92 / 1.55 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | big-event | 50 | 13.97 | 19.79 | 50 | — | 7.72 / 2.48 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | relay | 200 | 32.69 | 76.11 | 200 | — | 4.40 / 2.71 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | relay | 50 | 10.42 | 29.44 | 50 | — | 5.76 / 2.70 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | write | 200 | 14.28 | 44.99 | 200 | — | 3.99 / 1.25 | 0.000 |
| D-S-pg-c4 | probe-py2 → probe-go | write | 50 | 7.96 | 26.77 | 50 | — | 5.78 / 1.46 | 0.000 |
