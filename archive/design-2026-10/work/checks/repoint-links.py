#!/usr/bin/env python3
"""Rewrite links in tempDocs/final/ that still point at drafts listed in superseded-drafts.txt.

A link to a listed draft is replaced by a relative link to its final. When a draft was split
into several finals, the link goes to the final whose headings produce the link's anchor; a
link without an anchor goes to the first final. Links whose anchor exists in none of the
finals are reported and left unchanged. Prints the number of links changed per file.
"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))


def slug(h):
    h = h.strip().lower()
    h = re.sub(r"[^\w一-鿿\- ]", "", h)
    return h.replace(" ", "-")


def anchors(path):
    text = open(path, encoding="utf-8").read()
    return {slug(m) for m in re.findall(r"^#+ (.*)$", text, re.M)}


def load_map():
    mapping = {}
    for line in open(os.path.join(HERE, "superseded-drafts.txt"), encoding="utf-8"):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 2:
            mapping[parts[0]] = parts[1].split("|")
    return mapping


def main():
    mapping = load_map()
    os.chdir(ROOT)
    problems = []
    for path in sorted(glob.glob("final/**/*.md", recursive=True)):
        d = os.path.dirname(path)
        text = open(path, encoding="utf-8").read()
        count = 0

        def fix(m):
            nonlocal count
            target, anchor = m.group(1), m.group(2) or ""
            rel = os.path.normpath(os.path.join(d, target))
            if rel not in mapping:
                return m.group(0)
            finals = mapping[rel]
            chosen = finals[0]
            if anchor:
                hits = [f for f in finals if anchor[1:] in anchors(f)]
                if not hits:
                    problems.append(f"{path}: {target}{anchor} — anchor not found in {finals}")
                    return m.group(0)
                chosen = hits[0]
            count += 1
            return f"]({os.path.relpath(chosen, d)}{anchor})"

        new = re.sub(r"\]\(([^)#\s]+\.md)(#[^)\s]*)?\)", fix, text)
        if new != text:
            open(path, "w", encoding="utf-8").write(new)
            print(f"{path}: {count}")
    for p in problems:
        print("UNRESOLVED", p)
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
