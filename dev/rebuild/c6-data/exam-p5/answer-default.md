我读了两个组件的文档与代码，没有改任何文件。统计：10 题里 9 题一致；第 8 题有一处不一致，另有 4 处文档与代码的细节差异，列在文末。表中的原因码是文档与代码写的字面值；没有跑集成测试，运行时行为按代码推断，上游（`mdm/*`、SDK）的返回值也没有实测。

路径简写：商机组件在 `components/crm/opportunity/`，下称“商机”；销售在 `components/erp/sales/`，下称“销售”。

## 1. 新建商机时指定负责人、客户没有客户角色

**文档依据**：商机 `docs/design.md` OP01、OP04、命令表；`BRICKKIT.md` 契约索引的 `.assign`。
**代码依据**：`internal/opportunities/commands.go` 的 `Create`；`internal/masterdata/upstream.go` 的 `CustomerOf`；`cmd/seed/main.go` 的授予。

- **普通销售把负责人写成同事**：被拒。
  - `Create` 先用同事作负责人去核对 `edit`。种子里普通销售的 `owner` 范围是 `self`，所以在这一步就被拒，后面的 `assign` 检查不会走到。
  - 文档说的是“指定别人要 `assign`，否则能绕过 OP04”，结果相同，只是被拒的位置在 `edit`。
- **销售主管**：允许。
  - 种子给 `test.unit.admin.cn` 的授予含 `assign`，范围是 CN01 的全部负责人。
  - 商机落在指定的同事名下。
- **客户在该法人下没有客户角色**：答 `CUSTOMER_NOT_ELIGIBLE`。
  - `CustomerOf` 调伙伴的资格检查（用途 `sell`），不合格就带伙伴给的原因，如 `role_not_opened`。
  - 取证在事务之前，所以什么都不写。

一致。

## 2. 商机在 proposal（概率 50）

**文档依据**：OP03 与商机状态表。
**代码依据**：`changes.go` 的 `Move`、`commands.go` 的 `checkStage`、`core/names.go` 的 `OpenStages`。

| 操作 | 结果 |
| --- | --- |
| 推进到 negotiation | 成功，概率 75（命令里给了概率就用给的）。 |
| 推进到 won | `STAGE_ORDER`。`checkStage` 在进事务前就拒绝，won、lost 只能经赢单与输单到达。 |
| 回退到 qualification，不写原因 | `REQUEST_INVALID`（`reasonOf`，字段 `reason`）。这个检查在状态检查之前。 |
| 回退到 qualification，写了原因 | 成功，概率 10。 |

每次成功都写一行阶段历史和一个 `stage_changed` 事实。

一致。

## 3. 商机赢单之后

**文档依据**：OP02、OP05、OP06、OP07。
**代码依据**：`lifecycle.go` 的表；`changes.go` 的 `Edit`、`Close`、`Win`、`reopen`。

| 操作 | 结果 |
| --- | --- |
| 改名称 | 允许（预计成交日同样允许）。 |
| 改金额 | `WON_AMOUNT_LOCKED`。 |
| 再赢单一次 | 忽略：答成功，不发事实，不升版本。 |
| 输单 | `STATE_CONFLICT`。 |
| 请求报价 | `STATE_CONFLICT`。 |
| 重开（要写原因） | 回到关闭前的阶段与概率，清掉赢单金额、关闭原因与关闭时间。 |
| 重开之后再赢单 | 新的一次关闭，照样发事实。 |

- **赢单金额**：不给就用预计金额（`Close` 里 `amount := o.Amount`），给了就按币种小数位校验。赢单金额的币种就是商机的币种。
- **一处措辞缺口**：代码把概率也算进锁定项（`Edit` 里的 `locked` 含 `Probability`）。OP02 的列举没有写概率；但同一格写了“只改名称与预计成交日时允许”，实际行为被它覆盖。

一致，仅措辞缺口。

## 4. 请求报价与幂等

**文档依据**：OP05。
**代码依据**：`internal/quotes/request.go` 的 `RequestQuote`。

- **同一个幂等键提交两次**：1 个请求、1 个 `quote_requested` 事实。第二次重放第一次的结果，返回同一个请求身份。
- **不同的键提交两次**：2 个请求、2 个事实，各有自己的身份。一个商机可以有多个请求，OP05 明说了。
- **请求时给了明细**：
  - 先经 `CheckLines` 校验。
  - 请求的明细快照用给的这份，同时替换商机自己的明细（`WriteLines`）。
  - 不给明细就用商机现有的。

一致，但文档缺一处：请求报价走的是 `ChangeIn`，会升商机版本、发一次 `changed` 完整状态事件、写 `edit` 审计。OP05 没提。

## 5. 销售收到请求报价事件

