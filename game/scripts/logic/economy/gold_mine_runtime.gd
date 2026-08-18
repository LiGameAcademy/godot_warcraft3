class_name GoldMineRuntime
extends Node

## 中立金矿运行时（ngol）：储量、同时进矿人数、FIFO 进矿权。
## 「5 连连看」= 主城贴矿时 5 农民效率最高（约 1 人在矿内、4 人在路上），不是队外排成一列。

signal slot_available
signal gold_changed(remaining: int)
signal depleted

const META_KEY := "gold_mine_runtime"
const GOLD_MINE_TYPE := "ngol"
## 矿口弧形散开间距（WC3）。
const LANE_SPACING_WC3 := 56.0
## 相对矿心的候位点外推（在 collision 之外）。
const ENTRANCE_OFFSET_WC3 := 40.0
## 出矿点：贴金矿，只用 collision + 小余量（勿用 pathTex 半宽，否则离矿太远）。
const MINE_EXIT_MARGIN_WC3 := 16.0
## 改出矿/走廊布局时递增，强制重建缓存。
const CORRIDOR_LAYOUT_VERSION := 2
## 人族进矿时长（秒）。实机观感约 1.3；非 Ahar.Dur1（伐木）。
const DEFAULT_DWELL_SEC := 1.3
## 默认按 5 车道散开（对应最优农民数）。
const DEFAULT_LANE_COUNT := 5

var remaining_gold: int = 12500
## 同时在矿内人数。普通 Agld.DataB1≈1。
var max_inside: int = 1
var dwell_sec: float = DEFAULT_DWELL_SEC
## 矿口朝向：矿心 → 主城。
var queue_outward_wc3: Vector2 = Vector2(0.0, -1.0)

var _inside_ids: Array[int] = []
var _queue_ids: Array[int] = []
var _mine_radius_wc3: float = 100.0
## 储量耗尽后只发一次 depleted（塌陷由 Present 订阅）。
var _depleted_emitted: bool = false
## 对同一主城缓存固定运金走廊（端点 + 路点只算一次）。
var _corridor_hall_id: int = 0
var _corridor_layout_version: int = 0
var _corridor_mine_portal: Vector2 = Vector2.INF
var _corridor_hall_portal: Vector2 = Vector2.INF
var _corridor_dir: Vector2 = Vector2(0.0, -1.0)
var _corridor_to_hall: Array[Vector2] = []
var _corridor_to_mine: Array[Vector2] = []


static func is_gold_mine(node: Node) -> bool:
	if node == null:
		return false
	var d: Dictionary = node.get_meta("unit_data", {})
	return str(d.get("typeId", "")).strip_edges() == GOLD_MINE_TYPE


static func ensure(mine: Node3D) -> GoldMineRuntime:
	if mine == null or not is_instance_valid(mine):
		return null
	if not is_gold_mine(mine):
		return null
	var existing := mine.get_node_or_null("GoldMineRuntime") as GoldMineRuntime
	if existing != null:
		return existing
	if mine.has_meta(META_KEY):
		var m: Variant = mine.get_meta(META_KEY)
		if m is GoldMineRuntime and is_instance_valid(m):
			return m as GoldMineRuntime
	var rt := GoldMineRuntime.new()
	rt.name = "GoldMineRuntime"
	mine.add_child(rt)
	rt._bootstrap_from_mine()
	mine.set_meta(META_KEY, rt)
	return rt


## 矿口弧形候位点（仅排队散开用，不参与运金走廊）。
func entrance_slot_wc3(lane_index: int, lane_count: int = DEFAULT_LANE_COUNT) -> Vector2:
	var mine := get_parent() as Node3D
	if mine == null:
		return Vector2.ZERO
	var center := Wc3Coords.godot_to_wc3_xy(mine.global_position)
	var outward := _outward()
	var perp := Vector2(-outward.y, outward.x)
	var n := maxi(lane_count, 1)
	var mid := (float(n) - 1.0) * 0.5
	var lateral := (float(clampi(lane_index, 0, n - 1)) - mid) * LANE_SPACING_WC3
	var along := _mine_radius_wc3 + ENTRANCE_OFFSET_WC3
	return center + outward * along + perp * lateral


