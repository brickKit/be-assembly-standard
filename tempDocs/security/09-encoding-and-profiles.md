# 安全记录的正式编码与能力 profile

> 状态：2026-10-13 第九份安全候选规格，尚未冻结。把前八份候选中的结构落到逐字段：基本类型、规范编码与摘要、引用、定义、授予段、安全记录、变更协议、视图核验、严格路径、求值结果与错误、能力声明和 profile。按 D59，这是新契约的第一版，不对齐现有 rc.2 或旧 SDK。

## 本页的形式

本页用中文字段表写定语义：字段名、类型、是否必填、约束。冻结时由这些表统一生成 protobuf 与 JSON Schema；在此之前不写线格式文件，避免过早绑定。摘要与签名只按本页定义的规范 JSON 形式计算，不使用任何语言或 protobuf 的二进制序列化结果。

表中“必填”一列：**是**表示缺失即无效；**否**表示可以缺省，缺省有明确含义（写在约束里）；**条件**表示在约束所述情况下必填。

## 编码约定

### 基本类型

| 类型 | 线上表示 | 规范形式与约束 |
| --- | --- | --- |
| `Id` | 字符串 | 小写 UUIDv7 文本，36 个字符；只表示身份，不携带任何权限 |
| `Key` | 字符串 | 注册键，`[a-z][a-z0-9_]*` 以点分段，最长 128 字符；权限键、操作、资源类型、维度、字段、能力都用它 |
| `Text` | 字符串 | UTF-8，按 Unicode NFC 规范化后存储与计算摘要；不用于任何授权判断 |
| `Decimal` | 字符串 | 无指数、无前导 `+`、无多余的前导零与末尾零，整数不带小数点，零写作 `0`；最多 38 位有效数字，小数位不超过 18 |
| `Currency` | 字符串 | ISO 4217 三位大写字母 |
| `Instant` | 字符串 | UTC，`YYYY-MM-DDTHH:MM:SS.ffffffZ`，固定 6 位小数 |
| `Date` | 字符串 | 业务日期 `YYYY-MM-DD`，按法人的业务时区解释 |
| `DurationMs` | 整数 | 毫秒，非负 |
| `Int` | 整数 | 进入摘要的整数绝对值小于 2^53；可能更大的计数一律用 `Revision` |
| `Bool` | 布尔 | — |
| `Enum` | 字符串 | 小写下划线；每个 schema 版本列出全部取值；读者遇到未知取值时，安全相关字段拒绝整条记录，非安全字段按“未知”处理 |
| `Set<T>` | 数组 | 按元素规范字节升序排列、去重；空集写作 `[]`，表示“空”，不表示“全部” |
| `List<T>` | 数组 | 顺序有含义 |
| `Map<K,T>` | 对象 | 键为 `Key` 或 `Id`，由字段说明 |
| `Presence<T>` | 对象 | 显式存在性：`{"state":"value","value":…}`、`{"state":"null"}`、`{"state":"unobtained"}`、`{"state":"unsupported"}`；只用于事实属性（第六份要求区分已知空、已知 null、未取得、不支持） |
| `Digest` | 字符串 | `sha256:` 加 64 位小写十六进制 |

全部编码中不出现 JSON `null` 与浮点数。可选字段缺省就是不写这个键；需要表达“已知为 null”时用 `Presence`。

### 名称、类型与版本

- 字段名为小写下划线 ASCII。
- 每种记录有类型名 `be.security.<name>` 与 schema 版本 `主.次`。
- **次版本**只能增加不影响任何授权判断的可选字段；这类字段放在每条记录的 `ext` 对象里，读者不认识可以忽略。
- **任何能限制或放行访问的新内容**（新原子种类、新条件、新来源类型、新状态）都提升主版本，或者把功能名写进记录的 `required_features`。读者遇到不认识的 `required_features` 必须拒绝整条记录，不能忽略后继续放行（第六份）。

### 规范编码与摘要

1. 先规范化：集合排序去重、十进制与时刻写成规范形式、文本 NFC、缺省字段不写；授予段按第七份规范化。
2. 再按 [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785)（JSON 规范化方案）序列化。由于只用字符串、整数、布尔、数组和对象，且键为 ASCII，结果就是键升序、无多余空白、最小转义的 UTF-8 字节。
3. 摘要 = SHA-256（`be.<类型名>.v<主版本>` + 换行 + 规范字节），写作 `Digest`。类型名与版本作为前缀做域分隔：同样的 JSON 在不同记录类型或主版本下摘要不同。
4. 计算摘要时排除记录自身的 `digest` 字段与签名字段。

