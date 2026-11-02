# 06b infra/iam-casdoor：过程记录（T17，W2 提前开工，C1–C9）

> 本工作线是**中断后接手**的：前一个实现者做到 4515cb9（9 个提交）、留下 7 个未提交文件后被打断，没有留下记录与报告。本记录从接手时的磁盘状态写起；C1–C3 与 4515cb9 之前的 C4 是前一个实现者做的，这里只记能从提交、scratch 日志里核实的事实。

## 概况

- 日期：2026-10-02（接手 12:31，C6 结束 12:58）
- brickKit：`BrickKit CLI v1.1.0`（env.sh：`ℹ️  env.sh：BrickKit CLI v1.1.0（/home/zhijie/.local/bin/brickkit）；buf 在；TEST_PG_DSN 由 .env 的 POSTGRES_PASSWORD 在 eval 时拼出（URL 编码，不打印值），TEST_NATS_URL=nats://localhost:4222`）
- SDK：be-sdk-go v0.4.0
- 基础资源：`make check` → `✓ 全部基础资源就绪`
- 组件与版本：infra/iam-casdoor v1.0.10 → 2.0.0；组件仓库提交 ba0f243 … 7ec2250（20 个，未推送、未打 tag）
- 契约包：形态 B 拆出的嵌套模块 `gen/infra/iam`，**需要控制者打 `gen/infra/iam/v1.0.0`**（`go-v2.sh --recheck`：`📌 第 8.3 步需要打的契约包 tag：gen/infra/iam/v1.0.0`）
- scratch：`$S=$BE_SCRATCH/06b/infra-iam-casdoor`（BE_SCRATCH 是 plan 写定的旧会话路径）
- C1–C6 之后停下询问控制者（W2 提前开工）；控制者确认上游已发布、裁定 R56 后做 C7–C9（13:15–13:55，见文末"C7–C9"一节）

## infra/iam-casdoor

### 目标

按 component-loop 把 infra/iam-casdoor 重建到 2.0.0（brief：T17）；`ENABLED_COMPONENTS` 改为项目 `brickkit.yaml`（R27）；为 `WEBHOOK_CALLBACK_URL` 找 v1 下的正当做法；重构重点 casdoor / tokens / keys 的边界、签名密钥轮换的测试、Casdoor 管理 API 的超时与错误映射。本轮只做 C1–C6。

### 环境

brickKit v1.1.0；目标 docker；本组件尚未加入项目（`brickkit.yaml` 里没有它）；本地模式 off（`brickkit local status` → `Local mode: off` / `deploy.local.yaml: none (brickkit local on creates it)`）；没有起任何组件容器。测试库 `brickkit_test_db`；基础资源 Casdoor 在 `localhost:8000`（`be-casdoor`，在 `be-net` 上）。

### 步骤

**接手时的状态**

- `git -C $C status -sb` → `## main...origin/main [ahead 9]`，未提交：`backend/internal/casdoor/{admin.go,admin_test.go,fake_test.go}`、`backend/module/module.go` 改动，新文件 `backend/module/{casdoor.go,retry.go,retry_test.go}`。
- 前一个实现者最后一句话："Helpers are green. Now rewiring `Start` to use them, with R51 log levels." 读 diff：`Start` 实际已经改接好（`registerSigningKeys` / `connectCasdoorAdmin` / `discoverIDTokenVerifier` 三个函数、`retryUntilOK`、`casdoor.IsUnreachable`），编译、vet 通过，module 与 casdoor 两个包测试全绿。保留，补测试后提交（72bc3bb）。
- scratch 里的 `test-v-baseline.log`（前一个实现者 C4 起步时）：`--- FAIL: TestRun_webhookCallbackURL为空时跳过webhook步骤`，已由 5108465 修掉（测试自身的错，断言未动）。

**C1 前置（核实）**

- 上游已发布（W2 提前开工，原本记"待 C7 前复核"；现在已核实）：
  ```
  git -C components/infra/authz ls-remote --tags origin 2.0.0 v2.0.0 gen/infra/authz/v1.0.5
  d4918c67977e8188163887d59ec0cad56b099050	refs/tags/2.0.0
  9e443ee2c7a76283c259f097f079f0dc7fae9987	refs/tags/gen/infra/authz/v1.0.5
  9033a5f1fafb39cb8e80f1c23eabde864162ee13	refs/tags/v2.0.0
  ```
  `go.mod`：`github.com/brickKit/infra-authz/gen/infra/authz v1.0.5`。infra/authz 已在 `brickkit.yaml` 里（`up --dry-run` 列出 `infra/authz@2.0.0`）。C7 前仍按 1.1 重跑一次。
- 最后一个 1.x tag：`v1.0.10`（`contract-check` 的 `--against` 就是它）。
- `command -v protoc-gen-go protoc-gen-go-grpc` → `/home/zhijie/go/bin/protoc-gen-go`、`/home/zhijie/go/bin/protoc-gen-go-grpc`。
- 1.6 表属主：`select tableowner, count(*) from pg_tables where schemaname='infra_iam_casdoor' group by 1`（brickkit_db）→ 空（演示库里还没有本组件的表）。
- 1.2 仓库干净：接手时不干净（前一个实现者的半成品，见上），按 takeover.md 读后保留。

**C2 骨架（前一个实现者，ba0f243）**

`$S/brickkit-new.log`：`✅ Component skeleton generated: infra/iam-casdoor`。docs-skel 写出八份文档骨架 + `CLAUDE.md`，`docs/手册.md` 删除，`brickkit skills update` 写入 `.claude/skills/brickkit-component/`。

**C3 清单（前一个实现者，ba0f243）**

- `$S/lint-c3.log`：第一行 `🔎 Only infra/iam-casdoor is checked (brickkit lint --all checks the whole project)`，`✅ components/infra/iam-casdoor/component.yaml`，`📋 Checked 2 files: 0 with errors, 76 warnings`（只有文档类警告）。
- 本组件 `permissions: []`，没有新权限键，没跑 `make permissions`。
- 接手后重跑 `migrate-manifest.py infra/iam-casdoor --check`：`✅ --check 全部为"无"`，`exit=0`；它的 ℹ️ 列出注释与测试文案里 6 处旧驼峰键名，已改（1d34ebe），重跑后 ℹ️ 为 0 条。
- `assembly-removed-comments.txt`：3 行，都是去掉出处的"改"，结论（没有管理界面、不做行级过滤、没有权限键）已写进 BRICKKIT / docs/design。

**C4 代码**

前一个实现者（ba0f243 … 4515cb9）：go-v2.sh 拆嵌套模块、/v2、SDK v0.4.0（`$S/go-v2-1.log`、`go-v2-2.log`）；ENABLED_COMPONENTS 解析器（bdd1bb0，L2 用真实形态的 brickkit.yaml：外壳条目、requiredBy、带 `authToken: ${X}` 的 source）；webhook 对账改写（68b5188）；管理会话重登与 BatchGetUsers 的 Unavailable（b65cc1c）；REST 状态码与签名密钥轮换测试（5e9ca51）；刷新先拿 claims 再轮换（e02770a）；loadSettings（19a325b、4515cb9）。各提交信息里有红绿原文。

接手后：

1. **72bc3bb** 管理 API 登录改为后台重试（前一个实现者写的实现）+ 补 `TestConnectCasdoorAdmin_登录失败在后台重试直到成功且只记Warn`（假 Casdoor 前两次登录回 503）。这一条是先有实现、后补测试，没有红的记录（提交信息里写明）。
2. **07790c3** 对账途中 Casdoor 不可达时整轮重试。红（`$S/red-bootstrap-retry.log`）：
   ```
   --- PASS: TestConnectCasdoorAdmin_登录失败在后台重试直到成功且只记Warn (3.07s)
       casdoor_test.go:143: 对账途中 Casdoor 不可达应整轮重试，get-organization 实际只调了 1 次
   --- FAIL: TestConnectCasdoorAdmin_对账途中Casdoor不可达时整轮重试且只记Warn (0.06s)
   ```
   绿：module 包全部通过；bootstrap、casdoor 包对着真实 Casdoor（`TEST_CASDOOR_BASE_URL=http://localhost:8000`，管理员口令走测试默认值，没有读 `.env`）：
   ```
   --- PASS: TestRun_每一步都幂等可重跑 (0.84s)
   --- PASS: TestRun_webhookCallbackURL为空时跳过webhook步骤 (0.57s)
   --- PASS: TestRun_回调地址或共享密钥变了再跑一遍会更新webhook (0.64s)
   --- PASS: TestAdminClient与IDTokenVerifier_真机走一遍完整流程 (1.60s)
   --- PASS: TestIDTokenVerifier_拒绝错误issuer (0.58s)
   ```
   `bootstrap_test.go` 只随 `Run` 的签名去掉 logger 参数，断言未动。
3. **1a0e55e** Makefile 照抄 mdm/customer 模板（R43）：`dag-check` 改成 YAML 读 `dependencies.components`、判"恰好一条精确版本的 infra/authz"（旧版数 `- ` 行，对流式写法 `[infra/authz@2.0.0]` 一行都数不到）；负例在临时副本里核过（多一条 mdm/customer、空依赖都 `exit=2` 并点名）。Dockerfile 照模板（不再拷 `migrations/`）；`migrations/embed.go` 注释跟上 `migrate.Main`。`grep -n -i 'customer\|客户' Makefile` 为空。
4. **component-check 第一次**（`$S/component-check-c4a.log`）：第 4 项（历史 / 归档引用）FAIL，72 处；第 10 项（占位符）FAIL（预期）。逐处改写（38ed065、4f7a03b）：出处换成原因本身，RFC 章节写成"第 3.2 节"；`iam.openapi.yaml`、`iam.events.json` 只改 description / note（结构与 subject 不变，`openapi-additive-scan`、`events-breaking-scan` 都绿）；`.proto` 不动（R41）。另外去掉了指向不存在文件的引用（`docs/dev/实测踩坑记录.md`、`infra/seed-data/README.md` 等）。第二次：只剩第 10 项 FAIL。
5. **2fdaaea 分区维护（真实 bug）**：迁移只建了 `event_outbox` / `event_inbox` 到 2026-10-05 的周分区、`webhook_deliveries` 到 2027-01-01 的月分区，迁移注释说"其余由组件内置定时任务自动建"，组件里却没有这个任务（其余 Go 组件都有 `backend/internal/partition`）。红（`$S/red-partition.log`）：包不存在（`undefined: ensureAll` 等）；测试库里 `event_outbox_2026_09_28` 是最新的一个分区。绿：`TestMondayOf`、`TestFirstOfMonth`、`TestEnsureAll_建出往后的周分区与月分区且连跑两次都成功`；测试库里多出 `event_outbox_2026_10_05 … 10_26`、`event_inbox_2026_10_05 … 10_26`、`webhook_deliveries_2027_01_01`。module.go 的注释清理随这个提交一起进去了（同一文件）。
6. **e338a1c 去重竞态（真实 bug）**：`RecordDeliveryAndPublish` 是"先 SELECT EXISTS 再 INSERT"（项目 AGENTS.md 易错点里明令禁止的形状）。红（`$S/red-dedup.log`）：`同一投递并发到达 8 次，事件应只发布 1 次，实际 8 次`。改为事务开头 `pg_advisory_xact_lock(hashtext('infra_iam_casdoor.webhook_deliveries'), hashtext($1))`；绿：repo 包连跑三遍全部通过。
7. **da56d73** 共享密钥改用 `subtle.ConstantTimeCompare`（端点经 expose 的宿主机端口可达）；真值表不变，相关测试前后都过。
8. **24a3972** consumer 包原来没有任何测试，补三条（kicked 作废全部、普通变化不动、sub 为空跳过 / 坏 payload 报错）；payload 字段与 infra/authz 2.0.0 的 `authz.events.json` 核对过。

重构重点的结论：

- casdoor / tokens / keys 三个包边界干净：keys 只管密钥材料（PEM、RFC 7638 kid、JWK），tokens 只管本组件自己的 JWT，casdoor 只管与 Casdoor 的两条接触面（管理 API、OIDC 发现 + id_token 验签），service 编排。没有拆或并的必要。`service.New` 有 12 个位置参数，可读性一般，未动（不是本轮重点，改了也只是风格）。
- 签名密钥轮换有测试（5e9ca51：JWKS 双挂、两把钥匙签的应用 token 都能经 keyfunc 验过、上一把签的 refresh token 仍被认；tokens 包已有"旧公钥移除后拒绝"）。
- Casdoor 管理 API：每次调用（含重登）15 秒上限、会话过期重登一次、连不上 / 非 200 与 Casdoor 明确拒绝分开（`IsUnreachable`，决定 Warn 还是 Error，R51）；OIDC 发现 10 秒上限。错误不再拼响应体原文（应用对象里有 clientSecret）。
- 4.10：没有超过 600 行的文件、没有超过 150 行的函数（总 2610 行）。
- 4.12：`make module-check` 绿；模块代码零 `os.Getenv`、零进程级初始化、零 `log.Fatal` / `os.Exit`。

C4 收尾：

