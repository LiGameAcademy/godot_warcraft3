extends Node

## I4 商店：货架目录、扣费入包、售罄/满包/距离失败、半价出售。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SHOP: " + label)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_catalog()
	_test_buy_sell()
	_test_command_card()
	print("selftest_shop_service: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(1 if failures > 0 else 0)


func _hero(owner_id: int = 0) -> Node3D:
	var unit := Node3D.new()
	unit.set_meta("unit_data", {"typeId": "Hamg", "owner": owner_id})
	add_child(unit)
	unit.global_position = Vector3.ZERO
	Inventory.ensure_on(unit)
	return unit


func _shop(type_id: String = "ngme", pos: Vector3 = Vector3(1, 0, 0)) -> Node3D:
	var building := Node3D.new()
	building.set_meta("unit_data", {"typeId": type_id, "owner": 15})
	add_child(building)
	building.global_position = pos
	return building


func _test_catalog() -> void:
	check(ShopCatalog.is_shop("ngme"), "ngme 是商店")
	check(ShopCatalog.is_shop("nmrk"), "nmrk 是商店")
	check(not ShopCatalog.is_shop("htow"), "主城不是商店")
	var ids := ShopCatalog.stock_ids("ngme")
	check(ids.has("phea") and ids.has("pman") and ids.has("rde1"), "商人首批货架含药水与指环")
	check(ShopCatalog.TRADE_RANGE_WC3 > 0.0, "交易距离为正")


func _test_buy_sell() -> void:
	var svc := ShopService.new()
	var buyer := _hero()
	var shop := _shop()
	var stock := PlayerStock.new()
	stock.gold = 1000
	stock.lumber = 0

	var far := _hero()
	far.global_position = Vector3(50, 0, 0)
	var far_fail := svc.try_buy(far, shop, "phea", stock)
	check(not bool(far_fail.get("ok", true)), "过远应失败")
	check(stock.gold == 1000, "过远不扣金")

	var ok_buy := svc.try_buy(buyer, shop, "phea", stock)
	check(bool(ok_buy.get("ok", false)), "近距购入药水应成功")
	var inv := Inventory.of(buyer)
	check(inv != null and inv.item_at(0) != null and inv.item_at(0).type_id == "phea", "药水入包")
	var price := maxi(ShopCatalog.price_gold("phea"), 1)
	if ShopCatalog.price_gold("phea") <= 0:
		price = 150
	check(stock.gold == 1000 - price, "扣金正确，剩 %d 期望 %d" % [stock.gold, 1000 - price])
	check(svc.remaining(shop, "phea") == ShopCatalog.stock_start("phea") - 1, "库存减一")

	stock.gold = 0
	var poor := svc.try_buy(buyer, shop, "pman", stock)
	check(not bool(poor.get("ok", true)), "无金应失败")

	stock.gold = 5000
	for _i in range(8):
		inv.insert(ItemInstance.create("rde1"))
	var full := svc.try_buy(buyer, shop, "pman", stock)
	check(not bool(full.get("ok", true)), "满包应失败")
	check(stock.gold == 5000, "满包不扣金")

	## 清包后测出售半价
	for s in range(6):
		inv.remove_at(s)
	inv.insert(ItemInstance.create("rde1"))
	var before := stock.gold
	var ring_price := ShopCatalog.price_gold("rde1")
	if ring_price <= 0:
		ring_price = 125
	var sold := svc.try_sell(buyer, shop, 0, stock)
	check(bool(sold.get("ok", false)), "出售指环应成功")
	var refund := int(ring_price / 2)
	check(stock.gold == before + refund, "半价退金")
	check(inv.item_at(0) == null, "出售后槽空")


func _test_command_card() -> void:
	var card := CommandCard.for_shop("ngme", {
		"shop_stock": {"phea": 2, "pman": 0, "rde1": 1},
		"shop_buyer_in_range": true,
		"local_gold": 1000,
		"local_lumber": 0,
		"shop_buyer_inv_full": false,
	})
	var buy_ids: Array[String] = []
	for entry in card:
		if entry is Dictionary and str(entry.get("id", "")).begins_with(CommandCard.ACTION_BUY_PREFIX):
			buy_ids.append(str(entry.get("id")))
	check(buy_ids.has("buy:phea"), "命令卡含 buy:phea")
	check(buy_ids.has("buy:pman"), "命令卡含 buy:pman")
	var pman: Dictionary = {}
	for entry in card:
		if entry is Dictionary and str(entry.get("id", "")) == "buy:pman":
			pman = entry
			break
	check(not pman.is_empty() and not bool(pman.get("enabled", true)), "售罄项应禁用")
