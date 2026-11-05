# T8 覆盖对照（2026-11-05）

安全 01、06、07、09a 中属于首批的预期，逐条对到已有的测试或列为缺口。“向量”指 `be-protocol` 的向量，Go 与 Python 两种 SDK 都跑；“授权组件”指 `infra/authz` 的测试（集成测试文件名省去 `_integration_test.go`）。✅ 有通过的测试；🔶 部分；❌ 没有。

## 安全 01 求值

| 预期 | 现状 | 依据或缺口 |
| --- | --- | --- |
| AE01 配对 | ✅ | 向量 `two-grants-keep-their-pairing`；授予时：`bounded` bd1–bd5 |
| AE02 甲范围可审批、乙范围只读 | ✅ | 向量 `approve-in-one-scope-only`（T8a） |
| AE03 金额上限不能借、闭区间的边界 | ✅ | 向量 `limits-are-not-borrowed`（r10 的 75 不借 LE1 的 100；r1 落在闭端、r4 落在开端）（T8a） |
| AE04 掩码为 null 且列在 `_masked` | ✅ | P8.31；向量 `mask-*`；SDK 端到端（Go `TestOthersSeeNothingAndFieldsFollowTheSegments`）；套件 CK-AZ-05（T8a、T8d） |
| AE05 有 K 无读取 | ✅ | 向量 `approve-without-read` |
| AE06 可读、审批不匹配 | ✅ | `approve-up-to-10000-cny` 的 r2、r6 |
| AE07 两段覆盖同一行，字段只并本行、本动作的 | ✅ | 向量 `overlapping-segments-union-their-fields`；套件 CK-AZ-05b（T8a、T8d） |
| AE08 导出用导出段的字段 | ✅ | P8.15 改写，两种 SDK 改正（单对象原来给读取段的字段）；向量 `export-uses-its-own-fields`、`action_fields` 与 `action_list`；套件 CK-AZ-05b（T8a、T8d） |
| AE09 空部门、空集合、null、未取得 | ✅ | 向量 r7（空路径）、`empty-in-matches-nothing`、r4/r5（null）、r8/r9（未取得） |
| AE10 `owner OR org` 两个分支都保留其他限制 | ✅ | 向量 `owner-or-dept-keeps-the-legal-entity`（T8a） |
| AE13 两个分支命中同一行、页满 | ✅ | 套件 CK-AZ-05b：重叠的两段逐页（每页一条）翻完，每条一次（T8d） |
| AE14 按不可读的受限字段排序、筛选被拒，掩码列表可用 | ✅ | `TestRestrictedFieldsAndSearch`（两种 SDK，CK-LS-02） |
| AE15 候选的新状态越界被拒 | ✅ | 探针的移动与新建（T8c）；套件 CK-AZ-05：每种维度越界的移动与新建 403、条目不变、没有新建（T8d） |
| AE16 不可下推或未知的表达：列表不可完成 | 🔶 | 编译遇到不认识的原子报错；不认识的原子种类整条视图被拒（`atom-unknown-kind`），不合定义的段不参与（P8.14）。声明为不可下推的维度答 `QUERY_NOT_COMPLETABLE` 没有点名的测试：现有组件都没有这种维度，随第一个有它的组件 |
| AE17 游标之后撤权 | ✅ | `TestCursorsBindTheirFilterAndPlan`（两种 SDK，CK-LS-01：计划摘要变了，游标失效） |

## 安全 06 共同契约

