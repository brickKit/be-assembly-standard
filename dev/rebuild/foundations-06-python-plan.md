# 底层先行第 6 项：Python 剖面

> 2026-11-07 起，按 `f-plan`。上一项：[第 5 项（冷热数据）](foundations-05-tiering-plan.md)，维护者 2026-11-07 确认门槛；维护者 2026-11-07 说“现在可以写计划并执行”。推进方式照根 `AGENTS.md`：连续推进，每个任务做完写记录、更新交接、提交；到门槛汇报。

## 门槛与范围

| 门槛（[实验计划](experiment-plan.md)“实验之后：底层先行”） | 这一项里指什么 |
| --- | --- |
| 按一致性套件补到代表组件需要的剖面；同一剖面两种语言都通过 | 套件里现在只驱动 Go 探针的剖面（事件、后台工作、水位来源、对外命令、转层）对 Python 探针也跑并通过；已经两边都跑的（核心、身份、授权）在新的 Python SDK 上照样通过；每个有数据库的 Python 成员（探针、`infra/print`）满足所有成员都要做的（恢复阶段 P1.23、恢复核对 P14.1、补发 P6.38），并在真机格与一次整套恢复演练里通过 |

**依据**：正式文档的“首批范围”（协议 18，D75）：Python 先实现代表组件用到的子集，功能矩阵如实标出其余能力“未实现”。前五项明确转给这一项的（T0 逐条列出）。

**范围**（T2a 逐条定）：

- `be-sdk-python` 的协议副本从 alpha.68 换到现行（alpha.116 起），SDK 自己的迁移 0013–0024 一起带上；已实现的能力对新向量照样通过；
- 线协议的章：第 06 章其余（补发 `ResendService`、消费者库回退后的补发 P6.36–P6.40）、第 07 章（后台工作项与 SDK 自带的作业）、第 09 章的水位来源一侧、第 12 章（证据、运行档案）、第 13 章（对外命令）、第 14 章（恢复核对）、P1.23（恢复阶段）、第 15 章（转层，含规划、摘要、清单的向量：第 5 项门槛 G1 的 Python 部分）；
- Python 探针补齐契约里标着“Python 随第 6 项”的（`fail`、`hold_ms`、`emit`，作业 `probe.steps`，水位来源，付款，归档，恢复操作）；
- `infra/print` 与外壳 `be/py-render` 换上新的 SDK，补上所有成员都要做的；
- 转来的：第 5 项复盘的 S1（长时间推演在第一条端到端路径做通后就写、随功能增补）与 S4（新的格脚本先在开着的格上逐步跑）；SF27 的 Python 部分（互通测试的 Go 小程序换上现行的 Go SDK）；`be-sdk-python` 补 `AGENTS.md`（分层 L7 转来）。

**不在这一项**（T2a 写明理由与什么时候做）：只有业务组件才用、而现在没有 Python 业务组件用的能力，例如金额、业务日期、列表内搜索、投影的消费一侧、预占的参与方（第 16 章）；三种 SDK 都只留形状的（严格路径、影子投影、成员切换、高可用、事件签名）。

## 任务

