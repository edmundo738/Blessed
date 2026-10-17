#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
mkpack.py -- empacota o projeto COM os testes dentro.

O `tools/pack_pck.py` exclui `tests/` e `docs/` de proposito: e o contentor que
vai para o jogador. Mas para correr o autoteste o motor precisa de ler
`res://tests/selftest.gd`, por isso esta variante tira `tests` da lista de
exclusoes. Sem isto o motor responde:

    SELFTEST_FAIL: res://tests/selftest.gd em falta

Uso:
    python3 tools/mkpack.py <pasta_projeto> <saida.pck>
"""

from __future__ import annotations

import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
# o mkpack.py pode viver em tools/ ou numa copia fora do repo: o pack_pck.py
# procura-se ao lado e, se nao estiver, em <projeto>/tools
for _cand in (_here, os.path.join(sys.argv[1] if len(sys.argv) > 1 else ".", "tools")):
    if os.path.isfile(os.path.join(_cand, "pack_pck.py")):
        sys.path.insert(0, _cand)
        break
import pack_pck  # noqa: E402


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    root, dest = argv[1], argv[2]
    excludes = tuple(e for e in pack_pck.DEFAULT_EXCLUDE if e != "tests")
    size = pack_pck.write_pck(root, dest, excludes, (4, 7, 2))
    print(f"{dest}: {size} bytes (com tests/)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
