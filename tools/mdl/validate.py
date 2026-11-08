"""Проверка собственных моделей CSO (без игрового клиента).

  python3 tools/mdl/validate.py

1. Модели генерируются заново и совпадают байт-в-байт с assets/models/cso (воспроизводимость).
2. Каждый файл читается парсером, проверенным на эталонных моделях ZP: сигнатура, версия, длина,
   все смещения внутри файла, индексы вершин/нормалей/костей/текстур.
3. Порядок обхода треугольников совпадает с соглашением эталонных моделей (по часовой снаружи).
4. Анимация: позы, декодированные из файла алгоритмом движка, совпадают с заданными (< 0.05 юнита).
5. Габариты: гроб и ловушка помещаются в bbox из плагинов; v_hammer — 8 последовательностей ножа CS.
"""
import struct
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_models as bm  # noqa: E402
import goldsrc_mdl as g  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets" / "models" / "cso"
KNIFE_SEQ = ["idle", "slash1", "slash2", "draw", "stab", "stab_miss", "midslash1", "midslash2"]
# bbox сущностей из плагинов (src/cso_zclass_undertaker.sma, src/cso_zclass_heavy.sma)
LIMITS = {"coffin.mdl": ((-16, -16, 0), (16, 16, 64)), "zombitrap.mdl": ((-16, -16, 0), (16, 16, 12))}

errors = []


def fail(msg):
    errors.append(msg)
    print("  ОШИБКА:", msg)


def winding(data):
    """Доля первых треугольников полос, у которых геометрическая нормаль против нормали вершины."""
    h = struct.unpack_from(g.HDR_FMT, data, 0)
    bp = struct.unpack_from(g.BODYPART_FMT, data, h[37])
    md = struct.unpack_from(g.MODEL_FMT, data, bp[3])
    nummesh, meshindex, nv, _, vindex, nn, _, nindex = md[3:11]
    V = [np.array(struct.unpack_from("<3f", data, vindex + 12 * i)) for i in range(nv)]
    N = [np.array(struct.unpack_from("<3f", data, nindex + 12 * i)) for i in range(nn)]
    neg = tot = 0
    for k in range(nummesh):
        off = struct.unpack_from(g.MESH_FMT, data, meshindex + g.MESH_SIZE * k)[1]
        while True:
            (c,) = struct.unpack_from("<h", data, off)
            off += 2
            if c == 0:
                break
            pts = [struct.unpack_from("<4h", data, off + 8 * i) for i in range(abs(c))]
            off += 8 * abs(c)
            a, b, cc = (V[p[0]] for p in pts[:3])
            s = np.dot(np.cross(b - a, cc - a), N[pts[0][1]])
            tot += 1
            neg += s < 0
    return neg / max(tot, 1)


def main():
    builders = [bm.build_coffin, bm.build_trap, bm.build_v_hammer, bm.build_p_hammer]
    for fn in builders:
        model = fn()
        data = g.write_mdl(model)
        path = ASSETS / model.name
        print(f"{model.name}:")
        if not path.exists():
            fail(f"нет файла {path}")
            continue
        if path.read_bytes() != data:
            fail("файл в assets не совпадает с генератором — запустите build_models.py")
        m = g.read_mdl(path.read_bytes())

        w = winding(data)
        print(f"  треугольников по часовой снаружи: {w:.0%}")
        if w < 0.99:
            fail("порядок обхода треугольников не соответствует соглашению GoldSrc")

        # round-trip анимации
        worst = 0.0
        for si, seq in enumerate(model.sequences):
            for f in range(seq.numframes):
                mats = g.pose(m, si, f)
                want = bm.g._pose_points(model, seq, f)
                md = m["bodyparts"][0]["models"][0]
                got = [g.transform(mats[b], v) for v, b in zip(md["verts"], md["vert_bone"])]
                worst = max(worst, float(np.abs(np.array(got) - np.array(want)).max()))
        print(f"  макс. ошибка декодирования анимации: {worst:.4f} юнита")
        if worst > 0.05:
            fail("анимация декодируется с ошибкой")

        if model.name in LIMITS:
            lo, hi = LIMITS[model.name]
            P = np.array(model.verts)
            if (P.min(0) < np.array(lo) - 0.01).any() or (P.max(0) > np.array(hi) + 0.01).any():
                fail(f"геометрия {P.min(0).round(1)}..{P.max(0).round(1)} не помещается в bbox {lo}..{hi}")
            else:
                print(f"  габариты {P.min(0).round(1)}..{P.max(0).round(1)} внутри bbox плагина")
        if model.name == "v_hammer.mdl":
            labels = [s["label"] for s in m["sequences"]]
            if labels != KNIFE_SEQ:
                fail(f"последовательности {labels} != {KNIFE_SEQ}")
            else:
                print("  последовательности в порядке ножа CS 1.6")
        if model.name == "p_hammer.mdl" and m["bones"][0]["name"] != "Bip01 R Hand":
            fail("корневая кость p_-модели должна называться 'Bip01 R Hand'")
        print(f"  {len(data)} байт, текстуры: {[(t['name'], t['width'], t['height']) for t in m['textures']]}")

    print("ИТОГ:", "ошибок нет" if not errors else f"{len(errors)} ошибок")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
