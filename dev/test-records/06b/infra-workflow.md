# 06b infra/workflow：过程记录（Task 13）

## 概况

- 日期：2026-10-02（06:38 开工，07:10 交接，墙钟约 32 分钟）
- brickKit：env.sh → `ℹ️ env.sh：BrickKit CLI v1.1.0（/home/zhijie/.local/bin/brickkit）；buf 在；…`
- SDK：be-sdk-go v0.4.0（`git -C tools/be-sdk-go describe --tags --abbrev=0` → `v0.4.0`）
- 基础资源：`make check` → `✓ 全部基础资源就绪`（postgres、nats、traefik、casdoor、rustfs 全部 healthy；network be-net ✓）
- 组件与版本：infra/workflow v1.0.4 → 2.0.0；组件仓库 15 个提交 c6316c9 … aa6be29（未推送、未打 tag）；tag 待控制者 `make ship`：`2.0.0`、`v2.0.0`，**契约包需要新 tag `gen/infra/workflow/v1.0.4`**（只是重新生成，patch）
- 交接给控制者：提交 SHA（见"小结"）、发布说明 `$S/notes-2.0.0.md`（`$S=$BE_SCRATCH/06b/infra-workflow`；最后一次 `--write` 会因为我补进"升级前必须做"的一行打 ⚠️，见 C8）、`make verify` 汇总表与输出目录（见 C7）、父仓库待提交的路径（见"小结"）

## infra/workflow

### 目标

按 component-loop 重建到 2.0.0；frontend-needs §2.9 无新增接口，确认 `GET /infra/workflow/tasks/{id}` 返回 `TaskDetail`（含审批历史）并用 L2 测试钉住；重构重点：超期扫描是否用 `FOR UPDATE SKIP LOCKED` 认领、`Start()` 的后台循环是否并发启动；已知 gen 与 `.proto` 不一致，先 `buf generate` 单独提交、契约包升 patch。

### 环境

brickKit v1.1.0；目标 docker；拓扑：独立组件（go-infra 外壳尚未组装）；无依赖；项目里同时有并行工作线加入的 mdm/customer、infra/authz、infra/notification、mdm/product、integration/im-dingtalk、infra/print、erp/inventory（均 2.0.0，未必已发布）；iam-casdoor 不在项目里。本地模式开始与结束都是 off（`Local mode: off` / `deploy.local.yaml: none`）。

### 步骤

**C1 前置（06:38:44–06:40）**

- `git -C $C status -sb` → `## main...origin/main`，无文件行；`fetch --tags` 后最后一个 1.x tag `v1.0.4`，最新契约包 tag `gen/infra/workflow/v1.0.3`。
- `command -v protoc-gen-go protoc-gen-go-grpc buf brickkit` → `~/go/bin/protoc-gen-go`、`~/go/bin/protoc-gen-go-grpc`、`~/go/bin/buf`、`~/.local/bin/brickkit`。
- 无依赖，"上游已发布"不适用。
- 1.6 表属主：`select tableowner, count(*) from pg_tables where schemaname='infra_workflow' group by 1` → 空（演示库里还没有本组件的表）。迁移之后（C7）：`infra_workflow_rw|13`。
- 1.5 读了旧 AGENTS / README / docs/手册.md、`archive/pre-v1/docs/dev/design/infra-workflow.md`、四个清单 / 构建文件、frontend-needs §2.9 / §2.10、样板 mdm/customer 的 Makefile / Dockerfile / 八份文档、T8 裁定、mdm-customer 记录。

**C2 骨架（06:40:01，<1 秒）**

```
✅ docs-skel：改动 8 个文件，跳过 0 个（跳过的是已经填写过的文件）
exit=0
📦 Component repository (has component.yaml, no brickkit.yaml): the brickkit-component skill, plus the component's own AGENTS.md and CLAUDE.md
✅ AI assistant skills updated
   Wrote 1:
     .claude/skills/brickkit-component/SKILL.md
```

