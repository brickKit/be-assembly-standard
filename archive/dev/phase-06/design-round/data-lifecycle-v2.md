# 数据生命周期 v2：分层存储、生命周期契约、适配器与一致性测试——设计提案

> 开发文档，只给本项目自己用；正式文档（根目录 `AGENTS*.md`、`README*.md`、`docs/`、组件文档）不得链接本文件。
> 写于 2026-10-02（06b 设计轮）。只读调研，未改任何代码、未提交。行号以写作时各仓库工作区为准（be-sdk-go v0.5.0，组件在各自 2.0.x）。
> 重做 `data-layer.md` §3（下称"上一份"）。上一份按"够简单"选了"在线即挂载 + 到期删除或冻结"。本文按用户 2026-10-02 的新判据重做：**要完整、面向将来、不弱于主流产品；几种设计各适合不同场景时，每种做成可替换的适配器；契约和适配器先设计好，用一致性测试证明可互换（端口 / 适配器）；替换只需小而简单的改动，不改逻辑；一切都可重构。**
> 与 `events-consistency.md` 对齐：消费去重表以那份的 `event_cursor` 为准（取代上一份的 `event_inbox_watermark`），幂等表保留期以那份的 30 天为准。与 `authz-architecture.md` 对齐：冷数据读取也必须套规范谓词（数据范围），导出、解冻等 SDK 挂载端点照 `_authz` 的资源契约写法。
> 知识缺口记录：为确认"迁移在每次 `up` 都会重跑"，读过 brickKit 源码仓库 `docs/en/05-migration/01-migration-service.md:96`（"the migration container runs on every `up`"）；为确认 brickKit 有没有定时任务 / configSchema 片段复用，grep 过 `docs/en/`，两者都没有找到。
> 产品事实（第 3 节）来自公开文档和发布说明，凡标"需实测"的，在落地前先写最小复现（memory："没验证过的机制先写最小复现"）。

---

## 0. 结论（一页）

1. **上一份的骨架保留**：热、温两层都挂在同一张分区父表上（"在线即挂载"），取消 `<schema>_archive` 和 `BatchGetRouted` 的冷热路由；组件在 `migrations/lifecycle.yaml` 里声明，SDK 用每个 schema 一把事务级 advisory 锁执行，多副本、外壳多成员都安全。这一部分经得起新判据：SAP S/4HANA 的 Data Aging 也是"同一张表、默认只读当前、显式请求才读历史"，没有一个主流产品把历史数据搬进同库的影子 schema 再路由。
2. **上一份要推翻或补上的七处**（§1）：
   - 冻结格式从 NDJSON.gz 改成 **Parquet + 自描述清单**（有类型、列存、DuckDB / Trino / ClickHouse / Spark / Doris 直接能读）；
   - 冻结顺序改成 **封存 → 导出 → 校验 → 切换读路由 → `DETACH CONCURRENTLY` → `DROP`**，上一份"先 DETACH 再导出"中间有一段数据哪儿都读不到；
   - 上一份说"普通 DETACH / DROP 只锁父表一瞬间"不对：两者都要父表的 ACCESS EXCLUSIVE 锁，等锁期间会**堵住后面所有读写**；
   - 冷数据从"只能运维命令恢复"改成 **API 解冻 + 可选的冷查询适配器**；
   - 自由填写的 `then: keep|freeze|drop` 改成 **8 个表类别**，每类带默认值，组件多数表只写一行 `class:`；
   - 补上上一份没有的：**法定保存期的起算点**（会计档案从会计年度终了次日起算）、**法律保全（legal hold）**、**删除权与保留义务的冲突处理**、**PITR 之后重放删除**、**多租户**、**分析供给**、**封存后的防篡改摘要链**；
   - 冷层格式与读取路径定成契约，配 **一致性测试套件 `be-acceptance/lifecycleconf/`**。
3. **四层**（§4.4）：**热**（挂载，默认读窗口内）→ **温**（挂载，已封存只读，摘要入链，读法不变）→ **冷**（Parquet 存对象存储，库里只留单元目录；可经适配器查询、可解冻回库）→ **销毁**（过法定下限，按类别自动或走审批，留下销毁清册）。另有两个横切状态：**保全**（挡住销毁和擦除）、**限制处理**（删除权遇到法定保留时的处理，PIPL 第 47 条）。
4. **生命周期契约**（§4.3）：每张表声明 `class`（master / reference / document / ledger / audit / queue / snapshot / platform）、分区、关闭条件、`tiers`（hot / seal / cold）、`retention`（下限、起算点、依据、到期动作）、`erasure`（主体类型、键、按列动作）、`checkpoint`（冷冻前要先落的结转行）、`tenant_key`。部署方只能把保留期**调长**、把冷冻**推迟**，不能低于组件声明的下限。声明是方言无关的结构（关闭条件写成 `{column, in}` 而不是 SQL），所以换库、冷层查询、Python SDK 都能用同一份。
5. **SDK 保证 12 条**（§4.5），核心是三条：没有已校验的冷副本就绝不删业务数据；任何时候读一个时间范围，要么拿到完整结果，要么拿到明确的 `RANGE_COLD` 错误（附冷区间和解冻入口），不静默截断；保全中的数据不会被销毁或擦除。
6. **适配器而不是槽位族**（§5）：生命周期机制跑在每个组件进程里，库、对象存储、查询引擎按 0106 都不是组件，所以**全部做成 SDK 端口 + 适配器**，部署时用一个配置键选，靠一致性测试证明可换。端口与第一批适配器：
   - `ColdStore`：`none`（显式降级：冷冻关闭，数据留温层）、**`s3-parquet`（默认）**、`iceberg`（P3，在 Parquet 之上注册到 Iceberg REST 目录）；
   - `ColdQuery`：`none`（答 `RANGE_COLD`）、**`scan`（纯 Go / 纯 Python 读 Parquet，按行组统计裁剪；组件只读自己的前缀）**、`trino`（P3，远程引擎，按 0106 是基础设施）。**DuckDB 不能嵌进 Go 组件**：所有镜像都是 `CGO_ENABLED=0`（`components/erp/sales/Dockerfile:11-12`、`shell/be/go-core/Dockerfile:7`），go-duckdb 要 cgo；DuckDB 留给 Python 侧的 `ana` 组件直接读湖；
   - `Dialect`（分区 DDL 与目录查询）：`pg-native`（PG ≥ 14 及兼容发行版）；它存在的理由是**换库**（openGauss / 金仓的分区语法不同），不是 timescale 或 pg_partman；
   - `DatasetPublisher`（给 `ana` 的增量数据集）：`none` / `watermark`（P2）/ `debezium`（P3）；
   - `PiiProtector`：`plain` / `crypto-shred`（P3，按主体加密，删除权 = 删钥匙，备份里的副本一并失效）。
   **不建适配器的**：pg_partman（全局配置表在组件 schema 之外、后台进程以超级用户跑、它的保留逻辑会绕开我们的守卫）；TimescaleDB 不作为运行期可切换的引擎（换引擎是表结构迁移，不是配置），只作为"某张表数据量到触发条件时的一次性转换"登记在 Revisit 里。
7. **唯一新组件 `infra/data-governance`**（P2）：保全、删除请求（DSAR）的受理与跟踪、销毁审批（经 `infra/workflow`）、合规报表。它只发事件、收事件，**任何组件都不依赖它**；没装它时，每个组件的 SDK 挂载端点 `/_lifecycle/*` 照样能直接下保全、发擦除。
8. **分析（`ana`）不直连业务库**：0102 禁止报表直查别人的 schema，裸 CDC（Debezium 直接抓所有表）等于物理上直查。改成**组件发布数据集**：每个组件按声明把表导出成 Parquet 数据集（冷冻单元 + 可选的增量镜像），数据集结构就是组件的分析契约，只增不改（0302 的推广），`ana` 经查询引擎读。
9. **落地**（§6）：**P0 在组外壳之前**——契约一次定全（`lifecycle.yaml` v1 全部字段、平台表、`_lifecycle` 资源契约、`RANGE_COLD` 错误、配置键 `DATA_LIFECYCLE`），引擎只实现热 / 温（建窗口、平台表清理、队列表到期、封存与摘要链、保全、热温两层擦除），冷层适配器全是 `none`。**P1–P3 只加适配器、不改契约**：组件要做的只是升 SDK、改一个配置值。先写的红测试见 §6.3。
10. **要你拍板的 8 点**（§9），都是业务口径或方向：部署形态（单客户私有化 vs 多租户 SaaS）、各业务表的保留口径由谁定、冷数据的用户体验（异步导出够不够）、到期销毁默认自动还是审批、自然人客户的删除口径、电子会计档案归档包做不做、第二个"证明可换"的引擎要不要提前建、治理组件建不建。

---

## 1. 与上一份的关系：保留什么、推翻什么

| 上一份（data-layer.md §3） | 本文 | 理由 |
|---|---|---|
| 在线即挂载，取消 `<schema>_archive` 与冷热路由 | **保留** | 组件只要一个 schema、没有 DDL 漂移、读路径单一；SAP Data Aging 同构（§3.5） |
| `migrations/lifecycle.yaml`，配置键 `DATA_LIFECYCLE` 覆盖，不能低于 `min` | **保留并扩展**：加 `class`、起算点、保全、擦除、结转、租户键 | 新判据要求覆盖法定保留、删除权、分析 |
| 每 schema 一把事务级 advisory 锁，`lock_timeout` | **保留** | 外壳多成员、多副本的安全性已论证 |
| "不用 `DETACH CONCURRENTLY`，普通 DETACH / DROP 只锁父表一瞬间" | **推翻** | 普通 DETACH 和对已挂载分区的 `DROP TABLE` 都要父表 ACCESS EXCLUSIVE（PG 文档 ddl-partitioning 一节明写）。等锁期间排在它后面的所有查询都被堵住，`lock_timeout=3s` 意味着最坏每轮让整张表停 3 秒。改为：在**专用、不入池**的维护连接上 `DETACH … CONCURRENTLY`（只要 SHARE UPDATE EXCLUSIVE），之后再 `DROP` 已经独立的表（不再碰父表）。专用连接上的会话级 `SET ROLE` 不违反"SET 必须带 LOCAL"——那条铁律防的是连接回池，这条连接用完即关（§4.4） |
| 冻结状态机 `DETACHED → EXPORTED → VERIFIED → DROPPED` | **推翻顺序** | 先摘掉再导出，中间这段时间数据既不在线也不在冷层，读会漏。改为先封存（只读），在挂载状态下导出、校验，读路由切到冷层之后才摘（§4.4） |
| 冻结格式 NDJSON.gz | **推翻**：Parquet + 清单 | NDJSON 丢类型（`NUMERIC(18,2)`、`TIMESTAMPTZ` 都成了字符串），没有列存，分析引擎读起来慢；Parquet 是所有湖仓引擎的公约数 |
| 冻结数据只能经运维命令恢复，不支持在线查询 | **推翻** | 主流产品都给"可检索 + 可恢复"（Salesforce Archive、SAP 归档信息系统、Dynamics 长期保留）。改为 API 解冻（带过期时间）+ 可选冷查询适配器 |
| `then: keep|freeze|drop` + `allow_drop` | **改成表类别** | 13 个组件、约 60 张表按 8 类就能分完（§6.1），每类的默认值就是规则，AI 写新表只需判断"它是哪一类" |
| 财务 `min: 30y` | **修正** | 《会计档案管理办法》第十四条：保管期限**从会计年度终了后的第一天算起**，不是从行的创建时间；而且不同档案期限不同（凭证、账簿 30 年，月季报 10 年，年报和销毁清册永久） |
| 无 | **新增** | 保全、擦除账本与限制处理、PITR 后重放擦除、封存摘要链、结转检查点、多租户布局、数据集发布、一致性测试套件、治理组件 |

