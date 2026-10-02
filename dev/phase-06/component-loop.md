# 阶段 06b · 单组件闭环清单（component-loop）

> 开发文件（`dev/`），阶段结束后归档；正式文档不得链接本文件。
> 用途：06b 重建其余 12 个后端组件（试点 mdm/customer 已发布）时，每个组件逐项照做；按 `plan-06b.md` 的 Task 执行（波次、前置、自主并行模式见该文件；plan 的"组件 Task 通用流程" C1–C9 与本清单第 1–9 步一一对应），过程记录写 `dev/test-records/06b/<repo>.md`；成员齐了的外壳走 §4 外壳组装子清单。06c 的 `frontend/standard` 也按这份清单走（第 4 步换成前端测试）。
> 工具：一次性迁移工具 `dev/phase-06/tools/`（`env.sh`、`docs-skel.sh`、`migrate-manifest.py`、`go-v2.sh`、`component-check.sh`，用法与判据全集见该目录 `README.md`），长期脚本 `make integrate / verify / ship / teardown-sync / permissions / gates`（`infra/scripts/`）。脚本做了的步骤，本清单只写命令、判据和"人还要做什么"；手工命令只保留排障需要的。
> 样板：试点 mdm/customer 2.0.0（组件仓库 HEAD `70eb317`）的 `Makefile`、`Dockerfile`、八份文档、提交切分可以照抄（见各步）；试点结论与裁定 R38–R47 在 `dev/test-records/06b/T8-pilot-review.md`。
> 规则冲突时以正式文档为准，并在过程记录里写明冲突在哪；不要按本清单硬做。

---

## 0. 怎么用

1. 开始一个组件前，把 §3 的整段清单对照着做，在 `dev/test-records/06b/<repo>.md`（模板见 §8）里记录、勾选、贴输出。本文件本身不勾。
2. 每条命令的**关键输出原文**贴进记录，不截断、不只取 `tail`（`tail -N` 曾经把真正的警告截掉过）。耗时也记。
3. 判定标准写成"通过："的条目，不满足就不往下走：先按 06-testing.md 的 [When stuck] 三步走；仍不行由控制者裁定并记录（§7）。
4. 实现者在组件仓库里只提交、不推送、不打 tag；父仓库里不提交任何东西。推送、`gen/*` tag、`brickkit release`、`v` tag、外壳视角拉取由控制者 `make ship` 完成；父仓库由控制者按路径提交并推送（§3 第 8 步）。
5. 不再有按批次的检查点；停下的唯一条件是 brickKit 严重 bug（定义见 `plan-06b.md`"执行方式"，本文件 §7）。每个组件做完第 8 步交接后，在记录里写一句检查点小结即可。
6. 跟用户的回复一律中文。

### 0.1 本清单用到的变量

每次 Bash 调用开头都先跑 plan-06b"组件 Task 通用流程"开头那三行（`ROOT`/`ID`、`BE_SCRATCH`、`env.sh`）；`BE_SCRATCH` 以 plan 里写定的路径为准（没有它 `env.sh` 和所有迁移工具都 exit 2）：

```bash
export ROOT=/home/zhijie/Desktop/github/be-assembly-standard ID=<scope>/<name>
export BE_SCRATCH=<plan 里写定的 scratchpad 路径>
E=$(bash $ROOT/dev/phase-06/tools/env.sh $ID) && eval "$E" || exit 2     # 即 eval "$(bash … env.sh $ID)"，但 env.sh 失败时不往下跑
```

⚠️ Claude Code 的 Bash 工具**不在两次调用之间保留环境变量**（工作目录保留）：每次调用都要重新跑这三行，否则 `$C`、`$S` 是空的，`cd $C` 会落到别处、`$S/…` 会写到根目录。同理，只写 `eval "$(bash … env.sh $ID)"` 时 env.sh 失败 `eval` 照样成功、后面的命令带着空变量往下跑——所以用上面带 `|| exit 2` 的写法。

`env.sh` 做的事（全部在打印之前，任一不过就 `❌` 一行、exit 2、stdout 为空，所以 `eval` 不会吃进半截输出）：

- 核对工具：PATH（追加 `~/go/bin` 之后）上 `brickkit version` 第一行恰好是 `BrickKit CLI v1.1.0`（版本取自 `infra/scripts/lib/require-brickkit.sh`，全仓只写那一处），`buf` 在；`.env` 存在且有可用的 `POSTGRES_PASSWORD` 一行（`POSTGRES_PASSWORD` 来自基础资源的 `.env`，`make dev-env` 不补它；缺了就上报控制者，不要自己编一个）。
- PATH **追加** `$HOME/go/bin`（buf、protoc-gen-go、protoc-gen-go-grpc、grpcurl 在那里），已经在 PATH 里就不再加；绝不前置（`~/go/bin/brickkit` 是旧的 v0.4.6，前置会遮住 `~/.local/bin` 的 v1.1.0）。
- 导出 `TEST_PG_DSN`（`postgres://postgres:<口令>@localhost:5432/brickkit_test_db?sslmode=disable`，口令在 eval 那一刻由 `dotenv-pgpass.py` 从 `.env` 只读 `POSTGRES_PASSWORD` 一行、URL 编码后拼出，不 source `.env`）与 `TEST_NATS_URL=nats://localhost:4222`。输出和会话记录里只有变量名，没有值；不要 `echo $TEST_PG_DSN`。
- 只读模式 `env.sh --no-tools <id>` 只给 `component-check.sh` 内部用（跳过上面的核对、不输出 `TEST_*`）；环境里残留的旧变量 `BE_ENV_NO_TOOLS` 不再生效，只打一行 ⚠️、照常核对。
- 打印并建好下面这些变量：

| 变量 | 含义 | 例（mdm/customer） |
|---|---|---|
| `ROOT` | 项目根 | `/home/zhijie/Desktop/github/be-assembly-standard` |
| `ID` | 组件 ID `<scope>/<name>` | `mdm/customer` |
| `REPO` | 仓库名、config 文件名、镜像名（`ID` 的 `/` 换成 `-`） | `mdm-customer` |
| `UREPO` | `REPO` 大写、`-` 换成 `_`（密码变量前缀） | `MDM_CUSTOMER` |
| `C` | 组件仓库（submodule）`$ROOT/components/$ID` | |
| `S` | 本组件的临时目录 `$BE_SCRATCH/06b/$REPO`，不放进仓库 | |
| `SCHEMA` / `ROLE` | `registry/schemas.tsv` 的 schema / 登录角色 | `mdm_customer` / `mdm_customer_rw` |
| `SVC` | 版本化服务名（id+版本，`/` 与 `.` 换成 `-`） | `mdm-customer-2-0-0` |
| `NET` | brickKit 生成的 Docker 网络 | `brickkit-be-assembly-standard-net` |

命令按 bash / zsh 都能跑的写法写（Claude Code 的 Bash 工具实际是 zsh：避免 `${!var}`、`echo ===` 这类只在一边成立的写法）。`SCHEMA`/`ROLE` 为空说明这个组件不连库（`infra/bff-mobile`、前端），清单里所有数据库相关的条目跳过并在记录里注明"不连库"。

### 0.2 贯穿全程的纪律（出处见括号）

- 提交信息中文、写进文件、`git commit -F <文件>`，最后一行 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`；提交后先 `git log --oneline -1` 核对（tag 由控制者在这之后打）（01-development-workflow.md#commits）。父仓库只提交自己动过的路径：`git commit -F <msg> -- <路径…>`，不 `git add -A`。
- 镜像只本地 `brickkit build`，不 push（spec §11）。新建或删除 GitHub 仓库前先告诉用户（06b 预期不需要；实现者遇到就上报控制者）。
- 组件容器默认关着：每次真机验证结束都 `brickkit down`（`make verify` 默认自己收尾）（01-development-workflow.md#running-it-for-real）。
- 不改测试去迎合实现；测试确实错了，单独一个提交并在提交信息里写明错在哪（06-testing.md）。
- 没验证过的构建机制先做最小复现再铺开（如 §3 第 8 步的 Go `/v2` 拉取复现）。
- 缺知识先查 `brickkit docs <页面>` 与 `--help`；仍答不了、不得不读 brickKit 仓库源码时，在自己的过程记录里写一条知识缺口（日期、缺的知识、在做什么、读了哪里、建议怎么下发），由控制者合并进 `to-verify.md` 的 V-04 表。实现者不改 `to-verify.md`。
- 动项目状态的命令走项目锁：`make integrate` / `verify` / `permissions` / `test-db-init` / `dev-env` / `db-init` 自己拿锁；手工命令写成 `bash infra/scripts/project-lock.sh -- <命令>`，包括 `make gates`（它写 `tools/be-acceptance/build/` 并跑 `brickkit up --dry-run`，12 条线并行时会互相踩）与任何手工 `brickkit up` / `down` / `local`。
- 不在 shell 里 source `.env`：`.env` 是 Compose 语法、不是 shell 语法，里面还有多行 PEM；测试要的连接串由 `env.sh` 给（§0.1），组件密码只由脚本在锁内读。
- 别人对"已修复"的宣称，自己复测后再当真。

---

## 1. 波次与前置

波次、前置（"上游已发布"的含义）与每个 Task 的范围见 `plan-06b.md`；本节只保留登记事实与前端接口两张表（表里的"批次"列是 06b 早期的分组，仅作索引）。V-04（知识缺口）贯穿全程。V-05、V-08 属于 06e，本清单不实测。

### 1.1 各组件的登记事实（脚本从 `registry/` 生成，见附录 A.3）

| 批次 | 组件 | 语言 | HTTP / gRPC（ports.tsv） | 外壳分组 | schema / 登录角色（schemas.tsv） | `PG_PASSWORD` 的值 |
|---|---|---|---|---|---|---|
| B1 | mdm/customer | Go | 8080 / 9090 | go-core | `mdm_customer` / `mdm_customer_rw` | `${MDM_CUSTOMER_DB_PASSWORD}` |
| B1 | mdm/product | Go | 8082 / 9092 | go-core | `mdm_product` / `mdm_product_rw` | `${MDM_PRODUCT_DB_PASSWORD}` |
| B2 | infra/authz | Go | 8223 / 9223 | go-infra | `infra_authz` / `infra_authz_rw` | `${INFRA_AUTHZ_DB_PASSWORD}` |
| B2 | infra/iam-casdoor | Go | 8200 / 9200 | go-infra | `infra_iam_casdoor` / `infra_iam_casdoor_rw` | `${INFRA_IAM_CASDOOR_DB_PASSWORD}` |
| B3 | infra/workflow | Go | 8201 / 9201 | go-infra | `infra_workflow` / `infra_workflow_rw` | `${INFRA_WORKFLOW_DB_PASSWORD}` |
| B3 | infra/notification | Go | 8202 / 9202 | go-infra | `infra_notification` / `infra_notification_rw` | `${INFRA_NOTIFICATION_DB_PASSWORD}` |
| B3 | integration/im-dingtalk | Go | 8207 / 9207 | go-infra | `integration_im_dingtalk` / `integration_im_dingtalk_rw` | `${INTEGRATION_IM_DINGTALK_DB_PASSWORD}` |
| B4 | erp/inventory | Go | 8086 / 9096 | go-core | `erp_inventory` / `erp_inventory_rw` | `${ERP_INVENTORY_DB_PASSWORD}` |
| B4 | erp/finance | Go | 8087 / 9097 | go-core | `erp_finance` / `erp_finance_rw` | `${ERP_FINANCE_DB_PASSWORD}` |
| B4 | infra/print | Python | 8400 / 9400 | py-render | `infra_print` / `infra_print_rw` | `${INFRA_PRINT_DB_PASSWORD}` |
| B5 | erp/sales | Go | 8084 / 9094 | go-core | `erp_sales` / `erp_sales_rw` | `${ERP_SALES_DB_PASSWORD}` |
| B5 | crm/opportunity | Go | 8102 / 9102 | go-backoffice | `crm_opportunity` / `crm_opportunity_rw` | `${CRM_OPPORTUNITY_DB_PASSWORD}` |
| B6 | infra/bff-mobile | TypeScript | 8500 / - | standalone | 无（不连库） | — |
| 06c | frontend/standard | Vue（前端） | 80 / - | standalone | 无（不连库） | — |

外壳自己的端口（`_shell-*` 行）：be/go-core 8090、be/go-backoffice 8116、be/go-infra 8224、be/py-render 8402。外壳登录角色 `shell_go_core` / `shell_go_backoffice` / `shell_go_infra` / `shell_py_render`，密码 `${SHELL_<NAME>_PASSWORD}`。

### 1.2 各组件在 06b 要补的前端接口（摘自 frontend-needs.md §2）

只列 06b 必做项；"可选"项本期不做，除非本 Task 另定。新权限键一律写进 `manifest-overrides.yaml` 本组件的 `permissions_add`，由 `migrate-manifest.py --write` 追加进 `assembly.yaml`（第 3.0 步，不手改），再用 `make permissions` 汇总进 `registry/permissions.tsv`（第 3.5 步）。新配置键同理走 `add_properties`。

| 组件 | frontend-needs 小节 | 06b 必做 | 新权限键 / 新配置键 |
|---|---|---|---|
| mdm/customer | §2.1 | `GET /customers` 加 `q`（匹配 code、name，大小写不敏感，前缀优先） | 无 |
| mdm/product | §2.2 | `GET /products` 加 `q`（sku、name）；gRPC `List` 也带 `q`（BFF `searchProducts` 走 gRPC）；`POST /products/{id}/status` 改绑新键 | `mdm.product.set_status`（新） |
| infra/authz | §2.9 | 无 | — |
| infra/iam-casdoor | §2.9 | 无 | — |
| infra/workflow | §2.9 | 无（确认 `GET /tasks/{id}` 返回审批历史） | — |
| infra/notification | §2.8 | `GET /preferences` 的权限键改绑 `infra.notification.view`（键名不变，只改路由绑定） | — |
| integration/im-dingtalk | — | 无（菜单问题归 06c） | — |
| erp/inventory | §2.3 | `GET /warehouses`；`GET /balances/list`（P12：列表走这条新路径，`GET /balances` 的单条语义不改，以 frontend-needs §2.3 为准）；`GET /stats/summary` | 新配置键 `LOW_STOCK_THRESHOLD`（带默认值，走 `rt.Config`） |
| erp/finance | §2.5 | `GET /ar-ledger/summary`；`ARLedgerEntry` 加 `customer_name`、`outstanding`；`GET /entries` 加 `source_doc_id`、`source_doc_type` 过滤 | — |
| infra/print | §2.7 | `GET /templates/{id}/versions`；确认 `preview` 用 `infra.print.template.edit`、`render` 用 `infra.print.render`；seed 带一份默认送货单模板 | — |
| erp/sales | §2.4 | `Order.source_opportunity_id`（由赢单消费路径写入）+ `GET /orders?source_opportunity_id=`；`GET /stats/summary` | — |
| crm/opportunity | §2.6 | `Opportunity.order_id`（事件回填，方案按 P9 先写进 `docs/design.md`）；`GET /opportunities/{id}/stage-history`；`GET /opportunities/funnel` | — |
| infra/bff-mobile | §2.10 | `task(id)`、`approveTask`/`rejectTask`（首个 Mutation）、`myNotifications`、`inventoryBalances`、`warehouses`、`searchProducts`、`myOpportunities`/`opportunity(id)`；依赖在原有 optional 依赖之外新增 `infra/notification@2.0.0`、`crm/opportunity@2.0.0`（均 `optional: true`，P11；缺席时对应字段不注册） | `infra.bff-mobile.task.act`、`infra.bff-mobile.notification.view`、`infra.bff-mobile.opportunity.view`（新） |

---

## 2. configSchema 对照表（从 14 个真实 `component.yaml` 脚本生成）

生成时间 2026-10-01，基于**重写前**的 `component.yaml`（脚本见附录 A.1、A.2）。组件重写后再跑脚本结果会变，以下表为准。

### 2.1 旧键 → 新键

规则：共享键按 04-configuration.md 的固定名（`pgSchema`→`PG_SCHEMA`、`iamJwksUrl`→`IAM_JWKS_URL`、`authzBundleUrl`→`AUTHZ_BUNDLE_URL`、`otelBaseUrl`→`OTEL_BASE_URL`）；其余驼峰键机械转大写下划线。没有一个新键以 `_ENDPOINT` 结尾，也没有撞 `COMPONENT_ID`/`COMPONENT_VERSION`/`PORT`/`BRICKKIT_SERVED_MEMBERS*`。

| 组件 | 旧版本 | 旧键 | 新键 | 旧默认值 | 旧 required | 新 secret |
|---|---|---|---|---|---|---|
| crm/opportunity | 1.0.13 | `pgSchema` | `PG_SCHEMA` | `crm_opportunity` | 否 | 否 |
| crm/opportunity | 1.0.13 | `iamJwksUrl` | `IAM_JWKS_URL` | — | 否 | 否 |
| crm/opportunity | 1.0.13 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | — | 否 | 否 |
| crm/opportunity | 1.0.13 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| crm/opportunity | 1.0.13 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |
| erp/finance | 1.0.14 | `pgSchema` | `PG_SCHEMA` | `erp_finance` | 否 | 否 |
| erp/finance | 1.0.14 | `iamJwksUrl` | `IAM_JWKS_URL` | — | 否 | 否 |
| erp/finance | 1.0.14 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | — | 否 | 否 |
| erp/finance | 1.0.14 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| erp/finance | 1.0.14 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |
| erp/inventory | 1.0.18 | `pgSchema` | `PG_SCHEMA` | `erp_inventory` | 否 | 否 |
| erp/inventory | 1.0.18 | `iamJwksUrl` | `IAM_JWKS_URL` | — | 否 | 否 |
| erp/inventory | 1.0.18 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | — | 否 | 否 |
| erp/inventory | 1.0.18 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| erp/inventory | 1.0.18 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |
| erp/sales | 1.0.26 | `pgSchema` | `PG_SCHEMA` | `erp_sales` | 否 | 否 |
| erp/sales | 1.0.26 | `iamJwksUrl` | `IAM_JWKS_URL` | — | 否 | 否 |
| erp/sales | 1.0.26 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | — | 否 | 否 |
| erp/sales | 1.0.26 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| erp/sales | 1.0.26 | `defaultWarehouseId` | `DEFAULT_WAREHOUSE_ID` | — | 是 | 否 |
| erp/sales | 1.0.26 | `exceptionAssigneeSub` | `EXCEPTION_ASSIGNEE_SUB` | `""` | 否 | 否 |
| erp/sales | 1.0.26 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |
| frontend/standard | 1.0.1 | `gatewayBaseUrl` | `GATEWAY_BASE_URL` | `/` | 否 | 否 |
| frontend/standard | 1.0.1 | `iamIssuerUrl` | `IAM_ISSUER_URL` | — | 否 | 否 |
| frontend/standard | 1.0.1 | `casdoorClientId` | `CASDOOR_CLIENT_ID` | — | 否 | 否 |
| infra/authz | 1.0.8 | `pgSchema` | `PG_SCHEMA` | `infra_authz` | 否 | 否 |
| infra/authz | 1.0.8 | `iamJwksUrl` | `IAM_JWKS_URL` | — | 否 | 否 |
| infra/authz | 1.0.8 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | — | 否 | 否 |
| infra/authz | 1.0.8 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| infra/authz | 1.0.8 | `permissionCatalog` | `PERMISSION_CATALOG` | `""` | 否 | 否 |
| infra/authz | 1.0.8 | `accessTokenTtlSeconds` | `ACCESS_TOKEN_TTL_SECONDS` | `600` | 否 | 否 |
| infra/authz | 1.0.8 | `defaultOrgId` | `DEFAULT_ORG_ID` | `1` | 否 | 否 |
| infra/authz | 1.0.8 | `bootstrapAdminSub` | `BOOTSTRAP_ADMIN_SUB` | `""` | 否 | 否 |
| infra/authz | 1.0.8 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |
| infra/bff-mobile | 1.0.22 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| infra/bff-mobile | 1.0.22 | `iamJwksUrl` | `IAM_JWKS_URL` | `""` | 否 | 否 |
| infra/bff-mobile | 1.0.22 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | `""` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `pgSchema` | `PG_SCHEMA` | `infra_iam_casdoor` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `iamJwksUrl` | `IAM_JWKS_URL` | `""` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `casdoorBaseUrl` | `CASDOOR_BASE_URL` | — | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `casdoorAdminUsername` | `CASDOOR_ADMIN_USERNAME` | `admin` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `casdoorAdminPassword` | `CASDOOR_ADMIN_PASSWORD` | — | 否 | **是** |
| infra/iam-casdoor | 1.0.10 | `casdoorOrgName` | `CASDOOR_ORG_NAME` | `brickkit` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `casdoorAppName` | `CASDOOR_APP_NAME` | `brickkit-app` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `webhookSharedSecret` | `WEBHOOK_SHARED_SECRET` | — | 否 | **是** |
| infra/iam-casdoor | 1.0.10 | `webhookCallbackUrl` | `WEBHOOK_CALLBACK_URL` | `""` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `appTokenSigningKeyPem` | `APP_TOKEN_SIGNING_KEY_PEM` | — | 否 | **是** |
| infra/iam-casdoor | 1.0.10 | `appTokenPreviousPublicKeyPem` | `APP_TOKEN_PREVIOUS_PUBLIC_KEY_PEM` | `""` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `appTokenTtlSeconds` | `APP_TOKEN_TTL_SECONDS` | `600` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `refreshTokenTtlSeconds` | `REFRESH_TOKEN_TTL_SECONDS` | `604800` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `enabledComponents` | `ENABLED_COMPONENTS` | `""` | 否 | 否 |
| infra/iam-casdoor | 1.0.10 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |
| infra/notification | 1.0.4 | `pgSchema` | `PG_SCHEMA` | `infra_notification` | 否 | 否 |
| infra/notification | 1.0.4 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| infra/notification | 1.0.4 | `iamJwksUrl` | `IAM_JWKS_URL` | `""` | 否 | 否 |
| infra/notification | 1.0.4 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | `""` | 否 | 否 |
| infra/notification | 1.0.4 | `imTargetAdapters` | `IM_TARGET_ADAPTERS` | `dingtalk` | 否 | 否 |
| infra/notification | 1.0.4 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |
| infra/print | 1.0.8 | `pgSchema` | `PG_SCHEMA` | `infra_print` | 否 | 否 |
| infra/print | 1.0.8 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| infra/print | 1.0.8 | `iamJwksUrl` | `IAM_JWKS_URL` | `""` | 否 | 否 |
| infra/print | 1.0.8 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | `""` | 否 | 否 |
| infra/print | 1.0.8 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |
| infra/workflow | 1.0.4 | `pgSchema` | `PG_SCHEMA` | `infra_workflow` | 否 | 否 |
| infra/workflow | 1.0.4 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| infra/workflow | 1.0.4 | `iamJwksUrl` | `IAM_JWKS_URL` | `""` | 否 | 否 |
| infra/workflow | 1.0.4 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | `""` | 否 | 否 |
| infra/workflow | 1.0.4 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |
| integration/im-dingtalk | 1.0.5 | `pgSchema` | `PG_SCHEMA` | `integration_im_dingtalk` | 否 | 否 |
| integration/im-dingtalk | 1.0.5 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| integration/im-dingtalk | 1.0.5 | `iamJwksUrl` | `IAM_JWKS_URL` | `""` | 否 | 否 |
| integration/im-dingtalk | 1.0.5 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | `""` | 否 | 否 |
| integration/im-dingtalk | 1.0.5 | `dingtalkBaseUrl` | `DINGTALK_BASE_URL` | `https://oapi.dingtalk.com` | 否 | 否 |
| integration/im-dingtalk | 1.0.5 | `dingtalkAppKey` | `DINGTALK_APP_KEY` | — | 是 | 否 |
| integration/im-dingtalk | 1.0.5 | `dingtalkAppSecret` | `DINGTALK_APP_SECRET` | — | 是 | **是** |
| integration/im-dingtalk | 1.0.5 | `dingtalkAgentId` | `DINGTALK_AGENT_ID` | — | 是 | 否 |
| integration/im-dingtalk | 1.0.5 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |
| mdm/customer | 1.0.10 | `pgSchema` | `PG_SCHEMA` | `mdm_customer` | 否 | 否 |
| mdm/customer | 1.0.10 | `iamJwksUrl` | `IAM_JWKS_URL` | — | 否 | 否 |
| mdm/customer | 1.0.10 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | — | 否 | 否 |
| mdm/customer | 1.0.10 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| mdm/customer | 1.0.10 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |
| mdm/product | 1.0.11 | `pgSchema` | `PG_SCHEMA` | `mdm_product` | 否 | 否 |
| mdm/product | 1.0.11 | `iamJwksUrl` | `IAM_JWKS_URL` | — | 否 | 否 |
| mdm/product | 1.0.11 | `authzBundleUrl` | `AUTHZ_BUNDLE_URL` | — | 否 | 否 |
| mdm/product | 1.0.11 | `otelBaseUrl` | `OTEL_BASE_URL` | `""` | 否 | 否 |
| mdm/product | 1.0.11 | `resources: database,mq` | 删除；改为声明 `PG_*` + `NATS_URL` | — | — | — |

