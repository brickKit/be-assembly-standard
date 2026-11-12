#!/usr/bin/env python3
"""Runs a list of mutants: each rule broken by one edit, the tests run, the file restored (testing and validation,
"补测与定向测试要反向检查"; red must be red on that rule).

Usage: mutate.py <mutants.py> <out.txt>   (run from the repository the mutants edit)

<mutants.py> is plain Python defining:
    TITLE   = "infra/authz 3.0.26 ...: what this round checks"
    BUILD   = ["go", "vet", "-tags", "integration", "./authz"]       # a mutant that does not build is not a result
    TEST    = ["go", "test", "-count=1", "-tags", "integration", "./authz/"]
    MUTANTS = [("authz/x.go", "old text", "new text", "the rule this breaks"), ...]
    ENV     = {"PYTHONDONTWRITEBYTECODE": "1"}                        # optional, added to the environment
    CLEAN   = ["__pycache__"]                                         # optional: directories removed before each run

Before anything runs, every mutant's old text must occur exactly once in its file and differ from the new text, and
the list must not be empty (round 4 of T9 ran a script with no mutant; another left mutants out by a failed grep). A
red result records the failing assertion's messages, to read that it is red on its rule. Every file is restored from
memory after its mutant, and checked at the end. Progress goes to stdout, one line per mutant ("k/N red ..."), and the
out file starts with the count: a monitor reports "k of N" from either (a round runs a full suite per mutant, often
well over 5 minutes: run it in the background with a monitor, user-level instructions).
"""
import os
import pathlib
import runpy
import shutil
import subprocess
import sys


def main() -> int:
    spec, out = runpy.run_path(sys.argv[1]), pathlib.Path(sys.argv[2])
    mutants = spec.get("MUTANTS") or []
    if not mutants:
        sys.exit("no mutants: nothing would be checked")
    originals = {}
    for f, old, new, label in mutants:
        text = originals.setdefault(f, pathlib.Path(f).read_text())
        if text.count(old) != 1 or old == new:
            sys.exit(f"PATTERN MISSING or not unique ({text.count(old)}x): {label}")
    env = {**os.environ, **spec.get("ENV", {})}
    lines = [spec["TITLE"], f"mutants: {len(mutants)}"]
    print(f"0/{len(mutants)} starting: {spec['TITLE']}", flush=True)
    try:
        for k, (f, old, new, label) in enumerate(mutants, 1):
            for d in spec.get("CLEAN", []):
                for p in pathlib.Path(".").rglob(d):
                    shutil.rmtree(p, ignore_errors=True)
            pathlib.Path(f).write_text(originals[f].replace(old, new))
            try:
                if subprocess.run(spec["BUILD"], env=env, capture_output=True).returncode != 0:
                    lines.append(f"does not build: {label}")
                    continue
                r = subprocess.run(spec["TEST"], env=env, capture_output=True, text=True, errors="replace")  # a mutant may print broken UTF-8
                text = r.stdout + r.stderr
                if r.returncode != 0:
                    msgs = [l.strip()[:200] for l in text.splitlines()
                            if ("Error:" in l or "Messages:" in l or "AssertionError" in l) and '"level"' not in l][:3]
                    lines.append(f"red  {label}")
                    lines += ["       " + m for m in msgs]
                else:
                    lines.append(f"GREEN (survived)  {label}")
            finally: # every mutant, built or not: the file back, the result and the progress line out
                pathlib.Path(f).write_text(originals[f])
                out.write_text("\n".join(lines) + "\n")
                last = next(l for l in reversed(lines) if not l.startswith("       "))
                print(f"{k}/{len(mutants)} {last}", flush=True)
    finally:
        for f, text in originals.items():
            pathlib.Path(f).write_text(text)
    changed = [f for f, text in originals.items() if pathlib.Path(f).read_text() != text]
    lines.append("done" if not changed else f"NOT RESTORED: {changed}")
    out.write_text("\n".join(lines) + "\n")
    return 1 if changed else 0


if __name__ == "__main__":
    sys.exit(main())
