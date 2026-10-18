#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make_grass_masks.py — gera as máscaras de relva usadas pelos shaders.

Porque é que isto é um ficheiro e não código de shader
------------------------------------------------------
O volume de relva (shell texturing) recorta cada nível pela ALTURA do fio. Isso
exige uma textura de alturas: cada texel guarda «até que altura há fio aqui», e o
nível do shell decide o corte. É o modelo do diagrama da pelagem (xbdev / Crumble):

    Density Layers → cada camada é o mesmo campo, cortado mais alto
    «density is reduced so we have different length hairs»
    «spike effect is created by reducing the alpha value towards the peak»

Fazer isto em código de shader por pixel seria pagar 100 linhas de ruído por pixel
de relva; fazer isto uma vez, aqui, custa zero em runtime e dá resultados
repetíveis — o rasterizador de diagnóstico e o motor leem exatamente o mesmo PNG.

Saída (todas 512x512, RGB, repetíveis nos dois eixos):
    grass_fur.png     R = altura do fio (0 = sem fio, 1 = fio máximo)
                      G = variação por fio (tinta: verde↔seco)
                      B = massa de larga escala (tufos)
    grass_streak.png  R = riscas de vento alongadas
                      G = ruído fino de quebra
                      B = manchas de secura

Uso:
    python3 tools/make_grass_masks.py            # escreve em content/fx/grass/
    python3 tools/make_grass_masks.py --size 1024
