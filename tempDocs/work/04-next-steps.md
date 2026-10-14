# 接续清单

> 更新：2026-10-13，设计重组之后。本页只维护任务先后与接续方法。各设计文档的状态和仍待设计的部分在[设计地图](03-design-map.md)，用户决定在[决定台账](02-decisions.md)，问题在[问题台账](issues.md)，经过与证据在[证据记录](evidence.md)。

## 当前阶段

- **设计完整优先**（D59）：现有代码只作参考，终局设计按从零开始，不写从现有实现过渡的内容；设计会多轮复查和重构，稳定之后再彻底开发。
- **协议先写到可冻结**（D56），再按 D41 做代表部署实验，然后按新设计重建当前约 20 个组件的范围、用它们测试全部部署模式，最后扩展货架（开发五步见[路线](../08-roadmap.md#开发的前提与顺序)）。
- 安全候选第一至第十份（第六份为共同契约）与协议 01–20 已写成，都还是“候选”，未经独立复查；有状态或并发风险的都附有参考模型（`work/checks/08–32`），设计地图列出各自的剩余事项。

## 任务顺序

| 顺序 | 任务 | 内容 | 出口 |
| --- | --- | --- | --- |
| 1（已形成候选） | 管理、身份与变更的状态协议：[第八份](../security/08-state-and-change-protocol.md) | 各管理动作的资格、独立确认与受保护例外、系统角色、最后管理员、bootstrap 与恢复；员工与账号绑定、任职实例、模板与批量计划；共享治理、来源状态、有限链、扮演会话及通知落点 | 已形成：通用生命周期、生效点、有效段 = 记录 ∩ 来源、影响闭包、受保护操作、最后管理员、安装认领、恢复、紧急访问；剩逐字段编码并入第 3 项，部署所有者凭据与紧急访问认证路径并入身份协议 |
| 2（已形成候选） | 时间与内容发布，按 D57 改写安全 03：[第三份](../security/03-authorization-acceptance-and-revocation.md) | 默认路径：本地求值 + 短有效期的权威核验、超期拒绝或暂缓；可选严格路径：authz 持久接受（A 档）与提交屏障（B 档）。权威裁决与属主守卫的 DDL、隔离、重试，依赖域与 B 档参与者登记；安全属性变更、资源发布意图与水位、输出停止；外部发现、证据发行与时钟预算 | 已改写：默认路径的视图核验、有效期计算、事务内截止检查、撤权上界与不可用时的分级行为由参考模型验证；严格路径保留 A／B 档；剩操作分类与路径声明的编码并入第 3 项，参数实测并入第 8 项 |
| 3（已形成候选） | 正式编码与能力 profile：[第九份](../security/09-encoding-and-profiles.md) | 完整授予、管理职责与计划、身份、资源与字段、P／A／B、四类代次、水位、源类型与链、保护错误的逐字段编码；runtime 与装配的正式接口；有限摘要编码、签发或认证回读、动作 profile；第七份的段、原子、见证、计划摘要编码 | 已形成：逐字段表、规范编码与摘要（编码检查已运行）、能力目录与准入、操作与生命周期 profile；冻结时生成 protobuf／JSON Schema 与三语言向量 |
| 4（已形成候选） | provider 能力与成员切换：[第十份](../security/10-providers-and-member-switching.md) | 本地、静态、关系图、策略各方案支持哪些能力（第七份的“原子 × 算法”表）；客户换成员时的完整授予、角色与治理、源类型、资格、许可与水位、旧实例与恢复（新版本发布之后的切换） | 已形成：能力矩阵（外部产品按官方文档核对）、静态成员、切换协议与摘要等价核验（模型已运行）；剩一致性套件并入第 8 项，身份成员切换并入身份专题 |
| 5（已形成候选） | 数据与业务协议：[协议 01–08](../protocols/01-background-work.md)（I27、I30、I29、I23、I31、I33） | 作业认领后的恢复（I27）、局部投影修复（I30）、审计可靠保存（I29）、代表订单与财务时序（预占、出账、核销、关账，I23）、跨组件引用生命周期（I31）、扩展字段（I33） | 状态机、不变量、故障时序与 DT 向量 |
| 6（已形成候选） | 全覆盖细节 | 已写成协议 09–20：审批与流程（C27）、外部集成与通知打印（C28、C27）、冷热转层（C22–C23）、附件与对象存储（C24）、搜索报表与数据集（C25）、数据基础（C12、C17–C19、C21）、备份恢复（C37）、客户上线（C43）、运行与资源（C31–C35）、SDK 与一致性（C30）、配置密钥注册表与发布（C29、C36、C39）、前端（C38），清单见 [README](../README.md)。已写成全货架边界卡（[目录页](../components/README.md)，C01–C05）与协议 21 验证映射与正式文档迁移（C40–C42） | 每个 C 项都有设计文档与验证方式 |
| 7（进行中） | 整体复查与冻结报告 | 已做作者横切复查（rounds/09）、第一轮独立复查（rounds/10；D60–D63）与第二轮独立复查（rounds/11；D64 为 AI 决定、用户授权）；两轮发现登记为 I35–I58 并已修正；第三轮独立复查（rounds/12）的 13 项发现登记为 I59–I62 并已修正；第四轮聚焦复查（rounds/13）的 13 项发现登记为 I63–I66 并已修正；第五轮聚焦复查（rounds/14）的 12 项发现登记为 I67–I70 并已修正；第六轮聚焦复查（rounds/15）的 13 项发现登记为 I71–I76，按用户裁定 D65 与复查建议简化了故障与恢复的边缘；第七轮聚焦复查（rounds/16）的 12 项发现登记为 I77–I81；第八轮聚焦复查（rounds/17）的 19 项发现登记为 I82–I85，按用户裁定 D66（高可用整体同步，底层预留、后期启用）与作者的计数全量盘点修正；55 份文档标为“已复查”。AI 自行做出的选择汇总在 [05-ai-choices](05-ai-choices.md)（A01–A52）。下一步由用户决定：作者推荐进入冻结报告——把仍待实验的条款（高可用机制、纪元读取、同步等待的服务端行为）列为已知风险，交给第 8 项的实验；另一选择是再做一轮聚焦复查（第九轮，`18-ninth-review.md`），只看协议 14 的新规则与计数清单、协议 15 的整体同步与重放规则。冻结前先暂停（用户 2026-10-14 要求） | 冻结报告；用户确认后进入正式文档迁移（路线文档的切换步骤） |
| 8 | 代表部署实验 | 按新设计开发实验所需的代表组件、SDK 与外壳，做 D41 的部署对照（含连接池代理与仅 PG 对照组）；把 AE／TI／AT／AM／SD／SC／FX 预期对接 PA01–PA36，用黑盒套件真正测试 SDK，字段与查询用真实数据库，覆盖服务凭据、接受与撤销及至少一条业务链，套件要有坏变体与部分执行的边界 | 先写范围明确的实施与实验计划，经用户确认再写代码；据结果修订设计，再进入路线的第 3、4 步（重建当前范围、完整部署矩阵）；未测的未来成员仍标计划 |

缺少可运行组件不阻止继续写规范和独立预期，但不能用理论模型代替真实合格证据。若实验推翻候选，先修规范和所有受影响项再继续。“继续设计”不等于批准开始开发、替换 IAM 成员或部署真实客户；全量未来业务开发、完整合规和所有客户组合通过，都不属于可直接承诺的结果。

## 新会话先做的事

1. 读项目根 `AGENTS.md`，再读[交接入口](handoff.md)和本页；用户决定先看[决定台账](02-decisions.md)的总表。
2. 看 `git status`，保留未提交的工作；五个工具子模块指针的既有修改不要动。
3. 从上表的第一项未完成任务开始；动手前在[设计地图](03-design-map.md)确认相关文档的状态与遗留问题。
4. 每完成一项：更新设计地图（状态、遗留问题）、问题台账、证据记录，再更新本页。发现候选之间有矛盾时，先修受影响正文，不一路追加例外。

## 已答前提与不应重复的工作

- 用户没有统一规模计划，默认小公司开发；按业务、并发、资源、历史、监控选择配置、专项组件与部署。不再询问统一的用户数、单据量或年限。
- 文档整理进行中（用户 2026-10-14 选择“先在 tempDocs 里整理”）：按[整理计划](06-reorganization-plan.md)分批写 `tempDocs/final/`，每批停下请用户复核相关的 AI 选择；前端的 I86–I89 在第 7 批处理。图与表、文档分层的安排（用户 2026-10-15 提出）见整理计划的同名一节：第 2 批写规范，第 3–7 批补关键图表，第 8 项加“组件仓库骨架与文档分发”和“事实类图的生成工具”。
- 高可用已定（D66，用户 2026-10-14）：整体同步提交，底层预留、后期启用，正式开发起步是单实例单库；高可用切换边缘的新发现记为已知风险转入后期实验，不再开设计或复查轮次，也不再就此提问。
- D01–D69 的选择先读再用。真正未明且改变取舍的新问题才逐个问，一次一个。
- 不以现有实现为设计上限或兼容对象（D59）；不重新从产品名选权限模型；不自动启用并行 agent；不清理工作区；不修改 BrickKit 与知识库的主工作区。
- 外部反馈只针对已证实的问题。知识库 PR #8–#14 在提交时为待审；再次反馈前先查现状，不重复提交。项目成功案例等实际成果与验收后再整理。
- 现行正式 `docs` 在正式切换前保持原样；它与新设计的差异不作为迁移任务，切换时整体替换（路线文档的切换步骤）。

## 已有验证命令与证据范围

```sh
git status --short
git diff --check
make docs-boundary docs-mirror
python3 tempDocs/work/checks/06-document-counterexamples.py
python3 tempDocs/work/checks/07-authorization-time-models.py
python3 tempDocs/work/checks/08-finite-expressions.py
python3 tempDocs/work/checks/09-change-protocol.py
python3 tempDocs/work/checks/10-bounded-local-authorization.py
python3 tempDocs/work/checks/11-canonical-encoding.py
python3 tempDocs/work/checks/12-member-switch-equivalence.py
python3 tempDocs/work/checks/13-job-recovery.py
python3 tempDocs/work/checks/14-projection-repair.py
python3 tempDocs/work/checks/15-audit-durability.py
python3 tempDocs/work/checks/16-order-reservation.py
python3 tempDocs/work/checks/17-billing-settlement-costing.py
python3 tempDocs/work/checks/18-period-close.py
python3 tempDocs/work/checks/19-reference-lifecycle.py
python3 tempDocs/work/checks/20-extension-fields.py
python3 tempDocs/work/checks/21-approval-flow.py
python3 tempDocs/work/checks/22-external-commands.py
python3 tempDocs/work/checks/23-tiering.py
python3 tempDocs/work/checks/24-attachments.py
python3 tempDocs/work/checks/25-datasets-and-search.py
python3 tempDocs/work/checks/26-data-foundations.py
python3 tempDocs/work/checks/27-consistent-recovery.py
python3 tempDocs/work/checks/28-go-live-import.py
python3 tempDocs/work/checks/29-shared-budgets.py
python3 tempDocs/work/checks/30-conformance-report.py
python3 tempDocs/work/checks/31-key-rotation.py
python3 tempDocs/work/checks/32-offline-drafts.py
python3 tempDocs/work/checks/33-expectation-ids.py
python3 tempDocs/work/checks/34-dependency-closure.py
python3 tempDocs/work/checks/35-internal-source-watermark.py
python3 tempDocs/work/checks/36-billing-formalization.py
python3 tempDocs/work/checks/37-epoch-counters.py
```

这组命令只查当前工作树、正式文档边界／镜像和最小文档模型，不运行 PA／DT／ST 或 SDK 合规。还要核对本次修改的 Markdown 本地目标／标题锚点、表格列与场景编号；此前的数量／结果在[证据](evidence.md)，新修改后不能照抄通过数字。

## 交给新会话的任务说明

> 继续 `/home/zhijie/Desktop/github/be-assembly-standard` 的终局设计（中文 tempDocs）。先读根 AGENTS.md、tempDocs/work/handoff.md 和 tempDocs/work/04-next-steps.md；用户决定见 tempDocs/work/02-decisions.md 的总表，文档状态见 tempDocs/work/03-design-map.md。保留未提交工作，不动五个工具子模块的指针。项目处于“设计完整优先”阶段：现有代码只作参考（D59），协议先写到可冻结（D56），默认小公司、按客户情形扩展，不重复追问规模。从接续清单任务顺序的第一项未完成任务继续；候选、预期与实际验收分开记录；每完成一项同步设计地图、台账与证据。给用户的回复一律用中文。

## 独立复查的任务说明

> 你是 `/home/zhijie/Desktop/github/be-assembly-standard` 终局设计（中文 `tempDocs`）的独立复查者，不是作者。先读根 `AGENTS.md`、`tempDocs/work/00-brief.md`（用户原话）、`tempDocs/work/02-decisions.md` 的总表（U01–U13、D01–D69），再读 `tempDocs/work/03-design-map.md` 列出的全部设计文档：正文 00–09、`security/01–10`、`protocols/01–21`、`components/`、`replacements/`、`validation/`。从用户目标与决定出发，先找反例，再看作者的理由；不要因为作者的自查（`rounds/09-author-cross-review.md`）说没问题就相信。
>
> 重点：一、文档之间的矛盾（同一件事两处说法不同、参数不一致、职责归属冲突）；二、违背用户决定或 BrickKit 两条原则（组件独立运行、只在部署时合并）的设计；三、协议的漏洞：给出具体的交错或失败时序，说明哪条不变量被破坏；四、独立预期是否真由协议正文推出、是否漏了重要失败情形；五、参考模型（`work/checks/`）的坏变体是否覆盖协议的关键条款，可以运行它们；六、边界卡的组合闭包与缺件行为是否自洽；七、`rounds/09` 列出的 18 项 AI 设计选择中，有没有明显更好的备选或会推翻其他设计的问题。
>
> 产出：在 `tempDocs/work/rounds/10-independent-review.md` 写复查记录：读了什么、方法、发现表（编号、严重程度 阻塞／重要／一般、位置、问题、为什么、建议改法）、需要用户裁定的问题（每个给背景、推荐与备选）、结论（哪些文档可以标“已复查”）。只写这份记录，不修改设计文档，不提交 git，不动五个工具子模块。全部用中文。

**聚焦复查**（第四轮起）沿用上面的说明，改动三处：范围只看任务顺序第 7 项列出的上一轮改动（先读上一轮的复查记录与对应的问题台账条目，逐项核对是否真的解决、修正是否引入新问题）；运行相关模型与检查，并在会话临时目录的副本里尝试让它们漏掉协议条款；产出写到 `tempDocs/work/rounds/` 下的下一个编号（第九轮为 `18-ninth-review.md`）。
