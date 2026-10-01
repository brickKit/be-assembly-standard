#!/usr/bin/env bash
# 数据库登录角色密码清单，推导规则与 be-ops db-script 一致：
#   组件角色：registry/schemas.tsv 每一行的 role 列（<schema>_rw）；
#   外壳角色：registry/ports.tsv 的 _shell-<name> 行 ∪ shell/be/<name>/component.yaml（be-ops
#             的 ShellNamesFromRepos + LoadShells）。不读 schemas.tsv 第 4 列——它可能还留着已退役的外壳。
# 供 dev-env.sh、db-init.sh、test-db-init.sh source 引入；参数一律是装配仓库根目录。
#
# db_pw_pairs <root> 逐行输出 "<psql 变量名> <环境变量名>"：
#   组件角色  pw_<schema>_rw        <REPO 大写下划线>_DB_PASSWORD   （erp-sales → ERP_SALES_DB_PASSWORD）
#   外壳角色  pw_shell_go_core      SHELL_GO_CORE_PASSWORD         （角色名大写）
db_pw_pairs() {
  local root="$1" d
  {
    awk -F'\t' '/^#/ || NF<4 || $1=="repo" {next}
      { env=toupper($1); gsub("-","_",env); print "pw_" $3, env "_DB_PASSWORD" }' "$root/registry/schemas.tsv"
    {
      awk -F'\t' '$1 ~ /^_shell-/ { sub(/^_shell-/, "", $1); print $1 }' "$root/registry/ports.tsv"
      for d in "$root"/shell/be/*/component.yaml; do
        [ -f "$d" ] && basename "$(dirname "$d")"
      done
    } | awk '{ r="shell_" $0; gsub("-","_",r); print "pw_" r, toupper(r) "_PASSWORD" }'
  } | sort -u
}

# db_pw_set_lines <root>：向 stdout 输出 psql 的 \set 行（口令走 stdin，不进任何进程的 argv）。
# 缺失/为空的环境变量名收集到全局数组 DB_PW_MISSING，不输出值。
# psql 单引号参数的转义：' → ''，\ → \\。
db_pw_set_lines() {
  DB_PW_MISSING=()
  local pv ev val
  while read -r pv ev; do
    val="${!ev:-}"
    if [ -z "$val" ]; then DB_PW_MISSING+=("$ev"); continue; fi
    val="${val//\\/\\\\}"; val="${val//\'/\'\'}"
    printf '\\set %s '"'"'%s'"'"'\n' "$pv" "$val"
  done < <(db_pw_pairs "$1")
}
