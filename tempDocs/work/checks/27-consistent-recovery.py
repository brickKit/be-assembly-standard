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
  REVOKED      a revocation made after T is still in force after recovery

Bad variants (each must be caught): keep the old stream (ghost events delivered); recreate the
stream without republishing; republish only a fixed time window instead of from each
consumer's recorded progress; resend commands found in "sending"
without querying the provider; restore security state from the backup only.
"""
import random
import sys

SEED = 20261013
RUNS = 3000
WINDOW = 10            # the fixed window of the bad variant


def run(rng, variant, fails):
    t = 0
    db = dict(facts=set(), outbox={}, inbox=set(), applied=set(), cmds={}, revoked=set())
    stream = []                                   # (event_id, publish_time)
    provider = {}                                 # cmd -> times executed
    evidence = set()                              # independent security evidence log
    snapshots = {}

    def snapshot():
        return dict(facts=set(db["facts"]), outbox={k: dict(v) for k, v in db["outbox"].items()},
                    inbox=set(db["inbox"]), applied=set(db["applied"]),
                    cmds={k: v for k, v in db["cmds"].items()}, revoked=set(db["revoked"]))

    for step in range(40):
        t += 1
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
        elif r < 0.85:                                         # security revocation
            g = f"g{rng.randint(0, 3)}"
            db["revoked"].add(g); evidence.add(g)
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
    # security: replay the evidence log after the restore point
    if variant != "backup_security_only":
        db["revoked"] |= evidence
    # consumer drains the stream
    for e, _ in stream:
        if e not in db["inbox"]:
            db["inbox"].add(e); db["applied"].add(e)

    if db["applied"] - db["facts"]:
        fails.append("NO_GHOST"); return
    if db["facts"] - db["applied"]:
        fails.append("NO_LOSS"); return
    if any(n > 1 for n in provider.values()):
        fails.append("NO_REEXEC"); return
    if set(provider) - set(db["cmds"]):
        fails.append("EXT_KNOWN"); return
    if evidence - db["revoked"]:
        fails.append("REVOKED"); return


def main():
    variants = ["good", "keep_stream", "no_republish", "fixed_window", "resend_without_query", "backup_security_only"]
    res = {}
    for v in variants:
        rng = random.Random(SEED)
        fails = []
        for _ in range(RUNS):
            run(rng, v, fails)
        res[v] = sorted(set(fails))
    print(f"good: {'ok' if not res['good'] else 'FAIL ' + str(res['good'])} (NO_GHOST, NO_LOSS, NO_REEXEC, EXT_KNOWN, REVOKED over {RUNS} runs)")
    caught = True
    for v in variants[1:]:
        print(f"bad variant {v}: {'caught ' + str(res[v]) if res[v] else 'NOT CAUGHT'}")
        caught &= bool(res[v])
    if res["good"] or not caught:
        sys.exit(1)


if __name__ == "__main__":
    main()