这条规则从结构上排除了旧冷数据格式的两类碰撞（I20、F04：未转义分隔符、用固定字符串表示 null）。protobuf 的确定性序列化不跨语言和版本保证规范，不用于摘要（第六份已引官方说明）。

## 共同引用与封装

| 结构 | 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- | --- |
| `PrincipalRef` | `deployment` | `Id` | 是 | 部署身份 |
| | `kind` | `Enum` | 是 | `user`、`service`、`job` |
| | `id` | `Id` | 是 | 平台稳定主体；不是邮箱、登录名或外部 IdP 的 subject |
| `ObjectRef` | `owner_component` | `Key` | 是 | 权威属主组件 |
| | `type` | `Key` | 是 | 资源类型 |
| | `id` | `Id` | 是 | 不同类型的相同 ID 不是同一对象 |
| `RevisionRef` | `domain` | `Key` | 是 | 修订域，例如 `authz.security.legal_entity`；只在同一域内比较 |
| | `value` | `Text` | 是 | 不透明；比较规则由域声明（多数为十进制整数文本） |
| `DefinitionRef` | `owner_component` | `Key` | 是 | — |
| | `kind` | `Enum` | 是 | `resource`、`operation`、`field`、`dimension`、`role_template` |
| | `key` | `Key` | 是 | — |
| | `version` | `Text` | 是 | 定义版本 |
| | `digest` | `Digest` | 是 | 定义内容的摘要；版本相同摘要不同即视为不相容 |
| `TimeWindow` | `from` | `Instant` | 是 | 含 |
| | `until` | `Instant` | 否 | 不含；缺省表示无固定终点，只允许用于声明允许它的记录类型 |
| `EvidenceRef` | `kind` | `Enum` | 是 | `fact`、`qualification`、`view`、`permit`、`receipt` |
| | `issuer` | `PrincipalRef` | 是 | 可信发行者 |
| | `audience` | `Key` | 是 | 用途与受众 |
| | `subject_digest` | `Digest` | 是 | 所绑定记录或内容的摘要 |
| | `issued_at` | `Instant` | 是 | — |
| | `valid` | `TimeWindow` | 条件 | 有绝对终点的证据必填；视图证据改用单调时钟（见“视图与核验”） |

**记录封装**（每条安全记录、定义、证据都带）：

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `type` | `Key` | 是 | `be.security.<name>` |
| `schema` | `Text` | 是 | `主.次` |
| `deployment` | `Id` | 是 | — |
| `authority` | `Key` | 是 | 权威属主组件 |
| `id` | `Id` | 是 | 记录身份，终身不变 |
| `revision` | `RevisionRef` | 是 | 内容修订 |
| `required_features` | `Set<Key>` | 否 | 缺省为空；读者不认识其中任一项即拒绝整条记录 |
| `digest` | `Digest` | 是 | 按“规范编码与摘要”计算 |
| `ext` | `Map<Key,…>` | 否 | 不影响授权的扩展信息 |

## 定义：资源、维度、操作与字段

由业务组件随版本提交，进入 `DefinitionRef`。

**资源定义 `be.security.resource_definition`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `type` | `Key` | 是 | 资源类型 |
| `view_operation` | `Key` | 是 | 普通读取所用操作（第一份的 view_key） |
| `dimensions` | `Map<Key,DimensionDefinition>` | 是 | 全部授权维度；没有维度时写 `{}`，不能缺省（对应现行 `data_scopes: none` 的显式要求） |
| `fields` | `Map<Key,FieldDefinition>` | 是 | 全部可输出字段；未列出的字段不得输出 |
| `shareable` | `Bool` | 否 | 缺省 `false` |
| `governance_dimension` | `Key` | 条件 | `shareable` 为真时必填：共享治理按哪个维度划分（例如法人） |

**维度定义 `DimensionDefinition`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `kind` | `Enum` | 是 | `value_set`、`org_tree`、`principal`、`relation`、`record`、`amount`（第七份） |
| `column` | `Key` | 是 | 属主表上的列或派生依赖名；查询编译用 |
| `principal_role` | `Key` | 条件 | `principal` 维必填：负责人、创建人等哪种当事人 |
| `relation_type` | `Key` | 条件 | `relation` 维必填 |
| `currency_column` | `Key` | 条件 | `amount` 维必填 |
| `pushdown` | `Enum` | 是 | `local_column`、`local_projection`、`not_pushdownable` |
| `projection_watermark` | `Key` | 条件 | `local_projection` 时必填：投影完整性水位的修订域 |

