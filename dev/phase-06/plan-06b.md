# 06b 组件重建 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> 开发文件（`dev/`），阶段结束后归档；正式文档不得链接本文件。

**Goal:** 把 13 个后端组件按 brickKit v1.1.0 重建到 2.0.0 并真实发布，4 个外壳装上成员后发布 1.0.0；在重建后的系统上跑通"商机赢单 → 订单 → 库存预留 → 应收"的业务闭环；`frontend/standard` 留给 06c。

**Architecture:**
- **工具先行**：重复 13 遍的机械步骤（configSchema 键名改写、Go `/v2` 与契约包嵌套模块、`config/<repo>.yaml` 填写、`deploy.teardown.yaml` 同步、单组件真机验证、发布 + 双 tag + 契约包 tag）先做成脚本，每个组件都用同一套脚本，人只做判断类工作（代码审查、补接口、写文档）。
- **试点定模板**：mdm/customer 第一个走完全程，审查后把发现的问题回灌进 `component-loop.md` 和脚本，再铺开。
- **按依赖分波次并行**：没有强依赖的 8 个组件同时做；有强依赖的组件只要上游一发布就开工（代码和文档部分甚至可以更早开工）；外壳在它的成员全部发布后组装。
- **组件仓库内并行，项目层串行**：组件仓库里的工作各做各的；凡是动到项目共享状态的命令（`brickkit add/upgrade/up/down/build/local`、`config/`、部署文件、`registry/`、`.env`、`make test-db-init`）一律经项目锁串行执行。

**Tech Stack:** brickKit CLI v1.1.0；Go 1.25（Gin、pgx/v5、nats.go、golang-migrate）；Python 3.12（FastAPI、asyncpg、yoyo、WeasyPrint）；TypeScript（Node ≥ 24、GraphQL、vitest）；Bash；Python 3 + PyYAML（脚本）。

**Spec:** [`spec.md`](spec.md) §5（以本计划为准，下面列出与 spec 的差异）；总计划 [`plan.md`](plan.md)（含"跨子阶段待办"，本计划继承）；输入：[`batches/06a.md`](batches/06a.md) §6（遗留小问题）与 §7（给 06b 的输入）、[`component-loop.md`](component-loop.md)（单组件闭环清单）、[`frontend-needs.md`](frontend-needs.md)（各组件要补的接口）、[`to-verify.md`](to-verify.md)（V 项）。

**与 spec §5 / component-loop 的差异（以本计划为准）：**

| 原写法 | 本计划 | 原因 |
|---|---|---|
| 批次 B1–B6 串行，每批结束停下汇报 | 波次并行（见"任务依赖"），全程不停，只有 brickKit 严重 bug 才停 | 用户授权的自主模式（2026-10-02） |
| 试点 mdm/customer 完成后停下请用户拍板 P1–P8 | 试点完成后由审查者审查，控制者裁定 P1–P8（预设见下文"预设裁定"），记为 R38 起的裁定 | 同上 |
| 外壳是项目代码 | 外壳是独立仓库，以子模块挂在 `shell/be/<name>/`，在自己的仓库里发布裸 tag `1.0.0` | 决策 0108 |
| `infra/scripts/component-lint.sh` 限定单组件 lint | `brickkit lint <id>` / `make docs-check ID=<id>` | brickKit v1.1.0（F06-004 已修） |
| 组件 `AGENTS.zh.md` 手写一节占位 `## BrickKit` | 不再需要 | brickKit v1.1.0（F06-003 已修，R21 退役） |
| 每批一份批次记录 `batches/<批次>.md` | 每个组件一份过程记录 `dev/test-records/06b/<repo>.md`；06b 结束写一份汇报 `batches/06b.md` | 并行任务不能同时改一个文件 |

---

## 执行方式

- **角色**：实现者（每次只拿到一个 Task 的简报）、审查者（审查一个 Task 的产出）、控制者（调度、裁定、打 tag、推送、父仓库提交）。控制者的台账在 `.superpowers/sdd/plan-06b/progress.md`（已被 git 忽略）。
- **简报内容**：控制者派发组件 Task 时，把本计划的 Global Constraints、Review Focus、"组件 Task 通用流程"一节、该 Task 本身，以及 `component-loop.md` 的路径一起贴进简报。实现者不需要读本计划的其余部分。
- **"已发布"的含义**：组件仓库里的提交已推送，`2.0.0`（Go 组件还有 `v2.0.0` 和需要时的 `gen/<domain>/<name>/v1.x.y`）已推送到远端，`make ship` 的外壳视角拉取检查通过。只有控制者执行 `make ship`。下游 Task 的"前置"指的都是"上游已发布"。
- **实现者在组件仓库里只提交，不推送、不打 tag**（R4）。实现者在父仓库里不提交任何东西：父仓库工作区里的改动（`brickkit.yaml`、`deploy*.yaml`、`config/`、`AGENTS.md` 组件表、`registry/`）由脚本在项目锁下写出，控制者按路径提交（R5）。
- **项目锁**：`infra/scripts/project-lock.sh`（Task 5 Step 0 产出）。`make integrate`、`make verify`、`make permissions`、`make test-db-init`、`make dev-env`、`make db-init` 自己会拿锁；其它动项目状态的命令手工跑时写成 `bash infra/scripts/project-lock.sh -- <命令>`。拿不到锁就等，不要绕开。
- **记录**：每个组件、外壳、集成任务各写一份 `dev/test-records/06b/<repo>.md`，格式按 spec §10（目标 / 环境 / 步骤〔命令 + 关键输出原文，不截断、不只取 tail〕/ 现象 / 卡点与绕过 / V 项 / 结论 / 反馈候选）。实现者不改 `to-verify.md`，V 项结论写在自己的记录里，由控制者合并。
- **停下的唯一条件**：brickKit 严重 bug，即 brickKit 的实际行为与它的文档或 skill 不符，并且挡住了任务、项目内没有正当解法（例如 `release` 把 tag 打在错误的提交上、`up` 生成的 compose 文件本身是坏的、`lint`/`up` 崩溃）。这时控制者停下告诉用户，并写一条可复现的反馈草稿。其它一切（测试红、设计取舍、边界问题）由控制者裁定并记录，不停。
- **component-loop.md §7 的"停下汇报"条件**在 06b 一律改成"控制者裁定并记录"，例外仍然保留：新建或删除 GitHub 仓库、强推、移动或删除已推送的 tag——这些不做；真遇到了先告诉用户。

## 任务依赖与并行

| Task | 内容 | 前置（必须完成） | 可以提前开始的部分 | 并行组 |
|---|---|---|---|---|
| T0 | 基线与清点 | — | — | 串行第一个 |
| T1 | be-sdk-go v0.4.0（迁移入口包 + 遗留小问题） | T0 | — | W0 |
| T2 | be-sdk-python v0.4.4（遗留小问题） | T0 | — | W0 |
| T3 | 一次性迁移工具包 `dev/phase-06/tools/` | T0 | — | W0 |
| T4 | 长期脚本：集成、真机验证、发布、teardown 同步 | T0 | 跑测试前需要 T5 Step 0（项目锁脚本） | W0 |
| T5 | 项目锁、数据库重置与旧脚本修正 | T0 | — | W0 |
| T6 | 更新 `component-loop.md`（v1.1.0 + 自主模式 + 工具） | T0 | — | W0 |
| T7 | 试点 mdm/customer | T1–T6 | — | 串行 |
| T8 | 试点审查与模板回灌 | T7 已发布 | — | 串行 |
| T9 | mdm/product | T8 | — | W1 |
| T10 | erp/inventory | T8 | — | W1 |
| T11 | erp/finance | T8 | — | W1 |
| T12 | infra/authz | T8 | — | W1 |
| T13 | infra/workflow | T8 | — | W1 |
| T14 | infra/notification | T8 | — | W1 |
| T15 | integration/im-dingtalk | T8 | — | W1 |
| T16 | infra/print | T8 | — | W1 |
| T17 | infra/iam-casdoor | T12 已发布 | 通用流程 C1–C6 在 T8 之后即可开始 | W2 |
| T18 | erp/sales | T7、T9、T10、T11 已发布 | C1–C6 在 T8 之后 | W2 |
| T19 | crm/opportunity | T7、T9 已发布 | C1–C6 在 T8 之后 | W2 |
| T20 | infra/bff-mobile | T7、T9、T10、T13、T14、T18、T19 已发布 | C1–C6 在 T8 之后（按本计划写定的上游接口写代码） | W3 |
| T21 | 外壳 be/py-render | T16 已发布 | 外壳文档修正（T21 第 2 步）在 T8 之后 | S |
| T22 | 外壳 be/go-infra | T12、T13、T14、T15、T17 已发布 | 同上 | S |
| T23 | 外壳 be/go-core | T7、T9、T10、T11、T18 已发布 | 同上 | S |
| T24 | 外壳 be/go-backoffice | T19 已发布 | 同上 | S |
| T25 | 全栈集成与业务闭环 | T20–T24 | — | 串行 |
| T26 | 06b 遗留小问题收尾 | T25 | — | 串行 |
| T27 | 06b 汇报，进入 06c | T26 | — | 串行 |

```
T0 ─┬─ T1 ─┐
    ├─ T2 ─┤
    ├─ T3 ─┤
    ├─ T4 ─┼─ T7(customer) ─ T8 ─┬─ W1: T9 product ─┬────────────┬─ T19 opportunity ─┬─ T24 go-backoffice ─┐
    ├─ T5 ─┤                     │     T10 inventory ┼─ T18 sales ─┼───────────────────┼─ T23 go-core ───────┤
    └─ T6 ─┘                     │     T11 finance ──┘             │                   │                     │
                                 │     T12 authz ─── T17 iam ──────┼───────────────────┼─ T22 go-infra ──────┼─ T25 ─ T26 ─ T27
                                 │     T13 workflow, T14 notification, T15 im-dingtalk ┘                     │
                                 │     T16 print ──────────────────────────────────────── T21 py-render ─────┤
                                 └─ (W2/W3 的 C1–C6 可提前) ── T20 bff-mobile（W3） ─────────────────────────┘
```

控制者的调度规则：一个 Task 的前置一满足就派发，不等整个波次；同时在跑的实现者不超过 8 个（W1 正好 8 个）；真机验证靠项目锁自然串行，不需要另外排队。

## Global Constraints

- **brickKit CLI v1.1.0**（`brickkit version` → `BrickKit CLI v1.1.0`）。skill 里缺知识时先查 `brickkit docs <页面>`（`brickkit docs` 列出全部页）；只有它也答不了、不得不去读 brickKit 源码（`/home/zhijie/Desktop/github/brickKit`）时，才在自己的过程记录里写一条"知识缺口"（日期、缺的知识、在做什么、读了哪里、建议怎么下发），控制者合并进 `to-verify.md` 的 V-04 表。
- **版本**：组件一律 `2.0.0`，外壳一律 `1.0.0`。Go 组件同一提交上打两个 tag：`2.0.0`（`brickkit release`）和 `v2.0.0`（Go），模块路径以 `/v2` 结尾。契约包 `gen/<domain>/<name>/` 是独立嵌套 Go 模块，路径不带 `/v2`，tag 为 `gen/<domain>/<name>/v1.<minor>.<patch>`，只在生成物变化时打；组件根 `go.mod` require 一个真实存在的契约包版本 + 本地 `replace`。Python、TS 组件只有 `2.0.0`。外壳只有裸 tag `1.0.0`，在外壳自己的仓库里发布，绝不在父仓库用 `--path` 发布或打外壳 tag。工具仓库用带注释的 `vX.Y.Z` tag。
- **SDK**：Go 组件用 be-sdk-go **v0.4.0**（T1 产出），Python 用 be-sdk-python **v0.4.4**（T2 产出），TS 用 be-sdk-ts **v0.4.0**。外壳钉的 SDK 版本与成员相同；Python 外壳与成员钉同一个 tag（pip 不接受同一 git 依赖两个 tag）。
- **配置键**：一律大写下划线，键名就是环境变量名。不得以 `_ENDPOINT` 结尾，不得用 `COMPONENT_ID`、`COMPONENT_VERSION`、`PORT`、`BRICKKIT_SERVED_MEMBERS`、`BRICKKIT_SERVED_MEMBERS_CONFIG`。共享连接键 `PG_HOST`、`PG_PORT`、`PG_DATABASE`、`PG_USER`、`PG_PASSWORD`（`secret: true`）、`PG_SCHEMA`、`NATS_URL`、`S3_URL`、`OTEL_BASE_URL`、`AUTHZ_BUNDLE_URL`、`IAM_JWKS_URL`。没有 `default` 的键一律进 `required`。
- **配置值**（`config/<repo>.yaml`，由 `infra/scripts/config-fill.py` 填写）：共享值写 `$var:<名>`（`$var:` 后不空格）；`PG_USER` 写 `registry/schemas.tsv` 的 `role` 列字面量；`PG_PASSWORD` 写 `${<REPO 大写下划线>_DB_PASSWORD}`；`PG_SCHEMA` 写 schema 字面量；组件自有密钥写 `${<REPO 大写下划线>_<KEY>}`；属于基础资源的密钥（如 Casdoor 管理员口令）沿用基础资源已有的变量名；多行密钥用 `file://.secrets/<repo>/<文件>`。密钥值只进 `.env` / `.secrets/`，不进任何提交。
- **authz / iam 地址**：只在 `config/vars.yaml` 写一次，用成员自己的服务名 `http://infra-authz-2-0-0:8223/authz/bundle`、`http://infra-iam-casdoor-2-0-0:8200/.well-known/jwks.json`；任何部署文件都不用 `vars:` 覆盖；authz 或 iam 再发版时必须同步改（`make gates` 的 `service-hostname-scan` 把关）。
- **数据库**：组件以 `<schema>_rw` 登录（`PG_USER`）；外壳以 `shell_<name>` 登录并对每个成员 `SET LOCAL ROLE <member>_rw`；`SET ROLE` / `SET search_path` 只能带 `LOCAL`（用 `besdk.WithTx`）。测试库 `brickkit_test_db` 与演示库 `brickkit_db` 物理分开。
- **契约**：只增不改。新增字段、新 rpc、新路径、新事件可以；删字段、改类型、删 rpc / 路径 / 事件 subject 不可以。2.0.0 唯一允许的"破坏"是配置键改名（发布说明写明）。金额一律十进制字符串，List 一律游标分页。新增路由一律带权限键注册。
- **文档**：正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件和外壳的文档）不得链接 `dev/` 或 `archive/`（`make docs-boundary`）。组件五件套 + `docs/design.md`，各带同目录 `.zh.md`；中文固定标题照 skill 原文（BRICKKIT：组件定位 / 部署前准备 / 依赖说明 / 配置指南 / 契约索引 / 外壳声明；AGENTS：代码地图 / 构建与测试 / 设计取舍 / 易错点 / 改代码前自查；README：在项目里使用 / 文档 / 开发）。`BRICKKIT*.md` 不写相对链接；组件任何文档不写 `../` 链接；文档不写历史。`AGENTS.zh.md` 不再需要占位的 `## BrickKit` 一节。项目文档 `docs/en/` 与 `docs/zh/` 逐文件镜像（`make docs-mirror`）。
- **提交**：中文提交信息写进文件，`git commit -F <文件>`，提交后先 `git log --oneline -1` 核对，最后一行 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。父仓库只按路径提交（`git commit -F <msg> -- <路径…>`），不 `git add -A`。tag 与推送只由控制者在审查干净后做（`make ship`）；父仓库提交后推送（R31）。
- **不可逆操作**：绝不强推，绝不移动或删除已推送的 tag（Go 模块代理会永久缓存 `v` tag）；新建或删除 GitHub 仓库之前先告诉用户（06b 预期不需要）。
- **镜像与容器**：镜像只本地 `brickkit build`，不推送。每次真机验证结束都 `brickkit down`、`brickkit local off`；基础资源（`make up` 起的 postgres、nats、casdoor 等）可以一直开着。
- **测试**：不改测试去迎合实现；测试确实错了，单独一个提交并写明错在哪。新规则先写 L2 测试跑红再实现。有数据范围的接口必须有"别人的数据看不到"的真实建库测试。
- **重构**：旧组件是早期模型写的，允许大胆重构以提高质量（09-ai-development.md 的"Rewriting instead of patching"），但业务行为不变，除非是在修真实 bug（先写红测试）。

## Review Focus

