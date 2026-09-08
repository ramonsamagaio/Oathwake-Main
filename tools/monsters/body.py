#!/usr/bin/env python3
"""Gera as grades do corpo do heroi com ORCAMENTO DE TOM explicito.

Medido com px.py na versao anterior:

    peca        largura   tons usados   teto (largura/3)
    thigh         5px         5              2
    upper_arm     4px         5              1-2
    torso        10px        11              3-4

Duas a tres vezes o orcamento em toda peca. Num membro de 4px, 5 tons nao sao
sombreamento — sao 5 colunas de 1px cada, que e a definicao de ruido. E o que
o autor via como "montagem confusa" e "membros que se confundem com o corpo":
nenhuma peca tinha uma forma legivel, todas tinham textura.

Aqui a arte e gerada de um ESTENCIL: por direcao, uma largura (vinda da
antropometria) e um numero de tons (vindo da largura). O preenchimento e uma
rampa horizontal em bandas iguais. Contorno seletivo: o lado da luz (esquerda)
recebe o tom claro do proprio corpo, o lado da sombra recebe o contorno escuro
— contorno fechado nos dois lados e o que faz peca de rig ler como recorte de
papel.

Larguras por direcao (ANSUR II, percentil 50):
    tronco / ombros   perfil = 50% da frente
    quadril           perfil = 62%
    membro            perfil = 100%   (secao circular)
    cabeca            perfil = 130%   (tratada em hero_skin, nao aqui)
"""

DIRS = ["S", "SE", "E", "NE", "N"]


