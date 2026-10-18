#!/bin/bash
# FRR-007 retest with the installed brickkit CLI: local git repos as the source, the R66 structure,
# plus the R63 and R65 situations to check their output is unchanged.
set -u
B=$(cd "$(dirname "$0")" && pwd)/run; rm -rf "${B:?}"; mkdir -p "$B/org" "$B/work"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

manifest() {  # id version port [requires] [members] [configkey]
  local id=$1 v=$2 port=$3 req=${4:-} mem=${5:-} key=${6:-}
  printf 'apiVersion: brickkit/v1\nkind: Component\nmetadata:\n  id: %s\n  name: repro %s\n  version: %s\n  description: FRR-007 repro\n' "$id" "$id" "$v"
  [ -n "$req" ] && printf 'dependencies:\n  components:\n' && for r in $req; do printf '    - %s\n' "$r"; done
  [ -n "$mem" ] && printf 'shell:\n  members:\n' && for m in $mem; do printf '    - %s\n' "$m"; done
  [ -n "$key" ] && printf 'configSchema:\n  type: object\n  properties:\n    %s:\n      type: string\n      default: ""\n' "$key"
  printf 'deployment:\n  type: container\n  image: repro/%s:%s\n  port: %s\nhealthCheck:\n  type: http\n  path: /healthz\n' "${id//\//-}" "$v" "$port"
}
release() {  # org id version port [requires] [members] [configkey]
  local org=$1; shift; local name=${1//\//-}; local bare=$B/$org/$name.git w=$B/work/$org-$name
  [ -d "$bare" ] || { git init -q --bare "$bare"; git init -q "$w"; git -C "$w" remote add origin "$bare"; }
  manifest "$@" > "$w/component.yaml"
  git -C "$w" add -A && git -C "$w" commit -qm "release $2" && git -C "$w" tag "$2" && git -C "$w" push -q origin HEAD:refs/heads/main "$2"
}
project() {  # dir org
  mkdir -p "$1"
  printf 'project: repro\nsources:\n  - name: org\n    type: git\n    baseUrl: file://%s/\ncomponents: []\n' "$B/$2" > "$1/brickkit.yaml"
  printf 'target: docker\ncomponents: []\n' > "$1/deploy.yaml"
}
step() { echo; echo "## $*"; }
run() { echo "\$ brickkit $*"; brickkit "$@" 2>&1; echo "(exit $?)"; }

echo "# $(brickkit --version | head -1)"

echo; echo "################ R66: a removed member becomes required, comes back"
O=org66; P=$B/p66
release $O frr66/a 1.0.0 8081; release $O frr66/b 1.0.0 8082 "" "" B_URL
release $O frr66/shell 1.0.0 8080 "" "frr66/a@1.0.0 frr66/b@1.0.0"
project $P $O; cd $P
step "add the shell, write a value into b's config, remove b"
run add frr66/shell@1.0.0 --yes
sed -i 's|^# B_URL: .*|B_URL: http://b.internal|' config/frr66-b.yaml; grep -n "B_URL" config/frr66-b.yaml
run remove frr66/b
ls config config/.archive 2>&1
release $O frr66/a 2.0.0 8081 "frr66/b@2.0.0"; release $O frr66/b 2.0.0 8082 "" "" B_URL
release $O frr66/shell 2.0.0 8080 "" "frr66/a@2.0.0 frr66/b@2.0.0"
step "upgrade --dry-run"
run upgrade frr66/shell@2.0.0 --dry-run
step "upgrade"
run upgrade frr66/shell@2.0.0 --yes
step "result"
sed -n '/^components:/,$p' brickkit.yaml; cat deploy.yaml; grep -n "B_URL" config/frr66-b.yaml
run up --dry-run

echo; echo "################ R63: a removed member stays out; a newly compiled-in member joins"
O=org63; P=$B/p63
release $O frr63/a 1.0.0 8081; release $O frr63/b 1.0.0 8082
release $O frr63/shell 1.0.0 8080 "" "frr63/a@1.0.0 frr63/b@1.0.0"
project $P $O; cd $P
run add frr63/shell@1.0.0 --yes
run remove frr63/b
release $O frr63/a 2.0.0 8081; release $O frr63/b 2.0.0 8082; release $O frr63/c 1.0.0 8083
release $O frr63/shell 2.0.0 8080 "" "frr63/a@2.0.0 frr63/b@2.0.0 frr63/c@1.0.0"
run upgrade frr63/shell@2.0.0 --yes
sed -n '/^components:/,$p' brickkit.yaml; cat deploy.yaml; ls config
run up --dry-run

echo; echo "################ R65: removed from shell B's offer, shell A newly compiles it in: stays out"
O=org65; P=$B/p65
release $O frr65/a 1.0.0 8081; release $O frr65/b 1.0.0 8082
release $O frr65/sa 1.0.0 8080 "" "frr65/a@1.0.0"
release $O frr65/sb 1.0.0 8090 "" "frr65/b@1.0.0"
project $P $O; cd $P
run add frr65/sa@1.0.0 --yes
run add frr65/sb@1.0.0 --yes
run remove frr65/b
release $O frr65/b 2.0.0 8082; release $O frr65/a 2.0.0 8081
release $O frr65/sa 2.0.0 8080 "" "frr65/a@2.0.0 frr65/b@2.0.0"
run upgrade frr65/sa@2.0.0 --yes
sed -n '/^components:/,$p' brickkit.yaml; cat deploy.yaml; ls config
run up --dry-run
