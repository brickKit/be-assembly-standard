# C10 P6 一致性考试的答卷（摘录）

考生：一个没参与写作的子代理（2026-11-13，只读文件，约 25 万 token、61 次工具调用、8 分钟），对照线协议第 20 章与 P13.14、P17.17、P17.19、P17.20、P18.2、P18.11，SDK 的 `flow/actions.go`、`channel`、`notify`、`extcmd`、`calls`，通知组件 3.0.8，钉钉渠道成员 3.0.2，采购与收付款的接入，协议 10、IM 渠道卡、D68，格与 L3。下面按答卷原样摘录每条的结论与依据；处理见 `result.md`。

## 必须改

- **M1** 应用密钥可能进日志：`im-dingtalk/internal/dingtalk/client.go:47-48` 取令牌用 `GET /gettoken?appkey=…&appsecret=…`；连接失败时 `calls.transportResult` 保留 `*url.Error`（文字带完整 URL），`calls.Upward` 用 `Wrap` 包起来，`errs.Error.Error()` 带出 cause（`be-sdk-go/errs/errs.go:96-98`）；`UserOfCode` 第一次取令牌失败原样返回，`bindings.Callback` 以 `Warn(..., "error", err.Error())` 写日志：绑定时钉钉不可达、令牌没缓存，`appsecret` 原文进日志。依据 ID12；`calls.Request.Credential` 注释“never in the URL”。改：用新接口 `POST /v1.0/oauth2/accessToken`；至少 `accessToken` 不原样返回传输错误；单元测试断言错误文字不含密钥。
- **M2** 钉钉的对外命令会进人工：`be-sdk-go/extcmd/state.go:163-168`（`QueryDown` 超过 `ManualAfter`=24h 转 `Manual`）、`state.go:127`（放弃只覆盖 prepared、retry_wait、unknown）、`flow/intents.go:56`（意图到期取任务截止，没有上限）。放弃时刻在 24 小时以后时，读取超时的 `send_card` 停在 `unknown` 超过 24h 转 `manual`，从此不终结，`Settled` 不跑，P20.2 的结果事实永不发。依据 ID03、AGENTS“设计取舍”、P13.14；`TestTheLocalAbandonTimeAndTheSettleHook` 只用 1 小时。改：（a）SDK 里带放弃时刻的命令不转 `manual` 并补 >24h 的测试；或（b）渠道成员把放弃时刻限在 ≤24h 并写进 P20.2 与 ID01。
- **M3** 锁的顺序与条款相反：`flow/actions.go:178-181` 先锁授权行，再 `decideIn` 锁单据、任务；P17.17、P20.8 写“单据、实例、任务、授权”。现在不会死锁（只有动作路径锁授权行，签发只插入）。改：条款改成实际顺序并写明为什么不会死锁，或改代码先锁单据。
- **M4** 钉钉组件没有任何清理：`dingtalk/module.go:87-93` 只有两个作业，全仓库没有 `DELETE FROM`；设计“拥有的数据”写了 `bind_session` 过期 1 天后删、`delivery` 到期后 7 天（至少 90 天）、`callback` 180 天、`ended` 的绑定 400 天；实现状态却写 ID01–ID12 已实现。
- **M5** 卡片标题没有转义：`client.go:75` 原样放入；ID02 要求按纯文本放入（转义成钉钉卡片不解释的形式）。
- **M6** 协议 10 第 173 行写“渠道账号由渠道成员维护（从身份与员工信息同步）；没有渠道账号时退回站内消息”，与同一节、P20.9、ID10（只由本人经 OAuth）矛盾，站内消息也不是“退回”。
- **M7** 组件索引第 196 行动作事件的订阅方写“—”，实际 `erp/purchase`、`erp/payment` 配了 `FLOW_ACTION_SOURCES` 就订阅；两者 `component.yaml` 的 `events.subscribes` 也该像通知组件那样补上。

## 建议改

