# 数据层：库身份解耦、冷热生命周期、分区窗口、BatchGet 上限——分析与提案

> 开发文档，只给本项目自己用；正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件文档）不得链接本文件。
> 写于 2026-10-02（06b 设计轮，外壳 T21–T24 之前）。只读调研，未改任何代码、未提交。行号以写作时各仓库工作区为准；"库里实测"指对本机 `be-postgres` 的只读目录查询。
> 判据见 `README.md`：遵循 brickKit 理念、对 AI 开发友好、组件可替换、数据库可按情况替换、能快速定位与迭代。前提是 SDK 可以整体重写。

## 0. 结论

- **先说一个三天后就会出现的问题（P0，与设计无关）。** 13 个组件的迁移里，`event_outbox` / `event_inbox` 的初始周分区全是写死的日期，最晚到 **2026-10-05**；mdm/customer 的更早，只到 **2026-09-28**，已经过期（§4.1）。演示库 `brickkit_db` 没事，组件跑起来时后台任务已经把分区建到 11-02。测试库 `brickkit_test_db` 里，`erp_finance`、`erp_inventory`、`infra_authz`、`infra_notification` 的 outbox/inbox **只到 10-05**（库里实测）。从下周一起，这几个组件的连库测试只要写 outbox，就会报 `no partition of relation`。authz 和 notification 没有任何会顺手建分区的测试。在新机器上从零跑 `make test-db-init`，mdm/customer 今天就已经写不进去了。止血办法见 §6 第 0 步。
- **议题一：库身份。推荐方案 B：SDK 提供绑定身份的库句柄 `Store`，模块和 SDK 内部的所有数据库访问都从它进。** 句柄的角色来自 `PG_USER`，schema 来自 `PG_SCHEMA`，两者都必填，SDK 不提供默认值，也不从 schema 推导角色。outbox 推送、消费、生命周期任务都在 `SET LOCAL ROLE` 之后执行，外壳的登录角色因此可以改成 **NOINHERIT**（最小权限）。配套三件事：迁移里不得出现角色名和 schema 名，由 be-acceptance 新增的两个门禁卡住；SDK 测试套件 `besdktest` 给每个测试包现建随机 schema 和随机角色，在运行期证明身份解耦（R63 第 4 点从"三个组件各写一条"变成"所有连库测试天然覆盖"）；`test-db-init.sh` 改为从 `schemas.tsv` 的角色列取角色。需要扫尾的是 9 个已发布组件：模块里 `schema+"_rw"` 一行，加上 21 处 `OWNER TO`（§2.1）。
- **数据库可替换性：可以接受，但要把边界讲清楚。** 目标是"PostgreSQL 方言族"：PG ≥ 14（NOINHERIT 授权要 16），以及与 PG 兼容的发行版。不追求换成任意 SQL 库。绑定分两层。第一层是**机制**：身份切换、分区与目录查询、`SKIP LOCKED` 认领、advisory 锁、错误码识别、平台表 DDL。这一层今天散在 12 个组件里（每个组件都有一份 `partition/`，6 个组件各有一份 `pgerr.go`），应该**全部收进 SDK 内部的 `pgdialect`**。第二层是**业务 SQL 方言**：`ON CONFLICT`、`RETURNING`、`ANY($1)`、interval。这一层留在各组件的 repo 层；真要换成非 PG 的库，就是按组件移植 repo，这个代价可以接受。`NUMERIC` 是标准类型，`JSONB` 只当不透明存储用（全项目找不到 `->>`、`@>`、`jsonb_` 运算符），两者都不构成绑定（§2.7）。
- **议题二：冷热生命周期。推荐"在线即挂载"模型。** 分区一直挂在主表上，直到在线保留期结束；到期后按策略处理：技术表 `drop`；业务表默认 `keep`，或者配置了对象存储时走 `freeze`（导出到 `S3_URL`、校验、再删）。不再把分区搬进 `<schema>_archive`。好处有三条：组件只需要"一个 schema + 一个角色"；归档表不会和主表的 DDL 漂移；`BatchGetRouted` 不需要冷热路由。List 显式给出更早的时间范围时，查的还是同一张表，天然能读到老数据；只有早于"在线下界"的范围才返回 `OUT_OF_RANGE`。每个组件在 `migrations/lifecycle.yaml` 里声明自己的表和策略（跨语言、门禁可读，配置键 `DATA_LIFECYCLE` 可以覆盖）。SDK 以每个 schema 一把事务级 advisory 锁运行这些策略，多副本、外壳内多成员都安全。附带发现两处必须先修的缺口：inbox 的单调版本判断是对整张 inbox **无索引的 `max(version)`**，表越大越慢，而且删掉旧分区就会丢掉判断依据，所以要先加一张 `event_inbox_watermark` 表；`command_idempotency` 不能分区，只能按 TTL 分批删除（§3）。
- **议题三：分区窗口。** 13 个组件、29 张分区表全部检查过（§4.1）：所有 RANGE 分区的初始分区都是写死的日期；只有 erp/sales 补了 005。推荐**让 SDK 负责建分区**。`migrate.Main` 执行 up 之后，按 `lifecycle.yaml` 建出当前窗口；运行期的 `Plan.Run` 每 6 小时补一次提前量。判断一个分区是否已存在，看**分区边界**（`pg_partition` 目录），不看分区名。新迁移里一律不出现日期字面量，由门禁卡住；已发布的旧迁移保持冻结。finance 的分录行是按会计期间 LIST 分区的，开账靠每年写一份迁移（008 写死了 FY2027），建议改成"开会计年度"命令，由命令同时建期间和分区（§4.4，需拍板）。
- **议题四：BatchGet 上限。** 12 个组件的 14 个按 id 批量取的 rpc（含 customer/product 的 `GetSummary`）都不限个数，SDK 里也没有任何上限。sales 的 `BatchGetOrder` 是逐个 id 各开一个事务的 N+1（`repo/order.go:123`）。`BatchGetRouted` 把 id 拼成 `IN ($1..$N)`，超过 65535 个直接撞上 PG 的绑定参数上限。推荐**在契约里写上限，由 SDK 统一执行**：proto 字段选项 `[(besdk.v1.max_items) = N]`，SDK 的 gRPC 服务端拦截器统一检查，没有声明选项的 `BatchGet*` rpc 用默认值 500，门禁要求每个都写上。超限一律返回 `INVALID_ARGUMENT`，附 `ErrorInfo{reason:"BATCH_TOO_LARGE"}` 和 `BadRequest`；HTTP 返回 400，错误体加 `code` 字段；GraphQL 返回 `BAD_USER_INPUT`。调用方一律经 `besdk.BatchGetAll` 自动分片，TS 的 DataLoader 设 `maxBatchSize`。今天 bff 的入口上限是 100，但 DataLoader 会把同一请求里的多个字段合并，实际发往下游的一批可能超过 100（§5.1）。
- **版本。** be-sdk-go / python / ts 都升 `v0.6.0`，be-acceptance 加两个门禁，be-ops 小版本。12 个有库的组件各发一次版，建议 `2.1.0`（有删数据的新行为，契约也收窄了，见拍板点）。bff 发 `2.0.1`。四个议题合进**同一次**组件发版，不分四轮。外壳 T21–T24 可以照原计划用今天的 INHERIT 授权组装；等全部成员升到 SDK ≥ 0.6，再一次性切到 NOINHERIT（§6）。

## 1. 范围与术语

- **身份**：组件在库里的两个名字：schema（`PG_SCHEMA`）和角色（`PG_USER`）。单独运行时，`PG_USER` 就是连接池的登录角色。在外壳里，连接池以外壳自己的登录角色登录，每个事务里 `SET LOCAL ROLE` 切到成员自己配置的 `PG_USER`。
- **机制 SQL / 业务 SQL**：机制 SQL 是每个组件都要、写法完全一样的那部分：身份切换、建分区与删分区、outbox 认领、inbox 去重、锁、错误分类。业务 SQL 是 repo 层里组件自己的查询。
- **在线 / 冻结**：在线是指行还在库里、挂在主表上、能查到；冻结是指行已经导出到对象存储、从库里删掉，不能在线查询。本文提议取消"热表 / 归档 schema"这层中间态（§3.3）。
- 本文涉及 13 个组件（bff 和前端没有库，所以有库的是 12 个），以及 be-sdk-go v0.5.0、be-sdk-python v0.5.0（print 钉 v0.4.4）、be-sdk-ts v0.5.0、be-ops、be-acceptance v0.4.8。

## 2. 议题一：库身份解耦（R63 扫尾）与数据库可替换性

### 2.1 现状与证据

**SDK**

| 位置 | 现状 | 问题 |
|---|---|---|
| `be-sdk-go/tx.go:20-49` `WithTx(ctx, db, role, schema, fn)` | 调用方传入 role / schema；先 `SET LOCAL ROLE`（:38），再 `SET LOCAL search_path TO <schema>, <schema>_archive`（:42-43） | SDK 不管角色从哪来，所以 9 个组件各自写了 `schema+"_rw"`；`_archive` 写死在 search_path 里 |
| `be-sdk-go/outbox.go:58` `StartOutboxPump(ctx, db, schema, nc, logger)`，`pumpOnce` :109-122 | 直接 `db.QueryContext`，用 `schema.event_outbox` 限定名，**不切角色** | 在外壳里以外壳登录角色执行，所以外壳角色必须 INHERIT 每个成员的角色。sales 的 BRICKKIT"Before you deploy"把这条写成了部署要求（`components/erp/sales/BRICKKIT.md:27`） |
| `be-sdk-go/events.go:96-158` `handleOne` | 会 `SET LOCAL ROLE` / search_path（:114-119） | 正常；但 inbox 判断有隐患，见 §3.1 |
| `be-sdk-go/migrate/migrate.go:216-246` | 只用 `PG_*` 连接；`search_path=<PG_SCHEMA>`，状态表叫 `schema_migrations_<PG_SCHEMA>` | 已经与身份解耦：表属于跑迁移的登录角色 |
| `be-sdk-go/connection.go:19` `PGDSN` | `PG_USER` 只用来登录 | — |
| `be-sdk-go/shell/run.go:109-113` | 外壳用**自己的** `PG_*` 开唯一的连接池 | 成员配置里的 `PG_HOST/PG_PORT/PG_DATABASE` 被**静默忽略**：成员配置写的是库 B，外壳实际连的是库 A，不报错 |
| `be-sdk-python/besdk/tx.py:16-61` `with_tx` | 与 Go 同构 | 同上 |
| `be-sdk-python/besdk/outbox.py:63` `start_outbox_pump(pool, schema, nc)` | 不切角色 | 同 Go |
| `be-sdk-python` 迁移 | SDK 不提供迁移入口；print 自己写了 `infra_print/migrate.py`，`_DEFAULT_SCHEMA="infra_print"`（:28、:34、:61） | 默认 schema 字面量写在组件里 |
| `be-sdk-ts` | 没有数据库相关代码（bff 不连库，是硬规则） | — |

