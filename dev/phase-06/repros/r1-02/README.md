# R1 #2：grpc-go 的重试服务配置与 MaxConnectionAge 之后的透明重连

## 假设

来自 `sdk-redesign.md` §7.9 第 2 条，支撑 P7.5、P7.8：

1. 由 proto 方法选项 `idempotency_level` 生成的 `WithDefaultServiceConfig`（`retryPolicy` + `retryThrottling`）在 grpc-go 里真的生效：幂等方法在 `UNAVAILABLE` 时重试，其它方法不重试，重试预算按连接计算；
2. 服务端 `MaxConnectionAge` 到期发 GOAWAY 之后，客户端透明重连，调用方看不到错误。

## 环境与版本

- go 1.26.0，linux/amd64；服务端和客户端在同一进程，走真实 TCP，目标写 `localhost:<port>`（默认 dns 解析器，和 compose 里写服务名一样）。
- 钉住的版本：grpc v1.83.2、protobuf v1.36.12（同 `tools/be-sdk-go/go.mod`）；最新稳定版：grpc v1.84.0。两组输出一致。
- 不需要 protoc：`repro.proto` 用 `github.com/bufbuild/protocompile` v0.14.1 在运行时编译，生成器从描述符里读 `MethodOptions.idempotency_level`，拼出 service config JSON；消息用 `google.protobuf.StringValue`。
- 服务端参数取 P7.5：`MaxRecvMsgSize` 4 MiB、`EnforcementPolicy.MinTime` 20 s、`MaxConnectionAgeGrace` 30 s；`MaxConnectionAge` 用 1 s 代替 5 min，只为几秒内经历多次 GOAWAY。客户端 keepalive 取 P7.6（30 s / 10 s，空闲不发）。

## 步骤

`./run.sh`（约 1.5 分钟，T13 要等 dns 解析器的 30 s 最小间隔）。请求体 `"<id>|<mode>"` 控制服务端：`fail=N` 前 N 次答 `UNAVAILABLE`，`always` 一直答，`sleep=MS` 睡一会。

| 用例 | 内容 |
|---|---|
| T1–T3 | `NO_SIDE_EFFECTS`、`IDEMPOTENT` 方法前 2 次失败 → 重试成功；没标选项的方法不重试 |
| T4a / T4 | 同一连接上（预算已被 T1–T3 消耗）与新连接上，各测一次"最多几次尝试" |
| T5–T7 | 一直失败的 20 次调用总共几次尝试；预算被同一连接的所有方法共用；另一个 ClientConn 不受影响 |
| T8 | 60 ms 截止时间内，重试停在截止时间 |
| T12 | 预算耗尽后，要多少次成功调用才恢复重试 |
| T13 | 预算会不会被重新解析刷满：无 GOAWAY 空等 32 s / 有 GOAWAY 空等 2 s / 有 GOAWAY 空等 32 s |
| T9 | 8 个协程持续调用 6 s（一半是不带重试策略的方法），期间连接每秒被 GOAWAY |
| T10 / T11 | 2.5 s 的长调用跨过连接寿命：Grace 30 s 时成功；对照组 Grace 300 ms 时失败 |

## 原始输出（关键几行）

```
INFO generated service config: {"methodConfig":[{"name":[{"service":"repro.v1.Widgets","method":"GetWidget"},{"service":"repro.v1.Widgets","method":"TouchWidget"}],"retryPolicy":{"maxAttempts":4,"initialBackoff":"0.05s","maxBackoff":"0.5s","backoffMultiplier":2,"retryableStatusCodes":["UNAVAILABLE"]}}],"retryThrottling":{"maxTokens":10,"tokenRatio":0.1}}
PASS T1 NO_SIDE_EFFECTS retried on UNAVAILABLE: err=<nil> attempts=3 gaps=[45ms 103ms]
PASS T3 method without option is NOT retried: code=Unavailable attempts=1
PASS T4a same ClientConn after T1–T3: budget already cuts retries short: code=Unavailable attempts=2 (tokens 6.2 → 5.2 retry → 4.2 ≤ 5 stop)
PASS T4 at most 3 retries (maxAttempts=4) on a fresh ClientConn: code=Unavailable attempts=4 gaps=[46ms 88ms 205ms]
PASS T5 retryThrottling{10,0.1} caps retries: 20 calls → 23 attempts (no throttling would be 80; expected 4+19=23)
PASS T6 budget is shared by all methods on the same ClientConn: code=Unavailable attempts=1
PASS T7 budget is per ClientConn: another ClientConn still retries: err=<nil> attempts=3
PASS T12 after draining, 55 successes → probe attempts=1
PASS T12 after draining, 61 successes → probe attempts=2
PASS T13a no GOAWAY, idle 32s: probe attempts=1 want=1
PASS T13b GOAWAY every 1s, idle 2s: probe attempts=1 want=1
PASS T13c GOAWAY every 1s, idle 32s (re-resolve allowed again): probe attempts=2 want=2
PASS T9 continuous load across GOAWAYs: zero caller-visible errors: ok=121262 errors=0 [] server connections=6 in 6s (MaxConnectionAge=1s)
PASS T10 in-flight call survives GOAWAY with grace 30s: long call err=OK elapsed=2.502s
PASS T11 control: grace 300ms kills the in-flight call: long call err=Unavailable elapsed=2.317s
== failed=0
```

