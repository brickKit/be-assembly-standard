# 06b integration/im-dingtalk：过程记录（T15）

## 概况

- 日期：2026-10-02（06:38 开工，07:20 真机收尾，墙钟约 45 分钟，含两次等项目锁）
- brickKit：`brickkit version` → `BrickKit CLI v1.1.0` / `Supported Manifest version: brickkit/v1` / `Supported deploy targets: docker, podman, k8s`
- SDK：be-sdk-go v0.4.0（`git -C tools/be-sdk-go describe --tags --abbrev=0` → `v0.4.0`）
- 基础资源：`make check` → `✓ 全部基础资源就绪`（postgres、nats、traefik、casdoor、rustfs 全部 healthy）
- 组件与版本：integration/im-dingtalk v1.0.5 → 2.0.0；组件仓库 14 个提交 ff3ab78 … da6aa53（未推送、未打 tag，`## main...origin/main [ahead 14]`）；tag 待控制者 `make ship`：`gen/integration/im/v1.0.0`（形态 B 第一次拆出）、`2.0.0`、`v2.0.0`
- 交接给控制者：见"小结"

## integration/im-dingtalk

### 目标

按 component-loop 重建到 2.0.0（无新接口，菜单问题归 06c）；按 Task 的重构重点审查 tokenmgr 并发安全、对外 HTTP 超时、失败重试上限与死信；真机核对"假凭据下投递失败被记录、结果事件发出、不崩溃"。

### 环境

brickKit v1.1.0；目标 docker；拓扑：独立组件（`be/go-infra` 外壳还没组装）；项目里同时有其它工作线加入的 2.0.0 组件（infra/authz、infra/notification、infra/workflow、mdm/product、infra/print、erp/inventory、erp/finance），verify 只起本组件闭包（本组件 + 已在项目里的 infra/authz）。本地模式开始与结束都是 off。

### 步骤

**C1 前置（06:38–06:40）**

- `env.sh` stderr：`ℹ️  env.sh：BrickKit CLI v1.1.0（/home/zhijie/.local/bin/brickkit）；buf 在；TEST_PG_DSN 由 .env 的 POSTGRES_PASSWORD 在 eval 时拼出（URL 编码，不打印值），TEST_NATS_URL=nats://localhost:4222`
- `command -v protoc-gen-go protoc-gen-go-grpc` → `/home/zhijie/go/bin/protoc-gen-go`、`/home/zhijie/go/bin/protoc-gen-go-grpc`
- `git -C $C status -sb` → `## main...origin/main`，无文件行；最后一个 1.x tag `v1.0.5`（就在 HEAD 上）；没有 `gen/*` tag。
- 无依赖，"上游已发布"不适用。
- 1.6 表属主（brickkit_db）：空（演示库里还没有本组件的表）。迁移之后：`integration_im_dingtalk_rw|27`。
- 1.5 读了旧 AGENTS / README / docs/手册.md、`archive/pre-v1/docs/dev/design/integration-im-dingtalk.md`、四个清单 / 构建文件、全部非生成代码与测试；样板 mdm/customer 的 Makefile、Dockerfile、八份文档、记录。

**C2 骨架（06:40:18，<1 秒）**

`docs-skel.sh` → `✅ docs-skel：改动 8 个文件，跳过 0 个`；`git rm docs/手册.md`；`brickkit skills update` → `📦 Component repository (has component.yaml, no brickkit.yaml)…` / `Wrote 1: .claude/skills/brickkit-component/SKILL.md`。九个文件在，`CLAUDE.md` 恰好 `@AGENTS.md`，维护块在。

**C3 清单（06:40:27，约 1 秒）**

- `--write`：`assembly.yaml 删除的键：['version', 'asset', 'shell']`；`去掉 1 行归档引用注释`；`旧键 → 新键：{'pgSchema': 'PG_SCHEMA', 'otelBaseUrl': 'OTEL_BASE_URL', 'iamJwksUrl': 'IAM_JWKS_URL', 'authzBundleUrl': 'AUTHZ_BUNDLE_URL', 'dingtalkBaseUrl': 'DINGTALK_BASE_URL', 'dingtalkAppKey': 'DINGTALK_APP_KEY', 'dingtalkAppSecret': 'DINGTALK_APP_SECRET', 'dingtalkAgentId': 'DINGTALK_AGENT_ID'}`；module.go 五处读法改成新键；`ℹ️ backend/module/module.go:43: dingtalkAgentId    panic("必填配置项 \"dingtalkAgentId\" 未注入或不是合法整数")`（报错文案里的旧键名，随后在 C4 的 fix 提交里整段改掉）。`exit=0`。
- `--check` → 全部"无"，`✅ --check 全部为"无"`，`exit=0`。
- `brickkit lint integration/im-dingtalk` → 第一行 `🔎 Only integration/im-dingtalk is checked…`，`✅ components/integration/im-dingtalk/component.yaml`，`📋 Checked 2 files: 0 with errors, 72 warnings`（只有 DOC_* 占位）。
- 无新权限键，没跑 `make permissions`。

