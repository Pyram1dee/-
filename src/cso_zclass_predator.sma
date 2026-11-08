/*
 * CSO Zombie — класс "Хищник" (Predator)
 * Способность: временное ускорение. Клавиша по ТЗ: G.
 * Скорость: множитель поверх скорости, которую выставляет ядро ZP
 * в post-хуке ResetMaxSpeed, поэтому после окончания эффекта ядро
 * само восстанавливает исходное значение.
 *
 * ВНИМАНИЕ: итоговая скорость ограничена серверным sv_maxspeed (по умолчанию 320).
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <zombieplague>
#include <cso_common>

#define PLUGIN  "[CSO] ZClass: Predator"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#define TASK_END 51100

// Параметры класса (предложение, не согласованы). Меняются через zp_zombieclasses.ini
new const ZC_NAME[]  = "Predator"
new const ZC_INFO[]  = "Ускорение [G]"
new const ZC_MODEL[] = "zombie_source"
new const ZC_CLAW[]  = "v_knife_zombie.mdl"
const ZC_HEALTH      = 1800
const ZC_SPEED       = 250
const Float:ZC_GRAV  = 1.0
const Float:ZC_KNOCK = 1.0

new g_pcv_mult, g_pcv_duration, g_pcv_cooldown
new bool:g_boost[CSO_MAXPLAYERS + 1]

public plugin_precache()
{
	g_cso_class = zp_register_zombie_class(ZC_NAME, ZC_INFO, ZC_MODEL, ZC_CLAW, ZC_HEALTH, ZC_SPEED, ZC_GRAV, ZC_KNOCK)
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_mult     = register_cvar("cso_predator_speed_multiplier", "1.3")
	g_pcv_duration = register_cvar("cso_predator_duration", "5.0")
	g_pcv_cooldown = register_cvar("cso_predator_cooldown", "20.0")

	cso_skill_init(CSO_KEY_G, g_pcv_cooldown)

	RegisterHam(CSO_Ham_ResetMaxSpeed, "player", "fw_ResetMaxSpeed_Post", 1)
	RegisterHam(Ham_Killed, "player", "fw_Killed_Post", 1)
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
}

public bool:cso_skill_activate(id)
{
	new Float:duration = get_pcvar_float(g_pcv_duration)
	if (duration <= 0.0)
		return false

	g_boost[id] = true
	ExecuteHamB(CSO_Ham_ResetMaxSpeed, id)

	remove_task(id + TASK_END)
	set_task(duration, "task_end_boost", id + TASK_END)

	client_print(id, print_center, "[CSO] Ускорение!")
	return true
}

public fw_ResetMaxSpeed_Post(id)
{
	if (!g_boost[id] || !is_user_alive(id))
		return HAM_IGNORED

	// эффект только для живого зомби своего класса; иначе — гасим
	if (!cso_is_class_zombie(id))
	{
		g_boost[id] = false
		return HAM_IGNORED
	}

	new Float:speed
	pev(id, pev_maxspeed, speed)
	if (speed <= 1.0) // заморозка ZP или freezetime
		return HAM_IGNORED

	new Float:mult = get_pcvar_float(g_pcv_mult)
	if (mult < 0.1) mult = 0.1
	set_pev(id, pev_maxspeed, speed * mult)
	return HAM_IGNORED
}

public task_end_boost(taskid)
{
	stop_boost(taskid - TASK_END, true)
}

stop_boost(id, bool:recalc)
{
	remove_task(id + TASK_END)
	if (!g_boost[id])
		return
	g_boost[id] = false
	if (recalc && is_user_alive(id))
		ExecuteHamB(CSO_Ham_ResetMaxSpeed, id) // ядро вернёт штатную скорость
}

public zp_user_infected_post(id, infector, nemesis)
{
	stop_boost(id, false)
	cso_reset_cooldown(id)
	if (cso_is_class_zombie(id))
		cso_print_skill_help(id, ZC_NAME)
}

public zp_user_humanized_post(id, survivor)
{
	stop_boost(id, false)
}

public fw_Killed_Post(victim, attacker, shouldgib)
{
	stop_boost(victim, false)
}

public client_disconnected(id)
{
	stop_boost(id, false)
	cso_reset_cooldown(id)
}

public zp_round_ended(winteam)
{
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
		stop_boost(id, true)
}

public ev_new_round()
{
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
	{
		stop_boost(id, false)
		cso_reset_cooldown(id)
	}
}
