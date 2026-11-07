"""Like partition.py, but per name, with name moves. Usage:
partition2.py <pkgrefs.txt> '<pkg>:f1,f2;...' 'name=pkg,name=pkg' [ignore-files]"""
import re, sys, itertools
uses = {}  # file -> [(deffile, name)]
cur = None
for line in open(sys.argv[1]):
    m = re.match(r"^== (\S+)", line)
    if m:
        cur = m.group(1); uses[cur] = []; continue
    m = re.match(r"^\s+(\S+\.go): (.*)", line)
    if m and cur:
        for n in m.group(2).split():
            if n not in ("New", "Module"):
                uses[cur].append((m.group(1), n))
part = {}
for spec in sys.argv[2].split(";"):
    p, files = spec.split(":")
    for f in files.split(","):
        part[f.strip()] = p
moves = {}
if len(sys.argv) > 3 and sys.argv[3]:
    for kv in sys.argv[3].split(","):
        k, v = kv.split("=")
        moves[k] = v
ign = set(sys.argv[4].split(",")) if len(sys.argv) > 4 else set()
missing = [f for f in uses if f not in part and f not in ign]
if missing:
    print("unassigned:", missing)
g = {}
for f, us in uses.items():
    if f in ign: continue
    pf = part.get(f, "?")
    for d, n in us:
        pd = moves.get(n, part.get(d, "?"))
        if pd != pf:
            g.setdefault(pf, {}).setdefault(pd, set()).add(f"{f}->{n}")
for p in sorted(g):
    print(p, "->", ", ".join(f"{q}({len(v)})" for q, v in sorted(g[p].items())))
pk = sorted(set(part.values()) | set(moves.values()))
for a, b in itertools.combinations(pk, 2):
    if b in g.get(a, {}) and a in g.get(b, {}):
        print("CYCLE", a, "<->", b, ":", sorted(g[a][b])[:8], "|", sorted(g[b][a])[:8])
# longer cycles via DFS
import collections
adj = {p: set(g.get(p, {})) for p in pk}
def scc():
    idx, low, st, on, out = {}, {}, [], set(), []
    c = [0]
    def v(n):
        idx[n] = low[n] = c[0]; c[0] += 1; st.append(n); on.add(n)
        for w in adj.get(n, ()):
            if w not in idx: v(w); low[n] = min(low[n], low[w])
            elif w in on: low[n] = min(low[n], idx[w])
        if low[n] == idx[n]:
            comp = []
            while True:
                w = st.pop(); on.discard(w); comp.append(w)
                if w == n: break
            if len(comp) > 1: out.append(comp)
    for n in pk:
        if n not in idx: v(n)
    return out
for comp in scc():
    print("SCC", comp)
