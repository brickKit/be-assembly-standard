#!/usr/bin/env python3
"""Reference model for protocol 14: counters allocated in a database and compared elsewhere carry
the database's epoch.

A database allocates two counters: the claim generation of a work item (protocol 01) and the
security revision of an authorization view (security 03). It replicates asynchronously; a failover
loses the last few commits, so the new primary allocates the lost values again for other content.
The epoch (deployment recovery generation, timeline) grows at every failover. Checks:

  ONE_HOLDER  after a failover, a worker that held a claim lost with the old primary cannot renew
              or commit while the new holder holds the item (no two holders)
  NO_STALE    a component holding a view revision never hears "still current" for a revision
              whose content is not the current one

Bad variants (each must be caught): claims compare the generation only; view checks compare the
revision only.
"""
import random
import sys

SEED = 20261013
RUNS = 3000


def run(rng, variant, fails):
    epoch = 0
    gen = 0                       # work item generation in the database
    rev = 0                       # security revision in the database
    content = {0: "v0"}           # revision -> content at that revision (current epoch)
    log = []                      # committed changes since the last replicated point: ("gen"|"rev", value)
    workers = {}                  # worker -> (epoch, generation) it believes it holds
    view = None                   # (epoch, revision, content) the component holds
    for step in range(60):
        r = rng.random()
        if r < 0.25:                                          # a worker claims the item
            gen += 1
            w = f"w{step}"
            workers = {w: (epoch, gen)}                       # earlier holders are taken over
            log.append(("gen", gen))
        elif r < 0.5:                                         # a security change
            rev += 1
            content[rev] = f"c{step}"
            log.append(("rev", rev))
        elif r < 0.65:                                        # the component checks its view
            if view is None:
                view = (epoch, rev, content[rev])
            else:
                same = view[1] == rev if variant == "revision_only" else (view[0], view[1]) == (epoch, rev)
                if same:
                    if view[2] != content[rev]:
                        fails.append("NO_STALE"); return      # "still current" for other content
                else:
                    view = (epoch, rev, content[rev])
        elif r < 0.75:                                        # replication catches up
            log = []
        elif r < 0.82 and log:                                # asynchronous failover
            lost = log[-rng.randint(1, len(log)):]
            for kind, value in lost:
                if kind == "gen":
                    gen = min(gen, value - 1)
                else:
                    rev = min(rev, value - 1)
                    content = {k: v for k, v in content.items() if k <= rev}
            epoch += 1
            log = []
            # a worker whose claim was lost still believes it holds the item; someone claims again
            if rng.random() < 0.7:
                gen += 1
                workers[f"n{step}"] = (epoch, gen)
                log.append(("gen", gen))
        # renewals: each worker that believes it holds the item renews now and then
        for w, (ep, g) in list(workers.items()):
            if rng.random() < 0.5:
                ok = g == gen if variant == "generation_only" else (ep, g) == (epoch, gen)
                if not ok:
                    del workers[w]                            # renewal refused: it stops
        holders = [w for w, (ep, g) in workers.items()
                   if (g == gen if variant == "generation_only" else (ep, g) == (epoch, gen))]
        if len(holders) > 1:
            fails.append("ONE_HOLDER"); return


def main():
    variants = ["good", "generation_only", "revision_only"]
    res = {}
    for v in variants:
        rng = random.Random(SEED)
        fails = []
        for _ in range(RUNS):
            run(rng, v, fails)
        res[v] = {f: fails.count(f) for f in sorted(set(fails))}
    print(f"good: {'ok' if not res['good'] else 'FAIL ' + str(res['good'])} (ONE_HOLDER, NO_STALE over {RUNS} runs)")
    caught = True
    for v in variants[1:]:
        print(f"bad variant {v}: {'caught ' + str(res[v]) if res[v] else 'NOT CAUGHT'}")
        caught &= bool(res[v])
    if res["good"] or not caught:
        sys.exit(1)


if __name__ == "__main__":
    main()
