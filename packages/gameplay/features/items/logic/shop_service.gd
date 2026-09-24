class_name ShopService
extends RefCounted

## 商店交易：距离校验、扣费、入包、库存；出售退还半价金币。
## 不碰 Node/HUD；由 ItemsModule / CommandCardModule 接线。

signal message(text: String)

## shop_instance_id → { item_id → remaining }
var _stocks: Dictionary = {}


func ensure_stock(shop: Node3D) -> void:
	if not is_instance_valid(shop):
		return
	var sid := shop.get_instance_id()
	if _stocks.has(sid):
		return
	var tid := _type_id(shop)
	var table: Dictionary = {}
	for item_id in ShopCatalog.stock_ids(tid):
		table[item_id] = ShopCatalog.stock_start(item_id)
	_stocks[sid] = table


func remaining(shop: Node3D, item_id: String) -> int:
	ensure_stock(shop)
	if not is_instance_valid(shop):
		return 0
	var table: Dictionary = _stocks.get(shop.get_instance_id(), {})
	return int(table.get(item_id, 0))


func clear_shop(shop: Node3D) -> void:
	if is_instance_valid(shop):
		_stocks.erase(shop.get_instance_id())


func clear_all() -> void:
	_stocks.clear()


## 结果：{ok: bool, reason: String, item_id: String}
func try_buy(
	buyer: Node3D,
	shop: Node3D,
	item_id: String,
	stock: PlayerStock
) -> Dictionary:
	var id := item_id.strip_edges()
	if not is_instance_valid(buyer) or not is_instance_valid(shop):
		return _fail("无效交易对象")
	if stock == null:
		return _fail("无库存")
	var shop_tid := _type_id(shop)
	if not ShopCatalog.is_shop(shop_tid):
		return _fail("不是商店")
	if not ShopCatalog.stock_ids(shop_tid).has(id):
		return _fail("本店不售此物")
	if not _in_range(buyer, shop):
		return _fail("距离过远，靠近商店后再购买")
	var inv := Inventory.of(buyer)
	if inv == null:
		return _fail("仅英雄可购入背包")
	if inv.is_full():
		return _fail("背包已满")
	ensure_stock(shop)
	var left := remaining(shop, id)
	if left <= 0:
		return _fail("售罄")
	var gold := ShopCatalog.price_gold(id)
	var lumber := ShopCatalog.price_lumber(id)
	## 无 SLK 价格时给首版默认，避免 0 金白嫖。
	if gold <= 0 and lumber <= 0:
		gold = _fallback_gold(id)
	if not stock.try_spend(gold, lumber):
		return _fail("资源不足（需 %d金%s）" % [
			gold,
			(" · %d木" % lumber) if lumber > 0 else "",
		])
	var item := ItemInstance.create(id)
	if item == null or not inv.insert(item):
		stock.add_gold(gold)
		if lumber > 0:
			stock.add_lumber(lumber)
		return _fail("购入失败，已退款")
	_stocks[shop.get_instance_id()][id] = left - 1
	var title := ItemCatalog.title(id)
	message.emit("购入 %s（-%d金）" % [title, gold])
	return {"ok": true, "reason": "购入 %s" % title, "item_id": id}


## 出售：半价退金（向下取整）；不计木。
func try_sell(
	seller: Node3D,
	shop: Node3D,
	slot: int,
	stock: PlayerStock
) -> Dictionary:
	if not is_instance_valid(seller) or not is_instance_valid(shop) or stock == null:
		return _fail("无效交易对象")
	if not ShopCatalog.is_shop(_type_id(shop)):
		return _fail("不是商店")
	if not _in_range(seller, shop):
		return _fail("距离过远")
	var inv := Inventory.of(seller)
	if inv == null:
		return _fail("无背包")
	var item := inv.item_at(slot)
	if item == null:
		return _fail("空槽")
	var d := ItemCatalog.data(item.type_id)
	if d == null or not d.sellable:
		return _fail("该道具不可出售")
	var refund := int(ShopCatalog.price_gold(item.type_id) / 2)
	if refund <= 0:
		refund = int(_fallback_gold(item.type_id) / 2)
	inv.remove_at(slot)
	if refund > 0:
		stock.add_gold(refund)
	var title := ItemCatalog.title(item.type_id)
	message.emit("出售 %s（+%d金）" % [title, refund])
	return {"ok": true, "reason": "出售 %s" % title, "item_id": item.type_id}


func _in_range(a: Node3D, b: Node3D) -> bool:
	var pa := Wc3Coords.godot_to_wc3_xy(a.global_position)
	var pb := Wc3Coords.godot_to_wc3_xy(b.global_position)
	return pa.distance_to(pb) <= ShopCatalog.TRADE_RANGE_WC3


func _type_id(node: Node3D) -> String:
	var ud: Dictionary = node.get_meta("unit_data", {})
	return str(ud.get("typeId", "")).strip_edges()


func _fallback_gold(item_id: String) -> int:
	match item_id:
		"phea":
			return 150
		"pman":
			return 150
		"rde1":
			return 125
		_:
			return 100


func _fail(reason: String) -> Dictionary:
	message.emit(reason)
	return {"ok": false, "reason": reason, "item_id": ""}
