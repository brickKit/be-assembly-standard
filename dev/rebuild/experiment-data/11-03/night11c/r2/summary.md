# dev/rebuild/experiment-data/11-03/night11c/r2/d

## D9-X

Background load: 21232 sent, 21157 ok, 75 failed (17 of them list.order: 404, not visible to the reader); latency p50 22.1 ms, p95 51.1 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 1.7 s, settled 3.8 s | 2 failed (16:22:45–16:22:46); max p95 109 ms |
| 2 | rs05 | passed | hold | up 1.6 s, settled 561.5 s, reason processing_timeout | 2 failed (16:26:25–16:26:25); max p95 133 ms |
| 3 | bl04 | passed | hold | up 1.7 s, settled 30.8 s | 0 failed; max p95 131 ms |
| 4 | process_crashes and sales | passed | hold | up 1.7 s | 2 failed (16:43:35–16:43:35); max p95 102 ms |
| 5 | process_crashes and inventory | passed | hold | up 1.7 s | 0 failed; processing 1 s from 16:47:16; max p95 106 ms |
| 6 | process_crashes and billing | passed | hold | up 1.7 s | 1 failed (16:50:57–16:50:57); max p95 111 ms |
| 7 | rs18 | passed | hold | outcome confirmed, outbox backlog peak 4024, 120.2 s after the stop, drained 2.1 s after the start, projection caught up 2.0 s after | 0 failed; max p95 137 ms |
| 8 | authorization | passed | hold | refused after 2.5 s, (503 DEPENDENCY_UNAVAILABLE), allowed 1.0 s after the start | 5 failed (17:00:37–17:00:38); max p95 217 ms |
| 9 | database | passed | hold | answering 1.3 s after | 3 failed (17:04:21–17:04:21); max p95 139 ms |
| 10 | split | passed | hold | STEP move-in exit=0 secs=2.1<br>STEP build-in exit=0 secs=0.4<br>STEP up-in exit=0 secs=6.8<br>STEP healthy-in exit=0 secs=0.0<br>passed in 6.25s<br>STEP scenarios-in exit=0 secs=6.7<br>STEP move-out exit=0 secs=0.1<br>STEP build-out exit=0 secs=0.4<br>STEP up-out exit=0 secs=7.1<br>STEP healthy-out exit=0 secs=0.0<br>passed in 6.12s<br>STEP scenarios-out exit=0 secs=6.6 | 43 failed (17:08:10–17:08:27); max p95 166 ms |

Streams after the last fault (invariants-10.json): messages {'erp.billing': 46631, 'erp.credit': 77465, 'erp.inventory': 147842, 'erp.sales': 225216, 'mdm.currency': 700, 'mdm.org': 120, 'mdm.partner': 1525, 'mdm.product': 6527}, IDs more than once {'erp.billing': 0, 'erp.credit': 0, 'erp.inventory': 0, 'erp.sales': 0, 'mdm.currency': 0, 'mdm.org': 0, 'mdm.partner': 0, 'mdm.product': 0}.
# dev/rebuild/experiment-data/11-03/night11c/r2/k

## K9-S

Background load: 18350 sent, 18193 ok, 157 failed (62 of them list.order: 404, not visible to the reader); latency p50 23.0 ms, p95 53.2 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 2.7 s, settled 3.9 s | 8 failed (17:27:35–17:27:36); max p95 1074 ms |
| 2 | rs05 | passed | hold | up 12.3 s, settled 360.1 s, reason processing_timeout | 24 failed (17:31:16–17:31:30); max p95 11275 ms |
| 3 | bl04 | passed | hold | up 2.7 s, settled 29.9 s | 2 failed (17:40:55–17:40:56); max p95 111 ms |
| 4 | process_crashes and sales | passed | hold | up 3.3 s | 6 failed (17:45:03–17:45:04); max p95 129 ms |
| 5 | process_crashes and inventory | passed | hold | up 2.7 s | 0 failed; processing 6 s from 17:48:47; max p95 270 ms |
| 6 | process_crashes and billing | passed | hold | up 3.2 s | 2 failed (17:52:30–17:52:32); max p95 126 ms |
| 7 | rs18 | passed | hold | outcome confirmed, outbox backlog peak 4014, 120.2 s after the stop, drained 2.1 s after the start, projection caught up 1.0 s after | 0 failed; max p95 106 ms |
| 8 | authorization | passed | hold | refused after 32.5 s, (503 AUTHORIZATION_VIEW_EXPIRED), allowed 7.0 s after the start | 50 failed (18:02:41–18:02:49); max p95 137 ms |
| 9 | database | passed | hold | answering 1.4 s after | 3 failed (18:06:32–18:06:32); max p95 119 ms |
| 10 | split | not for an S cell |  |  |  |

Streams after the last fault (invariants-9.json): messages {'erp.billing': 45699, 'erp.credit': 75121, 'erp.inventory': 143692, 'erp.sales': 217731, 'mdm.currency': 700, 'mdm.org': 116, 'mdm.partner': 1525, 'mdm.product': 6527}, IDs more than once {'erp.billing': 0, 'erp.credit': 0, 'erp.inventory': 0, 'erp.sales': 0, 'mdm.currency': 0, 'mdm.org': 0, 'mdm.partner': 0, 'mdm.product': 0}.
