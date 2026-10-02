# 06b mdm/customer：过程记录（试点）

## 概况

- 日期：2026-10-02（04:25 开工，04:52 交接，墙钟约 27 分钟）
- brickKit：`brickkit version` → `BrickKit CLI v1.1.0` / `Supported Manifest version: brickkit/v1` / `Supported deploy targets: docker, podman, k8s`
- SDK：be-sdk-go v0.4.0（`git -C tools/be-sdk-go describe --tags --abbrev=0` → `v0.4.0`）；be-sdk-python v0.4.4、be-sdk-ts v0.4.0（本组件不用）
- 基础资源：`make check` → `✓ 全部基础资源就绪`（postgres、nats、traefik、casdoor、rustfs 全部 healthy）
- 组件与版本：mdm/customer v1.0.10 → 2.0.0；组件仓库提交 b2ac80e … 10562dc（9 个，未推送、未打 tag）；tag 待控制者 `make ship`：`2.0.0`、`v2.0.0`；契约包 **不需要新 tag**（仍 `gen/mdm/customer/v1.0.6`）
- 交接给控制者：提交 SHA（见"小结"）、发布说明 `$S/notes-2.0.0.md`（`$S=$BE_SCRATCH/06b/mdm-customer`）、`make verify` 汇总表与输出目录（见 7）、父仓库待提交的路径（见"小结"）

## mdm/customer

### 目标

按 component-loop 重建到 2.0.0；补 frontend-needs §2.1 的 `GET /customers?q=`；实测 V-01、V-07、V-09；作为后面 12 个组件的样板。

### 环境

brickKit v1.1.0；目标 docker；拓扑：独立组件（没有外壳）；项目里只有 mdm/customer@2.0.0（authz / iam-casdoor 尚未加入）；本地模式开始与结束都是 off（`brickkit local status` → `Local mode: off` / `deploy.local.yaml: none`）。

### 步骤

**C1 前置（04:25:49–04:26:56）**

- `git -C $C status -sb` → `## main...origin/main`，下面无文件行。最后一个 1.x tag `v1.0.10`。
- `make check` 全绿（见概况）。
- `brickkit version` → v1.1.0；`buf --version` → 1.47.2；无依赖，"上游已发布"不适用。
- 1.6 表属主：`select tableowner, count(*) … where schemaname='mdm_customer'` → 空（T5 重置过，演示库里还没有表）。迁移之后（见 7）：`mdm_customer_rw|25`——表归登录角色所有。
- 1.5 读了旧 AGENTS / README / docs/手册.md、`archive/pre-v1/docs/dev/design/mdm-customer.md`、四个清单/构建文件、frontend-needs §2.1、04/02/06/08 约定的相关节。

**C2 骨架（04:26:56，<1 秒）**

```
bash dev/phase-06/tools/docs-skel.sh mdm/customer
✅ docs-skel：改动 8 个文件，跳过 0 个（跳过的是已经填写过的文件）
git -C $C rm -q docs/手册.md; (cd $C && brickkit skills update)
📦 Component repository (has component.yaml, no brickkit.yaml): the brickkit-component skill, plus the component's own AGENTS.md and CLAUDE.md
✅ AI assistant skills updated
   Wrote 1:
     .claude/skills/brickkit-component/SKILL.md
```

通过：九个文件都在；`CLAUDE.md` 恰好 `@AGENTS.md`；`AGENTS.md` 末尾有 `<!-- brickkit:managed:begin lang=en -->`；留底在 `$S/old/`。

**C3 清单（04:27:03，约 1 秒）**

- `migrate-manifest.py --write`：`assembly.yaml 删除的键：['version', 'asset', 'shell']`；`旧键 → 新键：{'pgSchema': 'PG_SCHEMA', 'iamJwksUrl': 'IAM_JWKS_URL', 'authzBundleUrl': 'AUTHZ_BUNDLE_URL', 'otelBaseUrl': 'OTEL_BASE_URL'}`；`backend/module/module.go:31: "pgSchema" → "PG_SCHEMA"`。
- `--check` 全部"无"，`✅ --check 全部为"无"`，`exit=0`。
- `brickkit lint mdm/customer`：第一行 `🔎 Only mdm/customer is checked (brickkit lint --all checks the whole project)`，`✅ components/mdm/customer/component.yaml`，`📋 Checked 2 files: 0 with errors, 66 warnings`——只有 `DOC_PLACEHOLDER` 与 "required config key … does not explain it / listed under artifacts … does not mention it" 两类。
- 无新权限键，没跑 `make permissions`。

**C4 代码（04:27:23–04:40）**