**C4 代码（06:41–07:01）**

- `go-v2.sh $ID --sdk v0.4.0` → 5.2 秒，`exit=0`。形态 B：`新建 gen/integration/im/go.mod（grpc v1.83.2、protobuf v1.36.12，与根模块同版本）`、`根 go.mod：require …/gen/integration/im v1.0.0 + replace => ./gen/integration/im`、Dockerfile 改成先 `COPY . .`；`C-1 检查 … ⏭ 没有`；`go: upgraded go 1.25.0 => 1.25.11`、`be-sdk-go v0.2.4 → v0.4.0`、`golang-migrate v4.19.1 => v4.20.1`；迁移入口一行化、删 `Migrations:` 与 migrations import。判据 15 条全部 PASS，`📌 第 8.3 步需要打的契约包 tag：gen/integration/im/v1.0.0`。`go list -m all` 本仓库恰好两行：`…/gen/integration/im v1.0.0 => ./gen/integration/im`、`…/v2`（Review Focus 1）。提交 ff3ab78（机械步骤）。
- 4.16 `make test-db-init ID=$ID`：`- integration/im-dingtalk` 下两行 `{"msg":"迁移结束","direction":"up","schema":"integration_im_dingtalk","outcome":"ok","version":2,"dirty":false}`、`✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。基线 `go test ./... -race -count=1 -v`：全部 PASS，`--- SKIP` 0 条。
- 4.10 没有 >600 行的文件、>150 行的函数。
- 审查与修复（每个红绿循环一个提交）：
  - **New 遇坏配置 panic**（c68275b）：`MustString` 与 `panic` 在外壳里绕过"成员构造函数返回 error 即点名退出"的失败契约。红：`New 应该返回 error，实际 panic：必填配置项 "DINGTALK_APP_KEY" 未注入`（三个子测试 + 非整数 agent id 一条）。绿：`readDingtalkConfig` 一次点名全部问题键。
  - **网络层错误带出 AppSecret**（fe5a5f1）：红：`gettoken 的网络层错误带出了 appsecret：调用钉钉 API 失败（网络层）: Get "http://127.0.0.1:44203/gettoken?appkey=ak1&appsecret=secret-should-not-leak": dial tcp …`。这条错误会进日志与 `GetChannelHealth` 的 `last_error`。绿：`withoutQuery` 只留方法与路径。
  - **tokenmgr 并发安全**（6eb6840，守现有行为的测试）：20 个并发 `EnsureValid`、fake gettoken 慢 100ms，断言只调 1 次；`-race -count=3` 通过。变异核对：删掉 `m.mu.Lock()` 后 `20 个并发 EnsureValid 期望只调 1 次 /gettoken，实际 20 次`，已还原。结论：进程内并发安全（互斥锁 + 拿锁后再读缓存）；多副本之间没有协调，两个副本可能各刷新一次——钉钉 gettoken 在有效期内重复申请返回同一个 token，后写覆盖前写也是有效 token，无害，不加跨副本锁。
  - **重构 consumer**（ce34f50）：九个依赖逐个传参（最长 12 个参数）收进 `deliverer`；"写 delivery_attempts + 写结果事件"三处合成 `recordResultTx`。行为逐项对照（字段、payload、version、回查等待序列）不变；测试一行未改。
  - **测试随机失败**（833c33d，测试设施）：`dingtalk_token` 单行表被 repo / tokenmgr / consumer 三个测试包并行读写。修前 `go test ./... -race -count=1` 连跑 6 次 5 次失败（`tokenmgr_test.go:159: 期望每个调用方都拿到 tok-once，实际 "tok-abc"`；先前也见过 `token_test.go:29: 期望 tok-abc，实际 ""`）。新增 `backend/internal/testlock`（advisory lock），三处测试辅助函数各加一行；断言不动。修后 6/6 ok。
  - **delivery_attempts 月分区从没人建**（832d4a3，最严重）：`partition.StartMonthly` 存在但 `Module.Start` 从没启动它（注释写"四个循环"，实际三个）；测试库与演示库都只有迁移建的 `2026_09_01`、`2026_10_01`。2026-11-01 起每条派发事件写 `delivery_attempts` 都会 "no partition of relation found for row"，而 `besdk.Consume` 对失败只记日志——通知中心永远收不到结果。红（测试先删掉未来分区，防止残留分区造成假绿）：`期望月分区 delivery_attempts_2026_11_01 / 2026_12_01 / 2027_01_01 已建好`。绿：`partition.Start` 每轮维护周分区与月分区。变异核对：还原后重新红。
  - **BatchGetDeliveryStatus 顺序**（126845f）：契约写"顺序与 record_ids 一致"，实现按字典序。红：`期望顺序 [record-z_… record-a_…]，实际 [record-a_… record-z_…]`。绿：按请求顺序拼结果、重复 id 只返回一次。
  - 代码与契约说明文字的注释改写（9a97c14）；测试注释改写（2686f97，`git diff` 里除 `//` 注释行外没有改动行）。
  - Makefile / Dockerfile / go.mod / buf.yaml 按模板（653cbb9）：`grep -n -i 'customer\|客户\|seed' Makefile` 为空；本组件没有种子数据，不设 seed 目标；`contract-check` 打印 `buf breaking --against '.git#tag=v1.0.5'`。
