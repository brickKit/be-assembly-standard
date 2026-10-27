#!/usr/bin/env python3
"""Every exact reference to a rebuilt component names its current version. A component's version is metadata.version
in its own component.yaml (components/, shell/, the probes in tools/be-acceptance/probes/); a reference is
  - an exact dependency or shell member in a component.yaml: `<id>@<version>` (the short and the object form alike);
  - a member module in a Go shell's go.mod: `github.com/brickKit/<repository>/v3 v<version>`.
A reference to an older version brings a second node into a project (`brickkit up` finds a duplicate, cells create
says "already has") or compiles an old member into a shell; it slipped through six times while 3.x had no check.
Only rebuilt components count (major version 3); the 2.x leftovers and the frozen shells are skipped.
Usage: pin-check.py [root]   (exits 1 when a reference is stale)"""
from __future__ import annotations

import pathlib
import re
import sys

FROZEN = {"shell/be/go-backoffice"}  # the same list as version-check.sh
REF = re.compile(r"(?<![\w/.-])([a-z]+/[a-z0-9-]+)@(\d+\.\d+\.\d+)\b")
GOMOD = re.compile(r"^\s*github\.com/brickKit/([a-z0-9-]+)/v3 v(\d+\.\d+\.\d+)(?:\s|$)(?!.*// indirect)", re.M)


def manifests(root: pathlib.Path) -> list[pathlib.Path]:
    out = [*root.glob("components/*/*/component.yaml"), *root.glob("shell/*/*/component.yaml"),
           *root.glob("tools/be-acceptance/probes/*/component.yaml")]
    return [p for p in out if str(p.parent.relative_to(root)) not in FROZEN]


def meta(p: pathlib.Path) -> tuple[str, str]:
    text = p.read_text()
    block = text[text.index("metadata:"):]
    return (re.search(r"^\s+id:\s*(\S+)", block, re.M).group(1),
            re.search(r"^\s+version:\s*(\S+)", block, re.M).group(1))


def check(root: pathlib.Path) -> list[str]:
    current, owners = {}, {}
    for p in manifests(root):
        cid, version = meta(p)
        if version.startswith("3."):
            current[cid], owners[cid] = version, p
    stale = []
    for cid, p in owners.items():
        own = p.read_text().split("metadata:", 1)[1]
        for ref, version in REF.findall(own):
            if ref in current and ref != cid and version != current[ref]:
                stale.append(f"{p.relative_to(root)}: {ref}@{version}, current {current[ref]}")
        gomod = p.parent / "go.mod"
        if gomod.exists():
            for repo, version in GOMOD.findall(gomod.read_text()):
                ref = repo.replace("-", "/", 1)
                if ref in current and version != current[ref]:
                    stale.append(f"{gomod.relative_to(root)}: {ref} v{version}, current {current[ref]}")
    return stale


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2])
    stale = check(root)
    for s in stale:
        print(f"stale: {s}")
    print(f"pin-check: {len(stale)} stale reference(s)")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
