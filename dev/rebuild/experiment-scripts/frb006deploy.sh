#!/bin/bash
# FRB-006 end to end: build the D-H2 cell at the old shell versions, upgrade every shell with brickkit upgrade, check
# the upgraded project equals one created fresh at the new versions, then deploy it, profile it and measure it.
set -u
OUT=$1; R=/home/zhijie/Desktop/github/be-assembly-standard; CONF=$R/tools/be-acceptance/conformance
W=$OUT/cell/D-H2; REF=$R/dev/rebuild/experiment-cells/D-H2
mkdir -p "$OUT/logs" "$W"; echo $$ > "$OUT/pid"
source /tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/50abddb1-4a5f-46f1-951a-1c59973ee1b3/scratchpad/accenv.sh
N=5; I=0
stage() {
  I=$((I+1)); local name=$1; shift; local t0=$(date +%s)
  echo "STAGE $I/$N $name BEGIN $(date -Is)" >> "$OUT/status.log"
  ( "$@" ) > "$OUT/logs/$I-$name.log" 2>&1; local rc=$?
  echo "STAGE $I/$N $name END exit=$rc secs=$(( $(date +%s) - t0 ))" >> "$OUT/status.log"
}
old_cell() {
  sed -e 's/be\/go-core@3.0.4/be\/go-core@3.0.1/; s/be\/go-infra@3.0.4/be\/go-infra@3.0.1/; s/be\/py-render@3.0.5/be\/py-render@3.0.1/' \
    "$REF/cell.yaml" > "$W/cell.yaml" && cat "$W/cell.yaml" && cd "$CONF" && uv run python -m cells create "$W" &&
    sed -n '/^components:/,$p' "$W/brickkit.yaml" && cat "$W/deploy.yaml"
}
upgrade_all() {
  set -e; cd "$W"
  brickkit upgrade be/go-core@3.0.4 --yes; brickkit upgrade be/go-infra@3.0.4 --yes; brickkit upgrade be/py-render@3.0.5 --yes
  sed -n '/^components:/,$p' brickkit.yaml; cat deploy.yaml
}
same_as_fresh() {  # the upgraded project's components and deploy file against the cell created fresh at these versions
  cd "$CONF" && uv run python - "$W" "$REF" <<'PY'
import pathlib, sys, yaml
up, ref = (pathlib.Path(x) for x in sys.argv[1:])
def comps(d): return sorted((c["id"], c["version"]) for c in yaml.safe_load((d / "brickkit.yaml").read_text())["components"])
def dep(d): return yaml.safe_load((d / "deploy.yaml").read_text())["components"]
ok = True
for name, a, b in (("brickkit.yaml components", comps(up), comps(ref)), ("deploy.yaml components", dep(up), dep(ref))):
    print(f"{name}: {'same' if a == b else 'DIFFERENT'}")
    if a != b:
        ok = False
        print("  upgraded:", a); print("  fresh:   ", b)
sys.exit(0 if ok else 1)
PY
}
deploy_profile_measure() {
  cp "$REF/cell.yaml" "$W/cell.yaml"   # the versions the upgrade reached
  cd "$CONF" && uv run python -m cells prepare "$W" || return 1
  cd "$W" && brickkit build && brickkit up || { brickkit down; return 1; }
  cd "$CONF" && uv run python -m cells run "$W" "$OUT/measure/run1/D-H2" --loads 50,200 --idle 15 --warmup 3 --seconds 10
  local rc=$?
  cd "$W" && brickkit up && cd "$CONF" && uv run python -m cells profile "$W"; rc=$((rc + $?))
  cd "$W" && brickkit down
  return $rc
}
echo "START $(date -Is)" >> "$OUT/status.log"
stage create-old old_cell
stage upgrade upgrade_all
stage same-as-fresh same_as_fresh
stage deploy-profile-measure deploy_profile_measure
stage cleanup bash -c 'for p in $(docker ps -a --format "{{.Label \"com.docker.compose.project\"}}" | grep "^brickkit-d-" | sort -u); do docker compose -p $p down --remove-orphans; done'
echo "END $(date -Is)" >> "$OUT/status.log"
