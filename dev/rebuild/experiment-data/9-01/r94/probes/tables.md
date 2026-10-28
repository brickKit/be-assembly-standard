| 格 | 进程 | 常驻内存 MiB | cgroup 内存 MiB | 空闲 CPU 核 |
| --- | --- | --- | --- | --- |
| D9-probe-base-go | `brickkit-d9-probe-base-go-test-probe-go-3-2-20-1` | 32.4 | 13.5 | 0.010 |
| D9-probe-base-goshell-1 | `brickkit-d9-probe-base-goshell-1-be-go-core-3-0-33-1` | 33.9 | 40.2 | 0.010 |
| D9-probe-base-goshell-2 | `brickkit-d9-probe-base-goshell-2-be-go-core-3-0-33-1` | 35.1 | 14.4 | 0.018 |
| D9-probe-base-goshell-4 | `brickkit-d9-probe-base-goshell-4-be-go-core-3-0-33-1` | 38.7 | 17.9 | 0.031 |
| D9-probe-base-py | `brickkit-d9-probe-base-py-test-probe-py-3-2-19-1` | 101.8 | 97.5 | 0.016 |
| D9-probe-base-pyshell-1 | `brickkit-d9-probe-base-pyshell-1-be-py-render-3-0-25-1` | 107.4 | 139.4 | 0.013 |
| D9-probe-base-pyshell-2 | `brickkit-d9-probe-base-pyshell-2-be-py-render-3-0-25-1` | 107.9 | 93.4 | 0.020 |
| K9-probe-base-go | `pod:test-probe-go-3-2-20` | — | 11.7 | 0.010 |
| K9-probe-base-goshell-1 | `pod:be-go-core-3-0-33` | — | 12.4 | 0.010 |
| K9-probe-base-goshell-2 | `pod:be-go-core-3-0-33` | — | 14.0 | 0.018 |
| K9-probe-base-goshell-4 | `pod:be-go-core-3-0-33` | — | 17.3 | 0.032 |
| K9-probe-base-py | `pod:test-probe-py-3-2-19` | — | 89.0 | 0.017 |
| K9-probe-base-pyshell-1 | `pod:be-py-render-3-0-25` | — | 117.1 | 0.013 |
| K9-probe-base-pyshell-2 | `pod:be-py-render-3-0-25` | — | 94.6 | 0.021 |
| L9-probe-base-go | `proc:test/probe-go` | 35.6 | — | 0.010 |
| L9-probe-base-goshell-1 | `proc:be/go-core` | 37.5 | — | 0.010 |
| L9-probe-base-goshell-2 | `proc:be/go-core` | 39.2 | — | 0.017 |
| L9-probe-base-goshell-4 | `proc:be/go-core` | 42.8 | — | 0.029 |
| L9-probe-base-py | `proc:test/probe-py` | 99.6 | — | 0.013 |
| L9-probe-base-pyshell-1 | `proc:be/py-render` | 107.9 | — | 0.013 |
| L9-probe-base-pyshell-2 | `proc:be/py-render` | 108.1 | — | 0.025 |
| P9-probe-base-go | `brickkit-p9-probe-base-go-test-probe-go-3-2-20-1` | 34.1 | 13.2 | 0.010 |
| P9-probe-base-goshell-1 | `brickkit-p9-probe-base-goshell-1-be-go-core-3-0-33-1` | 36.0 | 12.8 | 0.010 |
| P9-probe-base-goshell-2 | `brickkit-p9-probe-base-goshell-2-be-go-core-3-0-33-1` | 37.4 | 14.6 | 0.015 |
| P9-probe-base-goshell-4 | `brickkit-p9-probe-base-goshell-4-be-go-core-3-0-33-1` | 40.4 | 17.8 | 0.024 |
| P9-probe-base-py | `brickkit-p9-probe-base-py-test-probe-py-3-2-19-1` | 102.1 | 96.6 | 0.017 |
| P9-probe-base-pyshell-1 | `brickkit-p9-probe-base-pyshell-1-be-py-render-3-0-25-1` | 107.1 | 162.5 | 0.014 |
| P9-probe-base-pyshell-2 | `brickkit-p9-probe-base-pyshell-2-be-py-render-3-0-25-1` | 108.2 | 93.7 | 0.020 |

