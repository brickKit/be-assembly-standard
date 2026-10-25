| cell | part | idle cores | idle MiB | mix cores | mix MiB | mix CPU s per 1000 requests |
| --- | --- | --- | --- | --- | --- | --- |
| D8-S | components | 0.165 | 512 | 0.257 | 500 | 36.8 |
| D8-S | base | 0.245 | 4883 | 0.367 | 4854 | 52.4 |
| D8-S | platform | 0.103 | 529 | 0.114 | 532 | 16.3 |
| D8-H | components | 0.116 | 360 | 0.193 | 372 | 27.6 |
| D8-H | base | 0.236 | 5244 | 0.351 | 5285 | 50.2 |
| D8-H | platform | 0.068 | 464 | 0.075 | 466 | 10.7 |
| D8-X | components | 0.142 | 319 | 0.227 | 314 | 32.5 |
| D8-X | base | 0.257 | 3412 | 0.364 | 3460 | 52.0 |
| D8-X | platform | 0.082 | 490 | 0.089 | 492 | 12.8 |

| cell | components: process RSS, idle MiB | mix MiB |
| --- | --- | --- |
| D8-S | 744 | 731 |
| D8-H | 383 | 380 |
| D8-X | 506 | 499 |

| cell | container | idle cores | idle MiB | mix cores | mix MiB |
| --- | --- | --- | --- | --- | --- |
| D8-S | erp-billing | 0.014 | 32 | 0.021 | 34 |
| D8-S | erp-credit | 0.013 | 24 | 0.020 | 23 |
| D8-S | erp-inventory | 0.015 | 31 | 0.027 | 30 |
| D8-S | erp-sales | 0.016 | 48 | 0.067 | 37 |
| D8-S | infra-audit | 0.023 | 23 | 0.010 | 24 |
| D8-S | infra-authz | 0.017 | 18 | 0.017 | 19 |
| D8-S | infra-iam-casdoor | 0.005 | 14 | 0.006 | 14 |
| D8-S | infra-print | 0.007 | 208 | 0.015 | 208 |
| D8-S | mdm-currency | 0.013 | 27 | 0.016 | 27 |
| D8-S | mdm-org | 0.013 | 29 | 0.019 | 28 |
| D8-S | mdm-partner | 0.014 | 28 | 0.018 | 28 |
| D8-S | mdm-product | 0.014 | 30 | 0.022 | 29 |
| D8-H | be-go-core | 0.042 | 93 | 0.107 | 85 |
| D8-H | be-go-infra | 0.067 | 53 | 0.072 | 50 |
| D8-H | be-py-render | 0.007 | 213 | 0.015 | 237 |
| D8-X | be-go-infra | 0.074 | 53 | 0.077 | 48 |
| D8-X | erp-billing | 0.015 | 28 | 0.021 | 29 |
| D8-X | erp-credit | 0.014 | 20 | 0.020 | 19 |
| D8-X | erp-inventory | 0.016 | 26 | 0.027 | 25 |
| D8-X | erp-sales | 0.017 | 42 | 0.067 | 32 |
| D8-X | infra-print | 0.007 | 151 | 0.015 | 160 |

| cell | sent / ok | p50 | p95 | p99 | max | list p95 | order p95 | confirm p95 | deliver p95 | bill p95 | issue to completed p50 / p95 / max | DB connections (component and shell roles, median) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D8-S | 6300 / 6300 | 22.4 | 50.9 | 65.8 | 175.7 | 11.8 | 31.8 | 34.4 | 35.9 | 70.0 | 3.6 / 4.9 / 29.4 | 99 |
| D8-H | 6300 / 6300 | 21.5 | 49.1 | 61.3 | 133.9 | 11.2 | 30.3 | 32.5 | 35.4 | 62.9 | 3.4 / 4.2 / 6.3 | 67 |
| D8-X | 6300 / 6300 | 21.8 | 50.9 | 63.9 | 137.3 | 12.0 | 31.6 | 34.5 | 37.0 | 68.0 | 3.5 / 4.7 / 13.6 | 70 |
