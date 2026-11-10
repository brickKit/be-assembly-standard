# 重建阶段的工作区

> 2026-10-15 建立：终局设计已冻结并迁成正式文档（`docs/zh/`），设计阶段的工作区归档在 `archive/design-2026-10/`。本目录放重建阶段仍在进行的工作；工作结束后整体归档。新会话先读“现在在哪里”。

## 现在在哪里

- **代表部署实验（D41）做完了**（2026-10-17 至 11-02）。结论在[实验报告](experiment-report.md)（最后是“结论汇总”与“限制与未测”），已提炼进正式文档：[部署模式](../../docs/zh/00-overview/guides/deployment-modes.md)、决定 D80（默认有根 Podman，开机实测后由无根改定）与 D81（Podman 上交付用 Quadlet 单元，2026-11-02 复测 BrickKit v1.12.0 之后）与 A112–A114（默认全部单跑、不加连接池代理、NATS；维护者 2026-11-02 复核）、各篇的修订（[第 14 步计划](step14-plan.md)第 3 节）。复盘：[整个实验](retro-experiment.md)、[第 12 步](retro-step12.md)、[第 13 步](retro-step13.md)。
- **现在：按依赖顺序重建其余组件**（维护者 2026-11-10 定）：计划 [components-plan.md](components-plan.md)，13 个组件 C1–C13 与阶段收尾 C14；C0 的仓库动作已执行（维护者 2026-11-10“执行”：7 个旧仓库挪 `legacy/` 并重启 main、`frontend-standard` 改名 `frontend-pc`、注册表追加；新仓库在各自开工时建）。**正在做：C1 `mdm/employee`**：仓库已建（`components/mdm/employee`），子计划 [c1-employee-plan.md](c1-employee-plan.md)，E0（首批范围，AI 定待复核）、E0b（`mdm/org` 3.0.34 的岗位与连锁，格 C1-H 到 L3 全过）已做；E1（设计文档，考设计两份 8/8）已做；**下一步 E2：契约**（用户面、系统面、事件、水位流、权限键；`infra/authz` 要加的系统方法一起定）。
- **底层先行（完成，2026-11-02 至 11-10）**（维护者 2026-11-02 确认进入；[重建计划](rebuild-plan.md)“顺序”第 3 项，路线第 3 步开头）：事务与消息、登录与身份、权限、审计与整套恢复、冷热数据，以及 Python 补到代表组件需要的剖面，逐项做；每项先写计划，做到[实验计划](experiment-plan.md)“实验之后：底层先行”的验证门槛后汇报、维护者确认后进下一项；实验留给各项的待测在重建计划里列着。之后按依赖顺序重建业务组件。
  - **第一项（事务与消息）完成**（维护者 2026-11-03 确认门槛，批准复盘的 K1，A115、A116 复核确认）：证据在[计划](foundations-01-transactions-plan.md)的 T11，复盘在 [retro-foundations-01.md](retro-foundations-01.md)。
  - **第 2 项（登录与身份）完成**（维护者 2026-11-03 看过门槛汇报后说“继续”；范围维护者 2026-11-03 定）：[计划](foundations-02-identity-plan.md) T1–T7 全部完成，门槛表在 T7，复盘在 [retro-foundations-02.md](retro-foundations-02.md)。做出来的：`be-protocol` alpha.53–55（令牌陈旧 P8.25–P8.28、边缘的会话层第 11 章）；`be-sdk-go` alpha.56；`infra/iam-casdoor` 3.0.16；`be-edge` v3.0.0-alpha.2（新仓库，Traefik 插件）；`be-ops` v3.0.0-alpha.1（`features`）；`be-sdk-python` a45（只动测试部署）；`be-acceptance` 1.0.38（身份剖面）、探针 3.2.33；浏览器路径的端到端（`experiment-data/16-05-*`）。待复核：A117、A118、T3 的范围划分（Casdoor 侧的变更归第 3 项）、复盘的 L1。
  - **第 3 项（权限）完成**（维护者 2026-11-05 看过门槛汇报后定“算过”）：[计划](foundations-03-authz-plan.md) T0–T10 全部完成，各任务的经过与验收在计划里；门槛核对在 `foundations-03-data/gate.md`（没测的 3 条、部分的 27 条按它第 6 节的去处留到以后），复盘在 [retro-foundations-03.md](retro-foundations-03.md)（M1–M4 已做）。做出来的（已发布）：`be-protocol` alpha.56–70，`contract-infra-authz` alpha.2–4，`contract-infra-iam` alpha.2，`be-sdk-go` alpha.57–76，`be-sdk-python` a46–a51，`infra/iam-casdoor` 3.0.17–3.0.22，`infra/authz` 3.0.16–3.0.26，探针 3.2.34–3.2.38，套件 1.0.39–1.0.44，外壳到 `be/go-infra` 3.0.49、`be/go-core` 3.0.49、`be/py-render` 3.0.39。A120–A130 维护者 2026-11-04 确认；A131–A134 与复盘的 M3、M4 待复核。
  - **第 4 项（审计与整套恢复）完成**（维护者 2026-11-06 确认门槛，A131–A148 复核确认）：[计划](foundations-04-recovery-plan.md) T0–T13 全部完成，各任务的经过与验收在计划里；门槛核对在 `foundations-04-data/gate.md`（首批没有缺口；门槛之外的已知缺口在它第 5 节），两次门槛演练是 T11 与 T13e（`foundations-04-data/t11/`、`t13e/`），复盘在 [retro-foundations-04.md](retro-foundations-04.md)（R8 写进第 5 项的计划）。做出来的（已发布）：`be-protocol` 到 alpha.96（第 12 章证据与运行档案、第 13 章对外命令、第 14 章恢复核对），`be-sdk-go` 到 alpha.102（全部组件在它上面），`be-ops` 到 alpha.14（`recover` 第 1–10 步、`trust` 签发者），`infra/audit` 3.0.28、`infra/authz` 3.0.38、`infra/iam-casdoor` 3.0.35，外壳 go-infra 3.0.63、go-core 3.0.63，探针 3.2.46，套件 1.0.58；kb PR #66、#68 等审查。
  - **组件代码按业务分层完成**（维护者 2026-11-07 提出并批准铺开；L1–L7 全部完成，2026-11-07）：计划、每一步的结果、考试与做法在 [layout-plan.md](layout-plan.md)，工具与每个组件的流水线在 `dev/rebuild/layout-tools/`；发现的结构问题登记在正式文档的“结构问题登记”（SF01–SF28，待处理的 SF06–SF08、SF10–SF13）。做出来的：12 个组件按业务模块分包、每层一份说明、`itest/` 与测试索引，`make layout-check`（Go 与 Python）进门禁；规则集中（L1b）：`erp/sales` 3.0.40、`erp/billing` 3.0.40、`infra/authz` 3.0.44 的生命周期表，`erp/credit`、`erp/inventory` 3.0.32 改用 SDK 的 `reserve`（维护者定参与方的状态机进 SDK：[reserve-participant-plan.md](reserve-participant-plan.md) R0–R6，be-protocol alpha.116、be-sdk-go alpha.117，全系统换到 alpha.117）；`infra/print` 3.0.15（Python）；真机格 `L6-S`、`L6-H` 从空库起到 L3 全过；L7 结论是 SDK 不拆包，`be-ops` 3.0.0-alpha.17 补了 `AGENTS.md`、升到 alpha.117，pin-check 加“部署的 Go 模块只用一个 SDK 版本”。现在各组件与外壳的版本以组件索引与 `make version-check` 为准。待复核：A160–A163（`docs/zh/02-decisions/09-ai-choices.md`）、生效点不再拆包与 SDK 不拆包（AI 定，计划的 L1b、L7 行）。**留下的**：be-sdk-python 补 `AGENTS.md`、互通测试换上现行的 Go SDK（SF27），都写进第 6 项的计划；`COMPAT.md` 的 Go alpha.117–118、Python a52–a54 两行与向量 `cron-slots` 的补充已随协议 alpha.117 发布。
  - **第 5 项（冷热数据）门槛通过**（维护者 2026-11-07）：计划在 [foundations-05-tiering-plan.md](foundations-05-tiering-plan.md)，T0–T11 全部完成，门槛核对 `foundations-05-data/gate.md` 42 行都是“有”（6 行带转出、写明去处），**下一步：做完 T12 剩下的几项**（见本段末尾）；T10e 真机格（T5-S 单跑、T5-H 外壳）全过，经过在计划“T10e 的结果”；T11 长时间推演第二轮 30 分钟全过（`foundations-05-data/t11a/run2/`），撞出的缺陷与修正在计划“T11 的结果”。这一轮发布：线协议 alpha.111–114（每天的孤儿清理、按主键排序的向量、擦除作废导出、已销毁的从决定起不可见），SDK alpha.116（全部组件统一换上：`sdk-unify.py`，审计 3.0.33、销售 3.0.38 等），`infra/audit` 3.0.32（链校验），`erp/sales` 3.0.37（先问归档），套件 1.0.60–1.0.63（格的冷层与登记表、第三方读取器 `tierread.py`）。统一换到 alpha.116 已完成（11 个组件、Go 探针 3.2.48 与套件 1.0.64、外壳 `be/go-infra` 3.0.66 与 `be/go-core` 3.0.65、`be-ops` alpha.16；`make version-check` 全过）。维护者 2026-11-07：推送（`origin/main` 到 `fdaa021e`），批准复盘的 S1–S6 与 A149–A159；门槛维护者 2026-11-07 确认通过。T12 还剩：S2、S3、S5 已做（复盘表里有经过：be-sdk-go alpha.118 的宿主登记检查；`make authz-keys-check`；测试规范的“生命周期测到终点之后”）；S1、S4 与 SF27 的 Python 部分、be-sdk-python 的 `AGENTS.md` 写进第 6 项的计划（[retro-foundations-05.md](retro-foundations-05.md)）；kb PR #70（这一项的反馈，等审查）；写屏障固定 `search_path` 的代价 2026-11-09 测完（性能模式，两批各 30 对：每行多约 0.57 微秒、插入多约 5%，`foundations-05-data/t12-barrier/night/`），交 kb PR #71（等审查）。A149–A159 维护者 2026-11-07 确认。注意到但没动：满载跑整套 SDK 测试时，启动器的 `TestRecoveryPhases` 有一次 10 秒内没就绪（单独与整包重跑都过）。
  - **第 6 项（Python 剖面）完成**（门槛维护者 2026-11-10 确认）（维护者 2026-11-07 说“现在可以写计划并执行”）：计划 [foundations-06-python-plan.md](foundations-06-python-plan.md)，门槛核对表 `foundations-06-data/gate.md`；T0–T5 已做（T3：be-sdk-python a52 的协议副本 alpha.116 与恢复阶段；T4：a53 的后台工作项、cron、幂等键、分区维护与 SDK 自带作业，Python 探针 3.2.44 的后台工作剖面“符合”；T5：a54 的补发与协议的 gRPC 生成代码，Python 探针 3.2.45 的事件剖面在两种运输上“符合”；T6：Python 长时间推演（`be-sdk-python` 的 `tests/sim`）第一轮撞出两种 SDK 都有的 P6.20 缺口——最后一次投递在处理中途进程退出时消息无声消失——协议 alpha.117 改写 P6.20、A167（待复核），`be-sdk-go` alpha.119（全部 Go 组件、外壳、探针 3.2.51、`be-ops` alpha.18、`be-edge` alpha.4 一起换）与 `be-sdk-python` a55 修好，重跑 30 分钟通过（门槛 H1）；每次 Python SDK 发版后的连锁用 `foundations-06-data/python-cascade.sh`（可带 `CORE_SUBJECT`、`CORE_NOTE`：go-core 先改好的其他成员）。T7：be-sdk-python a56 的水位来源补取与记录读取（来源一侧；门槛 D1–D4），Python 探针 3.2.47、套件 1.0.70。T8：be-sdk-python a57 的证据、运行档案与对外命令（第 12、13 章；门槛 E1–E3），a58 加对外命令的崩溃点、推演加付款（30 分钟通过；a58 不改行为，部署的成员留在 a57），Python 探针 3.2.48 的付款、套件 1.0.71 的对外命令剖面对 Python“符合”。T9：be-sdk-python a59 的整套恢复核对 `CheckService`（有数据库的成员都要声明 `Definition.recovery`；门槛 F2、F3），`infra/print` 3.0.22 的模板按版本答“还在不在”，Python 探针 3.2.49、套件 1.0.72。现在外壳 go-infra 3.0.71、go-core 3.0.77、py-render 3.0.49，`infra/print` 3.0.22，`erp/billing` 3.0.50，Python 探针 3.2.49，套件 1.0.72）；**T10（转层）完成（2026-11-09 至 11-10）**：be-sdk-python a60（转层全部模块、宿主接线、照 Go 移植的集成测试 47 个、`make simulation-tiering` 30 分钟通过）与 a61（Parquet 读回分批），Python 探针 3.2.50–3.2.51（归档）、套件 1.0.73–1.0.74（转层剖面加 Python 一对），`infra/print` 3.0.23–3.0.24，两次级联到 `erp/billing`、`be/go-core`、`be/py-render`；门槛 G1–G4 有；T2b 定 pyarrow（A168）、T2c 定线程且读取分批（A169），实测与 kb 的反馈在 kb PR #71（等审查）。经过在计划的“T10 的结果”。**T11（真机格与恢复演练）完成（2026-11-10）**：格 T6-S、T6-H 从空库到 L3、探针归档转层读回、恢复核对、核心剖面全过，格 T6-R 的整套恢复演练里 Python 外壳被杀后以各阶段参加、没有成员被停下（门槛 H2、F4；套件 1.0.75 修了格配置的两处）；经过在计划的“T11 的结果”。**T12 收尾完成，门槛维护者 2026-11-10 确认（“继续”）**：be-sdk-python a62–a63、be-sdk-go alpha.120 只改文档（部署的仍是 a61 与 alpha.119）；复盘 [retro-foundations-06.md](retro-foundations-06.md) 的 P1–P6 维护者批准、都已做（套件 1.0.76、`experiment-scripts/cellenv.sh`、格脚本失败不关格、开发流程的“核对”、删旧测试库）；COMPAT 第 2 节的两行（Go alpha.119、Python a55–a62 实现 alpha.117）与 `cron-slots` 向量缺的用例留到下次发协议时。下次发协议时：`COMPAT.md` 第 2 节补 be-sdk-go alpha.119、be-sdk-python a55–a62 实现 alpha.117；`cron-slots` 向量补“`none` 且最后一个到期槽早于一分钟”的用例。
  - 挂着的事：
    - 授权成员“写意图之前先查键”：同一个变更键重放时，意图在锁外先写、键的绑定在锁下才查到，留下一条“已取消”的意图（第二遍播种 26 条里 25 条；语义对，浪费证据存储的写入）。改法：写意图之前不加锁先查一次键的绑定。排在授权成员的下一版（第 4 项计划 T7 的 F3-X 一段）。
    - kb PR #67（长任务的门槛改成“预计 5 分钟以上”，一批命令合计）：维护者 2026-11-05 合并并补了一个提交（`6538747c`），已同步到本机。
    - 上层仓库 2026-11-10 推送到 `acd300ff`（维护者下令）；之后的提交以 `git log origin/main..main` 为准。子仓库发布的版本都已推送并打了标签；没有已推送而未发布的。BrickKit 信箱里 FRB-014（代码地图把组件 ID 当路径）等回复。
    - kb PR #61（计划缓存的实测记录与反馈）等 kb 审查；审查意见回来时照 `kb-contribute` 处理。kb PR #63（T5 的空闲轮询与统计检查）已合并。kb PR #64（复盘的反馈：补测的集成测试适合手工定点改坏；故障注入要打到“那一步”、只认故障造成的失败）等审查。kb PR #65（边缘会话层的实测，含真实插件的复测）、#64（又补了“红也要红在那条规则上”）等审查。
    - 注意到但没动：`be-sdk-go` 的 `launcher.TestResponsesAreNotHeldBackOnAKeptAliveConnection` 在 `make test` 的并行负载下偶尔以退出码 1 停止（2026-11-03 一次，单独跑 5 次都过，`foundations-03-data/t3/sdk-go-make-test.txt`）。
    - 移到 T10 的检查（要第二个副本或确定性的打断）：CK-EV-04、CK-EV-02 的两个副本同时编号、CK-WK-05、CK-WK-03 的接管一半；CK-EV-10 进 T8；Python 探针的 `fail`、`hold_ms`、`emit` 与后台工作项随第 6 项补。
    - 变异检查用 `experiment-scripts/mutate.py`（复盘 M2：开跑前核对每处原文、列表不空，记下没编译的，结束时确认还原）。
    - 跑套件的环境：`source dev/rebuild/experiment-scripts/itenv.sh`，再把 `BE_ACC_*` 设成对应的 `BE_SDK_TEST_*`（PG_ADMIN、NATS_URL、S3_URL、S3_ACCESS_KEY、S3_SECRET_KEY）。监视长任务时 `pgrep -f '<命令>'` 会匹配到监视脚本自己（2026-11-03 两个监视因此不退出），盯进程号或用 `pgrep -x`。
