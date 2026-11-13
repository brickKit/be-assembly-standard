#!/usr/bin/env python3
"""The audit's target never carries what was done (C10 retro R6): audit.TargetOf's third argument is the object as
written, only its "version" is kept; a map written there (`TargetOf(typ, id, map[string]any{...})`) is silently
dropped, so the record cannot tell what happened. What was done goes in the record's Changes.
Usage: audit-target-check.py [root]; exits 1 naming each call."""
import pathlib
import re
import sys

CALL = re.compile(r"TargetOf\(([^()]|\([^()]*\))*?,\s*map\[string\]any\{", re.S)


def check(root: pathlib.Path) -> list[str]:
    out = []
    for f in sorted(root.glob("components/*/*/**/*.go")):
        if "/legacy" in str(f) or f.name.endswith("_test.go"):
            continue
        text = f.read_text()
        for m in CALL.finditer(text):
            line = text.count("\n", 0, m.start()) + 1
            out.append(f"{f.relative_to(root)}:{line}: TargetOf with a map: what was done goes in Changes")
    return out


def main() -> int:
    root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else pathlib.Path(__file__).resolve().parents[2])
    found = check(root)
    for x in found:
        print(x)
    print(f"audit-target-check: {len(found)} call(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
