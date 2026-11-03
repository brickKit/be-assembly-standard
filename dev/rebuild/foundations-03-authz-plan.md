# 底层先行第 3 项：权限

> 2026-11-03 起草，按 `f-plan`。阶段与推进方式见根 `AGENTS.md`“推进方式”一行；这一项做到下面的门槛后汇报，维护者确认后进第 4 项（审计与整套恢复）。维护者 2026-11-03 说过：不需要他时一直做下去，能自己定的决策自己定（记忆“实验与重建连续推进”）。

## 门槛与范围

| 门槛（实验计划“实验之后：底层先行”） | 这一项里指什么 |
| --- | --- |
| 安全 01–09a 中首批范围的独立预期全过 | 下面“首批”的能力与安全 08 对应的预期条目（T1 逐条定），每条有通过的测试 |
| 越权与范围外不可见的测试覆盖每种维度 | 首批的四种维度：值集合、组织树、主体、金额区间；每种都有“别人的看不见、越界的取值被拒、列表与单对象一致”的测试（SDK 与黑盒剖面） |

**首批**（2026-11-03，AI 定，待复核）：按安全 09b 的能力目录与门槛表“内容”一栏划，再加上第 2 项留给这一项的：

- 能力：`authz.core`（完整段求值、三值、字段按命中段）、`authz.list.complete`（查询编译与命中位图）、`authz.path.bounded_local`（视图核验、随机数、分片）、`authz.recovery.owner`（部署所有者确认与恢复）、`authz.containment.single` 与 `authz.management.delegated`（受限的分级管理，D35；种子数据里已有“中国区授权管理员”）。
- 安全 08 的状态与变更协议：生效点、有效段的计算、受保护操作与确认、系统角色与最后管理员、安全处置、待恢复（D62）。
- 内部来源：身份成员（账号状态与安全状态版本：`accounts_disabled`、`security_version` 进视图，来源水位按 D64 覆盖）；组织（已重建的 `mdm/org`）。
- 第 2 项留下的：授权组件消费账号状态；Casdoor 侧变更（自助页面改密码、控制台停用）的定期全量比较与证据；强制登出与重置第二因素（授权管理的操作，经 iam-casdoor 办理）。

**不在首批**：关系与记录两种维度（随共享、团队与逐条共享，安全 05）；共享、委托、休假代理与只读扮演（安全 05）；严格路径 A、B 档；紧急访问；授权成员切换（安全 10）与增量导出；包含证明的单维拆分；任职关联的授予（安全 04 的任职部分，随 `mdm/employee` 的重建）；高可用的边缘情形（D66）。

**先决**（第 2 项发现的硬依赖）：授权成员往视图里写 `security_version` 之前，`be-sdk-python` 的协议副本到 alpha.53 以上，否则 Python 组件按旧 schema 拒收整份视图。

## 现状（2026-11-03 盘点）

- `infra/authz` 3.0.15（`be-sdk-go` alpha.41），约 1 800 行 Go：授予、视图（分片、核验）、定义的提交、生效。设计文档写明没做的：确认与受保护操作、严格路径、成员切换、共享委托扮演、任职关联的授予、包含证明的拆分、`relation` 与 `record` 维度；安装认领简化为“配置里的主体成为第一个授权管理员”；收紧意图的证据没有接上 `infra/audit`。
- SDK：视图的持有与核验、求值、列表编译、字段掩码（第 08 章 P8.7–P8.18）已有，向量 `segment-eval`、`view-accept`；维度支持值集合、组织树、主体、金额四种。
- 套件：没有授权剖面（CK-AZ-01..05 只由 SDK 自己的测试点名）。

## 任务

