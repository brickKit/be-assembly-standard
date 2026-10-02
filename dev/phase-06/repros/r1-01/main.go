// R1 #1：Go 外壳里"每个成员一个 TracerProvider、共用一个导出器"能不能成立；
// otelgrpc 的 stats handler 用的是成员自己的 provider 还是全局的。
//
// 一个假的 OTLP/HTTP 收集器（httptest）解出每个 span 的 service.name / trace_id / parent，
// 每个场景只看收集器真正收到了什么。
package main

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"sort"
	"strings"
	"sync"

	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/baggage"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/metric/metricdata"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
	coltracepb "go.opentelemetry.io/proto/otlp/collector/trace/v1"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/protobuf/proto"
)

// ---------- 假收集器 ----------

type gotSpan struct {
	Service, Name, TraceID, SpanID, Parent string
}

type collector struct {
	srv      *httptest.Server
	mu       sync.Mutex
	spans    []gotSpan
	requests int
}

func newCollector() *collector {
	c := &collector{}
	c.srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var req coltracepb.ExportTraceServiceRequest
		if err := proto.Unmarshal(body, &req); err != nil {
			http.Error(w, err.Error(), 400)
			return
		}
		c.mu.Lock()
		defer c.mu.Unlock()
		c.requests++
		for _, rs := range req.ResourceSpans {
			svc := ""
			for _, kv := range rs.Resource.Attributes {
				if kv.Key == "service.name" {
					svc = kv.Value.GetStringValue()
				}
			}
			for _, ss := range rs.ScopeSpans {
				for _, s := range ss.Spans {
					c.spans = append(c.spans, gotSpan{svc, s.Name,
						fmt.Sprintf("%x", s.TraceId), fmt.Sprintf("%x", s.SpanId), fmt.Sprintf("%x", s.ParentSpanId)})
				}
			}
		}
		w.Header().Set("Content-Type", "application/x-protobuf")
		out, _ := proto.Marshal(&coltracepb.ExportTraceServiceResponse{})
		_, _ = w.Write(out)
	}))
	return c
}

func (c *collector) byService() map[string]int {
	c.mu.Lock()
	defer c.mu.Unlock()
	m := map[string]int{}
	for _, s := range c.spans {
		m[s.Service]++
	}
	return m
}

func (c *collector) find(name, svc string) *gotSpan {
	c.mu.Lock()
	defer c.mu.Unlock()
	for i := range c.spans {
		if c.spans[i].Name == name && (svc == "" || c.spans[i].Service == svc) {
			s := c.spans[i]
			return &s
		}
	}
	return nil
}

func (c *collector) dump() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	var lines []string
	for _, s := range c.spans {
		lines = append(lines, fmt.Sprintf("    %-8s %-32s trace=%s…  span=%s parent=%s", s.Service, s.Name, s.TraceID[:8], s.SpanID[:8], short(s.Parent)))
	}
	sort.Strings(lines)
	return strings.Join(lines, "\n")
}

func short(s string) string {
	if len(s) < 8 {
		return "-"
	}
	return s[:8]
}

// ---------- 帮手 ----------

func exporter(c *collector) *otlptrace.Exporter {
	e, err := otlptracehttp.New(context.Background(),
		otlptracehttp.WithEndpointURL(c.srv.URL+"/v1/traces"), otlptracehttp.WithInsecure())
	if err != nil {
		panic(err)
	}
	return e
}

