# R1 #1：外壳里每个成员一个 TracerProvider、共用一个导出器；otelgrpc 用谁的 provider

## 假设

来自 `sdk-redesign.md` §7.9 第 1 条，支撑 P18.1、P19.3、P19.4（外壳的 trace 不变量）：

1. Go 外壳里每个成员一个 `TracerProvider`（`service.name` = 成员 ID），所有成员共用一个导出器，span 各自归到自己的成员名下；
2. otelgrpc 的 stats handler 用的是成员自己的 provider，不是全局的。

## 环境与版本

- go 1.26.0，linux/amd64；不需要 Docker：OTLP/HTTP 收集器是进程内的 `httptest`，按 protobuf 解出每个 span 的 `service.name`、trace_id、parent。
- 钉住的版本（同 `tools/be-sdk-go/go.mod`）：otel / sdk / otlptracehttp v1.46.0，otelgrpc v0.71.0（它正好对应 otel v1.46.0 和 grpc v1.83.2），grpc v1.83.2。
- 最新稳定版（`run.sh` 在临时副本里 `go get @latest`）：otel v1.47.0，otelgrpc v0.72.0，grpc v1.84.0。
- 两组版本的输出完全一致。

## 步骤

`./run.sh`：先用钉住的版本跑 `go run .`，再用最新版跑一次。场景：

| 场景 | 做法 |
|---|---|
| S1 | 每个成员 `WithBatcher(同一个导出器)`；成员 A 先 `Shutdown`，B 之后再发 span、再 `Shutdown` |
| S2 | 一个 `BatchSpanProcessor` 实例注册进两个 provider，停的顺序同上 |
| S3 | 每个成员自己的 BSP，共享导出器外面包一层 `Shutdown` 为空操作的壳；平台最后关真正的导出器 |
| S4 | 一个共享 BSP，成员侧包一层 `Shutdown` = `ForceFlush`；平台最后关真正的 BSP |
| G1 | 成员 A 起 gRPC 服务端、成员 B 当客户端，同一进程两个端口；otelgrpc 只给 `WithTracerProvider`，不给传播器 |
| G2 | 同上，再加 `WithPropagators(TraceContext + Baggage)`，不碰全局 |
| G3 | otelgrpc 什么都不给（默认）；全局 provider 设成 `service.name=GLOBAL`，看 span 落在哪 |
| G4 | 指标：默认 vs `WithMeterProvider(成员自己的)` |

## 原始输出（关键几行）

```
OBSERVED S1 naive per-member BSP + shared exporter: received=map[A:1] (want A:1 B:2), B.Shutdown err=<nil>
OBSERVED S2 one BSP registered in two providers: received=map[A:1 B:1] (want A:1 B:2), B.Shutdown err=<nil>
PASS S3 per-member BSP + shared exporter (no-op Shutdown): received=map[A:1 B:2] requests=2
PASS S4 one shared BSP (member Shutdown = ForceFlush): received=map[A:5 B:6] requests=2 (spans of both resources share batches)
    A        grpc.health.v1.Health/Check      trace=f64bfc1c…  span=ae5b9169 parent=-
    B        grpc.health.v1.Health/Check      trace=da857a38…  span=212952ad parent=cb66c5d5
OBSERVED G1 without WithPropagators: same trace=false (server.parent==client.span: false)
    A        A.handler.child                  trace=fa3ad06c…  span=c8e1a6a4 parent=cb99ad17
    A        grpc.health.v1.Health/Check      trace=fa3ad06c…  span=cb99ad17 parent=ec2eef94
    B        B.request                        trace=fa3ad06c…  span=ea384a87 parent=-
    B        grpc.health.v1.Health/Check      trace=fa3ad06c…  span=ec2eef94 parent=ea384a87
PASS G2 per-member provider + explicit propagator: one trace B.request→client→server→child, right service.name each: err=<nil> baggage(tenant)="t-42"
PASS G3 default otelgrpc handlers use the GLOBAL provider, not the member's: global collector=map[GLOBAL:2] member collector has rpc spans=false
PASS G4 otelgrpc metrics go to the global MeterProvider unless WithMeterProvider is given: default: global=2 member=0 metrics; with WithMeterProvider: member=1
INFO otel error handler saw 1 errors, first: traces export: Post "http://127.0.0.1:44653/v1/traces": context canceled
== failed=0
```

