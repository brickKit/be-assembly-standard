"""r1-03 addendum (grpcio / grpc.aio): is the retryThrottling budget per channel or per target in-process?
Raw bytes handlers, no codegen. Same service config shape as ../repro.ts."""
import asyncio
import json
from importlib.metadata import version

import grpc

SC = {"methodConfig": [{"name": [{"service": "r1.echo.v1.Echo", "method": "Get"}],
                        "retryPolicy": {"maxAttempts": 4, "initialBackoff": "0.05s", "maxBackoff": "0.5s",
                                        "backoffMultiplier": 2, "retryableStatusCodes": ["UNAVAILABLE"]}}],
      "retryThrottling": {"maxTokens": 10, "tokenRatio": 0.1}}
attempts: dict[bytes, int] = {}


async def get(request: bytes, ctx: grpc.aio.ServicerContext) -> bytes:
    attempts[request] = attempts.get(request, 0) + 1
    await ctx.abort(grpc.StatusCode.UNAVAILABLE, "injected")


async def main():
    server = grpc.aio.server()
    server.add_generic_rpc_handlers((grpc.method_handlers_generic_handler(
        "r1.echo.v1.Echo", {"Get": grpc.unary_unary_rpc_method_handler(get)}),))
    port = server.add_insecure_port("127.0.0.1:0")
    await server.start()
    opts = [("grpc.service_config", json.dumps(SC)), ("grpc.enable_retries", 1)]

    async def call(ch, key: bytes):
        try:
            await ch.unary_unary("/r1.echo.v1.Echo/Get")(key, timeout=5)
        except grpc.aio.AioRpcError:
            pass
        return attempts[key]

    print(f"===== grpcio {version('grpcio')}")
    a = grpc.aio.insecure_channel(f"127.0.0.1:{port}", options=opts)
    print("channel A, 6 failing Get calls, attempts per call:", [await call(a, f"t{i}".encode()) for i in range(6)])
    b = grpc.aio.insecure_channel(f"127.0.0.1:{port}", options=opts + [("grpc.use_local_subchannel_pool", 1)])
    print("channel B (new channel, same target, local subchannel pool), attempts:", await call(b, b"b"))
    d = grpc.aio.insecure_channel(f"localhost:{port}", options=opts)
    print(f"channel D (target spelled localhost:{port}), attempts:", await call(d, b"d"))
    await server.stop(None)


asyncio.run(main())
