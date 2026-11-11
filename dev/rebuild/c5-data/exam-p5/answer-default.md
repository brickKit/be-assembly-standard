以下是逐题核对的结果，没有改任何文件。路径相对 `components/erp/`。装配项目正式文档是 `docs/zh/06-protocols/05b-inventory-costing.md`（下称 05b）。

## 1. 已有计价流水的法人改计价方法；没写过政策的法人；版本不对

**文档依据**
- `costing/docs/design.md` 规则 PO01：每个法人一个方法，缺省移动平均，没写过的法人就是它；按版本修改；已有计价过的流水时不能改，答 `POLICY_IN_USE`。
- 同文件“拒绝的原因”写了 `POLICY_IN_USE` 与 `VERSION_CONFLICT`，命令与查询一节写了“修改政策要带版本”。
- `internal/policies/AGENTS.md` 的说明与此相同。
- 05b 没有写这条（只在参数表里提到政策）。

**代码依据**
- `costing/internal/policies/policies.go` 的 `read`：没有行时返回 `moving_average`、版本 0，`InUse` 来自 `EXISTS (SELECT 1 FROM valued_movement WHERE legal_entity_id=…)`。
- `SetPolicy` 里依次判断：
  1. `*in.Version != p.Version` → `ErrVersion`（`VERSION_CONFLICT`，409）。
  2. 方法没变 → 什么都不改，也不升版本。
  3. `p.InUse` → `ErrPolicyInUse`（`POLICY_IN_USE`，409）。
- 修改时 `FOR UPDATE`，计价时 `MethodOf` 持 `FOR SHARE`，两者互斥。

**结论：一致。**
- 已有计价流水的法人要改方法，会被 `POLICY_IN_USE` 拒绝。
- 没写过政策的法人用移动平均，版本 0。
- 版本带错答 `VERSION_CONFLICT`。
- 版本不对且已在用时，先报 `VERSION_CONFLICT`，因为版本判断在前。
- “同一方法再设一次不报错、不升版本”只在代码里，文档没写，不算矛盾。

## 2. 序号 1、2 到了，3 没到，4、5 到了

**文档依据**
- `design.md` VS03：下一号没到而更后的号已到，范围进入 `waiting_gap`，等 `VALUATION_GAP_WAIT`（起始 5 分钟）后补取。
- 到期在事务外向库存补取，补到的按 VS01 收下再处理；一批取满 1000 条就接着取。
- 补不到（库存那边还没编号）就再等一个周期，每次都告警。缺口补齐之前不计算后面的成本。
- 状态表“缺口补上了 → running”。
- 05b “计算与缺口”一节、参数表“计价序号的缺口等待 5 分钟”、IC02。

**代码依据**
- `internal/sequence/process.go`：
  - `missing`：有更后的号 → `waitFor(AwaitGap, m.GapWait)`，写 `waiting_since` 并 `EnqueueAt` 到期的工作项。
  - 到期时 `lock` 算出 `gapDue`，`missing` 返回 `refetch`，再调 `readGap` → `readBack` → `masterdata.Movements`（每批 `core.MaxRefetch`）。
  - 补到 3：`valueNext` 里 `Value` 命令在 `waiting_gap` 下转 `running`，3、4、5 依次计价。
  - 库存也没有 3：`readGap` 打 `gap_unfilled` 告警，`restartWait` 再等一个周期。
- `core/base.go`：`DefaultGapWait = 5 * time.Minute`。
- `sequence/lifecycle.go` 与设计表逐格相同（单元测试比较）。
- `sequence/checks.go`：`erp.costing.waiting` 报出等了超过一小时的范围。

**一致。**
- 4、5 在 3 到齐之前不计价。
- 默认等 5 分钟，到期向库存补取，补到后按 3、4、5 依次计价。
- 库存也没有 3 时，每个周期告警一次，继续等。

## 3. 采购收货的入库流水先到，收货计价依据还没到

**文档依据**
- `design.md` LY01：
  - 来源是采购收货（参考种类 `purchase_receipt`，`line_id` 是收货行）时按收货行找依据。
  - 没到就进入 `waiting_basis`，等 `VALUATION_BASIS_WAIT`（起始 5 分钟，期间新流水只收下）。
  - 到期按政策价入层、来源 `policy`（待定价），不再挡后面的流水。
