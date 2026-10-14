#!/usr/bin/env python3
"""Reference model for protocol 15: restoring a whole deployment to a point T.

A producer writes facts and outbox rows; a relay publishes them to a stream; a consumer applies
them through an inbox. An adapter executes external commands (an external provider keeps its
own record). Security revocations are written to the database and to an independent evidence
log. At a random time the deployment is restored to an earlier point T. Checks after recovery:

  NO_GHOST     the consumer has applied no event whose source fact does not exist after restore
  NO_LOSS      every source fact that exists after restore has been applied by the consumer
  NO_REEXEC    no external command is executed twice by the provider
  EXT_KNOWN    every command the provider executed is known locally after recovery
  REVOKED      a subject whose last effective change before the failure was a revocation is
               revoked after recovery (unless that record was a declared loss)
  NO_OVER_DESTROY  nothing is destroyed after recovery that was never destroyed
  DESTROYED    a destruction that took effect is re-executed or listed for review
  FLAGGED      a subject left more restricted than it really was is flagged, listed for review or
               covered by a declared loss (over-tightening is allowed only when visible)

Security changes (revocations, grants, destructions) are written in two parts: an intent outside
the local transaction (to the evidence store; if unreachable, the full record in an external alert;
if both fail, a declared loss), then the local commit, whose conclusion ("in effect" or
"cancelled") reaches the evidence store through the outbox. The process can crash before or after
the commit, the conclusion can be undelivered, and an intent can be written before T and
committed after it. Recovery replays each record not reflected in the restored database:
confirmed ones are re-executed, cancelled ones ignored, intent-only revocations executed and
flagged, intent-only grants and destructions listed for review.

Bad variants (each must be caught): keep the old stream (ghost events delivered); recreate the
stream without republishing; republish only a fixed time window instead of from each
consumer's recorded progress; no consumer repair for facts beyond the republish retention;
records written while the evidence store was unavailable are not carried in an alert;
commit before writing the intent (a crash in between loses it); resend commands found in
"sending" without querying the provider; restore security state from the backup only; choose
the records to replay by comparing their time with T; execute intent-only destructions; execute
intent-only revocations without flagging them.
"""
import random
import sys

SEED = 20261013
RUNS = 3000
WINDOW = 4             # the fixed window of the bad variant (shorter than the retention)
CAP = 8                # published outbox rows are kept this long for republishing


