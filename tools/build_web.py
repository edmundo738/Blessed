#!/usr/bin/env python3
"""
build_web.py — monta a pasta web jogável.

  python3 tools/build_web.py [pasta_de_saida]   (default: export/web)

Passos:
  1. regenera .godot/global_script_class_cache.cfg   (sem isto, `class_name` falha)
  2. corre o self-test do projeto, se o Godot nativo estiver no PATH
  3. empacota o projeto para blessed.pck (ver tools/pack_pck.py)
  4. copia o template web do motor + web/index.html para a pasta de saída

O motor web não vive no repositório: vem do pacote npm
`@ringozz/godot-web-wasm32` (ver tools/setup_engine.sh) e é lido de
$BLESSED_ENGINE (default: ~/.cache/blessed/engine).
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def engine_dir():
	d = os.environ.get("BLESSED_ENGINE") or os.path.join(
		os.path.expanduser("~"), ".cache", "blessed", "engine")
	if not os.path.isdir(d):
		raise SystemExit("motor web não encontrado em %s — corre tools/setup_engine.sh" % d)
	return d


def main():
	out = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, "export", "web")
	os.makedirs(out, exist_ok=True)

	# 1. cache de classes
	subprocess.run([sys.executable, os.path.join(ROOT, "tools", "gen_class_cache.py"), ROOT], check=True)

	# 2. self-test (só se houver Godot nativo; no browser usa-se run_godot.mjs)
	godot = shutil.which("godot") or shutil.which("godot4")
	if godot:
		r = subprocess.run([godot, "--headless", "--path", ROOT, "--quit-after", "3000", "--", "selftest"])
		if r.returncode != 0:
			print("\nO self-test falhou — a build continua, mas revê o output acima.")

	# 3. pck
	subprocess.run([sys.executable, os.path.join(ROOT, "tools", "pack_pck.py"), ROOT,
					os.path.join(out, "blessed.pck")], check=True)

	# 4. template web: todo o .js pelo seu nome, todo o .wasm passa a godot.wasm
	# (web/index.html resolve o wasm via locateFile, por isso o nome é nosso).
	import glob
	eng = engine_dir()
	any_wasm = False
	for p in sorted(glob.glob(os.path.join(eng, "*"))):
		base = os.path.basename(p)
		if base.endswith(".wasm"):
			shutil.copyfile(p, os.path.join(out, "godot.wasm"))
			any_wasm = True
		elif base.endswith(".js") and base != "godot.js":
			shutil.copyfile(p, os.path.join(out, base))
		elif base == "godot.js":
			shutil.copyfile(p, os.path.join(out, "godot.js"))
		else:
			print("ignorado do motor: %s" % base)
	if not any_wasm:
		raise SystemExit("não há .wasm em %s — corre tools/setup_engine.sh" % eng)
	shutil.copyfile(os.path.join(ROOT, "web", "index.html"), os.path.join(out, "index.html"))

	size = os.path.getsize(os.path.join(out, "blessed.pck"))
	print("\nbuild web pronta em %s" % out)
	print("  blessed.pck   %.0f KB" % (size / 1024.0))
	print("  para jogar:   python3 tools/serve_web.py %s" % out)


if __name__ == "__main__":
	main()