**操作定义 `be.security.operation_definition`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `key` | `Key` | 是 | 已注册权限键 |
| `resource_type` | `Key` | 是 | — |
| `purpose` | `Enum` | 是 | `read`、`special_read`、`export`、`action`、`create`、`manage` |
| `risk_class` | `Enum` | 是 | `low`、`high`；高风险使用 `W_high`（第三份）；未声明的操作不得默认为 `low` |
| `minimum_path` | `Enum` | 是 | `default`、`strict_acceptance`、`strict_barrier`；部署只能选不弱于它的路径 |
| `side_effects` | `Set<Enum>` | 是 | `business_write`、`external_command`、`job_or_subscription`、`file_capability`、`security_change`、`notification`；只读操作写 `[]` |
| `output_read_operation` | `Key` | 否 | 动作返回单据正文时用于字段裁剪的读取操作；缺省表示不返回正文 |
| `requires_appointment` | `Bool` | 是 | 是否必须选定任职（D09） |
| `self_review_rule` | `Key` | 否 | 本人自审控制所用的责任规则（D10） |
| `delegable` | `Bool` | 是 | 能否被个人委托 |
| `impersonation_allowed` | `Bool` | 是 | 只读扮演会话中能否执行；有副作用的操作必须为 `false` |
| `audit` | `Enum` | 是 | `none`、`required`；必需审计的落点按 I29 的协议 |

**字段定义 `FieldDefinition`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `class` | `Enum` | 是 | `ordinary`、`restricted`、`secret`；`secret` 永不输出 |
| `read_key` | `Key` | 条件 | `restricted` 必填 |
| `write_key` | `Key` | 否 | 缺省表示不可经普通修改写入 |
| `derived_from` | `Set<Key>` | 否 | 派生依赖：读取它要求读取全部依赖字段的资格 |
| `queryable` | `Set<Enum>` | 否 | `filter`、`sort`、`group`、`aggregate`；缺省为空，表示不能用于这些查询用途 |

## 授予段与原子

**原子 `Atom`**（按 `kind` 区分的联合）

| `kind` | 其余字段 | 约束 |
| --- | --- | --- |
| `all` | — | 显式全集 |
| `in` | `values: Set<Text>` | 可为空集，表示不匹配 |
| `tree` | `items: Set<{path: Text, mode: Enum(exact, subtree)}>` | 路径由组织节点 `Id` 以 `/` 连接，按段比较 |
| `self` | — | 只用于 `principal` 维；求值前实例化（第七份） |
| `subject_org` | `appointment: Id`，`mode: Enum(exact, subtree)` | 只用于 `org_tree` 维；只能出现在绑定了任职实例的授予中；求值前实例化为 `tree` |
| `related` | `relation_type: Key`，`anchor: Enum(subject, record)`，`max_depth: Int` | `max_depth` 至少为 1 |
| `interval` | `currency: Currency`，`lo: Decimal`（否），`lo_closed: Bool`（条件），`hi: Decimal`（否），`hi_closed: Bool`（条件） | 有 `lo` 必须有 `lo_closed`，`hi` 同理；两者都缺省等同 `all`，因此不允许 |

**授予段 `be.security.segment`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `resource_type` | `Key` | 是 | — |
| `operation` | `Key` | 是 | 一个段一个操作 |
| `atoms` | `Map<Key,Atom>` | 是 | 资源定义的每个维度恰好一个原子，不多不少（第七份规范化规则 1） |
| `read_fields` | `Set<Key>` | 是 | 可为空 |
| `write_fields` | `Set<Key>` | 是 | 可为空；每个元素必须也在 `read_fields` 中（第一份：写须可读） |
| `valid` | `TimeWindow` | 是 | — |
| `binding` | `Id` | 否 | 绑定的任职实例；缺省表示不绑定任职 |
| `source` | `Id` | 是 | 产生该段的安全记录 |
| `definition` | `DefinitionRef` | 是 | 所依据的资源定义版本 |

段的身份就是其摘要。规范化后内容相同的段摘要相同。

## 安全记录

