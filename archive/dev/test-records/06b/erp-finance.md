# 06b erp/finance：过程记录

## 概况

- 日期：2026-10-02（06:38 开工，07:22 交接，墙钟约 45 分钟；其中约 10 分钟在等项目锁）
- brickKit：`env.sh` → `ℹ️ env.sh：BrickKit CLI v1.1.0（/home/zhijie/.local/bin/brickkit）；buf 在；TEST_PG_DSN 由 .env 的 POSTGRES_PASSWORD 在 eval 时拼出（URL 编码，不打印值），TEST_NATS_URL=nats://localhost:4222`
- SDK：be-sdk-go v0.4.0（`git -C tools/be-sdk-go describe --tags --abbrev=0` → `v0.4.0`）
- 基础资源：`make check` → `✓ 全部基础资源就绪`（postgres、nats、traefik、casdoor、rustfs healthy）
- 组件与版本：erp/finance v1.0.14 → 2.0.0；组件仓库 20 个提交 18fb80c … （R53 后到 HEAD）（未推送、未打 tag）；tag 待控制者 `make ship`：`2.0.0`、`v2.0.0`；契约包**不需要新 tag**（仍 `gen/erp/finance/v1.0.10`）
- 交接：见"小结"

## erp/finance

### 目标

按 component-loop 重建到 2.0.0；补 frontend-needs §2.5：`GET /ar-ledger/summary`、`ARLedgerEntry.customer_name` / `outstanding`、`GET /entries` 的 `source_doc_id` / `source_doc_type`；重构重点：路由权限键、跨组件写入的幂等认领方式。

### 环境

brickKit v1.1.0；目标 docker；拓扑：独立组件；本组件无依赖；项目里同时有其他 W1 线已接入的组件（infra/authz 已在、infra/iam-casdoor 不在）；本地模式开始与结束都是 off（`Local mode: off` / `deploy.local.yaml: none`）。

### 步骤

**C1 前置（06:38）**

- `git -C $C status -sb` → `## main...origin/main`，无文件行；最后一个 1.x tag `v1.0.14`；契约包最新 `gen/erp/finance/v1.0.10`。
- `command -v protoc-gen-go protoc-gen-go-grpc` → 都在 `/home/zhijie/go/bin/`。
- 无依赖，"上游已发布"不适用。
- 1.6 演示库表属主：空（T5 重置过）。迁移之后：`erp_finance_rw|42`。
- 测试库 `brickkit_test_db`：`erp_finance_rw|3`、`postgres|31`（1.x 时代以 postgres 跑过迁移）。本 Task 要加 `ALTER TABLE` / `DROP INDEX` 类迁移，以 `erp_finance_rw` 跑会 `must be owner`，见"卡点与绕过" 1。
- 1.5 读了旧 AGENTS / README / docs/手册.md、`archive/pre-v1/docs/dev/design/erp-finance.md`、四个清单 / 构建文件、frontend-needs §2.5、样板 mdm/customer 的 Makefile / Dockerfile / 八份文档、试点记录与 T8 裁定。

**C2 骨架（06:42，<1 秒）**：`docs-skel.sh` → `✅ docs-skel：改动 8 个文件，跳过 0 个`；`git rm docs/手册.md`；`brickkit skills update` → `Wrote 1: .claude/skills/brickkit-component/SKILL.md`；`AGENTS.md:27: <!-- brickkit:managed:begin lang=en -->`。

**C3 清单（06:42，约 1 秒）**

- `--write`：`assembly.yaml 删除的键：['version', 'asset', 'shell']`；`去掉 4 行归档引用注释`（data_scopes 上方 legal_entity 的理由，结论已写进 docs/design.md 的 Data scopes）；`旧键 → 新键：{'pgSchema': 'PG_SCHEMA', 'iamJwksUrl': 'IAM_JWKS_URL', 'authzBundleUrl': 'AUTHZ_BUNDLE_URL', 'otelBaseUrl': 'OTEL_BASE_URL'}`；`backend/module/module.go:27: "pgSchema" → "PG_SCHEMA"`。
- `--check` 全部"无"，`✅ --check 全部为"无"`，`exit=0`。
- `brickkit lint erp/finance`：第一行 `🔎 Only erp/finance is checked …`，`✅ components/erp/finance/component.yaml`，0 个 `MANIFEST_INVALID`，只有 `DOC_*` 警告。
- 无新权限键，没跑 `make permissions`。

