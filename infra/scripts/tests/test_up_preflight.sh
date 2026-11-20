#!/usr/bin/env bash
# up.sh 的预检：停着的项目容器（机器重启后）不算不符，阶段二照常启动；停着而端口被别人占的拦下；
# 运行中而端口没发布的照旧拦下。docker 由一个假的脚本扮演（只回答预检与启动会问的）。
set -uo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/infra/scripts" "$T/bin"
cp "$SRC/infra/scripts/up.sh" "$SRC/infra/scripts/lib.sh" "$T/infra/scripts/"
printf '#!/usr/bin/env bash\necho "CHECK RAN"\n' > "$T/infra/scripts/check.sh"
: > "$T/.env"; : > "$T/infra/docker-compose.infra.yml"
printf 'pg\tbe-infra\tinfra/docker-compose.infra.yml\tpostgres\tbe-pg\timg:1\t59432\tyes\t\t\n' > "$T/infra/resources.tsv"
cat > "$T/bin/docker" <<'FAKE'
#!/usr/bin/env bash
# state: $FAKE_RUNNING (true/false), $FAKE_PUBLISHED (ports), $FAKE_OTHER (a container holding 5432)
case "$1 $2" in
  "network inspect") exit 0;;
  "inspect -f")
    case "$3" in
      *Config.Image*) echo img:1;;
      *State.Running*) echo "$FAKE_RUNNING";;
      *State.Health*) echo healthy;;
    esac; exit 0;;
  "inspect be-pg") exit 0;;
  "port be-pg") for p in $FAKE_PUBLISHED; do echo "59432/tcp -> 0.0.0.0:$p"; done; exit 0;;
  "ps --format") [ -n "${FAKE_OTHER:-}" ] && printf 'other\t0.0.0.0:59432->59432/tcp\n'; exit 0;;
  "compose --env-file") echo "COMPOSE UP"; exit 0;;
esac
exit 0
FAKE
chmod +x "$T/bin/docker"
export PATH="$T/bin:$PATH"
fail=0; chk() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1" >&2; echo "$out" >&2; fail=1; fi; }

out="$(FAKE_RUNNING=false FAKE_PUBLISHED= bash "$T/infra/scripts/up.sh" 2>&1)"; rc=$?
chk "停着的容器：预检通过、照常启动" '[ $rc -eq 0 ] && echo "$out" | grep -q "COMPOSE UP"'
out="$(FAKE_RUNNING=false FAKE_PUBLISHED= FAKE_OTHER=1 bash "$T/infra/scripts/up.sh" 2>&1)"; rc=$?
chk "停着而端口被别人占：拦下" '[ $rc -ne 0 ] && echo "$out" | grep -q "已被 容器 other 占用" && ! echo "$out" | grep -q "COMPOSE UP"'
out="$(FAKE_RUNNING=true FAKE_PUBLISHED= bash "$T/infra/scripts/up.sh" 2>&1)"; rc=$?
chk "运行中而端口没发布：照旧拦下" '[ $rc -ne 0 ] && echo "$out" | grep -q "端口 59432 未发布"'
out="$(FAKE_RUNNING=true FAKE_PUBLISHED=59432 bash "$T/infra/scripts/up.sh" 2>&1)"; rc=$?
chk "运行中且就绪：通过" '[ $rc -eq 0 ]'
[ $fail -eq 0 ] && echo PASS || { echo FAILED >&2; exit 1; }
