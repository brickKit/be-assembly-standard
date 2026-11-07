"""T2b: which Parquet library be-sdk-python's cold tier (be-protocol chapter 15, route object-parquet, format parquet-1)
writes and reads with. The files must carry the schema be-sdk-go's tiering/parquet.go writes (every column optional,
in name order, zstd; text and numeric as strings, jsonb and text[] as JSON-annotated strings, int2/4/8, boolean, uuid
with the UUID logical type, timestamptz as UTC microseconds, date, bytea), and reading them back must give the values
the canonical rows are computed from.

Usage: python bench.py <candidate> <rows> <rounds> ; candidates: pyarrow, polars, duckdb. Prints one JSON line per
round: write and read wall and CPU seconds, the file's size, and the schema the file carries (the fit check). The
runner alternates the candidates round by round (run.sh)."""
from __future__ import annotations

import datetime as dt
import io
import json
import os
import random
import sys
import time
import uuid

COLUMNS = ["b_bool", "c_bytea", "d_date", "i2", "i4", "i8", "j_jsonb", "n_numeric", "t_text", "ta_text_array",
           "ts_timestamptz", "u_uuid"]


def rows(n: int, seed: int = 7) -> dict[str, list]:
    """n rows as column lists of Python values, a tenth of each column null (deterministic)."""
    r = random.Random(seed)
    base = dt.datetime(2026, 1, 1, tzinfo=dt.timezone.utc)

    def maybe(v):
        return None if r.random() < 0.1 else v

    out = {c: [] for c in COLUMNS}
    for i in range(n):
        out["b_bool"].append(maybe(r.random() < 0.5))
        out["c_bytea"].append(maybe(r.randbytes(24)))
        out["d_date"].append(maybe(dt.date(2026, 1, 1) + dt.timedelta(days=r.randrange(365))))
        out["i2"].append(maybe(r.randrange(-30000, 30000)))
        out["i4"].append(maybe(r.randrange(-2**31, 2**31)))
        out["i8"].append(maybe(r.randrange(-2**62, 2**62)))
        out["j_jsonb"].append(maybe(json.dumps({"k": i, "v": r.random().hex()})))
        out["n_numeric"].append(maybe(f"{r.randrange(10**9)}.{r.randrange(100):02d}"))
        out["t_text"].append(maybe(f"row {i} " + "x" * r.randrange(40)))
        out["ta_text_array"].append(maybe(json.dumps([f"a{r.randrange(9)}", f"b{r.randrange(9)}"])))
        out["ts_timestamptz"].append(maybe(base + dt.timedelta(microseconds=r.randrange(10**13))))
        out["u_uuid"].append(maybe(uuid.UUID(int=r.getrandbits(128))))
    return out


def pyarrow_io():
    import pyarrow as pa
    import pyarrow.parquet as pq

    def schema():
        return pa.schema([("b_bool", pa.bool_()), ("c_bytea", pa.binary()), ("d_date", pa.date32()),
                          ("i2", pa.int16()), ("i4", pa.int32()), ("i8", pa.int64()), ("j_jsonb", pa.json_()),
                          ("n_numeric", pa.string()), ("t_text", pa.string()), ("ta_text_array", pa.json_()),
                          ("ts_timestamptz", pa.timestamp("us", tz="UTC")), ("u_uuid", pa.uuid())])

    def write(cols) -> bytes:
        data = dict(cols)
        data["u_uuid"] = [None if u is None else u.bytes for u in data["u_uuid"]]
        t = pa.table(data, schema=schema())
        buf = io.BytesIO()
        pq.write_table(t, buf, compression="zstd")
        return buf.getvalue()

    def read(raw: bytes) -> dict[str, list]:
        t = pq.read_table(io.BytesIO(raw))
        return {c: t.column(c).to_pylist() for c in COLUMNS}

    def described(raw: bytes) -> str:
        return str(pq.ParquetFile(io.BytesIO(raw)).schema)

    return write, read, described


