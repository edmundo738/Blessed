#!/usr/bin/env python3
"""Serve o build Web de BLESSED com os headers que o Godot 4 precisa.
Uso (na pasta do projeto, DEPOIS de exportar):
    python tools/serve_web.py export/web2 8060
Depois, no telemovel (mesmo Wi-Fi): http://IP_DO_PC:8060
"""
import http.server, socketserver, os, sys

DIR = sys.argv[1] if len(sys.argv) > 1 else "export/web2"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8060

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
        ".json": "application/json",
    }
    def end_headers(self):
        # cross-origin isolation (necessario se o build usar threads/SharedArrayBuffer)
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

if not os.path.isdir(DIR):
    print(f"ERRO: pasta '{DIR}' nao existe. Exporta primeiro (ver README_WEB.md).")
    sys.exit(1)
os.chdir(DIR)
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print(f"BLESSED Web em  http://0.0.0.0:{PORT}  (no telemovel: http://IP_DO_PC:{PORT})")
    httpd.serve_forever()
