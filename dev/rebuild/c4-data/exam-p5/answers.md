# 参考答案（出题时写，依据 P3 的实现）

1. 收件事务只写 `fact_received` 与过账工作项；工作项取证后没映射 → `work.Wait`（不耗尝试次数，间隔翻倍到 5 分钟），映射补上后最迟约 5 分钟过账（AR03）。同一事实身份再来：按 `fact_id` 去重；摘要不同时保留先到的并告警（AR02，AI 定）。
2. 配置键 `MATCH_TOLERANCES`（JSON：法人 → quantity_percent、price_percent），没写的法人两个都是 0；格式不对组件起不来（`core.NewBase` 解析）。登记人批准自己的差异答 409 `APPROVER_IS_SUBMITTER`（SI04）。改了回到 `draft`，清掉匹配结果与差异批准（SI01）。
3. 只用可用余额：1000 − 300 = 700 < 800，拒绝（超出可用）。期限是配置键 `CLAIM_PERIOD`，默认 7 天；到期由 `EnqueueAt` 排的工作项锁内退回。到期后的释放：忽略（CL08）。只有 `erp/payment`（`ClaimService` 只对它开放，操作 `erp.finance.system.claim`）。
4. 只分同一法人、同一币种、同一伙伴的应收，最早到期先分（锁内，ST03）；剩余形成客户贷方余额（`credit_balance`）；不知道付款方的记暂挂（`suspense`）不分配。
5. 事实落在关闭的月份：过账日期顺延到下一个开放月份首日（11 月 1 日，11 月期间），业务日期不变（PD01）；手工凭证落在关闭的月份答 `PERIOD_CLOSED`，要先带原因重开。关 11 月：有待审批的手工凭证（以及之前的月份没关）时拒绝（PD02 的 GuardNothingWaiting）。
6. 首批只收本位币（MI01，AI 定）；批准时没映射答 `MAPPING_MISSING`；已批准的不能取消（MI03 的表）；待批准的不能认领（只有 open 的未清项可认领）。
7. 规则键不在目录：等着（`work.Wait`，像没映射一样，AF01）；借贷不平：不过账，记 `fact_not_postable` 日志并 `work.Permanent`，不再重试；RC01 的检查会报出它。
8. 存在性与版本：科目与映射、凭证、期间、未清项、供应商票据、付款认领（`finance/checks.go`）；`pending_facts` 报收到还没过账的事实（RC01）；被推过的凭证号登记作废（`voidNumbers`，P14.5）。
