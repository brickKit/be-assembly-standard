#!/usr/bin/env python3
"""正式文档边界检查：正式文档不得链接 dev/ 或 archive/。

正式文档 = 根目录 AGENTS*.md、README*.md，docs/ 下全部 .md，
components/<scope>/<name>/ 与 shell/<scope>/<name>/ 下的 .md（不含 node_modules 等）。
dev/ 与 archive/ 自己可以链接任何地方，不检查。
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

INLINE = re.compile(r"\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
REFDEF = re.compile(r"^\s{0,3}\[[^\]]+\]:\s*<?(\S+?)>?(?:\s|$)")
ANGLE = re.compile(r"<([^>\s]+\.md(?:#[^>\s]*)?)>")
FENCE = re.compile(r"^\s{0,3}(```|~~~)")
INLINE_CODE = re.compile(r"`[^`]*`")
SKIP_DIRS = {"node_modules", "dist", ".git", ".brickkit", "vendor", "__pycache__"}
FORBIDDEN = ("dev", "archive")


def formal_docs(root: pathlib.Path):
    for p in root.glob("AGENTS*.md"):
        yield p
    for p in root.glob("README*.md"):
        yield p
    for base in ("docs", "components", "shell"):
        d = root / base
        if not d.is_dir():
            continue
        for p in d.rglob("*.md"):
            rel_parts = p.relative_to(root).parts
            if any(part in SKIP_DIRS or part.startswith(".") for part in rel_parts):
                continue
            yield p


def targets(line: str):
    line = INLINE_CODE.sub("", line)
    for rx in (INLINE, REFDEF, ANGLE):
        for m in rx.finditer(line):
            yield m.group(1)


def violates(root: pathlib.Path, doc: pathlib.Path, target: str) -> bool:
    if "://" in target or target.startswith(("#", "mailto:")):
        return False
    path = target.split("#", 1)[0]
    if not path:
        return False
    resolved = (root / path.lstrip("/")) if path.startswith("/") else (doc.parent / path)
    try:
        rel = resolved.resolve().relative_to(root.resolve())
    except ValueError:
        return False
    return len(rel.parts) > 0 and rel.parts[0] in FORBIDDEN


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    root = pathlib.Path(ap.parse_args().root)
    bad = 0
    for doc in sorted(set(formal_docs(root))):
        in_fence = False
        for no, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
            if FENCE.match(line):
                in_fence = not in_fence
                continue
            if in_fence:
                continue
            for t in targets(line):
                if violates(root, doc, t):
                    print(f"{doc.relative_to(root)}:{no}: 链接指向 {t}（正式文档不得链接 dev/ 或 archive/）")
                    bad += 1
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