以下五类错误，任务自己的测试都抓不到（全绿），审查者对每个组件 / 外壳 Task 逐条核对：

1. **成员悄悄对着自己的 v1 生成代码编译**。形态 B 组件被当成形态 A 改 `/v2`，`go mod tidy` 自动加回 `github.com/brickKit/<repo> v1.x.y`，组件和外壳都对着旧契约代码编译，所有门禁照绿。核对：组件目录 `go list -m all | grep "brickKit/<repo>"` 恰好两行（`…/<repo>/v2` 主模块、`…/<repo>/gen/<domain>/<name> v1.x.y => ./gen/…`）；外壳目录 `go list -m all | grep -E 'brickKit/[a-z-]+ v1\.'` 为空。
2. **配置键改了名但代码没跟着读**。`rt.Config.StringOr("pgSchema", "x")` 这类旧键读法在新键注入后静默返回默认值；`EXCEPTION_ASSIGNEE_SUB`、`LOW_STOCK_THRESHOLD`、`IM_TARGET_ADAPTERS` 之类有默认值的键尤其危险——值配了，组件照样用默认值跑。核对：`migrate-manifest.py --check` 与 component-loop 4.5 的 grep 都是"无"；每个有默认值的自有键，真机时在 `config/` 里配一个非默认值，从行为上（接口返回、日志）确认生效。
3. **外壳托管了它没编译进去的成员版本**。`shell.members`、`main.go` 的 Registry、`go.mod`（Python：`pyproject.toml`）三处任一处不一致：成员没登记 → 外壳启动即退出；`go.mod` 选中的成员版本与 `shell.members` 不同 → 镜像里跑的代码不是项目以为的版本，没有任何报错。核对：三处逐项对比；`docker image inspect be-<name>:1.0.0` 的 `io.brickkit.shell.members` 标签；外壳目录 `go list -m all | grep brickKit/` 里每个成员恰好是 `v2.0.0`；`make gates` 的 `dependency-version-scan` 绿。
4. **authz / iam 地址过时**。`config/vars.yaml` 的两个 URL 与 `brickkit.yaml` 里 authz / iam 的版本对不上（例如 T26 给 authz 发了 2.0.1 却没改 URL），或者有人改用了外壳服务名：每个受保护路由都回 `503`/`403`，`/healthz` 却一直是绿的。核对：`make gates` 的 `service-hostname-scan` 零违规、零警告；T25 每个组件经外壳带真 token 打一条受保护路由得到 `200`。
5. **数据范围的 OR 里有一个操作数是"全匹配"**。06b 新增的 sales `stats/summary`、crm `funnel` / `stage-history`、inventory `warehouses` / `balances/list` / `stats/summary`、finance `ar-ledger/summary` 都要按数据范围过滤；`owner OR org` 里任一操作数取了"无限制"的缺省值，整个条件匹配一切，人人看到全部数据。核对：每个新端点都有真实建库的"别人的数据看不到"测试（两个用户、两个范围），审查者读一遍操作数是从调用者真实范围派生的；有显式视角参数（`view=mine|dept`）的端点按参数切换，不是 OR。

另外两条同样要看：**多行或含 `$` 的值穿过外壳 JSON 时被 compose 的 `${VAR}` 二次替换弄坏**（`APP_TOKEN_SIGNING_KEY_PEM`、`file://registry/permissions.tsv`），只能在运行期核对（`docker exec … printenv` 与原文逐字节比较）；**Python 顶层包名冲突**（infra/print 的业务包叫 `app`，外壳 py-render 再装第二个 Python 成员就互相覆盖），T16 改成 `infra_print`。

## 预设裁定（T8 由控制者确认，记为 R38 起的裁定）

component-loop §6.2 的试点拍板项 P1–P8，以及本计划新增的几项。实现者先按预设做；T8 推翻哪一条，T8 负责把 mdm/customer 补齐并通知已开工的 Task。

| # | 问题 | 预设 |
|---|---|---|
| P1 | `AUTHZ_BUNDLE_URL`/`IAM_JWKS_URL` 一律 required、不给默认值 | 是 |
| P2 | `PG_SCHEMA` 带默认值（= registry schema），`config/` 里同时写字面量 | 是 |
| P3 | 契约包一律嵌套模块（形态 B 拆出来）、不带 `/v2`、tag `gen/<domain>/<name>/v1.x.y`；根 `go.mod` require 真实 tag + 本地 replace | 是；形态 B 拆出来的第一个 tag 一律 `v1.0.0`，即使同一轮契约有新增（v1.0.0 就包含新增），解决 06a N-5 |
| P4 | 迁移入口的驱动 | be-sdk-go v0.4.0 的 `migrate` 包（golang-migrate + `database/pgx/v5` + 内嵌迁移文件），每个 Go 组件的 `backend/cmd/migrate/main.go` 变成一行 |
| P5 | `assembly.yaml` 清理 | 删 `version`、`shell`、`asset`（旧 fork 指引写的是 v0 机制；fork 规则已在项目 AGENTS.md）；保留 `edge_routes`（网关路由表的输入，be-ops `routes` 尚未实现，归 06c）、`menus`、`domain`、`tier`、`data`、`data_scopes`、`permissions` |
| P6 | 组件仓库提交 `brickkit skills update` 写入的 `.claude/skills/brickkit-component/` | 提交 |
| P7 | 组件自有密钥的变量名 | `${<UREPO>_<KEY>}`；属于基础资源的密钥沿用基础资源的变量（iam-casdoor 的 `CASDOOR_ADMIN_PASSWORD: ${CASDOOR_ADMIN_PASSWORD}`） |
| P8 | 先跑容器形态再跑 focus | 是（`make verify` 先容器、`FOCUS=1` 时再 focus） |
| P9 | 商机 `order_id` 回填的事件方案 | erp/sales 在已有事件 `sales.order.created.v1` 的 payload 里**新增**可空字段 `source_opportunity_id`（只增）；crm/opportunity 新增消费者订阅 `sales.order.created.v1`，`source_opportunity_id` 非空且等于本组件的商机时回填 `order_id`（幂等：已有值且相同则跳过，不同则记 ERROR 不覆盖）。不加任何依赖边（CRM 与 ERP 之间只有事件）。subject 不符合 `<domain>.<aggregate>.<action>` 命名（缺 `erp.`）是历史遗留，不改名（删 subject 属于破坏性变更） |
| P10 | 仪表盘统计的视角参数 | 与同组件 List 端点完全一致：crm `funnel` 带 `view`（取值 `mine` / `dept`，List 已有）；sales `stats/summary` 不带视角参数（sales 的 List 没有），只按数据范围过滤；06a 遗留的"`dept` 不是真值"按此消除 |
| P11 | bff-mobile 新增的可选依赖 | `infra/notification@2.0.0`、`crm/opportunity@2.0.0` 以 `optional: true` 加入（BFF 要经注入地址调它们的 REST）；缺席时对应字段不注册 |
| P12 | 库存余额列表的路径 | `GET /balances/list`（frontend-needs §2.3），不改 `GET /balances` 的单条语义；§1.1 表里写的 `GET /balances` 以 §2.3 为准 |

---

## 组件 Task 通用流程（T7、T9–T20 都按它走）

每一步的细节在 `component-loop.md` 对应小节（T8 已按试点回灌）；这里给出用工具后的确切命令和判据。下面的 `$ROOT`、`$ID`、`$REPO`、`$UREPO`、`$C`、`$S`、`$SCHEMA`、`$ROLE`、`$SVC` 由 `env.sh` 给出。Bash 工具每次调用都是新 shell，**每次调用开头都重跑这三行**：

```bash
export ROOT=/home/zhijie/Desktop/github/be-assembly-standard ID=<scope>/<name>
export BE_SCRATCH=/tmp/claude-1000/-home-zhijie-Desktop-github-be-assembly-standard/1c264f6e-aaa4-4367-bc16-6601a194d7e7/scratchpad
E=$(bash $ROOT/dev/phase-06/tools/env.sh $ID) && eval "$E" || exit 2   # 核对 brickkit v1.1.0 与 buf；PATH 追加 ~/go/bin；TEST_PG_DSN/TEST_NATS_URL（不打印值）
```

- [ ] **C1 前置**（component-loop 第 1 步）：上面三行不报错；`command -v protoc-gen-go` 在 `~/go/bin` 下（component-loop 1.4）；`git -C $C status -sb` 第一行是 `## main...origin/main` 且下面没有文件行；`git -C $C fetch --tags -q` 后最后一个 1.x tag 在本地；`make -C $ROOT check` 全绿；本 Task 的前置都"已发布"（`git -C $ROOT/components/<上游> ls-remote --tags origin 2.0.0` 有一行）；按 component-loop 1.5 的顺序读文件。开 `dev/test-records/06b/$REPO.md`。样板是已发布的 `components/mdm/customer`（2.0.0）与它的记录 `dev/test-records/06b/mdm-customer.md`；裁定见 `dev/test-records/06b/T8-pilot-review.md`。
- [ ] **C2 骨架与文档骨架**（第 2 步）：
  ```bash
  bash $ROOT/dev/phase-06/tools/docs-skel.sh $ID
  git -C $C rm -q docs/手册.md 2>/dev/null; (cd $C && brickkit skills update)
  ```
  通过：`$C` 下有 `BRICKKIT.md`/`BRICKKIT.zh.md`/`AGENTS.md`/`AGENTS.zh.md`/`README.md`/`README.zh.md`/`docs/design.md`/`docs/design.zh.md`/`CLAUDE.md`（恰好 `@AGENTS.md`），`AGENTS.md` 末尾有 `<!-- brickkit:managed:begin lang=en -->`；旧文件已留底在 `$S/old/`（脚本做）。
- [ ] **C3 清单**（第 3 步）：
  ```bash
  cd $ROOT
  python3 $ROOT/dev/phase-06/tools/migrate-manifest.py $ID --write
  python3 $ROOT/dev/phase-06/tools/migrate-manifest.py $ID --check; echo "exit=$?"
  brickkit lint $ID 2>&1 | tee $S/lint-c3.log
  ```
  通过：`--check` 输出全部"无"且 `exit=0`；`brickkit lint` 第一行是 `🔎 Only <id> is checked…`，没有 `MANIFEST_INVALID`，只剩 `DOC_*` 警告。`--write` 同时写出发布说明骨架 `$S/notes-2.0.0.md`（只在不存在时写；每次都刷新 `notes-2.0.0.generated.md`，"升级前必须做"不一致时打印 ⚠️），清掉 `assembly.yaml` 里引用归档文档的注释并把原文列进 `$S/assembly-removed-comments.txt`。**C3 之后对清单的任何增量（新权限键、新配置键、新菜单、新依赖）只写进 `dev/phase-06/tools/manifest-overrides.yaml`（`permissions_add`、`add_properties`、`menus_add`、`edge_routes_add`、`deps_add` 等），再重跑 `--write`；手改 `component.yaml` / `assembly.yaml` 会被手改保护拒绝（exit 3）。** 有新权限键时跑 `make -C $ROOT permissions`（拿锁；通过：`registry/permissions.tsv` 只增不删、`make registry-check` 绿）。
- [ ] **C4 代码**（第 4 步）：
  ```bash
  bash $ROOT/dev/phase-06/tools/go-v2.sh $ID --sdk v0.4.0; echo "exit=$?"     # 只 Go 组件
  ```
  通过：`exit=0`（脚本最后跑 component-loop 4.4 的全部判据，含"gen 是当前 .proto 的生成结果"，任一不满足就非零退出）。`--sdk v0.4.0` 起，脚本顺带把迁移入口改成 SDK 的一行（`migrate.Main(migrations.FS)`）并删掉 `module.go` 的 `Migrations:`，人工只读 diff、核对 Dockerfile 的目的路径。然后：`Makefile` 照抄 mdm/customer 的模板（R43，component-loop 4.7）；脚本按 4.9；审查按 4.10–4.12（本 Task 的"重构重点"）；补接口按 4.13–4.15（契约先改：`.proto` → `buf generate` → `go-v2.sh $ID --recheck`，让根 `go.mod` require 正确的契约包版本）；测试按 4.16–4.17：`make -C $ROOT test-db-init ID=$ID`（拿锁，只跑本组件的 migrate-idempotent）、`cd $C && make test`（`TEST_PG_DSN` 由开头三行提供；没设时 `make test` 会大声失败，而不是全部 SKIP 显示 ok）。每个红绿循环一个提交（组件仓库）。C4 结束跑一次 `bash $ROOT/dev/phase-06/tools/component-check.sh $ID`（旧键读取、种子脚本、历史引用、文档对称共十项）：第 1–9 项的 FAIL 先修；第 10 项（文档占位符）此时一定 FAIL（文档还是骨架，C5 才填），原文记录即可；C5 / C6 之后十项全部 PASS（component-loop 4.18）。
- [ ] **C5 文档**（第 5 步）：按 component-loop 5.1 写满八份文件，`docs/design.md` 从 `archive/pre-v1/docs/dev/design/$REPO.md` 只提取结论，加上 `$S/assembly-removed-comments.txt` 里仍然成立的结论，并写进本 Task 引入的新设计（新接口、事件方案）。旧键 → 新键对照只写在发布说明里，不写进 BRICKKIT.md（R42）。
- [ ] **C6 版本与门禁**（第 6 步）：
  - `make -C $ROOT docs-check ID=$ID; echo "exit=$?"` → `0 with errors, 0 warnings` 且 `exit=0`；
  - `bash $ROOT/dev/phase-06/tools/component-check.sh $ID` → `exit=0`；
  - `cd $C && make check-version test contract-check import-scan module-check dag-check` 全绿（Python / TS 用各自目标；`contract-check` 打印的 `--against` 行必须是上一个发布 tag，不是 `branch=main`）；`make -C $ROOT test-db-init ID=$ID` 绿（代替组件里直接跑 `migrate-idempotent`）；
  - `bash $ROOT/infra/scripts/project-lock.sh -- make -C $ROOT gates` 里本组件零违规（别的组件尚未迁移带来的警告不算）。
- [ ] **C7 接入与真机**（第 7 步，脚本自己拿项目锁）：
  ```bash
  make -C $ROOT integrate ID=$ID                      # add / config-fill / teardown-sync / lint / up --dry-run；db-init 详细输出进日志
  make -C $ROOT verify ID=$ID ROUTE=<本 Task 给的受保护路径> FOCUS=1 SEED=1   # 组件没有 seed 目标时 SEED 一行是 SKIP
  ```
  `integrate` 列出"需要人给值"的 required 键而失败时（`config-fill.py` 退出 3），按本 Task 的"配置值"一栏直接给值，再重跑 `integrate`（已加入的组件不会重复 add，已有值的键不会被覆盖）：
  ```bash
  bash $ROOT/infra/scripts/project-lock.sh -- python3 $ROOT/infra/scripts/config-fill.py $ID --set 'KEY1=VALUE1' --set 'KEY2=VALUE2'   # 每个键一个 --set；值里有 $ 时用单引号；secret 键只收 ${VAR} / file:// / $var:
  ```
  通过：两条命令都 `exit=0`，`verify` 打印的汇总表每行都是 `PASS` 或写明原因的 `SKIP`（例如"authz/iam 尚未加入项目，只验 401"）；汇总表和输出目录路径贴进记录。
- [ ] **C8 交接发布**（第 8 步）：补全 `$S/notes-2.0.0.md`（C3 生成的骨架；补"新增 / 修复"两节，确认 `--write` 没有打印 ⚠️ 漂移；格式见 component-loop 8.1），组件仓库提交（文档 + 版本），`git -C $C log --oneline -3` 贴进记录。**不推送、不打 tag**。向控制者交付（component-loop 8.2）：提交 SHA、发布说明路径、`verify` 汇总表、契约包是否需要新 tag 及版本号。控制者审查通过后执行 `make -C $ROOT ship DIR=components/$ID NOTES=$S/notes-2.0.0.md`（发布前先跑本组件范围的 `openapi-additive-scan` 与 `config-key-scan --strict`），然后在父仓库按路径提交该组件的指针与项目文件。
- [ ] **C9 记录**（第 9 步）：补齐过程记录；V 项结论、知识缺口、反馈候选写在记录里。

---

## W0 地基

### Task 0: 基线与清点

**Files:**
- Modify: `dev/phase-06/batches/06a.md`（§4 裁定表补 R28–R37）、`dev/phase-06/plan.md`（勾掉已完成的待办）
- Delete: `components/mdm/contracts/`（空目录，root 属主，不在 git 里）、`.superpowers/sdd/plan-06a/`（git 忽略的执行区）
- Create: `dev/test-records/06b/T0-baseline.md`

