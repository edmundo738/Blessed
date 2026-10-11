#!/usr/bin/env bash
# Instala o template WEB do Godot 4.7.2 (os binários oficiais são grandes;
# este pacote npm traz exatamente os 4 ficheiros de que precisamos).
set -euo pipefail
VERSION="${GODOT_WEB_VERSION:-4.7.2-643}"
DIR="${BLESSED_ENGINE:-$HOME/.cache/blessed/engine}"
mkdir -p "$DIR"
TMP="$(mktemp -d)"
cd "$TMP"
npm pack "@ringozz/godot-web-wasm32@$VERSION" >/dev/null
tar -xzf ./*.tgz
# os binários vivem em package/gen/ com nomes longos; normalizamos para
# godot.js / godot.wasm, que e o que o harness procura
cp package/gen/godot.web.template_release.wasm32.nothreads.js "$DIR/godot.js"
cp package/gen/godot.web.template_release.wasm32.nothreads.wasm "$DIR/godot.wasm"
cp package/gen/audio.worklet.js "$DIR/" 2>/dev/null || true
cp package/gen/audio.position.worklet.js "$DIR/" 2>/dev/null || true
rm -rf "$TMP"
echo "motor web instalado em $DIR"
ls -1 "$DIR"
