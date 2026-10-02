[English](../../../en/02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md) · [中文](0301-money-as-strings-lists-by-cursor.md)

# 0301 金额是与币种成对的十进制字符串；列表按游标分页

**状态**：为 3.0.0 修订（金额与币种成对、列精度、汇率）；已决定，随 3.0.0 统一升级落地。

## 决策

**金额。** 每份契约（proto、OpenAPI、事件 schema）里的每个金额字段，都是以字符串编码的十进制数，而且每个金额都带着它的币种：

| 值 | 列 | 线上 |
|---|---|---|
| 金额 | `NUMERIC(19,4)` | 十进制字符串 |
| 单价、成本、数量 | `NUMERIC(19,6)` | 十进制字符串 |
| 汇率 | `NUMERIC(19,10)` | 十进制字符串 |
| 比率（折扣、税率） | `NUMERIC(9,6)` | 十进制字符串 |
| 币种 | `CHAR(3)`，ISO 4217 字母代码，放在每张带金额的单据头上 | `currency` |

每个法人有本位币；外币单据快照汇率、汇率日期和汇率类型，分录同时存交易币金额和本位币金额。汇率归 `mdm/currency`，和每个 mdm 枢纽一样谁都读它。解析、格式化、舍入和分摊只在官方 SDK 的十进制实现里做，由共享向量保持一致。

**列表。** 每个 `List` 操作都按不透明游标分页（`cursor`、`page_size`、`next_cursor`），没有 `offset` 字段。

## 理由

`double` 会丢精度，而且 Go、Python、TypeScript 的舍入方式各不相同；十进制字符串发出去是什么，收到的就是什么。集团多公司和海外客户都在范围内，不带币种的金额就没有意义；四位小数装得下现行每一种 ISO 4217 币种的最小单位。舍入是与币种和税相关的业务规则，所以放在一个库里，用一套测试。深度 offset 每翻一页都更慢，还允许客户端直接要第 1000 页；契约里没有 `offset` 字段，深分页连表达都表达不出来。

## 挡下什么

- `double` / `float` 金额，或用 JSON 数字表示金额
- 没有币种的金额字段或列；单价或成本用 `NUMERIC(18,2)`
- 组件里手写的舍入或十进制代码
- 汇率放在业务组件里，而不是 `mdm/currency`
- 在 `List` 请求里加 `offset`、`page` 或 `page_number`
- "跳到第 N 页"：改用筛选条件（日期范围、状态、搜索）缩小结果

## 何时重新讨论

金额作为带币种的字符串永不重新讨论；某一列需要超过 15 位整数时，只加宽那一列。分页同样不重新讨论：预计一直很小的列表也走游标，这样所有 `List` 的用法都一样。

完整分析：[06-money-quantity-units.md，选择](../../04-foundations/06-money-quantity-units.md#选择)；游标见 [04-identifiers-and-numbering.md，游标](../../04-foundations/04-identifiers-and-numbering.md#游标)。
