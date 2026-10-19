// Per-transaction overhead with pgx: a short write transaction (BEGIN, six set_config settings, one INSERT, COMMIT)
// two ways: A as the SDK does it (BeginTx, then set_config with parameters), C with BEGIN and set_config in one
// round trip (simple protocol, literal values). Client CPU and the PostgreSQL container's CPU per transaction, 8 at
// once. Usage: go run . <admin dsn> <postgres cgroup cpu.stat path> [n]
package main

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const settings = `SELECT set_config('search_path', $1, true), set_config('statement_timeout', $2, true),
	set_config('lock_timeout', $3, true), set_config('idle_in_transaction_session_timeout', $4, true),
	set_config('application_name', $5, true), set_config('timezone', $6, true)`

const merged = `BEGIN ISOLATION LEVEL READ COMMITTED; SELECT set_config('search_path', 'txbench', true),
	set_config('statement_timeout', '5000', true), set_config('lock_timeout', '2000', true),
	set_config('idle_in_transaction_session_timeout', '10000', true), set_config('application_name', 'txbench', true),
	set_config('timezone', 'UTC', true)`

func serverCPU(path string) float64 {
	f, _ := os.Open(path)
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if strings.HasPrefix(sc.Text(), "usage_usec") {
			v, _ := strconv.ParseFloat(strings.Fields(sc.Text())[1], 64)
			return v / 1e6
		}
	}
	return 0
}

func clientCPU() float64 {
	var r syscall.Rusage
	_ = syscall.Getrusage(syscall.RUSAGE_SELF, &r)
	return float64(r.Utime.Nano()+r.Stime.Nano()) / 1e9
}

func one(ctx context.Context, p *pgxpool.Pool, mode string) error {
	if mode == "A" {
		tx, err := p.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.ReadCommitted})
		if err != nil {
			return err
		}
		defer tx.Rollback(ctx)
		if _, err := tx.Exec(ctx, settings, "txbench", "5000", "2000", "10000", "txbench", "UTC"); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, "INSERT INTO txbench.t (id, v) VALUES ($1, $2)", uuid.New(), strings.Repeat("x", 100)); err != nil {
			return err
		}
		return tx.Commit(ctx)
	}
	c, err := p.Acquire(ctx)
	if err != nil {
		return err
	}
	defer c.Release()
	if _, err := c.Exec(ctx, merged, pgx.QueryExecModeSimpleProtocol); err != nil {
		return err
	}
	if _, err := c.Exec(ctx, "INSERT INTO txbench.t (id, v) VALUES ($1, $2)", uuid.New(), strings.Repeat("x", 100)); err != nil {
		return err
	}
	_, err = c.Exec(ctx, "COMMIT")
	return err
}

func run(ctx context.Context, p *pgxpool.Pool, mode, cpustat string, n int) {
	for range 200 {
		if err := one(ctx, p, mode); err != nil {
			panic(err)
		}
	}
	work := make(chan struct{}, n)
	for range n {
		work <- struct{}{}
	}
	close(work)
	c0, s0, t0 := clientCPU(), serverCPU(cpustat), time.Now()
	var wg sync.WaitGroup
	for range 8 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for range work {
				if err := one(ctx, p, mode); err != nil {
					panic(err)
				}
			}
		}()
	}
	wg.Wait()
	c1, s1 := clientCPU(), serverCPU(cpustat)
	fmt.Printf("%s: client %.3f ms/tx, server %.3f ms/tx, wall %.3f ms/tx (8 at once)\n", mode,
		(c1-c0)/float64(n)*1e3, (s1-s0)/float64(n)*1e3, time.Since(t0).Seconds()/float64(n)*1e3)
}

func main() {
	ctx := context.Background()
	n := 4000
	if len(os.Args) > 3 {
		n, _ = strconv.Atoi(os.Args[3])
	}
	cfg, err := pgxpool.ParseConfig(os.Args[1])
	if err != nil {
		panic(err)
	}
	cfg.MaxConns, cfg.MinConns = 8, 8
	p, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		panic(err)
	}
	defer p.Close()
	if _, err := p.Exec(ctx, "CREATE SCHEMA IF NOT EXISTS txbench; CREATE TABLE IF NOT EXISTS txbench.t (id uuid PRIMARY KEY, v text)"); err != nil {
		panic(err)
	}
	for r := range 3 {
		for _, m := range []string{"A", "C"} {
			fmt.Printf("round %d ", r)
			run(ctx, p, m, os.Args[2], n)
		}
	}
	_, _ = p.Exec(ctx, "DROP SCHEMA txbench CASCADE")
}
