# r1-07：JetStream pull consumer（nats.go、nats-py、nats.js）

对应 sdk-redesign §7.9 第 7 条；支撑 P12.4（流）、P12.5（durable 命名与参数）、P12.7（Nak 退避与 DLQ）、P12.9（InProgress）。

## 假设

1. durable 名 `<组件ID的/换成_>__<subject的.换成_>` 在三个客户端里都合法（包括带连字符的组件 ID）。
2. 首次创建时 `DeliverAll`，离线期间已发布的事件全部补收。
3. "没有就建，有就不碰" 可以靠客户端的创建 API 直接做到。
4. P12.5 的参数组合成立：`AckWait 30 s` + `BackOff = EVENTS_BACKOFF`（默认 `1s,10s,1m,5m,15m,30m,1h`）+ `MaxDeliver = EVENTS_MAX_DELIVER`（默认 8）。handler 出错就 `Nak`，按 BackOff 退避重投（P12.7）；处理慢时每 `AckWait/3`（10 s）发一次 `InProgress`，不会被重投（P12.9）。
5. compconf 用的加速值（`EVENTS_BACKOFF=200ms,500ms,1s`、`EVENTS_MAX_DELIVER=3`）是合法配置。

## 环境与版本

| 项 | 版本 |
|---|---|
| nats-server | 2.10.29（`nats:2.10-alpine`，与 be-nats 同一条线）；对照 2.11.17、2.12.15。一次性容器 `r1-r1b-nats`、`r1-r1b-nats211`、`r1-r1b-nats212`，`-js` |
| nats.go | 1.54.0（`jetstream` 包），Go 1.26 本机 |
| nats-py | 2.11.0（be-sdk-python 今天钉的）与 2.16.0（最新），`python:3.13-slim` 一次性容器 |
| nats.js | `@nats-io/jetstream` 3.4.0 + `@nats-io/transport-node` 3.4.0，Node v24.21.0 |

每个客户端用自己的流（`BE_R1GO` / `BE_R1PY` / `BE_R1JS`，按 P12.4 的默认值建：7 天、1 GiB、丢旧、去重 10 min、文件、单副本），跑同一组场景。

## 步骤

```bash
docker run -d --name r1-r1b-nats    -p 127.0.0.1::4222 nats:2.10-alpine -js
docker run -d --name r1-r1b-nats211 -p 127.0.0.1::4222 nats:2.11-alpine -js
docker run -d --name r1-r1b-nats212 -p 127.0.0.1::4222 nats:2.12-alpine -js
./run.sh > output.txt
docker rm -f r1-r1b-nats r1-r1b-nats211 r1-r1b-nats212
```

| 场景 | 做什么 |
|---|---|
| T1 | 按 P12.5 命名建 durable（`crm/opportunity`、`infra/iam-casdoor` 两种），读回参数 |
| T2 | 先发 3 条，再建 `DeliverAll` 的 durable，看能不能拉到 3 条 |
| T3 | 同名再建一次：参数相同 / `MaxDeliver` 不同 / `DeliverPolicy` 不同；再试 update |
| T4a | BackOff 长度与 MaxDeliver 的约束；读回 AckWait |
| T4b | BackOff `200ms,500ms,1s`、MaxDeliver 4，handler 不 ack（超时路径），记录每次投递的时刻 |
| T4c | 同上，handler 每次立刻 `Nak()` |
| T4d | 同上，handler `NakWithDelay(BackOff[n-1])` |
| T4e | **不设 BackOff**，AckWait 30 s，handler `NakWithDelay(EVENTS_BACKOFF[n-1])` |
| T4 advisory | 订阅 `$JS.EVENT.ADVISORY.CONSUMER.MAX_DELIVERIES.<流>.>` |
| T5a / T5b | AckWait 2 s，handler 4 s；每 AckWait/3 发 InProgress / 不发 |
| T5c / T5d | AckWait 6 s + BackOff `1s,2s,3s`，handler 4 s；每 AckWait/3（2 s）/ 每 BackOff[0]/3（330 ms）发 InProgress |
| T6（只 Go） | 服务端 `MaxDeliver -1`，上限由 SDK 自己判（2）：handler 崩溃不 ack，第 3 次投递时 SDK 直接写 DLQ 并 `Term` |

