# 第 6 项的门槛核对表

门槛：同一剖面两种语言都通过（[计划](../foundations-06-python-plan.md)）。每行一条要证明的事，“状态”写测试名或证据；“未做”的行写着由哪个任务做。与 Go 一样不在剖面里的（要第二个副本或确定的打断，第 1 项移到以后的 CK-EV-04、CK-EV-10、CK-WK-05、CK-WK-03 的接管一半，CK-WM-04…10 的消费一侧）对 Python 也不在，各自的去处不变。

## A. 已经两边都跑的剖面（换了 SDK 后照样通过）

| 行 | 要证明 | 任务 | 状态 |
| --- | --- | --- | --- |
| A1 | 核心剖面（`profile/checks.py`：CK-CF-03、CK-LC-08、10、12、14、CK-DB-09、CK-EV-09、CK-OBS-01…05）对 Python 探针单跑与外壳 | T3 | 有：套件 1.0.66 的 `make probes`（192 个全过，Python 探针 3.2.43 在 be-sdk-python a52 上，`tests/test_profile.py`） |
| A2 | 身份剖面 CK-ID-01…06 对 Python | T3 | 有：同上（`tests/test_identity_profile.py`） |
| A3 | 授权剖面 CK-AZ-01…05 对 Python | T3 | 有：同上（`tests/test_authz_profile.py`） |
| A4 | Python SDK 已实现的能力对现行协议的向量全过（协议副本换到现行，`make protocol-check`） | T3 | 有：a52 的协议副本是 alpha.116；`make test` 176 个、`make test-integration` 94 个全过；补上的是错误原因 `RECORD_SEALED`（含 `BE001`）与 `MAINTENANCE` |

## B. 事件（第 06 章）

| 行 | 要证明 | 任务 | 状态 |
| --- | --- | --- | --- |
| B1 | CK-EV-01 回滚没有发件行 | T5 | 有：套件 1.0.68 的事件剖面对 Python 探针 3.2.45（be-sdk-python a54）在 JetStream 与 PostgreSQL 队列上都“符合”（`tests/test_events_profile.py`） |
| B2 | CK-EV-02 位置连续、长事务晚编号 | T5 | 有：套件 1.0.68 的事件剖面对 Python 探针 3.2.45（be-sdk-python a54）在 JetStream 与 PostgreSQL 队列上都“符合”（`tests/test_events_profile.py`） |
| B3 | CK-EV-03 恢复代次推进后新纪元 | T5 | 有：套件 1.0.68 的事件剖面对 Python 探针 3.2.45（be-sdk-python a54）在 JetStream 与 PostgreSQL 队列上都“符合”（`tests/test_events_profile.py`） |
| B4 | CK-EV-05 补发保留内的行仍在 | T5 | 有：套件 1.0.68 的事件剖面对 Python 探针 3.2.45（be-sdk-python a54）在 JetStream 与 PostgreSQL 队列上都“符合”（`tests/test_events_profile.py`） |
| B5 | CK-EV-06 摘要不符的凭证检查 | T5 | 有：套件 1.0.68 的事件剖面对 Python 探针 3.2.45（be-sdk-python a54）在 JetStream 与 PostgreSQL 队列上都“符合”（`tests/test_events_profile.py`） |
| B6 | CK-EV-07 跳数上限（探针的 `emit`） | T5 | 有：套件 1.0.68 的事件剖面对 Python 探针 3.2.45（be-sdk-python a54）在 JetStream 与 PostgreSQL 队列上都“符合”（`tests/test_events_profile.py`） |
| B7 | CK-EV-08 投递两次、效果一次 | T5 | 有：套件 1.0.68 的事件剖面对 Python 探针 3.2.45（be-sdk-python a54）在 JetStream 与 PostgreSQL 队列上都“符合”（`tests/test_events_profile.py`） |
| B8 | CK-BUS-09 运输按保留删除 | T5 | 有：套件 1.0.68 的事件剖面对 Python 探针 3.2.45（be-sdk-python a54）在 JetStream 与 PostgreSQL 队列上都“符合”（`tests/test_events_profile.py`） |
| B9 | CK-BUS-10 运输晚到时等、一直没有时 0 退出、被拒 78 | T5 | 有：套件 1.0.68 的事件剖面对 Python 探针 3.2.45（be-sdk-python a54）在 JetStream 与 PostgreSQL 队列上都“符合”（`tests/test_events_profile.py`） |
| B10 | 上面 B1–B9 在两种运输（JetStream、PostgreSQL 队列）上都跑 | T5 | 有：套件 1.0.68 的事件剖面对 Python 探针 3.2.45（be-sdk-python a54）在 JetStream 与 PostgreSQL 队列上都“符合”（`tests/test_events_profile.py`） |
| B11 | 补发 `ResendService`（P6.38）与消费者库回退后的补发（P6.36、P6.37、P6.39、P6.40）：SDK 测试 | T5 | 有：SDK `test_progress`（向量 `inbox-progress`）、`test_resend_integration`、`test_redelivery_integration`；改坏 14 处全红（`foundations-06-data/t5/mutants-t5.txt`；第一次有一处活下来：两个订阅的进度相同，补成一个落后两步）。读模型按快照修复不在首批（A164），`features.json` 写明 |

