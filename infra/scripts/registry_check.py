#!/usr/bin/env python3
"""Consistency check of registry/ports.tsv and registry/schemas.tsv (make registry-check).

Replaces the old be-ops check, whose fixed count of 62 components belonged to the old catalogue. Rules:
  1. ports are pairwise distinct, except port 80 (frontends and gateways) and out-of-band containers (_infra-*)
     that replace one another;
  2. only frontends and out-of-band gateways use port 80;
  3. every schemas.tsv row has a ports.tsv row;
  4. schema = repo with "-" turned into "_"; the runtime role (column `role`) = schema + "_rw";
     the owner role is not listed: it is always schema + "_owner" (protocol 14);
  5. the shell column of ports.tsv matches shell_login_role of schemas.tsv (go-core <-> shell_go_core);
  6. a retired row (note starting with "retired") stays: its name and ports are never handed out again.
Identity columns are append-only; that is checked against git by `make registry-diff`, not here.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def rows(name, width):
    out = []
    for n, line in enumerate((ROOT / "registry" / name).read_text().splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        cols = line.split("\t")
        if len(cols) != width:
            sys.exit(f"✗ {name}:{n}: {len(cols)} columns, expected {width}")
        out.append(cols)
    return out


def main():
    ports = rows("ports.tsv", 6)      # repo, component_id, http_port, grpc_port, shell, note
    schemas = rows("schemas.tsv", 4)  # repo, schema, role (runtime role), shell_login_role
    errs = []

    usage = {}
    for repo, _, http, grpc, _, _ in ports:
        for p in (http, grpc):
            if p not in ("-", "80"):
                usage.setdefault(p, []).append(repo)
    for p, repos in sorted(usage.items()):
        if len(repos) > 1 and any(not r.startswith("_infra-") for r in repos):
            errs.append(f"port {p} used by {' '.join(repos)}")

    for repo, _, http, _, _, _ in ports:
        if http == "80" and not (repo.startswith("frontend-") or repo.startswith("_infra-")):
            errs.append(f"{repo} uses port 80 (only frontends and out-of-band gateways may)")

    seen = {}
    for repo, cid, *_ in ports:
        if repo in seen:
            errs.append(f"ports.tsv lists {repo} twice")
        seen[repo] = cid

    shell_of = {r[0]: r[4] for r in ports}
    for repo, schema, role, login in schemas:
        if repo not in seen:
            errs.append(f"schemas.tsv: {repo} has no ports.tsv row")
        want = repo.replace("-", "_")
        if schema != want:
            errs.append(f"{repo}: schema should be {want}, is {schema}")
        if role != schema + "_rw":
            errs.append(f"{repo}: runtime role should be {schema}_rw, is {role}")
        shell = shell_of.get(repo, "")
        if shell not in ("", "standalone", "out-of-band"):
            want_login = "shell_" + re.sub("-", "_", shell)
            if login != want_login:
                errs.append(f"{repo}: shell {shell} needs shell_login_role {want_login}, is {login}")

    retired = sum(1 for r in ports if r[5].startswith("retired"))
    if errs:
        print("✗ registry check failed:")
        for e in errs:
            print("  - " + e)
        return 1
    live = sum(1 for r in ports if not r[0].startswith(("_infra-", "_shell-")) and not r[5].startswith("retired"))
    print(f"✓ registry consistent: {live} components in use, {retired} retired, ports pairwise distinct, "
          f"{len(schemas)} schemas named by the rule")
    return 0


if __name__ == "__main__":
    sys.exit(main())
