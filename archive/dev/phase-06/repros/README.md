# R1 最小复现汇总

> 开发文档，只给本项目自己用；正式文档（`docs/`、根目录 `AGENTS*.md`、组件文档）不得链接本目录。
> 来源：`../design-round/sdk-redesign.md` §7.9 的十条假设，加两条补测（3b、4b，控制者裁决 bc）。每条一个目录，目录里的 `README.md` 有环境、步骤、原始输出和完整建议，`run.sh` 可以重跑。
> 汇总于 2026-10-02（phase A 收尾，lane X2）。"已落实到哪里"只列已经写进去的位置；be-protocol 由 lane X1 同步，写本表时还没进 be-protocol 的，列在文末。

## 汇总表

| # | 假设 | 结论 | 对设计的改动 | 已落实到哪里 |
|---|---|---|---|---|
| [1](r1-01/README.md) | Go 外壳里每个成员一个 `TracerProvider`、共用一个导出器，span 各归各的 `service.name`；otelgrpc 用成员自己的 provider | **部分成立**。每成员 provider + 共享导出器可行；但朴素地共享导出器或 BSP，第一个成员一停导出器就关，之后别的成员的 span 静默丢失（`Shutdown` 还返回 nil）；otelgrpc 不给选项就读全局 provider、全局 MeterProvider，传播器没装时每一跳都断 | 共享导出器只由平台在所有成员停完后关闭（成员各自的 BSP + 空 `Shutdown` 壳）；所有埋点显式传成员的 provider 和平台的传播器；全局只装传播器，全局 provider 设成外壳自己的；compconf 加两条外壳用例 | sdk-redesign P18.1、P19.3、§4.4 shell 09/10；apis §5、I-12；foundations 23、27；be-protocol P19.3、CP-SHELL-09/10 |
| [2](r1-02/README.md) | grpc-go：按 proto 方法选项生成的服务配置（retryPolicy + retryThrottling）生效；`MaxConnectionAge` 的 GOAWAY 之后透明重连 | **成立**。另三处细节：`maxAttempts` 含首发，原文"最多 3 次"有歧义且与 foundations 16 不一致；预算比字面紧（约 5 次失败就停、61 次成功才恢复）；预算按 ClientConn 计、每次 resolver 更新回满 | `maxAttempts: 3`（总共 3 次）三门语言统一；"按连接"改为"按 ClientConn，resolver 更新时回满"；"≤ 10 %"是稳态值；`maxTokens` 保持 10（裁决 m） | sdk-redesign P7.8、P9；foundations 14、16；be-protocol P7.8 |
| [3](r1-03/README.md) | grpc-js：同样两点；外加预算是否按成员、ping 限速 | **大部分成立**。重试和 GOAWAY 透明重连成立；`maxAttempts` 语义同 Go；预算按（进程，规范化目标）跨 channel 共享，resolver 更新不回满；服务端没有 keepalive 强制（`MinTime`）；grace 小于在途调用时会切断 | 预算范围按语言写明（Go / Python 按成员，TS 按进程；BFF 不进外壳所以等价）；`MinTime` 对 TS 不适用；`MaxConnectionAgeGrace` 必须大于最长入站截止时间；ts-proto 用 `outputSchema=true` 运行时推服务配置（裁决 az） | sdk-redesign P7.5、P7.8、§5.3；apis §4；foundations 14、16 |
| [3b](r1-03b/README.md) | （补测）ts-proto 和 Python protobuf 在运行时读得到自定义字段选项 `(be.v1.max_items)` | **成立**。TS 不在 `fileDescriptor` 的 field options 里，而在 `protoMetadata.options.messages.<Msg>.fields.<字段>.max_items`（短名，不带包名）；Python 用 `GetOptions().Extensions`。新发现：引入 `limits.proto` 会连带生成含 TS `enum` 的 `descriptor.ts`，Node 24 的类型擦除跑不了 | TS 生成选项加 `enumsAsLiterals=true`；上限表在注册时按方法建、默认 500 来自遍历每个 repeated 字段；besdk 附带 `be.v1.limits_pb2`；be 选项的短名要全局唯一；Go 的读取未测，Go SDK 实现时验证 | sdk-redesign P7.10、§5.3；apis §3、§4 |
| [4](r1-04/README.md) | asyncpg 和 node-postgres：`SET LOCAL ROLE` / `search_path` 之后，预编译语句缓存不会跨 schema 串用 | **成立，但缓存不能无条件开**。不串数据；形状不同时确定性报 `0A000` / `42804`，事务里不会自动恢复；提交、回滚后连接干净；没有 USAGE 时 search_path 项被静默跳过 | SDK 在 SQL 前加 `/* be:<schema> */` 让缓存键按成员区分（Python 保留缓存）；TS 保持未命名语句；平台 SQL 不用 `SELECT *`；`0A000` 不进自动重试；P10.7 的 USAGE 探测保留（裁决 ay） | sdk-redesign P10.2、P10.7；apis §2.3、§3、§4、I-3；foundations 03 |
| [4b](r1-04b/README.md) | （补测）pgx v5 同样的问题，`QueryExecModeCacheDescribe` 能否避开 | **默认模式与 asyncpg 同样报错；`CacheDescribe` 修不好**（列数不同 `08P01`，参数类型 `42804`）；前缀修好且最快 | Go 保持 `CacheStatement` + 前缀；foundations-data-platform DB-6 的 `CacheDescribe` 建议撤回；外壳里 `StatementCacheCapacity` 按成员数放大 | sdk-redesign P10.2；apis §2.3；foundations 03（正式文档里没有出现过 `CacheDescribe`） |
| [5](r1-05/README.md) | PG16 `GRANT m TO shell WITH INHERIT FALSE, SET TRUE` 之后 `SET LOCAL ROLE m` 可用，外壳角色自己没有成员表的权限 | **成立**。另三点：成员之间的隔离不由数据库保证（外壳角色能切到任一成员）；`pg_stat_activity.usename` 在外壳里永远是外壳角色，CP-DB-03 按角色数不出来；该语法 PG16 才有 | 外壳要求 PG16，单跑下限仍是 PG14（裁决 n）；成员隔离靠 SDK，门禁 `identity-literal-scan` 禁止组件代码 `SET ROLE`；每个事务 `SET LOCAL application_name = '<成员 ID>'`，CP-DB-03 按它计数（裁决 o） | sdk-redesign P10.2、P10.5、P10.7、P19.5；foundations 03、10、27，决策 0102；be-protocol P10.2、P10.5、P10.7、P19.5 |
| [6](r1-06/README.md) | golang-migrate、yoyo、node-pg-migrate 都忽略 `migrations/lifecycle.yaml`，状态表能放进组件 schema | **部分成立**。node-pg-migrate 默认读目录里全部文件，`lifecycle.yaml` 让迁移失败；它的默认锁是全库常量，两个 TS 组件同库并发迁移后一个失败；三者都用会话级 `search_path` / advisory 锁 | TS 迁移显式传 `ignorePattern`、由 schema 派生的 `lockValue`、`advisoryLockMode: 'wait'`；迁移连接是专用会话，会话级状态在这里允许；各语言的状态表名写死并列入 P11.11 白名单（裁决 o） | sdk-redesign P11.1、P11.3、P11.11、§5.3；apis §3、§4；foundations 08；be-protocol P11.1、P11.3、P11.11 |
| [7](r1-07/README.md) | nats.go、nats-py、nats.js 的 pull consumer：durable 命名、`DeliverAll`、`BackOff` 与 `MaxDeliver`、`InProgress` | **第 4 条不成立**。设了 BackOff 服务端就把 AckWait 改成 BackOff[0]；`Nak()` 不看 BackOff 立刻重投；InProgress 挡不住，同一条事件被并发执行两次。nats-py 的 `add_consumer` 是"创建或更新"，会悄悄改掉已有 durable | 服务端不设 BackOff，AckWait 30 s，MaxDeliver −1；`EVENTS_BACKOFF` 改成 SDK 的 `NakWithDelay` 表；SDK 判 `NumDelivered > EVENTS_MAX_DELIVER` → 写 DLQ（`Nats-Msg-Id dlq:<durable>:<seq>`）再 `Term`；durable 只建不改；pgqueue 和 busconf 同语义（裁决 ax） | sdk-redesign P2、P12.5、P12.7、P12.9、P12.12、§4.4；apis §2.7、§3、I-13；foundations 12、24 |
| [8](r1-08/README.md) | Fastify 5 同一进程起多个实例，各自监听、各自一套钩子 | **成立**。另两个细节：Node 只按 `connectionsCheckingInterval`（默认 30 s）检查 `headersTimeout`；`handlerTimeout` 默认答 503，且错误处理器里 ALS 为空 | TS SDK 固定实例选项（`headersTimeout` 5000 + `connectionsCheckingInterval` 1000、`requestTimeout` 30000、`keepAliveTimeout` 120000、`handlerTimeout` = 路由截止时间并改答 504）；错误处理器不读 ALS；Fastify ≥ 5.12（裁决 ba） | sdk-redesign P3.5、§5.3；apis §4；foundations 16 |
| [9](r1-09/README.md) | Casdoor：access token 的 `aud`；discovery + PKCE 能否在浏览器端走完 | **成立**。PKCE 在真浏览器里跨源走完；Casdoor token 的 `aud` 是 client_id，平台按 P5.3 天然拒收；refresh token 也是 JWT 且没有 `kid`。附带：默认 `tokenFormat: JWT` 把整条用户记录（86 个 claim，含 `passwordSalt`、`totpSecret`）放进 token | foundations 21 删去"PKCE 能否走通"的已知限制；iam 族契约写死 subject-token 的校验规则；iam-casdoor 3.0.0 改 `tokenFormat: JWT-Standard`、只开 `authorization_code`；Casdoor 镜像钉 v4.1.0（裁决 ag、aj、ak） | contract-infra-iam v1.0（K2）；foundations 21；sdk-redesign §7.5。**安全问题**（`admin.go:293`）待用户决定是先发 2.0.1 还是并进 3.0.0 |
| [10](r1-10/README.md) | Python 3.14 上 asyncpg、grpcio、pyarrow 的二进制 wheel 是否齐全 | **成立**，但 asyncpg 要 0.31.0（0.30.0 没有 cp314 wheel）；print 的 `psycopg2-binary` 要 2.9.13；3.14 标准库有 `uuid.uuid7` | Python 运行时定为 CPython 3.14；`asyncpg==0.31.0`；yoyo 的同步驱动用 `psycopg[binary]==3.3.6`；`uuid7` 用标准库；pyarrow 只在 `besdk[cold]`（裁决 bb） | sdk-redesign §5.3；apis §3；foundations 02 |

## 写本表时 be-protocol 还没含的

这些已写进 sdk-redesign 和 foundations，be-protocol rc.1 的对应条款由 lane X1 同步：

- P12.5 / P12.7：服务端不设 BackOff、MaxDeliver −1，SDK 执行延迟表和 DLQ（#7）。
- P3.5 或 TS 说明：Fastify 的 `connectionsCheckingInterval` 与 `handlerTimeout` 映射（#8）。
- P7.10：TS / Python 读 `max_items` 的位置，TS 生成选项 `enumsAsLiterals=true`（#3b）。
- `ddl/08-number-series.sql`：`besdk_number_allocations`（不是复现的结论，是同批裁决 ao，一并记在这里）。

## 还没做的

- Go 读取 `(be.v1.max_items)`（`proto.GetExtension`）没测，Go SDK 实现 P7.10 时顺手验证（#3b）。
- Node 上"每个成员一个 provider、共用一个导出器"没有单独复现，按 #1 的结论实现，由 compconf CP-SHELL-09 / -10 守住。
- pgx 把几条 `SET LOCAL` 合成一条 `set_config` 能省多少，留给 Go SDK 实现时测（#4b）。
