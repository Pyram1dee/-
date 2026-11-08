/*
 * CSO Zombie — Human Shop (ТЗ §4). Валюта — ammo packs ZP.
 * Ассортимент и порядок утверждены и НЕ меняются:
 *   Страница 1: Заморозка, Зажигательная граната, Броня +100, Walter, Poison,
 *               Dual Infinity (жёлтый + красный), Watergun
 *   Страница 2: Новогодний M249, Чёрная винтовка, Чёрный SPAS, Новогодняя двухстволка,
 *               SKULL-5, Новогодний M134, Чёрный AK-47 / 60R, Второй вариант M249
 * Заморозка/Зажигательная/Броня — встроенные (гранаты ZP: flashbang = заморозка, HE = поджог).
 * Остальные позиции выдаёт отдельный плагин оружия, привязанный по ключу (cso_shop_bind);
 * пока плагина/ресурсов нет — позиция видна серым «нет ресурсов» и не продаётся
 * (не заглушка: ничего не списывается и не выдаётся).
 *
 * Гарантии: только живой человек (выживший — по CVAR); проверки повторяются при выборе;
 * встроенный предмет — сначала выдача и проверка, потом списание; внешний — списание, forward,
 * возврат при PLUGIN_HANDLED; нет дублей; лимит на раунд (cso_shop_limit_<ключ>);
 * разрешённые режимы (cso_shop_modes).
 *
 * Категория VIP (не страница магазина): предметы VIP меню (Jetpack + Bazooka) — команда cso_vipweapons,
 * только VIP, с лимитом «раз в N раундов» по SteamID.
 */

#include <amxmodx>
#include <fakemeta>
#include <fun>
#include <cstrike>
#include <zombieplague>

#define PLUGIN  "[CSO] Human Shop"
#define VERSION "0.3.0"
#define AUTHOR  "CSO Custom Project"

#pragma reqlib cso_priv
native cso_is_vip(id)

#define MAXP 32
#define MAX_ITEMS 32
#define PAGE1_COUNT 7

enum { T_GRENADE = 0, T_ARMOR, T_EXTERNAL }
enum { CAT_PAGE = 0, CAT_VIP }

// Утверждённые позиции (порядок = порядок в меню)
new const SLOT_KEYS[][] = { "frost", "fire", "armor", "walter", "poison", "dual_infinity", "watergun",
	"xmas_m249", "black_rifle", "black_spas", "xmas_dbarrel", "skull5", "xmas_m134", "black_ak47", "m249_v2" }
new const SLOT_NAMES[][] = { "Заморозка", "Зажигательная граната", "Броня +100", "Walter", "Poison",
	"Dual Infinity (жёлтый + красный)", "Watergun",
	"Новогодний M249", "Чёрная винтовка", "Чёрный SPAS", "Новогодняя двухстволка", "SKULL-5",
	"Новогодний M134", "Чёрный AK-47 / 60R", "Второй вариант M249" }
new const SLOT_TYPES[] = { T_GRENADE, T_GRENADE, T_ARMOR, T_EXTERNAL, T_EXTERNAL, T_EXTERNAL, T_EXTERNAL,
	T_EXTERNAL, T_EXTERNAL, T_EXTERNAL, T_EXTERNAL, T_EXTERNAL, T_EXTERNAL, T_EXTERNAL, T_EXTERNAL }
// Цены и лимиты по умолчанию — ПРЕДЛОЖЕНИЕ
new const SLOT_COST[][]  = { "4", "4", "5", "15", "30", "20", "10", "30", "25", "25", "20", "35", "40", "30", "30" }
new const SLOT_LIMIT[][] = { "2", "2", "1", "1", "1", "1", "1", "1", "1", "1", "1", "1", "1", "1", "1" }

// Реестр: 0..14 — слоты страниц, далее — VIP-предметы
new g_name[MAX_ITEMS][48], g_key[MAX_ITEMS][24]
new g_type[MAX_ITEMS], g_cat[MAX_ITEMS]
new bool:g_bound[MAX_ITEMS]
new g_pcv_cost[MAX_ITEMS], g_pcv_limit[MAX_ITEMS], g_pcv_rounds[MAX_ITEMS]
new g_count

