"""Превью p_-модели оружия в руке модели игрока с эмуляцией StudioMergeBones:
кости оружия с тем же именем, что у игрока, берут мировой трансформ кости игрока.

  python3 preview_pmodel.py player.mdl p_weapon.mdl out.png [--seq N] [--yaw DEG] [--pitch DEG] [--zoom-bone NAME]
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import goldsrc_mdl as g  # noqa: E402
import render as r  # noqa: E402


def merged_model(player, weapon, seq):
    pmats = g.pose(player, seq, 0)
    pnames = {b["name"]: i for i, b in enumerate(player["bones"])}
    wmats = g.pose(weapon, 0, 0)
    out = []
    for i, b in enumerate(weapon["bones"]):
        if b["name"] in pnames:
            out.append(pmats[pnames[b["name"]]])
        else:
            out.append(wmats[i] if b["parent"] < 0 else g.concat(out[b["parent"]], wmats[i]))
    return pmats, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("player")
    ap.add_argument("weapon")
    ap.add_argument("png")
    ap.add_argument("--seq", type=int, default=75)
    ap.add_argument("--yaw", type=float, default=200.0)
    ap.add_argument("--pitch", type=float, default=10.0)
    ap.add_argument("--size", type=int, default=400)
    a = ap.parse_args()
    player = g.read_mdl(Path(a.player).read_bytes())
    weapon = g.read_mdl(Path(a.weapon).read_bytes())
    pmats, wmats = merged_model(player, weapon, a.seq)

    # Подменяем pose() так, чтобы render() нарисовал обе модели одним проходом
    combo = dict(player)
    combo["bodyparts"] = list(player["bodyparts"]) + list(weapon["bodyparts"])
    nb = len(player["bones"])
    combo["_mats"] = pmats + wmats
    for bp in weapon["bodyparts"]:
        for md in bp["models"]:
            md["vert_bone"] = [b + nb for b in md["vert_bone"]]
            for mesh in md["meshes"]:
                mesh["_tex_owner"] = weapon
    orig_pose, orig_tex = g.pose, g.texture_rgb
    g.pose = lambda m, s, f: combo["_mats"]  # noqa: E731
    wtex_base = len(player["textures"])
    combo["skins"] = list(player["skins"]) + [s + wtex_base for s in weapon["skins"]]
    for bp in weapon["bodyparts"]:
        for md in bp["models"]:
            for mesh in md["meshes"]:
                mesh["skinref"] += len(player["skins"])

    def tex(m, idx):
        if idx >= wtex_base:
            return orig_tex(weapon, idx - wtex_base)
        return orig_tex(player, idx)
    g.texture_rgb = tex
    try:
        r.render(combo, a.seq, 0, a.size, False, a.yaw, a.pitch).save(a.png)
    finally:
        g.pose, g.texture_rgb = orig_pose, orig_tex


if __name__ == "__main__":
    main()
