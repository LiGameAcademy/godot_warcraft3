class_name BuildFootprintClearance
extends RefCounted

## 建造开工清场：把 footprint 内（含碰撞圆重叠）的可移动单位推到脚印外。
## 排除：施工中的工人、建筑、离场单位。目标点用螺旋找可走格。

const EDGE_MARGIN_CELLS := 0.5
const SPIRAL_MAX_CELLS := 20


## footprint 轴对齐盒（WC3 XY；左下角 + 尺寸）。
static func footprint_aabb_wc3(
	building_id: String,
	site_wc3: Vector2,
	pathing: Wc3PathingMap
) -> Rect2:
	var sample := PlacementRules.sample_footprint(building_id, site_wc3, pathing)
	var fp: Vector2i = sample.get("size", Vector2i.ZERO)
	if fp.x <= 0 or fp.y <= 0 or pathing == null or not pathing.is_valid():
		return Rect2()
	var min_c: Vector2i = sample.get("min_cell", Vector2i.ZERO)
	var cs := pathing.cell_size
	var min_xy := Vector2(
		pathing.origin_wc3.x + float(min_c.x) * cs,
		pathing.origin_wc3.y + float(min_c.y) * cs
	)
	return Rect2(min_xy, Vector2(float(fp.x) * cs, float(fp.y) * cs))


## 单位碰撞圆是否与 footprint（外扩 radius）相交。
static func overlaps_footprint(pos_wc3: Vector2, radius_wc3: float, aabb: Rect2) -> bool:
	if aabb.size.x <= 0.0 or aabb.size.y <= 0.0:
		return false
	var expanded := aabb.grow(maxf(radius_wc3, 0.0))
	return expanded.has_point(pos_wc3)


## 扫 unit_layer，返回需要让位的单位（不含 exclude）。
static func collect_blockers(
	unit_layer: Node,
	building_id: String,
	site_wc3: Vector2,
	pathing: Wc3PathingMap,
	crowd: UnitCrowdQuery,
	exclude: Array
) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if unit_layer == null or pathing == null or not pathing.is_valid():
		return out
	var aabb := footprint_aabb_wc3(building_id, site_wc3, pathing)
	if aabb.size.x <= 0.0:
		return out
	var exclude_ids: Dictionary = {}
	for e in exclude:
		if e != null and is_instance_valid(e):
			exclude_ids[e.get_instance_id()] = true
	for c in unit_layer.get_children():
		if not (c is Node3D):
			continue
		var n := c as Node3D
		if exclude_ids.has(n.get_instance_id()):
			continue
		if not WorldMembership.is_in_world(n):
			continue
		if not n.has_meta("unit_data"):
			continue
		var d: Dictionary = n.get_meta("unit_data", {})
		var tid := str(d.get("typeId", "")).strip_edges()
		if tid.is_empty() or tid.to_lower() == "sloc":
			continue
		if BuildingVisual.is_building(tid) or BuildingCatalog.is_building(tid):
			continue
		var pos := Wc3Coords.godot_to_wc3_xy(n.global_position)
		var radius := 16.0
		if crowd != null:
			radius = crowd.radius_for_type(tid)
		if not overlaps_footprint(pos, radius, aabb):
			continue
		out.append(n)
	return out


## 脚印外最近可走点：先沿「离工地中心方向」推到外沿，再螺旋找空位。
static func resolve_outside(
	unit: Node3D,
	unit_type_id: String,
	unit_pos_wc3: Vector2,
	site_wc3: Vector2,
	aabb: Rect2,
	path_query: PathQuery,
	crowd: UnitCrowdQuery
) -> Vector2:
	var radius := 16.0
	if crowd != null:
		radius = crowd.radius_for_type(unit_type_id)
	var preferred := _preferred_outside(unit_pos_wc3, site_wc3, aabb, radius)
	if _slot_ok_outside(preferred, unit, radius, aabb, path_query, crowd):
		return preferred
	if path_query == null or not path_query.is_ready() or path_query.pathing == null:
		return preferred
	var pathing: Wc3PathingMap = path_query.pathing
	var c0 := pathing.world_to_cell(preferred.x, preferred.y)
	var best := preferred
	var best_d2 := INF
	for r in range(0, SPIRAL_MAX_CELLS + 1):
		var found := false
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var center := pathing.cell_center_wc3(c0.x + dx, c0.y + dy)
				if not _slot_ok_outside(center, unit, radius, aabb, path_query, crowd):
					continue
				var d2 := unit_pos_wc3.distance_squared_to(center)
				if d2 < best_d2:
					best_d2 = d2
					best = center
					found = true
		if found:
			return best
	return preferred


static func _preferred_outside(
	unit_pos: Vector2,
	site_wc3: Vector2,
	aabb: Rect2,
	radius: float
) -> Vector2:
	var margin := EDGE_MARGIN_CELLS * Wc3Coords.PATHING_CELL + radius
	var expanded := aabb.grow(margin)
	if not expanded.has_point(unit_pos):
		return unit_pos
	var half := expanded.size * 0.5
	var center := expanded.get_center()
	var dir := unit_pos - site_wc3
	if dir.length_squared() < 1.0:
		dir = unit_pos - center
	if dir.length_squared() < 1.0:
		dir = Vector2(1.0, 0.0)
	dir = dir.normalized()
	var tx := half.x / maxf(absf(dir.x), 1e-4)
	var ty := half.y / maxf(absf(dir.y), 1e-4)
	return center + dir * minf(tx, ty)


static func _slot_ok_outside(
	pos_wc3: Vector2,
	unit: Node3D,
	radius: float,
	aabb: Rect2,
	path_query: PathQuery,
	crowd: UnitCrowdQuery
) -> bool:
	if overlaps_footprint(pos_wc3, radius, aabb):
		return false
	if path_query != null and path_query.is_ready():
		var c := path_query.pathing.world_to_cell(pos_wc3.x, pos_wc3.y)
		if not path_query.can_walk_cell_clear(c.x, c.y, 0):
			return false
	if crowd != null and crowd.is_ready():
		var min_sep := maxf(radius * 2.0, 40.0)
		if not crowd.is_slot_free(pos_wc3, unit, min_sep):
			return false
	return true
