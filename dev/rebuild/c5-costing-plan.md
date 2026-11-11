# C5：`erp/costing` 的子计划

阶段“按依赖顺序重建其余组件”的第五个组件（[components-plan.md](components-plan.md) 的 C5）。照 C2–C4 的做法：先定首批范围与源头要补的能力，按改动的循环做，每一步先写红的测试，改坏检查，发布，真机格从空库到 L3。数据与改坏检查放 `c5-data/`。

## 依据与牵动

- 边界卡 `docs/zh/07-components/erp-finance.md#erpcosting`（范围：当前重建，新身份，D46）；协议 05b（存货成本：输入、计价序列、计算与缺口、暂估与调整、退货、输出与对账、期初、参数）、05（会计事实契约、共同规则、供应商票据发布的事实）、06（关账与迟到）；业务流程 `procure-to-pay.md` 第 3、5 步，`order-to-cash.md` 的出库成本；决定 D45、D46、D50。
- 上下游现在的状态（2026-11-11 读契约）：
  - `erp/inventory`：流水事件 `erp.inventory_movement.recorded.v1` 已带 `valuation_seq`（“产品 + 法人”的计价序号）与 `inventory_seq`、采购退货的 `origin_movement_id`；**没有按计价序号补取流水的系统面**（只有按流重发 `Resend`）。
  - `erp/purchase`：收货计价依据 `erp.purchase_receipt.valuation_basis.v1` 与撤回（3.0.1 起撤回的身份由依据推出）已发布。
  - `erp/finance`：票据单价确认与冲回已发布；会计事实按装配清单订阅（`FINANCE_FACT_SOURCES`）；**规则目录里还没有成本的规则键**。
  - `erp/sales`：销售退货引用原出库流水（库存的流水 `kind` 里 `sales_return` 写的是“以后”）。
- 仓库：`brickKit/erp-costing`（C0 已批准“在任务开工时建”；2026-11-11 建，挂在 `components/erp/costing`）；注册表已有端口 8229/9229 与 schema。

## 任务

