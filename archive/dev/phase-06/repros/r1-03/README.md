# r1-03：grpc-js 的服务配置重试、重试预算与 MaxConnectionAge

对应 sdk-redesign §7.9 第 3 条（"grpc-js：同样的两点"，即第 2 条对 grpc-go 验证的两点）；支撑 P7.5、P7.6、P7.8，以及 §5.3 选 grpc-js + ts-proto 的前提。控制者转来 R1a 对 grpc-go 的发现之后，补测了重试预算的恢复门槛、re-resolution 是否回满、`maxAttempts` 的含义（`throttle.ts`）。

## 假设

1. 从 proto 方法选项 `idempotency_level` 推出的服务配置（`retryPolicy` + `retryThrottling`），经 `grpc.service_config` 交给 grpc-js 后真的生效：幂等方法在 `UNAVAILABLE` 时重试，非幂等方法不重试。
2. ts-proto 生成的代码在运行时能拿到 `idempotency_level`，SDK 不需要另跑生成器。
3. 重试预算 `retryThrottling{maxTokens: 10, tokenRatio: 0.1}` "按连接计算，所以也是按成员计算"（P7.8）。
4. 服务端 `grpc.max_connection_age_ms` 到点发 GOAWAY，客户端透明重连，调用方看不到错误（P7.5、compconf grpc-05）。
5. 服务端能按 P7.5 执行 `EnforcementPolicy.MinTime 20 s`（限制客户端 ping 频率）。

## 环境与版本

| 项 | 版本 |
|---|---|
| Node | v24.21.0（本机 fnm），直接跑 `.ts`（类型擦除），不经构建 |
| @grpc/grpc-js | 1.14.5 |
| ts-proto | 2.12.4（`outputServices=grpc-js,outputSchema=true,importSuffix=.ts`），protoc 3.19.1 来自 `grpc-tools` 1.13.1 |
| 对照：grpcio | 1.76.0（`python:3.13-slim` 一次性容器，只测预算按什么计算） |

全部在本机回环上，服务端和客户端在同一个进程里（Python 对照在容器里）。

## 步骤

```bash
./run.sh > output.txt     # npm ci → 重新生成 gen/echo.ts → node repro.ts → node throttle.ts → grpcio 对照
```

`proto/echo.proto`：`Get` 标 `NO_SIDE_EFFECTS`，`Create` 不标。服务配置由 `repro.ts` 的 `serviceConfigFrom(protoMetadata)` 从 ts-proto 生成的描述符里推出：

```json
{"methodConfig":[{"name":[{"service":"r1.echo.v1.Echo","method":"Get"}],
  "retryPolicy":{"maxAttempts":3,"initialBackoff":"0.05s","maxBackoff":"0.5s","backoffMultiplier":2,"retryableStatusCodes":["UNAVAILABLE"]}}],
 "retryThrottling":{"maxTokens":10,"tokenRatio":0.1}}
```

`maxAttempts` 取 3，与 R1a 为 grpc-go 定下的"首次 + 2 次重试"一致。

## 原始输出（关键几行）

完整输出见 `output.txt`。

```
R1 Get (NO_SIDE_EFFECTS), first 2 attempts UNAVAILABLE: OK attempts=3 gaps(ms)=61,115
R2 Get, always UNAVAILABLE (maxAttempts 3): ERR UNAVAILABLE attempts=3 gaps(ms)=60,93
R3 Create (no idempotency level), always UNAVAILABLE: ERR UNAVAILABLE attempts=1
R4 channel A, 6 failing Get calls, attempts per call: 3,2,1,1,1,1
R4 channel B (new channel, same target string, local subchannel pool), first failing call attempts: 1
R4 channel D (same server, target spelled "dns:///127.0.0.1:45087"), first failing call attempts: 3
R5a age=2000ms grace=3000ms: {"Create OK":16140,"Get OK":9084}; distinct client connections seen by server=4; slow 2500ms call started ~300ms before GOAWAY: OK
R5b age=2000ms grace=500ms: {"Create OK":19160,"Get OK":10544}; distinct client connections seen by server=4; slow 2500ms call started ~300ms before GOAWAY: ERR UNAVAILABLE
R6 client pings every 100ms for 3s while idle, then calls again: OK same connection=true
M1 maxAttempts=2: attempts on an always-UNAVAILABLE Get = 2
M1 maxAttempts=3: ... = 3      M1 maxAttempts=5: ... = 5
M1 maxAttempts=6: ... = 5      M1 maxAttempts=10: ... = 5
M2 12 failing calls -> attempts 3,2,1,1,1,1,1,1,1,1,1,1; then 60 successes; probe attempts=1 (2 = retries back on)
M2 12 failing calls -> attempts 3,2,1,1,1,1,1,1,1,1,1,1; then 61 successes; probe attempts=2 (2 = retries back on)
M3 target localhost: exhausted, attempts 3,2,1,...; probe right away attempts=1
M3 after 3 s of connection rotation (+6 successes = +0.6 tokens): probe attempts=1 (2 = budget was refilled)
   （throttle-trace.log 里这 3 s 内有 3 次 "Looking up DNS hostname localhost / Resolved addresses"，即确实发生了 re-resolution）
===== grpcio 1.76.0
channel A, 6 failing Get calls, attempts per call: [4, 1, 1, 1, 1, 1]      （这个对照脚本用的是 maxAttempts 4）
channel B (new channel, same target, local subchannel pool), attempts: 4
```

## 结论

