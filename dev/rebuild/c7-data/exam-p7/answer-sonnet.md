以下是十题的核对结果。我没有改任何文件，也没有运行测试，结论都来自读文档和代码。

**读取的范围**
- 三个组件：`infra/workflow`（`docs/design.md`、`BRICKKIT.md`、各层 `AGENTS.md`、`workflow/`、`internal/*`）、`erp/purchase`、`erp/payment`。
- SDK 与线协议：`tools/be-sdk-go/flow`、`tools/be-protocol/spec/17-flow-kernel.md`。
- 契约：未读 `contract/` 目录。
- 单据：文档的 PO/PR/BE 编号都直接查了对应表格与规则；`internal/*/approval.go` 和 `internal/policies/policies.go` 逐文件读了，`orders.go`、`requisitions.go`、`actions.go` 只读了相关段落。

**总体：十题的主流程文档与代码一致。找到 5 处细节不一致（写在各题里，末尾汇总），没有发现主流程上的矛盾。**

---

## 1. 采购：政策与审批人

**文档依据**
- `purchase/docs/design.md`：PO03（第 82 行）、PR02（第 110 行）、“规则要点”的审批人（第 131 行）。
- `purchase/BRICKKIT.md`：“部署前准备”的审批一条（第 22 行）。
- 线协议 P17.3、P17.5、P17.8。

**代码依据**
- `internal/policies/policies.go`：`Policy.Approver`、`Of`。
- `internal/orders/approval.go`：`startApproval`。
- `internal/orders/orders.go`：`Action` 的 `GuardPolicy` 分支，在事务里调用。
- SDK：`flow/instance.go` 的 `StartIn`、`resolve`、`makeTasks`；`purchase/module.go` 的 `New`。

**CN01 要审批而没配审批人**
- `Approver()` 返回 `NO_APPROVER_CONFIGURED`（409），整个提交事务回滚，订单留在草稿。
- 从未设过政策的法人，起始值就是“要审批、没有审批人”，所以也会这样答。

**政策配了岗位但没有 mdm/employee**
- `flow.NewEmployees` 返回 `ok=false`，`Directory` 为 nil。
- `resolve` 对岗位规则返回 `no_assignee`，任务以 `paused` 建成，并写告警日志 `flow_no_assignee`。
- 订单照常变成 `submitted`，但没人的待办里会有这个任务。有 `erp.purchase.flow.manage` 的人在 `GET /be/flow/tasks?state=paused` 能看到它。
- 每分钟的 `ResolvePaused` 会重试，之后仍是 `no_assignee`。

**配了指定个人**
- 绑定是 `Binding{Principal}`，候选人就是该主体。
- 如果该主体就是提交人，或和提交人是同一个人，候选为空，任务暂停（`no_assignee`）。
- 个人规则没有“岗位在岗”的资格检查。

**政策不要审批时，订单之后能收货吗**
- 能。`StartIn` 带 `Automatic` 启动，不建任务，直接留下 `approved` 的实例，带修订号和依据摘要，订单直接变成 `approved`，提交人即批准人。
- 收货时 `Released` 调 `ReleaseIn`，凭这条已批准实例的修订号与摘要放行。
- 采购的流程定义没设 `Manual`，所以允许自动启动。

**结论：一致。**

---

## 2. 采购订单的驳回、重提、修订与取消

**文档依据**
- `purchase/docs/design.md`：PO04–PO06、PO11。
- 线协议 P17.1、P17.4、P17.6。

**代码依据**
- `orders/approval.go`：`Flow`（`RejectComment: true`、`OnReject: Returned`）、`FlowEnded`。
- `orders/lifecycle.go`：`Transition` 写 `reason`。
- `orders/orders.go`：`ReviseOrder`（第 248 行）、`Action`（第 358–362 行）。
- SDK：`flow/decisions.go` 的 `decideIn`（第 103 行）、`flow/instance.go` 的 `end`。

**驳回要不要意见**
- 要。没有意见答 `REQUEST_INVALID`。
- 实例结束为 `returned`，订单回到 `draft`。
- 原因取自决定里的意见：`FlowEnded` 把 `i.Ending.Comment` 经 `Set.Reason` 写进 `purchase_order.reason`。

**再提交是不是同一个实例**
- 不是。`StartIn` 每次生成新的 UUIDv7。唯一约束只针对 `running` 或 `approved`，已结束的不挡。