| # | 要做到什么 | 依据 | 依赖 | 验收 | 状态 |
| --- | --- | --- | --- | --- | --- |
| T0 | 盘点：两个 SDK 的能力表、套件里只驱动 Go 的剖面、探针契约里的“Python 随第 6 项”、前五项转来的、`infra/print` 用到 SDK 的什么 | 上面的门槛 | — | 本计划“T0 结果”一节 | ✅ 2026-11-07 |
| T1 | 门槛核对表 [`foundations-06-data/gate.md`](foundations-06-data/gate.md)：每个剖面的每项检查（Python 一列）、每个转来的条目、每条所有成员都要做的义务各一行“未做”，各任务完成时改成测试名（第 4 项复盘 R3） | T0 | T0 | 表里每行有去处；没有一行要靠猜 | ✅ 2026-11-07（A1–A4、B1–B11、C1–C12、D1–D3、E1–E3、F1–F4、G1–G4、H1–H6） |
| T2 | 要先定的（AI 定、记台账，真正要维护者定的才问）：T2a 能力的范围（逐个能力：做、不做的理由与触发条件）；T2b Python 的 Parquet 库（调研加实测，结果交 kb）；T2c CPU 重活（Parquet 编解码、摘要、渲染）在哪里算（kb 的“asyncio 的 CPU 重活”：进程池）；T2d 协议副本的换法（一次换到现行，还是逐章换） | 正式文档的首批范围、kb | T1 | 每个决定写进本计划与 `09-ai-choices.md`；实测有原始数据 | ✅ T2a、T2d 2026-11-07（A164、A165，见“T2 的决定”）；T2b、T2c 只有转层用到，挪到 T10，2026-11-10 定（A168、A169） |
| T3 | SDK 底座：协议副本换到现行、迁移 0013–0024、已实现能力的向量照样过；P1.23 的恢复阶段（进程级的阶段开关：用户面答 `MAINTENANCE`，转发、订阅、作业按阶段停）；`AGENTS.md`；`features.json`；pin-check 加“Python 成员只用一个 `be-sdk` 版本” | 线协议第 01、05、06 章 | T2 | `make test` 与 `make test-integration` 过；新能力先写红的测试；改坏检查 | ✅ 2026-11-07（见“T3 的结果”） |
| T4 | 后台工作项（第 07 章，含定时）：认领、租约与纪元、副作用种类、SDK 自带作业的登记与恢复规则（第 4 项复盘 R1 的表）；幂等键（P4.21–P4.25）与分区维护（A164）；Python 探针的 `probe.steps`；后台工作剖面对 Python 跑 | 第 07 章、P1.23 | T3 | 剖面 CK-WK-01…10 对 Python 通过（与 Go 一样的“移到 T10”的除外，写明）；SDK 的作业登记检查（照 be-sdk-go 的宿主登记测试） | ✅ 2026-11-07（见“T4 的结果”） |
| T5 | 事件的其余：补发 `ResendService`、消费者库回退后的补发（P6.36–P6.40）；探针的 `fail`、`hold_ms`、`emit`；事件剖面对 Python 在两种运输上跑 | 第 06 章 | T3 | 剖面 CK-EV、CK-BUS 对 Python 通过 | ✅ 2026-11-07（见“T5 的结果”） |
| T6 | 长时间推演（S1，第一条端到端路径通了就写）：Python 成员多副本、外壳里两个成员，作业与事件在崩溃点上注入故障、终态核对；之后每个任务往里加自己的崩溃点 | 第 5 项复盘 S1 | T4、T5 | 推演跑一轮 30 分钟通过，原始数据在 `foundations-06-data/` | ✅ 2026-11-07（见“T6 的结果”） |
| T7 | 水位来源（第 09 章的来源一侧，P9.13–P9.18）与它必须声明的记录读取 `RecordService`（P9.30–P9.33：水位来源的流必须声明，2026-11-07 读条款时补进范围；消费一侧仍不在首批）：探针的 `_wm` 流、`WatermarkService/Pull` 与记录读取；水位来源剖面对 Python 跑 | 第 09 章 | T5 | CK-WM-01…03 对 Python 通过；向量 `watermark-pull-check` | ✅ 2026-11-07（见“T7 的结果”） |
| T8 | 证据与运行档案（第 12 章）、对外命令（第 13 章，含幂等键 P4.21–P4.25 若付款要用）：探针的付款去掉 A144 的例外；对外命令剖面对 Python 跑 | 第 12、13 章，A144 | T4 | 对外命令剖面对 Python 通过；推演加对外命令的崩溃点 | ✅ 2026-11-07（见“T8 的结果”） |
| T9 | 恢复核对（第 14 章）与恢复操作：`CheckService`、`ReconcileService`、`<前缀>.recover`；`infra/print` 换上新 SDK，补恢复阶段与核对（模板按版本答“还在不在”）；外壳 `be/py-render` | 第 14 章、P1.23 | T8 | SDK 测试；`infra/print` 的集成测试；一次整套恢复演练里 Python 成员参加各阶段而不是被停下 | ✅ 2026-11-07（见“T9 的结果”；整套恢复演练里 Python 成员参加各阶段随 T11 的真机格，门槛 F4） |
| T10 | 转层（第 15 章）：先定 T2b、T2c；T10a 规划、摘要、清单的向量（第 5 项门槛 G1 的 Python 部分）；T10b 目录、封存与写屏障；T10c 复制校验发布、释放；T10d 读取、保全、销毁与擦除、路线更换、恢复核对；探针的归档；转层剖面对 Python 跑；推演加转层的崩溃点 | 第 15 章、第 5 项 gate.md 的 G1 | T6、T9 | 向量全过；转层剖面对 Python 通过；第三方读取器读 Python 写的冷层算出同一摘要；推演通过 | ✅ 2026-11-10（be-sdk-python a60–a61、探针 3.2.50–3.2.51、套件 1.0.73–1.0.74；门槛 G1–G4；T2b、T2c 实测定案 A168、A169；见“T10 的进度”） |
| T11 | 真机格（S4：新脚本先在开着的格上逐步跑）：Python 成员单跑与进外壳两格，业务链 L3 与套件剖面；整套恢复演练里 Python 成员参加 | 实验计划的格 | T9、T10 | 两格全过；演练通过 | ✅ 2026-11-10（套件 1.0.75；见“T11 的结果”） |
| T12 | 收尾：`gate.md` 逐条核对；SF27 的 Python 部分（互通测试换现行 Go SDK）；COMPAT；复盘；kb（T2b 的实测、这一项的反馈） | 全部 | 全部 | 门槛表全部“有”或写明转出 | ⬜ |

每个任务按改动的循环做（意图 → 考设计 → 契约 → 先写红的测试 → 实现 → 核对 → 发布）；测试写在实现之后的，照 K1 做改坏检查（`experiment-scripts/mutate.py`，Python 要关字节码缓存）。测试里的枚举值取自定义处（R8）。Python 的协议实现以线协议的条款与向量为准，不照抄 Go 的实现；两边行为不同时，不符合向量的一方是缺陷（SK05）。

**全局约束**：

- 探针契约两种语言一起改（`CONTRACT.md`）；两个探针的清单仍须一致（A144 的例外在 T8 去掉）。
- Python 的成员在外壳里共用一个事件循环：CPU 重活不上事件循环（T2c）；合并安全的检查覆盖新代码。
- SDK 每次发版后，Python 成员（探针 py、py2，`infra/print`）与外壳 `be/py-render` 的钉版本一起换（T3 加检查）；Go 一侧不受影响。
- 长任务（全部集成测试、推演、真机格）放后台配监视（`f-longrun`）。