## 原始输出（关键几行）

完整输出见 `output.txt`。三个服务端版本、三个客户端的结果逐条一致，下面取 nats.go @ 2.10.29，客户端差异另列。

```
T1 durable "crm_opportunity__r1go_order_confirmed_v1" created; hyphen variant "infra_iam-casdoor__r1go_order_confirmed_v1" -> ok
T1 config read back: AckWait=1s MaxDeliver=8 BackOff=[1s 10s 1m0s 5m0s 15m0s 30m0s 1h0m0s] InactiveThreshold=720h0m0s MaxAckPending=256
T2 DeliverAll on first create: fetched 3 of 3 pre-existing events
T3 CreateConsumer again, identical config: ok
T3 CreateConsumer again, MaxDeliver 8->9: ERR nats: API error: code=400 err_code=10148 description=consumer already exists
T3 UpdateConsumer MaxDeliver 8->9: ok, MaxDeliver now 9
T3 UpdateConsumer DeliverPolicy all->new: ERR nats: API error: code=500 err_code=10012 description=deliver policy can not be updated
T4a BackOff len 3, MaxDeliver 3: ok
T4a BackOff len 3, MaxDeliver 2: ERR ... err_code=10116 description=max deliver is required to be > length of backoff values
T4a stored AckWait when AckWait=30s and BackOff[0]=200ms: 200ms
T4b no ack (timeout path), BackOff 200ms,500ms,1s MaxDeliver 4: [+0s(n=1) +200ms(n=2) +700ms(n=3) +1.7s(n=4)]
T4c Nak() each time, same BackOff: [+0s(n=1) +0s(n=2) +0s(n=3) +0s(n=4)]
T4e stored AckWait without BackOff: 30s
T4e no BackOff, AckWait 30s, NakWithDelay(EVENTS_BACKOFF[n-1]): [+0s(n=1) +200ms(n=2) +700ms(n=3) +1.7s(n=4)]
T4 advisory $JS.EVENT.ADVISORY.CONSUMER.MAX_DELIVERIES.BE_R1GO.t4b: consumer=t4b stream_seq=4 deliveries=4
T5a AckWait 2s, slow handler 4s with InProgress every 0.66s (AckWait/3): [+0s(n=1)]
T5b control, slow handler 4s, no InProgress: [+0s(n=1) +2s(n=2)]
T5c AckWait 6s + BackOff [1s,2s,3s], handler 4s, InProgress every 2s (AckWait/3): [+0s(n=1) +1s(n=2)]
T5d same, InProgress every 330ms (BackOff[0]/3): [+0s(n=1)]
T6 MaxDeliver -1, SDK-side limit 2, handler crashes (no ack): [+0s(n=1) +1s(n=2) +2s(n=3)]
T6 DLQ stream messages: 1

# 客户端差异（T3）
nats-py 2.11.0 / 2.16.0: T3 add_consumer again, MaxDeliver 8->9: ok; MaxDeliver now 9      <- 悄悄改了配置
nats-py:                 T3 API surface: update_consumer = False
nats.js 3.4.0:           T3 consumers.add again, MaxDeliver 8->9: ERR JetStreamApiError: consumer already exists
```

## 结论

| 假设 | 结论 |
|---|---|
| 1 命名 | **成立**。`/`→`_`、`.`→`_`、`__` 分隔，连字符也合法 |
| 2 DeliverAll | **成立**。三个客户端都补收到离线期间的 3 条 |
| 3 "有就不碰" | **部分成立**。nats.go `CreateConsumer`、nats.js `consumers.add` 是"仅创建"：参数相同时幂等，不同时报 10148。**nats-py 的 `add_consumer` 是"创建或更新"**，参数不同时悄悄改掉服务端配置，并且没有单独的 update API。`DeliverPolicy` 建好后改不了（10012），`MaxDeliver`、`BackOff` 可以改 |
| 4 参数组合 | **不成立**，三处：① 设了 BackOff，服务端就把 AckWait 改成 BackOff[0]，读回是 1 s 不是 30 s；第 n 次投递的确认期限是 BackOff[n-1]（T4b：0.2、0.5、1 s）。② `Nak()` 不看 BackOff，立刻重投（T4c：4 次投递都在同一毫秒内），2.10、2.11、2.12 都一样；所以"出错就 Nak，按退避重投"实际上会在几毫秒内用完全部 MaxDeliver。③ InProgress 按配置的 AckWait/3（10 s）发，挡不住 1 s 的 BackOff[0] 期限：handler 还在跑，消息已经第二次投递给另一个并发槽（T5c），**同一条事件被并发执行两次** |
| 5 compconf 值 | **成立**。约束实际是 `MaxDeliver ≥ len(BackOff)`（报错文字写的是 `>`，但 3 对 3 能建，2 对 3 被拒） |

