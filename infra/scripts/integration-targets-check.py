#!/usr/bin/env python3
"""Every rebuilt component's `make test-integration` reaches integration tests (structure finding SF13): its command,
listed instead of run (`go test -list`, `pytest --collect-only`), finds at least one test. A command left pointing at
a package without them (SF18: the targets still named the entry packages after the tests moved to itest/) passes
without testing anything; this check fails it. Nothing runs, no base resources needed.

Usage: integration-targets-check.py [component directory ...]   (default: every components/*/*/ with a Makefile
target test-integration)
"""
from __future__ import annotations

import os
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def command(makefile: pathlib.Path) -> str | None:
    lines = makefile.read_text().splitlines()
    for i, line in enumerate(lines):
        if line.startswith("test-integration:"):
            for body in lines[i + 1:]:
                if body.startswith("\t"):
                    return body.strip()
                if body.strip():
                    return None
    return None


def count(directory: pathlib.Path, cmd: str) -> tuple[int, str]:
    env = {**os.environ, "GOWORK": "off", "PYTHONDONTWRITEBYTECODE": "1"}
    if cmd.startswith("go test"):
        args = cmd.split()[2:]
        args = [a for a in args if not a.startswith("-count") and not a.startswith("-run")]
        r = subprocess.run(["go", "test", "-list", ".", *args], cwd=directory, env=env, capture_output=True, text=True)
        if r.returncode:
            return 0, (r.stderr or r.stdout)[-300:]
        listed = {line for line in r.stdout.splitlines() if re.match(r"^(Test|Example|Fuzz)\w*$", line)}
        # only the tests of files built with the integration tag count: unit tests run by the same command are not
        # integration tests (SF18's command reached the entry package's unit tests and "passed")
        pkgs = [a for a in args if not a.startswith("-") and a != "integration"]
        dirs = subprocess.run(["go", "list", "-tags", "integration", "-f", "{{.Dir}}", *pkgs], cwd=directory, env=env,
                              capture_output=True, text=True).stdout.split()
        tagged = set()
        for d in dirs:
            for f in pathlib.Path(d).glob("*_test.go"):
                text = f.read_text()
                if re.search(r"^//go:build .*\bintegration\b", text, re.M):
                    tagged |= set(re.findall(r"^func ((?:Test|Example|Fuzz)\w*)\(", text, re.M))
        return len(listed & tagged), ""
    if "pytest" in cmd:
        parts = cmd.split()
        parts = [p for p in parts if p not in ("-q",)]
        r = subprocess.run([*parts, "--collect-only", "-q", "-p", "no:cacheprovider"], cwd=directory, env=env,
                           capture_output=True, text=True)
        tests = [line for line in r.stdout.splitlines() if "::" in line]
        return len(tests), "" if r.returncode in (0, 5) else r.stdout[-300:]
    return -1, f"a command this check does not know: {cmd}"


def main() -> int:
    dirs = [pathlib.Path(d).resolve() for d in sys.argv[1:]] or sorted(
        m.parent for m in ROOT.glob("components/*/*/Makefile") if command(m))
    bad = 0
    for d in dirs:
        cmd = command(d / "Makefile")
        name = d.relative_to(ROOT) if d.is_relative_to(ROOT) else d
        if cmd is None:
            print(f"✗ {name}: no test-integration target")
            bad += 1
            continue
        n, err = count(d, cmd)
        if n <= 0:
            print(f"✗ {name}: `{cmd}` reaches no integration test{(': ' + err) if err else ''}")
            bad += 1
        else:
            print(f"✓ {name}: {n} integration test(s)")
    if bad:
        print(f"integration-targets-check: {bad} component(s) whose make test-integration tests nothing", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