谁在读这些键（附录 A 的 `usage.py` 扫过各组件代码）：

- `pgSchema` 与各组件自有键（`defaultWarehouseId`、`permissionCatalog`、`casdoor*`、`dingtalk*`、`imTargetAdapters` 等）只在各组件的 `backend/module/module.go`（Python：`backend/app/module.py`）里读，改名时改这一个文件。
- `iamJwksUrl`、`authzBundleUrl`、`otelBaseUrl` 在组件代码里**一处也没有**：它们由 SDK 的 `RunStandalone` / `run_standalone` 读。新 SDK（be-sdk-go v0.3.0、be-sdk-python v0.4.x、be-sdk-ts v0.4.0）读的是 `IAM_JWKS_URL`、`AUTHZ_BUNDLE_URL`、`OTEL_BASE_URL`；升级 SDK 就改到了。
- 迁移入口（`backend/cmd/migrate/main.go`、`backend/app/migrate.py`）读的是平台旧注入的 `DATABASE_HOST/PORT/USER/PASSWORD/NAME`，v1 不再注入，必须改成 `PG_*`（第 4 步）。
- `frontend/standard` 的 `docker-entrypoint.sh` 早就读 `GATEWAY_BASE_URL`、`IAM_ISSUER_URL`、`CASDOOR_CLIENT_ID`（旧平台的驼峰→下划线转换结果），改键名后脚本不用动。

### 2.2 每个组件重写后的目标形态

推导规则（§2.3）作用在旧文件上的结果。"新 required" 一栏里的键在 `configSchema` 里**不写 `default`**。唯一的手工调整：`PERMISSION_CATALOG`（authz）与 `ENABLED_COMPONENTS`（iam-casdoor）按控制者裁定 R27 从"默认空串"改成 required，理由见 §2.5。

| 组件 | 依赖（全部改成 `@2.0.0`） | 新 required | 带默认值的键 | secret | `PG_SCHEMA` 默认值核对 | 删除的旧字段 |
|---|---|---|---|---|---|---|
| crm/opportunity | mdm/customer、mdm/product | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL` | `PG_PORT=5432`<br>`PG_SCHEMA=crm_opportunity`<br>`OTEL_BASE_URL=""` | `PG_PASSWORD` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |
| erp/finance | — | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL` | `PG_PORT=5432`<br>`PG_SCHEMA=erp_finance`<br>`OTEL_BASE_URL=""` | `PG_PASSWORD` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |
| erp/inventory | — | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL` | `PG_PORT=5432`<br>`PG_SCHEMA=erp_inventory`<br>`OTEL_BASE_URL=""`（另加 `LOW_STOCK_THRESHOLD`，§1.2） | `PG_PASSWORD` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |
| erp/sales | mdm/customer、mdm/product、erp/inventory、erp/finance、infra/workflow（optional） | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL`<br>`DEFAULT_WAREHOUSE_ID` | `PG_PORT=5432`<br>`PG_SCHEMA=erp_sales`<br>`OTEL_BASE_URL=""`<br>`EXCEPTION_ASSIGNEE_SUB=""` | `PG_PASSWORD` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |
| frontend/standard | — | `IAM_ISSUER_URL`<br>`CASDOOR_CLIENT_ID` | `GATEWAY_BASE_URL=/` | — | — | `deployment.image`（改 `deployment.build`） |
| infra/authz | — | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL`<br>`PERMISSION_CATALOG`（R27，见 §2.5） | `PG_PORT=5432`<br>`PG_SCHEMA=infra_authz`<br>`OTEL_BASE_URL=""`<br>`ACCESS_TOKEN_TTL_SECONDS=600`<br>`DEFAULT_ORG_ID=1`<br>`BOOTSTRAP_ADMIN_SUB=""` | `PG_PASSWORD` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |
| infra/bff-mobile | mdm/customer（optional）、mdm/product（optional）、erp/sales（optional）、erp/inventory（optional）、infra/workflow（optional）、infra/notification（optional，P11）、crm/opportunity（optional，P11） | `IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL` | `OTEL_BASE_URL=""` | — | — | `deployment.image`（改 `deployment.build`） |
| infra/iam-casdoor | infra/authz | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`CASDOOR_BASE_URL`<br>`CASDOOR_ADMIN_PASSWORD`<br>`WEBHOOK_SHARED_SECRET`<br>`APP_TOKEN_SIGNING_KEY_PEM`<br>`ENABLED_COMPONENTS`（R27，见 §2.5） | `PG_PORT=5432`<br>`PG_SCHEMA=infra_iam_casdoor`<br>`OTEL_BASE_URL=""`<br>`CASDOOR_ADMIN_USERNAME=admin`<br>`CASDOOR_ORG_NAME=brickkit`<br>`CASDOOR_APP_NAME=brickkit-app`<br>`WEBHOOK_CALLBACK_URL=""`<br>`APP_TOKEN_PREVIOUS_PUBLIC_KEY_PEM=""`<br>`APP_TOKEN_TTL_SECONDS=600`<br>`REFRESH_TOKEN_TTL_SECONDS=604800` | `PG_PASSWORD`<br>`CASDOOR_ADMIN_PASSWORD`<br>`WEBHOOK_SHARED_SECRET`<br>`APP_TOKEN_SIGNING_KEY_PEM` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |
| infra/notification | — | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL` | `PG_PORT=5432`<br>`PG_SCHEMA=infra_notification`<br>`OTEL_BASE_URL=""`<br>`IM_TARGET_ADAPTERS=dingtalk` | `PG_PASSWORD` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |
| infra/print | — | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL` | `PG_PORT=5432`<br>`PG_SCHEMA=infra_print`<br>`OTEL_BASE_URL=""` | `PG_PASSWORD` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |
| infra/workflow | — | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL` | `PG_PORT=5432`<br>`PG_SCHEMA=infra_workflow`<br>`OTEL_BASE_URL=""` | `PG_PASSWORD` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |
| integration/im-dingtalk | — | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL`<br>`DINGTALK_APP_KEY`<br>`DINGTALK_APP_SECRET`<br>`DINGTALK_AGENT_ID` | `PG_PORT=5432`<br>`PG_SCHEMA=integration_im_dingtalk`<br>`OTEL_BASE_URL=""`<br>`DINGTALK_BASE_URL=https://oapi.dingtalk.com` | `PG_PASSWORD`<br>`DINGTALK_APP_SECRET` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |
| mdm/customer | — | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL` | `PG_PORT=5432`<br>`PG_SCHEMA=mdm_customer`<br>`OTEL_BASE_URL=""` | `PG_PASSWORD` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |
| mdm/product | — | `PG_HOST`<br>`PG_DATABASE`<br>`PG_USER`<br>`PG_PASSWORD`<br>`NATS_URL`<br>`IAM_JWKS_URL`<br>`AUTHZ_BUNDLE_URL` | `PG_PORT=5432`<br>`PG_SCHEMA=mdm_product`<br>`OTEL_BASE_URL=""` | `PG_PASSWORD` | 一致 | `dependencies.resources`<br>`deployment.image`（改 `deployment.build`） |

### 2.3 推导规则（表外的新键也照这个写）

1. **连库组件**（旧 `resources` 有 `database`）声明 `PG_HOST`、`PG_PORT`（`default: "5432"`，字符串）、`PG_DATABASE`、`PG_USER`、`PG_PASSWORD`（`secret: true`）、`PG_SCHEMA`（`default:` = `schemas.tsv` 的 schema 列）。旧 `resources` 有 `mq` 的再声明 `NATS_URL`。be-sdk-go 的 `RunStandalone` 对 PG 与 NATS 都是硬要求（缺键直接退出），所以这些键进 `required`。不用对象存储的组件不声明 `S3_URL`（目前 14 个组件都不用）。
2. **没有 `default` 的键一律进 `required`**（brickkit-component skill 规则 2：项目必须提供的键不给默认值，`add` 会写成 `KEY: ""`，`up` 在填好之前拒绝启动）。旧 schema 里 `iamJwksUrl`/`authzBundleUrl` 有的写了 `default: ""`、有的没写——统一改成 required、不给默认值（理由：没有它们，受保护路由一律 403/503，不是一个能工作的默认状态）。⚠️ 这是试点拍板项 P1（§6.2）。
3. **`secret: true`**：`PG_PASSWORD`，以及键名含 `Password`/`Secret`/`SigningKey` 的（`CASDOOR_ADMIN_PASSWORD`、`WEBHOOK_SHARED_SECRET`、`APP_TOKEN_SIGNING_KEY_PEM`、`DINGTALK_APP_SECRET`）。`DINGTALK_APP_KEY`、`CASDOOR_CLIENT_ID` 是标识不是密钥，不标。
4. **`type` / `enum` 等只是文档**；整数默认值照旧写成数字（`600`），`brickkit` 原样注入字符串。`configSchema` 属性里不写 `description`：每个键的含义写在 `BRICKKIT.md` 的 Configuration 一节（一个事实一个家）。
5. **密钥的变量名**（P7 最终规则）：组件自有密钥在 `config/<repo>.yaml` 里写成 `${<UREPO>_<KEY>}`（例如 `${INFRA_IAM_CASDOOR_WEBHOOK_SHARED_SECRET}`），与 `${<UREPO>_DB_PASSWORD}` 同一前缀，避免 `.env` 里不同组件的同名键撞车；属于基础资源的密钥沿用基础资源已有的变量名（例如 iam-casdoor 的 `CASDOOR_ADMIN_PASSWORD: ${CASDOOR_ADMIN_PASSWORD}`）。
6. **多行密钥**（`APP_TOKEN_SIGNING_KEY_PEM`）用 `file://.secrets/<repo>/<文件>`，不塞进 `.env`。进外壳后它会被编码进 `BRICKKIT_SERVED_MEMBERS_CONFIG` 的 JSON，而 compose 运行期还会对生成文件再做一次 `${VAR}` 文本替换——必须在运行期（`docker exec … env`、成员日志）确认值完整，只看 `--dry-run` 不算数。

### 2.4 `config/<repo>.yaml` 的标准写法

`brickkit add` 写出的骨架：required 键是 `KEY: ""`，其余键是注释行。按 04-configuration.md 的"值从哪来"一栏填（共享值即使组件有默认值也显式写 `$var:`，这样换环境时 deploy 文件的 `vars:` 能覆盖到它）。**这一步由 `infra/scripts/config-fill.py` 按此规则填写**（`make integrate` 会调用；需要人给值的 required 键它会列出并以退出码 3 失败，再用 `--set KEY=VALUE` 补）：

```yaml
# config/mdm-customer.yaml（以 mdm/customer 为例；$var: 与名字之间没有空格）
PG_HOST: $var:PG_HOST
PG_PORT: $var:PG_PORT
PG_DATABASE: $var:PG_DATABASE
PG_USER: mdm_customer_rw                 # schemas.tsv 的 role 列，字面量
PG_PASSWORD: ${MDM_CUSTOMER_DB_PASSWORD} # .env 里由 make dev-env 补齐
PG_SCHEMA: mdm_customer                  # schemas.tsv 的 schema 列，字面量
NATS_URL: $var:NATS_URL
OTEL_BASE_URL: $var:OTEL_BASE_URL
AUTHZ_BUNDLE_URL: $var:AUTHZ_BUNDLE_URL
IAM_JWKS_URL: $var:IAM_JWKS_URL
```

组件自有键：只有"组件的默认值在本项目里就是对的"那些键才保持注释（跟随组件默认，升级时新默认值能到达）；凡是本项目必须给出真实内容的键——权限目录、已装组件清单、首个管理员（§2.5）、`DEFAULT_WAREHOUSE_ID` 这类——一律显式写出（字面量、`${…}` 或 `file://`），并且在 `configSchema` 里不给默认值、进 `required`，这样漏填时 `up` 会拒绝启动，而不是带着空值悄悄跑起来。`config/vars.yaml` 里的 `AUTHZ_BUNDLE_URL`/`IAM_JWKS_URL` 用成员自己的服务名（`http://infra-authz-2-0-0:8223/authz/bundle`、`http://infra-iam-casdoor-2-0-0:8200/.well-known/jwks.json`，R29/R30）：独立部署、进外壳（外壳容器的网络别名）、拆回验证都能解析，任何部署文件都不用 `vars:` 覆盖；只在 authz/iam 发版时改，`make gates`（`service-hostname-scan`）核对。authz/iam 还没加入项目时的预期见附录 B。

### 2.5 由项目内容决定的配置值（authz / iam-casdoor；控制者裁定 R27）

这三个键的值不是常量，而是"项目里有什么"。旧项目在 `brickkit.yaml` 里手写长字面量（`permissionCatalog` 一长串、`enabledComponents` 一串组件 ID），曾经漏同步过。v1 下的原则：**直接引用唯一的真相源，不另设需要"记得重新生成"的副本**。

| 键 | 组件 | 值 | 真相源 | 要改组件的什么 | 什么时候值会变、怎么生效 |
|---|---|---|---|---|---|
| `PERMISSION_CATALOG` | infra/authz | `file://registry/permissions.tsv` | `registry/permissions.tsv`（第 3.5 步用 be-ops 追加新键） | 解析器（`backend/internal/service/catalog.go` 的 `ParsePermissionCatalog`）现在只认 `key\|title\|type\|owner_component,…` 一行逗号串。改成解析 TSV：按行切；跳过空行、`#` 开头的行和表头行（第一列是 `key`）；按制表符切，至少 4 列（`key`、`title`、`type`、`owner_component`），第 5 列 `deprecated` 可空；`key` 为空报错并给出行号。**`deprecated` 非空的行也要同步**（已授出的旧键必须仍能在 `permissions` 表里解析到；同步本来就是 upsert、不删行）。旧的逗号格式不再支持（2.0.0 的发布说明写明"键的含义变了"）。先写 L2 测试（真实 TSV 片段，含中文标题、表头、`deprecated` 行）跑红，再改实现 | 新权限键进 `permissions.tsv` 后，下一次 `brickkit up` 生成时重新读文件，authz 容器（或 go-infra 外壳）因环境变化被重建，`Start()` 重新同步目录。不需要任何"再生成"步骤 |
| `ENABLED_COMPONENTS` | infra/iam-casdoor | `file://brickkit.yaml` | 项目的 `brickkit.yaml`（`brickkit add`/`remove`/`upgrade` 维护） | 现在按逗号切 `enabledComponents`（`module.go` 的 `splitNonEmpty`）。改成解析 YAML：取 `components[].id`，跳过 `kind: shell` 的条目，去重（同一 ID 的 `requiredBy` 兼容版本只算一次），保持稳定排序。yaml.v3 已在依赖树里。L2 测试用真实形态的 `brickkit.yaml`（含外壳条目与 `requiredBy` 行）。BRICKKIT.md 写明"值是项目 `brickkit.yaml` 的内容"，别的项目同样用 `file://brickkit.yaml`。代价：iam-casdoor 因此依赖 brickKit 锁文件的格式（`components[].id`、`kind`）；备选是 be-ops 生成一个组件清单文件再 `file://` 引用，但那样多一个"每次 add/remove 后记得重新生成"的步骤，正是 R27 要消除的。落地前由 authz/iam-casdoor 的 Task 确认取哪种 | 每次 `brickkit add`/`remove` 之后的下一次 `up` 自动生效 |
| `BOOTSTRAP_ADMIN_SUB` | infra/authz | `${INFRA_AUTHZ_BOOTSTRAP_ADMIN_SUB:-}` | 部署者本人在 IAM 里的 `sub`（[0303]）；本地开发是 seed 账号 `dev.superuser` 的 `sub` | 无（键名已由 0303 定为 `BOOTSTRAP_ADMIN_SUB`）。保留 `default: ""`——空表示"首个管理员手工授权"，是合法状态 | 本地：iam-casdoor 的 `make seed` 建好 `dev.superuser` 之后，用 `source infra/scripts/lib/seed-net.sh` 里的 `sub_of dev.superuser` 查出 `sub`，写进 `.env` 的 `INFRA_AUTHZ_BOOTSTRAP_ADMIN_SUB=`，再 `brickkit up` 让 authz 重启授权。authz 的 `scripts/seed.sh` 第 ① 步目前因为"没配 bootstrapAdminSub"直接写库建全权限角色——配上之后这一步能不能改走 admin API，iam-casdoor 的 Task 顺带评估，不强求 |