- `go-v2.sh infra/iam-casdoor --recheck` → `exit=0`，14 条判据全部 PASS（`$S/go-v2-recheck.log`），`📌 第 8.3 步需要打的契约包 tag：gen/infra/iam/v1.0.0（必须等于根 go.mod require 的版本；推送前外壳拉不到）`，`✅ go-v2.sh：判据全部 PASS`。
- `make -C $ROOT test-db-init ID=infra/iam-casdoor`（拿锁，4.5 秒，`$S/test-db-init-2.log`）：
  ```
    - infra/iam-casdoor
  {"time":"2026-10-02T12:40:34.051310798+02:00","level":"INFO","msg":"迁移结束","direction":"up","schema":"infra_iam_casdoor","outcome":"ok","version":2,"dirty":false}
  {"time":"2026-10-02T12:40:34.099623857+02:00","level":"INFO","msg":"迁移结束","direction":"up","schema":"infra_iam_casdoor","outcome":"ok","version":2,"dirty":false}
  ✓ 迁移幂等
  ✓ brickkit_test_db 就绪——TEST_PG_DSN 现在该指向这个库，不是 brickkit_db
  ```
- 全部测试（`$S/test-v.log`）：12 个包 `ok`，无 FAIL；6 条 SKIP：`TestRun_每一步都幂等可重跑`、`TestRun_webhookCallbackURL为空时跳过webhook步骤`、`TestRun_回调地址或共享密钥变了再跑一遍会更新webhook`、`TestAdminClient与IDTokenVerifier_真机走一遍完整流程`、`TestIDTokenVerifier_拒绝错误issuer`（要 Casdoor）、`TestExchangeTokenAndRefreshToken_端到端对着真实infra_authz走一遍`（要在跑的 infra/authz）。带 `TEST_CASDOOR_BASE_URL=http://localhost:8000` 再跑（`$S/test-v-casdoor.log`）：只剩端到端那 1 条 SKIP，它在 C7 的 `make verify`（test-cross）里必须真跑通过。

**C5 文档（7ec2250）**

八份文件写满。`docs/design.md` 从 `archive/pre-v1/docs/dev/design/infra-iam-casdoor.md` 只取结论，加上本轮新设计；未决问题如实写（见"现象"）。核对：

```
bash dev/phase-06/tools/component-check.sh infra/iam-casdoor
🔎 component-check infra/iam-casdoor（…/components/infra/iam-casdoor，78 个文件）
✅ component-check infra/iam-casdoor：10 项全部 PASS
make docs-boundary → exit=0
make docs-check ID=infra/iam-casdoor
🔎 Only infra/iam-casdoor is checked (brickkit lint --all checks the whole project)
✅ components/infra/iam-casdoor/component.yaml
✅ components/infra/iam-casdoor/ (docs)
ℹ️ infra/iam-casdoor is not in brickkit.yaml yet, so it has no configuration to check (brickkit add --local adds it)

📋 Checked 2 files: 0 with errors, 0 warnings
```

`history_allow`：没有用（manifest-overrides.yaml 本组件没有这一项）。

**C6 版本与门禁**

- 6.1：`component.yaml` 第 7 行 `version: 2.0.0`；`go.mod` 第一行 `module github.com/brickKit/infra-iam-casdoor/v2`。
- 6.3（`$S/c6-component.log`）：`make check-version test contract-check import-scan module-check dag-check` → `exit=0`：
  ```
  ✓ version=2.0.0（go.mod 主版本一致；HEAD 上没有 tag，或 2.0.0 与 v2.0.0 都在）
  （12 个包 ok）
  buf breaking --against '.git#tag=v1.0.10'
  ✓ 无组件间 import
  ✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规
  ✓ 唯一依赖 infra/authz，无环
  ```
- 6.4：component-check `exit=0`（同 C5）。
- 6.5 `bash infra/scripts/project-lock.sh -- make -C $ROOT gates`（`$S/gates.log`，全文读过）→ `exit=0`：
  ```
  ✓ 铁律六 import 扫描：0 条违规
  ✓ SystemClient 误用扫描：0 条违规
  ✓ 裸路由/裸 resolver 扫描：0 条违规
  ✓ 事件契约破坏性变更扫描：0 条违规
  ✓ data-scope-test-scan：0 条违规
  ✓ dependency-version-scan：0 条违规
  ⚠ config/vars.yaml:23：infra-iam-casdoor-2-0-0 对应的组件不在 brickkit.yaml 里，无法核对版本（还没装上它时是预期状态）
  ✓ service-hostname-scan：0 条错误（1 条警告）
  ⚠ components/frontend/standard/component.yaml（组件还在 1.x，naming 违规迁移到 2.x 时改名，现在不计入失败）：gatewayBaseUrl:17[naming] iamIssuerUrl:18[naming] casdoorClientId:24[naming]
  ✓ config-key-scan：0 条违规（另有 1 个 1.x 组件的 3 条 naming 违规只警告，--strict 判红；…）
  ✓ openapi-additive-scan：0 条违规（0 条跳过提示）
  ▸ brickkit up --dry-run …（9 个 2.0.0 组件，生成 compose.yaml，不启动容器）
  ```
  本组件零违规；唯一指向本组件的是 service-hostname-scan 的警告（还没加入项目，C7 之后应消失）。frontend/standard 的警告不归本 Task。
- 发布前门禁自查（锁内，`$S/preship-scans.log`）：
  ```
  ✓ config-key-scan（只看 components/infra/iam-casdoor）：0 条违规
  config-key-scan exit=0
  ✓ openapi-additive-scan（只看 components/infra/iam-casdoor）：0 条违规（0 条跳过提示）
  openapi-additive-scan exit=0
  ```
- 发布说明 `$S/notes-2.0.0.md`：已补"新增 / 修复"两节；"升级前必须做"在生成内容之外有意加了两行（`ENABLED_COMPONENTS` 含义变化、TTL 非正整数启动即报错），下次 `--write` 会因此打印 ⚠️ 漂移，差异只是这两行。

### 现象

- **`WEBHOOK_CALLBACK_URL` 在 v1 下的做法没有一个能同时满足"单独部署"和"外壳托管（T22）"**。查的是 `brickkit docs 01-three-layers/03-deploy-yaml`、`02-project-guide/03-local-debug-workflow`、`04-shell/01-shell-concept`、`04-shell/04-members-management`、`04-shell/05-shell-development`、`06-architecture/04-deploy-file-generation`（没有读 brickKit 源码）：
  - `expose: true` 在 Docker 上映射宿主机端口（`exposePort` 默认组件端口），所以单独部署时 `expose: true` + `http://host.docker.internal:8200/api/iam/webhooks/casdoor` 成立的前提是 Casdoor 容器能解析 `host.docker.internal`。
  - 实测 `be-casdoor` 解析不了：`docker exec be-casdoor sh -c 'getent hosts host.docker.internal || nslookup host.docker.internal'` → `** server can't find host.docker.internal: NXDOMAIN`；`docker inspect be-casdoor` → ExtraHosts `[]`，网络 `be-net=172.18.0.1`（旧值写死的 `172.18.0.1` 就是这个网桥网关）。brickKit 给自己生成的容器都加了 `extra_hosts: host.docker.internal:host-gateway`（`.brickkit/generated/compose.yaml`），但 `be-casdoor` 来自 `infra/docker-compose.infra.yml`，没有这一行。
  - `04-shell/04-members-management` 原文："while a shell hosts it, the fields describing "how its own container is deployed" **do nothing, without a warning**: `expose`, `exposePort`, …"；"A member's port can't be opened to the outside on its own while it's inside a shell; a member that needs its own external exposure shouldn't go into a shell." 也就是说进 go-infra 外壳后 8200 不会映射到宿主机，brief 的候选做法在 T22 不成立。
  - 另一条路：把 `be-casdoor` 接进项目网络 `brickkit-be-assembly-standard-net`，回调地址写成员服务名 `http://infra-iam-casdoor-2-0-0:8200/api/iam/webhooks/casdoor`（外壳容器带全部成员服务名作网络别名，单独与托管都成立），代价是基础资源依赖 brickKit 创建的网络、且地址带版本号（要像 `IAM_JWKS_URL` 一样随发版同步）。
  - 本轮没有替项目选定：组件代码与之无关（就是一个配置值，空 = 不建 webhook）；BRICKKIT 写了单独部署的做法与外壳的限制，docs/design 把两个候选列为未决问题。需要控制者裁定（见交接）。
- `infra.iam.login.v1` 在事件契约里声明了，但代码从来不发；`refresh_tokens` / `signing_keys` / `webhook_deliveries` 的删除与归档都没有实现；Casdoor id_token 的 `aud` 不校验。都写进 docs/design 的未决问题，没有在本轮动（不是本 Task 范围，改了是新行为）。

### 卡点与绕过

- 接手时组件仓库不干净（前一个实现者的半成品）：按 takeover.md 读完 diff 后保留，补测试提交。
- bootstrap / casdoor 的真机测试要 Casdoor 管理员口令：没有读 `.env`；基础资源的 Casdoor 没有改过管理员口令（compose 里没有设口令的项，`scripts/seed.sh` 也用 `admin` / `123`），测试默认值就能登录，全部通过。
- **C7 风险（未核实，因为不能读 `.env`）**：基础资源的 compose 不把 `.env` 的 `CASDOOR_ADMIN_PASSWORD` 交给 Casdoor，Casdoor 用的是镜像默认的管理员口令（上面的真机测试就是用默认值登录成功的）。如果 `.env` 里的 `CASDOOR_ADMIN_PASSWORD` 不是这个值，C7 时组件的管理 API 登录会被拒绝：日志一条 Error，`BatchGetUsers` 回 `UNAVAILABLE`，组织 / 应用 / webhook 不对账（换 token 不受影响，它只走 OIDC 发现）。C7 前请控制者核对。
- 一个提交混入了别的改动：2fdaaea（分区）把 `backend/module/module.go` 的注释清理一起带进去了（同一文件），38ed065 的提交信息里写明了。

### V 项

- V-13（`brickkit add` 重排注释）：C7 的 7.1 才观察，本轮未到。
- V-04（知识缺口）：本轮没有读 brickKit 源码，**无**。`WEBHOOK_CALLBACK_URL` 的结论全部来自 `brickkit docs`（页面见"现象"）。

### 结论

C1–C6 完成：组件仓库 20 个提交（接手后 11 个），`go-v2.sh` 14 条判据、component-check 10 项、docs-check、组件门禁、`make gates`、两个发布前门禁全部通过；测试 12 个包全绿，SKIP 只剩要真实 infra/authz 的端到端 1 条（有 Casdoor 时）。接手后修掉的真实 bug：没有分区维护（2026-10-05 起发事件失败）、webhook 去重竞态、对账途中 Casdoor 抖动后停在旧状态。停在 C7 之前，等控制者确认上游与 `WEBHOOK_CALLBACK_URL` 的做法。

### 反馈候选

- **be-sdk-go**：`Config.IntOr` 在值不是整数时静默返回默认值（"值配了、组件却按默认值跑"，Review Focus 2 的同类）。本组件用自己的 `secondsOr` 绕开；建议 SDK 提供报错的读法（例如 `Int(key) (int, bool, error)`）。
- **be-sdk-go**：分区维护（`backend/internal/partition`）在 mdm/customer、mdm/product、infra/authz、infra/workflow、infra/notification、erp/inventory 与本组件里几乎逐字重复（本组件是第七份）；后台重试（`retryUntilOK`）也是常见样板。建议下沉 SDK（例如 `besdk.StartPartitionMaintainer(db, role, schema, weekly, monthly)`）。漏了这个循环的组件（本组件）所有门禁都是绿的，到期那天才出事。
- **项目 infra**：`infra/docker-compose.infra.yml` 的 `be-casdoor` 没有 `extra_hosts: host.docker.internal:host-gateway`，Casdoor 回调不了任何经宿主机端口暴露的组件（不是 brickKit 的问题）。
- **brickKit（待 T22 真机验证后再定）**：需要被项目网络之外的服务回调的成员（webhook）进了外壳就没有办法单独开放端口；文档说"不该进外壳"，但本项目的 go-infra 外壳计划托管它。验证之前不报给 brickKit。

## infra/iam-casdoor：C7–C9（控制者确认后继续）

### 目标

C7 接入与真机（R56：Casdoor 经项目网络按成员服务名回调 webhook；带真 token 的第一次 `200`；KEEP=1 的手工步骤在同一次持锁里；authz 带真 token 复验；test-cross 真跑 authz 端到端测试），C8 发布说明与组件仓库提交（不推送、不打 tag），C9 补齐记录。

### 环境

brickKit v1.1.0；目标 docker；基础资源 `make check` → `✓ 全部基础资源就绪`；上游复核（1.1）：
```
d4918c67977e8188163887d59ec0cad56b099050	refs/tags/2.0.0
9e443ee2c7a76283c259f097f079f0dc7fae9987	refs/tags/gen/infra/authz/v1.0.5
9033a5f1fafb39cb8e80f1c23eabde864162ee13	refs/tags/v2.0.0
```
开始时本地模式 off、没有本项目容器、项目网络 `brickkit-be-assembly-standard-net` 不存在。

### 步骤

**1. R56：Casdoor 接进项目网络（父仓库文件，未提交）**

先在 scratch 里用两个玩具 compose 项目验证机制（Docker Compose v5.3.1，没有动真实项目）：
- 两边都把同名网络声明成非 external：网络键不同时 `network zzprobe-shared-net was found but has incorrect label com.docker.compose.network set to "pnet" (expected: "bnet")`，后起的项目起不来；键相同时 compose v5 把"别的项目建的"网络当成漂移，先删再建（`Network zzprobe-shared-net Removed` / `error while removing network: … has active endpoints`）。不可用。
- 基础资源一侧 `external: true`，网络预先用 brickKit 的标签建好（`com.docker.compose.project=<brickKit 的 compose 项目>`、`com.docker.compose.network=brickkit-net`）：brickKit 一侧照常 `up`、互相能 ping；brickKit 一侧 `down` 时 `Network zzprobe-shared-net Resource is still in use`，退出码 `b down exit=0`，网络与基础资源容器保留；再 `up` 照常。采用这个。

