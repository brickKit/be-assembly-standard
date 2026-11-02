# 06b infra/notification：过程记录（T14）

## 概况

- 日期：2026-10-02（06:38 开工，07:10 交接，墙钟约 32 分钟；其中约 3 分钟在等项目锁）
- brickKit：`env.sh` → `ℹ️ env.sh：BrickKit CLI v1.1.0（/home/zhijie/.local/bin/brickkit）；buf 在；…`
- SDK：be-sdk-go v0.4.0（`go-v2.sh … --sdk v0.4.0` 判据 `be-sdk-go 是 v0.4.0（实际：v0.4.0）`）
- 基础资源：`make check` → `✓ 全部基础资源就绪`（postgres、nats、traefik、casdoor、rustfs 全部 healthy）
- 组件与版本：infra/notification v1.0.4 → 2.0.0；组件仓库提交 f779101 … d207ce9（9 个，未推送、未打 tag）；tag 待控制者 `make ship`：`gen/infra/notification/v1.0.0`（形态 B 第一次拆出，必须打）、`2.0.0`、`v2.0.0`
- 交接给控制者：见"小结"

## infra/notification

### 目标

按 component-loop 重建到 2.0.0；补 frontend-needs §2.8（`GET /preferences` 改绑 `infra.notification.view`，L2 测试"只有 view 能读不能写"）；形态 B 拆契约包嵌套模块（Review Focus 1）；`IM_TARGET_ADAPTERS` 真机配非默认值从行为上确认生效（Review Focus 2）。

### 环境

brickKit v1.1.0；目标 docker；拓扑：独立组件；项目里在跑的组件：mdm/customer@2.0.0、infra/authz@2.0.0（authz 那条线在本 Task 期间加入），infra/iam-casdoor 尚未加入；本地模式开始与结束都是 off（`Local mode: off` / `deploy.local.yaml: none`）。W1 并行：authz、workflow 等线同时在用项目锁。

### 步骤

**C1 前置（06:38:38–06:39:06）**

- `git -C $C status -sb` → `## main...origin/main`，无文件行；HEAD `e33a7c5` 即 `v1.0.4`（`git describe --tags` → `v1.0.4`）；没有 `gen/*` tag；`find gen -name go.mod` 为空 → 形态 B。
- `command -v protoc-gen-go protoc-gen-go-grpc` → `/home/zhijie/go/bin/protoc-gen-go`、`/home/zhijie/go/bin/protoc-gen-go-grpc`。
- 无依赖，"上游已发布"不适用。
- 1.6 表属主：`select tableowner, count(*) … where schemaname='infra_notification'` → 空（演示库还没有本组件的表）。迁移之后（C7）：`infra_notification_rw|27`。
- 1.5 读了旧 AGENTS / README / docs/手册.md、`archive/pre-v1/docs/dev/design/infra-notification.md`、四个清单 / 构建文件、frontend-needs §2.8、mdm/customer 样板与它的记录、T8 裁定。

**C2 骨架（06:39:06，<1 秒）**

```
✅ docs-skel：改动 8 个文件，跳过 0 个（跳过的是已经填写过的文件）
exit=0
📦 Component repository (has component.yaml, no brickkit.yaml): the brickkit-component skill, plus the component's own AGENTS.md and CLAUDE.md
✅ AI assistant skills updated
   Wrote 1:
     .claude/skills/brickkit-component/SKILL.md
```

九个文件都在，`CLAUDE.md` = `@AGENTS.md`，`AGENTS.md` 末尾有 `<!-- brickkit:managed:begin lang=en -->`，留底在 `$S/old/`（取自 `v1.0.4`）。

**C3 清单（06:39:18，约 1 秒）**