| 预期 | 现状 | 依据或缺口 |
| --- | --- | --- |
| SC01 客户端自报 verified、系统模式、负责人 | ✅ | SDK `TestOthersSeeNothingAndFieldsFollowTheSegments` 的 TI05；授权组件的请求者取自令牌 |
| SC02 空、缺省、未知枚举、null、零 | ✅ | 向量 `canonical` 的 `json-null`、`security-records` 的 `enum-unknown`、`empty-in`、未取得的事实 |
| SC03 同 ID 不同部署或类型 | ✅ | 向量 `view-accept` 的 `view-instance-mismatch`、`digest-same-json-other-type`；视图核对部署（`TestAnswersThatDoNotRenew`） |
| SC04 跨域比较修订 | ✅ | 向量 `view-accept` 的 `new-domain`、`mixed`、`recovery-*` |
| SC05 分别取最宽造出错配 | ✅ | 同 AE01 |
| SC07 旧客户端忽略新限制、未知操作符 | ✅ | 向量 `security-records` 的 `atom-unknown-kind`、`view-unknown-field`；未知原子求值为未知 |
| SC09 旧证据重签、304 | ✅ | `TestAnswersThatDoNotRenew`（两种 SDK）、向量 `view-accept` |
| SC10 掩码与业务 null 可区分；新字段未分类 | ✅ | 未分类字段启动失败；可区分同 AE04 |
| SC12 计划或游标被改、先分页再筛 | ✅ | CK-LS-01；授权在 SQL 的 WHERE 里，先于分页 |
| SC13 同键不同内容、换键重试 | ✅ | 授权组件 T4 的变更键（`TestMemberEndToEnd`、`scheduled`）；SDK 幂等向量 |
| SC15 批量复用旧见证 | ✅ | T7 `plans`（AM08） |
| SC17 未登记的路由 | ✅ | CK-AZ-01（两种 SDK） |
| SC19 热重载扩权、来源故障退回旧角色 | ✅ | 没有静态角色配置；来源停住时关闭（T3 `identity`） |
| SC20 旧模式实例、Fork 没实现新字段 | ✅ | 视图 schema 拒绝未知字段（`view-unknown-field`）；`read_only` 的升级顺序写在 COMPAT |
| SC21 直接 hash protobuf | ✅ | 向量 `canonical` 的摘要例子 |
| SC24 证据范围如实 | ✅ | 两种 SDK 的 `features.json` 与它的测试（`pending` 写明未验证的） |

## 安全 07 有限表达

| 预期 | 现状 | 依据或缺口 |
| --- | --- | --- |
| FX01 资源新增维度，旧授予缺这一维 | ✅ | 授权组件 `usable` 按当前定义检查（`TestOnlyUsableKeysTakePart`，T8b）；组件一侧两种 SDK 也拒绝（P8.14，持有者测试与经启动器的测试，T8a） |
| FX02 `本人 OR 甲部门` 展开为两段 | ✅ | 同 AE10 |
| FX03 空集合、求交为空、空区间从执行视图删除 | ✅ | `TestAtomIntersection` 加 `all` 与空集合、空树、空区间四例（T8b）；组件一侧不匹配（向量 `empty-in-matches-nothing`、`empty-interval-matches-nothing`） |
| FX04 预算 | ✅ | T7 `bounded` 的 `budgets` |
| FX06 直接授予用“本人部门” | 转出 | `subject_org` 原子随任职（员工组件）；现在任何不认识的原子都被拒（`atom-unknown-kind`） |
| FX07 `/a` 与 `/ab` | ✅ | 向量 r6（`org1/org22` 对 `org1/org2` 的子树）；包含证明 `a sibling with a shared prefix` |
| FX08 一段未知、另一段已证明 | ✅ | 向量 `one-unknown-one-proven`（r8 只取已证明段的字段）（T8a） |
| FX09 位图与字段并集 | ✅ | 同 AE07；命中位都是布尔值（P8.17，协议 alpha.67；向量 r11；T8d 的黑盒查出） |
| FX11 按成本排序 | ✅ | `TestRestrictedFieldsAndSearch` |
| FX12 显式“只看成本可读的行” | ✅ | P9.4 的 `readable_only`；两种 SDK 的列表测试；套件 CK-AZ-05b（T8a、T8d） |
| FX13 受限字段求和、只计数 | 🔶 | 筛选与排序走 `ReadableEverywhere`；SDK 没有聚合的接口，计数只要可见性：随有聚合的组件 |
| FX14 多段重叠在页边界 | ✅ | 同 AE13 |
| FX15 翻页途中撤权 | ✅ | 同 AE17 |
| FX16 管理上限的配对 | ✅ | T7 `bounded` bd1–bd5 |
| FX18 `EXACT` 上限、`SUBTREE` 授出 | ✅ | `TestContainmentRules` |
| FX19 开区间上限、闭区间授出；外币 | ✅ | `TestContainmentRules` |
| FX20 字段多一个、期限更长 | ✅ | `TestContainmentRules`；`bounded` bd6–bd8 |
| FX23 提供方只能下发压平的集合 | 转出 | 装配时的准入检查，与 EN16、EN17 一起随 `be-ops` 的重建 |

## 安全 09a 编码与记录

