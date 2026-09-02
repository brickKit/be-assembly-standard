---
created: 2026-09-02
updated: 2026-09-02
---
# BrickEnterprise 设计书 · 修订清单

> 对象：`BrickEnterprise 设计书.md`（v 当前版）
> 核对基准：brickKit `AI-CONTEXT.md` / `design/002~008` / `组件合并部署.md` / `internal/` 实现
> 总纲：**业务架构不动，凡是设计书替 brickKit 承诺的事，一律改成我们自己承诺。**
>
> **2026-09-02 更新①**：brickKit 已回信并落地 4 项（labels 透传功能 + 三处文档口径），
> 拒绝 `as:` 依赖别名。本清单据此修订了 A1 / A3 / A7 / B1 / C 与批次划分，修订处标 🔄。
>
> **2026-09-02 更新②：A / B / C 三类已全部落到设计书里**（`git diff` 597 增 / 210 删）。
> 本清单从"待办"转为**变更依据记录**——想知道某处为什么这么改，看这里；
> 想知道现在是什么样，看设计书。仅 **D 类（待实测）3 项**未完成。

---

## 0. 一句话

设计书里所有关于业务的判断都站得住。需要改的全部集中在一处病根：**书里有 8 处把「我们要做的事」写成了「brickKit 会做的事」**。平台不做，活不会消失，只是没人认领。改法不是降低野心，是把这些活明确划到 `be-ops` 名下。

分级：**A = 不改就跑不起来或会静默出错**；**B = 会在交付现场变成事故**；**C = 口径与补充**。

---

## A 类 · 必须改

### A1 · §3.5 的 `component.yaml` 整份不合法 → 拆成两份

**现状**：`name` / `labels` / `asset` / `expose.edge_routes` / `dependencies.strong|weak` / `requirements` / `menus` / `slot_name` —— 平台一个都不认识。而 brickKit **拒绝未知字段并报错退出**（`002` §2.2.1，无扩展字段机制）。照 §3.5 写出来的第一个组件，`brickkit up` 直接失败。

**改法**：拆成两个文件，§3.5 同时给出两份骨架。

```yaml
# ① component.yaml —— 平台读的那一份，字段名一个字都不能自创
apiVersion: brickkit/v1
kind: Component
metadata: { id: erp/sales, name: 销售管理, version: 1.0.0, description: ... }
artifacts:
  - type: api-contract
    format: protobuf
    files: [contracts/sales.proto]
  - type: metadata                    # ← 装配元数据。🔄 已被 brickKit 采纳为
    files: [assembly.yaml]            #    官方约定（002 §2.2.1），不再是私下约定
dependencies:
  components:
    - mdm/customer@1.0.0              # 强依赖
    - mdm/product@1.0.0
    - erp/inventory@1.0.0
    - id: infra/notification@1.0.0    # 弱依赖
      optional: true
  resources:
    - { kind: database, engine: postgresql }
    - { kind: mq, engine: nats }
configSchema:
  type: object
  properties:
    pgSchema: { type: string, default: erp_sales }   # 见 A5
deployment:
  type: container
  image: brickenterprise/erp-sales:1.0.0
  port: 8080
  extraPorts: [{ name: grpc, port: 9090 }]
  labels:                             # 🔄 平台新增的透传口，组件作者的推荐值
    prometheus.io/scrape: "true"      #    值必须是字符串，布尔/数字要带引号
    prometheus.io/port: "9090"
migration: { command: ["./migrate", "up"] }
healthCheck: { type: http, path: /healthz, startPeriodSeconds: 60 }
```

```yaml
# ② assembly.yaml —— 只有 be-ops 读，平台永不解析
id: erp/sales
version: 1.0.0                        # 必须与 component.yaml 一致，be-ops 校验
asset:
  source_type: open_standard
  assembly_role: optional
  contract_lock: strict
domain: erp
tier: backend
edge_routes:
  - { path: /erp/sales/**, auth: required }
menus:
  - { key: erp.sales, title: 销售订单, permission: erp.sales.view }
```

**为什么放我们自己的文件更好，而不是去要平台加扩展字段**：这些字段平台永远不读，塞进 `component.yaml` 里平台也**校验不了**；放在 `assembly.yaml` 里，`be-ops` 可以用严格 schema 卡住拼写错误。载体问题已解决——`artifacts` 随 Manifest 一起分发（闭源组件由市场存储），`add` / `fetch` 自动下载到 `.brickkit/artifacts/<版本化服务名>/`。

