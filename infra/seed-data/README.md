# 本地开发种子数据

> ⚠️ **只给本地开发/测试用，不用于生产部署。** 这里灌的是假数据（假客户、假产品、假商机、一个万能测试账号），目的是让刚打开这个仓库的人不用从零建数据，`make seed-data` 一条命令就能有东西可点、可查、可测。真正部署给客户时，这些数据一条都不会跟着走——`make seed-data`/`seed-data-clean` 从不出现在任何部署脚本或 CI 流程里，纯手动触发。

## 灌了什么

⚠️ **架构已经变了（总纲 SOP-W-7）**：客户/产品/身份/授权数据不再由这里直接建，改成本脚本调用各组件自己的 `make seed`——每个组件自己拥有种子数据，单独 `make -C components/<组件> seed` 也能独立跑出一整套数据，不依赖这个装配层脚本。这里只负责编排顺序（先建身份、再建授权、再建客户产品、再建库存和商机——后面几步要用前面产出的 id/sub）+ 补上"天然跨组件"的那部分（跨组件库存写入、真实走 REST 建商机）。新组件如果也想要"开箱即用的示例数据"，应该照下表已落地的样板给自己加 `make seed`/`seed-clean`，而不是在这个脚本里加一段。

| 组件 | 数据 | 数量 | 谁负责 |
|---|---|---|---|
| `infra-iam-casdoor` | 一个万能测试用户 `dev.superuser`（密码 `DevSeed123!`）+ 一个开着 ROPC 授权的测试应用 `local-dev-seed-app` | 1 个用户 + 1 个应用 | `infra-iam-casdoor` 自己的 `make seed` |
| `infra-authz` | 一个持有 `registry/permissions.tsv` 里**全部**权限键的角色，授予 `dev.superuser` | 1 个角色 | `infra-authz` 自己的 `make seed`（独立向 Casdoor 查 `dev.superuser` 的 sub，不吃 `infra-iam-casdoor` 传参，两边各自 `make seed` 都能单独跑通——身份类种子数据链式调用这条此前未验证的判据，已真机验证） |
| `mdm-customer` | 示例客户（制造业/贸易/物流几个行业），覆盖 `ACTIVE`/`DISABLED` 两种状态 + 一条带联系人的样例 | 5 个 | `mdm-customer` 自己的 `make seed` |
| `mdm-product` | 示例产品，覆盖三种 `TrackingType`（`NONE`/`BATCH`/`SERIAL`）+ `ACTIVE`/`DISABLED` 两种状态 | 5 个 | `mdm-product` 自己的 `make seed` |
| `erp-inventory` | 给 4 个 `ACTIVE` 示例产品在默认仓库（`warehouse_id=1`）灌 200 件库存（`DISABLED` 样例不进货） | 4 条余额 | 本脚本（直接写库，还没有自己的 `make seed`，见下方"下一步"） |
| `crm-opportunity` | 示例商机：3 个 `OPEN`（分处不同阶段）、1 个 `WON`、1 个 `LOST`——真的走 `POST /crm/opportunity/opportunities` 等真实 REST 接口建的，不是直接写库（`CreateOpportunity` 会拒绝非 `ACTIVE` 的客户/产品，所以只用 4 个 `ACTIVE` 样例，`DISABLED` 那个不参与） | 5 个 | 本脚本（真实 REST 调用，还没有自己的 `make seed`，见下方"下一步"） |

**下一步（未做，留给用户决定节奏）**：`erp-inventory`/`crm-opportunity` 还没有自己的 `make seed`，这两块数据仍在这个装配层脚本里。数据本身也偏单薄——单一仓库、单一法人、库存只进不出，`erp-finance`/`infra-workflow`/`infra-notification` 几乎没有专属演示数据——铺开这两个组件自己的种子数据时可以一并把数据做得更丰富。

所有人类可读的名字字段都带 `「本地测试」` 前缀，方便在任何界面/查询结果里一眼认出——`clean.sh` 也是靠这个前缀 + 固定的 `idempotency_key`/用户名找到自己灌的数据，不会误删真实数据。

## 怎么用

```bash
make seed-data          # 灌数据，可以重复跑（幂等——命令内部全部走固定 idempotency_key/ON CONFLICT）
make seed-data-clean    # 清空这批数据
```

登录方式：走前端/`frontend-standard` 正常的 Casdoor 登录页，用户名 `dev.superuser`、密码 `DevSeed123!`。

## 这一步做了什么，为什么要手工建一个 ROPC 测试应用

`crm-opportunity` 的建档/赢单接口需要真实登录态（`besdk.ScopeOf(ctx)` 取 `owner_id`/`dept_path`），`seed.sh` 为此会在 Casdoor 里建一个**只在本地环境存在**的 OIDC 应用 `local-dev-seed-app`（开了 Resource Owner Password Credentials 授权类型），用 `dev.superuser` 的用户名密码换一个真实 JWT，再拿这个 JWT 走真实 REST 接口建商机——不是直接写库，这批商机数据因此也顺带验证了一遍真实鉴权链路。

⚠️ **`local-dev-seed-app` 只应该存在于本地/测试环境**——生产环境的 OIDC 应用（`brickkit-app`）不许开 `password` 授权类型（见 `infra-iam-casdoor` 的 `docs/手册.md` §6），`seed.sh` 建的是一个独立的、专门给这个脚本自己用的应用，不会碰 `brickkit-app`。

## 依赖

`seed.sh`/`clean.sh` 假设 `brickkit up` 已经把 14 个组件全部起来（脚本会在关键步骤前探测端口/健康检查，起不来就直接报错退出，不会留一半数据）。需要 `curl`、`python3`、`docker`（`docker exec` 打 `be-postgres`；委托给的 `mdm-customer`/`mdm-product` 各自的 `make seed` 内部会再拉 `fullstorydev/grpcurl` 镜像，不需要本机装 `grpcurl` 二进制）。

## 这不是什么

- **不是测试数据**——这里灌的是给人"打开项目就能体验"的演示数据，进的是 `brickkit_db`。测试用的是另一个物理分开的库 `brickkit_test_db`（`make test-db-init` 建/刷新，见根 `AGENTS.md`"测试库与演示库分开"）——两者结构镜像同一套 schema，但数据互不相通：你在前端点开的、这套种子数据建出来的客户/商机，不会被任何组件的 `go test`/`pytest` 碰到；反过来 `erp-inventory`/`erp-finance` 这类会真实写共享引用行（仓库余额、法人过账序号）的测试，也不会污染这里的演示数据。不是 H2 那种进程内数据库替身——两个库都是真实 Postgres，`be-sdk-go`/`be-sdk-python`/`be-sdk-ts` 的测试全部对着真实 Postgres/NATS 跑，见根 `AGENTS.md` 的"real verification only"纪律。
- 不是 CI 用的 fixture（CI 目前不存在；未来如果要建 CI，`seed-data` 这套东西可以直接复用，但现在纯粹是人手工跑）。
