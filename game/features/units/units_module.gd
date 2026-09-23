class_name UnitsModule
extends Node

signal form_changed(unit: Node3D)
var presenter := UnitModelPresenter.new()
var forms: UnitFormService

## 对局内单位出生与战斗组件装配。
## 由总管注入地图与服务；本模块不依赖 GameDirector 类型。
## 生产模块通过 spawn_trained / ensure_hero 两个 Callable 接入。

var _map_root: MapLoader
var _heightfield: Wc3Heightfield
var _path_query: PathQuery
var _crowd_query: UnitCrowdQuery
var _command_router: CommandRouter
var _health_bar_manager: HealthBarManager
## TeamRegistry 挂载宿主（通常为对局根下的总管节点）。
var _registry_host: Node
var _ensure_navigator: Callable
var _ensure_attack_controller: Callable
var _unit_host: Callable
var _refresh_pathing: Callable
var _on_inventory_changed: Callable
var _ensure_hero_passives: Callable
var _ensure_caster: Callable
var _add_food_used: Callable
var _next_runtime_cn: int = 900000
## D5：对局实体注册表（可选注入）。
var _entity_registry: EntityRegistry


func configure(deps: Dictionary) -> void:
	_map_root = deps.get("map_root") as MapLoader
	presenter.configure(_map_root)
	_heightfield = deps.get("heightfield") as Wc3Heightfield
	_path_query = deps.get("path_query") as PathQuery
	_crowd_query = deps.get("crowd_query") as UnitCrowdQuery
	_command_router = deps.get("command_router") as CommandRouter
	_health_bar_manager = deps.get("health_bar_manager") as HealthBarManager
	_registry_host = deps.get("registry_host") as Node
	_entity_registry = deps.get("entity_registry") as EntityRegistry
	_ensure_navigator = deps.get("ensure_navigator", Callable()) as Callable
	_ensure_attack_controller = deps.get("ensure_attack_controller", Callable()) as Callable
	_unit_host = deps.get("unit_host", Callable()) as Callable
	_refresh_pathing = deps.get("refresh_pathing", Callable()) as Callable
	_on_inventory_changed = deps.get("on_inventory_changed", Callable()) as Callable
	_ensure_hero_passives = deps.get("ensure_hero_passives", Callable()) as Callable
	_ensure_caster = deps.get("ensure_caster", Callable()) as Callable
	_add_food_used = deps.get("add_food_used", Callable()) as Callable
	if deps.has("next_runtime_cn"):
		_next_runtime_cn = int(deps["next_runtime_cn"])
	if not is_instance_valid(forms):
		forms = UnitFormService.new()
		forms.name = "UnitForms"
		add_child(forms)
		forms.changed.connect(_on_form_changed)
	forms.configure(self, _map_root, deps.get("navigation") as NavigationModule,
		deps.get("session") as GameSession, _command_router, presenter, _ensure_attack_controller)


func shutdown() -> void:
	if is_instance_valid(forms):
		forms.shutdown()
	presenter.configure(null)
	_map_root = null
	_heightfield = null
	_path_query = null
	_crowd_query = null
	_command_router = null
	_health_bar_manager = null
	_registry_host = null
	_entity_registry = null
	_ensure_navigator = Callable()
	_ensure_attack_controller = Callable()
	_unit_host = Callable()
	_refresh_pathing = Callable()
	_on_inventory_changed = Callable()
	_ensure_hero_passives = Callable()
	_ensure_caster = Callable()
	_add_food_used = Callable()


func _exit_tree() -> void:
	shutdown()


func alloc_creation_number() -> int:
	var cn := _next_runtime_cn
	_next_runtime_cn += 1
	return cn


func entity_registry() -> EntityRegistry:
	return _entity_registry


func _register_entity(node: Node, creation_number: int) -> void:
	if _entity_registry == null or node == null:
		return
	_entity_registry.register_unit(EntityId.from_creation_number(creation_number), node)