### A2 · slot 模型重构：五个槽位里有三个不该是组件

**现状**：§3.6 / §5.11 写「业务组件只依赖 `role:{slot}`」。平台没有 role/slot/接口依赖，依赖只能写精确组件 ID，而注入的变量名由 ID 推导（`INFRA_IAM_CASDOOR_ENDPOINT`）。按现在的写法，换一次 IAM 要改几十个仓库的 Manifest **加源码**。

**改法**：slot 概念保留（它对我们的货架管理是有意义的，写在 `assembly.yaml` 里，由 be-ops 做互斥校验），但**落地形态按下表重分**：

| 设计书原写法 | 改成 | 换实现的动作 |
| --- | --- | --- |
| `slot:event-bus`（3 个仓库） | **基础资源** `kind: mq, engine: nats\|kafka\|rabbitmq`，组件读 `MQ_HOST/MQ_PORT` | 改 `brickkit.yaml` 一个字段 |
| 对象存储底座（RustFS/MinIO） | **基础资源** `kind: storage, engine: minio`，组件读 `STORAGE_*` | 同上。`infra-storage` 作为 S3 门面组件保留 |
| `slot:gateway`（2 个仓库） | **带外容器**，不进组件清单（平台不做 path 路由，manifest 也没有 volumes 挂不了配置） | 换 compose 文件 |
| `slot:iam` | 保留为组件，但**业务组件对它无依赖边**（JWT 本地验签，公钥走 `configSchema`） | 换组件 + 换公钥配置 |
| `slot:frontend` | 保留为组件，无下游依赖 | 改 `brickkit.yaml` 一行 |

**连带**：附录 H 组件总数 **68 → 63**（删 event-bus×3、gateway×2；RustFS/MinIO 本来就不在组件清单里）；§5.13 统计表同步（infra 17→12，需构建 65→60）；§5.1 表格删掉对应 5 行并补一段"为什么它们不是组件"。

### A3 🔄 · 路由表的**两个出口**（原「brickkit up 生成期聚合」是错的）

**现状**：决策 20 / §6.3 写「`brickkit up` 生成期聚合路由表」。平台不做 path 路由，Ingress 只生成 `host + path: /`。

**平台侧已变化**：brickKit 接受了我们的诉求，**已实现 labels 透传**（`002` §4.7、`003` §4.11）——`component.yaml deployment.labels` 与 `brickkit.yaml components[].labels` 逐键合并，Docker 写进 service `labels`，K8s 写进 Deployment 与 Pod 模板的 `annotations`。**原修订清单里「若被拒绝，退路是手写 file-provider 配置」那段可以删掉。**

**但它和 A7 会撞**：`local: true` 的组件不生成容器，**没有可以挂标签的对象**——被合并进外壳的那 45 个组件，`components[].labels` 一行都不会出现在生成物里（平台现在会警告并点名那几个键，不是静默）。

**改法**：决策 20 改写为「路由表由 `be-ops` 生成期聚合，按**组件是否进外壳**分流到两个出口」：

| 组件形态 | `edge_routes` 产出到哪 | 阶段 |
| --- | --- | --- |
| 被合并进外壳（`local: true`） | **我们那份 shell-compose 的 service `labels`** | 阶段一/二，约 45 个组件 |
| 独立容器 | `brickkit.yaml` 的 `components[].labels` | 阶段一/二，约 7~8 个组件 |
| K8s 全拆 | **带外 Traefik Ingress / IngressRoute 清单** | 阶段三 |

⚠️ **K8s 下 labels 落在 `annotations`，Traefik 不读它** —— 阶段三的路由不走这个口子。那时 `components[].labels` 的用途是 `prometheus.io/*`（配合第 7 章可观测性），不是路由。

**外壳那一侧的两个细节**（be-ops 必须处理，brickKit 管不到）：

1. **router 名全局唯一**：Traefik 的 router name 跨 provider 全局，一个外壳 service 上挂 22 组规则，名字必须带组件前缀去重
2. **必须显式声明 service 端口**：外壳容器同时监听 8080~8087 等多个端口，**Traefik 猜不出该转发到哪个**。每个模块要成套产出三条标签：

