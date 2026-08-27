"""Leitor minimo de glTF (saida do assimp) focado em esqueleto + animacao.

Nao depende de nenhuma lib de 3D: le o JSON, o .bin, e resolve
hierarquia, TRS estatico e curvas de animacao.
"""

import base64
import json
import math
import os
import struct

COMPONENT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
             5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


# ------------------------------------------------------------------ quaternions
def q_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (
        aw * bx + ax * bw + ay * bz - az * by,
        aw * by - ax * bz + ay * bw + az * bx,
        aw * bz + ax * by - ay * bx + az * bw,
        aw * bw - ax * bx - ay * by - az * bz,
    )


def q_conj(q):
    return (-q[0], -q[1], -q[2], q[3])


def q_norm(q):
    n = math.sqrt(sum(c * c for c in q))
    if n < 1e-12:
        return (0.0, 0.0, 0.0, 1.0)
    return tuple(c / n for c in q)


def q_slerp(a, b, t):
    a = q_norm(a)
    b = q_norm(b)
    d = sum(x * y for x, y in zip(a, b))
    if d < 0.0:
        b = tuple(-c for c in b)
        d = -d
    if d > 0.9995:
        return q_norm(tuple(x + (y - x) * t for x, y in zip(a, b)))
    theta = math.acos(max(-1.0, min(1.0, d)))
    st = math.sin(theta)
    wa = math.sin((1.0 - t) * theta) / st
    wb = math.sin(t * theta) / st
    return q_norm(tuple(x * wa + y * wb for x, y in zip(a, b)))


def q_rotate(q, v):
    qv = (v[0], v[1], v[2], 0.0)
    r = q_mul(q_mul(q, qv), q_conj(q))
    return (r[0], r[1], r[2])


def q_angle_between(a, b):
    d = abs(sum(x * y for x, y in zip(q_norm(a), q_norm(b))))
    d = max(-1.0, min(1.0, d))
    return math.degrees(2.0 * math.acos(d))


# ------------------------------------------------------------------ gltf
class Gltf:
    def __init__(self, path):
        self.dir = os.path.dirname(os.path.abspath(path))
        self.g = json.load(open(path, encoding="utf-8"))
        self._buffers = []
        for buf in self.g.get("buffers", []):
            uri = buf.get("uri", "")
            if uri.startswith("data:"):
                self._buffers.append(base64.b64decode(uri.split(",", 1)[1]))
            else:
                self._buffers.append(open(os.path.join(self.dir, uri), "rb").read())
        self.nodes = self.g.get("nodes", [])
        self.names = [n.get("name", "node%d" % i) for i, n in enumerate(self.nodes)]
        self.parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []):
                self.parent[c] = i
        self.by_name = {}
        for i, nm in enumerate(self.names):
            self.by_name.setdefault(nm, i)
        self.redundant_translation = set()
        for i, nm in enumerate(self.names):
            if nm + "_$AssimpFbx$_Translation" in self.by_name:
                self.redundant_translation.add(i)
        # Nos auxiliares de rotacao (_PreRotation / _Rotation) guardam a rotacao
        # de bind do FBX. O assimp AINDA exporta um canal de rotacao no bone
        # original ja contendo essa pre-rotacao. Compor os dois gira o membro
        # duas vezes. Marcamos os auxiliares para zerar a rotacao deles quando a
        # animacao esta sendo avaliada (no rest eles continuam valendo).
        self.redundant_rotation = set()
        for i, nm in enumerate(self.names):
            for suffix in ("_$AssimpFbx$_PreRotation", "_$AssimpFbx$_Rotation"):
                if nm.endswith(suffix):
                    base = nm[: -len(suffix)]
                    if base in self.by_name:
                        self.redundant_rotation.add(i)

    def accessor(self, index):
        acc = self.g["accessors"][index]
        view = self.g["bufferViews"][acc["bufferView"]]
        data = self._buffers[view.get("buffer", 0)]
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        fmt, size = COMPONENT[acc["componentType"]]
        n = NCOMP[acc["type"]]
        stride = view.get("byteStride") or (size * n)
        out = []
        for i in range(acc["count"]):
            off = start + i * stride
            vals = struct.unpack_from("<" + fmt * n, data, off)
            out.append(vals[0] if n == 1 else tuple(vals))
        return out

    def static_trs(self, index):
        n = self.nodes[index]
        if "matrix" in n:
            m = n["matrix"]  # column-major
            t = (m[12], m[13], m[14])
            # extrai rotacao assumindo escala uniforme positiva
            cols = [(m[0], m[1], m[2]), (m[4], m[5], m[6]), (m[8], m[9], m[10])]
            sx = math.sqrt(sum(c * c for c in cols[0])) or 1.0
            sy = math.sqrt(sum(c * c for c in cols[1])) or 1.0
            sz = math.sqrt(sum(c * c for c in cols[2])) or 1.0
            r = [[cols[0][0] / sx, cols[1][0] / sy, cols[2][0] / sz],
                 [cols[0][1] / sx, cols[1][1] / sy, cols[2][1] / sz],
                 [cols[0][2] / sx, cols[1][2] / sy, cols[2][2] / sz]]
            return t, mat3_to_quat(r), (sx, sy, sz)
        t = tuple(n.get("translation", (0.0, 0.0, 0.0)))
        r = tuple(n.get("rotation", (0.0, 0.0, 0.0, 1.0)))
        s = tuple(n.get("scale", (1.0, 1.0, 1.0)))
        return t, r, s

    # ---------------- animação
    def animation_tracks(self, anim_index=0):
        """{node_index: {'rotation': [(t, quat)], 'translation': [(t, vec3)]}}"""
        anim = self.g["animations"][anim_index]
        tracks = {}
        for ch in anim["channels"]:
            target = ch["target"]
            node = target.get("node")
            path = target.get("path")
            if node is None or path not in ("rotation", "translation", "scale"):
                continue
            samp = anim["samplers"][ch["sampler"]]
            times = self.accessor(samp["input"])
            values = self.accessor(samp["output"])
            tracks.setdefault(node, {})[path] = list(zip(times, values))
        return tracks

    def duration(self, anim_index=0):
        anim = self.g["animations"][anim_index]
        end = 0.0
        for samp in anim["samplers"]:
            times = self.accessor(samp["input"])
            if times:
                end = max(end, times[-1])
        return end