def run(rng, variant, fails):
    t = 0
    subjects = [f"g{i}" for i in range(4)]
    db = dict(facts=set(), outbox={}, inbox=set(), applied=set(), cmds={},
              access={g: "granted" for g in subjects}, destroyed=set(), reflected=set())
    stream = []                                   # (event_id, publish_time)
    provider = {}                                 # cmd -> times executed
    records = {}                                  # security records outside the deployment:
    # id -> dict(kind, target, at, channel: evidence / alert / lost, status: intent / confirmed / cancelled)
    real = dict(access={g: "granted" for g in subjects}, destroyed=set(), last={})   # what really took effect
    pending = []                                  # intents written, local commit not yet attempted
    snapshots = {}

    def snapshot():
        return dict(facts=set(db["facts"]), outbox={k: dict(v) for k, v in db["outbox"].items()},
                    inbox=set(db["inbox"]), applied=set(db["applied"]),
                    cmds={k: v for k, v in db["cmds"].items()}, access=dict(db["access"]),
                    destroyed=set(db["destroyed"]), reflected=set(db["reflected"]))

    def write_intent(rid, kind, target):
        ev_up, alert_up = rng.random() < 0.8, rng.random() < 0.9
        channel = "evidence" if ev_up else "alert" if alert_up else "lost"
        records[rid] = dict(kind=kind, target=target, at=t, channel=channel, status="intent")

    def commit(rid, kind, target):
        u = rng.random()
        if u < 0.12:                                           # commit fails (conflict, check)
            if rng.random() < 0.8:
                records.get(rid, {})["status"] = "cancelled"   # conclusion delivered via the outbox
            return
        if u < 0.2:
            return                                             # crash before the commit: no effect
        if kind == "destroy":
            db["destroyed"].add(target); real["destroyed"].add(target)
        else:
            db["access"][target] = real["access"][target] = "revoked" if kind == "revoke" else "granted"
            real["last"][target] = rid
        db["reflected"].add(rid)
        if rid in records and rng.random() < 0.8:
            records[rid]["status"] = "confirmed"               # conclusion delivered via the outbox

    for step in range(40):
        t += 1
        if pending:
            commit(*pending.pop())
        r = rng.random()
        if r < 0.25:                                           # producer commits a fact + outbox row
            e = f"e{step}"
            db["facts"].add(e); db["outbox"][e] = dict(published=None)
        elif r < 0.45:                                         # relay publishes
            for e, row in db["outbox"].items():
                if row["published"] is None:
                    row["published"] = t; stream.append((e, t)); break
        elif r < 0.65 and stream:                              # consumer applies the next event
            for e, _ in stream:
                if e not in db["inbox"]:
                    db["inbox"].add(e); db["applied"].add(e); break
        elif r < 0.78:                                         # adapter sends an external command
            c = f"c{step}"
            db["cmds"][c] = "sending"
            if rng.random() < 0.7:
                provider[c] = provider.get(c, 0) + 1          # provider executed it
                if rng.random() < 0.6:
                    db["cmds"][c] = "succeeded"
        elif r < 0.85 and not pending:                         # a security change
            rid = f"s{step}"
            u = rng.random()
            kind = "revoke" if u < 0.5 else "grant" if u < 0.75 else "destroy"
            target = rng.choice(subjects) if kind != "destroy" else f"o{step}"
            if variant == "commit_then_evidence":
                commit(rid, kind, target)                      # committed first ...
                if rng.random() >= 0.15:                       # ... unless it crashes before the intent
                    write_intent(rid, kind, target)
                    if rid in db["reflected"] and rng.random() < 0.8:
                        records[rid]["status"] = "confirmed"
            else:
                write_intent(rid, kind, target)                # intent first, outside the transaction
                pending.append((rid, kind, target))            # committed in this or a later step
                if rng.random() < 0.5:
                    commit(*pending.pop())
        for e, row in list(db["outbox"].items()):              # republish retention has a fixed cap
            if row["published"] is not None and t - row["published"] > CAP:
                del db["outbox"][e]
        snapshots[t] = snapshot()

    # restore the whole deployment to T
    T = rng.randint(1, t)
    db = snapshots[T]
    if variant == "keep_stream":
        pass                                                   # ghosts published after T stay in the stream
    else:
        stream = []                                            # streams are recreated empty
        if variant == "fixed_window":
            for e, row in db["outbox"].items():
                if row["published"] is not None and row["published"] > T - WINDOW:
                    stream.append((e, row["published"]))      # a fixed time window only
        elif variant != "no_republish":
            # republish from each consumer's progress recorded in its restored database
            for e, row in db["outbox"].items():
                if row["published"] is not None and e not in db["inbox"]:
                    stream.append((e, row["published"]))
        for e, row in db["outbox"].items():
            if row["published"] is None:
                row["published"] = T; stream.append((e, T))
    # external reconciliation: query the provider before anything is resent
    for c, state in list(db["cmds"].items()):
        if state == "sending":
            if variant == "resend_without_query":
                provider[c] = provider.get(c, 0) + 1; db["cmds"][c] = "succeeded"
            elif c in provider:
                db["cmds"][c] = "succeeded"
            else:
                db["cmds"][c] = "failed"
    if variant != "resend_without_query":
        for c in provider:                                     # provider has it, we do not: import
            if c not in db["cmds"]:
                db["cmds"][c] = "succeeded"
    # security: replay each record not reflected in the restored database
    flagged, review = set(), set()
    if variant != "backup_security_only":
        for rid, rec in sorted(records.items(), key=lambda x: int(x[0][1:])):
            if rec["channel"] == "lost" or (rec["channel"] == "alert" and variant == "no_flag"):
                continue
            if variant == "time_select":
                if rec["at"] <= T:
                    continue
            elif rid in db["reflected"]:
                continue
            kind, target, status = rec["kind"], rec["target"], rec["status"]
            if status == "cancelled":
                continue
            if status == "intent" and kind == "revoke" and variant != "unflagged_intent":
                flagged.add(target)
            if status == "intent" and (kind == "grant" or (kind == "destroy" and variant != "destroy_on_intent")):
                review.add(target)
                continue
            if kind == "destroy":
                db["destroyed"].add(target)
            else:
                db["access"][target] = "revoked" if kind == "revoke" else "granted"
            db["reflected"].add(rid)
    # consumer drains the stream
    for e, _ in stream:
        if e not in db["inbox"]:
            db["inbox"].add(e); db["applied"].add(e)
    # beyond the republish retention: the consumer repairs only the facts whose outbox rows
    # were already removed by the retention cap at T (the same rule for every variant)
    if variant != "no_consumer_repair":
        for e in db["facts"] - db["applied"]:
            if e not in db["outbox"]:
                db["inbox"].add(e); db["applied"].add(e)

    if db["applied"] - db["facts"]:
        fails.append("NO_GHOST"); return
    if db["facts"] - db["applied"]:
        fails.append("NO_LOSS"); return
    if any(n > 1 for n in provider.values()):
        fails.append("NO_REEXEC"); return
    if set(provider) - set(db["cmds"]):
        fails.append("EXT_KNOWN"); return
    lost = {r["target"] for r in records.values() if r["channel"] == "lost"}
    for g, rid in real["last"].items():
        if real["access"][g] == "revoked" and records.get(rid, {}).get("channel") != "lost" \
                and db["access"][g] != "revoked":
            fails.append("REVOKED"); return
    if db["destroyed"] - real["destroyed"]:
        fails.append("NO_OVER_DESTROY"); return
    for o in real["destroyed"]:
        if records.get(f"s{o[1:]}", {}).get("channel") != "lost" and o not in db["destroyed"] | review:
            fails.append("DESTROYED"); return
    for g in subjects:
        if db["access"][g] == "revoked" and real["access"][g] == "granted" and g not in flagged | review | lost:
            fails.append("FLAGGED"); return


def main():
    variants = ["good", "keep_stream", "no_republish", "fixed_window", "no_consumer_repair", "resend_without_query", "backup_security_only", "no_flag", "commit_then_evidence", "time_select", "destroy_on_intent",
                "unflagged_intent"]
    res = {}
    for v in variants:
        rng = random.Random(SEED)
        fails = []
        for _ in range(RUNS):
            run(rng, v, fails)
        res[v] = sorted(set(fails))
    print(f"good: {'ok' if not res['good'] else 'FAIL ' + str(res['good'])} (NO_GHOST, NO_LOSS, NO_REEXEC, EXT_KNOWN, REVOKED, NO_OVER_DESTROY, DESTROYED, FLAGGED over {RUNS} runs)")
    caught = True
    for v in variants[1:]:
        print(f"bad variant {v}: {'caught ' + str(res[v]) if res[v] else 'NOT CAUGHT'}")
        caught &= bool(res[v])
    if res["good"] or not caught:
        sys.exit(1)


if __name__ == "__main__":
    main()