**完成标准**：门槛表全部“有”或写明转出与去处；Python 的 `features.json` 如实；所有转来的条目有结论；容器关掉；走不通的尝试留下的东西清理掉。

## T0 结果（2026-11-07）

**两个 SDK 的能力表**（`features.json`）：Go 48 项（40 已验证、7 只留形状、转层 1 项已实现），Python 39 项（22 已验证、17 未实现）。Python 缺的、Go 已验证的：后台工作、定时、幂等键、金额、业务日期、分区、投影（记录、水位、消费）、搜索；表里还没有的：证据（写入与重放）、运行档案、对外命令、恢复核对、恢复阶段、补发、预占的参与方、转层。

**协议副本**：Python 在 alpha.68（迁移到 0012，向量 33 份），线协议到 alpha.116（迁移到 0024，向量 43 份）。

**套件**：核心（13 项）、身份（CK-ID-01…06）、授权（CK-AZ-01…05）两种探针都跑；事件（CK-EV、CK-BUS，12 项，两种运输）、后台工作（CK-WK-01…10）、水位来源（CK-WM-01…04）、对外命令、转层只驱动 Go 探针。

**探针**：Go 3.2.49，Python 3.2.42。契约里标着“Python 随第 6 项”的：写入的 `fail`、`hold_ms` 与消费者的 `emit`（3.2.29）、作业 `probe.steps`（3.2.30；Python 只声明 `PROBE_STEPS_EVERY`）、水位来源（3.2.31）、恢复操作 `<前缀>.recover`（3.2.42）、付款（3.2.41，A144）、归档（3.2.47）。

**`infra/print`**（3.0.15）只用到组件定义、配置、用户面路由、系统面方法、授权与错误、列表；它有数据库，所以 P1.23（恢复阶段）与 P14.1（`CheckService`）对它也是“必须”，现在整套恢复时它被停下。

**前五项转来的**：第 1 项（Python 的事务与消息剖面、时钟）、第 2 项（P8.25–P8.28 已在第 3 项随 a46 补上）、第 4 项 T7e（证据、对外命令、恢复核对在 Python 标“未实现”）、第 5 项门槛 G1 的 Python 部分（转层向量）与复盘 S1、S4；SF27 的 Python 部分；L7 的 `be-sdk-python` 的 `AGENTS.md`。

**kb**：有“Python asyncio 的 CPU 重活交给进程池”（`zh/11-software-engineering/04-concurrency-async/07-event-loop.md`）；没有 Python 的 Parquet 库对比（缺口，T2b 实测后连同反馈交 kb）。

## T2 的决定（2026-11-07，AI 定，待复核）

| 子步 | 定了什么 | 理由 | 台账 |
| --- | --- | --- | --- |
| T2a | 做：后台工作（含定时）、补发与消费者库回退后的补发、水位来源一侧、证据与运行档案、对外命令、转层、恢复阶段与恢复核对、幂等键、SDK 自带的分区维护。不做：金额、业务日期、列表内搜索、投影的消费一侧、预占的参与方（`features.json` 标“未实现”，第一个要用的 Python 组件出现时按已有向量补） | 套件剖面与成员义务决定下限；幂等键是接命令的成员都要声明的（P4.21），分区维护是 SDK 自带作业的一部分；不做的几项没有使用者，也没有剖面能验证 | A164 |
| T2d | 协议副本一次换到现行 | 副本是整份快照，逐章换会让向量与 schema 互相对不上 | A165 |
| T2b、T2c | 挪到 T10 开头 | 只有转层用到 Parquet 与大块的 CPU 计算；到时的版本与信息最新 | 2026-11-10 实测定案：A168（pyarrow）、A169（线程，读取分批），见“T10 的结果” |

## T3 的结果（2026-11-07）

- **be-sdk-python a52**：协议副本一次从 alpha.68 换到 alpha.116（A165），SDK 的迁移 0013–0024 照常建上；已实现能力要跟着补的只有两个错误原因（`RECORD_SEALED` 与 SQLSTATE `BE001` 的映射、`MAINTENANCE`）。新能力在 `features.json` 里标“未实现”并写明归哪个任务。
- **恢复阶段（P1.22–P1.24）**：`RECOVERY_PHASE` 是进程级的键；成员带它启动时是 `recovery_ready`（就绪答 200 带阶段，自述与就绪日志带阶段）；用户面答 `MAINTENANCE`，`read_only` 时放行读取与声明 `read_only_open` 的写入；`frozen` 不转发、不订阅、不跑模块后台与审计转运。外壳里没设阶段的成员用别的成员设的那个，外壳自己的端口也带阶段。先写红的集成测试（照 Go 的 `TestRecoveryPhases`），四处改坏都红；第一次的测试漏了“冻结时照样转发”（上一次运行持有的转发租约 10 秒，测试只等 1.5 秒），改成等过租约、并在总线上留一条待消费的消息之后才红。作业的一半随 T4。
- **互通测试**（SF27 的 Python 部分）：三个 Go 小程序换到 be-sdk-go alpha.117。换上之后 Go 一侧拒绝启动（有数据库的组件必须声明恢复核对与补发的操作、授权定义），按现行要求补齐，测试给它们测试部署的服务身份；互通与安全的集成测试全过。
- **AGENTS.md**：`be-sdk-python` 的代码地图（L7 转来）。
- **pin-check**：加“部署的 Python 模块只钉一个 `be-sdk` 标签”，对现状报出 `infra/print` 停在 a48（SF29），这次一起换掉。
- **连锁发版**：`infra/print` 3.0.16（a52，清单声明 `RECOVERY_PHASE`）；两种探针的清单是同一份，Python 一侧读了这个键后也要声明，Go 探针 3.2.50（只改清单）、Python 探针 3.2.43（a52）；套件 1.0.66（`make check` 168、`make probes` 192 全过）；外壳 `be/go-infra` 3.0.70、`be/go-core` 3.0.70、`be/py-render` 3.0.43（`foundations-06-data/t3/shells.sh`）；`erp/billing` 依赖打印，3.0.43 换到 `infra/print` 3.0.16，`be/go-core` 再到 3.0.71。pin-check 0、`make version-check`、`make gates` 全过。