**Interfaces:**
- Produces: 06b 起点的基线记录（lint / gates / 版本 / 子模块），后面所有"是不是本次引入的"判断都以它为准。

- [ ] **Step 1: 确认 v1.1.0 清理任务已合入**（R35 退役、R21 退役，由另一个清理任务在本计划之前完成）

```bash
cd /home/zhijie/Desktop/github/be-assembly-standard
brickkit version                                   # BrickKit CLI v1.1.0
git status --short                                 # 期望：空（清理任务已提交）；不空就等它提交，不要动它的文件
test ! -e infra/scripts/component-lint.sh && echo "component-lint.sh 已删"
grep -n 'brickkit lint --strict $(ID)' Makefile    # docs-check 已改用 brickkit lint <id>
grep -c '^## BrickKit' shell/be/*/AGENTS.zh.md     # 每个都是 0
git submodule status
```

通过：五条都符合；`git submodule status` 每行开头是空格（不是 `+`）。不符合就停在这里，告诉控制者缺哪一项。

- [ ] **Step 2: 把 R28–R37 补进 `batches/06a.md`**

R28–R37 现在只记在 `.superpowers/sdd/plan-06a/progress.md`（git 忽略），删执行区之前必须搬进库里。在 `batches/06a.md` §4 的表格末尾按同样三列追加十行，内容从 progress.md 第 192–230 行提炼（每条：裁定一句话 + 判错的代价）：

| 编号 | 要点 |
|---|---|
| R28 | 06a 最终审查拆给两个审查者（代码 / 文档） |
| R29 | authz/iam 地址用成员服务名，换拓扑不覆盖 |
| R30 | component-loop 与路由题库同步到 R29 |
| R31 | fork 保留 `metadata.id`、版本照常升；父仓库推送；be-acceptance v0.4.1 tag 不重打 |
| R32 | 外壳各自独立仓库，子模块挂载，裸 tag 发布 |
| R33 | 阶段 06 内的决策可原地改写 |
| R34 | 项目 `docs/` 改为 en/zh 镜像树 |
| R35 | `component-lint.sh` 绕过 F06-004（已被 v1.1.0 取代，退役） |
| R36 | 决策全局连续重编号（中间步骤） |
| R37 | 决策按文件夹分号段 |

```bash
grep -c '^| R[0-9]' dev/phase-06/batches/06a.md     # 37
```

- [ ] **Step 3: 删除 06a 执行区与杂物**

控制者先把 progress.md 里"v1.1.0 adaptation"一节搬进新台账 `.superpowers/sdd/plan-06b/progress.md`，再：

```bash
rm -rf .superpowers/sdd/plan-06a
rmdir components/mdm/contracts && echo "空目录已删"
```

然后在 `plan.md` 的"跨子阶段待办"里把"删除 06a 的 SDD 执行区"改成 `[x]` 并写上本次提交号。

- [ ] **Step 4: 基线**

```bash
O=dev/test-records/06b; mkdir -p $O
S0=<本会话 scratchpad>/06b/T0; mkdir -p $S0
{ brickkit lint --strict 2>&1; echo "exit=$?"; } > $S0/lint-all.log
make gates  > $S0/gates.log 2>&1; echo "gates exit=$?"
make version-check > $S0/version-check.log 2>&1; echo "version-check exit=$?"
make docs-boundary docs-mirror registry-check
```

把 `lint-all.log` 按来源分类写进 `T0-baseline.md`：(a) `components/*` 旧清单的错误与警告（预期，06b 逐个消失）；(b) 4 个外壳 `members: []` 的 `MANIFEST_INVALID`（预期，外壳 Task 消失）；(c) **项目自己的文档**（`AGENTS*.md`、`README*.md`、`docs/`）的警告——v1.1.0 起它们也被检查。(c) 类在本 Task 直接修（它们是正式文档；改动同时满足 `make docs-mirror`、`make docs-boundary`），修完重跑，(c) 类为零。`make gates` 原文贴进记录（预期：`brickkit up --dry-run` 报"项目没有组件"之类，非零也照记）。

- [ ] **Step 5: 提交**

```bash
git add dev/phase-06/batches/06a.md dev/phase-06/plan.md dev/test-records/06b/T0-baseline.md <Step 4 改过的文档路径>
git commit -F $S0/msg.txt -- dev/phase-06/batches/06a.md dev/phase-06/plan.md dev/test-records/06b/T0-baseline.md <同上>
git log --oneline -1 && git push origin main
```

---

### Task 1: be-sdk-go v0.4.0

**Files:**（仓库 `tools/be-sdk-go`）
- Create: `migrate/migrate.go`、`migrate/migrate_test.go`
- Modify: `module.go`（删 `Module.Migrations` 字段）、`connection.go`（注释路径 + `sslmode` 说明）、`shell/*.go`（遗留小问题）、`README.md`、`go.mod`
- Parent: 子模块指针 `tools/be-sdk-go`（控制者提交）

**Interfaces:**
- Produces:
  ```go
  package migrate // github.com/brickKit/be-sdk-go/migrate
  // Main 是组件 backend/cmd/migrate/main.go 的唯一一行：func main() { migrate.Main(migrations.FS) }
  // 先校验参数（恰好一个，up 或 down；否则打印用法、exit 2，不读环境、不连库），
  // 再读 PG_HOST/PG_PORT/PG_DATABASE/PG_USER/PG_PASSWORD/PG_SCHEMA（缺任何一个 exit 1，报出键名），
  // 用 golang-migrate + database/pgx/v5 + source/iofs 跑；ErrNoChange 不是错误。
  func Main(src fs.FS)
  // Run 是 Main 的可测形式：env 与 args 显式传入，返回错误不退出。
  func Run(ctx context.Context, env map[string]string, args []string, src fs.FS) error
  ```
  DSN：`search_path=<PG_SCHEMA>`、`x-migrations-table=schema_migrations_<PG_SCHEMA>`（裸表名，不带 schema 前缀；不加 `x-migrations-table-quoted`）；口令里有 `@ : / %` 时正确转义（复用 `PGDSN` 的拼法）。`pgx` 的默认 `sslmode=prefer` 对不开 TLS 的本地库可用，不追加 `sslmode=disable`；部署者要强制 TLS 时在 `PG_HOST` 层面解决——这一点写进 README。
- `besdk.Module` 不再有 `Migrations` 字段（破坏性；所有 Go 组件在 06b 重建时一起改）。

- [ ] **Step 1: 写 `migrate` 的测试并跑红**

`migrate/migrate_test.go`，用 `TEST_PG_DSN` 指向的 `brickkit_test_db` 建一个临时 schema（测试结束删掉），内嵌两条迁移（`fstest.MapFS`）：
- `TestRunRejectsUnknownArgsBeforeReadingEnv`：`args` 为 `nil`、`["apply"]`、`["up","x"]` 都返回用法错误，且 `env` 为空 map 时也是用法错误而不是"缺 PG_HOST"。
- `TestRunUpTwiceIsIdempotent`：`up` 两次都成功，第二次 `ErrNoChange` 不报错；迁移状态表 `schema_migrations_<schema>` 落在该 schema。
- `TestRunDownThenUp`。
- `TestRunMissingKeyNamesTheKey`：缺 `PG_SCHEMA` 时错误信息含 `PG_SCHEMA`。
- `TestRunPasswordWithSpecialChars`：建一个口令为 `p@ss:w/rd%` 的临时登录角色，用它跑 `up` 成功。
没有 `TEST_PG_DSN` 时在测试函数本身里 `t.Skip`（不要在 goroutine 里 Skip，v0.3.2 的教训）。

```bash
cd tools/be-sdk-go && go test ./migrate/ -count=1 -v 2>&1 | tail -n +1 | grep -E '^(--- |FAIL|ok)'
```

期望：编译失败或全部 FAIL（包还不存在）。

- [ ] **Step 2: 实现 `migrate`，跑绿**

`go get github.com/golang-migrate/migrate/v4@latest`（含 `database/pgx/v5`、`source/iofs`）。只在 `migrate` 子包里 import golang-migrate，根包 `besdk` 不引入它（`go list -deps . | grep golang-migrate` 为空）。

```bash
set -a; . /home/zhijie/Desktop/github/be-assembly-standard/.env; set +a
export TEST_PG_DSN="postgres://postgres:${POSTGRES_PASSWORD}@localhost:5432/brickkit_test_db?sslmode=disable"
go test ./migrate/ -count=1 -v | grep -E '^(--- |FAIL|ok)'
go list -deps . | grep -c golang-migrate     # 0
```

- [ ] **Step 3: 删 `Module.Migrations`，处理 06a 遗留的 SDK 小问题**

先逐条核对 `batches/06a.md` §6.1 的 be-sdk-go 条目在 v0.3.1/v0.3.2 里是否已修（`git log v0.3.0..HEAD --oneline`、读代码），已修的在记录里写"已在 vX 修复"；未修的在这里修，每条一个红绿提交：
- `shell.go` 注释里的 `DATABASE_*`；`connection.go` 注释的旧文档路径 `docs/conventions/…` → `docs/en/01-conventions/…`（plan.md 待办）；
- 没有测试断言 authz 中间件读的是 `IAM_JWKS_URL` / `AUTHZ_BUNDLE_URL`：补测试；
- 成员 `httpPort` ≤ 0 未校验：启动即报错（带成员 ID）；
- `BRICKKIT_SERVED_MEMBERS_CONFIG` 的值是 `null` 时被当成零成员：改成报错（brickKit 零成员时给的是 `[]`）；
- `serveResult` / `Main` 没有单测：补。
删 `Migrations` 字段后 `go build ./... && go vet ./... && go test ./... -count=1` 全绿（有 `TEST_PG_DSN`）；README 的 Module 一节、"迁移"一节改写（迁移由 brickKit 用组件自己的镜像跑，入口用 `migrate.Main`）。

- [ ] **Step 4: 提交，交控制者发布**

提交信息写文件、`git commit -F`。发布说明 `$S/notes-be-sdk-go-v0.4.0.md`：先写"必须做的"（删除 `Module.Migrations`；迁移入口改用 `migrate.Main`），再写新增与修复。控制者审查后：`git tag -a v0.4.0 -F <说明> && git push origin main v0.4.0`，父仓库提交指针。

---

### Task 2: be-sdk-python v0.4.4

**Files:**（仓库 `tools/be-sdk-python`）
- Modify: `besdk/connection.py`（注释路径）、`besdk/shell_runner.py`、`tests/`、`README.md`、`pyproject.toml`
- Parent: 子模块指针 `tools/be-sdk-python`

**Interfaces:**
- Produces: be-sdk-python v0.4.4，API 不变；README 新增"外壳失败契约"一节，逐字列出 R15 三类失败对应的日志与退出行为（包括 `ShellMemberServeError` 与"registry 没有登记它的 new_module"两条原文），T21 的判据直接引用。

- [ ] **Step 1: 逐条核对 06a §6.1 的 be-sdk-python 条目**（v0.4.3 已修的写明），未修的每条一个红绿提交：取消路径下模块 `stop` 未覆盖（补测试）；带成员的 clean `stop_event` 关停不抛异常（补测试）；`load_own_ports` 重复解析 YAML（合并为一次）；YAML 顶层不是 dict 时 `AttributeError`（改成明确报错）；`connection.py` 注释路径改成 `docs/en/01-conventions/…`。
- [ ] **Step 2: 测试**

```bash
cd tools/be-sdk-python && uv venv --seed -p 3.12 $S/venv-sdk && $S/venv-sdk/bin/pip install -e '.[dev]' -q
set -a; . /home/zhijie/Desktop/github/be-assembly-standard/.env; set +a
TEST_PG_DSN="postgres://postgres:${POSTGRES_PASSWORD}@localhost:5432/brickkit_test_db" $S/venv-sdk/bin/pytest -q
```

（本机没有全局 pip/pytest，只用 venv 里的；`uv` 不在时先 `command -v uv` 查已装的同类工具，不要另装。）通过：全部 passed，没有意外 skip。

- [ ] **Step 3: 提交，交控制者发布 v0.4.4**（同 T1 Step 4）。

---

### Task 3: 一次性迁移工具包 `dev/phase-06/tools/`

只服务于"1.x → 2.0.0 这一次迁移"，阶段结束随 `dev/` 归档。

**Files:**
- Create: `dev/phase-06/tools/env.sh`、`migrate-manifest.py`、`manifest-overrides.yaml`、`go-v2.sh`、`docs-skel.sh`、`tests/run.sh`、`README.md`

**Interfaces:**
- `bash env.sh <scope>/<name>` → 打印 `export` 行：`ROOT ID REPO UREPO C S SCHEMA ROLE SVC NET`（取值规则同 component-loop §0.1；`S` = `<scratchpad>/06b/$REPO`，scratchpad 从环境变量 `BE_SCRATCH` 取，没有就报错退出要求设置），并 `mkdir -p $S`。
- `python3 migrate-manifest.py <id> [--write] [--check]`
  - 输入：组件**最后一个 1.x tag** 上的 `component.yaml` 与 `assembly.yaml`（`git -C $C describe --tags --abbrev=0 --match '1.*'`，用 `git show <tag>:component.yaml` 读），加上 `manifest-overrides.yaml` 里该组件的条目。读 tag 而不是工作区，所以重复运行结果相同。
  - 不带参数：打印将写出的两份文件与 diff，不写盘。
  - `--write`：按 component-loop §3.1 的布局与 §2.2/§2.3 的推导规则整份重写 `component.yaml`（删版本注释、`deployment.image`、`dependencies.resources`；补 `metadata.repository`、`deployment.build`、`local`；依赖改 `@2.0.0`；键名改大写下划线；secret 标记；required 规则）；`assembly.yaml` 删 `version`、`shell`、`asset`，`data.role` 注释改成"登录角色，`PG_USER` 的值"，其余（含注释）原样保留（文本级编辑，不经 YAML 往返）；并把代码里旧键的读取改成新键：Go `rt.Config.(String|StringOr|MustString|Int|IntOr|Bool|BoolOr)("<旧键>"`、Python `string_or("<旧键>"` 等、TS `config.*("<旧键>"`，逐处打印改了哪个文件哪一行。
  - `--check`：对**当前工作区**跑 component-loop 3.2 的全部检查，外加"代码里还有驼峰键读取"一项；任一项不是"无"就 `exit 1`。
- `manifest-overrides.yaml`：每个组件一段，键是组件 ID，可用字段：`name`、`description`（英文）、`tags`、`add_properties`（键 → schema）、`required_add`、`drop_default`（R27 那类改成 required 的键）、`deps_add`（如 bff 的两个 optional 依赖）、`start_period_seconds`、`local`（`language`、`runCommand` 数组）。初稿由本 Task 按 component-loop §2.2 表写全 13 个组件；Python / TS 的 `local.runCommand` 写成初稿，由 T16 / T20 真机确定后改。
- `bash go-v2.sh <id> --sdk <tag> [--recheck]`
  - 判形态（component-loop 4.0）；形态 B 拆嵌套模块（4.1，含 Dockerfile 改成先 `COPY . .` 再 `go mod download`）；`go mod edit -module …/v2` 与 import 改写（4.2）；根 `go.mod` require 契约包的真实版本（4.3：本地 `gen/` 与最新 `gen/*` tag 一致 → require 那个 tag；不一致 → 下一个 minor；形态 B 没有 tag → `v1.0.0`）；升 SDK、`go mod tidy`、`go build ./...`、`go vet ./...`；最后跑 4.4 的全部判据，打印每条 `PASS/FAIL`，有 FAIL 就 `exit 1`。
  - 幂等：已是 `/v2`、已拆过的跳过对应步骤。
  - `--recheck`：契约改动并 `buf generate` 之后再跑，只重算第 4.3 步与 4.4 判据；打印"第 8.3 步需要打的契约包 tag"（或"不需要"）。
