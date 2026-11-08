// Тест компиляции: потребитель API cso_shop.inc (на сервер не ставится)
#include <amxmodx>
#include <cso_shop>

new g_item

public plugin_init()
{
	register_plugin("[CSO] test shop api", "0.0.1", "CSO Custom Project")
	g_item = cso_shop_register_item("Test item", 1, CSO_SHOP_CAT_SPECIAL)
}

public cso_shop_item_bought(id, itemid)
{
	if (itemid != g_item)
		return PLUGIN_CONTINUE
	return PLUGIN_HANDLED // всегда «не удалось» → проверка возврата ammo packs
}
