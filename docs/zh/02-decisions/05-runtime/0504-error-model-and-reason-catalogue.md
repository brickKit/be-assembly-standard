[English](../../../en/02-decisions/05-runtime/0504-error-model-and-reason-catalogue.md) · [中文](0504-error-model-and-reason-catalogue.md)

# 0504 一种错误对象，由目录里的 reason 标识

**状态**：已决定，随 3.0.0 统一升级落地，排在依赖它的 06c 前端工作之前。

## 决策

- **一种错误对象，原样穿过每一个面。** 在 REST 上它是 RFC 9457 problem details（`application/problem+json`），装着 Google AIP-193 `ErrorInfo` 的成员：`type`、`title`、`status`、`code`（gRPC 码名）、`reason`、`domain`、`detail`、`metadata`（只有字符串）、`violations`、`instance`、`request_id`、`trace_id`。在 gRPC 上它是带 `ErrorInfo` 的 `google.rpc.Status`；在 BFF 的 GraphQL 上是 `extensions`。运行时负责双向映射。
- **`domain` + `reason` 标识错误。** 每个组件在 `contracts/errors.yaml` 里声明自己的 reason，只增不减，每种前端语言一份消息模板。平台 reason 用 `domain: be`，随组件协议发布；组件从不在自己的 domain 下抛出这些名字。
- **前端负责翻译**；服务端的 `detail` 用部署的默认语言，供日志和排障。
- **内部错误从不外泄**：`INTERNAL`、`UNKNOWN`、`DATA_LOSS` 一律答 `reason: INTERNAL`、`domain: be`、一句通用的 `detail` 和 `trace_id`；原始错误只进日志。组件代码无法选择退出。
- **日志级别跟随状态码**，由 SDK 决定，不由各组件决定。

## 理由

inventory 抛出的 reason，经 sales 的 REST 答复到达浏览器，或经 BFF 到达手机，每一跳都不必重新发明。机器 reason 让错误可测（测试断言 `CUSTOMER_CODE_TAKEN`，而不是一句话），并能在用户语言本来所在的地方翻译。内部错误由运行时的映射负责，所以按构造就不可能泄露任何内部信息。3.0.0 之前，错误体是 `{"error": "<中文消息>"}`，`INTERNAL` 错误还把数据库原始消息带到浏览器。

## 挡下什么

- 任何一个面上的 `error` 字符串字段，或任何第二种错误形状
- 不在组件目录里的 reason；改名、删除或复用 reason（用 `deprecated: true` 退役）
- 以服务端翻译好的消息作为错误唯一的标识
- `detail` 或 `metadata` 里出现数据库消息、堆栈或密钥；`metadata` 里出现用户自己发来的内容以外的个人信息
- 组件在自己的 domain 下抛 `be` 的 reason，或把依赖方有意义的 reason 映射成自己更含糊的 reason

## 何时重新讨论

在通知和打印之外也需要服务端文本时：以加法增加 `LocalizedMessage` 和对应的 problem 成员。

完整分析：[15-user-api-and-errors.md，错误体](../../04-foundations/15-user-api-and-errors.md#错误体)和 [reason 目录](../../04-foundations/15-user-api-and-errors.md#reason-目录)。
