# 06b mdm/product：过程记录（T9）

## 概况

- 日期：2026-10-02（06:38 开工）
- brickKit：`brickkit version` → `BrickKit CLI v1.1.0`（`env.sh` 的 ℹ️ 行原文：`ℹ️  env.sh：BrickKit CLI v1.1.0（/home/zhijie/.local/bin/brickkit）；buf 在；TEST_PG_DSN 由 .env 的 POSTGRES_PASSWORD 在 eval 时拼出（URL 编码，不打印值），TEST_NATS_URL=nats://localhost:4222`）
- SDK：be-sdk-go v0.4.0（`go-v2.sh --sdk v0.4.0` 判据 `be-sdk-go 是 v0.4.0`）；be-sdk-python / be-sdk-ts 本组件不用
- 基础资源：`make check` → `✓ 全部基础资源就绪`（postgres、nats、traefik、casdoor、rustfs 全部 healthy）
- 组件与版本：mdm/product v1.0.11 → 2.0.0；组件仓库 15 个提交（e5c7055 … 7ee4fd9，见"小结"，未推送、未打 tag）；tag 待控制者 `make ship`：`2.0.0`、`v2.0.0`；**契约包需要新 tag `gen/mdm/product/v1.1.0`**（`ListRequest.q = 6`）
- 交接给控制者：见文末"小结"

## mdm/product

### 目标

按 component-loop 重建到 2.0.0；补 frontend-needs §2.2：`GET /products?q=`（sku、name）、gRPC `ListRequest.q`（BFF `searchProducts`）、`POST /products/{id}/status` 改绑新键 `mdm.product.set_status`；契约包 `gen/mdm/product/v1.1.0`。

### 环境

brickKit v1.1.0；目标 docker；拓扑：独立组件（不进外壳）；无依赖；开工与结束时本地模式 off（`brickkit local status` → `Local mode: off` / `deploy.local.yaml: none (brickkit local on creates it)`）。项目里同时在做 W1 的其它组件（authz、notification、workflow 等已加入 brickkit.yaml）。

### 步骤

**C1 前置（06:38）**

- `env.sh mdm/product`：无 exit 2；`$S=$BE_SCRATCH/06b/mdm-product`、`SCHEMA=mdm_product`、`ROLE=mdm_product_rw`、`SVC=mdm-product-2-0-0`、`UREPO=MDM_PRODUCT`。
- `command -v protoc-gen-go protoc-gen-go-grpc` → `/home/zhijie/go/bin/protoc-gen-go`、`/home/zhijie/go/bin/protoc-gen-go-grpc`。
- `git -C $C status -sb` → `## main...origin/main`，无文件行；`git describe --tags` → `v1.0.11`；最后一个 1.x tag `v1.0.11`，最新契约包 tag `gen/mdm/product/v1.0.7`。
- 无依赖，"上游已发布"不适用。
- 1.6 表属主：`select tableowner, count(*) from pg_tables where schemaname='mdm_product' group by 1` → 空（演示库里还没有本组件的表）。
- 1.5 读了：旧 AGENTS / README / docs/手册.md（手册只有目录结构，其余全是"随 Task N 补"占位）、`archive/pre-v1/docs/dev/design/mdm-product.md`、四个清单 / 构建文件、frontend-needs §2.2、样板 mdm/customer（Makefile、Dockerfile、八份文档、search_test.go、http_test.go）、be-sdk-go v0.4.0 的 `authz.go` / `bundle.go` / `jwt.go` / `shell.go` / `gin.go` / `archive.go`（为写 403 测试与核对 BatchGetRouted 的 SQL；SDK 是本项目的工具仓库，不是 brickKit 源码）。

**C2 骨架（06:40:06，<1 秒）**

```
✅ docs-skel：改动 8 个文件，跳过 0 个（跳过的是已经填写过的文件）
exit=0
📦 Component repository (has component.yaml, no brickkit.yaml): the brickkit-component skill, plus the component's own AGENTS.md and CLAUDE.md
✅ AI assistant skills updated
   Wrote 1:
     .claude/skills/brickkit-component/SKILL.md
```

