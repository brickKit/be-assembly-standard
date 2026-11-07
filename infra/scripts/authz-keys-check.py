#!/usr/bin/env python3
"""The cells' authorization registry agrees with the components' definitions (foundations item 5, retro S3).

The conformance suite writes each cell's registry of resource types and permission keys from hand-kept tables
(tools/be-acceptance/conformance/cells/prepare.py: INFRA_KEYS, MDM_KEYS, ERP_KEYS); a component that adds an
operation and nobody updates the table gets a cell whose authorization member refuses the definition (the owner is
not registered), found only when the cell runs. This check reads what every rebuilt component really defines:
  - Go: a throwaway module that requires each component's module, replaced by its local source, and prints
    <entry>.Definition().Authz (resources' types, operations' keys);
  - Python: the component's own environment (uv run) prints definition().authz;
and compares them with the tables, both ways. A rebuilt component (major version 3) that defines resources and is
missing from the tables is an error too.
Usage: authz-keys-check.py [root]   (exits 1 on a difference; part of make registry-check)"""
from __future__ import annotations

import ast
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile

TABLES = ("INFRA_KEYS", "MDM_KEYS", "ERP_KEYS")
PY_PRINT = ("import json, importlib; m = importlib.import_module({pkg!r}); a = m.definition().authz; "
            "print(json.dumps({{'resource_type': [r.type for r in a.resources], "
            "'permission': [o.key for o in a.operations]}}))")


def tables(root: pathlib.Path) -> dict[str, dict[str, set[str]]]:
    """The suite's tables, read as literals (the suite's own dependencies are not needed)."""
    tree = ast.parse((root / "tools/be-acceptance/conformance/cells/prepare.py").read_text())
    out: dict[str, dict[str, set[str]]] = {}
    found = set()
    for node in tree.body:
        target = node.targets[0] if isinstance(node, ast.Assign) else getattr(node, "target", None)
        if isinstance(target, ast.Name) and target.id in TABLES:
            found.add(target.id)
            for comp, keys in ast.literal_eval(node.value).items():
                out[comp] = {kind: set(ks) for kind, ks in keys.items()}
    if missing := set(TABLES) - found:
        sys.exit(f"authz-keys-check: prepare.py has no {', '.join(sorted(missing))}: the check reads nothing")
    return out


def rebuilt(root: pathlib.Path) -> list[tuple[str, pathlib.Path]]:
    """(id, directory) of every rebuilt component (metadata.version 3.x) under components/."""
    out = []
    for manifest in sorted(root.glob("components/*/*/component.yaml")):
        text = manifest.read_text().split("metadata:", 1)[-1]
        cid = re.search(r"^\s+id:\s*(\S+)", text, re.M)
        version = re.search(r"^\s+version:\s*(\S+)", text, re.M)
        if cid and version and version.group(1).startswith("3."):
            out.append((cid.group(1), manifest.parent))
    return out


def placeholder(module: str) -> str:
    """A version the replaced module may be required at: the major its path carries (…/v3 → v3.0.0)."""
    m = re.search(r"/v(\d+)$", module)
    return f"v{m.group(1)}.0.0" if m else "v0.0.0"


