#!/usr/bin/env python3
"""
Gerador do gabarito Alabaster para monstros humanoides do Oathwake.

Produz, na pasta de saida:
  monster_humanoid_01.png        atlas 672x120 chroma-keyed, placeholder jogavel
  monster_template_overlay.png   overlay 672x120 transparente (camada de guia no Aseprite)
  monster_template_guide.png     poster anotado (referencia de leitura, nao vai pro jogo)

Contrato do runtime (AlabasterExternalSkinSource / AlabasterDefaultPlayableSkinRig):
  - atlas exatamente 672x120
  - fundo chroma RGB (255, 0, 195) -> vira alpha 0 no load
  - colunas = direcao, linhas = faixa de pitch
  - FACE_8_MIRR: 5 celulas unicas por linha -> col0=S col1=SE col2=E col3=NE col4=N
    (SW/W/NW sao espelhos automaticos de SE/E/NE)
"""

import json
import os
import sys

from PIL import Image, ImageDraw, ImageFont

CHROMA = (255, 0, 195, 255)
ATLAS_W, ATLAS_H = 672, 120

# ---------------------------------------------------------------- paleta
SKIN      = (206, 160, 118, 255)
SKIN_HI   = (232, 190, 148, 255)
SKIN_SH   = (156, 112,  78, 255)
HAIR      = ( 74,  52,  38, 255)
HAIR_HI   = (106,  76,  54, 255)
CLOTH     = ( 70,  96, 140, 255)
CLOTH_HI  = ( 98, 128, 176, 255)
CLOTH_SH  = ( 44,  62,  96, 255)
PANTS     = ( 62,  58,  74, 255)
PANTS_HI  = ( 88,  84, 106, 255)
PANTS_SH  = ( 40,  36,  50, 255)
BOOT      = ( 52,  40,  34, 255)
BOOT_HI   = ( 78,  60,  50, 255)
EYE       = ( 28,  26,  34, 255)
FRONT_TAG = (232,  80,  72, 255)   # marcador "isto e a frente"
BACK_TAG  = ( 72, 168, 232, 255)   # marcador "isto e as costas"

# --------------------------------------------------------- layout do atlas
# name, node(s), gfx, x, y, w, h, linhas(pitch), facing, pivot(x,y), texRotate
BLOCKS = [
    ("head",      "head",              0,   0,   0, 16, 16, ["UP1+", "ALL", "DOWN1+"], "FACE_8_MIRR",      (0.5,  0.13), "NONE"),
    ("top",       "top",               0,   0,  48, 16, 16, ["ALL", "DOWN1+"],         "FACE_8_MIRR",      (0.5,  0.25), "NONE"),
    ("abdomen",   "root",              0,   0,  80, 16, 12, ["ALL", "DOWN1+"],         "FACE_8_MIRR",      (0.5,  0.5),  "NONE"),
    ("pelvis",    "bottom",            0,   0, 104, 16, 12, ["ALL"],                   "FACE_8_MIRR",      (0.5,  0.5),  "NONE"),
    ("upper_leg", "legL / legR",       0, 144,   0,  8, 16, ["ALL"],                   "FACE_8_MIRR",      (0.63, 1.06), "PARENT_ROTATE_SCALE"),
    ("shin",      "footL / footR",     0, 144,  16,  8, 12, ["ALL"],                   "FACE_8_MIRR",      (0.5,  0.75), "PARENT_ROTATE_CUT"),
    ("foot",      "toeL / toeR",       0, 144,  28, 12, 12, ["ALL"],                   "FACE_8_MIRR",      (0.5,  0.25), "ROTATE"),
    ("shoulder",  "armL / armR",       0, 208,   0,  8,  8, ["ALL"],                   "FACE_8_MIRR",      (0.38, 0.38), "ROTATE"),
    ("upper_arm", "armL / armR",       1, 208,   8,  8, 12, ["ALL"],                   "FACE_8_MIRR",      (0.5,  0.17), "ROTATE_CUT"),
    ("forearm",   "handL / handR",     0, 208,  20,  8,  8, ["ALL"],                   "FACE_8_MIRR",      (0.38, 0.75), "PARENT_ROTATE_SCALE"),
    ("fist",      "fingerL / fingerR", 0, 208,  28,  8,  8, ["ALL"],                   "FACE_8_MIRR",      (0.38, 0.38), "PARENT_ROTATE"),
]