通过：九个文件都在；`CLAUDE.md` 恰好 `@AGENTS.md`；`AGENTS.md` 第 27 行 `<!-- brickkit:managed:begin lang=en -->`；留底在 `$S/old/`（8 个文件，取自 v1.0.11）。

**C3 清单（06:40:17，约 1 秒）**

- `--write`：`assembly.yaml 删除的键：['version', 'asset', 'shell']；data.role 注释 → # 登录角色，`PG_USER` 的值`；`去掉 1 行归档引用注释`；`旧键 → 新键：{'pgSchema': 'PG_SCHEMA', 'iamJwksUrl': 'IAM_JWKS_URL', 'authzBundleUrl': 'AUTHZ_BUNDLE_URL', 'otelBaseUrl': 'OTEL_BASE_URL'}`；`assembly.yaml 追加：{'permissions': ['mdm.product.set_status']}`；`backend/module/module.go:29: "pgSchema" → "PG_SCHEMA"`；`exit=0`。没有打印 ⚠️。
- `--check` 16 项全部"无"，`✅ --check 全部为"无"`，`exit=0`。
- `brickkit lint mdm/product`：第一行 `🔎 Only mdm/product is checked (brickkit lint --all checks the whole project)`，`✅ components/mdm/product/component.yaml`，`📋 Checked 2 files: 0 with errors, 66 warnings`（只有占位符与"文档没提到 required 键 / 契约文件"两类）。
- 去掉的注释（`$S/assembly-removed-comments.txt`）：`data_scopes: none  # 产品主数据全员可见（设计书 §14.2.2：…）` → 去掉括号；结论（全员可见、无数据范围）已写进 design.md 的 Data scopes。
- 3.5 `make permissions`（06:40:21）：`✓ registry/permissions.tsv 已产出（43 条权限键）`、`✓ registry/permissions.tsv 相对 HEAD 只有新增`；`git diff registry/permissions.tsv` 的 `+` 行只有 `mdm.product.set_status	启用/停用产品	action	mdm/product`，没有别的组件的行。
- overrides：`manifest-overrides.yaml` 的 mdm/product 段原样使用（标题初稿"启用/停用产品"保留，未改）。

**C4 代码（06:40:31–06:58）**