通过：九个文件都在；`CLAUDE.md` 恰好 `@AGENTS.md`；`AGENTS.md` 第 27 行 `<!-- brickkit:managed:begin lang=en -->`；留底在 `$S/old/`（取自 v1.0.4）。

**C3 清单（06:40:12，约 1 秒）**

- `--write`：`assembly.yaml 删除的键：['version', 'asset', 'shell']`；`去掉 3 行归档引用注释`；`旧键 → 新键：{'pgSchema': 'PG_SCHEMA', 'otelBaseUrl': 'OTEL_BASE_URL', 'iamJwksUrl': 'IAM_JWKS_URL', 'authzBundleUrl': 'AUTHZ_BUNDLE_URL'}`；`backend/module/module.go:32: "pgSchema" → "PG_SCHEMA"`；`ℹ️ 代码里还提到旧键名 … module.go:28: otelBaseUrl/iamJwksUrl/authzBundleUrl`（注释，C4 改写时一并清掉）；`exit=0`。
- `--check` 全部"无"，`✅ --check 全部为"无"`，`exit=0`。
- `brickkit lint infra/workflow`：第一行 `🔎 Only infra/workflow is checked (brickkit lint --all checks the whole project)`，`✅ components/infra/workflow/component.yaml`，`📋 Checked 2 files: 0 with errors, 66 warnings`，`MANIFEST_INVALID` 0 处；警告只有 44 条 `a placeholder (TODO)` 与 22 条 "is a required config key, but … does not explain it / listed under artifacts … does not mention it"。
- 无新权限键、无 overrides 增量，没跑 `make permissions`。

**C4 代码（06:40:37–06:56）**

