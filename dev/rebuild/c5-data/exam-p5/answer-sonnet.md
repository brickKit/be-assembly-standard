我没有改任何文件，也没有运行测试，下面都是读文档和代码得出的结论。路径相对 `components/erp/costing`（下称「成本」）或 `components/erp/purchase`（下称「采购」），装配项目正式文档用 `docs/zh/…` 全路径。

八题里有四题发现不一致：Q2 一处代码行为与恢复检查的说明对不上，Q5 一处文档只写了先进先出，Q6 一处提示语文档有、代码没有，Q8 一处措辞有歧义。

## 1. 改计价方法

**文档依据**
- `docs/design.md` 规则 PO01：缺省是移动平均，没写过的法人就是它。法人已有计价过的流水时不能改（`POLICY_IN_USE`），换方法要重估在库价值，不在首批。
- 同文件“拒绝的原因”：版本不对是 `VERSION_CONFLICT`。
- 同文件命令与查询：“修改政策要带版本”。

**代码依据**
- `internal/policies/policies.go` 的 `read`：没有行时按 `moving_average`、版本 0 返回；`InUse` 是 `EXISTS(valued_movement WHERE legal_entity_id)`。
- 同文件 `SetPolicy`，判断顺序是：
  1. 方法必须是 `moving_average` 或 `fifo`，版本必填，否则 400；
  2. 带的版本与当前不同，返回 `VERSION_CONFLICT`（409）；
  3. 方法与当前相同，直接返回，不升版本；
  4. 已有计价过的流水，返回 `POLICY_IN_USE`（409，`internal/core/rules.go`）。
- 所以“已有流水、从移动平均改先进先出”会被拒绝；版本不对时，先报版本冲突，不管有没有流水。
- 计价时 `MethodOf` 会先写一行版本 0 的默认政策（`migrations/0002_valuation.up.sql` 的注释说明了原因：改政策与首次计价锁同一行）。

**一致。** 文档没写版本冲突先于“已在用”的判断顺序，代码有这个顺序，不算矛盾。

## 2. 计价序号缺口（1、2 到，3 没到，4、5 到）

**文档依据**
- 规则 VS03：进入 `waiting_gap`，等 `VALUATION_GAP_WAIT`（缺省 5 分钟，从进入这个状态起算）。
- 到期后在事务外向库存补取（`StockService.Movements`，从 `next_seq` 起，一次至多 1000 条）。补到的按 VS01 收下再处理。
- 缺口后面的流水不论入库出库都等着。
- 库存还没编号：再等一个周期，每次都告警。
- 状态表：`waiting_gap` 下 `value` 变成 `running`。

**代码依据**
- `internal/sequence/process.go`：
  - `missing`：下一号没到、更后的号到了，调 `waitFor(AwaitGap, m.GapWait)`，由 `restartWait` 排一个 `since+wait` 的工作项。
  - `step`：下一号只处理 `movement_in` 里正好是 `next_seq` 的那条，所以 4、5 一直不动。
  - `lock`：算出 `gapDue`。
  - `readGap` / `readBack`：补取并写入 `movement_in`；补到 3 后，下一步 `valueNext` 把 3、4、5 依次计价，状态回 `running`。
  - 库存也没有 3：`readGap` 打 `gap_unfilled` 告警，`restartWait` 再等一个周期。
- `internal/sequence/lifecycle.go` 的表与文档逐格相同。

**不一致：** 恢复检查 `erp.costing.waiting` 的含义与代码行为对不上。
- 文档（“整套恢复之后”）说它报“等了超过一个小时的缺口与依据”。
- `internal/sequence/checks.go` 用 `waiting_since < now() - interval '1 hour'` 判断。
- 但库存一直补不到 3 时，`readGap` 每个周期都调 `restartWait` 并把 `waiting_since` 重写成当前时间。
- 结果：一个一直补不到的缺口，`waiting_since` 永远不会超过 5 分钟，不会被这条检查报出来。只有工作项本身卡住时才会。
- 这条检查自己的处置说明（“库存没有给缺的流水编号”）正是针对补不到的情形。

## 3. 采购收货入库等计价依据

**文档依据**
- 规则 LY01：范围进入 `waiting_basis`，等 `VALUATION_BASIS_WAIT`（缺省 5 分钟，从进入状态起算，期间新流水只收下）。到期按政策价入层，来源 `policy`（待定价），不再挡后面的流水。
- 规则 LY02：依据后到，层当前是 `policy` 时整层换成依据价，按 AD01 出调整；依据币种不是本位币时，按依据的业务日期取即期汇率折算（事务外），折算之前依据不可用，等依据的入库照样等。