**三种变动对审批实例的影响**
- 已批准订单修订：`SupersedeIn`，旧实例变 `superseded`，再按新修订启动新实例（政策不要审批时直接批准）。
- 已批准订单取消：`SupersedeIn`，实例变 `superseded`。
- 待审批订单取消：`WithdrawIn`，实例变 `withdrawn`。
- 三种情况下，实例里待处理或暂停的任务都转 `superseded`。

**结论：一致，但有一处细节不一致。**
- 不一致：线协议 P17.1 要求“没有意见的拒绝”在调用者能看到任务之后才检查。
- 原来的 `reject` 路由在 `orders.go:300` 先查意见，再进内核，所以不是候选的人会先收到 `REQUEST_INVALID`，而不是 `NOT_FOUND` 或 `NOT_ASSIGNEE`。
- 同样的写法还出现在 `requisitions.go:279`、`payment/requests/actions.go:48`、`payment/entries/actions.go:35`。
- 标准路由 `POST /be/flow/tasks/{id}/decisions` 的顺序是对的（`decide.go:100–106`）。

---

## 3. 同一员工的两个账号 A、B

**文档依据**
- `purchase/docs/design.md`：PO04（第 83 行）、依赖表的 `mdm/employee` 一行（第 175 行）。
- `purchase/BRICKKIT.md`：第 22 行。
- 线协议 P17.8、P17.10、P17.12。

**代码依据**
- SDK：`flow/instance.go` 的 `resolve`（第 195–209 行）、`flow/decisions.go` 的 `decideIn`（第 109–120 行）和 `visible`、`flow/employees.go` 的 `PersonOf`、`flow/decide.go` 的 `Decide`。

**装了员工组件时**
- `resolve` 把和发起人同一个人的账号排除出候选，B 不在候选里。
- 如果 B 是岗位上唯一的人，任务暂停为 `no_assignee`。

**B 去批准**
- 先看 B 能不能看到这个任务：B 不是候选、发起人或决定者，只有拥有 `erp.purchase.order.read` 才可见，否则答 `NOT_FOUND`。
- 可见时，检查顺序是 `TASK_NOT_PENDING`、`VERSION_CONFLICT`，然后 `SELF_APPROVAL`（403）。`SELF_APPROVAL` 排在 `NOT_ASSIGNEE` 前面，所以不是 `NOT_ASSIGNEE`。
- 走原来的 `approve` 路由时，要先过 `erp.purchase.order.approve` 的授权，再进同样的内核检查。

**没装员工组件时**
- `PersonOf` 退回账号本身，A、B 是两个人，B 不会触发 `SELF_APPROVAL`。
- 岗位规则没有候选（`no_assignee`）。
- 如果政策指定的个人恰好是 B，B 是候选，可以批准，这正是文档写明的 P17.12 风险。

**结论：一致，另有一个代码隐患。**
- 隐患：`decide.go:123–124` 对 `Position` 步且任务 `Pending` 直接调 `k.Directory.Holds`，没判 nil。
- 触发条件：任务建成时有员工组件，之后部署去掉 `mdm/employee`，这个待处理任务再被决定。此时会空指针 panic，而不是线协议 P17.8 写的“没有员工投影时按 `no_assignee` 处理”。
- 平常的路径碰不到，只在中途拆掉员工组件时才会出现。

---

## 4. 幂等键

**文档依据**
- 线协议 P17.11、P17.14。
- `purchase/BRICKKIT.md` 第 49 行：标准路由要 `Idempotency-Key`，原路由可选。

**代码依据**
- `flow/routes.go` 的 `decideRoute`、`idem/idem.go` 的 `FromHTTP` 与 `Do`、`flow/decisions.go` 的 `Decide` 与 `DecideDocument`。
- `orders/approval.go` 的 `decide`（第 139–140 行）。

**标准路由，同一键发两次**
- 第二次由 `idem.Do` 直接重放第一次的结果，返回 200，原样返回第一次的任务内容，不再进入检查，也不产生第二个决定。

**标准路由，不同的键再发一次**
- 任务已经 `decided`，第一条检查就失败，答 409 `TASK_NOT_PENDING`，什么也不改，只写一条审计。

**记下几个决定**
- 一个。每个任务至多一个决定。

**缺键**
- 标准路由不带键，`FromHTTP` 答 400 `REQUEST_INVALID`。

