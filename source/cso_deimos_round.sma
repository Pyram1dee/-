/*
 * CSO Zombie — специальный раунд "Deimos Round"
 *
 * Правила (подтверждены пользователем 2026-11-08):
 *  - Deimos один на весь раунд;
 *  - HP в CFG (cso_deimos_round_hp); тестовое значение по итоговому ТЗ — 500 (ранее обсуждалось 20000);
 *  - урон по людям: удар ЛКМ 500 (cso_deimos_round_dmg_slash), ПКМ 1000 (cso_deimos_round_dmg_stab);
 *  - Deimos не заражает, а убивает.
 *
 * Реализация без правки ядра ZP 4.3 Fix5a:
 *  - раунд включается только когда ядро выбрало MODE_INFECTION (ровно один первый зомби);
 *    немезида/выживший/swarm/multi/plague с Deimos Round не совпадают;
 *  - первый зомби превращается в немезиду (zp_make_user_nemesis): ядро ZP для немезиды наносит
 *    урон вместо заражения, само засчитывает убийства и конец раунда;
 *  - урон немезиды (zp_nem_damage) переопределяется post-ядром хуком TakeDamage: по кнопке атаки
 *    ножа (Ham_Weapon_PrimaryAttack / SecondaryAttack), удар наносится внутри этих вызовов;
 *  - Deimos получает способность класса Deimos (cso_deimos_grant).
 * Модель/свечение/скорость Deimos — настройки немезиды ZP (zombieplague.ini, zp_nem_*).
 *
 * Зависимость: cso_zclass_deimos.amxx (library "cso_deimos") загружается раньше.
 */

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <hamsandwich>
#include <zombieplague>

#define PLUGIN  "[CSO] Deimos Round"
#define VERSION "0.2.0"
#define AUTHOR  "CSO Custom Project"

#define TASK_MAKE 52300

#pragma reqlib cso_deimos
native cso_deimos_grant(id)
#pragma reqlib cso_hud
native cso_hud_set_mode(const name[])

enum
{
	ATTACK_NONE = 0,
	ATTACK_SLASH,   // ЛКМ
	ATTACK_STAB     // ПКМ
}

new g_pcv_enable, g_pcv_chance, g_pcv_min_players, g_pcv_hp, g_pcv_slash, g_pcv_stab
new bool:g_active
new bool:g_forced
new g_deimos           // id игрока-Deimos в текущем раунде (0 — нет)
new g_attack[33]       // какой кнопкой сейчас бьёт Deimos
new g_hud

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_enable      = register_cvar("cso_deimos_round_enable", "1")
	g_pcv_chance      = register_cvar("cso_deimos_round_chance", "10")     // % от раундов заражения
	g_pcv_min_players = register_cvar("cso_deimos_round_min_players", "4")
	g_pcv_hp          = register_cvar("cso_deimos_round_hp", "500")     // тестовое значение по ТЗ §11
	g_pcv_slash       = register_cvar("cso_deimos_round_dmg_slash", "500")  // ЛКМ
	g_pcv_stab        = register_cvar("cso_deimos_round_dmg_stab", "1000")  // ПКМ

	register_concmd("amx_deimos_round", "cmd_force", ADMIN_LEVEL_A, "- сделать следующий раунд заражения Deimos Round")
	register_clcmd("say /deimos", "cmd_status")

	RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_knife", "fw_Knife_Primary_Pre")
	RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_knife", "fw_Knife_Attack_Post", 1)
	RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_knife", "fw_Knife_Secondary_Pre")
	RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_knife", "fw_Knife_Attack_Post", 1)
	// регистрируется после ядра ZP: наш SetHamParamFloat перекрывает zp_nem_damage
	RegisterHam(Ham_TakeDamage, "player", "fw_TakeDamage_Pre")

	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
	g_hud = CreateHudSyncObj()
}

public cmd_force(id, level, cid)
{
	if (!cmd_access(id, level, cid, 1))
		return PLUGIN_HANDLED

	g_forced = true
	console_print(id, "[CSO] Следующий раунд заражения будет Deimos Round")
	log_amx("[CSO] Deimos Round принудительно включён на следующий раунд (админ #%d)", id)
	return PLUGIN_HANDLED
}

public cmd_status(id)
{
	if (g_active && is_user_connected(g_deimos))
	{
		new name[32]
		get_user_name(g_deimos, name, charsmax(name))
		client_print(id, print_chat, "[CSO] Deimos Round: Deimos — %s", name)
	}
	else
		client_print(id, print_chat, "[CSO] Deimos Round: нет")
	return PLUGIN_CONTINUE
}

