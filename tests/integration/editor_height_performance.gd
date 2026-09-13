extends Node
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(1))
func _run() -> void:
	var scene = preload("res://editor/scenes/editor_main.tscn").instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var doc = editor.get_document()
	if doc.load_json("res://tmp/editor-benchmark-64.wc3map.json") != OK:
		push_error("Fixed 64x64 performance fixture required")
		get_tree().quit(1)
		return
	await editor._apply_document(true)
	while editor._units_loading:
		await get_tree().process_frame
	for w in editor._tool_palettes:
		w.hide()
	editor.input_router.set_process(false)
	var runs: Array = []
	for sample in range(10):
		var index: int = doc.heightfield.index_at(32 + sample % 3, 32)
		doc.heightfield.heights[index] += 16.0
		editor.map_root.rebuild_terrain_cliffs_water(doc.as_build_dict(), doc.info)
		runs.append(editor.map_root.last_terrain_rebuild_timings.duplicate())
		await get_tree().process_frame
	var result := {"fixture": "editor-benchmark-64.wc3map.json", "renderer": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(), "runs": runs}
	var f := FileAccess.open("res://tmp/editor-height-profile.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(result, "\t"))
	f.close()
	print("Height rebuild profile: ", JSON.stringify(runs))
	get_tree().quit()