要点与判据（写进 authz、iam-casdoor 两个组件的第 4、7 步）：

- `PERMISSION_CATALOG`、`ENABLED_COMPONENTS` 在 `configSchema` 里是 **required、不给默认值**（§2.2 已调整）：`brickkit add` 会把它们写成 `KEY: ""`，`up` 在填好之前拒绝启动——不可能因为"可选键保持注释"而悄悄变空。
- `file://` 的路径相对项目根目录；`brickkit lint --strict` 会检查文件存在。值是多行、带制表符的文本，会进 compose 文件、进 `BRICKKIT_SERVED_MEMBERS_CONFIG` 的 JSON，compose 运行期还会对生成文件做 `${VAR}` 文本替换（标题里将来出现 `$` 就会被吃掉）。所以判据在运行期：
  ```bash
  docker exec <authz 容器或 go-infra 外壳> sh -c 'printf %s "$PERMISSION_CATALOG" | wc -l'     # 独立部署时；外壳里看 BRICKKIT_SERVED_MEMBERS_CONFIG 里 infra/authz 那一项
  wc -l < registry/permissions.tsv
  docker exec be-postgres psql -U postgres -d brickkit_db -tAc "select count(*) from infra_authz.permissions"
  ```
  通过：前两个行数一致（最后一行有无换行可差 1，原文记录）；`permissions` 表行数 ≥ TSV 数据行数；authz 日志没有"同步权限目录失败"。`ENABLED_COMPONENTS` 同理：`GET /api/tenant/features` 返回的组件集合等于 `brickkit.yaml` 里非外壳的组件 ID 集合。
- 第 3.5 步追加新权限键之后，"让 authz 看到新键"只需要下一次 `brickkit up`；在全栈集成（T25）里核对新键出现在 `infra_authz.permissions` 里。

---

## 3. 单组件闭环（每个组件对照这一节做，记进过程记录）

### 第 1 步　前置检查（pre-flight）

- [ ] **1.1 上游已就位**。本组件的每个依赖都已是 2.0.0 且已加入项目：
  ```bash
  cd $ROOT && python3 - "$C/component.yaml" <<'EOF'
  import sys, yaml
  m = yaml.safe_load(open(sys.argv[1])); bk = yaml.safe_load(open('brickkit.yaml'))
  have = {c['id']: c['version'] for c in bk.get('components') or []}
  for d in (m.get('dependencies') or {}).get('components') or []:
      dep = (d['id'] if isinstance(d, dict) else d).split('@')[0]
      print(f"{dep:28s} 项目里：{have.get(dep, '缺')}")
  EOF
  ```
  再确认每个上游都"已发布"（plan C1）：
  ```bash
  git -C $ROOT/components/<上游> ls-remote --tags origin 2.0.0      # 有一行
  git -C $ROOT/components/<上游> ls-remote --tags origin v2.0.0     # Go 上游：也有一行
  ```
  通过：每个依赖都是 `2.0.0`，且两条 `ls-remote` 都各有一行（Go 上游；Python / TS 上游只有 `2.0.0`）；optional 依赖可以缺，记录里写明缺哪个、组件会怎样降级。W2 / W3 提前开工（plan-06b"W2"一节：T17–T20 的 C1–C6 在 T8 之后即可开始）时，上游还没发布、还没加入项目是预期状态：这两条在记录里写"待 C7 前复核"，不挡 C1–C6；C7 之前重跑本条，必须通过。
- [ ] **1.2 组件仓库干净、与远端一致、tag 在本地**：`git -C $C status -sb` 第一行是 `## main...origin/main`，后面没有 `[ahead`/`[behind`，下面没有文件行。不干净就不动它，在记录里写明并上报控制者裁定（可能是别人的半成品）。`git -C $C fetch --tags && git -C $C tag -l '1.*' 'v1.*' | sort -V | tail -1` 有一行（最后一个 1.x tag）：`docs-skel.sh`、`migrate-manifest.py` 的输入取自它，组件 `contract-check` 与 `openapi-additive-scan` 也拿它当基线——本地没有 tag 时它们会失败或悄悄对比 `main`。
- [ ] **1.3 基础资源在跑**：`make check` 全绿（PostgreSQL、NATS、Casdoor 等）。不要 `make up` 重启已在跑的资源。
- [ ] **1.4 工具版本**：§0.1 的两行（`env.sh`）没有 exit 2 就说明 PATH（`export PATH=$PATH:$HOME/go/bin`，追加）、`brickkit` v1.1.0、`buf`、测试库变量都齐了；stderr 那行 `ℹ️ env.sh：BrickKit CLI v1.1.0（/home/zhijie/.local/bin/brickkit）；buf 在；…` 原文贴进记录。exit 2 时按 `❌` 那行处理：PATH 上的 brickkit 不对就是 `~/go/bin` 被前置了（改成追加）；`buf` 不在就上报控制者，不要自己另装；`~/go/bin/brickkit` 删不删由用户定，不要自己删。另核对 `command -v protoc-gen-go` 是 `~/go/bin/protoc-gen-go`（系统里另装的版本排在前面时，`go-v2.sh` 的 gen 判据会对每个组件都 FAIL，见 4.4）。SDK 版本：be-sdk-go v0.4.0、be-sdk-python v0.4.4、be-sdk-ts v0.4.0（核对：`git -C $ROOT/tools/<sdk> describe --tags --abbrev=0`）。Python 组件的 besdk 版本必须与 `shell/be/py-render/pyproject.toml` 里钉的是同一个 tag（pip 不接受同一个 git 依赖出现两个 tag）。
- [ ] **1.5 读这些，按顺序**（不读依赖方源码、不读 brickKit 仓库）：
  1. `$C/AGENTS.md`、`$C/README.md`、`$C/docs/手册.md`（旧四件套，第 5 步要从中提取仍成立的结论）；
  2. `$ROOT/archive/pre-v1/docs/dev/design/$REPO.md`（旧设计文档，`docs/design.md` 的来源）；
  3. `$C/component.yaml`、`$C/assembly.yaml`、`$C/Makefile`、`$C/Dockerfile`；
  4. 本文件 §1.2 中本组件那一行，以及 frontend-needs.md 对应小节；
  5. 规则：04-configuration.md（全篇）、02-backend.md 的 [Module entry]/[The runtime is the only way in]/[Database]/[Calling other components]、06-testing.md、08-documentation.md 的 [Component documents]；
  6. 样板（只看结构与写法，不抄事实）：`$ROOT/components/mdm/customer` 的 `Makefile`、`Dockerfile`、`BRICKKIT.md`、`AGENTS.md`、`docs/design.md`；工具用法 `$ROOT/dev/phase-06/tools/README.md`。
- [ ] **1.6 现有数据的属主**（迁移会以 `$ROLE` 身份跑，不再是 postgres 超级用户）：
  ```bash
  docker exec be-postgres psql -U postgres -d brickkit_db -tAc \
    "select tableowner, count(*) from pg_tables where schemaname='$SCHEMA' group by 1"
  ```
  记下结果。如果表属主是 `postgres`，而本组件这次要加 `ALTER TABLE` 类迁移（§1.2 里要给已有表加字段的：sales、finance、opportunity 等）：以 `$ROLE` 跑的迁移会报 `must be owner of table`，出路是用项目的数据库重置脚本重建演示库（Task 5）；由控制者裁定并记录，不在组件里绕过。结果为空 = 演示库里还没有本组件的表（迁移会以 `$ROLE` 建表，属主天然正确），记"空"，跳过本条后半。
- [ ] **1.7 本组件要实测的 V 项**：查 §6.1 表与本 Task；在记录里先写好 V 项小节标题。
- [ ] **1.8 开记录**：新建 `dev/test-records/06b/$REPO.md`，按 §8 模板写上目标与环境。

### 第 2 步　拿 v1 骨架，替换文档

- [ ] **2.1 骨架与文档骨架**（plan C2）：
  ```bash
  bash $ROOT/dev/phase-06/tools/docs-skel.sh $ID; echo "exit=$?"
  git -C $C rm -q docs/手册.md 2>/dev/null; (cd $C && brickkit skills update)     # 脚本不做这两步
  ```
  脚本做的：`brickkit new $ID --path $S/skel`（核对骨架五个文件、`CLAUDE.md` 是 `@AGENTS.md`、`AGENTS.md` 有维护块）；把旧的 `AGENTS.md README.md CLAUDE.md docs/手册.md component.yaml assembly.yaml Makefile Dockerfile` 从**最后一个 1.x tag** 留底到 `$S/old/`（与工作区、会话无关）；写出 `BRICKKIT.md`、`AGENTS.md`、`README.md`（后两个加首行互链）及三个 `.zh.md`（固定中文标题）、`docs/design.md` + `.zh.md`（5.1 的十个小节）、`CLAUDE.md`（恰好 `@AGENTS.md`）。已填写过的文件不覆盖（`--force` 才覆盖），换会话重跑也安全。
  通过：`exit=0`；`$C` 下九个文件都在；`skills update` 输出 `📦 Component repository …`、写入 `.claude/skills/brickkit-component/SKILL.md`，`AGENTS.md` 末尾有 `<!-- brickkit:managed:begin lang=en -->` 块（P6：提交这个 skill 目录，独立 clone 时 AI 才读得到维护块里引用的那份 skill）。
- [ ] **2.2 去向**：`component.yaml`、`assembly.yaml` 第 3 步由脚本重写；`docs/手册.md` 的内容分流进 `AGENTS.md`（代码地图、构建测试）和 `docs/design.md`（设计结论），原文在 `$S/old/`；代码、`contracts/`、`migrations/`、`gen/`、`scripts/`、`Dockerfile`、`Makefile` 保留，第 4 步按需修改。骨架里的 `TODO` 会被 lint 报 `DOC_PLACEHOLDER`，第 5 步填。

### 第 3 步　重写 `component.yaml` 与 `assembly.yaml`

- [ ] **3.0 一条命令重写两份清单**（plan C3；要 `BE_SCRATCH`，没设就在写任何文件之前 exit 2）：
  ```bash
  python3 $ROOT/dev/phase-06/tools/migrate-manifest.py $ID           # 先预览：两份文件全文 + diff + 代码改动，不写盘
  python3 $ROOT/dev/phase-06/tools/migrate-manifest.py $ID --write; echo "exit=$?"
  python3 $ROOT/dev/phase-06/tools/migrate-manifest.py $ID --check; echo "exit=$?"
  ```
  输入是组件最后一个 1.x tag 上的两份文件 + `dev/phase-06/tools/manifest-overrides.yaml` 里本组件的条目，所以重跑结果相同。`--write` 做的：
  - `component.yaml` 整份重写成 3.1 的版式（§2.2 那一行的键、依赖 `@2.0.0`、`deployment.build`、`local`、英文名称与描述）；代码里旧键的 SDK 读法改成新键，逐处打印 `文件:行: "旧" → "新"`；字符串和注释里残留的旧键名只用 `ℹ️` 列出，要不要改由人判断。
  - `assembly.yaml` 按 3.4 删改，并**去掉注释里的归档 / 历史引用**（"设计书 §x""阶段 X""Task N""docs/plans/"…），去掉的每一行写进 `$S/assembly-removed-comments.txt`（`删  原文` / `改  原文 → 现在`）；第 5 步照这份清单把仍成立的结论（不带出处）写进 `docs/design.md`。**不要再手工清这些注释**（手清就是手改，下一次 `--write` 会 exit 3）。
  - 发布说明骨架（8.1）：每次都重写 `$S/notes-2.0.0.generated.md`；`$S/notes-2.0.0.md` 只在不存在时写一次，之后不覆盖（人补的"新增 / 修复"不会被冲掉）。已存在且它的"升级前必须做"一节与重新生成的不同，打印 `⚠️ … 对照 …notes-2.0.0.generated.md 更新`——照着改 `notes-2.0.0.md`，交接前确认最后一次 `--write` 没有这条 ⚠️。
  通过：`--write` 与 `--check` 都 `exit=0`，`--check` 每一项都是"无"（3.2 的全部机器核对，外加代码里的驼峰键读取、读了 `configSchema` 没声明的键）。
  **C3 之后对两份清单的任何增量只走 overrides**：新配置键 `add_properties`、新依赖 `deps_add`、新权限键 `permissions_add`、新菜单 `menus_add`、新网关路由 `edge_routes_add`（字段全集见 tools README 的 manifest-overrides 一节）——改 `manifest-overrides.yaml` 本组件那一段，再重跑 `--write`。不手改 `component.yaml` / `assembly.yaml`：工作区文件既不是 tag 原文、也不是本次或上次 `--write` 的输出时，`--write` 一个文件都不写、把会丢掉的改动以 diff 打到 stderr、exit 3。`--force` 只在读完那份 diff、确认里面没有要保留的东西之后才用（新克隆里没有"上次写出"的记录，也会走到这里）。overrides 表达不了的改动（例如删掉一个 tag 版已有的权限键）上报控制者，不要自己手改后一路 `--force`。
- [ ] **3.1 目标形态**（`--write` 的产物；以 mdm/customer 为例，其余组件按 §2.2 那一行替换键、依赖、端口；人读一遍，不手写）：

  ```yaml
  apiVersion: brickkit/v1
  kind: Component

  metadata:
    id: mdm/customer
    name: Customer master data
    version: 2.0.0                       # 先升版本再动手（01-development-workflow.md#versions）
    description: Customer names, tax IDs, credit limits, status, contacts and billing details.
    repository: https://github.com/brickKit/mdm-customer
    license: Apache-2.0
    vendor: brickKit

  tags: [mdm, customer, master-data]

  artifacts:                             # 原样保留；assembly.yaml 靠 metadata 这一条随组件分发
    - type: api-contract
      format: protobuf
      files: [contracts/mdm/customer/v1/customer.proto, contracts/events/customer.events.json]
    - type: api-contract
      format: openapi
      files: [contracts/customer.openapi.yaml]
    - type: metadata
      files: [assembly.yaml]

  dependencies:
    components: []

  configSchema:
    type: object
    properties:
      PG_HOST: {type: string}
      PG_PORT: {type: string, default: "5432"}
      PG_DATABASE: {type: string}
      PG_USER: {type: string}
      PG_PASSWORD: {type: string, secret: true}
      PG_SCHEMA: {type: string, default: mdm_customer}
      NATS_URL: {type: string}
      OTEL_BASE_URL: {type: string, default: ""}
      AUTHZ_BUNDLE_URL: {type: string}
      IAM_JWKS_URL: {type: string}
    required: [PG_HOST, PG_DATABASE, PG_USER, PG_PASSWORD, NATS_URL, AUTHZ_BUNDLE_URL, IAM_JWKS_URL]

  deployment:
    type: container
    build: {context: ., dockerfile: Dockerfile}
    port: 8080
    extraPorts:
      - {name: grpc, port: 9090}
    labels:
      prometheus.io/scrape: "true"
      prometheus.io/path: "/metrics"
    resources:
      requests: {cpu: "100m", memory: "128Mi"}

  migration:
    command: ["./migrate", "up"]

  healthCheck:
    type: http
    path: /healthz

  local:                                 # focus / mode: local 时 brickKit 在宿主机上怎么起它（Go 的 main 不在根目录，自动探测会跑 go run .）
    language: go
    runCommand: ["go", "run", "./backend/cmd/server"]
  ```

  要点（脚本已按此生成；读预览时逐条核对，不对就改 overrides 而不是改文件）：
  - 删掉全部版本历史注释、`deployment.image`、`dependencies.resources`；`metadata.name`/`description` 用英文（`BRICKKIT.md` 主文件是英文；取自 overrides 的 `name` / `description`）。
  - `metadata.repository` = `https://github.com/brickKit/$REPO`（`git -C $C remote get-url origin` 核对）。
  - 依赖全部写上游的 `@2.0.0`：必需依赖一行 `- erp/inventory@2.0.0`，可选依赖写成 `- id: infra/workflow@2.0.0` 加下一行 `optional: true`；aggregator（bff-mobile）全部 `optional: true`；不为了拉 bundle / 验 token 加 authz 或 iam 的依赖边（[0107]）——但 `infra/iam-casdoor → infra/authz` 是真实的 gRPC 业务调用，保留。
  - `startPeriodSeconds`：Go 不写（默认 60）；Python 120；Node 90。
  - `local.runCommand` 必须是数组（写成字符串 `add` 报 `MANIFEST_INVALID: local.runCommand=must be an array`）。Python / TS 的写法在 infra/print、infra/bff-mobile 的 Task 用 `make verify … FOCUS=1` 真机确定后改 overrides 的 `local` 再重跑 `--write`（手改保护允许这种重跑）。
- [ ] **3.2 机器核对**：就是 3.0 的 `--check`（驼峰 / 非法键、保留名、无默认值却不在 required、required 却有默认值、required 里有未声明的键、密码 / 密钥未标 secret、残留 `dependencies.resources` / `deployment.image`、依赖不是 `@2.0.0`、版本注释、端口与 `registry/ports.tsv`、`PG_SCHEMA` 与 `registry/schemas.tsv`、metadata、`deployment.build` / `local.runCommand`、`assembly.yaml` 的四条、代码里的驼峰键读取与未声明键读取）。通过：`exit=0`。
- [ ] **3.3 组件级 lint**：`cd $ROOT && brickkit lint $ID 2>&1 | tee $S/lint-c3.log`（不严格；带 `<id>` 只检查这一个组件，`--all` 才查全项目）。通过：第一行是 `🔎 Only <id> is checked…`（在 `$ROOT` 跑；在 `$C` 里跑时第一行是 `📁 Project: ../../.. (be-assembly-standard)`、第二行才是 🔎，同样算通过。plan C3 的命令没写 `cd`，按本条先 `cd $ROOT`。），没有 `MANIFEST_INVALID`；此时只剩 `DOC_*` 警告（第 5 步清零）。
- [ ] **3.4 `assembly.yaml` 的规则**（`--write` 已按此处理，人只核对）：
  - `id` 保留；删除 `version:`（版本只在 `component.yaml` 一处）；删除 `shell:` 键（由哪个外壳托管在部署文件里选，[0108]）；`data.role` 的注释改成"登录角色，`PG_USER` 的值"（v1 起组件以它登录，不再只是 `SET LOCAL ROLE` 的目标）。
  - `asset:`（旧 fork 指引，写的是 v0 机制）删除；`edge_routes`、`menus`、`domain`、`tier`、`data`、`data_scopes`、`permissions` 一律保留（P5，R38 维持；`menus` 的结构扩展归 06c）。
  - §1.2 的新权限键写进 overrides 的 `permissions_add`（`{ key, title, type }`，`key` 的域前缀等于组件域），重跑 `--write`；`data_scopes` 段必须在（无行级范围写 `data_scopes: none`，`--check` 查）。
- [ ] **3.5 新权限键汇总进登记表**（只在本组件新增了键时，`--write` 之后）：
  ```bash
  make -C $ROOT permissions          # 拿项目锁：be-ops permissions + data-scopes + registry-check，并核对 permissions.tsv 只增不删
  git -C $ROOT diff --stat registry/
  ```
  通过：最后一行 `✓ registry/permissions.tsv 相对 HEAD 只有新增（…）`；孤儿键警告照常出现（旧组件），不处理。`git -C $ROOT diff registry/permissions.tsv` 里的 `+` 行只能是本组件 `owner_component` 的键；有别的组件的行就记录并告诉控制者（别的工作线的半成品），不手删。
  authz 的 `PERMISSION_CATALOG` 直接引用这个文件（§2.5），新键在下一次 `brickkit up` 时自动进入 authz，不需要再生成任何东西；全栈集成时核对新键已出现在 `infra_authz.permissions` 里。

### 第 4 步　代码迁移、审查、补接口、测试

**4A 机械迁移**（Go；Python / TS 对应项写在后面）

Go 组件的 4.0–4.4 与 4.6 由一条命令完成（plan C4；幂等，可重复运行，最后跑 4.4 的全部判据，任一 FAIL 就非零退出）：

```bash
cd $C && git fetch --tags -q                 # 4.3 的契约包版本只看本地已有的 gen/* tag
bash $ROOT/dev/phase-06/tools/go-v2.sh $ID --sdk v0.4.0; echo "exit=$?"
```

通过：`exit=0`。下面 4.0–4.4、4.6 的手工命令是脚本所做之事的原文，保留作排障参考与 diff 审读的对照；判据全集以脚本输出和 `dev/phase-06/tools/README.md` 的"go-v2.sh / 判据"为准（4.4 列出了全部判据）。脚本不做、仍要人做的：4.5、4.7、4.9 的修改（核对由 `component-check.sh` 做，4.18）；4.6 的读 diff、改 `migrations/embed.go` 的过时注释、核对 Dockerfile 的目的路径。

