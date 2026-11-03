// Command idle measures what an idle member's background work costs the database: one member with a queue job, a
// cron job (every 5 minutes) and a singleton (hourly), nothing due, for -seconds. It provisions its own database
// (be_idle_bench) and schema the way the assembly does, runs the SDK's work runner (and, with -statistics, the
// statistics upkeep of P5.33), and reports from pg_stat_statements and pg_stat_database what reached the server,
// plus the CPU of this process and of the member's backends (read from /proc inside the be-postgres container).
//
// BE_SDK_TEST_PG_ADMIN is a superuser DSN; the server needs pg_stat_statements preloaded.
package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"testing/fstest"
	"time"

	"github.com/brickKit/be-sdk-go/v3/config"
	"github.com/brickKit/be-sdk-go/v3/db"
	"github.com/brickKit/be-sdk-go/v3/work"
	"github.com/jackc/pgx/v5"
)

const database, schema = "be_idle_bench", "idle"

func main() {
	seconds := flag.Int("seconds", 60, "how long to measure, after a 5 s warm-up")
	statistics := flag.Bool("statistics", false, "also run the statistics upkeep (P5.33)")
	label := flag.String("label", "", "a label for the report")
	flag.Parse()
	ctx := context.Background()
	dsn := os.Getenv("BE_SDK_TEST_PG_ADMIN")
	admin := connect(ctx, dsn, "postgres")
	var exists bool
	must(admin.QueryRow(ctx, "SELECT EXISTS (SELECT 1 FROM pg_database WHERE datname = $1)", database).Scan(&exists))
	if !exists {
		exec1(ctx, admin, "CREATE DATABASE "+database)
	}
	a := connect(ctx, dsn, database)
	owner, rw := "idle_owner", "idle_rw"
	for _, r := range []string{owner, rw} {
		exec1(ctx, a, fmt.Sprintf(`DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '%s') THEN
			CREATE ROLE %s LOGIN PASSWORD '%s-pw'; END IF; END $$`, r, r, r))
	}
	exec1(ctx, a, "CREATE EXTENSION IF NOT EXISTS pg_stat_statements",
		"DROP SCHEMA IF EXISTS "+schema+" CASCADE",
		"GRANT CONNECT ON DATABASE "+database+" TO "+owner+", "+rw,
		"CREATE SCHEMA "+schema+" AUTHORIZATION "+owner,
		"GRANT USAGE ON SCHEMA "+schema+" TO "+rw,
		"ALTER DEFAULT PRIVILEGES FOR ROLE "+owner+" IN SCHEMA "+schema+" GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "+rw,
		"ALTER DEFAULT PRIVILEGES FOR ROLE "+owner+" REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC",
		"ALTER DEFAULT PRIVILEGES FOR ROLE "+owner+" IN SCHEMA "+schema+" GRANT EXECUTE ON FUNCTIONS TO "+rw)
	cfg := a.Config()
	env := map[string]string{"PG_HOST": cfg.Host, "PG_PORT": strconv.Itoa(int(cfg.Port)), "PG_DATABASE": database,
		"PG_USER": rw, "PG_PASSWORD": rw + "-pw", "PG_SCHEMA": schema, "PG_OWNER_USER": owner, "PG_OWNER_PASSWORD": owner + "-pw"}
	values, problems := config.Parse(db.MigrateKeys(), config.Map(env))
	if len(problems) > 0 {
		panic(fmt.Sprint(problems))
	}
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	mc, problems := db.MigrateConfigFrom("demo/idle", values, quiet)
	if len(problems) > 0 {
		panic(fmt.Sprint(problems))
	}
	must(db.Migrate(ctx, mc, db.SDKMigrations(), db.MigrationSet{Name: "demo/idle", Table: "schema_migrations",
		Files: fstest.MapFS{"0001_items.up.sql": {Data: []byte("CREATE TABLE items (id uuid PRIMARY KEY);")}}}))
	s := db.SettingsFrom(values)
	pool, err := db.Open(ctx, db.PoolConfig{Target: s.Target, User: s.User, Password: s.Password, AppName: "demo/idle",
		MaxConns: 8, Prepared: true})
	must(err)
	d := db.NewDB("demo/idle", pool, s)

	noop := func(context.Context, *work.Run) error { return nil }
	r := work.NewRunner(d, "demo/idle", quiet)
	must(r.Add(work.Job{Name: "q", Kind: work.Queue, Effect: work.Local, Handle: noop},
		work.Job{Name: "c", Kind: work.Cron, Effect: work.Local, Cron: "*/5 * * * *", TimeZone: "UTC", Handle: noop},
		work.Job{Name: "s", Kind: work.Singleton, Effect: work.Local, Interval: time.Hour, Handle: noop}))
	run, stop := context.WithCancel(ctx)
	must(r.Start(run))
	if *statistics {
		go db.KeepStatistics(run, d, quiet)
	}
	time.Sleep(5 * time.Second) // the singleton's first run, the cron watermark, the pool's connections

	var dbid uint32
	must(a.QueryRow(ctx, "SELECT oid FROM pg_database WHERE datname = $1", database).Scan(&dbid))
	exec1(ctx, a, fmt.Sprintf("SELECT pg_stat_statements_reset(0, %d, 0)", dbid))
	exec1(ctx, a, "SELECT pg_stat_reset()")
	time.Sleep(time.Second) // pg_stat_database is flushed at most once a second
	x0 := xacts(ctx, a)
	pids := backends(ctx, a, rw)
	b0 := backendTicks(pids)
	c0 := selfCPU()
	started := time.Now()
	time.Sleep(time.Duration(*seconds) * time.Second)
	took := time.Since(started).Seconds()
	c1 := selfCPU()
	b1 := backendTicks(pids)
	exec1(ctx, a, "SELECT pg_stat_force_next_flush()")
	time.Sleep(1500 * time.Millisecond)
	x1 := xacts(ctx, a)
	stop()
	r.Stop()

	fmt.Printf("label=%s seconds=%.1f statistics=%v backends=%d\n", *label, took, *statistics, len(pids))
	fmt.Printf("transactions/s=%.2f client_cpu_ms/s=%.3f backend_cpu_ms/s=%.3f\n", float64(x1-x0)/took,
		float64(c1-c0)/1e6/took, float64(b1-b0)*10/took)
	rows, err := a.Query(ctx, `SELECT calls, total_exec_time, query FROM pg_stat_statements WHERE dbid = $1
		ORDER BY calls DESC`, dbid)
	must(err)
	type st struct {
		calls int64
		ms    float64
		query string
	}
	var all []st
	var calls int64
	var ms float64
	for rows.Next() {
		var x st
		must(rows.Scan(&x.calls, &x.ms, &x.query))
		if strings.Contains(x.query, "pg_stat_statements") || strings.Contains(x.query, "pg_stat_") {
			continue // this program's own reads
		}
		all = append(all, x)
		calls += x.calls
		ms += x.ms
	}
	must(rows.Err())
	fmt.Printf("statements/s=%.2f exec_ms/s=%.3f\n", float64(calls)/took, ms/took)
	sort.Slice(all, func(i, j int) bool { return all[i].calls > all[j].calls })
	for _, x := range all {
		q := strings.Join(strings.Fields(x.query), " ")
		if len(q) > 110 {
			q = q[:110]
		}
		fmt.Printf("  %7.2f/s %8.4f ms/call  %s\n", float64(x.calls)/took, x.ms/float64(x.calls), q)
	}
}

