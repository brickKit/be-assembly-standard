# 数据与平台基础：数据库、标识、时间与金额、多租户、迁移、搜索、对象存储、可观测性、配置与密钥、IAM、数据层 i18n——基础选型审查

> 开发文档，只给本项目自己用；正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件文档）不得链接本文件。
> 写于 2026-10-02（06b 设计轮，外壳 T21–T24 之前）。只读调研，未改任何代码、未提交。行号以写作时各仓库工作区为准（be-sdk-* v0.5.0，组件 2.0.x）。"库里实测"指对本机 `be-postgres`（PostgreSQL 16.15，`timezone=UTC`）的只读查询。
> 判据：用户 2026-10-02 定的门槛——**基础选型一次设计到位，业务逻辑以后可以重写**；完整、面向未来、不弱于主流平台；不同场景适合不同设计的，做成可替换（端口与适配器：先定契约，再配一致性测试；替换只需简单改动，不重写逻辑）。
> 与已有分析的分工：库身份 / `Store` / 冷热生命周期 / 分区窗口 / BatchGet 上限见 `data-layer.md`；事件信封 / 幂等 / JetStream 见 `events-consistency.md`；权限、claims、authz 槽位族见 `identity-permissions.md` 与 `authz-architecture.md`。本文**只在它们之上补新东西**，引用处写"见 X §n"，不复述。
> brickKit 行为只查了 `brickkit docs`（本机装的是 **v1.1.0**，`common.md` 还写着 v1.0.0），没有读 brickKit 源码。

## 0. 结论（一页）

**最要紧的缺口（按严重度）**

1. **财务过账的日期是错的，而且错两次（真 bug，已实测）。** `erp/finance` 自动凭证与人工凭证的业务日期都是 `time.Now().UTC()`（`repo/autoentry.go:54`、`:185`，`repo/manual.go:52`、`:122`），按 `end_date >= $2` 找期间（`repo/period.go:139-146`）。`end_date` 是 DATE，和 timestamptz 比较时被当成当天 00:00（库里实测 `'2026-09-30'::date >= '2026-09-30 10:00+00'::timestamptz` 为 **false**）。结果：① **每月最后一天 00:00 UTC 之后的凭证全部记进下个月**；② 用 UTC 而不是法人时区，北京时间每天 0–8 点的单据记到前一天；③ 业务日期取"消费事件的时刻"而不是单据日期，事件积压或 DLQ 重放跨月时记错期间。同类问题：sales 价格表按 `CURRENT_DATE`（会话时区 UTC）判生效（`repo/pricing.go:48-49`），10-01 生效的价格北京时间 8 点才生效。
2. **没有任何跨组件链路追踪。** 三门 SDK 都没有设置 propagator（全仓库找不到 `SetTextMapPropagator` / `otelgrpc` / `otelhttp`），`tracingMiddleware` 每个请求都开一个新的根 span（`be-sdk-go/gin.go:99`），gRPC 没有任何 span；外壳里所有成员的 trace 都挂在外壳的 `service.name` 下（`shell/run.go:101` → `otel.go:23`）。`events-consistency.md` 设计的 `traceparent` 信封字段没有可依赖的底座。
3. **IAM 槽位族的契约里写着厂商名，换实现要改前端。** 换 token 的请求字段叫 `casdoor_id_token`（`iam.openapi.yaml:38-40`），前端写死了 Casdoor 的私有路径 `/login/oauth/authorize`、`/api/login/oauth/access_token`（`frontend/standard/apps/pc/src/auth/oidc.ts:48,85`），没有走 OIDC discovery。应用 token 的 `sub` 直接就是 Casdoor 的 `sub`，所以换 IdP 等于换掉每张表里 `owner_id` 的取值。签出的 access token **没有 `iss`、`aud`、`jti`**（`tokens/tokens.go:65-66`），SDK 验签也不查 `iss` / `aud`（`be-sdk-go/jwt.go:53`）。
4. **连接池没有上限。** Go 的 `sql.Open` 之后从不调用 `SetMaxOpenConns`（`standalone.go:79`、`shell/run.go:113`），即不设上限；Python 用 asyncpg 默认的 10（`standalone.py:103`、`shell_runner.py:126`）。PG 的 `max_connections=300`（`docker-compose.infra.yml:33`），而 registry 里登记了 59 个组件。外壳里所有成员共用一个池，一个成员就能把池占满（没有舱壁隔离）。角色上也没有 `statement_timeout`、`idle_in_transaction_session_timeout`（be-ops `gen.go:152-188` 只建角色、授权）。
5. **标识、金额、租户三项"建表时就定死"的形状还没定。** 主键全是 BIGSERIAL；`order_no = "SO"+id`（`sales repo/write.go:108`）会泄露业务量，也不能按期间或法人编号。金额列一律 `NUMERIC(18,2)`，包括单价和标准成本（`sales 001:70,117`、`product 001:64`）。只有 sales 和 opportunity 有 `currency` 列，汇率完全没有。十进制运算有三份各写各的实现，规则还不一样（sales 用 `decimal/decimal.go`，finance 用 `repo/money.go`，opportunity 用 `repo/decimal.go`）。交易单据（sales、inventory、opportunity）**没有法人列**，finance 收到事件时缺省为 `'default'`（`autoentry.go:49-52`）。
6. **错误体既不可翻译，还泄露内部细节。** `codes.Internal` 直接带 `err.Error()`（`mdm/customer service/status.go:29`、`erp/sales service/status.go:46`），HTTP 错误体只有 `{"error": "<中文消息>"}`（`gin.go:134-137`）。前端拿不到机器可读的码，只能显示中文原文；SQL 错误原文会到达浏览器。
7. **对象存储只有一个地址。** `S3_URL` 是唯一的配置键（`endpoint.go:54`），没有凭据键、bucket 约定和 SDK 客户端，也没有一个组件真的用它。print 把 PDF 字节直接放进 gRPC 响应返回，撞上 gRPC 默认 4 MB 的消息上限就会失败。
8. **其它**：带外镜像全是 `:latest`（`docker-compose.infra.yml:87,114,132,149`，`docker-compose.observability.yml:15,34,57,72,84`），不可复现；Casdoor / Keycloak 用 `postgres` 超级用户连业务库（`:101`、`:161`）；`Config.IntOr` 解析失败时静默回退默认值（`runtime.go:56-75`），`MustString` 在模块里 panic 会带垮整个外壳（`runtime.go:48`）；Go 的 PII 脱敏要业务代码自己调用，Python 是自动的，两门语言不一致（`logging.go:60-77` 对 `besdk/logging.py:3-9`）。

**主要推荐**

| # | 议题 | 推荐 | 可替换？ |
|---|---|---|---|
| 1 | 数据库 | 维持"PG 方言族"（`data-layer.md` §2.7），**补一套数据库一致性套件 `be-acceptance/dbconf`**，用它给目标引擎分级；横向扩展的路线写成 Citus 的 schema 分片（与 0102 天然吻合）。池有上限，外壳里加成员级舱壁；pooler 可选（transaction 模式，迁移直连）；角色级超时由 be-ops 生成 | 端口是"PG 线协议 + 能力清单"，靠一致性套件判定，**不做**多方言抽象 |
| 2 | 标识 | **自有主键一律 UUIDv7**（SDK 生成，`uuid` 类型）；外部引用保持 TEXT；分区表的 `created_at` 从 id 派生，按 id 取单条可以裁剪分区；单据编号由 SDK 的 `numbering` 按法人、期间分配，格式由配置决定 | 编号格式是配置项（0104 已判定不是槽位族） |
| 3 | 时间、金额、单位 | 瞬时用 timestamptz，**业务日期用 DATE**，并按**法人的业务时区**计算；SQL 里禁止 `CURRENT_DATE` / `now()::date`；事件带单据的业务日期。金额 `NUMERIC(19,4)`、单价 `NUMERIC(19,6)`、汇率 `NUMERIC(19,10)`，舍入只在 SDK 的 `money` 包里做，按 ISO 4217 小数位；三门 SDK 共用一组十进制向量 | 舍入、分摊是 SDK 内部策略，不是槽位 |
| 4 | 多租户 | **租户 = 部署**（silo，与 Odoo Online、Dynamics 365、SAP 云版同类），租户内多公司走法人维度：**交易单据现在就加 `legal_entity_id`**；token 带 `tenant_id` + `aud`，SDK 校验 | 形态不做成可切换（切到池化 SaaS 是 3.x 级别的重做，写进"何时重议"） |
| 5 | 迁移 | 保留 golang-migrate / yoyo（0103）；SDK 迁移入口统一设 `lock_timeout` 并重试；**expand/contract 写成规则，并由门禁按 `brickkit.yaml` 里并存的版本把关**；回填走 SDK 的可续跑任务；生产只前滚；Squawk 类 lint 进 `make gates` | — |
| 6 | 搜索 | 组件内的 `q` 收进 SDK 的 `search` 帮手：规范化 `search_text` 列（含拼音和首字母）+ 按能力探测选用 pg_trgm / pg_bigm；**全局搜索**以后做成 `infra/search-*` 槽位族（事件投影 + 按 ACL 过滤） | 组件内：SDK 策略；全局：槽位族 + 一致性测试 |
| 7 | 文件 | `infra/attachment` 管元数据和授权（向父记录的资源契约要授权）；预签名直传，先进隔离区，扫描后才可用；**每个组件一个 bucket、一份凭据**（类比 0102）；SDK 提供 `blob` 端口 | S3 API 就是端口（0106）；扫描器是适配器（ClamAV / 无） |
| 8 | 可观测性 | 三门 SDK 补 W3C propagator 和 gRPC/HTTP/NATS 的注入与提取；**每个成员一个 TracerProvider**（`service.name` = 成员 ID）；外壳的 `/metrics` 汇总各成员 registry 并打上 `component` 标签（解 V-08）；日志级别键 `LOG_LEVEL`，R51 分级收进 SDK；审计走 outbox → `infra/audit` | OTLP 本身就是端口，换后端只改 collector 的 exporter |
| 9 | 配置与密钥 | 维持"只经环境变量注入"；SDK 增加 `Secret` 端口（env / 文件热更新 / OpenBao 适配器），pgx 的 `BeforeConnect` 每次取最新口令，所以轮换不用重启；K8s 优先用 ESO + `existingSecret` | 是：SecretSource 适配器 + 一致性测试 |
| 10 | IAM | 族契约独立出来（`contract-infra-iam`）：OIDC discovery、RFC 8693 形状的换 token、claims 集合、JWKS 轮换、用户生命周期事件、**平台自有 `sub`**（IdP 的 sub 只存在 iam 的链接表里）。**第二实现是 `infra/iam-keycloak`**（registry 已占位）；第三个是通用 `iam-oidc`（SCIM 2.0 入站） | 是：槽位族 + `be-acceptance/iamconf` |
| 11 | 数据层 i18n | 可翻译的主数据加 `*_i18n JSONB`（`name` 保留为默认语言，只增不改）；错误模型按 AIP-193（`reason` + `domain` + `metadata`），前端按 reason 翻译；服务端要出文字的场景（通知、打印）从 IAM 用户档案取 `locale` | — |

**组外壳（T21–T24）之前必须定的**（会改表、改契约或改外壳代码，§13 有完整的表）：租户形态与交易单据的法人列（Q1、Q2）；主键是否换 UUIDv7（Q3）；金额精度与币种列（Q4）；平台 `sub` 与 IdP 解耦（Q7）；错误模型的形状（06c 前端依赖它）；外壳里每成员的 trace、metrics、日志级别与池舱壁（这部分就是外壳代码）；事件里带业务日期，以及 finance 期间 bug 的修复。

## 1. 范围与术语

- **端口 / 适配器 / 一致性套件**：端口是契约（proto、OpenAPI、事件、能力清单），适配器是某个实现，一致性套件是任何实现都必须通过的黑盒测试。本文判断"该不该可替换"的标准沿用 0104：(a) 成熟系统确实有多种合理做法、分别适合不同客户；(b) 没有组件对某个具体实现有依赖边。两条都不满足，就只保留一个实现，放在 SDK 内部。
- **瞬时 / 业务日期**：瞬时是时间轴上的一点（`created_at`、`posted_at`），业务日期是"这张单据属于哪一天"（单据日期、过账日期、到期日、生效日），它只有在指定时区下才有意义。
- **租户 / 法人**：租户是数据彼此完全不可见的客户；法人是同一客户内部的公司，共享主数据，可以有内部往来。
- 本文所说的"前置"，指必须在 T21–T24 之前定下来的事项。

---

## 2. 议题一：数据库选型、schema 隔离与连接池

### 2.1 现状与证据

- 引擎：`postgres:16-alpine`，`max_connections=300`（`infra/docker-compose.infra.yml:26,33`），会话时区为 UTC（库里实测）。
- 隔离：一个库，每个组件一个 schema 加一个角色（0102）；外壳用一个池加 `SET LOCAL ROLE`。`data-layer.md` §2 已经给出 `Store` / NOINHERIT / 能力探测的方案。
- 方言绑定程度：`data-layer.md` §2.7 已统计（机制层收进 SDK 的 `pgdialect`，业务 SQL 留在 repo）。
- 池：Go `sql.Open("pgx", dsn)` 之后不设任何参数（`standalone.go:79`、`shell/run.go:113`），所以 `MaxOpenConns=0`（无上限）、`MaxIdleConns=2`、连接永不过期。Python `asyncpg.create_pool(dsn)`，min 和 max 都是 10（`standalone.py:103`、`shell_runner.py:126`）。
- 角色：be-ops 只做 `CREATE ROLE … LOGIN`、授 USAGE+CREATE、设默认权限（`tools/be-ops/internal/dbscript/gen.go:152-188`），没有 `CONNECTION LIMIT` 和任何会话参数。**跑迁移的角色同时也是运行期角色**，它拥有自己的表，所以运行期就能 `DROP TABLE`。
- 带外容器：Casdoor 和 Keycloak 以 `postgres` 超级用户连 `brickkit_db`（`docker-compose.infra.yml:101,161`）。

