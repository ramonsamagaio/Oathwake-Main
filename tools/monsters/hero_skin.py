#!/usr/bin/env python3
"""
Skin do Heroi do Oathwake — REESCRITA, pixels escritos a mao.

Por que a versao anterior nao servia
------------------------------------
Ela GERAVA a arte com matematica (mascara afilada + rampa algoritmica). A
literatura de PCG e clara sobre o teto disso: Dave Bollinger, o trabalho de
referencia em pixel art procedural, teve que restringir 2^196 possibilidades ate
4e18 para que 999/1000 saidas fossem utilizaveis — todo o trabalho estava na
mascara, nao no gerador. Gillian Smith (Game AI Pro 2) descreve o dilema:
sobregeracao produz conteudo ilegivel, e corrigir isso leva a subgeracao, que
produz variacao apenas combinatoria.

Traduzindo para sprite de personagem: procedural resolve paleta, rampa e limpeza
de pixel orfao. Nao resolve POR ONDE passa o terminador, ONDE cai a sombra
projetada (queixo, cinto), nem legibilidade de silhueta — essas exigem semantica
de corpo, nao estatistica de pixel.

Entao aqui a arte e ESCRITA: cada peca e uma grade de caracteres, um caractere
por pixel, como um artista faz.

Estrutura doada pela Juno
-------------------------
Os tamanhos de celula, pivos e texRotate NAO sao invencao: sao copiados do
figure da Juno, que e arte acabada, feita a mao, autorada para este mesmo rig.
As pecas dela encaixam porque foram desenhadas para encaixar. Medido no atlas
dela: cabeca 20x20, tronco 12x12, pelve 12x12, membros 8x8 e 8x12 — as minhas
eram 26x26, 18x18 e ate 10x21, e era dai que vinha o inchaco.

5 colunas (FACE_8_MIRR): S, SE, E, NE, N. O oeste o runtime espelha sozinho.
"""

import math
import os

import carve

# Recorte direto do concept (carve.py): testado e REPROVADO para o corpo.
# No concept re-quantizado em 25px uma peca de 8px cai para ~6 pixels uteis e
# o ruido do requant (pele aparecendo no bracadeira, mecha no ombro) vira
# chiado no sprite. Para a CABECA o recorte ganha, porque ali a celula tem
# 22px e o desenho tem detalhe que sustenta. Para o corpo a grade escrita a
# mao le melhor. Fica desligado, mas fica documentado.
USE_CARVE = False

# Blocos que ignoram a direcao (ver o comentario em build_atlas).
UNIFORM = {"shoulder", "upper_arm", "forearm", "hand", "thigh", "shin", "foot"}


def _shade(img, k):
    if not k:
        return img
    p = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            c = p[x, y]
            if c[3]:
                p[x, y] = (max(0, min(255, c[0] + k)), max(0, min(255, c[1] + k)),
                           max(0, min(255, c[2] + k)), c[3])
    return img
import sys

from PIL import Image

CHROMA = (255, 0, 195, 255)
ATLAS_W, ATLAS_H = 672, 120
COLS = ["S", "SE", "E", "NE", "N"]

# ------------------------------------------------------------------ paleta
# Amostrada do concept. Rampa por MATERIAL, do claro ao escuro.
PAL = {
    "HAIR_TIP": (150, 106, 86), "HAIR_HI": (117, 82, 71), "HAIR_MID": (93, 63, 59),
    "HAIR": (79, 53, 53), "HAIR_DK": (43, 27, 34),

    "SKIN": (233, 179, 137), "SKIN_SH": (196, 140, 108),
    "SKIN_DK": (150, 100, 78), "SKIN_LN": (107, 74, 60),

    "TUNIC_HI": (104, 104, 134), "TUNIC": (74, 74, 100),
    "TUNIC_DK": (55, 54, 76), "TUNIC_DD": (36, 35, 52),

    "CLOTH": (213, 196, 181), "CLOTH_SH": (166, 152, 142),

    "LEATH_HI": (138, 90, 69), "LEATHER": (106, 65, 52),
    "LEATH_DK": (68, 41, 34), "LEATH_DD": (40, 24, 21),

    "PANTS_HI": (110, 102, 116), "PANTS": (87, 79, 90),
    "PANTS_DK": (62, 55, 66), "PANTS_DD": (40, 35, 44),

    "BOOT_HI": (121, 92, 82), "BOOT": (86, 64, 57),
    "BOOT_DK": (52, 38, 34), "BOOT_DD": (32, 23, 21),

    "GOLD": (238, 183, 87), "GOLD_DK": (168, 122, 46),
    "EYE_W": (232, 232, 240), "EYE": (46, 50, 66),
}

# --- sistema de grade -------------------------------------------------------
# Cada peca e escrita como grade de caracteres, um caractere por pixel.
#
# Os DIGITOS sao niveis da rampa do material da peca, nao cores fixas — assim a
# mesma grade serve para pano, couro ou calca, e a rampa vira parametro:
#
#   .  transparente
#   0  contorno   (versao escurecida do tom mais escuro — nunca preto puro)
#   1  luz
#   2  meio (base)
#   3  sombra
#   4  nucleo / sombra profunda
#   5  luz refletida (entre o meio e a sombra; NUNCA mais clara que o meio)
#
# As LETRAS sao acentos que quebram o material da peca:
#   U u  camisa creme          X x  metal dourado
#   Q q w  pele (luz/sombra/escuro)
#   L l  couro (claro/escuro)  P p  calca (claro/escuro)
#   Z z  olho (branco/iris)
#   H h  cabelo (medio/escuro)

ACCENT = {
    "U": "CLOTH", "u": "CLOTH_SH",
    "X": "GOLD", "x": "GOLD_DK",
    "Q": "SKIN", "q": "SKIN_SH", "w": "SKIN_DK",
    "L": "LEATHER", "l": "LEATH_DK",
    "P": "PANTS", "p": "PANTS_DK",
    "Z": "EYE_W", "z": "EYE",
    "H": "HAIR_MID", "h": "HAIR_DK",
}

