// r1-07 (nats.go jetstream): durable naming, DeliverAll, BackOff vs MaxDeliver, Nak vs BackOff,
// InProgress vs AckWait/BackOff, MAX_DELIVERIES advisory. Same scenarios as ../py and ../js.
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/nats-io/nats.go"
	"github.com/nats-io/nats.go/jetstream"
)

const seg = "r1go" // subject first segment -> stream BE_R1GO (P12.4)

var (
	ctx = context.Background()
	js  jetstream.JetStream
	nc  *nats.Conn
)

// P12.5: <component id, / -> _>__<subject, . -> _>
func durableName(component, subject string) string {
	return strings.ReplaceAll(component, "/", "_") + "__" + strings.ReplaceAll(subject, ".", "_")
}

func must[T any](v T, err error) T {
	if err != nil {
		panic(err)
	}
	return v
}

func pub(subject string, n int) {
	for i := 0; i < n; i++ {
		must(js.Publish(ctx, subject, []byte(fmt.Sprintf(`{"n":%d}`, i))))
	}
}

type delivery struct {
	at  time.Duration
	num uint64
}

// consume runs handler for each delivery of the first message for `window`, recording delivery times.
func consume(cons jetstream.Consumer, window time.Duration, h func(m jetstream.Msg, d int)) []delivery {
	var out []delivery
	start := time.Time{}
	deadline := time.Now().Add(window)
	for time.Now().Before(deadline) {
		batch, err := cons.Fetch(1, jetstream.FetchMaxWait(200*time.Millisecond))
		if err != nil {
			continue
		}
		for m := range batch.Messages() {
			md, _ := m.Metadata()
			if start.IsZero() {
				start = time.Now()
			}
			out = append(out, delivery{time.Since(start).Round(10 * time.Millisecond), md.NumDelivered})
			h(m, len(out))
		}
	}
	return out
}

func newCons(name, subject string, cfg jetstream.ConsumerConfig) (jetstream.Consumer, error) {
	cfg.Durable = name
	cfg.FilterSubject = subject
	cfg.AckPolicy = jetstream.AckExplicitPolicy
	return js.CreateConsumer(ctx, "BE_"+strings.ToUpper(seg), cfg)
}

