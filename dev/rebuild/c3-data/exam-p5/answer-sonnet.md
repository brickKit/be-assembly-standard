以下是逐题的核对结果。我没有改任何文件，也没有运行测试。"代码依据"都是读源码得出的，除第 3 题末尾标出的推断外，没有实际执行验证。

**缩写**：设计 = `components/erp/payment/docs/design.md`；AGENTS = 各层 `AGENTS.md`；协议 05 = `docs/zh/06-protocols/05-billing-settlement-and-payment.md`；财务设计 = `components/erp/finance/docs/design.md`。

---

## 1. 收款方与应付不符、余额不够、第二行被拒

**文档依据**
- 设计“付款申请”表的 PR02：提交时先用 `DueItems`（法人、收款方、种类、到期日不限）核对每行未清项，不在里面或币种不符就答 `OPEN_ITEM_NOT_PAYABLE`，什么也不认领。
- 然后逐行在事务外认领。有一行被拒（可用余额不够或已被认领），已成功的行同时释放，申请留在草稿，答财务的原因。
- 财务设计 CL01、CL02 和“拒绝的原因”：额度不足答 `CLAIM_EXCEEDS_AVAILABLE`，同一身份不同数量答 `CLAIM_CONFLICT`。
- PR01 写明草稿时不核对收款方，所以录入时不会报错。

**代码依据**
- `internal/requests/actions.go`：`payable()` 核对未清项。`submit()` 先调 `payable`，供应商 B 的应付不在 A 的到期未清项里，直接返回 `ErrOpenItem`（`OPEN_ITEM_NOT_PAYABLE`）。
- `submit()` 之后逐行调 `masterdata.Claim`。失败时对已成功的 `made` 调 `releaseAll`，并返回财务的拒绝（`masterdata.claimRefusal` 转成 `CLAIM_EXCEEDS_AVAILABLE` 等）。
- 失败行没有进入事务，所以申请仍是草稿，行上没有 `claim_id`。

**结论：一致，只有一处细节差别。**
- 文档写“同时释放”，代码是尽力释放：`releaseAll` 失败只记警告日志（`Logger.Warn`），请求仍答原来的拒绝。
- 这时第一行的认领会留在财务那边，直到 7 天期限（CL01）到期，由财务释放，文档没有写这个兜底。

## 2. 谁批准、谁放行、放行时的动作

**文档依据**
- 设计“命令与查询”：批准和驳回要 `erp.payment.request.approve`，放行、执行、退回要 `.execute`。
- PR03：批准人不是申请人（提交人）。
- PR04：放行人不是申请人，可以是批准人（未决问题第一行）。放行时在事务外逐行 `Confirm`，确认后财务不再让它到期。
- 有一行确认不了就答 `CLAIM_LOST`，申请保持 `approved`，后台工作会把它退回草稿。全部确认才变成 `ready`。

**代码依据**
- `actions.go` 的 `ops` 表：`Approve`、`Reject` 对应 `OpRequestApprove`，`Release`、`Execute`、`Return` 对应 `OpRequestExecute`。
- `approve()` 和 `release()` 都比较 `cur.ApplicantID == actor`，相同就返回 `ErrApprover`（`APPROVER_IS_SUBMITTER`）。
- `release()`：对 `cur.claims()` 逐个 `masterdata.Confirm`。`core.ClaimRefused(err)` 时返回 `ErrClaimLost`，此时尚未调用 `moved`，状态不变。
- 成功后 `moved` 里把行的 `claim_expires_at` 置空，状态改成 `ready`，写 `releaser_id`。
- 如果错误是财务不可达，则原样返回（`DEPENDENCY_UNAVAILABLE`）。
- `lifecycle.go` 里 `Release` 在 `Approved` 状态的格子是 `GuardConfirmed`。

**结论：一致。**
- 补充一个文档没覆盖的缺口，是代码推断：放行时前几行已经确认、后一行 `CLAIM_LOST` 时，前几行在财务那边保持 `confirmed`。后台 `lapse`（`renewal.go`）只释放“其余认领”，不释放触发失效的那一条。
- 如果触发失效的那条是已确认的，它被续期拒绝（CL03 对 `confirmed` 拒绝），也不会被释放。这条认领就留在财务那边，直到人手工处理。
- 设计 PR04、PR08 都没有写这种情况。这是两边都没写的缺口，不是两边不一致。

## 3. 已批准未放行的认领续期

**文档依据**
- PR08：`submitted`、`approved` 的每条认领在期限前一小时由后台工作 `Renew`，续期后按新期限再排。
- 财务不可达时工作项重试。续期被拒（认领已到期）时，申请退回草稿，原因写“付款认领已失效”，其余认领释放。
- `ready` 的认领已确认，不再续期。
- 财务设计 CL01：期限起始 7 天，续期从续期时起再算一个期限。

