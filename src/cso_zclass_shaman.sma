/*
 * CSO Zombie — класс "Шаман" (Shaman)
 * Способность: крик. Клавиша по ТЗ: E (+use).
 * Эффект (предложение): люди в радиусе и в прямой видимости получают
 * тряску экрана, затемнение и временное замедление.
 * Срабатывание — только по фронту нажатия +use (удержание не повторяет),
 * плюс кулдаун. Сам +use не блокируется.
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <zombieplague>
#include <cso_common>

#define PLUGIN  "[CSO] ZClass: Shaman"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#define TASK_SLOW 51400

// звук из комплекта ZP 4.3 Fix5a
new const SCREAM_SOUND[] = "zombie_plague/zombie_madness1.wav"

new const ZC_NAME[]  = "Shaman"
new const ZC_INFO[]  = "Крик [E]"
new const ZC_MODEL[] = "zombie_source"
new const ZC_CLAW[]  = "v_knife_zombie.mdl"
const ZC_HEALTH      = 1600
const ZC_SPEED       = 240
const Float:ZC_GRAV  = 1.0
const Float:ZC_KNOCK = 1.1

new g_pcv_radius, g_pcv_slow_mult, g_pcv_slow_time, g_pcv_cooldown, g_pcv_survivor
new bool:g_slowed[CSO_MAXPLAYERS + 1]
new g_msg_shake, g_msg_fade

public plugin_precache()
{
	g_cso_class = zp_register_zombie_class(ZC_NAME, ZC_INFO, ZC_MODEL, ZC_CLAW, ZC_HEALTH, ZC_SPEED, ZC_GRAV, ZC_KNOCK)
	precache_sound(SCREAM_SOUND)
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_radius    = register_cvar("cso_shaman_radius", "400.0")
	g_pcv_slow_mult = register_cvar("cso_shaman_slow_multiplier", "0.7")
	g_pcv_slow_time = register_cvar("cso_shaman_slow_duration", "3.0")
	g_pcv_cooldown  = register_cvar("cso_shaman_cooldown", "25.0")
	g_pcv_survivor  = register_cvar("cso_shaman_affect_survivor", "0")

	cso_skill_init(CSO_KEY_E, g_pcv_cooldown)

	g_msg_shake = get_user_msgid("ScreenShake")
	g_msg_fade  = get_user_msgid("ScreenFade")

	RegisterHam(CSO_Ham_ResetMaxSpeed, "player", "fw_ResetMaxSpeed_Post", 1)
	RegisterHam(Ham_Killed, "player", "fw_Killed_Post", 1)
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
}

public bool:cso_skill_activate(id)
{
	new Float:radius = get_pcvar_float(g_pcv_radius)
	if (radius <= 0.0)
		return false

	new Float:src[3], Float:dst[3], Float:ofs[3]
	pev(id, pev_origin, src)
	pev(id, pev_view_ofs, ofs)
	src[2] += ofs[2]

	new hit = 0, tr = create_tr2(), Float:frac
	for (new victim = 1; victim <= CSO_MAXPLAYERS; victim++)
	{
		if (victim == id || !is_user_alive(victim) || zp_get_user_zombie(victim))
			continue
		if (zp_get_user_survivor(victim) && !get_pcvar_num(g_pcv_survivor))
			continue

		pev(victim, pev_origin, dst)
		pev(victim, pev_view_ofs, ofs)
		dst[2] += ofs[2]
		if (get_distance_f(src, dst) > radius)
			continue

		// прямая видимость: крик не проходит сквозь стены
		engfunc(EngFunc_TraceLine, src, dst, IGNORE_MONSTERS, id, tr)
		get_tr2(tr, TR_flFraction, frac)
		if (frac < 1.0)
			continue

		affect_victim(victim)
		hit++
	}
	free_tr2(tr)

	emit_sound(id, CHAN_VOICE, SCREAM_SOUND, 1.0, ATTN_NORM, 0, PITCH_LOW)
	client_print(id, print_center, "[CSO] Крик! Задето людей: %d", hit)
	return true
}

affect_victim(victim)
{
	message_begin(MSG_ONE_UNRELIABLE, g_msg_shake, _, victim)
	write_short(1 << 14) // амплитуда
	write_short(1 << 13) // длительность
	write_short(1 << 13) // частота
	message_end()

	message_begin(MSG_ONE_UNRELIABLE, g_msg_fade, _, victim)
	write_short(1 << 12) // длительность
	write_short(1 << 11) // удержание
	write_short(0x0000)  // FFADE_IN
	write_byte(80)
	write_byte(0)
	write_byte(0)
	write_byte(120)
	message_end()

	new Float:t = get_pcvar_float(g_pcv_slow_time)
	if (t <= 0.0)
		return

	g_slowed[victim] = true
	ExecuteHamB(CSO_Ham_ResetMaxSpeed, victim)
	remove_task(victim + TASK_SLOW)
	set_task(t, "task_unslow", victim + TASK_SLOW)
}

public fw_ResetMaxSpeed_Post(id)
{
	if (!g_slowed[id] || !is_user_alive(id))
		return HAM_IGNORED

	if (zp_get_user_zombie(id)) // заражён во время замедления
	{
		g_slowed[id] = false
		return HAM_IGNORED
	}

	new Float:speed
	pev(id, pev_maxspeed, speed)
	if (speed <= 1.0)
		return HAM_IGNORED

	new Float:mult = floatclamp(get_pcvar_float(g_pcv_slow_mult), 0.1, 1.0)
	set_pev(id, pev_maxspeed, speed * mult)
	return HAM_IGNORED
}

public task_unslow(taskid)
{
	unslow(taskid - TASK_SLOW, true)
}

unslow(id, bool:recalc)
{
	remove_task(id + TASK_SLOW)
	if (!g_slowed[id])
		return
	g_slowed[id] = false
	if (recalc && is_user_alive(id))
		ExecuteHamB(CSO_Ham_ResetMaxSpeed, id)
}

public zp_user_infected_post(id, infector, nemesis)
{
	unslow(id, false)
	cso_reset_cooldown(id)
	if (cso_is_class_zombie(id))
		cso_print_skill_help(id, ZC_NAME)
}

public zp_user_humanized_post(id, survivor)
{
	unslow(id, false)
}

public fw_Killed_Post(victim, attacker, shouldgib)
{
	unslow(victim, false)
}

public client_disconnected(id)
{
	unslow(id, false)
	cso_reset_cooldown(id)
}

public zp_round_ended(winteam)
{
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
		unslow(id, true)
}

public ev_new_round()
{
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
	{
		unslow(id, false)
		cso_reset_cooldown(id)
	}
}
