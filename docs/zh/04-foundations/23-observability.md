[English](../../en/04-foundations/23-observability.md) · [中文](23-observability.md)

# 可观测性

一个请求怎么跨组件追踪，每个组件怎么报指标和日志，以及审计日志和应用日志有什么不同。读者是要动链路追踪、指标、日志字段或级别、可观测性栈或审计的人。

## 范围

- trace 上下文在 HTTP、gRPC 和事件上的传播；
- 每个信号都带的身份（哪个组件、哪个版本、哪个实例），单跑和外壳里都一样；
- 指标：暴露方式、标签、外壳的汇总端点；
- 应用日志：格式、字段、级别、哪种错误记什么级别、脱敏；
- 关联 id：request id、trace id、causation id；
- 审计日志：它是业务数据，走另一条路；
- 可观测性栈，以及怎么换。

不在本文：看板、告警规则和值班流程（计划中的 `05-operations/`）；任务指标本身（[19-background-jobs.md](19-background-jobs.md)）。

## 选择

- **OpenTelemetry** 做 trace，OTel metrics API 接到同一个 Prometheus registry；每一跳都用 **W3C Trace Context 和 Baggage**。
- **指标用 Prometheus 拉取**，不开 collector 也能看；每条序列都带 `component` 标签；外壳暴露一个汇总的 `/metrics`。
- **日志是 stdout 上的 JSON 行**，别无其他；collector 从容器运行时取日志送进 Loki。
- **每个成员有自己的遥测身份**：外壳里 `service.name` 是成员的组件 ID，绝不是外壳的名字。
- **日志级别由 SDK 按错误的状态决定**，不由各组件自己定。
- **审计走 outbox** 到 `infra/audit`，与业务写入在同一个事务里。
- **后端中立**：OTLP 就是端口；Tempo、Loki、Prometheus、Grafana 是默认栈，镜像全部钉到确切版本。

**状态**：已在用：stdout JSON 日志带 `component_id`、`trace_id`、`span_id`；每个模块一个 Prometheus registry，有 `http_requests_total` 和 `http_request_duration_seconds`；OTLP 导出到 `OTEL_BASE_URL`（为空即关闭）。已定（随 3.0.0 统一升级及配套的 SDK 版本）：传播（今天每一跳都开一个新的根 trace）、每成员的 resource、`component` 标签与外壳汇总端点、`LOG_LEVEL`、由 SDK 决定日志级别、每个 SDK 自动脱敏、审计路径、进 Loki 的日志管道、钉版本的镜像。

## 端口契约

**传播。**

| 一跳 | 载体 | 规则 |
|---|---|---|
| HTTP 入站 | `traceparent`、`tracestate`、`baggage` 头 | 提取；服务端 span 是调用方 span 的子 span。入站 `traceparent` 的采样标志为 0 时照样传播（保留 trace ID，子 span 也不采样），但它的 span 既不记录也不导出；`trace_id` 仍然出现在日志和 problem 体里 |
| HTTP 出站（用户面，见 [15-user-api-and-errors.md](15-user-api-and-errors.md)） | 同样的头，再加 `X-Request-Id` | 注入 |
| gRPC 入站与出站（[14-system-rpc.md](14-system-rpc.md)） | metadata 里同样的键 | 每次调用都提取、注入 |
| 发布事件 | 信封里的 trace 上下文（[13-event-contracts.md](13-event-contracts.md)） | 生产者的 span 上下文写进消息 |
| 消费事件 | — | 消费方开一个**新 trace，用 span link 指向生产者的 span**，而不是作为它的子 span（OpenTelemetry messaging 约定）：否则很长的异步链会长成一棵没有上限的 trace |

传播器和 OTLP 导出器是遥测里仅有的进程级的东西。两者都归平台一侧（单独运行时的启动器，或外壳）所有，从不归模块：模块既不安装它们，也不关闭它们。每一处埋点（HTTP 服务端、gRPC 服务端和客户端、出站 HTTP、消费者）都显式拿到本成员的 tracer provider、meter provider 和传播器，从不用进程全局的。全局 tracer provider 只是兜底，它的 `service.name` 是外壳自己的 ID，所以带这个名字的 span 就暴露出一处漏掉的埋点。

