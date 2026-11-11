**说明**：我读了组件的 `AGENTS.md`、`docs/design.md`、`BRICKKIT.md`、各层 `AGENTS.md`，以及对应的代码。`docs/zh/` 的协议原文（05、06、14、15）这次没有打开，只引用组件文档里写到的条款。SDK 的行为只核对了 `work`（`Wait` 的退避）这一处。所有判断都是读代码得出的，没有跑测试。

整体上，8 题中的 7 题文档与代码一致。有 3 处小的不一致或缺口：第 5 题的关账前置条件、第 2 题的“重新匹配不清批准”、第 8 题的凭证号作废（见该题）。

## 1. 出账、没有映射 `sales_invoice`

**这条“已出账”事实会怎样**
- 文档：`design.md` 的 AR03 说收件与过账分两段。法人没有映射这条规则时，工作项等着，不耗尝试次数，间隔翻倍到 5 分钟，事实不丢。`BRICKKIT.md` 的“部署前准备”和 `intake/AGENTS.md` 的第 2 步写法相同。
- 代码：
  - `intake/receive.go` 的 `OnFact` 只写 `fact_received` 和 `post-fact` 工作项。
  - `PostFact` 里，`postInvoice` 调 `ledger.Resolve`（`ledger/mapping.go`）。查不到映射就返回 `MAPPING_MISSING`，`PostFact` 转成 `work.Wait`。
  - `work/runner.go` 的 `fail` 对 wait 做 `attempts-1`，并设 `run_at = now + min(300s, max(1s, 已等时长))`。
  - 登记在 `finance/module.go:128`（`MaxAttempts: Unlimited`，没有 `MaxWait`）。所以没有映射时事实会一直等，不会变成死信。
- 结论：一致。

**映射补上后最迟多久过账**
- 文档：最迟 5 分钟。
- 代码：退避上限是 `BackoffCap = 5min`，所以最迟约 5 分钟。
- 结论：一致。

**同一身份再来、摘要不同**
- 文档：AR02 说保留先到的，告警 `fact_digest_mismatch`，不入账。“会计事实契约”一节还写了“回答成功（消息确认）”。
- 代码：`OnFact` 里 `INSERT … ON CONFLICT DO NOTHING`。冲突后比较摘要，不同就 `Logger.Error(event=fact_digest_mismatch)`，然后 `return nil`（确认）。
- 结论：一致。

## 2. 供应商票据

**匹配容差在哪里设、没设的法人是多少、格式写错了会怎样**
- 文档：`BRICKKIT.md` 的配置表和 `design.md` 的 SI02 都写配置键 `MATCH_TOLERANCES`，按法人的 JSON。没写的法人数量和价格都是 0，格式不对时组件起不来。
- 代码：
  - `core/base.go` 的 `NewBase` 解析 JSON，并校验法人 ID 是 UUID、两个百分比是十进制，不对就返回 error，启动失败。
  - `ToleranceOf` 对没写的法人返回 `"0"`、`"0"`。
  - 容差启动时读一次，改配置要重启。
- 结论：一致。

**登记人自己批准差异**
- 文档：SI04 说批准人不是登记人（按账号）。
- 代码：`supplierinvoices/lifecycle.go` 里 `mismatch` 的批准格带 `GuardNotMaker`。`actions.go` 的 `notMaker` 在 `MakerID == actor` 时返回 `ErrApprover`，即 `APPROVER_IS_SUBMITTER`（409）。批准还要写明原因，否则报 `Invalid("reason")`。
- 结论：一致。

**批准之后又改了票据，批准还在吗**
- 文档：SI01 说修改后回到 `draft`，清掉匹配结果与差异批准。
- 代码：`invoices.go:265` 的更新里 `state='draft', difference_approved_by=NULL, difference_reason=NULL`。已过账的票据修改被 SI05 拒绝。
- 结论：一致，批准不在了。
- 补充（缺口，不算不一致）：`Match` 命令（重新匹配）在 `matching.go` 的 `record` 里只改状态，不清 `difference_approved_by`。批准过的 `mismatch` 票据重新匹配后如果仍是 `mismatch`，旧批准还在，可以直接过账。文档只写了“修改”会清批准，没写“重新匹配”怎样，建议补一句或改代码。

## 3. 付款认领

**应付 1000、已有一笔 300 待确认，这次认领 800**
- 文档：CL01 说额度是可用余额 `amount − settled − pay_claimed`。拒绝原因写 `CLAIM_EXCEEDS_AVAILABLE`，系统面答 `FailedPrecondition`。
- 代码：`claims/claims.go` 的 `Claim` 在锁住未清项后比较 `amount > o.Available`。这里可用余额是 700，800 超了，所以返回 `ErrClaimExceeds`（409）。整个事务回滚，`pay_claimed` 仍是 300，不会产生认领。
- 结论：一致。

