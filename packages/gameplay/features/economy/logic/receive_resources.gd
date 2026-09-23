class_name ReceiveResources
extends RefCounted

## 建筑「接收资源」能力（主城交金木；伐木场只收木）。
## 不挂 Node：按 typeId 判定 + 向 PlayerStock 入账。未完工建筑不能交货。

enum Kind {
	NONE = 0,
	GOLD = 1,
	LUMBER = 2,
	BOTH = 3,
}

const TYPE_TOWN_HALL := "htow"
const TYPE_KEEP := "hkee"
const TYPE_CASTLE := "hcas"
const TYPE_LUMBER_MILL := "hlum"


## 该建筑能接收哪些资源。
static func capability_for_type(type_id: String) -> int:
	match type_id.strip_edges():
		TYPE_TOWN_HALL, TYPE_KEEP, TYPE_CASTLE:
			return Kind.BOTH
		TYPE_LUMBER_MILL:
			return Kind.LUMBER
		_:
			return Kind.NONE


static func can_receive(building: Node, resource_mask: int) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	# 与 TechPresence 一致：半成品不提供能力（含伐木场收木）。
	if bool(building.get_meta("under_construction", false)):
		return false
	var tid := _type_id(building)
	var cap := capability_for_type(tid)
	if cap == Kind.NONE or resource_mask == Kind.NONE:
		return false
	return (cap & resource_mask) == resource_mask


static func accepts_gold(building: Node) -> bool:
	return can_receive(building, Kind.GOLD)


static func accepts_lumber(building: Node) -> bool:
	return can_receive(building, Kind.LUMBER)


## 在 unit_host 下找最近、同 owner、能接收指定资源的建筑。
static func find_nearest_dropoff(
	unit_host: Node,
	from_wc3: Vector2,
	owner_id: int,
	resource_mask: int
) -> Node3D:
	if unit_host == null:
		return null
	var best: Node3D = null
	var best_d2 := INF
	for c in unit_host.get_children():
		if not (c is Node3D) or not is_instance_valid(c):
			continue
		var node := c as Node3D
		if not can_receive(node, resource_mask):
			continue
		var d: Dictionary = node.get_meta("unit_data", {})
		if int(d.get("owner", -1)) != owner_id:
			continue
		var xy := Wc3Coords.godot_to_wc3_xy(node.global_position)
		var d2 := from_wc3.distance_squared_to(xy)
		if d2 < best_d2:
			best_d2 = d2
			best = node
	return best


## 向库存入账。返回实际入账的 {gold, lumber}。
## building 须具备对应 ReceiveResources 能力；stock 为玩家库存权威。
static func deposit(
	building: Node,
	stock: PlayerStock,
	gold_amount: int,
	lumber_amount: int
) -> Dictionary:
	var out := {"gold": 0, "lumber": 0}
	if stock == null or building == null or not is_instance_valid(building):
		return out
	var g := maxi(0, gold_amount)
	var l := maxi(0, lumber_amount)
	if g > 0 and accepts_gold(building):
		stock.add_gold(g)
		out["gold"] = g
	if l > 0 and accepts_lumber(building):
		stock.add_lumber(l)
		out["lumber"] = l
	return out


static func _type_id(node: Node) -> String:
	var d: Dictionary = node.get_meta("unit_data", {})
	return str(d.get("typeId", "")).strip_edges()
