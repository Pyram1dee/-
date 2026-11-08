"""Сверка CVAR: config/cso_custom.cfg <-> регистрации в коде.
Источники: register_cvar в source/src, CVAR магазина (cso_shop_cost_/limit_<ключ> из SLOT_KEYS),
CVAR из патчей tools/thirdparty, CVAR ядра ZP (vendor/zp43fix5a). Ловит опечатки и забытые CVAR,
не заменяет проверку на HLDS."""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = root / "source" if (root / "source").is_dir() else root / "src"
reg = {}
for f in list(src.glob("*.sma")) + list((src / "include").glob("*.inc")):
    t = f.read_text(encoding="utf-8")
    for m in re.finditer(r'register_cvar\("([a-z0-9_]+)"', t):
        reg.setdefault(m.group(1), f.name)
    keys = re.search(r'SLOT_KEYS\[\]\[\]\s*=\s*\{([^}]*)\}', t)
    if keys:
        for k in re.findall(r'"([a-z0-9_]+)"', keys.group(1)):
            reg.setdefault("cso_shop_cost_" + k, f.name)
            reg.setdefault("cso_shop_limit_" + k, f.name)
for f in (root / "tools" / "thirdparty").glob("*.py"):
    for m in re.finditer(r'cso_shop_(?:register_item_cvar|set_item_round_limit)\([^,]+,\s*\\?"(cso_[a-z0-9_]+)\\?"', f.read_text(encoding="utf-8")):
        reg.setdefault(m.group(1), f.name)
zp = root / "vendor" / "zp43fix5a" / "addons" / "amxmodx" / "scripting" / "zombie_plague40.sma"
zp_cvars = set(re.findall(r'register_cvar\("(zp_[a-z0-9_]+)"', zp.read_text(encoding="utf-8", errors="replace"))) if zp.exists() else set()

cfg = {}
for line in (root / "config" / "cso_custom.cfg").read_text(encoding="utf-8").splitlines():
    line = line.split("//")[0].strip()
    if line:
        cfg[line.split()[0]] = line

errors = 0
for c in sorted(cfg):
    if c.startswith("zp_"):
        if zp_cvars and c not in zp_cvars:
            print(f"ОШИБКА: {c} нет в ядре ZP 4.3 Fix5a")
            errors += 1
    elif c not in reg:
        print(f"ОШИБКА: {c} есть в cso_custom.cfg, но не регистрируется ни одним плагином")
        errors += 1
for c in sorted(set(reg) - set(cfg)):
    if c.startswith("cso_") and c != "cso_custom_version":
        print(f"ПРЕДУПРЕЖДЕНИЕ: {c} ({reg[c]}) нет в cso_custom.cfg")
print(f"CVAR в коде: {len(reg)}, в конфиге: {len(cfg)} (из них ядра ZP: {sum(c.startswith('zp_') for c in cfg)}); ошибок: {errors}")
sys.exit(1 if errors else 0)