- `go-v2.sh mdm/product --sdk v0.4.0`：`exit=0`，形态 A，判据 15 条全部 PASS，`📌 第 8.3 步：不需要打契约包 tag（本地 gen/mdm/product 与 gen/mdm/product/v1.0.7 一致）`、`✅ go-v2.sh：判据全部 PASS`。值得注意的输出：`go: upgraded go 1.25.0 => 1.25.11`、`go: upgraded github.com/golang-migrate/migrate/v4 v4.19.1 => v4.20.1`、`ℹ️ 这些非 Go 文件还提到 github.com/brickKit/mdm-product（不带 /v2）…：component.yaml`（metadata.repository，正确）。
- 读 diff：`cmd/migrate/main.go` 一行化；`module.go` 删 `Migrations:` 与 migrations import；`lib/pq` 消失；golang-migrate 变 indirect；`role := schema + "_rw"` 保留；Dockerfile 仍 `-o /out/migrate` → `/app/migrate`。提交 e5c7055（机械步骤，含 C2 / C3）。
- 4.16 `make test-db-init ID=mdm/product`（06:40:58）：`{"msg":"迁移结束","direction":"up","schema":"mdm_product","outcome":"ok","version":3,"dirty":false}` ×2、`✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。基线测试全绿、SKIP 0。
- **测试本身的缺陷（单独提交 102f7fb）**：写路径测试用固定幂等键（`test-autosku-001`、`svc-status-001` …）与固定 sku（`P-001`、`P-SVC-STATUS` …）。测试库跨运行保留数据，第一次之后每次都只命中幂等重放——Create / Update / SetStatus 的写路径从第二次运行起根本没被执行，断言照样绿。重构前必须先把它修好，否则重构没有测试守。加 `runKey(prefix)`，断言一条没改；先在旧代码上跑绿（22 条 PASS），再做重构。
- 4.10 重构（提交 e8c08ee）：`repo.go` 598 行，三个写命令重复"查幂等键 → 写 → 记幂等键 → Outbox"，Update / SetStatus 几乎逐行相同，事件 payload 同一个 map 抄了三遍 → 拆成 `repo.go`（98）/ `write.go`（271，`replayProduct`、`recordIdempotency`、`publish`、`insertProduct`、`updateWithVersion`）/ `read.go`（151）/ `convert.go`（92）。测试不改，`-count=2` 全绿（真的走写路径）。拆完后最大的非测试文件 286 行，没有超过 150 行的函数。
- 4.11 真实 bug（每个先红后绿、一个提交）：
  - 0f14c9c 非法游标 500 → 400。红：`cursor="!!!不是base64" 应映射成 InvalidArgument，实际 Internal（非法 cursor：illegal base64 data at input byte 0）`。
  - 504a314 REST 不读 `created_after` / `created_before`。红：`给了 created_after=2026-03-16T03:45:11Z created_before=2026-03-16T05:45:11Z，200 天前的产品 82 应该在结果里（实际 72 条）`、`created_after 不是 RFC 3339 时间应返回 400，实际 200`。
  - 9eaad01 SetStatus 状态值。红：`status="DELETED" 应该拒绝并返回 ErrInvalidArgument，实际：<nil>`（REST 的 status 原样写进 products.status）、`status 未指定应返回 InvalidArgument，实际 OK（<nil>）`（gRPC 的 UNSPECIFIED 被当成 ACTIVE，漏填就把停用的产品重新启用）。
  - eb0428a 调用方的错被映射成 500。红：`…实际 Internal（insert products: ERROR: duplicate key value violates unique constraint "products_sku_uniq" (SQLSTATE 23505)）`、`base_uom_id 不存在：…实际 Internal（… violates foreign key constraint "products_base_uom_id_fkey" (SQLSTATE 23503)）`、`Update id=999999999：应映射成 NotFound，实际 Aborted（version 冲突…）`、`Get(abc) 应映射成 NotFound，实际 Internal（… invalid input syntax for type bigint: "abc" (SQLSTATE 22P02)）`。
  - a49e77b 十进制字符串。红：`qty="两箱" 应映射成 InvalidArgument，实际 Internal（换算: ERROR: invalid input syntax for type numeric: "两箱" (SQLSTATE 22P02)）`、`standard_cost="NaN" 应该拒绝并返回 ErrInvalidArgument，实际：<nil>`（ParseFloat 认 NaN，NUMERIC 也认，NaN 原样落库）。
- 4.13–4.15 `q`：设计先定（与 T7 同一套规则，见 design.md "Contract surface"），实现自己写（不复用 customer 代码）。
  - 契约（提交 b6219b8）：`.proto` 的 `ListRequest` 追加 `string q = 6;`，只改了 ListRequest 附近的注释（R41）；openapi 追加 `q` 参数。`buf generate` → `git diff --stat`：`product.proto | 8`、`product.openapi.yaml | 12`、`gen/mdm/product/v1/product.pb.go | 26`。`go-v2.sh --recheck`：`本地 gen/mdm/product 与 gen/mdm/product/v1.0.7 不一致（契约有变化）→ 下一个 minor v1.1.0`、判据全部 PASS、**`📌 第 8.3 步需要打的契约包 tag：gen/mdm/product/v1.1.0（必须等于根 go.mod require 的版本；推送前外壳拉不到）`**。`buf breaking --against '.git#tag=v1.0.11'` 通过。
  - 实现（提交 546596f）：先只加 `ListInput.Q` 字段跑红——`前缀匹配在前 / 大小写 / 首尾空白 / 通配符 / 与状态过滤同用 / 翻页不重不漏` 六条红（q 被忽略，返回窗口内全部行，例：`期望 5 条命中，实际 50`），`q为空白等于不过滤` 实现前后都绿；HTTP / gRPC 透传各一条红（`期望只返回产品 298，实际返回 50 条` / `…299…50 条`）→ 全部绿。
- set_status 改绑（提交 1c8d276）：`authz_test.go` 走真实路由 + SDK 权限中间件：测试自己起 JWKS 与 bundle 的 httptest 服务、用自己的 RSA 密钥签 RS256 token，经导出的 `besdk.InitShellAuthz` 装配，engine 用 `besdk.NewGinEngine(besdk.NewShellRuntime(...))`（业务错误按生产映射）。红：`只有 mdm.product.edit 的用户启用 / 停用应得 403，实际 200（{"id":"347",…,"status":"DISABLED",…}）`；改绑后绿：editor 启用 / 停用 403、编辑 200；只有 set_status 的用户启用 / 停用 200。`go.mod` 因此把 `golang-jwt/jwt/v5 v5.3.1` 从 indirect 升为直接依赖（只有测试用）。
- 4.12 合并安全：`make module-check` → `✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`；模块代码零 `os.Getenv` / `log.Fatal` / `os.Exit`（人工通读确认）。
- 注释清理：代码与契约说明文字一个提交（06df9a6；buf lint / breaking 通过），测试注释单独一个提交（62fa2f7，断言未动；diff 里除注释外只有两条 t.Fatal 文案去掉"（§3.10）""（§11.4.1）"与 pgx 导入行的行尾注释）。已发布迁移 `.sql` 的注释不动（不改旧迁移）。
- 4.7 Makefile / Dockerfile / 种子（提交 3695377）：Makefile 照抄 mdm/customer 模板，`diff` 只有 ID/REPO、migrate-idempotent 注释里的角色 / schema、seed 说明三处；`grep -n -i 'customer\|客户' Makefile` 为空。Dockerfile 照模板，端口 8082/9092。seed.sh 新增 seed-product-13、14（SKU `BOLT-M10` / `BOLT-M12`，前缀匹配样例），mkproduct 支持显式 sku；seed-clean 同步到 14。
- 4.17：`make test` → `exit=0`，5 个包 `ok`；`go test ./... -race -count=1 -v` 无 FAIL，`--- SKIP` 计数 `0`；`--- PASS` 44 条。
- 4.18 component-check（C4 结束）：第 1–9 项 PASS，第 10 项（占位符）FAIL（文档还是骨架，预期）。

**C5 文档（06:58–07:00）**

八份文件写满。`component-check.sh` → `✅ component-check mdm/product：10 项全部 PASS`；`make docs-boundary` 静默通过；`make docs-check ID=mdm/product` → `✅ components/mdm/product/component.yaml`、`✅ components/mdm/product/ (docs)`、`ℹ️ mdm/product is not in brickkit.yaml yet, so it has no configuration to check`、`📋 Checked 2 files: 0 with errors, 0 warnings`、`exit=0`。提交 7ee4fd9。
与样板的一处差异：mdm/customer 的 AGENTS "Build and test" 写的是 `set -a; . ../../../.env; set +a`，与 component-loop 0.2"不在 shell 里 source .env"冲突；本组件改成 `export TEST_PG_DSN="postgres://<user>:<password>@…/brickkit_test_db…"`（不 source）。

**C6 版本与门禁（07:01–07:05）**

- `make check-version test dag-check contract-check import-scan module-check`：`✓ version=2.0.0（go.mod 主版本一致；HEAD 上没有 tag，或 2.0.0 与 v2.0.0 都在）`、5 个包 `ok`、`✓ 无依赖，无环`、`buf breaking --against '.git#tag=v1.0.11'`（是上一个发布 tag，不是 main）、`✓ 无组件间 import`、`✓ 入口签名对…`，`exit=0`。
- `make test-db-init ID=mdm/product`（等锁约 2 分钟）：`outcome":"ok","version":3` ×2、`✓ 迁移幂等`。
- `migrate-manifest.py --check` → `✅ --check 全部为"无"`。
- `project-lock.sh -- make gates`（07:03:22–07:04:18）`exit=0`：import / system-client / bare-route / events-breaking / data-scope-test / dependency-version 全部 `0 条违规`；`service-hostname-scan：0 条错误（1 条警告）`（`infra-iam-casdoor-2-0-0 对应的组件不在 brickkit.yaml 里`，预期）；`config-key-scan：0 条违规`（警告只来自 5 个 1.x 组件，本组件不在其中）；`openapi-additive-scan：0 条违规（0 条跳过提示）`；`up --dry-run` 正常（本组件此时尚未加入项目）。本组件零违规；别的组件也没有 ✗。
- ship 的两个发布前门禁提前自查（锁内）：`✓ config-key-scan（只看 components/mdm/product）：0 条违规`、`cks=0`；`✓ openapi-additive-scan（只看 components/mdm/product）：0 条违规（0 条跳过提示）`、`oas=0`。