---

## 2. 需求模型

### 2.1 十二条需求

| # | 需求 | 依据 / 场景 | 验收口径 |
|---|---|---|---|
| R1 | 近期数据快读 | 订单、库存、凭证的日常列表和详情 | 默认列表只扫热窗口内的分区；单条按 id 毫秒级 |
| R2 | 老数据可以慢一点，但要能读 | 三年前的订单、去年的凭证、客户投诉追溯 | 显式时间范围内全部能读到（在线、冷查询或解冻），不静默截断 |
| R3 | 法定保留 | 会计档案 30 年 / 10 年 / 永久；涉税资料 10 年；网络日志 ≥ 6 个月（§2.3） | 组件声明下限，配置不能调短；起算点按法规；销毁要审批并留清册 |
| R4 | 删除权 | PIPL 第 47 条；GDPR 第 17 条（出海客户） | 主体发起后，所有层都不再返回其个人信息；与 R3 冲突时转"限制处理"并说明依据 |
| R5 | 历史分析 | 未来的 `ana/bi`、`ana/ai`（`registry/ports.tsv:56-57`，`registry/schemas.tsv:52-53`） | 分析读组件发布的数据集，不直连业务库；数据集有版本、只增不改 |
| R6 | 冻结数据可恢复 | 审计抽查、诉讼、补开票 | 单元级解冻回库，摘要校验一致，带过期时间 |
| R7 | 与备份、PITR 协同 | pgBackRest / WAL-G 一类工具 | PITR 之后：冷层不丢、不重复；已执行的擦除会被重放 |
| R8 | 多租户增长 | I10 已决定 JWT 加 `tenant_id`；SaaS 形态 | 租户可以单独下线（含冷层）；租户可以有更长的保留期 |
| R9 | 存储成本可控 | SSD 云盘、备份副本、从库 | 封存后的数据可以转到对象存储；真正的收益是备份 / 恢复时间（RTO），§4.13 |
| R10 | 库可替换 | `data-layer.md` §2.7 的"PG 方言族"目标 | 声明方言无关；冷层是开放格式，换库只需搬热温两层 |
| R11 | 防篡改 | 《会计档案管理办法》第八条：电子会计档案要"防止篡改"；审计 | 封存后的单元有摘要链，任何改动可被校验发现 |
| R12 | 不改业务代码就能换实现 | 用户新判据 | 换冷存储、冷查询、发布方式只改配置值；一致性测试给出能力矩阵 |

### 2.2 现状证据（只列本文新增的发现，上一份 §3.1 的表不重复）

| 发现 | 证据 | 对设计的影响 |
|---|---|---|
| 约定写着"摘进 `<schema>_archive`"，代码里一处都没实现 | `docs/en/01-conventions/02-backend.md:134`；be-ops 只建空 schema `tools/be-ops/internal/dbscript/gen.go:152-177` | 改约定没有迁移成本 |
| `BatchGetRouted` 的冷热路由只有 mdm 两个组件在用，而它们不归档 | `tools/be-sdk-go/archive.go:21-72` | 退化成直接查主表无风险 |
| 所有 Go 镜像 `CGO_ENABLED=0` | `components/erp/sales/Dockerfile:11-12`，`shell/be/go-core/Dockerfile:7` | 任何需要 cgo 的库（go-duckdb、部分 Arrow 加速）不能进组件进程 |
| 库存流水写完就不再 UPDATE（注释承诺，库里没约束） | `components/erp/inventory/migrations/001_create_inventory.up.sql:61-62` | 天然是 ledger 类；封存触发器可以从建分区那一刻就装上 |
| 库存余额靠流水对账 | 上一份 §3.6 | 冷冻流水前必须先落"期末结转"行，否则对账公式断掉（§4.8） |
| 财务没有任何余额表；分录行按期间 LIST 分区，头表不分区 | `components/erp/finance/migrations/001_create_finance.up.sql:66-70,124-146`；全部 `CREATE TABLE` 里没有 balance 类表 | 冷冻分录行之前要有"科目期间余额表"（本身就是 ERP 标配的科目余额表功能） |
| 应收台账与总账分家，注释预见了"已归档的总账分区" | `001_create_finance.up.sql:172-173` | 台账可变、凭证不可变的分工已在；未结清应收要挡住对应凭证的销毁（会计档案办法第二十条） |
| 分录行 FK 指向不分区的头表 | `001_create_finance.up.sql:126` | 冷冻行不影响头表；头表永久在线（行数有上界、很小） |
| 个人信息分布 | 客户联系人 `mdm/customer/migrations/001_create_customers.up.sql:28-38`（姓名、电话、邮箱）；通知 `user_contacts` `infra/notification/migrations/001_create_notification.up.sql:84-92`；钉钉 `dingtalk_user_map` 主键就是手机号 `integration/im-dingtalk/migrations/001_create_dingtalk.up.sql:3-10`；订单上的客户名快照 `erp/sales/migrations/001_create_sales.up.sql:22` | 擦除策略要按列声明；客户是自然人（个体户）时，订单上的名字也是个人信息 |
| 订单主键 `(id, created_at)`，id 是 BIGSERIAL | `001_create_sales.up.sql:19,36` | 按 id 找冷单元不需要索引：每个单元记 `min_id/max_id`，序列号与时间单调相关（§4.6） |
| 商机、待办、阶段历史都不分区 | 只有表 `PARTITION BY` 清单里没有它们（`grep PARTITION BY`，29 处，全是 outbox/inbox 与 §3.6 的那几张） | 冷层对这类表只能做"行单元"（按关闭月份导出后分批删除），引擎要同时支持分区单元和行单元 |
| 2026-10-02 用户新判据 | `README.md` | 本文 |

### 2.3 法定保存期速查（中国大陆；正式落地前请法务确认）

| 资料 | 期限 | 起算 | 依据 |
|---|---|---|---|
| 原始凭证、记账凭证、汇总凭证 | 30 年 | 会计年度终了后第一天 | 《会计档案管理办法》（财政部、国家档案局令第 79 号）第十四条及附表 |
| 总账、明细账、日记账、其他辅助账簿 | 30 年 | 同上 | 同上 |
| 月度、季度、半年度财务报告 | 10 年 | 同上 | 同上 |
| 年度财务报告；会计档案保管清册、销毁清册、鉴定意见书 | 永久 | — | 同上 |
| 银行存款余额调节表、银行对账单、纳税申报表 | 10 年 | 同上 | 同上 |
| 期满但涉及未结清债权债务的凭证 | 保管到未了事项完结 | — | 同上第二十条（单独抽出立卷） |
| 账簿、记账凭证、报表、完税凭证、发票等涉税资料 | 10 年（另有规定的除外） | — | 《税收征收管理法实施细则》第二十九条 |
| 已开具发票存根联 | 5 年 | — | 《发票管理办法》 |
| 网络日志（访问、安全事件） | 不少于 6 个月 | — | 《网络安全法》第二十一条 |
| 个人信息 | 实现处理目的所必要的最短时间 | — | 《个人信息保护法》第十九条 |
| 销毁会计档案 | 先鉴定，编销毁清册，单位负责人等签署，监销 | — | 《会计档案管理办法》第十七至十九条 |
| 仅以电子形式保存 | 来源可靠、系统可输出国家标准归档格式、防篡改、有备份等条件同时满足 | — | 同上第八条；DA/T 94-2022《电子会计档案管理规范》 |

### 2.4 两对张力，设计必须正面回答

- **保留 vs 删除。** PIPL 第 47 条第二款给了出口：法律、行政法规规定的保存期未届满，或删除技术上难以实现的，处理者应当**停止除存储和必要安全保护措施之外的处理**。GDPR 第 17 条第 3 款 (b) 和第 18 条（限制处理）同理。SAP 的做法叫"封锁"（blocking）：目的结束后封锁，只有审计角色能看，保留期满再销毁。所以设计里删除权有三种动作：**删除**（可删的）、**匿名化**（行要留、人不必可识别的）、**限制处理**（法定必须保留原样的），每张表按列声明，擦除结果写明用了哪种以及依据。
- **不可变 vs 更正。** 记账凭证过账后不可改，更正用红字冲销（项目已经这样设计，`006_source_doc_index.up.sql:1`）。数据库层面再加一道：封存单元装只读触发器，并把单元摘要链入 `besdk_lifecycle_units`。和 SQL Server Ledger 表、Oracle 不可变表 / 区块链表是同一类保证（摘要可验证，不是加密不可改）。

---

## 3. 市场方案对比

### 3.1 库内分层（热 / 温）

| 方案 | 怎么做 | 优点 | 缺点 | 对本项目 |
|---|---|---|---|---|
| **PG 原生声明式分区 + DETACH** | RANGE / LIST 分区；`DETACH CONCURRENTLY`（PG 14+，不能在事务块里跑，有 DEFAULT 分区时不可用）；`ATTACH` 前加匹配边界的 CHECK 约束可免全表扫描；可 `SET TABLESPACE` 搬到便宜盘 | 内核功能，所有托管 PG、PG 兼容库都有；无扩展、无超级用户 | 没有自带调度；PG 堆表没有真正的压缩（`SET COMPRESSION lz4` 只管 TOAST）；表空间多数托管服务不开放；PG 17 一度合入的 MERGE / SPLIT PARTITION 在正式发布前被回退 | **选为唯一引擎**。缺的调度、守卫、状态机由 SDK 补 |
| **pg_partman** | 扩展；`create_parent`、`run_maintenance()`、后台进程；保留期 `retention`、`retention_keep_table`、`retention_schema`（摘到另一个 schema） | 成熟，RDS / Cloud SQL / Azure 都支持；预建分区、模板表的思路好 | 配置表 `part_config` 在扩展自己的 schema 里——一个组件的生命周期配置落到组件 schema 之外，0102 的"各管各的"破了口；后台进程以高权限跑；它的保留逻辑不知道我们的守卫（未结束的行、保全、冷副本校验）；冷冻还得我们自己做 | **不用**。吸收它的两个好主意：预建窗口（`premake`）、按边界而不是名字判断（上一份 §4.3 已有） |
| **TimescaleDB** | hypertable 自动分块；列存压缩（2.18 起叫 columnstore / hypercore，压缩比常见 90%+）；`drop_chunks` / 保留策略；连续聚合；**分层到 S3 只在其云服务上有，开源版没有** | 追加型大表（流水、日志）压缩和时间聚合非常强 | 压缩、连续聚合是 TSL 许可，不是 Apache 2；RDS 不支持，Azure 已下线；换成 hypertable 是表结构迁移；压缩块的 UPDATE / DELETE 代价高，与擦除冲突 | **不作运行期适配器**；登记为"单表超过触发条件时的一次性转换"（§7 Revisit） |
| **Citus** | 分布式表（按租户分片）；Citus 12 起支持按 schema 分片；`columnar` 访问方法（追加型，不支持 UPDATE / DELETE） | AGPL 全开源；schema 分片和"每组件一个 schema"天然对得上；columnar 可以给封存分区当温层压缩 | 分布式要求分片键进所有主键 / 外键；扩展必须装在库上 | **登记为 P3 的温层压缩选项**（封存分区 `SET ACCESS METHOD columnar`，可逆），以及多租户横向扩展的方向（§4.11） |
| **应用层归档表** | 同库再建 `xxx_archive`，按条件 INSERT … SELECT + DELETE | 简单，任何库都行 | DDL 漂移；读要路由；大批 DELETE 造成膨胀 | 这就是旧约定，**放弃** |
| **软删除 + 定期清理** | `deleted_at` / `active=false`，后台硬删 | 用户误删可恢复（回收站） | 每个查询都要带条件；软删除不是生命周期，只是"回收站"；对法定保留无帮助 | **不用于生命周期**。回收站需求出现时作为组件功能单独做（ERPNext 的 Deleted Document 那种） |

