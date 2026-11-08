"""Адаптация "[ZP] Extra Item Jetpack+Bazooka 3.2" (B!gBud; основа AMX Jetpack — KleeneX)
под CSO Custom Edition.

Исходник не входит в репозиторий: vendor/jetpack/zp_jetpack_bazooka_3.2.sma
(копия с https://pastebin.com/raw/S89uALZp; релиз на AlliedModders недоступен из среды).
Каждая замена проверяется на точное число вхождений: другой исходник — остановка.

  python3 tools/thirdparty/patch_jetpack.py [исходник.sma] [выход.sma]
"""
import hashlib
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "vendor" / "jetpack" / "zp_jetpack_bazooka_3.2.sma"
OUT = ROOT / "build" / "thirdparty" / "cso_jetpack.sma"

# (найти, заменить, ожидаемое число вхождений, зачем)
PATCHES = [
    ('#define VERSION\t\t\t"3.2"', '#define VERSION\t\t\t"3.2-cso1"', 1, "пометка версии"),
    ("#include <cstrike>\n", "#include <cstrike>\n#include <zombieplague>\n#include <cso_shop>\n", 1, "API ZP и магазина"),
    # 1. бесплатная выдача по /jetpack любому (включая зомби) -> покупка только в Human Shop
    ('\tregister_clcmd("say /jetpack", "cmdBuy")\n',
     '\t// CSO: бесплатный "say /jetpack" убран. Купить нельзя: только VIP через /vipmenu,\n'
     '\t// не чаще раза в cso_jetpack_vip_rounds раундов; остальные люди — только подобрать с пола\n'
     '\tg_jp_item = cso_shop_register_item_cvar("Jetpack + Bazooka", "cso_jetpack_cost", "0", CSO_SHOP_CAT_VIP)\n'
     '\tcso_shop_set_item_round_limit(g_jp_item, "cso_jetpack_vip_rounds", "3")\n'
     '\tregister_think("zp_jp_rocket", "cso_rocket_think")\n'
     '\tregister_event("HLTV", "cso_jp_new_round", "a", "1=0", "2=0")\n', 1, "только VIP-меню, раз в 3 раунда"),
    ('\tp_JetpackCost = register_cvar("Jetpack_Money_Cost", "100")  // Cost of Jetpack in CS Money \n', "", 1, "мёртвая «цена в деньгах CS»"),
    ('\tp_BuyJetpack = register_cvar("Jetpack_buy", "1") // If you  don\'t want to buy jetpack set it to 0\n', "", 1, "мёртвый переключатель покупки"),
    ("new p_JetpackCost\nnew p_BuyJetpack\n", "new g_jp_item\nnew bool:g_snd_jet, bool:g_snd_blow\n", 1, "переменные CSO"),
    ("public cmdBuy(player){\n\tif (get_pcvar_num(p_BuyJetpack) == 1)\n\t\tcs_get_user_money(player + get_pcvar_num(p_JetpackCost))\n",
     "public cso_shop_item_bought(player, itemid){\n\tif (itemid != g_jp_item)\n\t\treturn PLUGIN_CONTINUE;\n"
     "\t// CSO: только живой человек (не выживший) без джетпака; иначе магазин вернёт AP\n"
     "\tif (!is_user_alive(player) || zp_get_user_zombie(player) || zp_get_user_survivor(player) || hasjet[player])\n"
     "\t\treturn PLUGIN_HANDLED;\n", 1, "обработчик покупки"),
    ('\t\tengclient_cmd(player,"weapon_knife"),switchmodel(player)\n\t}\n}\n',
     '\t\tengclient_cmd(player,"weapon_knife"),switchmodel(player)\n\t}\n\treturn PLUGIN_CONTINUE;\n}\n', 1, "возврат из forward"),
    # 2. подобрать джетпак может только человек
    ("if(!hasjet[id] && is_user_alive(id)) {",
     "if(!hasjet[id] && is_user_alive(id) && !zp_get_user_zombie(id) && !zp_get_user_survivor(id)) {", 1,
     "зомби не подбирают джетпак"),
    # 3. урон ракеты — только по зомби и через Ham_TakeDamage (ZP считает убийства и награды)
    ("\t\t\t\tnew hp = get_user_health(i)\n", "", 1, "лишняя переменная"),
    ("\t\t\t\tnew Origin[3]\n\t\t\t\tget_user_origin(i,Origin)\n\t\t\t\t\n"
     "\t\t\t\tif(get_user_team(id) != get_user_team(i)) {\n\t\t\t\t\t\tif(hp > damage)\n"
     "\t\t\t\t\t\t\tjp_take_damage(i,floatround(damage),Origin,DMG_BLAST)\n\t\t\t\t\t\telse\n"
     '\t\t\t\t\t\t\tlog_kill(id,i,"Jetpack Rocket",0)\n\t\t\t\t\t}\n',
     "\t\t\t\t// CSO: только по зомби, через Ham_TakeDamage — убийства, награды и иммунитеты считает ZP\n"
     "\t\t\t\tif(zp_get_user_zombie(i) && damage > 0.0)\n"
     "\t\t\t\t\tExecuteHamB(Ham_TakeDamage, i, entity, is_user_connected(id) ? id : 0, damage, DMG_BLAST)\n",
     1, "урон по правилам ZP"),
    # 4. звуков jetpack.wav/jp_blow.wav нет ни в CS, ни в источнике
    ('\tprecache_sound("jetpack.wav")\n\tprecache_sound("jp_blow.wav")\n',
     '\t// CSO: этих звуков нет в CS/HL и в источнике — грузим, только если файл есть на сервере\n'
     '\tif (file_exists("sound/jetpack.wav")) { precache_sound("jetpack.wav"); g_snd_jet = true; }\n'
     '\tif (file_exists("sound/jp_blow.wav")) { precache_sound("jp_blow.wav"); g_snd_blow = true; }\n', 1, "звуки по наличию"),
    ('emit_sound(player,CHAN_ITEM,"jetpack.wav",', 'if (g_snd_jet) emit_sound(player,CHAN_ITEM,"jetpack.wav",', 2, "звук полёта"),
    ('emit_sound(player,CHAN_ITEM,"jp_blow.wav",', 'if (g_snd_blow) emit_sound(player,CHAN_ITEM,"jp_blow.wav",', 2, "звук низкого топлива"),
    # 5. ракета с ограниченным временем жизни
    ("\t\tentity_set_float(rocket, EV_FL_takedamage, 1.0)\n",
     "\t\tentity_set_float(rocket, EV_FL_takedamage, 1.0)\n"
     "\t\tentity_set_float(rocket, EV_FL_nextthink, get_gametime() + 6.0) // CSO: ракета не живёт вечно\n", 1,
     "время жизни ракеты"),
    # 6. AMXX 1.9
    ("public client_disconnect(id) {", "public client_disconnected(id) {", 1, "устаревший forward"),
]

APPEND = """
// --- CSO: ракета, улетевшая без столкновения, удаляется через 6 с
public cso_rocket_think(ent)
{
	if (is_valid_ent(ent))
		remove_entity(ent)
}

// --- CSO: в новом раунде ракет не остаётся
public cso_jp_new_round()
{
	new ent = -1
	while ((ent = find_ent_by_class(ent, "zp_jp_rocket")) > 0)
		remove_entity(ent)
}
"""


def main():
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else SRC
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else OUT
    if not src.exists():
        print(f"[jetpack] нет {src} — пропуск")
        return 2
    raw = src.read_bytes()
    print(f"[jetpack] исходник {src.name}, SHA-256 {hashlib.sha256(raw).hexdigest()}")
    text = raw.decode("utf-8").replace("\r\n", "\n")
    for find, repl, count, why in PATCHES:
        n = text.count(find)
        if n != count:
            print(f"[jetpack] ОШИБКА: «{why}» — найдено {n}, ожидалось {count}; исходник другой версии")
            return 1
        text = text.replace(find, repl)
    text += APPEND
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")
    print(f"[jetpack] применено правок: {len(PATCHES)} -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