## T4 的结果（2026-11-07）

- **be-sdk-python a53**：`besdk.work`（排入、认领、租约与纪元、提交的认领核对、停止时交还租约与尝试、副作用种类、失败与退避、业务等待、死信、单例与分段进度、时限、提交后唤醒、一个轮询叫醒一个工作者、晚到期的项、每个副本的定时、运维的重新排队与标为已解决、清理）；`besdk.work.cron`（向量 `cron-slots` 16 个全过，水位锁、补跑策略、到下一个槽之前不开事务）；`besdk.idem`（向量 `idempotency` 22 个全过，认领、命令与结果同一事务，并发同键只执行一次）；`besdk.db.partitions`。宿主给有数据库的成员一个运行器（`rt.work`）、模块的作业（`jobs(j)`）与 SDK 自带的四个作业，每个作业在 `besdk/sdkjobs.py` 写明恢复阶段的行为，结构检查守住；作业只在正常运行时跑。
- **改坏检查**：运行器与认领 19 处全红（`foundations-06-data/t4/mutants-t4a.txt`，另有两处是等价改坏，写明后去掉）；cron 10 处，第一次有一处活下来（`none` 策略：向量唯一的 `none` 用例恰好在一分钟以内，与 `latest` 结果相同），补了 SDK 测试后全红（`mutants-t4b.txt`）。**给线协议**：`cron-slots` 向量缺“`none` 且最后一个到期槽早于一分钟”的用例，下次发协议时补。
- **顺带查出**：`test_bus_ready_integration` 的夹具 `serve()` 写反了，从来没跑迁移；成员启动时要登记 SDK 作业，它就红了。按夹具的意图改成先迁移（断言不动）。P7.20（每个作业的指标）与 Go 一样未做，`features.json` 写明。
- **探针**：Python 探针 3.2.44 补上后台工作项（每种副作用一个作业、`probe.minutely`、`probe.steps`），转发也改用作业 `probe.relay`（与 Go 探针相同；原来自己的转发表不再用、按只加不删留着）；套件 1.0.67 的后台工作剖面对两种探针都跑，Python 探针第一次就“符合”；`make check` 168、`make probes` 193 全过。
- **连锁**：`infra/print` 3.0.17（a53）、`erp/billing` 3.0.44、外壳 `be/go-core` 3.0.72、`be/py-render` 3.0.44（`foundations-06-data/t4/shells.sh`）；pin-check 0、`make version-check` 过。

## T5 的结果（2026-11-07）

- **be-sdk-python a54**：收件表记来源位置、订阅记运行段（P6.36）；进度（P6.37，向量 `inbox-progress` 全过）；生产者的补发 `be.source.v1.ResendService`（P6.38，有流的成员必须声明 `Definition.resend`，与 Go 相同）；清理记下清到的位置；消费者库回退后向见过的每个生产者要补发、记缺口、全部答完才更新纪元（P6.39、P6.40；读模型的快照修复属于投影的消费一侧，不在首批）。消息有了与事件身份分开的去重身份（`msg_id`）。协议的 gRPC 代码由 `scripts/gen.py` 从协议副本的 `proto/` 生成进 `besdk/_gen`（A166）。改坏 14 处全红。
- **测试跟着改的**：有流的 Python 成员现在必须有服务身份与补发操作，互通与恢复阶段两个测试里的生产者补上（和 Go 的互通小程序在 T3 补的一样）。
- **探针**：Python 探针 3.2.45：写入的 `fail`、`hold_ms`，消费时的 `emit`，补发操作；套件 1.0.68 的事件剖面对两种探针、两种运输都跑，Python 探针“符合”；`make probes` 195 全过。
- **连锁**：`infra/print` 3.0.18、`erp/billing` 3.0.45、外壳 `be/go-core` 3.0.73、`be/py-render` 3.0.45；连锁写成了可复用的 `foundations-06-data/python-cascade.sh`（带参数：SDK、探针与打印的版本）。

## T6 的结果（2026-11-07）

