# SDK 重新设计（续）：三门语言的 API、外壳启动器、夹具组件、第四门语言

> 开发文档，只给本项目自己用；正式文档不得链接本文件。写于 2026-10-02（06b 设计轮，lane A）。
> 这是 `sdk-redesign.md` 的姊妹篇。那一篇里有协议（P1–P20）、compconf、现状盘点、迁移路径；本篇只写**签名和用法**。签名是 v0.6.0 的目标形状，pilot（阶段 C）可以在冻结之前修改；修改要同时改三门语言和本文件。
> **修订（phase A 收尾，lane X2）**：按控制者对九个 lane 报告的裁决（a…bc）和 R1 最小复现的结果（`../repros/README.md`）修订。be-protocol rc.1（`tools/be-protocol`）已经是规范正文，名字和说法不一致时以它为准，本文件只是设计记录。
> **修订（2026-10-03，lane L2b）**：随 brickKit v1.2–v1.3.1（裁决 bk1–bk14）补上：密钥文件的读取与重读（§1 第 7 条、§2.2、§3、§4，→ P2.7、P2.9、P2.12）；族地址键 `AUTHZ_GRPC_URL` / `IAM_GRPC_URL`（→ P2.10）；`job run` 入口（§2.1、§2.9，→ P14.8）；外壳启动器的停机与就绪（§5，→ P19.9、P19.10）。
> **修订（2026-10-03，rc.2 spec lane 的文档 lane）**：按阶段 B 第一波审查裁决接受三门 SDK 已实现的名字：Go `Spec.Manifest`、`Spec.Catalog`、`Spec.ErrorDomain`、`besdk.ResourceType`、`PermKey.List` / `On`、`Subscription.AggregateType` / `TransactionDocument`、`Runtime.Now()`；Python `manifest`、`error_domain`、`Subscription.aggregate_type`；TS `ComponentSpec.manifest`、`errorDomain`、`aggregateType`；命令行统一为 `migrate up|down <n>|status`、`job run <name>`，不认识的参数和不存在的任务名都以 64 退出；reason 用 `REQUEST_INVALID`、`DEPENDENCY_UNAVAILABLE`；§3、§4 末尾列出接受的语言差异。

## 0. 怎么读

- §1 是三门语言共同遵守的规则。§2 是 Go，写得最全，作为参照；§3 是 Python，§4 是 TS，只写和 Go 不同的地方。
- 每个 API 后面的 `→ Pn` 指向它实现的协议条款。
- §8 是 v0.5.0 到 v0.6.0 的名字对照表，迁移组件的 lane 直接查它。

## 1. 共同规则

1. **名词相同、大小写各按语言**（主文件 §5.2）。
2. **上下文里装的东西相同**：截止时间、trace、request id、`Access`、`System`、"在事务里"标记、正在处理的事件（ID、hop、causation）。Go 显式传 `ctx`；Python 用 `contextvars`；TS 用 `AsyncLocalStorage`，SDK 在每个入口（HTTP 钩子、gRPC 拦截器、事件 handler、Job 运行器）里设好。
3. **"没有"是一个明确的值，不是空串**：可选依赖没装时返回 `ErrDependencyAbsent` 或 `None` / `undefined`（→ P2.5）；没有用户时返回 `ErrUnauthenticated`。
4. **一切都有界**：池、并发、批量、等待、重试、日志行长度都有默认上限。签名里能写成"可选参数取默认值"的，就不暴露成必填。
5. **事务函数可以被重放**：`Store.Tx` 遇到 40001 / 40P01 会重跑传进来的函数，所以函数里只碰 `tx`。网络调用被守卫拦下（→ P8.4）。
6. **错误一律带 reason**：组件写 `Errorf(code, "REASON", meta, …)`；SDK 内部的错误用保留的 `be` reason（→ P4）。
7. **密钥只从文件读，变了就重读**（→ P2.7、P2.9、P2.12）。`secret: true` 的键都是 `mount: file`、以 `_FILE` 结尾，环境变量里只有路径。三门 SDK 一样：
   - 启动时校验：文件不存在或读不了，和缺必填键一样以 78 退出、点名键；
   - 组件只经 `Secret` 取值（Go `rt.Config().Secret(key).Current()`，Python `rt.config.secret(key).current()`，TS `rt.config.secret(key).current()`），从不自己打开文件；`String(key)` 对 `_FILE` 键返回的是路径；
   - 比较文件的修改时间和大小，两次比较最多相隔 30 s（可以另加文件系统监视）；变了就重读，记一条点名键的 INFO；文本密钥去掉恰好一个结尾 LF / CRLF，二进制用 `Bytes()` 逐字节取；
   - 变化之后读失败：保留上一个有效值，记 ERROR（只点名键），计 `be_secret_reload_failures_total{key}`；
   - SDK 内部的使用方：库连接池每建一条新连接调一次 `Current()`（`PG_PASSWORD_FILE`）；对象存储客户端成对读 `S3_ACCESS_KEY_ID_FILE` / `S3_SECRET_ACCESS_KEY_FILE`，变了就换客户端；iam 成员的签名私钥 `APP_TOKEN_SIGNING_KEY_FILE`（加可选的 `APP_TOKEN_NEXT_SIGNING_KEY_FILE`，提前发布）变了就切到新钥；签过名的公钥记在成员自己的 schema 里，JWKS 在停用后继续发布访问令牌寿命 + 60 s（contract-infra-iam `TOKENS.md`；`APP_TOKEN_PREVIOUS_PUBLIC_KEY_PEM` 退役）；
   - 外壳里成员那一项的配置里也是路径，文件挂在外壳容器里同一个位置，启动器不做任何特殊处理。

## 2. Go：`github.com/brickKit/be-sdk-go` v0.6.0

### 2.1 入口与模块

```go
package besdk

type Spec struct {
    ID          string      // "erp/sales"；启动时与 COMPONENT_ID、清单的 metadata.id 核对，不一致就以 78 退出
    Manifest    []byte      // 组件自己的 component.yaml（go:embed）：configSchema、端口、events（→ P2.2）
    Migrations  fs.FS       // <version>_<name>.up.sql / .down.sql + lifecycle.yaml（同一个 embed）；nil = 没有库
    Contracts   fs.FS       // contracts/：errors.yaml、events/*.json（查 x-aggregate-type、校验 payload、/_be/info 用）
    Catalog     string      // authzgen.CatalogJSON：本组件的键和资源类型；"" = 没有
    ErrorDomain string      // 槽位族成员填族 ID（→ P4.1）；"" = 组件 ID
    New         func(ctx context.Context, rt *Runtime) (*Module, error)
}

// Main 按 os.Args 分派：无参数 = 起服务；"migrate up" | "migrate down <n>" | "migrate status" = 迁移（→ P1.1、P11）；
// "job run <name>" = 把一个声明过的任务跑一次就退出（可选能力 job_run，→ P14.8，§2.9）。
// 不认识的参数、不存在的任务名、环境里没有 COMPONENT_ID，都在读配置之前以 64 退出。
// 这是 SDK 里唯一会读进程环境、唯一会调 os.Exit 的地方。
func Main(s Spec)

type Module struct {
    HTTP        func(r *Router)            // 用户面路由；引擎和中间件由 SDK 持有（→ P3）
    GRPC        func(s *grpc.Server)       // 系统面服务（→ P7）
    Events      Events                     // → P12
    Jobs        []Job                      // → P14
    Workers     []Worker                   // tx.Enqueue 的消费者
    Reconcilers []ReconcilerRunner         // NewReconciler[T] 的返回值
    Snapshots   []SnapshotRunner           // NewSnapshot[T] 的返回值（回填 + 订阅自动登记）
    Sharing     []SharingLoader            // MountSharing 用的行加载器（→ P6.10）
    Lifecycle   LifecycleHooks             // Calendar（fiscal_year_end 锚点）、Guards、Checkpointers（→ P16）
    Start       func(ctx context.Context) error // 一次性初始化，最多 30 s；不许起循环
    Stop        func(ctx context.Context) error
}
```

