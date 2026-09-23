class_name ItemsModule
extends Node

## 对局内物品：地面生成、拾取反馈、背包 use/drop/swap、死亡掉落订阅。
## 由总管注入高度场与选择/状态回调；不依赖 GameDirector 类型。

var item_service: ItemService = null
var _ground_host: Node3D = null

var _map_root: MapLoader
var _heightfield: Wc3Heightfield
var _map_dir: String = ""
var _parent_for_ground: Node
var _combat: CombatModule
var _command_router: CommandRouter
var _set_status: Callable
var _get_primary: Callable
var _is_controllable: Callable
var _on_inventory_ui_refresh: Callable
var _get_model_cache: Callable


func configure(deps: Dictionary) -> void:
	_map_root = deps.get("map_root") as MapLoader
	_heightfield = deps.get("heightfield") as Wc3Heightfield
	_map_dir = str(deps.get("map_dir", ""))
	_parent_for_ground = deps.get("ground_parent") as Node
	_combat = deps.get("combat") as CombatModule
	_command_router = deps.get("command_router") as CommandRouter
	_set_status = deps.get("set_status", Callable()) as Callable
	_get_primary = deps.get("get_primary", Callable()) as Callable
	_is_controllable = deps.get("is_controllable", Callable()) as Callable
	_on_inventory_ui_refresh = deps.get("on_inventory_ui_refresh", Callable()) as Callable
	_get_model_cache = deps.get("get_model_cache", Callable()) as Callable
	_ensure_service()


func shutdown() -> void:
	if item_service != null:
		if item_service.ground_spawned.is_connected(_on_ground_spawned):
			item_service.ground_spawned.disconnect(_on_ground_spawned)
		if item_service.message.is_connected(_forward_status):
			item_service.message.disconnect(_forward_status)
	if _command_router != null and _command_router.item_feedback.is_connected(_forward_status):
		_command_router.item_feedback.disconnect(_forward_status)
	item_service = null
	_ground_host = null
	_map_root = null
	_heightfield = null
	_parent_for_ground = null
	_combat = null
	_command_router = null
	_set_status = Callable()
	_get_primary = Callable()
	_is_controllable = Callable()
	_on_inventory_ui_refresh = Callable()
	_get_model_cache = Callable()


func _exit_tree() -> void:
	shutdown()


func prepare_hero_death(unit: Node3D) -> void:
	if item_service != null:
		item_service.prepare_hero_death(unit)


func ground_host() -> Node3D:
	return _ground_host


func use_slot(slot: int) -> void:
	var unit := _primary_controllable()
	if unit == null:
		return
	var inv := Inventory.of(unit)
	if inv != null:
		var result := inv.try_use(slot)
		_forward_status(str(result.get("reason", "")))


func drop_slot(slot: int) -> void:
	var unit := _primary_controllable()
	if unit != null and item_service != null:
		item_service.drop_from(unit, slot)


func swap_slots(a: int, b: int) -> void:
	var unit := _primary_controllable()
	if unit == null:
		return
	var inv := Inventory.of(unit)
	if inv != null:
		inv.swap_slots(a, b)


func on_inventory_changed() -> void:
	if _on_inventory_ui_refresh.is_valid():
		_on_inventory_ui_refresh.call()


func spawn_test_kit_around_primary() -> bool:
	var unit := _primary_controllable()
	if unit == null or Inventory.of(unit) == null or item_service == null:
		_forward_status("请先选中己方英雄")
		return false
	var origin := Wc3Coords.godot_to_wc3_xy(unit.global_position)
	var ids := ["phea", "phea", "pman", "pman", "rde1", "rde1", "phea"]
	for i in range(ids.size()):
		var angle := TAU * float(i) / ids.size()
		item_service.spawn(
			ItemInstance.create(ids[i]),
			origin + Vector2(cos(angle), sin(angle)) * 180.0
		)
	_forward_status("已生成 7 件测试道具：右键拾取，六格满后应剩一件")
	return true


func _ensure_service() -> void:
	if _parent_for_ground == null:
		return
	if _ground_host == null or not is_instance_valid(_ground_host):
		_ground_host = Node3D.new()
		_ground_host.name = "GroundItems"
		_parent_for_ground.add_child(_ground_host)
	if item_service == null or not is_instance_valid(item_service):
		item_service = ItemService.new()
		item_service.name = "ItemService"
		add_child(item_service)
	item_service.configure(_ground_host, _heightfield, _map_dir)
	if not item_service.ground_spawned.is_connected(_on_ground_spawned):
		item_service.ground_spawned.connect(_on_ground_spawned)
	if not item_service.message.is_connected(_forward_status):
		item_service.message.connect(_forward_status)
	if _command_router != null and not _command_router.item_feedback.is_connected(_forward_status):
		_command_router.item_feedback.connect(_forward_status)
	if _combat != null:
		_combat.connect_unit_died(Callable(item_service, "on_unit_died"))


func _on_ground_spawned(ground: GroundItem) -> void:
	var cache: MapModelCache = null
	if _get_model_cache.is_valid():
		cache = _get_model_cache.call() as MapModelCache
	elif _map_root != null and _map_root.has_method("get_model_cache"):
		cache = _map_root.get_model_cache() as MapModelCache
	GroundItemVisual.attach(ground, cache)


func _forward_status(text: String) -> void:
	if _set_status.is_valid():
		_set_status.call(text)


func _primary_controllable() -> Node3D:
	var unit: Node3D = _get_primary.call() as Node3D if _get_primary.is_valid() else null
	if unit == null:
		return null
	if _is_controllable.is_valid() and not bool(_is_controllable.call(unit)):
		return null
	return unit
