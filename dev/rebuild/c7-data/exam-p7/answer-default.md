检查完了，没有改任何文件。下面每题先写文档依据，再写代码依据，最后一行是结论。

先说三处不一致，后面各题会引用：
- **A**：付款 `docs/design.md:84` 把批准人是申请人也列为 `APPROVER_IS_SUBMITTER`，代码里批准走流程内核，答 `SELF_APPROVAL`。
- **B**：协议 P17.8 与采购、收付款 `design.md` 都写“员工投影变化后重新解析暂停的任务”，代码只有每分钟的作业。
- **C**：旧的采购 `reject` 路由在看任务可见性之前就先查意见，顺序与 P17.1 不同。

## 1. 采购：提交订单时的审批人配置，与不审批的政策

**政策要审批、没配审批人**
- 文档：PO03（`erp/purchase/docs/design.md`），整笔拒绝，答 `NO_APPROVER_CONFIGURED`。`BRICKKIT.md` 写它是 409。
- 代码：
  - `internal/policies/policies.go` 的 `Policy.Approver()` 在岗位与个人都没配时返回 `core.ErrNoApprover`，定义在 `internal/core/rules.go`，409。
  - `orders/approval.go` 的 `startApproval` 在提交的事务里调它，出错整笔回滚，订单留在草稿。
  - 政策缺省值是“要审批、没审批人”（`policies.Of`）。
- 一致。

**配了岗位但部署里没有 `mdm/employee`**
- 文档：PO03、规则要点和依赖表写，配岗位的提交后任务暂停（`no_assignee`），不拒绝提交。协议 P17.3、P17.8 同。
- 代码：
  - `purchase/module.go` 的 `New` 只在 `flow.NewEmployees` 成功时设 `k.Directory`。
  - `flow/instance.go` 的 `resolve` 在岗位规则且 `Directory == nil` 时返回 `ReasonNoAssignee`。
  - `makeTasks` 把任务建成 `paused`，记告警 `flow_no_assignee`。订单照常变成 `submitted`。
- 一致。

**配了指定个人**
- 文档：候选就是这个人。设计文档只写了“岗位上只有提交人自己时暂停”。
- 代码：`resolve` 的 Person 分支取 `b.Principal`，之后排除发起账号，有员工组件时还排除发起人这个人。指定的个人就是提交人（或与提交人是同一员工）时，候选为空，任务暂停（`no_assignee`）。
- 一致，但设计文档没写指定个人这一种暂停情形。

**政策不要审批时，订单之后能不能收货**
- 文档：PO03 留下无需人工审批的已批准实例，提交人即批准人。PO07 收货要过放行核对。
- 代码：
  - `startApproval` 设 `s.Automatic = true`，订单转 `approved`，`ApprovedBy` 是提交人。
  - `flow/instance.go` 的 `StartIn` 直接写入 `approved` 的实例，没有任务。
  - 收货时（`receipts.go`）先过生命周期表，再调 `orders.Released`，也就是 `ReleaseIn`。凭这条 `approved` 实例的关键修订号和依据摘要放行。
  - 订单流程定义的 `Manual` 为 false，所以允许自动启动。
- 一致。

## 2. 采购订单驳回、修订与取消

**驳回要不要意见、状态与原因来源**
- 文档：PO05，必须附意见；实例 `returned`，订单回草稿，意见是原因。P17.1 说没有意见的拒绝答 `REQUEST_INVALID`，在调用者看到任务之后检查。
- 代码：
  - `orders.Flow()` 设 `RejectComment: true`、`OnReject: flow.Returned`。
  - `flow/decisions.go` 的 `decideIn` 在可见性检查之后查意见，没有就答 `REQUEST_INVALID`。
  - `FlowEnded` 在实例为 `Returned` 时执行 `Reject`，`Set{Reason: i.Ending.Comment}`，订单回 `draft`，原因取自决定者的意见。
  - 从待办走标准路由时，顺序与 P17.1 相符。
