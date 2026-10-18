#!/usr/bin/env python3
"""Serve o build Web de BLESSED com os headers que o Godot 4 precisa.
Uso (na pasta do projeto, DEPOIS de exportar):
    python tools/serve_web.py export/web2 8060
Depois, no telemovel (mesmo Wi-Fi): http://IP_DO_PC:8060
"""
import http.server, socketserver, os, sys

DIR = sys.argv[1] if len(sys.argv) > 1 else "export/web2"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 8060
# Os cabecalhos de isolamento (COOP/COEP) so sao precisos quando o build usa
# THREADS (SharedArrayBuffer). O build do BLESSED e single-thread
# (`thread_support=false` em export_presets.cfg), e envia-los sem necessidade
# tem um custo real: `Cross-Origin-Resource-Policy: same-origin` impede a pagina
# de ser embutida noutro site (por exemplo numa pre-visualizacao em iframe) e o
# COEP obriga TODOS os recursos a trazerem CORP. Por omissao, nada disso.
ISOLATE = "--isolate" in sys.argv or os.environ.get("BLESSED_ISOLATE") == "1"

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".pck": "application/octet-stream",
        ".js": "text/javascript",
        ".json": "application/json",
    }
    def end_headers(self):
        if ISOLATE:
            # cross-origin isolation (so com build de threads/SharedArrayBuffer)
            self.send_header("Cross-Origin-Opener-Policy", "same-origin")
            self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        # Cache curta: o .pck tem decenas de MB e um "no-store" obrigava a
        # descarregá-lo de novo em cada recarga da página. Curta, para uma
        # exportação nova não ficar presa em cache.
        ext = os.path.splitext(self.path.split("?")[0])[1].lower()
        if ext in (".html", ""):
            self.send_header("Cache-Control", "no-store")
        else:
            self.send_header("Cache-Control", "public, max-age=300")
        super().end_headers()

if not os.path.isdir(DIR):
    print(f"ERRO: pasta '{DIR}' nao existe. Exporta primeiro (ver README_WEB.md).")
    sys.exit(1)
os.chdir(DIR)
socketserver.TCPServer.allow_reuse_address = True
# ThreadingHTTPServer: um download de 50 MB do .pck não pode bloquear o pedido
# do .wasm que o browser faz em paralelo — com o servidor de uma linha só, o
# arranque parecia pendurado.
class Server(socketserver.ThreadingTCPServer):
	allow_reuse_address = True
	daemon_threads = True

with Server(("0.0.0.0", PORT), Handler) as httpd:
    print(f"BLESSED Web em  http://0.0.0.0:{PORT}  (no telemovel: http://IP_DO_PC:{PORT})")
    httpd.serve_forever()