- gen 先行：`buf generate` → `gen/infra/workflow/v1/workflow_grpc.pb.go | 16 ++++++++++++----`，diff 只有 `ListTasks` 的两处注释（客户端、服务端接口各一处）。单独提交 c6316c9。
- `go-v2.sh infra/workflow --sdk v0.4.0 --gen-bump patch` → 4.8 秒，`exit=0`。要点原文：`形态 A（嵌套模块；最新契约包 tag gen/infra/workflow/v1.0.3）`；`本地 gen/infra/workflow 与 gen/infra/workflow/v1.0.3 不一致（契约有变化）→ 下一个 patch v1.0.4（--gen-bump patch）`；`go: upgraded go 1.25.0 => 1.25.11`、`be-sdk-go v0.2.3 → v0.4.0`、`golang-migrate/migrate/v4 v4.19.1 => v4.20.1`；`backend/cmd/migrate/main.go 改成一行`、`module.go：删字段 Migrations: migrations.FS`、`删 import …/v2/migrations`；判据 15 条全部 PASS；`📌 第 8.3 步需要打的契约包 tag：gen/infra/workflow/v1.0.4`；`✅ go-v2.sh：判据全部 PASS`。`ℹ️ 这些非 Go 文件还提到 github.com/brickKit/infra-workflow（不带 /v2）…：component.yaml`——那是 `metadata.repository`，正确。读 diff：`lib/pq` 消失，`role := schema + "_rw"` 保留。机械迁移提交 e2f7553。
- 4.16 `make test-db-init ID=infra/workflow`（3.9 秒）：`{"msg":"迁移结束","direction":"up","schema":"infra_workflow","outcome":"ok","version":2,"dirty":false}` ×2、`✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。测试库里本组件原有的迁移状态（version 2）被新入口直接认出：迁移状态表名不变。
- 基线测试：19 条全部 PASS，`--- SKIP` 0。
- **重构重点核对**：超期扫描 `MarkOverdueAndPublish` 早已是 `ORDER BY due_at LIMIT … FOR UPDATE SKIP LOCKED`，同一事务里标记 + 进 outbox；`Start()` 三个循环（outbox pump、超期扫描、分区维护）各自 `go func()` 并发启动、`errCh` 收第一个错误，与 T7 / mdm/customer 的写法一致。两处都不用改；真机运行期核对（见 C7）里超期扫描在容器里实际扫到并发出事件。
- 4.10 重构（提交 e72be1f）：`scanTask` / `scanTaskRows` 合成一个接受 `rowScanner` 的 `scanTask`；`GET /tasks` 与 `GET /admin/tasks` 的两个逐行相同的 handler 合成 `listHandler(list, acceptAssignee)`。另两个小重构：超期批量上限只写一处 `repo.OverdueBatchSize`（SQL 原来写死 `LIMIT 100`、module 另写 `n < 100`；提交 054c46b）；删掉从无调用者的 `mapConstraintErr` 与 `pgerr.go`（提交 ba72dfd）。超长文件 / 函数：无（最长 tasks.go 约 330 行，没有超过 150 行的函数）。测试不改、全绿。
- **钉住 TaskDetail**（提交 5c0fc77）：新增 `backend/internal/http/http_test.go`（真实建库；engine 用 SDK 的 `NewGinEngine`，错误映射走 SDK 中间件；路由组先往 ctx 放 Claims）：`TestGetTask_返回TaskDetail含审批历史`（Task 全部字段 + `actions`，没人处理时是空数组，同意之后 1 条带 actor / action / comment / created_at）、`TestGetTask_范围外403`。两条在现有实现上直接 PASS——确认契约已满足，这是护栏。
- 4.11 发现的真实 bug（各一个红绿提交）：
  - **REST 对已处理的待办再 approve / reject 回 400，契约写的是 409**（提交 d993397）。红：`http_test.go:192: 已同意的待办再同意期望 409，实际 400：map[error:同意待办: 待办已经不是 PENDING 状态]`。原因：`ErrNotPending → FailedPrecondition`，SDK `grpcCodeToHTTPStatus` 把 FailedPrecondition 映射成 400（`tools/be-sdk-go/gin.go`）。修：REST 面 `restStatus` 把这一个错误换成 `codes.Aborted`（SDK 映射 409），gRPC 面不变。
  - **approve / reject 的 200 响应缺 `actions`、`updated_at` 是处理前的值**，契约写的是 `TaskDetail`（提交 ed2bba0）。红：`响应里没有 actions 字段（契约 TaskDetail 带审批历史）：map[… status:APPROVED … updated_at:<与 created_at 相同>]`。修：成功后与 GET 共用 `respondDetail` 重新读一遍。
  - **idempotency_key 被另一个命令用过时，返回别人的结果**（提交 b5c4178）。红：`idempotency_test.go:26: CloseTask 用了 CreateTask 的 key，期望 ErrInvalidArgument，实际 <nil>`（`command_idempotency.command` 列一直存着，从没人读）。修：重放走 `replayResult`，命令不同 → `ErrInvalidArgument`。
- 注释清理：非测试代码 + go.mod + embed.go + 两份契约说明文字一个提交（e66651a；`.proto` 按 R41 不动；迁移 `.sql` 不动）；顺带改正与代码不符的四处旧注释（`Task.InScope` 说列表只用 owner 维、embed.go 说迁移容器读磁盘、`MarkOverdueAndPublish` 说 module 不认识 repo、`OverdueBatchSize` 抢走了函数的文档注释）。核对：`git diff -U0 -- '*.go'` 里非注释行只有两条行尾注释。测试注释单独提交（a81e117；断言未动，非注释改动只有两行 pgx import 的行尾注释与一条 `t.Fatalf` 文案）。途中 `gofmt -l` 报 `service_test.go`：gofmt 会把文档注释里的 `''` 改成 `”`（旧文件里那个怪字符就是这么来的），改写成不含连续两个单引号的说法后 amend 进同一个提交（未推送）。
- 4.7 Makefile / Dockerfile（提交 bbca27e）：照抄 mdm/customer，改 `ID` / `REPO`、`migrate-idempotent` 注释里的角色与 schema、`dag-check` 的说明文字（仍判"必须没有依赖"）；没有种子脚本，删掉 `seed` / `seed-clean`。`grep -n -i 'customer\|客户\|seed' Makefile` → 空。Dockerfile 照抄（删 `COPY migrations`，`EXPOSE 8201 9201`）。`.gitignore` 加 `/migrate`、`/server`。核对：`make check-version dag-check contract-check import-scan module-check` 各一行 ✓，`contract-check` 打印 `buf breaking --against '.git#tag=v1.0.4'`；`env -u TEST_PG_DSN make test` → `✗ 没设 TEST_PG_DSN：…`、`exit=2`。
- 4.12 合并安全：`make module-check` → `✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`。
- 4.18 `component-check.sh`（注释清理前）：第 2 项（Makefile 注释里的 `DATABASE_*`）、第 4 项（历史引用，共 80 余处）、第 10 项（占位符）FAIL；注释清理与 Makefile 之后只剩第 10 项，C5 后十项全 PASS。`history_allow` 没有用到。
- `go-v2.sh --recheck --gen-bump patch` 复核：判据全部 PASS，仍 `v1.0.4`。

**C5 文档（06:51–06:57）**

八份文件写满（结构照 mdm/customer）。`docs/design.md` 从旧设计只取仍成立的结论；旧设计里写了但代码没有的（归档到 `infra_workflow_archive`、`command_idempotency` 90 天清理、outbox 30 天清理）明确写成"预期的保留策略，尚未实现"。`$S/assembly-removed-comments.txt` 的三行（数据范围两维落在被指派人身上、写反的症状）写进了 design 的 Data scopes。核对：`component-check` `✅ 10 项全部 PASS`、`make docs-boundary` exit 0、`make docs-check ID=infra/workflow` → `📋 Checked 2 files: 0 with errors, 0 warnings`。提交 86eb60a。

**C6 版本与门禁（06:57–06:59）**

- `version: 2.0.0`；`module github.com/brickKit/infra-workflow/v2`。
- `make check-version test dag-check contract-check import-scan module-check` → exit 0（四个包 `ok`）。
- `make test-db-init ID=infra/workflow` → `✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。
- `migrate-manifest.py --check` → `✅ --check 全部为"无"`。
- `project-lock.sh -- make gates`（1.3 秒）→ exit 0：import / SystemClient / 裸路由 / 事件破坏性 / data-scope-test / dependency-version 都 `0 条违规`；`service-hostname-scan：0 条错误（1 条警告）`（`config/vars.yaml:23：infra-iam-casdoor-2-0-0 对应的组件不在 brickkit.yaml 里`，预期）；`config-key-scan：0 条违规（另有 5 个 1.x 组件的 31 条 naming 违规只警告…）`——本组件不在其中；`openapi-additive-scan：0 条违规（0 条跳过提示）`；`up --dry-run` 通过。
- ship 前门禁自查（锁内）：`gate config-key-scan --only infra/workflow --strict` → `0 条违规`、rc=0；`gate openapi-additive-scan --only infra/workflow` → `0 条违规（0 条跳过提示）`、rc=0。

