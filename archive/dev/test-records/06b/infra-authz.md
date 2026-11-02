# 06b infra/authz：过程记录（T12）

## 概况

- 日期：2026-10-02（06:38 开工，07:10 交接，墙钟约 32 分钟；其中等项目锁约 2 分钟）
- brickKit：`brickkit version` → `BrickKit CLI v1.1.0` / `Supported Manifest version: brickkit/v1` / `Supported deploy targets: docker, podman, k8s`
- SDK：be-sdk-go v0.4.0（由 v0.2.1 升上来）；be-sdk-python / be-sdk-ts 本组件不用
- 基础资源：`make check` → `✓ 全部基础资源就绪`（postgres、nats、traefik、casdoor、rustfs 全部 healthy）
- 组件与版本：infra/authz v1.0.8 → 2.0.0；组件仓库提交 c502429 … 22a2701（9 个，未推送、未打 tag）；tag 待控制者 `make ship`：`2.0.0`、`v2.0.0`；契约包 **不需要新 tag**（仍 `gen/infra/authz/v1.0.5`）
- 交接给控制者：见"小结"

## infra/authz

### 目标

按 component-loop 重建到 2.0.0；`PERMISSION_CATALOG` 的值改为 `registry/permissions.tsv` 的文本（R27），先写 L2 测试跑红再实现；运行期核对 TSV 穿过 compose 后逐字节一致、表行数不少于 TSV 数据行数、没有"同步权限目录失败"；评估 `scripts/seed.sh` 第 ① 步能否改走 admin API；在设计文档写"为什么直接读注册表"。frontend-needs §2.9 本组件无新接口。

### 环境

brickKit v1.1.0；目标 docker；拓扑：独立组件；项目里先有 mdm/customer@2.0.0，本 Task 加入 infra/authz@2.0.0（infra/iam-casdoor 尚未加入）；并行的 W1 其它工作线同时在 integrate / verify（infra/workflow、infra/notification、mdm/product、integration/im-dingtalk 等）。本地模式开始与结束都是 off。

### 步骤

**C1 前置（06:38–06:39）**

- `env.sh` 的 stderr：`ℹ️  env.sh：BrickKit CLI v1.1.0（/home/zhijie/.local/bin/brickkit）；buf 在；TEST_PG_DSN 由 .env 的 POSTGRES_PASSWORD 在 eval 时拼出（URL 编码，不打印值），TEST_NATS_URL=nats://localhost:4222`
- `command -v protoc-gen-go protoc-gen-go-grpc` → `/home/zhijie/go/bin/protoc-gen-go`、`/home/zhijie/go/bin/protoc-gen-go-grpc`
- `git -C $C status -sb` → `## main...origin/main`，无文件行；HEAD 就是 `v1.0.8`；最新契约包 tag `gen/infra/authz/v1.0.5`
- 无依赖，"上游已发布"不适用。
- 1.6 表属主：`select tableowner, count(*) … where schemaname='infra_authz'` → 空（演示库里还没有本组件的表）。
- 1.5 读了旧 AGENTS / README / `docs/手册.md`、`archive/pre-v1/docs/dev/design/infra-authz.md`、`component.yaml` / `assembly.yaml` / `Makefile` / `Dockerfile`、全部后端代码与迁移、样板 mdm/customer 的 Makefile / Dockerfile / 八份文档、`dev/test-records/06b/mdm-customer.md`、`T8-pilot-review.md`、tools README。

**C2 骨架（06:39，<1 秒）**

```
✅ docs-skel：改动 8 个文件，跳过 0 个（跳过的是已经填写过的文件）
📦 Component repository (has component.yaml, no brickkit.yaml): the brickkit-component skill, plus the component's own AGENTS.md and CLAUDE.md
✅ AI assistant skills updated
   Wrote 1:
     .claude/skills/brickkit-component/SKILL.md
```

留底 `v1.0.8:` 八个文件到 `$S/old/`；`CLAUDE.md` 未改动（本来就是 `@AGENTS.md`）。

**C3 清单（06:39:45，约 1 秒）**