- `bash docs-skel.sh <id>`：`brickkit new $ID --path $S/skel`；把旧的 `AGENTS.md`、`README.md`、`docs/手册.md`、`component.yaml`、`assembly.yaml`、`Makefile`、`Dockerfile` 留底到 `$S/old/`；写出 `BRICKKIT.md`、`AGENTS.md`、`README.md`（取骨架）及其 `.zh.md`（固定中文标题、首行互链，正文写成"待填"——注意骨架里的 TODO 会被 lint 报 `DOC_PLACEHOLDER`，这是 C5 要填的），`docs/design.md` + `.zh.md`（小节按 component-loop 5.1 的 design 一行列出）；目标文件已存在且不是骨架时不覆盖（`--force` 才覆盖），`CLAUDE.md` 写成恰好 `@AGENTS.md`。
- `bash tests/run.sh`：在 scratch 里 `git clone --local` 两个真实组件仓库（`mdm-customer` 形态 A、`infra-notification` 形态 B；clone 带 tag，不碰 `components/` 下的子模块），分别跑上面四个脚本，断言：manifest `--check` 通过、`go-v2.sh` 退出 0、形态 B 拆出 `gen/infra/notification/go.mod`、`go list -m all` 只有两行本仓库模块、重复运行无改动（`git status --short` 第二次为空）。

- [ ] **Step 1: 先写 `tests/run.sh`，跑红**（脚本不存在）。
- [ ] **Step 2: 逐个实现，直到 `bash dev/phase-06/tools/tests/run.sh` 全绿**。`--sdk` 用 `v0.3.2` 跑测试（T1 的 v0.4.0 可能还没发布；SDK 版本只是参数）。
- [ ] **Step 3: `README.md`** 写每个脚本的用法、输入、判据、已知限制（例如 `--write` 会丢掉 `component.yaml` 里的全部注释——本来就要删）。
- [ ] **Step 4: 提交**（父仓库，按路径）：`git commit -F $S/msg.txt -- dev/phase-06/tools/`。由控制者审查后推送。

---

### Task 4: 长期脚本——集成、真机验证、发布、teardown 同步

以后每次改组件都用得上，所以放 `infra/scripts/` 并写进正式文档。

**Files:**
- Create: `infra/scripts/config-fill.py`、`teardown-sync.py`、`integrate.sh`、`verify-component.sh`、`ship.sh`；`infra/scripts/tests/test_config_fill.py`、`test_teardown_sync.py`、`test_ship_dryrun.sh`
- Modify: `Makefile`（目标 `integrate`、`verify`、`ship`、`teardown-sync`、`permissions`）、`.gitignore`（`deploy.verify.yaml`）、`docs/en/01-conventions/01-development-workflow.md` 与 `docs/zh/…` 同名文件（"Running it for real"、"Releasing"）、`.claude/skills/version-bump-ship/SKILL.md`（§3 第 6–8 步）

**Interfaces:**
- Consumes: `infra/scripts/project-lock.sh`（T5 Step 0 产出并最先提交；本 Task 的脚本都通过它拿锁，跑测试之前它必须已在）。
- `python3 infra/scripts/config-fill.py <id> [--set KEY=VALUE …]`：读组件 `configSchema`（本地源或 `.brickkit/manifests` 缓存）与 `config/<repo>.yaml`（`brickkit add` 写的骨架），按 Global Constraints 的"配置值"规则逐键填写：共享键 → `$var:KEY`（`config/vars.yaml` 里有这个键才写）；`PG_USER`/`PG_SCHEMA` → `schemas.tsv` 字面量；`PG_PASSWORD` → `${<UREPO>_DB_PASSWORD}`；外壳（`be/<name>`）→ `shell_<name>` / `${SHELL_<NAME>_PASSWORD}`，无 `PG_SCHEMA`；`--set` 给的值原样写；已经有非空值的键不动。required 键填不出值时列出键名并 `exit 3`。文本级编辑，保留 `brickkit add` 写的注释行。
- `python3 infra/scripts/teardown-sync.py [--check]`：让 `deploy.teardown.yaml` 的 `components` 与 `deploy.yaml` 完全一致（`target` 相同，没有 `vars:`），保留文件头注释；`--check` 不一致时 `exit 1` 并打印差异。
- `make integrate ID=<id> [VERSION=2.0.0]` → `integrate.sh`，持锁执行：连库组件先 `make dev-env db-init`；不在 `brickkit.yaml` 里 → `brickkit add <id>@<VERSION> --yes`，已在 → `brickkit upgrade <id>@<VERSION> --dry-run` 打印发布说明与改动，再 `brickkit upgrade <id>@<VERSION> --yes`（版本相同则跳过；`--yes` 会把配置冲突写成重复键，随后的 `brickkit lint` 会报出来，出现就停下按 brickkit-assemble skill 处理）；`config-fill.py <id>`；`teardown-sync.py`；`brickkit lint --strict <id>`；`brickkit up --dry-run`；最后打印 `git status --short -- brickkit.yaml deploy*.yaml config/ AGENTS.md registry/`。任一步失败 `exit 1`。外壳 ID 同样适用（`brickkit add be/<name>@1.0.0` 会把已在项目里的成员移进外壳）。
- `make verify ID=<id> [ROUTE=<路径>] [FOCUS=1] [KEEP=1]` → `verify-component.sh`，持锁执行，输出目录 `${OUT:-$BE_SCRATCH/verify/<repo>-<时间>}`：
  1. `brickkit build <id>`；闭包里其它组件缺镜像的也 build。镜像检查：`sh + wget`、`/app/component.yaml` 存在（component-loop 7.7）。
  2. 生成 `deploy.verify.yaml`：复制 `deploy.yaml`，把与"本组件 + 它的依赖闭包 + 已加入项目的 infra/authz、infra/iam-casdoor"无交集的顶层条目全部写成 `mode: disable`；含闭包成员的外壳条目保留。
  3. `brickkit up -f deploy.verify.yaml`；`brickkit status -f deploy.verify.yaml`；每个迁移容器 `Exited (0)` 并保存日志；本组件 `running (healthy)`。
  4. 用 `curlimages/curl` 在 brickKit 网络里打 `http://<svc>:<port>/healthz`（期望 200）和 `ROUTE`（可写成 `"<METHOD> <路径>"`，省略方法时是 `GET`；不带 token：记录实际码，`401`/`503` 记 PASS，`403` 记 FAIL——说明 `IAM_JWKS_URL` 没注入；带 token：authz 与 iam 都在闭包里且 iam 种子已在时用 `infra/scripts/lib/seed-net.sh` 的 `get_app_jwt dev.superuser`，期望 200；否则 SKIP 并写原因）。外壳 ID：改跑 component-loop §4.5 的运行期核对（成员清单、成员 JSON、R15 三条日志检查、`RestartCount`、每个成员按自己的服务名 `/healthz`）。
  5. Go 组件：`make test-cross ID=<id>`。
  6. `FOCUS=1`：`brickkit up --focus <id>` 后台运行，轮询宿主机 `http://localhost:<port>/healthz` 到 200（最多 120 秒），停掉进程，`brickkit up --all --dry-run`，`brickkit local status`，`brickkit local off`。
  7. 除非 `KEEP=1`：`brickkit down -f deploy.verify.yaml`，确认 `docker ps` 里没有本项目的组件容器。
  打印汇总表（每行：检查项、`PASS`/`FAIL`/`SKIP`、原因、日志文件），任何 `FAIL` → `exit 1`。
- `make ship DIR=<components/<id> 或 shell/be/<name>> NOTES=<说明文件>` → `ship.sh`，**只有控制者运行**，按顺序、第一处失败即停（已推送的东西绝不回滚或删除，只报告停在哪）：
  1. 目录干净、在 `main`、`git push origin main`。
  2. Go 组件（非外壳）：从根 `go.mod` 找出 require 的本仓库契约包 `…/gen/<d>/<n> vX`；远端已有 `gen/<d>/<n>/vX` → 校验 `git diff --quiet gen/<d>/<n>/vX HEAD -- gen/<d>/<n>`（06a N-3：已发布的契约包必须与 HEAD 逐字节一致，否则 FAIL）；远端没有 → 在 HEAD 打带注释的 tag（说明同 NOTES）并推送。
  3. `brickkit release --notes-file $NOTES`；核对 `git cat-file -t <ver>` 是 `tag`、`git ls-remote --tags origin <ver>` 有一行。
  4. Go 组件（非外壳）：`git tag -a v<ver> -F $NOTES && git push origin v<ver>`；两个 tag 指向同一提交。
  5. Go 组件（非外壳）：外壳视角拉取探针（component-loop 8.5），`go list -m all | grep brickKit/<repo>` 只有 `…/v2 v<ver>` 与契约包两行；探针失败最多重试 3 次、间隔 30 秒（代理刚收到新 tag 时可能滞后），仍失败则 FAIL。
  6. 打印父仓库要暂存的路径与 `git submodule status <路径>` 的期望形态。
  每一步打印 `▸ 第 n 步 … PASS/FAIL`。Python / TS 组件跳过 2、4、5；外壳跳过 2、4、5。
- `make permissions`：持锁执行 be-ops `permissions` + `data-scopes` + `make registry-check`，然后 `git diff registry/permissions.tsv | grep '^-[^-]'` 为空才算通过（只增不删）。

- [ ] **Step 1: 先写测试并跑红**：`test_config_fill.py`（夹具：一份 schema + 一份 `brickkit add` 风格骨架 + 迷你 `schemas.tsv`/`vars.yaml`；覆盖共享键、PG_USER、外壳、`--set`、已有值不动、缺值 `exit 3`）、`test_teardown_sync.py`（含外壳 `members` 嵌套的 deploy.yaml）、`test_ship_dryrun.sh`（在 scratch 的 bare 仓库 + clone 上跑 `ship.sh --dry-run`：不推送真实远端，验证步骤顺序与 N-3 校验能抓到"已发布契约包与 HEAD 不一致"）。这些测试用 `python3 <文件>` / `bash <文件>` 直接运行（本机没有 pytest），全部断言用 `assert`，失败非零退出。
- [ ] **Step 2: 实现脚本与 Makefile 目标，跑绿**。`ship.sh` 带 `--dry-run`（只打印将执行的命令，供测试与控制者预览）。
- [ ] **Step 3: 正式文档**：`01-development-workflow.md`（en + zh 同步）的"Running it for real"加一条：`make integrate ID=` / `make verify ID=` 是 add→填配置→同步拆回部署文件→lint→生成检查、build→只起闭包→健康与鉴权检查→跨组件测试→收尾 的一条命令版本，并说明项目锁；"Releasing"第 2–4 步注明 `make ship DIR= NOTES=` 一条命令完成（含契约包 tag 与外壳视角拉取检查）。`version-bump-ship` skill §3 第 6–8 步改成调用 `make ship`，保留"什么时候停下"那一节不变。
- [ ] **Step 4: 自检**：`make docs-mirror docs-boundary`；`brickkit lint --strict 2>&1 | grep -E 'docs/|AGENTS|README' ` 没有本 Task 引入的新警告；`make help | grep -E 'integrate|verify|ship|teardown-sync|permissions'` 五个目标都在。
- [ ] **Step 5: 提交**（父仓库，按路径；T5 同时在改 `infra/scripts/` 下的别的文件，所以逐个列出，不写目录）：`infra/scripts/config-fill.py infra/scripts/teardown-sync.py infra/scripts/integrate.sh infra/scripts/verify-component.sh infra/scripts/ship.sh infra/scripts/tests/test_config_fill.py infra/scripts/tests/test_teardown_sync.py infra/scripts/tests/test_ship_dryrun.sh Makefile .gitignore docs/en/01-conventions/01-development-workflow.md docs/zh/01-conventions/01-development-workflow.md .claude/skills/version-bump-ship/SKILL.md`。

---

### Task 5: 项目锁、数据库重置与旧脚本修正

**Files:**
- Create: `infra/scripts/project-lock.sh`、`infra/scripts/tests/test_project_lock.sh`
- Modify: `infra/scripts/test-db-init.sh`、`infra/scripts/dev-env.sh`、`infra/scripts/lib/seed-net.sh`（`service_host`）、`infra/scripts/db-init.sh`
- Create: `dev/test-records/06b/T5-db-reset.md`

**Interfaces:**
- Produces: `bash infra/scripts/project-lock.sh -- <命令…>`：`flock -w 3600 "${BE_PROJECT_LOCK:-/tmp/be-assembly-standard.project.lock}" <命令…>`；拿到锁时打印 `🔒 project lock acquired by <pid> (<命令>)`，等锁时每分钟打印一次谁占着（锁文件里写持有者的命令行）。执行命令时导出 `BE_PROJECT_LOCK_HELD=1`；子进程再调用本脚本（或自带锁的 make 目标）时看到它就直接执行，不再等锁——所以持锁 shell 里可以照常跑 `make dev-env`、`make verify` 等。
- Produces: 演示库 `brickkit_db` 里 14 个组件的 schema（及 `<schema>_archive`）都是空的、由 `make db-init` 新建，组件迁移以 `<schema>_rw` 身份建表（表属主即该角色）；`make test-db-init` 给迁移传 `PG_*`；`make dev-env` 把空的 `VAR=` 当缺失。06a §7.5 的"所有权重置"前置在这里完成。

- [ ] **Step 0: 项目锁脚本（最先做，做完立即单独提交，T4 要用）**：先写 `test_project_lock.sh`（两个后台进程同时拿锁，断言串行执行；持锁进程里嵌套调用不死锁；`-w` 超时时非零退出并打印持有者）跑红，再实现 `project-lock.sh` 跑绿；（`S5=<本会话 scratchpad>/06b/T5`）`git commit -F $S5/msg-lock.txt -- infra/scripts/project-lock.sh infra/scripts/tests/test_project_lock.sh`，通知控制者推送。
- [ ] **Step 1: 核对 be-ops `db-script` 的口令接线**（06a §6.1："`DBPasswordEnv` 没被 `main.go` 调用"）：`bash infra/scripts/db-init.sh --print 2>/dev/null || true` 或读 `db-init.sh` 看口令来源，确认每个 `<schema>_rw` 的口令取自 `.env` 的 `<REPO>_DB_PASSWORD`、外壳角色取自 `SHELL_<NAME>_PASSWORD`。不对就修 `db-init.sh`（不改 be-ops；需要改 be-ops 时记进 T26）。无论是否发现问题，`db-init.sh` 都用 `project-lock.sh` 包住整个执行。
- [ ] **Step 2: 修 `dev-env.sh`**：空值 `VAR=` 视为缺失（与 `db-init.sh` 一致，06a 遗留）；`.env` 不存在时给一句人话报错而不是 shell 报错；补一个测试 `infra/scripts/tests/test_dev_env.sh`（临时目录里的 `.env` 含空值行，运行后该行被填上、已有值不变、只打印变量名）；`dev-env.sh` 同样用 `project-lock.sh` 包住（它写 `.env`）。
- [ ] **Step 3: 修 `test-db-init.sh`**：给每个组件的 `migrate-idempotent` 同时传 `PG_HOST/PG_PORT/PG_DATABASE/PG_USER/PG_PASSWORD/PG_SCHEMA`（以 `<schema>_rw` 登录）和旧的 `DATABASE_*`（还没重建的组件读它；T26 删掉）；用 `infra/scripts/project-lock.sh` 包住整个脚本。
- [ ] **Step 4: 修 `seed-net.sh` 的 `service_host`**：解析失败时报错退出，不再静默吞掉（06a 遗留）；`bash infra/scripts/tests/test_seed_net.sh` 仍绿。
- [ ] **Step 5: 重置演示库**（数据都是假的，由各组件 `make seed` 重建；Casdoor 自己的库不动）：

```bash
cd /home/zhijie/Desktop/github/be-assembly-standard
bash infra/scripts/project-lock.sh -- bash -c '
  brickkit down 2>/dev/null || true
  for s in $(awk -F"\t" "!/^#/ && NF>=3 && \$1 !~ /^_/ {print \$2}" registry/schemas.tsv); do
    docker exec be-postgres psql -U postgres -d brickkit_db -v ON_ERROR_STOP=1 -qc "DROP SCHEMA IF EXISTS ${s}_archive CASCADE; DROP SCHEMA IF EXISTS ${s} CASCADE;"
  done
  make dev-env && make db-init'
docker exec be-postgres psql -U postgres -d brickkit_db -tAc "select nspname, pg_get_userbyid(nspowner) from pg_namespace where nspname like 'mdm_%' or nspname like 'erp_%' order by 1"
```

先把 `awk` 的输出单独打印一遍贴进记录，确认列出的只是 14 个组件（及登记表里预留的其它组件）的 schema、没有 `public` 或 Casdoor 的库，再执行删除。通过：`make db-init` 打印 `✓ 建库脚本已执行`；schema 全部重建、里面没有表。