## 结论

**成立**，另有三处细节要写进设计。

- 生成的服务配置生效：幂等方法按退避（实测间隔 46 / 88 / 205 ms，即 `random(0, min(50 ms·2ⁿ, 500 ms))` 的量级）重试，非幂等方法不重试；`retryThrottling` 生效，20 次一直失败的调用只产生 23 次尝试（没有预算时是 80 次）。
- GOAWAY 之后透明重连：6 s 内换了 6 条连接，12 万次调用 0 个错误，其中一半走的是没有重试策略的方法，靠的就是 gRPC 自带的透明重试。进行中的调用在 Grace 内正常完成；Grace 太短时调用失败（对照组）。Grace 30 s 大于入站最长截止时间 15 s（P9），所以设计值是安全的。

三处细节：

1. **"最多 3 次"有歧义，而且和 foundations 不一致。** `retryPolicy.maxAttempts` 包含首发。P7.8 写"重试最多 3 次"（= `maxAttempts: 4`，本复现照这个读法），`docs/en/04-foundations/16-deadlines-and-retries.md` 的示例 JSON 写 `"maxAttempts": 3`（= 2 次重试），同一页还写"三层各三次尝试，底层 27 次"。两份文档必须统一。
2. **预算比字面上紧得多。** grpc-go 的算法是：每次失败的尝试先把令牌减 1，减完之后令牌数 > `maxTokens/2` 才允许重试；每次成功调用加 `tokenRatio`。`maxTokens: 10` 意味着一条连接上累计约 5 次失败的尝试之后就不再重试（T4a：前面几个用例的失败已经让后一次调用少重试了两次），耗尽之后要 61 次成功调用才恢复（T12）。所谓"额外流量 ≤ 10 %"是稳态值，对调用量小的成员（ERP 里很常见），一次依赖重启之后的几分钟里基本不重试。
3. **预算会被解析器更新刷满。** 每次解析器更新，grpc-go 都会重新应用服务配置，并新建一个令牌满额的限流器（`clientconn.go` 的 `applyServiceConfigAndBalancer`）。GOAWAY 之后的重新解析受 dns 解析器 30 s 最小间隔约束（T13b 没刷满，T13c 刷满）。所以在 `MaxConnectionAge` = 5 min 的设定下，预算大约每 5 分钟回满一次。"按连接计算"准确的说法是"按 ClientConn 计算，并在每次解析器更新时重置"。

## 对设计的影响

1. **P7.8 改写成精确的数字**（建议）：`maxAttempts: 3`（首发 + 2 次重试），与 foundations 16 和"27 次"的论证一致；或者两边都改成 4，二选一，以写 JSON 的那份为准。推荐 3：重试只用来吸收换连接、滚动重启那一瞬间的 `UNAVAILABLE`，而 GOAWAY 本身已经由透明重试兜住（T9）。
2. **P7.8 里"按连接计算"改为"按 ClientConn 计算"**，并补一句："每次解析器更新（dns 重新解析，最快 30 s 一次，通常跟着 GOAWAY）时预算回满；`≤ 10 %` 是稳态上限，不是硬上限"。P7.6 已经规定按（成员，依赖，端口）复用一个 ClientConn，所以"一个成员的重试风暴花不到别的成员的预算"仍然成立（T7）。
3. `maxTokens: 10` 可以保留；如果希望低流量成员在依赖重启后也能重试，可以改成 `maxTokens: 20`（阈值 10）、`tokenRatio` 不变。这是取舍，不是缺陷，留给 lane 决定。
4. 生成器的写法已验证可行：从描述符读 `MethodOptions.idempotency_level`，同一份 JSON 可以三门语言共用（`main.go` 的 `serviceConfigFor`）。grpc-js 是否同样生效是第 3 条复现的事。