- 设计冻结与正式文档迁移已完成（[migration-plan.md](migration-plan.md)）。待复核的 AI 选择：A109（驻留期起始值）、A117、A118（第 2 项 T2）、A131、A132（第 3 项 T7）（A120–A130 维护者 2026-11-04 确认），都在 `docs/zh/02-decisions/09-ai-choices.md`。

### 实验各步

| 步 | 做了什么 | 计划 | 记录 |
| --- | --- | --- | --- |
| 0 | 机制的最小复现（外壳取成员、一个仓库多个组件、全部本机进程、Podman、minikube、两个版本、两个副本、两个 PostgreSQL、有根 Podman、连接池代理） | [实验计划](experiment-plan.md) | 0-01–0-12 |
| 1 | 仓库动作（15 个重启、5 个新建、改名） | [step1-repo-actions.md](step1-repo-actions.md) | — |
| 2、3 | `be-protocol` 子集、Go 与 Python 的 SDK、外壳启动器、探针与一致性剖面 | [step2](step2-plan.md)、[step3](step3-plan.md) | — |
| 4 | 三个外壳、资源采集、负载驱动；D 行的底价与通信细分 | [step4-plan.md](step4-plan.md) | 4-02、4-03、4-04 |
| 5 | 身份、授权、审计与两个契约包 | [step5-plan.md](step5-plan.md)、[契约](step5-contracts.md) | 5-01、5-02 |
| 6、6b | 主数据四个；丰富的种子数据 | [step6](step6-plan.md)、[step6b](step6b-seed-plan.md) | 6-01、6-02 |
| 7 | 交易链五个组件、L3 场景、负载驱动的业务链；文档结构实验 R2 | [step7-plan.md](step7-plan.md) | 7-01 |
| 8 | 套件 A 的 D 行 | [step8-plan.md](step8-plan.md) | 8-01 |
| 9 | 套件 A 的其余 5 行与探针 | [step9-plan.md](step9-plan.md) | 9-01、9-02 |
| 10 | 套件 B（B1–B7）与 LD、LP 的外壳列 | [step10-plan.md](step10-plan.md) | 10-01–10-10 |
| 11 | 套件 C（故障与运维） | [step11-plan.md](step11-plan.md) | 11-01、11-03 |
| 12 | 套件 D（多版本兼容） | [step12-plan.md](step12-plan.md) | 12-01 |
| 13 | 套件 E（多实例与多数据库） | [step13-plan.md](step13-plan.md) | 13-01 |
| 14 | 报告、部署模式说明、设计修订、给 BrickKit 的建议；之后 FRR-023 的复测（真重启三次） | [step14-plan.md](step14-plan.md) | `experiment-data/14-01-reboot/` |