- `go-v2.sh mdm/customer --sdk v0.4.0` → 4.6 秒，`exit=0`，判据 14 条全部 PASS，`📌 第 8.3 步：不需要打契约包 tag（本地 gen/mdm/customer 与 gen/mdm/customer/v1.0.6 一致）`。脚本输出里值得注意的两行：`go: upgraded go 1.25.0 => 1.25.11`（be-sdk-go v0.4.0 要求；Dockerfile 的 `golang:1.25-alpine` 实测是 go1.25.14，够用）、`ℹ️ 这些非 Go 文件还提到 github.com/brickKit/mdm-customer（不带 /v2）…：component.yaml`（那是 `metadata.repository`，正确，不用改）。
- 读 diff：`cmd/migrate/main.go` 一行化、`module.go` 删 `Migrations:` 与 migrations import、`lib/pq` 消失、golang-migrate 变 indirect；`role := schema + "_rw"` 保留。
- 4.5：`无驼峰键读取`；旧平台变量只剩 Makefile 注释里的 `DATABASE_*`（随 4.7 改掉）。4.9：`scripts/` 无 `1-0-` / `DATABASE_`。
- 提交 b2ac80e（机械步骤）。
- 4.16 `make test-db-init` 7.4 秒，mdm/customer 段：`{"msg":"迁移结束","direction":"up","schema":"mdm_customer","outcome":"ok","version":2,"dirty":false}` ×2、`✓ 迁移幂等`（SDK 的迁移入口读 `PG_*` 成功）。基线测试全绿、无 SKIP。
- 4.10 重构：`repo.go` 563 行，四个写命令重复"查幂等键 → 写 → 记幂等键 → Outbox"，Update / SetStatus 几乎逐行相同 → 拆成 `repo.go`（110）/ `write.go`（296）/ `read.go`（145），抽出 `replayCustomer`、`recordIdempotency`、`publish`、`updateWithVersion`；测试不改、全绿。提交 07fc475。
- 4.11 发现两个真实 bug（各一个红绿提交）：
  - 非法游标被映射成 500：红 `service_test.go:233: 非法 cursor 应映射成 InvalidArgument，实际 Internal（非法 cursor：illegal base64 data at input byte 0）`；加 `repo.ErrInvalidCursor` 后绿。提交 8fa49e8。
  - REST 列表从不读契约里已声明的 `created_after` / `created_before`（gRPC 读）：红 `给了 created_after=… created_before=…，200 天前的客户 15 应该在结果里（实际 10 条）`、`created_after 不是 RFC 3339 时间应返回 400，实际 200`；加 `parseListInput` 后绿。提交 30aad1b。这条对 `q` 是前提：默认 90 天窗口下，选择器要找更早的客户只能放宽窗口。
- 4.13–4.15 `q`：设计先写（见 C5 的 `docs/design.md` "Contract surface"）；先只加 `ListInput.Q` 字段跑行为红：前缀排序 / 大小写 / 通配符 / 翻页四条红（q 被忽略，返回全部行），`q为空等于不过滤` 实现前后都绿（守行为不变）；实现后全绿；HTTP 透传测试红（返回 38 条）→ 绿。只改 openapi（新增 `q` 参数）与 events.json 的说明文字，`.proto` 与 `gen/` 不变；`go-v2.sh --recheck` 全部 PASS、仍 `v1.0.6`。不加索引（理由写进 design.md）。提交 8f91636。
- 4.12 合并安全：`make module-check` → `✓ 入口签名对、零 os.Getenv、零进程级初始化、栈合规`。
- 注释清理：非测试代码一个提交（1329147），测试注释单独一个提交（550d6be，断言未动，`git diff` 里除注释外只有三条 `t.Fatal` 文案去掉 "（§x.y）"）。`.proto` 的注释仍引用归档文档——改它会改 `gen/`、逼出契约包新 tag，留到下一次真实契约变更；已发布迁移 `.sql` 的注释同理不动（不改旧迁移）。
- 4.7 Makefile / Dockerfile / 种子：提交 5464a59（内容见提交信息）。`check-version` 在 scratch 克隆里测了反向路径：只打 `2.0.0` → `✗ HEAD 有版本 tag（2.0.0），但缺 v2.0.0`；再加 `2.0.1` → `✗ HEAD 上的版本 tag 2.0.1 与 component.yaml 的 2.0.0 不一致`。

**C5 文档（04:40–04:43）**

八份文件写满。核对：`BRICKKIT en=6 zh=6`、`README en=3 zh=3`、`AGENTS en=6 zh=5`（英文多出的是维护块里的 `## BrickKit`，不计）、`docs/design en=10 zh=10`；`无越界链接`；`BRICKKIT 无相对链接`；`make docs-boundary` 静默通过。第一次 `make docs-check` 报 `⚠️ the code map names gen/mdm/customer/v1.x.y, which does not exist`（代码地图第一张表里任何列的行内代码只要含 `/` 都按路径查）→ 改成不加反引号后 `📋 Checked 2 files: 0 with errors, 0 warnings`、`exit=0`。

**C6 版本与门禁（04:43–04:44）**

`make check-version test migrate-idempotent contract-check import-scan module-check docs-check` → 全绿（`✓ version=2.0.0…`、4 个测试包 `ok`、`✓ 迁移幂等`、buf 通过、`✓ 无组件间 import`、`✓ 入口签名对…`、`0 with errors, 0 warnings`）。途中两个坑（见"卡点与绕过" 1、2），修完重跑。`contract-check` 改为对比上一个发布 tag（scratch 克隆里删 `page_size` 并提交，`buf breaking --against '.git#tag=v1.0.10'` 报 `Previously present field "2" with name "page_size" … was deleted`，确认拦得住）。提交 10562dc。

**C7 接入与真机**

