/*
 * CSO Zombie — рывок человека (Human Dodge)
 * Механика по мотивам "[ZP] Human Dodge" (PomanoB): двойное нажатие W (+forward)
 * даёт рывок в направлении взгляда. Реализация своя, без кода оригинала:
 *  - двойное нажатие — по фронтам IN_FORWARD с интервалом cso_dodge_interval;
 *  - направление — только горизонтальный угол взгляда (без деления на расстояние до прицела);
 *  - нет рывка в воздухе (cso_dodge_ground_only), в заморозке/freezetime/ловушке Heavy (maxspeed <= 1);
 *  - кулдаун, флаги доступа и силы рывка — CVAR; сброс при выходе и в новом раунде.
 * Звук берётся из комплекта пользователя, если файл есть (assets/MANIFEST.md).
 */

#include <amxmodx>
#include <fakemeta>
#include <zombieplague>

#define PLUGIN  "[CSO] Human Dodge"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#define MAXP 32

new const DODGE_SOUND[] = "zombie_plague/human_dodge/human_dodge.wav"

new bool:g_have_sound
new g_pcv_enable, g_pcv_flags, g_pcv_interval, g_pcv_cooldown, g_pcv_speed, g_pcv_up, g_pcv_ground
new Float:g_last_tap[MAXP + 1]
new Float:g_next_dodge[MAXP + 1]

public plugin_precache()
{
	if (file_exists("sound/zombie_plague/human_dodge/human_dodge.wav"))
	{
		precache_sound(DODGE_SOUND)
		g_have_sound = true
	}
	else
		log_amx("[CSO] Нет звука sound/%s — рывок будет без звука", DODGE_SOUND)
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	g_pcv_enable   = register_cvar("cso_dodge_enable", "1")
	g_pcv_flags    = register_cvar("cso_dodge_flags", "")        // "" — все люди; например "t" — только VIP
	g_pcv_interval = register_cvar("cso_dodge_interval", "0.35") // макс. пауза между двумя нажатиями W
	g_pcv_cooldown = register_cvar("cso_dodge_cooldown", "10.0")
	g_pcv_speed    = register_cvar("cso_dodge_speed", "600.0")   // горизонтальная скорость рывка
	g_pcv_up       = register_cvar("cso_dodge_up", "250.0")      // вертикальная составляющая
	g_pcv_ground   = register_cvar("cso_dodge_ground_only", "1")

	register_forward(FM_PlayerPreThink, "fw_PlayerPreThink")
	register_event("HLTV", "ev_new_round", "a", "1=0", "2=0")
}

bool:has_access(id)
{
	new flags[24]
	get_pcvar_string(g_pcv_flags, flags, charsmax(flags))
	if (!flags[0])
		return true
	new need = read_flags(flags)
	return ((get_user_flags(id) & need) == need)
}

public fw_PlayerPreThink(id)
{
	if (!get_pcvar_num(g_pcv_enable) || !is_user_alive(id))
		return FMRES_IGNORED
	if (zp_get_user_zombie(id) || zp_get_user_survivor(id))
		return FMRES_IGNORED

	// только фронт нажатия W
	if (!(pev(id, pev_button) & IN_FORWARD) || (pev(id, pev_oldbuttons) & IN_FORWARD))
		return FMRES_IGNORED

	new Float:now = get_gametime()
	if (g_last_tap[id] > 0.0 && now - g_last_tap[id] <= get_pcvar_float(g_pcv_interval))
	{
		g_last_tap[id] = 0.0 // третье нажатие начнёт новую пару
		try_dodge(id, now)
	}
	else
		g_last_tap[id] = now

	return FMRES_IGNORED
}

try_dodge(id, Float:now)
{
	if (now < g_next_dodge[id] || !has_access(id))
		return

	if (get_pcvar_num(g_pcv_ground) && !(pev(id, pev_flags) & FL_ONGROUND))
		return

	// заморозка ZP, freezetime, ловушка Heavy выставляют maxspeed <= 1
	new Float:maxspeed
	pev(id, pev_maxspeed, maxspeed)
	if (maxspeed <= 1.0)
		return

	new Float:angles[3], Float:fwd[3], Float:vel[3]
	pev(id, pev_v_angle, angles)
	angles[0] = 0.0 // только горизонтальное направление
	angles[2] = 0.0
	engfunc(EngFunc_MakeVectors, angles)
	global_get(glb_v_forward, fwd)

	new Float:speed = floatclamp(get_pcvar_float(g_pcv_speed), 0.0, 2000.0)
	vel[0] = fwd[0] * speed
	vel[1] = fwd[1] * speed
	vel[2] = floatclamp(get_pcvar_float(g_pcv_up), 0.0, 1000.0)
	set_pev(id, pev_velocity, vel)

	g_next_dodge[id] = now + floatmax(get_pcvar_float(g_pcv_cooldown), 0.0)

	if (g_have_sound)
		emit_sound(id, CHAN_VOICE, DODGE_SOUND, VOL_NORM, ATTN_NORM, 0, PITCH_NORM)
}

public client_disconnected(id)
{
	g_last_tap[id] = 0.0
	g_next_dodge[id] = 0.0
}

public ev_new_round()
{
	for (new id = 1; id <= MAXP; id++)
	{
		g_last_tap[id] = 0.0
		g_next_dodge[id] = 0.0
	}
}
