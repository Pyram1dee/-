/*
 * CSO Zombie — главное меню (ТЗ §2) и защита ammo packs (§12)
 * /menu (также кнопка M по бинду cso_menu):
 *   1. Меню оружия            → cso_guns (только живой человек, пока выбор не завершён)
 *   2. Магазин людей          → cso_shop
 *   3. Магазин зомби          → стандартный магазин ZP (Game Menu ZP, пункт 2 — extra items)
 *   4. Выбор класса зомби     → стандартное меню классов ZP (Game Menu ZP, пункт 3)
 *   5. VIP меню               → cso_vip
 *   6. Gold меню              → cso_gold
 *   7. Выбор модели персонажа → cso_models
 *   8. Личный кабинет
 *   9. Настройки: автооткрытие меню оружия, всегда повторять набор, HUD
 * Недоступные пункты показываются серыми (состояние игрока и права).
 * Ammo packs: встроенное сохранение ZP (zp_ammo_save*); здесь — только ограничение значения
 * в диапазоне 0..zp_ammo_save_limit во время игры (защита от некорректных значений).
 */

#include <amxmodx>
#include <zombieplague>

#define PLUGIN  "[CSO] Main Menu"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#pragma reqlib cso_priv
native cso_is_vip(id)
native cso_is_gold(id)
#pragma reqlib cso_guns
native cso_guns_setting(id, s)
native cso_guns_toggle(id, s)
native cso_guns_kit_text(id, out[], len)
#pragma reqlib cso_hud
native cso_hud_enabled(id)
native cso_hud_toggle(id)
#pragma reqlib cso_models
native cso_models_current(id, out[], len)

#define TASK_ZPMENU 52700

new g_pcv_ap_limit
new g_zp_key[33]

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	register_clcmd("say /menu", "cmd_menu")
	register_clcmd("say_team /menu", "cmd_menu")
	register_clcmd("cso_menu", "cmd_menu")

	register_menucmd(register_menuid("CSO Main Menu"), 1023, "main_handler")
	register_menucmd(register_menuid("CSO Settings"), 1023, "settings_handler")

	set_task(1.0, "task_ap_guard", _, _, _, "b")
}

public plugin_cfg()
{
	g_pcv_ap_limit = get_cvar_pointer("zp_ammo_save_limit")
}

// --- главное меню --------------------------------------------------------------

public cmd_menu(id)
{
	show_main(id)
	return PLUGIN_HANDLED
}

bool:is_human(id)  { return is_user_alive(id) && !zp_get_user_zombie(id); }

show_main(id)
{
	new m[1024], len, keys = (1 << 9)
	new bool:alive = bool:is_user_alive(id)
	len = formatex(m, charsmax(m), "\yCSO Zombie — главное меню^n\wAmmo packs: \r%d^n^n", zp_get_user_ammo_packs(id))

	len += item(m, len, charsmax(m), keys, 1, "Меню оружия", is_human(id) && !zp_get_user_survivor(id))
	len += item(m, len, charsmax(m), keys, 2, "Магазин людей", is_human(id))
	len += item(m, len, charsmax(m), keys, 3, "Магазин зомби", alive)
	len += item(m, len, charsmax(m), keys, 4, "Выбор класса зомби", true)
	len += item(m, len, charsmax(m), keys, 5, "VIP меню", bool:cso_is_vip(id))
	len += item(m, len, charsmax(m), keys, 6, "Gold меню", bool:cso_is_gold(id))
	len += item(m, len, charsmax(m), keys, 7, "Выбор модели персонажа", true)
	len += item(m, len, charsmax(m), keys, 8, "Личный кабинет", true)
	len += item(m, len, charsmax(m), keys, 9, "Настройки", true)
	len += formatex(m[len], charsmax(m) - len, "^n\r0.\w Выход")
	show_menu(id, keys, m, -1, "CSO Main Menu")
}

item(m[], len, maxlen, &keys, n, const text[], bool:enabled)
{
	if (enabled)
	{
		keys |= (1 << (n - 1))
		return formatex(m[len], maxlen - len, "\r%d.\w %s^n", n, text)
	}
	return formatex(m[len], maxlen - len, "\d%d. %s^n", n, text)
}

public main_handler(id, key)
{
	switch (key)
	{
		case 0: amxclient_cmd(id, "cso_guns")
		case 1: amxclient_cmd(id, "cso_shop")
		case 2: open_zp_menu(id, 2) // extra items ZP
		case 3: open_zp_menu(id, 3) // классы зомби ZP
		case 4: amxclient_cmd(id, "cso_vip")
		case 5: amxclient_cmd(id, "cso_gold")
		case 6: amxclient_cmd(id, "cso_models")
		case 7: show_cabinet(id)
		case 8: show_settings(id)
	}
	return PLUGIN_HANDLED
}

