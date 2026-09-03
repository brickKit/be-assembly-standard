# BrickEnterprise · AI 助手导读

> 这一页是**索引与禁令**，不是教程。它每次会话都会被加载，所以刻意保持薄。
> 细节在它指向的地方——**每一条指向都带节号，别猜**。
>
> 写给 AI 助手，人也能读。给人看的入口是 [`docs/plans/00-总纲.md`](docs/plans/00-总纲.md)。

**这是什么**：基于 brickKit 平台的企业级组件化 ERP/CRM 军火库。61 个组件、5 个外壳、一套按需装配的方法论。本仓库（`be-assembly-standard`）既是标准装配模板，也是**军火库索引**——`components/` 下每个组件是一个 git submodule。

---

## 只有一处必须先读

**§1.5 两条不可让渡的开发原则。** 全书其余部分都可以改，这两条不能：

1. **每个组件都以纯 brickKit 组件形态开发，并独立跑通。** gRPC 一个不省；`extraPorts` 里声明的端口必须真的 `Listen`；能只装这一个组件（连同强依赖树）就 `brickkit up` 起来。
   **「反正最后要合并进外壳，同进程直接调函数不就完了」——这么想一次，K8s 全拆就永远到不了。** gRPC 是逻辑边界的物理载体，省掉它等于合并那一刻边界消失。
2. **合并只发生在部署形态上。** 外壳能做的只有一件事：把 N 个进程变成 1 个进程。

---

## 当前状态

| 项 | 值 |
|---|---|
| 阶段 | **阶段一 · 地基与第一块砖**（未开工 / 见 [`01-阶段一`](docs/plans/01-阶段一-地基与第一块砖.md)） |
| 已建组件 | **0 个**（`components/` 还是空的） |
| 已钉死不许改的 | `registry/ports.tsv`、`registry/schemas.tsv`（**只增不改**，见下） |
| 平台 CLI | 已装。`brickkit restore` / `init --hooks` **尚未实现**（实测报「未知命令」） |

⚠️ **改了阶段就回来改这张表。** 它是 AI 判断「现在该做什么、什么已经定死」的唯一依据。

---

## 路由表：要做 X，读 Y

| 你要做的事 | 先读 |
|---|---|
| 搞清整体理念、九域、三枢纽、四把尺子 | 设计书 §1、§2.5、§2.6 |
| 起环境 / 查基础资源 | 总纲 §1；`make help` |
| **写任何 `component.yaml`** | 总纲 §2.1 端口册 + §2.2 schema 册 + 全局约束 B/C/E/F。**端口不许自定** |
| 写一个新组件 | 总纲 §4 SOP-D（四份文档）→ SOP-B（后端）/ SOP-F（前端） |
| 写前端 | 总纲 §4 SOP-F；设计书 §5.9 七条前端铁律、§12.2 |
| 改契约 | 设计书 §3.4 铁律 3、§8.5；组件仓库 `make contract-check` |
| 加迁移 / 分区表 | 设计书 §11.2；**§11.2.3 迁移状态表必须落各自 schema** |
| 事件 / Outbox / 幂等 / 补偿 | 设计书 §3.10、§4.4、§4.5、§4.6 |
| 合并部署 / 外壳 | 设计书 §13；`shells/*/AGENTS.md` |
| 装配生成（路由表、建库脚本、端口册…） | 总纲 §2.4 `be-ops` 的 8 个产出 |
| 验收 / 门禁 | 设计书 §3.11、§9.6.2、§13.7；`make gates` |
| **不知道某段业务逻辑该怎么写** | 总纲 §4 **SOP-R** 的 R-2 表：该看现实中哪个开源 ERP 的哪个模块。**先读那个模块，再回来实现** |
| **拿不准要不要用设计模式** | 总纲 §4 **SOP-P**：四个信号 / 已定的 9 处 / 三种不该用的情况 |
| 某个具体组件 | `docs/design/<仓库名>.md`（为什么这样设计，含第 8 节参考实现）+ `components/<scope>/<name>/AGENTS.md`（怎么改它） |
| 平台 CLI 的行为 | `.claude/skills/` 下四个技能；brickKit 仓库 `design/` 下 14 本 |

