**总体结论：**8 题里 7 题文档与代码一致，1 题不一致（第 3 题）。第 2 题两边一致，但审批的“同一个人”判断在代码里还没有实现。我没有改任何文件，也没有跑测试，只读了文档和代码。

路径省略了 `components/`：`E/` 是 `mdm/employee`，`A/` 是 `infra/authz`，`docs/zh/` 是装配项目的正式文档。

## 1. 张三调岗：原任职怎么变，新任职是新记录吗

- **文档依据：**`E/docs/design.md` 的“状态与规则 / 不变量”写了：调岗不改原任职，结束原任职（原因 `transfer`，最后一天是调岗日的前一天），新建一条任职，一次办理。调岗日不晚于今天，将来的调岗要拆成“给原任职写结束日期 + 新建计划中的任职”。`E/AGENTS.md` 的“设计取舍”和 `docs/zh/06-protocols/security/04-…` 第 102 行写了原因：法人、部门、岗位有安全含义，授予按任职实例绑定，原地改会让旧授予跟到新岗位。
- **代码依据：**
  - `E/internal/appointments/appointments.go` 的 `Transfer`：日期晚于今天就拒绝；在同一个事务里先调 `end(…, dayBefore(date), "transfer")`，再调 `insert(…)` 新建任职。
  - `insert` 做重叠检查，不重叠才写入。
  - `end` 把状态改成 `ended`，写入结束日期和原因。
  - 原任职的结束先写意图证据（`AppointmentEnd`）。
  - `UpdateAppointment` 只能改备注。
- **授权一侧：**`A/internal/employment/appointments.go` 的 `Closures`：任职状态变了就登记闭包，绑定旧任职的授予记为 `source_ended`。
- **结论：一致。**
- **文档没写的一点（顺带发现）：**`Transfer` 只用新岗位所在部门的路径调 `admit`，没有对原任职的部门做权限检查。部门级的人事管理员可能结束别的部门的任职。文档和代码都没有说这是有意的。

## 2. 两个账号发起与审批：谁判断“发起人与审批人是同一个人”

- **文档依据：**
  - `docs/zh/06-protocols/09-approval-and-workflow.md` 第 91 行：按人比较，同一个人的第二个账号不能审批本人发起的单据。
  - `D10`（`docs/zh/02-decisions/03-…`）。
  - `docs/zh/06-protocols/security/02-…` 第 98 行。
  - `E/docs/design.md` 的“验证故事”：关联与水位已做，“按人检查”由授权组件的确认与审批承接。
- **代码依据：**
  - `E/internal/links/links.go` 的 `EmployeeOfAccount` 能查“账号属于哪个员工”。
  - `A/internal/employment/person.go` 的 `PersonOf` 和 `Shares`，加上 `A/internal/effectpoint/confirm.go` 的 `Independent`，只用于确认人的独立性和安全处置。
  - `infra/workflow` 目前只有 `README.md`，审批引擎的代码没有。
- **结论：一致，但这个检查还没有实现。**协议 09 规定由审批引擎（`infra/workflow`）判断，两个组件都不判断。现在没有任何代码会拒绝张三的这次审批。

## 3. 把账号 bob 关联到李四：步骤、谁确认、没有确认的结果

- **文档依据：**`E/docs/design.md` 的“账号关联是受保护操作”三步；`A/docs/design.md` 第 105 行；`docs/zh/…/08-state-and-change-protocol.md` 第 21 行。
- **步骤（代码）：**
  1. 授权管理员调 `POST /api/authz/confirmations`，带 `employee`、`account`、`action=link`、`employee_version`。入口是 `A/internal/accounts/links.go` 的 `ConfirmLink`。
  2. 人事调员工组件，带 account、version、confirmation。这个调用需要 `mdm.employee.account_link.manage`。
  3. `E/internal/links/links.go` 的 `LinkAccount` 先查版本、是否离职、账号是否已关联，再调授权组件的 `CheckLinkChange`，最后在事务里复核版本和确认是否已用，写入关联。
  4. 授权组件从员工水位流应用这条关联时，才消耗确认（`LinkChanged`）。
- **谁能确认（代码）：**`ConfirmerEligible` 要求确认人持有授权管理员资格。`Independent` 要求确认人不是申请人、bob、李四本人（同一员工的账号算一个人）。部署所有者的签名确认，`unlink` 任何时候可以代替；`link` 只在没有别的可用管理员时可以（`linkVerdict`）。
- **没有确认的结果（代码）：**
  - 没带确认：`linkVerdict` 返回 `CONFIRMATION_REQUIRED`，员工组件答 202，body 里 `reason: CONFIRMATION_REQUIRED`，什么也不改。
  - 确认不绑定这个员工、账号、动作、版本，或已用、已过期：返回 `REFUSED`，员工组件答 `PERMISSION_DENIED`。
  - 此刻证明不了确认人是否独立或合格：202，`reason: ADMIN_AVAILABILITY_UNPROVABLE`。
- **结论：不一致。**`E/docs/design.md` 写“没带确认或确认不符时答 `CONFIRMATION_REQUIRED`（202）”。代码里只有没带确认才是 202，确认不符、已用、已过期都是 `PERMISSION_DENIED`。`E/internal/links/AGENTS.md` 写的是“没带确认答 202、被拒答 `PERMISSION_DENIED`”，与代码一致，所以 `design.md` 需要改。