- [ ] **Step 6: 测试库**：`make test-db-init`。通过：`✓ brickkit_test_db 就绪`（旧组件的迁移仍按 `DATABASE_*` 跑通）。
- [ ] **Step 7: 提交**（按路径，逐个列文件）：`infra/scripts/test-db-init.sh infra/scripts/dev-env.sh infra/scripts/db-init.sh infra/scripts/lib/seed-net.sh infra/scripts/tests/test_dev_env.sh dev/test-records/06b/T5-db-reset.md`。

---

### Task 6: 更新 `component-loop.md`

**Files:**
- Modify: `dev/phase-06/component-loop.md`

**Interfaces:**
- Consumes: 本计划写定的工具接口（T3、T4、T1 的 `migrate.Main`），不等它们实现完。
- Produces: 与 brickKit v1.1.0、自主模式、工具链一致的单组件清单；C1–C9 引用的每个小节都成立。

- [ ] **Step 1: 逐条修改**（每条改完在记录里写"§x 改了什么"）：
  1. 头部"用途"与 §0：去掉"批次 B1–B6、每批停下汇报"，改为"按 `plan-06b.md` 的 Task 执行；过程记录写 `dev/test-records/06b/<repo>.md`"；§0 第 4 条、第 5 条按自主模式改写。
  2. §0.1 变量：改成 `eval "$(bash $ROOT/dev/phase-06/tools/env.sh $ID)"`，保留变量含义表。
  3. §1 批次总览：整表替换成一句"波次与前置见 `plan-06b.md`"，保留 §1.1 登记事实表与 §1.2 前端接口表（§1.2 的 bff 行补上 P11 的两个 optional 依赖、inventory 行写明 P12 路径）。
  4. §1.4：`brickkit --version` → `BrickKit CLI v1.1.0`；SDK → be-sdk-go v0.4.0、be-sdk-python v0.4.4、be-sdk-ts v0.4.0。
  5. §2.2：bff-mobile 依赖补 `infra/notification`、`crm/opportunity`（optional，P11）；§2.3 第 5 条写成 P7 的最终规则（含"基础资源密钥沿用原变量名"）；§2.4 加一句"由 `infra/scripts/config-fill.py` 按此规则填写"。
  6. §3.3、§6.2、§7.6：`bash infra/scripts/component-lint.sh $C --` 一律改成 `brickkit lint $ID`（不严格）/ `make docs-check ID=$ID`（严格），删掉"项目内直接 `brickkit lint` 会 lint 整个项目"的说法（v1.1.0 在组件目录或带 `<id>` 时只查这一个组件，`--all` 查全项目）。
  7. §4.6 迁移入口：改为"`backend/cmd/migrate/main.go` 只剩 `func main() { migrate.Main(migrations.FS) }`（be-sdk-go v0.4.0），删除 lib/pq 与 `sslmode` 的讨论"；`component.yaml` 的 `migration.command` 不变（`["./migrate", "up"]`）；`module.go` 删 `Migrations:` 一行。
  8. §4.17：引用的步号 7.6 改成 7.9（06a N-6）；§4.3 加一句 P3 的"形态 B 第一个 tag 一律 v1.0.0"（06a N-5）。
  9. §5.0：删除"提醒用户切换到 Opus"。§5.1：`AGENTS.zh.md` 那一行删掉"外加一节翻译的 `## BrickKit`"，补上 AGENTS 与 README 的固定中文标题；§5.2 的小节计数说明改成"维护块不计入，两边直接相等"。
  10. §7.6（V-07）与 §7.8–7.11：说明 `make verify` 覆盖了 7.7–7.11，手工命令保留作排障参考。
  11. §8.2–8.5：实现者只提交不推送；推送、`gen/*` tag、`brickkit release`、`v` tag、外壳视角拉取由控制者 `make ship` 完成；§8.7 父仓库由控制者按路径提交并推送（R31）。
  12. §4（外壳）：§4.1 前置加"外壳 `go.mod` / `pyproject.toml` 的 SDK 升到成员所用版本"；§4.3 加"`BRICKKIT.md`/`.zh.md` 不得引用本项目的 `registry/ports.tsv`、`make db-init`（外壳会被别的装配项目复用），改成通用说法：'装配项目为外壳建一个登录角色，并把每个成员的 `<schema>_rw` 授给它'"；§4.2 Python 一段改为 `from infra_print.module import create_module`；§4.5 的 R15 判据引用 be-sdk-python README 的"外壳失败契约"原文（T2）；§4.4 起的项目侧命令改用 `make integrate ID=be/<name>`、`make verify ID=be/<name>`。
  13. §7 停止条件：整节改写为"控制者裁定并记录；只有 brickKit 严重 bug 才停（定义见 plan-06b 执行方式）；新建/删除仓库、强推、动已推送 tag 仍然不做"。
  14. 附录 B：v1.0.1 实测事实里被 v1.1.0 改掉的（单组件 lint、项目文档也被 lint、`AGENTS.zh.md` 计数）标注"v1.1.0 起"并改写；`make tier1` 仍是占位。
- [ ] **Step 2: 自检**：`grep -nE 'component-lint|v1\.0\.1|## BrickKit|切换到 Opus|停下汇报' dev/phase-06/component-loop.md` 只剩附录 B 里明确标注为历史对照的行；`make docs-boundary`（本文件在 `dev/`，不受约束，但不得被正式文档链接）。
- [ ] **Step 3: 提交**（按路径）：`git commit -F $S/msg.txt -- dev/phase-06/component-loop.md`。

---

## 试点

### Task 7: 试点 mdm/customer

**前置**：T1–T6 全部完成，be-sdk-go v0.4.0 与 be-sdk-python v0.4.4 已发布，T3/T4 的测试全绿。

**Files:**（组件仓库 `components/mdm/customer`）
- Modify: `component.yaml`、`assembly.yaml`、`go.mod`、`go.sum`、`Makefile`、`Dockerfile`（只在需要时）、`backend/**`、`contracts/customer.openapi.yaml`、`migrations/`（新增索引迁移）、`scripts/seed.sh`
- Create: `BRICKKIT.md`、`BRICKKIT.zh.md`、`AGENTS.zh.md`、`README.zh.md`、`docs/design.md`、`docs/design.zh.md`、`.claude/skills/brickkit-component/SKILL.md`
- Delete: `docs/手册.md`
- Parent（脚本写出，控制者提交）：`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/mdm-customer.yaml`、`AGENTS.md`（组件表）、`components/mdm/customer`（指针）
- Record: `dev/test-records/06b/mdm-customer.md`

**Interfaces:**
- Produces: `mdm/customer@2.0.0`（tag `2.0.0` + `v2.0.0`）；模块路径 `github.com/brickKit/mdm-customer/v2`；契约包仍是 `gen/mdm/customer v1.0.6`（本次只改 REST，`.proto` 不变 → 不打新契约包 tag；`go-v2.sh --recheck` 会确认）。
- `GET /mdm/customer/customers` 新增 query `q`。
- 一份可以照抄的样板：文件结构、文档写法、记录格式。

**事实**：Go；HTTP 8080 / gRPC 9090；`mdm_customer` / `mdm_customer_rw`；形态 A；无依赖；`data_scopes: none`。

**要补的接口**（frontend-needs §2.1）：`q` 匹配 `code`、`name`，大小写不敏感，前缀匹配排在包含匹配之前，仍游标分页、权限 `mdm.customer.view`。L2 测试：前缀优先的排序、大小写、空 `q` 等于不过滤、`q` 与游标一起用时翻页不重不漏。需要索引就新增一条迁移（例如 `lower(code) text_pattern_ops`），不改旧迁移。

**重构重点**：`backend/internal/repo/repo.go`（563 行）按读 / 写拆开是否更清楚（09-ai-development.md 判断）；全仓注释里引用归档文档的说法（"设计书 §x""总纲""§13.3 铁律""决策 110""docs/手册.md""阶段 X Task Y"）改成现行约定的说法或直接写原因，不写历史；`module.go` 删 `Migrations:` 一行，`role := schema + "_rw"` 保留（外壳里 `SET LOCAL ROLE` 仍要用）。

**V 项**（本 Task 独有）：V-01、V-07、V-09，V-06 的组件发布半程（控制者在 ship 时记录）。

- [ ] **Step 1: C1–C6**（通用流程）。C3 无新权限键。
- [ ] **Step 2: V-01**：在 `component.yaml` 的 `configSchema.properties` 临时加 `fooBar: {type: string, default: x}`，跑 `brickkit lint --strict mdm/customer` 与（Step 3 的 integrate 之后）`brickkit up --dry-run`，原文记录有无警告；删掉该键，`git -C $C diff component.yaml` 为空。
- [ ] **Step 3: C7**：`make integrate ID=mdm/customer`；`make verify ID=mdm/customer ROUTE=/mdm/customer/customers FOCUS=1`。authz/iam 还没加入，受保护路由只验 `401`/`503`（汇总表里带 token 一项是 SKIP，写明"待 T25"）。
- [ ] **Step 4: V-07**（integrate 之后 `.brickkit/manifests` 缓存已存在）：把 `$C/component.yaml` 版本临时改成 `2.0.1`（不提交），跑 `brickkit lint mdm/customer`、`brickkit lint --strict`（全项目）、`bash infra/scripts/project-lock.sh -- brickkit up --dry-run`，原文记录三者是否发现"`brickkit.yaml` 钉 2.0.0、本地源是 2.0.1"；`git -C $C checkout component.yaml` 复原后再跑一次 `up --dry-run` 确认恢复。
- [ ] **Step 5: V-09**（在锁内做）：`brickkit up --focus mdm/customer --dry-run` 之后，在 `deploy.yaml` 末尾临时加一行注释以外的无害改动（例如给 mdm/customer 条目加 `labels: {probe: "v09"}`），跑 `brickkit up --dry-run` 看是否提示 `deploy.local.yaml` 在生效、改动不生效；`brickkit local status` 原文；还原 `deploy.yaml`，`brickkit local off`。
- [ ] **Step 6: `make seed`**：`bash infra/scripts/project-lock.sh -- bash -c 'brickkit up -f deploy.verify.yaml && make -C components/mdm/customer seed; brickkit down -f deploy.verify.yaml'`（`deploy.verify.yaml` 是 `make verify` 留下的），种子数据含 `q` 搜得到的样例（例如名称有共同前缀的几个客户）。种子脚本里写死的 `1-0-` 服务名、`DATABASE_*` 全部消失（component-loop 4.9）。
- [ ] **Step 7: C8–C9**。记录里另写一节"给后续组件的模板说明"：哪些步骤脚本做了、哪些要人工、每一步实际耗时、脚本的摩擦点（交给 T8）。

---

### Task 8: 试点审查与模板回灌

**前置**：T7 已发布（控制者 `make ship` 通过，V-06 组件半程有结论）。

**Files:**
- Modify: `dev/phase-06/component-loop.md`、`dev/phase-06/tools/*`、`infra/scripts/*`（只修 T7 暴露的问题）、`dev/phase-06/tools/manifest-overrides.yaml`
- Possibly modify: `components/mdm/customer`（只在预设裁定被推翻、或审查发现它本身有问题时；它已发布，所以发 2.0.1，见 Step 4）
- Create: `dev/test-records/06b/T8-pilot-review.md`

**Interfaces:**
- Produces: 裁定 R38 起（P1–P12 的最终结论 + T7 暴露的新问题），写进控制者台账与 `T8-pilot-review.md`；更新后的清单与脚本，供 W1 起的 13 个 Task 使用。

- [ ] **Step 1: 审查**（审查者，opus）：按 Review Focus 五条 + component-loop §3 逐项审 mdm/customer 的组件仓库提交、父仓库工作区改动、过程记录、`verify` 输出目录。另外专门回答：(a) 文档五件套作为样板是否值得照抄（结构、粒度、有没有写历史）；(b) 每个脚本有没有"静默成功"的路径（例如 `config-fill.py` 漏填却退出 0）；(c) 试点里人工做了、但 13 个组件都要重复的步骤，哪些还应该进脚本。
- [ ] **Step 2: 控制者裁定**：P1–P12 逐条写"维持预设 / 改为…"，以及审查发现的每个 Important 以上问题的处理。记为 R38、R39…（台账 + `T8-pilot-review.md`）。
- [ ] **Step 3: 回灌**：把裁定和审查结论改进 `component-loop.md`、`dev/phase-06/tools/`、`infra/scripts/`（脚本改动要让 `dev/phase-06/tools/tests/run.sh` 与 `infra/scripts/tests/*` 仍然全绿）。
- [ ] **Step 4: mdm/customer 补齐**（只在有裁定推翻预设、或审查发现 mdm/customer 本身的问题时）：按 version-bump-ship 发 `2.0.1`（`make bump-version PLAN=…` 先 dry-run 再 `APPLY=1`；`make ship`；`make integrate ID=mdm/customer VERSION=2.0.1`；`make verify …`）。没有就跳过并写明。
- [ ] **Step 5: 父仓库提交（控制者）**：试点单独一个提交，路径：`components/mdm/customer brickkit.yaml deploy.yaml deploy.teardown.yaml config/mdm-customer.yaml AGENTS.md dev/phase-06/component-loop.md dev/phase-06/tools/ infra/scripts/ dev/test-records/06b/`；`git show --stat HEAD`；`git submodule status components/mdm/customer` 括号里是 `2.0.0`/`v2.0.0`（或 2.0.1）；推送。之后才派发 W1。

---

## W1：没有强依赖的 8 个组件（T8 之后同时开工）

每个 Task 都按"组件 Task 通用流程" C1–C9 走，下面只写本组件特有的内容。**Files** 一栏统一为：组件仓库 `components/<id>/` 内的改动（与 T7 同类文件）+ 脚本写出的父仓库路径（`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/<repo>.yaml`、`AGENTS.md`，有新权限键时还有 `registry/permissions.tsv`、`registry/data-scopes.tsv`）+ 过程记录 `dev/test-records/06b/<repo>.md`；只列额外的。

### Task 9: mdm/product

**事实**：Go；8082 / 9092；`mdm_product` / `mdm_product_rw`；形态 A（契约包 `gen/mdm/product`，最新 tag `v1.0.7`）；无依赖；`data_scopes: none`。ROUTE=`/mdm/product/products`。

**Interfaces:**
- Produces: `mdm/product@2.0.0`；**契约包 `gen/mdm/product/v1.1.0`**（gRPC `List` 新增 `q`，T20 的 BFF 用）；`GET /mdm/product/products?q=`；`POST /mdm/product/products/{id}/status` 改绑新键。

**要补的接口**（frontend-needs §2.2）：REST `GET /products` 加 `q`（匹配 `sku`、`name`，规则与 T7 的客户 `q` 相同，复用同样的 L2 测试思路，不复用代码）；`.proto` 的 `ListRequest` 追加字段 `string q = 6;`（1–5 已占用，只增），gRPC 实现同样过滤；`POST /products/{id}/status` 的权限键从 `mdm.product.edit` 改成新键 `mdm.product.set_status`。

**新权限键**：`{ key: mdm.product.set_status, title: 启用/停用产品, type: action }` → `make permissions`。

**重构重点**：`backend/internal/repo/repo.go`（598 行）同 T7 的判断；注释里的归档引用清理（同 T7）。

- [ ] **Step 1: C1–C9**。C4 改完 `.proto` 后 `buf generate`，`go-v2.sh $ID --recheck` 应打印"需要契约包 tag `gen/mdm/product/v1.1.0`"；交接时告诉控制者。L2 测试另加一条：持有 `mdm.product.edit` 但没有 `mdm.product.set_status` 的用户调 status 接口得到 403。

---

### Task 10: erp/inventory

**事实**：Go；8086 / 9096；`erp_inventory` / `erp_inventory_rw`；形态 A（`gen/erp/inventory`，最新 `v1.0.14`）；无依赖；数据范围 `warehouse`（`mode: in`），仓库在迁移 `003_seed_warehouses` 里预置。ROUTE=`/erp/inventory/warehouses`。

**Interfaces:**
- Produces: `erp/inventory@2.0.0`；`GET /erp/inventory/warehouses`、`GET /erp/inventory/balances/list`、`GET /erp/inventory/stats/summary`（REST，权限 `erp.inventory.view`）；配置键 `LOW_STOCK_THRESHOLD`（`{type: string, default: "10"}`，经 `rt.Config` 读）。只改 OpenAPI，`.proto` 不变则不打新契约包 tag。

