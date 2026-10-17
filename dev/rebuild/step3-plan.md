# 实验第 3 步：Python 的 SDK 子集、外壳启动器、两种语言的探针与一致性剖面

> 2026-10-17 起草。依据：[experiment-plan.md](experiment-plan.md) 的“探针组件”“SDK”表的 Python 一列、“各仓库先做到什么程度”的 `be-acceptance` 一行与第 3 步；[协议 18](../../docs/zh/06-protocols/18-sdk-and-conformance.md)；[组件协议与语言的锁定的技术栈](../../docs/zh/04-foundations/07-component-protocol-and-languages.md#锁定的技术栈)；`be-protocol` `v3.0.0-alpha.1` 的第 1–9 章与向量；第 2 步（[step2-plan.md](step2-plan.md)）的做法与实测发现。每个任务做完：提交到对应仓库、更新本页的进度、继续下一个（连续推进）。

## 范围

| 仓库 | 本步做到 |
| --- | --- |
| `be-sdk-python` | 实验计划“SDK”表的 Python 一列：运行时入口与合并安全（子集）、配置、错误、观测基本档、单跑启动器、外壳启动器（完整）、数据库的事务与迁移、发件表与两个运输适配器上的发布与消费、组件间调用（完整）、身份核验与操作检查、审计的发送、大消息的凭证检查（完整）。后台工作项、列表、投影、分区、幂等键等不做，功能矩阵如实标 `not_implemented` |
| `be-acceptance` | 探针组件 `test/probe-go` 与 `test/probe-py`（同一份契约，`Echo`、`Work`、`Write`、`Relay`、大事件）；一致性套件的最小剖面（端口、健康、表与角色、消息信封、日志与指标），对两种探针都通过 |

不做：负载驱动、资源采集与报告（第 4 步）；`infra/print` 组件本身（业务组件，按计划在之后的步骤）。

## AI 定下的取舍（记进复核清单）

| 项 | 取舍 | 理由 |
| --- | --- | --- |
| Python 版本 | 3.14（宿主机即 3.14.4，镜像用同版本的官方镜像） | 实验计划要求宿主机与镜像的版本对齐 |
| 依赖管理 | `uv`（本机已装 0.12.1），`pyproject.toml` 加 `uv.lock`，版本精确 | 确切版本以依赖锁为准（锁定的技术栈一节） |
| 包名 | 分发名 `be-sdk`，导入名 `besdk`；从 `3.0.0a1`（PEP 440 写法，对应 `3.0.0-alpha.1`）起 | 沿用旧仓库的导入名，组件代码的导入路径不变 |
| 协议的机器可读部分 | 按精确的标签（`v3.0.0-alpha.1`）取 `be-protocol` 的 `vectors/`、`migrations/`、`migrations-bus/`、`capabilities.json`，放进包内 `besdk/_protocol/`（迁移要随包分发），附来源的标签与提交；`make protocol-check` 重新取一次并逐字节比较，向量另按 `SHA256SUMS` 核对 | Python 不能像 Go 那样按模块版本引用；拷贝必须可验证，不能手改 |
| 迁移入口 | SDK 自带（A111，用户 2026-10-17 选定），按 P5.11–P5.16，状态表与 Go 相同 | 见下 |

**冲突与决定：迁移工具。** 锁定的技术栈给 Python 定的是 `yoyo-migrations`；`be-protocol` 的 P5.12 要求两张状态表（`be_sdk_migrations`、`schema_migrations`）在组件 schema 里、形状与 golang-migrate 相同，“所以三种语言的 SDK 读写同一份状态”（同一个库可以先后由不同语言的实现迁移，组件换语言不用重建库）。yoyo 的状态表名与形状是固定的（`_yoyo_migration` 等），做不到。用户选定（A111）：Python SDK 自己实现迁移入口（迁移检查、迁移锁、状态表、每个文件一个事务、锁等待重试与阻塞者报告，按 P5.11–P5.16，Go 的实现约 300 行），把锁定的技术栈中 Python 的迁移一格改为“SDK 自带的迁移入口，纯 SQL 文件”（TypeScript 的 `node-pg-migrate` 同样做不到，一并改）；没有采用的是放宽 P5.12、各语言各用自己的状态表（换语言就要重新迁移，违背语言中立）。

## 任务

| 编号 | 任务 | 仓库 | 验收 | 状态 |
| --- | --- | --- | --- | --- |
| T3.1 | 仓库与骨架：主分支（第 1 步已重启）上建包结构、`pyproject.toml` 与 `uv.lock`、取协议的脚本与检查、`make test`（单元与向量）与 `make test-integration`（`be-postgres`、`be-nats`、`be-rustfs`） | `be-sdk-python` | 向量读取通过 `SHA256SUMS` 核对；`make protocol-check` 通过 | 完成 |
| T3.2 | 运行时与单跑：组件定义与模块接口、配置（声明的键、严格解析、`_FILE` 密钥与重读）、错误对象与原因目录（problem+json、gRPC 状态）、观测基本档（标准 `logging` 的 JSON 格式、每成员一个指标注册表、OpenTelemetry）、FastAPI 跑在 uvicorn 上（单进程、单事件循环）、单跑启动器（`serve`/`migrate`、退出码、健康与就绪、自描述、计时源检查、体面停止）、合并安全检查（AST 扫描：读进程环境、进程级初始化、退出进程、绕过 SDK） | `be-sdk-python` | 向量 `errors`、`config-parse` 通过；合并安全检查对 SDK 自身通过、对故意加入的违规报出 | 待做 |
| T3.3 | 外壳启动器：按 `BRICKKIT_SERVED_MEMBERS_CONFIG` 构造成员；按安装的分发元数据核对成员版本，拒绝可编辑安装或路径安装（对应 Go 的 `replace`）；每个成员独立的端口与运行时；进程级键一致；同一数据库目标的成员共用一个池；拒绝条件一起报出；并行停止 | `be-sdk-python` | 与 Go 外壳同样的拒绝情形与“单跑与外壳行为一致”的测试 | 待做 |
| T3.4 | 数据库：`asyncpg` 池（按成员的预算，外壳中用外壳登录角色）、事务入口（`SET LOCAL ROLE`、`search_path`、超时；`40001`/`40P01` 重试；错误映射；不许嵌套）、外壳中按成员区分语句缓存（P5.4）、启动检查、迁移入口（按上面的决定）、UUIDv7、单号序列 | `be-sdk-python` | 向量 `db-errors`、`migration-lint` 通过；0-12 的泄漏情形不出现；**同一个 schema 先由 Go SDK 迁移、再由 Python SDK 迁移时“已是最新”**，反过来也一样 | 待做 |
| T3.5 | 组件间调用：`grpc.aio` 的服务端与客户端拦截器、HTTP 客户端；出站时限、重试决定与预算、熔断、并发上限、结果分类与向上报告、转述不重试；请求 ID、追踪、幂等键的转发；事务内不发调用 | `be-sdk-python` | 向量 `outbound-timeout`、`retry-decision`、`retry-budget`、`circuit-breaker`、`call-outcomes` 通过；Go→Python→Go 的调用链“只有一层重试” | 待做 |
| T3.6 | 事件：发件表（同一组表）、锁内编号与纪元、转发、CloudEvents 信封、JetStream（`nats-py`）与 PostgreSQL 队列适配器、消费者（收件表去重、死信、跳数）、大消息的凭证检查（`aioboto3`）；运输检查套件移植 | `be-sdk-python` | 向量 `partition`、`envelope` 通过；运输套件在两个适配器上通过；Go 产生、Python 消费与反方向，在两种运输上都只生效一次 | 待做 |
| T3.7 | 身份与操作检查、审计的发送：JWT 核验（PyJWT，公钥刷新与限速）、服务身份（部署 mTLS 与允许的调用组件）、授权视图的持有与核验（P8.9–P8.13）、段的单对象求值（P8.14–P8.16）、资源与操作的声明；本地审计表、编号与发送 | `be-sdk-python` | 向量 `jwt-verify`、`canonical`、`segment-eval`（单对象部分）通过；看不见答 404、无权答 403；审计记录经 mTLS 到达（假的）审计组件 | 待做 |
| T3.8 | 探针：契约（HTTP 与 gRPC 两面，`Echo` 1 KiB/60 KiB、`Work`、`Write`（事务内写一行与发件行）、`Relay`（收到事件调用下一个探针）、大事件），Go 与 Python 各实现一次；`be-acceptance` 中一个仓库放多个组件（目录前缀的标签），组件 ID `test/probe-go`、`test/probe-py` | `be-acceptance` | 两种探针单跑与互相调用、互发事件；`brickkit lint` 通过 | 待做 |
| T3.9 | 一致性剖面：从外部检查运行中的组件——端口与健康、就绪、自描述、表与角色（状态表、SDK 表、角色与授权）、消息信封（头与摘要）、日志（结构、无凭据）与指标 | `be-acceptance` | 两种探针都通过同一剖面；对故意做坏的变体判红 | 待做 |
| T3.10 | 收尾：`be-sdk-python` 的功能矩阵（`features.json`，按协议的能力清单）；发 `be-sdk-python` 的 `3.0.0a1` 与 `be-acceptance` 探针的标签（发布前列出标签请用户确认）；更新装配项目的子模块指针与交接 | 两个仓库、本项目 | 功能矩阵与协议一一对应 | 待做 |

## 进度

（每完成一个任务在这里加一行：日期、提交、结论。）
- 2026-10-17 T3.1 完成：`be-sdk-python` `64bea8e`。主分支上建 `pyproject.toml` 与 `uv.lock`（Python 3.14；FastAPI 0.143、uvicorn 0.54、grpcio 1.84、asyncpg 0.32 等锁定的技术栈全部能在 3.14 上解析与导入）；`besdk/_protocol/` 是 `be-protocol` `v3.0.0-alpha.1`（`659215e`）的向量、迁移与能力清单，`scripts/protocol.py` 按标签取与逐字节核对（`make protocol-check`），向量另按 `SHA256SUMS` 核对；清掉了旧代码留下的缓存与虚拟环境（只有缓存，没有源码）。