**原来的 approve 路由不带键**
- 内核以 `flow:<任务>:<决定>` 为键。
- 订单一旦批准，订单状态机的 approve 在 `approved` 一格是“忽略”，路由直接返回 200 和当前订单，不再进内核。所以第二次再发，无论带不带键、同键异键，都是 200，也只有一个决定。

**结论：一致，另有两处细节不一致。**
- 不一致 1：P17.11 写“作用域是任务与调用者”，代码是（调用者, 键）。任务只通过请求指纹里的目标路径体现，同一个键用在另一个任务上，答的是 `IDEMPOTENCY_KEY_REUSED`，不是两个独立的键。
- 不一致 2：P17.14 写“再没有就取任一待处理任务，由 P17.10 答原因”，对已决定的单据异键重发应是 `TASK_NOT_PENDING`。但原路由的状态机“忽略”格在前面拦住，答 200。这与组件设计文档的表一致，不过和协议文字有出入。

---

## 5. 放行核对

**文档依据**
- `purchase/docs/design.md`：PO07（第 86 行）、PO08（第 87 行）、PR06（第 114 行）。
- 线协议 P17.7。

**代码依据**
- SDK：`flow/instance.go` 的 `ReleaseIn`、`ErrNotReleased`。
- `orders/approval.go` 的 `Released`、`basis`。
- 调用处：`receipts/receipts.go:177`、`acceptances/acceptances.go:161`、`requisitions/ordering.go:81`。
- 摘要定义：`requisitions/approval.go` 的 `basis`、`keyRevision`。

**什么时候被拒、答什么**
- 都答 409 `NOT_RELEASED`，消息是 `<单号>: <原因>`。原因共四种：
  - `no approved instance`（没有已批准的实例）
  - `the approval is of key revision X, the document is at Y`（关键修订号不同）
  - `the steps' digests differ`（摘要数量不同）
  - `step N's approval basis changed`（第 N 步依据变了）
- 收货和验收是在 `idem.Do` 的事务里，先过订单状态机的 `Receive` 或 `Accept` 一格，通过之后才做放行核对。所以草稿、待审批订单先答状态拒绝，不是 `NOT_RELEASED`。
- 申请转订单（PR06）只在“取用”（数量为正）时核对，退回数量不核对；同样先过申请状态机，再核对。
- 实际会碰到 `NOT_RELEASED` 的情形：3.0.6 及之前批准的单据没有实例，或批准之后依据与实例对不上。

**依据摘要包含的字段**
- 订单：供应商、币种、每行的产品、数量、单位与单价、合计；关键修订号是订单修订号。
- 申请：每行的产品、数量与单位；关键修订号固定为 1。
- 付款申请：种类、收款方、账户、币种、金额，加每行的未清项与金额。

**结论：一致。**

---

## 6. 付款申请的驳回与取消

**文档依据**
- `payment/docs/design.md`：PR03（第 77 行）、PR04、PR07（第 81 行）、PR08。
- 线协议 P17.6。

**代码依据**
- `requests/approval.go`：`FlowEnded`（第 90–128 行）、`endApproval`（第 147–155 行）。
- `requests/actions.go`：`giveBack`（第 223–244 行）、`release`。
- `requests/lifecycle.go`：只有 `Submitted` 一格带 `GuardFlow`（第 63、70 行）。

**待审批时被审批人驳回**
- 走内核的决定，实例 `returned`。
- 在 `FlowEnded` 里，同一个事务：把认领的释放排成工作项 `release-claims`，清掉各行的认领，申请回到 `draft`，原因取自意见。
- 事务里不调用财务；释放在提交之后由工作项做，对财务幂等，财务不可达时无限重试。

**已批准、未放行的申请被驳回**
- 不是任务的决定，状态机里该格没有 `GuardFlow`，由 `giveBack` 处理。
- 先在事务外同步向财务释放全部认领；财务不可达就答 `DEPENDENCY_UNAVAILABLE`，什么也不改。
- 再在一个事务里：`SupersedeIn` 取代已批准的实例，清空认领，申请回 `draft`，原因写进去。
- 驳回必须有意见（`actions.go:48`）。

**取消已放行（ready）的申请**
- 同样走 `giveBack`：先同步释放已确认的认领，再事务里 `SupersedeIn`，申请变 `cancelled`。
- 取消待审批的申请用 `WithdrawIn`，实例变 `withdrawn`；已付的申请拒绝取消。

