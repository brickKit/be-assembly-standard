#!/usr/bin/env bash
# dev-env.sh：空值行被原地填上、已有值不变、只打印变量名；.env 不存在时被创建。
set -uo pipefail
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/infra/scripts/lib" "$T/registry" "$T/shell/be/go-core"
cp "$SRC/infra/scripts/dev-env.sh" "$SRC/infra/scripts/project-lock.sh" "$T/infra/scripts/"
cp "$SRC/infra/scripts/lib/db-pw.sh" "$T/infra/scripts/lib/"
printf '# repo\tschema\trole\tshell\nfoo-bar\tfoo_bar\tfoo_bar_rw\tshell_go_core\nfoo-baz\tfoo_baz\tfoo_baz_rw\tshell_go_core\n' > "$T/registry/schemas.tsv"
: > "$T/registry/ports.tsv"; : > "$T/shell/be/go-core/component.yaml"
export BE_PROJECT_LOCK="$T/lock"; unset BE_PROJECT_LOCK_HELD
fail=0; chk() { if eval "$2"; then echo "  ok   $1"; else echo "  FAIL $1" >&2; fail=1; fi; }

printf 'OTHER=keep\nFOO_BAR_DB_PASSWORD=\nFOO_BAZ_DB_PASSWORD=existing' > "$T/.env"
out="$(bash "$T/infra/scripts/dev-env.sh" 2>&1)"; rc=$?
chk "退出码 0" '[ $rc -eq 0 ]'
chk "空值行被填上（原地，只有一行）" '[ "$(grep -c "^FOO_BAR_DB_PASSWORD=" "$T/.env")" = 1 ] && grep -q "^FOO_BAR_DB_PASSWORD=[0-9a-f]\{32\}$" "$T/.env"'
chk "已有值不变" 'grep -q "^FOO_BAZ_DB_PASSWORD=existing$" "$T/.env" && grep -q "^OTHER=keep$" "$T/.env"'
chk "缺失的外壳变量被追加" 'grep -q "^SHELL_GO_CORE_PASSWORD=[0-9a-f]\{32\}$" "$T/.env"'
chk "只打印变量名不打印值" '! echo "$out" | grep -Eq "[0-9a-f]{32}" && echo "$out" | grep -q FOO_BAR_DB_PASSWORD'
before="$(cat "$T/.env")"; bash "$T/infra/scripts/dev-env.sh" >/dev/null 2>&1
chk "重跑幂等" '[ "$before" = "$(cat "$T/.env")" ]'
rm "$T/.env"; bash "$T/infra/scripts/dev-env.sh" >/dev/null 2>&1
chk ".env 不存在时被创建并写满" '[ "$(grep -c "=[0-9a-f]\{32\}$" "$T/.env")" = 3 ]'
chmod 444 "$T/.env"; out="$(bash "$T/infra/scripts/dev-env.sh" 2>&1)"
chmod 644 "$T/.env"
[ "$(id -u)" = 0 ] || chk "只读 .env 给人话报错" 'echo "$out" | grep -q 不可写'
[ $fail -eq 0 ] && echo PASS || { echo FAILED >&2; exit 1; }
