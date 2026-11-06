# 第 4 项（审计与整套恢复）的门槛核对（T12，2026-11-06）

门槛（[实验计划](../experiment-plan.md)“实验之后：底层先行”；计划的“门槛与范围”）：一次完整的恢复演练——隔离环境、真实备份、按协议 15 的第 1–10 步恢复到 T，跑协议 15“恢复目标与演练”列出的场景，记下每一步的时间与检查结果。

- **演练**：T11c 第 5 次全过（[`t11/summary.txt`](t11/summary.txt)；八个场景逐条见计划的“T11c 演练”）。格 R4-G 是单独的部署（自己的部署身份、运行档案、证据存储），备份是 pgBackRest 的全量备份加 WAL 归档，恢复到 T 是按时间点的物理恢复；外部系统是套件的假支付系统（只在这个格里）。
- **时间**（第 5 次，`summary.txt` 每步的毫秒数）：

  | 步 | 时间 |
  | --- | --- |
  | 1 宣布 | 0.02 秒 |
  | 2 冻结（换阶段重启全部成员、核对各自报告阶段） | 9.4 秒 |
  | 3 业务库恢复到 T（时间点恢复到临时实例、按 schema 拷回 12 个，审计的不动） | 76.6 秒 |
  | 4 推进两种代次 | 0.2 秒 |
  | 5 重建消息流、按进度补发 | 12.1 秒 |
  | 6 重放（6.2–6.6）与换签名密钥（6.8） | 13.3 + 0.3 秒 |
  | 7 外部对账 | 11.9 秒 |
  | 8 一致性核对 | 1.3 秒 |
  | 9 损失范围 | 0.5 秒 |
  | 10 只读开放、开放写入 | 12.4 + 12.9 秒 |
  | 合计（宣布到运行） | 150 秒 |

  这是开发机上的小数据量（种子数据）；第 3 步随数据量增长，各种布局的代价见 T11d 的实测。

“首批”按计划的“T1 覆盖地图”。“有”指有通过的测试或演练；“部分”只覆盖了一半；“推理”是结构上不会发生或只是流程要求，写了理由；“缺口”是没有实现或没有测，写了去处；“不适用”是首批部署形态里不会出现。

## 1. 汇总

| 文件 | 首批 | 有 | 部分或推理 | 缺口 | 不适用 |
| --- | --- | --- | --- | --- | --- |
| 协议 15 恢复（RC） | 69 | 39 | 14（部分 9、推理 5） | 12 | 4 |
| 协议 03 审计（AU） | 18（AU17 转第 5 项，A143） | 17 | 1 | 0 | 0 |
| 第 3 项转来 | 10 | 5 | 1 | 4 | 0 |

## 2. 协议 15

