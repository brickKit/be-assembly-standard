# 阶段 06b · 单组件闭环清单（component-loop）

> 开发文件（`dev/`），阶段结束后归档；正式文档不得链接本文件。
> 用途：06b 重建 13 个后端组件时，每个组件逐项照做；按 `plan-06b.md` 的 Task 执行（波次、前置、自主并行模式见该文件），过程记录写 `dev/test-records/06b/<repo>.md`；成员齐了的外壳走 §4 外壳组装子清单。06c 的 `frontend/standard` 也按这份清单走（第 4 步换成前端测试）。工具：一次性迁移工具 `dev/phase-06/tools/`，长期脚本 `make integrate / verify / ship / teardown-sync / permissions`。
> 依据（写本文件时逐个读过的现状）：spec §5/§10/§11、项目 `AGENTS.md`、`docs/en/01-conventions/{04-configuration,07-registries,02-backend,06-testing,05-data,08-documentation,01-development-workflow}.md`、`docs/en/02-decisions/` 的 0107、0108、0303、5 个 brickKit skill + `version-bump-ship`、根 `Makefile` 与 `infra/scripts/`、三个 SDK 的 README、`dev/phase-06/frontend-needs.md`、`dev/phase-06/to-verify.md`、`components/mdm/customer` 与 `components/erp/sales` 的真实文件，以及在 scratch 项目里对 brickKit CLI 的实测（§9 附录 B；v1.1.0 起的变化已在对应条目标注）。
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

每个组件开始时先设好（`BE_SCRATCH` 为当前会话的 scratchpad 目录，`env.sh` 没有它会报错）：

```bash
export ROOT=/home/zhijie/Desktop/github/be-assembly-standard ID=<scope>/<name> BE_SCRATCH=<当前会话的 scratchpad>
eval "$(bash $ROOT/dev/phase-06/tools/env.sh $ID)"
```

`env.sh` 打印并建好下面这些变量（含义与旧版手写 `export` 完全相同）：

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
- 动项目状态的命令走项目锁：`make integrate` / `verify` / `permissions` / `test-db-init` / `dev-env` / `db-init` 自己拿锁；手工命令写成 `bash infra/scripts/project-lock.sh -- <命令>`。
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

只列 06b 必做项；"可选"项本期不做，除非本 Task 另定。新权限键一律先追加进该组件 `assembly.yaml` 的 `permissions`，再用 `make permissions` 汇总进 `registry/permissions.tsv`（第 3.5 步）。

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
  通过：每个依赖都是 `2.0.0`，且两条 `ls-remote` 都各有一行（Go 上游；Python / TS 上游只有 `2.0.0`）；optional 依赖可以缺，记录里写明缺哪个、组件会怎样降级。
- [ ] **1.2 组件仓库干净、与远端一致**：`git -C $C status -sb` 第一行是 `## main...origin/main`，后面没有 `[ahead`/`[behind`，下面没有文件行。不干净就不动它，在记录里写明并上报控制者裁定（可能是别人的半成品）。
- [ ] **1.3 基础资源在跑**：`make check` 全绿（PostgreSQL、NATS、Casdoor 等）。不要 `make up` 重启已在跑的资源。
- [ ] **1.4 工具版本**：`buf`、`protoc-gen-go`、`protoc-gen-go-grpc`、`grpcurl` 装在 `~/go/bin`，默认不在 PATH 里——先 `export PATH=$HOME/go/bin:$PATH`，`buf --version` 能输出版本（不在就上报控制者，不要自己另装）；`brickkit version` 是 `BrickKit CLI v1.1.0`；SDK 版本：be-sdk-go v0.4.0、be-sdk-python v0.4.4、be-sdk-ts v0.4.0（核对：`git -C $ROOT/tools/<sdk> describe --tags --abbrev=0`）。Python 组件的 besdk 版本必须与 `shell/be/py-render/pyproject.toml` 里钉的是同一个 tag（pip 不接受同一个 git 依赖出现两个 tag）。
- [ ] **1.5 读这些，按顺序**（不读依赖方源码、不读 brickKit 仓库）：
  1. `$C/AGENTS.md`、`$C/README.md`、`$C/docs/手册.md`（旧四件套，第 5 步要从中提取仍成立的结论）；
  2. `$ROOT/archive/pre-v1/docs/dev/design/$REPO.md`（旧设计文档，`docs/design.md` 的来源）；
  3. `$C/component.yaml`、`$C/assembly.yaml`、`$C/Makefile`、`$C/Dockerfile`；
  4. 本文件 §1.2 中本组件那一行，以及 frontend-needs.md 对应小节；
  5. 规则：04-configuration.md（全篇）、02-backend.md 的 [Module entry]/[The runtime is the only way in]/[Database]/[Calling other components]、06-testing.md、08-documentation.md 的 [Component documents]。
- [ ] **1.6 现有数据的属主**（迁移会以 `$ROLE` 身份跑，不再是 postgres 超级用户）：
  ```bash
  docker exec be-postgres psql -U postgres -d brickkit_db -tAc \
    "select tableowner, count(*) from pg_tables where schemaname='$SCHEMA' group by 1"
  ```
  记下结果。如果表属主是 `postgres`，而本组件这次要加 `ALTER TABLE` 类迁移（§1.2 里要给已有表加字段的：sales、finance、opportunity 等）：以 `$ROLE` 跑的迁移会报 `must be owner of table`，出路是用项目的数据库重置脚本重建演示库（Task 5）；由控制者裁定并记录，不在组件里绕过。
- [ ] **1.7 本组件要实测的 V 项**：查 §6.1 表与本 Task；在记录里先写好 V 项小节标题。
- [ ] **1.8 开记录**：新建 `dev/test-records/06b/$REPO.md`，按 §8 模板写上目标与环境。

### 第 2 步　拿 v1 骨架，替换文档

- [ ] **2.1 留底**：`mkdir -p $S/old && cp $C/{AGENTS.md,README.md,component.yaml,assembly.yaml,Makefile,Dockerfile} $C/docs/手册.md $S/old/`
- [ ] **2.2 生成骨架**：
  ```bash
  rm -rf $S/skel && brickkit new $ID --path $S/skel
  ```
  通过：输出 `✅ Component skeleton generated: <id>`，列出 `component.yaml`、`BRICKKIT.md`、`AGENTS.md`、`CLAUDE.md`、`README.md` 五个文件。
- [ ] **2.3 对照**：`diff -rq $S/skel $C | grep -v '/\.git'`。预期：
  - `Only in $S/skel: BRICKKIT.md`
  - `Files … AGENTS.md / README.md / component.yaml differ`
  - `CLAUDE.md` 不出现（两边都是 `@AGENTS.md`）；出现了说明旧的不合规，用骨架的。
  - 其余全是 `Only in $C: …`（代码、契约、迁移、脚本）。
