#!/usr/bin/env python3
"""Reference model for protocol 05: confirming a claim before numbering a formal invoice.

Drafts claim billable quantity at the source; unconfirmed claims expire. The billing component
turns a draft into a formal (numbered) invoice and then tells the source to formalize. The
source can be unreachable for long periods. Check:

  NO_OVERLAP  the quantity covered by formal invoices never exceeds the billable quantity

Bad variants (each must be caught): number the formal invoice first and formalize afterwards
(the claim can expire in between and be re-claimed by another draft); confirmed claims still
expire automatically.
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


def main():
    variants = ["good", "number_first", "confirmed_expires"]
    res = {}
    for v in variants:
        rng = random.Random(SEED)
        fails = []
        for _ in range(RUNS):
            run(rng, v, fails)
        res[v] = sorted(set(fails))
    print(f"good: {'ok' if not res['good'] else 'FAIL ' + str(res['good'])} (NO_OVERLAP over {RUNS} runs)")
    caught = True
    for v in variants[1:]:
        print(f"bad variant {v}: {'caught ' + str(res[v]) if res[v] else 'NOT CAUGHT'}")
        caught &= bool(res[v])
    if res["good"] or not caught:
        sys.exit(1)


if __name__ == "__main__":
    main()
