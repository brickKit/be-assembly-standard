[English](../../../en/02-decisions/01-architecture/0103-locked-stack-per-language.md) · [中文](0103-locked-stack-per-language.md)

# 0103 每种语言一套锁定的技术栈

## 决策

技术栈按语言逐格锁定，组件不能自选。

| 层 | Go | Python | TypeScript |
|---|---|---|---|
| HTTP | Gin | FastAPI 跑在 uvicorn 上：单进程、单事件循环 | Apollo Server 4（只用于 BFF） |
| gRPC | `grpc-go` | `grpc.aio` | 不提供 |
| 数据库 | `database/sql` + `pgx/v5/stdlib`，`sqlc`，手写 SQL | `asyncpg`，手写 SQL，Pydantic 行映射 | 从不直连数据库 |
| 迁移 | `golang-migrate`，裸 `.sql` 文件 | `yoyo-migrations`，裸 `.sql` 文件 | — |
| 指标 | 每个模块一个 Prometheus registry | 每个模块一个 `CollectorRegistry` | — |
| 测试 | `testing` + `testify` + `rapid` | `pytest` + `pytest-asyncio` + `hypothesis` | `vitest` |

任何地方都不用 ORM。每个后端组件只导出一个模块入口（Go 是 `module.New`，Python 是 `create_module`），单独运行和在外壳里运行走同一个入口；模块从运行时拿到配置、连接池、日志和遥测，从不读取进程环境变量、不初始化进程级状态、不退出进程。

## 理由

外壳在一个进程里运行多个模块。有些格子在那里物理上混不了：WSGI handler 用不上共享的异步连接池，同步 gRPC 无法共享事件循环，两种连接池类型不可能同时递给模块，两个模块都用默认指标 registry 会让第二个模块启动即崩溃。另一些格子能启动，然后悄悄出错：最后一个初始化日志或链路追踪的模块会替所有模块做主。锁定 Gin，是为了让 SDK 的中间件链（追踪、请求 id、错误映射、指标）只写一遍。

## 挡下什么

- Go 组件用 Echo、Fiber、chi 或裸 `http.ServeMux`
- GORM、SQLAlchemy ORM 或任何 ORM；用 `pgxpool.Pool` 作为模块的连接池类型
- Flask 或 Django；同步 `grpc`；gunicorn，或开多个 worker 的 uvicorn
- alembic，或同一种语言里出现第二种迁移工具
- "这个组件换成 X 库会更简单"——按组件选框架
- 在 `main` 里自己开连接池、监听端口、装信号处理器或初始化 OTel

## 何时重新讨论

表中某个库停止维护，或出现任何变通都补不上的能力缺口时。届时在 SDK 中为该语言的所有组件一次性更换这一格——绝不只为某一个组件换。
