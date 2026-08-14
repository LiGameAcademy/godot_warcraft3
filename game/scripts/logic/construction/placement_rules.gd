class_name PlacementRules
extends RefCounted

## 建造选址规则（游戏侧）。
## 格网权威：寻路格（PATHING_CELL=32 = 调试栅格「小」；「中」128 = 4×4 寻路格）。
## 原作建造预览：footprint 内逐格绿/红，非整块变色；落点吸附到寻路格。

const MIN_DIST_FROM_TOWN_HALL_WC3 := 256.0


## 是否可在已吸附的 site 放置（全部 footprint 格可建）。
static func can_build_at(
	building_id: String,
	wc3_xy: Vector2,
	pathing: Wc3PathingMap,
	_unit_entries: Array = []
) -> bool:
	var sample := sample_footprint(building_id, wc3_xy, pathing)
	return bool(sample.get("all_ok", false))


## footprint 寻路格数。失败 → (0,0)。
static func get_footprint(building_id: String) -> Vector2i:
	if not BuildingCatalog.is_building(building_id):
		return Vector2i.ZERO
	return BuildingCatalog.get_footprint(building_id)


## 将光标世界点吸附为 footprint 中心（min 角落在寻路格边界上）。
static func snap_site_wc3(
	building_id: String,
	raw_wc3: Vector2,
	pathing: Wc3PathingMap
) -> Vector2:
	if pathing == null or not pathing.is_valid():
		return raw_wc3
	var fp := get_footprint(building_id)
	if fp.x <= 0 or fp.y <= 0:
		fp = Vector2i(1, 1)
	var cs := pathing.cell_size
	var half := Vector2(float(fp.x) * 0.5, float(fp.y) * 0.5)
	var min_c := pathing.world_to_cell(
		raw_wc3.x - half.x * cs,
		raw_wc3.y - half.y * cs
	)
	return Vector2(
		pathing.origin_wc3.x + (float(min_c.x) + half.x) * cs,
		pathing.origin_wc3.y + (float(min_c.y) + half.y) * cs
	)


## 采样 footprint 各寻路格可建性。
## 返回：
##   min_cell: Vector2i
##   size: Vector2i
##   ok: PackedByteArray（row-major，1=可建 0=不可建）
##   all_ok: bool
##   site_wc3: Vector2（与传入一致，调用方应先 snap）
static func sample_footprint(
	building_id: String,
	site_wc3: Vector2,
	pathing: Wc3PathingMap
) -> Dictionary:
	var empty := {
		"min_cell": Vector2i.ZERO,
		"size": Vector2i.ZERO,
		"ok": PackedByteArray(),
		"all_ok": false,
		"site_wc3": site_wc3,
	}
	if not BuildingCatalog.is_building(building_id):
		return empty
	if pathing == null or not pathing.is_valid():
		return empty
	var fp := get_footprint(building_id)
	if fp.x <= 0 or fp.y <= 0:
		fp = Vector2i(1, 1)
	var cs := pathing.cell_size
	var half := Vector2(float(fp.x) * 0.5, float(fp.y) * 0.5)
	var min_c := pathing.world_to_cell(
		site_wc3.x - half.x * cs,
		site_wc3.y - half.y * cs
	)
	var mask := PackedByteArray()
	mask.resize(fp.x * fp.y)
	var all_ok := true
	for dy in range(fp.y):
		for dx in range(fp.x):
			var ok := pathing.can_build_cell(min_c.x + dx, min_c.y + dy)
			mask[dy * fp.x + dx] = 1 if ok else 0
			if not ok:
				all_ok = false
	return {
		"min_cell": min_c,
		"size": fp,
		"ok": mask,
		"all_ok": all_ok,
		"site_wc3": site_wc3,
	}