- `migrate-manifest.py --write` → `exit=0`；`--check` 全部"无"、`✅ --check 全部为"无"`、`exit=0`；唯一的 ℹ️：`backend/internal/consumer/consumer.go:37: imTargetAdapters    // channel:im 成员，来自 configSchema 的 imTargetAdapters（module.go），`（注释，随注释清理改掉）。代码改写：`module.go` 的 `pgSchema` → `PG_SCHEMA`、`imTargetAdapters` → `IM_TARGET_ADAPTERS`。
- `assembly-removed-comments.txt`：1 行（`改  # 一维（设计计划 §1）：…` → `# 一维：…`）。
- `brickkit lint infra/notification` → 第一行 `🔎 Only infra/notification is checked (brickkit lint --all checks the whole project)`，`✅ components/infra/notification/component.yaml`，`📋 Checked 2 files: 0 with errors, 66 warnings`（只有 `DOC_PLACEHOLDER` 与 required 键 / 契约文件未提及两类）。
- 无新权限键、无新配置键，没改 overrides，没跑 `make permissions`。

**C4 代码（06:39:33–06:54）**

- `go-v2.sh infra/notification --sdk v0.4.0` → 5.8 秒，`exit=0`。关键输出原文：
  ```
  ▶ 4.0 判形态
    形态 B（gen/ 属于根模块；gen/infra/notification/go.mod 不存在，没有 gen/* tag）
  ▶ 4.1 契约包拆成嵌套模块（只有形态 B）
    ✏️  新建 gen/infra/notification/go.mod（grpc v1.83.2、protobuf v1.36.12，与根模块同版本）
    ✏️  根 go.mod：require github.com/brickKit/infra-notification/gen/infra/notification v1.0.0 + replace => ./gen/infra/notification
    ✏️  Dockerfile：`COPY go.mod go.sum ./` + `go mod download` 改成先 `COPY . .` 再 `go mod download`
  ▶ C-1 检查：根 go.mod 是否 require 了自己的旧路径
    ⏭  没有
  go: upgraded go 1.25.0 => 1.25.11
  go: upgraded github.com/brickKit/be-sdk-go v0.2.4 => v0.4.0
  ✏️  backend/module/module.go：删字段：Migrations: migrations.FS, // 合并态由外壳按拓扑顺序跑（§13.3 铁律五）
  PASS（14 条全部）… go list -m all 里本仓库模块恰好两行：
        │ github.com/brickKit/infra-notification/gen/infra/notification v1.0.0 => ./gen/infra/notification
        │ github.com/brickKit/infra-notification/v2
  📌 第 8.3 步需要打的契约包 tag：gen/infra/notification/v1.0.0（必须等于根 go.mod require 的版本；推送前外壳拉不到）
  ✅ go-v2.sh：判据全部 PASS
  ```
  读 diff：`cmd/migrate/main.go` 一行化、`module.go` 删 `Migrations:` 与 migrations import、`role := schema + "_rw"` 保留；Dockerfile 只改了 `COPY . .` 的顺序。提交 f779101（机械步骤）。