| # | 任务 | 依赖 | 状态 |
| --- | --- | --- | --- |
| T0 | `be-sdk-python` 的协议副本到最新（alpha.55）：核验器要求 `be_sv`、准入的 `TOKEN_STALE`、下游的 401、视图的 `security_version`、新的错误原因；新章节（P7.23、第 9 章的水位）在 `features.json` 里如实标未实现 | — | ✅ 2026-11-03（a46；探针 3.2.34、套件 1.0.39） |
| T1 | 覆盖地图：安全 01、03、04、06、07、08、09a 的每条预期，归首批或不归（写理由）；首批的每条落到哪个测试，已有的点名、缺的列出 | — | ⬜ |
| T2 | 设计里要先定的（T1 列出后逐个定，写进线协议与 A 台账）：身份作为水位来源、授权组件怎样消费账号状态；受保护操作的确认接口；安装认领 | T1 | 🔶 D1–D4 已定已做；确认接口与安装认领随 T5、T6 |
| T3 | 内部来源：iam-casdoor 的账号状态流做水位来源（补取者 `infra/authz`）；授权组件以带水位的投影消费它，`accounts_disabled` 与 `security_version` 进视图；来源水位超期时按风险关闭分片（D64）；身份侧的处置（被盗标记） | T2 | ✅ 2026-11-03（被盗标记的处置移到 T6） |
| T4 | 记录的生命周期与生效点：状态（待生效、待确认、暂停、结束及原因）、变更键的各种重试、到点生效的工作项、闭包作业与依赖索引、收紧与放宽拆开 | T2 | 🔶 T4a–T4c 已做（未发布，见“T4 进度”）；下一步 T4d |
| T5 | 受保护操作与确认：独立确认人、部署所有者确认、`T_tight` 与只减少访问的操作、确认的使用与作废 | T4 | ⬜ |
| T6 | 安全处置、最后管理员与待恢复（D62）、管理员恢复（`authz.recovery.owner`）、安装认领 | T5 | ⬜ |
| T7 | 受限的分级管理：管理上限的包含证明、父职责收紧后的交集与待复核、批量计划、管理员交接 | T4 | ⬜ |
| T8 | 求值与查询（安全 01、06、07、09a 的首批条目）：对照 SDK 已有的向量与测试补缺；每种维度（值集合、组织树、主体、金额）的越权与范围外不可见：SDK 测试与套件的授权剖面（CK-AZ-01..05 黑盒） | T1 | ⬜ |
| T9 | iam-casdoor 的第 2 项尾巴：Casdoor 侧变更的定期全量比较（`P_pull`，按 `LastChangePasswordTime` 与账号状态）与停用的证据；强制登出与重置第二因素（授权管理的操作） | T3 | ⬜ |
| T10 | 收尾与门槛核对 | 全部 | ⬜ |

### T0 结果

- `be-sdk-python` a46：协议副本 alpha.55；核验器要求 `be_sv`；视图解析 `security_version`；准入的 `TOKEN_STALE`（向量 `token-stale`）；`forward_user` 的下游 401 换成 `AUTHORIZATION_UNPROVABLE`；`SESSION_ENDED`、`CSRF_HEADER_REQUIRED`；`features.json` 的 `token-staleness` 为 verified。单元 164、集成 90 全过（`foundations-03-data/t0/test-integration.txt`）；四处改坏都红在对的测试上（`t0/mutations.txt`）。
- 探针 `test/probe-py` 与 py2 3.2.34（从 a38 直接到 a46，清单检查照常）；套件 1.0.39：身份剖面对两种探针 CK-ID-01..06 全部通过。第一次跑出一处判定的错：CK-ID-06 把下游写死成 `test/probe-go2`，Python 那一例的下游是 py2（改为观察里记下期望的下游）。第 2 项门槛表里 TI06、UI28 的“Python 随第 6 项”由此补上。
- 第 3 项的先决条件（Python 能收带 `security_version` 的视图）已满足。

### T1 覆盖地图

- **第一步：分进不进**（2026-11-03，按上面的“首批”）。“不进”的写了去处；“进”的下一步逐条点名测试。

