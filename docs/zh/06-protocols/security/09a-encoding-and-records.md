# 安全记录的正式编码

本页把安全 01–08 中的结构落到逐字段：基本类型、规范编码与摘要、共同引用与封装、定义、授予段、安全记录、变更协议、视图与核验、严格路径的记录、求值结果与错误。写给实现 SDK、授权成员与契约生成工具的人。能力声明与 profile 在[安全 09b](09b-capabilities-and-profiles.md)。这是新契约的第一版（D59），不对齐旧的契约或 SDK。

## 本页的形式

本页用字段表写定语义：字段名、类型、是否必填、约束。JSON Schema 由这些表生成（见下一段）；protobuf 只作信封，写在各成员的契约包里。摘要与签名只按本页定义的规范 JSON 形式计算，不使用任何语言或 protobuf 的二进制序列化结果（[安全 06](06-security-contracts-and-capabilities.md#共同标识与封装)引用了官方说明）。

**线上怎样传**（D76）：系统面照常是 gRPC 加 protobuf，但安全记录（视图分片、授予段、定义等本页定义的记录）本身以规范 JSON 字节放在 protobuf 信封的 `bytes` 字段里传输，按本页生成的 JSON Schema 校验；信封只承载调用本身的字段（随机数、分片号与状态、恢复代次、回执等）。接收方直接对收到的字节核对摘要，不把 protobuf 还原成规范 JSON。线上的记录字节不含记录自己的 `digest`：摘要放在信封里与字节并列，接收方对收到的字节计算摘要并比较；字节不是规范形式（解析后重新规范化，结果不同）的，整条拒绝。JSON Schema 由本页与组件协议第 08 章的字段表生成（`be-acceptance` 的 `doc-checks/security-schemas.py`），放在 `be-protocol` 的 `schemas/security/`，每种记录类型一份；schema 只查结构与类型，约束一列的条件规则由代码检查。

“必填”一列：**是**表示缺失即无效；**否**表示可以缺省，缺省有明确的含义（写在约束里）；**条件**表示在约束所述的情况下必填。

## 编码约定

### 基本类型

| 类型 | 线上表示 | 规范形式与约束 |
| --- | --- | --- |
| `Id` | 字符串 | 小写 UUIDv7 文本，36 个字符；只表示身份，不携带任何权限 |
| `Key` | 字符串 | 注册键，`[a-z][a-z0-9_]*` 以点分段，最长 128 字符；权限键、操作、资源类型、维度、字段、能力、记录类型都用它 |
| `ComponentId` | 字符串 | 组件 ID `<领域>/<名字>`，与 BrickKit 的组件 ID 同一写法：两段各为小写字母、数字与连字符，不以连字符开头或结尾（例如 `infra/authz`、`test/probe-go`）；不能用 `Key`，因为它不允许 `/` 与 `-`；服务身份证书里的组件就是它（协议 P8.5） |
| `Text` | 字符串 | UTF-8，按 Unicode NFC 规范化后存储与计算摘要；不用于任何授权判断 |
| `Decimal` | 字符串 | 无指数、无前导 `+`、无多余的前导零与末尾零，整数不带小数点，零写作 `0`；最多 38 位有效数字，小数位不超过 18 |
| `Currency` | 字符串 | ISO 4217 三位大写字母 |
| `Instant` | 字符串 | UTC，`YYYY-MM-DDTHH:MM:SS.ffffffZ`，固定 6 位小数 |
| `Date` | 字符串 | 业务日期 `YYYY-MM-DD`，按法人的业务时区解释 |
| `DurationMs` | 整数 | 毫秒，非负 |
| `Int` | 整数 | 进入摘要的整数绝对值小于 2^53；可能更大的计数一律用 `RevisionRef`（值为十进制整数文本） |
| `Bool` | 布尔 | — |
| `Enum` | 字符串 | 小写下划线；每个 schema 版本列出全部取值；读者遇到未知取值时，安全相关的字段拒绝整条记录，非安全字段按“未知”处理 |
| `Set<T>` | 数组 | 按元素的规范字节升序排列、去重；空集写作 `[]`，表示“空”，不表示“全部” |
| `List<T>` | 数组 | 顺序有含义 |
| `Map<K,T>` | 对象 | 键为 `Key` 或 `Id`，由字段说明 |
| `Presence<T>` | 对象 | 显式的存在性：`{"state":"value","value":…}`、`{"state":"null"}`、`{"state":"unobtained"}`、`{"state":"unsupported"}`；只用于事实属性（安全 06 要求区分已知空、已知 null、未取得、不支持） |
| `Digest` | 字符串 | `sha256:` 加 64 位小写十六进制 |

全部编码中不出现 JSON `null` 与浮点数。可选字段缺省，就是不写这个键；需要表达“已知为 null”时用 `Presence`。

### 名称、类型与版本

- 字段名为小写下划线 ASCII。
- 每种记录有记录类型 `be.security.<name>` 与 schema 版本 `主.次`。
- **次版本**只能增加不影响任何授权判断的可选字段；这类字段放在每条记录的 `ext` 对象里，读者不认识可以忽略。
- **任何能限制或放行访问的新内容**（新的原子种类、新条件、新来源类型、新状态）都提升主版本，或者把功能名写进记录的 `required_features`。读者遇到不认识的 `required_features` 必须拒绝整条记录，不能忽略后继续放行（[安全 06 的版本演进](06-security-contracts-and-capabilities.md#版本演进与切换准入)）。

### 规范编码与摘要

1. 先规范化：集合排序去重；十进制与时刻写成规范形式；文本按 NFC 规范化；缺省的字段不写；授予段按[安全 07 的段的规范化](07-finite-expressions-containment-and-queries.md#段的规范化)处理。
2. 再按 [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785)（JSON 规范化方案）序列化。由于只用字符串、整数、布尔、数组与对象，且键为 ASCII，结果就是键升序、无多余空白、最小转义的 UTF-8 字节。
3. 摘要 = SHA-256（`<记录类型>.v<主版本>` + 换行 + 规范字节），写作 `Digest`；例如授予段的前缀是 `be.security.segment.v1`。记录类型与主版本作为前缀做域分隔：同样的 JSON 在不同的记录类型或主版本下摘要不同。
4. 计算摘要时排除记录自身的 `digest` 字段与签名字段。

这条规则从结构上排除了旧的冷数据摘要格式的两类碰撞：未转义的分隔符，以及用固定字符串表示 null。

## 共同引用与封装

| 结构 | 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- | --- |
| `PrincipalRef` | `deployment` | `Id` | 是 | 部署身份 |
| | `kind` | `Enum` | 是 | `user`、`service`、`job` |
| | `id` | `Id` | 是 | 平台的稳定主体；不是邮箱、登录名或外部身份源的 subject |
| `ObjectRef` | `owner_component` | `ComponentId` | 是 | 权威属主组件 |
| | `type` | `Key` | 是 | 资源类型 |
| | `id` | `Id` | 是 | 不同类型的相同 ID 不是同一对象 |
| `RevisionRef` | `domain` | `Key` | 是 | 修订域，例如 `authz.security.legal_entity`；只在同一域内比较 |
| | `value` | `Text` | 是 | 不透明；比较规则由域声明（多数为十进制整数文本） |
| | `epoch` | `Text` | 否 | 库内分配、别处比较的计数所带的纪元（[协议 14 的库内计数与纪元](../14-data-foundations.md#库内计数与纪元)）；有它的域，比较按协议 14：同一纪元按整数，不同纪元用分叉点判断旧值是否仍被包含 |
| | `instance` | `Text` | 否 | 分配处的实现实例（例如授权成员实例）；分配处可以被另一个实现替换时必填。不同实例的值不按数值比较，只经登记的包含关系比较（协议 14） |
| `DefinitionRef` | `owner_component` | `ComponentId` | 是 | — |
| | `kind` | `Enum` | 是 | `resource`、`operation`、`field`、`dimension`、`role_template` |
| | `key` | `Key` | 是 | — |
| | `version` | `Text` | 是 | 定义的版本 |
| | `digest` | `Digest` | 是 | 定义内容的摘要；版本相同、摘要不同，即视为不相容 |
| `TimeWindow` | `from` | `Instant` | 是 | 含 |
| | `until` | `Instant` | 否 | 不含；缺省表示无固定终点，只允许用于声明允许它的记录类型 |
| `EvidenceRef` | `kind` | `Enum` | 是 | `fact`、`qualification`、`view`、`permit`、`receipt` |
| | `issuer` | `PrincipalRef` | 是 | 可信的发行者 |
| | `audience` | `Key` | 是 | 用途与受众 |
| | `subject_digest` | `Digest` | 是 | 所绑定的记录或内容的摘要 |
| | `issued_at` | `Instant` | 是 | — |
| | `valid` | `TimeWindow` | 条件 | 有绝对终点的证据必填；视图证据改用单调时钟（见[视图与核验](#视图与核验)） |

**记录封装**：每条安全记录、定义与证据都带下列字段。

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `record_type` | `Key` | 是 | `be.security.<name>`；记录类型只由这个字段表达 |
| `schema` | `Text` | 是 | `主.次` |
| `deployment` | `Id` | 是 | — |
| `authority` | `ComponentId` | 是 | 权威属主组件 |
| `id` | `Id` | 是 | 记录身份，终身不变 |
| `revision` | `RevisionRef` | 是 | 内容修订 |
| `required_features` | `Set<Key>` | 否 | 缺省为空；读者不认识其中任一项即拒绝整条记录 |
| `digest` | `Digest` | 是 | 按[规范编码与摘要](#规范编码与摘要)计算 |
| `ext` | `Map<Key,…>` | 否 | 不影响授权的扩展信息 |

## 定义：资源、维度、操作与字段

定义由业务组件随版本提交，通过 `DefinitionRef` 引用。**提交的核对**：授权组件只接受服务身份（安全 02）等于 `DefinitionRef.owner_component` 的提交，并且对**全部定义种类**（资源、操作、字段、维度、角色模板、附件类别）核对：所指的资源类型在注册表中登记的属主就是提交者，操作所用的权限键在注册表中的属主也是提交者；同一个键只接受一个属主的提交。**角色模板按组件拆分**：每个组件只提交引用自己资源类型与权限键的模板片段；跨组件的标准角色（例如“销售主管”）由授权组件按片段的角色名合成，每个片段各自经属主核对，不由某一个组件提交整套。资源类型、权限键与附件类别的键在注册表中登记属主（[协议 19 的注册表](../19-config-secrets-registries-release.md#注册表)），一个资源类型只有一个属主，提交的属主与登记不符时拒绝并记录安全事件。其他组件（例如附件组件核对“申请者是父资源类型的属主”，[协议 12](../12-attachments-and-object-storage.md#访问凭证)）以授权组件保存的、经过这一核对的定义为依据。

**资源定义 `be.security.resource_definition`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `type` | `Key` | 是 | 资源类型 |
| `view_operation` | `Key` | 是 | 普通读取所用的操作（[安全 01](01-authorization-evaluation.md#可信输入与资源声明) 的 `view_key`） |
| `dimensions` | `Map<Key,DimensionDefinition>` | 是 | 全部授权维度；没有维度时写 `{}`，不能缺省（安全设置不能默认关闭） |
| `fields` | `Map<Key,FieldDefinition>` | 是 | 全部可输出的字段；未列出的字段不得输出 |
| `shareable` | `Bool` | 否 | 缺省 `false` |
| `governance_dimension` | `Key` | 条件 | `shareable` 为真时必填：共享治理按哪个维度划分（例如法人） |
| `extensible` | `Bool` | 否 | 缺省 `false`；为真时允许客户扩展字段（[协议 08](../08-extension-fields.md)） |
| `extension_quota` | `Map<Key,Int>` | 条件 | `extensible` 为真时必填：字段数、可排序字段数、单条扩展数据的字节数、多值上限 |
| `attachment_categories` | `Map<Key,AttachmentCategory>` | 否 | 这个资源类型的记录可以带哪些附件类别；缺省为空，表示不能带附件 |

**附件类别 `AttachmentCategory`**（[协议 12 的附件类别](../12-attachments-and-object-storage.md#附件类别)）

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `field` | `Key` | 是 | 类别在父资源上对应的字段（`fields` 中已定义）；属主按它的读写资格判断用户能否读写这类附件 |
| `max_bytes` | `Int` | 是 | 不超过附件组件的全局上限 |
| `allowed_types` | `Set<Text>` | 是 | 允许的内容类型（按服务端检测） |
| `sensitivity` | `Enum` | 是 | `normal`、`strict`；`strict` 不签发预签名下载地址 |
| `retention_class` | `Key` | 是 | 协议 11 的保留类别 |
| `version` | `Text` | 是 | 类别的版本；附件记录保存创建时的版本 |

**维度定义 `DimensionDefinition`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `kind` | `Enum` | 是 | `value_set`、`org_tree`、`principal`、`relation`、`record`、`amount`（安全 07） |
| `column` | `Key` | 是 | 属主表上的列或派生依赖名；查询编译用 |
| `principal_role` | `Key` | 条件 | `principal` 维必填：负责人、创建人等哪种当事人 |
| `relation_type` | `Key` | 条件 | `relation` 维必填 |
| `currency_column` | `Key` | 条件 | `amount` 维必填 |
| `pushdown` | `Enum` | 是 | `local_column`、`local_projection`、`not_pushdownable` |
| `projection_watermark` | `Key` | 条件 | `local_projection` 时必填：投影完整性水位的修订域 |

**操作定义 `be.security.operation_definition`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `key` | `Key` | 是 | 已注册的权限键 |
| `resource_type` | `Key` | 是 | — |
| `purpose` | `Enum` | 是 | `read`、`special_read`、`export`、`action`、`create`、`manage` |
| `risk_class` | `Enum` | 是 | `low`、`high`；高风险使用 `W_high`（安全 03）；未声明的操作不得默认为 `low` |
| `tightening_only` | `Bool` | 否 | 缺省 `false`；为真表示这个操作只会减少访问（停用、冻结、撤销会话、撤销、放弃），来源水位超期时可以按最后已应用的事实判断请求者资格（安全 03 的有限度规则）；只有 `purpose = manage` 且 `side_effects` 只含 `security_change` 的操作可以声明，并且操作在属主的处理中只能结束、暂停或收窄记录（属主的一致性测试检查）；不满足的声明在提交时拒绝 |
| `minimum_path` | `Enum` | 是 | `default`、`strict_acceptance`、`strict_barrier`；部署只能选不弱于它的路径 |
| `side_effects` | `Set<Enum>` | 是 | `business_write`、`external_command`、`job_or_subscription`、`file_capability`、`security_change`、`notification`；只读操作写 `[]` |
| `output_read_operation` | `Key` | 否 | 动作返回单据正文时用于字段裁剪的读取操作；缺省表示不返回正文 |
| `requires_appointment` | `Bool` | 是 | 是否必须选定任职（D09） |
| `self_review_rule` | `Key` | 否 | 本人自审控制所用的责任规则（D10） |
| `delegable` | `Bool` | 是 | 能否被个人委托 |
| `impersonation_allowed` | `Bool` | 是 | 只读扮演会话中能否执行；有副作用的操作必须为 `false` |
| `audit` | `Enum` | 是 | `none`、`required`；必需审计的落点按[协议 03](../03-audit-durability.md) |

**字段定义 `FieldDefinition`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `class` | `Enum` | 是 | `ordinary`、`restricted`、`secret`；`secret` 永不输出 |
| `read_key` | `Key` | 条件 | `restricted` 必填 |
| `write_key` | `Key` | 否 | 缺省表示不能经普通修改写入 |
| `derived_from` | `Set<Key>` | 否 | 派生依赖：读取它，要求有读取全部依赖字段的资格 |
| `queryable` | `Set<Enum>` | 否 | `filter`、`sort`、`group`、`aggregate`；缺省为空，表示不能用于这些查询用途 |

**定义集合 `be.security.definition_set`**：一个组件的一个版本提交的全部定义，只用来算“被接受的摘要”，不另外保存。同一组件、同一版本再次提交同一集合，按幂等接受；版本相同、集合不同，整次拒绝（`DEFINITION_VERSION_CONFLICT`）：改了定义就要升版本。

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `component` | `ComponentId` | 是 | 提交者，等于它的服务身份 |
| `version` | `Text` | 是 | 组件的精确版本 |
| `definitions` | `Set<Digest>` | 是 | 每份定义（资源定义、操作定义）的摘要 |

## 授予段与原子

**原子 `Atom`**（按 `kind` 区分的联合）

| `kind` | 其余字段 | 约束 |
| --- | --- | --- |
| `all` | — | 显式全集 |
| `in` | `values: Set<Text>` | 可以为空集，表示不匹配 |
| `tree` | `items: Set<{path: Text, mode: Enum(exact, subtree)}>` | 路径由组织节点的 `Id` 以 `/` 连接，按段比较 |
| `self` | — | 只用于 `principal` 维；求值前实例化（安全 07） |
| `subject_org` | `appointment: Id`，`mode: Enum(exact, subtree)` | 只用于 `org_tree` 维；只能出现在绑定了任职实例的授予中；求值前实例化为 `tree` |
| `related` | `relation_type: Key`，`anchor: Enum(subject, record)`，`max_depth: Int` | `max_depth` 至少为 1 |
| `interval` | `currency: Currency`，`lo: Decimal`（否），`lo_closed: Bool`（条件），`hi: Decimal`（否），`hi_closed: Bool`（条件） | 有 `lo` 必须有 `lo_closed`，`hi` 同理；两者都缺省等同于 `all`，所以不允许 |

**授予段 `be.security.segment`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `resource_type` | `Key` | 是 | — |
| `operation` | `Key` | 是 | 一个段一个操作 |
| `atoms` | `Map<Key,Atom>` | 是 | 资源定义的每个维度恰好一个原子，不多不少（安全 07 的规范化规则 1） |
| `read_fields` | `Set<Key>` | 是 | 可以为空 |
| `write_fields` | `Set<Key>` | 是 | 可以为空；每个元素必须也在 `read_fields` 中（安全 01：写须可读） |
| `valid` | `TimeWindow` | 是 | — |
| `binding` | `Id` | 否 | 绑定的任职实例；缺省表示不绑定任职 |
| `source` | `Id` | 是 | 产生该段的安全记录 |
| `definition` | `DefinitionRef` | 是 | 所依据的资源定义版本 |

段的身份就是它的摘要；规范化后内容相同的段摘要相同。

## 安全记录

**通用部分**（[安全 08](08-state-and-change-protocol.md) 的全部记录类型都带）。记录类型由封装的 `record_type` 表达，取值为 `be.security.` 加上 `management_unit`、`management_holding`、`role_revision`、`grant`、`institutional_share`、`delegation_edge`、`impersonation_session`、`break_glass_session`、`bootstrap_claim`、`change_plan` 之一（安全处置另有字段表，见下文）。

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `state` | `Enum` | 是 | `requested`、`awaiting_confirmation`、`scheduled`、`active`、`held`、`ended`（安全 08 的通用生命周期） |
| `end_reason` | `Enum` | 条件 | `state = ended` 时必填：`expired`、`revoked`、`relinquished`、`source_ended`、`source_narrowed`、`superseded`、`rejected`、`cancelled`、`withdrawn`；各自的含义见安全 08 |
| `held_reason` | `Enum` | 条件 | `state = held` 时必填：`security_hold`、`uncomputable`、`restore_pending` |
| `review_pending` | `Bool` | 否 | 缺省 `false`；部分越界待复核（安全 08） |
| `confirmation_backfill_pending` | `Bool` | 否 | 只用于授权管理员持有资格：账号经控制台直接重新启用、事件不带合格的确认 ID 时为 `true`，按不可用处理（安全 08 的“待补确认”） |
| `predecessor` | `Id` | 否 | 续期、扩权、改目标、重新授予时引用旧记录 |
| `sources` | `List<SourceRef>` | 是 | 有效性依赖的来源；`SourceRef = {kind: Enum, ref: Id, role: Enum(ceiling, eligibility, permission_basis, target)}` |
| `valid` | `TimeWindow` | 是 | — |
| `requested_by` | `PrincipalRef` | 是 | — |
| `state_revision` | `RevisionRef` | 是 | 每次状态迁移推进一次，与内容修订分开（安全 08 的状态迁移）；派生键与作业触发按它核对 |
| `confirmations` | `List<Id>` | 否 | 引用确认记录 |
| `last_change` | `Id` | 是 | 最近一次生效的变更请求 |

`sources[].kind` 的取值：`management_unit`、`management_holding`、`role_revision`、`appointment`、`account`、`delegator_permissions`、`resource_governance`、`target_subject`。

**安全处置 `be.security.security_disposition`** 不带通用部分，字段如下（安全 08 的安全处置）：

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `state` | `Enum` | 是 | `active`、`released` |
| `origin` | `Enum` | 是 | `admin`（处置人提交）、`identity_side`（身份侧信号，治理域为部署全局）、`admin_recovery` |
| `subject_employee` | `Id` | 否 | 处置时关联的员工 |
| `accounts` | `Set<Id>` | 是 | 处置时的账号 |
| `suspended_segments` | `Set<Segment>` | 是 | 被暂停的范围；`identity_side` 时为该自然人的全部段 |
| `domain` | `Id` | 是 | 治理域 |
| `disposer` | `PrincipalRef` | 条件 | `origin = admin` 时必填；`admin_recovery` 时为部署所有者 |
| `confirmations` | `List<Id>` | 否 | 处置或解除其他授权管理员时的确认 |
| `signal_ref` | `Set<Text>` | 条件 | `origin = identity_side` 时必填：（账号，引起冻结或标记的证据记录身份）的集合：后来的冻结在已有生效中的处置时并入它；同一账号至多一条 `state = active` 的 `identity_side` 处置（安全 08 的身份侧处置的派生） |
| `released_by` | `PrincipalRef` | 条件 | `state = released` 时必填 |

**部署的授权状态 `be.security.deployment_admin_state`**：`state: Enum(operational, recovery_pending, admin_recovery)`（是）；`unavailable_holdings: List<{holding: Id, cause: Enum(security_disposition, source_fact, expired, uncomputable, confirmation_backfill)}>`（`recovery_pending` 时必填）；`entered_from: Enum(operational, recovery_pending)`（`admin_recovery` 时必填，中止时回到它）；`since: Instant`（是）。

**各类型的专有字段**

| 记录类型 | 专有字段（类型；必填） |
| --- | --- |
| `management_unit` | `parent: Id`（否，根单元缺省）；`managed_scope: Set<Segment>`（是，可授出上限）；`grantable_operations: Set<Key>`（是）；`management_actions: Set<Enum>`（是：`grant`、`revoke`、`edit_role`、`bind_role`、`delegate_management`、`share_governance`）；`max_subdelegation_depth: Int`（是） |
| `management_holding` | `unit: Id`；`holder: PrincipalRef`；`appointment: Id`（否）；`system_role: Enum`（否：`authorization_admin`、`audit_viewer`、`emergency_readonly`、`superuser`） |
| `role_revision` | `role: Id`；`segments_template: Set<Segment>`（段中的范围原子可以是 `self`、`subject_org` 等待实例化的形式）；`template_ref: DefinitionRef`（否）；`retired: Bool` |
| `grant` | `grantee: PrincipalRef`；`role_revision: Id`（否，直接授予时缺省）；`segments: Set<Segment>`；`governance_unit: Id`；`issued_by: PrincipalRef`（历史，不作为来源） |
| `institutional_share` | `resource: ObjectRef`；`recipient: PrincipalRef` 或 `group: Id`（二选一）；`segments: Set<Segment>`；`governance_unit: Id` |
| `delegation_edge` | `delegator: PrincipalRef`；`delegate: PrincipalRef`；`parent_edge: Id`（否）；`creation_cap: Set<Segment>`；`purpose: Text`；`task: ObjectRef`（否）；`allow_redelegation: Bool`；`remaining_depth: Int` |
| `impersonation_session` | `operator: PrincipalRef`；`target: PrincipalRef`；`reason: Text`；`ticket: Text`；`cap: Set<Segment>`（只含读取操作）；`notification_intent: Id`（是） |
| `break_glass_session` | `operator: PrincipalRef`；`incident: Text`；`role: Id`（预置的紧急角色）；`approval: Enum(approved, post_review)`；`notification_intent: Id`；`review_due: Instant`；`review_outcome: Enum`（否：`justified`、`unjustified`） |
| `bootstrap_claim` | `match: {issuer: Text, subject: Text}` 或 `code_digest: Digest`（二选一）；`deployment_generation: RevisionRef`；`consumed_by: PrincipalRef`（否） |
| `change_plan` | 见[变更协议](#变更协议) |

**由其他属主拥有、授权组件保存受控视图的记录**

| 记录 | 属主 | 字段（类型；必填） |
| --- | --- | --- |
| 任职实例 `appointment` | 员工组件 | `employee: Id`；`legal_entity: Id`；`org_unit: Id`；`position: Key`；`valid: TimeWindow`；`state: Enum(planned, active, ended)`；`revision: RevisionRef` |
| 账号关联 `account_link` | 员工组件（确认记录在授权组件） | `account: PrincipalRef`；`employee: Id`；`state`（通用状态）；`confirmations: List<Id>`；`revision: RevisionRef` |
| 账号状态 `account_status` | 身份组件 | 见下表（带记录封装，`authority` 是身份成员） |

**账号状态 `be.security.account_status`**：身份成员发出（事件 `infra.iam.account_status_changed.v1`，[contract-infra-iam](https://github.com/brickKit/contract-infra-iam)），授权组件保存受控视图；修订在身份成员的库内分配。

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `account` | `PrincipalRef` | 是 | `kind` 为 `user` |
| `status` | `Enum` | 是 | `active`、`disabled`、`security_frozen` |
| `security_mark` | `Enum` | 否 | `none`、`compromised`、`suspicious`；停用或冻结时可以带，身份侧处置按它派生（安全 08）；缺省等于 `none` |

## 变更协议

**变更请求 `be.security.change_request`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `change_key` | `Text` | 是 | 请求者命名空间内唯一；与 `requested_by` 一起构成幂等身份，绑定规则只在[安全 08 的变更键](08-state-and-change-protocol.md#生效点)；作业触发的生效使用授权组件命名空间中的派生键 `<记录身份>:<状态修订>:<触发种类>` |
| `requested_by` | `PrincipalRef` | 是 | — |
| `trigger` | `Enum(user, job, recovery)` | 是 | 由生效点从调用通道得出（恢复命令的通道、授权组件自己的工作项），不由请求自称；`recovery` 另要求恢复凭据在同一通道上已核对 |
| `expected_state_revision` | `RevisionRef` | 条件 | 作业触发、终止与批量计划的项必填：触发或预览时记录的状态修订（安全 08 决策表第 3、4、17 行） |
| `termination` | `Enum(withdraw, reject, cancel)` | 条件 | 终止尚未生效的记录时必填：收回、拒绝走安全 08 决策表第 7 行，取消按普通收紧；子类与请求者的身份不符（例如管理者以 `withdraw` 终止别人的申请）时按第 8 行驳回（`PERMISSION_DENIED`） |
| `acting_as` | `Id` | 条件 | 以管理资格操作时必填：所用的管理持有资格 |
| `direction` | `Enum` | 是 | `tighten`、`widen`、`neutral`、`restore_security_hold`、`restore_uncomputable`（安全 08 的变更种类）；同时含收紧与放宽的变更必须拆成两个请求 |
| `confirmation_ids` | `Set<Id>` | 否 | 附上的确认记录 |
| `target` | `Id` | 条件 | 修改既有记录时必填 |
| `expected_revision` | `RevisionRef` | 条件 | 修改既有记录时必填：预览时的修订 |
| `candidate` | 对象 | 条件 | 放宽与新建时必填：候选记录内容（不含封装字段） |
| `candidate_digest` | `Digest` | 条件 | 有 `candidate` 时必填 |
| `effective_from` | `Instant` | 否 | 声明的未来生效时间；缺省表示确认齐全后立即经过生效点 |
| `source_revisions` | `List<RevisionRef>` | 否 | 预览时读取的来源修订；生效点逐项核对 |
| `reason` | `Text` | 否 | 受保护操作必填（由 profile 声明） |

**确认 `be.security.confirmation`**：`change_key`（否；针对已提交的放宽请求时填写）、`candidate_digest`（条件；放宽时必填）、`target: Id` 与 `expected_revision: RevisionRef`（条件；收紧时必填；解除处置时为处置身份与处置修订）、`target_state: Key` 与 `target_state_version: RevisionRef`（条件；账号状态变更（停用、冻结、重新启用、解冻）时必填）、`confirmer: PrincipalRef`（是）、`confirmer_basis: Enum(holding, deployment_owner)`（是）、`confirmed_at: Instant`（是）、`expires_at: Instant`（是；有 `effective_from` 时为生效时间加确认有效期）、`waiting_since: Instant`（否；生效点返回处理中时记下，再次进入时按等待时长顺延 `expires_at` 并清空；顺延累计不超过处理中的等待上限）、`consumed_by_change: Id`（否；得到“已生效”的那次生效点写入）。生效点核对：确认人与申请人不是同一个自然人，确认人也不是受保护操作的对象本人（[安全 08 的确认与受保护操作](08-state-and-change-protocol.md#确认与受保护操作)）、对象与内容（或版本）一致、未过期、未被使用；`confirmer_basis = holding` 时还核对确认人此刻的资格可证明、合格且未处于安全处置（例外：对象不影响授权管理员可用性时，安全 03 两人规则下的确认人按最后已应用的事实判断，安全 08 决策表第 22 行），`deployment_owner` 时只核对凭据与使用记录。解除处置的确认绑定处置身份与处置修订，`consumed_by_change` 在整个解除完成时写入。

**解除处置的请求 `be.security.disposition_release`**：`change_key`（是）、`signal_refs: Set<Text>`（身份侧处置时必填：要移除的证据记录身份；重放的解除按它匹配，不核对处置修订）、`disposition: Id` 与 `disposition_revision: RevisionRef`（是）、`requested_by: PrincipalRef`（是；管理员恢复时为部署所有者）、`trigger: Enum(user, recovery)`（是）、`confirmations: List<Id>`（否）。结果用下面的变更结果表达，`outcome` 为整个解除的结果；另带 `items: List<{record: Id, outcome: Enum(applied, held_kept, processing, awaiting_confirmation, rejected), reason: Key（否）}>`，列出使解除未完成的那一条。

**变更结果 `be.security.change_result`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `change_key` | `Text` | 是 | — |
| `outcome` | `Enum` | 是 | `applied`、`rejected`、`processing`、`awaiting_confirmation`、`scheduled`、`held_kept` |
| `reason` | `Key` | 条件 | `rejected` 时必填，取自下文的错误表 |
| `record` | `Id` | 条件 | `applied`、`scheduled`，以及保存了记录的 `awaiting_confirmation`（放宽）时必填 |
| `new_revision` | `RevisionRef` | 条件 | `applied` 时必填 |
| `security_revisions` | `List<RevisionRef>` | 条件 | `applied` 时必填：被推进的安全修订 |

**变更计划 `change_plan` 的专有字段**：`items: List<PlanItem>`；`previewed_at: Instant`；`expires_at: Instant`；`plan_state: Enum(draft, previewed, confirmed, executing, completed, partially_completed, cancelled, expired)`。`PlanItem = {item_key: Text, request: change_request, item_state: Enum(pending, applied, rejected, needs_review), result: change_result（否）}`。各状态的含义与转换见[安全 08 的批量计划](08-state-and-change-protocol.md#批量计划)。

**包含见证 `be.security.containment_witness`**：`candidate_segment: Digest`；`ceiling_records: List<{record: Id, revision: RevisionRef}>`；`rules: Map<Key, Enum>`（每个维度所用的规则：`all`、`subset`、`subtree_cover`、`interval_inside`、`self_instantiated` 等）；`split: {dimension: Key, assignments: List<{value: Text, ceiling: Id}>}`（否）；`instantiation_facts: List<RevisionRef>`；`algorithm_version: Text`；`comparisons: Int`。见证用于审计与解释，生效点现场重算（安全 07）。

**依赖边 `be.security.dependency_edge`**：`dependent: Id`、`source_kind: Enum`（同 `sources[].kind`）、`source: Id`、`role: Enum`。由生效点在写入记录的同一事务中维护。

**闭包任务 `be.security.closure_task`**：`trigger_change: Id`、`source: Id`、`index_complete: Bool`（依赖索引是否完整；否则整个域待复核）、`cursor: Text`（进度）、`processed: Int`、`state: Enum(running, completed, failed)`。

## 视图与核验

**授权视图 `be.security.view`** 按分片发行，每个分片有自己的修订：

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `shard` | `Key` | 是 | 分片键，例如按资源类型或法人划分；分片方式由授权成员声明 |
| `recovery_generation` | `RevisionRef` | 是 | 恢复代次 |
| `security_revisions` | `List<RevisionRef>` | 是 | 本分片覆盖的各依赖域水位（带授权库纪元，[协议 14](../14-data-foundations.md#库内计数与纪元)） |
| `applicability` | `Set<Key>` | 是 | 本分片完整覆盖的资源类型；未列出的类型不能用本分片判定 |
| `subjects` | `Map<Id,SubjectEntry>` | 是 | 每个主体的有效段（安全 08 已与来源求交）；`SubjectEntry = {segments: Set<Segment>, accounts_disabled: Bool}` |
| `capabilities` | `Set<Key>` | 是 | 生成本分片的成员所具备的能力 |

**核验请求 `be.security.view_verify_request`**：`component: PrincipalRef`（是）、`held: List<{shard: Key, digest: Digest}>`（是）、`nonce: Text`（是，至少 128 位随机数的十六进制）。

**核验回答 `be.security.view_verify_answer`**

| 字段 | 类型 | 必填 | 约束 |
| --- | --- | --- | --- |
| `nonce` | `Text` | 是 | 必须等于请求中的 `nonce`；不等则丢弃，不续期 |
| `computed_at` | `Instant` | 是 | 只供审计；组件不用它计算有效期 |
| `instance` | `Text` | 是 | 作答的授权成员实例；与组件记下的不同（没有登记的成员切换）时整个回答判为回退。放在回答上而不只在视图的修订里：只答“未变”的回答不带视图，从备份另建的环境内容相同、摘要也相同 |
| `shards` | `List<{shard: Key, status: Enum(unchanged, changed, closed), view: be.security.view（条件）}>` | 是 | `changed` 时附新视图；`closed` 表示该分片暂时不能续发（安全 03） |
| `recovery_generation` | `RevisionRef` | 是 | 比组件持有的大时，组件丢弃全部旧视图并采用新视图；比持有的小时判为回退（[安全 03](03-authorization-acceptance-and-revocation.md#授权视图与核验)） |

组件按安全 03 计算有效期：从**发出这次请求**时的单调时钟读数起算。`nonce` 让组件能确认回答是针对本次请求计算的；缓存或重放的旧回答 `nonce` 不符，被丢弃（安全 03 模型中的“重放”坏变体）。回答通过已认证的服务通道传输（安全 02）。

**代次与修订的编码**：四类值都用 `RevisionRef`，以 `domain` 区分。

| 类别 | `domain` 的形式 | 比较 |
| --- | --- | --- |
| 恢复代次 | `authz.recovery` | 按整数比较；权威计数在独立证据存储，单调；更大即旧视图与旧许可全部作废，更小判为回退 |
| 安全修订 | `authz.security.<依赖域>` | 同域内按协议 14 比较：`epoch` 相同按十进制整数，不同用分叉点判断是否被包含 |
| 属主提交守卫代次 | `<组件>.guard.<范围>` | 同域内按十进制整数比较；只在严格路径 B 档使用 |
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

**单对象决定 `Decision`**（组件内部的结构，不跨网络传给用户）：`outcome: Enum(allowed, denied, unprovable)`；`matched_segments: Set<Digest>`；`readable_fields: Set<Key>`；`cutoff_remaining_ms: DurationMs`；`explain: Id`（否）。

**内部分类与对外表达**：下表的 reason 在新的错误目录中登记（一个错误对象，原因取自目录）。“占用变更键”只对安全记录的变更，规则在[安全 08 的变更键](08-state-and-change-protocol.md#生效点)；本列只标出每个 reason 属于哪一类。

| 内部分类 | reason | HTTP | 可重试 | 占用变更键 | 说明 |
| --- | --- | --- | --- | --- | --- |
| 不可见 | `NOT_FOUND` | 404 | 否 | — | 读取与命令一致；不泄露对象是否存在 |
| 可见但没有此操作的资格 | `PERMISSION_DENIED` | 403 | 否 | 是 | — |
| 请求参数中的维度取值越界 | 查询筛选：不报错；命令的目标：`PERMISSION_DENIED` | 200 或 403 | 否 | 命令：是；查询：— | 列表与查询按某个维度取值筛选（`warehouse_id=7`）而该取值不在调用者的授权内：筛选与授权求交，得到不含它的结果，不报错。命令以越界的取值为目标（在仓库 7 建单）：答 `PERMISSION_DENIED`；不存在的取值与无权的取值答同一个结果，不泄露取值是否存在 |
| 业务控制拒绝 | 各业务的 reason | 409 或 422 | 视业务 | — | 与授权拒绝分开 |
| 无法证明 | `AUTHORIZATION_UNPROVABLE` | 503 | 是 | 否 | 来源不可得、超期、修订不相容；不能写成“没有数据” |
| 视图过期 | `AUTHORIZATION_VIEW_EXPIRED` | 503 | 是 | — | 默认路径超过 `W` |
| 令牌陈旧 | `TOKEN_STALE` | 401 | 边缘换取新令牌后重试一次 | — | 只用于身份侧的事实（会话代次已推进、账号的安全状态版本已变），只由入口组件在准入阶段、任何副作用之前返回（[协议 20](../20-frontend.md#登录与会话)） |
| 查询不可完成 | `QUERY_NOT_COMPLETABLE` | 422 | 否 | — | 有段不可下推、候选集超预算、冷层没有覆盖（安全 07） |
| 受限字段不可用于此查询 | `FIELD_NOT_QUERYABLE` | 422 | 否 | — | 安全 07 的排序与筛选证明不成立 |
| 查询计划已变化 | `QUERY_PLAN_CHANGED` | 409 | 否（重新查询） | — | 游标的计划摘要不一致 |
| 变更冲突 | `CHANGE_KEY_CONFLICT` | 409 | 否 | 否（不覆盖原绑定） | 同一变更键、不同的内容 |
| 修订已变 | `CHANGE_REVISION_STALE` | 409 | 否（重新预览） | 是 | 生效点发现目标或来源的修订已变 |
| 包含证明不成立 | `CONTAINMENT_NOT_PROVEN` | 403 | 否 | 是 | 附失败的维度与原因（超出、无法证明、超预算） |
| 需要确认 | `CONFIRMATION_REQUIRED` | 202 | — | 放宽：是（保存记录）；收紧：否 | 变更进入待确认 |
| 最后管理员保护 | `LAST_ADMIN_PROTECTED` | 409 | 否 | 是 | — |
| 管理员可用性无法证明 | `ADMIN_AVAILABILITY_UNPROVABLE` | 202 | 是 | 否 | 处理中：不建记录，已保存的记录不变，用户提交的由调用者稍后重试，作业触发的放回 `retry_wait`。出现在安全 08 决策表的第 9、12、22、28 行：放宽或解除处置的请求者资格无法证明；收紧的请求者资格无法证明而对象影响管理员可用性又没有确认；某名确认人此刻的资格无法证明；变更后可用管理员无法证明。对象持有授权管理资格的只减少访问的操作见安全 03 |
| 安全处置限制 | `HELD_BY_SECURITY_DISPOSITION` | 403 | 否 | — | 只出现在解释中：求值时与同一自然人被安全处置暂停的范围相交的段不生效；对外按无权表达（安全 08） |
| 部署待恢复 | `RECOVERY_IN_PROGRESS` | 503 | 是 | 否 | 管理结构的放宽（管理员恢复除外；安全 08 的待恢复）；收紧照常；已有的记录不变，可以稍后重新提交 |
| 成员切换中 | `MEMBER_SWITCH_IN_PROGRESS` | 503 | 是 | 否 | 授权成员切换窗口内的全部放宽（`widen` 与 `restore_*`，已有的记录不变），身份成员切换窗口内的放宽类账号变更（[安全 10](10-providers-and-member-switching.md)、[安全 11](11-identity-member-switching.md)）；身份切换中新成员接管之后，旧地址上的收紧代理失败（安全 11） |
| 定义未到 | `DEFINITION_PENDING` | 503 | 是 | 否 | 变更引用的资源类型在注册表里有属主、还没有已被接受的定义：组件刚启动，定义还在提交中（安全 08 的生效点）；同一个键稍后重新提交。注册表里没有的资源类型答 `REQUEST_INVALID` |
| 定义的属主不符 | `DEFINITION_OWNER_MISMATCH` | — | 否 | — | 只在系统面：提交的定义的 `authority`、资源类型或权限键在注册表中的属主不是提交者（EN21、EN23）；同时记录安全事件 |
| 定义不合格 | `DEFINITION_INVALID` | — | 否 | — | 只在系统面：不符合 schema、字节不是规范形式、摘要不符，或违反约束一列的条件规则（例如 `restricted` 字段缺 `read_key`、写字段不在读字段中） |
| 定义的版本冲突 | `DEFINITION_VERSION_CONFLICT` | — | 否 | — | 只在系统面：同一组件、同一版本已被接受的定义集合与这次的不同 |
| 能力不支持 | `CAPABILITY_UNSUPPORTED` | 501 | 否 | — | 装配时应已阻止；运行时发现则保护受影响的路径 |
| 结果未知 | `RESULT_UNKNOWN` | 504 | 查询后再定 | — | 用变更键或动作键查询，不换键重试 |

对无权的调用者，错误内容不包含金额、负责人、角色内容或证明细节（安全 06）。

## 参考检查

[规范编码检查](../../../../tools/be-acceptance/models/11-canonical-encoding.py)（种子 20261013）按本页的规则实现规范化与摘要：

- 语义相同的段（字段顺序、集合顺序、`100.00` 与 `1E2`、`+08:00` 与 `Z`）摘要相同；
- 60,000 个随机值（含分隔符、引号、反斜杠、控制字符、非 BMP 字符、各种显式存在状态）没有两个不同的值得到相同的规范字节；
- 不同记录类型或主版本的同一 JSON 摘要不同；
- 旧冷数据格式的两组反例（未转义的分隔符、固定字符串表示 null）在旧规则下碰撞，新规则区分；
- “路径 + 查询 + 请求体直接拼接”的指纹碰撞，规范数组不碰撞。

5 个坏变体全部被发现：集合不排序、十进制不规范、时刻保留偏移、缺类型前缀、键不排序。检查只覆盖编码规则本身，不是三门 SDK 的实现。

## 独立预期

EN 预期全部在本页；其中 EN16、EN17 检验的是[安全 09b](09b-capabilities-and-profiles.md) 的准入规则。

| 编号 | 场景 | 固定预期 |
| --- | --- | --- |
| EN01 | 同一段由三门语言各自规范化并计算摘要 | 字节与摘要完全一致（共同向量） |
| EN02 | 金额 `100.00`、`100`、`1E2` | 规范形式都是 `100`，摘要一致 |
| EN03 | 同一时刻以不同的时区偏移提交 | 规范为同一个 UTC 文本 |
| EN04 | 记录中出现 JSON `null` 或浮点数 | 拒绝 |
| EN05 | 记录的 `required_features` 含读者不认识的项 | 拒绝整条记录，不忽略后放行 |
| EN06 | 次版本新增 `ext` 内的字段 | 旧读者可以忽略，摘要按新内容计算 |
| EN07 | 新的原子种类出现在旧读者 | 因主版本或 `required_features` 被拒绝 |
| EN08 | 段的 `atoms` 少一个资源定义的维度，或多一个未定义的维度 | 拒绝 |
| EN09 | `write_fields` 含不在 `read_fields` 中的字段 | 拒绝 |
| EN10 | `interval` 只给 `hi` 不给 `hi_closed`，或两端都缺 | 拒绝 |
| EN11 | `subject_org` 出现在没有绑定任职的授予中 | 拒绝 |
| EN12 | 两个修订域的值按整数比较 | 不允许；只在同域内比较 |
| EN13 | 核验回答的 `nonce` 与请求不符 | 丢弃，不续期 |
| EN14 | 核验回答的恢复代次比组件持有的大；或比持有的小 | 更大：丢弃全部旧视图，采用新视图；更小：判为回退，停用视图并告警 |
| EN15 | 视图分片的 `applicability` 不含某资源类型 | 不用该分片判定该类型 |
| EN16 | 操作 profile 把 `high` 改成 `low`，或路径弱于 `minimum_path` | 装配拒绝 |
| EN17 | 能力声明中某能力的证据为 `declared`，生产部署启用依赖它的功能 | 装配拒绝 |
| EN18 | 变更请求同时含收紧与放宽 | 拒绝，要求拆成两个请求 |
| EN19 | 确认的 `candidate_digest` 与生效时的候选内容不同 | 确认无效 |
| EN20 | 错误回答中出现无权查看的金额或负责人 | 不允许；只给 reason 与可显示的信息 |
| EN21 | 组件甲提交一份资源定义，`owner_component` 写成组件乙，或资源类型在注册表中属于组件乙 | 拒绝并记录安全事件 |
| EN22 | 附件类别引用的字段不在资源定义的 `fields` 中 | 拒绝 |
| EN23 | 组件甲为组件乙登记的资源类型提交操作定义，或使用组件乙的权限键 | 拒绝并记录安全事件 |
| EN24 | 一个 `purpose` 不是 `manage`、或 `side_effects` 含 `security_change` 以外的种类的操作声明 `tightening_only` | 提交时拒绝 |
| EN25 | 销售组件提交一个引用财务资源类型的角色模板 | 拒绝：模板片段只能引用提交者自己的资源类型与权限键；跨组件的标准角色由授权组件按片段合成 |

## 依据与独立判断

[RFC 8785](https://www.rfc-editor.org/rfc/rfc8785) 定义了 JSON 的规范化序列化；本项目进一步禁止浮点数与 JSON null、要求记录类型与版本的前缀，使规范形式在三门语言中容易一致地实现。显式的存在状态、未知取值即拒绝、`required_features` 的思路，与 JWT 的 `crit` 头（[RFC 7515 §4.1.11](https://www.rfc-editor.org/rfc/rfc7515#section-4.1.11)）相同：安全相关的扩展必须被理解才能使用。核验回答绑定请求随机数，是防重放的通行做法。

知识库没有“结构化数据的规范化编码与内容摘要”这一主题；它《幂等键》中的请求指纹写作“拼接后算 SHA-256”，没有要求无歧义的分帧，本页的检查复现了拼接碰撞。

## 已知风险与待定

- 安全记录的 JSON Schema 已由本页生成（实验第 5 步）；只覆盖写成字段表的记录，行内写法的记录（核验请求、确认、变更计划的项等）要用到时先改写成字段表。调用信封的 protobuf 在各成员的契约包里（D76）。三门语言的共同向量（EN、FX、CP、AT、PA 合并映射）还没有全部写出，第 5 步只写了视图核验与记录校验用到的。
- 视图的分片方式、分片大小与核验频率对授权组件负载的影响，在代表部署实验中测量。
- 错误 reason 的最终名称、HTTP 映射与可显示的文案，在新的错误目录中统一登记。
