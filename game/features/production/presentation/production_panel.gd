class_name ProductionPanel
extends Node

## 本地选择与生产界面适配器；生产事务和结算由 ProductionModule 管理。
signal command_card_requested(building: Node3D, type_id: String)
signal selection_refresh_requested
signal command_refresh_requested

var production: ProductionModule
var _session: GameSession
var _command_router: CommandRouter
var unit_selector: Node
var game_hud: GameHud
var unit_host: Node
var model_cache: MapModelCache

func configure(session: GameSession, commands: CommandRouter, selector: Node,
		hud: GameHud, host: Node, cache: MapModelCache) -> void:
	_session = session
	_command_router = commands
	unit_selector = selector
	game_hud = hud
	unit_host = host
	model_cache = cache

func _unit_host() -> Node:
	return unit_host

func _local_stock() -> PlayerStock:
	return _session.local_stock() if _session != null else null

func _is_controllable(unit: Node3D) -> bool:
	return _session != null and CombatQuery.is_controllable(unit, _session.local_player)

func _owned_buildings_for_local() -> Dictionary:
	return TechPresence.collect_owned_buildings(unit_host, _session.local_player) if _session != null else {}

func show_feedback(message: String) -> void:
	if is_instance_valid(game_hud):
		game_hud.set_status(message)

func on_research_completed(_id: String, _owner: int) -> void:
	command_refresh_requested.emit()

func request_train(unit_id: String) -> void:
	if _command_router == null or unit_selector == null or not unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	if primary == null or not is_instance_valid(primary):
		if game_hud:
			game_hud.set_status("请先选中可训练建筑")
		return
	if not _is_controllable(primary):
		if game_hud:
			game_hud.set_status("无法控制该建筑")
		return
	var d: Dictionary = primary.get_meta("unit_data", {})
	var building_id := str(d.get("typeId", "")).strip_edges()
	if building_id.is_empty() or not BuildingCatalog.is_building(building_id):
		if game_hud:
			game_hud.set_status("当前选中无法训练")
		return
	if UnitLife.is_under_construction(primary):
		if game_hud:
			game_hud.set_status("建造中，无法训练")
		return
	var uid := unit_id.strip_edges()
	var trains := TechPresence.filter_vertical_trains(
		building_id, CommandButtonCatalog.get_shared().get_trains(building_id)
	)
	if trains.find(uid) < 0:
		if game_hud:
			game_hud.set_status("%s 不能训练 %s" % [building_id, uid])
		return
	var owned := _owned_buildings_for_local()
	var missing := TechPresence.missing_requires(
		owned, UnitRequiresCatalog.get_shared().get_requires(uid)
	)
	if not missing.is_empty():
		if game_hud:
			game_hud.set_status(TechPresence.requires_tip(missing))
		return
	if TechPresence.is_hero_id(uid):
		var owner_id := int(d.get("owner", 0))
		if (
			TechPresence.count_heroes_with_queues(_unit_host(), owner_id)
			>= TechPresence.MAX_HEROES_PER_PLAYER
		):
			if game_hud:
				game_hud.set_status("每位玩家同时只能拥有 %d 名英雄" % TechPresence.MAX_HEROES_PER_PLAYER)
			return
	var stock := _local_stock()
	var gold := BuildingCatalog.get_gold_cost(uid)
	var lumber := BuildingCatalog.get_lumber_cost(uid)
	var food := BuildingCatalog.get_food_used(uid)
	if stock != null:
		if food > 0 and not stock.can_afford_food(food):
			if game_hud:
				game_hud.set_status("人口不足（%d/%d）" % [stock.food_used, stock.food_cap])
			return
		if stock.gold < gold or stock.lumber < lumber:
			_notify_cannot_afford_build(uid)
			return
	var existing := primary.get_node_or_null("TrainQueue") as TrainQueue
	if existing != null and existing.is_full():
		if game_hud:
			game_hud.set_status("训练队列已满（%d/%d）" % [existing.queue_count(), TrainQueue.MAX_QUEUE])
		return
	if not _command_router.issue_train(primary, uid):
		if game_hud:
			game_hud.set_status("无法训练 %s" % uid)
		return
	var queue := primary.get_node_or_null("TrainQueue") as TrainQueue
	production.watch(queue)
	command_card_requested.emit(primary, building_id)
	selection_refresh_requested.emit()
	if game_hud:
		var n := queue.queue_count() if queue != null else 1
		game_hud.set_status("已加入训练队列：%s（%d/%d）" % [uid, n, TrainQueue.MAX_QUEUE])

