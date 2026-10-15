# 能力声明与 profile

本页定义授权成员怎样逐字段声明自己具备的能力、装配工具怎样据此准入，以及部署与业务组件怎样按操作与记录类型声明 profile。写给实现授权成员、装配检查与部署配置的人。字段使用[安全 09a](09a-encoding-and-records.md#编码约定)的基本类型与“必填”约定（是、否、条件）。能力的分类、准入原则与证据状态的含义见[安全 06 的能力声明与准入](06-security-contracts-and-capabilities.md#能力声明与准入)；各类实现能承担哪些能力见[安全 10 的能力矩阵](10-providers-and-member-switching.md#能力矩阵)。

## 能力声明

**能力声明 `be.security.capability_descriptor`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `provider` | `Key` | 是 | 组件 ID |
| `version` | `Text` | 是 | 精确版本 |
| `artifact_digest` | `Digest` | 是 | 制品摘要 |
| `schema_versions` | `Map<Key,Text>` | 是 | [安全 09a](09a-encoding-and-records.md) 各记录类型所支持的 schema 版本 |
| `capabilities` | `Map<Key,{version: Text, limits: Map<Key,Int>}>` | 是 | 能力名到版本与上限（例如最大段数、最大链深） |
| `evidence` | `Map<Key,Enum(declared, implemented, verified)>` | 是 | 每项能力的证据状态；装配只接受 `verified` 用于生产 |

### 能力目录

| 能力 | 含义 | 依赖 |
| --- | --- | --- |
| `authz.core` | 完整段求值、三值结果、字段按命中段计算 | — |
| `authz.list.complete` | 查询编译与命中位图（[安全 07 的完整查询](07-finite-expressions-containment-and-queries.md#完整查询)） | `authz.core` |
| `authz.atom.related` | 关系原子：投影或完整候选集 | `authz.list.complete` |
| `authz.containment.single` | 单段包含证明 | `authz.core` |
| `authz.containment.split` | 单维拆分覆盖 | `authz.containment.single` |
| `authz.management.delegated` | 受限分级管理（D35） | `authz.containment.single` |
| `authz.share.institutional` | 机构共享 | `authz.containment.single` |
| `authz.delegation.single` | 单层个人委托 | `authz.core` |
| `authz.delegation.chain` | 有限多层委托 | `authz.delegation.single` |
| `authz.impersonation.readonly` | 只读扮演会话 | `authz.core`；部署有站内通知能力 |
| `authz.break_glass` | 紧急访问会话 | `authz.core`；所选 IAM 成员有独立的认证路径 |
| `authz.recovery.owner` | 部署所有者确认与恢复 | — |
| `authz.path.bounded_local` | 默认路径：视图核验、`nonce`、分片 | `authz.core` |
| `authz.path.strict_acceptance` | 严格路径 A 档 | `authz.path.bounded_local` |
| `authz.path.strict_barrier` | 严格路径 B 档 | `authz.path.strict_acceptance`，以及各业务属主的提交守卫 |

### 准入检查

装配工具从启用的资源、操作、列表用途、实际用到的原子种类、启用的记录类型与路径，推出所需的能力集合；逐项与所选成员的能力声明比较：版本兼容、上限满足、证据为 `verified`；列出缺口。有缺口就阻止装配或启用，不静默降级（D07）。更换授权成员时的预检使用同一检查（[安全 10 的成员切换协议](10-providers-and-member-switching.md#成员切换协议)）。

## profile

### 操作 profile

部署级，按操作键逐条声明。操作定义的字段见[安全 09a 的操作定义](09a-encoding-and-records.md#定义资源维度操作与字段)。

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `operation` | `Key` | 是 | — |
| `risk_class` | `Enum` | 否 | 只能比定义中更严（`low` 改为 `high`），不能放宽 |
| `path` | `Enum` | 否 | 不弱于定义中的 `minimum_path` |
| `w_ms` | `DurationMs` | 否 | 该操作所用的视图有效期；`high` 时允许 1–10 秒，`low` 时允许 5–300 秒 |

### 生命周期 profile

按记录类型声明。

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `record_type` | `Enum` | 是 | — |
| `confirmations_required` | `Int` | 是 | 受保护操作至少为 1（[安全 08 的确认与受保护操作](08-state-and-change-protocol.md#确认与受保护操作)） |
| `confirmer_basis` | `Set<Enum>` | 是 | `holding`、`deployment_owner` |
| `confirmation_valid_ms` | `DurationMs` | 是 | 起始值 72 小时 |
| `max_validity_ms` | `DurationMs` | 否 | 缺省表示允许无固定终点，只对声明允许的类型有效（例如机构共享） |
| `notify` | `Set<Enum>` | 是 | `recipient`、`target_subject`、`admins`、`resource_owner` |
| `review_within_ms` | `DurationMs` | 否 | 紧急访问的起始值为 2 个工作日 |
| `max_chain_depth` | `Int` | 否 | 委托边使用；基础 profile 为 1 |

### 业务确认 profile

业务确认 profile 由业务组件按操作声明（[安全 08 的确认与受保护操作](08-state-and-change-protocol.md#确认与受保护操作)），用于关账、重开、流程实例迁移、额度维护等业务动作。它的字段与生命周期 profile 的确认字段相同：`confirmations_required`、`confirmer_basis`（只能是 `holding`）、`confirmation_valid_ms`、`notify`。它不使用部署所有者确认，也不进入安全受保护操作的清单。

### 起始值

本页的起始值与[安全 03 的起始参数](03-authorization-acceptance-and-revocation.md#起始参数与可配置边界)、[安全 08 的参数起始值](08-state-and-change-protocol.md#参数起始值)一致，待评审与实测。

## 独立预期

本页规则的固定预期是 [安全 09a 的 EN16 与 EN17](09a-encoding-and-records.md#独立预期)：操作 profile 放宽风险档或路径弱于 `minimum_path` 时装配拒绝；证据只是 `declared` 的能力不能支撑生产部署启用的功能。成员能力缺口在切换时的预期见[安全 10 的独立预期](10-providers-and-member-switching.md#独立预期)。

## 已知风险与待定

- 能力目录的最终命名与版本规则在冻结时确认。
- 冻结时由本页与[安全 09a](09a-encoding-and-records.md) 一起生成 protobuf 与 JSON Schema。
- 操作与生命周期 profile 的起始值待评审与实测。