### 3.2 冷层（湖仓）

| 方案 | 怎么做 | 优点 | 缺点 | 对本项目 |
|---|---|---|---|---|
| **Parquet 文件 + 自描述清单（对象存储）** | 每个冻结单元写若干 Parquet 文件 + 一份 JSON 清单（行数、摘要、结构版本、依据） | 任何引擎都能读（DuckDB `read_parquet`、Trino Hive 连接器、ClickHouse `s3()`、Spark、Doris / StarRocks）；Go（arrow-go、parquet-go）和 Python（pyarrow）都有纯语言实现 | 没有表级事务、没有行级删除，擦除要重写文件 | **默认冷存储 `s3-parquet`** |
| **Apache Iceberg** | Parquet 数据文件 + 元数据树 + 目录（REST 规范；Polaris、Lakekeeper、Nessie、Glue、S3 Tables 等）；v2 起有行级删除文件，v3 有删除向量 | 事实标准的开放表格式：Snowflake、Databricks（UniForm）、AWS S3 Tables、Salesforce Data Cloud 的零拷贝都走它；模式演进、时间旅行；行级擦除便宜 | 要一个目录服务（基础设施）；Go 的 iceberg-go 写入能力较新（需实测） | **P3 适配器 `iceberg`**：数据文件格式不变，只多一步注册目录，所以和 `s3-parquet` 可以无损互转 |
| DuckLake | DuckDB 2025 年提出：元数据放在 SQL 库（可以是 PG），数据是 Parquet | 目录就在我们已有的 PG 里，不多一个服务 | 新、0.x，生态未定 | 登记观察，不建 |
| PG 内读湖：pg_duckdb、pg_mooncake、pg_lake、parquet_s3_fdw | 在 PG 里装扩展，直接 SQL 查 S3 上的 Parquet / Iceberg | 冷热可以一条 SQL 联合 | 都是库级扩展、要高权限，托管 PG 普遍不支持；把"组件只读自己的前缀"的隔离交给了扩展 | **不做默认**；可以作为 `ColdQuery` 的 P3 候选（`pg-lake`），前提是隔离能证明 |
| 查询引擎：DuckDB / Trino / ClickHouse / Doris / StarRocks | 嵌入式（DuckDB）或独立服务 | DuckDB 单机极快；Trino 联邦查询、细粒度访问控制；ClickHouse / Doris / StarRocks 在国内 BI 栈很常见 | 独立服务是基础设施（0106）；DuckDB 进 Go 要 cgo | `ColdQuery` 适配器：`scan`（自带）→ `trino`（P3）；`ana` 的 Python 组件直接用 DuckDB |

### 3.3 分析供给

| 方案 | 优点 | 缺点 | 对本项目 |
|---|---|---|---|
| 逻辑复制 / Debezium 全表 CDC 进分析库 | 低延迟、能抓删除 | 物理上就是"报表直查别人的 schema"（0102 明确排除）；复制槽在消费方宕机时会撑爆 WAL（需 `max_slot_wal_keep_size`）；要 REPLICATION 权限；表结构变了下游就坏，没有契约 | **不直连**。Debezium 可以作为组件**自己的**数据集发布器（`DatasetPublisher=debezium`），输出必须是组件声明的数据集结构，P3 |
| 业务事件进分析 | 已有（outbox + JetStream） | 事件是变化不是状态；流只留 7 天 | 用于实时指标；全量历史靠数据集 |
| **组件发布数据集（data product）** | 组件决定发布什么、怎么脱敏；结构有版本；与冷层同一种格式 | 要多写一份数据集声明 | **推荐**。数据集声明就写在 `lifecycle.yaml` 的表上（§4.12） |

### 3.4 主流产品怎么做

| 产品 | 做法 | 我们借鉴 |
|---|---|---|
| **Odoo** | 记录用 `active` 字段"归档"（只是隐藏，数据不动）；自动清理只针对临时模型（`ir.autovacuum`）；有数据回收（Data Recycle）模块按规则归档或删除；没有分区、没有冷层 | 反面参照：一切都在主表里，大客户靠 DBA 手工处理 |
| **ERPNext / Frappe** | 删除进 Deleted Document（可恢复的回收站）；Log Settings 按天数清日志；个人数据删除请求（Personal Data Deletion Request）按每个 DocType 配置的字段做匿名化；没有分区 | 擦除"按表按列声明匿名化规则"——我们的 `erasure.columns` |
| **SAP ECC / S/4HANA** | 数据归档（SARA）：归档对象 = 头 + 明细 + 依赖表一起，写 / 删 / 读三个程序，**可归档性检查**（未结束的单据不归档并给出原因）；归档信息系统（SAP AS）建检索索引；ILM：保留规则（驻留期 vs 保留期）、法律案件保全、销毁；S/4HANA Data Aging 把老数据放到同表的历史分区，**默认查询只看当前，要显式请求历史**；个人数据"目的结束检查 + 封锁 + 到期销毁" | 归档单元 = 主表 + 明细一起（我们的 `follows`）；可归档性检查（我们的封存守卫）；驻留期 vs 保留期（我们的 `tiers.cold` vs `retention.min`）；保全；封锁（我们的"限制处理"）；Data Aging 的默认读当前（我们的 `hot` 窗口） |
| **Salesforce** | Big Objects（按索引查询、容量大、功能受限）；Field Audit Trail（字段历史留到 10 年）；Salesforce Archive（2024 起：归档策略、可检索、可恢复、可清除）；回收站 15 天；Privacy Center（保留与被遗忘权策略）；Data Cloud 经 Iceberg 零拷贝给 Snowflake / Databricks | 冷数据要"可检索 + 可恢复"；隐私策略是一等公民；分析经开放表格式供给 |
| **Dynamics 365 / Dataverse** | 长期数据保留：按表配策略，数据转入托管数据湖，只读、可查看（以官方文档为准，搬回活动表能力有限） | "冷层只读可查"是基本盘，我们多给一个"解冻" |

### 3.5 从市场学到的十条（直接变成设计约束）

1. 默认读当前，显式请求才读历史（SAP Data Aging、我们已有的 90 天窗口）。
2. 归档单元是业务对象（头 + 明细），不是单张表（SAP 归档对象）。
3. 先做可归档性检查，挡住未结束的单据并给出原因（SAP）。
4. 驻留期（多久以后可以离线）与保留期（多久以后可以销毁）是两个数（SAP ILM）。
5. 保全优先于一切销毁规则（SAP ILM 法律案件、Salesforce Privacy Center）。
6. 删除权遇到法定保留就"封锁 / 限制处理"，不是二选一（SAP、PIPL 47、GDPR 18）。
7. 冷数据要能检索、能恢复（Salesforce Archive、SAP AS）。
8. 冷层用开放格式，分析靠零拷贝而不是再搬一份（Iceberg 生态）。
9. 匿名化规则按表按列声明（ERPNext）。
10. 不要指望软删除或 `active` 字段解决生命周期（Odoo 的教训）。

---

## 4. 推荐设计

### 4.1 总图

```
                        组件进程（单独跑 / 外壳成员都一样）
 ┌──────────────────────────────────────────────────────────────────────┐
 │ 业务代码：repo SQL ── lc.Window / lc.Locate / lc.Seal / lc.ColdList │
 │                                                                      │
 │ be-sdk lifecycle：Planner（纯函数）→ Executor（有锁、有状态机）       │
 │   端口：Dialect │ ColdStore │ ColdQuery │ DatasetPublisher │ PiiProtector │
 │   挂载：/_lifecycle/*（HTTP） + besdk.lifecycle.v1（gRPC）            │
 └──────┬───────────────────────┬───────────────────────┬───────────────┘
        │ 自己的 schema + 角色   │ 自己的前缀 + 凭据      │ outbox 事件
        ▼                       ▼                       ▼
 PostgreSQL（热、温，封存触发器）  对象存储 S3_URL（冷：Parquet + 清单）  NATS
 平台表 besdk_lifecycle_*        <env>/<component>/<table>/…           ↑↓
                                        ▲                         infra/data-governance
                                        │ 只读、按数据集授权           （保全、DSAR、销毁审批）
                                  ana/* 组件（DuckDB / Trino）
```

一条原则贯穿：**每个组件的数据，在每一层都只由它自己读写**。库里是自己的 schema，对象存储里是自己的前缀（自己的凭据只能读写这个前缀），分析读的是它发布的数据集。这是 0102 在新存储上的延伸，也是 0102 自己的 Revisit 条件写好的那条路："组件需要 PG 提供不了的存储能力时，用自己的配置拿自己的存储"。

### 4.2 表的分类

| 类别 | 是什么 | 分区 | 封存 | 冷层 | 到期 | 擦除默认 | 本项目的例子 |
|---|---|---|---|---|---|---|---|
| `master` | 主数据，可变，量有上界 | 不分区 | 不封存 | 不冷冻 | 永久保留 | 匿名化个人信息列 | `customers`、`contacts`、`products`、`notification_preferences` |
| `reference` | 配置、字典、模板 | 不分区 | 不封存 | 不冷冻 | 永久 | 无个人信息（门禁检查） | `accounts`、`pricelists`、`opportunity_stages`、`print_templates`、`fiscal_years` |
| `document` | 有状态机的业务单据 | 按创建时间（建议）或不分区（行单元） | 关闭后满 N 个月封存 | 可选 | 按保留口径 | 按列：限制处理 / 匿名化 | `sales_orders`（+`items`）、`opportunities`、`workflow_tasks`、`ar_ledger`、`inventory_reservations` |
| `ledger` | 追加型账簿，写入后不可改 | 按时间或期间 | 立即（`immediate`）或按业务信号（`on_signal`，如期间锁定） | 可选，冷冻前要结转 | 法定下限，到期走审批 | **不许有个人信息列**，只存主体不透明 id（门禁检查） | `inventory_movements`、`finance_journal_entry_lines`、`finance_journal_entries`（头，不分区） |
| `audit` | 谁在何时做了什么 | 按时间 | 立即 | 可选（1 年后） | 下限 ≥ 6 个月，默认 3 年后销毁 | 操作者 id 保留（限制处理） | `role_changes`、`workflow_task_actions`、`opportunity_stage_history`、`besdk_lifecycle_log`（永久） |
| `queue` | 有未结束状态的工作项 | 按时间 | 不封存 | 不冷冻 | 到期删除，但**有未结束行的分区不删** | 删除 | `webhook_deliveries`、`notification_records`、`delivery_attempts`、`print_jobs` |
| `snapshot` | 别人数据的本地副本、缓存，可重建 | 任意 | 不封存 | 不冷冻 | 可随时删 | 删除行 | `customer_snapshots`、`customer_credit_snapshots`、`product_tracking_snapshots`、`user_contacts`、`dingtalk_user_map` |
| `platform` | SDK 自带 | SDK 定 | — | 不冷冻 | SDK 定 | SDK 定 | `event_outbox`（发布后 14 天）、`event_cursor`（30 天）、`command_idempotency`（30 天）、`besdk_*` |

