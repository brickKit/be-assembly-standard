| 格 | 进程 | 常驻内存 MiB | cgroup 内存 MiB | 空闲 CPU 核 |
| --- | --- | --- | --- | --- |
| K9-probe-base-go | `pod:test-probe-go-3-2-19` | — | 13.9 | 0.010 |
| K9-probe-base-goshell-1 | `pod:be-go-core-3-0-32` | — | 12.5 | 0.010 |
| K9-probe-base-goshell-2 | `pod:be-go-core-3-0-32` | — | 14.2 | 0.018 |
| K9-probe-base-goshell-4 | `pod:be-go-core-3-0-32` | — | 17.5 | 0.032 |
| K9-probe-base-py | `pod:test-probe-py-3-2-19` | — | 89.0 | 0.016 |
| K9-probe-base-pyshell-1 | `pod:be-py-render-3-0-25` | — | 117.3 | 0.013 |
| K9-probe-base-pyshell-2 | `pod:be-py-render-3-0-25` | — | 93.9 | 0.020 |
| L9-probe-base-go | `proc:test/probe-go` | 35.9 | — | 0.010 |
| L9-probe-base-goshell-1 | `proc:be/go-core` | 37.5 | — | 0.010 |
| L9-probe-base-goshell-2 | `proc:be/go-core` | 36.8 | — | 0.017 |
| L9-probe-base-goshell-4 | `proc:be/go-core` | 42.3 | — | 0.029 |
| L9-probe-base-py | `proc:test/probe-py` | 99.8 | — | 0.013 |
| L9-probe-base-pyshell-1 | `proc:be/py-render` | 104.6 | — | 0.014 |
| L9-probe-base-pyshell-2 | `proc:be/py-render` | 108.1 | — | 0.025 |
| P9-probe-base-go | `brickkit-p9-probe-base-go-test-probe-go-3-2-19-1` | 32.8 | 13.8 | 0.010 |
| P9-probe-base-goshell-1 | `brickkit-p9-probe-base-goshell-1-be-go-core-3-0-32-1` | 35.6 | 12.2 | 0.011 |
| P9-probe-base-goshell-2 | `brickkit-p9-probe-base-goshell-2-be-go-core-3-0-32-1` | 36.7 | 14.2 | 0.015 |
| P9-probe-base-goshell-4 | `brickkit-p9-probe-base-goshell-4-be-go-core-3-0-32-1` | 40.3 | 17.8 | 0.024 |
| P9-probe-base-py | `brickkit-p9-probe-base-py-test-probe-py-3-2-19-1` | 102.0 | 97.2 | 0.019 |
| P9-probe-base-pyshell-1 | `brickkit-p9-probe-base-pyshell-1-be-py-render-3-0-25-1` | 110.1 | 101.2 | 0.014 |
| P9-probe-base-pyshell-2 | `brickkit-p9-probe-base-pyshell-2-be-py-render-3-0-25-1` | 111.0 | 94.1 | 0.019 |

| 外壳 | 承载 | 内存 MiB（常驻；K 行是 Pod 的 cgroup） | 比上一档每多一个成员 MiB |
| --- | --- | --- | --- |
| K9-probe goshell | 1 | 12.5 | — |
| K9-probe goshell | 2 | 14.2 | 1.8 |
| K9-probe goshell | 4 | 17.5 | 1.6 |
| K9-probe pyshell | 1 | 117.3 | — |
| K9-probe pyshell | 2 | 93.9 | -23.4 |
| L9-probe goshell | 1 | 37.5 | — |
| L9-probe goshell | 2 | 36.8 | -0.7 |
| L9-probe goshell | 4 | 42.3 | 2.8 |
| L9-probe pyshell | 1 | 104.6 | — |
| L9-probe pyshell | 2 | 108.1 | 3.5 |
| P9-probe goshell | 1 | 35.6 | — |
| P9-probe goshell | 2 | 36.7 | 1.2 |
| P9-probe goshell | 4 | 40.3 | 1.8 |
| P9-probe pyshell | 1 | 110.1 | — |
| P9-probe pyshell | 2 | 111.0 | 0.9 |