组件的 `main.go` 只有一行：`func main() { besdk.Main(module.Spec) }`。外壳 import 的也是同一个 `module.Spec`。

### 2.2 Runtime 与 Config

```go
type Runtime struct{ /* 不导出 */ }

func (rt *Runtime) ID() string
func (rt *Runtime) Version() string
func (rt *Runtime) Config() *Config
func (rt *Runtime) Logger() *slog.Logger               // 已带 component_id / version；JSON；自动脱敏（→ P18.2）
func (rt *Runtime) Tracer() trace.Tracer               // 成员自己的 provider（→ P18.1、P19.4）
func (rt *Runtime) Meter() metric.Meter                // 真的 MeterProvider，经 Prometheus exporter 进 Registry
func (rt *Runtime) Registry() prometheus.Registerer    // 每个成员一个；所有序列带 component 标签
func (rt *Runtime) Store() (*Store, error)             // 没配 PG_SCHEMA → ErrNoDatabase
func (rt *Runtime) Conn(dep, port string) (*grpc.ClientConn, error)   // → P7.6；可选依赖没装 → ErrDependencyAbsent
func (rt *Runtime) UserHTTP(dep string) (*UserHTTP, error)           // → P8.1
func (rt *Runtime) ExternalHTTP(name string, o ExternalOptions) *http.Client // → P8.3
func (rt *Runtime) Calendar() Calendar                 // → P11.9
func (rt *Runtime) Blob() (*Blob, error)               // → P17
func (rt *Runtime) Lifecycle() *lifecycle.Engine       // → P16
func (rt *Runtime) Capabilities() Capabilities         // 当前 authz provider 的能力位（→ P6）
func (rt *Runtime) Now() time.Time                     // 业务代码取"现在"只经它；besdktest 可以替换时钟

type Config struct{ /* 只装 configSchema 声明过的键 */ }
func (c *Config) Require(key string) string                         // 启动期校验过，运行期不会失败
func (c *Config) String(key, def string) string
func (c *Config) Int(key string, def int) int
func (c *Config) Bool(key string, def bool) bool
func (c *Config) Duration(key string, def time.Duration) time.Duration
func (c *Config) JSON(key string, into any) error
func (c *Config) Secret(key string) Secret                          // 只接受 _FILE 键（→ P2.12）；§1 第 7 条

type Secret interface {
    Current() string                    // 文本密钥的当前值（去掉一个结尾换行）；文件变了就是新值
    Bytes() []byte                      // 组件自己的二进制密钥，逐字节
    Changed() <-chan struct{}           // 每次重读成功后通知一次；签名私钥、凭据对这类要"换实例"的用
}
```

族地址（`AUTHZ_URL`、`AUTHZ_GRPC_URL`、`IAM_URL`、`IAM_GRPC_URL`）是普通配置键，值由 brickKit 的 `$endpoint:` 算出（→ P2.10）。SDK 自己读它们（bundle、changes、JWKS、`Check`、`ResolveClaims`、目录读取），组件代码不碰；`*_GRPC_URL` 去掉 `http://` 当拨号目标，从不由 `*_URL` 推端口。

`Config` 读值的方法不返回 error。原因：`New` 被调用之前，SDK 已经按 `component.yaml` 的 `configSchema` 把每个键都解析、校验过一遍，任何错误都在启动时一次报出，退出码 78（→ P2.3）。读一个没声明的键会 panic，被启动阶段的 recover 接住，同样以 78 退出，这属于编程错误。

### 2.3 Store 与 Tx

```go
type Store struct{ /* 绑定运行角色 PG_USER + PG_SCHEMA + 本成员的连接预算；从不使用 PG_OWNER_USER（→ P10.12） */ }

type Isolation int
const ( ReadCommitted Isolation = iota; RepeatableRead; Serializable )

type TxOptions struct {
    Isolation        Isolation
    ReadOnly         bool
    StatementTimeout time.Duration // 0 = 5 s；实际取它和 ctx 剩余时间的较小值
    LockTimeout      time.Duration // 0 = 2 s
    IdleTimeout      time.Duration // 0 = 30 s
    MaxAttempts      int           // 0 = 3；只对 40001 / 40P01 重试
}

func (s *Store) Tx(ctx context.Context, fn func(ctx context.Context, tx *Tx) error) error
func (s *Store) TxWith(ctx context.Context, o TxOptions, fn func(ctx context.Context, tx *Tx) error) error
func (s *Store) ReadSnapshot(ctx context.Context, fn func(ctx context.Context, tx *Tx) error) error // RR + 只读 + 30 s
func (s *Store) Identity() DBIdentity  // {Role, Schema}，只读

// Tx 实现 sqlc 的 DBTX 接口（ExecContext、QueryContext、QueryRowContext、PrepareContext），
// 所以 sqlc 生成的 Queries 可以直接用：db.New(tx)。
type Tx struct{ /* *sql.Tx + rt + 事务标记 */ }

func (tx *Tx) Publish(ctx context.Context, ev Event) error                                 // → P12.1
func (tx *Tx) Enqueue(ctx context.Context, kind string, args any, o EnqueueOptions) error  // → P14 Queue
func (tx *Tx) Lock(ctx context.Context, name string, parts ...string) error                // → P10.8
func (tx *Tx) TryLock(ctx context.Context, name string, parts ...string) (bool, error)
func (tx *Tx) NextNumber(ctx context.Context, s Series) (string, error)                    // → P11.10
func (tx *Tx) SyncRelation(ctx context.Context, rtype, id, relation string, subjects []string, version int64) error // → P6.13
func (tx *Tx) Seal(ctx context.Context, table, unit string) error                          // lifecycle on_signal
func (tx *Tx) IdemLookup(ctx context.Context, c Command) (Prior, error)                    // → P13
func (tx *Tx) IdemClaim(ctx context.Context, c Command) (Prior, error)
func (tx *Tx) IdemComplete(ctx context.Context, c Command, result any) error
func (tx *Tx) IdemRelease(ctx context.Context, c Command) error

var (
    ErrNestedTx     error // ctx 已经在事务里，又开一个（→ P10.6）
    ErrNetworkInTx  error // 事务里调了 Conn / UserHTTP / ExternalHTTP（→ P8.4）；日志 reason NETWORK_IN_TX，对外 INTERNAL；测试构建里直接 panic
    ErrNoDatabase   error
)
```

每个事务开头 `SET LOCAL ROLE` / `search_path` / `application_name` + 三个超时（→ P10.2、P10.3）。`Tx` 的 `ExecContext` / `QueryContext` / `QueryRowContext` 在 SQL 前加 `/* be:<PG_SCHEMA> */ `，pgx 保持默认的 `QueryExecModeCacheStatement`（`CacheDescribe` 不行，r1-04b）；外壳里 `StatementCacheCapacity` 按成员数放大（→ P10.2）。几条 `SET LOCAL` 可以合成一条 `SELECT set_config(…, true), …` 省往返，是否做由实现时实测决定。

SQLSTATE 由 SDK 统一分类并映射（→ P10.4；`53300` → `DB_TOO_MANY_CONNECTIONS`；连不上库、类 `08`、`57P01`–`57P03` → `DEPENDENCY_UNAVAILABLE`，`metadata.dependency = db`；调用方取消引起的 `57014` → `REQUEST_CANCELLED`）。组件里不再写 `pgerr.go`；需要判断错误类型时，用 `besdk.IsUniqueViolation(err)`、`IsLockTimeout(err)` 这类函数。

