[English](../../../en/02-decisions/02-permissions/0207-scope-assignments-live-in-authz.md) · [中文](0207-scope-assignments-live-in-authz.md)

# 0207 数据范围的分配放在 authz

**状态**：已决定，随 3.0.0 统一升级落地。

## 决策

谁得到规则（[0205](0205-data-scopes-ship-with-the-version.md)）的哪一部分，是授权 provider 持有的运行时分配，由管理员编辑，随 bundle 下发：

| 分配 | 例子 | 放在哪 |
|---|---|---|
| 每个角色、每个键的档位 | `erp.sales.view: subtree`、`erp.sales.cancel: own` | 角色的 `levels` |
| 每个角色的维度取值 | `warehouse: ["7"]`；一组自定义的部门子树，作为 `org` 的取值 | 角色的 `values` |
| 期限 | 一条仓库授权，到盘点结束为止 | 授予上的 `until`，在本地求值 |
| 共享或委托 | 一张订单共享给同事；休假期间把审批交给别人 | authz 里的元组和委托（[0206](0206-no-row-level-security.md)、[0210](0210-delegation-and-impersonation.md)） |

多个角色给同一个键时：取最高档位，取值求并集，`*` 表示全部且只能显式授予；授予了键却没给档位，视为 `own`。每个资源维度恰好有一个属主组件，记在 registry 里，由 be-ops 校验。组件不持有任何授权表，也不提供任何分配管理 API。

## 理由

3.0.0 之前，"这个库管员能看哪些仓库"住在 erp/inventory 和 erp/finance 里面的表中，各有各的管理端点；"经理能看全部"靠额外的 `.admin` 键表达。分配集中在一处，就只有一个管理界面、一条审计线、每个判定只有一种解释；"只看我自己的订单"这样的档位也能用于任何键，而各组件自建的表做不到。规则留在代码里；只有谁得到什么变成数据。

## 挡下什么

- 业务组件里的 `warehouse_access`、`legal_entity_access` 之类的表，以及编辑它们的端点（3.0.0 删除）
- 用权限键来扩大范围（`*.admin` 表示"全部行"）：由 `all` 档取代
- 两个组件同时声称拥有同一个资源维度
- 用事件把分配同步进组件自己的表；bundle 和投影是仅有的副本

## 何时重新讨论

某项分配取决于只有属主组件才有的业务数据（行本身的属性）时；那是规则，属于组件的版本，不属于这里。

完整分析：[20-authorization-provider.md，端口契约](../../04-foundations/20-authorization-provider.md#端口契约)。
