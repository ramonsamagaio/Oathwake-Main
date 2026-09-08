#!/usr/bin/env python3
"""Inspecao pixel a pixel de uma celula do atlas, em texto.

Ver o PNG ampliado nao serve para decidir: a olho nao da para dizer se aquela
coluna tem 4 ou 5 pixels, nem se o tom da coluna 2 e o mesmo da coluna 3. Este
script imprime a celula como grade de caracteres, cada caractere sendo o indice
do tom dentro da rampa daquele material, e ainda mede:

  - largura por linha (para conferir a regra de perfil: tronco 50%, membro 100%)
  - quantos tons distintos a peca usa (regra: largura_px / 3, teto 5)
  - dL* entre tons vizinhos (piso 8) e contra a peca que encosta (piso 12)

Uso:
    python px.py <atlas.png> <x> <y> <w> <h> [colunas]
    python px.py hero                      # todas as pecas do heroi, coluna a coluna
"""
import sys
from collections import Counter

from PIL import Image

CH = "0123456789abcdefghijklmnopqrstuvwxyz"


def lab_l(c):
    from coloraide import Color
    return Color("srgb", [v / 255.0 for v in c[:3]]).convert("lab")["lightness"]


def cell_ascii(img, bx, by, w, h):
    p = img.load()
    cols = {}
    for y in range(by, by + h):
        for x in range(bx, bx + w):
            r, g, b, a = p[x, y]
            if a == 0 or (r > 240 and g < 20 and b > 170):
                continue
            cols[(r, g, b)] = cols.get((r, g, b), 0) + 1
    order = sorted(cols, key=lambda c: -lab_l(c))          # do mais claro ao mais escuro
    idx = {c: CH[i] for i, c in enumerate(order)}
    rows = []
    for y in range(by, by + h):
        line = ""
        for x in range(bx, bx + w):
            r, g, b, a = p[x, y]
            if a == 0 or (r > 240 and g < 20 and b > 170):
                line += "."
            else:
                line += idx[(r, g, b)]
        rows.append(line)
    return rows, order, cols


def report(img, name, bx, by, w, h, ncols=5, labels=("S", "SE", "E", "NE", "N")):
    print("\n=== %s  celula %dx%d  em (%d,%d)" % (name, w, h, bx, by))
    grids = []
    for c in range(ncols):
        rows, order, cnt = cell_ascii(img, bx + c * w, by, w, h)
        grids.append((labels[c], rows, order, cnt))
    for lab, rows, order, cnt in grids:
        widths = [len(r) - r.count(".") for r in rows]
        wid = max(widths) if widths else 0
        ntons = len(order)
        limite = max(1, min(5, round(wid / 3)))
        flag = "" if ntons <= limite + 1 else "  <- %d tons para %dpx (teto %d)" % (ntons, wid, limite)
        print("  [%s] largura max %2dpx  %d tons%s" % (lab, wid, ntons, flag))
    print()
    # imprime lado a lado
    hgt = h
    head = "     " + "   ".join(("%-*s" % (w, lab)) for lab, _r, _o, _c in grids)
    print(head)
    for y in range(hgt):
        line = "%3d  " % y
        line += "   ".join(("%-*s" % (w, g[1][y])) for g in grids)
        print(line)
    # rampa de cada coluna
    for lab, rows, order, cnt in grids:
        if not order:
            continue
        ls = [lab_l(c) for c in order]
        deltas = [round(ls[i] - ls[i + 1], 1) for i in range(len(ls) - 1)]
        bad = [d for d in deltas if d < 8]
        print("  [%s] L* %s   dL* %s%s" % (
            lab, " ".join("%.0f" % v for v in ls), " ".join("%.1f" % v for v in deltas),
            "   <- degrau abaixo de 8" if bad else ""))


HERO = [
    ("head", 0, 0, 20, 20), ("torso", 144, 0, 12, 12), ("abdomen", 144, 24, 12, 10),
    ("pelvis", 144, 44, 12, 12), ("pouch", 144, 56, 8, 10),
    ("thigh", 216, 0, 8, 12), ("shin", 216, 12, 8, 12), ("foot", 216, 24, 8, 8),
    ("upper_arm", 216, 40, 8, 10), ("forearm", 216, 50, 8, 8), ("hand", 216, 58, 8, 8),
]

if __name__ == "__main__":
    if sys.argv[1] == "hero":
        img = Image.open("her/oathwake_hero_01.png").convert("RGBA")
        only = sys.argv[2:] or None
        for n, bx, by, w, h in HERO:
            if only and n not in only:
                continue
            report(img, n, bx, by, w, h)
    else:
        img = Image.open(sys.argv[1]).convert("RGBA")
        a = [int(v) for v in sys.argv[2:6]]
        n = int(sys.argv[6]) if len(sys.argv) > 6 else 5
        report(img, "celula", a[0], a[1], a[2], a[3], n)
