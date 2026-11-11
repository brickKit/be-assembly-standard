我没有改任何文件。除第 5 题有两处差异外，其余各题文档与代码一致。我只读代码和测试断言，没有跑集成测试。

## 1. 无 `sales_invoice` 映射的“已出账”

**文档依据**
- `docs/design.md` 的 AR03：法人没有映射这条规则时，工作项等着，不耗尝试次数，间隔翻倍到 5 分钟，补上映射后最迟 5 分钟内过账，事实不丢。
- AR02：同一事实身份、摘要不同，保留先到的、告警（日志事件 `fact_digest_mismatch`），不入账。
- `BRICKKIT.md` 的“部署前准备”和 `internal/intake/AGENTS.md` 的“怎样走”说法相同。

**代码依据**
- `intake/receive.go` 的 `OnFact`：事务里只写 `fact_received` 和一个 `post-fact` 工作项。
- `intake/invoice.go` 的 `postInvoice`：`ledger.Resolve`（`ledger/mapping.go`）找不到映射就返回 `MAPPING_MISSING`。整个过账事务回滚，没有凭证、没有应收、没有“应收已形成”，收件行保持 `pending`。
- `intake/receive.go` 的 `PostFact`：`MAPPING_MISSING` 转成 `work.Wait`。
- `tools/be-sdk-go/work/runner.go` 的 `fail`：等待不耗尝试次数。下次运行的延迟是已等待时长，下限 1 秒、上限 5 分钟。`finance/module.go` 里 `post-fact` 的 `MaxAttempts` 是不限，且没有设置最长等待。
- 摘要不同：`OnFact` 里 `ON CONFLICT DO NOTHING`，摘要不等就记 Error 日志 `fact_digest_mismatch` 并确认消息，不过账。

**结论**：一致。补上映射后最迟约 5 分钟过账。摘要不同时保留先到的，新内容不入账，这也是设计文档“未决问题”里写明的暂定做法，与协议 05 的“旧事实丢失、新事实到达”不同。

## 2. 供应商票据的容差与差异批准

**文档依据**
- 设计 SI02 与“未决问题”、`BRICKKIT.md` 配置表：用配置键 `MATCH_TOLERANCES`，JSON 为 法人身份 → `{quantity_percent, price_percent}`。没写的法人两个都是 0，格式不对时组件起不来。
- SI01：改了票据回到 `draft`，清掉匹配结果与差异批准。
- SI04：批准人不是登记人，要写明原因。

**代码依据**
- `core/base.go` 的 `NewBase`：JSON 解析失败，或法人身份不是 UUID、两个百分比不是十进制，都返回错误，启动失败。`ToleranceOf` 对没写的法人返回 `"0"` 和 `"0"`。
- `supplierinvoices/lifecycle.go`：`Mismatch` 下的 `Approve` 带 `GuardNotMaker`。
- `supplierinvoices/actions.go` 的 `guard`/`notMaker`：登记人自己批准答 `APPROVER_IS_SUBMITTER`（409），状态不变。不写原因先被拒（`REQUEST_INVALID`）。测试 `itest/supplierinvoices_integration_test.go:86` 断言了这个原因码。
- `supplierinvoices/invoices.go` 的 `UpdateSupplierInvoice`：更新语句把 `state` 置 `draft`，并清掉 `difference_approved_by` 和 `difference_reason`。`writeLines` 整份换行，匹配结果随之没有。

**结论**：一致。批准之后改了票据，批准就没了，要重新匹配；再进 `mismatch` 要再批准一次。

## 3. 应付 1000、已有 300 待确认，再认领 800

**文档依据**
- 设计 CL01：可用余额 = `amount − settled − pay_claimed`，额度不足拒绝。
- “拒绝的原因”：`CLAIM_EXCEEDS_AVAILABLE`。
- CL01：期限起始 7 天，配置键 `CLAIM_PERIOD`。
- CL05、CL08：到期由工作项执行，已到期、已释放的认领重复释放返回成功。
- 命令与查询表：`erp.finance.system.claim` 只许 `erp/payment`。

