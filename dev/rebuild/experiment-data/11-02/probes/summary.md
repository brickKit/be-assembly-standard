# k

## K9-S

Background load: 15873 sent, 15713 ok, 160 failed (68 of them list.order: 404, not visible to the reader); latency p50 24.0 ms, p95 57.1 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | process_crashes and sales | passed | hold | up 8.8 s | 19 failed (09:19:06–09:19:16); max p95 7231 ms |
| 2 | sh:probes11.sh K9-S erp/sales fast | passed | hold |  | 0 failed; max p95 145 ms |
| 3 | process_crashes and sales | passed | hold | up 2.7 s | 6 failed (09:25:50–09:25:50); max p95 184 ms |
| 4 | sh:probes11.sh K9-S erp/sales default | passed | hold |  | 0 failed; max p95 132 ms |
| 5 | process_crashes and sales | passed | hold | up 10.2 s | 24 failed (09:32:31–09:32:42); max p95 11266 ms |
| 6 | sh:probes11.sh K9-S erp/sales fast | passed | hold |  | 0 failed; max p95 107 ms |
| 7 | process_crashes and sales | passed | hold | up 2.7 s | 12 failed (09:39:17–09:39:19); max p95 2077 ms |
| 8 | sh:probes11.sh K9-S erp/sales default | passed | hold |  | 0 failed; max p95 106 ms |
| 9 | process_crashes and sales | passed | hold | up 10.0 s | 23 failed (09:45:58–09:46:10); max p95 11240 ms |
| 10 | sh:probes11.sh K9-S erp/sales fast | passed | hold |  | 0 failed; max p95 110 ms |
| 11 | process_crashes and sales | passed | hold | up 2.1 s | 8 failed (09:52:45–09:52:47); max p95 2074 ms |