**通用部分**（第八份的全部记录类型都带）：

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `record_type` | `Enum` | 是 | `management_unit`、`management_holding`、`role_revision`、`grant`、`institutional_share`、`delegation_edge`、`impersonation_session`、`break_glass_session`、`bootstrap_claim`、`change_plan` |
| `state` | `Enum` | 是 | `requested`、`awaiting_confirmation`、`scheduled`、`active`、`held`、`ended` |
| `end_reason` | `Enum` | 条件 | `state = ended` 时必填：`expired`、`revoked`、`relinquished`、`source_ended`、`source_narrowed`、`superseded`、`rejected`、`cancelled`、`withdrawn` |
| `held_reason` | `Enum` | 条件 | `state = held` 时必填：`security_action`、`constraint_not_computable` |
| `review_pending` | `Bool` | 否 | 缺省 `false`；部分越界待复核（第八份） |
| `predecessor` | `Id` | 否 | 续期、扩权、重新授予时引用旧记录 |
| `sources` | `List<SourceRef>` | 是 | 有效性依赖的来源；`SourceRef = {kind: Enum, ref: Id, role: Enum(ceiling, eligibility, permission_basis, target)}` |
| `valid` | `TimeWindow` | 是 | — |
| `requested_by` | `PrincipalRef` | 是 | — |
| `confirmations` | `List<Id>` | 否 | 引用确认记录 |
| `last_change` | `Id` | 是 | 最近一次生效的变更请求 |

`sources[].kind` 的取值：`management_unit`、`management_holding`、`role_revision`、`appointment`、`account`、`delegator_permissions`、`resource_governance`、`target_subject`。

**各类型的专有字段**

| 记录类型 | 专有字段（类型；必填） |
| --- | --- |
| `management_unit` | `parent: Id`（否，根单元缺省）；`managed_scope: Set<Segment>`（是，可授出上限）；`grantable_operations: Set<Key>`（是）；`management_actions: Set<Enum>`（是：`grant`、`revoke`、`edit_role`、`bind_role`、`delegate_management`、`share_governance`）；`max_subdelegation_depth: Int`（是） |
| `management_holding` | `unit: Id`；`holder: PrincipalRef`；`appointment: Id`（否）；`system_role: Enum`（否：`authorization_admin`、`audit_viewer`、`emergency_readonly`、`superuser`） |
| `role_revision` | `role: Id`；`segments_template: Set<Segment>`（段中范围原子可为 `self`、`subject_org` 等待实例化的形式）；`template_ref: DefinitionRef`（否）；`retired: Bool` |
| `grant` | `grantee: PrincipalRef`；`role_revision: Id`（否，直接授予时缺省）；`segments: Set<Segment>`；`governance_unit: Id`；`issued_by: PrincipalRef`（历史，不作为来源） |
| `institutional_share` | `resource: ObjectRef`；`recipient: PrincipalRef` 或 `group: Id`（二选一）；`segments: Set<Segment>`；`governance_unit: Id` |
| `delegation_edge` | `delegator: PrincipalRef`；`delegate: PrincipalRef`；`parent_edge: Id`（否）；`creation_cap: Set<Segment>`；`purpose: Text`；`task: ObjectRef`（否）；`allow_redelegation: Bool`；`remaining_depth: Int` |
| `impersonation_session` | `operator: PrincipalRef`；`target: PrincipalRef`；`reason: Text`；`ticket: Text`；`cap: Set<Segment>`（只含读取操作）；`notification_intent: Id`（是） |
| `break_glass_session` | `operator: PrincipalRef`；`incident: Text`；`role: Id`（预置紧急角色）；`approval: Enum(approved, post_review)`；`notification_intent: Id`；`review_due: Instant`；`review_outcome: Enum`（否：`justified`、`unjustified`） |
| `bootstrap_claim` | `match: {issuer: Text, subject: Text}` 或 `code_digest: Digest`（二选一）；`deployment_generation: RevisionRef`；`consumed_by: PrincipalRef`（否） |
| `change_plan` | 见“变更协议” |

**由其他属主拥有、Authz 保存受控视图的记录**

| 记录 | 属主 | 字段（类型；必填） |
| --- | --- | --- |
| 任职实例 `appointment` | 员工组件 | `employee: Id`；`legal_entity: Id`；`org_unit: Id`；`position: Key`；`valid: TimeWindow`；`state: Enum(planned, active, ended)`；`revision: RevisionRef` |
| 账号关联 `account_link` | IAM | `account: PrincipalRef`；`employee: Id`；`state`（通用状态）；`confirmations: List<Id>`；`revision: RevisionRef` |
| 账号状态 `account_status` | IAM | `account: PrincipalRef`；`status: Enum(active, disabled, security_frozen)`；`revision: RevisionRef` |

## 变更协议

