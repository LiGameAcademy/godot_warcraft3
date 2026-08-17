class_name SmartTarget
extends RefCounted
## 右键智能命令的「交互目标」：Director 只负责识别；Router 按单位能力匹配具体 Order。
## 扩展攻击/修理等时加 Kind，不必改输入层分支结构。

enum Kind {
	GROUND = 0,
	GOLD_MINE = 1,
	TREE = 2,
	DROPOFF = 3,
	## 未完工建筑：农民可 join 建造
	BUILD_SITE = 4,
	## 敌对 / 可攻击单位
	ENEMY_UNIT = 5,
}


var kind: int = Kind.GROUND
## 金矿 / 交货建筑（树可无 Node）
var node: Node3D = null
## 树木 creationNumber；-1 = 无
var tree_cn: int = -1
## 不能做特殊动作时的落点（及地面命令中心）
var goal_wc3: Vector2 = Vector2.INF


static func ground(goal: Vector2) -> SmartTarget:
	var t := SmartTarget.new()
	t.kind = Kind.GROUND
	t.goal_wc3 = goal
	return t


static func gold_mine(mine: Node3D, goal: Vector2) -> SmartTarget:
	var t := SmartTarget.new()
	t.kind = Kind.GOLD_MINE
	t.node = mine
	t.goal_wc3 = goal
	return t


static func tree(creation_number: int, goal: Vector2) -> SmartTarget:
	var t := SmartTarget.new()
	t.kind = Kind.TREE
	t.tree_cn = creation_number
	t.goal_wc3 = goal
	return t


static func dropoff(building: Node3D, goal: Vector2) -> SmartTarget:
	var t := SmartTarget.new()
	t.kind = Kind.DROPOFF
	t.node = building
	t.goal_wc3 = goal
	return t


static func build_site(building: Node3D, goal: Vector2) -> SmartTarget:
	var t := SmartTarget.new()
	t.kind = Kind.BUILD_SITE
	t.node = building
	t.goal_wc3 = goal
	return t


static func enemy_unit(unit: Node3D, goal: Vector2) -> SmartTarget:
	var t := SmartTarget.new()
	t.kind = Kind.ENEMY_UNIT
	t.node = unit
	t.goal_wc3 = goal
	return t


func kind_name() -> String:
	match kind:
		Kind.GROUND:
			return "Ground"
		Kind.GOLD_MINE:
			return "GoldMine"
		Kind.TREE:
			return "Tree"
		Kind.DROPOFF:
			return "Dropoff"
		Kind.BUILD_SITE:
			return "BuildSite"
		Kind.ENEMY_UNIT:
			return "EnemyUnit"
		_:
			return "Unknown"