改动：
- `infra/docker-compose.infra.yml`：新增网络 `brickkit-net: {external: true, name: brickkit-be-assembly-standard-net}`，`casdoor` 的 `networks: [be-net, brickkit-net]`。
- `infra/scripts/lib.sh` 的 `ensure_net`（`make net` / `make up` / `make check` 都先跑它）：网络不存在时带上述两个标签建出来（项目名读 `brickkit.yaml` 的 `project:`）。
- `config/vars.yaml` 新增 `IAM_WEBHOOK_CALLBACK_URL: http://infra-iam-casdoor-2-0-0:8200/api/iam/webhooks/casdoor`，`config/infra-iam-casdoor.yaml` 写 `WEBHOOK_CALLBACK_URL: $var:IAM_WEBHOOK_CALLBACK_URL`。

锁内重建 Casdoor：
```
已创建 brickKit 项目网络 brickkit-be-assembly-standard-net（Casdoor 回调 iam 用）
 Container be-casdoor Recreated
 Container be-casdoor Started
{"com.docker.compose.network":"brickkit-net","com.docker.compose.project":"brickkit-be-assembly-standard"} be-casdoor
casdoor healthy
```
之后多次 `brickkit down`：网络一直在、`be-casdoor` 一直连着；`make check` 仍 `✓ 全部基础资源就绪`。

**2. 密钥与 `.env`（不打印值）**

- `.secrets/infra-iam-casdoor/app-token-signing-key.pem`：从 `.env` 的 `APP_TOKEN_SIGNING_KEY_PEM`（28 行双引号多行值）原样写出、末尾补一个换行，目录 0700、文件 0600，`git check-ignore` → `.gitignore:9:.secrets/`。
- `.env` 追加 `INFRA_IAM_CASDOOR_WEBHOOK_SHARED_SECRET`（值复制自已有的 `WEBHOOK_SHARED_SECRET`）与 `INFRA_AUTHZ_BOOTSTRAP_ADMIN_SUB`（`sub_of dev.superuser`，长度 36，C7 第一轮锁内写入）。

**3. `make integrate ID=infra/iam-casdoor`**

第一次（`$S/integrate-1.log`）：db-init `✓`；`brickkit add` → `➕ Adding infra/iam-casdoor@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml`、`📝 Config skeletons: config/infra-iam-casdoor.yaml`；config-fill 写了 `PG_PASSWORD, PG_USER, PG_SCHEMA`，列出 5 个要人给的键后 exit（预期）。按 brief 的"配置值"一栏锁内 `config-fill.py --set` 六个键（含 `WEBHOOK_CALLBACK_URL=$var:IAM_WEBHOOK_CALLBACK_URL`）：`写了 6 个键`。为 Review Focus 2 临时把 `APP_TOKEN_TTL_SECONDS` 设成 900（验完已还原成注释掉的默认）。第二次（`$S/integrate-2.log`）：
```
✓ deploy.teardown.yaml 已从 deploy.yaml 同步（target、components；不带 vars:）
✅ infra/iam-casdoor: configuration (config/ ↔ configSchema)
📋 Checked 3 files: 0 with errors, 0 warnings
   ✅ infra/iam-casdoor@2.0.0        starting (top-level)
   infra/iam-casdoor@2.0.0 → infra/authz@2.0.0
✓ integrate infra/iam-casdoor@2.0.0 完成
```
`up --dry-run` 在 TTL 临时取消注释期间打印 `⚠️ Files under config/ may contain plaintext secrets … infra/iam-casdoor@2.0.0 → APP_TOKEN_TTL_SECONDS`（按键名里的 TOKEN 判的，见反馈候选）；还原后最终 verify 的 `up.log` 里 0 处。V-13：`git diff brickkit.yaml deploy.yaml` 只有追加的两行，没有重排注释。

**4. 第一轮真机（锁内：verify SEED=1 KEEP=1 → 手工核对 → down，`$S/c7a.log`）**

verify 表里"带 token → 200"一行 `FAIL 实际 400`：`POST /api/iam/logout` 的契约要求请求体 `refresh_token`（`required: true`，缺了回 400），verify 只发不带请求体的请求。400 说明鉴权已通过（不是 401/403）；第三轮手工带真实请求体核对为 200（见下）。其余手工核对：
```
✓ 与文件逐字节相同                          （容器内 printf %s "$APP_TOKEN_SIGNING_KEY_PEM" 与 .secrets 文件的 sha256 相同）
authz seed exit=0
JWKS kids: ['7PccEUtDTZGWMPGZ2EQ5ab5bcXJm-AdCnLss4uI6ygg'] token kid: 7PccEUtDTZGWMPGZ2EQ5ab5bcXJm-AdCnLss4uI6ygg alg: RS256
✓ JWKS 公钥验签通过；sub 长度 36 ；exp-iat = 900 （config 配的 APP_TOKEN_TTL_SECONDS=900）
GET /api/tenant/features → 200
✓ 集合相等                                  （enabled_components = brickkit.yaml 非外壳 ID，10 个）
webhook brickkit-user-events url= http://infra-iam-casdoor-2-0-0:8200/api/iam/webhooks/casdoor enabled= True …
投递行数（触发前）：5   投递行数（触发后）：13
13|11:33:35|update-user|IGNORED|payload 里找不到用户标识
6|11:33:35|login|IGNORED|payload 里找不到用户标识
```
**R56 判据成立**：Casdoor 的 POST 经项目网络按成员服务名到达 iam（iam 日志 `"path":"/api/iam/webhooks/casdoor","status":200`，`webhook_deliveries` 落库）。但每一条都是 `IGNORED`——真实 bug，见第 5 步。

**5. 真实 bug：投递体的 `object` 是 JSON 字符串（ab1e9a0）**

只列键、不打印值地读真机投递：顶层键 `action, clientIp, createdTime, detail, extendedUser, id, isTriggered, language, method, name, object, organization, owner, requestUri, response, statusCode, user`；`object` 是**字符串**，解开后 update-user 是整个用户对象（`id` 等于 dev.finance.viewer 的 sub，`password` 已掩码 `***`），login 是登录表单（`application, autoSignin, organization, password(***), type, username`，没有 id）；`user` 是 `admin`（发起者）；`extendedUser` 为 null。旧代码只按对象解 `object`。
红（`$S/red-webhook-object-string.log`）：
```
    webhook_test.go:49: Sub() = ""，期望从字符串形式的 object 里取出 "915d1763-586b-4526-a9d8-589194a624f5"
--- FAIL: TestWebhookUserPayload_object是JSON字符串时也能取出用户字段 (0.00s)
    webhook_test.go:74: 投递状态 = IGNORED（payload 里找不到用户标识），期望 PROCESSED
--- FAIL: TestHandleWebhookDelivery_真机形状的update_user标PROCESSED并写进outbox (0.14s)
```
绿（`$S/green-webhook-object-string.log`）：两条 PASS，service 包 `ok`。文档跟上（316cbf1、73eddbd、ed1f2df，见第 7 步）。

**6. 第二、三轮真机（锁内，`$S/c7b.log`、`$S/c7c.log`）**

第二轮发现 **test-cross 是空跑**：`test-cross.log` 第二行 `（无强依赖，等价于 make test）`，端到端测试 `--- SKIP: … 未设置 INFRA_AUTHZ_GRPC_ENDPOINT`。原因：`infra/scripts/test-cross.sh` 用 awk 按行找 `  components:` 下一行起的 `id@`，2.0.0 清单是流式写法 `components: [infra/authz@2.0.0]`，一条都数不到。**所有有依赖的 2.0.0 组件（crm/opportunity、erp/sales、infra/bff-mobile、本组件）的 test-cross 此前都是空跑、汇总表照样 PASS。** 改成按 YAML 解析（父仓库文件，未提交）：必需依赖照旧桥接，可选依赖容器不在时只提示不桥接；解析结果核对：iam → `infra/authz optional=0`；sales → 4 个必需 + `infra/workflow optional=1`；bff-mobile → 7 个可选；mdm/product → 无。

第二轮还看清了 Casdoor 的投递节奏（对照 `casdoor.record`）：约每 30 秒成批发一次；失败的发送记成单独一条 `send-webhook` 记录（`Post "http://infra-iam-casdoor-2-0-0:8200/…": dial tcp: lookup infra-iam-casdoor-2-0-0 … server misbehaving`），原记录 `is_triggered=t`、不重投。第二轮的触发正好落在 down 之后的那一批，丢了。`add-user` / `delete-user`（C4 时 bootstrap 测试经管理 API 建删的用户）投递的 `object` 只有请求体：add-user 8 个键、delete-user 只有 owner 与 name，都没有 `id` → `IGNORED`。

第三轮（FORCE_BUILD=1，修复后的镜像 13:45:46，脚本轮询等下一批）：
```
✓ 容器内与文件逐字节相同（sha256 985aa177fe02e750…）
    INFRA_AUTHZ_GRPC_ENDPOINT=http://localhost:20223
=== RUN   TestExchangeTokenAndRefreshToken_端到端对着真实infra_authz走一遍
--- PASS: TestExchangeTokenAndRefreshToken_端到端对着真实infra_authz走一遍 (0.88s)
换 token 响应键： ['access_token', 'expires_in', 'refresh_token', 'token_type'] expires_in = 900
POST /api/iam/logout 带 token + refresh_token → 200（期望 200）；带 token 不带请求体 → 400（契约的 400）；登出后用这个 refresh token 刷新 → 401（期望 401）
26|login|IGNORED|payload 里找不到用户标识
30|update-user|PROCESSED|
31|update-user|PROCESSED|
infra.iam.user.updated.v1|915d1763|t|0|「本地测试」财务只读
infra.iam.user.updated.v1|915d1763|t|0|「本地测试」财务只读·
```
webhook → `PROCESSED` → outbox → 已发布（`published_at` 非空）。**但顺序错了**：两次 update-user 先改成"…·"、再改回原值，同一秒（`createdTime` 都是 `2026-10-02T11:46:29Z`），Casdoor 按新到旧投递（record 2090 原值先到、2089 带"·"后到），本组件按处理时刻给 `version`（…358612765 原值、…367216054 带"·"），下游会留下旧值。未修，写进 docs/design 的未决问题，待裁定（见结论）。

**7. 文档与提交（组件仓库）**

- 316cbf1：BRICKKIT（中英）部署前准备改为 R56 的做法；加"Casdoor 镜像自带默认管理员口令，生产必须与 `CASDOOR_ADMIN_PASSWORD` 一起改"；`WEBHOOK_CALLBACK_URL` 一行与外壳声明跟上；docs/design 加"Casdoor 怎么到达 webhook""一次投递长什么样"；AGENTS 易错点加一行；admin.go、service.go 注释去掉"经 expose 的宿主机端口"。
- 73eddbd：30 秒成批、失败不重投、增删用户不带 ID 写进 BRICKKIT 契约索引与 docs/design 未决问题。
- ed1f2df：同批乱序写进未决问题。
- 每次改完：`make docs-check ID=infra/iam-casdoor` → `0 with errors, 0 warnings`；component-check `10 项全部 PASS`；`make docs-boundary` exit 0；组件门禁（`TEST_CASDOOR_BASE_URL` 设上）exit 0，12 个包 ok，`buf breaking --against '.git#tag=v1.0.10'`；`go-v2.sh --recheck` exit 0、`📌 … gen/infra/iam/v1.0.0`。
- `assembly.yaml` 的 edge_routes 注释仍写"走 expose 的宿主机端口 + 桥接网关 IP"，已过时；手改会被 migrate-manifest 的手改保护拒绝，overrides 不管注释，没有动（交控制者）。

**8. 最终验证（docs 改完之后，FORCE_BUILD=1，`$BE_SCRATCH/verify/infra-iam-casdoor-final/`）**

`make verify ID=infra/iam-casdoor ROUTE='POST /api/iam/logout' FOCUS=1 SEED=1 FORCE_BUILD=1`（exit 2，唯一 FAIL 是上面说的 400）：

| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build infra/iam-casdoor | PASS |  | build.log |
| 镜像 infra-iam-casdoor:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| infra-iam-casdoor-2-0-0 running (healthy)（容器服务 infra-iam-casdoor-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| POST /api/iam/logout 不带 token → 401/503 | PASS | 实际 401 | http.log |
| POST /api/iam/logout 带 token → 200 | FAIL | 实际 400 | http.log |
| make -C components/infra/iam-casdoor seed | PASS |  | seed.log |
| make test-cross ID=infra/iam-casdoor | PASS |  | test-cross.log |
| focus：宿主机 http://localhost:8200/healthz → 200 | PASS |  | focus.log |
| brickkit up --all --dry-run（清除 focus） | PASS |  | focus-all-dry-run.log |
| brickkit local off | PASS |  | local-off.log |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |

test-cross.log 第二行 `    INFRA_AUTHZ_GRPC_ENDPOINT=http://localhost:20223`，12 个包 ok。focus.log：`infra-iam-casdoor-2-0-0  listening on port 8200`；本机进程连不上 Casdoor（`lookup host.docker.internal on 127.0.0.53:53: no such host`，Warn 后台重试）——`CASDOOR_BASE_URL` 是写在组件自己配置里的字面量，verify 只改写 `config/vars.yaml` 里含 `host.docker.internal` 的值（R39）；focus 只验 `/healthz`，符合 7.4 的预期。

