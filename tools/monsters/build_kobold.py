#!/usr/bin/env python3
"""
Kobold encapuzado — segundo humanoide do Oathwake.

Mesmo esqueleto do Mixamo e as mesmas animacoes do golem; muda proporcao,
paleta e arte. A fisionomia animal e resolvida pela SILHUETA, nao pelo rosto:
nesse tamanho um focinho tem 3px e vira borrao. O que le como bicho e
  - duas orelhas furando o capuz (aparecem na silhueta da cabeca)
  - postura curvada (cabeca empurrada pra frente do eixo do tronco)
  - cauda, uma peca extra pendurada no no do quadril
  - pe chapado de tres dedos
e o rosto fica no escuro do capuz, com dois pontos de olho.

Uso: python build_kobold.py <pasta_gltf> <saida.json>
"""

import json
import os
import sys

import build_monster as B

FIGURE_NAME = "Oathwake-Kobold-01"
ATLAS_FILE = "oathwake_kobold_01.png"

# Escala global sobre o esqueleto humano. O golem tem ~46px de altura de tela;
# 0.74 poe o kobold em ~34px, que e a leitura de "chega na cintura do jogador".
GLOBAL = 0.74

# Multiplicadores por no, aplicados DEPOIS da escala global.
PROPORTION = {
    # Ombro 0.80 -> 1.45. Com 0.80 o braco encostava no tronco em toda a
    # extensao e a silhueta preta virava um trapezio macico — o kobold era o
    # unico do elenco que REPROVAVA no teste de silhueta. Vao entre braco e
    # tronco nao e detalhe de sombreamento: e o que da forma a mancha.
    "shoulderL": (1.45, 1.0, 1.0), "shoulderR": (1.45, 1.0, 1.0),
    "hipL": (0.92, 1.0, 1.0), "hipR": (0.92, 1.0, 1.0),
    # bracos longos demais pro corpo: le como bicho que anda meio curvado
    "armL": (1.10, 1.0, 1.0), "armR": (1.10, 1.0, 1.0),
    "handL": (1.12, 1.0, 1.0), "handR": (1.12, 1.0, 1.0),
    "fingerL": (1.12, 1.0, 1.0), "fingerR": (1.12, 1.0, 1.0),
    # pernas curtas e agachadas
    "legL": (1.0, 1.0, 0.82), "legR": (1.0, 1.0, 0.82),
    "footL": (1.0, 1.0, 0.82), "footR": (1.0, 1.0, 0.82),
    # dedo so pra frente (sem componente Z), senao o pe descola da canela
    "toeL": (0.0, 1.15, 0.0), "toeR": (0.0, 1.15, 0.0),
    # tronco curto
    "spine": (1.0, 1.0, 0.85), "top": (1.0, 1.0, 0.85), "chest": (1.0, 1.0, 0.85),
    "neck": (1.0, 1.0, 0.5),
}

# Deslocamento absoluto somado depois. E o que faz a corcunda: a cabeca sai do
# eixo do tronco e vai pra frente (+Y e a direcao pra onde o personagem olha).

DAMP = {
    "hipL": 0.60, "hipR": 0.60, "legL": 0.60, "legR": 0.60,
    "footL": 0.68, "footR": 0.68, "toeL": 0.68, "toeR": 0.68,
    "shoulderL": 0.78, "shoulderR": 0.78, "armL": 0.70, "armR": 0.70,
    "handL": 0.70, "handR": 0.70,
}

OFFSET = {
    "neck": (0.0, 0.10, 0.06),
    "head": (0.0, 0.05, 0.03),
}

Z = {
    "pelvis_back": -40,
    "tail": -20,
    "pelvis": 0,
    "abdomen": -12,
    "torso": -10,
    "upper_leg": -4,
    "shin": 0,
    "foot": 1,
    "joint_leg": 2,
    "upper_arm": 14,
    "forearm": 16,
    "joint_arm": 17,
    "shoulder": 18,
    "fist": 22,
    "head": 24,
}

Z_LEG = [0, -10, -14, -10, 0, 10, 14, 10]
Z_ARM = [0, -26, -30, -26, -20, 0, 0, 0]
# Cauda: sai da garupa. De frente ela esta ATRAS do corpo; de costas ela aponta
# PRA CAMERA e tem que passar na frente. 5 colunas (FACE_8_MIRR): S SE E NE N.
Z_TAIL = [0, 8, 18, 28, 34]

