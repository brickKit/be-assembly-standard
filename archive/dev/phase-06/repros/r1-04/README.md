# r1-04：预编译语句缓存 × `SET LOCAL ROLE` / `search_path`（asyncpg、node-postgres）

对应 sdk-redesign §7.9 第 4 条、foundations-data-platform DB-6；支撑 P10.2（每个事务开头 `SET LOCAL ROLE` + `SET LOCAL search_path`）在外壳共享物理池里的正确性。

## 假设

外壳里多个成员共用一个物理池。同一条物理连接上，成员 a 的事务之后紧跟成员 b 的事务，两者发出**完全相同的 SQL 文本**（不带限定名、靠 search_path 解析）。假设：

1. 驱动的预编译语句缓存不会让 b 读写到 a 的 schema（不会串数据）。
2. 两个 schema 里同名表形状不同时，最多报错，不会静默返回错误的数据。
3. `SET LOCAL` 在提交和回滚之后都不残留，归还到池里的连接是干净的。

## 环境与版本

| 项 | 版本 |
|---|---|
| PostgreSQL | 16.15（`postgres:16-alpine`，一次性容器 `r1-r1b-pg`） |
| asyncpg | 0.30.0，CPython 3.13（`python:3.13-slim` 一次性容器） |
| node-postgres（`pg`） | 8.23.1，Node v24.21.0（本机 fnm） |

库内布局（`setup.sql`）：成员角色 `ra`/`rb`（NOLOGIN），schema `a`/`b` 各归其主；外壳登录角色 `shell` 是 `NOINHERIT`，`GRANT ra, rb TO shell WITH INHERIT FALSE, SET TRUE`（P19.5）。三组表：

| 表 | schema a | schema b | 模拟什么 |
|---|---|---|---|
| `widget` | `(id int, v text)` | 同形，数据不同 | 正常情况：同 SDK 版本的平台表、同形业务表 |
| `besdk_thing` | `(id bigint, payload text)` | `(id bigint, payload jsonb, extra int)` | 两个成员的同名表形状不同（SDK 版本不一致，或两个组件恰好同名） |
| `besdk_same` | `(id bigint, payload text)` | 多一列 `extra int` | 列出的列同类型，但 `SELECT *` 的列数不同 |

## 步骤

```bash
docker run -d --name r1-r1b-pg -e POSTGRES_PASSWORD=pw -p 127.0.0.1::5432 postgres:16-alpine
./run.sh            # 每种模式前重建 r1db；asyncpg 跑在 python:3.13-slim 容器里，pg 用本机 Node 24
docker rm -f r1-r1b-pg
```

池固定为 1 条连接（`min_size=max_size=1` / `max: 1`），每个事务 `BEGIN; SET LOCAL ROLE; SET LOCAL search_path; <同一条 SQL>; COMMIT`，按 a、b、a、b 交替。每种驱动跑三种模式：

| 驱动 | 模式 | 含义 |
|---|---|---|
| asyncpg | `100` | 驱动默认：按 SQL 文本缓存预编译语句，每条连接 100 条 |
| asyncpg | `0` | `statement_cache_size=0`，不缓存 |
| asyncpg | `100 prefix` | 缓存开，SQL 前加 `/* be:<member> */ `，让缓存键按成员区分 |
| pg | `unnamed` | pg 的默认：不给 `name`，每次走未命名语句，不复用 |
| pg | `named` | `{ name: 's1', text }`：所有成员共用一个服务端命名语句（SDK 想提速时可能的写法） |
| pg | `named-member` | 命名语句的 `name` 里带成员（`a:s1`） |

## 原始输出（关键几行）

完整输出见 `output.txt`。

```
===== asyncpg 0.30.0, statement_cache_size=100, per-member SQL prefix=False
--- S1 same shape SELECT id, v FROM widget WHERE id=$1
  [a] OK   <Record id=1 v='from-a' s='a'>
  [b] OK   <Record id=1 v='from-b' s='b'>
--- S2 different result type: SELECT id, payload FROM besdk_thing
  [a] OK   <Record id=1 payload='a-text'>
  [b] ERR  InvalidCachedStatementError: cached statement plan is invalid due to a database schema or configuration change (sqlstate=0A000)
  [a] OK   <Record id=1 payload='a-text'>
  [b] ERR  InvalidCachedStatementError: ... (sqlstate=0A000)
--- S3 same listed types, b has extra col: SELECT id, payload FROM besdk_same     -> a/b 全部 OK
--- S3 SELECT * FROM besdk_same (column count differs)                             -> [b] ERR 0A000，每次切换都报
--- S4 INSERT INTO besdk_thing (id, payload) VALUES ($1,$2) (param text vs jsonb)
  [b] ERR  DatatypeMismatchError: column "payload" is of type jsonb but expression is of type text (sqlstate=42804)
--- S5 isolation: role ra with search_path b
  ERR (expected) UndefinedTableError: relation "widget" does not exist
--- S6 NOINHERIT: shell login without SET ROLE reads a.widget
  ERR (expected) InsufficientPrivilegeError: permission denied for schema a
--- S7 leak check after commit:   {'pid': 171, 'usr': 'shell', 'sp': '"$user", public'}
--- S7 leak check after rollback: {'pid': 171, 'usr': 'shell', 'sp': '"$user", public'}
--- bench: 2000 alternating member tx in 1.65s = 0.827 ms/tx
===== asyncpg 0.30.0, statement_cache_size=0          -> S1–S4 全部 OK；bench 0.985 ms/tx
===== asyncpg 0.30.0, statement_cache_size=100, per-member SQL prefix=True  -> S1–S4 全部 OK；bench 0.700 ms/tx
===== pg 8.23.1, mode=unnamed       -> S1–S4 全部 OK；bench 0.528 ms/tx
===== pg 8.23.1, mode=named         -> S2/S3* [b] ERR cached plan must not change result type (code=0A000)；S4 [b] ERR 42804
===== pg 8.23.1, mode=named-member  -> S1–S4 全部 OK；bench 0.466 ms/tx
```

