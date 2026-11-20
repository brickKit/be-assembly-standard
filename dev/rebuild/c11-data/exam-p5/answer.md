# C11 P5 一致性考试的答卷（摘录）

考生：一个没参与写作的子代理（2026-11-20，只读文件，约 70 个文件、74 次工具调用、9 分钟），对照 bff-mobile 3.0.1 的设计、契约、代码与测试，边界卡、协议 20、D68、A108、线协议 P3.3、P4.19、P8.31、P11.x，SDK 的出站调用与配置，七个属主的契约，外壳、套件与格 C11-A。考试时格 C11-A 第一次（`c11a-1`）正在构建。处理见 `result.md`。

## 必须改

- **M1** 格的持久化查询清单路径错：`prepare.py` 传 `c.dir/.secrets/bff`，`bffqueries.write` 又在下面建 `.secrets/bff`，文件落在 `.secrets/bff/.secrets/bff/`，config 指向的 `.secrets/bff/persisted-queries.json` 不存在。
- **M2** 可用量只取位置的第一页（`limit=200`，不读 `next_cursor`），超过 200 个仓库静默截断，没有缺件错误；L3 直接查属主也只取一页，比对抓不住。
- **M3** 屏蔽字段：属主屏蔽的非空字段映射成 `""` 或零值对象（`CustomerRef{"" ""}`），schema 说“null 表示无权看”；`masked` 透传属主的蛇形名（`tax_id`、`totals`），与 GraphQL 字段名（`taxId`、`total`）对不上。销售归档订单的读取会走 `Mask`。
- **M4** `core.Base.Get` 给任何失败都加 `metadata.dependency`，包括属主的 `NOT_FOUND` 等业务拒绝；P3.3、P4.19 要求业务错误原样，`dependency` 只在不可用、超时、没发出的几类上（SDK 已填）。“没有”与“暂时取不到”分不开。
- **M5** 替身答 `NOT_FOUND` 用属主自己的领域，真实属主用 `errs.New`，领域是 `be`；测试与索引守着一个不存在的形状。
- **M6** OpenAPI 与入口不一致：深度、代价、别名超限写成 `REQUEST_INVALID`（实际启动时拒绝、请求时答 `PERSISTED_QUERY_NOT_FOUND`）；`extensions`、`persistedQuery` 没写 `additionalProperties: false` 而代码拒绝多余成员；没有 401。

## 建议改

1. 替身不全合属主契约：任务 `state: open`、产品 `kind: goods`、产品 `names: null`、产品带 `_masked`。
2. `task(id: "done")` 命中 workflow 的 `/tasks/done`，解出全零值的任务；`customer(id)` 不核对客户角色。
3. `BFF_PERSISTED_QUERIES_FILE` 读不了时 SDK 记为配置问题、整个外壳退出，与注释“拒绝一切查询、照常启动”不符。
4. 配置键的说明前后不一（`names.go` 说经 `_FILE`，BM02 说 BrickKit 给内容）。
5. 属主的 `title` 进了 GraphQL 的 `message`，BM09 没写。
6. 根字段指标按路径第一段匹配，嵌套的 `stock` 失败把 `product` 记成失败；`outcome` 取值不受控。
7. 慢属主的断言接受两个原因，设计写 `DEADLINE_EXCEEDED`。
8. 缺测试：目录超过 5 页、位置翻页、业务拒绝不带 `dependency`、`extensions` 多余成员、itest 不核对被拒条目的原因。
9. L3 的入口测试没核对“没问属主”；`BE-Request`、`BE-Polling` 在边缘接上之前没有测试，交接要挂上。
10. 必需依赖的写法在边界卡、组件索引、BRICKKIT 三处不一。
11. design 对 D68 的转述（“不持用户凭据代为写”）不准，应引用例外条款。
12. “AI 定，待复核”的几项没进 AI 选择台账（止于 A169）。
13. design 引用了装配项目 `dev/` 的路径；实现状态没提 3.0.1。
14. itest 端口 28500 与注册表的 `exposePort=28500` 冲突。
15. `retryAfter` 只看原因、不看领域：属主领域里同名的原因会被误加 `retry_after`。

## 没能核实的

- BrickKit 把 `file://` 的内容写进 `env_file` 时 `$` 是否转义、多行能否原样送达（主会话核实：BrickKit `internal/compose/envplace.go` 的 `envFileLine` 对字面量与文件内容转义 `$`、换行，注释写实测于 Compose v5.3.1；清单仍改为单行）。
- gqlgen 的 `stock` 是否在根字段中间件返回前完成；SDK 的 GET 重试是否影响慢属主一步的耗时；用户面替用户读是否该另加服务身份（SDK 全局）；准入是否已先判断操作。