**C4 代码（06:42–07:10）**

- `go-v2.sh --sdk v0.4.0`（5 秒）→ `exit=0`，14 条判据全部 PASS，`📌 第 8.3 步：不需要打契约包 tag（本地 gen/erp/finance 与 gen/erp/finance/v1.0.10 一致）`。`go: upgraded go 1.25.0 => 1.25.11`。读 diff：`cmd/migrate/main.go` 一行化，`module.go` 删 `Migrations:` 与 migrations import，`role := schema + "_rw"` 保留。提交 18fb80c。
- 基线：`make test-db-init ID=erp/finance` → `✓ 迁移幂等`（version 4）；`go test ./... -race` 40 PASS、0 SKIP。
- Makefile 照 mdm/customer 模板（ID/REPO、角色名、dag-check 说明、seed / db-reset）；`grep -i 'customer\|客户' Makefile` 为空。Dockerfile 照模板（删 `COPY migrations`）。`migrations/embed.go` 注释改写。`make check-version dag-check contract-check import-scan module-check` 全 ✓，`buf breaking --against '.git#tag=v1.0.14'`。提交 bd48760。
- 测试库重置本组件 schema（卡点 1）后 34 张表全部 `erp_finance_rw`。
- 红绿循环（每个一个提交，红的原文在提交信息里）：
  1. 10f0bad 非法游标 500 → 400。红：`非法 cursor 应该是 ErrInvalidArgument，实际：非法 cursor：illegal base64 data at input byte 0`。
  2. d896593 REST `/entries`、`/ar-ledger` 不读 `created_after`/`created_before`（openapi 早已声明，gRPC 读）。红：`给了 created_after / created_before，200 天前的凭证应该在结果里`、`created_after 不是 RFC 3339 时间应返回 400，实际 200`。
  3. 2a46051 金额经 float64。红：`金额 "NaN" 应该被拒绝（ErrInvalidArgument），实际：<nil>`（NaN 真的过账了）、`"1e2"/"1.005"/"+1.00"/"1."/".5"` 实际 `<nil>`、`"Inf"` 与 17 位整数部分是 `numeric field overflow`（500）、`借方比贷方多一分应该报 ErrUnbalancedEntry，实际：<nil>`、`已用额度比额度多一分，期望 1 条 finance.credit.rejected.v1，实际 0 条`。`0.10 + 0.20 = 0.30` 修复前后都绿。
  4. 9abc95c post_no 全局唯一（旧 C17 缺口，在本 Task 的多法人测试里真的触发）。红：`法人 le-a-… 第一次过账失败：… duplicate key value violates unique constraint "finance_journal_entries_post_no_uniq"`。迁移 005 改为 `(legal_entity_id, post_no)`。
  5. 163bdb3 自动凭证"先 SELECT 再 INSERT"认领。红：5 个并发里 4 个 `duplicate key value violates unique constraint "finance_journal_entries_source_uniq"`。改为凭证头 `INSERT … ON CONFLICT … WHERE source_component != '' DO NOTHING` 认领、认领后再分配 post_no。测试辅助函数 `findExistingBySourceForTest` 原来调用随之删掉的生产函数，改为直接查表（断言不变，写在提交信息里）。
  6. 8bce4d1 同一张凭证可被冲销多次。红：`第二次冲销应该报 ErrEntryAlreadyReversed，实际：<nil>`、`并发冲销同一张凭证应该恰好成功一次，实际 4 次`。锁原凭证头 + 查已有冲销；迁移 006 索引（后在 1e003be 改为通用的 `(source_doc_id, source_doc_type)`）。
  7. 1e003be `GET /entries` 加 `source_doc_id`/`source_doc_type`。红：`实际 200 张` / `实际 50 张`。
  8. e26511e 应收行加 `customer_name`/`outstanding`/`due_date`（迁移 007）。红：三个字段空串、`column "name" does not exist`、响应缺字段。`TestListARLedger_看不到别的法人的应收`（两个法人都有真实数据）实现前后都绿。`UpsertCustomerCreditSnapshotTx` 改名 `UpsertCustomerSnapshotTx` 并多收 name，repo_test.go 一处调用补空串参数（断言不变）。
  9. 6644d34 `GET /ar-ledger/summary`。红（空实现）：四条全 FAIL；绿：精度 `0.30`、账龄边界第 30/31、60/61、90/91 天 + 部分核销（`{3.00 12.00 48.00 63.50}`、合计 `127.00 / 0.50 / 126.50`）、未到期进 d0_30、两个法人隔离（只授权 A 只看到 `10.00`、A+B `910.00`、无授权全 `0.00`）、customer 过滤。REST 测试与 handler 一起写。
  10. d47ba5f outbox schema 写死 `erp_finance`（`PG_SCHEMA` 配了别的值事件发不出去）。红：`事件应该写进 erp_finance_cfgtest.event_outbox（实际 0 条），不该写进 erp_finance（实际 1 条）`。