authz 复验 `make verify ID=infra/authz ROUTE=/api/admin/roles`（exit 0，`$BE_SCRATCH/verify/infra-authz-with-iam/`）：

| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build infra/authz | PASS |  | build.log |
| 镜像 infra-authz:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| infra-authz-2-0-0 running (healthy)（容器服务 infra-authz-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| GET /api/admin/roles 不带 token → 401/503 | PASS | 实际 401 | http.log |
| GET /api/admin/roles 带 token → 200 | PASS |  | http.log |
| make -C <源目录> seed | SKIP | 没设 SEED=1 |  |
| make test-cross ID=infra/authz | PASS |  | test-cross.log |
| brickkit up --focus infra/authz | SKIP | 没设 FOCUS=1 |  |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |

`BOOTSTRAP_ADMIN_SUB` 生效：`infra_authz.user_roles` 里 dev.superuser 有 `dev_superuser`（11:33，authz seed）与 `authz_admin`（11:38，写进 `.env` 之后 authz 第一次启动时自举）。收尾：`Local mode: off`、`deploy.local.yaml: none`、无本项目容器、项目根没有 `deploy.verify.yaml`。

**9. 门禁（锁内 `make gates`，`$S/gates-c7.log`）**：exit 0；`✓ service-hostname-scan：0 条错误（0 条警告）`（C6 时的"组件不在 brickkit.yaml 里"警告消失）；其余 9 个门禁 0 违规，frontend/standard 的 naming 警告不归本 Task。覆盖核对：scratch 副本里把 `IAM_WEBHOOK_CALLBACK_URL` 改成 `infra-iam-casdoor-1-0-10` → `✗ config/vars.yaml:27：infra-iam-casdoor-1-0-10 与 brickkit.yaml 不一致——infra/iam-casdoor 声明的服务名是 infra-iam-casdoor-2-0-0`，exit 1。门禁按正则扫 `config/*.yaml` 里每一个版本化 URL，第三个 URL 不需要扩展门禁。发布前门禁：`openapi-additive-scan` 与 `config-key-scan --strict`（`--only infra/iam-casdoor`）都 exit 0。

**C8**：`$S/notes-2.0.0.md` 补了两条（新增：BRICKKIT 写明回调做法；修复：object 是 JSON 字符串）；`migrate-manifest.py --check` 全部"无"、exit 0；"升级前必须做"与 generated 的差异只有 C6 时有意加的两行（`ENABLED_COMPONENTS` 含义、TTL 非正整数启动报错）。
```
git -C components/infra/iam-casdoor log --oneline -3
ed1f2df docs: 未决问题加一条——同一批里同一用户的两次修改会以错误顺序到达下游
73eddbd docs: 写下真机看到的 Casdoor 投递行为（30 秒成批、失败不重投、增删用户不带 ID）
316cbf1 docs: webhook 回调改走成员服务名（R56），写下真机抓到的投递体形状
```
`## main...origin/main [ahead 24]`，工作区干净，未推送、未打 tag。

### 现象

- 符合预期：R56 回调通路（单独部署）；多行 PEM 运行期逐字节一致；JWKS 能验 token；`APP_TOKEN_TTL_SECONDS` 非默认值从行为上生效（exp−iat=900、`expires_in = 900`）；`ENABLED_COMPONENTS` = brickkit.yaml 的非外壳 ID；带真 token 登出 200、登出后刷新 401；authz 带 token 200；BOOTSTRAP_ADMIN_SUB 自举成功；`brickkit down` 不删被基础资源占用的项目网络。
- 不符合预期：webhook 全部 IGNORED（已修）；test-cross 空跑（父仓库脚本已改，未提交）；verify 的带 token 一项对需要请求体的路由判 FAIL；同批乱序（未修）；停机期间投递丢失、增删用户不带 ID（Casdoor 行为，写进未决问题）。

### 卡点与绕过

- 读了 `brickkit docs 06-architecture/04-deploy-file-generation`（网络名 `brickkit-<project>-net`、compose 项目名 `brickkit-<project>`）与 `01-three-layers/03-deploy-yaml`（示例里网络键 `brickkit-net`）、`03-component-guide/02-component-yaml-reference`（optional 依赖写法）；没有读 brickKit 源码。compose 的网络标签行为用 scratch 里的玩具项目实测。
- 改了 brief 没点名的两个父仓库脚本：`infra/scripts/lib.sh`（R56 必需：网络要在 `make up` 之前存在）、`infra/scripts/test-cross.sh`（裁定要求 test-cross 真跑端到端测试，不改就跑不到）。都未提交，交控制者。

### V 项

- V-13：`brickkit add` 没有重排 `brickkit.yaml` / `deploy.yaml` 的注释（diff 只有追加行）。
- V-04（知识缺口）：无（没有读 brickKit 源码）。

### 结论

C7–C9 完成，交接状态 DONE_WITH_CONCERNS。组件仓库新增 4 个提交（ab1e9a0、316cbf1、73eddbd、ed1f2df），HEAD ed1f2df，未推送、未打 tag；契约包需要 `gen/infra/iam/v1.0.0`。本轮修掉的真实 bug：webhook 投递从来解析不出用户（`infra.iam.user.*.v1` 从来没发过）。待控制者裁定：同批乱序（候选：每次投递按 sub 读 Casdoor 当前用户再发 / `version` 以 `createdTime` 为基础）；verify 的带 token 检查对 logout 判 400（换路由或让 verify 支持请求体）；test-cross.sh 修复影响其它有依赖组件此前的 test-cross 结论。

### 反馈候选

- **项目 infra（直接改，已在工作区）**：test-cross.sh 不认流式依赖写法，所有有依赖的 2.0.0 组件 test-cross 空跑而汇总表 PASS（与 C4 时 Makefile `dag-check` 的同一类坑）。crm/opportunity、erp/sales、infra/bff-mobile 的 test-cross 结论需要重跑。
- **项目 infra**：verify 的"带 token → 200"不能给 ROUTE 带请求体；本组件唯一的 `Authenticated` 路由需要请求体。建议 `ROUTE_BODY=` 或允许 brief 写期望码。
- **项目 infra**：`CASDOOR_BASE_URL` 若改成 `config/vars.yaml` 的共享变量，focus 时会被 R39 的 host-gateway 改写，本机进程也能连上 Casdoor。
- **brickKit（待验证，进 to-verify）**：`up` 的"明文密钥"提醒按键名判，`APP_TOKEN_TTL_SECONDS: 900`（键名含 TOKEN，整数）被列为可能的明文密钥；文案里已说明"只按名字判"，影响小。
- **brickKit（待验证）**：基础资源要加入项目网络时，只能照 brickKit 生成文件的内部约定（compose 项目名、网络键 `brickkit-net`）预先打标签建网络；文档写了网络名与项目名，网络键只出现在示例里。若这些算稳定约定，建议文档明说；或者提供"项目网络由外部提供（external）"的开关。
- **be-sdk-go**（C6 已列）：`Config.IntOr` 静默回默认值；分区维护下沉 SDK。

---

## R61：用户事件回读 Casdoor（发布前修复，2026-10-02）

### 目标

裁定 R61：每次 Casdoor webhook 投递都回 Casdoor 读这个人的当前状态再发 `infra.iam.user.*.v1`，投递以什么顺序到达，下游留下的都是最新状态。版本号二选一（每人计数 / 处理时刻）并写明理由；人已不在 Casdoor 时发删除事件；只带 owner/name 的投递经回读找到人，核对之前的 `IGNORED` 是否随之解决。组件仍是 2.0.0，未发布。

### 环境

起点 HEAD ed1f2df；brickKit CLI v1.1.0；be-sdk-go v0.4.0；基础资源 be-postgres / be-nats / be-casdoor 在跑（`TEST_CASDOOR_BASE_URL=http://localhost:8000`）；测试库 brickkit_test_db（`make test-db-init ID=infra/iam-casdoor` 后迁移到第 3 版）。scratch：`$S` = `$BE_SCRATCH/06b/infra-iam-casdoor/`。

### 步骤

**1. 设计（重构许可）**：照投递体发事件这个设计本身不对——投递体只能说明"谁变了"，Casdoor 一批里的记录不按可靠顺序发、`createdTime` 只到秒。改成：投递体只取 `id`（没有时取 owner/name）；在登记投递的同一个事务里 ① upsert `user_event_versions` 这个人那一行取 `version = max(处理时刻纳秒, 上一版+1)`（行锁到提交）→ ② 回读 Casdoor（`GET /api/get-user?userId=` / `?id=<owner>/<name>`，真机先核对过两种查法与查不到时 `data:null`）→ ③ 人不在 / `isForbidden` / `isDeleted` → `disabled`，新建动作 → `created`，其余 → `updated`。读不回 → 503、事务回滚、投递不登记。

版本号选"每人计数、下限是处理时刻纳秒"，理由（写进 docs/design "为什么是这个版本号"）：行锁把"回读"与"定版本号"绑在一起（只取时间戳不加锁，两次并发投递可能按一种顺序读、按另一种顺序定版本号）；下限让新版本号不小于消费者可能已存着的纳秒时间戳版本号；`+1` 不怕副本时钟不齐或回拨。"删除事件"按契约发 `infra.iam.user.disabled.v1`（契约 note 明写删除也发这条、不设 deleted），没有新增 subject。

**2. 提交与红绿（组件仓库）**

- bfb564e feat(casdoor)：`GetUserByName`，`User` 加 `Owner/Name/IsForbidden/IsDeleted`。真机流程测试加按名查询、查不到、停用后 `isForbidden=true`。新方法与测试同时写成，没有单独的红（提交信息写明）。
- 5fbdd4f refactor(service)：`UserReader` 接口 + `SetUserReader`，module 接上后台登录得到的管理会话；测试加 `fakeUsers`。行为不变，全绿。
- 440167e fix(webhook)：红（`$S/red-r61-readback.log`，原文）：
```
    webhook_readback_test.go:106: 下游最后留下 infra.iam.user.updated.v1 display_name="旧"，期望 updated 且是 Casdoor 当前的值 "新"
--- FAIL: TestWebhook_两次修改倒序到达_下游留下的是最新状态 (0.14s)
    webhook_readback_test.go:143: 第一次投递一直没有回读 Casdoor
--- FAIL: TestWebhook_同一用户两次投递并发_后回读的拿到更大的版本号 (5.02s)
    webhook_readback_test.go:177: Casdoor 里已没有这个人，期望 disabled，实际 {Subject:infra.iam.user.updated.v1 Version:1790943756203677518 Payload:{Sub:casdoor-uuid_1790943756203594286_9 DisplayName:王五 Email: Phone: Version:1790943756203677518}}（有事件=true）
--- FAIL: TestWebhook_update_user到达时人已被删_发disabled (0.10s)
    webhook_readback_test.go:192: Casdoor 里这个人已停用，期望 disabled，实际 {Subject:infra.iam.user.updated.v1 Version:1790943756331697131 Payload:{Sub:casdoor-uuid_1790943756331614880_12 DisplayName: Email: Phone: Version:1790943756331697131}}（有事件=true）
--- FAIL: TestWebhook_update_user把人停用_发disabled (0.12s)
    webhook_readback_test.go:214: add-user 投递状态 IGNORED（payload 里找不到用户标识），期望 PROCESSED
--- FAIL: TestWebhook_只带owner与name的增删用户_经回读找到sub (0.12s)
--- PASS: TestWebhook_只带owner与name且查不到的人_标IGNORED (0.06s)
    webhook_readback_test.go:259: 期望 ErrUnavailable，实际 <nil>
--- FAIL: TestWebhook_Casdoor会话未就绪_回Unavailable且不登记 (0.05s)
--- PASS: TestWebhook_login不回读Casdoor_标IGNORED (0.13s)
--- PASS: TestWebhook_版本号每人单调且不小于处理时刻纳秒 (0.11s)
FAIL
```
  绿（`$S/green-r61-readback.log`，`-race`）：上面 9 条与 `TestWebhookUserPayload_object是JSON字符串时也能认出是谁` 全部 PASS；另加 REST `TestREST_webhook读不回Casdoor用户时回503` PASS。变异核对（`$S/mutation-r61-lock-order.log`）：把"先取版本号后回读"倒过来，并发测试红 `下游最后留下 display_name="第一次"，期望 Casdoor 的最新值 "第二次"`，已还原。测试改动：解析测试改名、去掉"displayName/email 来自投递体"的断言（事件字段不再取自投递体，由回读测试断言）；repo 三条 RecordDelivery 测试只改签名，断言不变——都写在提交信息里。同一提交：迁移 003 `user_event_versions`；`RecordDeliveryAndPublish` → `RecordDelivery(handle)`；openapi webhook 加 `503`、去掉过时的 expose 描述；事件契约 note 只改说明文字；created/updated 开始填契约已声明的 `im_accounts`。
- 790910a docs：design / BRICKKIT / AGENTS / README 中英同步。

**3. 门禁**：`TEST_CASDOOR_BASE_URL=http://localhost:8000 make check-version test contract-check import-scan module-check dag-check` exit 0（`$S/gates-r61.log`，12 个包 ok）；不设 Casdoor 时 SKIP 仍是 6 条（与 AGENTS 写的一致）；`make docs-check ID=infra/iam-casdoor` → `0 with errors, 0 warnings`；component-check `10 项全部 PASS`；`make docs-boundary` exit 0；`migrate-manifest.py --check` 全部"无"；`go-v2.sh --recheck` exit 0、`📌 … gen/infra/iam/v1.0.0`（proto 没动）；发布前 `openapi-additive-scan` / `config-key-scan --strict`（`--only infra/iam-casdoor`）rc=0。

