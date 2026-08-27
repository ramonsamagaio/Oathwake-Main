#!/usr/bin/env python3
"""
Skin "Golem de Pedra" para o Oathwake Monster 01.

A arte NAO e um redimensionamento do concept: nesse tamanho de celula
(cabeca 16x16, membros 8x8) um downscale vira papa. O que e reaproveitado e a
LINGUAGEM do concept, extraida dele:

  - paleta exata (subconjunto da DB32 lido do PNG)
  - contorno preto duro separando cada placa
  - veio de cyan (#5ecde4) rachando o meio de cada peca, com nucleo mais claro
  - musgo verde/oliva so nas faces viradas para cima
  - acento areia (#d8a066) nas quinas iluminadas
  - luz vindo de cima-esquerda: topo claro, base escura

Cada peca e desenhada nas 5 vistas (S, SE, E, NE, N). O corpo usa 4 direcoes
(SE copia S, NE copia N); cabeca e membros usam as 5 de verdade.
"""

import os
import sys

from PIL import Image, ImageDraw

CHROMA = (255, 0, 195, 255)
ATLAS_W, ATLAS_H = 672, 120

# ------------------------------------------------------------------ paleta
# Cores por PAPEL, nao por nome de cor: trocar de material e trocar um dict.
# STONE = concept do golem de pedra (DB32).  JADE = concept do golem de jade.
PALETTES = {
    "stone": dict(
        OUT=(0, 0, 0), HI=(154, 172, 182), BODY=(131, 126, 135), MID=(105, 105, 105),
        SH=(89, 86, 82), DK=(49, 59, 56), BK=(33, 31, 52),
        ACCENT=(94, 205, 228), ACCENT_DP=(47, 96, 130), ACCENT_HOT=(255, 255, 255),
        TRIM=(216, 160, 102), TRIM_HI=(237, 195, 154), TRIM_DK=(137, 110, 47),
        WEAR=((75, 105, 47), (142, 151, 73), (153, 228, 80), (137, 110, 47), (82, 75, 35)),
    ),
    "jade": dict(
        OUT=(26, 20, 16), HI=(79, 191, 160), BODY=(48, 144, 120), MID=(37, 122, 99),
        SH=(28, 99, 80), DK=(24, 72, 48), BK=(16, 48, 31),
        ACCENT=(255, 180, 60), ACCENT_DP=(160, 90, 20), ACCENT_HOT=(255, 244, 200),
        TRIM=(192, 160, 120), TRIM_HI=(224, 200, 160), TRIM_DK=(96, 72, 48),
        WEAR=((96, 72, 48), (120, 96, 72), (160, 136, 104), (72, 48, 24), (56, 40, 24)),
    ),
}
ACTIVE = "stone"

OUT = STONE_HI = STONE = STONE_MD = STONE_SH = STONE_DK = STONE_BK = None
CYAN = CYAN_DP = WHITE = TAN = TAN_L = OLIVE = None
MOSS_D = MOSS = MOSS_L = OLIVE_D = BLUE = None


def set_palette(name):
    """Reaponta os papeis. Toda peca desenha por papel, entao nenhuma funcao
    de desenho precisa saber de que material o monstro e feito."""
    global ACTIVE, OUT, STONE_HI, STONE, STONE_MD, STONE_SH, STONE_DK, STONE_BK
    global CYAN, CYAN_DP, WHITE, TAN, TAN_L, OLIVE, MOSS_D, MOSS, MOSS_L, OLIVE_D, BLUE
    ACTIVE = name
    p = PALETTES[name]
    a = lambda c: (c[0], c[1], c[2], 255)
    OUT = a(p["OUT"]); STONE_HI = a(p["HI"]); STONE = a(p["BODY"])
    STONE_MD = a(p["MID"]); STONE_SH = a(p["SH"]); STONE_DK = a(p["DK"]); STONE_BK = a(p["BK"])
    CYAN = a(p["ACCENT"]); CYAN_DP = a(p["ACCENT_DP"]); WHITE = a(p["ACCENT_HOT"])
    TAN = a(p["TRIM"]); TAN_L = a(p["TRIM_HI"]); OLIVE = a(p["TRIM_DK"])
    MOSS_D, MOSS, MOSS_L, OLIVE_D, BLUE = [a(c) for c in p["WEAR"]]