（bench 是本机回环上的单连接串行事务，只看相对差异；两次完整运行之间同一模式的绝对值能差 20 %。）

## 结论

**假设 1 成立，假设 2 成立，假设 3 成立；但"缓存开"不是可以无条件使用的。**

- 不串数据：所有模式、两种驱动，S1 的读和写都落在当前 search_path 的 schema 上。PG 的计划缓存把 search_path 记在计划里，切换后会重新规划，所以同一条预编译语句在 b 里执行就是读 b。
- 形状不同就**确定性报错**，不会给错数据：结果类型变了是 `0A000 cached plan must not change result type`（asyncpg 包成 `InvalidCachedStatementError`），参数类型变了是 `42804`（首次 Parse 时推断出的参数类型被缓存）。报错不是一次性的：a、b 交替时，b 的每个事务都失败（asyncpg 在出错后丢掉这条缓存，a 再次 prepare，下次轮到 b 又失败）。asyncpg 只在事务**之外**自动重试这个错误，而 P10.2 要求一切都在事务里，所以没有自动恢复。
- 连接干净：提交、回滚之后，`current_user` 回到 `shell`，`search_path` 回到默认值，同一个 pid。
- 顺带发现：角色没有某个 schema 的 USAGE 时，search_path 里的这一项被**静默跳过**，报的是 `relation does not exist`，而不是权限错误（S5）。P10.7 的启动探测（`has_schema_privilege(current_user, current_schema(), 'USAGE,CREATE')`）正好覆盖它，必须保留。
- NOINHERIT + `WITH INHERIT FALSE, SET TRUE` 的组合按预期工作：不切角色时外壳角色读不到成员表（S6），`SET LOCAL ROLE` 后可以读写（S1）。

## 对设计的影响

1. **P10.2 不用改**：`SET LOCAL ROLE` + `SET LOCAL search_path` + 共享池在两种驱动上都是正确的，不需要每个成员一个物理池。
2. **SDK 必须让"缓存键"按成员区分**（建议写进 P10.2 的 INTERNAL 说明，三门 SDK 一致）：
   - Python（asyncpg）：保留缓存，`Tx` 的 `fetch`/`fetchrow`/`execute` 在 SQL 前面加 `/* be:<PG_SCHEMA> */ `。实测它消除了 S2–S4 的报错，速度和"缓存开"相当（0.70 vs 0.83 ms/tx），比"缓存关"（0.99 ms/tx）快。附带收益：`pg_stat_statements` 和慢查询日志可以按成员归属。单跑时前缀不变，也无副作用。asyncpg 的 `statement_cache_size` 在外壳里按成员数放大（默认 100 × 成员数），否则成员之间互相挤出缓存。
   - TS（pg）：保持 pg 的默认（未命名语句，不复用）。如果以后要用命名语句提速，`name` 必须带成员前缀（`<schema>:<name>`）。门禁可以加一条：TS 组件代码里不许直接传 `name`。
   - Go（pgx，本 lane 未测）：同样的机制（pgx 默认 `QueryExecModeCacheStatement`，按 SQL 文本缓存）。建议 R1a / Go SDK 用同一个前缀办法，而不是 foundations-data-platform DB-6 里提的 `QueryExecModeCacheDescribe`，并用本目录的 `setup.sql` 复测。
3. **平台 SQL 不许用 `SELECT *`、`RETURNING *`**（DB-6 已提，这里实测确认：多一列就足以触发 0A000）。前缀办法落地后，这条从"必需"降为"良好习惯"，但 P19.1 允许的"同一 SDK 版本"之外如果将来放宽，它仍是第二道保险。
4. **不要把 0A000 加进 P10.4 的自动重试**：用了前缀之后它不该再出现；万一出现，说明有人绕过了 `Tx`，应当报错暴露出来，而不是被重试掩盖。
