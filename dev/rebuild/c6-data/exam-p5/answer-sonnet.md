以下是只读核对的结果，没有改任何文件。简称：商机 = `components/crm/opportunity`，销售 = `components/erp/sales`，设计 = 各自的 `docs/design.md`。

先说结论：10 题里 7 题文档与代码一致，3 题有不一致（第 7、8、9 题）。另有几处只是文档没写到、不算冲突的小点。

## 1. 新建商机时的负责人与客户资格

- **文档依据**：
  - 商机设计 OP01：指定别人要另有 `crm.opportunity.assign`，否则普通销售能绕过 OP04。
  - 商机设计 OP01：客户向 `mdm/partner` 取资格，用途 `sell`。
  - 商机设计“拒绝的原因”：没有资格答 `CUSTOMER_NOT_ELIGIBLE`，细节带 `role_not_opened` 等。
  - `itest/AGENTS.md` 的测试索引：看不见的答 404，有编辑权但没有改负责人操作的答 403。
- **代码依据**：`internal/opportunities/commands.go` 的 `Create`。
  - 先 `core.Check(OpEdit, Facts(法人, 目标负责人))`。
  - 目标负责人不是本人时，再 `core.Check(OpAssign, …)`。
  - 然后依次取法人、币种、客户，最后才开事务。
- **普通销售（只管自己）写同事**：第一道检查就过不去，答 404（“看不见”），不会走到 assign 检查。`itest/opportunities_integration_test.go` 的 Dave 用例断言了 404。
- **有编辑权但没有 assign 的人**（测试里的 Erin）：答 403。
- **销售主管**（测试里的 Bob，有 assign，范围是法人内全部负责人）：成功，负责人就是那位同事。
- **客户在该法人下没有客户角色**：`masterdata.CustomerOf` 里 `CheckEligibility` 不合格，答 409 `CUSTOMER_NOT_ELIGIBLE`，带伙伴的原因。事务没开，什么都没写。
- **结论：一致**。文档没写 404 还是 403，是测试和代码定的，不算冲突。

## 2. 商机在 proposal 时的阶段移动

- **文档依据**：商机设计 OP03 与“商机”表（推进、回退两行）。
- **代码依据**：`commands.go` 的 `checkStage` 与 `defaultProbability`；`changes.go` 的 `Move` 与 `reasonOf`。
- **推进到 negotiation**：成功，概率变 75（目标阶段的缺省，命令里给了概率就用给的）。写一行阶段历史，发 `stage_changed`。
- **推进到 won**：409 `STAGE_ORDER`，赢单只能走赢单命令。
- **回退到 qualification 不写原因**：400 `REQUEST_INVALID`，没有改动。
- **回退并写了原因**：成功，概率变 10，阶段历史带原因。
- **结论：一致**。

## 3. 赢单之后

- **文档依据**：商机设计 OP02、OP06、OP07 与“商机”表。
- **代码依据**：`lifecycle.go` 的表；`changes.go` 的 `Edit`、`Close`、`Win`、`reopen`。
- **改名称**：成功（预计成交日同理）。
- **改金额**：409 `WON_AMOUNT_LOCKED`。币种、客户、明细、概率同样被锁。
- **再赢单一次**：忽略，答 200 和原状态，不升版本，不再发 `won` 事实。
- **输单**：409 `STATE_CONFLICT`。
- **请求报价**：409 `STATE_CONFLICT`。
- **重开**：要写原因，否则 400。
  - 回到关闭前的阶段与关闭前的概率，包括手工改过的概率。
  - 赢单金额与关闭原因清空。
  - 发 `stage_changed`；重开后再赢单是新的一次关闭，会发新的 `won`。
- **结论：一致**。有一处措辞小差：OP02 正文只列了“金额、币种、客户、明细”被锁，代码和“商机”表（只许改名称与预计成交日）还锁了概率。以表为准则两边一致。

## 4. 请求报价与幂等

- **文档依据**：商机设计 OP05。
- **代码依据**：`internal/quotes/request.go` 的 `RequestQuote`，在 `idem.Do` 里调用 `ChangeIn`。
- **同一幂等键提交两次**：1 个请求、1 个 `quote_requested` 事实，第二次答同一个请求。
- **不同的键提交两次**：2 个请求、2 个事实（一个商机可以有多个请求）。每次还会升商机版本、发一个 `changed` 事件，设计没写这一点，属附带行为。
- **请求时给了明细**：先校验（最多 100 行、数量大于零、单位非空），然后整体替换商机的明细，同时作为这个请求的快照；不给就用商机现有的明细。
- **结论：一致**。

## 5. 销售收到请求报价事件

