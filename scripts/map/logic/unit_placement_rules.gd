class_name UnitPlacementRules
extends RefCounted
## 单位放置合法性：建筑脚印 vs 寻路面；单位间圆形碰撞（纯数学）。


## 碰撞半径（WC3）：UnitBalance.collision → selSize/2 → pathTex 半宽 → 默认半格。
static func collision_radius_wc3(info: Dictionary) -> float:
	var col: float = float(info.get("collision", 0.0))
	if col > 0.0:
		return col
	var diam := Wc3IdCatalog.selection_diameter_wc3(info)
	return maxf(diam * 0.5, Wc3Coords.PATHING_CELL * 0.5)


static func footprint_cells(info: Dictionary) -> Vector2i:
	var cells: Vector2i = Wc3IdCatalog.parse_path_tex_cells(str(info.get("path_tex", "")))
	if cells == Vector2i.ZERO:
		if bool(info.get("is_building", false)):
			return Vector2i(4, 4) # 默认 1 地形格
		return Vector2i(1, 1)
	return cells


## 是否可在 (wc3_x,wc3_y) 放置 type_id。ignore_cns 拖动自身时排除。
static func can_place(
	wc3_x: float,
	wc3_y: float,
	type_id: String,
	catalog: Wc3IdCatalog,
	pathing: Wc3PathingMap,
	unit_entries: Array,
	ignore_cn: int = -1,
	ignore_cns: PackedInt32Array = PackedInt32Array()
) -> bool:
	var info: Dictionary = {}
	if catalog != null:
		info = catalog.lookup(type_id)
	var is_bldg: bool = bool(info.get("is_building", false))
	if is_bldg and pathing != null and pathing.is_valid():
		var fp := footprint_cells(info)
		if not pathing.can_build_footprint(wc3_x, wc3_y, fp.x, fp.y):
			return false
	var r0 := collision_radius_wc3(info)
	for e in unit_entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var cn: int = int(d.get("creationNumber", -1))
		if cn == ignore_cn:
			continue
		if ignore_cns.has(cn):
			continue
		var pos: Dictionary = d.get("position", {})
		var ox := float(pos.get("x", 0.0))
		var oy := float(pos.get("y", 0.0))
		var other_id := str(d.get("typeId", ""))
		var other_info: Dictionary = catalog.lookup(other_id) if catalog != null else {}
		var r1 := collision_radius_wc3(other_info)
		var min_d: float = r0 + r1
		var dx: float = wc3_x - ox
		var dy: float = wc3_y - oy
		if dx * dx + dy * dy < min_d * min_d * 0.92:
			return false
	return true