- `make integrate ID=mdm/customer`（04:44:59，1.8 秒，`exit=0`）：`brickkit add mdm/customer@2.0.0 --yes` → 7 行 `🔗 … references the variable of the same name in config/vars.yaml (--yes)`、`✅ mdm/customer@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml`、`✏️ Fill in the required keys in config/mdm-customer.yaml: PG_PASSWORD, PG_USER`、`ℹ️  Not changed: deploy.teardown.yaml…`；`config-fill.py` → `写了 3 个键：PG_PASSWORD, PG_USER, PG_SCHEMA`（没有退出码 3，不需要 `--set`）；`teardown-sync` 同步；`brickkit lint --strict mdm/customer` → `✅ mdm/customer: configuration (config/ ↔ configSchema)`、`0 with errors, 0 warnings`；`up --dry-run` → `✅ mdm/customer@2.0.0  starting (top-level)`。生成的 compose 里 `PG_USER=mdm_customer_rw`、`PG_SCHEMA=mdm_customer`、`AUTHZ_BUNDLE_URL=http://infra-authz-2-0-0:8223/authz/bundle`、`IAM_JWKS_URL=http://infra-iam-casdoor-2-0-0:8200/.well-known/jwks.json`、`extra_hosts: host.docker.internal:host-gateway`。AGENTS.md 组件表多一行 `| mdm/customer | 2.0.0 | Customer names, … | BRICKKIT.md +zh | https://github.com/brickKit/mdm-customer |`。
- 第一次 `make verify ID=mdm/customer ROUTE=/mdm/customer/customers FOCUS=1`（04:45:26，57 秒）：容器形态全部 PASS，**focus FAIL**：`实际 000；focus 进程已退出`，focus.log：`[mdm/customer] 连接 NATS 失败：dial tcp: lookup host.docker.internal on 127.0.0.53:53: no such host`。排查与修法见"卡点与绕过" 3。
- 修 `infra/scripts/verify-component.sh` 后第二次（04:50:04，17 秒，build 因镜像已存在跳过——镜像是第一次 verify 从 HEAD 10562dc 构建的，之后组件代码没变）：

```
verify mdm/customer@2.0.0 汇总（输出目录 $BE_SCRATCH/verify/mdm-customer-20261002-045004）
| 检查项 | 结果 | 原因 | 日志 |
|---|---|---|---|
| brickkit build mdm/customer | PASS |  | build.log |
| 镜像 mdm-customer:2.0.0：sh + wget、/app/component.yaml | PASS |  | image-check.log |
| brickkit up -f deploy.verify.yaml | PASS |  | up.log |
| 迁移容器 Exited (0)（1 个） | PASS |  | migration-*.log |
| mdm-customer-2-0-0 running (healthy)（容器服务 mdm-customer-2-0-0） | PASS |  | status.log |
| GET /healthz → 200 | PASS |  | http.log |
| GET /mdm/customer/customers 不带 token → 401/503 | PASS | 实际 401 | http.log |
| GET /mdm/customer/customers 带 token → 200 | SKIP | infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token |  |
| make test-cross ID=mdm/customer | PASS |  | test-cross.log |
| focus：宿主机 http://localhost:8080/healthz → 200 | PASS |  | focus.log |
| brickkit up --all --dry-run（清除 focus） | PASS |  | focus-all-dry-run.log |
| brickkit local off | PASS |  | local-off.log |
| brickkit down：docker ps 里没有本项目（brickkit-be-assembly-standard）的容器 | PASS |  | down.log |
✓ 全部 PASS 或写明原因的 SKIP
```

  带 token 一项 SKIP：待 T25（authz / iam 加入项目后）。迁移容器日志最后一行 `{"msg":"迁移结束","direction":"up","schema":"mdm_customer","outcome":"ok","version":2,"dirty":false}`；focus 一节 `focus 用 deploy.local.yaml 的 vars: 把 host.docker.internal 换成 host-gateway IP 172.17.0.1：PG_HOST, NATS_URL, S3_URL`，focus 进程 `listening on port 8080`、`/healthz` 200；JWKS / bundle 拉取失败（宿主机解析不了容器服务名，附录 B 预期）。收尾后 `brickkit local status` → `Local mode: off` / `deploy.local.yaml: none`。
- Review Focus 2（有默认值的自有键配非默认值）：本组件没有自有键，只有共享键 `PG_SCHEMA` / `PG_PORT` / `OTEL_BASE_URL`；`PG_SCHEMA` 的默认值与 config 字面量相同，行为上分不出读的是哪个——代码读法 `StringOr("PG_SCHEMA", …)` 已由 `--check` 与 4.5 grep 核对。
- `make gates`（顺带跑，不是本 Task 的判据）：`✗ components/mdm/customer/backend/cmd/migrate/main.go:4：mdm/customer import 了 be-sdk-go（铁律六：组件互不 import）`——be-acceptance 的白名单只认 `github.com/brickKit/be-sdk-go` 本身，不认子包 `…/be-sdk-go/migrate`（`tools/be-acceptance/gates/importscan.go:211` 精确匹配 `allowedShared[impPath]`）。其余 gate 单独跑：system-client / bare-route / events-breaking / data-scope-test / dependency-version 都 `0 条违规`，service-hostname-scan `0 条错误（2 条警告）`（authz / iam 还没加入，预期）。

**Step 6 种子（04:51:32–04:51:49）**

`make verify` 收尾时删了项目根的 `deploy.verify.yaml`（只在输出目录留副本），所以按 brief 的命令先拷回再跑：`bash infra/scripts/project-lock.sh -- bash -c "cp <OUT>/deploy.verify.yaml deploy.verify.yaml && brickkit up -f deploy.verify.yaml && make -C components/mdm/customer seed; rc=\$?; brickkit down -f deploy.verify.yaml; rm -f deploy.verify.yaml; exit \$rc"` →

