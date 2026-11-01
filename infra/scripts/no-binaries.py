#!/usr/bin/env python3
"""Keeps build output out of Git history. A build artifact reached a release four times (be/go-core 3.0.20,
be/go-infra 3.0.23, be-sdk-go alpha.8, the Go probe 3.2.23: `go build .` and `go test -c` leave 40-55 MB binaries in the
source tree), and each time the history had to be rewritten (dev/rebuild/retro-step12.md, P1).
  staged   (pre-commit, in the repository being committed): refuse a staged file larger than LIMIT, or any executable
           binary (ELF, Mach-O, PE) whatever its size;
  tree     (make gates, from the project root): files larger than LIMIT in HEAD of the project and of every submodule.
Paths matching a line of no-binaries.allow (fnmatch, relative to the repository; `size:` before a pattern allows only
the size, not an executable) are skipped. Exits 1 with one line per offending file.
Usage: no-binaries.py staged | tree"""
from __future__ import annotations

import fnmatch
import pathlib
import subprocess
import sys

LIMIT = 5 << 20
ALLOW = pathlib.Path(__file__).with_name("no-binaries.allow")
MAGIC = (b"\x7fELF", b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce")


def rules() -> tuple[list[str], list[str]]:
    """(patterns allowing a file entirely, patterns allowing only its size)."""
    whole, size = [], []
    for line in ALLOW.read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line.startswith("size:"):
            size.append(line[5:].strip())
        elif line:
            whole.append(line)
    return whole, size


def matches(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, p) for p in patterns)


def executable(head: bytes) -> bool:
    if head.startswith(MAGIC):
        return True
    if head.startswith(b"MZ") and len(head) >= 64:  # PE: the offset at 0x3c points at "PE\0\0"
        off = int.from_bytes(head[0x3C:0x40], "little")
        return off + 4 <= len(head) and head[off:off + 4] == b"PE\0\0"
    return False


def git(repo: str, *args: str, data: bool = False):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, check=True)
    return r.stdout if data else r.stdout.decode()


def staged() -> list[str]:
    whole, size = rules()
    bad = []
    names = git(".", "diff", "--cached", "--name-only", "--diff-filter=ACMR", "-z").split("\0")
    for name in filter(None, names):
        if matches(name, whole) or git(".", "ls-files", "-s", "--", name).startswith("160000"):
            continue  # allowed, or a submodule pointer (a commit, not a file)
        blob = git(".", "show", f":{name}", data=True)
        if executable(blob[:4096]):
            bad.append(f"{name}: an executable binary (build output?); add it to .gitignore")
        elif len(blob) > LIMIT and not matches(name, size):
            bad.append(f"{name}: {len(blob) / 2**20:.1f} MiB, over {LIMIT >> 20} MiB")
    return bad


def tree() -> list[str]:
    whole, size = rules()
    repos = ["."] + git(".", "submodule", "--quiet", "foreach", "echo $sm_path").split()
    bad = []
    for repo in repos:
        for line in git(repo, "ls-tree", "-r", "-l", "HEAD").splitlines():
            meta, path = line.split("\t", 1)
            kind, length = meta.split()[1], meta.split()[3]
            full = path if repo == "." else f"{repo}/{path}"
            if kind == "blob" and int(length) > LIMIT and not matches(full, whole + size):
                bad.append(f"{full}: {int(length) / 2**20:.1f} MiB, over {LIMIT >> 20} MiB")
    return bad


def main() -> int:
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode not in ("staged", "tree"):
        print(__doc__, file=sys.stderr)
        return 64
    bad = staged() if mode == "staged" else tree()
    for b in bad:
        print(f"no-binaries: {b}", file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