- `--write`：`assembly.yaml 删除的键：['version', 'asset', 'shell']`；`去掉 2 行归档引用注释`；`旧键 → 新键：{'pgSchema': 'PG_SCHEMA', 'iamJwksUrl': 'IAM_JWKS_URL', 'authzBundleUrl': 'AUTHZ_BUNDLE_URL', 'otelBaseUrl': 'OTEL_BASE_URL', 'permissionCatalog': 'PERMISSION_CATALOG', 'accessTokenTtlSeconds': 'ACCESS_TOKEN_TTL_SECONDS', 'defaultOrgId': 'DEFAULT_ORG_ID', 'bootstrapAdminSub': 'BOOTSTRAP_ADMIN_SUB'}`；`module.go:27/29/30/31/32` 五处读法改成新键；`required: [PG_HOST, PG_DATABASE, PG_USER, PG_PASSWORD, NATS_URL, AUTHZ_BUNDLE_URL, IAM_JWKS_URL, PERMISSION_CATALOG]`（`PERMISSION_CATALOG` 无默认值）。`ℹ️` 列出注释与报错文案里的旧键名 10 处，C4 注释改写时全部处理。
- `--check` 全部"无"，`✅ --check 全部为"无"`，`exit=0`。
- `brickkit lint infra/authz`：第一行 `🔎 Only infra/authz is checked (brickkit lint --all checks the whole project)`，`✅ components/infra/authz/component.yaml`，`📋 Checked 2 files: 0 with errors, 68 warnings`（全是 `DOC_*`）；`MANIFEST_INVALID` 0 次。
- 无新权限键，没跑 `make permissions`。overrides 没有改动。

**C4 代码（06:39:54–06:52）**

- `go-v2.sh infra/authz --sdk v0.4.0`：形态 A；`go: upgraded go 1.25.0 => 1.25.11`、`be-sdk-go v0.2.1 => v0.4.0`、`golang-migrate v4.19.1 => v4.20.1`；迁移入口一行化、删 `Migrations: migrations.FS` 与 migrations import；14 条判据全部 PASS；`📌 第 8.3 步：不需要打契约包 tag（本地 gen/infra/authz 与 gen/infra/authz/v1.0.5 一致）`；`✅ go-v2.sh：判据全部 PASS`、`exit=0`。`go list -m all | grep brickKit/infra-authz` 恰好两行：`github.com/brickKit/infra-authz/v2`、`github.com/brickKit/infra-authz/gen/infra/authz v1.0.5 => ./gen/infra/authz`。
- SDK 跨了 v0.2.1 → v0.4.0 三个破坏性版本：读了 be-sdk-go 各 tag 的注释（项目自己的 SDK，不是 brickKit 源码）核对影响：迁移状态表名 `schema_migrations_infra_authz` 不变；本组件不用 `UserClient` / `SystemClient`；`besdk.Authenticated`、`ScopeOf` 照旧，编译直接通过。
- 4.16 `make test-db-init ID=infra/authz`：`{"msg":"迁移结束","direction":"up","schema":"infra_authz","outcome":"ok","version":3,"dirty":false}` ×2、`✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。基线 `go test ./... -race`：`repo`、`service` 两个包 ok，24 个 PASS，0 SKIP。提交 c502429（机械步骤）。
- **R27 红绿**（`ParsePermissionCatalog` 改 TSV）：
  - 两个结构体先只加 `Deprecated` 字段，测试能编译、按行为红。删掉三条断言旧逗号竖线格式的测试（单条、多条、字段数不对）——它们描述的行为在 2.0.0 被取消（R27），不是放宽；空串、key 为空、类型转换布局三条改成新格式保留。提交信息写明。
  - 红（提交 1a60a35）：catalog_test.go 8 条 FAIL，原文 `permissionCatalog 第 1 条格式不对（要 key|title|type|owner_component）："key\ttitle\ttype\towner_component\tdeprecated\ncrm.opportunity.edit\t编辑商机…"`、`错误信息要给出行号（第 3 行），得到：…`、`PERMISSION_CATALOG 的值是注册表 TSV，逗号竖线串应该报错…`；repo_test.go:432 `permissions.deprecated 应与注册表一致，得到 ""`。
  - 绿（提交 552d7b4）：按行切、跳过空行 / `#` / 表头、制表符分列、至少 4 列、第 5 列可空、去 `\r`、行号报错；`SyncPermissionCatalog` 把 `deprecated` 一起 upsert（决定：登记表是唯一真相源，表做镜像；旧注释"deprecated 是人工决定、本函数不碰"在 1.x 成立是因为逗号格式根本不带这一列，现在登记表带了，镜像它才不会让表与登记表分叉；没有任何代码读这一列，不影响判定）。用项目当前 `registry/permissions.tsv` 实际解析一次：`entries=43`，无报错。