new g_bought[MAXP + 1][MAX_ITEMS]   // покупки в текущем раунде
new Trie:g_vip_taken                // "steamid|item" -> номер раунда
new g_round_no = 1, g_mode = 0

new g_pcv_enable, g_pcv_survivor, g_pcv_modes, g_pcv_armor_max
new g_fw_bought

public plugin_natives()
{
	register_library("cso_shop")
	register_native("cso_shop_bind", "native_bind")
	register_native("cso_shop_register_item_cvar", "native_register_vip")
	register_native("cso_shop_set_item_round_limit", "native_set_round_limit")
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_enable    = register_cvar("cso_shop_enable", "1")
	g_pcv_survivor  = register_cvar("cso_shop_allow_survivor", "0")
	// режимы ZP: a — заражение, b — немезида, c — выживший, d — рой, e — множеств. заражение, f — чума;
	// "-" — до начала режима
	g_pcv_modes     = register_cvar("cso_shop_modes", "-abcdef")
	g_pcv_armor_max = register_cvar("cso_shop_armor_max", "200")

	new cvar[48]
	for (new i = 0; i < sizeof SLOT_KEYS; i++)
	{
		copy(g_name[i], charsmax(g_name[]), SLOT_NAMES[i])
		copy(g_key[i], charsmax(g_key[]), SLOT_KEYS[i])
		g_type[i] = SLOT_TYPES[i]
		g_cat[i] = CAT_PAGE
		g_bound[i] = (SLOT_TYPES[i] != T_EXTERNAL)
		formatex(cvar, charsmax(cvar), "cso_shop_cost_%s", SLOT_KEYS[i])
		g_pcv_cost[i] = register_cvar(cvar, SLOT_COST[i])
		formatex(cvar, charsmax(cvar), "cso_shop_limit_%s", SLOT_KEYS[i])
		g_pcv_limit[i] = register_cvar(cvar, SLOT_LIMIT[i])
	}
	g_count = sizeof SLOT_KEYS

	register_clcmd("say /shop", "cmd_shop")
	register_clcmd("say_team /shop", "cmd_shop")
	register_clcmd("cso_shop", "cmd_shop")
	register_clcmd("cso_vipweapons", "cmd_vipweapons")

	register_menucmd(register_menuid("CSO Human Shop 1"), 1023, "page1_handler")
	register_menucmd(register_menuid("CSO Human Shop 2"), 1023, "page2_handler")
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")

	g_fw_bought = CreateMultiForward("cso_shop_item_bought", ET_CONTINUE, FP_CELL, FP_CELL)
	g_vip_taken = TrieCreate()
}

public plugin_cfg()
{
	// отчёт о позициях без плагина/ресурсов (ТЗ §17: перечислять отсутствующее)
	for (new i = 0; i < sizeof SLOT_KEYS; i++)
		if (!g_bound[i])
			log_amx("[CSO Shop] «%s» (%s): нет плагина/ресурсов — позиция недоступна", g_name[i], g_key[i])
}

public plugin_end()
{
	TrieDestroy(g_vip_taken)
}

// --- natives ------------------------------------------------------------------

// native cso_shop_bind(const key[], const costcvar[] = "", const defcost[] = "")
// Привязывает плагин оружия к утверждённой позиции; цена — CVAR cso_shop_cost_<key>
public native_bind(plugin, params)
{
	new key[24]
	get_string(1, key, charsmax(key))
	for (new i = 0; i < sizeof SLOT_KEYS; i++)
	{
		if (!equal(key, SLOT_KEYS[i]) || SLOT_TYPES[i] != T_EXTERNAL)
			continue
		if (g_bound[i])
		{
			log_error(AMX_ERR_NATIVE, "[CSO Shop] Позиция %s уже занята другим плагином", key)
			return -1
		}
		g_bound[i] = true
		return i
	}
	log_error(AMX_ERR_NATIVE, "[CSO Shop] Неизвестная позиция %s — ассортимент утверждён, новые позиции не добавляются", key)
	return -1
}

