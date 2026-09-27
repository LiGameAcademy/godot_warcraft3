extends "res://tests/media/camera_comparison.gd"
const PickVolume := preload("res://client/selection/unit_pick_volume.gd")

func run() -> void:
	var output := ProjectSettings.globalize_path("res://../../tmp/selection-review")
	DirAccess.make_dir_recursive_absolute(output)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var game: Node = load("res://scenes/game_main.tscn").instantiate()
	director = game.get_node("GameDirector") as GameDirector
	director.random_start_location = false
	director.enable_opponent_economy = false
	director.enable_opponent_army = false
	director.show_pathing_ground = false
	director.view_grid_level = 0
	director.prepare_starting_portraits = false
	var rig := game.get_node("RtsCamera") as RtsCamera
	rig.edge_pan_enabled = false
	rig.arrow_pan_enabled = false
	viewport.add_child(game)
	var deadline := Time.get_ticks_msec() + 120000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(director.is_session_ready(), "real match ready")
	if not director.is_session_ready():
		get_tree().quit(1)
		return
	var hall: Node3D
	var worker: Node3D
	for node in director.map_root.get_unit_layer().get_children():
		if not node is Node3D or not director._command_router.is_unit_controllable(node):
			continue
		if CombatQuery.type_id_of(node) == "htow":
			hall = node
		if CombatQuery.type_id_of(node) == "hpea":
			worker = node
	check(hall != null and worker != null, "real starting units available")
	if hall == null or worker == null:
		get_tree().quit(1)
		return
	await get_tree().create_timer(1.0).timeout
	game.process_mode = Node.PROCESS_MODE_DISABLED
	rig.snap_to(hall.global_position)
	var selector := director.unit_selector as UnitSelector
	var model := hall.get_node("Model") as Node3D
	var bounds := PickVolume.model_bounds(model)
	var roof := bounds.get_center()
	roof.y = bounds.position.y + bounds.size.y * 0.7
	var screen := rig.get_camera().unproject_position(model.global_transform * roof)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = screen
	press.pressed = true
	var pick_start := Time.get_ticks_usec()
	check(selector.pick_at(screen) == hall, "cold real model query finds roof")
	print("Cold body query: %.2f ms" % ((Time.get_ticks_usec() - pick_start) / 1000.0))
	MatchHotpathMetrics.enabled = true
	var notifications := [0]
	selector.selection_changed.connect(func(_p: Node3D, _s: Array) -> void: notifications[0] += 1)
	var started := Time.get_ticks_usec()
	game.process_mode = Node.PROCESS_MODE_INHERIT
	viewport.push_input(press, true)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0
	check(selector.get_primary() == hall, "real Town Hall upper-body press selects immediately")
	print("Town Hall press callback time including HUD: %.2f ms; foot distance: %.1f px" % [elapsed_ms, selector.screen_foot_distance(hall, screen)])
	print("Selection metrics: ", MatchHotpathMetrics.drain())
	MatchHotpathMetrics.enabled = false
	press.pressed = false
	game.process_mode = Node.PROCESS_MODE_INHERIT
	viewport.push_input(press, true)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	check(notifications[0] == 1, "real viewport press/release emits exactly one selection")
	var repeat_start := Time.get_ticks_usec()
	game.process_mode = Node.PROCESS_MODE_INHERIT
	for i in range(20):
		press.pressed = true
		viewport.push_input(press, true)
		press.pressed = false
		viewport.push_input(press, true)
	game.process_mode = Node.PROCESS_MODE_DISABLED
	print("Repeated clicks (20) mean callback: %.2f ms" % ((Time.get_ticks_usec() - repeat_start) / 20000.0))
	check(notifications[0] == 1, "repeated real clicks do not rebuild HUD")
	await capture(viewport, output.path_join("building_selected.png"))
	await verify_overlap(viewport, game, rig, hall, worker, output)
	# Use a real ramp in Echo Isles to reproduce terrain cutting through the ring.
	var ramp := nearest_ramp(director._heightfield, hall.global_position)
	check(ramp != Vector3.INF, "real terrain slope found")
	if ramp != Vector3.INF:
		worker.global_position = ramp
		rig.snap_to(ramp)
		selector.select_node(worker)
		var ring := worker.get_node("SelectionRing") as SelectionRing
		ring._process(0.0)
		var material := ring.material_override as StandardMaterial3D
		material.no_depth_test = false
		await capture(viewport, output.path_join("slope_depth_test.png"))
		material.no_depth_test = true
		await capture(viewport, output.path_join("slope_selected.png"))
	# Input handler must no longer compete with the central router in the real scene.
	check(not selector.is_processing_input(), "real match owns input routing once")
	check(not selector._hud_blocks_screen(Vector2(400, 1030)), "real HUD leaves bottom gap clickable")
	check(selector._hud_blocks_screen(Vector2(1800, 1000)), "real command panel remains protected")
	game.queue_free()
	await get_tree().process_frame
	print("selection_review: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

func verify_overlap(viewport: SubViewport, game: Node, rig: RtsCamera, hall: Node3D, worker: Node3D, output: String) -> void:
	# Independent oracle: the GPU renders object IDs using the real animated meshes.
	# Compare these pixels with CPU picking, including places where old AABBs disagree.
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode unshaded, fog_disabled, cull_disabled; uniform vec3 id_color; uniform sampler2D alpha_tex; uniform bool has_alpha = false; uniform float alpha_value = 1.0; uniform float cutoff = 0.0; void fragment() { if (has_alpha && texture(alpha_tex, UV).a * alpha_value < cutoff) { discard; } ALBEDO = id_color; }"
	var saved: Array = []
	for target in [hall, worker]:
		var meshes: Array[MeshInstance3D] = []
		PickVolume._collect_meshes(target.get_node("Model"), meshes)
		for mesh in meshes:
			for surface in range(mesh.mesh.get_surface_count()):
				var original := mesh.get_active_material(surface)
				var mat := ShaderMaterial.new()
				mat.shader = shader
				mat.set_shader_parameter("id_color", Vector3(1, 0, 1) if target == hall else Vector3(0, 1, 1))
				if original is BaseMaterial3D and original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					mat.set_shader_parameter("has_alpha", original.albedo_texture != null)
					mat.set_shader_parameter("alpha_tex", original.albedo_texture)
					mat.set_shader_parameter("alpha_value", original.albedo_color.a)
					mat.set_shader_parameter("cutoff", original.alpha_scissor_threshold if original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.1)
				saved.append([mesh, surface, mesh.get_surface_override_material(surface), mat])
	var initial := worker.global_position
	var model := hall.get_node("Model") as Node3D
	var box := PickVolume.model_bounds(model)
	var world_box := model.global_transform * box
	var visible_checks := 0
	var old_wrong := 0
	var mismatches := 0
	var proof_screen := Vector2.INF
	var proof_position := initial
	var fixture := 0
	for offset in [Vector3.INF, Vector3(-0.4, 0, 0.35), Vector3(0.4, 0, 0.35), Vector3(-0.3, 0, -0.35), Vector3(0.3, 0, -0.35)]:
		worker.global_position = initial if offset == Vector3.INF else hall.global_position + offset * world_box.size
		for record in saved:
			record[0].set_surface_override_material(record[1], record[3])
		await get_tree().process_frame
		RenderingServer.force_draw(false)
		var ids := viewport.get_texture().get_image()
		ids.save_png(output.path_join("overlap_ids_%d.png" % fixture))
		fixture += 1
		for record in saved:
			record[0].set_surface_override_material(record[1], record[2])
		var foot := rig.get_camera().unproject_position(worker.global_position)
		for y in range(maxi(50, int(foot.y) - 90), mini(860, int(foot.y) + 20), 2):
			for x in range(maxi(0, int(foot.x) - 65), mini(1920, int(foot.x) + 65), 2):
				var color := ids.get_pixel(x, y)
				var expected: Node3D = worker if color.g > 0.8 and color.r < 0.05 and color.b > 0.8 else (hall if color.r > 0.8 and color.g < 0.05 and color.b > 0.8 else null)
				if expected == null:
					continue
				# Interior pixels only: avoid MSAA and subpixel edge ambiguity.
				if not interior_id(ids, x, y, color):
					continue
				var screen := Vector2(x + 0.5, y + 0.5)
				var actual: Node3D = director.unit_selector.pick_at(screen)
				visible_checks += 1
				if actual != expected:
					mismatches += 1
					if mismatches < 12:
						var debug_origin := rig.get_camera().project_ray_origin(screen)
						var debug_dir := rig.get_camera().project_ray_normal(screen)
						print("Mismatch fixture=", fixture, " screen=", screen, " expected=", CombatQuery.type_id_of(expected), " actual=", CombatQuery.type_id_of(actual) if actual != null else "null", " hall_distance=", PickVolume.ray_distance(hall, debug_origin, debug_dir), " worker_distance=", PickVolume.ray_distance(worker, debug_origin, debug_dir))
				if expected != worker:
					continue
				var origin := rig.get_camera().project_ray_origin(screen)
				var direction := rig.get_camera().project_ray_normal(screen)
				var inverse := model.global_transform.affine_inverse()
				var old_hit: Variant = box.intersects_ray(inverse * origin, inverse.basis * direction)
				if old_hit is Vector3 and (model.global_transform * old_hit - origin).dot(direction) < PickVolume.ray_distance(worker, origin, direction):
					old_wrong += 1
					if actual == worker:
						proof_screen = screen
						proof_position = worker.global_position
	print("Overlap GPU oracle: %d interior pixels, %d disagreements, %d old AABB false occlusions" % [visible_checks, mismatches, old_wrong])
	check(visible_checks > 50 and old_wrong > 0, "real model regression covers visible peasants behind Town Hall bounds")
	check(mismatches == 0, "real model selection matches GPU-visible unit pixels")
	if proof_screen != Vector2.INF:
		worker.global_position = proof_position
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.position = proof_screen
		press.pressed = true
		game.process_mode = Node.PROCESS_MODE_INHERIT
		viewport.push_input(press, true)
		press.pressed = false
		viewport.push_input(press, true)
		game.process_mode = Node.PROCESS_MODE_DISABLED
		check(director.unit_selector.get_primary() == worker, "real viewport selects exposed peasant instead of Town Hall")
		print("Peasant overlap click: ", proof_screen)
		var query_ms := 0.0
		for i in range(10):
			await get_tree().process_frame
			var query_start := Time.get_ticks_usec()
			director.unit_selector.pick_at(proof_screen)
			query_ms += (Time.get_ticks_usec() - query_start) / 1000.0
		print("Peasant query across 10 frames (pose cache refresh): %.2f ms mean" % (query_ms / 10.0))
		await capture(viewport, output.path_join("peasant_overlap_selected.png"))
	worker.global_position = initial

func interior_id(image: Image, x: int, y: int, color: Color) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if not image.get_pixel(x + dx, y + dy).is_equal_approx(color):
				return false
	return true

func nearest_ramp(hf: Wc3Heightfield, origin: Vector3) -> Vector3:
	var best := Vector3.INF
	var distance := INF
	for y in range(1, hf.height - 2):
		for x in range(1, hf.width - 2):
			var i := y * hf.width + x
			# Both sculpted slopes and authored ramps are valid depth-occlusion cases.
			var slope := maxf(absf(float(hf.heights[i + 1]) - float(hf.heights[i])), absf(float(hf.heights[i + hf.width]) - float(hf.heights[i])))
			if slope < 128.0 or slope > 192.0:
				continue
			var xy := hf.center_offset + (Vector2(x, y) + Vector2(0.5, 0.5)) * hf.tile_size
			var p := Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, hf.interpolated_height(xy.x, xy.y))
			if p.distance_squared_to(origin) < distance:
				distance = p.distance_squared_to(origin)
				best = p
	return best