另外：

- 不设 BackOff 时，`AckWait` 原样保存为 30 s，`NakWithDelay` 精确按给定的延迟重投（T4e，三个客户端一致：0.2、0.5、1.0 s），InProgress 每 AckWait/3 一次能挡住重投（T5a）。
- 投递次数用尽（超时或 Nak）时，服务端发 `MAX_DELIVERIES` advisory，带 `stream_seq`，之后不再投递。advisory 是核心 NATS 消息，当时没人订阅就没了。
- 服务端 `MaxDeliver -1`、由 SDK 按 `NumDelivered > 上限` 自己判，handler 崩溃（不 ack）的消息在超时后照常重投，到第 3 次时 SDK 写 DLQ 并 `Term`，不再投递（T6）。这样"最后一次投递时进程崩溃"也能进 DLQ，不依赖 advisory。

## 对设计的影响

建议改 P12.5、P12.7、P12.9（三门 SDK 和 busconf 一致）：

1. **consumer 上不设 BackOff。** `AckWait` 固定 30 s（就是 handler 的真实期限，P9 "AckWait − 5 s" 才成立）。`EVENTS_BACKOFF` 改为 SDK 侧的 Nak 延迟表：第 n 次投递失败 → `NakWithDelay(EVENTS_BACKOFF[min(n-1, len-1)])`。三个客户端都有这个 API（Go `NakWithDelay`、Python `nak(delay=)`、JS `nak(millis)`）。超时或崩溃造成的重投固定隔 AckWait（30 s），不再走退避表，这可以接受。
2. **服务端 `MaxDeliver = -1`，上限由 SDK 判。** 投递到达时 `NumDelivered > EVENTS_MAX_DELIVER`，就不跑 handler，直接写 DLQ（`Nats-Msg-Id = dlq:<durable>:<stream_seq>`，多副本或外壳里重复写会被去重）然后 `Term`。handler 在最后一次投递里失败，也是写 DLQ + `Term`，**不再 Nak**。这样 DLQ 覆盖"最后一次投递时进程崩溃"，不需要订阅 advisory。
3. 有了 1 和 2，**服务端 durable 上就不再有任何部署层面要调的参数**（AckWait 30 s、MaxAckPending 256、MaxDeliver -1、DeliverAll、InactiveThreshold 30 天都是协议常量）。P12.4/P12.5 的"没有就建，有就不碰"可以照字面执行，`EVENTS_MAX_DELIVER` / `EVENTS_BACKOFF` 改了立刻生效，不需要更新 consumer。SDK 必须自己实现"仅创建"：Go/JS 用 create 动作，Python 先 `consumer_info`，不存在才 `add_consumer`，**不能直接调 nats-py 的 `add_consumer`**（它会改掉已有 durable 的配置）。读回的配置与协议常量不一致时记 WARN，不覆盖。
4. **P12.9 不改文字**（InProgress 每 AckWait/3），但它只有在第 1 条落地后才成立；compconf events-sub 应加一条：handler 耗时 > AckWait/2 且持续发 InProgress → 只执行一次。
5. compconf 的加速值改为 `EVENTS_BACKOFF=200ms,500ms,1s`、`EVENTS_MAX_DELIVER=3`，语义不变；它们不再受 `MaxDeliver ≥ len(BackOff)` 约束。
6. pgqueue 适配器（P12.12）按同一语义实现：失败 → `next_attempt_at = now + EVENTS_BACKOFF[n-1]`；`delivery > EVENTS_MAX_DELIVER` → DLQ。busconf 加"Nak 后重投不早于 EVENTS_BACKOFF[n-1]"一条。
