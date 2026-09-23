class_name CommandRequest
extends RefCounted

## 尚未接受的命令意图（D2）。含请求玩家与单位列表；不读 InputEvent / HUD。
## 接受后转为 UnitOrder 入队；本类不推进跨帧行动。

enum ErrorCode {
	OK = 0,
	EMPTY_SELECTION = 1,
	NO_MOVERS = 2,
	INVALID_GOAL = 3,
	INVALID_TARGET = 4,
	REJECTED = 5,
	WRONG_PLAYER = 6,
	APPEND_UNSUPPORTED = 7,
}

var kind: int = UnitOrder.Kind.NONE
var source: int = UnitOrder.Source.UNKNOWN
## 请求玩家；-1 = 使用 Router 绑定玩家
var player_id: int = -1
var units: Array = []
var goal_wc3: Vector2 = Vector2.INF
## 对局内目标节点；跨存档勿依赖 instance_id
var target: Node = null
var queue_append: bool = false


static func move_to(
	p_units: Array,
	goal: Vector2,
	src: int = UnitOrder.Source.UNKNOWN,
	player: int = -1
) -> CommandRequest:
	var r := CommandRequest.new()
	r.kind = UnitOrder.Kind.MOVE
	r.units = p_units
	r.goal_wc3 = goal
	r.source = src
	r.player_id = player
	return r


static func stop_units(
	p_units: Array,
	src: int = UnitOrder.Source.UNKNOWN,
	player: int = -1
) -> CommandRequest:
	var r := CommandRequest.new()
	r.kind = UnitOrder.Kind.STOP
	r.units = p_units
	r.source = src
	r.player_id = player
	return r


static func attack_target(
	p_units: Array,
	p_target: Node,
	src: int = UnitOrder.Source.UNKNOWN,
	player: int = -1
) -> CommandRequest:
	var r := CommandRequest.new()
	r.kind = UnitOrder.Kind.ATTACK
	r.units = p_units
	r.target = p_target
	r.source = src
	r.player_id = player
	return r


static func attack_move_to(
	p_units: Array,
	goal: Vector2,
	src: int = UnitOrder.Source.UNKNOWN,
	player: int = -1
) -> CommandRequest:
	var r := CommandRequest.new()
	r.kind = UnitOrder.Kind.ATTACK_MOVE
	r.units = p_units
	r.goal_wc3 = goal
	r.source = src
	r.player_id = player
	return r
