#!/usr/bin/env python3
"""
Compositor offline do rig Alabaster: monta as pecas do atlas nas posicoes
projetadas, para conferir a skin sem abrir o Godot.

Reproduz do AlabasterRigRuntimeSource:
  - _build_state  (FK, com a compressao Z de 1.325)
  - _globalize / _snap_world / _project_world  (camera do source)
  - _facing_table (coluna por direcao, com espelho)
  - _pitch_slot / _pitch_bounds (linha por inclinacao)
  - pivo, zOrder, e PARENT_ROTATE_* (gira e estica a peca entre dois nós)

Uso: python render_sprite.py <figure.json> <atlas.png> <saida.png> [anim]
"""

import json
import math
import sys

from PIL import Image
import build_monster as B
from gltf_rig import q_mul, q_conj, q_norm, q_rotate

TILE_W, TILE_H = 24.0, 16.0
FOV = math.radians(25.0)
CAM_X = -math.pi * 0.25
SKEW = 0.45
SW, SH = 640.0, 360.0
CAM_Z = SH / (2.0 * math.tan(FOV * 0.5) * TILE_H)
Z_K = 1.325

A8 = [25.0, 70.0, 115.0, 160.0, 200.0, 245.0, 290.0, 335.0]
FACING = {
    "FACE_8_MIRR": (A8, [4, 3, 2, 1, 0, 1, 2, 3], [0, 0, 0, 0, 0, 1, 1, 1]),
    "FACE_8_MIRR_FLIP": (A8, [4, 3, 2, 1, 0, 1, 2, 3], [1, 0, 0, 0, 1, 1, 1, 1]),
}
PITCH = {"ALL": (0, 11), "UP1+": (5, 11), "DOWN1+": (0, 3), "NORM": (4, 4)}
SLOTS = [-105.0, -75.0, -45.0, -15.0, 15.0, 45.0, 75.0, 105.0, 135.0, 165.0, 195.0]


def norm_deg(v):
    return v % 360.0


def globalize(v, face):
    a = math.radians(face - 180.0)
    c, s = math.cos(a), math.sin(a)
    o = (v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2])
    return (round(o[0] * TILE_W * 2) / (TILE_W * 2),
            round(o[1] * TILE_H * 2) / (TILE_H * 2),
            round(o[2] * TILE_H * 2) / (TILE_H * 2))


def project(w):
    x = w[0] * (TILE_W / TILE_H)
    y = -w[1] + SKEW * w[2]
    z = w[2]
    c, s = math.cos(CAM_X), math.sin(CAM_X)
    vy = y * c - z * s
    vz = y * s + z * c - CAM_Z
    ww = max(-vz, 0.001)
    f = 1.0 / math.tan(FOV * 0.5)
    return (SW * 0.5 * ((f / (SW / SH)) * x / ww), -SH * 0.5 * (f * vy / ww))


def yaw_pitch(q):
    yaw = math.degrees(math.atan2(2 * (q[0] * q[1] + q[2] * q[3]),
                                  1 - 2 * (q[1] * q[1] + q[2] * q[2])))
    pit = math.degrees(math.atan2(2 * (q[0] * q[3] + q[1] * q[2]),
                                  1 - 2 * (q[0] * q[0] + q[1] * q[1])))
    return yaw, pit


def pitch_slot(p):
    if p < -135.0:
        p += 360.0
    for i, s in enumerate(SLOTS):
        if p < s:
            return i
    return 11


def select_tile(mode, yaw):
    angles, tiles, flips = FACING[mode]
    for i, th in enumerate(angles):
        if th >= yaw:
            return tiles[i], bool(flips[i])
    return tiles[0], bool(flips[0])


def fk(nodes, nx, order):
    """Igual ao _build_state: dir_q acumula; o pos do nó gira pelo dir_q dele."""
    dirq, pos = {}, {}
    for name in order:
        parent = nodes[name].get("parent", "")
        e = nx.get(name, {})
        local = (0.0, 0.0, 0.0, 1.0)
        if "rot" in e:
            local = B.runtime_angles_to_quat(*e["rot"])
        if parent:
            local = q_norm(q_mul(dirq[parent], local))
        dirq[name] = local
        p = tuple(nodes[name]["pos"])
        if parent:
            p = B.figure_transform(p, local)
            p = tuple(a + b for a, b in zip(p, pos[parent]))
        pos[name] = p
    return dirq, pos


