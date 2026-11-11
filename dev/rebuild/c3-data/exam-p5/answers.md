# 参考答案（出题时写，依据 P3 的实现）

1. 提交时先按收款方 A、种类（付款→应付）、币种在财务的 DueItems 里核对每行，B 的应付不在 A 的到期未清项里 → `OPEN_ITEM_NOT_PAYABLE`，什么也不认领（PR02，`requests.payable`）。可用余额不够：财务拒绝 → `CLAIM_EXCEEDS_AVAILABLE`，申请留在草稿；已成功的第一行同时释放（`submit` 的 `releaseAll`）。
2. 批准与放行都不能是申请人（提交人），按账号（PR03、PR04，`approve`、`release` 的 `ErrApprover`）。放行时在事务外逐行向财务确认认领（`Confirm`），全部确认后 `ready`；某条确认不了 → `CLAIM_LOST`，申请保持 `approved`。
3. 后台工作 `renew-claim` 在期限前一小时（期限短于两小时时在中点）续期，续期后排下一次（PR08，`renewal.go`）；续期被拒：申请退回草稿、原因“付款认领已失效”、释放其余认领；财务连不上：工作项重试。
4. 按行的顺序分：X 700、Y 50；事实的认领清单只列实付大于零的行（PR05，`split`、`execute`）；财务按实付正式化，没付到的部分由财务释放（CL07）。重复执行：`paid` 时忽略，不再发事实（表的 `Execute/Paid` 忽略）。
5. `mdm/currency` 的 `RateService.EffectiveRate`，即期、按到账日期（RC01，`masterdata.RateOf`）；同一账户同一流水号在未冲正的收款里重复 → `BANK_REFERENCE_TAKEN`（部分唯一索引）；冲正后可再用。
6. 批准：发会计事实 `fund_transfer_out`（`in_transit` 借、`bank` 贷），状态 `in_transit`；到账：`fund_transfer_in`（`bank` 借、`in_transit` 贷），状态 `posted`；两条事实的 `source` 都是这张调拨单（document_type `bank_entry`、同一 document_id）；会计事实的维度只有部门与项目，不带账户（BE02、BE03）。
7. 不会自动匹配：自动匹配只按流水号，只对收款与付款（BR01）；手工匹配时已被别的行匹配 → `NOT_MATCHABLE`（BR02，`matching.Match`）；BR04 生成的草稿过账时匹配回来源行（`entries.apply` 调 `matching.Match`）。
8. 银行账户、收款单、付款申请、调拨与收付、对账单行（`payment/checks.go`）；检查报出已放行（`ready`）而财务不再确认其认领的申请，只报告、写处置，不改状态；账号是受限字段，读取键 `erp.payment.bank_account.number`，授予里列出它的人看全，其他人看后四位。