```
── mdm-customer：灌 15 个示例客户（1-5 被下游种子脚本引用，只增不改）──
✓ 客户：1(ACTIVE+1联系人) 2(ACTIVE) 3(ACTIVE) 4(ACTIVE) 5(DISABLED) 6(ACTIVE) 7(ACTIVE+2联系人) 8(ACTIVE,低额度) 9(ACTIVE) 10(ACTIVE) 11(DISABLED,零额度) 12(ACTIVE) 13(HN-001) 14(HN-002) 15(含CHN)
✓ 已给 4 个客户回填历史创建时间（1-4 个月前），列表不再全部挤在同一秒
✅ All components stopped
```

按 q 的 SQL 规则直接查演示库（REST 要 token，还验不了）：`14|HN-002`、`13|HN-001`、`15|C000015|「本地测试」CHN 华南国际贸易公司`——前缀两条在前、包含一条在后。

**C8 交接（04:52）**：发布说明 `$S/notes-2.0.0.md`（先写"升级前必须做"：旧键 → 新键、`PG_*`、两个 URL 改必填、`/v2`、镜像；再写新增 / 修复）。`git -C $C log --oneline -3`：

```
10562dc docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
5464a59 chore: Makefile / Dockerfile / 种子脚本按 v1 改；种子数据加关键字搜索样例
550d6be test: 测试注释改写成测的是什么、为什么，不再引用归档文档
```

工作区干净，`## main...origin/main [ahead 9]`。最后核对：`go list -m all | grep brickKit/mdm-customer` 恰好两行（`…/v2`、`…/gen/mdm/customer v1.0.6 => ./gen/mdm/customer`）；`migrate-manifest.py --check` exit 0；`make teardown-sync CHECK=1` → `✓ deploy.teardown.yaml 与 deploy.yaml 一致`。

### 现象

- 符合预期的：三个迁移脚本全部一次通过；SDK 的一行迁移入口在测试库、迁移容器里都 `outcome=ok`，表属主是 `mdm_customer_rw`；`brickkit add` 自动把共享键链到 `$var:`；容器形态全部 PASS；不带 token 401。
- 不符合预期的：focus 下 `host.docker.internal` 没被换成 `localhost`（component-loop 7.10 的说法与 brickKit 文档不符，以文档为准）；`make verify` 删掉 `deploy.verify.yaml`，与 brief Step 6 的假设不符；`make gates` 的 import-scan 误判 SDK 子包；`brickkit add` 重排了 `brickkit.yaml` / `deploy.yaml` 里的注释（`# More sources…` 一段从缩进挪到行首，行尾注释对齐被压掉），diff 里多出与本组件无关的行。

### 卡点与绕过

1. **`~/go/bin/brickkit` 是 v0.4.6，遮住了 v1.1.0。** component-loop 1.4 要求 `export PATH=$HOME/go/bin:$PATH`（为了 buf），之后组件 Makefile 里的 `brickkit lint` 跑到旧二进制：`❌ 错误：未知命令 lint`（中文、旧命令集）。`which -a brickkit` 只显示 `~/.local/bin/brickkit`，`~/go/bin/brickkit version` → `BrickKit CLI v0.4.6`。绕过：改成 `export PATH=$PATH:$HOME/go/bin`。没有删那个旧二进制（用户机器上的东西，交控制者 / 用户决定）。
2. Makefile 里 `@#` 注释行以 `\` 结尾会把下一行 `@#` 拼进同一条命令：`/bin/sh: 2: @#: not found`。改掉，模板注意。
3. **focus 进程连不上 NATS。** 查 `brickkit docs 02-project-guide/03-local-debug-workflow`："Strings hard-coded in config aren't rewritten … change it to `localhost` yourself. The platform only rewrites the dependency addresses it computes."；`brickkit docs 10-troubleshooting/02-local-debug-issues` 的"The process on this machine can't reach an address written in config"给的修法是 `deploy.local.yaml` 的 `vars:`。这是 brickKit 的既定设计，不是 bug。但同一份 `vars:` 也作用于 focus 运行里的依赖容器，写 `localhost` 会把容器弄坏（容器里 localhost 是它自己）；改写成 Docker `host-gateway` 实际映射的 IP（`docker run --rm --add-host hgw:host-gateway alpine:3.20 getent hosts hgw` → `172.17.0.1`）两边都能到（宿主机实测 `/dev/tcp/172.17.0.1/5432`、`4222` 都通）。**改了工具**（它挡住了 C7 的判据）：`infra/scripts/verify-component.sh` 的 focus 一步先 `brickkit local on`，把 `config/vars.yaml` 里含 `host.docker.internal` 的值换成 host-gateway IP 写进 `deploy.local.yaml` 的 `vars:`（部署文件里已有的同名 vars 不覆盖），收尾时 deploy.local.yaml 原来不存在就删、存在就原样恢复（中断陷阱里同样处理）——顺带修掉"verify 留下 deploy.local.yaml，下一次 focus 沿用过期副本"（第一次 verify 之后实测 `using the existing deploy.local.yaml (kept from last time, not overwritten)`）。`infra/scripts/tests/test_verify_deploy.py` 加两条测试（改写 + 删除自建副本；恢复用户已有的副本），新测试在旧脚本上 FAIL、新脚本上 19/19 通过。父仓库未提交，交控制者。
4. 没有翻 brickKit 源码：全部用 `brickkit docs` / `--help` 答到了。

