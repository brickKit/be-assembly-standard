# dev/rebuild/experiment-data/11-03/night11c/r3/d

## D9-H

Background load: 2124 sent, 2082 ok, 42 failed (0 of them list.order: 404, not visible to the reader); latency p50 22.4 ms, p95 51.5 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | split | FAILED | hold | STEP move-out exit=0 secs=0.1<br>STEP build-out exit=0 secs=0.5<br>STEP up-out exit=0 secs=7.5<br>STEP healthy-out exit=0 secs=0.0<br>STEP ready-out exit=0 secs=0.4<br>failed, 6 passed in 2.06s<br>STEP scenarios-out exit=1 secs=2.5<br>SPLIT out scenarios FAILED<br>STEP move-in exit=0 secs=2.0<br>STEP build-in exit=0 secs=0.5<br>STEP up-in exit=0 secs=6.9<br>STEP healthy-in exit=0 secs=0.0<br>STEP ready-in exit=0 secs=0.4<br>failed, 17 passed in 6.14s<br>STEP scenarios-in exit=1 secs=6.6<br>SPLIT in scenarios FAILED | 42 failed (22:44:24–22:44:40); processing 8 s from 22:44:28; max p95 103 ms |

Streams after the last fault (invariants-1.json): messages {'erp.billing': 40895, 'erp.credit': 64034, 'erp.inventory': 122931, 'erp.sales': 178371, 'mdm.currency': 700, 'mdm.org': 118, 'mdm.partner': 1525, 'mdm.product': 6527}, IDs more than once {'erp.billing': 0, 'erp.credit': 0, 'erp.inventory': 0, 'erp.sales': 0, 'mdm.currency': 0, 'mdm.org': 0, 'mdm.partner': 0, 'mdm.product': 0}.
# dev/rebuild/experiment-data/11-03/night11c/r3/k

## K9-H

Background load: 22535 sent, 21746 ok, 789 failed (99 of them list.order: 404, not visible to the reader); latency p50 22.9 ms, p95 60.1 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 3.2 s, settled 3.4 s | 14 failed (23:03:40–23:03:42); max p95 2078 ms |
| 2 | rs05 | passed | hold | up 12.7 s, settled 548.5 s, reason processing_timeout | 33 failed (23:07:20–23:07:32); processing 16 s from 23:07:23; max p95 11252 ms |
| 3 | bl04 | passed | hold | up 3.2 s, settled 30.4 s | 14 failed (23:20:07–23:20:09); max p95 1089 ms |
| 4 | process_crashes and sales | passed | hold | up 12.7 s | 33 failed (23:24:17–23:24:30); processing 17 s from 23:24:20; max p95 11257 ms |
| 5 | process_crashes and inventory | passed | hold | up 24.3 s | 107 failed (23:28:09–23:28:34); processing 18 s from 23:28:24; max p95 15002 ms |
| 6 | process_crashes and billing | passed | hold | up 56.7 s | 333 failed (23:32:14–23:33:12); processing 17 s from 23:33:01; max p95 15002 ms |
| 7 | rs18 | passed | hold | outcome confirmed, outbox backlog peak 4016, 120.2 s after the stop, drained 2.1 s after the start, projection caught up 2.0 s after | 0 failed; max p95 145 ms |
| 8 | authorization | passed | hold | refused after 2.2 s, (503 DEPENDENCY_UNAVAILABLE), allowed 36.1 s after the start | 149 failed (23:42:51–23:43:27); max p95 3003 ms |
| 9 | database | passed | hold | answering 1.3 s after | 3 failed (23:47:10–23:47:10); max p95 130 ms |
| 10 | split | passed | hold | STEP move-out exit=0 secs=0.1<br>STEP build-out exit=0 secs=24.8<br>STEP up-out exit=0 secs=13.8<br>STEP healthy-out exit=0 secs=0.1<br>STEP ready-out exit=0 secs=0.0<br>passed in 5.76s<br>STEP scenarios-out exit=0 secs=6.2<br>STEP move-in exit=0 secs=2.4<br>STEP build-in exit=0 secs=26.1<br>STEP up-in exit=0 secs=13.5<br>STEP healthy-in exit=0 secs=0.1<br>STEP ready-in exit=0 secs=0.0<br>passed in 6.36s<br>STEP scenarios-in exit=0 secs=6.8 | 4 failed (23:52:22–23:52:22); max p95 15002 ms |

