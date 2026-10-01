[English](../../../en/02-decisions/01-architecture/0002-one-schema-per-component.md) · [中文](0002-one-schema-per-component.md)

# 0002 一个数据库，每个组件一个 schema

## 决策

所有组件共用一个 PostgreSQL 数据库。每个组件拥有一个 schema 和一个角色，两者都从 `registry/schemas.tsv` 中抄写；迁移状态表放在自己的 schema 里；绝不读写、也不 JOIN 别的组件的 schema。别的组件拥有的数据，通过该组件的接口获取（一批 id 用 `batchGet`）。

## 理由

一个数据库加每组件一个 schema，外壳才能让成员共享一个连接池，同时每个成员的角色仍是一道权限墙：外壳借出连接后用 `SET LOCAL ROLE` 切到成员的角色，事务提交时自动还原。每个组件一个数据库就无法共享连接池，而且数据进去之后再改就是一次数据迁移。迁移工具默认把状态表放在 `public` 里，不改的话各组件会互相覆盖迁移历史。无论组件是否被外壳托管，迁移都从组件自己的镜像运行。

## 挡下什么

- 每个组件一个数据库，或者"给这个组件单独起一个 Postgres"
- 跨 schema 的 `JOIN`、建在别的组件表上的视图、直接查别的组件 schema 的报表
- 从一个组件的表指向另一个组件的表的外键
- 把迁移状态表（`schema_migrations`、`_yoyo_migration`）留在 `public`
- 在池化连接上用不带 `LOCAL` 的 `SET ROLE` / `SET search_path`：下一个借用者会原样继承，悄悄读到别的组件的数据
- 自己编 schema 名或角色名，而不是从 `registry/schemas.tsv` 抄

## 何时重新讨论

某个组件需要 PostgreSQL 提供不了的存储能力时。它会通过自己的配置拿到自己的存储；即便如此，它仍然不能直接读别的组件的数据。