- 重构重点的其余两项：
  - **对外 HTTP 超时**：`http.Client{Timeout: 10 * time.Second}`，四个接口共用，加上请求 ctx；不改。一条派发最坏要串行走 gettoken / getbymobile（+ 刷新后重试）/ asyncsend（+ 刷新后重试），NATS 回调是逐条串行的，钉钉很慢时吞吐会被拖住——写进记录，不改（超时本身有上限）。
  - **失败重试上限与死信**：本组件自己的重试都有上限——token 过期只刷新重试一次；`getsendresult` 回查最多 4 轮（5/10/20/40 秒），用完记 `GET_SEND_RESULT_TIMEOUT`（可重试）。派发的重试归通知中心。死信：SDK 只在 `hop_count > 5` 时转 `dlq.<subject>`；handler 返回 error（数据库故障）时 `besdk.Consume` 只记日志、不重投、不进死信——事件丢失，写进 design.md 未决问题与反馈候选（SDK 层面，要 JetStream）。
- C4 结束 `component-check.sh` → 第 1–9 项 PASS，第 10 项（占位符）FAIL，原文在 `$S/component-check-c4.log`（预期）。

**C5 文档（07:01–07:05 之前写完）**

八份文件写满。`component-check` 第一次在历史扫描 FAIL：`BRICKKIT.zh.md:59`、`docs/design.zh.md:27/66`——"每个阶段一条 / 一行 / 一次"被 `阶段[一二三四五六0-9]` 命中（误报，正常中文），改成"各一条"等。`assembly.yaml` 里 `（导读第 22 条）` 这条历史出处 `HIST_RE` 认不出，C5 手工清掉（之后再跑 `--write` 需要 `--force`，见卡点 3）。之后 `component-check` 十项全部 PASS，`make docs-boundary` 绿，`make docs-check ID=integration/im-dingtalk` → `📋 Checked 2 files: 0 with errors, 0 warnings`。提交 9768842。

**C6 版本与门禁（07:01–07:04，最终复跑 07:16–07:20）**

- `make check-version test contract-check import-scan module-check dag-check` → 全绿（`✓ version=2.0.0…`、6 个测试包 `ok`、`buf breaking --against '.git#tag=v1.0.5'`、`✓ 无组件间 import`、`✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`、`✓ 无依赖，无环`）；`--- SKIP` 0 条。
- `make test-db-init ID=$ID` → `✓ 迁移幂等`、`✓ brickkit_test_db 就绪`。
- `project-lock.sh -- make gates` → `exit=0`：import / system-client / bare-route / events-breaking / data-scope-test / dependency-version 都 0 条违规；`service-hostname-scan：0 条错误（1 条警告）`（`infra-iam-casdoor-2-0-0 … 不在 brickkit.yaml 里`，预期）；`config-key-scan：0 条违规`（本组件不出现）；`openapi-additive-scan：0 条违规（0 条跳过提示）`。
- 发布前门禁自查（锁内）：`✓ config-key-scan（只看 components/integration/im-dingtalk）：0 条违规`、`✓ openapi-additive-scan（只看 components/integration/im-dingtalk）：0 条违规（0 条跳过提示）`，两者 `exit=0`。
- 最终复跑（da6aa53 上）：`component-check` 10 项 PASS；`migrate-manifest --check` 全部"无"；`go-v2.sh --recheck` 判据全部 PASS、仍 `gen/integration/im/v1.0.0`；`make gates` `exit=0`；`make teardown-sync CHECK=1` → `✓ deploy.teardown.yaml 与 deploy.yaml 一致`。