每个类别是一组默认值 + 一组**不变式**（Planner 在加载声明时校验，违反就启动失败并点名）：

- `ledger` 和 `audit` 上的 UPDATE / DELETE 由封存触发器拒绝（`immediate` 时从分区建好那一刻起）。
- `ledger` 上标了 `pii` 的列一律报错——个人信息放主数据，账簿只存不透明 id。这让"账簿 30 年"和"删除权"不再冲突。
- `queue` 不能声明 `cold`；`snapshot` 不能声明 `retention.min`（它不是真相源）。
- 声明了 `cold` 的表，所有 `NUMERIC` 列必须有精度（Parquet 的 DECIMAL 需要定长精度）。
- 声明了 `cold` 且主体可擦除（`erasure` 有 `delete` / `anonymize` 动作）的表，不能选 WORM 冷存储（§4.9）。

### 4.3 生命周期契约：`lifecycle.yaml` v1

位置：`migrations/lifecycle.yaml`（随迁移嵌进镜像；SDK 运行期读，be-ops 和门禁在组装期读同一份）。迁移工具忽略这个文件这一点，上一份已列为先做最小复现。

```yaml
# components/erp/sales/migrations/lifecycle.yaml
lifecycle: v1
tenant_key: none                 # 多租户以后写列名（如 tenant_id），见 §4.11
tables:
  sales_orders:
    class: document
    partition: {by: created_at, grain: month, ahead: 3}
    closed: {column: status, in: [COMPLETED, CANCELLED, CLOSED], at: updated_at}
    tiers:
      hot: 90d                   # List 没给范围时的默认窗口
      seal: 18mo after closed    # 关闭满 18 个月的分区整体封存（只读、入摘要链）
      cold: 5y after closed      # 有冷存储时冻结；没有就留在温层（只记一次 INFO）
    retention:
      min: 10y after closed      # 下限：部署方只能调长
      basis: "税收征管法实施细则第二十九条（涉税资料）——口径待法务确认"
      end: review                # keep | destroy | review（review = 生成销毁待办，审批后才销毁）
    erasure:
      subject: customer          # 主体类型（registry/data-subjects.tsv，§4.9）
      key: customer_id
      columns: {customer_name: restrict}   # 保留期内：限制处理
    dataset: {publish: true, exclude: [suspended_reason]}   # 给 ana 的数据集（§4.12）
  sales_order_items:
    follows: sales_orders        # 同边界建分区、同单元封存 / 冻结 / 销毁
  customer_snapshots:
    class: snapshot
    erasure: {subject: customer, key: customer_id, action: delete}
  pricelists: {class: reference}
  pricelist_items: {class: reference}
```

```yaml
# components/erp/finance/migrations/lifecycle.yaml（节选）
tables:
  finance_journal_entries:
    class: ledger                # 头表不分区：永久在线（承载幂等过账唯一约束，001:66-70）
    retention: {min: 30y after fiscal_year_end, basis: "会计档案管理办法第十四条", end: review}
  finance_journal_entry_lines:
    class: ledger
    partition: {by: accounting_period, kind: list, opened_by: command}   # 开会计年度命令建分区（上一份 §4.4 (b)）
    tiers:
      seal: on_signal            # LockPeriod 在同一事务里调 lc.Seal(...)
      cold: 10y after fiscal_year_end
    retention: {min: 30y after fiscal_year_end, basis: "会计档案管理办法第十四条", end: review}
    checkpoint: account_period_balances   # 冷冻前必须已有该期间的余额行（§4.8）
    guard: {blocked_by: open_receivables} # 组件实现的守卫：有未结清应收引用的凭证所在单元不销毁（第二十条）
  ar_ledger:
    class: document
    closed: {column: status, in: [RECONCILED], at: updated_at}
    retention: {min: 30y after fiscal_year_end, basis: "明细账", end: review}
```

```yaml
# components/mdm/customer/migrations/lifecycle.yaml（节选）
tables:
  customers:
    class: master
    tiers: {hot: none}           # 主数据不注入默认时间窗口（D3 的答案落在类别默认值上）
    erasure: {subject: customer, key: id, columns: {name: anonymize, tax_id: restrict}}
  contacts:
    class: master
    erasure: {subject: contact, key: id, columns: {name: anonymize, phone: delete, email: delete}}
```

**字段语义**（完整列表，P0 一次定全）：

| 字段 | 取值 | 说明 |
|---|---|---|
| `class` | 8 类之一 | 决定默认值与不变式 |
| `partition` | `{by, grain: week|month|year, ahead}` 或 `{by, kind: list, opened_by: command}` | 分区由 SDK 建（上一份 §4.3）；不写表示不分区 |
| `closed` | `{column, in: [...], at: <列>}` | 结构化，不写 SQL：Go / Python / 冷查询都能求值，换库不受影响 |
| `tiers.hot` | 时长或 `none` | 默认读窗口 |
| `tiers.seal` | `immediate` / `on_signal` / `<n> after <anchor>` / `never` | 进温层 |
| `tiers.cold` | `<n> after <anchor>` / `never` | 进冷层（驻留期） |
| `retention.min` | `<n> after <anchor>` / `forever` | 销毁下限（保留期） |
| `retention.basis` | 文本 | 写进销毁清册和擦除回执 |
| `retention.end` | `keep` / `destroy` / `review` | 到期动作 |
| 锚点 `<anchor>` | `created` / `closed` / `sealed` / `fiscal_year_end` | `fiscal_year_end` 由组件实现 `lifecycle.Calendar` 接口给出（finance 实现；其余组件默认自然年） |
| `erasure` | `{subject, key, columns: {<列>: delete|anonymize|restrict}}` 或 `{subject, key, action: delete}` | 见 §4.9 |
| `checkpoint` | 表名 | 冷冻前组件必须已写入的结转表；引擎调用组件实现的 `Checkpointer` 并核对 |
| `guard` | `{blocked_by: <名字>}` | 组件实现的命名守卫（Go / Python 函数），在封存 / 销毁前调用 |
| `follows` | 表名 | 跟随主表 |
| `dataset` | `{publish, exclude, pseudonymize}` | §4.12 |
| `tenant_key` | 列名 / `none` | §4.11 |

**部署覆盖**：一个配置键 `DATA_LIFECYCLE`（YAML / JSON 字符串），装下模式、适配器选择和逐表覆盖，避免每个组件的 configSchema 多出七八个键（brickKit `03-config-schema-design.md` 也反对拆得过细）：

```yaml
# config/vars.yaml
DATA_LIFECYCLE: |
  mode: on                       # on | dry-run | off
  cold_store: s3-parquet         # none | s3-parquet | iceberg
  cold_query: scan               # none | scan | trino
  publisher: none                # none | watermark | debezium
  pii: plain                     # plain | crypto-shred
# config/erp-sales.yaml 里可以再写组件自己的逐表覆盖：
#   DATA_LIFECYCLE: '{"$extends":"$var:DATA_LIFECYCLE","tables":{"sales_orders":{"retention":{"min":"15y after closed"}}}}'
```

（`$extends` 只是示意：两层合并由 SDK 做，键名与合并规则在 P0 定稿。）对象存储沿用 `S3_URL`，凭据是两个密钥键 `S3_ACCESS_KEY_ID` / `S3_SECRET_ACCESS_KEY`，**每个组件一套、只授权自己的前缀**（be-ops 生成桶策略，对照 `schemas.tsv` 的角色列）。冷查询引擎地址 `LAKE_QUERY_URL`（只有选了 `trino` 才需要）。

### 4.4 层、单元与状态机

**单元**：生命周期操作的最小粒度。分区表的单元是一个分区（含 `follows` 子表的同边界分区）；不分区表的单元是"按锚点列落在某个月"的行集合（行单元）。

```
               EnsureAhead                Seal                     Export        Verify
 (不存在) ──────────────▶ ACTIVE ──────────────▶ SEALED ──────▶ EXPORTING ──▶ EXPORTED ──▶ VERIFIED
                          热/温（挂载）            温（只读、入链）                         │ 切换读路由（同一事务改单元状态）
                                                                                         ▼
     DESTROYED ◀── review 审批 / destroy ── COLD ◀── DETACH CONCURRENTLY + DROP ── COLD_PENDING_DROP
         ▲                                    │  ▲
         └──────── 保全中禁止 ─────────────────┘  │ Thaw(days) / 到期 Refreeze
                                               THAWED（重新挂载、只读）
```

逐步说明（每一步一个事务、一把 advisory 锁、`lock_timeout`，崩溃后从 `besdk_lifecycle_units.state` 接着做）：

1. **EnsureAhead**：上一份 §4.3 原样保留（按边界判断、`follows` 同事务、迁移时建当前窗口、运行期补提前量）。`ledger` / `audit` 类建分区时同时装封存触发器。
2. **Seal**：Planner 选出满足 `tiers.seal` 的单元；Executor 在一个事务里：对该分区取 SHARE ROW EXCLUSIVE 锁（挡写不挡读）→ 校验所有行满足 `closed`（不满足的单元标 `BLOCKED` 并记录原因与前 100 个 id，导出指标 `besdk_lifecycle_blocked{table,reason}`，SAP 的"可归档性检查"）→ 调命名守卫 → 装触发器 `besdk_sealed_guard`（BEFORE UPDATE / DELETE 行级 + BEFORE TRUNCATE 语句级）→ 计算单元摘要并链接：`chain_n = SHA-256(chain_{n-1} ‖ unit_digest_n)`。行单元的封存用表级触发器对比"已封存到哪个月"的水位（每次 UPDATE 一次主键查找）。`on_signal` 由组件在业务事务里调用 `lc.Seal(ctx, tx, table, unit)`，与锁期间同一事务。
   - 注意：经父表访问时 PG 只检查父表的权限，所以不能靠"收回分区的 UPDATE 权限"实现只读，必须用分区上的触发器。
3. **Export**：从**仍然挂载**的已封存分区按主键顺序流式读出，写 Parquet（行组约 128 MB），同时按规范编码（§4.6）算摘要。文件布局：`<env>/<component>/<table>/v<数据集版本>/unit=<YYYY-MM>/tenant=<t>/part-NNNN.parquet` 与 `…/_manifests/<unit>.json`。对象键带内容摘要，重复导出是幂等覆盖。
4. **Verify**：回读对象（不是信任写入返回值），重算规范摘要，与封存摘要比对；比对通过才进 `VERIFIED`。
5. **切换读路由**：同一事务把单元改成 `COLD_PENDING_DROP`，在线区间随之收缩。此后 `Window` 对这段时间返回 `RANGE_COLD` 或走冷查询，读不会漏。
6. **Detach + Drop**：专用、不入池的维护连接（`pgx.Connect`，用外壳或组件的登录角色登录，会话级 `SET ROLE <成员角色>`，用完即关）上执行 `ALTER TABLE … DETACH PARTITION … CONCURRENTLY`（父表只要 SHARE UPDATE EXCLUSIVE），成功后 `DROP TABLE` 已独立的表（不再碰父表）。行单元则是分批 `DELETE … WHERE ctid IN (… LIMIT 5000)`，每批一个事务。状态 → `COLD`。
7. **Thaw**：`CREATE TABLE … (LIKE 父表 INCLUDING DEFAULTS INCLUDING CONSTRAINTS)` → 从 Parquet 灌入（按列名映射：文件里有、表里已删的列忽略；表里新增的列取默认值）→ 加与边界一致的 CHECK 约束 → 重算摘要比对 → 装封存触发器 → `ATTACH PARTITION`（父表 SHARE UPDATE EXCLUSIVE，有 CHECK 约束就免扫描）→ 状态 `THAWED until <t>`。到期由引擎重新执行第 5、6 步（文件还在，不用再导出）。
8. **Destroy**：只有 `retention.min` 已过、没有保全、命名守卫通过的 `COLD`（或从未冷冻的已封存）单元才进入候选。`end: destroy` 直接执行；`end: review` 生成销毁清单（单元、行数、摘要、依据），经 `_lifecycle/destructions` 或治理组件转成 `infra/workflow` 待办，审批通过后执行；清单本身写进 `besdk_lifecycle_log`（永久，对应"会计档案销毁清册永久保存"）。
9. **Expire（queue / platform）**：上一份的守卫原样保留（outbox 全部 PUBLISHED、队列表没有未结束行），走第 6 步的 DETACH CONCURRENTLY + DROP，不经冷层。