- **4.11 发现一个真实 bug**（BatchGetRoles 把任何错误都当"查不到"）：红（1c93b7f）`grpc_test.go:34: 数据库不可用时应返回错误，实际返回 0 个角色、没有错误`；绿（e1dee5c）只有 `repo.ErrNotFound` 才省略。同时加了一条守住现有行为的测试（查不到的 code 省略不报错），修复前后都绿。`MyPermissions` 同样吞掉逐角色读取的任何错误，但故障注入要改代码结构，且结果只影响前端显示哪些按钮——不修，写进 design.md 未决问题。
- 4.10：没有超过 600 行的文件、超过 150 行的函数。4.12 合并安全：`make module-check` → `✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`；`os.Getenv` / `log.Fatal` / `os.Exit` 只在注释里出现。
- 注释改写：非测试代码 + 契约说明文字一个提交（1ae5904；openapi `info.version` 2.0.0，`/api/me/permissions` 的说明改成与代码一致的 `besdk.Authenticated`——旧说明还写着"暂标 besdk.Public"）；测试注释单独一个提交（42510d1，只有两行注释）。`.proto` 不动（R41）。
- Makefile / Dockerfile / 种子脚本（9ef77ea）：Makefile 照抄 mdm/customer 模板，只改 `ID`/`REPO`、`migrate-idempotent` 注释里的角色与 schema、`dag-check` 的理由文字、`seed`/`seed-clean` 说明；`grep -i 'customer\|客户' Makefile` 为空。Dockerfile 照模板（删 `COPY migrations`，EXPOSE 8223 9223）。seed 脚本只改注释。
- `component-check.sh`（C4 末）：9 项 PASS，第 10 项占位符 FAIL（文档还是骨架，预期）。

**C5 文档（06:52–06:53）**

八份文件写满。`component-check.sh` → `✅ component-check infra/authz：10 项全部 PASS`；`make docs-boundary` 静默通过；`make docs-check ID=infra/authz` → `✅ components/infra/authz/component.yaml`、`✅ components/infra/authz/ (docs)`、`📋 Checked 2 files: 0 with errors, 0 warnings`、`exit=0`（一次过）。`$S/assembly-removed-comments.txt` 的两条（`/authz/bundle` 不进 edge_routes；`data_scopes: none` 的理由）写进 design.md 的 Contract surface / Data scopes。提交 22a2701。

**C6 版本与门禁（06:53–06:55）**

- `make check-version test contract-check import-scan module-check dag-check` → `exit=0`：`✓ version=2.0.0…`、三个测试包 ok、`buf breaking --against '.git#tag=v1.0.8'`（是发布 tag，不是 main）、`✓ 无组件间 import`、`✓ 入口签名对…`、`✓ 无依赖，无环`。
- `migrate-manifest.py --check` exit 0；`make test-db-init ID=infra/authz` 绿（`✓ 迁移幂等`）。
- `project-lock.sh -- make gates`（2 秒，exit 0）：import / SystemClient / 裸路由 / 事件契约 / data-scope-test / dependency-version 全部 `0 条违规`；`service-hostname-scan：0 条错误（2 条警告）`（`config/vars.yaml:22/23` 的 authz / iam 当时不在 brickkit.yaml，预期）；`config-key-scan：0 条违规（另有 5 个 1.x 组件的 31 条 naming 违规只警告…）`，本组件不在警告里；`openapi-additive-scan：0 条违规（0 条跳过提示）`；`up --dry-run` 正常。
- 发布前门禁自查（锁内）：`✓ config-key-scan（只看 components/infra/authz）：0 条违规` cks=0；`✓ openapi-additive-scan（只看 components/infra/authz）：0 条违规（0 条跳过提示）` oas=0。

**C7 接入与真机（06:54–07:07）**

- 第一次 `make integrate ID=infra/authz`（1 秒）：db-init `✓ .env 里的数据库密码已齐全`、`✓ 建库脚本已执行`；`brickkit add` 7 行 `🔗 … references the variable of the same name in config/vars.yaml (--yes)`、`✅ infra/authz@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml`；config-fill `写了 3 个键：PG_PASSWORD, PG_USER, PG_SCHEMA`，然后 `✗ … 还有 1 个 required 键没有值 … PERMISSION_CATALOG`，`exit=2`（预期，按"配置值"一栏给值）。
- `config-fill.py infra/authz --set 'PERMISSION_CATALOG=file://registry/permissions.tsv' --set 'BOOTSTRAP_ADMIN_SUB=${INFRA_AUTHZ_BOOTSTRAP_ADMIN_SUB:-}'` → `写了 2 个键`，exit 0。`ACCESS_TOKEN_TTL_SECONDS` / `DEFAULT_ORG_ID` 保持注释。`.env` 里没有 `INFRA_AUTHZ_BOOTSTRAP_ADMIN_SUB`（`:-` 取空，合法）。
- 第二次 `make integrate`（2 秒，exit 0）：`跳过 add / upgrade`、`config：无需改动`、teardown 同步、`brickkit lint --strict infra/authz` → `✅ infra/authz: configuration (config/ ↔ configSchema)`、`0 with errors, 0 warnings`；`up --dry-run` → `✅ infra/authz@2.0.0   starting (top-level)`、`infra-authz-2-0-0   no dependencies`；`✓ integrate infra/authz@2.0.0 完成`。
- 生成文件：`PERMISSION_CATALOG` 与 `PG_PASSWORD` 进 0600 的 `.brickkit/generated/env/infra-authz-2-0-0.env`（值为双引号串、`\n` 转义），其余在 `environment:`；`PG_USER=infra_authz_rw`、`PG_SCHEMA=infra_authz`、两个 URL 是成员服务名、`BOOTSTRAP_ADMIN_SUB=${INFRA_AUTHZ_BOOTSTRAP_ADMIN_SUB:-}`。
- `make verify … KEEP=1`（06:55:49，62 秒）全部 PASS / 写明原因的 SKIP；但随后锁内做运行期核对时容器已经没了——见"卡点与绕过" 1。改成一次锁内"生成闭包副本 → up → 核对 → down"（`$S/runtime-check.sh`）：

