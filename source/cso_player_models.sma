/*
 * CSO Zombie — выбор модели персонажа-человека (ТЗ §10)
 *  - список моделей — addons/amxmodx/configs/cso_player_models.ini:
 *        Название = модель [gold]
 *    (модель = models/player/<модель>/<модель>.mdl; пометка gold — эксклюзив для Gold);
 *  - precache только существующих файлов (+ <модель>T.mdl, если есть); отсутствующие
 *    пропускаются с записью в лог — случайными аналогами не подменяются;
 *  - выбор хранится по SteamID; «Случайная» — стандартный выбор ZP (строка HUMAN);
 *  - применяется после спавна человеком и после очеловечивания (zp_override_user_model);
 *    при заражении модель сбрасывает ядро ZP (модель зомби), при возвращении в люди — восстанавливается.
 * Команды: /models, cso_models, cso_models_gold (Gold меню → «Эксклюзивные модели»).
 * API (library "cso_models"): cso_models_current(id, out[], len)
 */

#include <amxmodx>
#include <hamsandwich>
#include <nvault>
#include <zombieplague>

#define PLUGIN  "[CSO] Player Models"
#define VERSION "0.1.0"
#define AUTHOR  "CSO Custom Project"

#pragma reqlib cso_priv
native cso_is_gold(id)

#define MAXP 32
#define MAX_MODELS 32
#define TASK_APPLY 52600

new g_title[MAX_MODELS][32], g_model[MAX_MODELS][32]
new bool:g_gold_only[MAX_MODELS]
new g_count
new g_choice[MAXP + 1] = { -1, ... }   // -1 — случайная (ZP)
new g_vault

public plugin_natives()
{
	register_library("cso_models")
	register_native("cso_models_current", "native_current")
}

public plugin_precache()
{
	new path[128]
	get_localinfo("amxx_configsdir", path, charsmax(path))
	add(path, charsmax(path), "/cso_player_models.ini")
	new f = fopen(path, "rt")
	if (!f)
	{
		log_amx("[CSO] Нет %s — выбор моделей пуст", path)
		return
	}
	new line[128], title[32], rest[64], model[32], flag[16], file[96]
	while (!feof(f) && g_count < MAX_MODELS)
	{
		fgets(f, line, charsmax(line))
		trim(line)
		if (!line[0] || line[0] == ';')
			continue
		strtok(line, title, charsmax(title), rest, charsmax(rest), '=')
		trim(title)
		trim(rest)
		parse(rest, model, charsmax(model), flag, charsmax(flag))
		if (!title[0] || !model[0])
			continue
		formatex(file, charsmax(file), "models/player/%s/%s.mdl", model, model)
		if (!file_exists(file))
		{
			log_amx("[CSO] Модель «%s»: нет файла %s — пропущена (ресурс отсутствует)", title, file)
			continue
		}
		precache_model(file)
		formatex(file, charsmax(file), "models/player/%s/%sT.mdl", model, model)
		if (file_exists(file))
			precache_model(file)
		copy(g_title[g_count], charsmax(g_title[]), title)
		copy(g_model[g_count], charsmax(g_model[]), model)
		g_gold_only[g_count] = bool:equali(flag, "gold")
		g_count++
	}
	fclose(f)
}

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)
	register_clcmd("say /models", "cmd_models")
	register_clcmd("say_team /models", "cmd_models")
	register_clcmd("cso_models", "cmd_models")
	register_clcmd("cso_models_gold", "cmd_models_gold")
	RegisterHam(Ham_Spawn, "player", "fw_Spawn_Post", 1)
	g_vault = nvault_open("cso_models")
}

public plugin_end()
{
	if (g_vault != INVALID_HANDLE)
		nvault_close(g_vault)
}

public native_current(plugin, params)
{
	new id = get_param(1)
	new idx = (1 <= id <= MAXP) ? g_choice[id] : -1
	set_string(2, (idx >= 0) ? g_title[idx] : "Случайная", get_param(3))
}

// --- сохранение ----------------------------------------------------------------