- LY02：
  - 依据后到时，政策价层整层换成依据价，按 AD01 出调整。
  - 外币依据按依据业务日期取即期汇率，折算之前依据不可用，等依据的入库照样等。
- 状态表：`waiting_basis` + 依据到达 → `running`；依据到期 → 按政策价入层。
- 05b 的“政策价（待定价）”与参数表。

**代码依据**
- `layers/layers.go` `Receive`：
  - `basisOf` 只取 `base_price IS NOT NULL` 且没被撤回的依据。
  - 没有且 `!policy` 时返回 `wait=true`，什么都不写。
  - `valueNext` 据此 `waitFor(AwaitBasis, m.BasisWait)`。
- 到期（`s.basisDue`）：`Receive` 用 `PolicyPrice` 入层，来源 `policy`，命令 `BasisDue` → `running`。
- 依据后到：`sources.OnBasis` → `Apply` → `applyBasis`。
  - 事务外用 `convert` / `masterdata.RateOf` 折成本位币，事务内 `layers.ConvertBasis`、`ApplyBasis`（`adjust` 发调整）。
  - 若范围在 `waiting_basis`，再 `sequence.Wake`。
- 外币且当天没有汇率：`RateOf` 答 `CURRENCY_NOT_USABLE`，`Apply` 里 `work.Wait(err)` 等汇率再试。
  - 这期间 `base_price` 为空，`basisOf` 当它不可用，入库照样等。
  - 等满时按政策价入层，汇率到了以后按 LY02 替换。

**一致。**
- 小的差别：文档没写“依据在等待期内先到但还没折算完”这一情形。代码里它也走 `basisOf` 的 `base_price IS NOT NULL` 条件，行为与“折算之前不可用”相符。

## 4. 先进先出：层 10 个、已出库 4 个，票据确认 6 个单位，比依据高 2 元

**文档依据**
- `design.md` AD01、AD02：
  - 先进先出下，层上已出库的数量按票据确认到达的先后对应。
  - 对应已出库的部分进差异，其余调层的单价。
  - 调高发 `cost_adjustment_up`（`inventory`、`variance` 借，`grni` 贷），`grni` 的金额是总额。
- LY03：确认占层的前几个单位，出库从层的前面取。
- 05b 的差异去处表与 IC24。

**代码依据**
- `layers/sources.go` `ApplyConfirm`：`take(l.uncovered(), x.Quantity)` 取前 6 个单位（0 到 6），`adjust` 里用 `core.Minus(*c.BasePrice, l.Base.Price)` 作差额。
- `methods/methods.go` `Split`（FIFO 分支）：
  - 总额 = 2 × 6 = 12。
  - 已出库的单位 `gone = min(issued=4, 6) − 0 = 4`，在库的是 2 个。
  - 进库存价值 = 2 × 2 = 4，进差异 = 12 − 4 = 8。
- 发的事实：规则键 `cost_adjustment_up`；金额 `inventory=4`、`variance=8`、`grni=12`，都是正数。
- 总额为负时才换 `cost_adjustment_down`，并把三个金额取反成正数。

**一致。**
- 进在库价值 4，进差异 8，规则键 `cost_adjustment_up`，金额为正（方向由规则键表达）。
- 前提是这张票据是该层的第一张确认。

## 5. 移动平均：在库 2、出库 5；之后入库 10，单价低于当时的政策价

**文档依据**
- `design.md` IS02：够的部分照常，不够的部分按政策价计，在库数量可为负，告警，恢复检查 `erp.costing.negative_stock` 报出。
- 之后的入库先补平：前几个单位的入库成本与当时按政策价取的成本之差，更正销售成本。
  - 入库更贵发 `cost_of_sales`。
  - 更便宜发 `cost_of_sales_return`（存货借、销售成本贷）。
  - 业务日期是入库的日期。
- LY01 的政策价：最近一层的当前单价，没有层时用移动平均，都没有是 0。
- 未决问题表“补平的差额记到哪里”。

**代码依据**
- `issues/issues.go` `movingAverage` → `methods.AverageTake`：
  - 取全部在库价值，加上超出的 3 个 × 政策价。
  - `s.Quantity = 2 − 5 = −3`。
  - `warnPast` 打 `negative_stock` 日志。