### 2.2 缺口与 bug

| # | 缺口 | 后果 |
|---|---|---|
| DB-1 | 池无上限、无舱壁 | 一个成员的慢查询或突发流量会耗尽外壳的池，其余成员一起超时；独立部署时组件越多，越容易突破 `max_connections`，表现为新连接 `FATAL: too many connections`，而且出现在随机的组件上 |
| DB-2 | 没有超时 | 一个忘了提交的事务（`idle in transaction`）会一直持锁，迁移的 `ALTER` 排在它后面，后面所有查询又排在 `ALTER` 后面，整张表不可用 |
| DB-3 | 连接不过期 | 主备切换、DNS 变化、pooler 重启之后，旧连接一直坏着，靠失败来发现 |
| DB-4 | 迁移角色就是运行期角色 | 一次 SQL 注入或 AI 写错的语句就能删表；外壳 NOINHERIT（`data-layer.md` §2.4-7）防不住这一点 |
| DB-5 | 超级用户给了带外容器 | Casdoor 历史上出过 SQL 注入漏洞；它被攻破就能读写全部组件的 schema |
| DB-6 | **待实测**：外壳共享池 × 语句缓存 × search_path | pgx v5 stdlib 默认缓存预备语句。`data-layer.md` 推荐的"表名不带限定、靠 search_path 解析"会让两个成员发出**完全相同的 SQL 文本**（SDK 平台表的认领、去重语句）。在同一条物理连接上，PG 会因 search_path 变化重新解析计划，可如果两个成员的平台表结构不同（SDK 版本不同、列数不同），就会报 `cached plan must not change result type`。只有成员 SDK 版本不一致时才出现，**先写最小复现再定方案**（memory："没验证过的机制先写最小复现"）。规避办法：平台 SQL 永远写明列名、不用 `*`；必要时外壳把执行模式设为 `QueryExecModeCacheDescribe` |

### 2.3 市场方案

| 方案 | 优点 | 缺点 | 对本项目 |
|---|---|---|---|
| **PostgreSQL 14–18**（含托管 RDS / Aurora / Cloud SQL / AlloyDB / Azure Flexible、阿里云 RDS PG、PolarDB-PG） | 本项目机制全部依赖它：事务级 `SET LOCAL ROLE`、声明式分区、`SKIP LOCKED`、事务级 advisory 锁、事务性 DDL、`ON CONFLICT`、NUMERIC；生态最全（CloudNativePG、Patroni、pgBackRest） | 单写节点，扩展靠分区、读副本或分片扩展 | **默认** |
| MySQL 8 / MariaDB / TiDB / OceanBase-MySQL | 国内运维熟悉；TiDB 能横向扩展 | schema 就是 database；没有 `SET LOCAL ROLE`；DDL 不是事务性的；分区表不支持外键；整套身份机制（0102）都要重做 | **不支持**（`data-layer.md` 已判） |
| CockroachDB | 分布式、强一致 | 没有 advisory 锁，只有 SERIALIZABLE，分区语义不同；2024 年起 Core 版退出，改为企业许可（小企业免费） | 不支持 |
| YugabyteDB（YSQL） | PG 兼容度高，Apache-2.0，可多地域 | advisory 锁、部分 DDL、分区的兼容性要逐项验证；资源占用重 | 列为"按需实测" |
| **Citus 12+**（PG 扩展） | **schema 分片**：每个 schema 整体落在一个 worker 上，跨 schema 不 JOIN。这正是 0102 已经强制的约束，所以组件代码零改动 | 需要协调节点；部分扩展和 DDL 有限制 | **横向扩展首选路线**，写进 0102 的"何时重议" |
| 人大金仓 KingbaseES（PG 兼容模式）、瀚高 HighGo | 信创名录；内核源自 PG，兼容度高 | 版本与上游 PG 的对应关系、`NOINHERIT` 授权语法、扩展可用性要实测 | "很可能可用，按一致性套件实测" |
| openGauss / GaussDB / 海量 Vastbase | 信创 | 从 PG 9.2 分叉、差异大（分区语法、角色、部分函数） | "预计要改 SDK 的 `pgdialect`"，不承诺 |
| 连接池：PgBouncer ≥1.21 / PgCat / Supavisor / Odyssey / CNPG Pooler | 减少后端连接、跨进程复用 | transaction 模式下会话状态不保留 | 可选（§2.4） |

### 2.4 推荐设计

1. **"数据库可替换"的精确含义**：在"PG 线协议 + 能力清单"这个端口后面换引擎，判定标准是一致性套件，**不在 SDK 里做多方言抽象**（对 `data-layer.md` §2.7 的细化）。能力清单：事务级 `SET LOCAL ROLE` / `search_path`、PG16 `GRANT … WITH INHERIT FALSE, SET TRUE`、RANGE/LIST 声明式分区与 `pg_partition_tree`、`FOR UPDATE SKIP LOCKED`、`pg_advisory_xact_lock`、事务性 DDL、`CREATE INDEX CONCURRENTLY`、`ON CONFLICT … RETURNING`、`uuid`、`NUMERIC`、`JSONB`（只作不透明存储）、`timestamptz`、错误码 23505 / 40001 / 55P03 / 57014。
2. **`be-acceptance/dbconf` 一致性套件**：三层。① SDK `pgdialect` 的全部机制测试；② 每个能力一条探针 SQL；③ 抽 3 个组件（sales、finance、iam）跑 L4。参数是 `-dsn`，输出"引擎 × 能力"矩阵，写进测试记录。KingbaseES、瀚高、YugabyteDB、Citus 各跑一次，就得到"确定可用 / 降级 / 不可用"的事实依据，D5 拍板时可以凭数据决定。
3. **池的配置**（SDK 统一实现，组件代码不碰）：
   - 独立部署：`PG_POOL_MAX`（默认 10）、`PG_POOL_MIN_IDLE`（默认 2）、`PG_CONN_MAX_LIFETIME`（默认 30m）、`PG_CONN_MAX_IDLE_TIME`（默认 5m）。四个都是可选键，写进各组件的 configSchema。
   - 外壳：外壳自己的 `PG_POOL_MAX` 决定物理池大小（默认取各成员 `PG_POOL_MAX` 之和与 40 中较小的那个）。**每个成员的 `PG_POOL_MAX` 变成它在共享池里的并发上限**：`Store` 内部一个信号量，即舱壁；取不到时等待 `PG_POOL_ACQUIRE_TIMEOUT`（默认 5s），超时返回 `Unavailable`，同时记指标 `besdk_db_pool_wait_seconds{component}`。
   - be-ops 增加 `connection-budget-scan` 门禁：按部署文件把每个进程的 `PG_POOL_MAX` 加起来，再加上迁移、Casdoor、Keycloak 的连接预留，总数必须小于 `max_connections - superuser_reserved_connections`。
4. **角色级的护栏**（be-ops 生成，`ALTER ROLE … SET`）：`statement_timeout=30s`、`idle_in_transaction_session_timeout=60s`、`lock_timeout=5s`。报表、导出这类长查询在事务里用 `SET LOCAL statement_timeout` 放宽（走 `Store.TxWith`，`data-layer.md` §2.5 的 `TxOptions` 增加 `StatementTimeout` 字段）。外壳登录角色也设同样的值。
5. **把迁移角色和运行期角色分开（可选的第二步）**：`<schema>_owner`（NOLOGIN，拥有表）加 `PG_USER`（只有 DML）。迁移以 `PG_USER` 登录后 `SET ROLE <owner>` 再执行 DDL。这样会改变 `data-layer.md` §2.2 那句"一个 schema、一个能连库的登录角色"的通用表述，所以作为**拍板点**列出（Q13）。推荐做：它是"AI 写错 SQL 也删不了表"的唯一硬防线。
6. **pooler 规则**（写进 `database.md`）：可以不用；用的话必须是 transaction 模式，PgBouncer 要 ≥1.21 且 `max_prepared_statements>0`（否则 pgx 和 asyncpg 都要关掉语句缓存）。运行期代码只允许事务级锁，由门禁扫描 `pg_advisory_lock(` / `pg_try_advisory_lock(` 这类会话级调用。**迁移必须直连 PG**，因为 golang-migrate 用会话级 advisory 锁：SDK 迁移入口增加可选键 `PG_MIGRATION_HOST` / `PG_MIGRATION_PORT`，缺省用 `PG_HOST` / `PG_PORT`（brickKit 的迁移容器拿到的环境和主服务完全相同，见 `brickkit docs 05-migration/02-env-passthrough`，所以只能用独立的键来区分）。
7. **带外容器各用独立角色**：Casdoor 用 `casdoor_rw`，只对 `casdoor` schema 有 CREATE。initdb 脚本（`postgres/initdb/00-bootstrap.sql`）里建角色，口令从 `.env` 来。
8. **HA 与备份**不在本文展开，只在 `database.md` 里指向运维文档：K8s 上推荐 CloudNativePG（自带 Pooler CRD、PITR），单机部署用 pgBackRest 或 WAL-G 做 PITR。**PITR 是"数据被删"时唯一真正的回滚手段**（§6.4）。

### 2.5 可替换性

引擎可替换，依据是一致性套件，不靠抽象层。pooler 可替换，因为它在线协议之后，代码无感知。不建 `slot:db`：所有组件都依赖数据库，0104(b) 不成立。

### 2.6 先写的红测试

- be-sdk-go：
  - `TestStore_成员并发超过PG_POOL_MAX_等待后Unavailable且其他成员不受影响`
  - `TestOpenPool_设置MaxOpen与ConnMaxLifetime`
  - `TestShell_物理池大小取成员上限之和与外壳上限的较小值`
  - `TestMigrate_PG_MIGRATION_HOST优先于PG_HOST`
  - `TestShellPool_两成员相同SQL文本_平台表结构不同_不报cached_plan`：先写复现，确认是红的再定修法
- be-ops：
  - `TestGen_角色带statement_timeout与idle_in_transaction_timeout`
  - `TestConnectionBudget_超过max_connections报错并列出各进程`
- be-acceptance：
  - `TestRuntimeAdvisoryLockScan_会话级锁报错`
  - `dbconf` 套件对本机 PG16 全绿，作为基线
- infra：`test_initdb_casdoor不是超级用户`

### 2.7 基础文档提纲（`database.md`）

- **我们的选择**：PostgreSQL ≥14（NOINHERIT 要 16）；一个库，每个组件一个 schema 加一个角色（0102）；SDK 的 `Store` 是唯一入口；池有上限并按成员舱壁隔离；角色级超时；pooler 可选。
- **备选**：MySQL 系、CockroachDB、YugabyteDB、Citus、信创各库、每组件一个库。
- **为什么选它**：本项目的隔离机制（事务级角色切换）、分区、队列认领、DDL 事务性，都是 PG 的原生能力；托管与信创生态覆盖最广。
- **为什么不选其它**：逐个列出缺失的能力（见 §2.3 的表）。
- **何时换**：单库写入成为瓶颈，走 Citus schema 分片；客户强制信创，用 `dbconf` 套件出矩阵后选库；某组件需要 PG 没有的存储能力，按 0102 的"何时重议"处理。

---

## 3. 议题二：标识与单据编号

### 3.1 现状与证据

- 主键：几乎全是 `BIGSERIAL`（迁移里统计到约 50 处），另有 1 处 `SMALLINT`、1 处 `TEXT`；没有一处使用 uuid。
- 契约：id 一律是 `string`（例如 `customer.proto:116` `GetRequest{string id}`、`sales.proto:148`），跨组件引用落库时是 `TEXT`（`sales_orders.customer_id TEXT`，`sales 001:21`）。**这是好的底子：换 id 方案时契约字段类型不用变。**
- 组件内部把自己的 id 当整数解析（`strconv.ParseInt` 有 30 多处：每个 repo 的 `repo.go`、`cursor.go`；inventory 的 `reservation.go:131` 把 `reservation_id` 当整数）。
- 游标：`(created_at, id)` 的 keyset，id 是整数（例如 `finance repo/cursor.go:18-35`）。
- 分区表的主键是 `(id, created_at)`（`sales 001:37`），所以按 id 取一张订单要探每一个分区（`data-layer.md` §3.3 已承认"每个分区探一次 PK 索引"）。
- 单据号：`order_no = "SO" + id`（`sales repo/write.go:106-110`）；finance 的 `entry_no` 用全局序列（`entry.go:84`），`post_no` 是"同期间、同法人连续"的计数器，搭在期间行的锁上（`finance 001:35-40`，`005`）。
- R62：范围外的单条读答 404。

### 3.2 缺口

- **id 泄露业务量**：`SO1532` → `SO1580`，隔两周下两单就能算出这段时间的订单数（即"德国坦克问题"）。将来开客户门户、供应商门户时，这是 B2B 场景里的真实情报泄露。R62 防得住读取，防不住计数。
- **不能合并**：集团合并报表、并购、把一家公司从一套部署搬到另一套、把生产数据（脱敏后）拷到测试环境，所有 BIGSERIAL 都会冲突，要重写全部引用。
- **不能在客户端生成 id**：移动端离线建草稿、带客户端 id 的幂等创建，都做不到（今天要另外引入 `idempotency_key`）。
- **按 id 取单条无法裁剪分区**（见上）。
- **单据号不能按法人、期间、类型编号**：中国企业普遍要求 `SO202610-00012` 这类格式，财务凭证号要求按期间连续；今天只有 finance 自己手写了一份。

