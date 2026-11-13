# C8 P6 审查答卷：通知意图（线协议第 18 章）与 infra/notification

审查范围：spec 18、intent.v1 schema、协议 10 的“通知”；be-sdk-go 的 `notify/notify.go`、`flow/intents.go`、`flow/instance.go` 的 `publish`、`flow/employees.go` 的 `OnChange`；`components/infra/notification` 全部文档与代码、迁移、契约、itest；`erp/purchase`、`erp/payment` 的清单、意图契约与 BRICKKIT；`be-acceptance` 的 `cells/prepare.py` 与 `scenarios/test_notification.py`。只读，未改任何文件。

路径简写：`N/` = `components/infra/notification/`，`SDK/` = `tools/be-sdk-go/`，`P/` = `tools/be-protocol/`。

---

## 必须改

### M1 发布者核对只比了两个都由发布方自填的字段，没有绑定到订阅的流（可冒充别的发送方、毒化它的合并键）

- **位置**：`N/internal/intents/intents.go:41`（`from := strings.TrimPrefix(e.Source, "urn:be:")`）、`:48`（`SenderIsSource: parsed && in.Sender == from`）；`N/internal/intents/intents.go:28-34`（`Subs` 的闭包里有配置的发送方 `c`，但没有传给 `OnEvent`）；文档同样的表述：`N/docs/design.md:52`（NT02）、`N/AGENTS.md:108`（易错点）、`P/spec/18-notification-intents.md:23`（P18.8）。
- **问题**：`ce-source` 是发布方自己写进消息头的（`SDK/events/consumer.go:219` 原样读出，`SDK/events/envelope.go:92` 由生产者填写），载荷的 `sender` 也是发布方写的。安全 02（`docs/zh/06-protocols/security/02-trusted-identity-and-attributes.md:113`）明确写“`ce-source` 或 actor 不能单独证明来源”，可信的只是“谁能在哪个流上发布”的排他映射。现在的核对只要求两者相等，没有要求它们等于这个订阅所对应的流的属主 `c`。
- **会怎样出错**：配置里的任一发送方（例如 `erp/purchase`，被攻破或有缺陷）在**自己的流** `erp.purchase` 上发一条类型 `erp.purchase_notification.intent.v1`、`ce-source: urn:be:erp/payment`、`sender: erp/payment` 的意图，就被当作 `erp/payment` 的意图收下：可以以 `erp/payment` 的名义给任何人发消息；更糟的是带 `collapse_key: task:<payment 的任务>`、`collapse_seq: 9223372036854775807` 的撤回意图会撤掉 `erp/payment` 已写的待审批消息，并让它以后这个键的所有真实意图都成为 `stale`（合并键记录保留 400 天）。itest 的 `forged` 用例（`N/itest/senders_integration_test.go:25,32`）只测了“来源对、载荷 sender 错”，没测“来源和载荷一起伪造”，所以全绿。
- **建议**：`Subs` 把配置的发送方 `c` 交给处理函数，`OnEvent` 要求 `from == c && in.Sender == c`（或直接以 `c` 为发送方，`from`、`in.Sender` 与它不符即 `not_the_sender`）；P18.8、NT02、AGENTS 易错点改成“载荷的发送方与信封的来源都必须是这个流按 P18.2 对应的组件”，并注明信任前提是消息系统的排他发布权限（安全 02）；itest 加一例：在 `test.buy` 流上发 `ce-source=test/pay`、`sender=test/pay` 的意图，必须被拒且不影响 `test/pay` 的合并键。顺带核对 `infra/workflow` 的同一形状（它靠任务类型→发布者的配置绑定，问题较轻，但同样只信 `ce-source`）。

### M2 链接的 schema 放过了 `//host` 这类网络路径引用，“系统内路径”这条规则没有被 schema 守住

- **位置**：`P/schemas/notification/intent.v1.schema.json:47`（`"link": {"pattern": "^/"}`）；规则 `P/spec/18-notification-intents.md:15`（P18.5：“以 `/` 开头的系统内前端路径”，检验写 schema）。
- **问题**：`//evil.example/login` 与 `/\evil.example` 都匹配 `^/`，浏览器把前者当作跨站链接。
- **会怎样出错**：任一配置的发送方（或 M1 里冒充的）可以让站内消息指向外站，前端照 `link` 渲染 `<a href>` 时用户被带去钓鱼页；协议 10 “通知不授予权限、只给系统内链接”的前提被打破，而检验列写的“schema”给人已守住的错觉。
- **建议**：pattern 改为 `^/(?![/\\])` 一类（并禁止控制字符与空白），向量 `notification-intent` 加反例；通知组件认收时用同一 schema 自然拒收；前端（协议 20）渲染时仍只按相对路径处理。

