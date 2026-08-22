class_name UnitOrder
extends RefCounted

## 单位命令意图（命令层）。Present / Navigator 只消费结果，不读 InputEvent。

## 命令类型
enum Kind {
	NONE = 0,				## 无命令
	MOVE = 1,				## 移动
	STOP = 2,				## 停止
	HOLD = 3,				## 待命
	HARVEST_GOLD = 10,		## 采集金矿
	HARVEST_LUMBER = 11,	## 伐木
	RETURN_GOODS = 12,		## 返回资源
	BUILD = 20,				## 建造
	TRAIN = 30,				## 训练
	RESEARCH = 40,			## 研究
	ABILITY = 50,			## 技能
	ATTACK = 60,			## 攻击
	ATTACK_MOVE = 61,		## 攻击移动
	PATROL = 62,			## 巡逻
}

## 命令来源
enum Source {
	UNKNOWN = 0,			## 未知
	SMART_RMB = 1, 			## 右键智能命令
	PANEL = 2, 				## 行动面板按钮
	HOTKEY = 3,				## 快捷键
	TARGETING = 4, 			## 点选移动模式后的落点
	UNIT_AI = 5,			## 单位微观 AI（警戒/反击；非 AI 玩家）
}

var kind: int = Kind.NONE						## 命令类型
var goal_wc3: Vector2 = Vector2.INF				## 目标位置
var source: int = Source.UNKNOWN				## 命令来源
## 目标单位 instance_id（金矿等）；0 = 无
var target_id: int = 0
## 建筑 id（仅 BUILD Order；其他 Kind 留空）。F2-3 引入。
var building_id: String = ""
## 技能 id（仅 ABILITY Order；四字符 SLK alias）。
var ability_id: String = ""

## 移动命令
static func move(goal: Vector2, src: int = Source.UNKNOWN) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.MOVE
	o.goal_wc3 = goal
	o.source = src
	return o

## 停止命令
static func stop(src: int = Source.UNKNOWN) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.STOP
	o.source = src
	return o

## 待命命令
static func hold(src: int = Source.UNKNOWN) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.HOLD
	o.source = src
	return o

## 攻击命令
static func attack(target: Node, src: int = Source.UNKNOWN) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.ATTACK
	o.source = src
	if target != null and is_instance_valid(target):
		o.target_id = target.get_instance_id()
	return o

## 攻击移动命令
static func attack_move(goal: Vector2, src: int = Source.UNKNOWN) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.ATTACK_MOVE
	o.goal_wc3 = goal
	o.source = src
	return o

## 巡逻命令
static func patrol(goal: Vector2, src: int = Source.UNKNOWN) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.PATROL
	o.goal_wc3 = goal
	o.source = src
	return o

## 采集金矿命令
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

## 返回资源命令
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

## 训练 Order。unit_id + 工地 wc3_xy（建筑门口）；具体逻辑在 TrainQueue。
static func train(p_unit_id: String, site_wc3: Vector2, src: int = Source.PANEL) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.TRAIN
	o.source = src
	o.building_id = p_unit_id ## 复用：训的是哪类单位
	o.goal_wc3 = site_wc3
	return o


## 技能 Order（点目标等）。ability_id = 四字符 SLK id（如 AHwe）。
static func ability(abil_id: String, goal: Vector2, src: int = Source.PANEL) -> UnitOrder:
	var o := UnitOrder.new()
	o.kind = Kind.ABILITY
	o.source = src
	o.ability_id = abil_id.strip_edges()
	o.goal_wc3 = goal
	return o

## 命令类型名称
func kind_name() -> String:
	match kind:
		Kind.MOVE:
			return "Move"
		Kind.STOP:
			return "Stop"
		Kind.HOLD:
			return "Hold"
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
		Kind.ATTACK:
			return "Attack"
		Kind.ATTACK_MOVE:
			return "AttackMove"
		Kind.PATROL:
			return "Patrol"
		_:
			return "None"
