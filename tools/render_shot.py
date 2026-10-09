#!/usr/bin/env python3
"""render_shot.py — rasteriza o dump do Godot headless e escreve um PNG.

Porque é que isto existe
------------------------
Não há GPU nem browser no sandbox onde este projecto é escrito. Durante semanas
cada bug visual foi "o utilizador descreve, o agente adivinha", e adivinhar é
exactamente o que produziu as rondas de correcções erradas.

Isto acaba com isso. `tests/shot.gd` corre o jogo no motor real, em headless, e
serializa a geometria que o Godot ia mandar para a GPU: as mesmas malhas, as
mesmas transformações globais, as mesmas normais e as mesmas cores de vértice.
Este script rasteriza esses dados — com z-buffer, backface culling e a MESMA
matemática de iluminação dos .gdshader — e escreve uma imagem. O agente lê a
imagem e VÊ o resultado. Deixou de ser inferência.

O que isto NÃO é: não é o renderer do Godot. Não há shadow maps, não há SSAO,
não há MSAA, e o passe transparente é aproximado. Serve para responder a
perguntas de geometria e de shading — "esta face está virada para onde?",
"que cor sai daqui?", "vê-se através disto?" — que são exactamente as perguntas
que estavam por responder.

Uso:
    SHOT_OUT=/tmp/shot.bin node shot.mjs /home/user/Blessed --quit-after 3000 -- shot
    venv/bin/python tools/render_shot.py /tmp/shot.bin -o /tmp/shot.png
    venv/bin/python tools/render_shot.py /tmp/shot.bin --audit     # só o relatório
"""
from __future__ import annotations

import argparse
import math
import struct
import sys

import numpy as np

# ── parâmetros dos materiais, lidos de scripts/world/materials.gd ────────────
# Manter estes valores sincronizados com o GDScript é parte do contrato: se um
# mudar lá, muda aqui, ou o PNG deixa de representar o jogo.
MATERIALS = {
    "toon_terrain.gdshader": dict(
        shadow_tint=(0.55, 0.58, 0.88), bands=3.0, band_soft=0.18,
        rim_strength=0.28, rim_power=3.0, light_gain=1.05, ambient_gain=0.85,
        slope_dim=0.10, kind="toon"),
    "toon_foliage.gdshader": dict(
        shadow_tint=(0.52, 0.56, 0.88), bands=3.0, band_soft=0.12,
        rim_strength=0.40, rim_power=2.5, light_gain=1.10, ambient_gain=0.90,
        slope_dim=0.0, kind="toon"),
    "stylized_water.gdshader": dict(kind="water"),
    "anime_sky.gdshader": dict(kind="sky"),
}
DEFAULT_MAT = dict(
    shadow_tint=(0.5, 0.5, 0.5), bands=3.0, band_soft=0.18, rim_strength=0.0,
    rim_power=3.0, light_gain=1.0, ambient_gain=0.85, slope_dim=0.0, kind="default")


class Reader:
    def __init__(self, data: bytes):
        self.d = data
        self.p = 0

    def u8(self) -> int:
        v = self.d[self.p]
        self.p += 1
        return v

    def u32(self) -> int:
        v = struct.unpack_from("<I", self.d, self.p)[0]
        self.p += 4
        return v

    def f32(self) -> float:
        v = struct.unpack_from("<f", self.d, self.p)[0]
        self.p += 4
        return v

    def vec(self, n: int = 3):
        out = tuple(self.f32() for _ in range(n))
        return np.array(out, dtype=np.float64)

    def s(self) -> str:
        """String com prefixo u32 (usada só no magic)."""
        n = self.u32()
        v = self.d[self.p:self.p + n].decode("utf-8", "replace")
        self.p += n
        return v

    def fixed(self, n: int) -> str:
        """Campo de tamanho fixo, terminado em NUL — mantém tudo alinhado a 4."""
        raw = self.d[self.p:self.p + n]
        self.p += n
        return raw.split(b"\x00")[0].decode("utf-8", "replace")


