# source me: the environment of every rebuilt component's integration tests (each component's AGENTS.md names what
# its own tests read); secrets come from the project's .env and are never printed
. "$(dirname "${BASH_SOURCE[0]}")/itenv.sh"
_PW=$(grep "^POSTGRES_PASSWORD=" "$(dirname "${BASH_SOURCE[0]}")/../../../.env" | cut -d= -f2- | tr -d "\"'")
export AUDIT_IT_PG_PASSWORD="$_PW" AUTHZ_IT_PG_PASSWORD="$_PW"
export BE_SDK_TEST_PG_ADMIN="postgres://postgres:$_PW@localhost:5432/brickkit_test_db?sslmode=disable"
unset _PW
. "$(dirname "${BASH_SOURCE[0]}")/iamenv.sh"