### 2.4 路由与守卫

```go
type Router struct{ /* 包着 gin.RouterGroup，前缀是 /{domain}/{name} */ }

type Guard interface{ guard() }         // PermKey、Public、Authenticated、ResourceGuard 都实现它
type PermKey string
type ResourceType string                // 资源类型名，如 "erp.sales.order"；authzgen 生成它的常量
type ResourceGuard struct{ Key PermKey; Type ResourceType; Param string } // Param：放记录 ID 的路径参数，List 时为空
func (k PermKey) List(t ResourceType) ResourceGuard             // 列表路由：按键的范围过滤
func (k PermKey) On(t ResourceType, param string) ResourceGuard // 单条记录路由：记录 ID 在路径参数 param 里
const Public PermKey = ""
const Authenticated PermKey = "__authenticated__"

func GET(r *Router, path string, g Guard, h gin.HandlerFunc, o ...RouteOption)
func POST(r *Router, path string, g Guard, h gin.HandlerFunc, o ...RouteOption)
func PUT(…); func PATCH(…); func DELETE(…)

func Timeout(d time.Duration) RouteOption   // 编排类路由用 15 s（→ P3.4）
func BodyLimit(n int64) RouteOption         // 默认 1 MiB，路由可以声明更大（→ P3.6）

// authzgen 由 be-ops 从 assembly.yaml 生成（authz-architecture §4.2），它的 CatalogJSON 填进 Spec.Catalog：
//   besdk.GET(r, "/orders",     authzgen.SalesView.List(authzgen.SalesOrder), h)
//   besdk.GET(r, "/orders/:id", authzgen.SalesView.On(authzgen.SalesOrder, "id"), h)

// handler 里用的辅助：
func Bind[T any](c *gin.Context) (T, error)           // 解析 JSON；失败答 400 REQUEST_INVALID + violations
func Respond(c *gin.Context, status int, v any)
func Fail(c *gin.Context, err error)                  // 统一走 problem+json（→ P4）
```

### 2.5 Access（授权的唯一入口）

```go
func AccessFrom(ctx context.Context) (*Access, error) // 没有用户 → ErrUnauthenticated（REST 401 / gRPC Unauthenticated）

func (a *Access) User() User                    // {Sub, TenantID, Roles, DeptPath, HasDept, Act, Locale}
func (a *Access) Has(k PermKey) bool            // 功能键，已经计入天花板（ceil）
func (a *Access) Scope(t ResourceType) Scope    // 按本路由的键求值（→ P6.3–P6.5）
func (a *Access) Can(k PermKey, r Resource) Decision                   // {Visible, Allowed, Reason}（→ P6.6）
func (a *Access) RowActions(t ResourceType, rows any, ks ...PermKey) map[string]map[string]bool
func (a *Access) Mask(v any) []string           // 按 struct tag `be:"field=erp.sales.pricing"` 置 null，返回 _masked
func (a *Access) CheckWritable(t ResourceType, changed []string) error // → FIELD_FORBIDDEN
func (a *Access) CheckSortable(field string) error                     // → SORT_FORBIDDEN

type Scope struct{ /* 不导出 */ }
func (s Scope) Params() ScopeParams             // 字段与规范谓词的 @s_* 一一对应（sqlc 的参数结构直接用）
func (s Scope) Branches() []ScopeParams         // 想把 OR 改写成 UNION ALL 时用
type Resource interface{ AuthzRef() Ref; AuthzAttrs() Attrs }
type Decision struct{ Visible, Allowed bool; Reason string }
func (d Decision) Err() error                   // 403 + reason；看不见时调用方应答 404（R62 / A3）

func SystemFrom(ctx context.Context) (System, bool) // gRPC 系统面：{Caller, ActorSub, Act}
func CallerOf(ctx context.Context) string           // "user:<sub>" | "svc:<caller>" | "system"
func MountSharing(r *Router, t ResourceType, load func(ctx context.Context, id string) (Resource, error))
```

### 2.6 调别人

```go
// 系统面：返回缓存好的连接；拦截器链 = 默认截止时间 → 舱壁 → metadata → RED 指标 → 事务守卫（→ P7）
conn, err := rt.Conn("erp/inventory", "grpc")
inv := inventoryv1.NewInventoryServiceClient(conn)

// 用户面：转发调用者的 token（→ P8.1）
type UserHTTP struct{ /* … */ }
func (c *UserHTTP) Do(ctx context.Context, req *http.Request) (*http.Response, error)
func (c *UserHTTP) JSON(ctx context.Context, method, path string, in, out any) error // problem+json 会被还原成 besdk 错误

// 第三方
type ExternalOptions struct{ Timeout time.Duration; MaxConns int; Retry RetryPolicy }

// 批量（→ P7.10）
func BatchGetAll[K comparable, V any](ctx context.Context, keys []K, max int,
    call func(context.Context, []K) (found []V, missing []K, err error)) ([]V, []K, error)
func Chunk[T any](items []T, max int) [][]T
```

### 2.7 事件

```go
type Event struct {
    ID          string    // SDK 填（UUIDv7）
    Subject     string
    AggregateID string
    Version     int64     // 聚合版本；同一聚合类型的所有 subject 共用一个序列
    Payload     any       // 序列化成 JSON，并按契约校验（→ P12.2）
    // 以下几个字段只读，消费时由 SDK 填
    AggregateType, Source, TraceParent, CausationID string
    OccurredAt  time.Time
    HopCount    int
    Delivery    int
}

type Events struct {
    Publishes []string        // 本组件发布的 subject；聚合类型从 Contracts 里的 x-aggregate-type 查
    Subscribe []Subscription
}
type Subscription struct {
    Subject             string
    Consumer            string                                      // 游标的消费者名（投影名），默认 ""（→ P12.6）
    AggregateType       string                                      // 可选：生产方契约的 x-aggregate-type；空 = 取消息的 ce-aggregatetype（→ P12.6）
    TransactionDocument bool                                        // 生产方契约的 x-transaction-document：缺法人的进 DLQ（→ P11.8）
    Apply               func(ctx context.Context, tx *Tx, ev Event) error // 和 Run 二选一
    Run                 func(ctx context.Context, ev Event) error
    MaxDeliver          int                                         // EVENTS_MAX_DELIVER 设了以它为准，否则取这里，0 = 8；由 SDK 判：d = max 的失败照常 Nak，d > max 时先进 DLQ + Term 再说（→ P12.5、P12.7），不写进 consumer
    Backoff             []time.Duration                             // SDK 的 NakWithDelay 延迟表；EVENTS_BACKOFF 设了以它为准；不写进 consumer
    StartFrom   StartFrom                                           // 默认 StartAll（E3）
    Concurrency int                                                 // 默认 4
}
func Permanent(err error) error                                     // 直接进 DLQ
func Decode[T any](ev Event) (T, error)                             // 解析失败自动变成 Permanent
```

durable、流、泵、DLQ、`InProgress` 心跳、游标、清理，都由 SDK 根据 `Events` 声明自动完成。组件里不再出现 NATS 的任何类型。durable 只在不存在时创建（nats.go `CreateConsumer`），从不更新；服务端参数是协议常量（AckWait 30 s、无 BackOff、MaxDeliver −1），读回不一致只记 WARN（→ P12.5，r1-07）。

### 2.8 命令幂等

```go
type Command struct {
    Key     string // 来自 Idempotency-Key 头或 idempotency_key 字段（SDK 的 Bind 会统一）
    Name    string // 权限键或 rpc 全名
    Target  string // 聚合 ID；建类命令为空
    Request any    // 参与指纹的业务字段；SDK 按 JCS 规范化后取 sha256（→ P13.2）
}
type Prior struct{ Found, InProgress bool; Result json.RawMessage }

// 一步式：认领、执行、完成都在同一个事务里；重放时不调用 do
func Idempotent[T any](ctx context.Context, tx *Tx, c Command, do func() (T, error)) (res T, replayed bool, err error)
var ErrIdempotencyMismatch, ErrIdempotencyInProgress error
```

