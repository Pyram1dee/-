/*
 * CSO Zombie — класс "Гробовщик" (Undertaker / Stamper)
 * Способность "Stamping" по образцу CSO (режим Zombie Hero Classic). Клавиша по ТЗ: G.
 *  - Iron Maiden ставится перед собой; нельзя в воздухе и сидя (как в CSO);
 *  - одна дева на игрока одновременно (cso_undertaker_max_coffins 1);
 *  - при установке Гробовщик ненадолго замирает (cso_undertaker_deploy_freeze);
 *  - аура: люди в радиусе и прямой видимости замедлены (по умолчанию на 90 %);
 *  - прочность 3000; люди ломают выстрелами, удар зомби наносит фиксированный урон
 *    (600 = 5 ударов, как в CSO — делает возможным "Coffin Jump");
 *  - при разрушении (и по истечении времени, если включено) — взрыв с отбрасыванием
 *    всех игроков в радиусе; урон взрыва по умолчанию выключен;
 *  - место проверяется hull-трассой: дева не появится в стене или в игроке;
 *  - удаление в конце/начале раунда и при выходе владельца.
 * Восстановление брони союзников из CSO не переносится: у зомби ZP 4.3 нет брони.
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <engine>
#include <zombieplague>
#include <cso_common>

#define PLUGIN  "[CSO] ZClass: Undertaker"
#define VERSION "0.2.0"
#define AUTHOR  "CSO Custom Project"

#define TASK_UNFREEZE 51300
#define THINK_STEP 0.2

new const COFFIN_CLASS[] = "cso_coffin"
// Собственная модель проекта: assets/models/cso/coffin.mdl (генератор tools/mdl/build_models.py).
new const COFFIN_MODEL[] = "models/cso/coffin.mdl"
new const COFFIN_MODEL_FALLBACK[] = "models/w_weaponbox.mdl" // есть в базовой CS 1.6
new const Float:COFFIN_MINS[3] = { -16.0, -16.0, 0.0 }
new const Float:COFFIN_MAXS[3] = { 16.0, 16.0, 64.0 } // стоячий гроб из tools/mdl/build_models.py

// ресурсы базовой CS 1.6
new const SPR_EXPLODE[] = "sprites/zerogxplode.spr"
new const SPR_RING[]    = "sprites/shockwave.spr"
new const SND_EXPLODE[] = "weapons/explode3.wav"

new const ZC_NAME[]  = "Undertaker"
new const ZC_INFO[]  = "Iron Maiden [G]"
new const ZC_MODEL[] = "zombie_source"
new const ZC_CLAW[]  = "v_knife_zombie.mdl"
const ZC_HEALTH      = 2500
const ZC_SPEED       = 235
const Float:ZC_GRAV  = 1.0
const Float:ZC_KNOCK = 0.9

new g_coffin_model[64], g_spr_explode, g_spr_ring
new g_pcv_max, g_pcv_life, g_pcv_health, g_pcv_cooldown, g_pcv_distance, g_pcv_slope
new g_pcv_freeze, g_pcv_slow_radius, g_pcv_slow_mult, g_pcv_survivor, g_pcv_zombie_hit
new g_pcv_exp_radius, g_pcv_exp_power, g_pcv_exp_damage, g_pcv_exp_expire

new Float:g_freeze_until[CSO_MAXPLAYERS + 1]
new Float:g_slow_until[CSO_MAXPLAYERS + 1]

public plugin_precache()
{
	g_cso_class = zp_register_zombie_class(ZC_NAME, ZC_INFO, ZC_MODEL, ZC_CLAW, ZC_HEALTH, ZC_SPEED, ZC_GRAV, ZC_KNOCK)
	cso_precache_model_safe(COFFIN_MODEL, COFFIN_MODEL_FALLBACK, g_coffin_model, charsmax(g_coffin_model))
	g_spr_explode = precache_model(SPR_EXPLODE)
	g_spr_ring = precache_model(SPR_RING)
	precache_sound(SND_EXPLODE)
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_max         = register_cvar("cso_undertaker_max_coffins", "1")
	g_pcv_life        = register_cvar("cso_undertaker_lifetime", "12.0")
	g_pcv_health      = register_cvar("cso_undertaker_coffin_health", "3000")
	g_pcv_cooldown    = register_cvar("cso_undertaker_cooldown", "20.0")
	g_pcv_distance    = register_cvar("cso_undertaker_distance", "64.0")
	g_pcv_slope       = register_cvar("cso_undertaker_max_slope", "0.7") // мин. нормаль Z поверхности
	g_pcv_freeze      = register_cvar("cso_undertaker_deploy_freeze", "0.8")
	g_pcv_slow_radius = register_cvar("cso_undertaker_slow_radius", "250.0")
	g_pcv_slow_mult   = register_cvar("cso_undertaker_slow_multiplier", "0.1") // 0.1 = замедление на 90 %
	g_pcv_survivor    = register_cvar("cso_undertaker_affect_survivor", "0")
	g_pcv_zombie_hit  = register_cvar("cso_undertaker_zombie_hit_damage", "600") // 0 — зомби не повреждают деву
	g_pcv_exp_radius  = register_cvar("cso_undertaker_explode_radius", "250.0")
	g_pcv_exp_power   = register_cvar("cso_undertaker_explode_knockback", "700.0")
	g_pcv_exp_damage  = register_cvar("cso_undertaker_explode_damage", "0")
	g_pcv_exp_expire  = register_cvar("cso_undertaker_explode_on_expire", "1")

	cso_skill_init(CSO_KEY_G, g_pcv_cooldown)

	register_think(COFFIN_CLASS, "fw_coffin_think")
	RegisterHam(Ham_TakeDamage, "info_target", "fw_TakeDamage_Pre")
	RegisterHam(CSO_Ham_ResetMaxSpeed, "player", "fw_ResetMaxSpeed_Post", 1)
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
	set_task(THINK_STEP, "task_expire_slow", _, _, _, "b")
}

// ---------------------------------------------------------------------------
// Установка
// ---------------------------------------------------------------------------

public bool:cso_skill_activate(id)
{
	new max_coffins = get_pcvar_num(g_pcv_max)
	if (max_coffins <= 0)
		return false

	new flags = pev(id, pev_flags)
	if (!(flags & FL_ONGROUND))
	{
		client_print(id, print_center, "[CSO] Iron Maiden нельзя ставить в воздухе")
		return false
	}
	if (flags & FL_DUCKING)
	{
		client_print(id, print_center, "[CSO] Iron Maiden нельзя ставить сидя")
		return false
	}
	if (count_coffins(id) >= max_coffins)
	{
		client_print(id, print_center, "[CSO] Iron Maiden уже стоит")
		return false
	}

	new Float:origin[3]
	if (!find_place(id, origin))
	{
		client_print(id, print_center, "[CSO] Здесь нельзя поставить Iron Maiden")
		return false
	}
	if (!create_coffin(id, origin))
		return false

	// Гробовщик замирает на время установки
	new Float:freeze = get_pcvar_float(g_pcv_freeze)
	if (freeze > 0.0)
	{
		g_freeze_until[id] = get_gametime() + freeze
		set_pev(id, pev_velocity, Float:{ 0.0, 0.0, 0.0 })
		ExecuteHamB(CSO_Ham_ResetMaxSpeed, id)
		remove_task(id + TASK_UNFREEZE)
		set_task(freeze + 0.05, "task_unfreeze", id + TASK_UNFREEZE)
	}
	return true
}

// Ищет точку пола перед игроком, где поместится дева
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

	// 3. hull 32x32x72 (HULL_HUMAN, центр в середине) покрывает деву 32x32x64 — нет стен и игроков
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
	angles[1] += 180.0 // лицом к Гробовщику
	set_pev(ent, pev_angles, angles)

	set_pev(ent, pev_solid, SOLID_BBOX)
	set_pev(ent, pev_movetype, MOVETYPE_TOSS)
	// владелец в iuser1, а не pev_owner: иначе трассы Гробовщика игнорируют деву и Coffin Jump невозможен.
	// Застревание исключено проверкой HULL_HUMAN (с учётом самого Гробовщика) и дистанцией >= 40.
	set_pev(ent, pev_iuser1, id)
	set_pev(ent, pev_takedamage, DAMAGE_YES)
	set_pev(ent, pev_health, float(max(1, get_pcvar_num(g_pcv_health))))

	new Float:life = floatmax(get_pcvar_float(g_pcv_life), 1.0)
	set_pev(ent, pev_fuser1, get_gametime() + life) // время окончания
	set_pev(ent, pev_nextthink, get_gametime() + THINK_STEP)
	return true
}

// ---------------------------------------------------------------------------
// Аура замедления и время жизни
// ---------------------------------------------------------------------------

public fw_coffin_think(ent)
{
	if (!pev_valid(ent))
		return

	new Float:now = get_gametime(), Float:expire
	pev(ent, pev_fuser1, expire)
	if (now >= expire)
	{
		if (get_pcvar_num(g_pcv_exp_expire))
			explode(ent)
		else
			engfunc(EngFunc_RemoveEntity, ent)
		return
	}

	slow_aura(ent, now)
	set_pev(ent, pev_nextthink, now + THINK_STEP)
}

slow_aura(ent, Float:now)
{
	new Float:radius = get_pcvar_float(g_pcv_slow_radius)
	if (radius <= 0.0)
		return

	new Float:center[3], Float:pos[3], Float:frac
	pev(ent, pev_origin, center)
	center[2] += 48.0

	new tr = create_tr2()
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
	{
		if (!is_user_alive(id) || zp_get_user_zombie(id))
			continue
		if (zp_get_user_survivor(id) && !get_pcvar_num(g_pcv_survivor))
			continue

		pev(id, pev_origin, pos)
		if (get_distance_f(center, pos) > radius)
			continue

		engfunc(EngFunc_TraceLine, center, pos, IGNORE_MONSTERS, ent, tr)
		get_tr2(tr, TR_flFraction, frac)
		if (frac < 1.0)
			continue // за стеной не действует

		new bool:was = (now < g_slow_until[id])
		g_slow_until[id] = now + THINK_STEP * 2.0
		if (!was)
			ExecuteHamB(CSO_Ham_ResetMaxSpeed, id)
	}
	free_tr2(tr)
}

// Снимает замедление у тех, кто вышел из ауры
public task_expire_slow()
{
	new Float:now = get_gametime()
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
	{
		if (g_slow_until[id] > 0.0 && now >= g_slow_until[id])
		{
			g_slow_until[id] = 0.0
			if (is_user_alive(id))
				ExecuteHamB(CSO_Ham_ResetMaxSpeed, id)
		}
	}
}

public fw_ResetMaxSpeed_Post(id)
{
	if (!is_user_alive(id))
		return HAM_IGNORED

	new Float:now = get_gametime()
	if (now < g_freeze_until[id])
	{
		set_pev(id, pev_maxspeed, 1.0)
		return HAM_IGNORED
	}

	if (now < g_slow_until[id] && !zp_get_user_zombie(id))
	{
		new Float:speed
		pev(id, pev_maxspeed, speed)
		if (speed > 1.0)
			set_pev(id, pev_maxspeed, speed * floatclamp(get_pcvar_float(g_pcv_slow_mult), 0.05, 1.0))
	}
	return HAM_IGNORED
}

public task_unfreeze(taskid)
{
	new id = taskid - TASK_UNFREEZE
	g_freeze_until[id] = 0.0
	if (is_user_alive(id))
		ExecuteHamB(CSO_Ham_ResetMaxSpeed, id)
}

// ---------------------------------------------------------------------------
// Урон и взрыв
// ---------------------------------------------------------------------------

public fw_TakeDamage_Pre(ent, inflictor, attacker, Float:damage, damagebits)
{
	if (!pev_valid(ent))
		return HAM_IGNORED

	static classname[32]
	pev(ent, pev_classname, classname, charsmax(classname))
	if (!equal(classname, COFFIN_CLASS))
		return HAM_IGNORED

	// удар зомби — фиксированный урон (0 — зомби не повреждают деву)
	if (cso_is_valid_player(attacker) && zp_get_user_zombie(attacker))
	{
		new Float:hit = get_pcvar_float(g_pcv_zombie_hit)
		if (hit <= 0.0)
			return HAM_SUPERCEDE
		damage = hit
	}

	new Float:health
	pev(ent, pev_health, health)
	if (health - damage <= 0.0)
	{
		explode(ent)
		return HAM_SUPERCEDE
	}
	set_pev(ent, pev_health, health - damage)
	return HAM_SUPERCEDE
}

explode(ent)
{
	new Float:center[3]
	pev(ent, pev_origin, center)
	center[2] += 32.0
	new owner = pev(ent, pev_iuser1)

	// сначала убираем деву, чтобы урон/трассы её не задевали
	set_pev(ent, pev_takedamage, DAMAGE_NO)
	set_pev(ent, pev_solid, SOLID_NOT)
	set_pev(ent, pev_flags, pev(ent, pev_flags) | FL_KILLME)

	explosion_fx(center)

	new Float:radius = get_pcvar_float(g_pcv_exp_radius)
	new Float:power = get_pcvar_float(g_pcv_exp_power)
	new Float:dmg = get_pcvar_float(g_pcv_exp_damage)
	if (radius <= 0.0)
		return

	new Float:pos[3], Float:dir[3], Float:vel[3], Float:dist, Float:k
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
	{
		if (!is_user_alive(id))
			continue
		pev(id, pev_origin, pos)
		dist = get_distance_f(center, pos)
		if (dist > radius)
			continue

		k = 1.0 - dist / radius // сильнее у центра
		dir[0] = pos[0] - center[0]
		dir[1] = pos[1] - center[1]
		new Float:len = floatsqroot(dir[0] * dir[0] + dir[1] * dir[1])
		if (len > 1.0)
		{
			dir[0] /= len
			dir[1] /= len
		}
		else
		{
			dir[0] = 0.0
			dir[1] = 0.0 // стоит прямо над девой — только вверх (Coffin Jump)
		}

		pev(id, pev_velocity, vel)
		vel[0] += dir[0] * power * k
		vel[1] += dir[1] * power * k
		vel[2] = floatmax(vel[2], 0.0) + power * 0.6 * k + 150.0
		set_pev(id, pev_velocity, vel)

		// урон без атакующего-зомби: иначе ZP посчитает его заражающей атакой
		if (dmg > 0.0)
			ExecuteHamB(Ham_TakeDamage, id, ent, 0, dmg * k, DMG_BLAST)
	}

	if (cso_is_valid_player(owner))
		client_print(owner, print_center, "[CSO] Iron Maiden взорвалась")
}

explosion_fx(const Float:c[3])
{
	engfunc(EngFunc_MessageBegin, MSG_PVS, SVC_TEMPENTITY, c, 0)
	write_byte(TE_EXPLOSION)
	engfunc(EngFunc_WriteCoord, c[0])
	engfunc(EngFunc_WriteCoord, c[1])
	engfunc(EngFunc_WriteCoord, c[2])
	write_short(g_spr_explode)
	write_byte(25)  // масштаб
	write_byte(20)  // частота кадров
	write_byte(TE_EXPLFLAG_NOSOUND)
	message_end()

	new Float:r = get_pcvar_float(g_pcv_exp_radius)
	engfunc(EngFunc_MessageBegin, MSG_PVS, SVC_TEMPENTITY, c, 0)
	write_byte(TE_BEAMCYLINDER)
	engfunc(EngFunc_WriteCoord, c[0])
	engfunc(EngFunc_WriteCoord, c[1])
	engfunc(EngFunc_WriteCoord, c[2] - 28.0)
	engfunc(EngFunc_WriteCoord, c[0])
	engfunc(EngFunc_WriteCoord, c[1])
	engfunc(EngFunc_WriteCoord, c[2] - 28.0 + r)
	write_short(g_spr_ring)
	write_byte(0)   // стартовый кадр
	write_byte(0)   // частота
	write_byte(4)   // время жизни
	write_byte(30)  // ширина
	write_byte(0)   // шум
	write_byte(90)  // R
	write_byte(140) // G
	write_byte(170) // B
	write_byte(200) // яркость
	write_byte(0)
	message_end()

	engfunc(EngFunc_EmitAmbientSound, 0, c, SND_EXPLODE, VOL_NORM, ATTN_NORM, 0, PITCH_NORM)
}

count_coffins(owner)
{
	new ent = -1, n = 0
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", COFFIN_CLASS)) > 0)
		if (pev(ent, pev_iuser1) == owner && !(pev(ent, pev_flags) & FL_KILLME))
			n++
	return n
}

remove_coffins(owner)
{
	new ent = -1
	while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", COFFIN_CLASS)) > 0)
		if (pev(ent, pev_iuser1) == owner)
			engfunc(EngFunc_RemoveEntity, ent)
}

// ---------------------------------------------------------------------------
// Сбросы
// ---------------------------------------------------------------------------

clear_player(id)
{
	remove_task(id + TASK_UNFREEZE)
	g_freeze_until[id] = 0.0
	g_slow_until[id] = 0.0
}

public zp_user_infected_post(id, infector, nemesis)
{
	clear_player(id)
	cso_reset_cooldown(id)
	if (cso_is_class_zombie(id))
		cso_print_skill_help(id, ZC_NAME)
}

public zp_user_humanized_post(id, survivor)
{
	clear_player(id)
}

public client_disconnected(id)
{
	remove_coffins(id)
	clear_player(id)
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
	{
		clear_player(id)
		cso_reset_cooldown(id)
	}
}