**变更请求 `be.security.change_request`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `change_key` | `Text` | 是 | 请求者命名空间内唯一；与 `requested_by` 一起构成幂等身份 |
| `requested_by` | `PrincipalRef` | 是 | — |
| `acting_as` | `Id` | 条件 | 以管理资格操作时必填：所用的管理持有资格 |
| `direction` | `Enum` | 是 | `tighten`、`widen`、`neutral`；同时含两者的变更必须拆成两个请求 |
| `target` | `Id` | 条件 | 修改既有记录时必填 |
| `expected_revision` | `RevisionRef` | 条件 | 修改既有记录时必填：预览时的修订 |
| `candidate` | 对象 | 条件 | 放宽与新建时必填：候选记录内容（不含封装字段） |
| `candidate_digest` | `Digest` | 条件 | 有 `candidate` 时必填 |
| `source_revisions` | `List<RevisionRef>` | 否 | 预览时读取的来源修订；生效点逐项核对 |
| `reason` | `Text` | 否 | 受保护操作必填（由 profile 声明） |

**确认 `be.security.confirmation`**：`change_key`、`candidate_digest`（是；确认针对的内容）、`confirmer: PrincipalRef`（是）、`confirmer_basis: Enum(holding, deployment_owner)`（是）、`confirmed_at: Instant`（是）、`expires_at: Instant`（是）。生效点核对：确认人与申请人不是同一自然人（第八份）、内容摘要一致、未过期。

**变更结果 `be.security.change_result`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `change_key` | `Text` | 是 | — |
| `outcome` | `Enum` | 是 | `applied`、`rejected`、`processing`、`awaiting_confirmation` |
| `reason` | `Key` | 条件 | `rejected` 时必填，取自下文错误表 |
| `record` | `Id` | 条件 | `applied` 时必填 |
| `new_revision` | `RevisionRef` | 条件 | `applied` 时必填 |
| `security_revisions` | `List<RevisionRef>` | 条件 | `applied` 时必填：被推进的安全修订 |

**变更计划 `change_plan` 的专有字段**：`items: List<PlanItem>`；`previewed_at: Instant`；`expires_at: Instant`；`plan_state: Enum(draft, previewed, confirmed, executing, completed, partially_completed, cancelled)`。`PlanItem = {item_key: Text, request: change_request, item_state: Enum(pending, applied, rejected, needs_review), result: change_result（否）}`。

**包含见证 `be.security.containment_witness`**：`candidate_segment: Digest`；`ceiling_records: List<{record: Id, revision: RevisionRef}>`；`rules: Map<Key, Enum>`（每个维度所用规则：`all`、`subset`、`subtree_cover`、`interval_inside`、`self_instantiated` 等）；`split: {dimension: Key, assignments: List<{value: Text, ceiling: Id}>}`（否）；`instantiation_facts: List<RevisionRef>`；`algorithm_version: Text`；`comparisons: Int`。见证用于审计与解释，生效点现场重算（第七份）。

**依赖边 `be.security.dependency_edge`**：`dependent: Id`、`source_kind: Enum`（同 `sources[].kind`）、`source: Id`、`role: Enum`。由生效点在写入记录的同一事务中维护。

**闭包任务 `be.security.closure_task`**：`trigger_change: Id`、`source: Id`、`index_complete: Bool`（依赖索引是否完整；否则整域待复核）、`cursor: Text`（进度）、`processed: Int`、`state: Enum(running, completed, failed)`。

## 视图与核验

**授权视图 `be.security.view`**按分片发行，每个分片有自己的修订：

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `shard` | `Key` | 是 | 分片键，例如按资源类型或法人划分；分片方式由 Authz 成员声明 |
| `recovery_generation` | `RevisionRef` | 是 | 恢复代次 |
| `security_revisions` | `List<RevisionRef>` | 是 | 本分片覆盖的各依赖域水位 |
| `applicability` | `Set<Key>` | 是 | 本分片完整覆盖的资源类型；未列出的类型不能用本分片判定 |
| `subjects` | `Map<Id,SubjectEntry>` | 是 | 每个主体的有效段（第八份已与来源求交）；`SubjectEntry = {segments: Set<Segment>, accounts_disabled: Bool}` |
| `capabilities` | `Set<Key>` | 是 | 生成本分片的成员所具备的能力 |

**核验请求 `be.security.view_verify_request`**：`component: PrincipalRef`（是）、`held: List<{shard: Key, digest: Digest}>`（是）、`nonce: Text`（是，至少 128 位随机数的十六进制）。

**核验回答 `be.security.view_verify_answer`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `nonce` | `Text` | 是 | 必须等于请求中的 `nonce`；不等则丢弃，不续期 |
| `computed_at` | `Instant` | 是 | 仅供审计；组件不用它计算有效期 |
| `shards` | `List<{shard: Key, status: Enum(unchanged, changed, closed), view: be.security.view（条件）}>` | 是 | `changed` 时附新视图；`closed` 表示该分片暂时不能续发（第三份） |
| `recovery_generation` | `RevisionRef` | 是 | 与组件持有的不同时，组件丢弃全部旧视图 |