- 4.16 `make test-db-init ID=infra/notification`（3.3 秒）：`{"msg":"迁移结束","direction":"up","schema":"infra_notification","outcome":"ok","version":3,"dirty":false}` ×2、`✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。基线 `go test ./... -race -count=1 -v`：三个包 `ok`，15 个 PASS，0 个 SKIP。
- 4.10 大小：最长的非测试文件 `consumer.go` 369 行、`records.go` 317 行，没有超过 150 行的函数——不拆。
- 4.11 审查发现一个真实 bug（红绿一个提交 1c9a64f）：`PUT /preferences` 请求体不带 `global_channels` 时解出 nil，写进 `NOT NULL` 的 `channels` 列 → 500；分类值为 `null` 时非 critical 分类 500、critical 分类被误判"清空"回 400。红：
  ```
  preferences_test.go:169: 没提交全局通道时期望成功，实际 写通道偏好: 写全局通道偏好: ERROR: null value in column "channels" of relation "notification_preferences" violates not-null constraint (SQLSTATE 23502)
  --- FAIL: TestSetPreferences_没提交全局通道就跟随默认 (0.01s)
  preferences_test.go:191: 分类值为 null 时期望成功，实际 参数不合法: 分类 "workflow_task" 是关键通知，不能清空全部通道
  --- FAIL: TestSetPreferences_分类值为null等于没提交 (0.00s)
  ```
  修法：nil = "没提交"（全局层不落行 → 跟随默认 `[IM]`；分类不落行 → 跟随全局），空数组仍是"全关"、critical 清空仍 400。绿：repo 包 12 个测试全部通过。gRPC 路径不受影响（`grpc.go` 总是构造非 nil 切片，空列表 = 全局全关）。
- 4.11 另一处：`pgerr.go` 的 `isUniqueViolation` 全仓库没有调用方（`command_idempotency` 删表后的遗留）→ 删掉，单独一个提交 1722465。
- 4.11 看过但不改：`repo.ListRecords` 在 `AdminView=false` 且 `RecipientSub` 为空时不加过滤（形式上的 fail-open）；但 REST 路径的 `RecipientSub` 恒为 `besdk.ScopeOf(ctx).Owner` = JWT 的 `sub`，SDK 验签时 `sub` 为空直接拒绝（`tools/be-sdk-go/jwt.go:60-62`：`token 缺少 sub`），走不到。只记为加固候选，不改业务代码。
- 4.12 合并安全：`make module-check` → `✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`。
- 4.13–4.15 §2.8 改绑（红绿一个提交 1ba1a55）：新增 `backend/internal/http/http_test.go`——本地起 JWKS（测试自己生成的 RSA 公钥）与 bundle 两个 httptest 服务器，`besdk.InitShellAuthz` 装一份权限判定，签真 RS256 token，经真实 `besdk` 权限中间件打四条路由（viewer 角色只有 view，editor 角色有 view + edit）。红（只有一条 FAIL，其余五条改绑前后都过）：
  ```
  http_test.go:165: view 读偏好：GET /infra/notification/preferences 期望 200，实际 403（{"error":"无权限"}）
  --- FAIL: TestRoutes_只有view的用户能读偏好不能写 (0.18s)
  ```
  改 `http.go` 一行：`besdk.GET(g, "/preferences", "infra.notification.view", …)`。绿：`--- PASS: TestRoutes_只有view的用户能读偏好不能写 (0.11s)`。`go mod tidy` 把 `golang-jwt/jwt/v5` 从 indirect 改成直接依赖（测试用）。契约没有变化（权限键不在 openapi 里，`.proto` 与 `gen/` 未动，`--recheck` 仍 `v1.0.0`）。
- 注释清理：代码一个提交 5391a16（去掉设计书 / 设计计划 / 决策 / 铁律 / 阶段 / Task 编号与"同某组件的既有判据"，换成原因本身；只改注释，`go build` / `go vet` 通过）；测试注释单独一个提交 2daf150（断言一处未动；除注释外只有一条 `t.Fatal` 文案与一个 import 行尾注释）；契约说明文字一个提交 cee8e09（openapi 的 description 与 events.json 的 note，结构未动；PUT 的说明补上 null 语义；`.proto` 按 R41 不动）。
- 4.7 Makefile / Dockerfile：照抄 mdm/customer，改 `ID` / `REPO`、`migrate-idempotent` 注释的角色与 schema、`dag-check` 的说明与失败文案；本组件没有种子脚本，删掉 `seed` / `seed-clean` 目标；Dockerfile 改契约包路径注释与 `EXPOSE 8202 9202`。`grep -n -i 'customer\|客户\|mdm' Makefile Dockerfile` 为空。提交 1bd5c24。
- 4.18 `component-check.sh`（C4 末）：第 1–9 项 PASS，第 10 项（占位符）FAIL（文档还是骨架，预期）。

**C5 文档（06:46–06:54）**

八份文件写满。`docs/design.md` 从归档设计文档只提取结论（边界、偏好两层模型、`ACCEPTED` 中间态、族级 subject 与 `target_adapters`、dispatch 版本 = attempt、为什么没有 `Notify`、为什么没有依赖、3 个月归档窗口、超过五条来源事件时改通用意图事件、到达策略是 Fork 点不是槽位族），加上本 Task 的新设计（`GET /preferences` 绑 view 的理由、PUT 的 null 语义）和 `assembly-removed-comments.txt` 里那条（一维 owner 不可省）；未决问题里写明归档还没实现、没手机号时的处理、`ACCEPTED` 停留没有告警、已读未读（frontend-needs §2.8 的可选项）。
`assembly.yaml` 的 `data_scopes` 上方注释还有一句"（导读第 22 条：省略 data_scopes 会被 be-ops 当场拦下）"——`HIST_RE` 不认"导读"，脚本没清；手工删掉（它引用的是已不存在的旧导读编号）。**之后再跑 `migrate-manifest.py --write` 会被手改保护拒绝（exit 3）**，需要先读 diff 再 `--force`；`--check` 照常 `exit=0`。
核对：`component-check.sh` → `✅ component-check infra/notification：10 项全部 PASS`、`exit=0`；`make docs-boundary` 静默通过；`make docs-check ID=infra/notification` → `✅ components/infra/notification/component.yaml`、`✅ components/infra/notification/ (docs)`、`📋 Checked 2 files: 0 with errors, 0 warnings`。提交 d207ce9。

**C6 版本与门禁（06:55）**

- `make check-version test contract-check import-scan module-check dag-check` → `exit=0`：`✓ version=2.0.0（go.mod 主版本一致；…）`、四个测试包 `ok`、`buf breaking --against '.git#tag=v1.0.4'`（是 tag，不是 `branch=main`）、`✓ 无组件间 import`、`✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`、`✓ 无依赖，无环`。
- `make test-db-init ID=infra/notification` → `✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。
- `go-v2.sh --recheck` → `exit=0`，`📌 第 8.3 步需要打的契约包 tag：gen/infra/notification/v1.0.0`、`✅ go-v2.sh：判据全部 PASS`。
- 最终测试：18 个 PASS、`grep -c -- '--- SKIP'` → `0`。
- `project-lock.sh -- make gates` → `exit=0`，原文：
  ```
  ✓ 铁律六 import 扫描：0 条违规
  ✓ SystemClient 误用扫描：0 条违规
  ✓ 裸路由/裸 resolver 扫描：0 条违规
  ✓ 事件契约破坏性变更扫描：0 条违规
  ✓ data-scope-test-scan：0 条违规
  ✓ dependency-version-scan：0 条违规
  ⚠ config/vars.yaml:23：infra-iam-casdoor-2-0-0 对应的组件不在 brickkit.yaml 里，无法核对版本（还没装上它时是预期状态）
  ✓ service-hostname-scan：0 条错误（1 条警告）
  ✓ config-key-scan：0 条违规（另有 5 个 1.x 组件的 31 条 naming 违规只警告，--strict 判红；…）
  ✓ openapi-additive-scan：0 条违规（0 条跳过提示）
  ```
  本组件零违规；警告都是别的组件（crm/opportunity、erp/sales、frontend/standard、infra/bff-mobile、infra/iam-casdoor 还在 1.x）或 iam 还没加入项目。