记录在 [experiment-records/](experiment-records/README.md)（索引），原始数据在 `experiment-data/<记录编号>/`，运行脚本在 [experiment-scripts/](experiment-scripts/README.md)，格在 `experiment-cells/`。

### 本目录的其他文件

| 文件 | 内容 |
| --- | --- |
| [rebuild-plan.md](rebuild-plan.md) | 仓库复用、`legacy/` 分支、改名与新建的清单与顺序；每一步动仓库前先列动作请用户确认（改名除外） |
| [implementation-checks.md](implementation-checks.md) | 冻结时列出、交给实现阶段核对的项 |
| [be-protocol-carry.md](be-protocol-carry.md) | 线协议细节的承接清单，重建 `be-protocol` 时逐条重审写入 |
| [migration-plan.md](migration-plan.md)、[migration-map.md](migration-map.md)、[review-migration.md](review-migration.md) | 正式文档迁移的动作、承接表与复查（已完成） |
| [doc-structure-plan.md](doc-structure-plan.md) | 文档结构实验（2026-10-22 至 23，R0–R3 都已完成）；题库在 `dev/routing-tests/` |
| [diagrams-plan.md](diagrams-plan.md) | 文档里的图（2026-10-25 完成：开发文档不放图，客户读的图后补全关系，`make docs-diagrams` 进 `make gates`） |