| 编号 | 结论 | 依据 |
| --- | --- | --- |
| RC01 | 有 | 演练 T8e–T11（第 1–10 步按状态表，`be-ops` 的 `Allowed`、`TestTheFirstStepsInTurn`、`TestTheStepsAfterTheReplay`、`TestTheStepsOfVerifyingAndOpening`） |
| RC02 | 有 | 第 5 步删并重建流（演练“deleted 9 streams”）；`TestAdvanceAndRedeliver` |
| RC03 | 有 | T11 场景 3：销售在 T 时落后（改名事件发布时刻提前两天），恢复后立刻核对没有、补发之后有、投影到版本 2；SDK `TestTheRedeliveryStartsAtTheSmallestProgress`、向量 `inbox-progress` |
| RC04 | 有 | SDK 的 `be_resend_gap` 与修复（T7，`TestRedeliveryAfterTheConsumersDatabaseWentBack`、`TestPurgeKeepsUnpublishedAndRecentRows`）；`redeliver` 记下空缺（演练 `gaps: map[]`） |
| RC05 | 有 | `extcmd` 的 `TestAnUnknownResultIsQueriedFirst`；恢复阶段只查询（`TestExternalCommandsOnlyQueryWhileVerifying`） |
| RC06 | 有 | T10e、T11 场景 7：`r-after` 对账为 `external_only`，第 9 步“不要再录入” 1 个 |
| RC07 | 有 | T9e–T11 场景 2：撤销的授予 `ended` |
| RC09 | 有 | 代次推进使旧认领失效（SDK `work` 的 `TestATakenOverHolderCanCommitNothing`、`TestALostClaimCannotCommitUnderAReusedCounter`，CK-WK-03）；纪元按（部署恢复代次，时间线）比较（P6.7） |
| RC10 | 部分 | 损失清单按用户与对象列出（第 9 步，演练“53 个对象、52 个丢失”）；“通知用户”没有实现：清单写进运行档案，由人通知。去处：通知组件重建时 |
| RC12 | 推理 | 投影出错走投影的修复与对齐（第 1 项的投影修复工作项、P9.26–P9.29），恢复工具只做整套；没有“只修投影”的恢复入口 |
| RC13 | 推理 | `be-ops recover` 只恢复整套（`restore-db` 拷回恢复组的全部 schema）；局部恢复不是它的能力 |
| RC15 | 推理 | 流程要求：演练记录在运行档案（`recovery.step`）与本文件；没有演练记录的部署不宣称恢复目标 |
| RC16 | 部分 | 恢复阶段用户面答 `MAINTENANCE`（503、可重试，`TestRecoveryPhases`）；接收外部回调的组件还没有重建，外部的重试没有实测。去处：第一个接收外部回调的组件 |
| RC17 | 有 | T11 场景 5 的同一机制：证据存储暂停时停用 `test.rates`，意图进告警渠道（运行档案 1 条），恢复时签名成立、按只有意图执行（同类记录：停用与撤销都是收紧，路径相同） |
| RC18 | 有 | 同 RC04；不限流上游（发件表与消费者无关的 7 天保留，P6.12） |
| RC19 | 推理 | 发件表与流的设计：生产者不知道消费者（第 1 项） |
| RC20 | 推理 | 同上：没有反压，消费者落后只告警（P6.12、RC18） |
| RC21 | 有 | T11 场景 4：意图进了证据存储、结论没有（行锁让事务等，审计暂停后放开），重放执行并标“意图未确认”；T9e 碰巧也出现过 |
| RC22 | 有（T13a） | 双通道失效时 SDK 补写一条 `evidence_double_failure` 记录（线协议 P12.23，SDK `TestAnUnreachableStoreDoesNotHoldATighteningBack`），证据存储收下（审计 `TestTheCategoriesAreTheProtocols`），第 9 步列为损失（`be-ops` 的 `TestDoubleFailuresAfterT`、`TestLossCalls`），重放不处理（`TestThePlanGroupsOrdersAndSetsApart`）；记录本身也没送到的时间段只能从日志找，协议 15 记为残余风险 |
| RC23 | 有 | “已体现”按记录身份（SDK `Reflected`、`TestTheOwnerReplaysItsEvidence`）；`be-ops` 的 `TestTheReplayGoesByCommitSequenceNotByAppendOrder` |
| RC26 | 有 | 身份成员比较 Casdoor：控制台停用记证据（`comparison` 一段）；T11 第 5 次恢复中比较按 Casdoor 的现状重新停用（`iam_status_evidence` 多 3 行） |
| RC27 | 有 | `TestTheReplayGoesByCommitSequenceNotByAppendOrder`；参考模型的坏变体 |
| RC28 | 有 | T9e–T11：退役的部门 `retired`（组织成员 `replay.go`，改坏 3 处全红） |
| RC33 | 有 | T9e 第 3 次在第 6 步中断后续做，第二遍全部 `reflected` |
| RC34 | 部分 | 按（纪元，提交序号）排序（`be-ops` 单元）、授权重放放过前置条件（3.0.29，“请求者现在已不合格”的情形）、单次重放不判最后管理员；管理员交接的端到端没有演练。去处：成员切换（D75 只留形状）一并演练 |
| RC35 | 有 | 演练第 6 步：`ops/recover` 在 `replaying` 阶段读证据存储（系统方法，服务到方法许可） |
| RC40 | 有 | 授权成员 `RecoveryService.ReplayDeferred` 与 `Check`（3.0.30，改坏 12 处全红）：会结束管理员持有资格且之后为零的不执行、持有人 `recovery_review` 关闭、判最后管理员进待恢复 |
| RC41 | 有 | 身份成员 6.6（3.0.26，`recovery` 一段）；演练“恢复前的会话 0 个还开着” |
| RC43 | 有 | 第 9 步的审计损失按来源的产生序号空位与窗口（`TestTheAuditLoss`，演练“7 个来源”）；严格档 `TestAStrictReadIsReleasedOnlyWithItsReceipt` |
| RC44 | 部分 | `be-ops` 拒收纪元不对的记录（`TestARecordWithoutAnIdentityOrAWrongEpochIsRefused`），“已体现”按记录身份不按位置；纪元历史祖先的比较没有专门用例（首批部署没有从更早备份单独恢复某个库的路径）。去处：多库、多实例的恢复（T11d 之后） |
| RC45 | 有 | `keys`（6.8）：新的当前与备用密钥，演练“签名密钥换新” |
| RC46 | 有 | T10e、T11 场景 1：`r-pending` 在 T 时 `retry_wait`、T 后发出，对账 `matched` 终结，外部只收 1 次 |
| RC47 | 有 | `TestRecoveryPhases`（恢复阶段后台作业不领取）、`TestExternalCommandsOnlyQueryWhileVerifying` |
| RC48 | 有 | `TestNotFoundWithoutDedupeGoesToManual`、向量 `external-reconcile` |
| RC49 | 有 | 恢复阶段公钥集合在用户面答 `MAINTENANCE`（身份成员 3.0.26）；“开放前核对全部验证方已刷新”只记进开放记录由批准人确认（T10d 记为已知缺口，见第 4 节） |
| RC51 | 有 | 对账的查询窗口往前留余量（`--window`，向量 `external-reconcile`） |
| RC54 | 有 | 同 RC41（Cookie 对应的会话已结束） |
| RC56 | 有 | T11 场景 8：去重期 61 分钟、截止已过的 `r-stale` 转 `manual`，外部收 0 次；向量 |
| RC57 | 有 | 同 RC06 |
| RC58 | 部分（T13d） | 证据存储从备份恢复后，备份点之后的收紧从告警渠道补回（重放合并证据存储与告警渠道，`be-ops` 的 `TestTheCallsMergeTheStoreAndTheAlerts`），其余列入损失；信任材料只在运行档案（A148），不随证据存储回退；代次取最大值加一（P12.5、`TestAGenerationAdvancesOnlyThroughTheRunProfile`）。证据存储本身从备份恢复没有演练（演练里审计库从不回退） |
| RC59 | 有 | 告警记录签名不成立不执行、列复核（`runprofile` 的 `TestATamperedOrForeignRecordIsNotUsed`、`be-ops` 的 `TestTheCallsMergeTheStoreAndTheAlerts`）；不关闭管理员（授权 `Check` 的 `AdminsNotClosed`） |
| RC60 | 有 | `TestPastTheDeadlineNothingIsSent`；向量 |
| RC61 | 有 | T11 场景 5 |
| RC62 | 有 | 签名不成立的记录所涉主体进 6.5 的复核主体（`be-ops` 的 `alerts`，`TestTheReplayCallsInOrderAndWaitsForTheSources`） |
| RC63 | 推理（T13c，A147） | 部署所有者的确认凭据与恢复凭据是部署的密钥文件，不在库里、不在恢复组内，整套恢复不让它们回退，第 4 步没有摘要可恢复；恢复后管理员恢复用的就是文件里的新凭据；协议 15 写明了这种情形 |
| RC64 | 有 | T11 场景 6：在 Casdoor 里改的密码由比较记证据（`credential_tightening_in_product`），6.7 核对 `consistent` |
| RC67 | 有 | 强制登出的重放只结束会话（身份成员 `replayLogout`）；6.6 覆盖 |
| RC69 | 有 | 同 RC60 |
| RC70 | 部分 | 参考模型与向量有“可能已执行待核实”；演练的探针不是不可撤回的付款（没有发出记录），没有走到。去处：第一个真实的不可撤回适配器 |
| RC71、RC72、RC80、RC81、RC83、RC86、RC87、RC88 | 有（T13d，A148） | 信任材料历史只记在运行档案（线协议 P12.24–P12.27，向量 `trust-history`）：SDK alpha.101 的 `BuildTrust`、`Holds`，`ListAll` 按收到时刻核验（`TestTheTrustHistoryVectors`、`TestTheTrustHistoryOnCertificates`、`TestTheTrustHistoryInTheStore`：RC81 轮换后旧 CA 下的记录仍有效、RC71/RC80 吊销后收到的无效、RC86 CA 吊销后其下的无效、伪造的轮换不受信）；alpha.102 写入者必须是签名证书的身份（P12.4，`TestATamperedOrForeignRecordIsNotUsed`）；签发者 `be-ops trust`（alpha.14，`internal/trust` 的六个测试：签发与轮换先写运行档案（RC87），吊销先生效、写不进时留存补写（RC88），吊销当前 CA）；第 6 步列出历史不用的信任记录（`TestTheReplayStepRunsTheCallsInTheNetworkAndRecordsTheList`）；RC83 按结构（信任材料不在证据存储）。演练见 T13e。运行时的服务凭据吊销（mTLS 不查吊销）是安全 03 的缺口，不在这一组 |
| RC73 | 推理（T13c，A147） | 同 RC63：凭据在文件里，不会出现“库里只有意图的轮换” |
| RC75 | 有（T13a） | `be-ops` alpha.11：核对与只读开放中 `freeze --approver --reason` 重新冻结，回到恢复中、第 7 步起重做（`TestAFreezeAgainFromVerifyingOrReadOnly`） |
| RC76 | 部分 | 同 RC70 |
| RC78 | 有 | T11 场景 6（Casdoor 不在恢复组内，A141）：只结束本平台会话、核对凭据收紧仍然有效 |
| RC79 | 有 | 签名者不是这类记录的记录者判无效（`be-ops` 的 `alerts`：签名成立且签名者就是记录者才重放） |
| RC84 | 有（T13c） | 授权 `Check` 判最后管理员进待恢复（3.0.30）；部署所有者的管理员恢复（第 3 项的测试）；只读开放的守卫：`be-ops` alpha.13 的 `open-read` 问授权状态，待恢复时拒绝开放（`TestTheStepsOfVerifyingAndOpening`、`TestAdminsCall`） |
| RC85 | 有（T13b） | 同第 4 节的 CP107 |
| RC37 | 有 | 身份成员比较 Casdoor 的回退判断（`comparison` 一段：重新停用并告警） |
| RC55、RC68、RC77、RC82 | 不适用 | 身份产品在恢复组内（作废凭据）的一列；首批部署 Casdoor 不在恢复组内（A141）。去处：有部署把身份产品放进恢复组时 |