### 3.3 市场方案

| 方案 | 大小 | 排序 | 全局唯一 / 可合并 | 泄露 | 生成 | 谁在用 |
|---|---|---|---|---|---|---|
| BIGSERIAL / IDENTITY | 8 B | 严格递增 | 否 | 数量 | 库内序列 | Odoo、ERPNext（部分）、本项目现状 |
| UUIDv4 | 16 B | 无序，B-tree 写放大 | 是 | 无 | 任何地方 | 早期微服务 |
| **UUIDv7**（RFC 9562，2024） | 16 B | 毫秒级时间有序 | 是 | 创建时刻（毫秒） | 任何地方；PG18 原生 `uuidv7()`，PG17 有 `uuid_extract_timestamp()` | SAP RAP 的托管 UUID 键、新一代 SaaS |
| ULID | 16 B（文本 26 字符） | 毫秒有序 | 是 | 创建时刻 | 库外 | 与 UUIDv7 等价，但不是 RFC，PG 没有原生类型 |
| Snowflake 类 | 8 B | 有序 | 要分配 worker id | 时刻 + 节点 | 需要协调（外壳、副本） | Twitter、Discord；D365 的 RecId 是块分配 |
| TypeID / 带前缀 id（`ord_01h…`） | 文本 | 同 v7 | 是 | 同 v7 | 库外 | Stripe 风格；可读性好，但要解析前缀 |

### 3.4 推荐设计

1. **自有主键一律 UUIDv7，列类型是 `uuid`**，由 SDK 的 `besdk.NewID()` 生成（Go 用 `google/uuid` 的 `NewV7`，已经是间接依赖；Python 3.12 用 `uuid-utils` 或 `uuid6`；TS 用 `uuid` v10 以上）。不依赖库默认值，原因有三：提交前就知道 id；分区键可以从 id 派生；PG14–17 都能用。
2. **分区表**：`created_at` 必须等于 `besdk.IDTime(id)`（毫秒精度，由 SDK 在同一时钟下同时给出两者）。按 id 取单条写成 `WHERE id=$1 AND created_at=$2`，`$2` 由 `IDTime(id)` 算出，**只探一个分区**。`data-layer.md` 的 BatchGet 也受益。主键仍是 `(id, created_at)`。
3. **外部引用保持 `TEXT`**：拥有者可能是 fork、外部系统或者别的 id 方案。平台 `sub`（§11）也是 UUIDv7，但在引用方那里仍是不透明文本。
4. **契约**：id 的格式写成"不透明字符串，当前为小写带连字符的 UUID"。0302 不受影响：类型不变，含义仍是"不透明标识"。**不加类型前缀**：解析成本、正则、跨工具互通都会变麻烦；可读性交给单据号解决。TypeID 记为备选。
5. **游标**：默认排序 `created_at DESC, id DESC` 不变。UUIDv7 跨副本不严格单调，这不影响 keyset 的正确性，keyset 只要求全序。
6. **例外**（写进规则）：必须严格单调的计数器（authz 的 `tuple_log` revision、outbox 的发布序号）用 `BIGINT GENERATED ALWAYS AS IDENTITY`；以自然码为键的参考表（币种、单位码）用 TEXT 自然键。
7. **单据编号**：SDK 的 `besdk/numbering`。
   - 平台表 `besdk_number_series(series, scope, period, next_value, updated_at)`，放在每个组件自己的 schema 里，由平台迁移建。
   - API：`NextNumber(tx, numbering.Series{Name, Scope, Period, Gapless})`。`Gapless=true` 时在同一事务里锁行（凭证号、发票类）；`false` 时按块预取（订单号，允许缺号）。
   - 格式由组件自己的配置键给出，例如 `ORDER_NO_FORMAT`，默认 `SO{yyyy}{mm}-{seq:05}`；占位符有 `{le}`、`{yyyy}`、`{yy}`、`{mm}`、`{seq:N}`。按 0104，这是一个配置键，不是槽位族。
   - 期间与日期按业务时区（§4）。
   - finance 的 `post_no` 换成 `numbering`（Gapless，Scope=法人，Period=会计期间）；sales 的 `order_no` 改为在确认时（或建单时，由 sales 决定）分配。
8. **现有 12 个组件怎么办**是拍板点（Q3）：A. 只有新组件、新表用 UUIDv7；B. 这一轮全部切换，重建迁移基线（没有生产数据，演示库和测试库 `db-reset`），版本定为 3.0.0；C. 维持现状。**推荐 B**：后面还有约 50 个组件，混用两套 id 规则对 AI 是长期的认知负担，而现在切换只花工时，不涉及数据迁移。代价是已发布的迁移文件被替换，违反"已发布迁移冻结"，需要写一条决策明文破例（同 I7 的"没有生产数据"判据）。

### 3.5 可替换性

不可替换，也不应可替换：id 方案是数据形状，一次定死。编号格式是配置。

### 3.6 先写的红测试

- be-sdk-go：
  - `TestNewID_是v7且同毫秒内单调`
  - `TestIDTime_与created_at一致_毫秒精度`
  - `TestNumbering_Gapless并发100次连续无缺号`
  - `TestNumbering_按法人与期间分别计数`
  - `TestNumbering_格式占位符_业务时区跨日`
  - `TestNumbering_非Gapless回滚后允许缺号但不重号`
- 组件（以 sales 为样板）：
  - `TestGetOrder_按id只扫描一个分区`：断言 `EXPLAIN` 里只有一个分区
  - `TestOrderNo_不可由id推出`
- be-acceptance：`TestIDTypeScan_新迁移的自有主键不是uuid报错`（`BIGSERIAL` 只对新文件报错）

### 3.7 基础文档提纲（`identifiers-and-numbering.md`）

- **我们的选择**：UUIDv7，`uuid` 类型，SDK 生成；外部引用用 TEXT；分区表的 `created_at` 从 id 派生；单据号由 SDK 的 `numbering` 生成，格式靠配置。
- **备选**：BIGSERIAL、UUIDv4、ULID、Snowflake、TypeID。
- **为什么选它**：可以合并、可以在客户端生成、不泄露数量、按 id 能裁剪分区，而且是 RFC 标准。
- **为什么不选其它**：BIGSERIAL 泄露数量、不能合并；v4 无序；ULID 不是标准；Snowflake 要协调 worker id；前缀让解析变复杂。
- **何时换**：不换。只有当 16 字节的存储真的成为瓶颈（有实测数据）时，个别超大明细表才例外改用 BIGINT IDENTITY。

---

## 4. 议题三：时间、金额与单位

### 4.1 现状与证据

- 时间：`TIMESTAMPTZ` 有 179 处（`data-layer.md` §2.7），DATE 用于 `pricelist_items.date_start/end`（`sales 001:122-123`）、`accounting_periods.start_date/end_date`（`finance 001:33-34`）、`ar_ledger.due_date`。会计期间是 `period TEXT 'YYYY-MM'`（`finance 001:31`）。
- 业务日期计算：见 §0 第 1 条（finance 的四处 `time.Now().UTC()`，`period.go:146` 的 DATE 与 timestamptz 比较；sales 的 `CURRENT_DATE`）。分区维护锚定 UTC（`*/partition/*.go` 里的 `time.Now().UTC()`），这一点是对的。
- 金额：每一处都是 `NUMERIC(18,2)`，包括单价（`sales 001:70,117`、`opportunity 001:83`）和标准成本（`product 001:64`）。数量 `NUMERIC(18,6)`；折扣、税率 `NUMERIC(9,6)`。
- 币种：只有 `sales_orders.currency DEFAULT 'CNY'`（注释"单币种"）和 opportunity 的 `currency` 字段（`opportunity.proto:69,108`）有；`credit_limit`、`ar_ledger` 和凭证分录都没有币种。
- 十进制运算三份：sales `internal/decimal/decimal.go`（big.Rat，四舍五入远离零到分，允许负数）；finance `repo/money.go`（换算成分，正则 `^[0-9]{1,16}(\.[0-9]{1,2})?$`，**不接受负数**）；opportunity `repo/decimal.go`。Python 和 TS 没有对应实现。
- 单位：全局 `uoms`（单位类别 + 基准单位 + `rounding`），`uom_conversions.factor NUMERIC(18,6)` 只存一个方向（`product 001:9-38`）。

### 4.2 缺口与 bug

- **B-1 / B-2 / B-3 / B-4**：见 §0 第 1 条（月末最后一天、UTC 对法人时区、`CURRENT_DATE`、处理时刻对单据日期）。**B-1 当 bug 修进这一轮**，红测试见 §4.6。
- 会计期间 `'YYYY-MM'` 默认会计年度等于自然年。4 月起始的会计年度、13 期、4-4-5 周历都表达不了，或者会产生误导：标签 2026-04 实际是 FY2026/27 的第 1 期。
- 单价只有 2 位小数：五金件 0.0035 元/个、按克计价的原料都表达不了；标准成本 2 位小数，成本滚算会累积误差。
- 3 位小数的币种（KWD、BHD、OMR）、0 位小数的币种（JPY、KRW）没有统一规则；现金舍入（CHF 0.05）没有位置。
- 多币种：没有汇率、汇率类型、本位币、重估。registry 里已经有 `integration-payment-stripe/paypal`、`hrm-payroll-es`、`im-slack/teams`，说明海外客户在路线图上。
- 舍入规则不成文：实际是"四舍五入远离零"（与 PG NUMERIC 一致），行级舍入还是整单舍入、尾差怎么分摊，都没有统一。
- 单位：没有"产品专属包装单位"（A 产品 1 箱 = 12 个，B 产品 1 箱 = 24 个）；factor 6 位小数时 mg→kg 刚好用满，再小就溢出；没有 UN/ECE Rec 20 码（`integration-edi` 和电子发票会用到）。

### 4.3 市场方案

| 主题 | 方案 | 说明 |
|---|---|---|
| 金额存储 | 整数最小单位（Stripe：BIGINT 分） | 精确、快；但币种小数位要随值一起携带，单价和汇率这类非金额的小数仍需要十进制 |
| | 固定 scale 的 NUMERIC（ERPNext `decimal(21,9)`、D365 `numeric(32,16)`） | 简单；舍入在应用层按币种做 |
| | 浮点 + 币种 rounding（Odoo） | 有已知的精度问题，不选 |
| | SAP CURR 两位小数、JPY 移位存储 | 是出了名的坑，不选 |
| 契约表示 | 十进制字符串（0301） / `google.type.Money`（units+nanos） / 整数分 | 0301 已定为字符串；`google.type.Money` 要两个字段且是 9 位小数，与 0301 冲突 |
| 十进制库 | Go：big.Rat / `shopspring/decimal` / `cockroachdb/apd`；Python：标准库 `decimal`；TS：`decimal.js` / `big.js` | apd 实现了通用十进制算术规范，舍入模式齐全 |
| 时区 | 用户时区显示（SaaS 常见） / 公司时区（ERP 常见：同一张单据所有人看到同一天） | — |
| 会计期间 | 自然月 / 会计年度起始月可配 / 13 期 / 4-4-5 | 主流 ERP 都支持"期间表 + 日期区间" |

### 4.4 推荐设计

**时间**

1. 瞬时一律用 `timestamptz`，在线上传输：proto 用 `google.protobuf.Timestamp`，REST 和事件用 RFC 3339 UTC。
2. **业务日期一律用 `DATE`**：proto 用 `google.type.Date`，REST 和事件用 `"YYYY-MM-DD"`（OpenAPI `format: date`）。它从不做时区换算。
3. **业务时区属于法人**。`mdm/org` 的法人带 IANA 时区；部署级默认值是共享变量 `BUSINESS_TIMEZONE`（例如 `Asia/Shanghai`）。SDK 的 `besdk.BusinessDate(ctx, legalEntity, instant) civil.Date` 是唯一的换算入口；mdm/org 建成之前只读默认值。
4. **数据库会话时区永远是 UTC**。共享池、外壳合并的情况下，任何会话级 `SET TIME ZONE` 都是"漏写 LOCAL"那一类雷。业务 SQL 里禁止 `CURRENT_DATE`、`now()::date`、`date_trunc(…, now())`、`::date` 作用于 timestamptz，由门禁 `business-date-scan` 卡住；"今天"由 SDK 算出后作为参数传入。
5. **事件里带单据的业务日期**（例如 `document_date`、`posting_date`，只增可选字段）。消费方按它记账，不按处理时刻。缺失时（旧事件）退回 `BusinessDate(occurred_at)`，绝不退回 `now()`。
6. **会计期间**：期间表本来就有 `start_date` / `end_date`，保留这一点；`period` 码只当标签，用"日期落在 [start_date, end_date] 内"来查，比较两边都是 DATE。会计年度的起始月、期数由"开会计年度"命令（D7）的参数决定。
7. **用户显示**：单据上的业务日期原样显示；瞬时默认按法人时区显示并带时区标注。不新增用户时区偏好（0404 不变）。

**金额**