## 结论

**部分成立。**

- 成立：每个成员一个 provider、共用一个导出器，可以做到 span 各归各的 `service.name`，而且两个 resource 的 span 可以进同一批导出（S3、S4）。otelgrpc 只要给了 `WithTracerProvider`，服务端 span 落在服务端成员、客户端 span 落在客户端成员（G1、G2）。
- 不成立（照字面写会出错）：
  1. **朴素地共享导出器或 BSP 会静默丢 span。** `TracerProvider.Shutdown` 会关掉它的 span processor，BSP 的 `Shutdown` 又会关掉导出器。第一个成员一停，共享导出器就关了：S1 里成员 B 的两个 span 全丢，S2 里丢了一个。`B.Shutdown` 返回 `nil`，只有全局错误处理器看到一条 `context canceled`。外壳停机是"各成员 Stop → 平台关闭"，正好踩中。
  2. **otelgrpc 默认读全局。** 不给选项时 span 进全局 provider（G3），指标进全局 MeterProvider（G4）。传播器也一样：只给 `WithTracerProvider` 不给 `WithPropagators`，而全局传播器又没装时，每一跳都是新的 trace（G1，就是 §6.2 第 21 条"trace 每一跳都断"的原样复现）。

## 对设计的影响

不需要改协议条款的意思，但 P19.3 / P19.4 和 be-sdk-go 的设计要写得更细：

1. **P19.3 补一句"共享的导出器只由平台关闭"**。建议写法：成员的 `TracerProvider` 各自有一个 BSP，导出器是共享的，外面包一层 `Shutdown` 为空操作的壳（S3 的写法）；成员 Stop 时调自己 provider 的 `Shutdown`（只会 flush 自己的队列），平台在所有成员停完之后才关真正的导出器。S4（一个共享 BSP、成员侧 `Shutdown` 改成 `ForceFlush`）也可以，但一个成员的 `ForceFlush` 会冲掉所有成员的队列，而且共享队列满时一个成员能挤掉别人的 span。**推荐 S3**：队列按成员隔离，与 P19.4"其余一切按成员实例化"一致。
2. **be-sdk-go：所有 OTel 埋点一律显式传选项**，不靠全局：`otelgrpc.NewServerHandler` / `NewClientHandler` 都传 `WithTracerProvider(成员的)`、`WithMeterProvider(成员的)`、`WithPropagators(平台的)`；HTTP 中间件（otelgin / otelhttp）同理，它们同样默认读全局。
3. **全局只装传播器**（foundations 23 已写"传播器无状态，每进程装一次"）：平台调一次 `otel.SetTextMapPropagator(TraceContext+Baggage)`，作为第三方埋点的兜底。全局 `TracerProvider` 建议设成**外壳自己的** provider（`service.name` = 外壳 ID），不设成某个成员的，也不留空：漏传选项的埋点会产出 `service.name` = 外壳 ID 的 span，一眼能看出来，而不是悄悄消失。
4. **一致性用例 CP-OBS 加一条**：外壳里跑完 HTTP → gRPC → 事件链路后，收集器里不能有 `service.name` = 外壳 ID 的 span（漏传 provider 的埋点都会落到这里）；再加一条"先停一个成员、再让另一个成员发 span"的停机用例（S1 的场景），要求 span 不丢。
5. 门禁可加一条静态检查：`otelgrpc.NewServerHandler(` / `NewClientHandler(` / `otelgin.Middleware(` 的调用里必须出现 `WithTracerProvider`，只在 SDK 仓库里跑即可。
