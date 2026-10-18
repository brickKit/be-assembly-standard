| 格 | 进程 | 常驻内存 MiB | cgroup 内存 MiB | 空闲 CPU 核 |
| --- | --- | --- | --- | --- |
| D-base-go | `brickkit-d-base-go-test-probe-go-3-2-7-1` | 29.3 | 9.9 | 0.012 |
| D-base-goshell-1 | `brickkit-d-base-goshell-1-be-go-core-3-0-7-1` | 29.5 | 35.0 | 0.012 |
| D-base-goshell-2 | `brickkit-d-base-goshell-2-be-go-core-3-0-7-1` | 31.3 | 12.1 | 0.022 |
| D-base-goshell-4 | `brickkit-d-base-goshell-4-be-go-core-3-0-7-1` | 32.9 | 13.7 | 0.040 |
| D-base-py | `brickkit-d-base-py-test-probe-py-3-2-6-1` | 100.7 | 97.6 | 0.017 |
| D-base-pyshell-1 | `brickkit-d-base-pyshell-1-be-py-render-3-0-7-1` | 102.0 | 129.9 | 0.021 |
| D-base-pyshell-2 | `brickkit-d-base-pyshell-2-be-py-render-3-0-7-1` | 102.9 | 99.7 | 0.031 |

| 外壳 | 承载 | 常驻内存 MiB | 比上一档每多一个成员 MiB |
| --- | --- | --- | --- |
| goshell | 1 | 29.5 | — |
| goshell | 2 | 31.3 | 1.8 |
| goshell | 4 | 32.9 | 0.8 |
| pyshell | 1 | 102.0 | — |
| pyshell | 2 | 102.9 | 0.9 |

| 格 | 组件 MiB / 核 | 基础资源 MiB / 核 | 平台 MiB / 核 | 数据库连接（峰值） |
| --- | --- | --- | --- | --- |
| D-H1 | 133 / 0.059 | 4675 / 0.168 | 514 / 0.063 | 13 |
| D-S | 262 / 0.075 | 1812 / 0.092 | 537 / 0.081 | 14 |
| D-base-go | 29 / 0.012 | 2548 / 0.043 | 430 / 0.057 | 5 |
| D-base-goshell-1 | 30 / 0.012 | 3099 / 0.697 | 454 / 0.062 | 5 |
| D-base-goshell-2 | 31 / 0.022 | 3120 / 0.112 | 469 / 0.056 | 8 |
| D-base-goshell-4 | 33 / 0.040 | 3539 / 0.174 | 515 / 0.058 | 12 |
| D-base-py | 101 / 0.017 | 3079 / 0.115 | 441 / 0.057 | 3 |
| D-base-pyshell-1 | 102 / 0.021 | 3502 / 0.116 | 480 / 0.059 | 3 |
| D-base-pyshell-2 | 103 / 0.031 | 1783 / 0.131 | 493 / 0.061 | 5 |