```
容器内 PERMISSION_CATALOG 行数（printf %s | wc -l）: 44
registry/permissions.tsv 行数（wc -l）: 44
容器内 sha256（printf %s）: 2724a09acb14e8bef8ccfc264916a063947107d653901e18f29a76a42f2ee703
（sha256sum registry/permissions.tsv）                2724a09acb14e8bef8ccfc264916a063947107d653901e18f29a76a42f2ee703
容器内字节数: 2741；文件字节数: 2741
permissions 表行数: 43
TSV 数据行数: 43
TSV 有而表里没有的键数: 0
表里有而 TSV 没有的键:
erp.finance.close|关账/反关账/锁定期间|action|erp/finance|
infra.authz.admin|权限与角色管理|page|infra/authz|
mdm.product.set_status|启用/停用产品|action|mdm/product|
日志里 ERROR / 同步权限目录失败（空即无）:
Etag: "2afd768a…"   If-None-Match 同一 ETag → 304
GET /api/me/permissions 不带 token → 401
RestartCount/Status: 0 running
```

  判据：行数一致（44 = 44，含末尾换行）、逐字节一致（sha256 相同、字节数相同）；表行数 43 ≥ TSV 数据行数 43，键集合完全相等；日志无"同步权限目录失败"、无 ERROR。容器日志里自己的 bundle 轮询 `GET /authz/bundle` 200 一次，之后每 15 秒 304（自吃自己的 bundle 成立）。
- **Review Focus 2（有默认值的自有键配非默认值）**，锁内临时改 `config/infra-authz.yaml`、用完逐字节还原（`$S/defaults-check.sh`）：`DEFAULT_ORG_ID: "77"`、`BOOTSTRAP_ADMIN_SUB: verify-bootstrap-check`、`ACCESS_TOKEN_TTL_SECONDS: 5`：

```
env: DEFAULT_ORG_ID=77 BOOTSTRAP_ADMIN_SUB=verify-bootstrap-check ACCESS_TOKEN_TTL_SECONDS=5
BOOTSTRAP_ADMIN_SUB → user_roles: verify-bootstrap-check authz_admin
ResolveClaims(verify-bootstrap-check): { "roles": [ "authz_admin" ], "orgId": "77" }
bundle（TTL=5，窗口 10 秒，grant 发生在启动时、已超出窗口）: {"roles":{"authz_admin":["infra.authz.admin"]},"stale_since":{}}
config 还原: 一致
```

  对照（`$S/ttl-contrast.sh`，默认 TTL 600）：同一条 `granted 2026-10-02 05:03:49` 出现在 `"stale_since":{"verify-bootstrap-check":1790917429}`——TTL 从行为上生效。核对完删掉了演示库里这条测试用的 `user_roles` 行（`DELETE 1`；`role_changes` 行写入即终态，留着）。三个键都按新键读到了非默认值。
- 正式 `make verify ID=infra/authz ROUTE=/api/admin/roles FOCUS=1`（07:05:49，95 秒，exit 0；构建因镜像已存在跳过——镜像 06:56 由 HEAD 22a2701 构建，之后组件没有改动）：

```
verify infra/authz@2.0.0 汇总（输出目录 $BE_SCRATCH/verify/infra-authz-20261002-070706）
| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build infra/authz | PASS |  | build.log |
| 镜像 infra-authz:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（1 个） | PASS |  | migration-*.log |
| infra-authz-2-0-0 running (healthy)（容器服务 infra-authz-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| GET /api/admin/roles 不带 token → 401/503 | PASS | 实际 401 | http.log |
| GET /api/admin/roles 带 token → 200 | SKIP | infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token |  |
| make -C <源目录> seed | SKIP | 没设 SEED=1 |  |
| make test-cross ID=infra/authz | PASS |  | test-cross.log |
| focus：宿主机 http://localhost:8223/healthz → 200 | PASS |  | focus.log |
| brickkit up --all --dry-run（清除 focus） | PASS |  | focus-all-dry-run.log |
| brickkit local off | PASS |  | local-off.log |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |
✓ 全部 PASS 或写明原因的 SKIP
```

  seed 没设 `SEED=1` 的原因：本组件的 `make seed` 第 ② 步要用 `get_app_jwt dev.superuser` 经 infra/iam-casdoor 的 `/api/iam/token` 换应用 JWT，iam 还不在项目里，跑了必然在第 ② 步 FAIL（第 ① 步还会先往演示库写一个全权限角色）。留给 iam 加入之后（T13 / T25）。迁移日志 `{"msg":"迁移结束","direction":"up","schema":"infra_authz","outcome":"ok","version":3,"dirty":false}`。focus：`host.docker.internal 换成 host-gateway IP 172.17.0.1：PG_HOST, NATS_URL, S3_URL`、`infra-authz-2-0-0  listening on port 8223`；JWKS 与自己 bundle 的拉取失败（宿主机解析不了容器服务名，附录 B 预期）。收尾后 `brickkit local status` → `Local mode: off` / `deploy.local.yaml: none`；本项目容器 0 个。
