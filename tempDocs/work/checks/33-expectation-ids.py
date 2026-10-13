#!/usr/bin/env python3
"""Check the independent-expectation IDs used across the design documents.

Every expectation table row starts with an ID such as `| AP01 |`. The check scans the design
documents (not the work records) and verifies:

  ONE_OWNER   each ID prefix is defined in exactly one document
  UNIQUE      no ID is defined twice
  CONTIGUOUS  within a prefix the numbers run 01..n without gaps

It also prints the prefix registry (prefix, document, count) used by protocol 21.
Exit status is non-zero when a check fails.
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SCOPES = ["security/*.md", "protocols/*.md", "validation/*.md", "07-validation.md"]
ROW = re.compile(r"^\| ([A-Z]{2})(\d{2}) \|", re.M)


def main():
    owners = {}
    seen = {}
    failures = []
    for pattern in SCOPES:
        for path in sorted(glob.glob(os.path.join(ROOT, pattern))):
            rel = os.path.relpath(path, ROOT)
            text = open(path, encoding="utf-8").read()
            for prefix, num in ROW.findall(text):
                key = f"{prefix}{num}"
                owners.setdefault(prefix, set()).add(rel)
                if key in seen:
                    failures.append(f"UNIQUE: {key} in {seen[key]} and {rel}")
                seen[key] = rel
    for prefix, files in sorted(owners.items()):
        if len(files) > 1:
            failures.append(f"ONE_OWNER: {prefix} defined in {sorted(files)}")
        nums = sorted(int(k[2:]) for k in seen if k.startswith(prefix))
        if nums != list(range(1, len(nums) + 1)):
            failures.append(f"CONTIGUOUS: {prefix} numbers {nums[0]}..{nums[-1]} with gaps or not starting at 01")
    print(f"{'prefix':<7} {'count':>5}  document")
    for prefix, files in sorted(owners.items()):
        count = sum(1 for k in seen if k.startswith(prefix))
        print(f"{prefix:<7} {count:>5}  {', '.join(sorted(files))}")
    print(f"{len(owners)} prefixes, {len(seen)} expectations")
    for f in failures:
        print(f)
    if failures:
        sys.exit(1)
    print("ONE_OWNER, UNIQUE, CONTIGUOUS: ok")


if __name__ == "__main__":
    main()