**文档依据**：销售 `docs/design.md` QR01–QR04。
**代码依据**：`internal/quoterequests/quoterequests.go` 的 `OnRequested`、`DraftJob`、`evidence`、`draft`、`refuse`。

- **同一事件收两次**：只生成 1 张草稿。
  - `quote_request_in` 按事实身份插入，`ON CONFLICT DO NOTHING`，第二次不再排工作。
  - 事务里还有 `lockReceived`，报价表上 `quote_request_id` 唯一，两道兜底。
- **客户在取证时已不合格**（法人或币种不可用同理）：
  - 不生成草稿，请求变 `rejected`。
  - 发 `erp.quote_request.rejected.v1`，原因是 `NOT_ELIGIBLE`（法人、币种分别是 `LEGAL_ENTITY_NOT_USABLE`、`CURRENCY_NOT_USABLE`），事实身份等于请求身份。
- **主数据不可达**：`evidence` 只把三个声明过的原因当作拒绝，其余错误原样返回，工作重试（`MaxAttempts: Unlimited`），不拒绝也不出草稿。我没有核对销售的 `masterdata` 在不可达时具体返回什么错误，只确认它不会被转成拒绝。
- **草稿上有**：
  - 单号 `QT`、法人、客户及名称与税号的快照、币种、负责人（取请求的）。
  - 商机参考 `opportunity_ref`、请求身份 `quote_request_id`、请求的产品 `requested_products`。
  - 草稿的创建经 `documents.EmitQuotation` 发出报价事件，写审计时没有用户操作者。
- **草稿上没有**：明细、有效期、部门。

一致，但文档缺一处：格式不对的请求（法人、客户、币种、负责人的格式）也以 `NOT_ELIGIBLE` 拒绝，QR04 没写这一类。

## 6. 草稿发出、补明细、接受转订单

**文档依据**：销售 QR05、数据表（`sales_order` 一行）。
**代码依据**：`internal/quotations/quotations.go` 的 `QuotationAction`、`UpdateQuotation`、`AcceptQuotation`；`internal/core/records.go` 的 `OrderCols`、`EmitOrder`。

- **无明细时发出**：`REQUEST_INVALID`（字段 `lines`）。已经是 `sent` 时重复发出照旧答成功。
- **补明细**：改报价时给了明细就整体替换，`BuildLines` 要求至少一行，所以补完才能发出，之后可以接受。
- **订单上的商机参考**：订单表没有这一列。订单读取时用子查询按 `quotation_id` 取报价的 `opportunity_ref`（`records.go` 227 行）。
- **订单事件里**：有。`Order.OpportunityRef` 在订单事件里，schema 的 required 里也有，手工建的订单是 null。

一致。

## 7. 部署设置为 order_confirmed

**文档依据**：商机 OP08、未决问题。
**代码依据**：`internal/quotes/sales.go` 的 `OnSales`、`AutoWins`；`opportunities.Win`。

- **订单确认事件到达、商机在进行中**：
  - 先记 `sales_link`，再按设置赢单。
  - 赢单金额是订单的不含税合计，概率 100。
  - 阶段历史与审计里没有用户操作者：阶段历史写 `system`，触发记订单身份。
- **同一事件再来一次**：什么也不发生。`sales_link` 的更新带 `WHERE version < 新版本`，影响 0 行就直接返回。
- **更旧版本的订单事件晚到**：同上，被丢弃，也不会影响自动赢单。
- **订单币种与商机不同**：赢单金额用商机的预计金额，阶段历史的原因写明“won by sales_order … in <币种>: the expected amount is kept”。
- **商机已输单**（已赢单同理）：只记 `sales_link`，不改状态。
- 订单只有 `confirmed` 才赢单；quotation 事件、订单草稿都只记下。

一致。小疑点：OP08 写“审计的操作者记 `system`”，代码调 `ChangeIn` 时给审计传的是空串 `""`，只有阶段历史写了 `system`。SDK 的审计会不会把空串转成 `system`，我没有核实（在 `tools/be-sdk-go/audit` 里搜 `Actor == ""`、`"system"` 没有命中）。

## 8. 互不依赖，怎样找到对方的事件

**文档依据**：商机 `design.md` “规则要点”第一条与“依赖”表；销售 `design.md` QR01、“订阅”一节；两边的 `BRICKKIT.md`。
**代码依据**：两个 `component.yaml`；商机 `opportunity/module.go` 的 `Subscriptions`；销售 `sales/module.go` 的 `Subscriptions`。

- **商机的 `component.yaml`**：
  - 依赖只有 `mdm/currency`、`mdm/org`、`mdm/partner`，没有 `erp/sales`。
  - 订阅 `erp.quotation.changed.v1`、`erp.sales_order.changed.v1`、`erp.quote_request.rejected.v1`。
  - 发布 5 个 `crm.opportunity.*` 事件。
