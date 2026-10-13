#!/usr/bin/env python3
"""Reference model for security 03: internal sources, watermarks, suspension and scheduled ends.

An internal source (the employee component) commits a revocation (an employee leaves) at s0.
Its changes reach Authz through an ordered stream whose lag varies and can grow to minutes.
Authz probes the source every P seconds; the source writes an echo of each probe into the same
ordered stream. Authz renews a component's view only while its watermark (Authz's monotonic
time when the last applied echo's probe was sent) is no older than D_src. The component uses a
view for W after it sent the verification request, on a clock that counts suspension; its host
is sometimes suspended. Some revocations are scheduled (an end date known in advance) and travel
with the view. Checks:

  BOUND_SRC   no decision relying on the employee being active happens later than
              s0 + D_src + W
  BOUND_END   no decision relying on a scheduled appointment happens after its end date

The leave event sometimes fails on first delivery and is redelivered 60 s later while later echoes
are applied (a shared durable consumer); the watermark only advances through the contiguous
applied position. When the stream stalls, Authz pulls committed changes by sequence (D64).

Bad variants (each must be caught): no watermark (Authz renews regardless of source lag);
watermark taken from the echo's arrival time instead of the probe's send time; watermark advanced
by any applied echo even behind an entry waiting for redelivery; a component clock
that stops while the host is suspended; scheduled end dates not carried in the view.
"""
import random
import sys

SEED = 20261013
RUNS = 3000
P = 5            # probe interval
D_SRC = 60       # maximum watermark age for high-risk decisions (D64)
REDELIVER = 60   # a failed delivery is redelivered after this delay
W = 5            # view validity
HORIZON = 400


def run(rng, variant, fails):
    s0 = rng.randint(50, 250)                       # unscheduled leave committed at the source
    scheduled_end = rng.choice([None, rng.randint(60, 300)])
    lag_base = rng.choice([1, 2, 5])
    surge = (rng.randint(40, 200), rng.choice([0, 120, 900]))   # (start, extra lag) for a stream stall
    suspend = (rng.randint(20, 300), rng.choice([0, 0, 60, 600]))  # (start, duration) of host suspension

    def lag(t):
        start, extra = surge
        return lag_base + (extra if start <= t < start + extra else 0)

    commits = [(p, "echo", p) for p in range(0, HORIZON, P)]   # echo committed when the probe arrives
    commits.append((s0, "leave", s0))
    commits.sort(key=lambda c: (c[0], c[1] != "leave"))
    stream = []            # (arrival, kind, payload) -- one ordered stream: arrivals keep commit order
    last = 0
    for commit_t, kind, payload in commits:
        last = max(last, commit_t + lag(commit_t))
        stream.append((last, kind, payload))
    applied_leave = False
    watermark = None
    fail_first = rng.random() < 0.3      # the leave event fails on first delivery and is redelivered
    pending = []                         # entries waiting for redelivery: (due, kind, payload)
    blocked = False                      # an earlier entry is pending: the contiguous position stops
    decisions = 0
    view = None            # (sent_local, active, end)
    comp_clock = 0.0       # component's local clock reading
    for t in range(HORIZON):
        # Authz applies stream entries; another replica may apply later entries while one waits
        for item in sorted([x for x in pending if x[0] <= t]):
            pending.remove(item)
            applied_leave = True
            blocked = False
        for item in [x for x in stream if x[0] <= t]:
            stream.remove(item)
            _, kind, payload = item
            if kind == "leave":
                if fail_first:
                    fail_first = False
                    pending.append((t + REDELIVER, kind, payload)); blocked = True
                else:
                    applied_leave = True
            elif kind == "echo":
                if blocked and variant != "applied_watermark":
                    continue                     # behind a pending entry: not contiguous, no advance
                watermark = t if variant == "arrival_watermark" else payload
        # pull path (D64): when the stream has stalled, fetch committed changes directly by sequence
        if variant not in ("no_watermark", "applied_watermark") and (watermark is None or watermark < t - 3 * P):
            if not stream or stream[0][0] > t + P:
                if s0 <= t:
                    applied_leave = True
                blocked = False; pending.clear()
                watermark = t
        # component clock: counts suspension unless the bad variant
        suspended = suspend[0] <= t < suspend[0] + suspend[1]
        if not (suspended and variant == "clock_stops"):
            comp_clock += 1
        if suspended:
            continue
        # renewal every 2 s
        if t % 2 == 0:
            fresh = watermark is not None and watermark >= t - D_SRC
            if variant == "no_watermark" or fresh:
                end = None if variant == "drop_end_date" else scheduled_end
                view = (comp_clock, not applied_leave, end)
        # a decision that needs the employee to be active
        if view is not None and rng.random() < 0.5:
            sent_local, active, end = view
            if comp_clock < sent_local + W and active and (end is None or t < end):
                decisions += 1
                if t > s0 + D_SRC + W:
                    fails.append("BOUND_SRC"); return
                if scheduled_end is not None and t >= scheduled_end:
                    fails.append("BOUND_END"); return


def main():
    variants = ["good", "no_watermark", "arrival_watermark", "applied_watermark", "clock_stops", "drop_end_date"]
    res = {}
    for v in variants:
        rng = random.Random(SEED)
        fails = []
        for _ in range(RUNS):
            run(rng, v, fails)
        res[v] = sorted(set(fails))
    print(f"good: {'ok' if not res['good'] else 'FAIL ' + str(res['good'])} (BOUND_SRC, BOUND_END over {RUNS} runs)")
    caught = True
    for v in variants[1:]:
        print(f"bad variant {v}: {'caught ' + str(res[v]) if res[v] else 'NOT CAUGHT'}")
        caught &= bool(res[v])
    if res["good"] or not caught:
        sys.exit(1)


if __name__ == "__main__":
    main()