注：RC 首批 69 条（计划 T1 的“进首批”一栏，RC72 在信任材料一组里记“部分”）；RC37 列在后面，对照计划的分组。

## 3. 协议 03

| 编号 | 结论 | 依据 |
| --- | --- | --- |
| AU01 | 有 | SDK `audit` 的 `TestBacklogDrainsInOneRun`、`TestNumberingTransferAndDeletion`（本地记录留到回执） |
| AU02 | 有 | 审计组件的幂等（`TestAuditEndToEnd`）；`TestNumberingTransferAndDeletion` |
| AU03 | 有 | `TestInvalidAndUnknownReceiptsStopTheRecord`；审计组件的冲突 |
| AU04 | 有 | 按已备份水位删除（`TestNumberingTransferAndDeletion`、向量 `audit-purge`） |
| AU05 | 有 | 分叉点之后的回执作废（向量 `audit-purge`、`TestPurgeVectors`） |
| AU06 | 有 | `TestChangesAreAuditedWithTheirTransaction` |
| AU07 | 有 | `TestASensitiveReadIsRefusedWhenItsRecordCannotBeWritten` |
| AU08 | 有 | `TestTheReadsRecordIsCommittedBeforeTheDataIsReleased` |
| AU09 | 有 | `TestDenialsPastTheBudgetAreCountedNotLost` |
| AU10 | 有 | `TestOverCapacityOnlyRequiredAuditsAreRefused` |
| AU13 | 有 | 审计组件的查询（`TestAuditEndToEnd`：要查看权限、查询本身写审计、字段裁剪，T4e） |
| AU14 | 有 | 审计组件的链校验（`TestChainOverDigests`、T4e 的 `audit_chain_break`） |
| AU15 | 有 | `TestRestrictedFieldsAreKeptAsDigests` |
| AU19 | 有 | 向量 `audit-purge`（分叉点） |
| AU20 | 有 | 同上（回执纪元不在历史中） |
| AU21 | 有 | 同上（新纪元未备份不删） |
| AU22 | 部分 | 严格档（`TestAStrictReadIsReleasedOnlyWithItsReceipt`）；默认档的损失窗口由第 9 步的审计损失列出（演练）；“审计组件库恢复到更早的备份”没有演练（审计库在整套恢复中不回退） |
| AU23 | 有 | `TestInterleavedReceiptsTripNothing` |
| （AU16、AU18 首批之外，AU11、AU12 转出，见计划 T1） | — | — |