**C7 接入与真机（07:07–07:20）**

- `.env`（锁内）追加三个明显的假值：`INTEGRATION_IM_DINGTALK_DINGTALK_APP_KEY` / `_APP_SECRET` / `_AGENT_ID`（`fake-local-key`、`fake-local-secret`、`0`——agent id 必须是整数）。`.env` 被 git 忽略。
- 第一次 `make integrate`（07:08:48）：`brickkit add` → 7 行 `🔗 … references the variable of the same name in config/vars.yaml (--yes)`、`✅ integration/im-dingtalk@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml`；`config-fill.py` 写了 `PG_PASSWORD, PG_USER, PG_SCHEMA`，然后 `✗ … 还有 3 个 required 键没有值`（三个钉钉键）→ 第 3 步失败（预期路径）。
- `config-fill.py --set 'DINGTALK_APP_KEY=${INTEGRATION_IM_DINGTALK_DINGTALK_APP_KEY}' --set 'DINGTALK_APP_SECRET=${…_APP_SECRET}' --set 'DINGTALK_AGENT_ID=${…_AGENT_ID}'` → `写了 3 个键`。`DINGTALK_BASE_URL` 保持注释。
- 第二次 `make integrate`（07:08:59，3 秒）→ `brickkit lint --strict` `0 with errors, 0 warnings`（含 `config/ ↔ configSchema`）；`up --dry-run` → `✅ integration/im-dingtalk@2.0.0  starting (top-level)`；`✓ integrate integration/im-dingtalk@2.0.0 完成`。生成的 compose：`PG_USER=integration_im_dingtalk_rw`、`PG_SCHEMA=integration_im_dingtalk`、`AUTHZ_BUNDLE_URL=http://infra-authz-2-0-0:8223/authz/bundle`、`IAM_JWKS_URL=http://infra-iam-casdoor-2-0-0:8200/.well-known/jwks.json`、`DINGTALK_BASE_URL=https://oapi.dingtalk.com`（注释掉的键注入 schema 默认值）、`extra_hosts: host.docker.internal:host-gateway`。AGENTS.md 组件表多一行 `| integration/im-dingtalk | 2.0.0 | The DingTalk member of the IM channel family; … | BRICKKIT.md +zh | https://github.com/brickKit/integration-im-dingtalk |`。
- 第一次 `make verify … FOCUS=1 SEED=1 KEEP=1`（07:09:17，75 秒）：全部 PASS / 写明原因的 SKIP。但 KEEP=1 留下的容器与项目根的 `deploy.verify.yaml` 一分钟内被别的工作线的 verify 收尾掉了（见卡点 1），手工核对改成自己的锁内脚本（`$S/runtime-check.sh`，用本线私有的 `deploy.verify-im-dingtalk.yaml`，由 `verify-component.sh --deploy-only` 现生成）。
- 第一次手工核对（07:15:34–07:15:59）发现**凭据不合法被判成可重试**：`收到结果事件 … "retryable": true, "error_code": "DINGTALK_40096"`。`curl 'https://oapi.dingtalk.com/gettoken?appkey=fake-local-key&appsecret=fake-local-secret'` → `{"errcode":40096,"errmsg":"不合法的appKey或appSecret"}`：关键词按字面大小写找 `AppKey` / `appkey`，漏了 `appKey`。红绿修复 da6aa53（红：`凭据不合法期望不可重试——这是钉钉对假凭据的真实响应`）。
- 最终 `make verify ID=integration/im-dingtalk ROUTE=/integration/im/admin/deliveries FOCUS=1 SEED=1 FORCE_BUILD=1`（07:17:44–07:19:23，99 秒）：

```
verify integration/im-dingtalk@2.0.0 汇总（输出目录 $BE_SCRATCH/verify/integration-im-dingtalk-20261002-071804）
| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build integration/im-dingtalk | PASS |  | build.log |
| 镜像 integration-im-dingtalk:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| integration-im-dingtalk-2-0-0 running (healthy)（容器服务 integration-im-dingtalk-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| GET /integration/im/admin/deliveries 不带 token → 401/503 | PASS | 实际 401 | http.log |
| GET /integration/im/admin/deliveries 带 token → 200 | SKIP | infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token |  |
| make -C components/integration/im-dingtalk seed | SKIP | components/integration/im-dingtalk/Makefile 没有 seed 目标 |  |
| make test-cross ID=integration/im-dingtalk | PASS |  | test-cross.log |
| focus：宿主机 http://localhost:8207/healthz → 200 | PASS |  | focus.log |
| brickkit up --all --dry-run（清除 focus） | PASS |  | focus-all-dry-run.log |
| brickkit local off | PASS |  | local-off.log |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |
✓ 全部 PASS 或写明原因的 SKIP
```

  build.log `✅ Built integration/im-dingtalk@2.0.0 → integration-im-dingtalk:2.0.0`；迁移容器最后一行 `{"msg":"迁移结束","direction":"up","schema":"integration_im_dingtalk","outcome":"ok","version":2,"dirty":false}`；focus `integration-im-dingtalk-2-0-0  listening on port 8207`。两个 SKIP：带 token 待 T25；本组件没有种子数据。

