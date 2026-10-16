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
import os
import struct
import sys

import numpy as np

# ── parâmetros dos materiais ─────────────────────────────────────────────────
# Já não são copiados à mão: tests/shot.gd escreve no dump os uniforms reais de
# cada material (nome, tipo e valor) e o caminho de cada textura. Esta tabela só
# serve de reserva para malhas sem material (ou de versões antigas do dump).
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


def load_texture(path: str):
    """PNG do projeto → array (H, W, 3) em 0..1. É a máscara da relva: o
    rasterizador avalia o MESMO campo que o shader avalia."""
    if not path:
        return None
    rel = path.replace("res://", "")
    disk = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), rel)
    if not os.path.isfile(disk):
        return None
    from PIL import Image
    img = Image.open(disk).convert("RGB")
    return np.asarray(img, dtype=np.float64) / 255.0


_TEXTURES: dict = {}


def texture(path: str):
    if path not in _TEXTURES:
        _TEXTURES[path] = load_texture(path)
    return _TEXTURES[path]


def sample_bilinear(tex, u, v):
    """Amostragem com repetição nos dois eixos, aceitando arrays de uv."""
    h, w = tex.shape[0], tex.shape[1]
    x = np.mod(u * w - 0.5, w)
    y = np.mod(v * h - 0.5, h)
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    x1 = (x0 + 1) % w
    y1 = (y0 + 1) % h
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]
    a = tex[y0, x0] * (1 - fx) + tex[y0, x1] * fx
    b = tex[y1, x0] * (1 - fx) + tex[y1, x1] * fx
    return a * (1 - fy) + b * fy


def sample_clamped(tex, u, v):
    h, w = tex.shape[0], tex.shape[1]
    x = np.clip(u * w - 0.5, 0, w - 1)
    y = np.clip(v * h - 0.5, 0, h - 1)
    x0 = np.floor(x).astype(np.int64)
    y0 = np.floor(y).astype(np.int64)
    x1 = np.minimum(x0 + 1, w - 1)
    y1 = np.minimum(y0 + 1, h - 1)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]
    a = tex[y0, x0] * (1 - fx) + tex[y0, x1] * fx
    b = tex[y1, x0] * (1 - fx) + tex[y1, x1] * fx
    return a * (1 - fy) + b * fy


def load(path: str):
    data = open(path, "rb").read()
    if not data.startswith(b"BSH1"):
        import gzip
        data = gzip.decompress(data)   # tests/shot.gd comprime o dump
    r = Reader(data)
    if data[:4] != b"BSH1":          # o magic é escrito sem prefixo de tamanho
        sys.exit("não é um dump BSH1")
    r.p = 4
    version = r.u32()
    hdr = dict(
        eye=r.vec(), right=r.vec(), up=r.vec(), back=r.vec(),
        fov=r.f32(), aspect=r.f32(), near=r.f32(), far=r.f32(),
        sun_dir=r.vec(), sun_color=r.vec(), sky_top=r.vec(), sky_bot=r.vec(),
        exposure=r.f32())
    hdr["version"] = version
    meshes = []
    for _ in range(r.u32()):
        name = r.fixed(32)
        mat = r.fixed(32)
        cull = r.u32()
        params = {}
        if version >= 2:
            for _ in range(r.u32()):
                pname = r.fixed(32)
                kind = r.u8()
                values = tuple(r.f32() for _ in range(4))
                text = r.fixed(64) if kind == 5 else ""
                params[pname] = (kind, values, text)
        # 12 floats na ordem: basis.x, basis.y, basis.z, origin (cada um com 3).
        # reshape(4,3) da uma linha por vector; reshape(3,4) misturava a origem
        # com a base e punha origin.x dentro da matriz — foi medido: a agua
        # saia com y = origin.x * x_local, ou seja +-84000.
        t = np.array([r.f32() for _ in range(12)], dtype=np.float64).reshape(4, 3)
        nv = r.u32()
        stride = 13 if version >= 2 else 9
        buf = np.array([r.f32() for _ in range(nv * stride)],
                       dtype=np.float64).reshape(nv, stride)
        ni = r.u32()
        idx = np.array([r.u32() for _ in range(ni)], dtype=np.uint32)
        # basis está em colunas (Godot): world = basis @ local + origin
        basis = t[:3, :3].T.copy()   # as linhas lidas SAO as colunas da base
        origin = t[3, :3].copy()
        pos = buf[:, 0:3] @ basis.T + origin
        nrm = buf[:, 3:6] @ basis.T
        ln = np.linalg.norm(nrm, axis=1, keepdims=True)
        nrm = np.where(ln > 1e-9, nrm / np.maximum(ln, 1e-9), nrm)
        meshes.append(dict(
            name=name, mat=mat, cull=cull, pos=pos, nrm=nrm, col=buf[:, 6:9],
            uv=(buf[:, 9:11] if version >= 2 else np.zeros((nv, 2))),
            uv2=(buf[:, 11:13] if version >= 2 else np.zeros((nv, 2))),
            params=params, idx=idx))
    return hdr, meshes


