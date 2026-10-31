# k

## K9-S

Background load: 16990 sent, 16841 ok, 149 failed (94 of them list.order: 404, not visible to the reader); latency p50 24.4 ms, p95 55.5 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | process_crashes and sales | passed | hold | up 2.7 s | 10 failed (11:21:42–11:21:44); max p95 1103 ms |
| 2 | sh:probes11.sh K9-S erp/sales fast | passed | hold |  | 0 failed; max p95 141 ms |
| 3 | process_crashes and sales | passed | hold | up 2.7 s | 11 failed (11:28:20–11:28:22); max p95 2114 ms |
| 4 | sh:probes11.sh K9-S erp/sales v1.10.3 | passed | hold |  | 0 failed; max p95 142 ms |
| 5 | process_crashes and sales | passed | hold | up 2.7 s | 11 failed (11:34:58–11:34:59); max p95 2091 ms |
| 6 | sh:probes11.sh K9-S erp/sales fast | passed | hold |  | 0 failed; max p95 105 ms |
| 7 | process_crashes and sales | passed | hold | up 2.0 s | 4 failed (11:41:36–11:41:38); max p95 158 ms |
| 8 | sh:probes11.sh K9-S erp/sales v1.10.3 | passed | hold |  | 0 failed; max p95 106 ms |
| 9 | process_crashes and sales | passed | hold | up 2.8 s | 10 failed (11:48:14–11:48:15); max p95 1096 ms |
| 10 | sh:probes11.sh K9-S erp/sales fast | passed | hold |  | 0 failed; max p95 119 ms |
| 11 | process_crashes and sales | passed | hold | up 2.7 s | 9 failed (11:54:53–11:54:55); max p95 2073 ms |
| 12 | sh:probes11.sh K9-S erp/sales events | passed | hold |  | 0 failed; max p95 114 ms |
