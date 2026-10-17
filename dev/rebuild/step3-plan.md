# 实验第 3 步：Python 的 SDK 子集、外壳启动器、两种语言的探针与一致性剖面

> 2026-10-17 起草。依据：[experiment-plan.md](experiment-plan.md) 的“探针组件”“SDK”表的 Python 一列、“各仓库先做到什么程度”的 `be-acceptance` 一行与第 3 步；[协议 18](../../docs/zh/06-protocols/18-sdk-and-conformance.md)；[组件协议与语言的锁定的技术栈](../../docs/zh/04-foundations/07-component-protocol-and-languages.md#锁定的技术栈)；`be-protocol` `v3.0.0-alpha.1` 的第 1–9 章与向量；第 2 步（[step2-plan.md](step2-plan.md)）的做法与实测发现。每个任务做完：提交到对应仓库、更新本页的进度、继续下一个（连续推进）。

## 范围

| 仓库 | 本步做到 |
| --- | --- |
| `be-sdk-python` | 实验计划“SDK”表的 Python 一列：运行时入口与合并安全（子集）、配置、错误、观测基本档、单跑启动器、外壳启动器（完整）、数据库的事务与迁移、发件表与两个运输适配器上的发布与消费、组件间调用（完整）、身份核验与操作检查、审计的发送、大消息的凭证检查（完整）。后台工作项、列表、投影、分区、幂等键等不做，功能矩阵如实标 `not_implemented` |
| `be-acceptance` | 探针组件 `test/probe-go` 与 `test/probe-py`（同一份契约，`Echo`、`Work`、`Write`、`Relay`、大事件）；一致性套件的最小剖面（端口、健康、表与角色、消息信封、日志与指标），对两种探针都通过 |

不做：负载驱动、资源采集与报告（第 4 步）；`infra/print` 组件本身（业务组件，按计划在之后的步骤）。

## AI 定下的取舍（记进复核清单）

| 项 | 取舍 | 理由 |
| --- | --- | --- |
| Python 版本 | 3.14（宿主机即 3.14.4，镜像用同版本的官方镜像） | 实验计划要求宿主机与镜像的版本对齐 |
| 依赖管理 | `uv`（本机已装 0.12.1），`pyproject.toml` 加 `uv.lock`，版本精确 | 确切版本以依赖锁为准（锁定的技术栈一节） |
| 包名 | 分发名 `be-sdk`，导入名 `besdk`；从 `3.0.0a1`（PEP 440 写法，对应 `3.0.0-alpha.1`）起 | 沿用旧仓库的导入名，组件代码的导入路径不变 |
| 协议的机器可读部分 | 按精确的标签（`v3.0.0-alpha.1`）取 `be-protocol` 的 `vectors/`、`migrations/`、`migrations-bus/`、`capabilities.json`，放进包内 `besdk/_protocol/`（迁移要随包分发），附来源的标签与提交；`make protocol-check` 重新取一次并逐字节比较，向量另按 `SHA256SUMS` 核对 | Python 不能像 Go 那样按模块版本引用；拷贝必须可验证，不能手改 |
| 迁移入口 | SDK 自带（A111，用户 2026-10-17 选定），按 P5.11–P5.16，状态表与 Go 相同 | 见下 |

**冲突与决定：迁移工具。** 锁定的技术栈给 Python 定的是 `yoyo-migrations`；`be-protocol` 的 P5.12 要求两张状态表（`be_sdk_migrations`、`schema_migrations`）在组件 schema 里、形状与 golang-migrate 相同，“所以三种语言的 SDK 读写同一份状态”（同一个库可以先后由不同语言的实现迁移，组件换语言不用重建库）。yoyo 的状态表名与形状是固定的（`_yoyo_migration` 等），做不到。用户选定（A111）：Python SDK 自己实现迁移入口（迁移检查、迁移锁、状态表、每个文件一个事务、锁等待重试与阻塞者报告，按 P5.11–P5.16，Go 的实现约 300 行），把锁定的技术栈中 Python 的迁移一格改为“SDK 自带的迁移入口，纯 SQL 文件”（TypeScript 的 `node-pg-migrate` 同样做不到，一并改）；没有采用的是放宽 P5.12、各语言各用自己的状态表（换语言就要重新迁移，违背语言中立）。

## 任务

| 编号 | 任务 | 仓库 | 验收 | 状态 |
| --- | --- | --- | --- | --- |
| T3.1 | 仓库与骨架：主分支（第 1 步已重启）上建包结构、`pyproject.toml` 与 `uv.lock`、取协议的脚本与检查、`make test`（单元与向量）与 `make test-integration`（`be-postgres`、`be-nats`、`be-rustfs`） | `be-sdk-python` | 向量读取通过 `SHA256SUMS` 核对；`make protocol-check` 通过 | 完成 |
| T3.2 | 运行时与单跑：组件定义与模块接口、配置（声明的键、严格解析、`_FILE` 密钥与重读）、错误对象与原因目录（problem+json、gRPC 状态）、观测基本档（标准 `logging` 的 JSON 格式、每成员一个指标注册表、OpenTelemetry）、FastAPI 跑在 uvicorn 上（单进程、单事件循环）、单跑启动器（`serve`/`migrate`、退出码、健康与就绪、自描述、计时源检查、体面停止）、合并安全检查（AST 扫描：读进程环境、进程级初始化、退出进程、绕过 SDK） | `be-sdk-python` | 向量 `errors`、`config-parse` 通过；合并安全检查对 SDK 自身通过、对故意加入的违规报出 | 完成 |
| T3.3 | 外壳启动器：按 `BRICKKIT_SERVED_MEMBERS_CONFIG` 构造成员；按安装的分发元数据核对成员版本，拒绝可编辑安装或路径安装（对应 Go 的 `replace`）；每个成员独立的端口与运行时；进程级键一致；同一数据库目标的成员共用一个池；拒绝条件一起报出；并行停止 | `be-sdk-python` | 与 Go 外壳同样的拒绝情形与“单跑与外壳行为一致”的测试 | 完成 |
| T3.4 | 数据库：`asyncpg` 池（按成员的预算，外壳中用外壳登录角色）、事务入口（`SET LOCAL ROLE`、`search_path`、超时；`40001`/`40P01` 重试；错误映射；不许嵌套）、外壳中按成员区分语句缓存（P5.4）、启动检查、迁移入口（按上面的决定）、UUIDv7、单号序列 | `be-sdk-python` | 向量 `db-errors`、`migration-lint` 通过；0-12 的泄漏情形不出现；**同一个 schema 先由 Go SDK 迁移、再由 Python SDK 迁移时“已是最新”**，反过来也一样 | 完成 |
| T3.5 | 组件间调用：`grpc.aio` 的服务端与客户端拦截器、HTTP 客户端；出站时限、重试决定与预算、熔断、并发上限、结果分类与向上报告、转述不重试；请求 ID、追踪、幂等键的转发；事务内不发调用 | `be-sdk-python` | 向量 `outbound-timeout`、`retry-decision`、`retry-budget`、`circuit-breaker`、`call-outcomes` 通过；Go→Python→Go 的调用链“只有一层重试” | 完成（跨语言调用链在 T3.7 完成） |
| T3.6 | 事件：发件表（同一组表）、锁内编号与纪元、转发、CloudEvents 信封、JetStream（`nats-py`）与 PostgreSQL 队列适配器、消费者（收件表去重、死信、跳数）、大消息的凭证检查（`aioboto3`）；运输检查套件移植 | `be-sdk-python` | 向量 `partition`、`envelope` 通过；运输套件在两个适配器上通过；Go 产生、Python 消费与反方向，在两种运输上都只生效一次 | 完成 |
| T3.7 | 身份与操作检查、审计的发送：JWT 核验（PyJWT，公钥刷新与限速）、服务身份（部署 mTLS 与允许的调用组件）、授权视图的持有与核验（P8.9–P8.13）、段的单对象求值（P8.14–P8.16）、资源与操作的声明；本地审计表、编号与发送 | `be-sdk-python` | 向量 `jwt-verify`、`canonical`、`segment-eval`（单对象部分）通过；看不见答 404、无权答 403；审计记录经 mTLS 到达（假的）审计组件 | 完成 |
| T3.8 | 探针：契约（HTTP 与 gRPC 两面，`Echo` 1 KiB/60 KiB、`Work`、`Write`（事务内写一行与发件行）、`Relay`（收到事件调用下一个探针）、大事件），Go 与 Python 各实现一次；`be-acceptance` 中一个仓库放多个组件（目录前缀的标签），组件 ID `test/probe-go`、`test/probe-py` | `be-acceptance` | 两种探针单跑与互相调用、互发事件；`brickkit lint` 通过 | 完成 |
| T3.9 | 一致性剖面：从外部检查运行中的组件——端口与健康、就绪、自描述、表与角色（状态表、SDK 表、角色与授权）、消息信封（头与摘要）、日志（结构、无凭据）与指标 | `be-acceptance` | 两种探针都通过同一剖面；对故意做坏的变体判红 | 待做 |
| T3.10 | 收尾：`be-sdk-python` 的功能矩阵（`features.json`，按协议的能力清单）；发 `be-sdk-python` 的 `3.0.0a1` 与 `be-acceptance` 探针的标签（发布前列出标签请用户确认）；更新装配项目的子模块指针与交接 | 两个仓库、本项目 | 功能矩阵与协议一一对应 | 待做 |

## 进度

（每完成一个任务在这里加一行：日期、提交、结论。）
- 2026-10-17 T3.1 完成：`be-sdk-python` `64bea8e`。主分支上建 `pyproject.toml` 与 `uv.lock`（Python 3.14；FastAPI 0.143、uvicorn 0.54、grpcio 1.84、asyncpg 0.32 等锁定的技术栈全部能在 3.14 上解析与导入）；`besdk/_protocol/` 是 `be-protocol` `v3.0.0-alpha.1`（`659215e`）的向量、迁移与能力清单，`scripts/protocol.py` 按标签取与逐字节核对（`make protocol-check`），向量另按 `SHA256SUMS` 核对；清掉了旧代码留下的缓存与虚拟环境（只有缓存，没有源码）。
- 2026-10-17 T3.2 完成：`be-sdk-python` `0996347`（`config`、`errs`）、`63df33c`（`obs`、`http`、`reqctx`、`clock`、`component`、`runtime`）、`6ccd685`（`host`、`launcher`、`mergesafety`）。向量 `config-parse`、`errors` 通过；HTTP 链（请求 ID、追踪、截止时间、准入、请求体上限、错误映射、崩溃恢复、访问日志与指标）、平台端点、单跑启动器（配置错误一次报全、模块装配失败不崩溃、就绪、体面停止中进行中的请求做完）都移植了 Go 的测试；另用真实进程验证 SIGTERM 的体面停止。合并安全检查用 AST 解析并解开别名，对 SDK 自身按允许清单通过。
  - **定下的设计**：每个成员的日志器是直接构造、不注册到 `logging` 全局管理器的 `logging.Logger`，从不传给根日志器；uvicorn 换掉它自己的信号处理（信号归启动器或外壳），套接字在启动前绑定，端口占用在就绪前就失败；处理函数拿到 `Context`，与 Go 同名同义，路径参数用 FastAPI 的 `<built-in function id>` 写法。
  - **实测发现**：请求范围的值（截止时间）最初用 `ContextVar.set` 只缩短不重置，同一任务上下文里的下一个请求继承了上一个的截止时间；测试抓到后改为每个请求设值并在结束时复位，不依赖服务器怎样调度任务。合并安全测试里有一处期望写错（别名的使用报在导入处），按测试错误改正。
- 2026-10-17 T3.3 完成：`be-sdk-python` `b0bdfbf`（`shell`）。按 `BRICKKIT_SERVED_MEMBERS_CONFIG` 承载成员，各自的端口与运行时，外壳自己的端口给出全部成员的就绪、带成员的自描述与按 `component` 标签区分的指标；拒绝情形与 Go 相同并一次报全：没装进来的成员、定义或已安装分发的元数据版本不同（语义化版本与 PEP 440 按含义比较，`3.0.0-alpha.1` 等于 `3.0.0a1`）、从本地路径安装（PEP 610 的 `direct_url`，对应 Go 的 `replace`，只有 `SHELL_ALLOW_REPLACE` 时放行并警告）、成员配置不合法、进程级键不一致；外壳不执行迁移。同一数据库目标共用一个池随 T3.4 加入。
- 2026-10-17 T3.4 完成：`be-sdk-python` `12e565b`（`db`：键与设置、池、事务入口、启动检查、单号、迁移检查与迁移入口；启动器与外壳接上数据库）。向量 `db-errors`、`migration-lint` 通过；集成测试在 `be-postgres` 上：事务内的角色、`search_path`、超时与应用名在事务结束后不留在连接上，外壳登录角色在事务外读不到成员的表（CK-DB-01、CK-DB-03）；前台预算为 1 时第二个事务约 2 秒答 `SERVICE_BUSY`（CK-DB-02）；嵌套被拒、序列化冲突重做整个事务、锁等待答 `LOCK_TIMEOUT`；迁移连跑两次、中途失败的文件不留痕迹且修好后可再跑、锁等待超时点名阻塞者、两个实例同时迁移每个文件只执行一次、被拒的迁移什么也不改（CK-DB-05、CK-DB-06）；单号回滚不留缺号、并发不重号、导入的最大值之后继续（CK-DB-07）；单跑的组件迁移并服务，密码错误退出 78、库不存在退出 69（CK-DB-04）；外壳中两个成员共用外壳登录角色的一个池，数据库只看到外壳登录角色。**语言中立的验证**：同一个 schema 先由 Go SDK（`v3.0.0-alpha.1` 的迁移入口）再由 Python SDK 迁移、反过来、以及两者同时迁移，状态表一致、每个文件只执行一次。
  - **定下的设计**：迁移入口自己实现（A111），状态表与 golang-migrate 同形状（一行，`TRUNCATE` 加 `INSERT`），迁移锁用 golang-migrate 的咨询锁键（`crc32(schema \0 table \0 database) × 1486364155` 取 32 位），所以两种语言互斥；每个文件作为一个简单查询执行，即一个隐式事务；`PG_POOLER_PREPARED=false` 时不缓存语句。
- 2026-10-17 T3.5 完成：`be-sdk-python` `13f908e`（`calls`、`errwire`、`system`；运行时的 `rt.http`、`rt.grpc`，启动器与外壳承载系统面）。五份调用向量全部通过；真实服务器上的 A→B→C：gRPC 与 HTTP 两条链里 C 被调 3 次、B 只被调 1 次，A 收到 B 原样转述的 `DEPENDENCY_UNAVAILABLE`（`dependency=demo/c`），A 的预算与熔断不受影响；请求 ID 与用户凭据传到 C，B 的截止时间不超过 A 这次尝试的时限；组件自己的错误（含 metadata 与字段错误）原样穿透；连接失败重试后上报；事务内的调用被拒（`NETWORK_IN_TX`）；单跑的系统面在停止时让进行中的调用做完。
  - **定下的设计**：每次调用的标志（幂等、幂等键）放在保留的元数据里，由客户端拦截器读取并去掉，所以生成的存根原样可用；系统面用生成代码的 `add_*_to_server` 登记，SDK 录下它的方法再包上链；系统面暂时不带 TLS，与 Go 先 T2.5 后 T2.8 的顺序相同，部署 mTLS 随 T3.7，跨语言的调用链测试（Go 的系统面只接受 mTLS）也随 T3.7。
  - **实测发现**：①合并安全检查原来把整个 `httpx` 包算违规，连异常类都报，收窄为客户端与请求函数；②一处测试期望写错：组件原因的 HTTP 状态（例如 409）经 gRPC 不传递，转述后按码取（400）。P3.3 只要求 `reason`、`domain`、`metadata` 不变，Go 也如此；但这意味着组件 C 声明的状态码经 B 转述到用户面时会变，**记下待评估**（可以把声明的 HTTP 状态放进 ErrorInfo 的 metadata，需要先改协议）。
- 2026-10-17 T3.6 进行中，先修了 Go 的一处缺口：移植事件时发现 Go 主机构造生产者时对象存储传的是空、消费者没有读取器，**真实组件既发不出也收不到超过 64 KiB 的事件**；第 2 步的“大消息凭证检查”只在包内测试里用内存假存储验证过，功能矩阵标的 `verified` 过头了。补上：`be-protocol` `025cdea`（第 2 章加成员级的 `OBJECT_STORE_*` 键；P6.14 写具体：生产者在转发时写到自己的桶与前缀下的 `events/<事件身份>`，引用是有效期等于运输保留的预签名只读地址，补发时重新签发，订阅者用普通 GET 取回、不持有存储凭据），`be-sdk-go` `ce12059`（`aws-sdk-go-v2` 的存储端口接进成员；在 `be-rustfs` 上测往返、篡改被拒，两个运行中的组件之间 65 KiB 以上的载荷在两种运输上完整到达）。这两处改动随 `3.0.0-alpha.2` 发布（第 3 步收尾时，先列出标签请用户确认）。
- 2026-10-17 T3.6 完成：`be-sdk-python` `8e65e61`（事件核心、发件表与编号、转发、消费者、凭证检查、JetStream 与 PostgreSQL 队列适配器）、`dea8357`（接进成员与两种主机）。向量 `partition`、`envelope` 通过（信封与 Go 逐字节相同，JSON 按 Go 的写法转义）；运输一致性套件 16 项在真实的 JetStream 与 PostgreSQL 队列上全部通过，对丢确认的假适配器判红；发件行只随业务提交、两个编号者并发不重不漏、推进部署恢复代次后新纪元从 1 编号并记下分叉点、转发按位置顺序且不重发、重复投递只生效一次、最后一次失败只记一条死信、跳数超限按失败、`be-rustfs` 上的大载荷经预签名地址到达。**语言中立的验证**：Go 组件（`tests/interop/goevents`，用 `be-sdk-go` `b33ec10` 构建）与 Python 组件在 JetStream 与 PostgreSQL 队列上双向收发事件，含超过 64 KiB 的载荷，每个事件只生效一次。
  - **实测发现**：①运行中的任务在事务里被取消时，事务入口把取消改写成 `REQUEST_CANCELLED`，转发器因此停不下来、每次停止都等满停止时限；改为取消一路传出（事务入口与两个请求层）。②处理函数抛出异常会让 PostgreSQL 队列的工作协程退出；改为按否认处理并报告。③**两种 SDK 共有的缺口**：订阅方先于任何生产者启动时，JetStream 上流还不存在，成员启动失败；改为订阅时也确保流存在、设置相同、已存在不改（P6.17，`be-protocol` `2e672f3`，Go `b33ec10`），两套运输套件都加了这一项。④测试里共用的队列留有之前的消息，新的持久订阅会从头读到它们；有顺序或计数断言的测试改用各自的流。

- 2026-10-18 T3.7 完成：`be-sdk-python` `a2f53b8`（`identity`、`authz`、`guard`、`audit`；系统面只走 mTLS 并按证书核对调用方；出站通道拒绝明文、证书轮换后新连接用新证书）。向量 `jwt-verify`（25 项）、`segment-eval`（单对象部分，含逐记录的对外错误）、`canonical`（段的摘要）通过；Go 的视图与安全测试移植（有效期从发出请求起算、迟到的回答不延长、随机数不符不续期、恢复代次回退停用、停顿与墙钟跳变作废、不适用的资源类型、停用账号）；受保护路由答 401（不记凭据，只记问题名）、看不见 404、可见无权 403、没有视图 503 可重试，撤销在下一次核验后生效；缺配置退出 78、缺声明退出 1 且有日志。真实数据库上审计记录随业务事务写入、敏感读取先记后放、拒绝超过每分钟 20 条后只计数并在窗口结束后补一条汇总，经 mTLS 到达假的审计组件、带回执、编号无缺口。**语言中立的验证**：Go→Python→Go 的调用链（`tests/interop/gochain`，`be-sdk-go` `940735a`）全程 mTLS：C 被调 3 次、B 只被调 1 次，A 收到 B 原样转述的 `DEPENDENCY_UNAVAILABLE`（`dependency=demo/goc`），C 按证书认出调用方是 B，请求 ID 贯穿两种语言。T3.5 里用明文系统面的测试改为 mTLS。
  - **定下的设计（AI 决定）**：①P8.5 扩展：服务证书同时带由 SPIFFE 身份派生的 DNS SAN `<组件 ID 中的 / 换成 .>.component.<部署身份>`，成员加载证书时两者都核对；原因是 Python 的 `grpcio` 客户端只能按主机名核对服务端证书，用这个名字核对与按 URI 核对等价（`be-protocol` `a8abd24`；Go 加载时核对、测试签发带上，`be-sdk-go` `9009f30`）。部署工具签发证书时要带上这个名字（第 5 步做身份与授权组件时落实）。②Python 的出站通道随证书代次重建，生成的存根绑定的调用对象按代次重新绑定，旧通道在 30 秒宽限后关闭；服务端用 `grpcio` 的动态证书。③Python SDK 没有后台工作项，审计转运作为成员的任务运行（编号在计数器锁内、回执按 ID 幂等，多副本同时运行安全），与 Go 的单例工作项算法相同。④授权截止时刻改为每个范围一个可变单元：`Subject.check` 用到有效期更短的分片时收紧到范围结束；在任何范围之外不留下值（测试抓到最初的写法会把截止时刻留在上下文里）。
  - **实测发现**：①**两种 SDK 共有的偏差**：可见性未知而动作资格明确不成立时，向量要求 `PERMISSION_DENIED`（安全 01：已知事实不匹配按动作规则拒绝），Go 的 `Check` 先判未知答了 `AUTHORIZATION_UNPROVABLE`；Go 的向量测试没有核对对外错误，所以一直没发现。改为由判定给出错误（Go `Decision.Err`、Python `Decision.error`），两边测试都逐记录核对 `read_error` 与 `action_error`（`be-sdk-go` `940735a`；把顺序改回去时 Go 测试报 5 处）。②新的构建失败（缺声明、证书不对）原来退出 1 却没有任何日志，因为启动器以为 `BuildError` 已经记过；改为构建在抛出前记录。③后台调用需要请求上下文里的截止时间（P4.4），只用 `asyncio.timeout` 时审计转运每次都被调用层以 `DEADLINE_BUDGET_EXHAUSTED` 拒绝；改为设置截止时间范围。④`grpcio` 的服务端没有设置最低 TLS 版本的入口（Go 要求 TLS 1.3）；Go 与 Python 互连时实际协商 TLS 1.3，记下待评估。
  - **复查（子代理，只读）**：没有放行规范要求拒绝的请求，凭据不进日志。改了：①**两种 SDK 共有**：核验撞上自己的时限（2.5 秒）后，下一次调度把“核验耗时 + 等待”当成间隔，超过 4.5 秒就判为停顿、作废全部分片，授权成员慢一轮就让 30 秒的读取视图失效；改为只计两次核验之间的等待（P8.10 写明，`be-protocol` `15125cc`；Go `facea0c`，Python `6bd2481`，两边的测试在旧代码上失败）。②**Go**：公钥集里有一个不认识类型的密钥就整次刷新失败、全部凭据答 503；改为跳过不认识的密钥（P8.2 写明，RFC 7517 第 5 节；Python 本来如此）。③Python：不带时区的时刻在段的有效期比较时抛异常（答 500），改为不成立（与 Go 相同）；拒绝的审计写入失败会改变拒绝结果，改为返回不抛出（P8.19）；未知 `kid` 的刷新会随请求超时被取消，改为属于公钥集的任务；时间声明须是有限数；证书轮换后其余调用形态也重新绑定；`pyjwt` 下限 2.10.1（CVE-2024-53861）；恢复代次与金额按 Go 一样严格解析。④Go 的小处：头部字段名按原样区分大小写、缺 `iss` 记为 `iss`、核验请求的 `held` 发空数组而不是 `null`。记下未改：Python 的 `grpcio` 没有设置最低 TLS 版本的入口；`sub` 不是字符串时两边记的问题名不同（只影响日志）；审计记录的值含非 JSON 类型时两边结果不同（都是模块的错误，Python 报清楚的错误）。
  - 测试部署的安全环境从测试目录提升为 SDK 的公开模块 `besdk.testing`（签发方、信任根、假的授权与审计组件，加成员数据库的准备 `provision`），供组件自己的测试与验收工具使用；只用于测试，组件代码不导入它。
- 2026-10-18 T3.8 完成：`be-acceptance` `a16bd5b`。`probes/go`（`test/probe-go`，用 `be-sdk-go` `940735a`）与 `probes/py`（`test/probe-py`，用 `be-sdk-python` `6bd2481`）实现同一份契约 `probes/CONTRACT.md`；`conformance/` 把它们当真实进程运行（建库与角色、`besdk.testing` 签发证书、`be-postgres`、`be-nats`、`be-rustfs`，先迁移再服务）：各自单跑通过全部操作；一起时在 JetStream 与 PostgreSQL 队列上，双向在 gRPC（mTLS）与 HTTP 两面调用 `Echo` 1 KiB/60 KiB 与 `Work`，双向互发 6 个事件（其中 1 个超过 64 KiB 走凭证检查），3 个转发成对下一个探针的调用。两个探针的 `brickkit lint`（按组件仓库检查）0 错误 0 警告；两个镜像都能构建（Go 98 MB，Python 224 MB），未知参数退出 64、缺配置退出 78；两个探针都过合并安全检查。
  - **定下的契约（AI 决定）**：用户面 `/api/probe/echo`、`/work`、`/write`、`/call`、`/seen`，缺省公开（探针没有受保护的数据，身份与授权组件就绪之前也能测通信），`PROBE_GUARD` 为真时按操作守卫；系统面 `/test.probe.v1.Probe/Echo`（`BytesValue`）与 `/Work`（`UInt32Value`），手写服务描述，不需要生成代码；下一个探针与对方的流由部署指定（`PROBE_NEXT`、`PROBE_PEER_STREAM`），不声明组件依赖，实验可以任意组合。转发在事务之外：Go 用 SDK 的后台工作项，Python 用自己的队列表与同样的认领规则（Python SDK 子集没有后台工作项，测出的转发代价因此含两种实现的差别，报告中写明）。
  - **定下的做法**：`component.yaml` 的 `configSchema` 由 SDK 的键清单生成（`probes/py/scripts/config_schema.py`），测试核对两个探针的清单与生成结果一致；容器内监听端口由镜像的 `PORT` 给出（BrickKit 只在 `mode: local` 时注入 `PORT`）；镜像与宿主机同版本（Go 1.26.0、Python 3.14.4、Alpine 3.24.2）。
  - **实测发现**：①对象存储的桶是部署要准备的资源，没有桶时大事件所在分区的转发一直重试（同一分区按序，后面的事件也停住），这是设计如此，部署工具要建桶（第 4 步做部署时落实）。②Go 的日志时间带本地时区偏移，Python 的是 UTC；T3.9 的剖面要定一种。③探针的操作键 `test.probe.*` 还没进项目注册表的权限键：开启 `PROBE_GUARD` 时才用到，随身份与授权组件（第 5 步）一起登记。
