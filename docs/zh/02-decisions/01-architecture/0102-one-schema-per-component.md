[English](../../../en/02-decisions/01-architecture/0102-one-schema-per-component.md) · [中文](0102-one-schema-per-component.md)

# 0102 一个数据库，每个组件一个 schema

**状态**：为 3.0.0 修订（库身份只来自配置、属主角色与运行期角色分开、库句柄、平台表、NOINHERIT 外壳、取消归档 schema，改为组件自己 bucket 里的冷层）；已决定，随 3.0.0 统一升级落地。

## 决策

所有组件共用一个 PostgreSQL 方言族的数据库：单独运行的组件要求 PostgreSQL 14 及以上，外壳要求 16 及以上（因为它的 NOINHERIT 授权），或任何讲它的线上协议并通过数据库套件 `tools/be-acceptance/conformance/db/` 的引擎。每个组件拥有一个 schema 和两个角色（属主角色和运行期角色），都取自 `registry/schemas.tsv`；迁移状态表放在自己的 schema 里；从不读、写或 JOIN 别的组件的 schema。别的组件拥有的数据通过该组件的 API 获取（按 id 列表取用 `BatchGet`，见 [0304](../03-contracts-and-data/0304-batch-get-takes-at-most-500-ids.md)）。

- **库身份只来自配置。** 属主角色是 `PG_OWNER_USER`，运行期角色是 `PG_USER`，schema 是 `PG_SCHEMA`；三者都必填、都没有默认值、谁也不从谁推导。迁移里不出现任何角色名或 schema 名。
- **属主角色与运行期角色分开。** 属主（`PG_OWNER_USER` / `PG_OWNER_PASSWORD`，一个登录角色）拥有表、做全部 DDL；迁移和平台迁移以它登录。运行期角色 `PG_USER` 只有 DML，不是属主角色的成员；运行中的服务只用它。运行期少数必须的 DDL（提前建分区、装封存守卫、删过期的平台分区）经由属主创建的 `SECURITY DEFINER` 函数。一条已记录的限制：brickKit 给迁移容器的环境和主服务相同，所以服务也会拿到属主凭据；SDK 从不使用它们，等 brickKit FR06-013（只给迁移的变量）落地后，就只有迁移容器拿到。
- **每一次访问都经过 SDK 的库句柄**：它在每个事务里用 `SET LOCAL` 设定角色、`search_path` 和超时；outbox 泵、消费者和后台任务也走它。
- **SDK 拥有的表**（`besdk_*`）放在组件自己的 schema 里，由 SDK 的平台迁移建；组件的 SQL 从不碰它们。
- **外壳的登录角色什么都不拥有**：它以 `WITH INHERIT FALSE, SET TRUE` 被授予每个被托管成员的运行期角色 `PG_USER`（从不授予属主角色），只有 `SET LOCAL ROLE` 之后才能干活。
- **没有归档 schema。** 以前每个组件的 `<schema>_archive` 取消了。热数据和温数据留在组件自己的表里；冷数据离开数据库时只进组件自己 bucket 里的冷层，放在 `cold/<table>/…` 之下，用组件自己的凭据，只有这个组件读写它（[09-data-lifecycle.md](../../04-foundations/09-data-lifecycle.md)）。

## 理由

一个数据库、每个组件一个 schema，外壳就能让成员共享一个物理连接池，同时每个成员的角色仍是一道权限墙：外壳借出一条连接，用 `SET LOCAL ROLE` 切到成员的角色，提交时自动复位。每个组件一个数据库就无法共享连接池，而一旦有了数据再改就是数据迁移。库身份只从配置来、并在一处 SDK 代码里按事务切换，模块就不可能误借另一个成员的 schema；NOINHERIT 让外壳自己即便出错也碰不到任何一张表。属主与运行期角色分开，运行期 SQL（一次注入、一条 AI 写错的语句）就没法 `DROP` 或 `ALTER` 一张表。归档 schema 只是把旧行挪进第二个 schema，带来自己的漂移和路由；组件自己 bucket 里的开放格式文件保住同一道归属墙，又不让数据库变大。迁移工具默认把状态表放在 `public`；放在那里，各组件会互相覆盖迁移历史。

## 挡下什么

- 每个组件一个独立数据库，或"给这个组件单独一个 Postgres 实例"
- 跨 schema 的 `JOIN`、建在别的组件表上的视图、直接查别的组件 schema 的报表
- 从一个组件的表指向另一个组件的表的外键
- 把迁移状态表（`schema_migrations`、`_yoyo_migration`）留在 `public`
- 在池化连接上执行不带 `LOCAL` 的 `SET ROLE` / `SET search_path`：下一个借用者会继承它，悄无声息地读到别的组件的数据
- 从 schema 推导角色（`<schema>_rw`）、给 `PG_SCHEMA` 写默认值、把角色名或 schema 名写进迁移
- 运行中的服务以属主角色登录或切到属主角色；运行期角色是属主角色的成员；组件代码里的 `SET ROLE`
- 每个组件一个归档 schema（`<schema>_archive`），或任何存放旧数据的第二个 schema；组件之间共用的冷数据 bucket，或一个组件读另一个组件的冷文件
- 组件 SQL 读写 `besdk_*` 表；模块在库句柄之外自己开连接池
- 自己编 schema 名或角色名，而不是从 `registry/schemas.tsv` 照抄

## 何时重新讨论

- 某个组件需要 PostgreSQL 提供不了的存储能力，或必须用另一个数据库实例。届时它通过自己的配置获得自己的存储，在外壳里也有自己的池；它仍然绝不直接读别的组件的数据。
- 在分区和只读副本之后，单库写入经测量成为瓶颈。路线是 Citus 基于 schema 的分片；组件之间本来就不碰彼此的 schema，所以组件无需任何改动。

完整分析：[03-database.md，选择](../../04-foundations/03-database.md#选择)。