**C7 接入与真机（07:05–07:09）**

- `make integrate ID=mdm/product`（07:05:49–07:07:06，其中约 1 分钟等锁：`⏳ project lock held by: … infra-workflow/runtime-check.sh …（已等 60s）`）`exit=0`：
  - 1 `✓ .env 里的数据库密码已齐全，无需补充`、`✓ 建库脚本已产出：build/db-init.sql（54 个组件，4 个外壳清单，目标库 brickkit_db）`、`✓ 建库脚本已执行（幂等，可重跑）`；
  - 2 `brickkit add mdm/product@2.0.0 --yes` → 7 行 `🔗 … references the variable of the same name in config/vars.yaml (--yes)`、`➕ Adding mdm/product@2.0.0`、`✅ mdm/product@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml`、`📝 Config skeletons: config/mdm-product.yaml`、`✏️ Fill in the required keys in config/mdm-product.yaml: PG_PASSWORD, PG_USER`、`ℹ️  Not changed: deploy.teardown.yaml…`、`📦 Artifacts: 4 files, in .brickkit/artifacts/`；
  - 3 `config-fill.py` → `写了 3 个键：PG_PASSWORD, PG_USER, PG_SCHEMA`（没有退出码 3，不需要 `--set`）；生成的 `config/mdm-product.yaml`：`PG_USER: mdm_product_rw`、`PG_PASSWORD: ${MDM_PRODUCT_DB_PASSWORD}`、`PG_SCHEMA: mdm_product`，其余 `$var:`；
  - 4 `✓ deploy.teardown.yaml 已从 deploy.yaml 同步`；5 `brickkit lint --strict mdm/product` → `✅ mdm/product: configuration (config/ ↔ configSchema)`、`📋 Checked 3 files: 0 with errors, 0 warnings`；6 `up --dry-run` → `✅ mdm/product@2.0.0  starting (top-level)`；
  - 7 父仓库改动：`M AGENTS.md`、`M brickkit.yaml`、`M deploy.teardown.yaml`、`M deploy.yaml`、`M registry/permissions.tsv`、`?? config/mdm-product.yaml`，另有别的工作线的 `?? config/infra-authz.yaml`、`config/infra-notification.yaml`、`config/infra-workflow.yaml`（不是本 Task 的）。AGENTS.md 组件表本组件一行：`| mdm/product | 2.0.0 | SKUs, categories, unit-of-measure conversions, batch and serial tracking policies, and standard costs. | BRICKKIT.md +zh | https://github.com/brickKit/mdm-product |`。
  - V-13：`git diff brickkit.yaml` 只多了 `components:` 下的条目（本组件与别的工作线的 authz / notification / workflow），这次没有出现注释重排（注释在 mdm/customer 那次 add 时已被重排过，之后保持不变）。
