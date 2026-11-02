# 06b erp/inventory：过程记录（T10）

## 概况

- 日期：2026-10-02（06:38 开工，07:20 交接，墙钟约 42 分钟）
- brickKit：`brickkit version` → `BrickKit CLI v1.1.0`（`/home/zhijie/.local/bin/brickkit`，env.sh 断言）
- SDK：be-sdk-go v0.4.0（`git -C tools/be-sdk-go describe --tags --abbrev=0` → `v0.4.0`；组件 `go list -m all` → `github.com/brickKit/be-sdk-go v0.4.0`）
- 基础资源：`make check` → `✓ 全部基础资源就绪`（postgres、nats、traefik、casdoor、rustfs 全部 healthy，network be-net ✓）
- 组件与版本：erp/inventory v1.0.18 → 2.0.0；组件仓库 11 个提交 c4fa253 … 67dedbe（未推送、未打 tag）；tag 待控制者 `make ship`：`2.0.0`、`v2.0.0`；契约包 **不需要新 tag**（仍 `gen/erp/inventory/v1.0.14`）
- 交接给控制者：见文末"小结"（提交、发布说明 `$S/notes-2.0.0.md`、verify 汇总表与输出目录、父仓库待提交路径、一次父仓库误提交已撤销的事故）

## erp/inventory

### 目标

按 component-loop 重建到 2.0.0；补 frontend-needs §2.3 的 `GET /warehouses`、`GET /balances/list`、`GET /stats/summary` 与配置键 `LOW_STOCK_THRESHOLD`；重构 `repo.go`（581 行）；对照事件规则核对 `mdm.product.created/updated.v1` 消费者的幂等与 version 严格递增。

### 环境

brickKit v1.1.0；目标 docker；拓扑：独立组件；项目里另有 mdm/customer、infra/authz、infra/notification、infra/workflow、mdm/product、integration/im-dingtalk、infra/print（都是 2.0.0，别的工作线加入），infra/iam-casdoor 不在项目里。本地模式开始与结束都是 off（`brickkit local status` → `Local mode: off` / `deploy.local.yaml: none`）。

### 步骤

**C1 前置（06:38–06:39）**

- env.sh：`ℹ️  env.sh：BrickKit CLI v1.1.0（/home/zhijie/.local/bin/brickkit）；buf 在；TEST_PG_DSN 由 .env 的 POSTGRES_PASSWORD 在 eval 时拼出（URL 编码，不打印值），TEST_NATS_URL=nats://localhost:4222`
- `command -v protoc-gen-go protoc-gen-go-grpc` → `/home/zhijie/go/bin/protoc-gen-go`、`/home/zhijie/go/bin/protoc-gen-go-grpc`
- `git -C $C status -sb` → `## main...origin/main`，无文件行；最后一个 1.x tag `v1.0.18`；最新契约包 tag `gen/erp/inventory/v1.0.14`
- 无依赖，"上游已发布"不适用。
- 1.6 表属主：`select tableowner, count(*) … where schemaname='erp_inventory'` → 空（演示库里还没有本组件的表）。真机迁移之后 → `erp_inventory_rw|31`。
- 1.5 读了旧 AGENTS / README / docs/手册.md、`archive/pre-v1/docs/dev/design/erp-inventory.md`、四个清单 / 构建文件、frontend-needs §2.3、02-backend 的相关节、样板 mdm/customer 的 Makefile / Dockerfile / 八份文档与记录。

**C2 骨架（06:39）**：`docs-skel.sh` → `✅ docs-skel：改动 8 个文件，跳过 0 个`，`exit=0`；`git rm docs/手册.md`；`brickkit skills update` → `✅ AI assistant skills updated / Wrote 1: .claude/skills/brickkit-component/SKILL.md`。九个文件在，`CLAUDE.md` = `@AGENTS.md`，维护块在，留底在 `$S/old/`。

**C3 清单（06:39）**

