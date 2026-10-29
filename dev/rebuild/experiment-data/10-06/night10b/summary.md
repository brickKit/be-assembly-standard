| cell | segment | part | cores | MiB | anon MiB | CPU s per 1000 requests |
| --- | --- | --- | --- | --- | --- | --- |
| D9-S | empty idle | base | 0.101 | 1165 | 418 |  |
| D9-S | empty idle | components | 0.094 | 266 | 224 |  |
| D9-S | empty idle | platform | 0.104 | 786 | — |  |
| D9-S | seeded idle | base | 0.138 | 4589 | 685 |  |
| D9-S | seeded idle | components | 0.103 | 405 | 374 |  |
| D9-S | seeded idle | platform | 0.105 | 776 | — |  |
| D9-S | mix | base | 0.259 | 4603 | 697 | 37.1 |
| D9-S | mix | components | 0.208 | 414 | 383 | 29.7 |
| D9-S | mix | platform | 0.113 | 775 | — | 16.1 |
| D9-S | mix 2 | base | 0.393 | 4772 | 631 | 28.1 |
| D9-S | mix 2 | components | 0.314 | 403 | 372 | 22.4 |
| D9-S | mix 2 | platform | 0.123 | 783 | — | 8.8 |
| D9-X | empty idle | base | 0.110 | 2030 | 403 |  |
| D9-X | empty idle | components | 0.071 | 183 | 153 |  |
| D9-X | empty idle | platform | 0.082 | 731 | — |  |
| D9-X | seeded idle | base | 0.134 | 4684 | 724 |  |
| D9-X | seeded idle | components | 0.084 | 312 | 288 |  |
| D9-X | seeded idle | platform | 0.082 | 735 | — |  |
| D9-X | mix | base | 0.266 | 4704 | 739 | 38.1 |
| D9-X | mix | components | 0.185 | 316 | 291 | 26.4 |
| D9-X | mix | platform | 0.090 | 732 | — | 12.9 |
| D9-X | mix 2 | base | 0.397 | 4755 | 707 | 28.4 |
| D9-X | mix 2 | components | 0.282 | 305 | 280 | 20.2 |
| D9-X | mix 2 | platform | 0.098 | 730 | — | 7.0 |
| D9-S-x2 | empty idle | base | 0.100 | 2046 | 407 |  |
| D9-S-x2 | empty idle | components | 0.093 | 277 | 225 |  |
| D9-S-x2 | empty idle | platform | 0.104 | 784 | — |  |
| D9-S-x2 | seeded idle | base | 0.165 | 5646 | 683 |  |
| D9-S-x2 | seeded idle | components | 0.105 | 409 | 376 |  |
| D9-S-x2 | seeded idle | platform | 0.104 | 774 | — |  |
| D9-S-x2 | mix | base | 0.298 | 4438 | 694 | 42.5 |
| D9-S-x2 | mix | components | 0.208 | 411 | 378 | 29.8 |
| D9-S-x2 | mix | platform | 0.113 | 771 | — | 16.2 |
| D9-S-x2 | mix 2 | base | 0.431 | 5157 | 644 | 30.8 |
| D9-S-x2 | mix 2 | components | 0.314 | 399 | 366 | 22.4 |
| D9-S-x2 | mix 2 | platform | 0.121 | 770 | — | 8.7 |
| D9-X-x2 | empty idle | base | 0.101 | 1903 | 440 |  |
| D9-X-x2 | empty idle | components | 0.074 | 184 | 154 |  |
| D9-X-x2 | empty idle | platform | 0.082 | 719 | — |  |
| D9-X-x2 | seeded idle | base | 0.174 | 5634 | 704 |  |
| D9-X-x2 | seeded idle | components | 0.086 | 352 | 287 |  |
| D9-X-x2 | seeded idle | platform | 0.082 | 716 | — |  |
| D9-X-x2 | mix | base | 0.293 | 5600 | 714 | 41.9 |
| D9-X-x2 | mix | components | 0.185 | 355 | 289 | 26.5 |
| D9-X-x2 | mix | platform | 0.091 | 713 | — | 13.0 |
| D9-X-x2 | mix 2 | base | 0.430 | 5545 | 654 | 30.7 |
| D9-X-x2 | mix 2 | components | 0.288 | 343 | 277 | 20.6 |
| D9-X-x2 | mix 2 | platform | 0.099 | 713 | — | 7.1 |

| cell | sent / ok | p50 | p95 | p99 | max | list p95 | order p95 | confirm p95 | deliver p95 | bill p95 | issue to completed p50 / p95 / max |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D9-S | 6300 / 6300 | 22.9 | 51.4 | 62.0 | 138.5 | 11.5 | 30.9 | 33.1 | 35.7 | 64.9 | 3.5 / 4.4 / 5.5 |
| D9-S (mix 2) | 12600 / 12600 | 22.5 | 48.7 | 58.3 | 143.5 | 12.6 | 30.4 | 32.0 | 35.5 | 61.7 | 3.4 / 4.4 / 6.0 |
| D9-X | 6300 / 6300 | 22.2 | 50.8 | 62.1 | 128.0 | 11.1 | 30.2 | 32.8 | 35.3 | 64.4 | 3.5 / 4.4 / 5.7 |
| D9-X (mix 2) | 12600 / 12600 | 21.7 | 48.6 | 57.9 | 133.0 | 12.3 | 29.9 | 31.6 | 35.5 | 61.0 | 3.5 / 4.3 / 6.9 |
| D9-S-x2 | 6300 / 6300 | 23.1 | 51.0 | 62.3 | 143.8 | 11.1 | 31.5 | 32.8 | 38.8 | 64.8 | 3.5 / 4.4 / 5.0 |
| D9-S-x2 (mix 2) | 12600 / 12600 | 22.5 | 49.1 | 58.6 | 155.7 | 12.5 | 30.4 | 32.3 | 37.9 | 62.4 | 3.6 / 4.4 / 8.6 |
| D9-X-x2 | 6300 / 6300 | 22.4 | 51.2 | 61.9 | 130.2 | 11.5 | 30.4 | 32.7 | 38.0 | 64.7 | 3.5 / 4.3 / 5.4 |
| D9-X-x2 (mix 2) | 12600 / 12600 | 22.0 | 48.5 | 58.4 | 134.8 | 12.6 | 29.7 | 31.7 | 37.6 | 61.6 | 3.5 / 4.3 / 16.4 |
