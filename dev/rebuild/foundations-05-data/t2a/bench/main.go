// Command bench compares two pure-Go Parquet libraries for the tiering's cold route (foundations item 5, T2a): the
// same rows written with a schema built at run time (the SDK does not know a component's columns at compile time),
// zstd, row groups of 100,000 rows; then read back, every value touched. One library and one operation per process,
// so the peak resident memory (VmHWM) is that operation's.
//
// Usage: bench <pq|arrow> <write|read> <rows> <file>
// Output: one JSON line {lib, op, rows, wall_ms, cpu_ms, hwm_kib, bytes, check}; check is a fold of the values read
// (equal for both libraries when they read the same content).
package main

import (
	"context"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"math/rand/v2"
	"os"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/apache/arrow-go/v18/arrow"
	"github.com/apache/arrow-go/v18/arrow/array"
	"github.com/apache/arrow-go/v18/arrow/decimal128"
	"github.com/apache/arrow-go/v18/arrow/memory"
	aparquet "github.com/apache/arrow-go/v18/parquet"
	acompress "github.com/apache/arrow-go/v18/parquet/compress"
	afile "github.com/apache/arrow-go/v18/parquet/file"
	"github.com/apache/arrow-go/v18/parquet/pqarrow"
	"github.com/parquet-go/parquet-go"
	"github.com/parquet-go/parquet-go/compress/zstd"
)

const rowGroup = 100_000

// row is one generated row: the same values for both libraries.
type row struct {
	id, entity [16]byte
	code       string
	name       *string
	amount     int64 // decimal(19,4), scaled
	quantity   int64
	closedAt   int64 // microseconds since the epoch, UTC
	day        int32 // days since the epoch
	active     bool
	attrs      *string
}

func gen(i int) row {
	r := rand.New(rand.NewPCG(uint64(i), 20261106))
	var x row
	binary.BigEndian.PutUint64(x.id[:8], r.Uint64())
	binary.BigEndian.PutUint64(x.id[8:], uint64(i))
	binary.BigEndian.PutUint64(x.entity[:8], uint64(i%7))
	x.code = "SO-2026-" + strconv.Itoa(1000000+i)
	if i%5 != 0 {
		s := "客户 " + strconv.Itoa(r.IntN(5000)) + " 的订单 " + strings.Repeat("x", r.IntN(30))
		x.name = &s
	}
	x.amount = r.Int64N(1_000_000_000_000)
	x.quantity = r.Int64N(10_000)
	x.closedAt = time.Date(2025, 1, 1, 0, 0, 0, 0, time.UTC).UnixMicro() + r.Int64N(365*24*3600*1_000_000)
	x.day = int32(20089 + r.IntN(365))
	x.active = r.IntN(2) == 0
	if i%3 == 0 {
		s := `{"channel":"web","lines":` + strconv.Itoa(r.IntN(40)) + `}`
		x.attrs = &s
	}
	return x
}

func main() {
	if len(os.Args) != 5 {
		fmt.Fprintln(os.Stderr, "usage: bench <pq|arrow> <write|read> <rows> <file>")
		os.Exit(2)
	}
	lib, op, file := os.Args[1], os.Args[2], os.Args[4]
	n, err := strconv.Atoi(os.Args[3])
	must(err)
	var ru0 syscall.Rusage
	_ = syscall.Getrusage(syscall.RUSAGE_SELF, &ru0)
	start := time.Now()
	var check uint64
	switch lib + "/" + op {
	case "pq/write":
		pqWrite(n, file)
	case "pq/read":
		check = pqRead(file)
	case "arrow/write":
		arrowWrite(n, file)
	case "arrow/read":
		check = arrowRead(file)
	default:
		must(fmt.Errorf("unknown %s %s", lib, op))
	}
	wall := time.Since(start)
	var ru1 syscall.Rusage
	_ = syscall.Getrusage(syscall.RUSAGE_SELF, &ru1)
	cpu := time.Duration(ru1.Utime.Nano()+ru1.Stime.Nano()-ru0.Utime.Nano()-ru0.Stime.Nano()) * time.Nanosecond
	st, err := os.Stat(file)
	must(err)
	out, _ := json.Marshal(map[string]any{"lib": lib, "op": op, "rows": n, "wall_ms": wall.Milliseconds(),
		"cpu_ms": cpu.Milliseconds(), "hwm_kib": hwm(), "bytes": st.Size(), "check": check})
	fmt.Println(string(out))
}

func must(err error) {
	if err != nil {
		fmt.Fprintln(os.Stderr, "bench:", err)
		os.Exit(1)
	}
}

