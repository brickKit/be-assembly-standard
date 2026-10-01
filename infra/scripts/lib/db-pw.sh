#!/usr/bin/env bash
# 数据库登录角色密码清单：registry/schemas.tsv 是唯一来源，映射规则与 be-ops 一致
# （be-ops 的 DBPasswordEnv(repo) 与 db-script 的 pw_<role> psql 变量）。
# 供 dev-env.sh 与 db-init.sh source 引入。
#
# db_pw_pairs 逐行输出 "<psql 变量名> <环境变量名>"：
#   组件角色  pw_<schema>_rw        <REPO 大写下划线>_DB_PASSWORD   （erp-sales → ERP_SALES_DB_PASSWORD）
#   外壳角色  pw_shell_go_core      SHELL_GO_CORE_PASSWORD         （角色名大写）
db_pw_pairs() {
  local tsv="$1"
  awk -F'\t' '/^#/ || NF<4 || $1=="repo" {next}
    { env=toupper($1); gsub("-","_",env); print "pw_" $3, env "_DB_PASSWORD"
      if ($4 != "") shells[$4]=1 }
    END { for (s in shells) print "pw_" s, toupper(s) "_PASSWORD" }' "$tsv" | sort -u
}

# db_pw_set_lines <tsv>：向 stdout 输出 psql 的 \set 行（口令走 stdin，不进任何进程的 argv）。
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
