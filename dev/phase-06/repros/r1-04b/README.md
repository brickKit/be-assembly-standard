# r1-04b：pgx v5 的语句缓存 × `SET LOCAL ROLE` / `search_path`（r1-04 的 Go 补测）

r1-04 只测了 asyncpg 和 node-postgres，并建议 Go SDK 用同一个"SQL 前缀"办法、而不是 foundations-data-platform DB-6 提的 `QueryExecModeCacheDescribe`。本目录用 pgx 复测，复用 `../r1-04/setup.sql`。支撑 P10.2。

## 假设

1. pgx 默认的 `QueryExecModeCacheStatement`（按 SQL 文本缓存服务端命名语句）在两个成员同名表形状不同时，会像 asyncpg 一样报 `0A000` / `42804`，但不串数据。
2. `QueryExecModeCacheDescribe`（只缓存描述，每次走未命名语句）能避开这些错误。
3. 在 SQL 前加 `/* be:<schema> */ ` 能在保留缓存的前提下消除全部错误，且不比关缓存慢。

## 环境与版本

| 项 | 版本 |
|---|---|
| PostgreSQL | 16（`postgres:16-alpine`，一次性容器 `r1-x3-pg`，用完已删） |
| pgx | v5.10.0（与 `tools/be-sdk-go/go.mod` 一致），`pgxpool`，Go 1.26.0（本机） |

池固定 1 条连接（`MinConns = MaxConns = 1`），每个事务 `BEGIN; SET LOCAL ROLE; SET LOCAL search_path; <同一条 SQL>; COMMIT`，按 a、b、a、b 交替。场景 S1–S4、S7 与 r1-04 相同（S5、S6 是 PG 本身的行为，r1-04 已测，这里不重复）。结果用 `rows.Values()` 打出来，任何解码错位都能看见。注意 pgx 在**没有参数**时一律走简单协议，所以每条被测 SQL 都带 `$1`。

| 模式 | 含义 |
|---|---|
| `cache_statement` | pgx 默认：按 SQL 文本缓存命名预编译语句（每连接 512 条） |
| `cache_describe` | 缓存参数/结果描述，每次 Parse 未命名语句 + Describe Portal |
| `describe_exec` | 不缓存，每次先 Describe 再执行（两次往返） |
| `exec` / `simple_protocol` | 不缓存，按 Go 类型推参数 / 客户端插值 |
| `… prefix` | 同上，SQL 前加 `/* be:<schema> */ ` |

## 步骤

```bash
docker run -d --name r1-x3-pg -e POSTGRES_PASSWORD=pw -p 127.0.0.1::5432 postgres:16-alpine
PG_CONTAINER=r1-x3-pg ./run.sh > output.txt     # 每种模式前重建 r1db；go/ 下 go build 后依次跑 7 种模式
docker rm -f -v r1-x3-pg
```

## 原始输出（关键几行）

完整输出见 `output.txt`（第一次运行）。

```
===== pgx v5.10.0, mode=cache_statement, per-member SQL prefix=false
--- S1 same shape SELECT id, v FROM widget WHERE id=$1      [a] OK {1,"from-a","a"}  [b] OK {1,"from-b","b"}（每次都对）
--- S2 different result type: SELECT id, payload FROM besdk_thing
  [a] OK   {1, "a-text"}
  [b] ERR  cached plan must not change result type (sqlstate=0A000)      （a、b 交替时 b 每次都失败）
--- S3 SELECT * FROM besdk_same (column count differs)       [b] ERR 0A000
--- S4 INSERT INTO besdk_thing (id, payload) VALUES ($1,$2)
  [b] ERR  column "payload" is of type jsonb but expression is of type text (sqlstate=42804)
--- S7 leak check after commit / rollback: pid=75 usr=shell sp="$user", public
===== mode=cache_describe, prefix=false
--- S2 SELECT id, payload FROM besdk_thing     [b] OK {1, map[b:jsonb]}     （列数相同：按服务端真实类型解码，正确）
--- S2 SELECT * FROM besdk_thing               [b] ERR bind message has 2 result formats but query has 3 columns (sqlstate=08P01)
--- S3 SELECT * FROM besdk_same                [b] ERR 08P01（同上）
--- S4 INSERT ...                              [b] ERR 42804（缓存的参数 OID 仍是 a 的 text）
===== describe_exec / exec / simple_protocol, prefix=false      -> S1–S4 全部 OK
===== cache_statement prefix=true / cache_describe prefix=true  -> S1–S4 全部 OK；S7 连接干净
```

