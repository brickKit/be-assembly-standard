| cell | segment | part | cores | MiB | anon MiB | CPU s per 1000 requests |
| --- | --- | --- | --- | --- | --- | --- |
| P9-S | empty idle | base | 0.098 | 1937 | 402 |  |
| P9-S | empty idle | components | 0.093 | 321 | 225 |  |
| P9-S | empty idle | platform | 0.035 | 121 | — |  |
| P9-S | empty idle | docker | 0.059 | 243 | — |  |
| P9-S | seeded idle | base | 0.142 | 4303 | 667 |  |
| P9-S | seeded idle | components | 0.106 | 439 | 378 |  |
| P9-S | seeded idle | platform | 0.041 | 135 | — |  |
| P9-S | seeded idle | docker | 0.059 | 225 | — |  |
| P9-S | mix | base | 0.249 | 4248 | 673 | 35.6 |
| P9-S | mix | components | 0.206 | 458 | 380 | 29.5 |
| P9-S | mix | platform | 0.094 | 135 | — | 13.4 |
| P9-S | mix | docker | 0.059 | 225 | — | 8.5 |
| LP9-S | empty idle | base | 0.099 | 1782 | 398 |  |
| LP9-S | empty idle | components | 0.091 | 313 | 225 |  |
| LP9-S | empty idle | platform | 0.029 | 106 | — |  |
| LP9-S | empty idle | local | 0.000 | 87 | 44 |  |
| LP9-S | empty idle | docker | 0.065 | 241 | — |  |
| LP9-S | seeded idle | base | 0.141 | 3355 | 685 |  |
| LP9-S | seeded idle | components | 0.098 | 485 | 380 |  |
| LP9-S | seeded idle | platform | 0.034 | 115 | — |  |
| LP9-S | seeded idle | local | 0.000 | 87 | 44 |  |
| LP9-S | seeded idle | docker | 0.065 | 224 | — |  |
| LP9-S | mix | base | 0.274 | 3466 | 694 | 39.1 |
| LP9-S | mix | components | 0.206 | 502 | 381 | 29.5 |
| LP9-S | mix | platform | 0.058 | 115 | — | 8.3 |
| LP9-S | mix | local | 0.001 | 88 | 45 | 0.2 |
| LP9-S | mix | docker | 0.096 | 224 | — | 13.7 |
| LP9-H | empty idle | base | 0.103 | 1283 | 420 |  |
| LP9-H | empty idle | components | 0.055 | 235 | 120 |  |
| LP9-H | empty idle | platform | 0.019 | 39 | — |  |
| LP9-H | empty idle | local | 0.000 | 52 | 26 |  |
| LP9-H | empty idle | docker | 0.070 | 240 | — |  |
| LP9-H | seeded idle | base | 0.139 | 3343 | 886 |  |
| LP9-H | seeded idle | components | 0.069 | 319 | 244 |  |
| LP9-H | seeded idle | platform | 0.024 | 43 | — |  |
| LP9-H | seeded idle | local | 0.000 | 52 | 26 |  |
| LP9-H | seeded idle | docker | 0.071 | 224 | — |  |
| LP9-H | mix | base | 0.272 | 3791 | 935 | 38.9 |
| LP9-H | mix | components | 0.165 | 350 | 246 | 23.5 |
| LP9-H | mix | platform | 0.038 | 43 | — | 5.4 |
| LP9-H | mix | local | 0.001 | 53 | 27 | 0.2 |
| LP9-H | mix | docker | 0.107 | 224 | — | 15.2 |
| LP9-X | empty idle | base | 0.103 | 1854 | 467 |  |
| LP9-X | empty idle | components | 0.063 | 269 | 158 |  |
| LP9-X | empty idle | platform | 0.024 | 55 | — |  |
| LP9-X | empty idle | local | 0.000 | 89 | 46 |  |
| LP9-X | empty idle | docker | 0.065 | 239 | — |  |
| LP9-X | seeded idle | base | 0.138 | 4149 | 777 |  |
| LP9-X | seeded idle | components | 0.076 | 398 | 297 |  |
| LP9-X | seeded idle | platform | 0.032 | 62 | — |  |
| LP9-X | seeded idle | local | 0.000 | 88 | 45 |  |
| LP9-X | seeded idle | docker | 0.066 | 223 | — |  |
| LP9-X | mix | base | 0.274 | 4050 | 793 | 39.2 |
| LP9-X | mix | components | 0.180 | 415 | 298 | 25.7 |
| LP9-X | mix | platform | 0.055 | 62 | — | 7.8 |
| LP9-X | mix | local | 0.001 | 89 | 47 | 0.2 |
| LP9-X | mix | docker | 0.096 | 223 | — | 13.7 |

| cell | sent / ok | p50 | p95 | p99 | max | list p95 | order p95 | confirm p95 | deliver p95 | bill p95 | issue to completed p50 / p95 / max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| P9-S | 6300 / 6300 | 23.8 | 53.7 | 65.6 | 142.7 | 10.3 | 32.4 | 35.9 | 36.7 | 67.6 | 3.5 / 4.8 / 8.2 |
| LP9-S | 6300 / 6300 | 26.3 | 56.0 | 68.5 | 140.2 | 11.8 | 35.3 | 38.2 | 40.2 | 72.9 | 3.7 / 5.0 / 14.8 |
| LP9-H | 6300 / 6300 | 26.7 | 56.2 | 70.0 | 139.9 | 11.9 | 35.4 | 38.7 | 41.2 | 72.6 | 4.1 / 5.2 / 8.4 |
| LP9-X | 6300 / 6300 | 26.3 | 55.1 | 67.0 | 144.3 | 11.8 | 34.8 | 38.2 | 39.8 | 69.3 | 3.6 / 4.9 / 8.1 |