**认领的期限和设置位置**
- 文档：起始 7 天，配置键 `CLAIM_PERIOD`（时长，没配是 7 天）。续期从续期时起再算一个期限。
- 代码：
  - `core/names.go:87` 的 `DefaultClaimPeriod = 7*24h`。
  - `NewBase` 读 `CLAIM_PERIOD`，值不大于 0 时启动失败。
  - `Claim` 用 `time.Now()+ClaimPeriod`。
  - `command` 里的续期用 `Now()+ClaimPeriod`。
- 结论：一致。

**到期之后收付款再来“释放”**
- 文档：CL08 说已到期、已释放的重复释放返回成功。
- 代码：释放格里 `Expired` 和 `Released` 都是 `IgnoreCell("CL08")`。`command` 对 `Ignore` 直接返回当前认领，不报错。到期本身由 `ExpireClaim` 工作项执行，会把数量退回 `pay_claimed`。
- 结论：一致。

**哪些组件能调认领**
- 文档：只许 `erp/payment`，操作 `erp.finance.system.claim`。
- 代码：`finance/module.go:96` 是 `Callers: []string{core.Payment}`，`core.Payment = "erp/payment"`。`FactService.Read` 才是任一组件。
- 结论：一致。

## 4. 没带认领的到账资金事实

- 文档：ST03 说按伙伴的应收自动分配，最早到期先分，同一到期日按身份。每张不超过可用余额，币种不同的跳过。分不完的形成客户贷方余额 `credit_balance`。
- 代码：`settlement/fund.go` 的 `receive`：
  - SQL 条件是 `legal_entity_id = 本法人 AND partner_id = 付款方 AND kind='receivable' AND state='open' AND currency = 到账币种 AND amount−settled−pay_claimed>0`。
  - 排序按（到期日，身份）。
  - 每张取 `min(rest, Available)`。
  - 剩余部分在 `PostFund` 里 `openitems.Form(... Kind: "credit_balance", Origin: "fund")`。
  - 没有伙伴的到账不分配，贷方记 `suspense`（资金暂挂）。
- 别的法人或别的币种的应收不会被分，待批准的人工应收也不会被分（要求 `state='open'`）。
- 结论：一致。

## 5. 10 月已关闭，业务日期 10 月 28 日的账单 11 月 3 日才到

**这张账单的凭证**
- 文档：PD01 说来源的事实落在已关闭的期间时，过账日期顺延到下一个开放期间的首日，业务日期不变。
- 代码：`periods.PostingDate` 逐月循环，状态不是 `open` 就取下月首日。`postInvoice` 用它的结果写凭证。`ledger.Write` 的 `period` 取 `PostingDate[:7]`。
- 凭证记在 **11 月 1 日**，不是到达那天 11 月 3 日。业务日期仍是 10 月 28 日，期间是 2026-11，凭证号取 11 月的序列（`JV-<法人代码>-202611-nnnnnn`）。如果 11 月也已关闭，继续顺延。
- 结论：一致。

**手工补一张 10 月的凭证**
- 文档：手工凭证落在已关闭期间的拒绝 `PERIOD_CLOSED`，要计入原期间的先重开。
- 代码：`vouchers.go` 新建草稿时不检查期间。批准时调 `periods.CheckManual(v.Period)`，`closed` 返回 `ErrPeriodClosed`。冲销检查的是当天所在月。重开要写原因（`Action` 里检查），重开后 10 月接受手工凭证。
- 结论：一致。文档没说是在“批准”这一步才检查，这是代码里的时机。

**关 11 月时 11 月还有待审批的手工凭证**
- 文档：PD02 说没有待审批的手工凭证、之前的期间都已关闭时才能关。
- 代码：`nothingWaiting` 统计本月 `state='submitted'` 的凭证，有就返回 `ErrState`（`STATE_CONFLICT`，“N manual vouchers of 2026-11 wait for approval”）。草稿不算，别的月份的待审批也不挡这个月。
- 结论：这一点一致。
- 不一致：文档（`design.md` 的 PD02、关闭格、`lifecycle.go` 的 `GuardNothingWaiting`）写“之前的期间都已关闭”，代码 `nothingWaiting` 里 `state == Open` 才拒绝，所以更早的月份是“重开”状态也放行。`periods/AGENTS.md` 写“关闭或重开”，与代码相符，与 `design.md` 不符。需要统一成其中一种。

## 6. 人工未清项

