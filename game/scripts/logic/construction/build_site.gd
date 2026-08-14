class_name BuildSite
extends Node

## 工地 runtime：人族可见施工。
## - 0 工人 → 暂停进度
## - N 工人 → 进度速率 ∝ N（对齐「效率与人数正相关」）
## - 额外资源：按 UnitBalance goldRep/lumberRep 与进度增量结算（首单造价已在 BuildOrder 扣过）
## - Ahrp（AbilityData）提供多工时间系数 DataB（缺省 1.0）

signal progress_changed(elapsed: float, total: float, ratio: float)
signal build_completed(order: BuildOrder, site_wc3: Vector2, owner: int)
signal builder_joined(site: Node, builder: Node3D)
signal builder_left(site: Node, builder: Node3D)
signal paused_changed(paused: bool)

const STATE_IDLE := 0
const STATE_BUILDING := 1
const STATE_DONE := 2

## Ahrp 缺省：每名工人等效 1.0× 基准速率；DataB 可抬高修理吞吐
const DEFAULT_REPAIR_TIME_RATIO := 1.0


var _order: BuildOrder = null
var _state: int = STATE_IDLE
var _elapsed: float = 0.0
var _owner: int = 0
var _active_builders: Array[Node3D] = []
var _session: GameSession = null
var _paused: bool = true
## 已按进度结算过的修理资源比例累计（0..1），避免重复扣
var _repair_settled_ratio: float = 0.0
var _repair_time_ratio: float = DEFAULT_REPAIR_TIME_RATIO


func _ready() -> void:
	set_process(false)


func configure_session(session: GameSession) -> void:
	_session = session


func start(order: BuildOrder, player_owner: int) -> void:
	if _state != STATE_IDLE or order == null:
		return
	_order = order
	_owner = player_owner
	_state = STATE_BUILDING
	_elapsed = 0.0
	_repair_settled_ratio = 0.0
	_repair_time_ratio = _load_ahrp_time_ratio()
	_paused = true
	set_process(true)


func cancel() -> void:
	if _state != STATE_BUILDING:
		return
	_state = STATE_DONE
	set_process(false)


func is_active() -> bool:
	return _state == STATE_BUILDING


func is_paused() -> bool:
	return _paused


func elapsed() -> float:
	return _elapsed


func total() -> float:
	return _order.build_time_sec if _order != null else 0.0


func current_order() -> BuildOrder:
	return _order


func builder_count() -> int:
	return _active_builders.size()


func active_builders() -> Array[Node3D]:
	return _active_builders.duplicate()


func add_builder(builder: Node3D) -> bool:
	if builder == null or _state != STATE_BUILDING:
		return false
	if _active_builders.has(builder):
		return false
	_active_builders.append(builder)
	_refresh_pause()
	builder_joined.emit(self, builder)
	return true


func remove_builder(builder: Node3D) -> void:
	if builder == null:
		return
	var idx := _active_builders.find(builder)
	if idx < 0:
		return
	_active_builders.remove_at(idx)
	_refresh_pause()
	builder_left.emit(self, builder)


func _refresh_pause() -> void:
	var want_pause := _active_builders.is_empty()
	if want_pause == _paused:
		return
	_paused = want_pause
	paused_changed.emit(_paused)


func _process(delta: float) -> void:
	if _state != STATE_BUILDING or _order == null:
		return
	if _paused or _active_builders.is_empty():
		return
	var n := _active_builders.size()
	var speed := float(n) * _repair_time_ratio
	var prev_ratio := 0.0
	var total_sec: float = _order.build_time_sec
	if total_sec <= 0.0:
		total_sec = 1.0
	prev_ratio = clampf(_elapsed / total_sec, 0.0, 1.0)
	_elapsed += delta * speed
	var ratio: float = clampf(_elapsed / total_sec, 0.0, 1.0)
	_settle_repair_cost(prev_ratio, ratio, n)
	progress_changed.emit(_elapsed, total_sec, ratio)
	if _elapsed >= total_sec:
		_state = STATE_DONE
		_order.state = BuildOrder.STATE_DONE
		set_process(false)
		build_completed.emit(_order, _order.site_wc3, _owner)


## 进度推进时按 goldRep/lumberRep 扣「修理」资源。
## 首单建造费已付；此处对「多人加速多出来的进度」额外扣（n>=1 时按全量进度×rep 结算差额）。
## 简化对齐体验：每推进 Δratio，扣 Δratio * goldRep/lumberRep；多人只加速不重复乘 n（费用跟 HP/进度走）。
func _settle_repair_cost(prev_ratio: float, new_ratio: float, _builder_n: int) -> void:
	if _session == null or _order == null:
		return
	var delta_r := maxf(new_ratio - maxf(prev_ratio, _repair_settled_ratio), 0.0)
	if delta_r <= 0.0:
		return
	var bid := _order.building_id
	var g := int(round(float(BuildingCatalog.get_gold_rep(bid)) * delta_r))
	var l := int(round(float(BuildingCatalog.get_lumber_rep(bid)) * delta_r))
	# 首单已付 goldcost；修理费从「超过已付进度对应造价」的部分收。
	# 更简明：仅当 builder≥2 时收修理费（辅助建造额外消耗）。
	if _active_builders.size() < 2:
		_repair_settled_ratio = new_ratio
		return
	if g <= 0 and l <= 0:
		_repair_settled_ratio = new_ratio
		return
	var stock: PlayerStock = _session.local_stock()
	if stock == null:
		return
	if not stock.try_spend(g, l):
		# 资源不够：踢掉多余工人，只留 1 人（暂停加速）
		while _active_builders.size() > 1:
			var extra: Node3D = _active_builders[_active_builders.size() - 1]
			remove_builder(extra)
		return
	_repair_settled_ratio = new_ratio


func _load_ahrp_time_ratio() -> float:
	var store := _def_store()
	if store == null:
		return DEFAULT_REPAIR_TIME_RATIO
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	var row: Resource = store.get_row(AbilityDataDef.TABLE_NAME, "Ahrp")
	if row == null:
		row = store.get_row(AbilityDataDef.TABLE_NAME, "Arep")
	if row is AbilityDataDef:
		var b: float = float((row as AbilityDataDef).data_b1)
		if b > 0.01:
			# DataB≈1.5 → 单工仍 1x，作轻微加速系数夹在 0.75..2
			return clampf(b / 1.5, 0.75, 2.0)
	return DEFAULT_REPAIR_TIME_RATIO


func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


## selftest / 外部可读
func _process_speedup() -> float:
	if _active_builders.is_empty():
		return 0.0
	return float(_active_builders.size()) * _repair_time_ratio