- V-13：这次 `brickkit add` 没有重排注释，`git diff brickkit.yaml deploy.yaml deploy.teardown.yaml` 只有新增的两行组件条目。
- `make teardown-sync CHECK=1` → `✓ deploy.teardown.yaml 与 deploy.yaml 一致`。

**C8 交接（07:08）**：发布说明 `$S/notes-2.0.0.md`（`$S=$BE_SCRATCH/06b/infra-authz`）。"升级前必须做"一节在生成骨架上**有意**加了第一条"`PERMISSION_CATALOG` 键的含义变了"（brief 要求放第一条），并把生成的那行"`PERMISSION_CATALOG` 改为必填（1.x 默认为空）"并进这一条——之后若再跑 `--write`，⚠️ 漂移提示只会指向这两处差异。`git -C $C log --oneline -3`：

```
22a2701 docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
9ef77ea chore: Makefile / Dockerfile / 种子脚本按 v1 改
42510d1 test: 测试注释去掉归档出处（断言未动）
```

工作区干净，`## main...origin/main [ahead 9]`。最后核对：`component-check.sh` 十项全部 PASS、`exit=0`；`history_allow` 无条目。

### 现象

- 符合预期的：三个迁移工具一次通过；SDK 跨三个破坏性版本直接编译通过；多行、带制表符与中文的 TSV 经 0600 env 文件注入后逐字节一致；表属主随迁移以 `infra_authz_rw` 建表天然正确；自吃自己的 bundle 在独立部署下工作（启动后第一次轮询 200，之后 304）；不带 token 401；三个有默认值的自有键都按新键读到非默认值。
- 不符合预期的：`KEEP=1` 留下的容器在并行工作线下被别的工作线的 `verify` 收尾带走（见卡点 1）；事件契约声明了两个审计事件，代码里从来没有写过 Outbox（见卡点 2）。

### 卡点与绕过

1. **`KEEP=1` 在并行工作线下不可靠。** `make verify … KEEP=1` 06:56:51 结束、释放锁；我 06:57 拿锁做运行期核对时 `docker ps` 里已经没有本组件的容器，项目根的 `deploy.verify.yaml` 也没了。原因：`verify-component.sh` 总是把闭包副本写到**项目根同一个文件** `deploy.verify.yaml`，另一条工作线的 `verify` 在我释放锁后拿锁、覆盖了它，收尾时 `brickkit down -f deploy.verify.yaml`（必要时再 `brickkit down`）把项目里的容器——包括我留着的——一起收掉了。component-loop 7.2 / 4.5 写的"在 `KEEP=1` 留下的容器上、锁内跑"在 W1 这种并行波次里实际做不到。绕过：把"生成闭包副本 → up → 核对 → down → 删副本"写进一个脚本、一次锁内跑完（`$S/runtime-check.sh`、`defaults-check.sh`、`ttl-contrast.sh`）。这是项目工具的问题，不是 brickKit 的；反馈候选见下。
2. **审计事件只在契约里。** `contracts/events/authz.events.json` 声明了 `infra.authz.role.changed.v1`、`infra.authz.user_role.changed.v1`，Outbox 表与推送循环都在，但没有任何代码调用 `besdk.PublishOutbox`——从 1.x 起就没有发过。实现它要决定 `version` 语义（角色与分配都没有版本列），属于"改变已有事件语义"，按 component-loop 4.13 交控制者裁定，本 Task 不自行扩展。文档（BRICKKIT、design.md）照实写"已声明、本版本未发出、没有消费者"，未决问题里列出。
3. `registry/permissions.tsv` 的工作区改动不是本组件的：`git diff` 里唯一的 `+` 行是 `mdm.product.set_status	启用/停用产品	action	mdm/product	`（mdm/product 工作线，T9）。没有手动处理，交控制者（component-loop 3.5）。它已经被本组件的运行期核对同步进了演示库的 `infra_authz.permissions`（键只增不删，无害）。
4. 协调者转来 mdm/product 的发现（旧测试用固定幂等键，第二次起写路径不再执行、测试空转）：本组件核对过，不存在。authz 没有幂等键（没有 `command_idempotency` 表，写操作靠 upsert / delete 天然幂等）；测试写入的每个自然键（`sub`、角色 code、权限键、部门名）都来自 `uniqueID`（`<前缀>_<UnixNano>_<计数>`），每次运行都真的走写路径。固定字面量只有 `u:someone`（在任何 SQL 之前就被拒绝）、迁移种下的 `authz_admin`（只读）与 gRPC 测试里的 `missing_<UnixNano>`。不需要测试提交。
5. 没有翻 brickKit 源码：全部由 `brickkit --help`、skill 与项目文档答到。读了项目自己的 be-sdk-go（`tools/be-sdk-go` 的 tag 注释、`tx.go`、`outbox.go`、`bundle.go`、`authz.go`）来核对 SDK 升级影响与 fail-closed 状态码——这是本项目的 SDK，不算 V-04 知识缺口。

