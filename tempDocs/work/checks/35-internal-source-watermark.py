#!/usr/bin/env python3
"""Reference model for security 03: internal sources, watermarks, suspension and scheduled ends.

The source (the employee component) runs transactions that insert outbox rows: ordinary changes,
the employee's leave at s0, and probe echoes. Some transactions roll back; the leave transaction
is sometimes long. A single relay numbers the rows visible in its snapshot ("numbered after
commit") and publishes them; the stream can stall for minutes; the leave delivery can fail and be
redelivered 120 s later while later entries arrive. Authz keeps the contiguous applied position
and a watermark: the probe time of the last echo within that position, on one clock. When the
stream stalls or falls behind (entries keep arriving, ever later) Authz calls the source's pull
endpoint directly once the watermark is half of D_SRC old; the pull is itself a probe. The
component uses a view for W after it asked, on a clock that counts suspension; some appointments
have scheduled ends. Checks:

  BOUND_SRC   no decision relying on the employee being active happens later than
              s0 + D_SRC + W
  BOUND_END   no decision relying on a scheduled appointment happens after its end date
  AVAILABLE   while the source is reachable, decisions keep being made during long stream
              stalls (the pull path keeps the watermark fresh)

Bad variants (each must be caught): no watermark; watermark from the echo's arrival time;
watermark advanced past an entry waiting for redelivery; relay numbers rows in insert order and
skips rows not yet committed (publishing them later); no pull path; clock stops while the host is
suspended; scheduled ends not in the view.
"""
import random
import sys

SEED = 20261013
RUNS = 3000
P = 5             # probe interval
D_SRC = 60        # D_src_high (D64)
W = 5             # view validity
REDELIVER = 120   # longer than D_SRC: a redelivery delay alone must not be able to hide a leave
GAP_TIMEOUT = 120 # the bad relay publishes skipped rows only after this
HORIZON = 400


