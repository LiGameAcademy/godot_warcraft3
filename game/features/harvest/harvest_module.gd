class_name HarvestModule
extends Node

## 对局采集生命周期；账本仍由 GameSession / PlayerStock 持有。
const SceneDelay = preload("res://scripts/shared/infra/scene_delay.gd")
signal carry_changed(resource_id: String, amount: int)
signal deposited(gold: int, lumber: int)
signal state_changed(state: int)
signal mine_depleted(mine: Node3D)

var tree_registry: TreeRegistry
var _map: MapLoader
var _navigation: NavigationModule
var _session: GameSession
var _camera: Camera3D
var _ensure_visual: Callable
var _expire_corpse: Callable
var _controllers: Dictionary = {}
var _mines: Dictionary = {}
var _generation := 0

func configure(map: MapLoader, navigation: NavigationModule, session: GameSession,
		camera: Camera3D, ensure_visual: Callable, expire_corpse: Callable) -> void:
	_map = map
	_navigation = navigation
	_session = session
	_camera = camera
	if is_instance_valid(tree_registry):
		tree_registry.set_camera(camera)
	_ensure_visual = ensure_visual
	_expire_corpse = expire_corpse

func shutdown() -> void:
	_generation += 1
	for ref: WeakRef in _controllers.values():
		var hc := ref.get_ref() as HarvestController
		if not is_instance_valid(hc):
			continue
		hc.carry_changed.disconnect(_on_carry_changed)
		hc.deposited.disconnect(_on_deposited)
		hc.state_changed.disconnect(_on_state_changed)
		hc.abort()
		hc.configure(Callable(), Callable(), Callable(), Callable(), Callable(), Callable())
	for ref: WeakRef in _mines.values():
		var mine := ref.get_ref() as Node3D
		if not is_instance_valid(mine):
			continue
		var rt := GoldMineRuntime.ensure(mine)
		var cb := _on_gold_mine_depleted.bind(mine)
		if rt.depleted.is_connected(cb):
			rt.depleted.disconnect(cb)
	_controllers.clear()
	_mines.clear()
	if is_instance_valid(tree_registry):
		tree_registry.free()
	tree_registry = null
	_map = null
	_navigation = null
	_session = null
	_camera = null
	_ensure_visual = Callable()
	_expire_corpse = Callable()

func _exit_tree() -> void:
	shutdown()

func _stock_for_unit(unit: Node3D) -> PlayerStock:
	if not is_instance_valid(unit) or _session == null:
		return null
	return _session.stocks.get(int(unit.get_meta("unit_data", {}).get("owner", -1))) as PlayerStock

func _unit_host() -> Node:
	return _map.get_unit_layer() if is_instance_valid(_map) else null

func _path_query_ref() -> PathQuery:
	return _navigation.path_query if is_instance_valid(_navigation) else null

func _crowd_query_ref() -> UnitCrowdQuery:
	return _navigation.crowd_query if is_instance_valid(_navigation) else null

func _tree_registry_ref() -> TreeRegistry:
	return tree_registry

func _on_carry_changed(resource_id: String, amount: int) -> void:
	carry_changed.emit(resource_id, amount)

func _on_deposited(gold: int, lumber: int) -> void:
	deposited.emit(gold, lumber)

func _on_state_changed(state: int) -> void:
	state_changed.emit(state)

func setup_trees() -> void:
	if _map == null:
		return
	if tree_registry == null or not is_instance_valid(tree_registry):
		tree_registry = TreeRegistry.new()
		tree_registry.name = "TreeRegistry"
		add_child(tree_registry)
	var cam: Camera3D = null
	cam = _camera
	tree_registry.configure(_map, _map.get_id_catalog(), cam)
	tree_registry.rebuild_from_map()


func ensure_controller(unit: Node3D) -> HarvestController:
	if not is_instance_valid(unit):
		return null
	if _ensure_visual.is_valid():
		_ensure_visual.call(unit)
	var existing := unit.get_node_or_null("HarvestController") as HarvestController
	if existing != null:
		existing.configure(
			Callable(_navigation, "ensure_navigator"),
			Callable(self, "_stock_for_unit").bind(unit),
			Callable(self, "_unit_host"),
			Callable(self, "_path_query_ref"),
			Callable(self, "_crowd_query_ref"),
			Callable(self, "_tree_registry_ref")
		)
		_wire_signals(existing)
		return existing
	var hc := HarvestController.new()
	hc.name = "HarvestController"
	hc.configure(
		Callable(_navigation, "ensure_navigator"),
		Callable(self, "_stock_for_unit").bind(unit),
		Callable(self, "_unit_host"),
		Callable(self, "_path_query_ref"),
		Callable(self, "_crowd_query_ref"),
		Callable(self, "_tree_registry_ref")
	)
	unit.add_child(hc)
	_wire_signals(hc)
	return hc


