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

const STATE_IDLE := 0
const STATE_BUILDING := 1
const STATE_DONE := 2


var _order: BuildOrder = null
var _state: int = STATE_IDLE
var _elapsed: float = 0.0
var _owner: int = 0


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


func _process(delta: float) -> void:
	if _state != STATE_BUILDING or _order == null:
		return
	_elapsed += delta
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
