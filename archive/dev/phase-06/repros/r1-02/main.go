// R1 #2：grpc-go
//
//	(a) 由 proto 方法选项 idempotency_level 生成的 WithDefaultServiceConfig（retryPolicy + retryThrottling）
//	    真的生效（P7.8）；
//	(b) 服务端 MaxConnectionAge 触发 GOAWAY 之后，客户端透明重连，调用方看不到错误（P7.5）。
//
// 服务端和客户端在同一进程，走真实 TCP；目标写 "localhost:<port>"（默认 dns 解析器，与 compose 里写服务名一样）。
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/bufbuild/protocompile"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/keepalive"
	"google.golang.org/grpc/stats"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/reflect/protodesc"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/descriptorpb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// ---------- 生成器：proto 方法选项 → service config JSON（SDK 生成代码里要做的事） ----------

type retryPolicy struct {
	MaxAttempts          int      `json:"maxAttempts"`
	InitialBackoff       string   `json:"initialBackoff"`
	MaxBackoff           string   `json:"maxBackoff"`
	BackoffMultiplier    float64  `json:"backoffMultiplier"`
	RetryableStatusCodes []string `json:"retryableStatusCodes"`
}
type methodName struct {
	Service string `json:"service"`
	Method  string `json:"method"`
}
type methodConfig struct {
	Name        []methodName `json:"name"`
	RetryPolicy *retryPolicy `json:"retryPolicy,omitempty"`
}
type serviceConfig struct {
	MethodConfig    []methodConfig `json:"methodConfig"`
	RetryThrottling struct {
		MaxTokens  float64 `json:"maxTokens"`
		TokenRatio float64 `json:"tokenRatio"`
	} `json:"retryThrottling"`
}

func serviceConfigFor(sd protoreflect.ServiceDescriptor) string {
	var sc serviceConfig
	sc.RetryThrottling.MaxTokens, sc.RetryThrottling.TokenRatio = 10, 0.1
	var names []methodName
	for i := 0; i < sd.Methods().Len(); i++ {
		md := sd.Methods().Get(i)
		lvl := protodesc.ToMethodDescriptorProto(md).GetOptions().GetIdempotencyLevel()
		if lvl == descriptorpb.MethodOptions_NO_SIDE_EFFECTS || lvl == descriptorpb.MethodOptions_IDEMPOTENT {
			names = append(names, methodName{string(sd.FullName()), string(md.Name())})
		}
	}
	if len(names) > 0 {
		// P7.8："最多 3 次"重试 → maxAttempts = 1 + 3 = 4
		sc.MethodConfig = append(sc.MethodConfig, methodConfig{Name: names, RetryPolicy: &retryPolicy{
			MaxAttempts: 4, InitialBackoff: "0.05s", MaxBackoff: "0.5s", BackoffMultiplier: 2,
			RetryableStatusCodes: []string{"UNAVAILABLE"},
		}})
	}
	b, _ := json.Marshal(sc)
	return string(b)
}

// ---------- 服务端 ----------
// 请求体是 "<testID>|<mode>"：mode = ok | fail=N（前 N 次答 UNAVAILABLE） | always | sleep=MS

type server struct {
	mu       sync.Mutex
	attempts map[string][]time.Time
}