def load(path: str):
    data = open(path, "rb").read()
    if not data.startswith(b"BSH1"):
        import gzip
        data = gzip.decompress(data)   # tests/shot.gd comprime o dump
    r = Reader(data)
    if data[:4] != b"BSH1":          # o magic é escrito sem prefixo de tamanho
        sys.exit("não é um dump BSH1")
    r.p = 4
    r.u32()
    hdr = dict(
        eye=r.vec(), right=r.vec(), up=r.vec(), back=r.vec(),
        fov=r.f32(), aspect=r.f32(), near=r.f32(), far=r.f32(),
        sun_dir=r.vec(), sun_color=r.vec(), sky_top=r.vec(), sky_bot=r.vec(),
        exposure=r.f32())
    meshes = []
    for _ in range(r.u32()):
        name = r.fixed(32)
        mat = r.fixed(32)
        cull = r.u32()
        # 12 floats na ordem: basis.x, basis.y, basis.z, origin (cada um com 3).
        # reshape(4,3) da uma linha por vector; reshape(3,4) misturava a origem
        # com a base e punha origin.x dentro da matriz — foi medido: a agua
        # saia com y = origin.x * x_local, ou seja +-84000.
        t = np.array([r.f32() for _ in range(12)], dtype=np.float64).reshape(4, 3)
        nv = r.u32()
        buf = np.array([r.f32() for _ in range(nv * 9)], dtype=np.float64).reshape(nv, 9)
        ni = r.u32()
        idx = np.array([r.u32() for _ in range(ni)], dtype=np.uint32)
        # basis está em colunas (Godot): world = basis @ local + origin
        basis = t[:3, :3].T.copy()   # as linhas lidas SAO as colunas da base
        origin = t[3, :3].copy()
        pos = buf[:, 0:3] @ basis.T + origin
        nrm = buf[:, 3:6] @ basis.T
        ln = np.linalg.norm(nrm, axis=1, keepdims=True)
        nrm = np.where(ln > 1e-9, nrm / np.maximum(ln, 1e-9), nrm)
        meshes.append(dict(name=name, mat=mat, cull=cull, pos=pos, nrm=nrm,
                           col=buf[:, 6:9], idx=idx))
    return hdr, meshes


# ── shading: transcrição dos .gdshader ───────────────────────────────────────
def shade_toon(albedo, nrm, view, p, L, sun_col, sky_bot, m):
    """light() do toon_terrain/toon_foliage, por vértice."""
    ndl = np.einsum("ij,j->i", nrm, L)
    lit = ndl * 0.5 + 0.5
    band = np.floor(lit * m["bands"]) / m["bands"]
    band = band * (1.0 - m["band_soft"]) + lit * m["band_soft"]

    if m["slope_dim"] > 0.0:
        slope = np.clip(1.0 - nrm[:, 1], 0.0, 1.0)
        albedo = albedo * (1.0 - m["slope_dim"] * slope)[:, None]

    base = albedo * m["light_gain"]
    st = np.array(m["shadow_tint"])
    k = np.clip(band * 1.12, 0.0, 1.0)[:, None]
    col = base * st * (1.0 - k) + base * k

    ndv = np.clip(np.einsum("ij,ij->i", nrm, view), 0.0, 1.0)
    rim = np.power(1.0 - ndv, m["rim_power"])
    mult = band if m["kind"] == "toon" and m["slope_dim"] > 0 else (0.4 + band)
    col += sun_col * (rim * m["rim_strength"] * mult)[:, None]

    col = col * sun_col * m["ambient_gain"]
    # ambiente do céu (no motor vem do ambient do WorldEnvironment)
    col += albedo * sky_bot * 0.12 * m["ambient_gain"]
    return np.clip(col, 0.0, 1.0)


