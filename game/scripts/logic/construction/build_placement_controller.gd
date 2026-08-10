class_name BuildPlacementController
extends RefCounted

## 建造瞄准态：玩家按下建造按钮后进入；鼠标光标 → 地面坐标 → 跟手 ghost。
## ghost 只是一根 Node3D（由调用方持有 / 增挂 / 删），本类只负责：
##   - 跟踪光标地面坐标
##   - 调用 PlacementRules.can_build_at 校验
##   - 通知 ghost 颜色
##   - 在玩家点下时返回 site_wc3 + 接单给 CommandRouter.issue_build
##
## 关键：ghost footprint 的 reservation 也要写入，避免玩家在工地边缘相互遮挡。
## 当前简化：瞄准过程中还没扣除资源、不在 reservation 登记正式占地（只有 issue_build 成功才登记）。

signal placement_changed(building_id: String, site_wc3: Vector2, valid: bool)
signal placement_committed(building_id: String, site_wc3: Vector2) ## 玩家点下
signal placement_cancelled()


var _building_id: String = ""
var _screen_pos: Vector2 = Vector2.ZERO
var _site_wc3: Vector2 = Vector2.INF
var _valid: bool = false
var _get_ground_hit: Callable = Callable() ## () -> Vector3（godot 坐标，已含地表 y）
var _get_heightfield: Callable = Callable() ## () -> Wc3Heightfield
var _get_pathing: Callable = Callable() ## () -> Wc3PathingMap
var _get_cell_reservation: Callable = Callable() ## () -> PathCellReservation


func configure(
	get_ground_hit: Callable,
	get_heightfield: Callable,
	get_pathing: Callable,
	get_cell_reservation: Callable
) -> void:
	_get_ground_hit = get_ground_hit
	_get_heightfield = get_heightfield
	_get_pathing = get_pathing
	_get_cell_reservation = get_cell_reservation


func is_active() -> bool:
	return not _building_id.is_empty()


func current_building_id() -> String:
	return _building_id


func current_site_wc3() -> Vector2:
	return _site_wc3


func is_valid() -> bool:
	return _valid


func begin(building_id: String) -> void:
	_building_id = building_id
	_site_wc3 = Vector2.INF
	_valid = false
	placement_changed.emit(_building_id, _site_wc3, _valid)


func cancel() -> void:
	if _building_id.is_empty():
		return
	_building_id = ""
	_site_wc3 = Vector2.INF
	_valid = false
	placement_cancelled.emit()


## 鼠标移动 / 帧 tick 时由 Director 调。一次采集 → 一次判定 → 一次 emit。
func update_screen(screen_pos: Vector2) -> void:
	_screen_pos = screen_pos
	if _building_id.is_empty():
		return
	_recompute()


## 玩家点下；返回 ok / site_wc3。
func commit() -> bool:
	if _building_id.is_empty() or not _valid:
		return false
	var bid := _building_id
	var site := _site_wc3
	_building_id = ""
	_site_wc3 = Vector2.INF
	_valid = false
	placement_committed.emit(bid, site)
	return true


func _recompute() -> void:
	if _building_id.is_empty():
		return
	var hit: Vector3 = _get_ground_hit.call() if _get_ground_hit.is_valid() else Vector3.INF
	if hit == Vector3.INF:
		_site_wc3 = Vector2.INF
		_valid = false
		placement_changed.emit(_building_id, _site_wc3, _valid)
		return
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	_site_wc3 = Vector2(hit.x * inv, -hit.z * inv)
	# 基础可建性：pathing 静态
	var pathing: Wc3PathingMap = _get_pathing.call() if _get_pathing.is_valid() else null
	_valid = PlacementRules.can_build_at(_building_id, _site_wc3, pathing, [])
	# 进一步：避免与其他已有的建筑 footprint 重叠（MapUnitLayer 已建模的"建筑"）
	placement_changed.emit(_building_id, _site_wc3, _valid)
