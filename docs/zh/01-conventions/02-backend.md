[English](../../en/01-conventions/02-backend.md) · [中文](02-backend.md)

# 后端约定

本项目里 Go 和 Python 组件（以及注明之处的 TypeScript BFF）怎么写。配置键和值见 [04-configuration.md](04-configuration.md)；端口和 schema 见 [07-registries.md](07-registries.md)；这些选择背后的理由见 [../02-decisions/README.md](../02-decisions/README.md)。

## 两条原则

1. **每个组件都是完整的 brickKit 组件，能独立运行。** 对其他组件的每一次调用都走真实的 gRPC 或 HTTP，`extraPorts` 里的每个端口都真的在监听，`brickkit up --focus <id>` 只带上它依赖的东西就能把它拉起来。
2. **合并只发生在部署层。** 外壳把 N 个进程变成 1 个，除此之外什么都不做：没有业务逻辑，不共享表，不共享 schema，不合并 API 端口，不让组件互相 import。

"反正最后都在同一个外壳里，直接调函数好了"违反第一条原则；外壳里的边界一旦消失，这个组件就再也不能单独部署了。

## 技术栈

技术栈是定死的，不按组件挑。

| | Go | Python |
|---|---|---|
| HTTP | Gin，经由 `besdk.NewGinEngine(rt)` | FastAPI，经由 `besdk.new_fastapi_app(rt)`；编程式启动一个 uvicorn `Server`，单进程、单事件循环 |
| SQL | `database/sql` + `pgx/v5/stdlib` + `sqlc` | `asyncpg` + 手写 SQL |
| gRPC | `grpc-go` | `grpc.aio` |
| 迁移 | `golang-migrate`，纯 `.sql` | `yoyo-migrations`，纯 `.sql` |

绝不使用：Echo、Fiber、chi 或裸 `ServeMux`；GORM；`lib/pq`；Flask 或 Django；同步 `grpc`；SQLAlchemy；alembic；gunicorn 或多个 worker。同一种语言内迁移工具统一，这种语言的每个组件镜像里都是同一个迁移入口，Makefile 里也是同样的迁移目标。

TypeScript BFF（`infra/bff-mobile`）跑在 Node 上，不进外壳。前端是 Vue 3：PC 端 Ant Design Vue 4 + vxe-table，移动端 Uni-app + wot-design-uni。每个 `package.json` 都写精确版本；前端规则见 [03-frontend.md](03-frontend.md)。

**选依赖库版本**：能自由选的，跟系统里已有的保持一致；依赖链强制要求更新的版本时，跟着走。

## 仓库结构

```
<repo>/
├── component.yaml              brickKit 读
├── assembly.yaml               be-ops 读：permissions、data_scopes、menus
├── contracts/                  <name>.proto、<name>.openapi.yaml、events/<name>.events.json
├── gen/<domain>/<name>/        生成的契约包，独立的 Go module（仅 Go）
├── backend/
│   ├── module/module.go        唯一入口：New(ctx, rt)
│   ├── cmd/server/main.go      只有一行：besdk.RunStandalone(module.New)
│   └── internal/{http,grpc,…}
├── migrations/                 001_<name>.up.sql / .down.sql
├── Dockerfile
└── Makefile
```

Python：`backend/app/module.py`（`create_module`），`backend/app/main.py`（一行），REST 处理器放 `backend/app/http/`，gRPC 处理器放 `backend/app/grpc/`。BFF 的 resolver 表放在 `src/resolvers/`，那个目录里不放别的东西。

## 模块入口

```go
// backend/module/module.go
func New(ctx context.Context, rt *besdk.Runtime) (*besdk.Module, error)

// backend/cmd/server/main.go
besdk.RunStandalone(module.New)
```

```python
# backend/app/module.py
async def create_module(rt: Runtime) -> Module: ...
# backend/app/main.py
besdk.run_standalone(create_module)
```

模块交回它的 HTTP handler（用 `besdk.NewGinEngine(rt)` 建）、gRPC 注册函数和 `Start` / `Stop`。迁移不属于模块：`component.yaml` 声明迁移命令，brickKit 在服务启动前用组件自己的镜像执行它（SDK 已不再读取 `Module.Migrations`，留空即可）。它自己从不监听端口：独立运行时由 `RunStandalone` 监听，合并时由外壳监听。两种形态调用的是同一个 `New`。