# Rampas por material: (luz, meio, sombra, nucleo). O contorno e derivado.
# ---------------------------------------------------------------------------
# ESCADA DE VALOR
#
# Medido, a versao anterior tinha o corpo inteiro no mesmo valor:
#
#     tronco (TUNIC)   L* 32
#     braco  (LEATHER) L* 32      -> dL* = 0
#     manga  (TUNIC)   L* 32      -> dL* = 0   (mesma cor do tronco!)
#     calca  (PANTS)   L* 35
#     bota   (BOOT)    L* 29      -> dL* = 5
#
# Piso de legibilidade onde duas pecas se TOCAM: dL* >= 12. Nenhuma emenda
# passava. E por isso que "os membros se confundem com o corpo" — nao e a
# silhueta nem o encaixe, e luminancia. Matiz nao separa peca em sprite
# pequeno; valor separa.
#
# A Juno faz exatamente isto: cabeca clara, braco CLARO, jaqueta escura,
# calca media, bota escura. A escada abaixo copia a estrutura dela mantendo as
# cores do concept — so o L* muda, em OKLCh (mexer em HSV clarearia e
# dessaturaria junto).
VALOR_ALVO = {
    # As pecas formam DUAS CADEIAS independentes, e so quem se toca precisa de
    # degrau. Tratar tudo como uma escada unica espremia 6 materiais em 20
    # pontos de L* e algum par sempre reprovava.
    #
    #   braco:  tronco 24 -> manga 38 -> bracadeira 50 -> mao 77
    #           dL*        14          12          27
    #   perna:  calca 22 -> bota 34    (o cinto separa a perna do tronco)
    #           dL*        12
    #
    # A bracadeira deixou de ser COURO e virou o mesmo azul da manga, mais
    # clara. Motivo medido: com couro, o realce dele caia em L* ~63 e o tom de
    # sombra da pele e L* 63.3 — a mesma cor, e o antebraco lia como braco nu.
    # Separar por matiz (azul contra pele quente) resolve o que o valor sozinho
    # nao resolvia. E a mesma solucao da Juno: antebraco de armadura cinza, mao
    # de pele.
    #
    # A bota foi de 12 para 34: em 12 ela ficava em L* 12.2 contra um fundo de
    # L* 10.3 — dL* 1.9, o pe era invisivel. Em 46 (primeira tentativa) ela
    # ficou mais clara que a pele e passou a ler como pe descalco. 34 e o valor
    # do couro no proprio concept.
    "TUNIC":   24,
    "SLEEVE":  38,
    # 50, e nao mais: a partir daqui o realce da bracadeira encosta no tom de
    # sombra da pele. O que separa mao de bracadeira aqui NAO e o valor (dL* 13
    # do lado da luz, quase zero do lado da sombra) — e o MATIZ: 284 graus de
    # azul contra 51 de pele quente, 127 graus de distancia em OKLCh. Regra:
    # valor separa matizes parecidos, matiz separa valores parecidos.
    "VAMB":    50,
    "PANTS":   22,
    "BOOT":    34,
    "LEATH":   46,
}


def _retone(keys, alvo):
    """Desloca a rampa inteira ate o tom do meio bater com o L* alvo.

    Em OKLCh: mexer a luminancia ali nao arrasta croma nem matiz junto, que e o
    que acontece se voce mexer em HSV.
    """
    from coloraide import Color
    def lab_l(c):
        return Color("srgb", [v / 255.0 for v in c[:3]]).convert("lab")["lightness"]
    mid = PAL[keys[1]]
    lo, hi = 0.0, 1.6
    for _ in range(40):
        k = (lo + hi) / 2
        c = Color("srgb", [v / 255.0 for v in mid]).convert("oklch")
        c["lightness"] = min(1.0, c["lightness"] * k)
        if lab_l(tuple(int(round(v * 255)) for v in c.convert("srgb")[:3])) < alvo:
            lo = k
        else:
            hi = k
    k = (lo + hi) / 2
    for key in keys:
        c = Color("srgb", [v / 255.0 for v in PAL[key]]).convert("oklch")
        c["lightness"] = min(1.0, c["lightness"] * k)
        PAL[key] = tuple(max(0, min(255, int(round(v * 255)))) for v in c.convert("srgb")[:3])


PAL["VAMB_HI"] = PAL["TUNIC_HI"]
PAL["VAMB"] = PAL["TUNIC"]
PAL["VAMB_DK"] = PAL["TUNIC_DK"]
PAL["VAMB_DD"] = PAL["TUNIC_DD"]
PAL["SLEEVE_HI"] = PAL["TUNIC_HI"]
PAL["SLEEVE"] = PAL["TUNIC"]
PAL["SLEEVE_DK"] = PAL["TUNIC_DK"]
PAL["SLEEVE_DD"] = PAL["TUNIC_DD"]
_retone(["TUNIC_HI", "TUNIC", "TUNIC_DK", "TUNIC_DD"], VALOR_ALVO["TUNIC"])
_retone(["LEATH_HI", "LEATHER", "LEATH_DK", "LEATH_DD"], VALOR_ALVO["LEATH"])
_retone(["SLEEVE_HI", "SLEEVE", "SLEEVE_DK", "SLEEVE_DD"], VALOR_ALVO["SLEEVE"])
_retone(["VAMB_HI", "VAMB", "VAMB_DK", "VAMB_DD"], VALOR_ALVO["VAMB"])
_retone(["PANTS_HI", "PANTS", "PANTS_DK", "PANTS_DD"], VALOR_ALVO["PANTS"])
_retone(["BOOT_HI", "BOOT", "BOOT_DK", "BOOT_DD"], VALOR_ALVO["BOOT"])

RAMPS = {
    "tunic":   ("TUNIC_HI", "TUNIC", "TUNIC_DK", "TUNIC_DD"),
    "sleeve":  ("SLEEVE_HI", "SLEEVE", "SLEEVE_DK", "SLEEVE_DD"),
    "vamb":    ("VAMB_HI", "VAMB", "VAMB_DK", "VAMB_DD"),
    "leather": ("LEATH_HI", "LEATHER", "LEATH_DK", "LEATH_DD"),
    "pants":   ("PANTS_HI", "PANTS", "PANTS_DK", "PANTS_DD"),
    "boot":    ("BOOT_HI", "BOOT", "BOOT_DK", "BOOT_DD"),
    "skin":    ("SKIN", "SKIN_SH", "SKIN_DK", "SKIN_LN"),
    # atencao a ordem: HAIR_MID e mais CLARO que HAIR, entao a rampa vai
    # HI > MID > HAIR > DK, nao na ordem dos nomes
    "hair":    ("HAIR_HI", "HAIR_MID", "HAIR", "HAIR_DK"),
    "cloth":   ("CLOTH", "CLOTH_SH", "LEATH_DK", "LEATH_DD"),
}


def _dark(c, k=22):
    return (max(0, c[0] - k), max(0, c[1] - k), max(0, c[2] - k), 255)


def _rgba(key):
    c = PAL[key]
    return (c[0], c[1], c[2], 255)