## C. 后台工作（第 07 章）

| 行 | 要证明 | 任务 | 状态 |
| --- | --- | --- | --- |
| C1 | CK-WK-01 回滚没有工作项；接管后 `operation_id` 不变 | T4 | 有：套件 1.0.67 的后台工作剖面对 Python 探针 3.2.44（be-sdk-python a53）“符合”（`tests/test_work_profile.py::test_the_probe_conforms_to_the_work_profile[py]`）；SDK `test_work_integration::test_identities_and_the_rollback` |
| C2 | CK-WK-02 租约到期被接管，代次加一 | T4 | 有：套件 1.0.67 的后台工作剖面对 Python 探针 3.2.44（be-sdk-python a53）“符合”（`tests/test_work_profile.py::test_the_probe_conforms_to_the_work_profile[py]`）；SDK `test_a_taken_over_holder_commits_nothing` |
| C3 | CK-WK-03 恢复代次推进后旧认领失效 | T4 | 有：套件 1.0.67 的后台工作剖面对 Python 探针 3.2.44（be-sdk-python a53）“符合”（`tests/test_work_profile.py::test_the_probe_conforms_to_the_work_profile[py]`）；SDK `test_a_taken_over_holder_commits_nothing`（推进恢复代次后旧认领提交被拒） |
| C4 | CK-WK-04 停止时释放租约 | T4 | 有：套件 1.0.67 的后台工作剖面对 Python 探针 3.2.44（be-sdk-python a53）“符合”（`tests/test_work_profile.py::test_the_probe_conforms_to_the_work_profile[py]`）；SDK `test_stop_gives_the_lease_and_the_attempt_back` |
| C5 | CK-WK-06 local 作业效果只有一次 | T4 | 有：套件 1.0.67 的后台工作剖面对 Python 探针 3.2.44（be-sdk-python a53）“符合”（`tests/test_work_profile.py::test_the_probe_conforms_to_the_work_profile[py]`）；SDK `test_a_local_effect_happens_once_after_a_crash` |
| C6 | CK-WK-07 非幂等调用发出后崩溃转 paused | T4 | 有：套件 1.0.67 的后台工作剖面对 Python 探针 3.2.44（be-sdk-python a53）“符合”（`tests/test_work_profile.py::test_the_probe_conforms_to_the_work_profile[py]`）；SDK `test_a_non_idempotent_call_is_never_sent_twice` |
| C7 | CK-WK-08 退避重试与死信 | T4 | 有：套件 1.0.67 的后台工作剖面对 Python 探针 3.2.44（be-sdk-python a53）“符合”（`tests/test_work_profile.py::test_the_probe_conforms_to_the_work_profile[py]`）；SDK `test_retries_then_dead_with_its_dead_letter` |
| C8 | CK-WK-09 singleton 换持有者后从已提交的进度继续 | T4 | 有：套件 1.0.67 的后台工作剖面对 Python 探针 3.2.44（be-sdk-python a53）“符合”（`tests/test_work_profile.py::test_the_probe_conforms_to_the_work_profile[py]`）；SDK `test_a_singleton_continues_from_its_committed_progress` |
| C9 | CK-WK-10 清理不删未到保留期的、dead、paused | T4 | 有：套件 1.0.67 的后台工作剖面对 Python 探针 3.2.44（be-sdk-python a53）“符合”（`tests/test_work_profile.py::test_the_probe_conforms_to_the_work_profile[py]`）；SDK `test_work_integration`（清理随 `be.work.cleanup`）与剖面的 CK-WK-10 |
| C10 | SDK 自带的作业都被宿主登记、都有恢复阶段的规则（照 be-sdk-go 的 `TestTheHostRegistersEverySDKJob`） | T4 | 有：`test_sdkjobs`（宿主登记每个造作业的函数、每个 `be.` 作业都有恢复规则、多一条少一条都失败；删掉一个登记会红）；`test_recovery_phases_integration`（各阶段不跑作业，改坏会红） |
| C11 | 幂等键（P4.21–P4.25，A164）：向量 `idempotency`、并发同键只执行一次、清理作业 `be.idempotency.cleanup` | T4 | 有：`test_idem`（向量 22 个）、`test_idem_integration`（重放、换请求被拒、并发同键只执行一次、失败不留、过期重新认领、清理只删过期） |
| C12 | 分区维护（P5.21–P5.23，A164）：声明的表按月预建，SDK 自带作业 | T4 | 有：`test_partitions_integration::test_the_job_keeps_the_months_ahead`（运行角色经作业补上缺的分区、脱离的分区使维护失败） |

