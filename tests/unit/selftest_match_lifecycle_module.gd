extends Node

## MatchLifecycleModule 契约：未开对手时跳过；shutdown 断开信号。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MATCH LIFECYCLE: " + label)


func _ready() -> void:
	var module := MatchLifecycleModule.new()
	add_child(module)
	var game_root := Node.new()
	game_root.name = "GameRoot"
	add_child(game_root)
	module.configure({
		"game_root": game_root,
		"settings_source": self,
	})
	var session := GameSession.from_melee_bootstrap("", 0, "human", 5)
	module.setup_match_end(session, false)
	check(not module._armed, "无对手时不武装")
	module.setup_match_end(session, true)
	check(module._armed, "有对手时武装")
	module.setup_match_end(session, true)
	check(module._armed, "重复 setup 保持武装")
	module.shutdown()
	check(not module._armed, "shutdown 清武装")
	module.free()

	print("selftest_match_lifecycle_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