**4. 真机（同一次持锁：verify KEEP=1 → 手工核对 → down，`$S/c7d.log`，手工脚本 `$S/c7d-manual.sh`）**

`make verify ID=infra/iam-casdoor ROUTE='POST /api/iam/logout' KEEP=1 FORCE_BUILD=1`（exit 2，唯一 FAIL 是已知的 400：路由要求请求体），`$BE_SCRATCH/verify/infra-iam-casdoor-r61/`：

| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build infra/iam-casdoor | PASS |  | build.log |
| 镜像 infra-iam-casdoor:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| infra-iam-casdoor-2-0-0 running (healthy)（容器服务 infra-iam-casdoor-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| POST /api/iam/logout 不带 token → 401/503 | PASS | 实际 401 | http.log |
| POST /api/iam/logout 带 token → 200 | FAIL | 实际 400 | http.log |
| make -C <源目录> seed | SKIP | 没设 SEED=1 |  |
| make test-cross ID=infra/iam-casdoor | PASS |  | test-cross.log |
| brickkit up --focus infra/iam-casdoor | SKIP | 没设 FOCUS=1 |  |
| brickkit down | SKIP | KEEP=1：容器保留，用完 brickkit down -f deploy.verify.yaml |  |

test-cross.log：`INFRA_AUTHZ_GRPC_ENDPOINT=http://localhost:20223`，12 个包 ok，无 FAIL。

手工核对原文：
```
== iam 容器：brickkit-be-assembly-standard-infra-iam-casdoor-2-0-0-1；镜像创建时间 2026-10-02T14:32:03.738365169+02:00
== ① 两次快速修改（同一秒），下游应留下后一次
  原值 '「本地测试」财务只读' → 先改 '「本地测试」财务只读·A' → 再改 '「本地测试」财务只读·B'
  update-user: ok 
  update-user: ok 
  Casdoor 当前 displayName：'「本地测试」财务只读·B'
-- 投递（按到达顺序）
  41|login|IGNORED|无法从 action 推出事件类型: login| createdTime=2026-10-02T12:32:37Z object.displayName=None object.keys=application,autoSignin,organization,type,username
  42|update-user|PROCESSED|| createdTime=2026-10-02T12:32:38Z object.displayName='「本地测试」财务只读·B' object.keys=(整个用户对象)
  43|update-user|PROCESSED|| createdTime=2026-10-02T12:32:38Z object.displayName='「本地测试」财务只读·A' object.keys=(整个用户对象)
-- outbox（sub 前 8 位 915d1763）
  id=3 infra.iam.user.updated.v1 version=1790944385335216015 published=t display_name='「本地测试」财务只读·B' payload.version=1790944385335216015
  id=4 infra.iam.user.updated.v1 version=1790944385369671781 published=t display_name='「本地测试」财务只读·B' payload.version=1790944385369671781
  → 下游（只接受 version 更大的）留下：infra.iam.user.updated.v1 display_name='「本地测试」财务只读·B'
== ② 还原原值，下游应留下原值
  update-user: ok 
  44|update-user|PROCESSED|| createdTime=2026-10-02T12:33:08Z object.displayName='「本地测试」财务只读' object.keys=(整个用户对象)
  id=5 infra.iam.user.updated.v1 version=1790944415329529070 published=t display_name='「本地测试」财务只读' payload.version=1790944415329529070
  → 下游（只接受 version 更大的）留下：infra.iam.user.updated.v1 display_name='「本地测试」财务只读'
== ③ 只带 owner/name 的 add-user，再只带 owner/name 的 delete-user（之前都是 IGNORED）
  add-user: ok 
  探针 sub 前 8 位：e0e8430c
  45|add-user|PROCESSED|| createdTime=2026-10-02T12:33:39Z object.displayName='R61 探针' object.keys=displayName,email,name,owner,type
  id=6 infra.iam.user.created.v1 version=1790944445348052475 published=t display_name='R61 探针' payload.version=
  → 下游（只接受 version 更大的）留下：infra.iam.user.created.v1 display_name='R61 探针'
  delete-user: ok 
  46|delete-user|PROCESSED|| createdTime=2026-10-02T12:34:10Z object.displayName=None object.keys=name,owner
  id=6 infra.iam.user.created.v1 version=1790944445348052475 published=t display_name='R61 探针' payload.version=
  id=7 infra.iam.user.disabled.v1 version=1790944475337996419 published=t display_name='' payload.version=
  → 下游（只接受 version 更大的）留下：infra.iam.user.disabled.v1 display_name=''
-- user_event_versions（两个 sub）
915d1763|1790944415329529070|brickkit|dev.finance.viewer
e0e8430c|1790944475337996419|brickkit|r61probe1790944419
-- iam 的 WARN/ERROR 日志（最后 10 条）
== 手工核对结束
```
收尾（同一次持锁）：`brickkit down -f deploy.verify.yaml` → `✅ All components stopped`；`Local mode: off`、`deploy.local.yaml: none`；本项目容器 0 个；项目根没有 `deploy.verify.yaml`。dev.finance.viewer 已还原原值；探针用户已删除。

### 现象

- Casdoor 再次按新到旧投递同一秒（`12:32:38Z`）的两条 update-user：42 号投递体是"·B"、43 号是"·A"。两条事件都是回读到的"·B"，后处理的那条 version 更大；下游留下"·B" = Casdoor 当前值。修复前同样的场景下游留下的是较旧的值。
- 只带 owner/name 的 add-user（object 键 `displayName,email,name,owner,type`，没有 id）→ `PROCESSED`、`created`；只带 `name,owner` 的 delete-user（人已不在 Casdoor）→ 按 `user_event_versions` 记下的名字找到 sub → `PROCESSED`、`disabled`。之前这两种都是 `IGNORED`，已解决。
- login 照旧 `IGNORED`，原因文字变成"无法从 action 推出事件类型: login"（先判动作、再找人）。
- iam 日志 0 条 WARN/ERROR。

### 卡点与绕过

无。verify 的"带 token"一行仍是已知的 400（logout 要求请求体），本轮未处理。没有读 brickKit 源码。

### 结论

R61 完成：组件仓库 4 个新提交（bfb564e、5fbdd4f、440167e、790910a），HEAD 790910a，未推送、未打 tag，版本仍 2.0.0；契约包 tag 仍是 `gen/infra/iam/v1.0.0`（proto 没动）。新增迁移 003（`user_event_versions`），发布说明 `$S/notes-2.0.0.md` 的"新增"加两条、"修复"加两条（行为变化写明：事件不再取自投递体、停用发 disabled、读不回 503）。剩下的限制写进 docs/design 未决问题：从没见过名字的人的最小请求体 delete-user、同一批里最小请求体的 add+delete，仍是 `IGNORED`（这样的人从没到过下游）；回 503 的投递 Casdoor 不重投，与停机期间一样会丢。

### 反馈候选

- 项目 infra（已列过）：verify 的"带 token → 200"不能给 ROUTE 带请求体。
- 无新的 brickKit 反馈。

## 发布前最后一轮：be-sdk-go v0.5.0、依赖 authz 2.0.1、种子说明、assembly 注释（2026-10-02）

### 目标

1. be-sdk-go 升到 v0.5.0，确认本组件不依赖"空 dept_path = 看全部"、也从不写哨兵（R60）。
2. 依赖从 `infra/authz@2.0.0` 改钉 `infra/authz@2.0.1`（overrides 的 `deps_pin`），契约包 require 仍是 `gen/infra/authz v1.0.5`。
3. `scripts/seed.sh` 里 dev.superuser"无部门归属"的说法改成 authz 2.0.1 种子的实际归属（根部门 `/1/`）。
4. 清掉 `assembly.yaml` 里过时的 expose 注释。
5. 全部检查重跑；真机 integrate + verify（带 ROUTE_BODY），test-cross 对着 authz 2.0.1 跑端到端测试。

### 环境

brickKit CLI v1.1.0；组件 HEAD 起点 790910a；基础资源 be-postgres / be-nats / be-casdoor 在跑；开始时没有项目容器、本地模式 off。日志目录 `$S/r-final/`，verify 输出 `$BE_SCRATCH/verify/infra-iam-casdoor-final2/`。

### 步骤

**1. be-sdk-go v0.5.0**：`go get github.com/brickKit/be-sdk-go@v0.5.0 && go mod tidy && go build ./... && go vet ./...` → `go: upgraded github.com/brickKit/be-sdk-go v0.4.0 => v0.5.0`，只改 go.mod / go.sum。核对：`grep -rn -i 'dept\|ScopeOf\|NoDeptPath'` 只命中 tokens.go（Claims.DeptPath 原样拷贝，`json:"dept_path"` 无 omitempty）、service.go:206（`DeptPath: resp.DeptPath`）、http.go:108（`besdk.ScopeOf(...).Owner`，只用 Owner）；没有任何地方判断 dept_path 是否为空，没有 NoDeptPath。新增守护测试 `TestSignAccessToken_dept_path原样抄进token不替换`（""、"/"、"/1/"、"/1/12/" 签出再解开等于原值且不是哨兵）：行为本来就对，直接绿；变异核对（SignAccessToken 把空串换成 "/"）→ `tokens_test.go:201: dept_path 应原样是 ""，实际 "/"` FAIL，已还原。提交 5cedbb2、3af7a1a。

**2. 依赖 authz 2.0.1**：`manifest-overrides.yaml` 的 infra/iam-casdoor 段加 `deps_pin: {infra/authz: 2.0.1}`（未提交），`migrate-manifest.py infra/iam-casdoor --write` exit 0：
```
  ✏️  component.yaml：已重写
-  components: [infra/authz@2.0.0]
+  components: [infra/authz@2.0.1]
  assembly.yaml：未改动（已是目标内容）
  ⚠️  notes-2.0.0.md 的"## 升级前必须做"一节与重新生成的不同
```
漂移只是 C6 起有意加的两行（ENABLED_COMPONENTS 含义、TTL 非整数报错）。go.mod 的 `gen/infra/authz v1.0.5` 不变。提交 d0824f5。

**3. 种子说明**：`scripts/seed.sh` 头部表改为 dev.superuser 根部门「本地测试」总公司（/1/）、销售 /1/2/、仓管 /1/3/、财务只读不分部门（dept_path 为空），并补一段"空 dept_path 不是看全部"。路径以演示库实查为准：`infra_authz.departments` = `1|「本地测试」总公司||/1/`、`2|…华东分部|1|/1/2/`、`3|…华南分部|1|/1/3/`；`user_departments` 里 e88c4f5a（dev.superuser）→ 1。seed-clean.sh 与组件文档里没有同类说法；docs/design（中英）职责表补"原样转抄、空串不换成 /"。提交 c6139f7。

**4. assembly.yaml 注释**：edge_routes 注释改成按 IAM_JWKS_URL / WEBHOOK_CALLBACK_URL（项目网络、版本化服务名）直连；data_scopes 注释"四张表"补上 user_event_versions。YAML 解析前后相等。手改保护：之后 `--write` → exit 3，diff 只是这两段注释（`$S/r-final/mm-write-after-comment.log`）。overrides 带不了注释，`--force` 会把注释还原成 tag 版，所以保留手改，没跑 `--force`。提交 f1a02b5。

**5. 检查**（全部 exit 0）：
- `go-v2.sh infra/iam-casdoor --recheck` → `✅ go-v2.sh：判据全部 PASS`，`📌 … gen/infra/iam/v1.0.0`
- `component-check.sh` → `✅ component-check infra/iam-casdoor：10 项全部 PASS`
- `make docs-check ID=infra/iam-casdoor` → `📋 Checked 3 files: 0 with errors, 0 warnings`
- `migrate-manifest.py --check` → `依赖: ['infra/authz@2.0.1']`、`✅ --check 全部为"无"`；`brickkit lint infra/iam-casdoor` 0 errors 0 warnings
- `make test` 12 个包 ok、6 条 SKIP（5 条要 Casdoor、1 条 authz 端到端）；`TEST_CASDOOR_BASE_URL=http://localhost:8000` 下只剩 `--- SKIP: TestExchangeTokenAndRefreshToken_端到端对着真实infra_authz走一遍`
- 组件门禁 `make check-version test contract-check import-scan module-check dag-check`（设 Casdoor）→ `✓ version=2.0.0`、`buf breaking --against '.git#tag=v1.0.10'`、`✓ 无组件间 import`、`✓ 入口签名对…`、`✓ 唯一依赖 infra/authz，无环`
- `make test-db-init ID=infra/iam-casdoor` → `version":3,"dirty":false` ×2、`✓ 迁移幂等`
- 持锁 `make gates` exit 0：`✓ dependency-version-scan：0 条违规`、`✓ service-hostname-scan：0 条错误（0 条警告）`