调用顺序固定（→ P13.5）：参数校验 → `AccessFrom` + `Can`（对 target）→ `Idempotent` 或 `IdemClaim` → 状态机 → 写。

### 2.9 后台工作

```go
type JobKind int
const ( Every JobKind = iota; Singleton; Cron )

type Job struct {
    Name     string        // 组件内唯一；指标、租约、日志、JOBS_OVERRIDES 都用它
    Kind     JobKind
    Interval time.Duration // Every / Singleton
    Cron     string        // 如 "0 3 * * *"
    TZ       string        // 默认 BUSINESS_TIMEZONE
    Timeout  time.Duration // 必填
    Run      func(ctx context.Context) error
}

type Worker struct {
    Kind        string
    Concurrency int
    MaxAttempts int
    Backoff     []time.Duration
    Timeout     time.Duration
    Run         func(ctx context.Context, j QueuedJob) error            // 在事务外；按 j.UniqueKey 或业务键幂等
    OnDead      func(ctx context.Context, tx *Tx, j QueuedJob) error    // 重试用尽
}
type EnqueueOptions struct{ RunAt time.Time; UniqueKey string }

type ReconcilerSpec[T any] struct {
    Name        string
    Every       time.Duration
    Batch       int
    Candidates  func(ctx context.Context, tx *Tx, limit int) ([]T, error) // 组件自己的 SQL：非终态且已过期
    ID          func(T) string
    Handle      func(ctx context.Context, item T) (Outcome, error)        // 事务外，可以走网络
    Apply       func(ctx context.Context, tx *Tx, item T, out Outcome) error
    MaxAttempts int
    Backoff     []time.Duration
    GiveUp      func(ctx context.Context, tx *Tx, item T) error           // 挂起 + tx.Enqueue("开异常待办")
}
func NewReconciler[T any](s ReconcilerSpec[T]) ReconcilerRunner
```

SDK 自己的平台任务，名字都以 `be.` 开头（`be.outbox`、`be.lifecycle`、`be.cleanup`、`be.authz.changes`、`be.snapshot.<name>`），同样受监督、同样可以用 `JOBS_OVERRIDES` 调整，组件不需要登记它们。

**跑一次就退出**（可选能力 `job_run`，→ P14.8）。`besdk.Main` 收到 `job run <name>` 时：读配置和密钥文件、核对 schema 版本（同服务入口）、不起 HTTP / gRPC、不起别的后台工作，按任务种类经同一批表跑**一次**（`Cron` 认领当前时刻及之前最近的槽，`Singleton` 抢租约，`Every` / Reconciler 走一遍，`Queue` 在超时内把该种类的就绪行处理一遍），holder 是 `<组件 ID>/job-run:<实例 id>`，指标在退出前推一次。退出码：成功或无事可做 0，失败 1，配置错误 78；任务名不存在和入口不认识的参数一样，在读配置之前就以 64 退出（→ P1.1）。`JOBS_OVERRIDES` 的 `enabled: false` 只停进程内调度，不影响 `job run`。三门 SDK 同样实现（Python `main` 的 `job run`，TS `main` 的 `job run`），并在 `/_be/info` 的 `capabilities` 里列出 `job_run`。外部触发方式见 foundations 19。

### 2.10 其它帮手

```go
// 快照（→ P15）
type SnapshotSpec[T any] struct {
    Name       string
    Upstream   string                 // 依赖 ID，必须在 component.yaml 里声明（可以是 optional）
    Subjects   []string
    FromEvent  func(ev Event) (v Versioned[T], full bool, err error)
    Upsert     func(ctx context.Context, tx *Tx, v Versioned[T], allowInsert bool) error // 必须带 version 守卫
    Load       func(ctx context.Context, tx *Tx, ids []string) (map[string]Versioned[T], error)
    Fetch      func(ctx context.Context, conn *grpc.ClientConn, ids []string) ([]Versioned[T], error)
    ListPage   func(ctx context.Context, conn *grpc.ClientConn, cursor string) ([]Versioned[T], string, error) // nil = 不回填
    StaleAfter time.Duration
}
func NewSnapshot[T any](s SnapshotSpec[T]) *Snapshot[T]
func (s *Snapshot[T]) Get(ctx context.Context, ids []string, o GetOptions) (map[string]Versioned[T], []string, error)

// 进程内缓存（0201 改写）：有容量上限、有 TTL、singleflight、带指标；可以在收到事件时失效
func NewCache[K comparable, V any](rt *Runtime, name string, o CacheOptions) *Cache[K, V]
func (c *Cache[K, V]) GetOrLoad(ctx context.Context, k K, load func(context.Context, K) (V, error)) (V, error)
func (c *Cache[K, V]) Delete(k K)
// CacheOptions{MaxEntries, TTL, InvalidateOn []string /* subject */}

// 法人日历（→ P11.7、P11.9）
type Calendar interface {
    Today(ctx context.Context, legalEntity string) (Date, error)
    BusinessDate(ctx context.Context, legalEntity string, t time.Time) (Date, error)
    FiscalPeriod(ctx context.Context, legalEntity string, d Date) (FiscalPeriod, error)
}
type Date struct{ Year int; Month time.Month; Day int } // 实现 sql.Scanner / driver.Valuer / JSON（"YYYY-MM-DD"）

// 标识（→ P11.5）
func NewID() uuid.UUID
func IDTime(id uuid.UUID) time.Time

// 单据编号（→ P11.10）
type Series struct{ Name, LegalEntity, Period string; Gapless bool } // 格式取配置 <NAME>_NO_FORMAT

// money 包（→ P11.6；跨语言由 vectors/money 锁定）
//   money.Parse(s) (Decimal, error)；d.Round(scale, mode)；money.Amount{Value, Currency}；
//   money.Allocate(total, weights) []Decimal；money.ScaleOf(currency)

// 对象存储（→ P17）
//   blob.Put / Get / Head / Delete / PresignPut(key, contentType, maxBytes, ttl) / PresignGet(key, ttl, disposition)

// 搜索（foundations-data-platform §7.4）
//   search.Text(fields ...string) string   生成 search_text：原文 + 全拼 + 首字母，已做大小写和全半角规范化
//   search.Params(q string) search.Query   按启动时探测到的能力，给出 SQL 片段需要的参数

// 生命周期钩子
type LifecycleHooks struct {
    Calendar      lifecycle.Calendar               // finance 实现 fiscal_year_end；其余组件默认用法人日历
    Guards        map[string]lifecycle.Guard
    Checkpointers map[string]lifecycle.Checkpointer
}
```

### 2.11 错误

```go
func Errorf(code codes.Code, reason string, meta map[string]string, format string, args ...any) error
func WithViolations(err error, v ...FieldViolation) error
func WithRetryAfter(err error, d time.Duration) error
func ReasonOf(err error) (domain, reason string, ok bool)
// 组件不写 ToStatus：gRPC 拦截器和 HTTP 的 Fail 统一做映射（→ P4.2）；
// 不认识的错误一律变成 INTERNAL + 通用文案（→ P4.3）。
```

### 2.12 `besdktest`（只给 `_test.go` 用；门禁 `besdktest-import-scan`）