- 最终手工核对（锁内，07:19:23–07:19:52，`$S/runtime-check-2.log`）：
  - 运行中的组件建好了未来月分区：`delivery_attempts_2026_11_01 / 2026_12_01 / 2027_01_01`，属主 `integration_im_dingtalk_rw`；表属主 `integration_im_dingtalk_rw|27`。
  - 默认 `DINGTALK_BASE_URL`、假凭据，往生产 subject 发一条 `target_adapters: [dingtalk]` 的派发事件：`收到结果事件 version=12 payload={"phase": "CONFIRMED", "adapter": "dingtalk", "attempt": 1, "success": false, "record_id": "verify-default-1790918377", "retryable": false, "error_code": "DINGTALK_40096", "external_task_id": ""}`；`delivery_attempts` 一行 `CONFIRMED|f|DINGTALK_40096|f|`；outbox 一行 `PUBLISHED`。日志无 panic、假 AppSecret 出现 0 次；`RestartCount/状态` → `0 running`。
  - Review Focus 2（有默认值的自有键配非默认值）：临时把 `DINGTALK_BASE_URL` 配成 `http://127.0.0.1:9` 重建容器，`docker exec … printf "$DINGTALK_BASE_URL"` → `http://127.0.0.1:9`；同样一条派发 → `error_code: NETWORK_ERROR, retryable: true`（默认值下是 `DINGTALK_40096`）——行为随配置值改变，读的确实是新键。配置随后还原（`config 已还原（与备份逐字节相同）`）。
  - 收尾：`down exit=0`、私有 deploy 文件删除、`Local mode: off` / `deploy.local.yaml: none`、`没有本项目的组件容器`。

**C8 交接（07:20）**：发布说明 `$S/notes-2.0.0.md`（`$S=$BE_SCRATCH/06b/integration-im-dingtalk`）补了"新增 / 修复"；"升级前必须做"相对 generated 多一行（有意补的）：`迁移状态表沿用 schema_migrations_integration_im_dingtalk，已有库直接升级；迁移文件已嵌进 ./migrate 二进制…`。只跑过一次 `--write`，没有 ⚠️ 漂移。`git -C $C log --oneline -3`：

```
da6aa53 fix(dingtalk): 凭据不合法（errcode 40096）判不可重试——关键词匹配不分大小写
fabb344 test(consumer): 派发事件测试每次运行用新的手机号，不再命中上次留下的缓存
9768842 docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
```

### 现象

- 符合预期的：形态 B 拆模块、`/v2`、SDK 一行迁移入口一次通过；迁移以 `_rw` 登录、表归它所有；`brickkit add` 自动把共享键链到 `$var:`；`config-fill` 在三个钉钉键上按预期 exit 3、`--set` 后通过；不带 token 401；focus 通过；假凭据下投递失败被记录、结果事件发出、不崩溃。
- 不符合预期的（都已修）：月分区循环从没启动；凭据错误判成可重试；网络错误带出 AppSecret；BatchGet 顺序与契约不符；New 里 panic；三个测试包共享单行表随机失败；固定手机号让 getbymobile 路径从第二次运行起不再被测。

### 卡点与绕过