**gen 判据先于一切**：脚本会把当前 `contracts/*.proto` `buf generate` 到 `$S` 下的临时目录，与组件的 `gen/` 逐个比（不写 `gen/`）。已知 **infra/workflow 在 v1.0.4 就不一致**（`gen/infra/workflow/v1/workflow_grpc.pb.go` 里 `ListTasks` 的注释改过 `.proto` 却没重新生成），它第一次跑就会在这条 FAIL：先在 `$C` 里 `buf generate`，读 `git diff --stat gen/`（应只有注释）、单独提交，再跑 `go-v2.sh`。只是重新生成按 4.0 的规则升 **patch**：重新生成提交之后跑 `go-v2.sh $ID --recheck --gen-bump patch`（最新契约包 tag 是 `gen/infra/workflow/v1.0.3`，所以是 `v1.0.4`），交接时告诉控制者。别的组件在这条 FAIL 时先核对 `command -v protoc-gen-go protoc-gen-go-grpc` 都在 `~/go/bin`——插件版本不对时每个组件都会 FAIL，这时**不要**照着 FAIL 去 `buf generate`（会用错版本的插件重写 `gen/`，凭空造出一次契约包升版），上报控制者。

- [ ] **4.0 先认清本组件 `gen/` 是哪种形态**（两种形态的改法不同，用错了不报任何错）：
  ```bash
  cd $C && find gen -name go.mod; git tag -l 'gen/*'; grep -n "brickKit/$REPO/gen" go.mod
  ```

  | 形态 | 判据 | 组件（写本文件时实测） |
  |---|---|---|
  | **A 嵌套模块** | `gen/<domain>/<name>/go.mod` 存在，有 `gen/<domain>/<name>/v*` tag，根 `go.mod` 里 `require …/gen/<domain>/<name> v0.0.0` + `replace => ./gen/<domain>/<name>` | mdm/customer、mdm/product、erp/inventory、erp/finance、infra/authz、infra/workflow |
  | **B 属于根模块** | `find gen -name go.mod` 为空，没有 `gen/*` tag，根 `go.mod` 里没有 `/gen/` 那一行 | crm/opportunity、erp/sales、infra/iam-casdoor、infra/notification、integration/im-dingtalk |

  ⚠️ 形态 B 照着形态 A 的改法做（import 改 `/v2` 时跳过 `gen/`）会**静默出错**：`go build` 先报 `no required module provides package github.com/brickKit/<repo>/gen/…`，接着 `go mod tidy` 自己"修好"它——`found … in github.com/brickKit/<repo> v1.x.y`，往 `go.mod` 里加一行 `require github.com/brickKit/<repo> v1.x.y`，之后 v2 组件就对着**自己上一个已发布版本**的生成代码编译，所有门禁都是绿的（infra/notification 上实测复现，见 task-17 报告）。

  **规则（两种形态统一到一种结果）**：每个 Go 组件的 `gen/<domain>/<name>/` 都是**独立的嵌套 Go 模块**（02-backend.md 的仓库结构本来就这么写），模块路径是 `github.com/brickKit/<repo>/gen/<domain>/<name>`，**不带 `/v2`**、跟组件的主版本无关；它自己的 tag 是 `gen/<domain>/<name>/v1.<minor>.<patch>`，只在生成物变化时打（契约新增 → minor，只是重新生成 → patch；形态 B 拆出来时第一个 tag 是 `v1.0.0`）。组件根 `go.mod` 永远 `require` 一个**真实存在的**契约包版本（第 8.3 步打的那个 tag，不再是 `v0.0.0`），外加本地 `replace => ./gen/<domain>/<name>` 给自己构建用。`.proto` 的 `go_package` 不改（它写的正是这个嵌套模块里的包路径），所以 `make contract-check` 不受影响。形态 B 先做 4.1，再和形态 A 一起做 4.2–4.4。
- [ ] **4.1 只有形态 B：把 `gen/` 拆成嵌套模块**（`G` 是 `gen/` 下第一层的两级目录，如 `gen/infra/notification`、`gen/infra/iam`、`gen/integration/im`、`gen/erp/sales`、`gen/crm/opportunity`；以 `ls -d gen/*/*/` 的实际结果为准）：
  ```bash
  cd $C && M=github.com/brickKit/$REPO && G=$(ls -d gen/*/*/ | head -1); G=${G%/}; echo "G=$G"
  VG=$(go list -m -f '{{.Version}}' google.golang.org/grpc); VP=$(go list -m -f '{{.Version}}' google.golang.org/protobuf)   # 与根模块用同一版本
  (cd $G && go mod init $M/$G && go mod edit -go=1.25.0 -require=google.golang.org/grpc@$VG -require=google.golang.org/protobuf@$VP \
    && go mod tidy && go build ./... && echo "契约包模块 OK")
  go mod edit -require=$M/$G@v1.0.0 -replace=$M/$G=./$G
  ```
  同时改 `Dockerfile`：`COPY go.mod go.sum ./` + `RUN go mod download` 在本地 `replace` 下会失败（目录还没拷进去；实测 `go mod download` exit 1），改成先 `COPY . .` 再 `RUN go mod download`（形态 A 组件的 Dockerfile 早就是这样写的）。
  通过：`契约包模块 OK`；`git status` 里多出 `$G/go.mod`、`$G/go.sum`。`v1.0.0` 这个 tag 第 8.3 步才推，在那之前只有本地 `replace` 能解析它——这是预期的。
- [ ] **4.2 Go 模块路径改 `/v2`，并改写全部自引用的 import**（两种形态都做；契约包的 import 路径 `…/<repo>/gen/…` 指向嵌套模块，**不改**）：
  ```bash
  cd $C && M=github.com/brickKit/$REPO
  go mod edit -module $M/v2
  git ls-files '*.go' | grep -v '^gen/' | xargs perl -pi -e 's#"github.com/brickKit/'$REPO'/(?!v2/|gen/)#"github.com/brickKit/'$REPO'/v2/#g'
  ```
- [ ] **4.3 根 `go.mod` 里的契约包版本不能是 `v0.0.0`**（形态 A 现在都是；形态 B 在 4.1 已写成 `v1.0.0`）：`replace` 只在本模块自己构建时生效，外壳把本组件当依赖拉取时它被忽略，外壳就去远端找 `v0.0.0`——实测（scratch 探针模块 require `mdm-customer/v2` 并把它 replace 到本地副本）：
  `reading github.com/brickKit/mdm-customer/gen/mdm/customer/go.mod at revision gen/mdm/customer/v0.0.0: unknown revision gen/mdm/customer/v0.0.0`；改成 `v1.0.6` 后探针 `go build` 通过。改法：
  ```bash
  git -C $C tag -l 'gen/*' | sort -V | tail -1            # 例如 gen/mdm/customer/v1.0.6 → 写 v1.0.6
  git -C $C diff --stat <这个 tag> -- gen/                  # 输出为空 = 本地生成物与这个 tag 一致
  go mod edit -require=github.com/brickKit/$REPO/gen/<domain>/<name>@v1.x.y   # 例如 …/mdm-customer/gen/mdm/customer@v1.0.6；本地 replace 不动
  ```
  形态 B 拆出来的组件第一个 tag 一律 `v1.0.0`（P3，即使同一轮契约有新增也是 `v1.0.0`，它就包含新增，06a N-5）。本地 `gen/` 与最新 tag 一致就 require 那个版本；这次契约有变化（§1.2 的新字段 / 新 rpc，第 4.14 步重新生成之后 `git diff` 不为空）就 require **下一个**版本号（例如 `v1.1.0`），第 8.3 步打这个 tag。下游组件（如 erp/sales 依赖 `mdm/product` 的契约包）：用到了新字段 / 新 rpc 就在它自己重建时 `go get …/gen/mdm/product@v1.1.0`；没用到可以不升（外壳里 Go 的最小版本选择会取最高的那个）。
- [ ] **4.4 升 SDK、整理、编译，然后用下面的判据确认没有退回 v1**（be-sdk-go v0.4.0 删掉了 `Module.Migrations`：手工做时先做 4.6——删 `module.go` 的 `Migrations:` 一行及随之不用的 import，把 `backend/cmd/migrate/main.go` 换成 `migrate.Main`——否则 `go build` 报 `backend/module/module.go:57:3: unknown field Migrations in struct literal of type besdk.Module`（实测）；`go-v2.sh --sdk v0.4.0` 在编译之前自己做 4.6，不会撞上这条。`UserClient`/`SystemClient` 等签名变化同理：编译不过就先做 4.5，再重跑 `go-v2.sh $ID --sdk v0.4.0`，它是幂等的）：
  ```bash
  cd $C && M=github.com/brickKit/$REPO
  go get github.com/brickKit/be-sdk-go@<1.4 的 tag> && go mod tidy && go build ./... && go vet ./... && echo BUILD_OK
  head -1 go.mod
  grep -nE "^\s*(require )?$M v" go.mod || echo "go.mod 没有 require 自己的旧路径"
  go list -m all | grep "$M"
  go list -deps -f '{{if .Module}}{{.Module.Path}}{{end}}' ./... | sort -u | grep "$M"
  grep -rn "\"$M/" --include='*.go' . | grep -v -e "\"$M/v2/" -e "\"$M/gen/" || echo "import 全部带 /v2（契约包除外）"
  ```
  通过（`go-v2.sh` 的判据全集，每条一行 PASS/FAIL，全部 PASS 才 `exit=0`；手工排障时逐条对照）：
  1. `go mod tidy` + `go build ./...` + `go vet ./...` 通过（`BUILD_OK`）；
  2. **`gen/` 是当前 `contracts/*.proto` 的生成结果**（`buf generate` 到临时目录比对；多出的、缺少的、内容不同的 `*.pb.go` 逐个点名，见 4A 开头）；
  3. `go.mod` 第一行是 `module github.com/brickKit/<repo>/v2`；
  4. `go.mod` 没有 require 自己的旧路径——出现 `github.com/brickKit/<repo> v1.x.y` 就是形态 B 被当成形态 A 做了（C-1），回到 4.0（完整运行会自动清掉并报 ⚠️；`--recheck` 不清、报 FAIL）；
  5. 契约包是嵌套模块（`gen/<domain>/<name>/go.mod` 在），模块路径不带 `/v2`；
  6. 根 `go.mod` require 的契约包版本 = 4.3 算出的版本（不是 `v0.0.0`），并有本地 `replace => ./gen/<domain>/<name>`；
  7. 根 `go.mod` 里除契约包外没有别的 `replace`（例如指到本机 `tools/be-sdk-go`：本机全绿，`brickkit build` 时才失败）；
  8. `go list -m all` 里本仓库模块恰好两行：`github.com/brickKit/<repo>/v2` 与 `github.com/brickKit/<repo>/gen/<domain>/<name> v1.x.y => ./gen/<domain>/<name>`；
  9. `go list -deps`（含测试）里的本仓库模块只有这两个（C-1 状态下会多出 `github.com/brickKit/<repo>`）；
  10. import 全部带 `/v2`（契约包 `…/<repo>/gen/…` 除外；没有不带子路径的裸导入 `"github.com/brickKit/<repo>"`，也没有 `…/v2/gen/…`；`//go:build ignore` 的文件也查）；
  11. Dockerfile 先 `COPY . .` 再 `go mod download`（本地 replace 要求契约包目录在场）；
  12. SDK ≥ v0.4.0 时 `backend/cmd/migrate/main.go` 恰好是 `migrate.Main(migrations.FS)` 一行入口、非 gen 代码里没有 `Migrations:` 字段（4.6）；
  13. Dockerfile 编译 `./backend/cmd/migrate` 并把二进制 `COPY --from` 进最终镜像；
  14. 给了 `--sdk` 时，be-sdk-go 就是那个版本。
  倒数第二行打印 `📌 第 8.3 步需要打的契约包 tag：gen/<d>/<n>/vX`，或"不需要"；最后一行是 `✅ go-v2.sh：判据全部 PASS`（或 `❌`）——原文进记录，交接时交给控制者。
- [ ] **4.5 改配置读取**：`migrate-manifest.py --write` 已把 SDK 读法里的旧键换成新键（3.0）；人改的是它认不出的地方（测试里构造 `Config` 的 map、报错文案里的旧键名、`flag` 之外的自定义读法）和旧平台变量 / 旧 API。核对由 `component-check.sh` 的前两项做（4.18；Go / Python / TS 都查，`*.go *.py *.ts *.js *.sh *.mk Makefile`）：`4.5 无驼峰键读取`、`4.5 无旧平台变量 / 旧 API（DATABASE_*、MQ_*、besdk.Endpoint、STORAGE_ENDPOINT）` 两行都是 PASS。这两项没有放行机制（只有历史扫描有 `history_allow`）：测试里故意写 `DATABASE_`（验证"不读它"）也会 FAIL，这种命中上报控制者裁定，不为了过检查去改测试。依赖地址只用 `rt.Config.Endpoint(dep, "grpc")` / `MustEndpoint`；用户请求路径上 `besdk.UserClient(ctx, rt.Config, dep, "grpc")`，`besdk.SystemClient(rt.Config, dep, "grpc")` 只在 `Start()` 和事件 handler 里；对象存储 `rt.Config.S3URL()`。
- [ ] **4.6 迁移入口**（be-sdk-go v0.4.0 的 `migrate` 包，P4；**由 `go-v2.sh --sdk v0.4.0` 完成，人工核对**）：
  - **脚本做的**（v0.4.0 起，在编译之前）：删掉 `backend/module/module.go` 的 `Migrations:` 一行；把 `backend/cmd/migrate/main.go` 改写成只剩 `func main() { migrate.Main(migrations.FS) }`（import `github.com/brickKit/be-sdk-go/migrate` 与本组件的 `…/v2/migrations`）；`migrations/embed.go`（`//go:embed *.sql` + `var FS embed.FS`）缺了就建；两处都核对，不符就 FAIL。连接串、`search_path`、`schema_migrations_<schema>` 表名、`up`/`down` 参数校验都由 SDK 负责（读 `PG_*`，缺键以 1 退出并点名；参数不对以 2 退出）；SDK 用 `database/pgx/v5`，不再有 lib/pq 与 `sslmode` 的问题。`component.yaml` 的 `migration.command` 不变（`["./migrate", "up"]`）。
  - **人要做的**：读脚本产生的 diff（`git -C $C diff -- backend/ migrations/`），确认 `module.go` 里随 `Migrations:` 一起不再用的 import 已清掉、`migrations/embed.go` 的注释不再说"挂到 `Module.Migrations`"；核对 `Dockerfile`（脚本已判"编译 `./backend/cmd/migrate` 并 `COPY --from` 进最终镜像"，人只看目的路径）：仍然 `go build … -o /out/migrate ./backend/cmd/migrate` 并拷成 `/app/migrate`（`WORKDIR /app`，`./migrate up` 才找得到），`COPY component.yaml /app/component.yaml` 保留；迁移文件已嵌进二进制，`COPY migrations /app/migrations` 不再需要，可以删。
  - 通过：`go-v2.sh` `exit=0`；4.16 的 `make test-db-init ID=$ID` 输出 `✓ 迁移幂等`；`verify` 里迁移容器 `Exited (0)`。
- [ ] **4.7 `Makefile`：Go 组件照抄 mdm/customer 的（R43）**：`cp $ROOT/components/mdm/customer/Makefile $C/Makefile`，然后只改组件特有的部分：
  - 顶部 `ID := <scope>/<name>`、`REPO := <repo>` 两行；`migrate-idempotent` 注释里的登录角色名（`$ROLE`）；
  - `dag-check`：模板判的是"没有任何依赖"（主数据组件）。有依赖的组件改成"列出 `dependencies.components` 并确认每一条都是 `@2.0.0`"（同样用 `python3 -c 'import yaml …'` 读，不数 `- ` 行），失败时说清是哪一条；
  - `help` 的目标说明、`seed` / `seed-clean`（或 `db-reset`）按组件已有的种子脚本写；`module-check` 的扫描目录与禁用库清单不改。
  改完 `grep -n -i 'customer\|客户' $C/Makefile` 必须为空（mdm/customer 自己除外；本组件确实要提到客户的说明文字，例如依赖 mdm/customer 的组件，逐条确认不是模板残留）——模板里 `migrate-idempotent` 注释的 `mdm_customer_rw` / `PG_SCHEMA=mdm_customer` 与 `seed` 说明的"示例客户"都要换掉。
  模板里已经修好、照抄时不要改回去的四处：
  - `contract-check` 对比**上一个发布 tag**（`git describe --tags --abbrev=0 --exclude 'gen/*'`），不是 `branch=main`（在 main 上等于自己比自己）。它找不到 tag 时会**不报警**地回落到 `main`：跑的时候看它打印的那一行，必须是 `buf breaking --against '.git#tag=v1.x.y'`（2.0.0 之前是最后一个 1.x tag），是 `.git#branch=main` 就回到 1.2 先 `fetch --tags`。
  - `test` 没设 `TEST_PG_DSN` 时大声失败（`✗ 没设 TEST_PG_DSN：…`，exit 非零），不再"全部 SKIP 却显示 ok"；DSN 由 §0.1 的 `env.sh` 给。
  - `import-scan`、`module-check` 先把 `go list -deps …` 的输出取进变量、检查退出码，再过滤；不要写成 `go list … 2>/dev/null | grep … || true`（`/bin/sh` 没有 pipefail，`go list` 失败时什么都没扫到也打印 ✓）。`import-scan` 的自身白名单是 `$(REPO)/v$(MAJOR)`，自动跟着版本走。
  - 配方里的说明注释写成 `@# …`：**`@#` 注释行绝不以 `\` 结尾**——续行符把下一行配方并进同一条 shell 命令，下一行开头的 `@` / `-` 不再被 make 当前缀处理：下一行也是 `@#` 时报 `/bin/sh: 2: @#: not found`（试点撞上过）；是普通命令时它照样执行，但继承了这一行的 `@`、不再回显。多行说明每行各自一个 `@#`、都不带 `\`。
  其余目标（`check-version` 的双 tag 判据、`docs-check` = `brickkit lint --strict $(ID)`、`smoke` = `brickkit up --dry-run`、`image` = `brickkit build` + 镜像里 sh/wget/`component.yaml` 检查）原样。Python / TS 组件不抄 Go 的 Makefile，按同样的目标集合与同样四条"不静默成功"的要求写各自的命令（`test` 同样要求 `TEST_PG_DSN`）。
  **Dockerfile**（Go）：照 mdm/customer 的写法——先 `COPY . .` 再 `go mod download`；`server` 与 `migrate` 两个二进制；`COPY migrations /app/migrations` 删掉（迁移已嵌进二进制）；`COPY component.yaml /app/component.yaml` 保留。
- [ ] **4.8 父仓库的过渡脚本**（只核对，不改父仓库文件）：`infra/scripts/test-db-init.sh` 已由 Task 5 改为同时传 `PG_*`（以 `<schema>_rw` 登录）与旧的 `DATABASE_*`（T26 删）；本组件只核对 `make test-db-init ID=$ID` 绿（4.16），不改父仓库文件。
- [ ] **4.9 脚本**：`scripts/seed.sh` 等里写死的旧版本服务名（`1-0-N`）与 `DATABASE_*` 改掉（服务名用 `infra/scripts/lib/seed-net.sh` 的 `service_name <id>` 现算，不写死版本）。核对是 `component-check.sh` 的 `4.9 scripts/` 一项（4.18）。

Python（infra/print）对应项：`pyproject.toml` 的 `version` 改 `2.0.0`（旧值 1.0.2 与组件版本早已分叉）；besdk 钉到与 py-render 同一个 tag；`backend/app/module.py` 的 `string_or("pgSchema", …)` 换新键；`backend/app/migrate.py` 改读 `PG_*`（yoyo 的 `postgresql://` 后端用 psycopg2，注意 `sslmode`；be-sdk-python v0.4.4 的迁移助手以其 README 为准）；没有 `/v2` 这件事。
TypeScript（infra/bff-mobile）对应项：`package.json` 的 `version` 改 `2.0.0`（旧值 1.0.6）；besdk 钉到 be-sdk-ts v0.4.0（`git+…#v0.4.0`）；`userClient(config, auth, dep, extra)` / `systemClient(config, dep, extra)` 新签名；`config.endpoint()` 取地址。

**4B 审查（只修真实问题，不改业务行为）**

- [ ] **4.10 超长文件 / 函数**：
  ```bash
  git ls-files '*.go' | grep -v -e '^gen/' -e '_test.go$' | xargs wc -l | sort -n | awk '$1>600'
  git ls-files '*.go' | grep -v -e '^gen/' -e '_test.go$' | xargs awk 'FNR==1{f=""} /^func /{f=$0; s=FNR} /^}/{if(f!=""){if(FNR-s>150) print FILENAME": "FNR-s" 行: "f; f=""}}'
  ```
  命中的按 09-ai-development.md 判断是否拆；拆就单独一个提交，说明为什么。