| 预期 | 现状 | 依据或缺口 |
| --- | --- | --- |
| EN01 各语言字节与摘要一致 | ✅ | 向量 `canonical`（Go、Python；第三种语言随它的 SDK） |
| EN02 金额规范形式 | ✅ | `canonical` 的 `decimal-*` |
| EN03 时区偏移 | ✅ | `canonical` 的 `instant-*` |
| EN04 null、浮点 | ✅ | `canonical` 的 `json-null`、`json-float`；`security-records` 的 `float` |
| EN05 `required_features` 含不认识的项 | ✅ | P8.30；向量 `security-records` 的 `read`（两例）；两种 SDK 的打开记录拒绝（T8a） |
| EN06 `ext` 里的新字段 | ✅ | 向量 `view-with-ext`（T8a） |
| EN07 新的原子种类 | ✅ | `atom-unknown-kind`；主版本不同的摘要不同（`digest-same-json-other-major`） |
| EN08 段少一维或多一维 | ✅ | 向量 `check-missing-dimension`、`check-extra-dimension`、`check-renamed-dimension`；组件一侧拒绝（P8.14）（T8a） |
| EN09 写字段不在读字段里 | ✅ | 向量 `check-write-not-readable`（T8a） |
| EN10 区间缺 `hi_closed` 或两端都缺 | ✅ | 向量 `check-interval-without-closed`、`check-interval-without-ends`（T8a） |
| EN11 `subject_org` 没有任职绑定 | 转出 | 随任职（同 FX06） |
| EN12 跨域比较修订 | ✅ | 同 SC04 |
| EN13 随机数不符 | ✅ | `TestAnswersThatDoNotRenew`（两种 SDK，CK-AZ-02） |
| EN14 恢复代次更大、更小 | ✅ | 向量 `view-accept` 的 `recovery-higher`、`recovery-lower` |
| EN15 `applicability` 不含某类型 | ✅ | 向量 `security-records` 的 `view-no-applicability`；P8.11 的持有者 |
| EN18 收紧与放宽同在一个请求 | ✅ | 授权组件 `TestMemberEndToEnd` 的 `split`（T4e） |
| EN19 确认的候选摘要不符 | ✅ | T5 `confirm` |
| EN20 错误回答里出现无权看的金额或负责人 | ✅ | 套件 CK-AZ-05：每种维度的拒绝回答里没有隐藏条目的负责人与金额（T8d） |
| EN21 提交别人的资源类型；记录安全事件 | ✅ | `authority` 写成别的组件：`TestSubmissionRules`；安全事件：`TestMemberEndToEnd` 的审计行（T8b） |
| EN22 附件类别引用不存在的字段 | ✅ | 授权组件拒绝：`TestSubmissionRules`（T8b）。SDK 声明附件类别随附件组件（协议 12） |
| EN23 用别人的权限键；记录安全事件 | ✅ | 同 EN21 |
| EN24 不合格的 `tightening_only` | ✅ | `TestSubmissionRules` 的四种不合格（T8b） |
| EN25 跨组件的角色模板 | 转出 | 组件提交角色模板片段、授权组件合成标准角色还没做：授权组件对 `role_template` 记录一律答 `DEFINITION_INVALID`。随标准角色的合成（种子数据现在直接建角色修订） |

## 四种维度 × 三项性质

“别人的看不见、越界的取值被拒、列表与单对象一致”：

| 维度 | 单对象与列表一致（SDK 向量） | 列表按越界取值筛选求交（向量） | 命令以越界取值为目标被拒 | 黑盒（套件 CK-AZ-05，两种探针） |
| --- | --- | --- | --- | --- |
| 值集合 | ✅ | ✅ `filter-outside-grant` | ✅ 套件 | ✅ |
| 组织树 | ✅ | ✅ `filter-outside-subtree` | ✅ 套件 | ✅ |
| 主体 | ✅ | ✅ `filter-another-owner` | ✅ 套件 | ✅ |
| 金额 | ✅ | ✅ `filter-amount-outside-limit`、`filter-another-currency` | ✅ 套件（AE15：150 超过 ≤100） | ✅ |

## 黑盒剖面 CK-AZ-01..05

套件的授权剖面 `conformance/profile/authz.py`，两种探针 3.2.38 都“符合”（`profile/report-authz-*.json`）：CK-AZ-01 未声明的操作启动失败；CK-AZ-02 随机数不符不续期；CK-AZ-03 授权成员停止后 `W_high`、`W_read` 过后分别被拒、恢复代次回退时暂停；CK-AZ-04 事务中视图过期回滚；CK-AZ-05 四种维度；CK-AZ-05b 重叠的段、`readable_only` 与导出。
