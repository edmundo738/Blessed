#!/usr/bin/env python3
"""render_feel.py — mostra o véu sensorial da HUD como imagem.

Porque existe
-------------
O `render_shot.py` desenha a geometria do mundo, mas o véu de fome/sede/cansaço
vive num shader de `canvas_item` — não entra no dump. Sem isto, cada mudança no
"sentir" era uma afirmação sem prova: eu dizia "o ecrã escurece quando a fome
aperta" e ninguém via nada.

Este script porta a MESMA matemática de `scripts/ui/hud.gd::_vignette` para
numpy, aplica-a sobre um PNG do mundo e escreve o resultado. Não é o renderer do
Godot: é a prova de que as cores, os pesos e os ritmos que estão no shader
produzem o efeito pretendido, e serve para comparar estados (saudável vs. a
cair) sem ter de jogar 20 minutos até à fome.

Uso:
    render_feel.py shot.png -o feel.png --left healthy --right broken
    render_feel.py shot.png -o feel.png --state hungry
"""
from __future__ import annotations

import argparse
import math

import numpy as np


def rnd(x, y):
    v = np.sin(x * 12.9898 + y * 78.233) * 43758.5453
    return v - np.floor(v)


def veil(width, height, fear=0.0, hurt=0.0, hunger=0.0, thirst=0.0,
         fatigue=0.0, cold=0.0, sick=0.0, t=7.0, grain=0.4):
    """Porta fiel do fragment() de hud.gd::_vignette (mesmos pesos e cores)."""
    ys, xs = np.mgrid[0:height, 0:width]
    u = (xs + 0.5) / width
    v = (ys + 0.5) / height
    cx = u - 0.5
    cy = v - 0.5
    d = np.sqrt(cx * cx + cy * cy) * 1.42

    def band(e0, e1, x):
        k = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
        return k * k * (3 - 2 * k)

    vig = band(0.55, 1.25, d)

    h = band(0.45, 1.0, hunger)
    th = band(0.45, 1.0, thirst)
    f = band(0.35, 1.0, fatigue)
    k = band(0.40, 1.0, cold)
    sv = band(0.25, 1.0, sick)

    lids = band(0.30, 1.10, d + 0.12 * np.sin(u * math.pi))
    breath = 0.5 - 0.5 * math.cos(t * (1.15 + thirst * 0.9))
    dark = (vig * (0.26 + fear * 0.60)
            + vig * (h * 0.38 + th * 0.42 + k * 0.24)
            + f * (lids * 0.50 + 0.12 * breath)
            + sv * vig * 0.22 * (0.7 + 0.3 * math.sin(t * 2.2)))
    dark = np.clip(dark, 0.0, 0.88)

    def const(c):
        return np.full((height, width, 3), c, dtype=np.float64)

    tint = (const((0.12, 0.065, 0.015)) * h[..., None]
            + const((0.035, 0.05, 0.062)) * th[..., None]
            + const((0.02, 0.02, 0.055)) * f[..., None]
            + const((0.05, 0.085, 0.115)) * k[..., None]
            + const((0.028, 0.085, 0.030)) * sv[..., None])
    mixk = np.clip(vig + f * 0.35 + sv * 0.5, 0.0, 1.0)
    tint = tint * mixk[..., None]

    frost = (rnd(np.floor(u * 230.0), np.floor(v * 230.0)) >= 0.94).astype(np.float64) * vig * k
    tint += const((0.02, 0.0, 0.03)) * (fear * 1.2)
    tint += const((0.5, 0.0, 0.05)) * (hurt * 0.6)

    g = (rnd(u * 512.0 + t, v * 512.0 + t) - 0.5) * grain * 0.06
    col = tint + const((0.55, 0.68, 0.80)) * (frost * 0.45)[..., None]
    a = np.clip(dark + frost * 0.28 + g, 0.0, 0.92)
    return np.clip(col + g[..., None], 0.0, 1.0), a


PRESETS = {
    "healthy": dict(),
    "hungry": dict(hunger=0.92),
    "thirsty": dict(thirst=0.95),
    "exhausted": dict(fatigue=0.95),
    "cold": dict(cold=0.9),
    "sick": dict(sick=0.8, thirst=0.4),
    "hungry_thirsty": dict(hunger=0.9, thirst=0.92),
    "fear": dict(fear=0.7),
    "broken": dict(hunger=0.9, thirst=0.9, fatigue=0.95, cold=0.55, sick=0.6, fear=0.35),
}


def apply_preset(rgb, state):
    h, w, _ = rgb.shape
    col, alpha = veil(w, h, t=7.3, **PRESETS[state])
    return np.clip(rgb * (1.0 - alpha[..., None]) + col * alpha[..., None], 0.0, 1.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base", help="PNG do mundo (tools/render_shot.py)")
    ap.add_argument("-o", "--out", default="feel.png")
    ap.add_argument("--state", default="hungry", choices=sorted(PRESETS))
    ap.add_argument("--left", default="healthy", choices=sorted(PRESETS))
    ap.add_argument("--right", default="", choices=[""] + sorted(PRESETS),
                    help="se dado, escreve um antes/depois lado a lado")
    ap.add_argument("--label", default="")
    a = ap.parse_args()

    from PIL import Image, ImageDraw

    img = Image.open(a.base).convert("RGB")
    rgb = np.asarray(img).astype(np.float64) / 255.0
    rgb = np.power(rgb, 2.2)  # desfazer o gamma que o render_shot escreveu

    if a.right:
        left = apply_preset(rgb, a.left)
        right = apply_preset(rgb, a.right)
        gap = np.ones((rgb.shape[0], 8, 3))
        both = np.concatenate([left, gap, right], axis=1)
        out = (np.power(both, 1.0 / 2.2) * 255).astype(np.uint8)
        im = Image.fromarray(out)
        draw = ImageDraw.Draw(im)
        label = a.label or "%s  →  %s" % (a.left, a.right)
        draw.text((14, 10), label, fill=(255, 255, 255))
        im.save(a.out)
    else:
        out = (np.power(apply_preset(rgb, a.state), 1.0 / 2.2) * 255).astype(np.uint8)
        im = Image.fromarray(out)
        ImageDraw.Draw(im).text((14, 10), a.label or a.state, fill=(255, 255, 255))
        im.save(a.out)
    print("-> %s" % a.out)


if __name__ == "__main__":
    main()