**C7 接入与真机**

- `make integrate ID=infra/workflow`（06:58:32，1.9 秒，exit 0）：db-init `✓ .env 里的数据库密码已齐全`、`✓ 建库脚本已执行`；`brickkit add infra/workflow@2.0.0 --yes` → 7 行 `🔗 … references the variable of the same name in config/vars.yaml (--yes)`、`✅ infra/workflow@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml`、`✏️ Fill in the required keys …: PG_PASSWORD, PG_USER`；`config-fill.py` → `写了 3 个键：PG_PASSWORD, PG_USER, PG_SCHEMA`（没有退出码 3，不需要 `--set`）；teardown 同步；`brickkit lint --strict infra/workflow` → `✅ … configuration (config/ ↔ configSchema)`、`0 with errors, 0 warnings`；`up --dry-run` → `✅ infra/workflow@2.0.0 starting (top-level)`。`config/infra-workflow.yaml`：`PG_USER: infra_workflow_rw`、`PG_PASSWORD: ${INFRA_WORKFLOW_DB_PASSWORD}`、`PG_SCHEMA: infra_workflow`，其余 `$var:`。
- 第一次 `make verify ID=infra/workflow ROUTE=/infra/workflow/tasks FOCUS=1 SEED=1`（06:58:44，77 秒，exit 0）：全部 PASS / 写明原因的 SKIP。
- **运行期核对**（verify 之外，锁内一个脚本 `$S/runtime-check.sh`：把 verify 输出目录里的 `deploy.verify.yaml` 拷回项目根、`up`、grpcurl 经项目网络调 gRPC、查库、EXIT 陷阱里 `down` 并删掉副本）。第一次就撞出一个真实 bug：`CreateTask` 不填 `summary_json` → `Code: Internal / Message: 建待办: 写 workflow_tasks: ERROR: invalid input syntax for type json (SQLSTATE 22P02)`（grpc 层把空串转成空字节串，repo 只在 nil 时补 `{}`）。红绿（提交 21daf55）：`summary_test.go:21: summary 为空串时应该照常建待办，实际：…invalid input syntax for type json` 与 `service_test.go:207: summary 不是合法 JSON 应该 ErrInvalidArgument，实际：…`；修后全绿；文档补一句（提交 aa6be29）。
- 第二次 `make verify … FOCUS=1 SEED=1 FORCE_BUILD=1`（07:04:26，65 秒，exit 0；build.log `✅ Built infra/workflow@2.0.0 → infra-workflow:2.0.0`）：