### V 项

- **V-01（驼峰键是否静默接受）**：`component.yaml` 临时加 `fooBar: {type: string, default: x}`。
  - `brickkit lint --strict mdm/customer`（加入项目前）：`✅ components/mdm/customer/component.yaml`、`✅ components/mdm/customer/ (docs)`、`📋 Checked 2 files: 0 with errors, 0 warnings`，`exit=0`。
  - 加入项目后 `brickkit up --dry-run`：输出与平时一字不差，无任何警告；生成文件 `compose.yaml:38: - fooBar=x`、`compose.yaml:75: - fooBar=x`（服务与迁移容器都注入）；同时 `brickkit lint --strict mdm/customer` 仍 `0 with errors, 0 warnings`（含 `config/ ↔ configSchema`）。
  - 项目侧的 `migrate-manifest.py --check` 拦得住：`驼峰/非法键: ['fooBar']`，`exit=1`。
  - 删掉后 `git -C $C diff component.yaml` 为空，`up --dry-run` 里 `fooBar` 0 处。
  - 结论：静默接受成立，且是 brickKit 的设计（键就是环境变量名，`fooBar` 是合法变量名，skill 规则 2）。重建后本组件 10 个键全部大写下划线，没有任何需要驼峰的场景。迁移工具 `--check` 是一次性的，06b 之后没有常设门禁——反馈候选（项目侧，见下）。
- **V-07（版本漂移与缓存）**：`.brickkit/manifests/mdm/customer/2.0.0` 已存在时，把 `$C/component.yaml` 改成 `2.0.1`：
  - `brickkit lint mdm/customer` → `✅ components/mdm/customer/component.yaml` … `0 with errors, 0 warnings`，`exit=0`；
  - `brickkit lint --strict`（项目根，全项目）→ `✅ brickkit.yaml`、`✅ cross-file: brickkit.yaml ↔ deploy.yaml ↔ config/`、`✅ components/mdm/customer/component.yaml`，没有任何一行提到 2.0.1 或漂移（失败只来自尚未重建的旧组件：`17 with errors, 133 warnings`）；`brickkit lint --all` 同；
  - `up --dry-run`（锁内）→ `✅ mdm/customer@2.0.0  starting (top-level)`、`exit=0`，无警告；
  - 对照：把缓存挪开再 `up --dry-run` → `❌ Error: the install source has this component, but not the version that was asked for` / `Wanted version: mdm/customer@2.0.0` / `Install source local-dev (local): it has 2.0.1 here` / `1. A local install source holds only one version per component directory — the version you asked for can only live in the .brickkit/manifests/ cache, and the cache can be deleted`，`exit=1`；恢复缓存。
  - `git -C $C checkout component.yaml` 后 `up --dry-run` 恢复 `starting (top-level)`。
  - 结论：缓存确实掩盖了本地源的版本变化，三条命令都不报。但这是有意设计：缓存就是"项目钉的那个版本"的存放处（多版本并存），`brickkit docs 02-project-guide/04-focus-run` 写明 "The project moves forward one explicit `upgrade` at a time; nothing moves because a directory changed"；`brickkit build --help` 写明 "The source is the local repository when it holds that version, otherwise the version's git tag is exported"——即本地源已是 2.0.1 时，构建 2.0.0 取 tag，不会把 2.0.1 的代码打成 2.0.0。缺的只是一条提示（反馈候选，低优先级）。
- **V-09（focus 后改 deploy.yaml）**：锁内 `brickkit up --focus mdm/customer --dry-run`（`✅ Local mode is on…` / `deploy.local.yaml was copied from deploy.yaml`），再给 deploy.yaml 的 mdm/customer 条目加 `labels: {probe: "v09"}`：
  - `brickkit up --dry-run` 第一行 `Local mode is on: using deploy.local.yaml (brickkit local off switches back to deploy.yaml)`、第二行 `🎯 Focus: mdm/customer`，此外没有任何"deploy.yaml 比副本新 / 改动不生效"的提示；生成文件里 `（没有 probe）`。
  - `brickkit local status` → `Local mode: on` / `deploy.local.yaml: present, in use` / `✅ deploy.local.yaml matches brickkit.yaml`（只比组件集合，不比 deploy.yaml 内容）。
  - `brickkit lint --strict mdm/customer` 也不提。
  - 复原：deploy.yaml 拷回、`up --all --dry-run`、`brickkit local off`（`deploy.local.yaml is kept; brickkit local on uses it again`）、删掉副本，`local status` → `Local mode: off` / `deploy.local.yaml: none`，`up --dry-run` 里 probe 0 处。
  - 结论：改动静默不生效成立；`up` 每次都打印"本地模式开着、读的是 deploy.local.yaml"，算醒目，但看不出 deploy.yaml 已经改了。这与项目 AGENTS.md 易错点和 brickKit 文档一致（"It replaces deploy.yaml wholesale"），是设计而不是 bug。反馈候选：`local status` / `up` 在 deploy.yaml 自复制后变过时提示 `brickkit local refresh`。`make verify` 已改成收尾时删掉自己建的副本，避免这条坑从工具里冒出来。
- V-06（组件发布半程）：由控制者在 `make ship` 时记录。

### 结论

