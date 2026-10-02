// r1-04b (pgx v5): statement / description cache x SET LOCAL ROLE / search_path on one pooled connection.
//
// Same layout as r1-04 (../../r1-04/setup.sql): members a (role ra) and b (role rb), same-named tables
// of different shape, one NOINHERIT shell login role. A pool with exactly one physical connection;
// every "member transaction" is BEGIN; SET LOCAL ROLE; SET LOCAL search_path; <same SQL text>; COMMIT,
// alternating a, b, a, b. Usage: go run . <exec-mode> [prefix]
//   exec-mode: cache_statement (pgx default) | cache_describe | describe_exec | exec | simple_protocol
//   prefix:    every member's SQL text starts with /* be:<schema> */ (cache key differs per member)
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

var members = map[string][2]string{"a": {"ra", "a"}, "b": {"rb", "b"}}
var modes = map[string]pgx.QueryExecMode{
	"cache_statement": pgx.QueryExecModeCacheStatement,
	"cache_describe":  pgx.QueryExecModeCacheDescribe,
	"describe_exec":   pgx.QueryExecModeDescribeExec,
	"exec":            pgx.QueryExecModeExec,
	"simple_protocol": pgx.QueryExecModeSimpleProtocol,
}
var prefix bool

// q is what an SDK Tx would do with prefix on: make the cache key (= SQL text) differ per member.
func q(m, sql string) string {
	if prefix {
		return "/* be:" + members[m][1] + " */ " + sql
	}
	return sql
}

func memberTx(ctx context.Context, p *pgxpool.Pool, m string, fn func(pgx.Tx) (any, error)) (any, error) {
	tx, err := p.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx) //nolint:errcheck
	if _, err := tx.Exec(ctx, fmt.Sprintf(`SET LOCAL ROLE %q`, members[m][0])); err != nil {
		return nil, err
	}
	if _, err := tx.Exec(ctx, fmt.Sprintf(`SET LOCAL search_path TO %q`, members[m][1])); err != nil {
		return nil, err
	}
	r, err := fn(tx)
	if err != nil {
		return nil, err
	}
	return r, tx.Commit(ctx)
}

// row returns the values pgx decoded (so a silently mis-decoded value would be visible).
func row(sql string, args ...any) func(string) func(pgx.Tx) (any, error) {
	return func(m string) func(pgx.Tx) (any, error) {
		return func(tx pgx.Tx) (any, error) {
			rows, err := tx.Query(context.Background(), q(m, sql), args...)
			if err != nil {
				return nil, err
			}
			defer rows.Close()
			var out [][]any
			for rows.Next() {
				v, err := rows.Values()
				if err != nil {
					return nil, err
				}
				out = append(out, v)
			}
			return fmt.Sprintf("%#v", out), rows.Err()
		}
	}
}

func errStr(err error) string {
	var pe *pgconn.PgError
	if errors.As(err, &pe) {
		return fmt.Sprintf("%s (sqlstate=%s)", pe.Message, pe.Code)
	}
	return err.Error()
}

func runCase(ctx context.Context, p *pgxpool.Pool, name string, f func(string) func(pgx.Tx) (any, error)) {
	fmt.Println("---", name)
	for _, m := range []string{"a", "b", "a", "b"} {
		r, err := memberTx(ctx, p, m, f(m))
		if err != nil {
			fmt.Printf("  [%s] ERR  %s\n", m, errStr(err))
		} else {
			fmt.Printf("  [%s] OK   %v\n", m, r)
		}
	}
}

func outside(ctx context.Context, p *pgxpool.Pool) string {
	var pid int
	var usr, sp string
	err := p.QueryRow(ctx, "SELECT pg_backend_pid(), current_user::text, current_setting('search_path')").Scan(&pid, &usr, &sp)
	if err != nil {
		return "ERR " + errStr(err)
	}
	return fmt.Sprintf("pid=%d usr=%s sp=%s", pid, usr, sp)
}

func main() {
	ctx := context.Background()
	mode := os.Args[1]
	prefix = len(os.Args) > 2 && os.Args[2] == "prefix"
	cfg, err := pgxpool.ParseConfig(os.Getenv("PG_DSN"))
	if err != nil {
		panic(err)
	}
	cfg.MinConns, cfg.MaxConns = 1, 1
	cfg.ConnConfig.DefaultQueryExecMode = modes[mode]
	p, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		panic(err)
	}
	defer p.Close()
	fmt.Printf("===== pgx v5.10.0, mode=%s, per-member SQL prefix=%v\n", mode, prefix)
	fmt.Println("before:", outside(ctx, p))

	runCase(ctx, p, "S1 same shape SELECT id, v FROM widget WHERE id=$1", row("SELECT id, v, current_schema()::text AS s FROM widget WHERE id = $1", 1))
	runCase(ctx, p, "S1 same shape UPDATE ... RETURNING", row("UPDATE widget SET v = v || '+' WHERE id = $1 RETURNING v", 1))
	runCase(ctx, p, "S2 different result type: SELECT id, payload FROM besdk_thing", row("SELECT id, payload FROM besdk_thing WHERE id = $1", 1))
	runCase(ctx, p, "S2 different result type: SELECT * FROM besdk_thing", row("SELECT * FROM besdk_thing WHERE id = $1", 1))
	runCase(ctx, p, "S3 same listed types, b has extra col: SELECT id, payload FROM besdk_same", row("SELECT id, payload FROM besdk_same WHERE id = $1", 1))
	runCase(ctx, p, "S3 SELECT * FROM besdk_same (column count differs)", row("SELECT * FROM besdk_same WHERE id = $1", 1))
	n := 100
	runCase(ctx, p, "S4 INSERT INTO besdk_thing (id, payload) VALUES ($1,$2) (param text vs jsonb)", func(m string) func(pgx.Tx) (any, error) {
		n++
		return row("INSERT INTO besdk_thing (id, payload) VALUES ($1, $2) RETURNING payload::text", n, `{"k":1}`)(m)
	})

	fmt.Println("--- S7 leak check after commit:  ", outside(ctx, p))
	_, err = memberTx(ctx, p, "a", row("SELECT 1/$1::int", 0)("a"))
	fmt.Println("  (forced error:", errStr(err)+")")
	fmt.Println("--- S7 leak check after rollback:", outside(ctx, p))

	const N = 2000
	t0 := time.Now()
	for i := 0; i < N; i++ {
		m := "ab"[i%2 : i%2+1]
		if _, err := memberTx(ctx, p, m, row("SELECT id, v FROM widget WHERE id = $1", 1)(m)); err != nil {
			fmt.Println("  bench ERR", errStr(err))
			break
		}
	}
	dt := time.Since(t0)
	fmt.Printf("--- bench: %d alternating member tx in %.2fs = %.3f ms/tx\n", N, dt.Seconds(), dt.Seconds()/N*1e3)
}