**能不能用外币登记**
- 文档：MI01 说币种是法人的本位币（首批）。
- 代码：`manualitems/manual.go` 的 `CreateOpenItem` 在 `in.Currency != le.BaseCurrency` 时返回 `ErrCurrency`（`CURRENCY_NOT_USABLE`，409）。
- 结论：一致，不能。

**法人还没有映射 `manual_receivable` 时批准**
- 文档：MI02 只写“经映射”，没写缺映射的后果。
- 代码：`Action` 里批准时先调 `post`，`ledger.Resolve` 返回 `MAPPING_MISSING`（409）。批准的事务回滚，未清项仍是 `pending_approval`，凭证和“应收已形成”都没有。这是同步拒绝，不像事实那样排队等待。
- 结论：文档没有说明，代码行为如上。建议文档补一句。

**已经批准的还能取消吗**
- 文档：MI03 说只取消待批准的，已批准的更正用反向人工未清项或手工凭证。
- 代码：取消格里 `Open` 是 `RefuseCell("MI03", ...)`，返回 `STATE_CONFLICT`。
- 结论：一致。

**待批准的能不能被收付款认领**
- 文档：MI01 说不能认领、不参与核销。CL01 说未清项要是 `open`。
- 代码：`Claim` 对 `pending_approval` 或 `cancelled` 返回 `ErrClaimState`。`DueItems` 的 SQL 有 `state='open'`。`receive` 也要 `state='open'`。
- 结论：一致，不能。

## 7. 规则目录里没有的规则键、借贷不平的会计事实

**规则键在规则目录里没有**
- 文档：AF02 说不认识的规则键让事实等着，补上后过账。
- 代码：`ledger.Resolve` 对没有的规则返回 `ErrMapping`（`no posting rule …`），`PostFact` 转成 `work.Wait`。`ledger/rules.go` 的 `Rules` 目录里没有这个规则键，所以会一直等。
- 会一直重试：是。不耗尝试次数，没有 `MaxWait`，间隔最长 5 分钟。要加规则并发新版本后才能过账。
- 结论：一致。

**借贷不平**
- 文档：AF02 说借贷不平、形状不对的事实不能过账，工作项停下并告警，事实留在收件表待人处理。
- 代码：`postAccounting` 里，`ledger.Write` 返回 `VOUCHER_UNBALANCED` 或 `ACCOUNT_NOT_POSTABLE` 时调 `stop`。`stop` 打 `Logger.Error(event=fact_not_postable)` 并返回 `work.Permanent`，工作项进 dead，不再重试。`fact_received.state` 保持 `pending`。形状不对（JSON 解析失败、金额为空、日期或金额格式不对）同样走 `stop`。
- 会不会一直重试：不会。
- 结论：一致。

## 8. 整套恢复

**财务答哪些对象的“还在不在”**
- 文档：科目与映射、凭证、期间、未清项、供应商票据、付款认领（`design.md`“整套恢复之后”、`BRICKKIT.md` 的契约索引）。
- 代码：`finance/checks.go` 的 `RecoveryChecks` 里 `c.Presence` 登记了 `core.Accounts`（`account` 表加 `mapping/<法人>` 的版本）、`Vouchers`、`Periods`、`OpenItems`、`SupplierInvoices`、`System`（`pay_claim`，按 `claim_id`）。
- 结论：一致。

**检查 `erp.finance.pending_facts` 报什么**
- 文档：RC01 说收件表里还没过账的事实，逐条报出类型、来源与收到时刻。
- 代码：`intake/checks.go` 的 `PendingFacts` 查 `fact_received WHERE state='pending'`，按收到时刻、身份排序。每条是一个 `Difference`（`ObjectType="fact_received"`，`Detail` 含类型、来源、收到时刻）。有就返回 `Diff`，并带 `Disposal` 文字，没有就 `Pass`。
- 结论：一致。

**恢复时发现凭证号被别的副本推过了**
- 文档：连续凭证号被工具推过的，登记为作废（`voided_number`，P14.5）。
- 代码：`c.Void(voidNumbers)` 把 `from..to` 每个号用 `generate_series` 插入 `voided_number`（`ON CONFLICT DO NOTHING`），原因写“a full recovery lost the voucher posted under this number”。`Issue` 里的审计带 `document_number`，供恢复工具对照。
- 结论：一致。`from..to` 的区间由 SDK 的 `recovery` 传入，我没有核对 be-protocol P14.5 里区间两端的含义。

## 需要处理的汇总

1. **PD02 的前置条件**：`design.md` 写“之前的期间都已关闭”，代码和 `periods/AGENTS.md` 允许“关闭或重开”。
2. **重新匹配不清批准**：文档没写，代码会让旧批准留下。
3. **缺映射时批准人工未清项**：文档没写后果，代码是同步报 `MAPPING_MISSING` 并回滚。

没有改任何文件。