| 格 | 组件 MiB / 核 | 基础资源 MiB / 核 | 平台 MiB / 核 | 数据库连接（峰值） |
| --- | --- | --- | --- | --- |
| K9-probe-H2 | 126 / 0.052 | 2543 / 0.092 | 2681 / 0.089 | 18 |
| K9-probe-S | 205 / 0.060 | 2358 / 0.098 | 2624 / 0.089 | 14 |
| K9-probe-base-go | 14 / 0.010 | 2037 / 0.043 | 1594 / 0.085 | 5 |
| K9-probe-base-goshell-1 | 12 / 0.010 | 2317 / 0.062 | 1914 / 0.086 | 5 |
| K9-probe-base-goshell-2 | 14 / 0.018 | 2337 / 0.057 | 1978 / 0.086 | 8 |
| K9-probe-base-goshell-4 | 17 / 0.032 | 2407 / 0.109 | 2051 / 0.086 | 16 |
| K9-probe-base-py | 89 / 0.016 | 2302 / 0.059 | 1776 / 0.085 | 3 |
| K9-probe-base-pyshell-1 | 117 / 0.013 | 2326 / 0.038 | 2389 / 0.086 | 3 |
| K9-probe-base-pyshell-2 | 94 / 0.020 | 2321 / 0.068 | 2570 / 0.086 | 6 |
| L9-probe-H2 | 186 / 0.055 | 2424 / 0.113 | 162 / 0.000 | 17 |
| L9-probe-base-go | 36 / 0.010 | 2540 / 0.062 | 61 / 0.000 | 5 |
| L9-probe-base-goshell-1 | 38 / 0.010 | 2502 / 0.061 | 57 / 0.000 | 5 |
| L9-probe-base-goshell-2 | 37 / 0.017 | 2482 / 0.056 | 69 / 0.000 | 8 |
| L9-probe-base-goshell-4 | 42 / 0.029 | 2487 / 0.105 | 62 / 0.000 | 16 |
| L9-probe-base-py | 100 / 0.013 | 2489 / 0.038 | 44 / 0.000 | 3 |
| L9-probe-base-pyshell-1 | 105 / 0.014 | 2405 / 0.037 | 57 / 0.000 | 3 |
| L9-probe-base-pyshell-2 | 108 / 0.025 | 2377 / 0.072 | 55 / 0.000 | 4 |
| P9-probe-H2 | 183 / 0.046 | 2515 / 0.084 | 45 / 0.028 | 17 |
| P9-probe-S | 270 / 0.054 | 2990 / 0.072 | 53 / 0.025 | 16 |
| P9-probe-base-go | 33 / 0.010 | 3000 / 0.042 | 29 / 0.007 | 5 |
| P9-probe-base-goshell-1 | 36 / 0.011 | 2928 / 0.040 | 29 / 0.010 | 4 |
| P9-probe-base-goshell-2 | 37 / 0.015 | 2951 / 0.075 | 29 / 0.016 | 8 |
| P9-probe-base-goshell-4 | 40 / 0.024 | 3018 / 0.099 | 29 / 0.022 | 16 |
| P9-probe-base-py | 102 / 0.019 | 2918 / 0.060 | 29 / 0.009 | 3 |
| P9-probe-base-pyshell-1 | 110 / 0.014 | 2935 / 0.037 | 29 / 0.007 | 3 |
| P9-probe-base-pyshell-2 | 111 / 0.019 | 2952 / 0.065 | 29 / 0.010 | 6 |

