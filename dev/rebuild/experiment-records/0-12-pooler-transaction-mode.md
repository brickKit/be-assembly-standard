# 0-12 连接池代理的事务模式与 `SET LOCAL`、pgx 的预编译语句

## 1. 结论

**通过，有一条配置要求**。PostgreSQL 16 前面放事务模式的 PgBouncer（1.26.0），几个客户端共用同一条后端连接时，设计依赖的机制都成立：事务内 `SET LOCAL ROLE` 切到运行角色、事务结束即回到登录角色；以 `INHERIT FALSE` 获授的角色不切换就没有权限；`SET LOCAL statement_timeout` 只在事务内生效；事务级应用锁互斥；`FOR UPDATE SKIP LOCKED` 两个客户端认领到不同的行。项目规则禁止的两种写法也实测会出事：事务外的 `SET` / `SET ROLE` 泄漏给下一个客户端；会话级应用锁留在后端连接上，另一个客户端也能“拿到”。

**要求**：pgx 默认的执行模式（语句缓存，按名字预编译）要求 PgBouncer 开 `max_prepared_statements`（1.21 起支持协议层预编译语句）。设为 0 时 6 次里 3 次报“prepared statement … already exists”；设为 100 时全部正常。pgx 的其余四种模式在两种设置下都正常。

## 2. 测了什么、为什么

计划第 0 步：“连接池代理的事务模式与 `SET LOCAL`（以及 pgx 的预编译语句）”，对应套件 B1（数据库前加事务模式的连接池代理）与[数据库引擎与连接](../../../docs/zh/04-foundations/05-database-engine.md)“连接池代理可选；用的话必须是事务模式”。事务模式下会话状态不保留，所以要确认设计依赖的每一种“事务内设置”与语句在代理后面都成立，并确认驱动的默认行为能不能直接用。与 BrickKit 无关。

## 3. 环境与版本

| 项 | 值 |
| --- | --- |
| 数据库 | `postgres:16-alpine`（16.15） |
| 代理 | `edoburu/pgbouncer:latest`（PgBouncer 1.26.0），三个实例都是 `pool_mode = transaction`：`pb0` 池 1、`max_prepared_statements = 0`；`pb100` 池 1、100；`pbc` 池 4、100。池 1 让几个客户端必然共用一条后端连接 |
| 角色 | 登录角色 `r012_shell`（代表外壳）以 `WITH INHERIT FALSE` 获授运行角色 `r012_east`；表 `east.items` 属于属主角色 `r012_owner_east`，运行角色只有查询与更新 |
| 程序 | Go 1.26.0、pgx v5.7.5 的探针（`experiment-data/0-12/run1.txt` 附源码），每项打印 PASS、FAIL 或 HAZARD（HAZARD 表示“被规则禁止的写法确实出事”） |

## 4. 结果

| 项 | 池 1、预编译 0 | 池 1、预编译 100 | 直连 |
| --- | --- | --- | --- |
| 事务内 `SET LOCAL ROLE r012_east`，读 `east.items` | 成功，5 行 | 成功 | 成功 |
| 事务之后，A 与 B（同一后端连接）的 `current_user` | 都是 `r012_shell` | 同左 | 同左 |
| 不切换角色读 `east.items` | `permission denied`（`INHERIT FALSE` 有效） | 同左 | 同左 |
| 事务外 `SET search_path`、`SET ROLE`（禁止的写法） | **泄漏**：B 看到 `search_path=east`、`current_user=r012_east` | 同左 | — |
| `SET LOCAL statement_timeout = '100ms'` | 事务内取消（57014），下一个客户端看到 `0` | 同左 | — |
| pgx `CacheStatement`（默认） | **6 次失败 3 次**：prepared statement already exists | 6/6 | 6/6 |
| pgx `CacheDescribe`、`DescribeExec`、`Exec`、`SimpleProtocol` | 都 6/6 | 都 6/6 | 都 6/6 |

| 并发项 | 结果 |
| --- | --- |
| A 持有 `pg_advisory_xact_lock(42)`，B 尝试（池 4） | B 得到 `false` |
| A 用会话级 `pg_advisory_lock(7)`，B 在共用的后端连接上尝试（池 1，禁止的写法） | **B 得到 `true`**：锁属于后端连接，不属于 A |
| A、B 同时 `FOR UPDATE SKIP LOCKED LIMIT 1`（池 4） | A 认领 1，B 认领 2 |
| 20 个客户端各开事务 `pg_sleep(0.2)`（池 4） | 全部成功，1.07 s；同时段 `r012_shell` 的后端连接 6 条（其中 2 条是前两个代理留下的空闲连接，`pbc` 自己不超过 4 条） |

## 5. 观察

- **规则的理由都实测成立**：易错点表里“不带 `LOCAL` 的 `SET ROLE`、`SET search_path`”与“会话级应用锁”的症状，在代理后面就是本节的 HAZARD 两行：下一个借到同一后端连接的人在别人的角色与 schema 下执行，不报错。没有代理时，SDK 自己的共享池（外壳里成员共用登录连接）是同一种情形，第 2 步要在 SDK 的池上再测一遍。
- **预编译语句是唯一需要配置的地方**：PgBouncer 1.21 之前不支持协议层预编译语句；1.21 起要显式开 `max_prepared_statements`。其他代理（PgCat、Supavisor、Odyssey）的支持情况各不相同，实验只测 PgBouncer。
- `SET LOCAL ROLE` 搭配 `INHERIT FALSE` 的授予（PostgreSQL 16 的写法）经代理没有任何问题，这是外壳“登录角色不继承成员权限、事务里切换”的基础。

## 6. 影响

- **第 2 步 SDK**：
  - 一切设置都在事务内（`SET LOCAL`），这是现行规则，SDK 的事务入口照做；
  - 执行模式二选一，写进 SDK 与部署说明：要求代理开启协议层预编译语句（PgBouncer `max_prepared_statements > 0`），或在配置声明“经事务模式代理”时改用 `CacheDescribe` / `Exec`。倾向前者（不牺牲默认性能），但要支持后者，以便接不支持预编译的代理。已记进[交实现核对的项](../implementation-checks.md)的“数据库与运行时”一行，结论在第 14 步写进[数据库引擎与连接](../../../docs/zh/04-foundations/05-database-engine.md)。
- **套件 B1**：代理用 PgBouncer，开 `max_prepared_statements`；实验报告写明版本与这项设置。
- 不需要改设计。

## 7. 原始数据

`dev/rebuild/experiment-data/0-12/run1.txt`（含 `run012.sh` 与探针源码 `main.go`）