- `sequence/checks.go` `CheckNegative`：`quantity < 0` 的范围报成差异。
- 入库后 `Receive`：发 `inventory_receipt` 事实，数量 +10。
  - 随后 `valueNext` 调 `issues.Level`：`n = min(10, 3) = 3`。
  - `took = 3 × beforeValue ÷ before`，`TakeFromLayer` 取新层前 3 个的价值，`diff = value − took`。
  - 为负时发 `cost_of_sales_return`，`inventory` 与 `cost_of_sales` 金额都是 |diff|。

**一致。**
- 出库按“全部在库价值 + 3 × 政策价”计价。
- 在库变为 −3，由日志告警和 `erp.costing.negative_stock` 报出。
- 之后入库 10 个：先发 `inventory_receipt`，再发一条 `cost_of_sales_return`（金额为差额的绝对值）。
- 有一处细节文档没写：`Level` 里 `TakeFromLayer` 对移动平均也会增加层的已出库数量，设计只写了先进先出下“算作已出库”。这对移动平均没有影响，因为 `Split` 的移动平均分支不读 `issued`，可以视为文档略写。

## 6. 先进先出下，层只剩 1 个，采购要退 2 个

**文档依据**
- costing `design.md` RT01：
  - 先进先出下退货不能超过原层在库数量（IC30）。
  - 拒绝在采购发起退货时发生，用 `LayerService.ReturnLimit`（先进先出是层的在库数量，移动平均不限）。
  - 超过就拒绝，提示按无原单的采购退货办理。
  - 计价异步，真超出的部分按 IS02 处理并告警。
- purchase `docs/design.md` PO09：
  - 建退货单之前（事务外）按每条流水问可退数量。
  - 同一流水各行合计超过就整笔拒绝，错误码 `RETURN_EXCEEDS_COST_LAYER`。
  - 成本组件不答复时不拦（它按在库不够计价并告警）。
  - 同一个幂等键的重放不再核对。
- 依赖表里 `erp/costing` 是“可选”。
- 05b 的退货表与 IC30。

**代码依据**
- `purchase/internal/returns/returns.go` `CreateReturn`：
  - 事务外对每条流水调 `masterdata.ReturnLimit`。
  - 在 `idem.Do` 的事务里，先 `orders.Lifecycle.Decide`，再 `withinLayers`：同一流水各行合计大于限额，就返回 `core.ErrReturnExceedsLayer`，早于任何 `INSERT`。
- `purchase/internal/core/rules.go`：`RETURN_EXCEEDS_COST_LAYER`，409。
- `purchase/internal/masterdata/upstream.go` `ReturnLimit`：
  - 没装、报错、`!Known` 或 `!Limited` 一律返回 `("", false)`，即不限；报错时打告警。
  - 所以成本组件不答复时不拦，之后由成本组件按 IS02 计价并告警。
- 重放：`idem.Do` 对重放直接返回原结果，不再执行事务内的比较，所以不核对。
  - 但 `ReturnLimit` 在 `idem.Do` 之前，重放时照样会问一次，只是结果不用。
- `costing/internal/issues/issues.go` `ReturnLimit`：
  - 先进先出 `Limited=true`、`Quantity` = 层在库数。
  - 移动平均 `Limited=false`；层不存在（还没计价）时 `Known=false`。
  - 这个函数只回答，不拒绝。
- 移动平均的法人：不限，退货正常通过。`issues.Return` 按层的加权单价出库，并 `MarkGone`。

**一致。**
- 拒绝的是采购（`erp/purchase`），错误码 `RETURN_EXCEEDS_COST_LAYER`（409）。
- 判断在 `CreateReturn` 的事务里的 `withinLayers`，在建退货单与行之前。
- 成本组件不答复时不拦。
- 重放不核对（代码里“不重新比较”，但仍会向成本组件问一次，文档说“不再核对”，效果一致）。
- 移动平均不限。
- 在这些之外，文档没写“退货单整笔被拒、不产生任何行”，代码里是这样，purchase 的 `AGENTS.md` 有写。

## 7. 库存以后加一种新的流水种类（如调拨）