- [ ] **4.11 正确性与重复样板**：通读 `module.go`、`internal/` 各层；重复的样板代码（同一段在三处以上）能下沉到 SDK 的，记进过程记录的"反馈候选"，不在组件里自创抽象。发现真实 bug：先写一个红的测试，再修（红绿各一个提交）。
- [ ] **4.12 合并安全三问**（02-backend.md#merge-safety）：`make module-check` 绿，且人工确认：模块代码零 `os.Getenv`、零进程级初始化、零 `log.Fatal`/`os.Exit`。

**4C 补前端需要的接口（§1.2 本组件那一行）**

- [ ] **4.13 先写设计**：边界 / 契约 / 事件有变化的，先改 `docs/design.md`（第 5 步的文件，可以先只写这一段）。涉及新的跨组件事件或改变已有事件语义的，除 plan-06b 预设裁定（P9）已定的方案外，由控制者裁定并记录（§7），不自行扩展。
- [ ] **4.14 契约先行，只增不改**：改 `contracts/*.proto` / `*.openapi.yaml` / `events/*.json`。顺序固定：改 `.proto` → 在 `$C` 里 `buf generate` → `bash $ROOT/dev/phase-06/tools/go-v2.sh $ID --recheck`（重算根 `go.mod` require 的契约包版本、重跑 4.4 全部判据；只改 `.proto` 不生成就 `--recheck`，gen 判据 FAIL）。`git diff --stat gen/` 有变化就要打新的契约包 tag：把 `--recheck` 最后打印的 `📌 第 8.3 步需要打的契约包 tag`（或"不需要"）原文交给控制者。脚本默认升 minor（`--gen-bump minor`），每次运行都把 require 重写成它算出的版本，所以不要手工 `go mod edit` 改版本号（会被改回去）。`gen/` 的变化只是重新生成（例如只改了注释）时传 `--gen-bump patch`，由控制者裁定；已知的就是 infra/workflow（T13，见 4A 开头）。核对：`make contract-check`（proto，`--against` 必须是上一个发布 tag，见 4.7）绿；REST 契约由 `openapi-additive-scan` 对比上一个发布 tag 核对（6.5 的 `make gates`，发布前 `make ship` 再跑一次）。
  **R41：`.proto` 里的旧注释（归档引用、历史说法）本轮不清理**——改 `.proto` 注释会改 `gen/`、逼出一个没有实质变化的契约包 tag。等这个组件下一次真实的契约变更时一起改；本 Task 正好要改 `.proto`（§1.2 的新字段 / 新 rpc）时，只顺手改**被改动的那几条消息**附近的注释，不做全文清理。`component-check.sh` 的历史扫描本来就跳过 `*.proto` 与 `gen/`。
- [ ] **4.15 红绿**：每条新规则先写 L2 测试并跑红（红的原因是"功能还不存在"），再写实现跑绿；一个循环一个提交。有数据范围的接口（warehouse、legal_entity、org/owner）必须有"别人的数据看不到"的测试（06-testing.md#l2）。新增路由一律 `besdk.GET(r, path, permKey, h)` 这类带权限键的注册。

**4D 全部测试**

- [ ] **4.16 测试库就绪、迁移幂等**：`make -C $ROOT test-db-init ID=$ID`（拿锁）。它先刷新 `brickkit_test_db` 的 schema 与授权，再**只对本组件**以 `$ROLE` 登录跑 `make migrate-idempotent`（不带 `ID` 时跑全部连库组件，并行开发时会被别人的半成品挡住，组件 Task 一律带 `ID`）。通过：`- $ID` 下面是 `✓ 迁移幂等`，最后一行 `✓ brickkit_test_db 就绪`。本组件的 `migrate-idempotent` 就以这条命令为准，不在组件目录里直接跑它（那要自己提供 `PG_PASSWORD`，不为此 source `.env`）。不连库的组件不在它的清单里（exit 2），记"不连库"。
- [ ] **4.17 跑测试**（在 `$C` 下；`TEST_PG_DSN` / `TEST_NATS_URL` 来自 §0.1 的 `env.sh`，同一次 Bash 调用里先 `eval`）：
  ```bash
  make test > $S/test.log 2>&1; echo "exit=$?"; tail -5 $S/test.log   # 没有 TEST_PG_DSN 时它大声失败，不会"全部 SKIP 显示 ok"；记录里贴全文
  go test ./... -race -count=1 -v 2>&1 | grep -E '^(--- FAIL|--- SKIP|FAIL|ok )' | tee $S/test-v.log
  grep -c -- '--- SKIP' $S/test-v.log
  make contract-check module-check import-scan
  ```
  通过：`make test` exit 0；没有 `--- FAIL`/`FAIL`；`--- SKIP` 计数只来自"需要真实依赖、由 `make test-cross` 跑"的跨组件测试（逐条列名进记录），这些测试在第 7 步 `make verify` 的跨组件测试（7.2 第 5 项）里必须真的 PASS；其余三个目标都绿（`contract-check` 打印的 `--against` 是 tag）。Python：`pytest -q`；TS：`npm test`（同样核对 skip，同样要求 `TEST_PG_DSN`）。
- [ ] **4.18 机械核对**（第 4 步改完代码、提交之前跑一次；第 5 步写完文档后（5.2）、第 6 步（6.4）各再跑一次）：
  ```bash
  bash $ROOT/dev/phase-06/tools/component-check.sh $ID; echo "exit=$?"
  ```
  只读、不需要 brickkit / buf / `.env`、组件不用先加入项目；范围是 `git ls-files -co --exclude-standard`（已跟踪 + 未跟踪但没被忽略的文件，提交前就能查）。十项各一行 PASS/FAIL，FAIL 下面逐处列 `文件:行: 原文`：

  | # | 检查项 | 原来人手做的 |
  |---|---|---|
  | 1 | 4.5 无驼峰键读取（Go / Python / TS 的 SDK Config 读法） | 原 4.5 第一条 grep |
  | 2 | 4.5 无旧平台变量 / 旧 API（`DATABASE_*`、`MQ_*`、`besdk.Endpoint`、`STORAGE_ENDPOINT`） | 原 4.5 第二条 grep |
  | 3 | 4.9 `scripts/` 里没有旧版本服务名（`1-0-N`）与 `DATABASE_*` | 原 4.9 的 grep |
  | 4 | 历史 / 归档引用（`§`、`决策 N`、`设计计划`、`设计书`、`阶段…`、`总纲`、`手册`、`铁律`、`Task N`、`docs/plans/`、`archive/`） | 5.1"不写历史"的人工 grep |
  | 5 | 四对文档 en/zh 的 `##` 小节数相等 | 原 5.2 的 `##` 计数 |
  | 6 | `AGENTS` / `README` / `docs/design` 首行互链 | 5.1 |
  | 7 | 文档没有 `../` 链接 | `DOC_LINK_NOT_PORTABLE` |
  | 8 | 文档没有越界链接（`dev/`、`archive/`） | 原 5.2 的越界链接 grep |
  | 9 | `BRICKKIT*.md` 没有相对链接 | 原 5.2 的 BRICKKIT 相对链接 grep |
  | 10 | 文档没有 `TODO` / `TBD` / `待填` | `DOC_PLACEHOLDER` 的一部分 |

  第 4 项的范围是**除** `gen/`、`.claude/`、任意位置的 `*.proto`、`migrations/*.sql` 以外的全部文件（含 `go.mod`、`buf.yaml`、`LICENSE`、`Makefile`、`Dockerfile`、测试、注释）与文件名本身（残留的 `docs/手册.md`）——试点人工 grep 漏掉的正是 `go.mod`、`buf.yaml`、`LICENSE` 三处。命中就改成原因本身（不写出处）。**确有理由必须留着的**命中写进 `manifest-overrides.yaml` 本组件的 `history_allow: [{path, text, why}]`：`path` 是确切的文件路径（不许通配），`text` 是命中行里的一段原文（至少 6 个字符、本身含命中的模式），`why` 写为什么必须留；这一行的**每一处**命中都要落在某条 `text` 的范围里，一条放行盖不住同一行的第二处；放行的行打印成 `ℹ️ … history_allow 放行（why）`，没用上的条目也会列出来（删掉）。放行是例外：能改写的一律改写，`history_allow` 的每一条在交接时告诉控制者。
  通过：第 4 步结束时第 1–9 项 PASS；第 10 项（占位符）此时一定 FAIL（文档还是 docs-skel 骨架，第 5 步才填），不算卡点，原文记录；第 1–4 项的 FAIL 先修（plan C4"FAIL 的先修"指的就是这几项）。第 5、6 步之后十项全部 PASS、`exit=0`。它不替代 `make docs-check ID=$ID`（`brickkit lint --strict`）与 `make docs-boundary`：那两个仍是第 5、6 步的最终判据。

### 第 5 步　四件套（每份都带 `.zh.md`）

- [ ] **5.1 写作要点**（08-documentation.md#component-documents、brickkit-component skill 规则 12）：

  | 文件 | 必须有的内容 |
  |---|---|
  | `BRICKKIT.md` | 六节：`Purpose`（一两句话说解决什么，然后 **Owns** / **Does not own** 两个列表，后者每条写明谁拥有）、`Before you deploy`（schema `$SCHEMA` 与 `${SCHEMA}_archive`、登录角色 `$ROLE` 及其在两个 schema 上的 USAGE+CREATE、`PG_PASSWORD` 从哪来；NATS 可达；本项目里由 `make dev-env` + `make db-init` 完成）、`Dependencies`（每个依赖按 ID 不带版本、用来做什么、optional 的缺席时怎样降级；说明 authz/iam 地址是配置不是依赖）、`Configuration`（**全部** `configSchema` 键，至少全部 required 键，写业务含义与推荐取值形式 `$var:` / `${…}` / 字面量；**不写旧键 → 新键对照**——那是历史，写在发布说明的"升级前必须做（破坏性变更）"里，R42）、`Contracts`（`artifacts` 里每个文件、主要 rpc 与 REST 路径及权限键、发布与消费的事件）、`Shell declaration`（"Not a shell." 并说明设计上可被哪个外壳托管）。**不写相对链接**，文件名写成行内代码 |
  | `BRICKKIT.zh.md` | 同样六节，标题必须是 `组件定位` / `部署前准备` / `依赖说明` / `配置指南` / `契约索引` / `外壳声明`（自由翻译 lint 不认）；不写相对链接 |
  | `AGENTS.md` | 第一行 `[English](AGENTS.md) · [中文](AGENTS.zh.md)`；五节 `Code map`（两张表："Path / Owns"，路径用反引号、目录以 `/` 结尾，每个路径都要真实存在；"Feature / Start here / Then"）、`Build and test`（确切命令与成功的样子）、`Design decisions`、`Pitfalls`（Never / Symptom / Why，**只写本组件特有的**，项目级规则不抄）、`Before changing code`（3–8 条）；末尾 brickKit 维护块不动。不写指向 `../` 的链接（`DOC_LINK_NOT_PORTABLE` 也查 AGENTS.md）。⚠️ `DOC_PATH_MISSING` 把 Code map **第一张表任何一列**里含 `/` 的行内代码都当路径去查：tag、模块路径、URL、`<scope>/<name>` 这类不是仓库路径的东西在这张表里不加反引号（或挪到第二张表 / 正文）。表格单元格里的行内代码不能含竖线（Markdown 把它当列分隔，整行错位），要写"或"就用文字或拆成两段行内代码。`Design decisions` 只写改代码必须知道的一句，原因留给 `docs/design.md`，两边不重复 |
  | `AGENTS.zh.md` | 同样五节，固定中文标题 `代码地图` / `构建与测试` / `设计取舍` / `易错点` / `改代码前自查`（v1.1.0 起不需要另写一节占位标题，维护块不计入小节数） |
  | `README.md` / `.zh.md` | 第一行互链；中文固定标题 `在项目里使用` / `文档` / `开发`；`Use it in a project`（`brickkit add <id>@2.0.0`，先看 BRICKKIT.md 的 Before you deploy）、`Documentation`（哪个问题读哪个文件）、`Development` |
  | `docs/design.md` / `.zh.md` | 从 `archive/pre-v1/docs/dev/design/$REPO.md` **只提取结论**：边界（含明确不归本组件的）、拥有的数据（表、分区、终态）、契约面（含 `batchGet`、REST 路径与权限键、幂等端点、状态端点）、发布与消费的事件、依赖及"为什么不依赖某个预期中的组件"、在同步调用图里的位置、分区与归档、数据范围或为什么没有、参考实现、未决问题。另把 `$S/assembly-removed-comments.txt`（3.0 去掉的 `assembly.yaml` 注释）里仍然成立的结论写进对应小节（不带出处）。每个事实都要能在代码里找到（试点写过"开票信息有写入"，其实没有任何接口写它） |
  | `CLAUDE.md` | 恰好 `@AGENTS.md` |

  所有文件：不写历史（"阶段 X 时…""v1.0.6 修了…""格式不变"一律不要，历史在 git 和 tag 说明里）——这条同样管代码注释、`go.mod`、`buf.yaml`、`LICENSE`、`Makefile`、`Dockerfile`（`component-check.sh` 第 4 项查；`.proto` 例外，见 4.14 的 R41）；每条禁令带症状和原因；不写"见上文"；不链接 `dev/`、`archive/`。
  照抄样板：mdm/customer 的八份文件结构可以直接用；BRICKKIT 里"失败关闭时各回什么状态码"那一段对每个连 authz / iam 的组件都成立（`IAM_JWKS_URL` 是 required，写"为空或不可达"，不写"没设"）。
- [ ] **5.2 核对**：
  ```bash
  bash $ROOT/dev/phase-06/tools/component-check.sh $ID; echo "exit=$?"     # 4.18 的十项；第 5–10 项是文档
  cd $ROOT && make docs-boundary && make docs-check ID=$ID; echo "exit=$?"
  ```
  通过：`component-check` `exit=0`（小节数、首行互链、`../` 与越界链接、BRICKKIT 相对链接、占位符、历史引用全部 PASS）；`make docs-boundary` 绿；`make docs-check` 输出 `0 with errors, 0 warnings`（见 6.2；`DOC_TRANSLATION_DRIFT` 以 lint 为准）。

### 第 6 步　版本 2.0.0，`lint --strict` 零警告

- [ ] **6.1 版本处处一致**：`grep -m1 -n 'version:' $C/component.yaml` → `2.0.0`；Go：`head -1 $C/go.mod` 以 `/v2` 结尾；Python：`pyproject.toml` 的 `version = "2.0.0"`；TS：`package.json` 的 `"version": "2.0.0"`。
- [ ] **6.2 严格 lint**：`make docs-check ID=<scope>/<name>; echo "exit=$?"`（项目根；严格档，只查这一个组件）。通过：`📋 Checked … files: 0 with errors, 0 warnings` 且 `exit=0`。常见警告与处理：`DOC_PLACEHOLDER`（骨架 TODO 没删）、`DOC_OUT_OF_STEP`（某个依赖 / required 键 / 契约文件文档没提）、`DOC_PATH_MISSING`（Code map 第一张表里的路径不存在——**任何一列**里含 `/` 的行内代码都算路径，见 5.1 的 AGENTS 一行）、`DOC_TRANSLATION_DRIFT`（两边小节数不一致）、`DOC_LINK_NOT_PORTABLE`（BRICKKIT*.md 或 AGENTS.md 里的相对 / `../` 链接）。
- [ ] **6.3 组件门禁**（在 `$C` 下，同一次调用里先 `eval` env.sh）：`make check-version test dag-check contract-check import-scan module-check` 全绿（`docs-check` 见 6.2，即 plan C6 第一条；`check-version` 此时 HEAD 还没有 tag，只核对版本一致性；HEAD 若仍是最后一个 1.x tag 所在的提交（本 Task 还一个提交都没有），`check-version` 会报"缺 2.0.0"——先完成第 4 步的提交再跑；`migrate-idempotent` 不在这里跑，改为 `make -C $ROOT test-db-init ID=$ID` 绿，见 4.16）。Python / TS 用各自的同名目标。
- [ ] **6.4 机械核对再跑一次**：`bash $ROOT/dev/phase-06/tools/component-check.sh $ID; echo "exit=$?"` → `exit=0`（第 5 步写完文档之后、交接提交之前的最后一次；`history_allow` 的 `ℹ️` 行原文进记录）。
- [ ] **6.5 项目门禁**：
  ```bash
  bash $ROOT/infra/scripts/project-lock.sh -- make -C $ROOT gates > $S/gates.log 2>&1; echo "exit=$?"   # 读全文，不只看 tail
  ```
  `make gates` 跑 docs-boundary、docs-mirror 和 be-acceptance（父仓库钉的 v0.4.7）的全部门禁：import-scan、system-client-scan、bare-route-scan、events-breaking-scan、data-scope-test-scan、dependency-version-scan、service-hostname-scan、**config-key-scan**（`configSchema` 键名大写下划线、不以 `_ENDPOINT` 结尾、不撞保留名；2.x 组件与外壳一律判红，还在 1.x 的组件的命名违规只警告）、**openapi-additive-scan**（REST 契约对比上一个发布 tag 只增不改），最后 `brickkit up --dry-run`。
  通过：**本组件**零违规——每个 `✗` 行都看路径，指向 `components/$ID/` 的必须修掉；`config-key-scan` 里本组件不出现（已是 2.0.0，按严格规则判）；`openapi-additive-scan` 里没有本组件的 `✗` 行，也没有指向本组件的"跳过 / 没有对比"提示（`ℹ` / `⚠`；有就是本地没有发布 tag 或组件目录不是独立仓库，回到 1.2——否则这一项是假绿）。W2 提前开工、上游还没到 2.0.0 时，指向本组件依赖声明的违规记为"待 C7 前复核"，不为了过门禁改依赖版本。别的组件的违规（并行的半成品、还没迁移的 1.x 组件）不归本 Task：原文记录、交接时告诉控制者。`make gates` 遇到第一个红的门禁就停，后面的门禁没跑：这时直接跑剩下的单个门禁看本组件，`$ROOT/tools/be-acceptance/build/be-acceptance gate <门禁名> --root $ROOT`（`make gates` 第一行已把它构建好；在锁内跑）。本组件的两个发布前门禁可以提前照 ship 的写法自查（在锁内）：`… gate config-key-scan --root $ROOT --only $ID --strict` 与 `… gate openapi-additive-scan --root $ROOT --only $ID`，退出码为 0 即与 `make ship` 第 1 步同判（`--only` 下"没能对比"的 ⚠ 也判红）。本组件还没加入项目时，`service-hostname-scan` 与 `up --dry-run` 对它没有内容，第 7 步之后再看。

### 第 7 步　接入项目、构建、真机验证

> 两条命令（plan C7），都自己拿项目锁：
> ```bash
> make -C $ROOT integrate ID=$ID                                   # [INTEGRATE_OUT=<日志目录>]
> make -C $ROOT verify ID=$ID ROUTE='<受保护路径>' FOCUS=1 SEED=1    # [KEEP=1] [FORCE_BUILD=1] [OUT=<输出目录>]
> ```
> `FOCUS` / `SEED` / `KEEP` / `FORCE_BUILD` 只有值为 `1` 才生效（`0` 或别的值等于没设）；`ROUTE` 可写 `'<METHOD> <路径>'`，省略方法时是 `GET`；组件没有 `seed` 目标时 `SEED=1` 记一行写明原因的 SKIP。两条命令开头都核对 `BrickKit CLI v1.1.0`（不对就 exit 2，不等锁）。7.1–7.4 是它们做了什么、看什么；每条后面的手工命令只用于排障。终端输出里的汇总表、输出目录路径原文贴进记录。

