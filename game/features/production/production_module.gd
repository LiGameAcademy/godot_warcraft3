class_name ProductionModule
extends Node

## 对局内生产生命周期：持有队列订阅，负责完工、退款、复活及终止。
## 单位生成接口：(type_id, wc3_position, owner, building) -> Node3D。
## 英雄初始化接口：(unit) -> void。由 UnitsModule 方法注入，本模块不依赖总管类型。
signal queue_changed(queue: TrainQueue)
signal progress_changed(queue: TrainQueue)
signal feedback(message: String)
signal research_completed(upgrade_id: String, owner: int)

var _session: GameSession
var _spawn_unit: Callable
var _ensure_hero: Callable
var _queues: Dictionary = {}

func configure(session: GameSession, spawn_unit: Callable, ensure_hero: Callable) -> void:
	_session = session
	_spawn_unit = spawn_unit
	_ensure_hero = ensure_hero

func watch(queue: TrainQueue) -> void:
	if not is_instance_valid(queue) or _queues.has(queue.get_instance_id()):
		return
	var links: Array = [
		[queue.training_completed, _on_training_completed.bind(queue)],
		[queue.training_cancelled, _on_training_cancelled.bind(queue)],
		[queue.queue_changed, _on_queue_changed.bind(queue)],
		[queue.progress_changed, _on_progress_changed.bind(queue)],
		[queue.training_started, _on_training_started.bind(queue)],
		[queue.tree_exiting, _forget_queue.bind(queue.get_instance_id())],
	]
	_queues[queue.get_instance_id()] = {"queue": weakref(queue), "links": links}
	for link in links:
		link[0].connect(link[1])
	queue_changed.emit(queue)

func _forget_queue(id: int) -> void:
	if not _queues.has(id):
		return
	var record: Dictionary = _queues[id]
	if is_instance_valid(record.queue.get_ref()):
		for link in record.links:
			if link[0].is_connected(link[1]):
				link[0].disconnect(link[1])
	_queues.erase(id)

func shutdown() -> void:
	for id in _queues.keys():
		_forget_queue(id)
	_spawn_unit = Callable()
	_ensure_hero = Callable()
	_session = null

func _exit_tree() -> void:
	shutdown()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		shutdown()

func _on_queue_changed(queue: TrainQueue) -> void:
	queue_changed.emit(queue)

func _on_progress_changed(_progress: float, _remaining: float, queue: TrainQueue) -> void:
	progress_changed.emit(queue)

func _on_training_started(_id: String, _time: float, queue: TrainQueue) -> void:
	queue_changed.emit(queue)

func _stock_for_owner(owner: int) -> PlayerStock:
	return _session.stocks.get(owner) as PlayerStock if _session != null else null

func cancel(building: Node3D, slot: int, command_owner: int) -> bool:
	if not CombatQuery.is_alive_in_world(building) or not CombatQuery.is_controllable(building, command_owner):
		return false
	var queue := building.get_node_or_null("TrainQueue") as TrainQueue
	if queue == null:
		return false
	watch(queue)
	return queue.cancel_at(slot)

func terminate(building: Node3D) -> void:
	if not is_instance_valid(building):
		return
	var queue := building.get_node_or_null("TrainQueue") as TrainQueue
	if queue != null:
		watch(queue)
		queue.terminate()


## 本地玩家全局生产/研发活动（每建筑当前在训一项）。
## 返回 [{kind, id, name, icon, progress, remaining_sec, building_id}, ...]
func collect_owner_activities(owner_id: int) -> Array:
	var out: Array = []
	var cat := CommandButtonCatalog.get_shared()
	for id in _queues.keys():
		var record: Dictionary = _queues[id]
		var queue: TrainQueue = record.queue.get_ref() as TrainQueue
		if queue == null or not is_instance_valid(queue) or not queue.is_training():
			continue
		var building := queue.get_parent() as Node3D
		if building == null or not is_instance_valid(building):
			continue
		var ud: Dictionary = building.get_meta("unit_data", {})
		if int(ud.get("owner", -1)) != owner_id:
			continue
		var snap := queue.snapshot()
		if snap.is_empty():
			continue
		var active: Dictionary = snap[0]
		var uid := str(active.get("unit_id", "")).strip_edges()
		if uid.is_empty():
			continue
		var is_research := TechPresence.is_upgrade_id(uid)
		var entry := cat.upgrade_hud_entry(uid, "activity:" + uid, {}) if is_research else cat.unit_hud_entry(uid, "activity:" + uid, {})
		out.append({
			"kind": "research" if is_research else "train",
			"id": uid,
			"name": TechPresence.display_name(uid),
			"icon": str(entry.get("icon", "")),
			"progress": float(active.get("progress", 0.0)),
			"remaining_sec": float(active.get("remaining_sec", 0.0)),
			"building_id": str(ud.get("typeId", "")),
		})
	return out