完成。mdm/customer 2.0.0 的组件仓库 9 个提交就绪（未推送、未打 tag），`make verify … FOCUS=1` 全部 PASS（带 token 一项 SKIP，待 T25），契约包不需要新 tag。遗留：父仓库的项目文件与两个工具文件待控制者提交；`make gates` 的 import-scan 误判要先修（见反馈候选）。

### 反馈候选

- **be-acceptance import-scan 不认 SDK 子包**（项目工具，必修）：`import "github.com/brickKit/be-sdk-go/migrate"` 被判"组件互不 import"违规，`make gates` 停在第一个 gate。13 个 Go 组件在 `go-v2.sh --sdk v0.4.0` 之后全部会撞上（`shell` 子包的外壳也可能）。修法：`allowedShared` 改成"等于或以 `<白名单>/` 开头"。→ 直接交控制者（不进信箱：是本项目工具）。
- **component-loop 1.4 的 PATH 写法会让 v0.4.6 的旧 brickkit 遮住 v1.1.0**（项目文档 + 本机环境）：改成 `export PATH=$PATH:$HOME/go/bin`；`~/go/bin/brickkit` 要不要删由用户定。→ 直接交控制者，后面 12 个组件开工前必须改。
- **focus / mode: local 进程与依赖容器共用 `vars:`，基础资源地址没法分别给值**（brickKit）：文档的修法（deploy.local.yaml 的 `vars:` 写 localhost）在 focus 组件有容器依赖时会弄坏那些容器；本项目靠 host-gateway IP 两边都通绕过去。建议 brickKit 对本机进程把 `host.docker.internal` 换成 `localhost`（`extra_hosts` 本来就是它加的），或提供只作用于本机进程的 vars。→ 先进 to-verify：有依赖的组件（erp/sales）focus 时再确认绕法够用，再决定是否进信箱。
- **V-09**：`local status` / `up` 不提示 deploy.yaml 在复制之后改过（建议记录复制时的内容哈希，变了就提示 `brickkit local refresh`）。→ to-verify，低优先级（行为有文档）。
- **V-07**：本地源版本与 `brickkit.yaml` 钉的版本不同、缓存在服务旧版本时，`lint` 可以给一行 ℹ️。→ to-verify，低优先级（设计如此）。
- **V-01**：项目侧缺常设的配置键命名门禁（迁移工具的 `--check` 是一次性的）：建议在 be-acceptance 加一个 gate（`configSchema` 键必须 `^[A-Z][A-Z0-9_]*$`、不撞保留名）。→ 项目内，交控制者。
- **`brickkit add` 重排 YAML 注释**：`brickkit.yaml` 的注释块从缩进挪到行首、行尾注释对齐被压成一个空格。不影响行为，只让 diff 变脏。→ to-verify（再观察一次 `remove` / `upgrade` 是否同样）。

## 给后续组件的模板说明

### 脚本做了什么、人要做什么

| 步骤 | 脚本 | 实际耗时 | 人要做的 |
|---|---|---|---|
| C1 前置 | `env.sh`（变量） | 1 分钟 | 读旧文档与设计；**PATH 写成 `export PATH=$PATH:$HOME/go/bin`（追加，不是前置）** |
| C2 骨架 | `docs-skel.sh` + 两条手工命令 | <1 秒 | 无 |
| C3 清单 | `migrate-manifest.py --write / --check` | 1 秒 | 无（新键 / 新依赖 / 新权限只改 `manifest-overrides.yaml`） |
| C4A 机械迁移 | `go-v2.sh --sdk v0.4.0` | 5 秒 | 读 diff；4.5 两条 grep |
| C4B–D 重构、补接口、测试 | — | 本组件约 12 分钟 | 全部人工：重构、红绿、注释清理、Makefile / Dockerfile / seed |
| C5 文档 | — | 约 3 分钟（不含构思） | 八份文件全部人工 |
| C6 门禁 | `make docs-check` + 组件 Makefile | 1 分钟 | 无 |
| C7 接入 | `make integrate` | 2 秒 | 无（本组件没有要人给值的键） |
| C7 真机 | `make verify … FOCUS=1` | 17–57 秒 | 读汇总表 |
| Step 6 种子 | — | 17 秒 | `deploy.verify.yaml` 要从 verify 输出目录拷回（见下） |
| C8 / C9 | — | — | 发布说明、记录 |

### 可以照抄的东西

- **组件 Makefile**：mdm/customer 的 `Makefile` 只有顶部 `ID` / `REPO` 两行是组件特有的，其余目标（`check-version` 双 tag 判据、`migrate-idempotent` 用 `PG_*`、`dag-check` 用 YAML 数依赖、`contract-check` 对比上一个发布 tag、`import-scan` 白名单 `<repo>/v<major>`、`module-check`、`docs-check`、`smoke`、`image`）可以原样拷。有依赖的组件 `dag-check` 改成"列出依赖并确认都是 `@2.0.0`"。
- **Dockerfile**：迁移文件已嵌进二进制，删 `COPY migrations /app/migrations`；保留 `COPY component.yaml /app/component.yaml`。
- **文档骨架**：mdm/customer 的八份文件结构（BRICKKIT 的"失败关闭时各回什么状态码"一段对每个连 authz / iam 的组件都成立）。
- **提交切分**：机械迁移一个；重构一个；每个红绿循环一个；代码注释一个；测试注释单独一个（写明断言未动）；Makefile / Dockerfile / seed 一个；文档一个。

### 摩擦点（交给 T8）