- **文档依据**：销售设计 QR01–QR04，“商机的请求报价”一节。
- **代码依据**：`internal/quoterequests/quoterequests.go` 的 `OnRequested`、`DraftJob`、`evidence`、`draft`、`refuse`。
- **同一事件两次**：只生成 1 张草稿。
  - `quote_request_in` 按事实身份 `ON CONFLICT DO NOTHING`，只有第一次才排工作。
  - `lockReceived` 再兜一层。
  - 集成测试 `quoterequests_integration_test.go` 断言了“delivered twice → 1 draft”。
- **客户在取证时已不合格**：不生成草稿，请求变 `rejected`，发布 `erp.quote_request.rejected.v1`，原因 `NOT_ELIGIBLE`（法人或币种不可用则是 `LEGAL_ENTITY_NOT_USABLE` 或 `CURRENCY_NOT_USABLE`）。商机侧 `quotes/sales.go` 的 `rejected` 把请求标为 `rejected` 并记下原因。
- **主数据不可达**：不是三种拒绝原因，工作失败重试（`MaxAttempts: work.Unlimited`）。请求仍是 `received`，没有草稿，也不发拒绝事实。这一条没有集成测试。
- **草稿上有**：
  - 法人、客户（含名称快照与税号）、币种、负责人（取请求的）。
  - 商机参考、请求身份、请求的产品（原样，不校验）。
  - 报价的事件与审计（没有用户操作者）。
- **草稿上没有**：明细、部门、有效期。
- **结论：一致**。文档没写的一点：请求里的法人、客户、币种、负责人形式不对时，代码也按 `NOT_ELIGIBLE` 拒绝。

## 6. 草稿发出、接受与订单上的商机参考

- **文档依据**：销售设计 QR05，以及“拥有的数据”表里 `sales_order` 一行。
- **代码依据**：`internal/quotations/quotations.go` 的 `QuotationAction`、`UpdateQuotation`、`AcceptQuotation`；`internal/documents/documents.go` 的 `checkLines`；`internal/core/records.go` 的 `OrderCols`。
- **没有明细就发出**：400 `REQUEST_INVALID`（“a quotation is sent with lines”），草稿不变。
- **补明细**：修改时给明细就整体替换，仍要求 1–100 行；给空数组同样 400。
- **接受之后**：订单表没有商机参考列。`OrderCols` 用子查询 `SELECT oq.opportunity_ref FROM quotation oq WHERE oq.id = o.quotation_id` 从订单的报价读出来。
- **订单事件里有没有**：有。`EmitOrder` 发的就是 `GetOrder` 的结果，`erp.sales_order.changed.v1` 的 schema 里 `opportunity_ref` 是必有的字段。
- **结论：一致**。QR05 写“带到订单”，设计的表写“按报价读”，效果相同。

## 7. 设置为 order_confirmed 时订单确认事件到达

- **文档依据**：商机设计 OP08、“商机”表的 `sales_event` 行、“验证故事”第 3 条。
- **代码依据**：`internal/quotes/sales.go` 的 `OnSales`、`AutoWins`；`opportunities.Win`；`ChangeIn`。
- **订单确认事件到达**：
  - 先把订单记进 `sales_link`（按版本）。
  - 商机在进行中时转 `won`：赢单金额是订单的不含税合计，概率 100。
  - 阶段历史的操作者记 `system`，触发是 `sales_order` 加订单身份。
  - 发 `won`，触发同样写订单身份。
- **同一事件再来一次**：`sales_link` 的 upsert 带 `WHERE version < EXCLUDED.version`，影响行数为 0，直接返回，不再赢单。
- **更旧版本的订单事件晚到**：同上，被丢弃。
- **订单币种与商机不同**：赢单金额用商机的预计金额，阶段历史的原因写“won by sales_order … in USD: the expected amount is kept”。
- **商机已输单**（已赢单也一样）：只记下关联，不改状态。
- **结论：不一致，一处**：
  - **文档**：OP08 写“阶段历史与审计的操作者记 `system`”。
  - **代码**：`moved` 把阶段历史的操作者置为 `"system"`；但审计走 `core.Change(…, actor "")`，SDK `audit/audit.go` 对空 actor 存的是 NULL，不是 `system`。
  - 其余部分一致。

## 8. 两个组件怎样找到对方的事件