组件按第三份计算有效期：从**发出这次请求**时的单调时钟读数起算。`nonce` 让组件能确认回答是针对本次请求计算的；缓存或重放的旧回答 `nonce` 不符，被丢弃（第三份模型中的“重放”坏变体）。回答通过已认证的服务通道传输（第二份）。

**代次与修订的编码**：四类值都用 `RevisionRef`，以 `domain` 区分。

| 类别 | `domain` 的形式 | 比较 |
| --- | --- | --- |
| 恢复代次 | `authz.recovery` | 只判断相等；不同即旧视图与旧许可全部作废 |
| 安全修订 | `authz.security.<依赖域>` | 同域内按十进制整数比较 |
| 属主提交守卫代次 | `<组件>.guard.<范围>` | 同域内按十进制整数比较；仅严格路径 B 档使用 |
| 内容修订 | `<组件>.<资源类型>` | 同域内按十进制整数比较 |

## 严格路径的记录

| 记录 | 字段（类型；必填） |
| --- | --- |
| 意图 `be.security.intent`（P） | `action_key: Text`；`operation: Key`；`actor: PrincipalRef`；`represented: PrincipalRef`（否）；`appointment: Id`（否）；`delegation: Id`（否）；`resource: ObjectRef`；`resource_revision: RevisionRef`；`content_digest: Digest`；`rules_version: Text`；`activate_before: Instant`；`state: Enum(prepared, activated, terminated)` |
| 接受许可 `be.security.acceptance_permit`（A） | `intent_digest: Digest`；`owner: Key`（目标属主）；`operation: Key`；`matched_segments: Set<Digest>`；`security_revisions: List<RevisionRef>`；`recovery_generation: RevisionRef`；`accepted_at: Instant`；`activate_before: Instant`；`issuer: PrincipalRef`；`proof: EvidenceRef` |
| 业务回执 `be.security.business_receipt`（B） | `intent: Id`；`permit: Digest`；`outcome: Enum(committed, rejected, terminated)`；`business_record: ObjectRef`（条件）；`guard_generation: RevisionRef`（条件，B 档） |
| 屏障安装 `be.security.barrier_install` | `revocation: Id`；`scope: Set<Segment>`；`target_generation: RevisionRef`；`participants_version: Int` |
| 屏障回执 `be.security.barrier_receipt` | `revocation: Id`；`participant: Key`；`installed_generation: RevisionRef`；`participants_version: Int`；`installed_at: Instant` |

## 求值结果与错误

**单对象决定 `Decision`**（组件内部结构，不跨网络传输给用户）：`outcome: Enum(allowed, denied, unprovable)`；`matched_segments: Set<Digest>`；`readable_fields: Set<Key>`；`cutoff_remaining_ms: DurationMs`；`explain: Id`（否）。

**内部分类与对外表达**：下表的 reason 名称是候选，冻结时登记进新的错误目录（现行 0504 的结构：一个错误对象、目录中的 reason）。

| 内部分类 | 候选 reason | HTTP | 可重试 | 说明 |
| --- | --- | --- | --- | --- |
| 不可见 | `NOT_FOUND` | 404 | 否 | 读取与命令一致（现行 0212 的方向） |
| 可见但无此操作资格 | `PERMISSION_DENIED` | 403 | 否 | — |
| 业务控制拒绝 | 各业务 reason | 409 或 422 | 视业务 | 与授权拒绝分开 |
| 无法证明 | `AUTHORIZATION_UNPROVABLE` | 503 | 是 | 来源不可得、超期、修订不相容；不能写成“没有数据” |
| 视图过期 | `AUTHORIZATION_VIEW_EXPIRED` | 503 | 是 | 默认路径超过 `W` |
| 查询不可完成 | `QUERY_NOT_COMPLETABLE` | 422 | 否 | 有段不可下推、候选集超预算、冷层无覆盖（第七份） |
| 受限字段不可用于此查询 | `FIELD_NOT_QUERYABLE` | 422 | 否 | 第七份的排序／筛选证明不成立 |
| 查询计划已变化 | `QUERY_PLAN_CHANGED` | 409 | 否（重新查询） | 游标的计划摘要不一致 |
| 变更冲突 | `CHANGE_KEY_CONFLICT` | 409 | 否 | 同一变更键、不同内容 |
| 修订已变 | `CHANGE_REVISION_STALE` | 409 | 否（重新预览） | 生效点发现目标或来源修订已变 |
| 包含证明不成立 | `CONTAINMENT_NOT_PROVEN` | 403 | 否 | 附失败维度与原因（超出／无法证明／超预算） |
| 需要确认 | `CONFIRMATION_REQUIRED` | 202 | — | 变更进入待确认 |
| 最后管理员保护 | `LAST_ADMIN_PROTECTED` | 409 | 否 | — |
| 部署待恢复 | `RECOVERY_IN_PROGRESS` | 503 | 是 | 除恢复外的管理变更 |
| 能力不支持 | `CAPABILITY_UNSUPPORTED` | 501 | 否 | 装配时应已阻止；运行时发现则保护受影响路径 |
| 结果未知 | `RESULT_UNKNOWN` | 504 | 查询后再定 | 用变更键或动作键查询，不换键重试 |

