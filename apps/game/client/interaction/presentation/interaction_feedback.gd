class_name InteractionFeedback
extends Node
const MoveConfirmFxScene = preload("res://scenes/move_confirm_fx.tscn")
var map_root: MapLoader
var unit_selector: Node
var _session: GameSession
var _navigation: NavigationModule
var preview_race := "human"
var local_player := 0
var _get_selected: Callable
var _controllable: Callable
var _rally_flag: RallyFlagFx
var _heightfield: Wc3Heightfield:
	get:
		return _navigation.heightfield if is_instance_valid(_navigation) else null

func configure(map: MapLoader, selector: Node, session: GameSession, navigation: NavigationModule,
		race: String, owner_id: int, selected: Callable, controllable: Callable) -> void:
	map_root = map
	unit_selector = selector
	_session = session
	_navigation = navigation
	preview_race = race
	local_player = owner_id
	_get_selected = selected
	_controllable = controllable

func shutdown() -> void:
	if is_instance_valid(_rally_flag):
		_rally_flag.queue_free()
	_rally_flag = null
	map_root = null
	unit_selector = null
	_session = null
	_navigation = null
	_get_selected = Callable()
	_controllable = Callable()

func _exit_tree() -> void:
	shutdown()

func spawn_move_confirm(goal_wc3: Vector2, kind: int = MoveConfirmFx.Kind.MOVE) -> void:
	if map_root == null:
		return
	var fx := MoveConfirmFxScene.instantiate() as MoveConfirmFx
	map_root.add_child(fx)
	var cache: MapModelCache = null
	if map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	fx.setup(cache)
	fx.play_at_wc3(goal_wc3, _heightfield, kind)


func ensure_rally_flag() -> RallyFlagFx:
	if _rally_flag != null and is_instance_valid(_rally_flag):
		return _rally_flag
	if map_root == null:
		return null
	var fx := RallyFlagFx.new()
	fx.name = "RallyFlagFx"
	map_root.add_child(fx)
	var cache: MapModelCache = null
	if map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	fx.setup(cache)
	_rally_flag = fx
	return fx


func sync_rally_flag() -> void:
	var building := rally_source()
	if building == null:
		if _rally_flag != null and is_instance_valid(_rally_flag):
			_rally_flag.hide_flag()
		return
	var fx := ensure_rally_flag()
	if fx == null:
		return
	var d: Dictionary = building.get_meta("unit_data", {})
	var race := str(d.get("race", "")).strip_edges().to_lower()
	if race.is_empty() and _session != null:
		race = str(_session.local_race).to_lower()
	if race.is_empty():
		race = preview_race.strip_edges().to_lower()
	var owner_id := int(d.get("owner", local_player))
	var tid := str(d.get("typeId", ""))
	var color_i := MapUnitLayer.resolve_team_color_index(tid, owner_id)
	fx.show_at_wc3(BuildingRally.goal_wc3(building), race, color_i, _heightfield)


func rally_source() -> Node3D:
	if unit_selector == null:
		return null
	var primary: Node3D = null
	if unit_selector.has_method("get_primary"):
		primary = unit_selector.call("get_primary") as Node3D
	if (
		primary != null
		and (_controllable.is_valid() and bool(_controllable.call(primary)))
		and BuildingRally.can_set_rally(primary)
		and BuildingRally.has_rally(primary)
	):
		return primary
	var selected: Array = _get_selected.call() if _get_selected.is_valid() else []
	for n in selected:
		if not (n is Node3D):
			continue
		var b := n as Node3D
		if BuildingRally.can_set_rally(b) and BuildingRally.has_rally(b):
			return b
	return null


func pointer_over_blocking_gui(screen_pos: Vector2) -> bool:
	if unit_selector is UnitSelector:
		return (unit_selector as UnitSelector).is_blocked_at(screen_pos)
	if unit_selector != null and unit_selector.has_method("is_blocked_at"):
		return bool(unit_selector.call("is_blocked_at", screen_pos))
	var vp := get_viewport()
	if vp == null:
		return false
	var hovered := vp.gui_get_hovered_control()
	if hovered == null:
		return false
	return hovered.mouse_filter != Control.MOUSE_FILTER_IGNORE