- **销售的 `component.yaml`**：
  - 依赖里没有 `crm/opportunity`。
  - 订阅 `crm.opportunity.quote_requested.v1` 与 `mdm.org_unit.changed.v1`。
  - 发布含 `erp.quote_request.rejected.v1`。
- **代码怎样找到对方**：按流名加事件类型订阅。商机订阅销售的流 `erp.sales`（订阅名 `sales-documents`），销售订阅商机的流 `crm.opportunity`（订阅名 `quote-requests`）。流名常量在两边各写一份。
- 商机组件的文档与代码一致。

**不一致：销售的 `BRICKKIT.md` 没有写商机请求报价。** 它没有任何一处提到商机、请求报价或 3.0.50，而 `component.yaml`、`design.md` 与代码都有：
- “部署前准备”只写订阅 `mdm/org`，没写订阅 `crm.opportunity.quote_requested.v1`。
- “契约索引”的事件列表缺 `erp.quote_request.rejected.v1`。
- “组件定位”里没有这项能力。

商机的 `BRICKKIT.md` 写了“销售 3.0.50 起订阅”，两边对不上。这份文档会随版本进入每个使用它的项目、脱离仓库单独读。

## 9. 漏斗

**文档依据**：商机 `design.md` 命令与查询的漏斗一行。
**代码依据**：`internal/forecast/funnel.go`、`itest/funnel_integration_test.go`。

- **赢单**：金额与加权都用赢单金额（概率 100，加权等于赢单金额）。
- **输单**：加权为 0（概率 0）；金额列用预计金额，文档没单独说。
- **加权的舍入**：SQL 先按（金额 × 概率 / 100）汇总，再按币种小数位舍入，`HalfAwayFromZero`。测试里 209.9989 变 210。
- **普通销售看到的范围**：只算看得见的商机。范围由 `list.Build` 按资源定义编进查询，测试里 Dave 只看到自己的 1 条。
- **筛选值形式不对**：`legal_entity_id` 不是 UUID，或 `close_from`、`close_to` 不是 `YYYY-MM-DD`，答 `REQUEST_INVALID`（400），不会成为 500。`owner_id` 是文本，不校验形式。

**不一致：文档写“六个阶段都列”。** 代码只返回有商机的（法人、币种、阶段）组；测试里 6 个阶段只有 4 行，并且断言 `Len(all, 4)`。文档这句可以读成“阶段取值含赢单与输单”，也可以读成“空阶段也列零行”，应改清楚。

## 10. 整套恢复之后

**文档依据**：商机 `design.md` “整套恢复之后”。
**代码依据**：`opportunity/checks.go` 的 `RecoveryChecks`；`quotes/sales.go` 的 `OnSales`。销售那一侧没有对应的恢复核对（`internal/recoverycheck` 与 `sales/checks.go` 里没找到 `quote_request_in`），文档也没声称有。

- **商机的核对**：只有一项，`Presence(core.Opportunities, TablePresence("opportunity","id","version"))`。回答审计里记过的商机还在不在、版本是多少。单号是允许缺号的序列，没有要作废的号。
- **请求停在 `requested` 而销售已有草稿**：商机不另做核对，靠重投递补齐。
  - 销售的报价事件重新到达，`OnSales` 插入 `sales_link`，再把对应请求改成 `drafted` 并记报价身份。
  - 请求报价事件的重复投递，销售按事实身份去重，不会出第二张草稿。
- **边界**：`sales_link` 已存在同版本或更新版本时，`OnSales` 直接返回，不再碰请求。两个更新在同一事务里，正常情况下不会出现“链接在、请求没更新”。

一致。

## 文档与代码不一致或文档缺失

1. **销售的 `BRICKKIT.md` 没有写商机请求报价**（第 8 题）。这是唯一一处整份文档缺失。
2. **商机设计的漏斗写“六个阶段都列”**，代码只列有数据的组（第 9 题）。
3. **OP02 没有把概率列进赢单后锁定的字段**，代码锁了（第 3 题）。
4. **OP05 没写请求报价会升商机版本、发 `changed` 事件、写审计**（第 4 题）。
5. **QR04 没写格式不对的请求也以 `NOT_ELIGIBLE` 拒绝**（第 5 题）。
6. **OP08 写“审计的操作者记 `system`”**，代码给审计传空串，SDK 是否转换未核实（第 7 题）。

边界卡 `docs/zh/07-components/crm.md` 与决定 A71 与两个组件一致：只经事件，请求报价由销售生成带商机参考的报价，赢单按部署设置手动或自动。