1. 列规格：金额 `NUMERIC(19,4)`；单价、成本 `NUMERIC(19,6)`；数量 `NUMERIC(19,6)`；汇率 `NUMERIC(19,10)`；比率 `NUMERIC(9,6)`（不变）。列的 scale 只表示**容量**，舍入发生在 SDK。
2. **币种总是成对出现**：每张带金额的单据头有 `currency CHAR(3)`（ISO 4217）；行上的金额沿用单据币种。法人有本位币；跨币种的单据在单据上快照 `fx_rate`、`fx_rate_date`、`fx_rate_type`。凭证分录同时存原币金额和本位币金额。
3. **SDK `besdk/money`**（三门语言一致）：
   - 内置 ISO 4217 小数位表，项目可以覆盖现金舍入；
   - `Parse`、`Format(currency)`、`Round(mode)`：默认 HALF_AWAY_FROM_ZERO（中国税务口径），可选 HALF_EVEN；
   - `Allocate(total, weights)`：最大余数法分摊尾差；
   - `TaxLine` / `TaxDocument`：两种舍入口径由组件选择。
   
   三份手写实现删除。Go 选 `cockroachdb/apd/v3`（舍入模式全、无 float 路径；`shopspring/decimal` 为备选）。
4. **跨语言一致性**：`be-acceptance/moneyconf/vectors/*.json`，三门 SDK 读同一组向量（解析、格式化、舍入、分摊、税额），做法同 `authz-architecture.md` §5.4 的决策向量。
5. **汇率归属**是拍板点（Q5）：推荐新组件 `mdm/currency`（币种、汇率类型、按日汇率），它是被所有人读、自己不调用任何人的 mdm 类枢纽；备选是放在 erp/finance 内。
6. 契约：金额字段仍是字符串（0301）。按币种小数位格式化输出，所以 CNY 仍然是 `"12.30"`，**现有消费者看到的字符串不变**；新增 `currency` 字段，只增不改。

**单位**

- 保留全局单位类别；新增 `product_uom_conversions(product_id, uom_id, factor)`，产品专属换算优先于全局换算。
- `factor NUMERIC(24,12)`。
- 加 `unece_code` 列（可空）。
- 数量舍入按单位的 `rounding` 在 SDK 的 `money.RoundQty` 里执行。
- 序列号追踪的产品，数量必须是整数（inventory 的业务规则）。

### 4.5 可替换性

时区、币种、舍入模式是配置和数据，不是槽位。十进制库是 SDK 内部实现。

### 4.6 先写的红测试

- erp/finance（**这一轮的 bug**）：
  - `TestPostEntry_月末最后一天下午_记入当月`（今天是红的）
  - `TestPostEntry_北京时间10月1日07点30_记入10月`（今天记进 9 月）
  - `TestAutoEntry_事件带posting_date_按单据日期记账_不按消费时刻`
  - `TestAutoEntry_跨月重放的旧事件_记入原期间`
- erp/sales：`TestPricing_生效日按业务时区_北京时间零点后立即生效`（今天要到 08:00 才生效）
- be-sdk-go：
  - `TestBusinessDate_法人时区换算_夏令时边界`
  - `TestMoney_向量全部通过`
  - `TestAllocate_尾差最大余数法_总和不变`
  - `TestMoney_JPY零位_KWD三位`
  - `TestRoundQty_按单位rounding`
- be-sdk-python / be-sdk-ts：`moneyconf` 向量
- be-acceptance：
  - `TestBusinessDateScan_CURRENT_DATE报错`
  - `TestMoneyColumnScan_新迁移金额列scale小于4报错`

### 4.7 基础文档提纲（`time-and-calendars.md`、`money-quantity-units.md`）

- **我们的选择**：瞬时 / 业务日期两分；业务时区属于法人；会话时区固定 UTC；事件带业务日期；期间按日期区间查。金额用固定 scale 的 NUMERIC 加 SDK 舍入；币种成对出现；ISO 4217；跨语言向量。
- **备选**：用户时区为准、数据库会话时区、整数分、浮点、`google.type.Money`、Odoo 的币种 rounding。
- **为什么选它**：同一张单据对所有人是同一天；共享池下会话状态不可靠；固定 scale 简单，又能容纳全部币种。
- **为什么不选其它**：见 §4.3。
- **何时换**：出现单列需要大于 19 位整数的场景（超大额累计报表）时，局部放宽 precision。

---

## 5. 议题四：多租户

### 5.1 现状与证据

- 单租户。JWT 的 `org_id` 恒为 `DEFAULT_ORG_ID`（`identity-permissions.md` §4.2 第 6 条），I10 推荐加 `tenant_id`、弃用 `org_id`。
- 法人：只有 finance 有 `legal_entity_id TEXT`（期间、凭证、应收），缺省值 `'default'`（`finance 003`、`004`）；它从 sales 事件里读法人，缺失就用 default（`autoentry.go:49-52`）。sales、inventory（仓库没有挂法人）、opportunity 都没有法人列。
- 任何表都没有 `tenant_id`。种子数据只有一个法人。
- 隔离单位：部署。`0201` 写着"Customers deploy on one machine"。

### 5.2 缺口

- **"一个客户 = 一套部署"从没写成决策**。所以"tenant_id 以后加不进表"的担心一直悬着。
- **多公司（集团）是 ERP 的刚需，今天的交易单据表达不了**：一张销售订单属于哪个法人、走哪套账、用哪个本位币，都没有列；仓库属于哪个法人也没有。等这些分区表上有了数据再补列，就要回填，并重建唯一索引。
- token 没有 `aud` 和 `tenant_id` 校验。多套部署共用一个 IdP、或误配成同一把签名私钥时，A 部署签的 token 在 B 部署也有效。

### 5.3 市场方案

| 形态 | 隔离 | 运维成本 | 噪声邻居 | 谁在用 | 与本项目 |
|---|---|---|---|---|---|
| **每租户一套部署**（silo：独立库、独立进程） | 最强，可以单独升级、单独备份恢复 | 每租户一套进程（一组外壳约 1–2 GB 内存） | 没有 | SAP S/4HANA Cloud（每租户一个系统）、Dynamics 365 F&O（每环境一个库）、Odoo Online（每租户一个库）、国内"专属云" | 与 0102、brickKit 的"一个项目一个部署"、`-f deploy.<env>.yaml` 天然吻合，**代码零改动** |
| 一套部署内每租户一个库 | 强 | 迁移要跑 N 遍；连接池按库分开 | 共享计算 | 部分 SaaS | 与 0102 的共享池冲突 |
| 每租户一个 schema | 中 | 本项目已经按组件分 schema，再乘以租户数是组件数 × 租户数，迁移量爆炸 | 共享 | 早期 Rails SaaS | 否 |
| **行级 `tenant_id`**（池化） | 弱，全靠代码 | 最省 | 严重，要配额 | Salesforce（org_id）、NetSuite、多数 SMB SaaS | 每张表、每个唯一索引、每条查询都要带上；0206 不用 RLS，只能靠 SDK 和门禁；是 3.x 级别的重做 |
| 租户内多公司列（`company_id`） | — | — | — | Odoo `company_id`、D365 `DataAreaId`、SAP `BUKRS`、ERPNext `company` | **ERP 必需** |

### 5.4 推荐设计

1. **新决策：租户 = 部署**（silo）。一个客户就是一个 brickKit 项目实例，独占自己的库、NATS 账号、bucket 和 IdP 组织（或独立的 IdP）。SaaS 运营方给每个租户一套部署：K8s 上每租户一个 namespace，`deploy.<tenant>.yaml` 只覆盖 `vars:`。**表里不加 `tenant_id`。**
2. **租户内多公司走法人维度，前置**：
   - 每张交易单据表（订单、出入库流水、预留、商机、待办里引用单据的行）**现在就加** `legal_entity_id TEXT NOT NULL`；
   - 仓库加 `legal_entity_id`；主数据（客户、产品）默认跨公司共享，按需再加"限定公司"关联表；
   - 事件 payload 带 `legal_entity_id`；
   - `legal_entity` 维度（已存在于 data scope）用于权限，见 `authz-architecture.md`。
   
   法人主数据归 `mdm/org`（registry 已占位）。
3. **token**：`tenant_id`（I10）+ `aud`。SDK 验签时要求 `aud` 包含部署配置 `TENANT_ID`（新的共享变量），并校验 `iss` 等于 `IAM_ISSUER`（新共享变量，§11）。这样多套部署共用一个 IdP 也不会互相串用 token。
4. **租户内的噪声邻居**（组件之间）：§2.4 的池舱壁和角色超时；NATS 每个流有上限（`events-consistency.md` E2）；K8s 用 resources/limits（`component.yaml` 里已经有 `requests`）。
5. **种子数据**：加第二个法人（`「本地测试」华南子公司`），让 `legal_entity` 维度和多公司过账有数据可测（05-data 的"维度要真实存在"）。
6. **何时重议**：出现"上千个小微租户、单租户付费撑不起一套进程"的商业模式时，评估池化（行级 `tenant_id`）。那时 `Store` 已经是唯一入口，可以由 SDK 强制每条语句带租户谓词，加门禁、加一致性测试。但它仍然是每个组件一次大版本，不在本轮做。

### 5.5 可替换性

形态不做成可切换。理由：池化与 silo 的差别落在每张表和每条 SQL 上，这正是"不能是简单改动"的那一类。写成决策，并给出何时重议的条件。

### 5.6 先写的红测试

- be-sdk-go：
  - `TestVerify_aud不含TENANT_ID拒绝`
  - `TestVerify_iss不符拒绝`
  - `TestVerify_缺aud的旧token在过渡期内按配置放行或拒绝`：开关 `IAM_REQUIRE_AUD`，一个版本之后默认改为 true
- erp/sales：`TestCreateOrder_落库带legal_entity_id_事件带legal_entity_id`
- erp/finance：`TestAutoEntry_按事件的法人记账_缺法人时拒绝而不是default`：缺法人时拒绝还是走 default，由用户定，见 Q2
- be-acceptance：`TestTransactionalTableScan_交易表缺legal_entity_id报错`（表清单取自 `lifecycle.yaml` 里声明为交易表的那些）

### 5.7 基础文档提纲（`tenancy.md`）

- **我们的选择**：租户 = 部署；法人是行维度；token 带 `tenant_id` 和 `aud`。
- **备选**：每租户一个库、每租户一个 schema、行级 `tenant_id`。
- **为什么选它**：主流 ERP 云的做法；隔离、升级、备份都按租户进行；代码零改动。
- **为什么不选其它**：与 0102 的共享池冲突、迁移量爆炸、隔离全靠代码。
- **何时换**：见 §5.4 第 6 条。

---

## 6. 议题五：迁移与 schema 演进

### 6.1 现状与证据

- 工具：Go 用 golang-migrate（`be-sdk-go/migrate/migrate.go`），一条一条 `Steps(1)`，库版本比镜像新时 WARN 后跳过（`:126-176`），适配 brickKit 的多版本串联（`brickkit docs 05-migration/03-multi-version-chain`：低版本先跑、高版本后跑，每次 `up` 都重跑）。Python 用 yoyo（print 有自己的 `migrate.py`，`data-layer.md` §2.1）。
- 幂等：`make migrate-idempotent` 连跑两次；L4 要求至少真跑一次 `down` 再 `up`（`06-testing.md:83`）。
- K8s：迁移是 Job，跑完才部署主服务（`brickkit docs 05-migration/01-migration-service`）。滚动更新期间，**旧 Pod 会在新 schema 上继续运行**。
- 迁移连接**没有** `lock_timeout` / `statement_timeout`（`migrate.go` 的 `dsn()` 只加了 `search_path` 和 `x-migrations-table`，`:216-246`）。
- 回填：只有 opportunity 的 `order_id` 回填是一个消费者（`crm-opportunity.md` 测试记录），没有通用机制。
- 规则：0302 说契约只增不改；迁移只有"可以连跑两次"和"迁移状态表放在自己的 schema 里"两条，**没有 expand/contract 的规则**。

### 6.2 缺口

- **锁排队导致整表不可用**：`ALTER TABLE … ADD COLUMN … DEFAULT …`（PG11 以后是元数据操作）本身很快，但要拿 ACCESS EXCLUSIVE 锁。它排在一个长事务后面时，后面所有查询都排在它后面。没有 `lock_timeout` 就是线上事故。
- **多版本并存时的兼容性**只写在 brickKit 文档里，项目约定里没有，门禁也查不到。最典型的错误：新版本加了 `NOT NULL` 且没有默认值的列，旧版本的 INSERT 全部失败。
- **大表回填写在迁移里**：迁移 Job 长时间持锁、超时；K8s Job `backoffLimit: 0`，失败一次部署就停了。
- **`CREATE INDEX CONCURRENTLY`**：golang-migrate 把整个文件作为一次 Exec 执行，多语句会处在隐式事务里，而 `CONCURRENTLY` 不能在事务块中执行。**待最小复现确认**：单语句文件是否可行、yoyo 怎么处理。
- **回滚策略不成文**：`down` 文件存在，但生产能不能执行 `down`、应用回滚到旧镜像时 schema 怎么办，都没有说。
- 外壳的 R63 第 2 点改迁移（删掉 `OWNER TO`）、日期字面量门禁见 `data-layer.md` §2.6，不重复。

### 6.3 市场方案

