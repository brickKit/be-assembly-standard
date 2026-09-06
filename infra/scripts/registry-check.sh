#!/usr/bin/env bash
# 端口册与 schema 册的自洽校验。Task 8 之后由 be-ops 接管，本脚本改为薄壳
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P="$ROOT/registry/ports.tsv"; S="$ROOT/registry/schemas.tsv"
FAIL=0
err() { echo "✗ $*" >&2; FAIL=1; }

# 1. 列数
while IFS= read -r l; do err "$l"; done < <(awk -F'\t' 'NF && $1 !~ /^#/ && NF != 6 {print "ports.tsv 第 " NR " 行不是 6 列：" $0}' "$P")
while IFS= read -r l; do err "$l"; done < <(awk -F'\t' 'NF && $1 !~ /^#/ && NF != 4 {print "schemas.tsv 第 " NR " 行不是 4 列：" $0}' "$S")

# 2. 端口两两不重复。两个例外：
#    ① slot:frontend 族共用 80（总纲 §2.1）
#    ② ⚠️ 实测修正：_infra- 前缀的带外容器互相之间允许同端口——它们是
#       互斥替换件（rustfs/minio 同为 9000、traefik/nginx 同为 80），
#       永不同时跑。原规则没考虑带外容器段是后回写补入的（见本文件同目录
#       ports.tsv 的注释），一上来就把这两对合法的互斥对报成"冲突"。
#       判据：冲突双方只要有一个不是 _infra- 前缀，就是真冲突；
#       两边都是 _infra- 前缀，跳过。
dups="$(awk -F'\t' '
  NF && $1 !~ /^#/ {
    if ($3 != "-" && $3 != "80") p[$3] = p[$3] " " $1
    if ($4 != "-")               p[$4] = p[$4] " " $1
  }
  END {
    for (k in p) {
      n = split(p[k], a, " ")
      if (n > 1) {
        real = 0
        for (i = 1; i <= n; i++) if (a[i] !~ /^_infra-/) real = 1
        if (real) print k ":" p[k]
      }
    }
  }' "$P")"
[[ -n "$dups" ]] && err "端口重复：$dups"

# 3. 用 80 的必须是 frontend-* 或带外网关容器（traefik/nginx，两者互斥）
bad80="$(awk -F'\t' 'NF && $1 !~ /^#/ && $3=="80" && $1 !~ /^frontend-/ && $1 !~ /^_infra-/ {print $1}' "$P")"
[[ -n "$bad80" ]] && err "非 frontend/带外网关占用 80：$bad80"

# 4. 两张表的 repo 集合关系：schemas 里的 repo 必须在 ports 里存在
while IFS=$'\t' read -r repo _ _ _; do
  [[ -z "$repo" || "$repo" == \#* ]] && continue
  grep -qP "^\Q$repo\E\t" "$P" || err "schemas.tsv 里的 $repo 不在 ports.tsv 里"
done < "$S"

# 5. schema/role 命名规则：schema = repo 的 - 换 _；role = schema + _rw
while IFS=$'\t' read -r repo schema role _; do
  [[ -z "$repo" || "$repo" == \#* ]] && continue
  want_schema="${repo//-/_}"
  [[ "$schema" == "$want_schema" ]] || err "$repo 的 schema 应为 $want_schema，实际 $schema"
  [[ "$role" == "${schema}_rw" ]]   || err "$repo 的 role 应为 ${schema}_rw，实际 $role"
done < "$S"

# 6. 组件数核对：ports.tsv 里非 _infra- 前缀的行必须正好 62 行
n="$(awk -F'\t' 'NF && $1 !~ /^#/ && $1 !~ /^_infra-/' "$P" | wc -l)"
[[ "$n" -eq 62 ]] || err "ports.tsv 里的组件行数是 $n，应为 62（设计书附录 H）"

((FAIL)) && exit 1
echo "✓ 端口册与 schema 册自洽（62 个组件 + 带外容器，端口两两不重复）"
