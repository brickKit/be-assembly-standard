#!/usr/bin/env python3
"""Frees disk space taken by images and build cache this project can rebuild. Lists by default; --apply deletes.

What goes, in Docker, in Podman and in the minikube node `bek` (when it runs):
  - this project's component, shell and probe images (repositories infra-*, mdm-*, erp-*, crm-*, integration-*,
    frontend-*, be-*, test-*) beyond the newest KEEP versions of each, except a version a container uses (running
    or stopped) or the project's brickkit.yaml pins;
  - retired images of this project (compconf-*: the 0.x conformance stubs);
  - dangling images (no name left);
  - Docker build cache older than CACHE_HOURS.
Never touched: volumes (they hold the base resources' data), containers, and every other image (base images,
BrickKit's own test images, other projects).

A run is skipped when anything may be measuring or building: a cell's containers are up (compose project brickkit-*),
the minikube node runs and --minikube is not given, or a runner, cell chain, smoke or brickkit build/up process
exists. The timer (infra/systemd/) runs it daily; `make prune` lists, `make prune-apply` deletes.

Usage: prune-images.py [--apply] [--keep N] [--cache-hours H] [--minikube]"""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OURS = re.compile(r"^(infra|mdm|erp|crm|integration|frontend|be|test)-[a-z0-9-]+$")
RETIRED = re.compile(r"^compconf-")
BUSY = re.compile(r"(runner9\.sh|cell-chain\.sh|smoke9\.sh|brickkit (build|up)\b|cells\.localrun)")
PROFILE = "bek"


def sh(*cmd: str, check: bool = False) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}: {r.stderr.strip()}")
    return r.stdout if r.returncode == 0 else ""


def name(repo: str) -> str:
    for prefix in ("docker.io/library/", "localhost/"):
        if repo.startswith(prefix):
            return repo[len(prefix):]
    return repo


def version_key(tag: str) -> tuple:
    return tuple(int(x) for x in tag.split(".")) if re.fullmatch(r"\d+(\.\d+)*", tag) else (-1,)


def busy(minikube_ok: bool) -> str | None:
    me = str(pathlib.Path("/proc/self").resolve().name)
    for p in pathlib.Path("/proc").iterdir():
        if not p.name.isdigit() or p.name == me:
            continue
        try:
            cmd = (p / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace")
        except OSError:
            continue
        if BUSY.search(cmd) and "prune-images" not in cmd:
            return f"process {p.name}: {cmd[:100]}"
    for engine in ("docker", "podman"):
        projects = sh(engine, "ps", "--format", "{{.Labels}}")
        if "com.docker.compose.project=brickkit-" in projects:
            return f"a cell runs in {engine}"
    if not minikube_ok and sh("minikube", "-p", PROFILE, "status", "--format", "{{.Host}}").strip() == "Running":
        return "the minikube node runs (a K cell may be measuring); pass --minikube to prune it anyway"
    return None


def pinned() -> set[str]:
    """repo:tag of every component the project's brickkit.yaml pins."""
    f = ROOT / "brickkit.yaml"
    if not f.exists():
        return set()
    text = f.read_text()
    return {f"{i.replace('/', '-')}:{v}" for i, v in re.findall(r"-\s+id:\s*(\S+)\s*\n\s+version:\s*(\S+)", text)}


class Engine:
    """docker or podman on this machine, or the minikube node's Docker (over minikube ssh)."""

    def __init__(self, label: str, run: list[str]):
        self.label, self.run = label, run

    def images(self) -> list[tuple[str, str, str]]:
        out = sh(*self.run, "images", "--format", "{{.Repository}}\t{{.Tag}}\t{{.Size}}")
        return [tuple(line.split("\t")) for line in out.splitlines() if line.count("\t") == 2]  # type: ignore[misc]

    def used(self) -> set[str]:
        return {name(i) if ":" in i else name(i) + ":latest"
                for i in sh(*self.run, "ps", "-a", "--format", "{{.Image}}").split()}

    def plan(self, keep: int, pins: set[str]) -> list[tuple[str, str]]:
        """(reference, size) of every image to remove."""
        used = self.used()
        by_repo: dict[str, list[tuple[str, str, str]]] = {}
        out = []
        for repo, tag, size in self.images():
            n = name(repo)
            if repo == "<none>" or tag == "<none>":
                continue  # dangling: the engine's own prune
            if RETIRED.match(n):
                out.append((f"{repo}:{tag}", size))
            elif OURS.match(n):
                by_repo.setdefault(n, []).append((repo, tag, size))
        for n, rows in by_repo.items():
            versions = sorted({t for _, t, _ in rows if version_key(t) != (-1,)}, key=version_key, reverse=True)
            kept = set(versions[:keep])
            for repo, tag, size in rows:
                ref = f"{n}:{tag}"
                if tag in kept or version_key(tag) == (-1,) or ref in used or ref in pins:
                    continue
                out.append((f"{repo}:{tag}", size))
        return sorted(out)

    def remove(self, refs: list[str]) -> None:
        for i in range(0, len(refs), 50):
            sh(*self.run, "rmi", *refs[i:i + 50])

    def prune_dangling(self) -> None:
        sh(*self.run, "image", "prune", "-f")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--apply", action="store_true", help="delete (default: list only)")
    ap.add_argument("--keep", type=int, default=2, help="newest versions kept of each image (default 2)")
    ap.add_argument("--cache-hours", type=int, default=72, help="Docker build cache older than this goes (default 72)")
    ap.add_argument("--minikube", action="store_true", help="run even while the minikube node runs, and prune it")
    a = ap.parse_args()
    why = busy(a.minikube)
    if why:
        print(f"skipped: {why}")
        return 0
    pins = pinned()
    engines = [Engine("docker", ["docker"]), Engine("podman", ["podman"])]
    if sh("minikube", "-p", PROFILE, "status", "--format", "{{.Host}}").strip() == "Running":
        engines.append(Engine(f"minikube {PROFILE}", ["minikube", "-p", PROFILE, "ssh", "--", "docker"]))
    for e in engines:
        plan = e.plan(a.keep, pins)
        dangling = sum(1 for r, t, _ in e.images() if r == "<none>" or t == "<none>")
        print(f"{e.label}: {len(plan)} images to remove, {dangling} dangling")
        for ref, size in plan:
            print(f"  {ref}  {size}")
        if a.apply:
            e.remove([r for r, _ in plan])
            e.prune_dangling()
    cache = sh("docker", "system", "df", "--format", "{{json .}}")
    for line in cache.splitlines():
        row = json.loads(line)
        if row.get("Type") == "Build Cache":
            print(f"docker build cache: {row.get('Size')} ({row.get('Reclaimable')} reclaimable); "
                  f"older than {a.cache_hours} h goes")
    if a.apply:
        sh("docker", "builder", "prune", "-f", "--filter", f"until={a.cache_hours}h")
        print(sh("df", "-h", "/").splitlines()[-1])
    else:
        print("listed only; --apply deletes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
