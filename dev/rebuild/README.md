# 重建阶段的工作区

> 2026-10-15 建立：终局设计已冻结并迁成正式文档（`docs/zh/`），设计阶段的工作区归档在 `archive/design-2026-10/`。本目录放重建阶段仍在进行的工作；工作结束后整体归档。

## 这里有什么

| 文件 | 内容 |
| --- | --- |
| [migration-plan.md](migration-plan.md) | 正式文档迁移的动作与进度（协议 21） |
| [migration-map.md](migration-map.md) | 承接表：旧文档每一节的去处 |
| [be-protocol-carry.md](be-protocol-carry.md) | 线协议细节的承接清单，重建 `be-protocol` 时逐条重审写入 |
| [rebuild-plan.md](rebuild-plan.md) | 仓库复用、`legacy/` 分支、改名与新建的清单与顺序；每一步动仓库前先列动作请用户确认（改名除外） |
| [implementation-checks.md](implementation-checks.md) | 冻结时列出、交给实现阶段核对的项 |
| [experiment-plan.md](experiment-plan.md) | 代表部署实验（D41）的实施计划（待用户审） |
| [step1-repo-actions.md](step1-repo-actions.md) | 实验第 1 步的仓库动作清单与执行结果（2026-10-17 已执行） |
| [step2-plan.md](step2-plan.md) | 实验第 2 步（`be-protocol` 子集与 Go SDK）的任务、取舍与进度 |
| [step3-plan.md](step3-plan.md) | 实验第 3 步（Python SDK 子集、外壳启动器、两种语言的探针与一致性剖面）的任务、取舍与进度 |
| [step4-plan.md](step4-plan.md) | 实验第 4 步（三个外壳、资源采集、负载驱动、报告生成，D 行的底价与通信细分）的任务、取舍与进度 |
| [experiment-report.md](experiment-report.md) | 实验报告（给维护者与客户）；第 4 步起按行填写 |
| [step5-plan.md](step5-plan.md) | 实验第 5 步（身份适配、授权、审计与两个契约包）的计划，2026-10-19 定稿 |
| [step5-contracts.md](step5-contracts.md) | 第 5 步的契约（系统面的方法、信封与记录字节、定稿时补的设计） |
| [step6-plan.md](step6-plan.md) | 实验第 6 步（主数据四个）的计划、决定与进度（2026-10-20 起草） |
| [step7-plan.md](step7-plan.md) | 实验第 7 步（销售、库存、信用、出账、打印）的范围、决定、任务与进度；同时是文档结构实验的 R2（2026-10-22 起） |
| [doc-structure-plan.md](doc-structure-plan.md) | 文档结构实验（2026-10-22 起）：内容类型 × 层、初步结构、给 BrickKit 的 FRR-010–012、R0–R3 的轮次；题库在 `dev/routing-tests/structure-questions.md` |

## 现在在哪里

