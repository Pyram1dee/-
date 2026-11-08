"""Проверка присланной модели GoldSrc перед установкой на сервер.

  python3 tools/mdl/check_model.py model.mdl [--knife] [--preview out.png]

--knife   — проверить, что последовательности подходят для замены ножа CS 1.6.
Проверяет: формат MDL v10 и все смещения, декодирование всех кадров анимации,
порядок обхода треугольников, размеры текстур (<= 512).
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import goldsrc_mdl as g  # noqa: E402
import render as r  # noqa: E402
import validate as v  # noqa: E402

KNIFE_SEQ = v.KNIFE_SEQ


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mdl")
    ap.add_argument("--knife", action="store_true")
    ap.add_argument("--preview")
    a = ap.parse_args()
    data = Path(a.mdl).read_bytes()
    problems = []
    try:
        m = g.read_mdl(data)
    except g.MdlError as e:
        print("ОШИБКА формата:", e)
        sys.exit(1)
    print(f"имя в заголовке: {m['name']}, {len(data)} байт, костей {len(m['bones'])}")
    for t in m["textures"]:
        print(f"  текстура {t['name']} {t['width']}x{t['height']}")
        if t["width"] > 512 or t["height"] > 512:
            problems.append(f"текстура {t['name']} больше 512")
    for si, s in enumerate(m["sequences"]):
        for f in range(s["numframes"]):
            g.pose(m, si, f)
    print(f"  последовательностей {len(m['sequences'])}: {[s['label'] for s in m['sequences']]} — все кадры декодируются")
    if not m["bodyparts"]:
        print("  файл текстур (…T.mdl): геометрии нет — проверены только текстуры")
    else:
        w = v.winding(data)
        print(f"  обход треугольников по часовой снаружи: {w:.0%}")
        if w < 0.5:
            problems.append("обход треугольников обратный (модель будет «вывернутой»)")
        if not m["textures"]:
            tfile = Path(a.mdl[:-4] + "T.mdl")
            if not tfile.exists():
                problems.append(f"текстуры во внешнем файле, но нет {tfile.name}")
            else:
                tm = g.read_mdl(tfile.read_bytes())
                print(f"  текстуры из {tfile.name}: {len(tm['textures'])}")
                if m["skinref"] and len(tm["textures"]) < m["skinref"]:
                    problems.append(f"в {tfile.name} {len(tm['textures'])} текстур, модель ссылается на {m['skinref']}")
    if a.knife:
        n = len(m["sequences"])
        if n < len(KNIFE_SEQ):
            problems.append(f"для ножа нужно >= {len(KNIFE_SEQ)} последовательностей, есть {n}")
        else:
            labels = [s["label"].lower() for s in m["sequences"][:len(KNIFE_SEQ)]]
            if labels != KNIFE_SEQ:
                print(f"  ВНИМАНИЕ: имена {labels} отличаются от {KNIFE_SEQ}; игра выбирает анимации по индексу")
            else:
                print("  порядок последовательностей совпадает с ножом CS 1.6")
    if a.preview and m["textures"] and m["bodyparts"]:
        r.render(m, 0, 0, 320, view=a.knife).save(a.preview)
        print("  превью:", a.preview)
    print("ИТОГ:", "OK" if not problems else "; ".join(problems))
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