COLS = ["S", "SE", "E", "NE", "N"]
# corpo em 4 direcoes: SE copia S, NE copia N. Cabeca desenha as 5 de verdade.
BODY_4DIR = {"top", "abdomen", "pelvis"}


# ------------------------------------------------------------- utilidades
def px(d, x, y, c):
    d.point((x, y), fill=c)


def rect(d, x0, y0, x1, y1, c):
    d.rectangle([x0, y0, x1, y1], fill=c)


def ellipse(d, x0, y0, x1, y1, c):
    d.ellipse([x0, y0, x1, y1], fill=c)


def new_cell(w, h):
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


# ------------------------------------------------------------- desenhos
def draw_head(direction, pitch_row):
    """16x16. Pivo (8, 2) -> o pescoco fica no topo, a cabeca pende para baixo."""
    im, d = new_cell(16, 16)
    dy = {"UP1+": -1, "ALL": 0, "DOWN1+": 1}[pitch_row]
    top = 1 + dy

    # cranio
    ellipse(d, 2, top, 13, top + 12, SKIN)
    ellipse(d, 3, top + 1, 12, top + 10, SKIN_HI)
    # sombra do lado direito da tela
    for y in range(top + 2, top + 12):
        px(d, 12, y, SKIN_SH)

    # cabelo: cobre mais o craneo conforme vira de costas
    hair_h = {"S": 4, "SE": 5, "E": 6, "NE": 9, "N": 11}[direction]
    ellipse(d, 2, top, 13, top + hair_h, HAIR)
    ellipse(d, 3, top, 12, top + hair_h - 2, HAIR_HI)

    if direction == "S":
        px(d, 5, top + 7, EYE); px(d, 6, top + 7, EYE)
        px(d, 9, top + 7, EYE); px(d, 10, top + 7, EYE)
        rect(d, 7, top + 10, 8, top + 10, SKIN_SH)
        px(d, 8, top + 8, FRONT_TAG)                      # nariz / marcador de frente
    elif direction == "SE":
        px(d, 6, top + 7, EYE); px(d, 7, top + 7, EYE)
        px(d, 10, top + 7, EYE)
        rect(d, 8, top + 10, 9, top + 10, SKIN_SH)
        px(d, 11, top + 8, FRONT_TAG)
    elif direction == "E":
        px(d, 9, top + 7, EYE); px(d, 10, top + 7, EYE)
        px(d, 13, top + 8, FRONT_TAG)                     # nariz de perfil
        px(d, 12, top + 10, SKIN_SH)
    elif direction == "NE":
        px(d, 4, top + 8, SKIN_SH); px(d, 4, top + 9, SKIN_SH)   # orelha
        px(d, 12, top + 9, BACK_TAG)
    elif direction == "N":
        px(d, 3, top + 8, SKIN_SH); px(d, 3, top + 9, SKIN_SH)
        px(d, 12, top + 8, SKIN_SH); px(d, 12, top + 9, SKIN_SH)
        px(d, 8, top + 11, BACK_TAG)
    return im