| 文件 | 进首批 | 不进（去处） |
| --- | --- | --- |
| 01 求值 | AE01–AE10、AE13–AE17（15） | AE11 任职（员工组件）；AE12 本人自审（审批，协议 09） |
| 03 接受与撤销 | AT12–AT14、AT16、AT21–AT49、AT51–AT53、AT57、AT58、AT61、AT64（约 40）；内部来源各条的“员工组件”以身份成员与 `mdm/org` 为实例 | AT01–AT11、AT18 严格路径；AT15 外部身份源；AT17 导出（随导出）；AT19、AT59、AT62、AT63 恢复与证据存储（第 4 项）；AT20、AT56、AT60 成员切换；AT50、AT54 高可用（D66） |
| 04 管理与任职 | AM01–AM10、AM14–AM18（15） | AM11–AM13 任职（员工组件）；AM19 审批任务（审批组件）；AM20 换提供方 |
| 06 共同契约 | SC01–SC05、SC07、SC09、SC10、SC12、SC13、SC15、SC17、SC19–SC21、SC24（16） | SC06 委托链；SC08、SC14、SC16、SC18 严格路径；SC11 图提供方；SC22 审计的落点（第 4 项）；SC23 切换与回退 |
| 07 有限表达 | FX01–FX04、FX06–FX09、FX11–FX16、FX18–FX20、FX23（17） | FX05、FX22 委托；FX10、FX21、FX24 关系与图；FX17 单维拆分 |
| 08 状态与变更 | 其余约 80 条：生效点、变更键、待生效与确认、收紧与放宽、闭包作业、批量、安全处置、受保护操作、最后管理员、待恢复、管理员恢复、认领 | CP08、CP18–CP20、CP27、CP33、CP45、CP46 任职、员工关联与委托；CP23、CP24 扮演与紧急访问；CP59、CP70、CP72、CP77、CP83、CP94 成员切换；CP60、CP73、CP78 恢复与证据存储（第 4 项） |
| 09a 编码与记录 | EN01–EN15、EN18–EN25（23） | EN16、EN17 装配的准入检查（随 `be-ops` 的重建） |

合计首批约 206 条，大半在安全 08。

### T2 要先定的

- **D1 只为普通读取续期**（A120，AI 定，待复核）：安全 03 的“续发与关闭”要求来源水位在 `D_src_high` 与 `D_src_read` 之间时高风险关闭、普通读取续发，但核验回答的分片只有 `unchanged`、`changed`、`closed`，`closed` 连读取一起关。回答的分片项加可选的 `read_only: Bool`：为真时这次回答只延长普通读取的有效期，高风险的有效期不动（`changed` 与 `unchanged` 都可以带它）。线协议 P8.11 加一句、09a 的 `view_verify_answer` 加字段、向量 `view-accept` 加例子，两种 SDK 实现；不另加状态，因为“视图变了、只续读取”也要能表达。
  - **做了**（2026-11-03）：`be-protocol` alpha.56（P8.11 一句、向量 `view-accept` 多 8 例，结果 `renewed_read`、`replaced_read`、`adopted_read`）；契约 `contract-infra-authz` alpha.2（`ShardAnswer.read_only = 5`，`buf breaking` 对 alpha.1 通过；它的 `make breaking` 在子模块里取不到 `.git`，改成先 `git archive` 基准）；`be-sdk-go` alpha.57、`be-sdk-python` a47：持有者另记最后一次完整续期的时刻，高风险的有效期从它起算。反向检查在 `foundations-03-data/t2/`：Go 第一轮两处存活（开机 5 秒内的时钟下零值的高风险时刻仍像有效；gRPC 的字段转换没有测试），补了测试后都红在对的测试上；Python 一处红在 `TypeError` 上，换成与 Go 对等的零值变异后红在规则上。COMPAT 写明要按顺序升级：组件先升 SDK，授权成员才答 `read_only`（旧 SDK 不认识这个字段，会把高风险也续上）。