| 工具 / 方法 | 要点 | 对本项目 |
|---|---|---|
| golang-migrate / yoyo（现状，0103 锁定） | 命令式 SQL，简单 | 保留 |
| goose | 支持 Go 函数迁移，`-- +goose NO TRANSACTION` | 与 0103 冲突；它对 CONCURRENTLY 的写法可以借鉴 |
| Atlas | 声明式 + lint（破坏性变更检测） | lint 思路可借鉴；商业特性需付费 |
| Flyway / Liquibase | Java（0105 排除） | 否 |
| pgroll / Reshape | 用视图和版本化 schema 实现零停机 expand/contract | 会新建 schema、改 search_path，与 0102 和 `Store` 冲突 |
| **Squawk**（PG 迁移 linter） | 静态检查不安全操作：加 NOT NULL、非 CONCURRENTLY 建索引、改列类型、没设 lock_timeout | **进 `make gates`**（许可证待核实） |
| expand/contract（并行变更） | 先加（新旧都能用），切读写，旧版本退役之后再删 | 主流做法（Stripe、GitHub），**写进规则** |

### 6.4 推荐设计

1. **SDK 迁移入口的护栏**：迁移连接是独占连接，会话级 SET 安全；通过 DSN 的 `options=-c lock_timeout=5s -c statement_timeout=15min` 设定。拿锁超时就退避重试（3 次，指数退避），最后失败要点名是哪条迁移、等的是什么锁（查 `pg_locks` / `pg_stat_activity` 打出阻塞者的 pid 和 SQL 前 200 字）。Python 入口照做。
2. **expand/contract 规则**（写进 `schema-evolution.md`，并在 02-backend 的 Database 一节放一行）：
   - **expand 迁移**（任何时候都可以）：加表；加可空列或带常量默认值的列；`CREATE INDEX CONCURRENTLY`（单独一个文件，文件头注释 `-- besdk:no-transaction`）；加 `NOT VALID` 约束，之后再 `VALIDATE`。
   - **contract 迁移**（删列、删表、改类型、加 NOT NULL、改名）：文件头必须声明 `-- besdk:contract after=<版本>`。be-acceptance 的门禁 `contract-migration-scan` 读 `brickkit.yaml`：只要这个组件还有低于 `after` 的版本并存，就报错。brickKit 已经知道哪些版本在并存，见 §14 反馈 4。
   - **永远禁止**：改列名、改列语义（同 0302）。
3. **回填**：SDK 的 `besdk/backfill`，声明式。
   - 任务名 + 每批的 SQL 或 Go 函数 + 游标列；在 Start 里、生命周期锁下运行，每批一个事务，进度记在平台表 `besdk_backfill(name, cursor, done, updated_at)`，重启后接着做。
   - 读路径在回填完成前必须兼容新旧两种形态（双读）。完成后组件自己再发一版 contract 迁移。
   - 迁移里只允许回填有界的小表（参考数据），由门禁按 `lifecycle.yaml` 声明的"大表"清单检查。
4. **回滚策略**：生产只前滚。`down` 只用于开发和测试（`db-reset`、L4）。应用回滚到旧镜像必须能在 expand 之后的 schema 上运行，这一点由规则 2 保证。数据被误删时，唯一的回滚是 PITR（运维文档）。
5. **Squawk 进 `make gates`**：只扫描新迁移文件，冻结文件只报警告（与 `data-layer.md` §2.6 的冻结规则一致）。
6. **基线**：不做迁移压缩，golang-migrate 不支持，冻结规则也不允许。新安装照样从 001 跑起，现在的成本是秒级。

### 6.5 可替换性

迁移工具被 0103 锁定，不可替换；护栏和规则在 SDK 与门禁里。

### 6.6 先写的红测试

- be-sdk-go migrate：
  - `TestMigrate_被长事务阻塞_lock_timeout后重试_最终失败点名阻塞者`
  - `TestMigrate_no_transaction文件_CREATE_INDEX_CONCURRENTLY成功`（先做复现）
  - `TestMigrate_多版本并存_旧版本在新schema上重跑up无事可做`（已有行为，补成测试）
- be-sdk-go backfill：
  - `TestBackfill_中途崩溃从游标续跑`
  - `TestBackfill_两副本只有一个执行`
  - `TestBackfill_完成后标记done不再运行`
- be-acceptance：
  - `TestContractMigrationScan_并存旧版本时contract迁移报错`
  - `TestContractMigrationScan_旧版本退役后放行`
  - `TestSquawk_新文件加NOT_NULL无默认值报错`
- 组件 L4：`TestOldVersionWritesAfterExpand`。以 sales 为样板：旧版本的二进制向 expand 之后的 schema 插入成功（用上一个 tag 的镜像跑）

### 6.7 基础文档提纲（`schema-evolution.md`）

- **我们的选择**：golang-migrate / yoyo + SDK 护栏；expand/contract 由门禁把关；回填由 SDK 执行；只前滚。
- **备选**：Atlas 声明式、pgroll、goose、Flyway。
- **为什么选它**：符合锁定的技术栈；多版本并存是 brickKit 的原生能力，把关点也应该在 `brickkit.yaml`。
- **为什么不选其它**：语言约束（0105）、与 schema 隔离冲突（pgroll）。
- **何时换**：迁移数量或复杂度让命令式 SQL 难以评审时（有实测的评审失误记录），再评估引入 Atlas lint 作为补充。

---

## 7. 议题六：搜索

### 7.1 现状与证据

- 只有 mdm 的两个组件支持 `q`：`strpos(lower(code|name), lower($q)) > 0`，按"前缀命中 = 0、包含 = 1"排序（`mdm/customer/backend/internal/repo/read.go:91-152`，product 同构）。
- 没有任何索引能加速它，每次都是顺序扫描，而且叠加 90 天窗口（D3 要去掉这个窗口，去掉之后就是全表扫描）。
- WHERE 子句由 `fmt.Sprintf` 拼出来（参数仍然是占位符，安全）。这与 02-backend 的"no dynamic SQL"说法不完全一致。

### 7.2 缺口

- 量到十万级（SKU）以后，全表 `lower()` 扫描会变慢。
- **中文用户期待的拼音和首字母检索（"zgyh" → 中国银行；用友、金蝶称之为"助记码"）完全没有。**
- 全角半角、繁简不归一；同音和错别字不容错。
- 没有跨实体的全局搜索（顶栏的"Services"搜索只搜菜单，见 03-frontend）。
- pg_trgm 对中文的效果**待实测**：两字查询（"华为"）凑不出完整的三元组，索引用不上；Alpine（musl）下的 locale 可能让 CJK 字符被当成非字母数字，提取三元组时被丢掉。

### 7.3 市场方案

| 方案 | 中文 | 运维 | 许可证 | 权限过滤 | 说明 |
|---|---|---|---|---|---|
| strpos / LIKE（现状） | 子串可以，没有拼音 | 无 | — | 同一条 SQL，天然有 | 小表足够 |
| pg_trgm + GIN | 三字以上；两字差 | 内置扩展 | PG | 天然有 | 托管云普遍支持 |
| **pg_bigm**（二元组） | 为 CJK 设计 | 扩展，需要安装 | PG 许可 | 天然有 | 托管云和信创库是否支持要逐个确认 |
| zhparser / pg_jieba（中文分词 FTS） | 好 | 扩展，带词典 | — | 天然有 | 阿里云 RDS 支持 zhparser |
| ParadeDB pg_search（BM25） | 依赖分词器 | 扩展 | AGPL | 天然有 | 许可证有风险 |
| Meilisearch | 好（内置中文分词）、容错 | 单独服务，单节点 | 社区版 MIT，部分企业特性另有许可 | 要投影 ACL 或后过滤 | 体验最好、最轻 |
| Typesense | 尚可 | 单独服务，数据全在内存 | GPL-3 | 同上 | — |
| OpenSearch | IK 和 pinyin 插件，强 | JVM，重 | Apache-2.0 | 同上 | 大规模、日志检索共用 |
| Elasticsearch | 同上 | 重 | AGPL / SSPL / ELv2 | 同上 | 许可证复杂 |

### 7.4 推荐设计

**两层，分开回答"该不该做成适配器"。**

1. **组件内的查找（List 的 `q`）：SDK 帮手，不做成槽位。** 原因：它必须和数据权限谓词、游标在同一条 SQL 里，跨网络就会破坏 List/Can 一致性（`authz-architecture.md` §3.5）。`besdk/search`：
   - 写入时，SDK 生成 `search_text`：小写、全角转半角、繁体转简体（可选）、原文 + 全拼 + 首字母，各段之间用分隔符隔开。拼音库 Go 用 `mozillazg/go-pinyin`，Python 用 `pypinyin`，两者的输出用 `searchconf` 向量对齐。组件只需声明 `search: [code, name]`。
   - 查询策略按 Store 打开时的能力探测选择：有 pg_bigm 用 bigram GIN；有 pg_trgm 用 trigram GIN，短于 3 字时退回 strpos；两者都没有就用 strpos。三种策略的结果集必须一致，只是快慢不同，由一致性测试保证。
   - 排序：完全相等 > 前缀 > 首字母前缀 > 包含。
   - 拼写 SQL 的工作收进 SDK，组件里不再有 `fmt.Sprintf` 拼 WHERE。
2. **全局搜索 / 全文 / 附件内容：以后做成槽位族 `infra/search-*`**，现在只定方向，不排期。
   - 成员：`search-pg`（默认，PG FTS + bigm）、`search-meilisearch`、`search-opensearch`。
   - 入口：消费各组件的事件，建立投影；对外提供 `Query`。
   - 权限：返回候选 id，再按类型调用属主组件的 `_authz/check`（`authz-architecture.md` 的资源契约）做后过滤，并过量取回以补足一页；或者直接复用 `besdk_authz_acl` 投影。
   - 寻址：经共享变量 `SEARCH_URL`，任何组件都不得依赖成员（0104(b)、0107 的推广）。
   - 一致性套件 `be-acceptance/searchconf`：索引延迟上界、不可见记录不出现、删除后消失、中文与拼音用例。

### 7.5 先写的红测试

- be-sdk-go search：
  - `TestSearchText_拼音首字母_全角半角`
  - `TestSearch_三种策略结果集一致`
  - `TestSearch_两字中文查询_bigm可用时走索引`：用 EXPLAIN 断言
  - `TestSearch_用户输入百分号下划线按字面`
- 组件：`TestListCustomers_q首字母zgyh命中中国银行`（mdm 的两个组件）
- 实测项：`pg_trgm在postgres:16-alpine上对CJK是否提取三元组`（只读复现，写进 `to-verify.md`）

### 7.6 基础文档提纲（`search.md`）

- **我们的选择**：组件内用 SDK 帮手（规范化列 + 按能力选索引）；全局搜索是将来的槽位族。
- **备选**：一上来就用外部搜索引擎、各组件各写一份 LIKE。
- **为什么选它**：数据权限和游标必须同在一条 SQL 里；中文的拼音需求统一实现一次。
- **为什么不选其它**：外部引擎需要 ACL 投影，而且只读能力不能替代 List。
- **何时换**：单表超过百万行、或者需要跨实体全文检索时，启动 `infra/search` 族。

---

## 8. 议题七：文件与对象存储

### 8.1 现状与证据

- 只有一个配置键 `S3_URL`（`04-configuration.md` 的表，`be-sdk-go/endpoint.go:54`）；凭据只在 infra 的 `.env` 里（`STORAGE_ACCESS_KEY` / `STORAGE_SECRET_KEY`，`docker-compose.infra.yml:118-119`），组件拿不到；没有 bucket 约定；SDK 没有客户端；**没有组件真的使用对象存储**。
- RustFS 是默认，MinIO 是互斥的替换件（`resources.tsv`）。0106 已经定了"S3 API 就是端口"。
- print 把 PDF 字节放在 gRPC 响应里返回。gRPC 默认最大消息 4 MB，带图片的多页 PDF 会超出。
- registry 已为 `infra-attachment`、`infra-storage` 占位；`data-layer.md` D4 的冻结存储也要用 S3。

### 8.2 推荐设计

1. **配置键**（追加进 `04-configuration.md` 的共享键表）：
   - `S3_URL`（不变）；
   - `S3_REGION`（默认 `us-east-1`）；
   - `S3_FORCE_PATH_STYLE`（RustFS / MinIO 用 `true`）；
   - `S3_ACCESS_KEY_ID`、`S3_SECRET_ACCESS_KEY`（secret，**每个组件一份**）；
   - `S3_BUCKET`（每个组件一个，取自 registry）。
   
   `registry/schemas.tsv` 增加 `bucket` 列（只增），或者新建 `buckets.tsv`。
2. **每个组件一个 bucket、一份凭据，策略只允许访问自己的 bucket**，类比 0102 的 schema 加角色。be-ops 生成 `make storage-init`（建 bucket、建用户和策略、设生命周期规则），与 `db-init` 并列。RustFS 的 IAM 策略能力要实测；MinIO 已知支持。
3. **SDK `besdk/blob` 端口**：`Put`、`Get`、`PresignPut(key, contentType, maxBytes, ttl)`、`PresignGet(key, ttl, disposition)`、`Delete`、`Head`。S3 适配器 Go 用 `aws-sdk-go-v2`，Python 用 `aioboto3`。测试辅助 `besdktest.Blob(t)`：用本机 RustFS 建一个随机 bucket。一致性套件 `be-acceptance/blobconf` 对 RustFS、MinIO、AWS S3、阿里云 OSS 各跑一遍：预签名、Range、`Content-Length` 限制、多段上传、生命周期、Object Lock。
4. **`infra/attachment`（业务组件，不是 SDK）**：
   - 元数据：属主组件、资源类型、资源 id、文件名、类型、大小、sha256、扫描状态、保留类别、法律保全。
   - **授权**：一律向父记录要授权，调用父记录所属组件的 `_authz/check`（`authz-architecture.md` 已列为资源契约的使用者）。
   - 上传：客户端申请，attachment 返回预签名 PUT 到 `quarantine/` 前缀（带内容长度上限）；客户端调用 `complete`；扫描器扫描；通过后移到 `clean/`，状态改为 READY，并发事件。
   - 下载：预签名 GET，有效期 5 分钟，带 `response-content-disposition`。bucket 永不公开读。