func (s *server) handle(method string) func(any, context.Context, func(any) error, grpc.UnaryServerInterceptor) (any, error) {
	return func(_ any, ctx context.Context, dec func(any) error, _ grpc.UnaryServerInterceptor) (any, error) {
		in := new(wrapperspb.StringValue)
		if err := dec(in); err != nil {
			return nil, err
		}
		id, mode, _ := strings.Cut(in.Value, "|")
		s.mu.Lock()
		s.attempts[id] = append(s.attempts[id], time.Now())
		n := len(s.attempts[id])
		s.mu.Unlock()
		switch {
		case mode == "always":
			return nil, status.Error(codes.Unavailable, "always")
		case strings.HasPrefix(mode, "fail="):
			k, _ := strconv.Atoi(mode[5:])
			if n <= k {
				return nil, status.Errorf(codes.Unavailable, "attempt %d", n)
			}
		case strings.HasPrefix(mode, "sleep="):
			ms, _ := strconv.Atoi(mode[6:])
			select {
			case <-time.After(time.Duration(ms) * time.Millisecond):
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
		return wrapperspb.String(method + ":ok"), nil
	}
}

func (s *server) count(id string) int {
	s.mu.Lock()
	defer s.mu.Unlock()
	return len(s.attempts[id])
}

func (s *server) gaps(id string) []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []string
	ts := s.attempts[id]
	for i := 1; i < len(ts); i++ {
		out = append(out, ts[i].Sub(ts[i-1]).Round(time.Millisecond).String())
	}
	return out
}

// connCounter：服务端的 stats handler，数 TCP 连接
type connCounter struct{ n atomic.Int64 }

func (c *connCounter) TagRPC(ctx context.Context, _ *stats.RPCTagInfo) context.Context   { return ctx }
func (c *connCounter) HandleRPC(context.Context, stats.RPCStats)                         {}
func (c *connCounter) TagConn(ctx context.Context, _ *stats.ConnTagInfo) context.Context { return ctx }
func (c *connCounter) HandleConn(_ context.Context, s stats.ConnStats) {
	if _, ok := s.(*stats.ConnBegin); ok {
		c.n.Add(1)
	}
}

func startServer(sd protoreflect.ServiceDescriptor, age, grace time.Duration) (*server, *connCounter, string, func()) {
	s := &server{attempts: map[string][]time.Time{}}
	cc := &connCounter{}
	desc := grpc.ServiceDesc{ServiceName: string(sd.FullName()), HandlerType: (*any)(nil)}
	for i := 0; i < sd.Methods().Len(); i++ {
		name := string(sd.Methods().Get(i).Name())
		desc.Methods = append(desc.Methods, grpc.MethodDesc{MethodName: name, Handler: s.handle(name)})
	}
	opts := []grpc.ServerOption{
		grpc.MaxRecvMsgSize(4 << 20), // P7.5
		grpc.KeepaliveEnforcementPolicy(keepalive.EnforcementPolicy{MinTime: 20 * time.Second}),
		grpc.StatsHandler(cc),
	}
	if age > 0 {
		opts = append(opts, grpc.KeepaliveParams(keepalive.ServerParameters{MaxConnectionAge: age, MaxConnectionAgeGrace: grace}))
	}
	srv := grpc.NewServer(opts...)
	srv.RegisterService(&desc, struct{}{})
	lis, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		panic(err)
	}
	go func() { _ = srv.Serve(lis) }()
	port := lis.Addr().(*net.TCPAddr).Port
	return s, cc, fmt.Sprintf("localhost:%d", port), srv.Stop
}

func dial(target, sc string) *grpc.ClientConn {
	opts := []grpc.DialOption{
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithKeepaliveParams(keepalive.ClientParameters{Time: 30 * time.Second, Timeout: 10 * time.Second}), // P7.6
	}
	if sc != "" {
		opts = append(opts, grpc.WithDefaultServiceConfig(sc))
	}
	conn, err := grpc.NewClient(target, opts...)
	if err != nil {
		panic(err)
	}
	return conn
}

func call(conn *grpc.ClientConn, svc, method, body string, timeout time.Duration) error {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	return conn.Invoke(ctx, "/"+svc+"/"+method, wrapperspb.String(body), new(wrapperspb.StringValue))
}

var failed int

func report(name string, ok bool, detail string) {
	tag := "PASS"
	if !ok {
		tag = "FAIL"
		failed++
	}
	fmt.Printf("%s %s: %s\n", tag, name, detail)
}

