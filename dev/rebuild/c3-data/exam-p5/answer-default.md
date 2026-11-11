我读了 `docs/design.md`、`BRICKKIT.md`、各层 `AGENTS.md`、`internal/` 与 `payment/` 的代码，以及协议 05 和 `erp/finance` 的认领代码与共享契约。结论：8 题里没有文档与代码互相矛盾的地方，但有几处文档没写或没写全的细节，下面逐题标出。没有改任何文件。

没读到或没核实的地方：`erp/finance` 的 `DueItems` 是否真的按“可用余额大于零”过滤，我只看到文档和错误信息这样写；SDK 对工作项重试的具体规则、对 gRPC 不可达的错误映射、审计层是否遮蔽受限字段，我也没有读。

## 1. 收款方对不上、可用余额不够、第二行被拒

**文档依据**
- `docs/design.md`，状态表“付款申请”下的 PR02：提交时先向财务查收款方的到期未清项，每行的未清项都要在里面且币种相同，否则答 `OPEN_ITEM_NOT_PAYABLE`、什么也不认领。
- 同一条 PR02：之后逐行认领，一行被拒时已成功的行同时释放，申请留在草稿，答财务的原因。
- `docs/design.md` 的“拒绝的原因”一段：财务的拒绝原因有 `CLAIM_EXCEEDS_AVAILABLE`、`CLAIM_CONFLICT`、`CLAIM_STATE`。

**代码依据**
- `internal/requests/actions.go` 的 `payable`：按申请的法人、收款方、种类（退款查 `credit_balance`，付款查 `payable`）调 `DueItems`，到期日不限；缺任何一行就返回 `core.ErrOpenItem`。
- 同文件的 `submit`：`payable` 通过后逐行 `masterdata.Claim`。某行失败时，对已成功的 `made` 调 `releaseAll`，再返回财务的原因。认领身份与期限在全部成功之前不写库，所以申请留在 `draft`，行上没有 `claim_id`。
- `internal/masterdata/upstream.go` 的 `claimRefusal`：把财务的拒绝转成本组件同名的原因。

**回答**
- 收款方写成 A：答 `OPEN_ITEM_NOT_PAYABLE`，一个认领都没发出。
- 收款方对，但这张应付已被别人认领、余额不够：
  - 余额还有但小于本次金额，认领时被财务拒绝，答 `CLAIM_EXCEEDS_AVAILABLE`。
  - 余额已被全部占满：设计文档把付款建议定义为“可用余额大于零”，而 `payable` 走同一个 `DueItems`，这张应付大概率根本不在列表里，会答 `OPEN_ITEM_NOT_PAYABLE`。
- 第一行成功、第二行被拒：第一行的认领立即向财务释放，申请保持草稿，错误是第二行财务给的原因。

**一致。** 补两点文档没写的细节：
- 释放失败时代码只记一条警告日志（`m.RT.Logger.Warn`），那条认领会在财务侧挂到 7 天期限到期。
- 提交失败后重试用的是新的认领身份。

## 2. 谁能批准、谁能放行；放行时认领已过期

**文档依据**
- `docs/design.md` 状态表与 PR03、PR04；“命令与查询”表：`approve` 与 `reject` 用 `.approve`，`release`、`execute`、`return` 用 `.execute`。
- “未决问题”里“放行人与申请人分开”一行：放行人不是申请人，可以是批准人，执行与退回不另限人。

**代码依据**
- `internal/requests/actions.go`：
  - 操作映射 `ops`；`approve` 与 `release` 里都有 `cur.ApplicantID == actor` 则返回 `ErrApprover`。
  - `release`：先逐行 `Confirm`；被拒（`core.ClaimRefused`）就返回 `CLAIM_LOST`，状态不变；全部确认后在 `moved` 里把行的 `claim_expires_at` 置空，状态变 `ready`，记下 `releaser_id`。
- `internal/requests/lifecycle.go`：`Approve` 只允许从 `submitted`，`Release` 只允许从 `approved`。

**回答**
- 批准：持 `erp.payment.request.approve` 且不是申请人（提交人）的账号。
- 放行：持 `erp.payment.request.execute` 且不是申请人的账号，批准人也可以。
- 放行做的事：事务外逐行向财务确认认领，确认后财务不再让它到期；再在一个事务里把状态改成 `ready`，写下放行人。
- 认领已过期：答 `CLAIM_LOST`，申请停在 `approved`，不自动重新认领。