- `make verify ID=mdm/product ROUTE=/mdm/product/products FOCUS=1 SEED=1`（07:07:23–07:08:44，81 秒，`exit=0`）。闭包 `infra/authz@2.0.0 mdm/product@2.0.0`（authz 已由别的工作线加入项目，iam-casdoor 未加入）：

```
verify mdm/product@2.0.0 汇总（输出目录 $BE_SCRATCH/verify/mdm-product-20261002-070729）
| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build mdm/product | PASS |  | build.log |
| 镜像 mdm-product:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| mdm-product-2-0-0 running (healthy)（容器服务 mdm-product-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| GET /mdm/product/products 不带 token → 401/503 | PASS | 实际 401 | http.log |
| GET /mdm/product/products 带 token → 200 | SKIP | infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token |  |
| make -C components/mdm/product seed | PASS |  | seed.log |
| make test-cross ID=mdm/product | PASS |  | test-cross.log |
| focus：宿主机 http://localhost:8082/healthz → 200 | PASS |  | focus.log |
| brickkit up --all --dry-run（清除 focus） | PASS |  | focus-all-dry-run.log |
| brickkit local off | PASS |  | local-off.log |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |
✓ 全部 PASS 或写明原因的 SKIP
```

  - build.log：`✅ Built mdm/product@2.0.0 → mdm-product:2.0.0`（从 HEAD 7ee4fd9 构建；verify 之后组件代码与文档没再改，不需要 FORCE_BUILD）。
  - 迁移容器日志最后一行：`{"msg":"迁移结束","direction":"up","schema":"mdm_product","outcome":"ok","version":3,"dirty":false}`（authz 的同样 `outcome":"ok"`）。
  - seed.log：`✓ 产品：1(NONE) 2(BATCH) 3(NONE) 4(SERIAL) 5(DISABLED) 6(NONE) 7(BATCH) 8(BATCH) 9(SERIAL) 10(SERIAL) 11(NONE) 12(DISABLED) 13(BOLT-M10) 14(BOLT-M12)`、`✓ 已给 4 个产品回填历史创建时间（1-4 个月前）`。
  - focus：`focus 用 deploy.local.yaml 的 vars: 把 host.docker.internal 换成 host-gateway IP 172.17.0.1：PG_HOST, NATS_URL, S3_URL`；focus.log `mdm-product-2-0-0  listening on port 8082`（与声明端口一致）。
  - 收尾后：`brickkit local status` → `Local mode: off` / `deploy.local.yaml: none (brickkit local on creates it)`；项目根没有 `deploy.verify.yaml`；`docker ps` 里没有本项目容器。
  - 演示库表属主：`mdm_product_rw|24`（迁移以登录角色建表）。
  - q 的规则在演示库的种子数据上按同一 SQL 核对（REST 要真 token，T25 才能验）：q=bolt → `14|BOLT-M12|…|0`、`13|BOLT-M10|…|0`（两条 sku 前缀）；q=螺栓 → `14`、`13`、`1`（都只是名称包含，按建档时间倒序）。
  - 带 token 打受保护路由得 200、以及 set_status 的 403 在真机上的复核：待 T25（iam-casdoor 加入后）。路由与权限键的绑定已由 `authz_test.go` 走真实 SDK 中间件覆盖。
  - Review Focus 2（有默认值的自有键配非默认值）：本组件没有自有键，只有共享键 `PG_SCHEMA` / `PG_PORT` / `OTEL_BASE_URL`；`PG_SCHEMA` 默认值与 config 字面量相同，代码读法 `StringOr("PG_SCHEMA", …)` 由 `--check`、component-check 第 1 项核对。

