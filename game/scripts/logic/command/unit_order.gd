class_name UnitOrder
extends RefCounted

## 单位命令意图（命令层）。Present / Navigator 只消费结果，不读 InputEvent。

enum Kind {
	NONE = 0,
	MOVE = 1,
	STOP = 2,
	HARVEST_GOLD = 10,
	HARVEST_LUMBER = 11,
	RETURN_GOODS = 12,
	BUILD = 20,
	TRAIN = 30,
	RESEARCH = 40,
	ABILITY = 50,
}

enum Source {
	UNKNOWN = 0,
	SMART_RMB = 1, ## 右键智能命令
	PANEL = 2, ## 行动面板按钮
	HOTKEY = 3,
	TARGETING = 4, ## 点选移动模式后的落点
}

var kind: int = Kind.NONE
var goal_wc3: Vector2 = Vector2.INF
var source: int = Source.UNKNOWN
## 目标单位 instance_id（金矿等）；0 = 无
var target_id: int = 0
## 建筑 id（仅 BUILD Order；其他 Kind 留空）。F2-3 引入。
var building_id: String = ""


static func move(goal: Vector2, src: int = Source.UNKNOWN) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.MOVE
	o.goal_wc3 = goal
	o.source = src
	return o


static func stop(src: int = Source.UNKNOWN) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.STOP
	o.source = src
	return o


static func harvest_gold(mine: Node, src: int = Source.UNKNOWN) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.HARVEST_GOLD
	o.source = src
	if mine != null and is_instance_valid(mine):
		o.target_id = mine.get_instance_id()
	return o


## 伐木：target_id 复用为 doodad creationNumber（非 Node instance_id）。
static func harvest_lumber(creation_number: int, src: int = Source.UNKNOWN) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.HARVEST_LUMBER
	o.source = src
	o.target_id = creation_number
	return o


static func return_goods(src: int = Source.UNKNOWN) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.RETURN_GOODS
	o.source = src
	return o


## 建造 Order。building_id + 工地 wc3_xy；具体逻辑在 BuildController。
static func build(p_building_id: String, site_wc3: Vector2, src: int = Source.PANEL) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.BUILD
	o.source = src
	o.building_id = p_building_id
	o.goal_wc3 = site_wc3
	return o


func kind_name() -> String:
	match kind:
		Kind.MOVE:
			return "Move"
		Kind.STOP:
			return "Stop"
		Kind.HARVEST_GOLD:
			return "HarvestGold"
		Kind.HARVEST_LUMBER:
			return "HarvestLumber"
		Kind.RETURN_GOODS:
			return "ReturnGoods"
		Kind.BUILD:
			return "Build"
		Kind.TRAIN:
			return "Train"
		Kind.RESEARCH:
			return "Research"
		Kind.ABILITY:
			return "Ability"
		_:
			return "None"
