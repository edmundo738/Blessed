#!/usr/bin/env python3
# Mapa de campos do LabWorld (debug visual da Etapa 1).
# Espelha o modelo de dados de scripts/world/lab_world.gd (ilha, montanha NW,
# bacia SE, D8, rios/lagos, biomas, manchas de especies) e escreve 1 PNG
# sem dependencias (stdlib). Nao e screenshot do renderer: e o modelo visto
# de cima, para provar causalidade antes de haver mesh 3D do laboratorio.
import json, math, struct, zlib, sys

W, H, M = 960, 540, 200.0  # mundo -200..200 m
N = 200

def h2(ix, iz, s):
    v = (ix * 374761393 + iz * 668265263 + s * 1274126177) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((v ^ (v >> 16)) & 0xFFFF) / 65535.0

def noise(x, z, freq, seed):
    fx, fz = x * freq, z * freq
    ix, iz = math.floor(fx), math.floor(fz)
    tx, tz = fx - ix, fz - iz
    tx, tz = tx * tx * (3 - 2 * tx), tz * tz * (3 - 2 * tz)
    a, b = h2(ix, iz, seed), h2(ix + 1, iz, seed)
    c, d = h2(ix, iz + 1, seed), h2(ix + 1, iz + 1, seed)
    return (a + (b - a) * tx + (c - a) * tz + (a - b - c + d) * tx * tz) * 2 - 1

def relief(x, z):
    r = math.hypot(x, z)
    t = max(0.0, min(1.0, (208 - r) / 150))
    t = t * t * (3 - 2 * t)
    land = -19 + (12.5 + 19) * (t ** 1.25)
    dm = math.hypot(x + 80, z + 70)
    dl = math.hypot(x - 85, z - 78)
    vx = -80 + (z + 70) * 0.42 + math.sin(z * 0.018) * 14
    vt = max(0.0, min(1.0, (z + 95) / 265))
    valley = 4.2 * math.exp(-((x - vx) ** 2) / (2 * 26 * 26)) * math.sin(math.pi * max(0.02, min(0.98, vt)))
    return (land + 34 * math.exp(-(dm * dm) / (2 * 62 * 62))
            + noise(x, z, 0.012, 1358) * 3.2 * t
            + noise(x, z, 0.045, 1359) * 0.6
            - 5.5 * math.exp(-(dl * dl) / (2 * 30 * 30)) - valley)

# grelha + D8
G = N * N
base = [0.0] * G
for j in range(N):
    for i in range(N):
        base[j * N + i] = relief(-M + 400 * i / (N - 1), -M + 400 * j / (N - 1))
filled = base[:]
for _ in range(24):
    ch = False
    for j in range(1, N - 1):
        for i in range(1, N - 1):
            k = j * N + i
            if filled[k] <= 0: continue
            mn = min(filled[(j+dj)*N+i+di] for dj in (-1,0,1) for di in (-1,0,1) if di or dj)
            if filled[k] <= mn:
                filled[k] = mn + 0.02; ch = True
    if not ch: break
acc = [1.0] * G
order = sorted(range(G), key=lambda k: -filled[k])
NB = [(di, dj) for dj in (-1,0,1) for di in (-1,0,1) if di or dj]
for k in order:
    i, j = k % N, k // N
    best, bh = -1, filled[k]
    for di, dj in NB:
        ni, nj = i + di, j + dj
        if 0 <= ni < N and 0 <= nj < N and filled[nj*N+ni] < bh:
            bh, best = filled[nj*N+ni], nj * N + ni
    if best >= 0: acc[best] += acc[k]

BIOME = {0:(10,40,90),1:(205,185,140),2:(90,140,70),3:(35,95,45),
         4:(215,150,175),5:(125,120,125),6:(70,110,80),7:(200,170,95)}
def biome(k, x, z, h):
    if h < 0: return 0
    if h < 0.7: return 1
    if h > 30: return 5
    rain = 0.52 + noise(x, z, 0.006, 1360) * 0.34 + (-x / 400) * 0.30
    if math.hypot(x - 55, z + 55) < 42 and rain > 0.4: return 4
    if rain < 0.36: return 7
    if noise(x, z, 0.010, 1362) > 0.08 and rain > 0.42: return 3
    if acc[k] >= 14: return 6
    return 2

img = bytearray(W * H * 3)
def px(x, y, c):
    o = (y * W + x) * 3
    img[o:o+3] = bytes(c)

stations = json.load(open('data/lab.json'))['stations']
for y in range(H):
    for x in range(W):
        if x < 480:  # esquerda: relevo+bioma+agua
            i = min(N-1, x * N // 480); j = min(N-1, y * N // 480)
            k = j * N + i
            wx, wz = -M + 400*i/(N-1), -M + 400*j/(N-1)
            h = base[k]
            c = list(BIOME[biome(k, wx, wz, h)])
            sh = max(0.55, min(1.25, 1 + (h - base[j*N+max(0,i-1)]) * 0.04)) if h >= 0 else 1.0
            c = [max(0, min(255, int(v * sh))) for v in c]
            if h < 0: c = [15, 70, 130] if h < -8 else [40, 130, 180]
            elif acc[k] >= 300: c = [50, 150, 220]
            px(x, y, c)
        else:  # direita: densidade de especies (carvalho/sakura/salgueiro)
            i = min(N-1, (x-480) * N // 480); j = min(N-1, y * N // 480)
            k = j * N + i
            wx, wz = -M + 400*i/(N-1), -M + 400*j/(N-1)
            h = base[k]
            if h < 0: px(x, y, (15, 50, 100)); continue
            pa = noise(wx, wz, 0.010, 1362) * 0.5 + 0.5
            oak = pa * 0.9
            sak = max(0.0, 1 - math.hypot(wx-55, wz+55) / 46) * pa
            wil = math.exp(-min(acc[k], 60) / 40) * 0.4
            px(x, y, (int(30 + oak*90), int(60 + oak*110 + sak*40), int(30 + sak*90 + wil*60)))

for st in stations:  # estacoes: pontos brancos nos dois paineis
    for ox in (0, 480):
        cx = ox + int((st['x'] + M) / 400 * 480); cy = int((st['z'] + M) / 400 * 480)
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                if dx*dx + dy*dy <= 9 and 0 <= cx+dx < W and 0 <= cy+dy < H:
                    px(cx+dx, cy+dy, (255, 255, 255))

raw = b''.join(b'\x00' + bytes(img[y*W*3:(y+1)*W*3]) for y in range(H))
def chunk(t, d):
    c = t + d
    return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(bytes(raw), 6)) + chunk(b'IEND', b''))
out = sys.argv[1] if len(sys.argv) > 1 else 'docs/shots/08_lab_world.png'
open(out, 'wb').write(png)
print('rios celulas~', sum(1 for k in range(G) if acc[k] >= 300 and base[k] >= 0), '->', out)
