"""Программный рендер MDL v10 в PNG (z-буфер, текстуры, ламбертовское освещение).
Только для визуальной проверки геометрии/UV/анимации без игрового клиента.

  python3 render.py model.mdl out.png [--seq N] [--frame F] [--view] [--yaw DEG] [--pitch DEG]
"""
import argparse
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import goldsrc_mdl as g  # noqa: E402


def render(m, seq=0, frame=0, size=512, view=False, yaw=35.0, pitch=20.0):
    mats = g.pose(m, seq, frame)
    tris = []  # (p0,p1,p2, uv0,uv1,uv2, tex)
    for bp in m["bodyparts"]:
        md = bp["models"][0]
        pts = [g.transform(mats[b], v) for v, b in zip(md["verts"], md["vert_bone"])]
        for mesh in md["meshes"]:
            tex = m["skins"][mesh["skinref"]] if m["skins"] else mesh["skinref"]
            for t in mesh["tris"]:
                tris.append(([pts[v] for v, _, _ in t], [(s, tt) for _, s, tt in t], tex))
    if not tris:
        raise SystemExit("нет треугольников")

    P = np.array([p for t in tris for p in t[0]], dtype=float)
    if view:
        # камера игрока: смотрит вдоль +X из начала координат, Y — влево, Z — вверх
        fov = math.radians(90.0)
        f = (size / 2) / math.tan(fov / 2)

        def project(p):
            x, y, z = p
            x = max(x, 0.5)
            return np.array([size / 2 - y / x * f, size / 2 - z / x * f, x])
    else:
        center = (P.min(0) + P.max(0)) / 2
        radius = np.linalg.norm(P - center, axis=1).max() or 1.0
        cy, sy = math.cos(math.radians(yaw)), math.sin(math.radians(yaw))
        cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))

        def project(p):
            v = np.array(p) - center
            # камера на +X, смотрим на центр; поворот модели по yaw, затем pitch
            x, y, z = v[0] * cy - v[1] * sy, v[0] * sy + v[1] * cy, v[2]
            x, z = x * cp + z * sp, -x * sp + z * cp
            s = size * 0.42 / radius
            return np.array([size / 2 - y * s, size / 2 - z * s, -x])

    img = np.full((size, size, 3), 40, dtype=np.float32)
    zbuf = np.full((size, size), np.inf, dtype=np.float32)
    light = np.array([0.4, 0.3, 0.85])
    light /= np.linalg.norm(light)
    texcache = {}
    for pts3, uvs, tex in tris:
        if tex not in texcache:
            w, h, pix, pal = g.texture_rgb(m, tex)
            palette = np.frombuffer(pal, dtype=np.uint8).reshape(256, 3)
            texcache[tex] = palette[np.frombuffer(pix, dtype=np.uint8)].reshape(h, w, 3).astype(np.float32)
        timg = texcache[tex]
        th, tw = timg.shape[:2]
        a, b, c = (np.array(p) for p in pts3)
        n = np.cross(b - a, c - a)
        nl = np.linalg.norm(n)
        shade = 0.35 + 0.65 * abs(float(np.dot(n / nl, light))) if nl > 0 else 0.6
        s = [project(p) for p in pts3]
        xs, ys = [q[0] for q in s], [q[1] for q in s]
        x0, x1 = max(int(min(xs)), 0), min(int(max(xs)) + 1, size - 1)
        y0, y1 = max(int(min(ys)), 0), min(int(max(ys)) + 1, size - 1)
        if x0 > x1 or y0 > y1:
            continue
        (ax, ay, az), (bx, by, bz), (cx, cy_, cz) = s
        den = (by - cy_) * (ax - cx) + (cx - bx) * (ay - cy_)
        if abs(den) < 1e-9:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        w0 = ((by - cy_) * (gx - cx) + (cx - bx) * (gy - cy_)) / den
        w1 = ((cy_ - ay) * (gx - cx) + (ax - cx) * (gy - cy_)) / den
        w2 = 1 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        if not inside.any():
            continue
        z = w0 * az + w1 * bz + w2 * cz
        u = w0 * uvs[0][0] + w1 * uvs[1][0] + w2 * uvs[2][0]
        v = w0 * uvs[0][1] + w1 * uvs[1][1] + w2 * uvs[2][1]
        sub = zbuf[y0:y1 + 1, x0:x1 + 1]
        mask = inside & (z < sub)
        ui = np.clip(u.astype(int), 0, tw - 1)
        vi = np.clip(v.astype(int), 0, th - 1)
        col = timg[vi, ui] * shade
        img[y0:y1 + 1, x0:x1 + 1][mask] = col[mask]
        sub[mask] = z[mask]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mdl")
    ap.add_argument("png")
    ap.add_argument("--seq", type=int, default=0)
    ap.add_argument("--frame", type=int, default=0)
    ap.add_argument("--view", action="store_true", help="камера view-модели (от первого лица)")
    ap.add_argument("--yaw", type=float, default=35.0)
    ap.add_argument("--pitch", type=float, default=20.0)
    ap.add_argument("--size", type=int, default=512)
    a = ap.parse_args()
    m = g.read_mdl(Path(a.mdl).read_bytes())
    render(m, a.seq, a.frame, a.size, a.view, a.yaw, a.pitch).save(a.png)


if __name__ == "__main__":
    main()
