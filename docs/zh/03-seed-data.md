[English](../en/03-seed-data.md) · [中文](03-seed-data.md)

# 种子数据

给本地开发和手工测试用的演示数据：假客户、假产品、订单、商机、凭证、模板，加上几个角色和数据范围各不相同的测试账号。一条命令，刚克隆下来的仓库就有东西可点、可查、可测。**它从不进入任何部署**：`make seed-data` 和 `make seed-data-clean` 不出现在任何部署脚本或 CI 流程里，只手工运行。背后的规则见 [01-conventions/05-data.md](01-conventions/05-data.md)。

## 灌了什么

每个组件拥有并灌自己的数据（在自己仓库里 `make seed`）；根目录的 `make seed-data` 只负责按顺序调用它们。

| 组件 | 数据 | 数量 |
|---|---|---|
| infra/iam-casdoor | 四个测试用户，密码都是 `DevSeed123!`：`dev.superuser`（全部权限，无部门）、`dev.sales.east`（华东销售）、`dev.warehouse.south`（华南仓管）、`dev.finance.viewer`（财务只读）；以及只在本地存在的登录应用 `local-dev-seed-app` | 4 个用户，1 个应用 |
| infra/authz | 四个角色（`dev_superuser` 拥有全部权限键；`dev_sales_rep`、`dev_warehouse_manager`、`dev_finance_viewer` 各有一个子集）和一棵部门树（总公司 → 华东、华南），分别授予上面四个用户。它自己去 Casdoor 查用户的 `sub` | 4 个角色，3 个部门 |
| mdm/customer | 覆盖零售、软件、食品、建筑、能源、农业、医疗等行业的客户；`ACTIVE` 和 `DISABLED`；信用额度从 0 到 100 万，含一个刻意压得极低的；部分回填了过去的创建时间。1–5 号被下游引用，只增不改 | 12 |
| mdm/product | 每种 `TrackingType`（`NONE`、`BATCH`、`SERIAL`）都有产品；`ACTIVE` 和 `DISABLED`；单价从几毛到 2200；部分回填了过去的创建时间。1–5 号只增不改 | 12 |
| erp/inventory | 一套自成一体的数据（四个自造 ID 的产品分布在 WH-EAST、WH-SOUTH 两个仓库：入库、出库、盘盈、盘亏、一条未完结预留）；探测到 mdm/product 的种子数据时，给它的每个产品各灌 200 件；只给 `dev.warehouse.south` 授权 WH-SOUTH | 4 条自造 + mdm/product 每个产品一条 |
| erp/sales | `dev.superuser` 建的订单（`CONFIRMED`、`SHIPPED`、`CANCELLED`）和 `dev.sales.east` 建的订单（`DRAFT`、`CONFIRMED`），走它自己的 REST 接口 | 5 |
| crm/opportunity | `seed-opp-1..5` 由 `dev.superuser` 建（三个 `OPEN` 处在不同阶段，一个 `WON`，一个 `LOST`）；`seed-opp-6..10` 用 `dev.sales.east` 的真实 token 建（同样的分布，在最近 2–25 天里逐步推进）；`seed-opp-11` 是给低信用客户的一条 `WON` 商机。每条成功的 `WON` 都让 erp/sales 建出一张归属相应的 `CONFIRMED` 订单；`seed-opp-11` 的订单停在 `DRAFT` | 11 |
| erp/finance | 覆盖应收、应付、存货、收入、成本的人工凭证（单行与多行，其中一张被红字冲销）；三种状态的会计期间（2026-04 结账后锁定、2026-05 结账后反结账、2026-07 只结账）；给 `dev.superuser` 和 `dev.finance.viewer` 的法人访问授权 | 5 张凭证，1 张冲销，3 个期间 |
| infra/print | 两个可渲染的模板：`sales.delivery_note`（PDF，按行循环的表格，模板 ID 与数据形状同前端的打印按钮；两个版本，版本列表与回滚有东西可看）和 `sales.shipping_label`（ZPL，含条码指令）；灌入时各经 gRPC 真实渲染一次 | 2 个模板，3 个版本 |

