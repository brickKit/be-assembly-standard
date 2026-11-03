# source me: the environment of infra/iam-casdoor's end-to-end test (iam/e2e_integration_test.go), without printing
# secrets; needs be-postgres, be-nats and Casdoor up and scripts/dev_setup.py run once
R=/home/zhijie/Desktop/github/be-assembly-standard
val() { grep "^$1=" "$R/.env" | cut -d= -f2- | tr -d "\"'"; }
export IAM_IT_PG_PASSWORD; IAM_IT_PG_PASSWORD=$(val POSTGRES_PASSWORD)
export IAM_IT_BUS_URL=nats://localhost:4222
export IAM_IT_CLIENT_SECRET; IAM_IT_CLIENT_SECRET=$(val IAM_CASDOOR_CLIENT_SECRET)
export IAM_IT_DEV_CLIENT_SECRET; IAM_IT_DEV_CLIENT_SECRET=$(val IAM_DEV_CLIENT_SECRET)
export IAM_IT_TEST_PASSWORD; IAM_IT_TEST_PASSWORD=$(val IAM_TEST_PASSWORD)
export IAM_IT_CASDOOR_ADMIN_PASSWORD; IAM_IT_CASDOOR_ADMIN_PASSWORD=$(val CASDOOR_ADMIN_PASSWORD)
export IAM_IT_KEY_FILE=$R/.secrets/infra-iam-casdoor/signing-key.pem
unset -f val