## 训练完工刷单位：脚印四角 → 重叠挤位 → AI/英雄装配 → 集结。
func spawn_trained(
	unit_id: String, site_wc3: Vector2, owner_id: int, from_building: Node3D = null
) -> Node3D:
	if _map_root == null or _heightfield == null:
		return null
	var corner_xy := TrainSpawn.exit_xy_for_building(from_building, site_wc3)
	var cn := alloc_creation_number()
	var entry := {
		"typeId": unit_id,
		"position": {"x": corner_xy.x, "y": corner_xy.y, "z": 0.0},
		"angle": MeleeBootstrap.UNIT_FACING_RAD,
		"scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"owner": owner_id,
		"flags": 2,
		"creationNumber": cn,
		"variation": 0,
	}
	var node := _map_root.add_unit_instance(entry, _heightfield.as_dict_view())
	if node == null:
		return null
	_register_entity(node, cn)
	UnitLife.ensure(node)
	var final_xy := TrainSpawn.resolve_with_displace(
		corner_xy, site_wc3, node, unit_id, _path_query, _crowd_query
	)
	if final_xy != corner_xy:
		teleport_wc3(node, final_xy)
	ensure_combat_ai(node)
	ensure_hero(node)
	if _refresh_pathing.is_valid():
		_refresh_pathing.call()
	if _health_bar_manager != null:
		_health_bar_manager.resync()
	_dispatch_trained_rally(from_building, node)
	return node


## 建造完工 / 半成品入图用的 unit entry（MapUnitLayer 字段）。
func build_building_entry(
	building_id: String, site_wc3: Vector2, player_owner: int, creation_number: int = -1
) -> Dictionary:
	var cn := creation_number if creation_number >= 0 else alloc_creation_number()
	return {
		"typeId": building_id,
		"position": {"x": site_wc3.x, "y": site_wc3.y},
		"angle": MeleeBootstrap.UNIT_FACING_RAD,
		"owner": player_owner,
		"creationNumber": cn,
		"variation": 0,
		"isBuilding": true,
	}


## 通用刷兵 entry：开发刷兵 / GM 野怪 / 其它来源共用。
## opts: ensure_hero, ensure_caster, charge_food, life_override, refresh_pathing
func build_unit_entry(
	type_id: String, site_wc3: Vector2, owner_id: int, extras: Dictionary = {}
) -> Dictionary:
	var entry := {
		"typeId": type_id,
		"position": {"x": site_wc3.x, "y": site_wc3.y, "z": 0.0},
		"angle": MeleeBootstrap.UNIT_FACING_RAD,
		"scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"owner": owner_id,
		"flags": 2,
		"creationNumber": alloc_creation_number(),
		"variation": 0,
	}
	entry.merge(extras, true)
	return entry


func spawn_entry(entry: Dictionary, opts: Dictionary = {}) -> Node3D:
	if _map_root == null or _heightfield == null or entry.is_empty():
		return null
	var node := _map_root.add_unit_instance(entry, _heightfield.as_dict_view())
	if node == null:
		return null
	UnitLife.ensure(node)
	if opts.has("life_override"):
		UnitLife.set_life(node, float(opts["life_override"]))
	ensure_combat_ai(node)
	if bool(opts.get("ensure_hero", false)):
		ensure_hero(node)
	if bool(opts.get("ensure_caster", false)) and _ensure_caster.is_valid():
		_ensure_caster.call(node)
	if bool(opts.get("charge_food", false)) and _add_food_used.is_valid():
		var food := BuildingCatalog.get_food_used(str(entry.get("typeId", "")))
		if food > 0:
			_add_food_used.call(int(entry.get("owner", 0)), food)
	if bool(opts.get("refresh_pathing", true)) and _refresh_pathing.is_valid():
		_refresh_pathing.call()
	if _health_bar_manager != null:
		_health_bar_manager.resync()
	return node


