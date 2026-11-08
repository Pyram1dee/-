/*
 * CSO Zombie — Human Shop (магазин людей)
 * Валюта: ammo packs ZP 4.3 (zp_get/set_user_ammo_packs).
 *
 * Гарантии (TECH_SPEC п. 5):
 *  - только живой человек (выживший — по CVAR);
 *  - все проверки повторяются в момент выбора пункта (меню могло висеть открытым);
 *  - встроенный предмет: сначала выдача и проверка, что он реально появился,
 *    только потом списание — оружие не выдаётся бесплатно и не списывается без выдачи;
 *  - нельзя купить оружие, которое уже есть, броню при полной броне, гранату, если она есть;
 *  - внешний предмет: списание, затем forward; PLUGIN_HANDLED от адаптера → возврат.
 * Цены — предложение, настраиваются CVAR cso_shop_cost_*.
 */

#include <amxmodx>
#include <fakemeta>
#include <fun>
#include <cstrike>
#include <zombieplague>

#define PLUGIN  "[CSO] Human Shop"
#define VERSION "0.2.0"
#define AUTHOR  "CSO Custom Project"

// Категории дублируют cso_shop.inc (include не подключаем: в нём #pragma reqlib на самого себя)
enum
{
	CAT_PISTOLS = 0,
	CAT_RIFLES,
	CAT_HEAVY,
	CAT_EQUIPMENT,
	CAT_SPECIAL,
	CAT_VIP,       // только через /vipmenu, в обычном магазине не показывается
	CAT_COUNT
}
new const CAT_NAMES[CAT_COUNT][] = { "Пистолеты", "Винтовки", "Тяжёлое оружие", "Снаряжение", "Особое", "VIP меню" }

enum
{
	TYPE_PRIMARY = 0,
	TYPE_SECONDARY,
	TYPE_ARMOR,
	TYPE_GRENADE,
	TYPE_EXTERNAL
}

// Встроенные предметы: имя, entity, CSW, тип, категория, ключ CVAR, цена по умолчанию (предложение)
new const B_NAME[][] = { "Desert Eagle", "Dual Elites", "AK-47", "M4A1", "AWP", "M249", "XM1014", "Броня 100 + шлем", "Огненная граната (HE)", "Ледяная граната" }
new const B_ENT[][]  = { "weapon_deagle", "weapon_elite", "weapon_ak47", "weapon_m4a1", "weapon_awp", "weapon_m249", "weapon_xm1014", "", "weapon_hegrenade", "weapon_flashbang" }
new const B_CSW[]    = { CSW_DEAGLE, CSW_ELITE, CSW_AK47, CSW_M4A1, CSW_AWP, CSW_M249, CSW_XM1014, 0, CSW_HEGRENADE, CSW_FLASHBANG }
new const B_TYPE[]   = { TYPE_SECONDARY, TYPE_SECONDARY, TYPE_PRIMARY, TYPE_PRIMARY, TYPE_PRIMARY, TYPE_PRIMARY, TYPE_PRIMARY, TYPE_ARMOR, TYPE_GRENADE, TYPE_GRENADE }
new const B_CAT[]    = { CAT_PISTOLS, CAT_PISTOLS, CAT_RIFLES, CAT_RIFLES, CAT_RIFLES, CAT_HEAVY, CAT_HEAVY, CAT_EQUIPMENT, CAT_EQUIPMENT, CAT_EQUIPMENT }
new const B_KEY[][]  = { "deagle", "elite", "ak47", "m4a1", "awp", "m249", "xm1014", "armor", "hegrenade", "frost" }
new const B_COST[][] = { "5", "6", "12", "12", "15", "20", "14", "5", "4", "4" }

// Полный боезапас, т.к. give_item выдаёт оружие с одним магазином
new const MAXBPAMMO[] = { -1, 52, -1, 90, 1, 32, 1, 100, 90, 1, 120, 100, 100, 90, 90, 90, 100, 120, 30, 120, 200, 32, 90, 120, 90, 2, 35, 90, 90, -1, 100 }