- 发布前门禁自查（锁内）：`gate config-key-scan --only infra/notification --strict` → `✓ … 0 条违规`、`cks=0`；`gate openapi-additive-scan --only infra/notification` → `✓ … 0 条违规（0 条跳过提示）`、`oas=0`。

**C7 接入与真机**

- `make integrate ID=infra/notification`（06:55:39–06:55:41，`exit=0`）：`✓ .env 里的数据库密码已齐全，无需补充`；`brickkit add infra/notification@2.0.0 --yes` → 7 行 `🔗 … references the variable of the same name in config/vars.yaml (--yes)`、`✅ infra/notification@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml`、`✏️ Fill in the required keys in config/infra-notification.yaml: PG_PASSWORD, PG_USER`；`config-fill.py` → `写了 3 个键：PG_PASSWORD, PG_USER, PG_SCHEMA`（没有 exit 3）；`✓ deploy.teardown.yaml 已从 deploy.yaml 同步`；`brickkit lint --strict infra/notification` → `✅ infra/notification: configuration (config/ ↔ configSchema)`、`📋 Checked 3 files: 0 with errors, 0 warnings`；`up --dry-run` → `✅ infra/notification@2.0.0  starting (top-level)`。生成的 compose 里 `PG_USER=infra_notification_rw`、`PG_SCHEMA=infra_notification`、`IM_TARGET_ADAPTERS=dingtalk`（键保持注释时注入的是组件默认值）、两个 URL 是成员服务名、`extra_hosts: host.docker.internal:host-gateway`。AGENTS.md 组件表多一行 `| infra/notification | 2.0.0 | Takes notification intents … | BRICKKIT.md +zh | https://github.com/brickKit/infra-notification |`。
- `make verify ID=infra/notification ROUTE=/infra/notification/notifications FOCUS=1 SEED=1`（06:56:25–06:58:09，`exit=0`，输出目录 `$BE_SCRATCH/verify/infra-notification-20261002-065654`）：

