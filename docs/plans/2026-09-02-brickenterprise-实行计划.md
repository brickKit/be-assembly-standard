# BrickEnterprise 实行计划

> **给执行者（人或 AI）：** 本计划按任务逐条执行。步骤用 `- [ ]` 复选框标记进度。
> AI 执行时建议用 `superpowers:subagent-driven-development`（每个任务一个新 subagent，任务间人工审查）。

**目标：** 在 brickKit 平台之上，按「先验平台 → 再跑闭环 → 再做外壳 → 最后铺货」的顺序，建成 58 个可交付组件的军火库、2 个外壳、2 个交付关键路径工具（`be-ops` / `be-acceptance`），以及一套一键管理的基础资源环境。

**架构：** 每个组件是一个独立 Git 仓库 + 一块能单独 `brickkit up` 起来的纯 brickKit 组件；本仓库（`be-assembly-standard`）既是标准装配模板，也是军火库索引（用 git submodule 记住每个组件仓库的地址与精确 commit）。基础资源全部 Docker 部署，分「brickKit 基础资源（形态 A）」与「带外容器（形态 B）」两类，由本仓库的 `Makefile` 统一管理。合并部署（外壳）只在档 3 之后作为**交付期的部署选择**出现，绝不反过来影响开发形态。

**技术栈：** Go 1.22+（骨骼与血管）、Python 3.11+（大脑与复杂器官）、TypeScript / Vue3 / Uni-app（皮肤与神经）、PostgreSQL 16、NATS 2.10 (JetStream)、Traefik v3、Casdoor、RustFS、gRPC / Protobuf、OpenTelemetry、Docker Compose v2+。

**规范来源（本计划的唯一真相源）：** [`BrickEnterprise 设计书.md`](../../BrickEnterprise%20设计书.md)
本计划引用设计书时一律带节号（如 §3.5.1.1）。**本计划与设计书冲突时，以设计书为准，并回来修本计划。**
平台侧行为以 brickKit 仓库 `design/` 下 14 本规范性文档为准（引用格式如 `004 §3.9`）。

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

平台注入的 `*_ENDPOINT` **恒为 `http://` 开头**，额外端口也一样：

```
ERP_SALES_ENDPOINT=http://erp-sales-1-0-0:8084          # deployment.port
ERP_SALES_GRPC_ENDPOINT=http://erp-sales-1-0-0:9094     # extraPorts 里 name: grpc
```

**没有 `grpc://` 这种东西。** gRPC 客户端必须自己 `strings.TrimPrefix(v, "http://")`——`grpc.Dial("http://host:9094")` 连不上，而报错指向名称解析，极难联想。这一条写进每个语言的基础库，**只做一次**（见 Task 6 / Task 7）。

**读 `*_ENDPOINT` 必须用 `os.Getenv()` / `os.environ.get()`。** 弱依赖缺失时那个变量**根本不存在**（不是空字符串），用 `os.environ["X"]` 会启动时崩溃——这是平台刻意的设计（§3.6）。

### E. 端口（§3.5.1.1）

- `deployment.port` 与 `extraPorts[].port` **在全部 61 个组件里两两不重复**，由「全局端口册」（本计划 §2.1）钉死。
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
- **迁移状态表必须落在各自的 schema 里**，且表名或主键含组件标识（golang-migrate 用 `x-migrations-table` + `search_path`，Alembic 用 `version_table_schema`）。默认往 `public` 写会让 61 个组件的迁移记录互相顶掉。
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

### J. 交付模型（§9.4）

全本地源、本地构建、无远程私有 Registry。**签名整体不生效**（本地源不强制签名 + 外壳镜像不在覆盖范围内），供应链保证靠：① 每个组件目录对应一个 git remote + 一个 tag（本仓库的 `.gitmodules` 就是这张表）；② 构建脚本进版本控制；③ 外壳镜像的构建/签/验流程写进交付文档。

---

## 第 0 部分 · 怎么用这份计划

### 0.1 阅读顺序

1. **第 1 部分（基础资源 + Makefile）** 必须先读完并做完——它是所有后续任务的物理前提。
2. **第 2 部分（三张全局册子）** 是查表用的，不用背。写任何一个 `component.yaml` 之前回来查端口和 schema。
3. **第 3 部分（仓库拓扑）** 讲 submodule 结构和「叫你建仓库」的检查点流程。
4. **第 4 部分（SOP）** 是组件开发的标准流程，只写一次。第 5 部分起每个组件任务只写它自己的参数与差异，流程一律引 SOP。
5. **第 5~10 部分** 是档 0 → 档 4b 的任务，**顺序不能改**（§9.6：档 3 必须早于档 4）。

### 0.2 检查点：需要你手动建 Git 仓库的地方

本计划有 **6 个人工检查点**。到检查点时，执行者必须**停下**，输出一份「请创建以下仓库」清单，等你建好仓库（并按需设 remote）之后再继续。

| 检查点 | 在哪个任务里 | 要建的仓库 | 数量 |
|---|---|---|---|
| **CP-1** | Task 6 | `be-ops`、`be-acceptance`、`be-sdk-go` | 3 |
| **CP-2** | Task 10 | `mdm-customer` | 1 |
| **CP-3** | Task 17 | `mdm-product`、`erp-inventory`、`erp-finance`、`erp-sales` | 4 |
| **CP-4** | Task 23 | `infra-iam-casdoor`、`infra-workflow`、`infra-notification`、`infra-print`、`infra-bff-mobile`、`integration-im-dingtalk`、`crm-opportunity`、`frontend-standard`、`be-sdk-python`、`be-sdk-ts` | 10 |
| **CP-5** | Task 35 | `be-shell-go`、`be-shell-python` | 2 |
| **CP-6** | Task 42 | `infra-storage`、`infra-attachment`、`infra-dlq-monitor`、`mdm-supplier`、`mdm-org` | 5 |

**六个检查点合计 25 个仓库**（21 个组件 + `be-ops` / `be-acceptance` / 3 个 SDK / 2 个外壳中的部分），到档 4a 结束时军火库里有 **18 个组件**。

档 4b 的 37 个仓库**不设统一检查点**——按客户订单点名，每次点名时走一次 §10.1 那套八步流程（其中第 4 步就是一次检查点）。

**检查点的标准话术**（执行者照抄）：

```
⏸ 检查点 CP-N：需要你手动创建 Git 仓库

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

### 0.3 每个任务的完成判据

任务末尾的「验证」块里写的命令必须**真的跑过并看到期望输出**才算完成。禁止「应该能过」「照理说没问题」——设计书 §9.6.2 那 20 条用例的存在就是因为断言会悄悄失效。

---

## 第 1 部分 · 基础资源与一键管理（先做这个）

### 1.1 基础资源总清单

基础资源是**非组件的外部服务**，我们不写业务代码，只部署官方镜像。**brickKit 不部署它们，也不做启动前的可达性探测**（`006` §8、§9.1）。全部通过 Docker 部署。

三种形态先分清（§2.7.0），混在一起读会得出「网关是个组件」这种错误结论：

| 形态 | 平台怎么看它 | 怎么声明 | 换实现的动作 |
|---|---|---|---|
| **A** brickKit 基础资源 | 认识它，注入连接变量 | `brickkit.yaml` 的 `resources` | 改 `engine` 一个字段 |
| **B** 带外容器 | **完全不知道它存在** | 我们自己的 `docker-compose.*.yml` | 改我们那份 compose |
| **C** 组件 | 普通组件 | `brickkit.yaml` 的 `components` | 改装哪一个 |

**Casdoor 和 Traefik 只能是 B**：平台的资源 `kind` 是封闭清单（`database` / `cache` / `mq` / `storage` / `search` / `smtp`），没有 `gateway` 也没有 `iam`（`006` §2.1）；Traefik 还多一条——**平台的 Manifest 没有 volumes 字段**，网关配置文件挂不进去。

#### 1.1.1 默认必须部署（5 个容器，缺一个系统就跑不起来）

| # | 资源 | 形态 | 声明为 | 镜像 | 宿主机端口 | 健康检查 | 数据卷 |
|---|---|---|---|---|---|---|---|
| 1 | **PostgreSQL** | A | `kind: database, engine: postgresql` | `postgres:16-alpine` | 5432 | `pg_isready -h localhost -p 5432` | `pg_data:/var/lib/postgresql/data` |
| 2 | **NATS** | A | `kind: mq, engine: nats` | `nats:2.10-alpine` | 4222, 8222 | `wget -qO- http://localhost:8222/healthz` | `nats_data:/data` |
| 3 | **Traefik** | B | —（带外） | `traefik:v3.0` | 80, 443, **18080** | `traefik healthcheck --ping` | 配置挂载 |
| 4 | **Casdoor** | B | —（带外） | `casbin/casdoor:latest` | 8000 | `curl -f http://localhost:8000/api/health` | 配置挂载 |
| 5 | **RustFS** | A | `kind: storage, engine: minio`（S3 兼容） | `rustfs/rustfs:latest` | 9000 | `curl -f http://localhost:9000/health/live` | `rustfs_data:/data` |

关键配置要点：

- **PostgreSQL**：`POSTGRES_PASSWORD` 必设；`max_connections=300`（5 个外壳各一个池，足够支撑全量组件）。⚠️ **平台不建库、不建 schema、不建 role**（`006` §9.5）——`brickkit up` 只会**打印**建库语句。实际建置由 `be-ops` 产出脚本、运维执行一次（Task 4）。
- **NATS**：必须 `--jetstream`；`--store_dir /data`；`max_payload=8MB`。
- **Traefik**：启用 Docker Provider（读容器 labels）；`ForwardAuth` 中间件对接 Casdoor；**Dashboard 端口从 8080 挪到 18080**（原因见 §1.2）。
- **Casdoor**：连 PostgreSQL，用自己的 schema `casdoor`；`origin` 配成网关地址。
- **RustFS**：设访问密钥；数据目录挂持久卷。

#### 1.1.2 可选替换件（与默认实现互斥，同一环境只装一个）

| 资源 | 形态 | 镜像 | 替换谁 | 宿主机端口 | 何时用 |
|---|---|---|---|---|---|
| **MinIO** | A（改 `engine`） | `minio/minio:latest` | RustFS | 9000, 9001 | 客户已有 MinIO 运维经验，或要管理界面 |
| **Keycloak** | B | `quay.io/keycloak/keycloak:latest` | Casdoor | **18081** | 复杂 LDAP/AD 域，或极细粒度 RBAC/ABAC |
| **Kafka** | A（改 `engine`） | `confluentinc/cp-kafka:latest` | NATS | **19092** | 每日事件量千万级以上、要流计算 |
| **RabbitMQ** | A（改 `engine`） | `rabbitmq:3.13-management` | NATS | 5672, 15672 | 客户已有 RabbitMQ 基础设施 |
| **Nginx** | B | `nginx:1.25-alpine` | Traefik | 80, 443 | 客户已有 Nginx 运维经验，不要动态服务发现 |

⚠️ 只有 RabbitMQ 才有 `MQ_VHOST`，NATS / Kafka 的资源绑定里**不写这一格**（空值不注入）。

#### 1.1.3 可观测性全家桶（形态 B，要就整套拉起，不要就整套不拉）

| 资源 | 镜像 | 宿主机端口 | 用途 |
|---|---|---|---|
| **OTel Collector** | `otel/opentelemetry-collector-contrib:latest` | 4317, 4318, 13133 | 数据统一收集网关 |
| **Prometheus** | `prom/prometheus:latest` | **19090** | 指标存储后端 |
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

设计书附录 G 原本给的是各镜像的官方默认端口，与 §13.2 的外壳端口区间**有四处物理撞车**。因为外壳必须把端口发布到宿主机（`extra_hosts` 指向 `host-gateway`，§13.1），所以这些是真撞，不是逻辑撞。

**修正已回写设计书**（§2.7.1 表格 + 表下新增的说明段、§2.7.2 ③、§2.7.5 的 compose 示例、附录 G、决策 99）：

| 撞的端口 | 谁和谁 | 修正 |
|---|---|---|
| **8080** | Traefik Dashboard ⚔ `mdm-customer` 的 HTTP（外壳一） | **Traefik Dashboard → 18080** |
| **8080** | Keycloak ⚔ 同上 | **Keycloak → 18081** |
| **9090** | Prometheus ⚔ `mdm-customer` 的 gRPC | **Prometheus → 19090** |
| **9092** | Kafka ⚔ `mdm-product` 的 gRPC | **Kafka → 19092** |

**连带结论：`be-ops` 的全局端口册（产出 6）必须把带外容器的端口一起纳进来**，不能只管 61 个组件。否则这四处撞车会在档 3 第一次把外壳端口发布到宿主机的那一刻才炸，而那时 gRPC 端口已经写进 61 份 `component.yaml`、改不动了（§3.5.1.1）。**这一条已回写设计书 §3.5.1.1、§5.10 产出 6、附录 I 与决策 99。**

**本机现状（2026-09-02 实测）与你的处理方式：**

| 冲突 | 现状 | 与设计书的差 |
|---|---|---|
| :5432 | `my-postgres` 跑 `postgres:15` | 要 `postgres:16-alpine` |
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

档 3 之后再往 Makefile 里加 `make up-all` / `make down-all`，包住 §13.8.3 那三份 compose 的启停链（`brickkit down` 停不了外壳，交付现场一定会出现「以为关干净了，其实外壳还在跑着占着端口」）。那时才有外壳，见 Task 45。

---

## 第 2 部分 · 三张全局册子

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

#### 外壳三 · Go 基建与外部通道（21 个，HTTP 8200–8220 / gRPC 9200–9220）

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

⚠️ **修正 2（已回写设计书 §13.2）**：外壳三的组件列表原本写的是「6 个 infra + 15 个 `integration-*`」，但 `integration-edi` 是 Python、在外壳五，所以 integration 只剩 14 个 → 6 + 14 = 20，与它自己写的「21 个」差 1。差的那一个是 **`infra-iam-casdoor` 适配层**——它是 Go、~500 行、没被任何外壳列表收录，但 §9.6.1 档 3 明确说「Go 外壳装 10 个模块」，而档 2 的 13 个里 Go 的正好是 `mdm-customer`/`mdm-product`/`erp-sales`/`erp-inventory`/`erp-finance`/`crm-opportunity`/`infra-iam-casdoor`/`infra-workflow`/`infra-notification`/`integration-im-dingtalk` = 10 个，含它。补上后 21 这个数字就对上了。

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
| `infra-iam-keycloak` | `infra/iam-keycloak` | 8221 | 9221 | `slot:iam` 替换件，与 `infra-iam-casdoor` 互斥。虽互斥，仍给独立端口（§3.5.1.1 说的是「全部 61 个组件里两两不重复」） |
| `hrm-payroll-core` | `hrm/payroll-core` | 8305 | 9305 | **blueprint，当前不开发。** 端口预留 |
| `hrm-payroll-cn` | `hrm/payroll-cn` | 8306 | 9306 | **blueprint，当前不开发。** 端口预留 |
| `hrm-payroll-us` | `hrm/payroll-us` | 8307 | 9307 | **blueprint，当前不开发。** 端口预留 |

#### 带外容器与基础资源的宿主机端口（本计划修正后的最终值）

| 资源 | 宿主机端口 | 默认? | 与设计书附录 G 的差异 |
|---|---|---|---|
| PostgreSQL | 5432 | ✅ | — |
| NATS | 4222, 8222 | ✅ | — |
| Traefik | 80, 443, **18080** | ✅ | Dashboard 8080 → **18080** |
| Casdoor | 8000 | ✅ | — |
| RustFS | 9000 | ✅ | — |
| MinIO | 9000, 9001 | ❌ | — |
| Keycloak | **18081** | ❌ | 8080 → **18081** |
| Kafka | **19092** | ❌ | 9092 → **19092** |
| RabbitMQ | 5672, 15672 | ❌ | — |
| Nginx | 80, 443 | ❌ | — |
| OTel Collector | 4317, 4318, 13133 | ❌ | — |
| Prometheus | **19090** | ❌ | 9090 → **19090** |
| Loki | 3100 | ❌ | — |
| Tempo | 3200 | ❌ | — |
| Grafana | 3000 | ❌ | — |

**已核对：** 上表所有端口与全部组件的 HTTP（8080–8115、8200–8221、8300–8307、8400–8401、8500、80）及 gRPC（9090–9115、9200–9221、9300–9307、9400–9401）两两不撞。

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
| 外壳三 Go-Infra | `shell_go_infra` | 外壳三那 21 个（+ `infra_iam_keycloak` 若换槽） |
| 外壳四 Py-Brain | `shell_py_brain` | 外壳四那 5 个 |
| 外壳五 Py-Render | `shell_py_render` | 外壳五那 2 个 |

另外两个非组件 schema：`casdoor`（Casdoor 官方镜像自用）、`keycloak`（换槽时用）。

`infra-bff-mobile` **不建 schema**——它严禁直连 DB（§6.5）。`frontend-*` 同理。

### 2.3 组件总表（61 个，一个不漏）

图例：**档位** = 本计划里它在哪一档开工；`4b` 表示按客户订单点名才动。**语言**照 §12.1。**外壳**照 §2.1。

#### infra 基础域（10 个）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 档位 |
|---|---|---|---|---|---|---|---|
| 1 | `infra-iam-casdoor` | `slot:iam` (Default) | Go | 三 | 8200/9200 | `infra_iam_casdoor` | **档 2** |
| 2 | `infra-iam-keycloak` | `slot:iam` (替换件) | Go | 三 | 8221/9221 | `infra_iam_keycloak` | 4b |
| 3 | `infra-bff-mobile` | default | TypeScript | 独立 | 8500/— | 无（禁直连 DB） | **档 2** |
| 4 | `infra-workflow` | default | Go | 三 | 8201/9201 | `infra_workflow` | **档 2** |
| 5 | `infra-notification` | default | Go | 三 | 8202/9202 | `infra_notification` | **档 2** |
| 6 | `infra-attachment` | default | Go | 三 | 8204/9204 | `infra_attachment` | **档 4a** |
| 7 | `infra-storage` | default | Go | 三 | 8205/9205 | `infra_storage` | **档 4a** |
| 8 | `infra-print` | default | **Python** | 五 | 8400/9400 | `infra_print` | **档 2** |
| 9 | `infra-audit` | reserve | Go | 三 | 8206/9206 | `infra_audit` | 4b |
| 10 | `infra-dlq-monitor` | default | Go | 三 | 8203/9203 | `infra_dlq_monitor` | **档 4a** |

#### integration 域（15 个）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 档位 |
|---|---|---|---|---|---|---|---|
| 11 | `integration-im-dingtalk` | `channel:im` | Go | 三 | 8207/9207 | `integration_im_dingtalk` | **档 2** |
| 12 | `integration-im-wechat-work` | `channel:im` | Go | 三 | 8208/9208 | `integration_im_wechat_work` | 4b |
| 13 | `integration-im-feishu` | `channel:im` | Go | 三 | 8209/9209 | `integration_im_feishu` | 4b |
| 14 | `integration-im-slack` | `channel:im` | Go | 三 | 8210/9210 | `integration_im_slack` | 4b |
| 15 | `integration-im-teams` | `channel:im` | Go | 三 | 8211/9211 | `integration_im_teams` | 4b |
| 16 | `integration-payment-stripe` | `channel:payment` | Go | 三 | 8212/9212 | `integration_payment_stripe` | 4b |
| 17 | `integration-payment-paypal` | `channel:payment` | Go | 三 | 8213/9213 | `integration_payment_paypal` | 4b |
| 18 | `integration-payment-alipay` | `channel:payment` | Go | 三 | 8214/9214 | `integration_payment_alipay` | 4b |
| 19 | `integration-payment-wechat-pay` | `channel:payment` | Go | 三 | 8215/9215 | `integration_payment_wechat_pay` | 4b |
| 20 | `integration-esign-docusign` | `channel:esign` | Go | 三 | 8216/9216 | `integration_esign_docusign` | 4b |
| 21 | `integration-esign-pandadoc` | `channel:esign` | Go | 三 | 8217/9217 | `integration_esign_pandadoc` | 4b |
| 22 | `integration-esign-esign` | `channel:esign` | Go | 三 | 8218/9218 | `integration_esign_esign` | 4b |
| 23 | `integration-email` | `channel:email` | Go | 三 | 8219/9219 | `integration_email` | 4b |
| 24 | `integration-sms` | `channel:sms` | Go | 三 | 8220/9220 | `integration_sms` | 4b |
| 25 | `integration-edi` | reserve | **Python** | 五 | 8401/9401 | `integration_edi` | 4b |

#### mdm 主数据域（4 个，只读枢纽）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 档位 |
|---|---|---|---|---|---|---|---|
| 26 | `mdm-customer` | default | Go | 一 | 8080/9090 | `mdm_customer` | **档 0** |
| 27 | `mdm-supplier` | default | Go | 一 | 8081/9091 | `mdm_supplier` | **档 4a** |
| 28 | `mdm-product` | default | Go | 一 | 8082/9092 | `mdm_product` | **档 1** |
| 29 | `mdm-org` | default | Go | 一 | 8083/9093 | `mdm_org` | **档 4a** |

#### crm 客户关系域（7 个，灵活容忍）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 档位 |
|---|---|---|---|---|---|---|---|
| 30 | `crm-lead` | optional | Go | 二 | 8100/9100 | `crm_lead` | 4b |
| 31 | `crm-customer` | optional | Go | 二 | 8101/9101 | `crm_customer` | 4b |
| 32 | `crm-opportunity` | optional | Go | 二 | 8102/9102 | `crm_opportunity` | **档 2** |
| 33 | `crm-activity` | optional | Go | 二 | 8103/9103 | `crm_activity` | 4b |
| 34 | `crm-campaign` | optional | Go | 二 | 8104/9104 | `crm_campaign` | 4b |
| 35 | `crm-case` | optional | Go | 二 | 8105/9105 | `crm_case` | 4b |
| 36 | `crm-commission` | reserve | **Python** | 四 | 8301/9301 | `crm_commission` | 4b |

#### erp 企业资源域（8 个，严谨强一致）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 档位 |
|---|---|---|---|---|---|---|---|
| 37 | `erp-sales` | optional | Go | 一 | 8084/9094 | `erp_sales` | **档 1** |
| 38 | `erp-purchase` | optional | Go | 一 | 8085/9095 | `erp_purchase` | 4b |
| 39 | `erp-inventory` | optional | Go | 一 | 8086/9096 | `erp_inventory` | **档 1** |
| 40 | `erp-finance` | optional | Go | 一 | 8087/9097 | `erp_finance` | **档 1** |
| 41 | `erp-manufacturing` | optional | **Python** | 四 | 8302/9302 | `erp_manufacturing` | 4b |
| 42 | `erp-asset` | optional | Go | 二 | 8111/9111 | `erp_asset` | 4b |
| 43 | `erp-quality` | optional | Go | 二 | 8112/9112 | `erp_quality` | 4b |
| 44 | `erp-maintenance` | optional | Go | 二 | 8113/9113 | `erp_maintenance` | 4b |

#### hrm 人力资源域（9 个，含 3 个 blueprint）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 档位 |
|---|---|---|---|---|---|---|---|
| 45 | `hrm-attendance` | optional | Go | 二 | 8106/9106 | `hrm_attendance` | 4b |
| 46 | `hrm-leave` | optional | Go | 二 | 8107/9107 | `hrm_leave` | 4b |
| 47 | `hrm-expense` | optional | Go | 二 | 8108/9108 | `hrm_expense` | 4b |
| 48 | `hrm-recruitment` | reserve | Go | 二 | 8114/9114 | `hrm_recruitment` | 4b |
| 49 | `hrm-appraisal` | reserve | Go | 二 | 8115/9115 | `hrm_appraisal` | 4b |
| 50 | `hrm-payroll-core` | **blueprint** | Python | 四 | 8305/9305 | `hrm_payroll_core` | **不开发** |
| 51 | `hrm-payroll-cn` | **blueprint** | Python | 四 | 8306/9306 | `hrm_payroll_cn` | **不开发** |
| 52 | `hrm-payroll-us` | **blueprint** | Python | 四 | 8307/9307 | `hrm_payroll_us` | **不开发** |
| 53 | `hrm-payroll-es` | `slot:payroll` optional | **Python** | 四 | 8300/9300 | `hrm_payroll_es` | 4b |

⚠️ `hrm-payroll-es` **内嵌薪资引擎功能**（薪资项字典、算薪周期、工资单数据结构），**不依赖** `hrm-payroll-core`（决策 64）。

#### prj 项目管理域（2 个）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 档位 |
|---|---|---|---|---|---|---|---|
| 54 | `prj-project` | optional | Go | 二 | 8109/9109 | `prj_project` | 4b |
| 55 | `prj-timesheet` | optional | Go | 二 | 8110/9110 | `prj_timesheet` | 4b |

#### ana 数据分析域（2 个，储备）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP/gRPC | schema | 档位 |
|---|---|---|---|---|---|---|---|
| 56 | `ana-bi` | reserve | **Python** | 四 | 8303/9303 | `ana_bi` | 4b |
| 57 | `ana-ai` | reserve | **Python** | 四 | 8304/9304 | `ana_ai` | 4b |

#### frontend 前端域（4 个）

| # | 仓库名 | 装配角色 | 语言 | 外壳 | HTTP | schema | 档位 |
|---|---|---|---|---|---|---|---|
| 58 | `frontend-standard` | `slot:frontend` (Default) | TypeScript (Vue3 + Uni-app) | 独立 | 80 | 无 | **档 2** |
| 59 | `frontend-advanced` | `slot:frontend` (替换件) | TypeScript | 独立 | 80 | 无 | 🔜 未来 |
| 60 | `frontend-{industry}` | `slot:frontend` (替换件) | TypeScript | 独立 | 80 | 无 | 🔜 未来 |
| 61 | `frontend-{customer}` | `customer_fork` `slot:frontend` | TypeScript | 独立 | 80 | 无 | 📋 按需 Fork |

#### 非组件资产仓库（6 个，不在 61 里）

| 仓库名 | 用途 | 档位 |
|---|---|---|
| `brickKit` | 平台本身（已存在） | — |
| `be-assembly-standard` | 产品根 / 标准装配模板 / 军火库索引（**本仓库**，已存在） | — |
| **`be-ops`** | **必需（交付关键路径）** 装配生成器，8 个产出，见 §2.4 | **阶段 -1** |
| **`be-acceptance`** | **必需（交付关键路径）** 验收测试：20 条平台验收 + 业务闭环 + 拆回门禁 + import 扫描 | **阶段 -1** |
| `be-shell-go` | Go 外壳启动器（我们自己适配，不进 `components/`） | **档 3** |
| `be-shell-python` | Python 外壳启动器（同上） | **档 3** |
| `be-sdk-events-go` | reserve，Go 事件 SDK | 4b（可选，先内嵌在各组件里） |
| `be-assembly-{customer}` | 客户后端装配清单 | 首个客户时 |

**统计核对**：61 = infra 10 + integration 15 + mdm 4 + crm 7 + erp 8 + hrm 9 + prj 2 + ana 2 + frontend 4 ✓
需构建 58（61 − 3 个 blueprint）；其中档 0–3 做 13 个、档 4a 做 5 个、档 4b 做 37 个（= 43 剩余 − 3 blueprint − 3 未来/按需前端）✓

### 2.4 `be-ops` 的 8 个产出（决策 89 / 93）

平台刻意不做、而活不会消失的那些，全在这里。`be-ops` **不是 brickKit 组件**（不进 `brickkit.yaml`），是我们自己的命令行工具，读全部组件的 `assembly.yaml` 产出：

| # | 产出 | 替代了平台的什么 | 本计划哪个任务做 |
|---|---|---|---|
| 1 | **网关路由表（两个出口）**：进外壳的组件 → shell-compose 的 service `labels`；独立容器 → `brickkit.yaml` 的 `components[].labels`；K8s → 带外 Ingress 清单 | 平台不做 path 路由（§6.3） | Task 43 |
| 2 | **数据库建置脚本**：`CREATE DATABASE` + 每组件 `CREATE SCHEMA` / `{schema}_archive` / `CREATE ROLE` / 授权 + 5 个外壳登录角色 | 平台只打印建库语句（§2.7.2） | Task 4 |
| 3 | **Feature 清单**：装配结果 → 写进 IAM 适配层的 `config.enabledComponents`（**逗号分隔字符串**） | 平台不给组件「当前装配了什么」的视图（§6.1） | Task 27 |
| 4 | **外壳合并配置**：哪些组件进哪个外壳、端口分配、迁移执行顺序 | 平台不提供合并部署支持（§13.6） | Task 41 |
| 5 | **`brickkit.yaml` 生成**：含 `assembly.yaml` 的 schema 校验、`slot` 互斥校验、`channel` 多选校验 | 平台没有装配角色的概念（§3.3） | Task 6 |
| 6 | **全局端口册**：61 个组件的 HTTP + gRPC 两两不重复 **+ 带外容器端口**（本计划的修正） | 平台只在 `local: true` 撞车时报错（§3.5.1.1） | Task 3 |
| 7 | **每外壳的环境变量表**：同外壳依赖 → `http://127.0.0.1:<端口>`；**跨外壳/独立容器 → `http://<宿主机地址>:<端口>`** | **平台只往它自己生成的容器里注入，合并后那些容器不存在**（§13.8） | Task 42 |
| 8 | **shell-compose 的 `depends_on`**：外壳之间的启动顺序 | 平台只排它生成的那些（§13.8） | Task 44 |

**三条生成器铁律（必须写进 `be-ops` 的实现与测试）：**

1. **`labels` 的值必须是字符串。** Docker labels 与 K8s annotations 两边都只收字符串，平台**不做自动转换**。布尔与数字一律带引号产出：`"true"` / `"8080"`。
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
│   └── plans/2026-09-02-brickenterprise-实行计划.md   ← 本文件
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
│   └── be-acceptance/                   → git@github.com:brickKit/be-acceptance.git
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

**步骤 B（检查点，停下等你）**：输出 §0.2 的标准话术，列出目录与仓库名。

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

---

## 第 4 部分 · 组件开发标准流程（SOP）

第 5 部分起，每个组件任务只写它自己的**参数与差异**，流程一律引用本节。**本节写一次，全项目 58 个组件通用。**

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
│   ├── cmd/server/main.go    # 或 Python: app/main.py
│   ├── internal/...
│   └── ...
├── migrations/
│   ├── 001_<...>.up.sql
│   └── 001_<...>.down.sql
├── Dockerfile                # 基底必须带 /bin/sh + wget
├── Makefile                  # §I 那 7 个门禁目标
└── README.md
```

**14 个步骤，顺序不能改**（TDD：契约先行、测试先写）：

- [ ] **B-1 建仓库骨架目录与文件**（不 `git init`，等检查点）
- [ ] **B-2 写 `contracts/`**：`.proto` + `events/*.events.json`（+ 对外 REST 组件写 `.openapi.yaml`）。
      每个聚合根**必须**提供 `batchGet`（§3.8，BFF 层防 N+1 的唯一合法调用方式）。
      跨组件写接口**必须**带 `idempotency_key`，且**必须**提供 `GetStatus`（§4.5 薛定谔的超时）。
- [ ] **B-3 写 `component.yaml`**：端口从 §2.1 端口册抄，`pgSchema` 默认值从 §2.2 抄。检查全局约束 B / C / E / F。
- [ ] **B-4 写 `assembly.yaml`**：`asset` / `domain` / `tier` / `edge_routes` / `menus` / `data.schema` / `data.role` / `shell`。
- [ ] **B-5 写迁移**：分区表在 migration 里建（决策 51）；强制字段（§G）；分区表主键含分区键；**迁移状态表落本组件 schema**。
- [ ] **B-6 写失败测试**（先写测试，再写实现）：`/healthz`、每个 gRPC rpc、`batchGet`、Outbox 落库、消费幂等。
      核心交易组件（`erp-inventory` / `hrm-payroll-es` / `erp-finance`）**必须**引入基于属性的测试（Go 用 `rapid` / `gopter`，Python 用 `hypothesis`），由人类定义不变量（如「库存总数不能为负」），框架生成随机边界输入攻击 AI 生成的代码（§8.0、决策 49）。
- [ ] **B-7 跑测试确认全红**（没红就是测试没写对）
- [ ] **B-8 写最小实现**：HTTP 主端口 + gRPC 端口都真的 `Listen`；配置只从环境变量来，代码里零硬编码地址；`*_ENDPOINT` 用 `os.Getenv()` 读并 `TrimPrefix("http://")`。
- [ ] **B-9 跑测试确认全绿**
- [ ] **B-10 写 `Dockerfile`**：基底 `alpine`（Go）/ `python:3.11-slim`（Python），装 `wget`；`make image` 后 `docker run --rm <img> sh -c 'wget --version'` 必须成功。
- [ ] **B-11 写 `Makefile`**：§I 那 7 个门禁目标全部实现。
- [ ] **B-12 跑 7 个门禁全绿**
- [ ] **B-13 单独 `brickkit up` 起来并跑档 0 六项验收**（见 §5.2）
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
│   └── mobile/               # Uni-app
│       └── {pages,manifest.json}
├── packages/
│   ├── shared-types/         # 由契约生成
│   ├── api-client/           # 由契约生成
│   ├── ui-kit/
│   └── feature-flags/        # 动态特性路由
├── docker/Dockerfile         # 构建产物打包为 Nginx 镜像
├── Makefile
└── README.md
```

**前端铁律（§5.9 / §6.4 / 决策 75）：**

1. **严禁硬编码核心商业逻辑**：算钱、扣库存、核心状态机流转一律在后端。
2. **全权接管表单交互逻辑**：正则校验、字段联动显隐、防抖节流、本地草稿缓存（断网保护）。拒绝「为了一个字段显隐去调后端接口」。
3. **Dry-Run 模式**：复杂联动（如按客户等级 + 产品实时算预估总价）必须**防抖调用后端的 `DryRun` / `Validate` 接口**取结果，不得在前端复写后端计算公式。
4. **严禁手写 `fetch('/api/sales')`**，必须用 `packages/api-client` 里由契约生成的 SDK（§3.9）。
5. **动态特性路由**：启动时调 `GET /api/tenant/features`，按返回的启用组件清单动态注册路由与菜单，未启用的自动隐藏。
6. **技术栈锁定**：PC 端 Vue3 SPA、移动端 Uni-app（Vue3），TypeScript 贯穿，**坚决排除 React**（决策 79）。
7. 所有日期选择器**默认选中「最近 90 天」**（§11.4.4，防无意识全表扫描）。

### SOP-L · 语言基础库（只做一次，Task 6 / 7 / 8）

以下逻辑**每个语言只实现一次**，各组件引入而不是各写一遍：

| 能力 | 为什么必须在基础库 |
|---|---|
| `endpoint(name)` —— 读 `*_ENDPOINT` 并 `TrimPrefix("http://")` | §D：`grpc.Dial("http://host:9094")` 连不上，而报错指向名称解析，极难联想 |
| `withTx(ctx, fn)` —— `BEGIN; SET LOCAL ROLE; SET LOCAL search_path; ...; COMMIT` | §G：用不带 `LOCAL` 的 `SET` 会跨组件串数据且不报错 |
| Outbox 写入 + 推送线程 | §H：生产者必须用 Outbox |
| 事件 Header 注入/提取（`trace_id` / `causation_id` / `hop_count`）+ 防环丢弃 | §H：`hop_count > 5` 直接 DLQ |
| 消费幂等 + `version` 单调校验 | §H：免疫乱序与重复 |
| OTel SDK 初始化（`otelBaseUrl` 空 → Blackhole Exporter） | §7.5：连不上必须静默丢弃，严禁阻塞业务线程 |
| List API 自动注入时间窗口（默认最近 90 天）+ Cursor 分页 | §11.4：业务代码里永远只写 `SELECT * FROM sales_orders` |
| `batchGet` 冷热自动路由（先热表，缺失再查 `{schema}_archive`） | §11.6.1：业务代码里不写 `if archived` |
| 结构化 JSON 日志 + 自动注入 trace 上下文 + PII 脱敏 + 2KB Payload 截断 | §7.3 |
| RED 指标自动暴露（Rate / Errors / Duration），采集间隔 15s | §7.4 |

⚠️ **基础库不是「公共 model 包」。** 它只放上面这些**与业务无关**的横切能力。**严禁**抽一个公共 model 包给两个组件共用——契约在 `contracts/`，代码不共享（§13.3 铁律六）。

---

## 第 5 部分 · 阶段 -1 与档 0

> 出档条件（阶段 -1）：`make check` 全绿；端口册与 schema 册落盘；`be-ops` / `be-acceptance` 骨架可跑。
> 出档条件（档 0）：`mdm-customer` 六项验收全绿（§5.2）。

### 5.1 阶段 -1 · 地基

#### Task 1：infra 目录、声明式资源表、两份 compose

**Files:**
- Create: `infra/resources.tsv`
- Create: `infra/docker-compose.infra.yml`
- Create: `infra/docker-compose.observability.yml`
- Create: `infra/traefik/traefik.yml`
- Create: `infra/casdoor/conf/app.conf`
- Create: `infra/otel/config.yaml`
- Create: `infra/prometheus/prometheus.yml`
- Create: `infra/tempo/tempo.yaml`
- Create: `.env.example`
- Modify: `.gitignore`（追加 `infra/**/secrets/`）

**Interfaces:**
- Produces：`infra/resources.tsv` 的 9 列格式 —— `name` / `project` / `compose_file` / `service` / `container` / `image` / `host_ports` / `default` / `profile` / `mutex`（制表符分隔，`#` 开头为注释）。Task 2 / 3 的脚本全部读它。
- Produces：两个 Compose 项目名 —— `be-infra`（默认 5 个 + 5 个替换件）与 `be-obs`（可观测性 5 件套）。两个项目共用 external network `be-net`。

- [ ] **步骤 1：写 `infra/resources.tsv`**

```tsv
# name	project	compose_file	service	container	image	host_ports	default	profile	mutex
# --- 默认必须部署（5 个）---
postgres	be-infra	infra/docker-compose.infra.yml	postgres	be-postgres	postgres:16-alpine	5432	yes	-	-
nats	be-infra	infra/docker-compose.infra.yml	nats	be-nats	nats:2.10-alpine	4222,8222	yes	-	mq
traefik	be-infra	infra/docker-compose.infra.yml	traefik	be-traefik	traefik:v3.0	80,443,18080	yes	-	gateway
casdoor	be-infra	infra/docker-compose.infra.yml	casdoor	be-casdoor	casbin/casdoor:latest	8000	yes	-	iam
rustfs	be-infra	infra/docker-compose.infra.yml	rustfs	be-rustfs	rustfs/rustfs:latest	9000	yes	-	storage
# --- 可选替换件（与默认互斥）---
minio	be-infra	infra/docker-compose.infra.yml	minio	be-minio	minio/minio:latest	9000,9001	no	minio	storage
keycloak	be-infra	infra/docker-compose.infra.yml	keycloak	be-keycloak	quay.io/keycloak/keycloak:latest	18081	no	keycloak	iam
kafka	be-infra	infra/docker-compose.infra.yml	kafka	be-kafka	confluentinc/cp-kafka:latest	19092	no	kafka	mq
rabbitmq	be-infra	infra/docker-compose.infra.yml	rabbitmq	be-rabbitmq	rabbitmq:3.13-management	5672,15672	no	rabbitmq	mq
nginx	be-infra	infra/docker-compose.infra.yml	nginx	be-nginx	nginx:1.25-alpine	80,443	no	nginx	gateway
# --- 可观测性五件套（要就整套，不要就整套不要）---
otel-collector	be-obs	infra/docker-compose.observability.yml	otel-collector	be-otel	otel/opentelemetry-collector-contrib:latest	4317,4318,13133	no	obs	-
prometheus	be-obs	infra/docker-compose.observability.yml	prometheus	be-prometheus	prom/prometheus:latest	19090	no	obs	-
loki	be-obs	infra/docker-compose.observability.yml	loki	be-loki	grafana/loki:latest	3100	no	obs	-
tempo	be-obs	infra/docker-compose.observability.yml	tempo	be-tempo	grafana/tempo:latest	3200	no	obs	-
grafana	be-obs	infra/docker-compose.observability.yml	grafana	be-grafana	grafana/grafana:latest	3000	no	obs	-
```

⚠️ `mutex` 列里默认实现也写了组名（`nats` 写 `mq`、`traefik` 写 `gateway`…），这是故意的：Task 3 的互斥校验要能从「我要开 kafka」反查「同组的 nats 在跑吗」。

- [ ] **步骤 2：写 `infra/docker-compose.infra.yml`**

```yaml
name: be-infra

networks:
  be-net:
    external: true

volumes:
  pg_data:
  nats_data:
  rustfs_data:
  minio_data:
  kafka_data:
  rmq_data:

services:
  # ① PostgreSQL —— 共享单一 Database + 每组件独立 Schema（决策 3）
  postgres:
    image: postgres:16-alpine
    container_name: be-postgres
    networks: [be-net]
    ports: ["5432:5432"]
    environment:
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?POSTGRES_PASSWORD 必须在 .env 里设置}
      POSTGRES_DB: postgres
    command: ["postgres", "-c", "max_connections=300"]
    volumes: [pg_data:/var/lib/postgresql/data]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h localhost -p 5432 -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

  # ② NATS —— 事件总线（默认）。JetStream 必开
  nats:
    image: nats:2.10-alpine
    container_name: be-nats
    networks: [be-net]
    ports: ["4222:4222", "8222:8222"]
    command: ["--jetstream", "--store_dir", "/data", "--http_port", "8222", "--max_payload", "8MB"]
    volumes: [nats_data:/data]
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:8222/healthz || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

  # ③ Traefik —— API 网关（默认）。Dashboard 从 8080 挪到 18080（本计划 §1.2）
  traefik:
    image: traefik:v3.0
    container_name: be-traefik
    networks: [be-net]
    ports: ["80:80", "443:443", "18080:18080"]
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/traefik.yml:/etc/traefik/traefik.yml:ro
    healthcheck:
      test: ["CMD", "traefik", "healthcheck", "--ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

  # ④ Casdoor —— IAM 认证（默认）。带外容器，不进 brickkit.yaml
  casdoor:
    image: casbin/casdoor:latest
    container_name: be-casdoor
    networks: [be-net]
    ports: ["8000:8000"]
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      RUNNING_IN_DOCKER: "true"
    volumes:
      - ./casdoor/conf:/conf
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:8000/api/health || curl -fsS http://localhost:8000/api/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 60s
    restart: unless-stopped

  # ⑤ RustFS —— 对象存储（默认）
  rustfs:
    image: rustfs/rustfs:latest
    container_name: be-rustfs
    networks: [be-net]
    ports: ["9000:9000"]
    environment:
      RUSTFS_ACCESS_KEY: ${STORAGE_ACCESS_KEY:?STORAGE_ACCESS_KEY 必须在 .env 里设置}
      RUSTFS_SECRET_KEY: ${STORAGE_SECRET_KEY:?STORAGE_SECRET_KEY 必须在 .env 里设置}
    volumes: [rustfs_data:/data]
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:9000/health/live || curl -fsS http://localhost:9000/health/live || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

  # ===== 以下全部是可选替换件，靠 profile 开启，默认不启动 =====

  minio:
    image: minio/minio:latest
    container_name: be-minio
    profiles: [minio]
    networks: [be-net]
    ports: ["9000:9000", "9001:9001"]
    command: ["server", "/data", "--console-address", ":9001"]
    environment:
      MINIO_ROOT_USER: ${STORAGE_ACCESS_KEY:?}
      MINIO_ROOT_PASSWORD: ${STORAGE_SECRET_KEY:?}
    volumes: [minio_data:/data]
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:9000/minio/health/live || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 5

  keycloak:
    image: quay.io/keycloak/keycloak:latest
    container_name: be-keycloak
    profiles: [keycloak]
    networks: [be-net]
    ports: ["18081:8080"]
    command: ["start-dev", "--health-enabled=true"]
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      KC_DB: postgres
      KC_DB_URL: jdbc:postgresql://be-postgres:5432/brickkit_db?currentSchema=keycloak
      KC_DB_USERNAME: postgres
      KC_DB_PASSWORD: ${POSTGRES_PASSWORD:?}
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: ${KEYCLOAK_ADMIN_PASSWORD:?}
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:9000/health/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 90s

  kafka:
    image: confluentinc/cp-kafka:latest
    container_name: be-kafka
    profiles: [kafka]
    networks: [be-net]
    ports: ["19092:9092"]
    environment:
      KAFKA_NODE_ID: 1
      KAFKA_PROCESS_ROLES: broker,controller
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://be-kafka:9092
      KAFKA_CONTROLLER_QUORUM_VOTERS: 1@be-kafka:9093
      KAFKA_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,CONTROLLER:PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      CLUSTER_ID: brickenterprise-dev-cluster
    volumes: [kafka_data:/var/lib/kafka/data]
    healthcheck:
      test: ["CMD-SHELL", "kafka-topics --bootstrap-server localhost:9092 --list || exit 1"]
      interval: 10s
      timeout: 10s
      retries: 10
      start_period: 60s

  rabbitmq:
    image: rabbitmq:3.13-management
    container_name: be-rabbitmq
    profiles: [rabbitmq]
    networks: [be-net]
    ports: ["5672:5672", "15672:15672"]
    environment:
      RABBITMQ_DEFAULT_USER: ${MQ_USER:-brickkit}
      RABBITMQ_DEFAULT_PASS: ${MQ_PASSWORD:?}
    volumes: [rmq_data:/var/lib/rabbitmq]
    healthcheck:
      test: ["CMD-SHELL", "rabbitmq-diagnostics -q ping || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  nginx:
    image: nginx:1.25-alpine
    container_name: be-nginx
    profiles: [nginx]
    networks: [be-net]
    ports: ["80:80", "443:443"]
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost/ || exit 1"]
      interval: 5s
      timeout: 3s
      retries: 5
```

- [ ] **步骤 3：写 `infra/docker-compose.observability.yml`**

```yaml
name: be-obs

networks:
  be-net:
    external: true

volumes:
  prom_data:
  loki_data:
  tempo_data:
  grafana_data:

services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:latest
    container_name: be-otel
    networks: [be-net]
    ports: ["4317:4317", "4318:4318", "13133:13133"]
    command: ["--config=/etc/otel/config.yaml"]
    volumes:
      - ./otel/config.yaml:/etc/otel/config.yaml:ro
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:13133/ || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5

  prometheus:
    image: prom/prometheus:latest
    container_name: be-prometheus
    networks: [be-net]
    ports: ["19090:9090"]
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prom_data:/prometheus
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:9090/-/healthy || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5

  loki:
    image: grafana/loki:latest
    container_name: be-loki
    networks: [be-net]
    ports: ["3100:3100"]
    volumes: [loki_data:/loki]
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:3100/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  tempo:
    image: grafana/tempo:latest
    container_name: be-tempo
    networks: [be-net]
    ports: ["3200:3200"]
    command: ["-config.file=/etc/tempo/tempo.yaml"]
    volumes:
      - ./tempo/tempo.yaml:/etc/tempo/tempo.yaml:ro
      - tempo_data:/var/tempo
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:3200/ready || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 10
      start_period: 30s

  grafana:
    image: grafana/grafana:latest
    container_name: be-grafana
    networks: [be-net]
    ports: ["3000:3000"]
    environment:
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_ADMIN_PASSWORD:?}
      GF_AUTH_ANONYMOUS_ENABLED: "false"
    volumes: [grafana_data:/var/lib/grafana]
    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://localhost:3000/api/health || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
```

- [ ] **步骤 4：写 `infra/traefik/traefik.yml`**

```yaml
# Traefik v3 静态配置。路由 labels 由 be-ops 产出到容器上，Docker Provider 读取（§6.3）
global:
  checkNewVersion: false
  sendAnonymousUsage: false

api:
  dashboard: true
  insecure: true      # 仅开发环境。生产用 ForwardAuth 保护

ping:
  entryPoint: traefik  # `traefik healthcheck --ping` 靠这个

entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
  traefik:
    address: ":18080"   # 本计划 §1.2：从 8080 挪开，让给外壳一的 mdm-customer

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: be-net     # 与三份 compose 共用的 external network（§13.8.3）

log:
  level: INFO

accessLog: {}
```

- [ ] **步骤 5：写 `infra/casdoor/conf/app.conf`**

```ini
appname = casdoor
httpport = 8000
runmode = dev
copyrequestbody = true
driverName = postgres
dataSourceName = "user=postgres password=${POSTGRES_PASSWORD} host=be-postgres port=5432 sslmode=disable dbname=brickkit_db search_path=casdoor"
dbName =
tableNamePrefix =
showSql = false
redisEndpoint =
defaultStorageProvider =
isCloudIntranet = false
authState = "casdoor"
socks5Proxy = ""
verificationCodeTimeout = 10
initScore = 0
logPostOnly = true
origin = "http://localhost"
staticBaseUrl = "https://cdn.casbin.org"
```

⚠️ **Casdoor 用自己的 schema `casdoor`，与 61 个组件的 schema 平级**（§2.7.2 ④）。`search_path=casdoor` 这一格必须有，否则它会往 `public` 建表，和迁移状态表打架（§11.2.3）。

- [ ] **步骤 6：写 `infra/otel/config.yaml`、`infra/prometheus/prometheus.yml`、`infra/tempo/tempo.yaml`**

```yaml
# infra/otel/config.yaml
receivers:
  otlp:
    protocols:
      grpc: { endpoint: 0.0.0.0:4317 }
      http: { endpoint: 0.0.0.0:4318 }

processors:
  batch: { timeout: 5s, send_batch_size: 1024 }
  memory_limiter: { check_interval: 1s, limit_percentage: 60, spike_limit_percentage: 20 }

exporters:
  prometheusremotewrite:
    endpoint: http://be-prometheus:9090/api/v1/write
  otlphttp/tempo:
    endpoint: http://be-tempo:4318
  otlphttp/loki:
    endpoint: http://be-loki:3100/otlp

extensions:
  health_check: { endpoint: 0.0.0.0:13133 }

service:
  extensions: [health_check]
  pipelines:
    traces:  { receivers: [otlp], processors: [memory_limiter, batch], exporters: [otlphttp/tempo] }
    metrics: { receivers: [otlp], processors: [memory_limiter, batch], exporters: [prometheusremotewrite] }
    logs:    { receivers: [otlp], processors: [memory_limiter, batch], exporters: [otlphttp/loki] }
```

```yaml
# infra/prometheus/prometheus.yml
global:
  scrape_interval: 15s      # §7.4：本地部署的资源克制，15s 不许再调小
  evaluation_interval: 15s

storage:
  tsdb:
    out_of_order_time_window: 5m

scrape_configs:
  # §7.5.1 被动抓取：靠平台的 labels 透传（prometheus.io/scrape 等）
  - job_name: docker-containers
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 30s
    relabel_configs:
      - source_labels: [__meta_docker_container_label_prometheus_io_scrape]
        regex: "true"
        action: keep
      - source_labels: [__address__, __meta_docker_container_label_prometheus_io_port]
        regex: "([^:]+)(?::\\d+)?;(\\d+)"
        replacement: "$1:$2"
        target_label: __address__
      - source_labels: [__meta_docker_container_label_prometheus_io_path]
        regex: "(.+)"
        target_label: __metrics_path__
      - source_labels: [__meta_docker_container_name]
        target_label: container
```

⚠️ Prometheus 的 Docker Provider 也需要挂 `docker.sock`。这一段在步骤 3 的 `prometheus` service 里补上 `- /var/run/docker.sock:/var/run/docker.sock:ro`。

```yaml
# infra/tempo/tempo.yaml
server:
  http_listen_port: 3200

distributor:
  receivers:
    otlp:
      protocols:
        http: { endpoint: 0.0.0.0:4318 }
        grpc: { endpoint: 0.0.0.0:4317 }

storage:
  trace:
    backend: local
    local: { path: /var/tempo/traces }
    wal:   { path: /var/tempo/wal }
```

- [ ] **步骤 7：写 `.env.example` 并把 `.env` 加进 `.gitignore`（已在）**

```bash
# .env.example —— 复制为 .env 并填上真值。.env 已在 .gitignore 里
POSTGRES_PASSWORD=change_me_pg
STORAGE_ACCESS_KEY=brickkit
STORAGE_SECRET_KEY=change_me_storage
MQ_USER=brickkit
MQ_PASSWORD=change_me_mq
KEYCLOAK_ADMIN_PASSWORD=change_me_kc
GRAFANA_ADMIN_PASSWORD=change_me_grafana
```

⚠️ 上面所有 compose 里用的都是 `${VAR:?错误提示}` 形态，**不是 `${VAR:-默认值}`**。理由：默认密码在私有化交付里会被原样带到客户现场（§9.4）。缺变量时 compose 当场报错，比悄悄用 `brickkit_dev` 强。

- [ ] **步骤 8：校准三个镜像的实际环境变量名**

RustFS / Kafka / Casdoor 三个镜像的环境变量名以官方镜像实际为准，本计划给的是按惯例写的。逐个核对：

```bash
docker run --rm rustfs/rustfs:latest --help 2>&1 | head -40
docker run --rm casbin/casdoor:latest ls /conf 2>&1 | head
docker run --rm confluentinc/cp-kafka:latest bash -c 'env | sort' 2>&1 | head -20
```

对不上就改 compose，**并在本任务的 commit message 里写明改了哪个变量名**——半年后有人会想知道为什么和设计书附录 G 不一样。

- [ ] **步骤 9：commit**

```bash
git add infra .env.example .gitignore
git commit -m "feat(infra): 基础资源两份 compose + 声明式资源表

- 默认 5 个容器（PG16 / NATS JetStream / Traefik / Casdoor / RustFS）
- 5 个可选替换件走 compose profile
- 可观测性 5 件套独立项目 be-obs，要就整套（设计书 §2.7.3）
- 修正设计书附录 G 的四处端口撞车：Traefik Dashboard→18080、
  Keycloak→18081、Prometheus→19090、Kafka→19092（本计划 §1.2）
- 三份 compose 共用 external network be-net（设计书 §13.8.3）"
```

**验证：**

```bash
docker network create be-net 2>/dev/null || true
cp .env.example .env   # 填上真值
docker compose -f infra/docker-compose.infra.yml config >/dev/null && echo "infra compose 语法 OK"
docker compose -f infra/docker-compose.observability.yml config >/dev/null && echo "obs compose 语法 OK"
awk -F'\t' 'NF && $1 !~ /^#/ {print NF}' infra/resources.tsv | sort -u
```
期望：两行 `... OK`；最后一条只输出 `10`（每行都是 10 列，没有漏制表符）。

---

#### Task 2：`make check` —— 一键查询基础资源状态

**Files:**
- Create: `infra/scripts/lib.sh`
- Create: `infra/scripts/check.sh`
- Create: `Makefile`

**Interfaces:**
- Consumes：Task 1 的 `infra/resources.tsv`（10 列制表符格式）。
- Produces：`infra/scripts/lib.sh` 导出 `read_rows <mode>`（mode ∈ `default` / `all` / `<name>` / `profile:<p>`）、`row_field <row> <col>`、`port_owner <port> <self_container>`、`ensure_net`。Task 3 复用这四个。
- Produces：`check.sh <mode>` 退出码 —— 0 全绿，1 有 `✗`（镜像/端口/健康不符或端口被占）。`缺失` 不算 `✗`（那是「还没开」，不是「不对」）。

- [ ] **步骤 1：写 `infra/scripts/lib.sh`**

```bash
#!/usr/bin/env bash
# 基础资源脚本公用函数。判据真相源是 infra/resources.tsv
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TSV="$ROOT/infra/resources.tsv"
NET="be-net"

C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'

die() { printf '%s\n' "${C_RED}✗ $*${C_OFF}" >&2; exit 1; }

# 列名 → 序号。改 tsv 列顺序时只改这里
col_of() {
  case "$1" in
    name) echo 1;; project) echo 2;; compose_file) echo 3;; service) echo 4;;
    container) echo 5;; image) echo 6;; host_ports) echo 7;; default) echo 8;;
    profile) echo 9;; mutex) echo 10;;
    *) die "未知列名：$1";;
  esac
}

# row_field "<制表符分隔的一行>" <列名>
row_field() {
  local row="$1" idx; idx="$(col_of "$2")"
  printf '%s' "$row" | cut -d$'\t' -f"$idx"
}

# read_rows <mode>  →  逐行输出匹配的 tsv 行
#   default      仅 default=yes
#   all          全部
#   profile:<p>  该 profile 的全部
#   <name>       单个资源
read_rows() {
  local mode="$1"
  [[ -f "$TSV" ]] || die "找不到 $TSV"
  while IFS= read -r row; do
    [[ -z "$row" || "$row" == \#* ]] && continue
    local name def prof
    name="$(row_field "$row" name)"
    def="$(row_field "$row" default)"
    prof="$(row_field "$row" profile)"
    case "$mode" in
      default)   [[ "$def" == yes ]] && printf '%s\n' "$row";;
      all)       printf '%s\n' "$row";;
      profile:*) [[ "$prof" == "${mode#profile:}" ]] && printf '%s\n' "$row";;
      *)         [[ "$name" == "$mode" ]] && printf '%s\n' "$row";;
    esac
  done < "$TSV"
}

# port_owner <宿主机端口> <自己的容器名>  →  占用者描述，空表示没人占
port_owner() {
  local port="$1" self="$2" owner=""
  owner="$(docker ps --format '{{.Names}}\t{{.Ports}}' 2>/dev/null \
           | awk -F'\t' -v p=":$port->" -v self="$self" \
                 '$2 ~ p && $1 != self {print "容器 " $1; exit}')"
  if [[ -z "$owner" ]] && command -v ss >/dev/null 2>&1; then
    owner="$(ss -ltnpH 2>/dev/null \
             | awk -v p=":$port$" '$4 ~ p {print "宿主机进程 " $6; exit}')"
  fi
  printf '%s' "$owner"
}

ensure_net() {
  if ! docker network inspect "$NET" >/dev/null 2>&1; then
    docker network create "$NET" >/dev/null
    printf '%s\n' "${C_DIM}已创建 external network $NET${C_OFF}"
  fi
}

net_ok() { docker network inspect "$NET" >/dev/null 2>&1; }
```

- [ ] **步骤 2：写 `infra/scripts/check.sh`**

```bash
#!/usr/bin/env bash
# make check / make check-all 的实现。只读，不改任何状态
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MODE="${1:-default}"
FAIL=0

printf '%-16s %-34s %-22s %s\n' "资源" "镜像" "端口" "状态"
printf '%s\n' "$(printf '─%.0s' {1..100})"

while IFS= read -r row; do
  name="$(row_field "$row" name)"
  cont="$(row_field "$row" container)"
  want_img="$(row_field "$row" image)"
  want_ports="$(row_field "$row" host_ports)"
  is_def="$(row_field "$row" default)"

  # 容器存在吗
  if ! docker inspect "$cont" >/dev/null 2>&1; then
    # 不存在时也要查端口有没有被别人占——这是「一键开启会不会失败」的预告
    squat=""
    IFS=',' read -ra ps <<< "$want_ports"
    for p in "${ps[@]}"; do
      o="$(port_owner "$p" "$cont")"
      [[ -n "$o" ]] && squat+="${p} 被 ${o}; "
    done
    if [[ -n "$squat" ]]; then
      printf '%-16s %-34s %-22s %s\n' "$name" "$want_img" "$want_ports" \
        "${C_RED}✗ 端口被占：${squat%; }${C_OFF}"
      FAIL=1
    elif [[ "$is_def" == yes ]]; then
      printf '%-16s %-34s %-22s %s\n' "$name" "$want_img" "$want_ports" \
        "${C_YEL}○ 缺失（make up 会拉起）${C_OFF}"
    else
      printf '%-16s %-34s %-22s %s\n' "$name" "$want_img" "$want_ports" \
        "${C_DIM}－ 未启用（可选）${C_OFF}"
    fi
    continue
  fi

  # 镜像对不对
  got_img="$(docker inspect -f '{{.Config.Image}}' "$cont")"
  msgs=()
  if [[ "$got_img" != "$want_img" ]]; then
    msgs+=("镜像不符：实际 ${got_img}")
  fi

  # 端口对不对
  mapfile -t published < <(docker port "$cont" 2>/dev/null | sed 's/.*:\([0-9]\+\)$/\1/' | sort -u)
  IFS=',' read -ra ps <<< "$want_ports"
  for p in "${ps[@]}"; do
    if ! printf '%s\n' "${published[@]}" | grep -qx "$p"; then
      msgs+=("端口 ${p} 未发布")
    fi
  done

  # 健康与运行状态
  state="$(docker inspect -f '{{.State.Status}}' "$cont")"
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cont")"
  [[ "$state" != running ]] && msgs+=("状态 ${state}")
  [[ "$health" == unhealthy ]] && msgs+=("健康检查 unhealthy")
  [[ "$health" == starting ]] && msgs+=("健康检查仍在 starting")

  if ((${#msgs[@]})); then
    printf '%-16s %-34s %-22s %s\n' "$name" "$want_img" "$want_ports" \
      "${C_RED}✗ $(IFS='；'; echo "${msgs[*]}")${C_OFF}"
    FAIL=1
  else
    printf '%-16s %-34s %-22s %s\n' "$name" "$want_img" "$want_ports" \
      "${C_GRN}✓ healthy${C_OFF}"
  fi
done < <(read_rows "$MODE")

printf '%s\n' "$(printf '─%.0s' {1..100})"
if net_ok; then
  printf 'network be-net  %s\n' "${C_GRN}✓${C_OFF}"
else
  printf 'network be-net  %s\n' "${C_RED}✗ 不存在（跑 make net）${C_OFF}"; FAIL=1
fi

if ((FAIL)); then
  cat <<'HINT'

✗ 有资源不符。本项目不会替你 stop / rm 任何容器——请自己排查后重跑：
    docker ps -a --filter name=be-
    docker logs --tail 50 <容器名>
  端口被非本项目容器占用时，先确认那个容器是不是别的项目在用。
HINT
  exit 1
fi
printf '\n%s\n' "${C_GRN}✓ 全部基础资源就绪${C_OFF}"
```

- [ ] **步骤 3：写 `Makefile`（第一版，只到 check）**

```makefile
# BrickEnterprise 基础资源一键管理。判据真相源：infra/resources.tsv
SHELL := /usr/bin/env bash
S     := infra/scripts

.DEFAULT_GOAL := help
.PHONY: help net check check-all

help:  ## 列出所有目标
	@awk 'BEGIN{FS=":.*##"; printf "\n用法: make <目标>\n\n"} \
	     /^[a-zA-Z0-9_-]+:.*##/ {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2} \
	     /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0,5)}' $(MAKEFILE_LIST)
	@echo ""

##@ 基础资源
net:  ## 幂等创建 external network be-net
	@source $(S)/lib.sh && ensure_net

check: net  ## 一键查询：默认基础资源是否全部就绪
	@bash $(S)/check.sh default

check-all: net  ## 同上，把已启用的可选资源一起查
	@bash $(S)/check.sh all
```

- [ ] **步骤 4：跑 `make check`，确认它在**本机当前状态下**报出预期的错**

```bash
chmod +x infra/scripts/*.sh
make check
```

期望输出（本机 2026-09-02 的状态）：
- `postgres` 行 → `✗ 端口被占：5432 被 容器 my-postgres`
- `rustfs` 行 → `✗ 端口被占：9000 被 容器 my-rustfs`
- `nats` / `traefik` / `casdoor` 行 → `○ 缺失（make up 会拉起）`
- 末尾 → 非零退出码 + 排查提示

**这就是「报错让你自己去排查」的样子。** 看到这个输出才算本步骤通过——如果 `make check` 一片绿，说明端口占用检测没生效，回步骤 1 检查 `port_owner`。

- [ ] **步骤 5：commit**

```bash
git add Makefile infra/scripts
git commit -m "feat(make): make check 一键查询基础资源

五项判据：容器在不在 / 镜像 tag / 发布端口 / 健康状态 / be-net。
端口被非本项目容器或宿主机进程占用时点名占用者，不做任何 stop/rm。"
```

**验证：** `make check; echo "exit=$?"` → 端口冲突未解决时 `exit=1` 且输出里点名了 `my-postgres` 与 `my-rustfs`。

---

#### Task 3：`make up` 与单个可选资源的开关

**Files:**
- Create: `infra/scripts/up.sh`
- Create: `infra/scripts/optional.sh`
- Modify: `Makefile`

**Interfaces:**
- Consumes：Task 2 的 `lib.sh`（`read_rows` / `row_field` / `port_owner` / `ensure_net`）与 `check.sh` 的退出码语义。
- Produces：`up.sh` 的两阶段契约 —— **阶段一整体预检，任一默认资源判为 `✗` 就 exit 1 且一个容器都不启动**；阶段二才 `docker compose up -d --wait`。
- Produces：`optional.sh <name|obs> up|down`，`up` 前做互斥组校验。

- [ ] **步骤 1：写 `infra/scripts/up.sh`**

```bash
#!/usr/bin/env bash
# make up 的实现。两阶段：先整体预检，全过才启动。已就绪的跳过，不符的报错中止
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ensure_net

# ── 阶段一：整体预检 ───────────────────────────────────────────
# 只有「不符」才拦（镜像/端口/健康/端口被占）；「缺失」是正常的，那正是要启动的
echo "▸ 阶段一：预检"
BLOCK=0
while IFS= read -r row; do
  name="$(row_field "$row" name)"
  cont="$(row_field "$row" container)"
  want_img="$(row_field "$row" image)"
  want_ports="$(row_field "$row" host_ports)"

  if docker inspect "$cont" >/dev/null 2>&1; then
    got_img="$(docker inspect -f '{{.Config.Image}}' "$cont")"
    if [[ "$got_img" != "$want_img" ]]; then
      echo "  ${C_RED}✗ ${name}：镜像不符${C_OFF}  期望 ${want_img} / 实际 ${got_img}"
      BLOCK=1
    fi
    mapfile -t published < <(docker port "$cont" 2>/dev/null | sed 's/.*:\([0-9]\+\)$/\1/' | sort -u)
    IFS=',' read -ra ps <<< "$want_ports"
    for p in "${ps[@]}"; do
      printf '%s\n' "${published[@]}" | grep -qx "$p" || {
        echo "  ${C_RED}✗ ${name}：端口 ${p} 未发布${C_OFF}"; BLOCK=1; }
    done
    health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cont")"
    [[ "$health" == unhealthy ]] && {
      echo "  ${C_RED}✗ ${name}：健康检查 unhealthy${C_OFF}"; BLOCK=1; }
  else
    IFS=',' read -ra ps <<< "$want_ports"
    for p in "${ps[@]}"; do
      o="$(port_owner "$p" "$cont")"
      [[ -n "$o" ]] && {
        echo "  ${C_RED}✗ ${name}：端口 ${p} 已被 ${o} 占用${C_OFF}"; BLOCK=1; }
    done
  fi
done < <(read_rows default)

if ((BLOCK)); then
  cat <<'HINT'

✗ 预检未通过，一个容器都没有启动（避免半开状态）。
  本项目不会替你 stop / rm 任何容器。请自己排查后重跑 make up：
    docker ps -a --filter name=be-
    docker logs --tail 50 <容器名>
HINT
  exit 1
fi
echo "  ${C_GRN}✓ 预检通过${C_OFF}"

# ── 阶段二：启动。compose up -d 对已就绪的容器是幂等的，不会重建 ──
echo "▸ 阶段二：启动"
docker compose -p be-infra -f infra/docker-compose.infra.yml up -d --wait --wait-timeout 180 \
  || die "compose up 失败。跑 make status 与 docker logs 看是哪个"

echo "▸ 阶段三：复检"
exec bash "$(dirname "${BASH_SOURCE[0]}")/check.sh" default
```

⚠️ **为什么预检要独立一遍、而不是直接 `compose up`**：`compose up` 在配置变了的时候会**静默重建容器**。已经跑着 `postgres:15` 的容器，`compose up` 会把它 recreate 成 16——数据目录不兼容，PG 起不来，而你以为只是「重启了一下」。预检把这种情况拦在启动之前。

- [ ] **步骤 2：写 `infra/scripts/optional.sh`**

```bash
#!/usr/bin/env bash
# make <res>-up / <res>-down 的实现。res 是单个资源名，或组名 obs
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TARGET="${1:?用法：optional.sh <资源名|obs> <up|down>}"
ACTION="${2:?用法：optional.sh <资源名|obs> <up|down>}"

# 解析成一批行：obs 是 profile 组，其余是单个资源名
if [[ "$TARGET" == obs ]]; then
  mapfile -t ROWS < <(read_rows "profile:obs")
else
  mapfile -t ROWS < <(read_rows "$TARGET")
fi
((${#ROWS[@]})) || die "resources.tsv 里没有 ${TARGET}"

# 可选资源专用。默认资源请用 make up / make down
for row in "${ROWS[@]}"; do
  [[ "$(row_field "$row" default)" == no ]] \
    || die "${TARGET} 是默认资源，请用 make up / make down"
done

PROJECT="$(row_field "${ROWS[0]}" project)"
FILE="$(row_field "${ROWS[0]}" compose_file)"
PROFILE="$(row_field "${ROWS[0]}" profile)"

if [[ "$ACTION" == up ]]; then
  ensure_net

  # ── 互斥校验：同一 mutex 组里已经有别的成员在跑就报错 ──
  for row in "${ROWS[@]}"; do
    grp="$(row_field "$row" mutex)"; me="$(row_field "$row" name)"
    [[ "$grp" == "-" ]] && continue
    while IFS= read -r other; do
      oname="$(row_field "$other" name)"
      ocont="$(row_field "$other" container)"
      [[ "$oname" == "$me" || "$(row_field "$other" mutex)" != "$grp" ]] && continue
      if [[ "$(docker inspect -f '{{.State.Status}}' "$ocont" 2>/dev/null)" == running ]]; then
        die "${me} 与 ${oname} 属于同一互斥组「${grp}」，同一环境只能装一个。
   先关掉它：make ${oname}-down（若它是默认资源，说明你要换的是默认实现，
   还要同步改 brickkit.yaml 的 resources[].engine 或那份 compose）"
      fi
    done < <(read_rows all)
  done

  # ── 端口预检 ──
  for row in "${ROWS[@]}"; do
    cont="$(row_field "$row" container)"
    IFS=',' read -ra ps <<< "$(row_field "$row" host_ports)"
    for p in "${ps[@]}"; do
      o="$(port_owner "$p" "$cont")"
      [[ -n "$o" ]] && die "$(row_field "$row" name)：端口 ${p} 已被 ${o} 占用"
    done
  done

  svcs=(); for row in "${ROWS[@]}"; do svcs+=("$(row_field "$row" service)"); done
  docker compose -p "$PROJECT" -f "$FILE" --profile "$PROFILE" \
    up -d --wait --wait-timeout 180 "${svcs[@]}" \
    || die "启动 ${TARGET} 失败"
  echo "${C_GRN}✓ ${TARGET} 已开启${C_OFF}"

elif [[ "$ACTION" == down ]]; then
  svcs=(); for row in "${ROWS[@]}"; do svcs+=("$(row_field "$row" service)"); done
  docker compose -p "$PROJECT" -f "$FILE" --profile "$PROFILE" \
    rm -sf "${svcs[@]}" || die "关闭 ${TARGET} 失败"
  echo "${C_GRN}✓ ${TARGET} 已关闭（volume 保留）${C_OFF}"
else
  die "ACTION 只能是 up 或 down"
fi
```

- [ ] **步骤 3：把余下目标补进 `Makefile`**

```makefile
##@ 基础资源（续）
up: net  ## 一键开启所有默认资源（已就绪的跳过；不符的报错中止）
	@bash $(S)/up.sh

down:  ## 停止本项目所有容器（不删 volume）
	@docker compose -p be-infra -f infra/docker-compose.infra.yml --profile "*" down
	@docker compose -p be-obs   -f infra/docker-compose.observability.yml down 2>/dev/null || true
	@echo "已停止（volume 保留）"

status:  ## 查看运行状态
	@docker compose -p be-infra -f infra/docker-compose.infra.yml --profile "*" ps
	@docker compose -p be-obs   -f infra/docker-compose.observability.yml ps 2>/dev/null || true

logs:  ## 跟日志：make logs SVC=postgres
	@test -n "$(SVC)" || { echo "用法：make logs SVC=<service>"; exit 1; }
	@docker logs -f --tail 200 "be-$(SVC)"

nuke:  ## 停止并删除所有 volume（危险，需二次确认）
	@read -r -p "输入 yes-delete-my-data 确认删除全部数据卷：" c; \
	 [[ "$$c" == "yes-delete-my-data" ]] || { echo "已取消"; exit 1; }; \
	 docker compose -p be-infra -f infra/docker-compose.infra.yml --profile "*" down -v; \
	 docker compose -p be-obs   -f infra/docker-compose.observability.yml down -v 2>/dev/null || true

##@ 可选资源（单个开关）
minio-up:     ; @bash $(S)/optional.sh minio up      ## 开启 MinIO（替换 RustFS）
minio-down:   ; @bash $(S)/optional.sh minio down    ## 关闭 MinIO
keycloak-up:  ; @bash $(S)/optional.sh keycloak up   ## 开启 Keycloak（替换 Casdoor）
keycloak-down:; @bash $(S)/optional.sh keycloak down ## 关闭 Keycloak
kafka-up:     ; @bash $(S)/optional.sh kafka up      ## 开启 Kafka（替换 NATS）
kafka-down:   ; @bash $(S)/optional.sh kafka down    ## 关闭 Kafka
rabbitmq-up:  ; @bash $(S)/optional.sh rabbitmq up   ## 开启 RabbitMQ（替换 NATS）
rabbitmq-down:; @bash $(S)/optional.sh rabbitmq down ## 关闭 RabbitMQ
nginx-up:     ; @bash $(S)/optional.sh nginx up      ## 开启 Nginx（替换 Traefik）
nginx-down:   ; @bash $(S)/optional.sh nginx down    ## 关闭 Nginx
obs-up:       ; @bash $(S)/optional.sh obs up        ## 开启可观测性 5 件套（整套）
obs-down:     ; @bash $(S)/optional.sh obs down      ## 关闭可观测性 5 件套（整套）

.PHONY: up down status logs nuke \
        minio-up minio-down keycloak-up keycloak-down kafka-up kafka-down \
        rabbitmq-up rabbitmq-down nginx-up nginx-down obs-up obs-down
```

- [ ] **步骤 4：验证「一键开启」的三条语义**

先解决端口冲突（这一步归你，脚本不会替你做）：

```bash
docker stop my-postgres my-rustfs      # 或改用别的端口，你自己定
make up
```

三条语义逐条验证：

```bash
# 语义 1：幂等 —— 已就绪的不再动
make up && make up
docker inspect -f '{{.State.StartedAt}}' be-postgres   # 两次 make up 后这个值不变
```

```bash
# 语义 2：不符就报错中止，一个都不动
docker rm -f be-nats
docker run -d --name be-nats --network be-net -p 4222:4222 -p 8222:8222 nats:2.9-alpine
make up; echo "exit=$?"
# 期望：exit=1，输出「be-nats：镜像不符 期望 nats:2.10-alpine / 实际 nats:2.9-alpine」
# 且 be-traefik 等其他容器状态没有任何变化
```

```bash
# 语义 3：单个可选资源的互斥
make minio-up; echo "exit=$?"
# 期望：exit=1，输出「minio 与 rustfs 属于同一互斥组「storage」…」
make rustfs-down 2>&1 | head -2
# 期望：报错「rustfs 是默认资源，请用 make up / make down」
```

- [ ] **步骤 5：commit**

```bash
git add Makefile infra/scripts
git commit -m "feat(make): make up 两阶段启动 + 单个可选资源开关

- make up：先整体预检（镜像/端口/健康/端口占用），全过才 compose up。
  已就绪的跳过；任一不符则一个容器都不启动，避免半开状态。
- 预检必须独立一遍：compose up 在配置变了时会静默 recreate，
  跑着 postgres:15 的容器会被悄悄换成 16 而数据目录不兼容。
- make <res>-up/down：5 个替换件 + 可观测性整套。up 前做互斥组校验。"
```

**验证：** 上面步骤 4 的三条语义各自看到期望输出。

---

#### Task 4：两张全局册子落盘 + 校验脚本

**Files:**
- Create: `registry/ports.tsv`
- Create: `registry/schemas.tsv`
- Create: `registry/README.md`
- Create: `infra/scripts/registry-check.sh`
- Modify: `Makefile`

**Interfaces:**
- Produces：`registry/ports.tsv` 6 列 —— `repo` / `component_id` / `http_port` / `grpc_port` / `shell` / `note`。`grpc_port` 为 `-` 表示不暴露 gRPC。
- Produces：`registry/schemas.tsv` 4 列 —— `repo` / `schema` / `role` / `shell_login_role`。
- Produces：`registry-check.sh` 退出码 0/1。Task 8（`be-ops`）会把这个校验搬进 `be-ops`，届时本脚本改为薄壳调用 `be-ops registry check`。

⚠️ **为什么先落在本仓库而不是 `be-ops` 里**：端口册是**写第一个 `component.yaml` 之前**就必须存在的东西（§3.5.1.1：gRPC 端口没有事后补救），而 `be-ops` 仓库要到 CP-1 才建。装配根是这两张表的天然家（`be-ops` 是读它们的工具，不是它们的主人）。

- [ ] **步骤 1：写 `registry/ports.tsv`**

内容照本计划 §2.1 的六张表逐行抄，包含带外容器段。格式：

```tsv
# repo	component_id	http_port	grpc_port	shell	note
# ===== 外壳一 Go-Core =====
mdm-customer	mdm/customer	8080	9090	go-core	-
mdm-supplier	mdm/supplier	8081	9091	go-core	-
mdm-product	mdm/product	8082	9092	go-core	-
mdm-org	mdm/org	8083	9093	go-core	-
erp-sales	erp/sales	8084	9094	go-core	-
erp-purchase	erp/purchase	8085	9095	go-core	-
erp-inventory	erp/inventory	8086	9096	go-core	-
erp-finance	erp/finance	8087	9097	go-core	-
# ===== 外壳二 Go-Backoffice =====
crm-lead	crm/lead	8100	9100	go-backoffice	-
crm-customer	crm/customer	8101	9101	go-backoffice	-
crm-opportunity	crm/opportunity	8102	9102	go-backoffice	-
crm-activity	crm/activity	8103	9103	go-backoffice	-
crm-campaign	crm/campaign	8104	9104	go-backoffice	-
crm-case	crm/case	8105	9105	go-backoffice	-
hrm-attendance	hrm/attendance	8106	9106	go-backoffice	-
hrm-leave	hrm/leave	8107	9107	go-backoffice	-
hrm-expense	hrm/expense	8108	9108	go-backoffice	-
prj-project	prj/project	8109	9109	go-backoffice	-
prj-timesheet	prj/timesheet	8110	9110	go-backoffice	-
erp-asset	erp/asset	8111	9111	go-backoffice	-
erp-quality	erp/quality	8112	9112	go-backoffice	-
erp-maintenance	erp/maintenance	8113	9113	go-backoffice	-
hrm-recruitment	hrm/recruitment	8114	9114	go-backoffice	设计书§13.2原漏列，已回写
hrm-appraisal	hrm/appraisal	8115	9115	go-backoffice	设计书§13.2原漏列，已回写
# ===== 外壳三 Go-Infra =====
infra-iam-casdoor	infra/iam-casdoor	8200	9200	go-infra	设计书§13.2原漏列，已回写
infra-workflow	infra/workflow	8201	9201	go-infra	-
infra-notification	infra/notification	8202	9202	go-infra	-
infra-dlq-monitor	infra/dlq-monitor	8203	9203	go-infra	-
infra-attachment	infra/attachment	8204	9204	go-infra	-
infra-storage	infra/storage	8205	9205	go-infra	-
infra-audit	infra/audit	8206	9206	go-infra	-
integration-im-dingtalk	integration/im-dingtalk	8207	9207	go-infra	-
integration-im-wechat-work	integration/im-wechat-work	8208	9208	go-infra	-
integration-im-feishu	integration/im-feishu	8209	9209	go-infra	-
integration-im-slack	integration/im-slack	8210	9210	go-infra	-
integration-im-teams	integration/im-teams	8211	9211	go-infra	-
integration-payment-stripe	integration/payment-stripe	8212	9212	go-infra	-
integration-payment-paypal	integration/payment-paypal	8213	9213	go-infra	-
integration-payment-alipay	integration/payment-alipay	8214	9214	go-infra	-
integration-payment-wechat-pay	integration/payment-wechat-pay	8215	9215	go-infra	-
integration-esign-docusign	integration/esign-docusign	8216	9216	go-infra	-
integration-esign-pandadoc	integration/esign-pandadoc	8217	9217	go-infra	-
integration-esign-esign	integration/esign-esign	8218	9218	go-infra	-
integration-email	integration/email	8219	9219	go-infra	-
integration-sms	integration/sms	8220	9220	go-infra	-
infra-iam-keycloak	infra/iam-keycloak	8221	9221	go-infra	slot:iam替换件，与casdoor互斥
# ===== 外壳四 Py-Brain =====
hrm-payroll-es	hrm/payroll-es	8300	9300	py-brain	-
crm-commission	crm/commission	8301	9301	py-brain	-
erp-manufacturing	erp/manufacturing	8302	9302	py-brain	-
ana-bi	ana/bi	8303	9303	py-brain	-
ana-ai	ana/ai	8304	9304	py-brain	-
hrm-payroll-core	hrm/payroll-core	8305	9305	py-brain	blueprint不开发，端口预留
hrm-payroll-cn	hrm/payroll-cn	8306	9306	py-brain	blueprint不开发，端口预留
hrm-payroll-us	hrm/payroll-us	8307	9307	py-brain	blueprint不开发，端口预留
# ===== 外壳五 Py-Render =====
infra-print	infra/print	8400	9400	py-render	-
integration-edi	integration/edi	8401	9401	py-render	-
# ===== 独立容器 =====
infra-bff-mobile	infra/bff-mobile	8500	-	standalone	GraphQL over HTTP，不暴露gRPC
frontend-standard	frontend/standard	80	-	standalone	slot:frontend族共用80，见下
frontend-advanced	frontend/advanced	80	-	standalone	同上，槽位互斥永不共存
frontend-industry	frontend/{industry}	80	-	standalone	同上
frontend-customer	frontend/{customer}	80	-	standalone	同上，Fork件
# ===== 带外容器与基础资源（设计书的端口册原本只管61个组件，已回写补入）=====
_infra-postgres	-	5432	-	out-of-band	-
_infra-nats	-	4222	-	out-of-band	监控口8222
_infra-traefik	-	80	-	out-of-band	443；Dashboard18080（原8080撞mdm-customer，已回写设计书）
_infra-casdoor	-	8000	-	out-of-band	-
_infra-rustfs	-	9000	-	out-of-band	-
_infra-minio	-	9000	-	out-of-band	9001；与rustfs互斥
_infra-keycloak	-	18081	-	out-of-band	原8080撞mdm-customer，已回写设计书
_infra-kafka	-	19092	-	out-of-band	原9092撞mdm-product的gRPC，已回写设计书
_infra-rabbitmq	-	5672	-	out-of-band	15672
_infra-nginx	-	80	-	out-of-band	443；与traefik互斥
_infra-otel	-	4317	-	out-of-band	4318、13133
_infra-prometheus	-	19090	-	out-of-band	原9090撞mdm-customer的gRPC，已回写设计书
_infra-loki	-	3100	-	out-of-band	-
_infra-tempo	-	3200	-	out-of-band	-
_infra-grafana	-	3000	-	out-of-band	-
```

- [ ] **步骤 2：写 `registry/schemas.tsv`**

```tsv
# repo	schema	role	shell_login_role
mdm-customer	mdm_customer	mdm_customer_rw	shell_go_core
mdm-supplier	mdm_supplier	mdm_supplier_rw	shell_go_core
mdm-product	mdm_product	mdm_product_rw	shell_go_core
mdm-org	mdm_org	mdm_org_rw	shell_go_core
erp-sales	erp_sales	erp_sales_rw	shell_go_core
erp-purchase	erp_purchase	erp_purchase_rw	shell_go_core
erp-inventory	erp_inventory	erp_inventory_rw	shell_go_core
erp-finance	erp_finance	erp_finance_rw	shell_go_core
crm-lead	crm_lead	crm_lead_rw	shell_go_backoffice
crm-customer	crm_customer	crm_customer_rw	shell_go_backoffice
crm-opportunity	crm_opportunity	crm_opportunity_rw	shell_go_backoffice
crm-activity	crm_activity	crm_activity_rw	shell_go_backoffice
crm-campaign	crm_campaign	crm_campaign_rw	shell_go_backoffice
crm-case	crm_case	crm_case_rw	shell_go_backoffice
hrm-attendance	hrm_attendance	hrm_attendance_rw	shell_go_backoffice
hrm-leave	hrm_leave	hrm_leave_rw	shell_go_backoffice
hrm-expense	hrm_expense	hrm_expense_rw	shell_go_backoffice
hrm-recruitment	hrm_recruitment	hrm_recruitment_rw	shell_go_backoffice
hrm-appraisal	hrm_appraisal	hrm_appraisal_rw	shell_go_backoffice
prj-project	prj_project	prj_project_rw	shell_go_backoffice
prj-timesheet	prj_timesheet	prj_timesheet_rw	shell_go_backoffice
erp-asset	erp_asset	erp_asset_rw	shell_go_backoffice
erp-quality	erp_quality	erp_quality_rw	shell_go_backoffice
erp-maintenance	erp_maintenance	erp_maintenance_rw	shell_go_backoffice
infra-iam-casdoor	infra_iam_casdoor	infra_iam_casdoor_rw	shell_go_infra
infra-iam-keycloak	infra_iam_keycloak	infra_iam_keycloak_rw	shell_go_infra
infra-workflow	infra_workflow	infra_workflow_rw	shell_go_infra
infra-notification	infra_notification	infra_notification_rw	shell_go_infra
infra-dlq-monitor	infra_dlq_monitor	infra_dlq_monitor_rw	shell_go_infra
infra-attachment	infra_attachment	infra_attachment_rw	shell_go_infra
infra-storage	infra_storage	infra_storage_rw	shell_go_infra
infra-audit	infra_audit	infra_audit_rw	shell_go_infra
integration-im-dingtalk	integration_im_dingtalk	integration_im_dingtalk_rw	shell_go_infra
integration-im-wechat-work	integration_im_wechat_work	integration_im_wechat_work_rw	shell_go_infra
integration-im-feishu	integration_im_feishu	integration_im_feishu_rw	shell_go_infra
integration-im-slack	integration_im_slack	integration_im_slack_rw	shell_go_infra
integration-im-teams	integration_im_teams	integration_im_teams_rw	shell_go_infra
integration-payment-stripe	integration_payment_stripe	integration_payment_stripe_rw	shell_go_infra
integration-payment-paypal	integration_payment_paypal	integration_payment_paypal_rw	shell_go_infra
integration-payment-alipay	integration_payment_alipay	integration_payment_alipay_rw	shell_go_infra
integration-payment-wechat-pay	integration_payment_wechat_pay	integration_payment_wechat_pay_rw	shell_go_infra
integration-esign-docusign	integration_esign_docusign	integration_esign_docusign_rw	shell_go_infra
integration-esign-pandadoc	integration_esign_pandadoc	integration_esign_pandadoc_rw	shell_go_infra
integration-esign-esign	integration_esign_esign	integration_esign_esign_rw	shell_go_infra
integration-email	integration_email	integration_email_rw	shell_go_infra
integration-sms	integration_sms	integration_sms_rw	shell_go_infra
hrm-payroll-es	hrm_payroll_es	hrm_payroll_es_rw	shell_py_brain
crm-commission	crm_commission	crm_commission_rw	shell_py_brain
erp-manufacturing	erp_manufacturing	erp_manufacturing_rw	shell_py_brain
ana-bi	ana_bi	ana_bi_rw	shell_py_brain
ana-ai	ana_ai	ana_ai_rw	shell_py_brain
infra-print	infra_print	infra_print_rw	shell_py_render
integration-edi	integration_edi	integration_edi_rw	shell_py_render
# 以下不建 schema
# infra-bff-mobile   严禁直连DB（§6.5）
# frontend-*         无数据
# hrm-payroll-core/cn/us  blueprint不开发
# 非组件 schema：casdoor（Casdoor官方镜像自用）、keycloak（换槽时用）
```

⚠️ 每个组件同时还有 `{schema}_archive` 归档 schema（§11.5.4），由建库脚本与主 schema 同批创建，**不在本表另列一行**——它由 `schema` 列机械派生，另列一行只会多一处可能写错的地方。

- [ ] **步骤 3：写 `infra/scripts/registry-check.sh`**

```bash
#!/usr/bin/env bash
# 端口册与 schema 册的自洽校验。Task 8 之后由 be-ops 接管，本脚本改为薄壳
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P="$ROOT/registry/ports.tsv"; S="$ROOT/registry/schemas.tsv"
FAIL=0
err() { echo "✗ $*" >&2; FAIL=1; }

# 1. 列数
awk -F'\t' 'NF && $1 !~ /^#/ && NF != 6 {print "ports.tsv 第 " NR " 行不是 6 列：" $0}' "$P" | while read -r l; do err "$l"; done
awk -F'\t' 'NF && $1 !~ /^#/ && NF != 4 {print "schemas.tsv 第 " NR " 行不是 4 列：" $0}' "$S" | while read -r l; do err "$l"; done

# 2. 端口两两不重复。唯一例外：slot:frontend 族共用 80（本计划 §2.1）
dups="$(awk -F'\t' '
  NF && $1 !~ /^#/ {
    if ($3 != "-" && $3 != "80") p[$3] = p[$3] " " $1
    if ($4 != "-")               p[$4] = p[$4] " " $1
  }
  END { for (k in p) { n=split(p[k],a," "); if (n>1) print k ":" p[k] } }' "$P")"
[[ -n "$dups" ]] && err "端口重复：$dups"

# 3. 用 80 的必须全是 frontend-*
bad80="$(awk -F'\t' 'NF && $1 !~ /^#/ && $3=="80" && $1 !~ /^frontend-/ {print $1}' "$P")"
[[ -n "$bad80" ]] && err "非 frontend 组件占用 80：$bad80"

# 4. 两张表的 repo 集合关系：schemas 里的 repo 必须在 ports 里存在
while IFS=$'\t' read -r repo _ _ _; do
  [[ -z "$repo" || "$repo" == \#* ]] && continue
  grep -qP "^\Q$repo\E\t" "$P" || err "schemas.tsv 里的 $repo 不在 ports.tsv 里"
done < "$S"

# 5. schema/role 命名规则：schema = repo 的 - 换 _；role = schema + _rw
while IFS=$'\t' read -r repo schema role _; do
  [[ -z "$repo" || "$repo" == \#* ]] && continue
  want_schema="${repo//-/_}"
  [[ "$schema" == "$want_schema" ]] || err "$repo 的 schema 应为 $want_schema，实际 $schema"
  [[ "$role" == "${schema}_rw" ]]   || err "$repo 的 role 应为 ${schema}_rw，实际 $role"
done < "$S"

# 6. 组件数核对：ports.tsv 里非 _infra- 前缀的行必须正好 61 行
n="$(awk -F'\t' 'NF && $1 !~ /^#/ && $1 !~ /^_infra-/' "$P" | wc -l)"
[[ "$n" -eq 61 ]] || err "ports.tsv 里的组件行数是 $n，应为 61（设计书附录 H）"

((FAIL)) && exit 1
echo "✓ 端口册与 schema 册自洽（61 个组件 + 带外容器，端口两两不重复）"
```

- [ ] **步骤 4：跑校验，确认全绿**

```bash
chmod +x infra/scripts/registry-check.sh
make registry-check
```
期望：`✓ 端口册与 schema 册自洽（61 个组件 + 带外容器，端口两两不重复）`，exit 0。

**如果报「组件行数是 60/62」**，回步骤 1 逐段数：8 + 16 + 21 + 1(keycloak) + 5 + 3(blueprint) + 2 + 1(bff) + 4(frontend) = 61。

- [ ] **步骤 5：写 `registry/README.md`**

```markdown
# 全局册子

这两张表是**写任何 `component.yaml` 之前必须来查的东西**。

| 文件 | 是什么 | 为什么必须提前定死 |
|---|---|---|
| `ports.tsv` | 61 个组件的 HTTP + gRPC 端口 **+ 带外容器端口** | gRPC 等额外端口**没有任何事后补救手段**：平台改写地址时明确跳过额外端口，两个 `local: true` 组件撞同一额外端口时 `brickkit up` 在生成阶段硬报错（设计书 §3.5.1.1）。写到第 30 个组件才发现要回头改前 29 份 Manifest |
| `schemas.tsv` | 每组件的 PG schema / Role / 所属外壳登录角色 | 库一旦按「一组件一 database」建好、数据进去了，再改成一库多 schema 就是一次数据迁移（设计书决策 3、`006` §9.5） |

## 改这两张表的规矩

1. **只增不改。** 已分配的端口/schema 不许改——改了就是所有依赖方的 `*_ENDPOINT` 换值。
2. 改完必须跑 `make registry-check`。
3. `ports.tsv` 里 `_infra-` 前缀的行是**带外容器**，不是组件。设计书的端口册只管 61 个组件，本项目把带外容器一起纳进来——因为外壳必须把端口发布到宿主机（§13.1），两边会真撞。
4. 唯一的端口复用例外是 `slot:frontend` 族共用 80（槽位互斥、永不共存、各自独立 Nginx 容器不进外壳）。校验脚本对此有专门放行。
```

- [ ] **步骤 6：把目标加进 `Makefile` 并 commit**

```makefile
##@ 全局册子
registry-check:  ## 校验端口册与 schema 册自洽
	@bash $(S)/registry-check.sh
.PHONY: registry-check
```

```bash
git add registry infra/scripts/registry-check.sh Makefile
git commit -m "feat(registry): 全局端口册与 schema 册 + 自洽校验

- 61 个组件的 HTTP/gRPC 端口两两不重复，唯一例外是 slot:frontend 族共用 80
- 带外容器端口一并纳入（设计书的端口册只管 61 个组件，但外壳要把端口
  发布到宿主机，两边会真撞：Traefik 8080 / Prometheus 9090 / Kafka 9092）
- 补设计书 §13.2 两处漏列：外壳二漏 hrm-recruitment/appraisal，
  外壳三漏 infra-iam-casdoor（补上后 21 这个数字才对得上）
- schema/role 命名机械派生，校验脚本逐条比对"
```

**验证：** `make registry-check && echo OK` → `✓ ... ` + `OK`。

---

#### Task 5：军火库骨架 —— `components/` 取消忽略、submodule 自洽闸门

**Files:**
- Modify: `.gitignore`
- Create: `infra/scripts/arsenal.sh`
- Create: `.githooks/pre-commit`
- Create: `docs/军火库维护手册.md`
- Modify: `Makefile`

**Interfaces:**
- Produces：`arsenal.sh check|restore` —— `check` 退出码 0/1（判据见 §3.4 的状态表）；`restore` 把 `enabled` 与目录结构还原到与 `brickkit.yaml` 一致。
- Produces：`.githooks/pre-commit` 调 `arsenal.sh check`，靠 `git config core.hooksPath .githooks` 生效。

- [ ] **步骤 1：改 `.gitignore` —— 只忽略归档区，不忽略 `components/`**

把这一段：

```gitignore
# 组件源码目录（每个组件是独立的 Git 仓库，不提交到项目仓库）
components/
```

换成：

```gitignore
# 组件源码目录：本项目用 git submodule 记住每个组件仓库的地址与精确 commit，
# 所以 components/ 本身要被跟踪（.gitmodules 就是设计书 §3.4.1 要的那张
# 「客户 → 组件仓库」映射表）。只忽略 brickkit sync 的归档区。
components/.archived/
```

⚠️ **这一改动的代价必须知道**：`components/` 一旦被本仓库跟踪，`brickkit sync` 的整目录 `os.Rename` 就会在本仓库的 diff 里留下「整棵树搬家」。纪律与闸门见 §3.3。

- [ ] **步骤 2：写 `infra/scripts/arsenal.sh`**

```bash
#!/usr/bin/env bash
# 军火库自洽闸门。判据刻意抄 brickKit 那份 restore --check 的状态表，
# 等 brickkit restore 上线就把本脚本换成 `brickkit restore --check` 的薄壳
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
ACTION="${1:-check}"

C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_OFF=$'\033[0m'

# 短路 1：components/ 还在 .gitignore 里（默认项目）→ 零成本退出
if [[ -z "$(git ls-files --cached -- components/ 2>/dev/null)" ]]; then
  echo "components/ 未被本仓库跟踪，无需检查"; exit 0
fi

# 短路 2：正在 merge/rebase 冲突中 → 放行 + 警告
if [[ -n "$(git ls-files -u 2>/dev/null)" ]]; then
  echo "⚠ 处于合并冲突中，跳过军火库检查"; exit 0
fi

# 短路 3：brickkit 不在 PATH → 放行 + 警告（不能让新人 clone 下来第一件事就提交不了）
if ! command -v brickkit >/dev/null 2>&1; then
  echo "⚠ brickkit 不在 PATH，跳过军火库检查"; exit 0
fi

# 官方命令一旦可用就直接用它，本脚本的判据立即退休
if brickkit restore --help >/dev/null 2>&1; then
  echo "▸ 检测到 brickkit restore，改用官方判据"
  case "$ACTION" in
    check)   exec brickkit restore --check;;
    restore) exec brickkit restore;;
  esac
fi

# ── 以下是 brickkit restore 上线前的本地兜底实现 ──────────────
# 从 brickkit up --dry-run 拿「这次会启动谁」。CLI 输出里每一行都带理由
if ! plan="$(brickkit up --dry-run 2>/dev/null)"; then
  echo "⚠ brickkit up --dry-run 失败（Manifest 缺失或要联网），跳过检查"; exit 0
fi

# 该跑的组件 ID（形如 mdm/customer）。--dry-run 的行首带组件 ID
mapfile -t SHOULD_RUN < <(printf '%s\n' "$plan" \
  | grep -oP '^\s*\K[a-z0-9-]+/[a-z0-9-]+(?=@)' | sort -u)

FAIL=0; TO_FIX=()
for id in "${SHOULD_RUN[@]}"; do
  active="components/${id}"
  archived="components/.archived/${id}"
  a=0; r=0
  git ls-files --cached --error-unmatch -- "$active"   >/dev/null 2>&1 && a=1
  [[ -d "$active" ]]   && a=1
  [[ -d "$archived" ]] && r=1

  if ((a && r)); then
    echo "${C_RED}✗ ${id}：两处都有源码${C_OFF}"
    echo "   活跃：${active}"
    echo "   归档：${archived}"
    echo "   平台不替你决定保留哪一份——请手工删掉不要的那一份再提交"
    FAIL=1
  elif ((!a && r)); then
    echo "${C_RED}✗ ${id}：brickkit.yaml 说它该启动，但源码在归档目录里${C_OFF}"
    echo "   即将提交的位置：${archived}"
    TO_FIX+=("$id"); FAIL=1
  fi
done

if [[ "$ACTION" == restore ]]; then
  if ((${#TO_FIX[@]})); then
    echo "▸ 跑 brickkit sync 把结构移回活跃目录"
    brickkit sync || exit 1
    echo "${C_GRN}✓ 已还原。请复查 git status 后再提交${C_OFF}"
  else
    echo "${C_GRN}✓ 结构已自洽，无需还原${C_OFF}"
  fi
  exit 0
fi

if ((FAIL)); then
  cat <<'HINT'

两条出路，按你的真实意图选：
  a) 我只是本地聚焦，忘了还原结构  →  make arsenal-restore
  b) 我就是要提交这个归档结构      →  把对应组件的 enabled: false 一起
                                      加进本次提交（那是意图声明，闸门会放行）
  c) 实在要绕                      →  git commit --no-verify（不推荐）
HINT
  exit 1
fi
echo "${C_GRN}✓ 军火库结构与 brickkit.yaml 自洽${C_OFF}"
```

- [ ] **步骤 3：写 `.githooks/pre-commit` 并启用**

```bash
#!/usr/bin/env bash
# BrickEnterprise pre-commit：军火库结构自洽闸门。
# brickkit init --hooks 上线后删掉本文件，改用官方 hook（§3.3）
exec bash "$(git rev-parse --show-toplevel)/infra/scripts/arsenal.sh" check
```

```bash
chmod +x .githooks/pre-commit infra/scripts/arsenal.sh
git config core.hooksPath .githooks
```

⚠️ `core.hooksPath` 是**本地配置，不随仓库分发**。所以必须写进 `docs/军火库维护手册.md` 的「新机器上手三步」，否则队友那边闸门等于没装。

- [ ] **步骤 4：建 `shells/` 与 `tools/` 占位目录**

```bash
mkdir -p shells tools
cat > shells/README.md <<'EOF'
# 外壳（Shell）

外壳是**我们自己造的、平台完全不知道的东西**（brickKit 明确不做，`012` §2.21）。
它可以做的事只有一件：**把 N 个进程变成 1 个进程**。

- `go/`     → be-shell-go     （外壳一/二/三，Go）
- `python/` → be-shell-python （外壳四/五，Python）

外壳**不放在 `components/` 里**——它不是 brickKit 组件，不进 `brickkit.yaml`。

外壳不许做的事（§1.5 原则二 / §13.3 铁律六）：
- ❌ 不许让两个组件模块直接互相 import
- ❌ 不许把两个组件的表放进同一个 schema、不许跨 schema JOIN
- ❌ 不许把 N 个模块的 API 合并成一个端口
- ❌ 不许在外壳里写任何业务逻辑
EOF
cat > tools/README.md <<'EOF'
# 交付关键路径上的工具（都不是 brickKit 组件）

- `be-ops/`        → 装配生成器。认领平台明确不做的 8 件事（本计划 §2.4）
- `be-acceptance/` → 验收测试。平台验收 20 条 + 业务闭环 + 拆回门禁 + import 扫描
- `be-sdk-go/`     → Go 横切基础库（SOP-L）。零业务逻辑、零组件 model
EOF
```

- [ ] **步骤 5：写 `docs/军火库维护手册.md`**

```markdown
# 军火库维护手册

## 新机器上手三步

```bash
git clone --recurse-submodules git@github.com:brickKit/be-assembly-standard.git
cd be-assembly-standard
git config core.hooksPath .githooks     # ⚠️ 这一条不随仓库分发，必须手动跑
cp .env.example .env                    # 填上真值
make up                                 # 拉起基础资源
```

已经 clone 过但漏了 submodule：`git submodule update --init --recursive`

## 日常开发循环（本地聚焦）

```bash
# 1. 只留你要动的那几个组件
#    改 brickkit.yaml：给不相关的顶层组件写 enabled: false
brickkit sync            # 其余源码收进 components/.archived/，IDE 与 grep 都清爽了

# 2. 开发、测试……

# 3. 提交前还原结构（否则 pre-commit 会拦你）
make arsenal-restore     # 把 enabled 与目录结构还原到与 brickkit.yaml 一致
git status               # 复查
git commit -m "..."
```

## 三条禁令

| 禁令 | 为什么 |
|---|---|
| **`brickkit remove` 前必须先 commit & push** | 它会**连同已归档的源码目录一起删除**（§9.4.2）。submodule 目录里有未 push 的改动时，这是数据丢失 |
| **不许改已分配的端口与 schema** | 端口册见 `registry/README.md`；gRPC 端口没有事后补救手段 |
| **不许在 Fork 件里改 `metadata.id` 或 `version`** | 改了之后所有依赖方拿到的 `*_ENDPOINT` **整个消失**——平台注入的变量名是从组件 ID 推导的。整条 Fork 机制当场垮掉（§3.4.1） |

## 找不到源码时

先看 `components/.archived/`——它以 `.` 开头，文件管理器默认隐藏（§9.4.2）。

## 加一个组件到军火库

见本计划 §3.5「仓库创建检查点的标准动作」。三步：建目录 → 停下叫人建仓库 → `git init` + push + `git submodule add`。
```

- [ ] **步骤 6：把目标加进 `Makefile` 并 commit**

```makefile
##@ 军火库
arsenal-check:  ## 检查 submodule 结构与 brickkit.yaml 是否自洽
	@bash $(S)/arsenal.sh check

arsenal-restore:  ## 把 enabled 与目录结构还原到与 brickkit.yaml 一致
	@bash $(S)/arsenal.sh restore
.PHONY: arsenal-check arsenal-restore
```

```bash
git add .gitignore .githooks infra/scripts/arsenal.sh shells tools docs Makefile
git commit -m "feat(arsenal): components/ 改为 submodule 跟踪 + 自洽闸门

- .gitignore 只忽略 components/.archived/，不再忽略 components/。
  .gitmodules 成为设计书 §3.4.1 要的那张「组件→仓库→精确commit」映射表。
- arsenal.sh 的判据刻意抄 brickKit 正在补的 restore --check 状态表；
  检测到官方 brickkit restore 可用时自动改用官方判据，本地兜底立即退休。
- pre-commit hook 拦「yaml 说该跑、而源码提交在归档目录里」这一个失误。
  core.hooksPath 不随仓库分发，已写进维护手册的上手三步。"
```

**验证：**

```bash
make arsenal-check          # 期望：components/ 里还没有 submodule → 短路退出 0
git config core.hooksPath   # 期望：.githooks
```

---

#### Task 6：`be-ops` / `be-acceptance` / `be-sdk-go` 骨架 → **检查点 CP-1**

**Files:**
- Create: `tools/be-ops/{go.mod,cmd/be-ops/main.go,internal/registry/registry.go,Makefile,README.md}`
- Create: `tools/be-acceptance/{go.mod,Makefile,README.md,platform/,closedloop/,gates/}`
- Create: `tools/be-sdk-go/{go.mod,Makefile,README.md,endpoint.go,tx.go,outbox.go,events.go,otel.go,query.go,archive.go,logging.go,metrics.go}`

**Interfaces:**
- Produces：`be-sdk-go` 的公开 API（档 0 起所有 Go 组件都依赖它，签名一旦定下就是契约）：

```go
package besdk

// Endpoint 读平台注入的 *_ENDPOINT 并剥掉 scheme。
// dep 用组件 ID 形态传入，如 "mdm/customer"；extra 传额外端口名如 "grpc"，主端口传 ""。
// 弱依赖缺失时返回 ("", false)——变量根本不存在，不是空串（§3.6）。
func Endpoint(dep string, extra string) (addr string, ok bool)

// WithTx 开事务并 SET LOCAL ROLE / search_path，COMMIT 时自动还原（§13.3 铁律二）。
func WithTx(ctx context.Context, db *sql.DB, role, schema string, fn func(*sql.Tx) error) error

// PublishOutbox 在同一事务里把事件写进 event_outbox（§3.10 Outbox Pattern）。
func PublishOutbox(tx *sql.Tx, schema string, ev Event) error

// StartOutboxPump 起后台推送线程，轮询 outbox 发往 NATS。
func StartOutboxPump(ctx context.Context, db *sql.DB, schema string, nc *nats.Conn) error

// Consume 注册幂等消费者：自动做 inbox 去重、hop_count 防环、version 单调校验。
func Consume(ctx context.Context, nc *nats.Conn, db *sql.DB, schema, subject string,
    fn func(context.Context, *sql.Tx, Event) error) error

// InitOTel 初始化 OTel。otelBaseUrl 为空时装 Blackhole Exporter（§7.5）。
func InitOTel(ctx context.Context, serviceName, otelBaseURL string) (shutdown func(context.Context) error, err error)

// Event 是事件的统一信封。Header 里的三个字段由 SDK 自动填/校验。
type Event struct {
    Subject      string            // {domain}.{aggregate}.{action}.v{n}
    AggregateID  string
    Version      int64             // 消费侧只允许严格大于本地当前值才更新（§3.10）
    TraceID      string
    CausationID  string
    HopCount     int               // > 5 直接丢弃进 DLQ
    Payload      []byte
    Headers      map[string]string
}

// ListWindow 给 List 查询自动注入时间窗口（默认最近 90 天）与 Cursor 分页（§11.4）。
func ListWindow(q Query) Query

// BatchGetRouted 先查热表，缺失的再查 {schema}_archive（§11.6.1）。
func BatchGetRouted[T any](ctx context.Context, tx *sql.Tx, schema, table string,
    ids []string, scan func(*sql.Rows) (T, error)) ([]T, error)
```

- Produces：`be-ops` 的子命令骨架（Task 8 起逐个实现）：
  `be-ops registry check` / `be-ops db-script` / `be-ops gen-brickkit-yaml` / `be-ops routes` / `be-ops features` / `be-ops shell-config` / `be-ops shell-env` / `be-ops shell-depends`

⚠️ **`be-sdk-go` 是本计划对设计书 §5.10 的一处扩展，必须记下来：** 设计书只列了 `be-sdk-events-go`（reserve，Go 事件 SDK）。但 SOP-L 那 10 项横切能力里，事件只占 3 项——`Endpoint` 剥 scheme、`WithTx` 的 `SET LOCAL`、OTel 的 Blackhole 降级这几项，**每个组件各写一遍必然有人写错，而写错的那两处（`grpc.Dial("http://...")` 与不带 `LOCAL` 的 `SET`）恰好是设计书点名的「最难查的雷」**。所以本计划把它升为**必需件**并扩到 10 项。

它**不是**「公共 model 包」（§13.3 铁律六禁的那个）：零业务逻辑、零组件 model、零组件间引用。`be-acceptance` 的 import 扫描要把 `be-sdk-*` 显式加进白名单，其他一律红。

- [ ] **步骤 1：建三个目录与初始文件（先不 `git init`）**

```bash
mkdir -p tools/be-ops/{cmd/be-ops,internal/registry}
mkdir -p tools/be-acceptance/{platform,closedloop,gates}
mkdir -p tools/be-sdk-go
```

- [ ] **步骤 2：写 `tools/be-sdk-go/endpoint.go`（唯一一处剥 scheme 的地方）**

```go
package besdk

import (
	"os"
	"strings"
)

// envName 把组件 ID 推导成平台注入的变量名前缀。
// 规则与平台一致（§2.1）：/ 与 . 换成 _，全大写。
//   "mdm/customer" + ""     → MDM_CUSTOMER_ENDPOINT
//   "mdm/customer" + "grpc" → MDM_CUSTOMER_GRPC_ENDPOINT
func envName(dep, extra string) string {
	p := strings.ToUpper(strings.NewReplacer("/", "_", ".", "_", "-", "_").Replace(dep))
	if extra == "" {
		return p + "_ENDPOINT"
	}
	return p + "_" + strings.ToUpper(extra) + "_ENDPOINT"
}

// Endpoint 读 *_ENDPOINT 并剥掉 scheme。
//
// ⚠️ 平台注入的值恒为 http:// 开头，额外端口也一样——没有 grpc:// 这种东西。
// grpc.Dial("http://host:9094") 连不上，而报错信息指向名称解析，
// 非常难联想到是这里。所以剥 scheme 这件事全项目只写在这一个函数里（§2.1）。
//
// ⚠️ 必须用 os.LookupEnv 而不是 os.Getenv 后判空：弱依赖缺失时那个变量
// 根本不存在，不是空字符串——这是平台刻意的设计（§3.6）。
func Endpoint(dep, extra string) (string, bool) {
	v, ok := os.LookupEnv(envName(dep, extra))
	if !ok || v == "" {
		return "", false
	}
	v = strings.TrimPrefix(v, "http://")
	v = strings.TrimPrefix(v, "https://")
	return strings.TrimSuffix(v, "/"), true
}

// MustEndpoint 用于强依赖：缺失即 panic（强依赖缺失时平台本来就会阻断启动）。
func MustEndpoint(dep, extra string) string {
	v, ok := Endpoint(dep, extra)
	if !ok {
		panic("强依赖 " + dep + " 的 " + envName(dep, extra) + " 未注入")
	}
	return v
}
```

- [ ] **步骤 3：写 `tools/be-sdk-go/tx.go`（唯一一处 `SET LOCAL` 的地方）**

```go
package besdk

import (
	"context"
	"database/sql"
	"fmt"
	"regexp"
)

var identRe = regexp.MustCompile(`^[a-z][a-z0-9_]*$`)

// WithTx 开事务，切到本组件的 role 与 schema，跑 fn，然后 COMMIT。
//
// ⚠️⚠️ 绝不能用不带 LOCAL 的 SET。SET search_path / SET ROLE 之后把连接
// 还回共享池，下一个借用者会原样继承它——A 组件的查询打在 B 组件的表上，
// 不报错、不崩，只是悄悄读写了别人的数据。这是这套写法唯一的雷，
// 也是最难查的一个（设计书决策 3、§13.3 铁律二）。
//
// SET LOCAL 在 COMMIT/ROLLBACK 时自动还原，连接干净地回到池里。
func WithTx(ctx context.Context, db *sql.DB, role, schema string,
	fn func(*sql.Tx) error) error {

	// role 与 schema 来自 registry，不是用户输入；但它们要拼进 SQL
	// （SET LOCAL ROLE 不接受占位符），所以仍然白名单校验。
	if !identRe.MatchString(role) {
		return fmt.Errorf("非法 role 名：%q", role)
	}
	if !identRe.MatchString(schema) {
		return fmt.Errorf("非法 schema 名：%q", schema)
	}

	tx, err := db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }() // COMMIT 成功后这次 Rollback 是 no-op

	if _, err := tx.ExecContext(ctx, "SET LOCAL ROLE "+role); err != nil {
		return fmt.Errorf("SET LOCAL ROLE %s: %w", role, err)
	}
	// 归档 schema 也要在 search_path 里，batchGet 的冷热路由才不用写限定名
	if _, err := tx.ExecContext(ctx,
		"SET LOCAL search_path TO "+schema+", "+schema+"_archive"); err != nil {
		return fmt.Errorf("SET LOCAL search_path TO %s: %w", schema, err)
	}
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit()
}
```

- [ ] **步骤 4：写余下 7 个文件的骨架**

`outbox.go` / `events.go` / `otel.go` / `query.go` / `archive.go` / `logging.go` / `metrics.go` 各写**函数签名 + 完整文档注释 + `panic("未实现")`**，不写实现。理由：签名是 61 个组件共同依赖的契约，必须先钉死；实现放 Task 7 用 TDD 补。每个文件的注释里必须写清它守的是设计书哪一条（对照 SOP-L 那张表）。

- [ ] **步骤 5：写 `tools/be-ops/cmd/be-ops/main.go` 的子命令骨架**

```go
package main

import (
	"fmt"
	"os"
)

// be-ops 认领平台明确不做的 8 件事（本计划 §2.4、设计书决策 89/93）。
// 它不是 brickKit 组件，不进 brickkit.yaml。
var subcommands = map[string]string{
	"registry":         "校验全局端口册与 schema 册自洽（产出 6）",
	"db-script":        "产出建库脚本：DATABASE/SCHEMA/ROLE/授权/外壳登录角色（产出 2）",
	"gen":              "产出 brickkit.yaml，含 slot 互斥与 channel 多选校验（产出 5）",
	"routes":           "产出网关路由表，两个出口按组件是否进外壳分流（产出 1）",
	"features":         "产出 feature 清单，写进 IAM 适配层的 enabledComponents（产出 3）",
	"shell-config":     "产出外壳合并配置：谁进哪个外壳、端口、迁移顺序（产出 4）",
	"shell-env":        "产出每外壳一份环境变量表（产出 7）——最容易被漏掉的一件",
	"shell-depends":    "产出 shell-compose 的 depends_on：外壳之间的启动顺序（产出 8）",
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("be-ops —— BrickEnterprise 装配生成器\n\n子命令：")
		for k, v := range subcommands {
			fmt.Printf("  %-14s %s\n", k, v)
		}
		os.Exit(2)
	}
	fmt.Fprintf(os.Stderr, "子命令 %q 尚未实现\n", os.Args[1])
	os.Exit(1)
}
```

- [ ] **步骤 6：写三个 `Makefile` 与三个 `README.md`**

每个都按 §I 那 7 个门禁目标写（`be-ops` / `be-acceptance` / `be-sdk-go` 不是组件，所以 `check-version` / `migrate-idempotent` / `contract-check` 三项标 `@echo "N/A：非组件仓库"`，其余四项真实实现）。

- [ ] **步骤 7：⏸ 检查点 CP-1 —— 停下，请人创建仓库**

输出 §0.2 的标准话术，清单为：

```
目录已建好：
  tools/be-ops/
  tools/be-acceptance/
  tools/be-sdk-go/

请在 github.com/brickKit/ 下创建这 3 个空仓库（不要 README / .gitignore / license）：
  be-ops
  be-acceptance
  be-sdk-go
```

⚠️ `be-sdk-go` 是本计划对设计书 §5.10 的扩展（把 `be-sdk-events-go` 从「reserve、只管事件」升为「必需、SOP-L 十项横切能力」）。创建仓库时描述里写清这一点。

**本任务在此中止，等人回「建好了」。**

---

#### Task 7：接入 submodule + `be-sdk-go` 用 TDD 实现 SOP-L

**Files:**
- Modify: `.gitmodules`（由 `git submodule add` 生成）
- Create: `tools/be-sdk-go/*_test.go`
- Modify: `tools/be-sdk-go/{outbox,events,otel,query,archive,logging,metrics}.go`

**Interfaces:**
- Consumes：Task 6 定下的 `besdk` 公开 API 签名（不许改，61 个组件都会依赖）。
- Produces：`be-sdk-go v0.1.0` tag。档 0 起所有 Go 组件 `require github.com/brickKit/be-sdk-go v0.1.0`（精确版本，不用 `latest`）。

- [ ] **步骤 1：三个仓库 push 并接成 submodule**

对 `be-ops` / `be-acceptance` / `be-sdk-go` 各跑一遍 §3.5 步骤 C。

- [ ] **步骤 2：写失败测试 —— `endpoint_test.go`**

```go
package besdk

import "testing"

func TestEndpoint_剥掉scheme(t *testing.T) {
	t.Setenv("MDM_CUSTOMER_GRPC_ENDPOINT", "http://mdm-customer-1-0-0:9090")
	got, ok := Endpoint("mdm/customer", "grpc")
	if !ok || got != "mdm-customer-1-0-0:9090" {
		t.Fatalf("期望 mdm-customer-1-0-0:9090/true，得到 %q/%v", got, ok)
	}
}

func TestEndpoint_主端口变量名不带额外端口段(t *testing.T) {
	t.Setenv("MDM_CUSTOMER_ENDPOINT", "http://mdm-customer-1-0-0:8080")
	got, ok := Endpoint("mdm/customer", "")
	if !ok || got != "mdm-customer-1-0-0:8080" {
		t.Fatalf("期望 mdm-customer-1-0-0:8080/true，得到 %q/%v", got, ok)
	}
}

// 弱依赖缺失时变量根本不存在，不是空串（§3.6）。
// 这一条守的是「组件代码不能用 os.Environ["X"] 崩掉」。
func TestEndpoint_弱依赖缺失返回false而不panic(t *testing.T) {
	if got, ok := Endpoint("infra/workflow", ""); ok || got != "" {
		t.Fatalf("期望 \"\"/false，得到 %q/%v", got, ok)
	}
}
```

- [ ] **步骤 3：跑测试确认通过（`endpoint.go` 在 Task 6 已实现）**

```bash
cd tools/be-sdk-go && go test -run TestEndpoint -v ./...
```
期望：3 个用例 PASS。

- [ ] **步骤 4：写 `tx_test.go` —— 用真 PG 守住 `SET LOCAL` 那条雷**

```go
package besdk

import (
	"context"
	"database/sql"
	"os"
	"testing"

	_ "github.com/lib/pq"
)

// 这个用例守的是设计书里点名「最难查的一个」的雷：
// 用不带 LOCAL 的 SET 之后把连接还回池，下一个借用者会原样继承它。
// 断言方式：把池限制成 1 条连接，WithTx 跑完之后再借出同一条连接，
// 它的 search_path 必须已经还原，不能还是组件的 schema。
func TestWithTx_连接还池后search_path必须还原(t *testing.T) {
	dsn := os.Getenv("TEST_PG_DSN")
	if dsn == "" {
		t.Skip("未设置 TEST_PG_DSN，跳过（CI 里必须设）")
	}
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	db.SetMaxOpenConns(1) // 关键：强制复用同一条物理连接

	ctx := context.Background()
	if _, err := db.ExecContext(ctx, `CREATE SCHEMA IF NOT EXISTS besdk_probe`); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `CREATE SCHEMA IF NOT EXISTS besdk_probe_archive`); err != nil {
		t.Fatal(err)
	}

	var before string
	if err := db.QueryRowContext(ctx, `SHOW search_path`).Scan(&before); err != nil {
		t.Fatal(err)
	}

	err = WithTx(ctx, db, "current_user", "besdk_probe", func(tx *sql.Tx) error {
		var inside string
		if err := tx.QueryRow(`SHOW search_path`).Scan(&inside); err != nil {
			return err
		}
		if inside != "besdk_probe, besdk_probe_archive" {
			t.Fatalf("事务内 search_path 应为 besdk_probe, besdk_probe_archive，实际 %q", inside)
		}
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	var after string
	if err := db.QueryRowContext(ctx, `SHOW search_path`).Scan(&after); err != nil {
		t.Fatal(err)
	}
	if after != before {
		t.Fatalf("连接还池后 search_path 未还原：还池前 %q，还池后 %q —— "+
			"说明用了不带 LOCAL 的 SET，会跨组件串数据", before, after)
	}
}

func TestWithTx_拒绝非法标识符(t *testing.T) {
	for _, bad := range []string{"erp_sales; DROP SCHEMA public", "ERP_Sales", "1erp", ""} {
		if err := WithTx(context.Background(), nil, "r", bad, nil); err == nil {
			t.Fatalf("schema=%q 应该被拒绝", bad)
		}
	}
}
```

- [ ] **步骤 5：跑测试**

```bash
export TEST_PG_DSN="postgres://postgres:$POSTGRES_PASSWORD@localhost:5432/postgres?sslmode=disable"
cd tools/be-sdk-go && go test -run TestWithTx -v ./...
```
期望：2 个用例 PASS。**`TEST_PG_DSN` 未设时那条会 Skip——CI 里必须设，本地至少跑一次真的。**

- [ ] **步骤 6：按同样节奏补完余下 7 个文件**

每个文件先写测试、跑红、写实现、跑绿。要守的断言逐条列出（这些就是各自的测试用例）：

| 文件 | 必须有的测试断言 | 守的设计书条款 |
|---|---|---|
| `outbox.go` | ① 事件与业务数据在**同一事务**里落库，业务回滚时事件也不留；② pump 发送成功后标记，失败保留重试；③ 已发布超 30 天的记录可清理 | §3.10 Outbox、§11.7 |
| `events.go` | ① `hop_count > 5` 直接丢弃进 DLQ；② `causation_id` 成环丢弃；③ 消费幂等（同 `idempotency_key` 投两次只落一次）；④ `version` 不大于本地当前值时**跳过更新**（免疫乱序） | §3.10、§4.6、决策 42/43 |
| `otel.go` | ① `otelBaseURL == ""` 时装 Blackhole，`shutdown` 不报错；② Collector 连不上时**不阻塞不抛异常**（用一个必失败的地址断言业务调用照样返回） | §7.5 优雅降级 |
| `query.go` | ① List 未传时间范围时自动注入最近 90 天；② `offset` 超阈值报错，强制 Cursor | §11.4.1/11.4.2、决策 52/53 |
| `archive.go` | ① `batchGet` 热表命中不查归档；② 热表缺失的 id 才去 `{schema}_archive` 补；③ 两处都没有时返回缺失而不报错 | §11.6.1、决策 56 |
| `logging.go` | ① 输出是合法 JSON；② 每行含 `trace_id`/`span_id`/`service_name`；③ PII 字段被脱敏；④ 超 2KB 的 payload 被截断 | §7.3 |
| `metrics.go` | ① 每个 HTTP/gRPC 接口自动暴露 Rate/Errors/Duration；② 采集间隔 15s；③ Histogram bucket 数量有上限 | §7.4 |

- [ ] **步骤 7：7 个门禁全绿，打 tag**

```bash
cd tools/be-sdk-go
make test image dag-check import-scan
git add -A && git commit -m "feat: SOP-L 十项横切能力（endpoint 剥 scheme / SET LOCAL / Outbox / 事件防环 / OTel 降级 / 查询窗口 / 冷热路由 / 日志 / 指标）"
git tag v0.1.0 && git push --follow-tags
```

**验证：** `go test ./... -race` 全绿；`TestWithTx_连接还池后search_path必须还原` 真的跑过（不是 Skip）。

---

#### Task 8：`be-ops` 的三个先决产出（产出 2 / 5 / 6）

**Files:**
- Create: `tools/be-ops/internal/registry/{load.go,check.go,load_test.go,check_test.go}`
- Create: `tools/be-ops/internal/dbscript/{gen.go,gen_test.go}`
- Create: `tools/be-ops/internal/genyaml/{gen.go,gen_test.go}`
- Modify: `tools/be-ops/cmd/be-ops/main.go`
- Modify: `infra/scripts/registry-check.sh`（改为薄壳调 `be-ops registry check`）
- Modify: `Makefile`（`make db-init` 接上）

**Interfaces:**
- Consumes：`registry/ports.tsv`、`registry/schemas.tsv`（Task 4）。
- Produces：
  - `be-ops registry check` —— 退出码 0/1，判据与 Task 4 的脚本完全一致（脚本退休为薄壳）。
  - `be-ops db-script --out build/db-init.sql` —— 幂等 SQL。
  - `be-ops gen --out brickkit.yaml` —— 读各组件 `assembly.yaml` 产出装配清单。

- [ ] **步骤 1：写 `dbscript` 的失败测试**

```go
package dbscript

import (
	"strings"
	"testing"
)

func TestGen_每组件三样东西(t *testing.T) {
	sql, err := Gen([]Row{{Repo: "erp-sales", Schema: "erp_sales",
		Role: "erp_sales_rw", ShellLoginRole: "shell_go_core"}})
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		`CREATE SCHEMA IF NOT EXISTS erp_sales`,
		// 归档 schema 必须是本组件专属的。不能共用全局 archive——
		// 那会在权限墙上开洞：erp_sales 为了写自己的归档分区拿到该 schema
		// 的写权限，于是也能读到 crm_activity 归档过去的数据（§11.5.4）
		`CREATE SCHEMA IF NOT EXISTS erp_sales_archive`,
		`CREATE ROLE erp_sales_rw`,
		`GRANT USAGE ON SCHEMA erp_sales TO erp_sales_rw`,
		`GRANT USAGE ON SCHEMA erp_sales_archive TO erp_sales_rw`,
		// 外壳登录角色要能 SET ROLE 成组件角色（§13.3 铁律二）
		`GRANT erp_sales_rw TO shell_go_core`,
	} {
		if !strings.Contains(sql, want) {
			t.Errorf("产出里缺少 %q", want)
		}
	}
}

func TestGen_组件角色之间互相看不见(t *testing.T) {
	sql, _ := Gen([]Row{
		{Repo: "erp-sales", Schema: "erp_sales", Role: "erp_sales_rw", ShellLoginRole: "shell_go_core"},
		{Repo: "crm-lead", Schema: "crm_lead", Role: "crm_lead_rw", ShellLoginRole: "shell_go_backoffice"},
	})
	// 权限墙：erp_sales_rw 绝不能拿到 crm_lead 的任何权限
	if strings.Contains(sql, "ON SCHEMA crm_lead TO erp_sales_rw") {
		t.Error("跨组件授权，PG RBAC 权限墙被打穿")
	}
}

func TestGen_幂等(t *testing.T) {
	sql, _ := Gen([]Row{{Repo: "mdm-org", Schema: "mdm_org",
		Role: "mdm_org_rw", ShellLoginRole: "shell_go_core"}})
	// CREATE ROLE 没有 IF NOT EXISTS，必须包在 DO 块里判存在
	if !strings.Contains(sql, "DO $$") {
		t.Error("CREATE ROLE 必须包在 DO 块里做存在判断，否则重跑会报 role already exists")
	}
}

// 平台只打印 CREATE DATABASE，不建库（§2.7.2 ①）。
// 建库语句必须在产出里，且必须与 CREATE SCHEMA 分开——
// PG 不能在一个库内部创建它自己，也不能在同一个事务里 CREATE DATABASE。
func TestGen_建库语句单独一段(t *testing.T) {
	sql, _ := Gen(nil)
	if !strings.Contains(sql, "CREATE DATABASE brickkit_db") {
		t.Error("缺少 CREATE DATABASE brickkit_db")
	}
	if strings.Contains(sql, "BEGIN;") &&
		strings.Index(sql, "CREATE DATABASE") > strings.Index(sql, "BEGIN;") {
		t.Error("CREATE DATABASE 不能在事务里")
	}
}
```

- [ ] **步骤 2：跑测试确认全红**

```bash
cd tools/be-ops && go test ./internal/dbscript/ -v
```
期望：FAIL，`undefined: Gen`。

- [ ] **步骤 3：写 `dbscript.Gen` 的实现**

产出的 SQL 结构（分三段，段间用注释分隔）：

```sql
-- ═══ 第 1 段：建库。必须单独连到 postgres 库执行一次 ═══
-- ⚠️ 平台只会打印这一句，不会执行（006 §9.5：建库要 CREATEDB 权限，
--    让每个组件的运行期账号都有它是全平台提权；且 PG 不能在一个库内部创建它自己）
SELECT 'CREATE DATABASE brickkit_db'
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'brickkit_db')\gexec

-- ═══ 第 2 段：5 个外壳登录角色。连到 brickkit_db 执行 ═══
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='shell_go_core') THEN
    CREATE ROLE shell_go_core LOGIN PASSWORD :'pw_shell_go_core';
  END IF;
END $$;
-- …其余 4 个外壳同形

-- ═══ 第 3 段：每组件 schema + archive schema + role + 授权 ═══
CREATE SCHEMA IF NOT EXISTS erp_sales;
CREATE SCHEMA IF NOT EXISTS erp_sales_archive;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='erp_sales_rw') THEN
    CREATE ROLE erp_sales_rw NOLOGIN;   -- ⚠️ NOLOGIN：组件角色只用于 SET LOCAL ROLE，从不登录
  END IF;
END $$;
GRANT USAGE, CREATE ON SCHEMA erp_sales         TO erp_sales_rw;
GRANT USAGE, CREATE ON SCHEMA erp_sales_archive TO erp_sales_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA erp_sales
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO erp_sales_rw;
ALTER DEFAULT PRIVILEGES IN SCHEMA erp_sales_archive
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO erp_sales_rw;
GRANT erp_sales_rw TO shell_go_core;   -- 外壳登录角色才能 SET ROLE 成它
-- …其余组件同形
```

- [ ] **步骤 4：跑测试确认全绿**

```bash
cd tools/be-ops && go test ./internal/dbscript/ -v
```
期望：4 个用例 PASS。

- [ ] **步骤 5：把 `registry check` 从 shell 搬进 `be-ops`**

判据一字不改地移植 Task 4 步骤 3 那 6 条，加上 Go 侧才好写的第 7 条：

```go
// 第 7 条：ports.tsv 与 schemas.tsv 的 shell 归属必须一致。
// ports.tsv 的 shell 列是 go-core/go-backoffice/go-infra/py-brain/py-render/standalone/out-of-band；
// schemas.tsv 的 shell_login_role 列是 shell_go_core/... 。两者必须机械对应。
// 对不上说明有人只改了一张表——那会让外壳的连接池借出错误的登录角色，
// 而症状是「某个模块查自己的表报 permission denied」，极难联想到是册子不同步。
```

然后把 `infra/scripts/registry-check.sh` 改成薄壳：

```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "$ROOT/tools/be-ops/build/be-ops" registry check --root "$ROOT"
```

- [ ] **步骤 6：写 `genyaml`（产出 5）**

读所有 `components/*/*/assembly.yaml`，产出 `brickkit.yaml`。必须实现三条生成器铁律（§2.4）的校验，各配一个测试：

| 测试 | 断言 |
|---|---|
| `TestGen_labels值必须是字符串` | 产出的 `labels` 里布尔与数字带引号（`"true"` / `"8080"`）。平台不做自动转换 |
| `TestGen_没买的组件整条不写` | 传入「不装 hrm」时产出里**没有** hrm 那几条，且**不是** `enabled: false`（后者会级联关掉下游主数据） |
| `TestGen_聚合型组件依赖全optional` | `infra-bff-mobile` 与 `infra-notification` 的所有 `dependencies.components` 条目都带 `optional: true` |
| `TestGen_slot互斥` | 同一 `slot_name` 出现两个实现时报错（如同时装 `iam-casdoor` 与 `iam-keycloak`） |
| `TestGen_channel多选放行` | 同一 `channel` 出现多个实现时正常产出（钉钉 + 企微可并存） |
| `TestGen_精确版本` | 产出里的 version 全是 `major.minor.patch`，出现 `^` / `~` / `latest` 就报错 |
| `TestGen_local注释` | 产出里每一串 `local: true` 上方必须有注释说明「这不是有人在调试，是合并部署」（§13.1） |

- [ ] **步骤 7：`make db-init` 接上并跑一次**

```makefile
##@ 数据库
db-init: ## 执行 be-ops 产出的建库脚本（幂等）
	@cd tools/be-ops && go build -o build/be-ops ./cmd/be-ops
	@tools/be-ops/build/be-ops db-script --root . --out build/db-init.sql
	@docker exec -i be-postgres psql -v ON_ERROR_STOP=1 -U postgres \
	   -f - < build/db-init.sql
	@echo "✓ 建库脚本已执行（幂等，可重跑）"
.PHONY: db-init
```

```bash
make db-init && make db-init   # 跑两次，第二次必须也成功（幂等）
docker exec be-postgres psql -U postgres -d brickkit_db -c '\dn'
```
期望：两次都成功；`\dn` 列出所有已注册组件的 schema 与 `_archive` schema。

⚠️ 此时 `registry/schemas.tsv` 里有 54 个组件行，但 `components/` 里还没有任何组件。**建库脚本按册子建全部 schema 是对的**——schema 是空壳，代价近乎零，而「等组件来了再建」会让每次加组件都要多一次运维动作。

- [ ] **步骤 8：commit**

```bash
cd tools/be-ops && git add -A
git commit -m "feat: 产出 2/5/6（建库脚本 / brickkit.yaml 生成 / 端口册校验）

- 建库脚本：每组件 schema + 专属 archive schema + NOLOGIN 组件角色 + 授权，
  5 个外壳登录角色，全部幂等（CREATE ROLE 包 DO 块）。
  归档 schema 必须专属，共用全局 archive 会在权限墙上开洞（§11.5.4）。
- brickkit.yaml 生成：三条生成器铁律各配测试（labels 字符串 / 没买的整条不写
  而不是 enabled:false / 聚合型组件依赖全 optional）。
- 端口册校验从 shell 搬进 be-ops，shell 退休为薄壳，判据一份不分叉。"
git tag v0.1.0 && git push --follow-tags
```

**验证：** `make registry-check` 与 `make db-init`（连跑两次）都全绿。

---

#### Task 9：`be-acceptance` 骨架 + 铁律六 import 扫描门禁

**Files:**
- Create: `tools/be-acceptance/gates/{importscan.go,importscan_test.go}`
- Create: `tools/be-acceptance/platform/README.md`
- Create: `tools/be-acceptance/closedloop/README.md`
- Modify: `tools/be-acceptance/Makefile`
- Modify: `Makefile`

**Interfaces:**
- Produces：`be-acceptance gate import-scan --root <装配根>` —— 对每个组件目录跑 import 扫描，发现任何一条指向**另一个组件仓库**的边就红。白名单：`be-sdk-go` / `be-sdk-python` / `be-sdk-ts`。
- Produces：`make gates` —— 跑全部门禁（当前只有 import-scan，Task 46 加拆回门禁）。

⚠️ **为什么这条门禁要在档 0 之前就装好**：设计书决策 91 说得很清楚——前五条铁律破了当场起不来，一小时能修；**铁律六破了没有任何症状**，系统跑得更快了，直到某天要上 K8s 全拆才发现拆不动，那时的代价是重写。装晚一天，就多一天没人看着。

- [ ] **步骤 1：写失败测试**

```go
package gates

import (
	"os"
	"path/filepath"
	"testing"
)

func TestImportScan_组件之间互相import要红(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "components/erp/sales/go.mod"),
		"module github.com/brickKit/erp-sales\n\ngo 1.22\n")
	write(t, filepath.Join(root, "components/erp/sales/svc.go"),
		`package svc

import (
	"github.com/brickKit/be-sdk-go"          // 白名单，放行
	"github.com/brickKit/mdm-customer/model" // ❌ 指向另一个组件仓库
)
`)
	write(t, filepath.Join(root, "components/mdm/customer/go.mod"),
		"module github.com/brickKit/mdm-customer\n\ngo 1.22\n")

	violations, err := ImportScan(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(violations) != 1 {
		t.Fatalf("期望 1 条违规，得到 %d 条：%v", len(violations), violations)
	}
	if violations[0].From != "erp/sales" || violations[0].To != "mdm/customer" {
		t.Fatalf("违规方向不对：%+v", violations[0])
	}
}

func TestImportScan_引be_sdk放行(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "components/erp/sales/go.mod"),
		"module github.com/brickKit/erp-sales\n\ngo 1.22\n")
	write(t, filepath.Join(root, "components/erp/sales/svc.go"),
		`package svc

import "github.com/brickKit/be-sdk-go"
`)
	violations, err := ImportScan(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(violations) != 0 {
		t.Fatalf("be-sdk-go 在白名单里，应放行，得到 %v", violations)
	}
}

// 也不许抽一个「公共 model 包」给两个组件共用——
// 契约在 contracts/，代码不共享（§13.3 铁律六）
func TestImportScan_公共model包也要红(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "components/erp/sales/go.mod"),
		"module github.com/brickKit/erp-sales\n\ngo 1.22\n")
	write(t, filepath.Join(root, "components/erp/sales/svc.go"),
		`package svc

import "github.com/brickKit/be-common-model"
`)
	violations, err := ImportScan(root)
	if err != nil {
		t.Fatal(err)
	}
	if len(violations) != 1 {
		t.Fatalf("be-common-model 不在白名单里，应报违规，得到 %v", violations)
	}
}

func write(t *testing.T, p, s string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(s), 0o644); err != nil {
		t.Fatal(err)
	}
}
```

- [ ] **步骤 2：跑测试确认全红**

```bash
cd tools/be-acceptance && go test ./gates/ -v
```
期望：FAIL，`undefined: ImportScan`。

- [ ] **步骤 3：写实现**

```go
package gates

// Violation 是一条铁律六违规：From 组件 import 了 To 组件。
type Violation struct {
	From string // 组件 ID，如 "erp/sales"
	To   string // 组件 ID，如 "mdm/customer"
	File string
	Line int
}

// allowedShared 是唯一的白名单：横切基础库。
// ⚠️ 往这里加东西之前先回答一个问题：它有没有业务逻辑或组件 model？
// 有就不许加——那正是铁律六要禁的（§13.3）。
var allowedShared = map[string]bool{
	"github.com/brickKit/be-sdk-go":     true,
	"github.com/brickKit/be-sdk-python": true,
	"github.com/brickKit/be-sdk-ts":     true,
}

// ImportScan 扫描 root/components/ 下每个组件目录，返回全部违规。
// Go 用 AST 解析 import 块（不用 go list -deps，那需要能编译且要联网拉依赖，
// 在 CI 早期跑不起来）；Python 用 AST 扫 import / from ... import。
func ImportScan(root string) ([]Violation, error) { /* 实现 */ }
```

实现要点：
1. 枚举 `root/components/<scope>/<name>/`，从每个目录的 `go.mod` module 行或 `pyproject.toml` name 提取「这个目录是哪个仓库」，建立「仓库名 → 组件 ID」映射。
2. 逐文件 AST 解析 import 路径。
3. 命中 `allowedShared` → 放行；命中另一个已知组件仓库名 → 记违规；其他（标准库、第三方）→ 放行。
4. **不要**扫 `components/.archived/`（归档的不参与本次装配）。

- [ ] **步骤 4：跑测试确认全绿**

```bash
cd tools/be-acceptance && go test ./gates/ -v
```
期望：3 个用例 PASS。

- [ ] **步骤 5：写两个 README 记下待办用例**

`platform/README.md` 里把 §9.6.2 那 20 条平台验收用例**逐条列成待办清单**（Task 17 逐条实现）。`closedloop/README.md` 里把附录 E 的业务闭环拆成步骤清单（Task 34 实现）。

⚠️ **这两个 README 不是占位符，是任务清单。** 设计书 §9.6.2 明确：发现平台真有问题时，**先在这里记一条用例（哪怕是红的），再回 brickKit 仓库修——不许在业务侧绕过去。** 绕过去的那一条，会在 61 个组件时变成 61 处绕法。

- [ ] **步骤 6：`make gates` 接上并 commit**

```makefile
##@ 门禁
gates:  ## 跑全部验收门禁
	@cd tools/be-acceptance && go build -o build/be-acceptance ./cmd/be-acceptance
	@tools/be-acceptance/build/be-acceptance gate import-scan --root .
.PHONY: gates
```

```bash
make gates    # components/ 里还没有组件 → 0 条违规，绿
cd tools/be-acceptance && git add -A
git commit -m "feat(gates): 铁律六 import 扫描

组件之间绝不能互相 import。白名单只有 be-sdk-*（零业务逻辑、零组件 model）。
这条门禁必须在第一块砖之前装好：前五条铁律破了当场起不来，
铁律六破了没有任何症状，直到要全拆才发现拆不动（决策 91）。"
git tag v0.1.0 && git push --follow-tags
```

**验证：** `make gates` 绿；`go test ./gates/ -v` 3 个用例 PASS。

**🏁 阶段 -1 出档检查（四条全绿才进档 0）：**

```bash
make check           # ① 基础资源 5 个全 healthy
make registry-check  # ② 端口册与 schema 册自洽，61 个组件行
make db-init         # ③ 建库脚本幂等（连跑两次）
make gates           # ④ import 扫描绿
```


---

### 5.2 档 0 · 单砖：`mdm-customer`

**目标：一块砖能独立活。** 同时也是在**验 brickKit 自己**——我们既是平台的作者也是它的第一个真实用户（§9.6.0）。

**出档条件（六项，全绿才进档 1，一条都不许放过）：**

| # | 验什么 | 怎么验 |
|---|---|---|
| 1 | 单独 `brickkit up` 起来 | 只装这一个组件（连同它的强依赖树，此处为空），容器 healthy |
| 2 | `curl` 打通 HTTP | `curl http://localhost:8080/healthz` 与业务 REST 接口 |
| 3 | **`grpcurl` 打通 gRPC 的 `Get` / `List` / `batchGet`** | 三个 rpc 都真的能跨进程调通 |
| 4 | 迁移能被平台单独调起且可重跑 | `brickkit up` 生成迁移容器并跑通；同一份迁移连跑两次都成功 |
| 5 | `/healthz` 只查本进程 | 把 PG 停掉，`/healthz` **仍然返回 200** |
| 6 | 镜像里有 shell + wget | `docker run --rm <img> sh -c 'wget --version'` 成功 |

**这块砖的业务定义（设计书 §8.1 标准砖样板 A · 只读枢纽）：**

| 项 | 内容 |
|---|---|
| 拥有的表 | `customers` / `contacts` / `billing_infos` |
| 命令 | `Create` / `Update` / `SetStatus` / `AddContact` |
| 读 | `Get` / `List` / **`batchGet`** / `GetSummary` |
| 事件 | `mdm.customer.created.v1` / `mdm.customer.updated.v1` / `mdm.customer.disabled.v1` |
| 依赖 | **一个都没有**（`mdm` 被所有人读、自己不调任何人，§2.6 三枢纽） |
| 资源 | `database` (postgresql) + `mq` (nats) |

#### Task 10：`mdm-customer` 骨架 → **检查点 CP-2**

**Files:**
- Create: `components/mdm/customer/{component.yaml,assembly.yaml,Dockerfile,Makefile,README.md,.gitignore}`
- Create: `components/mdm/customer/contracts/{customer.proto,customer.openapi.yaml,events/customer.events.json}`
- Create: `components/mdm/customer/migrations/`（空目录 + `.gitkeep`）
- Create: `components/mdm/customer/backend/`（空目录 + `.gitkeep`）

**Interfaces:**
- Produces：目录布局即 SOP-B 那份结构。**本任务只建目录与空文件，内容留给 Task 11–15**——因为 CP-2 之前不 `git init`，写太多东西会让「叫人建仓库」这一步拖得没必要地久。

- [ ] **步骤 1：建目录树**

```bash
mkdir -p components/mdm/customer/{contracts/events,migrations,backend}
touch components/mdm/customer/{migrations,backend}/.gitkeep
```

- [ ] **步骤 2：写 `README.md`（说明它是谁、边界在哪）**

```markdown
# mdm-customer · 客户主数据

**组件 ID**：`mdm/customer` ｜ **端口**：HTTP 8080 / gRPC 9090 ｜ **schema**：`mdm_customer`
**装配角色**：`default` ｜ **语言**：Go ｜ **合并部署时进**：外壳一 (go-core)

## 边界

客户的**基础主数据**归本组件：名称、税号、信用额度、状态、联系人、开票信息。

⚠️ 客户在销售流程中的**归属关系**（公海/私海/负责人）与**跟进状态**归 `crm-customer`，
不归这里。那个组件只存本组件主键的外键 + 摘要副本（§5.4）。

## 三枢纽里的位置

`mdm` 是**只读枢纽**：被所有人读、**自己不调任何人**（§2.6）。
所以本组件的 `dependencies.components` 永远是空的——加一条进去就是把枢纽变成了链上一环。

## 为什么必须有 batchGet

BFF 层 GraphQL Resolver 防 N+1 的**唯一合法调用方式**（§3.8、决策 23）。
没有它，Resolver 会退化成循环调 `Get` 的瀑布流。
```

- [ ] **步骤 3：写 `.gitignore`**

```gitignore
build/
*.test
.env
```

- [ ] **步骤 4：⏸ 检查点 CP-2 —— 停下，请人创建仓库**

```
目录已建好：
  components/mdm/customer/

请在 github.com/brickKit/ 下创建这 1 个空仓库（不要 README / .gitignore / license）：
  mdm-customer
```

**本任务在此中止，等人回「建好了」。**

---

#### Task 11：`mdm-customer` 的契约（契约先于实现）

**Files:**
- Modify: `.gitmodules`
- Create: `components/mdm/customer/contracts/customer.proto`
- Create: `components/mdm/customer/contracts/events/customer.events.json`
- Create: `components/mdm/customer/contracts/customer.openapi.yaml`
- Create: `components/mdm/customer/buf.yaml`、`buf.gen.yaml`

**Interfaces:**
- Produces：`mdm.customer.v1.CustomerService` 的 8 个 rpc。**后续所有依赖 `mdm/customer` 的组件（`erp-sales` / `erp-purchase` / `crm-*`）都消费这份契约，签名一旦发布就只能向后兼容地追加**（§3.4 铁律 3：允许末尾追加新字段、新接口，严禁删字段、改类型、改 Tag 编号）。

- [ ] **步骤 1：先接成 submodule（§3.5 步骤 C）**

```bash
cd components/mdm/customer
git init -b main && git add -A
git commit -m "chore: 组件骨架"
git remote add origin git@github.com:brickKit/mdm-customer.git
git push -u origin main
cd -
git submodule add git@github.com:brickKit/mdm-customer.git components/mdm/customer
git add .gitmodules components/mdm/customer
git commit -m "chore: 军火库接入 mdm-customer" && git push
```

- [ ] **步骤 2：写 `contracts/customer.proto`**

```protobuf
syntax = "proto3";

package mdm.customer.v1;

option go_package = "github.com/brickKit/mdm-customer/gen/mdm/customer/v1;customerv1";

import "google/protobuf/timestamp.proto";

// 客户主数据服务。mdm 是只读枢纽：被所有人读、自己不调任何人（§2.6）
service CustomerService {
  // ── 命令 ──
  rpc Create   (CreateRequest)   returns (CreateResponse);
  rpc Update   (UpdateRequest)   returns (UpdateResponse);
  rpc SetStatus(SetStatusRequest) returns (SetStatusResponse);
  rpc AddContact(AddContactRequest) returns (AddContactResponse);

  // ── 读 ──
  rpc Get       (GetRequest)       returns (Customer);
  rpc List      (ListRequest)      returns (ListResponse);
  // BatchGet 是 BFF 层 GraphQL Resolver 防 N+1 的唯一合法调用方式（§3.8）。
  // 每个聚合根都必须提供它——没有它，Resolver 会退化成循环调 Get 的瀑布流。
  rpc BatchGet  (BatchGetRequest)  returns (BatchGetResponse);
  // GetSummary 返回摘要副本用的那几个字段。下游只存外键 + 摘要（§3.8）
  rpc GetSummary(GetSummaryRequest) returns (GetSummaryResponse);
}

enum CustomerStatus {
  CUSTOMER_STATUS_UNSPECIFIED = 0;
  CUSTOMER_STATUS_ACTIVE      = 1;
  CUSTOMER_STATUS_DISABLED    = 2;  // 终态之一，可归档（§11.5.2）
}

message Customer {
  string   id            = 1;
  string   code          = 2;   // 业务编号，唯一
  string   name          = 3;
  string   tax_no        = 4;
  string   credit_limit  = 5;   // ⚠️ 金额一律用 string 传 decimal，绝不用 double
  CustomerStatus status  = 6;
  int64    version       = 7;   // 消费侧靠它做状态单向演进校验（§3.10）
  google.protobuf.Timestamp created_at = 8;
  google.protobuf.Timestamp updated_at = 9;
  repeated Contact     contacts      = 10;
  repeated BillingInfo billing_infos = 11;
}

message Contact {
  string id      = 1;
  string name    = 2;
  string phone   = 3;
  string email   = 4;
  bool   primary = 5;
}

message BillingInfo {
  string id             = 1;
  string title          = 2;
  string tax_no         = 3;
  string bank_name      = 4;
  string bank_account    = 5;
  string address        = 6;
}

// 摘要副本：外键 + name / status / version（§附录 I「摘要副本」）
message CustomerSummary {
  string id      = 1;
  string code    = 2;
  string name    = 3;
  CustomerStatus status = 4;
  int64  version = 5;
}

message CreateRequest {
  // ⚠️ 所有跨组件写操作接口必须基于业务单号实现严格幂等（§4.6）。
  // 被调用方用唯一约束去重，上游超时重试多次也只执行一次。
  string idempotency_key = 1;
  string code         = 2;
  string name         = 3;
  string tax_no       = 4;
  string credit_limit = 5;
}
message CreateResponse { Customer customer = 1; }

message UpdateRequest {
  string idempotency_key = 1;
  string id           = 2;
  int64  version      = 3;   // 乐观锁：与库里不一致则拒绝
  string name         = 4;
  string tax_no       = 5;
  string credit_limit = 6;
}
message UpdateResponse { Customer customer = 1; }

message SetStatusRequest {
  string idempotency_key = 1;
  string id      = 2;
  int64  version = 3;
  CustomerStatus status = 4;
}
message SetStatusResponse { Customer customer = 1; }

message AddContactRequest {
  string idempotency_key = 1;
  string customer_id = 2;
  Contact contact    = 3;
}
message AddContactResponse { Contact contact = 1; }

message GetRequest { string id = 1; }

message ListRequest {
  // ⚠️ 禁止深 Offset，强制 Cursor Pagination（决策 53）。
  // 未传时间范围时框架层自动注入最近 90 天（§11.4.1）——这里不给 offset 字段，
  // 就是为了让「翻到第 1000 页」在契约层面不可表达。
  string cursor    = 1;
  int32  page_size = 2;
  CustomerStatus status_filter = 3;
  google.protobuf.Timestamp created_after  = 4;
  google.protobuf.Timestamp created_before = 5;
}
message ListResponse {
  repeated Customer customers   = 1;
  string            next_cursor = 2;
}

message BatchGetRequest  { repeated string ids = 1; }
message BatchGetResponse {
  // 只返回找到的。缺失的 id 不报错——由调用方自己判断（§11.6.1 冷热路由后仍缺失是正常的）
  repeated Customer customers = 1;
  repeated string   missing_ids = 2;
}

message GetSummaryRequest  { repeated string ids = 1; }
message GetSummaryResponse { repeated CustomerSummary summaries = 1; }
```

⚠️ **金额字段一律 `string`。** `erp-finance` 要做高精度 Decimal 计算（§12.1.2），`double` 会在跨语言序列化时丢精度。这一条对全项目所有金额字段成立。

- [ ] **步骤 3：写 `contracts/events/customer.events.json`**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "mdm-customer 事件清单",
  "note": "Schema 演进铁律：只增不删不改（决策 19）。消费者宽容反序列化。",
  "envelope": {
    "description": "所有事件共用的信封。三个 Header 字段由 be-sdk 自动填/校验（§3.10）",
    "required": ["subject", "aggregate_id", "version", "trace_id", "causation_id", "hop_count", "occurred_at"],
    "properties": {
      "subject":      { "type": "string", "pattern": "^[a-z]+\\.[a-z-]+\\.[a-z-]+\\.v[0-9]+$" },
      "aggregate_id": { "type": "string" },
      "version":      { "type": "integer", "description": "消费者只在严格大于本地当前值时更新（决策 43）" },
      "trace_id":     { "type": "string" },
      "causation_id": { "type": "string" },
      "hop_count":    { "type": "integer", "maximum": 5, "description": "> 5 直接丢弃进 DLQ（决策 42）" },
      "occurred_at":  { "type": "string", "format": "date-time" }
    }
  },
  "events": [
    {
      "subject": "mdm.customer.created.v1",
      "grade": "core",
      "note": "核心交易事件：必须持久化、幂等、进死信队列（§3.10 事件分级）",
      "payload": {
        "type": "object",
        "required": ["id", "code", "name", "status", "version"],
        "properties": {
          "id":           { "type": "string" },
          "code":         { "type": "string" },
          "name":         { "type": "string" },
          "tax_no":       { "type": "string" },
          "credit_limit": { "type": "string" },
          "status":       { "type": "string", "enum": ["ACTIVE", "DISABLED"] },
          "version":      { "type": "integer" }
        }
      }
    },
    {
      "subject": "mdm.customer.updated.v1",
      "grade": "core",
      "payload": {
        "type": "object",
        "required": ["id", "name", "status", "version"],
        "properties": {
          "id":           { "type": "string" },
          "name":         { "type": "string" },
          "tax_no":       { "type": "string" },
          "credit_limit": { "type": "string" },
          "status":       { "type": "string", "enum": ["ACTIVE", "DISABLED"] },
          "version":      { "type": "integer" }
        }
      }
    },
    {
      "subject": "mdm.customer.disabled.v1",
      "grade": "core",
      "payload": {
        "type": "object",
        "required": ["id", "version"],
        "properties": {
          "id":      { "type": "string" },
          "version": { "type": "integer" }
        }
      }
    }
  ]
}
```

- [ ] **步骤 4：写 `contracts/customer.openapi.yaml`**

对外 REST 面。路径前缀必须与 `assembly.yaml` 的 `edge_routes` 一致：`/mdm/customer/**`。
接口：`GET /mdm/customer/customers`（List）、`GET /mdm/customer/customers/{id}`（Get）、
`POST /mdm/customer/customers`（Create）、`PATCH /mdm/customer/customers/{id}`（Update）、
`POST /mdm/customer/customers/{id}/status`（SetStatus）、
`POST /mdm/customer/customers/{id}/contacts`（AddContact）、
`GET /mdm/customer/healthz`。

⚠️ **REST 面不暴露 `BatchGet`。** 它是给 BFF 与其他组件走 gRPC 用的（§2.1：内部 gRPC，外部 HTTP/GraphQL）。暴露到公网 REST 上，等于给了一个「一次拿走全部客户」的接口。

- [ ] **步骤 5：写 `buf.yaml` / `buf.gen.yaml`，跑一次 `buf lint` 与代码生成**

```bash
cd components/mdm/customer
buf lint && buf generate
```
期望：lint 无输出（全过），`gen/` 下生成 Go stub。

- [ ] **步骤 6：commit**

```bash
git add contracts buf.yaml buf.gen.yaml gen
git commit -m "feat(contracts): CustomerService 8 个 rpc + 3 个事件

- BatchGet 必须有：BFF 防 N+1 的唯一合法调用方式（§3.8）
- 金额一律 string 传 decimal，double 跨语言会丢精度
- ListRequest 不给 offset 字段：深分页在契约层面不可表达（决策 53）
- 所有写接口带 idempotency_key（§4.6）
- REST 面不暴露 BatchGet（内部 gRPC，外部 HTTP，§2.1）"
```

**验证：** `buf lint` 无输出；`buf breaking --against '.git#branch=main'` 无输出。

---

#### Task 12：`mdm-customer` 的两份 yaml

**Files:**
- Create: `components/mdm/customer/component.yaml`
- Create: `components/mdm/customer/assembly.yaml`

**Interfaces:**
- Produces：`component.yaml` 是平台的全部工作依据；`assembly.yaml` 只有 `be-ops` 读。两份的 `id` 与 `version` 必须一致（`be-ops` 校验）。

- [ ] **步骤 1：写 `component.yaml`**

```yaml
apiVersion: brickkit/v1
kind: Component

metadata:
  id: mdm/customer                   # ⚠️ Fork 件必须与标准件完全一致（§3.4.1）
  name: 客户主数据
  version: 1.0.0                     # 精确版本，不接受 ^ / ~ / latest
  description: 客户名称、税号、信用额度、状态、联系人、开票信息

tags: [mdm, customer, master-data]

artifacts:
  - type: api-contract
    format: protobuf
    files:
      - contracts/customer.proto
      - contracts/events/customer.events.json
  - type: api-contract
    format: openapi
    files: [contracts/customer.openapi.yaml]
  - type: metadata                   # ← assembly.yaml 靠这一条随组件分发（§3.5）
    files: [assembly.yaml]

dependencies:
  components: []                     # mdm 是只读枢纽，自己不调任何人（§2.6）
  resources:
    - { kind: database, engine: postgresql }
    - { kind: mq,       engine: nats }      # 事件总线是资源，不是依赖组件（决策 86）

configSchema:
  type: object
  properties:
    pgSchema:                        # ⚠️ 不能叫 databaseSchema，DATABASE_ 是保留前缀
      type: string
      default: mdm_customer
    iamJwksUrl:                      # JWT 本地验签的公钥来源。不对 IAM 建依赖边（决策 87）
      type: string
    otelBaseUrl:                     # ⚠️ 不能叫 otelEndpoint，*_ENDPOINT 是保留后缀
      type: string
      default: ""                    # 空 → Blackhole Exporter，零成本（§7.5）
    defaultPageSize:
      type: integer
      default: 20
    listWindowDays:                  # List API 的默认时间窗口（§11.4.1）
      type: integer
      default: 90

deployment:
  type: container
  image: brickenterprise/mdm-customer:1.0.0
  port: 8080                         # 端口册 registry/ports.tsv
  extraPorts:
    - { name: grpc, port: 9090 }     # → MDM_CUSTOMER_GRPC_ENDPOINT（值仍以 http:// 开头）
  labels:                            # 平台只搬运，不解释键值。值必须是字符串
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
  resources:
    requests: { cpu: "100m", memory: "128Mi" }

migration:
  command: ["./migrate", "up"]

healthCheck:
  type: http
  path: /healthz                     # ⚠️ 只查本进程存活，严禁查库或查依赖组件（§12.3.6）
  # startPeriodSeconds 不写：默认就是 60，Go 组件够用（§12.3.5）
```

- [ ] **步骤 2：写 `assembly.yaml`**

```yaml
id: mdm/customer                     # 必须与 component.yaml 一致，be-ops 校验
version: 1.0.0

asset:
  source_type: open_standard
  assembly_role: default
  contract_lock: strict
  customization_guide: |
    客户主数据的字段或校验规则超出标准版时：
    1. 主管理员在客户电脑本地复制本目录为定制目录（如 mdm-customer-acme），改 git remote。
    2. 用 AI 在 backend/ 生成定制业务代码。
    3. 严禁对 contracts/ 做破坏性变更；只允许在末尾追加新字段、使用新 Tag 编号。
    4. 把定制目录声明成 local 安装源并排在标准源前面（§3.4.1 遮蔽机制）。
    ⚠️ metadata.id 与 version 一个字都不能改——改了所有依赖方的
       MDM_CUSTOMER_ENDPOINT 会整个消失。

domain: mdm
tier: backend

edge_routes:
  - { path: /mdm/customer/**, auth: required }

menus:
  - { key: mdm.customer, title: 客户管理, permission: mdm.customer.view }

data:
  schema: mdm_customer               # registry/schemas.tsv
  role:   mdm_customer_rw            # 只用于 SET LOCAL ROLE，从不登录，因此不进 brickkit.yaml

shell: go-core                       # 合并部署时进外壳一（§13.2）
```

- [ ] **步骤 3：验证平台真的接受这两份 yaml**

```bash
cd /home/zhijie/Desktop/github/be-assembly-standard
brickkit add mdm/customer@1.0.0 --yes
brickkit up --dry-run
```
期望：`--dry-run` 成功产出部署文件，输出里能看到 `mdm-customer-1-0-0`。

- [ ] **步骤 4：顺手验一条平台断言（§9.6.2 用例 1）**

```bash
# 往 component.yaml 临时塞一个 assembly.yaml 该管的字段，期望 up 当场失败
cd components/mdm/customer
cp component.yaml /tmp/component.yaml.bak
printf '\nassembly_role: default\n' >> component.yaml
cd - && brickkit up --dry-run; echo "exit=$?"
cp /tmp/component.yaml.bak components/mdm/customer/component.yaml
```
期望：`exit` 非 0，报错指出未知键 `assembly_role`。**这一条直接印证 §3.5 那个「未知键当场报错，不是静默忽略」的断言。** 结果记进 `tools/be-acceptance/platform/README.md` 的第 1 条。

- [ ] **步骤 5：commit**

```bash
cd components/mdm/customer
git add component.yaml assembly.yaml
git commit -m "feat: component.yaml 与 assembly.yaml

- 语义字段（asset/domain/tier/edge_routes/menus/data/shell）全在 assembly.yaml，
  靠 artifacts type: metadata 随组件分发。写进 component.yaml 会当场报错（§3.5）
- configSchema 避开保留前缀/后缀：pgSchema 不叫 databaseSchema，
  otelBaseUrl 不叫 otelEndpoint
- dependencies.components 为空：mdm 是只读枢纽，自己不调任何人（§2.6）
- 事件总线写成 resources 的 mq，不是依赖组件（决策 86）"
git push
```

**验证：** `brickkit up --dry-run` 成功；塞未知键时 `up` 当场失败。

---

#### Task 13：`mdm-customer` 的迁移

**Files:**
- Create: `components/mdm/customer/migrations/001_create_customers.up.sql` / `.down.sql`
- Create: `components/mdm/customer/migrations/002_create_outbox_inbox.up.sql` / `.down.sql`
- Create: `components/mdm/customer/backend/cmd/migrate/main.go`

**Interfaces:**
- Produces：`./migrate up` 可执行文件（`component.yaml` 的 `migration.command` 指向它）。**必须幂等**：同一份迁移连跑两次都成功（§I 门禁 4、§13.3 铁律五）。

- [ ] **步骤 1：写 `001_create_customers.up.sql`**

```sql
-- mdm-customer 主表。schema 由迁移工具的 search_path 指定，SQL 里不写限定名
-- ⚠️ 迁移状态表必须落在本组件 schema 里（§11.2.3）：
--    golang-migrate 的 x-migrations-table + search_path，见 backend/cmd/migrate/main.go
--    默认往 public 写会让 61 个组件的迁移记录互相顶掉

CREATE TABLE customers (
    id           BIGSERIAL,
    code         TEXT           NOT NULL,
    name         TEXT           NOT NULL,
    tax_no       TEXT           NOT NULL DEFAULT '',
    credit_limit NUMERIC(18,2)  NOT NULL DEFAULT 0,
    -- §11.2.1 强制字段（所有可能无限增长的业务表都必须有这四个）
    created_at   TIMESTAMPTZ    NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ    NOT NULL DEFAULT now(),
    version      BIGINT         NOT NULL DEFAULT 1,
    status       TEXT           NOT NULL DEFAULT 'ACTIVE',
    -- ⚠️ 分区表主键必须包含分区键（决策 59，PostgreSQL 强制要求）
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- 初始分区。未来分区由组件内置定时任务自动创建（决策 54）
CREATE TABLE customers_2026_01 PARTITION OF customers
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE customers_2026_02 PARTITION OF customers
  FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE customers_2026_03 PARTITION OF customers
  FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

-- code 唯一。分区表上的唯一约束必须含分区键
CREATE UNIQUE INDEX customers_code_uniq ON customers (code, created_at);
CREATE INDEX customers_status_created ON customers (status, created_at DESC);

-- 子表必须跟随主表分区（§11.2.4：主表与子表必须一起归档）
CREATE TABLE contacts (
    id          BIGSERIAL,
    customer_id BIGINT      NOT NULL,
    name        TEXT        NOT NULL,
    phone       TEXT        NOT NULL DEFAULT '',
    email       TEXT        NOT NULL DEFAULT '',
    is_primary  BOOLEAN     NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    version     BIGINT      NOT NULL DEFAULT 1,
    status      TEXT        NOT NULL DEFAULT 'ACTIVE',
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
CREATE TABLE contacts_2026_01 PARTITION OF contacts
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE contacts_2026_02 PARTITION OF contacts
  FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE contacts_2026_03 PARTITION OF contacts
  FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE INDEX contacts_customer ON contacts (customer_id, created_at DESC);

CREATE TABLE billing_infos (
    id           BIGSERIAL,
    customer_id  BIGINT      NOT NULL,
    title        TEXT        NOT NULL,
    tax_no       TEXT        NOT NULL DEFAULT '',
    bank_name    TEXT        NOT NULL DEFAULT '',
    bank_account TEXT        NOT NULL DEFAULT '',
    address      TEXT        NOT NULL DEFAULT '',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    version      BIGINT      NOT NULL DEFAULT 1,
    status       TEXT        NOT NULL DEFAULT 'ACTIVE',
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
CREATE TABLE billing_infos_2026_01 PARTITION OF billing_infos
  FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
CREATE TABLE billing_infos_2026_02 PARTITION OF billing_infos
  FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');
CREATE TABLE billing_infos_2026_03 PARTITION OF billing_infos
  FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');
CREATE INDEX billing_infos_customer ON billing_infos (customer_id, created_at DESC);
```

- [ ] **步骤 2：写 `002_create_outbox_inbox.up.sql`**

```sql
-- Outbox / Inbox。所有组件都有这两张表，且都按 created_at 周分区（§11.2.5）
-- 保留周期：已发布成功超过 30 天可清理（§11.7、决策 62）

CREATE TABLE event_outbox (
    id           BIGSERIAL,
    subject      TEXT        NOT NULL,
    aggregate_id TEXT        NOT NULL,
    version      BIGINT      NOT NULL,
    trace_id     TEXT        NOT NULL DEFAULT '',
    causation_id TEXT        NOT NULL DEFAULT '',
    hop_count    INT         NOT NULL DEFAULT 0,
    payload      JSONB       NOT NULL,
    published_at TIMESTAMPTZ,
    attempts     INT         NOT NULL DEFAULT 0,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    status       TEXT        NOT NULL DEFAULT 'PENDING',
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
CREATE TABLE event_outbox_2026_w01 PARTITION OF event_outbox
  FOR VALUES FROM ('2026-01-01') TO ('2026-01-08');
CREATE TABLE event_outbox_2026_w02 PARTITION OF event_outbox
  FOR VALUES FROM ('2026-01-08') TO ('2026-01-15');
-- 其余分区由定时任务自动建（决策 54）
CREATE INDEX event_outbox_pending ON event_outbox (status, created_at)
  WHERE status = 'PENDING';

CREATE TABLE event_inbox (
    id              BIGSERIAL,
    idempotency_key TEXT        NOT NULL,
    subject         TEXT        NOT NULL,
    aggregate_id    TEXT        NOT NULL,
    version         BIGINT      NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    status          TEXT        NOT NULL DEFAULT 'PROCESSED',
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
CREATE TABLE event_inbox_2026_w01 PARTITION OF event_inbox
  FOR VALUES FROM ('2026-01-01') TO ('2026-01-08');
CREATE TABLE event_inbox_2026_w02 PARTITION OF event_inbox
  FOR VALUES FROM ('2026-01-08') TO ('2026-01-15');
-- 消费幂等靠这个唯一约束（§4.6：被调用方在数据库中使用唯一约束去重）
CREATE UNIQUE INDEX event_inbox_idem ON event_inbox (idempotency_key, created_at);

-- 写操作的幂等表（命令侧，与事件消费侧分开）
CREATE TABLE command_idempotency (
    idempotency_key TEXT        PRIMARY KEY,
    command         TEXT        NOT NULL,
    result_id       TEXT        NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

- [ ] **步骤 3：写 `backend/cmd/migrate/main.go`（迁移状态表落本组件 schema）**

```go
package main

import (
	"fmt"
	"log"
	"os"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

func main() {
	schema := os.Getenv("PG_SCHEMA")
	if schema == "" {
		schema = "mdm_customer"
	}
	// 平台注入的 DATABASE_* 是保留前缀，只读不写（§C）
	dsn := fmt.Sprintf(
		"postgres://%s:%s@%s:%s/%s?sslmode=disable"+
			// ⚠️ 两条都必须有（§11.2.3）：
			//   search_path            —— 迁移里的 SQL 落在本组件 schema
			//   x-migrations-table     —— 迁移状态表也落在本组件 schema，
			//                             且表名含组件标识
			"&search_path=%s"+
			"&x-migrations-table=%s.schema_migrations_mdm_customer",
		os.Getenv("DATABASE_USER"), os.Getenv("DATABASE_PASSWORD"),
		os.Getenv("DATABASE_HOST"), os.Getenv("DATABASE_PORT"),
		os.Getenv("DATABASE_NAME"), schema, schema,
	)

	m, err := migrate.New("file://migrations", dsn)
	if err != nil {
		log.Fatalf("迁移初始化失败：%v", err)
	}
	if len(os.Args) > 1 && os.Args[1] == "down" {
		if err := m.Down(); err != nil && err != migrate.ErrNoChange {
			log.Fatalf("迁移回滚失败：%v", err)
		}
		return
	}
	// ⚠️ ErrNoChange 不是错误。迁移必须能连跑两次都成功：
	//    合并态由外壳跑、全拆态由平台跑，两条路径都要能重跑（§13.3 铁律五）
	if err := m.Up(); err != nil && err != migrate.ErrNoChange {
		log.Fatalf("迁移失败：%v", err)
	}
	log.Println("迁移完成")
}
```

- [ ] **步骤 4：本地验幂等**

```bash
cd components/mdm/customer
go build -o migrate ./backend/cmd/migrate
export DATABASE_HOST=localhost DATABASE_PORT=5432 DATABASE_NAME=brickkit_db \
       DATABASE_USER=postgres DATABASE_PASSWORD="$POSTGRES_PASSWORD" \
       PG_SCHEMA=mdm_customer
./migrate up && ./migrate up      # 两次都必须成功
docker exec be-postgres psql -U postgres -d brickkit_db \
  -c "\dt mdm_customer.*" -c "\dt mdm_customer.schema_migrations_mdm_customer"
```
期望：两次 `./migrate up` 都输出「迁移完成」；表列表里有 `customers`、`contacts`、`billing_infos`、`event_outbox`、`event_inbox`、`command_idempotency`，且 **`schema_migrations_mdm_customer` 在 `mdm_customer` schema 里、不在 `public` 里**。

- [ ] **步骤 5：确认 `public` 里干净**

```bash
docker exec be-postgres psql -U postgres -d brickkit_db -c "\dt public.*"
```
期望：`public` 里**没有** `schema_migrations`。**如果有，回步骤 3 检查 `x-migrations-table`**——这一条错了不会立刻出问题，但第二个组件跑迁移时会把第一个的记录顶掉，症状是「某个组件的迁移莫名其妙不跑了」（§11.2.3）。

- [ ] **步骤 6：commit**

```bash
git add migrations backend/cmd/migrate
git commit -m "feat(migrations): 三张业务表 + Outbox/Inbox/幂等表

- 全部分区表，主键含分区键（决策 59）；子表跟随主表分区（§11.2.4）
- 迁移状态表 schema_migrations_mdm_customer 落在 mdm_customer schema 里，
  不在 public。默认往 public 写会让 61 个组件的迁移记录互相顶掉（§11.2.3）
- ErrNoChange 不当错误：迁移必须能连跑两次都成功，
  合并态由外壳跑、全拆态由平台跑（§13.3 铁律五）"
git push
```

**验证：** `./migrate up` 连跑两次都成功；`schema_migrations_mdm_customer` 在 `mdm_customer` 里；`public` 里没有 `schema_migrations`。

---

#### Task 14：`mdm-customer` 的失败测试（测试先于实现）

**Files:**
- Create: `components/mdm/customer/backend/internal/service/service_test.go`
- Create: `components/mdm/customer/backend/internal/http/health_test.go`
- Create: `components/mdm/customer/backend/internal/repo/repo_test.go`

**Interfaces:**
- Consumes：`besdk.WithTx` / `besdk.PublishOutbox` / `besdk.Endpoint`（Task 7）。
- Produces：以下测试名是档 0 六项验收的自动化对应物，后续 57 个组件照抄这一套骨架。

- [ ] **步骤 1：写 `health_test.go` —— 守 `/healthz` 禁令**

```go
package http

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// 出档条件第 5 项：/healthz 只检查本进程存活。
// ⚠️ 严禁在里面查数据库、查依赖组件、查 NATS——一个下游抖动会让所有上游
// 同时被判不健康并重启；合并部署下更狠：一个模块把探针拖挂，
// 整组 21 个组件一起重启（§12.3.6）。
//
// 这个用例把 db 传成 nil。如果实现里碰了 db，它会 panic 而不是返回 200。
func TestHealthz_不碰任何依赖(t *testing.T) {
	h := NewHealthHandler() // 刻意不接受任何依赖参数——签名本身就是禁令
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("期望 200，得到 %d", rec.Code)
	}
}
```

- [ ] **步骤 2：写 `repo_test.go` —— 守权限墙与幂等**

```go
package repo

import (
	"context"
	"database/sql"
	"os"
	"testing"

	besdk "github.com/brickKit/be-sdk-go"
	_ "github.com/lib/pq"
)

func testDB(t *testing.T) *sql.DB {
	t.Helper()
	dsn := os.Getenv("TEST_PG_DSN")
	if dsn == "" {
		t.Skip("未设置 TEST_PG_DSN")
	}
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

func TestCreate_幂等(t *testing.T) {
	db := testDB(t)
	ctx := context.Background()
	r := New(db, "mdm_customer_rw", "mdm_customer")

	in := CreateInput{IdempotencyKey: "test-idem-001", Code: "C-001",
		Name: "Acme", CreditLimit: "100000.00"}
	a, err := r.Create(ctx, in)
	if err != nil {
		t.Fatal(err)
	}
	// 同一个 idempotency_key 再来一次：不许新建，必须返回同一条
	b, err := r.Create(ctx, in)
	if err != nil {
		t.Fatalf("幂等重试报错了：%v", err)
	}
	if a.ID != b.ID {
		t.Fatalf("幂等失效：第一次 %s，第二次 %s", a.ID, b.ID)
	}
}

func TestCreate_事件与业务数据同事务(t *testing.T) {
	db := testDB(t)
	ctx := context.Background()
	r := New(db, "mdm_customer_rw", "mdm_customer")

	// 刻意让业务逻辑在写完 outbox 之后失败，断言两边都回滚
	err := r.CreateWithInjectedFailure(ctx, CreateInput{
		IdempotencyKey: "test-rollback-001", Code: "C-ROLLBACK", Name: "Rollback"})
	if err == nil {
		t.Fatal("期望注入的失败被返回")
	}

	var n int
	if err := besdk.WithTx(ctx, db, "mdm_customer_rw", "mdm_customer",
		func(tx *sql.Tx) error {
			return tx.QueryRow(
				`SELECT count(*) FROM event_outbox WHERE aggregate_id = $1`,
				"C-ROLLBACK").Scan(&n)
		}); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("业务回滚了但 outbox 留了 %d 条——说明事件不在同一事务里（§3.10）", n)
	}
}

func TestBatchGet_缺失的id不报错(t *testing.T) {
	db := testDB(t)
	r := New(db, "mdm_customer_rw", "mdm_customer")
	got, missing, err := r.BatchGet(context.Background(), []string{"不存在的-id"})
	if err != nil {
		t.Fatalf("BatchGet 对缺失 id 不该报错：%v", err)
	}
	if len(got) != 0 || len(missing) != 1 {
		t.Fatalf("期望 0 命中 1 缺失，得到 %d/%d", len(got), len(missing))
	}
}

func TestList_未传时间范围时自动注入90天窗口(t *testing.T) {
	db := testDB(t)
	r := New(db, "mdm_customer_rw", "mdm_customer")
	q := r.BuildListQuery(ListInput{PageSize: 20}) // 不传 created_after
	if !q.HasTimeWindow() {
		t.Fatal("框架层必须自动注入默认时间窗口，否则用户无条件查询会拖垮数据库（§11.4.1）")
	}
	if q.WindowDays() != 90 {
		t.Fatalf("默认窗口应为 90 天，实际 %d", q.WindowDays())
	}
}
```

- [ ] **步骤 3：写 `service_test.go` —— 守状态机与乐观锁**

```go
package service

import "testing"

func TestUpdate_版本不一致时拒绝(t *testing.T) { /* 乐观锁：version 与库里不一致则拒绝 */ }

func TestSetStatus_只允许单向演进(t *testing.T) {
	// DISABLED 是终态之一。ACTIVE → DISABLED 允许；DISABLED → ACTIVE 拒绝。
	// 终态的定义要在这里写死——归档扫描靠它判断「无活跃业务」（§11.5.2、决策 55）
}

func TestSetStatus_发出disabled事件(t *testing.T) {
	// 断言 outbox 里落了 mdm.customer.disabled.v1，且 version 比之前大
}
```

- [ ] **步骤 4：跑测试确认全红**

```bash
cd components/mdm/customer
export TEST_PG_DSN="postgres://postgres:$POSTGRES_PASSWORD@localhost:5432/brickkit_db?sslmode=disable"
go test ./... -v
```
期望：编译失败或全部 FAIL（`undefined: NewHealthHandler` 等）。**没红就是测试没写对。**

- [ ] **步骤 5：commit（红的测试也要提交）**

```bash
git add backend/internal
git commit -m "test: 失败测试先行

- /healthz 的处理器签名不接受任何依赖参数——签名本身就是禁令（§12.3.6）
- 事件与业务数据必须同事务：业务回滚时 outbox 也不许留（§3.10）
- BatchGet 对缺失 id 不报错（§11.6.1 冷热路由后仍缺失是正常的）
- List 未传时间范围时框架自动注入 90 天窗口（§11.4.1）"
git push
```

**验证：** `go test ./...` 全红，且红的原因是「未实现」而不是「测试自己写错」。

---

#### Task 15：`mdm-customer` 的实现、Dockerfile、Makefile

**Files:**
- Create: `components/mdm/customer/backend/cmd/server/main.go`
- Create: `components/mdm/customer/backend/internal/{http,grpc,repo,service,partition}/*.go`
- Create: `components/mdm/customer/Dockerfile`
- Create: `components/mdm/customer/Makefile`

**Interfaces:**
- Produces：`brickenterprise/mdm-customer:1.0.0` 镜像；同时监听 8080 (HTTP) 与 9090 (gRPC)。

- [ ] **步骤 1：写 `main.go` —— 两个端口都真的 Listen**

```go
package main

import (
	"context"
	"database/sql"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	besdk "github.com/brickKit/be-sdk-go"
	customerv1 "github.com/brickKit/mdm-customer/gen/mdm/customer/v1"
	"google.golang.org/grpc"
	// …
)

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// ⚠️ 配置只从环境变量来，代码里零硬编码地址（§13.3 铁律一）。
	// 这是「合并部署不改代码」能成立的物理前提：合并时环境变量指向
	// 外壳内部的 127.0.0.1:<端口>，拆分时平台注入 K8s 的 DNS。
	schema := getenv("PG_SCHEMA", "mdm_customer")
	role := schema + "_rw"

	// otelBaseUrl 为空 → Blackhole Exporter，零成本（§7.5）
	shutdownOTel, err := besdk.InitOTel(ctx, "mdm-customer", os.Getenv("OTEL_BASE_URL"))
	if err != nil {
		log.Fatalf("OTel 初始化失败：%v", err)
	}
	defer shutdownOTel(context.Background())

	db, err := sql.Open("postgres", dsnFromEnv())
	if err != nil {
		log.Fatalf("打开数据库失败：%v", err)
	}
	defer db.Close()

	// Outbox 推送线程。合并后外壳只是换了个地方跑它，协议一个字不变（§1.5 原则一）
	nc := mustConnectNATS()
	if err := besdk.StartOutboxPump(ctx, db, schema, nc); err != nil {
		log.Fatalf("Outbox 推送线程启动失败：%v", err)
	}

	// 分区自动创建的定时任务（决策 54：跨月时分区不存在会导致写入崩溃）
	go startPartitionMaintainer(ctx, db, role, schema)

	// ── gRPC：extraPorts 里声明的端口必须真的 Listen ──
	// ⚠️ 这一条不许省。合并进外壳后，同一个 Go 进程里的两个模块仍然必须
	// 通过 gRPC 互相调用，不许直接函数调用。gRPC 是逻辑边界的物理载体，
	// 省掉它就等于合并那一刻边界消失，再也拆不回去（§1.5 原则一）
	grpcLn, err := net.Listen("tcp", ":"+getenv("GRPC_PORT", "9090"))
	if err != nil {
		log.Fatalf("gRPC 监听失败：%v", err)
	}
	gs := grpc.NewServer(besdk.GRPCServerOptions()...) // 拦截器自动注入 Trace/Metrics
	customerv1.RegisterCustomerServiceServer(gs, newGRPCServer(db, role, schema))
	go func() {
		if err := gs.Serve(grpcLn); err != nil {
			log.Printf("gRPC 退出：%v", err)
		}
	}()

	// ── HTTP：主端口 + /healthz + /metrics ──
	mux := http.NewServeMux()
	mux.Handle("/healthz", NewHealthHandler()) // 只查本进程，不接受任何依赖
	mux.Handle("/metrics", besdk.MetricsHandler())
	registerRESTRoutes(mux, db, role, schema)

	srv := &http.Server{Addr: ":" + getenv("HTTP_PORT", "8080"), Handler: mux}
	go func() {
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP 监听失败：%v", err)
		}
	}()

	log.Printf("mdm-customer 就绪：HTTP :%s gRPC :%s schema=%s",
		getenv("HTTP_PORT", "8080"), getenv("GRPC_PORT", "9090"), schema)

	<-ctx.Done()
	srv.Shutdown(context.Background())
	gs.GracefulStop()
}
```

⚠️ **`HTTP_PORT` / `GRPC_PORT` 不是平台注入的。** brickKit 明确**不注入「我该监听哪个端口」**（§13.8.1）——环境变量表里只有「别人在哪」（`*_ENDPOINT`），没有「我该监听哪」。全拆态下默认值 8080/9090 就是 Manifest 里的值；合并态下由**外壳启动器从每个模块自己的 `component.yaml` 读**并设进各模块的上下文。**外壳里不许另写一份端口表**——Manifest 才是权威，抄一份必然过期。

- [ ] **步骤 2：写 `repo` / `service` / `grpc` / `http` 四层，让 Task 14 的测试逐个变绿**

顺序：`repo`（先让 `repo_test.go` 绿）→ `service`（`service_test.go`）→ `http`（`health_test.go`）→ `grpc`。每让一个测试文件变绿就 commit 一次。

写 `repo` 时必须用 `besdk.WithTx`，**不许自己写 `SET`**：

```go
func (r *Repo) Create(ctx context.Context, in CreateInput) (*Customer, error) {
	var out *Customer
	err := besdk.WithTx(ctx, r.db, r.role, r.schema, func(tx *sql.Tx) error {
		// 幂等：先查 command_idempotency（§4.6 唯一约束去重）
		var existing string
		err := tx.QueryRowContext(ctx,
			`SELECT result_id FROM command_idempotency WHERE idempotency_key = $1`,
			in.IdempotencyKey).Scan(&existing)
		if err == nil {
			out, err = r.getInTx(ctx, tx, existing)
			return err
		} else if err != sql.ErrNoRows {
			return err
		}

		// 业务写入
		// …

		// 事件必须在同一事务里写 outbox（§3.10 Outbox Pattern）
		return besdk.PublishOutbox(tx, r.schema, besdk.Event{
			Subject:     "mdm.customer.created.v1",
			AggregateID: out.ID,
			Version:     out.Version,
			Payload:     payload,
		})
	})
	return out, err
}
```

- [ ] **步骤 3：跑测试确认全绿**

```bash
cd components/mdm/customer && go test ./... -race -v
```
期望：Task 14 写的每一个用例 PASS，`-race` 无报告。

- [ ] **步骤 4：写 `Dockerfile`**

```dockerfile
# ⚠️ 基底必须带 /bin/sh 加 wget 或 curl（§12.3.7）。
# 平台生成的健康检查是 CMD-SHELL：
#   ["CMD-SHELL", "wget -q --spider http://localhost:8080/healthz || curl -fsS ... || exit 1"]
# FROM scratch / distroless 连 shell 都没有，healthCheck.type: tcp 走的 nc -z 同样是 CMD-SHELL。
# 「在镜像里塞一个静态编译的探针二进制」这条出路不成立——平台只会调 wget/curl 这两个名字。
FROM golang:1.22-alpine AS build
WORKDIR /src
RUN apk add --no-cache git
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server  ./backend/cmd/server \
 && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/migrate ./backend/cmd/migrate

FROM alpine:3.20
RUN apk add --no-cache wget ca-certificates tzdata
WORKDIR /app
COPY --from=build /out/server  /app/server
COPY --from=build /out/migrate /app/migrate
COPY migrations /app/migrations
EXPOSE 8080 9090
ENTRYPOINT ["/app/server"]
```

- [ ] **步骤 5：写 `Makefile`（§I 那 7 个门禁）**

```makefile
IMAGE   := brickenterprise/mdm-customer
VERSION := $(shell grep -E '^\s+version:' component.yaml | head -1 | awk '{print $$2}')

.PHONY: all check-version test image migrate-idempotent dag-check contract-check import-scan

all: check-version test image migrate-idempotent dag-check contract-check import-scan

check-version:  ## component.yaml 的 version 与 git tag 不许分叉（§9.1 两个真相源）
	@tag="$$(git describe --tags --exact-match 2>/dev/null || true)"; \
	 if [ -n "$$tag" ] && [ "$$tag" != "v$(VERSION)" ]; then \
	   echo "✗ git tag $$tag 与 component.yaml 的 $(VERSION) 不一致"; exit 1; fi; \
	 echo "✓ version=$(VERSION)"

test:
	go test ./... -race -count=1

image:
	docker build -t $(IMAGE):$(VERSION) .
	@# 镜像里必须有 /bin/sh + wget，否则平台的 CMD-SHELL 健康检查永远失败，
	@# 症状是「组件日志写着已就绪，而平台说它不健康」（§12.3.7）
	@docker run --rm --entrypoint sh $(IMAGE):$(VERSION) -c 'wget --version >/dev/null' \
	  && echo "✓ 镜像里有 sh + wget"

migrate-idempotent:  ## 同一份迁移连跑两次都必须成功（§13.3 铁律五）
	@go build -o /tmp/migrate-probe ./backend/cmd/migrate
	@/tmp/migrate-probe up && /tmp/migrate-probe up && echo "✓ 迁移幂等"

dag-check:  ## 强依赖图无环（§4.2）。mdm 是只读枢纽，依赖为空，天然无环
	@deps="$$(grep -A5 'components:' component.yaml | grep -c '^\s*-\s' || true)"; \
	 if [ "$$deps" != "0" ]; then \
	   echo "✗ mdm 是只读枢纽，dependencies.components 必须为空（§2.6）"; exit 1; fi; \
	 echo "✓ 无强依赖，无环"

contract-check:  ## 禁破坏性变更（§8.5、决策 33）
	buf lint
	buf breaking --against '.git#branch=main'

import-scan:  ## 铁律六：不许 import 任何其他组件仓库（§13.3）
	@bad="$$(go list -deps ./... 2>/dev/null | grep -E '^github.com/brickKit/' \
	         | grep -vE '^github.com/brickKit/(mdm-customer|be-sdk-go)(/|$$)' || true)"; \
	 if [ -n "$$bad" ]; then \
	   echo "✗ 铁律六违规，import 了其他组件仓库："; echo "$$bad"; exit 1; fi; \
	 echo "✓ 无组件间 import"
```

- [ ] **步骤 6：7 个门禁全绿**

```bash
cd components/mdm/customer && make all
```
期望：7 个 `✓`。

- [ ] **步骤 7：commit + 打 tag**

```bash
git add -A
git commit -m "feat: HTTP 8080 + gRPC 9090 双端口实现、Dockerfile、7 个 CI 门禁

- gRPC 端口真的 Listen：合并后同进程的两个模块仍必须走 gRPC，
  省掉它就等于合并那一刻边界消失（§1.5 原则一）
- HTTP_PORT/GRPC_PORT 不是平台注入的（平台只注入「别人在哪」），
  合并态由外壳从各模块的 component.yaml 读（§13.8.1）
- 基底 alpine + wget：平台的健康检查是 CMD-SHELL，distroless 一律不行（§12.3.7）
- 分区自动创建的定时任务（决策 54：跨月时分区不存在会导致写入崩溃）"
git tag v1.0.0 && git push --follow-tags
cd - && git add components/mdm/customer && git commit -m "chore: mdm-customer 更新到 v1.0.0" && git push
```

**验证：** `make all` 七项全绿。

---

#### Task 16：档 0 出档 —— 六项验收逐条打勾

**Files:**
- Modify: `tools/be-acceptance/platform/README.md`（记录结果）
- Create: `tools/be-acceptance/closedloop/tier0_test.go`

**Interfaces:**
- Produces：`make tier0` —— 把六项验收固化成可重跑的自动化用例。**后续每加一个组件都要重跑它**（§9.6.1 档 4 的出档条件）。

- [ ] **步骤 1：验收 1 —— 单独 `brickkit up` 起来**

```bash
cd /home/zhijie/Desktop/github/be-assembly-standard
make check                    # 基础资源先就绪
brickkit up
brickkit status
```
期望：`mdm-customer-1-0-0` 容器 healthy。

- [ ] **步骤 2：验收 2 —— `curl` 打通 HTTP**

```bash
curl -fsS http://localhost:8080/healthz && echo " ← healthz OK"
curl -fsS -X POST http://localhost:8080/mdm/customer/customers \
  -H 'Content-Type: application/json' \
  -d '{"idempotency_key":"acc-001","code":"C-ACC-001","name":"验收客户","credit_limit":"50000.00"}'
curl -fsS 'http://localhost:8080/mdm/customer/customers?page_size=10'
```
期望：三条都 200，创建返回的对象里 `version` 为 1。

- [ ] **步骤 3：验收 3 —— `grpcurl` 打通三个 rpc（这一项最容易被跳过）**

```bash
grpcurl -plaintext localhost:9090 list mdm.customer.v1.CustomerService
grpcurl -plaintext -d '{"id":"1"}' localhost:9090 mdm.customer.v1.CustomerService/Get
grpcurl -plaintext -d '{"page_size":10}' localhost:9090 mdm.customer.v1.CustomerService/List
grpcurl -plaintext -d '{"ids":["1","999"]}' localhost:9090 mdm.customer.v1.CustomerService/BatchGet
```
期望：`list` 列出 8 个 rpc；`Get`/`List`/`BatchGet` 都返回数据，`BatchGet` 的 `missing_ids` 里有 `999`。

⚠️ **顺手验平台断言（§9.6.2 用例 4）：**

```bash
docker exec mdm-customer-1-0-0 env | grep -E 'MDM_CUSTOMER.*ENDPOINT' || \
  echo "（本组件没有依赖方，所以它自己容器里没有这个变量——这是对的）"
```
这一条要等档 1 有了 `erp-sales` 才真能验（在**依赖方**的容器里断言 `MDM_CUSTOMER_GRPC_ENDPOINT` 以 `http://` 开头）。**现在在 `platform/README.md` 的第 4 条上记一句「档 1 验」，不许当成已验过。**

- [ ] **步骤 4：验收 4 —— 迁移被平台单独调起且可重跑**

```bash
docker ps -a --filter 'name=mdm-customer' --format '{{.Names}}\t{{.Status}}'
# 期望能看到平台生成的一次性迁移容器（跑完退出 0）
brickkit down && brickkit up          # 第二次 up：迁移必须再跑一遍且成功
docker logs "$(docker ps -a --filter 'name=migrate' -q | head -1)" 2>&1 | tail -5
```
期望：两次 `up` 的迁移都成功；第二次输出「迁移完成」而不是报错。

⚠️ **顺手验平台断言（§9.6.2 用例 17）：**

```bash
brickkit up 2>&1 | grep -i 'CREATE DATABASE' && \
  echo "✓ 平台只打印建库语句（用例 17）"
```

- [ ] **步骤 5：验收 5 —— `/healthz` 只查本进程（把 PG 停掉）**

```bash
docker stop be-postgres
sleep 3
curl -fsS http://localhost:8080/healthz && echo " ← PG 停了 healthz 仍 200 ✓"
docker start be-postgres
```
期望：PG 停掉后 `/healthz` **仍返回 200**。

**如果返回 503**，实现里查了库——必须改。理由不是洁癖：一个下游抖动会让所有上游同时被判不健康并重启；合并部署下一个模块把探针拖挂，**整组 21 个组件一起重启**（§12.3.6）。

- [ ] **步骤 6：验收 6 —— 镜像里有 shell + wget**

```bash
docker run --rm --entrypoint sh brickenterprise/mdm-customer:1.0.0 -c 'wget --version | head -1'
```
期望：输出 wget 版本号。

- [ ] **步骤 7：顺手验两条平台断言（§9.6.2 用例 2 与 10）**

```bash
# 用例 2：assembly.yaml 靠 artifacts 随组件分发
ls -l .brickkit/artifacts/mdm-customer-1-0-0/metadata/assembly.yaml
# 用例 10：默认启动宽限是 60 秒（不是 30）
docker inspect mdm-customer-1-0-0 \
  -f '{{json .Config.Healthcheck.StartPeriod}}'
```
期望：`assembly.yaml` 存在；`StartPeriod` 是 60000000000（60 秒的纳秒数）。

- [ ] **步骤 8：把六项固化成 `tier0_test.go`**

每一项一个 Go 测试函数，函数名与验收项一一对应：
`Test档0_1_单独up起来` / `Test档0_2_curl打通HTTP` / `Test档0_3_grpcurl打通三个rpc` /
`Test档0_4_迁移可重跑` / `Test档0_5_healthz不查库` / `Test档0_6_镜像有shell和wget`。

`make tier0` 接上：

```makefile
##@ 验收
tier0:  ## 档 0 六项验收（每加一个组件都要重跑，§9.6.1 档 4）
	@cd tools/be-acceptance && go test ./closedloop/ -run 'Test档0' -v -count=1
.PHONY: tier0
```

- [ ] **步骤 9：把结果记进 `platform/README.md` 并 commit**

在那 20 条清单上给已验的打勾（1、2、10、17 四条），并给用例 4 标注「档 1 验」。

```bash
cd tools/be-acceptance && git add -A
git commit -m "test: 档 0 六项验收固化 + 平台断言 1/2/10/17 已验

平台断言的被测对象是 brickKit 本身，不是我们的业务。
用例 4（额外端口地址是 http:// 而不是 grpc://）要等档 1 有了依赖方才能真验，
现在只标注不打勾——不许当成已验过（§9.6.2）。"
git push
cd - && git add tools/be-acceptance && git commit -m "chore: be-acceptance 档 0 验收" && git push
```

**🏁 档 0 出档检查：**

```bash
make check && make tier0 && make gates && make arsenal-check
```
四条全绿才进档 1。


---

## 第 6 部分 · 档 1：验平台（加 4 砖，共 5 个组件）

> **这一档的被测对象是 brickKit，不是我们的业务**（§9.6.2）。
> 出档条件：§9.6.2 那 20 条平台验收清单**逐条打勾**，全部落进 `be-acceptance`。

**为什么是这 5 个**：`mdm-customer` + `mdm-product` + `erp-inventory` + `erp-finance` + `erp-sales` 恰好构成一条**含强依赖、含 gRPC 互调、含 Saga 补偿、含事件汇聚**的最短链路。平台的全部假设可以被这一条垂直切片打穿——那才是先做切片、不一上来铺满军火库的理由（§9.6.0）。

**这一档新增的四个组件全部在外壳一（go-core），全部 Go。**

#### Task 17：四个组件骨架 → **检查点 CP-3**

**Files:**
- Create: `components/mdm/product/`、`components/erp/inventory/`、`components/erp/finance/`、`components/erp/sales/` 四套 SOP-B 目录树

- [ ] **步骤 1：建四棵目录树**

```bash
for p in mdm/product erp/inventory erp/finance erp/sales; do
  mkdir -p "components/$p"/{contracts/events,migrations,backend}
  touch "components/$p"/{migrations,backend}/.gitkeep
done
```

- [ ] **步骤 2：给每个目录写 `README.md`（边界说明）**

四份 README 各自写清「什么归我、什么不归我」，内容取自本计划 §6.1–§6.4 的边界段。

- [ ] **步骤 3：⏸ 检查点 CP-3 —— 停下，请人创建仓库**

```
目录已建好：
  components/mdm/product/
  components/erp/inventory/
  components/erp/finance/
  components/erp/sales/

请在 github.com/brickKit/ 下创建这 4 个空仓库（不要 README / .gitignore / license）：
  mdm-product
  erp-inventory
  erp-finance
  erp-sales
```

**本任务在此中止，等人回「建好了」。**

---

#### Task 18：`mdm-product` —— 产品/物料主数据

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `mdm/product` / `mdm-product` |
| 端口 | HTTP **8082** / gRPC **9092** |
| schema / role | `mdm_product` / `mdm_product_rw`（归档 `mdm_product_archive`） |
| 语言 / 外壳 | Go / 外壳一 `go-core` |
| 装配角色 | `default` |
| `dependencies.components` | **空**（mdm 是只读枢纽，自己不调任何人，§2.6） |
| `dependencies.resources` | `database:postgresql`、`mq:nats` |
| `startPeriodSeconds` | 不写（Go 默认 60 够用） |

**边界**：SKU、分类、基础属性、条码归本组件。**价格不归这里**——销售价在 `erp-sales` 的定价模块、采购价在 `erp-purchase`（§5.5）。本组件只有 `standard_cost`（标准成本，供财务核算）。

**三个强制字段（决策 68，物理法则，不许省）：**

| 字段 | 为什么强制 |
|---|---|
| `base_uom`（基本计量单位）+ `uom_conversion`（转换因子） | 支持「买箱卖个」等跨单位换算。没有它库存台账对不上 |
| `tracking_type` 枚举（`none` / `batch` / `serial`） | 控制是否启用批次/序列号追踪。没有它无法追溯批次 |
| `standard_cost` | 财务核算要用 |

**表：**

| 表 | 分区 | 说明 |
|---|---|---|
| `products` | 月（`created_at`） | 主表。含 `sku`/`name`/`category_id`/`base_uom`/`tracking_type`/`standard_cost` |
| `product_categories` | 月 | 分类树 |
| `uom_conversions` | 月 | `product_id` + `from_uom` + `to_uom` + `factor` |
| `barcodes` | 月 | `product_id` + `barcode` + `uom` |
| `event_outbox` / `event_inbox` | **周** | 同 §5.2 Task 13 步骤 2 那份，逐字照抄 |
| `command_idempotency` | 不分区 | 同上 |

**gRPC 契约（`mdm.product.v1.ProductService`）：**

```
命令：Create / Update / SetStatus / AddBarcode / SetUomConversion
读：  Get / List / BatchGet / GetSummary / ConvertUom
```

⚠️ `ConvertUom` 必须是**后端接口**，不许前端自己算。跨单位换算错了就是库存对不上，属于核心商业逻辑（§1.3）。

**事件：** `mdm.product.created.v1` / `mdm.product.updated.v1` / `mdm.product.disabled.v1`

**执行：走 SOP-B 的 14 步。** 与 `mdm-customer`（Task 11–16）结构完全一致，逐步替换参数即可。以下三步的验证命令是本组件特有的：

- [ ] **B-13 验证 · gRPC 三个读接口**

```bash
grpcurl -plaintext localhost:9092 list mdm.product.v1.ProductService
grpcurl -plaintext -d '{"ids":["1","999"]}' localhost:9092 mdm.product.v1.ProductService/BatchGet
grpcurl -plaintext -d '{"product_id":"1","from_uom":"BOX","to_uom":"PCS","qty":"2"}' \
  localhost:9092 mdm.product.v1.ProductService/ConvertUom
```
期望：`ConvertUom` 返回换算后数量（如 BOX→PCS 因子 12 时返回 24）。

- [ ] **B-13 验证 · `tracking_type` 三个枚举值都能存**

```bash
for t in none batch serial; do
  curl -fsS -X POST http://localhost:8082/mdm/product/products \
    -H 'Content-Type: application/json' \
    -d "{\"idempotency_key\":\"acc-$t\",\"sku\":\"SKU-$t\",\"name\":\"测试$t\",\"base_uom\":\"PCS\",\"tracking_type\":\"$t\",\"standard_cost\":\"10.00\"}"
done
```

- [ ] **B-14 打 tag `v1.0.0` 并在本仓库更新 submodule 指针**

---

#### Task 19：`erp-inventory` —— 库存管理（物理命令枢纽）

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `erp/inventory` / `erp-inventory` |
| 端口 | HTTP **8086** / gRPC **9096** |
| schema / role | `erp_inventory` / `erp_inventory_rw` |
| 语言 / 外壳 | Go / 外壳一 `go-core` |
| 装配角色 | `optional` |
| `dependencies.components` | `mdm/product@1.0.0`（强依赖，同步 gRPC 校验产品） |
| `dependencies.resources` | `database:postgresql`、`mq:nats` |

**边界**：**所有动物命令的唯一写者**（§2.6 三枢纽）。任何组件想改库存，只能调本组件的 API，不许自己写表。

**表（这里有一条容易写错的）：**

| 表 | 分区 | ⚠️ |
|---|---|---|
| `inventory_balances`（当前库存余额） | **不分区** | **它必须永远小而快**（§11.2.5 注）。分了反而慢 |
| `inventory_movements`（库存流水） | 月（`created_at`） | **强制含 `batch_no` 和 `serial_no` 字段**（§5.5） |
| `warehouses` / `locations`（库位） | 月 | |
| `reservations`（预留） | 月 | Saga 的可补偿资源 |
| `event_outbox` / `event_inbox` | 周 | |
| `command_idempotency` | 不分区 | |

**gRPC 契约（`erp.inventory.v1.InventoryService`）：**

```
命令（全部严格幂等，全部带 idempotency_key）：
  Reserve            预留库存（Saga 的 Try）
  CancelReservation  取消预留（Saga 的 Cancel）
  ConfirmReservation 确认预留 → 转为实际出库（Saga 的 Confirm）
  Inbound / Outbound / Transfer / Adjust

读：
  Get / List / BatchGet / GetBalance
  GetStatus          ⚠️ 供上游做「薛定谔的超时」查询用（§4.5），不许省
```

**事件：** `erp.inventory.reserved.v1` / `erp.inventory.adjusted.v1` / `erp.inventory.transferred.v1`

**消费：** `sales.order.created.v1`（来自 `erp-sales`）

**两条本组件特有的硬要求：**

1. **物理级防超卖**：用**数据库行级锁 + 条件更新**（§4.4），不许用应用层锁、不许用分布式锁（决策 71：不引入 Redis）。

```sql
-- 防超卖的唯一合法写法：条件更新，受影响行数为 0 就是库存不足
UPDATE inventory_balances
   SET available = available - $1,
       reserved  = reserved  + $1,
       version   = version + 1,
       updated_at = now()
 WHERE product_id = $2 AND warehouse_id = $3 AND available >= $1;
-- 检查 RowsAffected()：0 → 库存不足，返回业务错误，不许重试
```

2. **基于属性的测试是强制的**（§8.0、决策 49）。本组件是核心交易组件，不能只靠 AI 写几个 Example 测试。

- [ ] **B-6 步骤特化：写属性测试**

```go
package service

import (
	"testing"

	"pgregory.net/rapid"
)

// 人类定义不变量，框架生成随机边界输入去攻击实现。
// 这一条守的是设计书决策 49：AI 生成的单测只覆盖快乐路径，
// 漏掉并发/边界 Bug。
func TestProperty_库存总数永不为负(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		初始 := rapid.Int64Range(0, 10000).Draw(t, "初始库存")
		操作 := rapid.SliceOfN(rapid.Int64Range(-500, 500), 0, 50).Draw(t, "操作序列")

		inv := newInMemoryInventory(初始)
		for _, delta := range 操作 {
			_ = inv.Apply(delta) // 库存不足时返回错误且不改变状态
		}
		if inv.Available() < 0 {
			t.Fatalf("不变量被破坏：available=%d（初始 %d，操作 %v）",
				inv.Available(), 初始, 操作)
		}
		if inv.Available()+inv.Reserved() != inv.Total() {
			t.Fatalf("不变量被破坏：available + reserved != total")
		}
	})
}

func TestProperty_Reserve严格幂等(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		key := rapid.String().Draw(t, "idempotency_key")
		qty := rapid.Int64Range(1, 100).Draw(t, "数量")
		n := rapid.IntRange(1, 10).Draw(t, "重试次数")

		inv := newInMemoryInventory(1000)
		for i := 0; i < n; i++ {
			_ = inv.Reserve(key, qty) // 同一个 key 重试 n 次
		}
		if inv.Reserved() != qty {
			t.Fatalf("幂等失效：同一 key 重试 %d 次后 reserved=%d，应为 %d",
				n, inv.Reserved(), qty)
		}
	})
}
```

- [ ] **B-13 验证 · 防超卖真的物理生效（并发压测）**

```bash
# 库存 100，并发 200 个请求各扣 1，期望恰好 100 个成功、100 个失败
seq 1 200 | xargs -P 50 -I{} curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST http://localhost:8086/erp/inventory/reservations \
  -H 'Content-Type: application/json' \
  -d '{"idempotency_key":"race-{}","product_id":"1","warehouse_id":"1","qty":"1"}' \
  | sort | uniq -c
```
期望：`100` 个 2xx + `100` 个 4xx。**出现 101 个成功就是防超卖破了**，回去检查条件更新的 `WHERE available >= $1` 与 `RowsAffected()`。

- [ ] **B-13 验证 · `GetStatus` 能被上游查到**

```bash
grpcurl -plaintext -d '{"idempotency_key":"race-1"}' \
  localhost:9096 erp.inventory.v1.InventoryService/GetStatus
```
期望：返回该幂等键对应操作的真实状态（`SUCCEEDED` / `NOT_FOUND` / `FAILED`）。**这是 `erp-sales` 在档 1 做超时补偿时唯一能问的地方**（§4.5）。

---

#### Task 20：`erp-finance` —— 财务管理（事件汇枢纽 / 会计引擎）

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `erp/finance` / `erp-finance` |
| 端口 | HTTP **8087** / gRPC **9097** |
| schema / role | `erp_finance` / `erp_finance_rw` |
| 语言 / 外壳 | Go / 外壳一 `go-core` |
| 装配角色 | `optional` |
| `dependencies.components` | **空**（几乎只被命令 + 听事件，§2.6） |
| `dependencies.resources` | `database:postgresql`、`mq:nats` |

**定位**：**不是业务计算器，只把业务数据「翻译」成会计凭证**（§附录 I「会计引擎」）。

**两条核心职责（决策 70，这是 ERP 区别于普通进销存的灵魂）：**

1. **会计日历（Accounting Calendar）与期间控制（Period Lock）**：已关账期间**严禁修改历史单据**。其他组件在修改/删除单据时**必须**先调本组件校验期间状态。
2. **标准版仅支持单币种（本位币）**（决策 63）。多币种需求走 `customer_fork` 定制，**不许在标准件里加 `if currency`**。

**表：**

| 表 | 分区 | ⚠️ |
|---|---|---|
| `accounting_periods`（会计日历） | 不分区 | 小表，永远热 |
| `finance_journal_entries`（分录明细） | **按 `accounting_period`**（不是 `created_at`！） | §11.2.5 明确写的是会计期间 |
| `journal_lines` | 跟随主表分区 | §11.2.4 |
| `ar_ledger`（应收台账） / `ap_ledger`（应付台账） | 月 | |
| `vouchers`（凭证） | 按 `accounting_period` | |
| `credit_snapshots`（信用额度本地摘要副本） | 月 | 外键 + name/status/version（§3.8） |
| `event_outbox` / `event_inbox` | 周 | |
| `command_idempotency` | 不分区 | |

**gRPC 契约（`erp.finance.v1.FinanceService`）：**

```
命令：CreateVoucher / ReverseVoucher / ClosePeriod / OpenPeriod
     CheckCredit        信用额度校验（供 erp-sales 同步调用）
     ReserveCredit / CancelCreditReservation / ConfirmCreditReservation   （Saga 三件套）
读：  Get / List / BatchGet / GetStatus / GetPeriodStatus
```

**事件（发布）：** `finance.voucher.created.v1` / `finance.credit.rejected.v1` / `finance.period.closed.v1`

**事件（消费）：** `sales.order.created.v1`、`erp.inventory.adjusted.v1`、`erp.inventory.transferred.v1`

**归档规则特殊（§11.7）：只有已关账期间的凭证才能归档。** 未关账期间的凭证永远热。

- [ ] **B-6 步骤特化：写期间控制的属性测试**

```go
// 决策 70 的不变量：已关账期间的任何单据都不许被修改。
// 这一条错了，财务报表就不可信——月结后数据被篡改是 ERP 最严重的故障之一。
func TestProperty_已关账期间不可写(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		period := rapid.SampledFrom([]string{"2026-01", "2026-02", "2026-03"}).Draw(t, "期间")
		fin := newInMemoryFinance()
		fin.ClosePeriod(period)

		err := fin.CreateVoucher(Voucher{Period: period})
		if err == nil {
			t.Fatalf("已关账期间 %s 仍允许写入凭证（决策 70）", period)
		}
		err = fin.ReverseVoucher("任意凭证号", period)
		if err == nil {
			t.Fatalf("已关账期间 %s 仍允许冲销（决策 70）", period)
		}
	})
}

// 复式记账的不变量：每张凭证借贷必平
func TestProperty_凭证借贷必平(t *testing.T) {
	rapid.Check(t, func(t *rapid.T) {
		lines := rapid.SliceOfN(genJournalLine(), 2, 20).Draw(t, "分录行")
		v, err := buildVoucher(lines)
		if err != nil {
			return // 构造非法时拒绝是对的
		}
		if v.TotalDebit().Cmp(v.TotalCredit()) != 0 {
			t.Fatalf("借贷不平：借 %s 贷 %s", v.TotalDebit(), v.TotalCredit())
		}
	})
}
```

- [ ] **B-13 验证 · 期间控制**

```bash
curl -fsS -X POST http://localhost:8087/erp/finance/periods/2026-01/close \
  -H 'Content-Type: application/json' -d '{"idempotency_key":"acc-close-01"}'
# 已关账期间再写凭证，期望 4xx
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:8087/erp/finance/vouchers \
  -H 'Content-Type: application/json' \
  -d '{"idempotency_key":"acc-v-01","period":"2026-01","lines":[]}'
```
期望：关账 200；关账后写凭证返回 4xx（不是 5xx——这是业务规则拒绝，不是系统错误）。

- [ ] **B-13 验证 · 金额精度**

```bash
grpcurl -plaintext -d '{"ids":["1"]}' localhost:9097 erp.finance.v1.FinanceService/BatchGet \
  | grep -E '"(amount|credit_limit|total_debit)"'
```
期望：所有金额字段是 **string**，不是 number。**出现 number 就是契约写错了**——`double` 跨语言序列化会丢精度（§6.1 Task 11 步骤 2 的注）。

---

#### Task 21：`erp-sales` —— 销售管理（含同步调用链与 Saga 补偿）

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `erp/sales` / `erp-sales` |
| 端口 | HTTP **8084** / gRPC **9094** |
| schema / role | `erp_sales` / `erp_sales_rw` |
| 语言 / 外壳 | Go / 外壳一 `go-core` |
| 装配角色 | `optional` |
| **强依赖** | `mdm/customer@1.0.0`、`mdm/product@1.0.0`、`erp/inventory@1.0.0`、`erp/finance@1.0.0` |
| **弱依赖** | `{ id: infra/workflow@1.0.0, optional: true }` |
| `dependencies.resources` | `database:postgresql`、`mq:nats` |

⚠️ **弱依赖 `infra/workflow` 在档 1 还不存在**（它是档 2 的组件）。这**正是要验的**：平台对弱依赖缺失的行为是「警告但继续，且**完全不注入** `INFRA_WORKFLOW_ENDPOINT`」（§3.6）。所以本组件的代码里**必须**用 `besdk.Endpoint("infra/workflow", "")` 的两返回值形态判断，不许假设变量存在。

**表：**

| 表 | 分区 |
|---|---|
| `sales_orders` | 月（`created_at`） |
| `sales_order_items` | 跟随主表（§11.2.4） |
| `pricelists` / `pricelist_items`（定价策略） | 月 |
| `customer_snapshots` / `product_snapshots`（摘要副本：外键 + name/status/version） | 月 |
| `saga_transactions`（Saga 状态机 + 待对账表） | 月 |
| `event_outbox` / `event_inbox` | 周 |
| `command_idempotency` | 不分区 |

**gRPC 契约（`erp.sales.v1.SalesService`）：**

```
命令：CreateOrder / ConfirmOrder / CancelOrder / ShipOrder
读：  Get / List / BatchGet / GetSummary / GetStatus
试算：CalculateOrderPriceDryRun    ⚠️ 前端联动的唯一合法入口（§8.4、决策 69）
```

**事件（发布）：** `sales.order.created.v1` / `sales.order.confirmed.v1` / `sales.order.cancelled.v1` / `sales.order.shipped.v1`

**事件（消费）：** `finance.credit.rejected.v1`、`opportunity.won.v1`（后者要等档 2 的 `crm-opportunity`）

**同步调用链（§8.2，顺序不能改）：**

```
1. 校验客户（gRPC → mdm/customer.BatchGet）
2. 校验产品（gRPC → mdm/product.BatchGet）
3. 预留库存（gRPC → erp/inventory.Reserve）        ← Saga 的 Try #1
4. 本地缓存校验信用额度 → 不足则 gRPC → erp/finance.ReserveCredit  ← Saga 的 Try #2
5. 创建订单 + 同事务写 Outbox 发 sales.order.created.v1
任一步失败 → 对已成功的步骤逆序调 Cancel API
```

**⚠️ 三条本组件特有的、最容易写错的铁律：**

**① 超时后严禁直接补偿，必须先查状态（§4.5「薛定谔的超时」）**

```go
// ❌ 错误写法：超时就 Cancel。会误杀「上游认为超时、下游其实已成功」的订单
if errors.Is(err, context.DeadlineExceeded) {
    inventoryClient.CancelReservation(ctx, key)   // 绝对不许这样写
}

// ✅ 正确写法
if errors.Is(err, context.DeadlineExceeded) {
    st, qerr := inventoryClient.GetStatus(ctx, &invv1.GetStatusRequest{
        IdempotencyKey: key,
    })
    switch {
    case qerr != nil:
        // GetStatus 也超时 → 写本地「待对账」表，由定时对账兜底修复（§4.5 第 5 步）
        return s.enqueueReconciliation(ctx, tx, key, "inventory.Reserve")
    case st.State == invv1.State_SUCCEEDED:
        // 下游其实成功了 → 继续后续流程，不许 Cancel
        return s.continueAfterReserve(ctx, tx, key)
    default:
        // 确认未成功 → 安全取消
        _, cerr := inventoryClient.CancelReservation(ctx, key)
        return cerr
    }
}
```

**② 补偿失败超 3 次 → 降级为异常待办，拒绝无限重试（§4.4.4、决策 44）**

```go
// 「补偿的补偿」也失败时，绝不能无限期自动重试——那是补偿风暴
if saga.CompensationAttempts >= 3 {
    saga.State = SagaSuspended
    // 弱依赖：workflow 没装时只记日志 + 落 saga 表，不许崩
    if addr, ok := besdk.Endpoint("infra/workflow", "grpc"); ok {
        _ = workflowClient(addr).CreateTask(ctx, &wfv1.CreateTaskRequest{
            Type:       "exception",
            AssigneeRole: "system-admin",
            RefID:      saga.ID,
            Title:      "Saga 补偿失败，需人工核查",
        })
    } else {
        log.Warn("infra/workflow 未装配，异常任务只落本地 saga 表",
            "saga_id", saga.ID)
    }
    return nil // 不再重试
}
```

**③ 价格计算在后端，前端只能调 DryRun（决策 69）**

`CalculateOrderPriceDryRun` 必须是**纯计算、无副作用、不写库**的接口。前端通过防抖调用它拿预估总价（§8.4）。**前端严禁复写折扣公式**——算错价格就是资损。

- [ ] **B-6 步骤特化：Saga 的三个测试**

```go
func TestSaga_库存预留成功但信用不足时逆序回滚(t *testing.T) {
	// 断言：CancelReservation 被调用了恰好一次，且带的是同一个 idempotency_key
}

func TestSaga_下游超时时先查状态再决定(t *testing.T) {
	// 用 mock 让 Reserve 超时、GetStatus 返回 SUCCEEDED，
	// 断言：CancelReservation 一次都没被调用（不许误杀）
}

func TestSaga_GetStatus也超时时进待对账表(t *testing.T) {
	// 断言：saga_transactions 里多了一条 state=PENDING_RECONCILE 的记录，
	// 且 CancelReservation 一次都没被调用
}

func TestSaga_补偿失败3次后挂起(t *testing.T) {
	// 断言：state 变成 SUSPENDED，且不再有第 4 次补偿调用
}

func TestDryRun_无副作用(t *testing.T) {
	// 断言：调用 CalculateOrderPriceDryRun 前后，sales_orders 与 event_outbox 行数不变
}
```

- [ ] **B-13 验证 · 全链路创建订单**

```bash
curl -fsS -X POST http://localhost:8084/erp/sales/orders \
  -H 'Content-Type: application/json' \
  -d '{"idempotency_key":"acc-order-001","customer_id":"1",
       "items":[{"product_id":"1","qty":"2","uom":"PCS"}]}'
```
期望：201，返回的订单里有计算好的 `total_amount`（string）。

- [ ] **B-13 验证 · 强依赖缺失时平台阻断（§9.6.2 用例）**

```bash
# 临时把 erp-inventory 从 brickkit.yaml 里删掉，期望 up 解析期报错
brickkit up --dry-run; echo "exit=$?"
```
期望：非 0 退出，报错指出 `erp/sales` 的强依赖 `erp/inventory` 不可获取。

- [ ] **B-13 验证 · 弱依赖缺失时变量根本不存在（§3.6，这一条最容易搞错）**

```bash
docker exec erp-sales-1-0-0 env | grep -c 'INFRA_WORKFLOW_ENDPOINT'
```
期望：**输出 `0`**。不是空字符串，是**这个键根本不在 env 里**。

**如果输出 1 且值为空**，说明平台行为与设计书 §3.6 的断言不一致——**先在 `be-acceptance/platform` 记一条红用例，再回 brickKit 仓库修，不许在业务侧绕**（§9.6.2）。

- [ ] **B-13 验证 · 依赖方拿到的 gRPC 地址是 `http://` 开头（补上档 0 欠的用例 4）**

```bash
docker exec erp-sales-1-0-0 env | grep -E 'MDM_CUSTOMER_(GRPC_)?ENDPOINT'
```
期望：

```
MDM_CUSTOMER_ENDPOINT=http://mdm-customer-1-0-0:8080
MDM_CUSTOMER_GRPC_ENDPOINT=http://mdm-customer-1-0-0:9090
```

**两条都必须以 `http://` 开头，没有 `grpc://`。** 这一条现在可以在 `platform/README.md` 的第 4 条上真正打勾了。

---

#### Task 22：§9.6.2 的 20 条平台验收清单 —— 档 1 出档

**Files:**
- Create: `tools/be-acceptance/platform/platform_test.go`
- Modify: `tools/be-acceptance/platform/README.md`
- Modify: `Makefile`

**Interfaces:**
- Produces：`make platform-acceptance` —— 20 条用例可重跑。**平台升级后重跑这一批就是回归测试**（决策 96）。

⚠️ **这批用例的被测对象是 brickKit 本身，不是我们的业务。** 每一条都对应设计书某处的断言，跑一次就知道那处断言还成不成立。

- [ ] **步骤 1：逐条实现 20 个测试函数**

| # | 测试函数名 | 验什么 | 怎么验 | 设计书 |
|---|---|---|---|---|
| 1 | `Test平台_未知键当场报错` | 未知键不是静默忽略 | 往 `component.yaml` 塞 `assembly_role: optional`，期望 `up` 失败 | §3.5 |
| 2 | `Test平台_metadata随组件分发` | `assembly.yaml` 靠 `artifacts` 分发 | 声明 `type: metadata`，`up` 后检查 `.brickkit/artifacts/<版本化服务名>/metadata/assembly.yaml` 在 | §3.5 |
| 3 | `Test平台_地址变量名由ID推导且不带版本号` | 变量命名规则 | 断言 `MDM_CUSTOMER_ENDPOINT=http://mdm-customer-1-0-0:8080` | §2.1、§3.4 |
| 4 | `Test平台_额外端口地址是http不是grpc` | 没有 `grpc://` | 断言 `MDM_CUSTOMER_GRPC_ENDPOINT` 以 `http://` 开头，且剥掉 scheme 后 gRPC 客户端能连上 | §2.1 |
| 5 | `Test平台_弱依赖缺失时不注入变量` | 是「不存在」不是「空串」 | 把可选依赖从 `brickkit.yaml` 删掉，断言容器 `env` 里根本没有那个键 | §3.6 |
| 6 | `Test平台_保留变量会被跳过` | `*_ENDPOINT` 后缀是保留的 | 故意起一个 `otelEndpoint` 配置项，断言 `up` 给警告且容器里拿不到值 | §2.7.3 |
| 7 | `Test平台_config数组会被渲染成方括号形态` | 必须写逗号分隔字符串 | 断言 `ENABLED_COMPONENTS` 写成数组时容器里是 `[a b c]` 而非 JSON | §6.1 |
| 8 | `Test平台_启停跟着上层走` | 级联与「删条目≠enabled:false」 | 顶层写 `enabled: false`，断言下层跟着不启动；再验两种写法不等价 | §3.6、§5.10 |
| 9 | `Test平台_Fork遮蔽按sources顺序` | 同 id 同 version 靠顺序 | 两份源断言靠前的赢；再验改了 `metadata.id` 后 `*_ENDPOINT` 消失 | §3.4.1 |
| 10 | `Test平台_默认启动宽限是60秒` | 不是 30 | 造一个冷启动 45 秒的组件，不写 `startPeriodSeconds`，断言它能起来 | §12.3.5 |
| 11 | `Test平台_local三件事` | 不生成 service / `extra_hosts` / 换 `localPort` | 断言三件都发生 | §13.1 |
| 12 | `Test平台_local的额外端口不被改写` | gRPC 端口没有 `localPort` | 断言依赖方拿到的 gRPC 地址仍是 Manifest 里的端口；再验两个 local 组件撞同一额外端口时 `up` 报错 | §3.5.1.1 |
| 13 | `Test平台_local不生成迁移容器` | 合并后迁移归外壳 | 断言 `up` 给警告，且库里表没建 | §13.3 铁律五 |
| 14 | `Test平台_local加k8s直接报错` | 没有中间态 | 断言生成阶段失败 | 决策 88 |
| 15 | `Test平台_K8s下labels落在Deployment与Pod两处` | Pod 上也要有 | `--dry-run` 出清单，两处都断言 | §7.5.1 |
| 16 | `Test平台_K8s下hostname必填且唯一` | 是硬报错不是静默 | 两个组件写同一 hostname，断言硬报错 | §6.3 |
| 17 | `Test平台_up只打印建库语句不建库` | 平台不建库 | 断言输出里有 `CREATE DATABASE`，而库并没有被创建 | §2.7.2 |
| 18 | `Test平台_remove连archived一起删` | 数据丢失风险是真的 | 先 `sync` 归档，再 `remove`，断言归档目录也没了 | §9.4.2 |
| 19 | `Test平台_精确版本` | 范围版本被拒绝 | 写 `^1.2`，断言报错 | 四条铁律之一 |
| 20 | `Test平台_本地源不受签名约束` | 签名整体不生效 | 开 `requireSignature: true`，断言本地源组件照装 | §9.4.1 |

⚠️ **用例 18 要在一次性的临时项目目录里跑**，绝不能在本仓库跑——`brickkit remove` 会真的删源码目录，而我们的组件是 submodule。测试里先 `t.TempDir()` 建一个最小项目再验。

- [ ] **步骤 2：跑一遍，红的那些不许绕**

```bash
make platform-acceptance
```

对每一条红的：

1. 先在 `platform/README.md` 上记清「红在哪、期望什么、实际什么」；
2. 回 `brickKit` 仓库修；
3. **不许在业务侧绕过去**——绕过去的那一条，会在 61 个组件时变成 61 处绕法（§9.6.2）。

- [ ] **步骤 3：`make platform-acceptance` 接上 Makefile 并 commit**

```makefile
platform-acceptance:  ## §9.6.2 那 20 条平台验收（被测对象是 brickKit 本身）
	@cd tools/be-acceptance && go test ./platform/ -v -count=1
.PHONY: platform-acceptance
```

**🏁 档 1 出档检查（五条全绿才进档 2）：**

```bash
make check                 # ① 基础资源
make registry-check        # ② 册子自洽
make gates                 # ③ import 扫描
make tier0                 # ④ 五个组件各自的档 0 六项
make platform-acceptance   # ⑤ 20 条平台验收逐条打勾
```


---

## 第 7 部分 · 档 2：业务闭环（加 8 砖，共 13 个组件）

> 出档条件：附录 E 全链路跑通 + Saga 补偿与超时查询走一遍 + DLQ 进得去出得来。

**这一档新增的 8 个：**

| 仓库 | 语言 | 外壳 | 端口 | 为什么在切片里 |
|---|---|---|---|---|
| `infra-iam-casdoor` | Go | 三 | 8200/9200 | 全链路要登录；`/api/tenant/features` 是前端动态路由的数据源 |
| `infra-workflow` | Go | 三 | 8201/9201 | 闭环里的「审批」那一步；Saga 补偿失败降级也要它 |
| `infra-notification` | Go | 三 | 8202/9202 | 闭环里的「钉钉通知」要经它路由 |
| `integration-im-dingtalk` | Go | 三 | 8207/9207 | 任选一个 IM 通道即可（§5.13 切片列） |
| `crm-opportunity` | Go | 二 | 8102/9102 | 闭环的起点：赢单 |
| **`infra-print`** | **Python** | 五 | 8400/9400 | 闭环的终点：打印送货单 PDF。**档 3 要靠它验 Python 外壳**（§9.6.1） |
| `infra-bff-mobile` | **TypeScript** | 独立 | 8500 | 复杂聚合层；验 DataLoader 绑 `batchGet` 防 N+1 |
| `frontend-standard` | **TypeScript** | 独立 | 80 | 只做这几个模块的页面 |

⚠️ **档 2 引入了另外两种语言**，所以要先把 `be-sdk-python` 与 `be-sdk-ts` 建起来（SOP-L 那 10 项横切能力，三种语言各一份，行为必须一致）。

#### Task 23：八个组件骨架 + 两个 SDK 骨架 → **检查点 CP-4**

- [ ] **步骤 1：建目录**

```bash
for p in infra/iam-casdoor infra/workflow infra/notification infra/print \
         infra/bff-mobile integration/im-dingtalk crm/opportunity frontend/standard; do
  mkdir -p "components/$p"
done
# 后端 Go/Python 的 SOP-B 结构
for p in infra/iam-casdoor infra/workflow infra/notification infra/print \
         integration/im-dingtalk crm/opportunity; do
  mkdir -p "components/$p"/{contracts/events,migrations,backend}
done
# TS 的两个走各自结构
mkdir -p components/infra/bff-mobile/{contracts,src}
mkdir -p components/frontend/standard/{apps/pc-web/src,apps/mobile,packages,docker}
mkdir -p tools/be-sdk-python tools/be-sdk-ts
```

- [ ] **步骤 2：⏸ 检查点 CP-4 —— 停下，请人创建仓库**

```
目录已建好：
  components/infra/iam-casdoor/      components/infra/workflow/
  components/infra/notification/     components/infra/print/
  components/infra/bff-mobile/       components/integration/im-dingtalk/
  components/crm/opportunity/        components/frontend/standard/
  tools/be-sdk-python/               tools/be-sdk-ts/

请在 github.com/brickKit/ 下创建这 10 个空仓库（不要 README / .gitignore / license）：
  infra-iam-casdoor
  infra-workflow
  infra-notification
  infra-print
  infra-bff-mobile
  integration-im-dingtalk
  crm-opportunity
  frontend-standard
  be-sdk-python
  be-sdk-ts
```

**本任务在此中止，等人回「建好了」。**

---

#### Task 24：`be-sdk-python` 与 `be-sdk-ts` —— 三种语言行为必须一致

**Files:**
- `tools/be-sdk-python/besdk/{endpoint.py,tx.py,outbox.py,events.py,otel.py,query.py,archive.py,logging.py,metrics.py}`
- `tools/be-sdk-ts/src/{endpoint.ts,outbox.ts,events.ts,otel.ts,query.ts,logging.ts,metrics.ts}`

**Interfaces:**
- Produces：与 `be-sdk-go` **一一对应**的 API。名字可按各语言习惯（`endpoint()` / `withTx()` / `publishOutbox()`），**行为必须逐条一致**。

⚠️ **`be-sdk-ts` 不需要 `tx.py`/`archive` 那两项** —— `infra-bff-mobile` **严禁直连 DB**（§6.5），`frontend-*` 更没有库。TS 版只有 `endpoint` / `events`（消费侧防环与幂等）/ `otel` / `query`（GraphQL 深度与复杂度限制）/ `logging` / `metrics`。

- [ ] **步骤 1：三份 SDK 的行为一致性测试（同一张表，三处各实现一遍）**

| 断言 | Go | Python | TS |
|---|---|---|---|
| `endpoint()` 剥掉 `http://` 前缀 | ✅ | ✅ | ✅ |
| 变量不存在时返回「缺失」而不是空串/不抛异常 | ✅ | ✅（`os.environ.get()`，**不许用 `os.environ["X"]`**） | ✅ |
| `withTx` 用 `SET LOCAL`（不带 LOCAL 会跨组件串数据） | ✅ | ✅（Alembic 侧 `version_table_schema`） | — |
| `otelBaseUrl` 为空 → Blackhole，不阻塞不抛异常 | ✅ | ✅ | ✅ |
| `hop_count > 5` 丢弃进 DLQ | ✅ | ✅ | ✅ |
| 消费 `version` 不大于本地时跳过 | ✅ | ✅ | ✅ |
| List 默认注入 90 天窗口 | ✅ | ✅ | GraphQL 侧：`max_depth 5` / `max_complexity 100` / `persisted_queries_only` |

- [ ] **步骤 2：Python SDK 的一处特殊注意**

```python
# tools/be-sdk-python/besdk/endpoint.py
import os

def endpoint(dep: str, extra: str = "") -> tuple[str, bool]:
    """读平台注入的 *_ENDPOINT 并剥掉 scheme。

    ⚠️ 必须用 os.environ.get()，不许用 os.environ["X"]。
    弱依赖缺失时那个变量**根本不存在**，不是空字符串——
    用下标访问会在启动时崩溃，而这是平台刻意的设计（§3.6）。
    """
    name = _env_name(dep, extra)
    v = os.environ.get(name)
    if not v:
        return "", False
    for scheme in ("http://", "https://"):
        if v.startswith(scheme):
            v = v[len(scheme):]
            break
    return v.rstrip("/"), True
```

- [ ] **步骤 3：三份各自 push + 打 tag `v0.1.0`，接成 submodule**

- [ ] **步骤 4：把两个新 SDK 加进 `be-acceptance` 的 import 扫描白名单**

```go
var allowedShared = map[string]bool{
	"github.com/brickKit/be-sdk-go":     true,
	"github.com/brickKit/be-sdk-python": true,
	"github.com/brickKit/be-sdk-ts":     true,
}
```
Python 侧扫 `import besdk` 放行、`import` 任何其他组件包报违规；TS 侧扫 `@brickkit/be-sdk-ts` 放行。

**验证：** 三份 SDK 的一致性测试表逐行打勾；`make gates` 绿。

---

#### Task 25：`infra-iam-casdoor` —— 发牌官的薄适配层

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `infra/iam-casdoor` / `infra-iam-casdoor` |
| 端口 | HTTP **8200** / gRPC **9200** |
| schema / role | `infra_iam_casdoor` / `infra_iam_casdoor_rw` |
| 语言 / 外壳 | Go / 外壳三 `go-infra` |
| 装配角色 | `slot:iam`（Default）。`slot_name: iam` 写在 `assembly.yaml` |
| `dependencies.components` | **空** |
| 代码量目标 | **~500 行**（§6.1：它只是薄适配层） |

⚠️ **它不是 Casdoor 本身。** Casdoor 官方镜像是**带外容器**（Task 1 已拉起），本组件是它前面那层薄适配层。**日常认证流（用户登录）不经过本组件**——浏览器直接走 OIDC 标准协议与 Casdoor 通信（附录 D）。

**三个职责，一个不多：**

1. **`GET /api/tenant/features`** —— 前端动态路由的数据源
2. **Webhook 事件桥接** —— Casdoor 的用户/角色变更 → 发成事件进 NATS
3. **首次部署初始化** —— 建默认应用与角色

**⚠️ `/api/tenant/features` 的数据从哪来（§6.1，这一条最容易做错）：**

平台**不给任何组件「当前装配了什么」的视图**。所以这份清单只能从外面喂进来：

> `be-ops` 在生成 `brickkit.yaml` 时，把本次启用的组件清单写进本组件的 `config.enabledComponents`，适配层读环境变量 `ENABLED_COMPONENTS` 后**原样下发**。

```yaml
# component.yaml 的 configSchema 片段
configSchema:
  type: object
  properties:
    enabledComponents:
      type: string        # ⚠️ 必须是字符串，不能写成 YAML 数组
      default: ""
      description: |
        逗号分隔的组件 ID 列表。平台把 config 值转成环境变量时只对
        字符串/布尔/数字做处理，**数组会被渲染成 [a b c] 而不是 JSON**，
        组件这边解析不出来（§6.1）。
    casdoorBaseUrl: { type: string }
    casdoorClientId: { type: string }
    iamJwksUrl: { type: string }
    otelBaseUrl: { type: string, default: "" }
```

⚠️ 配置项**键名**写错平台会警告并猜出你想写的那个，但**值不校验**——喂错内容不会有任何运行时失败，只会让前端少显示几个菜单。**所以 `be-ops` 自己要对这份清单做校验**（Task 32）。

⚠️ **业务组件不对本组件声明任何依赖**（决策 87）。权限校验一律走 **JWT 本地验签**，JWKS 地址从各组件 `configSchema` 的 `iamJwksUrl` 注入。这不是将就——一旦建了依赖边，注入的变量名就带上了实现的名字（`INFRA_IAM_CASDOOR_ENDPOINT`），换 Keycloak 就从改一个字段变成改几十个仓库（§5.11）。

**表：** `feature_snapshots`（月分区，记录每次下发的清单，供排障）、`event_outbox`/`event_inbox`（周）、`command_idempotency`。

- [ ] **执行 SOP-B 14 步**，其中特化验证：

```bash
# ① features 接口返回逗号分隔清单解析出来的数组
curl -fsS http://localhost:8200/api/tenant/features | jq '.components'

# ② 验平台断言用例 7：config 数组会被渲染成 [a b c]
#    故意在 brickkit.yaml 里把 enabledComponents 写成 YAML 数组，
#    断言容器里拿到的是 "[a b c]" 而不是 JSON
docker exec infra-iam-casdoor-1-0-0 env | grep ENABLED_COMPONENTS

# ③ 断言业务组件没有对 IAM 的依赖边
grep -rn 'infra/iam' components/*/*/component.yaml && \
  echo "✗ 有组件对 IAM 建了依赖边，slot:iam 名存实亡（决策 87）" || \
  echo "✓ 无组件对 IAM 建依赖边"
```

---

#### Task 26：`infra-workflow` —— 轻量级审批任务聚合与分发中心

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `infra/workflow` / `infra-workflow` |
| 端口 | HTTP **8201** / gRPC **9201** |
| schema / role | `infra_workflow` / `infra_workflow_rw` |
| 语言 / 外壳 | Go / 外壳三 `go-infra` |
| 装配角色 | `default` |
| `dependencies.components` | **空**（严禁反向同步调用业务组件） |

**三条铁律（§6.6，全是「不许做什么」）：**

| ❌ | 为什么 |
|---|---|
| **严禁包含业务规则判断** | 复杂的业务审批路由由业务组件在标准代码或 Fork 中实现（决策 27） |
| **严禁直接查询业务数据库** | 跨 schema JOIN 被 PG RBAC 物理阻断，想查也查不到 |
| **严禁反向同步调用业务组件** | §4.2 同步图里那条虚线：`WF -.->|严禁同步调用业务| BIZ` |

**四个职责：** 全局待办聚合 / 统一审批历史 / 任务状态流转 / 异常任务处理。

**异常任务交互（决策 41）：** 业务规则校验失败时，**不暴露「重试」按钮**，而是创建异常待办任务，通知用户修正数据后重新提交。「用户疯狂点重试但问题依旧」是要避免的坑。

**表：** `tasks`（月分区，含 `type` 枚举 `approval`/`exception`）、`task_histories`（跟随主表）、`event_outbox`/`event_inbox`（周）、`command_idempotency`。

**gRPC：** `CreateTask` / `Complete` / `Reject` / `Get` / `List` / `BatchGet` / `GetStatus`
**事件（发布）：** `workflow.task.created.v1` / `workflow.task.completed.v1` / `workflow.task.rejected.v1`

- [ ] **执行 SOP-B 14 步**，特化验证：

```bash
# 断言 workflow 没有任何对业务组件的依赖边
grep -A5 'components:' components/infra/workflow/component.yaml | grep -E 'erp/|crm/|mdm/|hrm/' \
  && echo "✗ workflow 反向依赖了业务组件（§6.6）" || echo "✓ 无反向依赖"
```

---

#### Task 27：`infra-notification` —— 统一通知中心

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `infra/notification` / `infra-notification` |
| 端口 | HTTP **8202** / gRPC **9202** |
| schema / role | `infra_notification` / `infra_notification_rw` |
| 语言 / 外壳 | Go / 外壳三 `go-infra` |
| 装配角色 | `default` |
| `dependencies.components` | **全部 `optional: true`** ⚠️ |

⚠️ **生成器铁律三（§2.4）在这里落地：聚合型组件的依赖必须全部 `optional: true`。**

```yaml
dependencies:
  components:
    # 全部 channel 适配器都是弱依赖。一条写成强依赖，客户没买那个通道时
    # 整个通知中心起不来（决策 98）
    - { id: integration/im-dingtalk@1.0.0,      optional: true }
    - { id: integration/im-wechat-work@1.0.0,   optional: true }
    - { id: integration/im-feishu@1.0.0,        optional: true }
    - { id: integration/im-slack@1.0.0,         optional: true }
    - { id: integration/im-teams@1.0.0,         optional: true }
    - { id: integration/email@1.0.0,            optional: true }
    - { id: integration/sms@1.0.0,              optional: true }
```

代码侧配套：**按变量在不在决定要不要挂那个通道**。

```go
// 启动时扫一遍所有已知通道，变量存在的才注册
for _, ch := range knownChannels {
    if addr, ok := besdk.Endpoint(ch.ComponentID, "grpc"); ok {
        registry.Register(ch.Name, newClient(addr))
        log.Info("通道已装配", "channel", ch.Name)
    } else {
        log.Info("通道未装配，跳过", "channel", ch.Name)
    }
}
```

**职责：** 接收业务组件的「通知意图」和系统告警 → 查用户通道偏好 → **并发**路由给下层所有已装配的 `channel_adapter`。

**表：** `notification_records`（**月分区**，§11.2.5）、`user_channel_prefs`（月）、`event_outbox`/`event_inbox`（周）、`command_idempotency`。

- [ ] **执行 SOP-B 14 步**，特化验证：

```bash
# 只装了钉钉，其余 6 个通道缺失 —— notification 必须照常启动
docker exec infra-notification-1-0-0 env | grep -c 'INTEGRATION_IM_FEISHU_ENDPOINT'   # 期望 0
curl -fsS http://localhost:8202/healthz                                                # 期望 200
docker logs infra-notification-1-0-0 2>&1 | grep '通道未装配'                          # 期望有 6 条
```

---

#### Task 28：`integration-im-dingtalk` —— 钉钉通道适配器

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `integration/im-dingtalk` / `integration-im-dingtalk` |
| 端口 | HTTP **8207** / gRPC **9207** |
| schema / role | `integration_im_dingtalk` / `integration_im_dingtalk_rw` |
| 语言 / 外壳 | Go / 外壳三 `go-infra` |
| 装配角色 | `channel:im`（**可与企微/飞书/Slack/Teams 同时装配**，决策 26） |
| `dependencies.components` | **空** |

**职责（§6.9，所有 `integration-*` 一致）：** 只监听事件 + 调外部 API + 发回调事件。**严禁包含任何业务逻辑**——它是「协议翻译官」和「消息搬运工」。

**表：** `send_records`（月分区，幂等去重）、`callback_records`（月）、`event_outbox`/`event_inbox`（周）。

**密钥处理（§9.4.1）：** 钉钉的 AppKey/AppSecret 从 `configSchema` 注入，**绝不硬编码，绝不进版本控制**。交付时由主管理员填进客户的 `brickkit.yaml`。

- [ ] **执行 SOP-B 14 步**，特化验证：本地用一个 mock 钉钉 HTTP server 顶替真实 API，断言发送记录幂等（同一 `idempotency_key` 投两次只调一次外部 API）。

---

#### Task 29：`crm-opportunity` —— 商机管理（闭环的起点）

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `crm/opportunity` / `crm-opportunity` |
| 端口 | HTTP **8102** / gRPC **9102** |
| schema / role | `crm_opportunity` / `crm_opportunity_rw` |
| 语言 / 外壳 | Go / 外壳二 `go-backoffice` |
| 装配角色 | `optional` |
| **强依赖** | `mdm/customer@1.0.0`、`mdm/product@1.0.0` |

⚠️ **CRM 与 ERP 之间零同步边，只有事件握手**（§1.4 第 6 句、§2.6）。所以 `crm-opportunity` 的 `dependencies` 里**绝不许出现 `erp/sales`**。赢单转订单走 `opportunity.won.v1` 事件，不走 gRPC。这是「CRM 与 ERP 可独立拔插」的物理前提。

**表：** `opportunities`（月分区）、`opportunity_stages`（月）、`customer_snapshots`/`product_snapshots`（摘要副本）、`event_outbox`/`event_inbox`（周）、`command_idempotency`。

**gRPC：** `Create` / `Update` / `AdvanceStage` / `Win` / `Lose` / `Get` / `List` / `BatchGet` / `GetSummary`
**事件（发布）：** `crm.opportunity.created.v1` / `crm.opportunity.stage_changed.v1` / **`opportunity.won.v1`** / `crm.opportunity.lost.v1`

⚠️ **`opportunity.won.v1` 的 subject 不带 `crm.` 前缀**，这是设计书附录 E 与 §4.3 事件图里写死的名字。其余事件照 `{domain}.{aggregate}.{action}.v{n}` 命名（§3.7）。**这一处不一致要在事件清单里写明，不然半年后有人会「顺手改统一」，把 `erp-sales` 的消费者打断。**

- [ ] **执行 SOP-B 14 步**，特化验证：

```bash
# 断言 crm 对 erp 零同步边
grep -A8 'components:' components/crm/opportunity/component.yaml | grep 'erp/' \
  && echo "✗ CRM 对 ERP 建了同步边（§2.6）" || echo "✓ CRM↔ERP 零同步边"
```

---

#### Task 30：`infra-print` —— 打印模板与条码管理中心（第一个 Python 组件）

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `infra/print` / `infra-print` |
| 端口 | HTTP **8400** / gRPC **9400** |
| schema / role | `infra_print` / `infra_print_rw` |
| 语言 / 外壳 | **Python** / 外壳五 `py-render` |
| 装配角色 | `default` |
| **`startPeriodSeconds`** | **`120`** ⚠️ |
| `dependencies.components` | **空** |

⚠️ **`startPeriodSeconds: 120` 不许省。** `WeasyPrint` / `NumPy` / `Pandas` 的 import 本身就要好几秒，Python 组件要预加载（§12.3.5）。超了会：Docker 下判 `unhealthy` → `up -d --wait` 失败、依赖方卡在 `service_healthy`；K8s 下 Pod 被 kill 重启 → **永久 CrashLoopBackOff，而容器日志一路正常**。

⚠️ **它在切片里的真正理由（§9.6.1）：档 3 要靠它验 Python 外壳。** 没有它，档 3 只能验 Go 外壳，而跨语言外壳的坑要等档 4 才踩到——那时已经有 5 个 Python 组件了。

**职责（§6.11）：** 业务组件只传数据（JSON）+ 模板 ID，返回 PDF 文件流或打印机指令流。**严禁包含任何业务逻辑**（如「订单金额大于 10 万才打印」——那个判断归业务组件）。

**能力：** HTML→PDF 渲染（`WeasyPrint`）、条码/标签指令生成（斑马打印机 ZPL）、模板版本管理（上传/预览/回滚）。

**表：** `templates`（不分区，小表）、`template_versions`（不分区）、`render_records`（月分区）、`event_outbox`/`event_inbox`（周）。

**Dockerfile 特化（Python 组件的通用形态）：**

```dockerfile
FROM python:3.11-slim AS build
WORKDIR /src
# WeasyPrint 的系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential libcairo2 libpango-1.0-0 libpangocairo-1.0-0 \
      libgdk-pixbuf-2.0-0 libffi-dev shared-mime-info \
 && rm -rf /var/lib/apt/lists/*
COPY pyproject.toml poetry.lock ./
RUN pip install --no-cache-dir poetry && poetry config virtualenvs.create false \
 && poetry install --only main --no-root

FROM python:3.11-slim
# ⚠️ 基底必须带 /bin/sh + wget（§12.3.7）。python:slim 有 sh，但默认没有 wget
RUN apt-get update && apt-get install -y --no-install-recommends \
      wget libcairo2 libpango-1.0-0 libpangocairo-1.0-0 libgdk-pixbuf-2.0-0 \
      shared-mime-info fonts-dejavu-core \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=build /usr/local/bin /usr/local/bin
WORKDIR /app
COPY . /app
EXPOSE 8400 9400
ENTRYPOINT ["python", "-m", "app.main"]
```

- [ ] **执行 SOP-B 14 步**（Python 版：`pytest` 代替 `go test`，`grimp` 代替 `go list -deps` 做 import 扫描，Alembic 的 `version_table_schema` 代替 golang-migrate 的 `x-migrations-table`），特化验证：

```bash
# ① 冷启动真的超过 60 秒了吗？超了才证明 startPeriodSeconds:120 是必要的
time docker run --rm --entrypoint python brickenterprise/infra-print:1.0.0 \
  -c 'import weasyprint, time; print("import 耗时可观")'

# ② 平台真的写了 120 秒
docker inspect infra-print-1-0-0 -f '{{json .Config.Healthcheck.StartPeriod}}'
# 期望 120000000000

# ③ 渲染一张送货单 PDF
curl -fsS -X POST http://localhost:8400/infra/print/render \
  -H 'Content-Type: application/json' \
  -d '{"template_id":"delivery-note-a4","data":{"order_no":"SO-001","items":[]}}' \
  -o /tmp/delivery.pdf && file /tmp/delivery.pdf
# 期望：PDF document

# ④ 镜像里有 sh + wget
docker run --rm --entrypoint sh brickenterprise/infra-print:1.0.0 -c 'wget --version | head -1'
```

---

#### Task 31：`infra-bff-mobile` —— GraphQL 复杂展示聚合层

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `infra/bff-mobile` / `infra-bff-mobile` |
| 端口 | HTTP **8500**（GraphQL over HTTP，**不暴露 gRPC**） |
| schema | **无** —— 严禁直连 DB |
| 语言 / 外壳 | **TypeScript (Node.js)** / **独立容器**（跨语言合不进 Go 外壳，§13.5） |
| 装配角色 | `default` |
| **`startPeriodSeconds`** | **`90`** ⚠️（GraphQL schema 构建 + Persisted Queries 预热） |
| `dependencies.components` | **全部 `optional: true`** ⚠️ |

**三条铁律（§6.5）：** 严禁业务逻辑；**严禁直连 DB**；**强制 DataLoader 绑定后端 `batchGet` 防 N+1**（决策 23：Resolver 循环调 `Get` 的瀑布流是唯一要避免的反模式）。

**强制启用 Persisted Queries**（决策 22）：弱网请求体降至数十字节。

**查询限制（§11.4.3）：** `max_depth: 5`、`max_complexity: 100`、`persisted_queries_only: true`。

**BFF 透传用户 JWT**（决策 21）：不许用服务账号，否则审计丢失操作人。

- [ ] **执行 SOP-B 14 步的 TS 变体**，特化验证：

```bash
# ① N+1 检测：查 10 个订单及其客户，断言对 mdm-customer 只发了 1 次 batchGet
#    做法：在 mdm-customer 侧开 access log，跑一次 GraphQL 查询后数请求数
curl -fsS -X POST http://localhost:8500/graphql \
  -H 'Content-Type: application/json' \
  -d '{"id":"persisted-query-hash-001","variables":{"first":10}}'
docker logs mdm-customer-1-0-0 2>&1 | grep -c 'BatchGet'
# 期望 1。出现 10 就是 DataLoader 没绑上，退化成瀑布流了

# ② 非持久化查询被拒
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://localhost:8500/graphql \
  -H 'Content-Type: application/json' -d '{"query":"{ __schema { types { name } } }"}'
# 期望 4xx（persisted_queries_only: true）

# ③ 深度超限被拒
# 构造一个 6 层嵌套的持久化查询，期望 4xx

# ④ 断言依赖全是 optional
grep -A30 'components:' components/infra/bff-mobile/component.yaml | \
  grep -c 'optional: true'
# 期望等于依赖条目总数（决策 98）
```

---

#### Task 32：`frontend-standard` —— 标准前端（SOP-F）

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `frontend/standard` / `frontend-standard` |
| 端口 | **80**（Nginx 静态容器） |
| schema | **无** |
| 语言 / 外壳 | **TypeScript**（PC: Vue3 SPA / 移动端: Uni-app） / **独立容器**（Nginx 合不进任何外壳，§13.5） |
| 装配角色 | `slot:frontend`（Default）。`slot_name: frontend` 写在 `assembly.yaml` |
| `dependencies.components` | **空** —— 前端不依赖任何后端组件，**它只认网关**（§3.5.2） |
| `edge_routes` | `- { path: /**, auth: none }` —— 兜底路由，`be-ops` 产出时排在所有业务路由**之后** |

**档 2 只做切片这几个模块的页面**（§9.6.1），不是全量：

| 后端组件 | 前端模块目录 | 标准页面 |
|---|---|---|
| `mdm-customer` | `modules/mdm-customer/` | 客户列表、客户详情、联系人管理 |
| `mdm-product` | `modules/mdm-product/` | 产品列表、产品详情、分类管理 |
| `erp-sales` | `modules/erp-sales/` | 订单列表、订单详情、创建订单、订单审批 |
| `erp-inventory` | `modules/erp-inventory/` | 库存台账、出入库单、库存盘点 |
| `erp-finance` | `modules/erp-finance/` | 凭证列表、应收应付、对账报表 |
| `crm-opportunity` | `modules/crm-opportunity/` | 商机看板、漏斗分析 |
| `infra-workflow` | `modules/workflow/` | 待办列表、审批历史 |

**七条前端铁律见 SOP-F。** 档 2 里最容易违反的是第 3 条：

```ts
// ❌ 绝对不许：前端复写后端的折扣公式（决策 69，算错价格就是资损）
const total = items.reduce((s, i) => s + i.qty * i.price * (1 - discountRate), 0)

// ✅ 唯一合法写法：防抖调用后端的 DryRun 接口（§8.4）
const total = ref('0.00')
const recalc = useDebounceFn(async () => {
  // 必须用 packages/api-client 里由契约生成的 SDK，
  // 严禁手写 fetch('/api/sales')（§3.9）
  const r = await salesClient.calculateOrderPriceDryRun({
    customerId: form.customerId,
    items: form.items,
  })
  total.value = r.totalAmount   // string，前端不做金额运算
}, 300)
```

**动态特性路由（决策 6）：**

```ts
// 启动时拉一次，按结果注册路由与菜单。未启用的组件自动隐藏 —— 优雅降级，
// 拒绝构建期硬绑定导致「缺组件就白屏」
const { components } = await fetch('/api/tenant/features').then(r => r.json())
for (const m of allModules) {
  if (components.includes(m.componentId)) router.addRoute(m.route)
}
```

- [ ] **执行 SOP-F 全流程**，特化验证：

```bash
# ① 契约生成的 SDK 真的被用了，没有手写 fetch
grep -rn "fetch('/api/" components/frontend/standard/apps/ && \
  echo "✗ 有手写 fetch，必须改用生成的 SDK（§3.9）" || echo "✓ 无手写 fetch"

# ② 动态路由：把 crm-opportunity 从 brickkit.yaml 删掉后重启，
#    前端菜单里不该出现「商机看板」，且不许白屏
curl -fsS http://localhost/api/tenant/features | jq '.components'

# ③ 日期选择器默认最近 90 天（§11.4.4）
grep -rn 'defaultDateRange\|最近 90 天\|last90' components/frontend/standard/packages/ui-kit/

# ④ 镜像是 Nginx 静态容器，port 80
docker inspect frontend-standard-1-0-0 -f '{{json .Config.ExposedPorts}}'
```

---

#### Task 33：`be-ops` 产出 1（路由表）与产出 3（Feature 清单）

**Files:**
- Create: `tools/be-ops/internal/routes/{gen.go,gen_test.go}`
- Create: `tools/be-ops/internal/features/{gen.go,gen_test.go}`

**Interfaces:**
- Produces：`be-ops routes --out <目标>`、`be-ops features --out <目标>`

**产出 1 · 网关路由表的两个出口（§6.3.1）：**

| 组件形态 | 产出到哪 |
|---|---|
| 被合并进外壳（`local: true`） | **我们那份 shell-compose 的 service `labels`** |
| 独立容器 | `brickkit.yaml` 的 `components[].labels`，平台透传进 compose service |
| K8s 全拆（阶段三） | **带外 Traefik Ingress / IngressRoute 清单** |

⚠️ **`local: true` 的组件不生成容器，没有可以挂标签的对象。** 平台会警告并点名那几个键（不是静默失效），但 `be-ops` **不能靠这个警告过日子，必须自己分流**。

**外壳侧的两个坑（§6.3.2，测试必须覆盖）：**

- [ ] **测试 1：router 名全局唯一**

```go
func TestRoutes_router名带组件前缀(t *testing.T) {
	// Traefik 的 router name 跨 provider 全局。外壳三那个 service 上要挂
	// 21 组规则，名字必须带组件前缀去重（erp-sales 而不是 sales）
	out := Gen(components)
	if strings.Contains(out, "traefik.http.routers.sales.") {
		t.Fatal("router 名没带组件前缀，21 组规则会互相顶掉")
	}
}
```

- [ ] **测试 2：必须显式声明 service 端口**

```go
func TestRoutes_成套产出三条标签(t *testing.T) {
	// 外壳容器同时监听 8080~8087 等多个端口，Traefik 猜不出该转发到哪个，
	// 会直接放弃。每个模块要成套产出三条标签
	out := Gen([]Component{{ID: "erp/sales", Port: 8084, Local: true}})
	for _, want := range []string{
		`traefik.http.routers.erp-sales.rule: "PathPrefix(` + "`" + `/erp/sales` + "`" + `)"`,
		`traefik.http.routers.erp-sales.service: "erp-sales"`,
		`traefik.http.services.erp-sales.loadbalancer.server.port: "8084"`,
	} {
		if !strings.Contains(out, want) {
			t.Errorf("缺少 %q", want)
		}
	}
}

func TestRoutes_值必须带引号(t *testing.T) {
	// Docker labels 与 K8s annotations 两边都只收字符串，平台不做自动转换。
	// traefik.enable: true 会被当场拦下（生成器铁律一）
	out := Gen(components)
	if regexp.MustCompile(`:\s*(true|false|\d+)\s*$`).MatchString(out) {
		t.Fatal("有 label 值没带引号")
	}
}

func TestRoutes_前端兜底路由排最后(t *testing.T) {
	// frontend 的 /** 是兜底，必须排在所有业务路由之后，否则它吃掉一切
}
```

**产出 3 · Feature 清单：**

- [ ] **测试 3：清单是逗号分隔字符串且被校验**

```go
func TestFeatures_逗号分隔字符串(t *testing.T) {
	out := GenFeatures([]string{"mdm/customer", "erp/sales"})
	if out != "mdm/customer,erp/sales" {
		t.Fatalf("必须是逗号分隔字符串。数组会被平台渲染成 [a b c]（§6.1），得到 %q", out)
	}
}

func TestFeatures_自己校验内容(t *testing.T) {
	// 平台对 config 的**值**不校验——喂错内容不会有任何运行时失败，
	// 只会让前端少显示几个菜单。所以 be-ops 自己要校验（§6.1）
	_, err := GenFeaturesChecked([]string{"不存在的/组件"})
	if err == nil {
		t.Fatal("清单里有未装配的组件时必须报错")
	}
}
```

**验证：** `cd tools/be-ops && go test ./internal/routes ./internal/features -v` 全绿；跑一次 `be-ops routes` 产出的 labels 喂给 Traefik，`curl http://localhost/erp/sales/orders` 能打到 `erp-sales`。

---

#### Task 34：附录 E 全链路闭环

**Files:**
- Create: `tools/be-acceptance/closedloop/tier2_test.go`
- Modify: `Makefile`

**Interfaces:**
- Produces：`make closedloop` —— 档 2 的业务闭环用例，**档 3 的拆回门禁要重跑它**（§13.7）。

**要跑通的链路（附录 E + §9.6.1 档 2 的出档条件）：**

```
销售在前端标记商机赢单
  → crm-opportunity 更新状态、写 Outbox、发 opportunity.won.v1
  → erp-sales 消费事件
      → 同步 gRPC batchGet 拿最新客户/产品数据（mdm-customer / mdm-product）
      → 同步 gRPC 预留库存（erp-inventory.Reserve）
      → 同步 gRPC 校验信用额度（erp-finance.CheckCredit）
      → 创建销售订单、写 Outbox、发 sales.order.created.v1
  → erp-inventory 消费事件 → 锁定库存 → 发 erp.inventory.reserved.v1
  → erp-finance   消费事件 → 生成应收账款凭证 → 发 finance.voucher.created.v1
  → infra-workflow 收到审批任务 → 审批通过 → 发 workflow.task.completed.v1
  → infra-notification 消费 → 路由给 integration-im-dingtalk → 钉钉卡片
  → infra-print 渲染送货单 PDF
```

- [ ] **步骤 1：写闭环测试**

```go
func Test档2_闭环_赢单到打印(t *testing.T) {
	// 1. 建客户与产品（mdm）
	// 2. 建商机并标记赢单（crm-opportunity）
	// 3. 轮询等待 erp-sales 里出现对应订单（事件是异步的，给 30s 超时）
	// 4. 断言 erp-inventory 的 available 减少了、reserved 增加了
	// 5. 断言 erp-finance 里生成了应收凭证，且借贷平
	// 6. 断言 infra-workflow 里有一条 type=approval 的待办
	// 7. 审批通过，断言 workflow.task.completed.v1 被发出
	// 8. 断言 mock 钉钉 server 收到了一次卡片推送
	// 9. 调 infra-print 渲染送货单，断言返回的是合法 PDF
}
```

- [ ] **步骤 2：跑 Saga 补偿与超时查询各一遍**

```go
func Test档2_Saga_信用不足时库存预留被回滚(t *testing.T) {
	// 把客户信用额度设成 0，触发 erp-finance 拒绝
	// 断言：erp-inventory 的 reserved 回到了原值（CancelReservation 被调用）
	// 断言：erp-sales 发出了 sales.order.cancelled.v1
}

func Test档2_超时_下游其实成功时不许误杀(t *testing.T) {
	// 用 toxiproxy 或 iptables 让 erp-inventory 的响应延迟超过 erp-sales 的超时
	// 断言：erp-sales 调了 GetStatus，且**没有**调 CancelReservation
	// 断言：订单最终创建成功（§4.5）
}
```

- [ ] **步骤 3：DLQ 进得去出得来**

⚠️ **`infra-dlq-monitor` 在档 4a，不在档 2 的 13 个里。** 所以档 2 验的是**平台 SDK 层的死信通道本身**，不是那个管理界面：

```go
func Test档2_DLQ_进得去(t *testing.T) {
	// 发一条消费者必然失败的事件（payload 故意不合法）
	// 断言：重试耗尽后，消息出现在 NATS JetStream 的 DLQ 主题里
	// 断言：hop_count > 5 的事件被直接丢弃进 DLQ 而不是无限循环（决策 42）
}

func Test档2_DLQ_出得来(t *testing.T) {
	// 用 nats CLI 直接把 DLQ 里那条消息重新投递
	// 断言：消费者这次成功处理（修好 payload 之后）
	// 管理界面留到档 4a 的 infra-dlq-monitor
}
```

- [ ] **步骤 4：接上 Makefile 并 commit**

```makefile
closedloop:  ## 档 2 业务闭环 + Saga + 超时 + DLQ
	@cd tools/be-acceptance && go test ./closedloop/ -run 'Test档2' -v -count=1 -timeout 10m
.PHONY: closedloop
```

**🏁 档 2 出档检查（六条全绿才进档 3）：**

```bash
make check                 # ① 基础资源
make registry-check        # ② 册子自洽
make gates                 # ③ import 扫描（13 个组件都扫）
make tier0                 # ④ 13 个组件各自的档 0 六项
make platform-acceptance   # ⑤ 20 条平台验收
make closedloop            # ⑥ 附录 E 全链路 + Saga + 超时 + DLQ
```


---

## 第 8 部分 · 档 3：做外壳、验拆回

> **档 3 必须排在档 4 之前**（决策 95）。外壳的坑（环境变量表、跨外壳顺序、端口册、import 边界）是**结构性**的：13 个组件时踩到只要改 `be-ops`；61 个组件时踩到，要改 61 份 `component.yaml` 的端口，还要拆开一堆已经互相 import 了的代码。

**档 3 的合并范围（§9.6.1）：**

| 外壳 | 装什么 | 为什么 |
|---|---|---|
| **Go 外壳**（1 个进程，10 个模块） | `mdm-customer`、`mdm-product`、`erp-sales`、`erp-inventory`、`erp-finance`、`crm-opportunity`、`infra-iam-casdoor`、`infra-workflow`、`infra-notification`、`integration-im-dingtalk` | 同语言同框架才合得进来（§13.5） |
| **Python 外壳**（1 个进程，1 个模块） | `infra-print` | 验跨语言外壳；Python 进程的启动预算与 Go 完全不同 |
| **保持独立容器** | `infra-bff-mobile`（Node）、`frontend-standard`（Nginx） | **跨语言合不进来，Nginx 也合不进来**（§13.5） |

⚠️ **档 3 的 Go 外壳是一个「验证用的临时形态」**，不是 §13.2 那五个外壳的最终形态。档 4 铺货时它会按 §13.2 拆成外壳一/二/三。**这里刻意先合成一个**：13 个组件时把「跨外壳环境变量」这个坑一次踩完，比分三个外壳分三次踩便宜。

**出档条件（四条）：**

1. 合并态业务闭环全绿（`make closedloop` 在合并态下跑一遍）
2. **§13.7 的拆回门禁全绿**
3. 铁律六的 import 扫描全绿
4. §13.8 那三份 compose 一条命令启停

#### Task 35：两个外壳仓库骨架 → **检查点 CP-5**

- [ ] **步骤 1：建目录**

```bash
mkdir -p shells/go/{cmd/shell,internal/{loader,envmap,migrate}}
mkdir -p shells/python/{app,tests}
```

- [ ] **步骤 2：⏸ 检查点 CP-5**

```
目录已建好：
  shells/go/
  shells/python/

请在 github.com/brickKit/ 下创建这 2 个空仓库（不要 README / .gitignore / license）：
  be-shell-go
  be-shell-python
```

**本任务在此中止，等人回「建好了」。**

---

#### Task 36：`be-shell-go` —— Go 外壳启动器

**Files:**
- `shells/go/cmd/shell/main.go`
- `shells/go/internal/loader/loader.go`
- `shells/go/internal/envmap/envmap.go`
- `shells/go/internal/migrate/runner.go`
- `shells/go/go.work`
- `shells/go/Dockerfile`

**Interfaces:**
- Consumes：`be-ops shell-config`（Task 38）产出的合并清单；`be-ops shell-env`（Task 39）产出的每模块环境变量表。
- Produces：一个进程内启动 N 个 `http.Server` + N 个 `grpc.Server`，端口从**各模块自己的 `component.yaml`** 读。

**外壳只许做一件事：把 N 个进程变成 1 个进程。四条不许（§1.5 原则二）：**

```go
// shells/go/cmd/shell/main.go
//
// ⚠️ 外壳能做的事只有一件：把 N 个进程变成 1 个进程。
// 不许做的事：
//   ❌ 不许让两个组件模块直接互相 import（13.3 铁律六）
//   ❌ 不许把两个组件的表放进同一个 schema、不许跨 schema JOIN（铁律二）
//   ❌ 不许把 N 个模块的 API 合并成一个端口（铁律三）
//   ❌ 不许在外壳里写任何业务逻辑
//
// ✅ 外壳 main 可以 import 每个组件的 NewServer()——这是唯一允许的方向。
```

- [ ] **步骤 1：写 `loader` —— 端口从 Manifest 读，不许另写一份**

```go
package loader

// Module 是外壳里的一个组件模块。
// ⚠️ 端口必须从各模块自己的 component.yaml 读（§13.8.1）。
// brickKit 明确不注入「我该监听哪个端口」——环境变量表里只有「别人在哪」。
// 外壳里另写一份端口表必然过期，Manifest 才是权威。
type Module struct {
	ID          string            // mdm/customer
	Version     string            // 1.0.0
	HTTPPort    int               // 从 deployment.port 读
	ExtraPorts  map[string]int    // 从 extraPorts 读，如 {"grpc": 9090}
	Schema      string            // 从 assembly.yaml 的 data.schema 读
	Role        string            // 从 assembly.yaml 的 data.role 读
	Env         map[string]string // be-ops shell-env 产出的**本模块那一份**
	NewServer   func(ModuleCtx) (Server, error)
}

// LoadFromManifests 读 components/<scope>/<name>/component.yaml 与 assembly.yaml。
// 合并清单里列了哪些模块，就读哪些。
func LoadFromManifests(root string, ids []string) ([]Module, error)
```

- [ ] **步骤 2：写 `envmap` —— 每模块一份 env，绝不拍平**

```go
package envmap

// ⚠️ 这些变量不能拍平成一份 .env 给整个外壳进程（§13.8.2）。
// 21 个模块各有一份 DATABASE_*、各有一个 COMPONENT_ID，拍平就互相顶掉。
// 外壳启动器必须**按模块持有各自的 env map**，模块代码读的是它自己那一份——
// 这是「合并不改代码」能成立的最后一环。
type ModuleEnv struct {
	m map[string]string
}

// Getenv 让模块代码读到的是它自己那一份，而不是进程的 os.Environ()。
// 组件侧通过 besdk 的注入点拿到它，业务代码一行不改。
func (e *ModuleEnv) Getenv(k string) string { return e.m[k] }

func (e *ModuleEnv) LookupEnv(k string) (string, bool) {
	v, ok := e.m[k]
	return v, ok
}
```

- [ ] **步骤 3：写 `migrate/runner.go` —— 迁移由外壳按拓扑顺序自己跑**

```go
package migrate

// ⚠️ local: true 的组件，平台不生成迁移容器 / Job（§13.3 铁律五）。
// 外壳一（8 个）、外壳二（14 个）、外壳三（21 个）的迁移全部由外壳启动器
// 按拓扑顺序执行，失败即中止启动。
//
// ⚠️ 各自的 schema_migrations 表必须落在各自的 schema 里，
// 迁移工具默认往 public 写，不配就会全挤在一起互相顶掉（§11.2.3）。
//
// ⚠️ 迁移脚本必须幂等：拆分回独立容器时平台重新接管迁移，
// 两种执行路径下都要能安全重跑。
func RunAll(ctx context.Context, db *sql.DB, mods []loader.Module) error {
	order, err := topoSort(mods) // 依赖先跑
	if err != nil {
		return err
	}
	for _, m := range order {
		if err := runOne(ctx, db, m); err != nil {
			return fmt.Errorf("模块 %s 迁移失败，中止启动：%w", m.ID, err)
		}
	}
	return nil
}
```

- [ ] **步骤 4：写 `main.go` —— 一个连接池、N 个 Server**

```go
func main() {
	cfg := mustLoadShellConfig() // be-ops shell-config 的产出
	mods, err := loader.LoadFromManifests(cfg.Root, cfg.ModuleIDs)
	// …

	// ⚠️ 外壳启动器在进程内只创建**一个**全局连接池（§13.3 铁律二）。
	// 严禁组件模块私自 sql.Open()。
	// PG 的连接绑死「一个 database + 一个认证角色」，所以想合池就必须同库同账号：
	// 每个外壳一个共享登录角色，借出连接时 SET LOCAL ROLE 切到组件角色。
	//
	// 要付的账：池是共享的，**没有舱壁**。一个模块连接泄漏或跑了个长事务，
	// 整组一起等。这是在合并那一刻就已经付掉的故障隔离。
	db := mustOpenPool(cfg.ShellLoginRole, cfg.DSN)
	defer db.Close()

	// 迁移先跑完再启动（铁律五）
	if err := migrate.RunAll(ctx, db, mods); err != nil {
		log.Fatal(err)
	}

	// 统一的事件推送线程池，轮询各模块的 Outbox 表（铁律四）
	pump := outbox.NewPump(db, nc)
	for _, m := range mods {
		pump.Watch(m.Schema)
	}
	go pump.Run(ctx)

	// 每个模块起自己的 HTTP + gRPC Server，各监听各的端口（铁律三）
	for _, m := range mods {
		m := m
		srv, err := m.NewServer(loader.ModuleCtx{
			DB:   db,
			Env:  m.Env,          // ← 本模块那一份，不是进程的 os.Environ()
			Role: m.Role,
			Schema: m.Schema,
		})
		if err != nil {
			log.Fatalf("模块 %s 初始化失败：%v", m.ID, err)
		}
		go srv.ServeHTTP(m.HTTPPort)
		if p, ok := m.ExtraPorts["grpc"]; ok {
			go srv.ServeGRPC(p)
		}
	}

	// 外壳自己的健康检查端口。
	// ⚠️ 它只查外壳进程存活，**仍然禁止**检查各模块的依赖（§13.6）。
	// 任何一个模块把探针拖挂，整组一起重启——故障隔离是第一样付掉的东西。
	go serveShellHealthz(cfg.ShellHealthPort)
	<-ctx.Done()
}
```

- [ ] **步骤 5：写 `go.work` 与 `Dockerfile`**

```
// shells/go/go.work
go 1.22

use (
	.
	../../components/mdm/customer
	../../components/mdm/product
	../../components/erp/sales
	../../components/erp/inventory
	../../components/erp/finance
	../../components/crm/opportunity
	../../components/infra/iam-casdoor
	../../components/infra/workflow
	../../components/infra/notification
	../../components/integration/im-dingtalk
)
```

⚠️ **`go.work` 把 10 个模块引进同一个包空间的那一刻，「组件之间不共享代码」从物理隔离退化成纪律——而纪律会烂**（决策 91）。所以 `make gates` 的 import 扫描从这一刻起**必须每次 CI 都跑**，不能只在提交时跑。

- [ ] **步骤 6：`startPeriodSeconds` 写 300**

外壳镜像在我们自己那份 shell-compose 里（不经平台），健康检查参数自己写：

```yaml
healthcheck:
  test: ["CMD-SHELL", "wget -q --spider http://localhost:8079/healthz || exit 1"]
  interval: 10s
  timeout: 5s
  retries: 3
  start_period: 300s   # ⚠️ 10 个模块的迁移串行跑，60 秒远远不够（§12.3.5）
```

**验证：** 外壳容器起来后，10 个模块的 HTTP 端口（8080–8087、8102、8200–8202、8207）与 gRPC 端口都能连上；`docker exec <shell> env | grep -c DATABASE_HOST` 输出 1（进程级只有一份，各模块的那份在内存里）。

---

#### Task 37：`be-shell-python` —— Python 外壳启动器

同 Task 36 的结构，差异：

| 项 | Go 外壳 | Python 外壳 |
|---|---|---|
| 模块引入 | `go.work` | 各模块装成本地 package，`app/loader.py` 动态 import 各自的 `create_app()` |
| 并发模型 | 每模块 goroutine 起 Server | `asyncio` + `uvicorn` 多 Server 实例，或每模块一个子进程 |
| import 扫描 | `go list -deps` | **`grimp`**（§13.3） |
| 迁移工具 | golang-migrate（`x-migrations-table`） | **Alembic（`version_table_schema`）** |
| `start_period` | 300s | **300s**（同样是迁移串行 + Python import 慢） |

档 3 的 Python 外壳只装 `infra-print` 一个模块。**这不是浪费**——它验的是「跨语言外壳能不能与 Go 外壳共存、跨外壳的环境变量对不对」，那两件事跟装几个模块无关。

---

#### Task 38：`be-ops` 产出 4 —— 外壳合并配置

**Files:** `tools/be-ops/internal/shellcfg/{gen.go,gen_test.go}`

产出内容：哪些组件进哪个外壳、端口分配、**迁移执行顺序**。

- [ ] **测试：迁移顺序必须是拓扑序**

```go
func TestShellConfig_迁移顺序是拓扑序(t *testing.T) {
	// erp/sales 强依赖 mdm/customer、mdm/product、erp/inventory、erp/finance，
	// 所以它的迁移必须排在那四个之后
	cfg := Gen(components)
	idx := indexOf(cfg.GoShell.MigrationOrder)
	for _, dep := range []string{"mdm/customer", "mdm/product", "erp/inventory", "erp/finance"} {
		if idx["erp/sales"] < idx[dep] {
			t.Fatalf("erp/sales 的迁移排在了 %s 前面", dep)
		}
	}
}

func TestShellConfig_端口来自Manifest不是另算的(t *testing.T) {
	// 断言产出里每个模块的端口与它 component.yaml 里写的一致（§13.8.1）
}

func TestShellConfig_跨语言不许合进同一外壳(t *testing.T) {
	// infra-print 是 Python，绝不能出现在 Go 外壳的清单里（§13.5）
}

func TestShellConfig_Nginx与Node不进外壳(t *testing.T) {
	// frontend-standard 与 infra-bff-mobile 必须标记为独立容器
}
```

---

#### Task 39：`be-ops` 产出 7 —— 每外壳一份环境变量表（**最容易被漏掉的一件**）

**Files:** `tools/be-ops/internal/shellenv/{gen.go,gen_test.go}`

⚠️ **这是设计书 §13.8 点名「真正会在交付现场炸的那个洞」。**

平台的注入只发生在**它自己生成的容器**上。`local: true` 的组件没有容器，它拿到的是一份 `local-debug.<版本化服务名>.env` 文件。**那份文件不能直接喂给外壳**，因为里面的依赖地址被改写成了 `http://localhost:<端口>`：

| 调用关系 | `local-debug` 里写的 | 在外壳容器里对不对 |
|---|---|---|
| 同外壳：`erp-sales` → `mdm-customer` | `http://localhost:8080` | ✅ 对，同一进程同一 localhost |
| **跨外壳**：Python 外壳的 `infra-print` → Go 外壳的 `mdm-customer` | `http://localhost:8080` | ❌ **错。打到 Python 外壳自己的 8080 上去了** |

那份文件的语义是「这个组件跑在开发者的 IDE 里，其他东西在容器里」——**它假设只有一个 local 进程。我们有两个（档 3）到五个（档 4）。**

**规则表（§13.8.2）：**

| 变量 | 值怎么定 |
|---|---|
| 依赖在**同一个外壳** | `http://127.0.0.1:<对方的端口>` |
| 依赖在**另一个外壳**或独立容器 | `http://<宿主机地址>:<对方的端口>`（外壳把端口发布到宿主机，§13.1） |
| 资源变量（`DATABASE_*` / `MQ_*` / `STORAGE_*`） | 照 `brickkit.yaml` 的 `resources` 原样，**本外壳的登录角色** |
| 组件自身 config | 照各自 `configSchema` 的默认值 + `brickkit.yaml` 的覆盖 |
| `COMPONENT_ID` / `COMPONENT_VERSION` | **每个模块一份**，外壳启动器按模块设进各自的上下文 |

⚠️ **`be-ops` 应当把平台的注入结果当输入，而不是自己另算一遍。** `brickkit up --dry-run` 会把每个 local 组件的完整变量表写进 `local-debug.*.env`；`be-ops` **读它、只重写依赖地址那几行**，其余原样。自己另算的那份，早晚和平台的算法分叉。

- [ ] **测试（四条，一条都不能少）**

```go
func TestShellEnv_同外壳依赖指127001(t *testing.T) {
	env := Gen(cfg)["go-shell"]["erp/sales"]
	if env["MDM_CUSTOMER_ENDPOINT"] != "http://127.0.0.1:8080" {
		t.Fatalf("同外壳依赖应指 127.0.0.1，得到 %q", env["MDM_CUSTOMER_ENDPOINT"])
	}
}

func TestShellEnv_跨外壳依赖指宿主机(t *testing.T) {
	// 这一条是那个「真正会炸的洞」。Python 外壳的 infra-print 要调
	// Go 外壳的 mdm-customer，指 localhost 会打到自己身上
	env := Gen(cfg)["py-shell"]["infra/print"]
	got := env["MDM_CUSTOMER_ENDPOINT"]
	if strings.Contains(got, "127.0.0.1") || strings.Contains(got, "localhost") {
		t.Fatalf("跨外壳依赖不许指 localhost，会打到自己身上（§13.8.1）：%q", got)
	}
	if !strings.HasPrefix(got, "http://"+cfg.HostGateway+":") {
		t.Fatalf("跨外壳依赖应指宿主机，得到 %q", got)
	}
}

func TestShellEnv_每模块一份不许拍平(t *testing.T) {
	// 10 个模块各有一份 DATABASE_*、各有一个 COMPONENT_ID，拍平就互相顶掉
	all := Gen(cfg)["go-shell"]
	if len(all) != 10 {
		t.Fatalf("Go 外壳应有 10 份独立 env map，得到 %d", len(all))
	}
	if all["mdm/customer"]["COMPONENT_ID"] == all["erp/sales"]["COMPONENT_ID"] {
		t.Fatal("COMPONENT_ID 被拍平了")
	}
}

func TestShellEnv_读平台产出而不是自己另算(t *testing.T) {
	// 断言实现真的读了 local-debug.*.env，且只重写了依赖地址那几行，
	// 其余（config 项、资源变量）与平台产出逐字一致
}
```

---

#### Task 40：`be-ops` 产出 8 + 三份 compose 一条命令启停

**Files:**
- `tools/be-ops/internal/shelldepends/{gen.go,gen_test.go}`
- `shell-compose.yml`（由 `be-ops` 产出，进版本控制）
- Modify: `Makefile`

**三份互不相干的 compose（§13.8.3），`brickkit up` 只管中间那一份：**

| # | 文件 | 谁生成 | 里面有什么 | 谁拉起 |
|---|---|---|---|---|
| 1 | `infra/docker-compose.infra.yml` | 我们手写（Task 1） | PostgreSQL / NATS / Traefik / Casdoor / RustFS | `docker compose` |
| 2 | `.brickkit/` 下的 compose | **`brickkit up`** | 档 3 只有 **2 个 service**（`infra-bff-mobile`、`frontend-standard`）——其余 11 个都是 `local: true`，不生成 service | `brickkit up` |
| 3 | `shell-compose.yml` | **`be-ops`** | 2 个外壳容器 + 路由 labels + 环境变量表 + 端口发布 | `docker compose` |

**启动顺序（产出 8）：**

```
① infra/docker-compose.infra.yml   基础资源健康后再往下
② be-ops 的建置脚本（make db-init）CREATE DATABASE / SCHEMA / ROLE，执行一次
③ shell-compose.yml                Go 外壳（主数据 + 核心交易在里面）
                                     ↓ depends_on: service_healthy
                                   Python 外壳
④ brickkit up                      bff-mobile + frontend
```

**Go 外壳必须最先起**：主数据在里面，其余外壳的模块启动时要对它做校准对账（`batchGet`）。**这层顺序平台一个字都不会排**——它不认识外壳。

⚠️ **三份 compose 必须挂同一个 external network `be-net`。** Traefik 的 Docker Provider 只能看到与它同网络的容器；外壳在第 3 份文件里、Traefik 在第 1 份里，不显式声明共享网络的话，`be-ops` 产出的路由 labels **Traefik 一条都读不到**——症状是**网关返回 404 而容器全是 healthy**。

- [ ] **步骤 1：`make up-all` / `make down-all`**

⚠️ **`brickkit down` 停不了外壳。** 它只管第 2 份。交付文档里必须给出成套的启停脚本，否则现场一定会出现「以为关干净了，其实外壳还在跑着占着端口」（§13.8.3）。

```makefile
##@ 合并态（档 3 起可用）
up-all: net  ## 三份 compose 一条命令启停：基础资源 → 建库 → 外壳 → 平台产物
	@bash $(S)/up.sh
	@$(MAKE) db-init
	@docker compose -p be-shells -f shell-compose.yml up -d --wait --wait-timeout 600
	@brickkit up
	@echo "✓ 全栈已启动（基础资源 + 外壳 + 平台产物）"

down-all:  ## 反序停止全部三份，一个都不许落下
	@brickkit down || true
	@docker compose -p be-shells -f shell-compose.yml down || true
	@$(MAKE) down
	@echo "✓ 全栈已停止（volume 保留）"
.PHONY: up-all down-all
```

- [ ] **步骤 2：验证网络共享（这一条不验就会在交付现场遇到 404）**

```bash
make up-all
# 三份 compose 的容器必须都在 be-net 上
docker network inspect be-net -f '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | sort
# 期望能同时看到：be-traefik、be-postgres、be-shell-go、be-shell-python、
#                 infra-bff-mobile-1-0-0、frontend-standard-1-0-0

# 路由真的通了
curl -fsS http://localhost/erp/sales/orders | head -c 200
curl -fsS http://localhost/ | head -c 200
```
期望：两条都 200。**若容器全 healthy 而网关 404**，第一个要查的就是 `be-net` 有没有真的共享。

- [ ] **步骤 3：验证 `local: true` 的三件事（§9.6.2 用例 11/12/13）**

```bash
# ① 不生成 service
docker compose -p brickkit ps --services 2>/dev/null | sort
# 期望只有 infra-bff-mobile 与 frontend-standard 两个

# ② 依赖方容器里有 extra_hosts
docker inspect infra-bff-mobile-1-0-0 -f '{{json .HostConfig.ExtraHosts}}'
# 期望能看到 mdm-customer-1-0-0:host-gateway 之类

# ③ 注入端口换成了 localPort
docker exec infra-bff-mobile-1-0-0 env | grep MDM_CUSTOMER_ENDPOINT

# ④ 额外端口**不被改写**（用例 12）
docker exec infra-bff-mobile-1-0-0 env | grep MDM_CUSTOMER_GRPC_ENDPOINT
# 期望端口仍是 Manifest 里声明的 9090，没有被换成 localPort

# ⑤ local: true 不生成迁移容器（用例 13）
docker ps -a --filter 'name=migrate' --format '{{.Names}}'
# 期望：11 个 local 组件一个迁移容器都没有；迁移由外壳自己跑
```

---

#### Task 41：拆回门禁（§13.7）—— 档 3 出档的核心

**Files:**
- `tools/be-acceptance/gates/{splitback.go,splitback_test.go}`
- Modify: `Makefile`

> **检验动作只有一个**：把全部 `local: true` / `localPort` 去掉，`brickkit up` 一次，本次装配的每个组件各起一个容器、全部 healthy，`be-acceptance` 的业务闭环用例全绿。

**为什么必须是「全拆」而不是「抽查」**：磨掉组件性的那些改动，在合并态下**全都是正确的**——同进程直调当然通、跨 schema JOIN 当然查得出来。**只有全拆才会让它们变成错误。**

**纪律表（§13.7，逐条写进 CI）：**

| 项 | 规定 |
|---|---|
| **频率** | 每次合并组关系变动时必跑；平时**每周一次**，进 `be-acceptance` 的定时任务 |
| **跑在哪** | 开发机 / CI 上跑全拆态（要 60 容器的内存）。**客户现场只跑合并态** |
| **失败意味着什么** | 不是「全拆有 bug」，是**合并那一刻磨掉了组件性**。八成命中铁律六（有人 import 了别人）或铁律二（有人跨 schema 查了） |
| **不许怎么处理** | **不许「先把全拆态用例注掉，回头再修」。那等于宣布阶段三不做了。** |

- [ ] **步骤 1：写门禁**

```makefile
split-back-gate:  ## 拆回门禁：全拆一次，业务闭环必须照样全绿（§13.7）
	@echo "▸ 生成全拆态配置（去掉全部 local: true / localPort）"
	@tools/be-ops/build/be-ops gen --root . --no-local --out /tmp/brickkit.split.yaml
	@echo "▸ 停掉合并态"
	@$(MAKE) down-all
	@echo "▸ 全拆启动（13 个组件各一个容器）"
	@bash $(S)/up.sh
	@$(MAKE) db-init
	@brickkit up --config /tmp/brickkit.split.yaml
	@echo "▸ 业务闭环在全拆态下重跑"
	@cd tools/be-acceptance && go test ./closedloop/ -run 'Test档2' -v -count=1 -timeout 15m
	@echo "▸ import 扫描"
	@$(MAKE) gates
	@echo "✓ 拆回门禁全绿——合并没有磨掉组件性"
.PHONY: split-back-gate
```

- [ ] **步骤 2：跑一次，看它真的能拆回来**

```bash
make split-back-gate
docker ps --format '{{.Names}}' | grep -c -- '-1-0-0'
```
期望：13 个组件容器（11 个原本 local 的 + bff-mobile + frontend）全部 healthy；闭环用例全绿。

**如果红了**，按这个顺序查：

1. `make gates` 是不是也红 → 有人 import 了别人（铁律六）
2. 某个模块起不来报 `permission denied` → 有人跨 schema 查了（铁律二）
3. 某个模块的 `*_ENDPOINT` 指向 127.0.0.1 → 代码里硬编码了地址（铁律一）
4. 迁移没跑 → 合并态下靠外壳跑，全拆后归平台，脚本不幂等（铁律五）

- [ ] **步骤 3：把它排进每周定时任务**

```bash
# tools/be-acceptance/.github/workflows/weekly-split-back.yml
# 或本地 cron。设计书 §13.7 要求「平时每周一次」
```

**🏁 档 3 出档检查（五条全绿才进档 4）：**

```bash
make up-all && make closedloop   # ① 合并态业务闭环全绿
make split-back-gate             # ② 拆回门禁全绿（含 ③ import 扫描）
make down-all && make up-all     # ④ 三份 compose 一条命令启停
make platform-acceptance         # ⑤ 20 条平台验收（含用例 11/12/13/14）
```


---

## 第 9 部分 · 档 4a：补齐 `default` 组件（5 个）

> **这 5 个不等客户点名。** `default` 的定义是「系统运行的基石，默认必选」（§3.3）——任何一次真实交付都必须有它们。设计书 §5.13 的「切片」列没勾它们，是因为切片只为验平台，**不是因为它们可选**。

| 仓库 | 角色 | 为什么不能等点名 | 顺序 |
|---|---|---|---|
| `infra-storage` | default | 对象存储门面，`infra-attachment` 的底座 | **1（必须最先）** |
| `infra-attachment` | default | 附件上传下载，ERP 单据必用 | 2（依赖 storage） |
| `infra-dlq-monitor` | default | 死信急诊室。决策 40：DLQ 必须配套告警与人工介入，否则变成「坟墓」 | 3 |
| `mdm-supplier` | default | `erp-purchase` 的强依赖 | 4 |
| `mdm-org` | default | `infra-workflow` 审批人路由的组织数据来源 | 5 |

#### Task 42：五个骨架 → **检查点 CP-6**

```bash
for p in infra/storage infra/attachment infra/dlq-monitor mdm/supplier mdm/org; do
  mkdir -p "components/$p"/{contracts/events,migrations,backend}
done
```

- [ ] **⏸ 检查点 CP-6**

```
目录已建好：
  components/infra/storage/     components/infra/attachment/
  components/infra/dlq-monitor/ components/mdm/supplier/
  components/mdm/org/

请在 github.com/brickKit/ 下创建这 5 个空仓库（不要 README / .gitignore / license）：
  infra-storage
  infra-attachment
  infra-dlq-monitor
  mdm-supplier
  mdm-org
```

**本任务在此中止，等人回「建好了」。**

---

#### Task 43：`infra-storage` —— 对象存储底座

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `infra/storage` / `infra-storage` |
| 端口 | HTTP **8205** / gRPC **9205** |
| schema / role | `infra_storage` / `infra_storage_rw` |
| 语言 / 外壳 | Go / 外壳三 `go-infra` |
| 装配角色 | `default` |
| `dependencies.components` | **空** |
| `dependencies.resources` | `database:postgresql`、**`storage:minio`**（RustFS 走 S3 兼容，`engine` 写 `minio`，见附录 G 第 5 行） |

**定位（§6.8、决策 73）：** 纯底座，对接物理存储（RustFS / MinIO / S3 / OSS）。**底层存储服务通过部署配置替换，本组件代码不感知具体实现（S3 SDK 兼容）。**

⚠️ **它为什么仍然是组件，而事件总线不是**（§5.11 判据）：**这一层有我们自己的代码**——S3 SDK 门面、预签名 URL 生成、分片上传编排。事件总线那一层我们一行代码都不写，所以它是基础资源。

**表：** `objects`（月分区，对象元数据）、`upload_sessions`（月，分片上传会话）、`event_outbox`（周）。

**gRPC：** `Put` / `Get` / `Delete` / `PresignPut` / `PresignGet` / `InitMultipart` / `CompleteMultipart` / `BatchGet` / `GetStatus`

- [ ] **执行 SOP-B 14 步**，特化验证：

```bash
# ① 换底层存储代码零改动：把 brickkit.yaml 的 resources engine 从 rustfs 改成 minio
make minio-up   # 互斥校验会先要求 make down 掉 rustfs
# 改 brickkit.yaml 的 storage engine 后重启，断言 infra-storage 代码一行没改也能用
curl -fsS -X POST http://localhost:8205/infra/storage/objects -F file=@/tmp/test.pdf

# ② STORAGE_* 是平台注入的保留前缀，代码里不许有硬编码 endpoint
grep -rn 'localhost:9000\|rustfs\|minio' components/infra/storage/backend/ \
  && echo "✗ 硬编码了存储地址（铁律一）" || echo "✓ 只读环境变量"
```

---

#### Task 44：`infra-attachment` —— 附件管理

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `infra/attachment` / `infra-attachment` |
| 端口 | HTTP **8204** / gRPC **9204** |
| schema / role | `infra_attachment` / `infra_attachment_rw` |
| 语言 / 外壳 | Go / 外壳三 `go-infra` |
| 装配角色 | `default` |
| **强依赖** | `infra/storage@1.0.0` |

**职责（§6.8）：** 文件上传/下载/URL 生成/元数据管理，支持常见格式轻量预览。**它是业务组件，`infra-storage` 才是底座。**

**表：** `attachments`（月分区，含 `ref_type`/`ref_id` 关联业务单据）、`previews`（月）、`event_outbox`（周）、`command_idempotency`。

**gRPC：** `Upload` / `Download` / `GetUrl` / `Delete` / `List` / `BatchGet` / `GetStatus`

- [ ] **执行 SOP-B 14 步。**

---

#### Task 45：`infra-dlq-monitor` —— 死信队列监控与人工干预中心

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `infra/dlq-monitor` / `infra-dlq-monitor` |
| 端口 | HTTP **8203** / gRPC **9203** |
| schema / role | `infra_dlq_monitor` / `infra_dlq_monitor_rw` |
| 语言 / 外壳 | Go / 外壳三 `go-infra` |
| 装配角色 | `default` |
| **弱依赖** | `{ id: infra/notification@1.0.0, optional: true }`（告警走它） |

**定位（§6.10）：** 死信队列的「急诊室」。监控积压、分级告警、提供界面供管理员**手动重新投递或丢弃**死信。**严禁业务用户直接操作**。

⚠️ **它补的是档 2 欠的那一半。** 档 2 验的是「死信通道本身进得去出得来」（对 NATS JetStream 直接断言），本组件补的是**管理界面与告警**——决策 40：DLQ 必须配套告警与人工介入机制，否则「死信队列变成坟墓」。

**表：** `dlq_messages`（月分区）、`redelivery_records`（月）、`alert_rules`（不分区）、`event_outbox`（周）。

**gRPC：** `List` / `Get` / `BatchGet` / `Redeliver` / `Discard` / `GetBacklogStats`

**背压保护（§3.10）：** 消费者在消息积压超过阈值时，必须自动降速或触发告警，**严禁无脑重试导致雪崩**。本组件负责发现积压并告警。

- [ ] **执行 SOP-B 14 步**，特化验证：

```bash
# ① 把档 2 那条毒消息重新投递，这次走管理接口而不是 nats CLI
curl -fsS -X POST http://localhost:8203/infra/dlq-monitor/messages/{id}/redeliver \
  -H 'Content-Type: application/json' -d '{"idempotency_key":"acc-redeliver-001"}'

# ② 积压告警：灌 1000 条必失败的消息，断言告警发给了 notification
docker logs infra-notification-1-0-0 2>&1 | grep 'DLQ 积压'
```

---

#### Task 46：`mdm-supplier` —— 供应商主数据

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `mdm/supplier` / `mdm-supplier` |
| 端口 | HTTP **8081** / gRPC **9091** |
| schema / role | `mdm_supplier` / `mdm_supplier_rw` |
| 语言 / 外壳 | Go / 外壳一 `go-core` |
| 装配角色 | `default` |
| `dependencies.components` | **空**（mdm 是只读枢纽） |

**边界（§5.3）：** 供应商名称、资质、评级、结算方式。

**表：** `suppliers`（月分区）、`supplier_qualifications`（跟随主表）、`supplier_ratings`（月）、`event_outbox`/`event_inbox`（周）、`command_idempotency`。

**gRPC：** `Create` / `Update` / `SetStatus` / `Get` / `List` / `BatchGet` / `GetSummary`
**事件：** `mdm.supplier.created.v1` / `mdm.supplier.updated.v1` / `mdm.supplier.disabled.v1`

- [ ] **执行 SOP-B 14 步**（结构与 `mdm-customer` 完全一致，逐步替换参数）。

---

#### Task 47：`mdm-org` —— 组织架构

| 参数 | 值 |
|---|---|
| 组件 ID / 仓库 | `mdm/org` / `mdm-org` |
| 端口 | HTTP **8083** / gRPC **9093** |
| schema / role | `mdm_org` / `mdm_org_rw` |
| 语言 / 外壳 | Go / 外壳一 `go-core` |
| 装配角色 | `default` |
| `dependencies.components` | **空** |

**边界（§5.3）：** 部门、岗位、员工主数据、汇报线。**为 `infra-workflow` 的审批人路由提供组织数据。**

⚠️ **`infra-workflow` 不许同步调本组件**（§6.6：严禁反向同步调用业务组件）。审批人路由的做法是：业务组件在创建审批任务时，**自己**先调 `mdm-org` 查出审批人，把结果作为参数传给 `workflow.CreateTask`。

**表：** `departments`（不分区，树形小表）、`positions`（不分区）、`employees`（月分区）、`reporting_lines`（月）、`event_outbox`/`event_inbox`（周）、`command_idempotency`。

**gRPC：** `Create*` / `Update*` / `Get` / `List` / `BatchGet` / `GetSummary` / **`GetReportingChain`**（查某员工的汇报链，供审批人路由用）

- [ ] **执行 SOP-B 14 步**，特化验证：

```bash
# 断言 workflow 没有对 mdm-org 建依赖边
grep -A8 'components:' components/infra/workflow/component.yaml | grep 'mdm/org' \
  && echo "✗ workflow 反向依赖了业务组件（§6.6）" || echo "✓ 无反向依赖"
```

---

#### Task 48：档 4a 出档 —— 外壳按 §13.2 拆成最终形态

档 3 的 Go 外壳是「验证用的临时形态」（一个进程装 10 个模块）。18 个组件到齐后，按 §13.2 拆成最终的五外壳布局：

| 外壳 | 档 4a 结束时装的（18 个组件里的） | 最终容量 |
|---|---|---|
| **外壳一** go-core | `mdm-customer`、`mdm-supplier`、`mdm-product`、`mdm-org`、`erp-sales`、`erp-inventory`、`erp-finance` | 8 |
| **外壳二** go-backoffice | `crm-opportunity` | 16 |
| **外壳三** go-infra | `infra-iam-casdoor`、`infra-workflow`、`infra-notification`、`infra-dlq-monitor`、`infra-attachment`、`infra-storage`、`integration-im-dingtalk` | 21 |
| **外壳四** py-brain | （档 4a 里一个都没有） | 5 |
| **外壳五** py-render | `infra-print` | 2 |
| **独立容器** | `infra-bff-mobile`、`frontend-standard` | — |

- [ ] **步骤 1：`be-ops shell-config` 从「1 个 Go 外壳」改成「3 个 Go 外壳」**

这一步会**第一次真正触发跨外壳环境变量**（档 3 只在 Go↔Python 之间验过）：外壳二的 `crm-opportunity` 要调外壳一的 `mdm-customer`，必须指宿主机而不是 `127.0.0.1`。

- [ ] **步骤 2：重跑 Task 39 的四条测试**，特别是 `TestShellEnv_跨外壳依赖指宿主机`。

- [ ] **步骤 3：重跑全部门禁**

```bash
make up-all && make closedloop && make split-back-gate && make platform-acceptance
```

**🏁 档 4a 出档检查：**

```bash
make check && make registry-check && make gates && make tier0 \
  && make platform-acceptance && make closedloop && make split-back-gate
```
**七条全绿。** 从这一刻起，系统具备**最小可交付形态**：18 个组件覆盖了全部 `default` 角色 + 一条完整业务闭环。

---

## 第 10 部分 · 档 4b：按客户订单点名（37 个）

> ⚠️ **附录 H 里那 61 个「✅ 开发」是军火库的最终形态，不是开工令**（§9.6.1）。
> 按第 1 章的**选配测试**（客户愿单独付钱、或永远用不到 → 才独立成砖），5 个 IM、4 个支付、3 个电子签、2 套 IAM、3 套额外前端里，**绝大多数应当停在队列里，等第一个客户点名再动。现在就全开工，等于用选配测试的反面在花钱。**

### 10.1 每次点名的标准流程（八步，一步不省）

- [ ] **1. 确认这次要做哪几个**，写进本节 §10.2 的队列表，标上「已点名」与客户名。
- [ ] **2. 查册子**：`registry/ports.tsv` 与 `registry/schemas.tsv` 里该组件那一行（端口与 schema 早已分配好，**不许改**）。
- [ ] **3. 建目录**（SOP-B 或 SOP-F 结构），**不 `git init`**。
- [ ] **4. ⏸ 走一次检查点**：输出 §0.2 的标准话术，停下等人建仓库。
- [ ] **5. `git init` + push + `git submodule add`**（§3.5 步骤 C）。
- [ ] **6. 执行 SOP-B / SOP-F 全流程。**
- [ ] **7. 跑本组件的档 0 六项验收**（§5.2）。
- [ ] **8. 重跑全套门禁**（§9.6.1 档 4 的出档条件：**每加一个组件，档 0 的六项 + 拆回门禁重跑**）：

```bash
make gates && make tier0 && make closedloop && make split-back-gate
```

⚠️ **第 8 步不许攒着一起跑。** 拆回门禁一旦红了，你需要知道是哪一个组件让它红的——攒了 5 个再跑，就要在 5 个里二分。

### 10.2 队列表（37 个真正要开发的 + 3 个不开发 + 3 个未来/按需）

**优先级说明**：`P1` = 有明确下游依赖或补齐域完整性，客户一提就得有；`P2` = 典型可选业务；`P3` = 纯替换件/储备，等点名。

#### erp 域（剩 5 个）

| 仓库 | 语言 | 外壳 | 端口 | schema | 优先级 | 备注 |
|---|---|---|---|---|---|---|
| `erp-purchase` | Go | 一 | 8085/9095 | `erp_purchase` | **P1** | 强依赖 `mdm/supplier`、`mdm/product`、`erp/inventory`、`erp/finance`。**内含采购价格策略模块，与 `erp-sales` 的价格表逻辑对称**（§5.5） |
| `erp-manufacturing` | **Python** | 四 | 8302/9302 | `erp_manufacturing` | P2 | BOM 管理、生产工单、工序汇报、**MRP 运算**。选 Python 因为树形 BOM 遍历 + 矩阵运算（§12.1.2）。强依赖 `mdm/product`、`erp/inventory` |
| `erp-asset` | Go | 二 | 8111/9111 | `erp_asset` | P2 | 资产台账、折旧计算、资产盘点、报废处置 |
| `erp-quality` | Go | 二 | 8112/9112 | `erp_quality` | P2 | 质检标准、质检单、不合格品处理 |
| `erp-maintenance` | Go | 二 | 8113/9113 | `erp_maintenance` | P2 | 设备巡检计划、维修工单、备件管理 |

#### crm 域（剩 5 个）

| 仓库 | 语言 | 外壳 | 端口 | schema | 优先级 | 备注 |
|---|---|---|---|---|---|---|
| `crm-lead` | Go | 二 | 8100/9100 | `crm_lead` | **P1** | 线索录入、清洗、评分、转化为客户/商机 |
| `crm-customer` | Go | 二 | 8101/9101 | `crm_customer` | **P1** | ⚠️ 只管**归属关系**（公海/私海/负责人）与**跟进状态**、360° 视图。基础主数据归 `mdm-customer`，本组件**只存外键 + 摘要副本**（§5.4） |
| `crm-activity` | Go | 二 | 8103/9103 | `crm_activity` | P2 | 拜访/电话记录、日程、任务。`crm_activities` **月分区**，可更激进归档（§11.7） |
| `crm-campaign` | Go | 二 | 8104/9104 | `crm_campaign` | P2 | 营销活动、渠道 ROI、线索归因 |
| `crm-case` | Go | 二 | 8105/9105 | `crm_case` | P2 | 客户投诉、售后工单、SLA 管理 |
| `crm-commission` | **Python** | 四 | 8301/9301 | `crm_commission` | P3（reserve） | 阶梯提成、团队分润。选 Python 因为表达能力（§12.1.3） |

#### hrm 域（剩 6 个开发 + 3 个不开发）

| 仓库 | 语言 | 外壳 | 端口 | schema | 优先级 | 备注 |
|---|---|---|---|---|---|---|
| `hrm-attendance` | Go | 二 | 8106/9106 | `hrm_attendance` | P2 | 考勤打卡、排班、加班/调休统计 |
| `hrm-leave` | Go | 二 | 8107/9107 | `hrm_leave` | P2 | 请假申请、假期类型配置、余额扣减 |
| `hrm-expense` | Go | 二 | 8108/9108 | `hrm_expense` | P2 | 报销单、发票验真、费用审批 |
| `hrm-recruitment` | Go | 二 | 8114/9114 | `hrm_recruitment` | P3（reserve） | 职位发布、简历筛选、面试安排 |
| `hrm-appraisal` | Go | 二 | 8115/9115 | `hrm_appraisal` | P3（reserve） | KPI/OKR、360° 评估、绩效校准 |
| `hrm-payroll-es` | **Python** | 四 | 8300/9300 | `hrm_payroll_es` | P3 | `slot:payroll`。西班牙 IRPF + Seguridad Social。⚠️ **内嵌薪资引擎功能，不依赖 `hrm-payroll-core`**（决策 64）。**强制属性测试**（§8.0） |
| `hrm-payroll-core` | — | — | 8305/9305 | — | **❌ 不开发** | blueprint。只有一个国家实现时，「引擎」和「国家实现」是同一个东西（决策 64） |
| `hrm-payroll-cn` | — | — | 8306/9306 | — | **❌ 不开发** | blueprint。待市场验证 |
| `hrm-payroll-us` | — | — | 8307/9307 | — | **❌ 不开发** | blueprint。待市场验证 |

#### integration 域（剩 14 个）

⚠️ **这一域是选配测试的重灾区。** 5 个 IM 里我们只做了钉钉，另 4 个、以及 4 个支付、3 个电子签，**一个都不该在没有客户点名时开工**。

| 仓库 | 语言 | 外壳 | 端口 | schema | 优先级 |
|---|---|---|---|---|---|
| `integration-email` | Go | 三 | 8219/9219 | `integration_email` | **P1**（`channel:email`，几乎每个客户都要） |
| `integration-sms` | Go | 三 | 8220/9220 | `integration_sms` | **P1**（`channel:sms`，验证码场景） |
| `integration-im-wechat-work` | Go | 三 | 8208/9208 | `integration_im_wechat_work` | P3 |
| `integration-im-feishu` | Go | 三 | 8209/9209 | `integration_im_feishu` | P3 |
| `integration-im-slack` | Go | 三 | 8210/9210 | `integration_im_slack` | P3（海外） |
| `integration-im-teams` | Go | 三 | 8211/9211 | `integration_im_teams` | P3（海外） |
| `integration-payment-stripe` | Go | 三 | 8212/9212 | `integration_payment_stripe` | P3 |
| `integration-payment-paypal` | Go | 三 | 8213/9213 | `integration_payment_paypal` | P3 |
| `integration-payment-alipay` | Go | 三 | 8214/9214 | `integration_payment_alipay` | P3 |
| `integration-payment-wechat-pay` | Go | 三 | 8215/9215 | `integration_payment_wechat_pay` | P3 |
| `integration-esign-docusign` | Go | 三 | 8216/9216 | `integration_esign_docusign` | P3 |
| `integration-esign-pandadoc` | Go | 三 | 8217/9217 | `integration_esign_pandadoc` | P3 |
| `integration-esign-esign` | Go | 三 | 8218/9218 | `integration_esign_esign` | P3（e签宝，国内） |
| `integration-edi` | **Python** | 五 | 8401/9401 | `integration_edi` | P3（reserve）。陈旧复杂协议映射 + 数据清洗，选 Python（§12.1.1） |

⚠️ **每加一个 `channel` 适配器，都要回 `infra-notification` 的 `component.yaml` 加一条 `optional: true` 的弱依赖**，并确认它「按变量在不在决定要不要挂那个通道」的逻辑覆盖到了新通道（Task 27）。

#### infra 域（剩 2 个）

| 仓库 | 语言 | 外壳 | 端口 | schema | 优先级 | 备注 |
|---|---|---|---|---|---|---|
| `infra-audit` | Go | 三 | 8206/9206 | `infra_audit` | P2（reserve） | 基于事件的关键审计。**只监听 Domain Events 落盘，不同步调任何人**。`audit_logs` 月分区，**审计数据不删除，只归档**，按合规保留 3~10 年（§11.7） |
| `infra-iam-keycloak` | Go | 三 | 8221/9221 | `infra_iam_keycloak` | P3 | `slot:iam` 替换件。**与 `infra-iam-casdoor` 契约面必须完全一致**（同样暴露 OIDC 端点、同样提供 `/api/tenant/features`）。换砖走 runbook（§5.11） |

#### prj 域（2 个）

| 仓库 | 语言 | 外壳 | 端口 | schema | 优先级 |
|---|---|---|---|---|---|
| `prj-project` | Go | 二 | 8109/9109 | `prj_project` | P2 |
| `prj-timesheet` | Go | 二 | 8110/9110 | `prj_timesheet` | P2 |

#### ana 域（2 个，储备）

| 仓库 | 语言 | 外壳 | 端口 | schema | 优先级 | 备注 |
|---|---|---|---|---|---|---|
| `ana-bi` | **Python** | 四 | 8303/9303 | `ana_bi` | P3（reserve） | ⚠️ 决策 61：**报表查询不得直接扫交易明细表**，必须走汇总表或本组件。交易库服务 CRUD，不服务重分析 |
| `ana-ai` | **Python** | 四 | 8304/9304 | `ana_ai` | P3（reserve） | 客户流失预警、销量预测 |

#### frontend 域（剩 3 个）

| 仓库 | 状态 | 备注 |
|---|---|---|
| `frontend-advanced` | 🔜 未来 | `slot:frontend` 替换件。3D 仓库看板、拖拽式审批流、经营驾驶舱 |
| `frontend-{industry}` | 🔜 未来 | 行业定制前端 |
| `frontend-{customer}` | 📋 按需 Fork | **不是独立开发**，是复制 `frontend-standard` 目录改 remote（§9.5 代码级定制）。⚠️ `metadata.id` 与 `version` 一个字都不能改 |

### 10.3 档 4b 的两条持续纪律

1. **每加一个组件，跑一次 §10.1 第 8 步的全套门禁。**
2. **每周跑一次拆回门禁**（§13.7），不管这周有没有加组件。

---

## 第 11 部分 · 贯穿全程的纪律（不属于某一档）

| # | 纪律 | 频率 | 出处 |
|---|---|---|---|
| 1 | **拆回门禁**：全部 `local: true` 去掉、`brickkit up` 全拆一次、业务闭环全绿 | **每周一次** + 每次合并组关系变动时 | §13.7、决策 92 |
| 2 | **import 扫描**：任何组件不许 import 另一个组件仓库 | **每次 CI** | §13.3 铁律六、决策 91 |
| 3 | **平台断言回归**：20 条平台验收用例重跑 | **每次 brickKit 升级后** | §9.6.2、决策 96 |
| 4 | **发现平台有问题时**：先在 `be-acceptance` 记一条用例（哪怕是红的），再回 brickKit 仓库修。**不许在业务侧绕过去** | 每次发生 | §9.6.2 |
| 5 | **提交前还原军火库结构**：`make arsenal-restore` | 每次 commit（pre-commit hook 兜底） | §3.3 |
| 6 | **`brickkit remove` 前先 commit & push** | 每次 remove | §9.4.2 |
| 7 | **契约变更走 `make contract-check`**：`buf breaking` / `oasdiff` 拦破坏性变更 | 每次改 `contracts/` | §8.5、决策 33 |
| 8 | **AI 生成的超 50 行复杂业务函数**，必须带自然语言决策树 + Mermaid 流程图注释，否则本地 Code Review 直接打回 | 每次 AI 生成 | §8.5、决策 48 |
| 9 | **核心交易组件的属性测试**（`erp-inventory` / `erp-finance` / `hrm-payroll-es` / `crm-commission`）：人类定义不变量，框架生成随机边界输入攻击 | 每次改核心逻辑 | §8.0、决策 49 |
| 10 | **`brickkit restore` 一旦上线**：改用 `brickkit init --hooks`，删掉我们那份 `arsenal.sh` 的本地兜底判据，避免两套分叉 | 一次性 | §3.3 |

---

## 第 12 部分 · 对设计书的五处修正与两处扩展（**已全部回写设计书**）

**这一节是给半年后接手的人看的**：以下是本计划制定过程中在设计书里发现的不自洽，**全部已经改进设计书本体**，本节只留一份变更记录。设计书与本计划现在是一致的——**两边冲突时以设计书为准，并回来改本计划**。

### 修正（5 处，已回写）

| # | 设计书原本写的 | 已改成 | 为什么 | 回写到设计书哪里 |
|---|---|---|---|---|
| 1 | 附录 G / §2.7.1：Traefik Dashboard 8080 | **18080** | 撞外壳一 `mdm-customer` 的 HTTP 8080，而外壳必须把端口发布到宿主机（§13.1），是真撞 | §2.7.1 表 + 表下新增说明段、§2.7.2 ③、§2.7.5 compose、附录 G |
| 2 | 附录 G：Keycloak 8080 / Prometheus 9090 / Kafka 9092 | **18081 / 19090 / 19092** | 同上，分别撞 `mdm-customer` 的 HTTP、`mdm-customer` 的 gRPC、`mdm-product` 的 gRPC | 同上 |
| 3 | §13.2 外壳二列 14 个组件 | **16 个**（加 `hrm-recruitment`、`hrm-appraisal`），区间 8100–8113 → **8100–8115** | 那两个是 Go、常规 CRUD、`reserve`，原文漏列。它们必须有端口，否则档 4b 做到时无处可放 | §13.2 外壳二表 + 表下新增说明 |
| 4 | §13.2 外壳三列「6 个 infra + 15 个 integration = 21 个」 | **7 个 infra**（加 `infra-iam-casdoor`）**+ 14 个 integration = 21 个**，端口区间写明 8200~8220 | `integration-edi` 是 Python、在外壳五，所以 integration 只有 14 个；差的那一个是 `infra-iam-casdoor`（Go、~500 行、没被任何外壳列表收录，但 §9.6.1 档 3 说「Go 外壳装 10 个模块」时把它算进去了）。补上后 21 才对得上 | §13.2 外壳三表 + 表下新增说明；顺带修正「钉子户」表把 Traefik/Casdoor 说成「基础资源」的口径（它们是形态 B 带外容器） |
| 5 | `opportunity.won.v1` 只有**两段**，全书其余事件都是三段 | **`crm.opportunity.won.v1`** | §3.7 的命名法是 `{domain}.{aggregate}.{action}`。改名的时机只有「还没有消费者」这一个——一旦 `erp-sales` 开始消费，改名等于删掉旧 subject（决策 19：只增不删不改） | §3.7（补了完整事件名表与两条 ⚠️）、§4.3 事件图、附录 E 沙盘 |

### 扩展（2 处，已回写）

| # | 设计书原本写的 | 已扩成 | 为什么 | 回写到设计书哪里 |
|---|---|---|---|---|
| 1 | §5.10：`be-sdk-events-go`（reserve，Go 事件 SDK） | **`be-sdk-go` / `be-sdk-python` / `be-sdk-ts`，必需件，SOP-L 十项横切能力** | 事件只占 10 项里的 3 项。`Endpoint` 剥 scheme、`WithTx` 的 `SET LOCAL`、OTel 的 Blackhole 降级这几项，每个组件各写一遍必然有人写错——**而写错的那两处恰好是设计书自己点名的「最难查的雷」**。它不是「公共 model 包」：零业务逻辑、零组件 model、零组件间引用，已加进 import 扫描白名单 | §5.10 新增「`be-sdk-*`」小节（含十项能力表）、附录 H 第 72 行、决策 100 |
| 2 | §5.10 / §2.4：`be-ops` 的端口册（产出 6）只管 61 个组件 | **端口册纳入带外容器的宿主机端口** | 外壳把端口发布到宿主机后，组件端口与带外容器端口在**同一个宿主机端口空间**里，两边会真撞（修正 1、2 就是这么发现的）。只管 61 个组件的端口册发现不了这四处 | §3.5.1.1（含 `slot:frontend` 族共用 80 的唯一例外）、§5.10 产出 6、附录 I「全局端口册」、决策 99 |

### 另外补进设计书的一处（不是修正，是原本缺的一档）

**§9.6.1 的「档 4」拆成「档 4a 补齐 default」与「档 4b 铺货」**，并补了一张表说明那 5 个 `default` 组件（`infra-storage` / `infra-attachment` / `infra-dlq-monitor` / `mdm-supplier` / `mdm-org`）为什么不能等客户点名。同时把档 2 出档条件里的「DLQ 进得去出得来」标注清楚——`infra-dlq-monitor` 在档 4a，档 2 验的是**平台 SDK 层的死信通道本身**，管理界面留到 4a。对应新增**决策 101**。

---

## 第 13 部分 · 已知风险与待决事项

| # | 风险 / 待决 | 影响 | 何时处理 |
|---|---|---|---|
| 1 | **`brickkit restore` / `init --hooks` 尚未实现**（实测当前 CLI 报「未知命令」；brickKit 仓库里设计已确认、实现计划已提交） | submodule 结构下 `sync` 的失误只能靠我们自己那份 `arsenal.sh` 兜底 | Task 5 已做兜底；官方版上线后按纪律 10 换掉 |
| 2 | **RustFS / Kafka / Casdoor 三个镜像的环境变量名按惯例写**，未经实测校准 | `make up` 可能因变量名不对而起不来 | Task 1 步骤 8 已排入校准动作 |
| 3 | **本机 `my-postgres` 跑的是 postgres:15，端口 5432 与本项目冲突**；`my-rustfs` 占 9000 | `make up` 会在预检阶段报错中止 | 由你手动处置（已确认的分工）。`make check` 会点名 |
| 4 | **`opportunity.won.v1` 的 subject 不带 `crm.` 前缀**，与 §3.7 的 `{domain}.{aggregate}.{action}` 命名法不一致 | 半年后有人「顺手改统一」会打断 `erp-sales` 的消费者 | Task 29 已要求在事件清单里写明；档 2 闭环用例会锁住它 |
| 5 | **共享连接池没有舱壁**（决策 3 / §13.3 铁律二的已知代价）：一个模块连接泄漏或跑长事务，整组一起等 | 合并态下的故障隔离弱于全拆态 | 这是合并那一刻就已付掉的账，不是 bug。上 K8s 全拆（阶段三）自动恢复 |
| 6 | **签名整体不生效**（§9.4.1）：全本地源不强制签名 + 外壳镜像不在覆盖范围内 | 供应链保证要靠别的东西承担 | 三条替代措施已写进全局约束 §J；交付文档里必须明确「外壳镜像谁构建、用谁的密钥签、客户怎么验」 |
| 7 | **档 3 的 Go 外壳是临时形态**（1 个进程 10 个模块），档 4a 才拆成 §13.2 的三个 Go 外壳 | 拆的那一次会第一次真正触发跨外壳环境变量 | Task 48 已排；Task 39 的 `TestShellEnv_跨外壳依赖指宿主机` 会守住 |
| 8 | **`be-assembly-{customer}` 与「客户 → 组件仓库」映射表**尚未开工 | 首个真实客户交付前必须有 | 首个客户签约时启动，走 §10.1 的同一套流程 |

---

## 第 14 部分 · 自检（本计划写完后的核对结果）

**① 设计书覆盖核对**

| 设计书章节 | 对应本计划 |
|---|---|
| §1.5 两条不可让渡原则 | 全局约束 A；SOP-B 的 B-8、B-13；Task 36 的四条不许 |
| §2.7 基础资源 | 第 1 部分；Task 1–3 |
| §3.5 两份 yaml | SOP-B 的 B-3/B-4；Task 12 |
| §3.5.1.1 端口全局唯一 | §2.1 端口册；Task 4 |
| §3.8 数据消费范式（`batchGet`） | 每个组件契约都含 `BatchGet`；Task 31 的 N+1 检测 |
| §3.11 CI 门禁 | 全局约束 I；Task 15 步骤 5 |
| §4.4/§4.5 Saga 与薛定谔超时 | Task 21 的三条铁律；Task 34 步骤 2 |
| §5.x 全量组件军火库 | §2.3 组件总表（61 个）；第 10 部分队列表 |
| §6.x 基础设施砖细节 | Task 25–31、43–47 |
| §7 可观测性 | SOP-L 的 `otel.go`；Task 1 的 obs compose；Task 30 |
| §8 AI-Native 样板 | SOP-B；属性测试（Task 19/20）；纪律 8/9 |
| §9.6 推进顺序档 0→4 | 第 5–10 部分 |
| §9.6.2 平台验收 20 条 | Task 22 |
| §11 数据生命周期 | 全局约束 G；每个组件的分区表设计；SOP-L 的 `query.go`/`archive.go` |
| §12 多语言战略 | §2.3 的语言列；Task 24 三份 SDK；Task 30/31 |
| §13 合并部署 | 第 8 部分；Task 36–41 |
| 附录 E 事件沙盘 | Task 34 |
| 附录 G 基础资源速查 | §1.1；§1.2 的四处端口修正 |
| 附录 H 仓库速查 | §2.3；§0.2 的 6 个检查点 |

**② 占位符扫描**：无 `TBD` / `TODO` / 「实现细节略」/「类似 Task N」。SOP-B / SOP-F / SOP-L 是显式定义的完整流程，不是「参照上文」。

**③ 类型一致性**：`besdk` 的 9 个公开 API 签名在 Task 6 定义，Task 7 实现，Task 15 / 24 / 36 消费，全程同名同签名（`Endpoint` / `MustEndpoint` / `WithTx` / `PublishOutbox` / `StartOutboxPump` / `Consume` / `InitOTel` / `ListWindow` / `BatchGetRouted` / `Event`）。`be-ops` 的 8 个子命令在 Task 6 定名，Task 8 / 33 / 38 / 39 / 40 逐个实现，命名一致。

**④ 组件计数核对**：61 = 10 infra + 15 integration + 4 mdm + 7 crm + 8 erp + 9 hrm + 2 prj + 2 ana + 4 frontend。
需构建 58（61 − 3 blueprint）= 档 0(1) + 档 1(4) + 档 2(8) + 档 4a(5) + 档 4b(37) + 未来/按需前端(3)。✅

**⑤ 端口册核对**：组件 HTTP 8080–8115 / 8200–8221 / 8300–8307 / 8400–8401 / 8500 / 80（frontend 族共用）；组件 gRPC 9090–9115 / 9200–9221 / 9300–9307 / 9400–9401；带外容器 80 / 443 / 3000 / 3100 / 3200 / 4222 / 4317 / 4318 / 5432 / 5672 / 8000 / 8222 / 9000 / 9001 / 13133 / 15672 / 18080 / 18081 / 19090 / 19092。**两两不撞。** ✅