func res(svc string) *resource.Resource {
	return resource.NewWithAttributes(semconv.SchemaURL, semconv.ServiceName(svc))
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

// 只是"观察到的事实"（不是被测假设本身，比如朴素写法会丢 span），用 OBSERVED 标记
func observed(name, detail string) { fmt.Printf("OBSERVED %s: %s\n", name, detail) }

func emit(tp trace.TracerProvider, name string) {
	_, s := tp.Tracer("repro").Start(context.Background(), name)
	s.End()
}

// noShutdownExporter：成员关自己的 provider 时只 flush，不关共享导出器；导出器由平台最后关
type noShutdownExporter struct{ sdktrace.SpanExporter }

func (noShutdownExporter) Shutdown(context.Context) error { return nil }

// noShutdownProcessor：共享一个 BSP 时，成员的 Shutdown 只变成 ForceFlush
type noShutdownProcessor struct{ sdktrace.SpanProcessor }

func (p noShutdownProcessor) Shutdown(ctx context.Context) error { return p.ForceFlush(ctx) }

var otelErrors []string

// ---------- 场景 ----------

// S1：每个成员自己的 BSP，直接包同一个导出器。成员 A 先停（Shutdown），B 后停。
func s1() {
	c := newCollector()
	defer c.srv.Close()
	e := exporter(c)
	tpA := sdktrace.NewTracerProvider(sdktrace.WithBatcher(e), sdktrace.WithResource(res("A")))
	tpB := sdktrace.NewTracerProvider(sdktrace.WithBatcher(e), sdktrace.WithResource(res("B")))
	emit(tpA, "a1")
	emit(tpB, "b1")
	_ = tpA.Shutdown(context.Background())
	emit(tpB, "b2")
	errB := tpB.Shutdown(context.Background())
	got := c.byService()
	observed("S1 naive per-member BSP + shared exporter", fmt.Sprintf("received=%v (want A:1 B:2), B.Shutdown err=%v", got, errB))
	report("S1 naive shared exporter loses spans of later members", got["B"] == 0, "shared exporter is closed by the first member's Shutdown")
}

// S2：一个 BSP 实例注册进两个 provider。
func s2() {
	c := newCollector()
	defer c.srv.Close()
	bsp := sdktrace.NewBatchSpanProcessor(exporter(c))
	tpA := sdktrace.NewTracerProvider(sdktrace.WithSpanProcessor(bsp), sdktrace.WithResource(res("A")))
	tpB := sdktrace.NewTracerProvider(sdktrace.WithSpanProcessor(bsp), sdktrace.WithResource(res("B")))
	emit(tpA, "a1")
	emit(tpB, "b1")
	_ = tpA.Shutdown(context.Background())
	emit(tpB, "b2")
	errB := tpB.Shutdown(context.Background())
	got := c.byService()
	observed("S2 one BSP registered in two providers", fmt.Sprintf("received=%v (want A:1 B:2), B.Shutdown err=%v", got, errB))
	report("S2 naive shared BSP loses spans after first member stops", got["B"] < 2, "the shared BSP is shut down by the first provider")
}

// S3：每个成员自己的 BSP，共享导出器包一层 noShutdown；平台最后关导出器。
func s3() {
	c := newCollector()
	defer c.srv.Close()
	e := exporter(c)
	shared := noShutdownExporter{e}
	tpA := sdktrace.NewTracerProvider(sdktrace.WithBatcher(shared), sdktrace.WithResource(res("A")))
	tpB := sdktrace.NewTracerProvider(sdktrace.WithBatcher(shared), sdktrace.WithResource(res("B")))
	emit(tpA, "a1")
	emit(tpB, "b1")
	_ = tpA.Shutdown(context.Background())
	emit(tpB, "b2")
	_ = tpB.Shutdown(context.Background())
	_ = e.Shutdown(context.Background()) // 平台关闭
	got := c.byService()
	report("S3 per-member BSP + shared exporter (no-op Shutdown)", got["A"] == 1 && got["B"] == 2,
		fmt.Sprintf("received=%v requests=%d", got, c.requests))
}

// S4：一个共享 BSP，成员侧包一层（Shutdown→ForceFlush）；平台最后关真的 BSP。
func s4() {
	c := newCollector()
	defer c.srv.Close()
	bsp := sdktrace.NewBatchSpanProcessor(exporter(c))
	tpA := sdktrace.NewTracerProvider(sdktrace.WithSpanProcessor(noShutdownProcessor{bsp}), sdktrace.WithResource(res("A")))
	tpB := sdktrace.NewTracerProvider(sdktrace.WithSpanProcessor(noShutdownProcessor{bsp}), sdktrace.WithResource(res("B")))
	for i := 0; i < 5; i++ {
		emit(tpA, "a")
		emit(tpB, "b")
	}
	_ = tpA.Shutdown(context.Background())
	emit(tpB, "b-after-A-stopped")
	_ = tpB.Shutdown(context.Background())
	_ = bsp.Shutdown(context.Background()) // 平台关闭
	got := c.byService()
	report("S4 one shared BSP (member Shutdown = ForceFlush)", got["A"] == 5 && got["B"] == 6,
		fmt.Sprintf("received=%v requests=%d (spans of both resources share batches)", got, c.requests))
}

// ---------- gRPC：成员 A 是服务端，成员 B 是客户端，同一进程两个端口 ----------

type healthA struct {
	grpc_health_v1.UnimplementedHealthServer
	tracer     trace.Tracer // 成员 A 自己的 tracer（rt.Tracer()）
	gotBaggage string
}

func (h *healthA) Check(ctx context.Context, _ *grpc_health_v1.HealthCheckRequest) (*grpc_health_v1.HealthCheckResponse, error) {
	_, s := h.tracer.Start(ctx, "A.handler.child")
	s.End()
	h.gotBaggage = baggage.FromContext(ctx).Member("tenant").Value()
	return &grpc_health_v1.HealthCheckResponse{Status: grpc_health_v1.HealthCheckResponse_SERVING}, nil
}

type grpcCase struct {
	serverOpts, clientOpts []otelgrpc.Option
}

// runGRPC：B 开一个 span "B.request"，在里面调 A 的 Check。
func runGRPC(tpA, tpB trace.TracerProvider, gc grpcCase) (*healthA, error) {
	lis, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	h := &healthA{tracer: tpA.Tracer("member-a")}
	srv := grpc.NewServer(grpc.StatsHandler(otelgrpc.NewServerHandler(gc.serverOpts...)))
	grpc_health_v1.RegisterHealthServer(srv, h)
	go func() { _ = srv.Serve(lis) }()
	defer srv.Stop()

	conn, err := grpc.NewClient(lis.Addr().String(),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithStatsHandler(otelgrpc.NewClientHandler(gc.clientOpts...)))
	if err != nil {
		return nil, err
	}
	defer conn.Close()

	m, _ := baggage.NewMemberRaw("tenant", "t-42")
	bg, _ := baggage.New(m)
	ctx := baggage.ContextWithBaggage(context.Background(), bg)
	ctx, root := tpB.Tracer("member-b").Start(ctx, "B.request")
	_, err = grpc_health_v1.NewHealthClient(conn).Check(ctx, &grpc_health_v1.HealthCheckRequest{})
	root.End()
	return h, err
}

const rpcName = "grpc.health.v1.Health/Check"

type members struct {
	c        *collector
	exp      *otlptrace.Exporter
	tpA, tpB *sdktrace.TracerProvider
}

func newMembers() *members {
	c := newCollector()
	e := exporter(c)
	shared := noShutdownExporter{e}
	return &members{c: c, exp: e,
		tpA: sdktrace.NewTracerProvider(sdktrace.WithBatcher(shared), sdktrace.WithResource(res("A"))),
		tpB: sdktrace.NewTracerProvider(sdktrace.WithBatcher(shared), sdktrace.WithResource(res("B")))}
}

func (m *members) flush() {
	_ = m.tpA.Shutdown(context.Background())
	_ = m.tpB.Shutdown(context.Background())
	_ = m.exp.Shutdown(context.Background())
	m.c.srv.Close()
}

// G1：只给 WithTracerProvider，不给传播器（全局传播器保持默认 = 空）
func g1() {
	m := newMembers()
	_, err := runGRPC(m.tpA, m.tpB, grpcCase{
		serverOpts: []otelgrpc.Option{otelgrpc.WithTracerProvider(m.tpA)},
		clientOpts: []otelgrpc.Option{otelgrpc.WithTracerProvider(m.tpB)},
	})
	m.flush()
	srv, cli := m.c.find(rpcName, "A"), m.c.find(rpcName, "B")
	ok := err == nil && srv != nil && cli != nil
	fmt.Println(m.c.dump())
	report("G1 WithTracerProvider: server span under member A, client span under member B", ok, fmt.Sprintf("err=%v", err))
	if ok {
		observed("G1 without WithPropagators", fmt.Sprintf("same trace=%v (server.parent==client.span: %v)",
			srv.TraceID == cli.TraceID, srv.Parent == cli.SpanID))
		report("G1 trace breaks without an explicit propagator", srv.TraceID != cli.TraceID,
			"otelgrpc falls back to the global propagator, which is a no-op unless someone calls otel.SetTextMapPropagator")
	}
}

// G2：WithTracerProvider + WithPropagators（显式，不碰全局）
func g2() {
	m := newMembers()
	prop := propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{})
	h, err := runGRPC(m.tpA, m.tpB, grpcCase{
		serverOpts: []otelgrpc.Option{otelgrpc.WithTracerProvider(m.tpA), otelgrpc.WithPropagators(prop)},
		clientOpts: []otelgrpc.Option{otelgrpc.WithTracerProvider(m.tpB), otelgrpc.WithPropagators(prop)},
	})
	m.flush()
	fmt.Println(m.c.dump())
	srv, cli, root, child := m.c.find(rpcName, "A"), m.c.find(rpcName, "B"), m.c.find("B.request", "B"), m.c.find("A.handler.child", "A")
	ok := err == nil && srv != nil && cli != nil && root != nil && child != nil &&
		cli.Parent == root.SpanID && srv.Parent == cli.SpanID && child.Parent == srv.SpanID &&
		srv.TraceID == root.TraceID && child.TraceID == root.TraceID
	report("G2 per-member provider + explicit propagator: one trace B.request→client→server→child, right service.name each", ok,
		fmt.Sprintf("err=%v baggage(tenant)=%q", err, h.gotBaggage))
	report("G2 baggage crosses the call", h != nil && h.gotBaggage == "t-42", "")
}

