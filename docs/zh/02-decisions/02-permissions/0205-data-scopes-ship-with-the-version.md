[English](../../../en/02-decisions/02-permissions/0205-data-scopes-ship-with-the-version.md) · [中文](0205-data-scopes-ship-with-the-version.md)

# 0205 数据范围的规则随版本发布

**状态**：为 3.0.0 原地重写（规则随版本，分配在 authz）；已决定，随 3.0.0 统一升级落地。

## 决策

决定一个键能触及哪些行的**规则**，是组件代码和契约的一部分，只能通过发布新版本来改变：

- 一个资源类型有哪些维度（`owner`、`org`，以及 `warehouse`、`legal_entity` 这类资源维度），以及它们怎么组合：`owner` 和 `org` 取 OR，资源维度取 AND；
- 适用哪些档位（`own`、`dept`、`subtree`、`all`）；
- 一个资源类型有哪些关系、每种关系授予什么、能不能共享。

它们在 `assembly.yaml` 的 `data_scopes` 和 `resources` 下声明，由 SDK 的规范谓词在组件的查询里执行。`data_scopes` 必填：不需要数据范围的组件写 `data_scopes: none`，省略即报错。

**分配**（某个角色在某个键上得到哪个档位、哪些取值，哪些记录共享给了谁）是 authz 里的运行时数据，由管理员编辑（[0207](0207-scope-assignments-live-in-authz.md)）。用户能*做*什么（功能权限）也是同一类运行时数据。

## 理由

SAP、Odoo 和 PostgreSQL 行级安全都让行规则随代码发布：写在代码里的规则可以评审、对比、测试、回滚，同一版本对每个客户都一样。真正每天都在变的是谁得到哪个档位、哪些取值，所以这一部分是数据。安全机制的默认值必须是拒绝，所以省略这一段不能等同于"none"。

## 挡下什么

- 在运行时编辑规则："让 `org` 维也匹配客户所在地区"、可配置的公式、在后台界面里写规则
- 先全部查出来再在调用方过滤：分页当场出错（查出 20 条、滤掉 12 条，用户只看到 8 条）
- 列表的过滤结果与同一个键的单条检查不一致（List/Can 一致性）
- 因为组件"用不上"就省略 `data_scopes`
- 在用户请求路径上用组件的系统身份：它会绕过数据范围，而且不报错（[0208](0208-grpc-is-the-system-plane.md)）

## 何时重新讨论

某个客户必须在两次发布之间修改行规则（不是分配），而且频率高到发布节奏跟不上时。

完整分析：[20-authorization-provider.md，选择](../../04-foundations/20-authorization-provider.md#选择)。