def go_definitions(comps: list[tuple[str, pathlib.Path]]) -> dict[str, dict[str, set[str]]]:
    imports, prints, requires = [], [], []
    for i, (cid, d) in enumerate(comps):
        module = re.search(r"^module\s+(\S+)", (d / "go.mod").read_text(), re.M).group(1)
        entry = [p.parent for p in d.glob("*/definition.go") if "func Definition() " in p.read_text()]
        if len(entry) != 1:
            sys.exit(f"authz-keys-check: {cid}: expected one entry package with func Definition(), found {entry}")
        imports.append(f'\tp{i} "{module}/{entry[0].name}"')
        prints.append(f'\tshow("{cid}", p{i}.Definition().Authz)')
        requires.append((module, d))
    main = ("package main\n\nimport (\n\t\"encoding/json\"\n\t\"fmt\"\n\n\t\"github.com/brickKit/be-sdk-go/v3/authz\"\n"
            + "\n".join(imports) + "\n)\n\n"
            "func show(id string, a *authz.Definitions) {\n"
            "\tout := map[string][]string{\"resource_type\": {}, \"permission\": {}}\n"
            "\tif a != nil {\n"
            "\t\tfor _, r := range a.Resources {\n\t\t\tout[\"resource_type\"] = append(out[\"resource_type\"], r.Type)\n\t\t}\n"
            "\t\tfor _, o := range a.Operations {\n\t\t\tout[\"permission\"] = append(out[\"permission\"], o.Key)\n\t\t}\n"
            "\t}\n\tb, _ := json.Marshal(map[string]any{\"id\": id, \"keys\": out})\n\tfmt.Println(string(b))\n}\n\n"
            "func main() {\n" + "\n".join(prints) + "\n}\n")
    gomod = "module authzkeys\n\ngo 1.27\n\nrequire (\n" + "".join(f"\t{m} {placeholder(m)}\n" for m, _ in requires) + ")\n\n" + \
        "".join(f"replace {m} => {d}\n" for m, d in requires)
    with tempfile.TemporaryDirectory(prefix="authz-keys-") as tmp:
        (pathlib.Path(tmp) / "go.mod").write_text(gomod)
        (pathlib.Path(tmp) / "main.go").write_text(main)
        env = {**os.environ, "GOFLAGS": "-mod=mod", "GOWORK": "off"}
        for cmd in (["go", "mod", "tidy"], ["go", "run", "."]):
            r = subprocess.run(cmd, cwd=tmp, env=env, capture_output=True, text=True)
            if r.returncode != 0:
                sys.exit(f"authz-keys-check: {' '.join(cmd)} failed:\n{r.stderr[-3000:]}")
    out = {}
    for line in r.stdout.splitlines():
        rec = json.loads(line)
        out[rec["id"]] = {k: set(v) for k, v in rec["keys"].items()}
    return out


def python_definition(cid: str, d: pathlib.Path) -> dict[str, set[str]]:
    pkg = re.search(r'^name\s*=\s*"([^"]+)"', (d / "pyproject.toml").read_text(), re.M).group(1).replace("-", "_")
    r = subprocess.run(["uv", "run", "--frozen", "--directory", str(d), "python", "-c", PY_PRINT.format(pkg=pkg)],
                       capture_output=True, text=True, env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
    if r.returncode != 0:
        sys.exit(f"authz-keys-check: {cid}: reading definition().authz failed:\n{r.stderr[-2000:]}")
    return {k: set(v) for k, v in json.loads(r.stdout.strip().splitlines()[-1]).items()}


def compare(table: dict[str, dict[str, set[str]]], defined: dict[str, dict[str, set[str]]]) -> list[str]:
    problems = []
    for cid in sorted(defined):
        if cid not in table:
            if any(defined[cid].values()):
                problems.append(f"{cid}: defines resources but is not in the suite's tables")
            continue
        for kind in ("resource_type", "permission"):
            want, have = defined[cid].get(kind, set()), table[cid].get(kind, set())
            for k in sorted(want - have):
                problems.append(f"{cid}: {kind} {k} is defined but missing from the suite's table")
            for k in sorted(have - want):
                problems.append(f"{cid}: {kind} {k} is in the suite's table but not defined")
    for cid in sorted(set(table) - set(defined)):
        problems.append(f"{cid}: in the suite's tables but not a rebuilt component")
    return problems


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2])
    table = tables(root)
    comps = rebuilt(root)
    go = [(c, d) for c, d in comps if (d / "go.mod").exists()]
    py = [(c, d) for c, d in comps if (d / "pyproject.toml").exists() and not (d / "go.mod").exists()]
    defined = go_definitions(go) if go else {}
    for cid, d in py:
        defined[cid] = python_definition(cid, d)
    problems = compare(table, defined)
    for p in problems:
        print(f"✗ {p}")
    print(f"authz-keys-check: {len(defined)} components, {len(problems)} difference(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
