# night11/d

## D9-S

Background load: 19092 sent, 19026 ok, 66 failed (0 of them list.order: 404, not visible to the reader); latency p50 22.4 ms, p95 51.4 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 5.4 s, settled 5.5 s | 2 failed (17:43:46–17:43:47); max p95 110 ms |
| 2 | rs05 | passed | hold | up 5.4 s, settled 360.1 s, reason processing_timeout | 2 failed (17:46:58–17:46:59); max p95 138 ms |
| 3 | bl04 | passed | hold | up 5.4 s, settled 30.5 s | 0 failed; max p95 100 ms |
| 4 | process_crashes and sales | passed | hold | up 5.3 s | 1 failed (17:59:42–17:59:42); max p95 102 ms |
| 5 | process_crashes and inventory | passed | hold | up 5.4 s | 0 failed; processing 30 s from 18:02:54; max p95 130 ms |
| 6 | process_crashes and billing | passed | hold | up 5.4 s | 0 failed; max p95 104 ms |
| 7 | rs18 | passed | hold | outcome confirmed | 0 failed; max p95 130 ms |
| 8 | authorization | passed | hold | refused after 30.5 s, (503 AUTHORIZATION_VIEW_EXPIRED), allowed 5.0 s after the start | 38 failed (18:14:53–18:14:59); max p95 104 ms |
| 9 | database | passed | hold | answering 1.4 s after | 4 failed (18:18:06–18:18:07); max p95 132 ms |
| 10 | burst | passed | hold | BURST exit=0 | 0 failed; max p95 102 ms |
| 11 | split | not for an S cell |  |  |  |
| 12 | upgrade | passed | hold | STEP upgrade-erp/inventory@3.0.9 exit=0 secs=1.7<br>STEP upgrade-erp/sales@3.0.14 exit=0 secs=1.4<br>STEP upgrade-erp/billing@3.0.13 exit=0 secs=1.5<br>STEP build exit=0 secs=0.4<br>STEP up exit=0 secs=10.8<br>STEP healthy exit=0 secs=0.0<br>REPLACED brickkit-d9-s-erp-billing-3-0-13-1 brickkit-d9-s-erp-inventory-3-0-9-1 brickkit-d9-s-erp-sales-3-0-14-1 | 19 failed (18:24:59–18:25:01); processing 32 s from 18:25:02; max p95 130 ms |

## D9-H

Background load: 22071 sent, 21858 ok, 213 failed (11 of them list.order: 404, not visible to the reader); latency p50 22.2 ms, p95 51.1 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 5.5 s, settled 5.6 s | 4 failed (18:41:09–18:41:09); max p95 104 ms |
| 2 | rs05 | passed | hold | up 5.8 s, settled 561.5 s, reason processing_timeout | 3 failed (18:44:21–18:44:21); max p95 133 ms |
| 3 | bl04 | passed | hold | up 5.5 s, settled 30.7 s | 4 failed (18:56:49–18:56:50); max p95 104 ms |
| 4 | process_crashes and sales | passed | hold | up 5.8 s | 4 failed (19:00:26–19:00:26); max p95 145 ms |
| 5 | process_crashes and inventory | passed | hold | up 5.8 s | 3 failed (19:03:38–19:03:38); max p95 100 ms |
| 6 | process_crashes and billing | passed | hold | up 5.8 s | 4 failed (19:06:50–19:06:50); max p95 137 ms |
| 7 | rs18 | passed | hold | outcome confirmed | 0 failed; max p95 113 ms |
| 8 | authorization | passed | hold | refused after 2.6 s, (503 DEPENDENCY_UNAVAILABLE), allowed 31.1 s after the start | 120 failed (19:15:11–19:15:42); max p95 217 ms |
| 9 | database | passed | hold | answering 1.4 s after | 3 failed (19:18:50–19:18:50); max p95 106 ms |
| 10 | burst | passed | hold | BURST exit=0 | 0 failed; max p95 247 ms |
| 11 | split | passed | hold | STEP move-out exit=0 secs=0.1<br>STEP build-out exit=0 secs=0.5<br>STEP up-out exit=0 secs=11.0<br>STEP healthy-out exit=0 secs=0.0<br>passed in 5.65s<br>STEP scenarios-out exit=0 secs=6.1<br>STEP move-in exit=0 secs=2.5<br>STEP build-in exit=0 secs=0.5<br>STEP up-in exit=0 secs=10.9<br>STEP healthy-in exit=0 secs=0.0<br>passed in 5.76s<br>STEP scenarios-in exit=0 secs=6.2 | 38 failed (19:25:38–19:26:01); processing 1 s from 19:25:41; max p95 104 ms |
| 12 | upgrade | passed | hold | STEP upgrade-be/go-core@3.0.38 exit=0 secs=5.0<br>STEP build exit=0 secs=0.5<br>STEP up exit=0 secs=10.2<br>STEP healthy exit=0 secs=0.0<br>REPLACED brickkit-d9-h-be-go-core-3-0-38-1 | 19 failed (19:29:27–19:29:30); max p95 96 ms |

