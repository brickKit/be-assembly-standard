[English](../../../en/02-decisions/01-architecture/0103-locked-stack-per-language.md) · [中文](0103-locked-stack-per-language.md)

# 0103 每种语言内部一套锁定的技术栈

**状态**：为 3.0.0 修订（补上 TypeScript 一列、新语言的准入规则）；已决定，随 3.0.0 统一升级落地。

## 决策

在每一门语言内部，技术栈逐格锁定；该语言的组件不能自选。这套栈就是官方 SDK 自己的栈：组件基于那个 SDK 构建，就得到了它。

| 层 | Go | Python | TypeScript |
|---|---|---|---|
| 运行时 | Go 1.25 | CPython 3.13 | Node 24 LTS |
| HTTP | Gin | FastAPI 跑在 uvicorn 上：单进程、单事件循环 | Fastify 5；BFF 的 GraphQL 用 graphql-yoga 5，挂在 Fastify 上 |
| gRPC | `grpc-go` | `grpc.aio` | `@grpc/grpc-js` + ts-proto（`outputServices=grpc-js`） |
| 数据库 | `database/sql` + `pgx/v5/stdlib`，`sqlc`，手写 SQL | `asyncpg`，手写 SQL，Pydantic 行映射 | `pg`（node-postgres）8，手写 SQL，zod 校验行 |
| 迁移 | `golang-migrate`，裸 `.sql` 文件 | `yoyo-migrations`，裸 `.sql` 文件，入口收进 SDK | `node-pg-migrate`，纯 SQL 文件 |
| 事件 | `nats.go` `jetstream` | `nats-py` JetStream | `@nats-io/jetstream` + `@nats-io/transport-node` |
| 十进制 | `cockroachdb/apd/v3` | `decimal` | `decimal.js` |
| JSON Schema（载荷校验） | `santhosh-tekuri/jsonschema/v6` | `jsonschema==4.26.0` | `ajv` 8.20.0 |
| JWT | `golang-jwt/v5` + `keyfunc/v3` | PyJWT，一律传 `audience` | `jose` 6 |
| 出站 HTTP | `net/http` | `httpx` | `undici`，每个依赖一个 Agent |
| 日志 / 指标 | `slog` / `client_golang`，每个模块一个 registry | `logging` 配 SDK 的 JSON formatter / `prometheus-client`，每个模块一个 `CollectorRegistry`，OpenTelemetry 指标经 `opentelemetry-exporter-prometheus==0.59b0` 导出 | `pino` / Prometheus 客户端，每个模块一个 registry |
| 链路追踪 | `otel-go` + `otelgrpc` | `opentelemetry-python` + gRPC 拦截器 | `@opentelemetry/sdk-trace-base`，不用自动插桩 |
| 对象存储 | `aws-sdk-go-v2` | `aioboto3` | `@aws-sdk/client-s3` |
| UUIDv7 / 拼音 | `google/uuid` / `go-pinyin` | `uuid6` / `pypinyin` | `uuid` 11 / `pinyin-pro` |
| 测试 | `testing` + `testify` + `rapid` | `pytest` + `pytest-asyncio` + `hypothesis` | `vitest` + `fast-check` |
| 包管理 | Go modules | `pyproject`，精确版本 | npm + `package-lock.json` |

任何地方都不用 ORM。每个后端组件只导出一个入口：它的 `Spec`，由 SDK 的 `Main` 运行（Go 是 `besdk.Main`，Python 是 `besdk.main`，TypeScript 是 `main`），单独运行和在外壳里运行走同一个入口；模块从运行时拿到配置、库句柄、日志和遥测，从不读取进程环境变量、不初始化进程级状态、不退出进程。

**新语言。** 一门语言只有一个组件时，由那个组件自己选栈，写进它 `AGENTS.md` 的 "Stack" 一节（[0105](0105-any-language-one-protocol.md)）。同一门语言要加第二个组件之前，先在本表给它加一列，并由项目决定要不要为它做官方 SDK。

## 理由

外壳在一个进程里运行多个模块。有些格子在那里物理上混不了：WSGI handler 用不上共享的异步连接池，同步 gRPC 无法共享事件循环，两种连接池类型不可能同时递给模块，两个模块都用默认指标 registry 会让第二个模块启动即崩溃。另一些格子能启动，然后悄悄出错：最后一个初始化日志或链路追踪的模块会替所有模块做主。锁定 HTTP 框架，SDK 的中间件链（追踪、请求 id、截止时间、错误映射、指标）在每门语言里只写一遍。TypeScript 如今是完整的后端语言：Fastify 的钩子正好放得下这条链，并且每个成员一个独立实例；node-postgres 能在每个事务里 `SET LOCAL ROLE` 和 `search_path`，查询构造器和 ORM 做不到；grpc-js 是仍在维护、支持重试策略、重试节流和连接寿命轮换的 JavaScript gRPC。第二个组件之前不锁栈，同一门语言里就会有两套写法，这门语言的组件也永远进不了同一个外壳。

## 挡下什么

- Go 组件用 Echo、Fiber、chi 或裸 `http.ServeMux`
- GORM、SQLAlchemy ORM、Prisma、Drizzle、Kysely 或任何 ORM、查询构造器；用 `pgxpool.Pool` 作为模块的连接池类型；带语句缓存的 `porsager/postgres`
- Flask 或 Django；同步 `grpc`；gunicorn，或开多个 worker 的 uvicorn
- Express、Hono 或 NestJS；Apollo Server；gRPC 用 `connect-node`；Node 上的 OpenTelemetry 自动插桩
- alembic，或同一种语言里出现第二种迁移工具
- "这个组件换成 X 库会更简单"：按组件选框架
- 在本表还没有一列的语言里加第二个组件
- 在 `main` 里自己开连接池、监听端口、装信号处理器或初始化 OTel

## 何时重新讨论

表中某个库停止维护，或出现任何变通都补不上的能力缺口时。届时在 SDK 中为该语言的所有组件一次性更换这一格，绝不只为某一个组件换。

完整分析：[02-languages-and-component-protocol.md，选择](../../04-foundations/02-languages-and-component-protocol.md#选择)；外壳的约束见 [27-shells.md，选择](../../04-foundations/27-shells.md#选择)。