### 4.5 SDK 保证（契约的另一半）

| # | 保证 |
|---|---|
| G1 | 任何日期迁移跑完当天就能写入；运行期窗口始终覆盖 `ahead` |
| G2 | 同一 schema 同一步同一时刻只有一个执行者；不同 schema 互不阻塞；DDL 不在热路径上排长队（专用连接 + CONCURRENTLY + 短 `lock_timeout`） |
| G3 | 不低于声明的 `retention.min` 删除任何行；部署覆盖低于下限启动即失败 |
| G4 | 业务类别（document / ledger / audit）的数据，没有已校验的冷副本就不会从库里删除；冷存储为 `none` 时冷冻跳过，数据留温层 |
| G5 | 封存单元不可改：UPDATE / DELETE / TRUNCATE 被拒绝（SQLSTATE 由 SDK 统一映射成 `FAILED_PRECONDITION` + `reason: UNIT_SEALED`） |
| G6 | 封存单元的摘要链可随时校验（`lc.Verify` / `GET _lifecycle/verify`），被改动必被发现 |
| G7 | 读一个时间范围：要么完整结果，要么 `RANGE_COLD`（附冷区间、可否解冻、可否异步导出），不静默截断 |
| G8 | 冷层读取（冷查询、导出、解冻后的在线读）套用与热层相同的数据范围谓词；适配器表达不了某个谓词时拒绝，不放宽 |
| G9 | 保全覆盖的数据不会被销毁、擦除；冷冻不受影响（数据仍保存） |
| G10 | 擦除请求在声明的范围内作用于所有层（热、温、冷、已发布数据集、之后的解冻），并留下回执；PITR 之后自动重放 |
| G11 | 每个动作写 `besdk_lifecycle_log`（追加型、永久），并发出 `<domain>.<name>.lifecycle.*.v1` 事件 |
| G12 | Go 与 Python 的 Planner 对同一组输入给出逐字相同的动作序列（一致性向量） |

### 4.6 读路径

**规范编码与摘要**：每行按声明列顺序，把每个值转成 PG 文本输出格式（NULL 记为 `\N`），字段用 `0x1F`、行用 `0x1E` 分隔，行按主键排序，整单元做 SHA-256。导出时从 PG 算、校验时从 Parquet 回读算、解冻时从库里再算，三者必须相同。规范编码写进契约，所以任何适配器（包括第三方工具，§5.3 ③）都能独立校验。

**在线区间**：`OnlineIntervals(table)` 返回一组区间（解冻会造成"岛"），从 `besdk_lifecycle_units` 读，进程内缓存，单元状态变化时经本地通知失效（单进程内）或最多 1 分钟过期（多副本）。

**单条 / 批量按 id（BatchGet）**：仍然直接查主表（`BatchGetRouted` 退化，保留名字、标 Deprecated）。查不到的 id，调用方需要区分"不存在"和"已冷冻"时调 SDK 挂载的 `Locate(table, ids)`：用每个冷单元的 `min_id/max_id`（BIGSERIAL 与时间单调）或时间有序 id（UUIDv7）的时间位直接算出所在单元，不需要冷 id 索引（SAP AS 要建检索索引，是因为它的单据号不带时间）。**组件自己的 BatchGet 契约不变**。

**列表**：

```go
w, err := lc.Window("sales_orders", req.Range, req.Page)   // 取代 besdk.ListWindow
// w.Online 是可直接拼进 SQL 的 Query（默认 hot 窗口、页大小夹紧、与在线区间求交）
// w.Cold 是请求范围里落在冷层的区间；err 只有在 Cold 非空且（没开冷查询 || 请求没带 include_cold）时才是 ErrRangeCold
rows := repo.ListOrders(ctx, tx, w.Online, scope)
if w.HasCold() && req.IncludeCold {
    more, next := lc.ColdList(ctx, "sales_orders", lifecycle.Filter{Eq: {...}, Scope: scope}, w)  // 走 ColdQuery 适配器
}
```

- 游标由 SDK 编码层级（`tier`、最后一个键），翻页从热层自然过渡到冷层，调用方不感知。
- `ColdList` 的过滤条件是结构化的（等值、范围、IN、数据范围谓词），由适配器翻成 Parquet 行组裁剪 + 内存求值（`scan`）或 Trino SQL（`trino`）。authz 的规范谓词里"共享（acl）分支"在冷层先在 PG 里求出共享给我的 id 集合，再作为 `id IN` 传下去。
- **错误契约**：gRPC `FAILED_PRECONDITION` + `ErrorInfo{reason: "RANGE_COLD", metadata: {online_from, cold_ranges, thaw_allowed, export_allowed}}`；HTTP 400（沿用 `be-sdk-go/gin.go:146` 现有映射）+ 错误体 `code: RANGE_COLD`；bff 映射为 GraphQL `extensions.code = RANGE_COLD`。（上一份用的是 `OUT_OF_RANGE` / `RANGE_NOT_ONLINE`；改名是因为"不在线"现在有了明确的下一步动作——解冻或导出，`FAILED_PRECONDITION` 的语义正是"系统状态不满足，改变状态后可重试"。）
- **契约**：List 请求要加 `include_cold`（bool，默认 false）——这是各组件 proto 唯一的改动，只增字段，P0 一次加齐，P2 冷查询上线时不再碰契约。

**导出（异步）**：SDK 挂载 `POST /{domain}/{name}/_lifecycle/exports {table, from, to, filter, format: parquet|csv}` → 任务 → 结果写进组件前缀下的 `exports/`，返回预签名 URL（短期）。跨热冷层，套数据范围。大范围历史查询（审计抽查、"导出 2015 年全部发票"）走这里，这是 Salesforce Bulk API、SAP 归档读程序的同类。

**解冻**：`POST _lifecycle/units/{table}/{unit}:thaw {days}`；`GET _lifecycle/units?table=` 列出单元与状态。

**权限键**：每个组件三把，由 be-ops 按 `_lifecycle` 资源契约自动生成进 `permissions.tsv`（与 `_authz` 同一做法）：`<id>.lifecycle.read`（导出、看单元）、`<id>.lifecycle.thaw`、`<id>.lifecycle.admin`（保全、擦除、销毁审批的执行）。

### 4.7 事件、outbox、游标与幂等

| 表 | 类别 | 生命周期 | 说明 |
|---|---|---|---|
| `event_outbox` | platform，周分区 | 全部 PUBLISHED 后 14 天删分区 | outbox 不是档案，真相源是业务表；JetStream 流留 7 天（events-consistency E2） |
| `event_cursor` | platform，不分区 | `seen_at` 超 30 天按行删 | 取代上一份的 inbox 水位表 |
| `command_idempotency` | platform，不分区 | 30 天按行删（E5） | 键的有效期写进契约 |
| `besdk_lifecycle_units` / `_log` / `_holds` / `_erasures` / `_exports` | platform | log 永久；其余随单元 | §4.14 |

- **事件里的个人信息**：outbox 14 天 + 流 7 天就是擦除的最大滞后，写进组件的隐私说明；`event_id` 等不含个人信息。DLQ 保留 30 天，擦除时 SDK 不改 DLQ（JetStream 消息不可改），在说明里列为已知滞后——或在 `pii: crypto-shred` 下随密钥一起失效。
- **新消费者要的历史早于在线窗口**：events-consistency 的回填走上游 `List`，遇到 `RANGE_COLD` 就改用上游的数据集（§4.12），而不是要求上游解冻。
- **生命周期事件**：`<domain>.<name>.lifecycle.sealed|frozen|thawed|destroyed|erasure_completed.v1`，经 outbox 发出。治理组件和 `ana` 订阅。

### 4.8 财务：法定保留、不可变、结转、销毁

- **不可变两层**：业务层（过账后只能冲销，已有）+ 存储层（期间 LOCKED 时 `lc.Seal` 封存该期间分区，摘要入链）。头表 `finance_journal_entries` 是 ledger 类、不分区、永久在线：它承载幂等过账唯一约束，三十年的凭证头也就几百万行。
- **起算点**：`fiscal_year_end` 锚点由 finance 实现 `lifecycle.Calendar`（读 `fiscal_years.end_date`），所以 30 年从会计年度终了次日起算。
- **结转检查点**：冷冻分录行之前，必须已有该期间的 `account_period_balances`（科目 × 法人 × 期间的期初、发生、期末）。这张表也是科目余额表、试算平衡的数据源，属于 finance 本来就缺的功能；inventory 同理需要 `inventory_period_balances`（期末结存）。没有结转表的组件不能给 ledger 表声明 `cold`（Planner 校验）。
- **未了事项**：命名守卫 `open_receivables`（finance 实现）：单元里有被未结清 `ar_ledger` 引用的凭证时，单元不进入销毁候选，并在销毁清单里单列——对应会计档案办法第二十条"单独抽出立卷"。
- **销毁**：`end: review`；清单包含单元、行数、摘要、保管期限、依据，审批人和时间写进 `besdk_lifecycle_log`，永久保存。
- **电子会计档案归档包**（业务功能，不是存储分层）：按 DA/T 94 输出凭证、账簿、报表的版式文件（OFD / PDF，经 `infra/print`）+ XML 元数据 + 移交清册。它依赖本文的封存与摘要链，但它是 finance 的一个新功能，要不要做见 §9 第 6 点。

### 4.9 删除权：擦除账本、限制处理、跨层

