# 06b infra/bff-mobile：过程记录

> 本工作线中途被打断（上一个实现者用量耗尽，会话记录已无），由接手者按 `.superpowers/sdd/plan-06b/takeover.md` 从磁盘恢复状态后继续。本记录由接手者新建；C1–C3 与 C4 前半的事实取自组件仓库的提交、`$S/` 下的日志与提交信息草稿（`msg-1.txt`…`msg-11.txt`），C4 后半起为接手者亲历。本轮是 W2 提前开工，只做 C1–C6，C7 之前停下问控制者。

## 概况

- 日期：2026-10-02
- brickKit：`BrickKit CLI v1.1.0`（`env.sh`：`ℹ️  env.sh：BrickKit CLI v1.1.0（/home/zhijie/.local/bin/brickkit）；buf 在；TEST_PG_DSN 由 .env 的 POSTGRES_PASSWORD 在 eval 时拼出（URL 编码，不打印值），TEST_NATS_URL=nats://localhost:4222`）
- SDK：be-sdk-ts v0.4.0（`git -C tools/be-sdk-ts describe --tags --abbrev=0` → `v0.4.0`；`package.json` 钉 `git+https://github.com/brickKit/be-sdk-ts.git#v0.4.0`，lock 里 resolved 到 `1e752d5`，与 tag 同一提交）
- 基础资源：`make check` → `✓ 全部基础资源就绪`
- 组件与版本：infra/bff-mobile 1.0.22 → 2.0.0（组件仓库 HEAD `90536b9`，origin/main 之上 17 个提交，未推送、未打 tag；TS 组件只打 `2.0.0` 一个 tag，由控制者 `make ship` 打）
- 交接：C1–C6 完成，停在 C7 之前（见"小结"）

## infra/bff-mobile

### 目标

本组件按 component-loop 重建到 2.0.0；补 frontend-needs §2.10 的全部操作（`task(id)`、`approveTask` / `rejectTask`——首个 Mutation、`myNotifications`、`inventoryBalances`、`warehouses`、`searchProducts`、`myOpportunities` / `opportunity(id)`）；P11 新增可选依赖 `infra/notification@2.0.0`、`crm/opportunity@2.0.0`；三个新权限键。本组件没有 V 项探针（V-13 在 C7 的 7.1 观察）。

### 环境

brickKit v1.1.0，部署目标 docker；本组件独立容器（TS，不进外壳），不连库（`SCHEMA`/`ROLE` 为空，所有数据库条目跳过）；local 模式关；本轮没有起任何组件容器。

### 步骤

**C1 前置**

- 1.1 上游（C1 时记"待 C7 前复核"；接手时 2026-10-02 现状如下，C7 前须重跑）：
  ```
  mdm/customer: refs/tags/2.0.0 refs/tags/v2.0.0
  mdm/product: refs/tags/2.0.0 refs/tags/v2.0.0
  erp/sales: （无 2.0.0 tag）
  erp/inventory: refs/tags/2.0.0 refs/tags/v2.0.0
  infra/workflow: refs/tags/2.0.0 refs/tags/v2.0.0
  infra/notification: refs/tags/2.0.0 refs/tags/v2.0.0
  crm/opportunity: （无 2.0.0 tag）
  ```
  项目里：mdm/customer、mdm/product、erp/inventory、infra/workflow、infra/notification 为 2.0.0；erp/sales、crm/opportunity 缺。全部是 optional：缺席时对应字段不注册（`order`/`myOrders`、`myOpportunities`/`opportunity`）。
- 1.2 组件仓库：接手时 `## main...origin/main [ahead 11]`，3 个未提交文件（`src/clients/product.ts`、`src/resolvers/product.ts` 改动，`test/product.test.ts` 新增）——上一个实现者的 searchProducts 红绿循环，读过后保留并完成（见 C4）。最后一个 1.x tag `v1.0.22` 在本地。
- 1.3 `make check` 全绿；1.4 工具见概况；1.6 不连库，跳过。

**C2 骨架与文档骨架**（上一个实现者，提交 `281a05a`）：`brickkit new` 输出见 `$S/brickkit-new.log`（`✅ Component skeleton generated: infra/bff-mobile`）；旧文件留底在 `$S/old/`；`docs/手册.md` 已删；`.claude/skills/brickkit-component/SKILL.md` 已提交（P6）；`AGENTS.md` 末尾有 `<!-- brickkit:managed:begin lang=en -->`。

**C3 清单**（上一个实现者，提交 `281a05a`；`$S/c3-write.log`）：
```
📦 infra/bff-mobile：输入 = tag v1.0.22 的 component.yaml / assembly.yaml + manifest-overrides.yaml
   assembly.yaml 删除的键：['version', 'asset']；…
   旧键 → 新键：{'otelBaseUrl': 'OTEL_BASE_URL', 'iamJwksUrl': 'IAM_JWKS_URL', 'authzBundleUrl': 'AUTHZ_BUNDLE_URL'}
   assembly.yaml 追加：{'permissions': ['infra.bff-mobile.task.act', 'infra.bff-mobile.notification.view', 'infra.bff-mobile.opportunity.view']}
```
`brickkit lint` 第一行 `🔎 Only infra/bff-mobile is checked …`、`✅ components/infra/bff-mobile/component.yaml`，只剩 `DOC_PLACEHOLDER`（`$S/lint-c3.log`）。`make permissions` 已跑：父仓库 `registry/permissions.tsv` 的未提交 diff 里有本组件三行：
```
+infra.bff-mobile.notification.view	查询我的通知（移动端）	action	infra/bff-mobile	
+infra.bff-mobile.opportunity.view	查询我的商机（移动端）	action	infra/bff-mobile	
+infra.bff-mobile.task.act	处理我的待办（移动端）	action	infra/bff-mobile	
```
同一 diff 里另有一行别的组件的：`+mdm.product.set_status	启用/停用产品	action	mdm/product`（mdm/product 工作线，已发布 2.0.0；按 3.5 记录、未动）。接手后重跑 `migrate-manifest.py infra/bff-mobile --check` → `✅ --check 全部为"无"`，exit 0。

**C4 代码**（TS：没有 go-v2.sh；按 component-loop 4 的 TS 对应项）