- [ ] **7.1 `make integrate`**：依次做六步，任一步失败 exit 1 并写明第几步：
  1. 连库组件（`registry/schemas.tsv` 有它）：`make dev-env db-init`。详细输出（约 1000 行 psql）写进 `<INTEGRATE_OUT>/db-init.log`，`INTEGRATE_OUT` 默认 `$BE_SCRATCH/integrate/$REPO-<时间>/`（integrate 不读通用的 `OUT`：上一次 `make verify` 留在环境里的 `OUT` 不会把日志带偏）；终端只打 `✓` / `✗` / `⚠` 结果行与它们下面列出的变量名（只有名字）。失败时打日志最后 30 行。
  2. `brickkit add $ID@2.0.0 --yes`（`brickkit.yaml` 里已是这个版本就跳过；是别的版本就 `upgrade --dry-run` 再 `upgrade --yes`）。输出形态：`➕ Adding <id>@2.0.0`、`✅ <id>@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml[, deploy.local.yaml]`、`📝 Config skeletons: config/$REPO.yaml`；`git diff AGENTS.md` 里组件表多一行（版本 2.0.0，Home 列是 `metadata.repository`）。`brickkit add` 会重排 `brickkit.yaml` / `deploy.yaml` 的注释（V-13），不影响行为。
  3. `config-fill.py $ID`：按 §2.4 填 `config/$REPO.yaml`。需要人给值的 required 键会被列出、exit 3（integrate 停在这一步）——按本 Task 的"配置值"一栏给值后重跑 `integrate`（已加入的不会重复 add，已有值的键不会被覆盖）：
     ```bash
     bash $ROOT/infra/scripts/project-lock.sh -- python3 $ROOT/infra/scripts/config-fill.py $ID --set 'KEY1=VALUE1' --set 'KEY2=VALUE2'   # 每个键一个 --set；值里有 $ 时用单引号
     ```
     写成 `$var:X` 的 required 键按 brickKit 的取值规则判：`X` 在 `deploy.yaml` 的 `vars:`（同名优先）与 `config/vars.yaml` 里都没有 → 算缺；`X` 是空串或 null → brickKit 退回 schema 默认值，没有默认值才算缺（引用照样写，去 `config/vars.yaml` 补值）。`secret: true` 的键只接受 `${VAR}` / `file://…` / `$var:`，明文会被拒绝；密钥值进 `.env`（不提交），多行密钥进 `.secrets/<repo>/`。
  4. `teardown-sync.py`：让 `deploy.teardown.yaml` 与 `deploy.yaml` 一致（`brickkit add` 不维护它）。之后单独核对用 `make -C $ROOT teardown-sync CHECK=1`（拿锁；不一致 exit 1 并打印差异），不要直接跑 `python3 infra/scripts/teardown-sync.py`（不拿锁）。
  5. `brickkit lint --strict $ID`（重复键、未定义的 `$var:`、`.env` 缺变量、文档警告）。
  6. `brickkit up --dry-run`：本组件 `starting (…)`，没有 `CONFIG_INVALID`、没有未定义的 `$var:` / `${…}`。
  最后列出父仓库里被改动的项目文件（控制者按路径提交，实现者不提交）。
  通过：`✓ integrate $ID@2.0.0 完成`、exit 0。排障：`grep -n -A30 "$SVC:" .brickkit/generated/compose.yaml` 能看到 `PG_USER=$ROLE`；配置里用了 `host.docker.internal` 的容器有 `extra_hosts: host.docker.internal:host-gateway`。
- [ ] **7.2 `make verify`**：只起本组件的依赖闭包（外加已加入项目的 infra/authz、infra/iam-casdoor），按顺序检查，最后打印汇总表（检查项 / 结果 / 原因 / 日志）并写进 `<OUT>/summary.md`（`OUT` 默认 `$BE_SCRATCH/verify/$REPO-<时间>/`）：
  1. **构建**：`brickkit build $ID`（`FORCE_BUILD=1` 加 `--force`：版本没变、代码改过时用——镜像 tag 只认版本号）；闭包里缺镜像的依赖也构建；镜像里有 `sh` + `wget` 与 `/app/component.yaml`。
  2. **只起闭包**：在项目根生成 `deploy.verify.yaml`（`deploy.yaml` 的副本，闭包外的条目写成 `mode: disable`，闭包里没写 `mode` 的顶层条目写成 `enabled`），`brickkit up -f deploy.verify.yaml`；每个 `*-migration` 容器 `Exited (0)`（迁移以 `PG_USER=$ROLE` 登录，这一行通过也就证明了登录角色和 `.env` 里的密码对得上）；本组件 `running (healthy)`。
  3. **健康与鉴权**：`/healthz` → `200`；`ROUTE` 不带 token → `401` 或 `503`（`403` 判 FAIL：`IAM_JWKS_URL` 没注入进去）；authz 与 iam-casdoor **都**在项目里时，用 seed 账号 `dev.superuser` 的真 token 再打一次，期望 `200`（Casdoor 里还没有这个用户时记 SKIP"iam 种子还没灌"；别的取 token 失败都是 FAIL）；不都在时这一行 SKIP，写明"只验不带 token"。
  4. **种子数据**（`SEED=1`，见 7.3）。
  5. **跨组件测试**：Go 组件跑 `make test-cross ID=$ID`（依赖容器此时在跑；强依赖的 gRPC 桥接到宿主机端口），第 4.17 步 SKIP 掉的跨组件测试这里必须 PASS（需要时手工 `bash $ROOT/infra/scripts/project-lock.sh -- make -C $ROOT test-cross ID=$ID ARGS="-run <名> -v"` 核对，在 `KEEP=1` 留下的容器上）；Python / TS 记 SKIP"不是 Go 组件"。
  6. **focus**（`FOCUS=1`，见 7.4）。
  7. **收尾**：`brickkit down -f deploy.verify.yaml`（还有本项目容器就再 `brickkit down`），确认 `docker ps` 里没有本项目的容器，然后**删掉项目根的 `deploy.verify.yaml`**（副本留在 `<OUT>/deploy.verify.yaml`）。`KEEP=1` 时不收尾：容器和项目根的 `deploy.verify.yaml` 都留着，用完在锁内 `brickkit down -f deploy.verify.yaml` 并删掉它。中断（Ctrl+C、SIGTERM、超时）时 EXIT 陷阱照样收尾。
  通过：exit 0，汇总表每行都是 `PASS` 或写明原因的 `SKIP`（例如"infra/authz 与 infra/iam-casdoor 没有都加入项目，只验不带 token"）。
  排障（verify 做的事的手工版，在锁内）：`brickkit status -f deploy.verify.yaml`；`docker ps -a --format '{{.Names}}\t{{.Status}}' | grep "$REPO"`；迁移容器日志最后一行是 SDK 的 `"msg":"迁移结束"` 带 `"outcome":"ok"`；`docker run --rm --network $NET curlimages/curl -s -o /dev/null -w '%{http_code}\n' http://$SVC:<HTTP 端口>/healthz`；真 token：`TOKEN=$(export ROOT NET; source $ROOT/infra/scripts/lib/seed-net.sh; with_toolbox $NET; get_app_jwt dev.superuser)`。日志都在 `<OUT>/` 下（`build.log`、`up.log`、`migration-*.log`、`container-*.log`、`http.log`、`seed.log`、`test-cross.log`、`focus.log`）。
- [ ] **7.3 种子数据：`SEED=1`**：健康检查通过之后、跨组件测试与收尾之前，verify 在容器还起着的时候跑 `make -C components/$ID seed`（清掉 `make verify` 传下来的 `MAKEFLAGS`，`ID=` / `OUT=` 不会覆盖组件 Makefile 的同名变量），输出进 `<OUT>/seed.log`；seed 失败算 FAIL（收尾照做）；组件 Makefile 没有 `seed` 目标、或容器没起来，记写明原因的 SKIP。种子灌进 `brickkit_db`，收尾 `down` 之后数据还在。不要再从 `<OUT>` 把 `deploy.verify.yaml` 拷回项目根、手工 `up` / `seed` / `down`——那是 `SEED=1` 之前的做法。种子脚本里没有写死的 `1-0-N` 服务名与 `DATABASE_*`（4.9）；种子数据要能让本 Task 新增的接口有东西可看（各 Task 写明）。需要先灌别的组件的种子（例如 iam 的 `dev.superuser`）时，按本 Task 的说明在 `KEEP=1` 留下的容器上、锁内跑。
- [ ] **7.4 focus：`FOCUS=1`**（容器形态之后再跑，P8）：verify 先 `brickkit local on`，再后台跑 `brickkit up --focus $ID`——本组件以 `mode: local` 进程在宿主机上从源码起（`local.runCommand`），依赖照样是容器；轮询宿主机 `http://localhost:<端口>/healthz` → `200`（端口取 focus 日志里 `<svc> listening on port N` 那一行，没有就用组件声明的端口）；然后停掉 focus 进程组、`brickkit up --all --dry-run`（清除 focus）、`brickkit local off`。
  - **`host.docker.internal`（R39）**：brickKit 只改写它自己算出的 `*_ENDPOINT`，手写在 `config/` 里的地址原样注入本机进程（`brickkit docs 10-troubleshooting/02-local-debug-issues`，"The process on this machine can't reach an address written in config"）——它**不会**把 `host.docker.internal` 换成 `localhost`。宿主机上 `host.docker.internal` 解析不了，而依赖容器与本机进程共用 `vars:`，也不能写 `localhost`。所以 verify 把 `config/vars.yaml` 里含 `host.docker.internal` 的值换成 Docker host-gateway 的实际 IP（`docker run --add-host hgw:host-gateway … getent hosts hgw`），写进 `deploy.local.yaml` 的 `vars:`（部署文件里已有的同名 vars 不覆盖），两边都可达。**只适用于 Linux 原生 Docker**，也只在它上面验证过；Docker Desktop / rootless 下这个 IP 宿主机未必可达，focus 会大声 FAIL，不会静默通过。查不到 host-gateway IP 时打印降级提示、不改写。是否是 brickKit 的问题记为 V-12，T18（第一个有容器依赖的 focus）再验。
  - `deploy.local.yaml` 在**所有退出路径**上还原（含中断、`KEEP=1`、`local off` 失败）：原来没有 → 删掉 verify 建的副本；本地模式开着 → 备份、改写、原样恢复；本地模式关着却留有旧副本 → 先移到 `<OUT>/deploy.local.yaml.stale`，让 `local on` 从 `deploy.yaml` 新复制一份，收尾时放回。
  - focus 只验 `/healthz`：authz / iam 的地址是容器服务名（`infra-authz-2-0-0` 等），宿主机进程解析不了，受保护路由在 focus 下验不了，带 token 的检查只在容器形态（7.2 第 3 项）做。focus 不跑迁移（`⚠️ Note: a mode: local component's database migration won't run automatically`），容器形态已经跑过。
  - 宿主机端口默认就是组件声明的主端口，被占才另分配；SDK 监听的是 `component.yaml` 里的端口，两者不一致就是问题，记录下来。
- [ ] **7.5 验证之后**：`brickkit status` 没有运行中的组件容器；`brickkit local status` 显示 `Local mode: off`（verify 验证前本地模式是开的，汇总行会写明"已关闭"）；项目根没有 `deploy.verify.yaml`（`KEEP=1` 除外，见 7.2 第 7 项）。之后组件代码或文档又改过，就带 `FORCE_BUILD=1` 重跑 `make verify`（8.6）。

### 第 8 步　交接与发布

> 实现者只做 8.1、8.2（提交不推送）并交接。`make ship` **只有控制者运行**（`make -C $ROOT ship DIR=components/$ID NOTES=$S/notes-2.0.0.md`，`DRY_RUN=1` 只做只读检查）：它先跑**发布前门禁**（`openapi-additive-scan` 与 `config-key-scan`，`--only $ID --strict`，看退出码），发布基线或门禁工具不可信时拒绝（远端最高的、不在 HEAD 上的发布 tag 本地没有 / 指向别的提交 / 不是 HEAD 的祖先；`tools/be-acceptance` 有改动或不是父仓库钉的提交）；拒绝或门禁红时还没推 `main`、没打任何 tag。全是控制者侧的事。然后按顺序推 `main`、打契约包 tag（Go，需要时）、`brickkit release`、`v` tag（Go）、外壳视角拉取检查（Go），第一处失败即停，已推送的东西绝不回滚、删除或移动。8.3–8.5 的手工命令保留作排障与原理参考，实现者不要执行任何推送类命令。所以 8.1 的发布说明与 6.5 的 `make gates` 要在交接前就是干净的：ship 的门禁与 `make gates` 里的同名门禁判的是同一件事，只是更严、只看本组件。

- [ ] **8.1 发布说明**（放组件目录**外**，否则 release 的"目录干净"检查不过）：`$S/notes-2.0.0.md`。它会变成 `2.0.0`、`v2.0.0`、契约包三个 tag 的注释，**推送后改不了**。骨架由 3.0 的 `migrate-manifest.py --write` 写好（只在不存在时写一次），人只补后两节：
  ```markdown
  <id> 2.0.0

  ## 升级前必须做（破坏性变更）

  - 配置键全部改为大写下划线的环境变量名，config/<repo>.yaml 要按新键重写：`pgSchema` → `PG_SCHEMA`，…（旧键 → 新键逐条写在这里，就是 --write 打印的映射；BRICKKIT.md 不写这份对照，R42）。不再读取平台注入的 DATABASE_* / MQ_*。
  - 数据库与消息改为组件自己声明的配置：PG_*（登录角色 <role>、PG_SCHEMA 默认值、角色在 schema 上要有 USAGE + CREATE）与 NATS_URL。
  - 必填性变化：`AUTHZ_BUNDLE_URL`、`IAM_JWKS_URL` 改为必填（1.x 可以不配）；R27 的键"改为必填（1.x 默认为空）"；表外新键"新增配置键 X（必填 / 默认 v）"。
  - Go 模块路径改为 github.com/brickKit/<repo>/v2；镜像由 brickkit build 构建，名称 <repo>:2.0.0。

  ## 新增

  - <本 Task 的新接口、新字段、新权限键、新配置键的用途>

  ## 修复

  - <修掉的真实 bug（各有先红后绿的提交）>
  ```
  核对：
  - "升级前必须做"一节以生成的为准：最后一次 `--write` 如果打印了 `⚠️ … 升级前必须做 … 对照 …notes-2.0.0.generated.md 更新`，就 `diff $S/notes-2.0.0.md $S/notes-2.0.0.generated.md` 把这一节改对（overrides 后来又加了键时会出现）。你有意补进这一节的行（例如"迁移状态表沿用 `schema_migrations_<schema>`，已有库直接升级"）也会让它出现——确认差异只是这些行即可，交接时在记录里写明。
  - 只讲 2.0.0 相对 1.x 的变化；不写"不再有默认值"（1.x 的这两个键本来就没有默认值，只是不在 required）；删掉不适用的条目，通读一遍。
- [ ] **8.2 组件仓库提交（不推送）**：
  ```bash
  cd $C && git status --short          # 只应有本次的改动；build/、.venv/、node_modules/ 已忽略
  git add -A && git commit -F $S/commit-msg.txt && git log --oneline -1
  ```
  通过：`git log` 第一行就是这次的提交，工作区干净。**不 `git push`、不打 tag。** 向控制者交付：`git -C $C log --oneline` 里本 Task 的全部提交、发布说明路径（以及最后一次 `--write` 有没有 ⚠️）、`component-check.sh` 的 `exit=0` 与 `history_allow` 条目（有的话）、6.5 `make gates` 里别的组件的违规（有的话）、`verify` 汇总表与输出目录、`go-v2.sh` 打印的 `📌` 契约包 tag 需求（或"不需要"）、`manifest-overrides.yaml` 本组件那一段的改动（父仓库文件，控制者提交）。
  提交切分照试点：机械迁移（第 3、4A 步）一个；重构一个；每个红绿循环一个（红、绿各一个也可以）；代码注释改写一个；测试注释单独一个（写明断言未动）；`Makefile` / `Dockerfile` / 种子脚本一个；文档（第 5 步）一个。这是正式文档 01-development-workflow.md#commits 的"一个红绿循环一个提交、改测试单独一个提交"，优先于 spec §11"组件仓库每个组件一个提交"。
- [ ] **8.3 契约包 tag（控制者，`make ship` 第 2 步；第 4.14 步 `gen/` 有变化时；形态 B 刚拆出来的组件第一次一定要打 `v1.0.0`）**：先打、先推，再发组件版本（三个 tag 打在同一个提交上）。tag 的版本必须等于根 `go.mod` 里 require 的契约包版本（第 4.3 步），推送之前外壳视角拉不到（实测：`unknown revision gen/infra/notification/v1.0.0`）；契约包 tag 已在远端时，`ship` 校验 `git diff --quiet <tag> HEAD -- gen/<d>/<n>`（已发布的契约包必须与 HEAD 逐字节一致，06a N-3）：
  ```bash
  git tag -a gen/<domain>/<name>/v<契约包版本> -F $S/notes-2.0.0.md && git push origin gen/<domain>/<name>/v<契约包版本>
  ```
- [ ] **8.4 brickKit 发布（控制者，`make ship` 第 3 步）**：
  ```bash
  cd $C && brickkit release --notes-file $S/notes-2.0.0.md
  git cat-file -t 2.0.0 && git ls-remote --tags origin 2.0.0
  ```
  通过：没有 `RELEASE_BLOCKED`；`git cat-file -t 2.0.0` 输出 `tag`（带注解）；`ls-remote` 有一行。推送失败时 brickKit 会自动删掉本地 tag——失败由控制者处理（§7），不手工补打。
- [ ] **8.5 Go 组件补 `v` tag 并验证可被拉取（V-06；控制者，`make ship` 第 4、5 步）**：
  ```bash
  cd $C && git tag -a v2.0.0 -F $S/notes-2.0.0.md && git push origin v2.0.0
  test "$(git rev-parse '2.0.0^{commit}')" = "$(git rev-parse 'v2.0.0^{commit}')" && echo "两个 tag 在同一提交"
  P=$(mktemp -d) && cd $P && go mod init probe >/dev/null 2>&1 \
    && printf 'package main\nimport _ "github.com/brickKit/%s/v2/backend/module"\nfunc main(){}\n' $REPO > main.go \
    && go get github.com/brickKit/$REPO/v2@v2.0.0 && go build ./... && echo "外壳视角拉取+编译 OK"
  go list -m all | grep "brickKit/$REPO"                            # 只应有 …/$REPO/v2 v2.0.0 与 …/$REPO/gen/<domain>/<name> v1.x.y
  go list -m github.com/brickKit/$REPO/v2@2.0.0 2>&1 | head -2      # 预期失败：不带 v 的 tag 不是 Go 版本
  ```
  通过：`两个 tag 在同一提交`、`外壳视角拉取+编译 OK`（`ship` 在代理刚收到新 tag 时最多重试 3 次、间隔 30 秒）；`go list -m all` 只有那两行（契约包是 8.3 推的版本，没有 `=>` 本地替换；出现不带 `/v2` 的 `github.com/brickKit/<repo> v1.x.y` 就是 C-1 那种回退）；最后一条报错（原文记录）。最小复现失败（典型：`unknown revision v0.0.0` 指向契约包，或 `module path must match major version`）就由控制者处理，别继续下游组件——这是 13 个组件和 3 个 Go 外壳共用的机制。⚠️ 推送到 GitHub 的 `v` tag 一旦被 Go 模块代理抓取就永久缓存，绝不能移动或删除重打。
- [ ] **8.6 镜像与提交一致**：`make verify` 之后组件代码或文档又改过的（包括只改注释），交接前 `make -C $ROOT verify ID=$ID ROUTE=… FORCE_BUILD=1` 重跑一遍（镜像 tag 只认版本号，不加 `--force` 时 `brickkit build` 跳过已有镜像，容器跑的还是旧代码）。
- [ ] **8.7 父仓库（控制者）：submodule 指针与项目文件**：实现者不在父仓库提交任何东西。`make ship` 通过后，控制者核对并按路径提交、推送（R31）：
  ```bash
  cd $ROOT
  git -C $C describe --tags --exact-match                  # 2.0.0 或 v2.0.0
  git status --short -- components/$ID brickkit.yaml deploy.yaml deploy.teardown.yaml config/ AGENTS.md registry/
  git commit -F <msg> -- <路径…> && git log --oneline -1 && git show --stat HEAD | head -20
  git submodule status components/$ID
  ```
  路径：`components/$ID`（指针）、`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/$REPO.yaml`（`config/vars.yaml` 有改时也带上）、`AGENTS.md`（组件表）、`registry/permissions.tsv` / `registry/data-scopes.tsv`（有新键时）、`dev/phase-06/tools/manifest-overrides.yaml`（本组件那一段改过时）、`dev/test-records/06b/$REPO.md`。**不带** `.env`、`.secrets/`、`deploy.local.yaml`、`deploy.verify.yaml`，也不带别的工作线的路径。共享文件里同时有别的已接入、未发布组件的改动时，先 `git diff -- <文件>` 核对；只含已发布组件的改动才提交，否则用 `git add -p <文件>` 只暂存本组件的块，再 `git commit -F <msg>`（不带路径）。
  通过：`git submodule status` 那一行开头是空格（不是 `+`），括号里是 `2.0.0` 或 `v2.0.0`，没有 `-N-g<hash>` 后缀；`make version-check` 对本组件不报漂移。

### 第 9 步　记录

