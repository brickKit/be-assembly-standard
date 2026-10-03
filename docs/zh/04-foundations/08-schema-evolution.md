[English](../../en/04-foundations/08-schema-evolution.md) · [中文](08-schema-evolution.md)

# schema 演进

组件的表怎样随时间变化：迁移工具、一次迁移运行时的护栏、迁移文件里能写什么、同一组件的两个版本怎样共用一个 schema、大回填怎么跑、为什么生产只前滚，以及 3.0.0 那一次性的基线重建。要写一个改动已有表的迁移、要改 SDK 的迁移入口、要提议换一个迁移工具之前，先读这篇。

## 范围

- **覆盖：** 每门语言的迁移工具；每个组件提供的迁移入口；它的超时、重试和阻塞者报告；禁止出现的语句；SDK 在组件迁移之后跑的平台迁移；expand 与 contract，以及文件头标记；并存版本；回填；回滚；基线，包括 3.0.0 的重建。
- **不覆盖：** 契约（API、事件）怎样演进：[0302](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)、[13-event-contracts.md](13-event-contracts.md#演进)、[15-user-api-and-errors.md](15-user-api-and-errors.md)。分区窗口、保留期与冻结数据：[09-data-lifecycle.md](09-data-lifecycle.md)。库身份是谁：[03-database.md](03-database.md)。日常怎么写迁移：[02-backend.md](../01-conventions/02-backend.md#数据库)。

## 选择

- **纯 SQL 文件，每门语言一个工具**：golang-migrate（Go）、yoyo-migrations（Python）、node-pg-migrate（TypeScript）。工具的状态表放在组件自己的 schema 里。
- **迁移用组件自己的镜像跑**，经 `component.yaml` 的 `migration.command`，在服务启动之前、每次 `brickkit up` 都跑（Kubernetes 上是 Deployment 之前的一个 Job）。所以它必须幂等。
- **SDK 的迁移入口加上护栏**：拿锁等待短并且会重试，语句时限长，并报告是谁挡住了它。
- **组件的迁移跑完之后，SDK 跑它的平台迁移**：`besdk_*` 表、当前的分区窗口、事件流和 durable。
- **按 expand 与 contract 演进。** 只增的改动随时可以发；破坏性的改动在文件头声明，等所有旧版本都下线之后才发。
- **列永远不改名，也永远不改含义**，和契约是同一条规则。
- **大回填作为可续跑的 SDK 任务运行**，绝不放在迁移里。
- **生产只前滚。** `down` 文件给开发和测试用。
- **3.0.0 是一次性的破例**：每个组件把已发布的迁移整体换成新基线，因为任何地方都还没有生产数据。此后，已发布的迁移文件重新冻结。

**状态**：已定。护栏、标记、平台迁移和重建的基线随 3.0.0 统一升级落地；contract 迁移的门禁和迁移 lint 后做。今天 golang-migrate 和 yoyo 已在用，测试里每个迁移都连跑两次验证幂等；但迁移没有拿锁超时，没有 expand/contract 规则，回填都是手写的。

## 端口契约

### 迁移入口

| 项 | 契约 |
|---|---|
| 命令 | 镜像的 `migration.command`；官方 SDK 是同一个二进制带子命令，`[./component, migrate, up]` |
| 连接 | 以属主 `PG_OWNER_USER` 登录（密码从 `PG_OWNER_PASSWORD_FILE` 指向的文件读），直连 PostgreSQL：设了 `PG_MIGRATION_HOST` / `PG_MIGRATION_PORT` 就用它们，否则退回 `PG_HOST` / `PG_PORT`，从而绕过 transaction 模式的连接池代理（[03](03-database.md#配置键)）。这是组件自己的可选键，也是 brickKit 推荐的做法，用来代替只给迁移的变量（FR06-013，不做）。运行期角色 `PG_USER` 只有 DML，执行不了 DDL（[03](03-database.md#角色)） |
| 会话参数 | `lock_timeout = 5s`、`statement_timeout = 15min`。迁移连接是一个专用、不进池的会话，用完即关：会话级设置、工具的会话级 `search_path` 和它的会话级 advisory 锁都允许用在它上面，这是"不在会话级设置任何东西"唯一的例外（[03](03-database.md#每个事务做什么)）。迁移锁按 schema 区分：两个组件同时迁移同一个库，都能成功 |
| 等锁 | 拿锁超时就退避重试三次；仍失败时，点名是哪条迁移、等的是什么锁，以及阻塞者的 pid 和它 SQL 的前 200 个字符 |
| 状态表 | 在组件的 schema 里；表名由工具决定（`schema_migrations_<PG_SCHEMA>`、`_yoyo_*` 那几张表、`pgmigrations_<PG_SCHEMA>`，be-protocol P11 列出）。官方 SDK 的状态表不受下文 `lifecycle.yaml` 声明规则的约束；不是官方 SDK 的运行时，把它所用工具的状态表声明为 `class: platform` |
| 库比镜像新 | 迁移入口记一条警告、以 0 退出，这样 brickKit 的多版本串联（每次 `up` 先跑低版本、再跑高版本）能工作；**服务**入口拒绝启动 |
| 退出码 | 成功为 0，任何失败为非 0 |

### 迁移文件里能写什么

- **禁止**：`OWNER TO`、`GRANT`、`REVOKE`、`CREATE SCHEMA`、`CREATE ROLE`、`ALTER ROLE`、任何 `SET`、带 schema 限定的名字、任何角色或 schema 名字面量，以及带日期字面量的子分区。名字靠 SDK 设好的 `search_path` 解析。计划中的 `migration-identity-scan` 对其中每一项报错。
- **从 3.0.0 起必须的形状**：自有主键是 `uuid`（UUIDv7，由应用生成，[04](04-identifiers-and-numbering.md)），例外是必须严格单调的计数器（`BIGINT GENERATED ALWAYS AS IDENTITY`）和以标准代码为键的参考表；金额、单价、汇率列用 [06](06-money-quantity-units.md) 的精度，每个金额都和币种成对；交易单据带 `legal_entity_id`（[07](07-tenancy.md)）；业务日期是 `DATE`（[05](05-time-and-calendars.md)）。`BIGSERIAL` 主键和 `NUMERIC(18,2)` 金额列被同一条扫描拦下。
- **分区表**：迁移只建父表（`CREATE TABLE … PARTITION BY RANGE (…)`）；分区由 SDK 按 `lifecycle.yaml` 建（[09](09-data-lifecycle.md)）。
- **不碰平台表**：组件从不建、也从不碰任何 `besdk_*` 表（计划中的 `platform-table-scan`）。
- **每张表都有声明**，在 `migrations/lifecycle.yaml` 里（计划中的 `lifecycle-scan`）；`besdk_*` 表和官方迁移状态表除外。
- **不写测试账号**（[0303](../02-decisions/03-contracts-and-data/0303-no-test-accounts-in-migrations.md)）。

### 平台迁移

SDK 在组件的迁移之后立即运行，在同一个迁移步骤里、以属主身份，按下面的顺序，每一步都幂等：

1. 按协议 `ddl/` 里的参考 DDL 建或升级 `besdk_*` 表和平台函数（运行期角色借以维护分区的那些 `SECURITY DEFINER` 函数，[09](09-data-lifecycle.md)），把级别记进 `besdk_platform_version`（[02](02-languages-and-component-protocol.md)）；
2. 按 `lifecycle.yaml` 建出当前分区窗口，组件装好的当天就能写入；
3. 确保事件流和本组件的 durable 消费者存在（[12](12-event-bus.md)）。

平台表同样按 expand 与 contract 演进：同一个组件可能同时跑在两个 SDK 版本上——单跑的和外壳里的并排——对着同一个 schema（[01](01-ports-and-adapters.md#版本)）。

### expand 与 contract

| 改动 | 类别 | 怎么发 |
|---|---|---|
| 加表 | expand | 随时 |
| 加可空列，或带常量默认值的列 | expand | 随时 |
| 加索引 | expand | `CREATE INDEX CONCURRENTLY`，单独一个文件，文件头标 `-- be:no-transaction` |
| 加约束 | expand | `ADD CONSTRAINT … NOT VALID`；`VALIDATE CONSTRAINT` 放在之后的文件里 |
| 把列改成 `NOT NULL` | 先 expand，再 contract | 先加成可空；回填；在 contract 文件里设 `NOT NULL` |
| 删列或删表；改类型 | contract | 文件头 `-- be:contract after=<版本>` |
| 改列名；改列的含义 | 永远不行 | 加一个新列，把读写都迁过去，再用 contract 删掉旧列 |

contract 文件以标记开头，写明仍然需要旧形状的最后一个版本：

```sql
-- be:contract after=3.2.0
ALTER TABLE sales_orders DROP COLUMN legacy_note;
```

```sql
-- be:no-transaction
CREATE INDEX CONCURRENTLY sales_orders_customer_idx ON sales_orders (customer_id);
```

**规则**：只有当不再有任何不高于 `after` 的版本对着这个 schema 运行时，contract 迁移才能发。计划中的 `contract-migration-scan` 读 `brickkit.yaml`（并存的版本列在那里），只要其中有一个不高于 `after`，就报错。

### 并存版本

同一个组件的两个版本，会在三种情况下碰上同一个 schema：

| 什么时候 | 谁跑在更新的 schema 上 |
|---|---|
| brickKit 的多版本串联 | 每次 `up` 两个版本都迁移，低版本先；旧入口发现库更新，什么也不做 |
| Kubernetes 上的滚动更新 | 迁移 Job 跑完之后，旧 Pod 继续服务 |
| 外壳和单跑并排 | 同一个组件跑在两个 SDK 版本上，共用平台表 |

所以第 N 版的代码必须能在第 N+1 版的 schema 上正确运行。expand 保证这一点；contract 要等第 N 版下线。

### 回填

- **声明成一个任务**：名字、每批执行的语句（或函数）、游标列。它作为 `singleton` 任务运行（[19](19-background-jobs.md)），每批一个事务，进度记在平台表 `besdk_backfill (name PRIMARY KEY, cursor, done, updated_at)`。崩溃后从游标续跑；两个副本绝不会跑两遍；`done` 之后永不再跑。
- **回填完成之前，读路径兼容新旧两种形状**；之后的那一版再发 contract 迁移。
- **迁移里只回填有界的参考数据。** 计划中的检查按 `lifecycle.yaml` 里的类别区分有界表和大表。

### 回滚

- **生产只前滚。** 修复就是一条新迁移。
- **`down` 文件** 服务于 `make db-reset`，以及 L4 的规则：每个迁移至少真跑一次 down 再 up（[06-testing.md](../01-conventions/06-testing.md#l4-集成测试)）。
- **应用回滚**到上一版镜像是可行的，因为上一版能在 expand 之后的 schema 上运行。
- **数据被误删或损坏**，靠时间点恢复（PITR）找回，这是运维流程（运维文档还没写）。

### 基线与 3.0.0 的重建

- **平时，已发布的迁移文件是冻结的**：除了没有任何效果的修改，一律不改；不压缩；新安装从第一个文件跑起。
- **3.0.0，仅此一次**：每个组件删掉自己的迁移，按上面的形状写一份新的 `0001_init`，不含平台表；mdm/org 和 mdm/currency 直接从这样的基线起步。演示库和测试库重建（各组件 `make db-reset`、`make test-db-init`）并重新播种。
- **判据**写进一条决策：任何一处安装都没有生产数据；只发生一次；以后同样的情况要另起一条决策。

## 备选方案

| 工具或方法 | 做什么 | 长处 | 短处 |
|---|---|---|---|
| golang-migrate、yoyo、node-pg-migrate（选定） | 有序的纯 SQL 文件，一张状态表 | 简单；人或 AI 都能评审 SQL | 没有内置的安全 lint；不支持 expand/contract |
| goose | SQL 或 Go 函数迁移，`-- +goose NO TRANSACTION` | `CONCURRENTLY` 处理得干净 | Go 函数会让迁移变成代码 |
| Atlas | 声明式 schema 加差异计算，迁移 lint | 能查出破坏性改动 | 生成的 DDL 只能事后评审；部分功能收费 |
| Flyway、Liquibase | 版本化 SQL（Flyway）或 changeset（Liquibase） | 成熟，支持很多数据库 | 每个迁移镜像里都要一个 JVM；Liquibase 的 changeset 不是纯 SQL |
| pgroll、Reshape | 经版本化的 schema 和视图做零停机的 expand/contract | 把新旧形状并存的那段时间自动化 | 要建 schema、切 `search_path`，和每个组件一个 schema、每个事务设 `search_path` 冲突 |
| Squawk | 对 PostgreSQL 迁移做不安全操作的 lint | 能抓出不带默认值的 `NOT NULL`、非并发建索引、没设拿锁超时 | 只是 lint，用来补充工具 |
| expand/contract（并行变更） | 先加，迁移读写，以后再删 | 主流做法（Stripe、GitHub） | 要纪律，也要门禁 |

## 为什么选它

- **纯 SQL 谁都能读**，在 AI 写、人评审的时候这一点最重要；每门语言一个工具，保持只有一种写法（[0103](../02-decisions/01-architecture/0103-locked-stack-per-language.md)）。
- **并存版本是 brickKit 的原生能力**，所以"旧版本下线没有"这一关就该放在 brickKit 列出版本的地方：`brickkit.yaml`。
- **拿锁护栏防住了最典型的事故**：一个本身很快的 `ALTER TABLE` 为了拿排他锁排在一个长事务后面，后面的所有查询又都排在它后面。
- **回填作为任务**让迁移保持很短。这很要紧，因为 Kubernetes 上的迁移 Job 失败一次（`backoffLimit: 0`）就会让部署停下，直到下一次 `up`。

## 为什么不选其他

- **goose**：Go 函数迁移打破了"迁移是纯 SQL"，而且在 Python 和 TypeScript 里不存在；我们借鉴的是它的不开事务标记。
- **Atlas**：声明式差异产出的是没有人亲手写过的 DDL；lint 的思路改用 Squawk 一类检查来吸收。
- **Flyway 和 Liquibase**：在每个 Go、Python、TypeScript 的迁移镜像里塞一个 JVM，换不来纯 SQL 工具缺的任何能力。
- **pgroll 和 Reshape**：版本化的 schema 打破了每个组件一个 schema（[0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)）和 SDK 的 `SET LOCAL search_path`。

## 什么时候换

- **评审漏掉了不安全的 DDL**，并且有事故记录：在工具旁边加一个声明式 lint（Atlas lint 或类似的），而不是替换工具。
- **某个工具没人维护了，或挡住了需要的功能**：改 0103 里这门语言的那一格，这门语言的所有组件一起改。
- **某张表大到 expand/contract 也撑不住**（即使并发执行，重写也要几个小时）：评估版本化 schema 的工具，这要先修订 0102。

## 怎么换

- **同一门语言里换工具**：发一个 SDK 版本。组件的文件仍是纯 SQL；SDK 把旧状态表里的版本一次性抄进新工具的表；0103 的那一格随之改。
- **打开 contract 门禁或 lint**：改 `make gates`；组件在写 contract 迁移之前什么都不用改。
- 这不是一个带适配器的端口：每门语言只有一个工具。

## 一致性测试

- **组件协议套件**（[02](02-languages-and-component-protocol.md)）：迁移连跑两次都以 0 退出；在新库上迁移一结束组件就能写入；每张 `besdk_*` 表都与参考 DDL 逐列一致；随机 schema 和角色下，所有表的属主都是 `PG_OWNER_USER`，`PG_USER` 对每张表都有 `SELECT, INSERT, UPDATE, DELETE` 且建不了表，schema 之外没有任何对象。
- **SDK，先写红测试**：被长事务挡住的迁移在 `lock_timeout` 之后重试，最终失败并点名阻塞者；带 `CREATE INDEX CONCURRENTLY` 的 `-- be:no-transaction` 文件执行成功（先在每个工具里做最小复现：golang-migrate 把多语句文件当作一个隐式事务执行）；旧版本在新 schema 上跑 `up` 什么也不做；回填崩溃后续跑，两个副本下只跑一次，`done` 之后不再运行。
- **be-acceptance**：`migration-identity-scan` 对每一条禁止的语句、对 `BIGSERIAL` 主键、对 `NUMERIC(18,2)` 金额报错；以后，`contract-migration-scan` 在有不高于 `after` 的旧版本并存时报错、旧版本退役后放行，lint 对不带默认值的 `NOT NULL` 报错。
- **组件 L4**：上一个发布版本的镜像，能成功写入本版本 expand 迁移之后的 schema。

## 相关决策

- [0305 3.0.0 重建可以替换已发布的迁移，仅此一次，不做兼容层](../02-decisions/03-contracts-and-data/0305-one-shot-baseline-rebuild-for-3-0-0.md)：基线重建及其判据。
- [0306 自有主键用 UUIDv7；单据号由 SDK 分配](../02-decisions/03-contracts-and-data/0306-uuidv7-own-keys.md)：每份新基线采用的主键形状，以及它的两个例外。
- [0302 契约只做加法](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)：schema 遵守同一条规则；contract 迁移是受控的例外。
- [0102 一个数据库，每个组件一个 schema](../02-decisions/01-architecture/0102-one-schema-per-component.md)：状态表放在组件的 schema 里；版本化 schema 的工具被排除。
- [0103 每种语言内部一套锁定的技术栈](../02-decisions/01-architecture/0103-locked-stack-per-language.md)：迁移工具是每门语言的一格，TypeScript 用 node-pg-migrate。
- [0508 后台工作只经 SDK 的 Jobs](../02-decisions/05-runtime/0508-background-work-only-through-jobs.md)：回填是任务。
- [0303 测试账号不写进迁移](../02-decisions/03-contracts-and-data/0303-no-test-accounts-in-migrations.md)。
- 计划中、尚未编号："schema 按 expand 与 contract 演进，由 `brickkit.yaml` 里的并存版本把关；生产只前滚"。

## 已知限制

- **contract 门禁和 lint 还没做。** 在那之前，由评审人核对 contract 迁移的 `after` 版本在所有地方都已退役。
- **各工具下的 `CONCURRENTLY` 还没验证**，要等最小复现跑完。
- **迁移里不做长活**：Kubernetes 上迁移 Job 失败一次，部署就停到下一次 `up`。
- **只前滚意味着数据错误要靠时间点恢复**；`down` 文件永远不在生产上跑。
- **3.0.0 的重建丢掉了迁移历史**：2.x 的库不能原地升级到 3.0.0，只能重建。
