extends Node
## Optional presentation-only capture entry. Does not change production settings.
var director: GameDirector
var game: Node
var output := ""

func _ready() -> void:
	output = ProjectSettings.globalize_path("res://../../tmp/devlog-navigation-media")
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func run() -> void:
	game = load("res://scenes/game_main.tscn").instantiate()
	director = game.get_node("GameDirector")
	director.random_start_location = false
	director.enable_opponent_economy = false
	director.enable_opponent_army = false
	director.show_pathing_ground = false
	director.show_ramp_debug = false
	director.show_path_debug = false
	director.view_grid_level = 0
	game.get_node("MapRoot").show_pathing_ground = false
	game.get_node("MapRoot").show_pathing_debug_grid = false
	add_child(game)
	var deadline := Time.get_ticks_msec() + 180000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not director.is_session_ready():
		push_error("Capture setup timeout")
		get_tree().quit(1)
		return
	await get_tree().create_timer(3.0).timeout
	var console := get_node_or_null("/root/Panku") as CanvasLayer
	if console:
		console.hide()
	get_tree().root.transparent_bg = false
	get_tree().root.transparent = false
	var camera := game.get_node("RtsCamera") as RtsCamera
	camera.edge_pan_enabled = false
	for unit in director.map_root.get_unit_layer().get_children():
		if unit is Node3D and CombatQuery.type_id_of(unit) == "hpea" and director._command_router.is_unit_controllable(unit):
			director.unit_selector.select_node(unit)
			camera.snap_to(unit.global_position)
			break
	await get_tree().create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.path_join("01_game_overview.png"))
	print("CAPTURE_READY ", output)