// Стандартные меню ZP открываются через его Game Menu (/zpmenu) и выбор пункта —
// у ZP 4.3 нет отдельных команд для магазина зомби и классов; функции ZP не дублируются.
open_zp_menu(id, zp_key)
{
	amxclient_cmd(id, "say", "/zpmenu")
	g_zp_key[id] = zp_key
	set_task(0.1, "task_zp_select", id + TASK_ZPMENU)
}

public task_zp_select(taskid)
{
	new id = taskid - TASK_ZPMENU
	if (!is_user_connected(id))
		return
	new k[4]
	num_to_str(g_zp_key[id], k, charsmax(k))
	amxclient_cmd(id, "menuselect", k)
}

// --- личный кабинет --------------------------------------------------------------

show_cabinet(id)
{
	new name[32], auth[40], kit[96], model[32], status[24], motd[1536], len
	get_user_name(id, name, charsmax(name))
	get_user_authid(id, auth, charsmax(auth))
	cso_guns_kit_text(id, kit, charsmax(kit))
	cso_models_current(id, model, charsmax(model))
	new bool:vip = bool:cso_is_vip(id), bool:gold = bool:cso_is_gold(id)
	copy(status, charsmax(status), (vip && gold) ? "Gold + VIP" : (gold ? "Gold" : (vip ? "VIP" : "нет")))

	len = formatex(motd, charsmax(motd), "<html><body style='background:#111;color:#ddd;font-family:Tahoma'><h3>Личный кабинет</h3><table cellpadding=4>")
	len += formatex(motd[len], charsmax(motd) - len, "<tr><td>Игрок</td><td><b>%s</b></td></tr><tr><td>SteamID</td><td>%s</td></tr>", name, auth)
	len += formatex(motd[len], charsmax(motd) - len, "<tr><td>Ammo packs</td><td><b>%d</b></td></tr><tr><td>Привилегия</td><td>%s</td></tr>", zp_get_user_ammo_packs(id), status)
	len += formatex(motd[len], charsmax(motd) - len, "<tr><td>Набор оружия</td><td>%s</td></tr><tr><td>Модель</td><td>%s</td></tr>", kit, model)
	len += formatex(motd[len], charsmax(motd) - len, "<tr><td>Автооткрытие меню оружия</td><td>%s</td></tr>", cso_guns_setting(id, 0) ? "вкл" : "выкл")
	len += formatex(motd[len], charsmax(motd) - len, "<tr><td>Всегда повторять набор</td><td>%s</td></tr>", cso_guns_setting(id, 1) ? "вкл" : "выкл")
	len += formatex(motd[len], charsmax(motd) - len, "<tr><td>HUD</td><td>%s</td></tr></table></body></html>", cso_hud_enabled(id) ? "вкл" : "выкл")
	show_motd(id, motd, "Личный кабинет")
}

// --- настройки -----------------------------------------------------------------

show_settings(id)
{
	new m[512], len
	len = formatex(m, charsmax(m), "\yНастройки^n^n")
	len += formatex(m[len], charsmax(m) - len, "\r1.\w Автооткрытие меню оружия: %s^n", cso_guns_setting(id, 0) ? "\yвкл" : "\rвыкл")
	len += formatex(m[len], charsmax(m) - len, "\r2.\w Всегда повторять прошлый набор: %s^n", cso_guns_setting(id, 1) ? "\yвкл" : "\rвыкл")
	len += formatex(m[len], charsmax(m) - len, "\r3.\w HUD: %s^n", cso_hud_enabled(id) ? "\yвкл" : "\rвыкл")
	len += formatex(m[len], charsmax(m) - len, "^n\r9.\w Назад^n\r0.\w Выход")
	show_menu(id, (1 << 0) | (1 << 1) | (1 << 2) | (1 << 8) | (1 << 9), m, -1, "CSO Settings")
}

public settings_handler(id, key)
{
	switch (key)
	{
		case 0: { cso_guns_toggle(id, 0); show_settings(id); }
		case 1: { cso_guns_toggle(id, 1); show_settings(id); }
		case 2: { cso_hud_toggle(id); show_settings(id); }
		case 8: show_main(id)
	}
	return PLUGIN_HANDLED
}

// --- защита ammo packs ------------------------------------------------------------

public task_ap_guard()
{
	new limit = g_pcv_ap_limit ? get_pcvar_num(g_pcv_ap_limit) : 0
	for (new id = 1; id <= 32; id++)
	{
		if (!is_user_connected(id))
			continue
		new ap = zp_get_user_ammo_packs(id)
		if (ap < 0)
			zp_set_user_ammo_packs(id, 0)
		else if (limit > 0 && ap > limit)
			zp_set_user_ammo_packs(id, limit)
	}
}

public client_disconnected(id)
{
	remove_task(id + TASK_ZPMENU)
}
