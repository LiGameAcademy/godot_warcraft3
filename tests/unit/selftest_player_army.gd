extends Node

const ArmyScript = preload("res://game/scripts/logic/ai/player_army_ai.gd")
var failures := 0
var checks := 0
var enemies: Array[Node3D] = []

class RecordingRouter extends CommandRouter:
	var batches: Array = []
	func issue_attack_move(units: Array, goal: Vector2, source: int = UnitOrder.Source.UNKNOWN) -> Dictionary:
		batches.append({"attack": true, "units": units.duplicate(), "goal": goal, "source": source})
		return {"moved": units.size()}
	func issue_move_to_wc3(units: Array, goal: Vector2, source: int = UnitOrder.Source.UNKNOWN) -> Dictionary:
		batches.append({"attack": false, "units": units.duplicate(), "goal": goal, "source": source})
		return {"moved": units.size()}

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PLAYER ARMY: " + label)

func unit(host: Node, type_id: String, owner_id: int, xy: Vector2) -> Node3D:
	var node := Node3D.new()
	node.set_meta("unit_data", {"typeId": type_id, "owner": owner_id})
	node.set_meta("life", 100.0)
	node.position = Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, 0)
	host.add_child(node)
	return node

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var host := Node3D.new()
	add_child(host)
	var session := GameSession.new()
	session.ensure_stock(1)
	var commands := RecordingRouter.new()
	commands.configure(null, null, Callable(), Callable(), Callable(), session, Callable(), Callable(), Callable(), 1)
	var army := ArmyScript.new()
	army.router = commands
	army.unit_host = host
	army.observe_enemies = func() -> Array[Node3D]: return enemies
	add_child(army)
	unit(host, "htow", 1, Vector2.ZERO)
	var worker := unit(host, "hpea", 1, Vector2.ZERO)
	var troops: Array[Node3D] = []
	for i in range(2):
		troops.append(unit(host, "hfoo", 1, Vector2.ZERO))
	enemies.append(unit(host, "htow", 0, Vector2(8000, 0)))
	army.decide()
	check(army.state == ArmyScript.State.ASSEMBLE and not commands.batches[-1].attack, "兵力不足时集结")
	check(worker not in commands.batches[-1].units, "经营工人不被拉入军队")
	for i in range(2):
		troops.append(unit(host, "hfoo", 1, Vector2.ZERO))
	army.decide()
	check(army.state == ArmyScript.State.ATTACK and commands.batches[-1].attack, "达到门槛发起攻击移动")
	check(commands.batches[-1].source == UnitOrder.Source.PLAYER_AI, "宏观订单标注电脑来源")
	var batch_count := commands.batches.size()
	army.decide()
	check(commands.batches.size() == batch_count, "目标未变不重置攻击订单")
	var reinforcement := unit(host, "hfoo", 1, Vector2.ZERO)
	army.decide()
	check(commands.batches[-1].units == [reinforcement], "增援单独加入进攻不打断旧部队")
	var intruder := unit(host, "hfoo", 0, Vector2(500, 0))
	enemies.append(intruder)
	army.decide()
	check(army.state == ArmyScript.State.DEFEND and commands.batches[-1].goal == Vector2(500, 0), "基地附近敌军触发回防")
	enemies.erase(intruder)
	intruder.free()
	army.decide()
	check(army.state == ArmyScript.State.ATTACK, "威胁消失后恢复进攻")
	for troop in troops:
		UnitLife.set_life(troop, 0)
	army.decide()
	check(army.state == ArmyScript.State.RETREAT and not commands.batches[-1].attack, "重损后撤退重组")
	enemies.clear()
	army.decide()
	check(army.state == ArmyScript.State.ASSEMBLE, "观察接口无目标时停止追逐旧目标")
	print("selftest_player_army: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
