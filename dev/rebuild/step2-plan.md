# 实验第 2 步：`be-protocol` 的实验子集与 Go SDK

> 2026-10-17 起草并开始执行（用户：“直接开始”）。依据：[experiment-plan.md](experiment-plan.md) 的“各仓库先做到什么程度”与第 2 步；[协议 18](../../docs/zh/06-protocols/18-sdk-and-conformance.md)、[协议 17](../../docs/zh/06-protocols/17-runtime-and-resources.md)、[组件实现约定](../../docs/zh/01-conventions/06-component-implementation.md)、[组件协议与语言](../../docs/zh/04-foundations/07-component-protocol-and-languages.md)、[承接清单](be-protocol-carry.md)，以及第 0 步记录里交给第 2 步的要求。每个任务做完：提交到对应仓库、更新本页的进度、继续下一个（连续推进）。

## 范围

| 仓库 | 本步做到 |
| --- | --- |
| `be-protocol` | 只写实验用到的规则与语义向量：生命周期与健康、配置、错误与原因、组件间调用（截止时间、重试、熔断）、消息信封、发件表编号、凭证检查（大消息）；Go 与 Python SDK 的 L1 测试都读这些向量。其余章节在重建时按承接清单写入 |
| `be-sdk-go` | 实验计划“SDK”表里 Go 一列：运行时入口与合并安全、数据库与迁移、发件表与两个消息适配器、后台工作项、组件间调用、身份与授权的链上部分、审计客户端、列表、投影（全量重新取回）、凭证检查、观测基本档、外壳启动器 |

## AI 定下的取舍（记进冻结报告式的复核清单）

| 项 | 取舍 | 理由 |
| --- | --- | --- |
| 模块路径 | `github.com/brickKit/be-sdk-go/v3`、`github.com/brickKit/be-protocol/v3`；Go 1.26 | A110 从 3.0.0 起；Go 主版本 2 起路径带主版本 |
| 协议仓库的布局 | `spec/`（中文规范，按协议 18 的章节编号）、`vectors/`（JSON 向量与 `SHA256SUMS`）、`schemas/`（JSON Schema：错误体、信封）、`ddl/`（参考 DDL：发件表、收件表、工作项、幂等记录）；仓库同时是一个 Go 模块，用 `embed` 交出向量，SDK 的 L1 测试按精确版本引用 | 规则正文只在一处（A99）；向量随协议版本发布（协议 18） |
| 规范语言 | 中文（D67，开发完成前只写中文）；代码、标识符、提交信息英文（D74） | — |
| 版本 | 开发中用预发布 `3.0.0-alpha.N`；实验结束、进入正式时 `3.0.0` | A110；预发布不占用正式号 |
| 需要真实数据库与消息系统的测试 | 放在构建标签 `integration` 下，`make test-integration` 对 `make up` 的 `be-postgres`、`be-nats` 运行，库名 `be_sdk_test`；缺环境时失败而不是跳过 | “绝不加跳过”；协议 18：未运行不是通过 |
| 包的划分 | 一个领域一个包：`runtime`、`config`、`launcher`（单跑）、`shell`（外壳启动器）、`httpx`（Gin 与中间件链）、`rpc`（grpc-go 的服务端与客户端）、`calls`（截止时间、重试预算、熔断、出站并发）、`errs`（原因目录与映射）、`db`（池、事务入口、启动检查、迁移入口）、`ids`（UUIDv7 与单号）、`events`（信封）、`outbox`、`bus/jetstream`、`bus/pgqueue`、`inbox`、`work`、`identity`、`authz`、`audit`、`list`、`projection`、`claimcheck`、`obs`、`decimal` | 每个包能单独读懂；文件与函数的大小上限按 AI 编码习惯 |

## 任务