**代码依据**
- `claims/claims.go` 的 `Claim`：锁住未清项，`core.Cmp(amount, o.Available) > 0` 时返回 `ErrClaimExceeds`。800 > 700，所以被拒，不创建认领。如果认领身份与那笔 300 相同，则返回 `CLAIM_CONFLICT`。
- 期限：`core/base.go` 的 `NewBase` 读 `CLAIM_PERIOD`，默认 `DefaultClaimPeriod`（7×24 小时），≤0 则启动失败。`Claim` 里 `time.Now().Add(m.ClaimPeriod)`，同时用 `expireAt` 排到期工作项。
- 到期后释放：`claims/lifecycle.go` 里 `Release` 在 `Expired` 下是 `IgnoreCell("CL08")`，`command` 对 Ignore 直接返回当前认领，成功，不改状态。
- 谁能调：`finance/module.go` 的 `Services`，`Claim`、`Renew`、`Confirm`、`Release`、`Get`、`DueItems` 的 `Callers` 都是 `[]string{core.Payment}`。`FactService.Read` 才是任一组件可调。正式化与冲回不开放调用，只在核销事务里做。

**结论**：一致。有一个设计没写的小点：到期工作项还没跑时，过期的 `pending` 认领被释放，得到的是 `released` 而不是“忽略”。

## 4. 不带认领的到账分给哪些应收

**文档依据**
- ST03：到账（不带认领）按伙伴的应收自动分配，最早到期的先分，同一到期日按身份，每张不超过可用余额，币种不同的跳过。分不完的形成这个伙伴的客户贷方余额（`credit_balance`）。
- ST02：没有伙伴的到账进 `suspense`，不分配。

**代码依据**
- `settlement/fund.go` 的 `receive`：只取 `legal_entity_id` 相同、`partner_id` 相同、`kind='receivable'`、`state='open'`、`currency` 相同且可用余额大于 0 的项，所以别的法人和别的币种不会被分。
- 取到的项按身份升序锁住，再按（到期日，身份）排序，每张取 `min(rest, o.Available)`，调用 `allocate`。
- `PostFund`：剩余大于 0 时用 `openitems.Form` 形成 `credit_balance`。凭证里贷方记在 `receivable` 角色上，对应“记在应收的科目上”。
- 没有伙伴：`fundVoucher` 用 `suspense` 角色，`PostFund` 里直接返回，不分配。

**结论**：一致。

## 5. 10 月已关闭

**文档依据**
- PD01：来源的事实落在已关闭或重开的期间，过账日期顺延到下一个开放期间的首日，业务日期不变。手工凭证落在已关闭期间的拒绝 `PERIOD_CLOSED`，要计入原期间的先重开。
- PD02：关闭期间要求没有待审批的手工凭证、之前的期间都已关闭。
- 协议 06 的迟到单据与 PC02、PC41 同样如此。

**代码依据**
- 账单：`periods/periods.go` 的 `PostingDate` 循环到第一个 `Open` 的月份。10 月关闭、11 月开放，则过账日期为 2026-11-01，业务日期仍为 10-28。`ledger/posting.go` 的 `Write` 把 `period` 设为过账日期的月份（2026-11），`Issue` 取号为 `JV-<法人代码>-202611-nnnnnn`。
- 手工补 10 月凭证：`vouchers/vouchers.go` 的 `Action` 在批准时调 `periods.CheckManual`，期间是 `closed` 就答 `PERIOD_CLOSED`。草稿的新建和提交没有期间检查，拒绝发生在批准那一步。先重开 10 月（要写原因）才能批准，重开后的 10 月只接受手工凭证，来源事实仍顺延。
- 关 11 月：`periods.Action` 调用 `nothingWaiting`。该月有 `state='submitted'` 的手工凭证就返回 `STATE_CONFLICT`（“N manual vouchers of 2026-11 wait for approval”）。测试 `itest/vouchers_integration_test.go:107` 断言了这个原因码。

**结论**：整体一致，另有两处差异。
1. 轻微不一致：设计 PD02 写“之前的期间都已关闭”。代码在 `nothingWaiting` 里只拒绝 `open` 或从未建立的月份，`reopened` 的月份放行。`periods/AGENTS.md` 写的是“已关闭或重开”，与代码相符，设计文档该处措辞需要对齐。
2. 与协议 05 的差异：协议 05“落进不能过账的期间”一行要求顺延到下一开放期间时“记下改道（原过账日期、新期间）并告警”。设计文档与代码只做顺延，凭证上同时存了业务日期和过账日期，没有告警，也没有单独的改道记录。设计文档没提这一点。

## 6. 人工未清项