**组件（模块代码里的角色从哪来）**

| 组件 | 状态 | 角色 | 默认 schema 字面量 | 迁移里的 `OWNER TO` |
|---|---|---|---|---|
| mdm/customer | 已发布 2.0.1 | `module.go:33` `schema+"_rw"` | `module.go:30` | `002:44,69` |
| mdm/product | 已发布 2.0.0 | `module.go:31` | `module.go:30` | `002:45,70` |
| erp/inventory | 已发布 2.0.0 | `module.go:28` | `module.go:27` | `001:97`、`002:40,67` |
| erp/finance | 已发布 2.0.0 | `module.go:31` | `module.go:28` | `001:170`、`002:40,67` |
| infra/authz | 已发布 2.0.1 | `module.go:27` | `module.go:26` | `002:41,73` |
| infra/workflow | 已发布 2.0.1 | `module.go:33` | `module.go:30` | `002:41` |
| infra/notification | 已发布 2.0.0 | `module.go:29` | `module.go:28` | `001:65`、`002:35,57` |
| integration/im-dingtalk | 已发布 2.0.0 | `module.go:40` | `module.go:37` | `001:47`、`002:34,56` |
| infra/print（Python） | 已发布 2.0.0 | `infra_print/module.py:25` `f"{schema}_rw"` | `module.py:24`、`migrate.py:28` | `001_create_print.sql:71`、`002_create_outbox.sql:35` |
| infra/iam-casdoor | R63 已做 | `module/settings.go:69` 取 `PG_USER` | `settings.go:65` 仍有默认值 | 无 |
| erp/sales | R63 已做 | `module/module.go:111` 取 `PG_USER`，校验并点名 | `module.go:107` 仍有默认值 | 无；`005` 注释写明不出现角色名 |
| crm/opportunity | R63 已做 | `module/module.go:81` | — | 无（`002:44` 注释） |

`OWNER TO` 一共 21 处，分布在 9 个组件里。全部迁移里**没有**限定名（形如 `<schema>.<表>` 的写法），也没有 `CREATE SCHEMA`、`GRANT`、`SET`。

**测试代码**：101 个测试文件写死了 `"<schema>_rw"` 或 `_ROLE = "…"`（finance 19、sales 25、inventory 10、iam 8、print 8、customer 8……）。只有 crm/opportunity 的 `backend/testdb/testdb.go:17-20` 允许用 `TEST_PG_ROLE` / `TEST_PG_SCHEMA` 覆盖。R63 的身份证明测试只有三条：`erp/sales/backend/module/identity_test.go`、`crm/opportunity/backend/module/identity_test.go`、`infra/iam-casdoor/backend/module/dbidentity_test.go`。三条都用 NOINHERIT 外壳角色证明业务读写走的是 `PG_USER`，但**都没有启动 outbox 推送**，所以没有覆盖 §2.1 第二行的那个缺口。

**advisory 锁的键**：生产代码里只有 iam 两处，用的是 `hashtext(current_schema() || '.webhook_deliveries')`（`repo/webhookdeliveries.go:29`、`repo/refreshtokens.go:192`），已经与 schema 名解耦。写死 schema 名的只有测试辅助 `integration/im-dingtalk/backend/internal/testlock/testlock.go:16` 的 `hashtext('integration_im_dingtalk.dingtalk_token')`。题目里说的"有些锁键写死了 schema"，查下来只剩这一处，而且是测试代码。

**项目侧脚本**

- `infra/scripts/test-db-init.sh:58-81`（①b 步）：把 postgres 名下的旧对象转给 `'${schema}_rw'`（:77）。`:90`：`PG_USER="${schema}_rw"`。两处都从 schema 名推导角色。同一目录下的 `lib/db-pw.sh:15` 读的是 `schemas.tsv` 的第 3 列（角色列），说明正确的数据源一直都在。
- `tools/be-ops/internal/dbscript/gen.go:152-188`：每个组件建 schema 和 `<schema>_archive`，角色带 `LOGIN`，授 USAGE+CREATE，再加默认权限。:203 是 `GRANT <成员角色> TO <外壳角色>`（PG16 下默认 INHERIT）。
- 文档：`docs/en/01-conventions/04-configuration.md:43-45` 写的是"`PG_USER` 就是 `schemas.tsv` 的角色列"，外壳 `SET LOCAL ROLE <member>_rw`；`07-registries.md:53-54` 写了 `<schema>_archive` 和 `<schema>_rw` 的命名规则。这些都是**本项目**的取名约定，本身没错；问题在于组件代码把这套约定当成了自己的假设。

### 2.2 目标形态

一个组件对数据库的全部要求，就是 BRICKKIT"Before you deploy"里的一句话：

> 一个 schema、一个能连库的登录角色；角色对这个 schema 有 USAGE + CREATE，并且由它来跑迁移（所以迁移建出的每一张表都归它所有）。两个名字随意取，填进 `PG_SCHEMA` 和 `PG_USER`。外壳托管时，外壳的登录角色要是 `PG_USER` 的成员，可以是 NOINHERIT。

为此要保证：

1. 组件的代码、迁移、SDK 都不会从一个名字推出另一个名字（不出现 `_rw`、`_archive`、`shell_`），也不写任何组件自己的 schema 或角色字面量（测试代码除外）。
2. 所有数据库访问（业务事务、outbox 推送、消费、生命周期、启动探测）都在 `SET LOCAL ROLE <PG_USER>; SET LOCAL search_path TO <PG_SCHEMA>` 之后执行。外壳登录角色因此不需要直接拥有任何成员的权限。
3. 迁移只用不带限定的名字，靠 search_path 解析；不写 `OWNER TO`、`GRANT`、`CREATE SCHEMA`、`SET`，也不写日期字面量（日期见 §4）。
4. 上面三条，**静态门禁**和**运行期证明**（每个连库测试都跑在随机身份下）各盖一遍。

### 2.3 可选方案与取舍

| | A. 最小扫尾 | **B. SDK 身份句柄 `Store`（推荐）** | C. 外壳里每个成员一个连接池 |
|---|---|---|---|
| 做法 | 9 个组件把 `schema+"_rw"` 换成读 `PG_USER`，删掉 `OWNER TO`；SDK 不动 | SDK 新增 `DBIdentityFrom(cfg)` 和 `Store`；pump、消费、生命周期都改收 `Store`，内部切角色；组件只调 `besdk.OpenStore(rt)` | 外壳给每个成员按它自己的 `PG_*` 单独开池，以成员角色登录，DSN 里带 `search_path`，不再需要 `SET LOCAL ROLE` |
| 外壳登录角色 | 必须 INHERIT（pump 不切角色） | **可以 NOINHERIT** | 不需要外壳登录角色 |
| "SET 漏写 LOCAL"这个雷 | 仍在 | 仍在，但只剩 SDK 一处 | **彻底消失** |
| 每个组件重复的代码 | 9 份身份读取逻辑，各自校验 | 1 份 | 1 份 |
| 连接数 | 一个外壳一个池 | 同左 | 成员数 × 池大小（go-core 有 6 个以上成员） |
| 与决策的关系 | 一致 | 一致 | **与 0102 冲突**：它的"Why"就是共享一个池加 `SET LOCAL ROLE` |
| 成员和外壳不在同一个库 | 静默错连 | 外壳启动时比对，不一致就拒绝启动 | 天然支持 |
| AI 友好 | 每个组件都要记住规则 | 只有一个入口，签名本身就说明问题 | 最简单，但要先改决策 |

C 在概念上最干净（"外壳只把 N 个进程变成一个"）。但它推翻 0102，连接数也是实打实的代价，而且项目目前没有一个成员需要独立的库。所以 **C 作为 0102 的"何时重议"条件记下来**：等真出现"某个成员必须用另一个库"时再考虑。

### 2.4 推荐：方案 B