func main() {
	comp := protocompile.Compiler{Resolver: protocompile.WithStandardImports(&protocompile.SourceResolver{ImportPaths: []string{"."}})}
	files, err := comp.Compile(context.Background(), "repro.proto")
	if err != nil {
		panic(err)
	}
	sd := files[0].Services().ByName("Widgets")
	svc := string(sd.FullName())
	sc := serviceConfigFor(sd)
	fmt.Println("INFO generated service config:", sc)

	// ---------- (a) 重试与重试预算 ----------
	s, _, target, stop := startServer(sd, 0, 0)
	conn := dial(target, sc)

	err = call(conn, svc, "GetWidget", "t1|fail=2", 3*time.Second)
	report("T1 NO_SIDE_EFFECTS retried on UNAVAILABLE", err == nil && s.count("t1") == 3,
		fmt.Sprintf("err=%v attempts=%d gaps=%v", err, s.count("t1"), s.gaps("t1")))

	err = call(conn, svc, "TouchWidget", "t2|fail=2", 3*time.Second)
	report("T2 IDEMPOTENT retried on UNAVAILABLE", err == nil && s.count("t2") == 3,
		fmt.Sprintf("err=%v attempts=%d", err, s.count("t2")))

	err = call(conn, svc, "CreateWidget", "t3|fail=2", 3*time.Second)
	report("T3 method without option is NOT retried", status.Code(err) == codes.Unavailable && s.count("t3") == 1,
		fmt.Sprintf("code=%v attempts=%d", status.Code(err), s.count("t3")))

	// T1–T3 已经让 conn 的令牌从 10 掉到 6.2（每次失败尝试 −1，每次成功调用 +0.1）。
	// 在同一个 conn 上再测"最多 3 次"，会被预算提前截断：先把这个现象记下来，再用新连接测 maxAttempts。
	err = call(conn, svc, "GetWidget", "t4a|fail=9", 3*time.Second)
	report("T4a same ClientConn after T1–T3: budget already cuts retries short", s.count("t4a") == 2,
		fmt.Sprintf("code=%v attempts=%d (tokens 6.2 → 5.2 retry → 4.2 ≤ 5 stop)", status.Code(err), s.count("t4a")))
	conn.Close()
	conn = dial(target, sc)
	err = call(conn, svc, "GetWidget", "t4|fail=9", 3*time.Second)
	report("T4 at most 3 retries (maxAttempts=4) on a fresh ClientConn", status.Code(err) == codes.Unavailable && s.count("t4") == 4,
		fmt.Sprintf("code=%v attempts=%d gaps=%v (backoff = random(0, min(50ms·2^n, 500ms)))", status.Code(err), s.count("t4"), s.gaps("t4")))
	conn.Close()

	// 重试预算：新连接，一直 UNAVAILABLE，20 次调用
	conn = dial(target, sc)
	total := 0
	for i := 0; i < 20; i++ {
		id := fmt.Sprintf("t5-%d", i)
		_ = call(conn, svc, "GetWidget", id+"|always", 3*time.Second)
		total += s.count(id)
	}
	report("T5 retryThrottling{10,0.1} caps retries", total < 30,
		fmt.Sprintf("20 calls → %d attempts (no throttling would be 80; expected 4+19=23: retries stop once tokens ≤ maxTokens/2)", total))

	err = call(conn, svc, "TouchWidget", "t6|fail=1", 3*time.Second)
	report("T6 budget is shared by all methods on the same ClientConn", status.Code(err) == codes.Unavailable && s.count("t6") == 1,
		fmt.Sprintf("code=%v attempts=%d", status.Code(err), s.count("t6")))

	conn2 := dial(target, sc) // 另一个成员（或另一个依赖）自己的 ClientConn
	err = call(conn2, svc, "GetWidget", "t7|fail=2", 3*time.Second)
	report("T7 budget is per ClientConn: another ClientConn still retries", err == nil && s.count("t7") == 3,
		fmt.Sprintf("err=%v attempts=%d", err, s.count("t7")))

	// 截止时间优先于重试
	start := time.Now()
	err = call(conn2, svc, "GetWidget", "t8|always", 60*time.Millisecond)
	report("T8 retries stop at the call deadline", status.Code(err) == codes.DeadlineExceeded || status.Code(err) == codes.Unavailable,
		fmt.Sprintf("code=%v attempts=%d elapsed=%v", status.Code(err), s.count("t8"), time.Since(start).Round(time.Millisecond)))
	conn.Close()
	conn2.Close()

	// 预算耗尽之后要多少次成功才恢复重试：throttle() 先减 1 再判断 tokens > 5，所以要 tokens ≥ 6.1，即 61 次成功
	for _, k := range []int{55, 61} {
		c := dial(target, sc)
		drain(c, svc, s, fmt.Sprintf("t12-%d", k))
		for i := 0; i < k; i++ {
			_ = call(c, svc, "GetWidget", fmt.Sprintf("t12-%d-ok-%d|ok", k, i), time.Second)
		}
		id := fmt.Sprintf("t12-%d-probe", k)
		_ = call(c, svc, "GetWidget", id+"|fail=1", time.Second)
		want := 1
		if k >= 61 {
			want = 2
		}
		report(fmt.Sprintf("T12 after draining, %d successes → probe attempts=%d", k, want), s.count(id) == want,
			fmt.Sprintf("attempts=%d", s.count(id)))
		c.Close()
	}
	stop()

	// 解析器每次更新都会重新应用 service config，并把重试预算重置成满的（clientconn.go applyServiceConfigAndBalancer）。
	// GOAWAY 之后会不会触发重新解析、从而把预算刷满？dns 解析器两次解析之间至少隔 30 s。
	resetRun(sd, svc, sc)

	// ---------- (b) MaxConnectionAge → GOAWAY → 透明重连 ----------
	// 用 1 s 代替默认的 5 min，只为了几秒内经历多次 GOAWAY；Grace 用设计值 30 s
	ageRun("T9", sd, svc, sc, 1*time.Second, 30*time.Second)

	// 进行中的长调用跨过连接寿命：Grace 30 s 时成功；对照组 Grace 300 ms 时失败（先见红）
	longCall("T10 in-flight call survives GOAWAY with grace 30s", sd, svc, sc, 30*time.Second, true)
	longCall("T11 control: grace 300ms kills the in-flight call", sd, svc, sc, 300*time.Millisecond, false)

	fmt.Printf("== failed=%d\n", failed)
	if failed > 0 {
		os.Exit(1)
	}
}