func _on_training_completed(unit_id: String, site: Vector2, owner: int, queue: TrainQueue) -> void:
	var completed := queue.take_last_completed()
	var building := queue.get_parent() as Node3D
	if TechPresence.is_upgrade_id(unit_id):
		var stock := _stock_for_owner(owner)
		if stock != null:
			var next_lv := TechPresence.upgrade_next_level(unit_id, stock.upgrade_level(unit_id))
			if next_lv > 0:
				stock.grant_upgrade(unit_id, next_lv)
			else:
				stock.grant_upgrade(unit_id)
		research_completed.emit(unit_id, owner)
		feedback.emit("研究完成：%s" % TechPresence.display_name(unit_id))
		queue_changed.emit(queue)
		return
	var unit: Node3D = _spawn_unit.call(unit_id, site, owner, building) if _spawn_unit.is_valid() else null
	if not is_instance_valid(unit):
		if bool(completed.get("is_revive", false)):
			_restore_dead(completed)
		var stock := _stock_for_owner(owner)
		if stock != null:
			var food := BuildingCatalog.get_food_used(unit_id)
			if food > 0:
				stock.add_food_used(-food)
		feedback.emit("训练完成但刷出失败：%s" % unit_id)
		queue_changed.emit(queue)
		return
	if bool(completed.get("is_revive", false)):
		apply_revived_hero_state(unit, completed)
		feedback.emit("复活完成：%s · Lv%d" % [unit_id, int(completed.get("revive_level", 1))])
	else:
		feedback.emit("训练完成：%s" % unit_id)
	queue_changed.emit(queue)

func _restore_dead(entry: Dictionary) -> void:
	var revive: Variant = entry.get("revive_entry", {})
	if revive is Dictionary and not revive.is_empty():
		HeroDeathRegistry.restore_dead(revive)

func _on_training_cancelled(unit_id: String, gold: int, lumber: int, food: int, owner: int, queue: TrainQueue) -> void:
	var cancelled := queue.take_last_cancelled()
	if bool(cancelled.get("is_revive", false)):
		_restore_dead(cancelled)
	var stock := _stock_for_owner(owner)
	if stock != null:
		if gold > 0:
			stock.add_gold(gold)
		if lumber > 0:
			stock.add_lumber(lumber)
		var used := food if food >= 0 else BuildingCatalog.get_food_used(unit_id)
		if used > 0:
			stock.add_food_used(-used)
	var kind := "研究" if TechPresence.is_upgrade_id(unit_id) else "训练"
	feedback.emit("取消%s：%s（退 %d金 %d木）" % [kind, TechPresence.display_name(unit_id), gold, lumber])
	queue_changed.emit(queue)

func apply_revived_hero_state(unit: Node3D, completed: Dictionary) -> void:
	if unit == null or completed.is_empty():
		return
	var lv := maxi(int(completed.get("revive_level", 1)), 1)
	var xp := int(completed.get("revive_xp", -1))
	HeroProgression.set_level(unit, lv, xp)
	var levels: Variant = completed.get("revive_ability_levels", {})
	if typeof(levels) == TYPE_DICTIONARY:
		unit.set_meta(AbilityCatalog.META_ABILITY_LEVELS, (levels as Dictionary).duplicate(true))
	if _ensure_hero.is_valid():
		_ensure_hero.call(unit)
	var entry: Dictionary = completed.get("revive_entry", {})
	var inv := Inventory.of(unit)
	if inv != null:
		inv.restore(entry.get("inventory", {}))
	# 祭坛复活：恢复等级与物品后设置生命、魔法，避免初始化覆盖。
	UnitLife.set_life(unit, UnitLife.get_max_life(unit))
	unit.set_meta(UnitMana.META_MANA, mini(100, UnitMana.get_max_mana(unit)))

func issue_revive(primary: Node3D, unit_id: String, command_owner: int) -> bool:
	if not CombatQuery.is_alive_in_world(primary) or not CombatQuery.is_controllable(primary, command_owner):
		return false
	var d: Dictionary = primary.get_meta("unit_data", {})
	if not HeroDeathRegistry.can_revive_at(str(d.get("typeId", ""))) or UnitLife.is_under_construction(primary):
		return false
	if _stock_for_owner(command_owner) == null:
		return false
	var uid := unit_id.strip_edges()
	if not TechPresence.is_hero_id(uid):
		return false
	var owner_id := int(d.get("owner", 0))
	var entry := HeroDeathRegistry.take_for_revive(owner_id, uid)
	if entry.is_empty():
		feedback.emit("无待复活的 %s" % uid)
		return false
	var lv := maxi(int(entry.get("level", 1)), 1)
	var gold := HeroDeathRegistry.revive_cost(lv, uid)
	var time_sec := HeroDeathRegistry.revive_time_sec(lv, uid)
	var stock := _stock_for_owner(owner_id)
	if stock != null and stock.gold < gold:
		HeroDeathRegistry.restore_dead(entry)
		feedback.emit("金币不足（需要 %d）" % gold)
		return false
	var queue := primary.get_node_or_null("TrainQueue") as TrainQueue
	if queue == null:
		queue = TrainQueue.new()
		queue.name = "TrainQueue"
		primary.add_child(queue)
	if queue.is_full():
		HeroDeathRegistry.restore_dead(entry)
		feedback.emit("训练队列已满（%d/%d）" % [queue.queue_count(), TrainQueue.MAX_QUEUE])
		return false
	if stock != null and not stock.try_spend(gold, 0):
		HeroDeathRegistry.restore_dead(entry)
		feedback.emit("金币不足（需要 %d）" % gold)
		return false
	var site := Wc3Coords.godot_to_wc3_xy(primary.global_position)
	watch(queue)
	var ok := queue.enqueue(
		uid,
		time_sec,
		gold,
		0,
		0,
		site,
		owner_id,
		{
			"is_revive": true,
			"revive_level": lv,
			"revive_ability_levels": entry.get("ability_levels", {}),
			"revive_xp": int(entry.get("hero_xp", 0)),
			"revive_entry": entry,
		}
	)
	if not ok:
		if stock != null:
			stock.add_gold(gold)
		HeroDeathRegistry.restore_dead(entry)
		feedback.emit("无法复活 %s" % uid)
		return false
	feedback.emit("复活中：%s · Lv%d（%d金 · %.0fs）" % [uid, lv, gold, time_sec])
	return true