// ---------------------------------------------------------------------------
// Запуск
// ---------------------------------------------------------------------------

public zp_round_started(gamemode, id)
{
	if (!get_pcvar_num(g_pcv_enable) || g_active)
		return

	// только обычное заражение: ровно один первый зомби (id)
	if (gamemode != MODE_INFECTION || !is_user_alive(id))
		return

	if (count_alive() < get_pcvar_num(g_pcv_min_players))
		return

	if (!g_forced && random_num(1, 100) > get_pcvar_num(g_pcv_chance))
		return

	g_forced = false
	g_active = true
	g_deimos = id
	// не вмешиваемся в середину запуска режима ядром — превращаем чуть позже
	set_task(0.1, "task_make_deimos", TASK_MAKE)
}

public task_make_deimos()
{
	new id = g_deimos
	if (!g_active || !is_user_alive(id) || !zp_get_user_zombie(id))
	{
		abort_round("первый зомби недоступен")
		return
	}

	if (!zp_get_user_nemesis(id) && !zp_make_user_nemesis(id))
	{
		abort_round("ядро ZP не разрешило немезиду")
		return
	}

	new Float:hp = float(max(1, get_pcvar_num(g_pcv_hp)))
	set_pev(id, pev_health, hp)
	set_pev(id, pev_max_health, hp)
	cso_deimos_grant(id)

	new name[32]
	get_user_name(id, name, charsmax(name))
	set_hudmessage(200, 30, 30, -1.0, 0.25, 1, 0.0, 5.0, 1.0, 1.0, -1)
	ShowSyncHudMsg(0, g_hud, "РАУНД ДЕЙМОСА^n%s — Деймос (%d HP)", name, floatround(hp))
	cso_hud_set_mode("Раунд Деймоса")
	log_amx("[CSO] Deimos Round начат: Deimos #%d (%s), HP %d", id, name, floatround(hp))
}

abort_round(const why[])
{
	log_amx("[CSO] Deimos Round отменён: %s", why)
	g_active = false
	g_deimos = 0
}

count_alive()
{
	new n = 0
	for (new id = 1; id <= 32; id++)
		if (is_user_alive(id))
			n++
	return n
}

// ---------------------------------------------------------------------------
// Урон Deimos
// ---------------------------------------------------------------------------

public fw_Knife_Primary_Pre(weapon)
{
	new id = pev(weapon, pev_owner)
	if (1 <= id <= 32)
		g_attack[id] = ATTACK_SLASH
	return HAM_IGNORED
}

public fw_Knife_Secondary_Pre(weapon)
{
	new id = pev(weapon, pev_owner)
	if (1 <= id <= 32)
		g_attack[id] = ATTACK_STAB
	return HAM_IGNORED
}

public fw_Knife_Attack_Post(weapon)
{
	new id = pev(weapon, pev_owner)
	if (1 <= id <= 32)
		g_attack[id] = ATTACK_NONE
	return HAM_IGNORED
}

public fw_TakeDamage_Pre(victim, inflictor, attacker, Float:damage, damagebits)
{
	if (!g_active || attacker != g_deimos || inflictor != attacker)
		return HAM_IGNORED
	if (!(1 <= attacker <= 32) || !zp_get_user_nemesis(attacker) || zp_get_user_zombie(victim))
		return HAM_IGNORED

	switch (g_attack[attacker])
	{
		case ATTACK_SLASH: SetHamParamFloat(4, get_pcvar_float(g_pcv_slash))
		case ATTACK_STAB:  SetHamParamFloat(4, get_pcvar_float(g_pcv_stab))
		default: return HAM_IGNORED // не удар ножом — оставляем как решило ядро
	}
	return HAM_HANDLED
}

// ---------------------------------------------------------------------------
// Конец
// ---------------------------------------------------------------------------

public client_disconnected(id)
{
	g_attack[id] = ATTACK_NONE
	if (g_active && id == g_deimos)
		log_amx("[CSO] Deimos вышел с сервера — раунд завершит ядро ZP")
}

public zp_round_ended(winteam)
{
	if (g_active)
		log_amx("[CSO] Deimos Round завершён, победитель: %d", winteam)
	remove_task(TASK_MAKE)
	g_active = false
	g_deimos = 0
}

public ev_new_round()
{
	remove_task(TASK_MAKE)
	g_active = false
	g_deimos = 0
}
