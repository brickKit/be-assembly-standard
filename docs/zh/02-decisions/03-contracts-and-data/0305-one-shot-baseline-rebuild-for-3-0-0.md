[English](../../../en/02-decisions/03-contracts-and-data/0305-one-shot-baseline-rebuild-for-3-0-0.md) · [中文](0305-one-shot-baseline-rebuild-for-3-0-0.md)

# 0305 3.0.0 重建可以替换已发布的迁移，仅此一次，不做兼容层

**状态**：已决定；只适用于 3.0.0 统一升级。

## 决策

对 3.0.0 统一升级、而且只对它，每个组件都可以把已发布的迁移整体替换为一份新基线 `0001_init`，并打破下表列出的各处，不做兼容层。允许这样做的条件是：**任何地方都没有生产数据**；演示库 `brickkit_db` 和测试库 `brickkit_test_db` 重置并重新播种。

| 一次改完的 | 不做的 |
|---|---|
| 迁移：UUIDv7 主键（[0306](0306-uuidv7-own-keys.md)）、金额精度与币种列（[0301](0301-money-as-strings-lists-by-cursor.md)）、交易单据上的 `legal_entity_id`、业务日期 `DATE` 列（[0307](0307-business-dates-and-legal-entity-calendar.md)）；不出现 `OWNER TO`、角色名或 schema 名；平台表交给 SDK | 从 2.x 表结构迁过来的迁移链 |
| REST 错误体改为 problem details（[0504](../05-runtime/0504-error-model-and-reason-catalogue.md)） | `error` 别名字段 |
| 事件信封改为 CloudEvents 头（[0505](../05-runtime/0505-cloudevents-envelope-and-aggregate-cursor.md)） | 读取旧的 `X-` 头；为旧事件派生 id |
| `AUTHZ_URL` 和 bundle v2 取代 `AUTHZ_BUNDLE_URL` 和 bundle v1（[0107](../01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)） | 派生过渡期、v1 回退 |
| 删除 erp/inventory 和 erp/finance 里各自的访问表及其端点（[0207](../02-permissions/0207-scope-assignments-live-in-authz.md)） | 过渡版本 |
| SDK 升到 v0.6.0，API 全新 | v0.5.0 API 的包装或弃用别名 |

组件升到 3.0.0（Go 模块路径 `/v3`），外壳升到 1.1.0。registry 仍然只增：失去用途的权限键标为弃用，不删除。

## 理由

3.0.0 的设计同时改动了各处的主键类型、列形状和线上信封。没有生产数据、外壳也还没有托管任何成员，迁移链或兼容层的成本会超过整个重建，而且会永远留在代码里。把条件和精确清单写下来，才不会让这次破例变成习惯。

## 挡下什么

- 以后的任何版本援引本决策：以后再重建基线或做破坏性变更，需要由人做出新决策
- 3.0.0 统一升级中任何地方"只保留一个版本"的兼容垫片
- 在新基线旁边保留 2.x 迁移，或事后修改已发布的 3.x 迁移
- 对存有真实数据的环境执行重建

## 何时重新讨论

不适用：3.0.0 统一升级发布后，本决策即已用完。此后迁移只向前，契约只增（[0302](0302-contracts-are-additive-only.md)）。

完整分析：[08-schema-evolution.md，选择](../../04-foundations/08-schema-evolution.md#选择)；主键的改变见 [04-identifiers-and-numbering.md，选择](../../04-foundations/04-identifiers-and-numbering.md#选择)。
