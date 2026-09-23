extends Node

## PlayerArmyAI 拾取：空位英雄发 PICKUP；满包/非白名单/已认领不发；进攻态不绕路。
const ArmyScript = preload("res://addons/rts_gameplay/features/ai/logic/player_army_ai.gd")
var failures := 0
var checks := 0
var enemies: Array[Node3D] = []


class RecordingRouter extends CommandRouter:
	var batches: Array = []
	var pickups: Array = []

	func issue_attack_move(units: Array, goal: Vector2, source: int = UnitOrder.Source.UNKNOWN) -> Dictionary:
		batches.append({"attack": true, "units": units.duplicate(), "goal": goal, "source": source})
		return {"moved": units.size()}

	func issue_move_to_wc3(units: Array, goal: Vector2, source: int = UnitOrder.Source.UNKNOWN) -> Dictionary:
		batches.append({"attack": false, "units": units.duplicate(), "goal": goal, "source": source})
		return {"moved": units.size()}

	func issue_pickup(selected: Array, ground: GroundItem, source: int) -> int:
		pickups.append({"units": selected.duplicate(), "ground": ground, "source": source})
		return 1 if not selected.is_empty() else 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ARMY PICKUP: " + label)


func unit(host: Node, type_id: String, owner_id: int, xy: Vector2) -> Node3D:
	var node := Node3D.new()
	node.set_meta("unit_data", {"typeId": type_id, "owner": owner_id})
	node.set_meta("life", 100.0)
	node.set_meta("max_life", 100.0)
	node.position = Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, 0)
	host.add_child(node)
	return node


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var host := Node3D.new()
	add_child(host)
	var ground_host := Node3D.new()
	add_child(ground_host)
	var session := GameSession.new()
	session.ensure_stock(1)
	var commands := RecordingRouter.new()
	commands.configure(null, null, Callable(), Callable(), Callable(), session, Callable(), Callable(), Callable(), 1)
	var service := ItemService.new()
	service.configure(ground_host, null, "")
	var army := ArmyScript.new()
	army.router = commands
	army.unit_host = host
	army.observe_enemies = func() -> Array[Node3D]: return enemies
	army.item_service = service
	add_child(army)

	unit(host, "htow", 1, Vector2.ZERO)
	var hero := unit(host, "Hamg", 1, Vector2.ZERO)
	Inventory.ensure_on(hero)
	# 兵力不足 → ASSEMBLE，应拾取
	var ground := service.spawn(ItemInstance.create("phea"), Vector2(200, 0))
	check(ground != null, "生成地面药水")
	army.decide()
	check(army.state == ArmyScript.State.ASSEMBLE, "兵力不足集结")
	check(commands.pickups.size() == 1, "集结时对白名单道具发拾取")
	check(commands.pickups[0].source == UnitOrder.Source.PLAYER_AI, "拾取来源为 PLAYER_AI")
	check(commands.pickups[0].ground == ground, "拾取目标正确")

	# 满包不拾取
	commands.pickups.clear()
	var full := unit(host, "Hpal", 1, Vector2(50, 0))
	var finv := Inventory.ensure_on(full)
	for _i in range(Inventory.CAPACITY):
		finv.insert(ItemInstance.create("rde1"))
	var near_full := service.spawn(ItemInstance.create("pman"), Vector2(80, 0))
	army.decide()
	var targeted_full := false
	for p in commands.pickups:
		if full in p.units:
			targeted_full = true
	check(not targeted_full and near_full != null, "满包英雄不发拾取")

	# 进攻态：远处道具不绕路（先清掉先前贴身残留）
	commands.pickups.clear()
	if near_full != null and is_instance_valid(near_full):
		near_full.claimed = true
	if ground != null and is_instance_valid(ground):
		ground.claimed = true
	for _i in range(3):
		unit(host, "hfoo", 1, Vector2.ZERO)
	enemies.append(unit(host, "htow", 0, Vector2(8000, 0)))
	var far := service.spawn(ItemInstance.create("phea"), Vector2(400, 0))
	army.decide()
	check(army.state == ArmyScript.State.ATTACK, "达到门槛进攻")
	var far_hit := false
	for p in commands.pickups:
		if p.ground == far:
			far_hit = true
	check(not far_hit and far != null, "进攻时不绕路拾取远处道具")

	# 进攻态：贴身白名单道具仍拾取（不绕路）
	commands.pickups.clear()
	var at_feet := service.spawn(ItemInstance.create("rde1"), Vector2(40, 0))
	army.decide()
	check(at_feet != null and commands.pickups.size() == 1, "进攻时贴身道具仍拾取")
	check(commands.pickups[0].ground == at_feet, "贴身拾取目标正确")

	# 已认领不拾取
	commands.pickups.clear()
	enemies.clear()
	army.state = ArmyScript.State.ASSEMBLE
	if at_feet != null and is_instance_valid(at_feet):
		at_feet.claimed = true
	ground.claimed = true
	army.decide()
	var claimed_hit := false
	for p in commands.pickups:
		if p.ground == ground:
			claimed_hit = true
	check(not claimed_hit, "已认领道具不重复发令")

	print("selftest_player_army_pickup: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
