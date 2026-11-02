#!/bin/bash
# What the SDK and acceptance tests leave in the shared test resources: per test database the schemas (bus-like
# leftovers by name pattern) and the shared bus tables' rows; the SDK roles; the test streams on NATS (the e6
# deployment's BE_ERP_*/BE_MDM_* streams share the server and are left out).
PW=$(grep '^POSTGRES_PASSWORD=' /home/zhijie/Desktop/github/be-assembly-standard/.env | cut -d= -f2- | tr -d "\"'")
q() { docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d "$1" -At -c "$2"; }
echo "# $(date -Is)"
for db in be_sdk_test be_acceptance; do
  echo "$db schemas: $(q $db "select count(*) from pg_namespace where nspname not like 'pg_%' and nspname <> 'information_schema'")"
  echo "$db bus-like schemas: $(q $db "select coalesce(string_agg(p || '=' || n, ' '), 'none') from (select regexp_replace(nspname, '[0-9a-f]{6,}$', '*') p, count(*) n from pg_namespace where nspname ~ '(bus|iop)' group by 1 order by 1) x")"
done
for s in be_bus_test py_bus_test; do
  for t in be_bus_subscription be_bus_message be_bus_delivery be_bus_stream; do
    echo "be_sdk_test $s.$t: $(q be_sdk_test "select count(*) from $s.$t" 2>/dev/null || echo -)"
  done
done
echo "roles sdk_*: $(q postgres "select count(*) from pg_roles where rolname like 'sdk_%'")"
echo "roles (all): $(q postgres "select count(*) from pg_roles")"
docker exec be-nats sh -c 'wget -qO- "http://127.0.0.1:8222/jsz?streams=true&consumers=true"' | python3 "$(dirname "$0")/nats.py"
