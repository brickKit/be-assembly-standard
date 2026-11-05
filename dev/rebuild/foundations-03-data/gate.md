# 第 3 项（权限）的门槛核对（T10，2026-11-05）

门槛（[实验计划](../experiment-plan.md)“实验之后：底层先行”；计划的“门槛与范围”）：

1. 安全 01–09a 中首批范围的独立预期全过；
2. 越权与范围外不可见的测试覆盖每种维度。

“首批”按计划的“T1 覆盖地图”划分。每条预期对到测试的依据在各任务的验收里：
- 安全 01、06、07、09a：[`t8/coverage.md`](t8/coverage.md)；
- 安全 08：计划的“T4 的验收”到“T9 的验收”；
- 安全 03、04：本文第 2、3 节（T10 补齐）。

“有”指有通过的测试；“部分”只测了一半，或靠决策表的单元测试；“推理”是结构上不会发生，写了理由；“未测”是缺口；“转出”指不在首批，写了去处。

## 1. 汇总

| 文件 | 首批 | 有 | 部分或推理 | 未测 | 首批之外（转出） |
| --- | --- | --- | --- | --- | --- |
| 01 求值 | 15 | 14 | 1（AE16） | 0 | AE11、AE12 |
| 03 接受与撤销 | 40 | 29 | 9 | 2（AT22、AT36） | 24 条，见第 2 节 |
| 04 管理与任职 | 15 | 15 | 0 | 0 | AM11–AM13、AM19、AM20 |
| 06 共同契约 | 16 | 16 | 0 | 0 | 8 条（T1） |
| 07 有限表达 | 16 | 15 | 1（FX13） | 0 | FX06、FX23 改为转出，另 7 条（T1） |
| 08 状态与变更 | 89 | 72 | 16 | 1（CP99） | 26 条，见第 4 节 |
| 09a 编码与记录 | 21 | 21 | 0 | 0 | EN11、EN25 改为转出，另 2 条（T1） |

结论：门槛一按这个口径没有完全达到——
- 3 条未测：AT22、AT36、CP99；
- 27 条部分或推理：AE16、FX13、9 条 AT、16 条 CP；
- 每条都写了理由与去处（第 2、4 节）；
- 未测与部分的条目都不在已经实现、却没有任何测试的代码路径上：都靠决策表的单元测试覆盖，或者要第二个副本、负载、别的组件才测得到。

门槛二达到（第 5 节）。

## 2. 安全 03 接受与撤销

首批是计划 T1 所列的那些条目：AT12–AT14、AT16、AT21–AT49、AT51–AT53、AT57、AT58、AT61、AT64。其中“员工组件”一律以身份成员与 `mdm/org` 为实例。