1. **KEEP=1 留下的东西被别的工作线收掉。** 第一次 verify（KEEP=1）结束一分钟内，`docker ps` 里已没有本组件容器，项目根 `deploy.verify.yaml` 也被删了（`❌ Error: the deploy file given with --file does not exist / Path: deploy.verify.yaml`）。`deploy.verify.yaml` 是各线共用的文件名，别的线的 verify 建它、删它，收尾的 `brickkit down` 也会停掉全部本项目容器。绕过：锁内脚本里用 `verify-component.sh <id> --deploy-only deploy.verify-im-dingtalk.yaml` 现生成私有文件，`up` / 核对 / `down` / 删除都在同一次持锁里完成。
2. 生成的 compose 里 `DINGTALK_APP_SECRET` 不以 `KEY=值` 出现（secret 走别的注入方式），运行期核对用的是行为（结果事件里的 error_code）而不是打印值，没有打印任何 `.env` 值。`project-lock.sh` 的 "acquired by … (命令行)" 会原样回显命令，我追加 `.env` 假值那一次命令行里带着假值（`fake-local-*`，不是密钥）。
3. `assembly.yaml` 的 `（导读第 22 条）` 手工清理之后，`migrate-manifest.py --write` 会把它当手改、exit 3；之后若要改 overrides 重跑 `--write`，先读 diff 再 `--force`。本 Task 之后没有再跑 `--write`。
4. 没有翻 brickKit 源码。为了回答"失败重试与死信"读了项目自己的 be-sdk-go v0.4.0：`events.go`（`Consume` 只记日志不重投，`hop_count > 5` 才进 `dlq.`）、`runtime.go`（`MustString` panic）、`standalone.go` / `shell/run.go`（构造函数 error 的处理）、`archive.go` / `outbox.go`（没有分区保留或 outbox 清理）。

### 控制者两条中途通知的核对结果

- **固定幂等键 / 自然键**（mdm/product 线的提醒）：本组件没有写 rpc、没有 `idempotency_key`；派发事件测试的 `record_id` 与 subject 每次都唯一。但手机号是 `dingtalk_user_map` 的主键：`TestDispatchHandler_成功提交后ACCEPTED_延迟回查后CONFIRMED` 用固定 `13800000000`，测试库里这一行 `resolved_at` 是 `2026-09-12 15:32:53`，今天跑完仍不变——"缓存没有 → 调 getbymobile → 写缓存"从第二次运行起就没再测过。修：`uniquePhone()`，单独一个测试提交 fabb344，断言不动；改后连跑两次，缓存表多出两条刚写入的行。repo 包的 usermap 测试本来就用 `uniqueID`。
- **R49（gRPC 码 → HTTP 码）**：`contracts/im-dingtalk.openapi.yaml` 两个路由只声明 `200`，没有任何 409。代码能返回的错误：非法 `cursor` → `ErrInvalidArgument` → `codes.InvalidArgument` → 400（与表一致）；刷新 token 失败 → `codes.Internal` → 500。没有 FailedPrecondition / Aborted / AlreadyExists。无不一致，无需补 409 测试。

### V 项

- V-13（`brickkit add` 重排注释）：本组件 `add` 之后 `git diff brickkit.yaml` 只有新增行，没看到注释被挪动（其它工作线的 add 也在同一份 diff 里，没逐一区分）。
- V-12：不适用（本组件没有容器依赖；focus 改写 `PG_HOST, NATS_URL, S3_URL` 为 `172.17.0.1` 后 healthz 200）。
- V-04 知识缺口：无（没读 brickKit 源码）。

### 结论

完成。integration/im-dingtalk 2.0.0 组件仓库 14 个提交就绪（未推送、未打 tag），`make verify … FOCUS=1 FORCE_BUILD=1` 全部 PASS（带 token 一项 SKIP 待 T25，seed 一项 SKIP：没有种子数据），假凭据下的投递失败链路真机核对通过；契约包需要第一个 tag `gen/integration/im/v1.0.0`。

### 反馈候选

- **`make verify KEEP=1` 与共用的 `deploy.verify.yaml`**（项目工具，交控制者）：并行工作线下，KEEP=1 留下的容器与项目根的 `deploy.verify.yaml` 会被别的线的 verify 删掉 / 停掉。建议 verify 用 `deploy.verify-<repo>.yaml` 这类按组件区分的文件名，收尾只 `down -f` 自己的文件；KEEP=1 时在汇总里提示"锁一释放，别的线可能收掉它们"。
- **`HIST_RE`**（项目工具，交控制者）：漏掉"导读第 N 条"这类出处（只能手清、之后 `--write` 要 `--force`）；又把正常中文"每个阶段一条 / 一行 / 一次"判成历史引用（`阶段[一…]`）。建议 `阶段[一二三四五六]` 后面要求不是量词（如排除"一条 / 一行 / 一次 / 一个"），并加上 `导读`。
- **be-sdk-go `Consume` 至多一次**（SDK，进 to-verify / SDK 待办）：handler 返回 error 时只记日志，不重投、不进死信；对本组件意味着数据库一抖，这条通知就永远没有结果。要至少一次得上 JetStream durable consumer。
- **没有分区保留 / 归档 / outbox 清理**（SDK 或项目，进 to-verify）：全项目没有组件 DETACH / DROP 旧分区，`delivery_attempts` 的"热一个月"和 outbox "30 天后清理"都只是目标。建议 SDK 提供一个分区保留助手，与建分区的循环放在一起。
- **样板 AGENTS 的 Build and test 写了 `set -a; . ../../../.env`**（项目文档，交控制者）：与"不在 shell 里 source .env"的纪律相反，本组件改成了通用的 `TEST_PG_DSN=postgres://<user>:<password>@…` 写法；mdm/customer 的同一段可以顺手改。
- **跨测试包共享的单行 / 固定键数据**（项目测试规范，交控制者）：`go test ./...` 并行跑各包的测试二进制，碰同一行的测试会随机失败；本组件用 advisory lock 解决。别的组件若有单行配置表也会撞上，可写进 06-testing.md 的"真实数据库测试"一节。