1. **SDK 是读取身份的唯一入口。** `DBIdentityFrom(cfg)` 读 `PG_USER` 和 `PG_SCHEMA`。两者都必填，缺了或者名字不合法，就报错并点名是哪个键，不提供任何默认值。9 个组件里 `StringOr("PG_SCHEMA", "<字面量>")` 这种写法一起删掉：configSchema 本来就声明了 `PG_SCHEMA`，默认值应该写在 component.yaml 里，不该写在代码里。
2. **`Store` 是模块里唯一的库句柄。** `rt.DB` 不再交给业务代码，只供 SDK 内部使用；一个 minor 版本内保留 `WithTx(db, role, schema)` 作为过渡包装，并标成 Deprecated。
3. **`StartOutboxPump` / `Consume` / `PublishOutbox` 改成收 `Store` 或 `tx`。** pump 的认领和状态回写都放进 `store.Tx`，带 `SET LOCAL ROLE`。表名不再写 `schema.event_outbox`，靠 search_path 解析，这样 SDK 里也不再拼 schema 名。
4. **search_path 只放 `PG_SCHEMA`。** 去掉 `<schema>_archive`（理由见 §3.3）。保留它也没有坏处：PG 会忽略 search_path 里不存在的 schema。但不再把它当成约定的一部分。
5. **外壳启动时做一致性检查**（在 `be-sdk-go/shell/run.go` 的 `buildModules` 之前）。成员配置里如果出现了 `PG_HOST`、`PG_PORT` 或 `PG_DATABASE`，而且和外壳自己的值不同，就拒绝启动，并点名成员和键。不能让配置说一套、实际连另一套。
6. **启动探测**（放在 Start 里，不放进 `/healthz`）。首轮在 `store.Tx` 里检查 `has_schema_privilege(current_user, current_schema(), 'USAGE,CREATE')`，并确认 schema 里不存在属主不是 `PG_USER` 的表。失败只记一条 ERROR，再导出指标 `besdk_db_identity_ok{component}=0`，不让模块退出。这样"角色配错"在启动时就被看到，不用等到第一个请求。
7. **NOINHERIT 分两步走。** 全部成员升到 SDK ≥ 0.6 之后，be-ops 改成生成 `GRANT <成员角色> TO <外壳角色> WITH INHERIT FALSE, SET TRUE`（PG16 语法；本机是 `postgres:16-alpine`，见 `infra/docker-compose.infra.yml:26`）。改之前保持现状。
8. **`besdktest` 测试套件**（Go 和 Python 都提供）。每个测试包在 `TEST_PG_DSN` 指向的库里现建一个随机 schema 和一个随机登录角色，只授 USAGE+CREATE；以这个角色跑组件迁移；另建一个 NOINHERIT 的"外壳"角色；测试结束时 `t.Cleanup` 全部删掉。R63 第 4 点于是从"各组件补一条专门的测试"变成"所有连库测试默认就在证明它"。它还能让测试包之间并行（memory 里 E2 那类抢数据的问题也随之消失）。代价是每个测试包多跑一次迁移，目前每个组件在秒级。
9. **`test-db-init.sh`**：`:77`、`:90` 两处改成按 repo 名从 `registry/schemas.tsv` 的第 3 列取角色（与 `lib/db-pw.sh:15` 同一来源）。等全部组件改用 `besdktest` 以后，`brickkit_test_db` 只是给 `besdktest` 提供连接的库，①b 那段转属主可以删掉。

### 2.5 SDK API

**Go（be-sdk-go v0.6.0）**

```go
// 库身份：PG_USER 是每个事务切换到的角色，PG_SCHEMA 是 schema。两者必填、无默认、不互相推导。
type DBIdentity struct{ Role, Schema string }
func DBIdentityFrom(cfg Config) (DBIdentity, error)

// Store：绑定身份的库句柄。模块里一切 SQL 从这里进；rt.DB 只给 SDK 内部。
type Store struct{ /* db *sql.DB; id DBIdentity */ }
func OpenStore(rt *Runtime) (*Store, error)
func (s *Store) Identity() DBIdentity
func (s *Store) Tx(ctx context.Context, fn func(*sql.Tx) error) error
func (s *Store) TxWith(ctx context.Context, o TxOptions, fn func(*sql.Tx) error) error
type TxOptions struct {
	ReadOnly    bool
	LockTimeout time.Duration // SET LOCAL lock_timeout，生命周期 DDL 用
}

// 机制原语（PG 方言集中在 SDK，组件不再各写一份 pgerr.go）
func XactLock(ctx context.Context, tx *sql.Tx, name, key string) error           // pg_advisory_xact_lock(hashtext(current_schema()||'.'||name), hashtext(key))
func TryXactLock(ctx context.Context, tx *sql.Tx, name, key string) (bool, error)
func IsUniqueViolation(err error) bool
func IsSerializationFailure(err error) bool
func IsLockTimeout(err error) bool

// 事件（签名变了：不再收 schema / role）
func PublishOutbox(tx *sql.Tx, ev Event) error
func StartOutboxPump(ctx context.Context, s *Store, nc *nats.Conn, logger *slog.Logger) error
func Consume(ctx context.Context, nc *nats.Conn, s *Store, subject string, fn Handler) error

// Deprecated: 用 Store.Tx。v0.7 删除。
func WithTx(ctx context.Context, db *sql.DB, role, schema string, fn func(*sql.Tx) error) error
```

```go
// 测试套件 github.com/brickKit/be-sdk-go/besdktest（只在 _test.go 里 import）
func NewStore(t testing.TB, migrations fs.FS, opts ...Option) *besdk.Store // 随机 schema + 随机登录角色，以它跑迁移
func ShellView(t testing.TB, s *besdk.Store) *besdk.Store                  // 同一身份，但以 NOINHERIT 外壳角色登录
func WithClock(now time.Time) Option                                       // 迁移后建窗口用的"今天"（§4 的红测试要用）
```

**Python（be-sdk-python v0.6.0）**：与 Go 一一对应。

```python
@dataclass(frozen=True)
class DBIdentity:
    role: str
    schema: str
    @classmethod
    def from_config(cls, cfg: Config) -> "DBIdentity": ...

class Store:
    @classmethod
    async def open(cls, rt: Runtime) -> "Store": ...
    @property
    def identity(self) -> DBIdentity: ...
    def tx(self, *, read_only: bool = False, lock_timeout: float | None = None) -> AsyncContextManager[asyncpg.Connection]: ...

async def xact_lock(conn, name: str, key: str) -> None: ...
async def try_xact_lock(conn, name: str, key: str) -> bool: ...
def is_unique_violation(exc: BaseException) -> bool: ...
async def publish_outbox(conn, ev: Event) -> None: ...
async def start_outbox_pump(store: Store, nc) -> None: ...

# 新增：迁移入口进 SDK（print 的 migrate.py 缩成一行 besdk.migrate.main()）
besdk.migrate.main(migrations_dir: Path = Path("migrations")) -> NoReturn
# 测试：pytest fixture
besdk.testing.fresh_store(migrations_dir) -> Store
```

**TS（be-sdk-ts）**：bff 不连库，本议题对 TS 没有改动。

### 2.6 门禁（be-acceptance 新增两个，接进 `make gates`）

1. **`migration-identity-scan`**：扫描每个组件 `migrations/` 下的 `*.sql` 和 yoyo 的 `*.py`。
   - **报错**：`OWNER TO`、`GRANT`、`REVOKE`、`CREATE SCHEMA`、`CREATE ROLE`、`ALTER ROLE`、`SET ROLE`、`SET search_path`、`SET SESSION AUTHORIZATION`；任何以本组件 registry schema（或它加 `_archive`）开头的限定名；任何 `\b\w+_rw\b` 或 `\bshell_\w+\b` 形式的标识符。
   - **报错，只对新文件**：`PARTITION OF … FOR VALUES FROM ('<日期>')` / `IN ('<期间>')` 这类日期字面量。"新文件"指上一个发布 tag 里还不存在的迁移文件。已发布的文件是冻结的（R63 只允许做零效果的删除），对它们只报警告。
   - **注释不算**：先去掉 `--` 和 `/* */` 注释再扫，所以 sales 005 里"不写 schema 名和角色名"这类说明不会误报。
2. **`identity-literal-scan`**：扫非测试代码。Go 用 AST，Python 用文本。
   - **报错**：字符串拼接里出现 `"_rw"` 或 `"_archive"`，或者 f-string 里出现 `_rw`；`StringOr("PG_SCHEMA", <非空字面量>)` / `string_or("PG_SCHEMA", …)`；任何与本组件 registry schema 名或角色名完全相同的字符串字面量；`hashtext('<字面量>.`。
   - **警告**：测试文件里直接写组件角色字面量的，算作"还没迁到 besdktest"，用来跟踪迁移进度。

静态门禁只负责快速反馈，真正的保障是 `besdktest` 在运行期使用随机身份：只要哪里漏了一个字面量，测试会直接失败。

### 2.7 数据库可替换性：今天绑定了什么

统计范围是 12 个有库组件的非测试代码和迁移，加上两个 SDK（每类的数字是"匹配行数 / 涉及组件"）。

| 类别 | 用法（行数 / 组件） | 归属 | 换库的代价 |
|---|---|---|---|
| 身份切换 `SET LOCAL ROLE` / `search_path` | SDK `tx.go`、`events.go`；py `tx.py` | **机制，SDK 独占** | 这是 0102 的核心机制；非 PG 库（MySQL 的 schema 就是 database，SET ROLE 语义也不同）需要在 SDK 里换一套实现 |
| 声明式分区 + `to_regclass` | 分区相关 338 行 / 12 组件；`to_regclass` 32 / 12 组件 + 2 SDK | **机制，收进 SDK**（§4） | 收进 SDK 以后只剩一个实现 |
| `FOR UPDATE SKIP LOCKED` 认领 | 7 行：SDK outbox、iam webhook 队列、workflow | **机制，收进 SDK**（`ClaimBatch`，见拍板点 6） | MySQL 8 也支持；SQLite 不支持 |
| advisory 锁 | iam 2 处（生产），dingtalk 1 处（测试） | **机制，收进 SDK**（`XactLock`） | CockroachDB 没有 |
| 错误码识别（23505 / 40001 / 42P01） | 6 个组件各有一份 `pgerr.go`，另有 4 个组件在 `repo.go` 里自己判断 | **机制，收进 SDK** | — |
| `ON CONFLICT`（40）/ `RETURNING`（28）/ `ANY($1)`（14 / 6）/ `array_agg`、`unnest`（3）/ interval（54）/ `LIKE … \|\| '%'`（15） | 业务 SQL | **方言，留在 repo** | 按组件移植 repo 层 |
| `BIGSERIAL` / `GENERATED`（60） | DDL | 方言 | 迁移要重写 |
| `NUMERIC`（90 / 7） | 金额 | 标准 SQL | 无 |
| `JSONB`（23） | 只当不透明存储，没有任何 `->>` / `@>` / `jsonb_` | 方言（存储） | 换成 JSON 类型即可 |
| `TIMESTAMPTZ`（179） | — | 基本是标准 | 小 |

**判断**：可以接受。理由有三。

1. 0102 已经决定"所有组件共用一个 PostgreSQL 库"，"数据库可替换"的现实含义就是**整套换成另一个 PG 兼容引擎**。要在 PG 能力之外再给某个组件单独配存储，属于 0102 的"何时重议"情形，由组件自己的配置来接，不影响其它组件。
2. 真正会让换库变成"改 12 个组件"的，是机制层。今天它散在每个组件的 `partition/`、`pgerr.go` 和手写的 SKIP LOCKED 里。全部收进 SDK 以后，换一个 PG 兼容引擎只需要验证 SDK 这一份实现。
3. 业务 SQL 用 PG 方言，是"不用 ORM"（0103）的直接结果。repo 是唯一写 SQL 的层，移植的边界很清楚。