**关联。** `X-Request-Id` 是客户端能看到、能报给我们的 id。请求进来没带它时，第一个服务把它设为 trace id。出站调用时继续往下传。每条日志都带 `trace_id`；事件带 `ce-causationid`（[13-event-contracts.md](13-event-contracts.md)）。

**resource 属性**，每个成员一份：`service.name` = 组件 ID（`erp/sales`）、`service.version` = 组件版本、`service.namespace` = 组件所属的领域（组件 ID 的第一段，`erp`）、`service.instance.id` = 容器或 Pod、`deployment.environment.name` = `DEPLOY_ENV`（默认 `dev`；OpenTelemetry 语义约定 1.27 起的名字，以前叫 `deployment.environment`）。外壳里每个成员有自己的 tracer provider 和 meter provider，带这些属性；导出器共用，只由外壳在所有成员都停下之后关闭。停掉一个成员只冲刷这个成员自己的 span 队列。

**导出。** OTLP 发往 `OTEL_BASE_URL`（[04-configuration.md](../01-conventions/04-configuration.md#共享连接键)）。为空表示不导出、也不报错；组件照常运行。

**指标。**

- 成员 HTTP 端口上的 `/metrics`，Prometheus 文本格式。
- 每条序列都带常量标签 `component=<组件 ID>`，单跑时也带，所以同一条查询在两种形态下都能用。
- 外壳在自己的端口上提供一个汇总的 `/metrics`，合并每个成员的 registry，每个都包上它的 `component` 标签；抓取目标是外壳，每个容器一个端口。
- RED 指标用协议名：`be_http_server_requests_total` 和 `be_http_server_duration_seconds`（标签 `method`、路由模板 `route`、数字形式的 `status_code`），以及 `be_grpc_server_handled_total` / `be_grpc_server_duration_seconds` 和客户端那一对。2.x 的名字 `http_requests_total`、`http_request_duration_seconds` 不保留（3.0.0 是一次性重建）。
- 协议定义的指标以 `be_` 开头，所以任何语言写的组件发出的名字都相同；组件自己的指标以它的 domain 和 name 开头。

**日志。** stdout 上每行一个 JSON 对象。

| 字段 | 内容 |
|---|---|
| `time` | RFC 3339 UTC |
| `level` | `debug`、`info`、`warn`、`error` |
| `msg` | 事件名或一句话 |
| `component_id`、`component_version` | 组件，外壳里是成员自己的值 |
| `trace_id`、`span_id` | 取自当前 span |
| `request_id` | 这一行属于某个请求时 |
| 访问日志还带 | `sub` 和 `perm`（路由要求的权限键），被拒的请求能追到人和键；在守卫运行之前就回答的 413 两者都不带 |

- **访问日志**只覆盖用户平面和资源契约。运维端点（`/healthz`、`/readyz`、`/metrics`、`/_be/info`）不记；运行时可以（MAY）以 debug 级别记它们。访问日志行的级别按状态码定：500（`INTERNAL`、`UNKNOWN`、`DATA_LOSS`）是 ERROR，503 和 504（`UNAVAILABLE`、`DEADLINE_EXCEEDED`）是 WARN，其余一切（2xx、3xx、4xx、499、501）是 INFO。

- **级别**：键 `LOG_LEVEL`（`debug|info|warn|error`，默认 `info`），外壳里按成员各自生效。
- **一个错误记什么级别**，由 SDK 在它的 HTTP 和 gRPC 错误映射里决定，不由各组件自己定：

| 状态（gRPC / HTTP） | 级别 |
|---|---|
| `INTERNAL`、`UNKNOWN`、`DATA_LOSS` / 500 | ERROR |
| `UNAVAILABLE`、`DEADLINE_EXCEEDED` / 503、504 | WARN |
| `CANCELLED`（`REQUEST_CANCELLED`），包括停机时的取消 | 不按错误记；它的访问日志行是 INFO |
| 调用方的错误：`INVALID_ARGUMENT`、`NOT_FOUND`、`PERMISSION_DENIED`、`FAILED_PRECONDITION` …… / 4xx | INFO |

  ERROR 表示运维必须处理。调用方的错误永远不是 ERROR。
- **脱敏**在每个 SDK 的日志处理器里自动完成，从不由业务代码做，用共享向量 `redaction` 校验，所有语言脱敏结果一致：
  - 受保护的名字：`phone`、`mobile`、`id_card`、`password`、`bank_card`、`email`、`token`、`secret`、`authorization`、`cookie`、`set-cookie`、`api_key`；
  - 字段名先拆成词：按 camelCase 拆，`_`、`-`、`.` 都当分隔符，转小写。受保护名字的词在其中作为一段连续的完整词出现时就算匹配（最后一个词可带复数 `s`）：`phone_number`、`accessToken`、`user.email` 匹配；`telephone`、`tokenizer` 不匹配；
  - 匹配字段的值，不论什么类型，都换成字符串 `"[REDACTED]"`，不再往里走；值从不被扫描，所以个人数据绝不写进自由文本；信封字段从不改动；
  - 一行最多 2048 字节，含行尾换行符，并且始终是一个合法的 JSON 对象。信封字段永不截断：`time`、`level`、`msg`、`component_id`、`component_version`、`trace_id`、`span_id`、`request_id`、`truncated`。其余字符串值都可以截断，最长的先截，在字符边界上截，结尾加 `…[TRUNCATED]`。
- 组件不自己经网络发日志；stdout 是唯一出口。collector 读容器日志（Docker 上用文件日志 receiver，Kubernetes 上用其日志管道），转给 Loki。

**审计日志**不是应用日志：

| | 应用日志 | 审计日志 |
|---|---|---|
| 给谁 | 排障的运维 | 业务、审计人员、租户管理员 |
| 内容 | 有用的都可以写，可以采样 | 谁、何时、对什么、做了什么动作、前后各是什么值；有人代表别人操作时记完整的 `act` 链 |
| 路径 | stdout → collector → Loki | outbox 里的一条事件，与业务变更同一个事务写入，subject 为 `audit.<domain>.<name>.<action>.v1`；`infra/audit` 存进只追加、哈希链式的表 |
| 保留 | 14 到 30 天 | 默认 3 年，可配，不低于法定下限 6 个月 |
| 个人数据 | 脱敏 | 字段级 diff 按字段键掩码（[20-authorization-provider.md](20-authorization-provider.md)） |

回滚的事务不留审计记录；提交的事务一定有。

## 备选方案

| | 长处 | 短处 |
|---|---|---|
| OTel trace + Prometheus 拉取 + stdout 日志经 collector（选用） | 厂商中立；不开 collector 也能看指标；写日志从不卡在网络上 | 三种信号，三条路径 |
| 只用 Prometheus 拉取，不做 trace | 最简单 | 无法跨组件跟踪一个请求 |
| 所有信号都走 OTLP 推送 | 一条管道 | 没有 collector 就什么都看不到；外壳推送指标照样需要每成员的 resource |
| SDK 直接把日志发到 Loki | 日志不需要 collector | 网络一抖，请求路径上的日志就阻塞或丢失 |
| 厂商 SDK（Datadog、阿里云 ARMS、腾讯云 APM） | 开箱功能多 | 每个组件、每种语言都绑定一个厂商 |
| 其他 OTLP 后端（SigNoz、OpenObserve、任何接收 OTLP 的厂商） | 同一个协议后面的完整栈 | 不是代码层面的选择：它们替换的是默认后端，见**怎么换** |

## 为什么选它

- 代码层面厂商中立：每个官方 SDK 都讲 OTLP 和 Prometheus，后端是部署时的决定。
- 指标不需要 collector，日志不依赖网络，适合资源有限的单机。
- 每成员的身份让外壳在 Tempo、Prometheus、Loki 里看起来和成员单跑完全一样。
- 级别集中决定，ERROR 才有意义：状态到级别的映射只在一处，每个组件记法一致。
- 审计走 outbox，审计记录与它描述的数据一致程度完全相同。

## 为什么不选其他

- **不做 trace**：一次跨 sales、inventory、finance 的慢确认订单跟不下去。
- **只推送指标**：collector 配错了，一切都看不见。
- **SDK 直接发日志到 Loki**：写日志进了请求路径，会随网络一起失败。
- **厂商 SDK**：每种语言、每个厂商一套，客户用的是别的平台就用不上。

## 什么时候换

客户已有一个接收 OTLP 的可观测平台（SigNoz、OpenObserve、云 APM、Datadog）：换后端，组件不动。

## 怎么换

1. 改 OpenTelemetry Collector 的 exporter（平台自己采日志时也改它的日志 receiver）；平台提供了 collector 的话，把 `OTEL_BASE_URL` 指过去。
2. 保留 Prometheus 抓取，或者让 collector 抓 `/metrics` 再转发。
3. 组件、SDK、版本钉都不改。

## 一致性测试

套件 `tools/be-acceptance/conformance/telemetry/`（已定），对每个官方 SDK 跑：

- 入站 `traceparent` 被继承，出站用户面调用注入它；
- gRPC 客户端和服务端在同一个 trace 里；
- 事件消费方的 span 链接到生产者的 span；
- 外壳里两个成员的 span 带不同的 `service.name`；走完一条 HTTP → gRPC → 事件的链路后，没有任何 span 带外壳自己的 ID；停掉一个成员，不会丢掉另一个成员之后发出的 span；
- 外壳汇总的 `/metrics` 带 `component` 标签，且没有任何 collector 被注册两次；
- `LOG_LEVEL=warn` 时 info 行不输出；
- 级别映射：调用方错误记 INFO，内部错误记 ERROR，取消不记；
- 脱敏向量在每个 SDK 里输出相同；
- 组件协议套件的 `obs` profile 从外面对每个组件检查同样的事：`CP-OBS-01`（入站 `traceparent` 成为服务端 span 的父）、`CP-OBS-02`（日志字段、按错误码定级别）、`CP-OBS-03`（`/metrics` 的名字和标签）、`CP-OBS-04`（脱敏）、`CP-OBS-05`（`LOG_LEVEL`）；外壳里是 `CP-SHELL-04`、`CP-SHELL-09`、`CP-SHELL-10`；
- 审计事件存在，当且仅当业务事务已提交。

基础设施：infra 和 observability 的 compose 文件里没有 `:latest` 镜像。真机：sales → inventory → finance 在 Tempo 里是一个 trace 加它的链接。

## 相关决策

- [0103 每种语言内部一套锁定的技术栈](../02-decisions/01-architecture/0103-locked-stack-per-language.md)：每个模块一个指标 registry。
- [0106 基础设施不是组件](../02-decisions/01-architecture/0106-infrastructure-is-not-a-component.md)：可观测性栈在组件图之外运行。
- [0108 一个外壳、一个仓库、一个镜像、一份成员清单](../02-decisions/01-architecture/0108-one-repository-per-shell.md)：外壳里每成员的身份。
- [0504 一种错误对象，由目录里的 reason 标识](../02-decisions/05-runtime/0504-error-model-and-reason-catalogue.md)：日志级别跟随状态码；内部错误只记日志，从不返回。
- 计划新增、尚未编号："审计记录是业务数据，走 outbox"。

## 已知限制

- 一条异步流程是若干个由链接连起来的 trace，不是一棵树。
- Prometheus 每个容器只抓一个端口；外壳必须提供汇总端点，否则只看得到一个成员。
- 日志采集依赖容器运行时的日志驱动；collector 停机期间写的日志，只有运行时保留着才会被补读。
- `infra/audit` 出现之后审计才能查询；在那之前审计事件留在各生产者的 outbox 里，outbox 是回放的事实源（[12-event-bus.md](12-event-bus.md)）。
- 开启采样时按 trace 采样；被采样掉的请求仍有它的日志和指标。