**代码依据**
- `internal/requests/renewal.go`：
  - `scheduleRenewal` 在提交的事务里用 `Work.EnqueueAt` 排 `renew-claim`。
  - `renewAt` 取期限前 `core.RenewAhead`（1 小时），期限更短时取中点。
  - `RenewClaim` 先看 `holds()`（只认 `Submitted`、`Approved`），再调 `masterdata.Renew`，成功就更新期限并排下一次。
- `core.ClaimRefused(err)` 时调 `lapse`：释放其余认领，经 `moved(..., Lapse, ...)` 改回 `Draft`，清 `claim_id`，原因 `LapseReason` = "付款认领已失效"。
- 其他错误（含财务不可达）原样返回。`payment/module.go` 里 `Jobs` 登记为 `MaxAttempts: work.Unlimited`，所以会一直重试。
- `release()` 在 `moved` 里把 `claim_expires_at` 置 NULL。

**结论：一致。**

## 4. 申请 1000（X 700、Y 300），实付 750

**文档依据**
- PR05：实付可逐行给，不给就按行的顺序分；资金事实的认领清单是“认领身份 → 这一行的实付”，实付为零的行不列。
- 财务按实付正式化认领，没付到的部分由财务同时释放（协议 05 与财务设计 CL07）。
- 验证故事第 2 条：同一付款执行被重复提交，只付一次、只发一个事实。

**代码依据**
- `actions.go` 的 `split()`：没给 `Lines` 时按 `cur.Lines` 顺序分，X 得 700，Y 得 50。
- `execute()`：只对份额大于零的行加 `ClaimAmount`，所以事实里是 X 认领 700、Y 认领 50。事实 `Amount` = 750，规则键为 `r.Kind`（`payment`）。
- 财务那边的 250 不是本组件的动作，由财务在核销时释放（财务设计 CL07 有同样的例子）。本组件的行上 `paid` 记 700 和 50。
- 重复提交：`Action` 里 `Lifecycle.Decide(Paid, Execute)` 是 `Ignore`，直接返回当前申请，不发事实。
- 并发时，`moved()` 在锁住行后再次决策，第二个调用同样是 `Ignore`。

**结论：一致。**

## 5. 美元到账：汇率与流水号

**文档依据**
- 设计“规则要点”的外币条：账户币种不是本位币时，事实带汇率快照（`mdm/currency` 的 `EffectiveRate`，按业务日期，事务前取证）。
- RC01：同一账户内银行流水号不重复；RC02：冲正过的流水号可以再用。
- 财务设计第 205 行写明财务不临时取汇率。

**代码依据**
- `internal/receipts/receipts.go` 的 `gather()`：`masterdata.RateOf(account.Currency, le.BaseCurrency, in.ReceivedOn)`。
- `masterdata.RateOf` 调 `RateService.EffectiveRate`，`RateType: "spot"`，日期是到账日期。同币种返回 nil；没有汇率答 `CURRENCY_NOT_USABLE`。
- 汇率快照带 `rate`、`date`、`type` 三个字段，进入 `facts.Fund.ExchangeRate`。
- 重复流水号：迁移 `0001_payment.up.sql` 里 `CREATE UNIQUE INDEX receipt_bank_reference ON receipt (bank_account_id, bank_reference) WHERE state = 'received'`。
- `RegisterReceipt` 用 `ON CONFLICT ... DO NOTHING`，没有插入就答 `ErrBankReference`（`BANK_REFERENCE_TAKEN`，409）。
- 冲正后状态为 `reversed`，不在部分唯一索引里，所以可以再用。
- 内部号 `RC` 在事务前取，重复提交会留下缺号（文档允许缺号）。

**结论：一致，有一处文档没写的细节。**
- 冲正事实复制原事实，沿用原事实的汇率快照（原到账日的汇率），但业务日期和过账日期换成当天。
- 设计 RC02 只写“规则键与金额同原事实”，没有说明汇率沿用原值。这是文档没写、代码这样做，不算冲突。

## 6. 基本户调 5 万到一般户

**文档依据**
- BE02：批准人不是制单人，调拨发布转出的一条 `fund_transfer_out`（角色 `in_transit`、`bank`），状态 `in_transit`。
- BE03：到账时发布 `fund_transfer_in`（角色 `bank`、`in_transit`），状态 `posted`。两条事实的来源都是这张调拨单（同一单据身份）。
- 设计 BE02 写明共享契约的维度只有部门与项目，不带账户。