- [ ] **2.4 按表处理**：

  | 文件 | 处理 |
  |---|---|
  | `BRICKKIT.md` | 拷入骨架（`cp $S/skel/BRICKKIT.md $C/`），第 5 步填写 |
  | `AGENTS.md`、`README.md` | 用骨架替换（`cp $S/skel/{AGENTS.md,README.md} $C/`），第 5 步按旧文件的仍成立结论重写 |
  | `CLAUDE.md` | 保留，内容必须恰好是 `@AGENTS.md` |
  | `component.yaml` | **合并**：结构取骨架（`deployment.build`、`healthCheck`），内容取旧文件，第 3 步重写 |
  | `docs/手册.md` | 删除（`git -C $C rm docs/手册.md`）；内容分流进 `AGENTS.md`（代码地图、构建测试）和 `docs/design.md`（设计结论） |
  | 代码、`contracts/`、`migrations/`、`gen/`、`scripts/`、`Dockerfile`、`Makefile`、`assembly.yaml` | 保留，第 3、4 步按需修改 |
- [ ] **2.5 组件仓库装 skill**：`cd $C && brickkit skills update`。通过：输出 `📦 Component repository …`，写入 `.claude/skills/brickkit-component/SKILL.md`，并确认 `AGENTS.md` 末尾有 `<!-- brickkit:managed:begin lang=en -->` 块。按 P6 预设提交这个 skill 目录（独立 clone 时 AI 才读得到 AGENTS.md 维护块里引用的那份 skill）。

### 第 3 步　重写 `component.yaml` 与 `assembly.yaml`

- [ ] **3.1 写 `component.yaml`**。以 mdm/customer 为样板（其余组件按 §2.2 那一行替换键、依赖、端口）：

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

  要点（每条都核对）：
  - 删掉全部版本历史注释、`deployment.image`、`dependencies.resources`；`metadata.name`/`description` 用英文（`BRICKKIT.md` 主文件是英文）。
  - `metadata.repository` = `https://github.com/brickKit/$REPO`（`git -C $C remote get-url origin` 核对）。
  - 依赖全部写上游的 `@2.0.0`：必需依赖一行 `- erp/inventory@2.0.0`，可选依赖写成 `- id: infra/workflow@2.0.0` 加下一行 `optional: true`；aggregator（bff-mobile）全部 `optional: true`；不为了拉 bundle / 验 token 加 authz 或 iam 的依赖边（[0107]）——但 `infra/iam-casdoor → infra/authz` 是真实的 gRPC 业务调用，保留。
  - `startPeriodSeconds`：Go 不写（默认 60）；Python 120；Node 90。
  - `local.runCommand` 必须是数组（写成字符串 `add` 报 `MANIFEST_INVALID: local.runCommand=must be an array`，scratch 实测）。Python / TS 的写法在 infra/print、infra/bff-mobile 的 Task 第一次 focus 时实测确定，记进过程记录并更新 `manifest-overrides.yaml`。
- [ ] **3.2 机器核对**（在 `$C` 下）：
  ```bash
  python3 - <<'EOF'
  import re, yaml
  m = yaml.safe_load(open('component.yaml'))
  props = m['configSchema']['properties']; req = set(m['configSchema'].get('required', []))
  print('驼峰/非法键:', [k for k in props if not re.fullmatch(r'[A-Z][A-Z0-9_]*', k)] or '无')
  print('保留名:', [k for k in props if k.endswith('_ENDPOINT') or k in ('COMPONENT_ID','COMPONENT_VERSION','PORT','BRICKKIT_SERVED_MEMBERS','BRICKKIT_SERVED_MEMBERS_CONFIG')] or '无')
  print('无默认值却不在 required:', [k for k, v in props.items() if 'default' not in v and k not in req] or '无')
  print('required 却有默认值:', [k for k in req if 'default' in props.get(k, {})] or '无')
  print('密码/密钥未标 secret:', [k for k in props if re.search('PASSWORD|SECRET|SIGNING_KEY', k) and not props[k].get('secret')] or '无')
  print('残留字段:', [k for k in ('resources',) if k in (m.get('dependencies') or {})] + (['deployment.image'] if 'image' in m['deployment'] else []) or '无')
  print('依赖:', (m.get('dependencies') or {}).get('components'))
  EOF
  grep -nE '#.*[0-9]+\.[0-9]+\.[0-9]+' component.yaml || echo "无版本注释"
  awk -F'\t' -v c=$ID '$2==c{print "registry:", $3, $4}' $ROOT/registry/ports.tsv
  grep -nE '^\s+port:|port: [0-9]+\}' component.yaml
  ```
  通过：前六行全部 `无`；依赖都是 `@2.0.0`；`无版本注释`；端口与 registry 一致；`PG_SCHEMA` 默认值等于 `$SCHEMA`。
- [ ] **3.3 组件级 lint**：`cd $ROOT && brickkit lint $ID`（不严格；v1.1.0 起带 `<id>`、或在组件目录里不带参数，只检查这一个组件，`--all` 才查全项目）。通过：第一行是 `🔎 Only <id> is checked…`，没有 `MANIFEST_INVALID`；此时只剩 `DOC_*` 警告（第 5 步清零）。
- [ ] **3.4 改 `assembly.yaml`**：
  - `id` 保留；删除 `version:`（版本只在 `component.yaml` 一处）；删除 `shell:` 键（由哪个外壳托管在部署文件里选，[0108]）；`data.role` 的注释改成"登录角色，`PG_USER` 的值"（v1 起组件以它登录，不再只是 `SET LOCAL ROLE` 的目标）。
  - `asset:`（旧 fork 指引，写的是 v0 机制）删除，`edge_routes:` 保留（P5 预设，plan-06b"预设裁定"；T8 若推翻由 T8 通知）；`menus`、`domain`、`tier`、`data`、`data_scopes`、`permissions` 一律保留（`menus` 的结构扩展归 06c）。`migrate-manifest.py --write` 已按此处理。
  - 按 §1.2 追加新权限键（`{ key, title, type }`，`key` 的域前缀等于组件域）；`data_scopes` 段必须在（无行级范围写 `data_scopes: none`）。
- [ ] **3.5 新权限键汇总进登记表**（只在本组件新增了键时）：
  ```bash
  make -C $ROOT permissions          # 拿项目锁：be-ops permissions + data-scopes + registry-check，并核对 permissions.tsv 只增不删
  git -C $ROOT diff --stat registry/
  ```
  通过：最后一行 `✓ registry/permissions.tsv 只有新增`；孤儿键警告照常出现（旧组件），不处理。
  authz 的 `PERMISSION_CATALOG` 直接引用这个文件（§2.5），新键在下一次 `brickkit up` 时自动进入 authz，不需要再生成任何东西；全栈集成时核对新键已出现在 `infra_authz.permissions` 里。

### 第 4 步　代码迁移、审查、补接口、测试

**4A 机械迁移**（Go；Python / TS 对应项写在后面）

