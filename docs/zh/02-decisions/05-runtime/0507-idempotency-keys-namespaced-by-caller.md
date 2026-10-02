[English](../../../en/02-decisions/05-runtime/0507-idempotency-keys-namespaced-by-caller.md) · [中文](0507-idempotency-keys-namespaced-by-caller.md)

# 0507 幂等键按调用方划分命名空间，并绑定到命令

**状态**：已决定，随 3.0.0 统一升级落地。

## 决策

- **命令的幂等键属于它的调用方。** 被调方的 `besdk_idempotency` 以 `(caller, idempotency_key)` 为键，调用方是 `user:<平台 sub>`、`svc:<组件 ID>`（来自系统面的 `be-caller`）或 `system`（组件自己的后台工作）。别的调用方的键，对我来说就是一个没用过的键。
- **键绑定到它的命令、目标和请求指纹**：对按 RFC 8785 规范化后的请求取 SHA-256。同一个键换了命令、目标或请求体，以 `INVALID_ARGUMENT` / `IDEMPOTENCY_MISMATCH` 失败；尚未完成的认领答 `ABORTED` / `IDEMPOTENCY_IN_PROGRESS`；已完成的直接返回存下的结果，不再执行。
- **认领是原子的**（`INSERT … ON CONFLICT DO NOTHING`）；两段式命令在网络调用期间一直保持认领；确定失败的步骤释放认领，这个键就可以重试。
- **检查按固定顺序进行**：校验参数，授权目标及其数据范围，再查或认领键，再检查状态机，最后写入。
- **键有效 30 天**，写进每个带键命令的契约。事件 handler 为下游命令使用的键由事件派生，所以重投就是带同一个键的重试。`Idempotency-Key` 是请求体里 `idempotency_key` 的 REST 头形式。

## 理由

全局共用一个键空间时，一个调用方能读到另一个调用方的结果、抢占系统派生的键（比如由商机 ID 派生的键），或探知某个键是否存在。把键绑定到命令和指纹，意外的复用就成了报错，而不是悄无声息的错误答复。先授权、再查键，重放就不会把结果交给已经看不见这条记录的人（[0212](../02-permissions/0212-invisible-records-answer-404.md)）。

## 挡下什么

- 所有调用方共用的键空间；只看键、不看调用方
- 对命令、目标或请求体不同的请求返回存下的结果
- 先用普通 `SELECT` 查、再插入来认领键
- 在检查权限和数据范围之前就查键
- 任何一层用新键重试同一个意图

## 何时重新讨论

出现两个不同调用方必须共享同一个命令结果的正当场景时；那是业务层面的引用（一个订单号），不是共享的幂等键。

完整分析：[11-consistency-across-components.md，被调方的命令幂等](../../04-foundations/11-consistency-across-components.md#被调方的命令幂等)。
