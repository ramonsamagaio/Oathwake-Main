#!/usr/bin/env python3
"""
Validador offline do par figure JSON + atlas PNG do Alabaster.

Reimplementa a selecao de celula do AlabasterRigRuntimeSource.gd
(_facing_table / _pitch_bounds / enderecamento do atlas) e verifica,
para cada peca e cada uma das 16 direcoes de root:

  - a celula escolhida cai dentro do atlas
  - a celula escolhida tem pixel desenhado (nao e so chroma)
  - o pivo declarado cai dentro (ou na borda declarada) da celula

Uso:
  python verify_alabaster_monster.py <figure.json> <atlas.png> [Nome-Do-Figure]
"""

import json
import sys

from PIL import Image

CHROMA = (255, 0, 195)
A8 = [25.0, 70.0, 115.0, 160.0, 200.0, 245.0, 290.0, 335.0]
S8 = [2, 2, 1, 0, 0, 0, 1, 2]
A16 = [11.25, 33.75, 56.25, 78.75, 101.25, 123.75, 146.25, 168.75,
       191.25, 213.75, 236.25, 258.75, 281.25, 303.75, 326.25, 348.75]
S16 = [2, 2, 2, 2, 1, 0, 0, 0, 0, 0, 0, 0, 1, 2, 2, 2]

FACING = {
    "FACE_1": ([360.0], [0], [0]),
    "FACE_1_FLIP": ([360.0], [0], [1]),
    "FACE_4": ([40.0, 140.0, 220.0, 320.0], [2, 1, 0, 3], [0, 0, 0, 0]),
    "FACE_4_FLIP": ([40.0, 140.0, 220.0, 320.0], [2, 3, 0, 1], [1, 1, 1, 1]),
    "FACE_4_MIRR": ([40.0, 140.0, 220.0, 320.0], [2, 1, 0, 1], [0, 0, 0, 1]),
    "FACE_4_MIRR_FLIP": ([40.0, 140.0, 220.0, 320.0], [2, 1, 0, 1], [1, 0, 1, 1]),
    "FACE_8": (A8, [4, 3, 2, 1, 0, 7, 6, 5], [0] * 8),
    "FACE_8_FLIP": (A8, [4, 5, 6, 7, 0, 1, 2, 3], [1] * 8),
    "FACE_8_MIRR": (A8, [4, 3, 2, 1, 0, 1, 2, 3], [0, 0, 0, 0, 0, 1, 1, 1]),
    "FACE_8_MIRR_FLIP": (A8, [4, 3, 2, 1, 0, 1, 2, 3], [1, 0, 0, 0, 1, 1, 1, 1]),
    "FACE_16": (A16, [8, 7, 6, 5, 4, 3, 2, 1, 0, 15, 14, 13, 12, 11, 10, 9], [0] * 16),
    "FACE_16_MIRR": (A16, [8, 7, 6, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5, 6, 7],
                     [0] * 9 + [1] * 7),
    "FACE_16_MIRR_FLIP": (A16, [8, 7, 6, 5, 4, 3, 2, 1, 0, 1, 2, 3, 4, 5, 6, 7],
                          [1] + [0] * 8 + [1] * 7),
}

PITCH = {
    "NORM": (4, 4), "NORM_W": (3, 5),
    "UP1": (5, 5), "UP1+": (5, 11), "UP2": (6, 6), "UP2+": (6, 11),
    "UP3": (7, 7), "UP3+": (7, 11), "UP4": (8, 8), "UP4+": (8, 11),
    "UP5": (9, 9), "UP5+": (9, 11), "BACK": (10, 10), "BACK+": (10, 11),
    "DOWN1": (3, 3), "DOWN1+": (0, 3), "DOWN2": (2, 2), "DOWN2+": (0, 2),
    "DOWN3": (1, 1), "DOWN3+": (0, 1), "DOWN4": (0, 0), "DOWN5": (11, 11),
    "ALL": (0, 11),
}

COMPASS = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
           "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]


def select_tile(mode, yaw):
    table = FACING.get(mode)
    if table is None:
        return None
    angles, tiles, flips = table
    for i, threshold in enumerate(angles):
        if threshold >= yaw:
            return tiles[i], bool(flips[i])
    return tiles[0], bool(flips[0])