## 本机的环境

实验与重启测试留下的、以后还会碰到的设置（各自的经过在括号里的记录）：

- **`/etc/hosts` 有 `127.0.0.1 host.docker.internal`**（维护者 2026-11-01，第 12 步 G7）：让本机进程与容器用同一个名字访问对象存储；不要删。
- **无根 Podman 的开机自启**（2026-11-02，`experiment-data/14-01-reboot/`）：linger 已开、`podman-restart.service` 已启用；`~/.config/systemd/user/podman-restart.service.d/wait-network.conf` 让它等网络；`/etc/systemd/system/user@1000.service.d/data-disk.conf` 让用户的 systemd 等数据盘；AppArmor 的 `podman`、`passt` 配置是包里的原样，`usr.bin.pasta` 是原样加 BrickKit 的一条信号规则（enforce）。**AI 的终端在 VS Code 的 snap 里**，那里允许建用户命名空间：查 Podman 的问题、模拟开机或 ssh，用 `systemd-run --user --wait …`；P、LP 两行起格前 `cell-chain.sh` 会先跑 `podman-preflight.sh`。
- **有根 Podman 的开机测试**（2026-11-02，`experiment-data/14-02-rootful-reboot/`，D80 因此改为有根）：测试时装了 root 的 `podman.socket`（组 `docker`，drop-in `be-rootful.conf`、`be-rootful-dir.conf`）、`DOCKER-USER` 的放行规则与开机补回它的 `be-podman-docker-forward.service`、系统的 `podman-restart.service`；测完维护者 2026-11-02 执行了 `rootful/revert-boot.sh` 与 `rootful/revert.sh`，都已还原（`after-revert.txt`）。以后再测有根，重新执行 `rootful/setup.sh` 与 `setup-boot.sh`。
- **Quadlet 单元的复测**（2026-11-02，`experiment-data/14-03-quadlet/`，FRR-025、FRR-024）：格 P9-S-q（无根）与 P9-S-root-q（有根，`rootful/quadlet-up.sh` 由维护者以 root 执行）都已 `down`；无根时临时停用的 `podman-restart` 与等网络的 drop-in 已恢复（`rootless-restored.txt`）；有根装的 `podman-docker-forward.service`、镜像与 `DOCKER-USER` 规则已由 `rootful/quadlet-revert.sh` 还原（`rootful-after-revert.txt`）。有根 Quadlet 格只有 root 能 `up`：`cell-chain.sh` 在 `up-by-root` 一段等，`quadlet-up.sh` 等安装声明写好后自己再 `up` 一次；中断的链用 `FROM=<段名>` 接着跑。**几个格共用一个数据库**：别的格重建过之后，再用一个旧格要先重新建格（`cell-chain.sh` 从头跑），否则授权成员报 `AUTHZ_INSTANCE differs from the instance this database was installed with` 拒绝启动（`14-06-frb013/1-root-up.txt`）。`rootful/frb012.sh <格> <输出目录>` 一次 sudo 测两个身份互相拒绝（FRB-012、FRB-013）。
- **数据盘** `/home/zhijie/data`：Docker 与 containerd 的根、Podman 的存储、Go 与 Python 的缓存都在上面；Docker 与用户的 systemd 都等它挂上。
- **还原过的设置**：维护者 2026-10-29 执行了 `cap/revert.sh` 与 `rootful/revert.sh`（Docker 的 `cgroup-parent` 去掉、`be-cap.slice` 停了；root 的 `podman.socket` 停用、`DOCKER-USER` 清空）。以后再要限内存或有根 Podman，重新执行对应的 `setup.sh`。GNOME 的文件索引忽略 `/home/zhijie/data`（`org.freedesktop.Tracker3.Miner.Files ignored-directories`）。
- **BrickKit**：CLI v1.12.2，本项目装的技能是 v1.12.2（`brickkit skills update`）；`target: podman` 加 `podman: { units: quadlet }` 生成 Quadlet 单元，本项目 D81（维护者 2026-11-02 定）：Podman 上交付用它，compose 只给开发机；`infra/scripts/lib/require-brickkit.sh` 精确要求 v1.12.2（v1.12.1：开机不跑迁移、迁移成功才换组件、换了身份 `up` 报 `DEPLOYED_ELSEWHERE`；v1.12.2：那个拒绝在生成与打印计划之前）；BrickKit 每次发版本机升级后，这一行与它的测试一起改，否则 `make gates` 拦下。v1.11.1 起 compose 下 `target: podman` 生成 `restart: always`，旧格升级后第一次 `up` 会重建每个组件容器；v1.10.3 起 compose 健康检查在启动阶段每秒一次（`start_interval: 1s`），D 行崩溃后的拉起读数在那之后变短，不与之前的比。
- **要查的**：Casdoor 的库导出有 557 MB（第 10 步 B7 切换前导出，已移出仓库），大得反常，推测是多轮测试积下的令牌与记录，要看是哪张表、要不要定期清理（[10-08](experiment-records/10-08-base-in-cluster.md)）。

