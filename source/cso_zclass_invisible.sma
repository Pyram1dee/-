/*
 * CSO Zombie — класс "Невидимка" (Invisible)
 * Способность: прозрачность на cso_invisible_duration секунд. Клавиша по ТЗ: G.
 * Рендер ставится и на игрока, и на отдельную сущность модели ZP ("player_model").
 * После разморозки ZP сбрасывает рендер — эффект переприменяется в zp_user_unfrozen.
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <zombieplague>
#include <cso_common>

#define PLUGIN  "[CSO] ZClass: Invisible"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#define TASK_END 51200

new const ZC_NAME[]  = "Невидимка"
new const ZC_INFO[]  = "Невидимость [G]"
new const ZC_MODEL[] = "zombie_source"
new const ZC_CLAW[]  = "v_knife_zombie.mdl"
const ZC_HEALTH      = 1500
const ZC_SPEED       = 240
const Float:ZC_GRAV  = 1.0
const Float:ZC_KNOCK = 1.2

new g_pcv_duration, g_pcv_alpha, g_pcv_cooldown
new bool:g_invisible[CSO_MAXPLAYERS + 1]

public plugin_precache()
{
	g_cso_class = zp_register_zombie_class(ZC_NAME, ZC_INFO, ZC_MODEL, ZC_CLAW, ZC_HEALTH, ZC_SPEED, ZC_GRAV, ZC_KNOCK)
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_duration = register_cvar("cso_invisible_duration", "15.0")
	g_pcv_alpha    = register_cvar("cso_invisible_alpha", "20")    // 0 — полностью невидим, 255 — обычный
	g_pcv_cooldown = register_cvar("cso_invisible_cooldown", "30.0")

	cso_skill_init(CSO_KEY_G, g_pcv_cooldown, ZC_NAME)

	RegisterHam(Ham_Killed, "player", "fw_Killed_Post", 1)
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
}

public bool:cso_skill_activate(id)
{
	new Float:duration = get_pcvar_float(g_pcv_duration)
	if (duration <= 0.0)
		return false

	g_invisible[id] = true
	apply_invisibility(id)

	remove_task(id + TASK_END)
	set_task(duration, "task_end", id + TASK_END)

	client_print(id, print_center, "[CSO] Невидимость на %.0f с", duration)
	return true
}

apply_invisibility(id)
{
	new alpha = clamp(get_pcvar_num(g_pcv_alpha), 0, 255)
	cso_set_player_rendering(id, kRenderFxNone, 0, 0, 0, kRenderTransAlpha, alpha)
}

public task_end(taskid)
{
	new id = taskid - TASK_END
	stop_invisibility(id, true)
	if (is_user_connected(id))
		client_print(id, print_center, "[CSO] Невидимость закончилась")
}

stop_invisibility(id, bool:restore)
{
	remove_task(id + TASK_END)
	if (!g_invisible[id])
		return
	g_invisible[id] = false

	// не трогаем рендер замороженного игрока: ZP сам вернёт обычный после разморозки
	if (restore && is_user_connected(id) && !cso_is_frozen(id))
		cso_set_player_rendering(id)
}

public zp_user_unfrozen(id)
{
	if (g_invisible[id] && cso_is_class_zombie(id))
		apply_invisibility(id)
}

public zp_user_infected_post(id, infector, nemesis)
{
	stop_invisibility(id, true)
	cso_reset_cooldown(id)
	if (cso_is_class_zombie(id))
		cso_print_skill_help(id, ZC_NAME)
}

public zp_user_humanized_post(id, survivor)
{
	// ядро ZP при очеловечивании само выставляет рендер (в т.ч. ауру выжившего)
	stop_invisibility(id, false)
}

public fw_Killed_Post(victim, attacker, shouldgib)
{
	stop_invisibility(victim, true)
}

public client_disconnected(id)
{
	stop_invisibility(id, false)
	cso_reset_cooldown(id)
}

public zp_round_ended(winteam)
{
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
		stop_invisibility(id, true)
}

public ev_new_round()
{
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
	{
		stop_invisibility(id, true)
		cso_reset_cooldown(id)
	}
}