Go 组件的 4.0–4.4 与 4.6 由一条命令完成（plan C4；幂等，可重复运行，最后跑 4.4 的全部判据，任一 FAIL 就非零退出）：

```bash
bash $ROOT/dev/phase-06/tools/go-v2.sh $ID --sdk v0.4.0; echo "exit=$?"
```

通过：`exit=0`。下面 4.0–4.4、4.6 的手工命令是脚本所做之事的原文，保留作排障参考与 diff 审读的对照；判据全集以脚本输出和 `dev/phase-06/tools/README.md` 的"go-v2.sh / 判据"为准。脚本不做、仍要人做的：4.5、4.7–4.9；4.6 的读 diff、改 `migrations/embed.go` 的过时注释、核对 Dockerfile 的目的路径。

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
  通过（全部满足才算过）：
  - `BUILD_OK`；`head -1` 是 `module github.com/brickKit/<repo>/v2`；
  - `go.mod 没有 require 自己的旧路径`——出现 `github.com/brickKit/<repo> v1.x.y` 就是形态 B 被当成形态 A 做了，回到 4.0（`go-v2.sh` 完整运行会自动清掉并报 ⚠️；`--recheck` 不清、报 FAIL）；
  - `go list -m all` 只有两行：`github.com/brickKit/<repo>/v2`（主模块）和 `github.com/brickKit/<repo>/gen/<domain>/<name> v1.x.y => ./gen/<domain>/<name>`；
  - `go list -deps` 列出的本仓库模块只有这同样两个（C-1 状态下这里会多出 `github.com/brickKit/<repo>`，实测）；
  - 最后一条输出 `import 全部带 /v2（契约包除外）`。
  - 脚本另外还判（手工排障时一并核对）：契约包模块路径不带 `/v2`；根 `go.mod` require 的契约包版本 = 4.3 算出的版本且有本地 replace；除契约包外没有别的 `replace`；Dockerfile 先 `COPY . .` 再 `go mod download`；Dockerfile 编译 `./backend/cmd/migrate` 并 `COPY --from` 进最终镜像；SDK ≥ v0.4.0 时迁移入口恰好一行、非 gen 代码里没有 `Migrations:`；be-sdk-go 是 `--sdk` 给的版本。
- [ ] **4.5 改配置读取**：按 §2.1 把 `module.go`（及测试里构造 `Config` 的地方）的旧键名换成新键名。核对：
  ```bash
  grep -rnE '(String|StringOr|MustString|Int|IntOr|Bool|BoolOr)\("[a-z]' --include='*.go' backend || echo "无驼峰键读取"
  grep -rnE 'besdk\.(Endpoint|MustEndpoint)\(|StorageEndpoint|STORAGE_ENDPOINT|DATABASE_|MQ_(HOST|PORT|USER|PASSWORD)' \
    --include='*.go' --include='*.sh' --include='Makefile' . | grep -v '^./gen/' || echo "无旧平台变量/旧 API"
  ```
  通过：两条都输出"无…"。依赖地址只用 `rt.Config.Endpoint(dep, "grpc")` / `MustEndpoint`；用户请求路径上 `besdk.UserClient(ctx, rt.Config, dep, "grpc")`，`besdk.SystemClient(rt.Config, dep, "grpc")` 只在 `Start()` 和事件 handler 里；对象存储 `rt.Config.S3URL()`。
- [ ] **4.6 迁移入口**（be-sdk-go v0.4.0 的 `migrate` 包，P4；**由 `go-v2.sh --sdk v0.4.0` 完成，人工核对**）：
  - **脚本做的**（v0.4.0 起，在编译之前）：删掉 `backend/module/module.go` 的 `Migrations:` 一行；把 `backend/cmd/migrate/main.go` 改写成只剩 `func main() { migrate.Main(migrations.FS) }`（import `github.com/brickKit/be-sdk-go/migrate` 与本组件的 `…/v2/migrations`）；`migrations/embed.go`（`//go:embed *.sql` + `var FS embed.FS`）缺了就建；两处都核对，不符就 FAIL。连接串、`search_path`、`schema_migrations_<schema>` 表名、`up`/`down` 参数校验都由 SDK 负责（读 `PG_*`，缺键以 1 退出并点名；参数不对以 2 退出）；SDK 用 `database/pgx/v5`，不再有 lib/pq 与 `sslmode` 的问题。`component.yaml` 的 `migration.command` 不变（`["./migrate", "up"]`）。
  - **人要做的**：读脚本产生的 diff（`git -C $C diff -- backend/ migrations/`），确认 `module.go` 里随 `Migrations:` 一起不再用的 import 已清掉、`migrations/embed.go` 的注释不再说"挂到 `Module.Migrations`"；核对 `Dockerfile`（脚本已判"编译 `./backend/cmd/migrate` 并 `COPY --from` 进最终镜像"，人只看目的路径）：仍然 `go build … -o /out/migrate ./backend/cmd/migrate` 并拷成 `/app/migrate`（`WORKDIR /app`，`./migrate up` 才找得到），`COPY component.yaml /app/component.yaml` 保留；迁移文件已嵌进二进制，`COPY migrations /app/migrations` 不再需要，可以删。
  - 通过：`go-v2.sh` `exit=0`；`make migrate-idempotent` 绿；`verify` 里迁移容器 `Exited (0)`。
- [ ] **4.7 `Makefile` 按 v1 改**（目标集合保持 06-testing.md 要求的那几个：`test`、`migrate-idempotent`、`contract-check`、`module-check`、`smoke`、`seed`/`seed-clean` 或 `db-reset`）：
  - `check-version`：不再查 `deployment.image`；HEAD 带 tag 时要求同时有 `$(VERSION)` 与 `v$(VERSION)`（Go）；`VERSION` 用 `yq` 或 `grep -m1 '^  version:'` 取 `metadata.version`。
  - `migrate-idempotent`：注释和用法改成 `PG_*`（`PG_HOST=localhost PG_PORT=5432 PG_DATABASE=brickkit_test_db PG_USER=… PG_PASSWORD=… PG_SCHEMA=$SCHEMA make migrate-idempotent`）。
  - `docs-check`：改成 `make docs-check ID=<scope>/<name>`（= `brickkit lint --strict <id>`；旧的 `infra/scripts/docs-check.sh` 已不存在）。
  - `smoke`：`cd ../../.. && brickkit up --dry-run`。
  - `import-scan` 的自身白名单改成 `github.com/brickKit/$REPO/v2`。
  - `IMAGE := brickenterprise/<repo>` 与 `image` 目标删掉（镜像名由 brickKit 定为 `<repo>:<version>`，构建走第 7.7 步的 `brickkit build`）；`all` 不再依赖 `image`。需要"镜像里有 sh + wget"的检查时，`image` 改成 `cd ../../.. && brickkit build $(ID)` 再 `docker run --rm --entrypoint sh <repo>:$(VERSION) -c 'wget --version'`。
  - `dag-check`：按新 `component.yaml` 的写法核对（旧版写死"`components: []` 行内空数组"或数 `- ` 行，`resources` 删除后要重新确认判据没有误数）；没有依赖的组件判"无强依赖"，有依赖的列出依赖并确认都是 `@2.0.0`。