- 其他提交：8a6351f openapi 补 legal-entity-access 三条路径；8e4af48 entry.go（539 行）拆成 entry / manual / entry_read（纯移动）；65e255f 代码与契约说明注释去历史；a7cb642 测试注释去历史（除注释外只有一处 import 行尾注释）；11c29e6 种子脚本。
- 4.10：没有超过 600 行的文件、超过 150 行的函数（拆分后 entry.go 207 行）。
- 4.12：`make module-check` → `✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`。
- 重构重点核对：12 条 REST 路由（加新的 summary 共 13 条）全部 `besdk.GET/POST/DELETE(g, path, key, h)`；`make gates` 的 bare-route-scan 0 条违规。期间状态机三条路由 `erp.finance.close`、过账/冲销 `erp.finance.post`。跨组件写入：五个写命令早就是 `INSERT … ON CONFLICT DO NOTHING` claim-first；事件驱动自动凭证原来是先 SELECT 后 INSERT（由唯一索引兜底、并发时报错），已改（循环 5）。
- 4.16 最终：测试库再重置一次 schema（006 改过内容）后 `make test-db-init ID=erp/finance` → version 7 两次 `outcome ok`，`✓ 迁移幂等`。
- 4.17：`make test` exit 0；`go test ./... -race -count=1 -v` 65 个 PASS、`--- SKIP` 0。
- 4.18（C4 末）`component-check.sh`：9 项 PASS、第 10 项（占位符）FAIL（预期，文档骨架）。

**C5 文档（07:10–07:15）**：八份文件写满。`component-check.sh` → `✅ component-check erp/finance：10 项全部 PASS`；`make docs-boundary` exit 0；`make docs-check ID=erp/finance` → `📋 Checked 2 files: 0 with errors, 0 warnings`。提交 56cc18f。

**C6 版本与门禁（07:15–07:19）**

- `make check-version test contract-check import-scan module-check dag-check` → exit 0：`✓ version=2.0.0…`、5 个包 `ok`、`buf breaking --against '.git#tag=v1.0.14'`、`✓ 无组件间 import`、`✓ 入口签名对…`、`✓ 无依赖，无环`。
- `make test-db-init ID=erp/finance` → `✓ 迁移幂等`；`migrate-manifest.py --check` → `✅`；`go-v2.sh --recheck` → `✅ 判据全部 PASS`，`📌 不需要打契约包 tag`。
- `go list -m all | grep brickKit/erp-finance` 恰好两行：`github.com/brickKit/erp-finance/v2`、`github.com/brickKit/erp-finance/gen/erp/finance v1.0.10 => ./gen/erp/finance`。
- `make gates`（锁内，等 im-dingtalk 的 verify 约 1 分钟）exit 0：import / SystemClient / 裸路由 / 事件破坏性 / data-scope-test / dependency-version 全 0 条违规；service-hostname-scan `0 条错误（1 条警告）`（`infra-iam-casdoor-2-0-0 对应的组件不在 brickkit.yaml 里`，预期）；config-key-scan 0 条违规（frontend/standard 1.x 的 3 条 naming 只警告）；openapi-additive-scan `0 条违规（0 条跳过提示）`；`brickkit up --dry-run` 通过。
- 发布前门禁自查（锁内）：`gate config-key-scan --only erp/finance --strict` → `0 条违规`、exit 0；`gate openapi-additive-scan --only erp/finance` → `0 条违规（0 条跳过提示）`、exit 0。

**C7 接入与真机**