## 在锚点单位附近刷（开发/GM）。
func spawn_near(
	anchor: Node3D, type_id: String, owner_id: int, offset_wc3: Vector2, opts: Dictionary = {}
) -> Node3D:
	if anchor == null or not is_instance_valid(anchor):
		return null
	var xy := Wc3Coords.godot_to_wc3_xy(anchor.global_position) + offset_wc3
	var extras: Dictionary = opts.get("entry_extras", {})
	var entry := build_unit_entry(type_id, xy, owner_id, extras)
	return spawn_entry(entry, opts)


## 召唤：Birth 动画 + InteractionSetup + 可选 SummonLifetime。
## entry 需已含 typeId/position/owner/creationNumber/spawn_anim 等。
func spawn_summon(
	entry: Dictionary, duration: float = 0.0, kill_cb: Callable = Callable(), caster: Node3D = null
) -> Node3D:
	if not entry.has("spawn_anim"):
		entry = entry.duplicate(true)
		entry["spawn_anim"] = "Birth"
	var node := spawn_entry(entry, {"refresh_pathing": true})
	if node == null:
		return null
	UnitMana.ensure(node)
	InteractionSetup.attach(node)
	if duration > 0.0:
		var life := SummonLifetime.new()
		life.name = "SummonLifetime"
		node.add_child(life)
		life.configure(duration, kill_cb)
	if caster != null and is_instance_valid(caster):
		node.set_meta("summon_caster_id", caster.get_instance_id())
	return node


func find_owned_unit_by_types(owner_id: int, type_ids: PackedStringArray) -> Node3D:
	var host: Node = _unit_host.call() if _unit_host.is_valid() else null
	if host == null:
		return null
	for tid in type_ids:
		for c in host.get_children():
			if not (c is Node3D) or not is_instance_valid(c):
				continue
			var node := c as Node3D
			var ud: Variant = node.get_meta("unit_data", {})
			if typeof(ud) != TYPE_DICTIONARY:
				continue
			if str((ud as Dictionary).get("typeId", "")) != str(tid):
				continue
			if int((ud as Dictionary).get("owner", -1)) == owner_id:
				return node
	return null


