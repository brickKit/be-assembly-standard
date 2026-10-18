# source me: integration test env without printing secrets
E=/home/zhijie/Desktop/github/be-assembly-standard/.env
PW=$(grep '^POSTGRES_PASSWORD=' $E | cut -d= -f2- | tr -d "\"'")
AK=$(grep '^STORAGE_ACCESS_KEY=' $E | cut -d= -f2- | tr -d "\"'")
SK=$(grep '^STORAGE_SECRET_KEY=' $E | cut -d= -f2- | tr -d "\"'")
export BE_SDK_TEST_PG_ADMIN="postgres://postgres:$PW@localhost:5432/postgres?sslmode=disable"
export BE_SDK_TEST_NATS_URL=nats://localhost:4222
export BE_SDK_TEST_S3_URL=http://localhost:9000 BE_SDK_TEST_S3_ACCESS_KEY="$AK" BE_SDK_TEST_S3_SECRET_KEY="$SK"
unset PW AK SK