- `make integrate ID=erp/finance`（07:19:57，3 秒，exit 0）：db-init `✓ 建库脚本已执行`；`brickkit add erp/finance@2.0.0 --yes` → 7 行 `🔗 … references the variable of the same name in config/vars.yaml`、`✅ erp/finance@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml`、`✏️ Fill in the required keys …: PG_PASSWORD, PG_USER`；config-fill `写了 3 个键：PG_PASSWORD, PG_USER, PG_SCHEMA`（没有 exit 3）；teardown-sync 同步；`brickkit lint --strict erp/finance` → `0 with errors, 0 warnings`；`up --dry-run` → `✅ erp/finance@2.0.0  starting (top-level)`。`config/erp-finance.yaml`：`PG_USER: erp_finance_rw`、`PG_PASSWORD: ${ERP_FINANCE_DB_PASSWORD}`、`PG_SCHEMA: erp_finance`，其余 `$var:`。AGENTS.md 组件表多一行 `| erp/finance | 2.0.0 | Chart of accounts, … | BRICKKIT.md +zh | https://github.com/brickKit/erp-finance |`。
- 父仓库改动（integrate 第 7 步列出）：`AGENTS.md`、`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/erp-finance.yaml`（本组件）；另有别的工作线的 `config/*.yaml`（erp-inventory、infra-authz、infra-print、infra-workflow、integration-im-dingtalk、mdm-product）与 `registry/permissions.tsv` 的 `+` 行——**全部不是本组件的**：`infra.bff-mobile.notification.view`、`infra.bff-mobile.opportunity.view`、`infra.bff-mobile.task.act`、`mdm.product.set_status`（3.5：记录并告知控制者，未手删）。
- `make verify ID=erp/finance ROUTE=/erp/finance/entries FOCUS=1 SEED=1`（07:20:10–07:21:42，exit 0）：

```
verify erp/finance@2.0.0 汇总（输出目录 $BE_SCRATCH/verify/erp-finance-20261002-072011）
| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build erp/finance | PASS |  | build.log |
| 镜像 erp-finance:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| erp-finance-2-0-0 running (healthy)（容器服务 erp-finance-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| GET /erp/finance/entries 不带 token → 401/503 | PASS | 实际 401 | http.log |
| GET /erp/finance/entries 带 token → 200 | SKIP | infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token |  |
| make -C components/erp/finance seed | PASS |  | seed.log |
| make test-cross ID=erp/finance | PASS |  | test-cross.log |
| focus：宿主机 http://localhost:8087/healthz → 200 | PASS |  | focus.log |
| brickkit up --all --dry-run（清除 focus） | PASS |  | focus-all-dry-run.log |
| brickkit local off | PASS |  | local-off.log |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |
✓ 全部 PASS 或写明原因的 SKIP
```

  - 迁移容器最后一行 `{"msg":"迁移结束","direction":"up","schema":"erp_finance","outcome":"ok","version":7,"dirty":false}`（以 `erp_finance_rw` 登录）；演示库表属主 `erp_finance_rw|42`。
  - 容器日志唯一的 ERROR 是 `Failed to refresh HTTP JWK Set … lookup infra-iam-casdoor-2-0-0 … server misbehaving`（iam 不在项目里，附录 B 预期）。
  - seed.log：`✓ 客户：1 2 3`（取到了 mdm-customer 种子的真实客户与名字）、`✓ 应收：6 行`、`✓ 到期日回填到 0 / 20 / 31 / 45 / 75 / 120 天前；订单 4 部分核销 300.00`、账龄 `16450.50 | 22680.25 | 15420.00 | 7300.00`、`跳过：infra/iam-casdoor 与 infra/authz 没有都加入项目，换不到 JWT`。演示库里 6 行应收的客户名为 `「本地测试」华南电子科技有限公司` 等真实种子名。
  - focus：`focus 用 deploy.local.yaml 的 vars: 把 host.docker.internal 换成 host-gateway IP 172.17.0.1：PG_HOST, NATS_URL, S3_URL`，`erp-finance-2-0-0  listening on port 8087`（与声明端口一致）。
  - 收尾后：`brickkit local status` → `Local mode: off` / `deploy.local.yaml: none`；项目根没有 `deploy.verify.yaml`；`docker ps` 无本项目容器。
- Review Focus 2：本组件没有带默认值的自有键（只有共享键 `PG_SCHEMA` / `PG_PORT` / `OTEL_BASE_URL`）；`PG_SCHEMA` 的读法由 `--check` 与 component-check 4.5 核对；`PG_SCHEMA` 写死的那一处（outbox）由循环 10 修掉并有红绿测试。