- `--write`：`assembly.yaml 删除的键：['version', 'asset', 'shell']`；`旧键 → 新键：{'pgSchema': 'PG_SCHEMA', 'iamJwksUrl': 'IAM_JWKS_URL', 'authzBundleUrl': 'AUTHZ_BUNDLE_URL', 'otelBaseUrl': 'OTEL_BASE_URL'}`；`backend/module/module.go:27: "pgSchema" → "PG_SCHEMA"`；`assembly.yaml：去掉 1 行归档引用注释`（`# warehouse 维（设计计划 §1、设计书 §14.2.2）：…` → 去掉括号，结论写进 design.md 的 Data scopes）；`exit=0`。`LOW_STOCK_THRESHOLD: {type: string, default: "10"}` 来自 overrides 已有的 `add_properties`。
- `--check` → `✅ --check 全部为"无"`，`exit=0`。
- `brickkit lint erp/inventory` → 第一行 `🔎 Only erp/inventory is checked …`，`✅ components/erp/inventory/component.yaml`，`📋 Checked 2 files: 0 with errors, 66 warnings`（只有占位符与"文档未提到"两类），无 `MANIFEST_INVALID`。
- 无新权限键，没跑 `make permissions`。

**C4 代码（06:39–07:05）**

- `go-v2.sh erp/inventory --sdk v0.4.0` → `exit=0`，判据 15 条全部 PASS；`go: upgraded go 1.25.0 => 1.25.11`、`be-sdk-go v0.2.4 → v0.4.0`、`golang-migrate v4.19.1 => v4.20.1`；`📌 第 8.3 步：不需要打契约包 tag（本地 gen/erp/inventory 与 gen/erp/inventory/v1.0.14 一致）`。读 diff：`cmd/migrate/main.go` 一行化、`module.go` 删 `Migrations:` 与 migrations import、`role := schema + "_rw"` 保留。提交 c4fa253。
- 4.16 `make test-db-init ID=erp/inventory`：`{"msg":"迁移结束","direction":"up","schema":"erp_inventory","outcome":"ok","version":4,"dirty":false}` ×2、`✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。基线 `go test ./... -race`：4 个包 ok，34 个 PASS，0 SKIP。
- 4.10 重构（f5624ed）：`repo.go` 581 行拆成 `repo.go`（错误、Repo、幂等工具）/ `balance.go` / `movement.go`；`Receive` 与 `Adjust` 逐行重复的 7 步事务抽成 `applyStockChange`（Adjust 的条件更新由 `guarded` 保留）；`ListMovements` 从 `fmt.Sprintf` 拼 SQL 改成一条静态查询；`isNegative` 不再 `ParseFloat`。原有测试不改全绿；新增行为对照 `TestListMovements_游标翻页不重不漏且可按仓库过滤`，在拆分前的提交（c4fa253 的 worktree）上同样 PASS。4.10 的长文件 / 长函数扫描之后：无超过 600 行的文件、无超过 150 行的函数。
- 4.11 三个真实 bug，各一个红绿提交：
  - eaa30a5 非法游标 500 → 400。红：`list_test.go:25: cursor="!!!不是base64"：非法游标应映射成 InvalidArgument，实际 Internal（非法 cursor：illegal base64 data at input byte 0）`。
  - 1f8944a REST `GET /movements` 不读契约里已声明的 `created_after` / `created_before`。红：`http_test.go:129: created_before=2026-10-02T03:46:15Z 时刚写入的流水不该出现，实际 1 条`、`http_test.go:141: created_after=昨天 应返回 400，实际 200（{"movements":[],"next_cursor":""}）`。
  - 6aae914 `GetReservationStatus` 按幂等键查时没限定 command。红：`reservation_status_test.go:43: idempotency_key="test-confirm-foreign-…"（不是 Reserve 的键）不该报错：参数不合法: reservation_id 不合法："CONFIRMED|3220"`。
- 4.11 消费者核对（未改代码）：`besdk.Consume` 按（subject, aggregate_id）只接受严格更大的 version、event_inbox 去重；跨 subject 的乱序由 `UpsertProductTrackingSnapshotTx` 的 `WHERE product_tracking_snapshots.version < EXCLUDED.version` 再挡一次（等 version 不覆盖，严格递增）；payload 的 `id` / `version` 是 mdm-product 事件清单里的 required 字段，与信封一致。已有测试 `TestConsumer_跨subject乱序时旧版本不覆盖新版本` 覆盖。结论：符合 02-backend 的事件规则。
- 4.12 合并安全：`make module-check` → `✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`。
- 4.13–4.15 新接口（fc44c5a）：先改 OpenAPI（只增），`.proto` 不变。先放返回空值的桩跑红（8 条红，原文见 `$S/red-new-endpoints.log`）：`stats_test.go:87: 用户 A 只授权了仓库 13，应恰好看到它，实际 []`、`stats_test.go:148: 用户 A 应恰好看到仓库 a 的 3 行余额（不重不漏），实际 []`、`stats_test.go:185: 非法游标应被拒绝`、`stats_test.go:213: 用户 A 的 sku_count 应为 3（只算仓 a），实际 0`、`stats_test.go:292: 阈值 10 时低库存应为 [th-3-… th-5-…]，实际 []`、`stats_test.go:310: "" 不是合法的非负十进制数，应被拒绝`、`config_test.go:28: map[LOW_STOCK_THRESHOLD:25]：阈值应为 "25"，实际 ""`、`http_test.go:187: GET /warehouses 的响应缺字段 "warehouses"：map[]`。实现后全绿（47 PASS）。数据范围测试：每个测试新建两个仓库、两个用户，各自看不到对方的仓库、余额、统计；无授权用户全空 / 全零。REST 形状测试里"非法游标"一条在实现时改成核对 handler 交给 `c.Error` 的错误码（裸 gin 引擎没有 SDK 的错误映射中间件，HTTP 400 在单元测试里测不到；这条断言从未提交过红版本，提交信息写明）。`go-v2.sh --recheck` 全部 PASS、仍 `v1.0.14`。
- 注释清理：非测试代码与契约说明 beb6936；OpenAPI 补 `/warehouse-access` 三条路由 9edc51f（代码早有、契约漏了，只增）；测试注释 + 两个测试文件 gofmt 4dd32e3（断言未动，`git diff` 里非注释行只有 gofmt 的一处对齐）。`.proto` 与已发布迁移 `.sql` 的注释不动（R41）。
- 4.7 / 4.9（5d93276）：Makefile 照 mdm/customer 模板（`grep -n -i 'customer\|客户' Makefile` 为空）；`dag-check` 文案改成物理命令枢纽；`seed` 先核对 `infra/iam-casdoor`、`infra/authz` 在 `brickkit.yaml` 里，不在就点名失败；`db-reset` 改用 SDK 迁移入口（PG_*）。Dockerfile 照样板（不再拷 migrations/）。`scripts/seed.sh` 注释去掉历史；新增 `SEED-INV-PROD-E`（WH-EAST 在手 6）、`SEED-INV-PROD-F`（WH-SOUTH 在手 30、在途预留 25），连同原有 `SEED-INV-PROD-C`（在手 1、预留 1）共三行低于默认阈值 10；末尾用同一个 token 打印 `/warehouses` 与 `/stats/summary`。
- 4.18 `component-check.sh`（C4 结束）：第 1–9 项 PASS，第 10 项（占位符）FAIL，符合预期。

**C5 文档（07:00–07:05）**：八份写满（67dedbe）。`component-check.sh` → `✅ 10 项全部 PASS`；`make docs-boundary` exit 0；`make docs-check ID=erp/inventory` → `📋 Checked 2 files: 0 with errors, 0 warnings`，`exit=0`（第一次就过）。

**C6 版本与门禁（07:06–07:09）**

- `make check-version test dag-check contract-check import-scan module-check` → `exit=0`：`✓ version=2.0.0…`、6 个包 ok、`✓ 无依赖，无环`、`buf breaking --against '.git#tag=v1.0.18'`、`✓ 无组件间 import`、`✓ 入口签名对…`；`--- SKIP` 计数 0。
- `make test-db-init ID=erp/inventory` → `✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。
- `make gates`（锁内，07:07:27–07:08:48，exit 0）：import / SystemClient / 裸路由 / 事件破坏 / data-scope-test / dependency-version 全部 `0 条违规`；`service-hostname-scan：0 条错误（1 条警告）`（`config/vars.yaml:23：infra-iam-casdoor-2-0-0 对应的组件不在 brickkit.yaml 里`，预期）；`config-key-scan：0 条违规`（另有 5 个 1.x 组件的 31 条 naming 警告）；`openapi-additive-scan：0 条违规（0 条跳过提示）`。
- ship 同判的发布前门禁（锁内）：`✓ config-key-scan（只看 components/erp/inventory）：0 条违规` exit 0；`✓ openapi-additive-scan（只看 components/erp/inventory）：0 条违规（0 条跳过提示）` exit 0。

