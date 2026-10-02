[English](../../../en/02-decisions/02-permissions/0210-delegation-and-impersonation.md) · [中文](0210-delegation-and-impersonation.md)

# 0210 委托与扮演不超过被代表的人；代理人只留位子

**状态**：已决定，契约形状随 3.0.0 统一升级落地。每种方式在 provider 声明对应能力（`delegation`、`impersonation`）后可用；代理人只留位子、不开发。

## 决策

一个主体代表另一个主体行事时，有效权限是行事者自己的权限与链上每一层天花板的交集（[0204](0204-permissions-are-a-pure-union.md)），**每次请求现算，从不快照**：一个人被撤掉某个角色，所有代表他行事的人同时失去它。

| 方式 | 例子 | 怎么运作 |
|---|---|---|
| 代办（`on_behalf`） | 审批人 A 10 月 1 日到 7 日休假，把 `infra.workflow.task.act` 交给 B | B 用自己的 token；bundle 里有一条给 B、覆盖本次键的委托时，SDK 在该键上把 A 的主体集合并进 B 的，限于日期范围内 |
| 只读扮演（`act_as`） | 客服以张三的身份查看系统，排查问题 | token 的 `act` 写明真实的人，`ceil` 只允许读；需要键 `infra.authz.impersonate`，生产环境允许；每一行访问日志都带 `act` 链，并通知被查看的人 |
| AI 代理人 | 无 | **只留位子**：`act.kind` 允许 `agent`，bundle 能力 `agents` 默认 `false`，profile 和天花板的形状定死，权限键接受一个可选字段 `delegable`，没有任何东西填写或读取它。带 `act.kind: agent` 的 token 答 `401 UNSUPPORTED_DELEGATION` |

没有对应能力的 provider，对带 `ceil` 或 `dg` 的 token 答 `401 UNSUPPORTED_DELEGATION`，并隐藏入口。委托链以 `be-actor-act` 传给其他组件，用于审计。

## 理由

两种面向人的方式都是 ERP 的日常需求（休假代办、客服排障），它们和 OAuth token exchange、permission boundary 有同样安全的形状：行事者永远不能超过被代表的人，链条有记录。按请求现算交集，撤销才能立即生效。现在就把代理人的形状留好、但不开发，等项目以后做 AI 时，契约只需加法。

## 挡下什么

- 委托或扮演会话能做的事超过被代表的人，或在其被撤权后仍保有权限
- 把委托人的权限复制进代理人的角色，或跨请求缓存有效权限集
- 能写入的扮演、日志里没有 `act` 的扮演、被查看的人永远不知道的扮演
- 用组件的系统身份替代理人或 AI 代理取用户的数据（[0208](0208-grpc-is-the-system-plane.md)）
- 现在就开发代理人分支：给代理人的 token exchange 路径、"永不下放"的键清单、`ana/ai` 组件

## 何时重新讨论

项目开始做 AI 代理人（届时经预留的形状以加法引入），或监管要求生产环境关闭扮演时。

完整分析：[20-authorization-provider.md，选择](../../04-foundations/20-authorization-provider.md#选择)；token 一侧见 [21-identity-provider.md，端口契约](../../04-foundations/21-identity-provider.md#端口契约)。