| 外壳 | 承载 | 内存 MiB（常驻；K 行是 Pod 的 cgroup） | 比上一档每多一个成员 MiB |
| --- | --- | --- | --- |
| D9-probe goshell | 1 | 33.9 | — |
| D9-probe goshell | 2 | 35.1 | 1.2 |
| D9-probe goshell | 4 | 38.7 | 1.8 |
| D9-probe pyshell | 1 | 107.4 | — |
| D9-probe pyshell | 2 | 107.9 | 0.5 |
| K9-probe goshell | 1 | 12.4 | — |
| K9-probe goshell | 2 | 14.0 | 1.6 |
| K9-probe goshell | 4 | 17.3 | 1.6 |
| K9-probe pyshell | 1 | 117.1 | — |
| K9-probe pyshell | 2 | 94.6 | -22.6 |
| L9-probe goshell | 1 | 37.5 | — |
| L9-probe goshell | 2 | 39.2 | 1.8 |
| L9-probe goshell | 4 | 42.8 | 1.8 |
| L9-probe pyshell | 1 | 107.9 | — |
| L9-probe pyshell | 2 | 108.1 | 0.3 |
| P9-probe goshell | 1 | 36.0 | — |
| P9-probe goshell | 2 | 37.4 | 1.4 |
| P9-probe goshell | 4 | 40.4 | 1.5 |
| P9-probe pyshell | 1 | 107.1 | — |
| P9-probe pyshell | 2 | 108.2 | 1.1 |

| 格 | 组件 MiB / 核 | 基础资源 MiB / 核 | 平台 MiB / 核 | 数据库连接（峰值） |
| --- | --- | --- | --- | --- |
| D9-probe-H2 | 177 / 0.053 | 1315 / 0.089 | 590 / 0.070 | 18 |
| D9-probe-base-go | 32 / 0.010 | 1973 / 0.061 | 528 / 0.062 | 5 |
| D9-probe-base-goshell-1 | 34 / 0.010 | 1977 / 0.059 | 540 / 0.062 | 5 |
| D9-probe-base-goshell-2 | 35 / 0.018 | 2001 / 0.054 | 551 / 0.062 | 8 |
| D9-probe-base-goshell-4 | 39 / 0.031 | 2062 / 0.085 | 573 / 0.067 | 16 |
| D9-probe-base-py | 102 / 0.016 | 1965 / 0.036 | 529 / 0.062 | 3 |
| D9-probe-base-pyshell-1 | 107 / 0.013 | 1982 / 0.056 | 540 / 0.062 | 3 |
| D9-probe-base-pyshell-2 | 108 / 0.020 | 1990 / 0.046 | 551 / 0.062 | 6 |
| K9-probe-H2 | 145 / 0.054 | 1401 / 0.092 | 2431 / 0.087 | 18 |
| K9-probe-base-go | 12 / 0.010 | 1242 / 0.062 | 1640 / 0.082 | 5 |
| K9-probe-base-goshell-1 | 12 / 0.010 | 1252 / 0.062 | 1918 / 0.083 | 5 |
| K9-probe-base-goshell-2 | 14 / 0.018 | 1267 / 0.057 | 1977 / 0.083 | 8 |
| K9-probe-base-goshell-4 | 17 / 0.032 | 1328 / 0.089 | 2051 / 0.084 | 16 |
| K9-probe-base-py | 89 / 0.017 | 1241 / 0.038 | 1840 / 0.083 | 3 |
| K9-probe-base-pyshell-1 | 117 / 0.013 | 1242 / 0.058 | 2394 / 0.084 | 3 |
| K9-probe-base-pyshell-2 | 95 / 0.021 | 1269 / 0.048 | 2577 / 0.084 | 6 |
| L9-probe-H2 | 187 / 0.055 | 1442 / 0.090 | 153 / 0.000 | 18 |
| L9-probe-S | 270 / 0.055 | 1220 / 0.098 | 174 / 0.000 | 15 |
| L9-probe-base-go | 36 / 0.010 | 1174 / 0.059 | 69 / 0.000 | 5 |
| L9-probe-base-goshell-1 | 37 / 0.010 | 1166 / 0.060 | 64 / 0.000 | 4 |
| L9-probe-base-goshell-2 | 39 / 0.017 | 1190 / 0.075 | 70 / 0.000 | 8 |
| L9-probe-base-goshell-4 | 43 / 0.029 | 1248 / 0.083 | 67 / 0.000 | 16 |
| L9-probe-base-py | 100 / 0.013 | 1169 / 0.036 | 44 / 0.000 | 3 |
| L9-probe-base-pyshell-1 | 108 / 0.013 | 1165 / 0.057 | 56 / 0.000 | 3 |
| L9-probe-base-pyshell-2 | 108 / 0.025 | 1178 / 0.050 | 54 / 0.000 | 5 |
| P9-probe-H2 | 179 / 0.047 | 1235 / 0.104 | 45 / 0.026 | 17 |
| P9-probe-base-go | 34 / 0.010 | 1977 / 0.060 | 29 / 0.009 | 5 |
| P9-probe-base-goshell-1 | 36 / 0.010 | 1983 / 0.059 | 29 / 0.009 | 5 |
| P9-probe-base-goshell-2 | 37 / 0.015 | 1986 / 0.051 | 29 / 0.015 | 8 |
| P9-probe-base-goshell-4 | 40 / 0.024 | 2047 / 0.098 | 29 / 0.022 | 16 |
| P9-probe-base-py | 102 / 0.017 | 1973 / 0.037 | 29 / 0.007 | 3 |
| P9-probe-base-pyshell-1 | 107 / 0.014 | 1961 / 0.063 | 29 / 0.007 | 3 |
| P9-probe-base-pyshell-2 | 108 / 0.020 | 1972 / 0.045 | 29 / 0.011 | 6 |