```
verify infra/workflow@2.0.0 汇总（输出目录 $BE_SCRATCH/verify/infra-workflow-20261002-070426）
| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build infra/workflow | PASS |  | build.log |
| 镜像 infra-workflow:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| infra-workflow-2-0-0 running (healthy)（容器服务 infra-workflow-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| GET /infra/workflow/tasks 不带 token → 401/503 | PASS | 实际 401 | http.log |
| GET /infra/workflow/tasks 带 token → 200 | SKIP | infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token |  |
| make -C components/infra/workflow seed | SKIP | components/infra/workflow/Makefile 没有 seed 目标 |  |
| make test-cross ID=infra/workflow | PASS |  | test-cross.log |
| focus：宿主机 http://localhost:8201/healthz → 200 | PASS |  | focus.log |
| brickkit up --all --dry-run（清除 focus） | PASS |  | focus-all-dry-run.log |
| brickkit local off | PASS |  | local-off.log |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |
✓ 全部 PASS 或写明原因的 SKIP
```

  闭包 `infra/authz@2.0.0 infra/workflow@2.0.0`（authz 已在项目里，verify 按规则带上）。迁移容器日志最后一行 `{"msg":"迁移结束","direction":"up","schema":"infra_workflow","outcome":"ok","version":2,"dirty":false}`。test-cross：`（无强依赖，等价于 make test）`，四个包 `ok`。focus：`把 host.docker.internal 换成 host-gateway IP 172.17.0.1：PG_HOST, NATS_URL, S3_URL`，`infra-workflow-2-0-0  listening on port 8201`（与声明端口一致），JWKS / bundle 解析失败是附录 B 的预期。
- 第二次运行期核对（07:05:37，锁内，新镜像）原文摘要：

