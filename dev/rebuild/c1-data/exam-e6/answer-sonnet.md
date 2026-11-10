下面逐题回答。我没有改任何文件。凡是只有一边写了的地方都单独标出。

**说明**：员工组件简称 E（`components/mdm/employee`），授权组件简称 A（`components/infra/authz`）。

---

## 1. 张三调岗：原任职怎样变，新任职是改原记录还是新记录

**文档依据**
- E `docs/design.md`“状态与规则”的不变量：调岗不改原任职。结束原任职（原因 `transfer`，最后一天是调岗日期的前一天），新建任职，一次办理。法人、部门、岗位都是有安全含义的字段，不原地改。只有备注这类显示字段可以原地改。
- E `AGENTS.md`“设计取舍”写了同一条。
- 装配项目文档：安全 04“任职事实与授予生命周期”。有安全含义的变化要结束旧的资格绑定、创建新的资格。
- A `docs/design.md`“术语”里的“任职绑定”：任职结束，授予立即不给，闭包记为 `source_ended`。

**代码依据**
- `internal/appointments/appointments.go` 的 `Transfer`，先调用 `end(..., dayBefore(date), "transfer")`，再调用 `insert(...)` 新建，两步在同一个事务里。
- `UpdateAppointment` 只改 `note`。
- `Transfer` 在锁内重新读取原任职，所以锁内会拒绝已结束的任职。
- 先写意图证据（`tightening.AppointmentEnd`），事务里写结论。
- A：`internal/employment/appointments.go` 的 `Closures`，任职状态变化会登记闭包。

**结论**：原记录变成 `ended`，`end_reason=transfer`，`end_date` 是调岗日的前一天，版本加一。新任职是新记录，开始日期是调岗日。绑在旧任职上的授予在视图里立即不给，闭包记为 `source_ended`。新任职的授权建议还没做，要管理者手工授出，文档也写了“随后做”。

一致。

**需要留意的一点**：`Transfer` 的 `admit` 只按目标岗位所在部门的路径检查 `appointment.manage`，没有用原任职所在部门的路径检查。文档说任职按法人和所在部门限定，但没说调岗要同时有两边部门的权限。这是文档没说清，不算文档与代码冲突。

---

## 2. 张三两个账号分别发起和审批，会怎样，哪个组件判断

**文档依据**
- 协议 09“职责分离（D10）”：比较以人为单位，同一个人的第二个账号不能审批本人发起的单据。没有员工组件时只能比较账号。
- E `docs/design.md`“验证故事”：“关联与水位已做；按人检查由授权组件的确认与审批（协议 09）”。
- A `docs/design.md`“术语”里的“自然人”：同一员工的全部有效账号算一个人，用于确认人的独立性和安全处置，没有提审批。

**代码依据**
- A 的 `employment.PersonOf`、`employment.Shares` 和 `effectpoint.Independent`，只被账号状态确认、账号关联确认、计划确认和生效点确认使用（`accounts/accountchange.go`、`accounts/links.go`、`plans/planhttp.go`、`effectpoint/confirm.go`）。
- 业务审批的职责分离没有实现：`components/infra/workflow/` 只有 README，没有代码。
- E 只提供按账号查员工的路由（`links.EmployeeOfAccount`）和 `mdm.employee.account_link.changed` 事件，没有“这两个账号是不是同一个人”的接口。

**结论**
- 按文档，业务审批的职责分离由审批契约承接，也就是 `infra/workflow`，在装配时由它按员工关联判断。授权组件只管授权的确认，E 只提供关联事实。
- 按代码，现在没有任何组件判断业务审批的人员级分离。张三能用另一个账号审批自己发起的单据。

**不一致**：E 的“验证故事”写“由授权组件的确认与审批（协议 09）”，措辞模糊。A 的实际范围只限于自己的确认，业务审批的按人检查哪个组件都没有。这一行本身标了待办（`infra/workflow` 是 C7），所以更像“尚未实现”，不算冲突。

---

## 3. 把账号 bob 关联到员工李四：步骤、谁能确认、没有确认时的响应

**文档依据**
- E `docs/design.md` 的“账号关联是受保护操作”三步。
- A `docs/design.md` 的“实现状态 3.0.46”：确认用 `POST /api/authz/confirmations`，带 `employee`、`account`、`action`、`employee_version`，绑定这四样。建立是放宽，有别的可用管理员时部署所有者不能代替。
- 装配项目文档：安全 08 的“确认与受保护操作”和第 21 行，独立指不同的自然人，对象本人不能确认。