set_palette("stone")

COLS = ["S", "SE", "E", "NE", "N"]
FRONTISH = ("S", "SE")
BACKISH = ("NE", "N")


def cell(w, h):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def px(d, x, y, c):
    d.point((x, y), fill=c)


def hline(d, x0, x1, y, c):
    d.line([x0, y, x1, y], fill=c)


def vline(d, x, y0, y1, c):
    d.line([x, y0, x, y1], fill=c)


def rng(seed):
    """PRNG deterministico simples: musgo estavel por celula, sem shimmer."""
    state = [seed & 0xFFFFFFFF]

    def nxt(n):
        state[0] = (state[0] * 1103515245 + 12345) & 0x7FFFFFFF
        return state[0] % n
    return nxt


# ---------------------------------------------------------------- formas
# O concept nao tem UMA quina reta: tudo e domo, capsula ou blob chanfrado, e
# cada junta tem um soquete redondo escuro. Um retangulo com contorno era a
# leitura errada da linguagem. Aqui a forma base e um blob com canto cortado em
# 45 graus, e o contorno preto e desenhado POR FORA — assim a peca nao perde
# area util e ainda ganha 1 px de sobreposicao, que ajuda a fechar as emendas.

def blob_mask(x0, y0, x1, y1, r_top=1, r_bot=1):
    """Conjunto de pixels de um retangulo de cantos chanfrados."""
    inside = set()
    for y in range(y0, y1 + 1):
        dt, db = y - y0, y1 - y
        cut = 0
        if dt < r_top:
            cut = max(cut, r_top - dt)
        if db < r_bot:
            cut = max(cut, r_bot - db)
        for x in range(x0 + cut, x1 - cut + 1):
            inside.add((x, y))
    return inside


def outline_of(mask):
    edge = set()
    for (x, y) in mask:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n not in mask:
                edge.add(n)
    return edge


def paint(d, mask, color, bounds=None):
    for (x, y) in mask:
        if bounds and not (bounds[0] <= x <= bounds[2] and bounds[1] <= y <= bounds[3]):
            continue
        d.point((x, y), fill=color)


def plate(d, x0, y0, x1, y1, r_top=1, r_bot=1, lit=True, bounds=None):
    """Placa de pedra arredondada, luz em cima-esquerda, contorno por fora."""
    mask = blob_mask(x0, y0, x1, y1, r_top, r_bot)
    paint(d, outline_of(mask), OUT, bounds)
    paint(d, mask, STONE, bounds)
    rows = {}
    for (x, y) in mask:
        rows.setdefault(y, []).append(x)
    ys = sorted(rows)
    for i, y in enumerate(ys):
        xs = sorted(rows[y])
        if i == 0:
            paint(d, {(x, y) for x in xs}, STONE_HI if lit else STONE_MD, bounds)
        elif i == 1 and len(ys) > 3:
            paint(d, {(x, y) for x in xs[:max(1, len(xs) - 1)]},
                  STONE_HI if lit else STONE_MD, bounds)
        elif i == len(ys) - 1:
            paint(d, {(x, y) for x in xs}, STONE_SH, bounds)
        elif i == len(ys) - 2 and len(ys) > 4:
            paint(d, {(x, y) for x in xs[1:]}, STONE_SH, bounds)
        else:
            paint(d, {(xs[0], y)}, STONE_HI if lit else STONE, bounds)
            paint(d, {(xs[-1], y)}, STONE_MD, bounds)
    return mask


def nub(d, x0, y0, x1, y1, color, shade=None, bounds=None):
    """Detalhe pequeno (2-3 px). NAO leva contorno preto: nesse tamanho o
    contorno consome a peca inteira e vira uma caixa preta. A leitura de volume
    vem de uma unica sombra na aresta inferior-direita."""
    mask = blob_mask(x0, y0, x1, y1, 1, 1) if (x1 - x0) >= 2 and (y1 - y0) >= 2 \
        else {(x, y) for x in range(x0, x1 + 1) for y in range(y0, y1 + 1)}
    paint(d, mask, color, bounds)
    if shade is not None:
        paint(d, {(x, y1) for x in range(x0 + 1, x1 + 1)}, shade, bounds)
        paint(d, {(x1, y) for y in range(y0 + 1, y1 + 1)}, shade, bounds)