const PRIMARY_BITSUM = (1<<CSW_SCOUT)|(1<<CSW_XM1014)|(1<<CSW_MAC10)|(1<<CSW_AUG)|(1<<CSW_UMP45)|(1<<CSW_SG550)|(1<<CSW_GALIL)|(1<<CSW_FAMAS)|(1<<CSW_AWP)|(1<<CSW_MP5NAVY)|(1<<CSW_M249)|(1<<CSW_M3)|(1<<CSW_M4A1)|(1<<CSW_TMP)|(1<<CSW_G3SG1)|(1<<CSW_SG552)|(1<<CSW_AK47)|(1<<CSW_P90)
const SECONDARY_BITSUM = (1<<CSW_P228)|(1<<CSW_ELITE)|(1<<CSW_FIVESEVEN)|(1<<CSW_USP)|(1<<CSW_GLOCK18)|(1<<CSW_DEAGLE)

// Реестр предметов (встроенные + внешние)
new Array:g_item_name, Array:g_item_cat, Array:g_item_type, Array:g_item_builtin, Array:g_item_cost, Array:g_item_pcvar
new g_item_count

new g_pcv_enable, g_pcv_survivor, g_pcv_vip_flag
new Array:g_item_rounds
new Trie:g_round_taken   // "steamid|item" -> номер раунда последнего получения
new g_round_no = 1
new g_fw_bought

public plugin_natives()
{
	register_library("cso_shop")
	register_native("cso_shop_register_item", "native_register_item")
	register_native("cso_shop_register_item_cvar", "native_register_item_cvar")

	g_item_name    = ArrayCreate(64, 16)
	g_item_cat     = ArrayCreate(1, 16)
	g_item_type    = ArrayCreate(1, 16)
	g_item_builtin = ArrayCreate(1, 16)   // индекс в B_* или -1
	g_item_cost    = ArrayCreate(1, 16)   // цена внешнего предмета
	g_item_pcvar   = ArrayCreate(1, 16)   // pcvar цены встроенного
	g_item_rounds  = ArrayCreate(1, 16)   // pcvar «не чаще раза в N раундов» (0 — без ограничения)
	register_native("cso_shop_set_item_round_limit", "native_set_round_limit")
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_enable   = register_cvar("cso_shop_enable", "1")
	g_pcv_survivor = register_cvar("cso_shop_allow_survivor", "0")
	g_pcv_vip_flag = register_cvar("cso_vip_flag", "t") // общий с VIP Hammer
	g_round_taken = TrieCreate()

	new cvar[48]
	for (new i = 0; i < sizeof B_NAME; i++)
	{
		formatex(cvar, charsmax(cvar), "cso_shop_cost_%s", B_KEY[i])
		add_item(B_NAME[i], B_CAT[i], B_TYPE[i], i, 0, register_cvar(cvar, B_COST[i]))
	}

	register_clcmd("say /shop", "cmd_shop")
	register_clcmd("say_team /shop", "cmd_shop")
	register_clcmd("cso_shop", "cmd_shop")
	register_clcmd("say /vipmenu", "cmd_vipmenu")
	register_clcmd("say_team /vipmenu", "cmd_vipmenu")
	register_clcmd("say /vm", "cmd_vipmenu")
	register_clcmd("cso_vipmenu", "cmd_vipmenu")
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")

	g_fw_bought = CreateMultiForward("cso_shop_item_bought", ET_CONTINUE, FP_CELL, FP_CELL)
}

add_item(const name[], cat, type, builtin, cost, pcvar)
{
	ArrayPushString(g_item_name, name)
	ArrayPushCell(g_item_cat, cat)
	ArrayPushCell(g_item_type, type)
	ArrayPushCell(g_item_builtin, builtin)
	ArrayPushCell(g_item_cost, cost)
	ArrayPushCell(g_item_pcvar, pcvar)
	ArrayPushCell(g_item_rounds, 0)
	return g_item_count++
}