```
| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build infra/notification | PASS |  | build.log |
| 镜像 infra-notification:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| infra-notification-2-0-0 running (healthy)（容器服务 infra-notification-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| GET /infra/notification/notifications 不带 token → 401/503 | PASS | 实际 401 | http.log |
| GET /infra/notification/notifications 带 token → 200 | SKIP | infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token |  |
| make -C components/infra/notification seed | SKIP | components/infra/notification/Makefile 没有 seed 目标 |  |
| make test-cross ID=infra/notification | PASS |  | test-cross.log |
| focus：宿主机 http://localhost:8202/healthz → 200 | PASS |  | focus.log |
| brickkit up --all --dry-run（清除 focus） | PASS |  | focus-all-dry-run.log |
| brickkit local off | PASS |  | local-off.log |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |
✓ 全部 PASS 或写明原因的 SKIP
```

  迁移容器日志最后一行 `{"level":"INFO","msg":"迁移结束","direction":"up","schema":"infra_notification","outcome":"ok","version":3,"dirty":false}`；build.log `✅ Built infra/notification@2.0.0 → infra-notification:2.0.0`（镜像 06:57:40 构建，晚于 HEAD d207ce9 的 06:55:00，此后组件没有任何提交）；容器日志没有 `"level":"ERROR"` 的 JSON 行，只有 keyfunc 的一行 `ERROR Failed to refresh HTTP JWK Set … lookup infra-iam-casdoor-2-0-0 … server misbehaving`（iam 还没加入项目，附录 B 预期）；focus：`focus 用 deploy.local.yaml 的 vars: 把 host.docker.internal 换成 host-gateway IP 172.17.0.1：PG_HOST, NATS_URL, S3_URL`、`infra-notification-2-0-0  listening on port 8202`。SEED SKIP 的理由：通知记录只由事件产生，本组件没有种子脚本。
