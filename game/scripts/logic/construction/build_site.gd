class_name BuildSite
extends Node

## 工地 runtime：BuildController.build_started 后启动。
## 状态机 IDLE → BUILDING → DONE
## timer 推进（基于 BuildOrder.build_time_sec，源自 UnitBalance.bldtm）
## 完工 emit build_completed(order, site_wc3, owner) →
##   Director 接管刷建筑（MapUnitLayer.add_one）+ 人口变化（PlayerStock.add_food_cap）
##
## F2-5 简化：
## - 工地幼体 / 全尺寸视觉由 Director 决定（暂 hide peasant 即可）
## - 建造动画（Stand Work / Birth）后置
## - BuildSite 自身只管 timer + 状态机

signal progress_changed(elapsed: float, total: float, ratio: float)
signal build_completed(order: BuildOrder, site_wc3: Vector2, owner: int)
## F2-C 多工：第二农民 join_via_repair 加速
signal builder_joined(site: Node, builder: Node3D)
signal builder_left(site: Node, builder: Node3D)

const STATE_IDLE := 0
const STATE_BUILDING := 1
const STATE_DONE := 2

## F2-C 多工加速系数：每多 1 个 builder +50% 进度速率（粗略，对齐体验优先）
const MULTI_BUILDER_SPEEDUP_PER_EXTRA := 0.5


var _order: BuildOrder = null
var _state: int = STATE_IDLE
var _elapsed: float = 0.0
var _owner: int = 0
## F2-C：参与建造的农民列表（人 MANY_VISIBLE 时可多）
var _active_builders: Array[Node3D] = []


func _ready() -> void:
	set_process(false)


## 接 BuildController.build_started 信号。
## owner：建造者 peasant 所属玩家 id（决定建筑归属 + 队伍色）。
func start(order: BuildOrder, owner: int) -> void:
	if _state != STATE_IDLE or order == null:
		return
	_order = order
	_owner = owner
	_state = STATE_BUILDING
	_elapsed = 0.0
	# primary builder 加入（_active_builders 留空等 arrived 时 add）
	set_process(true)


func cancel() -> void:
	if _state != STATE_BUILDING:
		return
	_state = STATE_DONE
	set_process(false)


func is_active() -> bool:
	return _state == STATE_BUILDING


func elapsed() -> float:
	return _elapsed


func total() -> float:
	return _order.build_time_sec if _order != null else 0.0


func current_order() -> BuildOrder:
	return _order


## 当前参与 builder 数
func builder_count() -> int:
	return _active_builders.size()


## F2-C：第二农民 Repair 加入（true=成功，false=拒绝）
func add_builder(builder: Node3D) -> bool:
	if builder == null or _state != STATE_BUILDING:
		return false
	if _active_builders.has(builder):
		return false
	_active_builders.append(builder)
	builder_joined.emit(self, builder)
	return true


## F2-C：builder 离开（完工 / 取消 / 死亡）
func remove_builder(builder: Node3D) -> void:
	if builder == null:
		return
	var idx := _active_builders.find(builder)
	if idx < 0:
		return
	_active_builders.remove_at(idx)
	builder_left.emit(self, builder)


func _process(delta: float) -> void:
	if _state != STATE_BUILDING or _order == null:
		return
	_elapsed += delta * _process_speedup()
	var total: float = _order.build_time_sec
	if total <= 0.0:
		total = 1.0
	var ratio: float = clampf(_elapsed / total, 0.0, 1.0)
	progress_changed.emit(_elapsed, total, ratio)
	if _elapsed >= total:
		_state = STATE_DONE
		_order.state = BuildOrder.STATE_DONE
		set_process(false)
		build_completed.emit(_order, _order.site_wc3, _owner)


## F2-C 多工加速系数：1 人 = 1x, 2 人 = 1.5x, 3 人 = 2x...
## 测试可读用（selftest_f2_build_system 验 _process_speedup）
func _process_speedup() -> float:
	var speedup := 1.0
	if _active_builders.size() > 1:
		speedup += float(_active_builders.size() - 1) * MULTI_BUILDER_SPEEDUP_PER_EXTRA
	return speedup