- [ ] **9.1** 在 `dev/test-records/06b/$REPO.md` 补齐：步骤（命令 + 关键输出原文 + 耗时）、现象（符合 / 不符合预期）、卡点与绕过（读了哪个 skill / 文档 / `--help`，是否翻了 brickKit 仓库）、结论、反馈候选（进 to-verify 还是直接进信箱、理由）。
- [ ] **9.2** 翻过 brickKit 源码的，在记录里写一条知识缺口：日期、缺的知识、当时在做什么、读了哪里、建议用什么形式下发（控制者合并进 to-verify 的 V-04 表）。
- [ ] **9.3** V 项有结论的，写在自己的记录里（实现者不改 to-verify，由控制者合并）。
- [ ] **9.4** 写一句检查点小结：版本、tag（待控制者 `make ship` 后确认）、组件提交 SHA、是否有遗留问题。

---

## 4. 外壳组装子清单

**什么时候走**：外壳要托管的成员全部已发布（2.0.0）时（`be/go-infra`、`be/py-render`、`be/go-core`、`be/go-backoffice` 各一个 Task，彼此并行，见 plan-06b "外壳"一节）。
**为什么是"成员齐了一次组装"**：brickKit 拒绝 `shell.members: []`（`MANIFEST_INVALID`："a shell must list at least one component compiled into it"；v1.1.0：`brickkit docs 04-shell/05-shell-development`——"`members: []` is `MANIFEST_INVALID` in `lint` and `add` … a new shell joins the project together with its first member"），所以外壳只能和它的第一个成员一起进 `brickkit.yaml`；06b 每个外壳都是在成员齐了之后一次性带着全部成员第一次加入。外壳第一次加入之前，它的成员一直作为独立组件运行。

| 外壳 | 端口 | 登录角色 / 密码 | 成员（`shell.members`） | 语言要点 |
|---|---|---|---|---|
| `be/go-infra` | 8224 | `shell_go_infra` / `${SHELL_GO_INFRA_PASSWORD}` | `infra/authz@2.0.0`、`infra/iam-casdoor@2.0.0`、`infra/workflow@2.0.0`、`infra/notification@2.0.0`、`integration/im-dingtalk@2.0.0` | Go；`config/vars.yaml` 的 `AUTHZ_BUNDLE_URL`/`IAM_JWKS_URL` 值不变，成员服务名从此由外壳容器的网络别名解析 |
| `be/py-render` | 8402 | `shell_py_render` / `${SHELL_PY_RENDER_PASSWORD}` | `infra/print@2.0.0` | Python；镜像要带 WeasyPrint 的系统库与中文字体 |
| `be/go-core` | 8090 | `shell_go_core` / `${SHELL_GO_CORE_PASSWORD}` | `mdm/customer@2.0.0`、`mdm/product@2.0.0`、`erp/inventory@2.0.0`、`erp/finance@2.0.0`、`erp/sales@2.0.0` | Go |
| `be/go-backoffice` | 8116 | `shell_go_backoffice` / `${SHELL_GO_BACKOFFICE_PASSWORD}` | `crm/opportunity@2.0.0` | Go |

以下用 `$SH=be/go-infra`、`$SHD=$ROOT/shell/be/go-infra`、`$SHN=go-infra` 举例。`env.sh` 只认 `components/` 下的组件（给外壳 ID 会 exit 2），外壳 Task 的每次 Bash 调用前面手工设好变量（Bash 工具不保留环境变量，§0.1）：

```bash
export ROOT=/home/zhijie/Desktop/github/be-assembly-standard BE_SCRATCH=<当前会话的 scratchpad>
export SH=be/go-infra SHN=go-infra SHD=$ROOT/shell/be/go-infra S=$BE_SCRATCH/06b/be-go-infra NET=brickkit-be-assembly-standard-net; mkdir -p $S
case ":$PATH:" in *":$HOME/go/bin:"*) ;; *) export PATH="$PATH:$HOME/go/bin" ;; esac     # 追加，不前置
bash $ROOT/infra/scripts/lib/require-brickkit.sh                                         # 不是 BrickKit CLI v1.1.0 就 exit 2
export TEST_PG_DSN="postgres://postgres:$(python3 $ROOT/dev/phase-06/tools/dotenv-pgpass.py $ROOT/.env)@localhost:5432/brickkit_test_db?sslmode=disable" TEST_NATS_URL=nats://localhost:4222   # make tier2 要用；不打印
```

外壳是独立仓库（`brickKit/be-$SHN`，0108），`$SHD` 是它在父仓库里的子模块检出：外壳文件在 `$SHD` 里提交、推送、发布，父仓库只提交子模块指针。

### 4.1 前置

- [ ] 外壳 `go.mod`（Python：`pyproject.toml`）的 SDK 先升到成员所用的版本（be-sdk-go v0.4.0 / be-sdk-python v0.4.4），与成员一致。
- [ ] 每个成员都已 2.0.0 发布并推送（Go 成员 `2.0.0` 与 `v2.0.0` 两个 tag 都在远端，`git -C <成员> ls-remote --tags origin v2.0.0` 有一行），且已作为独立组件加入项目、真机 healthy 过。
- [ ] 每个 Go 成员的契约包 tag 已推送：`git -C <成员> ls-remote --tags origin "gen/*"` 里有成员根 `go.mod` require 的那个版本（第 4.3、8.3 步）。
- [ ] 外壳 1.0.0 还没发布过：`git -C $SHD tag -l` 为空（外壳的 tag 在外壳仓库里；发布过的话版本改 1.1.0，走 4.7）。
- [ ] 外壳子模块干净且在 main 上：`git -C $SHD status --short` 为空；`git -C $ROOT submodule status shell/be/$SHN` 行首没有 `+`（检出的提交就是父仓库记录的指针）；子模块处于 detached HEAD 时先 `git -C $SHD switch main && git -C $SHD pull --ff-only`。

### 4.2 改外壳代码（成员清单三处一起改）

- [ ] **`component.yaml`**：`shell.members` 写全部成员的 `<id>@2.0.0`；`configSchema` 保持外壳自己的连接键（不放任何成员的键）。
- [ ] **Go**：
  - `main.go` 的 `shell.Registry` 一项一个成员，键是成员 ID，值是它的 `New`：
    ```go
    import (
        "github.com/brickKit/be-sdk-go/shell"
        infraauthz "github.com/brickKit/infra-authz/v2/backend/module"
        // …每个成员一行
    )
    func main() {
        shell.Main("be-go-infra", shell.Registry{
            "infra/authz": infraauthz.New,
            // …
        })
    }
    ```
  - `go.mod`：`cd $SHD && go get github.com/brickKit/infra-authz/v2@v2.0.0 …（每个成员）&& go mod tidy`；be-sdk-go 的版本与成员们用的一致（`go mod graph | grep be-sdk-go` 只应出现一个选中版本）。
  - `go build -o /dev/null ./...` 无输出（V-03 / V-06 外壳半程：外壳第一次真的从代理拉成员）。契约包解析失败（`unknown revision v0.0.0` 等）回到第 4.0–4.4 / 8.3 步修成员，不在外壳里加 `replace` 绕过。
- [ ] **Python（py-render）**：
  - `pyproject.toml` 的 `dependencies` 加 `"infra-print @ git+https://github.com/brickKit/infra-print.git@2.0.0"`，besdk 的 tag 与 infra-print 自己钉的完全相同。
  - `main.py`：`from infra_print.module import create_module`（顶层包已从 `app` 改名 `infra_print`，避免多个 Python 成员互相覆盖），`main("be-py-render", {"infra/print": create_module})`（成员入口名以 infra-print 的 `backend/infra_print/module.py` 实际导出为准）。
  - `Dockerfile` 补成员运行期需要的系统依赖：对照 `components/infra/print/Dockerfile` 的 `apt-get install` 列表（libpango、libcairo、libgdk-pixbuf、libharfbuzz-subset0、fonts-noto-cjk、fontconfig 与 `fc-cache -f`）。缺了它们镜像能构建、健康检查也绿，但渲染 PDF 时才失败或中文乱码。
  - 本地验证：`uv venv --seed -p 3.12 $S/pyvenv && $S/pyvenv/bin/pip install $SHD && $S/pyvenv/bin/python -c 'import main, infra_print.module'`（`uv venv` 不带 `--seed` 不装 pip，`$S/pyvenv/bin/pip` 不存在，实测；与 plan T21 一致）。
- [ ] **成员运行期读文件**：`grep -rnE 'os\.ReadFile|os\.Open\(|open\(' <成员>/backend --include='*.go' --include='*.py' | grep -v _test` —— 外壳镜像里没有成员的工作目录（没有成员的 `component.yaml`、`migrations/`、模板文件），读相对路径的成员必须改成 embed 或改走配置，否则合并后才坏。

### 4.3 外壳文档与配置

- [ ] `BRICKKIT.md`/`.zh.md` 的 `Shell declaration` / `外壳声明` 列出与 `shell.members` 完全相同的成员；`Purpose` 里"currently compiles in no members"之类的过渡说法删掉。
- [ ] `BRICKKIT.md`/`.zh.md` 不得引用本项目的 `registry/ports.tsv`、`make db-init`（外壳会被别的装配项目复用）；数据库授权写通用说法："装配项目为外壳建一个登录角色，并把每个成员的 `<schema>_rw` 授给它"（英文：the assembling project creates a login role for the shell and grants it each member's `<schema>_rw`）。
- [ ] `AGENTS.md`/`.zh.md` 的 Pitfalls 里"Leave `shell.members` empty…"那一行按现状改写或删除；Code map 不变。
- [ ] `make docs-check ID=be/<name>`（项目根；对应 `$SHD`）→ `0 with errors, 0 warnings`。
- [ ] 外壳登录角色拿到成员授权：`cd $ROOT && make db-init`（GRANT 来自外壳清单），然后：
  ```bash
  docker exec be-postgres psql -U postgres -d brickkit_db -tAc \
    "select r.rolname from pg_auth_members m join pg_roles r on r.oid=m.roleid join pg_roles u on u.oid=m.member where u.rolname='shell_$(echo $SHN | tr - _)'"
  ```
  通过：列出每个成员的 `<schema>_rw`。

### 4.4 加入项目、构建

- [ ] **加入**：`cd $ROOT && make integrate ID=$SH VERSION=1.0.0`（内部是 `brickkit add $SH@1.0.0 --yes`、`config-fill.py`、`teardown-sync.py`、`brickkit lint --strict`、`brickkit up --dry-run`）。手工等价：`brickkit add $SH@1.0.0`。通过（scratch 实测形态）：`➕ Adding be/go-infra@1.0.0`、每个成员一行 `🔗 <member> moved into shell be/go-infra`、`📝 Written: brickkit.yaml, deploy.yaml[, deploy.local.yaml]`、`ℹ️ Not changed: deploy.teardown.yaml; … carry the change over yourself`。`brickkit.yaml` 多一条 `kind: shell`；`deploy.yaml` 里成员嵌套到外壳条目的 `members:` 下。若没有 🔗 行、成员仍在 `deploy.yaml` 顶层，就手工把成员条目移到外壳的 `members:` 下，再 `make teardown-sync`，并在记录里写反馈候选（brickKit 文档与行为不符：`brickkit docs 04-shell/04-members-management` 说 `add` 不会把已在项目里的组件移进后来加入的外壳，scratch 实测与 v1.1.0 代码却会移）。
- [ ] **外壳配置**：`config/be-$SHN.yaml`：`PG_USER: shell_<name>`、`PG_PASSWORD: ${SHELL_<NAME>_PASSWORD}`，其余 `$var:`（`config-fill.py` 按外壳规则自动填）。
- [ ] **同步 `deploy.teardown.yaml`**：`make integrate` 已调用过 `make teardown-sync`；`make teardown-sync CHECK=1` 核对外壳条目、成员嵌套与 `deploy.yaml` 一致（不一致 exit 1 并打印差异）；`brickkit up -f deploy.teardown.yaml --ignore-shells --dry-run` 不报错。
- [ ] **构建**：`brickkit build $SH`，然后
  ```bash
  docker image inspect be-$SHN:1.0.0 --format '{{ index .Config.Labels "io.brickkit.shell.members" }}'
  ```
  通过：标签列出的成员与版本和 `shell.members` 完全一致（V-03：记录这次 `brickkit build` 是否顺利、耗时、构建上下文有没有越出外壳目录）。
- [ ] **生成检查**：`brickkit up --dry-run`。通过：没有 `IMAGE_STALE`、没有成员不匹配、没有 `depends_on` 环（有环时按报错给的三种出路选，选 `skipWaitFor` 时在记录里写明理由，plan T22）；`grep -n 'BRICKKIT_SERVED_MEMBERS=' .brickkit/generated/compose.yaml` 列出全部成员的版本化服务名；成员不再有自己的服务。

### 4.5 真机验证

- [ ] `make verify ID=$SH KEEP=1`（`KEEP` 只有值为 `1` 时生效）。外壳 ID 跑的是下面"运行期核对"与"R15"两条：镜像标签 `io.brickkit.shell.members`、每个成员的迁移容器 `Exited (0)`（迁移用成员自己的镜像跑）、外壳 `running (healthy)`、成员清单、成员 JSON、R15 三条日志检查、`RestartCount`、外壳与每个成员按自己服务名的 `/healthz`。手工命令保留作排障参考：`brickkit up`，然后 `brickkit status`。
  **verify 不做、必须手工做的**（plan H5）：每个成员带真 token 打一条受保护路由 → `200`；每个 Go 成员 `make test-cross ID=<成员>`；多行密钥（§2.3 第 6 条）逐字节核对；`make tier2`；拆回验证。它们在 `KEEP=1` 留下的容器上做，每条命令都写成 `bash infra/scripts/project-lock.sh -- <命令>`（verify 结束就释放了锁，留下的容器仍是项目状态）；做完 `bash infra/scripts/project-lock.sh -- brickkit down -f deploy.verify.yaml` 并删掉项目根的 `deploy.verify.yaml`（`KEEP=1` 时 verify 不删它），再做拆回验证。全栈（全部外壳一起）的同类核对由 T25 做。
- [ ] **运行期核对**（只看生成文件不算数）：
  ```bash
  SC=$(docker ps --filter "name=be-$SHN" --format '{{.Names}}' | head -1)
  docker exec $SC sh -c 'echo "$BRICKKIT_SERVED_MEMBERS"'
  docker exec $SC sh -c 'printf %s "$BRICKKIT_SERVED_MEMBERS_CONFIG"' | python3 -c 'import json,sys; [print(m["componentId"], m["version"], m["httpPort"], sorted(m["config"])[:6]) for m in json.load(sys.stdin)]'
  docker logs $SC 2>&1 | head -50
  ```
  通过：成员清单完整；JSON 合法、每个成员的 `config` 里是它自己的键（多行密钥完整，见 §2.3 第 6 条）；日志里每个成员都启动了。
- [ ] **R15 失败契约**（`healthy` 不等于"成员都好"：外壳 `/healthz` 只代表进程活着）：
  ```bash
  docker logs $SC 2>&1 | grep -iE '"level": ?"error"'                        # 必须为空（Go 是 "level":"ERROR"，Python 是 "level": "error"）
  docker logs $SC 2>&1 | grep -E 'module_component_id' | grep -iE 'error|panic' # 必须为空
  docker inspect -f '{{.RestartCount}} {{.State.Status}}' $SC                 # 必须是 "0 running"
  ```
  判据以 be-sdk-python README 的"外壳失败契约"原文为准（be-sdk-go 同一契约；`tools/be-sdk-python/README.md`），三类行为概括如下：
  - **启动阶段失败**——成员构造函数返回错误、外壳端口为 0、成员声明了额外端口却没返回 `RegisterGRPC`、平台下发的成员没编进外壳（Go 报"成员 <id> 在 BRICKKIT_SERVED_MEMBERS_CONFIG 里，但本外壳没有编译它（Registry 未登记）"，Python 报"…registry 没有登记它的 new_module…"）：外壳**退出**，容器反复重启，`RestartCount` 增长。
  - **端口失败**——任一成员的 HTTP / 额外端口绑定失败或服务协程意外返回：Go 外壳记"成员端口服务退出，外壳整体退出"，Python 外壳记 ERROR `成员监听/服务失败：<http 或 grpc:<name>>`、stderr 最后一行 `[<shell_name>] 成员监听/服务失败，外壳退出：…`（都带 `module_component_id`）后**非零退出**，其余成员一起下线。
  - **成员 `Start()` / 后台循环失败**（outbox pump、NATS 消费者、分区维护）：**只隔离**——Go 记 ERROR"模块后台循环退出（已隔离…）"或"…panic（已隔离…）"，Python 记 ERROR `成员任务异常退出，其余成员继续运行：start`，都带 `module_component_id`，外壳继续运行、`/healthz` 仍是 200，这个成员的后台循环一直停到外壳下次重启。这是"隔离降级"，**不是通过**：出现就按成员的故障排查，修好之前 §4 不算完成。
- [ ] **成员仍按自己的服务名可达**（手工，verify 只测 `/healthz`）：对每个成员 `docker run --rm --network $NET curlimages/curl -s -o /dev/null -w '%{http_code}\n' http://<member-svc>:<成员 HTTP 端口>/healthz` → `200`（verify 已测，排障用）；受保护路由带真 token → `200`：
  ```bash
  TOKEN=$(export ROOT NET; source $ROOT/infra/scripts/lib/seed-net.sh; with_toolbox $NET; get_app_jwt dev.superuser)
  docker run --rm --network $NET curlimages/curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOKEN" http://<member-svc>:<成员 HTTP 端口>/<该成员一条受保护的 REST 路径>
  ```
  同一外壳里成员之间的调用仍走 gRPC：每个 Go 成员 `bash infra/scripts/project-lock.sh -- make test-cross ID=<成员>` 绿（依赖此时由外壳托管）。
- [ ] **多行密钥逐字节核对**（手工；有多行或含 `$` 的值的成员，如 go-infra 的 `APP_TOKEN_SIGNING_KEY_PEM`、`PERMISSION_CATALOG`）：
  ```bash
  docker exec $SC sh -c 'printf %s "$BRICKKIT_SERVED_MEMBERS_CONFIG"' | python3 -c 'import json,sys,hashlib; m={x["componentId"]: x["config"] for x in json.load(sys.stdin)}; print(hashlib.sha256(m["<成员 id>"]["<键>"].encode()).hexdigest())'
  sha256sum $ROOT/.secrets/<repo>/<文件>          # PERMISSION_CATALOG 对照 $ROOT/registry/permissions.tsv
  ```
  通过：两个哈希相同（最后一行有无换行导致不同时，原文记录并用 `wc -c` 比较长度）。
- [ ] **合并态专属断言**（手工）：`bash infra/scripts/project-lock.sh -- make tier2`（需要 `TEST_PG_DSN`/`TEST_NATS_URL`，见本节开头的变量）；红了先读输出，判断是不是 06f 待重写的旧断言，是就记录、不改测试。
- [ ] **拆回验证**（手工，`make verify` 不做；先按上面 verify 那条在锁内 `brickkit down -f deploy.verify.yaml` 收掉 `KEEP=1` 留下的容器）：
  ```bash
  bash infra/scripts/project-lock.sh -- bash -c 'brickkit up --ignore-shells --dry-run && make teardown-up && brickkit status -f deploy.teardown.yaml; make teardown-down'
  ```
  通过：`--dry-run` 通过；`brickkit status -f deploy.teardown.yaml` 里全部成员各自 healthy；最后 `teardown-down` 已执行。
- [ ] `bash infra/scripts/project-lock.sh -- make gates`（其中 `dependency-version-scan` 会核对外壳 `go.mod` 钉的成员版本与成员 `metadata.version`，`config-key-scan` 对外壳一律按严格规则判）全绿；读法同 6.5。
- [ ] `brickkit down`。

### 4.6 发布外壳 1.0.0

- [ ] **在外壳仓库提交（实现者不推送）**：`cd $SHD && git status --short`（只应有外壳自己的文件），`git add -A && git commit -F $S/msg-be-$SHN.txt && git log --oneline -1`。
- [ ] **在外壳仓库发布（控制者：`make ship DIR=shell/be/$SHN NOTES=$S/notes-be-$SHN-1.0.0.md`）**：等价于推送 `main` 后 `cd $SHD && brickkit release --notes-file …`（说明文件在外壳目录之外）。通过：tag `1.0.0` 创建并推送（`git -C $SHD ls-remote --tags origin 1.0.0` 有一行，`git -C $SHD cat-file -t 1.0.0` 是 `tag`）。外壳没有人 import，不打 `v` tag；绝不在父仓库用 `brickkit release --path` 发布、也不在父仓库打 `be-$SHN/*` tag。
- [ ] **父仓库提交指针与项目文件（控制者）**：`shell/be/$SHN`（子模块指针）、`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/be-$SHN.yaml`、`AGENTS.md`，`git commit -F … -- <路径>`，`git show --stat HEAD` 核对；`git submodule status shell/be/$SHN` 显示 `(1.0.0)`；`make version-check` 里这个外壳一行是 `✓`。
- [ ] 发布后镜像与提交一致：发布前又改过外壳的，`brickkit build $SH --force`。

