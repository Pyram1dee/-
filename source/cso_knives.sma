/*
 * CSO Zombie — ножи людей (ТЗ §3, этап 3 меню оружия)
 *   1. Axe (Gravity Knife)  — пониженная гравитация, пока нож в руках
 *   2. Speed Knife          — повышенная скорость
 *   3. Dagger (Damage Knife)— повышенный урон в ближнем бою
 *   4. VIP Hammer           — только VIP: скорость + гравитация + урон + отбрасывание;
 *                             отдельной усиленной атаки нет (ПКМ заблокирована)
 * Бонусы действуют только у живого человека (не выжившего) и только с ножом в руках.
 * Заражение / смерть / выживший — бонусы сбрасываются (выбор восстанавливает меню оружия).
 * Модели — addons/amxmodx/configs/cso_knives.ini; нет файла → стандартный нож + запись в лог.
 *
 * API (library "cso_knives"):
 *   cso_knives_set(id, knife)  — выбрать нож (0..3); false, если нельзя (Hammer без VIP и т.п.)
 *   cso_knives_get(id)         — текущий нож или -1
 *   cso_knives_name(knife, out[], len)
 *   cso_knives_vip_only(knife)
 */

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <zombieplague>

#define PLUGIN  "[CSO] Knives"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#pragma reqlib cso_priv
native cso_is_vip(id)

#define MAXP 32
#define Ham_ResetMaxSpeed Ham_Item_PreFrame
#define FROZEN_GRAVITY 99999.0

enum
{
	KNIFE_AXE = 0,
	KNIFE_SPEED,
	KNIFE_DAGGER,
	KNIFE_HAMMER,
	KNIFE_COUNT
}

new const KNIFE_NAMES[KNIFE_COUNT][] = { "Axe (Gravity Knife)", "Speed Knife", "Dagger (Damage Knife)", "VIP Hammer" }
new const KNIFE_KEYS[KNIFE_COUNT][]  = { "axe", "speed", "dagger", "hammer" }

new g_vmodel[KNIFE_COUNT][64], g_pmodel[KNIFE_COUNT][64]

new g_knife[MAXP + 1] = { -1, ... }
new bool:g_grav_applied[MAXP + 1]
new Float:g_grav_base[MAXP + 1]

new g_pcv_axe_grav, g_pcv_speed_mult, g_pcv_dagger_dmg
new g_pcv_h_speed, g_pcv_h_grav, g_pcv_h_dmg, g_pcv_h_kb, g_pcv_h_kb_mult, g_pcv_h_block2

public plugin_natives()
{
	register_library("cso_knives")
	register_native("cso_knives_set", "native_set", 1)
	register_native("cso_knives_get", "native_get", 1)
	register_native("cso_knives_name", "native_name")
	register_native("cso_knives_vip_only", "native_vip_only", 1)
}

// --- модели из cso_knives.ini ---------------------------------------------------

public plugin_precache()
{
	new path[128]
	get_localinfo("amxx_configsdir", path, charsmax(path))
	add(path, charsmax(path), "/cso_knives.ini")

	new f = fopen(path, "rt")
	if (f)
	{
		new line[192], key[32], v[64], p[64]
		while (!feof(f))
		{
			fgets(f, line, charsmax(line))
			trim(line)
			if (!line[0] || line[0] == ';')
				continue
			// формат: ключ = v_модель , p_модель
			strtok(line, key, charsmax(key), line, charsmax(line), '=')
			trim(key)
			trim(line)
			strtok(line, v, charsmax(v), p, charsmax(p), ',')
			trim(v)
			trim(p)
			for (new k = 0; k < KNIFE_COUNT; k++)
				if (equali(key, KNIFE_KEYS[k]))
				{
					copy(g_vmodel[k], charsmax(g_vmodel[]), v)
					copy(g_pmodel[k], charsmax(g_pmodel[]), p)
				}
		}
		fclose(f)
	}
	else
		log_amx("[CSO] Нет %s — у всех ножей стандартная модель", path)

	for (new k = 0; k < KNIFE_COUNT; k++)
	{
		check_model(k, g_vmodel[k])
		check_model(k, g_pmodel[k])
	}
}

check_model(k, model[])
{
	if (!model[0])
	{
		log_amx("[CSO] Нож %s: модель не задана — стандартный нож (ресурс отсутствует)", KNIFE_NAMES[k])
		return
	}
	if (!file_exists(model))
	{
		log_amx("[CSO] Нож %s: нет файла %s — стандартный нож", KNIFE_NAMES[k], model)
		model[0] = 0
		return
	}
	precache_model(model)
}