**6. 接入**：第一次 `make integrate ID=infra/iam-casdoor` exit 0，但 iam 已是 2.0.0，脚本跳过 add/upgrade，`brickkit.yaml` 仍留着 `infra/authz 2.0.0 requiredBy: [infra/iam-casdoor]`，dry-run 里有 `infra-authz-2-0-0`。`brickkit deps` 已显示 `infra/iam-casdoor@2.0.0 └── infra/authz@2.0.1`、`infra/authz@2.0.0` 成了孤儿；`brickkit upgrade --dry-run` → `✅ Every component is up to date`，不清孤儿。于是持锁 `brickkit remove infra/authz@2.0.0`：
```
➖ Removed infra/authz@2.0.0
🗄️  Config archived: config/infra-authz@2.0.0.yaml → config/.archive/infra-authz@2.0.0.yaml
📝 Written: brickkit.yaml, deploy.yaml
ℹ️  Not changed: deploy.teardown.yaml; when you deploy those environments with -f, carry the change over yourself
```
再跑 `make integrate` exit 0：teardown-sync 同步了 deploy.teardown.yaml，dry-run 只剩 `infra/iam-casdoor@2.0.0 → infra/authz@2.0.1`。现在 brickkit.yaml / deploy.yaml / deploy.teardown.yaml 里 authz 各只有一行（2.0.1 / 裸 id），`config/infra-authz@2.0.0.yaml` 已归档。源码目录没动（还剩 2.0.1）。

**7. 真机（同一次持锁：verify KEEP=1 → 手工核对 → down）**，`$S/r-final/c7-final.log`、手工脚本 `$S/r-final/manual.sh`：

`make verify ID=infra/iam-casdoor ROUTE="POST /api/iam/logout" ROUTE_BODY='{"refresh_token":"verify-placeholder-not-a-jwt"}' FORCE_BUILD=1 KEEP=1` exit 0，闭包 `infra/authz@2.0.1 infra/iam-casdoor@2.0.0`：

| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build infra/iam-casdoor | PASS |  | build.log |
| 镜像 infra-iam-casdoor:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| infra-iam-casdoor-2-0-0 running (healthy)（容器服务 infra-iam-casdoor-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| POST /api/iam/logout 不带 token → 401/503 | PASS | 实际 401 | http.log |
| POST /api/iam/logout 带 token → 200 | PASS |  | http.log |
| make -C <源目录> seed | SKIP | 没设 SEED=1 |  |
| make test-cross ID=infra/iam-casdoor | PASS |  | test-cross.log |
| brickkit up --focus infra/iam-casdoor | SKIP | 没设 FOCUS=1 |  |
| brickkit down | SKIP | KEEP=1：容器保留，用完 brickkit down -f deploy.verify.yaml |  |

ROUTE_BODY 是静态占位串：logout 对验签不过的 refresh token 按幂等成功处理，所以这一行验的是鉴权门（不带 token 401、带 token 200）。真实 refresh token 的撤销在下面手工核对里验。

手工核对原文：
```
== 容器：brickkit-be-assembly-standard-infra-iam-casdoor-2-0-0-1 infra-iam-casdoor:2.0.0 Up 21 seconds (healthy)
brickkit-be-assembly-standard-infra-authz-2-0-1-1 infra-authz:2.0.1 Up 27 seconds (healthy)
== iam 镜像创建时间 2026-10-02T16:24:03.662447067+02:00
== ① 多行密钥运行期逐字节核对
✓ 容器内与文件逐字节相同
iam 容器里 authz 的注入地址：http://infra-authz-2-0-1:8223
== ② test-cross：端到端测试（对着真实 infra/authz 2.0.1）
exit=0
    INFRA_AUTHZ_GRPC_ENDPOINT=http://localhost:20223
=== RUN   TestExchangeTokenAndRefreshToken_端到端对着真实infra_authz走一遍
--- PASS: TestExchangeTokenAndRefreshToken_端到端对着真实infra_authz走一遍 (0.62s)
ok  	github.com/brickKit/infra-iam-casdoor/v2/backend/internal/service	1.665s
== ③ 登出带真实 refresh token → 200，之后这个 refresh token 失效；token 里的 dept_path
换 token 响应键： ['access_token', 'expires_in', 'refresh_token', 'token_type'] expires_in = 600
应用 token：sub 前 8 位 e88c4f5a dept_path = '/1/' org_id = '1' roles 含 dev_superuser: True
ERROR:  column d.path does not exist
dev.superuser 的 sub 前 8 位：e88c4f5a；authz 里的部门：
POST /api/iam/logout 带 token + 真实 refresh_token → 200（期望 200）；带 token 不带请求体 → 400（契约的 400）；不带 token 带请求体 → 401（期望 401）；登出后用这个 refresh token 刷新 → 401（期望 401）
-- refresh_tokens 里这个人最近一条：t
-- iam 的 WARN/ERROR 日志（最后 10 条）
== 手工核对结束
```
（`column d.path` 是手工脚本里写错了列名，只影响那一行旁证；部门归属已在第 3 步实查：e88c4f5a → 部门 1 `/1/`，与 token 里的 `dept_path = '/1/'` 一致。）

verify 自带的 test-cross（全量）：`INFRA_AUTHZ_GRPC_ENDPOINT=http://localhost:20223`，12 个包 ok，无 FAIL；此时项目里只有 authz 2.0.1 一个 authz 容器。

收尾（同一次持锁）：`brickkit down -f deploy.verify.yaml` → `✅ All components stopped`；`Local mode: off`、`deploy.local.yaml: none`；本项目容器 0 个；项目根没有 `deploy.verify.yaml`。

### 现象

- authz 2.0.1 下 dev.superuser 的应用 token 带 `dept_path = '/1/'`（根部门），不再是空串；本组件原样转抄。
- `make integrate` 不会清掉因依赖改钉而成为孤儿的 `requiredBy` 版本（被依赖方版本没变时脚本跳过 add/upgrade，`brickkit upgrade` 也说 up to date）；要 `brickkit remove <id>@<旧版本>`。

### 卡点与绕过

- 孤儿 `infra/authz@2.0.0`：用 `brickkit remove infra/authz@2.0.0`（持锁）清掉，再跑一次 integrate 同步 teardown。
- assembly.yaml 的注释只能手改，手改保护之后会拦 `--write`（见步骤 4）。
- 没有读 brickKit 源码。

### 结论

全部检查绿，verify 汇总表全部 PASS 或写明原因的 SKIP，logout 的真实 refresh token 撤销在同一次持锁里手工核对通过，test-cross 的 authz 端到端测试对着 authz 2.0.1 PASS。组件仓库新增 5 个提交（5cedbb2、3af7a1a、d0824f5、c6139f7、f1a02b5），HEAD f1a02b5，版本仍 2.0.0，未推送、未打 tag；契约包 tag 仍是 `gen/infra/iam/v1.0.0`。brickkit.yaml 里 authz 只剩 `infra/authz 2.0.1`（无 requiredBy）。发布说明"升级前必须做"加了一行（依赖 authz 2.0.1、be-sdk-go v0.5.0、dept_path 原样转抄）。

### 反馈候选

- 项目工具：`integrate.sh` 在组件版本没变、只是依赖改钉时，不会清掉旧依赖版本的 `requiredBy` 行；可以在 dry-run 前比对 `brickkit deps` 的孤儿版本并提示 `brickkit remove <id>@<ver>`。
- 项目工具：`migrate-manifest.py` 的 overrides 带不了 assembly.yaml 的注释改动，C3 之后改注释只能手改，然后再也跑不了 `--write`（除非 `--force` 丢掉它）。
- brickKit（待验证后再提）：`brickkit upgrade` 不清理已经没人依赖的 `requiredBy` 版本；文档写的是"the old version stays only if something still depends on it"，但那条只在 upgrade 真的动了版本时生效。

## 发布前安全修复：会话期限、停用即作废、投递队列、aud 校验（2026-10-02）

### 目标

控制者裁定 2.0.0 发布前修掉审查的 I1、I2、I3（身份组件，紧接着发 2.0.1 更糟），可用重构许可；外加发布前的 M1、M2、M3、M6。版本仍 2.0.0，不推送、不打 tag。

1. I1：在 Casdoor 里停用的人一直能刷新，而且每次刷新都续期。(a) 会话总期限从登录算起，轮换不续期；(b) 处理投递发 `disabled` 时同一事务撤掉这个人全部 refresh token；(c) 改正 docs/design 与 OpenAPI 里"不滑动续期"的错误说法。
2. I2：回 503 的 webhook 投递永远丢（Casdoor 不重投）。改成登记 RECEIVED、回 200，后台循环 `FOR UPDATE SKIP LOCKED` 认领、回读、发布；有限次退避重试，终态 FAILED + Warn。
3. I3：校验 Casdoor id_token 的 `aud`（`jwt.WithAudience`，client ID 取自 bootstrap_state）。
4. M1 / M2 文档措辞，M3 发布说明去掉"（R61）"，M6 加强只断言 `err == nil` 的测试。

### 环境

brickKit CLI v1.1.0；组件起点 HEAD f1a02b5（33 个本地提交，未推送）；be-acceptance v0.4.8（构建进 `$L`）；基础资源 be-postgres / be-nats / be-casdoor / be-traefik 在跑；开始时没有项目容器、本地模式 off、项目锁空闲。日志目录 `$L` = `$BE_SCRATCH/06b/infra-iam-casdoor/preship-sec/`；真机输出 `$L/rm/`。测试库 `brickkit_test_db`，`TEST_PG_DSN` 由 `$L/env.sh` 从 `.env` 拼出（不打印）。没有读 brickKit 源码。

### 设计（重构许可）

- **会话绝对终点（I1a）**：迁移 004 给 `refresh_tokens` 加 `session_expires_at`（登录时 = `expires_at`，轮换原样继承；已有行用自己的 `expires_at` 补）。`RotateRefreshToken` 改成在事务里调调用方给的 `mint(notAfter)`，新 token 的过期时间 = min(now + 有效期, `session_expires_at`)，过了终点判无效。签名在轮换事务里做（纯 CPU，毫秒级）。
- **停用即作废（I1b）**：`publishCurrentState` 主题为 `disabled` 时同一事务调 `RevokeAllRefreshTokensForSubTx`。写测试时发现一个竞态：撤销全部的 UPDATE 碰上一次轮换中途，会在旧行上等 `FOR UPDATE`，等到时旧行已被轮换撤销、新插的行不在它的快照里，新 token 漏网。登记、轮换、撤销全部现在都先取一把按人的事务级 advisory 锁（`lockSubTokensTx`）。
- **停用后不能拿旧 id_token 换新会话（I1b 的同一缺口，超出简报，单独提交）**：只撤 refresh token 的话，停用前拿到、还没过期的 Casdoor id_token（本组件建的应用 `expireInHours` 24）照样能换出一个新会话。迁移 006 给 `user_event_versions` 加 `disabled`，每次处理投递改写；`IssueRefreshToken` 在按人锁之内查它，停用时 401。代价：本组件停机期间被重新启用的人，要等 Casdoor 里下一次改动他才能再换 token（失败关闭的那一边；已写进 design 未决问题与 BRICKKIT）。
- **投递队列（I2）**：webhook 只分类 + 去重登记（用户变更 RECEIVED，认不出的 IGNORED / ERROR），永远回 200（登记本身失败除外）。`Start()` 里第四个常驻循环 `RunDeliveryLoop`：每个事务 `FOR UPDATE SKIP LOCKED` 认领一条到期的 RECEIVED，在同一事务里跑 R61 的回读 + 发布（版本号行锁仍在回读之前）。锁的顺序：投递行锁 → 版本号行锁（→ 停用时按人锁 → token 行），认领从不等锁。Casdoor 会话没就绪不认领；Casdoor 不可达或超过 20 秒回读时限 → 原样留着、不计次数、整个循环退避 1s→30s；Casdoor 有回答但对这条投递出错 → 回滚到 savepoint、计一次、5s·2^(n-1)（封顶 10 分钟）后再试，满 10 次 FAILED + Warn（status 改回 RECEIVED、attempts 清零即重新排队）。同进程登记的投递立刻唤醒循环，否则每 5 秒看一次。迁移 005 加 `attempts`、`next_attempt_at` 与部分索引。审查 M8 随之解决：webhook 请求只持去重锁与一次短插入；回读期间只有循环自己的一条连接持两把行锁，最长 20 秒。
- **aud 校验（I3）**：`Verify(token, audiences)` 加 `jwt.WithAudience(audiences...)`，audiences 为空一律拒绝。可信 client ID = 本组件应用的 client ID（`bootstrap_state` 的 `casdoor_app`，每次换 token 现读）+ 新配置键 `CASDOOR_EXTRA_CLIENT_IDS`（逗号分隔，默认空）。应用 client ID 还不知道时回 503。**为什么多一个键（偏离简报）**：项目的种子与 `make verify` 都用本地 ROPC 测试应用 `local-dev-seed-app` 签的 id_token 换 token（`infra/scripts/lib/seed-net.sh` 的 `get_app_jwt`），只认 `brickkit-app` 会让全部组件的"带 token"核对 401。真机先确认了 Casdoor 的 `add-application` / `update-application` 接受调用方给的 `clientId`（临时应用，已删），于是 `scripts/seed.sh` 把测试应用的 client ID 固定成它的名字，项目的 `config/infra-iam-casdoor.yaml` 列 `CASDOOR_EXTRA_CLIENT_IDS: local-dev-seed-app`。
- `component.yaml` 的新键经 `manifest-overrides.yaml` 的 `add_properties` 由 `migrate-manifest.py --write --force` 生成（diff 只多一行）；`--force` 只因审查 M9 的手改保护会还原 assembly.yaml 的两段注释，生成后 `git checkout -- assembly.yaml` 按 HEAD 保留。`--check` 全部"无"。

### 步骤（TDD，每项行为变化先红后绿、单独提交）