对无权调用者，错误内容不包含金额、负责人、角色内容或证明细节（第六份）。

## 能力声明

**能力声明 `be.security.capability_descriptor`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `provider` | `Key` | 是 | 组件 ID |
| `version` | `Text` | 是 | 精确版本 |
| `artifact_digest` | `Digest` | 是 | 制品摘要 |
| `schema_versions` | `Map<Key,Text>` | 是 | 本页各记录类型所支持的 schema 版本 |
| `capabilities` | `Map<Key,{version: Text, limits: Map<Key,Int>}>` | 是 | 能力名到版本与上限（例如最大段数、最大链深） |
| `evidence` | `Map<Key,Enum(declared, implemented, verified)>` | 是 | 每项能力的证据状态；装配只接受 `verified` 用于生产 |

**能力目录（候选）**

| 能力 | 含义 | 依赖 |
| --- | --- | --- |
| `authz.core` | 完整段求值、三值结果、字段按命中段 | — |
| `authz.list.complete` | 查询编译与命中位图（第七份） | `authz.core` |
| `authz.atom.related` | 关系原子：投影或完整候选集 | `authz.list.complete` |
| `authz.containment.single` | 单段包含证明 | `authz.core` |
| `authz.containment.split` | 单维拆分覆盖 | `authz.containment.single` |
| `authz.management.delegated` | 受限分级管理（D35） | `authz.containment.single` |
| `authz.share.institutional` | 机构共享 | `authz.containment.single` |
| `authz.delegation.single` | 单层个人委托 | `authz.core` |
| `authz.delegation.chain` | 有限多层委托 | `authz.delegation.single` |
| `authz.impersonation.readonly` | 只读扮演会话 | `authz.core`，部署有站内通知能力 |
| `authz.break_glass` | 紧急访问会话 | `authz.core`，所选 IAM 成员有独立认证路径 |
| `authz.recovery.owner` | 部署所有者确认与恢复 | — |
| `authz.path.bounded_local` | 默认路径：视图核验、`nonce`、分片 | `authz.core` |
| `authz.path.strict_acceptance` | 严格路径 A 档 | `authz.path.bounded_local` |
| `authz.path.strict_barrier` | 严格路径 B 档 | `authz.path.strict_acceptance`，以及各业务属主的提交守卫 |

**准入检查**：装配工具从启用的资源、操作、列表用途、实际用到的原子种类、启用的记录类型与路径，推出所需能力集合，逐项与所选成员的能力声明比较（版本兼容、上限满足、证据为 `verified`），列出缺口；有缺口则阻止装配或启用，不静默降级（D07）。

## profile

**操作 profile**（部署级，按操作键逐条）：

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `operation` | `Key` | 是 | — |
| `risk_class` | `Enum` | 否 | 只能比定义中更严（`low` 改 `high`），不能放宽 |
| `path` | `Enum` | 否 | 不弱于定义中的 `minimum_path` |
| `w_ms` | `DurationMs` | 否 | 该操作所用视图有效期；`high` 时允许 1–10 秒，`low` 时允许 5–300 秒 |

**生命周期 profile**（按记录类型）：

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `record_type` | `Enum` | 是 | — |
| `confirmations_required` | `Int` | 是 | 受保护操作至少为 1（第八份） |
| `confirmer_basis` | `Set<Enum>` | 是 | `holding`、`deployment_owner` |
| `confirmation_valid_ms` | `DurationMs` | 是 | 起始值 72 小时 |
| `max_validity_ms` | `DurationMs` | 否 | 缺省表示允许无固定终点，只对声明允许的类型有效（例如机构共享） |
| `notify` | `Set<Enum>` | 是 | `recipient`、`target_subject`、`admins`、`resource_owner` |
| `review_within_ms` | `DurationMs` | 否 | 紧急访问起始值 2 个工作日 |
| `max_chain_depth` | `Int` | 否 | 委托边；基础 profile 为 1 |

