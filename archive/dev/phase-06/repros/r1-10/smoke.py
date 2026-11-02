"""r1-10 smoke test: exercise the compiled parts, not just import them. Needs PG_DSN (throwaway PG16)."""
import asyncio
import io
import os
from importlib.metadata import version


async def main():
    out = []
    import asyncpg
    c = await asyncpg.connect(os.environ["PG_DSN"])
    out.append(f"asyncpg {version('asyncpg')}: {await c.fetchval('SELECT $1::numeric(19,4) + 1', __import__('decimal').Decimal('1.2345'))}")
    await c.close()

    import grpc
    srv = grpc.aio.server()
    srv.add_generic_rpc_handlers((grpc.method_handlers_generic_handler(
        "t.T", {"Echo": grpc.unary_unary_rpc_method_handler(_echo)}),))
    port = srv.add_insecure_port("127.0.0.1:0")
    await srv.start()
    async with grpc.aio.insecure_channel(f"127.0.0.1:{port}") as ch:
        r = await ch.unary_unary("/t.T/Echo")(b"ping", timeout=3)
    await srv.stop(None)
    out.append(f"grpcio {version('grpcio')}: aio round trip {r!r}")

    import pyarrow as pa
    import pyarrow.parquet as pq
    buf = io.BytesIO()
    pq.write_table(pa.table({"id": ["a", "b"], "amount": pa.array([1, 2], pa.decimal128(19, 4))}), buf)
    out.append(f"pyarrow {pa.__version__}: parquet {len(buf.getvalue())} bytes, rows={pq.read_table(io.BytesIO(buf.getvalue())).num_rows}")

    import nats  # noqa: F401
    import uvloop
    import pydantic_core
    import cryptography.hazmat.primitives.asymmetric.rsa as rsa
    import jwt
    k = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    tok = jwt.encode({"sub": "u", "aud": "t"}, k, algorithm="RS256")
    out.append(f"PyJWT+cryptography: RS256 ok={jwt.decode(tok, k.public_key(), algorithms=['RS256'], audience='t')['sub'] == 'u'}; "
               f"uvloop {uvloop.__version__}; pydantic-core {pydantic_core.__version__}")
    for mod in ("psycopg2", "psycopg", "yoyo", "aioboto3", "pypinyin", "weasyprint", "uuid6", "fastapi", "httptools", "watchfiles"):
        try:
            __import__(mod)
            out.append(f"import {mod}: ok")
        except Exception as e:  # noqa: BLE001
            out.append(f"import {mod}: {type(e).__name__}: {str(e)[:120]}")
    import uuid
    out.append(f"stdlib uuid.uuid7: {hasattr(uuid, 'uuid7')}")
    print("\n".join(out))


async def _echo(req, ctx):
    return req


asyncio.run(main())
