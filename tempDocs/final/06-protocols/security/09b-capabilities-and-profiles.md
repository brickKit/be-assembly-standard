# 能力声明与 profile

本页定义授权成员怎样逐字段声明自己具备的能力、装配工具怎样据此准入，以及部署与业务组件怎样按操作与记录类型声明 profile。写给实现授权成员、装配检查与部署配置的人。字段使用[安全 09a](09a-encoding-and-records.md#编码约定)的基本类型与“必填”约定。能力的分类、准入原则与证据状态的含义见[安全 06 的能力声明与准入](06-security-contracts-and-capabilities.md#能力声明与准入)；各类实现能承担哪些能力见[安全 10 的能力矩阵](10-providers-and-member-switching.md#能力矩阵)。

## 能力声明

**能力声明 `be.security.capability_descriptor`** 覆盖安全 06 要求列出的全部项目：

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `provider` | `Key` | 是 | 组件 ID |
| `version` | `Text` | 是 | 精确版本 |
| `artifact_digest` | `Digest` | 是 | 制品摘要 |
| `contract_versions` | `Map<Key,Text>` | 是 | 所实现的共同安全契约与语义的版本 |
| `schema_versions` | `Map<Key,Text>` | 是 | 安全 09a 各记录类型所支持的 schema 版本 |
| `capabilities` | `Map<Key,{version: Text, limits: Map<Key,Int>}>` | 是 | 能力名到版本与上限（例如最大段数、最大链深、候选集规模、查询预算）；能力名取自下文的能力目录 |
| `supported` | `{resources: Set<Key>, operations: Set<Key>, source_kinds: Set<Enum>, entries: Set<Enum>, outputs: Set<Enum>}` | 是 | 支持的资源类型、操作、业务授权来源类型（`role_grant`、`direct_grant`、`institutional_share`、`relation`、`delegation`、`impersonation`、`break_glass`，安全 05）、调用入口模式（安全 02）与出口种类（读取、导出、下载、流式） |
| `atoms` | `Map<Enum,{evaluate: Bool, complete_query: Bool, containment: Bool}>` | 是 | 每种原子能否单对象求值、能否给出完整查询、能否参与包含证明（[安全 07 的提供方能力表](07-finite-expressions-containment-and-queries.md#提供方要声明的能力)） |
| `guarantees` | `Set<Enum>` | 是 | 所提供的完整性与时间保证：`bounded_local`、`strict_acceptance`、`strict_barrier`、`output_barrier` |
| `required_adapters` | `Set<Key>` | 否 | 依赖的属主适配、SDK 能力与平台能力（例如“业务属主提交守卫”“站内通知”“独立认证路径”） |
| `profile_limits` | `Map<Key,Int>` | 否 | 本成员可承受的 profile 参数上下限（例如最短的 `w_ms`） |
| `evidence` | `Map<Key,Enum(declared, implemented, verified)>` | 是 | 每项能力的证据状态；装配只接受 `verified` 用于生产 |

### 能力目录

| 能力 | 含义 | 依赖 |
| --- | --- | --- |
| `authz.core` | 完整段求值、三值结果、字段按命中段 | — |
| `authz.list.complete` | 查询编译与命中位图（安全 07） | `authz.core` |
| `authz.atom.related` | 关系原子：投影或完整候选集 | `authz.list.complete` |
| `authz.containment.single` | 单段的包含证明 | `authz.core` |
| `authz.containment.split` | 单维拆分覆盖 | `authz.containment.single` |
| `authz.management.delegated` | 受限的分级管理（D35） | `authz.containment.single` |
| `authz.share.institutional` | 机构共享 | `authz.containment.single` |
| `authz.delegation.single` | 单层个人委托 | `authz.core` |
| `authz.delegation.chain` | 有限的多层委托 | `authz.delegation.single` |
| `authz.impersonation.readonly` | 只读扮演会话 | `authz.core`，部署有站内通知能力 |
| `authz.break_glass` | 紧急访问会话 | `authz.core`，所选身份成员有独立的认证路径 |
| `authz.recovery.owner` | 部署所有者确认与恢复 | — |
| `authz.path.bounded_local` | 默认路径：视图核验、`nonce`、分片 | `authz.core` |
| `authz.path.strict_acceptance` | 严格路径 A 档 | `authz.path.bounded_local` |
| `authz.path.strict_barrier` | 严格路径 B 档 | `authz.path.strict_acceptance`，以及各业务属主的提交守卫 |
| `authz.member.incremental_export` | 成员切换时的离线增量导出：按安全修订导出切换窗口内的变更与来源事件位置，供新成员重放（[安全 10](10-providers-and-member-switching.md#成员切换协议)） | `authz.core` |

### 准入检查

装配工具从启用的资源、操作、列表用途、实际用到的原子种类、启用的记录类型与路径，推出所需的能力集合，逐项与所选成员的能力声明比较：能力与契约版本兼容、上限满足、`supported` 与 `atoms` 覆盖实际的组合、`guarantees` 满足各操作的 `minimum_path`、`required_adapters` 在部署中存在、证据为 `verified`。列出全部缺口；有缺口则阻止装配或启用，不静默降级（D07）。准入按组合匹配，不按几个布尔值的交集（安全 06）。

## profile

### 操作 profile

部署级，按操作键逐条声明：

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `operation` | `Key` | 是 | — |
| `risk_class` | `Enum` | 否 | 只能比定义中更严（`low` 改 `high`），不能放宽 |
| `path` | `Enum` | 否 | 不弱于定义中的 `minimum_path` |
| `w_ms` | `DurationMs` | 否 | 该操作所用视图的有效期；`high` 时允许 1–10 秒，`low` 时允许 5–300 秒 |

### 生命周期 profile

按记录类型声明：

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `record_type` | `Key` | 是 | 安全 09a 的记录类型 |
| `confirmations_required` | `Int` | 是 | 受保护操作至少为 1（安全 08） |
| `confirmer_basis` | `Set<Enum>` | 是 | `holding`、`deployment_owner` |
| `confirmation_valid_ms` | `DurationMs` | 是 | 起始值 72 小时；只约束没有未来生效时间的记录（安全 08） |
| `max_validity_ms` | `DurationMs` | 否 | 缺省表示允许无固定终点，只对声明允许的类型有效（例如机构共享） |
| `notify` | `Set<Enum>` | 是 | `recipient`、`target_subject`、`admins`、`resource_owner` |
| `review_within_ms` | `DurationMs` | 否 | 紧急访问的起始值为 2 个工作日 |
| `max_chain_depth` | `Int` | 否 | 委托边；基础 profile 为 1 |

### 业务确认 profile

由业务组件按操作声明（[安全 08 的确认与受保护操作](08-state-and-change-protocol.md#确认与受保护操作)），用于关账、重开、流程实例迁移、额度维护等业务动作。字段与生命周期 profile 的确认字段相同：`confirmations_required`（可以为 0：发起人自己的显式确认即可，留审计）、`confirmer_basis`（只能是 `holding`）、`confirmation_valid_ms`、`notify`。业务确认不使用部署所有者确认，不进入安全的受保护操作清单。

### 起始值

起始值与[安全 03 的参数表](03-authorization-acceptance-and-revocation.md#起始参数与可配置边界)、[安全 08 的参数表](08-state-and-change-protocol.md#参数起始值)一致，待评审与实测。

## 独立预期

本页的准入规则由安全 09a 的 EN16（操作 profile 不能放宽风险档或路径）与 EN17（证据为 `declared` 的能力不能用于生产）检验；EN 编号只属于安全 09a。

## 已知风险与待定

- 能力目录的最终命名与版本规则在冻结时确认。
- `supported`、`atoms`、`guarantees` 的取值集合随第一个授权成员的实现确定，并与装配工具的准入检查一起验证。
- 各记录类型与操作的 profile 默认值与可调范围，随组件的声明逐个确定。