**SDK 怎么隔离**：在 SDK 内部建 `pgdialect` 包，不对外暴露成可替换的接口。等第二种方言真的出现时，再把接口抽出来（AI 友好：一个实现、一个位置）。`Store` 打开时做一次能力探测：`server_version_num >= 140000`、支持声明式分区、支持 `SKIP LOCKED`。不满足就在启动时报错，并点名缺的是哪项能力。

**目标引擎的分级**：

- **确定可用**：PostgreSQL 14–17；云上托管的 PG（RDS / Aurora PG / Cloud SQL / AlloyDB / Azure Flexible）。
- **很可能可用，要实测**：基于 PG 的国产发行版（人大金仓 Kingbase、瀚高 Highgo）。这条和信创相关，见拍板点 5。
- **未验证 / 预计要改 SDK**：openGauss / GaussDB（分区语法、角色语义和 PG 有差异）；YugabyteDB。
- **不支持**：CockroachDB（没有 advisory 锁）；MySQL / OceanBase-MySQL / 达梦（要换一套身份机制，还要移植 repo）。

### 2.8 各组件要改什么（议题一部分）

- **9 个已发布组件**（customer、product、inventory、finance、authz、workflow、notification、im-dingtalk、print），每个都要做：
  - `module.go` 里的身份两行改成 `besdk.OpenStore(rt)`；
  - repo / partition / consumer 改收 `*besdk.Store`；
  - 删除迁移里的 `OWNER TO`（行号见 §2.1 的表）；
  - 删除默认 schema 字面量；
  - 连库测试改用 `besdktest`；
  - BRICKKIT"Before you deploy"（中英两份）改成 §2.2 那句通用表述。

  print 还要把 `migrate.py` 换成 `besdk.migrate.main()`，并删掉 `_DEFAULT_SCHEMA`。
- **3 个已做 R63 的组件**（iam、sales、opportunity）：删除剩下的 `StringOr("PG_SCHEMA", …)` 默认值（iam `settings.go:65`、sales `module.go:107`）；把自写的 `identRe` 校验换成 `DBIdentityFrom`；测试迁到 `besdktest`；现有的 `identity_test.go` 补上"NOINHERIT 外壳角色下 pump 也能发布"这一步，或者直接由 besdktest 的通用用例替代。
- **删除 `OWNER TO` 的证明**（R63 第 2 点）：每个组件跑 `make test-db-init ID=<id>`（连跑两次，证明幂等），再在 `brickkit_test_db` 和 `brickkit_db` 两个库里对比表属主，证明没有变化。golang-migrate 不校验文件内容，可以放心改；yoyo 按迁移 id 记账、不比对内容，这一点要先用 print 实测确认。
- **be-ops**：第 4 段（`gen.go:190-206`）的 `WITH INHERIT FALSE` 按 §2.4 第 7 条，等第二步再上。`<schema>_archive` 的创建与授权，等 §3 落地后再删。
- **项目文档**：`04-configuration.md`"Database roles"一节改写：`PG_USER` 取 registry 的角色列，这是本项目的约定；组件对角色名没有任何假设。`02-backend.md` Database 一节的第一条改成 `Store`。

### 2.9 先写的红测试（议题一）

- **be-sdk-go**（真 PG，在 v0.5.0 上应当失败或编译不过）：
  - `TestDBIdentityFrom_缺PG_USER报错点名`
  - `TestDBIdentityFrom_不从schema推角色`
  - `TestDBIdentityFrom_非法名报错`
  - `TestStore_Tx里current_user就是PG_USER`
  - `TestStartOutboxPump_外壳登录角色NOINHERIT也能认领并发布`（v0.5.0 上应报 permission denied）
  - `TestConsume_外壳登录角色NOINHERIT也能落inbox`
  - `TestXactLock_键随current_schema变化_两个schema互不阻塞`
  - `TestBesdktest_NewStore_随机身份迁移后表属主是该角色_清理后角色与schema都不在`
- **be-sdk-go shell**：`TestRun_成员PG_HOST与外壳不同_拒绝启动并点名`。
- **be-sdk-python**：上述用例各写一份对应版本；另加 `test_migrate_main_非默认schema与角色`。
- **be-acceptance**：
  - `TestMigrationIdentityScan_OWNER_TO报错`
  - `…_限定名报错`
  - `…_registry角色名报错`
  - `…_注释里的角色名不报`
  - `…_冻结文件的日期字面量只警告`
  - `…_新文件的日期字面量报错`
  - `TestIdentityLiteralScan_schema拼_rw报错`
  - `…_PG_SCHEMA带字面量默认值报错`
  - `…_测试文件只警告`
- **be-ops**：`TestGen_外壳成员授权_INHERIT开关`（第二步启用）。
- **项目脚本**：`infra/scripts/tests/test_test_db_init.sh`：给一份 schemas.tsv，其中某一行角色列故意不是 `<schema>_rw`，断言迁移用的是角色列。
- **每个组件**：迁到 `besdktest` 以后，全部连库测试本身就是红测试，第一次运行会暴露所有剩下的字面量。

## 3. 议题二：冷热数据生命周期

### 3.1 现状与证据

| 已有的 | 证据 | 实际情况 |
|---|---|---|
| 约定："旧分区用 `DETACH CONCURRENTLY` 摘进 `<schema>_archive`" | `docs/en/01-conventions/02-backend.md:134` | **没有任何代码这样做**：全项目非测试代码里 `DETACH` 和 `DROP TABLE` 都是 0 处 |
| 归档 schema | be-ops `gen.go:155-158` 建 `<schema>_archive` 并授权；`tx.go:42-43` 把它放进 search_path | 两个库里都是空的 |
| `BatchGetRouted` 冷热路由 | `be-sdk-go/archive.go:21-72` | 只有 mdm/customer、mdm/product 在用（`repo/read.go:28`）；它们注释里写着"本组件不归档"，所以这条路径从来没有真正执行过。sales、opportunity 这些真有大表的组件不用它。Python 的 `batch_get_routed` 是 `NotImplementedError`（`besdk/archive.py:36`） |
| List 默认 90 天窗口 | `be-sdk-go/query.go:6,25-40` `ListWindow`；使用者：customer、product、sales、opportunity、finance（2 处）、inventory（只用分页上限） | 显式给出更早的范围也只查主表；数据从没被摘走过，所以今天"能查到"是碰巧。Python 的 `list_window` 是 `NotImplementedError`（`besdk/query.py:28`） |
| 主数据也套 90 天窗口 | `mdm/customer/backend/internal/repo/read.go:67-71,144`；product 同理；契约注释 `customer.proto:120` 写着"未传时间范围时框架层自动注入最近 90 天" | 默认列表里看不到 90 天前建档的客户。对主数据来说这多半不是想要的效果（拍板点 3） |

**技术表一行都不清理**：

| 表 | 证据 | 隐患 |
|---|---|---|
| `event_outbox`（12 个组件都有，周分区） | 状态改成 PUBLISHED 后永远留着（`outbox.go:178-180`） | 无限增长 |
| `event_inbox`（9 个组件，周分区；workflow、authz、print 没有 inbox） | `events.go:124-125`：`SELECT max(version) FROM event_inbox WHERE subject=$1 AND aggregate_id=$2`。inbox 上只有 `(idempotency_key, created_at)` 一个索引（例如 `erp/sales/migrations/002_create_outbox_inbox.up.sql:60`） | ① **每消费一条事件就把所有分区全扫一遍**，越来越慢；② 它就是"版本单调"的依据。如果直接删掉旧分区，一个很久没变过的聚合，它的旧版本事件被重放时（JetStream 从头重放、DLQ 重新投递）就会被**再应用一次** |
| `command_idempotency`（customer、product、inventory、finance、sales、opportunity、workflow；notification 已在 `003` 删掉） | 不分区，主键是 `idempotency_key`（例如 sales `002:65-70`） | 无限增长；它也不能分区，因为分区表的唯一键必须包含分区键，跨分区就去不了重 |
| 队列型分区表：iam `webhook_deliveries`、dingtalk `delivery_attempts`、notification `notification_records` | iam `005_webhook_delivery_queue.up.sql`：RECEIVED 表示还在排队；notification `001:21-22`：PENDING / ACCEPTED / RETRYING 表示还没结束 | 一旦开始清理，必须避开还没结束的行 |
| 不分区但会一直增长的业务表 | workflow `workflow_tasks`、opportunity `opportunity_stage_history`、finance `finance_journal_entries`（头表）/ `ar_ledger`、sales `sales_order_reconciliation_queue` | 各自的迁移注释给了"刻意不分区"的理由（例如 finance `001:66-70`：唯一约束不能带期间）。生命周期只能对这些表做"按行"策略，或者不管 |

### 3.2 需求

1. 组件声明自己有哪些表，以及每张表的保留策略和归档策略；部署方可以用配置覆盖，但不能低于组件声明的下限（例如财务凭证的法定保存期）。
2. 多副本、外壳内多成员都要安全：同一个 schema 同一时刻只有一个执行者；不同 schema 之间互不阻塞。
3. 调用方显式请求更早的时间范围时，能读到老数据；超出在线范围时明确报错，不能静默截断。
4. 给"冻结到对象存储（`S3_URL`）"留好钩子。
5. 默认策略要保守，参照 0205 的 fail-closed 思路：**业务数据默认从不自动删除**；技术表可以删，但要有守卫条件。

### 3.3 可选方案

| | A. 只清技术表 | **B. 在线即挂载 + 到期删除或冻结（推荐）** | C. 按现有约定摘进 `<schema>_archive` | D. 同一 schema 内放归档父表 |
|---|---|---|---|---|
| 业务表的老分区 | 永远挂着 | 挂着直到在线保留期结束，然后 keep / freeze | 过了热期就摘进归档 schema，挂到那边的父表上 | 同 C，但归档父表是同 schema 里的 `<表>_archive` |
| 组件对库的要求 | 一个 schema | **一个 schema** | 两个 schema（与 §2.2 矛盾） | 一个 schema |
| 读老数据 | 天然能读 | **天然能读**（查的是同一张表） | 需要路由：List 要 UNION ALL，BatchGet 要 `BatchGetRouted` | 同 C |
| DDL 漂移 | 无 | 无 | **有**：主表每加一列，归档父表也得同步加，否则 ATTACH 会失败 | 有 |
| BatchGet 代价 | 每个分区探一次 PK 索引 | 同左（120 个月分区也只是毫秒级） | 热表命中就不查归档 | 同 C |
| 冻结钩子 | 无 | 到期的分区：DETACH → 导出 → 校验 → DROP | 从归档 schema 导出 | 同 C |
| 复杂度 | 最低 | 低 | 高 | 中高 |

