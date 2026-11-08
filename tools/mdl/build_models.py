"""Генератор собственных моделей CSO Custom Edition (геометрия и текстуры созданы здесь, без чужих ресурсов).

  python3 tools/mdl/build_models.py [выходная_папка]   (по умолчанию assets/models/cso)

Модели:
  coffin.mdl     — гроб Гробовщика (стоячий, 30 x 14 x 64)
  zombitrap.mdl  — ловушка Толстяка (капкан, d=30, h<=10)
  v_hammer.mdl   — VIP-молот, вид от первого лица; последовательности в порядке ножа CS 1.6
  p_hammer.mdl   — VIP-молот в руке модели игрока (кость "Bip01 R Hand")
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import goldsrc_mdl as g  # noqa: E402

RNG = np.random.default_rng(1606)


# ---------------------------------------------------------------------------
# Текстуры (процедурные)
# ---------------------------------------------------------------------------

def noise(h, w, scale, octaves=3):
    out = np.zeros((h, w))
    amp = 1.0
    for o in range(octaves):
        sh, sw = max(2, h // (scale >> o or 1)), max(2, w // (scale >> o or 1))
        small = RNG.random((sh, sw))
        img = Image.fromarray((small * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        out += np.asarray(img, dtype=float) / 255.0 * amp
        amp *= 0.5
    return out / out.max()


def tex_wood(h, w, base=(92, 52, 28), dark=(52, 28, 14)):
    y = np.linspace(0, 1, h)[:, None]
    x = np.linspace(0, 1, w)[None, :]
    n = noise(h, w, 16)
    grain = 0.5 + 0.5 * np.sin((x * 40 + n * 6 + y * 2) * math.pi)
    t = np.clip(grain * 0.7 + n * 0.3, 0, 1)[..., None]
    return np.array(dark) * (1 - t) + np.array(base) * t


def tex_metal(h, w, base=(120, 122, 128), rust=(110, 58, 30), rust_amount=0.35):
    n = noise(h, w, 8, 4)
    streak = noise(h, w, 32, 2)
    v = (0.75 + 0.25 * n)[..., None]
    col = np.array(base) * v
    r = np.clip((streak - (1 - rust_amount)) * 3, 0, 1)[..., None]
    return col * (1 - r) + np.array(rust) * r


def tex_flat(h, w, color, var=10):
    n = noise(h, w, 8)
    return np.array(color, dtype=float) + (n[..., None] - 0.5) * var * 2


def tex_cloth(h, w, color=(48, 56, 40)):
    yy, xx = np.mgrid[0:h, 0:w]
    weave = ((xx + yy) % 4 < 2) * 6.0
    return np.array(color, dtype=float) + weave[..., None] + (noise(h, w, 8)[..., None] - 0.5) * 16


class Atlas:
    """Текстура-атлас: прямоугольные области под разные материалы."""

    def __init__(self, name, width, height):
        self.name = name
        self.w, self.h = width, height
        self.rgb = np.zeros((height, width, 3))
        self.regions = {}

    def add(self, key, x, y, w, h, pixels):
        self.rgb[y:y + h, x:x + w] = pixels
        self.regions[key] = (x, y, w, h)

    def to_texture(self):
        img = Image.fromarray(np.clip(self.rgb, 0, 255).astype(np.uint8), "RGB")
        q = img.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        pal = bytes(q.getpalette()[:768]).ljust(768, b"\0")
        return g.Texture(self.name, self.w, self.h, q.tobytes(), pal)


# ---------------------------------------------------------------------------
# Геометрия
# ---------------------------------------------------------------------------

class Builder:
    def __init__(self):
        self.verts, self.vbone, self.norms, self.nbone = [], [], [], []
        self.meshes = {}  # skinref -> Mesh

    def _v(self, p, bone):
        self.verts.append(tuple(float(c) for c in p))
        self.vbone.append(bone)
        return len(self.verts) - 1

    def _n(self, n, bone):
        n = np.asarray(n, dtype=float)
        ln = np.linalg.norm(n)
        n = n / ln if ln > 0 else np.array([0.0, 0.0, 1.0])
        self.norms.append(tuple(float(c) for c in n))
        self.nbone.append(bone)
        return len(self.norms) - 1

    def quad_or_poly(self, pts, uvs, bone=0, skin=0):
        """Плоский выпуклый многоугольник (вершины против часовой стрелки при взгляде снаружи)."""
        pts = [np.asarray(p, dtype=float) for p in pts]
        n = np.zeros(3)
        for i in range(len(pts)):  # нормаль Ньюэлла
            a, b = pts[i], pts[(i + 1) % len(pts)]
            n += np.array([(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])])
        ni = self._n(n, bone)
        vi = [self._v(p, bone) for p in pts]
        mesh = self.meshes.setdefault(skin, g.Mesh(skin))
        for i in range(1, len(pts) - 1):
            # GoldSrc рисует треугольники с обратным порядком обхода (cull front по часовой)
            idx = (0, i + 1, i)
            mesh.tris.append(g.Tri(tuple(vi[k] for k in idx), (ni, ni, ni), tuple(uvs[k] for k in idx)))

    def prism(self, profile, axis_from, axis_to, region, bone=0, skin=0, caps=True):
        """Призма: profile — 2D-точки (против часовой) в плоскости, перпендикулярной оси from->to."""
        a0, a1 = np.asarray(axis_from, float), np.asarray(axis_to, float)
        ax = a1 - a0
        L = np.linalg.norm(ax)
        ax /= L
        up = np.array([0, 0, 1.0]) if abs(ax[2]) < 0.9 else np.array([1.0, 0, 0])
        u = np.cross(up, ax)
        u /= np.linalg.norm(u)
        v = np.cross(ax, u)
        rx, ry, rw, rh = region
        ring0 = [a0 + p[0] * u + p[1] * v for p in profile]
        ring1 = [a1 + p[0] * u + p[1] * v for p in profile]
        n = len(profile)
        perim = [0.0]
        for i in range(n):
            perim.append(perim[-1] + np.linalg.norm(np.subtract(profile[(i + 1) % n], profile[i])))
        for i in range(n):
            j = (i + 1) % n
            s0 = rx + rw * perim[i] / perim[-1]
            s1 = rx + rw * perim[i + 1] / perim[-1]
            self.quad_or_poly([ring0[i], ring0[j], ring1[j], ring1[i]],
                              [(s0, ry + rh - 1), (s1, ry + rh - 1), (s1, ry), (s0, ry)], bone, skin)
        if caps:
            pr = np.array(profile)
            mn, mx = pr.min(0), pr.max(0)
            span = np.where(mx - mn > 0, mx - mn, 1)

            def cap_uv(p):
                t = (np.array(p) - mn) / span
                return (rx + t[0] * (rw - 1), ry + t[1] * (rh - 1))
            self.quad_or_poly(list(reversed(ring0)), [cap_uv(p) for p in reversed(profile)], bone, skin)
            self.quad_or_poly(ring1, [cap_uv(p) for p in profile], bone, skin)

    def box(self, mins, maxs, region, bone=0, skin=0):
        (x0, y0, z0), (x1, y1, z1) = mins, maxs
        rx, ry, rw, rh = region
        uv = [(rx, ry + rh - 1), (rx + rw - 1, ry + rh - 1), (rx + rw - 1, ry), (rx, ry)]
        faces = [
            [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)],  # +x
            [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)],  # -x
            [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)],  # +y
            [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],  # -y
            [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],  # +z
            [(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)],  # -z
        ]
        for f in faces:
            self.quad_or_poly(f, uv, bone, skin)

    def finish(self, name, bones, textures, sequences, hitboxes, flags=0):
        meshes = [self.meshes[k] for k in sorted(self.meshes)]
        return g.Model(name, bones, textures, self.verts, self.vbone, self.norms, self.nbone,
                       meshes, sequences, hitboxes, flags=flags)


def circle(r, n, start=0.0):
    return [(r * math.cos(start + 2 * math.pi * i / n), r * math.sin(start + 2 * math.pi * i / n)) for i in range(n)]


def rotate_pts(pts, axis, ang):
    c, s = math.cos(ang), math.sin(ang)
    out = []
    for x, y, z in pts:
        if axis == "z":
            out.append((x * c - y * s, x * s + y * c, z))
        elif axis == "y":
            out.append((x * c + z * s, y, -x * s + z * c))
        else:
            out.append((x, y * c - z * s, y * s + z * c))
    return out


# ---------------------------------------------------------------------------
# Гроб
# ---------------------------------------------------------------------------

def build_coffin():
    at = Atlas("cso_coffin.bmp", 128, 128)
    at.add("wood", 0, 0, 128, 96, tex_wood(96, 128))
    at.add("lid", 0, 96, 96, 32, tex_wood(32, 96, (70, 38, 20), (40, 20, 10)))
    at.add("cross", 96, 96, 32, 32, tex_metal(32, 32, (170, 150, 90), (120, 90, 40), 0.15))

    b = Builder()
    # профиль гроба в плоскости (ширина Y, высота Z), выдавливание по X (глубина)
    prof = [(-9, 0), (9, 0), (15, 46), (11, 64), (-11, 64), (-15, 46)]
    # prism строит базис u = up x axis; для оси -X->+X: u = (0,1,0)? проверяем явно ниже
    b.prism([(y, z) for y, z in prof], (-7, 0, 0), (7, 0, 0), at.regions["wood"])
    # крышка-накладка спереди (+X) и крест
    lid = [(-7.5, 3), (7.5, 3), (12.5, 45), (9.5, 61), (-9.5, 61), (-12.5, 45)]
    b.prism(lid, (7, 0, 0), (8, 0, 0), at.regions["lid"])
    b.box((8, -1.2, 22), (9, 1.2, 54), at.regions["cross"])
    b.box((8, -7, 41), (9, 7, 44), at.regions["cross"])
    bones = [g.Bone("coffin", -1)]
    seq = [g.Sequence("idle", 10.0, 1, loop=True)]
    return b.finish("coffin.mdl", bones, [at.to_texture()], seq, [(0, 0, (-8, -16, 0), (9, 16, 64))])


# ---------------------------------------------------------------------------
# Ловушка (капкан)
# ---------------------------------------------------------------------------

def build_trap():
    at = Atlas("cso_zombitrap.bmp", 128, 64)
    at.add("metal", 0, 0, 64, 64, tex_metal(64, 64))
    at.add("dark", 64, 0, 32, 64, tex_metal(64, 32, (70, 70, 74), (90, 40, 20), 0.5))
    at.add("blood", 96, 0, 32, 64, tex_flat(64, 32, (120, 20, 18), 12))

    b = Builder()
    # основание-диск и центральная пластина
    b.prism(circle(13, 16), (0, 0, 0), (0, 0, 1.5), at.regions["dark"])
    b.prism(circle(5, 10), (0, 0, 1.5), (0, 0, 2.5), at.regions["metal"])
    # пружины-дуги по бокам
    b.box((-3, -15, 0), (3, -13, 3), at.regions["dark"])
    b.box((-3, 13, 0), (3, 15, 3), at.regions["dark"])
    # раскрытые челюсти: кольцо из сегментов на высоте 1.5..3.5
    seg = 18
    for i in range(seg):
        a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
        r0, r1 = 12.0, 14.5
        p = lambda r, a, z: (r * math.cos(a), r * math.sin(a), z)  # noqa: E731
        z0, z1 = 1.5, 3.5
        # верх, внешняя и внутренняя стенки сегмента
        b.quad_or_poly([p(r0, a0, z1), p(r1, a0, z1), p(r1, a1, z1), p(r0, a1, z1)],
                       [(0, 0), (8, 0), (8, 8), (0, 8)], 0, 0)
        b.quad_or_poly([p(r1, a0, z0), p(r1, a1, z0), p(r1, a1, z1), p(r1, a0, z1)],
                       [(0, 8), (8, 8), (8, 12), (0, 12)], 0, 0)
        b.quad_or_poly([p(r0, a1, z0), p(r0, a0, z0), p(r0, a0, z1), p(r0, a1, z1)],
                       [(0, 8), (8, 8), (8, 12), (0, 12)], 0, 0)
        # зуб: треугольная пластина, смотрит вверх-внутрь
        am = (a0 + a1) / 2
        tip = (10.5 * math.cos(am), 10.5 * math.sin(am), 9.0)
        ba, bb = p(13.25, a0 + 0.04, z1), p(13.25, a1 - 0.04, z1)
        rx, ry, rw, rh = at.regions["blood"]
        b.quad_or_poly([ba, bb, tip], [(rx, ry + rh - 1), (rx + rw - 1, ry + rh - 1), (rx + rw // 2, ry)])
        b.quad_or_poly([tip, bb, ba], [(rx + rw // 2, ry), (rx + rw - 1, ry + rh - 1), (rx, ry + rh - 1)])
    bones = [g.Bone("trap", -1)]
    seq = [g.Sequence("idle", 10.0, 1, loop=True)]
    return b.finish("zombitrap.mdl", bones, [at.to_texture()], seq, [(0, 0, (-15, -15, 0), (15, 15, 9))])


# ---------------------------------------------------------------------------
# Молот
# ---------------------------------------------------------------------------

def hammer_atlas():
    at = Atlas("cso_hammer.bmp", 128, 128)
    at.add("handle", 0, 0, 64, 64, tex_wood(64, 64, (110, 70, 36), (60, 34, 16)))
    at.add("head", 64, 0, 64, 64, tex_metal(64, 64, (96, 98, 108), (70, 40, 24), 0.2))
    at.add("grip", 0, 64, 32, 64, tex_cloth(64, 32, (30, 30, 32)))
    at.add("skin", 32, 64, 32, 64, tex_flat(64, 32, (196, 150, 120), 8))
    at.add("sleeve", 64, 64, 64, 64, tex_cloth(64, 64))
    return at


def add_hammer(b, at, bone, origin=(0, 0, 0), up=(0, 0, 1), fwd=(1, 0, 0), scale=1.0):
    """Молот: рукоять вдоль up от origin, боёк смотрит вдоль fwd."""
    o, U, F = np.array(origin, float), np.array(up, float), np.array(fwd, float)
    U /= np.linalg.norm(U)
    F = F - U * np.dot(F, U)
    F /= np.linalg.norm(F)
    S = np.cross(U, F)
    P = lambda a, c, d: o + (F * a + S * c + U * d) * scale  # noqa: E731
    # рукоять (8-угольник), обмотка снизу
    b.prism(circle(0.9, 8), P(0, 0, -4), P(0, 0, 3), at.regions["grip"], bone, 0)
    b.prism(circle(0.8, 8), P(0, 0, 3), P(0, 0, 20), at.regions["handle"], bone, 0)
    # боёк: блок + ударная часть + клин сзади
    def blk(a0, a1, c0, c1, d0, d1, reg):
        corners = lambda: None  # noqa: E731
        pts = {}
        for ia, a in enumerate((a0, a1)):
            for ic, c in enumerate((c0, c1)):
                for idd, d in enumerate((d0, d1)):
                    pts[(ia, ic, idd)] = P(a, c, d)
        rx, ry, rw, rh = at.regions[reg]
        uv = [(rx, ry + rh - 1), (rx + rw - 1, ry + rh - 1), (rx + rw - 1, ry), (rx, ry)]
        F_ = [
            [(1, 0, 0), (1, 1, 0), (1, 1, 1), (1, 0, 1)],
            [(0, 1, 0), (0, 0, 0), (0, 0, 1), (0, 1, 1)],
            [(1, 1, 0), (0, 1, 0), (0, 1, 1), (1, 1, 1)],
            [(0, 0, 0), (1, 0, 0), (1, 0, 1), (0, 0, 1)],
            [(0, 0, 1), (1, 0, 1), (1, 1, 1), (0, 1, 1)],
            [(0, 1, 0), (1, 1, 0), (1, 0, 0), (0, 0, 0)],
        ]
        # базис F,S,U правый, поэтому порядок обхода как у box()
        for f in F_:
            b.quad_or_poly([pts[k] for k in f], uv, bone, 0)
        del corners
    blk(-3.5, 4.0, -1.8, 1.8, 18.0, 23.0, "head")
    blk(4.0, 6.5, -2.3, 2.3, 17.5, 23.5, "head")     # ударная часть
    blk(-6.5, -3.5, -1.0, 1.0, 19.0, 22.0, "head")   # клин


def knife_sequences(arm_rest, hand_rest_rot):
    """Последовательности в порядке ножа CS 1.6:
    0 idle, 1 slash1, 2 slash2, 3 draw, 4 stab, 5 stab_miss, 6 midslash1, 7 midslash2.
    Кость 0 "arm" — только небольшие смещения; кость 1 "hand" — вращение кисти с молотом."""

    def smooth(t):
        return t * t * (3 - 2 * t)

    def lerp_keys(keys, t):
        for (t0, a0, r0), (t1, a1, r1) in zip(keys, keys[1:]):
            if t0 <= t <= t1:
                k = smooth((t - t0) / (t1 - t0)) if t1 > t0 else 1.0
                return ([x + (y - x) * k for x, y in zip(a0, a1)], [x + (y - x) * k for x, y in zip(r0, r1)])
        return list(keys[-1][1]), list(keys[-1][2])

    def make(label, fps, frames, keys, loop=False):
        def arm_fn(f):
            dp, _ = lerp_keys(keys, f / max(1, frames - 1))
            return tuple(a + d for a, d in zip(arm_rest, dp)), (0.0, 0.0, 0.0)

        def hand_fn(f):
            _, dr = lerp_keys(keys, f / max(1, frames - 1))
            return (0.0, 0.0, 0.0), tuple(a + d for a, d in zip(hand_rest_rot, dr))
        return g.Sequence(label, fps, frames, loop=loop, anim={0: arm_fn, 1: hand_fn})

    Z = (0, 0, 0)
    idle = make("idle", 15.0, 31, [(0, Z, Z), (0.5, (0, 0, 0.5), (0, 0.03, 0)), (1, Z, Z)], loop=True)

    def swing(side):
        return [(0.0, Z, Z),
                (0.3, (-1, 0, 1), (0, -0.3, 0.1 * side)),
                (0.55, (2, 1.5 * side, -1), (0, 0.95, -0.35 * side)),
                (1.0, Z, Z)]
    slash1 = make("slash1", 30.0, 16, swing(1))
    slash2 = make("slash2", 30.0, 16, swing(-1))
    draw = make("draw", 30.0, 20, [(0, (0, 0, -16), (0, 0.8, 0)), (0.7, (0, 0, 0.5), (0, -0.08, 0)), (1, Z, Z)])
    stab_keys = [(0.0, Z, Z), (0.35, (-1.5, 0, 2), (0, -0.45, 0)), (0.6, (3, 0, -2), (0, 1.2, 0)), (1.0, Z, Z)]
    stab = make("stab", 30.0, 30, stab_keys)
    stab_miss = make("stab_miss", 30.0, 30, stab_keys)
    mid1 = make("midslash1", 30.0, 16, swing(1))
    mid2 = make("midslash2", 30.0, 16, swing(-1))
    return [idle, slash1, slash2, draw, stab, stab_miss, mid1, mid2]


def build_v_hammer():
    at = hammer_atlas()
    b = Builder()
    # пространство вида: x вперёд, y влево, z вверх. Кость 0 — запястье на предплечье.
    arm_rest = (15.0, -12.5, -16.5)
    hand_rot = (0.0, 0.2, 0.3)
    # предплечье (кость 0) уходит назад-вниз за край экрана
    b.prism(circle(2.4, 8), (0, 0, -1), (-24, 0, -14), at.regions["sleeve"], bone=0)
    # кулак и молот (кость 1)
    b.box((-2.2, -1.6, -1.5), (2.2, 1.6, 2.5), at.regions["skin"], bone=1)
    add_hammer(b, at, 1, origin=(0, 0, -2.5), up=(0.15, 0, 1), fwd=(1, 0, 0))
    bones = [g.Bone("arm", -1, arm_rest, (0.0, 0.0, 0.0)), g.Bone("hand", 0, (0.0, 0.0, 0.0), hand_rot)]
    seqs = knife_sequences(arm_rest, hand_rot)
    return b.finish("v_hammer.mdl", bones, [at.to_texture()], seqs, [(1, 0, (-6, -3, -3), (7, 3, 24))])


# Ориентация молота в локальной системе кости "Bip01 R Hand" модели игрока
P_GRIP_ORIGIN = (3.6, 2.2, -0.6)
P_GRIP_UP = (0.75, 0.0, 0.65)
P_GRIP_FWD = (0.65, 0.0, -0.75)


def build_p_hammer():
    at = hammer_atlas()
    b = Builder()
    add_hammer(b, at, 0, origin=P_GRIP_ORIGIN, up=P_GRIP_UP, fwd=P_GRIP_FWD, scale=0.9)
    # Имя кости совпадает с костью игрока: движок копирует её трансформ (StudioMergeBones)
    bones = [g.Bone("Bip01 R Hand", -1)]
    seq = [g.Sequence("idle", 10.0, 1, loop=True)]
    return b.finish("p_hammer.mdl", bones, [at.to_texture()], seq, [])


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2] / "assets" / "models" / "cso"
    out.mkdir(parents=True, exist_ok=True)
    for fn in (build_coffin, build_trap, build_v_hammer, build_p_hammer):
        model = fn()
        data = g.write_mdl(model)
        g.read_mdl(data)  # самопроверка
        (out / model.name).write_bytes(data)
        print(f"{model.name}: {len(data)} байт, вершин {len(model.verts)}, "
              f"треугольников {sum(len(m.tris) for m in model.meshes)}, последовательностей {len(model.sequences)}")


if __name__ == "__main__":
    main()
