#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
pack_pck.py -- escreve um .pck do Godot 4 (formato V3) a partir de uma pasta.

Porque existe: o export oficial precisa do editor + dos export templates, que
nao estao disponiveis em todo o lado (CI, sandbox, maquina sem editor).
Este script produz exatamente o mesmo contentor que o Godot le em runtime:
res:// continua a funcionar e o projeto abre no editor sem diferenca.

Layout (igual ao de editor/export/editor_export_platform.cpp):

    "GDPC"                      uint32 magic  (0x43504447, little endian)
    version                     uint32 (3 = V3)
    ver_major, ver_minor, patch uint32 x3
    pack_flags                  uint32 (PACK_REL_FILEBASE = 2)
    file_base                   uint64  (offset dos dados, relativo ao inicio do pck)
    dir_offset                  uint64  (offset do diretorio, relativo ao inicio do pck)
    reserved                    uint32 x16
    [padding ate 16 bytes]
    dados dos ficheiros         cada um alinhado a 16
    [padding ate 16 bytes]
    diretorio:
        file_count              uint32
        por ficheiro:
            sl                  uint32  (comprimento do path + pad ate multiplo de 4)
            path                sl bytes (sem prefixo "res://")
            ofs                 uint64  (relativo a file_base)
            size                uint64
            md5                 16 bytes
            flags               uint32

Uso:
    python3 tools/pack_pck.py <pasta_projeto> <saida.pck> [--exclude padrao ...]
"""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import os
import struct
import sys

MAGIC = 0x43504447
FORMAT_VERSION = 3  # V3: lido por Godot 4.3+ (V4 so muda no caso encriptado/sparse)
PACK_REL_FILEBASE = 1 << 1
PCK_PADDING = 16

# O que nunca entra no contentor (estado local, VCS, ferramentas de dev).
DEFAULT_EXCLUDE = (
    ".git",
    ".gitignore",
    ".gitattributes",
    ".godot",
    ".import",
    "tools",
    "tests",
    "docs",
    "export",
    "web",
    "*.tmp",
    "*.md5",
    "export_presets.cfg",
    "export_credentials.cfg",
    "*.blend1",
    ".*.swp",
    ".DS_Store",
    "Thumbs.db",
)

# Exceções: dentro das pastas ignoradas, isto tem MESMO de viajar no .pck.
# A cache de classes é o que faz `class_name` funcionar fora do editor.
ALWAYS_INCLUDE = (
    ".godot/global_script_class_cache.cfg",
)


def align(n: int, to: int) -> int:
    rest = n % to
    return 0 if rest == 0 else to - rest


def collect(root: str, excludes: tuple[str, ...]) -> list[tuple[str, str]]:
    """Devolve [(caminho_relativo_posix, caminho_absoluto)] ordenado e deterministico."""
    out: list[tuple[str, str]] = []
    for dirpath, dirnames, filenames in os.walk(root):
        keep = []
        for d in sorted(dirnames):
            rel_dir = os.path.relpath(os.path.join(dirpath, d), root).replace(os.sep, "/")
            if not _excluded(d + "/", excludes) or any(
                i.startswith(rel_dir + "/") for i in ALWAYS_INCLUDE
            ):
                keep.append(d)
        dirnames[:] = keep
        for name in sorted(filenames):
            abs_path = os.path.join(dirpath, name)
            rel = os.path.relpath(abs_path, root).replace(os.sep, "/")
            if rel in ALWAYS_INCLUDE:
                out.append((rel, abs_path))
                continue
            if _excluded(rel, excludes) or _excluded(name, excludes):
                continue
            out.append((rel, abs_path))
    out.sort(key=lambda t: t[0])
    return out


def _excluded(rel: str, excludes: tuple[str, ...]) -> bool:
    parts = rel.split("/")
    for pat in excludes:
        for part in parts:
            if fnmatch.fnmatch(part, pat):
                return True
    return False


def _build_stamp(root: str) -> str:
    import subprocess, datetime
    h = "dev"
    try:
        h = subprocess.run(["git", "-C", root, "rev-parse", "--short", "HEAD"],
                           capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        pass
    return "%s %s" % (h, datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%MZ"))


def write_pck(root: str, dest: str, excludes: tuple[str, ...], engine=(4, 7, 2)) -> int:
    files = collect(root, excludes)
    # carimbo de build: o jogo mostra-o no HUD e imprime-o na consola, para se
    # saber SEMPRE que build esta a correr (acabam as rondas as cegas)
    files.append(("build_info", None))
    if not files:
        raise SystemExit("pack_pck: nada para empacotar em %s" % root)

    entries: list[tuple[bytes, int, int, bytes]] = []
    with open(dest, "wb") as f:
        # --- cabecalho ---
        f.write(struct.pack("<IIIII", MAGIC, FORMAT_VERSION, engine[0], engine[1], engine[2]))
        f.write(struct.pack("<I", PACK_REL_FILEBASE))
        f.write(struct.pack("<Q", 0))  # file_base (preenchido depois)
        f.write(struct.pack("<Q", 0))  # dir_offset (preenchido depois)
        f.write(b"\x00" * 4 * 16)      # reserved (8 + 8 uint32)

        # --- dados (alinhado a 16) ---
        f.write(b"\x00" * align(f.tell(), PCK_PADDING))
        file_base = f.tell()

        for rel, abs_path in files:
            if abs_path is None:  # entrada virtual (build_info)
                data = _build_stamp(root).encode("utf-8")
            else:
                with open(abs_path, "rb") as src:
                    data = src.read()
            ofs = f.tell()
            f.write(data)
            f.write(b"\x00" * align(f.tell(), PCK_PADDING))
            path_utf8 = rel.encode("utf-8")
            entries.append((path_utf8, ofs - file_base, len(data), hashlib.md5(data).digest()))

        # --- diretorio (alinhado a 16) ---
        f.write(b"\x00" * align(f.tell(), PCK_PADDING))
        dir_offset = f.tell()

        # posicoes absolutas no cabecalho:
        #   0..3   magic | 4..7 version | 8..19 ver_major/minor/patch
        #   20..23 pack_flags | 24..31 file_base | 32..39 dir_offset | 40..103 reserved
        f.seek(24)
        f.write(struct.pack("<Q", file_base))
        f.seek(32)
        f.write(struct.pack("<Q", dir_offset))
        f.seek(dir_offset)

        f.write(struct.pack("<I", len(entries)))
        for path_utf8, ofs, size, md5 in entries:
            pad = align(len(path_utf8), 4)
            f.write(struct.pack("<I", len(path_utf8) + pad))
            f.write(path_utf8)
            f.write(b"\x00" * pad)
            f.write(struct.pack("<QQ", ofs, size))
            f.write(md5)
            f.write(struct.pack("<I", 0))  # flags: nem encriptado, nem remocao, nem delta

        end = f.tell()

    return end


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Empacota um projeto Godot num .pck (formato V3).")
    ap.add_argument("projeto")
    ap.add_argument("saida")
    ap.add_argument("--exclude", action="append", default=[], help="padrao extra (fnmatch), repetivel")
    ap.add_argument("--engine", default="4.7.2", help="versao do motor gravada no cabecalho")
    args = ap.parse_args(argv)

    maj, mnr, pat = (int(x) for x in args.engine.split("."))
    excludes = tuple(DEFAULT_EXCLUDE) + tuple(args.exclude)
    size = write_pck(os.path.abspath(args.projeto), args.saida, excludes, (maj, mnr, pat))
    print("pack_pck: %s -> %s (%d bytes)" % (args.projeto, args.saida, size))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
