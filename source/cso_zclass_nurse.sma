/*
 * CSO Zombie — класс "Медсестра" (Nurse)
 * Способность: временное изменение собственной гравитации. Клавиша по ТЗ: R (+reload).
 * Гарантированный сброс:
 *  - по таймеру восстанавливается гравитация, сохранённая при активации;
 *  - если в этот момент игрок заморожен (ZP держит гравитацию 999999),
 *    восстановление откладывается до zp_user_unfrozen;
 *  - при заражении/очеловечивании ядро ZP само выставляет гравитацию класса.
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <zombieplague>
#include <cso_common>

#define PLUGIN  "[CSO] ZClass: Nurse"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#define TASK_END 51600

new const ZC_NAME[]  = "Медсестра"
new const ZC_INFO[]  = "Гравитация [R]"
new const ZC_MODEL[] = "zombie_source"
new const ZC_CLAW[]  = "v_knife_zombie.mdl"
const ZC_HEALTH      = 1700
const ZC_SPEED       = 245
const Float:ZC_GRAV  = 0.9
const Float:ZC_KNOCK = 1.0

new g_pcv_mult, g_pcv_duration, g_pcv_cooldown
new bool:g_active[CSO_MAXPLAYERS + 1]
new bool:g_pending[CSO_MAXPLAYERS + 1]   // ждём разморозки, чтобы вернуть гравитацию
new Float:g_saved_grav[CSO_MAXPLAYERS + 1]

public plugin_precache()
{
	g_cso_class = zp_register_zombie_class(ZC_NAME, ZC_INFO, ZC_MODEL, ZC_CLAW, ZC_HEALTH, ZC_SPEED, ZC_GRAV, ZC_KNOCK)
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_mult     = register_cvar("cso_nurse_gravity_multiplier", "0.5")
	g_pcv_duration = register_cvar("cso_nurse_duration", "8.0")
	g_pcv_cooldown = register_cvar("cso_nurse_cooldown", "20.0")

	cso_skill_init(CSO_KEY_R, g_pcv_cooldown, ZC_NAME)

	RegisterHam(Ham_Killed, "player", "fw_Killed_Post", 1)
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
}

public bool:cso_skill_activate(id)
{
	new Float:duration = get_pcvar_float(g_pcv_duration)
	if (duration <= 0.0 || g_active[id])
		return false

	new Float:grav
	pev(id, pev_gravity, grav)
	g_saved_grav[id] = grav
	g_active[id] = true
	g_pending[id] = false

	new Float:mult = floatclamp(get_pcvar_float(g_pcv_mult), 0.05, 3.0)
	set_pev(id, pev_gravity, grav * mult)

	remove_task(id + TASK_END)
	set_task(duration, "task_end", id + TASK_END)

	client_print(id, print_center, "[CSO] Гравитация изменена на %.0f с", duration)
	return true
}

public task_end(taskid)
{
	restore(taskid - TASK_END)
}

restore(id)
{
	remove_task(id + TASK_END)
	if (!g_active[id])
		return
	g_active[id] = false

	if (!is_user_alive(id))
		return

	if (cso_is_frozen(id))
	{
		g_pending[id] = true // вернём после разморозки
		return
	}
	set_pev(id, pev_gravity, g_saved_grav[id])
}

// Сброс без восстановления: ядро ZP само выставит правильную гравитацию
drop_state(id)
{
	remove_task(id + TASK_END)
	g_active[id] = false
	g_pending[id] = false
}

public zp_user_unfrozen(id)
{
	// ZP вернул гравитацию, сохранённую до заморозки (пониженную) — исправляем
	if (g_pending[id] && is_user_alive(id))
		set_pev(id, pev_gravity, g_saved_grav[id])
	g_pending[id] = false
}

public zp_user_infected_post(id, infector, nemesis)
{
	drop_state(id)
	cso_reset_cooldown(id)
	if (cso_is_class_zombie(id))
		cso_print_skill_help(id, ZC_NAME)
}

public zp_user_humanized_post(id, survivor)
{
	drop_state(id)
}

public fw_Killed_Post(victim, attacker, shouldgib)
{
	drop_state(victim)
}

public client_disconnected(id)
{
	drop_state(id)
	cso_reset_cooldown(id)
}

public zp_round_ended(winteam)
{
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
		restore(id)
}

public ev_new_round()
{
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
	{
		drop_state(id)
		cso_reset_cooldown(id)
	}
}