- **D2 身份作为内部来源**：照第一项的水位来源（P9.13 起）：iam-casdoor 的账号状态流声明 `Watermark`（补取者 `infra/authz`），授权组件用带水位的投影（`projection.Watermarked`）消费；不是新机制，不另记 A。
- **D3 快照与批量读取是标准系统方法**（A121，AI 定，待复核）：身份成员要给授权组件提供协议 02 的 S3（按 ID 批量读取）与对齐用的快照；原来每个来源在自己的契约里各写一遍，身份族契约甚至没有系统面。照 A115 的理由做成 SDK 自带的 `be.source.v1.RecordService`（`Read`、`Snapshot`）：来源按流声明读取的组件与两个读取函数，水位来源的流必须声明；消费者逐页核对来源的声明（P9.18 早就要求、SDK 的对齐没做：测试替身直接读来源的库）。
  - **做了**（2026-11-03）：`be-protocol` alpha.57（P9.30–P9.33、`records.proto`、能力 `projection-records`、CK-PJ-04/05）、alpha.58（记录的 `claim` 标记，大内容走对象存储引用）；`be-sdk-go` alpha.58：`events.Records` 与 `RecordSource`（读快照与高点同一个 `REPEATABLE READ` 事务），`projection.Source` 改为每次回答带来源声明（去掉 `Identity`；`Align` 以第一页的声明为来源身份），`RecordClient`、`PullClient`（此前 SDK 没有真正的补取客户端，测试各写一个）。水位消费者的集成测试改为经真实的 `RecordService` 对齐。反向检查在 `foundations-03-data/t2b/mutations.txt`：第一轮两处存活（学身份时“只用主库”被后面的核对兜住、但先把副本的身份写进了来源表，测试没看这张表；水位消费者传给对齐的已采用身份换成空的也活着：测试的来源从不换部署），一处变异写错没编译；补了断言与“快照来自别的部署”的测试后都红在对的测试上。
- **D4 授权组件怎样找到身份成员**（AI 定，从现有写法推出）：授权组件加配置键 `IAM_GRPC_URL`（`$endpoint:<身份成员>:grpc`）与 `IAM_COMPONENT`（身份成员的组件 ID：mTLS 核对对端、水位来源的名字）；两者写进 `config/vars.yaml` 的共享值，换身份成员时一起改。不另记 A：与 `AUTHZ_GRPC_URL` 同一种写法。
- **参数**：`D_src_high` 60 s、`D_src_read` 10 min（D64）、`T_tight` 1 h（安全 03 的起始参数），配置键随授权组件。

### T3 结果

- `infra/iam-casdoor` 3.0.17：账号状态流 `infra.iam.account_status` 是水位来源（补取者、读取者只有 `infra/authz`），批量读取与快照照原样回答账号最后一次发出的状态记录（迁移 0003 保存它）；账号绑定时也发出状态，启动时给还没发过的账号补发。端到端测试（真实 Casdoor）以 `infra/authz` 的身份读：每个账号都在、内容与事件的载荷同一份字节、不认识的主体答“已清理”、边缘被拒；改坏六处，第一轮一处存活（绑定时发状态被后来的登录兜住）、一处红在启动失败上（变异的 SQL 用不到 `$1`），改了测试与变异后都红在规则上（`foundations-03-data/t3/iam-mutations.txt`）。测试里原来“改密码后账号状态一行”改成两行（绑定一行、改密码一行）：行为按新规则变了，不是为了通过。
- `be-sdk-go` alpha.59：`Watermarked.JudgeMany`，一条语句判一批记录，另回答来源整体的年龄，供调用方按另一个新鲜度比较；水位测试里每处 `Judge` 都同时问 `JudgeMany` 并要求一致。改坏六处，第一轮两处存活（不是已采用纪元的行、一个分区没有回声：测试里造不出这两种状态），一处没编译；测试里直接造出这两种状态后都红（`t3/judgemany-mutations.txt`）。
- `infra/authz` 3.0.16：投影 `accounts`；视图的主体带 `accounts_disabled`、`security_version`；水位年龄不超过 `AUTHZ_SOURCE_HIGH` 完整续发，不超过 `AUTHZ_SOURCE_READ` 只为普通读取续发（`read_only`），否则关闭；账号无法证明的主体不进视图。`component.yaml` 的 `configSchema` 换成 SDK 生成的块（原来漏了 `BUS_URL` 与对象存储的键），加了核对它的测试。端到端测试里加了替身身份成员 `test/iam`（只声明账号状态流，SDK 挂上补取与读取；不导入身份成员的代码），消息系统用每次重建的 `pgqueue` schema（共用 NATS 上旧运行的事件带别的部署身份，按 P9.11 会把来源判为 `blocked`）：安全状态版本与停用进视图；Bob 的版本升到 2 后旧令牌在授权组件自己的用户面答 `TOKEN_STALE`、新版本的令牌通过；替身停掉后先只为普通读取续发、再关闭，重启后完整续发。改坏七处全部变红（`t3/authz-mutations.txt`）。
- 没有覆盖的：账号无法证明（事件被隔离）时这个主体不进视图——授权组件的测试造不出隔离，SDK 一侧 `JudgeMany` 的隔离判断有测试；T4 的生命周期测试里补。

