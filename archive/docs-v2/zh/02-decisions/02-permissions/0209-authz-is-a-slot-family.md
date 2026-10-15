[English](../../../en/02-decisions/02-permissions/0209-authz-is-a-slot-family.md) · [中文](0209-authz-is-a-slot-family.md)

# 0209 授权是一个槽位族：一份契约、一套套件

**状态**：已决定，随 3.0.0 统一升级落地（`infra/authz-static` 和 `infra/authz-openfga` 在阶段 06 内建）。

## 决策

授权 provider 是一个槽位族（`slot:authz`，[0104](../01-architecture/0104-variants-become-slot-families.md)）。恰好安装一个成员；每个组件都经 `AUTHZ_URL` 访问它（[0107](../01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)）。

- **两份契约**，放在族仓库 `contract-infra-authz`：provider 契约 `infra.authz.v2`（bundle、变更流、元组、check、explain、委托、`ResolveClaims`、管理 REST），每个成员都实现；资源契约（`_authz/check`、`_authz/explain`、`_shares`），由 SDK 挂在每个声明了资源的组件上。
- **代码和向量都在族仓库里。** 它检出在 `contracts/infra/authz`（github.com/brickKit/contract-infra-authz）。Go 代码在那里用 `make gen` 生成，并在打 `v2.0.0` 标签之前提交到 `gen/go` 下（`github.com/brickKit/contract-infra-authz/v2/gen/go/infra/authz/v2`，属于族契约包，[0101](../01-architecture/0101-no-imports-between-components.md)）；Python 和 TypeScript SDK 从固定的标签复制 `proto/` 和 `schemas/`，私下生成。bundle 的含义是该仓库的 `EVALUATION.md`，锁定它的决策向量以该仓库的 `vectors/` 为准；be-protocol 按标签引用它们，自己只放全协议通用的向量。
- **List/Can 一致是契约的一部分**：某行出现在键 K 的列表里，当且仅当对 K 的单条检查说它可见。
- **能力在 bundle 里协商。** core（claims、键、档位、取值、字段键、stale、revision、目录同步、`/api/me/access`、基础 explain、期限）必须实现；其余（`admin_write`、`sharing`、`relation_sync`、`check`、`graph`、`delegation`、`agents`、`impersonation`、`access_review`、`explain_paths`、`conditions`）可选，缺一项就明确降级（`501` / `CAPABILITY_UNAVAILABLE`、投影为空、隐藏入口）。组件声明 `requires_capabilities`；已安装成员的 `provides_capabilities` 覆盖不了时，组装失败。
- **成员**全部在阶段 06 内建，顺序是：`infra/authz`（原生，默认）→ `infra/authz-static`（一个策略文件，不用库）→ `infra/authz-openfga`（ReBAC，加上 `graph`）。Cedar 或 OPA 只在有真实 ABAC 需求时做，而且只管动作；条件永不参与行可见性。
- **每个成员都要通过** `tools/be-acceptance/conformance/authz/`。换成员时，分配经族契约定义的 NDJSON 导出 / 导入搬过去；导入到缺某项能力的成员时，列出它装不下的每一行并停止。

## 理由

授权模型的分歧是真实的（大多数 ERP 客户是角色加档位，协作重的客户是关系图，ABAC 用策略语言），只要没有组件依赖成员，这个位置就满足槽位族的两个条件。尽早建好第二、第三个真实成员，才能逼着契约说实话；套件让"可替换"成为一项测试而不是一句声明。明确的降级让一个能力较少的成员成为看得见的选择，而不是悄悄丢掉保护。

## 挡下什么

- 组件依赖 `infra/authz` 或任何其他成员，或调用族契约之外某个成员专有的 API
- 能力靠假设而不是声明：代码依赖 `sharing` 或 `graph`，却没写 `requires_capabilities`
- 成员悄悄丢掉装不下的东西（把共享导入 static 成员），而不是拒绝
- 基于某个成员私有 API 做的管理界面；管理界面只按族契约生成
- 列表过滤结果与同一个键的 `_authz/check` 不一致
- 由 ABAC 条件决定列表返回哪些行

## 何时重新讨论

某个客户的模型即便新增一项可选能力，也无法放到这两份契约后面；或者这个族在实践中收敛到一个成员、没人再需要别的（届时套件留作回归测试）。

完整分析：[20-authorization-provider.md，选择](../../04-foundations/20-authorization-provider.md#选择)和[什么时候换](../../04-foundations/20-authorization-provider.md#什么时候换)。