def grid(rows, material="pants"):
    """Grade de caracteres -> imagem RGBA, usando a rampa do material."""
    hi, mid, sh, core = (_rgba(k) for k in RAMPS[material])
    lut = {
        "0": _dark(core, 5),       # contorno: mal mais escuro que o nucleo
        "1": hi, "2": mid, "3": sh, "4": core,
        "5": sh,                   # luz refletida: mesmo nivel da sombra
        # 6 = painel interno mais claro, na rampa "sleeve". Serve pra dar
        # valor ao meio de uma peca grande sem inventar cor nova.
        "6": _rgba("SLEEVE"), "7": _rgba("SLEEVE_HI"),
    }
    for ch, key in ACCENT.items():
        lut[ch] = _rgba(key)
    h = len(rows)
    w = max((len(r) for r in rows), default=0)
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    p = im.load()
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            c = lut.get(ch)
            if c is not None:
                p[x, y] = c
    return im


def pad(im, w, h, dx=0, dy=0):
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(im, (dx, dy))
    return out


def mirror(rows):
    """Espelha uma grade horizontalmente, preservando o comprimento."""
    w = max(len(r) for r in rows)
    return ["".join(reversed(r.ljust(w, "."))) for r in rows]


# ============================================================ MEMBROS
# Layout de coluna vindo da geometria, nao de gosto: com luz a 45 graus o
# terminador de um cilindro cai a cos(45)=0.71 do raio, ou seja 1px PARA DENTRO
# da borda. O pixel da borda e luz refletida. Se o tom mais escuro tocar a
# silhueta, o membro le como retangulo chanfrado.
#
#   5px -> 1 2 2 3 5      4px -> 1 2 3 5      3px -> 1 2 3
#
# E o terminador desliza 1px no meio do comprimento: terminador perfeitamente
# vertical le como face plana, nao como tubo.

# --- coxa: 8x12, pivo (0.38, 0.83). Topo aberto (mora dentro da pelve).
THIGH = {
"S": [
 "..12234.",
 "..12234.",
 "..12234.",
 "..12234.",
 "..12234.",
 "..12234.",
 "..11223.",
 "..11223.",
 "..11223.",
 "..11223.",
 "..12233.",
 "..00000.",
],
"SE": [
 "..12235.",
 "..12235.",
 ".0122350",
 ".0122350",
 ".0122350",
 ".0112350",
 ".0112230",
 ".0112230",
 ".0112230",
 ".0122330",
 ".0122330",
 "..0000..",
],
"E": [
 "..1235..",
 "..1235..",
 ".012350.",
 ".012350.",
 ".012350.",
 ".012350.",
 ".011230.",
 ".011230.",
 ".011230.",
 ".011230.",
 ".012330.",
 "..000...",
],
"NE": [
 "..22335.",
 "..22335.",
 ".0223350",
 ".0223350",
 ".0223350",
 ".0223350",
 ".0222330",
 ".0222330",
 ".0222330",
 ".0222330",
 ".0233440",
 "..0000..",
],
"N": [
 "..22334.",
 "..22334.",
 ".0223340",
 ".0223340",
 ".0223340",
 ".0223340",
 ".0223340",
 ".0223340",
 ".0223340",
 ".0223340",
 ".0233440",
 "..0000..",
],
}

# --- canela: 8x12, pivo (0.50, 0.75). As 3 ultimas linhas sao o cano da bota,
#     e e esse cano que transborda por baixo do tornozelo e cobre a emenda.
SHIN = {
"S": [
 "..12234.",
 "..12234.",
 "..12234.",
 "..12234.",
 "..11223.",
 "..11223.",
 "..LLLLL.",
 "..lllll.",
 "..11223.",
 "..11223.",
 "..12233.",
 "..00000.",
],
"SE": [
 "..12235.",
 "..12235.",
 ".0122350",
 ".0122350",
 ".0112230",
 ".0112230",
 ".0112230",
 ".0112230",
 ".0LLLLl0",
 ".0122350",
 ".0122330",
 "..0000..",
],
"E": [
 "..1235..",
 "..1235..",
 ".012350.",
 ".012350.",
 ".011230.",
 ".011230.",
 ".011230.",
 ".011230.",
 ".0LLLl0.",
 ".012350.",
 ".012330.",
 "..000...",
],
"NE": [
 "..22335.",
 "..22335.",
 ".0223350",
 ".0223350",
 ".0222330",
 ".0222330",
 ".0222330",
 ".0222330",
 ".0lLLll0",
 ".0223350",
 ".0233440",
 "..0000..",
],
"N": [
 "..22334.",
 "..22334.",
 ".0223340",
 ".0223340",
 ".0223340",
 ".0223340",
 ".0223340",
 ".0223340",
 ".0llll10",
 ".0223340",
 ".0233440",
 "..0000..",
],
}

# --- bota: 8x8, pivo (0.25, 0.38), texRotate NONE.
#
# NONE, nao ROTATE — e a correcao do defeito "a perna vira de lado de frente".
# Numa camera top-down de 45 graus, avancar e subir produzem o MESMO movimento
# na tela (vertical). Nao existe eixo de tela onde "pra frente" seja distinguivel
# de "pra cima", entao o pe girado vira a unica pista de direcao e o personagem
# le como se tivesse virado de perfil. A bota nao gira: ela encurta e alarga.
FOOT = {
"S": [
 "..1223..",
 "..1223..",
 "..1223..",
 ".012230.",
 "0122335.",
 "0122335.",
 "0123345.",
 ".000000.",
],
"SE": [
 "..1223..",
 ".012230.",
 ".0122350",
 "01223350",
 "01223350",
 "01233450",
 ".0000000",
 "........",
],
"E": [
 "...122..",
 "..01230.",
 ".0122350",
 "01223350",
 "01223350",
 "01233450",
 ".0000000",
 "........",
],
"NE": [
 "..2233..",
 ".022330.",
 ".0223340",
 "02233440",
 "02233440",
 "02334440",
 ".0000000",
 "........",
],
"N": [
 "..2233..",
 ".022330.",
 ".022334.",
 "0223344.",
 "0223344.",
 "0233444.",
 ".000000.",
 "........",
],
}

