extends Node

## 游戏 UI 壳与意图路由（Autoload：UiManager）。
## 不持有玩法权威、不判 Requires/扣费；只注册 Surface、推送展示、fan-out 意图。
## 设计：docs/design/game/UI_FRAMEWORK.md

signal intent(intent_id: StringName, payload: Dictionary)
signal session_bound()
signal session_unbound()

const SURFACE_MATCH_HUD := &"match_hud"

var _surfaces: Dictionary = {} # StringName -> UiSurface (or Node duck-typed)
var _active_surface: StringName = &""
var _bridge: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func register_surface(id: StringName, surface: Node) -> void:
	if id == &"" or surface == null or not is_instance_valid(surface):
		push_warning("UiManager.register_surface: invalid id/surface")
		return
	_surfaces[id] = surface
	var exit_cb := _on_surface_tree_exiting.bind(id)
	surface.set_meta(&"_ui_manager_exit_cb", exit_cb)
	if not surface.tree_exiting.is_connected(exit_cb):
		surface.tree_exiting.connect(exit_cb)
	if _active_surface == &"":
		set_active_surface(id)


func unregister_surface(id: StringName) -> void:
	if not _surfaces.has(id):
		return
	var surface: Node = _surfaces[id] as Node
	if surface != null and is_instance_valid(surface) and surface.has_meta(&"_ui_manager_exit_cb"):
		var exit_cb: Callable = surface.get_meta(&"_ui_manager_exit_cb") as Callable
		if exit_cb.is_valid() and surface.tree_exiting.is_connected(exit_cb):
			surface.tree_exiting.disconnect(exit_cb)
		surface.remove_meta(&"_ui_manager_exit_cb")
	_surfaces.erase(id)
	if _active_surface == id:
		_active_surface = &""
		for other_id in _surfaces.keys():
			set_active_surface(other_id as StringName)
			break


func get_surface(id: StringName) -> Node:
	return _surfaces.get(id) as Node


func set_active_surface(id: StringName) -> void:
	if _active_surface == id:
		return
	var prev := get_surface(_active_surface)
	if prev != null and prev.has_method("on_surface_deactivated"):
		prev.call("on_surface_deactivated")
	_active_surface = id
	var next := get_surface(id)
	if next != null and next.has_method("on_surface_activated"):
		next.call("on_surface_activated")


func bind_session(bridge: Node) -> void:
	_bridge = bridge
	session_bound.emit()


func unbind_session() -> void:
	_bridge = null
	session_unbound.emit()


func has_session() -> bool:
	return _bridge != null and is_instance_valid(_bridge)


func emit_intent(intent_id: StringName, payload: Dictionary = {}) -> void:
	if intent_id == &"":
		return
	intent.emit(intent_id, payload)


func push_resources(vm: Dictionary) -> void:
	_call_active("push_resources", [vm])


func push_selection(vm: Dictionary) -> void:
	_call_active("push_selection", [vm])


func push_command_card(entries: Array) -> void:
	_call_active("push_command_card", [entries])


func push_status(text: String) -> void:
	_call_active("push_status", [text])


func show_tip(text: String) -> void:
	_call_active("show_tip", [text])


func _call_active(method: String, args: Array) -> void:
	var surface := get_surface(_active_surface)
	if surface == null or not is_instance_valid(surface):
		return
	if surface.has_method(method):
		surface.callv(method, args)


func _on_surface_tree_exiting(id: StringName) -> void:
	unregister_surface(id)