```go
func NewRuntime(t testing.TB, spec besdk.Spec, o ...Option) *besdk.Runtime // 随机 schema + 随机角色，跑组件迁移和平台迁移
func ShellView(t testing.TB, rt *besdk.Runtime) *besdk.Runtime             // 同一身份，改以 NOINHERIT 的外壳角色登录
func WithUser(ctx context.Context, u besdk.User, o ...UserOption) context.Context
//   UserOption：WithLevel(key, level)、WithValues(dim, v...)、WithPermissions(k...)、WithCeil(p)、WithCapabilities(c...)
func InsertACL(t testing.TB, rt *besdk.Runtime, tuples ...Tuple)
func Clock(t testing.TB, rt *besdk.Runtime, now time.Time) *FakeClock
func FakeIAM(t testing.TB) *IAM            // JWKS + 签发器（与 compconf 的 fake-iam 是同一份代码）
func FakeAuthz(t testing.TB) *Authz        // provider 契约的进程内实现；它自己也要跑 authzconf 的 core（authz-architecture §4.6）
func FakePeer(t testing.TB, desc protoreflect.FileDescriptor) *Peer // 依赖的假实现：记录 metadata，可以挂起或报错
func Published(t testing.TB, rt *besdk.Runtime) []besdk.Event       // 读本 schema 的 outbox
func Deliver(t testing.TB, rt *besdk.Runtime, ev besdk.Event)       // 不经总线，直接走 handler 和游标
func RunJob(t testing.TB, rt *besdk.Runtime, name string)           // 立刻跑一次
func Vectors(t *testing.T, dir string, run func(t *testing.T, in, want json.RawMessage))
```

### 2.13 外壳

```go
package shell
type Members []besdk.Spec
func Main(m Members) // 语义见 §5；版本核对靠 debug.ReadBuildInfo() 里各成员模块的版本
```

### 2.14 一个模块的样子（erp/sales 节选）

```go
var Spec = besdk.Spec{ID: "erp/sales", Migrations: migrations.FS, Contracts: contracts.FS, New: New}

func New(ctx context.Context, rt *besdk.Runtime) (*besdk.Module, error) {
    store, err := rt.Store()
    if err != nil { return nil, err }
    svc := service.New(rt, store)
    return &besdk.Module{
        HTTP: svc.Routes,
        GRPC: func(s *grpc.Server) { salesv1.RegisterSalesServiceServer(s, svc.GRPC()) },
        Events: besdk.Events{
            Publishes: []string{"sales.order.created.v1", "sales.order.cancelled.v1", "sales.order.shipped.v1"},
            Subscribe: []besdk.Subscription{
                {Subject: "finance.credit.rejected.v1", Apply: svc.OnCreditRejected}, // 只做本地写，加 tx.Enqueue
                {Subject: "crm.opportunity.won.v1", Run: svc.OnOpportunityWon},       // 事务外，确定性的幂等键
            },
        },
        Snapshots:   []besdk.SnapshotRunner{svc.CustomerSnapshot()},
        Reconcilers: []besdk.ReconcilerRunner{svc.ConfirmingReconciler()},
        Workers:     []besdk.Worker{{Kind: "workflow.create_task", Concurrency: 2, MaxAttempts: 8, Timeout: 10 * time.Second,
                                      Run: svc.CreateTask, OnDead: svc.CreateTaskDead}},
        Sharing:     []besdk.SharingLoader{svc.OrderLoader()},
    }, nil
}
```

## 3. Python：`besdk`（be-sdk-python v0.6.0）

和 Go 的差别只有三处：用 `async`；上下文是隐式的（`contextvars`）；没有泛型约束。

```python
@dataclass(frozen=True)
class Spec:
    id: str
    migrations: Path            # 目录：yoyo 的 .sql/.rollback.sql + lifecycle.yaml
    contracts: Path
    create: Callable[[Runtime], Awaitable[Module]]
    manifest: Path | None = None    # 默认 <contracts>/../component.yaml
    error_domain: str | None = None # 槽位族成员填族 ID（→ P4.1）

def main(spec: Spec) -> NoReturn            # 起服务 | "migrate up" | "migrate down <n>" | "migrate status" | "job run <name>"（→ P14.8）；其它参数、不存在的任务名 → 64

@dataclass
class Module:
    http: Callable[[Router], None] | None = None
    grpc: Callable[[grpc.aio.Server], None] | None = None
    events: Events = Events()
    jobs: Sequence[Job] = ()
    workers: Sequence[Worker] = ()
    reconcilers: Sequence[Reconciler] = ()
    snapshots: Sequence[Snapshot] = ()
    sharing: Sequence[SharingLoader] = ()
    lifecycle: LifecycleHooks = LifecycleHooks()
    start: Callable[[], Awaitable[None]] | None = None
    stop: Callable[[], Awaitable[None]] | None = None

class Runtime:
    id: str; version: str; config: Config; logger: logging.Logger; tracer: Tracer; meter: Meter; registry: CollectorRegistry
    def store(self) -> Store
    def conn(self, dep: str, port: str = "grpc") -> grpc.aio.Channel
    def user_http(self, dep: str) -> UserHTTP                  # httpx.AsyncClient 的包装
    def external_http(self, name: str, *, timeout: float = 10, max_conns: int = 32) -> httpx.AsyncClient
    calendar: Calendar; clock: Clock          # Go 是 rt.Now()
    def blob(self) -> Blob
    def lifecycle(self) -> lifecycle.Engine
    def capabilities(self) -> Capabilities

class Store:
    async def tx(self, fn: Callable[[Tx], Awaitable[T]], *, isolation: Isolation = Isolation.READ_COMMITTED,
                 read_only: bool = False, statement_timeout: float | None = None, lock_timeout: float | None = None,
                 idle_timeout: float | None = None, max_attempts: int = 3) -> T
    async def read_snapshot(self, fn: Callable[[Tx], Awaitable[T]]) -> T
    identity: DBIdentity

class Tx:                                   # 包着一条 asyncpg.Connection；fetch / fetchrow / execute 透传
    async def publish(self, ev: Event) -> None
    async def enqueue(self, kind: str, args: Any, *, run_at: datetime | None = None, unique_key: str | None = None) -> None
    async def lock(self, name: str, *parts: str) -> None
    async def try_lock(self, name: str, *parts: str) -> bool
    async def next_number(self, series: Series) -> str
    async def sync_relation(self, rtype: str, id: str, relation: str, subjects: Sequence[str], version: int) -> None
    async def seal(self, table: str, unit: str) -> None
    async def idem_lookup(self, cmd: Command) -> Prior   # idem_claim / idem_complete / idem_release 同形

# 路由：besdk.Router 包着 APIRouter，前缀是 /{domain}/{name}
@r.get("/templates", guard=authzgen.PRINT_VIEW, timeout=10)
async def list_templates(q: ListQuery = Depends()) -> Page[Template]: ...

def access() -> Access                      # 没有用户就抛 Unauthenticated（→ 401 / UNAUTHENTICATED）
def system() -> System | None
def caller_of() -> str
async def idempotent(tx: Tx, cmd: Command, do: Callable[[], Awaitable[T]]) -> tuple[T, bool]

@dataclass(frozen=True)
class Subscription:
    subject: str
    consumer: str = ""
    apply: Callable[[Tx, Event], Awaitable[None]] | None = None
    run: Callable[[Event], Awaitable[None]] | None = None
    max_deliver: int | None = None
    backoff: tuple[float, ...] | None = None
    start_from: StartFrom = StartFrom.ALL
    concurrency: int = 4
    aggregate_type: str = ""        # 可选；空 = 取消息的 ce-aggregatetype（→ P12.6）

@dataclass(frozen=True)
class Job:
    name: str; kind: JobKind; timeout: float
    interval: float | None = None; cron: str | None = None; tz: str | None = None
    run: Callable[[], Awaitable[None]] = ...
```

**Python 特有的要点**：