- [ ] **4.8 父仓库的过渡脚本**（只核对，不改父仓库文件）：`infra/scripts/test-db-init.sh` 已由 Task 5 改为同时传 `PG_*`（以 `<schema>_rw` 登录）与旧的 `DATABASE_*`（T26 删）；本组件只核对 `make test-db-init` 绿，不改父仓库文件。
- [ ] **4.9 脚本**：`scripts/seed.sh` 等里有没有写死旧版本服务名（`1-0-`）或 `DATABASE_*`：`grep -rnE '1-0-[0-9]+|DATABASE_' scripts/ || echo 无`。

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
- [ ] **4.14 契约先行，只增不改**：改 `contracts/*.proto` / `*.openapi.yaml` / `events/*.json`；`make contract-check` 绿；`buf generate` 重新生成 `gen/`（`git diff --stat gen/` 有变化，第 8 步要打新的契约包 tag）。然后跑 `bash $ROOT/dev/phase-06/tools/go-v2.sh $ID --recheck`（plan C4：重算根 `go.mod` require 的契约包版本并重跑判据），把它最后打印的"第 8.3 步需要打的契约包 tag"（或"不需要"）交给控制者（脚本一律升 minor；只是重新生成、要 patch 时手工 `go mod edit -require=…@v1.x.(y+1)` 再 `--recheck`，见 tools README）。
- [ ] **4.15 红绿**：每条新规则先写 L2 测试并跑红（红的原因是"功能还不存在"），再写实现跑绿；一个循环一个提交。有数据范围的接口（warehouse、legal_entity、org/owner）必须有"别人的数据看不到"的测试（06-testing.md#l2）。新增路由一律 `besdk.GET(r, path, permKey, h)` 这类带权限键的注册。

**4D 全部测试**

- [ ] **4.16 测试库就绪**：`make test-db-init`（输出 `✓ brickkit_test_db 就绪`）。
- [ ] **4.17 跑测试**（在 `$C` 下）：
  ```bash
  set -a; . $ROOT/.env; set +a
  export TEST_PG_DSN="postgres://postgres:${POSTGRES_PASSWORD}@localhost:5432/brickkit_test_db?sslmode=disable" TEST_NATS_URL=nats://localhost:4222
  go test ./... -race -count=1 -v 2>&1 | tee $S/test.log | grep -E '^(--- FAIL|--- SKIP|FAIL|ok )'
  make migrate-idempotent contract-check module-check
  ```
  通过：没有 `--- FAIL`/`FAIL`；`--- SKIP` 只允许出现在"需要真实依赖、由 `make test-cross` 跑"的跨组件测试上，并且这些测试在第 7.9 步必须真的 PASS；其余三个目标都绿。Python：`pytest -q`；TS：`npm test`（同样核对 skip）。

### 第 5 步　四件套（每份都带 `.zh.md`）

- [ ] **5.1 写作要点**（08-documentation.md#component-documents、brickkit-component skill 规则 12）：

  | 文件 | 必须有的内容 |
  |---|---|
  | `BRICKKIT.md` | 六节：`Purpose`（一两句话说解决什么，然后 **Owns** / **Does not own** 两个列表，后者每条写明谁拥有）、`Before you deploy`（schema `$SCHEMA` 与 `${SCHEMA}_archive`、登录角色 `$ROLE` 及其在两个 schema 上的 USAGE+CREATE、`PG_PASSWORD` 从哪来；NATS 可达；本项目里由 `make dev-env` + `make db-init` 完成）、`Dependencies`（每个依赖按 ID 不带版本、用来做什么、optional 的缺席时怎样降级；说明 authz/iam 地址是配置不是依赖）、`Configuration`（**全部** `configSchema` 键，至少全部 required 键，写业务含义与推荐取值形式 `$var:` / `${…}` / 字面量）、`Contracts`（`artifacts` 里每个文件、主要 rpc 与 REST 路径及权限键、发布与消费的事件）、`Shell declaration`（"Not a shell." 并说明设计上可被哪个外壳托管）。**不写相对链接**，文件名写成行内代码 |
  | `BRICKKIT.zh.md` | 同样六节，标题必须是 `组件定位` / `部署前准备` / `依赖说明` / `配置指南` / `契约索引` / `外壳声明`（自由翻译 lint 不认）；不写相对链接 |
  | `AGENTS.md` | 第一行 `[English](AGENTS.md) · [中文](AGENTS.zh.md)`；五节 `Code map`（两张表："Path / Owns"，路径用反引号、目录以 `/` 结尾，每个路径都要真实存在；"Feature / Start here / Then"）、`Build and test`（确切命令与成功的样子）、`Design decisions`、`Pitfalls`（Never / Symptom / Why，**只写本组件特有的**，项目级规则不抄）、`Before changing code`（3–8 条）；末尾 brickKit 维护块不动。不写指向 `../` 的链接（`DOC_LINK_NOT_PORTABLE` 也查 AGENTS.md） |
  | `AGENTS.zh.md` | 同样五节，固定中文标题 `代码地图` / `构建与测试` / `设计取舍` / `易错点` / `改代码前自查`（v1.1.0 起不需要另写一节占位标题，维护块不计入小节数） |
  | `README.md` / `.zh.md` | 第一行互链；中文固定标题 `在项目里使用` / `文档` / `开发`；`Use it in a project`（`brickkit add <id>@2.0.0`，先看 BRICKKIT.md 的 Before you deploy）、`Documentation`（哪个问题读哪个文件）、`Development` |
  | `docs/design.md` / `.zh.md` | 从 `archive/pre-v1/docs/dev/design/$REPO.md` **只提取结论**：边界（含明确不归本组件的）、拥有的数据（表、分区、终态）、契约面（含 `batchGet`、REST 路径与权限键、幂等端点、状态端点）、发布与消费的事件、依赖及"为什么不依赖某个预期中的组件"、在同步调用图里的位置、分区与归档、数据范围或为什么没有、参考实现、未决问题 |
  | `CLAUDE.md` | 恰好 `@AGENTS.md` |

  所有文件：不写历史（"阶段 X 时…""v1.0.6 修了…"一律不要，历史在 git 和 tag 说明里）；每条禁令带症状和原因；不写"见上文"；不链接 `dev/`、`archive/`。
