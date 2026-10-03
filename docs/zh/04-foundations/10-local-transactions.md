[English](../../en/04-foundations/10-local-transactions.md) · [中文](10-local-transactions.md)

# 本地事务

一个组件内一个 PostgreSQL 事务的规则：隔离级别、每个事务都要设的超时、哪些错误会重试、加锁顺序、advisory 锁、事务里能做什么不能做什么，以及背后的连接预算。读者是写 repo 层代码的人、审这些代码的人、用一门新语言实现组件协议的人，以及想改某个默认值的人。

## 范围

- **在本文：** 一个组件自己 schema 里 `BEGIN` 和 `COMMIT` 之间的一切；每条不变式怎么挑隔离手段；数据库错误怎么离开事务；长事务和批量事务；限制同时能跑多少个事务的连接预算。
- **不在本文：** 跨两个组件的状态（事件、命令、saga、reconciler）：[11-consistency-across-components.md](11-consistency-across-components.md)。数据库引擎、它的版本承诺、连接池大小和连接池代理的规则：[03-database.md](03-database.md)。整个请求的时间预算：[16-deadlines-and-retries.md](16-deadlines-and-retries.md)。日常怎么写 repo 层：[02-backend.md](../01-conventions/02-backend.md#数据库)。

## 选择

1. **默认 READ COMMITTED**，每条不变式用显式的手段保证，从一个固定的阶梯里挑（约束、条件更新、按序行锁、事务级 advisory 锁、SERIALIZABLE）。单个事务可以要求 REPEATABLE READ 或 SERIALIZABLE；默认级别永远不变。
2. **每个事务用 `SET LOCAL` 自己设超时**：`statement_timeout`、`lock_timeout`、`idle_in_transaction_session_timeout`，PostgreSQL 17 及以上再加 `transaction_timeout`。不依赖角色级的默认值。
3. **序列化失败（`40001`）和死锁（`40P01`）自动重试**，做法是把整个事务体重跑一遍；这一层不重试别的任何错误。
4. **对多行加锁按固定顺序**（主键或业务键），请求里的重复项在加锁前就拒绝。
5. **advisory 锁只用事务级的**，锁键里包含组件的 schema。
6. **事务里不做网络调用。** 在事务里要对数据库之外产生效果，只有两条路：一行 outbox、一行作业队列，两者都在同一个事务里写入。
7. **不嵌套事务。** 一个工作单元同一时刻最多占一条连接。
8. **每个组件、外壳里的每个成员，各有自己的连接预算。**

**状态**：已定；随组件协议和 3.0.0 统一升级落地。今天事务按数据库默认设置跑，完全没有超时，没有重试，也不防网络调用；有三个消费者在持有事务时调用其他组件，多条目的预留按请求里的顺序给行加锁。

## 端口契约

契约是到达 PostgreSQL 的那些语句，这样任何语言的实现行为都一样。函数名由各 SDK 自己定。

**每个读写事务都以完全相同的这串语句开头：**

```sql
BEGIN ISOLATION LEVEL READ COMMITTED;            -- 或事务要求的级别
SET LOCAL ROLE <PG_USER of this component>;      -- 外壳里：成员自己的 PG_USER
SET LOCAL search_path TO <PG_SCHEMA>;
SET LOCAL application_name = '<component ID>';   -- 外壳里：成员的 ID
SET LOCAL statement_timeout = '<min(5s, remaining deadline)>';
SET LOCAL lock_timeout = '2s';
SET LOCAL idle_in_transaction_session_timeout = '30s';
SET LOCAL transaction_timeout = '<remaining deadline>';  -- 仅 PostgreSQL 17 及以上
```

- 角色和 schema 来自配置（`PG_USER`、`PG_SCHEMA`），绝不用代码里推导出来的名字。
- 用 `SET LOCAL`，绝不用 `SET`：没有 `LOCAL`，设置会留在池化的连接上，下一个借用者会继承它（[02-backend.md](../01-conventions/02-backend.md#数据库)）。
- **为什么按事务设、不按角色设：** `ALTER ROLE … SET` 只在登录时生效。外壳以自己的角色登录，再用 `SET LOCAL ROLE` 切换到各成员，所以成员角色的默认值在外壳里从来不会生效。登录角色上的角色级设置只是兜底（[03-database.md](03-database.md)），不是机制本身。
- "剩余截止时间"是调用方剩下的预算（[16-deadlines-and-retries.md](16-deadlines-and-retries.md)）。没有截止时间时，用上面的默认值。

**读快照**，用于必须在多条查询之间看到同一时刻的报表：`BEGIN ISOLATION LEVEL REPEATABLE READ READ ONLY`，同样的几行 `SET LOCAL`，`statement_timeout` 最多 30 秒。

**数据库错误怎么离开事务：**

| SQLSTATE | 含义 | 这一层怎么处理 | 对外表现为（code / reason，见 [15](15-user-api-and-errors.md)） |
|---|---|---|---|
| `40001` | 序列化失败 | 回滚，等待 `10 ms · 2^n` ± 抖动，重跑事务体；最多 3 次尝试 | 最后一次尝试之后：`ABORTED` / `TX_CONFLICT` |
| `40P01` | 检测到死锁 | 同 `40001` | 同上 |
| `55P03` | 拿不到锁（`lock_timeout`） | 不重试 | `ABORTED` / `LOCK_TIMEOUT` |
| `57014` | 语句被取消（`statement_timeout`） | 不重试 | `DEADLINE_EXCEEDED` / `STATEMENT_TIMEOUT`；取消来自调用方取消了请求时：`CANCELLED` / `REQUEST_CANCELLED` |
| `25P04` | 事务超时（PostgreSQL 17+） | 不重试 | `DEADLINE_EXCEEDED` / `STATEMENT_TIMEOUT` |
| `25P03` | 事务内空闲过久 | 服务端关闭了连接 | `INTERNAL`：这是组件的 bug |
| `53300` | 连接数过多 | 不重试 | `UNAVAILABLE` / `DB_TOO_MANY_CONNECTIONS` |
| `08` 类、`57P01`、`57P02`、`57P03` | 连不上、连接断开、服务器正在关闭或尚未接受连接 | 不重试 | `UNAVAILABLE` / `DEPENDENCY_UNAVAILABLE`，`metadata.dependency = db` |
| `23505` | 唯一约束冲突 | 不重试 | 组件把它映射成自己的 reason，通常是 `ALREADY_EXISTS` |

重试是在一个新事务里从头重跑事务体。这样做之所以安全，只是因为事务体除了这个事务什么都不碰，而这一点由下面两条规则保证。调用方想重试 `LOCK_TIMEOUT`，要在更上一层用同一个幂等键去重试。重试次数计入 `be_tx_retries_total{component,sqlstate}`（`sqlstate` 取 `40001` 或 `40P01`）。

**事务里不做网络调用。** 一个工作单元持有打开的事务时，运行时提供的每一种出站调用（gRPC、面向用户的 HTTP、直接向总线发布）都拒绝发起，并以 `INTERNAL` / `NETWORK_IN_TX` 失败：这是编程错误，在开发和测试中暴露出来（测试构建里直接让测试中止）。出口只有两个：

- 一行 outbox：事件在提交后发布（[12-event-bus.md](12-event-bus.md)）；
- 一行作业队列：命令在提交后、在任何事务之外执行（[19-background-jobs.md](19-background-jobs.md)）。

违反时的症状：行锁在下游的整段延迟里一直被占着，这一行上的其他请求全都排在它后面；重试事务体会把调用重复一遍；事件处理函数持有事务的时间超过总线的确认等待时间，消息会被重投，处理函数跑两次。

**不嵌套事务。** 同一个工作单元已经持有一个事务时再开一个，以 `INTERNAL` / `NESTED_TX` 失败。在本地写数据的事件处理函数拿到的是消费者的事务，不自己开。违反时的症状：连接池有了上限之后，一阵突发流量里每个 worker 都占着一条连接、等第二条，整个池就死锁了。

**advisory 锁**一律用事务级的：

```sql
SELECT pg_advisory_xact_lock(hashtext(current_schema() || ':' || $1), hashtext($2));      -- 等待，受 lock_timeout 限制
SELECT pg_try_advisory_xact_lock(hashtext(current_schema() || ':' || $1), hashtext($2));  -- 不等待，直接返回 false
-- $1 = 锁名；$2 = '<部分>|<部分>…'
```

绝不使用会话级 advisory 锁（`pg_advisory_lock`）：在池化连接上取的锁会留给下一个借用这条连接的人，而事务模式的连接池代理根本带不住它。锁键里的 schema，让两个用了同一个锁名的外壳成员不会互相阻塞；而同一个组件同时单跑和在外壳里跑时共用一个 schema，仍然互斥。

**长事务和批量事务。**

- 事件处理函数的本地写入预期在 1 秒内完成；更长的会记一条警告并计入一个指标。
- 回填、冻结和批量重算最多每 1,000 行提交一次，并记录进度，以便中断后续跑。
- 迁移 DDL 设 `lock_timeout = '5s'` 并重试；分区先用 `CREATE TABLE … (LIKE …)` 建出来，再 `ATTACH PARTITION`，后者只在父表上取 `SHARE UPDATE EXCLUSIVE`。直接 `CREATE TABLE … PARTITION OF` 要 `ACCESS EXCLUSIVE`；它一旦排在一个长事务后面，之后对这张表的每次读写都要排在它后面等，看起来就像整个组件卡死了。

**连接预算。** 每个组件都有配置键 `PG_POOL_MAX`（默认 10）：它最多占用的连接数。外壳里每个成员保留自己的 `PG_POOL_MAX`，作为外壳连接池里的一份预算。用完预算的成员最多等 `PG_POOL_ACQUIRE_TIMEOUT`（默认 5 s）或剩余截止时间，取较短者，然后以 `RESOURCE_EXHAUSTED` / `DB_POOL_EXHAUSTED` 失败；其他成员不受影响。连接池大小、连接寿命和连接池代理的兼容性见 [03-database.md](03-database.md)。

### 隔离手段阶梯

选第一个能表达这条不变式的台阶：

| 台阶 | 手段 | 本项目里的例子 |
|---|---|---|
| 1 | 约束：唯一（部分）索引、排他约束、check | "同一产品的两张价目表在时间上不重叠" |
| 2 | 条件更新：检查和写入放在一条 `UPDATE … WHERE <条件> RETURNING` 里（版本列就是这样一种条件） | 库存永不低于零；信用占用原子累加 |
| 3 | 按固定顺序加行锁：`SELECT … FOR UPDATE ORDER BY <键>` | 一个法人的各会计期间；一张预留的多条库存行，按 `(warehouse_id, product_id)` 排序 |
| 4 | 没有可锁的行时，对一个逻辑键取事务级 advisory 锁 | "一次只重算一个客户的信用" |
| 5 | 对这个事务用 `SERIALIZABLE`，配合自动重试 | 台阶 1 到 4 都表达不了的跨多行不变式 |

按领域的落点：

- **库存：** 台阶 2，多行请求再加按序加锁。
- **总账：** 锁期间行（台阶 3），借贷相等在事务内校验，报表走读快照。
- **信用：** finance 的原子更新是权威；sales 在确认前做的检查只是参考。
- **编号：** 无断号的编号（会计凭证，按期间编号）在编号序列那一行上取行锁，作为串行化点；允许断号的编号用 sequence（[04-identifiers-and-numbering.md](04-identifiers-and-numbering.md)）。

## 备选方案

| 做法 | 谁在用 | 长处 | 短处 |
|---|---|---|---|
| **READ COMMITTED 加显式手段**（选用） | PostgreSQL OLTP 的常见做法 | 热点行从不中止：PostgreSQL 会针对最新的行版本重新求值条件更新的 `WHERE` | 每条不变式都要选对台阶；报表要显式开快照 |
| REPEATABLE READ 加整个请求的全局重试 | Odoo（对 `40001`、`40P01`、`55P03` 重试，最多 5 次） | 每个请求看到同一个快照 | 并发更新同一热点行会以 `40001` 中止；重试的请求会把事务之外的副作用再做一遍 |
| 处处 SERIALIZABLE 加客户端重试循环 | CockroachDB、Spanner 一类系统 | 没有异常现象需要推敲 | 热点行（库存余额、会计期间）上的中止率；每个调用方都必须能安全重试 |
| 数据库旁边的逻辑锁服务 | SAP S/4 的 enqueue server | 锁在会话和步骤之间可见 | 又多一个服务；在 PostgreSQL 里 advisory 锁就是同一个东西，不用另起服务 |
| 只用乐观并发（版本列，不匹配就重试） | 很多 ORM、ERPNext 的 `modified` 检查 | 不持有锁 | 竞争下热点行会无休止地重试；它是阶梯的第 2 级，不是一整套策略 |

## 为什么选它

- **ERP 的两个热点**是 `inventory_balances`（每个产品每个仓库一行）和会计期间（每个法人一组）。在 READ COMMITTED 下，对它们的条件更新会等待，然后针对最新的行继续执行；在 REPEATABLE READ 或 SERIALIZABLE 下，同样的竞争变成中止和重试，用户感受到的就是延迟。
- **阶梯是显式的、可审的。** 每条不变式写明自己的台阶，审查者，不论是人还是 AI，都能拿手段去对照不变式，而不是信任一个全局级别。
- **按事务设的超时在两种形态下都生效。** 单跑和外壳里跑的是同样几行 `SET LOCAL`；不依赖任何登录时的角色设置，而外壳会悄无声息地跳过那些设置。
- **自动重试是安全的**，因为事务体碰不到网络，也开不了第二个事务。

## 为什么不选其他

- **REPEATABLE READ 加全局重试**把热点行上的竞争变成中止，而且重试会把请求在事务之外做过的事再做一遍。只有在事务之外什么都不做时它才安全，而这正是我们本来就强制的规则，所以全局重试只增加了中止，什么也换不来。
- **处处 SERIALIZABLE** 在热点行上有同样的中止问题，比例更高，而且迫使每种语言的每个调用方都写重试循环。
- **单独的锁服务**是又一套要运维的基础设施；事务级 advisory 锁在数据库内部就提供了同样的互斥。
- **只用乐观并发**在竞争下会空转；它作为阶梯里的一级保留下来，用于很少发生竞争的行。

## 什么时候换

- **单个事务换成 SERIALIZABLE：** 当一条不变式跨多行，而约束、条件更新、按序加锁、advisory 锁都表达不了它时。在调用处写注释说明原因。
- **默认级别：** 预期不会改。只有实测到阶梯表达不了的某类异常反复出现，才会重新讨论。
- **超时默认值：** 实测表明有一类正当的语句超过 5 秒（报表、导出）时，把这类语句挪到读快照或后台任务里；默认值保持短。

## 怎么换

- **单个事务的隔离级别：** 开事务的那个调用上的一个选项。不用迁移，不用配置。
- **单个事务的超时：** 同一个调用上的选项，在调用方剩余截止时间之内；更长的语句超时也绝不会超过截止时间。
- **连接预算：** 组件的 `config/<scope>-<name>.yaml` 里的 `PG_POOL_MAX`。
- **数据库引擎：** 见 [03-database.md](03-database.md)。在 PostgreSQL 方言族内换引擎，本文的规则一条都不变。

## 一致性测试

计划中的套件 `tools/be-acceptance/conformance/store/`，在 PostgreSQL 14、16 和 17 上对每个官方 SDK 跑。今天的行为过不了的用例，都先写成红的。

- 事务内 `SHOW statement_timeout` 和 `SHOW lock_timeout` 返回默认值（今天是红的：两者都是 0）。
- 截止时间剩不到 5 秒时，`statement_timeout` 等于剩余时间。
- SERIALIZABLE 下的写偏斜会被重试，其业务效果只发生一次。
- 人为制造的死锁（`40P01`）会被重试，事务最终成功。
- 测试持有一把锁超过 `lock_timeout` 时，请求在约 2 秒内以 `ABORTED` / `LOCK_TIMEOUT` 失败（从运行中的容器外部可观测）。
- 事务内的出站 gRPC 调用以 `NETWORK_IN_TX` 失败（今天是红的）。
- 在事务内再开事务以 `NESTED_TX` 失败。
- 连接池大小为 1 时，`SET LOCAL` 设过的东西在提交或回滚之后都不可见。
- 用 `SET LOCAL ROLE` 切换的外壳登录角色拿不到成员角色的 `ALTER ROLE … SET` 值（钉住本设计所依赖的 PostgreSQL 行为；今天是绿的）。
- 两个外壳成员用同一个名字取 advisory 锁，互不阻塞。
- 一个成员耗尽连接预算，不会拖慢另一个成员（今天是红的）。

统一升级前先写成红的组件测试：

- erp/inventory：两个订单以相反的顺序并发预留同样两个产品，都能完成，不报死锁错误（今天是红的）。
- erp/sales：一张信用被拒的订单正在挂起时，即使 infra/workflow 很慢（3 秒），取消同一张订单的耗时也不超过 500 毫秒（今天是红的）。
- erp/finance：应收汇总和它的明细行来自同一个快照。

## 相关决策

- [0501 事务里不发网络调用](../02-decisions/05-runtime/0501-no-network-inside-a-transaction.md)：本文是它的完整分析。
- [0502 默认 READ COMMITTED，配一架明确的阶梯](../02-decisions/05-runtime/0502-isolation-and-retry.md)：隔离手段阶梯、按事务设定的超时，以及对 `40001` / `40P01` 的重试。
- [0102 一个数据库，每个组件一个 schema](../02-decisions/01-architecture/0102-one-schema-per-component.md)：每个事务都以组件的角色在它自己的 schema 里运行。
- [0206 不用行级安全；共享引擎只有一个，在 authz](../02-decisions/02-permissions/0206-no-row-level-security.md)：范围限定写在静态查询里，所以事务不带按用户区分的数据库身份。

## 已知限制

- **只支持 PostgreSQL 方言族。** 换到别的引擎，意味着移植每个组件的 repo 层（[03-database.md](03-database.md)）。
- **无断号的凭证号让同一法人的过账串行化。** 一个法人的吞吐上限大约是每秒几十到一百张凭证；其他单据允许断号，不受这个限制。
- **自动重试只覆盖 `40001` 和 `40P01`。** 锁超时或语句超时会直接到达调用方。
- **`transaction_timeout` 从 PostgreSQL 17 才有**；在更老的服务器上，事务只受各条语句的超时和空闲超时约束。
- **`hashtext` 碰撞**会让两个不同锁名的无关操作互相等待；但绝不会让操作变得不安全。
- **网络防护只看得到经由运行时发起的调用。** 组件自己开 HTTP 客户端就绕过了它，这也是模块用到的一切都要来自运行时的又一个理由（[02-backend.md](../01-conventions/02-backend.md#rt-是唯一入口)）；标记手工构建客户端的门禁在计划中。
