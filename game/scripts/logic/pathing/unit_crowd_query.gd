class_name UnitCrowdQuery
extends RefCounted
## 邻近单位查询：扫 MapUnitLayer 子节点，供 UnitNavigator soft 分离使用。
##
## Echo Isles 单位量级很小，全量扫描足够；日后可换成寻路格空间哈希。

## 默认查询半径（WC3）：约覆盖数个农民碰撞圈
const DEFAULT_RANGE_WC3 := 192.0

var _unit_layer: Node = null
var _catalog: Wc3IdCatalog = null
## typeId → 碰撞半径缓存
var _radius_cache: Dictionary = {}


func configure(unit_layer: Node, catalog: Wc3IdCatalog) -> void:
	_unit_layer = unit_layer
	_catalog = catalog
	_radius_cache.clear()


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
	var out: Array = []
	if _unit_layer == null:
		return out
	var range_sq := range_wc3 * range_wc3
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	for c in _unit_layer.get_children():
		if c == self_unit or not (c is Node3D):
			continue
		var n := c as Node3D
		# 离场单位（进矿 / 工地 / 训练中）不参与 soft 分离与网格占位
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
		if not include_buildings and BuildingVisual.is_building(tid):
			continue
		var pos := Vector2(n.global_position.x * inv, -n.global_position.z * inv)
		if self_pos_wc3.distance_squared_to(pos) > range_sq:
			continue
		out.append({"pos": pos, "r": radius_for_type(tid), "id": n.get_instance_id()})
	return out


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