上一个实现者的提交（按顺序）：`281a05a` 机械迁移（besdk v0.4.0、`userClient(config, …)`、地址只从 `config.endpoint()`）→ `e44d46b` 客户端测试调用点跟随（断言未动）→ `e255c52` vendor 的 product.proto 换成带 `q` 的版本并新建 `contracts/vendor/SOURCES.tsv` → `812b684` 重构 → `3794eeb` 测试注释（断言未动）→ `fa2dd4f` 修 `order(id)` 的路径注入（红绿）→ `18a6c0c` 契约新增与按依赖裁剪 Mutation（红绿）→ `b71bb2c` 下游 REST 拒绝透传 `extensions.code`（红绿）→ `c73a43d` `task(id)` 与 `approveTask`/`rejectTask`（红绿）→ `9d79eca` R51 守护测试 → `8258142` 其余读字段（红绿）。

接手后：

- vendor proto 与上游发布 tag 逐字核对（`git show 2.0.0:contracts/…proto | diff -`）：`PRODUCT_SAME`、`CUSTOMER_SAME`；mdm/product 的 `2.0.0` 与 `gen/mdm/product/v1.1.0` tag 都在远端。
- **searchProducts**（`34ac6d4`）：把上一个实现者未提交的实现暂存后跑 `test/product.test.ts`，红：
  ```
  × searchProducts > 调 gRPC List，keyword 进 q、分页参数照传，Authorization 进 metadata，枚举前缀剥掉
    → {"errors":[{"message":"Unexpected error.",…"extensions":{"code":"INTERNAL_SERVER_ERROR"}}],"data":null}: expected [ { …(4) } ] to be undefined
  × searchProducts > 没有 product.view：HTTP 403，gRPC 收不到调用 → expected 200 to be 403
  × searchProducts > 不带 token：HTTP 401 → expected 200 to be 401
  ```
  恢复实现后 3 条绿，全量 `Tests  38 passed | 3 skipped (41)`。
- **R51 应用到 gRPC 下游（真实缺口）**：REST 转发已按 R51 处理，但 gRPC（mdm-customer / mdm-product）回 `INVALID_ARGUMENT` 等调用者错误时，`callUnary` 直接把 ServiceError 抛给 Yoga：客户端拿到 `INTERNAL_SERVER_ERROR`，Yoga 用自带 logger 记一条 `ERR`。先 `55e714b` 重构（gRPC 客户端改收 Caller，测试只改调用点、断言未动），再 `189bb1b` 红绿：新 `test/grpcErrors.test.ts` 6 条红：
  ```
  AssertionError: expected 'INTERNAL_SERVER_ERROR' to be 'BAD_USER_INPUT'
  AssertionError: expected 'INTERNAL_SERVER_ERROR' to be 'UNAUTHENTICATED'
  AssertionError: expected 'INTERNAL_SERVER_ERROR' to be 'FORBIDDEN'
  AssertionError: expected 'INTERNAL_SERVER_ERROR' to be 'CONFLICT'
  AssertionError: expected 'INTERNAL_SERVER_ERROR' to be 'UNAUTHENTICATED'
  AssertionError: expected '\u001b[31mERR\u001b[0m Error: 14 UNAV…' to contain 'mdm/product List 返回 UNAVAILABLE'
  ```
  绿：与 REST 同一张表（与 R49 的 grpc-gateway 对应关系一致）映射成 `GraphQLError`，`extensions.downstreamGrpcCode` 带状态名，记 warn；其余状态照旧掩盖。全量 `Tests  44 passed | 3 skipped (47)`。
- **Makefile 按统一目标集合重写**（`4cad7dd`，R43 的 TS 对应）：`check-version`（与 `package.json` 一致；HEAD 上的版本 tag 必须恰好是裸 `2.0.0`）、`test`、新 `test-e2e`（缺 `TEST_*` 变量点名失败）、`migrate-idempotent`（不适用）、`dag-check`（读 YAML：全部 `@2.0.0` 的 optional）、`contract-check`（新：`scripts/checkSchema.ts --against <上一个发布 tag>` 用 graphql 的 `findBreakingChanges`；找不到 tag 就失败）、`import-scan`、`module-check`、`docs-check`、`smoke`、`image`。探针：
  - contract-check 删掉 `Query.warehouses` 后对比 HEAD：`✗ 相对 HEAD 有 1 处破坏性变化：  FIELD_REMOVED: Field Query.warehouses was removed.`，exit 1（已还原）。
  - 旧 module-check 的裸 resolver 正则把 `src/resolvers/opportunity.ts:75: items: (raw.items ?? []).map(itemToDTO),` 误判为裸字段（旧 Makefile 在上一个实现者的代码上就会红）；改成与 be-acceptance `bare-route-scan` 同一判据。探针文件 `bare: async (_s: unknown) => 1,` → `✗ … src/resolvers/zz_probe.ts:2`，exit 2（已删）。
  - Dockerfile、buf.yaml、Makefile 的归档引用注释改写成原因本身。
- **`test/resolvers.test.ts`**（`deff049`）：逐个调用 Query / Mutation 根字段，确认都在鉴权前 403 失败关闭，并核对 resolver 汇总表与 `FIELD_TO_DEPENDENCY` 一一对应。一写就绿（18 条）；探针：把 `warehouses` 改成换行的裸箭头函数 → `× Query.warehouses 没有鉴权装配时失败关闭（403），不碰下游`，同时 `make module-check` 仍 `✓`（按行扫描的已知上限，正是这条测试补的）；已还原。
- 镜像探针（不经 brickkit，临时 tag，验完删除）：`docker build -t bff-mobile-c6probe:local .` exit 0；容器里 `wget`、`/app/component.yaml`、`/app/contracts/vendor/mdm/product/v1/product.proto` 在，besdk 版本 `0.4.0`。
- 4.18 `component-check.sh`（C4 末）：第 1–9 项 PASS，第 10 项（占位符）FAIL——文档还是骨架，预期。
- 4.16 `make -C $ROOT test-db-init ID=infra/bff-mobile`：`✗ infra/bff-mobile 不在有数据库的组件清单里：…`，exit 2——不连库，预期。

**C5 文档**（`90536b9`）：八份文件写满；`docs/design.md` 从归档设计文档只提取结论，并收进 `$S/assembly-removed-comments.txt` 里仍成立的四条（`tier: backend` 的理由、无 data 段、每个 resolver 一个权限键靠扫描守、不进外壳）。`contracts/schema.graphql` 只改注释（错误映射对 gRPC 同样成立；幂等键的实际语义，见现象）。首次 `make docs-check` 有 4 条 `the code map names mdm/customer, which does not exist`（Code map 第一张表里带 `/` 的行内代码被当路径）：去掉组件 ID 的反引号后 `0 with errors, 0 warnings`。