## 4. 最后一名授权管理员李四离职：会被拒绝吗，系统做什么

- **文档依据：**`E/docs/design.md`“最后的授权管理员”（D62）；`A/docs/design.md` 第 40 行和第 178 行（待恢复）；`docs/zh/07-components/mdm.md` 第 42 行。
- **代码依据：**
  - `E/internal/employees/employees.go` 的 `Terminate` 先调 `AdminWarning`，再办理离职。`AdminWarning` 只在响应里带 `last_admin_warning`，永不拒绝。
  - 离职不结束账号关联。
  - `Terminate` 通过 `Terminated` 钩子结束全部任职，并先写离职意图证据。
- **授权一侧（代码）：**`A/internal/employment/appointments.go` 的 `Closures` 只对任职结束和关联结束登记闭包，员工记录本身变成 `terminated` 不触发任何东西。
- **结论：一致，不拒绝。**但有两点要限定：
  - 警告的含义是“关联账号里有授权管理员”，不一定是“最后一名”。
  - 授权管理员资格绑定了任职时，离职才会通过任职结束使它失效，部署进入待恢复；没绑定任职的管理员资格不受离职影响，账号是否停用归身份组件。`A/docs/design.md` 第 40 行没写这个限定。
- **未核实：**我没有读 `A/internal/effectpoint/pending.go`，“进入待恢复”只按文档记录，没有核对代码。

## 5. `mdm/org` 退役有人任职的岗位

- **文档依据：**`mdm/org/docs/design.md` 第 148 行：退役时不检查谁还在引用，不读员工；`E/docs/design.md` 不变量：岗位退役时未结束的任职以 `position_retired` 结束，部门退役用 `unit_retired`。
- **代码依据：**
  - `mdm/org/internal/positions/positions.go` 的 `RetirePosition` 不查任职，只改状态并写证据。
  - `E/internal/orgview/orgview.go` 的 `positionChanged` 和 `unitChanged` 调 `endSoon`，排 `JobEndOnRetirement` 作业。
  - `E/internal/appointments/appointments.go` 的 `EndOnRetirement` 用法人的今天作为最后一天，结束这些任职，每条先写意图证据。
- **结论：一致。**`mdm/org` 不会拒绝。任职由员工组件消费事件后在作业里结束，是异步的，不在退役的事务里。`mdm/org` 拒绝的是“部门里还有启用岗位”，与岗位上有人无关。

## 6. 整套恢复到 T，T 之后王五离职

- **文档依据：**`docs/zh/06-protocols/15-backup-and-recovery.md` 第 203 行、第 206 行和 RC25：员工组件依据证据重新办理离职；只有意图的收紧也会执行，标为“意图未确认”。`E/docs/design.md`“安全来源”。
- **代码依据：**`E/internal/replay/replay.go` 的 `Replay` 对 `employee_tightening` 的 `termination`，调 `employees.ReplayTermination`。它不重做业务前置校验，把状态改成 `terminated`，调 `terminated(…)` 再次结束任职，写事件和审计，执行者是 `ops/recover`。员工记录不在就返回 `evidence.ErrDangling`，列入复核。
- **结论：一致。**恢复后王五是 `terminated`，任职已结束，关联不变，授权组件经投影重新得到这些事实。
- **缺口（两边都没有明说）：**将来才生效的离职，在录入时不写证据（`Termination.Due` 要求日期不晚于今天），只在作业到期时写。如果这样的离职是 T 之后才录入、且恢复时还没到期，恢复后它会丢失，王五仍是 `active` 且没有离职日期。

## 7. 离职日期是下个月 1 号

- **文档依据：**`E/docs/design.md` 员工状态表最后一行，以及“未决问题”：作业每分钟办理到期的，按法人业务日期。
- **代码依据：**
  - `Terminate`：日期晚于今天时，只把 `TerminationDate` 写入，状态仍是 `active`，也不写证据。
  - `Effective` 和 `effectiveIn`：`termination_date <= today` 时办理。到期那一天就生效，作业每分钟跑一次，到期后最晚一分钟生效。办理时会写证据并结束任职。
  - `WithdrawTermination`：状态是 `active` 且有离职日期时可以撤回。
- **结论：一致。**今天是 `active`，带离职日期；到期日由作业办理成 `terminated`；到期前可以撤回。极小的例外是：日期已到、作业还没跑的这最多一分钟内，代码仍允许撤回。

## 8. 有 `mdm.employee.appointment.manage` 能不能顺便给新任职的人授权

- **文档依据：**`E/docs/design.md`“任职维护权不等于授予权（D30）”；`E/BRICKKIT.md` 组件定位；`A/docs/design.md` 第 209 行：新任职的授权建议没做，现在由管理者手工授出并绑定任职。
- **代码依据：**
  - `E/employee/module.go` 里，`appointment.manage` 只挂在任命、调岗、结束、改备注这些路由上，处理函数只写 `appointment` 表和事件。
  - 员工组件对授权组件只调 `CheckLinkChange` 和 `Administrators`，没有授出的调用。
  - 授予在授权组件的生效点里做：要管理职责单元、包含证明和对应的操作权限。
- **结论：一致，不能。**授予必须由授权组件里的管理者另外办理。