**代码依据**
- `internal/layers/layers.go` 的 `Receive`：
  - 有依据且已折算且未撤回（`basisOf` 要求 `base_price IS NOT NULL`）就按依据价；
  - 没有且 `!policy`，返回 `wait`，`valueNext` 调 `waitFor(AwaitBasis)`；
  - `policy` 为 `s.basisDue`，到期后按 `PolicyPrice` 入层。
- `internal/sources/sources.go`：
  - `applyBasis`：依据到达后先折算，再用 `layers.ApplyBasis` 替换政策价并出调整（日期取依据日期），scope 在 `waiting_basis` 时 `Wake`。
  - 外币没有当天即期汇率：`masterdata.RateOf` 返回 `CURRENCY_NOT_USABLE`，`Apply` 把它包成 `work.Wait`（可重试，不限次数）。依据保持未折算、不可用，入库等满 5 分钟后按政策价入层。汇率补上后，依据替换政策价，出调整。

**一致。** 文档只写了“折算之前依据不可用”，没写汇率缺失时工作项等待重试，这只在代码里，不矛盾。

## 4. 先进先出层 10 个、已出 4 个，票据确认 6 个、比依据高 2 元

**文档依据**
- AD01：调整 = 差价 × 数量。
- AD02 先进先出：已出库的数量按确认先后对应，对应已出库的部分进差异，其余调层单价。
- AD01：上调规则键 `cost_adjustment_up`，金额写正数，`grni` 是总额。

**代码依据**
- `internal/layers/sources.go` 的 `ApplyConfirm`：取层里没被票据覆盖的前 6 个单位（第 0–5 个），差价是票据价减层的基础单价（即依据价），这里是 +2。
- `internal/methods/methods.go` 的 `Split`（先进先出）：总额 = 2×6 = 12；已出库 4 个都在这 6 个里，在库的只有 2 个，所以进库存价值 2×2 = 4。
- 同文件：差异 = 12 − 4 = 8。
- `adjust` 发 `cost_adjustment_up`，金额是 `inventory` 4、`variance` 8、`grni` 12，全是正数；调下时三项取绝对值并改发 `cost_adjustment_down`。

**结果：** 进在库价值 4、进差异 8、`grni` 12，规则键 `cost_adjustment_up`，金额都为正。**一致。**

## 5. 移动平均在库 2、出库 5

**文档依据**
- 规则 IS02：够的部分照常，不够的按政策价；在库数量可以变成负数，告警，恢复检查 `erp.costing.negative_stock` 报出。
- 之后的入库先补平：按入库成本与当时政策价成本的差更正销售成本；更便宜发 `cost_of_sales_return`（存货借、销售成本贷）；业务日期取入库日期。
- “先进先出下这几个单位算作已出库”。

**代码依据**
- `internal/issues/issues.go`：
  - `movingAverage` 调 `methods.AverageTake`，成本 = 全部在库价值 + 3 × `PolicyPrice`（范围最近一层的当前单价）；
  - 在库数量 = 2 − 5 = −3，`warnPast` 打 `negative_stock` 告警；
  - 恢复检查在 `internal/sequence/checks.go` 的 `CheckNegative`（`quantity < 0`）。
- 之后入库 10 个：`Receive` 先发 `inventory_receipt`，`sequence/process.go` 随后调 `issues.Level`：
  - n = 3，`took` 是当时按政策价取走的成本，`value` 是这 3 个单位按入库层单价的成本；
  - 差额为负时发 `cost_of_sales_return`，`inventory` 和 `cost_of_sales` 金额都是差额绝对值，业务日期是入库日期。

**不一致：**
- 文档写“先进先出下这几个单位算作已出库”，代码里 `Level` 无论哪种方法都调 `TakeFromLayer`，把这几个单位计入层的已出库数量。移动平均下它不影响调整的分配，也不限制退货，但文档的措辞比代码窄。

## 6. 先进先出下采购按这条收货退 2 个、层只剩 1 个

**文档依据**
- 采购 `docs/design.md` 规则 PO09：装了成本组件时，建退货单之前（事务外）按每条流水问可退数量；同一流水的各行合计超过就整笔拒绝（`RETURN_EXCEEDS_COST_LAYER`）；成本组件不答复时不拦；同一个幂等键的重放不再核对。
- 成本 `docs/design.md` 规则 RT01 与 IC30：拒绝发生在采购发起退货时，提示按无原单的采购退货办理；移动平均不限；问到的在库可能还没扣掉刚发生的出库，超出部分按 IS02 处理并告警。