**C6 版本与门禁**

```
$ make docs-check ID=infra/bff-mobile   → 📋 Checked 2 files: 0 with errors, 0 warnings   exit=0
$ component-check.sh infra/bff-mobile   → ✅ component-check infra/bff-mobile：10 项全部 PASS   exit=0
$ migrate-manifest.py --check           → ✅ --check 全部为"无"   exit=0
$ cd $C && make check-version test contract-check import-scan module-check dag-check   → exit=0
✓ version=2.0.0（package.json 一致；HEAD 上没有 tag，或恰好是 2.0.0）
 Test Files  9 passed | 1 skipped (10)
      Tests  62 passed | 3 skipped (65)
graphql breaking --against 'v1.0.22'
✓ contracts/schema.graphql 语法合法
ℹ️  需要留意（不算破坏）：An optional argument Query.myOrders(customerId:) was added.
✓ 相对 v1.0.22 只增不改
✓ 无组件间 import
✓ 入口签名对、零 process.env、零进程级初始化、resolver 全部带权限键
✓ 7 条依赖全部是 @2.0.0 的 optional，天然无环
$ make test-db-init ID=infra/bff-mobile → 不连库，exit 2（预期）
$ project-lock.sh -- make gates        → exit=0（全文 $S/gates.log）
✓ 铁律六 import 扫描：0 条违规
✓ SystemClient 误用扫描：0 条违规
✓ 裸路由/裸 resolver 扫描：0 条违规
✓ 事件契约破坏性变更扫描：0 条违规
✓ data-scope-test-scan：0 条违规
✓ dependency-version-scan：0 条违规
⚠ config/vars.yaml:23：infra-iam-casdoor-2-0-0 对应的组件不在 brickkit.yaml 里，无法核对版本（还没装上它时是预期状态）
✓ service-hostname-scan：0 条错误（1 条警告）
⚠ components/frontend/standard/component.yaml（组件还在 1.x，…）：gatewayBaseUrl:17[naming] iamIssuerUrl:18[naming] casdoorClientId:24[naming]
✓ config-key-scan：0 条违规（另有 1 个 1.x 组件的 3 条 naming 违规只警告，…）
✓ openapi-additive-scan：0 条违规（0 条跳过提示）
▸ brickkit up --dry-run … （本组件尚未加入项目，不在列表里）
$ 锁内：be-acceptance gate config-key-scan --only infra/bff-mobile --strict → ✓ 0 条违规，exit=0
$ 锁内：be-acceptance gate openapi-additive-scan --only infra/bff-mobile   → ✓ 0 条违规（0 条跳过提示），exit=0
```
两条警告都不指向本组件（iam-casdoor 未加入项目；frontend/standard 仍是 1.x）。本组件没有 OpenAPI，`openapi-additive-scan` 对它无内容；GraphQL 契约的只增不改由组件 `contract-check` 对比 `v1.0.22` 把关。

### 现象

- 符合预期的：三个新权限键进了 `registry/permissions.tsv`；按依赖裁剪覆盖 Mutation（缺 workflow 时整个 Mutation 类型消失）；下游 401/403/404/409/400 以 `extensions.code` 透给客户端且只记 warn（R51）；`order(id)` 的 id 编码进路径。
- 上游契约核对：本组件消费的 REST 路径与字段名对照了 `infra/workflow`、`infra/notification`、`erp/inventory` 的 OpenAPI（三者工作区文件与各自 `2.0.0` tag 逐字一致）、`crm/opportunity`、`erp/sales` 的工作区 OpenAPI（未发布，C7 前复核）。
- 不符合预期的：
  1. **gRPC 下游的调用者错误被当成内部故障**（INTERNAL_SERVER_ERROR + Yoga 的 ERR 日志），已红绿修复（`189bb1b`）。
  2. **旧 module-check 的裸 resolver 正则误报**，已改成与 gates 同一判据（`4cad7dd`），并加了行为测试补按行扫描的盲区（`deff049`）。
  3. **workflow 的 REST 同意 / 驳回不认幂等键**：`POST /tasks/{id}/approve|reject` 的请求体只有 `comment`（`backend/internal/repo/actions.go`：`ApproveTask：人点"同意"。REST 面用，没有 idempotency_key：双击、重复提交由"已经不是 PENDING 就报 ErrNotPending（REST 409）"挡住`）。本组件照 brief 原样转发 `idempotency_key`（Gin `ShouldBindJSON` 忽略未知字段，无害），但下游不用它：第一次成功后重试得到 `CONFLICT` 而不是重放结果。不会重复处理。schema 注释与 design 的未决问题写明了这一点；`idempotencyKey: String!` 是否保留为必填由控制者定（见小结）。
  4. **持久化查询清单为空 → 生产镜像拒绝一切查询**，以及 `make verify ROUTE='POST /graphql'` 的不带 token 判据对本组件不成立：本机探针（`tsx src/main.ts`，临时目录，端口 18599）：
     ```
     curl -X POST → 400
     curl -X POST -H content-type:application/json -d {} → 400
     curl -X POST -H content-type:application/json -d {"query":"{__typename}"} → 400
     curl -X GET → 400
     {"errors":[{"message":"PersistedQueryOnly","extensions":{"code":"CANNOT_SEND_PQ_ID_AND_BODY"}}]}
     ```
     鉴权在 resolver 里（`requirePermission`），持久化查询检查在它之前；只有发清单里的哈希才可能拿到 401。verify 的"不带 token → 401/503""带 token → 200"两行因此会 FAIL；C7"带 token 打一次 searchProducts / warehouses / myOpportunities"也需要清单里有这些查询。见小结的待裁定项。
  5. **`test/e2e.test.ts` 已过时**：它把 gRPC 地址放进 `MDM_CUSTOMER_ENDPOINT`，而客户端读的是 `MDM_CUSTOMER_GRPC_ENDPOINT`；还会写仓库里的 `contracts/persisted-operations.json`、固定占 8500。C7 之后对真实下游跑时要按 `test/harness.ts` 的方式重写（brief：e2e 在 C7 之后跑），本轮未动。

### 卡点与绕过