### V 项

- V-13（`brickkit add` 重排注释）：本次 `add infra/authz@2.0.0` 没有重排，diff 只有新增条目（brickkit.yaml +2 行、deploy.yaml +1、deploy.teardown.yaml +1、AGENTS.md 组件表 +1）。结论：本次未复现（前面的试点复现过，可能只在注释还在原始位置时发生一次）。同步到 to-verify：否（由控制者合并）。
- V-04（知识缺口）：无。

### 结论

完成。遗留：带 token 的 `200` 与 `make seed` 待 infra/iam-casdoor 加入项目（T13 / T25）；审计事件是否发出、`version` 用什么，待控制者裁定。

### 反馈候选

- `verify-component.sh` 的 `KEEP=1` 与并行工作线冲突（卡点 1）→ 直接进项目工具改进（不是 brickKit 的事）：闭包副本改成按组件命名（`deploy.verify.<repo>.yaml`）且收尾只 `down -f` 自己的副本，或者 `KEEP=1` 时在锁里多给一个"在保留的容器上跑这条命令"的钩子（`VERIFY_HOOK=<脚本>`），让运行期核对与 verify 共用一次锁。
- `make verify SEED=1` 对依赖 iam 换 token 的种子脚本（authz、以及凡是 seed 走 REST 的组件）在 iam 加入项目前必然 FAIL → 项目工具：verify 的 SEED 一步可以先判断 infra/iam-casdoor 是否在项目里，不在就 SKIP 并写明原因，与"带 token 一项"同一个判据。

## 小结

- 完成：infra/authz 2.0.0，组件仓库 9 个提交（c502429 … 22a2701），未推送、未打 tag；`make verify` 汇总全部 PASS 或写明原因的 SKIP；运行期判据全部满足。
- 需要控制者裁定的：审计事件 `infra.authz.role.changed.v1` / `user_role.changed.v1` 是否实现、`version` 语义；`registry/permissions.tsv` 里 mdm/product 的新增行（别的工作线）。
- 交给控制者的：发布说明 `$S/notes-2.0.0.md`（"升级前必须做"有意改动两处，见 C8）；契约包不需要新 tag（仍 `gen/infra/authz/v1.0.5`）；父仓库待提交路径：`components/infra/authz`（指针，ship 后）、`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/infra-authz.yaml`、`AGENTS.md`（组件表一行）、`dev/test-records/06b/infra-authz.md`；`manifest-overrides.yaml` 本组件那一段没有改动。`config/vars.yaml` 的 `AUTHZ_BUNDLE_URL` 已经是 `http://infra-authz-2-0-0:8223/authz/bundle`，与本次版本一致，没有改动。
- 遗留到后续 Task：带 token `200`、`make seed`（iam 加入后）；外壳 go-infra 里再核一次 `PERMISSION_CATALOG` 穿过 `BRICKKIT_SERVED_MEMBERS_CONFIG` 的逐字节一致（T22）。
- 检查点小结：infra/authz 2.0.0，tag `2.0.0` / `v2.0.0` 待 `make ship`，组件 HEAD 22a2701，无契约包 tag，遗留见上。

## 2.0.1（R60 跟进：种子与文档）

### 目标

R60 之后，空 `dept_path` 的意思是"没有部门、只剩本人"，不再是"看全部"。本版要做的：把 `dev.superuser` 分到根部门，让它拿到真实的 `/<根id>/`；SDK 升到 be-sdk-go v0.5.0；在组件文档与项目约定里写明 `dept_path` 的语义；`AUTHZ_BUNDLE_URL` 改成 `infra-authz-2-0-1`；最后真机验证一遍。

### 环境

- 日期：2026-10-02。brickKit CLI v1.1.0，目标 docker。
- 开工时组件仓库停在 22a2701（`2.0.0` / `v2.0.0`），工作区干净；开工前的 `make test` 全绿（`$S/201-test-baseline.log`）。
- 项目里同时有 infra/workflow@2.0.1（另一条工作线）和 infra/iam-casdoor@2.0.0（未发布）。本地模式开始与结束都是 off。