Streams after the last fault (invariants-10.json): messages {'erp.billing': 46805, 'erp.credit': 77859, 'erp.inventory': 148587, 'erp.sales': 226648, 'mdm.currency': 700, 'mdm.org': 120, 'mdm.partner': 1525, 'mdm.product': 6527}, IDs more than once {'erp.billing': 0, 'erp.credit': 0, 'erp.inventory': 0, 'erp.sales': 0, 'mdm.currency': 0, 'mdm.org': 0, 'mdm.partner': 0, 'mdm.product': 0}.

## K9-X

Background load: 20521 sent, 20373 ok, 148 failed (23 of them list.order: 404, not visible to the reader); latency p50 23.5 ms, p95 55.6 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 2.6 s, settled 3.8 s | 12 failed (00:11:09–00:11:11); max p95 1071 ms |
| 2 | rs05 | passed | hold | up 13.3 s, settled 360.1 s, reason processing_timeout | 36 failed (00:14:52–00:15:07); max p95 15001 ms |
| 3 | bl04 | passed | hold | up 3.2 s, settled 30.4 s | 3 failed (00:24:32–00:24:35); max p95 107 ms |
| 4 | process_crashes and sales | passed | hold | up 2.6 s | 3 failed (00:28:44–00:28:44); max p95 155 ms |
| 5 | process_crashes and inventory | passed | hold | up 2.7 s | 0 failed; processing 5 s from 00:32:28; max p95 111 ms |
| 6 | process_crashes and billing | passed | hold | up 2.6 s | 2 failed (00:36:12–00:36:15); max p95 130 ms |
| 7 | rs18 | passed | hold | outcome confirmed, outbox backlog peak 4013, 120.3 s after the stop, drained 2.1 s after the start, projection caught up 2.0 s after | 0 failed; max p95 112 ms |
| 8 | authorization | passed | hold | refused after 2.3 s, (503 DEPENDENCY_UNAVAILABLE), allowed 17.0 s after the start | 66 failed (00:45:58–00:46:14); max p95 3003 ms |
| 9 | database | passed | hold | answering 1.3 s after | 3 failed (00:49:59–00:50:00); max p95 1095 ms |
| 10 | split | passed | hold | STEP move-in exit=0 secs=2.0<br>STEP build-in exit=0 secs=22.9<br>STEP up-in exit=0 secs=13.9<br>STEP healthy-in exit=0 secs=0.1<br>STEP ready-in exit=0 secs=0.0<br>passed in 6.43s<br>STEP scenarios-in exit=0 secs=6.9<br>STEP move-out exit=0 secs=0.1<br>STEP build-out exit=0 secs=20.3<br>STEP up-out exit=0 secs=13.9<br>STEP healthy-out exit=0 secs=0.1<br>STEP ready-out exit=0 secs=0.0<br>passed in 5.84s<br>STEP scenarios-out exit=0 secs=6.4 | 0 failed; max p95 143 ms |

Streams after the last fault (invariants-10.json): messages {'erp.billing': 46348, 'erp.credit': 76879, 'erp.inventory': 146789, 'erp.sales': 223221, 'mdm.currency': 700, 'mdm.org': 120, 'mdm.partner': 1525, 'mdm.product': 6527}, IDs more than once {'erp.billing': 0, 'erp.credit': 0, 'erp.inventory': 0, 'erp.sales': 0, 'mdm.currency': 0, 'mdm.org': 0, 'mdm.partner': 0, 'mdm.product': 0}.