## 推进方式与停点

以根 `AGENTS.md` 的“推进方式”一行为准（2026-11-02 起是底层先行）：连续推进，每项做完写记录、更新本文件、提交，直接做下一项；只在需要用户决定、需要 BrickKit 配合、仓库的新建改名删除、要维护者本人执行时停下。底层每一项做到验证门槛后停下汇报，维护者确认后进下一项。下面几条是代表部署实验里定下、这一阶段照用的做法。

- **计划的步骤逐条标状态**（第 12 步复盘 I2）：每步计划的“步骤”一节，每条前面标 ✅（做完）或 ⬜（没做），做完一条当场改。交接的剩余清单从没标 ✅ 的条目抄，不凭记忆写。
- **进记录的运行当场存输出**（第 12 步复盘 I3、第 13 步复盘 J3、J4）：结论要写进记录的每次运行（含临时模块、格的副本上的命令、手动发的调用），输出当场写进 `experiment-data/<步>/`，命令写在同一处；只在终端里看过的不算数。记录里的计数与比例用命令从存下的数据算，不手数。停格前先跑 `experiment-scripts/cell-logs.sh`（各运行器已调用；手工停格时自己跑）。
- **测量**：一律在 performance 电源模式下、按小时算；每一轮记下电源模式，运行脚本切到 performance 并在结束时恢复。测量期间不在机器上跑任何测试、编译或剖析（会干扰数字，也会抢端口，4-03 记了一次）。测量取 `be-acceptance` **整个仓库**的快照（只拷 `conformance/` 会缺负载驱动的源码），经 `experiment-scripts/night-wrap.sh` 启动。
- **种子与下游**（第 7 步的经验）：组件写种子时引用[种子数据清单](../../docs/zh/03-seed-data.md)的“下游可以直接引用的数据”，缺的到上游种子里补；角色与授予照主数据的做法（`be-sdk-go` 的 `seed` 包），带上法人与部门的维度。
- **重跑套件 C 的升级（R4）**：`ops11.sh upgrade` 不写死版本，用 `UPGRADE_REFS` 给出比格里更新的发布（[11-03](experiment-records/11-03-suite-c-remaining-checks.md)）。