def run(rng, variant, fails, stats):
    s0 = rng.randint(50, 250)
    scheduled_end = rng.choice([None, rng.randint(60, 300)])
    stall = (rng.randint(40, 200), rng.choice([0, 0, 120, 900]))    # stream stall: (start, length)
    suspend = (rng.randint(20, 300), rng.choice([0, 0, 60, 600]))
    leave_fails_first = rng.random() < 0.3
    long_tx = rng.random() < 0.3      # the leave transaction inserted at s0 - 30, commits at s0
    lag_from = rng.choice([None, None, rng.randint(0, 200)])   # from here the stream falls behind:
    # an entry published at p arrives p - lag_from later, so entries keep arriving, ever later

    # source transactions: [insert time, commit time or None if rolled back, kind, payload]
    txs = []
    for t in range(0, HORIZON, 7):
        if rng.random() < 0.15:
            txs.append((t, None, "change", t))                 # rolled back: never visible
        else:
            txs.append((t, t + rng.choice([0, 0, 1, 3]), "change", t))
    txs.append((s0 - 30 if long_tx else s0, s0, "leave", s0))
    published = []                    # (position, kind, payload, publish time)
    numbered = set()
    skipped = []
    state = {"pos": 0}

    def relay(now):
        if variant == "insert_number_skip":
            order = sorted(range(len(txs)), key=lambda i: txs[i][0])
            for i in order:
                ins, com, kind, pay = txs[i]
                if i in numbered or i in [x[0] for x in skipped] or ins > now or com is None:
                    continue
                if com <= now:
                    numbered.add(i); state["pos"] += 1; published.append((state["pos"], kind, pay, now))
                elif i not in [x[0] for x in skipped]:
                    skipped.append((i, now))                   # gap skipped; published after a timeout
            for i, at in list(skipped):
                ins, com, kind, pay = txs[i]
                if com <= now and now >= at + GAP_TIMEOUT and i not in numbered:
                    skipped.remove((i, at)); numbered.add(i); state["pos"] += 1
                    published.append((state["pos"], kind, pay, now))
            return
        vis = [i for i, (ins, com, k, p) in enumerate(txs)
               if com is not None and com <= now and i not in numbered]
        for i in sorted(vis, key=lambda i: txs[i][0]):
            numbered.add(i); state["pos"] += 1
            published.append((state["pos"], txs[i][2], txs[i][3], now))

    applied_upto = 0
    waiting = None                    # (due, position) of the leave waiting for redelivery
    leave_applied = False
    watermark = None
    view = None
    comp_clock = 0.0
    next_probe = 0
    for t in range(HORIZON):
        if t >= next_probe:           # a direct call; the echo commits when the probe arrives
            next_probe = t + P
            txs.append((t, t, "echo", t))
        relay(t)
        stalled = stall[0] <= t < stall[0] + stall[1]
        if not stalled:
            for (p_, kind, pay, pub) in [x for x in published if x[0] > applied_upto]:
                if lag_from is not None and pub + max(0, pub - lag_from) > t:
                    break                                      # not delivered yet
                if waiting and variant != "applied_watermark":
                    break                                      # contiguous position stops here
                if kind == "leave" and leave_fails_first:
                    leave_fails_first = False
                    waiting = (t + REDELIVER, p_)
                    if variant == "applied_watermark":
                        applied_upto = p_                      # later entries keep being applied
                        continue
                    break
                applied_upto = p_
                if kind == "leave":
                    leave_applied = True
                elif kind == "echo":
                    watermark = t if variant == "arrival_watermark" else pay
        if waiting and t >= waiting[0]:
            leave_applied = True
            waiting = None
        # pull path: when the watermark is getting old the pull request is a probe; numbered rows
        # up to its echo are returned directly (not through the stream)
        if variant not in ("no_pull", "no_watermark") and (watermark is None or watermark < t - D_SRC // 2):
            txs.append((t, t, "echo", t))
            relay(t)
            for (p_, kind, pay, pub) in [x for x in published if x[0] > applied_upto]:
                applied_upto = p_
                if kind == "leave":
                    leave_applied = True; waiting = None
                elif kind == "echo":
                    watermark = pay
        suspended = suspend[0] <= t < suspend[0] + suspend[1]
        if not (suspended and variant == "clock_stops"):
            comp_clock += 1
        if suspended:
            continue
        if t % 2 == 0:
            fresh = watermark is not None and watermark >= t - D_SRC
            if variant == "no_watermark" or fresh:
                end = None if variant == "drop_end_date" else scheduled_end
                view = (comp_clock, not leave_applied, end)
        long_stall = stalled and stall[1] > D_SRC + 2 * W and t > stall[0] + D_SRC + W
        if view is not None and rng.random() < 0.5:
            sent_local, active, end = view
            if comp_clock < sent_local + W and active and (end is None or t < end):
                if long_stall:
                    stats["during_stall"] += 1
                if t > s0 + D_SRC + W:
                    fails.append("BOUND_SRC"); return
                if scheduled_end is not None and t >= scheduled_end:
                    fails.append("BOUND_END"); return


def main():
    variants = ["good", "no_watermark", "arrival_watermark", "applied_watermark", "insert_number_skip",
                "no_pull", "clock_stops", "drop_end_date"]
    res = {}
    for v in variants:
        rng = random.Random(SEED)
        fails = []
        stats = {"during_stall": 0}
        for _ in range(RUNS):
            run(rng, v, fails, stats)
        if stats["during_stall"] == 0:
            fails.append("AVAILABLE")
        res[v] = (sorted(set(fails)), stats)
    g, gs = res["good"]
    print(f"good: {'ok' if not g else 'FAIL ' + str(g)} (BOUND_SRC, BOUND_END, AVAILABLE over {RUNS} runs; "
          f"{gs['during_stall']} decisions during long stream stalls)")
    caught = True
    for v in variants[1:]:
        f, st = res[v]
        print(f"bad variant {v}: {'caught ' + str(f) if f else 'NOT CAUGHT'}")
        caught &= bool(f)
    if g or not caught:
        sys.exit(1)


if __name__ == "__main__":
    main()
