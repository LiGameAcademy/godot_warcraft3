extends Node

## UiManager：Surface 注册、意图 fan-out；未 bind 会话不崩。

var failures: int = 0
var checks: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("UI_MGR: " + label)


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var mgr := get_node_or_null("/root/UiManager")
	check(mgr != null, "Autoload UiManager 存在")
	if mgr == null:
		_finish()
		return
	var surface := UiSurface.new()
	surface.name = "FakeMatchHud"
	add_child(surface)
	mgr.call("register_surface", &"match_hud", surface)
	check(mgr.call("get_surface", &"match_hud") == surface, "register_surface 可取回")
	var got_intent := {"n": 0, "id": &"", "action": ""}
	var on_intent := func(intent_id: StringName, payload: Dictionary) -> void:
		got_intent["n"] = int(got_intent["n"]) + 1
		got_intent["id"] = intent_id
		got_intent["action"] = str(payload.get("action_id", ""))
	mgr.intent.connect(on_intent)
	mgr.call("emit_intent", UiIntent.COMMAND, {"action_id": "train:Hamg"})
	check(int(got_intent["n"]) == 1, "emit_intent 触发 signal")
	check(got_intent["id"] == UiIntent.COMMAND, "意图 id 正确")
	check(str(got_intent["action"]) == "train:Hamg", "payload 透传")
	mgr.call("unbind_session")
	mgr.call("emit_intent", UiIntent.ITEM_USE, {"slot": 0})
	check(int(got_intent["n"]) == 2, "未 bind 会话仍可 fan-out 意图")
	mgr.call("show_tip", "资源不够")
	mgr.call("push_status", "ok")
	check(true, "push/tip 无 Surface 实现时不崩")
	mgr.call("unregister_surface", &"match_hud")
	check(mgr.call("get_surface", &"match_hud") == null, "unregister 后清空")
	_finish()


func _finish() -> void:
	print(
		"selftest_ui_manager: %s (%d checks)"
		% [("PASS" if failures == 0 else "FAIL"), checks]
	)
	get_tree().quit(0 if failures == 0 else 1)