5. **病毒扫描**：扫描器是适配器，ClamAV（clamd，GPL 但作为独立服务使用）或 `none`（开发环境）。按 0106 算基础设施，地址走共享变量 `SCAN_URL`。是否默认开启，见 Q10。
6. **保留**：S3 生命周期规则清理隔离区（24 小时）和临时文件；需要法定保存的（电子会计档案）用 Object Lock（WORM，合规模式）。RustFS 的 Object Lock 要实测。冻结数据（D4）走同一套 bucket 策略。
7. **print**：大文件不再通过 gRPC 传字节，返回 attachment id（或者 print 自己的 bucket 加预签名 GET）。契约只增：新增 `RenderToObject` rpc，旧 rpc 保留，在契约里写明上限。

### 8.3 可替换性

存储后端靠 S3 API 加 `blobconf` 套件替换（0106 已定），扫描器靠适配器替换。

### 8.4 先写的红测试

- be-sdk-go blob：
  - `TestPresignPut_超过maxBytes被拒`
  - `TestPresignGet_过期后403`
  - `TestBlob_凭据不能访问其他组件bucket`
- be-ops：`TestStorageInit_每组件bucket与策略_幂等`
- infra/print：`TestRender_超过4MB走RenderToObject`
- attachment（建组件时）：
  - `TestUpload_未扫描前不可下载`
  - `TestDownload_父记录不可见答404`

### 8.5 基础文档提纲（`files-and-objects.md`）

- **我们的选择**：S3 API；每个组件一个 bucket 加凭据；SDK `blob`；attachment 组件管元数据和授权；预签名直传；先隔离、再扫描；用生命周期规则和 Object Lock 做保留。
- **备选**：文件存在数据库里（bytea / large object）、共享一个 bucket 按前缀划分、经后端中转上传。
- **为什么选它**：隔离方式与 0102 一致；大文件不经过应用进程。
- **为什么不选其它**：bytea 撑大备份；共享 bucket 一把凭据就能读全部。
- **何时换**：不换端口；后端按客户的环境选择。

---

## 9. 议题八：可观测性

### 9.1 现状与证据

- **traces**：`InitOTel` 只装了 TracerProvider，`service.name` 是进程名（`otel.go:21-23`），外壳里就是外壳名（`shell/run.go:101`）。成员只按 instrumentation scope 区分（`shell.go:35-51`）。**没有 propagator，HTTP 不提取 `traceparent`，gRPC 没有 interceptor 或 stats handler，NATS 不注入**（全仓库 grep 为空）。`OTEL_BASE_URL` 为空时是 blackhole（`otel.go:28-35`），这是对的。
- **metrics**：每个模块一个 Prometheus registry，挂在成员自己 HTTP 端口的 `/metrics` 上（`gin.go:73`）。RED 指标的标签没有 component（`gin.go:27-37`）。`rt.Meter` 来自全局的 noop MeterProvider，**是个摆设**。Prometheus 用 docker_sd，按容器 label 只抓一个端口（`prometheus.yml:11-19`），外壳里只能抓到一个成员（**V-08**）。
- **logs**：stdout JSON，带 `component_id`、`trace_id`、`span_id`（`logging.go:17-48`）；**没有级别配置**（`HandlerOptions{}`，`logging.go:24`）。R51（调用方错误不记 ERROR）由各组件自己写 `logFailure` 实现（`dev/test-records/06b/mdm-customer.md:304`、workflow 2.0.1）。collector 有 OTLP 日志管道，但**没有人发 OTLP 日志**，也没有采集容器 stdout，所以 Loki 是空的。
- 栈：OTel collector → Prometheus remote write / Tempo / Loki → Grafana，全是 `:latest`（`docker-compose.observability.yml`）。
- 审计：authz 声明了审计事件，但从没发过（`identity-permissions.md` §1 第 1 条）；registry 为 `infra-audit` 占了位。

### 9.2 推荐设计

1. **传播**（三门 SDK，在 Bootstrap 里只装一次；propagator 是无状态的全局对象，合并安全）：
   - W3C TraceContext + Baggage；
   - HTTP 服务端提取，客户端（`UserHTTP`）注入；
   - gRPC 用 `otelgrpc` 的 stats handler，服务端和客户端都挂；
   - NATS 发布时把 `traceparent` 写进 header（与 `events-consistency.md` §1.1 对齐）。**消费端开新 span，并以 span link 指向生产者**，而不是作为它的子 span（OTel messaging 语义约定：异步链很长，作为父子关系会把整条 trace 撑得很大）。
2. **外壳里每个成员一个 TracerProvider 和 MeterProvider**：resource 设 `service.name=<成员 ID>`、`service.version`、`service.namespace=<项目>`、`service.instance.id=<容器>`、`deployment.environment`。导出器共享，`rt.Tracer` 和 `rt.Meter` 取自成员自己的 provider。这样 Tempo 里按组件筛选，单跑和合并的结果一致。
3. **metrics 仍以 Prometheus 拉取为主**（collector 不是必需的）：
   - 外壳在自己的端口暴露一个汇总的 `/metrics`，用 `prometheus.WrapRegistererWith(Labels{"component": id})` 合并各成员的 registry，**解决 V-08**。
   - 单跑时也给 RED 指标加上常量标签 `component`，两种形态的查询语句一致。
   - `rt.Meter` 接上真的 MeterProvider，经 OTel Prometheus exporter 写进同一个 registry，否则就删掉它，免得 AI 以为它能用。推荐接上：OTel API 是跨语言的标准写法。
4. **日志**：
   - 新的标准键 `LOG_LEVEL`（`debug|info|warn|error`，默认 `info`），在外壳里按成员各自生效。
   - **R51 收进 SDK**：`besdk.LogFailure(ctx, logger, msg, err)` 按 gRPC code 分级：Internal、Unknown、DataLoss 记 ERROR；Unavailable、DeadlineExceeded 记 WARN；Canceled 不记；客户端错误（InvalidArgument 等）记 INFO。拦截器和 Gin 中间件自动调用，组件里那些 `logFailure` 删掉。
   - 字段名对齐 OTel 日志数据模型（`severity_text`、`trace_id`、`span_id`、`service.name`）。
   - stdout 仍是唯一的输出（12-factor，K8s 友好）。collector 加 `filelog` receiver（Docker 挂载 `/var/lib/docker/containers`，K8s 用 `k8s` 日志采集）把日志送进 Loki。
   - Go 的脱敏改成和 Python 一样，在 handler 里自动处理。
5. **审计日志与应用日志分开**：
   - 应用日志给运维排障，保留 14–30 天，可以采样。
   - **审计日志**是"谁、在何时、对什么、做了什么、前后各是什么"，属于业务数据：SDK 的 `besdk.Audit(tx, action, target, diff)` 在同一事务里写 outbox，subject 为 `audit.<domain>.<name>.<action>.v1`；`infra/audit` 消费后写入只追加、哈希链式的表，保留期由用户定（Q12）。等保 2.0 / 《网络安全法》第二十一条要求日志留存不少于 6 个月。字段级 diff 按字段键掩码处理 PII（`authz-architecture.md` 的字段级权限）。
   - 发出 `act`（代理人，委托链）的请求，审计里必须记下完整的 act 链。
6. **相关性**：`request_id` 保留，作为客户端可见的 id；日志一律带 `trace_id`；事件带 `causation_id`（见 `events-consistency.md`）。Grafana 里从日志跳到 trace（Loki 的 derived fields）。
7. **镜像钉版本**：infra 和 obs 的镜像全部钉到 `x.y.z`，与 0103 的"exact versions"一致。Tempo、Loki 显式配置保留期（各 14 天）。

### 9.3 可替换性

OTLP 本身就是端口：SigNoz、OpenObserve、阿里云 ARMS、腾讯云 APM、Datadog 都接收 OTLP，换后端只改 collector 的 exporter，不改代码。在 `observability.md` 里写明。

### 9.4 先写的红测试

- be-sdk-go：
  - `TestHTTP_入站traceparent被继承_出站UserHTTP注入`
  - `TestGRPC_客户端到服务端同一trace`
  - `TestNATS_消费span链接到生产span`
  - `TestShell_两成员span的service.name各自不同`
  - `TestShellMetrics_汇总端点含component标签且无重复注册panic`
  - `TestLogLevel_warn时info不输出`
  - `TestLogFailure_InvalidArgument记INFO_Internal记ERROR_Canceled不记`
  - `TestRedact_Go自动脱敏与Python一致`：共用一组向量
  - `TestAudit_与业务同事务_回滚则无审计`
- be-sdk-python / be-sdk-ts：对应的传播测试
- infra：`test_obs_镜像无latest`
- 真机（T25 里加）：sales → inventory → finance 一条链在 Tempo 里是一个 trace（加 link）

### 9.5 基础文档提纲（`observability.md`）

- **我们的选择**：OTel（traces，metrics 走 API）+ Prometheus 拉取 + stdout JSON 日志经 collector 采集；每个成员一个 resource；R51 分级在 SDK；审计走 outbox → `infra/audit`。
- **备选**：只用 Prometheus 拉取、只用 OTLP 推送、SDK 直接发日志到 Loki、各厂商私有 SDK。
- **为什么选它**：厂商中立；不开 collector 也能看指标；日志不依赖网络。
- **为什么不选其它**：私有 SDK 绑定厂商；从 SDK 直接推日志，网络抖动时会阻塞或丢日志。
- **何时换**：客户已经有可观测平台时，只改 collector 的配置。

---

## 10. 议题九：配置与密钥

### 10.1 现状与证据

- 配置只经环境变量注入；brickKit 负责 `$var:`、`${}`、`file://`、`existingSecret`（`brickkit docs 01-three-layers/07-sensitive-values`）：secret 在 Docker 上进 0600 的 env 文件，在 K8s 上进 Secret；`file://` 的内容**在生成部署文件时读入并内联**；外壳把成员配置打包成一个 JSON。
- `.env` 存明文；06b 期间多行 PEM 两次泄露进对话记录（`common.md` 的 `.env` 安全一节）。
- 轮换：iam 的签名私钥支持"上一把公钥"（`APP_TOKEN_PREVIOUS_PUBLIC_KEY_PEM`，`component.yaml`），这是唯一的轮换设计。数据库口令轮换只能改 `.env`、重新生成、重启。
- SDK：`Config.IntOr` 解析失败时静默回退默认值（`runtime.go:56-75`），T16 审查也提到过"loose int parsing"（`progress.md:93`）；`MustString` 会 panic（`runtime.go:48`），在模块的 `New` 里触发就会带垮外壳。

### 10.2 市场方案

| 方案 | 要点 | 许可证 | 对本项目 |
|---|---|---|---|
| 环境变量 + `.env`（现状） | 最简单 | — | 保留为默认 |
| K8s Secret + External Secrets Operator（ESO） | 从 Vault、OpenBao、云 KMS 同步成 K8s Secret | Apache-2.0 | K8s 推荐，配合 `existingSecret`，零代码 |
| HashiCorp Vault | 动态数据库凭据、租约 | BUSL（2023 起） | 许可证有风险 |
| **OpenBao**（Linux 基金会分支） | 与 Vault 的 API 兼容 | MPL-2.0 | 适配器的首选目标 |
| SOPS（CNCF） | 加密文件提交进 Git | MPL-2.0 | 可替代明文 `.env` |
| 云 KMS / Secrets Manager | 托管 | 商业 | 经 ESO 接入 |
| 配置中心（Nacos / Apollo） | 动态配置 | — | 违反"没有配置服务器"（AGENTS 的 BrickKit 一节），不选 |

### 10.3 推荐设计

1. **配置面不变**：只走环境变量和 configSchema，没有配置中心。
2. **SDK 收紧类型解析**：`Int`、`Bool` 解析失败返回错误（`IntOr` 遇到"有值但非法"时也报错并点名键），不再静默回退。`MustString` 改成返回 error 的 `Require`。外壳在 `buildModules` 时收集所有成员的配置错误，一次报出。
3. **`Secret` 端口**（SDK）：
   - `rt.Config.Secret(key) Secret`，`Secret.Current() (string, error)`。
   - 适配器：`env`（默认）；`file`，当配置值是 `@file:/run/secrets/x` 这种运行期路径时使用，按 mtime 重新读取，K8s Secret 卷挂载和 OpenBao Agent 都适用；`openbao`（以后再做，用 AppRole 或 K8s auth，支持租约续期）。
   - pgx 的 `BeforeConnect` 每建一条新连接都调用 `Current()`，所以**数据库口令轮换不用重启**：ALTER ROLE 改口令 → 更新 Secret → 新连接用新口令，旧连接按 `PG_CONN_MAX_LIFETIME` 自然淘汰。
   - 一致性套件 `be-acceptance/secretconf`：轮换期间零失败请求。
4. **K8s 推荐路径**：ESO 加 `existingSecret`，用卷挂载而不是环境变量（这样才能热更新）。这需要 brickKit 支持"secret 以文件形式挂载"，见 §14 反馈 3。Docker 上用 compose secrets。
5. **JWT 签名私钥**：沿用"当前 + 上一把"的双钥 JWKS，轮换流程写进运维文档。algorithm 不写死（§11）。
6. **`.env` 的替代**：推荐用 SOPS 加密的 `secrets.enc.yaml` 提交进 Git，开发机用 age 密钥解密生成 `.env`。这是拍板点 Q14，它改变开发者的工作流。

