/*
 * CSO Zombie — меню выбора оружия (ТЗ §3)
 * После появления человека: Основное оружие → Пистолеты → Ножи, строго по порядку;
 * каждый следующий этап открывается сразу после выбора предыдущего.
 *  - стандартные модели и механика CS 1.6; кастомного CSO-оружия нет;
 *  - VIP Hammer — четвёртый пункт меню ножей: видят все, выбрать может только VIP;
 *  - запоминание набора (по SteamID), «повторить прошлый набор», «всегда повторять»,
 *    отключение автооткрытия; после возрождения набор восстанавливается;
 *  - выдача только живому человеку (не выжившему); одна выдача каждого этапа за жизнь;
 *    при заражении/смене режима открытое меню перестаёт действовать (проверка в момент выбора).
 * Встроенные меню покупки ZP отключаются в cso_custom.cfg (zp_buy_custom 0): в них нет этапа ножей.
 *
 * Команды: /guns, cso_guns. API (library "cso_guns"): cso_guns_setting(id, s), cso_guns_toggle(id, s),
 * cso_guns_kit_text(id, out[], len). s: 0 — автооткрытие, 1 — всегда повторять набор.
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <fun>
#include <cstrike>
#include <nvault>
#include <zombieplague>

#define PLUGIN  "[CSO] Weapons Menu"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#pragma reqlib cso_knives
native cso_knives_set(id, knife)
native cso_knives_name(knife, out[], len)
native cso_knives_vip_only(knife)
#pragma reqlib cso_priv
native cso_is_vip(id)

#define MAXP 32
#define TASK_SPAWN 52500
#define KNIFE_COUNT 4

enum { STAGE_PRIMARY = 0, STAGE_PISTOL, STAGE_KNIFE, STAGE_DONE }
enum { SET_AUTO = 0, SET_REPEAT }

new const PRIMARY_NAMES[][] = { "AK-47", "M4A1", "AUG", "SG552", "FAMAS", "Galil", "MP5", "P90", "XM1014", "M3", "M249", "AWP" }
new const PRIMARY_ENTS[][]  = { "weapon_ak47", "weapon_m4a1", "weapon_aug", "weapon_sg552", "weapon_famas", "weapon_galil", "weapon_mp5navy", "weapon_p90", "weapon_xm1014", "weapon_m3", "weapon_m249", "weapon_awp" }
new const PRIMARY_CSW[]     = { CSW_AK47, CSW_M4A1, CSW_AUG, CSW_SG552, CSW_FAMAS, CSW_GALIL, CSW_MP5NAVY, CSW_P90, CSW_XM1014, CSW_M3, CSW_M249, CSW_AWP }

new const PISTOL_NAMES[][] = { "Desert Eagle", "USP", "Glock 18", "Five-SeveN", "P228", "Dual Elites" }
new const PISTOL_ENTS[][]  = { "weapon_deagle", "weapon_usp", "weapon_glock18", "weapon_fiveseven", "weapon_p228", "weapon_elite" }
new const PISTOL_CSW[]     = { CSW_DEAGLE, CSW_USP, CSW_GLOCK18, CSW_FIVESEVEN, CSW_P228, CSW_ELITE }

const PRIMARY_BITSUM = (1<<CSW_SCOUT)|(1<<CSW_XM1014)|(1<<CSW_MAC10)|(1<<CSW_AUG)|(1<<CSW_UMP45)|(1<<CSW_SG550)|(1<<CSW_GALIL)|(1<<CSW_FAMAS)|(1<<CSW_AWP)|(1<<CSW_MP5NAVY)|(1<<CSW_M249)|(1<<CSW_M3)|(1<<CSW_M4A1)|(1<<CSW_TMP)|(1<<CSW_G3SG1)|(1<<CSW_SG552)|(1<<CSW_AK47)|(1<<CSW_P90)
const PISTOL_BITSUM = (1<<CSW_P228)|(1<<CSW_ELITE)|(1<<CSW_FIVESEVEN)|(1<<CSW_USP)|(1<<CSW_GLOCK18)|(1<<CSW_DEAGLE)

// Полный боезапас (таблица из ZP 4.3)
new const MAXBPAMMO[] = { -1, 52, -1, 90, 1, 32, 1, 100, 90, 1, 120, 100, 100, 90, 90, 90, 100, 120, 30, 120, 200, 32, 90, 120, 90, 2, 35, 90, 90, -1, 100 }

new g_stage[MAXP + 1]          // текущий этап в этой жизни
new g_kit[MAXP + 1][3]         // запомненный набор: основное, пистолет, нож (-1 — нет)
new bool:g_set[MAXP + 1][2]    // настройки
new g_vault
new g_pcv_enable, g_pcv_delay
new g_knife_cb

public plugin_natives()
{
	register_library("cso_guns")
	register_native("cso_guns_setting", "native_setting", 1)
	register_native("cso_guns_toggle", "native_toggle", 1)
	register_native("cso_guns_kit_text", "native_kit_text")
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_enable = register_cvar("cso_guns_enable", "1")
	g_pcv_delay  = register_cvar("cso_guns_spawn_delay", "0.3") // после спавна: ядро ZP успевает выставить человека

	register_clcmd("say /guns", "cmd_guns")
	register_clcmd("say_team /guns", "cmd_guns")
	register_clcmd("cso_guns", "cmd_guns")

	RegisterHam(Ham_Spawn, "player", "fw_Spawn_Post", 1)
	g_knife_cb = menu_makecallback("knife_item_cb")
	g_vault = nvault_open("cso_guns")
}

public plugin_end()
{
	if (g_vault != INVALID_HANDLE)
		nvault_close(g_vault)
}

// --- сохранение ------------------------------------------------------------------

public client_authorized(id)
{
	g_kit[id][0] = -1
	g_kit[id][1] = -1
	g_kit[id][2] = -1
	g_set[id][SET_AUTO] = true
	g_set[id][SET_REPEAT] = false
	g_stage[id] = STAGE_DONE

	if (g_vault == INVALID_HANDLE || is_user_bot(id))
		return
	new key[40], val[32], ts
	get_user_authid(id, key, charsmax(key))
	if (!nvault_lookup(g_vault, key, val, charsmax(val), ts))
		return
	new a[4][6]
	parse(val, a[0], 5, a[1], 5, a[2], 5, a[3], 5)
	g_kit[id][0] = clamp(str_to_num(a[0]), -1, sizeof PRIMARY_NAMES - 1)
	g_kit[id][1] = clamp(str_to_num(a[1]), -1, sizeof PISTOL_NAMES - 1)
	g_kit[id][2] = clamp(str_to_num(a[2]), -1, KNIFE_COUNT - 1)
	new flags = str_to_num(a[3])
	g_set[id][SET_AUTO] = !(flags & 1)
	g_set[id][SET_REPEAT] = !!(flags & 2)
}

save_player(id)
{
	if (g_vault == INVALID_HANDLE || is_user_bot(id))
		return
	new key[40], val[32]
	get_user_authid(id, key, charsmax(key))
	formatex(val, charsmax(val), "%d %d %d %d", g_kit[id][0], g_kit[id][1], g_kit[id][2],
		(g_set[id][SET_AUTO] ? 0 : 1) | (g_set[id][SET_REPEAT] ? 2 : 0))
	nvault_set(g_vault, key, val)
}

// --- natives ---------------------------------------------------------------------

public bool:native_setting(id, s)
{
	return (1 <= id <= MAXP && 0 <= s <= 1) ? g_set[id][s] : false
}

public bool:native_toggle(id, s)
{
	if (!(1 <= id <= MAXP) || !(0 <= s <= 1))
		return false
	g_set[id][s] = !g_set[id][s]
	save_player(id)
	return g_set[id][s]
}

public native_kit_text(plugin, params)
{
	new id = get_param(1)
	new out[96]
	if (!(1 <= id <= MAXP) || g_kit[id][0] < 0)
		copy(out, charsmax(out), "не выбран")
	else
	{
		new kname[32]
		if (g_kit[id][2] >= 0)
			cso_knives_name(g_kit[id][2], kname, charsmax(kname))
		else
			copy(kname, charsmax(kname), "—")
		formatex(out, charsmax(out), "%s / %s / %s", PRIMARY_NAMES[g_kit[id][0]],
			g_kit[id][1] >= 0 ? PISTOL_NAMES[g_kit[id][1]] : "—", kname)
	}
	set_string(2, out, get_param(3))
}

// --- запуск ----------------------------------------------------------------------

bool:can_get(id)
{
	return get_pcvar_num(g_pcv_enable) && is_user_alive(id) && !zp_get_user_zombie(id) && !zp_get_user_survivor(id)
}

public fw_Spawn_Post(id)
{
	if (!(1 <= id <= MAXP))
		return
	g_stage[id] = STAGE_DONE
	remove_task(id + TASK_SPAWN)
	if (is_user_alive(id))
		set_task(floatclamp(get_pcvar_float(g_pcv_delay), 0.1, 3.0), "task_after_spawn", id + TASK_SPAWN)
}

public zp_user_humanized_post(id, survivor)
{
	// антидот: снова человек — новая «жизнь» человека
	if (!survivor)
	{
		remove_task(id + TASK_SPAWN)
		set_task(0.2, "task_after_spawn", id + TASK_SPAWN)
	}
}

public zp_user_infected_post(id, infector, nemesis)
{
	g_stage[id] = STAGE_DONE
	remove_task(id + TASK_SPAWN)
	show_menu(id, 0, "^n", 1) // закрыть открытое меню
}

public task_after_spawn(taskid)
{
	new id = taskid - TASK_SPAWN
	if (!can_get(id))
		return
	g_stage[id] = STAGE_PRIMARY

	if (g_set[id][SET_REPEAT] && g_kit[id][0] >= 0)
	{
		give_kit(id)
		return
	}
	if (g_set[id][SET_AUTO])
		open_current(id)
}

public cmd_guns(id)
{
	if (!can_get(id))
	{
		client_print(id, print_chat, "[CSO] Меню оружия доступно живому человеку")
		return PLUGIN_HANDLED
	}
	if (g_stage[id] == STAGE_DONE)
	{
		client_print(id, print_chat, "[CSO] Оружие в этой жизни уже выбрано")
		return PLUGIN_HANDLED
	}
	open_current(id)
	return PLUGIN_HANDLED
}

open_current(id)
{
	switch (g_stage[id])
	{
		case STAGE_PRIMARY:
		{
			if (g_kit[id][0] >= 0)
				show_start_menu(id)
			else
				show_primary(id)
		}
		case STAGE_PISTOL: show_pistols(id)
		case STAGE_KNIFE:  show_knives(id)
	}
}

// --- меню ------------------------------------------------------------------------

show_start_menu(id)
{
	new kit[96], title[160]
	native_kit_text_local(id, kit, charsmax(kit))
	formatex(title, charsmax(title), "\yМеню оружия^n\wПрошлый набор: \r%s", kit)
	new menu = menu_create(title, "start_handler")
	menu_additem(menu, "Новый выбор", "0")
	menu_additem(menu, "Повторить прошлый набор", "1")
	menu_additem(menu, g_set[id][SET_REPEAT] ? "Всегда повторять: \yвкл" : "Всегда повторять: \rвыкл", "2")
	menu_additem(menu, g_set[id][SET_AUTO] ? "Открывать автоматически: \yвкл" : "Открывать автоматически: \rвыкл", "3")
	menu_setprop(menu, MPROP_EXITNAME, "Выход")
	menu_display(id, menu)
}

native_kit_text_local(id, out[], len)
{
	if (g_kit[id][0] < 0)
	{
		copy(out, len, "не выбран")
		return
	}
	new kname[32]
	if (g_kit[id][2] >= 0)
		cso_knives_name(g_kit[id][2], kname, charsmax(kname))
	else
		copy(kname, charsmax(kname), "—")
	formatex(out, len, "%s / %s / %s", PRIMARY_NAMES[g_kit[id][0]], g_kit[id][1] >= 0 ? PISTOL_NAMES[g_kit[id][1]] : "—", kname)
}

public start_handler(id, menu, item)
{
	menu_destroy(menu)
	if (item == MENU_EXIT || !can_get(id) || g_stage[id] != STAGE_PRIMARY)
		return PLUGIN_HANDLED
	switch (item)
	{
		case 0: show_primary(id)
		case 1: give_kit(id)
		case 2: { native_toggle(id, SET_REPEAT); show_start_menu(id); }
		case 3: { native_toggle(id, SET_AUTO); show_start_menu(id); }
	}
	return PLUGIN_HANDLED
}

show_primary(id)
{
	new menu = menu_create("\yЭтап 1: Основное оружие", "primary_handler")
	new info[4]
	for (new i = 0; i < sizeof PRIMARY_NAMES; i++)
	{
		num_to_str(i, info, charsmax(info))
		menu_additem(menu, PRIMARY_NAMES[i], info)
	}
	menu_setprop(menu, MPROP_BACKNAME, "Назад")
	menu_setprop(menu, MPROP_NEXTNAME, "Далее")
	menu_setprop(menu, MPROP_EXITNAME, "Выход")
	menu_display(id, menu)
}

public primary_handler(id, menu, item)
{
	new info[4], access, cb
	if (item != MENU_EXIT)
		menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, cb)
	menu_destroy(menu)
	if (item == MENU_EXIT || !can_get(id) || g_stage[id] != STAGE_PRIMARY)
		return PLUGIN_HANDLED

	new i = str_to_num(info)
	if (!give_primary(id, i))
		return PLUGIN_HANDLED
	g_kit[id][0] = i
	g_stage[id] = STAGE_PISTOL
	save_player(id)
	show_pistols(id) // сразу следующий этап
	return PLUGIN_HANDLED
}

show_pistols(id)
{
	new menu = menu_create("\yЭтап 2: Пистолеты", "pistol_handler")
	new info[4]
	for (new i = 0; i < sizeof PISTOL_NAMES; i++)
	{
		num_to_str(i, info, charsmax(info))
		menu_additem(menu, PISTOL_NAMES[i], info)
	}
	menu_setprop(menu, MPROP_EXITNAME, "Выход")
	menu_display(id, menu)
}

public pistol_handler(id, menu, item)
{
	new info[4], access, cb
	if (item != MENU_EXIT)
		menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, cb)
	menu_destroy(menu)
	if (item == MENU_EXIT || !can_get(id) || g_stage[id] != STAGE_PISTOL)
		return PLUGIN_HANDLED

	new i = str_to_num(info)
	if (!give_pistol(id, i))
		return PLUGIN_HANDLED
	g_kit[id][1] = i
	g_stage[id] = STAGE_KNIFE
	save_player(id)
	show_knives(id) // после пистолета автоматически — ножи
	return PLUGIN_HANDLED
}

show_knives(id)
{
	new menu = menu_create("\yЭтап 3: Ножи", "knife_handler")
	new info[4], name[48]
	for (new k = 0; k < KNIFE_COUNT; k++)
	{
		cso_knives_name(k, name, charsmax(name))
		if (cso_knives_vip_only(k) && !cso_is_vip(id))
			add(name, charsmax(name), " \r(только VIP)")
		num_to_str(k, info, charsmax(info))
		menu_additem(menu, name, info, 0, g_knife_cb)
	}
	menu_setprop(menu, MPROP_EXITNAME, "Выход")
	menu_display(id, menu)
}

// VIP Hammer виден всем, но выбрать его может только VIP
public knife_item_cb(id, menu, item)
{
	new info[4], access, cb
	menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, cb)
	new k = str_to_num(info)
	return (cso_knives_vip_only(k) && !cso_is_vip(id)) ? ITEM_DISABLED : ITEM_ENABLED
}

public knife_handler(id, menu, item)
{
	new info[4], access, cb
	if (item != MENU_EXIT)
		menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, cb)
	menu_destroy(menu)
	if (item == MENU_EXIT || !can_get(id) || g_stage[id] != STAGE_KNIFE)
		return PLUGIN_HANDLED

	new k = str_to_num(info)
	if (!cso_knives_set(id, k))
	{
		client_print(id, print_chat, "[CSO] Этот нож сейчас недоступен")
		show_knives(id)
		return PLUGIN_HANDLED
	}
	g_kit[id][2] = k
	g_stage[id] = STAGE_DONE
	save_player(id)
	return PLUGIN_HANDLED
}

// --- выдача ----------------------------------------------------------------------

give_kit(id)
{
	if (g_kit[id][0] >= 0 && give_primary(id, g_kit[id][0]))
		g_stage[id] = STAGE_PISTOL
	else
	{
		show_primary(id)
		return
	}
	if (g_kit[id][1] >= 0 && give_pistol(id, g_kit[id][1]))
		g_stage[id] = STAGE_KNIFE
	else
	{
		show_pistols(id)
		return
	}
	// нож: Hammer мог стать недоступен (сняли VIP) — тогда спросить заново
	if (g_kit[id][2] >= 0 && cso_knives_set(id, g_kit[id][2]))
	{
		g_stage[id] = STAGE_DONE
		client_print(id, print_chat, "[CSO] Выдан прошлый набор. /guns — недоступно до следующей жизни")
	}
	else
		show_knives(id)
}

bool:give_primary(id, i)
{
	if (!(0 <= i < sizeof PRIMARY_NAMES))
		return false
	strip_slot(id, PRIMARY_BITSUM)
	return give_weapon(id, PRIMARY_ENTS[i], PRIMARY_CSW[i])
}

bool:give_pistol(id, i)
{
	if (!(0 <= i < sizeof PISTOL_NAMES))
		return false
	strip_slot(id, PISTOL_BITSUM)
	return give_weapon(id, PISTOL_ENTS[i], PISTOL_CSW[i])
}

bool:give_weapon(id, const ent[], csw)
{
	give_item(id, ent)
	if (!user_has_weapon(id, csw))
	{
		log_amx("[CSO] Не удалось выдать %s игроку #%d", ent, id)
		return false
	}
	if (MAXBPAMMO[csw] > 0)
		cs_set_user_bpammo(id, csw, MAXBPAMMO[csw])
	return true
}

// Убирает оружие слота у игрока (без выброса на пол, чтобы не плодить сущности)
strip_slot(id, bitsum)
{
	new weapons[32], num, wname[32]
	get_user_weapons(id, weapons, num)
	for (new i = 0; i < num; i++)
	{
		if (!((1 << weapons[i]) & bitsum))
			continue
		get_weaponname(weapons[i], wname, charsmax(wname))
		ham_strip_weapon(id, wname)
	}
}

ham_strip_weapon(id, const weapon[])
{
	new wid = get_weaponid(weapon)
	if (!wid)
		return
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", weapon)) > 0)
		if (pev(ent, pev_owner) == id)
			break
	if (ent <= 0)
		return
	if (get_user_weapon(id) == wid)
		ExecuteHamB(Ham_Weapon_RetireWeapon, ent)
	if (!ExecuteHamB(Ham_RemovePlayerItem, id, ent))
		return
	ExecuteHamB(Ham_Item_Kill, ent)
	set_pev(id, pev_weapons, pev(id, pev_weapons) & ~(1 << wid))
}

public client_disconnected(id)
{
	remove_task(id + TASK_SPAWN)
	save_player(id)
}
