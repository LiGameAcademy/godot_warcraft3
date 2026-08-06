class_name UnitOrder
extends RefCounted

## 单位命令意图（命令层）。Present / Navigator 只消费结果，不读 InputEvent。

enum Kind {
	NONE = 0,
	MOVE = 1,
	STOP = 2,
	## 以下为竖切预留，F0 不派发
	HARVEST_GOLD = 10,
	HARVEST_LUMBER = 11,
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