# --- ombreira de couro: 8x8, pivo (0.38, 0.38), texRotate ROTATE (como a Juno).
SHOULDER = {
"S": [
 "...1223.",
 "..112230",
 "..122350",
 "..112350",
 "...0000.",
 "........",
 "........",
 "........",
],
"SE": [
 "..1122..",
 ".0112230",
 "01122350",
 "01122350",
 ".0122350",
 "..00000.",
 "........",
 "........",
],
"E": [
 "..112...",
 ".011230.",
 ".011233 ".replace(" ","5"),
 ".011233 ".replace(" ","5"),
 "..01230.",
 "..0000..",
 "........",
 "........",
],
"NE": [
 "..2233..",
 ".0223340",
 "02233440",
 "02233440",
 ".0233440",
 "..00000.",
 "........",
 "........",
],
"N": [
 "..2233..",
 ".0223340",
 "02233440",
 "02233440",
 ".0233440",
 "..00000.",
 "........",
 "........",
],
}

# --- braco (manga da tunica): 8x10, pivo (0.38, 1.0), PARENT_ROTATE_SCALE.
#     O punho creme dobrado nas 2 ultimas linhas e o marcador do concept.
UPPER_ARM = {
# 6 linhas de arte em celula de 10: com pivo Y 1.0 o corte proximal nao age,
# entao o comprimento do desenho E o comprimento do membro na tela.
"S": [
 "........",
 "........",
 "........",
 "........",
 "..1223..",
 "..1223..",
 "..1123..",
 "..1123..",
 "..1u23..",
 "...00...",
],
"SE": [
 "..1223..",
 "..1223..",
 ".012230.",
 ".012230.",
 ".011230.",
 ".011230.",
 ".011230.",
 ".01uuu0.",
 ".0uu230.",
 "..000...",
],
"E": [
 "..123...",
 "..123...",
 ".01230..",
 ".01230..",
 ".01120..",
 ".01120..",
 ".01120..",
 ".0UUu0..",
 ".0Uuu0..",
 "..00....",
],
"NE": [
 "..2233..",
 "..2233..",
 ".022330.",
 ".022330.",
 ".022330.",
 ".022330.",
 ".022330.",
 ".0uUUu0.",
 ".0uuuu0.",
 "..000...",
],
"N": [
 "..2233..",
 "..2233..",
 ".022340.",
 ".022340.",
 ".022340.",
 ".022340.",
 ".022340.",
 ".0uuuu0.",
 ".0uuuu0.",
 "..000...",
],
}

# --- antebraco (bracadeira de couro): 8x8, pivo (0.38, 1.0), PARENT_ROTATE_SCALE.
FOREARM = {
# 5 linhas de arte em celula de 8, pelo mesmo motivo do UPPER_ARM.
"S": [
 ".01223..",
 ".012230.",
 ".012230.",
 ".012230.",
 ".012230.",
 ".011230.",
 ".011230.",
 "..0000..",
],
"SE": [
 "..1223..",
 ".012230.",
 ".012230.",
 ".0ll230.",
 ".011230.",
 ".011230.",
 ".011230.",
 "..000...",
],
"E": [
 "..123...",
 ".01230..",
 ".01230..",
 ".0hhh0..",
 ".01120..",
 ".01120..",
 ".0hhh0..",
 "..00....",
],
"NE": [
 "..2233..",
 ".022330.",
 ".022330.",
 ".0hhhh0.",
 ".022330.",
 ".022330.",
 ".0hhhh0.",
 "..000...",
],
"N": [
 "..2233..",
 ".022340.",
 ".022340.",
 ".0hhhh0.",
 ".022340.",
 ".022340.",
 ".0hhhh0.",
 "..000...",
],
}

# --- mao: 8x8, pivo (0.38, 0.50), PARENT_ROTATE. Pele em sombra: a mao nao pode
#     competir com o rosto pelo ponto mais claro do sprite.
HAND = {
"S": [
 ".0qqq0..",
 ".0Qqqw..",
 ".0Qqqw..",
 ".0Qqqw..",
 ".0qqww..",
 ".0qww0..",
 "..000...",
 "........",
],
"SE": [
 "........",
 "..qqq...",
 ".0qQqw0.",
 ".0qQqw0.",
 ".0qqww0.",
 "..000...",
 "........",
 "........",
],
"E": [
 "........",
 "..qq....",
 ".0qQw0..",
 ".0qQw0..",
 ".0qww0..",
 "..00....",
 "........",
 "........",
],
"NE": [
 "........",
 "..qqq...",
 ".0qqww0.",
 ".0qqww0.",
 ".0qwww0.",
 "..000...",
 "........",
 "........",
],
"N": [
 "........",
 "..qqq...",
 ".0qqww0.",
 ".0qwww0.",
 ".0wwww0.",
 "..000...",
 "........",
 "........",
],
}


# ============================================================ CORPO
# Tamanhos copiados da Juno: tronco 12x12, pelve 12x12, abdomen 12x10.
# Massa de 10px -> 4 tons (regra: tons ~= largura/2, teto de 4).

# --- tronco: 12x12, pivo (0.5, 0.33). Gola em V com a camisa creme, correia
#     diagonal e ombro caido — os tres marcadores do concept.
TORSO = {
# Estrutura copiada da ARQUITETURA da Juno, nao do desenho dela:
#   linha 0-1  pescoco em pele + gola clara -> fecha o buraco preto que ficava
#              entre o queixo e o peito
#   linha 2-8  peito com um PAINEL central mais claro (digito 6 = rampa sleeve).
#              O tronco inteiro no tom escuro virava um vazio; a Juno resolve
#              com a camisa clara dentro da jaqueta escura.
#   linha 9-10 cinto
# Colunas 0 e 11 vazias: e o VAZIO DE 1PX que separa tronco de braco. Sem ele,
# dois volumes encostados, mesmo com dL* 12, ainda leem como um bloco so.
"S": [
 "..0wQQw0....",
 "..0UccU0....",
 ".0L12233440.",
 ".01L2233440.",
 ".011L233440.",
 ".0112L33440.",
 ".01122L3440.",
 ".011223L440.",
 ".0112233L40.",
 ".0LLLLLLLL0.",
 ".0lllXXlll0.",
 "..00000000..",
],
"SE": [
 "..12223345..",
 ".0122UU3450.",
 "0112UUh23450",
 "0112Uh223450",
 "01122h223450",
 "01122h233450",
 "011223h33450",
 "011223h34450",
 "0112233h4450",
 "0LLLLLLLL450",
 "0llllllll450",
 "..00000000..",
],
"E": [
 "...122334...",
 "..01223450..",
 "..0122h3450.",
 "..012h23450.",
 "..0122234 0.".replace(" ","5"),
 "..012233450.",
 "..012233450.",
 "..012234450.",
 "..012234450.",
 "..0LLLLLL50.",
 "..0llllll50.",
 "...000000...",
],
"NE": [
 "..22233445..",
 ".0223344500.".replace("00.",".0."),
 "022333445 50".replace(" ","4"),
 "0223h3445450",
 "022h33445450",
 "02h333445450",
 "0223344 5450".replace(" ","4"),
 "022334445450",
 "022334445450",
 "0LLLLLLLL450",
 "0llllllll450",
 "..00000000..",
],
"N": [
 "..22233445..",
 ".0223344450.",
 "022333444450",
 "022333444450",
 "022h33444450",
 "0223h3444450",
 "02233h444450",
 "022334444450",
 "022334444450",
 "0LLLLLLLL450",
 "0llllllll450",
 "..00000000..",
],
}

