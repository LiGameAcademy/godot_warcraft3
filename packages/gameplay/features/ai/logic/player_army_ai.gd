extends Node

## 人族电脑军队调度：集结 / 进攻 / 回防 / 撤退，以及英雄拾取与阈值用药。
## 拾取：集结/撤退可绕路（480）；进攻/回防仅贴身（ItemPickupController.PICKUP_RANGE）。

enum State { ASSEMBLE, ATTACK, DEFEND, RETREAT }

const PICKUP_SCAN_RADIUS_WC3 := 480.0
const HEAL_HP_RATIO := 0.5
const MANA_MP_RATIO := 0.3

var state := State.ASSEMBLE
var router: CommandRouter
var unit_host: Node
## 由会话提供可观察敌人；调度器不自行读取隐蔽敌情。
var observe_enemies: Callable
## 地面道具宿主；空则跳过拾取决策。
var item_service: ItemService
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
	_consider_use()
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
		_consider_pickup(true)
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
		# 拾取中的英雄不打断；进攻/回防优先级高于拾取。
		if _is_picking_up(unit):
			continue
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
	# 集结/撤退可绕路捡；进攻/回防只捡贴身（PICKUP_RANGE 内，不绕路）。
	var allow_detour := state == State.ASSEMBLE or state == State.RETREAT
	_consider_pickup(allow_detour)
	last_status = "%s：%d 单位" % [State.keys()[state], army.size()]


func _consider_use() -> void:
	if router == null or not is_instance_valid(unit_host):
		return
	for unit in router.filter_controllable(unit_host.get_children()):
		if not _is_hero(unit) or not CombatQuery.is_alive_in_world(unit):
			continue
		var inv := Inventory.of(unit)
		if inv == null:
			inv = Inventory.ensure_on(unit)
		if inv == null:
			continue
		var slot := _needed_use_slot(unit, inv)
		if slot < 0:
			continue
		inv.try_use(slot)


func _consider_pickup(allow_detour: bool = true) -> void:
	if router == null or item_service == null or not is_instance_valid(unit_host):
		return
	var max_r := PICKUP_SCAN_RADIUS_WC3 if allow_detour else ItemPickupController.PICKUP_RANGE
	for unit in router.filter_controllable(unit_host.get_children()):
		if not _is_hero(unit) or not CombatQuery.is_alive_in_world(unit):
			continue
		if _is_picking_up(unit):
			continue
		var inv := Inventory.ensure_on(unit)
		if inv == null or inv.is_full():
			continue
		var xy := Wc3Coords.godot_to_wc3_xy(unit.global_position)
		var best: GroundItem = null
		var best_d2 := INF
		for ground in item_service.get_ground_items_in_radius(xy, max_r):
			if ground.claimed or ground.item == null:
				continue
			if not ItemCatalog.is_ai_pickup_worth(ground.item.type_id):
				continue
			var d2 := xy.distance_squared_to(Wc3Coords.godot_to_wc3_xy(ground.global_position))
			if d2 < best_d2:
				best = ground
				best_d2 = d2
		if best == null:
			continue
		if router.issue_pickup([unit], best, UnitOrder.Source.PLAYER_AI) > 0:
			_sent.erase(unit.get_instance_id())


func _needed_use_slot(unit: Node3D, inv: Inventory) -> int:
	var need_heal := false
	var need_mana := false
	var max_hp := UnitLife.get_max_life(unit)
	if max_hp > 0.0 and UnitLife.get_life(unit) / max_hp < HEAL_HP_RATIO:
		need_heal = true
	var max_mp := UnitMana.get_max_mana(unit)
	if max_mp > 0 and float(UnitMana.get_mana(unit)) / float(max_mp) < MANA_MP_RATIO:
		need_mana = true
	if not need_heal and not need_mana:
		return -1
	for i in range(Inventory.CAPACITY):
		var item := inv.item_at(i)
		if item == null:
			continue
		var ab := ItemCatalog.effect(item.type_id)
		if ab == null:
			continue
		if need_heal and ab.code_id == "AIhe":
			return i
		if need_mana and ab.code_id == "AIma":
			return i
	return -1


func _is_hero(unit: Node3D) -> bool:
	return TechPresence.is_hero_id(CombatQuery.type_id_of(unit))


func _is_picking_up(unit: Node) -> bool:
	var controller := unit.get_node_or_null("ItemPickupController") as ItemPickupController
	return controller != null and controller.is_processing() and is_instance_valid(controller.target)
