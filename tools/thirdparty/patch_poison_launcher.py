"""Адаптация Poison Launcher 1.8.1 (Re.Act!ve) под CSO Custom Edition.

Исходник автора в репозиторий не входит: берётся из vendor/poison_launcher/ (архив пользователя
9778_-_amxx_public_poison_launcher_1.8.1.rar). Скрипт применяет точечные замены и пишет
build/thirdparty/cso_poison_launcher.sma. Каждая замена проверяется: если исходник отличается
от ожидаемого (другая версия), скрипт останавливается, а не собирает непроверенный код.

  python3 tools/thirdparty/patch_poison_launcher.py [исходник.sma] [выход.sma]
"""
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "vendor" / "poison_launcher" / "amxx_public_poison_launcher_1.8.1.sma"
OUT = ROOT / "build" / "thirdparty" / "cso_poison_launcher.sma"

# (что найти, на что заменить, зачем) — каждая строка должна встретиться ровно один раз
PATCHES = [
    # --- метаданные
    ('#define VERSION "1.8.1"', '#define VERSION "1.8.1-cso1"', "пометка адаптированной версии"),
    ('new const g_item_name[] = { "Poison Launcher" }; // Item name\n', "// CSO: название — позиция «Poison» Human Shop\n", "имя из слота магазина"),
    ("new const g_item_cost = 1 ; // Item cost\n", "// CSO: цена — CVAR cso_shop_cost_poison (Human Shop)\n", "цена из CVAR"),
    # --- 1. пути ресурсов приведены к содержимому архива (иначе precache отсутствующего файла роняет сервер)
    ('"sprites/zm/poison_spr.spr"', '"sprites/poison_spr.spr"', "путь спрайта как в архиве"),
    ('"sprites/zm/poison_flare.spr"', '"sprites/poison_flare.spr"', "путь спрайта как в архиве"),
    ('"models/zm/v_plaunch1.mdl"', '"models/zm/v_plaunch.mdl"', "путь модели как в архиве"),
    ('"models/zm/p_plaunch1.mdl"', '"models/zm/p_plaunch.mdl"', "путь модели как в архиве"),
    # --- 2. покупка только через Human Shop, цена из CVAR
    ("#include <zombieplague>\n", "#include <zombieplague>\n#include <cso_shop>\n", "API магазина CSO"),
    ("\tg_itemid = zp_register_extra_item(g_item_name, g_item_cost, ZP_TEAM_HUMAN)\n",
     '\t// CSO: не регистрируемся в extra items ZP (там цена 1 AP) — только позиция «Poison» Human Shop\n'
     '\t// (страница 1, пункт 5; цена cso_shop_cost_poison, лимит cso_shop_limit_poison)\n'
     '\tg_itemid = cso_shop_bind("poison")\n'
     '\tregister_event("HLTV", "cso_ev_new_round", "a", "1=0", "2=0")\n',
     "регистрация в Human Shop"),
    ("public zp_extra_item_selected(id, itemid)\n{\n\tif(itemid == g_itemid) \n\t{\n",
     "public cso_shop_item_bought(id, itemid)\n{\n\tif(itemid != g_itemid)\n\t\treturn PLUGIN_CONTINUE;\n"
     "\t// повторная проверка: магазин вернёт AP, если выдать нельзя\n"
     "\tif(!is_user_alive(id) || zp_get_user_zombie(id) || g_has_item[id])\n\t\treturn PLUGIN_HANDLED;\n\t{\n",
     "обработчик покупки из магазина"),
    ("\t\tnew iWep2 = fm_give_item(id,gWeapon)\n\t\tif( iWep2 > 0 )\n",
     "\t\tnew iWep2 = fm_give_item(id,gWeapon)\n\t\tif( iWep2 <= 0 )\n\t\t{\n\t\t\tg_has_item[id] = false\n"
     "\t\t\treturn PLUGIN_HANDLED // не выдали — возврат AP\n\t\t}\n\t\tif( iWep2 > 0 )\n",
     "проверка факта выдачи"),
    ("\t\temit_sound(id, CHAN_WEAPON, g_sound[0], 1.0, ATTN_NORM, 0, PITCH_NORM)\n\t}\n}\n\npublic fw_PrimaryAttack(Weapon)",
     "\t\temit_sound(id, CHAN_WEAPON, g_sound[0], 1.0, ATTN_NORM, 0, PITCH_NORM)\n\t}\n\treturn PLUGIN_CONTINUE\n}\n\npublic fw_PrimaryAttack(Weapon)",
     "возврат значения из forward"),
    # --- 3. отладочный вывод всем игрокам
    ('\tclient_print(0, print_center, "Touch")\n', "", "убран отладочный спам"),
    # --- 4/5. облако: только зомби, замедление снимается через ResetMaxSpeed ядра
    ("\tif(is_user_alive(touch))\n\t{\n\t\tstatic Float:CurTime",
     "\tif(is_user_alive(touch) && zp_get_user_zombie(touch))\n\t{\n\t\tstatic Float:CurTime",
     "облако действует только на зомби"),
    ("\t\t\tnew Owner = pev(ent, pev_owner)\n\t\t\tExecuteHamB(Ham_TakeDamage, touch, Owner, touch, 50.0, DMG_BLAST)\n\t\t\tset_pev(touch, pev_maxspeed, 20.0)\t\n",
     "\t\t\tnew Owner = pev(ent, pev_owner)\n\t\t\tif(!is_user_connected(Owner)) Owner = 0\n"
     "\t\t\tExecuteHamB(Ham_TakeDamage, touch, ent, Owner, 50.0, DMG_BLAST)\n\t\t\tset_pev(touch, pev_maxspeed, 20.0)\t\n"
     "\t\t\t// снять замедление через секунду (client_PostThink)\n"
     "\t\t\tgPoisonGlow[touch] = CurTime + 1.0\n\t\t\tgGlowPlayer[touch] = true\n",
     "урон облака с корректными inflictor/attacker, гарантированный сброс скорости"),
    ("\t\tset_pev(id, pev_maxspeed, 100.0) // prevent from moving\n",
     "\t\tExecuteHamB(Ham_Item_PreFrame, id) // CSO: вернуть штатную скорость (ResetMaxSpeed ядра ZP)\n",
     "скорость не остаётся 100 навсегда"),
    # --- 5/6. прямое попадание: только зомби, корректный inflictor
    ("\tif(!is_user_alive(id) || !is_user_connected(id)) {\n\t\tremove_entity(ent)\n\t\treturn FMRES_IGNORED\n\t}\n",
     "\tif(!is_user_alive(id) || !is_user_connected(id)) {\n\t\tremove_entity(ent)\n\t\treturn FMRES_IGNORED\n\t}\n"
     "\t// CSO: по людям (своей команде) снаряд не действует\n"
     "\tif(!zp_get_user_zombie(id)) {\n\t\tremove_entity(ent)\n\t\treturn FMRES_IGNORED\n\t}\n",
     "прямое попадание только по зомби"),
    ("\t\tattacker = pev(ent, pev_owner)\n",
     "\t\tattacker = pev(ent, pev_owner)\n\t\tif(!is_user_connected(attacker)) attacker = 0\n",
     "владелец мог выйти"),
    ('\t\t\tExecuteHam(Ham_TakeDamage, id, "poison_launcher", attacker, ',
     "\t\t\tExecuteHamB(Ham_TakeDamage, id, ent, attacker, ",
     "inflictor — сущность снаряда, а не строка"),
    # --- 7. снаряд с ограниченным временем жизни
    ('\tnew iEnt = create_entity("info_target")\n',
     '\tnew iEnt = create_entity("info_target")\n\tif(!pev_valid(iEnt))\n\t\treturn\n', "проверка создания"),
    ("\tset_pev(iEnt, PEV_ENT_TIME, get_gametime() + 5.0)\t// time remove\n",
     "\tset_pev(iEnt, PEV_ENT_TIME, get_gametime() + 5.0)\t// time remove\n"
     "\tset_pev(iEnt, pev_nextthink, get_gametime() + 0.05) // CSO: без этого fw_think не вызывался\n",
     "запуск think снаряда"),
    # --- 8. удаление облака по таймеру — только своей сущности
    ("\tif(is_valid_ent(Ent)) engfunc(EngFunc_RemoveEntity, Ent)\n",
     "\tif(is_valid_ent(Ent))\n\t{\n\t\tstatic cls[32]\n\t\tpev(Ent, pev_classname, cls, charsmax(cls))\n"
     "\t\tif(equal(cls, poison_classname)) engfunc(EngFunc_RemoveEntity, Ent)\n\t}\n",
     "не удалять чужую сущность с переиспользованным индексом"),
    # --- AMXX 1.9
    ("public client_disconnect(id)\n", "public client_disconnected(id)\n", "устаревший forward"),
]

APPEND = """
// --- CSO: очистка снарядов и облаков в новом раунде
public cso_ev_new_round()
{
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", poison_classname)) > 0)
	{
		remove_task(ent + 1234)
		engfunc(EngFunc_RemoveEntity, ent)
	}
	ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", fire_classname)) > 0)
		engfunc(EngFunc_RemoveEntity, ent)
}
"""


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else SRC
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else OUT
    if not src.exists():
        print(f"[poison_launcher] нет {src} — пропуск (см. docs/ENVIRONMENT.md)")
        return 2
    raw = src.read_bytes()
    print(f"[poison_launcher] исходник {src.name}, SHA-256 {hashlib.sha256(raw).hexdigest()}")
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for find, repl, why in PATCHES:
        n = text.count(find)
        if n != 1:
            print(f"[poison_launcher] ОШИБКА: фрагмент для «{why}» найден {n} раз(а) — исходник другой версии")
            return 1
        text = text.replace(find, repl)
    text += APPEND
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")
    print(f"[poison_launcher] применено правок: {len(PATCHES)} -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
