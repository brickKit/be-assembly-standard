[English](../../../en/02-decisions/03-contracts-and-data/0304-batch-get-takes-at-most-500-ids.md) · [中文](0304-batch-get-takes-at-most-500-ids.md)

# 0304 `BatchGet` 最多 500 个 ID，上限是契约的一部分

**状态**：已决定，随 3.0.0 统一升级落地。

## 决策

每个聚合根都在系统面（[0208](../02-permissions/0208-grpc-is-the-system-plane.md)）提供 `BatchGet`，用于补全调用方已经持有的 ID（列表上的显示名、单据的行）。一次调用最多 500 个 ID。上限作为方法选项（`max_items`）写在契约里，由运行时的拦截器在组件代码运行之前执行；更大的请求以 `INVALID_ARGUMENT` / `BATCH_TOO_LARGE` 失败。授权 provider 的 `BatchCheck` 和组件的 `_authz/check` 用同一个上限。ID 更多的调用方自行切分；组件从不对一组 ID 逐个调用来解析。

## 理由

没有上限，一个请求就能让某个组件在一个截止时间内加载无限多行，代价落在被调方身上，而它没法体面地拒绝。500 覆盖了用户界面用到的每一种页大小，还留有余量，对普通记录也远低于 4 MiB 的消息上限。写进契约，每门语言的客户端和服务端、每个评审者读到的都是同一个数字。

## 挡下什么

- 没有 `max_items` 的 `BatchGet`，或只存在于某个组件代码里的上限
- 在循环里一次一个地解析 ID（跨网络的 N+1）
- 用 `BatchGet` 枚举或搜索记录：那是带游标的 `List`（[0301](0301-money-as-strings-lists-by-cursor.md)）
- 服务端对超限请求悄悄截断，而不是拒绝

## 何时重新讨论

某个经过测量的调用方在热路径上每次往返需要超过 500 个 ID，并且切分的代价超过了对被调方的保护价值时；届时只为那个方法在契约里以加法改上限。

完整分析：[14-system-rpc.md，选择](../../04-foundations/14-system-rpc.md#选择)。
