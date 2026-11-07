# 第 5 项（冷热数据）的门槛核对

门槛（[实验计划](../experiment-plan.md)“实验之后：底层先行”的冷热数据一行）：协议 11 的替换检查全过（规划向量、真实数据库上的长时间推演、冷层往返、冷读一致、端到端擦除），TR01–TR30 全过。T1 建表（第 4 项复盘 R3），每个任务完成时把它覆盖的行改成测试名；收尾只核对。

状态：“未做”；“有”（测试或演练的名字）；“部分”；“推理”（写理由）；“转出”（写去处）。

## 1. 协议 11 的独立预期

| 编号 | 场景 | 固定预期 | 任务 | 状态 |
| --- | --- | --- | --- | --- |
| TR01 | 一个月的订单大多已关闭，少数仍未完成 | 只封存已关闭的聚合；未完成的留在在线层 | T4 | 有：SDK `TestSealingAndTheWriteBarrier`（只封存已关闭、过了驻留期的订单） |
| TR02 | 封存后发生对已封存订单的更正 | 写成更正记录，原记录不变 | T4 | 有（机制）＋转出（业务）：写屏障拒绝对已封存订单与明细的任何写入（SDK `TestSealingAndTheWriteBarrier`；长时间推演里对已封存文档的写 935 次全部 `RECORD_SEALED`、模型不变）；“写成更正记录”是业务单据（退货、贷项）引用原单新建，不改原单，转出到 `erp/sales` 的退货与 `erp/billing` 的贷项重建时验证 |
| TR03 | 封存与写入同时提交 | 至多一方先赢；写入先赢则封存重新计算 | T4 | 有：SDK `TestASealAndAWriteSerialize`（根行）、`TestASealWaitsForAChildWrite`（子表不改外键的更新，屏障的 `FOR SHARE`） |
| TR04 | 转层工作者在复制中途停顿，租约过期，另一个工作者接替 | 只有新工作者能发布；旧工作者的对象被清理 | T5 | 有：SDK `TestOnlyTheCurrentClaimPublishes`（被接替的认领发布被拒，它写的对象由孤儿清理删除，已发布的留着） |
| TR05 | 校验发现行数相同但内容摘要不同 | 不发布；保留源数据并告警 | T5 | 有：SDK `TestATamperedCopyDoesNotVerify`（行数相同、内容不同：温层的行与对象存储的对象各一次；只改一个字节的对象由散列拦下） |
| TR06 | 发布后有一个持续 30 分钟的导出仍按旧路由读取 | 在线层在导出结束或租约过期前不删除 | T6 | 有：SDK alpha.105 `TestTheReleaseConditions`（发布前取的租约挡住释放，WhyLease） |
| TR07 | 宽限期内列出全部历史订单 | 每个单元只出现一次 | T6 | 有：SDK alpha.105 `TestAListUnderASnapshotReadsEachOrderOnce`（快照前与快照后发布的单元，四张订单各读一次） |
| TR08 | 按 ID 读取已转层的订单 | 经定位索引读冷层 | T6 | 有：SDK alpha.105 `TestReadsByKeyFromEveryRoute`（温层与对象两种路线，与在线时的规范行相同） |
| TR09 | 目录指向冷层但对象缺失 | 返回暂时无法读取并告警，不说不存在 | T6 | 有：SDK alpha.105 `TestAMissingObjectIsUnavailableNotAbsent`（DEPENDENCY_UNAVAILABLE，不是 NOT_FOUND）；告警在 T9 的核对里补 |
| TR10 | 默认列表“未收款发票” | 包含很早创建、仍未关闭的发票 | T6 | 有：`erp/sales` 3.0.35 `TestSalesEndToEnd` 的 tiering 一步（订单列表的默认范围：500 天前创建、仍未结束的在，已结束且超出 N 天的不在、已归档的不在；`history=true` 都在）|
| TR11 | 冷读取不能完整完成 | 返回异步任务或明确的不能完成，不返回部分数据 | T6 | 有：SDK alpha.106 `TestAHistoryPastTheLimitBecomesAnExport`（超过时限答导出、不答部分；导出按运行时的授权、只给请求者、预签名地址读到的与完整的同步读相同）、`TestAHistoryThatCannotBeExportedIsNotCompletable`（无存储、对象锁、无导出、无读取器答 QUERY_NOT_COMPLETABLE） |
| TR12 | 撤权后继续翻页冷数据 | 按当前授权检查；不因游标绑定旧快照而保留访问 | T6 | 有：SDK alpha.105 同 TR07 的测试（当前授权过滤一张、掩码到两个字段；租约过期答 QUERY_PLAN_CHANGED）；读历史（在线加冷层）按当前授权、撤权后下一次读不再含被撤的行：SDK alpha.106 `TestAHistoryReadIsCompleteUnderTheCurrentAuthorization`；组件的授权接线在 T10 |
| TR13 | 保留到期但有法律保全 | 不销毁 | T7 | 有：SDK alpha.107 `TestTheDestructionConditions`（单元、类别或其中一张订单的保全都挡住销毁） |
| TR14 | 销毁工作检查保全后、删除前设置了保全 | 删除的决定在同一事务内检查，保全生效，不销毁 | T7 | 有：SDK alpha.107 `TestAHoldSetDuringTheDecisionWins`（决定事务对保全表取 SHARE 锁，等未提交的保全，看到后取消意图） |
| TR15 | 已封存的单元中有人申请个人信息擦除 | 生成新的清单版本；保全中则推迟并告警 | T7 | 有：SDK alpha.108 `TestAnArchivedOrderIsErasedAsANewVersion`（温层与对象两种路线：新清单版本、状态不变、只擦这一张、解冻副本删除；保全中推迟并告警、不写意图）、`TestAHoldSetDuringAnErasureWins` |
| TR16 | 从备份恢复到销毁之前 | 重新执行销毁 | T7、T9 | 有（SDK）＋转出（演练）：SDK alpha.107 `TestADestructionAfterTheRecoveryPointIsReplayed`（库回到销毁之前：单元回到 released、行在；重放置为 destroyed，下一次销毁运行删数据；再重放答已体现）；整套恢复里它由第 4 项的 `be-ops recover replay` 调属主的重放（`erp/sales`、`infra/audit` 已登记销毁类别），这一项没有另跑带冷热数据的整套恢复演练，转出到下一次整套恢复演练 |
| TR17 | 恢复后发现未发布的冷对象 | 不开放读取；重做或清理 | T9 | 有：SDK alpha.110 `TestTheTieringRecoveryCheck`（不属于任何清单版本的对象与温层行是差异，读取只认清单所以不开放）；清理：alpha.116 `TestTheDailyCleanupRemovesEveryUnitsOrphans`（每天的作业 `be.tiering.cleanup`，P15.20；在这之前没有作业调用清理，T11a 设计推演时发现）；真机格 T10e 的恢复核对（套件 1.0.63 起建格时清空本格的冷层前缀，别的部署留下的对象正是这里说的差异） |
| TR18 | 解冻一个单元 | 只读、有到期时间；不重开写入 | T6 | 有：SDK alpha.105 `TestAThawedUnitReadsFromItsCopy`（对象删掉后仍从副本读、写入照样 RECORD_SEALED、清理不删活着的解冻） |
| TR19 | 读取旧结构版本的单元 | 经转换器读取，转换结果另行校验 | T8 | 有：SDK alpha.109 `TestAnOlderStructureIsReadThroughItsConverter`（温层与对象两种路线；没有转换器答 QUERY_NOT_COMPLETABLE、可读检查列出版本；转换结果不合类别的结构或丢了定位列被拒；路线更换以现在的结构重写） |
| TR20 | 从同库分区换到对象存储 | 同一协议完成复制、校验、发布、释放 | T8 | 有：SDK alpha.109 `TestARouteChangeMovesAReleasedUnit`（转层作业把单元从温层换到对象存储：复制、校验、发布，旧版本按宽限期、租约、备份释放） |
| TR21 | 单号的唯一性 | 由不分区的登记表保证，登记不随单元转层 | T4 | 有：SDK `TestAClassDeclaration`（唯一登记表不能是类别的表，P15.5） |
| TR22 | 去重与幂等记录按年龄搬走 | 不允许；按自己的保留规则清理 | T4 | 有：SDK `TestAClassDeclaration`（不转层的种类不能有驻留期与路线）、向量 `tier-plan` 的 `not-tierable` |
| TR23 | 财务凭证所在的期间未关闭 | 不能封存 | T4 | 有（机制）＋转出（业务）：阻塞检查由模块登记（SDK `TestABlockedGroupingStaysOpen`；`erp/sales` 的三个真实阻塞，TR30）；“财务凭证所在的期间未关闭”的真实检查属于总账组件，还没有重建，转出到它 |
| TR24 | 没有法规或合同依据的保留年限 | 标为待确认，上线时由客户确定 | T7 | 有：SDK alpha.107 `TestTheDestructionConditions`（`pending` 答 retention_pending，从不销毁）；alpha.111 部署时给保留期（`TIERING_RETENTION_<类别>`，`TestARetentionGivenAtDeployment`）、没给的启动时各记一条 `tiering_retention_pending`；上线手册的一步（`05-operations/04-go-live.md`）；`infra/audit` 3.0.30 的审计记录声明为 `pending`、由部署给 |
| TR25 | 30 天前创建、20 天前关闭的订单所在的单元 | 在最近的记录满 N 天之前不释放在线层，默认列表不漏掉它 | T6 | 有：SDK alpha.105 `TestTheReleaseConditions`（最近记录 30 天时 WhyRecentRecords）；默认列表不漏掉它在 T10（TR10） |
| TR26 | 已释放在线层的单元从同库分区换到对象存储 | 状态保持 `released`，新路线的副本校验后以新清单版本发布，旧路线宽限期后释放 | T8 | 有：同 TR20 的测试（状态保持 released、新清单版本、`route_version` 前移，旧路线的行在条件满足后才删） |
| TR27 | 单元已封存、尚未发布时收到个人信息擦除 | 在线行按协议 07 擦除，单元重新计算摘要；进行中的转层工作项发布失败并重做 | T7 | 有：SDK alpha.108 `TestAnErasureInASealedUnitRestartsItsTransfer`（在线行置空、摘要重算，擦除前的副本发布被拒，下一次转层发布擦除后的内容） |
| TR28 | 一个单元的订单都已关闭、满足封存条件，但最晚的关闭在 5 个月前（驻留期 12 个月） | 不选为候选，留在在线层 | T4 | 有：SDK `TestSealingAndTheWriteBarrier`（五个月前关闭的不封存）、向量 `tier-plan` 的 `residence-not-reached` |
| TR29 | 客户把已完成单据的驻留期从 12 个月改为 6 个月；另一次试图改为 30 天 | 下一轮选出新满足条件的单元，已发布的单元不变；30 天低于下限 N，被拒绝 | T4 | 有：SDK `TestAClassDeclaration`（短于 N 拒绝）、向量 `tier-plan` 的 `residence-shortened`、`residence-below-n` |
| TR30 | 单元过了驻留期 30 天，仍有一张订单的预占未结束 | 不封存；告警并列出这张订单与未结束的预占 | T4 | 有：阻塞时整个分组不封存、原因记在单元（SDK `TestABlockedGroupingStaysOpen`）；到期 30 天仍阻塞的告警 `tiering_blocked`（`TestTheCandidatesJobSealsAndAlerts`）、规划的告警（向量 `blocked-alert`） |