**文档依据**
- MI01：币种是法人的本位币（首批），状态 `pending_approval`，不能认领、不参与核销。
- MI02：批准人不是登记人，一个事务里过凭证（`manual_receivable`/`manual_payable`）。
- MI03：只取消待批准的，已批准的更正用反向人工未清项或手工凭证。
- CL01 与“拒绝的原因”：未批准的未清项认领答 `CLAIM_STATE`。

**代码依据**
- 外币：`manualitems/manual.go` 的 `CreateOpenItem`，`in.Currency != le.BaseCurrency` 时返回 `ErrCurrency`（`CURRENCY_NOT_USABLE`，409），不能用外币登记。
- 未映射时批准：`Action` 里调用 `post` → `ledger.Resolve`，返回 `MAPPING_MISSING`，事务回滚，状态仍是 `pending_approval`、没有凭证。测试 `itest/manualitems_integration_test.go:59` 断言了这个原因码。
- 已批准取消：`manualitems/lifecycle.go` 里 `Cancel` 在 `Open` 下是 `RefuseCell("MI03", …)`，答 `STATE_CONFLICT`。
- 认领：`claims/claims.go` 的 `Claim` 对非 `payable`/`credit_balance`，或 `pending_approval`、`cancelled` 一律答 `CLAIM_STATE`。待批准的应收和应付都不能被认领。核销 `settlement/fund.go` 的 `receive` 只取 `state='open'`。

**结论**：一致。设计文档没写“批准时缺映射会怎样”，这一点只有代码和测试有。

## 7. 规则键不在目录；借贷不平

**文档依据**
- AF02：不认识的规则键与没映射的角色让事实等着（AR03），补上后过账。角色金额借贷不平、形状不对的事实不能过账，工作项停下并告警，事实留在收件表待人处理。
- 设计 RC01 也列了 `fact_not_postable` 日志事件。

**代码依据**
- 规则键不在目录：`ledger.Resolve` 里 `Rules[rule]` 不存在就返回 `MAPPING_MISSING`。`PostFact` 转成 `work.Wait`，等待不耗尝试次数，延迟上限 5 分钟，会一直重试到目录里有这条规则并映射（或人处理），不会死掉。
- 借贷不平：`intake/accounting.go` 的 `postAccounting`，`ledger.Write` 返回 `VOUCHER_UNBALANCED` 或 `ACCOUNT_NOT_POSTABLE` 时调用 `stop`，记 Error 日志 `fact_not_postable`，返回 `work.Permanent`。工作项停止，不重试，`fact_received` 保持 `pending`。形状不对（金额非十进制、缺日期、缺汇率）同样走 `stop`。

**结论**：一致。代码把“科目不可记账”也归为停下，`intake/AGENTS.md` 写了，设计文档没提。

## 8. 整套恢复

**文档依据**
- 设计“整套恢复之后”：答科目与映射、凭证、期间、未清项、供应商票据、付款认领的“还在不在、在哪个版本”。被推过的凭证号登记为作废（`voided_number`，P14.5）。RC01 检查 `erp.finance.pending_facts`。
- `BRICKKIT.md` 契约索引同样列出。

**代码依据**
- `finance/checks.go` 的 `RecoveryChecks`：
  - `Presence` 登记了 `core.Accounts`（`account` 表加 `mapping/<法人>`）、`Vouchers`、`Periods`、`OpenItems`、`SupplierInvoices`，以及 `core.System`（`pay_claim`，用 `claim_id` 和 `version`）。
  - `c.Void(voidNumbers)` 往 `voided_number` 插入 `generate_series(from,to)`，`ON CONFLICT DO NOTHING`。
  - SDK 的 `recovery/server.go` 在 `AdvanceNumbers` 同一事务里调用它，范围是原最大值+1 到新值。
  - 检查 `intake.PendingFacts`（`intake/checks.go`）：没有 `pending` 事实报 `Pass`。有就报 `Diff`，每条差异是 `fact_received`、事实身份、说明“类型 from 来源，received 时刻，not posted”，并给出处置建议（补映射或规则后自动过账；其余按 `fact_not_postable`、`reversal_partial`、`reversal_credit_used` 核对来源后更正）。

**结论**：一致。凭证号被推过时由恢复工具提升序列，财务把被跳过的号登记为作废，不会重用。`pending_facts` 会把所有还没过账的事实都报出来，包括刚收到、正在等的，不区分等待和停止。