- 设计冻结、正式文档迁移已完成（[migration-plan.md](migration-plan.md)）；AI 选择 A99–A110 记在 `docs/zh/02-decisions/09-ai-choices.md`（A109 驻留期起始值待复核，其余已确认）。
- **代表部署实验（D41）进行中**：第 0–7 步已完成（第 6 步 2026-10-20 完成：主数据四个组件，[step6-plan.md](step6-plan.md)、[6-01](experiment-records/6-01-master-data-cells.md)；随后按用户要求补了种子数据，第 6b 步，[step6b-seed-plan.md](step6b-seed-plan.md)、[6-02](experiment-records/6-02-richer-seeds.md)）。第 4 步的 D 行结果见 [4-04](experiment-records/4-04-d-row.md)，第 5 步带真实安全组件的通信代价见 [5-02](experiment-records/5-02-security-cells.md)，都已写进[实验报告](experiment-report.md)。
- **文档结构实验**（2026-10-22 起，[doc-structure-plan.md](doc-structure-plan.md)）：R0 基线、R1 改结构与重考、R1b 压短根 `AGENTS.md` 已完成；R1 的尾巴与 R2（R2a 设计、R2b 设计与代码一致性，2026-10-22、23）都已完成；剩下 R3（定规则并反馈知识库与 BrickKit）。本轮的发布已推送（2026-10-22，用户同意）：`be-protocol` `v3.0.0-alpha.20`、`be-sdk-go` `v3.0.0-alpha.26`；`mdm/org` 3.0.4，`mdm/currency`、`mdm/partner`、`mdm/product` 3.0.5；`infra/authz` 3.0.5（包改名为 `authz/`）、`infra/audit` 3.0.3（包改名为 `audit/`）、`infra/iam-casdoor` 3.0.4；外壳 `be/go-infra` 3.0.25 编进 `mdm` 3.0.3/3.0.4、`infra/authz` 3.0.4、`infra/audit` 3.0.3、`infra/iam-casdoor` 3.0.3（之后只改了文档的版本没有再进外壳）。外壳 3.0.23 误带了 52MB 的构建产物，3.0.24 移除；用户同意保留历史、不改写。
- **第 7 步完成**（2026-10-23，[step7-plan.md](step7-plan.md)、[7-01](experiment-records/7-01-trading-chain.md)）：交易链五个组件（`erp/inventory`、`erp/credit` 3.0.2，`erp/sales`、`erp/billing`、`infra/print` 3.0.3）单跑（D7-S）与进外壳（D7-H：`be/go-infra` 3.0.26、`be/go-core` 3.0.24、`be/py-render` 3.0.22）都符合剖面；种子数据、L3 交易链（be-acceptance `conformance/scenarios`）、负载驱动的业务链（`load -flow`）、R2b（文档结构实验，10 题全对）都已完成。等用户确认后进入下一步。
- 第 7 步的经验（写种子与下游时照用）：组件写种子时引用[种子数据清单](../../docs/zh/03-seed-data.md)的“下游可以直接引用的数据”，缺的到上游种子里补；角色与授予照主数据的做法（be-sdk-go 的 `seed` 包），带上法人与部门的维度。待用户决定的事见下面“待用户决定”。测量一律在 performance 电源模式下、按小时算。
- 测量期间不在机器上跑任何测试、编译或剖析：会干扰数字，也会抢端口（4-03 记了一次）。 每一轮记下电源模式；运行脚本切到 performance 并在结束时恢复。
- 实验之后先做底层（权限、登录、冷热数据、事务、消息），再按 [rebuild-plan.md](rebuild-plan.md) 重建业务组件。

## 已定的事（跨步骤）