- 没有读 brickKit 源码（无 V-04 知识缺口）。为了对齐门禁判据读了 `tools/be-acceptance/gates/bareginscan.go`（`scanTSBareResolver`），为确认失败关闭的状态码读了 `node_modules/besdk/dist/authz.js`（`IAM_JWKS_URL` 为空 → 403；JWKS 不可达 → 验签失败 → 401；授权包从未取到 → 503），为确认 Yoga 掩盖错误时的日志读了 `node_modules/graphql-yoga/cjs/server.js`（`maskError` 里 `this.logger.error(error)`，默认 logger 是 `@graphql-yoga/logger` 的纯文本 `ERR` 前缀）。
- 一处 shell 坑：Makefile 配方里单引号内的 `\` 续行会原样进 `node -e`（`SyntaxError: Invalid or unexpected token`），`python3 -c` 恰好吃得下；改成单行。

### V 项

- V-13（`brickkit add` 重排注释）：在 C7 的 7.1 观察，本轮未到。
- V-04：本轮无。

### 结论

C1–C6 完成：组件门禁、严格 lint、component-check 十项、`make gates`、两条发布前门禁全部通过；停在 C7 之前，等控制者确认上游与两个待裁定项。

### 反馈候选

- **be-sdk-ts：Yoga 自带 logger 不走 `rt.logger`**——被掩盖的意外错误以纯文本 `ERR …` 打到 stderr，不是结构化 JSON、没有 component_id / trace_id，日志采集按 level 过滤时会漏或误分。建议 `newGraphQLServer` 把 Yoga 的 `logging` 接到 `rt.logger`。属于项目自己的 SDK（不是 brickKit），给控制者。
- **be-sdk-ts：gRPC 状态 → GraphQL 错误码的映射在组件里各写一份**——REST 与 gRPC 两张表现在都在本组件；若以后有第二个 TS 组件，下沉到 SDK（与 Go SDK 的 grpc-gateway 表同源）。
- **verify-component.sh 的受保护路由判据不适用于只认持久化查询的 GraphQL**（见现象 4）：需要能给 ROUTE 带请求体（APQ 哈希）或由控制者为 bff-mobile 定替代判据。项目脚本，给控制者。
- 不报给 brickKit：本轮没有发现 brickKit 本身的问题。

## 小结

- 完成：C1–C6；组件仓库 17 个提交（接手后 6 个：`34ac6d4`、`55e714b`、`189bb1b`、`4cad7dd`、`deff049`、`90536b9`；接手前 11 个），未推送、未打 tag，父仓库未提交任何东西。
- C7 之前需要控制者裁定 / 确认的：
  1. 上游：erp/sales、crm/opportunity 尚无 `2.0.0` tag、未加入项目（其余五个已发布并加入）。
  2. 持久化查询清单：C7 真机打 `searchProducts` / `warehouses` / `myOpportunities` 需要清单里有这些查询。可选：组件仓库里放一份"本组件自测用"的清单进镜像，或 verify 时临时挂载一份，或等 06c 前端产出清单——由控制者定。
  3. verify 的 `ROUTE='POST /graphql'`：不带 token 实际是 `400 PersistedQueryOnly`，不是 401；"带 token → 200"同理。需要替代判据（例如带一个清单里的哈希）。
  4. `approveTask` / `rejectTask` 的 `idempotencyKey: String!`：workflow 2.0.0 的 REST 面不认它（按状态去重）。保留必填（为以后接受它的下游预留、客户端反正要生成）还是改成可选——2.0.0 尚未发布，现在改不算破坏契约。
- 遗留到 C7 / C8：重跑 1.1；`make integrate` / `make verify`（`FOCUS=1` 后把 `local.runCommand` 回写 overrides）；按 `test/harness.ts` 的方式重写 `test/e2e.test.ts` 并对真实下游跑一次；补 `$S/notes-2.0.0.md` 的"新增 / 修复"两节。

## C7–C9（第二个接手者，2026-10-02）

> 控制者确认上游后继续：mdm/customer 2.0.1、mdm/product 2.0.0、erp/inventory 2.0.0、infra/workflow 2.0.1、infra/notification 2.0.0 已发布；erp/sales、crm/opportunity 已加入项目、未发布（最终返工中）；infra/iam-casdoor、infra/authz 2.0.1 在项目里。裁定 R57：生产仍只认持久化查询；verify 用 `$S/selftest/` 下的自测清单经配置 `file://` 给；`idempotencyKey` 改可选；`make verify` 支持 `ROUTE_BODY`；e2e 按 harness 重写。

### 步骤

**1. 依赖钉版本与 SDK**（提交 `5d77795`）

- `manifest-overrides.yaml` 本组件一段加 `deps_pin: {mdm/customer: 2.0.1, infra/workflow: 2.0.1}`；`migrate-manifest.py infra/bff-mobile --write` → component.yaml 只改这两行；`--check` → `✅ --check 全部为"无"`、exit 0。notification、opportunity 早在 C3 以 `optional: true` 加入（P11）。
- `dag-check` 原来只认 `@2.0.0`，改成"钉确切 2.x.y 的 optional"；探针写成 `@2.0` → `✗ 不是钉确切 2.x.y 版本的 optional 依赖：{'id': 'mdm/product@2.0', 'optional': True}`，exit 2。
- `contracts/vendor/SOURCES.tsv`：customer.proto 的来源 tag 记成 2.0.1（`git show 2.0.1:contracts/mdm/customer/v1/customer.proto | diff - …` → 逐字节相同）。workflow 2.0.0 → 2.0.1 的 OpenAPI 只改了 `GET /tasks/{id}` 的 403/404 描述（R62：范围外也是 404），本组件把 404 当 null，不用改。
- be-sdk-ts → v0.5.0：lock 里 `resolved …#e124b9a773fa…`，与 `git -C tools/be-sdk-ts rev-list -n1 v0.5.0` 同一提交；`graphqlServer.ts` 两版相同；本组件不用数据范围。typecheck + vitest：`62 passed | 3 skipped`，与升级前一致。

**2. idempotencyKey 改可选**（提交 `c2b6a29`）

- 红：`test/workflow.test.ts` 新增两条"不给幂等键"，2 failed：
  ```
  → {"errors":[{"message":"Argument \"Mutation.approveTask(idempotencyKey:)\" of type \"String!\" is required, but it was not provided.",…,"extensions":{"code":"GRAPHQL_VALIDATION_FAILED"}}]}
  ```
  （`$S/c7-idem-red.log`）
