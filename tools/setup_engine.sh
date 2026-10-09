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
cp package/* "$DIR"/
rm -rf "$TMP"
echo "motor web instalado em $DIR"
ls -1 "$DIR"
