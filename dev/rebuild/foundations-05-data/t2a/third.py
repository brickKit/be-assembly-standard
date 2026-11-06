import sys, pyarrow.parquet as pq, duckdb
for f in sys.argv[1:]:
    t = pq.read_table(f)
    print(f, "pyarrow rows", t.num_rows, [str(x.type) for x in t.schema])
    print("  first", {k: t.column(k)[0].as_py() for k in ("amount", "closed_at", "day", "id", "attrs")})
    con = duckdb.connect()
    print("  duckdb", con.execute(f"select count(*), sum(amount), min(closed_at), count(attrs), count(name) from read_parquet('{f}')").fetchone())