- 绿：schema 两处 `String!` → `String`；`task.ts` 非空才放 `idempotency_key`。`64 passed | 3 skipped`；`contract-check`：`✓ 相对 v1.0.22 只增不改`。

**3. 持久化查询清单经配置给**（提交 `e7eeaef`）

组件原来只从工作目录读 `contracts/persisted-operations.json`（import 时读），没有配置键。按 R57 新增可选键 `PERSISTED_OPERATIONS_JSON`（默认空，经 overrides 的 `add_properties` 生成）：非空时它的值就是整份清单（部署时写 `file://`，平台注入文件内容），整份替换镜像里的清单、不合并；值不是"字符串到字符串"的 JSON 对象时启动失败、错误点名这个键。

- 红：`test/persistedOperations.test.ts` 6 条里 5 条失败（`$S/c7-pq-red.log`）：
  ```
  → {"errors":[{"message":"PersistedQueryNotFound","extensions":{"code":"PERSISTED_QUERY_NOT_IN_LIST"}}]}: expected [ { …(2) } ] to be undefined
  → expected { task: { id: '42', title: '待办 42' } } to be null
  AssertionError: promise resolved "{ jwks: { …(3) }, …(3) }" instead of rejecting
  ```
  "空串等于没配"一条本来就绿（护栏）。
- 绿：`70 passed | 3 skipped`。harness 加 `manifestConfig`，子进程提前退出时不再等满 15 秒。
- 文档：BRICKKIT（配置指南 + 部署前准备 + Does not own）、AGENTS（代码地图 + 易错点一行"以为它是追加"）、docs/design 中英同步。
- 小发现：`migrate-manifest.py --check` 的"代码读取了 configSchema 没声明的键"在加键之前没报（代码经常量 `MANIFEST_CONFIG_KEY` 读，不是字面量），见反馈候选。

**4. 测试竞态**（提交 `f12b9e8`，单独的测试提交，断言不变）

两份全量并行跑 6 次复现 1 次：
```
FAIL  test/grpcErrors.test.ts > gRPC 下游拒绝的透传 > List 回 authn：…
AssertionError: expected '{"level":"info",…"msg":"graphql request"}' to contain 'mdm/product List 返回 UNAUTHENTICATED'
```
子进程日志经管道异步到达，可能晚于 HTTP 响应。harness 加 `logsAfter`（等到那一行再截取，最多 5 秒），四处日志断言改用它；改后并行 6 次 6/6 绿。

**5. 自测清单**（`$S/selftest/`，不提交）

`persisted-operations.selftest.json` 收 5 个查询：searchProducts、warehouses、myOpportunities、myNotifications、task；`queries.json` 是名字 → 哈希/原文；`route-body-searchProducts.json`：
```
{"variables":{"keyword":"a"},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"d9acbe4cbccbad3dfe228f050b85214b66a92e939ce9d3da80bd0a96a4bc64f7"}}}
```
验证期间 `config/infra-bff-mobile.yaml` 临时写 `PERSISTED_OPERATIONS_JSON: file://<$S 的绝对路径>/selftest/persisted-operations.selftest.json`；`brickkit lint --strict infra/bff-mobile` → `0 with errors, 0 warnings`（项目根之外的绝对路径也认）；生成的 env 文件里 `$keyword` 写成 `$$keyword`。**验证后已恢复成 integrate 生成的原样**（`# PERSISTED_OPERATIONS_JSON: ""  # string (default)`），lint 仍 0/0。

**6. C7 integrate**（`$S/c7-integrate.log`，exit 0）

```
▸ 1. 数据库角色与密码（make dev-env db-init）
  不连库（registry/schemas.tsv 没有 infra-bff-mobile），跳过
  $ brickkit add infra/bff-mobile@2.0.0 --yes
🔗 AUTHZ_BUNDLE_URL in config/infra-bff-mobile.yaml references the variable of the same name in config/vars.yaml (--yes)
🔗 IAM_JWKS_URL in config/infra-bff-mobile.yaml references the variable of the same name in config/vars.yaml (--yes)
🔗 OTEL_BASE_URL in config/infra-bff-mobile.yaml references the variable of the same name in config/vars.yaml (--yes)
   ✅ infra/bff-mobile@2.0.0
✓ config/infra-bff-mobile.yaml：无需改动
✓ deploy.teardown.yaml 已从 deploy.yaml 同步（target、components；不带 vars:）
📋 Checked 3 files: 0 with errors, 0 warnings
   infra/bff-mobile@2.0.0 → mdm/customer@2.0.1 (optional) … → crm/opportunity@2.0.0 (optional)
✓ integrate infra/bff-mobile@2.0.0 完成
```
V-13：`brickkit.yaml` 的 diff 只有追加的组件行与版本行，没有注释被重排。

**7. C7 verify**（一次持锁里跑完 A、B 两轮 + 手工步骤 + 收尾：`$S/c7-run.sh`，日志 `$S/c7-run.log`）

命令：`ROUTE_BODY="$(cat $S/selftest/route-body-searchProducts.json)" make -C $ROOT verify ID=infra/bff-mobile ROUTE='POST /graphql' FORCE_BUILD=1 FOCUS=1`（A）；同上 `KEEP=1`（B，容器留给手工步骤）。闭包：`crm/opportunity@2.0.0 erp/inventory@2.0.0 erp/sales@2.0.0 infra/authz@2.0.1 infra/bff-mobile@2.0.0 infra/iam-casdoor@2.0.0 infra/notification@2.0.0 infra/workflow@2.0.1 mdm/customer@2.0.1 mdm/product@2.0.0`；停用 `integration/im-dingtalk infra/print erp/finance`。

verify A 汇总（`$S/verify-A/summary.md`，exit 0）：

| 检查项 | 结果 | 原因 |
|---|---|---|
| brickkit build infra/bff-mobile | PASS | |
| 镜像 infra-bff-mobile:2.0.0：sh + wget、/app/component.yaml | PASS | |
| brickkit up -f deploy.verify.yaml | PASS | |
| 迁移容器 Exited (0)（9 个） | PASS | |
| infra-bff-mobile-2-0-0 running (healthy) | PASS | |
| GET /healthz → 200 | PASS | |
| POST /graphql 不带 token → 401/503 | PASS | 实际 401 |
| POST /graphql 带 token → 200 | PASS | |
| make -C <源目录> seed | SKIP | 没设 SEED=1（本组件没有 seed） |
| make test-cross | SKIP | 不是 Go 组件 |
| focus：宿主机 http://localhost:8500/healthz → 200 | PASS | |
| brickkit up --all --dry-run（清除 focus） | PASS | |
| brickkit local off | PASS | |
| brickkit down：docker ps 里没有本项目的容器 | PASS | |