**要补的接口**（frontend-needs §2.3，响应体照抄那里的字段）：三个端点都受 `warehouse` 维度过滤。`balances/list` 游标分页、可选 `product_id` / `warehouse_id`；`stats/summary` 的 `low_stock` 用 `available_qty < LOW_STOCK_THRESHOLD`（十进制比较，不用浮点）。L2 测试：两个用户各自只能看到自己有权限的仓库的仓库行、余额行、统计数；`LOW_STOCK_THRESHOLD` 配成非默认值时低库存清单随之变化（Review Focus 2）。

**新权限键**：无。**配置值**：`LOW_STOCK_THRESHOLD` 保持注释（跟随组件默认）。

**重构重点**：`backend/internal/repo/repo.go`（581 行）；consumer 订阅 `mdm.product.created/updated.v1` 的幂等与 `version` 严格递增（02-backend.md 的事件规则）对照一遍。

- [ ] **Step 1: C1–C9**。种子数据（`make seed`）要覆盖：多仓库、低于阈值的产品、在途预留——让 `stats/summary` 和 `balances/list` 有东西可看。

---

### Task 11: erp/finance

**事实**：Go；8087 / 9097；`erp_finance` / `erp_finance_rw`；形态 A（`gen/erp/finance`，最新 `v1.0.10`）；无依赖；数据范围 `legal_entity`（`mode: in`）；消费 `erp.inventory.adjusted.v1`、`mdm.customer.created/updated.v1`。ROUTE=`/erp/finance/entries`。

**Interfaces:**
- Produces: `erp/finance@2.0.0`；`GET /erp/finance/ar-ledger/summary`；`ARLedgerEntry` 新增 `customer_name`、`outstanding`；`GET /erp/finance/entries` 新增 query `source_doc_id`、`source_doc_type`。若 gRPC 的 `ARLedgerEntry` 消息也要带新字段（只增），契约包升 `v1.1.0`；只改 REST 则不升。

**要补的接口**（frontend-needs §2.5）：`customer_name` 是快照——先确认组件里已有的客户缓存（消费 `mdm.customer.*` 事件写的那张表）能不能直接提供，能就在读时取，不能就加列 + 在写应收时写入，二选一写进 `docs/design.md`；`outstanding = amount - reconciled_amount` 服务端用十进制算；`ar-ledger/summary` 的账龄分桶按到期日。L2 测试：`legal_entity` 隔离；金额全是字符串且精度不丢（例如 `0.10 + 0.20 = 0.30`）；账龄边界日（第 30 / 31 天）。

**新权限键**：无。

**重构重点**：凭证过账（`erp.finance.post`）与期间状态机的路由是否都带权限键注册（frontend-needs 遗留："少数行缺权限键"）；跨组件写入的 `idempotency_key` 是不是"先 `INSERT … ON CONFLICT DO NOTHING` 认领再写"。

- [ ] **Step 1: C1–C9**。

---

### Task 12: infra/authz

**事实**：Go；8223 / 9223；`infra_authz` / `infra_authz_rw`；形态 A（`gen/infra/authz`，最新 `v1.0.5`，iam-casdoor 在用）；无依赖；`data_scopes: none`（自身管理范围数据）。ROUTE=`/api/admin/roles`。

**Interfaces:**
- Produces: `infra/authz@2.0.0`；`PERMISSION_CATALOG` 的含义改为"`registry/permissions.tsv` 格式的文本"（R27）；`.proto` 不变则契约包仍是 `v1.0.5`。
- 配置值：`PERMISSION_CATALOG: file://registry/permissions.tsv`、`BOOTSTRAP_ADMIN_SUB: ${INFRA_AUTHZ_BOOTSTRAP_ADMIN_SUB:-}`、`ACCESS_TOKEN_TTL_SECONDS` / `DEFAULT_ORG_ID` 保持注释。按 C7 的写法：`config-fill.py infra/authz --set 'PERMISSION_CATALOG=file://registry/permissions.tsv' --set 'BOOTSTRAP_ADMIN_SUB=${INFRA_AUTHZ_BOOTSTRAP_ADMIN_SUB:-}'`。

**要做的**（component-loop §2.5，R27）：`backend/internal/service/catalog.go` 的 `ParsePermissionCatalog` 改成解析 TSV：按行切，跳过空行、`#` 开头的行和表头（第一列是 `key`），按制表符切，至少 4 列（`key`、`title`、`type`、`owner_component`），第 5 列 `deprecated` 可空，`key` 为空报错并给出行号；`deprecated` 非空的行照样同步。先写 L2 测试（真实 `registry/permissions.tsv` 的片段：中文标题、表头、`deprecated` 行、末尾无换行）跑红，再改实现。旧逗号格式不再支持，发布说明第一条写"键的含义变了"。`PERMISSION_CATALOG` 在 `configSchema` 里 required、无默认值。

**运行期判据**（独立部署时；外壳里由 T22 再核一次）：

```bash
docker exec <authz 容器> sh -c 'printf %s "$PERMISSION_CATALOG" | wc -l'; wc -l < registry/permissions.tsv
docker exec be-postgres psql -U postgres -d brickkit_db -tAc "select count(*) from infra_authz.permissions"
```

通过：前两个行数一致（末尾换行可差 1，原文记录）；表行数 ≥ TSV 数据行数；authz 日志没有"同步权限目录失败"。

**重构重点**：`scripts/seed.sh` 第①步直接写库建全权限角色——配上 `BOOTSTRAP_ADMIN_SUB` 后能否改走 admin API，评估并在 `docs/design.md` 写结论（不强求改）；06a 遗留 N-1（be-ops 生成目录文件的备选）不做，在设计文档里写一句"为什么直接读注册表"。

- [ ] **Step 1: C1–C9**。`make verify` 时 iam 还不在项目里，受保护路由只验 `401`/`503`。

---

### Task 13: infra/workflow

**事实**：Go；8201 / 9201；`infra_workflow` / `infra_workflow_rw`；形态 A（`gen/infra/workflow`，最新 `v1.0.3`，sales 在用）；无依赖；发布 `infra.workflow.task.*.v1`。ROUTE=`/infra/workflow/tasks`。

**要补的接口**：无新增。确认 `GET /infra/workflow/tasks/{id}` 的响应包含审批历史（`TaskDetail`），没有就补一条 L2 测试把它钉住（BFF 的 `task(id)` 依赖它）。

**重构重点**：超时 / 逾期扫描（`task.overdue`）的定时循环是否用 `FOR UPDATE SKIP LOCKED` 认领；`Start()` 里多个后台循环是否并发启动（参照 T7 `module.go` 的写法）。

**已知**：`gen/` 在 v1.0.4 就与 `.proto` 不一致（`ListTasks` 的注释），`go-v2.sh` 的 gen 判据会 FAIL。C4 先 `buf generate` 单独一个提交（只有注释变化），再 `go-v2.sh $ID --recheck --gen-bump patch`（只是重新生成 → 契约包升 patch：`gen/infra/workflow/v1.0.4`）；交接时告诉控制者。

- [ ] **Step 1: C1–C9**。

---

### Task 14: infra/notification

**事实**：Go；8202 / 9202；`infra_notification` / `infra_notification_rw`；**形态 B**（`gen/infra/notification` 拆成嵌套模块，第一个 tag `v1.0.0`）；无依赖；数据范围 `owner`（`recipient_sub`）；消费 iam 用户事件、`infra.workflow.task.created.v1`、`integration.im.result.v1`，发布 `infra.notification.dispatch.*`。ROUTE=`/infra/notification/notifications`。

**要补的接口**（frontend-needs §2.8）：`GET /infra/notification/preferences` 的权限键从 `infra.notification.preference.edit` 改成 `infra.notification.view`（键本身不变，只改路由绑定）；`PUT` 保持 `edit`。L2 测试：只有 `view` 的用户能读不能写。

**配置值**：`IM_TARGET_ADAPTERS` 保持注释（默认 `dingtalk`）——但按 Review Focus 2，真机时临时配一个非默认值（例如空串）确认分发行为随之变化，再改回注释。

**重构重点**：形态 B 是 Review Focus 1 的高危组件（06a 在它上面复现过回退）——`go-v2.sh` 的判据必须全过；消费者测试用测试私有 subject（项目惯例）。

- [ ] **Step 1: C1–C9**。交接时告诉控制者需要打 `gen/infra/notification/v1.0.0`。

---

### Task 15: integration/im-dingtalk

**事实**：Go；8207 / 9207；`integration_im_dingtalk` / `integration_im_dingtalk_rw`；**形态 B**（`gen/integration/im`，第一个 tag `v1.0.0`）；无依赖；消费 `infra.notification.dispatch.im.v1`，发布 `integration.im.result.v1`。ROUTE=`/integration/im/admin/deliveries`。

**要补的接口**：无（菜单问题归 06c）。

**配置值**：`DINGTALK_APP_KEY: ${INTEGRATION_IM_DINGTALK_DINGTALK_APP_KEY}`、`DINGTALK_APP_SECRET: ${INTEGRATION_IM_DINGTALK_DINGTALK_APP_SECRET}`、`DINGTALK_AGENT_ID: ${INTEGRATION_IM_DINGTALK_DINGTALK_AGENT_ID}`（P7）。本地没有真实钉钉应用：在 `.env` 里填明显是假的值（例如 `fake-local-key`），`BRICKKIT.md` 的 Before you deploy 写明"没有真实值时组件能启动，投递会失败并记录"；真机核对的是"投递失败被记录、发布了失败结果事件、没有崩溃"，不是投递成功。`DINGTALK_BASE_URL` 保持注释。

**重构重点**：`tokenmgr` 的 token 缓存与刷新是否并发安全；对外 HTTP 调用的超时；失败重试是否有上限并进死信。

- [ ] **Step 1: C1–C9**。交接时告诉控制者需要打 `gen/integration/im/v1.0.0`（以 `go-v2.sh` 打印的实际路径为准）。

---

### Task 16: infra/print（Python）

**事实**：Python 3.12（FastAPI、yoyo、WeasyPrint）；8400 / 9400；`infra_print` / `infra_print_rw`；无依赖；没有 `/v2` 与契约包 tag 这回事。ROUTE=`/infra/print/templates`。

**Interfaces:**
- Produces: `infra/print@2.0.0`（单 tag）；Python 包名从 `app` 改成 `infra_print`（外壳 py-render 的入口变成 `from infra_print.module import create_module`）；`GET /infra/print/templates/{id}/versions`；种子数据带一份默认送货单模板，模板 id `sales.delivery_note`。

**要补的接口**（frontend-needs §2.7）：`versions` 响应 `{ versions: [{ version, name, enabled, created_at }] }`，权限 `infra.print.template.view`；`preview` 用 `infra.print.template.edit`、`render` 用 `infra.print.render`——现状已是如此，补一条 L2 测试把它钉住。

**C3/C4 的 Python 对应项**（component-loop §4 末尾的 Python 段）：`pyproject.toml` 版本 `2.0.0`，besdk 钉 `v0.4.4`（与 T21 的 py-render 相同）；`backend/app/` → `backend/infra_print/`，`[tool.setuptools.packages.find]` 的 `include` 改成 `["infra_print*", "infra*"]`，全仓 import、`component.yaml` 的 `migration.command`（`["python", "-m", "infra_print.migrate", "apply"]`）、`local.runCommand`、Dockerfile、测试一起改；`migrate.py` 改读 `PG_*`（yoyo 的 `postgresql://` 用 psycopg2，DSN 带 `sslmode=disable` 或按 libpq 默认 `prefer`，以 `make migrate-idempotent` 真跑通过为准）；`module.py` 删 `_MIGRATIONS_DIR`（v1 起迁移只由 brickKit 用本组件镜像跑，模块在外壳里不该读相对路径）；`string_or("pgSchema", …)` → `PG_SCHEMA`。`local.runCommand` 在 `make verify FOCUS=1` 真机确定后回写 `manifest-overrides.yaml`。

**重构重点**：渲染路径里的任何运行期读文件（component-loop §4.2 末尾"成员运行期读文件"一条）——模板在库里、字体在镜像里，外壳镜像也必须有同样的系统库与字体（T21）；`docs/` 下指向 `../docs/design/` 的两处 `DOC_LINK_NOT_PORTABLE` 随文档重写消失。

- [ ] **Step 1: C1–C9**。测试用 `uv venv --seed -p 3.12 $S/venv && $S/venv/bin/pip install -e '.[dev]' && $S/venv/bin/pytest -q`。`make test-cross` 不适用（记录写"不适用"）。

---

## W2：依赖 W1 的组件（上游一发布就开工；C1–C6 可在 T8 之后提前做）

提前开工时注意：这三个组件的 Go 代码只依赖上游的**契约包**（`gen/<domain>/<name>`，已有的 `v1.0.x` tag 早已推送），所以 C4 的编译与单元 / L2 测试不需要上游 2.0.0；C7（接入项目、真机）与 C8 必须等上游"已发布"。C1 里"上游已发布"一条在提前开工时记为"待 C7 前复核"。

### Task 17: infra/iam-casdoor

**前置**：T12 已发布。

**事实**：Go；8200 / 9200；`infra_iam_casdoor` / `infra_iam_casdoor_rw`；**形态 B**（`gen/infra/iam`，第一个 tag `v1.0.0`）；依赖 `infra/authz@2.0.0`（真实 gRPC 业务调用，保留）；import 契约包 `github.com/brickKit/infra-authz/gen/infra/authz v1.0.5`；消费 `infra.authz.user_role.changed.v1`，发布 `infra.iam.user.*.v1`。ROUTE=`POST /api/iam/logout`（`besdk.Authenticated`；不带 token 期望 401）。

**Interfaces:**
- Produces: `infra/iam-casdoor@2.0.0`；`ENABLED_COMPONENTS` 的含义改为"项目 `brickkit.yaml` 的内容"（R27）；JWKS `/.well-known/jwks.json` 与 `config/vars.yaml` 的 `IAM_JWKS_URL`（`infra-iam-casdoor-2-0-0`）对上。

**配置值**（P7）：

| 键 | 值 |
|---|---|
| `CASDOOR_BASE_URL` | `http://host.docker.internal:8000`（基础资源 Casdoor） |
| `CASDOOR_ADMIN_PASSWORD` | `${CASDOOR_ADMIN_PASSWORD}`（基础资源的变量，沿用） |
| `WEBHOOK_SHARED_SECRET` | `${INFRA_IAM_CASDOOR_WEBHOOK_SHARED_SECRET}` |
| `APP_TOKEN_SIGNING_KEY_PEM` | `file://.secrets/infra-iam-casdoor/app-token-signing-key.pem`（从 `.env` 现有的 `APP_TOKEN_SIGNING_KEY_PEM` 原样写出，文件 0600，`.secrets/` 已被忽略） |
| `ENABLED_COMPONENTS` | `file://brickkit.yaml` |
| `WEBHOOK_CALLBACK_URL` | 见下 |

**要做的**：
1. `ENABLED_COMPONENTS` 解析器（component-loop §2.5）：现在按逗号切（`module.go` 的 `splitNonEmpty`），改成解析 YAML：取 `components[].id`，跳过 `kind: shell` 的条目，去重（同一 ID 的 `requiredBy` 兼容版本只算一次），稳定排序；**只**读 `components` 这一段，其余内容（`sources` 等）解析后立即丢弃、不进日志（06a N-4：`sources[].authToken` 的 `${VAR}` 会被 compose 运行期替换成真值）。L2 测试用真实形态的 `brickkit.yaml`（含外壳条目、`requiredBy` 行、带 `authToken: ${X}` 的 source）。`BRICKKIT.md` 写明值的含义与"已安装 ≠ 在运行"。`ENABLED_COMPONENTS` 在 `configSchema` 里 required、无默认值。
2. `WEBHOOK_CALLBACK_URL`：旧值 `http://172.18.0.1:8200/…`（写死的网桥地址）。v1 下 Casdoor 是基础资源（不在 brickKit 网络里），要回调本组件：先 `brickkit docs 02-project-guide/03-local-debug-workflow` 与 `brickkit docs 01-three-layers/03-deploy-yaml`（`expose`）找正当做法，候选：deploy 条目 `expose: true` + `http://host.docker.internal:8200/api/iam/webhooks/casdoor`。选定后写进 `docs/design.md` 与 BRICKKIT 的 Before you deploy；外壳托管后（T22）同一地址仍可达是判据之一。翻了 brickKit 源码才定下来的，记知识缺口。
3. 多行密钥端到端（06a Review Focus 2 的真机半程）：独立部署时 `docker exec <iam 容器> sh -c 'printf %s "$APP_TOKEN_SIGNING_KEY_PEM"' | sha256sum` 与 `sha256sum .secrets/infra-iam-casdoor/app-token-signing-key.pem` 相同；`GET /.well-known/jwks.json` 返回的公钥能验 `get_app_jwt dev.superuser` 拿到的 token。T22 在外壳里再核一次。