"""

from __future__ import annotations

import argparse
import math
import os
import random
import struct
import zlib

OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                       "content", "fx", "grass")


# ── escritor de PNG (sem dependências) ───────────────────────────────────────
def write_png(path: str, width: int, height: int, rgb: bytearray) -> None:
    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)                       # filtro 0 (None)
        raw += rgb[y * stride:(y + 1) * stride]

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


# ── ruído repetível (tileable) ───────────────────────────────────────────────
def value_noise(seed: int, cells: int, size: int, octaves: int = 1,
                gain: float = 0.5) -> list[float]:
    """Ruído de valor bilinear em grelha periódica → repetível por construção."""
    out = [0.0] * (size * size)
    total_amp = 0.0
    amp = 1.0
    for o in range(octaves):
        n = cells * (2 ** o)
        rng = random.Random(seed + o * 977)
        grid = [[rng.random() for _ in range(n)] for _ in range(n)]
        scale = n / size
        for y in range(size):
            gy = y * scale
            y0 = int(gy) % n
            y1 = (y0 + 1) % n
            fy = gy - int(gy)
            fy = fy * fy * (3.0 - 2.0 * fy)
            row0 = grid[y0]
            row1 = grid[y1]
            base = y * size
            for x in range(size):
                gx = x * scale
                x0 = int(gx) % n
                x1 = (x0 + 1) % n
                fx = gx - int(gx)
                fx = fx * fx * (3.0 - 2.0 * fx)
                a = row0[x0] + (row0[x1] - row0[x0]) * fx
                b = row1[x0] + (row1[x1] - row1[x0]) * fx
                out[base + x] += (a + (b - a) * fy) * amp
        total_amp += amp
        amp *= gain
    inv = 1.0 / max(total_amp, 1e-9)
    return [v * inv for v in out]


# ── campo de alturas do fio ─────────────────────────────────────────────────
def fur_field(size: int, seed: int, strands: int) -> tuple[list[float], list[float]]:
    """Campo de alturas da relva: cada fio é uma lâmina afunilada para a ponta.

    Cada texel guarda **até que altura há fio** naquele ponto (R) e o tom do fio
    (G). As lâminas são quase verticais na textura (inclinação máxima ~22°): é
    isso que faz com que a pilha de níveis forme folhas direitas em vez de placas
    horizontais. Um fio desenhado deitado só existiria entre dois níveis seguidos.

    O campo é rasterizado 3x3 (deslocamentos -size, 0, +size) para as lâminas que
    atravessam a borda continuarem do outro lado: sem isto a relva teria uma
    costura em cada repetição da textura.
    """
    height = [0.0] * (size * size)
    tint = [0.0] * (size * size)
    rng = random.Random(seed)

    for _ in range(strands):
        base_x = rng.random() * size
        base_y = rng.random() * size
        # lâmina quase vertical: ±22° em torno do eixo +Y da textura
        lean = math.radians((rng.random() - 0.5) * 44.0)
        along = (math.sin(lean), math.cos(lean))
        across = (-along[1], along[0])
        half = size * (0.055 + rng.random() * 0.075)     # 28..66 px num ladrilho de 512
        width = 2.4 + rng.random() * 4.6                 # meia-largura na base, em texels
        bow = (rng.random() - 0.5) * 0.30                # curvatura lateral
        tone = rng.random()
        reach = int(half + width + 4.0)

        for oy in (-size, 0, size):
            for ox in (-size, 0, size):
                for s in range(-reach, reach + 1):
                    t = s / max(half, 1e-6)              # -1 base .. +1 ponta
                    if t < -1.0 or t > 1.0:
                        continue
                    u = (t + 1.0) * 0.5                 # 0 base .. 1 ponta
                    # meia-largura: larga na base, aguçada na ponta (com um leve bojo)
                    w = width * (1.0 - u) ** 0.62 * (1.0 + 0.35 * math.sin(u * math.pi))
                    if w < 0.45:
                        continue
                    px = base_x + along[0] * s + across[0] * bow * u * u + ox
                    py = base_y + along[1] * s + across[1] * bow * u * u + oy
                    # altura da lâmina neste ponto: cresce até à ponta
                    tip = min(1.0, u ** 0.80)
                    cx = int(math.floor(px))
                    cy = int(math.floor(py))
                    span = int(w) + 1
                    for dx in range(-span, span + 1):
                        for dy in range(-span, span + 1):
                            d = math.hypot(px - (cx + dx + 0.5), py - (cy + dy + 0.5))
                            if d > w:
                                continue
                            # perfil da secção: a crista central é o ponto mais alto
                            value = tip * (1.0 - 0.45 * (d / w))
                            idx = ((cy + dy) % size) * size + ((cx + dx) % size)
                            if value > height[idx]:
                                height[idx] = value
                                tint[idx] = tone

    top = max(height) or 1.0
    inv = 1.0 / top
    height = [min(1.0, v * inv) for v in height]
    return height, tint


def build_rgb(height, tint, mass, fine, streak, dry, size) -> bytearray:
    out = bytearray(size * size * 3)
    for i in range(size * size):
        j = i * 3
        out[j] = int(max(0.0, min(1.0, height[i])) * 255.0)
        out[j + 1] = int(max(0.0, min(1.0, tint[i] * 0.65 + fine[i] * 0.35)) * 255.0)
        out[j + 2] = int(max(0.0, min(1.0, mass[i])) * 255.0)
    return out


def build_streak_rgb(streak, fine, dry, size) -> bytearray:
    out = bytearray(size * size * 3)
    for i in range(size * size):
        j = i * 3
        out[j] = int(max(0.0, min(1.0, streak[i])) * 255.0)
        out[j + 1] = int(max(0.0, min(1.0, fine[i])) * 255.0)
        out[j + 2] = int(max(0.0, min(1.0, dry[i])) * 255.0)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description="Gera as máscaras de relva (fur/streak).")
    ap.add_argument("--size", type=int, default=512)
    ap.add_argument("--strands", type=int, default=0, help="fios por ladrilho (0 = automático)")
    ap.add_argument("--out", default=OUT_DIR)
    args = ap.parse_args()

    size = args.size
    # Densidade: um campo de relva lê-se pela COBERTURA. Com ~200 fios num
    # ladrilho de 512 a relva fica esparsa e o chão aparece entre as lâminas em
    # manchas (o "picotado"); ~420 fios sobrepõem-se e o campo fecha.
    strands = args.strands or max(140, int(size * size / 620))
    os.makedirs(args.out, exist_ok=True)

    height, tint = fur_field(size, 20260115, strands)
    mass = value_noise(771, 4, size, octaves=3, gain=0.55)
    fine = value_noise(313, 32, size, octaves=2, gain=0.5)
    streak = value_noise(911, 3, size, octaves=2, gain=0.45)
    dry = value_noise(4242, 2, size, octaves=2, gain=0.5)

    # riscas alongadas: mistura do ruído de poucas células numa direção
    rows = value_noise(5150, 2, size, octaves=1)
    for y in range(size):
        for x in range(size):
            i = y * size + x
            v = rows[i] * 0.6 + streak[i] * 0.4
            streak[i] = v

    fur = os.path.join(args.out, "grass_fur.png")
    st = os.path.join(args.out, "grass_streak.png")
    write_png(fur, size, size, build_rgb(height, tint, mass, fine, streak, dry, size))
    write_png(st, size, size, build_streak_rgb(streak, fine, dry, size))

    covered = sum(1 for v in height if v > 0.02) / float(size * size)
    print("grama: %s  fios=%d  cobertura=%.1f%%" % (fur, strands, covered * 100.0))
    print("grama: %s" % st)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
