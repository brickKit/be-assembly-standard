"""A chain release: every rebuilt component onto new SDK versions, in dependency order, each with its exact dependencies
moved to the versions just released; build, test, lint, commit, push and `brickkit release --notes-file`. Stops at the
first failure; the shells and the probes follow by hand (their members and modules differ). Each component gets its
own notes file beside the log (step 12's script reused one file, and passed it to --notes, which wrote the path into
65 tags: retro-step12.md P2).
Usage: python3 chain-release.py <log> --go 3.0.0-alpha.40 --py 3.0.0a37 --protocol 3.0.0-alpha.35 \\
         --change "<one sentence: what the SDKs changed>" [component...]"""
import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
ORDER = ["infra/iam-casdoor", "infra/authz", "infra/audit", "mdm/org", "mdm/currency", "infra/print", "mdm/partner",
         "mdm/product", "erp/inventory", "erp/credit", "erp/sales", "erp/billing"]
TRAILER = "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"

a = argparse.ArgumentParser()
a.add_argument("log")
a.add_argument("--go", required=True)
a.add_argument("--py", required=True)
a.add_argument("--protocol", required=True)
a.add_argument("--change", required=True)
a.add_argument("only", nargs="*")
o = a.parse_args()
LOG = open(o.log, "a")
NOTES = pathlib.Path(o.log + ".notes")
NOTES.mkdir(exist_ok=True)


def run(cmd, cwd, check=True):
    LOG.write(f"$ {cmd}  (in {cwd})\n")
    LOG.flush()
    r = subprocess.run(cmd, cwd=cwd, shell=True, capture_output=True, text=True)
    LOG.write(r.stdout[-4000:] + r.stderr[-4000:] + f"exit={r.returncode}\n")
    LOG.flush()
    if check and r.returncode != 0:
        raise SystemExit(f"FAILED: {cmd} in {cwd} (exit {r.returncode})")
    return r.stdout


def version_of(d):
    return re.search(r"(?m)^  version: (\S+)$", (d / "component.yaml").read_text()).group(1)


def bump(v):
    x, y, z = v.split(".")
    return f"{x}.{y}.{int(z) + 1}"


new = {}
for cid in ORDER:
    d = ROOT / "components" / cid
    old = version_of(d)
    if o.only and cid not in o.only:
        new[cid] = old
        continue
    nv = bump(old)
    new[cid] = nv
    y = (d / "component.yaml").read_text().replace(f"  version: {old}\n", f"  version: {nv}\n", 1)
    moved = []
    for dep, dv in new.items():
        dold = re.search(rf"{re.escape(dep)}@(\d+\.\d+\.\d+)", y)
        if dold and dold.group(1) != dv:
            y = y.replace(f"{dep}@{dold.group(1)}", f"{dep}@{dv}")
            moved.append(f"{dep} {dv}")
    (d / "component.yaml").write_text(y)
    python = (d / "pyproject.toml").exists()
    if python:
        p = d / "pyproject.toml"
        t = p.read_text()
        t = re.sub(r'(?m)^version = "[^"]+"$', f'version = "{nv}"', t, count=1)
        t = re.sub(r'"be-sdk>=[^"]+"', f'"be-sdk>={o.py}"', t)
        t = re.sub(r'(be-sdk = \{ git = "https://github.com/brickKit/be-sdk-python", tag = )"v[^"]+"', rf'\1"v{o.py}"', t)
        p.write_text(t)
        run("uv lock -q && uv sync -q", d)
        run("uv run pytest -q", d)
    else:
        files = run(f"grep -rlE 'Version +=  *\"{re.escape(old)}\"' --include=*.go . || true", d).split()
        if not files:
            raise SystemExit(f"FAILED: {cid}: no Version const = {old}")
        for f in files:
            fp = d / f
            fp.write_text(re.sub(rf'(Version +=  *)"{re.escape(old)}"', rf'\g<1>"{nv}"', fp.read_text()))
        run(f"go get github.com/brickKit/be-sdk-go/v3@v{o.go} && go mod tidy", d)
        run("go build ./... && go vet ./... && go test ./...", d)
    run("brickkit lint", d)
    sdk = f"be-sdk-python {o.py}" if python else f"be-sdk-go {o.go}"
    deps = f"; depends on {', '.join(moved)}" if moved else ""
    msg = NOTES / f"{cid.replace('/', '-')}-{nv}.msg"
    notes = NOTES / f"{cid.replace('/', '-')}-{nv}.md"
    msg.write_text(f"chore: {sdk}{deps}; {nv}\n\n{o.change}\n\n{TRAILER}\n")
    notes.write_text(f"{cid} on {sdk} (be-protocol {o.protocol}).\n\n## What you must do\n\n"
                     + (f"Upgrade {', '.join(m.split()[0] for m in moved)} with it: this version names their exact "
                        "versions.\n" if moved else "Nothing.\n")
                     + f"\n## Changed\n\n- The SDK: {o.change}\n" + "".join(f"- Depends on {m}.\n" for m in moved))
    run(f"git add -A && git commit -q -F {msg} && git push -q", d)
    run(f"brickkit release --notes-file {notes}", d)
    head = run(f"git for-each-ref refs/tags/{nv} --format='%(contents:subject)'", d).strip()
    if head.startswith("/"):
        raise SystemExit(f"FAILED: {cid} {nv}: the tag's notes are a path: {head}")
    LOG.write(f"RELEASED {cid} {old} -> {nv}{deps}\n")
    LOG.flush()
    print(f"RELEASED {cid} {old} -> {nv}{deps}", flush=True)
print("CHAIN ALL-DONE", flush=True)
