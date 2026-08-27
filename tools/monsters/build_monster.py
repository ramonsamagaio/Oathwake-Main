#!/usr/bin/env python3
"""
Constroi o figure do monstro Oathwake a partir dos FBX do Mixamo.

NADA da Juno, do Male-Dummy ou de qualquer figure existente entra aqui:
  - a hierarquia e as proporcoes vem do esqueleto de rest do proprio FBX;
  - as animacoes vem das curvas dos FBX, retargetadas por delta global;
  - o atlas e o placeholder autoral gerado por make_monster_atlas.py.

Do repo so e reaproveitada a TECNICA: o formato de figure/anim que o
AlabasterRigRuntimeSource sabe ler.

Uso:
  python build_monster.py <pasta_gltf> <saida.json>
"""

import json
import math
import os
import sys

from gltf_rig import Gltf, Pose, q_mul, q_conj, q_norm, q_angle_between

# ---------------------------------------------------------------- convencoes
# Mixamo/assimp: X=direita, Y=cima, Z=frente  (destro)
# Figure Alabaster: X=direita, Y=frente, Z=cima  (canhoto)
# A troca Y<->Z e uma REFLEXAO (det = -1). Nao da para representar por
# quaternion, entao a conjugacao R_fig = M . R_mix . M^-1 e feita em matriz e
# so depois volta para quaternion. M e sua propria inversa.
AXIS_M = ((1.0, 0.0, 0.0),
          (0.0, 0.0, 1.0),
          (0.0, 1.0, 0.0))

# Altura do quadril em unidades de figure. Casa o monstro com a escala de mundo
# que o runtime ja usa (o rig projeta com PIXELS_PER_UNIT=16 / TILE_H=16).
HIP_HEIGHT_UNITS = 1.6875

SRC_TICK_RATE = 60.0
COMPENSATE_Z = True
BAKE_FPS = 30.0

# Regra geometrica do runtime (_build_state): o offset "pos" de um no e girado
# pela rotacao acumulada DO PROPRIO NO. Logo o bone que dirige o segmento
# pai->N e o bone Mixamo que fica NA articulacao do pai.
#   ROT_OF[N] = POS_OF[PARENT_OF[N]]
# Por isso a hierarquia segue as juntas do Mixamo 1:1: assim cada segmento
# corresponde a exatamente um bone, e o retarget fica exato em vez de aproximado.
#
# A arte de um no representa o segmento pai->N.
#
# nó, junta Mixamo, nó pai, peca de arte
RIG = [
    ("root",      "Hips",            None,        "abdomen"),
    ("bottom",    "Hips",            "root",      "pelvis"),

    ("hipL",      "LeftUpLeg",       "bottom",    None),
    ("legL",      "LeftLeg",         "hipL",      "upper_leg"),
    ("footL",     "LeftFoot",        "legL",      "shin"),
    ("toeL",      "LeftToeBase",     "footL",     "foot"),

    ("hipR",      "RightUpLeg",      "bottom",    None),
    ("legR",      "RightLeg",        "hipR",      "upper_leg"),
    ("footR",     "RightFoot",       "legR",      "shin"),
    ("toeR",      "RightToeBase",    "footR",     "foot"),

    ("spine",     "Spine",           "root",      None),
    ("top",       "Spine1",          "spine",     "top"),
    ("chest",     "Spine2",          "top",       None),
    ("neck",      "Neck",            "chest",     None),
    ("head",      "Head",            "neck",      "head"),

    ("shoulderL", "LeftShoulder",    "chest",     None),
    ("armL",      "LeftArm",         "shoulderL", "shoulder"),
    ("handL",     "LeftForeArm",     "armL",      "upper_arm"),
    ("fingerL",   "LeftHand",        "handL",     "forearm"),
    ("fistL",     "LeftHandIndex1",  "fingerL",   "fist"),

    ("shoulderR", "RightShoulder",   "chest",     None),
    ("armR",      "RightArm",        "shoulderR", "shoulder"),
    ("handR",     "RightForeArm",    "armR",      "upper_arm"),
    ("fingerR",   "RightHand",       "handR",     "forearm"),
    ("fistR",     "RightHandIndex1", "fingerR",   "fist"),
]
POS_OF = {n: j for n, j, _pa, _a in RIG}
PARENT_OF = {n: pa for n, _j, pa, _a in RIG}
ART_OF = {n: a for n, _j, _pa, a in RIG}
ORDER = [n for n, _j, _pa, _a in RIG]
# o bone que gira o segmento pai->N e o que esta na junta do pai
ROT_OF = {n: (POS_OF[PARENT_OF[n]] if PARENT_OF[n] else POS_OF[n]) for n, _j, _pa, _a in RIG}