def pval(params: dict, name: str, fallback):
    """Valor de um parâmetro do material, com reserva se o dump não o trouxer."""
    entry = params.get(name)
    if entry is None:
        return fallback
    kind, values, _ = entry
    if kind == 0 or kind == 4:
        return values[0]
    if kind == 1:
        return np.array(values[:2])
    if kind == 2:
        return np.array(values[:3])
    if kind == 3:
        return np.array(values[:4])
    return fallback


def ptex(params: dict, name: str):
    entry = params.get(name)
    if entry is None or entry[0] != 5:
        return None
    return texture(entry[2])


# ── shading: transcrição dos .gdshader ───────────────────────────────────────
def soil_blend(a, uv, idx, eye, params):
    """Peso de TERRA no chão: 1 junto ao jogador, 0 ao longe (toon_terrain)."""
    near = float(pval(params, "soil_near", 40.0))
    far = float(pval(params, "soil_far", 96.0))
    strength = float(pval(params, "soil_strength", 0.78))
    dist = np.linalg.norm(a - eye[None, :], axis=1)
    t = np.clip((dist - near) / max(far - near, 1e-4), 0.0, 1.0)
    t = t * t * (3.0 - 2.0 * t)
    grass_weight = np.clip(uv[idx, 0] if uv.shape[1] > 0 else np.zeros_like(dist), 0.0, 1.0)
    return (strength * (1.0 - t) * np.clip(grass_weight, 0.0, 1.0))


SOIL_COLOR = np.array([0.30, 0.21, 0.14])


def shade_toon(albedo, nrm, view, p, L, sun_col, sky_bot, m, soil=None):
    """light() do toon_terrain/toon_foliage, por vértice."""
    ndl = np.einsum("ij,j->i", nrm, L)
    lit = ndl * 0.5 + 0.5
    band = np.floor(lit * m["bands"]) / m["bands"]
    band = band * (1.0 - m["band_soft"]) + lit * m["band_soft"]

    if soil is not None:
        # o chão por baixo da relva: terra misturada com o verde do bioma
        dirt = SOIL_COLOR[None, :] * 0.58 + albedo * np.array([0.66, 0.52, 0.40]) * 0.42
        albedo = albedo * (1.0 - soil)[:, None] + dirt * soil[:, None]

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