把分区摘走，带来的收益本来是：分区多时规划器更快、热查询碰不到冷数据、冷数据可以单独删索引。在当前量级下：PG14 以后几百个分区的裁剪不是问题；时间窗口已经保证默认查询只打到最近的分区；单独删冷数据索引的需求还不存在。这几条收益抵不过路由和 DDL 漂移的成本。**选 B**，并把"何时重议"写清楚：单张表在线分区超过约 1000 个，或者实测 BatchGet 探测分区的耗时成为瓶颈时，再考虑 D。

### 3.4 推荐：B 的具体形态

**声明**：每个组件在 `migrations/lifecycle.yaml` 里声明（随迁移一起嵌进镜像；golang-migrate 的 iofs 和 yoyo 都会忽略不符合命名规则的文件，**这一点先写最小复现确认**，见 memory "先验证新机制"）：

```yaml
# erp/sales 示例
tables:
  sales_orders:
    partition: {by: created_at, grain: month, ahead: 3}
    list_window: 90d          # ListWindow 的默认窗口；none = 不注入
    online: forever           # 在线保留期；最短值由组件声明（min），配置只能往长了调
    then: keep                # keep | freeze | drop
  sales_order_items:
    partition: {by: order_created_at, grain: month, ahead: 3}
    follows: sales_orders     # 跟随主表：同边界一起建、一起冻结
platform:                     # SDK 自带的表，写一行就启用对应的内置策略
  outbox: {online: 14d}
  inbox: {online: 30d}        # 必须大于 JetStream 流的 max_age + 重投递窗口（与 events-consistency.md 对齐）
  command_idempotency: {ttl: 7d}
```

配置覆盖：可选键 `DATA_LIFECYCLE`（YAML 或 JSON 字符串，例如 `{"sales_orders":{"online":"10y","then":"freeze"}}`），以及 `DATA_LIFECYCLE_MODE`（`on` / `dry-run` / `off`，默认 `on`）。两个键都要写进各组件的 configSchema。覆盖值低于 `min`、写了不存在的表、把业务表设成 `then: drop` 但没有写 `allow_drop: true`，都在启动时报错并点名。

**执行**（`Plan.Run`，放在 Module.Start 里；每 6 小时跑一轮，带随机抖动，启动时先跑一轮）：

1. 每一步一个事务，事务里先取 `pg_try_advisory_xact_lock(hashtext(current_schema()||'.besdk.lifecycle'), hashtext(<步骤名>))`。取不到就跳过，说明另一个副本正在做。锁键由 schema 派生，所以外壳里多个成员互不阻塞，代码里也不出现 schema 字面量。
2. 所有 DDL 都设 `SET LOCAL lock_timeout = '3s'`，超时就放到下一轮再试。不用 `DETACH CONCURRENTLY`：它不能在事务里执行，只能在会话级连接上做，会把"SET 必须带 LOCAL"这条铁律再撕开一个口子。普通 DETACH 或 DROP 只锁父表一瞬间，配合锁超时，对夜间维护足够。`02-backend.md:134` 的约定相应要改。
3. 每轮依次做：**EnsureAhead**（§4）→ **Expire**（找出在线期已过的分区，按 `then` 处理）→ **Sweep**（按 TTL 清理 `command_idempotency`：每批 `DELETE … WHERE ctid IN (SELECT ctid … LIMIT 5000)`，一批一个事务）。
4. **守卫条件**（内置，不允许绕过）：
   - outbox 分区只有在 `NOT EXISTS (… status <> 'PUBLISHED')` 时才删；有卡住的行就不删，并导出 `besdk_lifecycle_blocked{table}` 指标；
   - 队列型业务表在 yaml 里写 `guard: "status NOT IN ('PENDING','ACCEPTED','RETRYING')"`，SDK 校验分区里没有不满足条件的行之后才动；
   - `then: freeze` 但没有配置存储端时，到期分区原样保留，只记 WARN。没有存储端就绝不删除业务数据。
5. **inbox 水位表**（SDK 平台迁移，见下）：`event_inbox_watermark(subject, aggregate_id, max_version, updated_at)`，主键 `(subject, aggregate_id)`，不分区，行数等于聚合数，有上界。`handleOne` 改成在同一事务里 `INSERT … ON CONFLICT DO UPDATE SET max_version = GREATEST(…)`，先判断后写入。它同时解决两件事：每条事件全表扫描的性能问题，以及删分区以后丢失版本依据的正确性问题。第一次上线时，用现有 inbox 回填：`INSERT … SELECT subject, aggregate_id, max(version) … GROUP BY 1,2`。这一条与 `events-consistency.md` 有交叉，以那份文档的投递语义为准。
6. **审计日志**：SDK 平台表 `besdk_lifecycle_log(id, at, table_name, partition, action, rows, receipt, status)`。冻结是一个状态机（`DETACHED → EXPORTED → VERIFIED → DROPPED`），进程重启后可以从中断处接着做。

**SDK 平台迁移**：`migrate.Main(migrations.FS)` 先跑完组件自己的迁移，再跑 SDK 嵌入的平台迁移。平台迁移用单独的状态表 `besdk_migrations_<PG_SCHEMA>`，全部写成 `IF NOT EXISTS`。outbox / inbox / command_idempotency 的规范 DDL、水位表、生命周期日志都在这里。对已有组件，它只新增水位表和日志表，其余是空操作；新组件不需要再写 `002_create_outbox_inbox`。最后它按 `lifecycle.yaml` 建出当前分区窗口（§4）。Python 的 `besdk.migrate.main()` 对 yoyo 做同样的事，平台迁移 id 带 `besdk-` 前缀。

**读取**：

- `Plan.Window(table, q)` 取代 `ListWindow`：按表的 `list_window` 补默认窗口，按页大小上限夹紧（沿用 `maxLimit=500`）；如果 `q.From` 早于这张表的**在线下界**（最老一个挂载分区的下边界，从 `pg_partition` 目录读取，缓存 1 小时），就返回 `ErrRangeNotOnline`。gRPC 映射为 `OUT_OF_RANGE` 加 `ErrorInfo{reason:"RANGE_NOT_ONLINE", metadata:{online_from}}`，HTTP 映射为 400（`gin.go:146` 已经有这条映射）。
- `BatchGetRouted` 退化成直接查主表。保留函数名，标成 Deprecated，删掉查归档的分支；Python 版补上实现。
- **契约不变**：List 请求本来就有 `created_after` / `created_before`（例如 `sales.proto:156-157`、`customer.proto:125-126`）。

**冻结钩子**：

```go
type FreezeJob struct{ Table, Partition string; From, To time.Time; Rows func(yield func([]byte) bool) error }
type Receipt struct{ URL string; Rows int64; SHA256 string }
type Sink interface{ Freeze(ctx context.Context, j FreezeJob) (Receipt, error) }
```

SDK 第一版只定义接口，并给一个 `s3sink.New(cfg)`（读 `S3_URL`，输出 NDJSON.gz 加一份清单文件）。不提供在线读取冻结数据；把冻结数据恢复回库里，是一个运维命令（拍板点 4）。

### 3.5 SDK API（议题二）

**Go**（`github.com/brickKit/be-sdk-go/lifecycle`）

```go
func Load(fsys fs.FS, cfg besdk.Config) (*Plan, error)                       // 读 lifecycle.yaml + DATA_LIFECYCLE 覆盖 + 校验
func (p *Plan) EnsureAhead(ctx context.Context, s *besdk.Store, now time.Time) (Report, error)
func (p *Plan) Run(ctx context.Context, s *besdk.Store, opts ...RunOption) error // 阻塞到 ctx 取消；单轮失败只记日志
func (p *Plan) Window(table string, q besdk.Query) (besdk.Query, error)       // 取代 besdk.ListWindow
func (p *Plan) OnlineFrom(ctx context.Context, s *besdk.Store, table string) (time.Time, error)
func WithSink(Sink) RunOption
func WithClock(func() time.Time) RunOption
func WithInterval(time.Duration) RunOption
var ErrRangeNotOnline = errors.New("请求的时间范围早于在线数据下界")
```

组件的 Start 从今天的 3–4 个 goroutine（pump + 周分区 + 月分区 + 消费）收敛成：

```go
plan, _ := lifecycle.Load(migrations.FS, rt.Config)
go besdk.StartOutboxPump(ctx, store, rt.NATS, rt.Logger)
go plan.Run(ctx, store, lifecycle.WithSink(sink))
```

**Python**（`besdk.lifecycle`）：`load(migrations_dir: Path, cfg) -> Plan`；`await plan.ensure_ahead(store, now)`；`await plan.run(store, sink=None)`；`plan.window(table, q) -> Query`；`class RangeNotOnline(Exception)`；`class Sink(Protocol)`。同时补上 `Query` 和 `list_window` 的实现（今天是桩）。

**TS**：没有库，不涉及。bff 把下游的 `RANGE_NOT_ONLINE` 映射成 GraphQL `BAD_USER_INPUT`，`extensions.onlineFrom` 带上在线下界（拍板点 3 的 UX 依赖它）。

### 3.6 各表的默认策略（组件声明的初稿，交各组件 AGENTS 确认）