| # | 要做到什么 | 依赖 | 验收 | 状态 |
| --- | --- | --- | --- | --- |
| P0 | 读全依据，列出首批范围：每个能力做或不做（不做的写理由与触发条件），要维护者定的业务问题一次问一个 | — | 本计划“P0 的结果” | 草稿（下面，AI 定，待复核） |
| P0b | 源头补能力（见“P0 的结果”的“源头要补的”） | P0 | 各源头的集成测试与发布 | ✅ 2026-11-11：库存 3.0.39（按计价序号读流水）、财务 3.0.4（成本的六条规则键）；第 3 项查完（销售退货没有来源，移到“不在首批”）；连锁：采购 3.0.3、财务 3.0.5、销售 3.0.49、账单 3.0.58、收付款 3.0.4、外壳 `be/go-core` 3.0.93（`c5-data/cascade-p0b/`、`c5-data/shells-p0b.sh`）；`make version-check`、`make authz-keys-check` 通过 |
| P1 | 设计文档 `docs/design.md`，考设计 | P0、仓库 | 文档与考试记录 | ✅ 2026-11-11：仓库 `brickKit/erp-costing` 建好（第一次建仓库的命令被 Claude Code 的自动权限检查拦下，维护者加了允许规则）；设计（组件仓库 `73942c9`）：计价进度与成本层两张生命周期表、规则 PO01、VS01–VS05、LY01–LY05、AD01–AD02、IS01–IS02、RT01–RT02、CF01；考设计两份（`c5-data/exam-p1/result.md`）：先进先出的单位按票据确认的先后分配（IC24）、新纪元从 1 起的接法（协议 05）、采购退货按协议拒绝（本组件系统面 `ReturnLimit`，采购随 P5 改）等；源头补了一项：`erp/finance` 3.0.6 的票据单价确认带票据日期（契约 alpha.4 给确认与冲回加 `business_date`），连锁 `erp/payment` 3.0.5、外壳 `be/go-core` 3.0.94（`c5-data/cascade-p0c/`、`shells-p0c.sh`）。`make version-check` 在组件 3.0.0 发布前只报 `erp/costing` 没有标签（同 C2、C3，P5 验收） |
| P2 | 契约（用户面、系统面、事件；成本事实按财务的会计事实契约）；注册表与套件的授权登记表跟上 | P1 | 契约生成、`make registry-check`、`make authz-keys-check` | ✅ 2026-11-11（组件仓库 `7b86b18`，`contract/v3.0.0-alpha.1`：用户面 7 条路由（计价政策读与改、计价进度列表与读取（含估值与先进先出的在库层）、成本层列表与读取、成本事实列表）；系统面 `FactService.Read`、`LayerService.ReturnLimit`（只许 `erp/purchase`；没计价时 `known` 为假、不限）；事件 1 种 `erp.costing.accounting_fact.v1`，只是指向财务共享契约的 `$ref`；`make check`、`openapi-spec-validator`、`check-jsonschema` 通过；注册表已有端口 8229/9229 与 schema `erp_costing`，`make registry-check` 通过；授权表随 P3a 的组件定义跟上） |
| P3 | 实现（拆子步）；标准布局与测试索引；先写红的测试 | P2 | L1–L2 与集成测试、改坏检查、`make layout-check` | 进行中 |
| P3a | 骨架：照 `erp/payment` 的布局（入口 `costing/`、`internal/`、`itest/`、迁移、清单、`BRICKKIT.md`、各层说明），组件定义，路由先都答“能力不支持”，`contract_test.go`；集成测试的框架与替身（`mdm/org`、`mdm/currency`、库存的 `Movements`）；套件的授权登记表 | P2 | `go test ./...`、集成测试、`brickkit lint`、`make layout-check`、`make authz-keys-check` | ✅ 2026-11-11（组件仓库 P3a 提交：入口 `costing/`（7 条路由先答“能力不支持”，`FactService.Read` 已接上，`LayerService` 登记为只许采购）、`core`（法人一个维度；三种列表共用资源 `erp.costing.valuation`；自己的两个配置键 `VALUATION_GAP_WAIT`、`VALUATION_BASIS_WAIT`）、`facts`、`masterdata`、迁移（`costing_fact`）、清单（必需 `erp/inventory` 3.0.39，可选采购与财务）、各层说明；`itest/` 的框架与替身；套件 `ea03c3c`：授权表、维度、端口、生产者加成本（标签随 P5）；`go test`、集成测试、`brickkit lint`、`make layout-check`、`make authz-keys-check` 通过） |
| P3b | 计价政策（PO01）与计价序列（VS01–VS05），带上 LY01（依据入层、等依据、政策价）与移动平均出库（IS01）、入库与出库的成本事实（CF01）、计价进度的读取与列表 | P3a | 集成测试、生命周期表的单元测试（与设计逐格）、改坏检查、`make layout-check` | ✅ 2026-11-11（组件仓库 `d970aa8`）：模块 `policies`、`sequence`（表 `scope`、`movement_in`、`valued_movement`；处理工作 `process-scope` 每步一个事务，事务之间补取缺口或把旧纪元补到底）、`layers`（`cost_layer`、`layer_source`、`basis`）、`issues`、`facts.Publish`；设计的计价进度表改成每格一种结果（原表一格两种结果，检查读不了）；改坏检查 8/8（`c5-data/mut-p3b-costing/`；第一轮 7/8，出库按整数舍入活下来，补了带分的情形）。没做的写进设计的实现状态：外币依据折算、IS02 的之后入库补平 |
| P3c | 成本层的单价来源（LY02–LY05）与调整（AD01–AD02）；原计划的 P3d（调整）并进来：来源替换必然出调整，分开就测不了 | P3b | 集成测试、两张生命周期表与设计逐格、`methods` 的单元测试（IC24、IC25）、改坏检查 | ✅ 2026-11-11（组件仓库 `e82b919`）：新模块 `sources`（四种订阅、折本位币的工作 `apply-source`、按范围顺序加锁）、`methods`（两种计价方法不同的算术，设计里的替换点）；`layers` 按单位记来源（票据按确认先后占没开票的单位，冲回留空位）；设计改了一处：开票后才到的依据只换没开票的单位（IC14 说的是整层都开票的情形，仍是只记录）；“实现状态”改成表；改坏检查 9/9（`c5-data/mut-p3c-costing/`） |
| P3e | 先进先出出库、在库不够与之后入库补平（IS01、IS02）、采购退货与可退数量（RT01、`LayerService.ReturnLimit`）；AD02 的先进先出分法 | P3c | 集成测试、改坏检查 | ✅ 2026-11-11（组件仓库 `ccf510e`）：问了维护者一个问题——补平的差额记到哪里，维护者定“更正销售成本”（用财务现成的 `cost_of_sales`、`cost_of_sales_return`；财务的目录里没有“存货与差异”这一对）；改坏检查 9/9（`c5-data/mut-p3e-costing/`；“移动平均也限制”第一版改法编译不过，改写后单独重跑杀掉，`result-rerun.txt`） |
| P4 | 种子数据 | P3 | 格里 `make seed-data` 两遍 | ⬜ |
| P5 | 发布与连锁：外壳 `be/go-core` 加成员、套件的格与 L3、一致性考试；`erp/purchase` 退货前问本组件的可退数量（RT01，可选依赖） | P3、P4 | 格从空库到 L3 全过；`make version-check`、`make gates` | ⬜ |

