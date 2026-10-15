[English](../../../en/02-decisions/05-runtime/0502-isolation-and-retry.md) · [中文](0502-isolation-and-retry.md)

# 0502 默认 READ COMMITTED，配一架明确的阶梯；只重试序列化失败和死锁

**状态**：已决定，随 3.0.0 统一升级落地。

## 决策

- **每个事务默认在 READ COMMITTED 下运行。** 单个事务可以要求 REPEATABLE READ 或 SERIALIZABLE；默认值永不改变。
- **每个不变量点名它的手段**，取固定阶梯上第一个能表达它的那一级：约束；条件更新；按固定顺序加行锁；键里带组件 schema 的事务级 advisory 锁；只对这一个事务用 SERIALIZABLE，并在调用处注释写明原因。
- **多行按固定顺序加锁**（主键或业务键），请求里的重复项在加锁之前就拒绝。
- **每个事务用 `SET LOCAL` 设定自己的超时**：`statement_timeout` 取 `min(5 s, 剩余截止时间)`，`lock_timeout` 2 s，`idle_in_transaction_session_timeout` 30 s，PostgreSQL 17 及以上再加 `transaction_timeout`。角色级设置只作兜底。
- **运行时只重试 `40001` 和 `40P01`**，做法是在新事务里重跑整个事务体：最多 3 次，`10 ms · 2^n` 加抖动，之后答 `ABORTED` / `TX_CONFLICT`。锁超时和语句超时在这一层不重试。
- **advisory 锁只用事务级。**

## 理由

ERP 的热点（每个产品 × 仓库一行库存余额、一个法人的会计期间）争用激烈。在 READ COMMITTED 下，对它们的条件更新会等待，然后基于最新的行继续；全局更严的级别会把同样的争用变成中止和重试，用户感受到的就是延迟。每个不变量点名一级阶梯，评审时就能对照这个不变量检查手段，而不是信任一个全局级别。按事务设定的超时在单跑和外壳里行为一致，而外壳里 `SET ROLE` 之后成员角色的设置从不生效。自动重试之所以安全，只因为事务体碰不到网络（[0501](0501-no-network-inside-a-transaction.md)）。3.0.0 之前，多品预留按请求顺序加锁、可能死锁，而且什么都不重试。

## 挡下什么

- "为了保险"调高默认隔离级别
- 按请求列出的顺序给多行加锁
- `pg_advisory_lock` 或任何会话级锁；不带 schema 的 advisory 键
- 不带 `LOCAL` 的 `SET`，或依赖 `ALTER ROLE … SET` 设定超时
- 在组件代码里给事务套重试循环，或在上一层重试 `LOCK_TIMEOUT` 却不带同一个幂等键

## 何时重新讨论

出现一类经测量、反复发生、阶梯上任何一级都表达不了的异常时。

完整分析：[10-local-transactions.md，隔离手段阶梯](../../04-foundations/10-local-transactions.md#隔离手段阶梯)和[选择](../../04-foundations/10-local-transactions.md#选择)。
