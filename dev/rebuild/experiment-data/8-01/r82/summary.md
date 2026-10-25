| cell | part | idle cores | idle MiB | mix cores | mix MiB | mix CPU s per 1000 requests |
| --- | --- | --- | --- | --- | --- | --- |
| D8-S | components | 0.172 | 441 | 0.265 | 429 | 37.9 |
| D8-S | base | 0.262 | 4393 | 0.382 | 4323 | 54.5 |
| D8-S | platform | 0.107 | 550 | 0.116 | 554 | 16.5 |
| D8-H | components | 0.121 | 373 | 0.206 | 373 | 29.4 |
| D8-H | base | 0.281 | 4170 | 0.372 | 4225 | 53.1 |
| D8-H | platform | 0.069 | 477 | 0.077 | 474 | 11.0 |
| D8-X | components | 0.150 | 330 | 0.231 | 314 | 33.0 |
| D8-X | base | 0.271 | 4034 | 0.365 | 4139 | 52.2 |
| D8-X | platform | 0.082 | 492 | 0.090 | 491 | 12.9 |

| cell | container | idle cores | idle MiB | mix cores | mix MiB |
| --- | --- | --- | --- | --- | --- |
| D8-S | erp-billing | 0.015 | 28 | 0.022 | 29 |
| D8-S | erp-credit | 0.015 | 20 | 0.021 | 20 |
| D8-S | erp-inventory | 0.016 | 26 | 0.028 | 25 |
| D8-S | erp-sales | 0.018 | 45 | 0.070 | 31 |
| D8-S | infra-audit | 0.021 | 24 | 0.010 | 25 |
| D8-S | infra-authz | 0.018 | 18 | 0.017 | 19 |
| D8-S | infra-iam-casdoor | 0.005 | 13 | 0.005 | 13 |
| D8-S | infra-print | 0.007 | 153 | 0.015 | 154 |
| D8-S | mdm-currency | 0.014 | 27 | 0.016 | 27 |
| D8-S | mdm-org | 0.014 | 29 | 0.019 | 28 |
| D8-S | mdm-partner | 0.014 | 29 | 0.019 | 29 |
| D8-S | mdm-product | 0.015 | 30 | 0.023 | 29 |
| D8-H | be-go-core | 0.043 | 92 | 0.114 | 84 |
| D8-H | be-go-infra | 0.070 | 52 | 0.078 | 50 |
| D8-H | be-py-render | 0.007 | 229 | 0.015 | 239 |
| D8-X | be-go-infra | 0.077 | 55 | 0.078 | 51 |
| D8-X | erp-billing | 0.015 | 28 | 0.022 | 29 |
| D8-X | erp-credit | 0.015 | 20 | 0.020 | 20 |
| D8-X | erp-inventory | 0.016 | 26 | 0.028 | 26 |
| D8-X | erp-sales | 0.020 | 44 | 0.069 | 32 |
| D8-X | infra-print | 0.007 | 156 | 0.015 | 157 |

| cell | sent / ok | p50 | p95 | p99 | max | list p95 | order p95 | confirm p95 | deliver p95 | bill p95 | issue to completed p50 / p95 / max | DB connections (component and shell roles, median) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| D8-S | 6300 / 6300 | 23.4 | 52.6 | 66.4 | 155.2 | 11.8 | 32.3 | 34.6 | 38.0 | 70.6 | 3.7 / 4.9 / 10.4 | 101 |
| D8-H | 6300 / 6300 | 22.8 | 52.5 | 64.4 | 133.7 | 11.8 | 31.8 | 34.1 | 36.9 | 67.1 | 3.6 / 4.8 / 6.7 | 64 |
| D8-X | 6300 / 6300 | 22.9 | 52.4 | 65.2 | 140.0 | 11.8 | 31.4 | 34.3 | 37.2 | 67.8 | 3.6 / 4.6 / 10.2 | 75 |