- 一致，旧的 `/reject` 路由除外，见不一致 C。

**不一致 C 的细节**
- 旧的 `orders.Action` 在 `decide` 之前就查 `in.Reason`（`orders.go` 的 `Action`）。
- 不是候选的人用空意见调旧 `/reject`，得到 `REQUEST_INVALID`，而不是 `NOT_FOUND` 或 `NOT_ASSIGNEE`。
- 文档没提这个分叉。

**之后再提交，审批是不是同一个实例**
- 文档：PO05 写“修改后再提交是新的实例”。P17.4 写 `returned` 是终态，只有 `running` 或 `approved` 的实例受唯一约束。
- 代码：`StartIn` 每次生成新的 UUIDv7 实例，旧的 `returned` 实例不受唯一约束。
- 一致。

**修订、取消的实例变化**

| 动作 | 文档 | 代码 | 实例变成 |
| --- | --- | --- | --- |
| 已批准订单修订 | PO06 | `ReviseOrder` 先调 `SupersedeIn`，再 `startApproval` | 旧实例 `superseded`，新开一个实例（不要审批的政策则新开一个直接 `approved` 的实例） |
| 已批准订单取消 | PO11 | `Action` 的 Cancel 分支，`o.State == Approved` 时用 `SupersedeIn` | `superseded` |
| 待审批订单取消 | PO11 | 同一处，其余状态用 `WithdrawIn` | `withdrawn` |

- 取消只在没有任何收货、验收时才行，由 `GuardNothingStarted` 把关。
- 以上三项一致。

## 3. 同一员工的两个账号 A、B

**装了员工组件**
- 文档：PO04 以人为单位，同一员工的两个账号算一个人。P17.8 写排除发起人这个人。P17.10 的检查顺序里，自审排在“是候选”之前。
- 代码：
  - `resolve` 用 `Directory.PersonOf` 比较，排除与发起人同一个人的账号，所以 B 不在候选里。
  - `decideIn` 里 `s.Self` 比较调用者这个人与记下的发起人这个人、发起账号现在归到的人。`Decide`（`flow/decide.go`）检查顺序是 `TASK_NOT_PENDING`、`VERSION_CONFLICT`、`SELF_APPROVAL`、`NOT_ASSIGNEE`……
- 结论：B 不能批准。
  - 走旧的 `/approve`：`DecideDocument` 会选到任务，答 `SELF_APPROVAL`。
  - 走标准路由：B 既非候选、发起人、决定者，也没有读权时答 404；有订单读取权，看得见任务，答 `SELF_APPROVAL`。
- 一致。

**没装员工组件**
- 文档：BRICKKIT 与依赖表写职责分离只能比较账号，同一个人的第二个账号能批自己提交的单据。P17.12 同。
- 代码：`Directory == nil` 时 `PersonOf` 返回账号本身。
- 结论：
  - 政策配的是指定个人 B（只有这种配法有候选）：B 与 A 账号不同，不算自审；B 是候选，有操作权，能批准，什么错也不答。
  - 政策配的是岗位：任务是 `paused`、没有候选，B 答 `TASK_NOT_PENDING`。
- 一致。

**候选里有没有 B**
- 代码：有员工组件时没有，被排除；没装员工组件时，只有政策指定 B 才有。
- 一致。

## 4. 同一个幂等键发两次“同意”，再用不同键发一次

**标准路由 `POST /be/flow/tasks/{id}/decisions`**
- 文档：P17.11，同一键重放答同一结果；不同键对已决定的任务答 `TASK_NOT_PENDING`。
- 代码：`flow/routes.go` 的 `decideRoute` 经 `idem.FromHTTP` 取键。`Kernel.Decide` 用 `idem.Do` 包住 `decideIn`。
- 结论：
  - 同一键第二次：重放首个结果，状态 200，不新增决定。
  - 不同键：`Decide` 里任务已是 `decided`，答 `TASK_NOT_PENDING`。
  - 全程只有一个决定，`be_flow_decision` 以 `task_id` 唯一。