| 项 | 结论 | 记在 |
| --- | --- | --- |
| 版本号 | 全部仓库从 `3.0.0` 起，`X` 大版本、`Y` 阶段性变化（新功能、从开发进入正式）、`Z` 修复；不重用旧号、旧标签保留、不需要 `GOPRIVATE`；Go 模块路径带 `/v3`（Go 的硬规定） | A110（取代 A107）；开发流程的版本一节 |
| TypeScript | 当前范围不做；`infra/bff-mobile` 用 Go（gqlgen） | A108 |
| 冷热分层 | 底层阶段完整实现；驻留期按数据类别（起始 12 个月等） | D75 修订；协议 11；A109（待复核） |
| 实验矩阵 | 6 形态 × 3 拓扑打底，五套测试（A 矩阵、B 对照、C 故障、D 多版本、E 多实例多库）；正确性先于性能；工时不限，一项项测、测完一项记一项 | experiment-plan.md |
| `mode: local` | BrickKit 回复不做长期运行的本机部署；本机进程三行只量资源与通信，标“不推荐”（图省事的另类模式） | FRR-001 已关闭（v1.4.2 复测通过） |
| `local` 之后的用法 | 全部部署形态测完后本项目基本不再用 `local`，用 Docker 或 Podman（按结果定）；给 BrickKit 的部署形态反馈预定在第 14 步一次发出，中途不发（用户 2026-10-17） | experiment-plan.md 的“给 BrickKit 的部署形态反馈（预定）” |
| 记录方式 | 档案（给 AI，详细、先结论、表格优先）+ 报告（给用户，含“用什么测的”与额外发现的表）+ 原始数据 | experiment-plan.md 的“记录与报告” |
| BrickKit CLI | 项目要求 v1.8.5（2026-10-20；项目技能同步更新）。v1.6.0 起只写 `deployment.image` 的组件来自本地源也拉取，要在本机构建的组件必须写 `deployment.build` | `infra/scripts/lib/require-brickkit.sh` |
| 发布标签 | AI 决定怎样发、按依赖顺序发、发后从远端核对并汇报（用户 2026-10-18）；仓库的新建、改名、删除仍先确认 | 记忆 |
| 测试与长时间运行 | 放后台、监视脚本每 30 秒检查、约每 5 分钟汇报、缺陷当场停、预期上限跑完再一次修 | 用户级指令（知识库） |
| 性能与可读性 | 越底层越要想性能、查市场上更好的做法；业务逻辑以看得懂为先 | `docs/zh/01-conventions/09-ai-coding.md`；知识库 PR #17 |

## 第 0–3 步的结果

**第 0 步**：

| 编号 | 项 | 状态 |
| --- | --- | --- |
| 0-01 | `GOPRIVATE` 绕过 Go 代理与校验和库 | 完成；因 A110 已不需要，留作历史 |
| 0-02 | 同号重发与 BrickKit 两层缓存 | 完成；缓存会静默给出旧内容；v1.5.0 起报 `VERSION_CHANGED`（FRR-002 复测通过） |
| 0-03 | 一个仓库放多个组件（探针） | 完成；v1.5.0 起安装源可写 `repo`，探针用 `brickkit add` 加入，不再手写三层（FRR-003 复测通过） |
| 0-04 | Go 外壳承载成员（外壳自己的 `go.mod` 引入成员模块；BrickKit 只核对成员版本，不替外壳编译）；成员版本不一致时被拒 | 完成（2026-10-17）；“编进的代码与声明不符”只有启动器能拦，第 2 步的启动器按 Go 构建信息核对；按标签取成员留到第 4 步；v1.6.0、v1.6.1 复测通过（FRR-004、FRB-001） |
| 0-05 | 全部组件与外壳 `mode: local`（`target: docker`，基础资源在 Docker） | 完成（2026-10-17）；Go、Python 的单跑与外壳都能跑，看护行为与文档一致；v1.7.1 起单跑的本机进程与本机外壳的成员都用 `local.migrationCommand` 从源码迁移；`go run` 常驻，内存分开报；计划的“负载与测量”已补三条 |
| 0-06 | 本机进程与 Podman 混合 | 完成（2026-10-17）；全部容器、外壳在容器、外壳在本机三种布局都通；无根 Podman 的 `host-gateway` 可用；正式跑 P、LP 行时基础资源只起 Podman 那套 |
| 0-07 | minikube 跑 BrickKit 生成的 K8s 清单（含外壳）；`local`、`debug` 不能配 `k8s` | 完成（2026-10-17）；v1.7.2 起外壳成员的地址写成员自己的服务名，K8s 上调用链通（FRB-004 关闭）。镜像要 `minikube image load`；没有 kubectl，用转给 `minikube kubectl --` 的小脚本 |
| 0-08 | 同一组件两个版本并存（BrickKit 多版本共存：`requiredBy`） | 完成（2026-10-17）；`add` 自动保留兼容版本，外壳只编进一个版本、另一个单独运行；迁移按版本串行；迁移顺序保护有效 |
| 0-09 | 同一组件两个副本 | 完成（2026-10-17）；K8s 上通过；v1.8.0 起 Docker、Podman 也支持副本（FRR-006 关闭），套件 E 恢复四格；Go、Python SDK 都要做到删副本时零失败 |
| 0-10 | 两个 PostgreSQL 实例 | 完成（2026-10-17）；分实例完全靠配置覆盖；三种形态下连接与迁移都去对的实例；特殊字符的密码三条注入路径一致 |
| 0-11 | Podman 有根与无根 | 完成（2026-10-17，用户执行有根脚本）；有根下 BrickKit 正常，但与同机 Docker 冲突、容器之间不通（静默）；B6 要在没有 Docker 的条件下跑；每格先跑冒烟测试 |
| 0-12 | 连接池代理的事务模式与 `SET LOCAL`（以及 pgx 的预编译语句） | 完成（2026-10-17）；设计依赖的事务内设置都成立；pgx 默认模式要求 PgBouncer 开 `max_prepared_statements`（记进交实现核对的项） |
| 0-13 | 负载与数据的试跑规模 | 推迟到有业务组件之后（第 8 步前） |