- **一个进程一个事件循环**（0103 不变）。阻塞调用（PyJWT 验签、pyarrow）一律经 `asyncio.to_thread`；SDK 里没有任何同步 IO。
- **`Store.tx` 是"传函数"而不是 `async with`**：上下文管理器没法在 40001 时重跑代码块。
- **运行时是 CPython 3.14**（`python:3.14-slim`，镜像里不需要编译器；r1-10）。`uuid.uuid7` 用标准库；`pyarrow` 只在 `besdk[cold]` 里。
- **迁移入口进 SDK**：`python -m <pkg> migrate up` 以 `PG_OWNER_USER` 登录调 yoyo（同步驱动 `psycopg[binary]==3.3.6`，`postgresql+psycopg://` 后端），状态表放在本组件的 schema 里（`_yoyo_*`、`yoyo_lock`；平台迁移 id 带 `besdk-` 前缀）。print 的 `migrate.py` 删掉。
- **pytest 插件 `besdk.testing`**：
  - fixture：`rt`（随机身份）、`shell_view`、`fake_iam`、`fake_authz`、`fake_peer`；
  - 辅助函数：`with_user(...)`（上下文管理器）、`published(rt)`、`deliver(rt, ev)`、`run_job(rt, name)`、`vectors(dir)`。
- **asyncpg 的池**：`asyncpg==0.31.0`；`max_size = PG_POOL_MAX`；`acquire(timeout=PG_POOL_ACQUIRE_TIMEOUT)`；预编译语句缓存**开着**，`Tx` 的 `fetch` / `fetchrow` / `execute` 在 SQL 前加 `/* be:<PG_SCHEMA> */ `，外壳里 `statement_cache_size` 按成员数放大（r1-04，→ P10.2）。
- **事件**：nats-py 的 `add_consumer` 是"创建或更新"，SDK 先 `consumer_info`、不存在才建，从不直接调它改已有的 durable（r1-07，→ P12.5）。
- **批量上限**：besdk 随包附带生成好的 `be/v1/limits_pb2.py`（顶层包 `be`），SDK 用 `field.GetOptions().Extensions[limits_pb2.max_items]` 读上限，`HasExtension` 为假时取 500（r1-03b，→ P7.10）。
- **JWT**：`jwt.decode(..., audience=TENANT_ID, issuer=IAM_ISSUER, options={"require": ["exp","iat","sub","jti","iss","aud"]})`，并另外检查 `typ`（→ P5.3）。
- **冷层**：`pip install besdk[cold]` 才有 `s3-parquet`；没装时，加载 `lifecycle.yaml` 那一刻就报"不支持"。
- **栈里另外两项**（0103 的 Python 行）：事件 payload 用 `jsonschema==4.26.0` 校验；Meter 经 `opentelemetry-exporter-prometheus==0.59b0` 写进成员的 CollectorRegistry。
- **接受的差异**（阶段 B 审查）：`rt.conn(dep)` 返回 channel 代理；事务开头的设置用 `set_config(…)` 一次往返完成；运维端点的访问日志按 debug 记（→ P3.10）。

## 4. TypeScript：`@brickkit/be-sdk-ts` v0.6.0

```ts
export interface ComponentSpec {
  id: string;                               // 启动时与 COMPONENT_ID 核对，不一致 → 78
  migrations?: string;                      // 目录：node-pg-migrate 的 SQL 文件 + lifecycle.yaml；没有 = 不连库
  contracts?: string;
  manifest?: string;                        // 镜像里的 component.yaml；默认工作目录下的 component.yaml
  errorDomain?: string;                     // 槽位族成员填族 ID（→ P4.1）
  create: (rt: Runtime) => Promise<Module>;
}
export function defineComponent(spec: ComponentSpec): Spec;
export function main(spec: Spec): never;    // 起服务 | "migrate up" | "migrate down <n>" | "migrate status" | "job run <name>"（→ P14.8）；其它参数、不存在的任务名 → 64

export interface Module {
  http?: (r: Router) => void;               // Router 包着本成员的 Fastify 实例（只开放 get/post/put/patch/delete）
  graphql?: YogaOptions;                    // 只给 BFF 用：Yoga 挂在 Fastify 的 /graphql 上
  grpc?: (s: grpc.Server) => void;
  events?: Events; jobs?: Job[]; workers?: Worker[]; reconcilers?: Reconciler[];
  snapshots?: Snapshot[]; sharing?: SharingLoader[]; lifecycle?: LifecycleHooks;
  start?: (signal: AbortSignal) => Promise<void>;
  stop?: () => Promise<void>;
}

export interface Runtime {
  readonly id: string; readonly version: string; readonly config: Config;
  readonly logger: pino.Logger; readonly tracer: Tracer; readonly meter: Meter; readonly registry: Registry;
  store(): Store;
  conn(dep: string, port?: string): grpc.Channel;                         // 缓存；拦截器链同 Go
  client<C>(ctor: new (addr: string, cred: grpc.ChannelCredentials, opts?: object) => C, dep: string, schema: ProtoMetadataLike, port?: string): C; // 共用 conn；第三个参数是 ts-proto 的 protoMetadata（推服务配置和 max_items）
  userHttp(dep: string): UserHttp;                                        // 基于 undici
  externalHttp(name: string, opts?: { timeoutMs?: number; maxConns?: number }): ExternalHttp;
  readonly calendar: Calendar; readonly clock: Clock;
  blob(): Blob; lifecycle(): LifecycleEngine; capabilities(): Capabilities;
}

export interface Store {
  tx<T>(fn: (tx: Tx) => Promise<T>, opts?: TxOptions): Promise<T>;
  readSnapshot<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
  readonly identity: { role: string; schema: string };
}
export interface Tx {                       // 包着一个 pg.PoolClient；query 透传
  query<R>(sql: string, params?: unknown[], row?: ZodType<R>): Promise<R[]>;
  publish(ev: EventInput): Promise<void>;
  enqueue(kind: string, args: unknown, opts?: { runAt?: Date; uniqueKey?: string }): Promise<void>;
  lock(name: string, ...parts: string[]): Promise<void>;
  nextNumber(series: Series): Promise<string>;
  syncRelation(rtype: string, id: string, relation: string, subjects: string[], version: bigint): Promise<void>;
  seal(table: string, unit: string): Promise<void>;
  idemLookup(cmd: Command): Promise<Prior>;  // idemClaim / idemComplete / idemRelease 同形
}

export function access(): Access;           // 从 AsyncLocalStorage 取；没有用户就抛 401 的 BeError
export function system(): System | undefined;
export function callerOf(): string;
export function idempotent<T>(tx: Tx, cmd: Command, run: () => Promise<T>): Promise<{ result: T; replayed: boolean }>;
export function beError(code: GrpcCode, reason: string, meta?: Record<string, string>, message?: string): BeError;
export function batchGetAll<K, V>(keys: K[], max: number, call: (ks: K[]) => Promise<{ found: V[]; missing: K[] }>): Promise<{ found: V[]; missing: K[] }>;
export function createBatchGetLoader<K, V>(batchGet: (ids: readonly K[]) => Promise<ArrayLike<V | Error>>, opts?: { maxBatchSize?: number }): DataLoader<K, V>;
```

**TS 特有的要点**：