### 4.7 以后再给已发布的外壳加成员 / 换成员版本

外壳版本 +1（加成员 minor，换成员版本 patch），4.2–4.6 同样走一遍（外壳仓库里提交、发布 `<新版本>`，父仓库提交新指针），项目侧用 `brickkit upgrade $SH@<新版本> --dry-run` 再去掉 `--dry-run`（不是 `add`），`brickkit up` 遇到旧镜像会报 `IMAGE_STALE`。成员版本变化时外壳必须跟着发版（[0108]）。

---

## 5. 全栈集成与收尾（plan-06b 的集成 Task 用；每个组件 Task 不做）

- [ ] 所有组件第 1–9 步已勾完；补齐了外壳的，§4 已勾完。
- [ ] 项目级检查：`make registry-check`、`make docs-boundary`、`bash infra/scripts/project-lock.sh -- make gates`（全部组件都到 2.x 之后，再跑一次 `tools/be-acceptance/build/be-acceptance gate config-key-scan --root . --strict`，应为 0 条）、`make version-check`、`brickkit lint --all --strict`、`brickkit up --dry-run`。
- [ ] 全量真机：`brickkit up`（全部组件）→ `brickkit status` 全部 healthy → 跨组件路径各打一次（受保护路由带真 token）→ 各组件 `make seed` 跑通（种子数据规则见 05-data.md）。`make tier0` 会临时停掉 postgres，并假设 `mdm/customer` 暴露在宿主机 8080（需要在 `deploy.local.yaml` 里给 mdm/customer 写 `expose: true`）；红了先判断是不是 v0 时代的假设，是就记录交 06f。
- [ ] 业务闭环：`make seed-data` 跑通后，确认至少一个 WON 商机有对应订单（`source_opportunity_id` 指向它、商机 `order_id` 回填）、订单确认产生了库存预留、财务有对应应收凭证；每一环的查询命令与结果原文进记录。
- [ ] `brickkit down`；`brickkit local off`。
- [ ] 已发布 2.0.0 的组件后来又改过的（返工、修 bug），用 `make bump-version PLAN=…`（dry-run → `APPLY=1`）传播版本并按 `version-bump-ship` 发布（`make ship`），再 `make integrate ID=<id> VERSION=<新版本>`；不要手改下游依赖或外壳成员版本。
- [ ] 记录写完；V 项结论、知识缺口、反馈候选由控制者合并进 to-verify。父仓库由控制者按路径提交并推送。

---

## 6. V 项与拍板项

### 6.1 V 项在哪一步实测

试点已验完 V-01（结论：v1 静默接受驼峰键 → 改成 be-acceptance 的常设门禁 `config-key-scan`，R45）、V-07、V-09，组件 Task 不再做这些探针。剩下的：

| V 项 | 在哪一步 | 做法摘要 | 结论写到 |
|---|---|---|---|
| V-12 focus 的本机进程与依赖容器共用 `vars:` | T18 erp/sales 的 7.4（第一个有容器依赖的 focus） | 看 verify 的 host-gateway 改写（R39）在有依赖时是否够用；原文记录 focus 日志与汇总行 | 自己的记录（控制者合并进 to-verify V-12） |
| V-06 Go 双 tag | 外壳半程：go-infra 4.2（外壳真实拉成员） | 记录 `go get …/v2@v2.0.0` 与契约包解析的每一处摩擦 | 自己的记录 |
| V-03 外壳 `brickkit build` | go-infra 4.4（Go 首个）；py-render 4.4（Python 首个） | 首次带成员 `brickkit build`，核对 `io.brickkit.shell.members` 标签 | 自己的记录 |
| V-13 `brickkit add` 重排注释 | 每个组件的 7.1 | `remove` / `upgrade` 时也观察；原文记录前后 diff | 自己的记录 |
| V-04 知识缺口 | 全程 | 每次不得不读 brickKit 源码就写一条（0.2） | 自己的记录 |

### 6.2 已定的裁定（实现者照做；全文在 plan-06b"预设裁定"与 `dev/test-records/06b/T8-pilot-review.md`）

- **P1–P12 全部维持**（R38）：P1 `AUTHZ_BUNDLE_URL` / `IAM_JWKS_URL` required、无默认值；P2 `PG_SCHEMA` 带默认值且 `config/` 里写字面量；P3 契约包一律嵌套模块、不带 `/v2`、形态 B 第一个 tag `v1.0.0`；P4 迁移入口用 be-sdk-go v0.4.0 的 `migrate` 包；P5 `assembly.yaml` 删 `version` / `shell` / `asset`，其余保留；P6 提交 `.claude/skills/brickkit-component/`；P7 自有密钥 `${<UREPO>_<KEY>}`；P8 先容器、后 focus；P9–P12 见 plan。
- **R39** focus 的 `host.docker.internal` 改写（7.4）。**R41** `.proto` 旧注释等下一次真实契约变更（4.14）。**R42** 旧键 → 新键只写在发布说明（5.1、8.1）。**R43** mdm/customer 的 Makefile 是 Go 模板（4.7）。**R44** PATH 一律追加、入口脚本断言 `BrickKit CLI v1.1.0`（§0.1、1.4）。**R45** `config-key-scan`、`openapi-additive-scan` 是常设门禁（6.5、第 8 步）。**R47** 12 个组件都要重复的人工步骤已进脚本，组件 Task 只在脚本不覆盖的地方用人工判断。

---

## 7. 停止条件

控制者裁定并记录；只有 brickKit 严重 bug 才停（brickKit 的实际行为与它的文档或 skill 不符，并且挡住了任务、项目内没有正当解法，例如 `release` 把 tag 打在错误的提交上、`up` 生成的 compose 文件本身是坏的、`lint`/`up` 崩溃；定义见 plan-06b "执行方式"）。此时控制者停下告诉用户，并写一条可复现的反馈草稿。

其它一切由控制者裁定并记录，不停：测试红（先按 06-testing.md 的 When stuck）、边界与契约取舍、新增事件链（按 P9 等预设裁定）、迁移权限问题（1.6）、别的工作线挡路。实现者遇到这些，在记录里写清卡在哪、引用哪份文件哪一节，然后向控制者上报。

**仍然不做**（真遇到了先告诉用户）：新建或删除 GitHub 仓库；强推；移动或删除已推送的 tag（`v` tag 一旦被 Go 模块代理抓取就永久缓存）。

---

## 8. 过程记录模板：`dev/test-records/06b/<repo>.md`

每个组件、外壳、集成任务各一份，文件名用仓库名（如 `mdm-customer.md`、`be-go-infra.md`）。格式遵循 spec §10。

```markdown
# 06b <组件或外壳>：过程记录

## 概况

- 日期：
- brickKit：`brickkit version` 原文（应为 `BrickKit CLI v1.1.0`）
- SDK：be-sdk-go vX / be-sdk-python vX / be-sdk-ts vX
- 基础资源：`make check` 结论
- 组件与版本：<id> 1.x.y → 2.0.0（组件提交 SHA、tag：2.0.0 / v2.0.0 / gen/…）
- 交接给控制者的内容：见 8.2（提交、发布说明与有无 ⚠️、`component-check` 结果与 `history_allow`、别的组件的门禁违规、`make verify` 汇总表与输出目录、`📌` 契约包 tag 需求、overrides 改动）

## <组件 id>

### 目标

本组件按 component-loop 重建到 2.0.0；补 frontend-needs §2.x 的 <接口>；实测 <V 项>。

### 环境

brickKit 版本、部署目标（docker）、拓扑（独立 / 外壳）、本组件与依赖的版本、本地模式开关状态。

### 步骤

（按 component-loop 的步号记；每条：命令、关键输出原文〔不截断、不只取 tail〕、耗时）

- 1.1 …
- …

### 现象

- 符合预期的：
- 不符合预期的：

### 卡点与绕过

卡在哪、怎么排查的、读了哪个 skill / 文档 / `--help`、是否不得不翻 brickKit 仓库（翻了就同步写进 to-verify 的 V-04 表）。

### V 项

- V-xx：做法、原文输出、结论（已同步到 to-verify：是 / 否）

### 结论

一句话：完成 / 未完成，遗留什么。

### 反馈候选

- <现象> → to-verify 还是直接进信箱，理由。

## 外壳组装：<shell id>（外壳 Task 用）

（同样的 目标 / 环境 / 步骤 / 现象 / 卡点与绕过 / V 项 / 结论 / 反馈候选）

## 小结

- 完成：
- 需要控制者裁定的：
- 遗留到后续 Task 或下一阶段的：
```

---

## 9. 附录

### 附录 A：生成 §1.1 / §2 表格的脚本

在仓库根目录运行（只读，不改任何文件）。表格是对**重写前**的 `component.yaml` 跑的结果；需要复核时用 `git -C components/<id> show <旧 tag>:component.yaml` 取旧文件。

**A.1 旧键 → 新键（§2.1）**

```python
"""从 14 个组件的真实 component.yaml 生成 configSchema 旧键 → 新键对照表（markdown）。"""
import glob, re, yaml
ROOT = '/home/zhijie/Desktop/github/be-assembly-standard/'
SHARED = {'pgSchema': 'PG_SCHEMA', 'iamJwksUrl': 'IAM_JWKS_URL',
          'authzBundleUrl': 'AUTHZ_BUNDLE_URL', 'otelBaseUrl': 'OTEL_BASE_URL'}
SECRET_HINT = re.compile(r'(Password|Secret|SigningKey)', re.I)
def snake(k):
    s = re.sub(r'(?<=[a-z0-9])([A-Z])', r'_\1', k)
    s = re.sub(r'(?<=[A-Z])([A-Z][a-z])', r'_\1', s)
    return s.upper()
rows = []
for p in sorted(glob.glob(ROOT + 'components/*/*/component.yaml')):
    m = yaml.safe_load(open(p))
    cid, ver = m['metadata']['id'], m['metadata']['version']
    cs = m.get('configSchema') or {}
    req = set(cs.get('required') or [])
    res = [r['kind'] for r in ((m.get('dependencies') or {}).get('resources') or [])]
    for k, v in (cs.get('properties') or {}).items():
        new = SHARED.get(k, snake(k))
        d = v.get('default', '—')
        d = '`""`' if d == '' else (f'`{d}`' if d != '—' else '—')
        sec = '**是**' if SECRET_HINT.search(k) else '否'
        rows.append((cid, ver, f'`{k}`', f'`{new}`', d, '是' if k in req else '否', sec))
    if res:
        rows.append((cid, ver, '`resources: ' + ','.join(res) + '`',
                     '删除；改为声明 `PG_*`' + (' + `NATS_URL`' if 'mq' in res else ''), '—', '—', '—'))
print('| 组件 | 旧版本 | 旧键 | 新键 | 旧默认值 | 旧 required | 新 secret |')
print('|---|---|---|---|---|---|---|')
for r in rows:
    print('| ' + ' | '.join(r) + ' |')
```

**A.2 每组件目标形态（§2.2）**

```python
"""每个组件重写后 configSchema / dependencies 的目标形态（由旧 component.yaml + registry 推导）。"""
import glob, re, yaml
ROOT = '/home/zhijie/Desktop/github/be-assembly-standard/'
SHARED = {'pgSchema': 'PG_SCHEMA', 'iamJwksUrl': 'IAM_JWKS_URL', 'authzBundleUrl': 'AUTHZ_BUNDLE_URL', 'otelBaseUrl': 'OTEL_BASE_URL'}
SECRET = re.compile(r'(Password|Secret|SigningKey)', re.I)
def snake(k):
    s = re.sub(r'(?<=[a-z0-9])([A-Z])', r'_\1', k); return re.sub(r'(?<=[A-Z])([A-Z][a-z])', r'_\1', s).upper()
schemas = {}
for line in open(ROOT + 'registry/schemas.tsv'):
    if line.startswith('#') or not line.strip(): continue
    repo, schema, role, _ = line.rstrip('\n').split('\t'); schemas[repo] = (schema, role)
print('| 组件 | 依赖（全部改成 `@2.0.0`） | 新 required | 带默认值的键 | secret | `PG_SCHEMA` 默认值核对 | 删除的旧字段 |')
print('|---|---|---|---|---|---|---|')
for p in sorted(glob.glob(ROOT + 'components/*/*/component.yaml')):
    m = yaml.safe_load(open(p)); cid = m['metadata']['id']; repo = cid.replace('/', '-')
    dep = m.get('dependencies') or {}; cs = m.get('configSchema') or {}
    props = cs.get('properties') or {}; oldreq = set(cs.get('required') or [])
    res = [r['kind'] for r in (dep.get('resources') or [])]
    deps = [(d['id'].split('@')[0] + '（optional）') if isinstance(d, dict) else d.split('@')[0] for d in dep.get('components') or []]
    req, dflt, sec = [], [], []
    if 'database' in res:
        req += ['PG_HOST', 'PG_DATABASE', 'PG_USER', 'PG_PASSWORD']; dflt += ['PG_PORT=5432']; sec.append('PG_PASSWORD')
    if 'mq' in res: req.append('NATS_URL')
    for k, v in props.items():
        nk = SHARED.get(k, snake(k))
        if nk in ('AUTHZ_BUNDLE_URL', 'IAM_JWKS_URL') or k in oldreq or 'default' not in v:
            req.append(nk)
        else:
            dv = v['default']; dflt.append(f'{nk}={dv!s}' if dv != '' else f'{nk}=""')
        if SECRET.search(k): sec.append(nk)
    chk = '—'
    if 'pgSchema' in props:
        want = schemas.get(repo, ('?', '?'))[0]
        chk = '一致' if props['pgSchema'].get('default') == want else f'**不一致**（registry：{want}）'
    removed = (['`dependencies.resources`'] if res else []) + (['`deployment.image`（改 `deployment.build`）'] if (m.get('deployment') or {}).get('image') else [])
    fmt = lambda xs: '<br>'.join(f'`{x}`' for x in xs) if xs else '—'
    print(f'| {cid} | {"、".join(deps) if deps else "—"} | {fmt(req)} | {fmt(dflt)} | {fmt(sec)} | {chk} | {"<br>".join(removed) or "—"} |')
```

**A.3 登记事实（§1.1）**：读 `registry/ports.tsv`（按 `component_id` 取 http/grpc/shell 列）与 `registry/schemas.tsv`（按 repo 取 schema/role），语言按仓库里有 `go.mod` / `pyproject.toml` / `tsconfig.json` 判断；密码变量 = `${<REPO 大写下划线>_DB_PASSWORD}`。

**A.4 谁在读哪个键（§2.1 下方的结论）**：对每个组件的每个旧键，`grep -rIl -e '"<键>"' -e "'<键>'"` 扫组件目录（排除 `.git`、`node_modules`、`gen`、`dist`、`component.yaml`、`*.md`）。

### 附录 B：已知过渡期现象与 scratch 实测（不修，照此预期）

**06b 期间的过渡期现象**

- 根目录 `brickkit lint --all` / `make lint` 在 06b 全程会因为还没重建的旧 `component.yaml`（`dependencies.resources` 等 v0 字段）报错；本地源里有非法的旧清单**不影响** `brickkit add` / `up` 其它组件。只查一个组件用 `brickkit lint <id>`（或在组件目录里不带参数；`make docs-check ID=<id>` 是它的严格档），`--all` 才查全项目。
- `make gates` 在 06b 期间：`config-key-scan` 对还在 1.x 的组件只警告（72 条左右，随迁移减少），2.x 组件与外壳判红；`openapi-additive-scan` 对比各组件本地最近的发布 tag；遇到第一个红的门禁就停（读法见 6.5）。
- `config/vars.yaml` 的 `AUTHZ_BUNDLE_URL` / `IAM_JWKS_URL` 用成员服务名 `infra-authz-2-0-0` / `infra-iam-casdoor-2-0-0`（R29/R30）。authz、iam-casdoor 还没都加入项目时：这两个主机名解析不到，受保护路由只验到 `401` / `503`（判定链在工作），带 token 一项 SKIP；`service-hostname-scan` 对还没声明的组件只警告。两者作为独立组件加入项目后地址直接可达，带 token 验 `200`；进 go-infra 外壳后由外壳容器的网络别名解析，值不变。任何阶段都不需要 `deploy.local.yaml` 或 `deploy.teardown.yaml` 的 `vars:` 覆盖，也不改 `config/vars.yaml`。focus 起的宿主机进程解析不了容器服务名，focus 下只验 `/healthz`（7.4）。
- `make test-db-init` 不带 `ID` 时对每个连库组件跑 `migrate-idempotent`（带 `ID` 只跑那一个，4.16），同时传 `PG_*` 与旧的 `DATABASE_*`（T26 删掉后者）。
- `make tier1` 仍是占位（06f 重写）。`make tier0` 是 mdm/customer 专用、带 v0 假设的旧断言。
- `make bump-version`：be-acceptance（v0.4.1 起）不再往 `component.yaml` 写历史注释，照常使用（R26）。分工：首轮 1.x → 2.0.0 时，下游组件的依赖版本在它自己第 3 步整份重写 `component.yaml` 时直接写 `@2.0.0`；**一个组件发布 2.0.0 之后再有任何改动**（修 bug 发 2.0.1、补字段发 2.1.0），以及外壳的 `shell.members` / `go.mod` 跟着成员换版本，一律走 `make bump-version PLAN=<计划文件>`（先 dry-run 看级联，再 `APPLY=1`），一轮改动写一份计划文件，然后按 `version-bump-ship` skill 逐个发布（`make ship`）、`make integrate ID=<id> VERSION=<新版本>`（内部是 `brickkit upgrade`）。
- `make test-cross` 只跑 Go（`go test`）。

**scratch 实测（历史，brickKit CLI v1.0.1 时在 scratch 项目里 `brickkit init` + 假组件做的，未起容器；以 `brickkit docs` 为准）**

- （历史）v1.0.1 时项目内 `brickkit lint` 一律 lint 整个项目、限定不到单个组件，所以当时有 `component-lint.sh`；`AGENTS.zh.md` 当时还要翻译 `## BrickKit` 一节。v1.1.0 起两者都不需要了。
- `brickkit new <id> --path <dir>`：写 `component.yaml`（只有 `deployment.build`，注释写着"发布预构建镜像后再加 `image:`"）与 `BRICKKIT.md`/`AGENTS.md`/`CLAUDE.md`/`README.md`；新骨架 `brickkit lint --strict` 报 11 条 `DOC_PLACEHOLDER`。
- `brickkit skills update` 在独立组件仓库里写入 `.claude/skills/brickkit-component/SKILL.md`。
- `brickkit add` 对 required 键写 `KEY: ""`、可选键写注释行（`# PG_SCHEMA: demo_b  # string (default)`）；`local.runCommand` 必须是数组。
- `brickkit up --focus <id> --dry-run`：focus 组件以 `mode: local` 从源码起（Go 默认探测成 `go run .`，所以要写 `local.runCommand`）；依赖照常是容器，并映射到宿主机（`18080:8080`）；提示"mode: local 组件的数据库迁移不会自动跑"。
- 外壳在成员已经独立加入项目之后 `brickkit add`：成员自动移进外壳（`🔗 demo/a moved into shell be/go-x`；与 `brickkit docs 04-shell/04-members-management` 的"`add` doesn't move it into the shell"说法相反，V-11，没移时的处理见 §4.4），`deploy.yaml` / `deploy.local.yaml` 同步嵌套，`deploy.teardown.yaml` 不动并提示手工同步；生成文件里外壳服务带 `BRICKKIT_SERVED_MEMBERS=<成员服务名列表>`，镜像名 `be-go-x:1.0.0`。
- `-f deploy.teardown.yaml` 的条目与 `brickkit.yaml` 不一致时报 `DEPLOY_INCONSISTENT`，逐个列出缺的条目。
- 读过的 brickKit 源码（已作为知识缺口报给控制者）：`internal/compose/local.go`（focus 进程的宿主机端口默认取组件声明的主端口、被占才从 8081 起分配；额外端口原样占用；配置里用了 `host.docker.internal` 的容器自动加 `extra_hosts`）、`internal/cli/up_local.go`（本机进程额外拿到 `PORT`）。当时据 `internal/deploy/naming.go` 得出的"宿主机上的进程把 `host.docker.internal` 换成 `localhost`"**不成立**：brickKit 只改写它自己算出的 `*_ENDPOINT`，手写在 `config/` 里的地址原样注入（v1.1.0 文档与试点实测一致），处理见 7.4。
