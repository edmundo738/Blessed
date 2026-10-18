#!/usr/bin/env bash
# Verificação do projeto: gera a cache de classes, empacota e corre o self-test.
#
#   ./tools/check.sh            # só o self-test
#   ./tools/check.sh --pack     # self-test + build do .pck web
#
# Precisa de um Godot 4.x no PATH (ou GODOT_BIN apontado para o binário).
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT_BIN:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo "erro: Godot não encontrado. Instala o Godot 4.x ou define GODOT_BIN." >&2
  exit 127
fi

python3 tools/gen_class_cache.py . >/dev/null

# Num clone limpo (ou num contentor) não existe `.godot/imported/`: sem essa
# cache o motor não abre `.ctex`/`.scn` e o self-test falha em quase tudo por
# uma razão que não é código. Importar primeiro torna o resultado fiável.
if [ ! -d .godot/imported ]; then
  echo "→ importar recursos (primeira corrida: não há cache do editor)"
  "$GODOT" --headless --path . --import
fi

echo "→ self-test"
"$GODOT" --headless --path . --quit-after 1200 -- selftest

if [ "${1:-}" = "--pack" ]; then
  echo "→ build do .pck"
  mkdir -p export
  python3 tools/pack_pck.py . export/blessed.pck
fi
