/*
 * CSO Zombie — API Human Shop (cso_human_shop.amxx, library "cso_shop").
 * Ассортимент Human Shop утверждён (ТЗ §4): новые позиции не добавляются,
 * плагин оружия только привязывается к своей позиции по ключу.
 */

#if defined _cso_shop_included
	#endinput
#endif
#define _cso_shop_included

#pragma reqlib cso_shop

// Категория для cso_shop_register_item_cvar: только VIP меню (не страница Human Shop)
#define CSO_SHOP_CAT_VIP 5

/**
 * Привязать плагин к утверждённой позиции Human Shop. Ключи:
 *   walter, poison, dual_infinity, watergun, xmas_m249, black_rifle, black_spas,
 *   xmas_dbarrel, skull5, xmas_m134, black_ak47, m249_v2
 * Цена — CVAR cso_shop_cost_<ключ>, лимит за раунд — cso_shop_limit_<ключ>.
 * @return id предмета или -1 (неизвестный ключ / позиция занята)
 */
native cso_shop_bind(const key[])

/**
 * Регистрирует предмет VIP меню (category должна быть CSO_SHOP_CAT_VIP).
 * Цена — CVAR cvarname (магазин регистрирует его сам).
 */
native cso_shop_register_item_cvar(const name[], const cvarname[], const defcost[], category = CSO_SHOP_CAT_VIP)

/**
 * Ограничение: игрок (по SteamID) получает предмет не чаще раза в N раундов.
 */
native cso_shop_set_item_round_limit(itemid, const cvarname[], const defrounds[])

/**
 * Вызывается после списания ammo packs за предмет плагина.
 * Верните PLUGIN_HANDLED, если выдать не удалось — стоимость вернётся игроку.
 */
forward cso_shop_item_bought(id, itemid)