| 提交 | 内容 | RED（原文） | GREEN |
|---|---|---|---|
| d19931e | I1a 会话终点，迁移 004 | `session_test.go:40: 登录后 4.3s 里轮换了 7 次，每次都成功：每次轮换都重新给了 2s，会话一直续期`（`red-i1a-session.log`） | `--- PASS: TestRefreshToken_轮换不延长会话_过了登录时的期限就拒绝 (1.32s)`（JWT exp 取整到秒，所以早于 2s 拒绝）；service/repo/tokens/http `-race` ok |
| 8b2c700 | I2 投递队列，迁移 005 | `http_test.go:200: 期望 200，实际 503（{"error":"处理 webhook 投递: 依赖尚未就绪: Casdoor 管理会话尚未就绪，读不回用户的当前状态"}）`；service 包新测试编译不过（`svc.claimPrefix undefined`）（`red-i2-queue.log`） | 12 个包 `-race` ok，webhook 测试连跑 3 次绿 |
| 51b5764 | I1b 停用即作废 + 按人锁 | `session_test.go:85: 停用后刷新期望 ErrUnauthenticated（401），实际 <nil>`（isForbidden、Casdoor里已删除 两个子测试）；`repo_test.go:443: 撤销之后这个人还有 1 个有效 refresh token（轮换中途插进来的新 token 漏网）` | 两条 PASS；12 个包 `-race` ok |
| 17f4948 | 停用者不能拿旧 id_token 换新会话，迁移 006 | `session_test.go:108: 停用后拿旧 id_token 换 token 期望 ErrUnauthenticated（401），实际 <nil>` | PASS（含重新启用后能登录）；12 个包 ok |
| e73be4f | I3 aud 校验 + `CASDOOR_EXTRA_CLIENT_IDS` | 先加接口不接 WithAudience：`aud=[another-casdoor-app] 期望 ErrUnauthenticated（401），实际 <nil>`、`aud=[] …实际 <nil>`；真实 Casdoor `casdoor_integration_test.go:151: aud 不是可信的 client ID 时应该验签失败`（`red-i3-aud.log`） | 设 Casdoor 12 个包 `-race` ok；真实 Casdoor 的 id_token 用签发应用的 client ID 验过、别的 client ID 失败 |
| b5d27f0 | seed.sh 固定测试应用 client ID | — | 真机 seed：`✓ Casdoor ROPC 测试应用 local-dev-seed-app 已存在，client ID 改成固定的 local-dev-seed-app` |
| 255d36b | M6 测试加强 | 变异核对：不写 outbox → `期望一条 created、字段来自回读，实际 …（有事件=false）` | PASS |
| 22e3e8f | 代码注释去掉内部审查编号 | — | vet ok |
| 61d9f66、7ac41d7 | 文档与契约说明（M1、M2、I1c）；停机期间重新启用的代价 | — | component-check 10/10、docs-check 0/0 |

变异核对（都已还原）：
- 去掉 `FOR UPDATE SKIP LOCKED` → `queue_test.go:214: sub casdoor-uuid_…_3 有 2 条事件，期望恰好 1 条（两个实例处理了同一条投递）`（`mutation-i2-skip-locked.log`）
- 回读挪到取版本号之前 → `webhook_readback_test.go:165: 下游最后留下 display_name="第一次"，期望 Casdoor 的最新值 "第二次"`（`mutation-i2-lock-order.log`）

测试改动（不是为了变绿改断言）：R61 时"会话未就绪回 503、不登记"的两条测试按裁定反转；R61 读回测试改成"登记 + 处理队列"，断言不变；repo 的投递测试按新 API 重写（去重、savepoint 回滚并记次数、Leave 不计次数、并发到达只登记一次）；repo 轮换测试只按新签名改调用。

M3：发布说明 `$BE_SCRATCH/06b/infra-iam-casdoor/notes-2.0.0.md` 去掉"（R61）"；同一行原来写的"会话未就绪时 webhook 回 503、投递不登记（1.x 回 200）"已不成立，删掉；"新增"里 503 那句改成"多声明了一个 503（只增；本版本不返回）"。新加：升级前必须做两行（aud 与 `CASDOOR_EXTRA_CLIENT_IDS`；会话不再续期），新增两行（投递队列、新配置键），修复三行（停用即作废、投递丢失、aud）。备份 `$L/notes-2.0.0.md.bak-pre-sec`。

### 检查（全部 exit 0）

- `go-v2.sh infra/iam-casdoor --recheck` → `✅ go-v2.sh：判据全部 PASS`，`📌 … gen/infra/iam/v1.0.0`（proto 没动）
- `component-check.sh` → `✅ component-check infra/iam-casdoor：10 项全部 PASS`
- `make docs-check ID=infra/iam-casdoor` → `📋 Checked 3 files: 0 with errors, 0 warnings`
- `migrate-manifest.py --check` → `✅ --check 全部为"无"`，依赖 `['infra/authz@2.0.1']`；`brickkit lint infra/iam-casdoor` 0/0
- 组件门禁 `TEST_CASDOOR_BASE_URL=http://localhost:8000 make check-version test contract-check import-scan module-check dag-check` → `✓ version=2.0.0`、12 个包 ok、`buf breaking --against '.git#tag=v1.0.10'`、`✓ 无组件间 import`、`✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`、`✓ 唯一依赖 infra/authz，无环`（`$L/component-gates.log`；`buf` 在 `~/go/bin`，要加进 PATH）
- SKIP：不设 Casdoor 6 条（与 AGENTS 一致）；设 Casdoor 只剩 `--- SKIP: TestExchangeTokenAndRefreshToken_端到端对着真实infra_authz走一遍`
- `make test-db-init ID=infra/iam-casdoor` → `"version":6,"dirty":false` ×2、`✓ 迁移幂等`
- 发布前扫描（be-acceptance v0.4.8）：`✓ openapi-additive-scan（只看 components/infra/iam-casdoor）：0 条违规（0 条跳过提示）`、`✓ config-key-scan（只看 components/infra/iam-casdoor）：0 条违规`、`✓ 事件契约破坏性变更扫描：0 条违规`

### 真机（一次持锁：种子 → verify KEEP=1 → 手工核对 → down），`$L/realmachine.log`、脚本 `$L/realmachine.sh` / `$L/manual.sh`

先改项目文件（未提交）：`config/infra-iam-casdoor.yaml` 加 `CASDOOR_EXTRA_CLIENT_IDS: local-dev-seed-app`；`dev/phase-06/tools/manifest-overrides.yaml` 加 `add_properties`。持锁第一步跑组件 seed，把测试应用的 client ID 改成固定值（其它 lane 的 `get_app_jwt` 每次现读 client ID，不受影响）。

`make verify ID=infra/iam-casdoor ROUTE='POST /api/iam/logout' ROUTE_BODY='{"refresh_token":"verify-placeholder-not-a-jwt"}' FORCE_BUILD=1 KEEP=1` exit 0，闭包 `infra/authz@2.0.1 infra/iam-casdoor@2.0.0`：

| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build infra/iam-casdoor | PASS |  | build.log |
| 镜像 infra-iam-casdoor:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| infra-iam-casdoor-2-0-0 running (healthy)（容器服务 infra-iam-casdoor-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| POST /api/iam/logout 不带 token → 401/503 | PASS | 实际 401 | http.log |
| POST /api/iam/logout 带 token → 200 | PASS |  | http.log |
| make -C <源目录> seed | SKIP | 没设 SEED=1 |  |
| make test-cross ID=infra/iam-casdoor | PASS |  | test-cross.log |
| brickkit up --focus infra/iam-casdoor | SKIP | 没设 FOCUS=1 |  |
| brickkit down | SKIP | KEEP=1：容器保留，用完 brickkit down -f deploy.verify.yaml |  |

演示库迁移到 `"version":6,"dirty":false`；"带 token"那行的 token 是测试应用签的 id_token 换来的，aud 校验之下照样 200（`CASDOOR_EXTRA_CLIENT_IDS` 生效）；test-cross 12 个包 ok，`INFRA_AUTHZ_GRPC_ENDPOINT=http://localhost:20223`。

手工核对原文：
```
== 容器：brickkit-be-assembly-standard-infra-iam-casdoor-2-0-0-1 infra-iam-casdoor:2.0.0 Up 26 seconds (healthy);brickkit-be-assembly-standard-infra-authz-2-0-1-1 infra-authz:2.0.1 Up 31 seconds (healthy);
== iam 镜像创建时间 2026-10-02T17:17:42.916735134+02:00
== 种子应用 client ID 是否为固定值：是
   dev.sales.east sub 前 8 位 4f269a9f；dev.finance.viewer sub 前 8 位 915d1763

== (i) 在 Casdoor 里停用 dev.sales.east → 它的刷新 401 → 重新启用、重新登录恢复
拿到 id_token
  登录换 token → 200（期望 200）
  停用前刷新一次 → 200（期望 200）
  update-user: ok 
  -- 投递：131 update-user PROCESSED attempts=0
  -- outbox：infra.iam.user.disabled.v1 published=true display_name=
  -- 有效 refresh token 数：0（期望 0）；disabled 标记：t（期望 t）
  停用后用手里的 refresh token 刷新 → 401（期望 401）
  停用后用停用前拿到的 id_token 换 token → 401（期望 401）
  停用后 Casdoor 还给不给 id_token：Casdoor 不给 id_token： invalid_grant the user is forbidden to sign in, please contact the administrator
  update-user: ok 
  -- 投递：132 update-user PROCESSED attempts=0
  -- outbox：infra.iam.user.updated.v1 published=true display_name=「本地测试」销售-华东
  -- disabled 标记：f（期望 f）
拿到 id_token
  重新登录换 token → 200（期望 200）；再刷新 → 200（期望 200）
  -- 有效 refresh token 数：1（期望 1）

== (ii) iam 停一下、期间在 Casdoor 里改人 → 起 iam → 改动经投递队列到下游
  iam 已停（0s）
  update-user: ok 
  iam 已起（1s）
  iam 健康：healthy（6s）
  -- 投递：133 update-user PROCESSED attempts=0
  -- outbox：infra.iam.user.updated.v1 published=true display_name=「本地测试」财务只读·停机期间
  -- 投递到达时刻与 iam 启动时刻：15:19:35 / 15:19:07Z
  update-user: ok 
  还原显示名的投递已处理

== (ii-b) Casdoor 读不了时（暂停 be-casdoor）来一条投递 → 200 + RECEIVED → 恢复后队列发出
  共享密钥：已从 .env 读到（不打印）
  be-casdoor 已暂停
  投递 → 200（期望 200）；状态：RECEIVED attempts=0
  25 秒后（回读超时过一轮）状态：RECEIVED attempts=0（期望 RECEIVED attempts=0）
  -- iam 日志里的 Warn：1 条“回读 Casdoor 失败（不可达）”
  be-casdoor 已恢复
  恢复后状态：PROCESSED attempts=0（期望 PROCESSED attempts=0）
  -- 投递：136 update-user PROCESSED attempts=0
  -- outbox：infra.iam.user.updated.v1 published=true display_name=「本地测试」财务只读

-- iam 的 ERROR 日志：0 条
{"time":"2026-10-02T15:20:21.406063936Z","level":"WARN","msg":"回读 Casdoor 失败（不可达），投递留在队列里，稍后重试","component_id":"infra/iam-casdoor","error":"回读 Casdoor 用户失败: Casdoor 不可达: Get \"http://host.docker.int
== 手工核对结束
```

收尾（同一次持锁）：`brickkit down -f deploy.verify.yaml` → 正常结束；删掉 `deploy.verify.yaml`；`Local mode: off deploy.local.yaml: none`；本项目容器 0 个；be-casdoor `running`；dev.sales.east 已重新启用并能登录，dev.finance.viewer 显示名已还原。

### 现象

- 停用一个人：Casdoor 下一批（约 30 秒）投递到达 → 队列处理 → `disabled` 发出且同一事务撤掉全部 refresh token；刷新 401、停用前的 id_token 换 token 401；重新启用后 `updated` 清掉标记，重新登录 200。
- (ii)：iam 停了约 1 秒（docker stop / start），期间的改动在 iam 起来 28 秒后随 Casdoor 的下一批到达并发出。这条能成，是因为 Casdoor 的那一批是在 iam 起来以后发的；赶上 iam 停着时发的那一批就会丢（Casdoor 不重投，文档写明的限制）。所以 (ii) 证明的是"重启之后投递照常进队列、发到下游"。真正对应 I2 的情况放在 (ii-b)：Casdoor 读不了的时候来了一条投递。暂停 be-casdoor 期间投递回 200、RECEIVED、attempts 不动、只记 Warn，恢复后队列发出。（ii-b）用的是手工按 Casdoor Record 形状发的投递；暂停之前确认过没有别的 go test 在跑。
- iam 全程没有 ERROR 日志。

### 卡点与绕过

- aud 校验与项目工具冲突：种子 / verify 用 ROPC 测试应用签的 id_token。加了 `CASDOOR_EXTRA_CLIENT_IDS`，并把测试应用 client ID 固定（见设计）。
- `migrate-manifest --write` 被 assembly.yaml 的手改保护拦住（审查 M9），用 `--force` 后按 HEAD 还原 assembly.yaml。
- 组件 Makefile 的 `contract-check` 要 `buf`，当前 shell 的 PATH 里没有 `~/go/bin`。
- 没有读 brickKit 源码。

### 结论

