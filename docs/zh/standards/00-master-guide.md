# BrickEnterprise 总纲

> **这一份是长期有效的框架与规范，不是任务清单。** 读完它，你就掌握了这个项目全部的骨架信息：
> 要跑哪些基础资源、端口与 schema 怎么分、62 个组件分别是什么、仓库怎么组织、
> 写一个组件要走哪些步骤、一共分几个阶段、每个阶段大致做什么、哪些纪律贯穿全程。
>
> **具体到"某个阶段的第几步做什么"，在各阶段自己的计划文件里**——那些文件是一个阶段做完、
> 拿到反馈、（必要时）改完设计书之后，才写下一份。

**目标：** 在 brickKit 平台之上，按「先验平台 → 再跑闭环 → 再做外壳 → 最后铺货」的顺序，建成 58 个可交付组件的军火库、5 个外壳、2 个交付关键路径工具（`be-ops` / `be-acceptance`）与 3 份语言基础库，以及一套一键管理的基础资源环境。

**架构：** 每个组件是一个独立 Git 仓库 + 一块能单独 `brickkit up` 起来的纯 brickKit 组件；本仓库（`be-assembly-standard`）既是标准装配模板，也是军火库索引（用 git submodule 记住每个组件仓库的地址与精确 commit）。基础资源全部 Docker 部署，分「brickKit 基础资源（形态 A）」与「带外容器（形态 B）」两类，由本仓库的 `Makefile` 统一管理。合并部署（外壳）只在验完平台、跑通闭环之后，作为**交付期的部署选择**出现，绝不反过来影响开发形态。

**技术栈：** Go 1.22+（骨骼与血管）、Python 3.11+（大脑与复杂器官）、TypeScript / Vue3 / Uni-app（皮肤与神经）、PostgreSQL 16、NATS 2.10 (JetStream)、Traefik v3、Casdoor、RustFS、gRPC / Protobuf、OpenTelemetry、Docker Compose v2+。

**规范来源（唯一真相源）：** [`BrickEnterprise 设计书.md`](../../../BrickEnterprise%20设计书.md)
引用时一律带节号（如 §3.5.1.1）。**本文档与设计书冲突时，以设计书为准，并回来改本文档。**
平台侧行为以 brickKit 仓库 `design/` 下 14 本规范性文档为准（引用格式如 `004 §3.9`）。

---

## 文档地图

```
be-assembly-standard/
├── BrickEnterprise 设计书.md          ← 规范真相源。改设计先改它
├── AGENTS.md                          ← AI 助手导读（索引 + 禁令）。CLAUDE.md 一行 @AGENTS.md
├── brickkit.yaml                      ← 装配清单真相源（§9.1 两个真相源之一）
├── Makefile                           ← 基础资源唯一入口
├── registry/                          ← 端口册 / schema 册 / 权限键册（写 component.yaml 前必查）
├── docs/
│   ├── README.md                      ← ⭐ 按读者分诊（部署 / 开发 / 架构 / 客户）。**人的总入口**
│   ├── ops/
│   │   └── 部署手册.md                ← 部署人员唯一需要的一份，自足；数据库五层表在它的 §3
│   ├── standards/                     ← 长期有效的规范文档（不分阶段，不是执行计划）
│   │   ├── 00-master-guide.md                    ← 本文件。框架 + 规范 + 阶段总览
│   │   ├── 04-testing-standard.md        ← ⭐ 测试怎么分层、红绿节奏、卡住怎么办——全部测试相关规范的唯一真相源
│   │   ├── 05-data-construction-standard.md ← ⭐ 种子数据 + 测试数据怎么设计、组件间怎么协作的唯一真相源
│   │   └── 01-documentation-standard.md  ← ⭐ 文档该怎么组织、何时拆分、组件文档服务哪两种读者
│   ├── plans/
│   │   ├── 01-阶段一-地基与第一块砖.md  ← 阶段一的完整任务
│   │   └── （02、03… 每阶段开工前才写）
│   ├── zh/                            ← 每一份第一档文档的中文镜像（AGENTS.md 加上 docs/standards/ 下全部六份，含本文件自己）
│   └── design/                        ← 组件设计计划，一个组件一份，随开发进度逐步添加
│       ├── README.md                  ← 索引 + 什么时候写、写成什么样
│       ├── _模板.md
│       └── mdm-customer.md            ← 阶段一产出的第一份
├── components/<scope>/<name>/         ← 每个组件一个 submodule
│                                        （各带 README.md + docs/手册.md + AGENTS.md + CLAUDE.md）
├── shells/{go,python}/                ← 外壳，不进 components/（各带 AGENTS.md）
└── tools/{be-ops,be-acceptance,be-sdk-go,…}/
```

### 一个组件有四份文档，缺一不可

| # | 文件 | 在哪 | 读者 | 写什么 | 什么时候写 |
|---|---|---|---|---|---|
| 1 | `docs/design/<仓库名>.md` | **装配仓库**（本仓库） | 做设计决策的人 | **组件设计计划**：边界、拥有的表、契约面、事件、依赖、分区与归档策略、在同步图里的位置、待决问题 | 该组件开工**之前**，随开发修订 |
| 2 | `README.md` | **组件仓库**根 | 「要不要装它、怎么装」的人 | **基础信息**：它是什么、有什么功能、需要哪些基础资源、怎么起来、怎么用、借鉴了哪些开源项目 | 建骨架时第一版，功能变了就改 |
| 3 | `docs/手册.md` | **组件仓库** | 「已经装了、要用它 / 要改它」的人 | **细节**：每个功能的具体使用方式、完整契约清单、项目结构、配置项逐条、开发与排障 | 随实现同步长出来 |
| 4 | `AGENTS.md` + `CLAUDE.md` | **组件仓库**根 | **AI 助手** | **判据与禁令**：身份证、边界（尤其「不归我」）、本组件特有的坑与症状、改代码前的自查 | 建骨架时骨架，Task 定稿时校准 |

**为什么分四份**（都不是洁癖）：

- 第 1 份留在装配仓库，因为**设计决策要能被跨组件对照着看**——`erp-sales` 为什么不直接查 `mdm-customer` 的表，只有把两份设计计划摆在一起才讲得清。它跟着装配仓库走，组件仓库被 Fork 出去也不会带走它。
- 第 2、3、4 份必须在**组件仓库里**，因为组件是独立交付物：客户拿到 `erp-sales-acme` 这个 Fork 目录时，得能只靠这个目录跑起来。
- 第 2 份与第 3 份分开，是因为**读者不同**：README 给「要不要装」的人，手册给「已经装了」的人。合成一份，两类读者都得翻过对方那一半。
- 第 4 份与前三份分开，是因为**AI 与人的失败模式不同**。人不会写出 `grpc.Dial("http://host:9094")`，也不会把 `SET LOCAL` 写成 `SET`——这两条在 README 里不该占篇幅，但在 AI 文档里必须**前置并带上症状**。反过来，AI 不需要 README 的铺垫与说服。

**AI 文档的两条硬规则**（违反了它就退化成第二份 README）：

1. **不许出现「见上文」「详见某节」这类需要回头翻的引用。** AI 可能只拿到文件片段，每一条必须自足；要指向别处就带节号（`§13.3 铁律六`）。
2. **每条禁令自带「为什么」+「违反后的症状」。** 症状是 AI 唯一的自查锚点——不带 `LOCAL` 的 `SET` 那条的症状是「不报错、不崩，只是悄悄读写了别人的数据」，不写出来，AI 没有任何办法发现自己写错了。

**结构上是「索引 + 叶子」，不做全站压缩件：**