**C7 特别说明**：本组件加入项目后，authz + iam 都在，`make verify` 的"带 token"一项第一次能真跑。种子用户与全权限角色这样灌（整段在**同一次持锁**里，否则别的工作线的 verify 收尾会收掉 KEEP 的容器）：`bash $ROOT/infra/scripts/project-lock.sh -- bash -c 'make -C $ROOT verify ID=infra/iam-casdoor ROUTE=… SEED=1 KEEP=1 && make -C $ROOT/components/infra/authz seed; brickkit down -f deploy.verify.yaml; rm -f deploy.verify.yaml'`，然后对 authz 再跑一次 `make verify ID=infra/authz ROUTE=/api/admin/roles`，期望带 token 一项 `200`。`BOOTSTRAP_ADMIN_SUB` 按 component-loop §2.5 用 `sub_of dev.superuser` 查出后写进 `.env`。

**重构重点**：`casdoor/`、`tokens/`、`keys/` 三个包的边界；签名密钥轮换（`APP_TOKEN_PREVIOUS_PUBLIC_KEY_PEM`）有没有测试；Casdoor 管理 API 的超时与错误映射。

- [ ] **Step 1: C1–C9**。交接时告诉控制者需要打 `gen/infra/iam/v1.0.0`。

---

### Task 18: erp/sales

**前置**：T7、T9、T10、T11 已发布；T13（workflow，optional）在 C7 时已发布就一起起，没发布就记"workflow 缺席，异常待办降级为日志"。

**事实**：Go；8084 / 9094；`erp_sales` / `erp_sales_rw`；**形态 B**（`gen/erp/sales`，第一个 tag `v1.0.0`）；依赖 `mdm/customer`、`mdm/product`、`erp/inventory`、`erp/finance`（required，`@2.0.0`）、`infra/workflow`（optional）；import 上游契约包 `mdm-customer/gen v1.0.6`、`mdm-product/gen v1.0.7`（用不到 product 的新字段就不升）、`erp-inventory/gen v1.0.14`、`erp-finance/gen v1.0.10`（T11 升了 minor 且 sales 要用新字段才升）、`infra-workflow/gen v1.0.3`；数据范围 `org` + `owner`；消费 `crm.opportunity.won.v1`（TCC 自动建单）、`infra.workflow.task.completed.v1`、`mdm.customer.*`；发布 `sales.order.created/cancelled/shipped.v1`。ROUTE=`/erp/sales/orders`。

**Interfaces:**
- Produces: `erp/sales@2.0.0`；`Order.source_opportunity_id`（REST 与 gRPC 消息都加，只增）；`GET /erp/sales/orders?source_opportunity_id=`；`GET /erp/sales/stats/summary`；事件 `sales.order.created.v1` 的 payload 新增可空字段 `source_opportunity_id`（P9，`contracts/events/sales.events.json` 只增）。
- 配置值：`DEFAULT_WAREHOUSE_ID: "1"`（erp/inventory 迁移 `003_seed_warehouses` 预置的仓库；先查 `select id from erp_inventory.warehouses` 核对）、`EXCEPTION_ASSIGNEE_SUB: u_ops_reviewer`（旧项目的值；按 Review Focus 2，真机核对异常待办真的派给了它）。

**要补的接口**（frontend-needs §2.4，P9、P10）：
1. 迁移：订单主表（表名以 `migrations/` 为准）加列 `source_opportunity_id TEXT NOT NULL DEFAULT ''`（新迁移文件，不改旧迁移；表属主已是 `erp_sales_rw`，T5 重置过；分区表要确认加列对全部分区生效）；赢单 TCC 路径（`backend/internal/tcc/opportunity_won.go`）建单时写入；手工建单为空串，建单请求**不接受**这个字段。
2. `GET /orders` 加 `source_opportunity_id` 过滤。
3. `sales.order.created.v1` 的 payload 带上 `source_opportunity_id`（在同一个事务里写 outbox）。
4. `GET /stats/summary`：query `period`（`month` 默认 / `week` / `quarter`），响应照抄 frontend-needs §2.4；**不带视角参数**（P10，sales 的 List 没有），按与 List 完全相同的 `org`/`owner` 数据范围过滤；金额字符串。
L2 测试：赢单事件 → 订单的 `source_opportunity_id` 等于商机 id、`sales.order.created.v1` 的 outbox 行带该字段；手工建单为空；`stats/summary` 两个不同范围的用户看到不同的数（Review Focus 5）；`period` 边界。

**重构重点**：全仓最大的组件（5707 行）——`tcc/` 的补偿路径是否满足 02-backend.md 的"超时先 `GetStatus`、补偿失败三次 `SUSPENDED` 并开异常待办"；`consumer.go` 里赢单 payload 的结构体与 crm 契约逐字段对照（只读不 import）；`client/` 里同步调用上游的超时与重试；有没有用户请求路径上用了 `SystemClient`（`make gates` 的 `system-client-scan` 也会抓）。

- [ ] **Step 1: C1–C9**。C7 的 `make verify` 闭包里会起 customer、product、inventory、finance（以及 workflow）。`make test-cross ID=erp/sales` 里此前 SKIP 的跨组件测试必须 PASS。**V-12** 在本组件的 `FOCUS=1` 里验：本机进程连容器里的 customer / product / inventory / finance（以及 postgres、nats）是否都通，原文记录 `deploy.local.yaml` 的 `vars:` 改写与结果。交接时告诉控制者需要打 `gen/erp/sales/v1.0.0`。

---

### Task 19: crm/opportunity

**前置**：T7、T9 已发布。

**事实**：Go；8102 / 9102；`crm_opportunity` / `crm_opportunity_rw`；**形态 B**（`gen/crm/opportunity`，第一个 tag `v1.0.0`）；依赖 `mdm/customer`、`mdm/product`（required，`@2.0.0`）；数据范围 `org` + `owner`，List 有 `view=mine|dept`；发布 `crm.opportunity.won/lost/stage_changed.v1`，消费 `mdm.customer.*`。ROUTE=`/crm/opportunity/opportunities`。

**Interfaces:**
- Produces: `crm/opportunity@2.0.0`；`Opportunity.order_id`（REST 与 gRPC，只增）；`GET /crm/opportunity/opportunities/{id}/stage-history`；`GET /crm/opportunity/opportunities/funnel`；新消费者订阅 `sales.order.created.v1`（P9）。
- Consumes: `sales.order.created.v1` 的 `order_id` 与新字段 `source_opportunity_id`（按 P9 写定的形状，不 import sales 任何东西，宽容反序列化：字段缺失 = 空串 = 忽略）。

**要补的接口**（frontend-needs §2.6，P9、P10）：
1. 迁移：商机主表（表名以 `migrations/` 为准）加列 `order_id TEXT NOT NULL DEFAULT ''`（新迁移文件）。
2. 消费者：`source_opportunity_id` 非空且是本组件的商机 → 在事务里写 `order_id`（已有相同值跳过；已有不同值记 ERROR 不覆盖）；按 `event_inbox` 幂等。测试用测试私有 subject。
3. `stage-history`：读已有的阶段历史表；权限 `crm.opportunity.view`；受 `org`/`owner` 范围（看不到的商机 → 404，不泄露存在性）。
4. `funnel`：只统计 OPEN，`view=mine|dept` 与 List 完全一致（P10，是切换不是 OR）；`weighted_amount = expected_amount × probability` 用十进制。
5. **路由冲突**（06a 遗留）：`/opportunities/funnel` 与 `/opportunities/:id` 同时注册——写一条 L4 测试（真实 Gin 引擎）证明 `GET /opportunities/funnel` 打到 funnel、`GET /opportunities/123` 打到详情。
L2 测试：消费者回填（含重复投递、乱序、不同值不覆盖）；funnel 在 `mine` / `dept` 下两个用户看到不同的数（Review Focus 5）；stage-history 的范围隔离。

**重构重点**：`backend/internal/repo/write.go`（506 行）；赢单 `MarkWon` 与 outbox 同事务；`client/` 对 customer/product 的同步调用超时。

- [ ] **Step 1: C1–C9**。业务闭环（赢单 → 订单 → 回填）要等 T18 也在项目里，放 T25 验；本 Task 的 C7 只验本组件与 customer/product。交接时告诉控制者需要打 `gen/crm/opportunity/v1.0.0`。

---

## W3

### Task 20: infra/bff-mobile（TypeScript）

**前置**：T7、T9、T10、T13、T14、T18、T19 已发布（C1–C6 可在 T8 之后按本计划写定的上游接口提前做）。

**事实**：TypeScript（Node ≥ 24，GraphQL，vitest）；8500；不连库；依赖全部 optional：`mdm/customer`、`mdm/product`、`erp/sales`、`erp/inventory`、`infra/workflow`，以及 P11 新增的 `infra/notification`、`crm/opportunity`（全部 `@2.0.0`）；`data_scopes: none`（真实数据权限由下游 REST 判）。ROUTE=`POST /graphql`（不带 token 期望 401）。

**Interfaces:**
- Produces: `infra/bff-mobile@2.0.0`（单 tag）；`contracts/schema.graphql` 新增 frontend-needs §2.10 表里的全部操作（`task(id)`、`approveTask`/`rejectTask`——首个 `Mutation`、`myNotifications`、`inventoryBalances`、`warehouses`、`searchProducts`、`myOpportunities`/`opportunity(id)`），只增不改已有 6 个 query。
- Consumes: workflow `GET /tasks/{id}`、`POST /tasks/{id}/approve|reject`；notification `GET /notifications`；inventory `GET /balances/list`、`GET /warehouses`；product gRPC `List`（带 `q`，契约包 `v1.1.0`）；opportunity `GET /opportunities?view=mine`、`/opportunities/{id}`。

**新权限键**：`infra.bff-mobile.task.act`、`infra.bff-mobile.notification.view`、`infra.bff-mobile.opportunity.view`（`type: action`）→ `make permissions`。

**C3/C4 的 TS 对应项**：`package.json` 版本 `2.0.0`，besdk 钉 `git+https://github.com/brickKit/be-sdk-ts.git#v0.4.0`；新签名 `userClient(config, auth, dep, extra)` / `systemClient(config, dep, extra)`，地址只用 `config.endpoint()`；optional 依赖缺席时对应字段不注册（schema 测试覆盖"缺 notification 时没有 `myNotifications`"）；`startPeriodSeconds: 90`；`local.runCommand` 在 `make verify FOCUS=1` 真机确定后回写 `manifest-overrides.yaml`。

**要做的**：
1. 有真实数据权限的操作一律 REST 转发调用者的 `Authorization`（沿用现有 `restForward.ts`），只有 product / customer 的批量读走 gRPC。`approveTask`/`rejectTask` 透传幂等键。
2. **供应方 `.proto`**：`src/clients/grpcProto.ts` 运行期加载随仓库携带的 `mdm/product/v1/product.proto` 等文件——从 mdm-product、mdm-customer 的 `2.0.0` tag 原样取出更新（只读拷贝 `.proto`，不拷生成代码），在 `AGENTS.md` 的 Pitfalls 写明"更新上游 proto 只从对方的发布 tag 取，并记 tag"。
3. 测试：`npm test` 覆盖每个新操作（对下游用桩）、Mutation 的幂等透传、401 透传；e2e 测试在 C7 之后对真实下游跑一次。

**重构重点**：`README.md` 里指向 `../../../docs/design/` 的链接（`DOC_LINK_NOT_PORTABLE`）随文档重写消失；resolver 是否全部经带权限键的包装注册（`make gates` 的 `bare-route-scan`）。

- [ ] **Step 1: C1–C9**（TS：`npm ci && npm test`；`make test-cross` 不适用）。C7 的闭包包含它的全部 optional 依赖（已加入项目的）。带 token 打一次 `searchProducts`、`warehouses`、`myOpportunities`，原文记录。

---

## 外壳（成员全部发布后组装；每个外壳一个 Task，彼此并行）

四个外壳 Task 共用下面的"外壳通用流程"，细节在 `component-loop.md` §4（T6 已更新）。外壳是独立仓库（`brickKit/be-<name>`），以子模块挂在 `shell/be/<name>/`：外壳文件在子模块里提交，控制者在子模块里 `make ship`，父仓库只提交指针。外壳第一次进 `brickkit.yaml` 时就带着全部成员（`shell.members` 不能为空；v1.1.0 的规则是"外壳和它的第一个成员一起加入"——这里成员都已作为独立组件在项目里，`brickkit add` 外壳时它们被移进外壳）。

**外壳通用流程**（`$SH=be/<name>`、`$SHD=$ROOT/shell/be/<name>`、`$SHN=<name>`）：

- [ ] **H1 前置**（component-loop 4.1）：每个成员 `git -C <成员> ls-remote --tags origin 2.0.0` 有一行（Go 成员还有 `v2.0.0` 和根 `go.mod` require 的 `gen/*` tag）；`git -C $SHD status --short` 为空且在 `main`（detached 时 `git -C $SHD switch main && git -C $SHD pull --ff-only`）；`git -C $SHD tag -l` 为空。
- [ ] **H2 外壳文档修正**（可在 T8 之后提前做，plan.md 待办）：`BRICKKIT.md`/`.zh.md` 不再引用本项目的 `registry/ports.tsv`、`make db-init`——外壳会被别的装配项目复用，改成通用说法："装配项目为外壳建一个 PostgreSQL 登录角色（本外壳的约定名 `shell_<name>`，口令变量 `SHELL_<NAME>_PASSWORD`），并把每个成员的 `<schema>_rw` 角色授给它"；`AGENTS.md`/`.zh.md` 的同类说法一并改；`Purpose` 里"目前没有编译进任何成员"之类的过渡说法删掉；`Shell declaration` / `外壳声明` 列出与 `shell.members` 完全相同的成员。
- [ ] **H3 成员清单三处一起改**（component-loop 4.2）：`component.yaml` 的 `shell.members`；Go：`main.go` 的 `shell.Registry`（键是成员 ID，值是 `<成员模块>/v2/backend/module.New`）+ `go get <成员>/v2@v2.0.0 …` + be-sdk-go 升到 `v0.4.0` + `go mod tidy && go build -o /dev/null ./...`；Python：`pyproject.toml` 加成员依赖、besdk 钉 `v0.4.4`、`main.py` 的 registry。核对 Review Focus 1、3：`go list -m all | grep brickKit/`（每个成员恰好 `v2.0.0`，没有任何 `brickKit/<repo> v1.`），`go mod graph | grep be-sdk-go` 只有一个选中版本。契约包解析失败（`unknown revision …`）回到成员修，不在外壳里加 `replace`。
- [ ] **H4 外壳 lint**：`make -C $ROOT docs-check ID=$SH` → `0 with errors, 0 warnings`。
- [ ] **H5 接入与真机**：
  ```bash
  make -C $ROOT integrate ID=$SH VERSION=1.0.0        # brickkit add 外壳：成员移进外壳；config-fill 写 shell_<name>；teardown-sync；db-init 授权
  make -C $ROOT verify ID=$SH                          # build（镜像标签 io.brickkit.shell.members）、只起闭包、成员运行期核对、R15 日志检查
  ```
  另外手工核对（结果贴进记录）：`docker image inspect be-$SHN:1.0.0 --format '{{ index .Config.Labels "io.brickkit.shell.members" }}'` 与 `shell.members` 逐字相同（V-03）；外壳登录角色的成员授权（component-loop 4.3 的 `pg_auth_members` 查询）；每个成员带真 token 打一条受保护路由 `200`（Review Focus 4）；`make test-cross ID=<每个 Go 成员>` 绿（依赖此时由外壳托管）；`make tier2`（需要 `TEST_PG_DSN`/`TEST_NATS_URL`；红了先判断是不是 06f 待重写的旧断言）；拆回验证 `bash infra/scripts/project-lock.sh -- bash -c 'brickkit up --ignore-shells --dry-run && make teardown-up && brickkit status -f deploy.teardown.yaml; make teardown-down'`，全部成员各自 healthy。
