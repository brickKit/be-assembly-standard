#!/usr/bin/env python3
"""Check local Markdown links and anchors under tempDocs/.

Every relative link to a .md file must point at an existing file, and its #anchor (if any)
must match a heading of that file (heading → anchor: strip punctuation, spaces to '-',
lower-case). Links inside fenced code blocks are ignored. Exit status 1 when any link is
broken. Review reports under work/rewrite-reports are skipped. Known false positive:
URL-encoded paths such as %20.
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
FENCE = re.compile(r"^```.*?^```", re.M | re.S)


def slug(h):
    h = h.strip().lower()
    h = re.sub(r"[^\w一-鿿\- ]", "", h)
    return h.replace(" ", "-")


_anchors = {}


def heads(p):
    if p not in _anchors:
        text = open(p, encoding="utf-8").read()
        _anchors[p] = {slug(m) for m in re.findall(r"^#+ (.*)$", FENCE.sub("", text), re.M)}
    return _anchors[p]


def main():
    skip = os.path.join(ROOT, "work", "rewrite-reports")  # one-off review reports, not maintained
    files = [os.path.join(d, f) for d, _, fs in os.walk(ROOT) for f in fs
             if f.endswith(".md") and not d.startswith(skip)]
    errs = n = 0
    for p in sorted(files):
        text = FENCE.sub("", open(p, encoding="utf-8").read())
        for m in re.finditer(r"\]\(([^)\s]+)\)", text):
            t = m.group(1)
            if t.startswith(("http:", "https:", "mailto:")):
                continue
            path, _, anchor = t.partition("#")
            target = os.path.normpath(os.path.join(os.path.dirname(p), path)) if path else p
            if not target.endswith(".md"):
                continue
            n += 1
            rel = os.path.relpath(p, ROOT)
            if not os.path.exists(target):
                print("MISSING", rel, t); errs += 1
            elif anchor and anchor not in heads(target):
                print("ANCHOR", rel, t); errs += 1
    print(f"{len(files)} files, {n} local links, {errs} errors")
    sys.exit(1 if errs else 0)


if __name__ == "__main__":
    main()