def mat3_to_quat(r):
    tr = r[0][0] + r[1][1] + r[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        return ((r[2][1] - r[1][2]) / s, (r[0][2] - r[2][0]) / s,
                (r[1][0] - r[0][1]) / s, 0.25 * s)
    if r[0][0] > r[1][1] and r[0][0] > r[2][2]:
        s = math.sqrt(1.0 + r[0][0] - r[1][1] - r[2][2]) * 2
        return (0.25 * s, (r[0][1] + r[1][0]) / s, (r[0][2] + r[2][0]) / s,
                (r[2][1] - r[1][2]) / s)
    if r[1][1] > r[2][2]:
        s = math.sqrt(1.0 + r[1][1] - r[0][0] - r[2][2]) * 2
        return ((r[0][1] + r[1][0]) / s, 0.25 * s, (r[1][2] + r[2][1]) / s,
                (r[0][2] - r[2][0]) / s)
    s = math.sqrt(1.0 + r[2][2] - r[0][0] - r[1][1]) * 2
    return ((r[0][2] + r[2][0]) / s, (r[1][2] + r[2][1]) / s, 0.25 * s,
            (r[1][0] - r[0][1]) / s)


def sample_track(keys, t, is_quat):
    if not keys:
        return None
    if t <= keys[0][0]:
        return keys[0][1]
    if t >= keys[-1][0]:
        return keys[-1][1]
    lo = 0
    hi = len(keys) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if keys[mid][0] <= t:
            lo = mid
        else:
            hi = mid
    t0, v0 = keys[lo]
    t1, v1 = keys[hi]
    u = 0.0 if t1 == t0 else (t - t0) / (t1 - t0)
    if is_quat:
        return q_slerp(v0, v1, u)
    return tuple(a + (b - a) * u for a, b in zip(v0, v1))


class Pose:
    """Transformadas globais (rotacao + posicao) de todos os nós num instante."""

    def __init__(self, gltf, tracks, time=None):
        self.g = gltf
        self.rot = {}
        self.pos = {}
        order = self._topo()
        for i in order:
            t, r, _s = gltf.static_trs(i)
            tr = tracks.get(i, {})
            if time is not None:
                if i in gltf.redundant_rotation:
                    r = (0.0, 0.0, 0.0, 1.0)
                if "rotation" in tr:
                    r = sample_track(tr["rotation"], time, True) or r
                # O assimp decompoe o FBX em nos auxiliares _$AssimpFbx$_ E ainda
                # deixa canais redundantes no bone original. Se o no auxiliar de
                # translacao existe, ele ja carrega o offset: aplicar o canal
                # tambem duplicaria o comprimento do osso.
                if "translation" in tr and i not in gltf.redundant_translation:
                    t = sample_track(tr["translation"], time, False) or t
            p = gltf.parent.get(i)
            if p is None:
                self.rot[i] = q_norm(r)
                self.pos[i] = tuple(t)
            else:
                pr = self.rot[p]
                self.rot[i] = q_norm(q_mul(pr, r))
                rt = q_rotate(pr, t)
                self.pos[i] = tuple(a + b for a, b in zip(self.pos[p], rt))

    def _topo(self):
        order = []
        seen = set()

        def visit(i):
            if i in seen:
                return
            p = self.g.parent.get(i)
            if p is not None:
                visit(p)
            seen.add(i)
            order.append(i)

        for i in range(len(self.g.nodes)):
            visit(i)
        return order
