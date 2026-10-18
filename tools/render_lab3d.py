#!/usr/bin/env python3
# Render obliquo do laboratorio a partir do LABGRID_B64 do tests/labscene.gd.
# Uso: render_lab3d.py <log> <saida.png>  — stdlib apenas.
#
# SENSIVEL A WINDING: antes de desenhar, le a ordem real dos indices de
# scripts/world/lab_mesh.gd e aplica a regra do Godot (KNOWN_ISSUES #9:
# frontal = winding horaria; vista de cima, uma face so e desenhada se o
# produto cruzado geometrico apontar para BAIXO, cross_y < 0). Se o
# terreno ou a agua voltarem a ficar espelhados, este script FALHA e nao
# gera PNG — a imagem antiga escondia o bug porque desenhava os dois lados.
import base64, math, os, re, struct, sys, zlib


def _cross_y(p, q, r):
    ux, uz = q[0] - p[0], q[1] - p[1]
    vx, vz = r[0] - p[0], r[1] - p[1]
    return uz * vx - ux * vz


def check_winding():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "..", "scripts", "world", "lab_mesh.gd")
    src = open(path).read()
    corner = {"a": (0, 0), "b": (1, 0), "c": (0, 1), "d": (1, 1)}
    m = re.search(r"idx\.append_array\(\[([a-d](?:, [a-d]){5})\]\)", src)
    if not m:
        sys.exit("render_lab3d: nao encontrei a ordem de indices do terreno")
    tok = [t.strip() for t in m.group(1).split(",")]
    tris = [(tok[0], tok[1], tok[2]), (tok[3], tok[4], tok[5])]
    for t in tris:
        if _cross_y(corner[t[0]], corner[t[1]], corner[t[2]]) > 0:
            sys.exit("render_lab3d: winding do TERRENO virada — a face de "
                     "cima seria cullada no Godot (PNG recusado)")
    wcorner = {0: (0, 0), 1: (1, 0), 2: (0, 1), 3: (1, 1)}
    w = re.search(r"idx\.append_array\(\[base, base \+ (\d), base \+ (\d), "
                  r"base, base \+ (\d), base \+ (\d)\]\)", src)
    if not w:
        sys.exit("render_lab3d: nao encontrei a ordem de indices da agua")
    nums = [int(g) for g in w.groups()]
    for t in [(0, nums[0], nums[1]), (0, nums[2], nums[3])]:
        if _cross_y(wcorner[t[0]], wcorner[t[1]], wcorner[t[2]]) > 0:
            sys.exit("render_lab3d: winding da AGUA virada — a face de "
                     "cima seria cullada no Godot (PNG recusado)")
    print("winding ok: faces de cima sao frontais (terreno + agua)")


check_winding()

W, H = 960, 540
log = open(sys.argv[1]).read()
b64 = [l.split("LABGRID_B64:", 1)[1].strip() for l in log.splitlines() if "LABGRID_B64:" in l][-1]
raw = base64.b64decode(b64)
N = 81
hgt = [[0.0] * N for _ in range(N)]
wtr = [[0] * N for _ in range(N)]
for j in range(N):
    for i in range(N):
        hgt[j][i] = raw[(j * N + i) * 2] / 255.0 * 70.0 - 20.0
        wtr[j][i] = raw[(j * N + i) * 2 + 1]

def biome(h, w, moist):
    if w == 255 and h < 0.5:
        return (30, 90, 160)
    if h < 0:
        return (25, 80, 145)
    if h < 0.7:
        return (205, 185, 140)
    if h > 30:
        return (125, 120, 125)
    if moist > 170:
        return (35, 95, 45)
    return (95, 145, 70)

img = bytearray(W * H * 3)
for k in range(W * H):
    img[k * 3:k * 3 + 3] = bytes((12, 18, 38))

def px(x, y, c):
    if 0 <= x < W and 0 <= y < H:
        o = (y * W + x) * 3
        img[o:o + 3] = bytes(c)

def proj(i, j, h):
    # obliquo: x do mundo -> ecra x, z -> ecra y comprimido, altura sobe
    x = 90 + (i / (N - 1)) * 780
    y = 470 - (j / (N - 1)) * 300 - h * 4.2
    return (x, y)

# painter: de tras (j alto) para a frente
cells = []
for j in range(N - 1):
    for i in range(N - 1):
        cells.append((j, i))
cells.sort(key=lambda c: -c[0])
step = 3  # desenha celulas de 3 em 3 para caber no ecra
for j in range(0, N - 3, step):
    for i in range(0, N - 3, step):
        h = hgt[j][i]
        w = wtr[j][i]
        c = biome(h, w, w if w != 255 else 0)
        shade = 0.75 + max(-0.25, min(0.35, (hgt[j][i] - hgt[j][min(N - 1, i + step)]) * 0.05))
        c = tuple(max(0, min(255, int(v * shade))) for v in c)
        x0, y0 = proj(i, j, h)
        x1, y1 = proj(i + step, j, hgt[j][min(N - 1, i + step)])
        size = int(780 / N * step) + 2
        for dy in range(size):
            for dx in range(size):
                px(int(x0) + dx, int(y0) + dy - size // 2, c)
raw_rows = b''.join(b'\x00' + bytes(img[y * W * 3:(y + 1) * W * 3]) for y in range(H))
def chunk(t, d):
    c = t + d
    return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
png = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(bytes(raw_rows), 6)) + chunk(b'IEND', b''))
open(sys.argv[2], 'wb').write(png)
print('->', sys.argv[2])
