| 格 | 进程 | 常驻内存 MiB | cgroup 内存 MiB | 空闲 CPU 核 |
| --- | --- | --- | --- | --- |

| 格 | 组件 MiB / 核 | 基础资源 MiB / 核 | 平台 MiB / 核 | 数据库连接（峰值） |
| --- | --- | --- | --- | --- |
| D9-probe-S | 275 / 0.059 | 1387 / 0.096 | 556 / 0.073 | 15 |
| K9-probe-S | 212 / 0.061 | 1288 / 0.099 | 1859 / 0.088 | 15 |
| L9-probe-S | 272 / 0.055 | 1391 / 0.098 | 169 / 0.000 | 14 |
| P9-probe-S | 273 / 0.055 | 1433 / 0.092 | 54 / 0.026 | 15 |

| 格 | 路径 | 操作 | 负载 | p50 ms | p99 ms | 吞吐 /s | 持续速率 /s | 每千次 CPU 秒（调用方 / 被调方） | 错误率 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D9-probe-S | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.27 | 0.51 | 200 | — | 0.46 / 0.35 | 0.000 |
| D9-probe-S | probe-go → probe-go2 | echo-1k-http | 200 | 0.24 | 0.41 | 200 | — | 0.37 / 0.24 | 0.000 |
| D9-probe-S | probe-go → probe-go2 | relay | 200 | 5.57 | 8.73 | 200 | — | 1.27 / 1.52 | 0.000 |
| D9-probe-S | probe-go → probe-go2 | write | 200 | 3.00 | 7.05 | 200 | — | 1.19 / 0.54 | 0.000 |
| D9-probe-S | probe-go2 → probe-py | echo-1k-grpc | 200 | 0.77 | 1.60 | 200 | — | 0.51 / 0.92 | 0.000 |
| D9-probe-S | probe-go2 → probe-py | echo-1k-http | 200 | 0.77 | 1.13 | 200 | — | 0.42 / 0.76 | 0.000 |
| D9-probe-S | probe-go2 → probe-py | relay | 200 | 6.96 | 13.41 | 200 | — | 1.34 / 3.14 | 0.000 |
| D9-probe-S | probe-go2 → probe-py | write | 200 | 3.44 | 7.83 | 200 | — | 1.26 / 1.41 | 0.000 |
| D9-probe-S | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.34 | 2.16 | 200 | — | 1.46 / 0.93 | 0.000 |
| D9-probe-S | probe-py → probe-py2 | echo-1k-http | 200 | 1.03 | 1.50 | 200 | — | 1.12 / 0.70 | 0.000 |
| D9-probe-S | probe-py → probe-py2 | relay | 200 | 8.50 | 22.26 | 200 | — | 3.28 / 3.24 | 0.000 |
| D9-probe-S | probe-py → probe-py2 | write | 200 | 5.44 | 20.96 | 200 | — | 3.05 / 1.36 | 0.000 |
| D9-probe-S | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.78 | 1.23 | 200 | — | 1.38 / 0.39 | 0.000 |
| D9-probe-S | probe-py2 → probe-go | echo-1k-http | 200 | 0.56 | 0.82 | 200 | — | 1.11 / 0.28 | 0.000 |
| D9-probe-S | probe-py2 → probe-go | relay | 200 | 9.12 | 22.62 | 200 | — | 3.44 / 1.64 | 0.000 |
| D9-probe-S | probe-py2 → probe-go | write | 200 | 5.35 | 17.88 | 200 | — | 3.04 / 0.60 | 0.000 |
| K9-probe-S | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.27 | 0.48 | 200 | — | 0.49 / 0.36 | 0.000 |
| K9-probe-S | probe-go → probe-go2 | echo-1k-http | 200 | 0.23 | 0.42 | 200 | — | 0.39 / 0.24 | 0.000 |
| K9-probe-S | probe-go → probe-go2 | relay | 200 | 7.16 | 11.40 | 200 | — | 1.40 / 1.65 | 0.000 |
| K9-probe-S | probe-go → probe-go2 | write | 200 | 2.60 | 5.79 | 200 | — | 1.22 / 0.57 | 0.000 |
| K9-probe-S | probe-go2 → probe-py | echo-1k-grpc | 200 | 0.78 | 1.83 | 200 | — | 0.53 / 0.95 | 0.000 |
| K9-probe-S | probe-go2 → probe-py | echo-1k-http | 200 | 0.77 | 1.16 | 200 | — | 0.44 / 0.77 | 0.000 |
| K9-probe-S | probe-go2 → probe-py | relay | 200 | 7.84 | 15.70 | 200 | — | 1.46 / 3.35 | 0.000 |
| K9-probe-S | probe-go2 → probe-py | write | 200 | 2.87 | 5.64 | 200 | — | 1.27 / 1.35 | 0.000 |
| K9-probe-S | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.34 | 2.41 | 200 | — | 1.49 / 0.96 | 0.000 |
| K9-probe-S | probe-py → probe-py2 | echo-1k-http | 200 | 1.10 | 1.50 | 200 | — | 1.21 / 0.75 | 0.000 |
| K9-probe-S | probe-py → probe-py2 | relay | 200 | 9.64 | 26.93 | 200 | — | 3.40 / 3.40 | 0.000 |
| K9-probe-S | probe-py → probe-py2 | write | 200 | 4.63 | 17.19 | 200 | — | 3.17 / 1.38 | 0.000 |
| K9-probe-S | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.78 | 1.21 | 200 | — | 1.44 / 0.40 | 0.000 |
| K9-probe-S | probe-py2 → probe-go | echo-1k-http | 200 | 0.57 | 0.83 | 200 | — | 1.17 / 0.29 | 0.000 |
| K9-probe-S | probe-py2 → probe-go | relay | 200 | 8.43 | 24.88 | 200 | — | 3.40 / 1.71 | 0.000 |
| K9-probe-S | probe-py2 → probe-go | write | 200 | 4.33 | 17.39 | 200 | — | 3.17 / 0.63 | 0.000 |
| L9-probe-S | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.27 | 0.49 | 200 | — | 0.47 / 0.35 | 0.000 |
| L9-probe-S | probe-go → probe-go2 | echo-1k-http | 200 | 0.23 | 0.43 | 200 | — | 0.37 / 0.24 | 0.000 |
| L9-probe-S | probe-go → probe-go2 | relay | 200 | 7.78 | 12.65 | 200 | — | 1.32 / 1.54 | 0.000 |
| L9-probe-S | probe-go → probe-go2 | write | 200 | 2.95 | 6.49 | 200 | — | 1.18 / 0.52 | 0.000 |
| L9-probe-S | probe-go2 → probe-py | echo-1k-grpc | 200 | 0.72 | 1.30 | 200 | — | 0.49 / 0.82 | 0.000 |
| L9-probe-S | probe-go2 → probe-py | echo-1k-http | 200 | 0.58 | 0.86 | 200 | — | 0.41 / 0.57 | 0.000 |
| L9-probe-S | probe-go2 → probe-py | relay | 200 | 6.99 | 12.24 | 200 | — | 1.35 / 2.70 | 0.000 |
| L9-probe-S | probe-go2 → probe-py | write | 200 | 2.93 | 6.86 | 200 | — | 1.17 / 1.04 | 0.000 |
| L9-probe-S | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.19 | 1.93 | 200 | — | 1.13 / 0.84 | 0.000 |
| L9-probe-S | probe-py → probe-py2 | echo-1k-http | 200 | 0.82 | 1.15 | 200 | — | 0.89 / 0.57 | 0.000 |
| L9-probe-S | probe-py → probe-py2 | relay | 200 | 7.90 | 16.36 | 200 | — | 2.65 / 2.81 | 0.000 |
| L9-probe-S | probe-py → probe-py2 | write | 200 | 4.21 | 14.28 | 200 | — | 2.41 / 1.06 | 0.000 |
| L9-probe-S | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.67 | 0.99 | 200 | — | 1.09 / 0.36 | 0.000 |
| L9-probe-S | probe-py2 → probe-go | echo-1k-http | 200 | 0.46 | 0.67 | 200 | — | 0.85 / 0.27 | 0.000 |
| L9-probe-S | probe-py2 → probe-go | relay | 200 | 8.16 | 19.60 | 200 | — | 2.75 / 1.61 | 0.000 |
| L9-probe-S | probe-py2 → probe-go | write | 200 | 3.93 | 12.81 | 200 | — | 2.45 / 0.59 | 0.000 |
| P9-probe-S | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.26 | 0.46 | 200 | — | 0.45 / 0.34 | 0.000 |
| P9-probe-S | probe-go → probe-go2 | echo-1k-http | 200 | 0.24 | 0.44 | 200 | — | 0.37 / 0.23 | 0.000 |
| P9-probe-S | probe-go → probe-go2 | relay | 200 | 6.14 | 11.51 | 200 | — | 1.19 / 1.44 | 0.000 |
| P9-probe-S | probe-go → probe-go2 | write | 200 | 2.30 | 5.56 | 200 | — | 1.06 / 0.47 | 0.000 |
| P9-probe-S | probe-go2 → probe-py | echo-1k-grpc | 200 | 0.80 | 1.62 | 200 | — | 0.51 / 0.98 | 0.000 |
| P9-probe-S | probe-go2 → probe-py | echo-1k-http | 200 | 0.78 | 1.14 | 200 | — | 0.43 / 0.77 | 0.000 |
| P9-probe-S | probe-go2 → probe-py | relay | 200 | 7.52 | 18.70 | 200 | — | 1.27 / 3.12 | 0.000 |
| P9-probe-S | probe-go2 → probe-py | write | 200 | 2.54 | 4.98 | 200 | — | 1.09 / 1.05 | 0.000 |
| P9-probe-S | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.39 | 2.16 | 200 | — | 1.45 / 0.99 | 0.000 |
| P9-probe-S | probe-py → probe-py2 | echo-1k-http | 200 | 1.08 | 1.55 | 200 | — | 1.16 / 0.73 | 0.000 |
| P9-probe-S | probe-py → probe-py2 | relay | 200 | 10.58 | 29.54 | 200 | — | 3.27 / 3.19 | 0.000 |
| P9-probe-S | probe-py → probe-py2 | write | 200 | 4.38 | 18.32 | 200 | — | 3.00 / 1.10 | 0.000 |
| P9-probe-S | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.79 | 1.19 | 200 | — | 1.39 / 0.39 | 0.000 |
| P9-probe-S | probe-py2 → probe-go | echo-1k-http | 200 | 0.58 | 0.82 | 200 | — | 1.13 / 0.28 | 0.000 |
| P9-probe-S | probe-py2 → probe-go | relay | 200 | 8.96 | 30.50 | 200 | — | 3.35 / 1.50 | 0.000 |
| P9-probe-S | probe-py2 → probe-go | write | 200 | 6.18 | 25.26 | 200 | — | 3.01 / 0.55 | 0.000 |