## D. 水位来源（第 09 章的来源一侧）

| 行 | 要证明 | 任务 | 状态 |
| --- | --- | --- | --- |
| D1 | CK-WM-01 没列出的补取者被拒；补取答出来源的声明 | T7 | 有：套件 1.0.70 的水位来源剖面对 Python 探针 3.2.47 “符合”；SDK 测试 `test_only_the_declared_pullers_may_pull` |
| D2 | CK-WM-02 回声与长事务、分页 | T7 | 有：剖面“符合”；SDK 测试 `test_a_pull_echoes_after_the_changes_before_it`、`test_a_pull_pages_with_the_echo_on_the_last_page` |
| D3 | CK-WM-03 连续位置上的行被换掉、超出计数、已清理、别的纪元（SK17） | T7 | 有：剖面“符合”；向量 `watermark-pull-check` 14 例；SDK 测试 `test_the_pull_checks_the_row_at_the_position` |
| D4 | 来源的记录读取（P9.30–P9.33）：`Read` 每个身份一项、`Snapshot` 按身份分页、页标记绑定实例与纪元、声明谁作答；水位流必须声明、补取者都在读者里 | T7 | 有：SDK 测试 7 个（与 Go 的同名，另加“一次读取只看一个快照”：去掉 REPEATABLE READ 就红）；套件的剖面不测记录读取（Go 也是 SDK 测试证明） |

## E. 证据与对外命令（第 12、13 章）

| 行 | 要证明 | 任务 | 状态 |
| --- | --- | --- | --- |
| E1 | 对外命令剖面（`tests/test_external_profile.py`：结果不明先查、按去重与否决定重发、不重复付款、不可撤回的没有发出记录就不发）对 Python 探针 | T8 | 有：套件 1.0.71 对两种探针都跑，Python 探针 3.2.48 “符合”；不可撤回一段先关证据存储（不发）、再开（发出记录先到、才付款）——测试部署有了证据存储，原来“这里没有证据存储”的前提不再成立 |
| E2 | 证据写入与重放（第 12 章）的 SDK 测试；运行档案的读写对向量 | T8 | 有：be-sdk-python a57：证据 7 个集成测试 + 4 个摘要向量 + 恢复阶段里的转运；运行档案 5 个集成测试（真实对象存储的对象锁）+ 27 个向量 + 证书上的信任历史 2 个；改坏 24 处全红，其中 2 处是补了证书上的测试之后才红（见计划“T8 的结果”） |
| E3 | 两个探针的清单相同，A144 的例外去掉 | T8 | 有：Python 探针 3.2.48 读付款的键，`EXTERNAL_COMMANDS_QUERY_ONLY` 由 SDK 随对外命令加上；`make check` 的清单测试过；3.2.50 起运行档案与转层的键由 SDK 随 `Definition.tiering` 读，探针不再自己声明，生成的 `configSchema` 与原来逐字相同 |

## F. 恢复（P1.23、第 14 章）