**C7 接入与真机（07:09–07:17）**

- `make integrate ID=erp/inventory`（07:09:00–07:09:05，exit 0）：db-init `✓`；`brickkit add erp/inventory@2.0.0 --yes` → 7 行 `🔗 … references the variable of the same name in config/vars.yaml`、`✅ erp/inventory@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml`；`config-fill.py` → `写了 3 个键：PG_PASSWORD, PG_USER, PG_SCHEMA`（无退出码 3）；teardown-sync 同步；`brickkit lint --strict erp/inventory` → `0 with errors, 0 warnings`（含 `configuration (config/ ↔ configSchema)`）；`up --dry-run` → `✅ erp/inventory@2.0.0  starting (top-level)`。`config/erp-inventory.yaml` 里 `LOW_STOCK_THRESHOLD` 是注释行 `# LOW_STOCK_THRESHOLD: "10"  # string (default)`（按 Task"保持注释"）。生成的 compose：`PG_USER=erp_inventory_rw`、`PG_SCHEMA=erp_inventory`、`LOW_STOCK_THRESHOLD=10`、两个 URL 用成员服务名、`extra_hosts: host.docker.internal:host-gateway`。之后 `make teardown-sync CHECK=1` → `✓ deploy.teardown.yaml 与 deploy.yaml 一致`。
- Review Focus 2 真机核对（07:10–07:13）：锁内把 `config/erp-inventory.yaml` 的注释行临时改成 `LOW_STOCK_THRESHOLD: "25"`（先备份），`make verify ID=erp/inventory ROUTE=/erp/inventory/warehouses OUT=…/erp-inventory-threshold25` → 全部 PASS / 写明原因的 SKIP、exit 0；容器日志 `{"level":"INFO","msg":"低库存阈值","component_id":"erp/inventory","LOW_STOCK_THRESHOLD":"25"}`。之后锁内恢复，`cmp` 与备份逐字节相同。最终 verify 的容器日志与 focus 日志都是 `"LOW_STOCK_THRESHOLD":"10"`。带 token 打 `stats/summary` 看低库存清单变化这一步做不了（iam 不在项目里），行为层面由 L2 测试 `TestStockSummary_阈值配成非默认值时低库存清单随之变化` 与模块测试 `TestLowStockThreshold_读LOW_STOCK_THRESHOLD` 守。
- 最终 `make verify ID=erp/inventory ROUTE=/erp/inventory/warehouses FOCUS=1 SEED=1 FORCE_BUILD=1`（07:15:43–07:16:45，镜像从 HEAD 67dedbe 重建），exit 2：