1. `tellHolder`（`flow/actions.go:313-317`）发的是类别 `approval_task`，按 P20.3 也投外部渠道：被拒的说明又以钉钉卡片发一次；标题直接拼错误码，用户看不懂。
2. 签发时视图取不到或安全版本读不出的候选人静默跳过（`actions.go:121-129`），P17.19 没写这个例外。
3. 授权的安全版本按操作取（`SecurityVersion(d.Operation)`），与 P20.5“主体签发时的安全版本（P8.25）”的措辞，待核实是否等价。
4. `TestInteractiveActions` 没测 `GRANT_STALE`、`malformed`、“同一动作重放哪怕已过期”、`VERSION_CONFLICT`；`w.act` 直接调 `Handle`，收件表去重、否认后重投没测到。
5. `features.json` 的 `flow-actions` 待验证说明写“在装配项目的格里验证（C10 的 P6）”，是 SDK `AGENTS.md` 禁止的“随某任务”式去处，C10-A 已跑过。
6. 通知组件 `ExternalLease` 1 分钟，一轮至多 200 行 × 每行 10s，慢而有答复时别的轮会重复调用。
7. 通知组件被“本轮跳过”的行也 `attempts + 1`，退避被放大；P20.3“连续不可达”与 NT13“不可达一次”措辞不一致。
8. 偏好：`external_comm`、`marketing` 等类别的钉钉开关答 `REQUEST_INVALID`，NT09 只说“不认识的渠道”才这样答。
9. 通知组件测试索引的 `externals` 行列了 P20.4，没测“到期不转、不为必须送达重试”；P20.3 的不可重试分支、退避翻倍、“一轮里不可达就跳过”都没测。
10. 钉钉 `Deliver` 先 `valid()` 后查幂等：已受理的投递过了到期再重试答 `REQUEST_INVALID`，违背 P20.1；动作名没按 `^[a-z][a-z_]{0,39}$` 校验，带 `.` 会破坏按钮值的解析，不合 schema 的动作让 `EmitAction` 失败、回调处理无限重试。
11. 回调处理查投递 `WHERE id::text = $1`（`callbacks.go:200`）用不上主键（`(caller, id)`），每个回调全表扫描。
12. 换绑时只写“bound”一条审计，没有“ended”；公开的回跳不核对当前浏览器的登录主体是否等于会话的发起主体：别人把自己发起的授权链接发给受害人，受害人一同意，受害人的钉钉就绑到发起人的账号上（不符合 P20.9“用户在系统里登录后”）。
13. ID03 写“`errcode` 为 0 算受理”“限流错误码算没处理”，代码看新接口的 `success`、只认 HTTP 429；`success=false` 一律 `rejected`。3.0.2 说“取不到用户的网络故障答依赖不可用”，`userAccessToken` 那一步仍答 `REQUEST_INVALID`。
14. ID06 写“限速”，代码只限大小；待核实边缘是否配了。
15. 钉钉测试索引夸大：`sending` 列了 P20.5 没测“重发换新随机值、旧按钮失效”；`expiry` 只测了 4 秒的到期；丢弃的计数、隔离区的告警没测；L3 的“nothing written”只核对了状态码和单据状态。
16. 术语漂移：协议 10、D68、IM 渠道卡里的“一次性动作令牌”“核对动作令牌”与第 20 章“动作授权，不是秘密”不一致；IM 卡“适用协议”写协议 09（应为 10）；协议 10“失败与积压”写“必须送达的类别转站内”，与 P20.4 冲突。
17. 基础外壳里同壳的有 `test/probe-go*`，设计说“同外壳的都是基础成员”；待核实客户基线。
18. 小处：`Grace` 的注释引 P20.7 应为 P20.8；P20.8 的小写原因 `expired` 与大写错误码混用、`03-errors.md` 里没有。

## 没发现问题

秘密（按钮随机值、绑定的 `state` 只存摘要，回调正文换成摘要后才落库，动作事件里没有随机值，访问日志只记路径）；通知组件的外部投递（`SKIP LOCKED` 认领、事务外调用、取代与到期不再交出、结果事件在外部投递都有结果后才发）。