**冲突时的优先级**：设计书 > 总纲 > 阶段计划 > 本页。发现下层与上层矛盾，**改下层**。

---

## 十一条最容易写错的（每条都带症状）

前六条与第 11 条的共同点：**代码看起来完全正确，测试也能过**，症状要么极难联想，要么根本没有。

| # | 不许 | 症状 | 出处 |
|---|---|---|---|
| 1 | `grpc.Dial(os.Getenv("X_GRPC_ENDPOINT"))` | 平台注入的值**恒为 `http://` 开头**，没有 `grpc://`。连不上，而**报错指向名称解析**，极难联想到是这里。必须 `TrimPrefix("http://")` | §2.1 |
| 2 | 不带 `LOCAL` 的 `SET ROLE` / `SET search_path` | 连接还回共享池后**下一个借用者原样继承**——A 组件的查询打在 B 组件的表上，**不报错、不崩，只是悄悄读写了别人的数据**。全项目最难查的一个 | 决策 3、§13.3 铁律二 |
| 3 | 组件之间互相 `import` | **没有任何症状**，系统跑得更快了，直到要上 K8s 全拆才发现拆不动，代价是重写。也不许抽「公共 model 包」 | §13.3 铁律六、决策 91 |
| 4 | `os.environ["X_ENDPOINT"]` / `os.Getenv` 后判空当缺失 | 弱依赖缺失时那个变量**根本不存在**（不是空串），下标访问启动即崩。这是平台刻意的设计 | §3.6 |
| 5 | 往 `component.yaml` 写 `asset` / `assembly_role` / `slot_name` / `edge_routes` / `menus` / `domain` / `tier` / `shell` | 未知键**当场报错**，不是静默忽略。这些全部放同目录 `assembly.yaml` | §3.5、决策 84 |
| 6 | 配置项起名 `otelEndpoint` / `databaseSchema` | 命中平台保留后缀 `*_ENDPOINT` / 前缀 `DATABASE_`，被**跳过并只给一条警告**——组件拿不到值，而 `up` 一路绿灯。必须叫 `otelBaseUrl` / `pgSchema` | §2.7.3 |
| 7 | `/healthz` 里查库、查依赖组件、查 NATS | 一个下游抖动让所有上游同时被判不健康并重启；合并态下**一个模块拖挂探针，整组 21 个组件一起重启** | §12.3.6 |
| 8 | `FROM scratch` / `distroless` 基底 | 平台的健康检查是 `CMD-SHELL`，没 shell 就永远失败。症状是**组件日志写着「已就绪」，而平台说它不健康**。基底必须带 `/bin/sh` + `wget` | §12.3.7 |
| 9 | Docker labels / K8s annotations 的值写成 `true` / `8080` | 两边都只收字符串，平台**不做自动转换**，`traefik.enable: true` 会被当场拦下。一律带引号 | §5.10 生成器铁律一 |
| 10 | 客户没买的组件写 `enabled: false` | 它下面那一串**跟着级联不启动**——关掉 hrm 顺带把 mdm 关了。「没买」的正确写法是**整条不写进 `brickkit.yaml`** | 决策 98、§9.5 |
| 11 | 把 **GPL / LGPL / AGPL** 项目（Odoo / ERPNext / Tryton / SuiteCRM / Twenty…）的代码复制、翻译、或逐行改写进任何组件 | **没有技术症状，只有法务后果**：客户 Fork 件成为衍生作品，必须同样开源——而设计书 §3.2 明确 `customer_fork` 是「闭源且归客户所有」，整条 Fork 机制当场失效。**「我只是用 Go 重写了一遍它的算法」同样算衍生作品** | 总纲 §4 SOP-R 的 R-1c |

⚠️ **第 11 条的正确做法是「读设计、不抄代码」**：学领域模型、状态机、字段设计与踩坑经验，那是知识不是代码。大型开源 ERP 里许可证宽松、可以直接抄的只有 **Apache OFBiz（Apache-2.0）**，抄了要补 `NOTICE`。