- **推演**（`be-sdk-python` 的 `tests/sim`，`make simulation`）：两个成员 sim/a、sim/b，三个副本（承载两者的外壳、各自单跑）在真实的 PostgreSQL 与 PostgreSQL 队列上；每个副本轮流在一个崩溃点结束自己（`besdk/crash.py` 的 17 个点：工作项的认领、完成、调用前、检查点、重试、等待、暂停、死亡、续租、记录调用，事件的编号、发布、标记已发布、收件表，各有提交前后），父进程不时随机强杀；之后排空、核对终态（作业恰好生效一次、非幂等调用至多一次、事件恰好处理一次或进死信、发件表位置无缺无重、单例的步与定时槽不重跑、没有卡住或死掉的工作项、每个崩溃点都走到）。1 分钟的冒烟 17/17 个点通过，改坏一处被它抓到。
- **第一轮 30 分钟没过，撞出一个两种 SDK 都有的缺口**（`foundations-06-data/t6/sim-1-p620-gap.log`）：sim/b 的一条事件（分区 0、位置 288、已发布）sim/a 从没处理过，也没有死信。原因：最后一次投递在处理中途进程退出时，运输不再投递（PostgreSQL 队列放弃、JetStream 的 MaxDeliver），订阅方也看不到失败。修法（A167，协议 alpha.117 改写 P6.20）：处理投递次数已达上限的那一次之前先提交死信（起因“最后一次投递没有结局”），处理成功或已应用时在应用事务里删掉，失败时改起因。`be-sdk-go` alpha.119、`be-sdk-python` a55 都先写了会红的测试（处理中途死信已在库里、成功后没了）。推演把这种死信算作结局（真实系统里由运维重投），已处理又有死信、或起因是别的错误仍算问题。
- **修复后重跑 30 分钟通过**（`foundations-06-data/t6/sim.log`，电源模式 balanced：正确性测量，不受电源影响）：4309 个订单、89 次强杀、6000 多次启动，17/17 个崩溃点，0 个问题；sim/a 有 1 条事件的最后一次投递赶上崩溃，进了死信（起因“没有结局”）——修复之前它会无声消失。
- **连锁**：Go 一侧 11 个组件经 `sdk-unify.py` 换到 alpha.119（`t6/unify.log`），`be-ops` alpha.18、`be-edge` alpha.4；Python 一侧 `infra/print` 3.0.19；探针 Go 3.2.51、Python 3.2.46。

## T7 的结果（2026-11-07）

- **be-sdk-python a56**：流可声明水位来源（`Stream.watermark`：补取操作、补取者、回声之前的一步）与记录读取（`Stream.records`：操作、读者、按身份读与按身份分页两个函数），校验与 Go 相同（水位流必须声明记录读取、补取者都在读者里，水位流上的事件必须列出主题）；`be.source.v1.WatermarkService/Pull`（核对位置上的行、按分区写回声——`Producer.insert`——用转发器的编号代码编号、每页 500、页标记绑定实例与纪元、声明谁作答）；`be.source.v1.RecordService` 的 `Read`、`Snapshot`（一次读取一个 REPEATABLE READ 事务，`TxOptions.snapshot`；大记录走凭证）；宿主按流的声明注册两个服务。消费一侧不在首批（A164），`features.json` 把 P9.19–P9.29、P9.34、P9.35 与 P9.33 的消费者核对写成待做。
- **测试**：与 be-sdk-go 同名的 12 个集成测试（另加“一次读取只看一个快照”）与 14 个拉取核对向量；实现先于测试写成，所以做了 11 处改坏，全红。
- **探针**：Python 探针 3.2.47：`_wm` 流（2 个分区，补取 `<前缀>.pull`、记录读取 `<前缀>.read`，补取者与读者是全部探针与套件），写入带 `"watermark": true` 时发到它、主题 `probe:<身份>`；迁移 `0008_watermark_records`。套件 1.0.70 的水位来源剖面对两种探针都跑，Python 探针“符合”（CK-WM-01…03）。
- **没有做的**：推演没有加水位的崩溃点（推演的成员不是水位来源；水位的消费一侧不在首批，来源一侧的回声写入与编号由剖面与 SDK 测试覆盖）。

## T8 的结果（2026-11-07）

- **be-sdk-python a57**，分三段做、各自先过测试与改坏检查再合起来发：
  - 证据（`besdk/evidence`，P12.9–P12.23）：意图在业务事务之前交证据存储（2 秒），不收就进告警渠道，再不行记双通道失效与它自己的一般记录；结论与一般记录随业务事务写变更历史（提交序号在计数行锁下分配）；`be.evidence.transfer` 是 SDK 自带的单例作业，恢复阶段里（冻结之外）是宿主的循环；属主的重放 `ReplayService`（重新执行、已体现、悬空、不支持、推迟，恢复组之外的只核对）。
  - 运行档案（`besdk/runprofile`，P12.1–P12.8、P12.24–P12.27）：对象锁合规模式、条件写入、按类别的保留期、签名与证书链；读回时按接收时刻对信任材料历史核对（沿双签的轮换、吊销与偏差、写入者就是签名证书的身份）；恢复代次的当前值与推进；告警渠道（运行档案一份、webhook 一份，互不等待）。是声明了 `evidence` 的组件的告警渠道。SDK 的 SigV4 改成能签任意请求。
  - 对外命令（`besdk/extcmd`，第 13 章）：状态表与重发截止（纯函数，对向量）、命令的写入与作业 `be.extcmd.process`（认领先提交再发、不可撤回的先交发出记录、结果不明先查、人工登记）、只查询模式、恢复阶段里 verifying 与 read_only 的只查询循环、整套恢复第 7 步的匹配（纯函数，对向量）与 `ReconcileService`。组件定义加 `evidence`、`replay`、`external_commands`、`recovery`。
  - 补了一处 SDK 的缺口：协议之外的错误答复只把状态码写在消息里，适配器分不出 404、429、422；现在抛 `StatusError`，并有 `status_of`、`not_sent`（Go 有 `calls.StatusError`）。
