/*
 * CSO Zombie 1.6 Custom Edition — общий код для модулей классов.
 * Подключается в каждый плагин отдельно (не отдельный плагин и не native-API).
 *
 * Требует: amxmodx, fakemeta, hamsandwich, zombieplague (ZP 4.3 Fix5a).
 *
 * Плагин класса обязан:
 *   1. в plugin_precache записать id класса в g_cso_class (результат zp_register_zombie_class);
 *   2. в plugin_init вызвать cso_skill_init(CSO_KEY_x, pcvar кулдауна, имя класса);
 *   3. определить функцию  bool:cso_skill_activate(id)  — запуск способности;
 *      вернуть true, если способность сработала (тогда запускается кулдаун).
 *
 * Клавиши (CLAUDE.md п. 7): в GoldSrc G/E/R — это клиентские бинды.
 *   G = "drop"    — клиентская команда, доходит до сервера, перехватывается register_clcmd.
 *   E = "+use"    — кнопка IN_USE в usercmd, видна серверу в pev_button.
 *   R = "+reload" — кнопка IN_RELOAD в usercmd, видна серверу в pev_button.
 * Перехват работает только для живого зомби нужного класса и отключается CVAR
 * cso_skill_hardkeys 0. Всегда доступны: консольная команда "cso_skill"
 * (bind g cso_skill) и чат "/skill".
 */

#if defined _cso_common_included
	#endinput
#endif
#define _cso_common_included

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <zombieplague>

// HUD (cso_hud.amxx): имя класса и перезарядка способности
#pragma reqlib cso_hud
native cso_hud_class(classid, const name[])
native cso_hud_cooldown(id, Float:ready_time)

#define CSO_MAXPLAYERS 32

// Хак ZP 4.3: Ham_Item_PreFrame у игрока = CBasePlayer::ResetMaxSpeed
#define CSO_Ham_ResetMaxSpeed Ham_Item_PreFrame

// ZP замораживает игрока, выставляя огромную гравитацию (zombie_plague40.sma: 999999.9)
#define CSO_FROZEN_GRAVITY 99999.0

enum
{
	CSO_KEY_G = 0,
	CSO_KEY_E,
	CSO_KEY_R
}

new const CSO_KEY_NAMES[][] = { "G (drop)", "E (+use)", "R (+reload)" }

new g_cso_class = -1          // id класса ZP
new g_cso_key = CSO_KEY_G
new g_cso_pcv_cooldown
new g_cso_pcv_hardkeys
new Float:g_cso_next_use[CSO_MAXPLAYERS + 1]
// Способность, выданная на текущую жизнь вне класса (например, Deimos Round)
new bool:g_cso_granted[CSO_MAXPLAYERS + 1]

// --------------------------------------------------------------------------
// Регистрация
// --------------------------------------------------------------------------

stock cso_skill_init(key, pcvar_cooldown, const classname[])
{
	if (g_cso_class >= 0)
		cso_hud_class(g_cso_class, classname)
	g_cso_key = key
	g_cso_pcv_cooldown = pcvar_cooldown
	g_cso_pcv_hardkeys = register_cvar("cso_skill_hardkeys", "1")

	register_clcmd("cso_skill", "cso__cmd_skill")
	register_clcmd("say /skill", "cso__cmd_skill")
	register_clcmd("say_team /skill", "cso__cmd_skill")

	if (key == CSO_KEY_G)
		register_clcmd("drop", "cso__cmd_drop")
	else
		register_forward(FM_PlayerPreThink, "cso__fw_prethink")
}

// --------------------------------------------------------------------------
// Проверки состояния
// --------------------------------------------------------------------------

stock bool:cso_is_valid_player(id)
{
	return (1 <= id <= CSO_MAXPLAYERS && is_user_connected(id))
}

// Живой обычный зомби (не немезида) нашего класса
stock bool:cso_is_class_zombie(id)
{
	if (g_cso_class < 0 || !cso_is_valid_player(id) || !is_user_alive(id))
		return false
	if (!zp_get_user_zombie(id))
		return false
	// выданная способность действует и у немезиды (Deimos в Deimos Round)
	if (g_cso_granted[id])
		return true
	if (zp_get_user_nemesis(id))
		return false
	return (zp_get_user_zombie_class(id) == g_cso_class)
}

stock bool:cso_is_frozen(id)
{
	new Float:grav
	pev(id, pev_gravity, grav)
	return (grav >= CSO_FROZEN_GRAVITY)
}

stock cso_reset_cooldown(id)
{
	g_cso_next_use[id] = 0.0
	if (1 <= id <= CSO_MAXPLAYERS)
		cso_hud_cooldown(id, 0.0)
}

// --------------------------------------------------------------------------
// Запуск способности
// --------------------------------------------------------------------------