**代码依据**
- 授权组件一侧：
  - 确认的建立在 `accounts/links.go` 的 `ConfirmLink`，用 `Independent` 排除 bob 和李四。
  - 之后由 `effectpoint.ConfirmerBasis` 处理确认的资格。
  - 写入 `authz_confirmation`。
- 员工组件一侧：
  - `links.LinkAccount` 先在事务外检查版本一致、员工未离职、账号未关联。
  - 再调用 `check`，也就是 A 的 `CheckLinkChange`。
  - A 的 `linkVerdict` 核对绑定一致、未用、未过期、确认人与申请人、账号、员工都不是同一个人、确认人此刻是合格的管理者。
  - 然后在事务里再核对员工版本，以及确认在本组件里是否已用过（`used`）。
  - 最后写关联，记录里带着 `confirmation`。
- 授权组件应用这条关联事件时才把确认标为已用（`LinkChanged`，`link:<关联>@<版本>`）。
- 部署所有者只在没有别的可用管理员时可以替代：`linkVerdict` 的 `BasisOwner` 分支，`OthersAvailable`。
- 没有确认：`linkVerdict` 在确认为空时返回 `CONFIRMATION_REQUIRED`，`check` 回 HTTP 202，带 `reason: "CONFIRMATION_REQUIRED"`，什么都不改。

**结论**：流程与文档一致，没有确认时得到 202 `CONFIRMATION_REQUIRED`。

一致。

**需要留意的一点**：E 的文档说“没有别的可用管理员时由部署所有者确认”，这句话只对建立成立。A 的代码和文档说，结束关联是收紧，所有者可随时代替。E 的文档没区分建立和结束，A 的文档里是完整的。

---

## 4. 李四是最后一名授权管理员，办理离职

**文档依据**
- E `docs/design.md`“最后的授权管理员（D62）”：离职与结束账号关联照常办理。办理前问授权组件，有就在响应里带 `last_admin_warning`，不阻止。
- 授权组件在可用的授权管理员变成零时让部署进入待恢复。
- A `docs/design.md`“规则”：来源侧的离职与停用照常生效，没有可用管理员时进入待恢复。
- 安全 04：来源事实不受阻止。AM17 同一结论。

**代码依据**
- `employees.Terminate`：调用 `m.AdminWarning`（即 `links.AdminWarning`，向 A 的 `AccountService.Administrators` 查询），结果放进响应的 `last_admin_warning`。任何情形都不拒绝。
- A：任职结束或关联结束会走 `employment.Closures`，然后 `effectpoint.CloseAfter`，闭包作业最后调用 `JudgeAdmins`（`effectpoint/closure.go`）。可证明没有可用管理员，就进入 `recovery_pending`。

**结论**：不会被拒绝。响应带 `last_admin_warning: true`。离职照常生效，全部任职结束。

**要注意**：关联不随离职结束，账号也不由员工组件停用。所以只有李四的管理持有资格绑定了任职（带 `appointment`），或者身份组件之后停用了他的账号，可用管理员才会变成零。管理持有没有绑任职时，他的账号仍是授权管理员，不会因离职进入待恢复。文档只说“可用管理员变成零时”进入待恢复，没有逐条列出这个触发条件。

另外，A 在任职结束与闭包之间按最后应用的事实判断持有资格的可用性，两者相差作业的延迟，这是 A 自己写明的。

一致。

---

## 5. `mdm/org` 退役有人任职的岗位

**文档依据**
- `mdm/org/docs/design.md` 第 54、55 行：部门里还有启用岗位不能退役，岗位的退役没有对任职的检查。
- 第 148 行：退役时不检查谁还在引用，员工组件消费退役事件，结束挂在岗位上的任职。
- E `docs/design.md` 的不变量：岗位退役时，未结束的任职以 `position_retired` 结束，部门同样（`unit_retired`）。

**代码依据**
- `mdm/org/internal/positions/positions.go` 的 `RetirePosition`，只做 `p.State = "retired"`，不会因为有任职而拒绝。
- E `internal/orgview/orgview.go` 的 `positionChanged` 和 `unitChanged`，发现退役就排队 `endSoon`。
- `internal/appointments/appointments.go` 的 `EndOnRetirement`，以 `position_retired` 或 `unit_retired` 结束，最后一天是该法人的今天，并写收紧意图。

**结论**：不会拒绝。任职由 E 消费 `mdm.org_position.changed` 事件后，在后台作业里结束，授权组件随后撤销绑定它们的授予。是异步的，有作业的延迟。

一致。

---

## 6. 整套恢复到 T，T 之后王五办了离职