- **Review Focus 2（`IM_TARGET_ADAPTERS` 配非默认值）**：`config-fill.py --set 'IM_TARGET_ADAPTERS=wecom'`（锁内）→ `IM_TARGET_ADAPTERS: wecom  # string`。第一次在 `KEEP=1` 留下的容器上做时，容器在我拿到下一把锁之前已经被别的工作线的 verify 收尾 `brickkit down` 掉了（`Error response from daemon: No such container: brickkit-be-assembly-standard-infra-notification-2-0-0-1`，那两条事件没人消费，丢了，库里没有留下任何东西）——见"卡点与绕过" 1。改成一整段在**同一把锁**里跑（`$S/rf2.sh`：`make verify … KEEP=1`（锁可重入）→ 发事件 → 查库 → `brickkit down -f deploy.verify.yaml` → 删 `deploy.verify.yaml` → 恢复 config）（07:00:36 开始等锁，07:03:44 结束）：
  ```
  verify exit=0（汇总表同上，除 seed / focus / down 三行 SKIP：没设 SEED / FOCUS、KEEP=1）
  printenv IM_TARGET_ADAPTERS = [wecom]
  published infra.iam.user.created.v1 verify-t14-1790917419 1
  published infra.workflow.task.created.v1 task-verify-t14-1790917419 1
  -- user_contacts
  verify-t14-1790917419|13800000000|f|1
  -- notification_records
  1|verify-t14-1790917419|workflow_task|IM|PENDING|T14 IM_TARGET_ADAPTERS 验证
  -- event_outbox
  infra.notification.dispatch.im.v1|1|1|["wecom"]|1|PUBLISHED
  down exit=0
  15:# IM_TARGET_ADAPTERS: dingtalk  # string (default)
  Local mode: off
  无本项目容器
  ```
  结论：配置值从注入（`printenv`）到行为（dispatch 事件的 `target_adapters` 是 `["wecom"]`，不是默认的 `["dingtalk"]`）都生效；版本 = attempt = 1；记录停在 `PENDING`（没有名叫 wecom 的适配器，符合 BRICKKIT 的说明）。用 `wecom` 而不是 brief 举例的空串：空串时 brickKit 是注入 `""` 还是退回 schema 默认值我没有核实（component-loop 7.1 第 3 项写的退回规则针对 `$var:` 引用），而组件这边 `StringOr` 对注入的 `""` 会原样返回、得到 `target_adapters: []`——两种结果的含义不同，用一个明确的非默认值判读更干净；`wecom` 也避免了真的 dingtalk 适配器（若别的线正好起着）去调钉钉。事件用 `$S/pubtool`（scratch 里的 30 行 Go 程序，带 be-sdk 的 `X-Aggregate-Id` / `X-Version` / `X-Hop-Count` 头）发到宿主机 NATS。收尾：`diff config-before-rf2.yaml config/infra-notification.yaml` 为空（`config 已原样恢复`）；测试用的行从 `brickkit_db` 删掉（`DELETE 1`、`DELETE 1`、`DELETE 1`、`DELETE 2`：outbox、records、contacts、inbox）。
- `make teardown-sync CHECK=1` → `✓ deploy.teardown.yaml 与 deploy.yaml 一致`；`brickkit local status` → `Local mode: off` / `deploy.local.yaml: none`；项目根没有 `deploy.verify.yaml`。

**C8 交接（07:05）**

- 发布说明 `$S/notes-2.0.0.md`（`$S=$BE_SCRATCH/06b/infra-notification`）：骨架的"升级前必须做"之外**有意补了三行**（契约包拆成嵌套模块与 v1.0.0；只有 edit 没有 view 的角色从此读不到偏好、要补 view；迁移状态表沿用 `schema_migrations_infra_notification`，库里核对过表名），所以它与 `notes-2.0.0.generated.md` 的这一节不同——差异只是这三行。"新增"写 `GET /preferences` 改绑；"修复"写 PUT 的 null。最后一次 `--write` 之后 overrides 没有改过，生成的那一节没有漂移。
- `git -C $C log --oneline -3`：
  ```
  d207ce9 docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
  cee8e09 docs(contracts): openapi 与事件清单的说明文字去掉归档引用，写明 PUT 的 null 语义
  1bd5c24 chore: Makefile / Dockerfile 按 v1 改（照 Go 组件模板）
  ```
  工作区干净，`## main...origin/main [ahead 9]`。最后核对：`go list -m all | grep brickKit/infra-notification` 恰好两行（`…/v2`、`…/gen/infra/notification v1.0.0 => ./gen/infra/notification`）；`migrate-manifest.py --check` `exit=0`。

### 现象