**一致。** 文档没写的一点：放行是逐行确认的，若第 1 行已确认、第 2 行丢了，第 1 行仍是已确认。之后第 1 行的续期工作项会被财务以“只有待确认的认领才能续期”（CL03）拒绝，`lapse` 把申请退回草稿并释放全部认领，与文档“后台工作会把它退回草稿”的说法相符。

## 3. 放很久的已批准申请：续期、被拒、财务连不上

**文档依据**
- `docs/design.md` 的 PR08：`submitted`、`approved` 的每条认领在期限前一小时由后台工作续期；续期被拒则退回草稿，原因写“付款认领已失效”，并释放其余认领；财务不可达时工作项重试；`ready` 的认领已确认，不再续期。
- 协议 05 的参数表：付款认领期限 7 天，可续期。

**代码依据**
- `internal/requests/renewal.go`：
  - `scheduleRenewal` 与 `renewAt`：期限前 `core.RenewAhead`（1 小时）排工作项，剩余不足 2 小时时取中点；续期后按新期限再排。
  - `RenewClaim`：`holds` 只认 `submitted`、`approved`；`Renew` 被拒（`ClaimRefused`）走 `lapse`；其他错误原样返回，工作项重试。
  - `lapse`：先释放其余认领，再经 `moved` 的 `Lapse` 命令写回 `draft`、清空 `claim_id`，原因取常量 `LapseReason`。
- `internal/core/rules.go` 的 `ClaimRefused`：只把 `CLAIM_EXCEEDS_AVAILABLE`、`CLAIM_CONFLICT`、`CLAIM_STATE` 视为“认领已不被持有”。
- 财务一侧：`internal/claims/lifecycle.go` 的 CL03、CL05、CL08。

**回答**
- 不过期靠后台工作每个周期续一次，直到放行；放行确认之后认领在财务侧不再到期。
- 续期被财务拒绝：申请退回 `draft`，原因“付款认领已失效”，其余认领释放，要重新提交。
- 财务连不上：工作项返回错误并重试，状态不变。如果断开的时间超过 1 小时的提前量，财务侧的认领会先到期，重试时续期被拒，申请就按上一条退回草稿。

**一致。** `design.md` 没写“剩余期限短于 2 小时时取中点”，这一条在 `internal/requests/AGENTS.md` 的 `renewAt` 一行里有，不矛盾。

## 4. 申请 1000（X 700、Y 300）只付了 750，没有逐行给；重复提交

**文档依据**
- `docs/design.md` 的 PR05：实付不超过申请金额，不给逐行就按行的顺序分；资金事实的认领清单是“认领身份 → 这一行的实付”，实付为零的行不列；没付到的部分由财务同时释放（协议 05 的 CL07）。
- 协议 05“付款认领”一节“部分付款”：财务在核销事务里按实付正式化认领，剩余部分同时释放。
- 验证故事第 2 条：同一付款执行被重复提交，只付一次、只发一个事实。

**代码依据**
- `internal/requests/actions.go`：
  - `split`：没给 `lines` 时按 `cur.Lines` 顺序分配，每行取 `min(行金额, 剩余)`。
  - `execute`：只把 `share > 0` 的行放进 `f.Claims`。
  - `Action`：先 `Lifecycle.Decide`，`paid` 状态下 `execute` 是 `Ignore`，直接返回当前记录。
  - `moved`：在事务里锁行再问一次表，并发的第二个调用也是 `Ignore`，不写、不发事实。
- `internal/requests/records.go` 的 `lines`：按 `ORDER BY position` 读行。
- 财务侧：`internal/claims/claims.go` 的 `Formalize`，整条认领离开 `pay_claimed`。

**回答**
- 事实里认领清单是两条：X 的认领 700，Y 的认领 50；事实金额 750。
- Y 没付到的 250：财务核销时按实付 50 正式化 Y 的认领，余下的释放，回到可用余额。要付剩下的，另开新申请。
- 同一次执行提交两次：第二次返回已 `paid` 的当前记录，不重复发事实。

**一致。** 注意重复提交时若金额或流水号不同，也只是被忽略，不会报冲突，文档与代码都是“忽略”。我没有去逐行验证财务 `Formalize` 的“同时释放剩余”，这一点依据的是协议 05 的描述。

## 5. USD 到账、汇率、流水号重复与冲正

**文档依据**
- `docs/design.md` 的“规则要点”里“外币”一条：账户币种不是本位币时，事实带 `mdm/currency` 的 `EffectiveRate`，按业务日期取，事务前取证；本位币时汇率为空。
- RC01：流水号在同一账户内不重复。
- RC02：冲正过的流水号可以再用。