```
verify erp/inventory@2.0.0 汇总（输出目录 $BE_SCRATCH/verify/erp-inventory-final）
| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build erp/inventory | PASS |  | build.log |
| 镜像 erp-inventory:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| erp-inventory-2-0-0 running (healthy)（容器服务 erp-inventory-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| GET /erp/inventory/warehouses 不带 token → 401/503 | PASS | 实际 401 | http.log |
| GET /erp/inventory/warehouses 带 token → 200 | SKIP | infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token |  |
| make -C components/erp/inventory seed | FAIL | 种子脚本失败，见日志 | seed.log |
| make test-cross ID=erp/inventory | PASS |  | test-cross.log |
| focus：宿主机 http://localhost:8086/healthz → 200 | PASS |  | focus.log |
| brickkit up --all --dry-run（清除 focus） | PASS |  | focus-all-dry-run.log |
| brickkit local off | PASS |  | local-off.log |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |
✗ 有 FAIL
```

  seed.log 全文：`✗ make seed 需要 infra/iam-casdoor 在项目里（brickkit.yaml 里没有）：入库 / 调整要真实 JWT 与权限` / `make: *** [Makefile:114: seed] Error 1`。这是预期的失败：本组件的入库 / 调整只能经 REST + 真实 JWT + warehouse_access 写入（gRPC 直连时没有 Claims，失败关闭），iam-casdoor（T17）加入项目之前没有任何正当的写入途径。见"卡点与绕过" 2。迁移容器日志最后一行 `{"msg":"迁移结束","direction":"up","schema":"erp_inventory","outcome":"ok","version":4,"dirty":false}`；focus 一节 `focus 用 deploy.local.yaml 的 vars: 把 host.docker.internal 换成 host-gateway IP 172.17.0.1：PG_HOST, NATS_URL, S3_URL`、`erp-inventory-2-0-0  listening on port 8086`（与声明端口一致）。收尾后 `brickkit local status` → `Local mode: off` / `deploy.local.yaml: none`。（收尾之后项目根出现的 `deploy.verify.yaml` 属于同时在跑的 infra/print 的 verify，不是本组件的。）