## 待用户决定

- 破坏性迁移的保险（第 12 步计划 9.1“还没定的”，不急）。
- 父仓库之后的提交（`git log origin/main..main`）：推送要维护者下令或授权。

## 未推送、已知问题与外部往来

- **推送**：子仓库（协议、SDK、验收、外壳、组件）的发布都已推送。父仓库 2026-11-02 推送到 `c755ccc9`（维护者下令）；之后的提交以 `git log origin/main..main` 为准。
- **给 BrickKit 的信箱** `brickkit-feedback/`（被 gitignore；规则在它的 `README.md`）：待办每条一个文件放在 `open/`，回复与复测写在同一个文件里，关闭后移到 `archive/`。没有待办：FRB-001–013、FRR-001–025 都已关闭（2026-11-02 最后一批：FRR-024 在 v1.12.0，FRR-025、FRB-011、FRB-012 在 v1.12.1，FRB-013 在 v1.12.2 上复测通过，`experiment-data/14-03-quadlet/`–`14-06-frb013/`）。下一个编号 FRB-015、FRR-026。待回复：FRB-014（代码地图里的组件 ID 被当成路径，2026-11-04）。
- **启动时等晚到的消息系统**（2026-11-02 修好，kb 审查 PR #58 查出）：线协议 alpha.40 加 P6.34（与数据库的 P5.10 一样，连不上就保持启动中、每秒重试；凭据或 scheme 不对 78，队列库不存在 69）、检查 CK-BUS-10；`be-sdk-go` alpha.43（`events/bus.Ready`，启动器与外壳都用）、`be-sdk-python` a40（`ready_bus`、`launcher.bus_ready_exit`）；协议 alpha.41 在 COMPAT 里记下这两个版本。**还没做**：组件与外壳仍在 Go alpha.41/42、Python a38/a39 上，随下次连锁发布换上之前，开机先于 Docker 里的 NATS 起来时仍会退出一次（Go 以 69 退出；Python 不退出、在 nats-py 里无限重连——旧写法 `max_reconnect_attempts=-1` 让第一次连接永不返回，实测 8 秒后仍在重连；它经 nats-py 默认的错误回调往 stderr 打 `ConnectionRefusedError`，所以 Python SDK a40 的提交说明与标签里“logged nothing and could not be stopped”说过了头：有日志，只是不经 SDK；停不停得下来没有测）。
- **启动时等依赖，对照 kb 的处理**（kb 处理 PR #59 后，2026-11-02）：kb 把“有上限的重试后退出”定为默认，“一直等”用于单机且“不健康、未就绪”有告警，Kubernetes 上要先把探针分开。我们保持一直等（维护者 2026-11-02 定）：只等暂时性错误、能被停止信号打断、数据库与消息系统同一种做法、等待写在启动流程里，这几条都符合；补了告警页的“组件不健康或未就绪超过 5 分钟、开机或发布后被平台重启过”一行，部署模式指南写明 Quadlet 单元每次 120 秒内没健康就被重启、Kubernetes 上启动探针到时杀掉（等于有上限）；补了“数据库晚到之后就绪”的测试（CK-DB-04；`be-sdk-go` alpha.46、`be-sdk-python` a42，各做过一次改坏代码的反向检查）。**以后做**：Kubernetes 上真正一直等，要 SDK 在等待时就应答存活检查、BrickKit 生成的启动探针不等依赖（要 BrickKit 配合）；COMPAT 第 2 节下次发协议时补 Go alpha.46、Python a42（实现 alpha.42）。
- **pgqueue 的两个“会抖”的测试**（2026-11-02 查清并修好，`be-sdk-go` alpha.44，`experiment-data/14-07-pgqueue-plan/`）：积压测试抖是因为它查到了真缺陷——运输连接池缓存预编译语句，执行到第 6 次 PostgreSQL 改用通用计划，投递表的统计还没跟上刚来的积压时，这个计划每次认领都把整个积压取出来排序（2 万条积压约 7 ms 一次，违反 P6.28）；表最近被自动 analyze 过时才不出现，所以在共用测试库上时红时绿。改为运输连接设 `plan_cache_mode=force_custom_plan`（实测：统计过期时认领 4.3 ms → 0.9 ms，发布吞吐看不出差别；Python 的运输连接本来不缓存语句）。清理测试抖是因为 `Purge` 清整个 bus，共用测试库里存着一周前的运行留下的消息。两个测试都改到各自新建、用完即删的 schema 上（修前 20 次红 19 次——更早一次没存原始数据的是 17 次，写在 alpha.44 的提交说明里——修后 0 次）。**第二种情形也修好了（kb 审查 PR #60 时查出，2026-11-02）**：`force_custom_plan` 只去掉了通用计划的排序；在从没 analyze 过的投递表上，“租约过期”那条路按参数规划也沿主键逐行走整个积压（规划器把在途估成一半的行）。协议 alpha.42 的 `migrations-bus/0003` 用 `(durable, seq) WHERE in_flight` 替换按 `lease_until` 的租约索引，P6.28 写明两条路各沿按位置排序的部分索引、领取按参数规划；`be-sdk-go` alpha.45、`be-sdk-python` a41 换上它，两个 SDK 的积压测试都改到自己的 schema 上、门槛收紧为“大积压 < 小积压 + 1 ms”（原来的“3 倍加 2 ms”让 20 次逐行走积压全部通过；新门槛下旧索引 20 次全红、新索引 20 次全绿；`experiment-data/14-08-pgqueue-inflight-index/`）。之前 SDK 测试看不出它，是门槛太松；“917 / 920 µs”是共用 schema 上“空表时 analyze 过”的另一种统计状态。协议 alpha.43 在 COMPAT 里记下 Go alpha.44/45、Python a41。组件随下次连锁发布换上新 SDK 并跑一次 `migrate`。**后来（底层先行第一项）**：T3 查明 alpha.44 的 `force_custom_plan` 让每次认领一直多付约 0.3 ms，协议 alpha.45、`be-sdk-go` alpha.49、`be-sdk-python` a44 起改为缓存计划、由 SDK 自己 analyze 统计落后的队列表（P5.33；组件连接池上的发件表与工作项也一样处理，发件表读未发布行的索引也换了，P6.35；`experiment-data/15-01-component-pool-plans/`）；T2 修好了共用测试 schema 越积越多（测试互相看得见彼此的东西）；
- **本项目的待办（来自 FRB-009）**：各组件、外壳与探针 Dockerfile 里的 `ENV PORT` 与注释“BrickKit injects PORT only for mode: local”已过时但无害，下次改动该组件时删掉（Python 探针与它的变体已在 3.2.20 删掉；Go 探针与它的变体还在）。
- **组件与外壳的 SDK**：组件与外壳在 `be-sdk-go` alpha.41、`be-sdk-python` a38；SDK 已到 alpha.42、a39（只给测试标了 CK-ID-01，行为不变），协议到 alpha.39（`COMPAT.md` 的“装配项目的正式文档”一列）。下次连锁发布时一起换。
- **改写过历史的仓库**（去掉误提交的二进制）：做法都一样——`git filter-repo` 只去掉那一个文件，只有含它的版本的文件树变了，其余文件树、作者、时间与说明都不变（说明里的旧哈希换成新哈希），分支与标签重新指向、强推；父仓库在改写之前记的指针已不在远端；改写前的整库备份放在当时会话的临时目录（会话结束会清掉）。
  - `be/go-core`（2026-10-23，用户同意）：3.0.20 误带 55 MB 的构建产物（3.0.21 移除），从 3.0.20 起改写，3.0.20–3.0.24 五个标签重新指向，远端克隆约 26 MB → 188 KB；父仓库 `d4a34794` 之前记的 3.0.20–3.0.24 指针悬空。
  - `be-acceptance`（2026-11-01，维护者同意）：探针 3.2.23 的提交误带 52 MB 的 `probes/go/go`，`main` 与 30 个标签重新指向，打包约 30 MB → 3.9 MiB；`legacy/v0`、`stage-b` 不变；父仓库此前记的 `1d205c5` 之后的指针悬空。`be/py-render` 3.0.29 的 `uv.lock` 按提交锁的探针因此取不到：3.0.30 重新锁定并发布，3.0.29 的说明写明改用新版本，实验格 `D12-H` 仍声明 3.0.29（本机已有镜像），下次用时换；Go 代理里 `probes/go/v3.2.23` 仍是带二进制的旧内容（没有东西依赖它）。
  - `be-sdk-go`（2026-11-01，维护者定：开发阶段只有我们自己用）：alpha.8、alpha.9 误带的 `grpcx.test`（48.6 MB），打包 24.5 → 1.6 MiB；alpha.10 起的模块内容不变（与组件的 `go.sum` 一致）；alpha.8、alpha.9 在 Go 代理里仍是旧内容，没有东西用。
  - `be/go-infra`（同上）：3.0.23 误带的 54.6 MB 产物，打包 25.6 MiB → 120 KiB；没进过 Go 代理。改写后 3.0.36 等版本指向的提交变了，**用改写前缓存的旧格**（例如 P9-H 的副本）`up` 会报“标签被移动过”，刷新缓存即可。
  - 2026-11-01 核对：各仓库历史里再没有误带的大文件；之后由提交钩子与 `make no-binaries` 拦（第 12 步复盘 I1）。