func drain(c *grpc.ClientConn, svc string, s *server, prefix string) {
	for i := 0; i < 15; i++ {
		_ = call(c, svc, "GetWidget", fmt.Sprintf("%s-drain-%d|always", prefix, i), time.Second)
	}
}

func resetRun(sd protoreflect.ServiceDescriptor, svc, sc string) {
	for _, tc := range []struct {
		name string
		age  time.Duration
		wait time.Duration
		want int // 探针的尝试次数：1 = 仍被限流，2 = 预算被刷满
	}{
		// 等待期间不发成功调用（成功调用本身就会 +0.1 回血，会混淆结论）
		{"T13a no GOAWAY, idle 32s", 0, 32 * time.Second, 1},
		{"T13b GOAWAY every 1s, idle 2s", time.Second, 2 * time.Second, 1},
		{"T13c GOAWAY every 1s, idle 32s (re-resolve allowed again)", time.Second, 32 * time.Second, 2},
	} {
		s, cc, target, stop := startServer(sd, tc.age, 30*time.Second)
		c := dial(target, sc)
		drain(c, svc, s, tc.name)
		time.Sleep(tc.wait)
		id := tc.name + "-probe"
		_ = call(c, svc, "GetWidget", id+"|fail=1", time.Second)
		report(tc.name, s.count(id) == tc.want, fmt.Sprintf("probe attempts=%d want=%d (1 = still throttled, 2 = budget refilled) server connections=%d",
			s.count(id), tc.want, cc.n.Load()))
		c.Close()
		stop()
	}
}

func ageRun(name string, sd protoreflect.ServiceDescriptor, svc, sc string, age, grace time.Duration) {
	_, cc, target, stop := startServer(sd, age, grace)
	defer stop()
	conn := dial(target, sc)
	defer conn.Close()
	var ok, bad atomic.Int64
	codesSeen := sync.Map{}
	deadline := time.Now().Add(6 * time.Second)
	var wg sync.WaitGroup
	for g := 0; g < 8; g++ {
		wg.Add(1)
		go func(g int) {
			defer wg.Done()
			for i := 0; time.Now().Before(deadline); i++ {
				method := "CreateWidget" // 没有 retryPolicy 的方法：只能靠透明重试
				if i%2 == 1 {
					method = "GetWidget"
				}
				if err := call(conn, svc, method, fmt.Sprintf("age-%d-%d|ok", g, i), 2*time.Second); err != nil {
					bad.Add(1)
					codesSeen.Store(status.Code(err).String()+":"+method, true)
				} else {
					ok.Add(1)
				}
			}
		}(g)
	}
	wg.Wait()
	var seen []string
	codesSeen.Range(func(k, _ any) bool { seen = append(seen, k.(string)); return true })
	report(name+" continuous load across GOAWAYs: zero caller-visible errors", bad.Load() == 0 && cc.n.Load() >= 4,
		fmt.Sprintf("ok=%d errors=%d %v server connections=%d in 6s (MaxConnectionAge=%v)", ok.Load(), bad.Load(), seen, cc.n.Load(), age))
}

func longCall(name string, sd protoreflect.ServiceDescriptor, svc, sc string, grace time.Duration, wantOK bool) {
	_, cc, target, stop := startServer(sd, 1*time.Second, grace)
	defer stop()
	conn := dial(target, sc)
	defer conn.Close()
	_ = call(conn, svc, "GetWidget", "warm|ok", time.Second) // 建好连接
	start := time.Now()
	err := call(conn, svc, "CreateWidget", "long|sleep=2500", 10*time.Second)
	after := call(conn, svc, "CreateWidget", "after|ok", 2*time.Second)
	got := err == nil
	report(name, got == wantOK && after == nil,
		fmt.Sprintf("long call err=%v elapsed=%v; next call err=%v; server connections=%d", status.Code(err), time.Since(start).Round(time.Millisecond), after, cc.n.Load()))
}