- 符合预期的：形态 B 拆分一次通过，C-1 没有出现；SDK 一行迁移入口在测试库、迁移容器里都 `outcome=ok`，表属主 `infra_notification_rw`；共享键自动链到 `$var:`；容器形态与 focus 全部 PASS；不带 token 401；`IM_TARGET_ADAPTERS` 的配置值真的改变了 dispatch 的 `target_adapters`。
- 不符合预期的：`KEEP=1` 留下的容器在释放锁之后被别的工作线的 verify 收尾一起 down 掉（见卡点 1）；`brickkit add` 这次**没有**重排 `brickkit.yaml` / `deploy.yaml` 的注释（diff 里只有新增的两行组件条目，V-13 见下）。

### 卡点与绕过

1. **并行时 `KEEP=1` 的容器保不住。** `make verify` 释放锁之后，下一个拿到锁的工作线（authz / workflow 的 runtime-check 与 verify）在收尾时 `brickkit down` 了本项目的全部容器，并覆盖了项目根的 `deploy.verify.yaml`。component-loop 7.2 第 7 项与 §4.5 的"在 `KEEP=1` 留下的容器上、锁内跑手工核对"在 W1 多条线并行时不成立：两把锁之间容器就可能没了。绕过：把 `verify KEEP=1` + 手工核对 + `down` 写进一个脚本，用一次 `project-lock.sh -- bash <脚本>` 跑完（锁可重入：持锁时导出 `BE_PROJECT_LOCK_HELD=1`，子进程里的 `make verify` 直接执行）。
2. `component-check.sh` 的 `HIST_RE` 不认"导读第 N 条"：`assembly.yaml` 里那句只能手清，代价是之后的 `--write` 要 `--force`（见 C5）。
3. 为了写权限绑定的 L2 测试，读了 be-sdk-go 源码（`authz.go`、`bundle.go`、`jwt.go`、`shell.go` 的 `InitShellAuthz`），确认判定状态是进程级、只能经 `RunStandalone` / `InitShellAuthz` 装配，以及 bundle 的 wire format；为了写 BRICKKIT 的"NATS 连不上就退出"读了 `standalone.go:89-92`、`events.go` 顶部的范围声明。**没有读 brickKit 仓库源码**，CLI 的问题都由 `--help` 与工具脚本输出答到。

### V 项

- V-13（`brickkit add` 重排注释）：本次 `brickkit add infra/notification@2.0.0 --yes` 之后 `git diff brickkit.yaml deploy.yaml` 只有新增的组件条目（`+  - id: infra/notification` / `+    version: 2.0.0`，以及 authz 那条线加的同形两行），没有注释被挪动或压缩——可能是试点那次已经重排过、文件已是 brickKit 的输出格式。结论：在已被 `add` 写过一次的文件上不再重排。同步到 to-verify：否（控制者合并）。
- V-04（知识缺口）：无（没有读 brickKit 源码）。读 be-sdk-go 源码的两处见卡点 3，属于 SDK 文档缺口，见反馈候选 4。

### 结论

完成。infra/notification 2.0.0 的组件仓库 9 个提交就绪（未推送、未打 tag），`make verify … FOCUS=1 SEED=1` 全部 PASS 或写明原因的 SKIP（带 token 一项待 iam 加入，seed 无目标），Review Focus 1 / 2 都核对过；需要控制者打 `gen/infra/notification/v1.0.0`、`2.0.0`、`v2.0.0`。

### 反馈候选