// native cso_shop_register_item_cvar(const name[], const cvarname[], const defcost[], category)
// Разрешено только для VIP меню (category = CSO_SHOP_CAT_VIP)
public native_register_vip(plugin, params)
{
	if (g_count >= MAX_ITEMS)
		return -1
	new cat = (params >= 4) ? get_param(4) : -1
	if (cat != 5) // CSO_SHOP_CAT_VIP в cso_shop.inc
	{
		log_error(AMX_ERR_NATIVE, "[CSO Shop] Новые позиции в Human Shop запрещены (ТЗ §4); только VIP меню")
		return -1
	}
	new cvarname[48], defcost[16]
	get_string(1, g_name[g_count], charsmax(g_name[]))
	get_string(2, cvarname, charsmax(cvarname))
	get_string(3, defcost, charsmax(defcost))
	g_key[g_count][0] = 0
	g_type[g_count] = T_EXTERNAL
	g_cat[g_count] = CAT_VIP
	g_bound[g_count] = true
	g_pcv_cost[g_count] = register_cvar(cvarname, defcost)
	g_pcv_limit[g_count] = 0
	return g_count++
}

// native cso_shop_set_item_round_limit(itemid, const cvarname[], const defrounds[])
public native_set_round_limit(plugin, params)
{
	new item = get_param(1)
	if (item < 0 || item >= g_count)
		return 0
	new cvarname[48], defval[8]
	get_string(2, cvarname, charsmax(cvarname))
	get_string(3, defval, charsmax(defval))
	g_pcv_rounds[item] = register_cvar(cvarname, defval)
	return 1
}

// --- состояние раунда ------------------------------------------------------------

public zp_round_started(gamemode, id)
{
	g_mode = gamemode
}

public ev_new_round()
{
	g_round_no++
	g_mode = 0
	for (new id = 1; id <= MAXP; id++)
		arrayset(g_bought[id], 0, MAX_ITEMS)
}

public client_disconnected(id)
{
	arrayset(g_bought[id], 0, MAX_ITEMS)
}

// --- проверки --------------------------------------------------------------------

bool:mode_allowed()
{
	new modes[16]
	get_pcvar_string(g_pcv_modes, modes, charsmax(modes))
	new c = (g_mode == 0) ? '-' : ('a' + g_mode - 1)
	return contain(modes, fmt("%c", c)) != -1
}

bool:can_use_shop(id, bool:notify)
{
	if (!get_pcvar_num(g_pcv_enable))
	{
		if (notify) client_print(id, print_chat, "[CSO] Магазин отключён")
		return false
	}
	if (!is_user_alive(id) || zp_get_user_zombie(id))
	{
		if (notify) client_print(id, print_chat, "[CSO] Магазин людей доступен только живым людям")
		return false
	}
	if (zp_get_user_survivor(id) && !get_pcvar_num(g_pcv_survivor))
	{
		if (notify) client_print(id, print_chat, "[CSO] Выжившему магазин недоступен")
		return false
	}
	if (!mode_allowed())
	{
		if (notify) client_print(id, print_chat, "[CSO] В этом режиме магазин людей закрыт")
		return false
	}
	return true
}

item_cost(i)
{
	return max(0, get_pcvar_num(g_pcv_cost[i]))
}

bool:can_receive(id, i, reason[], len)
{
	switch (g_type[i])
	{
		case T_GRENADE:
		{
			new csw = (i == 0) ? CSW_FLASHBANG : CSW_HEGRENADE
			if (user_has_weapon(id, csw))
			{
				copy(reason, len, "уже есть")
				return false
			}
		}
		case T_ARMOR:
		{
			if (get_user_armor(id) >= get_pcvar_num(g_pcv_armor_max))
			{
				copy(reason, len, "броня уже максимальная")
				return false
			}
		}
	}
	if (g_pcv_limit[i])
	{
		new limit = get_pcvar_num(g_pcv_limit[i])
		if (limit > 0 && g_bought[id][i] >= limit)
		{
			formatex(reason, len, "лимит %d за раунд", limit)
			return false
		}
	}
	if (g_pcv_rounds[i])
	{
		new wait = vip_rounds_left(id, i)
		if (wait > 0)
		{
			formatex(reason, len, "снова доступно через %d раунд(а)", wait)
			return false
		}
	}
	return true
}

