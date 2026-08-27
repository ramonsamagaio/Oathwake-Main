#!/usr/bin/env python3
"""
Deriva um figure JSON de monstro humanoide a partir de dummy.json (Male-Dummy).

O que muda em relacao ao Male-Dummy:
  - o figure passa a se chamar Monster-Humanoid-01
  - TODA peca cai para uma familia FACE_8 espelhada -> 5 celulas unicas por linha
      FACE_16_MIRR  -> FACE_8_MIRR
      FACE_8        -> FACE_8_MIRR
      FACE_8_FLIP   -> FACE_8_MIRR_FLIP
      FACE_8_MIRR*  -> inalterado
  - spriteSheets aponta para monster_humanoid_01.png

O que NAO muda (de proposito):
  - hierarquia de bones, posicoes, pivos, zOrder, texRotate, linhas de pitch
  - as coordenadas 'range' de cada peca no atlas
  - o banco de animacoes nativo (walk, run, punch, laying, sitting, ...)

Uso:
  python make_alabaster_monster_figure.py <dummy.json> <saida.json>
"""

import json
import sys

FACING_MAP = {
    "FACE_16_MIRR": "FACE_8_MIRR",
    "FACE_16_MIRR_FLIP": "FACE_8_MIRR_FLIP",
    "FACE_16": "FACE_8_MIRR",
    "FACE_16_FLIP": "FACE_8_MIRR_FLIP",
    "FACE_8": "FACE_8_MIRR",
    "FACE_8_FLIP": "FACE_8_MIRR_FLIP",
}

SOURCE_FIGURE = "Male-Dummy"
TARGET_FIGURE = "Monster-Humanoid-01"
TARGET_ATLAS = "monster_humanoid_01.png"

REQUIRED_NODES = [
    "root", "top", "head", "bottom",
    "hipL", "legL", "footL",
    "hipR", "legR", "footR",
    "shoulderL", "armL", "handL",
    "shoulderR", "armR", "handR",
]


def remap_facings(figure):
    changed = []
    for node_name, node in figure.get("nodes", {}).items():
        for gi, gfx in enumerate(node.get("gfx", [])):
            entries = gfx.get("tex", {}).get("multi", {}).get("entries", {})
            for ek, entry in entries.items():
                old = entry.get("facing")
                new = FACING_MAP.get(old, old)
                if new != old:
                    entry["facing"] = new
                    changed.append((node_name, gi, ek, old, new))
    return changed


def validate(payload):
    problems = []
    fig = payload["figures"][TARGET_FIGURE]
    for n in REQUIRED_NODES:
        if n not in fig["nodes"]:
            problems.append("nó obrigatório ausente: %s" % n)
    if fig.get("rootFacing") != "FACE_16":
        problems.append("rootFacing precisa ser FACE_16 (está %r)" % fig.get("rootFacing"))
    if not fig.get("anims"):
        problems.append("figure sem animações")
    sheet = payload.get("spriteSheets", {}).get("Male-1")
    if not isinstance(sheet, dict):
        problems.append("spriteSheets precisa ter a chave 'Male-1'")
    else:
        if not str(sheet.get("img", "")).endswith(TARGET_ATLAS):
            problems.append("Male-1.img precisa terminar em %s" % TARGET_ATLAS)
        if list(sheet.get("range", []))[2:4] != [672, 120]:
            problems.append("Male-1.range precisa ser [0,0,672,120]")
    return problems


def main():
    src, dst = sys.argv[1], sys.argv[2]
    data = json.load(open(src, encoding="utf-8"))
    figure = json.loads(json.dumps(data["figures"][SOURCE_FIGURE]))

    changed = remap_facings(figure)

    payload = {
        "figures": {TARGET_FIGURE: figure},
        "spriteSheets": {
            "Male-1": {"img": "media/char/%s" % TARGET_ATLAS, "range": [0, 0, 672, 120]}
        },
    }

    problems = validate(payload)
    for p in problems:
        print("ERRO:", p)
    if problems:
        sys.exit(1)

    with open(dst, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))

    print("figure  :", TARGET_FIGURE)
    print("nós     :", len(figure["nodes"]))
    print("anims   :", ", ".join(sorted(figure["anims"].keys())))
    print("facings remapeados:", len(changed))
    for node_name, gi, ek, old, new in changed:
        print("   %-10s gfx%d [%s]  %s -> %s" % (node_name, gi, ek, old, new))
    print("saída   :", dst)


if __name__ == "__main__":
    main()