- [ ] **H6 交接发布**：外壳子模块里提交（`git -C $SHD add -A && git -C $SHD commit -F $S/msg-be-$SHN.txt`），发布说明 `$S/notes-be-$SHN-1.0.0.md`（成员清单与版本、外壳登录角色要求、SDK 版本）。控制者：`make -C $ROOT ship DIR=shell/be/$SHN NOTES=$S/notes-be-$SHN-1.0.0.md`（只打裸 tag `1.0.0`）；发布后外壳又改过的，`brickkit build $SH --force`；父仓库按路径提交 `shell/be/$SHN brickkit.yaml deploy.yaml deploy.teardown.yaml config/be-$SHN.yaml AGENTS.md`，`git submodule status shell/be/$SHN` 显示 `(1.0.0)`，`make version-check` 里这一行 `✓`。
- [ ] **H7 记录**：`dev/test-records/06b/be-$SHN.md`。

### Task 21: 外壳 be/py-render

**前置**：T16 已发布。**成员**：`infra/print@2.0.0`。端口 8402；登录角色 `shell_py_render` / `${SHELL_PY_RENDER_PASSWORD}`。

**特有**：`main.py` 改为 `from infra_print.module import create_module` 与 `main("be-py-render", {"infra/print": create_module})`（入口名以 infra-print 2.0.0 的实际导出为准）；`pyproject.toml` 加 `"infra-print @ git+https://github.com/brickKit/infra-print.git@2.0.0"`，besdk 与 infra-print 钉同一个 `v0.4.4`；`Dockerfile` 补 WeasyPrint 系统库与中文字体（对照 `components/infra/print/Dockerfile` 的 `apt-get install` 列表与 `fc-cache -f`），并改成多阶段构建（06a 遗留：单阶段 517MB），记录前后镜像体积。本地验证：`uv venv --seed -p 3.12 $S/pyvenv && $S/pyvenv/bin/pip install $SHD && $S/pyvenv/bin/python -c 'import main, infra_print.module'`。真机多核一项：经外壳调 `POST /infra/print/render` 渲染 `sales.delivery_note` 得到 PDF，`pdftotext`（或检查字节头 `%PDF`）确认中文没有乱码。R15 判据用 be-sdk-python README"外壳失败契约"的原文（T2）。**V-03 Python 半程**在这里记结论。

- [ ] **Step 1: H1–H7**。

### Task 22: 外壳 be/go-infra

**前置**：T12、T13、T14、T15、T17 已发布。**成员**：`infra/authz@2.0.0`、`infra/iam-casdoor@2.0.0`、`infra/workflow@2.0.0`、`infra/notification@2.0.0`、`integration/im-dingtalk@2.0.0`。端口 8224；`shell_go_infra` / `${SHELL_GO_INFRA_PASSWORD}`。

**特有**：
- `config/vars.yaml` 的 `AUTHZ_BUNDLE_URL` / `IAM_JWKS_URL` **不改**（成员服务名从此由外壳容器的网络别名解析，R29）。
- authz 与 iam 合并后的三项运行期核对：`PERMISSION_CATALOG` 在 `BRICKKIT_SERVED_MEMBERS_CONFIG` 里 `infra/authz` 那一项的行数与 `registry/permissions.tsv` 一致；`APP_TOKEN_SIGNING_KEY_PEM` 在 `infra/iam-casdoor` 那一项里与 `.secrets/` 文件逐字节相同（`python3 -c` 解析 JSON 后 `sha256`）；`GET /api/tenant/features` 返回的组件集合等于 `brickkit.yaml` 里非外壳组件 ID 的集合（`ENABLED_COMPONENTS`）。
- iam 的 Casdoor webhook 回调地址（T17 选定的）在外壳托管下仍可达：在 Casdoor 里改一个种子用户的显示名，iam 日志收到 webhook 并发布 `infra.iam.user.updated.v1`。
- 启动顺序：iam 依赖 authz，两者同在一个外壳里时 `brickkit up --dry-run` 若报 `depends_on` 环，按报错给的出路处理，选 `skipWaitFor` 时在记录里写明理由。
- **这是第一个 Go 外壳**（以实际先完成的为准）：V-03 Go 半程、V-06 外壳拉成员半程在第一个完成 H3/H5 的 Go 外壳上记结论。

- [ ] **Step 1: H1–H7**。

### Task 23: 外壳 be/go-core

**前置**：T7、T9、T10、T11、T18 已发布。**成员**：`mdm/customer@2.0.0`、`mdm/product@2.0.0`、`erp/inventory@2.0.0`、`erp/finance@2.0.0`、`erp/sales@2.0.0`。端口 8090；`shell_go_core` / `${SHELL_GO_CORE_PASSWORD}`。

**特有**：同一进程里 sales 对 customer / product / inventory / finance 的调用仍走 gRPC（Review：`main.go` 只有 Registry，没有任何成员之间的直接函数调用）；sales 依赖的契约包版本与成员自己 require 的版本经 Go 最小版本选择后，`go list -m all | grep '/gen/'` 每个契约包只出现一个版本，记录下来（06a N-2）；mdm/customer 若在 T8 发了 2.0.1，成员清单写 2.0.1。

- [ ] **Step 1: H1–H7**。

### Task 24: 外壳 be/go-backoffice

**前置**：T19 已发布。**成员**：`crm/opportunity@2.0.0`。端口 8116；`shell_go_backoffice` / `${SHELL_GO_BACKOFFICE_PASSWORD}`。

**特有**：crm 消费 `sales.order.created.v1` 的消费者在外壳里照常启动（日志里有该订阅、带 `module_component_id`）；R15 的"后台循环隔离"不是通过（component-loop §4.5）。

- [ ] **Step 1: H1–H7**。

---

## 集成与收尾

### Task 25: 全栈集成与业务闭环

**前置**：T20–T24 全部完成。

**Files:**
- Create: `dev/test-records/06b/integration.md`
- Possibly modify: 任何组件（发现问题时，按 version-bump-ship 发 2.0.x）、`config/vars.yaml`（authz/iam 再发版时）
- Parent（控制者）：一个"06b 集成"提交

**Interfaces:**
- Produces: 重建后的系统整体跑通的证据；`make gates` 全绿且 `service-hostname-scan` 零警告；根 `make lint` 只剩 `frontend/standard` 的条目。

- [ ] **Step 1: 项目形态核对**

```bash
cd /home/zhijie/Desktop/github/be-assembly-standard
python3 -c "import yaml;b=yaml.safe_load(open('brickkit.yaml'));[print(c['id'],c['version'],c.get('kind','')) for c in b['components']]"
make teardown-sync CHECK=1
brickkit local status
```

通过：13 个后端组件 `2.0.0`（或之后的 2.0.x）、4 个外壳 `1.0.0` `kind: shell`；`deploy.yaml` 里 12 个成员嵌在 4 个外壳下，`infra/bff-mobile` 独立；teardown 文件一致；本地模式关闭。

- [ ] **Step 2: 全量起**（锁内；本 Task 从这里到 Step 7 一直持锁：`bash infra/scripts/project-lock.sh -- bash` 开一个持锁 shell）

```bash
S25=<本会话 scratchpad>/06b/T25; mkdir -p $S25
make dev-env && make db-init
brickkit up 2>&1 | tee $S25/up.log
brickkit status
```

通过：4 个外壳与 bff-mobile 全部 `running (healthy)`，12 个迁移容器 `Exited (0)`；每个外壳跑一遍 R15 三条日志检查（component-loop §4.5）为空、`RestartCount` 为 0。

- [ ] **Step 3: 种子数据**

```bash
make -C components/infra/iam-casdoor seed && make -C components/infra/authz seed
make seed-data 2>&1 | tee $S25/seed.log
```

通过：每个组件的 seed 都打印成功；`make seed-data` 末尾 `✓ 种子数据灌完了`。

- [ ] **Step 4: 业务闭环**（每一环的查询与结果原文进记录）

1. 找一个 WON 商机：`select id, status, order_id from crm_opportunity.<商机表> where status='WON' limit 3`。
2. 对应订单：`select id, status, source_opportunity_id from erp_sales.<订单表> where source_opportunity_id='<上一步 id>'`；商机的 `order_id` 等于这张订单的 id（P9 回填）。
3. 库存预留：`select * from erp_inventory.inventory_reservations where <订单关联列>='<订单 id>'`。
4. 应收：`select * from erp_finance.ar_ledger where <来源单据列>='<订单 id>'`。
5. 同样的链路经 REST 走一遍：带 `dev.superuser` 的 token 依次打 `GET /crm/opportunity/opportunities/{id}`（`order_id` 非空）、`GET /erp/sales/orders?source_opportunity_id=<id>`、`GET /erp/inventory/balances/list?product_id=<订单里的产品>`、`GET /erp/finance/ar-ledger?customer_id=<客户>`（`outstanding`、`customer_name` 有值）。
6. 新建一个商机并推进到赢单（REST：`POST /opportunities` → `POST /opportunities/{id}/stage` → `POST /opportunities/{id}/win`），30 秒内上面 2–4 都出现。
（表名、列名以各组件迁移为准，先 `\d` 看一眼再写查询。）

通过：六步全部有结果；任一环断了就按 06-testing.md 的 When stuck 查，修在对应组件（发 2.0.x），不在集成层绕过。

- [ ] **Step 5: 横切核对**

```bash
docker exec be-postgres psql -U postgres -d brickkit_db -tAc "select count(*) from infra_authz.permissions"; grep -vc '^#' registry/permissions.tsv
docker exec be-postgres psql -U postgres -d brickkit_db -tAc "select key from infra_authz.permissions where key in ('mdm.product.set_status','infra.bff-mobile.task.act','infra.bff-mobile.notification.view','infra.bff-mobile.opportunity.view')"
docker run --rm --network brickkit-be-assembly-standard-net curlimages/curl -s http://infra-iam-casdoor-2-0-0:8200/api/tenant/features
```

通过：permissions 表行数 ≥ TSV 数据行数（第二条命令的结果减 1 行表头），4 个新键都在；features 的组件集合等于 `brickkit.yaml` 非外壳组件 ID 集合。每个组件带 token 打一条受保护路由（ROUTE 见各 Task）全部 `200`（Review Focus 4）；bff-mobile 带 token 跑 `myTasks`、`searchProducts`、`myOpportunities`、`approveTask`（对种子待办）各一次。

- [ ] **Step 6: 门禁与检查**

```bash
make gates; echo "gates=$?"
make version-check registry-check docs-boundary docs-mirror
brickkit lint --strict 2>&1 | tee $S25/lint-all.log; echo "lint=$?"
make tier0; echo "tier0=$?"
make tier2; echo "tier2=$?"      # 需要 TEST_PG_DSN / TEST_NATS_URL
```

通过：`gates=0`，`service-hostname-scan` 零违规、**零警告**（R29 的门禁此时第一次真正全绿）；`version-check` 每行 `✓`；`lint` 只剩 `components/frontend/standard` 的条目（06c 处理），逐条贴进记录；`tier0`、`tier2` 原文记录，红的先判断是不是 v0 时代的旧断言（是就记进 T26 的"交 06f"清单，不改测试）。

- [ ] **Step 7: 拆回验证**

```bash
brickkit down
brickkit up --ignore-shells --dry-run
make teardown-up && brickkit status -f deploy.teardown.yaml
# 对 12 个成员各打一次 /healthz 与一条带 token 的受保护路由（ROUTE 见各 Task；toolbox 容器 + get_app_jwt，同 make verify）
make teardown-down
```

通过：12 个成员各自独立 `running (healthy)`，受保护路由 `200`（authz/iam 地址不用任何覆盖，R29）。

- [ ] **Step 8: 收尾**：`brickkit down`、`brickkit local off`、`docker ps` 没有本项目组件容器；释放锁。控制者父仓库提交（本 Task 改过的路径 + 记录），推送。

---

### Task 26: 06b 遗留小问题收尾

**前置**：T25。

**Files:** 视清单而定（工具仓库、`infra/scripts/`、正式文档、组件）；`dev/test-records/06b/T26-minors.md`

- [ ] **Step 1: 汇总清单**：来源——`batches/06a.md` §6.1 中 06b 没有顺手解决的条目、06b 各 Task 审查留下的 Minor、过程记录里的"反馈候选"之外的项目自身问题。每条标：现在修 / 交 06c / 交 06e / 交 06f，以及理由。至少包括：
  - be-acceptance：`imageLineRe` 未限定在 `deployment` 块（v1 组件已无 `deployment.image`，判断是否还相关）；`tier2-shell` 对 `./...` 不带 `-run`；全 SKIP 子用例的父测试打印 PASS；大版本升级不改写 `go.mod` 的 `replace` 与 import 路径（06b 用 `go-v2.sh` 做了，判断是否沉淀进 `bump-version`）。
  - be-ops：`Row.ShellLoginRole` / `schemas.tsv` 第 4 列已不驱动任何东西；README 仍是 v0 叙述（"总纲 §2.4""导读"）——按 v1 重写。
  - `infra/scripts/test-db-init.sh` 删掉给迁移传的 `DATABASE_*`（13 个组件都已改读 `PG_*`）；`tier1` 桩的输出写明"占位，未验证"；口令临时文件不放共享 `/tmp`。
  - 文档：`04-configuration.md` 补"`DATABASE_*`/`MQ_*`/`STORAGE_*` 现在是普通名字"、`<REPO>` 占位符尽早解释；`make module-check` 注明是组件仓库的目标。
  - `make docs-mirror` 是否由 `brickkit lint` 取代（F06-001 已支持镜像树）：保留做双保险还是删，二选一并记录。
- [ ] **Step 2: 修"现在修"的条目**：工具仓库改完由控制者打小版本 tag；组件有改动的一律走 version-bump-ship（一份计划文件、`make bump-version` dry-run → `APPLY=1`、`make ship`、`brickkit upgrade`），成员版本变了的外壳跟着发 1.0.x（0108）；authz 或 iam 再发版时同步 `config/vars.yaml`。
- [ ] **Step 3: 回归**：有组件或外壳改动时，重跑 T25 的 Step 2、Step 5、Step 6（锁内），全绿后 `brickkit down`。
- [ ] **Step 4: 提交**（父仓库按路径），推送。

---

### Task 27: 06b 汇报，进入 06c

**前置**：T26。

**Files:**
- Create: `dev/phase-06/batches/06b.md`（给用户看的汇报）
- Modify: `dev/phase-06/to-verify.md`、`dev/phase-06/plan.md`（待办勾选、06b 行状态）、`brickkit-feedback/phase-06.md`（只放真机验证过的条目，被 git 忽略）

- [ ] **Step 1: `batches/06b.md`**，结构：
  1. 结果总表：每个组件 / 外壳的版本、tag（`2.0.0` / `v2.0.0` / `gen/*` / 外壳 `1.0.0`）、组件仓库提交 SHA、父仓库提交、过程记录路径。
  2. 与本计划的差异（D 编号，原因）。
  3. 控制者裁定 R38 起全表（裁定 + 判错的代价）。
  4. V 项结论（V-01、V-03、V-06、V-07、V-09 等）与知识缺口（V-04 新增行；先试 `brickkit docs` 的效果）。
  5. 发现：组件里修掉的真实 bug（附红测试名）、重构了什么、哪些旧判断被推翻。
  6. 遗留：T26 标为"交 06c/06e/06f"的条目。
  7. 给 06c 的输入：bff-mobile 与各 REST 接口的最终形状、菜单 schema 扩展（06a §6.2）、网关路由（`edge_routes` 与 be-ops `routes` 未实现）、print 默认模板 id、im-dingtalk 菜单。
- [ ] **Step 2: `to-verify.md`**：合并各记录里的 V 项结论与知识缺口行。
- [ ] **Step 3: 反馈信箱**：真机验证成立、属于 brickKit 的问题写进 `brickkit-feedback/phase-06.md`（新编号接 F06-009 之后），每条带原始证据路径；不催对方读。
- [ ] **Step 4: `plan.md`**：06b 行写"完成，见 `batches/06b.md`"；勾掉"SDK 注释里的旧文档路径"（T1/T2 完成的提交号）；"阶段 06 结束时删 R33 那句"保持未勾。
- [ ] **Step 5: 提交并推送**（父仓库按路径：`dev/phase-06/batches/06b.md dev/phase-06/to-verify.md dev/phase-06/plan.md`）。
- [ ] **Step 6: 进入 06c**：按自主模式不等回复，以 `batches/06b.md` §7 与 spec §6 为输入写 `dev/phase-06/plan-06c.md`。
