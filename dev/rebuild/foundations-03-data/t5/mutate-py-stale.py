"""P8.29 mutants for be-sdk-python (run from tools/be-sdk-python). Bytecode caching is off: a mutant of the same size
written within the same second as the original would otherwise run from the stale .pyc."""
import os, pathlib, subprocess, sys
M = [
 ("closed not stale", "besdk/authz/view.py", "                h.source_stale = True  # not renewed", "                pass  # not renewed"),
 ("every op falls back", "besdk/authz/view.py", "            if tightening_only and errs.is_(", "            if errs.is_("),
 ("never fully renewed used", "besdk/authz/view.py", "if not h.source_stale or h.high_at is None or", "if not h.source_stale or"),
 ("guard plain lookup", "besdk/guard.py", "self.holder.lookup_for(op.resource_type, user.subject, op.risk_class, op.tightening_only)", "self.holder.lookup(op.resource_type, user.subject, op.risk_class)"),
 ("subject plain lookup", "besdk/authz/subject.py", "self.holder.lookup_for(r.type, self.principal, risk, o.tightening_only)", "self.holder.lookup(r.type, self.principal, risk)"),
 ("read_only unchanged not stale", "besdk/authz/view.py", "h.sent_at, h.suspended, h.source_stale = sent, False, read_only", "h.sent_at, h.suspended = sent, False"),
 ("basis not cleared", "besdk/authz/subject.py", "        _stale.set(None)\n", ""),
 ("since from sent_at", "besdk/authz/view.py", "since=self.wall() + (h.high_at - now)", "since=self.wall() + (h.sent_at - now)"),
 ("full renewal keeps stale", "besdk/authz/view.py", "h.sent_at, h.suspended, h.source_stale = sent, False, read_only", "h.sent_at, h.suspended, h.source_stale = sent, False, h.source_stale or read_only"),
]
for name, f, a, b in M:
    p = pathlib.Path(f); orig = p.read_text()
    assert orig.count(a) == 1, name
    for c in pathlib.Path("besdk").rglob("__pycache__"):
        for f in c.iterdir():
            f.unlink()
    p.write_text(orig.replace(a, b))
    try:
        r = subprocess.run(["uv", "run", "pytest", "-q", "-x", "tests/test_authz.py"], capture_output=True, text=True,
                           env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        last = [l for l in r.stdout.splitlines() if l.startswith("FAILED") or "passed" in l or "failed" in l]
        print(("KILLED " if r.returncode else "SURVIVED ") + name, "|", last[0] if last else r.stdout[-200:])
    finally:
        p.write_text(orig)