**第 1–3 步**：0-01 到 0-12 完成，0-13 按计划推迟；第 1 步的仓库动作已执行（[step1-repo-actions.md](step1-repo-actions.md)）；第 2 步发布 `be-protocol`、`be-sdk-go` 的 `v3.0.0-alpha.1`（[step2-plan.md](step2-plan.md)）；第 3 步做了 Python 的 SDK 子集与外壳启动器、两种语言的探针与核心一致性剖面（[step3-plan.md](step3-plan.md)）。之后的版本以各计划的进度为准（2026-10-20：协议 `alpha.19`、`be-sdk-go` `alpha.24`、`be-sdk-python` `a21`、探针 3.2.19、外壳 3.0.19（`be/go-infra` 3.0.20）；`infra/iam-casdoor` 3.0.1、`infra/authz` 3.0.2、`infra/audit` 3.0.1；`mdm/org` 3.0.2、`mdm/currency` 3.0.3、`mdm/partner` 3.0.3、`mdm/product` 3.0.3，四者的 `contract/` 各 `v3.0.0-alpha.1`；第 6b 步之后 `be-sdk-go` `alpha.25`、`infra/iam-casdoor` 3.0.2、`infra/authz` 3.0.3、`infra/audit` 3.0.2、`be/go-infra` 3.0.22；契约包 `contract-infra-authz`、`contract-infra-iam` 与 `infra-audit` 的 `contract/` 各 `v3.0.0-alpha.1`；BrickKit CLI v1.8.5）。

## 推进方式与停点

2026-10-17 起连续推进（用户授权）：每项做完写记录、更新本文件、提交，直接做下一项；只在需要用户决定、需要 BrickKit 配合、仓库的新建改名删除时停下。每一步结束停下汇报，用户确认后进入下一步（计划的“步骤与检查点”）。

## 待用户决定

