extends Node

## 固定开局，暂停世界后测量 CPU 热路径；不代表渲染 FPS。
const SAMPLES := 120
var _interaction_portraits: Array[UnitPortraitView] = []

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
	var game := preload("res://scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.random_start_location = false
	var args := OS.get_cmdline_user_args()
	director.prepare_starting_portraits = not "--skip-portrait-warmup" in args
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
	if "--interactions" in args:
		await run_interactions(game, director)
		game.free()
		await get_tree().process_frame
		get_tree().quit()
		return
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


## Isolated CPU event benchmark: world simulation paused; deferred work still runs.
## Frame intervals include the event and four following frames, not game FPS.
func trace_interaction(label: String, callback: Callable, iteration: int) -> void:
	MatchHotpathMetrics.drain()
	MatchHotpathMetrics.enabled = true
	var pipelines_before: Dictionary = pipeline_counts()
	var stamp: int = Time.get_ticks_usec()
	callback.call()
	var synchronous_ms: float = (Time.get_ticks_usec() - stamp) / 1000.0
	var intervals: Array[float] = []
	var rendered: bool = DisplayServer.get_name() != "headless"
	var render_cpu: float = 0.0
	var render_gpu: float = 0.0
	var deadline: int = Time.get_ticks_msec() + 15000
	var frame: int = 0
	var pending: bool = false
	while frame < 4 or pending:
		await get_tree().process_frame
		frame += 1
		pending = false
		for portrait in _interaction_portraits:
			pending = pending or not portrait._pending_path.is_empty()
		if Time.get_ticks_msec() >= deadline:
			break
		if rendered:
			render_cpu = maxf(render_cpu, RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()))
			render_gpu = maxf(render_gpu, RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()))
		var now: int = Time.get_ticks_usec()
		if intervals.size() < 2048:
			intervals.append((now - stamp) / 1000.0)
		else:
			intervals[(frame - 1) % 2048] = (now - stamp) / 1000.0
		stamp = now
	var pipelines_after: Dictionary = pipeline_counts()
	for key in pipelines_after:
		pipelines_after[key] -= pipelines_before[key]
	print("INTERACTION " + JSON.stringify({"event": label, "iteration": iteration,
		"sync_ms": synchronous_ms, "frame_intervals_ms": intervals,
		"pipeline_compilations": pipelines_after, "portrait_pending": pending, "render_cpu_max_ms": render_cpu if rendered else null,
		"render_gpu_max_ms": render_gpu if rendered else null,
		"hotpaths": MatchHotpathMetrics.drain()}))
	MatchHotpathMetrics.enabled = false


func run_interactions(game: Node, director: GameDirector) -> void:
	if DisplayServer.get_name() != "headless":
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if "--live-portraits" in OS.get_cmdline_user_args():
		for node in game.find_children("*", "", true, false):
			if node is UnitPortraitView:
				node.process_mode = Node.PROCESS_MODE_ALWAYS
				_interaction_portraits.append(node)
	var home: Node3D = null
	var worker: Node3D = null
	for unit in director.map_root.get_unit_layer().get_children():
		if not unit is Node3D or not CombatQuery.is_controllable(unit, director.local_player):
			continue
		if CombatQuery.type_id_of(unit) == "htow":
			home = unit
		if CombatQuery.type_id_of(unit) == "hpea":
			worker = unit
	assert(home != null and worker != null, "Expected human starting base")
	if "--selection-probe" in OS.get_cmdline_user_args():
		if "--no-portrait" in OS.get_cmdline_user_args():
			for portrait in _interaction_portraits:
				portrait.configure(null, null)
		if "--warm-real-portrait" in OS.get_cmdline_user_args():
			var warm_start: int = Time.get_ticks_usec()
			await _interaction_portraits[0].prepare_types(PackedStringArray(["hpea", "htow", "Hamg"]), director.local_player)
			print("PORTRAIT_PREPARE_MS ", (Time.get_ticks_usec() - warm_start) / 1000.0)
		if "--warm-empty-portrait" in OS.get_cmdline_user_args():
			await trace_interaction("empty_portrait_warmup", func():
				var portrait: UnitPortraitView = _interaction_portraits[0]
				portrait._ensure_fallback_camera().current = true
				portrait._vp.render_target_update_mode = SubViewport.UPDATE_ONCE, 0)
		await trace_interaction("idle_control", func(): pass, 0)
		if "--portrait-only" in OS.get_cmdline_user_args():
			await trace_interaction("portrait_only", func(): _interaction_portraits[0].show_type("hpea", director.local_player), 0)
		else:
			await trace_interaction("first_selection", func(): director.unit_selector.call("select_node", worker), 0)
		if "--probe-all-starting" in OS.get_cmdline_user_args():
			await trace_interaction("first_home", func(): director.unit_selector.call("select_node", home), 0)
			for unit: Node in director.map_root.get_unit_layer().get_children():
				if CombatQuery.type_id_of(unit) == "Hamg" and CombatQuery.is_controllable(unit, director.local_player):
					await trace_interaction("first_hero", func(): director.unit_selector.call("select_node", unit), 0)
					break
		await trace_interaction("settled", func(): pass, 0)
		print("SELECTION_PROBE PASS")
		return
	var position: Vector2 = Wc3Coords.godot_to_wc3_xy(home.global_position)
	var stock: PlayerStock = director.get_session().local_stock()
	stock.set_all(100000, 100000, 0, 100)
	director._ensure_production_module()
	for iteration in range(6):
		await trace_interaction("select_worker", func(): director.unit_selector.call("select_node", worker), iteration)
		await trace_interaction("select_home", func(): director.unit_selector.call("select_node", home), iteration)
		await trace_interaction("train_enqueue", func(): director._production_panel.request_train("hpea"), iteration)
		var queue: TrainQueue = home.get_node_or_null("TrainQueue") as TrainQueue
		assert(queue != null and queue.queue_count() == 1, "Training request failed")
		director._production.cancel(home, 0, director.local_player)
		for frame in range(2):
			await get_tree().process_frame
		var spawned: Array[Node3D] = []
		await trace_interaction("unit_spawn", func():
			spawned.append(director._ensure_units_module().spawn_trained("hpea", position, director.local_player, home)), iteration)
		assert(spawned[0] != null)
		director.map_root.remove_unit_instance(int(spawned[0].get_meta("unit_data").get("creationNumber")))
		await get_tree().process_frame
		var order: BuildOrder = BuildOrder.new()
		order.building_id = "hhou"
		order.site_wc3 = position + Vector2(768, 0)
		order.owner = director.local_player
		await trace_interaction("construction_start", func(): director._ensure_build_module().on_construction_started(order), iteration)
		director._ensure_build_module().on_construction_cancelled(order)
		for frame in range(4):
			await get_tree().process_frame
	print("INTERACTIONS PASS " + JSON.stringify({"headless": DisplayServer.get_name() == "headless",
		"world_paused": game.process_mode == Node.PROCESS_MODE_DISABLED,
		"units": director.map_root.get_unit_layer().get_child_count()}))


func pipeline_counts() -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {}
	return {
		"canvas": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_CANVAS),
		"mesh": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH),
		"surface": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE),
		"draw": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW),
		"specialization": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION),
	}
