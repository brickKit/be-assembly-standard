#!/usr/bin/env python3
"""One be-sdk-go version across the system (the rule: one version of a library in the whole system, every component
moved together): every component on be-sdk-go/v3, in dependency order, then the Go probes and the Go shells. Foundations
item 4 did this four times by hand-copied scripts (its retro R4).

Usage: sdk-unify.py --sdk v3.0.0-alpha.N --line "<design.md status line, Chinese>" --notes "<release notes, Chinese>"
                    --subject "<commit subject, English; {version} is the component's>" [--dry-run] [--from ID]
                    [--moved ID ...]

--moved ID: a component already released with a change of its own (its new version committed): every component that
depends on it moves for its pins, and theirs in turn. With --sdk the version they are all on, that is the cascade of
one component's release alone (C1 E0b: mdm/org 3.0.34's positions moved partner, product and the ERP members).

For each component: the last digit of its version up; its exact dependencies on the components moved before it set to
their new versions (a component already released on the SDK still moves when something it depends on moves); `go get` the SDK, `go mod tidy`; `go vet`, the unit tests, the integration tests (`-p 1`, the
environment of itenv.sh and iamenv.sh, secrets never printed); a status line at the top of docs/design.md's
implementation status; `brickkit lint`; commit, push, `brickkit release --notes-file`. A failure stops the run there:
fix it and go on with --from ID (the components before it are done). Still by hand after it: the Go probe (probes/go
to the SDK, its version up, variants.py, `make check`, `make probes`, brickkit release for go…go4, the suite's v1.0.x
tag), the shells be/go-infra and be/go-core (members' versions, the probe, the SDK; tests; release), the recovery
tool tools/be-ops (the SDK, `go test -race ./...`, the integration tests of internal/recovery, an annotated tag
v3.0.0-alpha.N+1), `make docs-index`, `make version-check` (pin-check's one-SDK check names whatever was left
behind) and the parent repository's commit.
--dry-run prints the order and the versions and changes nothing. Output: one line per step ("UNIFY <id> ..."), and
"UNIFY ALL-DONE" (or "UNIFY FAILED <id> <stage>") last: run it in the background with a monitor (f-longrun).
"""
import argparse
import os
import pathlib
import re
import subprocess
import sys
import tempfile

import yaml

R = pathlib.Path(__file__).resolve().parents[3]
SCRIPTS = R / "dev" / "rebuild" / "experiment-scripts"


def sh(cmd: str, cwd: pathlib.Path, log: pathlib.Path | None = None) -> None:
    """A command in bash with the components' test environment sourced (compenv.sh: it reads .env, prints nothing)."""
    full = f". {SCRIPTS}/compenv.sh && {cmd}"
    with open(log or os.devnull, "a") as out:
        subprocess.run(["bash", "-c", full], cwd=cwd, stdout=out, stderr=subprocess.STDOUT, check=True,
                       env=dict(os.environ, GOPROXY="direct", GONOSUMDB="github.com/brickKit/*"))


def components() -> dict[str, pathlib.Path]:
    """The components on be-sdk-go/v3 (the rebuilt ones; the 2.x ones are on v0 and not part of the system)."""
    out = {}
    for gomod in sorted((R / "components").glob("*/*/go.mod")):
        if "github.com/brickKit/be-sdk-go/v3 " in gomod.read_text():
            d = gomod.parent
            out[f"{d.parent.name}/{d.name}"] = d
    return out


def deps(d: pathlib.Path) -> list[str]:
    m = yaml.safe_load((d / "component.yaml").read_text())
    out = []
    for e in (m.get("dependencies") or {}).get("components") or []:
        ref = e["id"] if isinstance(e, dict) else e
        out.append(ref.split("@")[0])
    return out


def order(cs: dict[str, pathlib.Path]) -> list[str]:
    """Dependency order; the security members (infra/*) first, then master data, then the rest, alphabetically
    among equals."""
    layer = {"infra": 0, "mdm": 1}
    rest, done = sorted(cs, key=lambda c: (layer.get(c.split("/")[0], 2), c)), []
    while rest:
        for c in rest:
            if all(d not in cs or d in done for d in deps(cs[c])):
                done.append(c)
                rest.remove(c)
                break
        else:
            sys.exit(f"a dependency cycle among {rest}")
    return done


def bump(v: str) -> str:
    a, b, c = v.split(".")
    return f"{a}.{b}.{int(c) + 1}"


def version_of(d: pathlib.Path) -> str:
    """The version in the working tree."""
    return yaml.safe_load((d / "component.yaml").read_text())["metadata"]["version"]


def committed_version(d: pathlib.Path) -> str:
    """The version of the last commit: a run stopped midway leaves the working tree at the new version, which must not
    be bumped again."""
    out = subprocess.run(["git", "show", "HEAD:component.yaml"], cwd=d, capture_output=True, text=True, check=True)
    return yaml.safe_load(out.stdout)["metadata"]["version"]


