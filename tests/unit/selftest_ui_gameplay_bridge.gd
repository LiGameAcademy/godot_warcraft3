extends SceneTree

## UI → 玩法桥的自检：UiManager 路由到桥并触发模块回调。
## 设计：docs/design/game/UI_FRAMEWORK.md §6

const UiGameplayBridge := preload("res://client/ui/ui_gameplay_bridge.gd")

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
	# UiManager 没有 bind session 时 emit_intent 不应抛错。
	if is_instance_valid(UiManager):
		UiManager.emit_intent(UiIntent.COMMAND, {"action_id": "noop"})
		UiManager.emit_intent(UiIntent.MINIMAP_CLICK, {"uv": Vector2.ZERO})
		_pass("emit_intent 在无 session 时安全 no-op")


func _run_routes_through_bridge() -> void:
	var bridge := UiGameplayBridge.new()
	root.add_child(bridge)

	var captured_command := {"hit": false, "id": ""}
	var captured_rclick := {"hit": false, "id": ""}
	var captured_train := {"hit": false, "slot": -1}
	var captured_use := {"hit": false, "slot": -1}
	var captured_drop := {"hit": false, "slot": -1}
	var captured_swap := {"hit": false, "a": -1, "b": -1}
	var captured_multi := {"hit": false, "iid": 0}
	var captured_focus := {"hit": false, "world": Vector3.ZERO}

	var stub_router := _make_stub(\"_StubRouter\", [
		"func dispatch_action(action_id: String, src: int) -> void:",
		"\thit_command = {\"id\": action_id, \"src\": src}",
		"func dispatch_action_rclick(action_id: String) -> void:",
		"\thit_rclick = {\"id\": action_id}",
	])
	root.add_child(stub_router)

	var prod_panel := _make_stub(\"_StubProduction\", [
		"func cancel_selected(slot_index: int) -> void:",
		"\thit = {\"slot\": slot_index}",
	])
	root.add_child(prod_panel)

	var items_mod := _make_stub(\"_StubItems\", [
		"func use_slot(slot: int) -> void:",
		"\tuse_hit = {\"slot\": slot}",
		"func drop_slot(slot: int) -> void:",
		"\tdrop_hit = {\"slot\": slot}",
		"func swap_slots(a: int, b: int) -> void:",
		"\tswap_hit = {\"a\": a, \"b\": b}",
	])
	root.add_child(items_mod)

	var selector := _make_stub(\"_StubSelector\", [
		"func set_primary(unit) -> void:",
		"\tprimary_hit = {\"set\": true}",
	])
	root.add_child(selector)

	var camera := _make_stub(\"_StubCamera\", [
		"func focus_on_position(world: Vector3) -> void:",
		"\tfocus_hit = {\"world\": world}",
	])
	root.add_child(camera)

	bridge.bind(
		null,
		stub_router,
		prod_panel,
		items_mod,
		selector,
		camera,
		null,
		Vector2.ZERO,
		Vector2(100, 100),
		null
	)

	UiManager.emit_intent(UiIntent.COMMAND, {"action_id": "train_archer"})
	if stub_router.hit_command.get("id", "") == "train_archer":
		_pass("COMMAND intent → router.dispatch_action")
	else:
		_fail("COMMAND intent 未转发（hit=%s）" % str(stub_router.hit_command))

	UiManager.emit_intent(UiIntent.COMMAND_RCLICK, {"action_id": "move"})
	if stub_router.hit_rclick.get("id", "") == "move":
		_pass("COMMAND_RCLICK intent → router.dispatch_action_rclick")
	else:
		_fail("COMMAND_RCLICK intent 未转发")

	UiManager.emit_intent(UiIntent.TRAIN_CANCEL, {"slot_index": 3})
	if prod_panel.hit.get("slot", -2) == 3:
		_pass("TRAIN_CANCEL intent → prod_panel.cancel_selected")
	else:
		_fail("TRAIN_CANCEL intent 未转发")

	UiManager.emit_intent(UiIntent.ITEM_USE, {"slot": 4})
	UiManager.emit_intent(UiIntent.ITEM_DROP, {"slot": 5})
	UiManager.emit_intent(UiIntent.ITEM_SWAP, {"a": 1, "b": 2})
	if items_mod.use_hit.get("slot", -2) == 4:
		_pass("ITEM_USE intent → items_module.use_slot")
	else:
		_fail("ITEM_USE 未转发")
	if items_mod.drop_hit.get("slot", -2) == 5:
		_pass("ITEM_DROP intent → items_module.drop_slot")
	else:
		_fail("ITEM_DROP 未转发")
	if items_mod.swap_hit.get("a", -2) == 1 and items_mod.swap_hit.get("b", -2) == 2:
		_pass("ITEM_SWAP intent → items_module.swap_slots")
	else:
		_fail("ITEM_SWAP 未转发")

	# minimap：bridge 会调 camera.focus_on_position 并 world 计算
	UiManager.emit_intent(UiIntent.MINIMAP_CLICK, {"uv": Vector2(0.5, 0.5)})
	if camera.focus_hit.get("world", Vector3.INF) != Vector3.INF:
		_pass("MINIMAP_CLICK intent → camera.focus_on_position（world=%s）" % str(camera.focus_hit.world))
	else:
		_fail("MINIMAP_CLICK 未触发 focus")

	# shutdown 应断开
	bridge.shutdown()
	if not UiManager.has_session():
		_pass("bridge.shutdown() 解绑 UiManager session")

	# 清理
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


func _make_stub(name: String, funcs: Array) -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\n" + "\n".join(funcs)
	script.reload()
	var node := Node.new()
	node.name = name
	node.set_script(script)
	return node