- [ ] **5.2 核对**：
  ```bash
  cd $C && for f in BRICKKIT README AGENTS docs/design; do printf '%-14s en=%s zh=%s\n' $f $(grep -c '^## ' $f.md) $(grep -c '^## ' $f.zh.md); done
  grep -rnE '\]\((\.\./)+(dev|archive)/|archive/pre-v1|dev/phase-06' *.md docs/ || echo "无越界链接"
  grep -nP '\]\((?!https?://)' BRICKKIT.md BRICKKIT.zh.md || echo "BRICKKIT 无相对链接"
  cd $ROOT && make docs-boundary && make docs-check ID=$ID
  ```
  通过：四行都是 en=zh（维护块不计入小节数，两边直接相等；最终以 lint 的 `DOC_TRANSLATION_DRIFT` 为准）；两条"无…"；`make docs-boundary` 绿；`make docs-check` 输出 `0 with errors, 0 warnings`（见第 6 步）。

### 第 6 步　版本 2.0.0，`lint --strict` 零警告

- [ ] **6.1 版本处处一致**：`grep -m1 -n 'version:' $C/component.yaml` → `2.0.0`；Go：`head -1 $C/go.mod` 以 `/v2` 结尾；Python：`pyproject.toml` 的 `version = "2.0.0"`；TS：`package.json` 的 `"version": "2.0.0"`。
- [ ] **6.2 严格 lint**：`make docs-check ID=<scope>/<name>; echo "exit=$?"`（项目根；严格档，只查这一个组件）。通过：`📋 Checked … files: 0 with errors, 0 warnings` 且 `exit=0`。常见警告与处理：`DOC_PLACEHOLDER`（骨架 TODO 没删）、`DOC_OUT_OF_STEP`（某个依赖 / required 键 / 契约文件文档没提）、`DOC_PATH_MISSING`（Code map 第一张表里的路径不存在）、`DOC_TRANSLATION_DRIFT`（两边小节数不一致）、`DOC_LINK_NOT_PORTABLE`（BRICKKIT*.md 或 AGENTS.md 里的相对 / `../` 链接）。
- [ ] **6.3 组件门禁**：`cd $C && make check-version test migrate-idempotent contract-check import-scan module-check docs-check` 全绿（`check-version` 此时 HEAD 还没有 tag，只核对版本一致性）。
- [ ] **6.4 V-01（只在 mdm/customer 做）**：在 `component.yaml` 里临时加一个驼峰键 `fooBar: {type: string, default: x}`，分别跑 `make docs-check ID=mdm/customer`与 `brickkit up --dry-run`（项目根，第 7.2 步加入项目之后再跑这一半），原文记录有没有任何警告；然后删掉这个键、`git -C $C diff component.yaml` 确认复原。结论写进 to-verify 的 V-01 行（"静默接受"成立就转反馈候选）。

### 第 7 步　接入项目、构建、真机验证

> 7.1（除最后一条"以 `$ROLE` 连库"核对，那条仍手工做）–7.5 由 `make integrate ID=$ID` 一条命令完成（连库组件先 `dev-env`/`db-init`，`brickkit add`、`config-fill.py`、`teardown-sync.py`、`brickkit lint --strict $ID`、`brickkit up --dry-run`）；7.7–7.11 由 `make verify ID=$ID ROUTE=<受保护路径> FOCUS=1` 覆盖（build → 只起闭包 → 健康与鉴权 → `test-cross` → focus → 收尾；`FOCUS`、`KEEP` 只有值为 `1` 时才生效）。下面的手工命令保留作排障参考；命令版的汇总表与输出目录路径贴进记录即可。V-07（7.6）是试点专用的探针，`verify` 不覆盖。

- [ ] **7.1 数据库角色与密码**（连库组件）：
  ```bash
  cd $ROOT && make dev-env && make db-init
  set -a; . ./.env; set +a; eval "PW=\$${UREPO}_DB_PASSWORD"   # 不用 bash 专有的 ${!var}，Bash 工具实际跑在 zsh 里
  docker exec -e PGPASSWORD="$PW" be-postgres psql -h 127.0.0.1 -U $ROLE -d brickkit_db -tAc 'select current_user'
  ```
  通过：`make dev-env` 打印"已齐全"或列出新增的变量名（只有名字）；`make db-init` 打印 `✓ 建库脚本已执行`；最后一条输出 `$ROLE`（能以登录角色连上）。
- [ ] **7.2 加入项目**：
  ```bash
  cd $ROOT && brickkit add $ID@2.0.0
  ```
  通过（scratch 实测的输出形态）：`➕ Adding <id>@2.0.0`、`✅ <id>@2.0.0`、`📝 Written: brickkit.yaml, deploy.yaml[, deploy.local.yaml]`、`📝 Config skeletons: config/$REPO.yaml`、`✏️ Fill in the required keys in config/$REPO.yaml: …`。若提示 `ℹ️ Not changed: deploy.teardown.yaml` 之类，下一步手工同步。`git diff AGENTS.md` 看到组件表多了一行（版本 2.0.0，Home 列是 `metadata.repository`）。
- [ ] **7.3 填 `config/$REPO.yaml`**：按 §2.4。密钥写进 `.env`（`.env` 不提交）；多行密钥放 `.secrets/<repo>/`。`$var:` 后面没有空格。
- [ ] **7.4 同步 `deploy.teardown.yaml`**：`brickkit add` 只维护 `deploy.yaml`（和存在时的 `deploy.local.yaml`），拆回验证用的 `deploy.teardown.yaml` 用 `make teardown-sync`（拿项目锁；`make teardown-sync CHECK=1` 只核对、不一致时 exit 1 并打印差异）与 `deploy.yaml` 对齐（它没有 `vars:` 覆盖，authz/iam 地址本来就是成员服务名，R30）。`make integrate` 已经调用过它；不要直接跑 `python3 infra/scripts/teardown-sync.py`（不拿锁）。通过：`brickkit up -f deploy.teardown.yaml --ignore-shells --dry-run` 不报 `DEPLOY_INCONSISTENT`。
- [ ] **7.5 生成检查**：`brickkit up --dry-run`。通过：`📋 Component state calculation` 里本组件 `starting (…)`；没有 `CONFIG_INVALID`（缺 required 值）、没有未定义 `$var:` / `${…}`；`📄 Generated: .brickkit/generated/compose.yaml`。`grep -n -A30 "$SVC:" .brickkit/generated/compose.yaml` 能看到 `PG_USER=$ROLE`、`extra_hosts: host.docker.internal:host-gateway`（配置里用了 `host.docker.internal` 时 brickKit 自动加）。
- [ ] **7.6 V-07（只在 mdm/customer 做，7.5 之后缓存已生成）**：把 `$C/component.yaml` 的版本临时改成 `2.0.1`（不提交），跑 `cd $ROOT && brickkit lint mdm/customer`、`brickkit lint --all 2>&1 | grep -n -i -A3 'mdm/customer'`、`brickkit up --dry-run`，原文记录三者是否发现"`brickkit.yaml` 钉 2.0.0、本地源是 2.0.1"的漂移；然后 `git -C $C checkout component.yaml` 复原，再跑一次 `brickkit up --dry-run` 确认恢复。结论写进 to-verify 的 V-07 行。
- [ ] **7.7 构建镜像**（`make verify` 覆盖）：
  ```bash
  cd $ROOT && brickkit build $ID
  docker image ls $REPO --format '{{.Repository}}:{{.Tag}}'
  docker run --rm --entrypoint sh $REPO:2.0.0 -c 'wget --version >/dev/null && echo "sh+wget ok"'
  ```
  通过：镜像 `$REPO:2.0.0` 存在；输出 `sh+wget ok`。镜像里必须有 `component.yaml`（SDK 从工作目录读端口）：`docker run --rm --entrypoint sh $REPO:2.0.0 -c 'ls /app/component.yaml'`。