- **测试**：与 be-sdk-go 同名的集成测试（证据 7、运行档案 5、对外命令 10）与向量（证据摘要 4、运行档案 15、信任历史 12、对外命令 35）；恢复阶段的测试加了证据转运（去掉宿主循环就红）。实现先于测试写成，改坏 35 处（证据 12、运行档案 12、对外命令 11）：最终 34 处红，其中 3 处是补了测试之后才红——运行档案的“接受签名”“吊销者受信”原来只有抽象向量测到，补了证书上的单元测试；人工登记“只对 manual”补了一句断言；对账里“manual 提前返回”的一处是等价改动（只多写了故障时刻，P13.12 本就要求没对上的都写）。测试部署加了证据存储的替身（`EvidenceService`）与 `ca()`。
- **一次误报**：整套集成测试里转发器的计时测试失败一次，当时维护者另一个项目的虚拟机把负载推到 16；安静后 a57 与 a56 交替各跑 5 次全过，不是这次的改动。
- **探针**：Python 探针 3.2.48 有了付款（适配器经 SDK 的 HTTP 客户端，用 `status_of`、`not_sent` 分类；时间窗列出给第 7 步用），声明 `<前缀>.pay`、`<前缀>.recover`；`EXTERNAL_COMMANDS_QUERY_ONLY` 改由 SDK 加上。套件 1.0.71 的对外命令剖面对两种探针都跑，Python 只有两个变体，最后一段把第一个换成不可撤回再起。测试部署有了证据存储之后，“这里没有证据存储”的前提不再成立：不可撤回一段改为先关证据存储（不发）、再开（发出记录先到、才付款），多覆盖了正向的一半。`make probes` 197 全过。
- **推演**（a58：对外命令的 6 个崩溃点；每个订单在同一事务里另请求一笔付款，外部系统是不去重的表）：30 分钟 5050 个订单、89 次强杀、23/23 个崩溃点、0 个问题；15 笔付款进了 `manual`，都是认领与发出之间崩溃、外部一次也没收到（`t8/sim.log`）。a58 不改行为（崩溃点平时不做事），部署的成员留在 a57。
- **连锁**：`infra/print` 3.0.21，`erp/billing`、`be/go-core`、`be/py-render` 经 `python-cascade.sh`（SDK a57、探针 3.2.48）。
- **留给后面的**：Python 探针仍声明运行档案与转层的键而不读（Go 探针的归档要它们，A144 的这一半随 T10 的转层去掉）；推演里证据的崩溃点（意图、结论）没有加：推演的成员不写证据，T9 的 `infra/print` 也不写，等第一个写证据的 Python 组件。

## T9 的结果（2026-11-07）

- **be-sdk-python a59**：整套恢复的核对 `be.recovery.v1.CheckService`（`besdk/recovery`）：`Check`（SDK 自带的投影、消费者纪元、审计积压三项与组件登记的检查，每次读都在总是回滚的事务里，跑不起来的答 `unprovable`），`Present`（按组件登记的对象存在问题答 `present`、`older`、`absent`；没登记的类型答 `CAPABILITY_UNSUPPORTED`），`Numbers` 与 `AdvanceNumbers`（连续单号的已用最大值，只提不降，跨过的空号由属主在同一事务作废；`besdk/db/docno.py` 补了 `continuous_maxima`、`raise_continuous`）。和 Go 一样，有数据库的成员都要声明 `Definition.recovery`；SDK 自己的测试里带数据库的成员因此都接上了测试部署的服务身份与操作（`besdk.testing.recovering`）。
- **测试**：与 be-sdk-go 同名的 3 个集成测试，改坏 8 处全红；“没声明恢复操作起不来”一个。
- **顺带查出、修好的**：`EnvSource` 读文件不关；测试部署的 JWKS 服务器不关监听套接字；启动器在开端口之前退出时不收拾已建的系统面与出站通道；`test_ahead_and_beyond_the_retention` 假定 6 个随机事件里分区 0 至少分到两个（约九次一次只分到一个，T9 的整套运行里撞上两次），改为一直发到两个分区都有两行。
- **注意到但没动**：`test_db_hosting` 的“数据库凭据错误退出”在 pytest 里结束时打出 `Error in sys.excepthook`（不让测试失败）；同样的路径在 pytest 之外跑，退出干净。修了上面三处之后仍在，像是 pytest 的事件循环收尾与 gRPC 对象的回收顺序。
- **`infra/print` 3.0.22**：声明 `infra.print.system.recover`，模板按当前版本答“还在不在”（审计的模板编辑以它设成当前的版本为目标）；集成测试以恢复工具的身份问、以别的组件的身份被拒。套件 `prepare.py` 加了这个键（`authz-keys-check` 两向核对）。
- **探针**：Python 探针 3.2.49（a59，`CheckService` 由 SDK 挂上）；套件 1.0.72。
- **留给 T11**：一次整套恢复演练里 Python 成员参加各阶段（门槛 F4）。

