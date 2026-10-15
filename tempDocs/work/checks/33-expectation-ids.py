#!/usr/bin/env python3
"""Check the independent-expectation IDs used across the design documents.

Every expectation table row starts with an ID such as `| AP01 |`. The check scans the design
documents (not the work records) and verifies:

  ONE_OWNER   each ID prefix is defined in exactly one document
  UNIQUE      no ID is defined twice
  CONTIGUOUS  within a prefix the numbers run 01..n without gaps
  CARRIED     every ID of a draft listed in superseded-drafts.txt still exists in final/

Drafts listed in superseded-drafts.txt have been rewritten into final/; they are skipped
so that the final copy is the only owner of their IDs.

It also prints the prefix registry (prefix, document, count) used by protocol 21.
Exit status is non-zero when a check fails.
"""
import glob
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SCOPES = ["security/*.md", "protocols/*.md", "validation/*.md", "07-validation.md", "final/**/*.md"]
SUPERSEDED = os.path.join(os.path.dirname(__file__), "superseded-drafts.txt")
ROW = re.compile(r"^\| ([A-Z]{2})(\d{2}) \|", re.M)


def superseded():
    lines = open(SUPERSEDED, encoding="utf-8").read().splitlines()
    return {l.split()[0] for l in lines if l.strip() and not l.startswith("#") and not l.startswith("final/")}


def main():
    owners = {}
    seen = {}
    failures = []
    skipped = superseded()
    draft_ids = {}
    for rel in sorted(skipped):
        path = os.path.join(ROOT, rel)
        if not os.path.exists(path):
            failures.append(f"SUPERSEDED: {rel} listed but missing")
            continue
        for prefix, num in ROW.findall(open(path, encoding="utf-8").read()):
            draft_ids[f"{prefix}{num}"] = rel
    for pattern in SCOPES:
        for path in sorted(glob.glob(os.path.join(ROOT, pattern), recursive=True)):
            rel = os.path.relpath(path, ROOT)
            if rel in skipped:
                continue
            text = open(path, encoding="utf-8").read()
            for prefix, num in ROW.findall(text):
                key = f"{prefix}{num}"
                owners.setdefault(prefix, set()).add(rel)
                if key in seen:
                    failures.append(f"UNIQUE: {key} in {seen[key]} and {rel}")
                seen[key] = rel
    for key, rel in sorted(draft_ids.items()):
        if key not in seen or not seen[key].startswith("final/"):
            failures.append(f"CARRIED: {key} of {rel} not found in final/")
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
    print(f"{len(owners)} prefixes, {len(seen)} expectations; {len(skipped)} superseded drafts skipped")
    for f in failures:
        print(f)
    if failures:
        sys.exit(1)
    print("ONE_OWNER, UNIQUE, CONTIGUOUS, CARRIED: ok")


if __name__ == "__main__":
    main()
