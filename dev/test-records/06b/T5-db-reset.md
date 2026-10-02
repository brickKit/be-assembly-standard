# T5 演示库重置与脚本修正

## 目标
给 06b 的并行实施加项目锁；把演示库 brickkit_db 里组件 schema 重置为空并由 `make db-init` 重建；修正 dev-env / test-db-init / seed-net / db-init 的旧问题。

## 环境
本机 be-postgres 容器；brickKit v1.0.0；仅动本地 brickkit_db 与 brickkit_test_db，Casdoor 自己的库（schema `casdoor`、`keycloak`）、`public`、`besdk_*` 探针 schema 不动。

## 步骤
1. 项目锁：`bash infra/scripts/tests/test_project_lock.sh`——先红（脚本不存在），实现后四项全绿：两进程并发串行、嵌套不死锁且退出码透传、超时非零退出并点名持有者、`kill -9` 持有者后锁自动回收。已单独提交（969776b）。
2. db-init 口令接线：读 `db-init.sh` / `lib/db-pw.sh`——`<schema>_rw` 口令取 `.env` 的 `<REPO>_DB_PASSWORD`，外壳角色取 `SHELL_<NAME>_PASSWORD`，经 stdin 的 `\set` 行传给 psql，接线正确，未改动逻辑；整个脚本改为在项目锁内执行。
3. dev-env：空值 `VAR=` 原地填上（此前被当作缺失却另行追加一行）；`.env` 不存在时创建，不能创建/不可写给人话报错；新增 `test_dev_env.sh`（8 项全绿）；脚本在项目锁内执行。
4. test-db-init：迁移同时传 `PG_HOST/PG_PORT/PG_DATABASE/PG_USER(<schema>_rw)/PG_PASSWORD/PG_SCHEMA` 与旧 `DATABASE_*`；脚本在项目锁内执行。
5. seed-net `service_host`：解析失败时 `die`（点名 service_host）；`test_seed_net.sh` 增加坏文件用例，旧实现下红、新实现绿。
6. 删除前核对 schema 清单：awk 输出共 54 项（14 个已建组件 + 登记表里预留组件，如 mdm_customer … integration_edi），均为 `<域>_<名>` 形式，不含 public / casdoor / keycloak / besdk_*。
7. 重置命令（项目锁内）：`brickkit down`、逐个 `DROP SCHEMA IF EXISTS <s>_archive/<s> CASCADE`、`make dev-env && make db-init`，输出 `✓ 建库脚本已执行（幂等，可重跑）`。
8. 校验：`pg_namespace` 里 mdm_*/erp_* 的 schema 及 `_archive` 全部重建（owner 为 postgres，`<schema>_rw` 对 schema 与 archive 都有 CREATE 权限，t|t）；非系统 schema 里表数量为 0。
9. `make test-db-init` 输出 `✓ brickkit_test_db 就绪——TEST_PG_DSN 现在该指向这个库，不是 brickkit_db`，12 个旧组件迁移均 `✓ 迁移幂等`。

## 现象
schema 由 postgres 创建、`_rw` 角色获得 CREATE 与默认权限；表属主将在组件以 `<schema>_rw` 身份迁移时落到该角色（待各组件重建后验证）。

## 卡点与绕过
无。

## 结论
通过。项目锁可用，演示库已空、由 db-init 重建，测试库就绪。

## 反馈候选
无（be-ops 的口令接线无需修改）。