def socket(d, cx, cy, r=1, glow=False, bounds=None):
    """Soquete de junta: knob redondo escuro. E o que esconde a emenda entre
    duas pecas — o concept usa isso em cotovelo, joelho e pulso."""
    mask = blob_mask(cx - r, cy - r, cx + r, cy + r, 1, 1) if r >= 1 \
        else {(cx - 1, cy), (cx, cy), (cx + 1, cy)}
    paint(d, mask, STONE_BK, bounds)
    ring = outline_of(mask)
    paint(d, {p for p in ring if p[1] <= cy - r}, STONE_MD, bounds)
    if glow:
        paint(d, {(cx, cy)}, CYAN_DP, bounds)


def vein(d, x, y0, y1, bright=True, jag=1, xmin=None, xmax=None):
    """Veio de cyan descendo, em zigue-zague, preso dentro da placa."""
    core = CYAN if bright else CYAN_DP
    for i, y in enumerate(range(y0, y1 + 1)):
        off = (0, 1, 1, 0, -1, -1)[i % 6] if jag else 0
        cx = x + off
        if xmin is not None:
            cx = max(xmin, cx)
        if xmax is not None:
            cx = min(xmax, cx)
        px(d, cx, y, core)
        if bright and i % 6 == 1:
            px(d, cx, y, WHITE)


def moss(d, spots, seed, heavy=False):
    """Musgo/liquen nas faces de cima. spots = lista de (x, y) candidatos."""
    r = rng(seed)
    palette = (MOSS_D, MOSS, MOSS_L, OLIVE, OLIVE_D)
    for (x, y) in spots:
        roll = r(10)
        if roll < (6 if heavy else 4):
            d.point((x, y), fill=palette[r(5)])


def sand(d, spots, seed):
    r = rng(seed)
    for (x, y) in spots:
        if r(10) < 3:
            d.point((x, y), fill=TAN if r(2) else TAN_L)


# =============================================================== peças
def draw_head(direction, row, seed=0):
    """16x16. NAO e um rosto: e um idolo.

    A leitura de "lerdao" vinha de cabeca redonda larga com dois olhos e focinho.
    O concept faz o oposto: cunha vertical estreita e angular, listra de metal
    descendo pelo meio, UMA gema acesa, nenhum olho. Estreito + anguloso + um
    ponto de brilho le como ameaca; largo + redondo + dois olhos le como bicho.
    """
    im, d = cell(16, 16)
    dy = {"UP1+": -1, "ALL": 0, "DOWN1+": 1}[row]
    top = 2 + dy
    bot = 11 + dy          # 10 px, nao 13: alta demais lia como chifre
    B = (0, 0, 15, 15)

    narrow = {"S": 0, "SE": 1, "E": 1, "NE": 1, "N": 0}[direction]
    shift = {"S": 0, "SE": 1, "E": 2, "NE": 1, "N": 0}[direction]
    x0, x1 = 4 + narrow + shift, 11 - narrow + shift
    cx = (x0 + x1) // 2

    # sombra do nicho: a cunha nasce de dentro de uma cavidade escura
    paint(d, blob_mask(x0 - 2, top + 1, x1 + 2, bot, 2, 3), STONE_BK, B)

    # cunha: larga em cima, afunilando ate a ponta arredondada embaixo
    wedge = set()
    span = bot - top
    for i, y in enumerate(range(top, bot + 1)):
        t = i / max(span, 1)
        cut = 0 if t < 0.45 else int(round((t - 0.45) / 0.55 * ((x1 - x0) / 2)))
        for x in range(x0 + cut, x1 - cut + 1):
            wedge.add((x, y))
    paint(d, outline_of(wedge), OUT, B)
    paint(d, wedge, STONE, B)
    rows = {}
    for (x, y) in wedge:
        rows.setdefault(y, []).append(x)
    for y, xs in rows.items():
        xs = sorted(xs)
        paint(d, {(xs[0], y)}, STONE_HI, B)
        paint(d, {(xs[-1], y)}, STONE_SH, B)
    paint(d, {(x, top) for x in range(x0, x1 + 1)}, STONE_HI, B)

    if direction == "N":
        # nuca: so a placa e a costura do metal, sem gema
        vline(d, cx, top + 2, bot - 2, TRIM_DK_C())
        return _head_finish(im, d, x0, x1, top, bot, seed, direction, B)

    # listra de metal descendo pelo meio, bifurcada no alto como guarda-nariz
    stripe_x = cx if direction != "E" else x1 - 1
    vline(d, stripe_x, top + 1, bot - 1, TAN)
    px(d, stripe_x, top + 1, TAN_L)
    if direction in FRONTISH:
        vline(d, stripe_x - 1, top + 1, bot - 2, TAN)
        px(d, stripe_x - 2, top + 1, TAN); px(d, stripe_x + 1, top + 1, TAN)
        px(d, stripe_x - 2, top + 2, OLIVE); px(d, stripe_x + 1, top + 2, OLIVE)

    if direction != "NE":
        # gema: losango aceso, o unico ponto quente da peca
        gy = top + 4
        px(d, stripe_x, gy - 1, CYAN_DP)
        px(d, stripe_x, gy, CYAN)
        px(d, stripe_x, gy + 1, CYAN)
        if direction in FRONTISH:
            px(d, stripe_x - 1, gy, CYAN_DP)
            px(d, stripe_x, gy, WHITE)
        px(d, stripe_x, gy + 2, CYAN_DP)
    return _head_finish(im, d, x0, x1, top, bot, seed, direction, B)