## T10 的结果（2026-11-09 至 11-10）

- **T2b（Parquet 库，A168）**：适配初筛筛掉 fastparquet（没有 cp315 的二进制包）与 polars 2.1.0（写不出 UUID 与 JSON 逻辑类型，文件结构与 Go 的不同）；pyarrow 26.0.1 与 duckdb 2.0.0 都合格。实测（`foundations-06-data/t10/parquet-bench/run1`，10 万行，性能模式，8 轮交替，每格 40 次）：写 pyarrow 127 ms、duckdb 182 ms，读回 Python 值 494 对 429 ms，写加读合计持平（波动约 ±10%），取已在用的 pyarrow。套件的第三方读取器 `tierread.py` 也用 pyarrow：读写独立性由 Go 写、pyarrow 读的那一半保留。
- **T2c（CPU 重活在哪算，A169）**：实测（`foundations-06-data/t10/t2c-bench/run1`、`run2`，2 万行，性能模式，8 轮交替）：线程让同一事件循环的请求最多等约 10 ms；工作进程在封存与复制上多花 18–20% 的时间与 CPU、最坏的等待不更好；读取整列一次转换时线程的 p99 等待 34 ms，改成每 1024 行一批后 11 ms、耗时不变。定线程，be-sdk-python a61 的 Parquet 读回分批。kb 推荐工作进程，与实测不一致：反馈与三份实测记录（另一份是第 5 项的写屏障）在 kb PR #71。
- **T10a 完成**：`besdk/tiering/rows.py`、`manifest.py`、`plan.py`，向量 tier-digest 17、tier-manifest 2、tier-plan 21 全过（a60）。
- **T10b、T10c 完成**（a60）：目录、封存、写屏障（`catalog.py`、`member.py`、`barrier.py`）；复制、对象存储、Parquet、发布、释放（`store.py`、`parquet.py`、`transfer.py`、`release.py`），集成测试：封存 5、转层 5、释放 1。
- **T10d 完成**（2026-11-09，a60）：`reads.py`、`reroute.py`、`holds.py`、`destroy.py`、`erase.py`、`history.py`、`check.py`、`routes.py`；`authz.Subject.decider`；`transfer.Passthrough`。照 Go 移植的集成测试 47 个全过（reads 5、reroute 4、destroy 3、erase 5、export_erasure 1、history 8、check 1、cleanup 1、consistency 1、moved 3、nested 2，加 T10b/c 的 11 与启动器的 2）；一次就全绿，抽三处变异（擦除不置空、销毁决定不锁 hold 表、历史读取不判可见）都被抓到。崩溃点的钩子是同步的：moved 的两个测试在钩子里用线程开自己的事件循环与连接扮演另一个写入者或请求。
- **宿主接线完成**（同上）：`Definition.tiering`；`migrate` 入口装写屏障（`migrate.execute`，对应 Go 的 `MigrateConfig.Exec`）；宿主建目录、登记 8 个转层作业与它们在恢复阶段的规则、从运行档案读最近的备份、标准路由、模块的阻断（`tiering(registry)`）、销毁与擦除的重放、恢复核对排在组件自己的之前；`test_sdkjobs` 原来只认字面量的作业名，漏了用常量命名的 `be.tiering.erase`、`be.tiering.export`，改成也解析模块级常量；`features.json` 的 tiering 改为 implemented（P15.23 与 Go 一样待定）。
- **探针的归档与转层剖面**（2026-11-09）：Python 探针 3.2.50 加数据类别 `probe.archive`（`probe_py/archive.py`、迁移 `0009_archive`、两条路由，与 Go 探针的 `archive.go` 相同），原来为清单对齐而声明的运行档案与转层的键改由 SDK 读，生成的 `configSchema` 逐字不变；套件 1.0.73 的转层剖面加 Python 这一对（py 走对象存储、py2 走温层），第三方读取器算出的摘要等于封存的（门槛 G2、G3）。`make probes` 里事件剖面 CK-EV-02 的 pgqueue-py 格偶发“检查失效：StopIteration”，单独重跑通过：自检的变异在长事务所在分区没有先提交的行时崩溃，把裁判的“重跑”藏住了；套件 1.0.73 让变异在找不到可交换的行时不改（裁判照常报原因）。
- **推演**（2026-11-09）：`make simulation-tiering`（`tests/sim/test_tiering_simulation.py`、副本 `tests/sim/tierchild.py`），照 Go 的 `tiering/sim_test.go`：两个成员一个走对象存储、一个走温层、中途互换；四个副本（两个承载两个成员）轮流在 30 个崩溃点结束自己、不时被杀；父进程写、改、关闭、擦除（请求与排队的重做）、保全、记备份、按键读并对照。30 分钟一轮通过（门槛 G4）：23808 份文档、13683 份副本、353 次崩溃、22 次强杀、失败 0，没有撞出缺陷；日志 `foundations-06-data/t10/sim/sim-30min.log`。
- **发布**（2026-11-09）：be-sdk-python a60（SDK 单元 390、集成 212 全过），Python 探针 3.2.50、套件 1.0.73，`infra/print` 3.0.23，级联到 `erp/billing`、`be/go-core`、`be/py-render`（`python-cascade.sh`）。
- **a61 的级联**（2026-11-10）：be-sdk-python a61（单元 391、集成 212 全过），探针 3.2.51、套件 1.0.74（`make check` 168、`make probes` 198 全过），`infra/print` 3.0.24，`erp/billing`、`be/go-core`、`be/py-render` 再升一次。


