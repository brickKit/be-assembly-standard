# mdm-product · 产品/物料主数据 设计计划

| 项 | 值 |
|---|---|
| 组件 ID | `mdm/product` |
| 仓库名 | `mdm-product` |
| 端口 | HTTP `8082` / gRPC `9092`（`registry/ports.tsv`） |
| schema / role | `mdm_product` / `mdm_product_rw`（归档 `mdm_product_archive`，本组件不启用，见 §7） |
| 语言 | Go（设计书 §12.1.2：`mdm-*` 是只读枢纽，面临极高并发读） |
| 框架栈 | Gin + `database/sql` + `pgx/v5/stdlib` + `sqlc` + `golang-migrate`（§12.4 锁定表，逐格抄） |
| 合并部署时进 | 外壳一 `go-core` |
| 装配角色 | `default` |
| 阶段 | 阶段二（验平台，设计书 §9.6 档 1） |

## 1. 边界

**归我：** SKU、产品分类、基础属性、条码、**计量单位与换算因子**、`tracking_type`（是否启用批次/序列号追踪）、`standard_cost`（标准成本）。这些数据的唯一真相源。

**不归我：**

| 什么 | 归谁 | 为什么 |
|---|---|---|
| 产品的**库存数量**、批次号/序列号的**实际值** | `erp-inventory` | 本组件说的是"这个产品**要不要**按批次管"（`tracking_type`），不是"这批货的批次号是多少"。前者是主数据，后者是交易数据 |
| 产品的**售价**、价格表、折扣 | `erp-sales` | 设计书 §5.5：定价模块在 `erp-sales` 内部。本组件的 `standard_cost` 是**成本**不是售价——它给 `erp-finance` 核算用，不是给客户报价用 |
| 实际成本（移动加权 / FIFO 算出来的那个） | `erp-inventory` / `erp-finance` | `standard_cost` 是人工维护的标准值，实际成本是流水算出来的。**两者不是一回事**，混用会让成本差异分析整个失去意义 |
| BOM、工艺路线 | `erp-manufacturing`（阶段六） | 本组件只描述单个产品是什么，不描述产品之间的构成关系 |

**数据权限判定**（§11.2.1 强制在建表前判定）：`assembly.yaml` 写 `data_scopes: none`。理由：设计书 §14.2.2 明确"`mdm` 4 个组件全部 `none`"——产品主数据是全员可见的参照数据（销售要报价、仓库要收发货、财务要核算，看的是同一份产品档案），不存在"只能看自己名下产品"这类行级限制。

⚠️ **因此本组件的迁移不加 `dept_id` / `dept_path` / `owner_id` 三列**（§11.2.1 的"条件强制"）。

## 2. 拥有的数据

| 表 | 分区键 | 粒度 | 说明 |
|---|---|---|---|
| `products` | 不分区 | — | 主数据，量级是"SKU 数量级"（几千到几十万行），不是交易量级 |
| `product_categories` | 不分区 | — | 分类树，用**物化路径**（`path` 列）不用邻接表——理由同 §14.2.3 的 `dept_path`：前缀匹配一次查完子树，不需要递归 CTE |
| `uoms` | 不分区 | — | 计量单位。每个**单位类别**（重量/长度/数量…）内有且只有一个基准单位 |
| `uom_conversions` | 不分区 | — | 换算因子。见下方 §2.1 |

全部符合 §11.2.1（`created_at`/`updated_at`/`version`/`status`）。

**终态列表：** 不适用（同 `mdm-customer`）。`disabled`（停用）不是"业务已完结"——历史订单/库存流水仍引用这条产品记录，不存在可判定"无活跃业务"然后归档的时刻。详见 §7。

### 2.1 UoM 换算的三个决定

参考 Odoo 的 `uom.uom`（§8），但**三处刻意不同**：