- **主体登记**：新登记表 `registry/data-subjects.tsv`（只增）：`subject`、`owner`（拥有主数据的组件）、`description`。初稿：`customer`（mdm/customer）、`contact`（mdm/customer）、`user`（infra/iam-casdoor）、`supplier`（mdm/supplier）、`employee`（hrm/*）。
- **流程**：治理组件（或任何组件的 `_lifecycle/erasures` 端点）发 `infra.governance.erasure.requested.v1 {request_id, subject, subject_id}` → 每个声明了该主体的组件，SDK 在一个事务里按表按列执行：`delete`（删行或置空列）、`anonymize`（替换成稳定的假名，如 `客户-7f3a`，同一主体同一假名，报表仍可分组）、`restrict`（不改数据，登记限制处理：数据集发布时假名化、`ana` 不可见、普通业务界面仍可见并在审计日志记一笔）→ 回执 `<id>.lifecycle.erasure_completed.v1 {request_id, tables: [{table, action, rows, basis}]}`。
- **冷层**：`s3-parquet` 下，受影响单元重写受影响的文件（copy-on-write），清单出新版本，旧对象删除；`iceberg` 下写删除文件（便宜）。因此**可擦除的表不能用 WORM（对象锁）冷存储**；反过来，法定保留的 ledger 表没有个人信息列（§4.2 不变式），可以放 WORM——两条规则合起来，"不可篡改"和"可擦除"永远落在不同的表上。
- **擦除账本** `besdk_erasures(request_id, subject, subject_id, received_at, applied_at, result)`：只记主体的不透明 id，不记被擦的内容。它同时镜像一份到对象存储 `_erasures/` 前缀（只追加），原因见 §4.10。
- **`crypto-shred`（P3）**：主体级数据密钥加密 `pii` 列，擦除 = 删密钥。它是唯一能让**备份里和 JetStream 里**的副本同时失效的办法，代价是这些列不能在库里做条件查询和排序。适合个人信息重的组件（未来的 `hrm/*`），作为 `PiiProtector` 适配器，配 `KeyStore` 端口（本地表 / Vault Transit）。

### 4.10 备份与 PITR

- **库**：pgBackRest / WAL-G 一类工具负责（运维文档 `docs/en/04-operations/` 的范围）。生命周期这边只保证与之协同：
- **PITR 回到冻结之前**：单元在库里又是挂载状态，对象存储里也有文件。引擎启动时对账（`Reconcile`）：清单摘要与库内状态一致就把单元当作 `VERIFIED` 继续，不重复导出。
- **PITR 回到 DROP 之后**：库里是 `COLD`，文件在。对象存储的保留要比 PITR 窗口长，这一条写进部署说明。
- **孤儿对象**（库被回滚到导出之前，对象却已写出）：对账时找不到对应单元状态的清单标为孤儿，超过 PITR 窗口再删。
- **擦除被回滚**：PITR 把 `besdk_erasures` 也回滚了，所以引擎启动时读对象存储里的 `_erasures/` 镜像，重放库里缺的擦除（G10）。没配冷存储时，由治理组件重新发出未完成回执的请求；两者都没有时，运维手册写明"恢复后重放擦除"的手工步骤。这是 GDPR 实践里公认的做法（备份不逐个改，恢复后重新执行删除）。
- **冷冻缩小备份**：真正降低 RTO 的是冷冻——基础备份只含热温两层。

### 4.11 多租户

- 今天没有租户列（I10 只在 JWT 里加 `tenant_id`）。契约先留好 `tenant_key`：声明后，冷层文件按 `tenant=` 分目录，**一个租户下线**就是删它在每个单元里的文件 + 库里的行（按行单元执行），不用重写别的租户。
- 租户级覆盖：`DATA_LIFECYCLE.tenants.<id>.tables.<t>.retention.min` 只能调长；一个单元里各租户期限不同时，单元的销毁按最长的那个，短期租户的行用行级删除提前清掉。
- 横向扩展的方向：Citus 按 schema 分片与"每组件一个 schema"同构（每个组件的 schema 落在一个节点），按租户分片则要求租户列进主键——**这是要不要现在就给业务表加 `tenant_id` 的方向性问题**，见 §9 第 1 点。

### 4.12 分析：组件发布数据集

- `dataset.publish: true` 的表，组件把**冷冻单元**自动登记为数据集分片（零成本，冷冻本来就写了 Parquet）；`DatasetPublisher=watermark` 时再按 `(updated_at, version)` 水位把在线数据增量导出成"镜像"分片（每小时一次，最新版本覆盖）。删除靠 tombstone 行。
- 数据集结构 = 表的列 − `exclude` − 受限列（假名化），带 `v<版本>`；列只增不删（0302 推广到数据集；表上真的删列时数据集版本升一级，旧版本照样可读）。
- `ana/*` 组件经查询引擎读，**按数据集授权**（对象存储凭据或 Trino 目录权限），不拿业务库凭据。DuckDB 在 Python 的 `ana` 组件里嵌入式读，正合适（py-brain 外壳，不受 Go 的 cgo 限制）。
- `debezium` 发布器（P3）：给要分钟级延迟的场景；它只抓本组件 schema 的表，输出仍是数据集结构（用 Debezium 的转换把表行映射成数据集行）。

### 4.13 成本量级（估算，用于判断优先级，不是报价）

假设一个中型客户：每年 50 万张订单 × 8 行、400 万条库存流水、300 万条分录行；堆表 + 索引约 8 GB / 年。

| | 十年在线（热温） | 封存 2 年后冷冻 |
|---|---|---|
| 库容量 | 约 80 GB，加从库和备份副本约 300 GB 云盘 | 约 16 GB，加副本约 60 GB |
| 对象存储 | — | Parquet 通常比堆表 + 索引小一个数量级，约 8 GB |
| 月费（按云盘约 1 元 / GB·月、对象存储标准层约 0.12 元 / GB·月的量级） | 约 300 元 | 约 60 元 + 1 元 |
| 全量恢复时间 | 几十分钟到小时级 | 分钟级 |

结论：中小客户的存储钱不是主要矛盾，**真正的收益是恢复时间、从库重建、VACUUM、大版本升级和换库时要搬的数据量**；客户规模大两个数量级时钱也变成主要矛盾。所以冷层的优先级排在 P1，而不是 P0。

### 4.14 SDK API 与平台表

**Go**（`github.com/brickKit/be-sdk-go/v1/lifecycle`，最终路径随 `sdk-redesign.md`）

```go
func Load(fsys fs.FS, cfg besdk.Config, opts ...LoadOption) (*Engine, error)  // 读声明 + DATA_LIFECYCLE + 校验不变式
func WithCalendar(Calendar) LoadOption                                        // fiscal_year_end 锚点
func WithGuard(name string, g Guard) LoadOption                               // 命名守卫
func WithCheckpointer(table string, c Checkpointer) LoadOption

func (e *Engine) Run(ctx context.Context, s *besdk.Store) error              // 阻塞；单轮失败只记日志
func (e *Engine) EnsureAhead(ctx context.Context, s *besdk.Store) (Report, error)
func (e *Engine) Window(table string, r Range, p Page) (Window, error)       // ErrRangeCold
func (e *Engine) ColdList(ctx context.Context, table string, f Filter, w Window) ([]Row, Cursor, error)
func (e *Engine) Locate(ctx context.Context, s *besdk.Store, table string, ids []string) (map[string]Tier, error)
func (e *Engine) Seal(ctx context.Context, tx *besdk.Tx, table, unit string) error   // on_signal
func (e *Engine) Verify(ctx context.Context, s *besdk.Store, table string) (VerifyReport, error)
func (e *Engine) Mount(r besdk.Router)                                        // /_lifecycle/* 与 gRPC besdk.lifecycle.v1

// 端口（适配器实现，组件代码不碰）
type ColdStore interface {
    Capabilities() StoreCaps                       // worm, row_delete, catalog
    Put(ctx context.Context, u UnitRef, src RowStream) (Manifest, error)
    Open(ctx context.Context, m Manifest) (RowStream, error)
    Rewrite(ctx context.Context, m Manifest, drop func(Row) bool) (Manifest, error)   // 擦除
    Delete(ctx context.Context, m Manifest) error
}
type ColdQuery interface {
    Capabilities() QueryCaps                       // list, scope_predicate, order_by, aggregate
    List(ctx context.Context, ds Dataset, f Filter, c Cursor, limit int) ([]Row, Cursor, error)
}
type Dialect interface { /* EnsurePartition, ListUnits, DetachConcurrently, Drop, Attach, InstallSeal, … */ }
```

Planner 是纯函数 `Plan(decl, state, now) []Action`，Executor 只执行动作——这样一致性向量（§5.3 ①）测的是 Planner，真库测试测的是 Executor，AI 改规则时只动纯函数。

**Python**（`besdk.lifecycle`）同名同义；P0 只需要 print 用到的 queue / platform 类，冷层适配器 `besdk[cold]` 可选安装（pyarrow 体积大，print 用不到）。能力缺失时 Python 引擎在加载声明时就报"本 SDK 不支持 cold"，不在运行期才失败。

**平台表**（SDK 平台迁移，`IF NOT EXISTS`，P0 一次建齐）：

```sql
CREATE TABLE besdk_lifecycle_units (
  table_name text NOT NULL, unit_key text NOT NULL,
  range_from timestamptz, range_to timestamptz, list_value text,
  state text NOT NULL,            -- ACTIVE/BLOCKED/SEALED/EXPORTING/EXPORTED/VERIFIED/COLD_PENDING_DROP/COLD/THAWED/DESTROYED
  rows bigint, min_id text, max_id text,
  unit_digest bytea, chain_digest bytea, manifest_url text, manifest_sha256 bytea,
  sealed_at timestamptz, cold_at timestamptz, thawed_until timestamptz, destroyed_at timestamptz,
  blocked_reason text, version bigint NOT NULL DEFAULT 1, updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (table_name, unit_key));
CREATE TABLE besdk_lifecycle_log (id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, at timestamptz NOT NULL DEFAULT now(),
  table_name text, unit_key text, action text NOT NULL, actor text, detail jsonb NOT NULL);   -- 追加型，封存触发器保护
CREATE TABLE besdk_holds (hold_id text PRIMARY KEY, scope jsonb NOT NULL, reason text NOT NULL,
  placed_by text NOT NULL, placed_at timestamptz NOT NULL, released_at timestamptz);
CREATE TABLE besdk_erasures (request_id text PRIMARY KEY, subject text NOT NULL, subject_id text NOT NULL,
  received_at timestamptz NOT NULL, applied_at timestamptz, result jsonb);
CREATE TABLE besdk_exports (job_id text PRIMARY KEY, requested_by text NOT NULL, spec jsonb NOT NULL,
  state text NOT NULL, result_url text, created_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz);