def shade_water(pos, nrm, view, L, sun_col, m):
    """stylized_water.gdshader — bandas duras + crista de espuma."""
    deep = np.array([0.10, 0.36, 0.52])
    shallow = np.array([0.34, 0.78, 0.82])
    foam = np.array([0.94, 0.98, 1.00])
    sky_tint = np.array([0.62, 0.82, 1.00])
    x, z = pos[:, 0], pos[:, 2]
    w = np.sin(x * 0.35 + 1.7) * 0.5 + np.sin(z * 0.35 * 1.37 - 1.4) * 0.5
    w = w * 0.5 + 0.5
    band = np.floor(w * 4.0) / 4.0
    col = shallow * (1.0 - band)[:, None] + deep * band[:, None]
    col = col * (1.0 - 0.5 * (w > 0.75)[:, None]) + (col * 1.22 + 0.05) * (0.5 * (w > 0.75))[:, None]
    col = col * (1.0 - 0.7 * (w > 0.93)[:, None]) + foam * (0.7 * (w > 0.93))[:, None]
    glow = np.power(np.clip(np.einsum("ij,ij->i",
                                      2.0 * nrm * np.einsum("ij,j->i", nrm, -view)[:, None] + view,
                                      L), 0.0, 1.0), 18.0)
    col += sky_tint * (glow * 0.6)[:, None]
    return np.clip(col, 0.0, 1.0)