def TRIM_DK_C():
    return OLIVE


def _head_finish(im, d, x0, x1, top, bot, seed, direction, B):
    moss(d, [(x, top) for x in range(x0, x1 + 1)] +
            [(x, top + 1) for x in range(x0, x1 + 1)],
         seed + 11, heavy=direction in BACKISH)
    return im


def draw_torso(direction, row, seed=0):
    """16x16. Pivo (0.5, 0.80). Peitoral com a runa de cyan."""
    im, d = cell(16, 16)
    dy = 1 if row == "DOWN1+" else 0
    top, bot = 0 + dy, 12          # tronco = 13 px (pescoco -50 -> cintura -37)
    inset = {"S": 0, "SE": 0, "E": 3, "NE": 0, "N": 0}[direction]
    x0, x1 = 2 + inset, 13 - inset
    plate(d, x0, top + 1, x1, bot, r_top=3, r_bot=1, bounds=(0, 0, 15, 15))
    cx = (x0 + x1) // 2

    if direction in FRONTISH:
        # sulco entre peitorais
        vline(d, cx, top + 1, bot - 1, STONE_DK)
        # runa em losango
        px(d, cx, top + 4, CYAN)
        hline(d, cx - 2, cx + 2, top + 6, CYAN)
        px(d, cx - 1, top + 5, CYAN); px(d, cx + 1, top + 5, CYAN)
        px(d, cx - 1, top + 7, CYAN); px(d, cx + 1, top + 7, CYAN)
        px(d, cx, top + 8, CYAN)
        px(d, cx, top + 6, WHITE)
        # placas peitorais
        hline(d, x0 + 1, cx - 1, top + 2, STONE_HI)
        hline(d, cx + 1, x1 - 1, top + 2, STONE_HI)
    elif direction == "E":
        vein(d, cx, top + 2, bot - 2, bright=True, jag=1, xmin=x0 + 1, xmax=x1 - 1)
        vline(d, x1 - 1, top + 1, bot - 1, STONE_SH)
    else:
        # costas: canal da coluna
        d.rectangle([cx - 1, top + 1, cx + 1, bot - 1], fill=STONE_DK, outline=None)
        vein(d, cx, top + 2, bot - 3, bright=direction == "NE", jag=0)
        hline(d, x0 + 1, x1 - 1, top + 5, STONE_SH)
        hline(d, x0 + 1, x1 - 1, top + 9, STONE_SH)

    moss(d, [(x, top + 1) for x in range(x0 + 1, x1)] +
            [(x, top + 2) for x in range(x0 + 1, x1)],
         seed + 21, heavy=direction in BACKISH)
    sand(d, [(x0 + 1, y) for y in range(top + 3, bot)], seed + 22)
    # coleira em ferradura: o arco de metal que emoldura a cabeca. Mora no
    # torso porque no rig ela nasce dos ombros, nao do cranio.
    ax0, ax1 = x0 - 1, x1 + 1
    acx = (ax0 + ax1) / 2.0
    half = max((ax1 - ax0) / 2.0, 1.0)
    for x in range(ax0, ax1 + 1):
        t = (x - acx) / half
        y = top + 2 - int(round(2.0 * t * t))
        col = TAN
        if x <= ax0 + 1:
            col = TAN_L
        elif x >= ax1 - 1:
            col = OLIVE
        paint(d, {(x, y)}, col, (0, 0, 15, 15))
        paint(d, {(x, y + 1)}, OLIVE, (0, 0, 15, 15))
    return im


