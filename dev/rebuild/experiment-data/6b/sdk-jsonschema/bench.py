"""be-sdk-python: what opening a security record costs, part by part, and fastjsonschema against jsonschema-rs on the
protocol's own schemas. Correctness first: on all 24 cases of the security-records vector both validators must judge
each record the same (the invalid cases that reach the schema). Then, for each valid case: canon.parse, the digest,
validate with fastjsonschema (the SDK today), validate with jsonschema-rs, and records.open_ as a whole (us, median of
7 groups of N).

    uv run --with jsonschema-rs==0.59.0 python -I bench.py   (in tools/be-sdk-python)
"""
import statistics
import sys
import time
from importlib.metadata import version

import fastjsonschema
import jsonschema_rs

from besdk import canon, protocol, records

N, R = 2000, 7


def per_us(fn):
    fn()
    out = []
    for _ in range(R):
        t = time.perf_counter()
        for _ in range(N):
            fn()
        out.append(1e6 * (time.perf_counter() - t) / N)
    return statistics.median(out), min(out), max(out)


def rs_validator(rt):
    return jsonschema_rs.Draft202012Validator(protocol.schema(rt))


def main():
    print(f"python {sys.version.split()[0]}, fastjsonschema {version('fastjsonschema')}, jsonschema-rs {version('jsonschema-rs')}")
    cases = protocol.vector("security-records")["cases"]
    fast_cache, rs_cache, disagree = {}, {}, 0
    for c in cases:
        rt, rec = c["record_type"], c["record"]
        try:
            records.validate(rt, rec)
            fast_ok = True
        except records.Invalid:
            fast_ok = False
        rs = rs_cache.setdefault(rt, rs_validator(rt))
        rs_ok = rs.is_valid(rec)
        if fast_ok != rs_ok:
            disagree += 1
            print(f"DISAGREE {c['id']} {rt}: fastjsonschema {fast_ok}, jsonschema-rs {rs_ok}")
        if c["valid"] and not (fast_ok and rs_ok):
            print(f"REFUSED A VALID CASE {c['id']} {rt}: fast {fast_ok} rs {rs_ok}")
    print(f"cases {len(cases)}, disagreements {disagree}")
    print(f"{'case':28} {'type':34} {'bytes':>6} {'parse':>8} {'digest':>8} {'fast':>8} {'rs':>8} {'open_':>8}  share of open_: fast / rs")
    for c in cases:
        if not c["valid"]:
            continue
        rt, rec = c["record_type"], c["record"]
        raw, digest = records.seal(rt, rec)
        v = canon.parse(raw)
        rs = rs_cache[rt]
        p = per_us(lambda: canon.parse(raw))[0]
        d = per_us(lambda: canon.digest_bytes(rt, records.MAJOR, raw))[0]
        f = per_us(lambda: records.validate(rt, v))[0]
        r = per_us(lambda: rs.validate(v))[0]
        o = per_us(lambda: records.open_(rt, raw, digest))[0]
        print(f"{c['id'][:28]:28} {rt:34} {len(raw):6d} {p:8.2f} {d:8.2f} {f:8.2f} {r:8.2f} {o:8.2f}  {100*f/o:5.1f}% / {100*r/(o-f+r):5.1f}%")


if __name__ == "__main__":
    main()
