# 参考答案（出题时写，依据设计 3.0.0 与采购 3.0.4）

1. PO01：拒绝 `POLICY_IN_USE`（换方法要重估在库价值，不在首批）；缺省移动平均（第一次用到时插入版本 0 的缺省行）；版本不对 `VERSION_CONFLICT`。
2. VS03：4、5 只收下，范围进入 `waiting_gap`，等 `VALUATION_GAP_WAIT`（起始 5 分钟），到期按序号向库存补取（`StockService.Movements`）；库存也没有 3 时再等一个周期并告警；补齐之前不往后算。
3. LY01：范围进入 `waiting_basis`，等 `VALUATION_BASIS_WAIT`（起始 5 分钟），到期按政策价入层（来源 `policy`，待定价）；之后到达的依据按 LY02 替换政策价、按 AD01 出调整；外币依据按依据业务日期的即期汇率折算，没有汇率时依据不可用（`CURRENCY_NOT_USABLE`，处理工作稍后再试），等依据的入库照样等。
4. AD02（IC24）：确认按先后占层前面没开票的单位 0–5；已出库的是 0–3，其中 4 个已出库 → 差异 8.00，2 个在库 → 存货 4.00；`grni` 12.00；规则键 `cost_adjustment_up`；金额都为正。
5. IS02：2 个按当前单价，3 个按政策价，在库数量 −3，告警，恢复检查 `erp.costing.negative_stock` 报出；之后的入库先补平：前 3 个单位按入库成本与当时政策价的差更正销售成本，入库更便宜发 `cost_of_sales_return`（存货借、销售成本贷），业务日期是入库日期。
6. RT01、采购 PO09：采购在建退货单之前（事务外）调 `LayerService.ReturnLimit`，事务里同一流水的行合计超过就整笔拒绝 `RETURN_EXCEEDS_COST_LAYER`；成本组件不答复时不拦（它把超出的部分按在库不够计价并告警）；重放不再核对（核对在 `idem.Do` 的函数里，重放不执行它）；移动平均不限。
7. VS02：不认识的种类让范围停下（`stopped`，原因写种类）并告警，不跳过——跳过会让后面的成本都错；恢复检查 `erp.costing.stopped_scopes` 报出；库存加种类之前先发布能处理它的成本组件版本。
8. 只有 `mdm/currency`、`mdm/org`、`erp/inventory`；订阅不需要依赖（本组件不调用它们）；采购退货前调用本组件，两边都声明会让精确版本互相钉住，永远对不齐；财务没配 `FINANCE_FACT_SOURCES` 时不订阅成本事实，成本事实只供查询，不过账。
