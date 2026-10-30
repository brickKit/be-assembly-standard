# night11b/k

## K9-H

Background load: 4044 sent, 4007 ok, 37 failed (22 of them list.order: 404, not visible to the reader); latency p50 23.7 ms, p95 57.8 ms.

| # | fault | result | invariants | what the test timed | the load during the fault and its invariants |
| --- | --- | --- | --- | --- | --- |
| 1 | split | passed | hold | STEP move-out exit=0 secs=0.1<br>STEP build-out exit=0 secs=24.4<br>STEP up-out exit=0 secs=18.2<br>STEP healthy-out exit=0 secs=0.1<br>failed, 6 passed in 2.06s<br>STEP scenarios-out exit=1 secs=2.6<br>SPLIT out scenarios FAILED<br>STEP move-in exit=0 secs=1.7<br>STEP build-in exit=0 secs=26.1<br>STEP up-in exit=0 secs=18.9<br>STEP healthy-in exit=0 secs=0.1<br>failed, 6 passed in 2.30s<br>STEP scenarios-in exit=1 secs=2.8<br>SPLIT in scenarios FAILED | 8 failed (00:04:57–00:05:47); processing 80 s from 00:04:59; max p95 15002 ms |
| 2 | upgrade | passed | hold | STEP upgrade-be/go-core@3.0.38 exit=0 secs=2.8<br>STEP build exit=0 secs=27.6<br>STEP up exit=0 secs=19.2<br>STEP healthy exit=0 secs=0.1<br>REPLACED be-go-core-3-0-38-78f69f8d8c-knrvm erp-billing-3-0-13-migration-c2vpz erp-credit-3-0-8-migration-4kght erp-inventory-3-0-9-migration-ltqkv erp-sales-3- | 7 failed (00:09:46–00:09:46); max p95 15002 ms |