# --- abdomen: 12x10, pivo (0.5, 0.30). Cinto largo com a fivela dourada.
ABDOMEN = {
# SEM cinto. O cinto ja esta na base do torso e no topo da pelve; medido, o
# no do abdomen cai 3.4px abaixo do queixo, entao um terceiro cinto ali fecha
# uma barra marrom logo debaixo do rosto e o peito some. Um cinto por corpo.
"S": [
 ".0112233450.",
 "011223334450",
 "01122L334450",
 "011223L34450",
 "0112233L4450",
 "011223334L50",
 "011223334450",
 ".0122334450.",
 "..00000000..",
 "............",
],
"SE": [
 ".0112233450.",
 "011223334450",
 "0LLLLLLLLL50",
 "0LLLLXXLLL50",
 "0llllXXlll50",
 "011223334450",
 "011223334450",
 ".0122334450.",
 "..00000000..",
 "............",
],
"E": [
 "..01223450..",
 "..0122334 0.".replace(" ","5"),
 "..0LLLLLL50.",
 "..0LLLLXL50.",
 "..0llllxl50.",
 "..0122334 0.".replace(" ","5"),
 "..012233450.",
 "..01223450..",
 "...000000...",
 "............",
],
"NE": [
 ".0223344450.",
 "022334444450",
 "0LLLLLLLLL50",
 "0LLLLLLLLL50",
 "0lllllllll50",
 "022334444450",
 "022334444450",
 ".0233444450.",
 "..00000000..",
 "............",
],
"N": [
 ".0223344450.",
 "022334444450",
 "0LLLLLLLLL50",
 "0LLLLLLLLL50",
 "0lllllllll50",
 "022334444450",
 "022334444450",
 ".0233444450.",
 "..00000000..",
 "............",
],
}

# --- pelve: 12x12, pivo (0.5, 0.42). SO 7 linhas usadas: medido no concept, o
#     quadril e o joelho estao a ~11px, entao a pelve nao pode passar disso ou
#     engole a coxa. As duas abas descem por cima do topo de cada coxa.
PELVIS = {
"S": [
 ".0LLLLLLLL0.",
 ".0lllXXlll0.",
 ".0112233440.",
 ".0112233440.",
 ".0112233440.",
 ".0112233440.",
 ".01122.3440.",
 "..011.033...",
 "............",
 "............",
 "............",
 "............",
],
"SE": [
 "0LLLLLLLLL50",
 "011223334450",
 "011223334450",
 "011223334450",
 "01123.033450",
 "0110...03450",
 "..0.....00..",
 "............",
 "............",
 "............",
 "............",
 "............",
],
"E": [
 "..0LLLLLL50.",
 "..012233450.",
 "..012233450.",
 "..012233450.",
 "..012233450.",
 "..01223 450.".replace(" ","3"),
 "...000000...",
 "............",
 "............",
 "............",
 "............",
 "............",
],
"NE": [
 "0LLLLLLLLL50",
 "022334444450",
 "022334444450",
 "022334444450",
 "02233.044450",
 "0220...04450",
 "..0.....00..",
 "............",
 "............",
 "............",
 "............",
 "............",
],
"N": [
 "0LLLLLLLLL50",
 "022334444450",
 "022334444450",
 "022334444450",
 "02233.044450",
 "0220...04450",
 "..0.....00..",
 "............",
 "............",
 "............",
 "............",
 "............",
],
}

# --- bolsa de cinto: 8x10, pivo (0.5, 0.20). Fica no quadril direito dele.
POUCH = {
"S": [
 "........",
 ".011220.",
 ".0hhhh0.",
 ".012230.",
 ".01X230.",
 ".012230.",
 ".012330.",
 "..0000..",
 "........",
 "........",
],
"SE": [
 "........",
 ".011220.",
 ".0hhhh0.",
 ".012230.",
 ".01X230.",
 ".012230.",
 ".012330.",
 "..0000..",
 "........",
 "........",
],
"E": [
 "........",
 "..0110..",
 "..0hh0..",
 "..0120..",
 "..0X20..",
 "..0120..",
 "..0130..",
 "...00...",
 "........",
 "........",
],
"NE": [
 "........",
 ".022330.",
 ".0hhhh0.",
 ".023340.",
 ".023340.",
 ".023340.",
 ".023440.",
 "..0000..",
 "........",
 "........",
],
"N": [
 "........",
 ".022330.",
 ".0hhhh0.",
 ".023340.",
 ".023340.",
 ".023340.",
 ".023440.",
 "..0000..",
 "........",
 "........",
],
}


# ============================================================ CABECA
# 20x20, pivo (0.5, 0.5) — exatamente a celula da Juno. O no cai na linha 10.
#
# A versao anterior usava 26x26 recortado do concept. Ficava fiel mas punha o
# personagem em 72px de altura contra os 48px da Juno: ele nao pertencia a mesma
# tela. Aqui a cabeca e REDESENHADA na celula dela, guardando os marcadores que
# identificam o personagem: massa de cabelo espetada e assimetrica, franja
# caindo sobre a testa, rosto pequeno, dois olhos grandes e escuros com um unico
# pixel de brilho.
#
# Rampa "hair": 1=claro 2=medio 3=base 4=escuro 0=contorno.
# Acentos: Q pele, q pele-sombra, w pele-escura, z iris, Z brilho.

# A cabeca NAO e redesenhada: sao os pixels do concept, em camadas.
#
# Tentei redesenhar em 20x20 (a celula da Juno) e a identidade se perdeu — o
# cabelo virou pente e o rosto ficou grande demais. O concept ja e a melhor arte
# de cabeca que existe pra este personagem; o que faltava era o CORPO estar na
# escala certa, e isso as pecas escritas a mao acima resolvem.
#
# Solucao: corpo na escala da Juno, cabeca com os pixels do concept numa celula
# de 24x24 (contra 26x26 antes). O personagem fecha em ~52px, contra 72px da
# versao anterior e 48px da Juno.
#
# As camadas (cabelo / rosto / franja) deslizam independentes com o angulo:
# o rosto anda ate a borda e some, o cabelo anda menos porque esta mais perto do
# eixo. Girar por projecao cilindrica pixel a pixel NAO funciona — o concept nao
# tem nuca pra amostrar e vira borrao.

