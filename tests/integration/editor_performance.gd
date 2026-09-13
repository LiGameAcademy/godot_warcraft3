extends Node
## Fixed workload, real renderer. Writes evidence; does not hide failed targets.
const EditorScene := preload("res://editor/scenes/editor_main.tscn")
const Document := preload("res://editor/scripts/map_document.gd")
var results: Array = []


func _ready() -> void:
	get_tree().create_timer(180).timeout.connect(func():
		push_error("editor performance timeout")
		get_tree().quit(1)
	)
	call_deferred("_run")


func _run() -> void:
	get_window().size = Vector2i(1280, 720)
	var scene := EditorScene.instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	for window in editor._tool_palettes:
		window.hide()
	if editor._inspect_window != null:
		editor._inspect_window.hide()
	# No global input can change the deterministic workload while timing it.
	for node in [editor.brush, editor.doodad_brush, editor.unit_brush, editor.input_router]:
		node.process_mode = Node.PROCESS_MODE_DISABLED
	for config in [Vector2i(64, 100), Vector2i(256, 1000)]:
		var doc = editor.get_document()
		doc.create_from_options({"width": config.x, "height": config.x, "main_tileset": "L",
			"ground_tilesets": ["Ldrt", "Lgrs"], "cliff_tilesets": ["CLdi", "CLgr"], "random_height": false})
		# Four trees to one peasant, evenly spaced in a central 20-column grid.
		for i in range(config.y):
			var x: float = (i % 20 - 10) * 96.0
			var y: float = (i / 20 - config.y / 40) * 96.0
			if i % 5 == 0:
				doc.add_unit(doc.make_unit_entry("hpea", x, y, i % 4, 270))
			else:
				doc.add_doodad(doc.make_doodad_entry("LTlt", x, y, i % 4))
		if "--reuse-fixtures" in OS.get_cmdline_user_args():
			if doc.load_json("res://tmp/editor-benchmark-%d.wc3map.json" % config.x) != OK:
				push_error(doc.last_file_error)
				get_tree().quit(1)
				return
		var start := Time.get_ticks_usec()
		await editor._apply_document(true)
		while editor.map_root.is_units_batch_loading():
			await get_tree().process_frame
		var build_ms := (Time.get_ticks_usec() - start) / 1000.0
		var path := "res://tmp/editor-benchmark-%d.wc3map.json" % config.x
		start = Time.get_ticks_usec()
		var save_error: int = doc.save_json(path)
		var save_ms := (Time.get_ticks_usec() - start) / 1000.0
		var reloaded = Document.new()
		start = Time.get_ticks_usec()
		var load_error: int = reloaded.load_json(path)
		var load_ms := (Time.get_ticks_usec() - start) / 1000.0
		var edit_ms: Array = []
		var incremental_count := 0
		for i in range(20):
			start = Time.get_ticks_usec()
			doc.paint_corner(config.x / 2, config.x / 2, i % 2)
			var vertex: int = doc.heightfield.index_at(config.x / 2, config.x / 2)
			if "--texture-update" in OS.get_cmdline_user_args() and editor.map_root.update_ground_textures(doc.heightfield, [vertex]):
				incremental_count += 1
			else:
				editor.map_root.rebuild_terrain_only(doc.as_build_dict(), doc.info)
			edit_ms.append((Time.get_ticks_usec() - start) / 1000.0)
			await get_tree().process_frame
		var callback_ms: Array = []
		if "--texture-update" in OS.get_cmdline_user_args():
			for i in range(20):
				start = Time.get_ticks_usec()
				doc.paint_corner(config.x / 2, config.x / 2, i % 2)
				editor.brush._texture_vertices[doc.heightfield.index_at(config.x / 2, config.x / 2)] = true
				editor._on_brush_rebuild()
				callback_ms.append((Time.get_ticks_usec() - start) / 1000.0)
				await get_tree().process_frame
		for i in range(10):
			await get_tree().process_frame
		var frame_ms: Array = []
		for i in range(90):
			start = Time.get_ticks_usec()
			editor.camera_rig.apply_orbit(Vector2(1, 0))
			await get_tree().process_frame
			frame_ms.append((Time.get_ticks_usec() - start) / 1000.0)
		var row := {"map_tiles": config.x, "objects": config.y, "trees": config.y * 4 / 5,
			"units": config.y / 5, "build_ms": build_ms, "save_ms": save_ms, "load_ms": load_ms,
			"save_error": save_error, "load_error": load_error,
			"edit_cpu_p95_ms": _p95(edit_ms), "frame_p95_ms": _p95(frame_ms),
			"incremental_updates": incremental_count,
			"editor_callback_p95_ms": _p95(callback_ms) if not callback_ms.is_empty() else null,
			"mean_fps": 1000.0 / (frame_ms.reduce(func(a, b): return a + b, 0.0) / frame_ms.size()),
			"static_memory_bytes": OS.get_static_memory_usage(),
			"unit_placeholders": editor.map_root.get_unit_layer().last_placeholder,
			"doodad_placeholders": editor.map_root.get_doodad_layer().last_placeholder}
		results.append(row)
		print("EDITOR_BENCHMARK ", JSON.stringify(row))
	var report := {"godot": Engine.get_version_info().string, "cpu": OS.get_processor_name(),
		"gpu": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "viewport": [1280, 720],
		"vsync": DisplayServer.window_get_vsync_mode(), "results": results,
		"limitations": "Edit metric measures synchronous CPU terrain rebuild, not input-to-present latency; sampled orbit is near map center. Build is warm after startup. Memory is Godot static allocator, not process RSS or GPU VRAM."}
	var file := FileAccess.open("res://tmp/editor-performance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("editor_performance: measured (see tmp/editor-performance.json)")
	get_tree().quit()


func _p95(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return float(sorted[ceili(sorted.size() * 0.95) - 1])