```
== 1 CreateTask（due_at 在过去） → "id": "1", "status": "TASK_STATUS_PENDING", "summaryJson": "{}", "dueAt": "2020-01-01T00:00:00Z"
== 2 同一个 key 重放 CreateTask → "id": "1"
== 3 CloseTask 用 CreateTask 的 key → Code: InvalidArgument / Message: 关闭待办: 参数不合法: idempotency_key "rt-1790917553-create" 已经被 CreateTask 用过，不能再用于 CloseTask
== 4 GetTaskStatus 按 idempotency_key → "status": "TASK_STATUS_PENDING", "taskId": "1"
== 5 等超期扫描 → 第 12 次轮询（每 5 秒）：overdue_notified_at 已设置；1|PENDING|t
== 6 CloseTask 正确的 key → "status": "TASK_STATUS_RESOLVED"；重放 → RESOLVED；CancelTask → Code: FailedPrecondition / Message: 作废待办: 待办已经不是 PENDING 状态
== 7 outbox → infra.workflow.task.created.v1|PUBLISHED|t、infra.workflow.task.overdue.v1|PUBLISHED|t、infra.workflow.task.completed.v1|PUBLISHED|t
== 8 RestartCount → 0 running；收尾：无本项目容器
```

  结论：超期扫描（按 1 分钟 tick，约 60 秒后扫到）、outbox 推送、分区维护三个循环在真容器里同时在跑；超期不改状态；三处新行为在真容器里成立。演示库 `brickkit_db` 里因此留下一条 `source_component=runtime-check` 的 RESOLVED 待办（id 1，假数据）。
- Review Focus 2（有默认值的自有键）：本组件没有自有键；共享键 `PG_SCHEMA` 默认值与 config 字面量相同，读法 `StringOr("PG_SCHEMA", …)` 已由 `--check` 与 component-check 第 1 项核对。
- 收尾核对：`brickkit local status` → `Local mode: off` / `deploy.local.yaml: none`；项目根没有 `deploy.verify.yaml`；`make teardown-sync CHECK=1` → `✓ deploy.teardown.yaml 与 deploy.yaml 一致`。

**C8 交接（07:07–07:10）**

- 发布说明 `$S/notes-2.0.0.md`：生成的"升级前必须做"六条原样保留，**另补一行**"迁移状态表沿用 `schema_migrations_infra_workflow`，已有库直接升级"（测试库实测新入口认出 version 2）——因此之后再跑 `--write` 会打"升级前必须做"不一致的 ⚠️，差异只有这一行（component-loop 8.1 允许，在此写明）。最后一次 `--write`（补这行之前）：`component.yaml：未改动`、`assembly.yaml：未改动`、`⏭ 发布说明 … 已存在，不覆盖`，没有 ⚠️。"新增 / 修复"两节已补。
- 最终复核（07:07:41）：`component-check` `✅ 10 项全部 PASS`；组件门禁全绿；`--- SKIP` 0；`go list -m all | grep brickKit/infra-workflow` 恰好两行（`…/v2`、`…/gen/infra/workflow v1.0.4 => ./gen/infra/workflow`）；`test-db-init` `✓ 迁移幂等`；`docs-check` `0 with errors, 0 warnings`。
- `make gates` 第二次（07:08）exit 2：十个扫描门禁与第一次相同（全部 ✓），最后的 `brickkit up --dry-run` 报 `CONFIG_INVALID … integration/im-dingtalk@2.0.0 → DINGTALK_AGENT_ID / DINGTALK_APP_KEY / DINGTALK_APP_SECRET`——别的工作线（T15）加入项目后还没填值，与本组件无关，不处理。
- `git -C $C log --oneline -3`：

```
aa6be29 docs: 写明 CreateTask 的 summary_json 可选、不是合法 JSON 时报 INVALID_ARGUMENT
21daf55 fix: CreateTask 不填 summary_json 时照常建待办；不是合法 JSON 时报参数错误
86eb60a docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
```

  工作区干净，`## main...origin/main [ahead 15]`。

**控制者提醒的核对（07:12，mdm/product 工作线发现的"固定幂等键让写路径第二次起不再执行"）**