**C8 交接（07:17–07:20）**：发布说明 `$S/notes-2.0.0.md` 补了"新增 / 修复 / 其它"，并在"升级前必须做"里有意加了两行（契约包仍 v1.0.14；迁移状态表沿用 `schema_migrations_erp_inventory`，两个库里实测都是这张表），所以最后一次 `--write` 打印 `⚠️ notes-2.0.0.md 的"## 升级前必须做"一节与重新生成的不同`——`diff` 核对过，差异只是这两行与镜像一行的补充说明。`--write` 其余：`component.yaml / assembly.yaml：未改动`。组件仓库工作区干净，`## main...origin/main [ahead 11]`。`go list -m all | grep brickKit/erp-inventory` 恰好两行：`github.com/brickKit/erp-inventory/v2`、`github.com/brickKit/erp-inventory/gen/erp/inventory v1.0.14 => ./gen/erp/inventory`。

### 现象

- 符合预期的：三个迁移工具一次通过；SDK 一行迁移入口在测试库（已有 version 4，空跑）与演示库（全新建表）都 `outcome=ok`，表属主 `erp_inventory_rw`；容器形态、focus 全部 PASS；不带 token 401；`LOW_STOCK_THRESHOLD` 非默认值在运行期生效。
- 不符合预期的：旧组件有三处真实 bug（游标 500、REST 不读时间窗口参数、按幂等键查状态不限定命令）；OpenAPI 漏了三条已有路由；`make seed` 在 iam-casdoor 加入项目之前没法跑通。

### 卡点与绕过