```yaml
traefik.http.routers.erp-sales.rule: "PathPrefix(`/erp/sales`)"
traefik.http.routers.erp-sales.service: "erp-sales"
traefik.http.services.erp-sales.loadbalancer.server.port: "8080"
```

这一条 brickKit 的回信里没提，是多端口外壳独有的坑：只写 router 不写 service，Traefik 会在多端口容器上放弃转发。

### A4 · `SET search_path` 少了 `LOCAL` —— 会跨组件串数据且不报错

**位置**：§2.7.2 ①、§13.3 铁律二。

**现状**：「组件连接后执行 `SET search_path TO {schema_name}`」。在**共享连接池**下，连接归还时 `search_path` 不还原，下一个借用者原样继承 → **A 模块的查询打在 B 模块的表上，不报错、不崩，只是悄悄读写了别人的数据**。brickKit 把这条单独标为「最容易踩、也最难查的雷」。

**改法**：全书凡出现处一律改为 `SET LOCAL search_path`（事务结束自动还原），或在 SQL 里全用限定名。

### A5 · schema 名怎么进到组件里

**现状**：书里没交代。而 `bindings[]` 只有 `componentId` / `database` / `envPrefix` 三个字段，**没有 `schema`**；`DATABASE_*` 是保留前缀，`configSchema` 里起同名项会被平台跳过。

**改法**：在每个组件的 `configSchema` 加一项 `pgSchema`（→ 注入 `PG_SCHEMA`），默认值就是它自己的 schema 名。写进 §3.5 骨架和第 11 章。

### A6 · 决策 3 / 82 / 83 自相矛盾 —— 独立 Role 和单一全局池不能并存

**现状**：决策 3/82 要「每组件独立 PG Role 权限墙」，决策 83 要「外壳只创建一个全局 `sql.DB`」。PG 的连接绑死 database **和认证角色**，一个 `sql.DB` 只有一组凭据——8 个账号就是 8 个池，决策 82 声称的「~50 降至 5」达不到。

**改法**：三条决策合并重写为一条，抄 brickKit `组件合并部署` §7.3 的解法：

> 每个**外壳**一个共享登录角色，外壳只建一个全局连接池。借出连接时
> `BEGIN; SET LOCAL ROLE <组件角色>; SET LOCAL search_path TO <组件schema>; ... COMMIT`
> —— 权限墙保住（每组件仍有独立 PG Role），池仍然是一个。
> 组件角色**只用于切换，从不用于登录**，因此不出现在 `brickkit.yaml` 里。

**连带**：`brickkit.yaml` 里是 **5 个 database 资源条目**（一外壳一个登录角色，各带 5 个 `${PASSWORD}` 环境变量），不是 60 个。这一点必须写进 §2.7 和交付 runbook——不然运维会以为要配 60 份凭据。

**代价要写进去**：池共享 = 没有舱壁，一个模块连接泄漏或长事务，**整组一起等**。

### A7 🔄 · §13.4 阶段二：`standalone: true` 不存在

平台没有这个字段，且 `brickkit.yaml` 同样拒绝未知字段。

**改法**：
- 合并 = 给这些组件写 `local: true` + `localPort`（平台不生成容器，并在依赖方容器写 `extra_hosts`）
- 拆分 = **删掉这两行**。比书里写的还简单
- §13.1 那段 compose `aliases` 要删——`extra_hosts` 优先于 DNS 别名，别名不生效，**外壳必须把端口发布到宿主机**
- 🔄 **补一条代价**：`local: true` 的组件上写 `labels` **不生效**（没有可挂标签的对象）。平台会警告并点名那几个键，不是静默失效——但 be-ops 不能把路由标签产出到这些条目上，见 A3
- **新增铁律**：`local: true` 只能配 `deploy.target: docker`，K8s 目标下 CLI 在生成阶段直接报错。所以——

> **合并部署只用于 Docker 单机交付。上 K8s 就是全拆，没有中间态。**

这条和阶段一/二（Docker）→ 阶段三（K8s 全拆）的路线图本来就是一致的，只是没写死。

### A8 · 新增「Fork 铁律」—— 现在完全缺失，而它是 Fork 机制成立的前提