focus 日志：`infra-bff-mobile-2-0-0  listening on port 8500`——`local.runCommand`（`sh -c "npm run build && node dist/main.js"`）真机确认，overrides 的注释从"初稿"改成"真机确认"（component.yaml 不变）。verify B 同表（focus SKIP、down SKIP "KEEP=1"）。

**运行期核对**（R57 / 审查重点"含 `$` 的值被 compose 二次替换"）：`docker exec <bff> printenv PERSISTED_OPERATIONS_JSON` 与清单文件 `cmp` → `PASS 逐字节相同（928 字节，含 $keyword / $id）`。

**带 dev.superuser 的真 token 调用每个持久化查询**（容器内网 curl → `infra-bff-mobile-2-0-0:8500/graphql`；`$S/c7-manual/`、`$S/c7-manual-2/`）。不带 token 每个都是：
```
{"errors":[{"message":"缺少或格式不对的 Authorization",…,"path":["searchProducts"],"extensions":{"code":"UNAUTHENTICATED"}}],"data":null}
HTTP 401
```
带 token：
```
searchProducts keyword=a     → {"data":{"searchProducts":{"products":[],"nextCursor":""}}}  HTTP 200   （演示库 sku/名称里没有 a）
searchProducts keyword=P0000 → {"data":{"searchProducts":{"products":[{"id":"82","sku":"P000082","name":"CRM 测试产品","status":"ACTIVE","standardCost":"10.00"},…5 条],"nextCursor":"MjAyNi0xMC0wMlQxNjowMjo1NS44MjMzMzVafDc4"}}}  HTTP 200
searchProducts keyword=螺栓   → {"data":{"searchProducts":{"products":[{"id":"14","sku":"BOLT-M12","name":"「本地测试」高强度螺栓 M12","status":"ACTIVE","standardCost":"1.10"},{"id":"13","sku":"BOLT-M10",…},{"id":"1","sku":"P000001","name":"「本地测试」标准螺栓 M8","status":"ACTIVE","standardCost":"0.50"}],"nextCursor":""}}}  HTTP 200
warehouses       → {"data":{"warehouses":[{"id":"1","code":"WH-EAST","name":"华东仓","status":"ACTIVE"},{"id":"2","code":"WH-SOUTH","name":"华南仓","status":"ACTIVE"}]}}  HTTP 200
myOpportunities  → {"data":{"myOpportunities":{"opportunities":[{"id":"5","name":"「本地测试」滨海物流·已流失项目","customerName":"「本地测试」华南电子科技有限公司","stageName":"初步接洽","expectedAmount":"15000.00","status":"LOST"},…5 条],"nextCursor":""}}}  HTTP 200
myNotifications  → {"data":{"myNotifications":{"notifications":[],"nextCursor":""}}}  HTTP 200   （dev.superuser 没有通知）
task(999999999999) → {"data":{"task":null}}  HTTP 200   （workflow 404 → null）
task(2)          → {"data":{"task":{"id":"2","type":"EXCEPTION","status":"PENDING","title":"商机 dlq-test-…-redelivered 赢单自动转订单失败，需要人工介入","actions":[]}}}  HTTP 200
```
容器日志 error 级别行数 0。

**可选依赖缺席**：e2e 第二个 describe 起一个只注入 product / inventory / workflow 的真实进程（真 JWKS、真授权包、真 token）：`warehouses` 照常返回；`myNotifications`、`myOpportunities`、`customers`、`myOrders` 的持久化查询都被校验拒绝，`data` 为 null、错误 `Cannot query field "<字段>" on type "Query"`——字段根本不在 schema 里，不是注册了返回 null。

**make test-e2e**（本机子进程 → 容器 IP；必填 6 个 `TEST_*` 由持锁脚本从 `docker inspect` 与真实登录得到，token 只在变量里）：
- 第一轮：`✓ test/e2e.test.ts (10 tests)`、`Tests  10 passed (10)`。
- 第二轮（加 `TEST_SEARCH_KEYWORD=P0000`）：9 passed，"可选依赖缺席"那个进程启动失败 `listen EADDRINUSE: address already in use :::35725`——`freePort` 放掉的端口被本机出站连接的临时端口拿走。harness 改成 EADDRINUSE 时换端口重来（最多三次）。
- 第三轮（改后，同一次持锁里连跑两次）：`Tests  10 passed (10)` ×2，exit 0。
- `test/clients.test.ts` 真机（`MDM_*_GRPC_ENDPOINT` = 容器 IP，`TEST_PRODUCT_ID=82`、`TEST_CUSTOMER_ID=1`）：`Tests  3 passed (3)`。

**收尾**：第一、二轮脚本内 `brickkit down -f deploy.verify.yaml` → `剩下的本项目容器：无`、`Local mode: off`、`项目根没有 deploy.verify.yaml`。第三轮我的脚本在 H 段 `BC: unbound variable` 退出（裁剪脚本时删掉了定义 BC 的 C 段），收尾没跑、锁已释放；我立刻看了锁文件（空，没有别的持有者），在锁内补做 `brickkit down -f deploy.verify.yaml`、删文件 → 本项目容器 0 个、`Local mode: off`（`$S/c7-run3-teardown.log`）。e2e 的两次运行都在那次持锁之内完成。

**8. e2e 重写**（提交 `dcdfcbb`）：见提交说明；`Makefile` 的 `test-e2e` 必填变量改为 `TEST_TOKEN TEST_IAM_JWKS_URL TEST_AUTHZ_BUNDLE_URL TEST_MDM_PRODUCT_GRPC_ENDPOINT TEST_ERP_INVENTORY_ENDPOINT TEST_INFRA_WORKFLOW_ENDPOINT`（缺了 → `✗ 没设 … 端到端用例会全部 SKIP 而显示通过`，exit 1）。

**9. C8 门禁与交接**