func request_research(upgrade_id: String) -> void:
	if _command_router == null or unit_selector == null or not unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	if primary == null or not is_instance_valid(primary):
		if game_hud:
			game_hud.set_status("请先选中可研究建筑")
		return
	if not _is_controllable(primary):
		if game_hud:
			game_hud.set_status("无法控制该建筑")
		return
	var d: Dictionary = primary.get_meta("unit_data", {})
	var building_id := str(d.get("typeId", "")).strip_edges()
	if building_id.is_empty() or not BuildingCatalog.is_building(building_id):
		if game_hud:
			game_hud.set_status("当前选中无法研究")
		return
	if UnitLife.is_under_construction(primary):
		if game_hud:
			game_hud.set_status("建造中，无法研究")
		return
	var uid := upgrade_id.strip_edges()
	var researches := TechPresence.filter_vertical_researches(
		building_id, CommandButtonCatalog.get_shared().get_researches(building_id)
	)
	if researches.find(uid) < 0:
		if game_hud:
			game_hud.set_status("%s 不能研究 %s" % [building_id, uid])
		return
	var stock := _local_stock()
	if stock != null and stock.has_upgrade(uid):
		if game_hud:
			game_hud.set_status("已研究：%s" % TechPresence.display_name(uid))
		return
	var owner_id := int(d.get("owner", 0))
	if TechPresence.is_upgrade_queued(_unit_host(), owner_id, uid):
		if game_hud:
			game_hud.set_status("已在研究：%s" % TechPresence.display_name(uid))
		return
	var gold := TechPresence.upgrade_gold(uid)
	var lumber := TechPresence.upgrade_lumber(uid)
	if stock != null and (stock.gold < gold or stock.lumber < lumber):
		if game_hud:
			var msg := "资源不够（需 %d金" % gold
			if lumber > 0:
				msg += " %d木" % lumber
			msg += "）"
			if game_hud.has_method("show_command_tip"):
				game_hud.show_command_tip(msg)
			else:
				game_hud.set_status(msg)
		return
	var existing := primary.get_node_or_null("TrainQueue") as TrainQueue
	if existing != null and existing.is_full():
		if game_hud:
			game_hud.set_status("训练队列已满（%d/%d）" % [existing.queue_count(), TrainQueue.MAX_QUEUE])
		return
	if not _command_router.issue_research(primary, uid):
		if game_hud:
			game_hud.set_status("无法研究 %s" % uid)
		return
	var queue := primary.get_node_or_null("TrainQueue") as TrainQueue
	production.watch(queue)
	command_card_requested.emit(primary, building_id)
	selection_refresh_requested.emit()
	if game_hud:
		var n := queue.queue_count() if queue != null else 1
		game_hud.set_status("已加入研究队列：%s（%d/%d）" % [TechPresence.display_name(uid), n, TrainQueue.MAX_QUEUE])

func _notify_cannot_afford_build(building_id: String) -> void:
	if game_hud == null:
		return
	var g := BuildingCatalog.get_gold_cost(building_id)
	var l := BuildingCatalog.get_lumber_cost(building_id)
	var msg := "资源不够"
	if g > 0 or l > 0:
		msg = "资源不够（需 %d金" % g
		if l > 0:
			msg += " %d木" % l
		msg += "）"
	if game_hud.has_method("show_command_tip"):
		game_hud.show_command_tip(msg)
	else:
		game_hud.set_status(msg)