## T11 的设计（2026-11-10，AI 定，待复核）

- **两个真机格**（`experiment-cells/T6-S`、`T6-H`，脚本 `foundations-06-data/t11/run.sh` 与 `tier.py`；全部组件取现行发布：be-sdk-go alpha.119、be-sdk-python a61）：
  - T6-S：全部单跑，`infra/print` 3.0.24 与 Python 探针 `py` 3.2.51 各自一个容器，探针的归档走对象存储；
  - T6-H：`be/go-infra`、`be/go-core` 按 H2 拆分，`be/py-render` 3.0.51 在一个 Python 进程里承载 `infra/print` 与探针 `py2`（归档走温层）。
  - 每格：从空库建到 L3（`infra/print` 渲染发票）；探针造一份 400 天前关闭的归档与一份未关闭的，等探针自己的作业封存、复制、发布，读回比对；记一次备份、让释放到期，等释放、核对在线行已删、再读回；在部署网络里经 `be-ops recover verify-calls` 调 `infra/print` 与探针的恢复核对（全部 `pass`，探针有 `be.tiering`）；最后跑套件的核心剖面（`cells profile`：探针与外壳各一份报告，并停下格）。
  - 套件里只驱动 Go 的剖面（事件、后台工作、水位来源、对外命令、转层）不在格里重跑：它们由套件自己的部署跑（`make probes`，各任务已对 Python 通过），格里的“套件剖面”是核心剖面，它是唯一按格（单跑与外壳）出报告的。
- **整套恢复演练**（门槛 F4；格 `T6-R`，T6-H 的布局，探针 `py2` 付款到套件的假支付系统；脚本 `t11/drill.sh`）：建格到 L3，T 之前付一笔 `r-before`；T 之后再跑一遍 L3、付 `r-after`、探针写一行；故障是杀掉 Python 外壳；然后 `be-ops recover` 第 1–10 步。要看到：每次换阶段全部成员都报出该阶段、没有成员因“没有恢复模式”被停下；冻结时两个 Python 成员的用户面答 `MAINTENANCE`；第 7 步对探针的付款下结论（`r-before` 对上、`r-after` 只在外部）；第 8 步 `infra/print` 与探针的核对通过；表回到 T；开放之后 L3 再跑一遍。第 4 项演练的八个场景是 Go 成员的，这里不重做。
- **途中改的**：套件 1.0.75——格给每个探针授予付款（原来只给 Go，A144 在 T8 已去掉）；单跑的探针声明 `RECOVERY_PHASE` 时接上共享变量（Go 3.2.50、Python 3.2.43 起声明，之前的格里单跑的探针都早于它，T6-S 第一次建格时撞到）。

## T11 的结果（2026-11-10）

- **两格**（`foundations-06-data/t11/summary.txt`，平衡电源模式，正确性运行）：T6-S 建格到 L3 193 秒，T6-H 281 秒；探针的归档单元 S 在对象存储、H 在温层，发布后与释放后读回都是 0 处差异，释放后已关闭的归档在线行为 0；`be-ops recover verify-calls` 调 `infra/print`（`be.projections`、`be.audit_backlog`）与探针（另加 `be.consumer_epoch`、`be.tiering`）全部 `pass`；核心剖面：T6-S 的探针，T6-H 的探针与 `be/go-infra`、`be/go-core`、`be/py-render` 都“符合”（报告在各格的 `reports/`）。
- **演练**（`t11/drill/summary.txt`）：故障是杀掉 `be/py-render`；冻结时它以 `frozen` 重新起来，此后每次换阶段 13 个成员都报出该阶段，没有一个被停下；冻结时探针与 `infra/print` 答 `MAINTENANCE`（503）；第 7 步：`r-after` 判为只在外部（T 之后付的，随恢复丢失；假支付系统收过 1 次），`r-before` 在 T 之前已完成、不列；第 8 步两个成员的核对全过；T 之后改变的 19 张表恢复后 0 张与 T 不符（Python 一侧是探针的 `probe_writes`）；`infra/print` 的模板与 T 时相同；从宣布到开放 608 秒；开放后 L3 再过。脚本里原写的“r-before 对上”是我的预期错了（它在 T 时已是终态），改正了说明，原始输出保留原样。
- **途中**：失败的三次在 `t11/attempts/`（`NOTE.txt`）：套件少了单跑探针的 `RECOVERY_PHASE`（1.0.75 修，加了测试，还原修改时红）与付款的授予（演练里 Python 探针的付款证明）；两处是我的脚本漏导出变量。
- **注意到但没动**：恢复数据库这一步用了 527 秒（第 4 项 T13e 是 73 秒），备份 183 秒（原 131 秒）：`pg-backup.sh` 备份与恢复的是整个实例，开发机上的实例里现在有 `brickkit_db` 1.4 GB、`be_sdk_test` 1 GB、`be_experiment` 0.8 GB 和第 13 步留下的 `be_e6_*` 等库，时间随整个实例增长，与 Python 成员无关。生产里一个实例只放一个部署的库；开发机上要不要清掉旧的测试库，留给收尾时提。

