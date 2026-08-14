class_name BuildPlacementController
extends RefCounted

## 建造瞄准态：鼠标 → 地面 → **寻路格吸附** → footprint 逐格校验 → ghost。
## 格网 = PATHING_CELL（调试「小」格）；「中」格 = 4×4 寻路格。

signal placement_changed(building_id: String, site_wc3: Vector2, valid: bool)
signal placement_committed(building_id: String, site_wc3: Vector2)
signal placement_cancelled()


var _building_id: String = ""
var _screen_pos: Vector2 = Vector2.ZERO
var _site_wc3: Vector2 = Vector2.INF
var _valid: bool = false
var _footprint_sample: Dictionary = {}
var _get_ground_hit: Callable = Callable() ## (screen_pos) -> Vector3 godot
var _get_heightfield: Callable = Callable()
var _get_pathing: Callable = Callable()
var _get_cell_reservation: Callable = Callable()


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


## 最近一次 footprint 采样（供 Ghost 逐格上色）。
func current_footprint_sample() -> Dictionary:
	return _footprint_sample


func begin(building_id: String) -> void:
	_building_id = building_id
	_site_wc3 = Vector2.INF
	_valid = false
	_footprint_sample = {}
	placement_changed.emit(_building_id, _site_wc3, _valid)


func cancel() -> void:
	if _building_id.is_empty():
		return
	_building_id = ""
	_site_wc3 = Vector2.INF
	_valid = false
	_footprint_sample = {}
	placement_cancelled.emit()


func update_screen(screen_pos: Vector2) -> void:
	_screen_pos = screen_pos
	if _building_id.is_empty():
		return
	_recompute()


func commit() -> bool:
	if _building_id.is_empty() or not _valid:
		return false
	var bid := _building_id
	var site := _site_wc3
	_building_id = ""
	_site_wc3 = Vector2.INF
	_valid = false
	_footprint_sample = {}
	placement_committed.emit(bid, site)
	return true


func _recompute() -> void:
	if _building_id.is_empty():
		return
	var hit: Vector3 = (
		_get_ground_hit.call(_screen_pos) if _get_ground_hit.is_valid() else Vector3.INF
	)
	if hit == Vector3.INF:
		_site_wc3 = Vector2.INF
		_valid = false
		_footprint_sample = {}
		placement_changed.emit(_building_id, _site_wc3, _valid)
		return
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var raw := Vector2(hit.x * inv, -hit.z * inv)
	var pathing: Wc3PathingMap = _get_pathing.call() if _get_pathing.is_valid() else null
	_site_wc3 = PlacementRules.snap_site_wc3(_building_id, raw, pathing)
	_footprint_sample = PlacementRules.sample_footprint(_building_id, _site_wc3, pathing)
	_valid = bool(_footprint_sample.get("all_ok", false))
	placement_changed.emit(_building_id, _site_wc3, _valid)