func _sync_building_train_visual(building: Node3D) -> void:
	if building == null or not is_instance_valid(building):
		return
	var tid := str(building.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	if tid.is_empty() or not BuildingCatalog.is_building(tid):
		return
	if UnitLife.is_under_construction(building):
		return
	var cache := model_cache
	if cache == null:
		return
	var q := building.get_node_or_null("TrainQueue") as TrainQueue
	var phase := (
		BuildingVisual.Phase.WORK if q != null and q.is_training() else BuildingVisual.Phase.IDLE
	)
	BuildingVisual.apply_phase(cache, building, tid, phase)

func on_queue_changed(queue: TrainQueue = null) -> void:
	if queue != null and is_instance_valid(queue):
		_sync_building_train_visual(queue.get_parent() as Node3D)
	selection_refresh_requested.emit()
	if unit_selector != null and unit_selector.has_method("get_primary"):
		var primary: Node3D = unit_selector.call("get_primary") as Node3D
		if primary != null:
			var tid := str(primary.get_meta("unit_data", {}).get("typeId", ""))
			if not tid.is_empty() and not CommandButtonCatalog.get_shared().get_trains(tid).is_empty():
				command_card_requested.emit(primary, tid)

func _on_train_progress_changed(_progress: float, _remaining_sec: float, queue: TrainQueue) -> void:
	# 仅当该队列所属建筑是当前主选时刷 HUD（事件驱动，非 Director 轮询）
	if queue == null or not is_instance_valid(queue):
		return
	if not _is_primary_train_queue(queue):
		return
	show_queue(queue)

func _is_primary_train_queue(queue: TrainQueue) -> bool:
	if game_hud == null or unit_selector == null or not unit_selector.has_method("get_primary"):
		return false
	var primary: Node3D = unit_selector.call("get_primary") as Node3D
	if primary == null or not is_instance_valid(primary):
		return false
	return queue.get_parent() == primary

func show_queue(tq: TrainQueue) -> void:
	if game_hud == null or tq == null:
		return
	if not game_hud.has_method("set_train_queue"):
		return
	var slots: Array = []
	var cat := CommandButtonCatalog.get_shared()
	for e in tq.snapshot():
		var uid := str(e.get("unit_id", ""))
		var entry := cat.unit_hud_entry(uid, "train:" + uid, {})
		if entry.is_empty():
			entry = cat.upgrade_hud_entry(uid, "research:" + uid, {})
		var shown_name := str(entry.get("name", "")).strip_edges()
		if shown_name.is_empty():
			shown_name = TechPresence.display_name(uid)
		slots.append({
			"unit_id": uid,
			"name": shown_name,
			"icon": str(entry.get("icon", "")),
			"progress": float(e.get("progress", 0.0)),
			"active": bool(e.get("active", false)),
			"remaining_sec": float(e.get("remaining_sec", 0.0)),
			"tooltip": "%s · 点击取消" % shown_name,
		})
	game_hud.set_train_queue(slots, tq.queue_count(), TrainQueue.MAX_QUEUE)

func request_revive(unit_id: String) -> void:
	if unit_selector == null or not unit_selector.has_method("get_primary") or _session == null:
		return
	var primary := unit_selector.call("get_primary") as Node3D
	if not is_instance_valid(primary):
		show_feedback("请先选中祭坛")
		return
	if not _is_controllable(primary):
		show_feedback("无法控制该建筑")
		return
	var tid := str(primary.get_meta("unit_data", {}).get("typeId", ""))
	if not HeroDeathRegistry.can_revive_at(tid):
		show_feedback("仅祭坛可复活英雄")
		return
	if UnitLife.is_under_construction(primary):
		show_feedback("建造中，无法复活")
		return
	if production.issue_revive(primary, unit_id, _session.local_player):
		command_card_requested.emit(primary, tid)
		selection_refresh_requested.emit()

func cancel_selected(slot: int) -> void:
	if unit_selector == null or not unit_selector.has_method("get_primary") or _session == null:
		return
	var primary := unit_selector.call("get_primary") as Node3D
	production.cancel(primary, slot, _session.local_player)

func on_progress(queue: TrainQueue) -> void:
	_on_train_progress_changed(0.0, 0.0, queue)
