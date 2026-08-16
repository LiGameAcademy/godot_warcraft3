class_name TrainSpawn
extends RefCounted

## 训练完工出生点（对齐 WC3 观感的竖切近似）：
## 1) 脚印四角；有集结 → 离集结最近角；无集结 → 默认左下（SW）
## 2) 仍在该角创建；若与单位重叠 / 格不可走 → 以**建筑中心**为圆心向外挤到最近空位
##    （不换角重试；挤位搜索中心是建筑而非出生角）

## 角相对中心的顺序：NE(右上)、SW(左下)、NW(左上)、SE(右下)
const CORNER_NE := 0
const CORNER_SW := 1
const CORNER_NW := 2
const CORNER_SE := 3
## 无集结时的默认出生角（原作观感：建筑左下）
const DEFAULT_EXIT_CORNER := CORNER_SW

## 挤位最大半径（pathing 格）
const DISPLACE_MAX_CELLS := 16


## 四角世界坐标（略出脚印外缘半格，避免刷进建筑 pathTex）。
static func corner_positions_wc3(site_wc3: Vector2, building_type_id: String) -> Array[Vector2]:
	var fp := BuildingCatalog.get_footprint(building_type_id)
	var cells_x := maxi(fp.x, 1)
	var cells_y := maxi(fp.y, 1)
	var hx := float(cells_x) * 0.5 * Wc3Coords.PATHING_CELL
	var hy := float(cells_y) * 0.5 * Wc3Coords.PATHING_CELL
	var m := Wc3Coords.PATHING_CELL * 0.5
	var out: Array[Vector2] = []
	out.append(site_wc3 + Vector2(+hx + m, +hy + m)) # NE 右上
	out.append(site_wc3 + Vector2(-hx - m, -hy - m)) # SW 左下
	out.append(site_wc3 + Vector2(-hx - m, +hy + m)) # NW 左上
	out.append(site_wc3 + Vector2(+hx + m, -hy - m)) # SE 右下
	return out


## 选出出生角：集结最近角；无集结默认左下。
static func pick_exit_xy(
	site_wc3: Vector2,
	building_type_id: String,
	rally_wc3: Vector2 = Vector2.INF
) -> Vector2:
	var corners := corner_positions_wc3(site_wc3, building_type_id)
	if corners.is_empty():
		return site_wc3
	if rally_wc3 == Vector2.INF:
		return corners[DEFAULT_EXIT_CORNER]
	var best := corners[DEFAULT_EXIT_CORNER]
	var best_d2 := rally_wc3.distance_squared_to(best)
	for i in range(corners.size()):
		var d2 := rally_wc3.distance_squared_to(corners[i])
		if d2 < best_d2:
			best_d2 = d2
			best = corners[i]
	return best


## 建筑中心 + 集结目标 → 出生角（供 Director 一次算完）。
static func exit_xy_for_building(building: Node3D, site_wc3: Vector2) -> Vector2:
	var tid := ""
	if building != null and is_instance_valid(building):
		tid = str(building.get_meta("unit_data", {}).get("typeId", ""))
	var rally := Vector2.INF
	if BuildingRally.has_rally(building):
		rally = BuildingRally.goal_wc3(building)
	return pick_exit_xy(site_wc3, tid, rally)


## 若 preferred 可走且不与邻居重叠则保留；否则以 building_center 为圆心螺旋找最近空位。
static func resolve_with_displace(
	preferred_wc3: Vector2,
	building_center_wc3: Vector2,
	unit: Node3D,
	unit_type_id: String,
	path_query: PathQuery,
	crowd: UnitCrowdQuery
) -> Vector2:
	var self_r := 16.0
	if crowd != null:
		self_r = crowd.radius_for_type(unit_type_id)
	var min_sep := maxf(self_r * 2.0, 40.0)
	if _slot_ok(preferred_wc3, unit, min_sep, path_query, crowd):
		return preferred_wc3
	if path_query == null or not path_query.is_ready() or path_query.pathing == null:
		return preferred_wc3
	var pathing: Wc3PathingMap = path_query.pathing
	var c0 := pathing.world_to_cell(building_center_wc3.x, building_center_wc3.y)
	var best := Vector2.INF
	var best_d2 := INF
	for r in range(0, DISPLACE_MAX_CELLS + 1):
		var found_on_ring := false
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cx := c0.x + dx
				var cy := c0.y + dy
				if not path_query.can_walk_cell_clear(cx, cy, 0):
					continue
				var center := pathing.cell_center_wc3(cx, cy)
				if not _slot_ok(center, unit, min_sep, path_query, crowd):
					continue
				# 同环内：优先靠近「原本想出的角」
				var d2 := preferred_wc3.distance_squared_to(center)
				if d2 < best_d2:
					best_d2 = d2
					best = center
					found_on_ring = true
		if found_on_ring:
			return best
	return preferred_wc3


static func _slot_ok(
	pos_wc3: Vector2,
	unit: Node3D,
	min_sep: float,
	path_query: PathQuery,
	crowd: UnitCrowdQuery
) -> bool:
	if path_query != null and path_query.is_ready():
		var c := path_query.pathing.world_to_cell(pos_wc3.x, pos_wc3.y)
		if not path_query.can_walk_cell_clear(c.x, c.y, 0):
			return false
	if crowd != null and crowd.is_ready():
		if not crowd.is_slot_free(pos_wc3, unit, min_sep):
			return false
	return true