| 格 | 路径 | 操作 | 负载 | p50 ms | p99 ms | 吞吐 /s | 持续速率 /s | 每千次 CPU 秒（调用方 / 被调方） | 错误率 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D9-probe-H2 | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.22 | 0.41 | 200 | — | 0.66 / 同一进程 | 0.000 |
| D9-probe-H2 | probe-go → probe-go2 | echo-1k-http | 200 | 0.18 | 0.36 | 200 | — | 0.49 / 同一进程 | 0.000 |
| D9-probe-H2 | probe-go → probe-go2 | relay | 200 | 4.97 | 8.33 | 200 | — | 2.43 / 同一进程 | 0.000 |
| D9-probe-H2 | probe-go → probe-go2 | write | 200 | 2.29 | 4.38 | 200 | — | 1.51 / 同一进程 | 0.000 |
| D9-probe-H2 | probe-go2 → probe-go3 | echo-1k-grpc | 200 | 0.27 | 0.50 | 200 | — | 0.50 / 0.35 | 0.000 |
| D9-probe-H2 | probe-go2 → probe-go3 | echo-1k-http | 200 | 0.24 | 0.41 | 200 | — | 0.41 / 0.24 | 0.000 |
| D9-probe-H2 | probe-go2 → probe-go3 | relay | 200 | 5.62 | 9.04 | 200 | — | 1.31 / 1.54 | 0.000 |
| D9-probe-H2 | probe-go2 → probe-go3 | write | 200 | 2.31 | 4.24 | 200 | — | 1.17 / 0.54 | 0.000 |
| D9-probe-H2 | probe-go3 → probe-py | echo-1k-grpc | 200 | 0.70 | 1.47 | 200 | — | 0.50 / 0.85 | 0.000 |
| D9-probe-H2 | probe-go3 → probe-py | echo-1k-http | 200 | 0.66 | 1.01 | 200 | — | 0.43 / 0.66 | 0.000 |
| D9-probe-H2 | probe-go3 → probe-py | relay | 200 | 5.98 | 12.62 | 200 | — | 1.31 / 3.24 | 0.000 |
| D9-probe-H2 | probe-go3 → probe-py | write | 200 | 3.26 | 7.51 | 200 | — | 1.22 / 1.09 | 0.000 |
| D9-probe-H2 | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.16 | 2.17 | 200 | — | 1.89 / 同一进程 | 0.000 |
| D9-probe-H2 | probe-py → probe-py2 | echo-1k-http | 200 | 0.78 | 1.21 | 200 | — | 1.29 / 同一进程 | 0.000 |
| D9-probe-H2 | probe-py → probe-py2 | relay | 200 | 6.19 | 19.06 | 200 | — | 3.78 / 同一进程 | 0.000 |
| D9-probe-H2 | probe-py → probe-py2 | write | 200 | 4.15 | 16.05 | 200 | — | 2.97 / 同一进程 | 0.000 |
| D9-probe-H2 | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.70 | 1.18 | 200 | — | 1.24 / 0.42 | 0.000 |
| D9-probe-H2 | probe-py2 → probe-go | echo-1k-http | 200 | 0.51 | 0.76 | 200 | — | 1.01 / 0.32 | 0.000 |
| D9-probe-H2 | probe-py2 → probe-go | relay | 200 | 5.69 | 12.20 | 200 | — | 2.64 / 1.81 | 0.000 |
| D9-probe-H2 | probe-py2 → probe-go | write | 200 | 4.04 | 14.20 | 200 | — | 2.55 / 0.64 | 0.000 |
| K9-probe-H2 | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.24 | 0.44 | 200 | — | 0.74 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-go → probe-go2 | echo-1k-http | 200 | 0.19 | 0.35 | 200 | — | 0.53 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-go → probe-go2 | relay | 200 | 5.32 | 8.57 | 200 | — | 2.59 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-go → probe-go2 | write | 200 | 2.43 | 4.65 | 200 | — | 1.62 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-go2 → probe-go3 | echo-1k-grpc | 200 | 0.27 | 0.49 | 200 | — | 0.53 / 0.36 | 0.000 |
| K9-probe-H2 | probe-go2 → probe-go3 | echo-1k-http | 200 | 0.24 | 0.41 | 200 | — | 0.43 / 0.24 | 0.000 |
| K9-probe-H2 | probe-go2 → probe-go3 | relay | 200 | 5.80 | 9.24 | 200 | — | 1.39 / 1.62 | 0.000 |
| K9-probe-H2 | probe-go2 → probe-go3 | write | 200 | 2.41 | 4.75 | 200 | — | 1.24 / 0.57 | 0.000 |
| K9-probe-H2 | probe-go3 → probe-py | echo-1k-grpc | 200 | 0.69 | 1.64 | 200 | — | 0.52 / 0.89 | 0.000 |
| K9-probe-H2 | probe-go3 → probe-py | echo-1k-http | 200 | 0.66 | 1.03 | 200 | — | 0.45 / 0.68 | 0.000 |
| K9-probe-H2 | probe-go3 → probe-py | relay | 200 | 6.13 | 12.04 | 200 | — | 1.39 / 3.30 | 0.000 |
| K9-probe-H2 | probe-go3 → probe-py | write | 200 | 2.68 | 4.91 | 200 | — | 1.26 / 1.10 | 0.000 |
| K9-probe-H2 | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.17 | 2.19 | 200 | — | 1.95 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-py → probe-py2 | echo-1k-http | 200 | 0.82 | 1.33 | 200 | — | 1.36 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-py → probe-py2 | relay | 200 | 7.21 | 29.18 | 200 | — | 4.07 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-py → probe-py2 | write | 200 | 4.37 | 18.13 | 200 | — | 3.04 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.70 | 1.18 | 200 | — | 1.28 / 0.44 | 0.000 |
| K9-probe-H2 | probe-py2 → probe-go | echo-1k-http | 200 | 0.52 | 0.78 | 200 | — | 1.07 / 0.34 | 0.000 |
| K9-probe-H2 | probe-py2 → probe-go | relay | 200 | 6.01 | 13.56 | 200 | — | 2.78 / 1.93 | 0.000 |
| K9-probe-H2 | probe-py2 → probe-go | write | 200 | 4.25 | 14.94 | 200 | — | 2.59 / 0.66 | 0.000 |
| L9-probe-H2 | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.22 | 0.41 | 200 | — | 0.67 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-go → probe-go2 | echo-1k-http | 200 | 0.19 | 0.36 | 200 | — | 0.50 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-go → probe-go2 | relay | 200 | 7.07 | 11.31 | 200 | — | 2.46 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-go → probe-go2 | write | 200 | 3.22 | 8.07 | 200 | — | 1.53 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-go2 → probe-go3 | echo-1k-grpc | 200 | 0.27 | 0.44 | 200 | — | 0.48 / 0.34 | 0.000 |
| L9-probe-H2 | probe-go2 → probe-go3 | echo-1k-http | 200 | 0.23 | 0.41 | 200 | — | 0.41 / 0.24 | 0.000 |
| L9-probe-H2 | probe-go2 → probe-go3 | relay | 200 | 7.83 | 13.19 | 200 | — | 1.35 / 1.57 | 0.000 |
| L9-probe-H2 | probe-go2 → probe-go3 | write | 200 | 3.25 | 8.47 | 200 | — | 1.18 / 0.53 | 0.000 |
| L9-probe-H2 | probe-go3 → probe-py | echo-1k-grpc | 200 | 0.72 | 1.47 | 200 | — | 0.50 / 0.87 | 0.000 |
| L9-probe-H2 | probe-go3 → probe-py | echo-1k-http | 200 | 0.59 | 0.91 | 200 | — | 0.41 / 0.62 | 0.000 |
| L9-probe-H2 | probe-go3 → probe-py | relay | 200 | 6.92 | 12.43 | 200 | — | 1.34 / 3.49 | 0.000 |
| L9-probe-H2 | probe-go3 → probe-py | write | 200 | 3.43 | 8.49 | 200 | — | 1.18 / 1.12 | 0.000 |
| L9-probe-H2 | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.10 | 1.96 | 200 | — | 1.75 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-py → probe-py2 | echo-1k-http | 200 | 0.65 | 1.14 | 200 | — | 1.17 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-py → probe-py2 | relay | 200 | 10.51 | 29.97 | 200 | — | 4.42 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-py → probe-py2 | write | 200 | 6.29 | 22.85 | 200 | — | 3.18 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.67 | 1.04 | 200 | — | 1.14 / 0.39 | 0.000 |
| L9-probe-H2 | probe-py2 → probe-go | echo-1k-http | 200 | 0.47 | 0.69 | 200 | — | 0.92 / 0.30 | 0.000 |
| L9-probe-H2 | probe-py2 → probe-go | relay | 200 | 8.81 | 22.37 | 200 | — | 2.86 / 1.85 | 0.000 |
| L9-probe-H2 | probe-py2 → probe-go | write | 200 | 4.55 | 18.00 | 200 | — | 2.52 / 0.62 | 0.000 |
| L9-probe-S | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.27 | 0.46 | 200 | — | 0.45 / 0.34 | 0.000 |
| L9-probe-S | probe-go → probe-go2 | echo-1k-http | 200 | 0.23 | 0.41 | 200 | — | 0.37 / 0.24 | 0.000 |
| L9-probe-S | probe-go → probe-go2 | relay | 200 | 6.22 | 10.67 | 200 | — | 1.30 / 1.51 | 0.000 |
| L9-probe-S | probe-go → probe-go2 | write | 200 | 3.29 | 8.52 | 200 | — | 1.18 / 0.53 | 0.000 |
| L9-probe-S | probe-go2 → probe-py | echo-1k-grpc | 200 | 0.73 | 1.39 | 200 | — | 0.50 / 0.83 | 0.000 |
| L9-probe-S | probe-go2 → probe-py | echo-1k-http | 200 | 0.58 | 0.86 | 200 | — | 0.41 / 0.57 | 0.000 |
| L9-probe-S | probe-go2 → probe-py | relay | 200 | 7.07 | 13.06 | 200 | — | 1.35 / 2.72 | 0.000 |
| L9-probe-S | probe-go2 → probe-py | write | 200 | 3.32 | 7.95 | 200 | — | 1.17 / 1.05 | 0.000 |
| L9-probe-S | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.19 | 1.95 | 200 | — | 1.13 / 0.85 | 0.000 |
| L9-probe-S | probe-py → probe-py2 | echo-1k-http | 200 | 0.80 | 1.12 | 200 | — | 0.87 / 0.55 | 0.000 |
| L9-probe-S | probe-py → probe-py2 | relay | 200 | 7.91 | 18.16 | 200 | — | 2.65 / 2.80 | 0.000 |
| L9-probe-S | probe-py → probe-py2 | write | 200 | 5.80 | 23.46 | 200 | — | 2.42 / 1.09 | 0.000 |
| L9-probe-S | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.67 | 0.99 | 200 | — | 1.09 / 0.36 | 0.000 |
| L9-probe-S | probe-py2 → probe-go | echo-1k-http | 200 | 0.46 | 0.66 | 200 | — | 0.83 / 0.27 | 0.000 |
| L9-probe-S | probe-py2 → probe-go | relay | 200 | 8.69 | 19.95 | 200 | — | 2.73 / 1.60 | 0.000 |
| L9-probe-S | probe-py2 → probe-go | write | 200 | 4.83 | 17.97 | 200 | — | 2.43 / 0.60 | 0.000 |
| P9-probe-H2 | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.21 | 0.42 | 200 | — | 0.63 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-go → probe-go2 | echo-1k-http | 200 | 0.17 | 0.34 | 200 | — | 0.46 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-go → probe-go2 | relay | 200 | 5.14 | 9.26 | 200 | — | 2.18 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-go → probe-go2 | write | 200 | 2.34 | 5.21 | 200 | — | 1.37 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-go2 → probe-go3 | echo-1k-grpc | 200 | 0.27 | 0.46 | 200 | — | 0.49 / 0.35 | 0.000 |
| P9-probe-H2 | probe-go2 → probe-go3 | echo-1k-http | 200 | 0.24 | 0.43 | 200 | — | 0.40 / 0.24 | 0.000 |
| P9-probe-H2 | probe-go2 → probe-go3 | relay | 200 | 5.87 | 10.21 | 200 | — | 1.20 / 1.45 | 0.000 |
| P9-probe-H2 | probe-go2 → probe-go3 | write | 200 | 2.32 | 4.81 | 200 | — | 1.08 / 0.49 | 0.000 |
| P9-probe-H2 | probe-go3 → probe-py | echo-1k-grpc | 200 | 0.77 | 1.48 | 200 | — | 0.53 / 0.94 | 0.000 |
| P9-probe-H2 | probe-go3 → probe-py | echo-1k-http | 200 | 0.67 | 1.01 | 200 | — | 0.44 / 0.70 | 0.000 |
| P9-probe-H2 | probe-go3 → probe-py | relay | 200 | 6.38 | 13.46 | 200 | — | 1.22 / 3.30 | 0.000 |
| P9-probe-H2 | probe-go3 → probe-py | write | 200 | 2.51 | 4.89 | 200 | — | 1.08 / 0.91 | 0.000 |
| P9-probe-H2 | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.09 | 2.02 | 200 | — | 1.79 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-py → probe-py2 | echo-1k-http | 200 | 0.74 | 1.24 | 200 | — | 1.27 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-py → probe-py2 | relay | 200 | 9.53 | 35.62 | 200 | — | 4.30 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-py → probe-py2 | write | 200 | 3.95 | 11.77 | 200 | — | 3.02 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.71 | 1.10 | 200 | — | 1.24 / 0.41 | 0.000 |
| P9-probe-H2 | probe-py2 → probe-go | echo-1k-http | 200 | 0.51 | 0.77 | 200 | — | 0.98 / 0.30 | 0.000 |
| P9-probe-H2 | probe-py2 → probe-go | relay | 200 | 5.98 | 15.55 | 200 | — | 2.54 / 1.66 | 0.000 |
| P9-probe-H2 | probe-py2 → probe-go | write | 200 | 4.54 | 18.74 | 200 | — | 2.57 / 0.57 | 0.000 |