- **上下文用 `AsyncLocalStorage`**：Fastify 的 `onRequest` 钩子、grpc-js 的服务端包装、事件 handler 和 Job 运行器各自 `als.run(ctx, …)`。组件代码不传 `ctx`，但截止时间和取消信号可以用 `deadline()`、`signal()` 取到，交给 `pg` 和 `fetch`。
- **截止时间到 pg**：用 `SET LOCAL statement_timeout`，再加 `AbortSignal` 驱动 `client.query` 的取消（`pg` 的 `cancel` 走 `pg_cancel_backend`）。pg 保持默认的未命名语句；要用命名语句时 `name` 必须是 `<schema>:<name>`（r1-04，→ P10.2）。
- **Fastify 实例的固定选项**（r1-08，→ P3.4–P3.6；Fastify ≥ 5.12）：`http: { headersTimeout: 5000, connectionsCheckingInterval: 1000 }`（Node 只按这个周期检查，默认 30 s 会让 5 s 变成最多 35 s）、`requestTimeout: 30000`、`keepAliveTimeout: 120000`、`bodyLimit: 1 MiB`（路由声明更大时用路由级 `bodyLimit`）、`handlerTimeout` = 路由截止时间（默认 `HTTP_DEFAULT_TIMEOUT`）。错误处理器把 `FST_ERR_HANDLER_TIMEOUT`（Fastify 默认答 503）改成 504 + `DEADLINE_EXCEEDED`，`FST_ERR_CTP_BODY_TOO_LARGE` 改成 413 + `BODY_TOO_LARGE`；取消信号（SDK 自己建，见本节末尾接受的差异）交给 pg 的取消和 undici。**错误处理器和 `onTimeout` 钩子里不读 ALS**（定时器上下文里 ALS 为空），成员身份和 request id 从 `request` 和闭包里取。
- **迁移**（r1-06，→ P11.1、P11.3）：node-pg-migrate 以 `PG_OWNER_USER` 登录，必须显式传 `ignorePattern: '(\\..*)|(.*(?<!\\.sql))'`（只认 `.sql`，否则 `lifecycle.yaml` 让整次迁移失败）、`lockValue`（由 `PG_SCHEMA` + 状态表名派生，例如 FNV-1a 截到 53 位，不能用默认的全库常量）和 `advisoryLockMode: 'wait'`；状态表 `pgmigrations_<PG_SCHEMA>` + `besdk_migrations_<PG_SCHEMA>`。
- **gRPC 生成与批量上限**（r1-03、r1-03b，→ P7.8、P7.10）：ts-proto 选项 `outputServices=grpc-js,esModuleInterop=true,outputSchema=true,importSuffix=.ts,enumsAsLiterals=true`。SDK 从 `protoMetadata` 推服务配置（`idempotencyLevel`）；批量上限读 `protoMetadata.options.messages.<Msg>.fields.<字段>.max_items`（扩展短名，嵌套消息在 `.nested` 下，跨文件沿 `dependencies` 查），默认 500 来自遍历入参消息的每个 repeated 字段。grpc-js 的重试预算按（进程，目标）共享，服务端没有 `MinTime` 强制（→ P7.5、P7.8）。
- **金额**：`decimal.js` 的实例只在 SDK 的 money 模块里构造，线上一律是字符串（0301）；`number` 永远不承载金额（门禁里加一条 TS 的 `parseFloat` 扫描）。
- **`bigint`**：聚合版本、revision 用 `bigint`。JSON 序列化时转成字符串，和 P12 的头值一致。
- **BFF**：
  - 仍然没有库：`Module.graphql`，不写 `migrations`，`rt.store()` 会抛错；
  - resolver 用 `access()` 和下游的键（I6）；
  - `userHttp` 替换 `restForward.ts`；
  - `rt.client` 替换"每批建一个 gRPC 客户端"。
- **事件订阅**：`Subscription` 有可选的 `aggregateType`（空 = 取 `ce-aggregatetype`，→ P12.6）；延迟表字段叫 `backoffMs`（毫秒数组）。payload 用 **AJV** 按契约校验（0103 的 TS 行）。
- **接受的差异**（阶段 B 审查）：`rt.client` 的第三个参数是 `protoMetadata`；`backoffMs`；`isBeError` 靠品牌 symbol 判定；取消信号由 SDK 自己建；`close()` 会继续关闭空闲连接；运维端点的访问日志按 debug 记（→ P3.10）。
- **测试包 `@brickkit/be-sdk-ts/testing`**：`newRuntime()`（随机身份）、`withUser()`、`fakeIam()`、`fakeAuthz()`、`fakePeer()`、`published()`、`deliver()`、`runJob()`、`vectors()`。用 vitest，属性测试用 fast-check。

## 5. 外壳启动器（三门语言同一段语义，→ P19）

```
read BRICKKIT_SERVED_MEMBERS_CONFIG                     // 缺失、空串、null 都是错误；[] 表示零个成员
shellCfg := 外壳自己的配置（同样只装 configSchema 声明过的键）
for m in members:
    spec := compiled[m.componentId]                     // 没有 → 退出 2，点名成员
    assert compiledVersion(spec) == m.version           // 不一致 → 退出 2（Go 用 build info，Py 用 importlib.metadata，TS 用 package.json）
    assert m.config 里的 PG_HOST/PORT/DATABASE、EVENT_BUS_URL（或 NATS_URL）、AUTHZ_URL、AUTHZ_GRPC_URL、IAM_*、TENANT_ID == shellCfg 里的值   // 不一致 → 退出 78（$endpoint: 解析出的值对每个成员本来就相同）
    assert shellCfg.SHUTDOWN_GRACE >= max(成员的 SHUTDOWN_GRACE)                        // → P19.9；stopGracePeriodSeconds 由门禁对照 component.yaml
assert server_version_num >= 160000                    // 外壳要 PG16（WITH INHERIT FALSE, SET TRUE，→ P10.7、P19.5）
platform := 进程级：OTel 导出器 + 传播器（全局只装传播器；全局 TracerProvider 设成外壳自己的）；JWKS 验签器 + bundle；PG 物理池（大小 = min(Σ 成员 PG_POOL_MAX, 外壳的 PG_POOL_MAX)，以外壳的登录角色连）；总线连接
for m in members:
    rt := newRuntime(platform, m.config, m.ports)        // 成员自己的 Logger / Registry / TracerProvider（自己的 BSP + 包着共享导出器的空 Shutdown 壳）/ MeterProvider / 预算信号量 / Conn 池 / 舱壁 / 缓存；
                                                         // Store 每个事务 SET LOCAL ROLE <m 的 PG_USER> + application_name = m 的 ID；m 的 PG_OWNER_* 不用（迁移由 m 自己的迁移容器跑）
    mod := spec.New(rt)                                  // 失败 → 整个外壳退出非 0
    serve(m.httpPort, mod.HTTP); serve(m.extraPorts.grpc, mod.GRPC)
    supervise(mod.Jobs + 平台任务 + 消费者 + Reconcilers + Workers + 投影拉取)   // 和单跑用的是同一个监督器
serve(shell.port, /healthz + /readyz（所有成员都就绪才 200，否则 503 NOT_READY，metadata.waiting 列出没就绪的成员 ID；零个成员时 200，→ P19.10）+ 汇总的 /metrics)
on SIGTERM: 停止接新请求 → 各成员**并行** Stop，在外壳的 SHUTDOWN_GRACE 内（只刷出自己的 span 队列）→ 平台关闭（这时才关真正的导出器，r1-01）→ 退出 0，落在外壳的 stopGracePeriodSeconds 之内
```

## 6. 夹具组件 `widget`（规格在 be-protocol `fixtures/widget/`，三门 SDK 各实现一份）

- **ID**：`conformance/widget`，三门语言各起一个实例 ID：`conformance/widget-go`、`-py`、`-ts`。
- **库**：一个 schema，表按 8 个生命周期类别各建一张：
  - `widgets`（document，按 `created_at` 每月一个分区）；
  - `widget_lines`（`follows: widgets`）；
  - `widget_ledger`（ledger）；
  - `widget_audit`（audit）；
  - `widget_jobs`（queue）；
  - `owner_snapshots`（snapshot）；
  - `widget_kinds`（reference）；
  - `widget_owners`（master）。