| 格 | 路径 | 操作 | 负载 | p50 ms | p99 ms | 吞吐 /s | 持续速率 /s | 每千次 CPU 秒（调用方 / 被调方） | 错误率 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D-H1 | probe-go → probe-go2 | big-event | 200 | 21.72 | 46.03 | 200 | — | 4.59 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | big-event | 50 | 9.00 | 11.63 | 50 | — | 5.48 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.29 | 0.56 | 200 | — | 0.87 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | echo-1k-grpc | 50 | 0.41 | 0.75 | 50 | — | 1.40 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | echo-1k-http | 200 | 0.24 | 0.47 | 200 | — | 0.65 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | echo-1k-http | 50 | 0.32 | 0.59 | 50 | — | 1.14 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | echo-60k-grpc | 200 | 0.83 | 1.43 | 200 | — | 1.88 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | echo-60k-grpc | 50 | 0.90 | 1.50 | 50 | — | 2.20 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | echo-60k-http | 200 | 0.75 | 1.49 | 200 | — | 2.32 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | echo-60k-http | 50 | 0.86 | 1.74 | 50 | — | 2.88 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | relay | 200 | 62.35 | 490.54 | 200 | — | 2.97 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | relay | 50 | 251.40 | 499.66 | 50 | — | 3.62 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | work-grpc | 200 | 10.33 | 10.61 | 200 | — | 10.85 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | work-grpc | 50 | 10.44 | 10.72 | 50 | — | 11.50 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | work-http | 200 | 10.27 | 10.53 | 200 | — | 10.59 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | work-http | 50 | 10.36 | 10.63 | 50 | — | 11.20 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | write | 200 | 2.88 | 5.05 | 200 | — | 1.95 / 同一进程 | 0.000 |
| D-H1 | probe-go → probe-go2 | write | 50 | 3.51 | 5.58 | 50 | — | 2.58 / 同一进程 | 0.000 |
| D-H1 | probe-go2 → probe-py | big-event | 200 | 40.25 | 107.09 | 200 | — | 3.16 / 3.15 | 0.000 |
| D-H1 | probe-go2 → probe-py | big-event | 50 | 9.75 | 12.96 | 50 | — | 3.80 / 3.42 | 0.000 |
| D-H1 | probe-go2 → probe-py | echo-1k-grpc | 200 | 1.01 | 2.17 | 200 | — | 0.71 / 1.27 | 0.000 |
| D-H1 | probe-go2 → probe-py | echo-1k-grpc | 50 | 1.50 | 2.41 | 50 | — | 1.20 / 2.18 | 0.000 |
| D-H1 | probe-go2 → probe-py | echo-1k-http | 200 | 0.95 | 1.52 | 200 | — | 0.61 / 1.01 | 0.000 |
| D-H1 | probe-go2 → probe-py | echo-1k-http | 50 | 1.13 | 1.65 | 50 | — | 1.00 / 1.64 | 0.000 |
| D-H1 | probe-go2 → probe-py | echo-60k-grpc | 200 | 1.66 | 3.02 | 200 | — | 1.19 / 1.88 | 0.000 |
| D-H1 | probe-go2 → probe-py | echo-60k-grpc | 50 | 2.26 | 3.29 | 50 | — | 1.68 / 2.92 | 0.000 |
| D-H1 | probe-go2 → probe-py | echo-60k-http | 200 | 1.72 | 2.58 | 200 | — | 1.25 / 1.55 | 0.000 |
| D-H1 | probe-go2 → probe-py | echo-60k-http | 50 | 1.86 | 2.76 | 50 | — | 1.68 / 2.10 | 0.000 |
| D-H1 | probe-go2 → probe-py | relay | 200 | 247.04 | 504.66 | 200 | — | 1.61 / 3.69 | 0.000 |
| D-H1 | probe-go2 → probe-py | relay | 50 | 262.45 | 508.66 | 50 | — | 2.06 / 4.52 | 0.000 |
| D-H1 | probe-go2 → probe-py | work-grpc | 200 | 713.00 | 719.96 | 83 | — | 0.57 / 5.51 | 0.552 |
| D-H1 | probe-go2 → probe-py | work-grpc | 50 | 11.66 | 12.78 | 50 | — | 1.26 / 12.24 | 0.000 |
| D-H1 | probe-go2 → probe-py | work-http | 200 | 675.69 | 680.91 | 88 | — | 0.50 / 5.31 | 0.528 |
| D-H1 | probe-go2 → probe-py | work-http | 50 | 11.18 | 11.68 | 50 | — | 1.04 / 11.42 | 0.000 |
| D-H1 | probe-go2 → probe-py | write | 200 | 3.08 | 4.71 | 200 | — | 1.47 / 1.70 | 0.000 |
| D-H1 | probe-go2 → probe-py | write | 50 | 3.83 | 5.99 | 50 | — | 2.02 / 2.18 | 0.000 |
| D-H1 | probe-py → probe-py2 | big-event | 200 | 2865.99 | 3805.08 | 200 | — | 4.76 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | big-event | 50 | 11.59 | 16.24 | 50 | — | 8.70 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.62 | 3.59 | 200 | — | 2.73 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | echo-1k-grpc | 50 | 1.99 | 3.71 | 50 | — | 3.70 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | echo-1k-http | 200 | 1.09 | 1.88 | 200 | — | 1.91 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | echo-1k-http | 50 | 1.18 | 1.94 | 50 | — | 2.68 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | echo-60k-grpc | 200 | 2.20 | 4.47 | 200 | — | 3.42 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | echo-60k-grpc | 50 | 2.71 | 4.21 | 50 | — | 4.50 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | echo-60k-http | 200 | 1.80 | 3.10 | 200 | — | 2.67 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | echo-60k-http | 50 | 1.84 | 3.28 | 50 | — | 3.42 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | relay | 200 | 76.57 | 538.43 | 200 | — | 4.49 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | relay | 50 | 258.70 | 509.86 | 50 | — | 5.98 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | work-grpc | 200 | 853.83 | 874.98 | 69 | — | 5.55 / 同一进程 | 0.625 |
| D-H1 | probe-py → probe-py2 | work-grpc | 50 | 12.11 | 13.05 | 50 | — | 13.64 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | work-http | 200 | 772.81 | 784.65 | 73 | — | 5.36 / 同一进程 | 0.588 |
| D-H1 | probe-py → probe-py2 | work-http | 50 | 11.18 | 12.07 | 50 | — | 12.48 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | write | 200 | 8.33 | 35.40 | 200 | — | 3.94 / 同一进程 | 0.000 |
| D-H1 | probe-py → probe-py2 | write | 50 | 5.27 | 9.56 | 50 | — | 5.56 / 同一进程 | 0.000 |
| D-H1 | probe-py2 → probe-go | big-event | 200 | 51.01 | 125.88 | 200 | — | 4.25 / 1.69 | 0.000 |
| D-H1 | probe-py2 → probe-go | big-event | 50 | 11.30 | 15.92 | 50 | — | 7.06 / 2.10 | 0.000 |
| D-H1 | probe-py2 → probe-go | echo-1k-grpc | 200 | 1.01 | 1.87 | 200 | — | 1.96 / 0.55 | 0.000 |
| D-H1 | probe-py2 → probe-go | echo-1k-grpc | 50 | 1.18 | 1.86 | 50 | — | 2.84 / 0.94 | 0.000 |
| D-H1 | probe-py2 → probe-go | echo-1k-http | 200 | 0.73 | 1.19 | 200 | — | 1.62 / 0.41 | 0.000 |
| D-H1 | probe-py2 → probe-go | echo-1k-http | 50 | 0.86 | 1.31 | 50 | — | 2.36 / 0.78 | 0.000 |
| D-H1 | probe-py2 → probe-go | echo-60k-grpc | 200 | 1.66 | 2.65 | 200 | — | 2.47 / 0.92 | 0.000 |
| D-H1 | probe-py2 → probe-go | echo-60k-grpc | 50 | 1.87 | 2.77 | 50 | — | 3.38 / 1.32 | 0.000 |
| D-H1 | probe-py2 → probe-go | echo-60k-http | 200 | 1.47 | 2.22 | 200 | — | 2.10 / 0.89 | 0.000 |
| D-H1 | probe-py2 → probe-go | echo-60k-http | 50 | 1.54 | 2.36 | 50 | — | 2.80 / 1.24 | 0.000 |
| D-H1 | probe-py2 → probe-go | relay | 200 | 272.04 | 517.21 | 200 | — | 3.64 / 1.88 | 0.000 |
| D-H1 | probe-py2 → probe-go | relay | 50 | 250.82 | 498.81 | 50 | — | 5.04 / 2.32 | 0.000 |
| D-H1 | probe-py2 → probe-go | work-grpc | 200 | 11.12 | 12.04 | 200 | — | 1.97 / 10.47 | 0.000 |
| D-H1 | probe-py2 → probe-go | work-grpc | 50 | 11.24 | 11.69 | 50 | — | 2.72 / 10.96 | 0.000 |
| D-H1 | probe-py2 → probe-go | work-http | 200 | 10.80 | 11.63 | 200 | — | 1.60 / 10.33 | 0.000 |
| D-H1 | probe-py2 → probe-go | work-http | 50 | 10.86 | 11.27 | 50 | — | 2.18 / 10.86 | 0.000 |
| D-H1 | probe-py2 → probe-go | write | 200 | 16.77 | 48.30 | 200 | — | 3.98 / 0.84 | 0.000 |
| D-H1 | probe-py2 → probe-go | write | 50 | 5.35 | 8.48 | 50 | — | 5.04 / 1.22 | 0.000 |
| D-S | probe-go → probe-go2 | big-event | 200 | 22.68 | 45.27 | 200 | — | 3.05 / 1.91 | 0.000 |
| D-S | probe-go → probe-go2 | big-event | 50 | 8.91 | 11.70 | 50 | — | 3.70 / 2.08 | 0.000 |
| D-S | probe-go → probe-go2 | echo-1k-grpc | 200 | 0.37 | 0.66 | 200 | — | 0.64 / 0.48 | 0.000 |
| D-S | probe-go → probe-go2 | echo-1k-grpc | 50 | 0.53 | 0.79 | 50 | — | 1.00 / 0.82 | 0.000 |
| D-S | probe-go → probe-go2 | echo-1k-http | 200 | 0.32 | 0.54 | 200 | — | 0.51 / 0.33 | 0.000 |
| D-S | probe-go → probe-go2 | echo-1k-http | 50 | 0.44 | 0.71 | 50 | — | 0.84 / 0.58 | 0.000 |
| D-S | probe-go → probe-go2 | echo-60k-grpc | 200 | 0.86 | 1.40 | 200 | — | 1.15 / 0.92 | 0.000 |
| D-S | probe-go → probe-go2 | echo-60k-grpc | 50 | 1.07 | 1.62 | 50 | — | 1.50 / 1.22 | 0.000 |
| D-S | probe-go → probe-go2 | echo-60k-http | 200 | 0.87 | 1.79 | 200 | — | 1.50 / 1.07 | 0.000 |
| D-S | probe-go → probe-go2 | echo-60k-http | 50 | 0.95 | 1.76 | 50 | — | 1.78 / 1.32 | 0.000 |
| D-S | probe-go → probe-go2 | relay | 200 | 246.00 | 497.18 | 200 | — | 1.60 / 1.71 | 0.000 |
| D-S | probe-go → probe-go2 | relay | 50 | 253.79 | 500.32 | 50 | — | 2.00 / 1.94 | 0.000 |
| D-S | probe-go → probe-go2 | work-grpc | 200 | 10.42 | 10.69 | 200 | — | 0.68 / 10.42 | 0.000 |
| D-S | probe-go → probe-go2 | work-grpc | 50 | 10.56 | 10.85 | 50 | — | 1.06 / 10.90 | 0.000 |
| D-S | probe-go → probe-go2 | work-http | 200 | 10.34 | 10.57 | 200 | — | 0.53 / 10.25 | 0.000 |
| D-S | probe-go → probe-go2 | work-http | 50 | 10.46 | 10.65 | 50 | — | 0.82 / 10.60 | 0.000 |
| D-S | probe-go → probe-go2 | write | 200 | 3.19 | 6.18 | 200 | — | 1.52 / 0.70 | 0.000 |
| D-S | probe-go → probe-go2 | write | 50 | 3.54 | 5.44 | 50 | — | 1.98 / 0.96 | 0.000 |
| D-S | probe-go2 → probe-py | big-event | 200 | 28.17 | 54.35 | 200 | — | 3.16 / 2.94 | 0.000 |
| D-S | probe-go2 → probe-py | big-event | 50 | 9.81 | 12.41 | 50 | — | 3.74 / 3.12 | 0.000 |
| D-S | probe-go2 → probe-py | echo-1k-grpc | 200 | 1.02 | 2.02 | 200 | — | 0.69 / 1.21 | 0.000 |
| D-S | probe-go2 → probe-py | echo-1k-grpc | 50 | 1.65 | 2.34 | 50 | — | 1.12 / 2.22 | 0.000 |
| D-S | probe-go2 → probe-py | echo-1k-http | 200 | 0.94 | 1.44 | 200 | — | 0.55 / 0.96 | 0.000 |
| D-S | probe-go2 → probe-py | echo-1k-http | 50 | 1.16 | 1.62 | 50 | — | 0.84 / 1.42 | 0.000 |
| D-S | probe-go2 → probe-py | echo-60k-grpc | 200 | 1.73 | 2.87 | 200 | — | 1.16 / 1.88 | 0.000 |
| D-S | probe-go2 → probe-py | echo-60k-grpc | 50 | 2.18 | 2.98 | 50 | — | 1.50 / 2.60 | 0.000 |
| D-S | probe-go2 → probe-py | echo-60k-http | 200 | 1.80 | 2.70 | 200 | — | 1.42 / 1.54 | 0.000 |
| D-S | probe-go2 → probe-py | echo-60k-http | 50 | 1.89 | 2.76 | 50 | — | 1.70 / 1.88 | 0.000 |
| D-S | probe-go2 → probe-py | relay | 200 | 240.91 | 503.32 | 200 | — | 1.63 / 3.19 | 0.000 |
| D-S | probe-go2 → probe-py | relay | 50 | 258.72 | 507.53 | 50 | — | 1.92 / 3.82 | 0.000 |
| D-S | probe-go2 → probe-py | work-grpc | 200 | 706.12 | 713.97 | 84 | — | 0.52 / 5.50 | 0.548 |
| D-S | probe-go2 → probe-py | work-grpc | 50 | 11.60 | 12.28 | 50 | — | 1.06 / 11.94 | 0.000 |
| D-S | probe-go2 → probe-py | work-http | 200 | 677.58 | 684.02 | 88 | — | 0.46 / 5.30 | 0.530 |
| D-S | probe-go2 → probe-py | work-http | 50 | 11.22 | 11.66 | 50 | — | 0.84 / 11.22 | 0.000 |
| D-S | probe-go2 → probe-py | write | 200 | 3.46 | 7.26 | 200 | — | 1.55 / 1.80 | 0.000 |
| D-S | probe-go2 → probe-py | write | 50 | 3.80 | 5.51 | 50 | — | 1.84 / 2.04 | 0.000 |
| D-S | probe-py → probe-py2 | big-event | 200 | 58.73 | 111.88 | 200 | — | 4.21 / 2.91 | 0.000 |
| D-S | probe-py → probe-py2 | big-event | 50 | 11.92 | 16.69 | 50 | — | 6.58 / 3.20 | 0.000 |
| D-S | probe-py → probe-py2 | echo-1k-grpc | 200 | 1.64 | 2.69 | 200 | — | 1.81 / 1.21 | 0.000 |
| D-S | probe-py → probe-py2 | echo-1k-grpc | 50 | 2.17 | 3.03 | 50 | — | 2.52 / 1.88 | 0.000 |
| D-S | probe-py → probe-py2 | echo-1k-http | 200 | 1.29 | 2.00 | 200 | — | 1.49 / 0.92 | 0.000 |
| D-S | probe-py → probe-py2 | echo-1k-http | 50 | 1.46 | 2.08 | 50 | — | 1.94 / 1.34 | 0.000 |
| D-S | probe-py → probe-py2 | echo-60k-grpc | 200 | 2.30 | 3.65 | 200 | — | 2.25 / 1.54 | 0.000 |
| D-S | probe-py → probe-py2 | echo-60k-grpc | 50 | 2.87 | 3.95 | 50 | — | 2.84 / 2.38 | 0.000 |
| D-S | probe-py → probe-py2 | echo-60k-http | 200 | 2.27 | 3.32 | 200 | — | 1.96 / 1.41 | 0.000 |
| D-S | probe-py → probe-py2 | echo-60k-http | 50 | 2.26 | 3.22 | 50 | — | 2.34 / 1.72 | 0.000 |
| D-S | probe-py → probe-py2 | relay | 200 | 256.31 | 514.89 | 200 | — | 3.73 / 2.98 | 0.000 |
| D-S | probe-py → probe-py2 | relay | 50 | 262.18 | 507.19 | 50 | — | 5.12 / 3.74 | 0.000 |
| D-S | probe-py → probe-py2 | work-grpc | 200 | 706.40 | 712.33 | 84 | — | 1.73 / 5.44 | 0.548 |
| D-S | probe-py → probe-py2 | work-grpc | 50 | 12.37 | 13.10 | 50 | — | 2.50 / 11.84 | 0.000 |
| D-S | probe-py → probe-py2 | work-http | 200 | 680.01 | 684.95 | 88 | — | 1.47 / 5.30 | 0.531 |
| D-S | probe-py → probe-py2 | work-http | 50 | 11.62 | 12.23 | 50 | — | 2.04 / 11.30 | 0.000 |
| D-S | probe-py → probe-py2 | write | 200 | 8.07 | 25.91 | 200 | — | 3.75 / 1.88 | 0.000 |
| D-S | probe-py → probe-py2 | write | 50 | 5.40 | 9.15 | 50 | — | 4.54 / 2.24 | 0.000 |
| D-S | probe-py2 → probe-go | big-event | 200 | 52.10 | 108.09 | 200 | — | 4.19 / 1.72 | 0.000 |
| D-S | probe-py2 → probe-go | big-event | 50 | 11.32 | 16.31 | 50 | — | 6.76 / 2.00 | 0.000 |
| D-S | probe-py2 → probe-go | echo-1k-grpc | 200 | 0.94 | 1.50 | 200 | — | 1.78 / 0.48 | 0.000 |
| D-S | probe-py2 → probe-go | echo-1k-grpc | 50 | 1.15 | 1.79 | 50 | — | 2.50 / 0.72 | 0.000 |
| D-S | probe-py2 → probe-go | echo-1k-http | 200 | 0.70 | 1.09 | 200 | — | 1.50 / 0.35 | 0.000 |
| D-S | probe-py2 → probe-go | echo-1k-http | 50 | 0.82 | 1.17 | 50 | — | 1.94 / 0.58 | 0.000 |
| D-S | probe-py2 → probe-go | echo-60k-grpc | 200 | 1.67 | 2.48 | 200 | — | 2.44 / 0.87 | 0.000 |
| D-S | probe-py2 → probe-go | echo-60k-grpc | 50 | 1.84 | 2.57 | 50 | — | 3.00 / 1.08 | 0.000 |
| D-S | probe-py2 → probe-go | echo-60k-http | 200 | 1.48 | 2.22 | 200 | — | 2.04 / 0.90 | 0.000 |
| D-S | probe-py2 → probe-go | echo-60k-http | 50 | 1.50 | 2.46 | 50 | — | 2.46 / 1.14 | 0.000 |
| D-S | probe-py2 → probe-go | relay | 200 | 265.11 | 513.94 | 200 | — | 3.74 / 1.66 | 0.000 |
| D-S | probe-py2 → probe-go | relay | 50 | 256.65 | 505.79 | 50 | — | 4.98 / 1.92 | 0.000 |
| D-S | probe-py2 → probe-go | work-grpc | 200 | 11.13 | 11.87 | 200 | — | 1.94 / 10.42 | 0.000 |
| D-S | probe-py2 → probe-go | work-grpc | 50 | 11.24 | 11.64 | 50 | — | 2.50 / 10.78 | 0.000 |
| D-S | probe-py2 → probe-go | work-http | 200 | 10.84 | 11.87 | 200 | — | 1.62 / 10.30 | 0.000 |
| D-S | probe-py2 → probe-go | work-http | 50 | 10.85 | 11.17 | 50 | — | 1.90 / 10.62 | 0.000 |
| D-S | probe-py2 → probe-go | write | 200 | 9.66 | 29.98 | 200 | — | 3.72 / 0.74 | 0.000 |
| D-S | probe-py2 → probe-go | write | 50 | 5.26 | 7.95 | 50 | — | 4.76 / 1.00 | 0.000 |