| # | 决定 | 为什么 |
|---|---|---|
| 1 | 换算因子用 **`NUMERIC(18,6)`，不用浮点** | Odoo 的 `factor` 是 float。金额已经因为跨语言精度问题一律用 `string` 传 decimal（导读末尾那条），**换算因子是同一类问题**——`1/3` 的箱→个换算在 float 下会漂移，而它会乘进订单金额里 |
| 2 | **只存一个方向的因子**（`factor`：1 个本单位 = 多少个基准单位），不存 `factor_inv` | Odoo 同时存 `factor` 与 `factor_inv` 是缓存优化，代价是两者可能不一致（浮点下必然）。我们现算，一次除法不值得为它引入一个可能说谎的字段 |
| 3 | **跨类别换算直接报错**，不做"智能推断" | 千克换米没有意义。Odoo 也这么做（`category_id` 必须相同），这一条是照抄它的正确判断 |

**舍入策略必须在契约里写死**（不能留给调用方）：`ConvertQuantity` 返回值按**目标单位的 `rounding` 字段**（每个 UoM 自带，如"个"的 rounding=1 表示不能有半个）做**向上取整**（`CEIL`）。

⚠️ **向上取整是刻意的**：出库场景下"需要 2.3 箱"必须取 3 箱（不够会缺货），向下取整会让防超卖失效。**入库场景由调用方自己决定要不要反向处理**——本组件只提供一个语义明确的换算，不猜调用方的意图。这条写进契约注释。

## 3. 契约面

**gRPC（`mdm.product.v1.ProductService`）：**

| rpc | 类型 | 幂等键 | 权限键 | 说明 |
|---|---|---|---|---|
| `Create` | 写 | `idempotency_key` | `mdm.product.create` | SKU 可留空自动生成（同 `mdm-customer` 的 `code`），显式传入则唯一索引去重 |
| `Update` | 写 | `idempotency_key` | `mdm.product.edit` | 乐观锁 `version` |
| `SetStatus` | 写 | `idempotency_key` | `mdm.product.edit` | `ACTIVE` ↔ `DISABLED` 双向，不是终态（同 `mdm-customer`） |
| `Get` | 读 | — | `mdm.product.view` | 按 id 取单条 |
| `List` | 读 | — | `mdm.product.view` | 游标分页（决策 53，无 `offset`）+ 强制时间窗口（§11.4.1） |
| `BatchGet` | 读 | — | `mdm.product.view` | **BFF 与 `erp-sales` 防 N+1 的唯一合法调用方式**（§3.8）。`erp-sales` 建单时一次拿全部行的产品，不许逐行 `Get` |
| `GetSummary` | 读 | — | `mdm.product.view` | 轻量投影（`id`/`sku`/`name`/`base_uom`/`tracking_type`/`status`），给摘要副本同步用 |
| `ConvertQuantity` | 读 | — | `mdm.product.view` | `(product_id, qty, from_uom, to_uom) → qty`。**纯函数，不落库** |

**对外 REST 路径前缀：** `/mdm/product/**`（与 `assembly.yaml` 的 `edge_routes` 一致）

**不暴露到 REST 的接口：** `BatchGet` / `GetSummary`（同 `mdm-customer` 的理由：它们是给其他组件的 gRPC 客户端用的批量读优化，不是终端用户操作）。
**`ConvertQuantity` 暴露到 REST**——前端下单页面要实时显示"3 箱 = 36 个"，而设计书 §8.4 明确要求这类联动走后端 `DryRun` 接口，前端不许自己算。

**无 `GetStatus`：** §4.5 的"薛定谔的超时"查询针对的是**被别人同步写调用**的组件；本组件没有被任何组件同步写（同步图里它只有入边、且都是读），不存在这个问题。

⚠️ **阶段二所有 REST 路由标 `besdk.Public`**——权限判定要到阶段三 `infra-authz` 上线才有真实现（阶段一增补 B）。上表的权限键是**给 `assembly.yaml` 的 `permissions` 段抄的**，阶段三回来把 `Public` 换成它们。