- [ ] **7.8 容器形态真机跑**（`make verify` 覆盖；检验镜像、迁移容器、健康检查；先确认 `brickkit local status`，本地模式开着时读的是 `deploy.local.yaml`）：
  ```bash
  cd $ROOT && brickkit up 2>&1 | tee $S/up.log
  brickkit status
  docker ps -a --format '{{.Names}}\t{{.Status}}' | grep "$REPO"
  MIG=$(docker ps -a --format '{{.Names}}' | grep "$REPO" | grep -i migrat | head -1)   # docker 的多个 name 过滤是"或"，所以用 grep
  docker logs "$MIG" 2>&1
  docker run --rm --network $NET curlimages/curl -s -o /dev/null -w '%{http_code}\n' http://$SVC:<HTTP 端口>/healthz
  docker run --rm --network $NET curlimages/curl -s -o /dev/null -w '%{http_code}\n' http://$SVC:<HTTP 端口>/<一条受保护的 REST 路径>
  ```
  通过：本组件 `running (healthy)`；迁移容器 `Exited (0)`，日志最后一行是 SDK 的 `迁移结束`、`outcome=ok`（`"msg":"迁移结束"` 带 `"outcome":"ok"`）；`/healthz` → `200`；受保护路由不带 token → `401` 或 `503`（`IAM_JWKS_URL` 已配但 JWKS 不可达时，SDK 可能还没建起验签器；原文记录实际值，`403` 才说明 `IAM_JWKS_URL` 没注入进去）。authz/iam 已在项目里时，再用 seed 账号拿真 token（`source infra/scripts/lib/seed-net.sh` 后先 `with_toolbox $NET`、再 `get_app_jwt dev.superuser`，与 `verify` 的做法相同）打一次，期望 `200`；authz/iam 尚未加入项目时不做这一项，记录写原因（`verify` 里记 SKIP）。依赖它的上游（已加入项目的）也都 healthy。
- [ ] **7.9 跨组件测试**（`make verify` 覆盖）：`make test-cross ID=$ID`（依赖容器必须在跑，7.8 已拉起）。通过：输出 `▶ 局部测试 $REPO`，列出每个强依赖桥接到的 `<DEP>_GRPC_ENDPOINT=http://localhost:2xxxx`（无强依赖时显示"等价于 make test"），`go test` 全部 `ok`，第 4.17 步 SKIP 掉的跨组件测试这里是 PASS（`ARGS="-run <名> -v"` 核对）。test-cross 目前只跑 Go；Python/TS 组件没有强依赖，记"不适用"。
- [ ] **7.10 focus 运行**（`make verify FOCUS=1` 覆盖；spec 第 7 步要求；brickKit 的 focus 是把本组件当 `mode: local` 进程在宿主机上从源码起，依赖照样是容器）：
  ```bash
  cd $ROOT && brickkit up --focus $ID          # 前台监管进程：用后台方式跑，另开调用做检查
  ```
  通过：输出 `🎯 Focus: <id>`、本组件 `starting (focus)`、依赖 `starting (<id> needs it)`、其余 `not starting (outside the focus)`；有迁移的组件会出现 `⚠️ Note: a mode: local component's database migration won't run automatically`（容器形态 7.8 已经跑过迁移，这里不用再跑；首次就用 focus 的组件按提示用 `local-debug.$SVC.env` 里的变量手工跑一次迁移）；`curl -s -o /dev/null -w '%{http_code}' http://localhost:<HTTP 端口>/healthz` → `200`（宿主机端口默认就是组件声明的端口，被占用时才换（v1.1.0 同样如此，可用 `brickkit up --dry-run` 或 `local-debug.*.env` 核对）；SDK 监听的是 `component.yaml` 里的端口，两者不一致就是问题，记录下来）。宿主机上 `host.docker.internal` 解析不了，brickKit 给本机进程的变量会把它换成 `localhost`——用 `brickkit up --dry-run` 的提示或 `local-debug.*.env` 核对，而不是假设。
- [ ] **7.11 收尾**（`make verify` 默认自己收尾，`KEEP=1` 才保留）：停掉 focus 进程（Ctrl+C 等价操作），`brickkit up --all --dry-run`（清除 focus），`brickkit down`，`brickkit local off`（本地模式会让 `deploy.yaml` 的改动不生效，验证完就关）。通过：`brickkit status` 没有运行中的组件容器；`brickkit local status` 显示已关。

### 第 8 步　交接与发布

> 实现者只做 8.1、8.2（提交不推送）并交接；8.3–8.5 的推送、`gen/*` tag、`brickkit release`、`v` tag、外壳视角拉取由控制者用 `make ship DIR=components/$ID NOTES=$S/notes-2.0.0.md` 一条命令完成（按顺序、第一处失败即停；已推送的东西绝不回滚或删除）。8.3–8.5 的手工命令保留作排障与原理参考，实现者不要执行推送类命令。

- [ ] **8.1 写发布说明**（放组件目录**外**，否则 release 的"目录干净"检查不过）：`$S/notes-2.0.0.md`。先写项目必须做的事，再写新增：
  ```markdown
  ## 升级前必须做
  - 配置键全部改为大写下划线环境变量名（旧键 → 新键见 BRICKKIT.md 的 Configuration 一节）；不再读取平台注入的 DATABASE_* / MQ_*。
  - 需要登录角色 <role>（PG_USER）及其密码（PG_PASSWORD，secret），以及 PG_HOST / PG_PORT / PG_DATABASE / NATS_URL / AUTHZ_BUNDLE_URL / IAM_JWKS_URL。
  - Go 模块路径改为 github.com/brickKit/<repo>/v2（外壳 import 与 go.mod require 都要带 /v2）。
  ## 新增
  - <frontend-needs 的新接口、新字段、新权限键>
  ```