def polars_io():
    import polars as pl

    def write(cols) -> bytes:
        data = dict(cols)
        data["u_uuid"] = [None if u is None else u.bytes for u in data["u_uuid"]]
        df = pl.DataFrame(data, schema={"b_bool": pl.Boolean, "c_bytea": pl.Binary, "d_date": pl.Date, "i2": pl.Int16,
                                        "i4": pl.Int32, "i8": pl.Int64, "j_jsonb": pl.String, "n_numeric": pl.String,
                                        "t_text": pl.String, "ta_text_array": pl.String,
                                        "ts_timestamptz": pl.Datetime("us", "UTC"), "u_uuid": pl.Binary})
        buf = io.BytesIO()
        df.write_parquet(buf, compression="zstd")
        return buf.getvalue()

    def read(raw: bytes) -> dict[str, list]:
        df = pl.read_parquet(io.BytesIO(raw))
        return {c: df[c].to_list() for c in COLUMNS}

    def described(raw: bytes) -> str:
        import pyarrow.parquet as pq  # only to describe the file: the same view for every candidate
        return str(pq.ParquetFile(io.BytesIO(raw)).schema)

    return write, read, described


def duckdb_io():
    import duckdb
    import pyarrow as pa

    con = duckdb.connect()

    def write(cols) -> bytes:
        # DuckDB takes the column lists through Arrow (its fastest way in from Python), then writes its own Parquet
        data = dict(cols)
        data["u_uuid"] = [None if u is None else str(u) for u in data["u_uuid"]]
        t = pa.table(data)
        path = f"/dev/shm/bench-{os.getpid()}.parquet"
        con.execute(f"""COPY (SELECT b_bool, c_bytea, d_date, i2::SMALLINT AS i2, i4::INTEGER AS i4, i8, j_jsonb::JSON
            AS j_jsonb, n_numeric, t_text, ta_text_array::JSON AS ta_text_array, ts_timestamptz, u_uuid::UUID AS u_uuid
            FROM t) TO '{path}' (FORMAT parquet, COMPRESSION zstd)""")
        with open(path, "rb") as f:
            out = f.read()
        os.remove(path)
        return out

    def read(raw: bytes) -> dict[str, list]:
        path = f"/dev/shm/bench-{os.getpid()}-r.parquet"
        with open(path, "wb") as f:
            f.write(raw)
        rel = con.execute(f"SELECT {', '.join(COLUMNS)} FROM read_parquet('{path}')").fetchall()
        os.remove(path)
        return {c: [r[k] for r in rel] for k, c in enumerate(COLUMNS)}

    def described(raw: bytes) -> str:
        import pyarrow.parquet as pq
        return str(pq.ParquetFile(io.BytesIO(raw)).schema)

    return write, read, described


def main() -> None:
    cand, n, rounds = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    write, read, described = {"pyarrow": pyarrow_io, "polars": polars_io, "duckdb": duckdb_io}[cand]()
    cols = rows(n)
    raw = write(cols)  # warm-up, and the fit check below
    back = read(raw)
    same = all(len(back[c]) == n for c in COLUMNS)
    print(json.dumps({"candidate": cand, "fit": {"rows_back": same, "schema": described(raw)}}), flush=True)
    for k in range(rounds):
        w0, c0 = time.perf_counter(), time.process_time()
        raw = write(cols)
        w1, c1 = time.perf_counter(), time.process_time()
        read(raw)
        w2, c2 = time.perf_counter(), time.process_time()
        print(json.dumps({"candidate": cand, "round": k, "rows": n, "write_s": w1 - w0, "write_cpu_s": c1 - c0,
                          "read_s": w2 - w1, "read_cpu_s": c2 - c1, "bytes": len(raw)}), flush=True)
    import resource
    print(json.dumps({"candidate": cand, "max_rss_kib": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}), flush=True)


if __name__ == "__main__":
    main()