## D9-X

Background load: 21855 sent, 21758 ok, 97 failed (18 of them list.order: 404, not visible to the reader); latency p50 22.1 ms, p95 51.6 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 5.4 s, settled 5.5 s | 2 failed (19:45:53–19:45:53); max p95 107 ms |
| 2 | rs05 | passed | hold | up 5.3 s, settled 562.6 s, reason processing_timeout | 1 failed (19:49:04–19:49:04); max p95 143 ms |
| 3 | bl04 | passed | hold | up 5.4 s, settled 30.5 s | 1 failed (20:01:33–20:01:33); max p95 103 ms |
| 4 | process_crashes and sales | passed | hold | up 5.4 s | 3 failed (20:05:10–20:05:10); max p95 128 ms |
| 5 | process_crashes and inventory | passed | hold | up 5.4 s | 0 failed; max p95 97 ms |
| 6 | process_crashes and billing | passed | hold | up 5.3 s | 0 failed; max p95 135 ms |
| 7 | rs18 | passed | hold | outcome confirmed | 0 failed; max p95 109 ms |
| 8 | authorization | passed | hold | refused after 2.4 s, (503 DEPENDENCY_UNAVAILABLE), allowed 1.0 s after the start | 5 failed (20:19:54–20:19:55); max p95 136 ms |
| 9 | database | passed | hold | answering 1.3 s after | 2 failed (20:23:03–20:23:03); max p95 1025 ms |
| 10 | burst | passed | hold | BURST exit=0 | 0 failed; max p95 240 ms |
| 11 | split | passed | hold | STEP move-in exit=0 secs=2.1<br>STEP build-in exit=0 secs=0.5<br>STEP up-in exit=0 secs=10.9<br>STEP healthy-in exit=0 secs=0.0<br>passed in 5.78s<br>STEP scenarios-in exit=0 secs=6.2<br>STEP move-out exit=0 secs=0.1<br>STEP build-out exit=0 secs=0.4<br>STEP up-out exit=0 secs=11.4<br>STEP healthy-out exit=0 secs=0.0<br>passed in 5.56s<br>STEP scenarios-out exit=0 secs=6.0 | 45 failed (20:29:53–20:30:14); max p95 216 ms |
| 12 | upgrade | passed | hold | STEP upgrade-erp/inventory@3.0.9 exit=0 secs=1.4<br>STEP upgrade-erp/sales@3.0.14 exit=0 secs=1.3<br>STEP upgrade-erp/billing@3.0.13 exit=0 secs=1.4<br>STEP build exit=0 secs=0.4<br>STEP up exit=0 secs=10.9<br>STEP healthy exit=0 secs=0.0<br>REPLACED brickkit-d9-x-erp-billing-3-0-13-1 brickkit-d9-x-erp-inventory-3-0-9-1 brickkit-d9-x-erp-sales-3-0-14-1 | 20 failed (20:33:39–20:33:42); max p95 108 ms |
# night11/k