- **文档依据**：商机设计“规则要点”第一条与“依赖”表；销售设计 QR01 与“事件”；两边 `component.yaml`。
- **代码依据**：`internal/core/names.go`（两边的流名、事件类型常量）；商机 `opportunity/module.go` 的 `Subscriptions`；销售 `sales/module.go`（订阅 `quote-requests`）。
- **找到对方的方式**：靠固定的流名和事件类型，经消息系统：商机订阅流 `erp.sales`，销售订阅流 `crm.opportunity`。两边都不调用对方，也不声明对方为依赖。
- **商机 `component.yaml`**：
  - 依赖只有 `mdm/currency`、`mdm/org`、`mdm/partner`。
  - 发布 5 个事件（`changed`、`lost`、`quote_requested`、`stage_changed`、`won`）。
  - 订阅 `erp.quotation.changed.v1`、`erp.quote_request.rejected.v1`、`erp.sales_order.changed.v1`。
- **销售 `component.yaml`**：
  - 依赖是 4 个 mdm（currency、org、partner、product）加可选的 `erp/credit`、`erp/inventory`，没有 crm。
  - 发布含 `erp.quote_request.rejected.v1`。
  - 订阅 `crm.opportunity.quote_requested.v1` 与 `mdm.org_unit.changed.v1`。
- **结论：不一致，销售的 `BRICKKIT.md` 漏写**：
  - **文档**：“部署前准备”里写的订阅只有 `mdm/org` 的部门事件；“事件”的增量事实列表里没有 `erp.quote_request.rejected.v1`；全文没有商机的请求报价。
  - **代码与清单**：`component.yaml` 和销售设计 QR01 都有订阅与拒绝事实。
  - 商机的 `BRICKKIT.md` 反过来写了“装了 erp/sales 时它订阅本组件的 `quote_requested`”，两边对不上。

## 9. 漏斗

- **文档依据**：商机设计“命令与查询”的漏斗一行；OpenAPI `getFunnel` 的 `description`；协议 14 的舍入（缺省四舍五入远离零）。
- **代码依据**：`internal/forecast/funnel.go` 的 `value`、`weighted`、`Funnel`、`round`；`core.QueryFilters`。
- **赢单**：金额用赢单金额，加权 = 赢单金额 × 100 / 100。
- **输单**：金额用预计金额，概率为 0，所以加权为 0。
- **舍入**：先在 SQL 里按（法人、币种、阶段）求和，再按币种的小数位四舍五入远离零（不是逐商机舍入）。
- **普通销售**：`list.Build` 把数据范围编进查询，只算自己的；`owner_id` 筛选只在可见范围内再收窄。
- **筛选值形式不对**：
  - `legal_entity_id` 不是 UUID，或 `close_from`、`close_to` 不是 `YYYY-MM-DD`，答 400。
  - `owner_id` 不校验形式，随便什么字符串都只是匹配不到。
- **结论：不一致，一处**：
  - **文档**：设计写“六个阶段都列”，OpenAPI 开头也写 “All six stages are listed”。
  - **代码**：SQL 是 `GROUP BY` 现有数据，没有数据的阶段不出行，OpenAPI 同一段后面也写“one row per … stage that has opportunities”。
  - 集成测试 `funnel_integration_test.go` 断言的是 4 行，不是 6 行。
  - 所以这是文档自相矛盾，代码和测试按“有数据才有行”走。
  - 另外，“形式不对答 400”对 `owner_id` 实际不成立。

## 10. 整套恢复后

- **文档依据**：商机设计“整套恢复之后”；`opportunity/AGENTS.md` 的 `checks.go` 一行；销售设计 QR01、QR02。
- **代码依据**：`opportunity/checks.go` 的 `RecoveryChecks`（`Presence(core.Opportunities, TablePresence("opportunity","id","version"))`）；`quotes/sales.go` 的 `OnSales`；销售 `OnRequested` 与 `lockReceived`。
- **商机组件的核对**：只答被审计过的商机在不在、版本是多少。测试断言：版本高一千答“旧了”，新身份答“不在”。单号允许缺号，没有作废登记。
- **请求停在 `requested`、销售已有草稿**：商机组件不另做核对。靠销售发件表补发或重放的 `erp.quotation.changed` 到达，`OnSales` 写 `sales_link`，再把带请求身份的请求从 `requested` 改成 `drafted`（`WHERE state='requested'`）。
- **反方向**：商机重发的 `quote_requested` 被销售按事实身份去重，不会出第二张草稿。
- **结论：一致**。要说明的是，这个补齐依赖 SDK 的补发（协议 15）真的重投了销售的事件，两边文档和代码都这样设计，我没有实跑。

## 需要处理的三处

1. 商机设计和 OpenAPI 的“六个阶段都列”，要改成“有数据的阶段才出行”，或者代码补零行。
2. 销售的 `BRICKKIT.md` 要补上对 `crm.opportunity.quote_requested.v1` 的订阅和对 `erp.quote_request.rejected.v1` 的发布。
3. OP08 的“审计的操作者记 `system`”与代码不符：要么改文档，要么让审计也记 `system`。
