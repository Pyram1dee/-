/*
 * CSO Zombie — привилегии VIP и Gold, VIP меню и Gold меню (ТЗ §7, §8)
 *
 * Права — штатные флаги AMXX (users.ini), независимые:
 *   cso_vip_flag  "t"  (ADMIN_LEVEL_H)
 *   cso_gold_flag "s"  (ADMIN_LEVEL_G)
 * Игрок может иметь обе привилегии; бонусы при этом не суммируются — действует
 * старшая (cso_priv_tier: Gold > VIP), см. cso_priv_bonus_tier().
 *
 * VIP меню (/vip, /vipmenu): VIP оружие (предметы категории VIP магазина: Jetpack + Bazooka),
 *   VIP бонусы, Информация о VIP. VIP Hammer здесь НЕТ — он в меню ножей.
 * Gold меню (/gold): Gold оружие, Gold бонусы, Эксклюзивные модели, Информация о Gold.
 * Ассортимент Gold оружия и размеры бонусов VIP/Gold — на согласовании: пункты честно
 * показывают «на согласовании», ничего не выдают.
 *
 * API (library "cso_priv"): cso_is_vip(id), cso_is_gold(id), cso_priv_bonus_tier(id)
 */

#include <amxmodx>

#define PLUGIN  "[CSO] VIP & Gold"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

enum
{
	TIER_NONE = 0,
	TIER_VIP,
	TIER_GOLD
}

new g_pcv_vip_flag, g_pcv_gold_flag

public plugin_natives()
{
	register_library("cso_priv")
	register_native("cso_is_vip", "native_is_vip", 1)
	register_native("cso_is_gold", "native_is_gold", 1)
	register_native("cso_priv_bonus_tier", "native_bonus_tier", 1)
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_vip_flag  = register_cvar("cso_vip_flag", "t")
	g_pcv_gold_flag = register_cvar("cso_gold_flag", "s")

	register_clcmd("say /vip", "cmd_vip")
	register_clcmd("say_team /vip", "cmd_vip")
	register_clcmd("say /vipmenu", "cmd_vip")
	register_clcmd("say /vm", "cmd_vip")
	register_clcmd("cso_vip", "cmd_vip")
	register_clcmd("say /gold", "cmd_gold")
	register_clcmd("say_team /gold", "cmd_gold")
	register_clcmd("cso_gold", "cmd_gold")
}

bool:has_flag(id, pcvar)
{
	if (!is_user_connected(id))
		return false
	new flags[24]
	get_pcvar_string(pcvar, flags, charsmax(flags))
	new need = read_flags(flags)
	return (need != 0 && (get_user_flags(id) & need) == need)
}

public bool:native_is_vip(id)  { return has_flag(id, g_pcv_vip_flag); }
public bool:native_is_gold(id) { return has_flag(id, g_pcv_gold_flag); }

// Уровень для начисления бонусов: одна старшая привилегия, без суммирования
public native_bonus_tier(id)
{
	if (has_flag(id, g_pcv_gold_flag))
		return TIER_GOLD
	if (has_flag(id, g_pcv_vip_flag))
		return TIER_VIP
	return TIER_NONE
}

// ---------------------------------------------------------------------------
// VIP меню
// ---------------------------------------------------------------------------

public cmd_vip(id)
{
	if (!has_flag(id, g_pcv_vip_flag))
	{
		client_print(id, print_chat, "[CSO] VIP меню доступно только VIP")
		return PLUGIN_HANDLED
	}
	new menu = menu_create("\yVIP меню", "vip_menu_handler")
	menu_additem(menu, "VIP оружие", "1")
	menu_additem(menu, "VIP бонусы", "2")
	menu_additem(menu, "Информация о VIP", "3")
	menu_setprop(menu, MPROP_EXITNAME, "Выход")
	menu_display(id, menu)
	return PLUGIN_HANDLED
}

public vip_menu_handler(id, menu, item)
{
	menu_destroy(menu)
	if (item == MENU_EXIT || !has_flag(id, g_pcv_vip_flag))
		return PLUGIN_HANDLED
	switch (item)
	{
		case 0: amxclient_cmd(id, "cso_vipweapons") // предметы категории VIP в Human Shop
		case 1: client_print(id, print_chat, "[CSO] VIP бонусы: размеры на согласовании, сейчас не начисляются")
		case 2: show_info(id, false)
	}
	return PLUGIN_HANDLED
}

// ---------------------------------------------------------------------------
// Gold меню
// ---------------------------------------------------------------------------

public cmd_gold(id)
{
	if (!has_flag(id, g_pcv_gold_flag))
	{
		client_print(id, print_chat, "[CSO] Gold меню доступно только Gold")
		return PLUGIN_HANDLED
	}
	new menu = menu_create("\yGold меню", "gold_menu_handler")
	menu_additem(menu, "Gold оружие", "1")
	menu_additem(menu, "Gold бонусы", "2")
	menu_additem(menu, "Эксклюзивные модели", "3")
	menu_additem(menu, "Информация о Gold", "4")
	menu_setprop(menu, MPROP_EXITNAME, "Выход")
	menu_display(id, menu)
	return PLUGIN_HANDLED
}

public gold_menu_handler(id, menu, item)
{
	menu_destroy(menu)
	if (item == MENU_EXIT || !has_flag(id, g_pcv_gold_flag))
		return PLUGIN_HANDLED
	switch (item)
	{
		case 0: client_print(id, print_chat, "[CSO] Gold оружие: ассортимент на согласовании")
		case 1: client_print(id, print_chat, "[CSO] Gold бонусы: размеры на согласовании, сейчас не начисляются")
		case 2: amxclient_cmd(id, "cso_models_gold") // модели с пометкой gold в cso_player_models.ini
		case 3: show_info(id, true)
	}
	return PLUGIN_HANDLED
}

show_info(id, bool:gold)
{
	new flags[24], motd[1024], len
	get_pcvar_string(gold ? g_pcv_gold_flag : g_pcv_vip_flag, flags, charsmax(flags))
	len = formatex(motd, charsmax(motd), "<html><body style='background:#111;color:#ddd;font-family:Tahoma'><h3>%s</h3>", gold ? "Gold" : "VIP")
	if (gold)
		len += formatex(motd[len], charsmax(motd) - len, "<p>Gold — отдельная привилегия (флаг <b>%s</b>), независимая от VIP.</p><p>Меню: /gold. Эксклюзивные модели персонажа — пункт 3.</p><p>Gold оружие и бонусы — на согласовании.</p>", flags)
	else
		len += formatex(motd[len], charsmax(motd) - len, "<p>VIP — флаг <b>%s</b>.</p><p>VIP Hammer выбирается в меню ножей (третий этап меню оружия).</p><p>VIP оружие: Jetpack + Bazooka (не чаще раза в несколько раундов).</p><p>Бонусы — на согласовании.</p>", flags)
	len += formatex(motd[len], charsmax(motd) - len, "<p>При обеих привилегиях бонусы не суммируются: действует Gold.</p></body></html>")
	show_motd(id, motd, gold ? "Информация о Gold" : "Информация о VIP")
}
