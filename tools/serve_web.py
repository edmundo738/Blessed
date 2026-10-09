#!/usr/bin/env python3
"""serve_web.py — serve a build web em 0.0.0.0. Uso: python3 tools/serve_web.py [pasta] [porta]"""
import http.server
import os
import socketserver
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
folder = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, "export", "web")
port = int(sys.argv[2]) if len(sys.argv) > 2 else int(os.environ.get("PORT", "8080"))

http.server.SimpleHTTPRequestHandler.extensions_map.update({
	".wasm": "application/wasm", ".pck": "application/octet-stream",
	".js": "text/javascript", ".json": "application/json", ".html": "text/html",
})


class Handler(http.server.SimpleHTTPRequestHandler):
	def __init__(self, *a, **kw):
		super().__init__(*a, directory=folder, **kw)

	def end_headers(self):
		self.send_header("Cache-Control", "no-store")
		super().end_headers()

	def log_message(self, fmt, *args):
		sys.stdout.write("%s - %s\n" % (self.address_string(), fmt % args))


socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", port), Handler) as httpd:
	print("BLESSED a servir %s em http://0.0.0.0:%d" % (folder, port))
	httpd.serve_forever()
