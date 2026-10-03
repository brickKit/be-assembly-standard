[English](../../en/04-foundations/03-database.md) · [中文](03-database.md)

# 数据库

项目跑在哪种数据库引擎上、"数据库可替换"的确切含义、每个组件在同一个库里怎么隔离、连接怎么池化和设上限。要改 SDK 的数据库层、外壳的连接池、`be-ops` 生成的建库脚本或 `infra/postgres` 之前，或者要向客户承诺某种数据库之前，先读这篇。

## 范围

本文覆盖：引擎及其版本承诺、兼容发行版、SDK 里的方言层、schema 与角色隔离、组件从配置里拿到的库身份、连接池以及外壳里按成员的舱壁、连接池代理、角色级护栏，以及高可用与备份的入口。留给别的文档的：

- 一个事务里发生的事（隔离级别、超时、重试、加锁顺序、advisory 锁）：[10-local-transactions.md](10-local-transactions.md)；
- 迁移、expand/contract 与并存版本：[08-schema-evolution.md](08-schema-evolution.md)；
- 分区、保留期与冻结数据：[09-data-lifecycle.md](09-data-lifecycle.md)；
- 主键与单据编号：[04-identifiers-and-numbering.md](04-identifiers-and-numbering.md)；
- 组件日常怎么用数据库：[02-backend.md](../01-conventions/02-backend.md#数据库) 和 [04-configuration.md](../01-conventions/04-configuration.md#数据库角色)。

## 选择

- **PostgreSQL 方言族。** 单独运行的组件要求 PostgreSQL 14 及以上；外壳要求 16 及以上，因为它用 NOINHERIT 授权（`GRANT … WITH INHERIT FALSE, SET TRUE`）。基础资源跑的是 `postgres:16-alpine`。
- **"可替换"的意思是：换成另一个说 PostgreSQL 线协议、并且通过数据库套件的引擎。** SDK 里不做多方言抽象。每个组件都要的机制（角色切换、分区、队列认领、advisory 锁、错误分类、平台表）在 SDK 的 PostgreSQL 方言层里只有一份；业务 SQL 留在各组件的 repo 层。
- **一个数据库；每个组件一个 schema、两个角色**：属主角色和运行期角色（[0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)）。
- **身份只来自配置。** 属主角色是 `PG_OWNER_USER`，运行期角色是 `PG_USER`，schema 是 `PG_SCHEMA`；三者都必填，都没有默认值，互相之间、与组件 ID 之间都不推导。迁移里不出现角色名或 schema 名。
- **一切访问都经过 SDK 的 store 句柄**，它在每个事务里切换角色、`search_path` 和 `application_name`。outbox 推送、消费者、生命周期任务也都走它，所以外壳的登录角色自己不需要任何权限。
- **连接池有上限**；在外壳里，每个成员在共享池里有自己的预算。
- **属主角色与运行期角色分开**：属主拥有表并执行迁移；运行期角色只有 DML，不是属主角色的成员，建不了、改不了、删不了表。运行期少数必须的 DDL（提前建分区、装封存守卫、删过期的平台分区）只经由属主创建的 `SECURITY DEFINER` 函数。
- **连接池代理可选**；用的话必须是 transaction 模式，而且迁移绕过它。
- **带外服务**（Casdoor、Keycloak）用各自的角色连库，绝不用超级用户。

**状态**：PostgreSQL 16、schema 加角色的隔离、事务级切换已在用。身份只取自 `PG_USER` 已在三个组件里落地（iam、sales、opportunity）；store 句柄、有上限的池、按成员的舱壁、角色护栏、角色拆分、NOINHERIT 授权、Casdoor 与 Keycloak 的独立角色、数据库套件都已定，随 3.0.0 统一升级落地。

## 端口契约

引擎端口就是"PostgreSQL 线协议加这份能力清单"。SDK 一侧是配置面，以及每个事务做的事。

### 配置键

| 键 | 必填 | 默认值 | 含义 |
|---|---|---|---|
| `PG_HOST`、`PG_PORT`、`PG_DATABASE` | 是 | — | 数据库在哪里（[04-configuration.md](../01-conventions/04-configuration.md#共享连接键)） |
| `PG_USER` | 是 | 无 | 运行期角色：只有 DML；每个事务切换到它；单独运行时也是登录角色 |
| `PG_PASSWORD_FILE` | 是 | — | 密钥，以文件交付（`mount: file`）；值照旧填 `${<REPO>_DB_PASSWORD}`，变量里是文件路径；每建一条新连接读一次（[24](24-config-and-secrets.md#端口契约)） |
| `PG_OWNER_USER` | 是 | 无 | 属主角色：拥有 `PG_SCHEMA` 里的表，执行迁移和平台迁移；运行中的服务从不使用它 |
| `PG_OWNER_PASSWORD_FILE` | 是 | — | 密钥，以文件交付；属主的密码，只有迁移步骤读它 |
| `PG_SCHEMA` | 是 | 无 | 组件拥有的 schema；也是它 `search_path` 里唯一的一项。最多 40 个字符，这样运行时由它派生出的名字（例如 `besdk_migrations_<PG_SCHEMA>`）不会超出 PostgreSQL 63 字节的标识符上限 |
| `PG_POOL_MAX` | 否 | 10 | 单独运行：连接池最多打开的连接数。在外壳里：这个成员在共享池里的并发上限 |
| `PG_CONN_MAX_LIFETIME` | 否 | 30m | 连接用满这么久就关掉换新，这样主备切换和 DNS 变化能被感知 |
| `PG_CONN_MAX_IDLE_TIME` | 否 | 5m | 空闲这么久的连接被关掉 |
| `PG_POOL_ACQUIRE_TIMEOUT` | 否 | 5s | 取连接最多等多久；不超过调用方剩余的截止时间 |
| `PG_MIGRATION_HOST`、`PG_MIGRATION_PORT` | 否 | `PG_HOST`、`PG_PORT` | 迁移连到哪里；`PG_HOST` 指向连接池代理时要设它们。迁移需要另一条连接时，这是 brickKit 推荐的做法：组件声明自己的键，只由它的迁移命令读取 |

可选键写进各组件的 `configSchema`。外壳有自己的 `PG_POOL_MAX`：它那一个物理池的大小，默认取"各成员 `PG_POOL_MAX` 之和"与 40 中较小的一个。

协议没有"最少空闲连接数"这个键（原来的 `PG_POOL_MIN_IDLE` 已退役）：那是各运行时连接池自己的行为，由各 SDK 分别说明（Go 的 pgxpool、Python asyncpg 的 `min_size`、TypeScript 的 pg-pool）。只有一个下限属于协议：服务期间运行时为每个成员至少保持一个会话开着，好让迁移器始终看得到它的版本（[08](08-schema-evolution.md#expand-与-contract)）；单跑时连接池从不降到一个连接以下，外壳为每个成员保持一个空闲的在场会话。

一条已记录的限制：brickKit 给迁移容器的环境和挂载与主服务完全相同，所以运行中的服务也会拿到 `PG_OWNER_USER` 和属主的口令文件。brickKit 有意不做只给迁移的变量（FR06-013）：迁移读到的每个值都在该组件的 `config/` 文件里看得见。SDK 运行期从不读属主凭据。

### 每个事务做什么

```sql
BEGIN;
SET LOCAL ROLE <PG_USER>;                        -- 外壳里：该成员自己的运行期角色
SET LOCAL search_path TO <PG_SCHEMA>;
SET LOCAL application_name = '<组件 ID>';       -- 外壳里：该成员的 ID
-- 每个事务的超时：见 10-local-transactions.md
...
COMMIT;
```

在池化的连接上从不在会话级设置任何东西：不带 `LOCAL` 的 `SET` 会留在连接上，下一个借用者就会在你的 schema 里执行。唯一的例外是专用、不进池的迁移连接：它以属主登录，用完即关（[08-schema-evolution.md](08-schema-evolution.md#迁移入口)）。会话时区是 UTC，从不修改（[05-time-and-calendars.md](05-time-and-calendars.md)）。

区分成员的连接靠 `application_name`：在外壳里 `usename` 永远是外壳的登录角色，所以 `pg_stat_activity` 按 `application_name` 给成员计数（一致性用例 `CP-DB-03`）。在事务之外，连接带着会话级的 `application_name` `<组件 ID>@<版本>`（外壳的在场会话是 `<成员 ID>@<成员版本>`），它在建立连接时作为连接参数给出，而不是事后 `SET`；迁移器读它，在旧版本仍连着时暂缓 contract 迁移（[08](08-schema-evolution.md#expand-与-contract)）。SDK 还给成员的每条语句加上注释前缀 `/* be:<schema> */`，这样 asyncpg 和 pgx 的语句缓存不会让两个平台表结构不同的成员共用同一条预备语句；TypeScript 的 `pg` 驱动保持用未命名语句。

组件代码自己从不发 `SET ROLE` 或 `SET LOCAL ROLE`：只有 store 会发（门禁 `identity-literal-scan`）。

### SDK 在启动时检查什么

- **能力**：`server_version_num >= 140000`（外壳里 `>= 160000`）、声明式分区、`FOR UPDATE SKIP LOCKED`。探测只读 `current_setting('server_version_num')::int`：声明式分区（PostgreSQL 10）和 `SKIP LOCKED`（9.5）都由 14 及以上隐含。缺了哪一项就停止启动，并点名那项能力。
- **身份**：在 `SET LOCAL ROLE` 到 `PG_USER` 之后的一个事务里，执行列出的目录查询，检查：这个角色对 `PG_SCHEMA` 有 `USAGE`、没有 `CREATE`，不是 `PG_OWNER_USER` 的成员；schema 里每张表的属主都是 `PG_OWNER_USER`，且 `PG_USER` 对每张表都有 `SELECT, INSERT, UPDATE, DELETE`。失败时记一条 ERROR 日志、导出 `be_db_identity_ok = 0`，并让 `/readyz` 回 `503`；不让模块停下，也绝不放进 `/healthz`。
- **外壳**：成员配置里写的 `PG_HOST`、`PG_PORT` 或 `PG_DATABASE` 和外壳的不同时，外壳拒绝启动，并点名成员和键。否则这个成员会悄悄用上外壳的库。

### 能力清单

| 能力 | 用在哪里 |
|---|---|
| `SET LOCAL ROLE`、`SET LOCAL search_path` | 共享池上按成员的身份 |
| `GRANT … WITH INHERIT FALSE, SET TRUE`（PostgreSQL 16） | 外壳登录角色能切换到成员的角色，自己却不持有成员的任何权限 |
| RANGE 与 LIST 声明式分区、`pg_partition_tree`、`ATTACH PARTITION` | 会无限增长的表 |
| `FOR UPDATE SKIP LOCKED` | outbox、任务、webhook 队列 |
| `pg_advisory_xact_lock` | 逻辑锁；只用事务级 |
| 事务性 DDL、`CREATE INDEX CONCURRENTLY` | 迁移 |
| `INSERT … ON CONFLICT … RETURNING` | 幂等认领、upsert |
| `uuid`、`NUMERIC`、`timestamptz`、`date`、`JSONB`（只作不透明存储） | 列类型 |
| 带 `SET search_path FROM CURRENT` 的 `SECURITY DEFINER` 函数 | 运行期角色在运行期可以做的那些 DDL |
| SQLSTATE 23505、40001、40P01、55P03、57014、25P04、53300、08 类、57P01–57P03 | SDK 里的错误分类 |

**可选能力。** `pg_trgm` 和 `pg_bigm` 不是必需的扩展：SDK 启动时探测它们，用现有的最好那个建搜索索引；两个都没有时搜索结果照样正确，只是更慢（[25-search.md](25-search.md)）。缺它们的引擎照样能通过认证。

### 角色

| 角色 | 能否登录 | 拥有什么 | 谁用 |
|---|---|---|---|
| `PG_OWNER_USER`（`<schema>` 的属主） | 是 | `PG_SCHEMA` 里的表、序列和函数，因为迁移和平台迁移都以这个角色运行；所有 DDL 由它做 | 只有迁移步骤 |
| `PG_USER`（运行期角色） | 是 | 无；对 `PG_SCHEMA` 有 `USAGE`，经默认权限对其中的表有 `SELECT, INSERT, UPDATE, DELETE`；不是属主角色的成员 | 运行中的服务（单独运行时就是它的登录角色） |
| 外壳登录角色 | 是 | 无 | 外壳；以 `WITH INHERIT FALSE, SET TRUE`（PostgreSQL 16）被授予每个被托管成员的运行期 `PG_USER`（从不授予属主），只能经 `SET LOCAL ROLE` 到达它 |
| `casdoor_rw` 之类 | 是 | 只有它自己的 schema | 某个带外服务 |

这次拆分防的是：运行期 SQL（一次注入、一条 AI 写错的语句）没法 `DROP` 或 `ALTER` 一张表。运行期生命周期引擎提前建分区、装封存守卫、删过期的平台与队列分区，都只经由平台的 `SECURITY DEFINER` 函数（be-protocol 的 `ddl/10-lifecycle-functions.sql`），这些函数由属主在平台迁移里创建（[09-data-lifecycle.md](09-data-lifecycle.md)）。在外壳里，成员之间的隔离是 SDK 的职责：外壳角色可以切换到每个成员的运行期角色，所以只有 store 发 `SET LOCAL ROLE`，而且永远切到该成员自己的 `PG_USER`。

代码里不推导、迁移里也不写任何角色名或 schema 名：它们都来自 `PG_OWNER_USER`、`PG_USER` 和 `PG_SCHEMA`。`be-ops` 生成角色、授权、默认权限（`ALTER DEFAULT PRIVILEGES FOR ROLE <属主> IN SCHEMA <schema> GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES` 以及 `USAGE, SELECT ON SEQUENCES`，授给运行期角色），以及下面这些角色级护栏；它们对任何会话都起兜底作用，包括被遗忘的工具：

```sql
ALTER ROLE <登录角色> SET statement_timeout = '30s';
ALTER ROLE <登录角色> SET idle_in_transaction_session_timeout = '60s';
ALTER ROLE <登录角色> SET lock_timeout = '5s';
```

它们作用在登录的那个角色上。`SET ROLE` 之后，PostgreSQL 不会套用目标角色的设置，所以在外壳里真正生效的只有 [10-local-transactions.md](10-local-transactions.md) 里那些每个事务设定的值。

### 连接池与舱壁

- 每个进程一个池。在外壳里池属于外壳，每个成员经过一个"最多 `PG_POOL_MAX` 条并发连接"的限额去用它。
- 用完了全部预算的成员，最多等 `PG_POOL_ACQUIRE_TIMEOUT`（调用方剩余截止时间更短时以它为准），然后以 `RESOURCE_EXHAUSTED` 加 reason `DB_POOL_EXHAUSTED` 失败（[15-user-api-and-errors.md](15-user-api-and-errors.md)），只影响这一个成员。其他成员不受影响。成员的连接按 `application_name` 计数。
- 服务器以 SQLSTATE `53300`（连接数过多）拒绝新连接时，SDK 以 `UNAVAILABLE` / `DB_TOO_MANY_CONNECTIONS` 失败，不重试。
- 连不上数据库时（连不上、连接断开、SQLSTATE `08` 类、`57P01`、`57P02`、`57P03`），请求以 `UNAVAILABLE` / `DEPENDENCY_UNAVAILABLE` 失败，`metadata.dependency = db`（[15](15-user-api-and-errors.md#reason-目录)）。
- 一个任务同一时刻最多占一条连接；嵌套事务会被拒绝（[10-local-transactions.md](10-local-transactions.md)）。池有上限之后，同时占两条连接正是池把自己饿死的方式。
- `be-ops` 里的连接预算门禁：把部署文件里每个进程的 `PG_POOL_MAX` 加起来，再加上迁移、Casdoor、Keycloak 的预留，总数超过 `max_connections - superuser_reserved_connections` 就失败。

### 连接池代理

- 可选。用的话：只能是 transaction 模式，PgBouncer 要 1.21 及以上并设 `max_prepared_statements > 0`。否则要在每个驱动里关掉语句缓存。
- 运行期代码只取事务级 advisory 锁；有门禁扫描会话级的 `pg_advisory_lock` 调用。
- 迁移以 `PG_OWNER_USER` 登录，经 `PG_MIGRATION_HOST` / `PG_MIGRATION_PORT` 直连 PostgreSQL，因为 golang-migrate 持有一把会话级 advisory 锁。brickKit 给迁移容器的环境和主服务完全相同，所以只有用单独的键，才能让两者指向不同的主机。

## 备选方案

| 引擎 | 长处 | 对我们的短处 |
|---|---|---|
| **PostgreSQL 14+**，含托管服务（RDS、Aurora PostgreSQL、Cloud SQL、AlloyDB、Azure Flexible Server、阿里云 RDS PostgreSQL、PolarDB PostgreSQL 版） | 上面列的机制全都有；生态最全（CloudNativePG、Patroni、pgBackRest） | 单写节点；横向扩展要靠分区、只读副本或分片扩展 |
| MySQL 8、MariaDB、TiDB、OceanBase（MySQL 模式） | 很多运维团队熟悉；TiDB 能横向扩展 | schema 就是 database；没有 `SET LOCAL ROLE`；DDL 不是事务性的；分区表不支持外键 |
| CockroachDB | 分布式、强一致 | 没有 advisory 锁，只有 SERIALIZABLE，分区语义不同；免费的 core 版 2024 年已停止 |
| YugabyteDB（YSQL） | PostgreSQL 兼容度高，Apache-2.0，可多地域 | advisory 锁、部分 DDL 和分区要逐项验证；资源占用重 |
| **Citus 12+**（PostgreSQL 扩展） | 按 schema 分片：每个 schema 整个落在一个 worker 上，这正是 0102 已经强制的约束 | 需要协调节点；部分扩展和 DDL 受限 |
| 人大金仓 KingbaseES（PostgreSQL 模式）、瀚高 HighGo | 在信创名录里；内核源自 PostgreSQL | 版本对应关系、NOINHERIT 语法、扩展都要实测 |
| openGauss、GaussDB、海量 Vastbase | 在信创名录里 | 从 PostgreSQL 9.2 分叉：分区语法、角色、函数都有差异 |
| 每个组件一个数据库 | 隔离最强 | 外壳没法共享连接池；已被 0102 否决 |
| 连接池代理：PgBouncer、PgCat、Supavisor、Odyssey、CloudNativePG 的 pooler | 减少后端连接数 | transaction 模式下不保留会话状态 |

## 为什么选它

- 这里的每一种隔离与协调机制都是 PostgreSQL 原生的：事务级角色切换、声明式分区、`SKIP LOCKED`、事务级 advisory 锁、事务性 DDL。
- 它覆盖的托管服务和源自 PostgreSQL 的国产发行版最广，所以"客户允许用哪种数据库"这个问题，通常在这个家族里就有答案。
- 它的横向扩展路线（Citus 按 schema 分片）不需要改任何组件，因为组件本来就从不碰别人的 schema。
- 机制都放在 SDK 的同一层里，认证一个新引擎就是跑一次套件，而不是逐个审查组件。

## 为什么不选其他

- **MySQL 系**：没有事务级的角色切换，0102 的身份模型就得换一套机制；DDL 不是事务性的，失败的迁移会只执行一半；分区表没有外键；而且每个 repo 层都要移植。
- **CockroachDB**：没有 advisory 锁，只有 SERIALIZABLE（库存余额这类热点行会不停中止），而且是商业许可。
- **openGauss 及其衍生版**：9.2 分叉恰好在 SDK 方言层所在的地方有差异；预计要改 SDK，不作承诺。
- **多方言抽象**：今天只有一种真实的方言；在第二种出现之前写的抽象只能靠猜（[09-ai-development.md](../01-conventions/09-ai-development.md#何时用设计模式)），而且 ORM 已被 [0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md) 排除。
- **每个组件一个数据库**：失去让外壳成为一个进程的共享池，而且以后再改就是数据迁移（[0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)）。

## 什么时候换

- **单库写入成为瓶颈**（实测，且已经做了分区和只读副本之后）：迁到 Citus 按 schema 分片。
- **客户强制要求信创数据库**：对候选库跑数据库套件，看能力矩阵，选通过的那个。
- **某个组件需要 PostgreSQL 没有的存储能力**，或者必须用另一个数据库实例：针对这个组件重新讨论 0102；它通过自己的配置拿到自己的存储，在外壳里拿到自己的池。
- **连接数成为限制**（大量进程连同一个实例）：加一个 transaction 模式的连接池代理。

## 怎么换

- **换成家族内的另一个引擎**：把 `config/vars.yaml` 里共享的 `PG_*` 值指向新实例，对它跑 `make db-init`（be-ops 生成的脚本），再跑数据库套件。组件不改。
- **Citus**：在协调节点和 worker 上装扩展，打开按 schema 分片，让每个组件的 schema 成为分布式 schema，再跑套件。组件不改。
- **连接池代理**：`PG_HOST` / `PG_PORT` 指向代理，`PG_MIGRATION_HOST` / `PG_MIGRATION_PORT` 指向 PostgreSQL 本身。
- **托管服务**：同"家族内的另一个引擎"；用 be-ops 的建角色脚本，不要依赖服务自带的默认超级用户。
- **家族之外**（MySQL、CockroachDB）：这不是一次更换。它意味着每个官方 SDK 里新写一套方言层，再移植每个组件的 repo 层，要当成一个项目来规划。

## 一致性测试

套件 `tools/be-acceptance/conformance/db/`，以一个 DSN 为参数，对某个引擎跑一遍来认证它。分三层：

1. store 套件（`conformance/store`，清单见 [10-local-transactions.md](10-local-transactions.md#一致性测试)）里 SDK 的事务语义；
2. 上面能力清单里每项能力一条探针 SQL；
3. 三个形状不同的组件的 L4 测试：erp/sales、erp/finance、infra/iam-casdoor。

输出是一张"引擎 × 能力"矩阵，结论分三档：可用、降级、不可用。CI 矩阵跑 PostgreSQL 14、16、17，与 store 套件相同（SDK 在 18 上测过之后再加入）；人大金仓、瀚高、YugabyteDB、Citus 各跑一次并记录下来。目前的引擎分级：

| 档 | 引擎 |
|---|---|
| 支持 | PostgreSQL 14 及以上；托管 PostgreSQL 服务 |
| 很可能可用，待实测 | 人大金仓、瀚高；Citus 12+ 作为横向扩展路线 |
| 未验证，预计要改 SDK | openGauss、GaussDB、海量 Vastbase；YugabyteDB |
| 不支持 | CockroachDB；MySQL、OceanBase（MySQL 模式）、达梦 |

要先写红的测试：

- SDK：超出自己 `PG_POOL_MAX` 的成员等待之后拿到 `RESOURCE_EXHAUSTED` / `DB_POOL_EXHAUSTED`，同时另一个成员照常工作；连接池设了上限和生命周期；外壳物理池取成员之和与外壳上限中较小的那个；`PG_MIGRATION_HOST` 优先于 `PG_HOST`；缺 `PG_USER` 或 `PG_SCHEMA` 时报错并点名键，角色绝不从 schema 推出；NOINHERIT 的外壳登录角色照样能跑 outbox 推送和消费者；某成员的 `PG_HOST` 与外壳不同时外壳停止；满负载时 `application_name` 等于某成员 ID 的连接数不超过它的 `PG_POOL_MAX`（`CP-DB-03`）；运行期角色的 `DROP TABLE`、`ALTER TABLE` 失败，而运行期经 `SECURITY DEFINER` 函数建分区成功；连接被拒（`53300`）得到 `UNAVAILABLE` / `DB_TOO_MANY_CONNECTIONS`。
- SDK，先写复现：两个成员在同一条物理连接上，对结构不同的平台表发出完全相同的 SQL 文本，不能报 "cached plan must not change result type"；防住它的就是 `/* be:<schema> */` 前缀（带前缀的 pgx 复现还没跑）。
- be-ops：登录角色带上那三个超时；总数超过 `max_connections` 时连接预算门禁失败，并列出各进程。
- be-acceptance：运行期代码里的会话级 advisory 锁让扫描失败；迁移里出现 `OWNER TO`、`GRANT`、`CREATE SCHEMA`、`SET ROLE`、带限定的名字或角色名时，迁移身份扫描失败；代码从 schema 名推出角色、给 `PG_SCHEMA` 一个字面量默认值、或组件代码里发 `SET ROLE` 时，身份字面量扫描（`identity-literal-scan`）失败。
- infra：Casdoor 的角色不是超级用户。

## 相关决策

- [0102 一个数据库，每个组件一个 schema](../02-decisions/01-architecture/0102-one-schema-per-component.md)：PostgreSQL 方言族，由数据库套件认证；每个组件一个 schema、两个角色（属主 `PG_OWNER_USER`、运行期 `PG_USER`），库身份只来自配置；Citus 按 schema 分片、按成员各开一个池是它重新讨论的条件。
- [0103 每种语言内部一套锁定的技术栈](../02-decisions/01-architecture/0103-locked-stack-per-language.md)：不用 ORM、手写 SQL，所以业务 SQL 留在各组件的 repo 层。
- [0106 基础设施不是组件](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)：数据库服务器是基础设施，不是组件。
- [0502 默认 READ COMMITTED，配一架明确的阶梯](../02-decisions/05-runtime/0502-isolation-and-retry.md)：按事务设定的超时，使角色级设置只作兜底。

## 已知限制

- **只有 PostgreSQL 家族。** 离开它，就要在每个官方 SDK 里新写方言层，并移植每个组件的 repo 层：业务 SQL 大量使用 `ON CONFLICT`、`RETURNING`、`ANY($1)`、interval 和 `JSONB`。
- **信创发行版还没实测**；套件对某个库跑过之前，不承诺它。
- **单写节点。** 横向扩展走 Citus，这条路是设计上留好的，还没测过。
- **所有进程共用一个 `max_connections`。** 预算门禁让总数如实，但没法让服务器变大。
- **共享池上的语句缓存**在成员 SDK 版本不同时，靠的是 `/* be:<schema> */` 前缀，而它在 pgx 上还没复现：复现之前，平台 SQL 写明列名，从不用 `*`。
- **属主凭据也会到达运行中的服务**，不只是迁移容器（brickKit 不做 FR06-013）；SDK 运行期从不读它们。
- **高可用与备份属于运维**（运维文档 `05-operations/` 还没写）。入口：Kubernetes 上用 CloudNativePG（自带 pooler 和按时间点恢复）；单机用 pgBackRest 或 WAL-G。按时间点恢复是"数据被删"时唯一真正的回退手段。
