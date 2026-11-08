/*
 * CSO Zombie — класс "Деймос" (Deimos)
 * Эффект в ТЗ не определён (TBD). ПРЕДЛОЖЕНИЕ до подтверждения по референсу:
 *   "Шок" — мгновенный луч вперёд на cso_deimos_range юнитов; у задетого
 *   человека выпадает оружие в руках (только основное/пистолет, не нож/гранаты).
 * Клавиша: предложение G (drop), подтвердить.
 *
 * API для Deimos Round (library "cso_deimos"):
 *   native cso_deimos_grant(id)        — выдать способность зомби (в т.ч. немезиде) на текущую жизнь
 *   native cso_deimos_get_class()      — id класса ZP
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <zombieplague>
#include <cso_common>

#define PLUGIN  "[CSO] ZClass: Deimos"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

new const BEAM_SPRITE[] = "sprites/laserbeam.spr" // есть в базовой CS 1.6

new const ZC_NAME[]  = "Deimos"
new const ZC_INFO[]  = "Шок: выбивает оружие [G]"
new const ZC_MODEL[] = "zombie_source"
new const ZC_CLAW[]  = "v_knife_zombie.mdl"
const ZC_HEALTH      = 2200
const ZC_SPEED       = 245
const Float:ZC_GRAV  = 0.95
const Float:ZC_KNOCK = 0.8

const DROPPABLE_BITSUM = (1<<CSW_P228)|(1<<CSW_SCOUT)|(1<<CSW_XM1014)|(1<<CSW_MAC10)|(1<<CSW_AUG)|(1<<CSW_ELITE)|(1<<CSW_FIVESEVEN)|(1<<CSW_UMP45)|(1<<CSW_SG550)|(1<<CSW_GALIL)|(1<<CSW_FAMAS)|(1<<CSW_USP)|(1<<CSW_GLOCK18)|(1<<CSW_AWP)|(1<<CSW_MP5NAVY)|(1<<CSW_M249)|(1<<CSW_M3)|(1<<CSW_M4A1)|(1<<CSW_TMP)|(1<<CSW_G3SG1)|(1<<CSW_DEAGLE)|(1<<CSW_SG552)|(1<<CSW_AK47)|(1<<CSW_P90)

new g_pcv_range, g_pcv_cooldown, g_pcv_survivor
new g_beam_spr

public plugin_natives()
{
	register_library("cso_deimos")
	register_native("cso_deimos_grant", "native_grant", 1)
	register_native("cso_deimos_get_class", "native_get_class", 1)
}

public plugin_precache()
{
	g_cso_class = zp_register_zombie_class(ZC_NAME, ZC_INFO, ZC_MODEL, ZC_CLAW, ZC_HEALTH, ZC_SPEED, ZC_GRAV, ZC_KNOCK)
	g_beam_spr = precache_model(BEAM_SPRITE)
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_range    = register_cvar("cso_deimos_range", "600.0")
	g_pcv_cooldown = register_cvar("cso_deimos_cooldown", "20.0")
	g_pcv_survivor = register_cvar("cso_deimos_affect_survivor", "0")

	cso_skill_init(CSO_KEY_G, g_pcv_cooldown)

	RegisterHam(Ham_Killed, "player", "fw_Killed_Post", 1)
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
}

public native_grant(id)
{
	// немезида допускается: так Deimos Round делает единственного Deimos
	if (!cso_is_valid_player(id) || !is_user_alive(id) || !zp_get_user_zombie(id))
		return false
	g_cso_granted[id] = true
	cso_reset_cooldown(id)
	cso_print_skill_help(id, ZC_NAME)
	return true
}

public native_get_class()
{
	return g_cso_class
}

public bool:cso_skill_activate(id)
{
	new Float:range = get_pcvar_float(g_pcv_range)
	if (range <= 0.0)
		return false

	new Float:start[3], Float:ofs[3], Float:angles[3], Float:fwd[3], Float:end[3]
	pev(id, pev_origin, start)
	pev(id, pev_view_ofs, ofs)
	start[2] += ofs[2]
	pev(id, pev_v_angle, angles)
	engfunc(EngFunc_MakeVectors, angles)
	global_get(glb_v_forward, fwd)
	for (new i = 0; i < 3; i++)
		end[i] = start[i] + fwd[i] * range

	new tr = create_tr2()
	engfunc(EngFunc_TraceLine, start, end, DONT_IGNORE_MONSTERS, id, tr)
	get_tr2(tr, TR_vecEndPos, end)
	new victim = get_tr2(tr, TR_pHit)
	free_tr2(tr)

	draw_beam(start, end)

	if (cso_is_valid_player(victim) && is_user_alive(victim) && !zp_get_user_zombie(victim))
	{
		if (zp_get_user_survivor(victim) && !get_pcvar_num(g_pcv_survivor))
			return true

		new weapon = get_user_weapon(victim)
		if (weapon > 0 && ((1 << weapon) & DROPPABLE_BITSUM))
		{
			new wname[32]
			get_weaponname(weapon, wname, charsmax(wname))
			engclient_cmd(victim, "drop", wname)
			client_print(victim, print_center, "[CSO] Деймос выбил у вас оружие!")
			client_print(id, print_center, "[CSO] Попадание!")
		}
	}
	return true // промах тоже тратит способность
}

draw_beam(const Float:start[3], const Float:end[3])
{
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
	write_byte(TE_BEAMPOINTS)
	engfunc(EngFunc_WriteCoord, start[0])
	engfunc(EngFunc_WriteCoord, start[1])
	engfunc(EngFunc_WriteCoord, start[2] - 10.0)
	engfunc(EngFunc_WriteCoord, end[0])
	engfunc(EngFunc_WriteCoord, end[1])
	engfunc(EngFunc_WriteCoord, end[2])
	write_short(g_beam_spr)
	write_byte(0)   // стартовый кадр
	write_byte(0)   // частота кадров
	write_byte(3)   // время жизни, 0.1 с
	write_byte(20)  // ширина
	write_byte(10)  // шум
	write_byte(200) // R
	write_byte(40)  // G
	write_byte(40)  // B
	write_byte(200) // яркость
	write_byte(0)   // скорость прокрутки
	message_end()
}

clear_state(id)
{
	g_cso_granted[id] = false
}

public zp_user_infected_post(id, infector, nemesis)
{
	clear_state(id)
	cso_reset_cooldown(id)
	if (cso_is_class_zombie(id))
		cso_print_skill_help(id, ZC_NAME)
}

public zp_user_humanized_post(id, survivor)
{
	clear_state(id)
}

public fw_Killed_Post(victim, attacker, shouldgib)
{
	clear_state(victim)
}

public client_disconnected(id)
{
	clear_state(id)
	cso_reset_cooldown(id)
}

public ev_new_round()
{
	for (new id = 1; id <= CSO_MAXPLAYERS; id++)
	{
		clear_state(id)
		cso_reset_cooldown(id)
	}
}