| 格 | 路径 | 操作 | 负载 | p50 ms | p99 ms | 吞吐 /s | 持续速率 /s | 每千次 CPU 秒（调用方 / 被调方） | 错误率 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| K9-probe-H2 | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.23 | 0.41 | 200 | — | 0.70 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-go → probe-go2 | echo-1k-http | 200 | 0.18 | 0.36 | 200 | — | 0.51 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-go → probe-go2 | relay | 200 | 6.12 | 10.29 | 200 | — | 2.57 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-go → probe-go2 | write | 200 | 2.49 | 5.06 | 200 | — | 1.58 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-go2 → probe-go3 | echo-1k-grpc | 200 | 0.26 | 0.45 | 200 | — | 0.51 / 0.35 | 0.000 |
| K9-probe-H2 | probe-go2 → probe-go3 | echo-1k-http | 200 | 0.23 | 0.41 | 200 | — | 0.43 / 0.24 | 0.000 |
| K9-probe-H2 | probe-go2 → probe-go3 | relay | 200 | 6.72 | 10.34 | 200 | — | 1.39 / 1.61 | 0.000 |
| K9-probe-H2 | probe-go2 → probe-go3 | write | 200 | 2.48 | 4.62 | 200 | — | 1.22 / 0.56 | 0.000 |
| K9-probe-H2 | probe-go3 → probe-py | echo-1k-grpc | 200 | 0.66 | 1.43 | 200 | — | 0.50 / 0.85 | 0.000 |
| K9-probe-H2 | probe-go3 → probe-py | echo-1k-http | 200 | 0.68 | 1.23 | 200 | — | 0.48 / 0.72 | 0.000 |
| K9-probe-H2 | probe-go3 → probe-py | relay | 200 | 6.10 | 10.78 | 200 | — | 1.37 / 3.32 | 0.000 |
| K9-probe-H2 | probe-go3 → probe-py | write | 200 | 2.88 | 5.63 | 200 | — | 1.32 / 1.20 | 0.000 |
| K9-probe-H2 | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.13 | 2.07 | 200 | — | 1.87 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-py → probe-py2 | echo-1k-http | 200 | 0.79 | 1.23 | 200 | — | 1.32 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-py → probe-py2 | relay | 200 | 6.62 | 21.81 | 200 | — | 3.88 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-py → probe-py2 | write | 200 | 3.38 | 8.96 | 200 | — | 2.97 / 同一进程 | 0.000 |
| K9-probe-H2 | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.68 | 1.15 | 200 | — | 1.24 / 0.43 | 0.000 |
| K9-probe-H2 | probe-py2 → probe-go | echo-1k-http | 200 | 0.49 | 0.71 | 200 | — | 1.00 / 0.31 | 0.000 |
| K9-probe-H2 | probe-py2 → probe-go | relay | 200 | 6.52 | 13.88 | 200 | — | 2.74 / 1.92 | 0.000 |
| K9-probe-H2 | probe-py2 → probe-go | write | 200 | 3.50 | 9.38 | 200 | — | 2.59 / 0.66 | 0.000 |
| K9-probe-S | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.26 | 0.46 | 200 | — | 0.47 / 0.35 | 0.000 |
| K9-probe-S | probe-go → probe-go2 | echo-1k-http | 200 | 0.23 | 0.40 | 200 | — | 0.39 / 0.24 | 0.000 |
| K9-probe-S | probe-go → probe-go2 | relay | 200 | 7.37 | 10.78 | 200 | — | 1.39 / 1.62 | 0.000 |
| K9-probe-S | probe-go → probe-go2 | write | 200 | 2.94 | 6.58 | 200 | — | 1.24 / 0.56 | 0.000 |
| K9-probe-S | probe-go2 → probe-py | echo-1k-grpc | 200 | 0.73 | 1.53 | 200 | — | 0.51 / 0.91 | 0.000 |
| K9-probe-S | probe-go2 → probe-py | echo-1k-http | 200 | 0.75 | 1.10 | 200 | — | 0.43 / 0.74 | 0.000 |
| K9-probe-S | probe-go2 → probe-py | relay | 200 | 7.08 | 13.75 | 200 | — | 1.40 / 3.20 | 0.000 |
| K9-probe-S | probe-go2 → probe-py | write | 200 | 3.17 | 6.81 | 200 | — | 1.26 / 1.32 | 0.000 |
| K9-probe-S | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.31 | 2.13 | 200 | — | 1.45 / 0.93 | 0.000 |
| K9-probe-S | probe-py → probe-py2 | echo-1k-http | 200 | 1.06 | 1.53 | 200 | — | 1.16 / 0.72 | 0.000 |
| K9-probe-S | probe-py → probe-py2 | relay | 200 | 8.83 | 22.29 | 200 | — | 3.33 / 3.30 | 0.000 |
| K9-probe-S | probe-py → probe-py2 | write | 200 | 5.28 | 19.42 | 200 | — | 3.13 / 1.37 | 0.000 |
| K9-probe-S | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.76 | 1.15 | 200 | — | 1.40 / 0.39 | 0.000 |
| K9-probe-S | probe-py2 → probe-go | echo-1k-http | 200 | 0.56 | 0.80 | 200 | — | 1.14 / 0.28 | 0.000 |
| K9-probe-S | probe-py2 → probe-go | relay | 200 | 9.19 | 23.24 | 200 | — | 3.44 / 1.71 | 0.000 |
| K9-probe-S | probe-py2 → probe-go | write | 200 | 4.73 | 17.40 | 200 | — | 3.14 / 0.62 | 0.000 |
| L9-probe-H2 | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.24 | 0.46 | 200 | — | 0.71 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-go → probe-go2 | echo-1k-http | 200 | 0.20 | 0.39 | 200 | — | 0.51 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-go → probe-go2 | relay | 200 | 7.18 | 12.29 | 200 | — | 2.52 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-go → probe-go2 | write | 200 | 3.29 | 8.09 | 200 | — | 1.55 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-go2 → probe-go3 | echo-1k-grpc | 200 | 0.28 | 0.53 | 200 | — | 0.51 / 0.37 | 0.000 |
| L9-probe-H2 | probe-go2 → probe-go3 | echo-1k-http | 200 | 0.24 | 0.43 | 200 | — | 0.42 / 0.25 | 0.000 |
| L9-probe-H2 | probe-go2 → probe-go3 | relay | 200 | 8.01 | 15.64 | 200 | — | 1.40 / 1.64 | 0.000 |
| L9-probe-H2 | probe-go2 → probe-go3 | write | 200 | 3.32 | 8.39 | 200 | — | 1.22 / 0.56 | 0.000 |
| L9-probe-H2 | probe-go3 → probe-py | echo-1k-grpc | 200 | 0.76 | 1.50 | 200 | — | 0.52 / 0.92 | 0.000 |
| L9-probe-H2 | probe-go3 → probe-py | echo-1k-http | 200 | 0.62 | 1.01 | 200 | — | 0.43 / 0.66 | 0.000 |
| L9-probe-H2 | probe-go3 → probe-py | relay | 200 | 7.38 | 14.78 | 200 | — | 1.45 / 3.65 | 0.000 |
| L9-probe-H2 | probe-go3 → probe-py | write | 200 | 3.58 | 9.66 | 200 | — | 1.26 / 1.17 | 0.000 |
| L9-probe-H2 | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.14 | 2.06 | 200 | — | 1.87 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-py → probe-py2 | echo-1k-http | 200 | 0.75 | 1.20 | 200 | — | 1.29 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-py → probe-py2 | relay | 200 | 11.76 | 30.52 | 200 | — | 4.51 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-py → probe-py2 | write | 200 | 6.40 | 23.19 | 200 | — | 3.20 / 同一进程 | 0.000 |
| L9-probe-H2 | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.69 | 1.11 | 200 | — | 1.23 / 0.41 | 0.000 |
| L9-probe-H2 | probe-py2 → probe-go | echo-1k-http | 200 | 0.48 | 0.77 | 200 | — | 0.98 / 0.31 | 0.000 |
| L9-probe-H2 | probe-py2 → probe-go | relay | 200 | 9.21 | 22.72 | 200 | — | 2.93 / 1.89 | 0.000 |
| L9-probe-H2 | probe-py2 → probe-go | write | 200 | 4.84 | 17.12 | 200 | — | 2.59 / 0.63 | 0.000 |
| P9-probe-H2 | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.20 | 0.41 | 200 | — | 0.62 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-go → probe-go2 | echo-1k-http | 200 | 0.17 | 0.33 | 200 | — | 0.45 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-go → probe-go2 | relay | 200 | 6.48 | 10.82 | 200 | — | 2.23 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-go → probe-go2 | write | 200 | 2.88 | 6.76 | 200 | — | 1.40 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-go2 → probe-go3 | echo-1k-grpc | 200 | 0.27 | 0.48 | 200 | — | 0.49 / 0.35 | 0.000 |
| P9-probe-H2 | probe-go2 → probe-go3 | echo-1k-http | 200 | 0.24 | 0.41 | 200 | — | 0.40 / 0.23 | 0.000 |
| P9-probe-H2 | probe-go2 → probe-go3 | relay | 200 | 7.35 | 12.94 | 200 | — | 1.24 / 1.45 | 0.000 |
| P9-probe-H2 | probe-go2 → probe-go3 | write | 200 | 2.95 | 7.66 | 200 | — | 1.10 / 0.49 | 0.000 |
| P9-probe-H2 | probe-go3 → probe-py | echo-1k-grpc | 200 | 0.72 | 1.46 | 200 | — | 0.50 / 0.90 | 0.000 |
| P9-probe-H2 | probe-go3 → probe-py | echo-1k-http | 200 | 0.63 | 0.95 | 200 | — | 0.42 / 0.66 | 0.000 |
| P9-probe-H2 | probe-go3 → probe-py | relay | 200 | 6.20 | 12.61 | 200 | — | 1.21 / 3.25 | 0.000 |
| P9-probe-H2 | probe-go3 → probe-py | write | 200 | 3.15 | 6.97 | 200 | — | 1.12 / 0.90 | 0.000 |
| P9-probe-H2 | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.08 | 1.97 | 200 | — | 1.74 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-py → probe-py2 | echo-1k-http | 200 | 0.73 | 1.19 | 200 | — | 1.24 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-py → probe-py2 | relay | 200 | 9.09 | 29.19 | 200 | — | 4.27 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-py → probe-py2 | write | 200 | 4.77 | 16.77 | 200 | — | 2.95 / 同一进程 | 0.000 |
| P9-probe-H2 | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.70 | 1.06 | 200 | — | 1.21 / 0.40 | 0.000 |
| P9-probe-H2 | probe-py2 → probe-go | echo-1k-http | 200 | 0.51 | 0.75 | 200 | — | 0.98 / 0.30 | 0.000 |
| P9-probe-H2 | probe-py2 → probe-go | relay | 200 | 6.29 | 15.74 | 200 | — | 2.59 / 1.65 | 0.000 |
| P9-probe-H2 | probe-py2 → probe-go | write | 200 | 4.11 | 14.52 | 200 | — | 2.51 / 0.55 | 0.000 |
| P9-probe-S | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.27 | 0.48 | 200 | — | 0.45 / 0.34 | 0.000 |
| P9-probe-S | probe-go → probe-go2 | echo-1k-http | 200 | 0.24 | 0.43 | 200 | — | 0.37 / 0.23 | 0.000 |
| P9-probe-S | probe-go → probe-go2 | relay | 200 | 5.95 | 9.49 | 200 | — | 1.18 / 1.41 | 0.000 |
| P9-probe-S | probe-go → probe-go2 | write | 200 | 2.30 | 5.08 | 200 | — | 1.05 / 0.47 | 0.000 |
| P9-probe-S | probe-go2 → probe-py | echo-1k-grpc | 200 | 0.81 | 1.66 | 200 | — | 0.51 / 0.99 | 0.000 |
| P9-probe-S | probe-go2 → probe-py | echo-1k-http | 200 | 0.76 | 1.09 | 200 | — | 0.42 / 0.74 | 0.000 |
| P9-probe-S | probe-go2 → probe-py | relay | 200 | 7.08 | 16.24 | 200 | — | 1.21 / 2.95 | 0.000 |
| P9-probe-S | probe-go2 → probe-py | write | 200 | 2.55 | 5.03 | 200 | — | 1.07 / 1.04 | 0.000 |
| P9-probe-S | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.41 | 2.32 | 200 | — | 1.45 / 1.01 | 0.000 |
| P9-probe-S | probe-py → probe-py2 | echo-1k-http | 200 | 1.01 | 1.47 | 200 | — | 1.12 / 0.71 | 0.000 |
| P9-probe-S | probe-py → probe-py2 | relay | 200 | 8.73 | 23.64 | 200 | — | 3.17 / 3.02 | 0.000 |
| P9-probe-S | probe-py → probe-py2 | write | 200 | 4.71 | 17.16 | 200 | — | 3.12 / 1.10 | 0.000 |
| P9-probe-S | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.78 | 1.18 | 200 | — | 1.36 / 0.38 | 0.000 |
| P9-probe-S | probe-py2 → probe-go | echo-1k-http | 200 | 0.58 | 0.81 | 200 | — | 1.11 / 0.27 | 0.000 |
| P9-probe-S | probe-py2 → probe-go | relay | 200 | 7.28 | 25.12 | 200 | — | 3.12 / 1.49 | 0.000 |
| P9-probe-S | probe-py2 → probe-go | write | 200 | 6.22 | 22.67 | 200 | — | 3.03 / 0.54 | 0.000 |
