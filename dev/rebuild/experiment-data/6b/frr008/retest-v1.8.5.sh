#!/bin/bash
# FRR-008 retest on the installed CLI: (A) add a dependent that keeps an older version; (A2) build with its deploy entry
# removed; (B) a dependent that follows (no kept version, no note); (C) upgrade the default version while a dependent
# keeps the old one.
B=$(cd "$(dirname "$0")" && pwd)
brickkit --version | head -1
proj() { rm -rf "$B/$1" && mkdir -p "$B/$1" && cd "$B/$1" && brickkit init --yes --no-skills > /dev/null && python3 - <<'PY'
import pathlib
p=pathlib.Path("brickkit.yaml"); s=p.read_text()
s=s.replace("  # More sources: uncomment and fill in the address", "  - name: brickkit-github\n    type: git\n    baseUrl: https://github.com/brickKit/\n  # More sources: uncomment and fill in the address")
p.write_text(s)
PY
}
show() { grep -v '^\s*$\|Fill in the required\|Config skeletons\|^{"time"' ; }
echo "=== A: add mdm/org@3.0.2, then mdm/partner@3.0.2 (depends on mdm/org@3.0.1)"
proj A; brickkit add mdm/org@3.0.2 --yes 2>&1 | show; brickkit add mdm/partner@3.0.2 --yes 2>&1 | show
echo "=== A2: the kept version's deploy entry removed; build"
sed -i '/  - id: mdm\/org@3.0.1/d' deploy.yaml; brickkit build 2>&1 | grep -v '^{"time"' | head -4
echo "=== B: add mdm/org@3.0.2, then mdm/partner@3.0.3 (depends on mdm/org@3.0.2)"
proj B; brickkit add mdm/org@3.0.2 --yes 2>&1 | show; brickkit add mdm/partner@3.0.3 --yes 2>&1 | show
sed -n '/^components:/,/^[a-z]/p' brickkit.yaml
echo "=== C: add mdm/partner@3.0.2 (brings mdm/org@3.0.1), then upgrade mdm/org@3.0.2"
proj C; brickkit add mdm/partner@3.0.2 --yes 2>&1 | show; brickkit upgrade mdm/org@3.0.2 --yes 2>&1 | show
sed -n '/^components:/,/^[a-z]/p' brickkit.yaml