## 矿↔主城最短连线两端：统一出矿点 + 统一交货点。
## 出矿用 collision 半径贴金矿；交货用 pathTex 半宽避免站进主城脚印。
static func corridor_portals_wc3(
	mine: Node3D,
	hall: Node3D,
	p_mine_radius_wc3: float = 100.0,
	hall_radius_wc3: float = 176.0,
	mine_margin_wc3: float = MINE_EXIT_MARGIN_WC3,
	hall_margin_wc3: float = ENTRANCE_OFFSET_WC3
) -> Dictionary:
	if mine == null or hall == null:
		return {}
	var mine_xy := Wc3Coords.godot_to_wc3_xy(mine.global_position)
	var hall_xy := Wc3Coords.godot_to_wc3_xy(hall.global_position)
	var to_hall := hall_xy - mine_xy
	if to_hall.length_squared() < 1.0:
		to_hall = Vector2(0.0, -1.0)
	var dir := to_hall.normalized()
	var mine_r := maxf(p_mine_radius_wc3, 32.0) + mine_margin_wc3
	var hall_r := maxf(hall_radius_wc3, 32.0) + hall_margin_wc3
	# 矿上离主城最近的点；主城上离矿最近的点
	return {
		"mine": mine_xy + dir * mine_r,
		"hall": hall_xy - dir * hall_r,
		"dir": dir,
		"mine_center": mine_xy,
		"hall_center": hall_xy,
		"mine_dist": mine_r,
		"hall_dist": hall_r,
	}


## 全矿共享的固定运金走廊（同一 hall 只算一次端点 + 路点）。
## 返回 { mine, hall, dir, to_hall: Array[Vector2], to_mine: Array[Vector2] }
func shared_corridor_portals(
	hall: Node3D,
	path_query: Variant,
	mine_half_wc3: float,
	hall_half_wc3: float
) -> Dictionary:
	if hall == null or not is_instance_valid(hall):
		return {}
	var hid := hall.get_instance_id()
	if (
		hid == _corridor_hall_id
		and _corridor_layout_version == CORRIDOR_LAYOUT_VERSION
		and _corridor_mine_portal != Vector2.INF
		and _corridor_hall_portal != Vector2.INF
	):
		return {
			"mine": _corridor_mine_portal,
			"hall": _corridor_hall_portal,
			"dir": _corridor_dir,
			"to_hall": _corridor_to_hall.duplicate(),
			"to_mine": _corridor_to_mine.duplicate(),
		}
	var mine := get_parent() as Node3D
	if mine == null:
		return {}
	# mine_half 传入 collision；出矿贴矿。hall 用 footprint 半宽。
	var raw := corridor_portals_wc3(
		mine,
		hall,
		mine_half_wc3,
		hall_half_wc3,
		MINE_EXIT_MARGIN_WC3,
		ENTRANCE_OFFSET_WC3
	)
	if raw.is_empty():
		return {}
	var dir: Vector2 = raw.get("dir", Vector2(0.0, -1.0)) as Vector2
	var mine_center: Vector2 = raw.get("mine_center", Vector2.ZERO) as Vector2
	var hall_center: Vector2 = raw.get("hall_center", Vector2.ZERO) as Vector2
	var mine_dist: float = float(raw.get("mine_dist", mine_half_wc3))
	var hall_dist: float = float(raw.get("hall_dist", hall_half_wc3))
	var mine_portal: Vector2 = raw.get("mine", Vector2.ZERO) as Vector2
	var hall_portal: Vector2 = raw.get("hall", Vector2.ZERO) as Vector2
	if path_query != null and path_query.has_method("snap_along_dir_walkable"):
		# 从贴矿的理想距离往外找第一可走格 → 尽量靠近金矿
		var sm: Dictionary = path_query.call(
			"snap_along_dir_walkable", mine_center, dir, mine_dist, 16
		)
		if bool(sm.get("ok", false)):
			mine_portal = sm["wc3"] as Vector2
		var sh: Dictionary = path_query.call(
			"snap_along_dir_walkable", hall_center, -dir, hall_dist, 16
		)
		if bool(sh.get("ok", false)):
			hall_portal = sh["wc3"] as Vector2
	elif path_query != null and path_query.has_method("snap_to_walkable"):
		var sm2: Dictionary = path_query.call(
			"snap_to_walkable", mine_portal.x, mine_portal.y, 12
		)
		if bool(sm2.get("ok", false)):
			mine_portal = sm2["wc3"] as Vector2
		var sh2: Dictionary = path_query.call(
			"snap_to_walkable", hall_portal.x, hall_portal.y, 12
		)
		if bool(sh2.get("ok", false)):
			hall_portal = sh2["wc3"] as Vector2
	_corridor_hall_id = hid
	_corridor_layout_version = CORRIDOR_LAYOUT_VERSION
	_corridor_mine_portal = mine_portal
	_corridor_hall_portal = hall_portal
	_corridor_dir = dir
	_rebuild_corridor_waypoints(path_query, mine_portal, hall_portal)
	return {
		"mine": mine_portal,
		"hall": hall_portal,
		"dir": dir,
		"to_hall": _corridor_to_hall.duplicate(),
		"to_mine": _corridor_to_mine.duplicate(),
	}


