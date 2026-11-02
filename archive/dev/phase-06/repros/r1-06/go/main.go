// R1 #6（Go 部分）：golang-migrate + iofs + pgx5 驱动，写法照 be-sdk-go/migrate：
// URL 里带 search_path=<PG_SCHEMA> 和 x-migrations-table=<表名>。
// 验证：1) iofs 忽略 migrations/lifecycle.yaml；2) 状态表落在组件 schema；
// 3) 同一个 schema 里两套状态表（组件 + SDK 平台）互不干扰。
package main

import (
	"context"
	"embed"
	"errors"
	"fmt"
	"io/fs"
	"net/url"
	"os"

	gomigrate "github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/pgx/v5"
	"github.com/golang-migrate/migrate/v4/source"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"github.com/jackc/pgx/v5"
)

//go:embed migrations/*
var componentFS embed.FS

//go:embed platform/*
var platformFS embed.FS

func must(err error, what string) {
	if err != nil {
		fmt.Printf("FAIL %s: %v\n", what, err)
		os.Exit(1)
	}
}

func newMigrate(fsys fs.FS, dir, dsn, schema, table string) (*gomigrate.Migrate, source.Driver) {
	src, err := iofs.New(fsys, dir)
	must(err, "iofs.New "+dir)
	u, err := url.Parse(dsn)
	must(err, "parse dsn")
	u.Scheme = "pgx5"
	q := u.Query()
	q.Set("search_path", schema)
	q.Set("x-migrations-table", table)
	u.RawQuery = q.Encode()
	m, err := gomigrate.NewWithSourceInstance("iofs", src, u.String())
	must(err, "migrate.New "+dir)
	return m, src
}

func listVersions(src source.Driver) []uint {
	var out []uint
	v, err := src.First()
	for err == nil {
		out = append(out, v)
		v, err = src.Next(v)
	}
	return out
}

func version(m *gomigrate.Migrate) string {
	v, dirty, err := m.Version()
	if errors.Is(err, gomigrate.ErrNilVersion) {
		return "nil"
	}
	must(err, "version")
	return fmt.Sprintf("%d(dirty=%v)", v, dirty)
}

func main() {
	dsn, schema := os.Getenv("DSN"), os.Getenv("PG_SCHEMA")
	if dsn == "" || schema == "" {
		fmt.Println("need DSN and PG_SCHEMA")
		os.Exit(2)
	}
	compTable := "schema_migrations_" + schema
	platTable := "besdk_migrations_" + schema

	// 0) iofs 能看见哪些版本；lifecycle.yaml 解析会失败，应被跳过
	_, perr := source.DefaultParse("lifecycle.yaml")
	fmt.Printf("INFO source.DefaultParse(lifecycle.yaml) err=%v\n", perr)

	comp, compSrc := newMigrate(componentFS, "migrations", dsn, schema, compTable)
	fmt.Printf("INFO iofs component versions=%v\n", listVersions(compSrc))
	plat, platSrc := newMigrate(platformFS, "platform", dsn, schema, platTable)
	fmt.Printf("INFO iofs platform versions=%v\n", listVersions(platSrc))

	must(comp.Up(), "component up")
	fmt.Printf("PASS component up, version=%s\n", version(comp))
	must(plat.Up(), "platform up")
	fmt.Printf("PASS platform up, version=%s\n", version(plat))

	if err := comp.Up(); errors.Is(err, gomigrate.ErrNoChange) {
		fmt.Println("PASS component up again: no change")
	} else {
		must(fmt.Errorf("expected ErrNoChange, got %v", err), "component up again")
	}
	must(comp.Steps(-1), "component down 1")
	fmt.Printf("PASS component down 1: component=%s platform=%s\n", version(comp), version(plat))
	must(comp.Up(), "component up after down")
	fmt.Printf("PASS component re-up: component=%s platform=%s\n", version(comp), version(plat))

	// 状态表和业务表都在哪个 schema
	ctx := context.Background()
	conn, err := pgx.Connect(ctx, dsn)
	must(err, "connect")
	defer conn.Close(ctx)
	rows, err := conn.Query(ctx, `SELECT table_schema||'.'||table_name FROM information_schema.tables
	  WHERE table_schema NOT IN ('pg_catalog','information_schema') ORDER BY 1`)
	must(err, "list tables")
	for rows.Next() {
		var t string
		must(rows.Scan(&t), "scan")
		fmt.Printf("TABLE %s\n", t)
	}
	must(rows.Err(), "rows")
}