// --- инициализация -------------------------------------------------------------

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_axe_grav    = register_cvar("cso_knife_axe_gravity", "0.75")    // множитель гравитации
	g_pcv_speed_mult  = register_cvar("cso_knife_speed_multiplier", "1.15")
	g_pcv_dagger_dmg  = register_cvar("cso_knife_dagger_damage", "1.5")   // множитель урона
	g_pcv_h_speed     = register_cvar("cso_vip_hammer_speed_multiplier", "1.1")
	g_pcv_h_grav      = register_cvar("cso_vip_hammer_gravity_multiplier", "0.85")
	g_pcv_h_dmg       = register_cvar("cso_vip_hammer_damage_multiplier", "1.5")
	g_pcv_h_kb        = register_cvar("cso_vip_hammer_knockback", "250.0")
	g_pcv_h_kb_mult   = register_cvar("cso_vip_hammer_knockback_multiplier", "1.5")
	g_pcv_h_block2    = register_cvar("cso_vip_hammer_block_attack2", "1")

	RegisterHam(Ham_Item_Deploy, "weapon_knife", "fw_Knife_Deploy_Post", 1)
	RegisterHam(Ham_Item_Holster, "weapon_knife", "fw_Knife_Holster_Post", 1)
	RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_knife", "fw_Knife_Attack2_Pre")
	RegisterHam(Ham_ResetMaxSpeed, "player", "fw_ResetMaxSpeed_Post", 1)
	RegisterHam(Ham_TakeDamage, "player", "fw_TakeDamage_Pre")
	RegisterHam(Ham_TakeDamage, "player", "fw_TakeDamage_Post", 1)
	RegisterHam(Ham_Killed, "player", "fw_Killed_Post", 1)
	RegisterHam(Ham_Spawn, "player", "fw_Spawn_Post", 1)
}

// --- natives -------------------------------------------------------------------

public bool:native_set(id, knife)
{
	if (!(1 <= id <= MAXP) || !(0 <= knife < KNIFE_COUNT))
		return false
	if (!is_user_alive(id) || zp_get_user_zombie(id) || zp_get_user_survivor(id))
		return false
	if (knife == KNIFE_HAMMER && !cso_is_vip(id))
		return false

	restore_gravity(id)
	g_knife[id] = knife
	refresh(id)
	return true
}

public native_get(id)
{
	return (1 <= id <= MAXP) ? g_knife[id] : -1
}

public native_name(plugin, params)
{
	new k = get_param(1)
	set_string(2, (0 <= k < KNIFE_COUNT) ? KNIFE_NAMES[k] : "", get_param(3))
}

public bool:native_vip_only(knife)
{
	return knife == KNIFE_HAMMER
}

// --- логика --------------------------------------------------------------------

bool:knife_active(id)
{
	if (!(1 <= id <= MAXP) || g_knife[id] < 0 || !is_user_alive(id))
		return false
	if (zp_get_user_zombie(id) || zp_get_user_survivor(id))
		return false
	if (g_knife[id] == KNIFE_HAMMER && !cso_is_vip(id)) // права могли снять
		return false
	return true
}

bool:in_hands(id)
{
	return knife_active(id) && get_user_weapon(id) == CSW_KNIFE
}

Float:speed_mult(k)
{
	switch (k)
	{
		case KNIFE_SPEED:  return floatclamp(get_pcvar_float(g_pcv_speed_mult), 0.1, 3.0)
		case KNIFE_HAMMER: return floatclamp(get_pcvar_float(g_pcv_h_speed), 0.1, 3.0)
	}
	return 1.0
}

Float:grav_mult(k)
{
	switch (k)
	{
		case KNIFE_AXE:    return floatclamp(get_pcvar_float(g_pcv_axe_grav), 0.1, 2.0)
		case KNIFE_HAMMER: return floatclamp(get_pcvar_float(g_pcv_h_grav), 0.1, 2.0)
	}
	return 1.0
}

Float:dmg_mult(k)
{
	switch (k)
	{
		case KNIFE_DAGGER: return floatclamp(get_pcvar_float(g_pcv_dagger_dmg), 0.0, 10.0)
		case KNIFE_HAMMER: return floatclamp(get_pcvar_float(g_pcv_h_dmg), 0.0, 10.0)
	}
	return 1.0
}

refresh(id)
{
	if (!is_user_alive(id))
		return
	if (get_user_weapon(id) == CSW_KNIFE)
	{
		if (knife_active(id))
		{
			apply_models(id)
			apply_gravity(id)
		}
		else
			restore_gravity(id)
	}
	ExecuteHamB(Ham_ResetMaxSpeed, id)
}

