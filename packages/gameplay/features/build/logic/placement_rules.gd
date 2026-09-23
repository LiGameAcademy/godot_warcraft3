class_name PlacementRules
extends RefCounted

## 建造选址规则（游戏侧）。
## 格网权威：寻路格（PATHING_CELL=32 = 调试栅格「小」；「中」128 = 4×4 寻路格）。
## 原作建造预览：footprint 内逐格绿/红，非整块变色；落点吸附到寻路格。
## 合法性：解释 UnitBalance.preventPlace / requirePlace + WPM/动态 pathTex 标志。

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
	var min_c := _footprint_min_cell(pathing, raw_wc3, half, cs)
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
	var min_c := _footprint_min_cell(pathing, site_wc3, half, cs)
	var mask := PackedByteArray()
	mask.resize(fp.x * fp.y)
	var all_ok := true
	for dy in range(fp.y):
		for dx in range(fp.x):
			var ok := cell_allows_building(building_id, pathing, min_c.x + dx, min_c.y + dy)
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


## 单格是否允许该建筑（preventPlace / requirePlace + pathing 标志）。
## 与路径-地面叠色同源：蓝=NO_BUILD、红=NO_WALK、品红=两者。
static func cell_allows_building(
	building_id: String,
	pathing: Wc3PathingMap,
	px: int,
	py: int
) -> bool:
	if pathing == null or not pathing.is_valid():
		return false
	var f: int = pathing.flag_at(px, py)
	var prevent := BuildingCatalog.get_prevent_place(building_id).strip_edges().to_lower()
	var require := BuildingCatalog.get_require_place(building_id).strip_edges().to_lower()
	# 缺省 / `_`：地面建筑按 unbuildable（与多数 UnitBalance 行一致）
	if prevent.is_empty() or prevent == "_":
		prevent = "unbuildable"
	if prevent.find("unbuildable") >= 0:
		if (f & Wc3PathingMap.FLAG_NO_BUILD) != 0:
			return false
	if prevent.find("unwalkable") >= 0:
		if (f & Wc3PathingMap.FLAG_NO_WALK) != 0:
			return false
	# 结构体始终禁止不可建格（叠层蓝/品红），避免 prevent 字段异常时漏检
	if (f & Wc3PathingMap.FLAG_NO_BUILD) != 0:
		return false
	if not require.is_empty() and require != "_":
		if require.find("blight") >= 0:
			if (f & Wc3PathingMap.FLAG_BLIGHT) == 0:
				return false
	return true


## 由中心点反推 footprint 左下角格；+eps 减轻「恰在格线」的 floor 漂移。
static func _footprint_min_cell(
	pathing: Wc3PathingMap,
	center_wc3: Vector2,
	half: Vector2,
	cs: float
) -> Vector2i:
	var lx: float = (center_wc3.x - pathing.origin_wc3.x) / cs - half.x
	var ly: float = (center_wc3.y - pathing.origin_wc3.y) / cs - half.y
	return Vector2i(int(floor(lx + 1e-4)), int(floor(ly + 1e-4)))
