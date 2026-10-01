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