**现状**：§3.4 / §9.4 只说「复制目录、改 remote、把 `source` 指向 Fork 目录」。没说 `metadata.id` 怎么办。如果定制件把 id 改成 `erp/sales-acme`，**所有依赖方的 `ERP_SALES_ENDPOINT` 全部失效**，整条 Fork 机制当场垮掉。

**改法**：新增一节铁律——

> Fork 件的 `component.yaml` 中 `metadata.id` 与 `version` **必须与标准件完全一致**；仓库名、目录名随便改（`erp-sales-acme` 只是目录名）。
> 遮蔽靠 `brickkit.yaml` 的 `sources` **声明顺序**：把 Fork 目录源写在标准源前面，同 id 时靠前的赢。
> 依赖方零感知——Manifest 不动、变量名不动、源码不动。
> 代价：同 id 同版本对应两份不同产物。可接受（全本地源，无市场分发），但**主管理员的「客户 → 组件仓库」映射表因此是唯一真相源**，不是可选项。

这一条验证过，是 brickKit 设计里对我们最友好的一处，值得单独成节。

---

## B 类 · 会在交付现场变成事故

### B1 🔄 · `be-ops` 从 `reserve` 升为 `default`，并明确它的产出

A1/A3/A5/B4 加起来，`be-ops` 是**关键路径上的第 62 个仓库**，而 §5.10 现在把它标成「reserve，运维工具」。

**改法**：§5.10 + 附录 H 改标 `default`，并列出四项产出：

1. **网关路由表（两个出口，见 A3）**：汇总各组件 `assembly.yaml` 的 `edge_routes`
   → 进外壳的 → 我们那份 shell-compose 的 service `labels`（含 router 去重 + 显式 service 端口）
   → 独立容器的 → `brickkit.yaml` 的 `components[].labels`
   → K8s → 带外 Ingress / IngressRoute 清单
2. **数据库建置脚本**：`CREATE SCHEMA` + `CREATE ROLE` + 授权 + 5 个外壳登录角色（平台只会打印 `CREATE DATABASE`）
3. **Feature 清单**：装配结果 → 写进 IAM 适配层的 `config`（见 B2）
4. **外壳合并配置**：哪些组件进哪个外壳、端口分配、迁移执行顺序
5. 附带：`assembly.yaml` 的 schema 校验、slot 互斥校验、`brickkit.yaml` 生成

⚠️ **生成器铁律：labels 的值必须是字符串。** Docker labels 与 K8s annotations 两边都只收字符串，平台**不做自动转换**（转了就得决定 `1.0` 该变成 `"1"` 还是 `"1.0"`）。布尔和数字一律带引号产出：`"true"` / `"8080"`。平台有专门检查会指到行号，但让生成器一次写对更省事。

### B2 · `/api/tenant/features` 的数据来源

平台不给任何组件「当前装配了什么」的视图，manifest 没有 volumes 挂不进 `brickkit.yaml`。

**改法**：`be-ops` 生成 `brickkit.yaml` 时，把启用清单写进 `infra-iam-casdoor` 的 `config.enabledComponents`。

⚠️ **实现细节**（核对过 `internal/inject/inject.go` 的 `formatValue`）：config 值只对 string / bool / 数字做处理，**数组会被 `fmt.Sprint` 渲染成 `[a b c]`，不是 JSON**。所以这一项必须声明为**逗号分隔的字符串**，不要写成数组。

### B3 · 合并态下的迁移，平台不管

`local: true` 的组件**不生成迁移容器 / Job**。外壳一（8 个）、外壳二（14 个）、外壳三（21 个）的迁移全部要外壳自己按序跑。而多模块共用一个库时，**各自的 `schema_migrations` 表必须落在各自 schema 里**，迁移工具默认往 `public` 写，不配就全挤在一起互相顶掉。

**改法**：写进 §13.3（补第五条铁律）和第 11 章。

### B4 · 签名在我们的交付模型下整体不生效

全部走 `type: local` 安装源 → 不受签名约束（`008` §8.5.2，理由是「若一并强制，用本地源开发的项目会当场瘫痪」）。加上外壳镜像是本地构建、不在任何签名覆盖范围内。

**改法**：§9.4 补一节，明确供应链保证改由**本地构建 + git tag + 主管理员映射表 + 交付文档**承担，并写进交付清单：外壳镜像谁构建、怎么校验。**不要让人以为 `requireSignature: true` 在保护我们。**

