| cell | segment | part | cores | MiB | anon MiB | CPU s per 1000 requests |
| --- | --- | --- | --- | --- | --- | --- |
| P9-S | empty idle | base | 0.097 | 1494 | 424 |  |
| P9-S | empty idle | components | 0.092 | 265 | 224 |  |
| P9-S | empty idle | platform | 0.034 | 121 | — |  |
| P9-S | empty idle | docker | 0.059 | 487 | — |  |
| P9-S | seeded idle | base | 0.139 | 3705 | 696 |  |
| P9-S | seeded idle | components | 0.104 | 401 | 379 |  |
| P9-S | seeded idle | platform | 0.040 | 136 | — |  |
| P9-S | seeded idle | docker | 0.058 | 481 | — |  |
| P9-S | mix | base | 0.256 | 3745 | 705 | 36.6 |
| P9-S | mix | components | 0.202 | 405 | 383 | 28.8 |
| P9-S | mix | platform | 0.092 | 136 | — | 13.1 |
| P9-S | mix | docker | 0.059 | 484 | — | 8.4 |
| P9-S-root | empty idle | base | 0.098 | 1397 | 410 |  |
| P9-S-root | empty idle | components | 0.094 | 266 | 225 |  |
| P9-S-root | empty idle | platform | 0.018 | 88 | — |  |
| P9-S-root | empty idle | docker | 0.059 | 489 | — |  |
| P9-S-root | seeded idle | base | 0.139 | 3519 | 687 |  |
| P9-S-root | seeded idle | components | 0.103 | 444 | 372 |  |
| P9-S-root | seeded idle | platform | 0.018 | 85 | — |  |
| P9-S-root | seeded idle | docker | 0.058 | 451 | — |  |
| P9-S-root | mix | base | 0.263 | 3867 | 700 | 37.6 |
| P9-S-root | mix | components | 0.210 | 501 | 377 | 30.0 |
| P9-S-root | mix | platform | 0.020 | 85 | — | 2.9 |
| P9-S-root | mix | docker | 0.059 | 458 | — | 8.4 |
| P9-H | empty idle | base | 0.104 | 1867 | 471 |  |
| P9-H | empty idle | components | 0.057 | 154 | 123 |  |
| P9-H | empty idle | platform | 0.030 | 47 | — |  |
| P9-H | empty idle | docker | 0.059 | 468 | — |  |
| P9-H | seeded idle | base | 0.136 | 3841 | 890 |  |
| P9-H | seeded idle | components | 0.068 | 258 | 244 |  |
| P9-H | seeded idle | platform | 0.038 | 56 | — |  |
| P9-H | seeded idle | docker | 0.058 | 458 | — |  |
| P9-H | mix | base | 0.249 | 4088 | 951 | 35.5 |
| P9-H | mix | components | 0.153 | 260 | 246 | 21.8 |
| P9-H | mix | platform | 0.091 | 56 | — | 12.9 |
| P9-H | mix | docker | 0.059 | 458 | — | 8.5 |
| P9-H-root | empty idle | base | 0.103 | 1804 | 481 |  |
| P9-H-root | empty idle | components | 0.059 | 156 | 123 |  |
| P9-H-root | empty idle | platform | 0.015 | 66 | — |  |
| P9-H-root | empty idle | docker | 0.058 | 475 | — |  |
| P9-H-root | seeded idle | base | 0.136 | 2955 | 881 |  |
| P9-H-root | seeded idle | components | 0.070 | 314 | 245 |  |
| P9-H-root | seeded idle | platform | 0.015 | 65 | — |  |
| P9-H-root | seeded idle | docker | 0.059 | 457 | — |  |
| P9-H-root | mix | base | 0.261 | 3403 | 921 | 37.2 |
| P9-H-root | mix | components | 0.160 | 315 | 244 | 22.8 |
| P9-H-root | mix | platform | 0.017 | 64 | — | 2.4 |
| P9-H-root | mix | docker | 0.059 | 460 | — | 8.5 |

| cell | sent / ok | p50 | p95 | p99 | max | list p95 | order p95 | confirm p95 | deliver p95 | bill p95 | issue to completed p50 / p95 / max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| P9-S | 6300 / 6300 | 23.3 | 54.5 | 65.8 | 130.6 | 10.2 | 32.0 | 35.4 | 36.9 | 67.1 | 3.4 / 4.7 / 7.3 |
| P9-S-root | 6300 / 6300 | 21.9 | 51.5 | 63.2 | 130.5 | 11.1 | 30.6 | 32.6 | 35.4 | 65.9 | 3.4 / 4.5 / 16.1 |
| P9-H | 6300 / 6300 | 23.2 | 52.1 | 65.3 | 136.9 | 10.7 | 31.8 | 35.2 | 35.7 | 68.3 | 3.6 / 4.7 / 13.1 |
| P9-H-root | 6300 / 6300 | 21.8 | 50.1 | 61.2 | 129.0 | 11.0 | 30.0 | 32.5 | 34.5 | 63.4 | 3.4 / 4.2 / 5.3 |