def draw_torso(direction, pitch_row):
    """16x16. Pivo (8, 4)."""
    im, d = new_cell(16, 16)
    dy = 1 if pitch_row == "DOWN1+" else 0
    narrow = {"S": 0, "SE": 1, "E": 3, "NE": 1, "N": 0}[direction]
    x0, x1 = 2 + narrow, 13 - narrow
    rect(d, x0, 2 + dy, x1, 14, CLOTH)
    rect(d, x0 + 1, 3 + dy, x1 - 1, 9, CLOTH_HI)
    rect(d, x0, 12, x1, 14, CLOTH_SH)
    for y in range(2 + dy, 15):
        px(d, x1, y, CLOTH_SH)
    if direction in ("S", "SE"):
        for y in range(4 + dy, 13):
            px(d, (x0 + x1) // 2, y, CLOTH_SH)            # fecho frontal
        px(d, (x0 + x1) // 2, 6 + dy, FRONT_TAG)
    if direction in ("N", "NE"):
        px(d, (x0 + x1) // 2, 6 + dy, BACK_TAG)
    return im


def draw_abdomen(direction, pitch_row):
    """16x12. Pivo (8, 6)."""
    im, d = new_cell(16, 12)
    dy = 1 if pitch_row == "DOWN1+" else 0
    narrow = {"S": 0, "SE": 1, "E": 2, "NE": 1, "N": 0}[direction]
    x0, x1 = 3 + narrow, 12 - narrow
    rect(d, x0, 1 + dy, x1, 10, CLOTH)
    rect(d, x0 + 1, 2 + dy, x1 - 1, 6, CLOTH_HI)
    for y in range(1 + dy, 11):
        px(d, x1, y, CLOTH_SH)
    if direction in ("S", "SE"):
        px(d, (x0 + x1) // 2, 4 + dy, FRONT_TAG)
    if direction in ("N", "NE"):
        px(d, (x0 + x1) // 2, 4 + dy, BACK_TAG)
    return im


def draw_pelvis(direction, pitch_row):
    """16x12. Pivo (8, 6)."""
    im, d = new_cell(16, 12)
    narrow = {"S": 0, "SE": 1, "E": 2, "NE": 1, "N": 0}[direction]
    x0, x1 = 3 + narrow, 12 - narrow
    rect(d, x0, 2, x1, 9, PANTS)
    rect(d, x0 + 1, 3, x1 - 1, 6, PANTS_HI)
    rect(d, x0, 8, x1, 9, PANTS_SH)
    for y in range(2, 10):
        px(d, x1, y, PANTS_SH)
    if direction in ("S", "SE"):
        px(d, (x0 + x1) // 2, 5, FRONT_TAG)
    if direction in ("N", "NE"):
        px(d, (x0 + x1) // 2, 5, BACK_TAG)
    return im


def draw_upper_leg(direction, pitch_row):
    """8x16. Pivo (5, 17) -> abaixo da celula; a arte e esticada quadril->joelho."""
    im, d = new_cell(8, 16)
    w = {"S": 0, "SE": 0, "E": 1, "NE": 0, "N": 0}[direction]
    x0, x1 = 1 + w, 6 - w
    rect(d, x0, 0, x1, 15, PANTS)
    rect(d, x0, 0, x0 + 1, 15, PANTS_HI)
    for y in range(0, 16):
        px(d, x1, y, PANTS_SH)
    if direction in ("S", "SE"):
        px(d, (x0 + x1) // 2, 2, FRONT_TAG)
    if direction in ("N", "NE"):
        px(d, (x0 + x1) // 2, 2, BACK_TAG)
    return im


def draw_shin(direction, pitch_row):
    """8x12. Pivo (4, 9)."""
    im, d = new_cell(8, 12)
    w = {"S": 0, "SE": 0, "E": 1, "NE": 0, "N": 0}[direction]
    x0, x1 = 2 + w, 5 - w
    rect(d, x0, 0, x1, 11, SKIN)
    px(d, x0, 0, SKIN_HI)
    for y in range(0, 12):
        px(d, x1, y, SKIN_SH)
    if direction in ("S", "SE"):
        px(d, x0, 3, FRONT_TAG)
    if direction in ("N", "NE"):
        px(d, x0, 3, BACK_TAG)
    return im


def draw_foot(direction, pitch_row):
    """12x12. Pivo (6, 3). O pe aponta para a frente da tela em S."""
    im, d = new_cell(12, 12)
    if direction in ("S", "SE"):
        rect(d, 3, 2, 8, 9, BOOT)
        rect(d, 3, 2, 8, 4, BOOT_HI)
        px(d, 5, 9, FRONT_TAG); px(d, 6, 9, FRONT_TAG)
    elif direction == "E":
        rect(d, 3, 3, 10, 7, BOOT)
        rect(d, 3, 3, 10, 4, BOOT_HI)
        px(d, 10, 6, FRONT_TAG)
    else:  # NE / N
        rect(d, 3, 2, 8, 8, BOOT)
        rect(d, 3, 2, 8, 3, BOOT_HI)
        px(d, 5, 2, BACK_TAG); px(d, 6, 2, BACK_TAG)
    return im


def draw_shoulder(direction, pitch_row):
    """8x8. Pivo (3, 3). Capa do ombro."""
    im, d = new_cell(8, 8)
    ellipse(d, 0, 0, 6, 6, CLOTH)
    ellipse(d, 1, 1, 4, 4, CLOTH_HI)
    px(d, 6, 5, CLOTH_SH)
    if direction in ("S", "SE"):
        px(d, 3, 5, FRONT_TAG)
    if direction in ("N", "NE"):
        px(d, 3, 5, BACK_TAG)
    return im


def draw_upper_arm(direction, pitch_row):
    """8x12. Pivo (4, 2) -> preso perto do topo, estica ombro->cotovelo."""
    im, d = new_cell(8, 12)
    w = {"S": 0, "SE": 0, "E": 1, "NE": 0, "N": 0}[direction]
    x0, x1 = 2 + w, 5 - w
    rect(d, x0, 0, x1, 11, CLOTH)
    for y in range(0, 12):
        px(d, x0, y, CLOTH_HI)
        px(d, x1, y, CLOTH_SH)
    if direction in ("S", "SE"):
        px(d, x0, 4, FRONT_TAG)
    if direction in ("N", "NE"):
        px(d, x0, 4, BACK_TAG)
    return im


def draw_forearm(direction, pitch_row):
    """8x8. Pivo (3, 6)."""
    im, d = new_cell(8, 8)
    w = {"S": 0, "SE": 0, "E": 1, "NE": 0, "N": 0}[direction]
    x0, x1 = 2 + w, 5 - w
    rect(d, x0, 0, x1, 7, SKIN)
    for y in range(0, 8):
        px(d, x0, y, SKIN_HI)
        px(d, x1, y, SKIN_SH)
    if direction in ("S", "SE"):
        px(d, x0, 2, FRONT_TAG)
    if direction in ("N", "NE"):
        px(d, x0, 2, BACK_TAG)
    return im


def draw_fist(direction, pitch_row):
    """8x8. Pivo (3, 3)."""
    im, d = new_cell(8, 8)
    ellipse(d, 1, 1, 6, 6, SKIN)
    ellipse(d, 1, 1, 4, 4, SKIN_HI)
    px(d, 6, 5, SKIN_SH)
    if direction in ("S", "SE"):
        px(d, 3, 6, FRONT_TAG)
    if direction in ("N", "NE"):
        px(d, 3, 6, BACK_TAG)
    return im


PAINTERS = {
    "head": draw_head,
    "top": draw_torso,
    "abdomen": draw_abdomen,
    "pelvis": draw_pelvis,
    "upper_leg": draw_upper_leg,
    "shin": draw_shin,
    "foot": draw_foot,
    "shoulder": draw_shoulder,
    "upper_arm": draw_upper_arm,
    "forearm": draw_forearm,
    "fist": draw_fist,
}


# --------------------------------------------------------------- atlas
def build_atlas():
    atlas = Image.new("RGBA", (ATLAS_W, ATLAS_H), CHROMA)
    for name, node, gfx, bx, by, w, h, rows, facing, pivot, texrot in BLOCKS:
        painter = PAINTERS[name]
        for r, pitch in enumerate(rows):
            for c, direction in enumerate(COLS):
                src = direction
                if name in BODY_4DIR:          # 4 direcoes: diagonais copiam o vizinho cardeal
                    src = {"S": "S", "SE": "S", "E": "E", "NE": "N", "N": "N"}[direction]
                cell = painter(src, pitch)
                atlas.paste(cell, (bx + c * w, by + r * h), cell)
    return atlas


def build_overlay():
    """Camada transparente 672x120: bordas de celula + pivo. Usar por cima no Aseprite."""
    ov = Image.new("RGBA", (ATLAS_W, ATLAS_H), (0, 0, 0, 0))
    d = ImageDraw.Draw(ov)
    grid = (0, 220, 255, 170)
    pivc = (255, 60, 60, 255)
    for name, node, gfx, bx, by, w, h, rows, facing, pivot, texrot in BLOCKS:
        for r in range(len(rows)):
            for c in range(len(COLS)):
                x0, y0 = bx + c * w, by + r * h
                d.rectangle([x0, y0, x0 + w - 1, y0 + h - 1], outline=grid)
                pxr = x0 + int(round(w * pivot[0]))
                pyr = y0 + int(round(h * pivot[1]))
                pyr = min(pyr, ATLAS_H - 1)
                d.point((min(pxr, ATLAS_W - 1), pyr), fill=pivc)
    return ov


# --------------------------------------------------------------- poster
def load_font(size, bold=False):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else ""),
              "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def build_guide(atlas):
    S = 7
    pad_l, pad_t = 70, 190
    W = 272 * S + pad_l + 70
    H = 1830
    g = Image.new("RGBA", (W, H), (22, 24, 30, 255))
    d = ImageDraw.Draw(g)
    f_ttl = load_font(36, True)
    f_h = load_font(20, True)
    f = load_font(15)
    f_s = load_font(13)
    f_b = load_font(15, True)

    ACC = (120, 210, 255)
    TXT = (222, 226, 234)
    DIM = (150, 156, 170)

    d.text((40, 30), "Gabarito Alabaster — monstro humanoide", font=f_ttl, fill=(240, 240, 245))
    for i, line in enumerate([
        "Atlas 672×120  ·  fundo chroma RGB(255,0,195) → vira alpha 0 no carregamento",
        "Colunas = direção  ·  linhas = faixa de pitch  ·  FACE_8_MIRR = 5 células únicas: S · SE · E · NE · N",
        "SW / W / NW são espelhos automáticos de SE / E / NE — o lado esquerdo nunca é desenhado.",
    ]):
        d.text((42, 84 + i * 24), line, font=f, fill=ACC if i else (200, 220, 240))

    view = atlas.crop((0, 0, 272, 120)).resize((272 * S, 120 * S), Image.NEAREST)
    g.paste(view, (pad_l, pad_t), view)

    grid = (0, 190, 255, 190)
    for idx, (name, node, gfx, bx, by, w, h, rows, facing, pivot, texrot) in enumerate(BLOCKS, start=1):
        for r in range(len(rows)):
            for c in range(len(COLS)):
                x0 = pad_l + (bx + c * w) * S
                y0 = pad_t + (by + r * h) * S
                d.rectangle([x0, y0, x0 + w * S - 1, y0 + h * S - 1], outline=grid)
                cx = x0 + int(w * S * pivot[0])
                cy = min(y0 + int(h * S * pivot[1]), pad_t + 120 * S - 1)
                d.line([cx - 4, cy, cx + 4, cy], fill=(255, 70, 70, 255), width=2)
                d.line([cx, cy - 4, cx, cy + 4], fill=(255, 70, 70, 255), width=2)
        # badge numerado no canto do bloco
        bxp, byp = pad_l + bx * S, pad_t + by * S
        d.rectangle([bxp, byp, bxp + 19, byp + 15], fill=(20, 22, 28, 235))
        d.text((bxp + 5, byp + 1), str(idx), font=f_b, fill=(255, 214, 120))

    # regua de colunas, uma por grupo (a largura da celula muda entre grupos)
    seen_groups = set()
    for name, node, gfx, bx, by, w, h, rows, facing, pivot, texrot in BLOCKS:
        if bx in seen_groups:
            continue
        seen_groups.add(bx)
        for c, cname in enumerate(COLS):
            x0 = pad_l + (bx + c * w) * S
            d.text((x0 + 2, pad_t - 24), ("col %d\n%s" % (c, cname)) if w >= 12 else cname,
                   font=f_s, fill=(255, 214, 120))

    # area livre
    d.text((pad_l + 86 * S, pad_t + 52 * S),
           "colunas 5–8 livres: é aqui que entram SSE/ESE/ENE/NNE\nse um dia esta peça virar FACE_16_MIRR",
           font=f_s, fill=(60, 20, 50))

    # ------------------------------------------------------------ tabela
    y = pad_t + 120 * S + 46
    d.text((42, y), "Blocos do atlas", font=f_h, fill=(245, 245, 250))
    y += 32
    cols_x = [46, 82, 200, 350, 420, 500, 590, 780, 900, 1010]
    heads = ["#", "peça", "bone(s)", "gfx", "origem", "célula", "linhas de pitch", "facing", "pivô", "texRotate"]
    for cx, ht in zip(cols_x, heads):
        d.text((cx, y), ht, font=f_b, fill=ACC)
    y += 22
    d.line([42, y, W - 60, y], fill=(60, 66, 80), width=1)
    y += 8
    for idx, (name, node, gfx, bx, by, w, h, rows, facing, pivot, texrot) in enumerate(BLOCKS, start=1):
        vals = [str(idx), name, node, "gfx%d" % gfx, "(%d,%d)" % (bx, by), "%d×%d" % (w, h),
                " / ".join(rows), facing, "%.2f / %.2f" % pivot, texrot]
        for cx, v in zip(cols_x, vals):
            d.text((cx, y), v, font=f_s, fill=TXT if cx > 46 else (255, 214, 120))
        y += 21
    y += 26

    # ------------------------------------------------------------ hierarquia
    d.text((42, y), "Hierarquia de bones (idêntica ao Male-Dummy / DEFAULT)", font=f_h, fill=(245, 245, 250))
    tree = [
        "root ──────────── abdômen (bloco 3)",
        " ├── top ───────── torso (bloco 2)",
        " │    ├── head ─── cabeça (bloco 1)",
        " │    ├── shoulderL ── armL ── handL ── fingerL ── weaponL (socket, sem pixels)",
        " │    └── shoulderR ── armR ── handR ── fingerR ── weaponR (socket, sem pixels)",
        " └── bottom ────── pélvis (bloco 4)",
        "      ├── hipL ── legL ── footL ── toeL",
        "      └── hipR ── legR ── footR ── toeR",
        "",
        "armL/armR carregam DOIS gráficos: gfx0 = capa do ombro (bloco 8), gfx1 = braço (bloco 9).",
        "handL/handR desenham o ANTEBRAÇO (bloco 10); fingerL/fingerR desenham a MÃO (bloco 11).",
        "footL/footR desenham a CANELA (bloco 6); toeL/toeR desenham o PÉ (bloco 7).",
    ]
    for i, line in enumerate(tree):
        d.text((60, y + 32 + i * 21), line, font=f, fill=TXT if not line.startswith(("armL", "handL", "footL")) else DIM)
    y += 32 + len(tree) * 21 + 26

    # ------------------------------------------------------------ regras
    d.text((42, y), "Regras que não podem ser quebradas", font=f_h, fill=(245, 245, 250))
    rules = [
        "1.  O PNG final precisa ter exatamente 672×120. O loader rejeita qualquer outro tamanho e cai no atlas de fallback.",
        "2.  Tudo que não é personagem fica em RGB(255,0,195) exato. Nada de anti-alias contra o magenta: gera borda rosa no jogo.",
        "3.  A cruz vermelha é o PIVÔ — é onde o bone encosta na arte. Desenhe a peça em volta da cruz, não centralizada na célula.",
        "     O pivô da coxa e do braço fica de propósito na borda ou fora da célula; isso é o que faz o membro esticar certo.",
        "4.  Colunas 0..4 = S, SE, E, NE, N. Oeste é espelho automático — nunca desenhe o lado esquerdo do corpo.",
        "5.  Corpo em 4 direções: desenhe só S, E e N; copie S→SE e N→NE. Para virar 8 direções de verdade depois,",
        "     é só repintar as duas cópias. Nenhuma linha de JSON muda.",
        "6.  A cabeça tem 3 linhas de pitch: linha 0 = UP1+ (olhando pra cima), linha 1 = ALL (neutro), linha 2 = DOWN1+ (pra baixo).",
        "     Torso e abdômen têm 2 (ALL, DOWN1+). Pélvis e membros têm 1 só.",
        "7.  Peças marcadas PARENT_ROTATE_SCALE / _CUT são esticadas e recortadas pelo runtime entre dois bones.",
        "     Desenhe-as retas e cheias no comprimento total; o motor faz o encurtamento em perspectiva sozinho.",
        "8.  Vermelho = marcador de frente, azul = marcador de costas. Servem só para achar direção invertida no teste.",
        "     Apague os dois quando a arte final entrar.",
        "9.  weaponL / weaponR são sockets sem pixels. Arma e ferramenta são figures separados, anexados a esses bones.",
        "10. Uma peça pode ter facing próprio. Cabeça em FACE_8_MIRR e pés em FACE_4_MIRR no mesmo personagem é legítimo,",
        "     e é exatamente o que a Juno original faz.",
    ]
    for i, line in enumerate(rules):
        d.text((60, y + 32 + i * 21), line, font=f, fill=TXT if line[:2].strip().rstrip(".").isdigit() else DIM)
    return g


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    atlas = build_atlas()
    atlas.save(os.path.join(out, "monster_humanoid_01.png"))
    build_overlay().save(os.path.join(out, "monster_template_overlay.png"))
    build_guide(atlas).save(os.path.join(out, "monster_template_guide.png"))
    print("ok ->", out)


if __name__ == "__main__":
    main()