| 假设 | 结论 |
|---|---|
| 1 服务配置生效 | **成立**。幂等方法重试到 `maxAttempts`，间隔约 50 ms、100 ms 递增；非幂等方法只试 1 次 |
| 2 运行时拿到选项 | **成立**。`outputSchema=true` 时 `protoMetadata.fileDescriptor.service[].method[].options.idempotencyLevel` 有值（1 = NO_SIDE_EFFECTS，2 = IDEMPOTENT），SDK 运行时就能推出服务配置 |
| 3 预算按成员 | **不成立（grpc-js）**。grpc-js 把 `RetryThrottler` 放在模块级的 `RETRY_THROTTLER_MAP` 里，键是规范化后的目标字符串（`127.0.0.1:P` 与 `dns:127.0.0.1:P` 是同一个键）。同一进程里对同一目标新建的 channel，即使用 `grpc.use_local_subchannel_pool`，也和旧 channel 共用一个预算（R4 channel B）；只有目标字符串写法不同才分开（R4 channel D）。对照：grpcio（C-core）是按 channel 的（channel B 有完整预算） |
| 4 GOAWAY 透明 | **成立**。7 s 内服务端轮换 4 条连接，约 2.5 万次调用（含不可重试的 `Create`）零错误。前提是 grace ≥ 最长的在途调用：grace 500 ms 时，一个 2.5 s 的调用被切断，答 `UNAVAILABLE`（R5b） |
| 5 ping 限速 | **不成立（grpc-js 做不到）**。grpc-js 服务端没有 keepalive enforcement 的选项（`recognizedOptions` 里没有，`grpc.http2.min_ping_interval_without_data_ms` 被忽略）；客户端每 100 ms ping 一次，连接照常保持（R6）。grpc-go 会以 `too_many_pings` 断开 |

R1a 让补测的三点（与 grpc-go 对照）：

| 项 | grpc-go（R1a） | grpc-js（本次） |
|---|---|---|
| `maxAttempts` 含义 | 总次数，含首次 | **相同**：总次数含首次（M1：2→2、3→3）。上限 5，超过按 5（`grpc-node.retry_max_attempts_limit`） |
| 预算的范围 | 按 channel | **按（进程，规范化的目标字符串）**，跨 channel 共享 |
| 用尽后多少次成功才恢复 | 约 61 次 | **61 次**（M2：60 次后仍不重试，61 次后恢复）。原因：每次失败的尝试 −1（下限 0），每次成功 +0.1，"能否重试"是在扣掉这次失败之后判断 `tokens > maxTokens/2`，所以从 0 要攒到 6.1 |
| resolver 更新是否回满 | 回满 | **不回满**：新配置到来时按比例继承旧令牌（`tokens × 新max/旧max`）。M3 里 3 次真实的 re-resolution 之后，预算仍是用尽状态 |
| 最少几次失败关掉重试 | 约 5 次 | 相同：满额 10，第一次调用的 3 次尝试 −3，第二次调用 2 次尝试后到 5，之后不再重试（R4：3,2,1,1…） |

## 对设计的影响

1. **P7.8 的"按连接计算，所以也是按成员计算"改为按语言写明**：Go、Python 按 channel，所以按成员；TS（grpc-js）按（进程，目标）。TS 今天只有 BFF，而 BFF 永远不进外壳（0108、§5.5），所以进程等于成员，语义上没有差别；TS 外壳启动器跑 compconf `shell` profile 时，outbound-04（重试量 ≤ 10 %）按进程计。如果将来 TS 真要进外壳，SDK 再在拦截器里自己做按成员的预算（届时去掉服务配置里的 `retryThrottling`）。不建议用"每个成员换一种目标写法"绕开，那是依赖 grpc-js 内部实现。
2. **P7.8 写明 `maxAttempts: 3`（总次数，含首次）**，三门语言一致，和 R1a 的结论相同；顺便把"最多 3 次"这句改成"最多再试 2 次"，免得被读成 1 + 3。
3. **预算恢复与回满的差异写进 compconf 的说明，而不是写进协议**：协议只规定 `{maxTokens: 10, tokenRatio: 0.1}`；"resolver 更新时是否回满"各语言不同（Go 回满、JS 不回满），outbound-04 只测"持续 UNAVAILABLE 时重试量 ≤ 10 %"，两种实现都满足。
4. **P7.5 的 `EnforcementPolicy.MinTime 20 s` 降为 Go/Python 的 MUST、TS 的不适用**（grpc-js 服务端无此能力）；compconf 如有对应用例，TS widget 要能声明 skip。`MaxConnectionAge` / `MaxConnectionAgeGrace` 在 grpc-js 上可用（`grpc.max_connection_age_ms` / `grpc.max_connection_age_grace_ms`）。
5. **P7.5 补一句约束：`MaxConnectionAgeGrace` 必须大于最长的入站截止时间**（今天 30 s 对 10 s / 15 s，满足；R5b 证明不满足时在途调用会被切断）。
6. TS SDK 的生成选项定为 `outputServices=grpc-js,outputSchema=true`，SDK 从 `protoMetadata` 推服务配置；`importSuffix=.ts` 让 Node 24 直接运行生成代码。`(be.v1.max_items)` 这类自定义选项在描述符里的形状，本次没有测，留给 P7.10 落地时验证。
7. P7.6 的"每个依赖一条 TCP 连接"在 grpc-js 上默认成立（全局子通道池按目标和选项复用）。如果每个成员要各自一条连接，用 `grpc.use_local_subchannel_pool: 1`；但它不影响第 1 条说的重试预算共享。