- [ ] **8.2 组件仓库提交（不推送）**：
  ```bash
  cd $C && git status --short          # 只应有本次的改动；build/、.venv/、node_modules/ 已忽略
  git add -A && git commit -F $S/commit-msg.txt && git log --oneline -1
  ```
  通过：`git log` 第一行就是这次的提交，工作区干净。**不 `git push`、不打 tag。** 向控制者交付：提交 SHA、发布说明路径、`verify` 汇总表、契约包是否需要新 tag 及版本号。红绿循环中途已经有若干提交的，这里是最后一个"文档 + 版本"提交。⚠️ 与 spec §11"组件仓库每个组件一个提交"的冲突：本清单按正式文档 01-development-workflow.md#commits 的"一个红绿循环一个提交、改测试单独一个提交"来做（正式文档优先）；纯机械迁移（第 3、4A 步）与文档（第 5 步）各合成一个提交即可。
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
- [ ] **8.6 镜像与提交一致**：7.7 之后组件代码或文档又改过的，`brickkit build $ID --force` 重建（镜像 tag 只认版本号）；`make verify` 之后又改过就重跑。
- [ ] **8.7 父仓库（控制者）：submodule 指针与项目文件**：实现者不在父仓库提交任何东西。`make ship` 通过后，控制者核对并按路径提交、推送（R31）：
  ```bash
  cd $ROOT
  git -C $C describe --tags --exact-match                  # 2.0.0 或 v2.0.0
  git status --short -- components/$ID brickkit.yaml deploy.yaml deploy.teardown.yaml config/ AGENTS.md registry/
  git commit -F <msg> -- <路径…> && git log --oneline -1 && git show --stat HEAD | head -20
  git submodule status components/$ID
  ```
  路径：`components/$ID`（指针）、`brickkit.yaml`、`deploy.yaml`、`deploy.teardown.yaml`、`config/$REPO.yaml`（`config/vars.yaml` 有改时也带上）、`AGENTS.md`（组件表）、`registry/permissions.tsv` / `registry/data-scopes.tsv`（有新键时）。**不带** `.env`、`.secrets/`、`deploy.local.yaml`、`deploy.verify.yaml`，也不带别的工作线的路径。
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

以下用 `$SH=be/go-infra`、`$SHD=$ROOT/shell/be/go-infra`、`$SHN=go-infra` 举例。`env.sh` 只认 `components/` 下的组件（给外壳 ID 会 exit 2），外壳 Task 开始时手工设好变量：

```bash
export ROOT=/home/zhijie/Desktop/github/be-assembly-standard BE_SCRATCH=<当前会话的 scratchpad>
export SH=be/go-infra SHN=go-infra SHD=$ROOT/shell/be/go-infra S=$BE_SCRATCH/06b/be-go-infra NET=brickkit-be-assembly-standard-net; mkdir -p $S
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
- [ ] **合并态专属断言**（手工）：`bash infra/scripts/project-lock.sh -- make tier2`（需要 `TEST_PG_DSN`/`TEST_NATS_URL`）；红了先读输出，判断是不是 06f 待重写的旧断言，是就记录、不改测试。
- [ ] **拆回验证**（手工，`make verify` 不做；先按上面 verify 那条在锁内 `brickkit down -f deploy.verify.yaml` 收掉 `KEEP=1` 留下的容器）：
  ```bash
  bash infra/scripts/project-lock.sh -- bash -c 'brickkit up --ignore-shells --dry-run && make teardown-up && brickkit status -f deploy.teardown.yaml; make teardown-down'
  ```
  通过：`--dry-run` 通过；`brickkit status -f deploy.teardown.yaml` 里全部成员各自 healthy；最后 `teardown-down` 已执行。
- [ ] `make gates`（其中 `dependency-version-scan` 会核对外壳 `go.mod` 钉的成员版本与成员 `metadata.version`）全绿。
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
- [ ] 项目级检查：`make registry-check`、`make docs-boundary`、`make gates`、`make version-check`、`brickkit lint --all --strict`、`brickkit up --dry-run`。
- [ ] 全量真机：`brickkit up`（全部组件）→ `brickkit status` 全部 healthy → 跨组件路径各打一次（受保护路由带真 token）→ 各组件 `make seed` 跑通（种子数据规则见 05-data.md）。`make tier0` 会临时停掉 postgres，并假设 `mdm/customer` 暴露在宿主机 8080（需要在 `deploy.local.yaml` 里给 mdm/customer 写 `expose: true`）；红了先判断是不是 v0 时代的假设，是就记录交 06f。
- [ ] 业务闭环：`make seed-data` 跑通后，确认至少一个 WON 商机有对应订单（`source_opportunity_id` 指向它、商机 `order_id` 回填）、订单确认产生了库存预留、财务有对应应收凭证；每一环的查询命令与结果原文进记录。
- [ ] `brickkit down`；`brickkit local off`。
- [ ] 已发布 2.0.0 的组件后来又改过的（返工、修 bug），用 `make bump-version PLAN=…`（dry-run → `APPLY=1`）传播版本并按 `version-bump-ship` 发布（`make ship`），再 `make integrate ID=<id> VERSION=<新版本>`；不要手改下游依赖或外壳成员版本。
- [ ] 记录写完；V 项结论、知识缺口、反馈候选由控制者合并进 to-verify。父仓库由控制者按路径提交并推送。

---

## 6. V 项与拍板项

### 6.1 V 项在哪一步实测

| V 项 | 在哪一步 | 做法摘要 | 结论写到 |
|---|---|---|---|
| V-01 驼峰键是否静默接受 | 试点 mdm/customer，6.4（组件 lint 一半）+ 7.2 之后（`up --dry-run` 一半） | 临时加 `fooBar` 键，看 `lint --strict` / `up --dry-run` 有无警告，复原 | to-verify V-01 |
| V-06 Go 双 tag | 试点 mdm/customer 8.5（`make ship` 的外壳视角拉取）；go-infra 4.2（外壳真实拉成员） | 记录 `release` 后补 `v` tag 的每一处摩擦；brickKit 有没有现成办法 | to-verify V-06 |
| V-07 版本漂移与缓存 | 试点 mdm/customer 7.6 | 缓存生成后改本地源版本，看 `lint` / `up --dry-run` 是否发现，复原 | to-verify V-07 |
| V-03 外壳 `brickkit build` | go-infra 4.4（Go 首个）；py-render 4.4（Python 首个） | 首次带成员 `brickkit build`，核对 `io.brickkit.shell.members` 标签 | to-verify V-03 |
| V-04 知识缺口 | 全程 | 每次不得不读 brickKit 源码就追加一行 | to-verify 知识缺口表 |

### 6.2 拍板项（预设裁定见 plan-06b "预设裁定"一节，试点 Task 8 确认；以那一节为准，下表是原始提议）

| # | 问题 | 本清单的默认做法 | 依据 |
|---|---|---|---|
| P1 | `AUTHZ_BUNDLE_URL`/`IAM_JWKS_URL` 是否一律 required、不给默认值 | 是 | §2.3 第 2 条 |
| P2 | `PG_SCHEMA` 带默认值（= registry schema），同时在 `config/` 里写字面量 | 是 | 04-configuration.md 的值来源表 |
| P3 | 契约包 `gen/<domain>/<name>`：一律是嵌套模块（形态 B 的 5 个组件拆出来），路径不带 `/v2`，tag `gen/<domain>/<name>/v1.<minor>.<patch>` 只在生成物变化时打；组件根 `go.mod` require 真实 tag（不再 `v0.0.0`）+ 本地 `replace` | 是（scratch 上两种形态都验证过，见 task-17 报告） | 第 4.0–4.4、8.3、8.5 步；conventions 里没有写契约包的 tag 规则，定了之后补进 01-development-workflow.md#versions |
| P4 | 迁移入口的驱动：golang-migrate `pgx/v5`（与模块同一个 pgx）还是保留 lib/pq 显式带 `sslmode` | 倾向 `pgx/v5`，以 `make migrate-idempotent` 与 7.8 迁移容器真跑通过为准 | 第 4.6 步 |
| P5 | `assembly.yaml` 清理：删 `version`、`shell`；`asset`、`edge_routes` 留不留 | 删 `version`、`shell`；`asset`/`edge_routes` 等用户定 | [0108]、"一个事实一个家" |
| P6 | 组件仓库是否提交 `brickkit skills update` 写入的 `.claude/skills/brickkit-component/` | 提交 | 第 2.5 步 |
| P7 | 组件自有密钥的环境变量名 `${<UREPO>_<KEY>}`；基础资源密钥沿用原变量名 | 是 | §2.3 第 5 条 |
| P8 | focus 运行之前先跑容器形态（7.8 在 7.10 之前），与 spec 第 7 步写的顺序不同 | 是：focus 不跑迁移、不用镜像，先跑容器才验证得到镜像与迁移 | 第 7.10 步 |

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
- 交接给控制者的内容：提交 SHA、发布说明路径、`make verify` 汇总表与输出目录、契约包 tag 需求

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

**过渡期现象与历史对照（v1.0.1 实测的条目，v1.1.0 起变化处已标注）**

- 根目录 `brickkit lint --all` / `make lint` 在 06b 全程会因为还没重建的旧 `component.yaml`（`dependencies.resources` 等 v0 字段）报错；本地源里有非法的旧清单**不影响** `brickkit add` / `up` 其它组件（scratch 实测）。v1.1.0 起：`brickkit lint <id>`（或在组件目录里不带参数）只检查这一个组件，项目文档（根 `AGENTS.md` 等）也在项目级 lint 范围内，`--all` 才在任何位置查全项目；v1.0.1 时项目内 `brickkit lint` 一律 lint 整个项目、限定不到单个组件，所以当时才有 `component-lint.sh`（现已不用）。
- `config/vars.yaml` 的 `AUTHZ_BUNDLE_URL` / `IAM_JWKS_URL` 用成员服务名 `infra-authz-2-0-0` / `infra-iam-casdoor-2-0-0`（R29/R30）。authz、iam-casdoor 还没加入项目时：这两个主机名解析不到，受保护路由只验到 `401`（判定链在工作），不验 `200`；`service-hostname-scan` 对还没声明的组件只警告。authz、iam-casdoor 作为独立组件加入项目后地址直接可达，验 `200`；它们进 go-infra 外壳后由外壳容器的网络别名解析，值不变。任何阶段都不需要 `deploy.local.yaml` 或 `deploy.teardown.yaml` 的 `vars:` 覆盖，也不改 `config/vars.yaml`。focus 起的宿主机进程解析不了容器服务名，受保护路由在 focus 下只验 `401`。
- `make tier1` 仍是占位（06f 重写）。`make tier0` 是 mdm/customer 专用、带 v0 假设的旧断言。
- `make bump-version`：be-acceptance v0.4.1（父仓库的 `tools/be-acceptance` 已指向它）不再往 `component.yaml` 写历史注释，照常使用（控制者裁定 R26）。分工：首轮 1.x → 2.0.0 时，下游组件的依赖版本在它自己第 3 步整份重写 `component.yaml` 时直接写 `@2.0.0`（那时它的旧文件反正要整份换掉）；**一个组件发布 2.0.0 之后再有任何改动**（修 bug 发 2.0.1、补字段发 2.1.0），以及外壳的 `shell.members` / `go.mod` 跟着成员换版本，一律走 `make bump-version PLAN=<计划文件>`（先 dry-run 看级联，再 `APPLY=1`），一轮改动写一份计划文件，然后按 `version-bump-ship` skill 逐个发布、`brickkit upgrade`。
- `version-bump-ship` skill 和根 `Makefile` 的 `bump-version` 帮助文字还引用已归档的 `00-master-guide.md` SOP-W-11；以 01-development-workflow.md 为准。
- `make test-cross` 只跑 Go（`go test`）。

**scratch 实测（历史，brickKit CLI v1.0.1；与 v1.1.0 不同处：`AGENTS.zh.md` 不再需要翻译的 `## BrickKit` 一节，lint 按组件限定；其余以 `brickkit docs` 为准，scratch 项目 `brickkit init` + 假组件，未起容器）**

