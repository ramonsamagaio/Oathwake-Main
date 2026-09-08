#!/usr/bin/env python3
"""
Herói do Oathwake — figure construido a partir do concept art.

O concept foi medido: a grade de pixel dele e de 17.3px, o personagem real tem
30x70 pixels, e as juntas caem nestas linhas (medidas no proprio concept):

    topo do cabelo   1      ombro           29
    no da cabeca    24      cotovelo        38
    peito           29      punho           45
    abdomen         35      quadril         43
    pelve           41      joelho          54
                            tornozelo       62
                            dedo            67

Ou seja, o ESQUELETO dele tem ~43px (a Juno tem 39.6, o golem 46). O que faz o
personagem parecer alto nao e o corpo: sao os 23px de cabelo acima do no da
cabeca. A celula de cabeca precisa de 26x26 por causa do cabelo, mas mesmo assim tudo
cabe nos 672x120 do contrato do dummy — nao foi preciso ir pro 672x240 da Juno.

As proporcoes abaixo sao multiplicadores sobre o esqueleto humano do Mixamo,
calibrados ate as distancias projetadas baterem com as linhas acima. Confira com
    python measure_any.py data/monsters/oathwake_hero_01.json

Uso: python build_hero.py <pasta_gltf> <saida.json>
"""

import json
import math
import os
import sys

import build_monster as B

FIGURE_NAME = "Oathwake-Hero-01"
ATLAS_FILE = "oathwake_hero_01.png"
ATLAS_W, ATLAS_H = 672, 120

GLOBAL = 1.0

# ---------------------------------------------------------------------------
# RETARGET PARA O ESQUELETO DA JUNO
#
# Calibrar COMPRIMENTO de osso nao resolve: dois rigs podem ter a mesma
# clavicula e por o cotovelo em lugares completamente diferentes. O que a
# silhueta enxerga e a POSICAO projetada. Medido com layout2.py, o erro do
# heroi anterior era:
#
#     no          meu(x,y)      juno(x,y)     erro
#     armL       9.18 -17.27   5.51  -0.90   +3.7 -16.4   <- braco na altura da orelha
#     handL     11.48 -12.80   6.69  +4.50   +4.8 -17.3
#     chest      0.11 -13.52   (top) -6.88         -6.6
#
# Duas causas, ambas estruturais:
#
#  1. root z = 1.688 contra 1.312 da Juno. A projecao e PERSPECTIVA: subir o
#     root aproxima o personagem da camera e ampliou tudo em ~27%. E dai que
#     vem o "nao me parece que ele esta do tamanho da juno" — nenhuma celula
#     de atlas conserta isso.
#  2. O rig do Mixamo e ANATOMICO: a clavicula sobe do peito e o ombro fica na
#     altura do pescoco. O rig da Juno nao e — o soquete do ombro fica 0.125
#     ABAIXO do peito e so 4.8px acima da pelve. E essa compressao que faz um
#     corpo de 48px ler como personagem e nao como boneco esticado.
#
# Entao: mantenho as DIRECOES de repouso do Mixamo (as quaternions da animacao
# dependem delas — mexer nelas quebra o balanco) e troco so as MAGNITUDES,
# copiando as da Juno segmento a segmento. O soquete do ombro e posicionado na
# mao, porque ali a direcao tambem esta errada, nao so o tamanho.
# ---------------------------------------------------------------------------

ROOT_Z = 1.3125  # identico ao da Juno: e o que fixa a escala na tela

# Magnitude alvo, em unidades de figure. Direcao preservada do Mixamo.
LENGTH = {
    # tronco: root->chest tem que dar 0.438 (o root->top da Juno), nao 0.706
    "spine": 0.130, "top": 0.130, "chest": 0.130,
    # pescoco + cabeca = 0.438 (top->head da Juno)
    "neck": 0.219, "head": 0.219,
    # braco: na Juno o antebraco tem o MESMO tamanho do braco (0.323 cada)
    "armL": 0.060, "armR": 0.060,        # clavicula -> soquete, quase nulo
    "handL": 0.323, "handR": 0.323,      # ombro -> cotovelo
    "fingerL": 0.250, "fingerR": 0.250,  # cotovelo -> punho
    "fistL": 0.110, "fistR": 0.110,      # mao (curta: fecha a emenda do punho)
    # perna: ja batia com a Juno em unidades de figure
    "legL": 0.500, "legR": 0.500,
    "footL": 0.500, "footR": 0.500,
}