# (x, y, w, h, linhas de pitch, pivotX, pivotY, texRotate, zOrder, zFrames)
ATLAS = {
    "head":      (0, 0, 16, 16, ["UP1+", "ALL", "DOWN1+"], 0.5, 0.63, "NONE", Z["head"], None),
    "torso":     (0, 48, 16, 14, ["ALL", "DOWN1+"], 0.5, 0.46, "NONE", Z["torso"], None),
    "abdomen":   (0, 76, 16, 10, ["ALL", "DOWN1+"], 0.5, 0.05, "NONE", Z["abdomen"], None),
    "pelvis":    (0, 96, 16, 10, ["ALL"], 0.5, 0.18, "NONE", Z["pelvis"], None),
    # coxa: junta ate 10.61px -> 11 acima do joelho + 2 de transbordo
    "upper_leg": (96, 0, 8, 14, ["ALL"], 0.5, 11.0 / 14.0, "PARENT_ROTATE_CUT", Z["upper_leg"], Z_LEG),
    # canela: ate 7.51px -> 8 acima do tornozelo + 4 de calcanhar
    "shin":      (96, 14, 8, 12, ["ALL"], 0.5, 8.0 / 12.0, "PARENT_ROTATE_CUT", Z["shin"], Z_LEG),
    # braco: ate 12.65px -> 13 acima do cotovelo + 2
    "upper_arm": (96, 26, 8, 15, ["ALL"], 0.5, 13.0 / 15.0, "PARENT_ROTATE_CUT", Z["upper_arm"], Z_ARM),
    # antebraco: ate 10.55px -> 11 acima do punho + 4
    "forearm":   (96, 41, 8, 15, ["ALL"], 0.5, 11.0 / 15.0, "PARENT_ROTATE_CUT", Z["forearm"], Z_ARM),
    "foot":      (176, 0, 12, 10, ["ALL"], 0.5, 0.25, "ROTATE", Z["foot"], Z_LEG),
    # ombreira 8x8: com 10x10 as duas se encontravam no meio e viravam uma
    # barra escura atravessando o peito, e a cabeca ficava pousada em cima dela
    "shoulder":  (176, 12, 8, 8, ["ALL"], 0.5, 0.35, "NONE", Z["shoulder"], Z_ARM),
    "fist":      (176, 24, 10, 10, ["ALL"], 0.5, 0.45, "NONE", Z["fist"], Z_ARM),
    "joint":     (176, 36, 6, 6, ["ALL"], 0.5, 0.5, "NONE", Z["joint_leg"], Z_LEG),
    "tail":      (280, 0, 14, 16, ["ALL"], 0.5, 0.12, "NONE", Z["tail"], Z_TAIL),
}

ART = {
    "bottom": ("pelvis", "FACE_8_MIRR"),
    "top": ("abdomen", "FACE_8_MIRR"),
    "chest": ("torso", "FACE_8_MIRR"),
    "head": ("head", "FACE_8_MIRR"),
    "legL": ("upper_leg", "FACE_8"), "legR": ("upper_leg", "FACE_8_FLIP"),
    "footL": ("shin", "FACE_8"), "footR": ("shin", "FACE_8_FLIP"),
    "toeL": ("foot", "FACE_8"), "toeR": ("foot", "FACE_8_FLIP"),
    "armL": ("shoulder", "FACE_8"), "armR": ("shoulder", "FACE_8_FLIP"),
    "handL": ("upper_arm", "FACE_8"), "handR": ("upper_arm", "FACE_8_FLIP"),
    "fingerL": ("forearm", "FACE_8"), "fingerR": ("forearm", "FACE_8_FLIP"),
    "fistL": ("fist", "FACE_8"), "fistR": ("fist", "FACE_8_FLIP"),
}

# Removidas pelo mesmo motivo do golem: bola de junta le como chunk solto em
# movimento. Emenda se fecha por transbordo distal da propria peca.
JOINT_CAPS = {}


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
        "hidden": False, "pos": [0.0, 0.0, 0.0],
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
    for name, (block, facing) in ART.items():
        if name in nodes:
            nodes[name]["gfx"].append(gfx_entry(block, facing))
    if "bottom" in nodes:
        # chapa de fundo: tampa o vao entre as coxas
        nodes["bottom"]["gfx"].append(
            gfx_entry("pelvis", "FACE_8_MIRR", zorder=Z["pelvis_back"], zframes=None))
        # cauda
        nodes["bottom"]["gfx"].append(gfx_entry("tail", "FACE_8_MIRR"))
    for name, (facing, zkey) in JOINT_CAPS.items():
        if name in nodes:
            zf = Z_ARM if zkey == "joint_arm" else Z_LEG
            nodes[name]["gfx"].append(
                gfx_entry("joint", facing, zorder=Z[zkey], zframes=zf))
    return nodes


def apply_proportions(nodes):
    for name in nodes:
        nodes[name]["pos"] = [v * GLOBAL for v in nodes[name]["pos"]]
    for name, mult in PROPORTION.items():
        if name in nodes:
            p = nodes[name]["pos"]
            nodes[name]["pos"] = [p[i] * mult[i] for i in range(3)]
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
    B.damp_anims(figure, DAMP)
    figure["nodes"] = attach_gfx(figure["nodes"])
    out = {
        "figures": {FIGURE_NAME: figure},
        "spriteSheets": {"Male-1": {"img": "media/char/" + ATLAS_FILE,
                                    "range": [0, 0, 672, 120]}},
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    os.remove(tmp)
    print()
    print("figure:", FIGURE_NAME, " escala global:", GLOBAL)
    print("pecas de arte:", sum(len(n["gfx"]) for n in figure["nodes"].values()))
    print("saida:", out_path)


if __name__ == "__main__":
    main()