- **用户面 REST**（`/conformance/widget/...`）：
  - `POST /widgets`：建类命令，带幂等键，发出 `conformance.widget.created.v1`；
  - `GET /widgets/:id`、`GET /widgets`（规范谓词，带 owner / org / `region` 资源维度，可以共享）；
  - `POST /widgets/:id/approve`：动作类、两段式幂等、调 fake-peer 的 `Reserve`；
  - `POST /widgets/:id/slow?ms=`：用来测截止时间和舱壁；
  - 字段键 `conformance.widget.price.read`。
- **系统面 gRPC**：
  - `BatchGetWidgets`（`max_items = 100`）；
  - `GetWidget`（`NO_SIDE_EFFECTS`）；
  - `TouchWidget`（`IDEMPOTENT`，带 `idempotency_key`）。
- **事件**：
  - 发布 `conformance.widget.created|approved.v1`（聚合类型 `conformance.widget.widget`）；
  - 订阅 `conformance.owner.updated.v1`，用快照帮手维护 `owner_snapshots`。
- **后台工作**：
  - 一个 `Cron`（`widget.daily`）；
  - 一个 `Worker`（`widget.notify`）；
  - 一个 `Reconciler`（approve 卡在半路时推进）。
- **坏变体**（构建参数 `BROKEN=<名字>`，§4.7）：`accept-refresh`、`healthz-db`、`no-ce-id`、`select-claim`、`no-set-role`、`unbounded-pool`、`no-deadline`、`leak-internal`。

widget 的 `conformance/fixtures.yaml` 也在 be-protocol 里，就是 compconf 用例的"金样本"。真实组件照着它写自己的 fixtures。

## 7. 第四门语言：实现顺序与 INTERNAL 清单

**实现顺序**（每一步做完都能多过一个 compconf profile）：

1. `core`、`obs`、`err`：进程、配置、`/healthz`、日志、指标、problem+json；
2. `auth`：JWT 加 bundle v2；
3. `db`：身份、`SET LOCAL`、超时、池、平台迁移和参考 DDL；
4. `events-pub`、`events-sub`：outbox、JetStream、游标；
5. `idempotency`、`jobs`、`lifecycle`；
6. `scope`、`grpc`、`outbound`。

建议对照 be-protocol 的 `vectors/` 写单元测试，这比读正文快。

**INTERNAL 清单**（compconf 测不到，评审时逐条核对；官方 SDK 自己的测试已经覆盖）：

| # | 规则 | 来源 |
|---|---|---|
| I-1 | 事务里没有网络调用；对外的动作只经 outbox 和作业队列 | P8.4 |
| I-2 | 没有嵌套事务；同一个执行流最多占一条连接 | P10.6 |
| I-3 | 每一次数据库访问都在事务里，都先 `SET LOCAL ROLE` / `search_path` / `application_name`；池化连接上没有会话级的 `SET`（迁移连接除外）；语句缓存的键包含成员 schema | P10.2 |
| I-4 | advisory 锁只用事务级的，键的派生方式符合 P10.8 | P10.8 |
| I-5 | 列表 SQL 是规范谓词，参数全部来自求值结果；没有字符串拼接出来的 WHERE | P6.5 |
| I-6 | 不跨请求缓存授权决策 | P6.14 |
| I-7 | 原始 token 不进日志、不进 `User` 对象 | P5.8 |
| I-8 | 只读 configSchema 声明过的键；不读进程环境 | P2.2 |
| I-9 | 所有后台工作都受监督，没有自己写的无监督循环 | P14.1 |
| I-10 | 多行加锁按固定顺序 | P10.10 |
| I-11 | 运行进程从不以 `PG_OWNER_USER` 连库；运行期的 DDL 只经平台的 `SECURITY DEFINER` 函数 | P10.12 |
| I-12 | 所有 OTel 埋点显式传成员的 provider 和平台的传播器；成员停止不关共享导出器 | P18.1、P19.3 |
| I-13 | durable 只建不改；重投延迟和 DLQ 由运行时自己执行，不靠服务端 BackOff / MaxDeliver | P12.5、P12.7 |

## 8. v0.5.0 → v0.6.0 名字对照（给迁移 lane 查）

| v0.5.0 | v0.6.0 |
|---|---|
| `besdk.RunStandalone(module.New)`、`cmd/migrate` 的 `migrate.Main(fs)` | `besdk.Main(module.Spec)`（`Spec` 带 `Manifest`、`Catalog`），迁移是同一个二进制的 `migrate up` / `migrate down <n>` / `migrate status` 子命令；`component.yaml` 改为 `migration.command: [./component, migrate, up]` |
| `besdk.Module{HTTPHandler, RegisterGRPC, Start, Stop}` | `besdk.Module{HTTP, GRPC, Events, Jobs, Workers, Reconcilers, Snapshots, Sharing, Lifecycle, Start, Stop}` |
| `rt.Config.StringOr("PG_SCHEMA", "…")`、`schema + "_rw"` | `rt.Store()`（身份来自 `PG_USER` / `PG_SCHEMA`） |
| `besdk.WithTx(ctx, rt.DB, role, schema, fn(*sql.Tx))` | `store.Tx(ctx, fn(ctx, *besdk.Tx))` |
| `besdk.PublishOutbox(tx, schema, ev)`、`StartOutboxPump(…)` | `tx.Publish(ctx, ev)`；泵是平台任务 |
| `besdk.Consume(ctx, nc, db, role, schema, subject, fn)` | `Module.Events.Subscribe` 里的 `Subscription{Apply \| Run}` |
| 组件自写的 `partition/` 包、ticker 循环 | `lifecycle.yaml` + 平台任务 `be.lifecycle`；组件的循环改成 `Module.Jobs` |
| 组件自写的 claim / lookup / finalize | `besdk.Idempotent`、`tx.Idem*` |
| `besdk.UserClient(ctx, cfg, dep, extra)` / `SystemClient(cfg, dep, extra)` | `rt.Conn(dep, "grpc")`；用户面改用 `rt.UserHTTP(dep)` |
| `besdk.ScopeOf(ctx)`、`ScopeFilter.Prefix/Exact/Owner` | `besdk.AccessFrom(ctx)` → `a.Scope(t).Params()`（规范谓词的数组参数） |
| `besdk.ContextWithClaims(ctx, claims)` | `besdktest.WithUser(ctx, u, …)` |
| `besdk.ListWindow(q)`、`BatchGetRouted` | 分页按 P3.8；`besdk.BatchGetAll`；冷热由生命周期引擎负责 |
| `status.go` 里手写的 `ToStatus`、`pgerr.go` | `besdk.Errorf` + `contracts/errors.yaml`；`besdk.Is*` |
| `time.Now()`、SQL 里的 `CURRENT_DATE` | `rt.Now()`（Python `rt.clock`、TS `rt.clock.now()`）、`rt.Calendar().Today(ctx, le)` 作为参数传进 SQL |
| Python 的 `with_tx(pool, role, schema, fn)`、`start_outbox_pump`、`scope_of()`、print 的 `migrate.py` | `await store.tx(fn)`、`await tx.publish(ev)`、`besdk.access()`、`python -m <pkg> migrate up` |
| TS 的 `MALFORMED_REQUEST`；Go 提议的 `DB_UNAVAILABLE`、TS store 借用的 `UPSTREAM_UNAVAILABLE` | `be` 的 `REQUEST_INVALID`；`DEPENDENCY_UNAVAILABLE`（`metadata.dependency`）；`UPSTREAM_*` 只留给边缘 |
| TS 的 `runStandalone`、`newGraphQLServer`、`requirePermission(perm, resolver)`、`userClient` | `main(defineComponent(…))`、`Module.graphql`、`guard(perm, resolver)`、`rt.client(Ctor, dep)` 或 `rt.userHttp(dep)` |