**C8 交接（07:22）**：发布说明 `$S/notes-2.0.0.md`（`$S=$BE_SCRATCH/06b/erp-finance`）补了"新增 / 修复"，并在"升级前必须做"手工加了一条（1.x 库的表属主要先转给 `erp_finance_rw`，否则迁移 005–007 `must be owner`）——所以最后一次 `--write` 打印 `⚠️ notes-2.0.0.md 的"## 升级前必须做"一节与重新生成的不同`，`diff` 确认差异只有这一条有意补的行。`git -C $C log --oneline -3`：

```
56cc18f docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
11c29e6 chore: 种子脚本加应收台账样例，人工凭证部分在没有 iam / authz 时跳过
a7cb642 test: 测试注释改写成测的是什么、为什么，不再引用归档文档与历史
```

工作区干净，`## main...origin/main [ahead 18]`。镜像 `erp-finance:2.0.0` 由 verify 从 HEAD 56cc18f 构建，之后组件没有再改。

### 现象

- 符合预期的：三个迁移工具一次通过；SDK 一行迁移入口在测试库、迁移容器里都 `outcome=ok`；`brickkit add` 自动把共享键链到 `$var:`；容器形态与 focus 全部 PASS；不带 token 401；种子经 NATS 走真实消费者生成应收。
- 不符合预期的：测试库里本组件的表属主是 postgres（1.x 遗留），挡住新迁移（卡点 1）；旧代码里一批真实 bug（金额 float、NaN 能过账、post_no 全局唯一、先查后插、可重复冲销、outbox schema 写死、REST 不读时间窗口、游标 500），全部红绿修掉。

### 卡点与绕过

1. **测试库表属主是 postgres。** `brickkit_test_db` 的 `erp_finance` 里 31 张表属 postgres（1.x 用管理账号跑过迁移），本 Task 的迁移 005–007 要 `DROP INDEX` / `ALTER TABLE`，以 `erp_finance_rw` 跑会 `must be owner of table`。演示库是空的（T5 重置过），不受影响。处理：在项目锁内 `DROP SCHEMA erp_finance_archive / erp_finance CASCADE`（只动测试库、只动本组件的 schema），再 `make test-db-init ID=erp/finance` 由 be-ops 重建 schema 与授权、以 `erp_finance_rw` 跑迁移——与 T5 对演示库的处理相同。之后又因为改了未发布的 006 的内容重复一次。别的组件的测试库 schema 同样混有 postgres 属主（mdm_product、erp_inventory、erp_sales、crm_opportunity、infra_authz……），要加 ALTER 类迁移的工作线会撞上同一件事——建议控制者统一裁定（例如 test-db-init 加一个"重置某组件测试 schema"的选项）。发布说明里写明了已有 1.x 数据的库升级前要转表属主。
2. 迁移 005 的 down 在已有"两个法人同号凭证"的数据上会失败（回到全局唯一）——这正是 up 修掉的情形，down 文件注释写明。没有做 down/up 往返实测。
3. 项目锁等待：`make gates` 等 im-dingtalk 的 verify 约 1 分钟；其余命令拿锁顺利。
4. 没有翻 brickKit 源码：全部用 `brickkit docs` / `--help` / 项目文档答到。读了 be-sdk-go 源码（`scope.go`、`events.go`、`outbox.go`、`gin.go`、`standalone.go`）确认 `ScopeOf` 无 Claims 时 panic、Consume 的 inbox 逻辑、`PublishOutbox` 的 schema 参数、gRPC→HTTP 映射——属于项目自己的 SDK，不算 brickKit 知识缺口。

### 控制者消息的处理

- **固定幂等键（mdm/product 线的提醒）**：逐个查了全部测试：`IdempotencyKey` 都来自 `uniqueID(...)`（或 `"pme-" + uniqueID(...)`），事件测试的 `aggregate_id` 都带 `UnixNano`，没有固定键。无需修改。种子脚本的固定幂等键是有意的（重跑幂等）。
- **R49（错误码与契约）**：`contracts/finance.openapi.yaml` 每条路径只声明了 `200`，没有声明任何 409 / 400；没有"契约承诺 409 而代码回别的"的不一致。新增的 `ErrEntryAlreadyReversed` 与同类的 `ErrEntryNotPosted`、`ErrPeriodNotOpen` 一样映射 `FailedPrecondition`（400），发布说明写明。

