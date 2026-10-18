"""One FastAPI app with one route (POST /api/probe/echo, the load driver's echo: returns the 1 KiB payload), served in
this process by uvicorn (httptools) or by granian's embedded server, on one asyncio loop.
Usage: python serve.py <uvicorn|granian> <port>"""
import asyncio, os, sys

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

app = FastAPI()


@app.post("/api/probe/echo")
async def echo(req: Request):
    body = await req.json()
    return JSONResponse({"payload": body["payload"]})


async def main(kind: str, port: int) -> None:
    if kind == "uvicorn":
        import uvicorn
        server = uvicorn.Server(uvicorn.Config(app, host="127.0.0.1", port=port, http="httptools", loop="asyncio",
                                               log_level="warning", access_log=False, lifespan="off"))
        await server.serve()
    else:
        from granian.constants import Interfaces
        from granian.server.embed import Server
        server = Server(app, address="127.0.0.1", port=port, interface=Interfaces.ASGI, log_enabled=False)
        await server.serve()

print(os.getpid(), flush=True)
asyncio.run(main(sys.argv[1], int(sys.argv[2])))