# ── rasterizador ─────────────────────────────────────────────────────────────
def render(hdr, meshes, W=640, H=360):
    eye = hdr["eye"]
    right, up, back = hdr["right"], hdr["up"], hdr["back"]
    fwd = -back
    tan_h = math.tan(math.radians(hdr["fov"]) * 0.5)
    tan_w = tan_h * hdr["aspect"]
    near = hdr["near"]

    # L = direcção PARA o sol; Game.sun_direction() devolve a de viagem
    L = -hdr["sun_dir"]
    if np.linalg.norm(L) < 1e-6:
        L = np.array([0.0, 1.0, 0.0])
    L = L / np.linalg.norm(L)
    sun_col = hdr["sun_color"]
    sky_top, sky_bot = hdr["sky_top"], hdr["sky_bot"]

    fb = np.zeros((H, W, 3), dtype=np.float64)
    zb = np.full((H, W), np.inf, dtype=np.float64)

    # céu: gradiente vertical ao longo do raio de visão
    ys = (0.5 - (np.arange(H)[:, None] + 0.5) / H) * 2.0
    xs = ((np.arange(W)[None, :] + 0.5) / W) * 2.0 - 1.0
    dx = np.broadcast_to(xs * tan_w, (H, W))   # xs ja e (1,W)
    dy = np.broadcast_to(ys * tan_h, (H, W))   # ys ja e (H,1)
    rays = (right[:, None, None] * dx[None]
            + up[:, None, None] * dy[None]
            + fwd[:, None, None] * np.ones((1, H, W)))
    assert rays.shape == (3, H, W), rays.shape
    rays = rays / np.linalg.norm(rays, axis=0, keepdims=True)
    t = np.clip(rays[1] * 0.5 + 0.5, 0.0, 1.0) ** 0.7
    fb = sky_bot[None, None, :] * (1 - t)[:, :, None] + sky_top[None, None, :] * t[:, :, None]

    n_tri_total = 0
    n_tri_drawn = 0
    n_tri_culled = 0
    for m_ in meshes:
        mat = MATERIALS.get(m_["mat"], DEFAULT_MAT)
        if mat["kind"] == "sky":
            continue  # o céu é pintado pelo gradiente acima
        P = m_["pos"]
        N = m_["nrm"]
        C = m_["col"]
        I = m_["idx"]
        if I.size < 3:
            continue
        I = I[: (I.size // 3) * 3].reshape(-1, 3)
        a, b, c = P[I[:, 0]], P[I[:, 1]], P[I[:, 2]]
        n_tri_total += I.shape[0]

        # backface culling pela winding no espaço do mundo (o que a GPU faz)
        geo = np.cross(b - a, c - a)
        facing = np.einsum("ij,ij->i", geo, eye - a)
        keep = facing > 0 if m_["cull"] == 0 else np.ones(I.shape[0], bool)
        if not keep.any():
            n_tri_culled += I.shape[0]
            continue
        n_tri_culled += int((~keep).sum())

        # espaço da câmara: profundidade = projecção em FWD (positiva à frente)
        def to_cam(Q):
            d = Q - eye
            return np.stack([d @ right, d @ up, d @ fwd], axis=1)

        ca, cb, cc = to_cam(a), to_cam(b), to_cam(c)
        zmin = np.minimum(np.minimum(ca[:, 2], cb[:, 2]), cc[:, 2])
        keep &= zmin > near
        if not keep.any():
            continue
        ca, cb, cc = ca[keep], cb[keep], cc[keep]
        a, b, c = a[keep], b[keep], c[keep]

        # shading por vértice (Gouraud) — mesma função dos shaders
        na, nb, nc = N[I[keep, 0]], N[I[keep, 1]], N[I[keep, 2]]
        ca_, cb_, cc_ = C[I[keep, 0]], C[I[keep, 1]], C[I[keep, 2]]
        if mat["kind"] == "water":
            sa = shade_water(a, na, -fwd, L, sun_col, mat)
            sb = shade_water(b, nb, -fwd, L, sun_col, mat)
            sc = shade_water(c, nc, -fwd, L, sun_col, mat)
        else:
            va = (eye - a); va /= np.maximum(np.linalg.norm(va, axis=1, keepdims=True), 1e-9)
            vb = (eye - b); vb /= np.maximum(np.linalg.norm(vb, axis=1, keepdims=True), 1e-9)
            vc = (eye - c); vc /= np.maximum(np.linalg.norm(vc, axis=1, keepdims=True), 1e-9)
            sa = shade_toon(ca_, na, va, a, L, sun_col, sky_bot, mat)
            sb = shade_toon(cb_, nb, vb, b, L, sun_col, sky_bot, mat)
            sc = shade_toon(cc_, nc, vc, c, L, sun_col, sky_bot, mat)

        # projecção
        def proj(cm):
            sx = (cm[:, 0] / cm[:, 2]) / tan_w
            sy = (cm[:, 1] / cm[:, 2]) / tan_h
            return (sx * 0.5 + 0.5) * W, (0.5 - sy * 0.5) * H

        pax, pay = proj(ca); pbx, pby = proj(cb); pcx, pcy = proj(cc)
        minx = np.floor(np.minimum(np.minimum(pax, pbx), pcx)).astype(int)
        maxx = np.ceil(np.maximum(np.maximum(pax, pbx), pcx)).astype(int)
        miny = np.floor(np.minimum(np.minimum(pay, pby), pcy)).astype(int)
        maxy = np.ceil(np.maximum(np.maximum(pay, pby), pcy)).astype(int)
        np.clip(minx, 0, W - 1, out=minx); np.clip(maxx, 0, W - 1, out=maxx)
        np.clip(miny, 0, H - 1, out=miny); np.clip(maxy, 0, H - 1, out=maxy)
        # triângulos maiores que o ecrã: desenhar por faixas (raro, mas acontece
        # com o plano da água ao perto)
        area = np.abs((pbx - pax) * (pcy - pay) - (pcx - pax) * (pby - pay)) * 0.5
        order = np.argsort(-area)
        for ti in order:
            x0, x1 = int(minx[ti]), int(maxx[ti])
            y0, y1 = int(miny[ti]), int(maxy[ti])
            if x1 < x0 or y1 < y0:
                continue
            gw, gh = x1 - x0 + 1, y1 - y0 + 1
            if gw * gh > 4_000_000:
                continue
            gx = np.arange(x0, x1 + 1) + 0.5
            gy = np.arange(y0, y1 + 1) + 0.5
            PX, PY = np.meshgrid(gx, gy)
            d = (pby[ti] - pcy[ti]) * (pax[ti] - pcx[ti]) + (pcx[ti] - pbx[ti]) * (pay[ti] - pcy[ti])
            if abs(d) < 1e-9:
                continue
            w0 = ((pby[ti] - pcy[ti]) * (PX - pcx[ti]) + (pcx[ti] - pbx[ti]) * (PY - pcy[ti])) / d
            w1 = ((pcy[ti] - pay[ti]) * (PX - pcx[ti]) + (pax[ti] - pcx[ti]) * (PY - pcy[ti])) / d
            w2 = 1.0 - w0 - w1
            mask = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
            if not mask.any():
                continue
            zz = w0 * ca[ti, 2] + w1 * cb[ti, 2] + w2 * cc[ti, 2]
            sub = zb[y0:y1 + 1, x0:x1 + 1]
            hit = mask & (zz < sub)
            if not hit.any():
                continue
            n_tri_drawn += 1
            ys_, xs_ = np.nonzero(hit)
            col = (w0[hit][:, None] * sa[ti] + w1[hit][:, None] * sb[ti]
                   + w2[hit][:, None] * sc[ti])
            fb[y0 + ys_, x0 + xs_] = col
            zb[y0 + ys_, x0 + xs_] = zz[hit]

    return np.clip(fb, 0.0, 1.0), dict(tris=n_tri_total, drawn=n_tri_drawn,
                                      culled=n_tri_culled, meshes=len(meshes))


def audit(hdr, meshes):
    """Relatório de contrato: o que a geometria e os materiais realmente são."""
    print("── AUDITORIA DE RENDERIZAÇÃO ─────────────────────────────────")
    print("câmara   (%.1f, %.1f, %.1f)  sol→(%.2f, %.2f, %.2f)"
          % (*hdr["eye"], *(-hdr["sun_dir"])))
    print("malhas   %d" % len(meshes))
    by_mat = {}
    for m in meshes:
        by_mat.setdefault(m["mat"], []).append(m)
    for mat, ms in sorted(by_mat.items()):
        v = sum(m["pos"].shape[0] for m in ms)
        t = sum(m["idx"].size // 3 for m in ms)
        cols = np.concatenate([m["col"] for m in ms if m["col"].size]) if any(m["col"].size for m in ms) else np.zeros((1, 3))
        allp = np.concatenate([m["pos"] for m in ms])
        bb = (allp.min(0), allp.max(0))
        print("  %-26s malhas=%-3d verts=%-7d tris=%-7d cor[%.2f..%.2f] y[%.1f..%.1f]"
              % (mat, len(ms), v, t, cols.min(), cols.max(), bb[0][1], bb[1][1]))
        nomes = ", ".join(sorted({m["name"] for m in ms})[:6])
        print("      nomes: %s" % nomes)
        if cols.min() == cols.max() == 0.0:
            print("      !! COR DE VÉRTICE TODA PRETA — desenha a preto")
    # normais degeneradas / winding incoerente
    print("── verificações ──────────────────────────────────────────────")
    bad_n = bad_w = 0
    for m in meshes:
        if m["idx"].size < 3:
            continue
        I = m["idx"][: (m["idx"].size // 3) * 3].reshape(-1, 3)
        P = m["pos"]
        geo = np.cross(P[I[:, 1]] - P[I[:, 0]], P[I[:, 2]] - P[I[:, 0]])
        g = np.linalg.norm(geo, axis=1)
        bad_n += int((g < 1e-9).sum())
        vn = m["nrm"][I[:, 0]] + m["nrm"][I[:, 1]] + m["nrm"][I[:, 2]]
        bad_w += int((np.einsum("ij,ij->i", geo, vn) < 0).sum())
    print("  triângulos degenerados ............ %d" % bad_n)
    print("  winding != normal do vertice ...... %d  <-- se >0, a face aponta"
          % bad_w)
    print("                                        para o lado errado do shading")
    sem_cor = [m["name"] for m in meshes if m["col"].size == 0]
    print("  malhas SEM cor de vértice ......... %d %s" % (len(sem_cor), sem_cor[:6]))
    print("  malhas com cull_disabled .......... %d"
          % sum(1 for m in meshes if m["cull"] == 1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("-o", "--out", default="shot.png")
    ap.add_argument("--width", type=int, default=640)
    ap.add_argument("--height", type=int, default=360)
    ap.add_argument("--audit", action="store_true")
    ap.add_argument("--no-png", action="store_true")
    a = ap.parse_args()

    hdr, meshes = load(a.dump)
    if a.audit:
        audit(hdr, meshes)
    if a.no_png:
        return
    fb, st = render(hdr, meshes, a.width, a.height)
    from PIL import Image
    img = (np.power(fb, 1.0 / 2.2) * 255).astype(np.uint8)
    Image.fromarray(img).save(a.out)
    print("── RENDER ────────────────────────────────────────────────────")
    print("  malhas=%d  triângulos=%d  desenhados=%d  cullados=%d"
          % (st["meshes"], st["tris"], st["drawn"], st["culled"]))
    print("  -> %s (%dx%d)" % (a.out, a.width, a.height))


if __name__ == "__main__":
    main()