def cell_has_art(img, x, y, w, h):
    px = img.load()
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            r, g, b, a = px[xx, yy]
            if a != 0 and (r, g, b) != CHROMA:
                return True
    return False


def main():
    fig_path, png_path = sys.argv[1], sys.argv[2]
    payload = json.load(open(fig_path, encoding="utf-8"))
    figures = payload["figures"]
    name = sys.argv[3] if len(sys.argv) > 3 else sorted(figures)[0]
    figure = figures[name]

    img = Image.open(png_path).convert("RGBA")
    errors, warnings, checked = [], [], 0

    if img.size != (672, 120):
        errors.append("atlas tem %dx%d, o runtime exige 672x120" % img.size)

    if figure.get("rootFacing") != "FACE_16":
        errors.append("rootFacing = %r, o loader exige FACE_16" % figure.get("rootFacing"))

    sheet = payload.get("spriteSheets", {}).get("Male-1")
    if not isinstance(sheet, dict):
        errors.append("spriteSheets['Male-1'] ausente")
    elif list(sheet.get("range", []))[2:4] != [672, 120]:
        errors.append("spriteSheets['Male-1'].range != [0,0,672,120]")

    print("figure: %s   nós: %d   anims: %d" % (name, len(figure["nodes"]), len(figure.get("anims", {}))))
    print()
    print("%-10s %-4s %-18s %-6s %s" % ("nó", "gfx", "facing", "cels", "região usada no atlas"))
    print("-" * 78)

    for node_name, node in figure["nodes"].items():
        for gi, gfx in enumerate(node.get("gfx", [])):
            entries = gfx.get("tex", {}).get("multi", {}).get("entries", {})
            bb = gfx.get("shape", {}).get("billboard", {})
            for ek, entry in entries.items():
                mode = entry.get("facing", "FACE_1")
                rng = entry.get("range", [])
                if len(rng) < 4:
                    continue
                bx, by, w, h = (int(v) for v in rng[:4])
                rows = entry.get("rows", [{}])
                if mode not in FACING:
                    errors.append("%s gfx%d: facing desconhecido %s" % (node_name, gi, mode))
                    continue

                used, missing = set(), []
                for yaw_idx in range(16):
                    yaw = yaw_idx * 22.5
                    sel = select_tile(mode, yaw if yaw > 0 else 0.001)
                    if sel is None:
                        continue
                    tile, flip = sel
                    if tile < 0:
                        continue
                    used.add(tile)
                    for ri in range(len(rows)):
                        x = bx + w * tile
                        y = by + h * ri
                        checked += 1
                        if x + w > img.width or y + h > img.height:
                            errors.append("%s gfx%d %s tile%d linha%d sai do atlas em (%d,%d)"
                                          % (node_name, gi, mode, tile, ri, x, y))
                        elif not cell_has_art(img, x, y, w, h):
                            key = (node_name, gi, tile, ri)
                            if key not in missing:
                                missing.append(key)
                                warnings.append("%s gfx%d: célula vazia tile%d linha%d em (%d,%d) — %s"
                                                % (node_name, gi, tile, ri, x, y, COMPASS[yaw_idx]))

                pivx = float(bb.get("pivotX", 0.5))
                pivy = float(bb.get("pivotY", 0.5))
                if not (-0.5 <= pivx <= 1.5) or not (-0.5 <= pivy <= 1.5):
                    warnings.append("%s gfx%d: pivô fora do razoável (%.2f, %.2f)" % (node_name, gi, pivx, pivy))

                span = "x %d..%d  y %d..%d" % (bx, bx + w * (max(used) + 1), by, by + h * len(rows))
                print("%-10s gfx%-1d %-18s %-6d %s" % (node_name, gi, mode, len(used), span))

    print()
    print("células testadas:", checked)
    if warnings:
        print("\nAVISOS (%d):" % len(warnings))
        for w_ in warnings:
            print("  ", w_)
    if errors:
        print("\nERROS (%d):" % len(errors))
        for e in errors:
            print("  ", e)
        sys.exit(1)
    print("\nOK — o par JSON/PNG satisfaz o contrato do runtime.")


if __name__ == "__main__":
    main()