- `make check-version test contract-check import-scan module-check dag-check` → exit 0：`Tests  70 passed | 12 skipped (82)`（12 = e2e 10 + clients 2，都在第 7 步真机 PASS）；`graphql breaking --against 'v1.0.22'`、`✓ 相对 v1.0.22 只增不改`。
- `make docs-check ID=infra/bff-mobile` → `0 with errors, 0 warnings`；`component-check.sh` → `10 项全部 PASS`；`migrate-manifest.py --write` 无 ⚠️（发布说明"升级前必须做"已与重新生成的一致），`--check` 全"无"。
- `make gates`（持锁）exit 0，本组件零违规；唯一警告是 frontend/standard 仍在 1.x。
- 发布前门禁（持锁）：`config-key-scan --only infra/bff-mobile --strict` 0 违规 exit 0；`openapi-additive-scan --only infra/bff-mobile --strict` 0 违规 exit 0。
- 发布说明 `$S/notes-2.0.0.md` 已补"新增 / 修复 / 其它"。
- `git -C components/infra/bff-mobile log --oneline -3`：
  ```
  dcdfcbb test: 端到端用例按 harness 重写：真实下游、真实 token、无写死端口、不碰仓库清单（R57）
  f12b9e8 test: 日志断言等日志行到达再截取（测试本身的竞态，断言不变）
  e7eeaef feat: 持久化查询清单可由配置键 PERSISTED_OPERATIONS_JSON 给出（R57）
  ```
  未推送、未打 tag；TS 组件只要 `2.0.0` 一个 tag；没有契约包。

### 卡点与绕过

- **磁盘写满**：第 4 步提交时 `OSError: [Errno 28] No space left on device`、`fatal: unable to write loose object file`，`test/harness.ts` 被截成 0 字节（tmpfs 上有提交前的副本，已恢复；`git fsck` 干净，没有丢提交）。`/` 100%：docker build cache 111GB（可回收 12.8GB）、`~/.cache/go-build` 44GB。我只删了 go-build 里 5 天以上没用过的条目（Go 自己的自动清理阈值就是 5 天，4.5GB），没动 docker。之后有别的进程又放出了空间（交接时 94%）。**控制者需要关注**：docker build cache 很大，并行工作线随时可能再写满。
- 读了 `tools/be-sdk-ts` 的 `standalone.ts`（v0.5.0）确认 createModule 抛错时进程退出；没读 brickKit 源码。`file://` 的行为查的是 `brickkit docs 01-three-layers/07-sensitive-values`。

### V 项

- V-13：`brickkit add` 没有重排 `brickkit.yaml` 的注释。
- V-04：本轮无。

### 结论

C7–C9 完成：verify 两轮全部 PASS / 写明原因的 SKIP（含 focus）；5 个持久化查询带真 token 都拿到真实数据形状；e2e 对真实下游 10/10（连续两次）；可选依赖缺席时字段不在 schema 里；`$` 穿过 env 文件后运行期逐字节相同。组件 HEAD `dcdfcbb`，等控制者审查与 `make ship`。

### 反馈候选

- **migrate-manifest.py（项目工具）**："代码读取了 configSchema 没声明的键"只认字面量键名，经常量读（`config.stringOr(MANIFEST_CONFIG_KEY, …)`）的键查不出。给控制者。
- **brickKit 文档（候选，已验证）**：`brickkit docs 01-three-layers/07-sensitive-values` 只写 `file://` 的路径相对项目根；实测 `file:///<绝对路径>`（项目根之外）lint 认、内容注入、运行期逐字节相同。属于文档没写，不是 bug；是否报给 brickKit 由控制者定。
- **测试夹具共性**（项目内）：`freePort` 先占后放的端口在有出站连接时会撞；别的 TS / Python 组件的进程级测试夹具若同样写法，同样会偶发。

## 修复轮（审查 task-20-review 之后，2026-10-02）

### 目标

按审查结论在发布前修掉 I1、M7、M1、M2：持久化查询按继承属性名查清单（I1）；`customers` / `products` 的 `ids` 不限个数（M7，移动端边界，提到发布前）；AGENTS 坑表与 `persistedOperations.ts` 注释里错误名、状态码、introspection 的说法（M1）；发布说明（M2）。版本仍是 2.0.0，未发布。

### 环境

- 组件 HEAD 起点 `dcdfcbb`；`df -h /`：53%（109G 可用）。
- 只有 base 资源在跑（be-postgres、be-nats、be-rustfs、be-casdoor、be-traefik），没有项目组件容器；`brickkit local status`：Local mode off。
- env.sh：`E=$(BE_SCRATCH=… bash dev/phase-06/tools/env.sh infra/bff-mobile) && eval "$E"`，输出 `BrickKit CLI v1.1.0；buf 在`。

### 步骤

1. **I1 红**：`test/harness.ts` 的 BffProcess 加 `post(body)`（原样发请求体）与 `graphqlUrl`；`test/persistedOperations.test.ts` 加：四个继承属性名（`__proto__`、`constructor`、`toString`、`hasOwnProperty`）不带 token POST、`constructor` 走 GET、配了 `PERSISTED_OPERATIONS_JSON` 时的 `__proto__`，都要 `PersistedQueryNotFound`、HTTP 200、没有 ERROR 日志行；带查询文本的请求（单独 / 带清单里有的哈希 / 配了配置键）一律 `PersistedQueryOnly`。`npx vitest run test/persistedOperations.test.ts`：
   ```
   AssertionError: {"errors":[{"message":"Unexpected error.","extensions":{"code":"INTERNAL_SERVER_ERROR"}}]}: expected 'Unexpected error.' to match /PersistedQueryNotFound/
   AssertionError: {"errors":[{"message":"Expected \"query\" param to be a string, but given function.","extensions":{"code":"BAD_REQUEST"}}]}: expected 'Expected "query" param to be a string…' to match /PersistedQueryNotFound/
   AssertionError: {"errors":[{"message":"Expected \"query\" param to be a string, but given function.","extensions":{"code":"BAD_REQUEST"}}]}: expected 'Expected "query" param to be a string…' to match /PersistedQueryNotFound/
   AssertionError: {"errors":[{"message":"Unexpected error.","extensions":{"code":"INTERNAL_SERVER_ERROR"}}]}: expected 'Unexpected error.' to match /PersistedQueryNotFound/
         Tests  6 failed | 8 passed (14)
   ```
   PersistedQueryOnly 的三条修复前就绿（护栏，不是红测）。为确认"没有 ERROR 日志"的断言抓得住，在修复前的代码上单独探测一次 `__proto__`：`STATUS 500 ERRLINES 2`（探测文件用完即删）。