### T4 的拆分（2026-11-03，AI 定）

现有的生效点（`infra/authz` 的 `effect.go`，约 400 行）只有 `active`、`ended` 两个状态、一个变更键表、四种记录；T4 按安全 08 的“通用生命周期”“生效点”“有效段的计算”“影响闭包”重做，逐段交付，每段先写红的测试：

| 子步 | 做到什么 | 依据 |
| --- | --- | --- |
| T4a | 记录的表：六个状态、暂停原因（`security_hold`、`uncomputable`、`restore_pending`）、九个结束原因、状态修订与内容修订分开、前身（被替代、重新授予）、生效时间与有效期 | 安全 08 通用生命周期；09a 的记录字段 |
| T4b | 生效点的决策表做成一个纯函数（输入：键的绑定、种类、触发、记录状态与修订、请求者资格三值、确认、包含证明、预算、最后管理员、待恢复与切换的状态），按行序第一条命中；每行一个定向测试（从表逐行写，不从实现写）；T5、T6 才有输入的行（确认、管理员恢复、处置）先由输入表达，返回表里的结果 | 安全 08 生效点的结果（30 行）与“结果对记录状态的作用” |
| T4c | 变更键：请求者键按结果种类绑定或不绑定；派生键 `<记录>:<状态修订>:<触发>`；按键查询（未绑定答“未绑定”） | 安全 08 变更键 |
| T4d | 待生效：生效时间在未来的放宽保存为 `scheduled`，登记到点的定时工作项（SDK `work`），到点以派生键进生效点；状态修订变了的旧工作项按第 3 行作废 | 状态迁移第 2、6 行；协议 01 |
| T4e | 收窄生成新内容修订；续期与扩大建新记录、生效时以 `superseded` 结束旧记录（新记录必须包含旧的）；同时收紧与放宽的请求拒绝，要求拆成两步 | 状态迁移；变更方向 |
| T4f | 有效段：授予 ∩ 治理单元当前的上限；退役权限键的段为空；部分越界保持生效并标记待复核 | 有效段的计算 |
| T4g | 闭包作业与依赖索引：到期、来源结束、来源收窄、无法计算的记账迁移（推进状态修订，不进增量与证据）；`uncomputable` 恢复以派生键进生效点；索引不完整时整个来源域待复核 | 影响闭包；状态迁移 |

