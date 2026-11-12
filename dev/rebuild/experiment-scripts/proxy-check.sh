#!/bin/bash
# Before a cell's build (C7 retro R3): every brickKit module a Go shell of the cell pins must be served by the public
# Go proxy. A fetch the proxy once failed (a module released minutes before, GitHub unreachable) stays cached as a
# failure for about 30 minutes, and inside the build it only shows as "git not found". Checks each pinned module's
# .info every minute until all answer 200, up to PROXY_WAIT minutes (default 45); fails naming the missing ones.
# The shells' go.mod come from the assembly's shell submodules at the cell's shell versions (bare tags).
# Usage: proxy-check.sh <cell directory>
set -u
D=$1; R=/home/zhijie/Desktop/github/be-assembly-standard; WAIT=${PROXY_WAIT:-45}
mods=$(awk '/^  - id:/{id=$3} /^    version:/{v=$2} /^    kind: shell/{print id, v}' "$D/brickkit.yaml" | while read -r id v; do
  git -C "$R/shell/$id" show "$v:go.mod" 2>/dev/null | awk '$1 ~ /^github.com\/brickKit\// && $2 ~ /^v/ {print $1, $2}'
done | sort -u)
[ -n "$mods" ] || { echo "no Go shell in $D/brickkit.yaml (or its go.mod not found): nothing to check"; exit 0; }
echo "$(echo "$mods" | wc -l) pinned modules"
deadline=$(( $(date +%s) + WAIT * 60 ))
while true; do
  missing=$(echo "$mods" | while read -r m v; do
    esc=$(echo "$m" | sed 's/[A-Z]/!\L&/g')
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "https://proxy.golang.org/$esc/@v/$v.info")
    [ "$code" = 200 ] || echo "$m@$v ($code)"
  done)
  [ -z "$missing" ] && { echo "the proxy serves every pinned module"; exit 0; }
  echo "$(date -Is) not served yet: $(echo "$missing" | tr '\n' ' ')"
  [ "$(date +%s)" -lt "$deadline" ] || { echo "still not served after $WAIT minutes"; exit 1; }
  sleep 60
done