**文档依据**
- 协议 15：证据存储不随恢复回退，T 之后的收紧按提交序号重放。“已生效”的证据在属主处重新执行，“员工组件重新办理离职”。“只有意图”的离职在该属主的已生效记录之后执行，并标“意图未确认”。
- E `docs/design.md` 的“安全来源”：离职是收紧，写意图证据，整套恢复后按证据重放，只查对象还在，不重做业务前置校验。
- 协议 15 第 64 行：由来源事实派生的撤销不另记证据，恢复后来源在属主处重新办理，授权组件经投影重新派生。

**代码依据**
- `employee/definition.go`（`Evidence: true`，`Replay`、`Recovery` 登记）。
- `employee/checks.go` 的 `Replays`，调用 `replay.Replay`（`internal/replay/replay.go`）。
- `employees.ReplayTermination`：对象不在时返回 `evidence.ErrDangling`，已离职则什么也不做，否则 `terminated(...)`，调用 `Terminated`（`appointments.Ended`）结束他的全部任职，写事件和审计。

**结论**：恢复后库里的王五先是 `active`。重放后他变成 `terminated`，任职以 `termination` 结束，与原来一致。授权组件经投影重新派生撤销。

**不能完全保证的情形**（文档与代码都一致，但要知道）：
- 证据既不在证据存储也不在告警渠道，或签名无效时，不自动重放，列入人工复核。
- 王五的离职日期在未来、T 之后才到期的，不会提前写证据。作业到期时才写意图，所以那时才有证据。T 之后到期的，恢复后只能靠作业重新办理，到期日已过则恢复后很快就办理。

一致。

---

## 7. 离职日期是下个月 1 号

**文档依据**
- E `docs/design.md`“状态与规则”：生效日期在之后，仍是 `active`，记下 `termination_date`，到期由作业办理，到期前可撤回。
- “未决问题”：到期由单例作业每分钟办理，按法人的业务日期，到期后最晚一分钟生效。
- “安全来源”：作业到期办理的离职也先写意图。

**代码依据**
- `employees.Terminate`：`d <= today` 才调 `terminated`，否则只记 `TerminationDate`。
- `tightening.Termination` 的 `Due` 要求 `date <= today`，所以未来日期的请求不写意图。
- 作业 `Effective`（`employee/module.go` 里每分钟）按每个法人的 `Today` 调用 `effectiveIn`，在那一刻写意图，调用 `terminated`，写结论。
- `employees.WithdrawTermination`：只在 `State == "active"` 且 `TerminationDate != nil` 时清空，这是用来撤回的。

**结论**：今天仍是 `active`，响应里能看到 `termination_date`。到了那天，作业在最晚一分钟内办理为 `terminated`，全部任职结束（最后一天是 `termination_date`）。到期前可用 `withdraw-termination` 撤回，需要 `mdm.employee.manage`。

一致。

---

## 8. 有 `mdm.employee.appointment.manage` 能不能顺便授权

**文档依据**
- E `docs/design.md` 的“命令与查询”：任职维护权不等于授予权（D30），`appointment.manage` 只改人事事实，授予由 `infra/authz` 的管理者办理。
- A `docs/design.md`：改变安全记录要 `infra.authz.security_record.change`，授出受管理上限与包含证明约束。
- E `docs/design.md`“实现状态”：新任职的授权建议还没做。

**代码依据**
- E `internal/core/names.go`：`OpApptEdit = "mdm.employee.appointment.manage"`，它在 `appointments.Appoint` 等处只用于 `admit`。整个 E 里没有调用授权组件的授予接口，只有 `CheckLinkChange` 和 `Administrators`。
- A：授予走用户面生效点，要求 `infra.authz.security_record.change`，请求者要有对应的管理职责单元和上限。

**结论**：不能。人事管理员在 E 里任命，授予要另一个有管理职责的人在授权组件里手工授出，并可以绑定这条任职。

一致。

---

## 其他发现

- **两个文档对“结束账号关联可否由部署所有者代替”的表述不完整**：E 的文档写“没有别的可用管理员时由部署所有者确认”。A 的文档与代码是：建立只在没有别的可用管理员时可以，结束随时可以。建议 E 的文档对照 A 补全，这只是文档没写全，行为没有错。
- 版本号一致：E 在 `component.yaml` 和 `employee/definition.go` 都是 3.0.2，A 在 `component.yaml` 和 `internal/core/names.go` 都是 3.0.47，组件索引也是这两个版本。
- 第 2 题是这批里唯一“代码里没有”的行为：业务审批按人分离，文档把它分给了 `infra/workflow`，该组件还没开始实现。