def edit_component(d: pathlib.Path, new: str, moved: dict[str, str]) -> None:
    # the version constant: in the entry package's definition.go, or internal/core/names.go when the modules use it
    version = re.compile(r'(\n\tVersion\s+= )"[0-9.]+"')
    defs = [p for p in sorted(d.rglob("*.go")) if not p.name.endswith("_test.go") and "contract" not in p.parts
            and "cmd" not in p.parts and version.search(p.read_text())]
    assert len(defs) == 1, f"{d}: the Version constant in {defs}"
    s, n = version.subn(r'\1"' + new + '"', defs[0].read_text(), count=1)
    defs[0].write_text(s)
    c = (d / "component.yaml").read_text()
    c, n = re.subn(r"(\n  version: )[0-9.]+", r"\g<1>" + new, c, count=1)
    assert n == 1, d
    for other, v in moved.items():
        c = re.sub(r"(- (?:id: )?" + re.escape(other) + r")@[0-9.]+", r"\1@" + v, c)
    (d / "component.yaml").write_text(c)


def status_line(d: pathlib.Path, new: str, line: str) -> None:
    p = d / "docs" / "design.md"
    s = p.read_text()
    m = re.search(r"\n(3\.0\.\d+)[（：]", s)
    assert m, f"{p}: no implementation status line"
    # the line follows the version the script writes; a "{version}" in it is not filled in (C7: 71 lines carried one)
    assert "{version}" not in line, "--line: the version is written before it; leave {version} out"
    sep = "" if line.startswith("（") else "："  # "3.0.24（why）：what" as the existing lines, or "3.0.24：what"
    p.write_text(s[:m.start() + 1] + f"{new}{sep}{line}\n\n" + s[m.start() + 1:])


def release(d: pathlib.Path, subject: str, notes: str, log: pathlib.Path) -> None:
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as msg, \
            tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as nf:
        msg.write(subject + "\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n")
        nf.write(notes + "\n")
    sh(f"brickkit lint && git add -A && git commit -q -F {msg.name} && git push -q && brickkit release --notes-file "
       f"{nf.name}", d, log)
    if "✅ Released" not in log.read_text():
        raise RuntimeError("brickkit release did not say Released")


def main() -> int:
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("--sdk", required=True)
    a.add_argument("--line", required=True)
    a.add_argument("--notes", required=True)
    a.add_argument("--subject", required=True)
    a.add_argument("--from", dest="start")
    a.add_argument("--moved", action="append", default=[], help="a component released already; its dependents move")
    a.add_argument("--dry-run", action="store_true")
    a.add_argument("--logs", help="where each component's log goes (default: a new temporary directory)")
    o = a.parse_args()
    cs = components()
    seq = order(cs)
    if o.start:  # the components before it are done: their released versions are the ones to pin
        done, seq = seq[:seq.index(o.start)], seq[seq.index(o.start):]
    else:
        done = []
    # a component already released on this SDK (moved with a change of its own) is done too
    on = [c for c in seq if f"github.com/brickKit/be-sdk-go/v3 {o.sdk}" in
          subprocess.run(["git", "show", "HEAD:go.mod"], cwd=cs[c], capture_output=True, text=True).stdout]
    # ... unless something it depends on moves in this run, or was released before it (--moved): then it moves too,
    # for its pins; a --moved component itself is done at its committed version
    for c in o.moved:
        assert c in cs, f"--moved {c}: not a component"
        if c in on:
            on.remove(c)
        seq = [x for x in seq if x != c]
        done = done + [c]
    moving = set(c for c in seq if c not in on) | set(o.moved)
    changed = True
    while changed:
        changed = False
        for c in list(on):
            if any(d in moving for d in deps(cs[c])):
                on.remove(c)
                moving.add(c)
                changed = True
    done, seq = done + on, [c for c in seq if c not in on]
    plan = {c: committed_version(cs[c]) for c in done} | {c: bump(committed_version(cs[c])) for c in seq}
    print(f"UNIFY plan to be-sdk-go {o.sdk}:", ", ".join(f"{c} {plan[c]}" for c in seq),
          f"(already on it: {', '.join(on) or 'none'})", flush=True)
    if o.dry_run:
        return 0
    logs = pathlib.Path(o.logs or tempfile.mkdtemp(prefix="sdk-unify-"))
    logs.mkdir(parents=True, exist_ok=True)
    print(f"UNIFY logs in {logs}", flush=True)
    for c in seq:
        d, new, log = cs[c], plan[c], logs / f"{c.replace('/', '-')}.log"
        stage = "edit"
        try:
            print(f"UNIFY {c} BEGIN {new}", flush=True)
            if version_of(d) != new:
                edit_component(d, new, {k: v for k, v in plan.items() if k != c})
                status_line(d, new, o.line)
            sh(f"go get github.com/brickKit/be-sdk-go/v3@{o.sdk} && go mod tidy", d, log)
            stage = "unit"
            sh("go vet ./... && go test -count=1 ./...", d, log)
            stage = "integration"
            sh("go test -count=1 -p 1 -tags integration ./...", d, log)
            stage = "release"
            release(d, o.subject.format(version=new), o.notes, log)
            print(f"UNIFY {c} END {new}", flush=True)
        except (subprocess.CalledProcessError, RuntimeError, AssertionError) as e:
            print(f"UNIFY FAILED {c} {stage}: {e} (log {log}; go on with --from {c})", flush=True)
            return 1
    print("UNIFY next by hand: the Go probe, the shells, make docs-index and version-check (see the usage)", flush=True)
    print("UNIFY ALL-DONE", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