# Posicao cravada (direcao do Mixamo descartada de proposito).
SET = {
    "bottom": (0.0, 0.0, -0.250),        # pelve ABAIXO do root, como a Juno
    "hipL": (0.125, 0.0, 0.0),           # soquete do quadril no nivel da pelve
    "hipR": (-0.125, 0.0, 0.0),
    # soquete do ombro: 0.167 pra fora e 0.125 PRA BAIXO do peito. O -0.112
    # ja desconta o pedaco que o osso armL vai somar depois.
    # X 0.108 -> 0.150. Medido: com 0.108 a linha do ombro fechava em 15px
    # contra 20px de cabeca, e um cranio mais largo que os ombros le como
    # pirulito. Na Juno a linha do ombro tem a MESMA largura da cabeca (21 x
    # 20). Este numero e o que amarra a leitura do busto.
    "shoulderL": (0.150, 0.0, -0.112),
    "shoulderR": (-0.150, 0.0, -0.112),
    # dedo so pra frente: com componente Z pra baixo a bota descola da canela
    "toeL": (0.0, 0.190, 0.0),
    "toeR": (0.0, 0.190, 0.0),
}


# Amplitude de rotacao por no (ver build_monster.damp_anims). 1.0 = Mixamo cru.
DAMP = {
    "hipL": 0.62, "hipR": 0.62, "legL": 0.62, "legR": 0.62,
    "footL": 0.70, "footR": 0.70, "toeL": 0.70, "toeR": 0.70,
    "shoulderL": 0.80, "shoulderR": 0.80, "armL": 0.72, "armR": 0.72,
    "handL": 0.72, "handR": 0.72,
}

OFFSET = {}

Z = {
    "pelvis_back": -40,
    "abdomen": -12,
    "torso": -10,
    "pelvis": 0,
    "upper_leg": -4,
    "shin": 0,
    "foot": 1,
    "joint_leg": 2,
    "pouch": 12,
    "upper_arm": 14,
    "forearm": 16,
    "joint_arm": 17,
    "shoulder": 18,
    "fist": 22,
    "head": 24,
}

# Z por direcao, indexado pelo tile do FACE_8 (0=S 1=SE 2=E 3=NE 4=N 5=NW 6=W 7=SW).
# Tiles 1-3 sao sempre o membro do lado oposto a camera, 5-7 o do lado de ca.
Z_LEG = [0, -10, -14, -10, 0, 10, 14, 10]
Z_ARM = [0, -26, -30, -26, -20, 0, 0, 0]