**C8 交接（07:10）**

- 发布说明 `$S/notes-2.0.0.md`：骨架的"升级前必须做"全部保留，另补四条（set_status 改绑要给角色授新键、契约包 v1.1.0、迁移状态表沿用、迁移文件嵌进二进制）；"新增 / 修复 / 其它"补全。最后一次 `--write`（07:10）：`component.yaml / assembly.yaml：未改动`，并打印 `⚠️ notes-2.0.0.md 的"## 升级前必须做"一节与重新生成的不同`——`diff` 核对：差异只是有意补进的上述四条（另两条在生成行末尾追加了说明），生成的每一行都在。
- `git -C $C log --oneline -3`：
```
7ee4fd9 docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
3695377 chore: Makefile / Dockerfile / 种子脚本按 v1 改；种子数据加关键字搜索样例
62fa2f7 test: 测试注释改写成测的是什么、为什么，不再引用归档文档
```
  工作区干净，`## main...origin/main [ahead 15]`。`go list -m all | grep brickKit/mdm-product` 恰好两行：`github.com/brickKit/mdm-product/v2`、`github.com/brickKit/mdm-product/gen/mdm/product v1.1.0 => ./gen/mdm/product`。

### 现象

- 符合预期的：脚本链（docs-skel / migrate-manifest / go-v2 / component-check）一次通过；契约包版本由 `--recheck` 自动算成 v1.1.0；SDK 迁移入口在测试库 `outcome=ok`；门禁零违规。
- 不符合预期的：
  - 旧测试的固定幂等键让写路径测试从第二次运行起形同虚设（见 C4），属于项目侧测试质量问题，不是 brickKit 的问题；其它 Go 组件很可能有同样的写法。
  - 1.x 代码里调用方的错大量回 500（重复 sku、外键、非数字 id、非法十进制、非法状态值），mdm/customer 2.0.0 里同类问题（重复 code、非数字 id、非法 status）大概率同样存在，T7 未覆盖。

