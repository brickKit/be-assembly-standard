#!/usr/bin/env python3
"""项目文档镜像检查：docs/en/ 与 docs/zh/ 两棵树必须逐文件对应。

(a) 两棵树下的相对路径集合完全相同；
(b) 每对 .md 文件的 `## ` 二级标题数相同（代码块里的不算）；
(c) 每个 .md 文件第一行有一个链接指向另一种语言的对应文件，且能解析到它。
有问题时逐行打印 `<path>: <problem>`，退出码 1。两棵树都不存在时什么也不查。
组件文档不归这里管：它们按 brickKit 的 `.zh.md` 后缀规则，由 brickkit lint 检查。
"""
from __future__ import annotations

import argparse
import pathlib
import re
import sys

LANGS = ("en", "zh")
LINK = re.compile(r"\]\(\s*<?([^)\s>]+)>?(?:\s+\"[^\"]*\")?\s*\)")
FENCE = re.compile(r"^\s{0,3}(```|~~~)")
H2 = re.compile(r"^##\s")
SKIP_DIRS = {"node_modules", "__pycache__"}


def tree(base: pathlib.Path) -> set[pathlib.PurePosixPath]:
    if not base.is_dir():
        return set()
    out = set()
    for p in base.rglob("*"):
        if not p.is_file():
            continue
        rel = p.relative_to(base)
        if any(part in SKIP_DIRS or part.startswith(".") for part in rel.parts):
            continue
        out.add(pathlib.PurePosixPath(rel.as_posix()))
    return out


def h2_count(p: pathlib.Path) -> int:
    n = 0
    in_fence = False
    for line in p.read_text(encoding="utf-8").splitlines():
        if FENCE.match(line):
            in_fence = not in_fence
            continue
        if not in_fence and H2.match(line):
            n += 1
    return n


def links_counterpart(p: pathlib.Path, counterpart: pathlib.Path) -> bool:
    lines = p.read_text(encoding="utf-8").splitlines()
    if not lines:
        return False
    want = counterpart.resolve()
    for target in LINK.findall(lines[0]):
        if "://" in target or target.startswith("#"):
            continue
        path = target.split("#", 1)[0]
        if path and (p.parent / path).resolve() == want:
            return True
    return False


def check(root: pathlib.Path) -> list[str]:
    docs = root / "docs"
    files = {lang: tree(docs / lang) for lang in LANGS}
    if not files["en"] and not files["zh"]:
        return []
    problems = []
    for lang, other in (("en", "zh"), ("zh", "en")):
        for rel in sorted(files[lang] - files[other]):
            problems.append(f"docs/{lang}/{rel}: 没有对应的 docs/{other}/{rel}")
    for rel in sorted(files["en"] & files["zh"]):
        if rel.suffix != ".md":
            continue
        en, zh = docs / "en" / rel, docs / "zh" / rel
        ne, nz = h2_count(en), h2_count(zh)
        if ne != nz:
            problems.append(f"docs/en/{rel}: `##` 小节数 {ne}，docs/zh/{rel} 是 {nz}")
        for lang, me, cp, other in (("en", en, zh, "zh"), ("zh", zh, en, "en")):
            if not links_counterpart(me, cp):
                problems.append(f"docs/{lang}/{rel}: 第一行没有能解析到 docs/{other}/{rel} 的链接")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    root = pathlib.Path(ap.parse_args().root)
    problems = check(root)
    for line in problems:
        print(line)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