## 4. 事件

**发布：**

| subject | 分级 | 何时发 | payload 要点 |
|---|---|---|---|
| `mdm.product.created.v1` | 核心交易事件 | `Create` 成功提交事务后，经 Outbox 异步发布 | `id`/`sku`/`name`/`base_uom`/`tracking_type`/`standard_cost`/`version` |
| `mdm.product.updated.v1` | 核心交易事件 | `Update` 成功后，或 `SetStatus` 流转到 `ACTIVE` 后 | 同上（全量字段，下游按 `version` 覆盖） |
| `mdm.product.disabled.v1` | 核心交易事件 | `SetStatus` 流转到 `DISABLED` 后 | `id`/`version` |

⚠️ **`tracking_type` 必须进 payload**：`erp-inventory` 靠它维护"这个产品要不要收批次号"的摘要副本，而那是本阶段唯一一处跨组件语义耦合（见 `erp-inventory` 设计计划 §5）。

**消费：** 无。`mdm` 是只读枢纽，消费一条就是在给枢纽加一条依赖边。

## 5. 依赖

**强依赖：** 无。
**弱依赖：** 无。

**明确不依赖：**

| 谁 | 为什么不建依赖边 |
|---|---|
| 任何业务组件 | `mdm` 是被所有人读、自己不调任何人的只读枢纽（§2.6）。这不是"暂时没有依赖"，是这个组件存在的设计前提 |
| `erp-inventory` | 反直觉但重要：本组件**不查库存**。"这个产品还有多少货"是库存的事，产品档案页要显示库存量走**展示上推**（§4.7）——由 BFF/前端分别调两个域再聚合，不在后端建边 |
| `infra-iam-casdoor` | JWT 本地验签（决策 87），只需 `iamJwksUrl` 拉公钥 |

## 6. 在同步图与三枢纽里的位置

本组件是设计书 §2.6 三枢纽之一——**只读枢纽**（与 `mdm-customer` 同族）。§4.2 同步图里指向它的有 `crm-opportunity`、`erp-sales`、`erp-purchase`、`erp-manufacturing`，**它不指向任何人**。在 DAG 里是叶子节点（只有入边没有出边），天然不可能引入环。

不违反"CRM 与 ERP 零同步边"（§1.4）——本组件是 `mdm` 域，被两边共同读取正是它作为主数据枢纽的职责。

## 7. 分区与归档策略

四张表全部长期"热"，不分区、不归档：

| 数据 | 热 | 归档条件 | 归档去哪 |
|---|---|---|---|
| `products` / `product_categories` / `uoms` / `uom_conversions` | 永久 | 不适用 | 不归档 |

理由与 `mdm-customer` 完全相同：主数据不是交易流水，量级不随时间无限增长（§11.2.5 的分区大表清单里没有 `mdm-*`）。`mdm_product_archive` schema 由建库脚本一视同仁建出来但业务代码不写它。

⚠️ **停用的产品不能删也不能归档**：三年前的订单行、五年前的库存流水都还引用着它的 `product_id`，`batchGet` 查不到就会让历史单据显示成空白。

## 8. 参考实现

| 项目 | 版本/commit | 看的模块 | 借鉴了什么 | 许可证（已复核） | 用法 |
|---|---|---|---|---|---|
| Odoo | 17.0 | `addons/product/models/product_uom.py`（`uom.uom`） | 单位**类别内**换算 + 基准单位 factor=1 的模型；跨类别直接拒绝这个正确判断 | LGPL-3 | 借鉴逻辑 |
| Odoo | 17.0 | `addons/stock/models/stock_lot.py` + `product.tracking` 枚举 | `tracking` ∈ `none`/`lot`/`serial` **挂在产品上而不是挂在批次上**——追踪策略是产品的属性，这个位置是对的 | LGPL-3 | 借鉴逻辑 |
| Apache OFBiz | 18.12 | `applications/product/entitydef/entitymodel.xml` | `Product` / `ProductCategory` / `UomConversion` 实体关系的完整度，用来核对我们有没有漏掉必需字段 | Apache-2.0 | 借鉴逻辑 |

