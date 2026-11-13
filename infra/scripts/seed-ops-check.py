#!/usr/bin/env python3
"""Every user-facing operation a rebuilt component defines is granted by some seed (C9 retro).

A component that adds an operation and forgets its seed ships a demo where nobody can use the new route: erp/purchase
3.0.15 added erp.purchase.order.read_invoice without a seed grant, erp/inventory's erp.inventory.movement.adjust had
none for days; both looked fine in every test. The operations come from the suite's tables (cells/prepare.py), which
authz-keys-check proves equal to the definitions. An operation is granted when its key appears in a seed's source
(components/<id>/cmd/seed, Go or Python). System operations (".system.") are services' and not checked; the ones left
out on purpose are listed below with why.
Usage: seed-ops-check.py [root]   (exits 1 on a missing grant)"""
from __future__ import annotations

import ast
import pathlib
import sys

TABLES = ("INFRA_KEYS", "MDM_KEYS", "ERP_KEYS")
# operation (or "<component>" for a whole component) -> why no seed grants it
ON_PURPOSE = {
    "infra/iam-casdoor": "its seed makes the test accounts; its operations are the accounts' own (sessions) or the "
                         "security administrators' (disable, freeze, logout), granted through infra/authz when needed",
    "infra/audit": "no seed (docs/zh/03-seed-data.md); who reads the audit in the demo is still open (retro-c9 R6)",
    "infra/print": "no seed (docs/zh/03-seed-data.md); who edits the templates in the demo is still open (retro-c9 R6)",
    "infra.authz.security_record.relinquish": "a fixed segment every holder gets from infra/authz itself (D82)",
}


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    tree = ast.parse((root / "tools/be-acceptance/conformance/cells/prepare.py").read_text())
    keys: dict[str, list[str]] = {}
    for node in tree.body:
        target = node.targets[0] if isinstance(node, ast.Assign) else getattr(node, "target", None)
        if isinstance(target, ast.Name) and target.id in TABLES:
            for comp, k in ast.literal_eval(node.value).items():
                keys[comp] = k["permission"]
    missing = []
    for comp, ops in sorted(keys.items()):
        if comp in ON_PURPOSE or comp.startswith("test/"):
            continue
        seed = root / "components" / comp / "cmd" / "seed"
        text = "".join(p.read_text() for p in seed.rglob("*") if p.suffix in (".go", ".py")) if seed.exists() else ""
        for op in ops:
            if ".system." in op or op in ON_PURPOSE:
                continue
            if f'"{op}"' not in text:
                missing.append(f"{comp}: {op}")
    for m in missing:
        print(f"seed-ops-check: no seed grants {m}")
    print(f"seed-ops-check: {len(keys)} components, {len(missing)} operation(s) without a seed grant")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
