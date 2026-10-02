[English](../../en/04-foundations/25-search.md) · [中文](25-search.md)

# 搜索

用户怎样输入编码、名称的一部分、拼音或首字母找到一条记录：组件自己列表上的 `q` 参数，它背后那一列规范化的搜索文本，怎样按数据库装了哪些扩展来选索引，结果怎样排序，以及以后跨组件搜索的方向。读者是要给列表加 `q`、要改哪些字段可搜，或者想提议上搜索引擎的人。

## 范围

- **覆盖：** 组件自己 `List` 上的 `q`；`search_text` 列及其规范化（大小写、全半角、拼音、首字母）；按探测到的扩展选索引策略；带 `q` 时的排序和翻页；转义；让每个 SDK 结果一致的共享向量；全局搜索槽位族。
- **不覆盖：** 与 `q` 组合的数据范围谓词（[20-authorization-provider.md](20-authorization-provider.md)）；游标和翻页字段（[15-user-api-and-errors.md](15-user-api-and-errors.md#列表)）；翻译后的名称作为搜索文本的来源（[26-i18n-data.md](26-i18n-data.md)）；附件内容检索和分析，等全局族出现时归它。

## 选择

- **组件内的搜索是 SDK 帮手，不是一个单独的服务。** 匹配条件必须和数据范围谓词、游标在同一条 SQL 里；由另一个进程回答的列表，可能显示用户无权看到的行，也可能漏掉他能看到的行（[20](20-authorization-provider.md) 的 List/Can 一致）。
- **一列规范化的 `search_text`**，由组件声明的字段随行一起写入：原文、全拼、首字母，做过大小写和全半角折叠。"zgyh" 能找到"中国银行"；拼音搜索从第一版起就是必备。
- **一个谓词，三种速度。** 每次查询都是 `search_text LIKE '%<q>%'`。SDK 在启动时探测一次数据库，并确保最合适的索引存在：有 `pg_bigm` 用 bigram GIN 索引，有 `pg_trgm` 用 trigram GIN 索引，都没有就不建。这两个扩展都是可选能力，从不是必需的（[03-database.md](03-database.md#能力清单)）。三种情况返回的行完全相同，只是快慢不同。
- **排序**：与 `q` 完全相等的段（编码、名称、全拼或首字母），然后是以 `q` 开头的段，然后是任意包含；并列时按列表自己的排序。
- **跨组件的全局搜索是以后的槽位族** `infra/search-*`，由事件喂数据，按调用方的访问权限过滤。现在什么都不建；下面只预留它的契约形状。

**状态**：已就位：mdm/customer 和 mdm/product 接受 `q`，用 `strpos(lower(code|name), lower(q))` 匹配，前缀命中排前；没有索引支撑，没有拼音，两个列表还叠加了一个 90 天窗口，3.0.0 统一升级会去掉它（去掉之后就是全表扫描）。已定（随 3.0.0 统一升级和 SDK v0.6.0）：这一列、规范化及其向量、探测与索引管理、排序、SQL 收进 SDK。以后：全局搜索族。

## 端口契约

### 搜索列

| 列 | 类型 | 规则 |
|---|---|---|
| `search_text` | `TEXT NOT NULL DEFAULT ''` | 由组件在写这一行的同一条语句里写入，每次插入、每次更新来源字段时都写 |
| `search_text_v` | `SMALLINT NOT NULL DEFAULT 0` | 生成这个值的规范化版本 |

- 拼音在 SQL 里算不出来，所以值由代码生成，不用触发器。
- **来源字段**由组件按可搜索的表逐表声明：通常是 `code`、`name`、`name_i18n` 的每一个值（[26](26-i18n-data.md#可翻译列)），以及实体有的话，用户填写的助记码。
- 规范化版本升高时，一个可续跑的回填任务（[19-background-jobs.md](19-background-jobs.md)）重写 `search_text_v` 更低的行。
- **来源字段含个人信息，`search_text` 就含个人信息**：某个来源字段是个人数据（联系人电话）时，组件要把 `search_text` 列进该主体的擦除列（[09-data-lifecycle.md](09-data-lifecycle.md#擦除)）。

### 规范化，第 1 版

对每个来源字段分别处理，然后用 `U+001F` 把各段连起来，这个字符用户输入不了：

1. Unicode NFKC（全角转半角、兼容字符）。
2. 小写（Unicode 简单大小写折叠）。
3. 分段：折叠后的原文；对含汉字的文本，再加不带声调的全拼（`zhongguoyinhang`）和首字母（`zgyh`）。
4. 多音字取向量规定的读音；每个官方 SDK 把自己的拼音库（`go-pinyin`、`pypinyin`、`pinyin-pro`）对齐到这份输出，库的结果不一致的地方带一张覆盖表。

查询词按第 1、2 步折叠，去掉首尾空白，内部连续空白合成一个，去掉控制字符，截到 64 个字符。`%`、`_` 和 `\` 被转义，按字面匹配。

期望输出放在 `be-protocol` 的 `vectors/search/` 里，这一组还只是提案，尚未写出；每个 SDK 的测试将读它。

### 查询

```sql
-- $1 = 转义并规范化之后的 q
WHERE <数据范围谓词> AND <列表过滤条件>
  AND search_text LIKE '%' || $1 || '%' ESCAPE '\'
ORDER BY CASE
           WHEN position(chr(31) || $1 || chr(31) IN chr(31) || search_text || chr(31)) > 0 THEN 0
           WHEN position(chr(31) || $1 IN chr(31) || search_text) > 0                      THEN 1
           ELSE 2
         END,
         <列表自己的排序键>, id
```

- 只用内建运算符：查询不需要组件的 `search_path` 上有任何扩展。
- 带 `q` 时，游标编码排名、排序键和最后一个 ID；`q` 计入过滤条件的哈希，所以换了 `q` 还用旧游标会答 `400 CURSOR_INVALID`（[15](15-user-api-and-errors.md#列表)）。
- 规范化之后为空的 `q` 等于没有搜索条件。
- 组件代码绝不用字符串格式化拼这段 SQL：片段和参数都由 SDK 给出。

### 索引策略

| 平台迁移时探测（`pg_extension`） | SDK 确保存在的索引 | 对谁快 |
|---|---|---|
| 有 `pg_bigm` | `CREATE INDEX CONCURRENTLY IF NOT EXISTS <table>_search_text_idx ON <table> USING gin (search_text <扩展所在 schema>.gin_bigm_ops)` | 所有查询，包括两个字的中文 |
| 否则有 `pg_trgm` | 同上，换成 `gin_trgm_ops` | 三个字符及以上的查询；更短的会扫整个索引 |
| 都没有 | 不建 | 只适合小表 |

- SDK 从 `pg_extension` 读出扩展所在的 schema，自己给运算符类加限定名，因为组件的迁移里不许出现限定名。它在平台迁移里执行：以属主身份、在专用的迁移连接上，因为运行角色没有 DDL 权（[03](03-database.md#角色)）；绝不在运行期、绝不在请求里执行。每次 `up` 都会重跑迁移步骤，所以新装的扩展在那时被探测到。
- 扩展由 `make db-init` 在每个库里装一次；组件从不执行 `CREATE EXTENSION`。两者都是数据库端口的可选能力（[03-database.md](03-database.md#能力清单)）：缺了只是搜索变慢，绝不阻止启动。
- 选定的策略在启动时记一次日志。

### 全局搜索（槽位族，以后）

预留下来，以便建它的时候任何组件的契约都不用改：

- **成员**：`infra/search-pg`（默认：在它自己的 schema 里用 PostgreSQL 全文检索加 bigram 索引）、`infra/search-meilisearch`、`infra/search-opensearch`。一份族契约，像 authz、iam 两个族一样单独成仓库。
- **数据来源**：每个属主声明哪些资源类型可被全局搜索；成员消费它们的事件，建一份投影 `{type, id, owner, title, search_text, updated_at, deleted}`。新成员靠属主的 `List` 回填重建投影，因为流只保留七天。
- **查询**：经边缘的 `GET /api/search?q=&types=&page_size=&cursor=`。候选结果用各属主的 `_authz/check`（每次最多 500 个）做后过滤，不够一页就继续多取。调用方看不到的东西永远不会返回；没有精确总数。
- **寻址**：共享变量 `SEARCH_URL`；任何组件都不依赖成员（[0104](../02-decisions/01-architecture/0104-variants-become-slot-families.md)、[0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)）。

## 备选方案

| 方案 | 中文 | 运维 | 许可证 | 权限过滤 | 说明 |
|---|---|---|---|---|---|
| **规范化列 + LIKE，按探测选索引**（选用） | 子串、拼音、首字母 | 不新增 | — | 同一条 SQL | 由 SDK 负责 |
| 原始列上 `strpos` / `LIKE`（现状） | 子串，没有拼音 | 无 | — | 同一条 SQL | 全表扫描 |
| 只用 `pg_trgm` | 三个字以上；两字查询慢 | 内置扩展 | PostgreSQL | 同一条 SQL | 托管服务普遍提供 |
| 只用 `pg_bigm` | 为 CJK 设计 | 要安装的扩展 | PostgreSQL | 同一条 SQL | 托管库和信创库上是否可用不一 |
| zhparser、pg_jieba（中文分词全文检索） | 词好，没有拼音 | 带词典的扩展 | — | 同一条 SQL | 阿里云 RDS 提供 zhparser |
| ParadeDB `pg_search`（BM25） | 取决于分词器 | 扩展 | AGPL | 同一条 SQL | 许可证有风险 |
| Meilisearch | 好，容错 | 单独的服务 | MIT（社区版） | 投影或后过滤 | 最轻的引擎 |
| Typesense | 尚可 | 单独的服务，数据全在内存 | GPL-3.0 | 投影或后过滤 | — |
| OpenSearch、Elasticsearch | 有 IK 和拼音插件，强 | JVM 集群 | Apache-2.0；Elastic 的几种许可证 | 投影或后过滤 | 大规模 |

## 为什么选它

- **访问控制和翻页在构造上就是对的**：匹配、数据范围和游标是属主自己库里的同一条语句。
- **拼音只实现一次**，每个 SDK 都按同一份向量实现，而不是每个组件各写一份。
- **单机部署不新增基础设施**，没有扩展的数据库照样答对。
- **只有一个谓词**，"三种策略返回同样的行"靠构造成立，而不是靠测三条代码路径。

## 为什么不选其他

- **列表用外部引擎**：要么把访问投影复制进去，要么做会破坏翻页的后过滤，而且每个部署多一个有状态服务；它没法回答组件自己的 `List`。
- **各组件各写 `LIKE`**：就是今天的状态；每个组件都会重写一遍折叠和拼音，而且写得不一样。
- **分词扩展**：要维护词典，可用性参差不齐，而且照样没有拼音和首字母。
- **`pg_search`**：AGPL。

## 什么时候换

- **某张可搜索的表超过约一百万行**，而且即使有 bigram 索引，实测的 `q` 延迟仍超过路由的预算：为这个类型启动全局族，或者加一种专用的索引策略。
- **要求跨实体搜索、搜附件内容，或者要容错和同义词**：建 `infra/search-pg`，实测需要时再建 Meilisearch 或 OpenSearch 成员。
- **数据库没有 `pg_bigm`**，两个字的中文查询很慢：装上它，或者接受 `pg_trgm` 的表现。

## 怎么换

- **索引策略**：用 `make db-init` 装扩展；下次 `up` 时平台迁移探测到它，并发地建好索引。组件不用改。
- **规范化**：be-protocol 出一版新向量，SDK 发一版；回填任务重写各行；组件只需升 SDK。
- **全局搜索**：`brickkit add infra/search-pg`，设置 `SEARCH_URL`，属主声明可搜索的类型。换成员就是 `brickkit remove` / `add` 加重建投影；属主和前端都不变。

## 一致性测试

- **向量**（提案）：be-protocol 的 `vectors/search/`（折叠、全半角、拼音、首字母、多音字、转义、排序）；每个官方 SDK 的测试都读它。
- **对真实数据库的 SDK 测试**，先写成红的：同样的数据和查询，三种策略返回完全相同的行；有 `pg_bigm` 时，两个字的中文查询 `EXPLAIN` 显示走了索引；`q` 里的 `%` 和 `_` 按字面匹配；换了 `q` 还用旧游标答 `CURSOR_INVALID`。
- **组件**：mdm/customer 和 mdm/product，`q=zgyh` 能找到"中国银行"。
- **依赖它之前实测一次**：`postgres:16-alpine` 上的 `pg_trgm` 到底能不能从中文里提取出三元组。
- **全局族**（以后）：套件 `tools/be-acceptance/conformance/search/`，对每个成员跑：索引延迟有上界，不可见的记录永不返回，删除的记录会消失，中文和拼音用例。

## 相关决策

- [0102 一个数据库，每个组件一个 schema](../02-decisions/01-architecture/0102-one-schema-per-component.md)：全局搜索读事件，从不读别人的 schema。
- [0104 槽位族需要多种合理实现，而且没有依赖边](../02-decisions/01-architecture/0104-variants-become-slot-families.md) 和 [0107 权限 bundle 与 token 公钥地址是共享变量](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)：搜索族和 `SEARCH_URL`。
- [0206 不用行级安全，不做共享引擎](../02-decisions/02-permissions/0206-no-row-level-security.md)：数据范围是同一条 SQL 里的谓词，所以 `q` 也必须在那条 SQL 里。
- 没有计划中的新决策；全局族建的时候再加它自己的。

## 已知限制

- **多音字**每个字只取一种读音；主人读法不同的名称可能需要助记码。
- 组件内**没有容错、同义词或相关度打分**；排序就是上面那三档。
- **繁体与简体还不折叠**；等有一份映射能在每个官方 SDK 里产出完全相同的结果，作为一个规范化版本加进来。
- **只有 `pg_trgm` 时，两个字的查询**会扫整个索引：结果对，只是慢。
- **`search_text` 让每一行可搜索的数据变大**，大约是来源字段的三倍。
- **全局搜索不存在**：顶栏的搜索只搜菜单。
