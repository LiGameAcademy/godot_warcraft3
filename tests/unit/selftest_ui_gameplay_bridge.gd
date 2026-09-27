extends SceneTree

## UI → 玩法桥的自检：UiManager 路由到桥并触发模块回调。
## 设计：docs/design/game/UI_FRAMEWORK.md §6 / §8 M2
##
## UiGameplayBridge / UiIntent 已有 class_name，按规则用全局类型名引用，
## 不再 preload。
##
## 跑法（仓库根）：
##   godot --path apps/game -s res://../tests/unit/selftest_ui_gameplay_bridge.gd

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("[ui_bridge] ===== 开始 selftest =====")
	# 桥自身在没绑定会话时不响应 intent；用于验证安全门
	_run_safe_when_no_session()
	# 桥绑定占位回调：command / rclick / train_cancel / item / minimap / multi_select
	_run_routes_through_bridge()
	print("[ui_bridge] 通过 %d / 失败 %d" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("[ui_bridge] FAIL: %s" % f)
	quit(1 if _failed > 0 else 0)


func _run_safe_when_no_session() -> void:
	if is_instance_valid(UiManager):
		UiManager.emit_intent(UiIntent.COMMAND, {"action_id": "noop"})
		UiManager.emit_intent(UiIntent.MINIMAP_CLICK, {"uv": Vector2.ZERO})
		_pass("emit_intent 在无 session 时安全 no-op")


func _run_routes_through_bridge() -> void:
	var bridge := UiGameplayBridge.new()
	root.add_child(bridge)

	var stub_router := _make_stub("_StubRouter", [
		"var hit_command: Dictionary = {}",
		"var hit_rclick: Dictionary = {}",
		"func dispatch_action(action_id: String, src: int) -> void:",
		"\thit_command = {\"id\": action_id, \"src\": src}",
		"func dispatch_action_rclick(action_id: String) -> void:",
		"\thit_rclick = {\"id\": action_id}",
	])
	root.add_child(stub_router)

	var prod_panel := _make_stub("_StubProduction", [
		"var hit: Dictionary = {}",
		"func cancel_selected(slot_index: int) -> void:",
		"\thit = {\"slot\": slot_index}",
	])
	root.add_child(prod_panel)

	var items_mod := _make_stub("_StubItems", [
		"var use_hit: Dictionary = {}",
		"var drop_hit: Dictionary = {}",
		"var swap_hit: Dictionary = {}",
		"func use_slot(slot: int) -> void:",
		"\tuse_hit = {\"slot\": slot}",
		"func drop_slot(slot: int) -> void:",
		"\tdrop_hit = {\"slot\": slot}",
		"func swap_slots(a: int, b: int) -> void:",
		"\tswap_hit = {\"a\": a, \"b\": b}",
	])
	root.add_child(items_mod)

	var selector := _make_stub("_StubSelector", [
		"var primary_hit: Dictionary = {}",
		"func set_primary(_unit) -> void:",
		"\tprimary_hit = {\"set\": true}",
	])
	root.add_child(selector)

	var camera := _make_stub("_StubCamera", [
		"var focus_hit: Dictionary = {}",
		"func focus_on_position(world: Vector3) -> void:",
		"\tfocus_hit = {\"world\": world}",
	])
	root.add_child(camera)

	# M2：bridge.bind(deps: Dictionary) — Callable 注入
	bridge.bind({
		UiGameplayBridge.DEP_DISPATCH_COMMAND: func(action_id: String, src: int) -> void:
			if stub_router.has_method("dispatch_action"):
				stub_router.dispatch_action(action_id, src),
		UiGameplayBridge.DEP_DISPATCH_COMMAND_RCLICK: func(action_id: String) -> void:
			if stub_router.has_method("dispatch_action_rclick"):
				stub_router.dispatch_action_rclick(action_id),
		UiGameplayBridge.DEP_CANCEL_TRAIN_SLOT: func(slot: int) -> void:
			prod_panel.cancel_selected(slot),
		UiGameplayBridge.DEP_USE_ITEM: func(slot: int) -> void: items_mod.use_slot(slot),
		UiGameplayBridge.DEP_DROP_ITEM: func(slot: int) -> void: items_mod.drop_slot(slot),
		UiGameplayBridge.DEP_SWAP_ITEMS: func(a: int, b: int) -> void: items_mod.swap_slots(a, b),
		UiGameplayBridge.DEP_SET_PRIMARY: func(unit) -> void: selector.set_primary(unit),
		UiGameplayBridge.DEP_FOCUS_CAMERA: func(world: Vector3) -> void: camera.focus_on_position(world),
		UiGameplayBridge.DEP_UV_TO_WORLD_FALLBACK: func(_uv: Vector2) -> Vector3: return Vector3(1, 2, 3),
	})

	UiManager.emit_intent(UiIntent.COMMAND, {"action_id": "train_archer"})
	var hit_command: Dictionary = stub_router.get("hit_command")
	if hit_command.get("id", "") == "train_archer":
		_pass("COMMAND intent → router.dispatch_action")
	else:
		_fail("COMMAND intent 未转发（hit=%s）" % str(hit_command))

	UiManager.emit_intent(UiIntent.COMMAND_RCLICK, {"action_id": "move"})
	var hit_rclick: Dictionary = stub_router.get("hit_rclick")
	if hit_rclick.get("id", "") == "move":
		_pass("COMMAND_RCLICK intent → router.dispatch_action_rclick")
	else:
		_fail("COMMAND_RCLICK intent 未转发")

	UiManager.emit_intent(UiIntent.TRAIN_CANCEL, {"slot_index": 3})
	var prod_hit: Dictionary = prod_panel.get("hit")
	if prod_hit.get("slot", -2) == 3:
		_pass("TRAIN_CANCEL intent → prod_panel.cancel_selected")
	else:
		_fail("TRAIN_CANCEL intent 未转发")

	UiManager.emit_intent(UiIntent.ITEM_USE, {"slot": 4})
	UiManager.emit_intent(UiIntent.ITEM_DROP, {"slot": 5})
	UiManager.emit_intent(UiIntent.ITEM_SWAP, {"a": 1, "b": 2})
	var use_hit: Dictionary = items_mod.get("use_hit")
	var drop_hit: Dictionary = items_mod.get("drop_hit")
	var swap_hit: Dictionary = items_mod.get("swap_hit")
	if use_hit.get("slot", -2) == 4:
		_pass("ITEM_USE intent → items_module.use_slot")
	else:
		_fail("ITEM_USE 未转发")
	if drop_hit.get("slot", -2) == 5:
		_pass("ITEM_DROP intent → items_module.drop_slot")
	else:
		_fail("ITEM_DROP 未转发")
	if swap_hit.get("a", -2) == 1 and swap_hit.get("b", -2) == 2:
		_pass("ITEM_SWAP intent → items_module.swap_slots")
	else:
		_fail("ITEM_SWAP 未转发")

	UiManager.emit_intent(UiIntent.MINIMAP_CLICK, {"uv": Vector2(0.5, 0.5)})
	var focus_hit: Dictionary = camera.get("focus_hit")
	if focus_hit.get("world", Vector3.INF) != Vector3.INF:
		_pass("MINIMAP_CLICK intent → camera.focus_on_position（world=%s）" % str(focus_hit.world))
	else:
		_fail("MINIMAP_CLICK 未触发 focus")

	bridge.shutdown()
	if not UiManager.has_session():
		_pass("bridge.shutdown() 解绑 UiManager session")

	stub_router.queue_free()
	prod_panel.queue_free()
	items_mod.queue_free()
	selector.queue_free()
	camera.queue_free()
	bridge.queue_free()


func _pass(label: String) -> void:
	_passed += 1
	print("[ui_bridge] PASS: %s" % label)


func _fail(label: String) -> void:
	_failed += 1
	_failures.append(label)
	print("[ui_bridge] FAIL: %s" % label)


func _make_stub(stub_name: String, funcs: Array) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\n" + "\n".join(funcs)
	script.reload()
	var node := Node.new()
	node.name = stub_name
	node.set_script(script)
	return node