### M3 岗位展开成功后不记结果：每一轮都重新展开，可能多投、结果事件自相矛盾

- **位置**：`N/internal/delivery/delivery.go:115-146`（`deliver` 只在 `result != core.Written` 时 `record` 岗位；展开成功的岗位没有任何记录）；设计 `N/docs/design.md:55`（NT05：“所有收件人都有了结果（主体有投递结果，岗位展开了或记了无法展开）”）、`:42`（数据表）。
- **问题**：只要意图里还有别的岗位在等投影，意图就留在 `pending`，下一轮会把**已经展开过**的岗位再展开一次（没给日期时用“投递当天”，跨零点日期也会变）。
- **会怎样出错**：① 第一轮岗位 A 展开为 X 并写了消息，等岗位 B 期间 A 换人为 Y，下一轮 Y 也收到消息——同一意图投给了两任持有人，违背“投递时展开为当时的持有人”的一次性语义；② 若下一轮 A 的投影变得不完整且意图已到期，A 被记为 `expired`，结果事件里 A“过期”而它的持有人其实已写入，下游按结果事件统计会出错；③ 每分钟对等待中的大意图重复展开，白白放大开销。
- **建议**：岗位展开成功时也记一行（例如 `delivery` 里 `position:<法人>/<岗位>[/<日期>]` → 新结果值 `expanded`，或单独的 `intent_position` 表），已有结果的岗位不再展开；同时把日期纳入岗位键（现在 `positionKey` 不含 `date`，同一岗位不同日期的两个收件人会互相覆盖，`delivery.go:187`）；事件契约与 NT05、数据表一起更新。itest 加一例：两个岗位一个等投影、另一个在两轮之间换人，断言只投第一任。

### M4 测试索引声称“员工投影在装配项目的格里验证”，但格里的 L3 根本不走岗位展开

- **位置**：`N/itest/AGENTS.md:9`；`tools/be-acceptance/conformance/scenarios/test_notification.py` 全文；`N/notification/module.go:37-40`（真实的 `flow.Employees` 目录与 `EmployeesChanged` 钩子）；`N/internal/delivery/delivery.go:297-307`。
- **问题**：L3 里的意图全部来自流程内核，内核已把岗位解析成主体（P18.10），所以通知组件收到的收件人只有主体；`Holders` 的真实实现、`complete` 判断、`EmployeesChanged` 在员工事件事务里排一轮（以及它对 SDK 内部表 `be_work_item` 的查询）都没有任何测试执行到。itest 用 `UseDirectory` 换掉了目录，也不经过 `OnChange`。
- **会怎样出错**：NT06 与 NT05“员工投影变化时排一轮”整段可以坏掉（例如 `be_work_item` 的列名或状态值在 SDK 里改了、钩子没装上）而全部测试仍绿；`itest/AGENTS.md` 的说法让维护者以为已覆盖。
- **建议**：要么在格的 L3 里加一个直接发岗位收件人的发送方场景（例如探针或 `erp/*` 的到期提醒），断言持有人收到、投影变化后等待的意图被及时收尾；要么在 itest 里起真实的 `flow.Employees`（喂员工事件），至少测 `EmployeesChanged` 会排一轮且不重复排；并把 `itest/AGENTS.md:9` 改成实际覆盖情况。

---

## 建议改

### S1 必须送达的类别到期即丢：与协议 10 矛盾，NT07 与 NT12 也互相矛盾