func wire_mines() -> void:
	var host := _unit_host()
	if host == null:
		return
	for c in host.get_children():
		if not (c is Node3D) or not GoldMineRuntime.is_gold_mine(c):
			continue
		wire_mine(c as Node3D)


func wire_mine(mine: Node3D) -> void:
	if mine == null or not is_instance_valid(mine):
		return
	var rt := GoldMineRuntime.ensure(mine)
	if rt == null:
		return
	var cb := _on_gold_mine_depleted.bind(mine)
	if rt.depleted.is_connected(cb):
		return
	rt.depleted.connect(cb)
	_mines[mine.get_instance_id()] = weakref(mine)
	var exiting := _forget_mine.bind(mine.get_instance_id())
	if not mine.tree_exiting.is_connected(exiting):
		mine.tree_exiting.connect(exiting, CONNECT_ONE_SHOT)


func _on_gold_mine_depleted(mine: Node3D) -> void:
	if mine == null or not is_instance_valid(mine):
		return
	if bool(mine.get_meta("gold_mine_collapsing", false)):
		return
	mine.set_meta("gold_mine_collapsing", true)
	mine_depleted.emit(mine)
	WorldMembership.exit(mine)
	if is_instance_valid(mine):
		mine.visible = true
	var cache: MapModelCache = null
	if _map != null and _map.has_method("get_model_cache"):
		cache = _map.get_model_cache()
	var tid := str(mine.get_meta("unit_data", {}).get("typeId", "ngol"))
	var played: Dictionary = BuildingVisual.play_death(cache, mine, tid)
	var wait := float(played.get("duration", 0.0))
	if wait < 0.35:
		wait = 1.6
	var tree := get_tree()
	if tree != null:
		SceneDelay.create_timer(self, wait).timeout.connect(_finish_collapse.bind(weakref(mine), _generation))
	else:
		_on_gold_mine_collapse_finished(mine)


func _on_gold_mine_collapse_finished(mine: Node3D) -> void:
	if is_instance_valid(mine) and _expire_corpse.is_valid():
		_expire_corpse.call(mine)


func _wire_signals(hc: HarvestController) -> void:
	if hc == null:
		return
	if not hc.carry_changed.is_connected(_on_carry_changed):
		hc.carry_changed.connect(_on_carry_changed)
	if not hc.deposited.is_connected(_on_deposited):
		hc.deposited.connect(_on_deposited)
	if not hc.state_changed.is_connected(_on_state_changed):
		hc.state_changed.connect(_on_state_changed)
	_controllers[hc.get_instance_id()] = weakref(hc)
	var exiting := _forget_controller.bind(hc.get_instance_id())
	if not hc.tree_exiting.is_connected(exiting):
		hc.tree_exiting.connect(exiting, CONNECT_ONE_SHOT)


func is_harvestable_tree(node: Node) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var dd: Dictionary = node.get_meta("doodad_data", {})
	if dd.is_empty():
		return false
	var cn := int(dd.get("creationNumber", -1))
	if cn < 0 or tree_registry == null:
		return false
	return tree_registry.is_alive(cn)


func tree_cn_of(node: Node) -> int:
	if node == null:
		return -1
	var dd: Dictionary = node.get_meta("doodad_data", {})
	return int(dd.get("creationNumber", -1))


static func is_gold_mine(node: Node) -> bool:
	if node == null:
		return false
	var d: Dictionary = node.get_meta("unit_data", {})
	return str(d.get("typeId", "")).strip_edges() == HarvestController.GOLD_MINE_TYPE


func _forget_controller(id: int) -> void:
	_controllers.erase(id)

func _forget_mine(id: int) -> void:
	_mines.erase(id)

func _finish_collapse(ref: WeakRef, generation: int) -> void:
	if generation == _generation:
		_on_gold_mine_collapse_finished(ref.get_ref() as Node3D)