外壳在 Go 里是 `shell.Main("<name>", shell.Registry{...})`，在 Python 里是 `besdk.shell_runner.main(name, registry)`。registry 把每个成员的 ID 映射到它的 `New`，列出的成员与外壳 `shell.members` 完全一致。brickKit 在外壳启动之前用每个成员自己的镜像跑它的迁移，所以每个成员仍然要有自己的镜像。

## rt 是唯一入口

模块需要的一切都从 `rt` 来；模块代码不从进程读任何东西。

- **配置**：`rt.Config.String(key)`、`StringOr(key, def)`、`MustString(key)`（还有 `Int*`、`Bool*`），键名就是 `configSchema` 里那个精确的大写下划线名。
- **依赖地址**：`rt.Config.Endpoint(dep, extra)` 返回去掉 `http://` 的地址以及它是否存在；强依赖用 `MustEndpoint`。平台注入的值前面一律带 `http://`，gRPC 端口也一样；拿 `http://host:9094` 去拨号会失败，报错指向域名解析。gRPC 要传端口名：`Endpoint("mdm/customer", "grpc")`；传 `""` 拿到的是 HTTP 端口，gRPC 会报协议错误，而 TCP 连接本身完全正常。
- **缺席的可选依赖根本没有这个变量。** `Endpoint` 返回 `ok == false`，模块自己降级。绝不直接按下标读环境。
- **连接**：`rt.DB` 和 `rt.NATS`。由 `RunStandalone` 或外壳根据 `PG_*` 键和 `NATS_URL` 建好（`besdk.PGDSN(cfg)`、`besdk.NATSURL(cfg)`）；模块从不自己开连接池。
- **对象存储**：`rt.Config.S3URL()`，完整 URL。
- **日志、追踪、指标**：`rt.Logger`、`rt.Tracer`、`rt.Meter`，以及模块自己的 Prometheus registry `rt.Registry`。

Python 用蛇形命名对应同一套名字（`rt.config.endpoint`、`must_endpoint`、`s3_url`、`besdk.pg_dsn`）；TypeScript 用驼峰（`config.endpoint`、`mustEndpoint`）。

## 合并安全

代码完成之前，三个问题都要回答"没有"：

1. **模块代码有没有读进程环境**（`os.Getenv`、`os.environ`）？一个进程只有一份环境：合并后各成员互相覆盖 `PG_SCHEMA` 和其他所有键，某个模块静默地读写了别的组件的 schema。
2. **有没有初始化任何进程级的东西？** `otel.SetTracerProvider`、`logging.basicConfig`、信号处理器、默认 Prometheus registry、`gin.SetMode`（它是包级变量：一个模块开了 debug，所有模块都进 debug，panic 堆栈直接发给客户端）。最后一个初始化的赢、一切照样全绿；默认 registry 在第二个模块注册时直接 panic。一律用 `rt` 提供的。
3. **有没有退出进程**（`log.Fatal`、`os.Exit`、`sys.exit`）？一个模块的可恢复错误会拖垮整个外壳。返回 error。

模块里也绝不调用 `gin.New()`（引擎会丢掉 SDK 的整条中间件链：请求 ID、追踪、RED 指标、访问日志、panic 恢复和错误映射，而且不报错）、`sql.Open()` 或 `Listen`。`make module-check` 检查以上全部。

## 健康检查与镜像

- `/healthz` 只报告这个进程是否活着。绝不在里面检查数据库、NATS、authz 或其他组件：下游一次抖动就会让所有上游同时被判不健康、被重启，在外壳里就是所有成员一起重启。
- `/healthz` 同时应答 `GET` 和 `HEAD`。SDK 的引擎两个都注册了，别自己再注册。
- 启动宽限期（`startPeriodSeconds`）：Go 组件用默认值（60）不写；Python 120；Node 90；外壳镜像 300。
- 基础镜像要有 `/bin/sh` 和 `wget`（Go 用 `alpine`，Python 用 `python:3.12-slim`；be-sdk-python 要求 Python 3.12 及以上）：健康检查经由 shell 执行。用 `scratch` 或 distroless，组件日志说"已就绪"，平台却永远报不健康。检查：`docker run --rm <镜像> sh -c 'wget --version'`。

