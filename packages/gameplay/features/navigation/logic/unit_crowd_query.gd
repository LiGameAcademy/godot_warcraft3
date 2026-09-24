class_name UnitCrowdQuery
extends RefCounted
## 邻近单位查询：扫 MapUnitLayer 子节点，供 UnitNavigator soft 分离使用。
##
## 同帧多次查询共用一张空间哈希（O(N) 建索引 + O(k) 查询）；同帧改坐标后须 invalidate。

## 默认查询半径（WC3）：约覆盖数个农民碰撞圈
const DEFAULT_RANGE_WC3 := 192.0
## 空间桶边长（WC3）；与默认查询半径同量级，邻域桶数少。
const HASH_CELL_WC3 := 128.0

var _unit_layer: Node = null
var _catalog: Wc3IdCatalog = null
## typeId → 碰撞半径缓存
var _radius_cache: Dictionary = {}
var _index_frame: int = -1
var _indexed_child_count: int = -1
var _buckets: Dictionary = {} ## Vector2i -> Array[{node, pos, r, id, building}]


func configure(unit_layer: Node, catalog: Wc3IdCatalog) -> void:
	_unit_layer = unit_layer
	_catalog = catalog
	_radius_cache.clear()
	invalidate()


func invalidate() -> void:
	_index_frame = -1
	_indexed_child_count = -1
	_buckets.clear()


func is_ready() -> bool:
	return _unit_layer != null


## 取单位碰撞半径（UnitBalance.collision → PlacementRules）。
func radius_for_unit(unit: Node) -> float:
	if unit == null:
		return Wc3Coords.PATHING_CELL * 0.5
	var d: Dictionary = unit.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	return radius_for_type(tid)


func radius_for_type(type_id: String) -> float:
	if type_id.is_empty():
		return Wc3Coords.PATHING_CELL * 0.5
	if _radius_cache.has(type_id):
		return float(_radius_cache[type_id])
	var info: Dictionary = {}
	if _catalog != null:
		info = _catalog.lookup(type_id)
	var r := UnitPlacementRules.collision_radius_wc3(info)
	_radius_cache[type_id] = r
	return r


## 返回邻居列表：[{pos:Vector2, r:float}, ...]，不含 self。
## include_buildings=true：建筑也当硬圆挡一下（静态脚印外的视觉重叠）。
func neighbors_of(
	self_unit: Node,
	self_pos_wc3: Vector2,
	range_wc3: float = DEFAULT_RANGE_WC3,
	include_buildings: bool = false
) -> Array:
	var started := MatchHotpathMetrics.begin()
	var result: Array = _measured_neighbors_of(self_unit, self_pos_wc3, range_wc3, include_buildings)
	MatchHotpathMetrics.finish(&"crowd", started)
	return result


func _measured_neighbors_of(
	self_unit: Node,
	self_pos_wc3: Vector2,
	range_wc3: float = DEFAULT_RANGE_WC3,
	include_buildings: bool = false
) -> Array:
	var out: Array = []
	if _unit_layer == null:
		return out
	_ensure_index()
	var range_sq := range_wc3 * range_wc3
	var cell := HASH_CELL_WC3
	var span := maxi(1, int(ceil(range_wc3 / cell)) + 1)
	var cx := int(floor(self_pos_wc3.x / cell))
	var cy := int(floor(self_pos_wc3.y / cell))
	for gy in range(cy - span, cy + span + 1):
		for gx in range(cx - span, cx + span + 1):
			var bucket: Variant = _buckets.get(Vector2i(gx, gy), null)
			if bucket == null:
				continue
			for entry in bucket as Array:
				var n: Node3D = entry.get("node", null)
				if n == null or n == self_unit:
					continue
				if not include_buildings and bool(entry.get("building", false)):
					continue
				# 查询时再读实时坐标：同帧先移动再查仍可见（桶可能偏一格，靠 range 过滤）。
				if not WorldMembership.is_in_world(n):
					continue
				var pos: Vector2 = entry.get("pos", Vector2.ZERO)
				if is_instance_valid(n):
					var inv := 1.0 / Wc3Coords.WORLD_SCALE
					pos = Vector2(n.global_position.x * inv, -n.global_position.z * inv)
				if self_pos_wc3.distance_squared_to(pos) > range_sq:
					continue
				out.append({
					"pos": pos,
					"r": float(entry.get("r", 16.0)),
					"id": int(entry.get("id", 0)),
				})
	return out


func _ensure_index() -> void:
	var frame := Engine.get_process_frames()
	var child_count := 0 if _unit_layer == null else _unit_layer.get_child_count()
	if frame == _index_frame and child_count == _indexed_child_count:
		return
	_rebuild_index(frame)
	_indexed_child_count = child_count


func _rebuild_index(frame: int) -> void:
	_buckets.clear()
	_index_frame = frame
	if _unit_layer == null:
		return
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var cell := HASH_CELL_WC3
	for c in _unit_layer.get_children():
		if not (c is Node3D):
			continue
		var n := c as Node3D
		if not WorldMembership.is_in_world(n):
			continue
		if not n.has_meta("unit_data"):
			continue
		var d: Dictionary = n.get_meta("unit_data", {})
		var tid := str(d.get("typeId", "")).strip_edges()
		if tid.is_empty():
			continue
		if tid.to_lower() == "sloc":
			continue
		var pos := Vector2(n.global_position.x * inv, -n.global_position.z * inv)
		var key := Vector2i(int(floor(pos.x / cell)), int(floor(pos.y / cell)))
		var entry := {
			"node": n,
			"pos": pos,
			"r": radius_for_type(tid),
			"id": n.get_instance_id(),
			"building": BuildingVisual.is_building(tid),
		}
		if not _buckets.has(key):
			_buckets[key] = [entry]
		else:
			(_buckets[key] as Array).append(entry)


## 落点是否足够空（与可见邻居不重叠）。min_sep：中心距下限。
func is_slot_free(
	pos_wc3: Vector2,
	self_unit: Node,
	min_sep_wc3: float = 48.0
) -> bool:
	var neighbors := neighbors_of(self_unit, pos_wc3, maxf(min_sep_wc3 * 3.0, 128.0), false)
	var need := maxf(min_sep_wc3, 32.0)
	for n in neighbors:
		var other: Vector2 = n.get("pos", Vector2.ZERO)
		var orad := float(n.get("r", 16.0))
		# 中心距须 ≥ min_sep，并再留半个对方半径余量
		if pos_wc3.distance_to(other) < need + orad * 0.5:
			return false
	return true