### 卡点与绕过

- 等项目锁：`test-db-init` 与 ship 门禁自查各等了约 1–2 分钟（`⏳ project lock held by: pid=758093 cmd=bash infra/scripts/verify-component.sh infra/workflow（已等 60s）`），按规则等待，未绕过。
- 403 测试需要让 SDK 的权限中间件真正生效：SDK 没有给组件测试用的 authz 测试辅助，私有的 `setAuthzRuntime` 只能经导出的 `besdk.InitShellAuthz` 间接设置（它本是给外壳用的）。读了 be-sdk-go v0.4.0 的 `authz.go`、`shell.go`、`bundle.go`、`jwt.go`、`gin.go` 才确定这条路——这是本项目的 SDK，不是 brickKit 源码，不算 V-04 知识缺口，但列为反馈候选。
- 没有读 brickKit 源码；brickkit 相关问题全部用 `--help` / 输出答到了。

### V 项

- V-13（`brickkit add` 重排注释）：本次 add 没有重排注释（diff 只有新增的组件条目），结论见 C7。
- 本 Task 不涉及 V-12（无容器依赖）、V-03 / V-06（外壳 Task）。

### 结论

完成。mdm/product 2.0.0 的组件仓库 15 个提交就绪（未推送、未打 tag），`make verify … FOCUS=1 SEED=1` 全部 PASS（带 token 一项 SKIP，待 T25）；需要新契约包 tag `gen/mdm/product/v1.1.0`。

### 反馈候选

- **be-sdk-go 缺组件测试用的权限判定辅助**（项目工具，交控制者）：要测"路由绑了哪个权限键"，只能借外壳用的 `besdk.InitShellAuthz` 加自建 JWKS / bundle 服务（本组件 `authz_test.go` 约 90 行样板）。建议 SDK 提供 `besdktest.Authz(t, roles map[string][]string) (token func(role string) string)` 之类的辅助，13 个组件的"持有 A 键没有 B 键得 403"测试都能一行装配。→ 直接交控制者（项目工具），不进 brickKit 信箱。
- **`besdk.BatchGetRouted` 用 `SELECT *`**（项目工具）：组件表加一列、扫描函数没跟上，`BatchGet` 立刻报 `sql: expected 12 destination arguments in Scan, not 11`，而用显式列清单的 List / Get 不受影响。建议 SDK 接受列清单参数。本组件已写进 AGENTS 易错点。→ 交控制者。
- **组件测试的固定幂等键**（项目侧，所有 Go 组件）：建议审查时 grep `IdempotencyKey: "` 字面量。→ 交控制者。
- **mdm/customer 2.0.0 的同类 4xx 问题**（重复 code、非数字 id、非法 status 值）：建议下一次 customer 改动（2.0.1）时按本组件 eb0428a / 9eaad01 的测试补上。→ 交控制者。
- **mdm/customer AGENTS 的 Build and test 里 `source .env`**：与 component-loop 0.2 冲突，模板该改。→ 交控制者。

## 小结