| 编号 | 任务 | 仓库 | 验收 | 状态 |
| --- | --- | --- | --- | --- |
| T2.1 | 协议仓库骨架；第一批章节：生命周期与健康、配置、错误与原因目录（含 HTTP 与 gRPC 的映射）、组件间调用的头与数值；向量：错误映射、出站时限计算、重试预算、熔断状态转换 | `be-protocol` | `make check` 校验向量的格式与校验和；规范与正式文档的引用一致 | 完成 |
| T2.2 | SDK 骨架：运行时接口与模块入口、配置（声明的键、严格类型、`_FILE` 密钥与重读）、观测基本档（slog JSON、每模块一个 Prometheus 注册表、每成员的追踪提供者）、单跑启动器（健康 `GET`/`HEAD`、就绪、启动与停止状态机、SIGTERM 体面停止）、Gin 引擎与中间件链（请求 ID、追踪、截止时间、错误映射、指标、崩溃恢复、操作登记） | `be-sdk-go` | L1 通过；合并安全的静态检查（不读进程环境、不初始化全局、不退出）对 SDK 自己通过 | 完成 |
| T2.3 | 外壳启动器：按 `BRICKKIT_SERVED_MEMBERS_CONFIG` 构造成员；按 Go 构建信息核对编进来的成员版本、发布构建拒绝 `replace`（0-04）；进程级共享与按成员的划分（协议 17 的四条不变量）；拒绝条件一起报出；并行停止 | `be-sdk-go` | 0-04 的 C5、C6 两种情形都拒绝启动并点名成员；单跑与外壳行为一致的测试 | 完成 |
| T2.4 | 数据库：池（按成员标名 `application_name`、预算）、事务入口（`SET LOCAL ROLE`、`search_path`、超时；禁止嵌套与事务内网络调用）、启动检查（`fsync`、`synchronous_commit`、计时源）、迁移入口（golang-migrate，状态表在组件 schema，连跑两次）、执行模式（0-12：代理开启预编译时用默认，配置为经事务模式代理且不支持时用 `CacheDescribe`）、UUIDv7 与单号 | `be-sdk-go` | 集成测试：0-12 的泄漏情形在 SDK 入口下不出现；外壳共享池下成员互不串 schema；多实例并发认领测试 | 进行中 |
| T2.5 | 组件间调用：错误原因与映射、截止时间逐跳缩短、重试预算、熔断、出站并发上限；HTTP 与 gRPC 两侧的客户端与拦截器；服务身份与转发用户凭据的形状 | `be-sdk-go`（规则在 T2.1） | 读 T2.1 的向量；故障注入下“只有一层重试” | 待做 |
| T2.6 | 事件：信封、发件表（分区计数行、锁内编号、纪元）、发件转发、JetStream 适配器、PostgreSQL 队列适配器、消费者与收件表、大消息的凭证检查；对应的协议章节与向量 | `be-protocol`、`be-sdk-go` | 两个副本同时转发不重号（RT09）；消费者重复投递只生效一次；两个适配器过同一组测试 | 待做 |
| T2.7 | 后台工作项：原子认领、租约与代次、定时槽位、`outcome_unknown` 与暂停 | `be-sdk-go` | 两个副本同时触发同一定时任务只执行一次（RT08）；停止时释放租约（RT07） | 待做 |
| T2.8 | 身份与授权的链上部分：令牌验证（JWKS）、主体与服务身份、资源定义登记、有界本地视图与生效点、数据范围编译成 SQL；审计客户端（发送与重试） | `be-sdk-go` | 认证在 SDK 测一次；没有登记的路由启动失败；数据范围的“别人的看不见”测试 | 待做 |
| T2.9 | 列表（游标、排序、筛选、一种搜索列）、投影与水位（全量重新取回） | `be-sdk-go` | 游标向量；投影重建后与来源一致 | 待做 |
| T2.10 | 收尾：功能矩阵（每项能力的状态）、发 `be-protocol` 与 `be-sdk-go` 的 `3.0.0-alpha.1`、更新装配项目的子模块指针与交接 | 两个仓库、本项目 | 发布前列出标签请用户确认（首次发版） | 待做 |

第 0 步留给本步的验收项汇总：外壳启动器按构建信息核对版本并拒绝 `replace`（0-04）；`local.migrationCommand` 能从源码跑迁移（0-05、FRB-003）；删副本时零失败的体面停止（0-09）；每个成员一个连接池（0-10）；事务内设置与执行模式（0-12）。

## 进度

（每完成一个任务在这里加一行：日期、提交、结论。）

- 2026-10-17 T2.1 完成：`be-protocol` `17007cf`。第 1–4 章（生命周期与健康、配置、错误、组件间调用）与 6 个向量文件（错误、配置解析、出站时限、重试决定、重试预算、熔断），由 `scripts/gen-vectors.py` 生成、`vectors_test.go` 独立重算；故意改坏一个期望值时测试变红。定下的细节：共享连接键表（含 `PG_SCHEMA`、`PG_MIGRATION_HOST`、`PG_OWNER_*` 只给迁移入口、`PG_POOLER_PREPARED`、`BUS_URL` 按 scheme 选适配器）；退出码 0/1/64/69/78；停止先等 2 秒摘除延迟；1 号进程自己处理 SIGTERM（0-09 的发现）；重试预算按 gRPC `retryThrottling` 并以千分之一整数计；熔断试探一次一个、连续 3 次成功关闭。
- 2026-10-17 T2.2 完成：`be-sdk-go` `a4a752d`。包：`component`、`launcher`（入口、退出码、配置一次报全、`COMPONENT_ID`/`COMPONENT_VERSION` 与编进的定义核对、计时源检查、就绪、体面停止：立即不就绪→摘除延迟→进行中的请求完成→停止时限）、`config`、`errs`、`httpx`（每成员一个 Gin 引擎与中间件链，路由必须声明操作或显式公开）、`runtime`、`obs`、`clock`、`mergesafety`（合并安全检查，对 SDK 自身运行；故意加入的读环境变量被抓到）。L1 全部通过，含协议的 errors 与 config-parse 向量。**发现并修正规范的一处错误**：共享连接键表写了 `OTEL_EXPORTER_OTLP_ENDPOINT`，以 `_ENDPOINT` 结尾属于平台（P2.3），SDK 启动即按自己的规则拒绝它；改名 `OTEL_URL`（`be-protocol` `fc018dd`）。
- 2026-10-17 T2.3 完成：`be-sdk-go` 外壳启动器（`shell`）与单跑共用的成员构造（`internal/host`）。0-04 的 C6（成员没编进来）、C5（构建信息里的版本不同、带 `replace`）都拒绝启动并点名成员；`replace` 只在显式 `SHELL_ALLOW_REPLACE=true` 时放行并警告。外壳端口的就绪列出还在等的成员，指标按成员加 `component` 标签。写测试时有一个断言写错（Go 按最长模块前缀归属包，旧的 v1 模块可以包含 `v3/` 目录），未提交前改正并在提交说明前确认实现无误。真实镜像里的端到端（按标签取成员、不用 `replace`）留到第 4 步建外壳时验证。
