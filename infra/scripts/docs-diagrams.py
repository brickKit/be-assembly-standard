#!/usr/bin/env python3
"""文档里的图：开发与修改用的文档不放图；客户会读的文档里，每张图后面写出它画的关系。

规则见 docs/zh/01-conventions/04-diagrams-and-tables.md 的“图放在哪里”。
客户会读的文档（docs/<语言>/ 下）：00-overview/ 的 01-product.md、03-catalog.md、04-selection.md、guides/，
以及 05-operations/、08-flows/。这些文档里的每个 Mermaid 块，后面第一段文字以“图中的”开头。
其余的正式文档（根目录 AGENTS*.md、README*.md，docs/ 的其余文件，components/ 与 shell/ 下的 .md）不得有 Mermaid 块。
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

MERMAID = re.compile(r"^\s{0,3}(```|~~~)\s*mermaid\b")
FENCE = re.compile(r"^\s{0,3}(```|~~~)")
SKIP_DIRS = {"node_modules", "dist", ".git", ".brickkit", "vendor", "__pycache__"}
CUSTOMER_FILES = {"00-overview/01-product.md", "00-overview/03-catalog.md", "00-overview/04-selection.md"}
CUSTOMER_DIRS = ("00-overview/guides/", "05-operations/", "08-flows/")
RELATION_LEAD = "图中的"


def formal_docs(root: pathlib.Path):
    for pattern in ("AGENTS*.md", "README*.md"):
        yield from root.glob(pattern)
    for base in ("docs", "components", "shell"):
        d = root / base
        if not d.is_dir():
            continue
        for p in d.rglob("*.md"):
            parts = p.relative_to(root).parts
            if any(part in SKIP_DIRS or part.startswith(".") for part in parts):
                continue
            yield p


def is_customer_doc(rel: pathlib.PurePosixPath) -> bool:
    # docs/<lang>/<path>: the language directory is not part of the rule
    if len(rel.parts) < 3 or rel.parts[0] != "docs":
        return False
    inner = "/".join(rel.parts[2:])
    return inner in CUSTOMER_FILES or inner.startswith(CUSTOMER_DIRS)


def check(root: pathlib.Path) -> list[str]:
    errors = []
    for doc in sorted(set(formal_docs(root))):
        rel = pathlib.PurePosixPath(doc.relative_to(root).as_posix())
        lines = doc.read_text(encoding="utf-8").split("\n")
        customer = is_customer_doc(rel)
        i = 0
        while i < len(lines):
            if not MERMAID.match(lines[i]):
                i += 1
                continue
            start = i + 1
            i += 1
            while i < len(lines) and not FENCE.match(lines[i]):
                i += 1
            if not customer:
                errors.append(f"{rel}:{start}: Mermaid diagram in a developer document; write it as text, a table, "
                              f"numbered steps or a role table (04-diagrams-and-tables.md#图放在哪里)")
            else:
                following = next((l.strip() for l in lines[i + 1:] if l.strip()), "")
                if not following.startswith(RELATION_LEAD):
                    errors.append(f"{rel}:{start}: diagram not followed by a paragraph starting with "
                                  f"\"{RELATION_LEAD}\" that writes out every relation it draws")
            i += 1
    return errors


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("root", nargs="?", default=".")
    args = ap.parse_args()
    errors = check(pathlib.Path(args.root))
    for e in errors:
        print(e)
    if errors:
        print(f"docs-diagrams: {len(errors)} problem(s)")
        return 1
    print("docs-diagrams: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