AU22 记“部分”。AU05、AU19–AU21 靠向量与单元测试，审计组件真的从备份恢复没有演练（整套恢复里审计库不回退）。

## 4. 第 3 项转来的

| 编号 | 结论 | 依据 |
| --- | --- | --- |
| AT19 | 有 | 恢复后授权恢复代次推进、旧视图作废（第 4 步，`TestAdvanceAndRedeliver`；演练后组件照常取新视图） |
| AT59 | 有 | 代次的权威计数在运行档案与证据存储，推进取各处最大值加一（`TestAGenerationAdvancesOnlyThroughTheRunProfile`、演练的 `generation.authz` 记录） |
| AT63 | 有 | 同上（取证据存储、各库与运行档案的最大值） |
| CP78 | 有 | 取消作为收紧两段写入证据（授权 3.0.27）、重放后仍是已结束（授权 `TestTheReplayAppliesTheEvidenceAgain`） |
| CP60 | 有 | 证据存储不可达时收紧照常、证据走告警渠道（SDK `TestAnUnreachableStoreDoesNotHoldATighteningBack`；T11 场景 5）；放宽部分等新代次的分支由管理员恢复的代次推进守着（第 3 项 A129） |
| AT62 | 部分 | 拿不到新代次时操作不开始：管理员恢复有（第 3 项）；成员切换不在首批（D75） |
| CP73、CP102、CP107、CP112 | 有（T13b） | 账号状态记录带引起它的证据记录身份（安全 09a 的 `evidence`，身份成员 3.0.33 的 `accountOperations`、`comparison`、`replay` 各一条断言），授权成员以它作 `signal_ref`；解除的证据带处置与 `signal_refs`，重放按 `signal_refs` 找处置、没到齐答 `deferred`，`be-ops` 在 6.4 之后再问（授权成员 3.0.37 的 `identitySideRecovery`：CP73 派生、CP102 解除、推迟后应用、CP112 两个一起移除、CP107 只移除点名的；`be-ops` 的 `TestADeferredRecordIsAskedAgainAfterTheSources`）。T13b 之前解除根本重放不了（证据里没有解除的内容，被当作缺候选的放宽） |

## 5. 门槛之外的已知缺口（汇报时列出）

- 信任材料历史（RC71 一组、RC58、RC83）；
- 恢复凭据与确认凭据在第 4 步的处理（RC63、RC73），管理员恢复在恢复中的端到端（RC84）；
- 身份侧处置的恢复（CP73、CP102、CP107、CP112、RC85）；
- 从只读开放重新冻结（RC75）；“双通道失效”时间段进损失范围（RC22）；
- 开放守卫的两条自动核验（全部验证方已刷新公钥集合、至少一名授权管理员能登录）仍由批准人确认；
- 恢复工具在 Kubernetes 上的调用（`replay-calls` 等只认 Docker）。