**代码依据**
- 采购 `internal/returns/returns.go` 的 `CreateReturn`：
  - 步骤一：事务外对每条流水调 `masterdata.ReturnLimit`。
  - 步骤二：进入 `idem.Do` 的事务后，先判订单状态，再调 `withinLayers`，然后才建退货单、逐行扣 `returned_base_qty`。
  - 谁拒绝：采购，不是成本，成本只回答数量。
  - 错误码：`RETURN_EXCEEDS_COST_LAYER`（`internal/core/rules.go`，409，FailedPrecondition）。
- 成本 `internal/issues/issues.go` 的 `ReturnLimit`：返回 `Known`、`Limited = (方法 == fifo)`，`Quantity` 是层的在库数量（这里是 1）；移动平均返回不限制。这个调用只许 `erp/purchase`（`costing/module.go`）。
- 采购 `internal/masterdata/upstream.go` 的 `ReturnLimit`：成本不答复或没部署时，打 `return_limit_unknown` 告警并返回“不限”，退货只受收货流水限制（`RETURN_EXCEEDS_RECEIPT`）。
- 同一幂等键重放：`idem.Do` 命中已存的结果时不跑回调（SDK `idem/idem.go`），所以 `withinLayers` 不执行；`ReturnLimit` 仍在 `idem.Do` 之外被调用，只是答案不参与比较。
- 成本端按序计价时，超出的部分按 IS02 处理：`issues.Return` 走 `TakeFromLayer`，取到 1 个，其余按政策价并告警。

**不一致：**
- 成本 RT01 与协议 05b 的 IC30 说“提示按无原单的采购退货办理”，但代码的错误信息只写“erp/costing has N of movement … in stock”，没有这个提示。
- 采购现在也没有无原单退货（退货单每行必须引用入库流水），所以这个提示在两边都没落地。

## 7. 库存加了新的流水种类（如调拨）

**文档依据**
- 规则 VS02：不认识的种类停下这个范围并告警（`stopped`，原因写种类），不跳过，因为跳过会让后面的成本都错；所以库存加新种类之前，先发布能处理它的成本组件版本。
- VS05：停下的范围不再处理，新流水照样收下，由恢复检查 `erp.costing.stopped_scopes` 报出。

**代码依据**
- `internal/core/values.go` 的 `ParseMovement` 不校验种类，所以这条流水会被收下。
- `internal/sequence/process.go` 的 `valueNext`：`default` 分支打 `scope_stopped` 错误日志，调 `stop(UnknownKind, reason)`，`Lifecycle` 把 `running` / `waiting_gap` 置为 `stopped` 并写原因。
- `step` 对 `Stopped` 直接保存、不处理；`keep` 仍收下后面的流水。
- `internal/sequence/checks.go` 的 `CheckStopped`：每个停下的范围一条差异，写法人、产品与原因，处置是“等能处理这个种类的成本组件版本”。已在 `costing/checks.go` 注册。

**一致。**

## 8. `component.yaml` 的依赖与财务配置

**文档依据**
- `docs/design.md` “依赖”表与 `BRICKKIT.md` “依赖说明”：必需的是 `erp/inventory`、`mdm/org`、`mdm/currency`。订阅的事件不是依赖。
- 原因：采购退货前要调成本，如果成本也声明依赖采购，两边的精确版本会互相钉住，任何一边发布都要另一边再发布，永远对不齐。
- `mdm/product` 首批用不到。
- `BRICKKIT.md` “部署前准备”：财务的 `FINANCE_FACT_SOURCES` 要列出 `erp.costing` 的 `erp.costing.accounting_fact.v1`，否则成本事实等着不过账。

**代码依据**
- `component.yaml` 的 `dependencies.components` 恰是 `mdm/currency@3.0.33`、`mdm/org@3.0.35`、`erp/inventory@3.0.39`，都没标 `optional`。`events.subscribes` 里订阅采购的依据与撤回、财务的票据确认与冲回，库存的流水。
- 采购的 `component.yaml` 反过来把 `erp/costing@3.0.0` 声明为 `optional`。
- 成本的代码没有调用 `mdm/product`；`costing/module.go` 里只订阅事件，没有对采购、财务的调用。
- 财务 `internal/core/base.go`：`FINANCE_FACT_SOURCES` 为空时 `FactSources` 为空；`finance/module.go` 的 `Subscriptions` 只对列表里的项加订阅。不配就不订阅 `erp.costing`，成本事实不过账。
- 成本这边照常写 `costing_fact` 并发布，只供查询（`FactService.Read` 与成本事实列表）。

**一致，但有一处措辞歧义：** 文档说“成本事实等着不过账”。代码只能证明财务没订阅；这些事实日后补配置后能不能补过账，取决于消息系统对流的保留期，我没有去核实这一点。
