class_name ShopCatalog
extends RefCounted

## 中立商店首版货架（I4）。完整 SellItems 表驱动后置；先用人族竖切常见商店。

## 购买交互距离（WC3 单位）。
const TRADE_RANGE_WC3 := 300.0

## building typeId → 可购物品 id 列表（稳定顺序 = 命令卡槽位）。
const SHOP_STOCK := {
	## 地精商人（Goblin Merchant）
	"ngme": ["phea", "pman", "rde1"],
	## 市场（Marketplace）— 与商人同首批药水/戒指，后续接完整货架
	"nmrk": ["phea", "pman", "rde1"],
}


static func is_shop(building_type_id: String) -> bool:
	return SHOP_STOCK.has(building_type_id.strip_edges())


static func stock_ids(building_type_id: String) -> PackedStringArray:
	var raw: Variant = SHOP_STOCK.get(building_type_id.strip_edges(), [])
	var out := PackedStringArray()
	if raw is Array:
		for id in raw as Array:
			var s := str(id).strip_edges()
			if not s.is_empty():
				out.append(s)
	return out


static func price_gold(item_id: String) -> int:
	var d := ItemCatalog.data(item_id)
	if d == null:
		return 0
	return maxi(d.gold_cost, 0)


static func price_lumber(item_id: String) -> int:
	var d := ItemCatalog.data(item_id)
	if d == null:
		return 0
	return maxi(d.lumber_cost, 0)


static func stock_max(item_id: String) -> int:
	var d := ItemCatalog.data(item_id)
	if d == null:
		return 1
	## stock_max=0 在原作常表示无限；首版用较大上限代替。
	return d.stock_max if d.stock_max > 0 else 99


static func stock_start(item_id: String) -> int:
	var d := ItemCatalog.data(item_id)
	if d == null:
		return 1
	if d.stock_start > 0:
		return d.stock_start
	return stock_max(item_id)