### V 项

- V-13（`brickkit add` 重排注释）：本次 `add` 写了 `brickkit.yaml`、`deploy.yaml`；父仓库这两个文件同时有多条工作线的改动，没有单独拆出本组件引起的注释变化，未做结论。
- 其余 V 项本 Task 不涉及。

### 结论

完成：erp/finance 2.0.0 本地全部门禁绿、真机容器 + focus 全 PASS（带 token 一项 SKIP，待 iam 加入）。遗留：gRPC 面向用户的 rpc 因无用户身份不可用（SDK 工作）；会计年度只到 2026-12-31（已由下方"追加：R53"一节修复）；收款流程、真实成本、归档都未实现（写在 docs/design.md 的未决问题）。

### 反馈候选

- be-sdk-go `handleOne`（events.go）：inbox 用"先 INSERT、撞唯一约束就 `tx.Commit()`"——失败语句之后事务已作废，`Commit` 实际回滚并返回错误，重复投递被记成"消费事件失败"的 ERROR 日志。应改成 `INSERT … ON CONFLICT DO NOTHING` 看影响行数。→ 项目内 SDK 问题（不是 brickKit），交控制者排进 SDK 修复。
- be-sdk-go：gRPC 上没有用户身份透传，`ScopeOf` 在 gRPC 用户路径上 panic（被 recovery 变成 INTERNAL）。所有有数据范围的组件的 gRPC 面向用户 rpc 都不可用。→ SDK 设计问题，交控制者。
- erp/sales（另一条线）：`sumSubtotals`、`computeSubtotal` 也用 `strconv.ParseFloat` 算金额（同本组件修掉的问题），T18 可以顺带看。
- 测试库属主混杂（卡点 1）→ 项目脚本改进候选。

## 小结

- 完成：erp/finance 2.0.0，组件提交 18fb80c..56cc18f（18 个，未推送、未打 tag）；契约包不需要新 tag（`gen/erp/finance/v1.0.10`）；发布说明 `$S/notes-2.0.0.md`。
- 需要控制者做的：`make ship DIR=components/erp/finance NOTES=$S/notes-2.0.0.md`；父仓库按路径提交本组件的 `components/erp/finance`（指针）、`brickkit.yaml` / `deploy.yaml` / `deploy.teardown.yaml` 里本组件的块、`config/erp-finance.yaml`、`AGENTS.md` 组件表那一行、本记录；`registry/permissions.tsv` 的新增行不属于本组件。`manifest-overrides.yaml` 没有改。
- 需要控制者裁定的：测试库表属主（卡点 1）的统一处理；两条 SDK 反馈候选。
- 遗留到后续：FY2027 迁移（2027-01-01 前必须有）、gRPC 用户身份、收款流程。

## 追加：R53（发布前，开 FY2027）

- 红：`TestPostEntryTx_2027年的业务日期记进FY2027的期间` → `2027-01-15 的凭证应该能过账，实际：not found: 业务日期 2027-01-15（法人 default）之后没有任何已建的会计期间`。
- 绿：新迁移 `008_open_fiscal_year_2027`（照 003 的写法：FY2027 一个年度；给每个已有 FY2026 期间的法人建 12 个月度期间；分录行 12 个分区；`ON CONFLICT DO NOTHING` / `IF NOT EXISTS`，没改 005–007）。`make test-db-init ID=erp/finance` → version 8 两次 `outcome ok`、`✓ 迁移幂等`、`✓ brickkit_test_db 就绪`；测试库期间计数 2026 段 557 行、2027 段 612 行（测试造的只有一个 2026-09 期间的法人也得到完整的 2027 年度）。
- 提交：3f957e0（迁移 + 红绿测试）、a9e4700（BRICKKIT"部署前准备"写明每个新会计年度要在 1 月 1 日前开好、第四季度核对；AGENTS 代码地图与易错点；design 未决问题：开年度是业务动作，需要管理接口或提前开好下一年的定时任务 + 第四季度告警）。发布说明"修复"补一条。
- 复核：`component-check` 10 项全部 PASS；`make docs-check ID=erp/finance` `0 with errors, 0 warnings`；`docs-boundary` 0；`make test` exit 0，`-v` 66 PASS、0 FAIL、0 SKIP。
- 真机复验（镜像跟上 HEAD，FORCE_BUILD=1，不带 FOCUS/SEED）：输出目录 `$BE_SCRATCH/verify/erp-finance-20261002-072810/`，全部 PASS（带 token 一项、seed、focus 写明原因 SKIP），迁移容器 `version 8 outcome ok`；收尾后 `Local mode: off`、无 deploy.verify.yaml。
- 控制者告知卡点 1（测试库表属主）由 test-db-init.sh 统一修。