HEAD_W, HEAD_H = 20, 20
# concept25.png = o concept de 971x1619 re-quantizado em 25x58 (hero/requant.py),
# nao o 30x70 reduzido. Reduzir arte ja quantizada come mecha; voltar ao
# original e refazer a media de area preserva a silhueta.
CONCEPT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                            "hero", "concept23.png")
# Recorte 25x26 do concept, com as caixas nas coordenadas DESTE recorte.
# Tentei apertar em 24x24 pra encolher o personagem e os pontos de referencia
# sairam do lugar: a franja espalhou e o rosto sumiu. O tamanho da CELULA nao e
# o que controla a altura do personagem — quem controla e o PIVO. Com pivo 0.5
# (o da Juno) o no da cabeca cai no meio do cranio, metade do cabelo fica acima
# e o personagem fecha em ~49px, contra os 72px de antes.
HEAD_SRC_BOX = (2, 0, 22, 20)
FACE_BOX = (6, 13, 14, 19)         # rosto
FRINGE_BOX = (4, 10, 16, 17)       # mechas que caem sobre a testa
_LAYERS = None


def _compact(pts, src, w, h):
    """Tira os pixels de cabelo que estao soltos na borda.

    O cabelo do concept e uma massa ARFJADA: mechas de 1px espalhadas alem da
    silhueta. Em alta resolucao isso e textura; em 20px vira uma nuvem com
    buracos, e o olho le a extensao externa — por isso o heroi parecia bem
    maior que a Juno mesmo com altura medida quase igual (54.5 contra 52.5).
    O capacete da Juno e uma forma COMPACTA; e disso que vem a leitura de
    tamanho.

    Um pixel com menos de 3 vizinhos opacos nao sustenta forma: sai.
    """
    keep = set(pts)
    for _ in range(2):
        nxt = set()
        for (x, y) in keep:
            n = sum(1 for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                    if (dx or dy) and (x + dx, y + dy) in keep)
            if n >= 3:
                nxt.add((x, y))
        keep = nxt
    return keep


def _head_layers():
    """Separa o recorte da cabeca em (cabelo, rosto, franja).

    Por COORDENADA, nunca por cor: as mechas claras do cabelo passam em qualquer
    teste de "isto e pele" e o rosto acaba engolindo a cabeca inteira.
    """
    global _LAYERS
    if _LAYERS is not None:
        return _LAYERS
    src = Image.open(CONCEPT_PATH).convert("RGBA").crop(HEAD_SRC_BOX)
    w, h = src.size
    p = src.load()
    fx0, fy0, fx1, fy1 = FACE_BOX
    gx0, gy0, gx1, gy1 = FRINGE_BOX
    face, fringe, hair = set(), set(), set()
    for y in range(h):
        for x in range(w):
            if p[x, y][3] == 0:
                continue
            if fx0 <= x <= fx1 and fy0 <= y <= fy1:
                face.add((x, y))
            elif gx0 <= x <= gx1 and gy0 <= y <= gy1:
                fringe.add((x, y))
            else:
                hair.add((x, y))
    hair = _compact(hair, src, w, h)
    out = []
    for pts in (hair, face, fringe):
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        ip = img.load()
        for (x, y) in pts:
            c = p[x, y]
            ip[x, y] = (c[0], c[1], c[2], 255)   # alpha duro: ver _harden
        out.append(img)
    _LAYERS = (out[0], out[1], out[2], w, h)
    return _LAYERS


def _squeeze(img, sx, dx, dy=0):
    """Aperta horizontalmente e desloca. NEAREST de proposito: interpolar aqui
    inventa cor que nao existe na paleta."""
    w, h = img.size
    nw = max(1, int(round(w * sx)))
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(img.resize((nw, h), Image.NEAREST),
                        (int(round((w - nw) / 2 + dx)), int(round(dy))))
    return out


def _shade(img, k):
    if k == 0:
        return img
    p = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            c = p[x, y]
            if c[3]:
                p[x, y] = (max(0, min(255, c[0] + k)), max(0, min(255, c[1] + k)),
                           max(0, min(255, c[2] + k)), c[3])
    return img


def draw_head(v):
    """v = 0 (S) .. 4 (N). v=0 devolve a cabeca do concept pixel por pixel.

    ANTROPOMETRIA, nao intuicao. Medido (ANSUR II, percentil 50):

        tronco   perfil = 50% da largura frontal
        quadril  perfil = 62%
        braco/perna     = 100%   (secao circular)
        CABECA   perfil = 130%   (largura 154mm x comprimento 200mm)

    A versao anterior APERTAVA a cabeca horizontalmente nas diagonais, como se
    fosse um tronco. E o contrario: de perfil a cabeca e a unica peca que fica
    MAIOR, porque o cranio e mais comprido do que largo. E o rosto nao encolhe
    em direcao ao centro — ele DESLIZA para a borda proxima e o lado distante
    some atras da macã do rosto. Apertar produzia exatamente o que se via: uma
    tira vertical de pele no meio de um borrao de cabelo.
    """
    hair, face, fringe, sw, sh = _head_layers()
    phi = (v / 4.0) * math.pi
    sa, ca = math.sin(phi), math.cos(phi)
    im = Image.new("RGBA", (HEAD_W, HEAD_H), (0, 0, 0, 0))
    ox, oy = (HEAD_W - sw) // 2, 0

    # --- massa do cranio PRIMEIRO, senao o buraco em forma de rosto que existe
    # na camada de cabelo aparece quando o rosto desliza para o lado.
    im.alpha_composite(_skull_mass(hair, face, fringe, 1.0 + 0.18 * sa, -1.4 * sa,
                                   dark=int(-10 - 16 * (1.0 - max(ca, -1)) * 0.5)),
                       (ox, oy))

    # --- massa de cabelo: ALONGA de perfil (1.0 -> 1.18), nao aperta
    layer = _stretch(hair, 1.0 + 0.18 * sa, -1.4 * sa)
    if ca < 0.6:
        layer = _shade(layer.copy(), int(-14 * (0.6 - ca)))
    im.alpha_composite(layer, (ox, oy))

    if ca > -0.25:
        # --- rosto: DESLIZA e e OCLUIDO pelo lado distante, nunca comprimido.
        # cut = quantas colunas do lado distante o cranio come.
        cut = int(round(4.0 * sa))
        fl = _slide_occlude(face, dx=int(round(2.0 * sa)), cut_left=cut)
        vis = min(1.0, (ca + 0.25) / 0.9)
        if vis < 1.0:
            fl = _shade(fl.copy(), int(-18 * (1.0 - vis)))
        im.alpha_composite(fl, (ox, oy))
        im.alpha_composite(
            _slide_occlude(fringe, dx=int(round(1.6 * sa)), cut_left=max(0, cut - 1)),
            (ox, oy))
        if sa > 0.55:
            _profile_features(im, ox, oy, sa)
    else:
        nape = _stretch(fringe.transpose(Image.FLIP_LEFT_RIGHT), 1.0 + 0.10 * sa, -1.0 * sa)
        im.alpha_composite(_shade(nape.copy(), -26), (ox, oy))
        _grow_nape(im, ca)
    return im