## 2. 转来的与参考模型没覆盖的

| 编号 | 内容 | 任务 | 状态 |
| --- | --- | --- | --- |
| AU17 | 法律保全期间到达保留期：不删除（协议 03；A143 把审计的保留期删除与法律保全放到这一项） | T7、T10 | 有：`infra/audit` 3.0.30 `TestTheAuditRecordsTier`（审计记录封存、转层、释放后，保留期已过、删除已批准，一条记录的法律保全挡住整个单元的删除；解除后才删）|
| RC08 | T 之后执行的销毁：恢复后重新执行（协议 15） | T7、T9 | 有（SDK）＋转出（演练）：同 TR16 |
| RC11 | 目录指向的冷对象缺失：核对不通过，按协议 11 处理后才开放（协议 15） | T9 | 有：SDK alpha.110 `TestTheTieringRecoveryCheck`（清单里的对象缺失、温层行不全是差异，读取答暂时不可用）；真机格 T10e（`foundations-05-data/t10e/`：T5-S、T5-H 三个成员的 `be.tiering` 经 `be-ops recover verify-calls` 在部署网络里调，转层并释放之后答 `pass`）；长时间推演 T11a 的终态核对 |
| RC24 | 销毁只有意图、本地提交失败：恢复后不自动执行，列入人工复核（协议 15） | T7、T9 | 有（推理）：SDK 的销毁只在决定成立时写结论，否则取消意图（`TestAHoldSetDuringTheDecisionWins`）；本地提交失败时意图留着、不自动执行，“只有意图的列入复核”是恢复工具对一切证据类别的通用行为（第 4 项 T9 与 T13e 演练过），销毁类别走同一条路；带冷热数据的整套恢复演练同 TR16 转出 |
| M1 | 认领纪元：发布核对工作者认领时的代次与纪元，且纪元仍是当前的（模型没覆盖） | T5 | 有：SDK `TestOnlyTheCurrentClaimPublishes`（认领与发布之间纪元变了，发布被拒） |
| M2 | 擦除的新清单版本：擦除后的副本、重算摘要、旧版本按保全与恢复规则清理（模型没覆盖） | T7 | 有：SDK alpha.108 `TestAnArchivedOrderIsErasedAsANewVersion`（擦除后的副本、新清单版本、重算摘要）；alpha.109 `TestAnErasedVersionsOldObjectsAreReleased`、`TestARouteChangeMovesAReleasedUnit`（旧版本在宽限期、租约与新版本之后的备份都满足后才删） |
| M3 | 恢复时的核对的四种发现（模型没覆盖） | T9 | 有：SDK alpha.110 `TestTheTieringRecoveryCheck`（目录指向冷层而对象缺失、对象在而清单未发布、已释放仍有在线行）；销毁晚于恢复点由重放处理，alpha.107 `TestADestructionAfterTheRecoveryPointIsReplayed` |

