"""Given pkgrefs output (file -> files it uses) and a partition (package -> files), print the package graph and its
cycles. Usage: partition.py <pkgrefs.txt> '<pkg>:f1,f2;<pkg>:...'"""
import re, sys, itertools
deps = {}
cur = None
for line in open(sys.argv[1]):
    m = re.match(r"^== (\S+)", line)
    if m:
        cur = m.group(1); deps[cur] = set(); continue
    m = re.match(r"^\s+(\S+\.go): (.*)", line)
    if m and cur:
        names = set(m.group(2).split()) - {"New"}
        if names:
            deps[cur].add(m.group(1))
part = {}
for spec in sys.argv[2].split(";"):
    p, files = spec.split(":")
    for f in files.split(","):
        part[f.strip()] = p
missing = [f for f in deps if f not in part]
if missing:
    print("unassigned:", missing)
g = {}
for f, ds in deps.items():
    pf = part.get(f, "?")
    for d in ds:
        pd = part.get(d, "?")
        if pd != pf:
            g.setdefault(pf, {}).setdefault(pd, set()).add(f"{f}->{d}")
for p in sorted(g):
    print(p, "->", ", ".join(f"{q}({len(v)})" for q, v in sorted(g[p].items())))
# cycles of length 2 and 3
pk = sorted(set(part.values()))
for a, b in itertools.combinations(pk, 2):
    if b in g.get(a, {}) and a in g.get(b, {}):
        print("CYCLE", a, "<->", b, ":", sorted(g[a][b])[:6], "|", sorted(g[b][a])[:6])