def _bands(n, tones):
    """Indice de tom (1..tones) para cada uma das n colunas internas."""
    if n <= 0:
        return []
    return [min(tones, 1 + (i * tones) // n) for i in range(n)]


def piece(h, widths, cw, tones=2, rows_open=(), accents=None, tail=0, prof=None,
          slide=None, bands=None, inset=None, top=0):
    """Monta a peca nas 5 direcoes.

    h        altura util (linhas desenhadas, do topo)
    widths   largura total por direcao, dict ou lista de 5
    cw       largura da celula
    tones    tons internos (fora o contorno)
    rows_open linhas que NAO levam contorno inferior (ponta proximal aberta:
             sem isso a emenda com a peca de cima le como linha preta)
    accents  {linha: string de 'cw' caracteres} desenhada por cima
    tail     linhas vazias no fim da celula
    """
    if isinstance(widths, (list, tuple)):
        widths = dict(zip(DIRS, widths))
    out = {}
    for d in DIRS:
        w = widths[d]
        inner = max(1, w - 1)          # o contorno da direita ocupa 1 coluna
        band = _bands(inner, tones)
        rows = []
        for y in range(h):
            # perfil por linha: um membro nao e um retangulo. A coxa afina do
            # quadril ao joelho, a canela tem barriga da panturrilha. Sem isso
            # a peca le como tira de papelao — que era o defeito de perfil.
            dw = prof[y] if prof and y < len(prof) else 0
            ww = max(2, w + dw)
            inner_y = max(1, ww - 1)
            band_y = _bands(inner_y, tones)
            # terminador deslizante: a partir da linha `slide` a banda clara
            # anda 1px, o que sugere cilindro em vez de placa chapada.
            if slide is not None and y >= slide and len(band_y) > 2:
                band_y = band_y[1:] + [band_y[-1]]
            x0 = (cw - ww) // 2
            line = ["."] * cw
            for i, t in enumerate(band_y):
                line[x0 + i] = str(t)
            line[x0 + inner_y] = "0"      # contorno so do lado da sombra
            rows.append("".join(line))
        x0 = (cw - w) // 2
        # tampa inferior
        if h - 1 not in rows_open:
            last = list(rows[-1])
            for i in range(cw):
                if last[i] != ".":
                    last[i] = "0"
            rows[-1] = "".join(last)
        if bands:
            # faixa que segue a LARGURA DA LINHA, nao uma string fixa. Um cinto
            # escrito como ".0LLLLLLLL0." tem 10px em todas as direcoes, e ai o
            # tronco de perfil (6px) volta a medir 10 — o aperto do perfil so
            # existe se o acento apertar junto.
            for y, spec in bands.items():
                if not (0 <= y < h):
                    continue
                line = list(rows[y])
                xs = [i for i, c in enumerate(line) if c != "."]
                if not xs:
                    continue
                mid, edge = spec
                for i in xs:
                    line[i] = mid
                if edge:
                    line[xs[-1]] = edge
                rows[y] = "".join(line)
        if inset:
            # faixa CENTRADA e estreita. Um pescoco desenhado na largura toda
            # do tronco vira uma barra de pele debaixo do queixo — foi o que
            # aconteceu quando o cinto e a gola passaram a seguir a largura.
            for y, (ch, margin) in inset.items():
                if not (0 <= y < h):
                    continue
                line = list(rows[y])
                xs = [i for i, c in enumerate(line) if c != "."]
                if not xs:
                    continue
                a, b = xs[0] + margin, xs[-1] - margin
                for i in range(len(line)):
                    line[i] = ch if a <= i <= b else "."
                if b + 1 < len(line):
                    line[b + 1] = "0"
                rows[y] = "".join(line)
        if accents:
            for y, s in accents.items():
                if 0 <= y < h:
                    base = list(rows[y])
                    for i, ch in enumerate(s):
                        if ch != " " and i < cw:
                            base[i] = ch
                    rows[y] = "".join(base)
        # `top` = linhas vazias ANTES da arte. Em peca com pivo Y 1.0 quem
        # encosta na junta e a ULTIMA linha da celula: pondo o vazio no fim, a
        # arte ficava 4-5px acima do pivo e a emenda abria (medido: vao de
        # 5.4px entre antebraco e braco). O vazio vai em cima.
        rows = ["." * cw] * top + rows + ["." * cw] * tail
        out[d] = rows
    return out


# --------------------------------------------------------------------- pecas
# Largura por direcao. O membro NAO muda; o tronco cai pela metade de perfil.
W_TORSO = [10, 9, 6, 9, 10]
W_PELVIS = [10, 9, 7, 9, 10]
W_LIMB4 = [4, 4, 4, 4, 4]
W_LIMB5 = [5, 5, 5, 5, 5]
W_LIMB6 = [6, 6, 6, 6, 6]


def build():
    g = {}

    # TRONCO 12x12. 10px de largura -> 3 tons (10/3). Gola e cinto sao acentos.
    #   linha 0-1  pescoco + gola: fecha o buraco preto sob o queixo
    #   linha 2-8  peito, com o baldric de couro na diagonal
    #   linha 9-10 cinto com fivela
    tor = piece(12, W_TORSO, 12, tones=3,
                prof=[0, 0, 0, 0, 0, 0, -1, -1, -1, -1, -1, -1],
                bands={9: ("L", "0"), 10: ("l", "0")},
                inset={0: ("q", 3), 1: ("U", 2)})
    for i, d in enumerate(DIRS):
        rows = tor[d]
        # fivela: 2px de ouro no centro da linha do cinto. E o unico acento
        # realmente saturado do personagem — orcamento 3-5% da area.
        line = list(rows[10])
        xs = [k for k, c in enumerate(line) if c != "."]
        if len(xs) >= 4:
            c0 = xs[len(xs) // 2 - 1]
            line[c0] = "X"
            line[c0 + 1] = "X"
            rows[10] = "".join(line)
        # baldric: uma diagonal de couro do ombro ao quadril. E o unico detalhe
        # de identidade que sobrevive a 10px de largura.
        x0 = (12 - W_TORSO[i]) // 2
        for k, y in enumerate(range(2, 9)):
            x = x0 + 1 + k
            if x < 12 - 1 and rows[y][x] not in ".0":
                rows[y] = rows[y][:x] + "L" + rows[y][x + 1:]
    g["TORSO"] = tor

    # ABDOMEN 12x10, mesma largura do tronco, sem cinto (um cinto por corpo).
    g["ABDOMEN"] = piece(10, W_TORSO, 12, tones=3, tail=0)

    # PELVE 12x12: 8 linhas de massa, 4 vazias — a coxa precisa de espaco.
    g["PELVIS"] = piece(8, W_PELVIS, 12, tones=3,
                        prof=[0, 0, 0, 0, -1, -1, -2, -3],
                        bands={0: ("L", "0"), 1: ("l", "0")}, tail=4)

    # BOLSA 8x10 no quadril
    g["POUCH"] = piece(7, [6, 6, 5, 6, 6], 8, tones=2,
                       bands={0: ("L", "0"), 6: ("l", "0")}, tail=3)

    # COXA 8x12 e CANELA 8x12: 5px -> 2 tons. Ponta de cima ABERTA (rows_open)
    # para a emenda com a pelve nao virar linha preta.
    # coxa: afina do quadril (5px) ao joelho (4px); terminador desliza na
    # metade, que e onde a curvatura da coxa muda de lado.
    g["THIGH"] = piece(12, W_LIMB5, 8, tones=2,
                       prof=[1, 1, 1, 0, 0, 0, 0, -1, -1, -1, -1, -1], slide=6)
    # canela: estreita no joelho, barriga da panturrilha no meio, estreita no
    # tornozelo. As duas linhas de couro sao o cano da bota.
    g["SHIN"] = piece(12, W_LIMB5, 8, tones=2,
                      prof=[-1, -1, 0, 0, 0, 0, -1, -1, -1, -1, -1, -1], slide=7,
                      bands={6: ("L", "0"), 7: ("l", "0")})
    # BOTA 8x8: 6px, 2 tons
    g["FOOT"] = piece(8, W_LIMB6, 8, tones=2,
                      prof=[-1, -1, 0, 0, 0, 0, 0, -1])

    # OMBREIRA: fora (a Juno nao tem arte de ombro em no proprio)
    g["SHOULDER"] = piece(1, [1] * 5, 8, tones=1, tail=7)

    # BRACO 8x10: 4px -> 2 tons. 6 linhas de arte para um osso de 5.4px.
    # pivo Y 1.0 -> a arte tem de terminar na ULTIMA linha da celula (10)
    g["UPPER_ARM"] = piece(6, W_LIMB4, 8, tones=2, top=4,
                           prof=[1, 0, 0, 0, 0, -1], slide=3)
    # ANTEBRACO 8x8: 4px, 2 tons, 7 linhas
    g["FOREARM"] = piece(7, W_LIMB4, 8, tones=2, top=1,
                         prof=[-1, 0, 1, 1, 0, 0, -1], slide=4)
    # MAO 8x8: pele, 2 tons
    # mao: enche a celula inteira (pivo 0.5). Com 6 linhas o vao punho->mao
    # abria 3px nos quadros de soco e corrida.
    # 5px, nao 4: o vao punho->mao que sobrava era LATERAL (aparecia em
    # face112, com o braco girado), e vao lateral se fecha alargando a peca.
    # 5px de largura (fecha o vao LATERAL) mas so 5 linhas, centradas no pivo
    # 0.5. Preenchendo as 8 linhas a mao virava um bloco de pele maior que o
    # rosto — e pele e o tom mais claro do personagem, entao ela rouba o olho.
    g["HAND"] = piece(5, W_LIMB5, 8, tones=2, top=2, tail=1,
                      prof=[-1, 0, 0, 0, -1])
    for d in DIRS:
        # mao de volta em SKIN/SKIN_SH. Escurecendo para q/w ela caia em 63 e o
        # realce do couro esta em 57: dL* 5.7, e o punho sumia. Mao e rosto sao
        # o MESMO material; o problema da mao nunca foi o brilho, foi o tamanho.
        g["HAND"][d] = [r.replace("1", "Q").replace("2", "q") for r in g["HAND"][d]]
    return g


if __name__ == "__main__":
    gg = build()
    for name in ["TORSO", "THIGH", "UPPER_ARM"]:
        print("---", name)
        for y in range(len(gg[name]["S"])):
            print("   " + "   ".join(gg[name][d][y] for d in DIRS))