item_cost(item)
{
	new pcvar = ArrayGetCell(g_item_pcvar, item)
	return max(0, pcvar ? get_pcvar_num(pcvar) : ArrayGetCell(g_item_cost, item))
}

// native cso_shop_register_item(const name[], cost, category)
public native_register_item(plugin, params)
{
	new name[64]
	get_string(1, name, charsmax(name))
	new cost = get_param(2)
	new cat = (params >= 3) ? get_param(3) : CAT_SPECIAL
	if (!name[0] || cost < 0)
	{
		log_error(AMX_ERR_NATIVE, "[CSO Shop] Некорректный предмет")
		return -1
	}
	if (cat < 0 || cat >= CAT_COUNT)
		cat = CAT_SPECIAL
	return add_item(name, cat, TYPE_EXTERNAL, -1, cost, 0)
}

// native cso_shop_register_item_cvar(const name[], const cvarname[], const defcost[], category)
public native_register_item_cvar(plugin, params)
{
	new name[64], cvarname[48], defcost[16]
	get_string(1, name, charsmax(name))
	get_string(2, cvarname, charsmax(cvarname))
	get_string(3, defcost, charsmax(defcost))
	new cat = (params >= 4) ? get_param(4) : CAT_SPECIAL
	if (!name[0] || !cvarname[0])
	{
		log_error(AMX_ERR_NATIVE, "[CSO Shop] Некорректный предмет")
		return -1
	}
	if (cat < 0 || cat >= CAT_COUNT)
		cat = CAT_SPECIAL
	return add_item(name, cat, TYPE_EXTERNAL, -1, 0, register_cvar(cvarname, defcost))
}

// ---------------------------------------------------------------------------
// Проверки
// ---------------------------------------------------------------------------

bool:can_use_shop(id, bool:notify)
{
	if (!get_pcvar_num(g_pcv_enable))
	{
		if (notify) client_print(id, print_chat, "[CSO] Магазин отключён")
		return false
	}
	if (!is_user_alive(id) || zp_get_user_zombie(id))
	{
		if (notify) client_print(id, print_chat, "[CSO] Магазин доступен только живым людям")
		return false
	}
	if (zp_get_user_survivor(id) && !get_pcvar_num(g_pcv_survivor))
	{
		if (notify) client_print(id, print_chat, "[CSO] Выжившему магазин недоступен")
		return false
	}
	return true
}

// Возвращает true, если предмет можно выдать (нет дубля)
bool:can_receive(id, item, reason[], len)
{
	new type = ArrayGetCell(g_item_type, item)
	new b = ArrayGetCell(g_item_builtin, item)
	switch (type)
	{
		case TYPE_PRIMARY, TYPE_SECONDARY, TYPE_GRENADE:
		{
			if (user_has_weapon(id, B_CSW[b]))
			{
				copy(reason, len, "у вас уже есть этот предмет")
				return false
			}
		}
		case TYPE_ARMOR:
		{
			if (get_user_armor(id) >= 100)
			{
				copy(reason, len, "броня уже полная")
				return false
			}
		}
	}
	return true
}

// native cso_shop_set_item_round_limit(itemid, const cvarname[], const defrounds[])
public native_set_round_limit(plugin, params)
{
	new item = get_param(1)
	if (item < 0 || item >= g_item_count)
	{
		log_error(AMX_ERR_NATIVE, "[CSO Shop] Неверный id предмета %d", item)
		return 0
	}
	new cvarname[48], defval[8]
	get_string(2, cvarname, charsmax(cvarname))
	get_string(3, defval, charsmax(defval))
	ArraySetCell(g_item_rounds, item, register_cvar(cvarname, defval))
	return 1
}

// ---------------------------------------------------------------------------
// VIP и ограничение по раундам
// ---------------------------------------------------------------------------