## 3. 门槛的五层检查

| 检查 | 内容 | 任务 | 状态 |
| --- | --- | --- | --- |
| G1 规划向量 | 输入数据类别、单元、时间、保全与能力，输出动作与被阻塞的单元；Go 对向量全过（Python 随第 6 项） | T3、T11 | 有（Go）：SDK `TestThePlanVectors`、`TestTheDigestVectors`、`TestTheManifestVectors` 对向量全过；第三方读取器（套件 `tierread.py`）答全部摘要向量；Python 的转层实现转出到第 6 项（Python 剖面） |
| G2 长时间推演 | 真实数据库，多副本与外壳成员同时运行，每个状态迁移点注入崩溃，最终状态一致；数据量让边界条件出现 | T11 | 有：SDK alpha.116 `TestTheLongSimulation`（构建标签 `simulation`；`foundations-05-data/t11a/run2/`）：真实的 PostgreSQL 与对象存储，两个成员（中途互换路线），四个副本（两个承载两个成员、即外壳的形态），每个后台事务提交前后与每次对象写删共 30 个崩溃点轮换注入（30 分钟 376 次，另 33 次随机强杀，每个点 3–15 次），同时写、改、关、对已封存的写、请求擦除与排队重做、保全、备份与按身份读；终态 25508 份文档逐份读回一致、14569 个副本核对通过、恢复核对通过、没有卡住的工作项。数据量：Parquet 每 40 行一个对象、释放每批 7 行、一万四千多个单元。第一轮撞出的缺陷与修正在计划“T11 的结果” |
| G3 冷层往返 | 每种列类型冻结、读回、摘要相等；第三方读取器从文件与清单算出同一个摘要；不可改写的存储拒绝可擦除的数据 | T5、T11 | 有：每种列类型写成 Parquet 再读回、规范行与表的散列相等（SDK `TestEveryColumnTypeRoundTrips`）；开了对象锁的桶拒绝可擦除的类别（`TestALockedBucketRefusesErasableData`）；套件的转层剖面（探针 3.2.47：每种列类型加 `text[]`、三层、叶子表两列主键，两条路线）；**第三方读取器**（套件 1.0.63 的 `tierread.py`：只用 pyarrow 26.0.1 与协议条文，不用 SDK）答全部向量 `tier-digest`（`test_tierread.py` 18 例；它的改坏让线协议 alpha.112 补了 `table-hash-by-key-not-row`），在转层剖面里从清单与 Parquet 对象、从温层行算出的摘要等于封存时的摘要（两条路线） |
| G4 冷读一致 | 每个读取实现返回相同的行；封存前后与读回后的列表结果相同 | T6、T11 | 有：SDK alpha.105 的两种路线按 ID 读回与在线时相同、快照下的列表每单元一次；alpha.116 `TestTheSameReadAnswersTheSameAtEveryStep`（同一个历史读在线、封存、发布、释放、换到另一条路线、旧版本释放之后答同样的行，按身份在两条路线上相同）；套件 1.0.63 的转层剖面（第三方读取器读到的行与在线时相同，两条路线）；真机格 T10e（发布后、释放后按身份与历史读回 0 处差异）；长时间推演 T11a 的读者（每份文档按身份读、与最后写入的相同） |
| G5 端到端擦除 | 横跨在线层、冷层、数据集与导出，包括恢复之后的重新执行 | T7、T11 | 有（数据集转出）：在线（sealed）、温层、对象三处与恢复之后的重新执行（SDK alpha.108 `TestAnErasureAfterTheRecoveryPointIsReplayed`）；**导出**（线协议 alpha.113 的 P15.31，SDK alpha.116 `TestAnErasureVoidsTheExports`：完成的导出随擦除到期、读取途中的导出不以擦除之前的读取完成，A159）；长时间推演 T11a 在崩溃注入下擦除在线、已封存、已发布、已释放的文档（两条路线，请求的 2481 次与排队重做的 1474 次），每次读回为置空后的内容；**数据集**转出：数据集组件还没有（协议 13） |

## 4. 汇总

2026-11-07（T11e）：首批 42 行（TR01–TR30、AU17、RC08、RC11、RC24、M1–M3、G1–G5）都是“有”，其中带转出的 6 行写明了去处：
- **业务部分转出**：TR02 的更正单据（`erp/sales` 退货、`erp/billing` 贷项）、TR23 的期间未关闭（总账组件）；
- **演练转出**：TR16、RC08、RC24 在 SDK 层有测试或推理，带冷热数据的整套恢复演练留给下一次整套恢复演练；
- **语言与组件转出**：G1 的 Python 实现（第 6 项）、G5 的数据集（数据集组件，协议 13）。

没有缺口。真机格 T10e（单跑与外壳）与长时间推演 T11a 的第二轮都全过；它们撞出的缺陷都已修正并有定向测试（计划“T10e 的结果”“T11 的结果”）。