// --- меню страниц (порядок фиксирован) --------------------------------------------

public cmd_shop(id)
{
	if (can_use_shop(id, true))
		show_page(id, 1)
	return PLUGIN_HANDLED
}

show_page(id, page)
{
	new menu[1024], len, keys
	new from = (page == 1) ? 0 : PAGE1_COUNT
	new to = (page == 1) ? PAGE1_COUNT : sizeof SLOT_KEYS
	new packs = zp_get_user_ammo_packs(id)

	len = formatex(menu, charsmax(menu), "\yМагазин людей \w(стр. %d/2)^nAmmo packs: \r%d^n^n", page, packs)
	for (new i = from, n = 1; i < to; i++, n++)
	{
		if (!g_bound[i])
			len += formatex(menu[len], charsmax(menu) - len, "\d%d. %s — нет ресурсов^n", n, g_name[i])
		else
		{
			new cost = item_cost(i)
			len += formatex(menu[len], charsmax(menu) - len, "\r%d.\w %s %s%d AP^n", n, g_name[i], (packs >= cost) ? "\y" : "\r", cost)
			keys |= (1 << (n - 1))
		}
	}
	if (page == 1)
	{
		len += formatex(menu[len], charsmax(menu) - len, "^n\r8.\w Далее")
		keys |= (1 << 7)
	}
	else
	{
		len += formatex(menu[len], charsmax(menu) - len, "^n\r9.\w Назад")
		keys |= (1 << 8)
	}
	len += formatex(menu[len], charsmax(menu) - len, "^n\r0.\w Выход")
	keys |= (1 << 9)
	show_menu(id, keys, menu, -1, (page == 1) ? "CSO Human Shop 1" : "CSO Human Shop 2")
}

public page1_handler(id, key)
{
	if (key == 9)
		return PLUGIN_HANDLED
	if (key == 7)
	{
		if (can_use_shop(id, true))
			show_page(id, 2)
		return PLUGIN_HANDLED
	}
	if (0 <= key < PAGE1_COUNT)
	{
		buy_item(id, key)
		if (can_use_shop(id, false))
			show_page(id, 1)
	}
	return PLUGIN_HANDLED
}

public page2_handler(id, key)
{
	if (key == 9)
		return PLUGIN_HANDLED
	if (key == 8)
	{
		if (can_use_shop(id, true))
			show_page(id, 1)
		return PLUGIN_HANDLED
	}
	new i = PAGE1_COUNT + key
	if (key < 8 && i < sizeof SLOT_KEYS)
	{
		buy_item(id, i)
		if (can_use_shop(id, false))
			show_page(id, 2)
	}
	return PLUGIN_HANDLED
}

// --- VIP оружие (VIP меню → пункт 1) ---------------------------------------------

public cmd_vipweapons(id)
{
	if (!cso_is_vip(id))
	{
		client_print(id, print_chat, "[CSO] VIP оружие доступно только VIP")
		return PLUGIN_HANDLED
	}
	if (!can_use_shop(id, true))
		return PLUGIN_HANDLED

	new menu = menu_create("\yVIP оружие", "vip_handler")
	new info[4], line[96], n = 0
	for (new i = 0; i < g_count; i++)
	{
		if (g_cat[i] != CAT_VIP)
			continue
		formatex(line, charsmax(line), "%s \y%d AP", g_name[i], item_cost(i))
		num_to_str(i, info, charsmax(info))
		menu_additem(menu, line, info)
		n++
	}
	if (!n)
	{
		menu_destroy(menu)
		client_print(id, print_chat, "[CSO] VIP оружие: ассортимент на согласовании")
		return PLUGIN_HANDLED
	}
	menu_setprop(menu, MPROP_EXITNAME, "Выход")
	menu_display(id, menu)
	return PLUGIN_HANDLED
}