### B5 · 运维禁令：`brickkit remove` 会删源码

`remove` 自动删除对应源码目录，**含已归档的那一份**。Fork 目录里有未提交改动时，这是数据丢失。

**改法**：交付 runbook 加一条硬禁令——**动 Fork 目录前先 commit & push**；主管理员执行 `remove` 前必须确认目录干净。

---

## C 类 · 口径与补充

| # | 位置 | 改什么 |
| --- | --- | --- |
| C1 | 第 12 章 | 补 `healthCheck.startPeriodSeconds`。平台默认启动预算只有 **30 秒**（10s×3s×3 固定），Python（WeasyPrint / NumPy 预加载）和 Node BFF 大概率超。超了 Docker 下 `up` 失败、**K8s 下永久 CrashLoopBackOff 而容器日志一路正常**。写大没有代价 |
| C2 | §2.7.1 表 | 15 个「基础资源」现在混成一张表。按形态分三类重画：① brickkit `resources`（PG=database、NATS=mq、RustFS/MinIO=storage）② 带外容器（Traefik、Casdoor——平台的 kind 列表是封闭的，这两个没有对应 kind，声明不出来）③ 真组件（infra-storage、infra-attachment…） |
| C3 | §9.5 组件级定制 | 「Acme 只装 5-10 个组件」要补一句：`brickkit add erp/sales` 会**递归拉下整棵强依赖树**（mdm-customer、mdm-product、erp-inventory、erp-finance）。选配粒度受依赖图约束，销售口径要对齐 |
| C8 🔄 | 交付 runbook | K8s 下 labels 落在 Deployment **与 Pod 模板**的 `annotations`（`prometheus.io/*` 抓的是 Pod，只写 Deployment 等于没写）。连带后果：**改一条路由或抓取规则会触发一次滚动重启**。写进变更流程 |
| C9 🔄 | §7 可观测性 | 平台的 labels 透传给了「不装 OTel Collector 时怎么被抓」一条新路：`prometheus.io/scrape` / `port` 直接写在 `component.yaml deployment.labels` 里，由组件作者声明（他才知道自己在哪个端口暴露指标）。§7.5 可以补这一段 |
| C4 | 决策 4 + 术语表 | 「废弃前端组件化，拥抱项目制大仓」「项目制大仓 = 前端按客户建立的 Monorepo」是上一代想法的残留，与 §2.3 / 决策 74「前端是可替换的组件」冲突。删掉残留，保留「前端是一个组件，其仓库内部是 monorepo 结构」这一层意思 |
| C5 | §5.1 表 | `infra-bff-mobile` 标 `default`，但前端的依赖里没有它，也没人强依赖它。要么补上依赖边，要么改标 `optional` |
| C6 | 第 11 章 | 归档用的 `archive` schema 与「一组件一 schema」的关系要说清：是 `erp_sales_archive` 还是共用一个 `archive`？跨 schema 权限怎么给（权限墙不能被归档打穿） |
| C7 | 全书 | 凡出现「brickKit 会…」「`brickkit up` 会…」的句子，逐句核对是否属实。这次找到 8 处，不保证没有第 9 处 |

---

## D · 待实测（文档没写清，需要跑一遍确认）

1. **`brickkit sync` 对 `local: true` 组件的归档行为**。合并交付态下 45 个组件标 `local: true`，它们在启停判定里算「启动」，`sync` 应该不归档——但文档没明说。跑一次确认，结论写进 runbook。
2. **`local: true` 组件的依赖端口映射**（`005` §4.8：CLI 为 local 组件的依赖自动映射宿主机端口）。5 个外壳互相调用时，这套映射够不够用、会不会撞宿主机端口。
3. **60 个组件同绑一个 `database`** 时 `brickkit up` 的输出（应该只打印一条 `CREATE DATABASE "brickkit_db"`）。已读实现确认会归集去重，但跑一遍看实际提示文案。

---

## E · 改动优先级