**文档依据**
- costing `design.md` VS02：不认识的种类（以后的调拨、调整、期初、销售退货）停下这个范围并告警，原因写种类，不跳过。
- 理由：跳过会让后面的成本都错，所以库存加一种流水之前，先发布能处理它的成本组件版本。
- VS05：停下的范围不再处理，新流水照样收下；恢复检查 `erp.costing.stopped_scopes` 报出它与原因。
- 状态表 `unknown_kind` 一行。
- “整套恢复之后”一节再列了这三个检查。
- 05b 没有写这一条（只讲范围内调拨记一笔）。

**代码依据**
- `sequence/process.go` `valueNext`：`switch mv.Kind` 的 `default` 分支。
  - 打 `scope_stopped` 错误日志，原因文字里有流水身份、序号、纪元与种类。
  - `stop(ctx, tx, s, UnknownKind, reason)` 转入 `stopped`，写 `stopped_reason`。
- `step`：`stopped` 的范围只 `save(queued=false)` 返回 `idle`，不再计价；新流水仍由 `keep` 放进 `movement_in`。
- `sequence/lifecycle.go`：`UnknownKind` 在 `running`、`waiting_gap` 下 → `stopped`，在 `waiting_basis` 下忽略。
- `sequence/checks.go`：`CheckStopped`（`erp.costing.stopped_scopes`）报每个 `state='stopped'` 的范围，带 `stopped_reason`，并写处置建议。
- `core.ParseMovement` 不校验种类，所以新种类能进到 `valueNext` 才被停下。

**一致。**
- 新种类的流水到了会停下这个范围并告警，不跳过。
- 恢复检查 `erp.costing.stopped_scopes` 按范围报出，带原因。

## 8. 成本组件的依赖声明；订阅与依赖；财务没配 `FINANCE_FACT_SOURCES`

**文档依据**
- costing `design.md` 依赖表：`erp/inventory`、`mdm/org`、`mdm/currency` 必需。
- 同文件下面的说明：订阅的事件不是依赖（本组件不调用它们，`component.yaml` 只在 `events.subscribes` 列上）。
  - 采购退货前调用本组件（RT01），本组件若也声明依赖它，两边的精确版本互相钉住，任何一边发布都要另一边再发布，永远对不齐。
  - 没装采购时入库都按政策价；没装财务时暂估不被调整，成本事实也没人过账，只供查询。
- `BRICKKIT.md` “依赖说明”与“部署前准备”：财务的 `FINANCE_FACT_SOURCES` 要列出 `erp.costing` 的 `erp.costing.accounting_fact.v1`，法人的科目映射要有成本的六条规则，否则成本事实等着不过账。
- `finance/docs/design.md` ST01：按 `FINANCE_FACT_SOURCES` 订阅，没填就不订阅。

**代码依据**
- `costing/component.yaml`：
  - `dependencies.components` 是 `mdm/currency@3.0.33`、`mdm/org@3.0.35`、`erp/inventory@3.0.39`，都不是可选。
  - `events.subscribes` 里是库存的流水、采购的依据与撤回、财务的票据单价确认与冲回。
- 对照 `purchase/component.yaml`：`erp/costing@3.0.0` 是 `optional: true`，方向正是文档说的那一边。
- `finance/internal/core/base.go`：`FINANCE_FACT_SOURCES` 为空串时 `FactSources` 为空。
- `finance/finance/module.go` `Subscriptions`：只对 `FactSources` 里的每一项加订阅，没有默认来源。
- 所以没配时财务不订阅 `erp.costing`，成本事实留在成本组件的 `costing_fact` 里，只能经用户面与 `FactService.Read` 查询。

**一致。**
- 声明的依赖是 `mdm/currency`、`mdm/org`、`erp/inventory` 三个。
- 订阅不声明依赖，是为了避免与采购的互相钉版本。
- 财务没配 `FINANCE_FACT_SOURCES` 时，成本事实只供查询，不过账。

## 总结

八题里文档与代码都没有发现“不一致”的地方。需要留意的只有两点，不影响结论：
- **第 5 题**：`Level` 对移动平均也记层的已出库数量，设计 IS02 只写了先进先出，属文档略写。
- **第 6 题**：重放时仍会向成本组件问一次可退数量，只是不再比较，设计文档说的是“不再核对”，措辞略有出入。

此外，`costing/docs/design.md` 的 RT01 与实现状态里还写着“采购的改动随 P5 做”，而采购 3.0.4 已经做完（`purchase/docs/design.md` 第 172 行）。这是装配过程中的叙述，不是规则冲突，若要整理可以顺手改成现状。