1. **父仓库误提交（已撤销）。** 06:58 提交组件的注释改写时，那次 Bash 调用开头没有 `cd` 到组件目录（上一次调用的 `cd` 不保留），`git add -A && git commit -F msg-7.txt` 落在父仓库，生成父仓库提交 b5f628b（15 个路径：AGENTS.md、brickkit.yaml、8 个 components/* 指针、config/infra-authz.yaml、config/infra-notification.yaml、deploy*.yaml、registry/permissions.tsv——都是别的工作线写出、未提交的文件）。未推送。发现后立即核对 HEAD 仍是 b5f628b、没有 `.git/index.lock`，`git reset --mixed 39864bc` 撤销：HEAD 回到 39864bc，工作区一字未动，那些文件回到"未暂存"（两个 config 回到未跟踪）。之后控制者在 39864bc 上正常提交了 c31e97d、086fac1（reflog 可查）。此后本 Task 的所有 git 命令一律写 `git -C <路径>`。
2. **种子数据要 iam。** Receive / Adjust 只接受经 RequirePermission 验签的请求（service 用 `besdk.ScopeOf` 取 sub 查 warehouse_access）；经 gRPC 直连时 ScopeOf panic、被 SDK 恢复成 Internal。所以种子只能走 REST + 真实 JWT，iam-casdoor 不在项目里时没有正当途径。考虑过的绕法：直接写 SQL（绕过 Outbox，erp-finance 收不到事件，且要维护两套种子路径）、种子脚本发现缺 iam 就 exit 0（静默成功）——都不取。按最终形态保留 REST 种子，`make seed` 开头核对前提并点名失败。待 iam-casdoor 加入后（T17 / T25）`make verify … SEED=1` 再验。
3. 没有翻 brickKit 源码。读了本项目 `tools/be-sdk-go` 的 `scope.go`、`events.go`、`gin.go`、`standalone.go`、`query.go`、`runtime.go`（为了确认 ScopeOf 的 panic、Consume 的 version 规则、错误码映射、gRPC 恢复拦截器、ListWindow 默认值）——项目内工具，不算知识缺口。

### 协调者中途提示的两项

- **固定幂等键（mdm/product 发现的问题）**：逐个核对本组件测试的写命令幂等键——全部带 `uniqueProductID` / `svcUniqueProductID` / `unique()`（纳秒时间 + 自增序号），每次运行都不同；测试库实测 `test-recv-idem-%` 已有 36 个不同的键（每跑一次一个）。唯一的固定键 `svc-l3-items-empty` 在 service 校验阶段就被拒、从不进入声明（测试库里这个键 0 行）。两个固定的 sub（`u_test-adjust-neg-ok`、`svc-list-bad-cursor`）只用来授权、没有断言依赖跨运行的授权状态。结论：本组件没有这个问题，没有改测试。
- **R49（409 与错误码）**：`contracts/inventory.openapi.yaml` 没有声明任何 409；声明的错误只有 400（非法游标、`created_after` / `created_before` 格式、授权一个不存在的仓库）。代码里对应的都是 `InvalidArgument`（→ 400）；库存不足是 `FailedPrecondition`（→ 400，契约没写成 409）；越权点名仓库是 `PermissionDenied`（→ 403）；代码里没有 `Aborted` / `AlreadyExists`。没有不一致，没有要补的 409 测试。

### V 项

- V-13（`brickkit add` 重排注释）：本次 `add` 的 diff 混在别的工作线的累积改动里（`brickkit.yaml` 里本组件只多两行 `- id: erp/inventory` / `version: 2.0.0`），没能单独分辨出注释重排；不下结论。
- V-12（focus 与依赖容器共用 vars）：本组件 focus 没有容器依赖（只有 authz 的迁移容器在闭包里），host-gateway 改写照常（`172.17.0.1`），focus 进程 `/healthz` 200。不是 V-12 的判定场景（那是 T18）。
- V-04 知识缺口：无。

### 结论

完成到 C8 交接，遗留一项：`make verify … SEED=1` 的种子一行 FAIL（iam-casdoor 不在项目里，种子脚本点名失败），其余全部 PASS 或写明原因的 SKIP。组件仓库 11 个提交就绪（未推送、未打 tag），契约包不需要新 tag。

### 反馈候选

- **gRPC 上没有按调用者的数据范围**（be-sdk-go，项目内）：有范围的方法经 gRPC 直连时 ScopeOf panic、恢复成 Internal——失败关闭，但调用方拿到的是 500 而不是 401/403，排障时看不出原因。建议 SDK 提供"ctx 里有没有 Claims"的非 panic 查询，或在 gRPC 服务端校验 UserClient 转发来的 token。→ 交控制者（项目内 SDK，不进 brickKit 信箱）。
- **种子数据与 iam 的先后**：凡是有数据范围、只能经 REST 写入的组件（inventory、sales、finance…），在 iam-casdoor 加入项目之前 `make verify SEED=1` 都会 FAIL。建议 verify 在 iam-casdoor 不在项目里时把种子一行记成 SKIP（写明原因），或者 plan 里把这类组件的 SEED 验证挪到 T25。→ 交控制者。
- 组件 Makefile 模板的 `seed` 前提核对（本组件新加的那段 python 一行）对所有"种子要真 JWT"的组件都适用，可以进模板。→ 交控制者。

## 小结

- 完成：组件仓库提交（components/erp/inventory，均未推送）：
  - c4fa253 chore: 迁移到 brickKit v1 骨架与 2.0.0 清单（机械步骤）
  - f5624ed refactor(repo): repo.go 按职责拆成 repo / balance / movement 三个文件，抽出入库与调整共用的事务步骤
  - eaa30a5 fix: 非法列表游标返回 400 而不是 500
  - 1f8944a fix: REST GET /movements 读取契约里已有的 created_after / created_before
  - 6aae914 fix: 按幂等键查预留状态时只认 Reserve 的键
  - fc44c5a feat: 新增 GET /warehouses、GET /balances/list、GET /stats/summary（按 warehouse 维过滤）与配置键 LOW_STOCK_THRESHOLD
  - beb6936 docs(code): 代码与契约说明文字改写成原因本身，不再引用归档文档与历史
  - 9edc51f fix(contract): OpenAPI 补上代码早已提供的三条 /warehouse-access 路由
  - 4dd32e3 test: 测试注释改写成测的是什么、为什么，不再引用归档文档；两个测试文件 gofmt
  - 5d93276 chore: Makefile / Dockerfile / 种子脚本按 v1 改；种子数据加低库存与在途预留样例
  - 67dedbe docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
- 父仓库待控制者提交（脚本写出，未提交）：`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml` 里本组件的条目，`config/erp-inventory.yaml`（新文件，`LOW_STOCK_THRESHOLD` 为注释行），`AGENTS.md` 组件表的 erp/inventory 一行，`components/erp/inventory`（指针，ship 之后），本记录。`manifest-overrides.yaml` 本组件那一段没改。`registry/permissions.tsv` 里的 `+mdm.product.set_status` 是 mdm/product（T9）的，不是本组件的。
- 需要控制者裁定的：种子一行 FAIL 怎么算（见反馈候选第二条）；`stats/summary` 多了一个 frontend-needs 没写的字段 `low_stock_count`（清单截断到 50 行后看得出总数；只增）；`GET /warehouses` 按 frontend-needs 的形状不分页（仓库是几十行的播种主数据，理由写进 design.md）。
- 遗留到后续：带 token 打受保护路由得 200、`make seed` 真跑、`stats/summary` 在真数据上的低库存清单（T17 / T25）；归档、终态预留清理、对账任务（design.md 未决问题，无代码）；`.proto` 注释清理（下一次真实契约变更）。
- 检查点：erp/inventory 2.0.0，tag `2.0.0` / `v2.0.0` 待 `make ship`，契约包不需要新 tag，组件 HEAD 67dedbe。

## 修复轮（审查 task-10-review.md 的 I1、M1、M2）

### 目标

发版前修掉审查提出的 I1（数量入参用 ParseFloat 校验，NaN 能存进余额让防超卖失效）、M1（发布说明把可选新键列进"升级前必须做"）、M2（BRICKKIT 部署前准备对归档 schema 的要求比代码严）。

### 环境

brickKit CLI v1.1.0；be-postgres / nats 基础资源在跑；起点组件 HEAD 67dedbe（工作区干净）；local mode off。

### 步骤

1. 红测试（`go test ./backend/internal/service/ ./backend/internal/http/ -run 'TestQty_|TestMovements_REST'`，日志 `$BE_SCRATCH/06b/erp-inventory/fix-i1-red.log`）。关键输出原文：
   ```
   --- FAIL: TestQty_NaN_Inf_科学计数法与空串一律是InvalidArgument (0.19s)
       service_test.go:233: Receive qty="NaN" 应该是 InvalidArgument，实际：<nil>
       service_test.go:239: Adjust qty_delta="NaN" 应该是 InvalidArgument，实际：<nil>
       service_test.go:246: Reserve qty="NaN" 应该是 InvalidArgument，实际：<nil>
       service_test.go:233: Receive qty="Inf" 应该是 InvalidArgument，实际：写 inventory_movements: ERROR: numeric field overflow (SQLSTATE 22003)
       service_test.go:233: Receive qty="1e3" 应该是 InvalidArgument，实际：<nil>
       service_test.go:233: Receive qty="0x1p4" 应该是 InvalidArgument，实际：更新 inventory_balances: ERROR: invalid input syntax for type numeric: "0x1p4" (SQLSTATE 22P02)
       service_test.go:246: Reserve qty="0.0000001" 应该是 InvalidArgument，实际：写 inventory_reservations: ERROR: new row for relation "inventory_reservations" violates check constraint "inventory_reservations_qty_positive" (SQLSTATE 23514)
       service_test.go:233: Receive qty="1234567890123" 应该是 InvalidArgument，实际：写 inventory_movements: ERROR: numeric field overflow (SQLSTATE 22003)
       service_test.go:250: 被拒绝的数量入参不该写下余额行，实际 1 行
   --- FAIL: TestMovements_REST的NaN_Inf_科学计数法数量返回400 (0.06s)
       http_test.go:296: POST /movements/receive qty="NaN" 应交出 InvalidArgument（HTTP 400），实际 OK
       http_test.go:296: POST /movements/receive qty="Inf" 应交出 InvalidArgument（HTTP 400），实际 Internal
       http_test.go:296: POST /movements/receive qty="1e3" 应交出 InvalidArgument（HTTP 400），实际 OK
   ```
   （Reserve qty="NaN" 返回 nil：同一轮里先入库的 NaN 已经让 on_hand_qty 变成 NaN，没有任何库存也预留成功——审查描述的无限超卖在测试库里真实复现。）
2. 修：`service.validateQty` 改成只认 `^-?[0-9]{1,12}(\.[0-9]{1,6})?$`（与 `NUMERIC(18,6)` 对齐），符号与是否为 0 按字符串判断。Receive / Adjust / Reserve 三个调用点都走它；ConfirmIssue 不收数量。
3. 绿（`fix-i1-green.log`）：`TestQty_*` 三个、`TestMovements_REST的NaN_Inf_科学计数法数量返回400`、原有 `TestReserve_qty为0或负数时拒绝` / `TestReceive_qty为负数时拒绝` / `TestAdjust_*` 全部 PASS。提交 cda30d0。
4. 文档（提交 4ffb7c2）：BRICKKIT.md / .zh.md 部署前准备改成 mdm/customer 的写法（"plus `erp_inventory_archive` if your schema convention creates one (this component never writes to it)"，USAGE / CREATE 只要求在 `erp_inventory` 上）；AGENTS.md / .zh.md 设计取舍加"数量是严格十进制字符串"，易错点加"不许用 strconv.ParseFloat 校验数量"一行。
5. 发布说明 `$BE_SCRATCH/06b/erp-inventory/notes-2.0.0.md`：删掉"升级前必须做"里的 `LOW_STOCK_THRESHOLD` 一行（M1；"新增"里已有）；"修复"加一行数量严格校验。
6. 门禁：
   - `bash dev/phase-06/tools/component-check.sh erp/inventory` → `✅ component-check erp/inventory：10 项全部 PASS`，exit=0；
   - `make -C $ROOT docs-check ID=erp/inventory` → `📋 Checked 3 files: 0 with errors, 0 warnings`，exit=0；
   - `make test`（env.sh 前导三行）→ exit=0，六个包 ok，`-v` 计数 51 PASS、0 SKIP、0 FAIL（原 47 + 新 4）；
   - 顺带 `make check-version contract-check import-scan module-check dag-check` → exit=0（`buf breaking --against '.git#tag=v1.0.18'`）。
7. 真机：`make -C $ROOT verify ID=erp/inventory ROUTE=/erp/inventory/warehouses FORCE_BUILD=1` → exit=0，输出目录 `$BE_SCRATCH/verify/erp-inventory-20261002-123548`：

| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build erp/inventory | PASS |  | build.log |
| 镜像 erp-inventory:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| erp-inventory-2-0-0 running (healthy)（容器服务 erp-inventory-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| GET /erp/inventory/warehouses 不带 token → 401/503 | PASS | 实际 401 | http.log |
| GET /erp/inventory/warehouses 带 token → 200 | SKIP | infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token |  |
| make -C <源目录> seed | SKIP | 没设 SEED=1 |  |
| make test-cross ID=erp/inventory | PASS |  | test-cross.log |
| brickkit up --focus erp/inventory | SKIP | 没设 FOCUS=1 |  |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |

   镜像 `erp-inventory:2.0.0` 创建时间 2026-10-02T12:36:44+02:00（本轮重建）；收尾后 `docker ps` 里没有 erp-inventory 容器。

### 现象

ParseFloat 放行的写法不止 NaN / Inf / 1e3：`0x1p4`（十六进制浮点）进 SQL 是 22P02 → 500；13 位整数是 numeric overflow → 500；`0.0000001` 入库与调整返回成功（按 `NUMERIC(18,6)` 存进去是 0，没有单独查库核对），预留则撞上 `inventory_reservations_qty_positive` → 500。新校验把位数上限与列类型对齐，这几类一并变成 400。

### 卡点与绕过

- REST 层测试沿用本文件已有的做法：裸 engine 没有 SDK 的错误映射中间件，所以核对 handler 交出的 gRPC 码是 InvalidArgument（SDK 按 R49 映射成 400）；空串在 gin 绑定（`binding:"required"`）时直接 400，这一条核对的是真实 HTTP 状态码。
- `component-check.sh` 第一次跑 exit=2：那次调用没导出 BE_SCRATCH（脚本要求），导出后 exit=0。

### 结论

I1 修复且先红后绿；M1、M2 已改。全部门禁与真机 verify 通过（PASS 或写明原因的 SKIP）。组件 HEAD 4ffb7c2，未推送、未打 tag；契约包不需要新 tag（只改 service 与文档，`.proto` / OpenAPI 未动）。

### 反馈候选

- **notes 生成器把有默认值的新键放进"升级前必须做"**：`notes-2.0.0.generated.md` 第 8 行仍是"新增配置键 `LOW_STOCK_THRESHOLD`（默认 `10`，不配也能跑）"在"升级前必须做"一节里——M1 的根源在 `migrate-manifest.py` 的生成逻辑。下次 `--write` 时它会把手改后的 notes 判为"升级前必须做不一致"并打印 ⚠️。建议生成器只把"没有默认值的新键 / 改名 / 改必填"列进那一节。→ 交控制者（dev/phase-06/tools，本轮没动）。
- 数量校验收紧也拒绝了 `+1`、`.5`、`1.`（PostgreSQL 本来接受）。项目内调用方（erp/sales）送的是 `NUMERIC(18,6)` 的文本，不受影响；发布说明里已写明。
