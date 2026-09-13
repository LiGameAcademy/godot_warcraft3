extends Node

var failed := 0
var checks := 0

class TestSelection extends Node:
	var primary: Node3D
	func get_primary() -> Node3D:
		return primary

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("PRODUCTION OWNERS: " + label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	# 不启动地图；实际 Director 接线和 TrainQueue 信号使用两个独立库存。
	var director := GameDirector.new()
	var session := GameSession.new()
	director._session = session
	var human := session.ensure_stock(0)
	var computer := session.ensure_stock(1)
	human.set_all(500, 150, 10, 30)
	computer.set_all(300, 80, 8, 30)
	var building := Node3D.new()
	building.set_meta("unit_data", {"typeId": "hbar", "owner": 1})
	add_child(building)
	var queue := TrainQueue.new()
	building.add_child(queue)
	director._wire_train_queue(queue)
	queue.enqueue("hfoo", 20.0, 135, 0, 2, Vector2.ZERO, 1)
	check(queue.cancel_at(0), "取消电脑生产队列")
	check(computer.gold == 435 and computer.food_used == 6, "退款和人口回到下单玩家")
	check(human.gold == 500 and human.food_used == 10, "电脑取消不影响本地库存")
	# 入队后建筑转移所有权也不能改变原订单的付款账户。
	queue.enqueue("hfoo", 20.0, 135, 0, 2, Vector2.ZERO, 1)
	building.set_meta("unit_data", {"typeId": "hbar", "owner": 0})
	queue.cancel_at(0)
	check(computer.gold == 570 and human.gold == 500, "取消依原订单归属而非当前建筑归属")
	queue.enqueue("Rhde", 1.0, 150, 100, 0, Vector2.ZERO, 1)
	queue._process(2.0)
	check(computer.has_upgrade("Rhde") and not human.has_upgrade("Rhde"), "研究完成归原订单玩家")
	var unit := Node3D.new()
	unit.set_meta("unit_data", {"typeId": "hfoo", "owner": 1})
	add_child(unit)
	var before := computer.food_used
	director._release_unit_food(unit)
	check(computer.food_used == before - BuildingCatalog.get_food_used("hfoo"), "电脑阵亡释放电脑人口")
	director._release_unit_food(unit)
	check(computer.food_used == before - BuildingCatalog.get_food_used("hfoo") and human.food_used == 10, "重复死亡不重复释放或影响本地玩家")
	computer.food_used = 8
	queue.enqueue("hfoo", 1.0, 135, 0, 2, Vector2.ZERO, 1)
	# 没有地图生成器，故意触发出生失败回滚。
	queue._process(2.0)
	check(computer.food_used == 6 and human.food_used == 10, "出生失败只释放原订单玩家人口")
	queue.enqueue("hfoo", 20.0, 135, 0, 2, Vector2.ZERO, 0)
	queue.cancel_at(0)
	check(human.gold == 635 and human.food_used == 8 and computer.gold == 570, "本地玩家取消仍正常结算")
	var neutral := Node3D.new()
	neutral.set_meta("unit_data", {"typeId": "hfoo", "owner": 12})
	add_child(neutral)
	director._release_unit_food(neutral)
	check(not session.stocks.has(12) and human.food_used == 8, "中立单位死亡不创建库存或扣本地人口")
	check_command_owners(director, session, building)
	check_cancel_routes(director, session, building)
	check_food_capacity(director, session)
	check_production_termination(director, session)
	director.free()
	print("selftest_production_owners: %s (%d checks)" % ["PASS" if failed == 0 else "FAIL", checks])
	get_tree().quit(0 if failed == 0 else 1)

func check_command_owners(director: GameDirector, session: GameSession, building: Node3D) -> void:
	var human := session.ensure_stock(0)
	var computer := session.ensure_stock(1)
	human.set_all(1000, 1000, 0, 100)
	computer.set_all(1000, 1000, 0, 100)
	building.set_meta("unit_data", {"typeId": "hbar", "owner": 1})
	var local_router := CommandRouter.new()
	local_router.configure(null, null, Callable(), Callable(), Callable(), session)
	var ai_router := CommandRouter.new()
	ai_router.production_queue_ready.connect(director._wire_train_queue)
	ai_router.configure(null, null, Callable(), Callable(), Callable(), session, Callable(), Callable(), Callable(), 1)
	check(not local_router.issue_train(building, "hfoo"), "本地入口拒绝控制电脑建筑")
	check(ai_router.issue_train(building, "hfoo"), "电脑独立入口接受己方训练")
	var cost := BuildingCatalog.get_gold_cost("hfoo")
	check(computer.gold == 1000 - cost and human.gold == 1000 and session.local_player == 0, "电脑训练只扣自身库存且不切换本地玩家")
	var queue := building.get_node("TrainQueue") as TrainQueue
	queue.cancel_at(0)
	check(computer.gold == 1000 and computer.food_used == 0, "命令扣费到取消退款完整往返")
	building.set_meta("unit_data", {"typeId": "hbar", "owner": 0})
	check(not ai_router.issue_train(building, "hfoo"), "电脑入口拒绝控制人类建筑")
	building.set_meta("unit_data", {"typeId": "hbar", "owner": 1})
	computer.gold = 0
	check(not ai_router.issue_train(building, "hfoo") and human.gold == 1000, "电脑资金不足不得使用人类库存")
	computer.gold = 10000
	for i in range(TrainQueue.MAX_QUEUE):
		check(ai_router.issue_train(building, "hfoo"), "合法订单填充队列 %d" % i)
	var before_gold := computer.gold
	var before_food := computer.food_used
	check(not ai_router.issue_train(building, "hfoo") and computer.gold == before_gold and computer.food_used == before_food, "满队列失败回滚到电脑账户")
	while queue.queue_count() > 0:
		queue.cancel_at(0)
	computer._upgrades.clear()
	var research_gold := computer.gold
	var research_lumber := computer.lumber
	check(ai_router.issue_research(building, "Rhde"), "电脑可下达研究命令")
	check(computer.gold == research_gold - TechPresence.upgrade_gold("Rhde") and computer.lumber == research_lumber - TechPresence.upgrade_lumber("Rhde") and human.gold == 1000, "研究仅扣电脑金木")
	check(not ai_router.issue_research(building, "Rhde"), "拒绝重复排队研究")
	queue._process(TechPresence.upgrade_time("Rhde") + 1.0)
	check(computer.has_upgrade("Rhde") and not human.has_upgrade("Rhde"), "命令研究到科技授予闭环")
	var orphan := CommandRouter.new()
	orphan.configure(null, null, Callable(), Callable(), Callable(), session, Callable(), Callable(), Callable(), 9)
	building.set_meta("unit_data", {"typeId": "hbar", "owner": 9})
	check(not orphan.issue_train(building, "hfoo") and not session.stocks.has(9), "未加入会话的玩家不能免费生产")

func check_cancel_routes(director: GameDirector, session: GameSession, building: Node3D) -> void:
	building.set_meta("unit_data", {"typeId": "halt", "owner": 1})
	var queue := building.get_node("TrainQueue") as TrainQueue
	var selection := TestSelection.new()
	selection.primary = building
	director.unit_selector = selection
	queue.enqueue("hfoo", 20.0, 135, 0, 2, Vector2.ZERO, 1)
	var before := session.ensure_stock(1).gold
	director._on_train_queue_cancel(0)
	check(queue.queue_count() == 1 and session.ensure_stock(1).gold == before, "本地取消按钮不能取消敌方生产")
	director.unit_selector = null
	selection.free()
	while queue.queue_count() > 0:
		queue.cancel_at(0)
	HeroDeathRegistry.clear_owner(1)
	var entry := {"owner": 1, "type_id": "Hamg", "level": 3, "hero_xp": 750, "inventory": {"slots": []}}
	queue.enqueue("Hamg", 20.0, 300, 0, 5, Vector2.ZERO, 1, {"is_revive": true, "revive_entry": entry})
	queue.cancel_at(0)
	check(HeroDeathRegistry.dead_count(1) == 1, "无界面取消复活也恢复英雄登记")
	check(HeroDeathRegistry.take_for_revive(1, "Hamg") == entry, "恢复等级经验及背包快照")
	check(not queue.cancel_at(0) and HeroDeathRegistry.dead_count(1) == 0, "重复取消不复制英雄登记")
	HeroDeathRegistry.clear_owner(1)
	building.set_meta("unit_data", {"typeId": "halt", "owner": 0})
	var own_selection := TestSelection.new()
	own_selection.primary = building
	director.unit_selector = own_selection
	HeroDeathRegistry.clear_owner(0)
	var own_entry := {"owner": 0, "type_id": "Hamg", "level": 2}
	queue.enqueue("Hamg", 20.0, 300, 0, 5, Vector2.ZERO, 0, {"is_revive": true, "revive_entry": own_entry})
	director._on_train_queue_cancel(0)
	check(queue.queue_count() == 0 and HeroDeathRegistry.dead_count(0) == 1, "己方界面仍可取消复活且只恢复一次")
	director.unit_selector = null
	own_selection.free()
	HeroDeathRegistry.clear_owner(0)

func check_food_capacity(director: GameDirector, session: GameSession) -> void:
	var human := session.ensure_stock(0)
	var computer := session.ensure_stock(1)
	human.set_all(500, 150, 10, 30)
	computer.set_all(500, 150, 10, 30)
	var farm := Node3D.new()
	farm.set_meta("unit_data", {"typeId": "hhou", "owner": 1})
	add_child(farm)
	var capacity := BuildingCatalog.get_food_made("hhou")
	director._release_unit_food(farm)
	check(computer.food_cap == 30 - capacity and human.food_cap == 30, "电脑农场摧毁只减少电脑人口上限")
	director._release_unit_food(farm)
	check(computer.food_cap == 30 - capacity and computer.food_used == 10, "重复摧毁不重复扣上限且保留现有部队人口")
	var unfinished := Node3D.new()
	unfinished.set_meta("unit_data", {"typeId": "hhou", "owner": 0})
	add_child(unfinished)
	UnitLife.set_under_construction(unfinished, true)
	director._release_unit_food(unfinished)
	check(human.food_cap == 30, "未完工农场没有授予人口上限，摧毁不扣")
	var hall := Node3D.new()
	hall.set_meta("unit_data", {"typeId": "htow", "owner": 0})
	add_child(hall)
	director._release_unit_food(hall)
	check(human.food_cap == 30 - BuildingCatalog.get_food_made("htow"), "本地主城摧毁扣回人口上限")

func check_production_termination(director: GameDirector, session: GameSession) -> void:
	var building := Node3D.new()
	building.set_meta("unit_data", {"typeId": "halt", "owner": 1})
	add_child(building)
	var queue := TrainQueue.new()
	queue.name = "TrainQueue"
	building.add_child(queue)
	var human := session.ensure_stock(0)
	var computer := session.ensure_stock(1)
	human.set_all(500, 150, 10, 30)
	computer.set_all(100, 50, 7, 30)
	HeroDeathRegistry.clear_owner(1)
	var entry := {"owner": 1, "type_id": "Hamg", "level": 4, "inventory": {"slots": []}}
	queue.enqueue("hfoo", 1.0, 135, 0, 2, Vector2.ZERO, 1)
	queue.enqueue("Hamg", 1.0, 300, 0, 5, Vector2.ZERO, 1, {"is_revive": true, "revive_entry": entry})
	queue.enqueue("Rhde", 1.0, 150, 100, 0, Vector2.ZERO, 1)
	var events := {"started": 0, "completed": 0}
	queue.training_started.connect(func(_id: String, _time: float): events.started += 1)
	queue.training_completed.connect(func(_id: String, _xy: Vector2, _owner: int): events.completed += 1)
	director._terminate_unit_production(building)
	check(queue.queue_count() == 0 and not queue.is_processing(), "建筑生产终止后清空并停止")
	check(events.started == 0, "终止队列不启动等待中的订单")
	check(computer.food_used == 0 and human.food_used == 10, "终止释放所有预占人口且不影响对手")
	check(HeroDeathRegistry.take_for_revive(1, "Hamg") == entry, "祭坛终止后英雄仍可再次复活")
	var refunded := computer.gold
	check(refunded == 685 and computer.lumber == 150, "暂定取消规则对所有订单退款")
	director._terminate_unit_production(building)
	queue._process(100.0)
	check(computer.gold == refunded and events.completed == 0, "重复死亡不重复退款且不再出兵")
	check(not queue.enqueue("hfoo", 1.0, 135, 0, 2, Vector2.ZERO, 1), "已终止队列拒绝新订单")
	HeroDeathRegistry.clear_owner(1)
