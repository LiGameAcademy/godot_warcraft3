extends "res://tests/media/navigation_capture.gd"
## Identical presentation/probe harness for Git baseline and current working tree.
var variant := "CURRENT"
var result_dir := ""
var last_command_ms := 0.0
var peak_frame_ms := 0.0
var sample_frames := false
var previous_tick := 0
var running := false
var ready_to_record := false
var banner: Label
var clock_label: Label
var scenario_origin := Vector2.ZERO
var scenario_goal := Vector2.ZERO
var selected: Array = []

func run() -> void:
	seed(240924)
	var args := OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--variant": variant = args[i + 1]
		if args[i] == "--result-dir": result_dir = args[i + 1]
	await super.run()
	if result_dir.is_empty(): result_dir = output.path_join("comparison")
	DirAccess.make_dir_recursive_absolute(result_dir)
	DisplayServer.window_set_title("Navigation comparison - " + variant)
	var movers: Array = director._command_router.filter_movers(director._command_router.filter_controllable(director.map_root.get_unit_layer().get_children()))
	selected = movers.slice(0, 1)
	var unit: Node3D = selected[0]
	scenario_origin = Vector2(unit.global_position.x, -unit.global_position.z) / Wc3Coords.WORLD_SCALE
	scenario_goal = scenario_origin + Vector2(0, 1024)
	director.unit_selector._set_selection(selected)
	_setup_overlay()
	await _setup_monitor()
	await get_tree().create_timer(2).timeout
	ready_to_record = true
	banner.text = variant + " | 固定命令回放：1 单位 / 同一不可达目标\nF6 开始 · 原速录制 · 命令耗时不含鼠标拾取"
	print("COMPARISON_READY ", variant, " origin=", scenario_origin, " goal=", scenario_goal)

func _setup_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	add_child(layer)
	banner = Label.new()
	banner.position = Vector2(450, 52)
	banner.add_theme_font_size_override("font_size", 20)
	banner.add_theme_color_override("font_shadow_color", Color.BLACK)
	banner.add_theme_constant_override("shadow_outline_size", 6)
	layer.add_child(banner)
	clock_label = Label.new()
	clock_label.position = Vector2(450, 108)
	clock_label.add_theme_font_size_override("font_size", 20)
	clock_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	clock_label.add_theme_constant_override("shadow_outline_size", 6)
	layer.add_child(clock_label)

func _setup_monitor() -> void:
	var panku = get_node("/root/Panku")
	panku.show()
	panku.gd_exprenv.register_env("demo", self)
	var logger = panku.module_manager.get_module("native_logger")
	logger.output_overlay_display_mode = 2
	logger.output_overlay.hide()
	var monitor = panku.module_manager.get_module("expression_monitor")
	monitor.monitor.monitor_groups_ui.load_persistent_data([{
		"group_name": "CPU + 本次命令（ms）",
		"expressions": ["snapped(perf.process_ms(), 0.01)", "snapped(perf.physics_ms(), 0.01)", "perf.fps()", "demo.command_ms()", "demo.frame_peak_ms()"]
	}])
	await get_tree().process_frame
	for group in monitor.monitor.monitor_groups_ui.groups_container.get_children():
		group.group_toggle_button.button_pressed = true
		group.state_control_button.button.button_pressed = true
	monitor.monitor_window.position = Vector2(8, 48)
	monitor.monitor_window.size = Vector2(424, 420)
	monitor.open_window()

func command_ms() -> String:
	return "%.2f ms（命令返回）" % last_command_ms

func frame_peak_ms() -> String:
	return "%.2f ms（回放窗口峰值）" % peak_frame_ms

func _process(_delta: float) -> void:
	var tick := Time.get_ticks_usec()
	if sample_frames and previous_tick > 0:
		peak_frame_ms = maxf(peak_frame_ms, float(tick - previous_tick) / 1000.0)
	previous_tick = tick
	if is_instance_valid(clock_label):
		clock_label.text = "运行时钟：%.2f s" % (tick / 1000000.0)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F6 and ready_to_record and not running:
		running = true
		get_viewport().set_input_as_handled()
		_replay()

func _replay() -> void:
	for seconds in [3, 2, 1]:
		banner.text = variant + " | 同一不可达目标 · %d 秒后下达移动命令" % seconds
		await get_tree().create_timer(1).timeout
	banner.text = variant + " | 正在下达移动命令…"
	await RenderingServer.frame_post_draw
	peak_frame_ms = 0
	sample_frames = true
	previous_tick = Time.get_ticks_usec()
	var started := Time.get_ticks_usec()
	var result: Dictionary = director._command_router.issue_move_to_wc3(selected, scenario_goal)
	last_command_ms = float(Time.get_ticks_usec() - started) / 1000.0
	banner.text = variant + " | 命令已返回：成功 %d / 失败 %d\n同一不可达目标 · 完整保留等待时间" % [result.moved, result.failed]
	await get_tree().create_timer(2).timeout
	sample_frames = false
	var record := {"variant": variant, "origin": [scenario_origin.x, scenario_origin.y], "goal": [scenario_goal.x, scenario_goal.y], "count": selected.size(), "command_ms": last_command_ms, "peak_frame_ms": peak_frame_ms, "moved": result.moved, "failed": result.failed, "engine": Engine.get_version_info().string}
	FileAccess.open(result_dir.path_join(variant + ".json"), FileAccess.WRITE).store_string(JSON.stringify(record, "\t"))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(result_dir.path_join(variant + ".png"))
	print("COMPARISON_RESULT ", JSON.stringify(record))
