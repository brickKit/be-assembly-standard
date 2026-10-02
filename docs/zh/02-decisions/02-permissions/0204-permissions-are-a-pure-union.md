[English](../../../en/02-decisions/02-permissions/0204-permissions-are-a-pure-union.md) · [中文](0204-permissions-are-a-pure-union.md)

# 0204 权限是纯并集，没有 Deny

**状态**：为 3.0.0 修订（只沿委托链取交集）；已决定，随 3.0.0 统一升级落地。

## 决策

在一个主体内部，权限是授给它的一切的并集：它所有角色的键、它的任一角色给某个键的最高档位、所有角色的维度取值、它的共享和关系。没有 Deny 规则，也没有规则顺序。要给某一个人开例外，就建一个只有他一个成员的角色。

唯一的交集出现在委托链上（[0210](0210-delegation-and-impersonation.md)）：一个主体代表另一个主体行事时，有效权限是代理人的并集，与链上每一层天花板取交集，类似 permission boundary。天花板只会收窄；它从不否决授予在其范围内给出的东西，也没有顺序。

## 理由

纯并集下，"这个人为什么能做这件事"永远只有一种答案：给出它的那条授予。Kubernetes RBAC 不设 Deny 正是为此；先 Deny 后 Allow 的求值顺序，正是 AWS IAM 策略难以推理的原因。委托链上的天花板保留了这个性质：解释仍然是一条授予加上"并且天花板允许"，授予仍然只会扩大可见范围。

## 挡下什么

- "销售部所有人，除了 Bob"；"禁止实习生导出"
- 负权限、黑名单、规则之间的优先级或顺序
- `registry/permissions.tsv` 或 bundle 里的 Deny 列
- 把天花板 profile 当成普通用户（不代表任何人行事）的 Deny 清单

要表达"除 X 以外的一切"，就给用户一个不含 X 的角色。

## 何时重新讨论

某项监管要求只能表述为凌驾于所有授予之上的禁令，而且任何角色拆分都无法表达它时。

完整分析：[20-authorization-provider.md，选择](../../04-foundations/20-authorization-provider.md#选择)。
