# 本地开发种子数据

> ⚠️ **只给本地开发/测试用，不用于生产部署。** 这里灌的是假数据（假客户、假产品、假商机、一个万能测试账号），目的是让刚打开这个仓库的人不用从零建数据，`make seed-data` 一条命令就能有东西可点、可查、可测。真正部署给客户时，这些数据一条都不会跟着走——`make seed-data`/`seed-data-clean` 从不出现在任何部署脚本或 CI 流程里，纯手动触发。

## 灌了什么

⚠️ **架构已经变了（总纲 SOP-W-7）**：所有数据都不再由这里直接建，改成本脚本调用各组件自己的 `make seed`——每个组件自己拥有种子数据，单独 `make -C components/<组件> seed` 也能独立跑出一整套数据，不依赖这个装配层脚本。这里现在只剩一件事：编排顺序（先建身份、再建授权、再建客户产品、再建库存、最后建商机——后面几步要用前面产出的 id/sub 才能完整）。新组件如果也想要"开箱即用的示例数据"，应该照下表已落地的样板给自己加 `make seed`/`seed-clean`（或 `db-reset`，见下），而不是在这个脚本里加一段。

| 组件 | 数据 | 数量 | 谁负责 |
|---|---|---|---|
| `infra-iam-casdoor` | 一个万能测试用户 `dev.superuser`（密码 `DevSeed123!`）+ 一个开着 ROPC 授权的测试应用 `local-dev-seed-app` | 1 个用户 + 1 个应用 | `infra-iam-casdoor` 自己的 `make seed` |
| `infra-authz` | 一个持有 `registry/permissions.tsv` 里**全部**权限键的角色，授予 `dev.superuser` | 1 个角色 | `infra-authz` 自己的 `make seed`（独立向 Casdoor 查 `dev.superuser` 的 sub，不吃 `infra-iam-casdoor` 传参，两边各自 `make seed` 都能单独跑通——身份类种子数据链式调用这条此前未验证的判据，已真机验证） |
| `mdm-customer` | 示例客户（制造业/贸易/物流几个行业），覆盖 `ACTIVE`/`DISABLED` 两种状态 + 一条带联系人的样例 | 5 个 | `mdm-customer` 自己的 `make seed` |
| `mdm-product` | 示例产品，覆盖三种 `TrackingType`（`NONE`/`BATCH`/`SERIAL`）+ `ACTIVE`/`DISABLED` 两种状态 | 5 个 | `mdm-product` 自己的 `make seed` |
| `erp-inventory` | ① 自成一体的演示数据：4 个自造 id 的假产品分布在 WH-EAST/WH-SOUTH 两仓库，覆盖入库/出库/盘盈/盘亏/一条在途预留；② 探测到 `mdm-product` 的种子数据后，顺手再给 4 个真实 `ACTIVE` 示例产品各灌 200 件库存（`DISABLED` 样例不进货） | 4 条自造 + 4 条真实 | `erp-inventory` 自己的 `make seed`（`product_id` 对本组件是不透明外键，`dependencies.components` 为空，②那一步是探测式关联，不是正式依赖——找不到 `mdm-product` 的种子数据就跳过，不影响①） |
| `crm-opportunity` | 示例商机：3 个 `OPEN`（分处不同阶段）、1 个 `WON`、1 个 `LOST`——真的走 `POST /crm/opportunity/opportunities` 等真实 REST 接口建的，不是直接写库（`CreateOpportunity` 会拒绝非 `ACTIVE` 的客户/产品，所以只用 4 个 `ACTIVE` 样例，`DISABLED` 那个不参与） | 5 个 | `crm-opportunity` 自己的 `make seed`（`component.yaml` 声明的强依赖，Makefile 链式调用 `mdm-customer`/`mdm-product` 与身份类例外 `infra-iam-casdoor`/`infra-authz` 各自的 `make seed`，单独跑就能拿到完整数据——只是单独跑的话，WON 商机触发的自动建单会因为 `erp-inventory` 没有库存走 TCC 补偿建异常待办，这是设计上正确的行为；完整"库存先备好、订单真正 CONFIRMED"的演示效果需要按本脚本的编排顺序） |

**下一步（未做，留给用户决定节奏）**：`erp-inventory` 已经有自己的 `make seed`（多仓库、四种流水原因 + 一条在途预留），`erp-finance`/`infra-workflow`/`infra-notification` 依然几乎没有专属演示数据——如果要照 `erp-inventory`/`crm-opportunity` 这个样板给它们也补上，可以参考 `components/erp/inventory/scripts/seed.sh` 的写法。

