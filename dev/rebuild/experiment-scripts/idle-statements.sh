#!/bin/bash
# Step 10 (step10-plan.md 5.8): how many statements an idle seeded cell sends to PostgreSQL, by role, from
# pg_stat_statements. The cell comes up with seed data (cell-chain.sh, KEEP_UP=1), settles 90 s, then the counters are
# reset and read after 60 s idle: by-role.txt (role|calls|exec ms), top.txt (the 12 most frequent statements),
# work.txt (the 15 most frequent ones without the session setup, begin and commit). The cell is brought down at the
# end. These are the commands that produced experiment-data/10-03/idle-statements/before (2026-10-28 18:10, D9-S on
# be-sdk-go 3.0.0-alpha.35) and after (18:36, alpha.36), in one script. Counts only: not affected by the power mode.
# Usage: idle-statements.sh <cell> <out>
set -u
R=/home/zhijie/Desktop/github/be-assembly-standard; CELL=$1; O=$(realpath -m "$2")
mkdir -p "$O"; cd "$R" || exit 1
P=$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2- | tr -d "\"'")
psqlc() { docker exec -e PGPASSWORD="$P" be-postgres psql -U postgres -d be_experiment -Atc "$1"; }
KEEP_UP=1 dev/rebuild/experiment-scripts/cell-chain.sh "$CELL" "$O/up" > "$O/up.log" 2>&1
tail -1 "$O/up/status.log"; sleep 90
psqlc "select pg_stat_statements_reset()" >/dev/null; sleep 60
psqlc "select r.rolname, sum(s.calls), round(sum(s.total_exec_time)::numeric,1) from pg_stat_statements s
       join pg_roles r on r.oid=s.userid group by 1 order by 2 desc" > "$O/by-role.txt"
psqlc "select s.calls, left(regexp_replace(s.query,'\s+',' ','g'),110) from pg_stat_statements s
       order by s.calls desc limit 12" > "$O/top.txt"
psqlc "select s.calls, left(regexp_replace(s.query,'\s+',' ','g'),150) from pg_stat_statements s
       where s.query not ilike '%set_config%' and s.query not in ('commit','begin isolation level read committed','rollback')
       order by s.calls desc limit 15" > "$O/work.txt"
awk -F'|' '{c+=$2} END {print "total calls in 60 s:", c, "per s", c/60}' "$O/by-role.txt"
(cd "dev/rebuild/experiment-cells/$CELL" && brickkit down >/dev/null 2>&1)