### 10.4 先写的红测试

- be-sdk-go：
  - `TestIntOr_有值但非法报错点名`
  - `TestShell_成员配置错误一次全部报出_不panic`
  - `TestSecretFile_文件更新后Current返回新值`
  - `TestPool_口令轮换后新连接成功_旧连接到期淘汰`
- be-acceptance：`secretconf` 用 file 适配器轮换数据库口令，期间请求零失败

### 10.5 基础文档提纲（`config-and-secrets.md`）

- **我们的选择**：环境变量 + configSchema；brickKit 的四种值形式；SDK 的 `Secret` 端口（env / file / openbao）；K8s 用 ESO。
- **备选**：配置中心、直接接 Vault、SOPS。
- **为什么选它**：符合 brickKit "没有配置服务器"；轮换不用重启。
- **为什么不选其它**：配置中心会成为运行期依赖；Vault 的许可证。
- **何时换**：客户强制使用某个密钥平台时，加一个适配器，再跑 `secretconf`。

---

## 11. 议题十：身份提供方（IAM）槽位族

### 11.1 现状与证据

- `infra/iam-casdoor` 是薄适配层：浏览器和 Casdoor 之间走标准的 OIDC 授权码 + PKCE 流程；`/api/iam/token` 用 Casdoor 的 id_token 换应用 token，签出的应用 token 是 RS256，带 `sub`、`roles`、`dept_path`、`org_id`，TTL 600 秒；refresh 轮换；`/api/iam/webhooks/casdoor` 桥接用户事件，发 `infra.iam.user.created/updated/disabled.v1`；gRPC 提供 `BatchGetUsers`、`GetTenantFeatures`（`iam.proto:21-25`）。
- 契约包 `contracts/infra/iam/v1` 放在 casdoor 成员的仓库里。
- 已知问题：
  - 契约字段 `casdoor_id_token`；
  - 前端写死 Casdoor 路径（§0 第 3 条）；
  - `sub` 就是 IdP 的 sub；
  - access token 没有 `iss`、`aud`、`jti`；
  - SDK 只认 RS256，不校验 `iss`、`aud`（`jwt.go:47-53`）；
  - refresh token 能当 access token 用（`identity-permissions.md`，一期必修）；
  - iam → authz 的依赖边（`authz-architecture.md` 要求删除）。
- 第二个实现已经占位：registry 的 `infra-iam-keycloak`，`docker-compose.infra.yml` 的 keycloak profile，端口 28081，schema `keycloak`。

### 11.2 市场方案

| IdP | 语言 / 资源 | 许可证 | 标准覆盖 | 中国生态 | 适合 |
|---|---|---|---|---|---|
| **Casdoor**（现状） | Go，轻 | Apache-2.0 | OIDC、OAuth2、SAML、LDAP；webhook | **内置钉钉、企业微信、飞书、微信登录** | 国内中小客户，默认 |
| **Keycloak** | Java，约 0.5–1 GB 内存 | Apache-2.0，CNCF | 最全：OIDC、SAML、LDAP/AD 联邦、细粒度管理权限；标准 token exchange（26.2 起） | 社区插件 | 大型企业、已有 AD 的客户 |
| Zitadel | Go | **v3 起改为 AGPL-3.0** | OIDC、SAML、多租户组织、actions | 弱 | 许可证要评估 |
| Authentik | Python | MIT（核心） | OIDC、SAML、LDAP 出口、**SCIM 出口**、代理 | 弱 | 中型、偏运维友好 |
| Ory（Kratos + Hydra + Keto） | Go，多服务 | Apache-2.0 | 无头，要自己做 UI | 无 | 想完全自定义登录体验的 |
| Logto | TS | MPL-2.0 | OIDC，组织（多租户）是一等概念 | 弱 | SaaS 开发者体验 |
| 客户自有 IdP（Entra ID、Okta、钉钉统一身份） | — | — | OIDC + SCIM 2.0 | 钉钉支持 OIDC | 企业客户普遍有 |

### 11.3 推荐：族契约 `infra.iam.v1`（放进新仓库 `contract-infra-iam`，与 authz 族同法）

**前端与 IdP 之间：只用标准**

1. `GET /api/iam/login-config`（Public）返回 `{issuer, discovery_url, client_id, scopes, pkce: "S256", end_session_supported}`。前端只读 `/.well-known/openid-configuration` 拿到授权端点和 token 端点，**不写任何厂商路径**。Casdoor 也提供标准 discovery，要实测它的 token 端点能否在浏览器端完成 PKCE（今天用的是它的私有路径，原因要查清楚）。
2. `POST /api/iam/token` 改成 RFC 8693 的形状：`grant_type=urn:ietf:params:oauth:grant-type:token-exchange`、`subject_token`、`subject_token_type=urn:ietf:params:oauth:token-type:id_token`（再加 `audience` 可选）。casdoor 成员保留 `casdoor_id_token` 作为弃用别名（只增）。refresh 和 logout 不变。

**应用 token：族契约的核心**

3. claims 集合：`iss`（=`IAM_ISSUER`）、`aud`（=`TENANT_ID`）、`sub`、`typ`、`iat`、`exp`、`nbf`、`jti`，以及 `tenant_id`、`roles`、`dept_path`、`act`、`azp`、`locale`（`authz-architecture.md` §3.2 的扩展加上 `locale`）。
4. `alg` 由 JWKS 里每把钥匙的 `alg` 决定，SDK 接受白名单 `RS256`、`ES256`、`EdDSA`。是否需要国密 SM2，看 Q9。
5. JWKS 同时发布当前钥和上一把钥，`kid` 必填。

**`sub` 归平台所有**

6. iam 族签发的 `sub` 是**平台用户 id**（UUIDv7）。成员内部维护 `identity_links(idp, idp_issuer, idp_sub, user_id)`。首次登录时创建平台用户；按 email 或用户名链接已有用户的策略由配置决定（默认只按 `idp_sub` 精确匹配，自动按 email 链接是一个有安全风险的选项）。
7. 换 IdP 的迁移路径：新成员导入旧成员的 `identity_links` 导出（族契约里定义导出格式 NDJSON），把新 IdP 的 sub 链接到已有的平台 `sub`，这样 `owner_id`、角色分配、审计全都不受影响。**前置**：今天切换只需要重签 token，加上对种子和测试数据做一次 `db-reset`；数据越多，代价越大。

**目录与生命周期**

8. 事件 `infra.iam.user.created|updated|disabled|deleted.v1`（deleted 是新增的）。payload 至少包含 `sub`、`display_name`、`email`、`phone`、`locale`、`im_accounts`、`status`。成员怎么得知变更是它自己内部的事：Casdoor 用 webhook，Keycloak 轮询 admin events，通用成员用 **SCIM 2.0 入站**（`/scim/v2/Users`、`/Groups`），Entra、Okta、Authentik 都能推送。
9. gRPC `BatchGetUsers`、`GetTenantFeatures`：GetTenantFeatures 按 I3 收窄，并入 `/api/me/access`。服务账号（`sub: svc:<id>`，client-credentials）留作扩展点（`identity-permissions.md` §5.3）。
10. 能力声明 `capabilities`：`password_login`、`social_cn`（钉钉、企业微信、飞书）、`ldap`、`saml`、`scim_inbound`、`mfa`、`token_exchange_delegation`、`service_accounts`。前端登录页按能力降级。

**成员与顺序**

- ① `infra/iam-casdoor`（默认，升级到族契约）；
- ② **`infra/iam-keycloak`**（第二实现，registry 已占位；证明 OIDC discovery、RFC 8693、轮询式目录同步、重型企业场景）；
- ③ `infra/iam-oidc`（通用：任何 OIDC IdP 加 SCIM 入站，证明"客户自带 IdP"）。
- 不选 Zitadel 当第二实现：AGPL，且与 Keycloak 证明的东西重合。

**一致性套件 `be-acceptance/iamconf`**

- 自带一个测试 OIDC 提供方（发 id_token），被测成员指向它（Keycloak、Casdoor 成员要配置成联邦到它，或者直接用真实 IdP 容器跑）。
- 用例：
  - `TestIAMConf_discovery字段齐全`
  - `TestIAMConf_token_exchange_RFC8693形状`
  - `TestIAMConf_签出token含iss_aud_jti_typ_tenant_id`
  - `TestIAMConf_refresh当access用被拒`
  - `TestIAMConf_refresh轮换旧token立即失效`
  - `TestIAMConf_JWKS双钥轮换期间新旧token都能验`
  - `TestIAMConf_同一IdP用户两次登录sub不变`
  - `TestIAMConf_停用用户事件在N秒内发出且登录被拒`
  - `TestIAMConf_identity_links导出导入后sub不变`
  - `TestIAMConf_未声明的能力明确降级`
- SDK 侧：
  - `TestVerify_拒绝typ_refresh`
  - `TestVerify_alg白名单`
  - `TestVerify_iss_aud`
- 前端：`FE-1 登录流程只依赖discovery`（mock 一个非 Casdoor 的 discovery）。

### 11.4 基础文档提纲（`identity-provider.md`）

- **我们的选择**：IdP 只负责认证，iam 族签发平台 token，`sub` 归平台；族契约 + `iamconf`；默认 Casdoor，第二实现 Keycloak，第三实现通用 OIDC + SCIM。
- **备选**：组件直接验 IdP 的 token、把 IdP 的 sub 当成平台 sub、Zitadel、Authentik、Ory、Logto。
- **为什么选它**：换 IdP 不碰业务数据；国内社交登录靠 Casdoor，企业联邦靠 Keycloak。
- **为什么不选其它**：直接验 IdP token，会让角色和部门 claims 依赖 IdP；Zitadel 的许可证。
- **何时换**：按客户场景在族内换成员，不改族契约。

---

## 12. 议题十一：数据层 i18n 与错误语言

### 12.1 现状与证据

- 主数据只有单个 `name TEXT`（客户、产品、单位、分类、科目、商机阶段）。
- 前端要求每个页面中英文齐全（`03-frontend.md:100-102`），语言是用户偏好，存在 `localStorage`（0404），**服务端不知道用户的语言**。
- 错误：`status.Error(codes.X, err.Error())` 直接透出组件内部的中文消息；`codes.Internal` 也照透（`mdm/customer service/status.go:29`、`erp/sales service/status.go:46`）；HTTP 错误体是 `{"error": msg}`（`gin.go:134-137`）；`data-layer.md` §5.3 已提出加 `code` 字段作为第一步。
- 通知（notification）和打印（print）都要按收件人或客户的语言出文字，但拿不到语言。

### 12.2 市场方案

| 主题 | 方案 | 谁在用 |
|---|---|---|
| 可翻译字段 | JSONB 翻译列（`name` 加 `{"zh-CN":…, "en":…}`） | Odoo 16+（从翻译表迁到了 JSONB 列） |
| | 文本表（每个实体一张 `*_texts(id, lang, name)`） | SAP（MAKT 等）、D365 |
| | 中央翻译服务 | 跨组件，违反边界 |
| 错误模型 | Google AIP-193：`ErrorInfo{reason, domain, metadata}` + 可选 `LocalizedMessage` | Google API、gRPC 生态 |
| | RFC 9457 Problem Details（`type`、`title`、`detail`） | REST 生态 |
| | 服务端按 `Accept-Language` 返回翻译后的文案 | 传统 Web |

### 12.3 推荐设计

1. **可翻译主数据**：需要多语言的短文本加 `<field>_i18n JSONB NOT NULL DEFAULT '{}'`；`name` 保留为部署默认语言的值（只增，兼容现有消费者）。
   - SDK 的 `besdk/i18n.Pick(row, field, locale, fallbacks)` 负责取值。
   - 契约：在实体上加 `map<string,string> name_i18n`，只增。BatchGet 的调用方按自己的语言选值。
   - 单据快照：单据记录 `language`，快照时按单据语言取产品名，例如出口订单用英文名打印。
   - 搜索：`search_text` 包含所有语言的值（§7）。
   - 这一条**不是前置**：主数据表不分区，之后加列成本很低。
2. **错误模型**（三门 SDK 一致，**06c 之前定**）：
   - gRPC：`status` + `ErrorInfo{reason: UPPER_SNAKE, domain: <组件ID>, metadata}`，`BadRequest` 用于字段错误。
   - REST：`{"code": reason, "domain", "message", "details", "trace_id"}`，`message` 是默认语言文案，只供调试。
   - GraphQL：`extensions.code` 和 `extensions.domain`。
   - **`codes.Internal` 一律只返回通用消息加 `trace_id`**，原始错误只进日志，由 SDK 映射层强制。
   - 每个组件在 `contracts/errors.yaml` 里声明 `reason`、gRPC code、HTTP status、参数、中英文模板，只增不改，门禁检查。前端由它生成 i18n 消息表（与"前端类型从契约生成"同一条路）。服务端不翻译。
3. **服务端需要语言的场景**：用户语言作为 IAM 用户档案的属性（OIDC 标准 claim `locale`），进 token 和用户事件；前端改语言时同步写回 IAM（新增 `PUT /api/me/locale`）。客户和供应商的语言是 mdm 的字段（`preferred_language`）。通知和打印按收件方的语言渲染。
4. **标准码**：语言用 BCP 47，国家用 ISO 3166-1，币种用 ISO 4217，时区用 IANA，单位用 UN/ECE Rec 20。全部只存码，名称由 i18n 层负责。

### 12.4 先写的红测试

