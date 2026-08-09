class_name PlacementRules
extends RefCounted

## 建造选址规则（游戏侧；编辑器侧的 unit_placement_rules.gd 是 Document 上下文）。
## 校验：(building_id, wc3_xy) 是否可建。
##
## F2 当前规则：
## 1. pathing.can_build_footprint(x, y, cells_w, cells_h) 全部可建
## 2. footprint 解析失败时降级为 can_build_at（点 cell）
## 3. unit_entries 占位检查暂略（F2-3 简化；F2-4 ghost preview 时加）
##
## 距己方主城最小距离暂不强制（WC3 实际允许紧贴；F2-3 不做）。

## 距主城最小距离（WC3 单位；暂未启用，留常量给后续）。
const MIN_DIST_FROM_TOWN_HALL_WC3 := 256.0


## 是否可在 (wc3_x, wc3_y) 放置 building_id。
static func can_build_at(
	building_id: String,
	wc3_xy: Vector2,
	pathing: Wc3PathingMap,
	_unit_entries: Array = []
) -> bool:
	if not BuildingCatalog.is_building(building_id):
		return false
	if pathing == null or not pathing.is_valid():
		return false
	var fp: Vector2i = BuildingCatalog.get_footprint(building_id)
	if fp.x <= 0 or fp.y <= 0:
		return pathing.can_build_at(wc3_xy.x, wc3_xy.y)
	return pathing.can_build_footprint(wc3_xy.x, wc3_xy.y, fp.x, fp.y)


## footprint（pathing 格数）。失败时返回 (0, 0) 供 ghost 走"点"放置。
static func get_footprint(building_id: String) -> Vector2i:
	if not BuildingCatalog.is_building(building_id):
		return Vector2i.ZERO
	return BuildingCatalog.get_footprint(building_id)