- **位置**：`N/internal/delivery/route.go:10`（`case expired:` 排在 `Mandatory` 之前）；向量 `route-expired-mandatory`（`P/vectors/notification-intent.json`）；`P/spec/18-notification-intents.md:16`（P18.6 没有必须送达的例外）；`docs/zh/06-protocols/10-external-integration.md:187`（“超过时效丢弃并计数，必须送达的类别转站内消息并告警”）；`N/docs/design.md:57`（NT07：“必须送达的类别转站内就是照常写站内消息”）对 `:62`（NT12：过期了就告警，“转站内不适用”）。
- **问题**：协议 10 的意思是必须送达的通知不会因超时而消失（最终落到站内）；本组件站内就是唯一渠道，按协议应“到期也写站内并告警”，而代码与向量是“到期不写、只告警”。NT07 的说法读起来是前者，NT12 是后者。
- **会怎样出错**：安全提醒、法律通知在本组件积压或岗位等投影超过到期后静默不出现在收件人的站内消息里（只有一条日志），而协议 10 承诺它们必达。
- **建议**：先定一种：若按协议 10，`Route` 对必须送达的类别在到期时仍 `written`（另记告警），改向量与 P18.6；若维持现状，就改协议 10 的这一句与 NT07，明确“首批到期即丢、只告警”。

### S2 无法解析的载荷被报成“冒充”（`not_the_sender`）

- **位置**：`N/internal/intents/intents.go:43-48`（`parsed` 为假时 `SenderIsSource` 也为假）；`N/internal/intents/admit.go`（`!SenderIsSource` 最先判断）。
- **问题**：载荷不是 JSON，或字段类型不对（如 `collapse_seq` 是字符串、超出 int64）时 `json.Unmarshal` 进结构体失败，答案是 `not_the_sender`。
- **会怎样出错**：排障的管理员与安全审计看到的是“发送方冒充别人”，实际是发送方的格式错误；安全告警被误报。
- **建议**：“是不是发送方”只依赖能否从原始 JSON 读出 `sender` 字符串（用 `map[string]any` 读），读不出时按 `malformed`；向量的 `admit-not-the-sender-and-malformed` 语义保持“两者都错时报冒充”，但“读不出 sender”应单列。

### S3 被拒的意图在重投时重复记录、重复审计，且审计操作名用错

- **位置**：`N/internal/intents/intents.go:166-179`（`reject` 每次都插新行、写审计，没有按“发送方 + 意图身份”去重）；`:176`（`Operation: core.OpRejectRead`）。
- **问题**：至少一次的投递（以及补发 P6.38）会让同一条被拒意图写多行与多条安全审计；审计记录的操作是“读被拒列表”的权限键，与发生的事无关。被拒走 `Audit.Write` 而不是 `Audit.Denial`，没有每分钟预算（P8.23）。
- **会怎样出错**：一个出错的发送方持续发坏意图时，审计被刷屏，排障列表里同一意图出现多次；审计的读者会把它理解成“某人读被拒列表被拒绝”。
- **建议**：`rejected_intent` 加 `(sender, intent_id, reason)` 唯一并 `ON CONFLICT DO NOTHING`，只有新插入时写审计；操作名用一个描述认收的名字（如 `infra.notification.intent.admit`，不作为权限键），或改走 `Audit.Denial` 享受预算。

### S4 被取代（或迟到作废）的投递意图没有投递结果事件，BRICKKIT 说法与设计不一致

- **位置**：`N/BRICKKIT.md:11`（“每个意图处理完发一条事件”）对 `N/docs/design.md:60`（NT10：“每个投递意图成为 `done`”）；`N/internal/intents/intents.go:118-130`（`supersede` 把 `pending` 改成 `superseded`，不发事件）；`N/contract/events/infra.notification_delivery.recorded.v1.schema.json` 的描述。
- **问题**：一个等岗位的意图已经给部分主体写了消息，随后被更新的序号取代——这些已写的结果永远不会出现在任何结果事件里。
- **会怎样出错**：订阅投递结果的下游（以后的统计、渠道对账）会少掉这部分已写入的投递，且无法分辨“还在投”与“已被取代”。
- **建议**：要么在取代时为有结果的旧意图也发一条结果事件（带 `superseded` 标记），要么在 BRICKKIT、NT10 与事件契约里写清“被取代、迟到作废、撤回意图不发结果事件”。

### S5 每个投递意图都入队一轮完整的投递；一个批次在一个事务里逐行处理，锁持有时间随收件人数放大

