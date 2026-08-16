class_name BuildingRally
extends RefCounted

## 可训练建筑的集结点（挂 Node3D meta）。
## 训练完工：单位在脚印四角出生（离集结最近；默认左下），再按集结点 Move / Harvest。
## 未设置集结 → 留在出生角（挤位后）。

const META_GOAL := "rally_wc3"
const META_KIND := "rally_kind"
const META_MINE_ID := "rally_mine_id"
const META_TREE_CN := "rally_tree_cn"

const KIND_NONE := ""
const KIND_GROUND := "ground"
const KIND_GOLD_MINE := "gold_mine"
const KIND_TREE := "tree"


static func clear(building: Node3D) -> void:
	if building == null or not is_instance_valid(building):
		return
	building.remove_meta(META_GOAL)
	building.remove_meta(META_KIND)
	building.remove_meta(META_MINE_ID)
	building.remove_meta(META_TREE_CN)


static func set_ground(building: Node3D, goal_wc3: Vector2) -> void:
	if building == null or not is_instance_valid(building) or goal_wc3 == Vector2.INF:
		return
	building.set_meta(META_KIND, KIND_GROUND)
	building.set_meta(META_GOAL, goal_wc3)
	building.remove_meta(META_MINE_ID)
	building.remove_meta(META_TREE_CN)


static func set_gold_mine(building: Node3D, mine: Node3D, goal_wc3: Vector2 = Vector2.INF) -> void:
	if building == null or not is_instance_valid(building):
		return
	if mine == null or not is_instance_valid(mine):
		return
	var g := goal_wc3
	if g == Vector2.INF:
		var d: Dictionary = mine.get_meta("unit_data", {})
		var pos: Dictionary = d.get("position", {})
		g = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	building.set_meta(META_KIND, KIND_GOLD_MINE)
	building.set_meta(META_GOAL, g)
	building.set_meta(META_MINE_ID, mine.get_instance_id())
	building.remove_meta(META_TREE_CN)


static func set_tree(building: Node3D, tree_cn: int, goal_wc3: Vector2) -> void:
	if building == null or not is_instance_valid(building) or tree_cn < 0:
		return
	building.set_meta(META_KIND, KIND_TREE)
	building.set_meta(META_GOAL, goal_wc3)
	building.set_meta(META_TREE_CN, tree_cn)
	building.remove_meta(META_MINE_ID)


static func has_rally(building: Node3D) -> bool:
	return kind(building) != KIND_NONE and goal_wc3(building) != Vector2.INF


static func kind(building: Node3D) -> String:
	if building == null or not is_instance_valid(building):
		return KIND_NONE
	return str(building.get_meta(META_KIND, KIND_NONE))


static func goal_wc3(building: Node3D) -> Vector2:
	if building == null or not is_instance_valid(building):
		return Vector2.INF
	if not building.has_meta(META_GOAL):
		return Vector2.INF
	var g: Variant = building.get_meta(META_GOAL)
	return g as Vector2 if g is Vector2 else Vector2.INF


static func mine_node(building: Node3D) -> Node3D:
	if building == null or not is_instance_valid(building):
		return null
	if not building.has_meta(META_MINE_ID):
		return null
	var id := int(building.get_meta(META_MINE_ID, 0))
	var obj := instance_from_id(id)
	return obj as Node3D if obj is Node3D and is_instance_valid(obj) else null


static func tree_cn(building: Node3D) -> int:
	if building == null or not is_instance_valid(building):
		return -1
	return int(building.get_meta(META_TREE_CN, -1))


## 该建筑是否可设集结点（有 Trains 列表）。
## 以 Trains 为准；勿仅靠 BuildingCatalog.is_building（Def 未就绪时 htow 会误判 false）。
## 建造中也可设（与命令卡保留集结点一致）。
static func can_set_rally(building: Node3D) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	var tid := str(building.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	if tid.is_empty():
		return false
	return not CommandButtonCatalog.get_shared().get_trains(tid).is_empty()