# (x, y, w, h, linhas de pitch, pivotX, pivotY, texRotate, zOrder, zFrames, facing)
# A cabeca usa FACE_16_MIRR (9 colunas) como a Juno: e onde mora a identidade.
ATLAS = {
    # Tamanhos copiados do figure da Juno, que e arte acabada autorada para este
    # mesmo rig. As minhas eram 26x26 / 18x18 / 10x21 e era dai que vinha o
    # inchaco: medido, o personagem estava 3-6px gordo em TODA faixa do corpo.
    #
    # A cabeca e um recorte 22x22 do concept re-quantizado (hero/requant.py).
    # PIVO Y 0.67, nao 0.5: o recorte vai do topo do cabelo (linha 0) ate a
    # linha do pescoco (linha 21), entao o no da cabeca cai no FIM do recorte,
    # nao no meio. Com 0.5 (o valor da Juno, cuja celula e centrada no cranio)
    # a cabeca descia 10px e enterrava o tronco: sobravam 4px de peito entre o
    # queixo e o cinto, contra 15px no concept.
    "head":      (0, 0, 20, 20, ["UP1+", "ALL", "DOWN1+"], 0.5, 0.67, "NONE", Z["head"], None),
    "torso":     (144, 0, 12, 12, ["ALL", "DOWN1+"], 0.5, 0.33, "NONE", Z["torso"], None),
    "abdomen":   (144, 24, 12, 10, ["ALL", "DOWN1+"], 0.5, 0.30, "NONE", Z["abdomen"], None),
    "pelvis":    (144, 44, 12, 12, ["ALL"], 0.5, 0.42, "NONE", Z["pelvis"], None),
    "pouch":     (144, 56, 8, 10, ["ALL"], 0.5, 0.20, "NONE", Z["pouch"], None),
    "thigh":     (216, 0, 8, 12, ["ALL"], 0.38, 0.83, "PARENT_ROTATE_CUT", Z["upper_leg"], None),
    "shin":      (216, 12, 8, 12, ["ALL"], 0.50, 0.75, "PARENT_ROTATE_CUT", Z["shin"], None),
    # bota: texRotate NONE, nao ROTATE.
    # Numa camera top-down de 45 graus, avancar e subir produzem o MESMO
    # movimento na tela. O pe girado vira a unica pista de direcao que sobra e o
    # personagem le como se tivesse virado de perfil — que e exatamente o defeito
    # "a perna dele de frente esta virando de lado". A bota nao gira.
    # pivo Y 0.38 -> 0.55: com 0.38 sobravam 3px de arte acima do no do dedo, e o
    # osso do dedo tem 3.2px — a bota encostava na canela por 0.2px e abria nos
    # quadros de soco. Com 0.55 sobram 4.4px.
    "foot":      (216, 24, 8, 8, ["ALL"], 0.25, 0.55, "NONE", Z["foot"], None),
    "shoulder":  (216, 32, 8, 8, ["ALL"], 0.38, 0.38, "NONE", Z["shoulder"], None),
    "upper_arm": (216, 40, 8, 10, ["ALL"], 0.38, 1.0, "PARENT_ROTATE_CUT", Z["upper_arm"], None),
    "forearm":   (216, 50, 8, 8, ["ALL"], 0.38, 1.0, "PARENT_ROTATE_CUT", Z["forearm"], None),
    "hand":      (216, 58, 8, 8, ["ALL"], 0.38, 0.5, "NONE", Z["fist"], None),
}

# 5 colunas em tudo: S, SE, E, NE, N. O runtime espelha o oeste sozinho.
# Sem FACE_8 de 8 colunas -> nao da pra distinguir leste de oeste no Z, entao a
# camada esquerda/direita usa assimetria estatica, como o dummy e a Juno fazem.
FACING = {}
DEFAULT_FACING = "FACE_8_MIRR"

ART = {
    "bottom": "pelvis", "top": "abdomen", "chest": "torso", "head": "head",
    "legL": "thigh", "legR": "thigh",
    "footL": "shin", "footR": "shin",
    "toeL": "foot", "toeR": "foot",
    # A ombreira mora na CLAVICULA, nao no braco. Ancorada em armL ela viajava
    # com o balanco do braco e abria 2px de vao com o tronco nos quadros de
    # corrida; em shoulderL ela quase nao se move — que e o que uma ombreira faz.
    "shoulderL": "shoulder", "shoulderR": "shoulder",
    "handL": "upper_arm", "handR": "upper_arm",
    "fingerL": "forearm", "fingerR": "forearm",
    "fistL": "hand", "fistR": "hand",
}

# Sem bolas de articulacao: o seams.py fecha todas as emendas so com
# transbordo distal e ponta aberta. Bola aqui virava colar de contas na perna.
JOINT_CAPS = {}


def facing_for(block, node):
    base = FACING.get(block, DEFAULT_FACING)
    return base + "_FLIP" if node.endswith("R") else base


# Deslocamento do gfx dentro do no. O runtime soma isto ao "pos" do no antes de
# projetar, entao da pra pendurar uma peca fora do eixo do osso sem inventar um
# osso novo. E assim que a bolsa vai pro quadril em vez de ficar no umbigo.
GFX_OFFSET = {
    # medido: 1 unidade de figure ~= 24.5px de tela no quadril. O concept
    # poe a bolsa a +7px do centro -> 7/24.5 = 0.29
    "pouch": [0.29, 0.10, -0.10],
}


