#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gen_class_cache.py -- gera `.godot/global_script_class_cache.cfg`.

O editor do Godot constrói esta cache ao varrer o projeto; um export guarda-a
dentro do .pck. Sem ela, um projeto corrido "a frio" (harness headless, .pck
feito por script, CI) falha com `Identifier "X" not declared` em cada
`class_name`. Este script reproduz o ficheiro exatamente como o Godot o le
(ProjectSettings::get_global_class_list):

    [ ]
    list=[{ "base": ..., "class": ..., "is_abstract": ..., "is_tool": ...,
            "language": "GDScript", "path": "res://..." }, ...]

Uso:
    python3 tools/gen_class_cache.py [pasta_projeto]
"""

from __future__ import annotations

import os
import re
import sys

CLASS_RE = re.compile(r"^\s*class_name\s+([A-Za-z_][A-Za-z0-9_]*)", re.M)
EXTENDS_RE = re.compile(r"^\s*extends\s+([A-Za-z_][A-Za-z0-9_.]*)", re.M)
TOOL_RE = re.compile(r"^\s*@tool\b", re.M)


def scan(root: str) -> list[dict]:
    entries: dict[str, dict] = {}
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".git", ".godot")]
        for name in filenames:
            if not name.endswith(".gd"):
                continue
            abs_path = os.path.join(dirpath, name)
            rel = os.path.relpath(abs_path, root).replace(os.sep, "/")
            with open(abs_path, "r", encoding="utf-8") as f:
                src = f.read()
            m = CLASS_RE.search(src)
            if not m:
                continue
            e = EXTENDS_RE.search(src)
            entries[m.group(1)] = {
                "class": m.group(1),
                "base": e.group(1) if e else "RefCounted",
                "language": "GDScript",
                "path": "res://" + rel,
                "is_abstract": False,
                "is_tool": bool(TOOL_RE.search(src)),
            }
    # resolve cadeias: extends Nome -> base real da classe pai
    for _ in range(8):
        changed = False
        for e in entries.values():
            b = e["base"]
            if b in entries and entries[b]["class"] != e["class"]:
                e["base"] = entries[b]["base"]
                changed = True
        if not changed:
            break
    return [entries[k] for k in sorted(entries)]


def to_variant(entries: list[dict]) -> str:
    parts = []
    for e in entries:
        parts.append(
            "{{\n\"base\": &\"{base}\",\n\"class\": &\"{cls}\",\n"
            "\"is_abstract\": {abs},\n\"is_tool\": {tool},\n"
            "\"language\": &\"GDScript\",\n\"path\": \"{path}\"\n}}".format(
                base=e["base"], cls=e["class"],
                abs="true" if e["is_abstract"] else "false",
                tool="true" if e["is_tool"] else "false",
                path=e["path"],
            )
        )
    return "list=[%s]\n" % ", ".join(parts)


def main(argv: list[str]) -> int:
    root = os.path.abspath(argv[0] if argv else ".")
    entries = scan(root)
    out_dir = os.path.join(root, ".godot")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, "global_script_class_cache.cfg")
    # Nota importante sobre o formato: o ConfigFile do Godot NÃO escreve
    # cabeçalho para a secção vazia (`if (!E.key.is_empty())`), e o parser trata
    # "[]" como um Array vazio, não como secção. Por isso a chave `list` tem de
    # ficar no TOPO do ficheiro, antes de qualquer [seccao].
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(to_variant(entries))
    print("gen_class_cache: %d classes -> %s" % (len(entries), out))
    for e in entries:
        print("   %-14s extends %-14s %s" % (e["class"], e["base"], e["path"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
