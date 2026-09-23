extends Node

## 固定开局，暂停世界后测量 CPU 热路径；不代表渲染 FPS。
const SAMPLES := 120

func _ready() -> void:
	call_deferred("run")

func measure(label: String, callback: Callable, sample_count: int = SAMPLES) -> Dictionary:
	for i in range(5):
		callback.call()
	var samples: Array[float] = []
	for i in range(sample_count):
		var start := Time.get_ticks_usec()
		callback.call()
		samples.append(float(Time.get_ticks_usec() - start) / 1000.0)
	samples.sort()
	var total := 0.0
	for value in samples:
		total += value
	return {"name": label, "mean_ms": total / samples.size(), "p95_ms": samples[int(samples.size() * 0.95)]}

func run() -> void:
	if "--scale" in OS.get_cmdline_user_args():
		run_scale()
		return
	var game := preload("res://game/scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.random_start_location = false
	var args := OS.get_cmdline_user_args()
	var soak := "--soak" in args
	var realtime := "--realtime" in args
	var fixed := "--fixed-units" in args
	var duration := 120.0
	for arg in args:
		if arg.begins_with("--seconds="):
			duration = float(arg.trim_prefix("--seconds="))
	director.enable_opponent_economy = soak and not fixed
	director.enable_opponent_army = soak and not fixed
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
		MatchHotpathMetrics.enabled = true
		var frames: Array[float] = []
		var previous := Time.get_ticks_usec()
		var elapsed := Time.get_ticks_usec()
		var begun := elapsed
		var simulated := 0.0
		var frame := 0
		var window_frames := 0
		var viewport_rid := get_viewport().get_viewport_rid()
		var rendered := DisplayServer.get_name() != "headless"
		var capture_pending := rendered and "--capture" in args
		if rendered:
			RenderingServer.viewport_set_measure_render_time(viewport_rid, true)
		var camera := game.get_node("RtsCamera") as Node3D
		var camera_start := camera.position
		if "--camera-route" in args:
			# Anchor the route to the fixed spawn, independent of bootstrap camera tween timing.
			for unit in director.map_root.get_unit_layer().get_children():
				if unit is Node3D and CombatQuery.type_id_of(unit) == "Hamg":
					camera_start = unit.global_position
					director.unit_selector.call("select_node", unit)
					break
			camera.set_process(false)
		while (Time.get_ticks_usec() - begun) / 1000000.0 < duration if realtime else frame < int(duration * 60.0):
			await get_tree().process_frame
			if capture_pending and simulated >= 20.0:
				get_viewport().get_texture().get_image().save_png("res://tmp/round2-render.png")
				capture_pending = false
			frame += 1
			simulated += get_process_delta_time()
			if "--camera-route" in args:
				camera.position = camera_start + Vector3(sin(simulated * 0.1) * 12.0, 0.0, sin(simulated * 0.05) * 12.0)
			var stamp := Time.get_ticks_usec()
			if frames.size() < 2048:
				frames.append((stamp - previous) / 1000.0)
			else:
				frames[window_frames % 2048] = (stamp - previous) / 1000.0
			window_frames += 1
			previous = stamp
			if (Time.get_ticks_usec() - elapsed >= 10000000) if realtime else frame % 600 == 0:
				var now := Time.get_ticks_usec()
				frames.sort()
				print("MATCH_SOAK " + JSON.stringify({"simulation_seconds": simulated,
					"wall_seconds": (now - begun) / 1000000.0,
					"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid) if rendered else null,
					"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid) if rendered else null,
					"match_finished": not director._session.get_match_result().is_empty(),
					"frame_p95_ms": frames[int(frames.size() * 0.95)],
					"hotpaths": MatchHotpathMetrics.drain(),
					"mean_wall_ms": float(now - elapsed) / (window_frames * 1000.0),
					"units": director.map_root.get_unit_layer().get_child_count(),
					"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
					"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
					"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
					"memory_mb": OS.get_static_memory_usage() / 1048576.0}))
				frames.clear()
				window_frames = 0
				elapsed = now
		print("MATCH_SOAK_DONE " + JSON.stringify({"wall_seconds": (Time.get_ticks_usec() - begun) / 1000000.0, "simulation_seconds": simulated, "frames": frame}))
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
	if "--acquire-compare" in args:
		for repeat in range(3):
			results.append(measure("acquire_reference_%d" % repeat, func():
				for unit in host.get_children():
					if unit is Node3D:
						reference_acquire(unit, host)
			))
			results.append(measure("acquire_optimized_%d" % repeat, func():
				for unit in host.get_children():
					if unit is Node3D:
						CombatQuery.find_acquire_target(unit, host)
			))
		for unit in host.get_children():
			if unit is Node3D:
				assert(reference_acquire(unit, host) == CombatQuery.find_acquire_target(unit, host))
	var reservation := PathCellReservation.new()
	for owner in range(1, 301):
		reservation.set_owner_cells(owner, [Vector2i(owner, 0), Vector2i(owner, 1)])
	results.append(measure("reservation_300", func():
		for owner in range(1, 301):
			reservation.set_owner_cells(owner, [Vector2i(owner, 0), Vector2i(owner, 1)])
	))
	var draw := PathDebugDraw.new()
	add_child(draw)
	draw.setup(null)
	results.append(measure("path_draw_empty", func(): draw.redraw([])))
	results.append(measure("command_card_refresh", func(): director._ensure_command_card_module().refresh()))
	draw.free()
	print("MATCH_HOTPATHS " + JSON.stringify({"units": host.get_child_count(), "samples": SAMPLES,
		"renderer": RenderingServer.get_current_rendering_method(), "results": results}))
	game.free()
	await get_tree().process_frame
	get_tree().quit()


## Pre-optimization algorithm retained only as a benchmark oracle.
func reference_acquire(attacker: Node3D, host: Node) -> Node3D:
	var best: Node3D
	var best_distance := CombatQuery.acquire_range_wc3(attacker)
	for candidate in host.get_children():
		if not candidate is Node3D or not CombatQuery.is_auto_acquire_target(attacker, candidate):
			continue
		var distance := CombatQuery.weapon_distance_wc3(attacker, candidate)
		if distance <= best_distance:
			best_distance = distance
			best = candidate
	return best


func run_scale() -> void:
	var results: Array = []
	for count in [100, 300, 600]:
		var host := Node3D.new()
		add_child(host)
		for i in range(count):
			var unit := Node3D.new()
			unit.set_meta("unit_data", {"typeId": "hfoo"})
			host.add_child(unit)
			unit.position = Wc3Coords.wc3_xy_to_godot((i % 30) * 256, floori(i / 30.0) * 256, 0)
		var crowd := UnitCrowdQuery.new()
		crowd.configure(host, null)
		results.append(measure("crowd_%d" % count, func():
			for unit in host.get_children():
				crowd.neighbors_of(unit, Wc3Coords.godot_to_wc3_xy(unit.global_position))
		, 20))
		host.free()
	print("MATCH_SCALE " + JSON.stringify(results))
	get_tree().quit()