**完成标准**：组件发布、在组件索引里有版本；P0 定为“做”的能力都有测试；不做的写进设计文档的实现状态；格通过；容器关掉。

## P0 的结果（草稿，2026-11-11，AI 定，待复核）

**首批做的**：

| 能力 | 怎样做 |
| --- | --- |
| 计价政策 | 按法人：移动平均（缺省）或先进先出；计价范围等于法人（细分以后） |
| 按计价序号计算 | 订阅库存的流水；按“产品 + 法人”的计价序号顺序处理，乱序的先缓存；缺口超过等待（5 分钟）按序号向库存补取，补齐前不算后续出库；每条流水只计价一次 |
| 成本层与暂估 | 每条入库流水一个成本层；单价来源三级：政策价（待定价，等计价依据 5 分钟后取最近采购价）< 收货计价依据（暂估）< 票据单价确认（最终）；替换规则照协议 05b 的表（首批不含票据单价调整：财务的补差票与折让不在首批） |
| 调整 | 来源替换按差额作为新的成本事实（不改写原事实）；差异的去处按计价方法（先进先出：仍在库的部分进库存；移动平均：按在库比例摊入；其余进销售成本差异）；来源冲回（票据单价冲回、计价依据撤回）撤掉它的贡献 |
| 出库成本 | 移动平均按当前平均；先进先出逐层出库；发布出库的成本事实 |
| 退货 | 采购退货按原入库层的当前单价出库、层数量减少（先进先出下超过在库的拒绝——在出库已经发生时只能告警，见未决问题）；销售退货不在首批（P0b 查过：`erp/sales` 的退货与库存的 `sales_return` 流水都还是“以后”，没有来源），规则键 `cost_of_sales_return` 已在财务的目录里预备 |
| 成本事实 | 按财务的会计事实契约在自己的流 `erp.costing` 上发布 `erp.costing.accounting_fact.v1`：入库暂估（存货借、收货待票贷）、出库（销售成本借、存货贷）、调整（存货或差异、收货待票）；分析维度从流水的来源单据继承（首批只有部门：库存流水没有部门的，留空） |
| 查询 | 成本层、某产品某法人的当前单价与在库价值、成本事实列表 |

**不在首批**（理由与触发）：

| 能力 | 理由 | 触发 |
| --- | --- | --- |
| 标准成本、定期盘存 | 标准成本要维护与价差、定期盘存要盘点倒算；首批两种逐笔方法 | 第一个要它的客户 |
| 关账的封存与解封（代理库存参加关账） | 财务的关账批次不在首批 | 财务做关账批次时 |
| 票据单价调整（折让、补差票） | 财务的供应商贷项与补差票不在首批 | 财务做时 |
| 到岸成本分摊单、生产成本 | 费用票据确认、制造不在当前重建 | 制造或到岸成本 |
| 期初成本层导入 | 协议 16 的迁移 | 客户上线迁移 |
| 成本重算（受控） | 追加调整已覆盖更正；重算要关账配合 | 关账批次之后 |
| 销售退货的成本冲回 | `erp/sales` 的退货单与库存的 `sales_return` 流水都没做（P0b 查过） | 销售做退货、库存加 `sales_return` 流水时：按原出库的成本冲回 |
| 成本子账与总账的对账 | 要财务按科目的余额查询给出存货科目的口径 | P1 定：倾向做一个只读的对账查询 |

**源头要补的（P0b）**：

1. `erp/inventory`：系统面按“产品 + 法人”与计价序号范围读流水（缺口补取，协议 05b“计算与缺口”）；契约加法、实现、集成测试、发布，连锁。**结果**：3.0.39，`StockService.Movements`（契约 alpha.3，只许 `erp/costing`），改坏检查 3/3（`c5-data/mut-p0b-inventory/`）。
2. `erp/finance`：规则目录加成本的规则键（入库暂估、出库成本、调整的几种角色；名字在 P1 定，照协议 05 的会计事实契约，来源不写科目）；种子的映射跟上；发布，连锁。**结果**（3.0.4，名字提前在这里定了，P1 照用）：`inventory_receipt`（`inventory` 借、`grni` 贷）、`cost_of_sales`、`cost_of_sales_return`、`inventory_return`、`cost_adjustment_up`、`cost_adjustment_down`（金额不为负，调整按方向两条；已出库部分的差额记 `variance`）；种子把 `grni` 映射到供应商票据借记的材料采购 1401，入库计价与票据在那里冲平。
3. `erp/inventory` 的销售退货流水（`sales_return`，引用原出库流水）：看 `erp/sales` 的退货现在怎样入库；没有的话首批按“当前平均入库并标记”处理，销售退货流水作为触发条件留到以后。

**要问维护者的**：没有（计价方法、等待期限、规则键都能从边界卡、协议 05b 与已有决定推出；推不出的按 AI 定记在设计的未决问题）。
