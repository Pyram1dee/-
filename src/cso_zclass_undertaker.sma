/*
 * CSO Zombie — класс "Гробовщик" (Undertaker)
 * Способность: поставить гроб перед собой. Клавиша по ТЗ: G.
 *  - только на поверхности с наклоном не круче cso_undertaker_max_slope;
 *  - место проверяется hull-трассой: гроб не появится в стене или в игроке;
 *  - лимит активных гробов на игрока, старший удаляется (или отказ);
 *  - время жизни, прочность, урон от зомби не проходит;
 *  - все гробы удаляются в конце/начале раунда, гробы игрока — при выходе.
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <engine>
#include <zombieplague>
#include <cso_common>

#define PLUGIN  "[CSO] ZClass: Undertaker"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

new const COFFIN_CLASS[] = "cso_coffin"
// Собственная модель проекта: assets/models/cso/coffin.mdl (генератор tools/mdl/build_models.py).
new const COFFIN_MODEL[] = "models/cso/coffin.mdl"
new const COFFIN_MODEL_FALLBACK[] = "models/w_weaponbox.mdl" // есть в базовой CS 1.6
new const Float:COFFIN_MINS[3] = { -16.0, -16.0, 0.0 }
new const Float:COFFIN_MAXS[3] = { 16.0, 16.0, 64.0 } // стоячий гроб из tools/mdl/build_models.py

new const ZC_NAME[]  = "Undertaker"
new const ZC_INFO[]  = "Гроб [G]"
new const ZC_MODEL[] = "zombie_source"
new const ZC_CLAW[]  = "v_knife_zombie.mdl"
const ZC_HEALTH      = 2000
const ZC_SPEED       = 235
const Float:ZC_GRAV  = 1.0
const Float:ZC_KNOCK = 0.9

new g_coffin_model[64]
new g_pcv_max, g_pcv_life, g_pcv_health, g_pcv_cooldown, g_pcv_distance, g_pcv_slope, g_pcv_replace

public plugin_precache()
{
	g_cso_class = zp_register_zombie_class(ZC_NAME, ZC_INFO, ZC_MODEL, ZC_CLAW, ZC_HEALTH, ZC_SPEED, ZC_GRAV, ZC_KNOCK)
	cso_precache_model_safe(COFFIN_MODEL, COFFIN_MODEL_FALLBACK, g_coffin_model, charsmax(g_coffin_model))
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_max      = register_cvar("cso_undertaker_max_coffins", "2")
	g_pcv_life     = register_cvar("cso_undertaker_lifetime", "20.0")
	g_pcv_health   = register_cvar("cso_undertaker_coffin_health", "500")
	g_pcv_cooldown = register_cvar("cso_undertaker_cooldown", "10.0")
	g_pcv_distance = register_cvar("cso_undertaker_distance", "64.0")
	g_pcv_slope    = register_cvar("cso_undertaker_max_slope", "0.7") // мин. нормаль Z поверхности
	g_pcv_replace  = register_cvar("cso_undertaker_replace_oldest", "1")

	cso_skill_init(CSO_KEY_G, g_pcv_cooldown)

	register_think(COFFIN_CLASS, "fw_coffin_think")
	RegisterHam(Ham_TakeDamage, "info_target", "fw_TakeDamage_Pre")
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
}

public bool:cso_skill_activate(id)
{
	new max_coffins = get_pcvar_num(g_pcv_max)
	if (max_coffins <= 0)
		return false

	if (cso_count_entities_by_class(COFFIN_CLASS, id) >= max_coffins)
	{
		if (!get_pcvar_num(g_pcv_replace))
		{
			client_print(id, print_center, "[CSO] Достигнут лимит гробов (%d)", max_coffins)
			return false
		}
		remove_oldest_coffin(id)
	}

	new Float:origin[3]
	if (!find_place(id, origin))
	{
		client_print(id, print_center, "[CSO] Здесь нельзя поставить гроб")
		return false
	}

	if (!create_coffin(id, origin))
		return false

	client_print(id, print_center, "[CSO] Гроб установлен")
	return true
}

// Ищет точку пола перед игроком, где поместится гроб
bool:find_place(id, Float:out[3])
{
	new Float:start[3], Float:view_ofs[3], Float:angles[3], Float:fwd[3], Float:end[3]
	pev(id, pev_origin, start)
	pev(id, pev_view_ofs, view_ofs)
	start[2] += view_ofs[2]

	pev(id, pev_v_angle, angles)
	angles[0] = 0.0 // только горизонтальное направление
	engfunc(EngFunc_MakeVectors, angles)
	global_get(glb_v_forward, fwd)

	new Float:dist = floatclamp(get_pcvar_float(g_pcv_distance), 40.0, 200.0)
	end[0] = start[0] + fwd[0] * dist
	end[1] = start[1] + fwd[1] * dist
	end[2] = start[2]

	// 1. луч вперёд, чтобы не ставить за стену
	new tr = create_tr2()
	engfunc(EngFunc_TraceLine, start, end, IGNORE_MONSTERS, id, tr)
	new Float:frac
	get_tr2(tr, TR_flFraction, frac)
	get_tr2(tr, TR_vecEndPos, end)
	if (frac < 1.0)
	{
		// отступаем от стены на полгроба
		end[0] -= fwd[0] * 20.0
		end[1] -= fwd[1] * 20.0
	}

	// 2. вниз до пола
	new Float:down[3]
	down[0] = end[0]
	down[1] = end[1]
	down[2] = end[2] - 160.0
	engfunc(EngFunc_TraceLine, end, down, IGNORE_MONSTERS, id, tr)
	get_tr2(tr, TR_flFraction, frac)
	if (frac >= 1.0 || get_tr2(tr, TR_StartSolid))
	{
		free_tr2(tr)
		return false
	}

	new Float:normal[3], Float:floor[3]
	get_tr2(tr, TR_vecPlaneNormal, normal)
	get_tr2(tr, TR_vecEndPos, floor)
	if (normal[2] < get_pcvar_float(g_pcv_slope))
	{
		free_tr2(tr)
		return false
	}

	// 3. hull 32x32x72 (HULL_HUMAN, центр в середине) покрывает гроб 32x32x64 — нет стен и игроков
	new Float:center[3]
	center[0] = floor[0]
	center[1] = floor[1]
	center[2] = floor[2] + 37.0
	engfunc(EngFunc_TraceHull, center, center, DONT_IGNORE_MONSTERS, HULL_HUMAN, 0, tr)
	new bool:blocked = (get_tr2(tr, TR_StartSolid) || get_tr2(tr, TR_AllSolid))
	free_tr2(tr)
	if (blocked)
		return false

	out[0] = floor[0]
	out[1] = floor[1]
	out[2] = floor[2] + 1.0
	return true
}

bool:create_coffin(id, const Float:origin[3])
{
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"))
	if (!pev_valid(ent))
		return false

	set_pev(ent, pev_classname, COFFIN_CLASS)
	engfunc(EngFunc_SetModel, ent, g_coffin_model)
	engfunc(EngFunc_SetSize, ent, COFFIN_MINS, COFFIN_MAXS)
	engfunc(EngFunc_SetOrigin, ent, origin)

	new Float:angles[3]
	pev(id, pev_angles, angles)
	angles[0] = 0.0
	angles[2] = 0.0
	set_pev(ent, pev_angles, angles)

	set_pev(ent, pev_solid, SOLID_BBOX)
	set_pev(ent, pev_movetype, MOVETYPE_TOSS)
	set_pev(ent, pev_owner, id) // владелец проходит сквозь свой гроб — не застрянет
	set_pev(ent, pev_takedamage, DAMAGE_YES)
	set_pev(ent, pev_health, float(max(1, get_pcvar_num(g_pcv_health))))
	set_pev(ent, pev_fuser1, get_gametime()) // время создания — для удаления старшего

	new Float:life = get_pcvar_float(g_pcv_life)
	if (life < 1.0) life = 1.0
	set_pev(ent, pev_nextthink, get_gametime() + life)
	return true
}

remove_oldest_coffin(id)
{
	new ent = -1, oldest = 0
	new Float:best = 999999.0, Float:t
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", COFFIN_CLASS)) > 0)
	{
		if (pev(ent, pev_owner) != id)
			continue
		pev(ent, pev_fuser1, t)
		if (t < best)
		{
			best = t
			oldest = ent
		}
	}
	if (oldest)
		engfunc(EngFunc_RemoveEntity, oldest)
}

public fw_coffin_think(ent)
{
	if (pev_valid(ent))
		engfunc(EngFunc_RemoveEntity, ent) // истекло время жизни
}

public fw_TakeDamage_Pre(ent, inflictor, attacker, Float:damage, damagebits)
{
	if (!pev_valid(ent))
		return HAM_IGNORED

	static classname[32]
	pev(ent, pev_classname, classname, charsmax(classname))
	if (!equal(classname, COFFIN_CLASS))
		return HAM_IGNORED

	// гроб ломают только люди
	if (cso_is_valid_player(attacker) && zp_get_user_zombie(attacker))
		return HAM_SUPERCEDE

	return HAM_IGNORED
}

public zp_user_infected_post(id, infector, nemesis)
{
	cso_reset_cooldown(id)
	if (cso_is_class_zombie(id))
		cso_print_skill_help(id, ZC_NAME)
}

public client_disconnected(id)
{
	cso_remove_entities_by_class(COFFIN_CLASS, id)
	cso_reset_cooldown(id)
}

public zp_round_ended(winteam)
{
	cso_remove_entities_by_class(COFFIN_CLASS)
}

public ev_new_round()
{
	cso_remove_entities_by_class(COFFIN_CLASS)
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
		cso_reset_cooldown(id)
}