1. **mdm/customer 的 BRICKKIT"Before you deploy"说"it starts without NATS reachable, and the events wait in the outbox"与 SDK 行为不符**：be-sdk-go `standalone.go:89-92` 在 `nats.Connect` 失败时 `exitf("连接 NATS 失败")`，进程退出（`nats.Connect` 没有 `RetryOnFailedConnect`）。本组件的 BRICKKIT 按实际行为写的。→ 直接交控制者（已发布组件的文档事实错误，下一次 mdm/customer 改版时改；或者 SDK 改成连不上也启动——那是 SDK 的决定）。
2. **`KEEP=1` 与并行工作线**（项目工具）：建议 `verify-component.sh` 支持 `RUN=<脚本>`（在 KEEP 的容器上、同一把锁里跑完再收尾），或在 component-loop 7.2 / §4.5 写明"手工核对与 verify 写进同一次 `project-lock.sh` 调用"。→ 直接交控制者。
3. **模板 AGENTS.md 的"Build and test"写着 `set -a; . ../../../.env; set +a`**，与 component-loop 0.2"不在 shell 里 source `.env`"冲突（`.env` 是 Compose 语法，含多行 PEM）。本组件改成只写 `TEST_PG_DSN` 的形状与 `make test-db-init`。→ 直接交控制者（mdm/customer 下次改版时一起改）。
4. **权限绑定测试的样板应进 SDK**：每个有 REST 的组件都该测"哪条路由绑哪个键"，现在只能像本组件这样手搭 JWKS + bundle 两个 httptest 服务器、自己签 RS256 token、借用给外壳用的 `besdk.InitShellAuthz`。建议 be-sdk-go 提供测试辅助（例如 `besdktest.Authz(t, roles map[string][]string)` 返回签 token 的函数），并在 README 写明测试里怎么装权限判定。→ 交控制者，进 SDK 反馈（不是 brickKit）。
5. **`HIST_RE` 加上"导读"**（`migrate-manifest.py` 与 `component-check.sh` 共用）：旧注释里还有"导读第 N 条"这类引用，脚本认不出、只能手清，之后 `--write` 撞手改保护。→ 交控制者（一次性工具）。
6. **`repo.ListRecords` 的空 `RecipientSub` 形式上 fail-open**（`AdminView=false` 时不加过滤）：当前走不到（SDK 拒绝空 `sub`），可以在下一次改这个组件时加一行"非管理视图必须有 RecipientSub，否则 ErrInvalidArgument"做纵深防御。→ 记在本组件，低优先级。

## 小结

- 完成：组件仓库提交（components/infra/notification，均未推送）：
  - f779101 chore: 迁移到 brickKit v1 骨架与 2.0.0 清单（机械步骤）
  - 1c9a64f fix: PUT /preferences 不带 global_channels（或分类值为 null）时不再 500
  - 1ba1a55 feat: GET /preferences 改绑 infra.notification.view（读偏好不再要编辑权限）
  - 5391a16 docs(code): 代码注释改写成原因本身，不再引用归档文档、历史与别的组件
  - 1722465 refactor: 删掉没有调用方的 isUniqueViolation（pgerr.go）
  - 2daf150 test: 测试注释改写成测的是什么、为什么，不再引用归档文档与别的组件
  - 1bd5c24 chore: Makefile / Dockerfile 按 v1 改（照 Go 组件模板）
  - cee8e09 docs(contracts): openapi 与事件清单的说明文字去掉归档引用，写明 PUT 的 null 语义
  - d207ce9 docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
- 控制者 `make ship DIR=components/infra/notification NOTES=$S/notes-2.0.0.md`：契约包 tag **`gen/infra/notification/v1.0.0`**（形态 B 第一次拆出，根 `go.mod` require 的就是它），再 `2.0.0`、`v2.0.0`。
- 父仓库待控制者提交（脚本写出，未提交）：`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/infra-notification.yaml`（已恢复成 integrate 写出的样子，`IM_TARGET_ADAPTERS` 保持注释）、`AGENTS.md`（组件表）、`components/infra/notification`（指针，ship 之后）、本记录。共享文件里同时有 infra/authz、infra/workflow 那两条线的改动（`brickkit.yaml` / `deploy*.yaml` / `AGENTS.md` / `config/infra-authz.yaml`、`config/infra-workflow.yaml`），按路径或 `git add -p` 只取本组件的块。
- `registry/permissions.tsv` 里有一条不属于本组件的 `+` 行：`mdm.product.set_status	启用/停用产品	action	mdm/product`（mdm/product 那条线的新键，component-loop 3.5），本 Task 没有新键、没有动它。
- `manifest-overrides.yaml`：本组件那一段没改。`history_allow`：无。
- 检查点：infra/notification 2.0.0，tag 待 `make ship`，组件 HEAD d207ce9，遗留见反馈候选（都不挡发布）。
