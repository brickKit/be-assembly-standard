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
- **第 7 步完成**（2026-10-23，[step7-plan.md](step7-plan.md)、[7-01](experiment-records/7-01-trading-chain.md)）：交易链五个组件（`erp/inventory`、`erp/credit` 3.0.2，`erp/sales`、`erp/billing`、`infra/print` 3.0.3）单跑（D7-S）与进外壳（D7-H：`be/go-infra` 3.0.26、`be/go-core` 3.0.24、`be/py-render` 3.0.22）都符合剖面；种子数据、L3 交易链（be-acceptance `conformance/scenarios`）、负载驱动的业务链（`load -flow`）、R2b（文档结构实验，10 题全对）都已完成。之后处理的小事、文档结构 R2c 与 R3、SDK 版本对齐（全部组件 be-sdk-go alpha.32，D7-H、D7-S 复跑通过）见 step7-plan 的“第 7 步之后处理的小事”。**正式的部署模式测试（第 8 步起的部署矩阵）等用户下令再开始**（2026-10-23）。**第 8 步的测量轮已做完**（2026-10-25，[step8-plan.md](step8-plan.md)、[8-01](experiment-records/8-01-d-row-chain.md)）：R8.1 三格结果摘要相同；R8.2、R8.3 两遍一致（不跑 R8.4），H2 外壳比单跑的组件 CPU 少 22–25%、常驻内存少 47–48%，延迟看不出差别；R8.2e 空库起格 47–55 秒。第 8 步还剩：实验报告的 D 行、性能发现交知识库；之后修 R8.2 发现的缺陷（下面“已知问题”）、给采样加不含页缓存的内存读数，再等用户下令开第 9 步（其余 5 行）。
- **第 9 步（其余运行形态）：整夜测量完成**（2026-10-27，[9-01](experiment-records/9-01-other-rows-chain.md)）：D9-S 与 P、K、L 三行的 S、H、X 共十格一次跑完，结果摘要都与 D8-S 相同；组件开销四种形态差不多，差在平台（Kubernetes 常驻约 2 GiB）；外壳在每种形态都省；本机进程 p50 多约 2 毫秒（测量的转发）。之前修的两个问题、“定义未到”不绑定变更键（D77）与冒烟见 [step9-plan.md](step9-plan.md) 第 8 节。基础资源各行都用同一套 Docker（用户定）。第 9 步还剩：LD、LP 两行，探针的底价与通信细分（含 9-01 第 6 节两处待细分），实测交 kb知识库。容器数据与大缓存 2026-10-26 搬到数据盘 `/home/zhijie/data`（同一块 NVMe）。
- 第 7 步的经验（写种子与下游时照用）：组件写种子时引用[种子数据清单](../../docs/zh/03-seed-data.md)的“下游可以直接引用的数据”，缺的到上游种子里补；角色与授予照主数据的做法（be-sdk-go 的 `seed` 包），带上法人与部门的维度。待用户决定的事见下面“待用户决定”。测量一律在 performance 电源模式下、按小时算。
- 测量期间不在机器上跑任何测试、编译或剖析：会干扰数字，也会抢端口（4-03 记了一次）。 每一轮记下电源模式；运行脚本切到 performance 并在结束时恢复。
- 实验之后先做底层（权限、登录、冷热数据、事务、消息），再按 [rebuild-plan.md](rebuild-plan.md) 重建业务组件。

- **文档里的图（2026-10-24 交办，2026-10-25 完成）**：开发文档不放图（34 张换成步骤与表），客户读的 19 张图后补全关系，组件的 3 张随 `erp/sales` 3.0.7、`erp/billing` 3.0.5 发布；`make docs-diagrams` 进 `make gates`。经过与留下的事见 [diagrams-plan.md](diagrams-plan.md) 的“结果”。

## 推进方式与停点

2026-10-17 起连续推进（用户授权）：每项做完写记录、更新本文件、提交，直接做下一项；只在需要用户决定、需要 BrickKit 配合、仓库的新建改名删除时停下。每一步结束停下汇报，用户确认后进入下一步（计划的“步骤与检查点”）。

## 待用户决定

（目前没有。）

## 未推送、已知问题与外部往来

- **`be/go-core` 的历史改写过**（2026-10-23，用户同意）：3.0.20 误带了 55 MB 的构建产物，3.0.21 移除；之后从 3.0.20 起改写历史去掉它，3.0.21–3.0.24 的文件树、作者、时间与说明都不变，五个标签重新指向（远端的克隆从约 26 MB 变成 188 KB）。父仓库 `d4a34794` 之前的提交记的 go-core 指针（3.0.20–3.0.24 的旧提交）已不在远端；改写前的整个仓库备份在会话临时目录的 `gocore-rewrite/be-go-core-before-rewrite.bundle`（会话结束会清掉）。`be/go-infra` 3.0.23 的同类产物仍按当时的决定留在历史里。