## 追加：发布前修复轮（审查 I-1、I-2、I-3、M-1、M-2）

### 目标

修掉审查 `task-11-review.md` 的两条 pre-ship Important（I-1 NaN 额度、I-2 gRPC 面向用户 rpc panic），顺带修 I-3（R51）与两条只改说明文字的 pre-ship Minor（M-1、M-2）；每条先红后绿，各自一个提交。

### 环境

起点 HEAD `a9e4700`；BrickKit CLI v1.1.0；be-sdk-go v0.4.0；测试库 `brickkit_test_db`（env.sh 拼 TEST_PG_DSN，不打印值）；NATS `nats://localhost:4222`。

### 步骤

1. **I-1 红**（`backend/internal/repo/snapshot_test.go`，`$S/fix-i1-red.log`）：
   ```
   snapshot_test.go:39: 额度 "NaN" 应该按未配置存成 0.00，库里是 "NaN"
   snapshot_test.go:44: 额度 "NaN" 的客户下单应该照常过账，实际：参数不合法: credit_limit 必须是非负、最多两位小数的十进制数："NaN"
   snapshot_test.go:35: 额度 "Infinity"：摘要副本照常写（名字要更新），不该报错：写 customer_credit_snapshots: ERROR: numeric field overflow (SQLSTATE 22003)
   snapshot_test.go:39: 额度 "-5.00" 应该按未配置存成 0.00，库里是 "-5.00"
   snapshot_test.go:44: 额度 "-5.00" 的客户下单应该照常过账，实际：参数不合法: credit_limit 必须是非负、最多两位小数的十进制数："-5.00"
   snapshot_test.go:39: 额度 "1e3" 应该按未配置存成 0.00，库里是 "1000.00"
   snapshot_test.go:66: 库里额度是 NaN 时应该按未配置处理、照常过账，实际：参数不合法: credit_limit 必须是非负、最多两位小数的十进制数："NaN"
   ```
   绿：`UpsertCustomerSnapshotTx` 加 `logger` 参数，进库前 `parseCents`，不合法存 `"0"` 并 Warn（带 customer_id 与原值）；`exceedsLimit` 读到解析不了的额度按未配置处理并 Warn；`postSalesOrderEntryTx` 带 logger（`Repo.PostSalesOrderEntry` 传 nil = 不记）。测试补断言：两处都有点名客户的 `level=WARN`、没有 `level=ERROR`。两条 PASS。提交 `bc42e76`（含 AGENTS 易错点、design、BRICKKIT 中英，发布说明"修复"一条）。
2. **I-2 红**（`backend/internal/grpc/grpc_test.go`，`besdk.ServeExtraPort` 起真 gRPC，不带身份逐个调 8 个 rpc，`$S/fix-i2-red.log`）：8 个都是 `实际 Internal（rpc error: code = Internal desc = internal server error）`，日志 8 行 `level=ERROR msg="gRPC 处理 panic" recovered="besdk.ScopeOf: ctx 里没有 Claims…"`。
   绿：`grpc.go` 新增 `requireUser`（就地 recover `ScopeOf`，SDK 没有不 panic 的 Claims 读取函数），8 个方法开头先调，回 `codes.Unauthenticated`；另加 `TestRequireUser_有Claims时放行`。PASS。BRICKKIT / design / AGENTS 中英的 `INTERNAL` 改成 `UNAUTHENTICATED`；契约不动。提交 `e90b480`。
3. **I-3 红**（`$S/fix-i3-red.log`）：`service/logging_test.go` 五种调用方错误（三个期间操作无授权、借贷不平、冲销 id 不合法）日志里 5 行 `level=ERROR`（`关账失败 … error=无权访问该法人` 等）；`partition_test.go` 已取消的 ctx 调 `Start` → `level=ERROR msg=周分区维护失败 error="context canceled"`。
   绿：service 新增 `logFailure`（`ToStatus` 是 Internal/Unknown 才 Error，其余 Info）；partition `logIfNotShutdown`（`ctx.Err() != nil` 不记）。两条 PASS。提交 `e808135`。