def grass_shell_pixels(wpos, normal, tint, shell, cover, dryness, eye, params, L,
                       sun_col, sky_bot):
    """grass_shells.gdshader, pixel a pixel.

    Devolve (cores, visivel). `visivel` é falso onde o shader faz `discard` —
    exatamente a mesma decisão: campo de alturas, densidade e desvanecimento de
    distância. Sem avaliar a máscara, o rasterizador só conseguia desenhar placas
    horizontais empilhadas, que é justamente o erro que se está a tentar ver.
    """
    n = wpos.shape[0]
    mask_tex = ptex(params, "grass_mask")
    streak_tex = ptex(params, "grass_streak")
    if mask_tex is None:
        return np.zeros((n, 3)), np.zeros(n, bool)

    scale = max(float(pval(params, "mask_scale", 0.36)), 1e-4)
    grow = float(pval(params, "grow", 1.0))
    gain = float(pval(params, "coverage_gain", 1.0))
    dens_min = float(pval(params, "density_min", 0.30))
    dens_near = float(pval(params, "density_near", 34.0))
    dens_far = float(pval(params, "density_far", 110.0))
    size_far = float(pval(params, "size_far", 96.0))
    bands = float(pval(params, "bands", 3.0))
    band_soft = float(pval(params, "band_soft", 0.46))
    rim_strength = float(pval(params, "rim_strength", 0.30))
    ambient_gain = float(pval(params, "ambient_gain", 0.78))
    light_gain = float(pval(params, "light_gain", 0.95))
    shadow_tint = np.array(pval(params, "shadow_tint", (0.48, 0.52, 0.86, 1.0))[:3])

    dist = np.linalg.norm(wpos - eye, axis=1)
    far_fade = np.clip((dist - size_far) / 34.0, 0.0, 1.0)
    far_fade = 1.0 - far_fade * far_fade * (3.0 - 2.0 * far_fade)
    visible = far_fade > 0.002

    mask = sample_bilinear(mask_tex, wpos[:, 0] / scale, wpos[:, 2] / scale)
    blade_height = mask[:, 0] * grow
    visible &= shell <= blade_height

    ss = np.clip((dist - dens_near) / max(dens_far - dens_near, 1e-4), 0.0, 1.0)
    ss = ss * ss * (3.0 - 2.0 * ss)
    thinning = 1.0 + (dens_min - 1.0) * ss
    cov = np.clip(cover * gain * far_fade, 0.0, 1.0)
    keep = cov * thinning * (0.45 + 0.95 * mask[:, 2])
    visible &= ~(mask[:, 1] > keep)

    if streak_tex is not None:
        uv = (wpos[:, 0] / (scale * 3.1), wpos[:, 2] / (scale * 3.1))
        streak = sample_bilinear(streak_tex, uv[0], uv[1])
    else:
        streak = np.full((n, 3), 0.5)

    vertical = np.clip(shell / np.maximum(blade_height, 1e-3), 0.0, 1.0)
    tone = np.clip(mask[:, 1] * 0.55 + streak[:, 1] * 0.45, 0.0, 1.0)
    dry = np.clip(dryness + (streak[:, 2] - 0.5) * 0.55, 0.0, 1.0)
    # A cor da lâmina é a cor da relva do bioma (tinta do vértice) com a rampa
    # base-escura -> ponta-clara por cima, igual ao grass_shells.gdshader.
    color = tint * (0.58 + 0.64 * vertical)[:, None]
    color = color * (0.88 + 0.22 * tone)[:, None]
    color = color * ((1.0 - dry)[:, None]
                     + np.array([1.16, 1.02, 0.72])[None, :] * dry[:, None])

    ndl = np.einsum("ij,j->i", normal, L)
    lit = ndl * 0.5 + 0.5
    band = np.floor(lit * bands) / bands
    band = band * (1.0 - band_soft) + lit * band_soft
    base = color * light_gain
    k = np.clip(band * 1.08, 0.0, 1.0)[:, None]
    col = base * shadow_tint * (1.0 - k) + base * k
    view = eye[None, :] - wpos
    view = view / np.maximum(np.linalg.norm(view, axis=1, keepdims=True), 1e-9)
    rim = np.power(1.0 - np.clip(np.einsum("ij,ij->i", normal, view), 0.0, 1.0), 2.6)
    col = col + sun_col * (rim * rim_strength * band)[:, None]
    col = col * sun_col * ambient_gain
    col = col + color * sky_bot * 0.12 * ambient_gain
    return np.clip(col, 0.0, 1.0), visible


