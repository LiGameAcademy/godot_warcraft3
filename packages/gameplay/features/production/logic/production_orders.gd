class_name ProductionOrders
extends RefCounted

## 按命令归属校验生产资格、扣费和预占人口；不依赖 HUD 或全局场景。
signal production_queue_ready(queue: TrainQueue)
signal train_issued(unit_id: String)
signal research_issued(upgrade_id: String)

var _session: GameSession
var _owner: int = 0

func configure(session: GameSession, owner: int) -> void:
	_session = session
	_owner = owner

func _command_stock() -> PlayerStock:
	return _session.stocks.get(_owner) as PlayerStock if _session != null else null

func is_unit_controllable(building: Node3D) -> bool:
	return CombatQuery.is_alive_in_world(building) and CombatQuery.is_controllable(building, _owner)

func issue_train(building: Node3D, unit_id: String) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	if UnitLife.is_under_construction(building):
		return false
	if not is_unit_controllable(building):
		return false
	var uid := unit_id.strip_edges()
	if uid.is_empty():
		return false
	var d: Dictionary = building.get_meta("unit_data", {})
	var building_id := str(d.get("typeId", "")).strip_edges()
	var trains := TechPresence.filter_vertical_trains(
		building_id, CommandButtonCatalog.get_shared().get_trains(building_id)
	)
	if trains.find(uid) < 0:
		return false
	var owner: int = int(d.get("owner", 0))
	var unit_host: Node = building.get_parent()
	var owned := TechPresence.collect_owned_buildings(unit_host, owner)
	var missing := TechPresence.missing_requires(
		owned, UnitRequiresCatalog.get_shared().get_requires(uid)
	)
	if not missing.is_empty():
		return false
	if TechPresence.is_hero_id(uid):
		if (
			TechPresence.count_heroes_with_queues(unit_host, owner)
			>= TechPresence.MAX_HEROES_PER_PLAYER
		):
			return false
	var time_sec: float = BuildingCatalog.get_build_time(uid)
	var gold: int = BuildingCatalog.get_gold_cost(uid)
	var lumber: int = BuildingCatalog.get_lumber_cost(uid)
	var food: int = BuildingCatalog.get_food_used(uid)
	if time_sec <= 0.0:
		return false
	var waived := false
	if _session != null:
		var mode := _session.ensure_game_mode()
		var adj := mode.adjust_train_cost(owner, uid, gold, lumber, unit_host)
		gold = int(adj.get("gold", gold))
		lumber = int(adj.get("lumber", lumber))
		waived = bool(adj.get("waived", false))
	## 非首免英雄仍要求 Catalog 有造价；首免允许 0 金 0 木。
	if not waived and gold <= 0 and lumber <= 0:
		return false
	var stock: PlayerStock = null
	if _session != null:
		stock = _command_stock()
	if stock == null:
		return false
	if food > 0 and not stock.can_afford_food(food):
		return false
	if (gold > 0 or lumber > 0) and not stock.try_spend(gold, lumber):
		return false
	if food > 0:
		stock.add_food_used(food)
	var pos: Dictionary = d.get("position", {})
	var site_wc3: Vector2 = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	var queue: TrainQueue = building.get_node_or_null("TrainQueue") as TrainQueue
	if queue == null:
		queue = TrainQueue.new()
		queue.name = "TrainQueue"
		building.add_child(queue)
	production_queue_ready.emit(queue)
	if queue.is_full():
		_refund_train_spend(stock, gold, lumber, food)
		return false
	if not queue.enqueue(uid, time_sec, gold, lumber, food, site_wc3, owner):
		_refund_train_spend(stock, gold, lumber, food)
		return false
	if _session != null:
		_session.ensure_game_mode().notify_train_issued(owner, uid, waived)
	train_issued.emit(uid)
	return true