**代码依据**
- `internal/entries/actions.go` 的 `apply()`：`Approve` 分支对调拨用 `rule="fund_transfer_out"`、`roles=["in_transit","bank"]`、`to=InTransit`，并写 `out_fact_id`。
- `Arrive` 分支用 `fund_transfer_in`、`["bank","in_transit"]`，写 `in_fact_id` 和 `arrived_on`，状态 `posted`。
- `entries.go` 的 `fact()` 两次都用同一个 `Source{DocumentType:"bank_entry", DocumentID:e.ID}`。
- `facts.Accounting` 结构（`facts/shapes.go`）没有公司账户字段，只有 `Amounts`、`Dimensions` 等。
- 财务的 `accounting_fact.v1.schema.json` 里也没有 `company_account_id`（`fund_fact` 的 schema 才有）。
- `Approve` 时对 `Arrive` 的限制：`arrived_on` 不早于 `entry_date`（`Action` 里检查）。

**结论：一致。**
- 设计 BE02、BE03 的括号里写了“转出账户”“转入账户”，同一段又写“不带账户”，文档自身有一处字面矛盾。代码和共享契约都不带账户，以“不带”为准。
- 建议把括号里的“转出账户”“转入账户”删掉。

## 7. 对账单行：-35 手续费

**文档依据**
- BR01：自动匹配只对有流水号的行（条件是 BR02 加流水号相同、唯一）。没有流水号的行不自动匹配。
- BR02：手工匹配要同一账户、金额相等、方向一致、状态是已过账，且这张单据没被别的行匹配，否则 `NOT_MATCHABLE`。
- BR04：付的行生成手续费草稿，过账时自动匹配回这一行。

**代码依据**
- `internal/matching/matching.go` 的 `ByReference`：SQL 条件含 `l.bank_reference IS NOT NULL AND d.ref = l.bank_reference`。手续费单的 `ref` 本来就是 NULL，所以不会自动匹配。
- `Match()`：`documents` 里手续费金额取 `-e.amount`，与 -35 吻合。
- 单据已被别的行匹配时，子查询里 `NOT EXISTS` 排除，查不到行，返回 `ErrNotMatchable`。
- 迁移里还有 `statement_line_document` 唯一索引兜底。
- `statements.go` 的 `CreateEntryFromLine`：负数行生成 `charge`，记 `statement_line_id`，一行只生成一张（有未取消草稿就答 `ErrState`）。
- 草稿经审批后，`entries/actions.go` 的 `Approve` 分支调 `matching.Match(line, "bank_entry", e.ID)`，匹配成功行变 `matched`。
- 如果这行已被手工匹配，`NOT_MATCHABLE` 被忽略，过账照常完成。

**结论：一致。**

## 8. 整套恢复

**文档依据**
- 设计“整套恢复之后”：答公司银行账户、收款单、付款申请、调拨与收付、对账单行的存在性与版本；单号允许缺号，没有要登记作废的。
- 检查 `erp.payment.held_claims`：对 `ready` 的申请逐条向财务读认领，不是已确认的报出来，不自动改状态；处置写在答复里。
- 设计“规则要点”：银行账号是受限字段，读取键 `erp.payment.bank_account.number`，授予里列出这个字段的人才看全，其他人看后四位。

**代码依据**
- `payment/checks.go` 的 `RecoveryChecks`：五个 `c.Presence(...)`，依次是 `BankAccounts`、`Receipts`、`Requests`、`Entries`、`Statements`，用 `TablePresence(表, "id", "version")`。
- 检查 `requests.CheckHeldClaims` = `erp.payment.held_claims`，函数 `HeldClaims`：只查 `state='ready'` 且 `claim_id` 非空的行，调 `masterdata.ClaimState`。
- 状态不是 `confirmed`（财务不认识时为空）的，每个申请只报一次差异。
- 差异的 `Disposal` 写了“钱还没付的取消后重新申请，已经付了的照实登记执行”，没有任何写库动作。
- 没装财务时直接通过。
- 账号：`internal/core/names.go` 里 `accounts["number"] = Field{Class: Restricted, ReadKey: NumberKey}`，`NumberKey = "erp.payment.bank_account.number"`。
- `bankaccounts.Account.Mask(readable)`：读取授予的 `Fields` 里没有 `number` 就显示 `"****" + 后四位`。列表按每一行可读的字段遮蔽。

**结论：一致。**

---

**汇总**
- 8 题里没有“文档说的与代码做的相反”的情况。
- 第 1 题有一处细节差别（释放失败只记日志，靠财务到期兜底）。
- 第 2 题有一个两边都没写的缺口：放行时部分认领已确认、另一行 `CLAIM_LOST`，后台失效不释放那条已确认的认领。
- 第 6 题的设计文档有一处自身措辞矛盾（BE02、BE03 括号里的“转出账户”“转入账户”与“不带账户”并存）。
- 第 5 题文档没有写冲正事实沿用原汇率这一细节。

第 2 题的缺口我没有跑集成测试验证，只是从代码推断。如果要确认，可以补一个集成测试：认领 1 已确认、认领 2 失效，然后看认领 1 在财务那边的状态。