## 小结

- 完成：组件仓库提交（components/integration/im-dingtalk，均未推送）：
  - ff3ab78 chore: 迁移到 brickKit v1 骨架与 2.0.0 清单（机械步骤）
  - c68275b fix: 钉钉配置缺失或 DINGTALK_AGENT_ID 不是整数时 New 返回 error，不再 panic
  - fe5a5f1 fix: 连不上钉钉时的错误文本不再带出 appsecret 与 access_token
  - 6eb6840 test(tokenmgr): 并发 EnsureValid 只调一次 gettoken
  - ce34f50 refactor(consumer): 投递依赖收进 deliverer，结果的"落库 + 发事件"合成一处
  - 833c33d test: 碰 dingtalk_token 单行的测试跨包串行（advisory lock），修掉随机失败
  - 832d4a3 fix(partition): 分区维护循环同时建 delivery_attempts 的月分区
  - 126845f fix(repo): BatchGetDeliveryStatus 按请求的 record_ids 顺序返回
  - 9a97c14 docs(code): 代码与契约说明文字改写成原因本身，不再引用归档文档与历史
  - 2686f97 test: 测试注释改写成测的是什么、为什么，不再引用归档文档与历史
  - 653cbb9 chore: Makefile / Dockerfile / go.mod / buf.yaml 按 v1 模板改
  - 9768842 docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
  - fabb344 test(consumer): 派发事件测试每次运行用新的手机号，不再命中上次留下的缓存
  - da6aa53 fix(dingtalk): 凭据不合法（errcode 40096）判不可重试——关键词匹配不分大小写
- 契约包 tag：需要 `gen/integration/im/v1.0.0`（`go-v2.sh` 最后一次 `--recheck` 原文：`📌 第 8.3 步需要打的契约包 tag：gen/integration/im/v1.0.0（必须等于根 go.mod require 的版本；推送前外壳拉不到）`）。
- 父仓库待控制者提交（脚本写出，未提交）：`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/integration-im-dingtalk.yaml`、`AGENTS.md`（组件表）、`components/integration/im-dingtalk`（指针，ship 之后）、本记录。`manifest-overrides.yaml` 本组件那一段没改。`registry/permissions.tsv` 里的 `+mdm.product.set_status	启用/停用产品	action	mdm/product` 是 mdm/product 线的，不是本组件的（本组件没跑 `make permissions`）。`.env` 追加了三行假钉钉值（不提交）。
- 需要控制者裁定的：KEEP=1 与共用 `deploy.verify.yaml` 的冲突（反馈候选 1）；SDK `Consume` 至多一次（反馈候选 3）。
- 遗留到后续：带 token 打受保护路由得 200（T25）；`.proto` 注释清理（下一次契约变更，R41）；回查不持久化、归档未实现、管理列表没有默认时间窗口（写进 design.md 未决问题）。
- 检查点：integration/im-dingtalk 2.0.0，tag `gen/integration/im/v1.0.0` / `2.0.0` / `v2.0.0` 待 `make ship`，组件 HEAD da6aa53。

## 修复轮（审查 C-1，2026-10-02）

### 目标

审查 C-1（`.superpowers/sdd/plan-06b/task-15-review.md`）：`backend/internal/dingtalk/client.go` 还有三条路径把 AppSecret / access_token 带进错误文本（进日志、`GetChannelHealth.last_error`、`POST /admin/token/refresh` 的 500 响应体）。fe5a5f1 只修了网络层那一条。

### 环境

组件 HEAD da6aa53（工作区干净）起步；env.sh：BrickKit CLI v1.1.0，TEST_PG_DSN 指向 brickkit_test_db（不打印值）。不跑真机：改动不碰已在真机上核对过的路径（假凭据返回的是合法 JSON 40096）。