- be-sdk-go：
  - `TestErrorMapping_Internal不泄露原文_带trace_id`
  - `TestErrorMapping_ErrorInfo映射为REST的code与domain`
  - `TestI18nPick_回退链`
- be-acceptance：
  - `TestErrorCatalogScan_代码里出现未声明的reason报错`
  - `TestErrorCatalogScan_已发布reason被删报错`
- 组件（mdm/customer 样板）：`TestCreate_重复code返回reason_CUSTOMER_CODE_TAKEN`
- 前端 FE-1：`未知reason回退到message并上报`

### 12.5 基础文档提纲（`i18n-data.md`、`error-model.md`）

- **我们的选择**：JSONB 翻译列、标准码、错误 reason 目录、前端翻译、服务端只在通知和打印里按收件方语言渲染。
- **备选**：文本表、中央翻译服务、服务端按 `Accept-Language` 翻译、RFC 9457。
- **为什么选它**：不跨组件、只增；错误码可以测试，前端可以生成。
- **为什么不选其它**：文本表 JOIN 成本高、AI 容易漏；服务端翻译要在每个组件里维护文案。
- **何时换**：单个实体翻译语言超过 10 种、需要按语言建索引时，评估文本表。

---

## 13. 组外壳（T21–T24）之前必须定的（汇总）

| 项 | 会改什么 | 为什么必须在外壳之前 | 拍板点 |
|---|---|---|---|
| 租户 = 部署；交易单据加 `legal_entity_id` | sales、inventory、opportunity 的分区表；事件 payload | 分区表有数据后再补列要回填、重建唯一索引；外壳组好后成员要再升一轮 | ★Q1、★Q2 |
| 主键 UUIDv7（现有组件是否一起换） | 12 个组件的全部表；内部 id 解析；游标 | 现在只花工时，不涉及数据迁移；之后 50 个组件按哪套规则写，取决于它 | ★Q3 |
| 金额精度与币种列 | 全部金额列；单据头加 `currency` | 改列类型要重写表，分区表尤其重 | ★Q4 |
| 平台 `sub` 与 IdP 解耦；token 加 `iss`、`aud`、`jti`、`tenant_id` | iam 的 token 内容、链接表；SDK 验签 | `owner_id` 等数据随用随积累；与 I10、`typ` 修复同一版 iam | Q7 |
| 错误模型（reason 目录） | 全部组件的错误映射、契约 `errors.yaml` | 06c 前端依赖它；外壳的映射层在 SDK 里 | — |
| 外壳里每成员的 trace、metrics、日志级别；池舱壁 | be-sdk-go 的 `shell/`、外壳的 configSchema | **这就是外壳代码**；外壳组好后再改要重建外壳 | — |
| 业务日期规则；事件带业务日期；finance 期间 bug | finance、sales；sales 事件只增字段 | 已经是线上 bug；事件字段越早加，消费方越早用上 | Q6 |

不是前置的（可以随后续轮次做）：搜索帮手、blob 端口与 attachment、`numbering`（建议与 Q3 同批，但不阻塞外壳）、i18n 列、Secret 端口、迁移护栏与 expand/contract 门禁（越早越好，但不改表）、dbconf 套件、Keycloak 成员。

---

## 14. （a）基础文档目录：本议题贡献的文件

目录名和编号由另一份布局提案决定。下面是本文负责的文件，每个都以 §2–§12 的"基础文档提纲"为骨架（我们的选择 / 备选 / 为什么选 / 为什么不选其它 / 何时换）。

| 文件 | 范围（一行） |
|---|---|
| `database.md` | PG 方言族与目标引擎分级、`dbconf` 一致性套件、schema 加角色隔离、池的上限与舱壁、pooler 规则、角色超时、HA 与备份的入口 |
| `identifiers-and-numbering.md` | UUIDv7 自有主键、外部引用用 TEXT、id 派生分区键、游标、单据编号（`numbering`） |
| `time-and-calendars.md` | 瞬时与业务日期、法人业务时区、会话时区固定 UTC、事件带业务日期、会计期间与会计年度 |
| `money-quantity-units.md` | 金额、单价、汇率的列规格、币种成对、ISO 4217、舍入与分摊、跨语言向量、汇率归属、单位与换算 |
| `tenancy.md` | 租户 = 部署、法人维度、`tenant_id` 和 `aud`、组件间噪声邻居、何时重议池化 |
| `schema-evolution.md` | 迁移工具与护栏、expand/contract 与并存版本门禁、回填、只前滚、Squawk |
| `search.md` | 组件内的 `q` 帮手（规范化列、拼音、按能力选索引）、全局搜索槽位族的方向 |
| `files-and-objects.md` | S3 端口、每组件 bucket 加凭据、`blob` SDK、attachment 组件、预签名、扫描、保留与 Object Lock |
| `observability.md` | 传播、每成员 resource、外壳汇总 `/metrics`、日志级别与 R51、日志采集、审计与应用日志、OTLP 即端口 |
| `config-and-secrets.md` | 环境变量配置面、brickKit 的四种值形式、`Secret` 端口与轮换、ESO 和 OpenBao、`.env` 替代方案 |
| `identity-provider.md` | IAM 族契约（discovery、RFC 8693、claims、JWKS、平台 `sub`、目录事件、能力）、成员顺序、`iamconf` |
| `i18n-data.md` | 可翻译主数据、标准码、服务端语言来源 |
| `error-model.md` | AIP-193 映射、reason 目录与门禁、Internal 不外泄、前端生成 |

另外建议**新决策**（落地时编号）：租户 = 部署；UUIDv7 主键；业务日期与业务时区；错误 reason 目录；每组件 bucket。**修订**：0102（何时重议加上 Citus、迁移与运行期角色分离）、0301（币种成对）、0203（claims 加 `iss`、`aud`、`jti`、`locale`）、0107（`IAM_ISSUER`、`TENANT_ID` 共享变量）。

## 15. （b）brickKit 反馈候选

只列"对所有用户有益"的，并且按 memory 的要求，**提交之前要在重建后真机验证**。未验证的先进 `to-verify.md`。

1. **按"槽位"声明依赖，不按成员**：例如 `dependencies.slots: [iam]` 注入 `IAM_URL`，取值由项目填。它直接对应 0107 的"何时重议"，也能消除 C18 那类手写版本化服务名漂移（`config/vars.yaml` 里 `infra-authz-2-0-1` 这种）。对 AI 尤其有帮助：族契约和寻址方式在 manifest 里就能看出来。
2. **迁移容器可以单独覆盖少量环境变量**（例如 `migration.env` 或部署文件的 `migrationOverrides`）。场景是 pooler 处于 transaction 模式时迁移要直连 PG。今天只能由组件自己发明 `PG_MIGRATION_HOST` 这类键，各组件写法会不一样。
3. **secret 以文件挂载的方式交付**（Docker 用 compose secrets、K8s 用 Secret 卷），而不是在生成部署文件时内联。热轮换要靠它，也能减少 env 被打印进日志的风险（06b 两次 PEM 泄露）。
4. **把"并存版本"暴露给迁移进程**（保留名，例如 `BRICKKIT_COEXISTING_VERSIONS`），让迁移工具能拒绝在旧版本还在运行时执行 contract 步骤。brickKit 文档已经说"数据兼容是作者的事"，这一条把它变成可以检查的事。
5. **外壳的 metrics 抓取**：`prometheus.io/port` 只能声明一个端口。可以文档化"外壳汇总各成员 /metrics 并加 component 标签"这种模式，或者让 labels 支持多端口（V-08）。
6. **09-patterns 增加"槽位族契约仓库 + 一致性套件"一页**：族契约不放在任何成员的仓库里；成员按能力声明降级；用黑盒套件判定是否合格（本项目 authz、iam、search、blob 都按这个套路）。
7. **configSchema 值的类型校验**：`brickkit lint` 和 `up` 按 `type: integer|boolean` 校验 config 里的字面值。今天写错类型会一路到运行期，组件 SDK 可能静默回退。
8. **AI 指南增加"基础选型清单"**：id、时间与时区、金额、租户、错误模型。组件作者在步骤 ① 必须回答（类似本项目的"Before writing code"）。这些是 AI 最容易各写各的、事后又最难改的部分。
9. **"每租户一套部署"的模式页**：`-f deploy.<tenant>.yaml` + `vars:`，加上 K8s namespace，作为官方推荐的多租户形态。

## 16. （c）需要用户拍板的问题

只列业务或方向性的问题。标 ⏱ 的必须在 T21–T24 之前定（会改表、改契约或改外壳）。

| # | 问题 | 推荐 | 备选 |
|---|---|---|---|
| ⏱★Q1 | **租户形态**：将来会不会有"多个客户共用一套部署"的 SaaS？ | 不会；一个客户一套部署，写成决策；上千个小微租户的商业模式出现时再重议 | 现在就为池化 SaaS 在每张表加 `tenant_id` |
| ⏱★Q2 | **集团多公司**在不在近期范围？交易单据要不要现在加 `legal_entity_id`？缺法人的旧事件是拒绝还是记到 default？ | 在；现在加；拒绝（不悄悄记进 default） | 先不加，等第一个多公司客户 |
| ⏱★Q3 | **主键换 UUIDv7**：现有 12 个组件要不要一起换（重建迁移基线、演示库和测试库 `db-reset`、版本 3.0.0）？ | 一起换 | 只有新组件用；维持 BIGSERIAL |
| ⏱★Q4 | **多币种 / 海外客户**在不在范围？（registry 里有 Stripe、PayPal、西班牙薪资、Slack） | 在：金额列扩到 `NUMERIC(19,4)`、单价 `(19,6)`，单据头加 `currency` | 只做人民币单币种 |
| Q5 | 汇率归谁？ | 新组件 `mdm/currency` | 放在 erp/finance 内 |
| ⏱Q6 | 默认业务时区 `Asia/Shanghai`；会不会有跨时区的法人？会计年度会不会不从 1 月开始？ | 法人带时区；"开会计年度"命令支持起始月 | 全部固定北京时间、自然年 |
| ⏱Q7 | IAM：同意第二实现是 **Keycloak**、第三是通用 OIDC + SCIM 吗？平台 `sub` 与 IdP 的 sub 解耦（现在切，种子数据和测试数据重建）？ | 同意；同意 | 第二实现选 Authentik 或 Zitadel；sub 维持现状 |
| Q8 | 中文搜索的拼音和首字母是不是一期必备？是否接受依赖 pg_trgm / pg_bigm 扩展（托管云和信创库的可用性各不相同）？ | 是；接受，并按能力探测降级 | 只做子串匹配 |
| Q9 | 等保 / 密评是不是目标客户的硬要求？要不要支持国密 SM2 签 token、SM4 加密？ | 先列为能力项，有真实客户需求时再做 | 现在就做 |
| Q10 | 附件病毒扫描是否默认开启？（ClamAV 约 1 GB 内存） | 生产默认开，开发默认关 | 一律可选 |
| Q11 | 主数据多语言（产品英文名、出口单据）要不要？ | 要，加 `*_i18n` 列（不急） | 不要 |
| Q12 | 审计日志保留多久、谁能查？（等保要求不少于 6 个月） | 业务审计保留 3 年，可配；租户管理员可以查自己的审计 | 只给运维看 |
| Q13 | 迁移角色和运行期角色要不要分开（运行期删不了表）？ | 要（随 NOINHERIT 第二步一起做） | 维持一个角色 |
| Q14 | 开发机密钥要不要从明文 `.env` 换成 SOPS 加密文件提交进 Git？ | 换（防 06b 那类泄露） | 维持 `.env` |

## 17. 落地顺序（建议，与另外三份合并排期）

0. **现在、不发版**：把 finance 的 B-1 至 B-4 写成红测试并补进 T26 清单；只读复现 `pg_trgm` 对 CJK 的表现和 DB-6（语句缓存 × search_path），结果写进 `to-verify.md`。
1. **用户拍板** Q1–Q4、Q6、Q7（⏱ 项）。
2. **SDK v0.6.0**（与 `data-layer.md`、`events-consistency.md`、`identity-permissions.md` 同一版）：
   - 池配置与舱壁；
   - propagator 与每成员 provider；
   - 外壳汇总 `/metrics`；
   - `LOG_LEVEL` 与 `LogFailure`；
   - 错误映射（reason、Internal 不外泄）；
   - 配置类型收紧；
   - JWT 校验 `iss`、`aud`、`typ`，alg 白名单；
   - `NewID`、`IDTime`；
   - `BusinessDate`；
   - `money` 与向量；
   - 迁移护栏（`lock_timeout`、`PG_MIGRATION_HOST`、no-transaction 文件）。
3. **be-ops / be-acceptance**：
   - 角色超时；
   - `connection-budget-scan`、`business-date-scan`、`contract-migration-scan`、`error-catalog-scan`、`id-type-scan`；
   - Squawk；
   - Casdoor 独立角色；
   - 镜像钉版本。
4. **iam-casdoor 升级到族契约**（`login-config`、RFC 8693 形状、平台 `sub`、`iss`、`aud`、`jti`、`tenant_id`、`locale`）；前端改为走 discovery（06c）。
5. **外壳 T21–T24**：在 SDK v0.6.0 上组装。
6. **12 个组件的版本**（与另外三份同批）：UUIDv7（如果 Q3 选 B）、法人列、金额列、`numbering`、业务日期、错误目录。
7. **之后的轮次**：`dbconf` 矩阵、`blob` 与 attachment、`search` 帮手、Secret 端口、`iam-keycloak`、`infra/audit`。
