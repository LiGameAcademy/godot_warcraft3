extends Node

## MatchBootstrapModule 契约：空 map 时仍能创建会话；shutdown 不崩。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MATCH BOOTSTRAP: " + label)


func _ready() -> void:
	var module := MatchBootstrapModule.new()
	add_child(module)
	var hud := _FakeHud.new()
	add_child(hud)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	module.configure({
		"map_dir": "",
		"game_hud": hud,
		"rng": rng,
		"apply_cursor_race": func(_r: String) -> void: pass,
		"refresh_pathing": func() -> void: pass,
		"map_display_name": func() -> String: return "test-map",
	})
	var result := module.bootstrap_melee({
		"preview_race": "human",
		"local_player": 0,
		"random_start_location": true,
		"spawn_melee_base": false,
		"spawn_opponent_base": false,
	})
	var session := result.get("session") as GameSession
	check(session != null, "bootstrap 返回 session")
	check(session != null and session.local_player == 0, "local_player=0")
	check(session != null and session.stocks.has(0), "本地库存已注册")
	check(hud.last_status.contains("无 sloc") or hud.bind_count == 1, "HUD 已绑定或状态提示")
	check(module.spawn_opponent_base(session, [], {}, 0) == false, "无 sloc 时对手基地失败")
	module.shutdown()
	check(true, "shutdown 可调用")
	module.free()

	print("selftest_match_bootstrap_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


class _FakeHud extends Node:
	var bind_count: int = 0
	var last_status: String = ""

	func bind_stock(_stock) -> void:
		bind_count += 1

	func set_status(text: String) -> void:
		last_status = text