def grass_card_pixels(wpos, normal, uv, vcol, inst, eye, params, L, sun_col, sky_bot):
    """grass_cards.gdshader, pixel a pixel.

    Os cartões são a malha próxima: aqui a máscara decide *onde nasce tufo* e a
    altura do vértice inclina a normal para cima, como no shader. Sem isto o
    rasterizador desenhava quadrados verdes por cima de tudo.
    """
    n = wpos.shape[0]
    mask_tex = ptex(params, "grass_mask")
    streak_tex = ptex(params, "grass_streak")
    if mask_tex is None:
        return np.zeros((n, 3)), np.zeros(n, bool)

    scale = max(float(pval(params, "mask_scale", 0.36)), 1e-4)
    mask_min = float(pval(params, "mask_min", 0.16))
    blade_height = max(float(pval(params, "blade_height", 0.72)), 1e-3)
    fade_begin = float(pval(params, "fade_begin", 46.0))
    fade_end = float(pval(params, "fade_end", 74.0))
    grow = float(pval(params, "grow", 1.0))
    bands = float(pval(params, "bands", 3.0))
    band_soft = float(pval(params, "band_soft", 0.48))
    rim_strength = float(pval(params, "rim_strength", 0.34))
    ambient_gain = float(pval(params, "ambient_gain", 0.78))
    light_gain = float(pval(params, "light_gain", 0.95))
    shadow_tint = np.array(pval(params, "shadow_tint", (0.45, 0.50, 0.82, 1.0))[:3])

    dist = np.linalg.norm(wpos - eye, axis=1)
    t = np.clip((dist - fade_begin) / max(fade_end - fade_begin, 1e-4), 0.0, 1.0)
    v_fade = 1.0 - t * t * (3.0 - 2.0 * t)
    visible = v_fade > 0.002

    mask = sample_bilinear(mask_tex, wpos[:, 0] / scale, wpos[:, 2] / scale)
    variation = inst[:, 0]
    dryness_i = inst[:, 1]
    patch = np.clip(mask[:, 2] * 1.25, 0.0, 1.0)
    visible &= ~(patch * (0.35 + 0.75 * variation) < mask_min)

    if streak_tex is not None:
        streak = sample_bilinear(streak_tex, wpos[:, 0] / (scale * 3.1),
                                 wpos[:, 2] / (scale * 3.1))
    else:
        streak = np.full((n, 3), 0.5)

    # UV.y do cartão vai de 1 na base a 0 na ponta: é a altura local
    height = np.clip(1.0 - uv[:, 1], 0.0, 1.0) * np.clip(grow, 0.35, 1.0)
    height = np.clip(height, 0.0, 1.0)
    dryness = np.clip(dryness_i * 0.72 + (streak[:, 2] - 0.5) * 0.5, 0.0, 1.0)
    tone = np.clip(mask[:, 1] * 0.5 + streak[:, 1] * 0.5, 0.0, 1.0)
    # v_color = rampa da malha x cor da relva do bioma (grass_cards.gdshader).
    color = vcol * (0.62 + 0.54 * height)[:, None]
    color = color * (0.88 + 0.24 * tone)[:, None]
    color = color * ((1.0 - dryness)[:, None]
                     + np.array([1.16, 1.02, 0.72])[None, :] * dryness[:, None])
    color = color * (0.94 + 0.12 * variation)[:, None]
    del blade_height

    # a normal da lâmina inclina-se para cima e é corrigida nas costas
    nrm = normal * (1.0 - height)[:, None] + np.array([0.0, 1.0, 0.0]) * height[:, None]
    nrm = nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    facing = np.einsum("ij,ij->i", nrm, eye[None, :] - wpos) > 0.0
    nrm = np.where(facing[:, None], nrm, -nrm)

    ndl = np.einsum("ij,j->i", nrm, L)
    lit = ndl * 0.5 + 0.5
    band = np.floor(lit * bands) / bands
    band = band * (1.0 - band_soft) + lit * band_soft
    base = color * light_gain
    k = np.clip(band * 1.08, 0.0, 1.0)[:, None]
    col = base * shadow_tint * (1.0 - k) + base * k
    view = eye[None, :] - wpos
    view = view / np.maximum(np.linalg.norm(view, axis=1, keepdims=True), 1e-9)
    ndv = np.clip(np.einsum("ij,ij->i", nrm, view), 0.0, 1.0)
    rim = np.power(1.0 - ndv, 2.4)
    col = col + sun_col * (rim * rim_strength * band * height)[:, None]
    col = col * sun_col * ambient_gain
    col = col + color * sky_bot * 0.12 * ambient_gain
    return np.clip(col, 0.0, 1.0), visible


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
        mat_key = os.path.basename(m_["mat"])
        params = m_.get("params", {})
        pixel_kind = ("shells" if mat_key == "grass_shells.gdshader"
                      else "cards" if mat_key == "grass_cards.gdshader" else "")
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

        # backface culling pela winding no espaço do mundo (o que a GPU faz).
        # O Godot considera FRONTAL a winding HORÁRIA (é a convenção do Godot, ao
        # contrário do CCW do OpenGL puro): com `> 0` este rasterizador punha fora
        # TODAS as faces do terreno e das árvores e depois desenhava-as pelas
        # costas. Medido: 178.469 de 235.000 triângulos marcados ao contrário.
        geo = np.cross(b - a, c - a)
        facing = np.einsum("ij,ij->i", geo, eye - a)
        keep = facing < 0 if m_["cull"] == 0 else np.ones(I.shape[0], bool)
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
        pix_channels = None
        if pixel_kind:
            # Interpolação por pixel (as duas malhas de relva decidem máscara,
            # cor e normal em cada fragmento, não no vértice).
            def trip(arr, comp=None):
                if comp is None:
                    cols_ = [arr[I[keep, k]] for k in range(3)]
                else:
                    cols_ = [arr[I[keep, k], comp] for k in range(3)]
                return cols_
            if pixel_kind == "shells":
                pix_channels = dict(shell=trip(m_["uv2"], 0),
                                    cover=trip(m_["uv"], 0),
                                    dry=trip(m_["uv"], 1),
                                    tint=trip(m_["col"]))
            else:
                pix_channels = dict(uv=trip(m_["uv"]), vcol=trip(m_["col"]),
                                    instg=trip(m_["uv2"], 0),
                                    instr=trip(m_["uv2"], 1))
            sa = sb = sc = None
            va = vb = vc = None
        elif mat["kind"] == "water":
            sa = shade_water(a, na, -fwd, L, sun_col, mat)
            sb = shade_water(b, nb, -fwd, L, sun_col, mat)
            sc = shade_water(c, nc, -fwd, L, sun_col, mat)
        else:
            va = (eye - a); va /= np.maximum(np.linalg.norm(va, axis=1, keepdims=True), 1e-9)
            vb = (eye - b); vb /= np.maximum(np.linalg.norm(vb, axis=1, keepdims=True), 1e-9)
            vc = (eye - c); vc /= np.maximum(np.linalg.norm(vc, axis=1, keepdims=True), 1e-9)
            soil = None
            if mat_key == "toon_terrain.gdshader":
                # UV.x é o peso da classe "relva": de perto o chão é TERRA, ao
                # longe continua o verde do bioma (a relva não chega ao horizonte).
                soil = soil_blend(a, m_["uv"], I[keep, 0], eye, params)
            sa = shade_toon(ca_, na, va, a, L, sun_col, sky_bot, mat, soil)
            sb = shade_toon(cb_, nb, vb, b, L, sun_col, sky_bot, mat, soil)
            sc = shade_toon(cc_, nc, vc, c, L, sun_col, sky_bot, mat, soil)

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
            ys_, xs_ = np.nonzero(hit)
            if pix_channels is not None:
                w0h = w0[hit][:, None]
                w1h = w1[hit][:, None]
                w2h = w2[hit][:, None]
                pw = a[ti] * w0h + b[ti] * w1h + c[ti] * w2h
                nw = na[ti] * w0h + nb[ti] * w1h + nc[ti] * w2h
                nw = nw / np.maximum(np.linalg.norm(nw, axis=1, keepdims=True), 1e-9)
                vals = {}
                for key, (ca_, cb_, cc_) in pix_channels.items():
                    vals[key] = ca_[ti] * w0h + cb_[ti] * w1h + cc_[ti] * w2h
                if pixel_kind == "shells":
                    cols, visible = grass_shell_pixels(
                        pw, nw, vals["tint"], vals["shell"][:, 0],
                        vals["cover"][:, 0], vals["dry"][:, 0], eye, params, L,
                        sun_col, sky_bot)
                else:
                    cols, visible = grass_card_pixels(
                        pw, nw, vals["uv"], vals["vcol"],
                        np.concatenate([vals["instg"], vals["instr"]], axis=1),
                        eye, params, L, sun_col, sky_bot)
                live = np.nonzero(visible)[0]
                if live.size == 0:
                    continue
                n_tri_drawn += 1
                fb[y0 + ys_[live], x0 + xs_[live]] = cols[live]
                zb[y0 + ys_[live], x0 + xs_[live]] = zz[hit][live]
                continue
            n_tri_drawn += 1
            col = (w0[hit][:, None] * sa[ti] + w1[hit][:, None] * sb[ti]
                   + w2[hit][:, None] * sc[ti])
            fb[y0 + ys_, x0 + xs_] = col
            zb[y0 + ys_, x0 + xs_] = zz[hit]

    return np.clip(fb, 0.0, 1.0), dict(tris=n_tri_total, drawn=n_tri_drawn,
                                      culled=n_tri_culled, meshes=len(meshes))