## 英雄背包 + 被动技能运行时。
func ensure_hero(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var inv := Inventory.ensure_on(unit)
	if inv != null and _on_inventory_changed.is_valid() and not inv.changed.is_connected(_on_inventory_changed):
		inv.changed.connect(_on_inventory_changed)
	if _ensure_hero_passives.is_valid():
		_ensure_hero_passives.call(unit)


## 可战斗非建筑单位挂 UnitAI + AttackController；中立 → 入营。
func ensure_combat_ai(unit: Node3D) -> UnitAI:
	if unit == null or not is_instance_valid(unit):
		return null
	if not CombatQuery.has_weapon(unit):
		return null
	var tid := CombatQuery.type_id_of(unit)
	if BuildingCatalog.is_building(tid) or BuildingVisual.is_building(tid):
		return null
	if _ensure_attack_controller.is_valid():
		_ensure_attack_controller.call(unit)
	var existing := UnitAI.of(unit)
	if existing != null:
		_configure_unit_ai(existing, unit)
		existing.set_profile(UnitAI.default_profile_for(unit))
		_attach_to_camp_if_neutral(unit, existing)
		return existing
	var ai := UnitAI.new()
	ai.name = UnitAI.NODE_NAME
	unit.add_child(ai)
	_configure_unit_ai(ai, unit)
	ai.set_profile(UnitAI.default_profile_for(unit))
	_attach_to_camp_if_neutral(unit, ai)
	ai.captures_home_from_body()
	return ai


## 地图已有单位 + 开局刷兵：批量挂 AI / 英雄，并聚类营地。
func wire_existing() -> void:
	var host: Node = _unit_host.call() if _unit_host.is_valid() else null
	if host == null:
		return
	for c in host.get_children():
		if c is Node3D:
			ensure_combat_ai(c as Node3D)
			ensure_hero(c as Node3D)
	var reg_host := _registry_host if _registry_host != null else self
	var reg := TeamRegistry.attach(reg_host)
	if reg != null:
		var summary := reg.cluster_and_bind(host)
		print(
			"[TeamRegistry] players=%d camps=%d units=%d"
			% [summary.players, summary.camps, summary.units]
		)
		for c in host.get_children():
			if c is Node3D:
				var ai := UnitAI.of(c as Node3D)
				if ai != null:
					ai.captures_home_from_body()


func teleport_wc3(unit: Node3D, wc3_xy: Vector2) -> void:
	if unit == null or not is_instance_valid(unit) or wc3_xy == Vector2.INF:
		return
	var z := 0.0
	if _heightfield != null and _heightfield.is_valid():
		z = _heightfield.interpolated_height(wc3_xy.x, wc3_xy.y)
	unit.global_position = Wc3Coords.wc3_xy_to_godot(wc3_xy.x, wc3_xy.y, z)
	if unit.has_meta("unit_data"):
		var d: Dictionary = unit.get_meta("unit_data", {}).duplicate(true)
		var pos: Dictionary = d.get("position", {})
		if typeof(pos) != TYPE_DICTIONARY:
			pos = {}
		pos["x"] = wc3_xy.x
		pos["y"] = wc3_xy.y
		pos["z"] = z
		d["position"] = pos
		unit.set_meta("unit_data", d)


func _dispatch_trained_rally(building: Node3D, unit: Node3D) -> void:
	if building == null or unit == null or _command_router == null:
		return
	if not BuildingRally.has_rally(building):
		return
	match BuildingRally.kind(building):
		BuildingRally.KIND_GOLD_MINE:
			var mine := BuildingRally.mine_node(building)
			if mine != null:
				_command_router.issue_harvest_gold([unit], mine, UnitOrder.Source.UNKNOWN)
				return
		BuildingRally.KIND_TREE:
			var cn := BuildingRally.tree_cn(building)
			if cn >= 0:
				_command_router.issue_harvest_lumber([unit], cn, UnitOrder.Source.UNKNOWN)
				return
	var goal := BuildingRally.goal_wc3(building)
	if goal != Vector2.INF:
		_command_router.issue_move_to_wc3([unit], goal, UnitOrder.Source.UNKNOWN)


func _attach_to_camp_if_neutral(unit: Node3D, ai: UnitAI) -> void:
	if unit == null or ai == null:
		return
	var reg_host := _registry_host if _registry_host != null else self
	var reg := TeamRegistry.get_for(reg_host)
	if reg == null:
		return
	if reg.attach_to_nearest_camp(unit):
		ai.captures_home_from_body()


func _configure_unit_ai(ai: UnitAI, unit: Node3D) -> void:
	if ai == null or unit == null:
		return
	ai.configure(
		func() -> bool: return _is_player_occupied(unit),
		_ensure_attack_controller,
		_unit_host,
		Callable(),
		_ensure_navigator
	)


func _is_player_occupied(unit: Node3D) -> bool:
	if unit == null or _command_router == null:
		return false
	var q := _command_router.queue_for(unit)
	if q == null or q.is_idle():
		return false
	var o: UnitOrder = q.current
	if o == null:
		return false
	return o.source != UnitOrder.Source.UNIT_AI


func _on_form_changed(unit: Node3D) -> void:
	form_changed.emit(unit)

func ensure_visual(unit: Node3D) -> Unit:
	return presenter.ensure_visual(unit)

func apply_form(unit: Node3D, type_id: String) -> bool:
	return forms.apply_form(unit, type_id) if is_instance_valid(forms) else false

func apply_building_upgrade(unit: Node3D, type_id: String) -> bool:
	return forms.apply_building_upgrade(unit, type_id) if is_instance_valid(forms) else false

func issue_call_to_arms(selected: Array, source: int) -> int:
	return forms.issue_call_to_arms(selected, source) if is_instance_valid(forms) else 0