| 组件 | 表 | 分区粒度 | 提前量 | 列表窗口 | 在线保留期 | 到期处理 | 守卫 / 下限 |
|---|---|---|---|---|---|---|---|
| 全部 | `event_outbox` | 周 | 4 | — | 14 天 | drop | 全部 PUBLISHED |
| 9 个 | `event_inbox` | 周 | 4 | — | 30 天 | drop | 先有水位表 |
| 7 个 | `command_idempotency` | 不分区 | — | — | TTL 7 天 | 按行删 | TTL 要大于客户端最长重试时长 |
| erp/sales | `sales_orders` / `_items` | 月 | 3 | 90 天 | 永久 | keep（可配成 freeze） | — |
| erp/inventory | `inventory_movements` | 月 | 3 | 90 天 | 永久 | keep | 余额靠它对账，不能删 |
| erp/finance | `finance_journal_entry_lines` | LIST（会计期间） | 由开账决定（§4.4） | — | 永久 | keep | **法定**：会计凭证和账簿保存 30 年（《会计档案管理办法》），`min: 30y` |
| infra/authz | `role_changes` | 月 | 3 | — | 3 年 | keep | 审计用途；下限待定 |
| infra/iam-casdoor | `webhook_deliveries` | 月 | 3 | — | 90 天 | drop | `status <> 'RECEIVED'` |
| infra/notification | `notification_records` | 月 | 3 | 90 天 | 1 年 | drop | 未结束的三种状态 |
| infra/print | `print_jobs` | 月 | 3 | 90 天 | 180 天 | drop | 终态写入，没有守卫 |
| integration/im-dingtalk | `delivery_attempts` | 月 | 3 | — | 180 天 | drop | — |
| mdm/customer、mdm/product | `customers` / `products` | 不分区 | — | **待定**（拍板点 3） | 永久 | keep | 主数据 |

### 3.7 先写的红测试（议题二）

- **be-sdk-go lifecycle**（真 PG，用 besdktest 建随机身份）：
  - `TestRun_两个副本并发_同一步只有一个执行`
  - `TestRun_外壳两个成员同时跑_互不阻塞`
  - `TestExpire_outbox分区里有PENDING行不删并导出blocked指标`
  - `TestExpire_业务表then_keep_到期也不动`
  - `TestExpire_freeze没配存储端_分区保留并WARN`
  - `TestExpire_拿不到锁超时_下一轮重试不报ERROR`
  - `TestFreeze_中途崩溃重启后从EXPORTED接着做`
  - `TestSweep_command_idempotency超TTL分批删且不影响新键`
  - `TestLoad_覆盖值低于min报错点名`
  - `TestLoad_未知表报错`
  - `TestLoad_业务表设drop但没写allow_drop报错`
  - `TestDryRun_只记日志不改库`
  - `TestWindow_显式更早范围能读到在线老分区`
  - `TestWindow_早于在线下界返回ErrRangeNotOnline`
- **be-sdk-go events**：
  - `TestConsume_inbox旧分区删掉后_旧版本事件仍被水位拦下`（在 v0.5.0 上会再应用一次，所以是红的）
  - `TestConsume_水位表回填后行为与改造前一致`
  - `BenchmarkConsume_inbox十万行`：基线与改造后对比。
- **be-sdk-python**：对应用例各写一份；另加 `test_list_window_默认90天_夹紧页大小`（今天是 NotImplementedError）、`test_batch_get_routed`（同上）。
- **每个组件**：`TestLifecycleYAML_声明的表都存在且分区键正确`，可以由 SDK 提供一个通用断言 `besdktest.AssertLifecycle(t, store, plan)`。

## 4. 议题三：分区窗口

### 4.1 现状：全部分区表

迁移里写死的初始分区，以及两个库里当前的最后一个分区上界（`pg_inherits` 加 `pg_get_expr` 的只读查询，2026-10-02）：

| 组件 | 表（分区键） | 迁移里写死的范围 | 运行期维护（提前量） | brickkit_test_db 上界 | brickkit_db 上界 |
|---|---|---|---|---|---|
| mdm/customer | outbox / inbox（created_at） | 2026-08-31 … **09-28**（`002`） | `partition/partition.go`（4 周） | 11-02 | 11-02 |
| mdm/product | outbox / inbox | 09-07 … 10-05 | `partition.go`（4 周） | 11-02 | 11-02 |
| erp/inventory | `inventory_movements`（created_at） | 09-01 … 12-01（`001:87-92`） | `monthly.go`（3 月） | 2027-02-01 | 2027-02-01 |
| | outbox / inbox | 09-07 … **10-05** | `partition.go`（4 周） | **10-05** | 11-02 |
| erp/finance | `finance_journal_entry_lines`（LIST 期间） | FY2026（`001:154-165`）+ FY2027（`008`） | **无**（靠开账迁移） | 2027-12 | 2027-12 |
| | outbox / inbox | 09-07 … **10-05** | `partition.go`（4 周） | **10-05** | 11-02 |
| erp/sales | `sales_orders` / `_items` | 09-01 … 12-01（`001:51-53,91-93`） | `monthly.go`（3 月）；`005` 按迁移当天补窗口 | 2027-02-01 | 2027-02-01 |
| | outbox / inbox | 09-07 … 10-05；`005` 补到当周起 5 周 | `partition.go` | 11-02 | 11-02 |
| crm/opportunity | outbox / inbox | 09-07 … 10-05（`002:30-37,58-65`） | `partition.go`（4 周） | 11-02 | 11-02 |
| infra/authz | `role_changes`（changed_at） | 09-01 … 2027-01-01（`002:63-70`） | `partition.go`（3 月） | 2027-01-01 | 2027-02-01 |
| | outbox | 09-07 … **10-05** | `partition.go`（4 周） | **10-05** | 11-02 |
| infra/iam-casdoor | `webhook_deliveries`（received_at） | 09-01 … 2027-01-01（`001`） | `partition.go`（3 月） | 2027-02-01 | 2027-02-01 |
| | outbox / inbox | 09-07 … 10-05 | `partition.go`（4 周） | 11-02 | 11-02 |
| infra/workflow | outbox | 09-07 … 10-05 | `partition.go`（4 周） | 11-02 | 11-02 |
| infra/notification | `notification_records`（created_at） | 09-01 … 12-01（`001`） | `monthly.go`（3 月） | **12-01** | 2027-02-01 |
| | outbox / inbox | 09-07 … **10-05** | `partition.go`（4 周） | **10-05** | 11-02 |
| infra/print（Python） | `print_jobs`（created_at） | 09-01 … 12-01（`001_create_print.sql`） | `partition.py` `start_monthly`（3 月） | 2027-02-01 | 2027-02-01 |
| | outbox | 09-07 … 10-05（`002_create_outbox.sql`） | `start_weekly`（4 周） | 11-02 | 11-02 |
| integration/im-dingtalk | `delivery_attempts`（attempted_at） | 09-01 … **11-01**（`001`） | `monthly.go`（3 月） | 2027-02-01 | 2027-02-01 |
| | outbox / inbox | 09-07 … 10-05 | `partition.go`（4 周） | 11-02 | 11-02 |

合计 12 个组件（bff 和前端没有库），29 张分区父表。**每一张 RANGE 分区表的初始分区都是写死的日期**；只有 erp/sales 的 `005_ensure_current_partitions` 在迁移时按当天日期补齐（`005:13-42`）。

**结论**：

1. **运行中的组件不会断档**：每个组件的后台任务启动时立刻建一轮，之后每 24 小时一次，提前 4 周或 3 个月（例如 `erp/sales/backend/internal/partition/partition.go:20-23,30-33`）。演示库因此一直延伸到 11-02 以后。
2. **会断档的是"只跑了迁移、还没跑 Start"的库**，以及首轮维护失败的部署：
   - 测试库：四个 schema 停在 10-05，另有 notification 的 `notification_records` 停在 12-01；
   - 任何一台新机器，或者一次全新安装：customer 今天就写不进去，其余组件从 10-05 起写不进去；
   - 部署时首轮维护失败（例如角色不是表的属主），之后要等 24 小时才重试。
3. **12 份几乎相同的维护代码**，各自都有三个问题：
   - **没有任何锁**：两个副本同时 `to_regclass` → `CREATE`，一个会报 already exists。整个事务回滚，这一轮一个分区都没建成，24 小时后才重试（例如 sales `partition.go:49-63`、`:76-95`）；
   - **按名字判断分区是否存在**：如果某个迁移的命名格式和运行期代码不一样（注释里说踩过，见 sales `monthly.go:3-4`），就会撞上"分区范围不能重叠"；
   - 注释里写着"过期分区整块删掉"（sales `partition.go:1-3`），**实际没有实现**。
4. 没有 DEFAULT 分区。这是对的：有了 DEFAULT 分区以后，每建一个新分区都要扫描 DEFAULT 分区；一旦 DEFAULT 里有落在新分区范围内的行，建分区就会失败；而且会让 DETACH CONCURRENTLY 不可用。

### 4.2 可选方案

| | A. 每个组件都补一个"005"迁移 | B. 加 DEFAULT 分区兜底 | **C. 由 SDK 建分区（推荐）** |
|---|---|---|---|
| 做法 | 照 sales 005 的写法，迁移执行时按 `now()` 建当前窗口 | 每张表加一个 DEFAULT 分区 | `lifecycle.yaml` 声明粒度和提前量；`migrate.Main` 在 up 之后建当前窗口；`Plan.Run` 运行期续建 |
| 新迁移里的日期字面量 | 没有，但每个组件都要写一段 PL/pgSQL | — | 没有，组件一行 SQL 都不用写 |
| 重复代码 | 12 个迁移 + 12 份维护代码 | 不减少 | **0** |
| 风险 | 迁移写法和运行期代码的命名、窗口要人工保持一致 | 见 §4.1 第 4 点 | SDK 只有一份实现，靠测试覆盖 |
| 发版 | 12 个组件都要发 | 同左 | 12 个组件都要发（反正要跟议题一一起发） |

### 4.3 推荐：C

- **EnsureAhead 的规则**：
  - 边界一律锚定 UTC：周从周一 00:00 开始，月从 1 日 00:00 开始。分区名用 `<表>_YYYY_MM_DD`（与现有命名一致，可以直接接管已有分区）。
  - 判断分区是否存在，**看边界不看名字**：从 `pg_partition_tree` / `pg_inherits` 读出现有分区的边界；目标区间已经被覆盖就跳过；部分重叠就跳过并 WARN，不去建。
  - `follows` 声明的子表和主表用同一组边界，在同一个事务里一起建。
  - 整个过程在生命周期锁下进行，并设 `lock_timeout`。