def gfx_entry(block, facing, zorder=None, zframes="default"):
    x, y, w, h, rows, pivx, pivy, texrot, z, zf = ATLAS[block]
    if zorder is not None:
        z = zorder
    if zframes != "default":
        zf = zframes
    entry = {
        "facing": facing, "flipShift": 0, "sheet": "Male-1",
        "range": [x, y, w, h], "variants": [],
        "rows": [{"pitchRange": pr, "refAngles": [], "texRotate": texrot,
                  "frameKeys": []} for pr in rows],
    }
    if zf:
        entry["zFrames"] = list(zf)
    return {
        "hidden": False, "pos": list(GFX_OFFSET.get(block, [0.0, 0.0, 0.0])),
        "shape": {"billboard": {
            "cutInverse": False, "cutScaleShift": 0,
            "pivotX": pivx, "pivotY": pivy,
            "shadow": True, "shadowTolerance": True,
            "sheer": 0.5, "windWiggle": 0, "zOrder": z,
        }},
        "style": "NORMAL",
        "tex": {"multi": {"onMissingFrame": "USE_DEFAULT", "entries": {"default": entry}}},
    }


def attach_gfx(nodes):
    for name in nodes:
        nodes[name]["gfx"] = []
    for node, block in ART.items():
        if node in nodes:
            nodes[node]["gfx"].append(gfx_entry(block, facing_for(block, node)))
    if "bottom" in nodes:
        # chapa de fundo: a mesma pelve desenhada de novo bem atras, tapando o
        # vao entre as coxas. Truque do dummy e da Juno (ela tem duas: tronco e
        # pelve). Sem ela o quadril fica vazado e o corpo vira paper doll.
        nodes["bottom"]["gfx"].append(
            gfx_entry("pelvis", "FACE_8_MIRR", zorder=Z["pelvis_back"], zframes=None))
        nodes["bottom"]["gfx"].append(gfx_entry("pouch", "FACE_8_MIRR"))
    if "chest" in nodes:
        nodes["chest"]["gfx"].append(
            gfx_entry("torso", "FACE_8_MIRR", zorder=Z["torso"] - 8, zframes=None))
    for node, zkey in JOINT_CAPS.items():
        if node in nodes:
            zf = Z_ARM if zkey == "joint_arm" else Z_LEG
            nodes[node]["gfx"].append(
                gfx_entry("joint", facing_for("joint", node), zorder=Z[zkey], zframes=zf))
    return nodes


def apply_proportions(nodes):
    for name in nodes:
        nodes[name]["pos"] = [v * GLOBAL for v in nodes[name]["pos"]]
    # magnitude alvo, direcao do Mixamo preservada
    for name, target in LENGTH.items():
        if name in nodes:
            p = nodes[name]["pos"]
            mag = math.sqrt(sum(v * v for v in p))
            if mag > 1e-6:
                k = target / mag
                nodes[name]["pos"] = [v * k for v in p]
    # posicoes cravadas
    for name, pos in SET.items():
        if name in nodes:
            nodes[name]["pos"] = list(pos)
    if "root" in nodes:
        nodes["root"]["pos"] = [nodes["root"]["pos"][0], nodes["root"]["pos"][1], ROOT_Z]
    for name, add in OFFSET.items():
        if name in nodes:
            p = nodes[name]["pos"]
            nodes[name]["pos"] = [p[i] + add[i] for i in range(3)]
    for name in nodes:
        nodes[name]["pos"] = [round(v, 6) for v in nodes[name]["pos"]]
    return nodes


def main():
    src_dir, out_path = sys.argv[1], sys.argv[2]
    tmp = out_path + ".human.json"
    argv = sys.argv
    sys.argv = ["build_monster.py", src_dir, tmp]
    B.main()
    sys.argv = argv

    payload = json.load(open(tmp, encoding="utf-8"))
    figure = payload["figures"]["Oathwake-Monster-01"]
    figure["nodes"] = apply_proportions(figure["nodes"])
    figure["nodes"] = attach_gfx(figure["nodes"])
    out = {
        "figures": {FIGURE_NAME: figure},
        "spriteSheets": {"Male-1": {"img": "media/char/" + ATLAS_FILE,
                                    "range": [0, 0, ATLAS_W, ATLAS_H]}},
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    os.remove(tmp)
    print()
    print("figure:", FIGURE_NAME, " atlas:", "%dx%d" % (ATLAS_W, ATLAS_H))
    print("pecas de arte:", sum(len(n["gfx"]) for n in figure["nodes"].values()))
    print("saida:", out_path)


if __name__ == "__main__":
    main()
