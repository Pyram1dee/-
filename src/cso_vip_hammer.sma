/*
 * CSO Zombie — VIP Hammer
 * VIP определяется штатной системой доступа AMXX (users.ini), флаг — CVAR cso_vip_flag.
 * Молот заменяет нож живого VIP-человека (не выжившего). Пока молот в руках:
 *  - скорость  × cso_vip_hammer_speed_multiplier   (post ResetMaxSpeed, после ядра ZP);
 *  - гравитация × cso_vip_hammer_gravity_multiplier (восстанавливается при смене оружия);
 *  - урон по зомби × cso_vip_hammer_damage_multiplier;
 *  - отбрасывание зомби: cso_vip_hammer_knockback × cso_vip_hammer_knockback_multiplier.
 * Отдельной усиленной атаки нет (TECH_SPEC п. 6): вторичная атака ножа
 * блокируется (cso_vip_hammer_block_attack2 1). Огнестрельное оружие и покупки не затрагиваются.
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <zombieplague>

#define PLUGIN  "[CSO] VIP Hammer"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#define MAXP 32
#define Ham_ResetMaxSpeed Ham_Item_PreFrame
#define FROZEN_GRAVITY 99999.0
#define TASK_SPAWN 52100

// Собственные модели проекта (assets/models/cso, генератор tools/mdl); без них остаётся обычный нож
new const HAMMER_V_MODEL[] = "models/cso/v_hammer.mdl"
new const HAMMER_P_MODEL[] = "models/cso/p_hammer.mdl"

new bool:g_have_v_model, bool:g_have_p_model
new g_pcv_enable, g_pcv_flag, g_pcv_speed, g_pcv_grav, g_pcv_damage, g_pcv_kb, g_pcv_kb_mult, g_pcv_block2
new bool:g_disabled_by_user[MAXP + 1]
new bool:g_grav_applied[MAXP + 1]
new Float:g_grav_base[MAXP + 1]

public plugin_precache()
{
	if (file_exists(HAMMER_V_MODEL))
	{
		precache_model(HAMMER_V_MODEL)
		g_have_v_model = true
	}
	else
		log_amx("[CSO] Нет модели %s — у VIP останется модель ножа", HAMMER_V_MODEL)

	if (file_exists(HAMMER_P_MODEL))
	{
		precache_model(HAMMER_P_MODEL)
		g_have_p_model = true
	}
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_enable = register_cvar("cso_vip_hammer_enable", "1")
	g_pcv_flag   = register_cvar("cso_vip_flag", "t")
	g_pcv_speed  = register_cvar("cso_vip_hammer_speed_multiplier", "1.1")
	g_pcv_grav   = register_cvar("cso_vip_hammer_gravity_multiplier", "0.85")
	g_pcv_damage = register_cvar("cso_vip_hammer_damage_multiplier", "1.5")
	g_pcv_kb     = register_cvar("cso_vip_hammer_knockback", "250.0")
	g_pcv_kb_mult = register_cvar("cso_vip_hammer_knockback_multiplier", "1.5")
	g_pcv_block2 = register_cvar("cso_vip_hammer_block_attack2", "1")

	register_clcmd("say /hammer", "cmd_toggle")
	register_clcmd("say_team /hammer", "cmd_toggle")

	RegisterHam(Ham_Item_Deploy, "weapon_knife", "fw_Knife_Deploy_Post", 1)
	RegisterHam(Ham_Item_Holster, "weapon_knife", "fw_Knife_Holster_Post", 1)
	RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_knife", "fw_Knife_Attack2_Pre")
	RegisterHam(Ham_ResetMaxSpeed, "player", "fw_ResetMaxSpeed_Post", 1)
	RegisterHam(Ham_TakeDamage, "player", "fw_TakeDamage_Pre")
	RegisterHam(Ham_TakeDamage, "player", "fw_TakeDamage_Post", 1)
	RegisterHam(Ham_Killed, "player", "fw_Killed_Post", 1)
	RegisterHam(Ham_Spawn, "player", "fw_Spawn_Post", 1)
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
}

// ---------------------------------------------------------------------------
// Состояние
// ---------------------------------------------------------------------------

bool:is_vip(id)
{
	new flags[24]
	get_pcvar_string(g_pcv_flag, flags, charsmax(flags))
	new need = read_flags(flags)
	return (need != 0 && (get_user_flags(id) & need) == need)
}

// Может ли игрок пользоваться молотом сейчас (независимо от оружия в руках)
bool:has_hammer(id)
{
	if (!get_pcvar_num(g_pcv_enable) || g_disabled_by_user[id])
		return false
	if (!(1 <= id <= MAXP) || !is_user_alive(id))
		return false
	if (zp_get_user_zombie(id) || zp_get_user_survivor(id))
		return false
	return is_vip(id)
}

bool:hammer_in_hands(id)
{
	return (has_hammer(id) && get_user_weapon(id) == CSW_KNIFE)
}

public cmd_toggle(id)
{
	if (!is_vip(id))
	{
		client_print(id, print_chat, "[CSO] VIP Hammer доступен только VIP")
		return PLUGIN_HANDLED
	}
	g_disabled_by_user[id] = !g_disabled_by_user[id]
	client_print(id, print_chat, "[CSO] VIP Hammer %s", g_disabled_by_user[id] ? "выключен" : "включён")
	refresh(id)
	return PLUGIN_HANDLED
}

// Пересчитать модели/скорость/гравитацию для текущего оружия
refresh(id)
{
	if (!is_user_alive(id))
		return
	new weapon = get_user_weapon(id)
	if (weapon == CSW_KNIFE)
	{
		if (has_hammer(id))
		{
			apply_models(id)
			apply_gravity(id)
		}
		else
		{
			restore_gravity(id)
			if (g_have_v_model && is_vip(id) && !zp_get_user_zombie(id))
			{
				set_pev(id, pev_viewmodel2, "models/v_knife.mdl")
				set_pev(id, pev_weaponmodel2, "models/p_knife.mdl")
			}
		}
	}
	ExecuteHamB(Ham_ResetMaxSpeed, id)
}

apply_models(id)
{
	if (g_have_v_model)
		set_pev(id, pev_viewmodel2, HAMMER_V_MODEL)
	if (g_have_p_model)
		set_pev(id, pev_weaponmodel2, HAMMER_P_MODEL)
}

apply_gravity(id)
{
	if (g_grav_applied[id])
		return
	new Float:grav
	pev(id, pev_gravity, grav)
	if (grav >= FROZEN_GRAVITY)
		return
	g_grav_base[id] = grav
	g_grav_applied[id] = true
	set_pev(id, pev_gravity, grav * floatclamp(get_pcvar_float(g_pcv_grav), 0.1, 2.0))
}

restore_gravity(id)
{
	if (!g_grav_applied[id])
		return
	g_grav_applied[id] = false
	if (is_user_alive(id))
		set_pev(id, pev_gravity, g_grav_base[id])
}

// Сброс без восстановления — ядро ZP выставит гравитацию само (заражение, спавн)
drop_state(id)
{
	g_grav_applied[id] = false
}

// ---------------------------------------------------------------------------
// Хуки оружия
// ---------------------------------------------------------------------------

public fw_Knife_Deploy_Post(weapon)
{
	new id = pev(weapon, pev_owner)
	if (!(1 <= id <= MAXP) || !has_hammer(id))
		return HAM_IGNORED
	apply_models(id)
	apply_gravity(id)
	return HAM_IGNORED
}

public fw_Knife_Holster_Post(weapon)
{
	new id = pev(weapon, pev_owner)
	if (1 <= id <= MAXP)
		restore_gravity(id)
	return HAM_IGNORED
}

public fw_Knife_Attack2_Pre(weapon)
{
	if (!get_pcvar_num(g_pcv_block2))
		return HAM_IGNORED
	new id = pev(weapon, pev_owner)
	if ((1 <= id <= MAXP) && has_hammer(id))
		return HAM_SUPERCEDE // у молота нет отдельной усиленной атаки
	return HAM_IGNORED
}

public fw_ResetMaxSpeed_Post(id)
{
	if (!hammer_in_hands(id))
		return HAM_IGNORED
	new Float:speed
	pev(id, pev_maxspeed, speed)
	if (speed <= 1.5) // freezetime или обездвижен ловушкой
		return HAM_IGNORED
	set_pev(id, pev_maxspeed, speed * floatclamp(get_pcvar_float(g_pcv_speed), 0.1, 3.0))
	return HAM_IGNORED
}

bool:is_hammer_hit(victim, inflictor, attacker)
{
	if (!(1 <= attacker <= MAXP) || attacker == victim || inflictor != attacker)
		return false
	if (!hammer_in_hands(attacker))
		return false
	return (is_user_alive(victim) && zp_get_user_zombie(victim))
}

public fw_TakeDamage_Pre(victim, inflictor, attacker, Float:damage, damagebits)
{
	if (!is_hammer_hit(victim, inflictor, attacker))
		return HAM_IGNORED
	SetHamParamFloat(4, damage * floatclamp(get_pcvar_float(g_pcv_damage), 0.0, 10.0))
	return HAM_HANDLED
}

public fw_TakeDamage_Post(victim, inflictor, attacker, Float:damage, damagebits)
{
	if (!is_hammer_hit(victim, inflictor, attacker))
		return HAM_IGNORED

	new Float:power = get_pcvar_float(g_pcv_kb) * get_pcvar_float(g_pcv_kb_mult)
	if (power <= 0.0)
		return HAM_IGNORED

	new Float:a[3], Float:v[3], Float:vel[3]
	pev(attacker, pev_origin, a)
	pev(victim, pev_origin, v)
	new Float:dir[3]
	dir[0] = v[0] - a[0]
	dir[1] = v[1] - a[1]
	new Float:len = floatsqroot(dir[0] * dir[0] + dir[1] * dir[1])
	if (len < 1.0)
		return HAM_IGNORED

	pev(victim, pev_velocity, vel)
	vel[0] += dir[0] / len * power
	vel[1] += dir[1] / len * power
	if (vel[2] < 100.0) vel[2] = 100.0 // небольшой подброс, чтобы трение не гасило толчок
	set_pev(victim, pev_velocity, vel)
	return HAM_IGNORED
}

// ---------------------------------------------------------------------------
// Сбросы состояния
// ---------------------------------------------------------------------------

public zp_user_infected_post(id, infector, nemesis)
{
	drop_state(id)
}

public zp_user_humanized_post(id, survivor)
{
	drop_state(id)
	if (is_vip(id))
		refresh(id)
}

public fw_Spawn_Post(id)
{
	drop_state(id)
	remove_task(id + TASK_SPAWN)
	if (is_user_alive(id) && is_vip(id))
		set_task(0.2, "task_after_spawn", id + TASK_SPAWN) // после того как ядро ZP выставит гравитацию
}

public task_after_spawn(taskid)
{
	new id = taskid - TASK_SPAWN
	if (!has_hammer(id))
		return
	client_print(id, print_chat, "[CSO] У вас VIP Hammer (нож). /hammer — вкл/выкл")
	refresh(id)
}

public fw_Killed_Post(victim, attacker, shouldgib)
{
	drop_state(victim)
}

public client_disconnected(id)
{
	remove_task(id + TASK_SPAWN)
	drop_state(id)
	g_disabled_by_user[id] = false
}

public zp_round_ended(winteam)
{
	for (new id = 1; id <= MAXP; id++)
		restore_gravity(id)
}

public ev_new_round()
{
	for (new id = 1; id <= MAXP; id++)
		drop_state(id)
}