- **位置**：`N/internal/intents/intents.go:98`（每个投递意图 `Enqueue(JobDeliverNow)`，不像 `EmployeesChanged` 那样“已有待办就不再排”）；`N/notification/module.go:93-94`（`MaxAttempts: work.Unlimited` 的队列作业）；`N/internal/delivery/delivery.go:58-80, 190-210`（一批 100 个意图、每个最多 1000 个主体，每个主体 3–4 条语句，全在一个事务里且持有这 100 行的 `FOR UPDATE`）。
- **问题**：突发 1 万个意图会排 1 万个队列项，每项都跑一遍完整的 `Deliver` 扫描；最坏一个事务 40 万次往返，期间同键的取代（`supersede` 的 `UPDATE intent`）要等它，可能撞锁超时后重试。
- **会怎样出错**：积压时数据库负载与延迟被放大，审批消息的撤回被投递事务挡住；某个意图持续失败（如目录查询出错）会让整批与之后每一轮都回滚，无限重试的队列项堆积。
- **建议**：入队前同样判断“已有待处理的 `deliver-now`”（或用 SDK 的单例/合并入队）；按主体数而非意图数分批，`delivery` 的“是否已有结果”与偏好改成一次集合查询；单个意图出错时记下并跳过，不拖垮整批。实测一次大意图的耗时后再定批大小。

### S6 itest 有几处断言守不住它声称的规则

- **位置与问题**：
  - `N/itest/senders_integration_test.go:61-64`：数整个 schema 的 `security_denial` 行 `>= 4`，不按这 4 个意图身份对应；别的拒绝（任何路径写的安全拒绝）都能凑数，“各有安全审计”没有被逐条守住。建议按 `target` 的意图身份逐条断言。
  - `N/itest/senders_integration_test.go:54`：`test/evil` 不被订阅只用“被拒列表里没有它”与随后一次计数来证，而等待条件只等另外四条（另一个流），即使 `test/evil` 被订阅、只是还没处理到，也会通过。建议断言消息系统上没有这个订阅的消费者，或先发 evil、再发一条 `test/buy` 的哨兵并等哨兵处理完之后再断言。
  - `N/itest/delivery_integration_test.go:39-71`（merging）：每个新序号都在旧意图 `done` 之后才发，“还没投递的意图被取代后不再投递”（`UPDATE intent ... state='pending'` 那条路径）没有被执行到。建议用等投影的岗位让旧意图停在 `pending`，再发新序号，断言旧意图 `superseded`、没有任何消息。
  - `N/itest/inbox_integration_test.go`：NT08 的“游标分页”“已撤回的不算未读”在 inbox 步都没有测（全部 `limit=200`），而 `itest/AGENTS.md` 的索引把整条 NT08 归给它。建议加一页 `limit=1` 的翻页与一条撤回后的未读数断言，或把索引改成实际覆盖。
  - 并发：NT04 写“结果不依赖到达顺序与并发”，占位行 + `FOR UPDATE` 的锁是关键（AGENTS 易错点），但没有任何测试并发送同一合并键的两个首个意图。建议加一个并发用例（两个分区同时到达），断言只有序号大的生效。
- **会怎样出错**：对应的实现改坏后测试仍然全绿。

### S7 L3 的偏好场景区分不了“按偏好不投”与“根本没投”

- **位置**：`tools/be-acceptance/conformance/scenarios/test_notification.py:76-87`。
- **问题**：关掉偏好后睡 5 秒再打开，最后只断言“关掉时的那条没有消息”。两条意图的身份不同、分区不同，“打开后那条到了”不能证明“关掉时那条已经处理过”；如果那条意图根本没被收下（订阅坏了、被拒），断言同样通过。反过来，若 5 秒内没处理完，它会在偏好打开后被写入，测试偶发变红。
- **建议**：以投递结果事件或 `rejected-intents`/一个只读的排障接口确认那条意图的结果是 `preference_off`；或者在偏好关闭期间等待，直到能观察到它已处理（例如它的结果事件出现在 `infra.notification` 流上），再打开偏好。

### S8 设计、P18.10 与 SDK 对“什么时候发撤回”的描述不一致