func issue_research(building: Node3D, upgrade_id: String) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	if UnitLife.is_under_construction(building):
		return false
	if not is_unit_controllable(building):
		return false
	var uid := upgrade_id.strip_edges()
	if uid.is_empty() or not TechPresence.is_upgrade_id(uid):
		return false
	var d: Dictionary = building.get_meta("unit_data", {})
	var building_id := str(d.get("typeId", "")).strip_edges()
	var researches := TechPresence.filter_vertical_researches(
		building_id, CommandButtonCatalog.get_shared().get_researches(building_id)
	)
	if researches.find(uid) < 0:
		return false
	var owner: int = int(d.get("owner", 0))
	var unit_host: Node = building.get_parent()
	var stock: PlayerStock = null
	if _session != null:
		stock = _command_stock()
	if stock == null:
		return false
	var cur_lv := stock.upgrade_level(uid)
	var next_lv := TechPresence.upgrade_next_level(uid, cur_lv)
	if next_lv <= 0:
		return false
	var owned := TechPresence.collect_owned_buildings(unit_host, owner)
	var missing := TechPresence.missing_requires(
		owned, TechPresence.upgrade_requires_for_level(uid, next_lv), stock.upgrade_map()
	)
	if not missing.is_empty():
		return false
	if TechPresence.is_upgrade_queued(unit_host, owner, uid):
		return false
	var time_sec := TechPresence.upgrade_time_at_level(uid, next_lv)
	var gold := TechPresence.upgrade_gold_at_level(uid, next_lv)
	var lumber := TechPresence.upgrade_lumber_at_level(uid, next_lv)
	if time_sec <= 0.0 or (gold <= 0 and lumber <= 0):
		return false
	if not stock.try_spend(gold, lumber):
		return false
	var pos: Dictionary = d.get("position", {})
	var site_wc3: Vector2 = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	var queue: TrainQueue = building.get_node_or_null("TrainQueue") as TrainQueue
	if queue == null:
		queue = TrainQueue.new()
		queue.name = "TrainQueue"
		building.add_child(queue)
	production_queue_ready.emit(queue)
	if queue.is_full():
		_refund_train_spend(stock, gold, lumber, 0)
		return false
	if not queue.enqueue(uid, time_sec, gold, lumber, 0, site_wc3, owner):
		_refund_train_spend(stock, gold, lumber, 0)
		return false
	research_issued.emit(uid)
	return true


func issue_building_upgrade(building: Node3D, target_id: String) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	if UnitLife.is_under_construction(building):
		return false
	if not is_unit_controllable(building):
		return false
	var d: Dictionary = building.get_meta("unit_data", {})
	var from_id := str(d.get("typeId", "")).strip_edges()
	var want := target_id.strip_edges()
	var to_id := TechPresence.building_upgrade_target(from_id)
	if to_id.is_empty() or to_id != want:
		return false
	var owner: int = int(d.get("owner", 0))
	var unit_host: Node = building.get_parent()
	var stock: PlayerStock = null
	if _session != null:
		stock = _command_stock()
	if stock == null:
		return false
	var owned := TechPresence.collect_owned_buildings(unit_host, owner)
	var missing := TechPresence.missing_requires(
		owned, UnitRequiresCatalog.get_shared().get_requires(to_id), stock.upgrade_map()
	)
	if not missing.is_empty():
		return false
	if TechPresence.is_upgrade_queued(unit_host, owner, to_id):
		return false
	var time_sec := TechPresence.building_upgrade_time(to_id)
	var gold := TechPresence.building_upgrade_gold(from_id, to_id)
	var lumber := TechPresence.building_upgrade_lumber(from_id, to_id)
	if time_sec <= 0.0 or (gold <= 0 and lumber <= 0):
		return false
	if not stock.try_spend(gold, lumber):
		return false
	var pos: Dictionary = d.get("position", {})
	var site_wc3: Vector2 = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	var queue: TrainQueue = building.get_node_or_null("TrainQueue") as TrainQueue
	if queue == null:
		queue = TrainQueue.new()
		queue.name = "TrainQueue"
		building.add_child(queue)
	production_queue_ready.emit(queue)
	if queue.is_full():
		_refund_train_spend(stock, gold, lumber, 0)
		return false
	if not queue.enqueue(
		to_id, time_sec, gold, lumber, 0, site_wc3, owner, {"is_building_upgrade": true}
	):
		_refund_train_spend(stock, gold, lumber, 0)
		return false
	return true

func _refund_train_spend(stock: PlayerStock, gold: int, lumber: int, food: int) -> void:
	if stock == null:
		return
	if gold > 0:
		stock.add_gold(gold)
	if lumber > 0:
		stock.add_lumber(lumber)
	if food > 0:
		stock.add_food_used(-food)