起始值与第三份、第八份的参数表一致，待评审与实测。

## 参考检查

[规范编码检查](../work/checks/11-canonical-encoding.py)按本页的规则实现规范化与摘要（种子 20261013）：语义相同的段（字段顺序、集合顺序、`100.00` 与 `1E2`、`+08:00` 与 `Z`）摘要相同；60,000 个随机值（含分隔符、引号、反斜杠、控制字符、非 BMP 字符、各种显式存在状态）没有两个不同值得到相同规范字节；不同记录类型或主版本的同一 JSON 摘要不同；旧规则的两组 F04 反例碰撞、新规则区分；“路径 + 查询 + 请求体直接拼接”的指纹碰撞、规范数组不碰撞。5 个坏变体（集合不排序、十进制不规范、时刻保留偏移、缺类型前缀、键不排序）全部使检查失败。检查只覆盖编码规则本身，不是三门 SDK 的实现。

## 独立预期

| 编号 | 场景 | 固定预期 |
| --- | --- | --- |
| EN01 | 同一段由三门语言各自规范化并计算摘要 | 字节与摘要完全一致（共同向量） |
| EN02 | 金额 `100.00`、`100`、`1E2` | 规范形式都是 `100`，摘要一致 |
| EN03 | 同一时刻以不同时区偏移提交 | 规范为同一个 UTC 文本 |
| EN04 | 记录中出现 JSON `null` 或浮点数 | 拒绝 |
| EN05 | 记录的 `required_features` 含读者不认识的项 | 拒绝整条记录，不忽略后放行 |
| EN06 | 次版本新增 `ext` 内的字段 | 旧读者可忽略，摘要按新内容计算 |
| EN07 | 新原子种类出现在旧读者 | 因主版本或 `required_features` 被拒绝 |
| EN08 | 段的 `atoms` 少一个资源定义的维度，或多一个未定义维度 | 拒绝 |
| EN09 | `write_fields` 含不在 `read_fields` 中的字段 | 拒绝 |
| EN10 | `interval` 只给 `hi` 不给 `hi_closed`，或两端都缺 | 拒绝 |
| EN11 | `subject_org` 出现在没有绑定任职的授予中 | 拒绝 |
| EN12 | 两个修订域的值按整数比较 | 不允许；只在同域内比较 |
| EN13 | 核验回答的 `nonce` 与请求不符 | 丢弃，不续期 |
| EN14 | 核验回答的恢复代次与组件持有的不同 | 丢弃全部旧视图 |
| EN15 | 视图分片的 `applicability` 不含某资源类型 | 不用该分片判定该类型 |
| EN16 | 操作 profile 把 `high` 改成 `low`，或路径弱于 `minimum_path` | 装配拒绝 |
| EN17 | 能力声明中某能力证据为 `declared`，生产部署启用依赖它的功能 | 装配拒绝 |
| EN18 | 变更请求同时含收紧与放宽 | 拒绝，要求拆成两个请求 |
| EN19 | 确认的 `candidate_digest` 与生效时的候选内容不同 | 确认无效 |
| EN20 | 错误回答中出现无权查看的金额或负责人 | 不允许；只给 reason 与可显示信息 |

## 仍未解决与下一步

- 冻结时由本页生成 protobuf 与 JSON Schema，并写出三门语言的共同向量（EN、FX、CP、AT、PA 合并映射）。
- 视图分片方式、分片大小与核验频率对 Authz 负载的影响，需在代表实验中测量。
- 错误 reason 的最终名称、HTTP 映射与可显示文案在新错误目录中统一登记。
- 能力目录的最终命名与版本规则，随第 4 项（provider 能力与成员切换）一起确定。

## 依据与独立判断

[RFC 8785](https://www.rfc-editor.org/rfc/rfc8785) 定义了 JSON 的规范化序列化；本项目进一步禁止浮点与 JSON null、要求类型与版本前缀，使规范形式在三门语言中容易一致实现。显式存在状态、未知取值即拒绝、`required_features` 的思路与 JWT 的 `crit` 头（[RFC 7515 §4.1.11](https://www.rfc-editor.org/rfc/rfc7515#section-4.1.11)）相同：安全相关的扩展必须被理解才能使用。核验回答绑定请求随机数是防重放的通行做法。

知识库没有“结构化数据的规范化编码与内容摘要”这一主题；其《幂等键》中的请求指纹写作“拼接后算 SHA-256”，未要求无歧义分帧，本页的检查复现了拼接碰撞。已作为反馈提交（见证据记录）。