def draw_abdomen(direction, row, seed=0):
    """16x12. Pivo (0.5, 0.70)."""
    im, d = cell(16, 12)
    dy = 1 if row == "DOWN1+" else 0
    top, bot = 0 + dy, 8           # abdome = 9 px (cintura -38.5 -> quadril -29.5)
    inset = {"S": 0, "SE": 0, "E": 2, "NE": 0, "N": 0}[direction]
    x0, x1 = 2 + inset, 13 - inset
    plate(d, x0, top + 1, x1, bot, r_top=3, r_bot=2, bounds=(0, 0, 15, 15))
    cx = (x0 + x1) // 2
    # segmentos horizontais do abdome
    for y in (top + 3, top + 6):
        hline(d, x0 + 1, x1 - 1, y, STONE_DK)
        hline(d, x0 + 1, x1 - 1, y + 1, STONE_HI)
    if direction in FRONTISH:
        vein(d, cx, top + 1, bot - 1, bright=True, jag=1, xmin=x0 + 1, xmax=x1 - 1)
    elif direction == "E":
        vein(d, cx, top + 1, bot - 1, bright=True, jag=0)
    else:
        vline(d, cx, top + 1, bot - 1, STONE_DK)
        px(d, cx, top + 4, CYAN_DP)
    moss(d, [(x, top + 1) for x in range(x0 + 1, x1)], seed + 31,
         heavy=direction in BACKISH)
    return im


def draw_pelvis(direction, row, seed=0):
    """16x12. Pivo (0.5, 0.5)."""
    im, d = cell(16, 12)
    inset = {"S": 0, "SE": 0, "E": 3, "NE": 0, "N": 0}[direction]
    x0, x1 = 2 + inset, 13 - inset
    plate(d, x0, 1, x1, 9)
    cx = (x0 + x1) // 2
    # cavidade central escura, como no concept
    d.rectangle([cx - 1, 4, cx + 1, 6], fill=STONE_DK, outline=None)
    if direction in FRONTISH:
        px(d, cx, 5, CYAN)
        px(d, cx - 1, 4, CYAN_DP); px(d, cx + 1, 4, CYAN_DP)
    elif direction == "E":
        px(d, cx + 1, 5, CYAN)
    moss(d, [(x, 1) for x in range(x0 + 1, x1)], seed + 41,
         heavy=direction in BACKISH)
    return im


