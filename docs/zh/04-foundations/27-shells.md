[English](../../en/04-foundations/27-shells.md) · [中文](27-shells.md)

# 外壳

N 个组件要共用一个进程而互不察觉，需要什么：一个外壳能装哪些成员，进程里共用什么、绝不共用什么，以及每个 SDK 功能在被称为"合并安全"之前要过的核对表。读者是要改外壳、改 SDK 的外壳启动器，或者要给 SDK 加进程级功能的人。

## 范围

- 哪些组件可以合并进一个外壳（同一种语言）；
- 外壳不变量：进程级的四样东西，以及其余一切都按成员；
- 合并安全核对表，逐项列出，每项配上证明它的测试；
- 什么时候不该用外壳。

不在本文：外壳仓库怎么布局、发布、钉版本（[0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)、`brickkit-component` 技能）；部署文件怎么选择外壳承载哪些成员（`brickkit-deploy` 技能）；模块代码要守的规则（[02-backend.md](../01-conventions/02-backend.md#合并安全)）。

## 选择

**一个外壳只合并同一种语言写的组件。** 每个组件可以用自己的语言写：进项目靠的是语言中立的组件协议和它的黑盒一致性套件（[02-languages-and-component-protocol.md](02-languages-and-component-protocol.md)）。合并是另一回事：外壳把成员的代码编译进一个进程、一个运行时，所以只有当一种语言既有官方 SDK、**又有**该 SDK 的外壳启动器时，才有这种语言的外壳。用别的语言写的组件可以进项目、通过一致性测试、单独运行；等它的语言两样都有了，才能合并。今天：Go 外壳 `be/go-core`、`be/go-infra`、`be/go-backoffice`；一个 Python 外壳 `be/py-render`；TypeScript 没有外壳启动器，所以 BFF 单独运行。

**外壳只把 N 个进程变成一个**（原则二）。它不加路由、不加逻辑、不在成员之间加调用；成员之间照样经各自端口上真实的 HTTP 或 gRPC 互相调用（[0101](../02-decisions/01-architecture/0101-no-imports-between-components.md)）。启动器是 SDK 代码；外壳仓库就是一份成员清单（[0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)）。

**四条外壳不变量：**

1. **进程级的东西恰好四样**：OpenTelemetry 导出器与传播器（共享的导出器只由启动器在所有成员都停下之后关闭；停掉一个成员只冲刷它自己的 span 队列）；权限 bundle 与 token 验签器（JWKS）；物理数据库连接池；事件总线连接。
2. **其余一切都按成员**：配置、logger、tracer 与 meter provider、指标 registry、HTTP 与 gRPC 服务端、出站连接、缓存、后台任务、授权投影、advisory 锁的键。
3. **每个成员有自己的资源预算**：数据库连接、出站并发、缓存内存。一个成员耗尽预算，绝不会饿死另一个。
4. **两种形态下监督行为相同**：外壳里成员失败的后台任务按退避重启，和单跑时完全一样；成员绝不停掉或退出整个进程。

每个成员单独跑，和合并在一起跑，行为必须一致；`brickkit up --ignore-shells` 就是检查这一点的办法。

**状态**：已在用：每个外壳一个仓库、一份成员清单，每个进程一份 bundle 和验签器，每个成员一个指标 registry，成员在自己的端口上、有自己的 gRPC 服务端，事务级的角色切换。已定（随 3.0.0 统一升级及配套的 SDK 版本）：每成员的连接预算、每成员的 tracer provider、汇总的 `/metrics`、SDK 的任务监督者、每成员的出站连接、一次报出全部配置错误。今天外壳里所有 span 都带外壳的名字，连接池对所有成员共享且无上限（Go）或所有人共用 10 条（Python），成员的循环失败后一直停着。

## 端口契约

外壳启动器是每个官方 SDK 的一部分。不论哪种语言，它承诺：

- **输入。** brickKit 传入 `BRICKKIT_SERVED_MEMBERS` 和 `BRICKKIT_SERVED_MEMBERS_CONFIG`（一个 JSON 值）。启动器恰好启动列出的成员，每个只拿到自己的配置键；列出的成员没有编译进来或编译进来的版本不同、某个成员的 `PG_HOST`、`PG_PORT`、`PG_DATABASE`、`EVENT_BUS_URL`、`AUTHZ_URL`、`IAM_*` 或 `TENANT_ID` 与外壳的不同（这几项撑着那四样进程级共享的东西）、或者任何成员的配置非法（全部错误一起报出）时，拒绝启动，并点名是哪个成员。
- **端口。** 每个成员在自己的 HTTP 端口和自己的 `extraPorts` 上监听，有自己的 gRPC 服务端和拦截器链。地址按成员自己的服务名解析，brickKit 把它做成外壳的别名（[04-configuration.md](../01-conventions/04-configuration.md#依赖地址)）。
- **数据库。** 外壳要求 PostgreSQL 16 及以上；单独运行的组件仍以 14 为下限。外壳用它自己的 `PG_USER` 登录，这个登录角色以 `WITH INHERIT FALSE, SET TRUE` 被授予每个成员的运行期角色，因此不持有它们的任何权限。每个事务用 `SET LOCAL ROLE` 切到该成员自己的运行期 `PG_USER`（取自成员的配置，绝不由 schema 名推导；绝不切到属主角色，外壳从不被授予属主角色），把事务内的 `search_path` 设为该成员的 `PG_SCHEMA`，并用 `SET LOCAL application_name` 设为该成员的 ID，让 `pg_stat_activity` 能按成员数连接。成员之间的隔离是 SDK 的职责，不是数据库的：只有运行时的 store 发 `SET LOCAL ROLE`，成员代码从不发 `SET ROLE`（门禁 `identity-literal-scan`）。物理池大小是外壳的 `PG_POOL_MAX`；每个成员经一个容量为它自己 `PG_POOL_MAX` 的限额取连接，预算用尽时怎么办见 [03-database.md](03-database.md)。
- **advisory 锁**只用事务级的，键由「成员 schema 加锁名」的哈希和锁的各部分的哈希组成，两个成员绝不会争同一个键（[10-local-transactions.md](10-local-transactions.md)）。
- **遥测。** 每个成员一个 tracer 和 meter provider，`service.name` = 成员的组件 ID；每一处埋点（HTTP 与 gRPC 的服务端和客户端、出站 HTTP、消费者）都显式拿到该成员的 provider 和传播器，从不用 OpenTelemetry 的进程全局对象；全局 tracer provider 只作兜底，带外壳自己的 ID，所以出现这个名字的 span 就说明有埋点漏了；共用一个导出器，只由启动器在所有成员都停下之后关闭；外壳端口上一个汇总的 `/metrics`，每个成员带一个 `component` 标签（[23-observability.md](23-observability.md)）。
- **健康检查。** `/healthz` 只报告进程活着；一个成员的下游抖动不能让所有成员一起重启（[02-backend.md](../01-conventions/02-backend.md#健康检查与镜像)）。
- **迁移**在外壳启动之前，从每个成员自己的镜像里跑，绝不在外壳里跑，各自以该成员自己的属主凭据（`PG_OWNER_USER` / `PG_OWNER_PASSWORD`，[08-schema-evolution.md](08-schema-evolution.md#迁移入口)）登录；外壳的登录角色从不被授予属主角色。

**合并安全核对表。** SDK 的每个功能，涉及到哪一项就在这里核对，过了才能叫"合并安全"。

| 项 | 外壳里的风险 | 怎么保证安全 | 由什么证明 |
|---|---|---|---|
| 事务身份 | 不带 `LOCAL` 的 `SET` 泄漏给下一个借连接的 | `SET LOCAL ROLE`、`search_path` 和 `application_name`；store 绑定成员身份；成员代码禁止 `SET ROLE` | 已有测试、store 一致性套件 |
| 事务超时 | `SET ROLE` 之后，成员角色上的 `ALTER ROLE … SET` 不生效 | 每个事务用 `SET LOCAL` 设超时 | store 一致性套件 |
| 连接池 | 一个无上限的共享池；一个成员就能把它吃光 | 池由外壳定大小，每个成员一份预算 | "一个成员预算耗尽不影响另一个" |
| advisory 锁 | 同名键在成员之间相撞；会话级锁泄漏 | 键里含成员 ID；只用事务级 | "两个成员的锁互不阻塞" |
| 事务内不走网络 | — | "在事务里"的标记随调用链传递，与进程无关 | "事务内发起 gRPC 被拒" |
| gRPC 客户端 | 进程级的连接池让 `be-caller` 变成别的成员 | 出站连接归成员 | "外壳里 `be-caller` 是发起调用的成员" |
| gRPC 服务端 | — | 每个成员一个服务端、一条拦截器链 | 已在用 |
| HTTP 服务端 | 没有超时 | 统一设置 read-header、read、write、idle 超时，单跑时相同 | 服务端超时测试 |
| 截止时间与重试预算 | 一个成员的重试风暴耗尽别人的预算 | 预算按出站连接计，连接按成员分（[16-deadlines-and-retries.md](16-deadlines-and-retries.md)） | rpc 一致性套件 |
| NATS 连接 | 一条连接；长时间断线后全体失联 | 一条连接，无限重连；durable 和订阅名带成员 ID（[12-event-bus.md](12-event-bus.md)） | 两个成员的消费测试 |
| outbox 推送泵 | N 个成员空闲时每秒各轮询 5 次 | 自适应轮询 | 空闲推送泵测试 |
| 事件游标、幂等表 | — | 在成员自己的 schema 里 | 已定 |
| 任务租约与时间槽 | 同一个组件的外壳实例和单跑实例重复干活 | 表在成员 schema 里，跨进程协调（[19-background-jobs.md](19-background-jobs.md)） | jobs 一致性套件 |
| 后台任务失败 | 外壳里永久停止，单跑时重启进程 | SDK 监督者，两种形态一样 | "成员失败的任务被重启"（今天是红的） |
| 缓存 | 包级 map 被成员共享 | 缓存按成员创建，加全局 map 门禁（[17-caching.md](17-caching.md)） | cache 一致性套件 |
| trace | 所有 span 都挂在外壳名下；一个成员停下就关掉了共享导出器 | 每个成员一个 tracer 和 meter provider，连同传播器显式传入；只有启动器关闭导出器 | "每个成员的 span 带自己的 `service.name`"（今天是红的） |
| 日志 | SDK 用进程默认 logger 记日志，丢了成员 ID | SDK 只经成员的 logger 记日志 | "消费失败的日志带成员 ID" |
| 指标 | 默认 registry 在第二个成员上 panic | 每个成员一个 registry，汇总时加 `component` 标签 | 已在用，加汇总测试 |
| bundle 与 JWKS | — | 每个进程一份（不变量 1）；授权投影按成员，在它自己的 schema 里（[20-authorization-provider.md](20-authorization-provider.md)） | 已在用 |
| 边缘路由与共享地址 | 指向外壳名，外壳每发一版就失效 | 一律用成员自己的服务名（[0107](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)） | 边缘路由测试、`service-hostname-scan` |
| 爆炸半径 | 外壳一重启，所有成员同时不可用 | durable 消费者保留进度；reconciler 推进进行中的流程；重试预算吸收这段空档 | 组装后外壳的真机测试 |

## 备选方案

| | 长处 | 短处 |
|---|---|---|
| 每个组件一个进程（不用外壳） | 完全隔离、可以分别扩容 | 每个组件一个运行时：单机上吃内存 |
| 同语言外壳，成员在各自端口上（选用） | N 个成员一个运行时；调用方无感知 | 成员一起扩容、一起出故障 |
| 一个容器里多个进程（进程管理器） | 一个镜像 | 内存一点没省；把崩溃藏起来，平台看不见 |
| 合并时改成进程内函数调用 | 少了网络跳数 | 打破"每个组件能单独运行"；这个组件再也不能单独部署 |
| 混合语言的外壳（嵌入解释器、cgo 或 FFI 桥） | 容器更少 | 一个进程两个运行时、两份进程级状态、每对语言一个启动器 |
| JVM 组件用 GraalVM native image | 不合并也能降低 JVM 内存 | 每个组件都要额外的构建工作；重度反射的框架要配置 |
| 不需要的组件 `mode: disable` | 零成本 | 只适用于真的不用的组件 |

## 为什么选它

- 客户在单机上部署；运行时的内存底线基本按进程固定，N 个成员共用一个运行时就省下了大部分（brickKit 的外壳理由）。
- 调用方和成员代码都无感知：成员在自己的端口上监听、按自己的名字被访问，所以合并和拆开都只是部署时的决定。
- 每个外壳一种语言，就是一个运行时、一个 SDK 版本（所有成员解析到同一个 SDK 版本）、一个启动器，四条不变量才能在代码里强制。

## 为什么不选其他

- **进程内调用**：组件再也不能单独运行，这是原则一；[0101](../02-decisions/01-architecture/0101-no-imports-between-components.md) 禁止。
- **一个容器里多个进程**：内存没有共享，什么都没省下，平台还看不出哪个组件崩了。
- **混合语言外壳**：一个进程里两个运行时、两份进程级状态，正是这些不变量要防止的失败。

## 什么时候换

满足下面任一条时，组件单独运行，或者放进它自己的外壳，而不是放进共享外壳：

- 它必须单独扩容（热点读路径、CPU 密集的渲染器）；
- 它的故障不能拖垮邻居；
- 它的资源画像和邻居差别很大（内存很重、在 Python 单事件循环上跑很长的 CPU 密集任务）；
- 内存不是约束（按独立 Pod 规划的 Kubernetes 集群）。

没有外壳启动器的语言写的组件，永远单独运行；JVM 语言每个进程明显更吃内存，选它之前要权衡这一点。

## 怎么换

- 外壳承载哪些已编译进来的成员，在部署文件里外壳条目下的 `members:` 选；把一个成员移出来就是改部署文件，然后 `brickkit up`。
- 往外壳里加成员，或者把成员换到新版本，是外壳自己仓库里的一次提交和发布，然后在这里更新子模块指针并 `brickkit upgrade be/<name>@<version>`（[0108](../02-decisions/01-architecture/0108-one-repository-per-shell.md)）。
- `brickkit up --ignore-shells` 让每个成员单独运行；外壳的任何改动之后都用它做拆回检查（[01-development-workflow.md](../01-conventions/01-development-workflow.md#真机运行)）。
- 新语言的外壳随该语言的官方 SDK 和启动器一起到来，绝不随某一个组件到来。

## 一致性测试

- 上面核对表里的每一条红测试，在每个有启动器的官方 SDK 里都要有。
- 组件协议套件里（[02-languages-and-component-protocol.md](02-languages-and-component-protocol.md)）：一个夹具组件分别单独运行和在外壳里运行，黑盒结果完全相同。
- 门禁：`make module-check`（模块代码不读进程环境、不做进程级初始化、不退出进程）；外壳成员检查（注册的成员 = `shell.members` = 模块依赖声明）；`service-hostname-scan`。
- 组装后真机：`be/go-core` 里 sales → inventory 的 `Reserve` 走回环 gRPC，记下的操作人是发起确认的用户；然后 `brickkit up --ignore-shells` 得到相同结果。

## 相关决策

- [0105 任何语言，一份协议](../02-decisions/01-architecture/0105-any-language-one-protocol.md)：每个组件自选语言；外壳只合并同一门、有官方 SDK 和启动器的语言的成员；JVM 的内存开销是文档里的提醒。
- [0109 规则写在语言中立的组件协议里，由黑盒套件检查](../02-decisions/01-architecture/0109-language-neutral-component-protocol.md)：组件协议，包括外壳成员的义务。
- [0108 一个外壳、一个仓库、一个镜像、一份成员清单](../02-decisions/01-architecture/0108-one-repository-per-shell.md)：还有每个外壳一个 SDK 版本，以及启动器在启动时的核对。
- [0508 后台工作只经 SDK 的 Jobs](../02-decisions/05-runtime/0508-background-work-only-through-jobs.md)：单跑和外壳里的监督方式相同。
- [0101 组件之间禁止 import](../02-decisions/01-architecture/0101-no-imports-between-components.md)
- [0102 一个数据库，每个组件一个 schema](../02-decisions/01-architecture/0102-one-schema-per-component.md)
- [0103 每种语言内部一套锁定的技术栈](../02-decisions/01-architecture/0103-locked-stack-per-language.md)：让每成员不变量能在代码里落实。
- [0107 授权与身份经共享变量访问，从不经依赖](../02-decisions/01-architecture/0107-authz-and-iam-addresses-are-shared-vars.md)

## 已知限制

- 外壳里的成员一起扩容、一起出故障；一个成员把进程搞崩，就带走所有成员。
- 一个外壳的所有成员用同一个 SDK 版本；某个成员需要更新的 SDK，就得整个外壳一起动。
- 每成员的内存只是计算，不是强制：操作系统看到的是一个进程。
- Python 成员共用一个事件循环；一个 CPU 密集的成员会拖慢其他成员。
- 没有启动器的语言写的组件完全不能合并，只能单独运行。