def _skull_mass(hair, face, fringe, sx, dx, dark):
    """Silhueta cheia da cabeca, em tom de cabelo, atras de tudo.

    A camada de cabelo tem um buraco com a forma exata do rosto (as camadas sao
    separadas por coordenada). Assim que o rosto desliza para a borda, esse
    buraco vira um retangulo transparente no meio da cabeca. A massa resolve:
    e a mesma silhueta, preenchida, desenhada por baixo.
    """
    w, h = hair.size
    # 1. silhueta: uniao das tres camadas, preenchida por linha
    sil = [[False] * w for _ in range(h)]
    for src in (hair, face, fringe):
        p = src.load()
        for y in range(h):
            for x in range(w):
                if p[x, y][3]:
                    sil[y][x] = True
    for y in range(h):
        xs = [x for x in range(w) if sil[y][x]]
        if xs:
            for x in range(min(xs), max(xs) + 1):
                sil[y][x] = True
    # 2. preenche com a TEXTURA do cabelo espelhada, nao com um tom chapado.
    # Massa lisa vira tigela; a textura espelhada e o mesmo truque da nuca.
    # cadeia de fontes: o buraco do rosto e um buraco no cabelo E no cabelo
    # espelhado (a caixa do rosto e quase centrada, entao espelhar mapeia nela
    # mesma). Por isso a terceira e a quarta fonte sao deslocadas para cima —
    # e de la que vem textura de cabelo de verdade.
    srcs = [hair,
            hair.transpose(Image.FLIP_LEFT_RIGHT),
            _shift_down(hair, 7),
            _shift_down(hair.transpose(Image.FLIP_LEFT_RIGHT), 5),
            _shift_down(hair, 11)]
    loads = [s.load() for s in srcs]
    mass = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mp = mass.load()
    tone = _dark(_rgba("HAIR"), 0)
    for y in range(h):
        for x in range(w):
            if not sil[y][x]:
                continue
            c = None
            for lp in loads:
                if lp[x, y][3]:
                    c = lp[x, y]
                    break
            mp[x, y] = c if c else tone
    return _shade(_stretch(mass, sx, dx), dark)


def _shift_down(img, n):
    """out[y] = img[y-n]: traz textura das linhas de CIMA para baixo.

    Tem de ser para baixo. Deslocando para cima, a zona do rosto (linhas 15-21
    de um recorte de 22) ia buscar textura nas linhas 22-28, que nao existem, e
    o preenchimento caia no tom chapado — que e o bloco escuro que aparecia."""
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(img, (0, n))
    return out


def _stretch(img, sx, dx):
    """Escala horizontal em torno do centro. sx > 1 ALONGA."""
    w, h = img.size
    nw = max(1, int(round(w * sx)))
    big = img.resize((nw, h), Image.NEAREST)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(big, (int(round((w - nw) / 2.0 + dx)), 0))
    return out


def _slide_occlude(img, dx, cut_left):
    """Desliza a peca e apaga as colunas que o cranio esconde.

    Isto e o que substitui o aperto horizontal: uma face que gira nao fica mais
    estreita em si, ela sai de vista por tras da propria cabeca.
    """
    w, h = img.size
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    out.alpha_composite(img, (dx, 0))
    if cut_left > 0:
        p = out.load()
        xs = [x for x in range(w) for y in range(h) if p[x, y][3]]
        if xs:
            x0 = min(xs)
            for x in range(x0, min(w, x0 + cut_left)):
                for y in range(h):
                    p[x, y] = (0, 0, 0, 0)
    return out


def _profile_features(im, ox, oy, sa):
    """De perfil a leitura vem da BORDA: testa, nariz, queixo.

    Sem isso o perfil e um oval de cabelo com um retangulo de pele colado. Com
    3 pixels de nariz e um degrau de queixo o cerebro fecha a forma.
    """
    p = im.load()
    xs = [(x, y) for x in range(HEAD_W) for y in range(HEAD_H) if p[x, y][3]]
    if not xs:
        return
    skin = (*PAL["SKIN"], 255)
    shade = (*PAL["SKIN_SH"], 255)
    rows = [y for (_x, y) in xs]
    y0, y1 = min(rows), max(rows)
    face_y = int(y0 + (y1 - y0) * 0.72)          # linha dos olhos/nariz
    edge = max(x for (x, y) in xs if abs(y - face_y) <= 1)
    k = (sa - 0.55) / 0.45
    nose = 1                                     # 1px: mais que isso vira bico
    for i in range(nose):
        x = min(HEAD_W - 1, edge + 1 + i)
        if p[x, face_y][3] == 0:
            p[x, face_y] = shade
        if p[x, face_y + 1][3] == 0 and face_y + 1 < HEAD_H:
            p[x, face_y + 1] = shade
    # queixo: um degrau para dentro, uma linha abaixo do nariz
    cy = min(HEAD_H - 1, face_y + 2)
    cx = min(HEAD_W - 1, edge)
    if p[cx, cy][3] == 0:
        p[cx, cy] = shade