def _limb(w, h, direction, seed, taper=0, vein_bright=True, tag=0):
    """Placa de membro generica: contorno, topo claro, veio central."""
    im, d = cell(w, h)
    inset = {"S": 0, "SE": 0, "E": taper, "NE": 0, "N": 0}[direction]
    x0, x1 = 1 + inset, w - 2 - inset
    plate(d, x0, 1, x1, h - 2, r_top=1, r_bot=1, bounds=(0, 0, w - 1, h - 1))
    cx = (x0 + x1) // 2
    if direction in FRONTISH:
        vein(d, cx, 3, h - 3, bright=vein_bright, jag=1, xmin=x0 + 1, xmax=x1 - 1)
    elif direction == "E":
        vein(d, cx, 3, h - 3, bright=vein_bright, jag=0, xmin=x0 + 1, xmax=x1 - 1)
    else:
        vline(d, cx, 3, h - 3, STONE_DK)
        px(d, cx, h // 2, CYAN_DP)
    moss(d, [(x, 2) for x in range(x0 + 1, x1)] +
            [(x, 3) for x in range(x0 + 1, x1)],
         seed + tag, heavy=direction in BACKISH)
    sand(d, [(x0 + 1, y) for y in range(3, h - 2)], seed + tag + 1)
    # soquete na ponta proximal: e ele que cobre a emenda com a peca do pai
    socket(d, cx, 1, r=1, glow=direction in FRONTISH, bounds=(0, 0, w - 1, h - 1))
    return im


def draw_upper_leg(direction, row, seed=0):
    return _limb(8, 16, direction, seed, taper=1, tag=51)


def draw_shin(direction, row, seed=0):
    return _limb(8, 12, direction, seed, taper=1, tag=61)


def draw_upper_arm(direction, row, seed=0):
    return _limb(8, 12, direction, seed, taper=1, tag=71)


def draw_forearm(direction, row, seed=0):
    return _limb(8, 8, direction, seed, taper=1, tag=81)


def draw_foot(direction, row, seed=0):
    """12x12. Pivo (0.5, 0.35). Pe chapado de tres dedos."""
    im, d = cell(12, 12)
    if direction in FRONTISH:
        plate(d, 2, 1, 9, 7, r_top=2, r_bot=2, bounds=(0, 0, 11, 11))
        # tres dedos
        for i, x in enumerate((2, 5, 8)):
            nub(d, x, 7, x + 1, 9, STONE, STONE_SH, bounds=(0, 0, 11, 11))
            px(d, x, 8, CYAN if i == 1 else STONE_HI)
        moss(d, [(x, 2) for x in range(3, 9)], seed + 91)
    elif direction == "E":
        plate(d, 1, 2, 10, 7, r_top=2, r_bot=2, bounds=(0, 0, 11, 11))
        nub(d, 8, 7, 10, 9, STONE, STONE_SH, bounds=(0, 0, 11, 11))
        px(d, 9, 8, CYAN)
        moss(d, [(x, 3) for x in range(2, 10)], seed + 92)
    else:
        plate(d, 2, 1, 9, 8, r_top=3, r_bot=2, bounds=(0, 0, 11, 11))
        vline(d, 5, 2, 7, STONE_DK)
        moss(d, [(x, 2) for x in range(3, 9)] + [(x, 3) for x in range(3, 9)],
             seed + 93, heavy=True)
    return im


def draw_shoulder(direction, row, seed=0):
    """12x12. Pivo (0.5, 0.5). Pauldron: a assinatura da silhueta do golem."""
    im, d = cell(12, 12)
    inset = {"S": 0, "SE": 0, "E": 1, "NE": 0, "N": 0}[direction]
    x0, x1 = inset, 11 - inset
    # domo
    d.ellipse([x0, 0, x1, 10], fill=STONE, outline=OUT)
    d.ellipse([x0 + 1, 1, x1 - 2, 6], fill=STONE_HI, outline=None)
    d.arc([x0, 0, x1, 10], start=20, end=160, fill=STONE_SH)
    cx = (x0 + x1) // 2
    if direction in FRONTISH:
        d.arc([x0 + 2, 2, x1 - 2, 9], start=200, end=340, fill=CYAN)
        px(d, cx, 4, WHITE)
    elif direction == "E":
        d.arc([x0 + 2, 2, x1 - 2, 9], start=250, end=330, fill=CYAN)
    else:
        d.arc([x0 + 2, 3, x1 - 2, 9], start=210, end=330, fill=CYAN_DP)
    moss(d, [(x, 1) for x in range(x0 + 2, x1 - 1)] +
            [(x, 2) for x in range(x0 + 1, x1)] +
            [(x, 3) for x in range(x0 + 1, x1)],
         seed + 101, heavy=True)
    socket(d, cx, 9, r=1, glow=False, bounds=(0, 0, 11, 11))
    return im


def draw_fist(direction, row, seed=0):
    """10x10. Pivo (0.5, 0.5). Punho macico de tres nos."""
    im, d = cell(10, 10)
    inset = {"S": 0, "SE": 0, "E": 1, "NE": 0, "N": 0}[direction]
    x0, x1 = 1 + inset, 8 - inset
    plate(d, x0, 2, x1, 8, r_top=2, r_bot=2, bounds=(0, 0, 9, 9))
    if direction in FRONTISH:
        for x in (x0, x0 + 3, x1 - 1):
            nub(d, x, 5, x + 1, 7, STONE_HI, STONE_SH, bounds=(0, 0, 9, 9))
            px(d, x + 2, 6, STONE_DK)
        hline(d, x0 + 1, x1 - 1, 4, CYAN)
    elif direction == "E":
        nub(d, x1 - 2, 5, x1, 7, STONE_HI, STONE_SH, bounds=(0, 0, 9, 9))
        vline(d, x0 + 1, 4, 6, CYAN)
    else:
        hline(d, x0 + 1, x1 - 1, 5, STONE_DK)
        px(d, (x0 + x1) // 2, 6, CYAN_DP)
    socket(d, (x0 + x1) // 2, 1, r=0, glow=direction in FRONTISH, bounds=(0, 0, 9, 9))
    moss(d, [(x, 3) for x in range(x0 + 1, x1)], seed + 111,
         heavy=direction in BACKISH)
    return im


def draw_joint(direction, row, seed=0):
    """Bola de articulacao 6x6. NAO e enfeite: pecas com PARENT_ROTATE_SCALE
    sao esticadas ate exatamente a junta, entao duas pecas vizinhas encostam mas
    nunca se sobrepoem — qualquer erro de 1 px vira fresta. Esta bola fica
    ancorada na junta, sem esticar, e cobre a emenda. O concept usa o mesmo
    recurso em cotovelo, joelho e pulso."""
    im, d = cell(6, 6)
    plate(d, 1, 1, 4, 4, r_top=1, r_bot=1, bounds=(0, 0, 5, 5))
    if direction in FRONTISH:
        px(d, 2, 2, STONE_HI)
        px(d, 3, 3, CYAN)
    elif direction == "E":
        px(d, 2, 2, STONE_HI)
        px(d, 3, 3, CYAN_DP)
    else:
        px(d, 2, 3, STONE_DK)
    moss(d, [(x, 1) for x in range(1, 5)], seed + 121, heavy=direction in BACKISH)
    return im


# ============================================== layout do atlas (golem)
# Pauldron e punho cresceram e foram para o espaco livre do atlas (x >= 272),
# porque a silhueta do golem vive nos ombros e nas maos.
BLOCKS = [
    ("head",      draw_head,      0,   0, 16, 16, ["UP1+", "ALL", "DOWN1+"], False),
    ("torso",     draw_torso,     0,  48, 16, 16, ["ALL", "DOWN1+"], True),
    ("abdomen",   draw_abdomen,   0,  80, 16, 12, ["ALL", "DOWN1+"], True),
    ("pelvis",    draw_pelvis,    0, 104, 16, 12, ["ALL"], True),
    ("upper_leg", draw_upper_leg, 144,  0,  8, 16, ["ALL"], False),
    ("shin",      draw_shin,      144, 16,  8, 12, ["ALL"], False),
    ("foot",      draw_foot,      144, 28, 12, 12, ["ALL"], False),
    ("upper_arm", draw_upper_arm, 208,  8,  8, 12, ["ALL"], False),
    ("forearm",   draw_forearm,   208, 20,  8,  8, ["ALL"], False),
    ("shoulder",  draw_shoulder,  272,  0, 12, 12, ["ALL"], False),
    ("fist",      draw_fist,      272, 16, 10, 10, ["ALL"], False),
    ("joint",     draw_joint,     272, 28,  6,  6, ["ALL"], False),
]

# corpo em 4 direcoes: a diagonal reusa a vizinha cardeal
FOUR_DIR = {"S": "S", "SE": "S", "E": "E", "NE": "N", "N": "N"}


def build_atlas():
    atlas = Image.new("RGBA", (ATLAS_W, ATLAS_H), CHROMA)
    for name, painter, bx, by, w, h, rows, four in BLOCKS:
        for r, row in enumerate(rows):
            for c, direction in enumerate(COLS):
                src = FOUR_DIR[direction] if four else direction
                seed = (abs(hash(name)) % 9973) + r * 131 + c * 17
                art = painter(src, row, seed)
                atlas.paste(art, (bx + c * w, by + r * h), art)
    return atlas


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    pal = sys.argv[2] if len(sys.argv) > 2 else "stone"
    set_palette(pal)
    os.makedirs(out, exist_ok=True)
    atlas = build_atlas()
    name = "oathwake_golem_01.png" if pal == "stone" else "oathwake_golem_%s_01.png" % pal
    path = os.path.join(out, name)
    atlas.save(path)
    print("ok ->", path)
    for name, _p, bx, by, w, h, rows, four in BLOCKS:
        print("  %-10s (%3d,%3d) %2dx%-2d  %d linha(s)  %s"
              % (name, bx, by, w, h, len(rows), "4 dir" if four else "8 dir"))


if __name__ == "__main__":
    main()
