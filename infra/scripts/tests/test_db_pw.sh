#!/usr/bin/env bash
# db-pw.sh：外壳登录角色的推导必须与 be-ops db-script 一致——ports.tsv 的 _shell-<name> 行
# ∪ shell/be/<name>/component.yaml，而不是 schemas.tsv 第 4 列（那一列可能留着已退役的外壳）。
set -euo pipefail
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/registry" "$T/shell/be/go-core" "$T/shell/be/manifest-only"
printf '# repo\tschema\trole\tshell_login_role\n' > "$T/registry/schemas.tsv"
printf 'erp-sales\terp_sales\terp_sales_rw\tshell_go_core\n' >> "$T/registry/schemas.tsv"
printf 'ana-ai\tana_ai\tana_ai_rw\tshell_py_brain\n' >> "$T/registry/schemas.tsv"
printf '# repo\tcomponent_id\thttp_port\tgrpc_port\tshell\tnote\n' > "$T/registry/ports.tsv"
printf 'erp-sales\terp/sales\t8084\t9094\tgo-core\t-\n' >> "$T/registry/ports.tsv"
printf '_shell-go-core\tbe/go-core\t8090\t-\tstandalone\t-\n' >> "$T/registry/ports.tsv"
printf '_shell-new-one\tbe/new-one\t8091\t-\tstandalone\t-\n' >> "$T/registry/ports.tsv"
printf 'shell:\n  members: []\n' > "$T/shell/be/go-core/component.yaml"
printf 'shell:\n  members: []\n' > "$T/shell/be/manifest-only/component.yaml"

# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/db-pw.sh"
out="$(db_pw_pairs "$T")"
fail=0
expect() { grep -qx "$1" <<<"$out" || { echo "✗ 缺少：$1"; fail=1; }; }
reject() { ! grep -q "$1" <<<"$out" || { echo "✗ 不该有：$1"; fail=1; }; }
expect "pw_erp_sales_rw ERP_SALES_DB_PASSWORD"
expect "pw_ana_ai_rw ANA_AI_DB_PASSWORD"
expect "pw_shell_go_core SHELL_GO_CORE_PASSWORD"
expect "pw_shell_new_one SHELL_NEW_ONE_PASSWORD"          # 只在 ports.tsv 里
expect "pw_shell_manifest_only SHELL_MANIFEST_ONLY_PASSWORD" # 只有外壳清单
reject "shell_py_brain"                                    # schemas.tsv 第 4 列里已退役的外壳
[ "$(grep -c '^pw_shell_go_core ' <<<"$out")" = 1 ] || { echo "✗ pw_shell_go_core 重复"; fail=1; }
if [ $fail = 0 ]; then echo "✓ test_db_pw：外壳登录角色与 be-ops 同源（ports.tsv _shell-* ∪ shell/be/*）"; fi
exit $fail