// hwm is the process's peak resident set (VmHWM, KiB).
func hwm() int64 {
	raw, err := os.ReadFile("/proc/self/status")
	must(err)
	for _, l := range strings.Split(string(raw), "\n") {
		if strings.HasPrefix(l, "VmHWM:") {
			v, _ := strconv.ParseInt(strings.Fields(l)[1], 10, 64)
			return v
		}
	}
	return 0
}

// fold mixes a value into the check (order-sensitive, so both readers must return rows in the same order).
func fold(c, v uint64) uint64 { return (c ^ v) * 1099511628211 }

func foldBytes(c uint64, b []byte) uint64 {
	for _, x := range b {
		c = fold(c, uint64(x))
	}
	return fold(c, uint64(len(b)))
}

// ---- parquet-go: a schema built from parquet.Group (columns in name order), rows as parquet.Row ----

func pqSchema() *parquet.Schema {
	return parquet.NewSchema("unit", parquet.Group{
		"active":    parquet.Leaf(parquet.BooleanType),
		"amount":    parquet.Decimal(4, 19, parquet.FixedLenByteArrayType(9)), // 19 digits: 9 bytes, as arrow writes it
		"attrs":     parquet.Optional(parquet.JSON()),
		"closed_at": parquet.Timestamp(parquet.Microsecond),
		"code":      parquet.String(),
		"day":       parquet.Date(),
		"entity":    parquet.UUID(),
		"id":        parquet.UUID(),
		"name":      parquet.Optional(parquet.String()),
		"quantity":  parquet.Int(64),
	})
}

// dec9 is a decimal's unscaled value as 9 bytes, big-endian two's complement (the Parquet DECIMAL encoding).
func dec9(v int64) []byte {
	b := make([]byte, 9)
	if v < 0 {
		b[0] = 0xff
	}
	binary.BigEndian.PutUint64(b[1:], uint64(v))
	return b
}

func opt(s *string, col int) parquet.Value {
	if s == nil {
		return parquet.NullValue().Level(0, 0, col)
	}
	return parquet.ByteArrayValue([]byte(*s)).Level(0, 1, col)
}

func pqWrite(n int, path string) {
	f, err := os.Create(path)
	must(err)
	w := parquet.NewWriter(f, pqSchema(), parquet.Compression(&zstd.Codec{}), parquet.MaxRowsPerRowGroup(rowGroup))
	batch := make([]parquet.Row, 0, 1024)
	flush := func() {
		_, err := w.WriteRows(batch)
		must(err)
		batch = batch[:0]
	}
	for i := 0; i < n; i++ {
		x := gen(i)
		batch = append(batch, parquet.Row{
			parquet.BooleanValue(x.active).Level(0, 0, 0),
			parquet.FixedLenByteArrayValue(dec9(x.amount)).Level(0, 0, 1),
			opt(x.attrs, 2),
			parquet.Int64Value(x.closedAt).Level(0, 0, 3),
			parquet.ByteArrayValue([]byte(x.code)).Level(0, 0, 4),
			parquet.Int32Value(x.day).Level(0, 0, 5),
			parquet.FixedLenByteArrayValue(x.entity[:]).Level(0, 0, 6),
			parquet.FixedLenByteArrayValue(x.id[:]).Level(0, 0, 7),
			opt(x.name, 8),
			parquet.Int64Value(x.quantity).Level(0, 0, 9),
		})
		if len(batch) == cap(batch) {
			flush()
		}
	}
	flush()
	must(w.Close())
	must(f.Close())
}

func pqRead(path string) uint64 {
	f, err := os.Open(path)
	must(err)
	defer f.Close()
	r := parquet.NewReader(f)
	defer r.Close()
	rows := make([]parquet.Row, 1024)
	var c uint64
	for {
		k, err := r.ReadRows(rows)
		for _, rw := range rows[:k] {
			for _, v := range rw {
				if v.IsNull() {
					c = fold(c, 0)
					continue
				}
				switch v.Kind() {
				case parquet.Boolean:
					if v.Boolean() {
						c = fold(c, 1)
					} else {
						c = fold(c, 2)
					}
				case parquet.Int32:
					c = fold(c, uint64(v.Int32()))
				case parquet.Int64:
					c = fold(c, uint64(v.Int64()))
				default:
					c = foldBytes(c, v.ByteArray())
				}
			}
		}
		if err == io.EOF {
			return c
		}
		must(err)
	}
}

// ---- arrow-go: an arrow schema (the same name order), records of 64Ki rows through pqarrow ----

