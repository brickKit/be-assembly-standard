#!/usr/bin/env python3
"""把 spa.html 挂在 http://localhost:38001 的任何路径上（/ 和 /callback 都是它）。"""
import http.server, pathlib
PAGE = (pathlib.Path(__file__).parent / "spa.html").read_bytes()
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("content-type", "text/html; charset=utf-8")
        self.end_headers()
        self.wfile.write(PAGE)
http.server.ThreadingHTTPServer(("127.0.0.1", 38001), H).serve_forever()