另外两条金额与查询的：**金额字段一律 `string` 传 decimal**（`double` 跨语言丢精度）；**List 不给 `offset` 字段**，深分页在契约层面就不可表达（决策 53）。

---

## 三张钉死的表：只增不改

| 表 | 为什么不许改 |
|---|---|
| `registry/ports.tsv` | **gRPC 等额外端口没有任何事后补救手段**：平台改写地址时明确跳过额外端口，两个 `local: true` 组件撞同一额外端口时 `brickkit up` 生成阶段硬报错。写到第 30 个组件才发现要回头改前 29 份 Manifest（§3.5.1.1） |
| `registry/schemas.tsv` | 库一旦按「一组件一 database」建好、数据进去了，再改成一库多 schema 就是一次数据迁移（决策 3） |
| `.gitmodules` | 它就是设计书 §3.4.1 要的「组件 → 仓库 → 精确 commit」映射表，是半年后接手的人**唯一**能查到「这个客户的 `erp/sales@1.0.0` 到底是哪一份代码」的地方 |

唯一的端口复用例外：`slot:frontend` 族 4 个前端组件共用 80（槽位互斥、永不共存、各自独立 Nginx 容器不进外壳）。

---

## 仓库结构与三条运维禁令

```
components/<scope>/<name>/   每个组件一个 git submodule（scope/name 是组件 ID，仓库名是扁平的 domain-name）
components/.archived/        brickkit sync 的归档区（以 . 开头，文件管理器默认隐藏）
shells/{go,python}/          外壳，不是组件，不进 brickkit.yaml
tools/{be-ops,be-acceptance,be-sdk-go,be-sdk-python,be-sdk-ts}/
registry/                    端口册 + schema 册
docs/plans/                  00-总纲（长期有效）+ 每阶段一份
docs/design/                 组件设计计划，一个组件一份
```

| 禁令 | 为什么 |
|---|---|
| **`brickkit remove` 前必须先 commit & push** | 它**连同已归档的源码目录一起删除**。submodule 里有未 push 的改动时这是数据丢失（§9.4.2） |
| **提交前跑 `make arsenal-restore`** | `brickkit sync` 整目录搬家会在本仓库的 diff 里留下「整棵树搬家」。pre-commit hook 会拦，但先跑一次省事（总纲 §3.3） |
| **Fork 件的 `metadata.id` 与 `version` 一个字都不能改** | 改了之后所有依赖方拿到的 `*_ENDPOINT` **整个消失**——平台注入的变量名是从组件 ID 推导的，整条 Fork 机制当场垮掉（§3.4.1） |

**找不到源码时先看 `components/.archived/`。**

---

## 常用命令

```bash
make help                        # 所有目标
make check                       # 一键查询基础资源（容器/镜像 tag/端口/健康/网络）
make up                          # 一键开启默认资源（先整体预检，不符则一个都不动）
make <res>-up / <res>-down       # 单个可选资源：minio/keycloak/kafka/rabbitmq/nginx/obs
make registry-check              # 端口册与 schema 册自洽
make gates                       # 铁律六 import 扫描
make docs-check REPO=<仓库名>     # 某个组件的四份文档结构检查
make arsenal-check / -restore    # 军火库结构与 brickkit.yaml 是否自洽
brickkit up --dry-run            # 只算不启动，看这次会跑哪些、什么顺序
```

**任何 `brickkit` 命令的参数去问 `brickkit <命令> --help`。** 本页与 `.claude/skills/` 都刻意不复刻参数清单——复刻一份就是承诺维护两份，而过期的那份会让你自信地敲出一条 `unknown flag`。

---

## 平台的四条铁律（brickKit 侧）