- **组件仓库的布局与正式规则冲突**：[AI 导航的标准布局](../../docs/zh/01-conventions/05-ai-navigation.md#组件仓库的标准布局与代码地图)写的是 `contracts/`、`gen/`、`backend/module|cmd|internal`、根目录的 `migrations/`、`assembly.yaml`、`docs/design.md`；第 5、6 步的七个组件实际是 `contract/`（单独的 Go 模块，含 proto、事件 schema、OpenAPI 与生成代码）、以组件命名的包（`org/`、`partner/`……，外壳以 `org.Definition()` 引入）、包内的 `migrations/`（随包嵌入）、根目录 `main.go` 与 `cmd/seed`，没有 `assembly.yaml` 与 `docs/design.md`。建议按实际布局改规则（契约单独成模块是为了调用方只引入契约；迁移随包嵌入是为了外壳里每个成员带着自己的迁移），也可以按规则改七个组件。

- **`be/go-core` 3.0.20 误带了 55 MB 的构建产物**（2026-10-23），3.0.21 移除，产物仍在历史里。上次 `be/go-infra` 3.0.23 的同类情况用户同意保留历史；这次是否同样处理待确认。

## 未推送、已知问题与外部往来

- **未推送的提交**：父仓库 2026-10-20 按用户要求推送到 `9e58039`（第 5、6、6b 步与之后的知识库、BrickKit 往来），之后的提交是否推送等用户决定；以 `git log origin/main..main` 为准。子仓库（协议、SDK、验收、外壳、组件）的发布都已推送并从远端核对。
- **发布说明是空的（2026-10-20 发现）**：第 5、6、6b 步的发布脚本直接打注释标签，说明只有“mdm/org 3.0.2”一句，没有照[开发流程与发布](../../docs/zh/01-conventions/10-development-workflow.md)用 `brickkit release` 写发布说明；`brickkit upgrade` 把标签说明当作发布说明显示，使用方看不到改了什么。已发布的标签不改（版本不可变）；第 7 步起用 `brickkit release --notes <文件>` 发布（使用方必须做什么在前，新增在后），Go 的 `v` 标签用同一份说明。**2026-10-23 又犯了一次**：第 7 步 3.0.1 起的交易链、打印与两个外壳的十几个版本都是手打的标签（会话压缩后漏看了这一条），说明只有一行版本号；同样不改，下一次发布起照做（已记进 AI 的记忆）。
- **已知、暂不处理**：旧的发布、接入与验证工具的测试失败，工具随重建重新提供，届时一并处理：`infra/scripts/tests/test_ship_dryrun.sh`（旧的 `ship.sh` 还调用旧 `be-acceptance` 的命令，迁移后已不存在）；`test_config_fill.py` 中 `integrate.sh` 的 4 项（伪造的 `brickkit` 报 v1.4.0，被版本检查拒绝）与 `test_verify_deploy.py`（`verify-component.sh`）——2026-10-18 在改动之前的提交上核实同样失败。
- **给 BrickKit 的收件箱** `brickkit-feedback/rebuild.md`：FRR-001 到 FRR-006、FRB-001 到 FRB-006 全部关闭（FRB-006 于 2026-10-18 在 v1.8.2 复测通过，升级后的部署与测量也通过）；FRB-007（升级把用户已移除、但旧外壳版本编进了的成员加回来）2026-10-18 新开、当天在 v1.8.3 复测通过并关闭；FRR-007（使用者移除过的成员因强依赖被升级加回来时提示一声）当天在 v1.8.4 实现、复测通过并关闭；2026-10-20 新开 FRR-008（依赖方的精确依赖没跟上时提醒两个版本会并存、报错点名依赖方；已在 v1.8.4 复现，脚本在 `experiment-data/6b/frr008/`）与 FRR-009（种子数据页补三条做法），当天在 v1.8.5 实现、复测通过并关闭；没有未回复的条目。
- **知识库**（2026-10-20）：
  - 反馈与处理：
    - PR #22、#23：实测记录与反馈，已合并并处理；
    - PR #24：三轮查阅测试 19 问（演示种子、销售开票与应收、信用控制，五处说法不一致），已合并并处理，新增 05.21 开票、应收与信用额度；
    - PR #25：两轮 14 问（成本暂估、关账、改单、业务链压测，九处不一致或算错），已合并并处理（c84acfce）；
    - PR #26：按第 7 步真实要做的事测两轮 17 问（报价单、欠交、按法人的模板、Go 十进制库，九处不一致），已合并并处理（abb862f2）；知识库同时定了只收技术内容；
    - PR #27：按第 7 步要写的代码测两轮 17 问（发件表、Saga、迁移、打印服务、停机、毒消息、多副本任务等），反馈两处会让照抄出错的地方（NATS 示例的 backoff、按 schema 授权漏序列，都已真机复现），并附实测记录「PostgreSQL 金额列：bigint 还是 numeric」，待审查。
    - PR #29（2026-10-23）：实测记录「打印渲染：Typst 对 WeasyPrint」与 Typst 的包下载、字体封闭、`RLIMIT_AS` 与线程池、只有 glibc 轮子，待审查；
    - PR #30（2026-10-23，第 7 步收尾）：健康检查要答 `HEAD`（探针的方法因镜像而异）、批量后台任务打破全局加锁顺序、验证重跑不变要等后台做完、版本号单一来源，待审查。
  - 第 7 步怎样用：
    - 设计出账与信用时，05.21 可作参考，以本项目的协议 04、05 与边界卡为准；
    - 各国的法规（发票系列、电子发票报送，例如西班牙的 Verifactu 已推迟到 2027）不归知识库管，知识库只管技术；设计各法人的编号与开票时查官方来源，写进本项目的文档。
    - NATS 消费者设 `BackOff` 时，服务端用它的第一个值代替 `AckWait`，且它只管确认超时、不管 `Nak`：第一个值按处理时间 p99 的 2–3 倍定（NATS 2.12 实测）；
    - 金额列是 `NUMERIC(p,s)` 时，写入多出的小数位会被悄悄舍入（远离零）：应用里先按业务规则舍入再写；扫几百万行的报表，`numeric` 的求和、排序约慢一倍，联机请求看不出差别（PostgreSQL 16 实测，见 PR #27）；
    - 运行时角色要能用迁移角色建的序列：`bigserial` 需要另授 `USAGE ON SEQUENCES`，identity 列不需要。
- **知识库（更早）**：PR #22（基准在共用测试环境里留下数据）、#23（2026-10-20：Python 与 Go 的 JSON Schema 校验库实测；反馈：校验库怎样选、Go 代理缓存“找不到”、`&&` 链挡不住下一行；追加：nil 切片在 JSON 比较里不同于空切片、集成测试固定端口被本机部署占用）待审查；PR #16（测试定期检查、asyncio 的 Nagle）、#17（性能与可读性）、#18（版本与技术栈按最新、性能、适配度优先；不知道就测；实测对比与项目经验分开）、#19（2026-10-18 的实测对比，陆续追加：granian、Go 的 S3 客户端、修复后的数字）等审查；其余草稿见下一节。**性能发现一律交给知识库**（用户 2026-10-18）：写成好读的结论，原始数据作为同编号的日志文件一起提交。

## 任务结束时：知识库反馈

把知识库反馈作为一个 PR 提交（走 `kb-contribute`）。**第 7、9、10 项已并入 PR #19**（实测对比 06、01–03、07），不再单独提交；剩下的是第 1、3、4、5、6 项。**提交时机（用户 2026-10-18）**：等全部复测与 `step4-plan.md` 留到后续的 Go、Python 性能实验做完，按结果修改第 7–10 项（尤其第 9 项的 Python 加速件与新发现的 Go 优化）后再提交。目前草稿有十项（另有两项——测试定期检查进用户级指令、asyncio 的 Nagle——已于 2026-10-18 按用户要求先行提交：knowledge-base PR #16）：

1. Linux 的 `CLOCK_MONOTONIC` 在系统休眠期间停走（`CLOCK_BOOTTIME` 才计入）；知识库选主相关文档按单调时钟计租约时没有提醒这一点。提交前先在 Linux 上验证。
2. 跨平台 D2 一节没有把 uni-app 列为 Vue 团队的 App 选项。
4. Go 程序在 Alpine、distroless 等镜像里 `time.LoadLocation` 失败（镜像不带时区数据库）；需要按 IANA 时区算日期或定时的库应当嵌入 `time/tzdata`。知识库的 Go 容器化与时区相关文档没有提这一点。提交前在 Alpine 镜像里复现。
5. 用 PostgreSQL 表做消息队列时，清理若等“所有订阅都读过”，一个不再回来的订阅者会让表永远增长；消息系统只是运输缓冲，应按保留期清理，离线过久的订阅者靠发件表补发与对账恢复。知识库的消息队列与发件表文档可以补一句。
3. 项目文档“用什么方式表达”缺一处总的选择：14.04.03 只在图与表之间选；编号步骤（14.04 的操作手册、07 技术写作的一行）、填好的样例（只在 API 文档 D4）、改前改后的对比（只在知识库自己的写作规则 meta/02-writing）散在各处。建议在 14.04.03 D1 前加一张“内容的形状 → 图、表、代码、步骤、样例、文字”的表，写明这些都是按情况选的选项，同样适用于项目文档；“能用图代替的不写代码”放到项目文档里偏绝对，几行代码更直接的地方（接口形状、机制本身）应当用代码。本项目的写法见 `docs/zh/01-conventions/04-diagrams-and-tables.md` 的“先选表达方式”。
6. Go 模块在主版本 2 及以上时路径必须带 `/vN`，放在仓库子目录里的模块也一样（标签是 `<目录>/vX.Y.Z`，路径是 `<仓库>/<目录>/vN`）；漏了时模块标签被 Go 拒绝，而且标签不能删了重用。知识库的 Go 模块与单仓库多模块文档如果没写子目录的情形，补一句。提交前核对知识库现有内容。
7. **数据库表做队列的三个性能坑**（知识库已有 `SKIP LOCKED` 领取，缺这些）：①每次领取前做全量清理（例如删掉消息已被清理的投递），代价随积压增长，积压越多越慢、订阅一落后就追不上；②积压突增后统计信息过时，`OR` 条件跨两个部分索引让数据库取出全部积压再排序（实测 0.1 ms 变 34 ms），改为各走一条有序索引取第一行、再按主键精确定位要更新的行；③多个流共用一张表时，推进读取位置有进展就应立即继续，只在既没推进也没领到消息时才等轮询。依据：本项目 `be-sdk-go` `alpha.6` 的 `events/pgqueue` 与 P6.28，及其测试。可补进知识库的作业表与执行计划相关文档。
8. **Claim Check 与发布顺序**：要求按顺序发布时，大载荷的上传可以并发（各条上传互不依赖），发布再按顺序等每一条就绪；逐条上传会把一个分区限死在 1/上传耗时（实测 100 KiB 载荷、200/s 时发出 p50 3.6 秒）。可补进消息模式的 Claim Check 一节。
9. **Python 异步服务的加速件与坑**：uvicorn 装上 `httptools` 后用 C 解析 HTTP（显式指定，缺包时启动即失败而不是悄悄退回）；httpx 底层的 httpcore 每次用连接锁都 `import sniffio`，没装时每次失败的导入都重扫整个搜索路径（实测加上 `sniffio` 与 `httptools`，代理一次 HTTP 调用的 CPU 少 17%）；实测（2026-10-18）：出站 HTTP 由 httpx 换成 aiohttp，每次调用的 CPU 少约 37%、一跳少约 40%（aiohttp 本来就随 aiobotocore 装着）；uvloop 只省 5%–10%，在测量波动之内。知识库的 Python 一篇只提到 orjson、msgspec，没有出站 HTTP 客户端与事件循环的对比。另：Go 1.27（2026-08）的 `encoding/json` 改由 v2 实现、反序列化明显更快，知识库的 Go 一篇没提；Go 一篇推荐 `net/http` 加 chi、不用 Gin，本项目锁定 Gin（中间件链每种语言只写一遍），定稿时写明这是项目的选择。可补进知识库的 Python 与 Go 两篇。
10. **待定**：功能测试全过、性能问题仍可能藏着——成批测量按操作类型设合理上限（例如固定速率下一跳 p50 的上限），本项目两次靠它抓到问题。先对照知识库的测试文档再决定是否反馈。
