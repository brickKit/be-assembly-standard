#!/usr/bin/env python3
"""Reference model for protocol 12: attachments and object storage.

Clients upload through a pre-signed URL to a staging key; the attachment component finalizes
(copies to an immutable final key and records the digest), a scanner scans, and downloads are
served from the final key. Concurrently: a client keeps writing to the staging key after
finalizing (the pre-signed URL is still valid), orphan cleanup runs, legal holds are placed,
attachments are detached and purged, and the parent record's permission is revoked.
Checks:

  SCAN_BOUND   bytes served for download are always the bytes that were scanned clean
  NO_DANGLING  an available attachment always has its object
  HOLD         an attachment under hold is never purged
  REVOKE_BOUND after a revocation at time t, no download happens later than t + link TTL

Bad variants (each must be caught): scan and serve the staging key; replace the file of an
attachment in place under the same key and keep the earlier scan result;
orphan cleanup decides by object age instead of checking metadata references; purge ignores holds; download links without an expiry.
"""
import random
import sys

SEED = 20261013
RUNS = 3000
TTL = 3


def run(rng, variant, fails):
    store = {}                 # key -> bytes
    att = None                 # dict(state, staging, final, digest, scanned_digest, held, session_open)
    links = []                 # (issued_at, expires_at)
    revoked_at = None
    now = 0
    for step in range(60):
        now += 1
        a = rng.choice(["create", "put", "put", "finalize", "scan", "download", "download", "download",
                        "link", "link", "revoke", "cleanup", "hold", "detach", "purge", "replace"])
        if a == "create" and att is None:
            att = dict(state="uploading", staging=f"stg/{step}", final=None, digest=None,
                       scanned=None, held=False, session_open=True)
        elif a == "put" and att and att["session_open"]:
            # the pre-signed PUT stays usable until the session expires, even after finalize
            store[att["staging"]] = rng.choice(["clean", "clean", "virus"])
            if rng.random() < 0.1:
                att["session_open"] = False
        elif a == "finalize" and att and att["state"] in ("uploading", "pending_scan") and att["staging"] in store:
            content = store[att["staging"]]
            if variant == "staging_served":
                att["final"] = att["staging"]
            else:
                key = f"fin/{step}"
                store[key] = content                      # server-side copy to an immutable key
                att["final"] = key
            att["digest"] = content
            att["state"] = "pending_scan"
        elif a == "replace" and att and att["state"] == "available" and att["session_open"] and att["staging"] in store:
            # the user replaces the file of an existing attachment
            content = store[att["staging"]]
            if variant == "digest_unbound":
                store[att["final"]] = content            # same key, scan status kept
            else:
                key = f"fin/r{step}"
                store[key] = content
                att.update(final=key, digest=content, scanned=None, state="pending_scan")
        elif a == "scan" and att and att["state"] == "pending_scan" and att["final"] in store:
            content = store[att["final"]]
            if variant != "digest_unbound" and content != att["digest"]:
                att["state"] = "quarantined"; continue
            if content == "clean":
                att["state"] = "available"; att["scanned"] = content
            else:
                att["state"] = "quarantined"
        elif a == "link" and att and att["state"] == "available":
            if revoked_at is None:
                links.append((now, None if variant == "no_expiry" else now + TTL))
        elif a == "revoke" and revoked_at is None and rng.random() < 0.15:
            revoked_at = now
        elif a == "download" and links and att and att["state"] == "available":
            issued, exp = rng.choice(links)
            if exp is not None and now > exp:
                continue
            if revoked_at is not None and now > revoked_at + TTL:
                fails.append("REVOKE_BOUND"); return
            obj = store.get(att["final"])
            if obj is None:
                fails.append("NO_DANGLING"); return
            if obj != att["scanned"] or obj != "clean":
                fails.append("SCAN_BOUND"); return
        elif a == "cleanup":
            referenced = {att["final"]} if att and att["final"] else set()
            for k in list(store):
                if k.startswith("fin/") and k not in referenced:
                    del store[k]
                if k.startswith("stg/") and att and k == att["staging"] and not att["session_open"] and att["state"] != "uploading":
                    del store[k]
            if variant == "cleanup_by_age" and att and att["state"] == "available" and rng.random() < 0.3:
                store.pop(att["final"], None)            # treated as orphan by an age rule
        elif a == "hold" and att:
            att["held"] = rng.random() < 0.5
        elif a == "detach" and att and att["state"] == "available":
            att["state"] = "detached"
        elif a == "purge" and att and att["state"] == "detached":
            if att["held"] and variant != "purge_ignores_hold":
                continue
            if att["held"]:
                fails.append("HOLD"); return
            store.pop(att["final"], None); att = None
        if att and att["state"] == "available" and att["final"] not in store:
            fails.append("NO_DANGLING"); return


def main():
    variants = ["good", "staging_served", "digest_unbound", "cleanup_by_age", "purge_ignores_hold", "no_expiry"]
    res = {}
    for v in variants:
        rng = random.Random(SEED)
        fails = []
        for _ in range(RUNS):
            run(rng, v, fails)
        res[v] = sorted(set(fails))
    print(f"good: {'ok' if not res['good'] else 'FAIL ' + str(res['good'])} (SCAN_BOUND, NO_DANGLING, HOLD, REVOKE_BOUND over {RUNS} runs)")
    caught = True
    for v in variants[1:]:
        print(f"bad variant {v}: {'caught ' + str(res[v]) if res[v] else 'NOT CAUGHT'}")
        caught &= bool(res[v])
    if res["good"] or not caught:
        sys.exit(1)


if __name__ == "__main__":
    main()
