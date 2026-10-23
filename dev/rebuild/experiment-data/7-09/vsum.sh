#!/usr/bin/env bash
# Prints, for every business table of the cell (a version column, not partitions' parents twice), row count and sum(version).
q="select format('select %L, count(*), coalesce(sum(version),0) from %I.%I', table_schema||'.'||table_name, table_schema, table_name)
   from information_schema.columns c join pg_class k on k.relname=c.table_name join pg_namespace n on n.oid=k.relnamespace and n.nspname=c.table_schema
   where column_name='version' and table_schema in ('erp_billing','erp_credit','erp_inventory','erp_sales','infra_print','mdm_currency','mdm_org','mdm_partner','mdm_product')
   and not k.relispartition order by 1"
docker exec be-postgres psql -U postgres -d be_experiment -Atc "$q" | while read s; do docker exec be-postgres psql -U postgres -d be_experiment -AtF' ' -c "$s"; done