I1（a、b、c）、I2、I3 与 M1、M2、M3、M6 全部完成。组件仓库在 f1a02b5 之上新增 10 个提交，HEAD 7ac41d7，版本仍 2.0.0，未推送、未打 tag，契约包 tag 仍是 `gen/infra/iam/v1.0.0`（proto 没动）。新增迁移 004–006。所有检查绿，verify 表全部 PASS 或写明原因的 SKIP，手工核对 (i)(ii)(ii-b) 都符合期望，收尾干净。

### 反馈候选

- 项目工具：`migrate-manifest.py` 的手改保护按文件整体判断；assembly.yaml 被手改过时，component.yaml 的一次正常 `--write` 也被拦，只能 `--force` 再手工还原（审查 M9 的另一个表现）。
- 项目工具：`infra/scripts/lib/seed-net.sh` 的 `get_app_jwt` 依赖测试应用的 client ID 被 iam 信任；以后再有 IAM 实现时也要同样的"额外信任的 client ID"。

## R63：数据库身份来自配置（2026-10-02）

### 目标

按裁定 R63 第 1–4 条：事务角色取配置的 `PG_USER`（不再 `schema + "_rw"`）；迁移里不写死角色名与 schema 名（删掉 `ALTER … OWNER TO infra_iam_casdoor_rw`）；BRICKKIT"部署前准备"写成通用要求；用一个非默认 schema + 与之配套、名字不按 schema 推的登录角色做 L2 证明。版本仍 2.0.0，只在组件仓库提交，不推送、不打 tag。

### 环境

brickKit CLI v1.1.0；组件起点 HEAD 7ac41d7；be-sdk-go v0.5.0；基础资源 be-postgres / be-nats / be-casdoor 在跑；开始时没有项目容器、本地模式 off。日志目录 `$L` = `$BE_SCRATCH/06b/infra-iam-casdoor/r63/`；`TEST_PG_DSN` 由 `$BE_SCRATCH/06b/infra-iam-casdoor/preship-sec/env.sh` 从 `.env` 拼出（以 `postgres` 登录，不打印）。没有读 brickKit 源码；读了 be-sdk-go v0.5.0 的 `migrate.Run`、`WithTx`、`StartOutboxPump`（确认迁移的 search_path 与状态表名、事务里 SET LOCAL 的内容、outbox 推送不切角色）。

### 全仓 grep（`_rw|infra_iam_casdoor|OWNER TO|search_path|PG_USER|PG_SCHEMA`，不含 gen/）

| 位置 | 处理 |
|---|---|
| `backend/module/settings.go:65` `s.role = s.schema + "_rw"` | 改成 `PG_USER`（加进 requiredKeys，缺失或空白启动报错点名） |
| `migrations/001_create_iam.up.sql:89`、`002_create_outbox_inbox.up.sql:39`、`:65` 的 `OWNER TO infra_iam_casdoor_rw` 及其注释 | 删除（零效果；原因改写进 docs/design） |
| 迁移 003–006 | 没有角色名、schema 名，不用改 |
| `backend/internal/repo/refreshtokens.go:189`、`webhookdeliveries.go:29` advisory 锁键 `hashtext('infra_iam_casdoor.…')` | 改成 `hashtext(current_schema() \|\| '.表名')`；默认 schema 下键值不变（`$L/lockkey-same.log`：`infra_iam_casdoor\|t\|t`） |
| `Makefile:42` migrate-idempotent 说明"以 infra_iam_casdoor_rw 登录" | 改成"以组件的登录角色登录，即 PG_USER" |
| `scripts/seed.sh`、`seed-clean.sh` | 不碰数据库，没有命中 |
| `BRICKKIT*.md`（部署前准备、PG_DATABASE / PG_USER / PG_SCHEMA 三行）、`docs/design*.md`（归档 schema 名） | 改成通用写法 |
| `assembly.yaml` `schema: infra_iam_casdoor`、`role: infra_iam_casdoor_rw` | 保留：这是本项目 be-ops / db-init 读的登记，不是组件代码 |
| 测试里的 `repo.New(db, "infra_iam_casdoor_rw", "infra_iam_casdoor")` 与带 `infra_iam_casdoor.` 限定名的断言查询（repo / service / http / bootstrap / consumer / partition / module 各包） | 保留：它们指向 `make test-db-init` 建好的那个测试夹具（默认 schema 与角色），不是从 schema 推角色；非默认名字由新 L2 测试覆盖。`settings_test.go` 的默认值断言改成"角色取 PG_USER" |

### 步骤（TDD）

1. 改前记下两个库的表 owner（`$L/owners-before.log`，查询见下）。
2. 新 L2 测试 `backend/module/dbidentity_test.go` `TestDBIdentity_非默认schema与不按schema起名的登录角色_迁移并经模块读写`：以 TEST_PG_DSN（超级用户）在 brickkit_test_db 建随机 schema `r63_iam_<hex>` 与登录角色 `r63_iam_login_<hex>`（故意不是 `<schema>_rw`），只授 schema 上的 `USAGE, CREATE` 与库的 `CONNECT`；`migrate.Run` 以该角色迁移，断言 schema 里每张表都归它；以该角色登录的池 + 这对名字的配置构造 `module.New`，经 `HTTPHandler` POST 一条 webhook 投递（写）、同样内容再投一次（去重先读到第一条），断言库里恰好 1 行；再以 `loadSettings` 给的角色跑一轮 `partition.Start`，断言建出当前月 + 3 个月的 `webhook_deliveries` 分区、归该角色。`t.Cleanup`：`DROP SCHEMA … CASCADE`、`DROP OWNED BY`、`DROP ROLE`。
3. RED ①（原代码，`$L/red-1-migration.log`）：
   `dbidentity_test.go:103: 以角色 r63_iam_login_14d3a7de 迁移进 schema r63_iam_14d3a7de 失败：迁移 up 失败（schema r63_iam_14d3a7de）：migration failed: must be able to SET ROLE "infra_iam_casdoor_rw" (column 0) in line 1: …`
   之后查 `pg_roles` / `pg_namespace` 里 `r63_%`：0 / 0（清理生效）。
4. 删迁移里的 OWNER TO → RED ②（`$L/red-2-role.log`）：
   `dbidentity_test.go:149: 响应体：{"error":"登记 webhook 投递: SET LOCAL ROLE r63_iam_7794bbdd_rw: ERROR: role \"r63_iam_7794bbdd_rw\" does not exist (SQLSTATE 22023)"}`
   `dbidentity_test.go:154: 第一次投递期望 200，实际 500`
5. 角色取 PG_USER → GREEN（`$L/green-module.log`）：`--- PASS: TestDBIdentity_非默认schema与不按schema起名的登录角色_迁移并经模块读写 (0.63s)`，module 包 14 条全 PASS（`-race`），新增 `TestLoadSettings_事务角色取PG_USER_缺了报错` PASS。
6. 变异核对（`$L/mutation-role.log`，已还原）：把角色改回 `s.schema + "_rw"` → L2 `SET LOCAL ROLE r63_iam_dc9eba20_rw … does not exist`、`settings_test.go:62: schema 应取默认值、角色应取 PG_USER："infra_iam_casdoor" / "infra_iam_casdoor_rw"`、`settings_test.go:117: … 实际 "iam_custom" / "iam_custom_rw"`，三条 FAIL。
7. advisory 锁键改 `current_schema()` 后 repo / service / consumer `-race` ok（含并发撤销与轮换、并发投递去重的测试）。

### test-db-init 与 owner 核对

`make test-db-init ID=infra/iam-casdoor`（`$L/test-db-init.log`）exit 0：
```
{"time":"2026-10-02T17:49:08.331670472+02:00","level":"INFO","msg":"迁移结束","direction":"up","schema":"infra_iam_casdoor","outcome":"ok","version":6,"dirty":false}
{"time":"2026-10-02T17:49:08.363915851+02:00","level":"INFO","msg":"迁移结束","direction":"up","schema":"infra_iam_casdoor","outcome":"ok","version":6,"dirty":false}
✓ 迁移幂等
✓ brickkit_test_db 就绪——TEST_PG_DSN 现在该指向这个库，不是 brickkit_db
```

owner 查询（`$L/owners.sql`，两个库各跑一次，改前改后各一次）：
```sql
SELECT current_database() AS db, n.nspname AS schema, c.relname, c.relkind, pg_get_userbyid(c.relowner) AS owner
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'infra_iam_casdoor' AND c.relkind IN ('r','p','S')
ORDER BY c.relname;
```
`diff owners-before.log owners-after.log` → 无差异（`owners identical`），每个库 32 行。汇总：
```
        db        |        owner         | relations 
------------------+----------------------+-----------
 brickkit_test_db | infra_iam_casdoor_rw |        32
(1 row)

     db      |        owner         | relations 
-------------+----------------------+-----------
 brickkit_db | infra_iam_casdoor_rw |        32
(1 row)
```

### 检查（全部 exit 0）

- `component-check.sh infra/iam-casdoor` → `✅ component-check infra/iam-casdoor：10 项全部 PASS`
- `go-v2.sh infra/iam-casdoor --recheck` → `✅ go-v2.sh：判据全部 PASS`，`📌 第 8.3 步需要打的契约包 tag：gen/infra/iam/v1.0.0`
- `make docs-check ID=infra/iam-casdoor` → `📋 Checked 3 files: 0 with errors, 0 warnings`；`brickkit lint infra/iam-casdoor` 同
- `TEST_CASDOOR_BASE_URL=http://localhost:8000 make check-version test contract-check import-scan module-check dag-check`（`$L/component-gates.log`）→ `✓ version=2.0.0`、12 个包 ok、`buf breaking --against '.git#tag=v1.0.10'`、`✓ 无组件间 import`、`✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`、`✓ 唯一依赖 infra/authz，无环`
- SKIP（设 Casdoor）只剩 `--- SKIP: TestExchangeTokenAndRefreshToken_端到端对着真实infra_authz走一遍`；跑完 `r63_%` 角色与 schema 各 0 个

### 真机

`make verify ID=infra/iam-casdoor ROUTE='POST /api/iam/logout' ROUTE_BODY='{"refresh_token":"verify-placeholder-not-a-jwt"}' FORCE_BUILD=1`（`$L/verify.log`）exit 0，闭包 `infra/authz@2.0.1 infra/iam-casdoor@2.0.0`：

| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build infra/iam-casdoor | PASS |  | build.log |
| 镜像 infra-iam-casdoor:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（2 个） | PASS |  | migration-*.log |
| infra-iam-casdoor-2-0-0 running (healthy)（容器服务 infra-iam-casdoor-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| POST /api/iam/logout 不带 token → 401/503 | PASS | 实际 401 | http.log |
| POST /api/iam/logout 带 token → 200 | PASS |  | http.log |
| make -C <源目录> seed | SKIP | 没设 SEED=1 |  |
| make test-cross ID=infra/iam-casdoor | PASS |  | test-cross.log |
| brickkit up --focus infra/iam-casdoor | SKIP | 没设 FOCUS=1 |  |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |

迁移容器：`"schema":"infra_authz","outcome":"ok","version":3`、`"schema":"infra_iam_casdoor","outcome":"ok","version":6,"dirty":false`；test-cross 12 个包 ok。收尾后 `Local mode: off`、deploy.verify.yaml 不在、本项目容器 0 个；verify 之后再查 brickkit_db 的 owner，与改前逐行相同。

### 现象

- 原代码在任何不叫 `infra_iam_casdoor` / `infra_iam_casdoor_rw` 的部署里都跑不起来：先是迁移失败（OWNER TO 写死的角色），去掉之后每次写库 500（角色由 schema 拼）。本项目名字恰好对得上，所以此前所有检查与真机都是绿的。
- 删掉的三条 OWNER TO 在本项目里一直是空操作：迁移本来就以 `infra_iam_casdoor_rw` 运行，表本来就归它；两个库的 owner 前后一致。

### 卡点与绕过

- component-check / go-v2.sh 要先 `export BE_SCRATCH=…`（第一次没设，`❌ env.sh: 请先设置 BE_SCRATCH`）。
- 一次失误：在终端里 `cut -d= -f1 .env` 想列 `.env` 的键名，多行的 PEM 值让私钥正文进了本会话的工具输出（只在会话记录里，没写进任何文件、日志或提交）。按需告知控制者，是否轮换本地开发用的 `APP_TOKEN_SIGNING_KEY_PEM` 由控制者决定。

### 结论

R63 第 1–4 条在 infra/iam-casdoor 完成：组件仓库在 7ac41d7 之上新增 4 个提交（87047bf、6f3e44d、b6ec559、6d2e6da），版本仍 2.0.0，未推送、未打 tag，契约包 tag 仍是 `gen/infra/iam/v1.0.0`（proto 没动）。L2 测试先红（两层原因各一次）后绿，变异核对有效；test-db-init 幂等、两个库 owner 不变；全部检查与真机 verify 通过。

### 反馈候选

- be-sdk-go：`StartOutboxPump(ctx, db, schema, …)` 不切角色，查询以池的登录角色执行。单跑时就是组件角色；进外壳后它以外壳的角色读写成员的 `event_outbox`，靠外壳角色继承成员角色的权限（`INHERIT`）才成立。要不要像 `WithTx` 一样接收角色、每轮 `SET LOCAL ROLE`，留给 SDK 决定（同样影响其它 Go 组件）。
- 项目工具：`infra/scripts/test-db-init.sh` 的"①b 把 postgres 名下的旧对象转给各组件的 `<schema>_rw`"仍按 schema 拼角色名；它是本项目登记表的做法，不影响组件，但与 R63 的说法不一致，可以改成读 assembly.yaml 的 `role`。