1. **版本必须精确。** `1.2.0` 可以，`^1.2` / `~1.2` / `1.2.x` / `latest` 一律不行。范围版本是**被论证过后拒绝**的，不是还没做。
2. **不许碰保留变量。** `COMPONENT_ID`、`COMPONENT_VERSION`、任何以 `_ENDPOINT` 结尾的、以及 `DATABASE_` / `REDIS_` / `MQ_` / `STORAGE_` / `SEARCH_` / `SMTP_` 开头的，由平台注入；`configSchema` 里起同名项会被跳过。
3. **健康检查有禁令。** 别把依赖的可用性写进自己的健康检查。**默认启动宽限是 60 秒**（不是 30）；Python 写 `120`、Node 写 `90`、Go 不写、外壳镜像写 `300`。
4. **启停跟着上层走。** 顶层关掉，下面那一串跟着不启动。收窄范围唯一的路是改 `brickkit.yaml` 的 `enabled`，**没有 `--only` 之类的参数**。

> 第 3 条的「60 秒」修正自 `brickkit init` v0.1.1 生成的旧版导读（那份写的是 30 秒）。依据是设计书 §12.3.5：平台的 `startPeriodSeconds` 默认值就是 60，`interval`/`timeout`/`retries` 写死为 10s/3s/3。**平台导读的权威版本在 brickKit 仓库**；本页接管了这个文件，所以 `brickkit skills update` 不会再刷新它（`.claude/skills/` 下那四个技能仍会正常刷新）。

---

## 不要提议的东西（都是被论证过后拒绝的）

| 别提议 | 理由 |
|---|---|
| 给 brickKit 加注册中心 / 配置中心 / 网关 / 常驻服务 | 平台刻意极简。**正因为它克制，我们才能只改 DNS 指向就把对端换成任何东西** |
| 引入 Redis | JWT 无状态 + 本地摘要副本 + PG 行级锁 + 网关限流已覆盖它的全部常见用途（决策 71） |
| 引入 Consul / etcd / Zookeeper | 路由表生成期聚合，不需要运行时服务发现（决策 72） |
| 把事件总线 / 对象存储包成组件 | 我们零代码的东西不该包成组件——包了之后「换实现」从改一个字段变成改几十个 Manifest（决策 86） |
| 让网关或可观测性当组件 | 平台的资源 `kind` 是封闭清单（无 `gateway` / `iam` / `telemetry`），且 Manifest **没有 volumes 字段**，配置文件挂不进去 |
| 前端用 React | 决策 79：ToB 表单双向绑定、多端统一、AI 生成代码结构清晰、国内生态。锁定 Vue3 + Uni-app |
| 用 Java / C# 写组件 | JVM 内存与启动开销和「客户本地单机部署」根本冲突（决策 78） |
| 为了代码生成自研工具链 | 工具优先，AI 兜底。有现成的就用现成的（决策 32） |
| K8s 上做部分合并部署 | `local: true` 只能配 `deploy.target: docker`，K8s 目标下 CLI 生成阶段直接报错。**上 K8s 就是全拆，没有中间态**（决策 88） |

---

## 写代码之前的五个自查

1. **我要写的东西，端口和 schema 是从 `registry/` 抄的，还是我自己起的？** 自己起的一律错。
2. **我是不是让两个组件模块直接互相认识了？** 跨组件只能走 gRPC/HTTP + `contracts/`，代码不共享（`be-sdk-*` 是唯一白名单）。
3. **这段业务逻辑我是凭空想的，还是先看过现实 ERP 怎么做的？** 凭空设计的领域模型漏掉的边界情形，要到客户上线三个月后才暴露。该看哪个模块见总纲 §4 SOP-R——**但只读设计，不抄代码**（第 11 条）。
4. **这个文件是不是已经太长了？** 一个函数超 150 行、一个文件超 600 行、或一条 `if-elif` 链超 5 个分支且还会长，就对照总纲 §4 SOP-P 判一次要不要拆成策略/状态表。反过来，**逻辑本身很简单却硬套模式，是更糟的结果**。
5. **我改的这处，四份文档里哪几份该跟着改？** 边界/契约/事件变了 → 先改 `docs/design/<仓库名>.md`；功能变了 → README；用法或结构变了 → `docs/手册.md`；禁令或判据变了 → 该仓库的 `AGENTS.md`。**顺序是文档先行，不是代码先行。**
