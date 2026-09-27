extends SceneTree

## HUD → UiManager intent 端到端自检：注册 surface、emit_intent 透传、
## push_* 在 surface 无实现时静默 no-op、unregister 清空。
## 设计：docs/design/game/UI_FRAMEWORK.md §8 M4
##
## 跑法（仓库根）：
##   godot --path apps/game -s res://../tests/unit/selftest_hud_intent.gd

var _passed: int = 0
var _failed: int = 0
var _passed_labels: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	print("[hud_intent] ===== 开始 selftest =====")
	if not is_instance_valid(UiManager):
		_fail("UiManager Autoload 缺失")
		_finish()
		return

	# 1. 注册 fake surface
	var hud := Node.new()
	hud.name = "FakeMatchHud"
	var gs := GDScript.new()
	gs.source_code = "extends Node\nfunc surface_id() -> StringName: return &\"match_hud\""
	gs.reload()
	hud.set_script(gs)
	root.add_child(hud)
	UiManager.call("register_surface", &"match_hud", hud)
	if UiManager.call("get_surface", &"match_hud") == hud:
		_pass("register_surface 注册 fake_match_hud")
	else:
		_fail("register_surface 后 get_surface != hud")

	# 2. emit_intent 透传
	var got := {"id": &"", "payload": {}}
	UiManager.intent.connect(func(intent_id: StringName, payload: Dictionary) -> void:
		got["id"] = intent_id
		got["payload"] = payload)
	UiManager.emit_intent(UiIntent.COMMAND, {"action_id": "train:Hamg"})
	if got["id"] == UiIntent.COMMAND and str(got["payload"].get("action_id", "")) == "train:Hamg":
		_pass("emit_intent(COMMAND) 收到正确 id 与 payload")
	else:
		_fail("emit_intent 信号未透传（got=%s）" % str(got))

	# 3. push_* 在 surface 无 push_* 方法时静默 no-op
	UiManager.call("push_resources", {"gold": 10, "lumber": 5, "food_used": 0, "food_cap": 100})
	UiManager.call("push_selection", {})
	UiManager.call("push_command_card", [])
	UiManager.call("push_status", "ok")
	UiManager.call("show_tip", "tip")
	_pass("push_* 在 surface 无实现时静默 no-op")

	# 4. unregister 清理
	UiManager.call("unregister_surface", &"match_hud")
	if UiManager.call("get_surface", &"match_hud") == null:
		_pass("unregister 后清空")
	else:
		_fail("unregister 后仍残留 surface")

	hud.queue_free()
	_finish()


func _pass(label: String) -> void:
	_passed += 1
	_passed_labels.append(label)
	print("[hud_intent] PASS: %s" % label)


func _fail(label: String) -> void:
	_failed += 1
	_failures.append(label)
	print("[hud_intent] FAIL: %s" % label)


func _finish() -> void:
	print("[hud_intent] 通过 %d / 失败 %d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)