func main() {
	nc = must(nats.Connect(os.Getenv("NATS_URL")))
	defer nc.Close()
	js = must(jetstream.New(nc))
	stream := "BE_" + strings.ToUpper(seg)
	_ = js.DeleteStream(ctx, stream)
	// P12.4 defaults: 7 d, 1 GiB, discard old, dedupe window 10 min, file storage, 1 replica
	must(js.CreateStream(ctx, jetstream.StreamConfig{Name: stream, Subjects: []string{seg + ".>"},
		MaxAge: 7 * 24 * time.Hour, MaxBytes: 1 << 30, Discard: jetstream.DiscardOld,
		Duplicates: 10 * time.Minute, Storage: jetstream.FileStorage, Replicas: 1}))
	fmt.Printf("===== nats.go %s, server %s\n", nats.Version, nc.ConnectedServerVersion())

	// T1 naming + T2 DeliverAll: 3 events published before the durable exists
	subj := seg + ".order.confirmed.v1"
	pub(subj, 3)
	name := durableName("crm/opportunity", subj)
	base := jetstream.ConsumerConfig{DeliverPolicy: jetstream.DeliverAllPolicy, AckWait: 30 * time.Second,
		MaxAckPending: 256, MaxDeliver: 8, InactiveThreshold: 30 * 24 * time.Hour,
		BackOff: []time.Duration{time.Second, 10 * time.Second, time.Minute, 5 * time.Minute, 15 * time.Minute, 30 * time.Minute, time.Hour}}
	c := must(newCons(name, subj, base))
	info := must(c.Info(ctx))
	fmt.Printf("T1 durable %q created; hyphen variant %q -> ", name, durableName("infra/iam-casdoor", subj))
	_, err := newCons(durableName("infra/iam-casdoor", subj), subj, base)
	fmt.Println(errOr(err))
	fmt.Printf("T1 config read back: AckWait=%s MaxDeliver=%d BackOff=%v InactiveThreshold=%s MaxAckPending=%d\n",
		info.Config.AckWait, info.Config.MaxDeliver, info.Config.BackOff, info.Config.InactiveThreshold, info.Config.MaxAckPending)
	b := must(c.Fetch(10, jetstream.FetchMaxWait(time.Second)))
	n := 0
	for m := range b.Messages() {
		n++
		_ = m.Ack()
	}
	fmt.Printf("T2 DeliverAll on first create: fetched %d of 3 pre-existing events\n", n)

	// T3 create-if-absent semantics
	_, err = newCons(name, subj, base)
	fmt.Println("T3 CreateConsumer again, identical config:", errOr(err))
	changed := base
	changed.MaxDeliver = 9
	_, err = newCons(name, subj, changed)
	fmt.Println("T3 CreateConsumer again, MaxDeliver 8->9:", errOr(err))
	changed.Durable, changed.FilterSubject, changed.AckPolicy = name, subj, jetstream.AckExplicitPolicy
	u, err := js.UpdateConsumer(ctx, stream, changed)
	if err == nil {
		fmt.Println("T3 UpdateConsumer MaxDeliver 8->9:", "ok, MaxDeliver now", must(u.Info(ctx)).Config.MaxDeliver)
	} else {
		fmt.Println("T3 UpdateConsumer:", err)
	}
	changed.DeliverPolicy = jetstream.DeliverNewPolicy
	_, err = js.UpdateConsumer(ctx, stream, changed)
	fmt.Println("T3 UpdateConsumer DeliverPolicy all->new:", errOr(err))

	// T4a BackOff length vs MaxDeliver (compconf values: EVENTS_BACKOFF=200ms,500ms,1s EVENTS_MAX_DELIVER=3)
	bo := []time.Duration{200 * time.Millisecond, 500 * time.Millisecond, time.Second}
	_, err = newCons("t4a", seg+".t4a", jetstream.ConsumerConfig{AckWait: 30 * time.Second, MaxDeliver: 3, BackOff: bo})
	fmt.Println("T4a BackOff len 3, MaxDeliver 3:", errOr(err))
	_, err = newCons("t4a2", seg+".t4a", jetstream.ConsumerConfig{AckWait: 30 * time.Second, MaxDeliver: 4, BackOff: bo})
	fmt.Println("T4a BackOff len 3, MaxDeliver 4:", errOr(err))
	c4 := must(js.Consumer(ctx, stream, "t4a2"))
	fmt.Println("T4a stored AckWait when AckWait=30s and BackOff[0]=200ms:", must(c4.Info(ctx)).Config.AckWait)
	_, err = newCons("t4a4", seg+".t4a", jetstream.ConsumerConfig{AckWait: 30 * time.Second, MaxDeliver: 2, BackOff: bo})
	fmt.Println("T4a BackOff len 3, MaxDeliver 2:", errOr(err))
	_, err = newCons("t4a3", seg+".t4a", jetstream.ConsumerConfig{AckWait: 30 * time.Second, MaxDeliver: -1, BackOff: bo})
	fmt.Println("T4a BackOff len 3, MaxDeliver -1 (unlimited):", errOr(err))

	// advisory listener (core NATS) for T4b/T4c
	adv, _ := nc.SubscribeSync("$JS.EVENT.ADVISORY.CONSUMER.MAX_DELIVERIES." + stream + ".>")

	// T4b handler never acks -> redeliveries on ack timeout follow BackOff
	s4b := seg + ".t4b"
	c4b := must(newCons("t4b", s4b, jetstream.ConsumerConfig{AckWait: 30 * time.Second, MaxDeliver: 4, BackOff: bo}))
	pub(s4b, 1)
	fmt.Println("T4b no ack (timeout path), BackOff 200ms,500ms,1s MaxDeliver 4:", consume(c4b, 4*time.Second, func(jetstream.Msg, int) {}))

	// T4c handler Naks immediately -> does BackOff apply to Nak?
	s4c := seg + ".t4c"
	c4c := must(newCons("t4c", s4c, jetstream.ConsumerConfig{AckWait: 30 * time.Second, MaxDeliver: 4, BackOff: bo}))
	pub(s4c, 1)
	fmt.Println("T4c Nak() each time, same BackOff:", consume(c4c, 3*time.Second, func(m jetstream.Msg, _ int) { _ = m.Nak() }))

	// T4d NakWithDelay(BackOff[n-1]) computed by the client
	s4d := seg + ".t4d"
	c4d := must(newCons("t4d", s4d, jetstream.ConsumerConfig{AckWait: 30 * time.Second, MaxDeliver: 4, BackOff: bo}))
	pub(s4d, 1)
	fmt.Println("T4d NakWithDelay(BackOff[n-1]):", consume(c4d, 4*time.Second, func(m jetstream.Msg, d int) { _ = m.NakWithDelay(bo[min(d-1, len(bo)-1)]) }))

	// T4e proposed shape: no server BackOff, AckWait 30s, client-side NakWithDelay(EVENTS_BACKOFF[n-1])
	s4e := seg + ".t4e"
	c4e := must(newCons("t4e", s4e, jetstream.ConsumerConfig{AckWait: 30 * time.Second, MaxDeliver: 4}))
	fmt.Println("T4e stored AckWait without BackOff:", must(c4e.Info(ctx)).Config.AckWait)
	pub(s4e, 1)
	fmt.Println("T4e no BackOff, AckWait 30s, NakWithDelay(EVENTS_BACKOFF[n-1]):", consume(c4e, 4*time.Second, func(m jetstream.Msg, d int) { _ = m.NakWithDelay(bo[min(d-1, len(bo)-1)]) }))

	for i := 0; i < 5; i++ {
		am, err := adv.NextMsg(500 * time.Millisecond)
		if err != nil {
			break
		}
		var a map[string]any
		_ = json.Unmarshal(am.Data, &a)
		fmt.Printf("T4 advisory %s: consumer=%v stream_seq=%v deliveries=%v\n", am.Subject, a["consumer"], a["stream_seq"], a["deliveries"])
	}

	// T5a InProgress with AckWait 2s, no BackOff: handler takes 5 s, InProgress every AckWait/3
	s5 := seg + ".t5a"
	c5 := must(newCons("t5a", s5, jetstream.ConsumerConfig{AckWait: 2 * time.Second, MaxDeliver: 5}))
	pub(s5, 1)
	fmt.Println("T5a AckWait 2s, slow handler 4s with InProgress every 0.66s (AckWait/3):", consumeAsync(c5, 8*time.Second, 660*time.Millisecond))
	// T5b control: same, no InProgress
	s5b := seg + ".t5b"
	c5b := must(newCons("t5b", s5b, jetstream.ConsumerConfig{AckWait: 2 * time.Second, MaxDeliver: 5}))
	pub(s5b, 1)
	fmt.Println("T5b control, slow handler 4s, no InProgress:", consumeAsync(c5b, 8*time.Second, 0))

	// T5c BackOff set: AckWait 6s, BackOff [1s,2s,3s], MaxDeliver 5; handler 4 s with InProgress every AckWait/3 = 2 s
	bo2 := []time.Duration{time.Second, 2 * time.Second, 3 * time.Second}
	s5c := seg + ".t5c"
	c5c := must(newCons("t5c", s5c, jetstream.ConsumerConfig{AckWait: 6 * time.Second, MaxDeliver: 5, BackOff: bo2}))
	pub(s5c, 1)
	fmt.Println("T5c AckWait 6s + BackOff [1s,2s,3s], handler 4s, InProgress every 2s (AckWait/3):", consumeAsync(c5c, 9*time.Second, 2*time.Second))
	// T5d same, InProgress every BackOff[0]/3
	s5d := seg + ".t5d"
	c5d := must(newCons("t5d", s5d, jetstream.ConsumerConfig{AckWait: 6 * time.Second, MaxDeliver: 5, BackOff: bo2}))
	pub(s5d, 1)
	fmt.Println("T5d same, InProgress every 330ms (BackOff[0]/3):", consumeAsync(c5d, 9*time.Second, 330*time.Millisecond))

	// T6 alternative: server MaxDeliver -1, the SDK enforces EVENTS_MAX_DELIVER=2 itself. Deliveries 1-2 "crash"
	// (no ack, AckWait 1s); delivery 3 has NumDelivered > 2 -> DLQ publish + Term without running the handler.
	s6 := seg + ".t6"
	c6 := must(newCons("t6", s6, jetstream.ConsumerConfig{AckWait: time.Second, MaxDeliver: -1}))
	_ = js.DeleteStream(ctx, "BE_DLQ_R1GO")
	dlq := must(js.CreateStream(ctx, jetstream.StreamConfig{Name: "BE_DLQ_R1GO", Subjects: []string{"dlq.t6.>"}, Duplicates: 10 * time.Minute}))
	pub(s6, 1)
	fmt.Println("T6 MaxDeliver -1, SDK-side limit 2, handler crashes (no ack):", consume(c6, 5*time.Second, func(m jetstream.Msg, _ int) {
		if md, _ := m.Metadata(); md.NumDelivered > 2 {
			_, _ = js.Publish(ctx, "dlq.t6."+m.Subject(), m.Data(), jetstream.WithMsgID(fmt.Sprintf("dlq:t6:%d", md.Sequence.Stream)))
			_ = m.Term()
		}
	}))
	fmt.Println("T6 DLQ stream messages:", must(dlq.Info(ctx)).State.Msgs)
}