public client_authorized(id)
{
	g_choice[id] = -1
	if (g_vault == INVALID_HANDLE || is_user_bot(id))
		return
	new key[40], val[40], ts
	get_user_authid(id, key, charsmax(key))
	if (!nvault_lookup(g_vault, key, val, charsmax(val), ts))
		return
	for (new i = 0; i < g_count; i++)
		if (equal(val, g_model[i]))
			g_choice[id] = i
}

save_choice(id)
{
	if (g_vault == INVALID_HANDLE || is_user_bot(id))
		return
	new key[40]
	get_user_authid(id, key, charsmax(key))
	nvault_set(g_vault, key, (g_choice[id] >= 0) ? g_model[g_choice[id]] : "")
}

// --- меню ----------------------------------------------------------------------

public cmd_models(id)
{
	show_list(id, false)
	return PLUGIN_HANDLED
}

public cmd_models_gold(id)
{
	if (!cso_is_gold(id))
	{
		client_print(id, print_chat, "[CSO] Эксклюзивные модели доступны только Gold")
		return PLUGIN_HANDLED
	}
	show_list(id, true)
	return PLUGIN_HANDLED
}

show_list(id, bool:gold_list)
{
	new menu = menu_create(gold_list ? "\yЭксклюзивные модели Gold" : "\yВыбор модели персонажа", "models_handler")
	new info[4], line[64], n = 0
	if (!gold_list)
	{
		menu_additem(menu, (g_choice[id] < 0) ? "Случайная \y(выбрана)" : "Случайная", "-1")
		n++
	}
	for (new i = 0; i < g_count; i++)
	{
		if (g_gold_only[i] != gold_list)
			continue
		formatex(line, charsmax(line), "%s%s", g_title[i], (g_choice[id] == i) ? " \y(выбрана)" : "")
		num_to_str(i, info, charsmax(info))
		menu_additem(menu, line, info)
		n++
	}
	if (!n)
	{
		menu_destroy(menu)
		client_print(id, print_chat, "[CSO] Список моделей пуст: файлы моделей не установлены")
		return
	}
	menu_setprop(menu, MPROP_BACKNAME, "Назад")
	menu_setprop(menu, MPROP_NEXTNAME, "Далее")
	menu_setprop(menu, MPROP_EXITNAME, "Выход")
	menu_display(id, menu)
}

public models_handler(id, menu, item)
{
	new info[4], access, cb
	if (item != MENU_EXIT)
		menu_item_getinfo(menu, item, access, info, charsmax(info), _, _, cb)
	menu_destroy(menu)
	if (item == MENU_EXIT)
		return PLUGIN_HANDLED

	new i = str_to_num(info)
	if (i >= g_count || (i >= 0 && g_gold_only[i] && !cso_is_gold(id)))
		return PLUGIN_HANDLED
	g_choice[id] = i
	save_choice(id)
	client_print(id, print_chat, "[CSO] Модель: %s (применяется к человеку сейчас или после возрождения)", (i >= 0) ? g_title[i] : "Случайная")
	apply(id)
	return PLUGIN_HANDLED
}

// --- применение -----------------------------------------------------------------

apply(id)
{
	new i = g_choice[id]
	if (i < 0 || !is_user_alive(id) || zp_get_user_zombie(id) || zp_get_user_survivor(id))
		return
	if (g_gold_only[i] && !cso_is_gold(id)) // привилегию могли снять
		return
	zp_override_user_model(id, g_model[i])
}

public fw_Spawn_Post(id)
{
	if (!(1 <= id <= MAXP) || !is_user_alive(id))
		return
	remove_task(id + TASK_APPLY)
	set_task(0.3, "task_apply", id + TASK_APPLY) // после того как ядро ZP выставит модель
}

public zp_user_humanized_post(id, survivor)
{
	remove_task(id + TASK_APPLY)
	set_task(0.2, "task_apply", id + TASK_APPLY)
}

public task_apply(taskid)
{
	apply(taskid - TASK_APPLY)
}

public client_disconnected(id)
{
	remove_task(id + TASK_APPLY)
}