- 一致。

**旧的 `/api/purchase/orders/{id}/approve`，不带幂等键**
- 文档：P17.14，没给键时以“任务 + 调用者 + 决定”为键，幂等比较的是决定与意见（不含版本）。BRICKKIT 写 `Idempotency-Key` 可选。
- 代码：`DecideDocument` 在 `key == ""` 时用 `"flow:" + task + ":" + choice`。
- 采购订单和申请的 `decide` 前面还有一道生命周期表：订单已批准时，`Lifecycle.Decide(approved, Approve)` 是 `Ignore`，直接返回 200 与当前订单，请求不再走到内核。
- 结论：重复 `/approve` 答 200 与当前订单，不产生第二个决定；对已批准订单再 `reject` 是生命周期表的拒绝。
- 一致。重放在这条旧路由上走的是生命周期表的忽略，不是内核的幂等键重放，结果相同。

## 5. 采购的放行核对：PO07、PO08、PR06

**什么时候被拒、答什么**
- 文档：PO07、PO08、PR06，答 `NOT_RELEASED`；`BRICKKIT.md` 写 409。
- 代码：
  - `orders.Released` 和 `requisitions.released` 调 `ReleaseIn`，不满足时转成 `core.ErrNotReleased`（409）。
  - 消息是“单号: 原因”，原因由 `ReleaseIn` 给出：没有已批准的实例、关键修订号不同、依据摘要数量不同、第 N 步依据摘要变了。
  - 调用处：
    - 收货：`receipts.go` 的 `CreateReceipt`。
    - 验收：`acceptances.go`。
    - 申请转订单：`requisitions/ordering.go` 的 `Apply`。
  - 前提是先通过生命周期表（收货和验收要订单 `approved`）。PR06 还先核对同法人、同产品、同单位。
  - 放行核对只在“取用”时做，退回（数量为负）不查。
- 一致。

**依据摘要包含的字段**

| 单据 | 文档 | 代码 | 摘要字段 |
| --- | --- | --- | --- |
| 订单 | PO03 | `orders/approval.go` 的 `basis` | 供应商、币种、每行的产品、数量、单位、单价，合计 |
| 申请 | PR02 | `requisitions/approval.go` 的 `basis` | 每行的产品、数量、单位 |

- 订单的关键修订号是订单的修订号，申请固定为 1。
- 一致。

## 6. 付款申请的驳回、取消与认领释放

**待审批时被审批人驳回**
- 文档：PR03，实例退回，申请回草稿，意见是原因，认领在同一事务里排一个释放的工作项（决定的事务里不调财务），再提交用新的认领身份。
- 代码：`requests/approval.go` 的 `FlowEnded` 在 `Returned` 时：
  - 用 `m.RT.Work.Enqueue(…, JobReleaseClaims, …)` 排释放工作项；
  - 清掉各行的 `claim_id` 与 `claim_expires_at`；
  - 把状态改成 `draft`，原因是意见。
- 工作项之后由 `ReleaseClaims` 到财务释放，释放是异步的。
- 一致。

**已批准、未放行时被驳回**
- 文档：PR03 表中“批准 → 驳回：写明原因 → 草稿”，这是本组件的规则，不是任务的决定。先释放认领，已批准的实例被取代，回草稿。
- 代码：
  - 生命周期表里 `Approved` 的 `Reject` 是 `Guard: GuardReason`，不走内核。
  - `giveBack` 先在事务外 `releaseAll`（同步向财务释放，释放是幂等的）。
  - `moved` 里 `endApproval` 对 `Approved` 或 `Ready` 调 `SupersedeIn`，清认领，状态改 `draft`，原因取这次驳回的意见。
  - 意见必须有，`Action` 在读单据之前就检查。
- 一致。