func corridor_waypoints_to_hall() -> Array[Vector2]:
	return _corridor_to_hall.duplicate()


func corridor_waypoints_to_mine() -> Array[Vector2]:
	return _corridor_to_mine.duplicate()


func _rebuild_corridor_waypoints(
	path_query: Variant,
	mine_portal: Vector2,
	hall_portal: Vector2
) -> void:
	_corridor_to_hall.clear()
	_corridor_to_mine.clear()
	if path_query == null or not path_query.has_method("find_path"):
		_corridor_to_hall.append(hall_portal)
		_corridor_to_mine.append(mine_portal)
		return
	# 固定走廊：忽略单位预约，只对静态 pathing 算一次
	var res: Dictionary = path_query.call(
		"find_path", mine_portal, hall_portal, 0, 0, true
	)
	if bool(res.get("ok", false)):
		var wps: Array = res.get("waypoints", [])
		for p in wps:
			if p is Vector2:
				_corridor_to_hall.append(p)
	if _corridor_to_hall.is_empty():
		_corridor_to_hall.append(hall_portal)
	# 回程：反向路点 + 确保终点是矿门
	for i in range(_corridor_to_hall.size() - 1, -1, -1):
		_corridor_to_mine.append(_corridor_to_hall[i])
	if (
		_corridor_to_mine.is_empty()
		or _corridor_to_mine[_corridor_to_mine.size() - 1].distance_to(mine_portal) > 1.0
	):
		_corridor_to_mine.append(mine_portal)
	# 去程终点必须是交货点
	if _corridor_to_hall[_corridor_to_hall.size() - 1].distance_to(hall_portal) > 1.0:
		_corridor_to_hall.append(hall_portal)


func invalidate_corridor_cache() -> void:
	_corridor_hall_id = 0
	_corridor_layout_version = 0
	_corridor_mine_portal = Vector2.INF
	_corridor_hall_portal = Vector2.INF
	_corridor_dir = Vector2(0.0, -1.0)
	_corridor_to_hall.clear()
	_corridor_to_mine.clear()


## 兼容旧调用：统一交货点（不再按车道横移）。
static func dropoff_slot_wc3(
	hall: Node3D,
	mine: Node3D,
	_lane_index: int = 0,
	_lane_count: int = DEFAULT_LANE_COUNT,
	hall_radius_wc3: float = 176.0
) -> Vector2:
	var mine_r := 100.0
	if mine != null:
		var rt := mine.get_node_or_null("GoldMineRuntime") as GoldMineRuntime
		if rt != null:
			mine_r = rt.mine_radius_wc3()
	var portals := corridor_portals_wc3(mine, hall, mine_r, hall_radius_wc3)
	return portals.get("hall", Vector2.ZERO) as Vector2


func mine_radius_wc3() -> float:
	return _mine_radius_wc3


func is_depleted() -> bool:
	return remaining_gold <= 0 or _depleted_emitted


func has_gold() -> bool:
	return remaining_gold > 0 and not _depleted_emitted


func _bootstrap_from_mine() -> void:
	var mine := get_parent() as Node3D
	if mine == null:
		return
	var d: Dictionary = mine.get_meta("unit_data", {})
	var amt := int(d.get("goldAmount", -1))
	if amt < 0:
		amt = _agld_default_gold()
	remaining_gold = maxi(0, amt)
	max_inside = maxi(1, _agld_max_inside())
	dwell_sec = DEFAULT_DWELL_SEC
	_mine_radius_wc3 = _collision_radius(str(d.get("typeId", GOLD_MINE_TYPE)))


