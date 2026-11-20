# C11 P5 一致性考试的结果

考生：一个没参与写作的子代理（2026-11-20），只读文件。答卷摘录在 `answer.md`。考试时格 C11-A 第一次（`c11a-1`）正在构建。处理都进 `infra/bff-mobile` 3.0.2（与套件、装配文档），格 C11-A 第二次从空库验证。

## 必须改（6 条，全部处理）

| # | 发现 | 处理 |
| --- | --- | --- |
| M1 | 格的清单路径错（`.secrets/bff/.secrets/bff/`） | 套件 `prepare.py` 传格目录给 `bffqueries.write`；清单写成单行 JSON（核实了 BrickKit 对 `file://` 内容转义 `$` 与换行：`internal/compose/envplace.go` 的 `envFileLine`）；正在跑的 `c11a-1` 在构建时就地改正了文件 |
| M2 | 库存位置只取第一页，静默截断 | 位置照仓库目录按页取、至多 5 页，超过时已取的照常、带 `DEPENDENCY_UNAVAILABLE`（写明 `erp/inventory`）；集成测试：两页都取（替身答两页）、超过 5 页带缺件错误（新步 `bounds`）；BM05 写明 |
| M3 | 被屏蔽的字段成了零值，`masked` 用属主的字段名 | 属主记录的字段在 schema 里全部可为空（各属主把每个字段都声明为可屏蔽，P8.31），映射用指针、`null` 原样；`masked` 换成 GraphQL 字段名（`taxId`、`total`、位置的 `warehouse`）；`StockPosition` 加 `masked`；集成测试：归档订单的 `customer`、`total` 为 null 并列出；BM04 写明。前端还没有，改 schema 不影响使用方（A174，待复核） |
| M4 | 业务拒绝也被加了 `metadata.dependency` | `core.Base.Get` 原样返回 SDK 的错误（P4.19）；集成测试断言属主的 `NOT_FOUND` 不带它；属主自己用协议体答的 503 原样转述，库存“取不到”的用例改成不带协议体的 503（SDK 才会写明属主）；BM06 写明 |
| M5 | 替身的 `NOT_FOUND` 用属主自己的领域 | 替身的平台原因一律 `be`（含 405 与缺省分支），断言与测试索引同改 |
| M6 | OpenAPI 与入口不一致 | 超限条目写成启动时拒绝、请求时答 `PERSISTED_QUERY_NOT_FOUND`；`extensions`、`persistedQuery` 加 `additionalProperties: false`（集成测试：多余成员 400）；加 401；200 的说明写明 `dependency` 的含义与 id 参数的 `REQUEST_INVALID` |

## 建议改

| # | 处理 |
| --- | --- |
| 1 替身不合契约 | 任务 `pending`、产品 `stock`、`names` 是对象、产品不带 `_masked`；屏蔽改由伙伴、商机、归档订单示范 |
| 2 `task(id: "done")`；`customer(id)` 不核对角色 | 按 id 读取先核对参数是 UUID，不是就答 `REQUEST_INVALID`、不问属主（集成测试）；`customer(id)` 读的是伙伴，写进 BM04 |
| 3 `_FILE` 读不了时外壳退出 | 写进 BM02 与 `entry.load` 的注释：这是 SDK 的配置问题，照常不启动 |
| 4 配置键的说明不一 | `names.go` 改成与 BM02 一致 |
| 5 属主的 `title` 进了 `message` | `message` 改为平台原因的目录标题、属主自己的原因就是原因本身；BM09 写明（A175） |
| 6 根字段指标被嵌套失败带偏 | 只算路径长度为 1 的错误；`outcome` 是平台原因或 `owner` |
| 7 慢属主断言过宽 | 收紧为 `DEADLINE_EXCEEDED` |
| 8 缺的测试 | 补：目录超过 5 页、位置翻页与超过 5 页、业务拒绝不带 `dependency`、`extensions` 多余成员、被拒条目的原因逐条核对日志、属主同名原因不重试 |
| 9 L3 没核对“没问属主”；`BE-Request`、`BE-Polling` 没有测试 | 前者在 L2 有（`entry` 步），L3 不再重复；后者挂进交接与 A176：随 C12 在格前面放边缘时测 |
| 10 必需依赖写法不一 | 边界卡改为“身份、授权”，组件索引随之生成 |
| 11 D68 转述不准 | design 改为引用例外条款 |
| 12 AI 选择没进台账 | 登记 A170–A176（公网前缀、只读与首批范围、代价、清单键、屏蔽字段可为空、错误的 message 与 `retry_after`、L3 不经边缘），都待复核 |
| 13 design 引用 `dev/`；实现状态 | 改为“记录在装配项目的开发区”；实现状态写到 3.0.2 |
| 14 测试端口与注册表冲突 | itest 改用 29500、29509 |
| 15 `retryAfter` 不看领域 | 只对平台原因（领域 `be`）；集成测试：属主领域里同名的原因不带 `retry_after` |

改坏检查（3.0.2）：`../mutation/result-3.0.2.txt`。