**取消已放行的（`ready`）**
- 文档：PR07，`submitted`、`approved`、`ready` 取消时同时向财务释放认领；已批准的实例被取代；已付的不能取消。
- 代码：
  - 生命周期表里 `Cancel` 的 `Ready` 格是移到 `Cancelled`，`Paid` 格拒绝。
  - `giveBack` 同样先 `releaseAll`，再在事务里 `endApproval`。`Ready` 走 `SupersedeIn`，状态变 `cancelled`。
- 一致。

## 7. 调拨与收付批准即过账

**汇率何时取、为什么不在批准时取**
- 文档：BE02，提交时取汇率快照（按单据日期，事务之前取证）；批准即过账在决定的事务里，用提交时的汇率快照。设计文档说明批准时不能再取证，决定的事务里不调用别的组件。
- 代码：
  - `entries/actions.go` 的 `Action`：Submit 在事务之前调 `masterdata.RateOf`（日期是 `cur.EntryDate`），再经 `startApproval` 写进 `bank_entry.rate`。
  - `entries/approval.go` 的 `FlowEnded` 读回这个快照，交给 `apply`。`apply` 的 Approve 在决定事务里发会计事实并改状态，状态由 `d.To` 定：手续费、利息是 `posted`，调拨是 `in_transit`。
  - 到账（`Arrive`）按到账日期另取一次汇率，与批准无关。
- 一致。

**驳回要不要意见**
- 文档：BE02，驳回必须附意见、回到草稿。
- 代码：
  - 流程定义 `RejectComment: true`、`OnReject: flow.Returned`。
  - 旧 `/reject` 路由在 `Action` 里先查意见。
  - 内核路由在 `decideIn` 里查。
  - `FlowEnded` 经 `apply` 的 Reject 分支写状态 `draft` 与原因。
- 一致。

## 8. 付款申请的放行人

**比较账号还是人**
- 文档：PR04 与“放行人与申请人分开”（设计文档“未决问题”）：不是申请人这个人，装了员工组件时按人，没装时比较账号。
- 代码：`requests/approval.go` 的 `notApplicant` 用 `m.Flow.PersonOf` 取放行人和申请人（`r.ApplicantID`）的人，比较人，另外也比较账号，相同答 `core.ErrApprover`（`APPROVER_IS_SUBMITTER`）。
- 结论：装了员工组件时，申请人的第二个账号也不能放行。
- 一致。

**没装员工组件**
- 文档：BRICKKIT 写职责分离只能比较账号，同一个人用第二个账号能批准或放行自己的付款申请。
- 代码：`Kernel.PersonOf` 在 `Directory == nil` 时直接返回账号，所以同一人的第二个账号能放行。
- 一致。

**付款政策能不能设成不要审批**
- 文档：设计文档规则表写“付款总要人审批，没有不要审批”。未决问题表写流程定义声明必须人工审批（P17.5）。
- 代码：
  - `policies.policyIn` 只有岗位、个人、版本三个字段，没有“要不要审批”。
  - `requests.Flow()` 与 `entries.Flow()` 都是 `Manual: true`。
  - `StartIn` 在 `Automatic && Manual` 时返回 `ErrManual`。
- 一致。

**不一致 A 的细节**
- 文档 `design.md:84` 的“拒绝的原因”写“批准人或放行人是申请人 `APPROVER_IS_SUBMITTER`”。
- 代码里批准走内核，答 `SELF_APPROVAL`；`APPROVER_IS_SUBMITTER` 只用于放行（`notApplicant`）。
- `BRICKKIT.md` 的写法是对的，这一行没跟上。

## 9. 统一待办：任务投影的发布者核对

四种情形的文档依据都是 WF01、WF09，代码依据都是 `projections.OnEvent` 与 `sources.Judge`。`from` 取信封的 `e.Source`。