apply_models(id)
{
	new k = g_knife[id]
	set_pev(id, pev_viewmodel2, g_vmodel[k][0] ? g_vmodel[k] : "models/v_knife.mdl")
	set_pev(id, pev_weaponmodel2, g_pmodel[k][0] ? g_pmodel[k] : "models/p_knife.mdl")
}

apply_gravity(id)
{
	if (g_grav_applied[id])
		return
	new Float:mult = grav_mult(g_knife[id])
	if (mult == 1.0)
		return
	new Float:grav
	pev(id, pev_gravity, grav)
	if (grav >= FROZEN_GRAVITY)
		return
	g_grav_base[id] = grav
	g_grav_applied[id] = true
	set_pev(id, pev_gravity, grav * mult)
}

restore_gravity(id)
{
	if (!g_grav_applied[id])
		return
	g_grav_applied[id] = false
	if (is_user_alive(id))
		set_pev(id, pev_gravity, g_grav_base[id])
}

reset_player(id)
{
	g_knife[id] = -1
	g_grav_applied[id] = false // гравитацию выставит ядро ZP (спавн/заражение)
}

// --- хуки ----------------------------------------------------------------------

public fw_Knife_Deploy_Post(weapon)
{
	new id = pev(weapon, pev_owner)
	if (knife_active(id))
	{
		apply_models(id)
		apply_gravity(id)
	}
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
	new id = pev(weapon, pev_owner)
	if (in_hands(id) && g_knife[id] == KNIFE_HAMMER && get_pcvar_num(g_pcv_h_block2))
		return HAM_SUPERCEDE // у VIP Hammer нет отдельной усиленной атаки
	return HAM_IGNORED
}

public fw_ResetMaxSpeed_Post(id)
{
	if (!in_hands(id))
		return HAM_IGNORED
	new Float:mult = speed_mult(g_knife[id])
	if (mult == 1.0)
		return HAM_IGNORED
	new Float:speed
	pev(id, pev_maxspeed, speed)
	if (speed > 1.5) // не freezetime и не ловушка
		set_pev(id, pev_maxspeed, speed * mult)
	return HAM_IGNORED
}

bool:is_knife_hit(victim, inflictor, attacker)
{
	if (!(1 <= attacker <= MAXP) || attacker == victim || inflictor != attacker)
		return false
	return in_hands(attacker) && is_user_alive(victim) && zp_get_user_zombie(victim)
}

public fw_TakeDamage_Pre(victim, inflictor, attacker, Float:damage, damagebits)
{
	if (!is_knife_hit(victim, inflictor, attacker))
		return HAM_IGNORED
	new Float:mult = dmg_mult(g_knife[attacker])
	if (mult == 1.0)
		return HAM_IGNORED
	SetHamParamFloat(4, damage * mult)
	return HAM_HANDLED
}

public fw_TakeDamage_Post(victim, inflictor, attacker, Float:damage, damagebits)
{
	if (!is_knife_hit(victim, inflictor, attacker) || g_knife[attacker] != KNIFE_HAMMER)
		return HAM_IGNORED

	new Float:power = get_pcvar_float(g_pcv_h_kb) * get_pcvar_float(g_pcv_h_kb_mult)
	if (power <= 0.0)
		return HAM_IGNORED

	new Float:a[3], Float:v[3], Float:vel[3], Float:dir[2]
	pev(attacker, pev_origin, a)
	pev(victim, pev_origin, v)
	dir[0] = v[0] - a[0]
	dir[1] = v[1] - a[1]
	new Float:len = floatsqroot(dir[0] * dir[0] + dir[1] * dir[1])
	if (len < 1.0)
		return HAM_IGNORED

	pev(victim, pev_velocity, vel)
	vel[0] += dir[0] / len * power
	vel[1] += dir[1] / len * power
	if (vel[2] < 100.0) vel[2] = 100.0
	set_pev(victim, pev_velocity, vel)
	return HAM_IGNORED
}

public fw_Spawn_Post(id)
{
	if (1 <= id <= MAXP)
		reset_player(id) // меню оружия выдаст выбранный нож заново
}

public fw_Killed_Post(victim, attacker, shouldgib)
{
	if (1 <= victim <= MAXP)
		reset_player(victim)
}

public zp_user_infected_post(id, infector, nemesis)
{
	reset_player(id) // сброс человеческих бонусов при заражении
}

public zp_user_humanized_post(id, survivor)
{
	reset_player(id)
}

public client_disconnected(id)
{
	reset_player(id)
}