## K9-S

Background load: 19459 sent, 19190 ok, 269 failed (8 of them list.order: 404, not visible to the reader); latency p50 22.8 ms, p95 55.0 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 9.3 s, settled 9.5 s | 21 failed (20:51:48–20:51:56); max p95 7237 ms |
| 2 | rs05 | passed | hold | up 21.5 s, settled 360.1 s, reason processing_timeout | 94 failed (20:55:04–20:55:54); max p95 15002 ms |
| 3 | bl04 | passed | hold | up 5.4 s, settled 30.6 s | 4 failed (21:04:11–21:04:14); max p95 106 ms |
| 4 | process_crashes and sales | passed | hold | up 8.7 s | 20 failed (21:07:47–21:07:55); max p95 7280 ms |
| 5 | process_crashes and inventory | passed | hold | up 9.4 s | 0 failed; processing 31 s from 21:11:03; max p95 137 ms |
| 6 | process_crashes and billing | passed | hold | up 6.7 s | 6 failed (21:14:19–21:14:25); max p95 99 ms |
| 7 | rs18 | passed | hold | outcome confirmed | 0 failed; max p95 139 ms |
| 8 | authorization | passed | hold | refused after 31.5 s, (503 AUTHORIZATION_VIEW_EXPIRED), allowed 15.0 s after the start | 106 failed (21:23:10–21:23:25); max p95 113 ms |
| 9 | database | passed | hold | answering 1.4 s after | 4 failed (21:26:32–21:26:32); max p95 143 ms |
| 10 | burst | passed | hold | BURST exit=0 | 0 failed; max p95 263 ms |
| 11 | split | not for an S cell |  |  |  |
| 12 | upgrade | passed | hold | STEP upgrade-erp/inventory@3.0.9 exit=0 secs=1.5<br>STEP upgrade-erp/sales@3.0.14 exit=0 secs=1.3<br>STEP upgrade-erp/billing@3.0.13 exit=0 secs=1.4<br>STEP build exit=0 secs=20.7<br>STEP up exit=0 secs=18.0<br>STEP healthy exit=0 secs=0.1<br>REPLACED erp-billing-3-0-13-54889fdf9d-jn56t erp-billing-3-0-13-migration-ts28c erp-credit-3-0-8-migration-l78w6 erp-inventory-3-0-9-7f445cccbb-d9784 erp-invent | 6 failed (21:34:00–21:34:01); max p95 15002 ms |

## K9-H

Background load: 22526 sent, 21600 ok, 926 failed (77 of them list.order: 404, not visible to the reader); latency p50 22.7 ms, p95 62.1 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 9.2 s, settled 10.4 s | 13 failed (21:50:58–21:51:08); max p95 107 ms |
| 2 | rs05 | passed | hold | up 22.9 s, settled 540.5 s, reason processing_timeout | 96 failed (21:54:15–21:54:38); processing 39 s from 21:54:28; max p95 15002 ms |
| 3 | bl04 | passed | hold | up 10.4 s, settled 30.6 s | 13 failed (22:06:23–22:06:33); max p95 124 ms |
| 4 | process_crashes and sales | passed | hold | up 22.4 s | 97 failed (22:10:00–22:10:22); processing 38 s from 22:10:12; max p95 15002 ms |
| 5 | process_crashes and inventory | passed | hold | up 34.1 s | 174 failed (22:13:28–22:14:02); processing 42 s from 22:13:52; max p95 15002 ms |
| 6 | process_crashes and billing | passed | hold | up 53.0 s | 311 failed (22:17:09–22:18:02); processing 42 s from 22:17:52; max p95 15002 ms |
| 7 | rs18 | passed | hold | outcome confirmed | 0 failed; max p95 109 ms |
| 8 | authorization | passed | hold | refused after 2.2 s, (503 DEPENDENCY_UNAVAILABLE), allowed 31.1 s after the start | 138 failed (22:26:18–22:27:08); max p95 139 ms |
| 9 | database | passed | hold | answering 1.3 s after | 3 failed (22:29:56–22:29:56); max p95 103 ms |
| 10 | burst | passed | hold | BURST exit=0 | 0 failed; max p95 213 ms |
| 11 | split | FAILED | hold | STEP move-out exit=0 secs=0.1<br>STEP build-out exit=0 secs=24.2<br>STEP up-out exit=1 secs=17.2 | 4 failed (22:37:22–22:37:23); processing 31 s from 22:37:24; max p95 15002 ms |
| 12 | upgrade | FAILED | hold | STEP upgrade-be/go-core@3.0.38 exit=1 secs=0.0 | 0 failed; max p95 132 ms |