def apply_overrides(meshes, specs):
    """`--set mask_scale=1.6` — muda o uniform em todos os materiais de relva.

    A relva é decidida no fragment shader a partir dos uniforms e da máscara,
    portanto afinar aqui é equivalente a mexer no .gdshader e reexportar — mas em
    segundos em vez de minutos por tentativa.
    """
    targets = ("grass_shells.gdshader", "grass_cards.gdshader", "toon_terrain.gdshader")
    for spec in specs:
        if "=" not in spec:
            sys.exit("--set espera NOME=VALOR (recebido %r)" % spec)
        name, raw = spec.split("=", 1)
        values = [float(v) for v in raw.split(",")]
        for m in meshes:
            if m["mat"] not in targets or name not in m["params"]:
                continue
            kind = m["params"][name][0]
            packed = [0.0, 0.0, 0.0, 0.0]
            for i, v in enumerate(values[:4]):
                packed[i] = v
            m["params"][name] = (kind, tuple(packed), m["params"][name][2])
        print("--set %s = %s" % (name, values))


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
        # (winding horário = frontal no Godot, ver render())
        g = np.linalg.norm(geo, axis=1)
        bad_n += int((g < 1e-9).sum())
        vn = m["nrm"][I[:, 0]] + m["nrm"][I[:, 1]] + m["nrm"][I[:, 2]]
        bad_w += int((np.einsum("ij,ij->i", geo, vn) > 0).sum())
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
    ap.add_argument("--set", action="append", default=[],
                    metavar="NOME=VALOR",
                    help="sobrepõe um uniform dos materiais de relva (afinação "
                         "rápida a partir do mesmo dump, sem reexportar o pck)")
    ap.add_argument("--no-png", action="store_true")
    a = ap.parse_args()

    hdr, meshes = load(a.dump)
    if a.set:
        apply_overrides(meshes, a.set)
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
