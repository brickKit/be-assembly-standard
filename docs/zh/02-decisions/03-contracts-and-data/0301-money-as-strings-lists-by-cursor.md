[English](../../../en/02-decisions/03-contracts-and-data/0301-money-as-strings-lists-by-cursor.md) · [中文](0301-money-as-strings-lists-by-cursor.md)

# 0301 金额是字符串编码的十进制；列表按游标分页

## 决策

所有契约（proto、OpenAPI、事件 schema）中的金额字段，一律是用字符串编码的十进制数。所有 `List` 操作都按游标分页，没有 `offset` 字段。

## 理由

`double` 会丢精度，而且 Go、Python、TypeScript 各自的舍入方式不同；十进制字符串发出去是什么，收到的就是什么。深 offset 每翻一页都更慢，还允许客户端直接要第 1000 页；没有 `offset` 字段，深分页在契约层根本表达不出来。

## 挡下什么

- 用 `double` / `float` 表示金额，或在 JSON 里用数字类型表示金额
- 给 `List` 请求加 `offset`、`page` 或 `page_number`
- "跳到第 N 页"——改用筛选条件（日期范围、状态、搜索）缩小结果

## 何时重新讨论

金额永远不重新讨论。分页也不重新讨论：预计一直很小的列表同样用游标，这样每个 `List` 的用法都一样。