| 层 | 文件 | 特点 |
|---|---|---|
| 索引 | 装配仓库根 [`AGENTS.md`](../../../AGENTS.md) | **薄、稳定、每次会话都加载**。只放路由表（要做 X → 读 Y）、十八条最容易写错的、三张钉死的表、当前阶段、不要提议的东西 |
| 叶子 | `components/<scope>/<name>/AGENTS.md` | **自包含**。只讲这一个组件，不假设读者读过别的 |
| 叶子 | `shells/{go,python}/AGENTS.md` | 外壳的四条不许 + 铁律二/五/六/**七** |

⚠️ **刻意不做「全站压缩件」**（brickKit 自己有一份 `AI-CONTEXT.md`）。62 个组件的压缩件必然过期，而过期的压缩件比没有更糟——它读起来权威、实际是半年前的快照。索引 + 叶子的结构里，每一片的作者就是那一片的负责人。

具体每一份写什么、模板在哪，见 §4 的 **SOP-D**。

---

## 全局约束（每个任务都隐含包含本节）

以下每一条都是设计书里的硬约束，抄的是原值，不是概述。**任何任务的实现都必须同时满足这一整节。**

### A. 两条不可让渡的开发原则（§1.5）

1. **每个组件都以纯 brickKit 组件形态开发，并独立跑通。** gRPC 一个不省；`extraPorts` 里声明的 gRPC 端口必须真的 `Listen`；`contracts/*.proto` 里每个 rpc 必须能被跨进程调通（含 `batchGet`）；能只装这一个组件（连同强依赖树）就 `brickkit up` 起来。
2. **合并只发生在部署形态上。** 外壳不许让两个组件模块直接互相 `import`、不许把两个组件的表放进同一 schema、不许把 N 个模块的 API 合并成一个端口、不许在外壳里写任何业务逻辑。

### B. `component.yaml` 的字段禁区

- **未知键当场报错，不是静默忽略**（`002` §2.2.1）。`asset` / `assembly_role` / `slot_name` / `edge_routes` / `menus` / `domain` / `tier` / `shell` / `requirements` / `expose` / `dependencies.strong|weak` / 顶层 `labels` **一个都不能写进 `component.yaml`**，全部放同目录的 `assembly.yaml`，并在 `artifacts` 里声明 `type: metadata` 随组件分发（§3.5）。
- **版本必须精确**：`1.0.0` 可以，`^1.2` / `~1.2` / `1.2.x` / `latest` 一律报错。
- **同一份 `dependencies` 里一个组件 ID 只能出现一次**（变量名不带版本号，写两个版本会静默互相覆盖，CLI 解析期报错）。
- **没有 `role:{slot}` 这种依赖写法**，依赖只能是精确组件 ID + 精确版本。

### C. 平台保留变量（§附录 I）

`COMPONENT_ID`、`COMPONENT_VERSION`、**任何以 `_ENDPOINT` 结尾的**、以及以 `DATABASE_` / `REDIS_` / `MQ_` / `STORAGE_` / `SEARCH_` / `SMTP_` 开头的，全部由平台注入。`configSchema` 里起同名项会被**跳过并只给一条警告**。

因此本项目**钉死**以下命名：

| 语义 | 必须叫 | 绝不能叫 | 理由 |
|---|---|---|---|
| 本组件的 PG schema | `pgSchema` | `databaseSchema` | `DATABASE_` 是保留前缀 |
| OTel Collector 地址 | `otelBaseUrl` | `otelEndpoint` | `*_ENDPOINT` 是保留后缀（§2.7.3） |
| JWT 验签公钥地址 | `iamJwksUrl` | `iamEndpoint` | 同上，且业务组件不对 IAM 建依赖边 |
| 启用组件清单（仅 IAM 适配层） | `enabledComponents` | — | 值必须是**逗号分隔字符串**，数组会被渲染成 `[a b c]`（§6.1） |

### D. 地址格式（§2.1）

**组件依赖地址**（`{组件前缀}_ENDPOINT` 与 `{组件前缀}_{端口名}_ENDPOINT`）**恒为 `http://` 开头**，额外端口也一样：

```
ERP_SALES_ENDPOINT=http://erp-sales-1-0-0:8084          # deployment.port
ERP_SALES_GRPC_ENDPOINT=http://erp-sales-1-0-0:9094     # extraPorts 里 name: grpc
```

**没有 `grpc://` 这种东西。** gRPC 客户端必须自己 `strings.TrimPrefix(v, "http://")`——`grpc.Dial("http://host:9094")` 连不上，而报错指向名称解析，极难联想。这一条写进每个语言的基础库，**只做一次**（见 Task 6 / Task 7）。

⚠️⚠️ **但资源变量不是这个格式，`STORAGE_ENDPOINT` 是唯一的陷阱：**

| 变量 | 值 | 基础库里怎么处理 |
|---|---|---|
| `{组件前缀}_ENDPOINT` / `..._{端口名}_ENDPOINT` | `http://mdm-customer-1-0-0:9090` | **剥掉** scheme（gRPC 客户端要 `host:port`） |
| **`STORAGE_ENDPOINT`** | `host.docker.internal:9000`，**裸 host:port** | **加上** scheme（S3 SDK 要完整 URL） |
| `DATABASE_HOST`+`DATABASE_PORT`、`MQ_HOST`+`MQ_PORT` … | 主机与端口分成两个变量 | 各自拼 |

**`STORAGE_ENDPOINT` 是唯一一个名字里带 `ENDPOINT`、值却不带 scheme 的**（实测 brickKit `internal/inject/inject.go`：组件地址走 `fmt.Sprintf("http://%s:%d", ...)`，而 storage 走 `hostPort(r)` 即 `host:port`）。基础库里这两个必须是**两个函数**，共用一个必然有一边错。

**读 `*_ENDPOINT` 必须用 `os.Getenv()` / `os.environ.get()`。** 弱依赖缺失时那个变量**根本不存在**（不是空字符串），用 `os.environ["X"]` 会启动时崩溃——这是平台刻意的设计（§3.6）。

### E. 端口（§3.5.1.1）

- `deployment.port` 与 `extraPorts[].port` **在全部 62 个组件里两两不重复**，由「全局端口册」（§2.1）钉死。
- **HTTP 主端口**装配期还能用 `localPort` 改；**gRPC 等额外端口完全不能事后改**（平台没有额外端口的 `localPort`，改写地址时明确跳过；两个 `local: true` 组件撞同一额外端口，`brickkit up` 生成阶段硬报错）。
- 结论：**gRPC 端口只能在 `component.yaml` 里一次写对。** 端口册必须在第一块砖之前建好。

### F. 健康检查（§12.3.6 / §12.3.7）

- `/healthz` **只检查本进程存活**。严禁查数据库、查依赖组件、查 NATS。
- 默认启动宽限是 **60 秒**（不是 30）。`startPeriodSeconds` 只推迟「判死」不推迟「判活」，写大没有代价：

| 谁 | 写多少 |
|---|---|
| Go 单体组件 | **不写**（默认 60 够用） |
| Python 组件（`infra-print`、`hrm-payroll-es`、`crm-commission`、`erp-manufacturing`、`ana-bi`、`ana-ai`、`integration-edi`） | `120` |
| Node 组件（`infra-bff-mobile`） | `90` |
| 外壳镜像（在我们自己那份 shell-compose 里，不经平台） | `300` |

- **镜像里必须有 `/bin/sh` 加 `wget` 或 `curl`。** 平台的健康检查是 `CMD-SHELL`，`FROM scratch` / `distroless` 一律不行。全项目统一用 `alpine` / `debian-slim` 基底并装 `wget`。

### G. 数据（决策 3 / §13.3 铁律二 / §11.2.3）

- 全系统**共享单一 Database `brickkit_db`**，每组件独立 schema + 独立 PG Role。
- **切换必须用 `SET LOCAL`，绝不能用不带 `LOCAL` 的 `SET`**：

```sql
BEGIN;
SET LOCAL ROLE {组件角色};
SET LOCAL search_path TO {组件schema};
-- 业务 SQL
COMMIT;   -- SET LOCAL 自动还原，连接干净地回池
```

  用不带 `LOCAL` 的 `SET` 之后把连接还回共享池，**下一个借用者会原样继承——A 组件的查询打在 B 组件的表上，不报错、不崩，只是悄悄读写了别人的数据。** 这是这套写法唯一的雷，也是最难查的一个。
- **严禁跨 schema JOIN**，关联数据走 gRPC `batchGet`。
- **迁移状态表必须落在各自的 schema 里**，且表名或主键含组件标识（Go 侧 `golang-migrate` 用 `x-migrations-table` + `search_path`；Python 侧 `yoyo-migrations` 用 `--schema` / 连接串的 `schema` 参数）。**迁移工具按语言分，语言内必须统一**——见 §K。默认往 `public` 写会让 62 个组件的迁移记录互相顶掉。
- 所有可能无限增长的业务表强制含：`created_at TIMESTAMPTZ NOT NULL DEFAULT now()`、`updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`、`version BIGINT NOT NULL DEFAULT 1`、`status TEXT NOT NULL`。
- **分区表主键必须包含分区键**（决策 59）；归档用 `DETACH CONCURRENTLY`（PG 14+，决策 60）；归档分区移入**本组件专属**的 `{组件schema}_archive`，**不许共用全局 archive schema**（§11.5.4）。

### H. 事件（§3.10 / §4.4 / §4.6）

- 生产者**必须**用 Outbox Pattern（本地事务写 `event_outbox`，后台线程发 NATS）。
- 消费者**必须**幂等；事件 Header 必须带 `trace_id` / `causation_id` / `hop_count`，`hop_count > 5` 或成环直接丢弃进 DLQ。
- 消费者**必须**校验 `version`，只允许状态单向演进（严格大于才更新）。
- Schema 演进：**只增不删不改**，消费者宽容反序列化。
- 事件命名：`{domain}.{aggregate}.{action}.v{n}`，与权限键、路由前缀共用 `{domain}.{aggregate}.{action}` 模式（§3.7）。
- 所有跨组件写接口带 `idempotency_key`，被调用方用唯一约束去重。
- **同步调用超时后严禁直接补偿**，必须先调下游 `GetStatus`；`GetStatus` 也超时则写本地「待对账」表，由定时对账兜底（§4.5）。
- 补偿失败超 3 次 → 标记 `SUSPENDED` + 调 `infra-workflow` 建 `type: exception` 待办（§4.4.4）。

### I. CI 门禁（§3.11 + §13.3 铁律六）

每个组件仓库的 `Makefile` 必须提供，全绿才允许打 tag：

| # | 目标 | 守的是 |
|---|---|---|
| 1 | `make check-version` | `component.yaml` 的 version 与 git tag 不许分叉 |
| 2 | `make test` | 单测 race-clean |
| 3 | `make image` | Docker 构建；镜像里必须有 `/bin/sh` + `wget` |
| 4 | `make migrate-idempotent` | 同一份迁移连跑两次都必须成功 |
| 5 | `make dag-check` | 强依赖图无环 |
| 6 | `make contract-check` | `buf breaking`（proto）/ `oasdiff`（OpenAPI），禁破坏性变更 |
| 7 | `make import-scan` | **铁律六**：本组件不许 import 任何其他组件仓库（Go 用 `go list -deps`，Python 用 `grimp`） |
| 8 | `make smoke` | **原则一**：只装这一个组件（连同强依赖树）`brickkit up`，`curl` 打 HTTP、**`grpcurl` 打 gRPC**、`/healthz` 转 healthy（设计书 §3.11 第 8 条，本表旧版漏抄） |
| 9 | `make module-check` | **铁律七**：① `backend/module/module.go` 导出的签名与 §K 逐字一致；② `cmd/` 之外零 `os.Getenv`/`os.environ`；③ 零 `log.Fatal`/`os.Exit`/`sys.exit`；④ 零 `SetTracerProvider`/`basicConfig`/信号处理器/默认 Prometheus registry；⑤ 依赖里没有 §12.4 为**本组件这门语言**禁掉的库（Go：echo/fiber/chi、gorm、lib/pq；Python：flask/django、同步 `grpc`、sqlalchemy、alembic、gunicorn）。**全是 grep 级的检查，但人守不住** |

### J. 交付模型（§9.4）

全本地源、本地构建、无远程私有 Registry。**签名整体不生效**（本地源不强制签名 + 外壳镜像不在覆盖范围内），供应链保证靠：① 每个组件目录对应一个 git remote + 一个 tag（本仓库的 `.gitmodules` 就是这张表）；② 构建脚本进版本控制；③ 外壳镜像的构建/签/验流程写进交付文档。

### K. 统一技术栈与模块入口（§12.4 / §12.5 / §13.3 铁律七）

**这一节整节的判据是一句话：在单跑形态下 100% 正确、只有进外壳才错的东西，全在这里。**

- **栈不许自选，逐格抄设计书 §12.4**：
  - Go = **Gin** + `database/sql` + `pgx/v5/stdlib` 驱动 + **`sqlc`**（不用 GORM）+ `grpc-go` + **`golang-migrate`**
  - Python = **FastAPI** + **uvicorn 编程式 `Server`（单进程单事件循环，禁 gunicorn、禁 `workers > 1`）** + **`grpc.aio`**（禁同步 `grpc`）+ **`asyncpg`** + 手写 SQL（不用 ORM）+ **`yoyo-migrations`**（裸 `.sql`，不用 alembic）
  - ⚠️ **迁移那一格是「语言内统一」，其余每一格是「全项目统一」。** 外壳不跨语言（§13.5），所以 Go 外壳的启动器只需认识 `golang-migrate`、Python 外壳只需认识 `yoyo`；而「迁移状态表落各自 schema」已保证没有组件会读别人的迁移表。**语言内混用才是硬错**——那会让一个外壳的启动器为 22 个模块写两套迁移编排。不用 alembic 的理由是它对我们没价值（零 ORM ⇒ autogenerate 用不上，硬 DDL 只能包在 `op.execute` 里），不是「跨语言不统一」
  - 其中 Python 的 ASGI/WSGI、gRPC 同步/异步、DB 驱动、迁移工具、指标 registry 五格是**物理合不进去**；Gin 那一格是纪律锁（`gin.Engine` 就是个 `http.Handler`，混用能编译）
- **唯一入口**：`backend/module/module.go` 导出 `New(ctx context.Context, rt *besdk.Runtime) (*besdk.Module, error)`（Python：`app/module.py` 的 `async def create_module(rt: Runtime) -> Module`）。`main` 只有一行 `besdk.RunStandalone(module.New)`。**单跑与合并走同一个函数**——这是 §1.5 原则二唯一能被机器守住的形态。
- **模块代码里零 `os.Getenv` / `os.environ`**：依赖地址走 `besdk.Endpoint()`，其余全部配置走 `rt.Config`。一个进程只有一份 `environ`，22 个模块的 `PG_SCHEMA` 与全部 `configSchema` 项会互相顶掉，**不报错**（§12.5.3）。⚠️ 这一条**更正了本文档 SOP-B 的旧版 B-8**。
- **不许碰进程内单例**：`otel.SetTracerProvider` / `logging.basicConfig` / 信号处理器 / **默认 Prometheus registry** / 连接池，全部归调用方。指标一律用 SDK 发的**每模块一个 registry**——用默认全局 registry 时 Go `MustRegister` panic、Python 抛 `Duplicated timeseries`，而单跑 100% 正常。
- **不许 `log.Fatal` / `os.Exit` / `sys.exit`**，一律返回 error 交给调用方。一个模块踩到可恢复的错就退进程，**整组 22 个组件一起没了**。

⚠️ **补记：「精确版本」锁的是不许写范围（`^1.2`），不是必须追最新（决策 119）。** §12.4 锁的是**框架选型**（Gin/FastAPI/sqlc…），不是每个依赖的具体补丁号；具体版本怎么选，判据是：

> **默认贴着「系统已经有的」走；只有某个版本带来确实要用的功能时才升级。**

本项目自己就踩过一次相关的坑：PostgreSQL 一开始选了 `16-alpine`，而本机早就装着 `postgres:15`——事后翻遍设计书也找不出一条「非 16 不可」的理由，纯粹是选的时候没有对照系统现状。⚠️ **但 `be-postgres` 此时已经用 16 跑起来并建过库**，真要切回 15 得走一次 `pg_upgrade` 或 dump/restore（已实测：直接换镜像重建容器会报 `database files are incompatible with server`，v16 的数据目录 v15 读不了）——**为一条事后才想清楚的原则去付一次真实的迁移代价不划算，所以维持 16，只把判据记下来管以后的选择。**

⚠️ **这条不适用于「依赖链本身把版本顶上去了」的情况。** `be-sdk-go` 的 `go.mod` 最终是 `go 1.25`，不是我们主动追新——是 gin/grpc/otel/prometheus/nats.go 的**最新版**都要求 `go >= 1.25`（整个生态过去一年逐步抬高门槛，查了这几个库最近几个版本确认不是个例）。用旧版依赖换回 1.22 没有任何好处，只会损失安全补丁；本机工具链本来就是 1.26，自动匹配、成本为零。**「贴着系统已有的走」在这种情况下就是接受 1.25，而不是倒退去找一套都停在 1.22 的旧依赖。**

判据合起来是一句话：**能自由选的地方，默认最小变动；被动态依赖链逼着走的地方，跟着走，不为了凑一个数字去自锁旧版本。**

---

---

## 第 1 部分 · 基础资源与一键管理（先做这个）

### 1.1 基础资源总清单

基础资源是**非组件的外部服务**，我们不写业务代码，只部署官方镜像。**brickKit 不部署它们，也不做启动前的可达性探测**（`006` §8、§9.1）。全部通过 Docker 部署。

三种形态先分清（§2.7.0），混在一起读会得出「网关是个组件」这种错误结论：

| 形态 | 平台怎么看它 | 怎么声明 | 换实现的动作 |
|---|---|---|---|
| **A** brickKit 基础资源 | 认识它，注入连接变量 | `brickkit.yaml` 的 `resources` | ⚠️ **不是「改一个字段」**，见设计书 §2.7.3.1 |
| **B** 带外容器 | **完全不知道它存在** | 我们自己的 `docker-compose.*.yml` | 改我们那份 compose |
| **C** 组件 | 普通组件 | `brickkit.yaml` 的 `components` | 改装哪一个 |

**Casdoor 和 Traefik 只能是 B**：平台的资源 `kind` 是封闭清单（`database` / `cache` / `mq` / `storage` / `search` / `smtp`），没有 `gateway` 也没有 `iam`（`006` §2.1）；Traefik 还多一条——**平台的 Manifest 没有 volumes 字段**，网关配置文件挂不进去。

#### 1.1.1 默认必须部署（5 个容器，缺一个系统就跑不起来）

| # | 资源 | 形态 | 声明为 | 镜像 | 宿主机端口 | 健康检查 | 数据卷 |
|---|---|---|---|---|---|---|---|
| 1 | **PostgreSQL** | A | `kind: database, engine: postgresql` | `postgres:16-alpine` | 5432 | `pg_isready -h localhost -p 5432` | `pg_data:/var/lib/postgresql/data` |
| 2 | **NATS** | A | `kind: mq, engine: nats` | `nats:2.10-alpine` | 4222, 8222 | `wget -qO- http://localhost:8222/healthz` | `nats_data:/data` |
| 3 | **Traefik** | B | —（带外） | `traefik:v3.0` | 80, 443, **28080** | `traefik healthcheck --ping` | 配置挂载 |
| 4 | **Casdoor** | B | —（带外） | `casbin/casdoor:latest` | 8000 | `curl -f http://localhost:8000/api/health` | 配置挂载 |
| 5 | **RustFS** | A | `kind: storage, engine: s3` | `rustfs/rustfs:latest` | 9000 | `curl -f http://localhost:9000/health/live` | `rustfs_data:/data` |

关键配置要点：

- **PostgreSQL**：`POSTGRES_PASSWORD` 必设；`max_connections=300`（5 个外壳各一个池，足够支撑全量组件）。⚠️ **平台不建库、不建 schema、不建 role**（`006` §9.5）——`brickkit up` 只会**打印**建库语句。实际建置由 `be-ops` 产出脚本、运维执行一次（Task 4）。
- **NATS**：必须 `--jetstream`；`--store_dir /data`；`max_payload=8MB`。
- **Traefik**：启用 Docker Provider（读容器 labels）；`ForwardAuth` 中间件对接 Casdoor；**Dashboard 端口从 8080 挪到 28080**（原因见 §1.2）。
- **Casdoor**：连 PostgreSQL，用自己的 schema `casdoor`；`origin` 配成网关地址。
- **RustFS**：设访问密钥；数据目录挂持久卷。

#### 1.1.2 可选替换件（与默认实现互斥，同一环境只装一个）

| 资源 | 形态 | 镜像 | 替换谁 | 宿主机端口 | 何时用 |
|---|---|---|---|---|---|
| **MinIO** | A | `minio/minio:latest` | RustFS | 9000, 9001 | 客户已有 MinIO 运维经验，或要管理界面。`engine` 两边都是 `s3`，**换实现真正零改动** |
| **Keycloak** | B | `quay.io/keycloak/keycloak:latest` | Casdoor | **28081** | 复杂 LDAP/AD 域，或极细粒度 RBAC/ABAC |
| **Kafka** | A | `confluentinc/cp-kafka:latest` | NATS | **29092** | 每日事件量千万级以上、要流计算。⚠️ 换它要改 ~50 份 `component.yaml` + 换 SDK driver（设计书 §2.7.3.1） |
| **RabbitMQ** | A | `rabbitmq:3.13-management` | NATS | 5672, 15672 | 客户已有 RabbitMQ 基础设施。⚠️ 同上 |
| **Nginx** | B | `nginx:1.25-alpine` | Traefik | 80, 443 | 客户已有 Nginx 运维经验，不要动态服务发现 |

⚠️ 只有 RabbitMQ 才有 `MQ_VHOST`，NATS / Kafka 的资源绑定里**不写这一格**（空值不注入）。

#### 1.1.3 可观测性全家桶（形态 B，要就整套拉起，不要就整套不拉）

| 资源 | 镜像 | 宿主机端口 | 用途 |
|---|---|---|---|
| **OTel Collector** | `otel/opentelemetry-collector-contrib:latest` | 4317, 4318, 13133 | 数据统一收集网关 |
| **Prometheus** | `prom/prometheus:latest` | **29090** | 指标存储后端 |
| **Loki** | `grafana/loki:latest` | 3100 | 日志存储后端 |
| **Tempo** | `grafana/tempo:latest` | 3200 | 链路追踪存储后端 |
| **Grafana** | `grafana/grafana:latest` | 3000 | 可视化展示 |

⚠️ **这五个一个组件都不是**（决策 97）：纯官方镜像 + 必须挂 `config.yaml`，而平台的 Manifest 没有 volumes。可观测性在 `brickkit.yaml` 里**一个字都不写**。

**不拉起时的行为**：组件的 `otelBaseUrl` 留空 → OTel SDK 配 Blackhole Exporter → 数据静默丢弃，系统完美运行，**零成本**。这一档不需要动 `brickkit.yaml` 的任何一行。

#### 1.1.4 明确排除、不要部署（§2.7.4）

| 资源 | 为什么不需要 |
|---|---|
| **Redis** | JWT 无状态（不需要 Session）；本地摘要副本（不需要集中缓存）；PG 行级锁（不需要分布式锁）；Traefik 自带限流。四项用途全覆盖（决策 71） |
| **Consul / etcd** | 路由表生成期聚合（决策 20），不需要运行时服务发现 |
| **Zookeeper** | NATS 不需要；Kafka 3.x 已有 KRaft |
| **Elasticsearch** | 当前无全文检索需求；审计日志走 PG 分区表 |

### 1.2 ⚠️ 端口冲突与修正（已回写设计书）

带外容器的官方默认端口撞了两层东西，**第二层只有读平台代码才能发现**。

**第一层 · 撞我们自己的组件端口。** 外壳必须把端口发布到宿主机（`extra_hosts` 指向 `host-gateway`，§13.1），于是组件端口与带外容器端口活在同一个宿主机端口空间里。

**第二层 · `1xxxx` 整段归平台。** brickKit 给 `local: true` 组件与它们的依赖做宿主机映射时用固定约定（`internal/compose/local.go`）：首选 `10000 + 容器端口`，被占了从 `18080` 起递增扫描。所以我们每个组件端口都对应一个平台会去占的 `1xxxx`：

| 带外容器 | 官方默认 | 撞谁（两层） | 最终 |
|---|---|---|---|
| Traefik Dashboard | 8080 | `mdm-customer` HTTP；且 `18080` 是平台给 8080 的首选映射 | **28080** |
| Keycloak | 8080 | 同上；且 `18081` 是平台给 8081（`mdm-supplier`）的首选映射 | **28081** |
| Prometheus | 9090 | `mdm-customer` gRPC；且 `19090` 是平台给 9090 的首选映射 | **29090** |
| Kafka | 9092 | `mdm-product` gRPC；且 `19092` 是平台给 9092 的首选映射 | **29092** |

⚠️ **`18080` / `18081` / `19090` / `19092` 正是「把官方默认端口挪开」时最自然的落点**——本计划第一版就是这么选的，然后整整四个都撞在平台头上。**结论：带外容器一律用 `2xxxx` 段**，既高于 `10000 + 组件端口` 的上界（组件端口最大 9221 → 19221），也远离 `18080` 起的实际扫描范围。

**连带结论：`be-ops` 的全局端口册（产出 6）必须同时纳入带外容器端口，并把 `1xxxx` 整段标为平台保留。** 只管 62 个组件的端口册发现不了这些，而它们要到第一次把外壳端口发布到宿主机、或第一次给 local 组件做调试映射时才炸——那时 gRPC 端口已经写进 61 份 `component.yaml`、改不动了（§3.5.1.1）。**已回写设计书 §2.7.1、§2.7.2 ③、§2.7.5、附录 G、决策 106。**

**本机现状（2026-09-02 实测）与你的处理方式：**

| 冲突 | 现状 | 与设计书的差 |
|---|---|---|
| :5432 | `my-postgres` 跑 `postgres:15` | ⚠️ **维持 `postgres:16-alpine` 不改**：这条差异本可以对齐（PG16 没有被本设计依赖的任何特性），但 `be-postgres` 已经用 16 跑起来并建过库，切回 15 需要真实的数据迁移（`pg_upgrade`/dump-restore）——版本选择的判据（见 §K 补记）只管**以后新选**版本时怎么定，不要求把已经在跑、已经生效的选择倒回去 |
| :9000-9001 | `my-rustfs` 跑 `rustfs/rustfs:latest` | 镜像对，但不是本项目 compose 管的容器 |
| :6379 | `my-redis` | Redis 是本项目**明确排除**的资源，占着端口无影响 |

**已定决策：`make check` / `make up` 只负责检测并点名报错，绝不 stop / rm 任何非本项目的容器。** 排查与处置由你手动完成。

### 1.3 Makefile 契约

Makefile 放在本仓库根目录，是**基础资源的唯一入口**。设计原则：Makefile 保持很薄，判据落在一张声明式表 `infra/resources.tsv`，检查脚本读它——加一个资源 = 表里加一行 + compose 里加一段，Makefile 不动。

Compose 项目名统一 `be-infra`，所有容器都接同一个 external network `be-net`（§13.8.3 那条铁律：三份 compose 必须挂同一个 external network，否则 Traefik 的 Docker Provider 读不到外壳的路由 labels，症状是网关 404 而容器全 healthy）。

| 目标 | 行为 |
|---|---|
| `make help` | 列出所有目标（默认目标） |
| `make net` | 幂等创建 external network `be-net` |
| **`make check`** | **一键查询**：逐个默认资源查五件事——容器在不在、镜像 tag 对不对、发布端口对不对、健康状态、`be-net` 在不在。端口被非本项目容器/宿主机进程占用时**点名那个容器名或 PID**。表格输出；全绿 exit 0，任一红 exit 1 |
| `make check-all` | 同上，但把已启用的可选资源一起查 |
| **`make up`** | **一键开启所有默认资源**：先跑一遍**整体预检**，全部通过才开始启动（避免半开状态）。已健康且正确的**跳过**；缺的拉起；**存在但镜像/端口不符的直接报错中止，一个字节都不动** |
| `make down` | 停止本项目所有容器（**不删 volume**） |
| `make status` | `docker compose ps` + 健康状态汇总 |
| `make logs SVC=<service>` | 跟一个服务的日志 |
| **`make <res>-up`** | 单个可选资源开启。`res` ∈ `minio` / `keycloak` / `kafka` / `rabbitmq` / `nginx` / `obs`。**开启前做互斥校验**：`minio-up` 时 RustFS 在跑就报错 |
| **`make <res>-down`** | 单个可选资源关闭 |
| `make nuke` | 停止并**删除 volume**。需二次确认（输入 `yes-delete-my-data`） |
| `make db-init` | 执行 `be-ops` 产出的建库脚本（CREATE DATABASE / SCHEMA / ROLE / 授权）。幂等 |
| `make arsenal-check` | 军火库自洽检查（submodule 结构 vs `brickkit.yaml` 的启停判定），见 §3.4 |
| `make arsenal-restore` | 把 submodule 结构还原到与 `brickkit.yaml` 一致，见 §3.4 |

可观测性五件套是**一个整体 profile `obs`**（§2.7.3：要就整套拉起，不要就整套不拉），不提供单独开 Prometheus 的目标。

互斥组（`make <res>-up` 时校验）：

| 互斥组 | 成员 |
|---|---|
| `storage` | `rustfs`（默认）、`minio` |
| `mq` | `nats`（默认）、`kafka`、`rabbitmq` |
| `iam` | `casdoor`（默认）、`keycloak` |
| `gateway` | `traefik`（默认）、`nginx` |

**阶段四**之后再往 Makefile 里加 `make up-all` / `make down-all`，包住 §13.8.3 那三份 compose 的启停链（`brickkit down` 停不了外壳，交付现场一定会出现「以为关干净了，其实外壳还在跑着占着端口」）。那时才有外壳，见**阶段四**。

---

## 第 2 部分 · 三张全局册子

> 这里只放**需要手写初始内容**的三张。另有两张由 `be-ops` 从各组件的 `assembly.yaml` **生成**，
> 现在还没有内容可枚举，规格见 §2.4 产出 9 / 10 与设计书第 14 章：
> `registry/permissions.tsv`（权限键册，**只增不改**，与 `ports.tsv` 同级）、
> `registry/data-scopes.tsv`（数据权限总表，纯派生，可随时重生成）。

### 2.1 全局端口册（`be-ops` 产出 6 的初始内容）

**这张表是 `component.yaml` 里 `deployment.port` 与 `extraPorts` 的唯一来源。gRPC 端口没有事后补救手段，写之前必须回来查。**

分配规则：外壳内序号 `n` → HTTP `基址+n`、gRPC `基址+1000+n`（HTTP 8080 配 gRPC 9090，即 gRPC = HTTP + 1010 的段偏移）。

#### 外壳一 · Go 核心交易与主数据（8 个，HTTP 8080–8087 / gRPC 9090–9097）

| # | 仓库名 | 组件 ID | HTTP | gRPC |
|---|---|---|---|---|
| 1 | `mdm-customer` | `mdm/customer` | 8080 | 9090 |
| 2 | `mdm-supplier` | `mdm/supplier` | 8081 | 9091 |
| 3 | `mdm-product` | `mdm/product` | 8082 | 9092 |
| 4 | `mdm-org` | `mdm/org` | 8083 | 9093 |
| 5 | `erp-sales` | `erp/sales` | 8084 | 9094 |
| 6 | `erp-purchase` | `erp/purchase` | 8085 | 9095 |
| 7 | `erp-inventory` | `erp/inventory` | 8086 | 9096 |
| 8 | `erp-finance` | `erp/finance` | 8087 | 9097 |

（8080 / 8081 / 8084+9094 这三处与设计书 §13.1、§3.5.1 的示例完全一致，其余按同一序推。）

#### 外壳二 · Go 大后方与支撑（16 个，HTTP 8100–8115 / gRPC 9100–9115）

| # | 仓库名 | 组件 ID | HTTP | gRPC |
|---|---|---|---|---|
| 1 | `crm-lead` | `crm/lead` | 8100 | 9100 |
| 2 | `crm-customer` | `crm/customer` | 8101 | 9101 |
| 3 | `crm-opportunity` | `crm/opportunity` | 8102 | 9102 |
| 4 | `crm-activity` | `crm/activity` | 8103 | 9103 |
| 5 | `crm-campaign` | `crm/campaign` | 8104 | 9104 |
| 6 | `crm-case` | `crm/case` | 8105 | 9105 |
| 7 | `hrm-attendance` | `hrm/attendance` | 8106 | 9106 |
| 8 | `hrm-leave` | `hrm/leave` | 8107 | 9107 |
| 9 | `hrm-expense` | `hrm/expense` | 8108 | 9108 |
| 10 | `prj-project` | `prj/project` | 8109 | 9109 |
| 11 | `prj-timesheet` | `prj/timesheet` | 8110 | 9110 |
| 12 | `erp-asset` | `erp/asset` | 8111 | 9111 |
| 13 | `erp-quality` | `erp/quality` | 8112 | 9112 |
| 14 | `erp-maintenance` | `erp/maintenance` | 8113 | 9113 |
| 15 | `hrm-recruitment` | `hrm/recruitment` | 8114 | 9114 |
| 16 | `hrm-appraisal` | `hrm/appraisal` | 8115 | 9115 |

⚠️ **修正 1（已回写设计书 §13.2）**：外壳二原本只列了 14 个，漏了 `hrm-recruitment` 与 `hrm-appraisal`（两个都是 Go、都是常规 CRUD、都是 `reserve`）。它们必须有端口，否则档 4b 做到它们时无处可放。区间已从 8100–8113 扩到 **8100–8115**。

#### 外壳三 · Go 基建与外部通道（22 个，HTTP 8200–8223 / gRPC 9200–9223）

| # | 仓库名 | 组件 ID | HTTP | gRPC |
|---|---|---|---|---|
| 1 | `infra-iam-casdoor` | `infra/iam-casdoor` | 8200 | 9200 |
| 2 | `infra-workflow` | `infra/workflow` | 8201 | 9201 |
| 3 | `infra-notification` | `infra/notification` | 8202 | 9202 |
| 4 | `infra-dlq-monitor` | `infra/dlq-monitor` | 8203 | 9203 |
| 5 | `infra-attachment` | `infra/attachment` | 8204 | 9204 |
| 6 | `infra-storage` | `infra/storage` | 8205 | 9205 |
| 7 | `infra-audit` | `infra/audit` | 8206 | 9206 |
| 8 | `integration-im-dingtalk` | `integration/im-dingtalk` | 8207 | 9207 |
| 9 | `integration-im-wechat-work` | `integration/im-wechat-work` | 8208 | 9208 |
| 10 | `integration-im-feishu` | `integration/im-feishu` | 8209 | 9209 |
| 11 | `integration-im-slack` | `integration/im-slack` | 8210 | 9210 |
| 12 | `integration-im-teams` | `integration/im-teams` | 8211 | 9211 |
| 13 | `integration-payment-stripe` | `integration/payment-stripe` | 8212 | 9212 |
| 14 | `integration-payment-paypal` | `integration/payment-paypal` | 8213 | 9213 |
| 15 | `integration-payment-alipay` | `integration/payment-alipay` | 8214 | 9214 |
| 16 | `integration-payment-wechat-pay` | `integration/payment-wechat-pay` | 8215 | 9215 |
| 17 | `integration-esign-docusign` | `integration/esign-docusign` | 8216 | 9216 |
| 18 | `integration-esign-pandadoc` | `integration/esign-pandadoc` | 8217 | 9217 |
| 19 | `integration-esign-esign` | `integration/esign-esign` | 8218 | 9218 |
| 20 | `integration-email` | `integration/email` | 8219 | 9219 |
| 21 | `integration-sms` | `integration/sms` | 8220 | 9220 |
| 22 | `infra-authz` | `infra/authz` | **8223** | **9223** |

⚠️ **`infra-authz` 取 8223 而不是 8222，也不插在 infra 段中间，两件事都是刻意的。**

① `ports.tsv` 只增不改（§3.5.1.1），8221 已经给了 `infra-iam-keycloak`，所以新组件只能往后取——**不要为了「看起来整齐」去重排已发布的端口**。
② **8222 被跳过，因为那是 NATS 的监控端口**（§1.2 宿主机端口表）。合并部署时外壳三会把 8200–8223 整段发布到宿主机，占 8222 就与 NATS 当场撞车。
⚠️ **这就是端口册必须同时纳入带外容器端口的原因**（决策 99）——只看组件区间 8200–8221 的话，8222 看起来是空的。

⚠️ **修正 2（已回写设计书 §13.2）**：外壳三的组件列表原本写的是「6 个 infra + 15 个 `integration-*`」，但 `integration-edi` 是 Python、在外壳五，所以 integration 只剩 14 个 → 6 + 14 = 20，与它自己写的「21 个」差 1。差的那一个是 **`infra-iam-casdoor` 适配层**——它是 Go、~500 行、没被任何外壳列表收录，但 §9.6.1 档 3 明确说「Go 外壳装 10 个模块」，而档 2 的 13 个里 Go 的正好是 `mdm-customer`/`mdm-product`/`erp-sales`/`erp-inventory`/`erp-finance`/`crm-opportunity`/`infra-iam-casdoor`/`infra-workflow`/`infra-notification`/`integration-im-dingtalk` = 10 个，含它。补上后 21 这个数字就对上了。

⚠️ **修正 2 的后续（阶段二出档复盘发现，2026-09-08）**：`infra-authz` 当时同样漏算了——它和 `infra-iam-casdoor` 一样没被任何外壳列表收录，但确实是 Go、确实在外壳三、上面的端口表（8223/9223）也确实给它留了位置。补上它，档 2/档 3 的 Go 部分是 11 个（不是 10 个），外壳三最终形态是 **8 个 infra + 14 个 integration = 22 个**（不是 21 个）。§9.6.1、§13.2、附录 H 三处已核对过彼此一致（附录 H 的「切片」列本来就打勾了 `infra-authz`，问题只出在 §9.6.1 的数字没跟上）；本节这两条历史修正记录原样保留，不改旧数字——它们记录的是"当时怎么发现、怎么修"的过程，新的漏算走一条新记录，不回去篡改旧的。

#### 外壳四 · Python 复杂大脑（5 个，HTTP 8300–8304 / gRPC 9300–9304）

| # | 仓库名 | 组件 ID | HTTP | gRPC |
|---|---|---|---|---|
| 1 | `hrm-payroll-es` | `hrm/payroll-es` | 8300 | 9300 |
| 2 | `crm-commission` | `crm/commission` | 8301 | 9301 |
| 3 | `erp-manufacturing` | `erp/manufacturing` | 8302 | 9302 |
| 4 | `ana-bi` | `ana/bi` | 8303 | 9303 |
| 5 | `ana-ai` | `ana/ai` | 8304 | 9304 |

#### 外壳五 · Python 渲染与 EDI（2 个，HTTP 8400–8401 / gRPC 9400–9401）

| # | 仓库名 | 组件 ID | HTTP | gRPC |
|---|---|---|---|---|
| 1 | `infra-print` | `infra/print` | 8400 | 9400 |
| 2 | `integration-edi` | `integration/edi` | 8401 | 9401 |

#### 独立容器 · 不进任何外壳（§13.5：跨语言合不进来，Nginx 也合不进来）

| 仓库名 | 组件 ID | 语言 | HTTP | gRPC | 说明 |
|---|---|---|---|---|---|
| `infra-bff-mobile` | `infra/bff-mobile` | TypeScript | 8500 | — | GraphQL over HTTP，不暴露 gRPC |
| `frontend-standard` | `frontend/standard` | TypeScript | 80 | — | Nginx 静态容器 |
| `frontend-advanced` | `frontend/advanced` | TypeScript | 80 | — | 与 standard 同 slot，永不共存 |
| `frontend-{industry}` | `frontend/{industry}` | TypeScript | 80 | — | 同上 |
| `frontend-{customer}` | `frontend/{customer}` | TypeScript | 80 | — | 同上（Fork 件，`metadata.id` 与被 Fork 者一致，见 §3.4.1） |

⚠️ **端口全局唯一的唯一例外是 `slot:frontend` 族**：4 个前端组件都用 80，因为它们是槽位互斥的、永不同时装配，且各自是独立 Nginx 容器不进外壳。这个例外必须写进 `be-ops` 的端口册校验逻辑，否则校验会误报。

#### 槽位替换件与蓝图

| 仓库名 | 组件 ID | HTTP | gRPC | 说明 |
|---|---|---|---|---|
| `infra-iam-keycloak` | `infra/iam-keycloak` | 8221 | 9221 | `slot:iam` 替换件，与 `infra-iam-casdoor` 互斥。虽互斥，仍给独立端口（§3.5.1.1 说的是「全部 62 个组件里两两不重复」） |
| `hrm-payroll-core` | `hrm/payroll-core` | 8305 | 9305 | **blueprint，当前不开发。** 端口预留 |
| `hrm-payroll-cn` | `hrm/payroll-cn` | 8306 | 9306 | **blueprint，当前不开发。** 端口预留 |
| `hrm-payroll-us` | `hrm/payroll-us` | 8307 | 9307 | **blueprint，当前不开发。** 端口预留 |

#### 带外容器与基础资源的宿主机端口（修正后的最终值，已回写设计书）

| 资源 | 宿主机端口 | 默认? | 与设计书附录 G 的差异 |
|---|---|---|---|
| PostgreSQL | 5432 | ✅ | — |
| NATS | 4222, 8222 | ✅ | — |
| Traefik | 80, 443, **28080** | ✅ | Dashboard 8080 → **28080** |
| Casdoor | 8000 | ✅ | — |
| RustFS | 9000 | ✅ | — |
| MinIO | 9000, 9001 | ❌ | — |
| Keycloak | **28081** | ❌ | 8080 → **28081** |
| Kafka | **29092** | ❌ | 9092 → **29092** |
| RabbitMQ | 5672, 15672 | ❌ | — |
| Nginx | 80, 443 | ❌ | — |
| OTel Collector | 4317, 4318, 13133 | ❌ | — |
| Prometheus | **29090** | ❌ | 9090 → **29090** |
| Loki | 3100 | ❌ | — |
| Tempo | 3200 | ❌ | — |
| Grafana | 3000 | ❌ | — |

**已核对：** 上表所有端口与全部组件的 HTTP（8080–8115、8200–8221、8300–8307、8400–8401、8500、80）及 gRPC（9090–9115、9200–9221、9300–9307、9400–9401）两两不撞。

⚠️ **两个平台生成的独立容器要占 `exposePort`（宿主机端口），也必须进端口册：**

| 组件 | 容器内端口 | `exposePort`（宿主机） | 为什么要 expose |
|---|---|---|---|
| `frontend-standard` | 80 | **28090** | 平台生成的 compose 接不进 `be-net`，Traefik 的 Docker Provider 看不见它。只能发布到宿主机，由 Traefik 的 **file provider** 指过来（决策 107） |
| `infra-bff-mobile` | 8500 | **28500** | 同上 |

⚠️ **`1xxxx` 整段是平台保留，端口册里不许分配。** brickKit 给 `local: true` 组件及其依赖做宿主机映射时首选 `10000 + 容器端口`、fallback 从 `18080` 起递增（`internal/compose/local.go`）。我们的组件端口最大 9221，所以平台实际会用到 **18080–19221**。带外容器一律走 `2xxxx`（§1.2、决策 106）。

### 2.2 全局 Schema / Role 册（`be-ops` 产出 2 的初始内容）

命名规则（无例外）：

| 对象 | 规则 | 例 |
|---|---|---|
| Database | 全系统唯一一个 | `brickkit_db` |
| 组件 schema | 仓库名 `-` → `_` | `mdm-customer` → `mdm_customer` |
| 组件归档 schema | `{schema}_archive` | `mdm_customer_archive` |
| 组件 PG Role | `{schema}_rw` | `mdm_customer_rw` |
| 外壳登录角色 | `shell_{外壳标识}` | `shell_go_core` |

⚠️ **组件 Role 只用于 `SET LOCAL ROLE` 切换，从不用于登录**，因此**不出现在 `brickkit.yaml` 里**（§13.3 铁律二）。`brickkit.yaml` 的 `resources` 里只有 5 个外壳登录角色（同一个 host、不同凭据）。

五个外壳登录角色：

| 外壳 | 登录角色 | 覆盖的组件 schema |
|---|---|---|
| 外壳一 Go-Core | `shell_go_core` | 外壳一那 8 个 |
| 外壳二 Go-Backoffice | `shell_go_backoffice` | 外壳二那 16 个 |
| 外壳三 Go-Infra | `shell_go_infra` | 外壳三那 22 个（含 `infra_authz`；+ `infra_iam_keycloak` 若换槽） |
| 外壳四 Py-Brain | `shell_py_brain` | 外壳四那 5 个 |
| 外壳五 Py-Render | `shell_py_render` | 外壳五那 2 个 |

另外两个非组件 schema：`casdoor`（Casdoor 官方镜像自用）、`keycloak`（换槽时用）。

`infra-bff-mobile` **不建 schema**——它严禁直连 DB（§6.5）。`frontend-*` 同理。

### 2.3 组件总表（62 个，一个不漏）

图例：**阶段** = 它在第几阶段开工（对照 §5.1）。**语言**照设计书 §12.1。**外壳**照 §2.1 端口册。

#### infra 基础域（11 个）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 阶段 |
|---|---|---|---|---|---|---|---|
| 1 | `infra-iam-casdoor` | `slot:iam` (Default) | Go | 三 | 8200/9200 | `infra_iam_casdoor` | **阶段三** |
| 2 | `infra-iam-keycloak` | `slot:iam` (替换件) | Go | 三 | 8221/9221 | `infra_iam_keycloak` | 阶段六 |
| 3 | `infra-bff-mobile` | default | TypeScript | 独立 | 8500/— | 无（禁直连 DB） | **阶段三** |
| 4 | `infra-workflow` | default | Go | 三 | 8201/9201 | `infra_workflow` | **阶段三** |
| 5 | `infra-notification` | default | Go | 三 | 8202/9202 | `infra_notification` | **阶段三** |
| 6 | `infra-attachment` | default | Go | 三 | 8204/9204 | `infra_attachment` | **阶段五** |
| 7 | `infra-storage` | default | Go | 三 | 8205/9205 | `infra_storage` | **阶段五** |
| 8 | `infra-print` | default | **Python** | 五 | 8400/9400 | `infra_print` | **阶段三** |
| 9 | `infra-audit` | reserve | Go | 三 | 8206/9206 | `infra_audit` | 阶段六 |
| 10 | `infra-dlq-monitor` | default | Go | 三 | 8203/9203 | `infra_dlq_monitor` | **阶段五** |
| 11 | `infra-authz` | default | Go | 三 | 8223/9223 | `infra_authz` | **阶段三** |

#### integration 域（15 个）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 阶段 |
|---|---|---|---|---|---|---|---|
| 11 | `integration-im-dingtalk` | `channel:im` | Go | 三 | 8207/9207 | `integration_im_dingtalk` | **阶段三** |
| 12 | `integration-im-wechat-work` | `channel:im` | Go | 三 | 8208/9208 | `integration_im_wechat_work` | 阶段六 |
| 13 | `integration-im-feishu` | `channel:im` | Go | 三 | 8209/9209 | `integration_im_feishu` | 阶段六 |
| 14 | `integration-im-slack` | `channel:im` | Go | 三 | 8210/9210 | `integration_im_slack` | 阶段六 |
| 15 | `integration-im-teams` | `channel:im` | Go | 三 | 8211/9211 | `integration_im_teams` | 阶段六 |
| 16 | `integration-payment-stripe` | `channel:payment` | Go | 三 | 8212/9212 | `integration_payment_stripe` | 阶段六 |
| 17 | `integration-payment-paypal` | `channel:payment` | Go | 三 | 8213/9213 | `integration_payment_paypal` | 阶段六 |
| 18 | `integration-payment-alipay` | `channel:payment` | Go | 三 | 8214/9214 | `integration_payment_alipay` | 阶段六 |
| 19 | `integration-payment-wechat-pay` | `channel:payment` | Go | 三 | 8215/9215 | `integration_payment_wechat_pay` | 阶段六 |
| 20 | `integration-esign-docusign` | `channel:esign` | Go | 三 | 8216/9216 | `integration_esign_docusign` | 阶段六 |
| 21 | `integration-esign-pandadoc` | `channel:esign` | Go | 三 | 8217/9217 | `integration_esign_pandadoc` | 阶段六 |
| 22 | `integration-esign-esign` | `channel:esign` | Go | 三 | 8218/9218 | `integration_esign_esign` | 阶段六 |
| 23 | `integration-email` | `channel:email` | Go | 三 | 8219/9219 | `integration_email` | 阶段六 |
| 24 | `integration-sms` | `channel:sms` | Go | 三 | 8220/9220 | `integration_sms` | 阶段六 |
| 25 | `integration-edi` | reserve | **Python** | 五 | 8401/9401 | `integration_edi` | 阶段六 |

#### mdm 主数据域（4 个，只读枢纽）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 阶段 |
|---|---|---|---|---|---|---|---|
| 26 | `mdm-customer` | default | Go | 一 | 8080/9090 | `mdm_customer` | **阶段一** |
| 27 | `mdm-supplier` | default | Go | 一 | 8081/9091 | `mdm_supplier` | **阶段五** |
| 28 | `mdm-product` | default | Go | 一 | 8082/9092 | `mdm_product` | **阶段二** |
| 29 | `mdm-org` | default | Go | 一 | 8083/9093 | `mdm_org` | **阶段五** |

#### crm 客户关系域（7 个，灵活容忍）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 阶段 |
|---|---|---|---|---|---|---|---|
| 30 | `crm-lead` | optional | Go | 二 | 8100/9100 | `crm_lead` | 阶段六 |
| 31 | `crm-customer` | optional | Go | 二 | 8101/9101 | `crm_customer` | 阶段六 |
| 32 | `crm-opportunity` | optional | Go | 二 | 8102/9102 | `crm_opportunity` | **阶段三** |
| 33 | `crm-activity` | optional | Go | 二 | 8103/9103 | `crm_activity` | 阶段六 |
| 34 | `crm-campaign` | optional | Go | 二 | 8104/9104 | `crm_campaign` | 阶段六 |
| 35 | `crm-case` | optional | Go | 二 | 8105/9105 | `crm_case` | 阶段六 |
| 36 | `crm-commission` | reserve | **Python** | 四 | 8301/9301 | `crm_commission` | 阶段六 |

#### erp 企业资源域（8 个，严谨强一致）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 阶段 |
|---|---|---|---|---|---|---|---|
| 37 | `erp-sales` | optional | Go | 一 | 8084/9094 | `erp_sales` | **阶段二** |
| 38 | `erp-purchase` | optional | Go | 一 | 8085/9095 | `erp_purchase` | 阶段六 |
| 39 | `erp-inventory` | optional | Go | 一 | 8086/9096 | `erp_inventory` | **阶段二** |
| 40 | `erp-finance` | optional | Go | 一 | 8087/9097 | `erp_finance` | **阶段二** |
| 41 | `erp-manufacturing` | optional | **Python** | 四 | 8302/9302 | `erp_manufacturing` | 阶段六 |
| 42 | `erp-asset` | optional | Go | 二 | 8111/9111 | `erp_asset` | 阶段六 |
| 43 | `erp-quality` | optional | Go | 二 | 8112/9112 | `erp_quality` | 阶段六 |
| 44 | `erp-maintenance` | optional | Go | 二 | 8113/9113 | `erp_maintenance` | 阶段六 |

#### hrm 人力资源域（9 个，含 3 个 blueprint）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 阶段 |
|---|---|---|---|---|---|---|---|
| 45 | `hrm-attendance` | optional | Go | 二 | 8106/9106 | `hrm_attendance` | 阶段六 |
| 46 | `hrm-leave` | optional | Go | 二 | 8107/9107 | `hrm_leave` | 阶段六 |
| 47 | `hrm-expense` | optional | Go | 二 | 8108/9108 | `hrm_expense` | 阶段六 |
| 48 | `hrm-recruitment` | reserve | Go | 二 | 8114/9114 | `hrm_recruitment` | 阶段六 |
| 49 | `hrm-appraisal` | reserve | Go | 二 | 8115/9115 | `hrm_appraisal` | 阶段六 |
| 50 | `hrm-payroll-core` | **blueprint** | Python | 四 | 8305/9305 | `hrm_payroll_core` | **不开发** |
| 51 | `hrm-payroll-cn` | **blueprint** | Python | 四 | 8306/9306 | `hrm_payroll_cn` | **不开发** |
| 52 | `hrm-payroll-us` | **blueprint** | Python | 四 | 8307/9307 | `hrm_payroll_us` | **不开发** |
| 53 | `hrm-payroll-es` | `slot:payroll` optional | **Python** | 四 | 8300/9300 | `hrm_payroll_es` | 阶段六 |

⚠️ `hrm-payroll-es` **内嵌薪资引擎功能**（薪资项字典、算薪周期、工资单数据结构），**不依赖** `hrm-payroll-core`（决策 64）。

#### prj 项目管理域（2 个）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 阶段 |
|---|---|---|---|---|---|---|---|
| 54 | `prj-project` | optional | Go | 二 | 8109/9109 | `prj_project` | 阶段六 |
| 55 | `prj-timesheet` | optional | Go | 二 | 8110/9110 | `prj_timesheet` | 阶段六 |

#### ana 数据分析域（2 个，储备）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 阶段 |
|---|---|---|---|---|---|---|---|
| 56 | `ana-bi` | reserve | **Python** | 四 | 8303/9303 | `ana_bi` | 阶段六 |
| 57 | `ana-ai` | reserve | **Python** | 四 | 8304/9304 | `ana_ai` | 阶段六 |

#### frontend 前端域（4 个）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP | schema | 阶段 |
|---|---|---|---|---|---|---|---|
| 58 | `frontend-standard` | `slot:frontend` (Default) | TypeScript (Vue3 + Uni-app) | 独立 | 80 | 无 | **阶段三** |
| 59 | `frontend-advanced` | `slot:frontend` (替换件) | TypeScript | 独立 | 80 | 无 | 🔜 未来 |
| 60 | `frontend-{industry}` | `slot:frontend` (替换件) | TypeScript | 独立 | 80 | 无 | 🔜 未来 |
| 61 | `frontend-{customer}` | `customer_fork` `slot:frontend` | TypeScript | 独立 | 80 | 无 | 📋 按需 Fork |

#### 非组件资产仓库（不在 62 里）

| 仓库名 | 用途 | 阶段 |
|---|---|---|
| `brickKit` | 平台本身（已存在） | — |
| `be-assembly-standard` | 产品根 / 标准装配模板 / 军火库索引（**本仓库**，已存在） | — |
| **`be-ops`** | **必需（交付关键路径）** 装配生成器，11 个产出，见 §2.4 | **阶段一** |
| **`be-acceptance`** | **必需（交付关键路径）** 验收测试：20 条平台验收 + 业务闭环 + 拆回门禁 + import 扫描 | **阶段一** |
| `be-shell-go` | Go 外壳启动器（我们自己适配，不进 `components/`） | **阶段四** |
| `be-shell-python` | Python 外壳启动器（同上） | **阶段四** |
| **`be-sdk-go`** | **必需（交付关键路径）** Go 横切基础库，SOP-L 十四项能力 | **阶段一** |
| **`be-sdk-python`** | **必需** Python 横切基础库 | **阶段三** |
| **`be-sdk-ts`** | **必需** TS 横切基础库（只有一半：无 `withTx` / 无冷热路由，多 GraphQL 限制） | **阶段三** |
| `be-assembly-{customer}` | 客户后端装配清单 | 首个客户时 |

**统计核对**：62 = infra 11 + integration 15 + mdm 4 + crm 7 + erp 8 + hrm 9 + prj 2 + ana 2 + frontend 4 ✓
需构建 59（62 − 3 个 blueprint）；其中**阶段一~三**做 14 个、**阶段五**做 5 个、**阶段六**做 37 个（= 44 剩余 − 3 blueprint − 3 未来/按需前端）✓

### 2.4 `be-ops` 的 11 个产出（决策 89 / 93、115–118）

平台刻意不做、而活不会消失的那些，全在这里。`be-ops` **不是 brickKit 组件**（不进 `brickkit.yaml`），是我们自己的命令行工具，读全部组件的 `assembly.yaml` 产出：

| # | 产出 | 替代了平台的什么 | 哪个阶段做 |
|---|---|---|---|
| 1 | **网关路由表（三个出口）**：进外壳的组件 → shell-compose 的 service `labels`（Traefik Docker Provider）；**平台生成的独立容器 → Traefik file provider 动态配置，指向 `http://<宿主机>:<exposePort>`**；K8s → 带外 Ingress 清单 | 平台不做 path 路由（§6.3）；**且平台生成的 compose 接不进 `be-net`，Docker Provider 看不见那些容器**（决策 107） | **阶段三** |
| 2 | **数据库建置脚本**：`CREATE DATABASE` + 每组件 `CREATE SCHEMA` / `{schema}_archive` / `CREATE ROLE` / 授权 + 5 个外壳登录角色 | 平台只打印建库语句（§2.7.2） | **阶段一** |
| 2b | **`resources` 的 `bindings`**：每个声明了资源依赖的组件都要有一条 `componentId`；合并态下是 **5 条 PostgreSQL 条目**（同 host、5 个外壳登录角色）各带自己那组 bindings | **声明了资源依赖却没绑定，`up` 直接阻断**（`006` §4.4）。62 个组件手写必然漏 | **阶段一**（随产出 5） |
| 3 | **Feature 清单**：装配结果 → 写进 IAM 适配层的 `config.enabledComponents`（**逗号分隔字符串**） | 平台不给组件「当前装配了什么」的视图（§6.1） | **阶段三** |
| 4 | **外壳合并配置**：哪些组件进哪个外壳、端口分配、迁移执行顺序。**生成对象是每个组件的 `module.New`**（§K / 设计书 §12.5.1）——没有那个统一入口，这一项没有东西可生成 | 平台不提供合并部署支持（§13.6） | **阶段四** |
| 5 | **`brickkit.yaml` 生成**：含 `assembly.yaml` 的 schema 校验、`slot` 互斥校验、`channel` 多选校验 | 平台没有装配角色的概念（§3.3） | **阶段一** |
| 6 | **全局端口册**：62 个组件的 HTTP + gRPC 两两不重复 **+ 带外容器端口**（已回写设计书，见 §7） | 平台只在 `local: true` 撞车时报错（§3.5.1.1） | **阶段一** |
| 7 | **每外壳的环境变量表**：同外壳依赖 → `http://127.0.0.1:<端口>`；**跨外壳/独立容器 → `http://<宿主机地址>:<端口>`** | **平台只往它自己生成的容器里注入，合并后那些容器不存在**（§13.8） | **阶段四** |
| 8 | **shell-compose 的 `depends_on`**：外壳之间的启动顺序 | 平台只排它生成的那些（§13.8） | **阶段四** |
| **9** | **权限键册**：聚合 62 份 `assembly.yaml` 的 `permissions` 段 → `registry/permissions.tsv`（`key / title / type / owner_component / deprecated`），并喂进 `infra-authz` 的 `config.permissionCatalog`（**逗号分隔字符串**）。校验三条：`menus[].permission` 必须在本组件清单里、**键前缀必须等于本组件 domain**、全局不重复 | 平台没有权限概念；而 iam/authz 要「分配权限」就得先知道有哪些键——这条链的第一环只能由我们生成（设计书 §14.1.2） | **阶段一**（先建空表 + 校验）／**阶段三**（喂 authz） |
| **10** | **数据权限总表**：扫描 62 份 `assembly.yaml` 的 `data_scopes` 段 → `registry/data-scopes.tsv`。⚠️ **没写这一段就报错**——不需要的组件必须显式写 `data_scopes: none` | 交付验收与客户安全评审要「一张全系统数据权限总表」，否则只能一个组件一个组件巡查；而「省略」若等于「无」，漏配就是静默泄露（设计书 §14.2.2） | **阶段一** |
| **11** | **`authzBundleUrl` 注入**：把 `infra-authz` 的地址填进每个组件 `configSchema` 的 `authzBundleUrl`（随产出 5 / 7） | 业务组件对 authz **不声明依赖**（同 §6.1 的 `iamJwksUrl`），所以地址只能由我们填 | **阶段三** |

**三条生成器铁律（必须写进 `be-ops` 的实现与测试）：**

1. **`labels` 的值必须是字符串。** Docker labels 与 K8s annotations 两边都只收字符串，平台**不做自动转换**。布尔与数字一律带引号产出：`"true"` / `"8080"`。
   ⚠️ **另有三组键归平台所有，写了当场报错**：`brickkit.io/*`、`com.docker.compose.*`、`app`。我们产出的 `prometheus.io/*` 与 `traefik.http.*` 安全，但生成器要显式拦住那三组（设计书 §5.10）。
2. **没买的组件要从 `brickkit.yaml` 里整条删掉，不能写 `enabled: false`。** 条目不存在 → 强依赖方解析期报错、弱依赖方警告后继续且不注入 `*_ENDPOINT`；`enabled: false` → 它不启动且**它下面那一串跟着不启动**（级联）。把「没买」写成 `enabled: false` 会把下游主数据一起关掉。
3. **聚合型组件的依赖必须全部 `optional: true`。** `infra-bff-mobile` 要对各业务组件调 `batchGet`、`infra-notification` 要调各 channel 适配器，依赖清单会长到几十条。**一条写成强依赖，客户没买那个组件时整个 BFF 起不来。**

---

## 第 3 部分 · 仓库拓扑与 submodule 军火库索引

### 3.1 目录结构

```
be-assembly-standard/                    ← 本仓库 = 产品根 + 军火库索引
├── BrickEnterprise 设计书.md            ← 规范真相源
├── brickkit.yaml                        ← 装配清单（真相源之二，§9.1）
├── Makefile                             ← 基础资源唯一入口（第 1 部分）
├── AGENTS.md / CLAUDE.md
├── docs/
│   ├── README.md                        ← 按读者分诊，人的总入口
│   ├── ops/部署手册.md                  ← 部署人员唯一需要的一份
│   ├── standards/00-master-guide.md                ← 本文件
│   └── design/<仓库名>.md               ← 组件设计计划，一个组件一份
├── infra/                               ← 三份 compose 的第 1 份 + 检查脚本
│   ├── resources.tsv                    ← 声明式资源表（判据真相源）
│   ├── docker-compose.infra.yml         ← 默认 5 个 + 可选替换件（profiles）
│   ├── docker-compose.observability.yml ← 可观测性 5 件套（profile: obs）
│   ├── traefik/traefik.yml
│   ├── casdoor/conf/app.conf
│   └── scripts/
│       ├── check.sh                     ← make check 的实现
│       ├── up.sh                        ← make up 的实现（含整体预检）
│       ├── optional.sh                  ← make <res>-up/down 的实现（含互斥校验）
│       └── arsenal.sh                   ← make arsenal-check/restore 的实现
├── components/                          ← 【已从 .gitignore 移除】每个组件一个 submodule
│   ├── mdm/customer/                    → git@github.com:brickKit/mdm-customer.git
│   ├── mdm/product/                     → git@github.com:brickKit/mdm-product.git
│   ├── erp/sales/                       → git@github.com:brickKit/erp-sales.git
│   ├── ...                              （照 §2.3 总表，档位到了才 add）
│   └── .archived/                       ← brickkit sync 的归档区（仍在 .gitignore）
├── shells/                              ← 外壳，不进 components/
│   ├── go/                              → git@github.com:brickKit/be-shell-go.git
│   └── python/                          → git@github.com:brickKit/be-shell-python.git
├── tools/
│   ├── be-ops/                          → git@github.com:brickKit/be-ops.git
│   ├── be-acceptance/                   → git@github.com:brickKit/be-acceptance.git
│   ├── be-sdk-go/                       → git@github.com:brickKit/be-sdk-go.git
│   ├── be-sdk-python/                   → git@github.com:brickKit/be-sdk-python.git   （阶段三才 add）
│   └── be-sdk-ts/                       → git@github.com:brickKit/be-sdk-ts.git       （阶段三才 add）
└── .gitmodules                          ← 「组件 → 仓库 → 精确 commit」映射表
```

### 3.2 为什么用 submodule，以及它是怎么满足设计书的

设计书 §3.4.1 要求：「**主管理员维护的「客户 → 组件仓库」映射表是唯一真相源，不是可选项。** 半年后接手的人，只有这张表能告诉他这个客户的 `erp/sales@1.0.0` 到底是哪一份代码。」

`.gitmodules` **就是这张表**，而且比手写表强三点：git 原生维护、带精确 commit SHA、`git clone --recurse-submodules` 一条命令全量恢复。

**为什么不用 `brickkit add --repo`：** 它靠的是**市场登记的 Git 地址**（`publish --git-url`，默认取组件目录的 `origin`），而设计书 §9.4.1 明确我们走「全本地源、无市场分发」的交付模型。没有市场，`--repo` 就没有 URL 可用。等哪天要上市场分发，再把 `--repo` 作为 submodule 的补充手段（两者不冲突：submodule 记的是同一个 URL）。

**目录路径与仓库名不同名，这是正常的：** 平台约定源码目录是 `components/<scope>/<name>`（`003` §116），而仓库名是扁平的 `mdm-customer`（§5.0）。`.gitmodules` 里两边都记着。

### 3.3 ⚠️ submodule 与 `brickkit sync` 的摩擦（必须建立纪律）

`brickkit sync` 把这次不启动的组件源码**整目录连 `.git` 一起** `os.Rename` 进 `components/.archived/`（`004` §3.9）。在本仓库的视角里，这是「gitlink 从 A 路径消失、B 路径多出个未跟踪目录」。

这正是 brickKit 正在补的那个功能要拦的失误。brickKit 仓库里已确认的设计（`docs/superpowers/specs/2026-09-02-commit-gate-restore-design.md`）会提供：

- **`brickkit restore`** —— 节点级只改 `enabled` 字段，把 yaml 与目录结构一次还原到与最后一次提交一致
- **`brickkit restore --check`** —— 判据：**这次提交里 yaml 与目录结构自洽吗**。读 index（`git show :<配置文件>` + `git ls-files --cached --stage`），主判据是「yaml 说该跑、而结构在归档区」→ 硬拦 exit 1
- **`brickkit init --hooks`** —— 装 `pre-commit` hook（用 `git rev-parse --git-path hooks` 定位，正确处理 worktree / submodule / `core.hooksPath`）

**⚠️ 当前装的 CLI 里还没有 `restore` 命令**（实测 `brickkit restore` 报「未知命令」）。所以：

| 时期 | 用什么 |
|---|---|
| **现在** | 本仓库自带的 `make arsenal-check` / `make arsenal-restore` + 我们自己的 `pre-commit` hook（同判据，见 Task 5） |
| **`brickkit restore` 上线后** | 改用 `brickkit init --hooks`，**删掉我们那份**，避免两套判据分叉 |

**开发纪律（三条，不许省）：**

1. 本地为了聚焦，给顶层写 `enabled: false` + `brickkit sync` 归档 —— **允许且鼓励**（这正是你说的用法）。
2. **提交前必须先把 `enabled` 还原、再跑一次 `sync` 把结构复原。** `make arsenal-restore` 一条命令做完这两件。
3. `pre-commit` hook 在你忘了第 2 条时硬拦，并把出路印出来。

⚠️ **另外两条运维禁令（§9.4.2），在 submodule 结构下更致命：**

- **`brickkit remove` 会连同已归档的源码目录一起删除。** submodule 目录里有未 push 的改动时，这是**数据丢失**。执行 `remove` 前必须确认目录干净（先 commit & push）。
- **`components/.archived/` 以 `.` 开头，文件管理器默认隐藏。** 找不到源码时先看这里。

### 3.4 `make arsenal-check` / `arsenal-restore` 的判据

与 brickKit 那份设计的判据保持一致（等官方版上线就换掉，所以刻意抄同一张状态表）：

| `brickkit.yaml` 的启停判定 | 结构在哪 | 行为 |
|---|---|---|
| 该跑 | 活跃（`components/<scope>/<name>`） | 放行 |
| 该跑 | **归档（`components/.archived/...`）** | **拦**（唯一主判据，就是那个失误） |
| 该跑 | **两处都有** | **拦**（违反「一个组件 ID 只有一个源码目录」） |
| 该跑 | 都没有 | 放行（源码没进仓库，管不着） |
| 不该跑 | 活跃 | 放行（只是没跑过 sync，允许） |
| 不该跑 | 归档 | 放行（`enabled: false` 一起进了提交 = 意图声明） |
| 不该跑 | **两处都有** | **拦** |
| 不该跑 | 都没有 | 放行 |
| yaml 里没声明 | 任意 | **一律放行**（判定算不到它） |

短路条件（保持零成本）：`git ls-files --cached --stage -- components/` 返回空 → 立刻 exit 0。

### 3.5 仓库创建检查点的标准动作

每个检查点，执行者按顺序做完这三步：

**步骤 A（检查点之前，执行者自己做）**：建好目录与初始文件，但**不 `git init`**。

**步骤 B（检查点，停下等你）**：输出下面这段话术，列出目录与仓库名，然后**停下**：

```
⏸ 检查点：需要你手动创建 Git 仓库

我已经把以下目录和初始文件建好了：
  <目录列表>

请在 github.com/brickKit/ 下创建这些仓库（空仓库，不要 README / .gitignore / license，
否则第一次 push 会因为历史分叉而被拒）：
  <仓库名列表>

建好之后回我一句「建好了」，我会：
  1. 在每个组件目录里 git init + 首次 commit + 设 remote + push
  2. 回到本仓库 git submodule add 把它们接进来
  3. 继续下一个任务
```

**步骤 C（你回「建好了」之后，执行者做）**：对每个组件目录跑：

```bash
# 以 mdm-customer 为例
cd components/mdm/customer
git init -b main
git add -A
git commit -m "chore: 组件骨架（component.yaml / assembly.yaml / contracts / migrations / Makefile / Dockerfile）"
git remote add origin git@github.com:brickKit/mdm-customer.git
git push -u origin main
cd -

# 回本仓库接成 submodule
git submodule add git@github.com:brickKit/mdm-customer.git components/mdm/customer
git add .gitmodules components/mdm/customer
git commit -m "chore: 军火库接入 mdm-customer"
git push
```

⚠️ **`git submodule add` 要求目标路径不是已有 git 仓库以外的东西。** 因为步骤 C 里那个目录已经是个 git 仓库且已 push，`submodule add` 会直接把它登记为 gitlink 而不重新 clone——这是想要的行为。若报「already exists in the index」，先 `git rm -r --cached components/mdm/customer` 再 add。

#### 3.5.1 全部要你手动建的仓库，和会在什么时候叫你

**8 个非组件仓库**（组件仓库 62 个，按档位到了才建，见 §2.3）。**顺序不许提前**：每一个都必须先有「步骤 A 的文件」才建仓库——**空仓库先建出来会闲置好几个月，而闲置的仓库只会积累一份过期的 README**。

| 仓库名 | 目录 | 什么时候叫你建 | 里面是什么 |
|---|---|---|---|
| `be-assembly-standard` | 本仓库 | 已存在 | 产品根 + 军火库索引 |
| `be-ops` | `tools/be-ops/` | **CP-1**（阶段一 Task 6） | 装配生成器，8 个产出（§2.4） |
| `be-acceptance` | `tools/be-acceptance/` | **CP-1** | 20 条平台验收 + 业务闭环 + 拆回门禁 + import 扫描 |
| `be-sdk-go` | `tools/be-sdk-go/` | **CP-1** | SOP-L 十四项横切能力 + `Runtime`/`Module`/`RunStandalone`/`NewGinEngine`（§K） |
| `mdm-customer` | `components/mdm/customer/` | **CP-2**（阶段一 Task 11） | 第一块砖 |
| `be-sdk-python` | `tools/be-sdk-python/` | **阶段三**（第一个 Python 组件之前） | 与 `be-sdk-go` **一一对应**的 Python 版 |
| `be-sdk-ts` | `tools/be-sdk-ts/` | **阶段三** | 只有一半：无 `withTx`、无冷热路由，多 GraphQL 深度限制（§5.10） |
| `be-shell-go` | `shells/go/` | **阶段四** | 外壳启动器：挂 `module.New`、跑迁移、`Listen`、持有进程内单例（§12.5） |
| `be-shell-python` | `shells/python/` | **阶段四** | 同上，Python 版 |

⚠️ **`be-sdk-python` 必须晚于 `be-sdk-go`，这不是排期问题而是设计问题。** 两份 SDK 的公开 API 要**一一对应**（同名、同参数顺序、同语义），否则同一个人在两种语言之间切换时每次都要重新学一遍，而 AI 会把 Go 那边的写法直接套到 Python 上。**先把 Go 版写实、被真组件用过一轮**，再照着它做 Python 版——反过来做，两边一定分叉。

⚠️ **不要为了「以后可能共享」提前建仓库。** 判据只有一条：**现在有没有已经写好、正等着 push 的文件**。没有就不建——`.gitmodules` 是设计书 §3.4.1 要的那张「组件 → 仓库 → 精确 commit」映射表，往里塞一条指向空仓库的 gitlink，会让半年后接手的人以为那里有东西。

---

## 第 4 部分 · 组件开发标准流程（SOP）

七套 SOP。**先读 SOP-W——它是驱动其余各套的节奏**：

| SOP | 管什么 | 什么时候读 |
|---|---|---|
| **SOP-W** | **AI 驱动的开发循环**：七步循环、测试分四层、红绿节奏、一次会话装多少、卡住怎么办、人类审查看哪五样 | **开工前先读这个** |
| **SOP-D** | 每个组件的四份文档（设计计划 / README / 手册 / AGENTS.md） | 第 1 份在动手之前 |
| **SOP-R** | 参考现实 ERP 的三步法 + 各域该看哪个项目 | 设计与实现之间 |
| **SOP-B / SOP-F** | 后端 / 前端组件的 14 步产出清单 | 主线 |
| **SOP-P** | 要不要用设计模式（判据按 AI 能不能快速看懂来定） | 写实现之前判一次 |
| **SOP-L** | 语言基础库的十四项横切能力 | 每种语言只做一次 |

第 5 部分起，每个组件任务只写它自己的**参数与差异**，流程一律引用本节。**本节写一次，全项目 58 个组件通用。**

### SOP-W · AI 驱动的开发循环（**驱动 SOP-B/F 的节奏，先读这个**）

SOP-B / SOP-F 说的是「一个组件要产出哪 14 样东西」。**SOP-W 说的是「怎么一步步把它们做出来」**——一次会话做多少、测试分几层、什么时候提交、AI 卡住了怎么办。

**这一套是为「AI 写、人审」这个组合设计的**，两个约束推出了它的形状：

| 约束 | 推出什么 |
|---|---|
| AI 每次会话都是全新的、上下文有限 | 任务要切到「一次会话能装下」；每次会话开头要有固定的读文件清单 |
| 人不可能逐行读 58 个组件的实现 | 人只审**不可逆**的东西（契约、迁移、不变量清单），其余靠门禁；所以门禁必须真的能拦住东西 |

#### W-1 · 七步循环（一个组件走一遍）

```
① 设计业务逻辑        docs/design/<仓库名>.md          ← 01-documentation-standard.md §4.1
② 查参考实现          先自己设计 → 理不清才去读        ← SOP-R 的三步法
③ 契约                contracts/*.proto + events/*.json  ← 设计的可执行形式
④ 写业务规则测试       不变量 / 状态机迁移表 / 属性测试   ← ⚠️ 在实现之前，测的是规格
⑤ 实现                红 → 绿 → 重构，一个规则一轮       ← 每轮一次 commit
⑥ 补单元测试          边界、错误路径、并发               ← 实现之后，测的是这个实现
⑦ 集成 + 门禁 + 文档   真 PG / 真 NATS / grpcurl / make all
```

⚠️ **③ 在 ④ 之前、④ 在 ⑤ 之前，这两个顺序都不能反。**

- 契约先于测试：测试要 import 契约生成的类型，没契约就只能测 map[string]any，那种测试重构一次就废
- 测试先于实现：**这是「规格」与「实现」的分界线**。先写实现再补测试，写出来的一定是「描述现有实现的测试」——它能防回归，但防不住「实现从一开始就理解错了需求」

#### W-2 · 测试分四层（详见 [`04-testing-standard.md`](04-testing-standard.md) §三）

测试分 L1 契约 / L2 业务规则（规格，实现之前写，重构时一个字都不该改）/ L3 单元（这一版实现的分支）/ L4 集成（真 PG/NATS/gRPC）四层，核心交易组件的 L2 必须用属性测试，禁止用 mock 测"跨组件调用发生了"。**完整的分层判据、示例代码、消费者测试私有 subject 判据，见 [`04-testing-standard.md`](04-testing-standard.md) 的 §三。**

#### W-3 · 红-绿-重构的节奏（详见 [`04-testing-standard.md`](04-testing-standard.md) §二）

一次会话做一个"红-绿-重构"循环，一个循环一次 commit；**最重要的禁令是不许为了让测试通过而改测试**——实现不对就改实现（默认都是这一种），测试真的写错了要单独一次 commit 说明原断言错在哪，L2 测试挡路几乎一定是实现或理解错了。**完整的六步节奏与"改测试 vs 改实现"判据表，见 [`04-testing-standard.md`](04-testing-standard.md) 的 §二。**

#### W-4 · 一次会话装多少（完整判据见 [`03-ai-development-standard.md`](03-ai-development-standard.md) §二）

会话/红绿循环/commit 三个单位的大小判据、新会话开头该固定读哪几样、不必读什么——跟具体业务领域无关，通用于任何组件，统一写在 [`03-ai-development-standard.md`](03-ai-development-standard.md) 的 §二，不在总纲重复。

#### W-5 · AI 卡住时的三条出路（详见 [`04-testing-standard.md`](04-testing-standard.md) §2.4）

"卡住"（同一个红绿循环三轮还不绿）按顺序试：① 把这一步切小 ② 去看参考实现（SOP-R 的第二步，读完自己想清楚再写，不要照抄）③ 停下来说清卡在哪，交给人判断——**绝不许绕过去**（不许注掉测试/加 `t.Skip`/放宽断言）。**完整说明见 [`04-testing-standard.md`](04-testing-standard.md) 的 §2.4。**

#### W-6 · 人类审查只看这五样（判据本身见 [`03-ai-development-standard.md`](03-ai-development-standard.md) §三）

"为什么只审这五样、为什么不需要逐行审业务代码"的完整判据跟具体业务领域无关，统一写在 [`03-ai-development-standard.md`](03-ai-development-standard.md) 的 §三。这里只留这五样在本项目里具体落在哪：

| # | 审什么 | 本项目具体落点 |
|---|---|---|
| 1 | 契约 | `contracts/`。契约一旦有消费者，就只能向后兼容地追加（决策 19、§3.4 铁律 3） |
| 2 | 迁移 | `migrations/`。分区键、主键、索引在建表时定死；数据进去之后改就是一次迁移（§11.2） |
| 3 | 不变量清单 | L2 业务规则测试里的不变量清单是否列全 |
| 4 | 设计文档的边界/依赖 | `docs/design/*.md` 的第 1 节（边界）与第 5 节（依赖）——边界画错、或多建了一条同步边，是唯一会污染整张架构图的错误（§4.2 同步图必须无环、CRM↔ERP 零同步边） |
| 5 | 门禁输出 | `make all` 的 8 个 ✓ |

#### W-7 · 种子数据与跨组件测试分组（完整规范见 [`05-data-construction-standard.md`](05-data-construction-standard.md) 与 [`04-testing-standard.md`](04-testing-standard.md)）

种子数据（`make seed`，给人探索/演示用）与自动化测试数据两条路径的完整策略——归属、丰富度判据、`db-reset` vs `seed-clean`、跨组件协作、安全边界——统一写在 [`05-data-construction-standard.md`](05-data-construction-standard.md)，不在总纲重复。跨组件测试分组见 [`04-testing-standard.md`](04-testing-standard.md) 的 §四。下面只留这个模式在本项目里被真机验证过的历史记录。

✅ **样板已验证**（`mdm-customer`/`mdm-product@1.0.4`）：两个都是依赖链叶子（零强依赖），是这个模式最简单的样板——`make -C components/mdm/customer seed` 单独跑通，5 个客户覆盖 `ACTIVE`/`DISABLED` 两种状态 + 一条联系人；`mdm-product` 同理覆盖三种 `TrackingType`。真机验证过幂等（连跑 id 不变）、精确清理（`seed-clean` 后 0 残留）。根 `infra/seed-data/seed.sh` 改成调用这两个组件自己的 `make seed`，不再重复实现。⚠️ 两条实现中修正的判据（原文写得过于理想化）：
  - **根编排的"顺序不敏感"不成立**——库存/商机这些下游步骤需要客户/产品的真实 id，编排脚本必须先跑完 `make seed` 再往下走，不是"随便顺序调用"。真正不敏感的只是`seed`目标之间彼此不互相依赖这件事本身（都是幂等的，谁先跑都行），不是"编排脚本可以乱序调用"。
  - **组件自己的 `seed.sh` 和需要用到产出 id 的编排脚本之间，用组件自己的 `command_idempotency` 表当"交接协议"**——组件的 `seed` 只管把数据灌进去，不负责把 id 打印成任何约定格式；谁需要这些 id，自己反查 `SET search_path TO <schema>; SELECT result_id FROM command_idempotency WHERE idempotency_key = '<固定key>'`（`psql -tA -q` 拿干净输出，**漏了 `-q` 会把 `SET` 的命令回执也混进变量里**，是实现时真的踩过的坑）。
  - ✅ 身份类种子数据（`infra/iam-casdoor`+`infra/authz` 链式调用）这条判据已验证：两个组件各自补了 `seed`/`seed-clean`，`infra-authz` 独立向 Casdoor 查询 `infra-iam-casdoor` 建的测试用户的 `sub`（不吃对方传参，同强依赖链式调用一样各自单独跑都通）。旁路发现一个真实 Casdoor API 不对称 bug：`delete-application` 只传 `{owner,name}` 会返回 `status:ok data:"Unaffected"`（看起来成功，其实没删），必须先 `get-application` 拿完整对象再整个传回去；`delete-user` 反而只要 `{owner,name}` 就行。
  - ✅ **真实强依赖链式调用这条判据也已验证**（`crm-opportunity@1.0.5`）：对 `mdm-customer`/`mdm-product` 是真正的强依赖（`component.yaml` 纯字符串声明，`CreateOpportunity` 真的走 gRPC `BatchGet` 校验），`Makefile` 的 `seed` 目标链式调用它们 + 身份类例外，单独 `make -C components/crm/opportunity seed` 能拿到完整数据（5 条商机覆盖全部状态）。⚠️ 单独跑时 WON 商机触发的自动建单会因为 `erp-inventory` 没有库存走 `erp-sales` 真实的 TCC 补偿建异常待办——这是**设计上正确的行为**（`crm-opportunity` 不依赖 `erp-inventory`，`product_id` 对后者是不透明外键，给真实产品灌库存这件事没有单一归属，留在编排层），不是回归；"库存先备好、订单真正 `CONFIRMED`"这个完整演示效果由编排脚本 `infra/seed-data/seed.sh` 按正确顺序（客户产品→库存→商机）保证。旁路发现两个真实 bug（记入踩坑记录 C18/C19）：`brickkit.yaml` 里 13 个组件的 `authzBundleUrl`/`iamJwksUrl` 手写字面量在 `infra-authz`/`infra-iam-casdoor` 升版本时漏改了全部 25 处引用（`dependency-version-scan` 门禁查不出这类漂移，它不扫 `config` 段的手写字符串）；Casdoor 的测试应用被真实登录一次后 `get-application` 响应带非法 JSON 控制字符，`json.load` 要加 `strict=False`。
  - ✅ **零依赖组件"自成一体 + 弱连接探测"这条判据已验证**（`erp-inventory@1.0.9`）：本组件明确不依赖 `mdm-product`（`product_id` 是不透明外键），`make seed` 因此分两步——① 始终生成自己造 id 的完整演示数据（两仓库 + 入库/出库/盘盈/盘亏/在途预留，`dependencies.components` 为空也能独立跑通）；② 反查 `mdm-product` 的 `command_idempotency` 表探测它的种子数据是否存在，存在就顺手给那几个真实 product id 也灌库存——不建立正式依赖边，纯 dev tooling 层面"能连就顺手连"，取代了原来留在 `infra/seed-data` 编排层的裸 SQL 步骤。这条也是本节新增的"delete 不是 reset"判据的第一个真实样板：本组件没有 `seed-clean`（`inventory_movements` 只增不改），只有 `make db-reset`，真机验证过 `migrate down` 再 `up` 后 balances/movements 归零、`warehouses` 的 `BIGSERIAL` 序列真的从 1 重新开始，容器不重启也能正常继续服务。旁路发现两个真实 bug：Receive/Adjust 虽然也在 gRPC 接口里声明，但 service 层固定调 `besdk.ScopeOf(ctx)`，而 Claims 只有 REST 那层 `besdk.RequirePermission` 中间件会塞——直接 grpcurl 调这两个方法必然 panic（同 C11 的既有判据，seed 脚本改走 REST + 真实 Bearer token 解决）；grpcurl 用 protojson 默认编排 JSON，带下划线的 proto 字段（`reservation_id`）会变成驼峰（`reservationId`），跟 REST 手写 JSON 不是同一套命名（记入踩坑记录 C20）。**更重要的一个发现**：`003_seed_warehouses.down.sql` 的 `DELETE` 在 `migrate down` 倒序执行时会撞上 `inventory_balances` 的外键——这条路径本仓库历史上从未被真机跑过（`migrate-idempotent` 门禁只测 up），`make db-reset` 第一次真跑就复现，已修复（记入踩坑记录 C21）。`infra/seed-data/seed.sh` 的库存步骤已改成调用本组件自己的 `make seed`。⚠️ **第三个发现，比前两个更能说明问题**：真机走了两轮完整的 `make seed-data-clean`→`make seed-data`（验证"reset/clean 循环稳不稳"这件事本身）后，第二轮的 WON 商机意外又走了补偿路径——根因是探测式关联那一步的 `idempotency_key` 当时固定按位置编号（`seed-inv-recv-real-$i`），`mdm-product` 被 `seed-clean` 后产品 id 必然变新，但本组件没有 `seed-clean`（`command_idempotency` 不会跟着清），claim-first 幂等让固定 key 永远绑死"第一轮"那个已经不存在的旧 id，新 id 静默拿不到库存。改成 `idempotency_key` 带上真实解析出来的产品 id（`seed-inv-recv-real-$PID`）后，id 一变自然是全新的 key，问题消失（记入踩坑记录 C22）。**这条本身印证了本节新增的判据**：种子脚本反查一个"数据会随 clean/reseed 轮换 id"的组件时，链接动作的幂等键必须包含被链接对象的真实 id，不能用序号这类跟 id 无关的固定值。
  - ✅ **"delete 不是 reset"判据的第二个真实样板，且换了一种更强的理由**（`erp-finance@1.0.6`）：本组件从零设计 `make seed`——5 张 `PostManualEntry` 人工凭证（覆盖 5 个科目 + 单行/四行多行 + 一张真做过 `ReverseEntry` 的待冲销样例）+ 会计期间三态生命周期演示（`close→lock` 终态、`close→reopen` 往返、只 `close`）+ `legal_entity_access` 授权 `dev.superuser`/`dev.finance.viewer`（同 `erp-inventory` 的 `warehouse_access` 判据）。本组件不是靠"流水表只增不改"这条既有理由拒绝 `seed-clean`，而是有一条更硬的理由：`LockPeriod` 是这份契约里**唯一的终态**——一旦某个期间被锁定，`ClosePeriod`/`ReopenPeriod`/`LockPeriod` 三个 rpc 里没有任何一个能把它转回去，逐行 `DELETE` 从物理上就不可能干净复原被锁定的期间状态。真机验证过 `make db-reset`：`entries`/`ar_ledger`/`legal_entity_access` 全部归零，12 个会计期间全部回到默认 `OPEN`，`entry_no_seq` 序列真的从 1 重新开始。旁路复现并**提前修复**了 C21 那类 down 迁移倒序执行撞外键的坑：`003_seed_accounts_and_periods.down.sql` 的 `DELETE` 会在 `migrate down` 执行到它时撞上还没被删的 `finance_journal_entries`——这次是照着 C21 的教训在真机跑 `migrate down` **之前**、单纯审阅 down 文件执行顺序时就推理出来并提前改成空文件，修完后再真机验证一次成功，记入踩坑记录 C23。⚠️ 额外发现（不是 bug，是环境状态）：`PostManualEntry`/`ReverseEntry` 不接受调用方指定业务日期，凭证一律落进"运行脚本这一刻"所在的会计期间——种子脚本原计划挑 2026-01/02/03 三个月演示期间三态，真机一跑发现这几个月早就被 Task 6 实现期间的人工验证留下了 `LOCKED`/`CLOSED` 的真实历史状态（早于本脚本、也早于测试库/演示库分离），改用确认过是 `OPEN` 的 2026-04/05/07 三个月，不管数据库处于哪种历史状态都不会跟别的期间操作打架。
  - ✅ **`crm-opportunity` 重做，"下游可以、也应该倒逼上游丰富数据"这条判据第一次真实触发**（`crm-opportunity@1.0.6`）：商机从 5 条加量到 10 条——`seed-opp-1..5` 原样保留（`dev.superuser` 建，只增不改），新增 `seed-opp-6..10` 改用 `dev.sales.east`（华东分部）的真实 JWT 去调 `CreateOpportunity`/`MarkWon`/`MarkLost`（`dept_id`/`dept_path`/`owner_id` 是创建时从调用者 `besdk.ScopeOf(ctx)` 快照的，必须真的换这个身份的 token 去调，不能建完再补写归属字段）。真机验证：用 `dev.sales.east` 的 token 拉 `ListOpportunities`，只看到 `seed-opp-6..10` 五条，`seed-opp-1..5`（`dev.superuser` 名下，无部门归属）一条都看不到——"华东销售看不到别的部门商机"这条 org 维数据权限边界第一次有真实商机样本可以登录体验，不只是纯自动化测试里才存在。`seed-opp-9` 是第二个 `WON` 商机（华东身份赢单），验证了"赢单转订单、归属跟着走"这条判据不只在 `dev.superuser` 名下成立：`erp-sales` 生成的订单 `owner_id`/`dept_path` 正确带着华东部门路径。同时也补上了时间跨度（`seed-opp-6..10` 回填成"最近 2-25 天内逐步推进"的样子，用 `now() - interval` 写绝对值而不是 `created_at - interval`，重跑不会越跑越早，同 `mdm-customer`/`erp-finance` 已验证过的判据）。⚠️ **过程中真机复现了一次"下游倒逼上游"的真实场景**（不是设计讨论）：`seed-opp-9` 首次真机跑时订单卡在 `DRAFT`、`infra-workflow` 真的出现一条异常待办——根因是 `erp-inventory` 探测 `mdm-product` 种子数据那一步的循环范围还停留在旧版"只有 5 个产品"时代的 `1 2 3 4`，`mdm-product` 这一轮已经扩到 12 个，`seed-opp-9` 选用的第 7 号产品落在探测范围之外，`Reserve` 找不到余额只能走 TCC 补偿——这是完全正确的既有设计路径，只是这次不是故意演示补偿，是真的想要一条干净成交订单。把 `erp-inventory/scripts/seed.sh` 的探测范围改成 `1 2 3 4 5 6 7 8 9 10 11 12`（覆盖 `mdm-product` 当前全部种子产品）后，`seed-clean` 撤销半途卡住的商机/订单、重新 `seed` 一遍，两条 `WON` 商机（`dev.superuser`/`dev.sales.east`）都拿到了干净的 `CONFIRMED` 订单，记入踩坑记录 C24。最后把 `infra/seed-data/clean.sh` 里原来"按种子客户 id 反查所有订单一并清掉"那段清理逻辑挪进了本组件自己的 `scripts/seed-clean.sh`（反查本组件自己种的 `WON` 商机 id → 反查 `erp_sales.command_idempotency` 的 `crm-won:<opportunity_id>` 键拿到真实订单 id → 精确删除，比原来的客户 id 模糊扫更精确）——这是删掉 `infra/seed-data/` 的前提条件之一，已完成；真机验证过整个 `make seed-data-clean`→`make seed-data` 从零跑一遍，两条 `WON` 商机的订单清理/重建全部正确。⚠️ **顺带解决了 `infra-workflow` 的种子数据判断**：这个组件的 `CreateTask`/`CloseTask`/`CancelTask` 明确不暴露 REST（proto 顶部注释直接点名"人能创建待办只有一种可能'人代表某个业务组件创建'，那等于给了一条绕过业务规则的路"）——种子脚本直接 grpcurl 伪造一条 `CreateTask` 正是这条设计禁令想挡住的事，不该为了"造点数据"就绕开组件自己的架构安全边界。正确做法是新增第 11 条商机 `seed-opp-11`：用信用额度仅 ¥5000 的 `mdm-customer` 低信用样例客户（`mdm-customer` 自己 seed 时特意留的）下一张 qty=100（真实定价引擎按 GLOBAL 规则算出的单价乘出来约 ¥10000，远超额度——⚠️ 实测踩坑：`erp-sales` 的定价引擎不认商机行的 `quoted_unit_price`，是真的查 `pricelist_items` 重算，qty 太小根本凑不出超额度的订单，第一次试跑 qty=10 时订单只有 ¥1000 完全没触发信用校验）的 `WON` 商机，赢单后 `erp-sales` 真实拒绝确认（订单卡 `DRAFT`），`createOpportunityExceptionTask` 真实建一条 `infra-workflow` 异常待办，`assignee_sub`/`assignee_dept_path` 正确带着华东归属——`infra-workflow` 因此不需要自己的 `make seed`，也有一条真实的、org/owner 维归属正确的异常待办可看，这是"用真实业务失败路径产生负向数据，而不是直接灌库伪造"这条新判据的第一个样板。

#### W-8 · 扩展测试范畴（详见 [`04-testing-standard.md`](04-testing-standard.md) §五）

权限/数据权限边界测试、事件契约破坏性变更检测、跨组件测试局部化三项已转正并接进 `make gates`/`make test-cross`；前端视觉回归移交 SOP-F 的 FE-4；SDK 并发正确性测试首例已验证可行（`be-sdk-go`），其余语言待补。**完整说明见 [`04-testing-standard.md`](04-testing-standard.md) 的 §五。**

#### W-9 · 三种运行粒度（详见 [`04-testing-standard.md`](04-testing-standard.md) §7.1）

全量 / 组件完整 / 组件内子集三种粒度，后端前端通用，只是命令不同（`make gates`/`pnpm test`、`make test`/`pnpm --filter`、`go test -run`/`vitest <pattern>`）。**完整对照表见 [`04-testing-standard.md`](04-testing-standard.md) 的 §7.1。**

#### W-10 · 允许整体重写，不只是增量打补丁（完整判据与流程见 [`03-ai-development-standard.md`](03-ai-development-standard.md) §四）

什么时候该整体重写而不是打补丁、具体流程怎么走——跟具体业务领域无关，统一写在 [`03-ai-development-standard.md`](03-ai-development-standard.md) 的 §四，不在总纲重复。

✅ **已验证的样板**：种子数据丰富度整改那一批（`00-master-guide.md` W-7 段落链到的历史记录）就是"种子数据类判据可以更松"这条规则的真实落地——给某个组件"加数据"大多不是在现有 `seed.sh` 后面追加几行，而是把整份 `seed.sh` 按新判据重新设计一遍，这是预期中的正常工作方式，不是"没控制好改动范围"。

#### W-11 · 传播一次版本升级：机械化，不靠人肉满仓库找（工具：`be-acceptance bump-version`）

**这条要解决的问题**：本项目自己定的规矩是**每一个改动**——哪怕是零行为/契约变更的纯文档修复或纯补测试——都要跳自己的版本号（本节整体的节奏；"为什么版本号和镜像必须绑在一起走，而不只是'为什么要跳版本号'"这条更深的理由见下文）。但一个组件的版本号一动，从来不会只影响它自己：每一个在 `dependencies.components` 里引用了它的别的组件，那一条引用也要跟着改（意味着那个组件自己也要跟着跳版本号，可能继续往下传）；根 `brickkit.yaml` 顶层 `components[].version` 那个 pin 要跟着改；根 `AGENTS.md`/`docs/zh/AGENTS.md` 的组件名录表要跟着改；如果这次跳版本号的恰好是 `infra/authz` 或 `infra/iam-casdoor`，全项目每一个别的组件 `config:` 段里手写的 `authzBundleUrl`/`iamJwksUrl` 字面量（里面嵌着旧版本号拼出来的主机名）也要跟着改（踩坑记录 C18——曾经一次性漏改过全部 25 处，因为压根没有东西在替人盯着这件事）。这些全靠人一处一处 grep、一处一处手改，正是这个项目自己早就有名字的那类事情——"能机制化的判据必须机制化"（04-testing-standard.md §1）——只是这次要机制化的不是"检查"，是"传播"本身，此前一直没做只是因为"传播一处改动"跟"侦测一处漂移"是两种不同形状的活。

**工具**：`tools/be-acceptance` 的 `bump-version` 子命令（`versionbump` 包，接进了 `make gates` 本来就在编译的同一个 `be-acceptance` 二进制里）。

```
be-acceptance bump-version --root . --plan <计划文件>            # 只算、只打印，不写盘
be-acceptance bump-version --root . --plan <计划文件> --apply    # 真的写盘
```

计划文件里只需要写**真的动了什么**的那些组件（真代码、真测试、真文档）——因为依赖它们而只需要同步版本号引用的下游组件，工具会自己顺着反向依赖图走到不动点，自动算出来：

```
id: erp/inventory
reason: 补 TestProperty_库存三大不变式，无行为/契约变更。
---
id: erp/finance
reason: 补 TestProperty_借贷不平衡的分录被拒绝且不落库，无行为/契约变更。
```

（`version: 1.1.0` 是每块可选的第三个字段，给那种真的需要跳到某个明确目标版本、而不是走默认"当前版本 patch 位加一"的少见情形用。）

跑上面这两条变更，不会只跳这两个组件——它会自动找到 `erp-sales`（同时依赖两者）、再找到 `infra-bff-mobile`（依赖 `erp-sales`），给每一个都算好各自的下一个 patch 版本号，自动生成对应的变更记录（"因为跟着谁一起走"这类模板句，跟那两条真实改动手写的理由分开），并且把每一处该改的文件全部改好：每个被牵连组件自己的 `component.yaml`（`metadata.version`、`deployment.image` 的 tag，以及——如果它是下游——自己 `dependencies.components` 段里那些 `id@版本号` 引用）、根 `brickkit.yaml` 的 pin、两份 `AGENTS.md` 名录表。

⚠️ **这个工具刻意不做的事**：`git commit`/`tag`/`make image`/`push`。批量改文件是安全、可审查、git 可撤销的操作；把一个打好标签、重建过的镜像推到好几个各自独立的组件仓库，正是这个项目一贯认为需要有人/AI 在场把关的那类"对外可见、难以撤销"的动作（真机验证、`make gates`、看一眼 diff）——把这一步也塞进同一次调用里，是拿一段真实的安全边际去换一点点方便，不划算。所以流程刻意保持两阶段：

1. **先把整批都算完，一次性 apply。** 如果这次会话的工作同时动了好几个组件（一个功能横跨多个组件是常态），就写**一份**计划文件把这批真实改动全部列进去，跑**一次** `bump-version`——不要每做完一个组件就单独跑一次。这才是真正省掉"来回改"这部分成本的地方：所有文件在一次 pass 里就落到最终版本号，不会出现"这个组件的依赖引用先改成 X，几分钟后因为另一个兄弟组件也变了，又要再改一次"的情况。
2. **按工具打印的顺序逐个组件收尾**（打印顺序是"根变更在前，牵连出来的在后"，纯粹是给人看的可读性——文件层面的版本号在第 1 步就已经全部定下来了，收尾这几步谁先谁后不影响结果）。对每一个：看一眼 diff、跑这个组件自己的测试/`make gates`、`git commit` + `git tag -a` + `make image`、`git push`（commit 和 tag 都推）。全部做完后提交装配仓库自己的改动（`brickkit.yaml`、两份 `AGENTS.md`、重新生成的 `.brickkit/manifests`），真机跑一遍 `brickkit up` 验证、`brickkit down`、推送。

**为什么纯文档/纯测试改动还是要跳版本号，而不是只跳"仓库版本"、把 `metadata.version`/镜像放着不动**：这个问题被直接提出来过——既然跳版本号+重建在这个项目里完全是本地、免费的操作（`make image` 是本地构建，秒级，不涉及任何远程 Registry，见全局约束 §J），"每个改动都跳版本号"这条规矩本来唯一的真实代价，就是**把它传播到各处的人力**——而这正是这个工具刚刚消掉的那部分。把 git tag 跟 `metadata.version`/镜像内容解耦，并不会再省下什么（自动化已经把那部分省掉了），却会重新打开一个这个项目真实踩过的坑：`component.yaml` 会被 `COPY` 进**镜像本身**，所以镜像内部携带的版本号必须跟它外部的 tag 一致——这正是踩坑记录 C5；它的反面（版本号跳了，镜像却没跟着重建，`brickkit up` 悄悄复用本地的旧镜像）就是 C13。"这次只是改测试，跳过重建"这种例外，重新打开的正是那道判断题——而本文档自己在 W-2 早就说过，"这个改动是不是真的不影响行为"恰恰是那种偶尔会判断错的事，这正是要有 L2 测试、而不是"作者当时觉得应该没问题"的理由。保留这条不变式（版本号、git tag、镜像内容三者永远一致），把体力活交给工具去扛。

---

### SOP-B · 后端组件（Go / Python）

每个后端组件仓库的文件结构（§8.3）：

```
<repo>/
├── component.yaml            # 平台读的那份。字段名一个字都不能自创
├── assembly.yaml             # 只有 be-ops 读。平台永不解析
├── contracts/
│   ├── <name>.proto          # gRPC 契约
│   ├── <name>.openapi.yaml   # HTTP 契约（对外 REST）
│   └── events/
│       └── <name>.events.json # 事件 Schema
├── backend/                  # 业务代码
│   ├── module/module.go      # ⭐ 唯一入口 New(ctx, rt)。外壳与 main 都只认这一个（§K）
│   ├── cmd/server/main.go    # 只有一行 besdk.RunStandalone(module.New)
│   ├── internal/...
│   └── ...
├── migrations/
│   ├── 001_<...>.up.sql      # 裸 SQL。Go 用 golang-migrate，Python 用 yoyo，两边都是裸 .sql
│   └── 001_<...>.down.sql
├── Dockerfile                # 基底必须带 /bin/sh + wget
├── Makefile                  # §I 那 9 个门禁目标
└── README.md
```

Python 组件的对应位置是 `backend/app/module.py`（`create_module`）与 `backend/app/main.py`（一行 `besdk.run_standalone(create_module)`）。

⚠️ **阶段三 Task 3 补记**：Go 版 `backend/internal/http`、`backend/internal/grpc` 在 Python 侧的对应目录是 **`backend/app/http`、`backend/app/grpc`**——这两个目录名此前一直没有文档化（`infra-print` 是本项目第一个 Python 组件，Task 3 写 `make gates` 的 Python 版扫描时才补上），现在钉死：REST handler 放 `backend/app/http/`，gRPC handler 放 `backend/app/grpc/`。这两个目录同时是 `SystemClient` 误用扫描（§14.2.6）与裸路由扫描（§14.1.7）的危险目录，判据同 Go 版，只是 Python 没有 `go/ast` 可用，退化成逐行正则（精度上限见 `tools/be-acceptance/gates/bareginscan.go`/`systemclientscan.go` 的代码注释）。

TS 侧的 `infra-bff-mobile`（GraphQL BFF，不进外壳，见 §12.4.3）同样补一条约定：**resolver map 一律放在 `src/resolvers/` 下，这个目录不放别的东西**。这既是 `SystemClient` 误用扫描的危险目录，也是裸 resolver 扫描（判据：resolver 字段的值必须经过 `requirePermission(perm, resolver)` 包一层，不能直接是箭头函数/`function`）的扫描范围——`docs/design/infra-bff-mobile.md` 待决问题 #1 就此了结。

**15 个步骤，顺序不能改**（TDD：契约先行、测试先写）：

- [ ] **B-0 抄技术栈，不许自选**：对照全局约束 §K / 设计书 §12.4 那张锁定表，把本组件的语言那一列逐格抄进骨架的依赖清单。**这一步花两分钟，省的是「做外壳那天发现某个组件用了 Flask」**——那时改的是已经写完的实现

- [ ] **B-1 建仓库骨架目录与文件**（不 `git init`，等检查点）。**同时写 SOP-D 的第 2、4 份文档**（`README.md` 七节、`AGENTS.md` 六节 + `CLAUDE.md`）；第 1 份设计计划在本 SOP 之前就该有了
- [ ] **B-1.5 走一遍 SOP-R**：把设计计划第 8 节「参考实现」里列的模块真的读一遍，再动手写契约。**这一步不许跳**——凭空设计出来的领域模型漏掉的边界情形，要到客户上线三个月后才暴露
- [ ] **B-2 写 `contracts/`**：`.proto` + `events/*.events.json`（+ 对外 REST 组件写 `.openapi.yaml`）。
      每个聚合根**必须**提供 `batchGet`（§3.8，BFF 层防 N+1 的唯一合法调用方式）。
      跨组件写接口**必须**带 `idempotency_key`，且**必须**提供 `GetStatus`（§4.5 薛定谔的超时）。
- [ ] **B-3 写 `component.yaml`**：端口从 §2.1 端口册抄，`pgSchema` 默认值从 §2.2 抄。检查全局约束 B / C / E / F。
- [ ] **B-4 写 `assembly.yaml`**：`asset` / `domain` / `tier` / `edge_routes` / `menus` / `data.schema` / `data.role` / `shell`。
- [ ] **B-5 写迁移**：分区表在 migration 里建（决策 51）；强制字段（§G）；分区表主键含分区键；**迁移状态表落本组件 schema**。
- [ ] **B-6 写失败测试**（先写测试，再写实现）：**按 SOP-W 的 W-2 分层**——这一步写的是 **L2 业务规则测试**（不变量、状态机迁移边、幂等），L3 单元测试留到 B-9 之后补。覆盖：`/healthz`、每个 gRPC rpc、`batchGet`、Outbox 落库、消费幂等。
      核心交易组件（`erp-inventory` / `hrm-payroll-es` / `erp-finance`）**必须**引入基于属性的测试（Go 用 `rapid` / `gopter`，Python 用 `hypothesis`），由人类定义不变量（如「库存总数不能为负」），框架生成随机边界输入攻击 AI 生成的代码（§8.0、决策 49）。
- [ ] **B-7 跑测试确认全红**（没红就是测试没写对）
- [ ] **B-8 写最小实现**：实现 `module.New`，把 HTTP handler（Gin engine）与 `RegisterGRPC` 交回去，**由调用方 `Listen`**——单跑时是 `besdk.RunStandalone`，合并时是外壳（§K、设计书 §12.5.1）；代码里零硬编码地址；依赖地址走 `besdk.Endpoint()`（它剥 scheme），**其余全部配置走 `rt.Config`，模块代码里零 `os.Getenv`**（§12.5.3）；**不碰进程内单例、不 `log.Fatal`**（§12.5.2）。**写之前对照 SOP-P 判一次要不要用设计模式**——`erp-sales` 的定价、`erp-finance` 的凭证翻译、`infra-notification` 的通道路由这几处已经定了要用（SOP-P 的 P-2 表）。
- [ ] **B-9 跑测试确认全绿**，然后**补 L3 单元测试**（边界、错误路径、并发、SQL 拼得对不对）。⚠️ L3 与 L2 的分界：把实现删掉用另一种语言重写，这条测试还该成立吗——该 → L2，不该 → L3（W-2）
- [ ] **B-10 写 `Dockerfile`**：基底 `alpine`（Go）/ `python:3.11-slim`（Python），装 `wget`，以及本语言的迁移工具（Go：`golang-migrate`；Python：`pip install yoyo-migrations`，§K）；`make image` 后 `docker run --rm <img> sh -c 'wget --version'` 必须成功。
- [ ] **B-11 写 `Makefile`**：§I 那 9 个门禁目标全部实现。
- [ ] **B-12 跑 9 个门禁全绿**（第 9 条 `make module-check` 守铁律七）
- [ ] **B-13 单独 `brickkit up` 起来并跑六项验收**（见 [`01-阶段一`](../../plans/01-阶段一-地基与第一块砖.md) §2 那张六项验收表。**每加一个组件都要重跑**，§9.6.1 档 4）
- [ ] **B-14 commit + push + 打 tag `v<version>`**（tag 必须与 `component.yaml` 的 `version` 一致，§9.1）

### SOP-F · 前端组件（TypeScript）

前端组件仓库结构（§2.3）：

```
frontend-standard/
├── component.yaml            # port: 80，deployment.type: container（平台里没有 static 类型）
├── assembly.yaml             # assembly_role: slot, slot_name: frontend
├── apps/
│   ├── pc-web/               # Vue3 SPA
│   │   └── src/{modules,layouts,router,App.vue}
│   │       # layouts/ 装 §12.6.7 的骨架：服务选择器 / 收藏栏 / 标签页 / ⌘K
│   │       #          / 组织切换器 / 组件内扁平侧栏
│   └── mobile/               # Uni-app
│       └── {pages,manifest.json}
├── packages/
│   ├── shared-types/         # 由契约生成
│   ├── api-client/           # 由契约生成
│   ├── design-tokens/        # ⭐ 两端唯一共享的 UI 资产。纯数据、零框架 import：
│   │                         #    主色/色阶规则/间距/字号/行高/圆角（§12.6.1.1）
│   ├── ui-kit-pc/            # ⭐ PC 侧第三方组件的唯一出口（AntDV + vxe-table）
│   │                         #    ① AntDV token → vxe CSS 变量（主题一处真相源）
│   │                         #    ② AntDV 控件注册成 vxe 的单元格渲染器
│   │                         #    ③ 导出 <BeTable>，页面不许直接用 <vxe-grid>
│   │                         #    ④ 页面级模板 <BeListPage>/<BeDetailPage>/
│   │                         #      <BeFormPage>/<BeSettingsPage>（§12.6.7）
│   ├── ui-kit-mobile/        # ⭐ 移动端第三方组件的唯一出口（wot-design-uni）
│   ├── shell/                # ⭐ 应用骨架（§12.6.7）：服务选择器 / 收藏栏 /
│   │                         #    应用内标签页 / ⌘K 命令面板 / 组织切换器
│   └── feature-flags/        # 动态特性路由
├── docker/Dockerfile         # 构建产物打包为 Nginx 镜像
├── Makefile
└── README.md
```

**前端铁律（§5.9 / §6.4 / §12.6 / 决策 75）：**

1. **严禁硬编码核心商业逻辑**：算钱、扣库存、核心状态机流转一律在后端。
2. **全权接管表单交互逻辑**：正则校验、字段联动显隐、防抖节流、本地草稿缓存（断网保护）。拒绝「为了一个字段显隐去调后端接口」。
3. **Dry-Run 模式**：复杂联动（如按客户等级 + 产品实时算预估总价）必须**防抖调用后端的 `DryRun` / `Validate` 接口**取结果，不得在前端复写后端计算公式。
4. **严禁手写 `fetch('/api/sales')`**，必须用 `packages/api-client` 里由契约生成的 SDK（§3.9）。
5. **可见路由 = `features ∩ permissions ∩ 登录态`，三层缺一不可**（设计书 §14.1.8）。层 1 `GET /api/tenant/features` 是**装配级**（这个环境装了没有），层 2 `GET /api/me/permissions` 是**用户级**（这个人能不能）。按钮走 `v-be-auth="'erp.sales.approve'"`（出自 `ui-kit-pc`）。
    ⚠️ **只判 feature 不判 permission 的症状是「菜单看得见、点进去整页 403」**——旧版把这两件事混着说了。
    ⚠️ **前端可见性从来不是安全边界**（决策 8）：用户改本地代码一定能让隐藏菜单显示出来并路由过去，那时他看到的是一个**空壳**，因为每个数据请求都被后端拒绝。所以正确的目标不是防他看见画面，而是**看见了也拿不到数据**。
    ⚠️ 配套纪律：这两个接口**只返回该用户可见的那部分**，不要下发全量让前端过滤——那泄露「这家公司买了哪些模块」。
6. **语言与框架锁定**：PC 端 Vue3 SPA、移动端 Uni-app（Vue3），TypeScript 贯穿，**坚决排除 React**（决策 79）。契约生成的 Hooks 用 `@tanstack/vue-query`（设计书 §3.9 旧版写的是「React Query Hooks」，已更正）。前端与 `infra-bff-mobile` **都不进任何外壳**（§13.5），所以 TS 侧没有 §K 那套模块入口契约。
7. 所有日期选择器**默认选中「最近 90 天」**（§11.4.4，防无意识全表扫描）。
8. **UI 层逐格锁定**（设计书 §12.6，决策 111）：PC = **Ant Design Vue v4 + vxe-table**，移动端 = **wot-design-uni**（退路 `uni-ui`），图表 = **ECharts + `vue-echarts`**。**精确版本，`package.json` 里不许有 `^` / `~` / `latest`。**
   ⚠️ **两端用不同组件库是设计使然，不是妥协**（§12.6.1.1）：移动端是卡片列表 / 扫码 / 两个审批按钮，PC 是密集表格 / 多级联动长表单——**共用组件的收益本来就接近零**。所以 `packages/` 拆成 `design-tokens`（两端唯一共享，纯数据）+ `ui-kit-pc` + `ui-kit-mobile`。**共享 token，不共享组件**；反过来做会同时得到一个难用的移动端和一个被移动端限制住的 PC 端。
9. **第三方 UI 组件只许出现在 `packages/ui-kit-pc` / `ui-kit-mobile`。** 业务页面严禁直接 `import` 第三方——换实现时改一个文件，而不是改 40 个页面。混搭的**唯一**理由是 AntDV 确实没有这个能力（甘特图、审批流设计器、富文本、代码编辑器、大屏），**观感不是理由**（§12.6.3）。⚠️ **表格例外**：它的 API 面太大，薄封装做不到全保真——`ui-kit-pc` 导出 `<BeTable>` 只封 80% 的用法，剩下的逃生口**每个都要在 `ui-kit-pc/README.md` 记一行**，判据是「这份清单必须可数」（§12.6.6 第 4 步）。
10. **主题只有一处真相源**：AntDV 的 seed token 是源，派生成 vxe 的 `--vxe-ui-*`；`theme.algorithm` 与 `VxeUI.setTheme()` **必须在同一个函数里切**。⚠️ 不接起来的症状是**不报错、能跑，只是每张 ERP 表格看起来像贴进页面里的**（§12.6.2）。
11. **视觉方向「克制专业型」**：只改 seed token 的主色、开 `compactAlgorithm`、系统字体栈（不引入需联网或内嵌的自选字体）、业务页面**禁止硬编码颜色值与间距数值**（值全在 `packages/design-tokens`）。⚠️ **「好看」在本项目里的具体含义是「一致」**——62 个组件的页面由 AI 分批生成，最容易毁观感的不是配色不够大胆，而是「这一页间距 16、下一页 20」（§12.6.5）。
12. **应用骨架自研**，但按 SOP-R 三步法去读 `vue-vben-admin` 的 layout / router+access / request 三块（决策 112、§12.6.4）。**只读它的实现手法，不抄它的导航形态**——形态见下一条。
13. **骨架形态锁定：AWS Console 式两级导航**（设计书 §12.6.7、决策 113）。顶栏「▾服务」下拉（覆盖层，不离开当前页）+ **收藏栏** + ⌘K 命令面板 + **组织/法人切换器**；顶栏下 **应用内标签页**；组件内侧栏**强制扁平 3–5 项、不折叠**，底部固定「组件设置」。
    ⚠️ **不许铺成左侧多级树**：菜单是 62 份 `assembly.yaml` 生成期聚合来的，**每个客户装的组件不同、那棵树家家形状不同**，AI 生成页面时不知道它落在哪一层。
    ⚠️ **照抄 AWS 时必改这三处**：它没有应用内标签页（ERP 一张未保存的出库单会被浏览器刷新吃掉）、它的服务内菜单深度不统一、它的 Region 切换器在我们这里是组织/法人切换器。
14. **业务页面不许从空白 `<div>` 开始摆布局**：一律从 `ui-kit-pc` 的页面级模板起手——`<BeListPage>` / `<BeDetailPage>` / `<BeFormPage>` / `<BeSettingsPage>`，选模板、填插槽。
    ⚠️ 这是铁律 11 的加强版，针对的是 **AWS Console 最被诟病的那个病**：各页面各做各的，二十个服务看起来像二十个产品。**我们的病因一模一样——62 个组件的页面由 AI 分批生成。**
15. **偏好设置只有四项归用户**（设计书 §12.6.8、决策 114）：收藏的组件、亮/暗/跟随系统、标准/紧凑密度、语言；表格列宽列序是第五项但**纯本地不同步**。主色 / logo / 水印 / 灰度是**装配期配置**，**布局模式不做**。
    ⚠️ **`packages/design-tokens` 必须是运行时可写的 CSS 变量，不能是编译进 bundle 的 TS 常量。** 亮/暗与紧凑都要运行时切 token，写成常量就物理上换不了——而**发现的时候页面已经写了几十个**。这是整套前端设计里唯一有时间压力的一条，**在写第一个页面之前落实**。

16. **`401 token_stale` 必须静默刷新后重试一次**（设计书 §14.1.6）：`packages/api-client` 收到带 `error="token_stale"` 的 401 → 静默 refresh → 用新 token 重试原请求，**只重试一次**（防死循环）。这是「人的角色变更也能 ~15 秒生效」的前端那一半；不做的话调岗要等 token TTL。

#### F-测试 · 前端测试分层（详见 [`04-testing-standard.md`](04-testing-standard.md) §六）

FE-1（单元）/FE-2（组件）已在用；FE-3（端到端，Playwright）/FE-4（视觉回归）明确推迟到前端功能基本开发完再统一做，骨架已定死，到时候直接填。契约漂移的正解是建 `packages/api-client`（从契约生成类型），不是多写测试去追——这是一次性建设成本，待实现。**完整的分层判据、现状核对、骨架设计，见 [`04-testing-standard.md`](04-testing-standard.md) 的 §六。**

### SOP-L · 语言基础库（每种语言只做一次）

以下逻辑**每个语言只实现一次**，各组件引入而不是各写一遍：

| 能力 | 为什么必须在基础库 |
|---|---|
| `endpoint(dep, extra)` —— 读**组件地址** `*_ENDPOINT` 并 `TrimPrefix("http://")` | §D：`grpc.Dial("http://host:9094")` 连不上，而报错指向名称解析，极难联想 |
| `storageEndpoint()` —— 读 `STORAGE_ENDPOINT` 并**加上** scheme | §D：它是唯一一个名字带 `ENDPOINT`、值却是裸 `host:port` 的。与上一条**方向相反**，共用一个函数必然有一边错 |
| `withTx(ctx, fn)` —— `BEGIN; SET LOCAL ROLE; SET LOCAL search_path; ...; COMMIT` | §G：用不带 `LOCAL` 的 `SET` 会跨组件串数据且不报错 |
| Outbox 写入 + 推送线程 | §H：生产者必须用 Outbox |
| 事件 Header 注入/提取（`trace_id` / `causation_id` / `hop_count`）+ 防环丢弃 | §H：`hop_count > 5` 直接 DLQ |
| 消费幂等 + `version` 单调校验 | §H：免疫乱序与重复 |
| OTel SDK 初始化（`otelBaseUrl` 空 → Blackhole Exporter） | §7.5：连不上必须静默丢弃，严禁阻塞业务线程 |
| List API 自动注入时间窗口（默认最近 90 天）+ Cursor 分页 | §11.4：业务代码里永远只写 `SELECT * FROM sales_orders` |
| `batchGet` 冷热自动路由（先热表，缺失再查 `{schema}_archive`） | §11.6.1：业务代码里不写 `if archived` |
| 结构化 JSON 日志 + 自动注入 trace 上下文 + PII 脱敏 + 2KB Payload 截断 | §7.3 |
| RED 指标自动暴露（Rate / Errors / Duration），采集间隔 15s | §7.4 |
| **功能权限判定**：`GET /authz/bundle` 每 15s 条件拉 → **进程内存 map**；`besdk.GET/POST(r, path, permKey, h)` 注册即鉴权；`stale_since` 命中 → `401 token_stale` | 设计书 §14.1：**组件里零权限表**。漏写 permKey 编译不过；fail-static 降级、启动未拿到 bundle 返 `503` 而 `/healthz` 照常 healthy |
| **数据范围求解**：从 JWT 的 `dept_path`/`sub` + `data_scopes` 配置算出 `ScopeFilter` 放进 `ctx`，仓储方法取用 | 设计书 §14.2.3：五档退化成纯函数，**不需要组织树副本** |
| **两种调用身份**：`UserClient`（透传 JWT）/ `SystemClient`（组件身份，绕过数据权限） | 设计书 §14.2.6：用户路径上误用 `SystemClient` = 数据权限整条被绕过且**不报错**。`make gates` 扫描：`SystemClient` 只许出现在 `Start()` 与事件 handler 里 |

⚠️ **基础库不是「公共 model 包」。** 它只放上面这些**与业务无关**的横切能力。**严禁**抽一个公共 model 包给两个组件共用——契约在 `contracts/`，代码不共享（§13.3 铁律六）。

#### L-1 · `Runtime` / `Module` / `RunStandalone`：基础库最要紧的三个类型

上面那张表是「横切能力」，这三个类型是**结构**——它们决定了外壳能不能把模块挂进来（设计书 §12.5、§13.3 铁律七）。

```go
package besdk

// Runtime 是调用方交给模块的一切。模块自己不去取任何一样。
//   单跑：由 RunStandalone 填（读进程环境变量、自己开池、自己连 NATS）
//   合并：由外壳启动器填（本模块那一份 env map、外壳的唯一全局池、共用的 NATS 连接）
type Runtime struct {
    ComponentID      string
    ComponentVersion string
    Config           Config          // ⭐ 模块读配置的唯一入口。不许 os.Getenv
    DB               *sql.DB         // ⭐ 合并态下是外壳的唯一池（铁律二）
    NATS             *nats.Conn
    Logger           *slog.Logger    // 已注入 component_id 与 trace 上下文
    Tracer           trace.Tracer
    Meter            metric.Meter
    Registry         *prometheus.Registry // ⭐ 每模块一个，不是默认全局那个
    HTTPPort         int             // 从 component.yaml 来，不是环境变量（§13.8.1）
    ExtraPorts       map[string]int  // {"grpc": 9090}
}

// Module 是模块交回去的一切。模块自己不 Listen、不注册全局、不装信号处理器。
type Module struct {
    HTTPHandler  http.Handler                 // ⭐ 外壳对 Gin 完全无感
    RegisterGRPC func(*grpc.Server)
    Migrations   fs.FS                        // 外壳按拓扑顺序跑（铁律五）
    Start        func(context.Context) error  // 后台循环。必须接 ctx，cancel 时返回
    Stop         func(context.Context) error
}

// RunStandalone 是单跑形态的全部装配，也是**全项目唯一允许读进程环境变量的地方**。
// 它做：Bootstrap（OTel/日志，进程级一次）→ 填 Runtime → 调 newModule →
// 跑迁移 → Listen HTTP 与全部 extraPorts → 装信号处理器 → 优雅关停。
func RunStandalone(newModule func(context.Context, *Runtime) (*Module, error))

// NewGinEngine 发一个已挂好全部中间件的 Gin engine：OTel、request-id、
// error → gRPC status 映射、PII 脱敏日志、RED 指标、/healthz、/metrics。
// ⚠️ 组件不许自己 gin.New()——中间件漏一条不会报错，只是那个组件从此没有 trace。
func NewGinEngine(rt *Runtime) *gin.Engine
```

Python 侧对称：`Runtime`（dataclass）、`Module`（dataclass，`asgi_app: FastAPI`）、`run_standalone(create_module)`、`new_fastapi_app(rt) -> FastAPI`。

#### L-2 · 基础库必须替模块拦住的「进程内单例」

| 东西 | 基础库怎么给 | 模块自己做会怎样 |
|---|---|---|
| OTel provider | `Bootstrap()` 进程级只一次；模块用 `rt.Tracer` | `SetTracerProvider` **最后一个 init 的赢**，22 个模块的 trace 全挂在同一个 `service.name` 上，**一路全绿** |
| 日志根 | `rt.Logger` 已派生好 | `logging.basicConfig()` 是进程级，谁先调谁赢，其余 20 个模块的日志格式被顶掉 |
| Prometheus registry | `rt.Registry`，**每模块一个** | 用默认全局 registry：Go `MustRegister` **panic**、Python 抛 `Duplicated timeseries`。单跑 100% 正常，进外壳第二个模块起来就崩 |
| 信号处理器 | `RunStandalone` 装；外壳形态由外壳装 | 5 个 `uvicorn.Server` 抢 SIGTERM，`docker stop` 关不干净 |
| **Gin 的包级全局**（`gin.SetMode` / `gin.DefaultWriter`） | `Bootstrap` 里设一次；`NewGinEngine` 不碰它 | 它们是**包级变量**，不是 engine 字段。一个模块调 `gin.SetMode(gin.DebugMode)`，**另外 21 个模块一起进 debug**（panic 堆栈直接吐给客户端）。长得像「设置我自己的 engine」，所以最容易漏 |
| 连接池 | `rt.DB` | 铁律二：模块私自 `sql.Open()` 那条路已被否掉 |
| 进程环境变量 | `rt.Config`（唯一读 env 的地方在 `RunStandalone` 里） | `PG_SCHEMA` 与全部 `configSchema` 项在 22 个模块间互相顶掉，**不报错**，模块按别人的 schema 读写数据（§12.5.3） |
| 进程退出 | 返回 error 给调用方 | `log.Fatal` 一次，**整组 22 个组件一起没了** |

---

### SOP-R · 参考实现纪律（先查现实项目，再动手）

**每个组件的业务逻辑都应当先去看现实中成熟的 ERP/CRM 怎么做的。** 理由不是谦虚：ERP 的领域模型是几十年踩坑踩出来的，凭空设计出来的「订单状态机」「库存流水」「会计凭证」几乎必然漏掉边界情形——而那些边界情形要到客户上线三个月后才暴露。

**完整方法论**（三步法、闭源产品也值得参考、许可证判据、怎么记录参考过什么、怎么识别"槽位族"信号）跟具体业务领域无关，通用于任何组件，统一写在 [`02-reference-implementation-standard.md`](02-reference-implementation-standard.md)，不在总纲重复。这里只留本项目专属的部分：**R-2，各域该看哪个项目的哪一块**。

#### R-2 · 各域该看哪个项目的哪一块

| 我们的组件 | 首选参考 | 看它的什么 | 许可证 | 要避免它的什么 |
|---|---|---|---|---|
| `mdm-product` | **Odoo** `addons/product` | `uom.uom` + 换算因子的表设计、`tracking`（none/lot/serial）枚举 | LGPL-3 | —— |
| `mdm-customer` / `mdm-supplier` | **Odoo** `addons/base`（`res.partner`） | 一张 partner 表兼容客户/供应商/联系人的取舍 | LGPL-3 | `res.partner` 把公司、个人、地址、银行账户全塞一张表——**我们刻意拆开**（三测试：数据所有权不同） |
| `erp-inventory` | **ERPNext** `stock`（Stock Ledger Entry） | **流水不可变 + 余额是投影**这个核心设计；批次/序列号追踪 | GPL-3 | —— |
| ↑ 同上 | **Odoo** `addons/stock` | `stock.move` 状态机、`stock.quant` 的预留（reserved）语义 | LGPL-3 | quant 的双写在高并发下要靠数据库锁——我们直接用条件更新（§4.4） |
| `erp-sales` / `erp-purchase` | **Odoo** `addons/sale` / `purchase` | 订单状态机的状态与迁移边、报价→订单→发货→开票的分离 | LGPL-3 | 定价逻辑散落在多个 `_compute` 里——我们集中在一个定价模块（决策 69） |
| ↑ 定价 | **metasfresh** pricing | 价格表 / 折扣阶梯 / 促销的规则模型 | GPL-2/3 | 规则引擎过度可配置，交付现场没人会配 |
| `erp-finance` | **Tryton** `account` | 复式记账的严谨性、会计期间与关账（**这是 Tryton 比 Odoo 强的地方**） | GPL-3 | —— |
| ↑ 同上 | **ERPNext** `accounts` | 会计维度（Accounting Dimension）、单号序列（naming series） | GPL-3 | —— |
| `erp-manufacturing` | **Odoo** `addons/mrp` | BOM 多层展开、工单与工序汇报 | LGPL-3 | MRP 运算与业务对象耦合紧，难独立测 |
| `crm-lead` / `crm-opportunity` | **EspoCRM** / **SuiteCRM** | Lead→Opportunity 转化流程、阶段与赢率、漏斗 | GPL-3 / AGPL-3 | —— |
| `crm-customer` | **Twenty** | 归属关系（owner / assignment）与公海私海的建模 | AGPL-3 | —— |
| `crm-activity` | **EspoCRM** activities | 拜访/电话/日程的统一活动模型 | GPL-3 | —— |
| `infra-workflow` | **Camunda** / **Flowable** | **只看「任务聚合与待办列表」那一层** | Apache-2.0 | ⚠️ **绝不引入 BPMN 引擎**——设计书 §6.6 明确 workflow 严禁包含业务规则（决策 27） |
| `infra-print` | **Odoo** report engine（QWeb） | 模板 + 数据分离、模板版本管理 | LGPL-3 | 它绑 wkhtmltopdf；我们用 WeasyPrint |
| ↑ ZPL 条码 | **Zebra 官方 ZPL II Programming Guide** | 指令集本身（规范文档，不是代码） | 厂商文档 | —— |
| `infra-notification` | **Novu** | 通知意图 → 用户通道偏好 → 多通道并发路由 | MIT | —— |
| `infra-bff-mobile` | **Medusa** 的模块化 + workflow SDK | Saga 编排的 API 形态（补偿步骤怎么声明） | MIT | —— |
| `hrm-payroll-es` | **Odoo** `hr_payroll` 的**结构**（薪资项字典、算薪规则、工资单） | 薪资项如何声明依赖并排序计算 | LGPL-3 | ⚠️ 西班牙 IRPF / Seguridad Social 的**具体规则以官方法规为准**，不要从任何开源项目抄税率表——税率每年变，抄来的那份一定是旧的 |
| `erp-quality` / `erp-maintenance` / `erp-asset` | **Odoo** 对应 addons | 常规 CRUD 与状态机的字段设计 | LGPL-3 | —— |
| `frontend-*` **应用骨架** | **vue-vben-admin** | **只看三块**：`layout`（侧边栏 / 多页签 / 面包屑的组织）、`router` + `access`（路由与权限的注册时机与守卫顺序）、`request` 封装（拦截器、错误码到提示的映射、并发去重） | MIT | ⚠️ **不要把它当依赖引进来**（决策 112）：它的路由+权限层由「后端菜单表 / 静态路由 + 角色码」驱动，而我们是 `GET /api/tenant/features` 的 feature-flag 驱动，换掉那一层就只剩一个 layout 而依赖树全留着。**读它，不装它** |
| ↑ 页面套路 | **Ant Design Pro** 的页面模式（不是它的代码——那是 React） | 列表页 / 详情页 / 表单页 / 分步表单的**信息结构**：筛选区放哪、批量操作放哪、详情页的 tab 怎么切 | MIT | React 实现一行都不抄；只看它的页面结构约定 |
| `frontend-*` **表格** | **vxe-table 官方示例** | 可编辑单元格 + `#edit` 插槽塞第三方控件的写法、虚拟滚动与冻结列的配置边界 | 见 §12.6.6 ⚠️ | ⚠️ **部分能力属于商业版**，开工前逐条核对我们要用的在不在免费档，结论写进设计计划第 8 节 |
| **整体模块化取舍** | **Apache OFBiz** | 实体模型（`OrderHeader` / `OrderItem` / `InventoryItem` / `AcctgTrans`）**极为完整**；`Service Engine` 的事件触发（SECA） | **Apache-2.0** ← **唯一可直接抄的大型 ERP** | Java + 重度 XML 配置，与我们的 Go/Python 栈不搭 |

**要避免的通病（这几乎是所有开源 ERP 的共同缺陷，也是本项目存在的理由）：**

| 通病 | 我们怎么避开 |
|---|---|
| 所有模块同进程、同库、可跨表 JOIN，边界是软约束、天天被破坏 | 独立进程 + 独立 schema + PG RBAC **物理墙**（设计书 §1.1、§1.2） |
| 靠 `_inherit` / 猴子补丁 / 钩子做定制，升级时全部崩 | 整仓 Fork + 契约锁死（§3.4、决策 25） |
| 元数据驱动一切（DocType / 动态字段），强类型缺失，AI 与 IDE 都推不出来 | 契约先行（Protobuf/OpenAPI）+ 强类型语言 |
| 报表直接扫交易明细表，BI 查询拖垮核心业务 | 决策 61：报表必须走汇总表或 `ana-bi` |
| 无限增长的大表，几年后系统被自己的历史数据拖死 | 建表即分区 + 自动归档（设计书第 11 章） |

**R-3（怎么记录参考过什么）与 R-4（怎么识别槽位族信号）完整方法论见 [`02-reference-implementation-standard.md`](02-reference-implementation-standard.md) 的 §二/§四。** 落到本项目时，R-4 发现的新槽位族要按该标准 §4 第 1 步"正式注册"这一步，具体动作是**回设计书新增这个族**（§5.11.1、决策 104）：族名、槽位语义、族内契约面必须完全一致、每个成员适配什么客户画像、默认装哪一个；同步 §5.13 组件总数 + 附录 H；`registry/ports.tsv`/`schemas.tsv` 追加条目（只增不改）。

---

### SOP-P · 什么时候用设计模式（判据，不是偏好）

**不强制用设计模式，但适合的地方必须用。** 完整判据（一句话标准、帮/害 AI 的具体信号、该用/不该用的场景、落地后的文件组织）跟具体业务领域无关，通用于任何组件，统一写在 [`03-ai-development-standard.md`](03-ai-development-standard.md) 的 §一，不在总纲重复。这里只留本项目已经确定要用的几处。

#### P-2 · 本项目已经确定要用的几处

这几处不用再判断，直接照做——它们的分支数和扩展频率已经能预见：

| 组件 | 位置 | 模式 | 为什么 |
|---|---|---|---|
| `erp-sales` / `erp-purchase` | 定价与折扣 | **策略 + 责任链** | 价格规则是「20% 极度个性化且频繁变动」的典型（§1.1）。Fork 件几乎一定要加规则——用一条链，加规则就是加一个文件 |
| `erp-sales` | 订单状态机 | **显式状态表** | 状态迁移的合法性必须集中，散开就一定漏 |
| `erp-inventory` | 出入库单据类型 | **策略** | 入库/出库/调拨/盘点/退货各有校验，但都落到同一张流水表 |
| `erp-finance` | 业务单据 → 会计凭证的翻译 | **策略（一种单据一个翻译器）** | 它的定位就是「把业务数据翻译成会计凭证」（§附录 I）。加一种单据 = 加一个翻译器，不碰已有的 |
| `infra-notification` | 通道路由 | **策略 + 注册表** | 通道是 `channel` 多选并存（决策 26），且**按环境变量在不在动态注册**（§2.4 铁律三） |
| `infra-print` | 渲染后端（PDF / ZPL） | **策略** | 两种输出的实现毫无共同点，只有入参一致 |
| `hrm-payroll-es` | 薪资项计算 | **策略 + 拓扑排序** | 薪资项之间有依赖（社保基数 → 应税所得 → IRPF），算错顺序就算错钱 |
| 所有组件 | Saga 的补偿步骤 | **命令（Command）** | 每步都要能被反向执行，且要能持久化到 `saga_transactions` 表以便重启后继续 |
| `be-ops` | 11 个产出 | **每个产出一个包，一个统一接口** | 已经在总纲 §2.4 定了 |

---

### SOP-D · 每个组件的四份文档（完整模板已并入 [`01-documentation-standard.md`](01-documentation-standard.md) §4）

四份文档不是收尾工作，是**开发流程里的四个具体步骤**：第 1 份在 SOP-B/F 之前，第 2、4 份在建骨架时，第 3 份随实现同步长出来。**每一份具体写什么、模板长什么样、门禁怎么查**，这些跟具体业务领域无关，已经整份并入 [`01-documentation-standard.md`](01-documentation-standard.md) 的 §4（含 D-1~D-4 四个子节 + §4.5 门禁表），不在总纲重复——原本 D-1 那张"九问对应设计书哪一节"的表，其中的具体章节号（§3.1、§11.2、§14.2.2 等）在新标准里换成了通用问法，本项目实际对应哪个设计书章节，仍以本文件其余各节引用的编号为准。

---
## 第 5 部分 · 阶段总览

**顺序不能改**（设计书 §9.6、决策 95）。每一档都是下一档的前提，而且**做外壳必须排在铺满军火库之前**——外壳的坑是结构性的，13 个组件时踩到只要改 `be-ops`，62 个组件时踩到要改 61 份 Manifest 加拆代码。

### 5.1 七个阶段一览

| 阶段 | 名称 | 组件数 | 目标一句话 | 出档条件 | 计划文件 |
|---|---|---|---|---|---|
| **一** | 地基与第一块砖 | 1 | 环境能一键起来，第一块砖能独立活 | `mdm-customer` 六项验收全绿 | [`01-阶段一`](../../plans/01-阶段一-地基与第一块砖.md) ✅ **已出档** |
| **二** | 验平台 | +4 = 5 | brickKit 的每条承诺都真的成立 | 设计书 §9.6.2 那 **20 条平台验收清单**逐条打勾 | [`02-阶段二`](../../plans/02-阶段二-验平台.md) ✅ 已写，四份设计计划齐（未开工） |
| **三** | 业务闭环 | +9 = 14 | 一条业务链真的跑通，权限判定从 stub 换成真实的 | 附录 E 全链路 + Saga 补偿 + 超时查询 + DLQ 进出 + `infra-authz` 上线 | 待写 |
| **四** | 做外壳、验拆回 | 14（合成 2 个外壳） | 验「合并不磨掉组件性」 | 合并态闭环全绿 + **拆回门禁全绿** + import 扫描全绿 + 三份 compose 一条命令启停 | 待写 |
| **五** | 补齐 default | +5 = 18 | 凑齐最小可交付形态 | 每加一个组件，六项验收 + 拆回门禁重跑 | 待写 |
| **六** | 按订单铺货 | +37 = 55 | 军火库补齐 | 同上，逐个 | 待写 |
| **七** | K8s 完全体 | —— | 全拆上云 | 一个组件一个 Deployment/Service | 客户买 K8s 时才写 |

对应设计书 §9.6.1 的档位：阶段一 = 地基 + 档 0，阶段二 = 档 1，阶段三 = 档 2，阶段四 = 档 3，阶段五 = 档 4a，阶段六 = 档 4b，阶段七 = §13.4 阶段三。

⚠️ **每个阶段的计划，是上一个阶段出档之后才写的。** 流程固定：

```
阶段 N 出档
  → 复盘：哪些断言不成立、哪些设计书写的和实际不一样
  → 先改设计书（改不动就先在 be-acceptance 记一条红用例）
  → 再写阶段 N+1 的计划文件
  → 再写该阶段涉及组件的 docs/design/<仓库名>.md
  → 开工
```

**不许跳过「先改设计书」这一步。** 绕过去的那一条，会在 62 个组件时变成 61 处绕法（§9.6.2）。

⚠️ **设计书是「在还没实现任何组件的情况下」尽力做出的划分**（决策 104）。所以每一档的复盘都要预期它会变，而反馈通常是这三种形态之一：

| 反馈形态 | 症状 | 动作 |
|---|---|---|
| **平台断言不成立** | 设计书说平台会 X，实测它不 X | 先在 `be-acceptance` 记一条红用例（哪怕是红的），再回 brickKit 仓库修。**不许在业务侧绕**（§9.6.2） |
| **组件边界画错了** | 实现到一半发现某个字段/职责放错组件，或两个组件之间需要一条设计书里没有的边 | 改设计书的域地图 / 依赖图 / §5.x 职责表，再改代码。**注意别顺手加同步边**——设计书 §4.2 要求同步图无环，且 CRM↔ERP 零同步边 |
| **这里该是一个槽位族** | 参考多个 ERP 时发现同一功能有多种实现、**每一种都合理**、只是适配客户不同 | 走 §4 SOP-R 的 **R-4** 那四步：先回设计书新增族（§5.11.1）→ 同步组件总数与端口册 → 确认没有依赖边 → 再实现。**这是货架长出来的主要方式**（决策 104） |

**最终目标不是把设计书里那 62 个实现完，而是：我们自己有一套默认 ERP，而每个功能组件都可以有多种实现，客户按需选择，甚至基于最接近他需求的那一个做闭源二次开发——那样我们后期二次开发的时间最少。**

### 5.2 每个阶段大致做什么

#### 阶段一 · 地基与第一块砖

把环境和规矩立起来，然后用一块最简单的砖把它们走一遍。

- 基础资源两份 compose（默认 5 个 + 5 个替换件 + 可观测性 5 件套）与 `Makefile`（一键查询 / 一键开启 / 单个开关）
- 全局端口册与 schema 册落盘并配自洽校验——**这两张表必须在写第一个 `component.yaml` 之前定死**，gRPC 端口没有事后补救手段（§3.5.1.1）
- `components/` 改为 git submodule 跟踪，配军火库自洽闸门
- 三个非组件仓库：`be-ops`（装配生成器）、`be-acceptance`（验收）、`be-sdk-go`（横切基础库）
- `mdm-customer` 一个组件，走完 SOP-D + SOP-B 全流程

**为什么第一块砖选 `mdm-customer`**：它是只读枢纽，`dependencies.components` 为空（§2.6），所以能在没有任何其他组件的情况下单独跑通——这正是「一块砖能独立活」要证明的事。

#### 阶段二 · 验平台

加 `mdm-product`、`erp-inventory`、`erp-finance`、`erp-sales` 四块。

**这一档的被测对象是 brickKit，不是我们的业务。** 这四块加上 `mdm-customer` 恰好构成一条含强依赖、含 gRPC 互调、含 Saga 补偿、含事件汇聚的最短链路——平台的全部假设可以被这一条垂直切片打穿（§9.6.0）。设计书 §9.6.2 那 20 条用例在这一档逐条落进 `be-acceptance`，**平台升级后重跑它们就是回归测试**。

#### 阶段三 · 业务闭环

加 `infra-iam-casdoor`、`infra-authz`、`infra-workflow`、`infra-notification`、`integration-im-dingtalk`、`crm-opportunity`、`infra-print`、`infra-bff-mobile`、`frontend-standard` 九块，凑成设计书 §5.13「切片」列那 14 个（附录 H 的「切片」列打勾即是这份清单）。

⚠️ **`infra-authz` 曾经从这份清单里漏写**（阶段二出档复盘核对 §9.6.1/§14.3/附录 H 三处时发现互相矛盾——前者少算一个，后两处一直是对的），已订正。这一档不只是业务链跑通，**权限判定本身也要从阶段二的 fail-closed stub 换成 `infra-authz` 的真实 bundle 轮询**——阶段二五个组件标 `Public` 的接口，这一档要回去换成真实权限键，否则"业务闭环"跑通的其实是一条权限全放行的闭环，验不到 §14 章的任何承诺。

要跑通的链路：**CRM 赢单 → 建单 → 锁库存 → 生成应收 → 审批 → 钉钉通知 → 打印送货单 PDF**（附录 E）。这一档同时引入另外两种语言，所以要先把 `be-sdk-python` 与 `be-sdk-ts` 建起来。

⚠️ `infra-print` 是 Python，选它进切片的理由不是业务，是**阶段四要靠它验 Python 外壳**（§9.6.1）。

#### 阶段四 · 做外壳、验拆回

把 14 个组件合成 **2 个外壳**（Go 外壳装 11 个模块、Python 外壳装 `infra-print`），`infra-bff-mobile` 与 `frontend-standard` 保持独立容器（跨语言合不进来，Nginx 也合不进来，§13.5）。

这一档 `be-ops` 要补齐产出 4/7/8（外壳合并配置、**每外壳的环境变量表**、外壳间 `depends_on`）。其中**产出 7 是设计书点名「真正会在交付现场炸的那个洞」**：平台只往它自己生成的容器里注入，合并后那些容器不存在；同外壳的依赖指 `127.0.0.1`，**跨外壳的必须指宿主机**（§13.8）。

出档的核心是**拆回门禁**：把全部 `local: true` 去掉、`brickkit up` 全拆一次、业务闭环照样全绿。**失败不代表「全拆有 bug」，代表「合并那一刻磨掉了组件性」**（§13.7）。

#### 阶段五 · 补齐 default

加 `infra-storage` → `infra-attachment` → `infra-dlq-monitor` → `mdm-supplier` → `mdm-org` 五块（顺序有依赖：storage 必须在 attachment 前）。

这五个的装配角色都是 `default`——「系统运行的基石，默认必选」（§3.3）。**它们不等客户点名。** 做完这一档，系统具备最小可交付形态。

同时把阶段四那个「验证用的临时 Go 外壳」按 §13.2 拆成外壳一/二/三——**这会第一次真正触发跨外壳环境变量**（阶段四只在 Go↔Python 之间验过）。

#### 阶段六 · 按订单铺货

其余 37 个组件，**按客户订单优先级排队，等第一个客户点名再动**。

⚠️ 设计书附录 H 里那 62 个「✅ 开发」是军火库的最终形态，**不是开工令**。按第 1 章的**选配测试**（客户愿单独付钱、或永远用不到 → 才独立成砖），5 个 IM 里的另 4 个、4 个支付、3 个电子签、2 套 IAM 的替换件、3 套额外前端，绝大多数应当停在队列里。**现在就全开工，等于用选配测试的反面在花钱。**

每次点名的流程固定八步：确认范围 → 查册子（端口与 schema 早已分配，**不许改**）→ 写 `docs/design/<仓库名>.md` → 建目录 → 停下请人建仓库 → 接 submodule → 走 SOP-D/B/F → **重跑六项验收 + 全套门禁**。第八步不许攒着一起跑——拆回门禁红了，你需要知道是哪一个组件让它红的。

#### 阶段七 · K8s 完全体

⚠️ **合并部署只用于 Docker 单机交付，上 K8s 就是全拆，没有中间态**（决策 88）。`local: true` 只能配 `deploy.target: docker`，K8s 目标下 CLI 在生成阶段直接报错。

这一档在客户买了 K8s 集群时才启动。前提是阶段四的拆回门禁**一直是绿的**——如果中途放任它红过，这一档就是重写。

### 5.3 三个不开发的组件

`hrm-payroll-core` / `hrm-payroll-cn` / `hrm-payroll-us` 是 `blueprint`：设计书保留概念定义与契约骨架，**当前不开发、不构建、不交付**（§3.3、决策 65）。端口已在册子里预留，市场验证后激活为 `optional` 才进队列。

`frontend-advanced` / `frontend-{industry}` 标记「🔜 未来」，`frontend-{customer}` 是**按需 Fork**（复制 `frontend-standard` 目录改 remote，不是独立开发）。

---

## 第 6 部分 · 贯穿全程的纪律（不属于某一阶段）

| # | 纪律 | 频率 | 出处 |
|---|---|---|---|
| 1 | **拆回门禁**：全部 `local: true` 去掉、`brickkit up` 全拆一次、业务闭环全绿 | **每周一次** + 每次合并组关系变动时 | §13.7、决策 92 |
| 2 | **import 扫描**：任何组件不许 import 另一个组件仓库 | **每次 CI** | §13.3 铁律六、决策 91 |
| 3 | **平台断言回归**：20 条平台验收用例重跑 | **每次 brickKit 升级后** | §9.6.2、决策 96 |
| 4 | **发现平台有问题时**：先在 `be-acceptance` 记一条用例（哪怕是红的），再回 brickKit 仓库修。**不许在业务侧绕过去** | 每次发生 | §9.6.2 |
| 5 | **提交前还原军火库结构**：`make arsenal-restore` | 每次 commit（pre-commit hook 兜底） | §3.3 |
| 5b | **四份文档同步**：改了边界/契约/事件 → 先改 `docs/design/<仓库名>.md`；改了功能 → README；改了用法或结构 → `docs/手册.md`；改了禁令或判据 → 该仓库的 `AGENTS.md`。**文档先行，不是代码先行** | 每次改动 | §4 SOP-D |
| 6 | **`brickkit remove` 前先 commit & push** | 每次 remove | §9.4.2 |
| 7 | **契约变更走 `make contract-check`**：`buf breaking` / `oasdiff` 拦破坏性变更 | 每次改 `contracts/` | §8.5、决策 33 |
| 8 | **AI 生成的超 50 行复杂业务函数**，必须带自然语言决策树 + Mermaid 流程图注释，否则本地 Code Review 直接打回 | 每次 AI 生成 | §8.5、决策 48 |
| 9 | **核心交易组件的属性测试**（`erp-inventory` / `erp-finance` / `hrm-payroll-es` / `crm-commission`）：人类定义不变量，框架生成随机边界输入攻击 | 每次改核心逻辑 | §8.0、决策 49 |
| 10 | **`brickkit restore` 一旦上线**：改用 `brickkit init --hooks`，删掉我们那份 `arsenal.sh` 的本地兜底判据，避免两套分叉 | 一次性 | §3.3 |

---

## 第 7 部分 · 对设计书的修正与扩展（四批，**已全部回写设计书**）

**这一节是给半年后接手的人看的**：以下是规划过程中在设计书里发现的不自洽，**全部已经改进设计书本体**，本节只留一份变更记录。设计书与本文档现在是一致的——**两边冲突时以设计书为准，并回来改本文档**。

### 修正（6 处，已回写）

| # | 设计书原本写的 | 已改成 | 为什么 | 回写到设计书哪里 |
|---|---|---|---|---|
| 1 | 附录 G / §2.7.1：Traefik Dashboard 8080 | **28080** | 撞外壳一 `mdm-customer` 的 HTTP 8080，而外壳必须把端口发布到宿主机（§13.1），是真撞 | §2.7.1 表 + 表下新增说明段、§2.7.2 ③、§2.7.5 compose、附录 G |
| 2 | 附录 G：Keycloak 8080 / Prometheus 9090 / Kafka 9092 | **28081 / 29090 / 29092** | 同上，分别撞 `mdm-customer` 的 HTTP、`mdm-customer` 的 gRPC、`mdm-product` 的 gRPC | 同上 |
| 3 | §13.2 外壳二列 14 个组件 | **16 个**（加 `hrm-recruitment`、`hrm-appraisal`），区间 8100–8113 → **8100–8115** | 那两个是 Go、常规 CRUD、`reserve`，原文漏列。它们必须有端口，否则档 4b 做到时无处可放 | §13.2 外壳二表 + 表下新增说明 |
| 4 | §13.2 外壳三列「6 个 infra + 15 个 integration = 21 个」 | **7 个 infra**（加 `infra-iam-casdoor`）**+ 14 个 integration = 21 个**，端口区间写明 8200~8220 | `integration-edi` 是 Python、在外壳五，所以 integration 只有 14 个；差的那一个是 `infra-iam-casdoor`（Go、~500 行、没被任何外壳列表收录，但 §9.6.1 档 3 说「Go 外壳装 10 个模块」时把它算进去了）。补上后 21 才对得上 | §13.2 外壳三表 + 表下新增说明；顺带修正「钉子户」表把 Traefik/Casdoor 说成「基础资源」的口径（它们是形态 B 带外容器） |
| 5 | `opportunity.won.v1` 只有**两段**，全书其余事件都是三段 | **`crm.opportunity.won.v1`** | §3.7 的命名法是 `{domain}.{aggregate}.{action}`。改名的时机只有「还没有消费者」这一个——一旦 `erp-sales` 开始消费，改名等于删掉旧 subject（决策 19：只增不删不改） | §3.7（补了完整事件名表与两条 ⚠️）、§4.3 事件图、附录 E 沙盘 |
| 6 | 修正 4 的后续（**2026-09-08 阶段二出档复盘发现**）：`infra-authz` 同样漏算——它和当时补的 `infra-iam-casdoor` 是同一类遗漏（Go、没被外壳列表收录），但设计书 §14.3、附录 H 的「切片」列一直都对（后者早就打了勾），只有 §9.6.1/§13.2 的数字没跟上 | **档 2/档 3 的 Go 部分是 14/11 个（不是 13/10 个）；外壳三最终形态是 8 个 infra + 14 个 integration = 22 个（不是 21 个）** | `infra-authz` 是权限判定的组件本体（第 14 章），"业务闭环"这一档如果不带真实权限判定，验的其实是一条全放行的闭环，验不到 §14 章任何承诺——这条遗漏不是端口计数问题，是**范围**问题 | §9.6.1 档 2/档 3 两行、§13.2 外壳三表下说明段（"10 个模块"→"11 个模块"处一并订正）；行 4 的旧记录原样保留，不倒着改 |

### 扩展（2 处，已回写）

| # | 设计书原本写的 | 已扩成 | 为什么 | 回写到设计书哪里 |
|---|---|---|---|---|
| 1 | §5.10：`be-sdk-events-go`（reserve，Go 事件 SDK） | **`be-sdk-go` / `be-sdk-python` / `be-sdk-ts`，必需件，SOP-L 十四项横切能力** | 事件只占十四项里的 3 项。`Endpoint` 剥 scheme、`WithTx` 的 `SET LOCAL`、OTel 的 Blackhole 降级这几项，每个组件各写一遍必然有人写错——**而写错的那两处恰好是设计书自己点名的「最难查的雷」**。它不是「公共 model 包」：零业务逻辑、零组件 model、零组件间引用，已加进 import 扫描白名单 | §5.10 新增「`be-sdk-*`」小节（含能力表）、附录 H 的 `be-sdk-*` 行、决策 100 |
| 2 | §5.10 / §2.4：`be-ops` 的端口册（产出 6）只管 62 个组件 | **端口册纳入带外容器的宿主机端口** | 外壳把端口发布到宿主机后，组件端口与带外容器端口在**同一个宿主机端口空间**里，两边会真撞（修正 1、2 就是这么发现的）。只管 62 个组件的端口册发现不了这四处 | §3.5.1.1（含 `slot:frontend` 族共用 80 的唯一例外）、§5.10 产出 6、附录 I「全局端口册」、决策 99 |

### 第二批：参考实现纪律与设计模式判据（已回写设计书）

| # | 设计书原本 | 已补成 | 为什么 | 回写到哪里 |
|---|---|---|---|---|
| 6 | 全书没有任何参考实现方法论 | 新增 **§3.2.1 参考实现三步法**：先自己按四把尺子设计一版 → 理不清才去看现实 ERP 怎么实现 → 回来自己想清楚再写。闭源产品同样参考（看不到源码，但「哪些功能客户天天用、哪些从来不点」在选配测试上比源码更有价值） | 凭空设计的领域模型漏掉的边界情形，要到客户上线三个月后才暴露；但顺序反了也不行——空着脑袋去读只会照搬，而我们的技术栈（Go）与组件边界（独立进程独立 schema）都与它们完全不同。许可证只留一小段：借鉴逻辑不构成衍生作品，要避免的只有「打开源文件逐行照抄」 | §3.2.1、决策 102 |
| 7 | 全书没有关于设计模式的任何口径 | 「不强制、但适合就必须用」，判据是「更容易被读懂和扩展，还是更难」，而且**明确按 AI 能不能快速看懂来判**（人这边默认都有模式基础，不构成约束）；已确定要用的九处列在总纲 §4 SOP-P | AI 每次会话都是全新的、上下文有限、看不到运行时状态。所以帮它的是小文件 + 集中注册表 + 显式优于隐式，害它的是深继承 + 元编程 + 空抽象。反过来，纯 CRUD 硬套模式是更糟的结果 | 决策 103（细则在总纲 §4 SOP-P，因为它会随开工进度补充） |
| 8 | §5.11 只写了「已经有多个实现时它该是什么形态」，**没写什么时候该新增一个族** | 新增 **§5.11.1 什么时候该新增一个槽位族**：判据不是「我们想支持多种」，而是「参考多个成熟 ERP 时发现同一功能有多种实现、**每一种都合理**、只是适配客户不同」。含四步回写流程与五个正反例 | **这才是货架长出来的方式。** 最终目标是「我们有一套默认 ERP，但每个功能组件都可以有多种实现，客户按需选择、甚至基于最接近的那个做闭源二次开发」——族越贴合真实分歧，客户 Fork 的起点越近，我们后期二次开发的时间越少 | §5.11.1、决策 104；细则在总纲 §4 SOP-R 的 R-4 |

### 第三批：对照 brickKit **代码**逐项核对（开工前的最后一次审查）

前两批是读设计书发现的不自洽。这一批是**读 brickKit 的 Go 代码**发现的——文档与实现分叉的地方，实现说了算。

| # | 我们原本以为 | 平台实际 | 依据 | 已改哪里 |
|---|---|---|---|---|
| 9 | 「换基础资源实现只改 `brickkit.yaml` 的 `engine` 一个字段，组件代码与 Manifest 零改动」 | **`engine` 逐字参与匹配**。组件写 `nats`、项目写 `kafka` → `up` 阻断。换事件总线要改 ~50 份 `component.yaml` **加**换 SDK driver（客户端库不同）；对象存储反而真零改动。**连带定下 `engine` 该写什么的判据：协议兼容写能力名（storage → `s3`，默认实现 RustFS），协议不兼容写产品名（mq → `nats`，让平台在换 Kafka 时主动阻断）**；数据库写 `postgresql`，不在替换范围 | `internal/config/validate.go`、`006` §2.2/§4.4 | 设计书新增 **§2.7.3.1** + 决策 **105**；§2.7.0/§2.7.1/§2.7.2/§3.4/§5.11/§6.2/附录 I 共 9 处引用点改口径；决策 86 的理由重写 |
| 10 | 带外容器端口挪到 `18080` / `18081` / `19090` / `19092` 就安全了 | **`1xxxx` 整段归平台**：给 `local: true` 组件及其依赖做宿主机映射时首选 `10000 + 容器端口`、fallback 从 `18080` 起递增。我们那四个数**恰好全撞** | `internal/compose/local.go`（`hostPortOffset = 10000`、`hostPortBase = 18080`） | 全部挪到 `2xxxx`：**28080 / 28081 / 29090 / 29092**。设计书 §2.7.1 说明段重写 + 决策 **106**；端口册加「`1xxxx` 不许分配」 |
| 11 | 「平台注入的 `*_ENDPOINT` 恒为 `http://` 开头」 | **只对组件地址成立。** `STORAGE_ENDPOINT` 是裸 `host:port`——它是唯一一个名字带 `ENDPOINT`、值却不带 scheme 的 | `internal/inject/inject.go`（组件地址 `fmt.Sprintf("http://%s:%d")`，storage `hostPort(r)`） | 设计书 §2.1 补一张三行对照表；总纲 §D 同步；`be-sdk-*` 增加 `storageEndpoint()`（**加** scheme，与 `endpoint()` 方向相反） |
| 12 | `bindings` 是可选的 | **声明了资源依赖却没绑定，`up` 阻断。** 每个组件都要一条 `componentId`；合并态下是 **5 条 PostgreSQL 资源条目**（同 host、5 个外壳登录角色）各带自己那组 bindings。`DATABASE_NAME` 取的是 binding 的 `database` 字段，**schema 不走 binding**（走 `configSchema.pgSchema`） | `006` §3.1/§4.4、`internal/inject/inject.go` | 设计书 §2.7.2 ① 补一段；总纲 §2.4 新增**产出 2b** |
| 13 | `labels` 只要值是字符串就行 | **另有三组键归平台所有，写了当场报错**：`brickkit.io/*`、`com.docker.compose.*`、`app` | `internal/manifest/labels.go` | 设计书 §5.10 生成器铁律一补一张表；总纲同步。我们的 `prometheus.io/*` 与 `traefik.http.*` 安全 |
| **14** | 路由表有「两个出口」，独立容器走 `brickkit.yaml` 的 `components[].labels`，平台透传进 compose service | **⚠️ 这条行不通，是本次审查最严重的一处。** 平台生成的 compose **自建一个非 external 的 bridge 网络**，`brickkit.yaml` 里没有任何字段能改。Traefik 的 Docker Provider 只看得见同网络的容器 → 那些路由 labels **一条都读不到**。症状：**labels 写对了、`docker inspect` 看得见，而网关 404、容器全 healthy** | `internal/compose/compose.go`（`networks` 写死为项目名派生的 bridge）；`internal/config/config.go` 无 networks 字段 | 设计书 §6.3.1 改成**三个出口** + §13.8.3 网络那段重写 + 决策 **107**。平台生成的两个容器改走 **`expose: true` + `exposePort` + Traefik file provider**；`exposePort` 进端口册（`frontend-standard` 28090、`infra-bff-mobile` 28500）；`traefik.yml` 加 file provider。**同时记为一条平台改进请求**（`deploy.docker.externalNetworks`） |
| **15** | 连带：`resources[].host` 可以写容器名（如 `be-postgres`） | 平台生成的容器不在 `be-net` 上，**解析不到我们那些容器的名字**。只能写 `host.docker.internal`——这也正是 brickKit `006` §10.4 的建议 | 同上 | 设计书 §13.8.3 补一句 |
| **16** | storage 的 `engine` 写 `minio`（S3 兼容） | 既然 `engine` 是自由字符串且只做逐字比对，**这个词写什么就是个设计决定**。写产品名会让「换实现」白白多改几十份 Manifest；而我们默认跑 RustFS、声明里写 `minio` 也误导人 | `engine` 只校验非空；`006` §2.1 给 storage 举的常见 engine 是 `minio、s3` | **统一改成 `engine: s3`**（能力名）。连带定下判据：**协议兼容写能力名**（storage → `s3`，换 RustFS↔MinIO↔S3 零改动），**协议不兼容写产品名**（mq → `nats`，换 Kafka 时让平台主动阻断，因为那本来就是一次迁移）。设计书 §2.7.3.1 新增一小节 + 决策 73/105 改口径 |

**另外三处小修正：**

| 项 | 内容 |
|---|---|
| `metadata` 支持 `license` / `vendor` / `apiDocs` | 平台的 `manifest.Metadata` 有这三格。`component.yaml` 模板补上 `license: Apache-2.0` 与 `vendor` |
| 组件 ID 正则 | `^[a-z0-9]([a-z0-9-]*[a-z0-9])?/[a-z0-9]([a-z0-9-]*[a-z0-9])?$`——**恰好一个斜杠、只允许小写字母数字与连字符、不允许点号**。所以 §2.3 表里的 `frontend/{industry}` / `frontend/{customer}` 只是占位，真做时要写成 `frontend/retail` 这种 |
| `be-sdk-go` 的 `envName` | 平台的 `manifest.EnvPrefix` **只替换 `/` 与 `-`**。我们原来多写了一条 `.` 的替换规则——不会出错，但会让读的人以为 ID 里可能有点号 |

**核对通过、无需改动的（记下来，免得下次重查）：**

| 假设 | 核对结果 |
|---|---|
| `apiVersion: brickkit/v1` + `kind: Component` | ✓ 常量写死 |
| `deployment.type` 只有 `container` | ✓ `DeploymentTypeContainer` 是唯一合法值 |
| `artifacts[].type` 可以自定义（我们用 `metadata` 分发 `assembly.yaml`） | ✓ `type` / `format` 都是自由字符串，平台不限枚举、不解析内容 |
| 资源 `kind` 封闭枚举 `database/cache/mq/storage/search/smtp` | ✓ 且 `cache` 的变量前缀是 `REDIS_` 不是 `CACHE_` |
| 保留变量：`COMPONENT_ID` / `COMPONENT_VERSION` / `*_ENDPOINT` / `DATABASE_`·`REDIS_`·`MQ_`·`STORAGE_`·`SEARCH_`·`SMTP_` 前缀 | ✓ 逐字一致（另有 binding 上的 `envPrefix` 也会成为保留前缀） |
| `startPeriodSeconds` 默认 **60**（不是 30） | ✓ `DefaultStartPeriodSeconds = 60`，且它是 `healthCheck` 下唯一可覆盖的时间参数 |
| 额外端口变量名 `{前缀}_{端口名大写}_ENDPOINT` | ✓ |
| 版本化服务名 `mdm/customer` + `1.0.0` → `mdm-customer-1-0-0` | ✓ `/` 与 `.` 换 `-`、全小写 |
| `local: true` 不生成容器、迁移容器一并跳过（只警告） | ✓ `localMigrationWarnings` |
| `localPort` 只在 `local: true` 时生效，撞车报错 | ✓ 且非 local 时写它直接报错 |
| `brickkit up --config <文件>` 可用 | ✓ `--config` 是 root 的 persistent flag，子命令继承 |
| 本地安装源布局 `<path>/<scope>/<name>/component.yaml`，原地使用、一个目录一个版本 | ✓ 与我们的 submodule 结构一致 |
| 精确版本正则 `^\d+\.\d+\.\d+$` | ✓ |
| 额外端口名正则 `^[a-z0-9]([a-z0-9-]*[a-z0-9])?$`（我们用 `grpc`） | ✓ |
| `deploy` 支持 `target: docker\|k8s` + 一堆 K8s 选项 | ✓ 另有 `networkPolicy` / `serviceAccount` / `podSecurity` / `ingressClass` 等，阶段七再用 |
| `installer.requireSignature` 存在，但本地源不受约束 | ✓ 与 §9.4.1 一致 |

### 另外补进设计书的一处（不是修正，是原本缺的一档）

**§9.6.1 的「档 4」拆成「档 4a 补齐 default」与「档 4b 铺货」**，并补了一张表说明那 5 个 `default` 组件（`infra-storage` / `infra-attachment` / `infra-dlq-monitor` / `mdm-supplier` / `mdm-org`）为什么不能等客户点名。同时把档 2 出档条件里的「DLQ 进得去出得来」标注清楚——`infra-dlq-monitor` 在档 4a，档 2 验的是**平台 SDK 层的死信通道本身**，管理界面留到 4a。对应新增**决策 101**。

### 第四批：统一技术栈与模块入口（已回写设计书）

起点是一个问题：**为了把 N 个组件合并进一个外壳，同语言的组件是不是必须用同一套框架？** 是——但展开之后发现「框架」只是最表层的一格。

| # | 设计书原本 | 已补成 | 为什么 | 回写到哪里 |
|---|---|---|---|---|
| 17 | §13.5 只有一句「只能合并同语言**同框架**的组件」，全书没有任何地方展开过「同框架」是什么意思；§12.1 还写着「`sqlc` 或 `GORM`」两可 | 新增 **§12.4 每种语言的统一技术栈**：一张逐格锁定表（HTTP 框架 / server / gRPC / DB 驱动 / SQL 层 / 迁移 / 校验 / 指标 / 日志 / OTel / 测试 / 镜像基底），并把分歧分成三层——**物理合不进去 / 起得来然后悄悄错 / 纪律**；其中**迁移那一格是「语言内统一」，其余每一格是「全项目统一」**（外壳不跨语言，所以每个外壳的启动器只需认识自己那门语言的迁移工具；Python 用 `yoyo-migrations`，不用 alembic——零 ORM 让 alembic 的 autogenerate 完全用不上） | 五格是物理的：ASGI 与 WSGI 不能共享事件循环、同步 `grpc` 拿不到共享 async 池、`*sql.DB` 与 `*pgxpool.Pool` 互相递不进去、两种迁移工具两种 `schema_migrations`、默认 Prometheus registry 注册同名指标**直接崩**。而 **Gin 那一格是纪律锁**（`gin.Engine` 就是个 `http.Handler`，混用能编译）——**这个区别必须写明**，否则将来有人以为 FastAPI 也只是偏好 | 设计书新增 §12.4；§12.1 删掉「或 GORM」；§13.5 代价表第一行改写并指向 §12.4；决策 **108** |
| 18 | **全书没有任何地方说「外壳要挂一个组件，该调它什么」** | 新增 **§12.5 模块入口契约**：每个后端组件导出唯一入口 `module.New(ctx, rt) (*besdk.Module, error)`（Python `create_module`），`main` 塌成一行 `besdk.RunStandalone(module.New)`，**单跑与合并调同一个函数**；`Runtime`/`Module` 两个类型的字段逐条定死 | 这是空缺，不是不自洽：缺了它，`be-ops` 产出 4（外壳合并配置）**没有生成对象**，62 个组件会各自发明一个 `main`，而那些装配在合并那天全要重写。更要紧的是——**同一个入口是 §1.5 原则二唯一能被机器守住的形态**，否则 §13.7 的拆回门禁会在半年后第一次真跑时全红 | 设计书新增 §12.5；§13.3 新增**铁律七**；§3.11 新增门禁 **9 `make module-check`**；总纲新增全局约束 **§K** + SOP-L 的 **L-1/L-2** + SOP-B 新增 **B-0**；决策 **109** |
| 19 | §13.3 铁律一 与 SOP-B 的 B-8：「配置只从环境变量来、`*_ENDPOINT` 用 `os.Getenv()` 读」 | **模块代码里零 `os.Getenv`**：依赖地址走 `besdk.Endpoint()`，其余全部配置走 `rt.Config`。不许硬编码地址的意图没变，**改的是「谁去读」** | §13.8.2 已经要求「外壳按模块持有各自的 env map」，可**一个进程只有一份 `environ`**——那句要求只有在模块不碰 `os.Getenv` 时才成立。撞的恰好都是不带 `_ENDPOINT` 的那些：`COMPONENT_ID`、`PG_SCHEMA`、以及每份 `configSchema` 里的每一项（`pgSchema`/`batchSize`/`otelBaseUrl` 同名很常见）。**症状是模块按别人的 schema 读写数据，不报错**——决策 3 那个坑的第二条路径 | 设计书 §12.5.3（含会撞/不会撞的分类表）+ §13.3 铁律七第一条；总纲 §K + SOP-B 的 B-8 改写；决策 **110** |
| 20 | §3.9：契约生成 "TypeScript Interface、**React Query Hooks**" | `@tanstack/vue-query` | 与决策 79「坚决排除 React」直接冲突，是旧版遗留的一处口径 | 设计书 §3.9；总纲 SOP-F 铁律六 |

**这一批与前三批的差别**：前三批修的是「设计书自己前后不一致」和「文档与 brickKit 实现分叉」；这一批修的是**一整块从来没写过的东西**。它之所以现在必须写，是因为它约束的是**每一份组件代码的骨架**——而阶段一的第一块砖（`mdm-customer`）就要按它写。阶段一 Task 6/7/11/16 已同步改。

### 第五批：前端 UI 层锁定（已回写设计书）

与第四批同一个性质：**又一块从来没写过的东西**。§12.2 一直只定到「Vue3 + Uni-app」，它上面那一层（组件库 / 图表 / 应用骨架 / 视觉）全书没有任何口径，而 §12.2 顺口提到的 `Element Plus` / `vxe-table` / `Ant Design Vue` 三个名字容易被当成已经选好了。

| # | 设计书原本 | 已补成 | 为什么 | 回写到哪里 |
|---|---|---|---|---|
| 21 | 只定到 Vue3 + Uni-app；组件库无口径 | 新增 **§12.6 前端 UI 层锁定**：PC = **Ant Design Vue v4 + vxe-table**，移动端 = **wot-design-uni**，图表 = **ECharts + `vue-echarts`** | 移动端用另一套是**设计使然**（移动端形态本来就完全不同，共用组件收益接近零），AntDV 依赖 DOM 只是顺便封死「偷懒复用」。**连带一个结构后果：`packages/ui-kit` 不能是一个包**——共享的 ui-kit 只要 import 了 AntDV，Uni-app 那侧就会把它打进去（小程序端很可能直接编不过）。拆成 `design-tokens`（两端唯一共享，纯数据）+ `ui-kit-pc` + `ui-kit-mobile`：**共享 token，不共享组件**。图表锁 ECharts 的关键理由是**离线可用**（本地化部署没有外网 CDN） | 设计书新增 §12.6.1；§12.2 末尾加一句「本节只定语言与框架，不定组件库」；§5.9 铁律加第 5 条；决策 **111** |
| 22 | —— | **§12.6.2**：AntDV 与 vxe-table 是**两套主题系统**（一套 design token + `theme.algorithm`，一套 CSS 变量 + `VxeUI.setTheme`），必须在 `packages/ui-kit` 里接起来：① seed token 派生成 `--vxe-ui-*`，② AntDV 控件注册成 vxe 的单元格渲染器 | **不接起来的症状是不报错、能跑，只是每张 ERP 表格看起来像贴进页面里的**——主色、边框、行高都不一样，可编辑单元格里的输入框是 vxe 的。这是这一批里唯一一条会直接毁观感的，而它属于「代码看起来完全正确」那一类 | 设计书 §12.6.2、§6.4（`ui-kit` 的三件职责）；总纲 SOP-F 铁律 10 |
| 23 | —— | **§12.6.3 混搭四条判据**：只在 AntDV 确实**没有这个能力**时才混；混进来的必须先进 `packages/ui-kit` 包一层，业务页面严禁直接 `import`；每混一个在设计计划第 8 节记一行；**不许为了「好看」混** | 「需要时可以混搭」不带判据的话，一年后一个页面里五个库、token 体系两两对不齐，**混得越多越不好看**。`ui-kit` 唯一出口那条与 `be-sdk-*` 同一个道理：换实现改一个文件而不是 40 个页面 | 设计书 §12.6.3；总纲 SOP-F 铁律 9；AGENTS.md「不要提议」 |
| 24 | —— | **§12.6.4 应用骨架自研**（不把 admin 模板当依赖），**但按三步法去读 `vue-vben-admin` 的 layout / router+access / request 三块**；**SOP-R 的 R-2 表补上前端三行**（vben / Ant Design Pro 的页面套路 / vxe 官方示例） | 我们有两条约束恰好落在模板最难改的那一层：动态特性路由（模板的路由+权限由后端菜单表或静态路由驱动，换掉它就只剩一个 layout 而依赖树全留着）与 Uni-app 共享层（没有模板覆盖）。而 **R-2 表原本前端一行都没有**，等于前端没有参考实现纪律 | 设计书 §12.6.4；总纲 SOP-R 的 R-2 补 3 行、SOP-F 铁律 12；决策 **112** |
| 25 | —— | **§12.6.5 视觉方向「克制专业型」** + **§12.6.6 vxe 商业版边界开工前必须逐条核** | 「尽量好看」在 62 个组件由 AI 分批生成的前提下，**具体含义是「一致」**——毁观感的不是配色不够大胆，而是「这一页间距 16、下一页 20」。所以 `ui-kit` 导出常量、页面禁止硬编码。而 vxe 文档里有 `enterprise-version` 标记，**部分能力属于商业版**，所以它的状态是「默认选择，待核」——§12.6.6 写成了**四步闭环**（核 → 判定 → 换的候选 → 用 `<BeTable>` 提前压低换的代价），而不是一句提醒；发现得越晚越改不动（40 个页面围着某个能力设计完了，换掉它就是重画） | 设计书 §12.6.5 / §12.6.6；总纲 SOP-F 铁律 11、SOP-R 的 R-2 vxe 那一行；`docs/design/_模板.md` 表头 |

---

---

---

## 第 8 部分 · 已知风险与待决事项

| # | 风险 / 待决 | 影响 | 何时处理 |
|---|---|---|---|
| 1 | **`brickkit restore` / `init --hooks` 尚未实现**（实测当前 CLI 报「未知命令」；brickKit 仓库里设计已确认、实现计划已提交） | submodule 结构下 `sync` 的失误只能靠我们自己那份 `arsenal.sh` 兜底 | 阶段一已做兜底；官方版上线后按纪律 10 换掉 |
| 2 | **RustFS / Kafka / Casdoor 三个镜像的环境变量名按惯例写**，未经实测校准 | `make up` 可能因变量名不对而起不来 | 阶段一 Task 1 步骤 8 已排入校准动作 |
| 3 | **本机 `my-postgres` 跑的是 postgres:15，端口 5432 与本项目冲突**；`my-rustfs` 占 9000 | `make up` 会在预检阶段报错中止 | 由你手动处置（已确认的分工）。`make check` 会点名 |
| 4 | **`sales.*` / `finance.*` 事件第一段用组件短名而非域名**，与 `erp.inventory.*` 不一致（`opportunity.won.v1` 那处已修正为 `crm.opportunity.won.v1`） | 事件 Schema 只增不删不改（决策 19），有消费者之后就改不动了 | **现在还没有任何消费者，是唯一能改的窗口。**已在设计书 §3.7 记下防止有人顺手统一；要不要统一是待决项 |
| 5 | **共享连接池没有舱壁**（决策 3 / §13.3 铁律二的已知代价）：一个模块连接泄漏或跑长事务，整组一起等 | 合并态下的故障隔离弱于全拆态 | 这是合并那一刻就已付掉的账，不是 bug。上 K8s 全拆（阶段三）自动恢复 |
| 6 | **签名整体不生效**（§9.4.1）：全本地源不强制签名 + 外壳镜像不在覆盖范围内 | 供应链保证要靠别的东西承担 | 三条替代措施已写进全局约束 §J；交付文档里必须明确「外壳镜像谁构建、用谁的密钥签、客户怎么验」 |
| 7 | **阶段四的 Go 外壳是临时形态**（1 个进程 11 个模块，含 `infra-authz`），阶段五才拆成 §13.2 的三个 Go 外壳 | 拆的那一次会第一次真正触发跨外壳环境变量 | 阶段五的计划里排；`be-ops` 产出 7 的测试会守住 |
| 8 | **`be-assembly-{customer}` 与「客户 → 组件仓库」映射表**尚未开工 | 首个真实客户交付前必须有 | 首个客户签约时启动，走阶段六那套八步流程 |
| 11 | **brickKit 的设计文档与实现有分叉，且不止一处** | 第三批审查里 5 条全部来自「文档这么写、代码那么做」。往后凡是「平台会不会 X」的关键假设，**以代码为准，并在 `be-acceptance` 里落一条断言** | 已落地：§9.6.2 那 20 条平台验收用例就是这个机制。**新增假设时同步加用例**，别只写进文档 |
| 10 | **我们自己的组件许可证：按 Apache-2.0 推进**（未经正式书面确认，随时可改） | 每个仓库都需要一份 `LICENSE`；事后改许可证需要所有贡献者同意，所以早定省事 | 选 Apache-2.0 的三个理由：① 允许客户 Fork 件闭源，正是设计书 §3.2 要的形态（GPL/AGPL 会直接否掉它）；② 带专利授权，私有化交付时对方法务更容易过；③ 与 Apache OFBiz 同许可证，真要借用它的代码时少一层判断。**阶段一 CP-1 建仓库时一并写入 `LICENSE`**；要换成别的，在那之前说一声即可 |
| 9 | **`docs/design/` 目前只有 `mdm-customer` 一份** | 后续每个组件开工前都要补 | 每个阶段的计划里，第一件事就是写该阶段涉及组件的设计计划（§4 SOP-D） |
| 12 | **`vxe-table` 是「默认选择，待核」，不是已锁死。** 官方文档里带 `enterprise-version` / `enterprise-link` 标记，具体哪些能力属于免费档**未经核对** | 我们是私有化交付。**可编辑单元格 / 虚拟滚动 / 冻结列**这三条是 ERP 表格的地板，其中任何一条落在付费档就必须换 | **阶段三 `frontend-standard` 开工前**走完设计书 §12.6.6 的四步闭环：① 按那张能力清单逐条核 → ② 判定（全免费则锁定 / 少数付费则绕 / 地板三条有付费则换 / 或买——买要先算清私有化交付时是不是每个客户都要授权）→ ③ 换的候选是 AG Grid Community、RevoGrid、TanStack Table，**一律要核同一份清单**（所有严肃表格库都把企业能力做成付费档）→ ④ 从第一天就用 `ui-kit-pc` 的 `<BeTable>`，让换引擎是改一个包而不是 40 个页面。结论写进 `docs/design/frontend-standard.md` 第 8 节。⚠️ 与端口册同类的时序性风险：**发现得越晚越改不动** |
| 13 | **移动端组件库 `wot-design-uni` 不是 DCloud 官方件**，各端小程序的兼容性未经实测 | `apps/mobile` 编到微信 / 钉钉小程序时可能踩组件兼容坑 | 阶段三写 `apps/mobile` 时先拿三五个关键组件（表单、上传、扫码入口、下拉刷新）在目标端各编一遍再铺页面。**退路是 DCloud 官方的 `uni-ui`**（观感差一档，兼容性最稳）——退路要保留在设计计划里，别只写选定的那个 |

---