1. `~/go/bin/brickkit`（v0.4.6）遮住 v1.1.0——component-loop 1.4 的 PATH 写法要改（必改）。
2. `make gates` 的 import-scan 误判 `be-sdk-go/migrate`（必修，否则 T25 的 gates 全红）。
3. `verify-component.sh` 的 focus 步骤：已修（见"卡点与绕过" 3），控制者审查并提交。
4. `make verify` 收尾删 `deploy.verify.yaml`，brief Step 6 的命令找不到它：要么 verify 不删，要么 Step 6 改成从 `$OUT/deploy.verify.yaml` 拷回（本组件这样做）。
5. `migrate-manifest.py --write` 的手改保护会被"清理 assembly.yaml 里引用归档文档的注释"触发（之后 `--write` exit 3）：要么脚本顺手把这些注释改掉，要么清单写明"注释清理放在最后一次 `--write` 之后"。`--check` 不受影响。
6. `go-v2.sh --recheck` 也要求 `BE_SCRATCH`（经 `env.sh`），没设直接 exit 2，提示清楚但多一步。
7. `make integrate` 第 1 步把 `db-init` 的约 1000 行 psql 输出（`CREATE SCHEMA` / `GRANT` / NOTICE）全部打到终端，真正的结果行淹在里面；建议只打印摘要、细节进日志。
8. 代码地图第一张表里，任何列的行内代码只要含 `/` 都会被 `DOC_PATH_MISSING` 当路径查——写 tag、模块路径时不加反引号；表格单元里也不能写 `a|b` 这种带竖线的行内代码。
9. `.proto` 的注释改动也会改 `gen/`：注释清理不碰 `.proto`，留到下一次真实契约变更一起改（否则平白多一个契约包 tag）。
10. `buf breaking --against '.git#branch=main'` 在 main 上等于自己比自己——组件 Makefile 的 `contract-check` 要对比上一个发布 tag（本组件已改，模板照抄）。

## 小结

- 完成：组件仓库提交（components/mdm/customer，均未推送）：
  - b2ac80e chore: 迁移到 brickKit v1 骨架与 2.0.0 清单（机械步骤）
  - 07fc475 refactor(repo): repo.go 按读 / 写拆成三个文件，抽出写命令共用的事务步骤
  - 8fa49e8 fix: 非法列表游标返回 400 而不是 500
  - 30aad1b fix: REST GET /customers 读取契约里已有的 created_after / created_before
  - 8f91636 feat: GET /customers 新增关键字 q（code / name，前缀优先，游标分页）
  - 1329147 docs(code): 代码注释改写成原因本身，不再引用归档文档与历史
  - 550d6be test: 测试注释改写成测的是什么、为什么，不再引用归档文档
  - 5464a59 chore: Makefile / Dockerfile / 种子脚本按 v1 改；种子数据加关键字搜索样例
  - 10562dc docs: 写满 BRICKKIT / AGENTS / README / docs/design 四对文档（2.0.0）
- 父仓库待控制者提交（脚本写出，未提交）：`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/mdm-customer.yaml`、`AGENTS.md`（组件表）、`components/mdm/customer`（指针，ship 之后）；另有本 Task 改的工具 `infra/scripts/verify-component.sh`、`infra/scripts/tests/test_verify_deploy.py`，以及本记录。
- 需要控制者裁定的：import-scan 白名单修法；PATH 写法与旧 `~/go/bin/brickkit`；verify 是否保留 `deploy.verify.yaml`；关键字搜索沿用默认 90 天窗口（项目约定）是否合适（选择器要显式传 `created_after`，已写进 design.md 未决问题）。
- 遗留到后续：带 token 打受保护路由得 200（T25）；`.proto` 注释清理（下一次契约变更）；`Get` / `List` 返回联系人与开票信息（未决，未排期）。
- 检查点：mdm/customer 2.0.0，tag `2.0.0` / `v2.0.0` 待 `make ship`，契约包不需要新 tag，组件 HEAD 10562dc。

## 修复轮（ship 前，控制者裁定 R19，依据审查 `task-7-review.md`）

### 目标

ship 前修完审查列出的 pre-ship 项与控制者点名的模板项，免得 2.0.0 刚发布就要 2.0.1。

### 环境

同上；开工前 `brickkit version` → `BrickKit CLI v1.1.0`，`command -v brickkit` → `/home/zhijie/.local/bin/brickkit`；全程 `PATH=$PATH:$HOME/go/bin`（追加，不前置）。

### 步骤