`grep -n 'IdempotencyKey' backend/internal/*/*_test.go` 共 34 处：每一处要么是 `uniqueID(…)` / `uniqueSuffix(…)` / `unique(…)` 现算，要么是同一测试里由它们赋值的变量（`key`、`closeKey`）。本组件没有唯一的自然键（`source_id` 等不加唯一约束）。唯一一个写死的值是 `GetTaskStatus(ctx, "999999999", "")`，用来查"不存在的 task_id"，与幂等重放无关（待办 ID 来自 identity 序列，测试库远没到这个量级）。结论：本组件不存在这个问题，测试不改。

### 现象

- 符合预期的：机械迁移一次通过；gen 判据按已知情况 FAIL → `buf generate` 单独提交 → `--gen-bump patch` 得 `v1.0.4`；SDK 一行迁移入口在测试库与迁移容器里都 `outcome=ok`，表归 `infra_workflow_rw`；`brickkit add` 自动把共享键链到 `$var:`；不带 token 401；focus 端口与声明一致；超期扫描本来就是 `SKIP LOCKED`、`Start()` 本来就并发。
- 不符合预期的：契约与实现有三处不一致（409、TaskDetail、空 summary），任务自己的旧测试全绿却没覆盖——都是 REST / gRPC 入口层的形状，旧测试只测到 repo / service；第三处只有真容器里调一次 gRPC 才看得出来。gofmt 会改写文档注释里的 `''`。

### 卡点与绕过

1. **项目锁上的并行工作线**：第一次 verify 结束后，项目根出现别的工作线的 `deploy.verify.yaml`（`# infra/authz 运行期核对用的临时副本`）与一个 authz 容器——是 infra-authz 工作线的 `runtime-check.sh` 在锁内运行，不是本 verify 漏收尾（本次 down.log PASS）。我的运行期核对因此写成"一次锁内拷副本 → up → 核对 → EXIT 陷阱 down + 删副本"，不在两次锁之间留状态。
2. 读的资料：component-loop、tools README、T8 裁定、mdm-customer 记录；`brickkit docs` 没有用到（没有 brickKit 层面的疑问）。**没有翻 brickKit 源码**。读了本项目 SDK 的源码 `tools/be-sdk-go/scope.go`（`ScopeOf` 对空 `dept_path` 的定义）、`gin.go`（gRPC 码到 HTTP 码的映射，定位 400 / 409）、`runtime.go`（测试里构造 `Runtime`）——是项目自己的 SDK，不是 brickKit，不算 V-04 知识缺口。

### V 项

- **V-13（`brickkit add` 重排注释）**：本次 `add` 后 `git diff brickkit.yaml` 只有新增的组件行、`deploy.yaml` 只有 `- id: …` 新行，没有看到注释重排（注释在之前的 add 里已经被归一过）。结论：本次未复现。
- V-04：无（没有读 brickKit 源码）。
- V-12、V-06、V-03 不在本 Task。

### 结论

完成。infra/workflow 2.0.0 的组件仓库 15 个提交就绪（未推送、未打 tag）；`make verify … FOCUS=1 FORCE_BUILD=1` 全部 PASS（带 token 一项 SKIP，待 iam 加入 / T25）；契约包需要 `gen/infra/workflow/v1.0.4`。修了四个真实 bug（409、TaskDetail、幂等键跨命令、空 summary），每个都有先红后绿的提交。

### 反馈候选

