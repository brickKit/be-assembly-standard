#!/bin/bash
# During round 7: when D-S-pg starts, reset the statement statistics of be_experiment; when the round ends, write the
# statements by total time. Reads nothing secret (psql over the container's local socket).
O=$1
q() { docker exec be-postgres psql -U postgres -d be_experiment -At -F $'\t' -c "$1"; }
q "CREATE EXTENSION IF NOT EXISTS pg_stat_statements" > /dev/null
until grep -q '^== run 1 D-S-pg ' $O/campaign.log 2>/dev/null; do grep -q '^END' $O/status.log 2>/dev/null && exit 0; sleep 2; done
q "SELECT pg_stat_statements_reset()" > /dev/null && echo "RESET $(date -Is)" >> $O/pgprof.log
until grep -q '^END' $O/status.log; do sleep 5; done
{
  echo "# statements of every database during D-S-pg (round 7): database, calls, total ms, mean ms, rows, query"
  q "SELECT d.datname, calls, round(total_exec_time::numeric, 1), round(mean_exec_time::numeric, 3), rows,
       regexp_replace(left(query, 220), '\s+', ' ', 'g')
     FROM pg_stat_statements s JOIN pg_database d ON d.oid = s.dbid ORDER BY total_exec_time DESC LIMIT 50"
  echo "# totals per database: database, calls, total ms"
  q "SELECT d.datname, sum(calls), round(sum(total_exec_time)::numeric, 1) FROM pg_stat_statements s
     JOIN pg_database d ON d.oid = s.dbid GROUP BY 1 ORDER BY 3 DESC"
} > $O/pgprof.tsv 2>&1
echo "PROFILED $(date -Is)" >> $O/pgprof.log