**代码依据**
- `internal/masterdata/upstream.go` 的 `RateOf`：调 `RateService.EffectiveRate`，类型 `spot`，日期是传入日期，币种相同返回 `nil`，查无汇率答 `CURRENCY_NOT_USABLE`。
- `internal/receipts/receipts.go`：
  - `gather` 里用 `in.ReceivedOn` 取汇率，事实的 `ExchangeRate` 即这个快照（含 `rate`、`date`、`type`）。
  - `RegisterReceipt` 用 `ON CONFLICT (bank_account_id, bank_reference) WHERE state = 'received' DO NOTHING`，影响行数为 0 时返回 `BANK_REFERENCE_TAKEN`。
- `payment/migrations/0001_payment.up.sql`：部分唯一索引 `receipt_bank_reference ... WHERE state = 'received'`。
- `ReverseReceipt`：冲正事实沿用原事实的汇率，业务日期与过账日期改成法人当地的今天。

**回答**
- 汇率：来自 `mdm/currency`，是美元对人民币的即期汇率，按到账日期（`received_on`）取，在事务之前取证。取不到汇率，登记失败，什么也不写。
- 同一账户同一流水号登记两次：第二次返回 409 `BANK_REFERENCE_TAKEN`。同一幂等键的重放则返回原收款单，不算重复。
- 冲正之后再用这个流水号：允许，因为唯一索引只管 `state = 'received'`。

**一致。** 文档没写的一处：冲正事实的汇率和日期。代码沿用原事实的汇率（不重取），业务日期取冲正当天。`design.md` 只写了“规则键与金额同原事实”，这是文档缺口，不是矛盾。

## 6. 基本户调 5 万到一般户

**文档依据**
- `docs/design.md` 状态表“资金调拨与科目收付”，BE02、BE03：批准后发布转出的 `fund_transfer_out`（`in_transit` 借、`bank` 贷），状态 `in_transit`；到账时发布 `fund_transfer_in`（`bank` 借、`in_transit` 贷），状态 `posted`；两条事实的来源都是这张调拨单；共享契约的分析维度不带账户。
- “命令与查询”表：到账用 `.edit`，批准用 `.approve`。

**代码依据**
- `internal/entries/actions.go` 的 `apply`：
  - `Approve`：批准人不能是制单人；调拨的规则键为 `fund_transfer_out`，角色为 `in_transit`、`bank`，状态变 `in_transit`。
  - `Arrive`：规则键为 `fund_transfer_in`，角色为 `bank`、`in_transit`，状态变 `posted`，记下 `arrived_on`。
- `internal/entries/entries.go` 的 `fact`：来源是 `{component, document_type: "bank_entry", document_id: 单据 id, document_number}`，事实身份 `FactID` 各自新生成；金额 map 里每个角色都是整笔金额。
- `internal/facts/shapes.go` 的 `Accounting`：字段里没有账户。
- 财务侧 `internal/ledger/rules.go`：同样的两条规则，借贷方向与上面一致。
- `internal/entries/actions.go` 的 `Action`：汇率批准时按单据日期取，到账按到账日期取；人民币到人民币汇率为空。

**回答**
- 批准后：发一条 `fund_transfer_out` 的会计事实，调拨单变 `in_transit`。
- 到账时：发一条 `fund_transfer_in`，单据变 `posted`；到账日期不得早于转出日期。
- 关联：两条事实的来源单据相同，都是这张调拨单（同一个 `document_id`）；调拨身份就是这个来源，没有另设字段。
- 会计事实不带公司账户；财务按法人把 `bank` 角色映射到科目。

**一致。** 有一处文字上的出入：协议 05 的“不针对伙伴未清项的资金流”一节把调拨写成“成对的两条资金事实”、科目收付写成“一条资金事实”，而 `design.md`、共享契约与代码都用会计事实 `accounting_fact`（资金事实 `fund_fact` 要求 `company_account_id` 与认领，不适用）。这是协议 05 的措辞与组件设计不一致，建议改协议的措辞。

## 7. 没有流水号的 -35 手续费行

**文档依据**
- `docs/design.md`：
  - BR01：没有流水号的行不去重；自动匹配只对有相同流水号的收款与付款，调拨与收付手工匹配，或由 BR04 生成的单过账时匹配回来源行。
  - BR02：手工匹配可以不要求流水号相同，条件是同账户、金额相等、方向一致、状态是已过账、这张单据没被别的行匹配，否则 `NOT_MATCHABLE`。
  - BR04：付的行生成手续费草稿，之后照 BE01、BE02 审批，过账时自动匹配回这一行。

