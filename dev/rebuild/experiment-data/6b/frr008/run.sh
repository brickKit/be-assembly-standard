#!/bin/bash
# FRR-008 repro: a dependent pins an older exact version of a component the project upgraded; what add says, and
# what build says once the deploy file lacks the kept version's entry. BrickKit CLI v1.8.4.
D=$(cd "$(dirname "$0")" && pwd)/proj
rm -rf "$D" && mkdir -p "$D" && cd "$D"
brickkit init --yes --no-skills > /dev/null
python3 - <<'PY'
import pathlib
p=pathlib.Path("brickkit.yaml"); s=p.read_text()
s=s.replace("  # More sources: uncomment and fill in the address", """  - name: brickkit-github
    type: git
    baseUrl: https://github.com/brickKit/
  # More sources: uncomment and fill in the address""")
p.write_text(s)
PY
echo "== add mdm/org@3.0.2"; brickkit add mdm/org@3.0.2 --yes 2>&1 | grep -v "^\s*$" | tail -12
echo "== add mdm/partner@3.0.2 (depends on mdm/org@3.0.1)"; brickkit add mdm/partner@3.0.2 --yes 2>&1 | grep -v "^\s*$" | tail -15
echo "== brickkit.yaml components"; sed -n '/^components:/,/^[a-z]/p' brickkit.yaml
echo "== deploy.yaml components as add wrote them"; sed -n '/^components:/,$p' deploy.yaml
echo "== deploy.yaml rewritten with bare IDs only; brickkit build"
python3 - <<'PY'
import pathlib,re
p=pathlib.Path("deploy.yaml"); s=p.read_text()
s=re.sub(r"\n  - id: mdm/org@3\.0\.1[^\n]*(\n    [^\n]*)*", "", s)
p.write_text(s)
PY
sed -n '/^components:/,$p' deploy.yaml
brickkit build 2>&1 | grep -v '^{"time"' | head -12