def _grow_nape(im, ca):
    """Fecha a nuca como MASSA e carimba nela a textura do topo do cabelo,
    espelhada. Crescer coluna a coluna vira dreadlock; massa lisa vira tigela."""
    p = im.load()
    w, h = im.size
    fx0, fy0, fx1, fy1 = FACE_BOX
    ox = (w - 25) // 2
    x0, x1 = fx0 + ox - 1, fx1 + ox + 1
    depth = 1.0 if ca <= -0.7 else min(1.0, (-ca - 0.25) / 0.45)
    bot = fy0 + int(round(4 + 2 * depth))
    base = (*PAL["HAIR_DK"], 255)
    cx, rx = (x0 + x1) / 2.0, (x1 - x0) / 2.0
    for y in range(fy0 - 2, bot + 1):
        t = (y - (fy0 - 2)) / max(1.0, bot - (fy0 - 2))
        half = rx * math.sqrt(max(0.0, 1.0 - (t * 0.92) ** 2))
        for x in range(int(round(cx - half)), int(round(cx + half)) + 1):
            if 0 <= x < w and 0 <= y < h and (p[x, y][3] == 0 or y >= fy0):
                p[x, y] = base
    hair_img = _head_layers()[0]
    hp = hair_img.load()
    hw, hh = hair_img.size
    for y in range(fy0 - 2, bot + 1):
        sy = 2 + (bot - y)
        if not (0 <= sy < hh):
            continue
        for x in range(x0, x1 + 1):
            sx = x - ox
            if not (0 <= sx < hw and 0 <= x < w and 0 <= y < h) or p[x, y][3] == 0:
                continue
            c = hp[sx, sy]
            if c[3]:
                p[x, y] = (max(0, c[0] - 30), max(0, c[1] - 24), max(0, c[2] - 20), 255)


# ============================================== layout do atlas (heroi)
# 5 colunas (FACE_8_MIRR): S, SE, E, NE, N. O oeste o runtime espelha sozinho.
# Tamanhos copiados da Juno — era dai que vinha o inchaco da versao anterior.
# ---------------------------------------------------------------------------
# As grades do corpo vem de body.py, que gera cada peca de um estencil com
# ORCAMENTO DE TOM. Medido com px.py, as grades escritas a mao usavam 5 tons
# num membro de 4px (teto: 2) e 11 tons num tronco de 10px (teto: 3-4) — nao
# era sombreamento, era ruido, e e a causa medida do "montagem confusa".
# As dicts antigas ficam no arquivo como historico; estas sobrescrevem.
import body as _body

for _k, _v in _body.build().items():
    globals()[_k] = _v

BLOCKS = [
    ("head",      None,        0,   0, 20, 20, ["UP1+", "ALL", "DOWN1+"], "hair"),
    ("torso",     "TORSO",   144,   0, 12, 12, ["ALL", "DOWN1+"], "tunic"),
    ("abdomen",   "ABDOMEN", 144,  24, 12, 10, ["ALL", "DOWN1+"], "tunic"),
    ("pelvis",    "PELVIS",  144,  44, 12, 12, ["ALL"], "pants"),
    ("pouch",     "POUCH",   144,  56,  8, 10, ["ALL"], "leather"),
    ("thigh",     "THIGH",   216,   0,  8, 12, ["ALL"], "pants"),
    ("shin",      "SHIN",    216,  12,  8, 12, ["ALL"], "pants"),
    ("foot",      "FOOT",    216,  24,  8,  8, ["ALL"], "boot"),
    ("shoulder",  "SHOULDER",216,  32,  8,  8, ["ALL"], "leather"),
    ("upper_arm", "UPPER_ARM",216, 40,  8, 10, ["ALL"], "sleeve"),
    ("forearm",   "FOREARM", 216,  50,  8,  8, ["ALL"], "vamb"),
    ("hand",      "HAND",    216,  58,  8,  8, ["ALL"], "skin"),
]


def check_layout():
    used = {}
    for name, _g, bx, by, w, h, rows, _m in BLOCKS:
        for r in range(len(rows)):
            for c in range(5):
                for y in range(by + r * h, by + (r + 1) * h):
                    for x in range(bx + c * w, bx + (c + 1) * w):
                        if x >= ATLAS_W or y >= ATLAS_H:
                            return ["%s sai do atlas em (%d,%d)" % (name, x, y)]
                        prev = used.get((x, y))
                        if prev and prev != name:
                            return ["%s colide com %s em (%d,%d)" % (name, prev, x, y)]
                        used[(x, y)] = name
    return []


def _harden(img):
    """Alpha so 0 ou 255.

    Os pixels do concept vem com alpha 253. Colar isso sobre o fundo chroma faz
    o Pillow misturar 1% de magenta em cada pixel, e nas bordas sobra
    (253,0,193) — que o keying do runtime (que procura (255,0,195) exato) nao
    reconhece, e vira um ponto magenta no jogo.
    """
    p = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            c = p[x, y]
            p[x, y] = (c[0], c[1], c[2], 255) if c[3] >= 128 else (0, 0, 0, 0)
    return img


def build_atlas():
    atlas = Image.new("RGBA", (ATLAS_W, ATLAS_H), CHROMA)
    for name, gname, bx, by, w, h, rows, mat in BLOCKS:
        for r in range(len(rows)):
            for c, dirn in enumerate(COLS):
                if gname is None:
                    art = draw_head(c)
                elif USE_CARVE and name in carve.PIECES:
                    art = carve.piece(name, c)
                elif name in UNIFORM:
                    # Membro: as 5 colunas sao quase iguais, de proposito.
                    #
                    # O runtime escolhe a coluna pelo YAW DO OSSO, nao pelo do
                    # personagem. Num braco pendurado (ou numa canela) o yaw e
                    # ruido: medido no face S, handR caia na coluna SE e
                    # fingerL/fistL na coluna E. Com colunas muito diferentes
                    # isso vira o membro piscando de perfil parado.
                    #
                    # E um cilindro de 6px: virar 45 graus nao muda a silhueta
                    # dele de verdade. Entao as colunas so mudam de VALOR, e o
                    # sorteio de coluna deixa de aparecer.
                    art = _shade(grid(globals()[gname]["S"], mat), -4 * c)
                else:
                    art = grid(globals()[gname][dirn], mat)
                art = _harden(pad(art, w, h).convert("RGBA"))
                atlas.paste(art, (bx + c * w, by + r * h), art)
    return atlas


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    bad = check_layout()
    if bad:
        print("LAYOUT INVALIDO:", bad[0])
        sys.exit(1)
    path = os.path.join(out, "oathwake_hero_01.png")
    build_atlas().save(path)
    print("ok ->", path)
    for name, _g, bx, by, w, h, rows, mat in BLOCKS:
        print("  %-10s (%3d,%3d) %2dx%-2d  %d linha(s)  5 colunas  [%s]"
              % (name, bx, by, w, h, len(rows), mat))


if __name__ == "__main__":
    main()