# ------------------------------------------------------------- matriz/quat
def quat_to_mat(q):
    x, y, z, w = q_norm(q)
    return (
        (1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
        (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
        (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)),
    )


def mat_mul(a, b):
    return tuple(tuple(sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3))
                 for i in range(3))


def mat_to_quat(m):
    tr = m[0][0] + m[1][1] + m[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        q = ((m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s,
             (m[1][0] - m[0][1]) / s, 0.25 * s)
    elif m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        q = (0.25 * s, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s,
             (m[2][1] - m[1][2]) / s)
    elif m[1][1] > m[2][2]:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        q = ((m[0][1] + m[1][0]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s,
             (m[0][2] - m[2][0]) / s)
    else:
        s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
        q = ((m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s,
             (m[1][0] - m[0][1]) / s)
    return q_norm(q)


def to_figure_quat(q_mix):
    """R_fig = M . R_mix . M^-1, feito em matriz porque M reflete."""
    return mat_to_quat(mat_mul(mat_mul(AXIS_M, quat_to_mat(q_mix)), AXIS_M))


def to_figure_vec(v):
    return (v[0], v[2], v[1])


# ---------------------------------- codec de rotacao do runtime (V16 exato)
# _source_quat(): Q = Qz(yaw) * Qy(roll) * Qx(pitch), angulos em graus.
def runtime_angles_to_quat(yaw, pitch, roll):
    x = math.radians(pitch) * 0.5
    y = math.radians(roll) * 0.5
    z = math.radians(yaw) * 0.5
    sx, cx = math.sin(x), math.cos(x)
    sy, cy = math.sin(y), math.cos(y)
    sz, cz = math.sin(z), math.cos(z)
    return q_norm((
        sx * cy * cz - cx * sy * sz,
        cx * sy * cz + sx * cy * sz,
        cx * cy * sz - sx * sy * cz,
        cx * cy * cz + sx * sy * sz,
    ))


def quat_to_runtime_angles(q):
    """Inverso exato de runtime_angles_to_quat."""
    m = quat_to_mat(q)
    # Q = Qz(yaw) Qy(roll) Qx(pitch)  ->  decomposicao Z-Y-X intrinseca
    sy = -m[2][0]
    sy = max(-1.0, min(1.0, sy))
    roll = math.asin(sy)
    if abs(sy) < 0.999999:
        pitch = math.atan2(m[2][1], m[2][2])
        yaw = math.atan2(m[1][0], m[0][0])
    else:  # gimbal lock
        pitch = math.atan2(-m[1][2], m[1][1])
        yaw = 0.0
    return (math.degrees(yaw), math.degrees(pitch), math.degrees(roll))


def codec_self_test(samples=4000):
    import random
    rnd = random.Random(20260825)
    worst = 0.0
    for _ in range(samples):
        v = [rnd.gauss(0, 1) for _ in range(4)]
        q = q_norm(tuple(v))
        yaw, pitch, roll = quat_to_runtime_angles(q)
        back = runtime_angles_to_quat(yaw, pitch, roll)
        worst = max(worst, q_angle_between(q, back))
    return worst



# ---------------------------------------------- correcao da distorcao Z (1.325)
# O runtime nao gira o offset direto: _figure_transform comprime Z por 1/1.325,
# gira, e descomprime. Logo a rotacao que aponta o osso para o alvo NAO e a
# rotacao do Mixamo — e a rotacao resolvida no espaco comprimido.
# Resolver ali deixa a DIRECAO de cada osso exata; o twist em torno do eixo do
# osso (que decide pitch/facing do sprite) vem do delta original.
Z_SQUASH = 1.325


def _squash(v):
    return (v[0], v[1], v[2] / Z_SQUASH)


def _norm3(v):
    n = math.sqrt(sum(c * c for c in v))
    return (0.0, 0.0, 0.0) if n < 1e-12 else tuple(c / n for c in v)


def _swing(u, w):
    """Menor rotacao que leva o vetor unitario u ate w."""
    d = max(-1.0, min(1.0, sum(a * b for a, b in zip(u, w))))
    if d > 0.999999:
        return (0.0, 0.0, 0.0, 1.0)
    if d < -0.999999:
        axis = _norm3((-u[1], u[0], 0.0)) if abs(u[0]) + abs(u[1]) > 1e-6 else (1.0, 0.0, 0.0)
        return (axis[0], axis[1], axis[2], 0.0)
    c = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
    return q_norm((c[0], c[1], c[2], 1.0 + d))


def _twist_about(q, axis):
    """Componente de q que gira em torno de axis (swing-twist)."""
    proj = sum(q[i] * axis[i] for i in range(3))
    t = (axis[0] * proj, axis[1] * proj, axis[2] * proj, q[3])
    if sum(c * c for c in t) < 1e-12:
        return (0.0, 0.0, 0.0, 1.0)
    return q_norm(t)


# ----------------------------------------------------------------- figura
def build_nodes(gltf, rest, scale):
    def gpos(bone):
        idx = gltf.by_name.get("mixamorig:" + bone)
        if idx is None:
            raise SystemExit("bone Mixamo ausente no FBX: %s" % bone)
        return rest.pos[idx]

    nodes = {}
    for name in ORDER:
        parent = PARENT_OF[name]
        if parent is None:
            pos = (0.0, 0.0, gpos(POS_OF[name])[1] * scale)
        else:
            a = gpos(POS_OF[parent])
            b = gpos(POS_OF[name])
            delta = tuple((b[i] - a[i]) * scale for i in range(3))
            pos = to_figure_vec(delta)
        nodes[name] = {
            "parent": parent or "",
            "pos": [round(v, 6) for v in pos],
            "colls": [],
            "gfx": [],
        }
    nodes["root"].pop("parent")
    nodes["root"]["parent"] = ""
    # sockets de arma: bones sem pixels, iguais em conceito ao source
    for socket, host in (("weaponR", "fingerR"), ("weaponL", "fingerL")):
        nodes[socket] = {"parent": host, "pos": [0.0, 0.0, 0.0], "colls": [], "gfx": []}
    return nodes


# --------------------------------------------------------------- animacao
def bake_clip(gltf, clip_name, category, loop, root_motion=False,
              compensate_z=True, rest_offsets=None):
    tracks = gltf.animation_tracks(0)
    rest = Pose(gltf, {})
    duration = gltf.duration(0)
    frame_repeat = int(round(SRC_TICK_RATE / BAKE_FPS))
    frame_count = max(2, int(round(duration * BAKE_FPS)))

    rest_offsets = rest_offsets or {}
    rest_fig = {}
    for name in ORDER:
        idx = gltf.by_name["mixamorig:" + ROT_OF[name]]
        rest_fig[name] = to_figure_quat(rest.rot[idx])

    hip_rest_y = rest.pos[gltf.by_name["mixamorig:Hips"]][1]
    scale = HIP_HEIGHT_UNITS / hip_rest_y

    transforms = []
    poses = []
    for f in range(frame_count):
        t = duration * (f / float(frame_count)) if loop else duration * (f / float(max(1, frame_count - 1)))
        pose = Pose(gltf, tracks, t)
        poses.append(pose)

        cumulative = {}
        for name in ORDER:
            idx = gltf.by_name["mixamorig:" + ROT_OF[name]]
            cur = to_figure_quat(pose.rot[idx])
            # delta global em relacao ao rest: D = Q_atual * Q_rest^-1
            cumulative[name] = q_norm(q_mul(cur, q_conj(rest_fig[name])))

        if compensate_z:
            for name in ORDER:
                parent = PARENT_OF[name]
                if not parent or name not in rest_offsets:
                    continue
                rest_off = rest_offsets[name]
                ia = gltf.by_name["mixamorig:" + POS_OF[parent]]
                ib = gltf.by_name["mixamorig:" + POS_OF[name]]
                target = to_figure_vec(tuple(pose.pos[ib][i] - pose.pos[ia][i]
                                             for i in range(3)))
                u = _norm3(_squash(rest_off))
                w = _norm3(_squash(target))
                if u == (0.0, 0.0, 0.0) or w == (0.0, 0.0, 0.0):
                    continue
                twist = _twist_about(cumulative[name], u)
                cumulative[name] = q_norm(q_mul(_swing(u, w), twist))

        node_xfm = {}
        for name in ORDER:
            parent = PARENT_OF[name]
            if parent is None:
                local = cumulative[name]
            else:
                local = q_norm(q_mul(q_conj(cumulative[parent]), cumulative[name]))
            yaw, pitch, roll = quat_to_runtime_angles(local)
            entry = {}
            if max(abs(yaw), abs(pitch), abs(roll)) > 0.0005:
                entry["rot"] = [round(yaw, 4), round(pitch, 4), round(roll, 4)]
            if name == "root" and root_motion:
                hips = pose.pos[gltf.by_name["mixamorig:Hips"]]
                dy = (hips[1] - hip_rest_y) * scale
                if abs(dy) > 0.0005:
                    entry["trans"] = [0.0, 0.0, round(dy, 5)]
            node_xfm[name] = entry

        transforms.append({
            "frame": f * frame_repeat,
            "hooks": [],
            "nodeXfm": node_xfm,
            "spline": "LINEAR",
        })

    anim = {
        "animStart": 0,
        "category": category,
        "frameCnt": frame_count * frame_repeat,
        "frameRepeat": frame_repeat,
        "loopStart": 0,
        "repeat": bool(loop),
        "transforms": transforms,
        "nodes": {},
    }
    return anim, poses, rest, scale


# --------------------------------------------------- reconstrucao FK (teste)
def figure_transform(v, q):
    """Igual ao _figure_transform do runtime: escala Z por 1/1.325, gira, desescala."""
    k = 1.325
    p = (v[0], v[1], v[2] / k)
    from gltf_rig import q_rotate
    r = q_rotate(q, p)
    return (r[0], r[1], r[2] * k)


def fk_positions(nodes, node_xfm):
    """Reproduz _build_state: dir_q acumula, pos do nó e girado por dir_q."""
    from gltf_rig import q_rotate
    dirq = {}
    root_pos = {}
    for name in ORDER:
        parent = nodes[name]["parent"]
        entry = node_xfm.get(name, {})
        local = (0.0, 0.0, 0.0, 1.0)
        if "rot" in entry:
            local = runtime_angles_to_quat(*entry["rot"])
        if parent:
            local = q_norm(q_mul(dirq[parent], local))
        dirq[name] = local
        pos = tuple(nodes[name]["pos"])
        if parent:
            pos = figure_transform(pos, local)
        base = root_pos[parent] if parent else (0.0, 0.0, 0.0)
        if not parent:
            base = (0.0, 0.0, 0.0)
            pos = tuple(nodes[name]["pos"])
        root_pos[name] = tuple(a + b for a, b in zip(pos, base))
    return root_pos


def main():
    src_dir, out_path = sys.argv[1], sys.argv[2]
    clips = [
        ("Walking.gltf", "walk", "MOVE", True, False),
        ("Fast Run.gltf", "run", "MOVE", True, False),
        ("Punching.gltf", "punch", "ATTACK", False, False),
    ]

    err = codec_self_test()
    print("codec self-test: erro maximo %.6f graus em 4000 quaternions aleatorios" % err)
    if err > 0.01:
        raise SystemExit("codec de rotacao nao fecha; abortando")

    base_gltf = Gltf(os.path.join(src_dir, clips[0][0]))
    base_rest = Pose(base_gltf, {})
    hip_rest_y = base_rest.pos[base_gltf.by_name["mixamorig:Hips"]][1]
    scale = HIP_HEIGHT_UNITS / hip_rest_y
    nodes = attach_gfx(build_nodes(base_gltf, base_rest, scale))
    print("escala figure = %.6f unidades por cm Mixamo (quadril %.2f -> %.4f)"
          % (scale, hip_rest_y, HIP_HEIGHT_UNITS))

    rest_offsets = {n: tuple(nodes[n]["pos"]) for n in ORDER if PARENT_OF[n]}
    anims = {}
    report = []
    for filename, anim_name, category, loop, root_motion in clips:
        path = os.path.join(src_dir, filename)
        if not os.path.exists(path):
            print("AVISO: %s ausente, pulando" % filename)
            continue
        g = Gltf(path)
        anim, poses, rest, sc = bake_clip(g, anim_name, category, loop, root_motion,
                                          COMPENSATE_Z, rest_offsets)
        anims[anim_name] = anim

        # ---- teste: direcao de cada osso na FK reconstruida x pose real.
        # A metrica e ANGULAR de proposito: "Fast Run" vem de um personagem
        # Mixamo com outras proporcoes, entao comparar posicao mediria a
        # diferenca de esqueleto, nao a fidelidade do retarget.
        worst = 0.0
        worst_bone = ""
        total = 0.0
        count = 0
        for f, pose in enumerate(poses):
            fk = fk_positions(nodes, anim["transforms"][f]["nodeXfm"])
            for name in ORDER:
                parent = PARENT_OF[name]
                if not parent:
                    continue
                ia = g.by_name["mixamorig:" + POS_OF[parent]]
                ib = g.by_name["mixamorig:" + POS_OF[name]]
                ref = to_figure_vec(tuple(pose.pos[ib][i] - pose.pos[ia][i] for i in range(3)))
                got = tuple(fk[name][i] - fk[parent][i] for i in range(3))
                na = math.dist((0, 0, 0), ref)
                nb = math.dist((0, 0, 0), got)
                if na < 1e-6 or nb < 1e-6:
                    continue
                dot = sum(a * b for a, b in zip(ref, got)) / (na * nb)
                ang = math.degrees(math.acos(max(-1.0, min(1.0, dot))))
                total += ang
                count += 1
                if ang > worst:
                    worst, worst_bone = ang, name
        report.append((anim_name, anim["frameCnt"], anim["frameRepeat"],
                       len(anim["transforms"]), worst, worst_bone,
                       total / max(count, 1)))

    payload = {
        "figures": {
            "Oathwake-Monster-01": {
                "nodes": nodes,
                "actorReduce": 0,
                "bounds": [-0.5, -0.5, 0.0, 0.5, 0.5, 2.6],
                "globalZOrder": 16,
                "halfPixelShift": True,
                "nodeAlign": {},
                "rootFacing": "FACE_16",
                "variants": {},
                "windSway": 0,
                "anims": anims,
            }
        },
        "spriteSheets": {
            "Male-1": {"img": "media/char/oathwake_monster_01.png",
                       "range": [0, 0, 672, 120]}
        },
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))

    print()
    print("%-8s %7s %7s %7s %10s %10s   %s" % ("anim", "frames", "repeat", "keys", "erro med", "erro max", "pior osso"))
    print("-" * 76)
    for name, cnt, rep, keys, worst, bone, mean in report:
        print("%-8s %7d %7d %7d %9.3f\u00b0 %9.3f\u00b0   %s"
              % (name, cnt, rep, keys, mean, worst, bone))
    print()
    print("nós: %d   animações: %s" % (len(nodes), ", ".join(sorted(anims))))
    print("saída:", out_path)




# ============================================================ graficos (gfx)
# Regra: a arte de um no representa o segmento pai->N, ancorada no no N.
# Pecas de membro usam PARENT_ROTATE_* : o runtime estica/corta a arte entre o
# no e o pai, entao o pivo fica na ponta distal (embaixo da celula).
#
# bloco do atlas -> (x, y, w, h, linhas de pitch, pivotX, pivotY, texRotate, zOrder)
ATLAS = {
    "head":      (0, 0, 16, 16, ["UP1+", "ALL", "DOWN1+"], 0.5, 0.88, "NONE", 12),
    "torso":     (0, 48, 16, 16, ["ALL", "DOWN1+"], 0.5, 0.80, "NONE", -4),
    "abdomen":   (0, 80, 16, 12, ["ALL", "DOWN1+"], 0.5, 0.70, "NONE", -6),
    "pelvis":    (0, 104, 16, 12, ["ALL"], 0.5, 0.50, "NONE", 0),
    "upper_leg": (144, 0, 8, 16, ["ALL"], 0.5, 1.0, "PARENT_ROTATE_SCALE", 11),
    "shin":      (144, 16, 8, 12, ["ALL"], 0.5, 1.0, "PARENT_ROTATE_SCALE", 3),
    "foot":      (144, 28, 12, 12, ["ALL"], 0.5, 0.35, "ROTATE", 0),
    "shoulder":  (208, 0, 8, 8, ["ALL"], 0.5, 0.5, "ROTATE", 1),
    "upper_arm": (208, 8, 8, 12, ["ALL"], 0.5, 1.0, "PARENT_ROTATE_SCALE", 0),
    "forearm":   (208, 20, 8, 8, ["ALL"], 0.5, 1.0, "PARENT_ROTATE_SCALE", 2),
    "fist":      (208, 28, 8, 8, ["ALL"], 0.5, 0.5, "PARENT_ROTATE", 4),
}

# qual bloco cada no desenha, e o facing dele.
# corpo em 4 direcoes (colunas 1 e 3 sao copias), cabeca em 8 -> tudo FACE_8_MIRR
# lado direito reusa as mesmas celulas espelhadas com _FLIP
ART = {
    "bottom": ("pelvis", "FACE_8_MIRR"),
    "top": ("abdomen", "FACE_8_MIRR"),
    "chest": ("torso", "FACE_8_MIRR"),
    "head": ("head", "FACE_8_MIRR"),
    "legL": ("upper_leg", "FACE_8_MIRR"), "legR": ("upper_leg", "FACE_8_MIRR_FLIP"),
    "footL": ("shin", "FACE_8_MIRR"), "footR": ("shin", "FACE_8_MIRR_FLIP"),
    "toeL": ("foot", "FACE_8_MIRR"), "toeR": ("foot", "FACE_8_MIRR_FLIP"),
    "armL": ("shoulder", "FACE_8_MIRR"), "armR": ("shoulder", "FACE_8_MIRR_FLIP"),
    "handL": ("upper_arm", "FACE_8_MIRR"), "handR": ("upper_arm", "FACE_8_MIRR_FLIP"),
    "fingerL": ("forearm", "FACE_8_MIRR"), "fingerR": ("forearm", "FACE_8_MIRR_FLIP"),
    "fistL": ("fist", "FACE_8_MIRR"), "fistR": ("fist", "FACE_8_MIRR_FLIP"),
}


def attach_gfx(nodes):
    for node_name, (block, facing) in ART.items():
        x, y, w, h, rows, pivx, pivy, texrot, zorder = ATLAS[block]
        nodes[node_name]["gfx"] = [{
            "hidden": False,
            "pos": [0.0, 0.0, 0.0],
            "shape": {"billboard": {
                "cutInverse": False, "cutScaleShift": 0,
                "pivotX": pivx, "pivotY": pivy,
                "shadow": True, "shadowTolerance": True,
                "sheer": 0.5, "windWiggle": 0, "zOrder": zorder,
            }},
            "style": "NORMAL",
            "tex": {"multi": {
                "onMissingFrame": "USE_DEFAULT",
                "entries": {"default": {
                    "facing": facing,
                    "flipShift": 0,
                    "sheet": "Male-1",
                    "range": [x, y, w, h],
                    "variants": [],
                    "rows": [{"pitchRange": pr, "refAngles": [],
                              "texRotate": texrot, "frameKeys": []} for pr in rows],
                }},
            }},
        }]
    return nodes


if __name__ == "__main__":
    main()
