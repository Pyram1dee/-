/*
 * CSO Zombie — класс "Толстяк" (Heavy Zombie)
 * Способность: поставить ловушку под собой. Клавиша по ТЗ: R (+reload).
 *  - ловушка — триггер (SOLID_TRIGGER): с ней нельзя столкнуться и застрять;
 *  - человек, наступивший на ловушку, обездвижен на cso_heavy_trap_hold секунд;
 *  - лимит ловушек на игрока, время жизни, минимальная дистанция между ловушками;
 *  - все ловушки удаляются в конце/начале раунда, ловушки игрока — при выходе;
 *  - пойманный освобождается по таймеру, при смерти, заражении, конце раунда.
 * Модель heavy_zombie.zip была в Source-формате и не подходит (TECH_SPEC п. 7);
 * используется собственная модель assets/models/cso/zombitrap.mdl.
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <engine>
#include <zombieplague>
#include <cso_common>

#define PLUGIN  "[CSO] ZClass: Heavy"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#define TASK_RELEASE 51500

new const TRAP_CLASS[] = "cso_trap"
new const TRAP_MODEL[] = "models/cso/zombitrap.mdl" // assets/models/cso, генератор tools/mdl
new const TRAP_MODEL_FALLBACK[] = "models/w_weaponbox.mdl"
new const Float:TRAP_MINS[3] = { -16.0, -16.0, 0.0 }
new const Float:TRAP_MAXS[3] = { 16.0, 16.0, 12.0 }

new const ZC_NAME[]  = "Heavy"
new const ZC_INFO[]  = "Ловушка [R]"
new const ZC_MODEL[] = "zombie_source"
new const ZC_CLAW[]  = "v_knife_zombie.mdl"
const ZC_HEALTH      = 3000
const ZC_SPEED       = 220
const Float:ZC_GRAV  = 1.1
const Float:ZC_KNOCK = 0.5

new g_trap_model[64]
new g_pcv_max, g_pcv_life, g_pcv_hold, g_pcv_cooldown, g_pcv_alpha, g_pcv_survivor, g_pcv_spacing
new bool:g_trapped[CSO_MAXPLAYERS + 1]

public plugin_precache()
{
	g_cso_class = zp_register_zombie_class(ZC_NAME, ZC_INFO, ZC_MODEL, ZC_CLAW, ZC_HEALTH, ZC_SPEED, ZC_GRAV, ZC_KNOCK)
	cso_precache_model_safe(TRAP_MODEL, TRAP_MODEL_FALLBACK, g_trap_model, charsmax(g_trap_model))
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_max      = register_cvar("cso_heavy_max_traps", "2")
	g_pcv_life     = register_cvar("cso_heavy_trap_lifetime", "30.0")
	g_pcv_hold     = register_cvar("cso_heavy_trap_hold", "3.0")
	g_pcv_cooldown = register_cvar("cso_heavy_cooldown", "15.0")
	g_pcv_alpha    = register_cvar("cso_heavy_trap_alpha", "120")
	g_pcv_survivor = register_cvar("cso_heavy_affect_survivor", "0")
	g_pcv_spacing  = register_cvar("cso_heavy_trap_spacing", "48.0")

	cso_skill_init(CSO_KEY_R, g_pcv_cooldown)

	register_think(TRAP_CLASS, "fw_trap_think")
	register_touch(TRAP_CLASS, "player", "fw_trap_touch")
	register_forward(FM_PlayerPreThink, "fw_PlayerPreThink")
	RegisterHam(CSO_Ham_ResetMaxSpeed, "player", "fw_ResetMaxSpeed_Post", 1)
	RegisterHam(Ham_Killed, "player", "fw_Killed_Post", 1)
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
}

public bool:cso_skill_activate(id)
{
	new max_traps = get_pcvar_num(g_pcv_max)
	if (max_traps <= 0)
		return false

	if (!(pev(id, pev_flags) & FL_ONGROUND))
	{
		client_print(id, print_center, "[CSO] Ловушку можно ставить только стоя на земле")
		return false
	}

	if (cso_count_entities_by_class(TRAP_CLASS, id) >= max_traps)
	{
		client_print(id, print_center, "[CSO] Достигнут лимит ловушек (%d)", max_traps)
		return false
	}

	new Float:origin[3], Float:mins[3]
	pev(id, pev_origin, origin)
	pev(id, pev_mins, mins)
	origin[2] += mins[2] + 1.0 // уровень ступней

	if (trap_nearby(origin))
	{
		client_print(id, print_center, "[CSO] Слишком близко к другой ловушке")
		return false
	}

	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"))
	if (!pev_valid(ent))
		return false

	set_pev(ent, pev_classname, TRAP_CLASS)
	engfunc(EngFunc_SetModel, ent, g_trap_model)
	engfunc(EngFunc_SetSize, ent, TRAP_MINS, TRAP_MAXS)
	engfunc(EngFunc_SetOrigin, ent, origin)
	set_pev(ent, pev_solid, SOLID_TRIGGER)
	set_pev(ent, pev_movetype, MOVETYPE_TOSS)
	set_pev(ent, pev_owner, id)
	cso_set_rendering(ent, kRenderFxNone, 255, 255, 255, kRenderTransAlpha, clamp(get_pcvar_num(g_pcv_alpha), 0, 255))

	new Float:life = get_pcvar_float(g_pcv_life)
	if (life < 1.0) life = 1.0
	set_pev(ent, pev_nextthink, get_gametime() + life)

	client_print(id, print_center, "[CSO] Ловушка установлена")
	return true
}

bool:trap_nearby(const Float:origin[3])
{
	new Float:spacing = get_pcvar_float(g_pcv_spacing)
	new ent = -1, Float:pos[3]
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", TRAP_CLASS)) > 0)
	{
		pev(ent, pev_origin, pos)
		if (get_distance_f(origin, pos) < spacing)
			return true
	}
	return false
}

public fw_trap_think(ent)
{
	if (pev_valid(ent))
		engfunc(EngFunc_RemoveEntity, ent)
}

public fw_trap_touch(ent, victim)
{
	if (!pev_valid(ent) || !cso_is_valid_player(victim) || !is_user_alive(victim))
		return PLUGIN_CONTINUE
	if (pev(ent, pev_flags) & FL_KILLME) // уже сработала в этом кадре
		return PLUGIN_CONTINUE
	if (zp_get_user_zombie(victim) || g_trapped[victim])
		return PLUGIN_CONTINUE
	if (zp_get_user_survivor(victim) && !get_pcvar_num(g_pcv_survivor))
		return PLUGIN_CONTINUE

	new Float:hold = get_pcvar_float(g_pcv_hold)
	if (hold <= 0.0)
		return PLUGIN_CONTINUE

	// ловушка одноразовая; удаляем через FL_KILLME — внутри touch удалять напрямую небезопасно
	set_pev(ent, pev_solid, SOLID_NOT)
	set_pev(ent, pev_flags, pev(ent, pev_flags) | FL_KILLME)

	g_trapped[victim] = true
	set_pev(victim, pev_velocity, Float:{ 0.0, 0.0, 0.0 })
	ExecuteHamB(CSO_Ham_ResetMaxSpeed, victim)
	remove_task(victim + TASK_RELEASE)
	set_task(hold, "task_release", victim + TASK_RELEASE)

	client_print(victim, print_center, "[CSO] Вы попали в ловушку!")
	return PLUGIN_CONTINUE
}

public fw_PlayerPreThink(id)
{
	if (!g_trapped[id] || !is_user_alive(id))
		return FMRES_IGNORED

	// держим на месте: гасим горизонтальную скорость и прыжок вверх
	new Float:vel[3]
	pev(id, pev_velocity, vel)
	vel[0] = 0.0
	vel[1] = 0.0
	if (vel[2] > 0.0) vel[2] = 0.0
	set_pev(id, pev_velocity, vel)
	return FMRES_IGNORED
}

public fw_ResetMaxSpeed_Post(id)
{
	if (g_trapped[id] && is_user_alive(id))
		set_pev(id, pev_maxspeed, 1.0)
	return HAM_IGNORED
}

public task_release(taskid)
{
	release(taskid - TASK_RELEASE, true)
}

release(id, bool:recalc)
{
	remove_task(id + TASK_RELEASE)
	if (!g_trapped[id])
		return
	g_trapped[id] = false
	if (recalc && is_user_alive(id))
		ExecuteHamB(CSO_Ham_ResetMaxSpeed, id)
}

public zp_user_infected_post(id, infector, nemesis)
{
	release(id, true)
	cso_reset_cooldown(id)
	if (cso_is_class_zombie(id))
		cso_print_skill_help(id, ZC_NAME)
}

public zp_user_humanized_post(id, survivor)
{
	release(id, true)
}

public fw_Killed_Post(victim, attacker, shouldgib)
{
	release(victim, false)
}

public client_disconnected(id)
{
	release(id, false)
	cso_remove_entities_by_class(TRAP_CLASS, id)
	cso_reset_cooldown(id)
}

public zp_round_ended(winteam)
{
	cso_remove_entities_by_class(TRAP_CLASS)
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
		release(id, true)
}

public ev_new_round()
{
	cso_remove_entities_by_class(TRAP_CLASS)
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
	{
		release(id, false)
		cso_reset_cooldown(id)
	}
}