- **发布说明**：第 5、6、6b 步与第 7 步 3.0.1 起的十几个版本是手打的标签，说明只有一行版本号；已发布的不改（版本不可变）。现在一律 `brickkit release --notes-file <文件>`（使用方必须做什么在前，新增在后），Go 的 `v` 标签用同一份说明；发完用 `git for-each-ref refs/tags/<版本> --format='%(contents:subject)'` 看一眼。2026-11-01 第 12 步误用 `--notes <文件>` 把路径写进了 65 个标签，当天换成正文（BrickKit v1.11.0 起拒绝这样用）。
- **`tools/be-ops`、`tools/be-sdk-ts` 的 `stage-b` 分支**（2026-10-01 至 04，已推送、未发布）：设计冻结之前的阶段 B 实验。父仓库的指针停在各自 `main` 的发布版本（be-ops v0.2.0、be-sdk-ts v0.5.0）。重建这两个工具时只作参考，按新设计从零写（D59）。
- **kb知识库**：本项目交的 PR 已合并到 #58；#59（反馈：启动时关键依赖“一直等”的取舍——维护者 2026-11-02 定保持 P5.10、P6.34 的一直等；nats-py 第一次连接永不返回）、#60（反馈：拆成两条有序路的队列认领在缓存的通用计划下仍会排序整个积压）待审查。#58 的审查查出本项目报错的四处并在合并前改正：v1.12.1 那次重启有两个服务第一次启动失败（见下面“SDK 启动时连不上消息系统”）、有根的迁移时刻、有根单元的 `[Install]`、无根重启策略的出处；性能发现一律交给它（用户 2026-10-18），写成好读的结论，原始数据与通用脚本一起提交。第 7 步查到、以后用得上的几条：设计出账与信用时 05.21 可作参考，以本项目的协议 04、05 与边界卡为准；各国的法规（发票系列、电子发票报送）不归 kb 管，查官方来源写进本项目的文档；NATS 消费者设 `BackOff` 时第一个值代替 `AckWait`、它只管确认超时，按处理时间 p99 的 2–3 倍定；金额列 `NUMERIC(p,s)` 写入多出的小数位会被悄悄舍入，应用里先按业务规则舍入；运行时角色要能用迁移角色建的序列时，`bigserial` 要另授 `USAGE ON SEQUENCES`，identity 列不需要。

## 任务结束时：知识库反馈

还没交的草稿（Python 的字节码缓存、公共 Go 代理缓存自己的失败、变异不借共用的种子账号三份已交：kb PR #66，2026-11-05；第 4 项的实测记录、WAL-G 的不测推理与整套恢复的反馈已交：kb PR #68，2026-11-06；都等审查）：
- Linux 的 `CLOCK_MONOTONIC` 在系统休眠期间停走（`CLOCK_BOOTTIME` 才计入）；kb 选主相关文档（07.06 选主、07.10 时间与时钟）按单调时钟计租约时没有提醒这一点。提交前先在 Linux 上验证。
- 第 5 项 T10e、T11 撞出的四条已交 kb PR #70（2026-11-07，等审查）；“向量要能区分常见的错误实现”一条 kb 的一致性测试与变异测试两节已经讲了，不交。