| 情形 | 代码里的处理 | 结果 |
| --- | --- | --- |
| `erp/payment` 发 `erp.purchase_task.changed.v1`，任务类型是采购订单审批 | 形状合格；该任务类型的现在发布方是 `erp/purchase`；`Judge` 里 `from` 不等于现在的发布方，也不是“已有任务的以前的发布方” | 返回 `not_the_chosen_publisher`。`reject` 写 `rejected_projection` 一行与一条安全审计，不改任何任务 |
| 以前的发布方，再发它已有任务的新版本 | `known` 为真，且 `from` 在 `Previous` 里，`Judge` 返回空 | 收下，按版本覆盖 |
| 以前的发布方发一个新任务 | `known` 为假 | 拒绝，`not_the_chosen_publisher` |
| 载荷里的 `component` 与信封来源不同 | `p.Component != from` | `malformed`，同样记录与审计，不改任务 |

- 以前的发布方那两行：配置里没有以前的发布方时，按第一行处理。
- 全部一致。

## 10. 统一待办：读取与标注

**我的待办**
- 文档：WF03，候选包含我、状态 `pending`，按截止（没有的按收到的时刻）排序，游标分页，可按任务类型、法人筛选。
- 代码：`worklist.Mine`：`t.state = 'pending'` 且 `task_candidate.current` 里有我；排序键 `coalesce(due_at, received_at)`，再按 `component`、`id`；筛选 `task_type`、`legal_entity_id`；游标三段。
- 一致。

**已办**
- 文档：WF04，决定的处理人是我的、已结束的任务，与我曾是候选的已结束任务；游标分页。
- 代码：`worklist.Done`：状态在 `decided`、`superseded` 之中，并且 `decided_by = me` 或我曾是候选（`task_candidate` 不限 `current`）；按 `received_at` 倒序。只能按任务类型筛选。
- 一致，“已结束”在代码里是 `decided` 或 `superseded`。

**读取一个任务**
- 文档：WF05，现在或曾经是候选、或是决定者才能看，否则 404。
- 代码：`worklist.Get` 按 `component`、`id`、`(decided_by = me 或曾是候选)` 查，查不到答 `NotFound`。路由要求 `?component=`。
- 一致。

**动作入口从哪里来**
- 文档：WF05、WF07，由所属组件推出，不取投影里的地址。
- 代码：`Action{Component: t.component, Path: "/be/flow/tasks/" + t.id + "/decisions"}`，`t.component` 来自表列，而表列由信封来源写入。
- 一致。

**可能不是最新**
- 文档：WF06，最后一次心跳与最后一份投影都早于阈值，默认 15 分钟（`WORKFLOW_STALE_AFTER`），只标 `stale`，不在本地关闭任务。
- 代码：`worklist.go` 的 `cols` 里 `t.state = 'pending' AND coalesce(greatest(last_heartbeat, last_projection), '-infinity') < now() - $1::interval`。这是查询里的列，没有任何写任务的路径，模块也没有写路由。从未见过动静的发布方，其待处理任务会被标 `stale`。
- 一致。

**`WORKFLOW_TASK_SOURCES` 写错格式**
- 文档：WF08，格式不对、同一任务类型写两次，成员启动失败。
- 代码：`workflow/module.go` 的 `New` 调 `sources.Parse`，出错就返回错误，成员不启动。检查的是：
  - 条目带 `=`，任务类型至少三段点分；
  - 组件 ID 形如 `a/b`；
  - 任务类型不重复。
- 一致。

**不一致 B 的细节**
- 文档：协议 P17.8、采购 `design.md` 规则要点、收付款 `BRICKKIT.md` 都写员工投影变化后重新解析暂停的任务。`flow/routes.go` 的 `Jobs` 注释也写“queued when the employee projection changes”。
- 代码：没有任何地方在投影变化时排 `be-flow-resolve`；该作业只是每分钟跑一次的 `Singleton`（grep 只找到定义和注册）。
- 效果是暂停的任务最多晚约一分钟转 `pending`，没有数据错误。文档与注释说的“变化后立即重新解析”没实现。

## 顺带发现

- `infra/workflow/docs/design.md` 的实现状态写着“3.0.1：{version}：…”，采购、收付款的 `design.md` 实现状态也有多处 `{version}`，是没替换的占位符。
- 没有其他与你的问题相关的差异。