基准（2000 个交替成员的事务，单连接，本机回环，ms/tx；三次完整运行）：

| 模式 | 第 1 次 | 第 2 次 | 第 3 次 |
|---|---|---|---|
| `cache_statement`（默认，无前缀） | 0.421 | 0.452 | 0.411 |
| `cache_statement` + 前缀 | **0.380** | **0.410** | **0.353** |
| `cache_describe`（无前缀） | 0.445 | 0.479 | 0.459 |
| `cache_describe` + 前缀 | 0.434 | 0.446 | 0.418 |
| `describe_exec` | 0.507 | 0.489 | 0.478 |
| `exec` | 0.472 | 0.418 | 0.441 |
| `simple_protocol` | 0.451 | 0.435 | 0.425 |

（每个事务 5 次往返，其中 `BEGIN`、两条 `SET LOCAL`、`COMMIT` 都没有参数、走简单协议，被测查询只占一次往返，所以模式之间的差距被摊薄；只看相对顺序。）

## 结论

| 假设 | 结论 |
|---|---|
| 1 默认模式像 asyncpg 一样报错 | **成立**。`cache_statement` 下 S2、S3（`SELECT *`）报 `0A000`，S4 报 `42804`，与 asyncpg 完全相同；每次切到 b 都失败（pgx 出错后把这条语句标为失效、下次空闲时 `DEALLOCATE`，a 重新 prepare，轮到 b 又失败）。pgx 在事务里不重试。不串数据：S1 的读写始终落在当前 search_path 的 schema |
| 2 `CacheDescribe` 能避开 | **不成立**。它只躲开了"列数相同、类型不同"（S2 列名列表，因为每次发 Describe Portal、按服务端真实类型解码）；列数不同时 Bind 带的是缓存的结果格式个数，报 `08P01 bind message has 2 result formats but query has 3 columns`；参数类型仍用缓存的 OID，S4 照样 `42804`。连接本身没断（同一 pid） |
| 3 前缀能修且保留缓存 | **成立**。`cache_statement` + 前缀 S1–S4 全部正确，三次都是最快的一档（比默认无前缀快约 10 %，因为 a、b 不再共用一条命名语句、PG 不必在每次 search_path 变化后重新规划）；三次运行里也都快于最快的不缓存模式（差 2–17 %） |

没观察到"静默给错数据"：所有失败都是确定性的报错。

## 对设计的影响

1. **P10.2 的 INTERNAL 说明对 Go 写死：保持 pgx 默认 `QueryExecModeCacheStatement`，`Tx` 的 `Query`/`QueryRow`/`Exec` 在 SQL 前加 `/* be:<PG_SCHEMA> */ `**，与 Python 一致。三门 SDK 的规则就统一成"缓存键必须包含成员 schema"：Go、Python 用前缀，TS 用未命名语句或带成员的 `name`（r1-04）。
2. **foundations-data-platform DB-6 里"Go 改用 `QueryExecModeCacheDescribe`"这条要撤掉**：实测它挡不住列数不同（`08P01`）和参数类型不同（`42804`）。
3. 外壳里 pgx 的 `StatementCacheCapacity`（默认 512）是一个连接上所有成员共用的，成员多时应按成员数放大，和 asyncpg 的 `statement_cache_size` 同理。
4. 前缀之外仍不许绕过 `Tx` 直接用 `pgxpool.Pool.Query`（没有前缀、也没有 `SET LOCAL`）；门禁的 import/调用扫描保持不变。`0A000`、`08P01` 都不进 P10.4 的自动重试。
5. 顺带：两条 `SET LOCAL` 是每个事务固定的两次往返，占了基准时间的大头。Go SDK 可以把它们合成一条 `SELECT set_config('role', …, true), set_config('search_path', …, true)`，或者放进 `BEGIN` 后的同一个简单协议批里；这不影响正确性，是否要做留给 Go SDK 实现时测。
