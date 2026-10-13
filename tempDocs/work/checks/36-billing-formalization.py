#!/usr/bin/env python3
"""Reference model for protocol 05: confirming a claim before numbering a formal invoice.

Drafts claim billable quantity at the source; unconfirmed claims expire. The billing component
turns a draft into a formal (numbered) invoice and then tells the source to formalize. The
source can be unreachable for long periods. Check:

  NO_OVERLAP  the quantity covered by formal invoices never exceeds the billable quantity
  LIVENESS    once the source is reachable, every confirmed claim ends billed or released
              (confirm replies can be lost and are retried with the same claim id; drafts can be
              abandoned after confirming)

Bad variants (each must be caught): number the formal invoice first and formalize afterwards
(the claim can expire in between and be re-claimed by another draft); confirmed claims still
expire automatically; abandoned confirmed claims are never released by recovery.
"""
import random
import sys

SEED = 20261013
RUNS = 3000
EXPIRY = 7


def run(rng, variant, fails):
    billable = 10
    claims = {}              # id -> dict(qty, state, at)  state: held / confirmed / billed / released
    formal = []              # (invoice, claim id, qty)
    pending_formalize = []   # claim ids whose invoice is numbered but not yet formalized at the source
    t = 0
    nxt = 0
    abandoned = []           # confirmed claims whose draft was abandoned before numbering
    for step in range(80):
        t += 1
        source_up = rng.random() < 0.6
        # expiry at the source
        for c in claims.values():
            expires = c["state"] == "held" or (variant == "confirmed_expires" and c["state"] == "confirmed")
            if expires and t - c["at"] > EXPIRY:
                c["state"] = "released"
        used = sum(c["qty"] for c in claims.values() if c["state"] in ("held", "confirmed", "billed"))
        r = rng.random()
        if r < 0.35 and source_up and used < billable:        # a draft claims what is left
            q = billable - used
            cid = f"c{nxt}"; nxt += 1
            claims[cid] = dict(qty=q, state="held", at=t)
        elif r < 0.7:                                           # billing numbers an invoice for a draft
            held = [cid for cid, c in claims.items() if c["state"] == "held" and cid not in pending_formalize]
            if not held:
                continue
            cid = rng.choice(held)
            if variant == "number_first":
                formal.append((len(formal), cid, claims[cid]["qty"]))
                pending_formalize.append(cid)
            else:
                if not source_up:
                    continue                                    # cannot confirm; do not number
                if claims[cid]["state"] != "held":
                    continue                                    # expired: no number
                claims[cid]["state"] = "confirmed"
                if rng.random() < 0.2:
                    # the confirm reply is lost: retry with the same claim id (idempotent: confirmed again)
                    if claims[cid]["state"] != "confirmed":
                        continue
                if rng.random() < 0.1:
                    abandoned.append(cid)                       # the draft is abandoned after confirming
                    continue
                formal.append((len(formal), cid, claims[cid]["qty"]))
                pending_formalize.append(cid)
        elif source_up and pending_formalize:                   # formalize at the source (retries)
            cid = pending_formalize.pop(0)
            c = claims[cid]
            if c["state"] in ("held", "confirmed"):
                c["state"] = "billed"
            # an expired claim is rejected: the numbered invoice becomes "basis invalid"
        if sum(q for _, _, q in formal) > billable:
            fails.append("NO_OVERLAP"); return
        # recovery work item: release abandoned confirmed claims (the source is reachable)
        if variant != "no_recovery" and source_up:
            for cid in list(abandoned):
                claims[cid]["state"] = "released"; abandoned.remove(cid)
    # liveness: with the source reachable, recovery ends every confirmed claim
    for _ in range(3):
        if variant != "no_recovery":
            for cid in list(abandoned):
                claims[cid]["state"] = "released"; abandoned.remove(cid)
        for cid in list(pending_formalize):
            pending_formalize.remove(cid)
            if claims[cid]["state"] in ("held", "confirmed"):
                claims[cid]["state"] = "billed"
    if any(c["state"] == "confirmed" for c in claims.values()):
        fails.append("LIVENESS")


def main():
    variants = ["good", "number_first", "confirmed_expires", "no_recovery"]
    res = {}
    for v in variants:
        rng = random.Random(SEED)
        fails = []
        for _ in range(RUNS):
            run(rng, v, fails)
        res[v] = sorted(set(fails))
    print(f"good: {'ok' if not res['good'] else 'FAIL ' + str(res['good'])} (NO_OVERLAP, LIVENESS over {RUNS} runs)")
    caught = True
    for v in variants[1:]:
        print(f"bad variant {v}: {'caught ' + str(res[v]) if res[v] else 'NOT CAUGHT'}")
        caught &= bool(res[v])
    if res["good"] or not caught:
        sys.exit(1)


if __name__ == "__main__":
    main()