bool:is_vip(id)
{
	new flags[24]
	get_pcvar_string(g_pcv_vip_flag, flags, charsmax(flags))
	new need = read_flags(flags)
	return (need != 0 && (get_user_flags(id) & need) == need)
}

taken_key(id, item, key[], len)
{
	new auth[40]
	get_user_authid(id, auth, charsmax(auth)) // по SteamID: перезаход не сбрасывает ограничение
	formatex(key, len, "%s|%d", auth, item)
}

// Сколько раундов ещё ждать (0 — можно)
rounds_left(id, item)
{
	new pcvar = ArrayGetCell(g_item_rounds, item)
	if (!pcvar)
		return 0
	new limit = get_pcvar_num(pcvar)
	if (limit <= 0)
		return 0
	new key[64], last
	taken_key(id, item, key, charsmax(key))
	if (!TrieGetCell(g_round_taken, key, last))
		return 0
	new passed = g_round_no - last
	return (passed >= limit) ? 0 : limit - passed
}

mark_taken(id, item)
{
	if (!ArrayGetCell(g_item_rounds, item))
		return
	new key[64]
	taken_key(id, item, key, charsmax(key))
	TrieSetCell(g_round_taken, key, g_round_no)
}

public ev_new_round()
{
	g_round_no++
}

public cmd_vipmenu(id)
{
	if (!is_vip(id))
	{
		client_print(id, print_chat, "[CSO] VIP меню доступно только VIP")
		return PLUGIN_HANDLED
	}
	if (!can_use_shop(id, true))
		return PLUGIN_HANDLED
	if (!category_has_items(CAT_VIP))
	{
		client_print(id, print_chat, "[CSO] В VIP меню пока нет предметов")
		return PLUGIN_HANDLED
	}
	show_items(id, CAT_VIP)
	return PLUGIN_HANDLED
}

public plugin_end()
{
	TrieDestroy(g_round_taken)
}

// ---------------------------------------------------------------------------
// Меню
// ---------------------------------------------------------------------------

public cmd_shop(id)
{
	if (can_use_shop(id, true))
		show_categories(id)
	return PLUGIN_HANDLED
}

show_categories(id)
{
	new title[96]
	formatex(title, charsmax(title), "\yМагазин людей^n\wAmmo packs: \r%d", zp_get_user_ammo_packs(id))
	new menu = menu_create(title, "shop_menu_categories")

	new info[4]
	for (new c = 0; c < CAT_COUNT; c++)
	{
		if (c == CAT_VIP || !category_has_items(c))
			continue
		num_to_str(c, info, charsmax(info))
		menu_additem(menu, CAT_NAMES[c], info)
	}
	menu_setprop(menu, MPROP_EXITNAME, "Выход")
	menu_display(id, menu)
}

bool:category_has_items(cat)
{
	for (new i = 0; i < g_item_count; i++)
		if (ArrayGetCell(g_item_cat, i) == cat)
			return true
	return false
}

public shop_menu_categories(id, menu, item)
{
	if (item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	new info[4], access, callback
	menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, callback)
	menu_destroy(menu)

	if (can_use_shop(id, true))
		show_items(id, str_to_num(info))
	return PLUGIN_HANDLED
}

show_items(id, cat)
{
	new title[96], line[96], info[8]
	formatex(title, charsmax(title), "\y%s^n\wAmmo packs: \r%d", CAT_NAMES[cat], zp_get_user_ammo_packs(id))
	new menu = menu_create(title, "shop_menu_items")
	new packs = zp_get_user_ammo_packs(id)

	for (new i = 0; i < g_item_count; i++)
	{
		if (ArrayGetCell(g_item_cat, i) != cat)
			continue
		new name[64]
		ArrayGetString(g_item_name, i, name, charsmax(name))
		new cost = item_cost(i)
		formatex(line, charsmax(line), "%s %s%d AP", name, (packs >= cost) ? "\y" : "\r", cost)
		num_to_str(i, info, charsmax(info))
		menu_additem(menu, line, info)
	}
	menu_setprop(menu, MPROP_BACKNAME, "Назад")
	menu_setprop(menu, MPROP_NEXTNAME, "Далее")
	menu_setprop(menu, MPROP_EXITNAME, "Выход")
	menu_display(id, menu)
}

