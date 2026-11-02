#!/bin/bash
# Loop for TestPurgeDropsMessagesPastTheRetention: an expired message of another stream already in the shared test bus
# (left by an earlier run). Red when the test counts it.
cd /home/zhijie/Desktop/github/be-assembly-standard/tools/be-sdk-go && source ../../dev/rebuild/experiment-scripts/itenv.sh
PW=$(grep '^POSTGRES_PASSWORD=' /home/zhijie/Desktop/github/be-assembly-standard/.env | cut -d= -f2- | tr -d "\"'")
docker exec -e PGPASSWORD="$PW" be-postgres psql -U postgres -d be_sdk_test -qAtc "INSERT INTO be_bus_test.be_bus_message (subject, headers, data, published_at) VALUES ('be.leftover.0.x.v1', '{}', '\x7b7d', now() - interval '9 days')"
go test -count=1 -tags integration -run 'TestPurgeDropsMessagesPastTheRetention$' ./events/pgqueue/ 2>&1 | grep -E -- '--- FAIL|^ok|^FAIL|expected|actual' | head -5
