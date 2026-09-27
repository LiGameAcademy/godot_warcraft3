extends Node
## Render the real match in an offscreen viewport; no interaction with the user's game.
var checks := 0
var failures := 0
var director: GameDirector

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	get_window().mode = Window.MODE_MINIMIZED
	call_deferred("run")

func run() -> void:
	var output := ProjectSettings.globalize_path("res://../../tmp/camera-review")
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
	check(director.is_session_ready(), "real match becomes ready")
	if not director.is_session_ready():
		get_tree().quit(1)
		return
	check(rig._heightfield == director._heightfield and rig._heightfield != null, "map heightfield injected before startup focus")
	check(is_equal_approx(rig.get_camera().fov, 50.0), "director preserves trial FOV")
	var start := rig.get_look_at()
	# Let the initial loading overlay and presentation settle.
	await get_tree().create_timer(1.0).timeout
	game.process_mode = Node.PROCESS_MODE_DISABLED
	# Reconstruct the previous rig settings at the identical XZ target.
	rig.terrain_follow_enabled = false
	rig.camera_fov = 70.0
	rig.apply_export_tuning()
	rig.global_position = Vector3(start.x, 0, start.z)
	await capture(viewport, output.path_join("before.png"))
	rig.terrain_follow_enabled = true
	rig.camera_fov = 50.0
	rig.apply_export_tuning()
	rig.snap_to(start)
	await capture(viewport, output.path_join("after.png"))
	# Check the minimap click path, including Y, with the actual map.
	director._on_minimap_clicked(Vector2(0.5, 0.5))
	check(rig._focus_tween == null, "minimap click completes immediately")
	check(rig.get_look_at().y > 0.0, "minimap focus uses real terrain")
	print("camera_comparison: %s (%d checks); images: %s" % ["PASS" if failures == 0 else "FAIL", checks, output])
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failures == 0 else 1)

func capture(viewport: SubViewport, path: String) -> void:
	# Simulation is frozen for a fair comparison; camera-projected overlays still need refresh.
	director.health_bar_manager._process(0.0)
	director.game_hud._minimap_dock.minimap._process(0.0)
	await get_tree().process_frame
	RenderingServer.force_draw(false)
	var image := viewport.get_texture().get_image()
	check(image != null and not image.is_empty(), "rendered viewport has an image")
	if image != null and not image.is_empty():
		check(image.save_png(path) == OK, "capture saved")