// G3：什么都不给（默认）：otelgrpc 用全局 provider。全局设成 "GLOBAL" 以便识别。
func g3() {
	m := newMembers()
	cg := newCollector()
	eg := exporter(cg)
	tpG := sdktrace.NewTracerProvider(sdktrace.WithBatcher(eg), sdktrace.WithResource(res("GLOBAL")))
	otel.SetTracerProvider(tpG)
	_, err := runGRPC(m.tpA, m.tpB, grpcCase{})
	m.flush()
	_ = tpG.Shutdown(context.Background())
	cg.srv.Close()
	fmt.Println(cg.dump())
	gotG := cg.byService()
	report("G3 default otelgrpc handlers use the GLOBAL provider, not the member's", err == nil && gotG["GLOBAL"] == 2 &&
		m.c.find(rpcName, "") == nil, fmt.Sprintf("global collector=%v member collector has rpc spans=%v", gotG, m.c.find(rpcName, "") != nil))
	otel.SetTracerProvider(trace.NewNoopTracerProvider()) //nolint:staticcheck // 复原
}

// G4：指标同理：默认用全局 MeterProvider；WithMeterProvider 才进成员自己的
func g4() {
	m := newMembers()
	defer m.flush()
	globalReader, memberReader := sdkmetric.NewManualReader(), sdkmetric.NewManualReader()
	otel.SetMeterProvider(sdkmetric.NewMeterProvider(sdkmetric.WithReader(globalReader)))
	mpA := sdkmetric.NewMeterProvider(sdkmetric.WithReader(memberReader))
	_, err := runGRPC(m.tpA, m.tpB, grpcCase{
		serverOpts: []otelgrpc.Option{otelgrpc.WithTracerProvider(m.tpA)}, // 故意不给 WithMeterProvider
	})
	count := func(r sdkmetric.Reader) int {
		var rm metricdata.ResourceMetrics
		_ = r.Collect(context.Background(), &rm)
		n := 0
		for _, sm := range rm.ScopeMetrics {
			n += len(sm.Metrics)
		}
		return n
	}
	g, mem := count(globalReader), count(memberReader)
	_, err2 := runGRPC(m.tpA, m.tpB, grpcCase{
		serverOpts: []otelgrpc.Option{otelgrpc.WithTracerProvider(m.tpA), otelgrpc.WithMeterProvider(mpA)},
	})
	mem2 := count(memberReader)
	report("G4 otelgrpc metrics go to the global MeterProvider unless WithMeterProvider is given",
		err == nil && err2 == nil && g > 0 && mem == 0 && mem2 > 0,
		fmt.Sprintf("default: global=%d member=%d metrics; with WithMeterProvider: member=%d", g, mem, mem2))
}

func main() {
	otel.SetErrorHandler(otel.ErrorHandlerFunc(func(err error) { otelErrors = append(otelErrors, err.Error()) }))
	s1()
	s2()
	s3()
	s4()
	g1()
	g2()
	g3()
	g4()
	if len(otelErrors) > 0 {
		fmt.Printf("INFO otel error handler saw %d errors, first: %s\n", len(otelErrors), otelErrors[0])
	}
	fmt.Printf("== failed=%d\n", failed)
	if failed > 0 {
		os.Exit(1)
	}
}
