class_name NavigationModule
extends Node

## 对局内导航服务所有者。地图就绪后 initialize；获取模块不会重新绑定依赖。
## 不持有 Director；导航变化通过信号通知界面，视觉装配暂由单位入口注入。
signal locomotion_changed(moving: bool)

var path_query: PathQuery
var pathing: Wc3PathingMap
var heightfield: Wc3Heightfield
var crowd_query: UnitCrowdQuery
var cell_reservation: PathCellReservation
var _map_root: MapLoader
var _ensure_visual: Callable
var _navigators: Dictionary = {}
## 同帧 coalesce：多次 refresh_dynamic_pathing 只 flush 一次。
var _pathing_refresh_queued: bool = false


func initialize(map_root: MapLoader, ensure_visual: Callable) -> void:
	shutdown()
	_map_root = map_root
	_ensure_visual = ensure_visual
	if _map_root == null:
		return
	pathing = _map_root.get_pathing_map()
	path_query = PathQuery.new()
	path_query.bind_pathing(pathing)
	cell_reservation = PathCellReservation.new()
	path_query.bind_reservation(cell_reservation)
	path_query.prepare_navigation()
	var hf := _map_root.get_heightfield_dict()
	heightfield = Wc3Heightfield.from_dict(hf, true) if not hf.is_empty() else null
	crowd_query = UnitCrowdQuery.new()
	crowd_query.configure(_map_root.get_unit_layer(), _map_root.get_id_catalog())


func shutdown() -> void:
	for ref: WeakRef in _navigators.values():
		var nav := ref.get_ref() as UnitNavigator
		if not is_instance_valid(nav):
			continue
		if nav.locomotion_changed.is_connected(_on_locomotion_changed):
			nav.locomotion_changed.disconnect(_on_locomotion_changed)
		var exiting := _on_navigator_exiting.bind(nav.get_instance_id())
		if nav.tree_exiting.is_connected(exiting):
			nav.tree_exiting.disconnect(exiting)
		nav.stop()
		nav.configure(null, null, null, null)
	_navigators.clear()
	_map_root = null
	_ensure_visual = Callable()
	path_query = null
	pathing = null
	heightfield = null
	crowd_query = null
	cell_reservation = null


func _exit_tree() -> void:
	shutdown()


func _track(nav: UnitNavigator) -> void:
	var id := nav.get_instance_id()
	if not _navigators.has(id):
		_navigators[id] = weakref(nav)
		nav.tree_exiting.connect(_on_navigator_exiting.bind(id), CONNECT_ONE_SHOT)
	if not nav.locomotion_changed.is_connected(_on_locomotion_changed):
		nav.locomotion_changed.connect(_on_locomotion_changed)


func _on_navigator_exiting(id: int) -> void:
	_navigators.erase(id)


func _on_locomotion_changed(moving: bool) -> void:
	locomotion_changed.emit(moving)


func ensure_navigator(unit: Node3D) -> UnitNavigator:
	if unit == null or not is_instance_valid(unit):
		return null
	var visual: Unit = _ensure_visual.call(unit) as Unit if _ensure_visual.is_valid() else Unit.of(unit)
	var existing := unit.get_node_or_null("UnitNavigator") as UnitNavigator
	if existing != null:
		existing.configure(path_query, heightfield, crowd_query, cell_reservation)
		existing.set_visual(visual)
		apply_move_stats(unit, existing)
		_track(existing)
		return existing
	var nav := UnitNavigator.new()
	nav.name = "UnitNavigator"
	# 先 configure 再进树：即使 _ready 延后，query 也已就绪。
	nav.configure(path_query, heightfield, crowd_query, cell_reservation)
	nav.set_visual(visual)
	apply_move_stats(unit, nav)
	unit.add_child(nav)
	_track(nav)
	return nav


func apply_move_stats(unit: Node3D, nav: UnitNavigator) -> void:
	if unit == null or nav == null:
		return
	var d: Dictionary = unit.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	if tid.is_empty():
		return
	var spd := 0.0
	var turn := 0.0
	var radius := 0.0
	Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
	Wc3DefStore.ensure_table(UnitDataDef.TABLE_NAME)
	var bal := Wc3DefStore.get_row(UnitBalanceDef.TABLE_NAME, tid) as UnitBalanceDef
	if bal != null and bal.spd > 0.0:
		spd = bal.spd
	var data := Wc3DefStore.get_row(UnitDataDef.TABLE_NAME, tid) as UnitDataDef
	if data != null and data.turn_rate > 0.0:
		turn = data.turn_rate
	if crowd_query != null:
		radius = crowd_query.radius_for_unit(unit)
	nav.apply_unit_stats(spd, turn, radius)
	var dc := DefendController.of(unit)
	nav.speed_mul = dc.speed_mul() if dc != null else 1.0
	# 农民 soft 分离略放大，减轻采金/伐木叠人（不改 UnitBalance.collision 权威值）
	if tid == HarvestController.WORKER_PEASANT:
		nav.separation_radius_mul = 1.45


func refresh_dynamic_pathing() -> void:
	## 同帧多次训兵/开建合并为一次全量 blit + A* 重建。
	if _pathing_refresh_queued:
		return
	_pathing_refresh_queued = true
	call_deferred("_flush_dynamic_pathing")


func _flush_dynamic_pathing() -> void:
	_pathing_refresh_queued = false
	if _map_root == null:
		return
	# 动态脚印变更后：数据与叠层必须同源，否则会出现「蓝格可摆」或「叠层过期」
	if bool(_map_root.get("show_pathing_ground")) and _map_root.has_method("_rebuild_pathing_overlay"):
		_map_root.call("_rebuild_pathing_overlay")
	elif _map_root.has_method("_apply_dynamic_pathing"):
		_map_root.call("_apply_dynamic_pathing")
	elif _map_root.has_method("set_pathing_map") and pathing != null:
		_map_root.set_pathing_map(pathing)
	if path_query != null:
		path_query.prepare_navigation()


## 同帧大幅改单位坐标后调用，避免 crowd 空间哈希漏检。
func invalidate_crowd_index() -> void:
	if crowd_query != null:
		crowd_query.invalidate()


func bind_pathing(value: Wc3PathingMap) -> void:
	pathing = value
	if path_query != null:
		path_query.bind_pathing(value)
		path_query.prepare_navigation()