```

---

## 5. 适配器、槽位族还是组件

### 5.1 判定

| 东西 | 它是什么 | 按哪条决策 | 结论 |
|---|---|---|---|
| 生命周期引擎（Planner + Executor） | 每个组件进程里、对自己 schema 做的机制 | 原则 1（单独能跑）、0102（不碰别人的 schema） | **SDK**。做成组件就得替所有组件动它们的 schema，或者让每个组件依赖它 |
| PostgreSQL / openGauss / 金仓 | 数据库 | 0106（基础设施不是组件） | **`Dialect` 适配器**（SDK 内部） |
| 对象存储（RustFS / MinIO / S3 / OSS） | 基础设施 | 0106：换 `S3_URL` 即可 | 不需要适配器（S3 API 已是端口）；**冷数据格式**才是要做成适配器的（`ColdStore`） |
| Iceberg 目录（Lakekeeper / Polaris） | 基础设施 | 0106 | `ColdStore=iceberg` 适配器 + 地址配置 |
| 查询引擎（Trino / ClickHouse） | 基础设施（官方镜像 + 配置） | 0106 | **`ColdQuery` 适配器** + `LAKE_QUERY_URL` |
| DuckDB | 库 | — | Go 侧不可用（cgo）；Python `ana` 组件直接用 |
| Debezium | 基础设施（Debezium Server 镜像） | 0106 | `DatasetPublisher=debezium` 适配器 |
| 治理（保全、DSAR、销毁审批、报表） | 有业务逻辑、有界面、有自己的数据 | 0104 (a) 不成立：说不出第二种合理实现 | **普通组件 `infra/data-governance`**，不是槽位族；任何组件不依赖它（只走事件） |
| 冷层 vs 无冷层、scan vs trino | 不同客户的不同部署形态 | 0104 是给"组件"的规则 | 不是槽位族——这些位置不在组件图里，**是 SDK 端口**。0104 的精神（多种合理实现、不能被依赖、族契约先定）照样适用：端口契约先定、组件只依赖端口、靠一致性测试 |

**这需要一条新决策（草拟 0109）**：基础设施不是组件（0106 不变），但 SDK 对一类基础设施支持多个产品时，产品选择是 SDK 端口后面的适配器，用一个配置值选，并且每个适配器必须通过同一套一致性测试、输出能力矩阵。0106 里"换事件总线是一次迁移，不是一个设置"那句保留——事件总线只有一个适配器，没有多实现的需求；本文的几个端口有。

### 5.2 端口与适配器清单

| 端口 | 适配器 | 阶段 | 能力 | 何时选它 |
|---|---|---|---|---|
| `Dialect` | `pg-native` | P0 | detach_concurrently、list_partition、seal_trigger | 默认（PG ≥ 14、托管 PG、PG 兼容库） |
| | `opengauss` / `kingbase` | 按触发 | 视实测 | 信创交付（D5） |
| `ColdStore` | `none` | P0 | — | 小客户、不想管对象存储；**也是降级证明** |
| | `s3-parquet` | P1 | row_delete（重写）、worm（桶支持对象锁时） | 默认 |
| | `iceberg` | P3 | row_delete（删除文件）、catalog、time_travel | 已有湖仓 / 要给 Snowflake、Databricks、Doris 零拷贝 |
| `ColdQuery` | `none` | P0 | — | 冷数据只走导出和解冻 |
| | `scan` | P2 | list、scope_predicate、order_by（单元内） | 默认（组件自带，不加基础设施） |
| | `trino` | P3 | 上面全部 + aggregate、跨单元排序 | 历史查询多、数据量大 |
| `DatasetPublisher` | `none` / `watermark` / `debezium` | P0 / P2 / P3 | freshness、deletes | `ana` 上线时选 `watermark` |
| `PiiProtector` | `plain` / `crypto-shred` | P0 / P3 | erase_backups | `hrm/*` 或个人信息重的客户 |
| 温层编码（可选） | `heap` / `columnar` | P0 / P3 | compress | 封存分区占空间大、又不想冷冻（需 Citus / Hydra 扩展） |

替换的代价（新判据要求"只需小而简单的改动"）：

- 同一 SDK 版本内换适配器：**只改 `DATA_LIFECYCLE` 一个值**，`brickkit up`。
- 需要新适配器的 SDK 版本：组件升 SDK（`go.mod` 一行 + 发补丁版本），没有代码改动。
- 冷存储从 `s3-parquet` 换到 `iceberg`：数据文件不动，引擎对已有单元补注册目录（一次性 `lc.Migrate`）。反向同理。
- 冷查询换实现：无数据迁移。
- `Dialect` 换库：热温两层要搬（pg_dump / 逻辑迁移），冷层不动——这正是"冷层用开放格式"给换库带来的好处。

### 5.3 一致性测试套件 `be-acceptance/lifecycleconf/`

照 `authzconf` 的结构，五层：

| 层 | 内容 | 怎么跑 | 断言 |
|---|---|---|---|
| ① 规划向量 `vectors/*.json` | `{declaration, overrides, now, units[state, bounds, open_rows, holds], caps}` → `{actions[], blocked[], errors[]}`，几百条 | Go、Python 的 Planner 读同一组向量（`make sync-vectors`） | 逐字相同：起算点、下限、保全、守卫、降级（cold_store=none 时不出 Export 动作）、校验错误点名 |
| ② 引擎黑盒（真 PG） | 夹具组件 `fixtures/widget`（复用 authzconf 的夹具，补齐 8 类表各一张、分区表与行单元各一）；模拟时钟走 40 年 | 每个 `Dialect` 适配器跑一遍；两个副本 + 两个外壳成员并发 | G1–G6、G9、G11：窗口、封存拒写的 SQLSTATE、单元状态、在线区间、读结果；**每个状态迁移点注入崩溃**，重启后结果与不崩溃相同 |
| ③ 冷存储往返 | 属性测试：随机行覆盖项目用到的全部类型（`NUMERIC(18,2)`/`(18,6)` 边界值、`TIMESTAMPTZ` 1900 / 2262 之外的拒绝、空串与 NULL、Unicode、JSONB、BIGINT 极值） | 每个 `ColdStore` 适配器 | 冻结 → 解冻 → 规范摘要相等；**用第三方工具（DuckDB CLI 容器）独立读 Parquet + 清单并算出同一摘要**，证明"开放格式"不是只有我们能读；擦除重写后摘要链只在受影响单元变化；WORM 存储拒绝可擦除表 |
| ④ 冷查询 | 查询向量（等值、范围、IN、数据范围谓词、游标、排序、金额精度）跑在同一份冻结夹具上 | 每个 `ColdQuery` 适配器 | 各适配器结果逐行相同；**层级透明性**（属性）：任意范围 R、过滤 F，冻结前 `List(R,F)` = 冻结后（开冷查询）= 解冻后；`none` 恰好在冷区间答 `RANGE_COLD` |
| ⑤ 擦除端到端 | 主体 S 的数据分布在热、温、冷、数据集、导出 | 全栈（夹具 + 每个适配器组合） | 擦除后任何读取路径都拿不到 S 的个人信息；`restrict` 的行仍在且被登记；模拟 PITR（恢复擦除前的库快照）后启动，擦除被自动重放 |

**输出**：能力矩阵（适配器 × 能力 × 通过 / 正确降级 / 失败）写进 `dev/test-records/`。**门禁** `lifecycle-scan`（进 `make gates`）：每个组件迁移里出现的表都在 `lifecycle.yaml` 里有声明；ledger 表没有 `pii` 列；cold 表的 NUMERIC 有精度；声明的 `requires`（如某组件要求 `cold_query.list`）⊆ 部署所选适配器的能力。

### 5.4 它为 brickKit 证明了什么

- **"基础设施不是组件"和"基础设施可替换"可以同时成立**：替换发生在 SDK 端口后面，靠配置值和一致性测试，组件图、组件代码、组件契约都不变。这是 brickKit 理念里"平台只管组装"的自然延伸：平台不需要知道冷存储是什么。
- **原则 1 在新存储上仍然成立**：`brickkit up --focus erp/sales` 起来的 sales 带着自己的生命周期引擎、自己的 schema、自己的对象存储前缀，不需要任何别的组件（治理组件不装也能下保全、做擦除）。
- **外壳只合并进程**：引擎的锁键由 schema 派生、维护连接用成员角色，外壳里 N 个成员各跑各的，互不阻塞（引擎黑盒的并发用例证明）。

---

## 6. 影响与落地

### 6.1 各组件声明初稿（交各组件 AGENTS 确认）

| 组件 | 表 → 类别（关键设置） |
|---|---|
| mdm/customer | `customers` master（hot none，name 匿名化、tax_id 限制）；`contacts` master（姓名匿名化，电话邮箱删除）；`billing_infos` master |
| mdm/product | `products` 等 master / reference（hot none） |
| erp/sales | `sales_orders` + `items` document（seal 18 个月、cold 5 年、retention 10 年、review）；`pricelists*` reference；`customer_snapshots` snapshot；`sales_order_reconciliation_queue` queue（events-consistency 已定退役） |
| erp/inventory | `inventory_movements` ledger（seal immediate，cold 需 `inventory_period_balances`）；`inventory_balances` master；`inventory_reservations` document（关闭后 1 年行级删除）；`warehouses` reference；`product_tracking_snapshots` snapshot |
| erp/finance | `finance_journal_entries` ledger（不分区、永久在线、retention 30 年 after fiscal_year_end）；`finance_journal_entry_lines` ledger（on_signal 封存、cold 10 年、需 `account_period_balances`、守卫 `open_receivables`）；`ar_ledger` / `ap_ledger` document；`fiscal_years` / `accounting_periods` / `accounts` reference；`customer_credit_exposure` master；`customer_credit_snapshots` snapshot |
| crm/opportunity | `opportunities` + `items` document（不分区 → 行单元；cold 默认 never）；`opportunity_stage_history` audit；`opportunity_stages` reference；`customer_snapshots` snapshot |
| infra/authz | 角色、键 reference；`role_changes` audit（retention 3 年、≥ 6 个月下限） |
| infra/iam-casdoor | `refresh_tokens` queue（过期后删）；`signing_keys` reference；`webhook_deliveries` queue（90 天，守卫 RECEIVED）；`user_event_versions` platform-like snapshot |
| infra/workflow | `workflow_tasks` document（不分区，行单元）；`workflow_task_actions` audit |
| infra/notification | `notification_records` queue（1 年，三种未结束状态守卫）；`notification_preferences` master；`user_contacts` snapshot（主体 user，删除） |
| infra/print | `print_templates*` reference；`print_jobs` queue（180 天） |
| integration/im-dingtalk | `delivery_attempts` queue（180 天）；`dingtalk_user_map` snapshot（主体 user，按手机号删除）；`dingtalk_token` platform-like |

### 6.2 分阶段，契约在 P0 一次定全

**P0：组外壳（T21–T24）之前**——和上一份议题一、三、四合进同一次组件发版（2.1.0）：

1. `lifecycle.yaml` v1 的全部字段、8 个类别与不变式、`DATA_LIFECYCLE` 结构（含 P1–P3 才有实现的适配器名，未实现的选了就启动失败并说"本 SDK 版本不支持"）。
2. 平台表全部建齐（§4.14）；`_lifecycle` 资源契约（OpenAPI 片段 + gRPC `besdk.lifecycle.v1`）全部端点挂出，未实现的答 `501 capability_unavailable`（与 authz 的降级写法一致）。
3. 引擎实现：EnsureAhead、platform / queue 到期（DETACH CONCURRENTLY）、封存与摘要链（含 `on_signal`）、保全、热温两层擦除、`Window` / `Locate` / `RANGE_COLD`、Planner 纯函数与 `lifecycleconf` ①②⑤（热温部分）。
4. 各组件：写 `lifecycle.yaml`；删 `partition/`；List 请求加 `include_cold`（只增字段，P0 一次加齐）；configSchema 加 `DATA_LIFECYCLE`、`S3_ACCESS_KEY_ID`、`S3_SECRET_ACCESS_KEY`（可选）；finance 的 `LockPeriod` 调 `lc.Seal`；mdm 两个组件 `hot: none`。
5. be-ops：不再建 `<schema>_archive`；生成 `_lifecycle` 的三把权限键；`registry/data-subjects.tsv`；门禁 `lifecycle-scan` 先只警告。

**P1（随 06c 之后）**：`ColdStore=s3-parquet`、冻结 / 校验 / 解冻 / 销毁审批 / 导出任务；`lifecycleconf` ③；finance 的 `account_period_balances`、inventory 的 `inventory_period_balances`（它们也是业务功能，走各自的七步流程）；be-ops 生成每组件对象存储前缀的桶策略。
**P2**：`ColdQuery=scan`、`lifecycleconf` ④；`infra/data-governance` 组件；`DatasetPublisher=watermark`（`ana` 启动时）。
**P3（按触发条件）**：`iceberg`、`trino`、`debezium`、`crypto-shred`、`columnar` 温层、信创 `Dialect`、电子会计档案归档包。

**为什么 P0 之后不再改契约**：组件看到的只有声明格式、SDK API、`_lifecycle` 端点、错误码和 `include_cold` 字段，这些在 P0 全部定型；P1–P3 新增的只是适配器实现和能力位。组件在后续阶段只需升 SDK、改配置值。唯一例外是"新业务功能"（结转表、归档包），它们本来就是组件自己的需求。

### 6.3 先写的红测试

**be-sdk-go `lifecycle`（Planner，纯函数，P0）**

- `TestPlan_ledger声明pii列_加载失败并点名列`
- `TestPlan_覆盖保留期低于下限_加载失败`
- `TestPlan_fiscal_year_end锚点_从会计年度终了次日起算`
- `TestPlan_保全覆盖的单元_不出现Destroy与Erase动作`
- `TestPlan_cold_store为none_不出现Export且不删业务单元`
- `TestPlan_review到期_只生成销毁清单不直接Destroy`
- `TestPlan_cold表的NUMERIC没写精度_加载失败`
- `TestPlan_可擦除表配WORM存储_加载失败`

**be-sdk-go `lifecycle`（Executor，真 PG，P0）**

- `TestSeal_有未关闭行_单元BLOCKED并记录前100个id`
- `TestSeal_封存后UPDATE被拒_映射为UNIT_SEALED`
- `TestSeal_on_signal与业务事务同成败`
- `TestVerify_改动已封存单元的一行_摘要链校验失败`
- `TestExpire_用DETACH_CONCURRENTLY_父表上的长读不被阻塞`（另开一个持有父表 ACCESS SHARE 的长事务，断言新查询不排队；在上一份的普通 DETACH 写法上是红的）
- `TestExpire_维护连接用完即关_池中连接的role与search_path不受影响`
- `TestRun_外壳两个成员并发_互不阻塞`、`TestRun_两个副本并发_同一步只有一个执行`
- `TestWindow_请求范围跨冷区间_返回RANGE_COLD并带cold_ranges`
- `TestLocate_按min_max_id定位冷单元`
- `TestErase_热温两层_delete_anonymize_restrict各自生效并写回执`
- `TestErase_假名对同一主体稳定`
- `TestCrash_每个状态迁移点注入崩溃_重启后结果一致`（P0 覆盖到 SEALED；P1 补到 COLD）

**be-sdk-python**：Planner 向量全部；print 用到的 queue / platform 执行用例；`test_load_声明cold但未装besdk_cold_加载即报错`。

**be-acceptance**：`lifecycleconf` ①② 的骨架与夹具；门禁 `lifecycle-scan`：`TestScan_迁移里有表未声明_报出表名`、`TestScan_ledger表有phone列_报错`。

**每个组件**：`TestLifecycle_声明的表都存在且分区键与声明一致`（`besdktest.AssertLifecycle`）；finance：`TestLockPeriod_同事务封存该期间分区`；mdm：`TestList_主数据不注入默认时间窗口`。

**P1 起**：`TestFreeze_导出期间读不漏行`（冻结流程中并发全范围读，行数恒等，在上一份"先 DETACH"的顺序上是红的）、`TestThaw_表加列后解冻_新列取默认值`、`TestReconcile_PITR回到冻结前_不重复导出`、`TestReplayErasures_PITR后从对象存储镜像重放`、第三方 DuckDB 独立校验摘要。

---

## 7. 对比表与理由（可直接转成正式文档 `docs/en/05-foundations/data-lifecycle.md` 的骨架）

**我们的选择**：同表分层（热 / 温挂载在原生分区父表上，温层封存只读并入摘要链）+ 冷层开放格式（Parquet + 清单，存组件自己的对象存储前缀，可查询、可解冻）+ 声明式生命周期契约（8 类表、驻留期与保留期分离、保全、擦除）+ SDK 端口与适配器（一致性测试证明可换）。

| 方案 | 优点 | 缺点 | 为什么选 / 不选 | 何时切换 |
|---|---|---|---|---|
| **同表分层 + 开放格式冷层（选定）** | 一个 schema、读路径单一、无 DDL 漂移；冷层任何引擎都能读；换库只搬热温；法定保留、擦除、保全都有明确语义 | 要自己写引擎、状态机和适配器；冷查询能力取决于适配器 | 满足 R1–R12 的唯一组合；不需要任何库扩展 | — |
| 摘进 `<schema>_archive`（旧约定） | 冷数据仍可 SQL 查 | 两个 schema、DDL 漂移、路由、不省空间 | 只换了地方，没换层 | 不切换 |
| pg_partman | 成熟、托管 PG 普遍支持 | 配置在组件 schema 外、高权限后台进程、绕开守卫 | 破 0102 隔离；我们反正要状态机 | 不切换；只借鉴预建与按边界 |
| TimescaleDB | 追加型大表压缩 90%+、连续聚合 | TSL 许可、托管支持少、换引擎是迁移、压缩块难擦除 | 不作运行期适配器 | 单张 ledger / audit 表在线超过约 1 TB 且不能冷冻时，做一次性转换（Revisit） |
| Citus columnar / 分布式 | 温层压缩；schema 分片与本项目同构 | 扩展依赖；分布式要求分片键进主键 | 登记为 P3 温层编码与横向扩展方向 | 单库撑不住或客户要求在线保留全部历史时 |
| Iceberg | 事实标准表格式、行级删除便宜、零拷贝 | 要目录服务；Go 写入较新 | 作为 `ColdStore` 的 P3 适配器，数据文件与默认适配器相同 | 客户已有湖仓，或擦除频繁到重写 Parquet 太贵 |
| 全表 CDC 进分析库 | 实时、能抓删除 | 等于直查别人的 schema、没有契约、复制槽风险 | 破 0102 | 只作为组件自己的数据集发布器（P3） |
| 应用层归档表 / 软删除 | 简单 | 不是生命周期 | 不用于生命周期 | 回收站需求出现时单独做 |
| 一切留在主表（Odoo 式） | 零开发 | 大客户靠 DBA、无法定保留语义 | 不满足 R3、R4、R9 | 不切换 |

**决策记录影响**：

- 新增 **0305 数据生命周期按表声明、由 SDK 执行**（类别、驻留期与保留期、保全、擦除；取消 `<schema>_archive`；"何时重议"：出现 PG 原生分区承载不了的单表规模）。
- 新增 **0306 冷数据是组件自有的开放格式数据集**（Parquet，组件前缀与凭据隔离，分析只读发布的数据集）。
- 新增 **0109 基础设施产品是 SDK 端口后的适配器**（§5.1）。
- 修订 **0102**：What this rules out 去掉 archive schema 的隐含前提；Revisit 一节点名"对象存储冷层就是'自己的存储'这一条的实例"。
- 约定 **02-backend.md** Database 一节第 134、137 行重写（分区、封存、冷层、`Window` 取代 `ListWindow`）；`07-registries.md` 去掉 `_archive`、加 `data-subjects.tsv`。
- 根 `AGENTS.md` Pitfalls 新增四条：①在业务代码里 UPDATE 已封存单元（`UNIT_SEALED`，应该新建冲销 / 退货单）；②给 ledger 表加个人信息列；③在池化连接上跑 `DETACH CONCURRENTLY`（会话级 SET 泄漏）；④列表绕过 `lc.Window` 自己拼时间条件（冷区间被静默截断）。

---

## 8. brickKit 反馈候选（未经重建验证，先进 `dev/phase-06/to-verify.md`，验证后才写给 brickKit）

1. **组件级维护任务**。brickKit 有一次性迁移容器（`05-migration/01-migration-service.md`），没有定期任务（grep `cron` / `scheduled` 无结果）。冷冻导出、对账、重建索引、报表这类重活今天只能塞进服务进程。候选：`component.yaml` 声明 `deployment.maintenance: {command, schedule}`，compose 生成一个带循环的伴随服务、k8s 生成 CronJob，配置与主服务相同（同迁移的环境透传）。对所有用户都有用（备份、清理、报表）。
2. **文档写明"迁移每次 `up` 都重跑"可以被依赖来做时间相关的幂等工作**（例如按当天建分区窗口），以及 k8s Job 的 `backoffLimit: 0` 意味着这种工作失败一次就要等下一次 `up`。已在 `01-migration-service.md:67,96` 读到行为，候选是把它写成模式。
3. **configSchema 片段复用**。SDK 定义的一组键（`DATA_LIFECYCLE`、`S3_*`）要在每个组件的 configSchema 里各抄一遍，AI 很容易漏抄或抄错。候选：允许 configSchema 引用一个版本化的片段（例如 SDK 仓库发布的 JSON），`brickkit lint` 展开校验。
4. **组件文档规范加一节"数据与保留"**（`03-component-guide/08-component-doc-spec.md`）：组件保存哪些个人信息、法定保留多久、怎么擦除。部署方在"Before you deploy"之外最需要知道的就是这个，AI 读组件时也能直接找到。
5. **`brickkit remove` 与数据**：需要先核实 remove 是否碰数据库或外部存储；若不碰，文档写明"移除组件不删除它的数据，保留与销毁归项目负责"，避免有人以为 remove 等于清数据。
6. **09-patterns 增加"基础设施适配器 + 一致性测试"一页**：说明 0106 一类规则下怎样仍然让基础设施可替换，让其他用户不必重新推导。

---

## 9. 需要你拍板的点（只列业务口径与方向）

1. **★部署形态**：主要面向"单客户私有化"，还是也要支持"多租户 SaaS"？后者意味着现在就给业务表加 `tenant_id` 列并进主键（越晚越贵），并把租户下线、租户级保留期排进 P1。推荐：契约先留 `tenant_key`（已在 P0），列的事等你定。
2. **★各业务表的保留口径由谁定**：本文 §6.1 的期限（订单 10 年、凭证 30 年、审计 3 年、队列 90–365 天）是按法规和惯例起草的。是组件作者给默认值、项目逐表确认，还是交给每个客户的法务在部署时覆盖（下限不变）？订单是否算"涉税资料"按 10 年保留，也需要一个口径。
3. **★冷数据的用户体验**：用户查三年前的订单时，"提示已归档，可一键导出或申请解冻"够不够（P1 就能给），还是必须像今天一样在列表里直接翻到（要 P2 的冷查询）？
4. **★到期销毁**：非财务数据（订单、商机、审计日志）过保留期后，默认自动销毁、走审批，还是永久保留？财务数据按会计档案办法必须走鉴定和审批，这一点不需要选。
5. **★自然人客户的删除口径**：个体户客户要求删除时，订单与凭证上的名字在保留期内"限制处理"（照常保存、不再用于营销和分析，审计可见），过期后匿名化。同意这个口径吗？
6. **★电子会计档案归档包**：要不要把"按 DA/T 94 输出年度会计档案（版式文件 + 元数据 + 移交清册）"作为 finance 的正式功能排进路线图？这是"仅以电子形式保存会计档案"的合规前提，也是对外宣传的卖点。
7. **第二个"证明可换"的实现要不要提前建**：authz 那边你选了尽早建第二个真实成员（A6）。这里推荐的证明组合是 `ColdStore: none ↔ s3-parquet`（P1）和 `ColdQuery: none ↔ scan`（P2），都便宜；如果想像 A6 一样更早逼出契约偏差，可以把 `iceberg` 或 `trino` 提前到 P2。
8. **治理组件 `infra/data-governance`**：做（统一的保全、删除请求、销毁审批界面与合规报表），还是只靠每个组件的 `_lifecycle` 管理端点 + 运维手册？推荐 P2 做，它也是对外"隐私合规"能力的承载点。