**代码依据**
- `internal/matching/matching.go`：
  - `documents`：`bank_entry` 这一支的 `ref` 是 `NULL`，所以 `ByReference` 永远匹配不到它；`Match` 按账户、金额（手续费取 `-amount`）、没被别的行匹配来核对，失败返回 `NOT_MATCHABLE`。
- `payment/migrations/0001_payment.up.sql`：`statement_line_document` 唯一索引兜底，一张单据（腿）只能被一行匹配。
- `internal/statements/statements.go`：
  - `RegisterLines`：没流水号的行不去重，登记后调 `ByReference`。
  - `CreateEntryFromLine`：未匹配的行才能生成；已有未取消的草稿则返回 `STATE_CONFLICT`；负数行生成手续费，取摘要为说明，记下来源行。
- `internal/entries/actions.go` 的 `apply` 里 `Approve`：手续费批准即 `posted`，同一事务里调 `matching.Match` 匹配回来源行；`NOT_MATCHABLE` 被吞掉，单据照样过账。

**回答**
- 会不会自动匹配：不会。这行没有流水号，而手续费单本来就没有流水号。
- 手工匹配时手续费单已被另一行匹配：答 409 `NOT_MATCHABLE`，这一行保持未匹配。
- 从该行生成手续费草稿并过账：草稿要提交，再由另一人批准（批准即过账）；过账的同一事务里这一行变 `matched`，指向这张手续费单。若这一行在批准之前已被手工匹配或已处理，就不再覆盖，单据仍然过账。

**一致。** `design.md` 没写“批准时这一行已被手工匹配则不覆盖”，这是代码注释里的行为，不冲突。

## 8. 整套恢复

**文档依据**
- `docs/design.md` 的“整套恢复之后”：答公司银行账户、收款单、付款申请、调拨与收付、对账单行的存在性与版本；`ready` 的申请由 `erp.payment.held_claims` 逐条向财务读认领，不是已确认的报出来，不自动改状态，处置写在答复里。
- “规则要点”最后一条：账号是受限字段，读取键 `erp.payment.bank_account.number`，授予里列出这个字段的人看全，其他人只看后四位。

**代码依据**
- `payment/checks.go` 的 `RecoveryChecks`：五个 `c.Presence(...)`（`bank_account`、`receipt`、`payment_request`、`bank_entry`、`statement_line`，各读 `id` 与 `version`），再注册 `requests.CheckHeldClaims`。
- `internal/requests/checks.go` 的 `HeldClaims`：
  - 在只读事务里读出 `state = 'ready'` 且有 `claim_id` 的行，事务之后才向财务调 `ClaimState`。
  - 状态不是 `confirmed`（含财务不认识的空串）就按申请报一条 `Difference`，结果 `Diff`，附 `Disposal` 文字。
  - 没装财务时直接通过；整个检查不写任何状态。
- `internal/core/names.go`：`NumberKey` 是 `erp.payment.bank_account.number`，`number` 字段是 `Restricted`。
- `internal/bankaccounts/accounts.go` 的 `Mask`：可读字段里没有 `number` 就显示 `****` 加后四位。
- `ListBankAccounts` 按每一行的范围分别遮蔽。

**回答**
- 答存在性：上面五种对象，另外收付款的单号都是允许缺号的序列，没有要登记作废的号。
- `erp.payment.held_claims`：报出“已放行、财务那边的认领不是已确认”的申请，每张申请一条差异，附处置建议（钱没付的取消后重新申请，已经付的照实登记执行）。不自动改单据状态。
- 银行账号：授予里列出受限字段 `number`（读取键 `erp.payment.bank_account.number`）的人看全账号，其他人只看后四位；这个字段也不能用于排序与筛选。

**一致。** 一点文档没写、也没核实的观察：`CreateBankAccount` 与 `UpdateBankAccount` 里 `core.Change` 写审计时传入的是没遮蔽的 `Account`，审计记录里可能带全账号，要看 SDK 的 `audit.TargetOf` 是否按受限字段处理，我没读那一层。

## 汇总

| 题 | 结论 |
| --- | --- |
| 1 | 一致（释放失败只记日志；“可用余额被占满”大概率答 `OPEN_ITEM_NOT_PAYABLE`，文档没区分） |
| 2 | 一致（放行逐行确认，部分确认后的后续由续期工作项收拾，文档没展开） |
| 3 | 一致（中点规则只在 `requests/AGENTS.md`） |
| 4 | 一致 |
| 5 | 一致（冲正沿用原汇率、取当天日期，文档没写） |
| 6 | 一致；协议 05 把调拨与科目收付写成“资金事实”，与设计及代码的会计事实措辞不一致 |
| 7 | 一致 |
| 8 | 一致（审计里是否带全账号待核实） |