### 步骤

1. 跑 `go get github.com/brickKit/be-sdk-go@v0.5.0 && go mod tidy`，输出 `go: upgraded github.com/brickKit/be-sdk-go v0.4.0 => v0.5.0`。之后 `make test` 全绿，`--- SKIP` 计数为 0。
2. 核对 authz 里 dept_path 的取值：
   - `grep ScopeOf|DeptPath`：authz 只在 `http.go:82` 用到 `ScopeOf(...).Owner`，没有任何代码读 `.Prefix`、`.All` 或空 dept_path。
   - `CreateDepartment` 的 `parentPath` 初值是 `"/"`，路径算法是 `parentPath + id + "/"`，所以顶层部门是 `/<id>/`，本组件从不签发 `"/"`。
   - 没有部门时 `DeptPathFor` 返回 `""`（`TestDeptPathFor_未分配返回空串不报错` 仍然成立）。
   - 新增 `TestCreateDepartment_顶层部门dept_path是斜杠id斜杠不是根标记`，锁住现有行为，所以改动前后都是绿的，不是一次红绿循环。
3. 改种子 `scripts/seed.sh`：
   - 加上 `assign_dept "$SEED_SUB" "$ROOT_DEPT_ID"`。
   - `assign_dept` 改为检查 HTTP 码，不是 200 就 `die`。
   - `seed-clean.sh` 已经会按"「本地测试」总公司"删除 `user_departments`，不用改。
4. 改文档：
   - BRICKKIT、docs/design、AGENTS（各中英一份）。
   - 组件版本号改成 2.0.1，README 的 add 命令和 OpenAPI `info.version` 一起改。
   - 共 5 个提交，见"结论"。
5. 组件门禁：`make test check-version dag-check contract-check import-scan module-check docs-check` 退出码 0。各项输出：
   - `✓ version=2.0.1`
   - `✓ 无依赖，无环`
   - `buf breaking --against '.git#tag=v2.0.0'` 通过
   - `✓ 无组件间 import`
   - `✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`
   - `📋 Checked 3 files: 0 with errors, 0 warnings`
   - `component-check.sh`：`✅ component-check infra/authz：10 项全部 PASS`
6. 改父仓库文件（未提交）：
   - `config/vars.yaml`：`AUTHZ_BUNDLE_URL: http://infra-authz-2-0-1:8223/authz/bundle`
   - `docs/{en,zh}/01-conventions/02-backend.md` 的 Data scopes 一节加 3 条
   - `docs/{en,zh}/03-seed-data.md`：每个种子用户在哪个部门
   - 根 `AGENTS.md` / `AGENTS.zh.md` 易错点表加一行
   - `make docs-mirror docs-boundary` 两个都退出 0
7. `make integrate ID=infra/authz VERSION=2.0.1` 退出 0。upgrade 的输出原文：
   ```
      ⬆️  infra/authz: 2.0.0 → 2.0.1
      ✅ infra/authz@2.0.0 (requiredBy: infra/iam-casdoor)
   ```
   `up --dry-run` 里 `infra-authz-2-0-0` 和 `infra-authz-2-0-1` 同时出现（见卡点 1）。
8. `make gates` 退出 0，其中 `✓ service-hostname-scan：0 条错误（0 条警告）`，其余 gate 都是 0 条违规。
9. 真机运行：用 `project-lock.sh` 跑 `$S/201-verify-and-claims.sh`，在一次锁内依次做完下面几件事：
   - `make verify ID=infra/authz ROUTE=/api/admin/roles SEED=1 FORCE_BUILD=1 KEEP=1`
   - 换四个种子用户的应用 JWT，只解码 `dept_path` 这一个 claim
   - `brickkit down -f deploy.verify.yaml`，删掉 `deploy.verify.yaml`

   verify 汇总（`$S/201-verify/summary.md`）：
   ```
   | brickkit build infra/authz | FAIL | 构建失败 | build.log |
   | 镜像 infra-authz:2.0.1：sh + wget、/app/component.yaml | PASS |  | image-check.log |
   | brickkit up -f deploy.verify.yaml | PASS |  | up.log |
   | 迁移容器 Exited (0)（3 个） | PASS |  | migration-*.log |
   | infra-authz-2-0-1 running (healthy)（容器服务 infra-authz-2-0-1） | PASS |  | status.log |
   | GET /healthz → 200 | PASS |  | http.log |
   | GET /api/admin/roles 不带 token → 401/503 | PASS | 实际 401 | http.log |
   | GET /api/admin/roles 带 token → 200 | PASS |  | http.log |
   | make -C components/infra/authz seed | PASS |  | seed.log |
   | make test-cross ID=infra/authz | PASS |  | test-cross.log |
   | brickkit up --focus infra/authz | SKIP | 没设 FOCUS=1 |  |
   | brickkit down | SKIP | KEEP=1：容器保留，用完 brickkit down -f deploy.verify.yaml |  |
   ```
   build.log 里 FAIL 的原文：`✅ Built infra/authz@2.0.1 → infra-authz:2.0.1`，然后 `🔨 Building infra/authz@2.0.0 → infra-authz:2.0.0` / `❌ Error: component not found … error_code":"COMPONENT_NOT_FOUND"`。

   种子之后的 claims（token 本身没有打印）：
   ```
     dev.superuser          dept_path='/1/'
     dev.sales.east         dept_path='/1/2/'
     dev.warehouse.south    dept_path='/1/3/'
     dev.finance.viewer     dept_path=''
   authz 部门表：1 「本地测试」总公司 /1/；2 「本地测试」华东分部 /1/2/；3 「本地测试」华南分部 /1/3/
   ```
   收尾：`down exit=0`，`剩下的项目容器：<无>`，`Local mode: off`。