def render(figure, atlas, anim_name, face, frame_index, scale=4.0, size=(260, 300)):
    nodes = figure["nodes"]
    order = [n for n in B.ORDER if n in nodes]
    anim = figure["anims"][anim_name]
    nx = anim["transforms"][frame_index % len(anim["transforms"])]["nodeXfm"]
    dirq, wpos = fk(nodes, nx, order)

    img = Image.new("RGBA", size, (0, 0, 0, 0))
    draws = []
    for name in order:
        for gi, gfx in enumerate(nodes[name].get("gfx", [])):
            bb = gfx["shape"]["billboard"]
            entry = gfx["tex"]["multi"]["entries"]["default"]
            mode = entry["facing"]
            if mode not in FACING:
                continue
            bx, by, w, h = entry["range"]
            rows = entry.get("rows", [{}])

            node_yaw, node_pitch = yaw_pitch(dirq[name])
            slot = pitch_slot(node_pitch)
            row_index, best = 0, 99
            for ri, row in enumerate(rows):
                lo, hi = PITCH.get(row.get("pitchRange", "ALL"), (0, 11))
                if lo <= slot <= hi and (hi - lo) < best:
                    row_index, best = ri, hi - lo
            tile, flip = select_tile(mode, norm_deg(face + node_yaw) or 0.001)

            cellimg = atlas.crop((bx + w * tile, by + h * row_index,
                                  bx + w * (tile + 1), by + h * (row_index + 1)))
            if flip:
                cellimg = cellimg.transpose(Image.FLIP_LEFT_RIGHT)

            screen = project(globalize(wpos[name], face))
            pivx = w * float(bb.get("pivotX", 0.5))
            pivy = h * float(bb.get("pivotY", 0.5))
            if flip:
                pivx = w - pivx

            texrot = rows[row_index].get("texRotate", "NONE")
            if texrot.startswith("PARENT_ROTATE") or texrot == "ROTATE_SCALE":
                parent = nodes[name].get("parent", "")
                if parent:
                    ps = project(globalize(wpos[parent], face))
                    dx, dy = ps[0] - screen[0], ps[1] - screen[1]
                    dist = math.hypot(dx, dy)
                    ang = math.degrees(math.atan2(dx, -dy))
                    if "SCALE" in texrot and h > 0 and dist > 0.5:
                        nh = max(2, int(round(dist)))
                        cellimg = cellimg.resize((w, nh), Image.NEAREST)
                        pivy = pivy * nh / h
                    cellimg = cellimg.rotate(-ang, expand=True, resample=Image.NEAREST)
                    pivx, pivy = cellimg.width / 2.0, cellimg.height / 2.0
                    cx = (screen[0] + ps[0]) / 2.0
                    cy = (screen[1] + ps[1]) / 2.0
                    screen = (cx, cy)

            z = int(figure.get("globalZOrder", 0)) + int(bb.get("zOrder", 0))
            draws.append((z, cellimg, screen, pivx, pivy))

    draws.sort(key=lambda t: t[0])
    ox, oy = size[0] / 2.0, size[1] - 60
    for _z, cellimg, screen, pivx, pivy in draws:
        big = cellimg.resize((int(cellimg.width * scale), int(cellimg.height * scale)),
                             Image.NEAREST)
        x = int(round(ox + screen[0] * scale - pivx * scale))
        y = int(round(oy + screen[1] * scale - pivy * scale))
        img.alpha_composite(big, (x, y))
    return img


def main():
    fig_path, atlas_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    anim_name = sys.argv[4] if len(sys.argv) > 4 else "walk"
    payload = json.load(open(fig_path, encoding="utf-8"))
    figure = payload["figures"][sorted(payload["figures"])[0]]
    atlas = Image.open(atlas_path).convert("RGBA")
    px = atlas.load()
    for y in range(atlas.height):
        for x in range(atlas.width):
            if px[x, y][:3] == (255, 0, 195):
                px[x, y] = (0, 0, 0, 0)

    faces = [180.0, 135.0, 90.0, 45.0, 0.0]
    labels = ["S", "SE", "E", "NE", "N"]
    frames = [0, 4, 8, 12]
    cw, ch = 260, 300
    sheet = Image.new("RGBA", (cw * len(faces), ch * len(frames)), (22, 24, 30, 255))
    for r, fr in enumerate(frames):
        for c, face in enumerate(faces):
            sheet.alpha_composite(render(figure, atlas, anim_name, face, fr,
                                         scale=4.0, size=(cw, ch)), (c * cw, r * ch))
    sheet.save(out_path)
    print("ok ->", out_path, "| anim:", anim_name, "| vistas:", labels)


if __name__ == "__main__":
    main()
