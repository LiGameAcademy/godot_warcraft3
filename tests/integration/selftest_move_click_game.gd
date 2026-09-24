extends Node

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var game: Node = load("res://scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.random_start_location = false
	director.enable_opponent_economy = false
	director.enable_opponent_army = false
	add_child(game)
	var deadline := Time.get_ticks_msec() + 180000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not director.is_session_ready():
		push_error("move click loading timeout")
		get_tree().quit(1)
		return
	for i in range(10):
		await get_tree().process_frame
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var router: CommandRouter = director._command_router
	var movers := router.filter_movers(router.filter_controllable(director.map_root.get_unit_layer().get_children()))
	if movers.is_empty():
		push_error("move click has no controllable units")
		get_tree().quit(1)
		return
	var unit: Node3D = movers[0]
	var origin := Vector2(unit.global_position.x, -unit.global_position.z) / Wc3Coords.WORLD_SCALE
	var failures := 0
	MatchHotpathMetrics.enabled = true
	for count in [1, movers.size()]:
		var selected := movers.slice(0, count)
		for offset: Vector2 in [Vector2(512, 0), Vector2(0, 1024), Vector2(1800, 1800), Vector2(-2400, -2400)]:
			router.issue_stop(selected)
			var started := Time.get_ticks_usec()
			var result := router.issue_move_to_wc3(selected, origin + offset)
			var elapsed := (Time.get_ticks_usec() - started) / 1000.0
			print("EI_CLICK count=%d offset=%s ms=%.3f moved=%d failed=%d" % [count, offset, elapsed, result.moved, result.failed])
			if result.moved + result.failed != count:
				failures += 1
			router.issue_stop(selected)
			for moving_unit in selected:
				var nav := moving_unit.get_node_or_null("UnitNavigator") as UnitNavigator
				if nav != null and nav.is_moving():
					failures += 1
	print("EI_CLICK_METRICS ", JSON.stringify(MatchHotpathMetrics.drain()))
	MatchHotpathMetrics.enabled = false
	game.queue_free()
	for i in range(4):
		await get_tree().process_frame
	print("selftest_move_click_game: ", "PASS" if failures == 0 else "FAIL")
	get_tree().quit(0 if failures == 0 else 1)