// slow simulates a handler of duration d that sends InProgress every `every` (0 = never), then acks.
func slow(m jetstream.Msg, d, every time.Duration) {
	end := time.Now().Add(d)
	for time.Now().Before(end) {
		if every > 0 {
			time.Sleep(every)
			_ = m.InProgress()
		} else {
			time.Sleep(100 * time.Millisecond)
		}
	}
	_ = m.Ack()
}

// consumeAsync: handler runs concurrently (as an SDK with concurrency 4 would), so redeliveries during a slow
// first handler are observable. The first delivery is slow (4-5 s); later deliveries ack at once.
func consumeAsync(cons jetstream.Consumer, window, every time.Duration) []delivery {
	var out []delivery
	start := time.Time{}
	deadline := time.Now().Add(window)
	for time.Now().Before(deadline) {
		batch, err := cons.Fetch(1, jetstream.FetchMaxWait(200*time.Millisecond))
		if err != nil {
			continue
		}
		for m := range batch.Messages() {
			md, _ := m.Metadata()
			if start.IsZero() {
				start = time.Now()
			}
			out = append(out, delivery{time.Since(start).Round(10 * time.Millisecond), md.NumDelivered})
			if len(out) == 1 {
				go slow(m, 4*time.Second, every)
			} else {
				_ = m.Ack()
			}
		}
	}
	return out
}

func errOr(err error) string {
	if err != nil {
		return "ERR " + err.Error()
	}
	return "ok"
}

func (d delivery) String() string { return fmt.Sprintf("+%s(n=%d)", d.at, d.num) }
