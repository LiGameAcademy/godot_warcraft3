class_name UiGameplayBridge
extends Node

## 对局作用域的 UI ↔ 玩法桥：订阅 UiManager.intent 并分派到玩法模块。
## 不持有玩法权威；只持有对回调的 Callable 引用。
## 配置风格与 CommandCardModule / BuildModule 同款——bind(deps) 注入一组 Callable。
## 设计：docs/design/game/UI_FRAMEWORK.md §4 / §6。

## 注入依赖键名常量（避免散落魔法字符串）。
const DEP_DISPATCH_COMMAND := &"dispatch_command"
const DEP_DISPATCH_COMMAND_RCLICK := &"dispatch_command_rclick"
const DEP_CANCEL_TRAIN_SLOT := &"cancel_train_slot"
const DEP_USE_ITEM := &"use_item"
const DEP_DROP_ITEM := &"drop_item"
const DEP_SWAP_ITEMS := &"swap_items"
const DEP_SET_PRIMARY := &"set_primary"
const DEP_FOCUS_CAMERA := &"focus_camera_world"
## 兜底：uv → world；heightfield 为 null 时使用。
const DEP_UV_TO_WORLD_FALLBACK := &"uv_to_world_fallback"

var _deps: Dictionary = {}
var _bound: bool = false


func bind(deps: Dictionary) -> void:
	_deps = deps.duplicate()
	_bound = true
	if is_instance_valid(UiManager):
		# bind_session 必须先于 intent.connect，确保桥视角的 session 状态正确。
		UiManager.bind_session(self)
		if not UiManager.intent.is_connected(_on_intent):
			UiManager.intent.connect(_on_intent)


func shutdown() -> void:
	if is_instance_valid(UiManager) and UiManager.intent.is_connected(_on_intent):
		UiManager.intent.disconnect(_on_intent)
	if is_instance_valid(UiManager):
		UiManager.unbind_session()
	_bound = false
	_deps.clear()


func _exit_tree() -> void:
	shutdown()


func _on_intent(intent_id: StringName, payload: Dictionary) -> void:
	if not _bound:
		return
	if intent_id == UiIntent.COMMAND:
		_call_str_arg(DEP_DISPATCH_COMMAND, payload, "action_id")
	elif intent_id == UiIntent.COMMAND_RCLICK:
		_call_str_arg(DEP_DISPATCH_COMMAND_RCLICK, payload, "action_id")
	elif intent_id == UiIntent.TRAIN_CANCEL:
		_call_int_arg(DEP_CANCEL_TRAIN_SLOT, payload, "slot_index")
	elif intent_id == UiIntent.ITEM_USE:
		_call_int_arg(DEP_USE_ITEM, payload, "slot")
	elif intent_id == UiIntent.ITEM_DROP:
		_call_int_arg(DEP_DROP_ITEM, payload, "slot")
	elif intent_id == UiIntent.ITEM_SWAP:
		var a := int(payload.get("a", -1))
		var b := int(payload.get("b", -1))
		_call(DEP_SWAP_ITEMS, [a, b])
	elif intent_id == UiIntent.MULTI_SELECT:
		_handle_multi_select(int(payload.get("instance_id", 0)))
	elif intent_id == UiIntent.MINIMAP_CLICK:
		_handle_minimap_click(payload.get("uv", Vector2.ZERO) as Vector2)


func _call(dep_key: StringName, args: Array) -> void:
	if not _deps.has(dep_key):
		return
	var cb: Callable = _deps[dep_key] as Callable
	if not cb.is_valid():
		return
	cb.callv(args)


func _call_str_arg(dep_key: StringName, payload: Dictionary, key: String) -> void:
	var s := str(payload.get(key, ""))
	if s.is_empty():
		return
	# Source 默认 PANEL(2) — 与 HUD 旧 _on_command_action 行为一致。
	if dep_key == DEP_DISPATCH_COMMAND:
		var src: int = int(payload.get("source", 2))
		_call(dep_key, [s, src])
	else:
		_call(dep_key, [s])


func _call_int_arg(dep_key: StringName, payload: Dictionary, key: String) -> void:
	_call(dep_key, [int(payload.get(key, -1))])


func _handle_multi_select(iid: int) -> void:
	if iid == 0 or not _deps.has(DEP_SET_PRIMARY):
		return
	var obj := instance_from_id(iid)
	if obj is Node3D:
		var cb: Callable = _deps[DEP_SET_PRIMARY] as Callable
		if cb.is_valid():
			cb.call(obj as Node3D)


func _handle_minimap_click(uv: Vector2) -> void:
	var world := _resolve_world(uv)
	_call(DEP_FOCUS_CAMERA, [world])


func _resolve_world(uv: Vector2) -> Vector3:
	# 优先走外部注入的 resolver（如 Wc3Heightfield.minimap_uv_to_world），
	# 未注入时退化到 cam_min/cam_max 线性映射。
	if _deps.has(DEP_UV_TO_WORLD_FALLBACK):
		var cb: Callable = _deps[DEP_UV_TO_WORLD_FALLBACK] as Callable
		if cb.is_valid():
			return cb.call(uv) as Vector3
	return Vector3.ZERO