- **迁移时建窗口**：`migrate.Main` 结束前，以迁移的登录角色，用 `now()` 建当前窗口。所以无论哪天全新安装，迁移一跑完就能写入（与 sales 005 的效果相同，但不需要每个组件都写一份）。
- **迁移文件**：新迁移只写 `CREATE TABLE … PARTITION BY RANGE (…)`，不建任何子分区。门禁按 §2.6 卡住新文件里的日期字面量。已发布的 `001` / `002` 里写死的分区**保持不动**：删掉它们不是零效果的修改（全新安装会少几个 2026-09 的分区）。留着也无害，SDK 判断看边界，会把它们当成已有分区接管。
- **组件删除** `backend/internal/partition/`（11 个 Go 组件）和 `infra_print/partition.py`，Start 里改成 `plan.Run(...)`。erp/sales 的 `005` 保留，它已经发布过。

### 4.4 finance 的会计期间分区（单列）

- **现状**：`finance_journal_entry_lines` 按 `accounting_period` 做 LIST 分区（`001:146`）。FY2026 的 12 个分区写在 `001:154-165`，FY2027 的期间和分区写在 `008_open_fiscal_year_2027.up.sql`（注释写明"必须在 2027-01-01 之前上线"）。运行期没有任何维护。所以**每年必须发一次版，才能开新的会计年度**；FY2028 要在 2027 年内再写一份 009。
- **方案**：
  - **(a)** 保持现状，每年发一份开账迁移。缺点：开账这种业务动作要靠发版完成；漏发一次，过年那天就无法过账。
  - **(b)（推荐）** 新增一个"开会计年度"命令（REST 和 gRPC 各一个，配权限键 `erp.finance.fiscal_year.open`）。它在一个事务里建会计年度、12 个期间、12 个 LIST 分区。SDK 提供 `lifecycle.EnsureListPartition(tx, table, value)`，所以组件不写 DDL。可选再加一个后台提醒：下一年度还没开，而且离年底不到 60 天时，开一条 workflow 待办。
  - **(c)** 改成 RANGE 按过账日期分区。这是数据迁移，代价大，不推荐。
- (b) 是新功能（契约只增不改、新增一个权限键），要走 finance 自己的七步流程。是否放进这一轮由用户决定（拍板点 7）。

### 4.5 先写的红测试（议题三）

- **be-sdk-go**：
  - `TestMigrateMain_迁移后当天就能写入_任意日期`：用 `besdktest.WithClock(2030-01-15)` 和 `2026-10-05` 两个日期，迁移后立即 INSERT 一行 `created_at = <那天>`。
  - `TestEnsureAhead_两个副本并发不报already_exists`
  - `TestEnsureAhead_已有异名同界分区_接管不重建`
  - `TestEnsureAhead_部分重叠_跳过并WARN`
  - `TestEnsureAhead_follows子表与主表同边界同事务`
  - `TestEnsureAhead_锁超时下一轮重试`
  - `TestEnsureListPartition_幂等`
- **每个组件**：`TestMigrate_全新库迁移后outbox当天可写`（用 besdktest）。**在现有代码上，mdm/customer 今天就是红的；其余组件从 2026-10-05 起变红。**
- **be-acceptance**：§2.6 里关于日期字面量的那几条。
- **finance（如果选 (b)）**：
  - `TestOpenFiscalYear_建年度期间与12个分区_同一事务`
  - `TestOpenFiscalYear_重复调用幂等`
  - `TestPostEntry_未开年度的日期_FailedPrecondition`

## 5. 议题四：BatchGet 上限

### 5.1 现状与证据

**按 id 列表批量取的 rpc（12 个组件、14 个 rpc）**

| 组件 | rpc | 请求字段 | 实现 | 是否有上限 |
|---|---|---|---|---|
| mdm/customer | `BatchGet`、`GetSummary` | `ids`（`customer.proto:133`） | `grpc/grpc.go:136`，`repo/read.go:19-50` → `BatchGetRouted` | 无 |
| mdm/product | `BatchGet`、`GetSummary` | `ids`（`product.proto:126`） | `grpc/grpc.go:144`，`repo/read.go:19` | 无 |
| erp/sales | `BatchGetOrder` | `ids`（`sales.proto:166`） | `repo/order.go:123-136`：**每个 id 调一次 `GetOrder`，各开一个事务**（N+1） | 无 |
| crm/opportunity | `BatchGetOpportunities` | `ids`（`opportunity.proto:148`） | `grpc/grpc.go:193`，`repo/opportunity.go:140` | 无 |
| erp/inventory | `BatchGetBalance` | `keys`（`inventory.proto:175-177`） | `grpc/grpc.go:127`，`repo/balance.go:81` | 无 |
| erp/finance | `BatchGetCreditExposure` | `customer_ids`（`finance.proto:95`） | `grpc/grpc.go:119`，`repo/credit.go:43` | 无 |
| infra/authz | `BatchGetRoles` | `codes`（`authz.proto:34-35`） | `grpc/grpc.go:34` | 无 |
| infra/iam-casdoor | `BatchGetUsers` | `subs`（`iam.proto:41-42`） | `grpc/grpc.go:43` | 无 |
| infra/workflow | `BatchGetTasks` | `task_ids`（`workflow.proto:142-143`） | `grpc/grpc.go:158`，`repo/tasks.go:183` | 无 |
| infra/notification | `BatchGetRecords` | `record_ids`（`notification.proto:67-68`） | `grpc/grpc.go:147`，`repo/records.go:158` | 无 |
| infra/print | `BatchGetTemplates` | `template_ids`（`print.proto:65-66`） | `grpc/server.py:69`，`repo/templates.py:83` | 无 |
| integration/im-dingtalk | `BatchGetDeliveryStatus` | `record_ids`（`im.proto:49-50`） | `grpc/grpc.go:45`，`repo/deliveries.go:70` | 无 |

同一类问题、但不在本议题范围内的：命令请求里的 `repeated` 字段，`CreateOrderRequest.items`、`CreateOpportunityRequest.items`、`ReserveRequest.items`、`PostManualEntryRequest.lines`、`CalculatePriceDryRunRequest.items`，也都没有上限（只检查了"不能为空"，例如 sales `service.go:64`）。

**SDK**

- `be-sdk-go/archive.go:100-107`：`IN ($1..$N)`。PG 一条语句最多 65535 个绑定参数，超过就是协议错误，返回 500。
- `be-sdk-go/standalone.go:215`：gRPC 服务端只挂了 panic 恢复拦截器，没有地方统一做请求校验。外壳复用的是同一个拦截器（`shell.go:88`）。
- `be-sdk-python/besdk/standalone.py:198`：`grpc_aio.server()` 没有任何拦截器。
- `be-sdk-go/gin.go:132-136`：HTTP 错误体只有 `{"error": "<消息>"}`，没有机器可读的错误码。
- `be-sdk-ts/src/dataloader.ts:34-38`：`new DataLoader(batchGet)` 没有设置 `maxBatchSize`。

**调用方**

- bff `src/limits.ts:16-25`：`MAX_BATCH_IDS = 100`，超出时抛 `BAD_USER_INPUT`。但它只检查**单个字段参数**的长度；同一请求里的 DataLoader（`context.ts:34-35`）会把多个字段、多个嵌套 resolver 的 id 合并成一次 gRPC 调用，所以下游实际收到的一批可能超过 100。
- sales `tcc/tcc.go:115`、`tcc/opportunity_won.go:111`，opportunity `client/client.go:59`：把一张订单或商机的所有行的产品 id 一次传过去。行数没有上限，所以上游一旦加了上限，这里必须分片。

### 5.2 可选方案

| | A. 各 handler 手写检查 | B. SDK 拦截器 + 代码注册 | **C. 契约字段选项 + SDK 拦截器（推荐）** |
|---|---|---|---|
| 上限写在哪 | 12 个 handler | 模块里 `besdk.BatchLimit("/pkg.Svc/BatchGet", "ids", 500)` | proto：`repeated string ids = 1 [(besdk.v1.max_items) = 500];` |
| 调用方知不知道上限 | 不知道 | 不知道 | **知道**：契约里写着，生成代码里也能读到 |
| 门禁 | 难 | 能查"是否注册了" | 能查"每个 `BatchGet*` 请求的 `repeated` 字段都带了选项" |
| 漏写的后果 | 不限 | 不限 | 拦截器对 `BatchGet*` 套默认值 500，同时门禁报错 |
| 代价 | 小 | 小 | 每个组件的 `contracts/` 多引一个 `besdk/v1/limits.proto`（放在 be-sdk-go，Go 生成代码也在那里；按 0101，be-sdk-* 本来就是允许跨边界的） |

### 5.3 推荐：C，加统一的错误契约

- **上限的取值**：默认 **500**，与 `ListWindow` 的 `maxLimit=500` 对齐，含义是"一批最多一页"。sales 的 `BatchGetOrder` 是 N+1，建议设成 100，或者先把它改成一条 `IN` 查询（拍板点 8）。bff 入口的 100 保持不变，作为更严的边缘限制；同时把 DataLoader 的 `maxBatchSize` 设成下游的上限，让 DataLoader 自己分片。
- **计数方式**：按原始长度计数，不先去重。这样能直接挡住超大的请求体；去重是实现内部的事。
- **错误契约**：
  - **gRPC**：`INVALID_ARGUMENT`（参照 Google AIP-193 对"请求项过多"的分类，不用 `RESOURCE_EXHAUSTED`，那个用于配额和限流）。details 里放 `google.rpc.ErrorInfo{reason:"BATCH_TOO_LARGE", domain:"besdk", metadata:{field, max, got}}` 和 `google.rpc.BadRequest{field_violations:[{field, description}]}`。
  - **HTTP**：400，错误体**只增加字段**：`{"error":"…","code":"BATCH_TOO_LARGE","details":{"field","max","got"}}`。`code` 字段对所有带 ErrorInfo 的错误都适用，是整个 SDK 错误模型的第一步，统一模型见 `sdk-redesign.md`。
  - **GraphQL（bff）**：`BAD_USER_INPUT`，`extensions:{code:"BATCH_TOO_LARGE", field, max, got}`。原有的 `maxIds` 保留，避免破坏前端。
