#!/usr/bin/env python3
"""Check the boundary cards' required dependencies and the customer combinations.

Reads every `## <component>` section in tempDocs/components/*.md, takes the component IDs that
appear in its "必需依赖" row (plus 身份 -> infra/iam-casdoor, 授权 -> infra/authz), and checks:

  ACYCLIC   the required-dependency graph has no cycle (BrickKit rejects a required cycle)
  KNOWN     every required dependency names a component that has a card
  CLOSURE   every combination in the README table lists the transitive closure of the
            required dependencies of its own listed components
  BASELINE  every combination contains the deployment-level components every formal
            deployment needs: one identity member (any infra/iam-*), authorization, audit
            (protocol 03)

Exit status is non-zero when a check fails.
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..", "components")
ID = re.compile(r"\b((?:mdm|erp|crm|hrm|prj|ana|infra|integration|frontend)/[a-z0-9<>\-]+)")
ALIASES = {"身份": "infra/iam-casdoor", "授权": "infra/authz"}   # 身份 stands for the identity family; Casdoor is its representative
BASELINE = {"infra/authz", "infra/audit"}
IDENTITY = re.compile(r"^infra/iam-")


def cards():
    deps = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "*.md"))):
        name = os.path.basename(path)
        if name in ("README.md", "catalog.md", "selection-map.md"):
            continue
        text = open(path, encoding="utf-8").read()
        for sec in re.split(r"^## ", text, flags=re.M)[1:]:
            head = sec.split("\n", 1)[0]
            ids = ID.findall(head)
            if not ids:
                continue
            m = re.search(r"^\| 必需依赖 \| (.*) \|$", sec, re.M)
            req = set()
            if m:
                cell = m.group(1)
                req |= set(ID.findall(cell))
                for word, cid in ALIASES.items():
                    if re.search(r"(^|[、，（ ])" + word + r"($|[、，（）(])", cell):
                        req.add(cid)
            for cid in ids:
                deps[cid] = req - {cid}
    return deps


def cycle(deps):
    state, stack = {}, []
    def visit(n):
        state[n] = 1; stack.append(n)
        for d in deps.get(n, ()):
            if state.get(d) == 1:
                return stack[stack.index(d):] + [d]
            if d not in state:
                c = visit(d)
                if c:
                    return c
        state[n] = 2; stack.pop()
        return None
    for n in list(deps):
        if n not in state:
            c = visit(n)
            if c:
                return c
    return None


def closure(deps, roots):
    out, todo = set(), list(roots)
    while todo:
        n = todo.pop()
        if n in out:
            continue
        out.add(n)
        todo += list(deps.get(n, ()))
    return out


def combos():
    text = open(os.path.join(ROOT, "README.md"), encoding="utf-8").read()
    sec = text.split("## 客户组合的闭包", 1)[1].split("\n## ", 1)[0]
    rows = {}
    for line in sec.splitlines():
        if not line.startswith("| ") or line.startswith("| 组合") or line.startswith("| ---"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        name, req = cells[0], cells[1]
        listed = set(ID.findall(req))
        for other, ids in list(rows.items()):
            if req.startswith(other + "的全部"):
                listed |= ids
        rows[name] = listed
    return rows


def main():
    deps = cards()
    fails = []
    c = cycle(deps)
    if c:
        fails.append("ACYCLIC: " + " -> ".join(c))
    for n, ds in sorted(deps.items()):
        for d in ds:
            if d not in deps and "<" not in d:
                fails.append(f"KNOWN: {n} requires {d}, which has no card")
    for name, listed in combos().items():
        missing = closure(deps, listed) - listed
        if missing:
            fails.append(f"CLOSURE: {name} misses {sorted(missing)}")
        if BASELINE - listed:
            fails.append(f"BASELINE: {name} misses {sorted(BASELINE - listed)}")
        if not any(IDENTITY.match(c) for c in listed):
            fails.append(f"BASELINE: {name} has no identity member (infra/iam-*)")
    print(f"{len(deps)} components with cards; {sum(len(v) for v in deps.values())} required edges; {len(combos())} combinations")
    for f in fails:
        print(f)
    if fails:
        sys.exit(1)
    print("ACYCLIC, KNOWN, CLOSURE, BASELINE: ok")


if __name__ == "__main__":
    main()