- **未推送的提交**：父仓库 2026-10-23 按用户要求推送到第 7 步完成（`35a1cec0` 及本条的更新），之后的提交是否推送等用户决定；以 `git log origin/main..main` 为准。子仓库（协议、SDK、验收、外壳、组件）的发布都已推送并从远端核对。
- **发布说明是空的（2026-10-20 发现）**：第 5、6、6b 步的发布脚本直接打注释标签，说明只有“mdm/org 3.0.2”一句，没有照[开发流程与发布](../../docs/zh/01-conventions/10-development-workflow.md)用 `brickkit release` 写发布说明；`brickkit upgrade` 把标签说明当作发布说明显示，使用方看不到改了什么。已发布的标签不改（版本不可变）；第 7 步起用 `brickkit release --notes <文件>` 发布（使用方必须做什么在前，新增在后），Go 的 `v` 标签用同一份说明。**2026-10-23 又犯了一次**：第 7 步 3.0.1 起的交易链、打印与两个外壳的十几个版本都是手打的标签（会话压缩后漏看了这一条），说明只有一行版本号；同样不改，下一次发布起照做（已记进 AI 的记忆）。
- **`tools/be-ops`、`tools/be-sdk-ts` 的 `stage-b` 分支**（2026-10-01 至 04，已推送、未发布）：设计冻结之前的阶段 B 实验（be-ops 的 O1、O2 生成器与门禁；be-sdk-ts v0.6 起步，钉 `be-protocol v1.0.0-rc`）。父仓库的指针停在各自 `main` 的发布版本（be-ops v0.2.0、be-sdk-ts v0.5.0）；2026-10-25 本机检出从 `stage-b` 切回指针。重建这两个工具时只作参考，按新设计从零写（D59）。
- **已修（2026-10-26）：Kubernetes 上授权组件永远不就绪；授权组件换了地址之后约一分钟不能写**：协议 P8.24、P4.27、P4.28，SDK `be-sdk-go` 3.0.0-alpha.33 与 `be-sdk-python` 3.0.0a29，全部组件与外壳发了新版本；`cell-chain.sh` 的两个绕法已去掉，换 IP 的回归 `MOVE=1` 在 D9-S 通过。经过与版本见 [step9-plan.md](step9-plan.md) 8.2。
- **已知、暂不处理**：旧的发布、接入与验证工具的测试失败，工具随重建重新提供，届时一并处理：`infra/scripts/tests/test_ship_dryrun.sh`（旧的 `ship.sh` 还调用旧 `be-acceptance` 的命令，迁移后已不存在）；`test_config_fill.py` 中 `integrate.sh` 的 4 项（伪造的 `brickkit` 报 v1.4.0，被版本检查拒绝）与 `test_verify_deploy.py`（`verify-component.sh`）——2026-10-18 在改动之前的提交上核实同样失败。
- **给 BrickKit 的收件箱** `brickkit-feedback/rebuild.md`：FRR-001 到 FRR-006、FRB-001 到 FRB-006 全部关闭（FRB-006 于 2026-10-18 在 v1.8.2 复测通过，升级后的部署与测量也通过）；FRB-007（升级把用户已移除、但旧外壳版本编进了的成员加回来）2026-10-18 新开、当天在 v1.8.3 复测通过并关闭；FRR-007（使用者移除过的成员因强依赖被升级加回来时提示一声）当天在 v1.8.4 实现、复测通过并关闭；2026-10-20 新开 FRR-008（依赖方的精确依赖没跟上时提醒两个版本会并存、报错点名依赖方；已在 v1.8.4 复现，脚本在 `experiment-data/6b/frr008/`）与 FRR-009（种子数据页补三条做法），当天在 v1.8.5 实现、复测通过并关闭；没有未回复的条目。 2026-10-23 新开的 FRB-008 与 FRR-010–013 在 v1.9.0、v1.9.1 复测通过并关闭（本项目这边的待办 2026-10-25 核对已完成）；2026-10-25 新开的 FRR-014（`release.goModule: true` 一次打平台与 Go 的两个标签并核对模块路径）、FRR-015（文档规范：规则与流程写成文字与表）、FRR-016（AI 指南的检验文档一页）在 v1.10.0 实现并复测：015、016 关闭；014 的第 3 步（外壳取到新成员）等下一次发布 Go 组件时顺带看，各 Go 组件下次改动时在 `component.yaml` 加 `release.goModule: true`。
- **知识库**（2026-10-25 核对）：PR #16–#34 全部已合并并处理，没有待审查的。近几个：#27（NATS 的 backoff、授权漏序列、金额列 numeric 对 bigint）、#29（Typst 对 WeasyPrint）、#30（健康检查的 HEAD、批量任务的加锁顺序、版本号单一来源）、#31（项目案例：改动的循环与两次 AI 考试）、#33（实测：文档里的图对 AI 有没有用——本项目“图只放在客户读的文档里”的依据）、#34（知识库的盲测改用无头会话；考试查不出“文档自洽却不是用户要的”）。还没交的只剩下面“任务结束时”的草稿。
  - 第 7 步怎样用：
    - 设计出账与信用时，05.21 可作参考，以本项目的协议 04、05 与边界卡为准；
    - 各国的法规（发票系列、电子发票报送，例如西班牙的 Verifactu 已推迟到 2027）不归知识库管，知识库只管技术；设计各法人的编号与开票时查官方来源，写进本项目的文档。
    - NATS 消费者设 `BackOff` 时，服务端用它的第一个值代替 `AckWait`，且它只管确认超时、不管 `Nak`：第一个值按处理时间 p99 的 2–3 倍定（NATS 2.12 实测）；
    - 金额列是 `NUMERIC(p,s)` 时，写入多出的小数位会被悄悄舍入（远离零）：应用里先按业务规则舍入再写；扫几百万行的报表，`numeric` 的求和、排序约慢一倍，联机请求看不出差别（PostgreSQL 16 实测，见 PR #27）；
    - 运行时角色要能用迁移角色建的序列：`bigserial` 需要另授 `USAGE ON SEQUENCES`，identity 列不需要。
- **性能发现一律交给知识库**（用户 2026-10-18）：写成好读的结论，原始数据作为同编号的日志文件一起提交。

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