- **调用方**：一律用 `besdk.BatchGetAll` 自动按上限分片，并发度 1，按传入顺序拼回结果，`missing` 合并。门禁（可选）：组件代码里直接调用生成的 `.BatchGet(` 客户端方法时给警告，提示改用 `BatchGetAll`。
- **契约兼容**：给已发布的 rpc 加上限，是对可接受输入的**收窄**。0302 只禁止改字段，没有说上限；但"一个字段的含义不能变"可以解读成同样适用于这里。建议写一条新决策 `0304 Batch inputs are capped; the cap is part of the contract`：上限只能放宽、不能收紧；首次加上限时，取值不得低于所有已知调用方的实际用量（目前已知调用方一次只传一张单据的行数或一个页面的 id）。

### 5.4 SDK API（议题四）

**Go**

```go
// proto：be-sdk-go/proto/besdk/v1/limits.proto
//   extend google.protobuf.FieldOptions { int32 max_items = 51001; }   // 51001 在 50000–99999 的内部使用区间
const DefaultBatchMax = 500
func BatchLimitInterceptor() grpc.UnaryServerInterceptor // standalone 与外壳的 grpc.NewServer 自动挂上，组件不用管
func BatchTooLarge(field string, got, max int) error     // 手写入口（REST）时用；返回带 ErrorInfo 的 status
func IsBatchTooLarge(err error) (field string, max, got int, ok bool)
func Chunk[T any](items []T, max int) [][]T
func BatchGetAll[K comparable, V any](ctx context.Context, keys []K, max int,
	call func(context.Context, []K) (found []V, missing []K, err error)) ([]V, []K, error)
```

**Python**

```python
DEFAULT_BATCH_MAX = 500
class BatchLimitInterceptor(grpc.aio.ServerInterceptor): ...   # run_standalone / 外壳自动挂
def batch_too_large(field: str, got: int, max: int) -> grpc.aio.AbortError: ...
def chunk(items: Sequence[T], max: int) -> list[list[T]]: ...
async def batch_get_all(keys, max: int, call) -> tuple[list, list]: ...
```

**TS**

```ts
export const DEFAULT_BATCH_MAX = 500;
export function createBatchGetLoader<K, V>(
  batchGet: (ids: readonly K[]) => Promise<ArrayLike<V | Error>>,
  opts?: { maxBatchSize?: number },          // 默认 DEFAULT_BATCH_MAX；bff 传下游上限
): DataLoader<K, V>;
export function assertBatchWithin(field: string, ids: readonly unknown[], max: number): void; // GraphQLError BAD_USER_INPUT
export function batchTooLargeFromGrpc(err: unknown): { field: string; max: number; got: number } | null;
export function chunk<T>(items: readonly T[], max: number): T[][];
```

### 5.5 先写的红测试（议题四）

- **be-sdk-go**：
  - `TestBatchLimitInterceptor_超限返回InvalidArgument且带ErrorInfo与BadRequest`
  - `…_等于上限放行`
  - `…_无选项的BatchGet套默认500`
  - `…_非BatchGet的rpc不受影响`
  - `TestBatchGetAll_按上限分片_保序_missing合并`
  - `TestGinErrorMapping_带ErrorInfo时错误体多出code与details`
  - `TestBatchGetRouted_7万个id不触发绑定参数上限`：在入口处就被上限挡住；即使绕过上限直接调用，内部也会分片。
- **be-sdk-python**：`test_interceptor_超限_abort_invalid_argument`、`test_batch_get_all`。
- **be-sdk-ts**：`createBatchGetLoader 默认 maxBatchSize 会分片`、`batchTooLargeFromGrpc 解析 ErrorInfo`。
- **be-acceptance**：`TestBatchCapScan_BatchGet请求的repeated字段缺max_items报错`。
- **每个组件**：`TestBatchGet_超过上限返回BATCH_TOO_LARGE`，14 个 rpc 每个一条，可以由 SDK 提供表驱动的通用断言。
- **sales / opportunity**：`TestCreateOrder_150行_产品校验分片调用每次不超过上限`（假的 product 服务里断言每次调用的长度）。
- **bff**：`下游返回 BATCH_TOO_LARGE 映射成 BAD_USER_INPUT`、`两个字段各 80 个 id 合并后下游每批不超过 100`。

## 6. 落地顺序与版本

按 memory 里"每个任务一个 checkpoint"的原则，下面每一步做完都停下来汇报。

0. **止血（现在，不发版）**：赶在 2026-10-05 之前，把测试库四个 schema 的 outbox/inbox 窗口补出来。可选做法：
   - (i) 跑一遍 finance、inventory 自带的分区测试（它们会对真实 schema 调 Start）。authz 和 notification 没有这类测试，只能用 (ii)；
   - (ii) 由控制者手工执行一段一次性 SQL：按 `_YYYY_MM_DD` 命名、以各组件角色建当周起 5 周的分区；
   - (iii) 在 `test-db-init.sh` 里加一步"按现有命名补窗口"的过渡脚本，SDK 方案落地后删掉。

   建议 (ii) 加 (iii)。同时提醒：在新机器上，mdm/customer 的连库测试今天就会失败。
1. **SDK v0.6.0 三条线并行**（Go / Python / TS，各自在自己的仓库提交；打 tag 留给控制者）。先写 §2.9、§3.7、§4.5、§5.5 里的 SDK 红测试，再实现：
   - Go / Python：`Store`、`besdktest`、`pgdialect`、平台迁移、`lifecycle`、批量上限、错误码字段；
   - TS：`createBatchGetLoader` 的 `maxBatchSize`、`assertBatchWithin`、`batchTooLargeFromGrpc`。

   开工前先单独验证两个新机制的最小复现：iofs 和 yoyo 是否忽略 `lifecycle.yaml`；golang-migrate 能否在同一个 schema 里用两套状态表。
2. **be-acceptance 增加三个门禁**：`migration-identity-scan`、`identity-literal-scan`、`batch-cap-scan`。先以只警告的方式运行，在 12 个组件上把命中清单完整列出来，与 §2.1 和 §5.1 的表逐项核对；全部组件改完后再切成报错。
3. **外壳 T21–T24 照原计划进行**：继续用今天的 INHERIT 授权和现有成员版本。外壳的 `go.mod` 只是钉住版本，SDK 升级以后重新钉一次即可。
4. **12 个有库组件各发一个版本**（建议 `2.1.0`），用 version-bump-ship 一批推进，按依赖顺序：先 mdm 两个，再 inventory、finance、authz、iam、workflow、notification、im-dingtalk、print，最后 sales、opportunity。每个组件这一版合并完成：
   - 议题一：Store、删 `OWNER TO`、删默认 schema、测试迁到 besdktest、改 BRICKKIT 文档；
   - 议题二、三：写 `lifecycle.yaml`、删 `partition/`、Start 改用 `plan.Run`；
   - 议题四：`limits.proto` 选项，调用方改用 `BatchGetAll`。

   每个组件完成后，补一次 R63 第 2 点的属主对比，结果写进测试记录。
5. **bff 2.0.1**：升 SDK、设置 `maxBatchSize`、映射 `BATCH_TOO_LARGE` 和 `RANGE_NOT_ONLINE`。
6. **be-ops 小版本**：
   - 授权改成 `WITH INHERIT FALSE`；
   - 不再生成 `<schema>_archive`（已经存在的空 schema 留着无害，可以另外清理）；
   - 外壳也改用 NOINHERIT 登录角色，然后重新组装外壳，跑一遍 T25 的真机验证。证明点：外壳角色是 NOINHERIT 时，四类后台任务（pump、消费、生命周期、业务事务）全部正常。
7. **项目正式文档（中英两份）**：
   - `02-backend.md` Database 一节：改写成 Store、生命周期、迁移不出现身份和日期、BatchGet 上限；
   - `04-configuration.md` Database roles 一节；
   - `07-registries.md`：去掉 `_archive` 那一行；
   - 新增决策 0304（批量上限）；0102 的"何时重议"补上方案 C 的触发条件。

## 7. 需要拍板的点

1. **身份方案 B 加 `besdktest`**：同意吗？`rt.DB` 在 v0.7 不再对模块可见，同意吗？
2. **生命周期模型**："在线即挂载"（B），取消 `<schema>_archive` 和冷热路由，同意吗？这会改写 `02-backend.md:134` 的现有约定，并让 `BatchGetRouted` 退化成直接查主表。
3. **主数据的默认 90 天窗口**：customer 和 product 的 List 默认窗口要不要去掉（`list_window: none`）？`customer.proto:120` 的注释把这个行为写进了已发布的契约。去掉它会让结果变多，算不算"含义改变"？建议去掉，并当作 bug 修复处理：主数据列表看不到 90 天前建档的客户，这不可能是想要的行为。
4. **冻结存储端**：第一版只定义接口、给一个 NDJSON.gz 的 S3 实现，同意吗？冻结的数据只允许经运维命令恢复、不支持在线查询，同意吗？各业务表的在线保留期（§3.6 的初稿）谁来定：组件作者，还是用户逐项拍？
5. **数据库目标范围**：官方承诺只到"PG ≥ 14 及 PG 兼容发行版"，同意吗？要不要现在就把人大金仓、瀚高列为待实测目标（信创场景）？
6. **队列认领要不要也收进 SDK**：iam 的 webhook 队列、workflow 的超期扫描是两份手写的 SKIP LOCKED。是现在就收成 `besdk.ClaimBatch`，还是等第三个使用者出现再收？
7. **finance 开账**：这一轮就把"开会计年度"命令（§4.4 方案 (b)）一起做掉，还是先维持每年发一份迁移？如果维持，FY2028 的 009 最晚要在 2027 年内发布。
8. **BatchGet 上限的取值**：默认 500，sales 的 `BatchGetOrder` 设 100（或者先消除它的 N+1），同意吗？要不要写决策 0304？
9. **组件版本号**：这一轮各组件发 `2.1.0` 还是 `2.0.x`？项目目前没有 minor / patch 的规则；本文建议，凡是"有新行为（会删数据）或契约收窄"的发版都用 minor。
10. **止血方式**：§6 第 0 步用 (ii) 加 (iii)，同意吗？由谁在 10-05 之前执行？
