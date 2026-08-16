class_name BuildSite
extends Node

## 工地 runtime：人族可见施工 / Powerbuild。
## 原作（Ahrp Repair / Peasant Powerbuild）：
## - 首个农民到位后才有半成品；0 工人 → 暂停
## - 速率：1 + (N-1) * PowerbuildRate（TFT≈0.6，Ahrp DataD）
## - 帮工附加费：随进度连续扣，非整次 join 扣费
##   本帧追加 = 造价 × DataC(0.15) × (N-1) × Δratio；全程 N 人 ≈ 造价×15%×(N-1)
## - 普通修理用 DataA=0.35×goldRep，建造加速用 DataC，二者不同

signal progress_changed(elapsed: float, total: float, ratio: float)
signal build_completed(order: BuildOrder, site_wc3: Vector2, owner: int)
signal builder_joined(site: Node, builder: Node3D)
signal builder_left(site: Node, builder: Node3D)
signal paused_changed(paused: bool)

const STATE_IDLE := 0
const STATE_BUILDING := 1
const STATE_DONE := 2

## TFT 默认；SLK DataD1 若为 RoC 0.5 仍可用，缺省抬到 0.6
const DEFAULT_POWERBUILD_RATE := 0.6
const DEFAULT_POWERBUILD_COST := 0.15


var _order: BuildOrder = null
var _state: int = STATE_IDLE
var _elapsed: float = 0.0
var _owner: int = 0
var _active_builders: Array[Node3D] = []
var _session: GameSession = null
var _paused: bool = true
## 已结算过的 Powerbuild 进度（0..1）
var _powerbuild_settled_ratio: float = 0.0
var _powerbuild_rate: float = DEFAULT_POWERBUILD_RATE
var _powerbuild_cost: float = DEFAULT_POWERBUILD_COST
## 小数资源累计，避免每帧 round 丢费或脉冲式整扣
var _powerbuild_gold_acc: float = 0.0
var _powerbuild_lumber_acc: float = 0.0


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
	_powerbuild_settled_ratio = 0.0
	_powerbuild_gold_acc = 0.0
	_powerbuild_lumber_acc = 0.0
	_load_ahrp_powerbuild()
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
	# 原作：首工 100%；每名额外工 +PowerbuildRate（≈60%）
	var speed := 1.0 + float(maxi(n - 1, 0)) * _powerbuild_rate
	var total_sec: float = _order.build_time_sec
	if total_sec <= 0.0:
		total_sec = 1.0
	var prev_ratio := clampf(_elapsed / total_sec, 0.0, 1.0)
	_elapsed += delta * speed
	var ratio: float = clampf(_elapsed / total_sec, 0.0, 1.0)
	_settle_powerbuild_cost(prev_ratio, ratio, n)
	progress_changed.emit(_elapsed, total_sec, ratio)
	if _elapsed >= total_sec:
		_state = STATE_DONE
		_order.state = BuildOrder.STATE_DONE
		set_process(false)
		build_completed.emit(_order, _order.site_wc3, _owner)


## Powerbuild 附加费：按进度周期累计扣，不是 join 时一次付清。
## 本帧：造价 × DataC × (N-1) × Δratio → 累加后扣整数部分。
## 首单 goldcost 已在下单时付清；此处只收加速附加费。
func _settle_powerbuild_cost(prev_ratio: float, new_ratio: float, builder_n: int) -> void:
	if _session == null or _order == null:
		return
	var delta_r := maxf(new_ratio - maxf(prev_ratio, _powerbuild_settled_ratio), 0.0)
	if delta_r <= 0.0:
		return
	var extra := maxi(builder_n - 1, 0)
	if extra <= 0:
		_powerbuild_settled_ratio = new_ratio
		return
	var gold_base := float(_order.gold_spent)
	var lumber_base := float(_order.lumber_spent)
	if gold_base <= 0.0 and lumber_base <= 0.0:
		var bid := _order.building_id
		gold_base = float(BuildingCatalog.get_gold_cost(bid))
		lumber_base = float(BuildingCatalog.get_lumber_cost(bid))
	var mul := _powerbuild_cost * float(extra)
	var add_g := gold_base * mul * delta_r
	var add_l := lumber_base * mul * delta_r
	_powerbuild_gold_acc += add_g
	_powerbuild_lumber_acc += add_l
	var g := int(floor(_powerbuild_gold_acc))
	var l := int(floor(_powerbuild_lumber_acc))
	if g <= 0 and l <= 0:
		_powerbuild_settled_ratio = new_ratio
		return
	var stock: PlayerStock = _session.local_stock()
	if stock == null:
		_powerbuild_settled_ratio = new_ratio
		return
	if not stock.try_spend(g, l):
		# 不够付：回滚本帧累计，踢掉帮工；已推进的进度不再补扣（原作踢人停加速）
		_powerbuild_gold_acc -= add_g
		_powerbuild_lumber_acc -= add_l
		while _active_builders.size() > 1:
			var kicked: Node3D = _active_builders[_active_builders.size() - 1]
			remove_builder(kicked)
		_powerbuild_settled_ratio = new_ratio
		return
	_powerbuild_gold_acc -= float(g)
	_powerbuild_lumber_acc -= float(l)
	_powerbuild_settled_ratio = new_ratio


## Ahrp：DataC=Powerbuild Cost(0.15)，DataD=Powerbuild Rate(0.5 RoC / 常用 0.6 TFT)。
func _load_ahrp_powerbuild() -> void:
	_powerbuild_rate = DEFAULT_POWERBUILD_RATE
	_powerbuild_cost = DEFAULT_POWERBUILD_COST
	var store := _def_store()
	if store == null:
		return
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	var row: Resource = store.get_row(AbilityDataDef.TABLE_NAME, "Ahrp")
	if row == null:
		row = store.get_row(AbilityDataDef.TABLE_NAME, "Arep")
	if not (row is AbilityDataDef):
		return
	var ab := row as AbilityDataDef
	if ab.data_c1 > 0.01:
		_powerbuild_cost = clampf(ab.data_c1, 0.05, 0.5)
	if ab.data_d1 > 0.01:
		# RoC 导出常为 0.5；TFT 观感用至少 0.6
		_powerbuild_rate = clampf(maxf(ab.data_d1, DEFAULT_POWERBUILD_RATE), 0.25, 1.0)


func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


## selftest / 外部可读
func _process_speedup() -> float:
	if _active_builders.is_empty():
		return 0.0
	return 1.0 + float(_active_builders.size() - 1) * _powerbuild_rate