**明确没有参考的：** ERPNext 的 Item——它把 UoM 换算表（`UOM Conversion Detail`）做成 Item 的子表，即"每个产品自带一份换算表"。那与 Odoo 的"全局单位类别"是两种模型，我们选了 Odoo 那种（换算是单位的属性，不是产品的属性），所以没有细读它。

**要避免它的什么：**

| 项目 | 它的做法 | 我们为什么不这么做 |
|---|---|---|
| Odoo `uom.uom` | `factor` 与 `factor_inv` 两个 float 字段同时存 | 浮点 + 冗余 = 两个字段迟早不一致，而不一致会乘进订单金额。改成单向 `NUMERIC(18,6)` 现算（§2.1） |
| Odoo `stock.lot` | "序列号数量必然为 1"**只在业务逻辑里管，数据库没有任何约束** | 我们在 `erp-inventory` 侧用 CHECK 约束兜住（见那份设计计划）。这一条不是本组件的活，但发现于此，记在这里 |

**读完之后，这里有没有「多种实现都合理、只是适配客户不同」的分歧？**

**有一条，但判定为「不是族」：** ERPNext 的换算表挂产品、Odoo 的换算表挂单位类别。看起来是分歧，实际上是**同一个需求的两种建模**，而 Odoo 那种明显更好（避免同一组换算在 N 个产品上重复 N 遍，且改一次改全部）。按 R-4 的判据——"读下来发现其中一种明显更好 → 那就是我们的默认实现，不需要族"。

## 9. 待决问题

| # | 问题 | 什么时候能有答案 | 答案 |
|---|---|---|---|
| 1 | `standard_cost` 由谁维护、多久更新一次？本组件只存值不管更新逻辑，那"标准成本变更"要不要发专门事件？ | `erp-finance` 的成本核算做到差异分析时（阶段五或六） | 阶段二先复用 `mdm.product.updated.v1`（payload 里带 `standard_cost`），**不发明新 subject**——事件只增不删不改（决策 19），发明容易撤销难。等真有下游需要"只关心成本变更"再单独加 |
| 2 | 产品属性（颜色/尺寸这类）要不要做成动态字段？ | 阶段六铺货、或第一个客户提出变体需求时 | 阶段二**不做**。动态字段是所有开源 ERP 的通病之一（总纲 SOP-R 的"要避免的通病"表：元数据驱动一切让强类型缺失，AI 与 IDE 都推不出来）。真需要变体时正确形态是 `customer_fork` 或新槽位族，不是往标准件里塞 EAV |
| 3 | `ConvertQuantity` 的向上取整是否对所有场景都对？ | `erp-inventory` 与 `erp-sales` 真正用起来之后（阶段二内） | 现在按"出库安全"定为 `CEIL`（§2.1）。**阶段二内如果发现入库场景被它坑到，回来把它改成显式参数**——但默认值必须仍是 `CEIL`，因为默认值出错的方向应该是"多备货"而不是"少发货" |
| 4 | `uoms`/`product_categories` 由谁建？契约（§3）只留了 `Product` 的 CRUD，没留 UoM/分类的管理接口——Task 6 写迁移时才发现漏了，`Create` 却要求一个已存在的 `base_uom_id` | Task 6 实现时（当场决定，不阻塞） | **迁移播种，不开接口**：`003_seed_uoms.up.sql` 播种最小可用集（`EA`/`BOX`/`KG`/`G` 四个单位 + 两条换算）。理由：这是准静态参考数据，客户很少需要新增计量单位**类别**（换算因子这种具体数值差异走 Fork，决策 25），为它单开一整套鉴权+校验的 CRUD 接口成本大于收益。真出现"客户频繁要求新增单位类别"的信号，按 R-4 重新评估 |
