# 参考答案（出题时写）

1. 普通销售：授予只管自己的（owner self），对同事为负责人的事实连编辑都不允许，答 404（看不见）；有编辑全部但没有 `assign` 的答 403；销售主管（有 assign）可以。没开客户角色：`CUSTOMER_NOT_ELIGIBLE`（带 `role_not_opened`）。OP01、OP04；`opportunities.Create`。
2. 推进 negotiation：允许，概率 75；推进 won：`STAGE_ORDER`；回退不写原因：`REQUEST_INVALID`；写原因：qualification、概率 10。OP03；`Move`、`checkStage`。
3. 改名称可以；改金额 `WON_AMOUNT_LOCKED`；再赢单忽略（版本不变、不发事实）；输单 `STATE_CONFLICT`；请求报价 `STATE_CONFLICT`。重开回关闭前的阶段与概率，赢单金额清掉。OP02、OP06、OP07；`Edit`、`ChangeIn`、`reopen`。
4. 同一键：一个请求一个事实（幂等重放）；不同键：两个请求、两个事实。给明细就替换商机的明细，请求记下快照。OP05；`quotes.RequestQuote`。
5. 一张（`quote_request_in` 按请求身份去重）；不合格：不生成、发布 `erp.quote_request.rejected.v1`（NOT_ELIGIBLE），商机标 rejected；不可达：工作重试。草稿：法人、客户、币种、负责人取请求的，部门与有效期留空，没有明细，请求的产品、商机参考、请求身份。QR01–QR04；`OnRequested`、`DraftJob`。
6. 发出答 `REQUEST_INVALID`；订单的商机参考按 `quotation_id` 从报价读（订单表不加列），订单事件 `opportunity_ref` 带出。QR05；`QuotationAction`、`core.OrderCols`。
7. 商机在进行中则赢单（订单不含税合计，操作者 system，触发是订单）；同一事件再来：版本没变，`sales_link` 不更新、什么也不做；更旧版本：丢弃；币种不同：用预计金额并写原因；已输单：只记下。OP08；`OnSales`、`AutoWins`。
8. 只订阅：商机订阅流 `erp.sales` 的三种类型，销售订阅流 `crm.opportunity` 的 `quote_requested`；订阅方自己建流（P6.17）。两边 component.yaml 的 dependencies 里都没有对方，events.subscribes 列出对方的类型。
9. 按法人、币种、阶段；赢单用赢单金额、加权 = 金额（概率 100）；输单加权 0；加权按币种小数位四舍五入（离零）；只算看得见的（数据范围编进查询）；筛选值形式不对 400。`forecast.Funnel`、`core.QueryFilters`。
10. 审计过的商机的存在性与版本（`RecoveryChecks` 的 Presence），SDK 自带检查；请求停 requested：销售的报价事件一到就补上，不另做核对。设计“整套恢复之后”。
