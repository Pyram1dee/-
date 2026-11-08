/*
 * CSO Zombie — специальный раунд "Deimos Round"
 *
 * ZP 4.3 Fix5a не имеет API пользовательских режимов, поэтому раунд —
 * надстройка над режимами ядра: срабатывает только когда ядро уже выбрало
 * MODE_INFECTION или MODE_MULTI. Немезида/выживший/swarm/plague никогда не
 * совпадают с Deimos Round — ядро выбирает ровно один режим на раунд.
 *
 * Эффект (предложение): стартовые зомби получают способность Deimos на
 * текущую жизнь и HP = cso_deimos_round_hp.
 * Неясно (TECH_SPEC п. 4), относятся ли 500 HP к каждому Deimos или к особому
 * персонажу: поэтому режим HP вынесен в CVAR cso_deimos_round_hp_mode.
 *
 * Зависимость: cso_zclass_deimos.amxx (library "cso_deimos") загружается раньше.
 */

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <zombieplague>

#define PLUGIN  "[CSO] Deimos Round"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#pragma reqlib cso_deimos
native cso_deimos_grant(id)

new g_pcv_enable, g_pcv_chance, g_pcv_min_players, g_pcv_hp, g_pcv_hp_mode, g_pcv_all
new bool:g_active
new bool:g_forced
new g_hud

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_enable      = register_cvar("cso_deimos_round_enable", "1")
	g_pcv_chance      = register_cvar("cso_deimos_round_chance", "10")     // % от подходящих раундов
	g_pcv_min_players = register_cvar("cso_deimos_round_min_players", "4")
	g_pcv_hp          = register_cvar("cso_deimos_round_hp", "500")
	g_pcv_hp_mode     = register_cvar("cso_deimos_round_hp_mode", "0")     // 0 — HP каждому, 1 — HP * число людей
	g_pcv_all         = register_cvar("cso_deimos_round_all_zombies", "0") // выдавать и заражённым по ходу раунда

	register_concmd("amx_deimos_round", "cmd_force", ADMIN_LEVEL_A, "- сделать следующий подходящий раунд Deimos Round")
	register_clcmd("say /deimos", "cmd_status")

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
	client_print(id, print_chat, "[CSO] Deimos Round: %s", g_active ? "идёт" : "нет")
	return PLUGIN_CONTINUE
}

public zp_round_started(gamemode, id)
{
	if (!get_pcvar_num(g_pcv_enable) || g_active)
		return

	// только поверх обычного заражения — исключаем конфликт режимов
	if (gamemode != MODE_INFECTION && gamemode != MODE_MULTI)
		return

	if (count_alive() < get_pcvar_num(g_pcv_min_players))
		return

	if (!g_forced && random_num(1, 100) > get_pcvar_num(g_pcv_chance))
		return

	g_forced = false
	start_round()
}

start_round()
{
	g_active = true

	new hp = calc_hp()
	new count = 0
	for (new id = 1; id <= 32; id++)
	{
		if (make_deimos(id, hp))
			count++
	}

	set_hudmessage(200, 30, 30, -1.0, 0.25, 1, 0.0, 5.0, 1.0, 1.0, -1)
	ShowSyncHudMsg(0, g_hud, "DEIMOS ROUND^nДеймосов: %d, HP: %d", count, hp)
	log_amx("[CSO] Deimos Round начат: %d деймос(ов), HP %d", count, hp)
}

bool:make_deimos(id, hp)
{
	if (!is_user_alive(id) || !zp_get_user_zombie(id) || zp_get_user_nemesis(id))
		return false
	if (!cso_deimos_grant(id))
		return false
	set_pev(id, pev_health, float(hp))
	set_pev(id, pev_max_health, float(hp))
	return true
}

calc_hp()
{
	new hp = max(1, get_pcvar_num(g_pcv_hp))
	if (get_pcvar_num(g_pcv_hp_mode) == 1)
		hp *= max(1, zp_get_human_count())
	return hp
}

count_alive()
{
	new n = 0
	for (new id = 1; id <= 32; id++)
		if (is_user_alive(id))
			n++
	return n
}

public zp_user_infected_post(id, infector, nemesis)
{
	if (g_active && !nemesis && get_pcvar_num(g_pcv_all))
		make_deimos(id, calc_hp())
}

public zp_round_ended(winteam)
{
	if (g_active)
		log_amx("[CSO] Deimos Round завершён, победитель: %d", winteam)
	g_active = false
}

public ev_new_round()
{
	g_active = false
}