### 步骤

1. 先写三条红测试（照 `TestClient_网络层错误不带出appsecret与access_token` 的断言）：`TestClient_建请求失败的错误不带出appsecret与access_token`（base URL `http://bad host`）、`TestClient_响应解码失败的错误不带出access_token`（`errcode=0` 但 `expires_in` 是字符串）、`TestClient_非JSON响应的错误不带出原文`（502 + text/html，页面回显请求 URL；另断言错误里有路径、`502`、`text/html`）。修复前 `go test -count=1 -run 'TestClient_' ./backend/internal/dingtalk`，原文：
   ```
--- FAIL: TestClient_建请求失败的错误不带出appsecret与access_token (0.00s)
    client_test.go:225: gettoken 建请求失败的错误带出了 appsecret：建请求: parse "http://bad host/gettoken?appkey=ak1&appsecret=secret-should-not-leak": invalid character " " in host name
--- FAIL: TestClient_响应解码失败的错误不带出access_token (0.00s)
    client_test.go:255: 解码失败的错误带出了 access_token：解析钉钉响应体: json: cannot unmarshal string into Go struct field getTokenResponse.expires_in of type int64（原文: {"errcode":0,"access_token":"tok-should-not-leak","expires_in":"7200"}）
--- FAIL: TestClient_非JSON响应的错误不带出原文 (0.00s)
    client_test.go:279: 非 JSON 响应的错误带出了 appsecret：解析钉钉响应体: invalid character '<' looking for beginning of value（原文: <html>Bad gateway for /gettoken?appkey=ak1&appsecret=secret-should-not-leak</html>）
FAIL
FAIL	github.com/brickKit/integration-im-dingtalk/v2/backend/internal/dingtalk	0.011s
FAIL
   ```
2. 修复：`withoutQuery` 改成 `withoutURL(err, method, path)`，建请求、网络层、读响应体三处都把错误链上的任何 `*url.Error` 换成"方法 路径: 底层原因"（不再带 base URL）；响应解不开时 `decodeError` 只报方法、路径、HTTP 状态码、Content-Type 与字节数，不放原文。`errcode != 0` 分支仍只是 `*APIError{Code, Msg}`，没有加原文。
3. 同一提交里改文字：`AGENTS.md` / `AGENTS.zh.md` 的代码地图一行与易错点一行（"错误文本里不放请求 URL，也不放响应原文"，列出四种触发情况与三个去处）；`client.go` 顶部包注释加一段；发布说明 `$BE_SCRATCH/06b/integration-im-dingtalk/notes-2.0.0.md`"修复"一节的泄露条目扩写成四种情况。
4. 组件仓库提交 `ce794c9 fix(dingtalk): 错误文本里不放请求 URL，也不放响应原文（建请求失败、响应解不开两类路径仍会带出 AppSecret / access_token）`。
5. 复跑（日志在 `$S/c1-*.log`）：
   - `go test -race -count=1 -v ./...` → `exit=0`，39 个 `--- PASS`（原 36 + 新 3），0 个 `--- SKIP`，0 个 `--- FAIL`；六个包都是 `ok`。
   - `component-check.sh integration/im-dingtalk` → `✅ component-check integration/im-dingtalk：10 项全部 PASS`，`exit=0`。
   - `make -C $ROOT docs-check ID=integration/im-dingtalk` → `📋 Checked 3 files: 0 with errors, 0 warnings`，`exit=0`。
   - `make check-version test contract-check import-scan module-check dag-check` → `exit=0`：`✓ version=2.0.0…`、六个包 `ok`、`buf breaking --against '.git#tag=v1.0.5'`、`✓ 无组件间 import`、`✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`、`✓ 无依赖，无环`。
   - `go vet ./...` 通过；`go mod tidy -diff` 无输出；`go list -m all | grep brickKit/integration` 仍恰好两行（`…/v2`、`…/gen/integration/im v1.0.0 => ./gen/integration/im`）。

### 现象

三条红测试修复前都红，红的原文与审查者的三条探测一致；修复后全绿，其余测试不受影响。网络层错误的文本从"方法 base+路径"变成"方法 路径"（base URL 也可能带代理的用户名口令，一起去掉）。

### 卡点与绕过

无。

### 结论

C-1 已修。组件 HEAD `ce794c9`，比 origin/main 多 15 个提交；2.0.0 未发布，不 bump。tag 仍按原计划：`gen/integration/im/v1.0.0`、`2.0.0`、`v2.0.0` 打在 `ce794c9` 上（`make ship`）。要不要重跑 `make verify` 由控制者决定。

### 反馈候选

无新增。
