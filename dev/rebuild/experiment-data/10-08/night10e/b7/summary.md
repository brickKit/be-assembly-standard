| cell | segment | part | cores | MiB | anon MiB | CPU s per 1000 requests |
| --- | --- | --- | --- | --- | --- | --- |
| K9-X | empty idle | base | 0.103 | 1170 | 455 |  |
| K9-X | empty idle | components | 0.061 | 187 | 157 |  |
| K9-X | empty idle | platform | 0.094 | 2874 | 657 |  |
| K9-X | empty idle | docker | 0.059 | 767 | — |  |
| K9-X | seeded idle | base | 0.138 | 3975 | 717 |  |
| K9-X | seeded idle | components | 0.071 | 312 | 293 |  |
| K9-X | seeded idle | platform | 0.093 | 1811 | 685 |  |
| K9-X | seeded idle | docker | 0.059 | 749 | — |  |
| K9-X | mix | base | 0.280 | 3664 | 729 | 40.0 |
| K9-X | mix | components | 0.178 | 319 | 294 | 25.4 |
| K9-X | mix | platform | 0.097 | 1744 | 684 | 13.9 |
| K9-X | mix | docker | 0.061 | 765 | — | 8.8 |
| K9-X-cb | empty idle | base | 0.076 | 1357 | 373 |  |
| K9-X-cb | empty idle | components | 0.059 | 183 | 155 |  |
| K9-X-cb | empty idle | platform | 0.103 | 3238 | 732 |  |
| K9-X-cb | empty idle | docker | 0.034 | 690 | — |  |
| K9-X-cb | seeded idle | base | 0.110 | 3812 | 698 |  |
| K9-X-cb | seeded idle | components | 0.069 | 306 | 289 |  |
| K9-X-cb | seeded idle | platform | 0.103 | 2488 | 761 |  |
| K9-X-cb | seeded idle | docker | 0.034 | 660 | — |  |
| K9-X-cb | mix | base | 0.245 | 3795 | 719 | 35.0 |
| K9-X-cb | mix | components | 0.172 | 312 | 292 | 24.5 |
| K9-X-cb | mix | platform | 0.109 | 2444 | 752 | 15.6 |
| K9-X-cb | mix | docker | 0.036 | 669 | — | 5.1 |

| cell | sent / ok | p50 | p95 | p99 | max | list p95 | order p95 | confirm p95 | deliver p95 | bill p95 | issue to completed p50 / p95 / max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| K9-X | 6300 / 6300 | 22.9 | 51.9 | 62.7 | 140.5 | 11.7 | 30.9 | 33.4 | 36.5 | 65.4 | 3.7 / 4.7 / 9.5 |
| K9-X-cb | 6300 / 6300 | 22.2 | 51.1 | 61.9 | 144.1 | 11.7 | 30.6 | 32.4 | 35.3 | 64.6 | 3.4 / 4.6 / 6.3 |