4. **M-1 / M-2**（说明文字）：发布说明"升级前必须做"⚠️ 那一行改成可照做的 `DO` 块（照 `infra/scripts/test-db-init.sh` ①b，范围 `erp_finance` + `erp_finance_archive`，含 `schema_migrations_erp_finance`），删掉"以表属主身份先跑一次迁移"这个备选并写明原因；"新增"与 design 中英补"1.x 升上来的客户 `customer_name` 要等下一次 `mdm.customer.updated.v1`"。提交 `4a2ee5a`（发布说明在 scratch，不进提交）。
5. 复核：
   - `bash dev/phase-06/tools/component-check.sh erp/finance` → `✅ component-check erp/finance：10 项全部 PASS`，exit 0；
   - `make -C $ROOT docs-check ID=erp/finance` → `📋 Checked 3 files: 0 with errors, 0 warnings`，exit 0；
   - `migrate-manifest.py erp/finance --check` → `✅ --check 全部为"无"`；
   - `make check-version test contract-check import-scan module-check dag-check` exit 0：consumer / grpc / http / partition / repo / service 六个包 `ok`；`buf breaking --against '.git#tag=v1.0.14'`；`go test ./... -v` 0 SKIP；
   - `go list -m all | grep brickKit/erp-finance` 两行（`…/v2`、`…/gen/erp/finance v1.0.10 => ./gen/erp/finance`）；
   - `project-lock.sh -- make gates` exit 0，八个 gate 全部 0 条违规（唯一警告是 frontend/standard 的 1.x naming）。
6. `make -C $ROOT verify ID=erp/finance ROUTE=/erp/finance/entries FORCE_BUILD=1` exit 0，输出目录 `$BE_SCRATCH/verify/erp-finance-20261002-125230/`：

   | 检查项 | 结果 | 原因 | 日志 |
   |---|---|---|---|
   | brickkit build erp/finance | PASS |  | build.log |
   | 镜像 erp-finance:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
   | brickkit up -f deploy.verify.yaml | PASS |  | up.log |
   | 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
   | erp-finance-2-0-0 running (healthy)（容器服务 erp-finance-2-0-0） | PASS |  | status.log |
   | GET /healthz → 200 | PASS |  | http.log |
   | GET /erp/finance/entries 不带 token → 401/503 | PASS | 实际 401 | http.log |
   | GET /erp/finance/entries 带 token → 200 | SKIP | infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token |  |
   | make -C <源目录> seed | SKIP | 没设 SEED=1 |  |
   | make test-cross ID=erp/finance | PASS |  | test-cross.log |
   | brickkit up --focus erp/finance | SKIP | 没设 FOCUS=1 |  |
   | brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |

   迁移容器 `"schema":"erp_finance","outcome":"ok","version":8`；镜像创建时间 12:53，晚于最后一个提交；收尾后 `Local mode: off`，没有 deploy.verify.yaml。

### 现象

全部按预期：NaN / Infinity / 负数 / 指数写法的额度不再挡住应收；gRPC 面向用户的 rpc 回 `UNAUTHENTICATED`，服务端没有 panic 日志；调用方错误与关停取消不再记 ERROR。

### 卡点与绕过

无。

### 结论

审查的 I-1、I-2、I-3 与 M-1、M-2 已修，组件 HEAD `4a2ee5a`（比 `a9e4700` 多 4 个提交，未推送、未打 tag）。契约与 `gen/` 未动，仍不需要契约包 tag（`gen/erp/finance/v1.0.10`）。留给 T26：M-3（`component.yaml` description 去掉 "and reconciliation"——要改父仓库的 `manifest-overrides.yaml` 与项目 AGENTS 组件表，本轮不碰父仓库）、M-4–M-9；mdm/customer 2.0.1 修 `validateCreditLimit` 的 NaN 类问题。

### 反馈候选

- be-sdk-go（SDK v0.5 已有项的补充证据）：组件为了不 panic 只能就地 `recover` `besdk.ScopeOf`；SDK 应提供不 panic 的 `ClaimsFrom(ctx) (Claims, bool)`，并在 gRPC 端口上验 JWT。
