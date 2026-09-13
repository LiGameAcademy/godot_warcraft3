extends Node

enum State { ASSEMBLE, ATTACK, DEFEND, RETREAT }
var state := State.ASSEMBLE
var router: CommandRouter
var unit_host: Node
## 由会话提供可观察敌人；调度器不自行读取隐蔽敌情。
var observe_enemies: Callable
var launch_count := 4
var retreat_count := 1
var defense_radius := 1400.0
var _elapsed := 0.0
var _sent: Dictionary = {}
var last_status := "集结"

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 1.0:
		_elapsed = 0.0
		decide()

func decide() -> void:
	if router == null or not is_instance_valid(unit_host) or not observe_enemies.is_valid():
		return
	var army: Array[Node3D] = []
	var base: Node3D = null
	for unit in router.filter_controllable(unit_host.get_children()):
		var id := CombatQuery.type_id_of(unit)
		if id in ["htow", "hkee", "hcas"]:
			base = unit
		elif not BuildingCatalog.is_building(id) and not HarvestController.is_peasant(unit) and CombatQuery.has_weapon(unit):
			army.append(unit)
	if army.is_empty():
		_sent.clear()
		state = State.ASSEMBLE
		return
	var home := Wc3Coords.godot_to_wc3_xy(base.global_position if base != null else army[0].global_position)
	var threat: Node3D = null
	var target: Node3D = null
	var threat_distance := INF
	var target_distance := INF
	for enemy in observe_enemies.call():
		if not enemy is Node3D or not CombatQuery.is_alive_in_world(enemy) or not CombatQuery.is_hostile(army[0], enemy):
			continue
		var xy := Wc3Coords.godot_to_wc3_xy(enemy.global_position)
		var distance := home.distance_squared_to(xy)
		if CombatQuery.has_weapon(enemy) and distance < defense_radius * defense_radius and distance < threat_distance:
			threat = enemy
			threat_distance = distance
		if BuildingCatalog.is_building(CombatQuery.type_id_of(enemy)) and distance < target_distance:
			target = enemy
			target_distance = distance
	var goal := home + Vector2(320, 0)
	var aggressive := false
	if threat != null:
		state = State.DEFEND
		goal = Wc3Coords.godot_to_wc3_xy(threat.global_position)
		aggressive = true
	elif state == State.ATTACK and army.size() <= retreat_count:
		state = State.RETREAT
	elif target != null and (army.size() >= launch_count or state == State.ATTACK):
		state = State.ATTACK
		goal = Wc3Coords.godot_to_wc3_xy(target.global_position)
		aggressive = true
	else:
		state = State.ASSEMBLE
	var key := "%d:%d:%d" % [state, roundi(goal.x / 128.0), roundi(goal.y / 128.0)]
	var pending: Array[Node3D] = []
	var live: Dictionary = {}
	for unit in army:
		var id := unit.get_instance_id()
		live[id] = true
		if _sent.get(id, "") != key:
			pending.append(unit)
	for id in _sent.keys():
		if not live.has(id):
			_sent.erase(id)
	if not pending.is_empty():
		var result: Dictionary
		if aggressive:
			result = router.issue_attack_move(pending, goal, UnitOrder.Source.PLAYER_AI)
		else:
			result = router.issue_move_to_wc3(pending, goal, UnitOrder.Source.PLAYER_AI)
		if int(result.get("moved", 0)) == pending.size():
			for unit in pending:
				_sent[unit.get_instance_id()] = key
	last_status = "%s：%d 单位" % [State.keys()[state], army.size()]