**结论：一致。** 文档 PR07 没点名 `ready`，但“`submitted`、`approved`、`ready`”和代码 `endApproval` 的覆盖相同。

---

## 7. 调拨与收付批准即过账

**文档依据**
- `payment/docs/design.md`：BE02（第 112 行）、`bank_entry` 一行（第 48 行）、规则要点“事务里不调用别的组件”（第 141 行）。
- `payment/internal/entries/AGENTS.md`。

**代码依据**
- `entries/actions.go`：第 66–79 行（汇率在事务前取）、`apply` 的 Approve 分支（第 142 行）。
- `entries/approval.go`：`startApproval`（第 101 行存汇率）、`FlowEnded`（第 81–91 行读存下的汇率）。

**汇率何时取**
- 在提交时、事务之前取，按单据日期取（到账另按到账日期取）。
- `startApproval` 把它写在 `bank_entry.rate`，批准时 `FlowEnded` 读出来用于过账。

**为什么不在批准时取**
- 批准是内核的决定，在决定的本地事务里，不能再发网络调用（取汇率要调 `mdm/currency`）。

**驳回要不要意见**
- 要。`Flow` 声明 `RejectComment: true`，`Action` 里 `entries/actions.go:35` 也预先检查。实例 `returned`，单据回到草稿，原因是意见。

**结论：一致。** 驳回意见的检查顺序同第 2 题的不一致。

---

## 8. 付款放行人与付款政策

**文档依据**
- `payment/docs/design.md`：PR04（第 78 行）、未决问题（第 247、248 行）。
- `payment/BRICKKIT.md`：第 22 行。
- 线协议 P17.5、P17.12。

**代码依据**
- `requests/approval.go`：`notApplicant`（第 173–189 行）、`Flow` 与 `entries.Flow` 的 `Manual: true`。
- SDK：`flow/kernel.go` 的 `PersonOf`、`flow/instance.go` 的 `StartIn`（`ErrManual`）。
- `payment/internal/policies/policies.go`。

**放行人与申请人比较的是什么**
- 比人：`m.Flow.PersonOf` 分别取放行人和申请人（`ApplicantID`）所属的人，再加上直接比账号。相同则答 409 `APPROVER_IS_SUBMITTER`。
- 没装员工组件时 `PersonOf` 退回账号，只能比较账号。

**付款政策能不能设成不要审批**
- 不能。
  - `Policy` 只有审批人岗位与个人，没有“不要审批”字段。
  - 流程定义声明 `Manual: true`，内核拒绝自动启动。
  - 付款侧的代码也从不设 `Automatic`。

**结论：基本一致，有一处文档过期。**
- 不一致：`design.md` 第 84 行把“批准人或放行人是申请人”统一写成 `APPROVER_IS_SUBMITTER`。
- 实际上批准人现在由内核答 `SELF_APPROVAL`（403），只有放行才答 `APPROVER_IS_SUBMITTER`。
- `BRICKKIT.md` 第 48 行写对了，只有 `design.md` 的那一行没改。

---

## 9. 统一待办：发布者核对

**文档依据**
- `infra/workflow/docs/design.md`：WF01（第 45 行）、WF08、WF09。
- `AGENTS.md` 易错点。
- 线协议 P17.15。

**代码依据**
- `internal/sources/sources.go`：`Judge`。
- `internal/projections/projections.go`：`OnEvent`、`reject`、`Subs`。
- `internal/core/names.go`：原因名。
- SDK：`events/consumer.go:111`（订阅过滤）。

**erp/payment 的服务身份发出 `erp.purchase_task.changed.v1`，任务类型是采购订单审批**
- 订阅按“流 + 事件类型”过滤。`erp.payment` 流的订阅只收 `erp.payment_task.*`，这条事件在传输层就进不来。
- 如果它真的到了 `OnEvent`：
  - 载荷里的 `component` 若是 `erp/payment`（等于信封来源），形状通过。
  - `Judge` 里该任务类型的现在发布方是 `erp/purchase`，来源不是它，且这个任务不是已有的 `(erp/payment, id)`，答 `not_the_chosen_publisher`。
  - 拒绝时记 `rejected_projection` 和一条安全审计，不改任何任务，也不更新发布方的“最后投影”时刻。
- 如果载荷里 `component` 写成 `erp/purchase`，来源仍是 `erp/payment`，则按 `malformed` 拒绝。

