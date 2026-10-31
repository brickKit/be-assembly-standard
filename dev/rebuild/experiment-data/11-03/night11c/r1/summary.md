# r1/d

## D9-S

Background load: 19682 sent, 19650 ok, 32 failed (0 of them list.order: 404, not visible to the reader); latency p50 22.8 ms, p95 51.7 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 1.7 s, settled 3.8 s | 2 failed (13:06:58–13:06:58); max p95 109 ms |
| 2 | rs05 | passed | hold | up 1.7 s, settled 561.6 s, reason processing_timeout | 2 failed (13:10:39–13:10:39); max p95 138 ms |
| 3 | bl04 | passed | hold | up 1.7 s, settled 30.8 s | 0 failed; max p95 133 ms |
| 4 | process_crashes and sales | passed | hold | up 1.7 s | 2 failed (13:27:48–13:27:48); max p95 107 ms |
| 5 | process_crashes and inventory | passed | hold | up 1.6 s | 0 failed; processing 1 s from 13:31:30; max p95 116 ms |
| 6 | process_crashes and billing | passed | hold | up 1.7 s | 1 failed (13:35:10–13:35:10); max p95 101 ms |
| 7 | rs18 | passed | hold | outcome confirmed, outbox backlog peak 4009, 120.2 s after the stop, drained 2.1 s after the start, projection caught up 1.0 s after | 0 failed; max p95 139 ms |
| 8 | authorization | passed | hold | refused after 31.5 s, (503 AUTHORIZATION_VIEW_EXPIRED), allowed 3.0 s after the start | 21 failed (13:45:19–13:45:23); max p95 107 ms |
| 9 | database | passed | hold | answering 1.3 s after | 4 failed (13:49:06–13:49:06); max p95 132 ms |
| 10 | split | not for an S cell |  |  |  |

Streams after the last fault (invariants-9.json): messages {'erp.billing': 46143, 'erp.credit': 76109, 'erp.inventory': 145484, 'erp.sales': 221134, 'mdm.currency': 700, 'mdm.org': 116, 'mdm.partner': 1525, 'mdm.product': 6527}, IDs more than once {'erp.billing': 0, 'erp.credit': 0, 'erp.inventory': 0, 'erp.sales': 0, 'mdm.currency': 0, 'mdm.org': 0, 'mdm.partner': 0, 'mdm.product': 0}.

## D9-H

Background load: 21215 sent, 21129 ok, 86 failed (18 of them list.order: 404, not visible to the reader); latency p50 22.4 ms, p95 51.6 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 1.9 s, settled 3.9 s | 4 failed (14:07:08–14:07:09); max p95 109 ms |
| 2 | rs05 | passed | hold | up 1.6 s, settled 561.6 s, reason processing_timeout | 3 failed (14:10:48–14:10:48); max p95 147 ms |
| 3 | bl04 | passed | hold | up 1.8 s, settled 30.0 s | 4 failed (14:23:48–14:23:48); max p95 134 ms |
| 4 | process_crashes and sales | passed | hold | up 1.6 s | 2 failed (14:27:56–14:27:57); max p95 201 ms |
| 5 | process_crashes and inventory | passed | hold | up 1.6 s | 3 failed (14:31:37–14:31:38); max p95 107 ms |
| 6 | process_crashes and billing | passed | hold | up 1.6 s | 3 failed (14:35:19–14:35:19); max p95 133 ms |
| 7 | rs18 | passed | hold | outcome confirmed, outbox backlog peak 4014, 120.2 s after the stop, drained 2.1 s after the start, projection caught up 2.0 s after | 0 failed; max p95 128 ms |
| 8 | authorization | passed | hold | refused after 2.3 s, (503 DEPENDENCY_UNAVAILABLE), allowed 1.0 s after the start | 5 failed (14:44:59–14:45:00); max p95 106 ms |
| 9 | database | passed | hold | answering 1.3 s after | 3 failed (14:48:42–14:48:42); max p95 153 ms |
| 10 | split | FAILED | hold | STEP move-out exit=0 secs=0.1<br>STEP build-out exit=0 secs=0.4<br>STEP up-out exit=0 secs=7.3<br>STEP healthy-out exit=0 secs=0.0<br>failed, 7 passed in 2.08s<br>STEP scenarios-out exit=1 secs=2.6<br>SPLIT out scenarios FAILED<br>STEP move-in exit=0 secs=1.9<br>STEP build-in exit=0 secs=0.5<br>STEP up-in exit=0 secs=7.0<br>STEP healthy-in exit=0 secs=0.0<br>failed, 17 passed in 5.68s<br>STEP scenarios-in exit=1 secs=6.2<br>SPLIT in scenarios FAILED | 41 failed (14:52:30–14:52:46); processing 7 s from 14:52:34; max p95 112 ms |

Streams after the last fault (invariants-10.json): messages {'erp.billing': 46621, 'erp.credit': 77378, 'erp.inventory': 147701, 'erp.sales': 225000, 'mdm.currency': 700, 'mdm.org': 120, 'mdm.partner': 1525, 'mdm.product': 6527}, IDs more than once {'erp.billing': 0, 'erp.credit': 0, 'erp.inventory': 0, 'erp.sales': 0, 'mdm.currency': 0, 'mdm.org': 0, 'mdm.partner': 0, 'mdm.product': 0}.