public vip_handler(id, menu, item)
{
	new info[4], access, cb
	if (item != MENU_EXIT)
		menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, cb)
	menu_destroy(menu)
	if (item == MENU_EXIT)
		return PLUGIN_HANDLED
	new i = str_to_num(info)
	if (g_cat[i] != CAT_VIP || !cso_is_vip(id))
		return PLUGIN_HANDLED
	buy_item(id, i)
	return PLUGIN_HANDLED
}

vip_key(id, i, key[], len)
{
	new auth[40]
	get_user_authid(id, auth, charsmax(auth)) // по SteamID: перезаход не сбрасывает ограничение
	formatex(key, len, "%s|%d", auth, i)
}

vip_rounds_left(id, i)
{
	new limit = get_pcvar_num(g_pcv_rounds[i])
	if (limit <= 0)
		return 0
	new key[64], last
	vip_key(id, i, key, charsmax(key))
	if (!TrieGetCell(g_vip_taken, key, last))
		return 0
	new passed = g_round_no - last
	return (passed >= limit) ? 0 : limit - passed
}

// --- покупка ---------------------------------------------------------------------

buy_item(id, i)
{
	// состояние могло измениться, пока меню было открыто
	if (!can_use_shop(id, true) || i < 0 || i >= g_count)
		return
	if (!g_bound[i])
	{
		client_print(id, print_chat, "[CSO] «%s»: нет плагина/ресурсов — позиция недоступна", g_name[i])
		return
	}
	if (g_cat[i] == CAT_VIP && !cso_is_vip(id))
		return

	new reason[64]
	new cost = item_cost(i)
	new packs = zp_get_user_ammo_packs(id)
	if (packs < cost)
	{
		client_print(id, print_chat, "[CSO] Недостаточно ammo packs: нужно %d, есть %d", cost, packs)
		return
	}
	if (!can_receive(id, i, reason, charsmax(reason)))
	{
		client_print(id, print_chat, "[CSO] %s: %s", g_name[i], reason)
		return
	}

	if (g_type[i] == T_EXTERNAL)
	{
		zp_set_user_ammo_packs(id, packs - cost)
		new ret
		ExecuteForward(g_fw_bought, ret, id, i)
		if (ret >= PLUGIN_HANDLED)
		{
			zp_set_user_ammo_packs(id, zp_get_user_ammo_packs(id) + cost)
			client_print(id, print_chat, "[CSO] %s: выдача не удалась, ammo packs возвращены", g_name[i])
			return
		}
	}
	else
	{
		if (!give_builtin(id, i))
		{
			client_print(id, print_chat, "[CSO] %s: выдача не удалась, ammo packs не списаны", g_name[i])
			log_amx("[CSO Shop] Не удалось выдать %s игроку #%d", g_name[i], id)
			return
		}
		zp_set_user_ammo_packs(id, packs - cost)
	}

	g_bought[id][i]++
	if (g_pcv_rounds[i])
	{
		new key[64]
		vip_key(id, i, key, charsmax(key))
		TrieSetCell(g_vip_taken, key, g_round_no)
	}
	client_print(id, print_chat, "[CSO] Получено: %s за %d AP", g_name[i], cost)
}

bool:give_builtin(id, i)
{
	if (g_type[i] == T_ARMOR)
	{
		new armor = min(get_user_armor(id) + 100, get_pcvar_num(g_pcv_armor_max))
		cs_set_user_armor(id, armor, CS_ARMOR_VESTHELM)
		return (get_user_armor(id) == armor)
	}
	new csw = (i == 0) ? CSW_FLASHBANG : CSW_HEGRENADE
	give_item(id, (i == 0) ? "weapon_flashbang" : "weapon_hegrenade")
	return bool:user_has_weapon(id, csw)
}