public shop_menu_items(id, menu, item)
{
	if (item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	new info[8], access, callback
	menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, callback)
	menu_destroy(menu)

	buy_item(id, str_to_num(info))
	return PLUGIN_HANDLED
}

// ---------------------------------------------------------------------------
// Покупка
// ---------------------------------------------------------------------------

buy_item(id, item)
{
	// состояние могло измениться, пока меню было открыто
	if (!can_use_shop(id, true) || item < 0 || item >= g_item_count)
		return
	if (ArrayGetCell(g_item_cat, item) == CAT_VIP && !is_vip(id))
	{
		client_print(id, print_chat, "[CSO] Этот предмет доступен только VIP")
		return
	}
	new wait = rounds_left(id, item)
	if (wait > 0)
	{
		client_print(id, print_chat, "[CSO] Снова доступно через %d раунд(а)", wait)
		return
	}

	new name[64], reason[64]
	ArrayGetString(g_item_name, item, name, charsmax(name))
	new cost = item_cost(item)
	new packs = zp_get_user_ammo_packs(id)

	if (packs < cost)
	{
		client_print(id, print_chat, "[CSO] Недостаточно ammo packs: нужно %d, есть %d", cost, packs)
		return
	}
	if (!can_receive(id, item, reason, charsmax(reason)))
	{
		client_print(id, print_chat, "[CSO] %s: %s", name, reason)
		return
	}

	if (ArrayGetCell(g_item_type, item) == TYPE_EXTERNAL)
	{
		zp_set_user_ammo_packs(id, packs - cost)
		new ret
		ExecuteForward(g_fw_bought, ret, id, item)
		if (ret >= PLUGIN_HANDLED)
		{
			// адаптер не смог выдать — возвращаем ровно списанное
			zp_set_user_ammo_packs(id, zp_get_user_ammo_packs(id) + cost)
			client_print(id, print_chat, "[CSO] %s: выдача не удалась, ammo packs возвращены", name)
			return
		}
	}
	else
	{
		if (!give_builtin(id, item))
		{
			client_print(id, print_chat, "[CSO] %s: выдача не удалась, ammo packs не списаны", name)
			log_amx("[CSO Shop] Не удалось выдать %s игроку #%d", name, id)
			return
		}
		zp_set_user_ammo_packs(id, packs - cost)
	}

	mark_taken(id, item)
	client_print(id, print_chat, "[CSO] Получено: %s за %d AP", name, cost)
}

bool:give_builtin(id, item)
{
	new b = ArrayGetCell(g_item_builtin, item)
	switch (B_TYPE[b])
	{
		case TYPE_ARMOR:
		{
			cs_set_user_armor(id, 100, CS_ARMOR_VESTHELM)
			return (get_user_armor(id) >= 100)
		}
		case TYPE_PRIMARY:   drop_slot(id, PRIMARY_BITSUM)
		case TYPE_SECONDARY: drop_slot(id, SECONDARY_BITSUM)
	}

	give_item(id, B_ENT[b])
	if (!user_has_weapon(id, B_CSW[b]))
		return false

	if (B_TYPE[b] != TYPE_GRENADE && MAXBPAMMO[B_CSW[b]] > 0)
		cs_set_user_bpammo(id, B_CSW[b], MAXBPAMMO[B_CSW[b]])
	return true
}

// Освобождаем слот: give_item не выдаст второе основное оружие
drop_slot(id, bitsum)
{
	new weapons[32], num, wname[32]
	get_user_weapons(id, weapons, num)
	for (new i = 0; i < num; i++)
	{
		if ((1 << weapons[i]) & bitsum)
		{
			get_weaponname(weapons[i], wname, charsmax(wname))
			engclient_cmd(id, "drop", wname)
		}
	}
}
