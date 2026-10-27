| cell | segment | part | cores | MiB | anon MiB | CPU s per 1000 requests |
| --- | --- | --- | --- | --- | --- | --- |
| D9-S | empty idle | base | 0.191 | 1687 | 318 |  |
| D9-S | empty idle | components | 0.143 | 323 | 228 |  |
| D9-S | empty idle | platform | 0.098 | 728 | — |  |
| D9-S | seeded idle | base | 0.222 | 4931 | 650 |  |
| D9-S | seeded idle | components | 0.149 | 438 | 376 |  |
| D9-S | seeded idle | platform | 0.095 | 715 | — |  |
| D9-S | mix | base | 0.356 | 4834 | 664 | 50.8 |
| D9-S | mix | components | 0.251 | 456 | 376 | 35.9 |
| D9-S | mix | platform | 0.104 | 716 | — | 14.9 |
| K9-S | empty idle | base | 0.192 | 1885 | 412 |  |
| K9-S | empty idle | components | 0.121 | 266 | 231 |  |
| K9-S | empty idle | platform | 0.100 | 2935 | 712 |  |
| K9-S | empty idle | docker | 0.051 | 698 | — |  |
| K9-S | seeded idle | base | 0.224 | 4909 | 661 |  |
| K9-S | seeded idle | components | 0.129 | 390 | 350 |  |
| K9-S | seeded idle | platform | 0.099 | 1998 | 747 |  |
| K9-S | seeded idle | docker | 0.051 | 669 | — |  |
| K9-S | mix | base | 0.368 | 4792 | 669 | 52.6 |
| K9-S | mix | components | 0.240 | 415 | 354 | 34.3 |
| K9-S | mix | platform | 0.104 | 2017 | 745 | 14.8 |
| K9-S | mix | docker | 0.053 | 665 | — | 7.6 |
| K9-H | empty idle | base | 0.196 | 2111 | 462 |  |
| K9-H | empty idle | components | 0.095 | 149 | 122 |  |
| K9-H | empty idle | platform | 0.089 | 3144 | 668 |  |
| K9-H | empty idle | docker | 0.052 | 755 | — |  |
| K9-H | seeded idle | base | 0.235 | 4985 | 869 |  |
| K9-H | seeded idle | components | 0.105 | 250 | 237 |  |
| K9-H | seeded idle | platform | 0.088 | 2153 | 657 |  |
| K9-H | seeded idle | docker | 0.052 | 725 | — |  |
| K9-H | mix | base | 0.367 | 5017 | 901 | 52.5 |
| K9-H | mix | components | 0.205 | 259 | 245 | 29.4 |
| K9-H | mix | platform | 0.094 | 2137 | 651 | 13.5 |
| K9-H | mix | docker | 0.054 | 725 | — | 7.8 |
| K9-X | empty idle | base | 0.191 | 2562 | 487 |  |
| K9-X | empty idle | components | 0.104 | 189 | 161 |  |
| K9-X | empty idle | platform | 0.093 | 2754 | 685 |  |
| K9-X | empty idle | docker | 0.051 | 743 | — |  |
| K9-X | seeded idle | base | 0.255 | 4902 | 715 |  |
| K9-X | seeded idle | components | 0.116 | 306 | 288 |  |
| K9-X | seeded idle | platform | 0.092 | 1865 | 679 |  |
| K9-X | seeded idle | docker | 0.052 | 728 | — |  |
| K9-X | mix | base | 0.366 | 4778 | 721 | 52.4 |
| K9-X | mix | components | 0.220 | 312 | 291 | 31.5 |
| K9-X | mix | platform | 0.097 | 1761 | 679 | 13.9 |
| K9-X | mix | docker | 0.053 | 729 | — | 7.6 |

| cell | sent / ok | p50 | p95 | p99 | max | list p95 | order p95 | confirm p95 | deliver p95 | bill p95 | issue to completed p50 / p95 / max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D9-S | 6300 / 6300 | 22.1 | 50.0 | 61.2 | 138.2 | 11.2 | 30.8 | 32.9 | 35.4 | 64.5 | 3.4 / 4.5 / 8.0 |
| K9-S | 6300 / 6300 | 22.7 | 51.8 | 64.8 | 142.9 | 11.9 | 31.6 | 34.0 | 36.2 | 66.8 | 3.6 / 4.9 / 6.3 |
| K9-H | 6300 / 6300 | 23.2 | 53.2 | 65.1 | 141.1 | 11.7 | 32.4 | 35.9 | 37.7 | 68.5 | 3.8 / 5.0 / 7.0 |
| K9-X | 6300 / 6300 | 22.4 | 51.6 | 62.3 | 134.2 | 11.5 | 31.5 | 33.7 | 35.8 | 65.4 | 3.5 / 4.6 / 9.9 |
