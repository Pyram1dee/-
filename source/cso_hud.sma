/*
 * CSO Zombie — HUD в стиле CSO Zombie (ТЗ §13)
 * Показывает: HP, броню, Ammo Packs, класс зомби (или «Человек/Выживший/Немезида»),
 * статус VIP/Gold, текущий режим, перезарядку способности.
 * Один синхронизированный HUD-канал, слева по центру экрана — не перекрывает
 * прицел, счёт, радар и стандартные HP/броню CS. Отключается в настройках (/menu → 9).
 *
 * API (library "cso_hud"):
 *   cso_hud_class(classid, const name[])      — имя класса ZP для показа (вызывают плагины классов)
 *   cso_hud_cooldown(id, Float:ready_time)    — момент готовности способности
 *   cso_hud_set_mode(const name[])            — переопределить название режима (Deimos Round); "" — сброс
 *   cso_hud_enabled(id), cso_hud_toggle(id)   — настройка игрока
 */

#include <amxmodx>
#include <fakemeta>
#include <nvault>
#include <zombieplague>

#define PLUGIN  "[CSO] HUD"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#pragma reqlib cso_priv
native cso_is_vip(id)
native cso_is_gold(id)

#define MAX_CLASSES 64
#define TASK_HUD 52400

new const MODE_NAMES[][] = { "Ожидание", "Заражение", "Немезида", "Выживший", "Рой", "Множественное заражение", "Чума" }

new g_class_names[MAX_CLASSES][32]
new Float:g_ready[33]
new bool:g_off[33]
new g_mode, g_mode_override[32]
new g_hud, g_vault
new g_pcv_enable, g_pcv_interval

public plugin_natives()
{
	register_library("cso_hud")
	register_native("cso_hud_class", "native_class")
	register_native("cso_hud_cooldown", "native_cooldown", 1)
	register_native("cso_hud_set_mode", "native_set_mode")
	register_native("cso_hud_enabled", "native_enabled", 1)
	register_native("cso_hud_toggle", "native_toggle", 1)
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)
	g_pcv_enable   = register_cvar("cso_hud_enable", "1")
	g_pcv_interval = register_cvar("cso_hud_interval", "1.0")
	g_hud = CreateHudSyncObj()
	g_vault = nvault_open("cso_hud")
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
	set_task(1.0, "task_hud", TASK_HUD)
}

public plugin_end()
{
	if (g_vault != INVALID_HANDLE)
		nvault_close(g_vault)
}

// --- natives -----------------------------------------------------------------

public native_class(plugin, params)
{
	new classid = get_param(1)
	if (0 <= classid < MAX_CLASSES)
		get_string(2, g_class_names[classid], charsmax(g_class_names[]))
}

public native_cooldown(id, Float:ready)
{
	if (1 <= id <= 32)
		g_ready[id] = ready
}

public native_set_mode(plugin, params)
{
	get_string(1, g_mode_override, charsmax(g_mode_override))
}

public bool:native_enabled(id)
{
	return (1 <= id <= 32) && !g_off[id]
}

public bool:native_toggle(id)
{
	if (!(1 <= id <= 32))
		return false
	g_off[id] = !g_off[id]
	save_setting(id)
	if (g_off[id])
		ClearSyncHud(id, g_hud)
	return !g_off[id]
}

// --- состояние ---------------------------------------------------------------

public zp_round_started(gamemode, id)
{
	g_mode = gamemode
}

public zp_round_ended(winteam)
{
	g_mode_override[0] = 0
}

public ev_new_round()
{
	g_mode = 0
	g_mode_override[0] = 0
	arrayset(_:g_ready, 0, sizeof g_ready)
}

public client_authorized(id)
{
	g_off[id] = false
	if (g_vault == INVALID_HANDLE || is_user_bot(id))
		return
	new key[40], val[4], ts
	get_user_authid(id, key, charsmax(key))
	if (nvault_lookup(g_vault, key, val, charsmax(val), ts))
		g_off[id] = (val[0] == '0')
}

save_setting(id)
{
	if (g_vault == INVALID_HANDLE || is_user_bot(id))
		return
	new key[40]
	get_user_authid(id, key, charsmax(key))
	nvault_set(g_vault, key, g_off[id] ? "0" : "1")
}

public client_disconnected(id)
{
	g_ready[id] = 0.0
}

// --- отрисовка ---------------------------------------------------------------

public task_hud()
{
	new Float:interval = floatclamp(get_pcvar_float(g_pcv_interval), 0.2, 5.0)
	set_task(interval, "task_hud", TASK_HUD)
	if (!get_pcvar_num(g_pcv_enable))
		return

	new mode[40]
	if (g_mode_override[0])
		copy(mode, charsmax(mode), g_mode_override)
	else
		copy(mode, charsmax(mode), MODE_NAMES[(0 <= g_mode < sizeof MODE_NAMES) ? g_mode : 0])

	for (new id = 1; id <= 32; id++)
	{
		if (!is_user_alive(id) || g_off[id] || is_user_bot(id))
			continue
		show_player_hud(id, mode, interval)
	}
}

show_player_hud(id, const mode[], Float:interval)
{
	new Float:hp, Float:armor
	pev(id, pev_health, hp)
	pev(id, pev_armorvalue, armor)

	new role[48], status[16], skill[32]
	get_role(id, role, charsmax(role))

	new bool:vip = bool:cso_is_vip(id), bool:gold = bool:cso_is_gold(id)
	if (vip && gold)
		copy(status, charsmax(status), "Gold + VIP")
	else if (gold)
		copy(status, charsmax(status), "Gold")
	else if (vip)
		copy(status, charsmax(status), "VIP")
	else
		copy(status, charsmax(status), "—")

	skill[0] = 0
	if (zp_get_user_zombie(id) && g_ready[id] > 0.0)
	{
		new Float:left = g_ready[id] - get_gametime()
		if (left > 0.0)
			formatex(skill, charsmax(skill), "^nСпособность: %.0f с", left)
		else
			copy(skill, charsmax(skill), "^nСпособность: готова")
	}

	if (zp_get_user_zombie(id))
		set_hudmessage(255, 80, 60, 0.02, 0.55, 0, 0.0, interval + 0.1, 0.0, 0.0, -1)
	else
		set_hudmessage(120, 200, 255, 0.02, 0.55, 0, 0.0, interval + 0.1, 0.0, 0.0, -1)

	ShowSyncHudMsg(id, g_hud, "HP: %d   Броня: %d   AP: %d^n%s^nСтатус: %s^nРежим: %s%s",
		floatround(hp), floatround(armor), zp_get_user_ammo_packs(id), role, status, mode, skill)
}

get_role(id, out[], len)
{
	if (!zp_get_user_zombie(id))
	{
		copy(out, len, zp_get_user_survivor(id) ? "Выживший" : "Человек")
		return
	}
	if (zp_get_user_nemesis(id))
	{
		copy(out, len, g_mode_override[0] ? "Deimos" : "Немезида")
		return
	}
	new cls = zp_get_user_zombie_class(id)
	if (0 <= cls < MAX_CLASSES && g_class_names[cls][0])
		formatex(out, len, "Класс: %s", g_class_names[cls])
	else
	{
		new info[32]
		zp_get_zombie_class_info(cls, info, charsmax(info))
		formatex(out, len, "Класс: %s", info[0] ? info : "Зомби")
	}
}