func connect(ctx context.Context, dsn, database string) *pgx.Conn {
	cfg, err := pgx.ParseConfig(dsn)
	must(err)
	cfg.Database = database
	c, err := pgx.ConnectConfig(ctx, cfg)
	must(err)
	return c
}

func exec1(ctx context.Context, c *pgx.Conn, sqls ...string) {
	for _, q := range sqls {
		_, err := c.Exec(ctx, q)
		must(err)
	}
}

func xacts(ctx context.Context, a *pgx.Conn) int64 {
	var n int64
	must(a.QueryRow(ctx, "SELECT xact_commit + xact_rollback FROM pg_stat_database WHERE datname = $1", database).Scan(&n))
	return n
}

func backends(ctx context.Context, a *pgx.Conn, user string) []int {
	rows, err := a.Query(ctx, "SELECT pid FROM pg_stat_activity WHERE datname = $1 AND usename = $2", database, user)
	must(err)
	var pids []int
	for rows.Next() {
		var p int
		must(rows.Scan(&p))
		pids = append(pids, p)
	}
	return pids
}

// backendTicks sums utime and stime (clock ticks, 100 a second) of the backends; one that is gone counts zero.
func backendTicks(pids []int) int64 {
	var args []string
	for _, p := range pids {
		args = append(args, fmt.Sprintf("/proc/%d/stat", p))
	}
	out, _ := exec.Command("docker", append([]string{"exec", "be-postgres", "cat"}, args...)...).Output()
	var n int64
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		f := strings.Fields(line[strings.LastIndex(line, ")")+1:])
		if len(f) > 13 {
			u, _ := strconv.ParseInt(f[11], 10, 64)
			s, _ := strconv.ParseInt(f[12], 10, 64)
			n += u + s
		}
	}
	return n
}

func selfCPU() int64 {
	var u syscall.Rusage
	must(syscall.Getrusage(syscall.RUSAGE_SELF, &u))
	return u.Utime.Nano() + u.Stime.Nano()
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