### 现象

- 符合预期的：
  - `dev.superuser` 的 token 带上了根部门的真实路径 `/1/`，它是 `/1/2/`、`/1/3/` 的前缀，所以它在 org 维看得到每个部门。
  - `dev.finance.viewer` 是唯一没有部门的种子用户，`dept_path=''`。
  - 带 token 访问受保护路由得到 200。
  - 种子可以重复跑：部门和角色都按"已存在"跳过，只补上分配。
- 不符合预期的：项目里出现了 authz 2.0.0 和 2.0.1 两个版本并存（见卡点 1）。

### 卡点与绕过

1. **authz 两个版本并存。** `infra/iam-casdoor/component.yaml` 里依赖的还是 `infra/authz@2.0.0`（iam 未发布，pin 归 iam 工作线改），所以 `brickkit upgrade` 照规则把 2.0.0 保留为 `requiredBy: [infra/iam-casdoor]`，带来四处连锁变化：
   - `brickkit.yaml`、`deploy.yaml`（`infra/authz@2.0.0`）、`config/infra-authz@2.0.0.yaml`、AGENTS 组件表都多出一项。
   - verify 闭包同时起了两个 authz 实例，共用同一个 `infra_authz` schema。iam 的 `ResolveClaims` 打到 2.0.0 实例，但因为库是同一个，claims 的结果一样。
   - 这次 verify 唯一的 FAIL 就是它造成的：`FORCE_BUILD` 时 `brickkit build infra/authz` 要把项目里这个 ID 的两个版本都构建一遍，而本地源只有 2.0.1，于是 2.0.0 报 `COMPONENT_NOT_FOUND`。2.0.1 的镜像构建成功，2.0.0 用的是已有镜像。
   - 绕过：本工作线没改 iam（不在 brief 范围内）。iam 的 pin 改成 `@2.0.1` 之后再跑一次 `brickkit upgrade infra/iam-casdoor` 或 `brickkit sync`，2.0.0 那项和 `config/infra-authz@2.0.0.yaml` 就会消失，build 也会恢复成单个版本。
2. 演示库里 `dev.superuser` 早先建的 `seed-order-*` 和 `seed-opp-1..5`，`dept_path` 是 `''`。等消费方用上 SDK v0.5.0，这些行只有 owner 自己看得到。sales 和 opportunity 要先 `seed-clean` 再重灌（已经写进 `03-seed-data.md`）。这一步本工作线没有做。
3. 没有翻 brickKit 源码。

### 结论

已完成。组件仓库新增 5 个提交，没有推送、没有打 tag：

- 84f2244 版本号 2.0.1
- 21510e8 be-sdk-go v0.5.0
- ff88599 test：顶层部门路径
- c29d830 fix(seed)：dev.superuser 分到根部门
- 7b3f823 docs

契约包仍是 `gen/infra/authz/v1.0.5`。发布说明在 `$S/notes-2.0.1.md`。

没有部门的种子用户只有 `dev.finance.viewer`。这是对的：它只有 `erp.finance.view`，finance 按 `legal_entity` 维限定，不读 `dept_path`；在按部门限定的列表里它只看得到自己的行，正好符合"只读财务"的意图。`BOOTSTRAP_ADMIN_SUB`（本地留空）配置的首个管理员同样没有部门。它只需要用 admin API 分配部门和角色，不需要看部门数据；部署方要让他看全公司，就给他分到根部门（已写进 BRICKKIT 的"部署前准备"）。

### 反馈候选

- 项目工具：`verify-component.sh` 在 `FORCE_BUILD=1` 时跑的 `brickkit build <id>` 会构建项目里这个 ID 的所有版本。并存版本只要缺本地源，就整行 FAIL，哪怕目标版本已经构建成功。可以改成 `brickkit build <id>@<目标版本>`，或者把两行分开报告。这不是 brickKit 的问题，brickKit 的行为符合"项目里有哪些版本就建哪些"。
