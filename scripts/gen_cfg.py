"""Генерирует config/cso_custom.cfg из register_cvar в source/src и патчах tools/thirdparty.
Значения по умолчанию берутся из кода (все — предложение, если не утверждены в ТЗ).

  python3 scripts/gen_cfg.py
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "source" if (ROOT / "source").is_dir() else ROOT / "src"

ORDER = ["cso_privileges", "cso_hud", "include/cso_common.inc", "cso_zclass_predator", "cso_zclass_invisible",
         "cso_zclass_undertaker", "cso_zclass_shaman", "cso_zclass_heavy", "cso_zclass_nurse", "cso_zclass_deimos",
         "cso_deimos_round", "cso_human_shop", "cso_knives", "cso_weapons_menu", "cso_human_dodge"]

# Настройки ядра ZP 4.3 Fix5a, которые задаёт проект
ZP_LINES = [
    "// --- ядро ZP 4.3 Fix5a",
    'zp_buy_custom "0"          // встроенные меню покупки ZP выключены: их заменяет 3-этапное меню оружия (ТЗ §3)',
    'zp_ammo_save "1"           // сохранение ammo packs между подключениями (встроено в ZP Fix5a, ТЗ §12)',
    'zp_ammo_save_by "1"        // 1 — по SteamID',
    'zp_ammo_save_limit "100000" // предел значения (также ограничивается во время игры, cso_main_menu)',
]


def cvars(text):
    return re.findall(r'register_cvar\("(cso_[a-z0-9_]+)",\s*"([^"]*)"\)\s*(?://\s*(.*))?', text)


def main():
    out = ["// CSO Zombie 1.6 Custom Edition — настройки модулей.",
           "// Сгенерировано scripts/gen_cfg.py из исходников; проверка: python3 scripts/check_cvars.py",
           "// Значения — ПРЕДЛОЖЕНИЕ, кроме утверждённых в ТЗ. Подключение: exec из amxx.cfg (делает server.sh).", ""]
    out += ZP_LINES + [""]
    seen = set()
    for name in ORDER:
        f = SRC / name if name.endswith(".inc") else SRC / f"{name}.sma"
        text = f.read_text(encoding="utf-8")
        rows = [(n, v, c) for n, v, c in cvars(text) if n not in seen]
        # динамические CVAR магазина: cso_shop_cost_<key>, cso_shop_limit_<key>
        if name == "cso_human_shop":
            keys = re.findall(r'"([a-z0-9_]+)"', re.search(r'SLOT_KEYS\[\]\[\]\s*=\s*\{([^}]*)\}', text).group(1))
            costs = re.findall(r'"([0-9]+)"', re.search(r'SLOT_COST\[\]\[\]\s*=\s*\{([^}]*)\}', text).group(1))
            limits = re.findall(r'"([0-9]+)"', re.search(r'SLOT_LIMIT\[\]\[\]\s*=\s*\{([^}]*)\}', text).group(1))
            for k, c, l in zip(keys, costs, limits):
                rows.append((f"cso_shop_cost_{k}", c, ""))
                rows.append((f"cso_shop_limit_{k}", l, "за раунд, 0 — без лимита"))
        if not rows:
            continue
        out.append(f"// --- {Path(name).name}")
        for n, v, c in rows:
            seen.add(n)
            line = f'{n} "{v}"'
            out.append(f"{line:<44} // {c.strip()}" if c and c.strip() else line)
        out.append("")
    for f in sorted((ROOT / "tools" / "thirdparty").glob("patch_*.py")):
        text = f.read_text(encoding="utf-8")
        rows = re.findall(r'cso_shop_(?:register_item_cvar|set_item_round_limit)\([^,]+,\s*\\?"(cso_[a-z0-9_]+)\\?",\s*\\?"([^"\\]*)\\?"', text)
        rows = [(n, v) for n, v in rows if n not in seen]
        if rows:
            out.append(f"// --- {f.stem.replace('patch_', 'cso_')} (tools/thirdparty/{f.name})")
            for n, v in rows:
                seen.add(n)
                out.append(f'{n} "{v}"')
            out.append("")
    (ROOT / "config" / "cso_custom.cfg").write_text("\n".join(out), encoding="utf-8")
    print(f"cso_custom.cfg: {len(seen)} CVAR")


if __name__ == "__main__":
    main()
