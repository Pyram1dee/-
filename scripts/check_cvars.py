"""Сверка CVAR: config/cso_custom.cfg <-> register_cvar в src/*.sma и src/include/*.inc.
Не заменяет проверку на HLDS: только ловит опечатки и забытые CVAR."""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
reg = {}
for f in list((root / "src").glob("*.sma")) + list((root / "src" / "include").glob("*.inc")):
    for m in re.finditer(r'register_cvar\("([a-z0-9_]+)"', f.read_text(encoding="utf-8")):
        reg.setdefault(m.group(1), f.name)
    # динамические cso_shop_cost_<key>
    keys = re.search(r'B_KEY\[\]\[\]\s*=\s*\{([^}]*)\}', f.read_text(encoding="utf-8"))
    if keys:
        for k in re.findall(r'"([a-z0-9_]+)"', keys.group(1)):
            reg.setdefault("cso_shop_cost_" + k, f.name)

# CVAR, которые регистрирует магазин по запросу внешних плагинов (cso_shop_register_item_cvar),
# в т.ч. из патчей сторонних плагинов в tools/thirdparty
for f in list((root / "src").glob("*.sma")) + list((root / "tools" / "thirdparty").glob("*.py")):
    for m in re.finditer(r'cso_shop_(?:register_item_cvar|set_item_round_limit)\([^,]+,\s*\\?"(cso_[a-z0-9_]+)\\?"', f.read_text(encoding="utf-8")):
        reg.setdefault(m.group(1), f.name)

cfg = {}
for line in (root / "config" / "cso_custom.cfg").read_text(encoding="utf-8").splitlines():
    line = line.split("//")[0].strip()
    if line:
        cfg[line.split()[0]] = line

missing_in_src = sorted(set(cfg) - set(reg))
missing_in_cfg = sorted(c for c in set(reg) - set(cfg) if c.startswith("cso_") and c != "cso_custom_version")
for c in missing_in_src:
    print(f"ОШИБКА: {c} есть в cso_custom.cfg, но не регистрируется ни одним плагином")
for c in missing_in_cfg:
    print(f"ПРЕДУПРЕЖДЕНИЕ: {c} ({reg[c]}) нет в cso_custom.cfg")
print(f"CVAR в исходниках: {len(reg)}, в конфиге: {len(cfg)}")
sys.exit(1 if missing_in_src else 0)