| 批次 | 内容 | 理由 |
| --- | --- | --- |
| **第一批（动手前必须做完）** | A1、A2、A5、A8、**A6** 🔄 | 决定组件仓库长什么样，以及**库怎么建**。晚一天改就多一批组件返工；A6 更急——库按 database 建好、数据进去之后再改成一库多 schema，**就是一次数据迁移**（brickKit `006` §9.5 新增的时序性提醒） |
| **第二批（第一条链跑通前）** | A3、A4、A7、B1、B2 | 决定 `be-ops` 长什么样 |
| **第三批（首次交付前）** | B3、B4、B5、C1、C2 | 交付现场才会炸的那些 |
| **随时** | C3~C7、D | 口径与验证 |

**建议做法**：不要一次性改完 1947 行。先按第一批改完 §3.5 / §3.6 / §5.11 / 附录 H，然后**只做一条链**——`mdm-customer` + `erp-sales` + `erp-inventory` + `frontend-standard` + 带外网关 + IAM，跑通 `brickkit up`，把 `be-ops` 写出来。这条链会把上面 A/B 两类里的绝大多数逼到台面上，成本比现在纸上补文档低得多。


---

## F · 落地记录（2026-09-02）

设计书 `git diff`：**597 增 / 210 删**，1947 → 2334 行。

| 项 | 落在设计书哪里 |
| --- | --- |
| A1 | §3.5 整节重写为「组件的两份 yaml」：3.5.1 后端两份骨架、3.5.2 前端两份、3.5.3 语义字段对照表 |
| A2 | §3.3 加装配角色说明、§3.4 加"基础资源级替换"、§5.1 表删 5 行 + 说明、§5.11 重写为"先判是不是组件"、§5.13 计数、§6.2、附录 H 重排 63 行 |
| A3 | §6.3 重写 + 新增 6.3.1「路由表的两个出口」/ 6.3.2「外壳侧两个坑」、§2.7.2 ③、决策 20 |
| A4 | §2.7.2 ① 新增「连接与切换」行、§13.3 铁律二、决策 3 |
| A5 | §3.5.1 `configSchema.pgSchema`、§3.5.3 对照表 |
| A6 | §13.3 铁律二整段重写（共享登录角色 + `SET LOCAL ROLE`）、§2.7.2 ①「初始化」「时序性」两行、决策 3（82/83 并入） |
| A7 | §13.1 机制三重写（`local: true` + `extra_hosts`，删 aliases）、§13.4 阶段表加"部署目标"列 + K8s 铁律 + 阶段二五步、§13.6 |
| A8 | 新增 §3.4.1「Fork 铁律」、决策 85、术语表 |
| B1 | §5.10 新增「be-ops：平台明确不做的活全在这里」五项产出表 + 生成器铁律、附录 H #74、决策 89 |
| B2 | §6.1 新增「`/api/tenant/features` 的数据从哪来」 |
| B3 | §13.3 新增铁律五、§11.2.2.1 迁移状态表 |
| B4 | 新增 §9.4.1「签名整体不生效」 |
| B5 | 新增 §9.4.2「运维禁令」 |
| C1 | §12.3 新增第 5/6/7 条（冷启动预算、健康检查禁令、镜像里要有 wget/curl） |
| C2 | 新增 §2.7.0「三种形态，先分清楚」+ §2.7.1 加"形态"列 + 附录 G 加"形态/声明为"两列 |
| C3 | §9.5 组件级加两条 ⚠️（强依赖树递归、收窄范围只能改 `enabled`） |
| C4 | 决策 4 重写、术语表「项目制大仓」→「前端仓库内 monorepo」 |
| C6 | §11.5.4 归档 schema 改为 `{组件schema}_archive` + 权限墙说明 |
| C8 | §7.5.1 K8s 滚动重启提醒 |
| C9 | 新增 §7.5.1「不装 Collector 时的另一条路：被动抓取」 |
| 顺带 | 两处 mermaid 的 `role:gateway` → `网关（带外容器，不是组件）`；术语表新增 11 条 |

**C5（`infra-bff-mobile` 的装配角色）没做** —— 它需要先决定 BFF 到底是不是 `default`，那是业务判断不是口径问题，留给你定。

**D 类 3 项仍未完成**，需要真跑一遍才能确认，不能靠读文档：

1. `brickkit sync` 对 `local: true` 组件的归档行为
2. `local: true` 组件的依赖端口映射（5 个外壳互调时够不够用、会不会撞宿主机端口）
3. 60 个组件同绑一个 `database` 时 `brickkit up` 的实际提示文案