**以前的发布方再发一份它已有任务的新版本**
- 接受：`known && 在以前的发布方列表里` 通过 `Judge`，版本更大才覆盖。

**以前的发布方发一个新任务**
- 拒绝：`known` 为假，答 `not_the_chosen_publisher`。

**载荷里的 component 与信封来源不同**
- `malformed`，同样记表加审计。

**结论：一致。** 两点可以注意：
- `known` 只按 `(component, id)` 判断，不核对已存任务的类型。
- 审计只在 `RT.Audit` 非空时才写。

---

## 10. 统一待办：读取、陈旧与配置

**文档依据**
- `infra/workflow/docs/design.md`：WF03–WF08。
- `infra/workflow/BRICKKIT.md`：定位与配置指南。
- 线协议 P17.14、P17.18。

**代码依据**
- `internal/worklist/worklist.go`：`Mine`、`Done`、`Get`、`cols`、`Action`。
- `internal/projections/projections.go`：`seen`。
- `workflow/module.go`：`New`。
- `internal/sources/sources.go`：`Parse`。
- `internal/core/names.go`：默认阈值。
- SDK：`flow/routes.go` 的 `Heartbeat`。

**我的待办**
- 包括：状态 `pending`，且我是当前候选。
- 可按任务类型、法人筛选。
- 排序：按 `coalesce(due_at, received_at)` 升序，再按 `component`、`id`；游标分页。

**已办**
- 包括：状态是 `decided` 或 `superseded`，且我是决定者，或我曾是候选。
- 排序：`received_at` 降序，再按 `component`、`id` 降序；游标分页。

**读取一个任务**
- 必须带 `?component=`。
- 我现在或曾经是候选，或我是决定者，才能读，否则 404。
- 发起人与有单据读取权的人不在待办里看，要去所属组件。

**动作入口从哪里来**
- 由任务所属的 `component` 推出：`Action{Component, "/be/flow/tasks/<id>/decisions"}`，不取投影里的地址。

**什么时候标“可能不是最新”**
- 只标 `pending` 的任务，条件是发布方的最后心跳和最后投影都早于 `now() - WORKFLOW_STALE_AFTER`（默认 15 分钟）。
- 只是返回 `stale` 标志，代码里没有写入路径，不会在本地关闭任务。

**WORKFLOW_TASK_SOURCES 格式错**
- `Parse` 返回错误，`New` 把它返回，成员启动失败。
- 以下都算格式错：缺 `=`、任务类型或组件 ID 格式不对、同一类型写两次、结尾多逗号。
- 配置为空则没有订阅，待办是空的。

**结论：一致，另有一处文档含糊。**
- 含糊：`projections.go:118` 在每次版本覆盖时都把 `received_at` 重置为现在。
- 所以没有截止时间的任务，排序用的是“最近一版到达的时刻”，不是首次到达。
- 文档只写“按收到的时刻”，没说是哪一次。

---

## 不一致与隐患汇总

| 编号 | 位置 | 文档说的 | 代码做的 |
| --- | --- | --- | --- |
| a（第 2、7 题） | 原 `reject` 路由 | 意见要在能看到任务之后检查（P17.1） | 先查意见，再进内核；不是候选的人先收到 `REQUEST_INVALID` |
| b（第 4 题） | 幂等键 | 作用域是任务与调用者（P17.11） | 作用域是（调用者, 键），同一个键用在别的任务上答 `IDEMPOTENCY_KEY_REUSED` |
| c（第 4 题） | 原路由重复同意 | P17.14 暗示异键重发答 `TASK_NOT_PENDING` | 状态机“忽略”格先拦，答 200 |
| d（第 8 题） | `payment/docs/design.md:84` | 批准人是申请人答 `APPROVER_IS_SUBMITTER` | 批准由内核答 `SELF_APPROVAL`，只有放行答 `APPROVER_IS_SUBMITTER` |
| e（第 3 题） | `flow/decisions.go:123` | 无员工投影时按 `no_assignee` 处理（P17.8） | 对已有待处理的岗位任务，若部署之后去掉员工组件，决定时会空指针 panic |

另有一项文档含糊：第 10 题的 `received_at` 语义。

我没验证消息系统按服务身份限制谁能在哪个流上发布这一点，也没查心跳事件是否做发布方核对。第 9 题关于传输层过滤的说法只依据订阅的 `filters` 构造代码。
