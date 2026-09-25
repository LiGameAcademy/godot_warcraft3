class_name SelectionHudModule
extends Node

## 选中 HUD 协调：肖像 vitals / 限时生命条 / buff 条 / 选中详情。
## 建造工地与训练队列 HUD 经 Callable 注入；不持有 GameDirector 类型。
## TODO: 肖像/buff 目前仍由 tick 轮询；后续改为 UnitLife / Buff 信号驱动。

var _game_hud: Node
var _unit_selector: Node
var _map_root: Node
var _sync_build_hud: Callable
var _is_controllable: Callable


func matches_dependencies(hud: Node, selector: Node, root: Node) -> bool:
	return _game_hud == hud and _unit_selector == selector and _map_root == root and _sync_build_hud.is_valid()


func configure(deps: Dictionary) -> void:
	_game_hud = deps.get("game_hud") as Node
	_unit_selector = deps.get("unit_selector") as Node
	_map_root = deps.get("map_root") as Node
	_sync_build_hud = deps.get("sync_build_hud", Callable()) as Callable
	_is_controllable = deps.get("is_controllable", Callable()) as Callable


func shutdown() -> void:
	_game_hud = null
	_unit_selector = null
	_map_root = null
	_sync_build_hud = Callable()
	_is_controllable = Callable()


func _exit_tree() -> void:
	shutdown()


## Prime current local unit types during the loading screen, without selecting them.
func prepare_starting_portraits(owner_id: int) -> void:
	if _game_hud == null or _map_root == null or not _game_hud.has_method("prepare_portraits"):
		return
	var host: Node = _map_root.call("get_unit_layer") as Node
	if host == null:
		return
	var type_ids: PackedStringArray = PackedStringArray()
	for unit: Node in host.get_children():
		if not _controllable(unit):
			continue
		var type_id: String = CombatQuery.type_id_of(unit)
		if not type_id.is_empty() and not type_ids.has(type_id):
			type_ids.append(type_id)
	await _game_hud.call("prepare_portraits", type_ids, owner_id)


func setup_portrait() -> void:
	if _game_hud == null or _map_root == null:
		return
	if not _game_hud.has_method("configure_portrait"):
		return
	var cache = null
	var catalog = null
	if _map_root.has_method("get_model_cache"):
		cache = _map_root.call("get_model_cache")
	if _map_root.has_method("get_id_catalog"):
		catalog = _map_root.call("get_id_catalog")
	_game_hud.call("configure_portrait", cache, catalog)


## 每帧：肖像生命/魔法、限时条、buff/攻甲芯片。
func tick(_delta: float = 0.0) -> void:
	refresh_portrait_vitals()
	refresh_portrait_timed_life_bar()
	refresh_buff_strip()


func apply_selection_info(primary: Node3D, selected: Array) -> void:
	if _game_hud == null:
		return
	if not _game_hud.has_method("set_selection_info"):
		_apply_unit_info(primary, "")
		return
	_game_hud.call("set_selection_info", SelectionInfoBuilder.build(primary, selected))


func sync_panel() -> void:
	if _unit_selector == null or not _unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = _unit_selector.call("get_primary") as Node3D
	var selected: Array = []
	if _unit_selector.has_method("get_selected"):
		selected = _unit_selector.call("get_selected")
	if primary == null or _game_hud == null:
		return
	apply_selection_info(primary, selected)
	if _sync_build_hud.is_valid():
		_sync_build_hud.call()


func sync_panel_hp_only() -> void:
	refresh_portrait_vitals()


func bind_inventory_for(primary: Node3D) -> void:
	if _game_hud == null or not _game_hud.has_method("bind_inventory"):
		return
	var inv = null
	var read_only := false
	if primary != null and is_instance_valid(primary):
		var tid := CombatQuery.type_id_of(primary)
		if TechPresence.is_hero_id(tid):
			# 己方：可操作；敌方/中立：只读展示（对齐原作点选敌方英雄可见背包）。
			inv = Inventory.of(primary)
			if inv == null and _controllable(primary):
				inv = Inventory.ensure_on(primary)
			read_only = inv != null and not _controllable(primary)
	_game_hud.call("bind_inventory", inv, read_only)


func refresh_portrait_vitals() -> void:
	if _game_hud == null or _unit_selector == null or not _unit_selector.has_method("get_primary"):
		return
	if not _game_hud.has_method("update_portrait_vitals"):
		return
	var primary: Node3D = _unit_selector.call("get_primary") as Node3D
	if primary == null or not is_instance_valid(primary):
		return
	var vit := SelectionInfoBuilder.vitals(primary)
	_game_hud.call(
		"update_portrait_vitals",
		int(vit.get("hp", 0)),
		int(vit.get("hp_max", 0)),
		int(vit.get("mana", 0)),
		int(vit.get("mana_max", 0))
	)


func refresh_portrait_timed_life_bar() -> void:
	if _game_hud == null or _unit_selector == null or not _unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = _unit_selector.call("get_primary") as Node3D
	if primary == null:
		return
	var timed := SelectionInfoBuilder.timed_life_progress(primary)
	if not bool(timed.get("show", false)):
		return
	if _game_hud.has_method("update_portrait_timed_life"):
		_game_hud.call(
			"update_portrait_timed_life",
			float(timed.get("left", 0.0)),
			float(timed.get("total", 1.0))
		)


func refresh_buff_strip() -> void:
	if _game_hud == null or _unit_selector == null or not _unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = _unit_selector.call("get_primary") as Node3D
	if primary == null or not is_instance_valid(primary):
		if _game_hud.has_method("update_buff_strip"):
			_game_hud.call("update_buff_strip", [])
		return
	if _game_hud.has_method("update_buff_strip"):
		_game_hud.call("update_buff_strip", BuffQuery.hud_entries(primary))
	if _game_hud.has_method("update_combat_stat_chips"):
		var stats := SelectionInfoBuilder.combat_stats(primary)
		_game_hud.call(
			"update_combat_stat_chips",
			stats.get("attack", {}) as Dictionary,
			stats.get("armor", {}) as Dictionary
		)


func _apply_unit_info(unit: Node3D, label: String) -> void:
	if _game_hud == null or unit == null:
		return
	if not _game_hud.has_method("set_unit_info"):
		return
	UnitLife.ensure(unit)
	var hp := int(round(UnitLife.get_life(unit)))
	var hp_max := int(round(UnitLife.get_max_life(unit)))
	var name_s := label
	if name_s.is_empty():
		var d: Dictionary = unit.get_meta("unit_data", {})
		name_s = str(d.get("typeId", "—"))
	_game_hud.call("set_unit_info", name_s, hp, hp_max)


func _controllable(node: Node) -> bool:
	if _is_controllable.is_valid():
		return bool(_is_controllable.call(node))
	return false