| 行 | 要证明 | 任务 | 状态 |
| --- | --- | --- | --- |
| F1 | P1.23 各阶段的运行：用户面答 `MAINTENANCE`，转发、订阅、作业（含 SDK 自带的）按阶段停或运行：SDK 测试 | T3 | 有（用户面、转发、订阅、审计转运、就绪与自述、外壳）：`test_recovery_phases_integration::test_the_recovery_phases`、`test_shell::test_a_shell_in_recovery`、`test_a_member_without_a_phase_runs_in_the_shells_phase`；改坏 4 处（冻结时照样转发、照样订阅、忽略 `read_only_open`、外壳端口不带阶段）都红；作业一半随 T4 |
| F2 | `CheckService`（P14.1）与 `ReconcileService` 的登记、只许恢复工具：SDK 测试；探针的 `<前缀>.recover` | T9 | 有：be-sdk-python a59 的 `CheckService`（3 个集成测试：检查、对象是否还在、单号；改坏 8 处全红），有数据库的成员都要声明 `Definition.recovery`（`test_a_member_with_a_database_declares_its_recovery_operation`）；`ReconcileService` 随 a57（T8）；只许恢复工具由 `infra/print` 的集成测试核对（别的组件答 `PERMISSION_DENIED`）；Python 探针 3.2.48 起声明 `<前缀>.recover`，3.2.49 在 a59 上答 `CheckService` |
| F3 | `infra/print` 的恢复阶段与核对（模板按版本答“还在不在”） | T9 | 有：`infra/print` 3.0.22（操作 `infra.print.system.recover`，`test_a_full_recoverys_checks`：当前版本答还在、更高的答更低、不存在的答不在、别的组件被拒）；恢复阶段在 3.0.18 起声明 `RECOVERY_PHASE`，阶段行为由 SDK（T3） |
| F4 | 一次整套恢复演练里 Python 成员参加各阶段，不被停下 | T11 | 未做 |

## G. 转层（第 15 章）

| 行 | 要证明 | 任务 | 状态 |
| --- | --- | --- | --- |
| G1 | 规划、摘要、清单的向量对 Python 全过（第 5 项门槛 G1 的 Python 部分） | T10a | 有：be-sdk-python a60，tier-digest 17、tier-manifest 2、tier-plan 21 全过 |
| G2 | 转层剖面（`tests/test_tiering_profile.py`）对 Python 探针的归档 | T10 | 有：套件 1.0.73 的 `test_the_python_probe_tiers_its_archive`（py 走对象存储、py2 走温层；封存、复制、发布后按键读出的根与每层子表与在线时相同，未关闭的留在在线）通过 |
| G3 | 第三方读取器（`tierread.py`）读 Python 写的冷层，算出同一个摘要 | T10 | 有：同上的测试里，两条路线上读取器从清单与 Parquet 对象（或温层的行）算出的摘要等于封存时的、读出的行相同。注意：Python 写 Parquet 与读取器都用 pyarrow，读写独立性由 Go 探针那一半保留 |
| G4 | 长时间推演里加转层的崩溃点，终态一致 | T10 | 有：`make simulation-tiering`（照 be-sdk-go 的 `tiering/sim_test.go`）30 分钟：23808 份文档全部按写入读回或按规则销毁，13683 份副本校验通过，恢复核对通过，没有卡住的工作项，30 个崩溃点全部到过（353 次崩溃、22 次强杀），失败 0（`foundations-06-data/t10/sim/sim-30min.log`） |

## H. 推演、真机格与转来的

| 行 | 要证明 | 任务 | 状态 |
| --- | --- | --- | --- |
| H1 | 长时间推演（第 5 项复盘 S1）：Python 多副本、外壳两个成员，崩溃点、终态核对，30 分钟一轮通过 | T6 | 有：第一轮撞出 P6.20 的缺口（A167，两种 SDK 一起修），修复后 30 分钟一轮通过：4309 个订单、89 次强杀、17/17 个崩溃点、0 个问题（`t6/sim.log`） |
| H2 | 真机格：Python 成员单跑与进外壳两格，业务链 L3 与套件剖面；新脚本先在开着的格上逐步跑（S4） | T11 | 未做 |
| H3 | SF27 的 Python 部分：互通测试的 Go 小程序换上现行的 Go SDK | T3 | 有：三个小程序换到 be-sdk-go alpha.117（协议 alpha.116，`test_the_go_interop_helpers_pin_the_same_protocol`）；`goevents` 按 Go 现行的要求补了恢复操作、补发操作与授权定义，测试给它 `world` 的服务身份；互通与安全的集成测试 9 个全过 |
| H4 | `be-sdk-python` 的 `AGENTS.md`（分层 L7 转来） | T3 | 有：`AGENTS.md` 与 `CLAUDE.md`（a52） |
| H5 | Python 成员只用一个 `be-sdk` 版本的检查（pin-check） | T3 | 有：`pin-check.py` 的 `one_python_sdk`（3 个单元测试）；对现状报出 `infra/print` 停在 a48（SF29），T3 的连锁发版后为 0 |
| H6 | `features.json` 如实：做了的“已验证”，范围外的“未实现”且写明理由（T2a） | T12 | 未做 |
