[English](../../en/04-foundations/09-data-lifecycle.md) · [中文](09-data-lifecycle.md)

# 数据生命周期

组件的数据行怎样变老：从热，到封存只读，到冻结成对象存储里的开放格式文件，到法律允许时销毁。还有法律保全和删除请求怎样横穿这一切，以及让同一批组件既能不要冷层、也能用 Parquet 文件、以后还能接湖仓的那几个端口。要加表、改保留期、写按时间范围查询的列表、改 SDK 的生命周期引擎之前，先读这篇。

## 范围

- **覆盖：** 各层与横切状态；八个表类别；生命周期契约 `lifecycle.yaml` v1 及其部署覆盖；单元与状态机；SDK 给的保证；读路径（默认窗口、`RANGE_COLD`、定位、导出、解冻）；`/_lifecycle/*` 资源契约；跨层擦除；冷层格式；分区窗口；平台表及其保留期；生命周期的端口与适配器；与备份的协同。
- **不覆盖：** 对象存储本身、bucket 与凭据（[22-object-storage.md](22-object-storage.md)）；事件回放（[12-event-bus.md](12-event-bus.md#回放)）；迁移（[08-schema-evolution.md](08-schema-evolution.md)）；会计日历（[05-time-and-calendars.md](05-time-and-calendars.md)）；备份与恢复流程（运维文档，还没写）。

## 选择

- **在同一张表里分层。** 热行和温行都挂在同一个原生分区父表上。温就是已封存：只读，单元摘要链进一条摘要链。没有 `<schema>_archive`，也没有 schema 之间的路由。
- **冷数据是组件自有的开放格式**：Parquet 文件加一份自描述清单，放在组件自己的 bucket 里，用组件自己的凭据（[22](22-object-storage.md)）。可以经适配器查询、导出，或解冻回库。
- **销毁**只在法定下限过了之后发生。按类别，要么自动执行，要么先审查（经工作流待办审批），销毁清册永久保存。
- **两个状态横穿各层**：**法律保全**挡住销毁和擦除；**限制处理**保留法律要求保留的行，同时不再把它们用于任何其他用途（《个人信息保护法》第 47 条、GDPR 第 18 条）。
- **每张表都有声明**，写在 `migrations/lifecycle.yaml` 里，归入八个类别之一。部署方可以把保留期调长、把冷冻推迟，不能低于组件的声明。
- **每门官方 SDK 一个引擎。** 纯函数的规划器产出动作，执行器去执行。它作为 `singleton` 任务运行（[19](19-background-jobs.md)），每一步取一把事务级 advisory 锁（[10](10-local-transactions.md)）；运行期角色没有 DDL 权限（[03](03-database.md#角色)），所以它运行期的 DDL（提前建分区、装封存守卫、删过期的平台与队列分区）只经由属主在平台迁移里创建的 `SECURITY DEFINER` 函数。并发摘下已冻结的业务单元，在迁移步骤里以属主身份、在它的专用连接上执行。
- **基础设施产品放在 SDK 端口后面**，用一个配置值选：`Dialect`、`ColdStore`、`ColdQuery`、`DatasetPublisher`、`PiiProtector`。组件从不点名适配器。
- **分区由声明产生**：迁移里没有日期字面量，迁移跑完的当天窗口就已存在。
- **治理是一个普通组件** `infra/data-governance`：保全、数据主体请求、销毁审批、合规报表。没有组件依赖它；没装它时，每个组件的 `/_lifecycle/*` 端点照样能下保全、做擦除。
- **用户选定的默认口径**：保留期由组件作者按法规给出，部署方可以调长，订单作为涉税资料保留 10 年。冷数据先提供"导出或申请解冻"，列表里直接翻到冷数据以后再做。非财务数据到期后审查销毁，财务资料按会计档案的规定处理。自然人客户的数据在保留期内限制处理，到期后匿名化。电子会计档案归档包排进 erp/finance 的路线图。

**状态**：已定。整份契约在阶段 0 随 3.0.0 统一升级一次定全：`lifecycle.yaml` v1、平台表、全部 `/_lifecycle/*` 端点（未实现的答 `501`）、`RANGE_COLD`、`DATA_LIFECYCLE`、列表字段 `include_cold`。阶段 0 的引擎只实现热、温两层，冷层适配器都是 `none`。后面的阶段只加适配器，从不改契约：阶段 1 是 `s3-parquet`，带冻结、校验、解冻、导出和销毁审查；阶段 2 是 `scan`、治理组件和 `watermark` 数据集；阶段 3 按需求做 `iceberg`、`trino`、`debezium` 和 `crypto-shred`。今天十二个组件各带一份没有锁的分区维护代码，初始分区是迁移里写死的日期，`<schema>_archive` 的约定还在，outbox 和 inbox 表没有契约规定的过期。

## 端口契约

### 层与状态

| 层或状态 | 行在哪里 | 读 | 写 |
|---|---|---|---|
| 热 | 默认窗口内、挂载着的分区 | 默认读 | 正常 |
| 温（已封存） | 挂载着的分区，触发器封存，摘要入链 | 按需读（默认窗口之外的范围） | 拒绝：`FAILED_PRECONDITION` / `UNIT_SEALED` |
| 冷 | 对象存储里的 Parquet 加清单；库里只留单元目录 | `RANGE_COLD`，或冷查询适配器、导出、解冻 | 无 |
| 已销毁 | 没了；清册条目留下 | — | — |
| 法律保全（横切） | 不变 | 不变 | 挡住销毁和擦除 |
| 限制处理（横切） | 不变 | 只有业务界面和审计可见；不进数据集和分析 | — |

### 表类别

| 类别 | 是什么 | 分区 | 封存 | 冷层 | 到期 | 擦除默认 |
|---|---|---|---|---|---|---|
| `master` | 可变的主数据，量有上界 | 否 | 否 | 否 | 保留 | 匿名化个人信息列 |
| `reference` | 配置、字典、模板 | 否 | 否 | 否 | 保留 | 无：不许有个人信息列（检查） |
| `document` | 有状态机的业务单据 | 按创建时间，或行单元 | 关闭后满 N 个月 | 可选 | 按保留口径 | 按列：限制处理或匿名化 |
| `ledger` | 只追加的账簿 | 按时间或期间 | 立即，或按业务信号（期间锁定） | 可选，要先有结转 | 法定下限，审查后销毁 | **不许有个人信息列**，只存主体的不透明 id（检查） |
| `audit` | 谁在何时做了什么 | 按时间 | 立即 | 可选 | 至少 6 个月；默认 3 年 | 操作者 id 保留（限制处理） |
| `queue` | 有未结束状态的工作项 | 按时间 | 否 | 永不 | 删除，但有未结束行的分区不删 | 删除 |
| `snapshot` | 别人数据的本地副本，可重建 | 任意 | 否 | 永不 | 随时可删 | 删除行 |
| `platform` | SDK 自己的表 | SDK 定 | — | 永不 | SDK 定 | SDK 定 |

不变式在加载声明时校验（违反就启动失败并点名）：`ledger` 和 `audit` 的行从分区建好的那一刻起就受封存触发器保护；`ledger` 上标了个人信息的列一律报错；`queue` 不能有冷层，`snapshot` 不能有保留下限；有冷层的表，所有 `NUMERIC` 列都要带精度；可擦除的冷表不能用 WORM 存储。

### `lifecycle.yaml` v1

放在迁移旁边、随镜像发布；SDK 在运行期读它，be-ops 和门禁在组装期读同一份。

```yaml
lifecycle: v1
tenant_key: none
tables:
  sales_orders:
    class: document
    partition: {by: created_at, grain: month, ahead: 3}
    closed: {column: status, in: [COMPLETED, CANCELLED, CLOSED], at: updated_at}
    tiers: {hot: 90d, seal: 18mo after closed, cold: 5y after closed}
    retention: {min: 10y after closed, basis: "涉税资料，10 年", end: review}
    erasure: {subject: customer, key: customer_id, columns: {customer_name: restrict}}
    dataset: {publish: true, exclude: [suspended_reason]}
  sales_order_items: {follows: sales_orders}
  customer_snapshots: {class: snapshot, erasure: {subject: customer, key: customer_id, action: delete}}
```

| 字段 | 取值 |
|---|---|
| `class` | 八类之一；决定默认值和不变式 |
| `partition` | `{by, grain: week\|month\|year, ahead}` 或 `{by, kind: list, opened_by: command}`；不写 = 不分区 |
| `closed` | `{column, in: [...], at: <列>}`，结构化而不是 SQL，所以每门 SDK 和每个冷层适配器都能求值 |
| `tiers.hot` / `seal` / `cold` | 时长或 `none` / `immediate`、`on_signal`、`<n> after <锚点>`、`never` / `<n> after <锚点>`、`never` |
| `retention` | `min: <n> after <锚点>` 或 `forever`；`basis`（文本，写进销毁清册）；`end: keep\|destroy\|review` |
| 锚点 | `created`、`closed`、`sealed`、`fiscal_year_end`（由组件提供；erp/finance 取自它的会计年度，其余组件按自然年） |
| `erasure` | `{subject, key, columns: {<列>: delete\|anonymize\|restrict}}` 或 `{subject, key, action: delete}` |
| `checkpoint` | 单元冻结之前必须已经写好结转行的表（erp/finance 的 `account_period_balances`） |
| `guard` | `{blocked_by: <名字>}`，组件实现的命名检查，在封存或销毁之前调用 |
| `follows` | 与指定的表同边界、同单元 |
| `dataset` | `{publish, exclude, pseudonymize}` |
| `tenant_key` | 列名，或 `none`（[07](07-tenancy.md)） |

**部署覆盖**：一个配置键 `DATA_LIFECYCLE`，在 `config/vars.yaml` 里写一个 YAML 或 JSON 值，各组件可以在自己的配置文件里再加：

```yaml
DATA_LIFECYCLE: |
  mode: on                 # on | dry-run | off
  cold_store: s3-parquet   # none | s3-parquet | iceberg
  cold_query: scan         # none | scan | trino
  publisher: none          # none | watermark | debezium
  pii: plain               # plain | crypto-shred
  tables: {sales_orders: {retention: {min: 15y after closed}}}
```

覆盖值低于声明的下限，启动失败；写了当前 SDK 版本没实现的适配器名，启动失败并提示"本 SDK 版本不支持"。对象存储用 `S3_URL` 和每个组件一套的凭据 `S3_ACCESS_KEY_ID_FILE` / `S3_SECRET_ACCESS_KEY_FILE`，只授权到组件自己的 bucket；只有选了 `trino` 才需要 `LAKE_QUERY_URL`。一个键装一整块结构，违背了 brickKit 对配置设计的建议；这是有意的例外，因为平铺的键表达不了按表覆盖。

### 单元与状态机

**单元**是一个分区（连同它的 `follows` 分区）；不分区的表，单元是锚点落在同一个月的那些行。每一步是一个事务，持一把步骤锁并设 `lock_timeout`，崩溃后从 `besdk_lifecycle_units.state` 接着做。

1. **提前建窗口**：按边界建分区，从不按名字（命名不同的已有分区会被接管），`follows` 的表在同一个事务里建；迁移时建当前窗口，运行期经 `besdk_ensure_range_partition` / `besdk_ensure_list_partition` 补足 `ahead`。没有 DEFAULT 分区。
2. **封存**：锁住分区，挡写不挡读；校验每一行都已关闭，否则把单元标成 `BLOCKED`，记下原因和前 100 个 id（指标 `be_lifecycle_blocked{table,reason}`）；调用命名检查；经 `besdk_seal_table` 装上封存触发器（行级 `UPDATE`/`DELETE`、语句级 `TRUNCATE`；用触发器，是因为经父表访问时不检查分区上的权限）；把单元摘要链入：`chain_n = SHA-256(chain_{n-1} ‖ unit_digest_n)`。`on_signal` 在业务事务里封存（erp/finance 锁定期间时）。
3. **导出**仍然挂载着的已封存单元，写成 Parquet；4. **校验**：把对象读回来，重算摘要；5. **切换读路由**：在一个事务里把单元标成 `COLD_PENDING_DROP`，此后读就得到 `RANGE_COLD`，一行也不会漏。
6. **摘下并删除**：在迁移步骤里、以属主身份、在它那条从不进池的专用连接上执行 `ALTER TABLE … DETACH PARTITION … CONCURRENTLY`（这条语句不能在函数或事务块里执行；父表只需要 `SHARE UPDATE EXCLUSIVE`），再 `DROP` 已经独立的表。行单元按每批 5,000 行删除。状态变为 `COLD`。
7. **解冻**：重建表，按列名灌入（文件里有、表里已删的列忽略，表里新增的列取默认值），加上与边界一致的 `CHECK`，重新核对摘要，封存，挂载；状态 `THAWED until <时间>`；到期后重新冻结，不用再导出。
8. **销毁**：只针对已过 `retention.min`、没有保全、命名检查通过的单元。`end: destroy` 直接执行；`end: review` 生成一份销毁清单等待审批。每一次销毁都写进 `besdk_lifecycle_log`，永久保存。
9. **过期**（`queue`、`platform`）：分区里没有未结束的行之后删除，不经冷层，运行期经 `besdk_drop_partition` 执行（在很短的 `lock_timeout` 下普通 `DETACH`，再 `DROP`）。

### 保证

| # | SDK 保证 |
|---|---|
| G1 | 不论哪天跑迁移，组件当天就能写入；窗口始终覆盖 `ahead` |
| G2 | 同一个 schema 的同一步，同一时刻只有一个执行者；不同 schema 互不阻塞；热路径上没有排队等锁的 DDL |
| G3 | 不到 `retention.min` 不删任何行 |
| G4 | `document`、`ledger`、`audit` 的行，没有校验过的冷副本就绝不离开数据库；`cold_store: none` 时它们留在温层 |
| G5 | 已封存的单元拒绝 `UPDATE`、`DELETE`、`TRUNCATE`（`UNIT_SEALED`） |
| G6 | 摘要链随时可以校验；已封存单元的任何改动都会被发现 |
| G7 | 读一个时间范围，要么拿到全部，要么得到 `RANGE_COLD`；绝不静默截断 |
| G8 | 冷层读取套用与热层相同的数据范围谓词；表达不了的适配器直接拒绝 |
| G9 | 保全中的数据绝不被销毁或擦除 |
| G10 | 擦除作用于每一层、每个数据集和之后的每次解冻，留下回执，并在时间点恢复之后重放 |
| G11 | 每个动作都记日志，并作为事件发布 |
| G12 | 每门官方 SDK 的规划器从共享向量得出完全相同的动作 |

### 读

- **默认窗口**：不带范围的列表读 `hot` 窗口；`master` 和 `reference` 没有窗口。
- **`RANGE_COLD`**：`FAILED_PRECONDITION`，HTTP 400，reason `RANGE_COLD`，`metadata` 里有 `online_from`、`cold_ranges`、`thaw_allowed`、`export_allowed`（[15](15-user-api-and-errors.md)）。每个列表请求加一个可选字段 `include_cold`（默认 false），在 3.0.0 的契约里一次加齐；有冷查询适配器时，`include_cold: true` 会接着读进冷数据，游标里记着层级，所以翻页从热层过渡到冷层时调用方无感。
- **按 id 读**：BatchGet 照旧读表。要区分"不存在"和"已冻结"时，SDK 从 UUIDv7 的时间位算出所在单元（[04](04-identifiers-and-numbering.md)），不需要冷 id 索引。

### 资源契约

每个有库的组件都挂出 `/{domain}/{name}/_lifecycle/*`（OpenAPI 在 `be-protocol` 里，gRPC 是 `be.lifecycle.v1`）：`GET units?table=`、`POST units/{table}/{unit}:thaw {days}`、`POST exports {table, from, to, filter, format: parquet|csv}`（异步；结果是组件 `exports/` 前缀下的短期预签名 URL）、`GET verify`、`holds`、`erasures`、`destructions`。还没实现的端点答 `501` `CAPABILITY_UNAVAILABLE`。权限键由 be-ops 生成：`<id>.lifecycle.read`（导出、看单元）、`<id>.lifecycle.thaw`、`<id>.lifecycle.admin`（保全、擦除、销毁）。

### 冷层格式

- 布局，在组件自己的 bucket 里（[22](22-object-storage.md#键布局)）：`cold/<table>/v<数据集版本>/unit=<YYYY-MM>/tenant=<t>/part-NNNN.parquet` 和 `cold/<table>/_manifests/<unit>.json`（行数、摘要、结构版本、依据）。行组约 128 MB。对象键里带内容摘要，所以重复导出是幂等覆盖。
- **规范摘要**：每个值取 PostgreSQL 的文本输出形式（null 记为 `\N`），字段用 `0x1F` 分隔，行用 `0x1E` 分隔，行按主键排序，每个单元做一次 SHA-256。导出时从 PostgreSQL 算，校验时从 Parquet 算，解冻时再从库里算，三者必须相同。任何第三方工具都能重算它。

### 擦除

- **主体**登记在 `registry/data-subjects.tsv`（只追加）：`customer`、`contact`、`user`、`supplier`、`employee`，每个写明拥有它的组件。
- **流程**：`infra.governance.erasure.requested.v1 {request_id, subject, subject_id}`（或组件自己的端点）→ 每个声明了该主体的组件，在一个事务里按表按列执行 `delete`、`anonymize`（同一主体用同一个稳定假名，报表仍能分组）或 `restrict` → 回执 `<domain>.<name>.lifecycle.erasure_completed.v1 {request_id, tables: [{table, action, rows, basis}]}`。
- **冷层**：`s3-parquet` 重写受影响的文件，并出一份新清单；`iceberg` 写删除文件。擦除账本 `besdk_erasures` 只存不透明 id，并以只追加的方式镜像到 `_erasures/` 前缀。
- **已知滞后**：事件里的个人信息最长留存 outbox 的 14 天加流的 7 天；死信保留 30 天，不会被改写。`crypto-shred`（阶段 3）通过删除每个主体的密钥消除这段滞后。

### 分区窗口与平台表

- 边界锚定 UTC（周从周一 00:00 开始，月从 1 日开始）；命名 `<表>_YYYY_MM_DD`；判断是否存在时从目录读边界；部分重叠就跳过并警告。
- erp/finance 按会计期间的 list 分区，由它的"开会计年度"命令经 SDK 建出，绝不靠每年一份迁移（[05](05-time-and-calendars.md)）。
- 平台表的保留：`besdk_outbox` 按周分区，全部行发布后 14 天删除分区；`besdk_event_cursor` 和 `besdk_idempotency` 删除 30 天以前的行；`besdk_lifecycle_log` 永久保存。
- 生命周期的表：`besdk_lifecycle_units`（单元、边界、状态、行数、最小和最大 id、单元摘要与链摘要、清单、各时间点、阻塞原因）、`besdk_lifecycle_log`（只追加，已封存）、`besdk_holds`、`besdk_erasures`、`besdk_exports`；参考 DDL 在 `be-protocol` 里。

### 端口与适配器

| 端口 | 适配器 | 阶段 | 适合 |
|---|---|---|---|
| `Dialect` | `pg-native` | 0 | PostgreSQL 14+、托管 PostgreSQL、兼容引擎（[03](03-database.md)） |
| | `opengauss`、`kingbase` | 按需 | 信创交付，实测之后 |
| `ColdStore` | `none` | 0 | 没有对象存储的小客户；也证明降级路径 |
| | `s3-parquet` | 1 | 默认 |
| | `iceberg` | 3 | 已有湖仓的客户，或要零拷贝给 Snowflake、Databricks、Doris；数据文件与 `s3-parquet` 相同 |
| `ColdQuery` | `none` | 0 | 冷数据只走导出和解冻 |
| | `scan` | 2 | 默认：进程内读 Parquet，按行组裁剪，只读组件自己的 bucket |
| | `trino` | 3 | 历史查询多、要聚合 |
| `DatasetPublisher` | `none`、`watermark`、`debezium` | 0、2、3 | 分析（`ana/*`）读发布的数据集，从不读业务 schema |
| `PiiProtector` | `plain`、`crypto-shred` | 0、3 | 个人信息多的组件，例如以后的 `hrm/*` |

生命周期事件经 outbox 发出：`<domain>.<name>.lifecycle.sealed|frozen|thawed|destroyed|erasure_completed.v1`。

### 备份

时间点恢复之后，引擎做一次对账：清单对得上的单元当作已校验，不再重复导出；找不到对应单元的对象标为孤儿，超过恢复窗口后删除；库里缺失的擦除从 `_erasures/` 镜像重放。对象存储的保留期必须长于恢复窗口。

## 备选方案

| 方案 | 长处 | 短处 |
|---|---|---|
| 同一张表里用原生分区，加开放格式的冷层（选定） | 一个 schema、一条读路径；任何引擎都能读冷层；换库只搬热温两层 | 引擎、状态机和适配器都要自己写 |
| 每个组件一个归档 schema（旧约定） | 冷行仍能用 SQL 查 | 两个 schema、DDL 漂移、要路由、不省空间 |
| pg_partman | 成熟；托管 PostgreSQL 上有 | 配置在组件 schema 之外；高权限的后台进程；它的保留逻辑绕开我们的守卫 |
| TimescaleDB | 只追加的表压缩 90% 以上；连续聚合 | TSL 许可；托管服务少；转换是一次迁移；压缩块擦除代价高 |
| Citus columnar | 温层压缩；按 schema 分片与每个组件一个 schema 对得上 | 依赖扩展；只追加 |
| 只用 Apache Iceberg 作冷层格式 | 开放表格式的事实标准；行级删除便宜 | 要目录服务；Go 的写入实现还很新 |
| PostgreSQL 湖扩展（pg_duckdb、pg_lake、parquet_s3_fdw） | 一条 SQL 横跨冷热 | 高权限扩展，托管服务很少支持；隔离交给了扩展 |
| 全表 CDC 进分析库 | 实时，能抓到删除 | 物理上就是读别的组件的 schema；没有契约 |
| 软删除或 `active` 标记（Odoo） | 极简单 | 只是回收站，不是生命周期；没有法定保留 |

主流产品塑造了这份契约：SAP 的归档对象、可归档性检查、驻留期与保留期之分和法律案件；SAP Data Aging 的"默认只读当前"；Salesforce Archive 的可检索、可恢复归档；ERPNext 的按字段匿名化；Dynamics 365 的只读长期保留。

## 为什么选它

- **每个组件一个 schema、一条读路径**：SAP Data Aging 是同样的形状，没有一个主流产品把历史数据搬进同库的影子 schema。
- **开放文件**让冷数据任何引擎都能读，让换库更便宜，也让分析不用再复制一份。
- **用声明，不用代码**：新表只要写一行 `class:`，AI 只需要判断"这张表属于哪一类"。
- **端口让基础设施可替换，又不必变成组件**（[0106](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)）：换一个只改一个配置值。
- **改正后的顺序**（封存、导出、校验、切换、并发摘下、删除）永远不会有一段数据哪里都读不到，也永远不会让所有查询排在父表的排他锁后面。

## 为什么不选其他

- **归档 schema**：只是把问题挪了个地方。
- **pg_partman**：它的配置表在组件 schema 之外，破坏了 [0102](../02-decisions/01-architecture/0102-one-schema-per-component.md)，还会绕过保全、结转检查和校验。我们借鉴它的预建分区和按边界判断。
- **TimescaleDB**：是某一张超大表的一次性转换候选，不是运行期适配器。
- **湖扩展与 CDC**：两者都把隔离交给了组件之外的东西。
- **在 Go 组件里嵌 DuckDB**：要 cgo，而镜像不开 cgo；Python 的分析组件可以嵌它。

## 什么时候换

- **客户已经有湖仓**，或者擦除多到重写 Parquet 太贵：`cold_store: iceberg`。
- **用户经常查历史**：`cold_query: scan`；数据量大到要聚合或跨单元排序时换 `trino`。
- **分析上线**（`ana/*`）：`publisher: watermark`；要分钟级新鲜度时用 `debezium`。
- **某个组件个人信息很多**（人力资源）：`pii: crypto-shred`。
- **某一张 `ledger` 或 `audit` 表在线超过约 1 TB**，又不能冻结：评估对这一张表做一次性转换。
- **信创数据库交付**：做出并实测它的 `Dialect`。

## 怎么换

1. 对目标适配器组合跑 `tools/be-acceptance/conformance/lifecycle/`；红了就不换。
2. 改 `config/vars.yaml` 里的 `DATA_LIFECYCLE`；`brickkit up`。
3. 如果适配器比组件钉的 SDK 版本新，每个组件升一个 SDK 补丁版本。组件代码不改。

`s3-parquet` 换到 `iceberg`，是把已有单元一次性注册进目录（文件不动），反过来也一样。换 `cold_query` 不搬数据。换 `Dialect` 要搬热温两层的数据；冷层原地不动。

## 一致性测试

套件 `tools/be-acceptance/conformance/lifecycle/`，经各自的 widget 每门 SDK 跑一遍，分五层：

1. **规划向量**（`be-protocol` 的 `vectors/lifecycle/`）：输入声明、覆盖、时间、单元、保全和能力；输出动作、被阻塞的单元和错误；每门 SDK 完全相同。
2. **引擎黑盒**，真 PostgreSQL，模拟时钟走 40 年，两个副本加两个外壳成员同时跑：窗口、封存拒写、状态、在线区间；在每个状态迁移点注入崩溃，最终状态都一样。
3. **冷层往返**，对项目用到的每种列类型做属性测试：冻结、解冻、摘要相等；第三方读取器（一个 DuckDB CLI 容器）从 Parquet 和清单算出同一个摘要；WORM 存储拒绝可擦除的表。
4. **冷查询**：每个适配器返回完全相同的行；冻结前的 `List(R, F)` 等于冻结后（开着冷查询）的结果，也等于解冻后的结果；`none` 恰好对冷区间答 `RANGE_COLD`。
5. **端到端擦除**，横跨热、温、冷、数据集和导出，包括模拟恢复之后的重放。

先写红测试：覆盖值低于下限时加载失败；`ledger` 表有个人信息列时加载失败；`cold_store: none` 时绝不出现导出、绝不删业务单元；封存有未关闭行的单元时把它标为 `BLOCKED`；改已封存单元的一行得到 `UNIT_SEALED`；并发摘下时，父表上的长读不会让新查询排队（在普通 `DETACH` 上是红的）；运行期角色自己执行 `CREATE TABLE … PARTITION OF` 失败，而经 `besdk_ensure_range_partition` 建同一个分区成功；冻结过程中做全范围读，一行都不丢；不论哪天迁移，outbox 当天都能写入。门禁 `lifecycle-scan`：迁移里出现的每张表都有声明；`ledger` 上没有个人信息列；冷表的 `NUMERIC` 列都带精度。

## 相关决策

- [0102 一个数据库，每个组件一个 schema](../02-decisions/01-architecture/0102-one-schema-per-component.md)：推广到每一层：一个组件的数据只由它自己读写，在它的 schema 里，也在它自己的 bucket 里。
- [0106 基础设施不是组件](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)：存储和查询引擎仍是基础设施，在 SDK 端口后面选用。
- [0104 槽位族需要多种合理实现，而且没有依赖边](../02-decisions/01-architecture/0104-variants-become-slot-families.md)：治理是普通组件，不是槽位族；生命周期适配器是 SDK 端口，不是组件。
- [0302 契约只做加法](../02-decisions/03-contracts-and-data/0302-contracts-are-additive-only.md)：发布的数据集遵守它；`include_cold` 是唯一新增的列表字段。
- [0508 后台工作只经 SDK 的 Jobs](../02-decisions/05-runtime/0508-background-work-only-through-jobs.md)：引擎作为 `singleton` 任务运行。
- 计划中、尚未编号："数据生命周期按表声明、由 SDK 执行"；"冷数据是组件自有的开放格式数据集"；"基础设施产品作为适配器放在 SDK 端口后面，每个都通过同一套套件"。

## 已知限制

- **阶段 0 没有冷层**：`s3-parquet` 上线之前数据都留在温层，库会一直增长。
- **冷查询受适配器限制**：`scan` 只能在单元内过滤和排序；聚合要 `trino`。
- **擦除在事件和死信里有滞后**（最长 14 + 7 天和 30 天），除非用 `crypto-shred`；备份里的已擦除数据要等备份过期。
- **法定期限按中国大陆规定起草**（会计档案从会计年度终了次日起保存 30 年，涉税资料 10 年，网络日志不少于 6 个月），交付前要经法务确认。
- **只支持 PostgreSQL 一族**，经 `pg-native`；其他方言要先实测才承诺。
- **治理组件和会计档案归档包都还没做。**