用这些账号看到的数据范围：`dev.sales.east` 的列表里只有 `seed-opp-6..11` 和本部门的订单；`dev.warehouse.south` 只看得到 WH-SOUTH 的库存。erp/finance 的应收和信用占用不需要灌：库存、销售、商机产生的事件会把它们填满。

每个人类可读的名字都以 `「本地测试」` 开头，在任何地方都能认出种子数据；每个组件的 `seed-clean` 靠这个前缀加它固定的幂等键找到自己的行。

## 没有 seed-clean 或没有 seed 的组件

- **erp/inventory 和 erp/finance 没有 `seed-clean`，只有 `db-reset`。** `inventory_movements` 是只增表；`LOCKED` 的会计期间没有任何 rpc 能转回去。两者逐行删除都复原不了，所以 `make seed-data-clean` 不动它们。要清空：`make -C components/erp/inventory db-reset` 或 `make -C components/erp/finance db-reset`（`migrate down` 再 `up`）。这会清空该组件的**全部**数据，不只是种子灌的那部分。
- **infra/print 没有 `seed-clean`**：管理员改过的模板绝不能被种子覆盖或删掉。重灌时已存在的模板一律跳过，可以放心重复跑。
- **infra/workflow 和 infra/notification 没有 `make seed`。** workflow 的待办命令刻意不对外开放 REST，notification 连一个写 rpc 都没有：记录只来自事件。它们的数据来自一次真实的业务失败：`seed-opp-11` 用一个超出信用额度的客户赢单，erp/sales 拒绝确认订单、在 infra/workflow 建一条异常待办（分派给华东），这条待办又产生一条通知记录。
- **integration/im-dingtalk 没有种子数据**：它连的是真实的钉钉团队和真实的手机；假凭据什么都测不出，真凭据每跑一次都会给人发消息。

## 怎么用

```bash
make seed-data          # 全部灌入；可以重复跑（固定幂等键）
make seed-data-clean    # 撤销能撤销的部分（见上一节）
make -C components/erp/inventory seed   # 单个组件，连同它依赖的组件
```

在前端正常的 Casdoor 登录页用 `dev.superuser` / `DevSeed123!` 登录，或用另外三个用户之一，体验不同的角色和数据范围。

## 测试账号与 ROPC 应用

建商机、订单、凭证需要真实的登录态：负责人和部门取自调用者的 token。所以 infra/iam-casdoor 的 `make seed` 会建一个开了 Resource Owner Password Credentials 授权、**只在本地环境存在**的应用 `local-dev-seed-app`。种子脚本用测试用户的用户名和密码换一个真实 token，再通过真实的 REST 接口建数据，从不直接写库，因此这批数据也顺带把真实鉴权链路走了一遍。

生产应用（`brickkit-app`）从不开 password 授权；种子脚本建的是它自己的应用，从不碰那一个。

## 前提

- 整个项目已经起来（`brickkit up`）；每个种子脚本都会先探测它需要的端口和健康检查，不满足就报错退出，不会只灌一半。
- 宿主机上有 `curl`、`python3`、`docker`。调用 gRPC 的脚本会运行 `fullstorydev/grpcurl` 镜像，不需要本机装 `grpcurl`。
- 表里每一行都能单独跑（`make -C components/<scope>/<name> seed`）；它会先灌这个组件依赖的那些。

## 这不是什么

- **不是测试数据。** 种子数据进的是 `brickkit_db`，运行中的项目用的库。自动化测试用 `brickkit_test_db`（`make test-db-init`）：schema 相同，数据不相通。你在前端点开的东西不会被任何组件的测试碰到；会写共享基准行的测试（仓库余额、法人过账序号）也不会改动演示数据。
- 不是 CI 夹具。它只手工运行。
