/*
 * CSO Zombie — API магазина людей (cso_human_shop.amxx, library "cso_shop").
 * Используется адаптерами внешних предметов (например, Poison Launcher).
 */

#if defined _cso_shop_included
	#endinput
#endif
#define _cso_shop_included

#pragma reqlib cso_shop

enum
{
	CSO_SHOP_CAT_PISTOLS = 0,
	CSO_SHOP_CAT_RIFLES,
	CSO_SHOP_CAT_HEAVY,
	CSO_SHOP_CAT_EQUIPMENT,
	CSO_SHOP_CAT_SPECIAL,
	CSO_SHOP_CAT_COUNT
}

/**
 * Регистрирует внешний предмет. Вызывать в plugin_init или позже.
 * @return id предмета или -1
 */
native cso_shop_register_item(const name[], cost, category = CSO_SHOP_CAT_SPECIAL)

/**
 * Регистрирует внешний предмет с ценой из CVAR (магазин регистрирует CVAR сам
 * и читает цену в момент покупки, поэтому значение из cso_custom.cfg действует).
 * @return id предмета или -1
 */
native cso_shop_register_item_cvar(const name[], const cvarname[], const defcost[], category = CSO_SHOP_CAT_SPECIAL)

/**
 * Вызывается после списания ammo packs за внешний предмет.
 * Верните PLUGIN_HANDLED, если выдать не удалось — стоимость вернётся игроку.
 */
forward cso_shop_item_bought(id, itemid)