| 预期 | 状态 | 依据 |
| --- | --- | --- |
| AT12 窗口内外的旧视图、重复的回答、冷启动 | 有 | `be-sdk-go` `TestNoViewAfterStart`、`TestAnswersThatDoNotRenew`；套件 CK-AZ-02、CK-AZ-03 |
| AT13 流式输出途中到期 | 推理 | 组件没有流式的回答：列表按页，每页一次请求、一次检查（P8.12）；有流式输出的组件出现时再测 |
| AT14 新视图配旧事实、旧权限配新内容 | 部分 | 视图与记录都带修订，单对象与列表按当前事实求值（向量）；兼容水位的拒绝与追赶要“附件、负责人”这类跨组件的事实，随第一个有它们的组件 |
| AT16 已建立的 mTLS 连接遇到撤销或证书到期 | 部分 | 每个系统方法按证书核对调用者（`grpcx` 的 `TestTheCallerIsTheCertificateNotALabel`、`TestAnExpiredCertificateIsRefused`）；“已建立的连接上证书中途到期”没有专门的用例 |
| AT21 撤销一份授予，其他完整的授予照常 | 有 | `infra/authz` 端到端的撤权段（下一次核验里消失），其余段照常 |
| AT22 过载、锁等待、来源滞后、刷新风暴 | 未测 | 要负载；随第 5 步那样的实测格（性能与正确性分开测），记入第 3 项的复盘 |
| AT23 撤权在 t0，视图在 t0 之前发出请求 | 有 | `TestValidityCountsFromTheRequest`；端到端的撤权段 |
| AT24 回复晚到不延长有效期 | 有 | `TestValidityCountsFromTheRequest` |
| AT25 墙钟相差不影响上界 | 有 | SDK 只用自己的单调时钟（`clock`，CLOCK_BOOTTIME）：`TestBootClockAdvances`；有效期从请求时起算 |
| AT26 事务开始时有效、提交前过期 | 有 | 套件 CK-AZ-04（两种探针）；`db` 的提交前检查 |
| AT27 授权组件短暂与长时间不可用；来源短暂停滞 | 有 | 套件 CK-AZ-03；`infra/authz` 的身份来源段（停住后先只为普通读取续发，再关闭，恢复后完整续发） |
| AT28 缓存或重放的回复不续期 | 有 | 套件 CK-AZ-02；`TestAnswersThatDoNotRenew` |
| AT29 宿主挂起后恢复 | 有 | `TestAStallInvalidatesEveryShard`、`TestAVerificationThatTimesOutIsNotAStall`；`TestBootClockAdvances` |
| AT30 来源提交离职后消息系统中断 | 有 | 补取不经消息系统：`events` 的 `TestAPullEchoesAfterTheChangesBeforeIt`；`infra/authz` 的身份来源段；套件的消息系统中断（第 1 项） |
| AT31 来源可达、回声长期不到 | 有 | `infra/authz` 的身份来源段（来源停住按水位关闭、恢复后开放） |
| AT32 已登记的终点到达 | 有 | 段的有效期终点随视图下发，到点在本地失效：向量的有效期场景；`infra/authz` 的到期作业（`scheduled`） |
| AT33 提交检查后超过 `C_commit` | 有 | `db` 的提交截止（`db_integration_test.go`）；套件 CK-AZ-04 |
| AT34 用只读副本回答核验 | 推理 | `infra/authz` 只有主库的连接（没有读副本的配置），核验在主库上重新计算 |
| AT35 失败的事件之后的回声已被应用 | 有 | `projection` 的 `TestAHoleStopsTheContiguousPosition` |
| AT36 两个授权副本对同一视图的判断一致 | 未测 | 要第二个副本；与第 1 项移到 T10 的 CK-EV-02、CK-EV-04、CK-WK-03、CK-WK-05 一起，随多副本的格 |
| AT37 控制台停用，补取前先拉取 | 有 | `iam` 的 `comparison`；`events` 的 `TestTheStepBeforeTheEchoRunsFirst` |
| AT38 身份适配组件 1 分钟内重启 | 有 | `projection` 的 `TestJudgeManyAtTwoFreshnesses`（`D_src_high` 内照常）；`infra/authz` 的身份来源段 |
| AT39 一笔回滚、一笔长事务（PJ23） | 有 | `events` 的水位测试（PJ23） |
| AT40 消息系统中断、来源可达 | 有 | 同 AT30 |
| AT41 主库时钟回拨或切换 | 有 | `projection` 的 `TestALargerEpochIsAdoptedThroughAnAlignment`、`TestARollbackStallsUntilTheGenerationAdvances` |
| AT42、AT43 并发编号、旧租约恢复（PJ25） | 有 | `events` 的水位测试（PJ25） |
| AT44 库异步切换后位置超前（PJ26） | 有 | `projection` 的水位测试（PJ26） |
| AT45 保留期丢弃了一条（PJ27） | 有 | `projection` 的水位测试（PJ27） |
| AT46 位置早于补发保留（PJ29） | 有 | `events` 的水位测试（PJ29） |
| AT47 一条事件始终无法处理（PJ30） | 有 | `projection` 的 `TestAFailingEventQuarantinesItsSubjectsOnly`；`infra/authz` 的视图：被隔离的主体不进视图 |
| AT49 夜间停用，按 `P_pull` 拉取并记证据 | 部分 | 比较与证据：`iam` 的 `comparison`；定期作业（`IAM_PULL_INTERVAL`）注册了，测试里设 1 小时、由补取触发，没有等一个周期 |
| AT48 物理备库提升 | 部分 | 纪元变化后水位作废的规则由 AT41 的测试覆盖；真实的备库提升要高可用的格（D66） |
| AT51 离职后 10 秒异步切换 | 部分 | 新纪元对齐完成前按无法证明：`TestALargerEpochIsAdoptedThroughAnAlignment`；真实切换同 AT48 |
| AT52 高可用下员工库切换（PJ34） | 部分 | 同 AT51 |
| AT53 新纪元后旧补取迟到（PJ38） | 部分 | `TestAnotherSystemWithoutALargerGenerationStalls`、`TestTheAlignmentUsesOnlyTheAdoptedSourcesReads`；迟到的旧响应没有专门的用例 |
| AT57 `T_tight` 内单人停用 | 有 | `infra/authz` `tighten` 的 st5 |
| AT58 被解雇的管理员停用其他管理员 | 有 | `tighten` 的 st6；账号的形态：A134（管理员账号一律要确认，确认人要此刻可证明，`tighten` 的 Heidi） |
| AT61 超过 `T_tight` 撤销普通授予 | 有 | `tighten` 的 st7；账号的形态：`tighten` 的 Paula（CP80） |
| AT64 只有一名管理员、超过 `T_tight` | 有 | `tighten` 的 st8 |

