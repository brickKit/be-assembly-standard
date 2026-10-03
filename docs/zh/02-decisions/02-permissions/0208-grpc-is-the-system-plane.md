[English](../../../en/02-decisions/02-permissions/0208-grpc-is-the-system-plane.md) · [中文](0208-grpc-is-the-system-plane.md)

# 0208 gRPC 是系统面，人用 REST

**状态**：已决定，随 3.0.0 统一升级落地。

## 决策

两个面，按传输方式分开：

| 面 | 传输 | 调用方 | 上面走什么 |
|---|---|---|---|
| 系统面 | 组件之间的 gRPC | 永远是系统主体：项目里的另一个组件，由 `be-caller` metadata 指明 | `data_scopes: none` 的主数据；系统协议（预留的 try / confirm / cancel、建待办、检查期间）；按 ID 补全（`BatchGet`，[0304](../03-contracts-and-data/0304-batch-get-takes-at-most-500-ids.md)），ID 必须是调用方正当持有的 |
| 用户面 | REST（以及移动端 BFF 的 GraphQL） | 人，凭其 token | 一切按这个人的数据范围过滤的数据 |

不带 `be-caller` 的系统调用答 `UNAUTHENTICATED` / `MISSING_CALLER`。用户的 `sub` 和委托链以 `be-actor-sub`、`be-actor-act` 传递，只用于审计，从不用来授予访问。契约里已有的面向用户的 rpc 保留（契约只增），在每个组件里都由运行时统一答 `UNAUTHENTICATED`，reason 为 `TOKEN_INVALID`（domain `be`）。一个组件需要替用户取另一个组件的数据时，经 SDK 的用户面客户端，带着用户的 token 调对方的 REST API。

## 理由

一条任何开发者（人或 AI）都能遵守的规则：人用 REST，组件用 gRPC。安全边界于是就是传输方式，范围受限的读取不会因疏忽而用组件自己的身份发出，而组件身份能看到的行比用户多。gRPC 还把组件之间调用的难点（截止时间、带预算的重试、keepalive、连接轮换）写在规范里，每门语言都能靠配置获得。

## 挡下什么

- 返回按调用用户范围过滤的行的 gRPC 方法，或信任 `be-actor-sub` 来判定访问的方法
- 在服务用户请求的路径上使用组件的系统身份（gRPC 或系统客户端）：返回结果悄无声息地多出用户不该看到的行
- 浏览器或移动 App 直接调 gRPC
- 将来的代理用系统身份取用户的数据：它要经 REST、凭委托 token 行事（[0210](0210-delegation-and-impersonation.md)）

## 何时重新讨论

浏览器必须直接调 proto 契约（在 gRPC 旁边用 connect handler 提供同一份契约），或组件跨信任边界运行，使预留在 `authorization` 上的服务 token 变成硬需求时。

完整分析：[14-system-rpc.md，选择](../../04-foundations/14-system-rpc.md#选择)。
