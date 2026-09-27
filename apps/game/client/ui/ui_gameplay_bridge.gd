class_name UiGameplayBridge
extends Node

## 对局作用域的 UI ↔ 玩法桥：订阅 UiManager.intent 并分派到 CommandRouter / 业务模块。
## 不持有玩法权威；只持有对回调的 Callable 引用。
## 设计：docs/design/game/UI_FRAMEWORK.md §4 / §6。

var _director: Node = null
var _command_router: Node = null
var _production_panel: Node = null
var _items_module: Node = null
var _unit_selector: Node = null
var _camera: Node = null
var _heightfield: Node = null
var _cam_min: Vector2 = Vector2.ZERO
var _cam_max: Vector2 = Vector2.ZERO
var _game_hud: Node = null
var _bound: bool = false


func bind(
	director: Node,
	command_router: Node,
	production_panel: Node,
	items_module: Node,
	unit_selector: Node,
	camera: Node,
	heightfield: Node,
	cam_min: Vector2,
	cam_max: Vector2,
	game_hud: Node
) -> void:
	_director = director
	_command_router = command_router
	_production_panel = production_panel
	_items_module = items_module
	_unit_selector = unit_selector
	_camera = camera
	_heightfield = heightfield
	_cam_min = cam_min
	_cam_max = cam_max
	_game_hud = game_hud
	if is_instance_valid(UiManager):
		# bind_session 必须先于 intent.connect，确保桥视角的 session 状态正确。
		UiManager.bind_session(self)
		if not UiManager.intent.is_connected(_on_intent):
			UiManager.intent.connect(_on_intent)
	_bound = true


func shutdown() -> void:
	if is_instance_valid(UiManager) and UiManager.intent.is_connected(_on_intent):
		UiManager.intent.disconnect(_on_intent)
	if is_instance_valid(UiManager):
		UiManager.unbind_session()
	_bound = false
	_director = null
	_command_router = null
	_production_panel = null
	_items_module = null
	_unit_selector = null
	_camera = null
	_heightfield = null
	_game_hud = null


func _exit_tree() -> void:
	shutdown()


func _on_intent(intent_id: StringName, payload: Dictionary) -> void:
	if not _bound:
		return
	if intent_id == UiIntent.COMMAND:
		var action_id := str(payload.get("action_id", ""))
		if action_id.is_empty():
			return
		if _command_router != null and is_instance_valid(_command_router):
			if _command_router.has_method("dispatch_action"):
				# Source 默认 PANEL；与 HUD 旧 _on_command_action 行为一致。
				var src: int = int(payload.get("source", 2)) # 2 = UnitOrder.Source.PANEL
				_command_router.call("dispatch_action", action_id, src)
	elif intent_id == UiIntent.COMMAND_RCLICK:
		var action_id_r := str(payload.get("action_id", ""))
		if action_id_r.is_empty():
			return
		if _command_router != null and is_instance_valid(_command_router):
			if _command_router.has_method("dispatch_action_rclick"):
				_command_router.call("dispatch_action_rclick", action_id_r)
	elif intent_id == UiIntent.TRAIN_CANCEL:
		if _production_panel != null and is_instance_valid(_production_panel):
			if _production_panel.has_method("cancel_selected"):
				_production_panel.call("cancel_selected", int(payload.get("slot_index", -1)))
	elif intent_id == UiIntent.ITEM_USE:
		if _items_module != null and is_instance_valid(_items_module):
			if _items_module.has_method("use_slot"):
				_items_module.call("use_slot", int(payload.get("slot", -1)))
	elif intent_id == UiIntent.ITEM_DROP:
		if _items_module != null and is_instance_valid(_items_module):
			if _items_module.has_method("drop_slot"):
				_items_module.call("drop_slot", int(payload.get("slot", -1)))
	elif intent_id == UiIntent.ITEM_SWAP:
		if _items_module != null and is_instance_valid(_items_module):
			if _items_module.has_method("swap_slots"):
				_items_module.call(
					"swap_slots",
					int(payload.get("a", -1)),
					int(payload.get("b", -1))
				)
	elif intent_id == UiIntent.MULTI_SELECT:
		var iid := int(payload.get("instance_id", 0))
		if iid == 0 or _unit_selector == null or not is_instance_valid(_unit_selector):
			return
		var obj := instance_from_id(iid)
		if obj is Node3D and _unit_selector.has_method("set_primary"):
			_unit_selector.call("set_primary", obj)
	elif intent_id == UiIntent.MINIMAP_CLICK:
		_handle_minimap_click(payload.get("uv", Vector2.ZERO) as Vector2)


func _handle_minimap_click(uv: Vector2) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var world := Vector3.ZERO
	if _heightfield != null and is_instance_valid(_heightfield) and _heightfield.has_method("is_valid") and _heightfield.call("is_valid"):
		if _heightfield.has_method("minimap_uv_to_world") == false:
			# 桥使用静态工具避免直接耦合 MapMinimapUtils 的静态 API
			world = _uv_to_world_fallback(uv)
		else:
			world = _heightfield.call("minimap_uv_to_world", uv, 0.0) as Vector3
	else:
		world = _uv_to_world_fallback(uv)
	if _camera.has_method("focus_on_position"):
		_camera.call("focus_on_position", world)
	if _game_hud != null and is_instance_valid(_game_hud) and _game_hud.has_method("set_status"):
		var inv := 1.0 / Wc3Coords.WORLD_SCALE
		_game_hud.set_status("镜头 → (%.0f, %.0f)" % [world.x * inv, -world.z * inv])


func _uv_to_world_fallback(uv: Vector2) -> Vector3:
	var wx := lerpf(_cam_min.x, _cam_max.x, uv.x)
	var wy := lerpf(_cam_max.y, _cam_min.y, uv.y)
	return Wc3Coords.wc3_xy_to_godot(wx, wy, 0.0)