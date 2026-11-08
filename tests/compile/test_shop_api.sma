// Тест компиляции: потребитель API cso_shop.inc (на сервер не ставится)
#include <amxmodx>
#include <cso_shop>

new g_item, g_vip

public plugin_init()
{
	register_plugin("[CSO] test shop api", "0.0.2", "CSO Custom Project")
	g_item = cso_shop_bind("walter")
	g_vip = cso_shop_register_item_cvar("Test VIP item", "cso_test_cost", "0", CSO_SHOP_CAT_VIP)
	cso_shop_set_item_round_limit(g_vip, "cso_test_rounds", "3")
}

public cso_shop_item_bought(id, itemid)
{
	if (itemid != g_item && itemid != g_vip)
		return PLUGIN_CONTINUE
	return PLUGIN_HANDLED // всегда «не удалось» → проверка возврата ammo packs
}
