extends Node

## 固定开局，暂停世界后测量 CPU 热路径；不代表渲染 FPS。
const SAMPLES := 120

func _ready() -> void:
	call_deferred("run")

func measure(label: String, callback: Callable) -> Dictionary:
	for i in range(5):
		callback.call()
	var samples: Array[float] = []
	for i in range(SAMPLES):
		var start := Time.get_ticks_usec()
		callback.call()
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	var total := 0.0
	for value in samples:
		total += value
	return {"name": label, "mean_ms": total / samples.size(), "p95_ms": samples[int(samples.size() * 0.95)]}

func run() -> void:
	var game := preload("res://game/scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.random_start_location = false
	var soak := "--soak" in OS.get_cmdline_user_args()
	director.enable_opponent_economy = soak
	director.enable_opponent_army = soak
	add_child(game)
	var deadline := Time.get_ticks_msec() + 180000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not director.is_session_ready():
		push_error("benchmark: loading timeout")
		get_tree().quit(1)
		return
	for i in range(20):
		await get_tree().process_frame
	if soak:
		var elapsed := Time.get_ticks_usec()
		for frame in range(7200):
			await get_tree().process_frame
			if (frame + 1) % 600 == 0:
				var now := Time.get_ticks_usec()
				print("MATCH_SOAK " + JSON.stringify({"simulation_seconds": (frame + 1) / 60.0,
					"mean_wall_ms": float(now - elapsed) / 600000.0,
					"units": director.map_root.get_unit_layer().get_child_count(),
					"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
					"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
					"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
					"memory_mb": OS.get_static_memory_usage() / 1048576.0}))
				elapsed = now
		game.free()
		await get_tree().process_frame
		get_tree().quit()
		return
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var host := director.map_root.get_unit_layer()
	var selected: Node3D
	for unit in host.get_children():
		if unit is Node3D and CombatQuery.type_id_of(unit) == "Hamg":
			selected = unit
			break
	if selected == null:
		push_error("benchmark: expected development archmage")
		get_tree().quit(1)
		return
	director.unit_selector.call("select_node", selected)
	var selection := director._ensure_selection_hud_module()
	var bars := game.get_node("HealthBarManager") as HealthBarManager
	var crowd: UnitCrowdQuery = director._crowd_query
	var results: Array = []
	results.append(measure("selected_hud_tick", func(): selection.tick(1.0 / 60.0)))
	results.append(measure("health_bars_frame", func(): bars._process(1.0 / 60.0)))
	results.append(measure("health_bars_resync", func(): bars.resync()))
	results.append(measure("crowd_query_all_units", func():
		for unit in host.get_children():
			if unit is Node3D:
				crowd.neighbors_of(unit, Wc3Coords.godot_to_wc3_xy(unit.global_position))
	))
	print("MATCH_HOTPATHS " + JSON.stringify({"units": host.get_child_count(), "samples": SAMPLES,
		"renderer": RenderingServer.get_current_rendering_method(), "results": results}))
	game.free()
	await get_tree().process_frame
	get_tree().quit()