- **SDK：gRPC 码到 HTTP 码的映射没有 409 的"状态冲突"路径**（项目工具，be-sdk-go）：`FailedPrecondition` → 400 与 grpc-gateway 一致，但多数组件的"已经不是某状态"用的正是 FailedPrecondition，而 REST 契约普遍写 409。本组件在 REST 层单独翻译成 `Aborted`。别的组件（sales 的状态流转、inventory 的预留）大概率有同样的契约不一致。建议：SDK 提供一个 `besdk.ErrConflict` 之类的哨兵或"REST 覆写"钩子，或在 component-loop 加一条核对项"契约写 409 的路径实测状态码"。→ 交控制者（项目内）。
- **service 层把调用方的参数错误 / 状态冲突记成 ERROR 日志**（本组件 `建待办失败`、`关闭待办失败` 对 InvalidArgument / NotPending 也打 ERROR）：R15 外壳失败契约用 `"level":"ERROR"` 判成员是否健康，调用方一次传错参数就会让 `make verify` 的外壳检查"不为空"。本次没改（改日志级别是行为变化，属于 go-infra 外壳 Task 之前要定的规则）。→ 交控制者裁定：要么 service 层按错误类别分级（4xx 记 WARN），要么外壳检查排除带 `component_id` 的业务错误日志。
- **入口层形状的测试缺口是普遍的**：本组件旧测试只覆盖 repo / service，REST 响应形状、状态码、gRPC 入参转换一处没测，三处不一致全在这里。建议后续组件 Task 的 4.11 加一条"契约里每个路径的成功响应形状与每个列出的错误码各有一条 REST 层测试"，以及"gRPC 可选字段不填调一次"。→ 交控制者（component-loop）。
- gofmt 把 Go 文档注释里的 `''` 改写成 `”`（Go 1.19 文档注释规范化）——写 SQL 片段时用 `LIKE '%'` 之类的说法。→ 记录即可。

## 小结

- 完成：组件仓库提交（components/infra/workflow，均未推送）：
  - c6316c9 chore(gen): 按当前 workflow.proto 重新生成 gen/（只有 ListTasks 的注释变化）
  - e2f7553 chore: 迁移到 brickKit v1 骨架与 2.0.0 清单（机械步骤）
  - e72be1f refactor: 合并两份逐行相同的样板（scanTask、两个列表 handler）
  - 5c0fc77 test(http): 钉住 GET /tasks/{id} 返回 TaskDetail（含审批历史）
  - d993397 fix(http): 对已处理的待办再 approve / reject 返回契约写的 409，而不是 400
  - ed2bba0 fix(http): approve / reject 的 200 响应按契约返回 TaskDetail（含审批历史）
  - b5c4178 fix(repo): idempotency_key 被另一个命令用过时报参数错误，不再返回别人的结果
  - 054c46b refactor: 超期扫描的批量上限只写一处（repo.OverdueBatchSize）
  - ba72dfd refactor(repo): 删掉没有任何调用者的 mapConstraintErr 与 pgerr.go
  - e66651a docs(code): 代码与契约说明里的注释改写成原因本身，不再引用归档文档与历史
  - a81e117 test: 测试注释改写成测的是什么、为什么，不再引用归档文档与历史
  - bbca27e chore: Makefile / Dockerfile 按 v1 改（与 mdm/customer 的模板同一套目标）
  - 86eb60a docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
  - 21daf55 fix: CreateTask 不填 summary_json 时照常建待办；不是合法 JSON 时报参数错误
  - aa6be29 docs: 写明 CreateTask 的 summary_json 可选、不是合法 JSON 时报 INVALID_ARGUMENT
- 契约包：**需要** `gen/infra/workflow/v1.0.4`（只是重新生成；根 `go.mod` 已 require 它）。
- 父仓库待控制者提交（脚本写出，未提交）：`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/infra-workflow.yaml`、`AGENTS.md`（组件表一行）、`components/infra/workflow`（指针，ship 之后），以及本记录。共享文件里同时有别的工作线的行（authz、notification、mdm/product、im-dingtalk、print、inventory），按 8.7 只取本组件的块。`registry/permissions.tsv` 里的 `+mdm.product.set_status	启用/停用产品	action	mdm/product` 是 mdm/product 工作线的，不是本组件（本组件没有新权限键）。
- 遗留到后续：带 token 打受保护路由得 200（iam 加入后 / T25）；`.proto` 注释清理（下一次契约变更）；归档与清理任务（未实现，写进 design 的未决问题）。
- 检查点：infra/workflow 2.0.0，tag `2.0.0` / `v2.0.0` / `gen/infra/workflow/v1.0.4` 待 `make ship`，组件 HEAD aa6be29。