func set_queue_outward_from_to(from_wc3: Vector2, toward_wc3: Vector2) -> void:
	var delta := toward_wc3 - from_wc3
	if delta.length_squared() < 1.0:
		return
	queue_outward_wc3 = delta.normalized()


func inside_count() -> int:
	_prune_dead()
	return _inside_ids.size()


func queue_count() -> int:
	_prune_dead()
	return _queue_ids.size()


func is_inside(peasant: Node) -> bool:
	if peasant == null:
		return false
	return _inside_ids.has(peasant.get_instance_id())


func queue_index(peasant: Node) -> int:
	if peasant == null:
		return -1
	_prune_dead()
	return _queue_ids.find(peasant.get_instance_id())


func try_enter(peasant: Node) -> bool:
	if peasant == null or not is_instance_valid(peasant):
		return false
	if is_depleted():
		return false
	_prune_dead()
	var id := peasant.get_instance_id()
	if _inside_ids.has(id):
		return true
	if not _queue_ids.is_empty() and _queue_ids[0] != id:
		return false
	if _inside_ids.size() >= max_inside:
		return false
	_queue_ids.erase(id)
	_inside_ids.append(id)
	return true


func enqueue(peasant: Node) -> int:
	if peasant == null or not is_instance_valid(peasant):
		return -1
	_prune_dead()
	var id := peasant.get_instance_id()
	if _inside_ids.has(id):
		return -1
	var idx := _queue_ids.find(id)
	if idx >= 0:
		return idx
	_queue_ids.append(id)
	return _queue_ids.size() - 1


func leave_queue(peasant: Node) -> void:
	if peasant == null:
		return
	_queue_ids.erase(peasant.get_instance_id())


func exit_mine(peasant: Node, gold_taken: int) -> int:
	if peasant == null:
		return 0
	var id := peasant.get_instance_id()
	_inside_ids.erase(id)
	var taken := clampi(gold_taken, 0, remaining_gold)
	if taken > 0:
		remaining_gold -= taken
		_sync_gold_meta()
		gold_changed.emit(remaining_gold)
	_notify_if_empty()
	slot_available.emit()
	return taken


func _notify_if_empty() -> void:
	if remaining_gold > 0 or _depleted_emitted:
		return
	_depleted_emitted = true
	depleted.emit()


func cancel_inside(peasant: Node) -> void:
	if peasant == null:
		return
	_inside_ids.erase(peasant.get_instance_id())
	slot_available.emit()


## 兼容旧名：等同 entrance_slot_wc3（按车道，非 FIFO 挤位）。
func wait_slot_wc3(index: int, lane_count: int = DEFAULT_LANE_COUNT) -> Vector2:
	return entrance_slot_wc3(index, lane_count)


func _outward() -> Vector2:
	if queue_outward_wc3.length_squared() < 0.25:
		return Vector2(0.0, -1.0)
	return queue_outward_wc3.normalized()


func _prune_dead() -> void:
	_inside_ids = _inside_ids.filter(func(id: int) -> bool: return is_instance_id_valid(id))
	_queue_ids = _queue_ids.filter(func(id: int) -> bool: return is_instance_id_valid(id))


func _sync_gold_meta() -> void:
	var mine := get_parent()
	if mine == null:
		return
	var d: Dictionary = mine.get_meta("unit_data", {})
	d["goldAmount"] = remaining_gold
	mine.set_meta("unit_data", d)


func _agld_default_gold() -> int:
	Wc3DefStore.ensure_table(AbilityDataDef.TABLE_NAME)
	var ab := Wc3DefStore.get_row(AbilityDataDef.TABLE_NAME, "Agld") as AbilityDataDef
	if ab != null and ab.data_a1 > 0.0:
		return int(ab.data_a1)
	return 12500


func _agld_max_inside() -> int:
	Wc3DefStore.ensure_table(AbilityDataDef.TABLE_NAME)
	var ab := Wc3DefStore.get_row(AbilityDataDef.TABLE_NAME, "Agld") as AbilityDataDef
	if ab != null and ab.data_b1 > 0.0:
		return int(ab.data_b1)
	return 1


func _collision_radius(type_id: String) -> float:
	Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
	var bal := Wc3DefStore.get_row(UnitBalanceDef.TABLE_NAME, type_id) as UnitBalanceDef
	if bal != null and bal.collision > 0.0:
		return bal.collision
	return 100.0