func arrowSchema() *arrow.Schema {
	ts := &arrow.TimestampType{Unit: arrow.Microsecond, TimeZone: "UTC"}
	return arrow.NewSchema([]arrow.Field{
		{Name: "active", Type: arrow.FixedWidthTypes.Boolean},
		{Name: "amount", Type: &arrow.Decimal128Type{Precision: 19, Scale: 4}},
		{Name: "attrs", Type: arrow.BinaryTypes.String, Nullable: true},
		{Name: "closed_at", Type: ts},
		{Name: "code", Type: arrow.BinaryTypes.String},
		{Name: "day", Type: arrow.FixedWidthTypes.Date32},
		{Name: "entity", Type: &arrow.FixedSizeBinaryType{ByteWidth: 16}},
		{Name: "id", Type: &arrow.FixedSizeBinaryType{ByteWidth: 16}},
		{Name: "name", Type: arrow.BinaryTypes.String, Nullable: true},
		{Name: "quantity", Type: arrow.PrimitiveTypes.Int64},
	}, nil)
}

func arrowWrite(n int, path string) {
	f, err := os.Create(path)
	must(err)
	schema := arrowSchema()
	props := aparquet.NewWriterProperties(aparquet.WithCompression(acompress.Codecs.Zstd),
		aparquet.WithMaxRowGroupLength(rowGroup))
	w, err := pqarrow.NewFileWriter(schema, f, props, pqarrow.DefaultWriterProps())
	must(err)
	b := array.NewRecordBuilder(memory.DefaultAllocator, schema)
	defer b.Release()
	flush := func() {
		rec := b.NewRecordBatch()
		must(w.WriteBuffered(rec))
		rec.Release()
	}
	str := func(fb *array.StringBuilder, s *string) {
		if s == nil {
			fb.AppendNull()
		} else {
			fb.Append(*s)
		}
	}
	for i := 0; i < n; i++ {
		x := gen(i)
		b.Field(0).(*array.BooleanBuilder).Append(x.active)
		b.Field(1).(*array.Decimal128Builder).Append(decimal128.FromI64(x.amount))
		str(b.Field(2).(*array.StringBuilder), x.attrs)
		b.Field(3).(*array.TimestampBuilder).Append(arrow.Timestamp(x.closedAt))
		b.Field(4).(*array.StringBuilder).Append(x.code)
		b.Field(5).(*array.Date32Builder).Append(arrow.Date32(x.day))
		b.Field(6).(*array.FixedSizeBinaryBuilder).Append(x.entity[:])
		b.Field(7).(*array.FixedSizeBinaryBuilder).Append(x.id[:])
		str(b.Field(8).(*array.StringBuilder), x.name)
		b.Field(9).(*array.Int64Builder).Append(x.quantity)
		if (i+1)%65536 == 0 {
			flush()
		}
	}
	flush()
	must(w.Close())
}

func arrowRead(path string) uint64 {
	f, err := os.Open(path)
	must(err)
	defer f.Close()
	pf, err := afile.NewParquetReader(f)
	must(err)
	defer pf.Close()
	fr, err := pqarrow.NewFileReader(pf, pqarrow.ArrowReadProperties{BatchSize: 65536}, memory.DefaultAllocator)
	must(err)
	rr, err := fr.GetRecordReader(context.Background(), nil, nil)
	must(err)
	defer rr.Release()
	var c uint64
	for rr.Next() {
		rec := rr.RecordBatch()
		cols := rec.Columns()
		for i := 0; i < int(rec.NumRows()); i++ {
			for _, col := range cols {
				if e, ok := col.(array.ExtensionArray); ok { // a UUID column written by parquet-go
					col = e.Storage()
				}
				if col.IsNull(i) {
					c = fold(c, 0)
					continue
				}
				switch a := col.(type) {
				case *array.Boolean:
					if a.Value(i) {
						c = fold(c, 1)
					} else {
						c = fold(c, 2)
					}
				case *array.Decimal128:
					c = fold(c, a.Value(i).LowBits())
				case *array.Timestamp:
					c = fold(c, uint64(a.Value(i)))
				case *array.Date32:
					c = fold(c, uint64(a.Value(i)))
				case *array.Int64:
					c = fold(c, uint64(a.Value(i)))
				case *array.String:
					c = foldBytes(c, []byte(a.Value(i)))
				case *array.FixedSizeBinary:
					c = foldBytes(c, a.Value(i))
				case *array.Binary: // a JSON column written by parquet-go
					c = foldBytes(c, a.Value(i))
				default:
					must(fmt.Errorf("unexpected column type %T", col))
				}
			}
		}
	}
	must(rr.Err())
	return c
}
