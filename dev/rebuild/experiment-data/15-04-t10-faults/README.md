# T10: faults under load on a probe chain (2026-11-03)

Foundations item 1, T10. Cell `D15-T10` (Docker, balanced power mode: correctness, not timing): test/probe-go 3.2.32
with two replicas writes and emits (its cron job on), test/probe-go2 with two replicas consumes go's stream and
relays every event to test/probe-go3 through a work item; both replicated probes behind HAProxy front doors.
be-sdk-go alpha.52, PostgreSQL 16.15, NATS JetStream. Brought up by `cell-chain.sh` (`up/status.log`), the runs by
`experiment-scripts/t10faults.py` (`runs/*.json`, the logs `runs/log*.txt`), the containers' logs in `logs/`.

After every run the invariants are checked (`invariants()` in the script): every write answered 201 has its outbox
row, is seen by go2 exactly once and relayed; go's outbox is all published and its positions contiguous and unique
per partition and epoch (two replicas number concurrently: CK-EV-02); no relay work item dead, paused, waiting or
running past its lease; no cron slot ran twice (CK-WK-05).

| run | the fault, and whether it hit what it means to | result |
| --- | --- | --- |
| baseline | none, 60 s at 20 writes/s | 1 200 answered 201, all seen once and relayed |
| kill-go | SIGABRT to go's second replica 30 s into 90 s of load; the replica served 80 requests in the 8 s before it, its last log line 0.1 s before the abort; **not proven to be inside a transaction** | 1 800 answered 201, none lost or doubled; replaced by in-tx |
| kill-go2 | SIGABRT to go2's second replica mid-load; JetStream's durable shows 6 600 delivered, **0 redelivered**: it held no unacknowledged message, **not mid-handling** | 1 800 seen once and relayed; replaced by in-job |
| bus-down | NATS stopped 120.1 s, 20 s into 90 s of load (the load ended while it was down) | 1 800 answered 201 from the outbox alone; all forwarded, seen once and relayed 2.0 s after NATS came back |
| takeover (CK-WK-03) | a job holding its attempt 120 s; go's first replica paused 45 s: no takeover (not the holder); the second paused 45 s: the other process took the item over (attempt 2), then the paused one resumed | attempt 1 ended `cancelled` (its renewal found the claim gone), attempt 2 `done`, the effect once |
| in-tx | 12 writes holding their transaction 2 s, go's second replica killed 1 s in: 6 cut (connection lost), 6 answered 201 | the 6 cut have no row (rolled back), the 6 answered have theirs |
| forwarding | 600 writes with NATS down, NATS back, go's second replica killed 0.5 s later: 600 still unpublished at the kill | all published, seen once and relayed 8.1 s later |
| in-job | go3 paused, so go2's relay calls hang; go2's second replica killed when both replicas held a running relay | all relayed once, 16.2 s later (takeover after the lease) |
| baseline (after all) | none | 1 200 answered 201, all fine; 14 cron slots 12:13-12:26 each run once, by 4 processes over the restarts |

The first in-tx attempt asked for `hold_ms` 3000, over the probe's limit of 2000: every write was refused with 400 and
the first version of the check counted any answer but 201 as "killed in a transaction" and passed. The check now
counts only a cut connection or a 5xx, requires some 201s too, and fails on any refusal (`log-targeted.txt`, the
`in-tx.json` of that attempt was overwritten; the second attempt compared IDs as UUID objects with strings and
reported `kept=False`, `log-targeted-2.txt`). The rows of the first attempts' `held-` labels were deleted before the
third (`log-targeted-3.txt`).

Not run here: killing go2 inside its subscription's handling transaction (a short transaction a message; the SDK's
consumer tests cover a failure inside it), and the consumer's database restored to an older backup (needs a replay
by consumer progress the SDK does not have yet: the plan's T10d).