⚠️ **`erp-inventory` 没有 `seed-clean`，只有 `db-reset`**：`inventory_movements` 表本身"只增不改"（该组件 `AGENTS.md` 既有判据），逐行 `DELETE` 既做不到干净复原（`BIGSERIAL` 序列不会因为 `DELETE` 回退）又违背这条设计原则，所以 `make seed-data-clean` 不会清理 `erp-inventory` 的数据——想清空它用 `make -C components/erp/inventory db-reset`（`migrate down` 再 `up`，真正的重置，但会清空该组件**全部**数据，不止 seed 灌的那部分），见总纲 SOP-W-7"delete 不是 reset"判据。

所有人类可读的名字字段都带 `「本地测试」` 前缀，方便在任何界面/查询结果里一眼认出——`clean.sh` 也是靠这个前缀 + 固定的 `idempotency_key`/用户名找到自己灌的数据，不会误删真实数据。

## 怎么用

```bash
make seed-data          # 灌数据，可以重复跑（幂等——命令内部全部走固定 idempotency_key/ON CONFLICT）
make seed-data-clean    # 清空这批数据
```

登录方式：走前端/`frontend-standard` 正常的 Casdoor 登录页，用户名 `dev.superuser`、密码 `DevSeed123!`。

## 为什么要建一个 ROPC 测试应用

`crm-opportunity` 的建档/赢单接口需要真实登录态（`besdk.ScopeOf(ctx)` 取 `owner_id`/`dept_path`），`infra-iam-casdoor` 自己的 `scripts/seed.sh` 为此会在 Casdoor 里建一个**只在本地环境存在**的 OIDC 应用 `local-dev-seed-app`（开了 Resource Owner Password Credentials 授权类型）；`crm-opportunity` 自己的 `scripts/seed.sh` 用 `dev.superuser` 的用户名密码换一个真实 JWT，再拿这个 JWT 走真实 REST 接口建商机——不是直接写库，这批商机数据因此也顺带验证了一遍真实鉴权链路。

⚠️ **`local-dev-seed-app` 只应该存在于本地/测试环境**——生产环境的 OIDC 应用（`brickkit-app`）不许开 `password` 授权类型（见 `infra-iam-casdoor` 的 `docs/手册.md` §6），`seed.sh` 建的是一个独立的、专门给这个脚本自己用的应用，不会碰 `brickkit-app`。

## 依赖

`seed.sh`/`clean.sh` 假设 `brickkit up` 已经把 14 个组件全部起来（脚本会在关键步骤前探测端口/健康检查，起不来就直接报错退出，不会留一半数据）。需要 `curl`、`python3`、`docker`（`clean.sh` 的 `docker exec` 打 `be-postgres`；委托给的各组件自己的 `make seed` 内部会再拉 `fullstorydev/grpcurl` 镜像，不需要本机装 `grpcurl` 二进制）。`erp-inventory`/`crm-opportunity` 自己的 `make seed` 也都可以单独跑（`make -C components/erp/inventory seed`、`make -C components/crm/opportunity seed`），各自会自动链式调用它们需要的组件（身份类 + 强依赖）各自的 `make seed`，不需要这个装配层脚本。

## 这不是什么

- **不是测试数据**——这里灌的是给人"打开项目就能体验"的演示数据，进的是 `brickkit_db`。测试用的是另一个物理分开的库 `brickkit_test_db`（`make test-db-init` 建/刷新，见根 `AGENTS.md`"测试库与演示库分开"）——两者结构镜像同一套 schema，但数据互不相通：你在前端点开的、这套种子数据建出来的客户/商机，不会被任何组件的 `go test`/`pytest` 碰到；反过来 `erp-inventory`/`erp-finance` 这类会真实写共享引用行（仓库余额、法人过账序号）的测试，也不会污染这里的演示数据。不是 H2 那种进程内数据库替身——两个库都是真实 Postgres，`be-sdk-go`/`be-sdk-python`/`be-sdk-ts` 的测试全部对着真实 Postgres/NATS 跑，见根 `AGENTS.md` 的"real verification only"纪律。
- 不是 CI 用的 fixture（CI 目前不存在；未来如果要建 CI，`seed-data` 这套东西可以直接复用，但现在纯粹是人手工跑）。