stock bool:cso_skill_try(id)
{
	if (!cso_is_class_zombie(id))
		return false

	if (cso_is_frozen(id))
	{
		client_print(id, print_center, "[CSO] Нельзя использовать способность в заморозке")
		return false
	}

	new Float:now = get_gametime()
	if (now < g_cso_next_use[id])
	{
		client_print(id, print_center, "[CSO] Способность перезаряжается: %.0f с", g_cso_next_use[id] - now)
		return false
	}

	if (!cso_skill_activate(id))
		return false

	new Float:cd = get_pcvar_float(g_cso_pcv_cooldown)
	if (cd < 0.0) cd = 0.0
	g_cso_next_use[id] = now + cd
	cso_hud_cooldown(id, g_cso_next_use[id])
	return true
}

public cso__cmd_skill(id)
{
	if (cso_is_class_zombie(id))
	{
		cso_skill_try(id)
		return PLUGIN_HANDLED
	}
	// чужой класс: не глотаем команду, чтобы её мог обработать плагин другого класса
	return PLUGIN_CONTINUE
}

public cso__cmd_drop(id)
{
	if (!get_pcvar_num(g_cso_pcv_hardkeys) || !cso_is_class_zombie(id))
		return PLUGIN_CONTINUE

	cso_skill_try(id)
	return PLUGIN_HANDLED // у зомби только нож, обычный drop ему не нужен
}

public cso__fw_prethink(id)
{
	if (!is_user_alive(id) || !get_pcvar_num(g_cso_pcv_hardkeys))
		return FMRES_IGNORED

	new bit = (g_cso_key == CSO_KEY_E) ? IN_USE : IN_RELOAD
	new buttons = pev(id, pev_button)
	new old = pev(id, pev_oldbuttons)

	// только фронт нажатия: удержание клавиши не повторяет способность
	if ((buttons & bit) && !(old & bit) && cso_is_class_zombie(id))
		cso_skill_try(id)

	// +use/+reload не блокируем: двери и т.п. работают как обычно
	return FMRES_IGNORED
}

// --------------------------------------------------------------------------
// Утилиты
// --------------------------------------------------------------------------

stock cso_set_rendering(ent, fx = kRenderFxNone, r = 255, g = 255, b = 255, render = kRenderNormal, amount = 16)
{
	if (!pev_valid(ent))
		return
	new Float:color[3]
	color[0] = float(r)
	color[1] = float(g)
	color[2] = float(b)
	set_pev(ent, pev_renderfx, fx)
	set_pev(ent, pev_rendercolor, color)
	set_pev(ent, pev_rendermode, render)
	set_pev(ent, pev_renderamt, float(amount))
}

// ZP может рисовать модель игрока отдельной сущностью "player_model"
stock cso_get_model_ent(id)
{
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", "player_model")) > 0)
	{
		if (pev(ent, pev_owner) == id)
			return ent
	}
	return 0
}

stock cso_set_player_rendering(id, fx = kRenderFxNone, r = 255, g = 255, b = 255, render = kRenderNormal, amount = 16)
{
	cso_set_rendering(id, fx, r, g, b, render, amount)
	new ment = cso_get_model_ent(id)
	if (ment)
		cso_set_rendering(ment, fx, r, g, b, render, amount)
}

// Precache модели с проверкой существования файла и запасным вариантом.
// В out записывается фактически используемый путь.
stock cso_precache_model_safe(const wanted[], const fallback[], out[], outlen)
{
	if (wanted[0] && file_exists(wanted))
		copy(out, outlen, wanted)
	else
	{
		if (wanted[0])
			log_amx("[CSO] Нет модели %s, используется %s (см. assets/MANIFEST.md)", wanted, fallback)
		copy(out, outlen, fallback)
	}
	return engfunc(EngFunc_PrecacheModel, out)
}

stock cso_print_skill_help(id, const classname[])
{
	if (!get_pcvar_num(g_cso_pcv_hardkeys))
		client_print(id, print_chat, "[CSO] %s: способность — bind <клавиша> cso_skill или /skill", classname)
	else
		client_print(id, print_chat, "[CSO] %s: способность — %s, cso_skill или /skill", classname, CSO_KEY_NAMES[g_cso_key])
}

stock cso_remove_entities_by_class(const classname[], owner = 0)
{
	new ent = -1, count = 0
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", classname)) > 0)
	{
		if (owner && pev(ent, pev_owner) != owner)
			continue
		engfunc(EngFunc_RemoveEntity, ent)
		count++
	}
	return count
}

stock cso_count_entities_by_class(const classname[], owner)
{
	new ent = -1, count = 0
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", classname)) > 0)
	{
		if (pev(ent, pev_owner) == owner)
			count++
	}
	return count
}