**接口跟着换成 09a 的形状**（2026-11-03，从规范推出，不另记 A）：用户面 `POST /api/authz/changes` 收 `be.security.change_request`（`direction`、`target`、`candidate`、`termination`、`expected_state_revision`、`expected_revision`、`effective_from`、`acting_as`、`confirmation_ids`；`requested_by` 与 `trigger` 由生效点从调用通道得出），回答 `be.security.change_result`（`applied`、`rejected`、`processing`、`awaiting_confirmation`、`scheduled`、`held_kept`；后三种与 `processing` 是 202）；记录按 09a 的通用部分（`state`、`end_reason`、`held_reason`、`review_pending`、`predecessor`、`sources`、`valid`、`state_revision`、`last_change`）与专有字段。第 5 步临时的 `action` 名字（`unit.create`、`grant.revoke` 等）退掉，用它的有：`be-sdk-go` 的 `seed` 包、套件的 `conformance/cells/secure.py`、`infra/authz` 与 `mdm/partner` 的种子命令，随 T4 一起改。按键查询：`GET /api/authz/changes/{change_key}`，没有绑定的答 `outcome: unbound`。

T4 的验收：安全 08 首批里“生效点、变更键与到点生效”“来源变化、上限与闭包”两组预期每条有通过的测试；参考模型 `09-change-protocol.py` 的关键交错落成定向测试（T4b、T4d、T4g 各自引用）。

### T4 进度（2026-11-03 停在这里）

- **做了（`infra/authz` 3.0.17，只在本地提交，未发布）**：T4b 决策表是纯函数 `authz/decide.go`，`decide_test.go` 按表逐行写了 61 例（先红后绿；“确认人拒绝”与“管理者取消”一度被我合成一种，按第 9 行与第 10–12 行分开，补了两例并用变异确认红在规则上）。T4a 迁移 0002：六个状态、暂停与结束原因、状态修订、前身、生效时间、记录级有效期、待复核、`last_change`；读有效记录时过滤有效期（到期在求值时生效）。T4c 新的生效点 `authz/change.go`：收 09a 的 `be.security.change_request`，收集事实（请求者的资格 = 安全记录上的管理资格 ∩ 身份来源证明的账号：此刻按 `D_src_high`，“最后已应用的事实”不计年龄）、决策表、按结果写记录（新放宽终局驳回也留一条 `ended`（`rejected`）），按键表绑定（冲突不再绑定）；按键查询 `GET /api/authz/changes/{key}`（未绑定答 `unbound`）；收窄（同一记录的新内容修订，候选必须在原内容之内，否则要求拆成两步）、续期与扩大（`predecessor`，新记录必须包含旧的，生效时旧的 `superseded`）、终止（收回、取消；拒绝要等 T5 的确认）。未来生效的放宽暂答 `CAPABILITY_UNSUPPORTED`（T4d 加到点的工作项后去掉）。端到端测试换成新接口并加了这一段的断言，全绿；反向检查（`foundations-03-data/t4/change-mutations.txt`）十处，第一轮三处存活——状态修订过期的那一例同时带着过期的内容修订（被第 17 行兜住）、“终止已生效的记录”那一例的目标早已结束、没有测试造过已过有效期的记录——补准这三例后都红在对的规则上。授权组件提交 `c709342` 已推送，没有打标签。
- **发布之前要一起改**（旧接口的使用者）：`be-sdk-go` 的 `seed` 包、套件的 `conformance/cells/secure.py`、`infra/authz` 的 `cmd/seed`、`mdm/partner` 的 `cmd/seed`；`BRICKKIT.md` 与设计文档的接口一节。
- **下一步**：T4d（到点生效的工作项、第 3 行的作废）、T4e 剩下的（中性变更）、T4f、T4g；放弃自己的授予要先能调用变更路由（现在路由要求 `infra.authz.security_record.change` 的权限，受授人一般没有），T4 里定。

## 全局约束

照第一、二项：改动的循环；行为变了先改协议的条款与向量，再改 SDK；版本每次都升，按依赖顺序发布；测试先断言前提成立；写在实现之后、第一次就绿的测试做改坏代码的反向检查，红也要红在那条规则上；进记录的运行当场存输出；这一阶段不新做业务组件，用探针与已有组件验证；新建仓库先问。
