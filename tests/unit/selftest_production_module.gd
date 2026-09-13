extends Node

var failures := 0
var checks := 0
var births: Array[Dictionary] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PRODUCTION MODULE: " + label)

func spawn_unit(type_id: String, position: Vector2, owner: int, building: Node3D) -> Node3D:
	births.append({"type_id": type_id, "position": position, "owner": owner, "building": building})
	var unit := Node3D.new()
	add_child(unit)
	return unit

func make_building(owner: int) -> Node3D:
	var building := Node3D.new()
	building.set_meta("unit_data", {"typeId": "halt", "owner": owner})
	building.set_meta("life", 100.0)
	building.set_meta("max_life", 100.0)
	add_child(building)
	return building

func _ready() -> void:
	# 不创建 GameDirector、HUD、地图或模型缓存，直接验证模块契约。
	var session := GameSession.new()
	session.ensure_stock(0).set_all(1000, 500, 0, 100)
	var stock := session.ensure_stock(1)
	stock.set_all(1000, 500, 4, 100)
	var module := ProductionModule.new()
	add_child(module)
	module.configure(session, spawn_unit, Callable())
	var building := make_building(1)
	var queue := TrainQueue.new()
	queue.name = "TrainQueue"
	building.add_child(queue)
	module.watch(queue)
	module.watch(queue)
	queue.enqueue("hfoo", 1.0, 135, 0, 2, Vector2(64, 96), 1)
	building.set_meta("unit_data", {"typeId": "halt", "owner": 0})
	queue._process(2.0)
	check(births.size() == 1, "重复订阅只生成一个单位")
	check(births[0].owner == 1 and births[0].position == Vector2(64, 96) and births[0].building == building,
		"出生接口传递原订单归属、坐标和建筑")
	check(stock.food_used == 4, "正常出生保留预占人口")
	queue.enqueue("hfoo", 10.0, 135, 0, 2, Vector2.ZERO, 1)
	queue.cancel_at(0)
	check(stock.gold == 1135 and stock.food_used == 2, "重复订阅只结算一次退款")
	check(session.ensure_stock(0).gold == 1000, "建筑易主不改变原订单退款账户")

	# 模块卸载必须断开所有队列回调，旧队列不能改写下一局。
	module.shutdown()
	queue.enqueue("hfoo", 10.0, 135, 0, 2, Vector2.ZERO, 1)
	queue.cancel_at(0)
	check(stock.gold == 1135, "shutdown 后旧队列不再结算")
	var second_session := GameSession.new()
	var second_stock := second_session.ensure_stock(1)
	second_stock.set_all(200, 0, 2, 100)
	module.configure(second_session, spawn_unit, Callable())
	module.watch(queue)
	queue.enqueue("hfoo", 10.0, 135, 0, 2, Vector2.ZERO, 1)
	queue.cancel_at(0)
	check(second_stock.gold == 335 and stock.gold == 1135, "重新装配只写入新会话")
	queue.free()
	check(module._queues.is_empty(), "队列离树释放订阅记录")
	module.free()

	# 复活是模块业务，电脑也可使用；不借用本地玩家库存。
	var revive := ProductionModule.new()
	add_child(revive)
	revive.configure(session, Callable(), Callable())
	building.set_meta("unit_data", {"typeId": "halt", "owner": 1})
	HeroDeathRegistry.clear_owner(1)
	var entry := {"owner": 1, "type_id": "Hamg", "level": 3, "hero_xp": 750}
	HeroDeathRegistry.restore_dead(entry)
	check(not revive.issue_revive(building, "Hamg", 0), "拒绝替敌方建筑下复活订单")
	var gold_before := stock.gold
	check(revive.issue_revive(building, "Hamg", 1), "无需选择器或 HUD 即可下复活订单")
	check(stock.gold == gold_before - HeroDeathRegistry.revive_cost(3, "Hamg") and session.ensure_stock(0).gold == 1000,
		"复活费用归下单玩家")
	check(revive.cancel(building, 0, 1), "模块支持取消己方复活")
	check(stock.gold == gold_before and HeroDeathRegistry.dead_count(1) == 1, "取消恢复退款及阵亡登记")
	stock.gold = 0
	check(not revive.issue_revive(building, "Hamg", 1) and HeroDeathRegistry.dead_count(1) == 1,
		"复活资金不足保留英雄登记")
	HeroDeathRegistry.clear_owner(1)
	revive.free()
	print("selftest_production_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