- 完成：组件仓库提交（components/mdm/product，均未推送、未打 tag）：
  - e5c7055 chore: 迁移到 brickKit v1 骨架与 2.0.0 清单（机械步骤）
  - 102f7fb test: 写路径测试的幂等键与 sku 改成每次运行唯一（测试错在哪写在提交信息里）
  - e8c08ee refactor(repo): repo.go 按读 / 写 / 换算拆成四个文件，抽出写命令共用的事务步骤
  - 0f14c9c fix: 非法列表游标返回 400 而不是 500
  - 504a314 fix: REST GET /products 读取契约里已有的 created_after / created_before
  - 9eaad01 fix: SetStatus 拒绝非法状态值，gRPC 漏填 status 不再当成 ACTIVE
  - eb0428a fix: 重复 sku、不存在的单位 / 分类 / 产品 id 返回 4xx 而不是 500
  - a49e77b fix: 数量与标准成本只接受十进制字符串，换算接口不合法的 id 返回 404
  - b6219b8 feat(contract): List 新增关键字 q（gRPC ListRequest.q = 6、REST GET /products?q=）
  - 546596f feat: 产品列表支持关键字 q（sku / name，前缀优先，游标分页；REST 与 gRPC 都接）
  - 1c8d276 feat: POST /products/{id}/status 改绑新权限键 mdm.product.set_status
  - 06df9a6 docs(code): 代码与契约注释改写成原因本身，不再引用归档文档与历史
  - 62fa2f7 test: 测试注释改写成测的是什么、为什么，不再引用归档文档
  - 3695377 chore: Makefile / Dockerfile / 种子脚本按 v1 改；种子数据加关键字搜索样例
  - 7ee4fd9 docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
- 契约包：**需要 tag `gen/mdm/product/v1.1.0`**（根 go.mod 已 require v1.1.0 + 本地 replace；ship 第 2 步）。
- 父仓库待控制者提交（脚本写出，未提交）：`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/mdm-product.yaml`、`AGENTS.md`（组件表本组件一行）、`registry/permissions.tsv`（`mdm.product.set_status` 一行）、`components/mdm/product`（指针，ship 之后）、本记录。共享文件里同时有 W1 别的工作线（authz / notification / workflow）的行，按路径提交时要按块区分。`manifest-overrides.yaml` 未改。
- `history_allow`：无。
- 需要控制者裁定的：无硬卡点。可以讨论的：mdm/customer 2.0.0 的同类 4xx 问题是否在 2.0.1 补；SDK 加组件测试用的权限判定辅助；`BatchGetRouted` 的 `SELECT *`。
- 遗留到后续：带 token 的受保护路由 200 与 set_status 403 的真机复核（T25）；categories / units 没有管理接口（design.md 未决问题）。
- 检查点：mdm/product 2.0.0，tag `2.0.0` / `v2.0.0` / `gen/mdm/product/v1.1.0` 待 `make ship`，组件 HEAD 7ee4fd9。

## ship 前修正（控制者审查 task-9-review.md）

- BRICKKIT.md / BRICKKIT.zh.md 第 26 行"no longer / 不再能"是历史说法，改写成现状（启用 / 停用要求单独的键 `mdm.product.set_status`，`mdm.product.edit` 只管编辑）。组件仓库提交 51cff19，HEAD 51cff19（`main...origin/main [ahead 16]`）。
- 发布说明（scratch，不提交）：`standard_cost` 不再写成 ConvertQuantity 的参数（改成"`Create` / `Update` 的 `standard_cost` 同样只接受非负十进制字符串"）；"原来是 409"与"此前都是 500"拆成两条，不再自相矛盾。
- 复核：`component-check.sh mdm/product` → `✅ component-check mdm/product：10 项全部 PASS`、exit 0；`make docs-check ID=mdm/product` → `📋 Checked 3 files: 0 with errors, 0 warnings`、exit 0。只改了文档，镜像二进制不受影响（ship 前需不需要 FORCE_BUILD 重跑 verify 由控制者定；镜像里只有 component.yaml 与二进制，不含 BRICKKIT.md）。