2. **I1 绿**：`parseManifest` 读进来就转成 `Map`，查找用 `Map.get`。本文件 `Tests  14 passed (14)`；`make test`：`Tests  78 passed | 12 skipped (90)`。其它按客户端输入下标取对象的地方逐个查过（`FIELD_TO_DEPENDENCY[name]` 的 name 来自 schema 文件；`VISIBLE_STATUS` / `VISIBLE_GRPC_STATUS` 的键是下游状态码；`callUnary` 的 method 是常量；BatchGet 结果按 id 拼回用 Map），没有第二处。提交 `d00ec5d`。
3. **M7 查上游**：mdm-customer 2.0.1、mdm-product 2.0.0 的 BatchGet（`backend/internal/grpc/grpc.go` → service → repo → `besdk.BatchGetRouted`）都不限 id 个数；be-sdk-go 只在 `query.go` 给 List 设了 `maxLimit = 500`；besdk-ts 的 `createBatchGetLoader` 不传 `maxBatchSize`。没有上游上限可对齐，定 100。
4. **M7 红**：`test/batchLimit.test.ts`（两个字段各四条：恰好 100 个一次 BatchGet；101 个 BAD_USER_INPUT、桩没收到调用、没有 ERROR；没权限先 FORBIDDEN；schema 字段说明写着 100 与 BAD_USER_INPUT），harness 的 gRPC 桩抽成 mdm 通用、加 `startCustomerGrpcStub`。`src/limits.ts` 只有常量 100、resolver 未接：
   ```
   AssertionError: expected undefined to deeply equal [ 'customers' ]
   AssertionError: expected '' to contain '100'
   AssertionError: expected undefined to deeply equal [ 'products' ]
         Tests  4 failed | 4 passed (8)
   ```
5. **M7 绿**：`assertBatchIdsWithinLimit` 在权限检查之后、DataLoader 之前抛 `GraphQLError`（`extensions.code = BAD_USER_INPUT`，带 `maxIds`）；schema 两个字段加 description；BRICKKIT（中英）查询限制一行写上。本文件 `Tests  8 passed (8)`；`make test`：`Tests  86 passed | 12 skipped (98)`；contract-check `✓ 相对 v1.0.22 只增不改`。提交 `8fec592`。
6. **M1**：AGENTS（中英）第 66 行改成"带哈希回 `PersistedQueryNotFound`、带查询文本回 `PersistedQueryOnly`，HTTP 都是 200"；`persistedOperations.ts` 注释去掉"非 introspection"。测试补两条证据：查询文本那条断言 HTTP 200；introspection 查询文本也 `PersistedQueryOnly`（修改前就绿）。本文件 `Tests  15 passed (15)`。提交 `b074a1f`。
7. **M2**：`$S/notes-2.0.0.md`（改前副本 `notes-2.0.0.md.pre-fix`）：8 个已有 Query 只增不改、`myOrders` 新增可选参数；"默认 为空"→"默认为空"；修复里加 I1、M7 两行；其它里写明 be-sdk-ts v0.5.0 让空 `sub` 的 token 验签失败（`UNAUTHENTICATED`，HTTP 401；查的是 be-sdk-ts `2aaaf0f`，v0.5.0 之前放行）。`PERSISTED_OPERATIONS_JSON` 那一行没挪出"破坏性变更"小节（生成骨架里就在那，只修了空格）。
8. **门禁**（env.sh 在 PATH 上）：`make check-version test contract-check import-scan module-check dag-check` exit 0：
   ```
   ✓ version=2.0.0（package.json 一致；HEAD 上没有 tag，或恰好是 2.0.0）
    Test Files  11 passed | 1 skipped (12)
         Tests  87 passed | 12 skipped (99)
   ✓ contracts/schema.graphql 语法合法
   ℹ️  需要留意（不算破坏）：An optional argument Query.myOrders(customerId:) was added.
   ✓ 相对 v1.0.22 只增不改
   buf lint
   ✓ 无组件间 import
   ✓ 入口签名对、零 process.env、零进程级初始化、resolver 全部带权限键
   ✓ 7 条依赖全部是钉确切 2.x.y 版本的 optional，天然无环
   ```
   `bash dev/phase-06/tools/component-check.sh infra/bff-mobile`：`✅ component-check infra/bff-mobile：10 项全部 PASS`（exit 0）。`make docs-check ID=infra/bff-mobile`：`📋 Checked 3 files: 0 with errors, 0 warnings`（exit 0）。日志在 `$S/fix-*.log`。
9. **`make test-e2e`：跳过**。没有项目组件容器（只有 base 资源），真实下游不在；本轮改动不碰启动路径，按派单不做真机 verify。

### 现象

- 修复前：不带 token 发哈希 `__proto__` → HTTP 500 `Unexpected error.` + 2 条 ERROR 行；`constructor` / `toString` / `hasOwnProperty`（POST 与 GET）→ 400 `Expected "query" param to be a string, but given function.`。修复后全部 `PersistedQueryNotFound`、HTTP 200、零 ERROR 行。
- 修复前 101 个 id 照样执行（errors 为空）；修复后字段报 BAD_USER_INPUT，下游桩零调用。

### 卡点与绕过

- 第一次跑 component-check 时子 shell 里没有导出 BE_SCRATCH，env.sh 拒绝（`❌ env.sh: 请先设置 BE_SCRATCH`），导出后重跑 exit 0。不是组件问题。
- 没读 brickKit 源码。读了 mdm-customer / mdm-product 的 BatchGet 实现、tools/be-sdk-go 的 `archive.go` / `query.go`、tools/be-sdk-ts 的 `dataloader.js`、`authz.ts` 与 `2aaaf0f` 提交说明。

### 结论

I1、M7、M1、M2 修完，三个组件提交（`d00ec5d`、`8fec592`、`b074a1f`），组件 HEAD `b074a1f`，未推送、未打 tag。组件门禁、component-check、docs-check 全绿；e2e 因无容器跳过。

### 反馈候选

- **mdm-customer / mdm-product（项目内）**：BatchGet 不限 id 个数，任何调用方都能发任意大的批量读。BFF 这边已经限到 100，上游自己也该有上限（加上限对上游是行为变化，要它们各自决定、写进发布说明）。
- **be-sdk-ts（项目内）**：`createBatchGetLoader` 不收 DataLoader 选项（如 `maxBatchSize`），组件没法在合并层再兜一道上限。