- **位置**：`SDK/flow/intents.go:32-37`（任务不是 `pending` 或没有候选时一律发撤回：建任务就 `paused`、`paused` 换原因时也发）；`P/spec/18-notification-intents.md:30`（P18.10 只写“任务离开 `pending` 时”发撤回）。
- **问题**：行为本身无害（撤回只做取代），但规范没写；新的接收方实现照 P18.10 会以为不会收到没有先导投递的撤回。
- **建议**：P18.10 补一句“任务每次以非 `pending` 状态发布时都发同序号的撤回意图（包括建任务即暂停）”，或代码只在“上一版本是 `pending`”时发。SDK 测试另补到期取任务截止（`DueAt`）与超过 1000 个候选的截断两条（P18.10 写了，`flow_integration_test.go:677-714` 没测）。

---

## 可不改

### C1 `itest/AGENTS.md` 说“按下表的顺序跑各步”，实际顺序不同

`N/itest/AGENTS.md:10` 对 `N/itest/endtoend_integration_test.go`（`delivery, merging, preferences, positions, expiry, inbox, senderCheck, recoveryChecks`）：`expiry` 在表里排在 delivery 文件、实际在 `positions` 之后，且各步共享假目录的全局“完整”标志，顺序有依赖。改成“按 `TestNotificationEndToEnd` 里的顺序”即可。

### C2 “到期不晚于发生”与形状错误共用 `malformed`，被拒列表里分不出来

`N/internal/intents/admit.go:44-45`、`N/contract/openapi.yaml:106`（原因枚举只有三个）。P18.8 把它单列，BRICKKIT 也单列；排障时看不出是哪一种。可加 `expires_before_occurred`（契约只加不改）。

### C3 被拒但已通过形状核对的带键意图会留下序号 0 的占位行

`N/internal/intents/intents.go:56-66` 在 `Admit` 之前插占位行；类别不在目录或到期早于发生被拒时，事务照常提交，占位行留到 400 天后才清。无功能影响，可在拒收分支删掉或把占位放到判定之后。

### C4 `EmployeesChanged` 直接查询 SDK 内部表 `be_work_item`

`N/internal/delivery/delivery.go:300-301`。是对 SDK 内部结构的耦合（列名、状态值改了这里静默失效，且见 M4 没有测试）。可请 SDK 提供“同名队列项已待处理就不重复入队”的入队选项。

### C5 订阅名可能撞名

`N/internal/intents/intents.go:31-33`：`erp/a-b` 与 `erp-a/b` 都得到 `intents-erp-a-b`。当前的领域名不含连字符，实际不会发生；可以把 `/` 换成别的分隔符。

### C6 协议 10 的“岗位展开为当前的持有人”与 P18.4 “按发送方给出的日期”措辞不一致

`docs/zh/06-protocols/10-external-integration.md:173` 对 `P/spec/18-notification-intents.md:14`。改成“按意图给出的日期（没给时是投递当天）的持有人”。

### C7 小处

- `N/internal/intents/intents.go` 包注释说负责“被拒意图的清理”，清理在 `delivery.Purge`。
- `N/docs/design.md:42` 数据表只说岗位会记 `unresolvable`，代码还会记 `expired`（NT05 正文写了）。
- 流程内核的标题是英文（`"Purchase requisition " + 单号`），P18.5 要求“发送方按部署的语言写好”；客户端可用模板重渲染，影响小。
- 撤回后的消息照常列出（NT08 有意如此），标题只含单据类型与单号，未见越权内容；以后若标题带业务字段，要与协议 10“通知里能看到的不超过系统里能看到的”一并考虑。

---

## 核对过、没有发现问题的

- 合并键并发：占位行 + `FOR UPDATE` 让同键的两个首个意图依次判断；`supersede` 在读已提交下等投递事务释放旧意图的行锁后，对已写成的消息逐条标撤回，不会漏撤。
- 同一意图的不同事件身份并发到达（`Seen` 在锁之前读）：后到的那条撞主键报错、重试后成为 `duplicate`，结果正确。
- 我的消息与偏好：每条查询都带 `principal = 调用者`，别人的消息 404，全部已读只改自己的；偏好对必须送达的类别拒改，投递时也不看旧的关闭行。
- 消息只存标题、链接、模板与参数，不授予任何权限；流程内核的收件人是账号，与令牌的 `sub` 同一空间。
- 发送方 `erp/purchase`、`erp/payment` 的清单、`contract/events/*notification*`（`$ref` 协议的 schema）与 BRICKKIT 的说法一致；`prepare.py` 按格里放置的发送方设置 `NOTIFICATION_INTENT_SOURCES`，权限键与资源登记齐全。
