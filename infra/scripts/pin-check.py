#!/usr/bin/env python3
"""Every exact reference to a rebuilt component names its current version. A component's version is metadata.version
in its own component.yaml (components/, shell/, the probes in tools/be-acceptance/probes/); a reference is
  - an exact dependency or shell member in a component.yaml: `<id>@<version>` (the short and the object form alike);
  - a Go module of a rebuilt component, in a go.mod's require (`<module> v<version>`) or installed by a Dockerfile
    (`<module>@v<version>`); a module belongs to the component whose directory's go.mod declares it, so a module
    below a repository's root (the probes' github.com/brickKit/be-acceptance/probes/go/v3) counts too.
A reference to an older version brings a second node into a project (`brickkit up` finds a duplicate, cells create
says "already has") or compiles an old member into a shell; it slipped through six times while 3.x had no check.
A Python component's pyproject.toml beside its component.yaml must agree with it too:
  - [project] version is metadata.version: a shell compares the installed distribution's version with the member's,
    and the Python probe stayed at 3.2.20 from 3.2.21 to 3.2.25, so a shell hosting it refused to start;
  - a member (not a shell, whose SDK is its override-dependencies) declares `be-sdk>=<v>` with v the tag it pins in
    [tool.uv.sources]: the tag never reaches the package metadata, and a shell checks the declared minimum (P1.21).
The conformance suite (tools/be-acceptance/conformance) pins the Python SDK too: its test deployment (besdk.testing)
stands in for the identity provider and the members the probes talk to, so it is never older than the SDK any Python
probe pins (the suite stayed at a20 while the probes were at a44, and its tokens lacked what newer SDKs require).
Only rebuilt components count (major version 3); the 2.x leftovers and the frozen shells are skipped.
Usage: pin-check.py [root]   (exits 1 when a reference is stale)"""
from __future__ import annotations

import pathlib
import re
import sys
import tomllib

FROZEN = {"shell/be/go-backoffice"}  # the same list as version-check.sh
REF = re.compile(r"(?<![\w/.-])([a-z]+/[a-z0-9-]+)@(\d+\.\d+\.\d+)\b")
GOMOD = re.compile(r"^\s*(github\.com/brickKit/\S+) v(\d+\.\d+\.\d+)(?:\s|$)(?!.*// indirect)", re.M)
DOCKERFILE = re.compile(r"(github\.com/brickKit/\S+?)@v(\d+\.\d+\.\d+)\b")
MODULE = re.compile(r"^module\s+(\S+)", re.M)
SDK = re.compile(r"^be[-_]sdk(?![\w.-])")


def manifests(root: pathlib.Path) -> list[pathlib.Path]:
    out = [*root.glob("components/*/*/component.yaml"), *root.glob("shell/*/*/component.yaml"),
           *root.glob("tools/be-acceptance/probes/*/component.yaml")]
    return [p for p in out if str(p.parent.relative_to(root)) not in FROZEN]


def meta(p: pathlib.Path) -> tuple[str, str]:
    text = p.read_text()
    block = text[text.index("metadata:"):]
    return (re.search(r"^\s+id:\s*(\S+)", block, re.M).group(1),
            re.search(r"^\s+version:\s*(\S+)", block, re.M).group(1))


def python(root: pathlib.Path, manifest: pathlib.Path, version: str) -> list[str]:
    f = manifest.parent / "pyproject.toml"
    if not f.exists():
        return []
    rel, data = f.relative_to(root), tomllib.loads(f.read_text())
    out = []
    if (own := data["project"].get("version")) != version:
        out.append(f"{rel}: version {own}, component.yaml {version}")
    if re.search(r"^shell:", manifest.read_text(), re.M):
        return out
    for dep in data["project"].get("dependencies", []):
        if SDK.match(dep):
            tag = data.get("tool", {}).get("uv", {}).get("sources", {}).get("be-sdk", {}).get("tag", "")
            if dep.replace(" ", "") != f"be-sdk>={tag.removeprefix('v')}":
                out.append(f"{rel}: {dep}, the pinned tag is {tag}; declare be-sdk>={tag.removeprefix('v')} (P1.21)")
    return out


def check(root: pathlib.Path) -> list[str]:
    current, owners, modules = {}, {}, {}
    for p in manifests(root):
        cid, version = meta(p)
        if version.startswith("3."):
            current[cid], owners[cid] = version, p
            gomod = p.parent / "go.mod"
            if gomod.exists() and (m := MODULE.search(gomod.read_text())):
                modules[m.group(1)] = cid
    stale = []

    def pins(f: pathlib.Path, pattern: re.Pattern) -> None:
        for module, version in pattern.findall(f.read_text()):
            ref = modules.get(module)
            if ref and version != current[ref]:
                stale.append(f"{f.relative_to(root)}: {ref} v{version}, current {current[ref]}")
    for cid, p in owners.items():
        own = p.read_text().split("metadata:", 1)[1]
        for ref, version in REF.findall(own):
            if ref in current and ref != cid and version != current[ref]:
                stale.append(f"{p.relative_to(root)}: {ref}@{version}, current {current[ref]}")
        for name, pattern in (("go.mod", GOMOD), ("Dockerfile", DOCKERFILE)):
            if (p.parent / name).exists():
                pins(p.parent / name, pattern)
        stale += python(root, p, current[cid])
    return stale


SDK_TAG = re.compile(r"^v?3\.0\.0a(\d+)$")


def suite_sdk(root: pathlib.Path) -> list[str]:
    """The suite's be-sdk tag is not older than any Python probe's."""
    def tag(pyproject: pathlib.Path) -> str:
        data = tomllib.loads(pyproject.read_text())
        return data.get("tool", {}).get("uv", {}).get("sources", {}).get("be-sdk", {}).get("tag", "")
    suite = root / "tools/be-acceptance/conformance/pyproject.toml"
    if not suite.exists():
        return []
    st = tag(suite)
    out = []
    for probe in sorted(root.glob("tools/be-acceptance/probes/*/pyproject.toml")):
        pt = tag(probe)
        sm, pm = SDK_TAG.match(st), SDK_TAG.match(pt)
        if sm and pm and int(sm.group(1)) < int(pm.group(1)):
            out.append(f"{suite.relative_to(root)}: be-sdk {st} is older than {probe.relative_to(root)}'s {pt}; "
                       "the suite's test deployment must know what the probes' SDK requires")
    return out


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2])
    stale = check(root) + suite_sdk(root)
    for s in stale:
        print(f"stale: {s}")
    print(f"pin-check: {len(stale)} stale reference(s)")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main())
