# r1-08：Fastify 5 同进程多实例（TS 外壳启动器的前提）

对应 sdk-redesign §7.9 第 8 条；支撑 §5.5 的 TS 启动器 `runShell([specA, …])`、P19.4（除四样共享物之外一切按成员实例化），以及 P3.4–P3.6 在 Fastify 上的落法。

## 假设

1. 一个 Node 进程里起多个 Fastify 实例，各自监听一个端口，钩子（onRequest、preHandler、onSend、onError、onResponse、onClose）、错误处理器、日志器互不串。
2. 进程里只有一个 `AsyncLocalStorage`（SDK 的 ctx），在 `onRequest` 里 `als.run(ctx, done)` 之后，handler 跨 `await` 仍能拿到本成员、本请求的 ctx，并发请求不串。
3. P3.5 的服务端超时（读请求头 5 s、整个请求 30 s、空闲 120 s）、P3.6 的请求体上限（默认 1 MiB、路由可加大）、P3.4 的路由截止时间（504 + `DEADLINE_EXCEEDED`）都能按实例设置。
4. 关掉一个实例不影响另一个。

## 环境与版本

| 项 | 版本 |
|---|---|
| Node | v24.21.0（本机 fnm） |
| fastify | 5.12.5 |

不需要容器；两个实例 `erp/sales`（A）和 `erp/finance`（B）在同一个进程里，监听回环上的随机端口。为了跑得快，A 的请求头超时设 1 s、B 设 3 s，A 的 `handlerTimeout` 设 1 s。

## 步骤

```bash
./run.sh > output.txt     # npm ci && node repro.mjs
```

| 场景 | 做什么 |
|---|---|
| F1 | 两个实例各自 `listen({port: 0})` |
| F2 | 对 A、B 交替并发 4 个请求，handler 里 `await sleep(20)` 后读 ALS |
| F3 | 数两边钩子的触发次数；只对 A 发一个 404 |
| F4 | 两个实例的 pino 写同一个流，看每行的 `component` |
| F5 | 对 A POST 2 MiB：默认路由（上限 1 MiB）和声明了 4 MiB 的路由 |
| F6 | A 的 `/slow`（1.5 s）撞上 `handlerTimeout` 1 s；B 没设 |
| F7 | 慢速请求头（只发半个请求就停）：A、B 各自多久断开 |
| F8 | `A.close()` 之后再请求 A、B |
| F9 | 对照：只设 `headersTimeout`、不设 `connectionsCheckingInterval` |

## 原始输出（关键几行）

完整输出见 `output.txt`。

```
===== node v24.21.0, fastify 5.12.5
F2 /whoami x4 interleaved: 200 {"member":"erp/sales","ctx":{"member":"erp/sales",…}} | 200 {"member":"erp/finance","ctx":{"member":"erp/finance",…}} | …
F3 hook counts after 2 requests each: A {"onRequest":2,"preHandler":2,"onSend":2,"onError":0,"onResponse":2} B {…同样是 2…}
F3 after one 404 on A only: A.onRequest 3 B.onRequest 2
F4 log lines carry their own component: erp/sales/ctx=erp/sales, erp/finance/ctx=erp/finance, erp/sales/ctx=erp/sales, erp/finance/ctx=erp/finance
F5 A POST 2 MiB to /upload (limit 1 MiB): 413 {"status":413,"reason":"BODY_TOO_LARGE","member":"erp/sales","ctx":"erp/sales"}
F5 A POST 2 MiB to /upload-big (route limit 4 MiB): 200 {"bytes":2097160}
F6 A /slow (handlerTimeout 1000ms, handler 1500ms): 504 {"status":504,"reason":"DEADLINE_EXCEEDED","member":"erp/sales","ctx":null}
F6 B /slow (no handlerTimeout): 200 {"aborted":false}
F7 slowloris (partial headers): A (headersTimeout 1000) 1023ms HTTP/1.1 408 Request Timeout | B (headersTimeout 3000) 3005ms HTTP/1.1 408 Request Timeout
F8 after A.close(): B still serves -> 200 ; A -> ERR ECONNREFUSED ; onClose A 1 B 0
F9 headersTimeout 1000 with default connectionsCheckingInterval: 30003ms HTTP/1.1 408 Request Timeout (server.connectionsCheckingInterval default 30000)
```

## 结论

**假设 1、2、4 成立；假设 3 成立，但有两个必须写进 SDK 的细节。**

- 实例之间完全隔离：钩子计数、错误处理器、pino 的 `base.component`、请求体上限、超时、关闭，都只作用于自己的实例。一个进程一个 ALS 足够，`als.run(ctx, done)` 包住后续生命周期，跨 `await` 和并发都不串。
- 细节一（P3.5）：Node 的 `headersTimeout` / `requestTimeout` 只在 `connectionsCheckingInterval` 的周期上检查，默认 **30 s**。只设 `headersTimeout: 5000`，慢速请求头实际要 30 s 才被断开（F9）。必须同时设 `http: { headersTimeout, connectionsCheckingInterval }`（Fastify 把 `http` 选项原样传给 `http.createServer`）；本次用 200 ms，断开时刻精确到 ±25 ms（F7）。断开时回的是 `408 Request Timeout` 并关连接，满足"慢速请求头必须被断开"。
- 细节二（P3.4）：Fastify 5.12 自带 `handlerTimeout`（实例级和路由级都可以设），到点答 **503** 并 abort `request.signal`。SDK 在错误处理器里把 `FST_ERR_HANDLER_TIMEOUT` 映射成 504 + `DEADLINE_EXCEEDED` 就行（F6）。但这时错误处理器跑在定时器的上下文里，**ALS 是空的**（`ctx: null`）；请求体超限的 413 则拿得到 ctx。所以 SDK 的错误处理器不能依赖 ALS，成员身份、request id 要从 `request` 和闭包里取。
- `bodyLimit` 实例级默认 1 MiB、路由级可以加大，超限的错误码是 `FST_ERR_CTP_BODY_TOO_LARGE`，映射成 413 + `BODY_TOO_LARGE`。

## 对设计的影响

1. §5.3 选 Fastify 5 的理由成立，TS 启动器可以照 apis §5 的伪代码写：每个成员 `Fastify({...})` 一个实例、`listen(m.httpPort)`，外壳自己的 `/healthz` 和汇总 `/metrics` 再起一个实例。
2. TS SDK 建实例时固定这组选项（写进 apis §4 "TS 特有的要点"）：
   - `http: { headersTimeout: 5000, connectionsCheckingInterval: 1000 }`（≤ 1 s，否则 P3.5 的 5 s 变成最多 35 s）；
   - `requestTimeout: 30000`、`keepAliveTimeout: 120000`、`bodyLimit: 1 MiB`（路由声明更大时用路由级 `bodyLimit`）；
   - `handlerTimeout` 取路由截止时间（默认 `HTTP_DEFAULT_TIMEOUT` 10 s，编排类 15 s），错误处理器把 `FST_ERR_HANDLER_TIMEOUT` 改成 504 + `DEADLINE_EXCEEDED`；`request.signal` 交给 pg 的取消和 undici，这样 P3.4 的"同时取消下游调用和事务"也有了现成的信号。
3. 锁 Fastify 的精确版本时不得低于带 `handlerTimeout` 的版本（本次是 5.12.5，SDK 直接钉它）。
4. SDK 的错误处理器、`onTimeout` 钩子里不读 ALS（写进 INTERNAL 清单）。