## K9-X

Background load: 21375 sent, 21101 ok, 274 failed (24 of them list.order: 404, not visible to the reader); latency p50 23.1 ms, p95 56.5 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | rs06 | passed | hold | up 7.3 s, settled 7.4 s | 18 failed (22:57:57–22:58:04); max p95 5163 ms |
| 2 | rs05 | passed | hold | up 19.1 s, settled 360.1 s, reason processing_timeout | 68 failed (23:01:12–23:01:31); max p95 15002 ms |
| 3 | bl04 | passed | hold | up 6.0 s, settled 30.2 s | 4 failed (23:10:20–23:10:24); max p95 109 ms |
| 4 | process_crashes and sales | passed | hold | up 10.6 s | 25 failed (23:13:56–23:14:07); max p95 11241 ms |
| 5 | process_crashes and inventory | passed | hold | up 7.3 s | 0 failed; processing 31 s from 23:17:13; max p95 138 ms |
| 6 | process_crashes and billing | passed | hold | up 7.2 s | 4 failed (23:20:29–23:20:32); max p95 107 ms |
| 7 | rs18 | passed | hold | outcome confirmed | 0 failed; max p95 140 ms |
| 8 | authorization | passed | hold | refused after 2.4 s, (503 DEPENDENCY_UNAVAILABLE), allowed 31.1 s after the start | 127 failed (23:28:51–23:29:22); max p95 125 ms |
| 9 | database | passed | hold | answering 1.4 s after | 4 failed (23:32:29–23:32:29); max p95 134 ms |
| 10 | burst | passed | hold | BURST exit=0 | 0 failed; max p95 252 ms |
| 11 | split | passed | hold | STEP move-in exit=0 secs=2.0<br>STEP build-in exit=0 secs=22.9<br>STEP up-in exit=0 secs=17.6<br>STEP healthy-in exit=0 secs=0.1<br>passed in 6.46s<br>STEP scenarios-in exit=0 secs=7.0<br>STEP move-out exit=0 secs=0.1<br>STEP build-out exit=0 secs=20.4<br>STEP up-out exit=0 secs=17.7<br>STEP healthy-out exit=0 secs=0.1<br>passed in 5.84s<br>STEP scenarios-out exit=0 secs=6.4 | 0 failed; max p95 184 ms |
| 12 | upgrade | passed | hold | STEP upgrade-erp/inventory@3.0.9 exit=0 secs=2.4<br>STEP upgrade-erp/sales@3.0.14 exit=0 secs=1.4<br>STEP upgrade-erp/billing@3.0.13 exit=0 secs=1.5<br>STEP build exit=0 secs=22.0<br>STEP up exit=0 secs=18.7<br>STEP healthy exit=0 secs=0.1<br>REPLACED erp-billing-3-0-13-7b599bfb6f-j2kgs erp-billing-3-0-13-migration-fqdks erp-credit-3-0-8-migration-cmd7n erp-inventory-3-0-9-7898c87c4f-8hrck erp-invent | 0 failed; processing 31 s from 23:44:43; max p95 115 ms |