首批 40 条：有 29，部分或推理 9（AT13、AT14、AT16、AT34、AT48、AT49、AT51、AT52、AT53），未测 2（AT22、AT36）。转出（T1）：AT01–AT11、AT18 严格路径；AT15 外部身份源；AT17 导出；AT19、AT59、AT62、AT63 恢复与证据存储（第 4 项）；AT20、AT56、AT60 成员切换；AT50、AT54 高可用（D66）；AT55 身份产品的库切换（回退规则本身由 AT37 一行的回退测试覆盖，真实的库切换随高可用）。

## 3. 安全 04 管理与任职

依据都在计划的“T7 的验收”（`infra/authz` 的集成测试）：AM01（`handover` ho2）、AM02（`bounded` bd1–bd5）、AM03（bd6–bd8）、AM04（bd9–bd15、bd-d1）、AM05 与 AM09（`handover` ho10–ho15）、AM06（`delegation` dl3–dl10h）、AM07（ho5–ho9）、AM08（`plans` d、g、m）、AM10（退役的权限键段为空，T4f；冒充系统角色，T4）、AM14（ho17–ho20）、AM15（T4f、T4g）、AM16（`plans`）、AM17（最后管理员与来源结束：T6 的 `pending`、`recovery`）、AM18（乱序与同版本按修订收敛：投影与水位的测试；旧备份随第 4 项）。转出：AM11–AM13 任职（员工组件）、AM19 审批任务、AM20 换提供方。

## 4. 安全 08 状态与变更

首批 89 条。依据在计划的“T4 的验收”到“T9 的验收”。下面只列不是“有”的条目，以及 T10 重新归类的条目。

**部分或推理（16）**：
- CP01：放弃本人的记录，在 T4 之后按 D82 做了，有测试；任职结束随员工组件。
- CP29、CP75：只告警，靠决策表第 28 行；集成测试里造不出“别人可证明、自己证明不了”。
- CP30、CP56：结束的记录本来不复活。
- CP40：控制台解冻被回退规则挡住，授权一侧收不到启用。
- CP48、CP58：Casdoor 4.1.0 的登录失败锁定不改 `isForbidden`，比较不会把它映射成停用；永久锁定 Casdoor 没有。
- CP50：决策表第 14 行。
- CP62：撤换时作废他未用的确认，没有单测。
- CP69：决策表第 22 行，集成测试里申请人与确认人共用一个来源。
- CP84、CP85、CP86、CP95：恢复路由只接三种动作，步骤顺序靠实现。
- CP87：第 3 行的通用作废。

**未测（1）**：CP99（撤销 `held` 的管理员持有资格要确认）。规则走受保护收紧的通用路径（第 21 行），没有点名的用例。

**T10 改为转出（另 7 条）**：
- CP25：员工组件的离职；账号停用的形态 CP26 已测。
- CP28：业务确认 profile，属于审批（协议 09）。
- CP35：自动开通。身份成员首次登录时建立新主体，从不接管已有主体（`iam` 的绑定测试）；“映射到已有主体要确认”没有这种功能。
- CP38：调岗、团队、共享、委托、关联账号都不在首批；新授予被挡已由 `disposition` 的 ds5 覆盖。
- CP100：成员切换。
- CP102、CP107、CP112：整套恢复的重放，第 4 项。

**T1 已转出（19）**：见 T1 覆盖地图。

## 5. 门槛二：每种维度的越权与范围外不可见

四种维度（值集合、组织树、主体、金额区间）× 三项（别人的看不见、越界的取值被拒、列表与单对象一致），在三处都有测试：

| 层次 | 测试 | 状态 |
| --- | --- | --- |
| 协议向量（两种 SDK 都跑） | 每种维度的越界筛选、`segment-eval`（T8a） | 有 |
| SDK 端到端 | Go `TestOthersSeeNothingAndFieldsFollowTheSegments`、Python 对应测试；编译出的列表与向量一致（`TestCompiledListsMatchTheVectors`） | 有 |
| 黑盒（两种探针） | 套件 CK-AZ-05、CK-AZ-05b（`t8/profile`）；探针有带四种维度的资源（T8c） | 有 |

## 6. 留到以后的（去处）

| 条目 | 去处 |
| --- | --- |
| AT36 与第 1 项的 CK-EV-02、CK-EV-04、CK-WK-03、CK-WK-05 | 多副本的格（第一次部署多副本时） |
| AT22 | 负载实测（性能与正确性分开） |
| AT48、AT51、AT52 的真实切换 | 高可用（D66） |
| AT14、AE16、FX13 | 第一个有跨组件事实、不可下推维度、聚合的组件 |
| CP99、CP62、CP87 | 下次改 `infra/authz` 的确认或撤换时补定向用例（规则已经由通用路径与决策表覆盖） |
| CP102、CP107、CP112、AT19、AT59、AT62、AT63、CP60、CP73、CP78 | 第 4 项（审计与整套恢复） |