- `brickkit new <id> --path <dir>`：写 `component.yaml`（只有 `deployment.build`，注释写着"发布预构建镜像后再加 `image:`"）与 `BRICKKIT.md`/`AGENTS.md`/`CLAUDE.md`/`README.md`；新骨架 `brickkit lint --strict` 报 11 条 `DOC_PLACEHOLDER`。
- `brickkit skills update` 在独立组件仓库里写入 `.claude/skills/brickkit-component/SKILL.md`。
- `brickkit add` 对 required 键写 `KEY: ""`、可选键写注释行（`# PG_SCHEMA: demo_b  # string (default)`）；`local.runCommand` 必须是数组。
- `brickkit up --focus <id> --dry-run`：focus 组件以 `mode: local` 从源码起（Go 默认探测成 `go run .`，所以要写 `local.runCommand`）；依赖照常是容器，并映射到宿主机（`18080:8080`）；提示"mode: local 组件的数据库迁移不会自动跑"。
- 外壳在成员已经独立加入项目之后 `brickkit add`：成员自动移进外壳（`🔗 demo/a moved into shell be/go-x`；与 `brickkit docs 04-shell/04-members-management` 的"`add` doesn't move it into the shell"说法相反，没移时的处理见 §4.4），`deploy.yaml` / `deploy.local.yaml` 同步嵌套，`deploy.teardown.yaml` 不动并提示手工同步；生成文件里外壳服务带 `BRICKKIT_SERVED_MEMBERS=<成员服务名列表>`，镜像名 `be-go-x:1.0.0`。
- `-f deploy.teardown.yaml` 的条目与 `brickkit.yaml` 不一致时报 `DEPLOY_INCONSISTENT`，逐个列出缺的条目。
- 为确认 focus 进程的宿主机端口与 `host.docker.internal` 的处理，读了 brickKit 源码 `internal/compose/local.go`（宿主机端口默认取组件声明的主端口、被占才从 8081 起分配；额外端口原样占用；配置里用了 `host.docker.internal` 的容器自动加 `extra_hosts`）、`internal/cli/up_local.go`（本机进程额外拿到 `PORT`）、`internal/deploy/naming.go`（宿主机上的进程把 `host.docker.internal` 换成 `localhost`）——已作为知识缺口候选报给控制者。