1. **归档 / 历史引用（Important 1）**：`go.mod` 嵌套契约包的注释换成现行原因（调用方只 require 契约包、同一外壳里 MVS 只选一份生成代码、`/v1` 不能做模块路径结尾、replace 只给本仓库构建用）；`buf.yaml` 删"（设计计划 §3）"；`LICENSE` 删指向归档文档的一行。顺带 Minor 2：design(.zh).md 里 billing_infos 改成"还没有任何接口读写它"、删"每个客户一到三条"、游标一句去掉"格式不变"、未决问题把联系人与开票信息分开写；BRICKKIT(.zh).md 拥有清单写明联系人读接口不返回、开票信息无接口。核对：`git ls-files | grep -v -e '^gen/' -e '\.proto$' -e '^migrations/.*\.sql$' -e '^\.claude/' | xargs grep -nE '§|决策 ?[0-9]|设计计划|设计书|阶段[一二三四五六0-9]|总纲|手册|铁律|Task ?[0-9]'` → `无命中`；`go mod tidy` 保留注释；`make docs-check ID=mdm/customer` → `0 with errors, 0 warnings`。提交 f9d0632。
2. **`make test` 没设 DSN 时大声失败（Important 3）**：
   - 红（修前）：`env -u TEST_PG_DSN make test` → 四个包 `ok`，`exit=0`（全部 SKIP 却显示通过）。
   - 修后：`env -u TEST_PG_DSN make test` → `✗ 没设 TEST_PG_DSN：连库测试会全部 SKIP 而显示 ok（设法见 AGENTS.md 的 Build and test）`、`make: *** [Makefile:39: test] Error 1`、`exit=2`。
   - 绿：设了 DSN 的 `make test` → 四个包 `ok`、`exit=0`；`go test ./... -count=1 -v | grep -c -- '--- SKIP'` → `0`。AGENTS(.zh).md 的 Build and test 改成这条可核对的计数。提交 933e0a5。
3. **栈扫描在 `go list` 失败时大声失败（Important 4）**：
   - 红（修前）：`GOFLAGS=-mod=bogus make import-scan` → `✓ 无组件间 import`、`exit=0`；`module-check` 同样 `✓`、`exit=0`。
   - 修法：先 `deps="$$(go list -deps …)" || { echo "✗ …"; exit 1; }`，再用 awk 过滤，去掉 `|| true`。
   - 修后：`-mod=bogus not supported (can be '', 'mod', 'readonly', or 'vendor')` / `✗ go list -deps ./... 失败，没法扫 import` / `make: *** [Makefile:64: import-scan] Error 1`、`exit=2`；module-check `✗ go list -deps 失败，没法核对依赖栈`、`exit=2`。
   - 绿：正常环境两者 `✓`；PATH 上放一个假 `go` 输出 `erp-sales/v2/…` 与 `lib/pq`，import-scan 报 `github.com/brickKit/erp-sales/v2/backend/internal/repo`、module-check 报 `github.com/lib/pq`（过滤逻辑没丢）。提交 70eb317。
4. **发布说明**：标题改 `## 升级前必须做（破坏性变更）`；两个 URL 键改成"改为必填（1.x 可以不配）"；加一行"迁移状态表沿用 `schema_migrations_mdm_customer`，已有库直接升级"（审查已核对）。
5. **verify-component.sh 的两个缺口（父仓库，未提交）**：
   - 任何退出路径都还原 deploy.local.yaml：`on_exit` 里 `local off` + `focus_restore` 挪到 `KEEP` 判断之外（KEEP 只保留容器，focus 进程本来就停掉）；正常路径 `local off` 成败都调用 `focus_restore`。
   - 本地模式关着却留有 deploy.local.yaml：先移到 `$OUT/deploy.local.yaml.stale`，`local on` 从 deploy.yaml 重新复制，收尾放回原处；本地模式开着时才沿用（备份 + 恢复）。`focus_prepare` 拿验证前 `brickkit local status` 的第一行判断（精确匹配 `Local mode: on`）。缺 `config/vars.yaml` 时跳过改写不报错。注释写明"只在 Linux 原生 Docker 上验证过"。
   - 测试：新增 5 条（过期副本被移开且收尾放回；本地模式开着时用并恢复个人副本；`local off` 失败时删掉自建副本 / 恢复个人副本；中断时删掉自建副本；KEEP=1 中断时恢复个人副本且不 down）。其中 3 条在上一轮脚本上 FAIL（`test_focus_stale_local_copy_set_aside`、`test_interrupt_with_keep_restores_local_copy`、`test_local_off_failure_still_restores`，`21/24 通过`），新脚本 `24/24 通过`。
6. **门禁与真机复验**：新 HEAD 70eb317 上 `make check-version test migrate-idempotent dag-check contract-check import-scan module-check docs-check` 全绿。verify 里 `FORCE_BUILD` 是现成变量（`verify-component.sh:14`、`:269` 给 `brickkit build` 加 `--force`）。`make -C $ROOT verify ID=mdm/customer ROUTE=/mdm/customer/customers FOCUS=1 FORCE_BUILD=1`（05:15:45–05:16:49，64 秒）：build.log `✅ Built mdm/customer@2.0.0 → mdm-customer:2.0.0`；汇总表除带 token 一项 SKIP（待 T25）外全部 PASS（表见报告）；收尾后 `Local mode: off`、`deploy.local.yaml: none`、`deploy.verify.yaml` 不存在、无本项目容器。

### 现象

- 符合预期：三个静默成功路径都复现了红、修后大声失败；verify 新逻辑真机一次通过。
- 值得一提：`--force` 重建后 `docker image inspect mdm-customer:2.0.0` 的 `Created` 仍是 04:46:04、镜像 ID 不变——本轮只改了注释、文档、Makefile，`-trimpath` 编译出的两个二进制逐字节相同，最终阶段的层全部命中缓存；镜像内容就是新 HEAD 的产物。

### 卡点与绕过

无。没有读 brickKit 源码。

### 结论

修复轮完成。组件 HEAD 70eb317（`main...origin/main [ahead 12]`），契约包仍不需要新 tag，可以 ship。

### 反馈候选

本轮无新增；审查 Part 3 的 T8 回灌项（版本断言、seed 并进 verify、历史引用扫描脚本化等）由 T8 处理。