## 权限

- 权限键是 `<domain>.<aggregate>.<action>`（`erp.sales.confirm`），领域前缀等于组件所属领域。键在 `assembly.yaml` 的 `permissions` 段声明（`key`、`title`、`type: page|action`）；`menus[].permission` 必须是本组件自己的键。新键追加进 `registry/permissions.tsv`，从不改名（[07-registries.md](07-registries.md#权限键)）。
- **权限键是注册路由的一部分。** Go：`besdk.GET(r, path, permKey, h)`（以及 `POST`、`PUT`、`PATCH`、`DELETE`）；Python：`besdk.get(router, path, perm, handler)`；BFF：每个 resolver 都包在 `requirePermission(perm, resolver)` 里。公开路由要显式写 `besdk.Public`；"登录即可"是 `besdk.Authenticated`。用 Gin 裸 `r.GET` 或 FastAPI 裸 `@app.get` 注册的业务路由完全没有校验，而且毫无症状；`make gates` 会扫出来。
- 校验是一次进程内 map 查找。SDK 大约每 15 秒向 infra/authz 拉一次 bundle（`AUTHZ_BUNDLE_URL`）；没有任何组件持有权限表，JWT 只带身份（`sub`、角色、`dept_path`、`org_id`），从不带权限键。bundle 第一次加载成功之前，受保护的路由返回 `503`，`/healthz` 照常健康。用户角色变更之前签发的 token 返回 `401 token_stale`；前端静默刷新 token，并且只重试一次原请求。
- 权限是纯并集，没有 deny。"除了 X 都行"就是给一个不含 X 的角色。
- 前端只在三者同时满足时显示一个路由：已安装（`GET /api/tenant/features`）、该用户有权（`GET /api/me/permissions`）、已登录。只查第一个，结果是菜单看得见、点进去整页 403。前端隐藏从来不是安全边界：拒绝数据的是后端（[03-frontend.md](03-frontend.md#功能权限与菜单)）。

## 数据范围

- `assembly.yaml` 永远有 `data_scopes` 段。不做行级范围的组件写 `data_scopes: none`；漏写这一段 be-ops 会报错，这是刻意的：一个省略即"关闭"的安全设置就是静默泄漏。
- 现在用到的维度：`org`（按 `dept_path` 前缀匹配，不需要组织树副本）、`owner`（等于调用者的 `sub`），以及 `warehouse`、`legal_entity` 这类资源维度（调用者被授权的 ID 集合）。be-ops 把它们汇总进 `registry/data-scopes.tsv`。
- `besdk.ScopeOf(ctx)` 给出按调用者 token 算好的过滤条件；repository 方法接收它，作为静态 `sqlc` 查询的参数传进去。不用 PostgreSQL 行级安全，不拼动态 SQL。
- 列表把 `owner` 和 `org` 用 OR 组合时，两个操作数都必须来自调用者真实的范围；任何一个停留在"全匹配"，整个条件就匹配一切。
- 每个有数据范围的组件都有一个测试：建两条归属不同身份的数据，用其中一个身份查，断言另一个身份的数据一条都不返回（[06-testing.md](06-testing.md#l2-业务规则测试)）。

## 调用其他组件

- 在服务用户请求的路径上，用 `besdk.UserClient(ctx, rt.Config, dep, "grpc")` 调用：它转发调用者的 token，被调方因此按调用者的数据范围过滤。
- `besdk.SystemClient(rt.Config, dep, "grpc")` 带的是组件自己的身份，绕过数据范围。只允许出现在 `Start()` 和事件处理器里。用在用户请求路径上，响应会静默多出用户不该看到的数据；`make gates` 会扫出来。
- 关联数据通过数据所有者的 `batchGet` 拿，绝不跨 schema JOIN。每个聚合根都提供 `batchGet`。
- 组件之间互不 import。唯一共享的代码是 `be-sdk-*`，以及组件生成的契约包 `gen/<domain>/<name>`：它作为独立的 Go module 发布、被直接 import。改成复制一份生成代码，同一个 proto 文件会在一个进程里注册两次，调用方和被调方进了同一个外壳时第二次注册直接 panic。
- 聚合很多组件的组件（BFF、通知路由）把这些依赖全部声明为 `optional: true`；只要有一个是必需依赖，客户没买那个组件的地方它就起不来。客户没买的组件，干脆不加进项目。
- 拉权限 bundle 和验证 token 时，authz 和 iam 不是依赖边：它们的地址是配置键 `AUTHZ_BUNDLE_URL` 和 `IAM_JWKS_URL`。通过 gRPC 调用 authz 或 iam 业务接口的组件（例如 `infra/iam-casdoor` → `infra/authz`），与其他依赖一样声明这条依赖，注入的 `*_ENDPOINT` 只用于这类调用（[04-configuration.md](04-configuration.md#依赖地址)）。

## 数据库

- 每个组件有自己的 schema 和角色。切换永远限定在事务内：`besdk.WithTx(ctx, rt.DB, role, schema, fn)`（Python 是 `with_tx`）在事务里执行 `SET LOCAL ROLE` 和 `SET LOCAL search_path`。不带 `LOCAL` 的 `SET` 会留在池里的连接上，下一个借到它的人把查询打到你的 schema 上：不报错，不崩溃。
- 不跨 schema JOIN。
- 迁移是纯 SQL。迁移状态表放在组件自己的 schema 里（`golang-migrate` 配 `x-migrations-table` 和 `search_path`；`yoyo` 配 schema 参数）。每个迁移都能连跑两次（`make migrate-idempotent`）。
- 会无限增长的表带 `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`、`updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`、`version BIGINT NOT NULL DEFAULT 1`、`status TEXT NOT NULL`，并且从第一个迁移起就分区。分区表的主键和唯一索引包含分区键；归档分区用 `DETACH CONCURRENTLY` 挪进组件自己的 `<schema>_archive`。
- 分区表的唯一索引包含分区键，所以 `INSERT` 发现不了分区键不同的重复（两次投递相隔几微秒）。去重先按业务键显式查一次，再插入，放在同一个事务里。
- 当队列用的行（outbox、重试）要原子认领：`UPDATE … WHERE id IN (SELECT … FOR UPDATE SKIP LOCKED) RETURNING …`。先 `SELECT` 再 `UPDATE`，两个副本一起轮询时每一行都会发两次。
- 金额跨任何边界都用十进制字符串，绝不用浮点数。`List` 接口用游标分页，不接受 `offset`；列表查询默认带时间窗口（SDK 的 `ListWindow`，最近 90 天），除非调用方自己收窄。

## 事件与跨组件写入

- 生产者在业务变更的同一个事务里把事件写进自己的 outbox（`besdk.PublishOutbox`），由后台泵发布到 NATS。
- 消费者是幂等的，每个聚合只接受严格更大的 `version`，重复和乱序都无害。事件头带 `trace_id`、`causation_id`、`hop_count`；`hop_count > 5` 或检测到环，直接进死信队列。
- 事件名是 `<domain>.<aggregate>.<action>.v<n>`。事件 schema 只增：加字段、加新事件可以；删字段、改类型、删 subject 过不了 `make gates`。消费者宽松反序列化。
- 每个跨组件写入都带 `idempotency_key`，先用原子的 `INSERT … ON CONFLICT DO NOTHING` 认领，认领成功才真正写。"先查有没有、没有再插"会让两个并发请求都执行。被调方同时提供 `GetStatus`。
- 同步调用超时后，绝不直接补偿：先调 `GetStatus`。它也超时，就记进本地的待对账表，由定时对账兜底。补偿失败超过三次，把事务标成 `SUSPENDED`，并在 infra/workflow 建一条异常待办。

## 契约

- `contracts/` 是接口的唯一事实来源：gRPC 用 `.proto`，对外 REST 用 `.openapi.yaml`，事件用 `events/*.json`。
- 契约只增。`make contract-check` 拦截 `.proto` / OpenAPI 的破坏性变更；`make gates` 拦截事件的破坏性变更。
- 前端的类型和请求函数从契约生成，从不手写。
