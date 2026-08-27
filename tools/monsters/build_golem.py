#!/usr/bin/env python3
"""
Monta o figure do Golem: mesmo esqueleto e mesmas animacoes do Mixamo, com
proporcoes de golem e o atlas de pedra.

Uso: python build_golem.py <pasta_gltf> <saida.json>
"""

import json
import sys

import build_monster as B

FIGURE_NAME = "Oathwake-Golem-01"
ATLAS_FILE = "oathwake_golem_01.png"

# ------------------------------------------------------- proporcoes de golem
# Multiplicadores sobre os offsets humanos vindos do Mixamo. Mudar "pos" nao
# quebra nada: o runtime gira o offset pela rotacao acumulada do no, entao a
# animacao continua valendo — so o corpo que ela move fica com outra forma.
PROPORTION = {
    # ombros e quadris bem mais afastados: e disso que vem a silhueta larga
    "shoulderL": (1.35, 1.0, 1.0), "shoulderR": (1.35, 1.0, 1.0),
    "hipL": (1.20, 1.0, 1.0), "hipR": (1.20, 1.0, 1.0),
    # sem pescoco: a cabeca senta quase direto no tronco
    "neck": (1.0, 1.0, 0.35), "head": (1.0, 1.0, 0.55),
    # bracos longos e pesados
    "armL": (1.05, 1.0, 1.05), "armR": (1.05, 1.0, 1.05),
    "handL": (1.00, 1.0, 1.00), "handR": (1.00, 1.0, 1.00),
    "fingerL": (1.00, 1.0, 1.00), "fingerR": (1.00, 1.0, 1.00),
    # pernas curtas e grossas
    "legL": (1.0, 1.0, 0.90), "legR": (1.0, 1.0, 0.90),
    "footL": (1.0, 1.0, 0.90), "footR": (1.0, 1.0, 0.90),
    "toeL": (1.0, 1.25, 1.0), "toeR": (1.0, 1.25, 1.0),
    # tronco mais compacto
    "spine": (1.0, 1.0, 0.90), "top": (1.0, 1.0, 0.90), "chest": (1.0, 1.0, 0.90),
}

# --------------------------------------------------------- atlas do golem
# pauldron e punho foram para o espaco livre do atlas e cresceram; sao as duas
# pecas que mais definem a leitura de golem.
ATLAS = {
    "head":      (0, 0, 16, 16, ["UP1+", "ALL", "DOWN1+"], 0.5, 0.72, "NONE", 12),
    "torso":     (0, 48, 16, 16, ["ALL", "DOWN1+"], 0.5, 0.41, "NONE", -4),
    "abdomen":   (0, 80, 16, 12, ["ALL", "DOWN1+"], 0.5, 0.04, "NONE", -6),
    "pelvis":    (0, 104, 16, 12, ["ALL"], 0.5, 0.10, "NONE", 0),
    "upper_leg": (144, 0, 8, 16, ["ALL"], 0.5, 1.0, "PARENT_ROTATE_SCALE", 11),
    "shin":      (144, 16, 8, 12, ["ALL"], 0.5, 1.0, "PARENT_ROTATE_SCALE", 3),
    "foot":      (144, 28, 12, 12, ["ALL"], 0.5, 0.70, "ROTATE", 0),
    "upper_arm": (208, 8, 8, 12, ["ALL"], 0.5, 1.0, "PARENT_ROTATE_SCALE", 0),
    "forearm":   (208, 20, 8, 8, ["ALL"], 0.5, 1.0, "PARENT_ROTATE_SCALE", 2),
    "shoulder":  (272, 0, 12, 12, ["ALL"], 0.5, 0.5, "ROTATE", 6),
    "fist":      (272, 16, 10, 10, ["ALL"], 0.5, 0.5, "PARENT_ROTATE", 8),
    # bola de articulacao: ancorada na junta, sem esticar, cobre a emenda
    "joint":     (272, 28, 6, 6, ["ALL"], 0.5, 0.5, "NONE", 9),
}

# nós que ganham uma SEGUNDA arte: a bola de articulacao por cima da emenda
JOINT_CAPS = ["legL", "legR", "footL", "footR", "handL", "handR", "fingerL", "fingerR"]


def add_joint_caps(nodes):
    """Pendura a bola de articulacao como gfx extra nos nós de junta."""
    x, y, w, h, rows, pivx, pivy, texrot, zorder = ATLAS["joint"]
    for name in JOINT_CAPS:
        if name not in nodes:
            continue
        facing = "FACE_8_MIRR_FLIP" if name.endswith("R") else "FACE_8_MIRR"
        nodes[name]["gfx"].append({
            "hidden": False,
            "pos": [0.0, 0.0, 0.0],
            "shape": {"billboard": {
                "cutInverse": False, "cutScaleShift": 0,
                "pivotX": pivx, "pivotY": pivy,
                "shadow": True, "shadowTolerance": True,
                "sheer": 0.5, "windWiggle": 0, "zOrder": zorder,
            }},
            "style": "NORMAL",
            "tex": {"multi": {"onMissingFrame": "USE_DEFAULT", "entries": {"default": {
                "facing": facing, "flipShift": 0, "sheet": "Male-1",
                "range": [x, y, w, h], "variants": [],
                "rows": [{"pitchRange": pr, "refAngles": [], "texRotate": texrot,
                          "frameKeys": []} for pr in rows],
            }}}},
        })
    return nodes


def apply_proportions(nodes):
    for name, mult in PROPORTION.items():
        if name not in nodes:
            continue
        pos = nodes[name]["pos"]
        nodes[name]["pos"] = [round(pos[i] * mult[i], 6) for i in range(3)]
    return nodes


def main():
    src_dir, out_path = sys.argv[1], sys.argv[2]
    B.ATLAS.clear()
    B.ATLAS.update(ATLAS)

    tmp = out_path + ".human.json"
    sys.argv = ["build_monster.py", src_dir, tmp]
    B.main()

    payload = json.load(open(tmp, encoding="utf-8"))
    figure = payload["figures"]["Oathwake-Monster-01"]
    figure["nodes"] = apply_proportions(figure["nodes"])
    figure["nodes"] = add_joint_caps(figure["nodes"])
    out = {
        "figures": {FIGURE_NAME: figure},
        "spriteSheets": {"Male-1": {"img": "media/char/" + ATLAS_FILE,
                                    "range": [0, 0, 672, 120]}},
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    import os
    os.remove(tmp)
    print()
    print("figure:", FIGURE_NAME)
    print("proporcoes de golem aplicadas em %d nós" % len(PROPORTION))
    print("saída:", out_path)


if __name__ == "__main__":
    main()
