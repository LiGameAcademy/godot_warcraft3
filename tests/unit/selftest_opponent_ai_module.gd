extends Node

## OpponentAiModule 契约：无 session/库存时 setup 返回 null；observe 不崩。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("OPPONENT AI: " + label)


func _ready() -> void:
	var host := Node.new()
	host.name = "Host"
	add_child(host)
	var module := OpponentAiModule.new()
	add_child(module)

	module.configure({
		"host_parent": host,
		"map_root": null,
		"session": null,
	})
	check(module.setup(0, false) == null, "无 session 时 setup 返回 null")

	var session := GameSession.from_melee_bootstrap("", 0, "human", 5)
	# 仅本地库存，对手 owner=1 不存在
	module.configure({
		"host_parent": host,
		"session": session,
		"map_root": null,
	})
	check(module.setup(0, false) == null, "无对手库存时 setup 返回 null")

	var enemies := module.observe_enemies(0)
	check(enemies.is_empty(), "无地图时 observe 为空")
	module.shutdown()
	check(true, "shutdown 可调用")
	module.free()

	print("selftest_opponent_ai_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
