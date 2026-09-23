extends Node
var failed := 0


func check(value: bool, message: String) -> void:
	if not value:
		failed += 1
		push_error(message)


func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(1))


func _run() -> void:
	var scene = preload("res://scenes/editor_main.tscn").instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var doc = editor.get_document()
	var palette = editor._tool_palettes[0]
	var camera: Camera3D = editor.camera_rig.get_camera()
	palette.unit_selected.emit("hpea", editor.map_root.get_id_catalog().lookup("hpea"), 0)
	editor.unit_brush.stroke_press(camera.unproject_position(Vector3.ZERO))
	editor.unit_brush.stroke_release()
	check(doc.units.count() == 1 and doc.is_dirty(), "placement creates dirty map")
	editor._on_menu_action(&"file_save")
	var dialog: FileDialog = editor._map_file_dialog
	check(dialog.visible and dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE, "first Save opens file chooser")
	dialog.canceled.emit()
	dialog.hide()
	check(doc.file_path.is_empty() and doc.is_dirty(), "cancel Save preserves unsaved map")
	editor._on_menu_action(&"file_save_as")
	var path := ProjectSettings.globalize_path("res://tmp/editor-file-flow.wc3map.json")
	dialog.file_selected.emit(path)
	dialog.hide()
	check(FileAccess.file_exists(path) and doc.file_path == path and not doc.is_dirty(), "Save As writes current map and clears dirty flag")
	var saved_unit: Dictionary = doc.get_unit(0).duplicate(true)
	var saved_bytes := FileAccess.get_file_as_bytes(path)
	doc.paint_corner(3, 3, 1)
	editor._show_map_file_dialog(false)
	dialog.file_selected.emit(path)
	dialog.hide()
	await get_tree().process_frame
	check(editor._discard_pending, "opening file protects unsaved edit")
	editor._discard_dialog.canceled.emit()
	editor._discard_dialog.hide()
	await get_tree().process_frame
	check(doc.is_dirty() and doc.heightfield.ground_textures[doc.heightfield.index_at(3, 3)] == 1, "cancel Open keeps unsaved terrain")
	editor._on_menu_action(&"file_save")
	check(not doc.is_dirty() and FileAccess.get_file_as_bytes(path) != saved_bytes, "Save reuses selected path with latest terrain")
	var saved_heights: Array = doc.heightfield.heights.duplicate()
	var saved_textures: Array = doc.heightfield.ground_textures.duplicate()
	await editor._on_new_map_confirmed({"width": 32, "height": 32, "main_tileset": "L"})
	check(doc.units.count() == 0 and doc.file_path.is_empty(), "New clears previous objects and file association")
	editor._show_map_file_dialog(false)
	dialog.hide()
	# Await the same selected-file handler to include its asynchronous scene reload.
	_accept_discard_next_frame(editor)
	await editor._on_map_file_selected(path)
	check(doc.file_path == path and not doc.is_dirty(), "Open restores saved document")
	check(doc.units.count() == 1 and doc.get_unit(0).typeId == saved_unit.typeId, "Open restores original unit ID")
	check(PackedFloat64Array(doc.heightfield.heights) == PackedFloat64Array(saved_heights) and PackedInt32Array(doc.heightfield.ground_textures) == PackedInt32Array(saved_textures), "Open restores terrain arrays")
	check(not editor.get_history().can_undo(), "Open clears old map history")
	var before := JSON.stringify(doc.file_data())
	var invalid := ProjectSettings.globalize_path("res://tmp/editor-file-flow-invalid.json")
	var f := FileAccess.open(invalid, FileAccess.WRITE)
	f.store_string("{broken")
	f.close()
	await editor._on_map_file_selected(invalid)
	check(JSON.stringify(doc.file_data()) == before and doc.file_path == path, "failed Open preserves current map and file association")
	check(not doc.last_file_error.is_empty(), "failed Open supplies readable diagnostic")
	editor._on_menu_action(&"file_test_map")
	var preview = editor._preview
	if not preview.built:
		await preview.preview_built
	check(JSON.stringify(preview.snapshot) == before, "preview receives reopened map")
	preview.close_requested.emit()
	await preview.tree_exited
	await get_tree().process_frame
	check(JSON.stringify(doc.file_data()) == before and not doc.is_dirty(), "return from preview preserves reopened map")
	check(not is_instance_valid(preview), "closed preview released after frame")
	var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var orphan_count := int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	for cycle in range(3):
		editor._on_menu_action(&"file_test_map")
		var repeated = editor._preview
		if not repeated.built:
			await repeated.preview_built
		repeated.close_requested.emit()
		await repeated.tree_exited
		await get_tree().process_frame
		check(not is_instance_valid(repeated), "repeated preview released")
		check(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) <= node_count, "preview cycles do not accumulate nodes")
		check(int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)) <= orphan_count, "preview cycles do not accumulate orphan nodes")
	print("Preview lifecycle baseline: nodes=%d orphan_nodes=%d" % [node_count, orphan_count])
	print("selftest_editor_file_flow: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	get_tree().quit(0 if failed == 0 else 1)


func _accept_discard_next_frame(editor) -> void:
	await get_tree().process_frame
	check(editor._discard_pending, "replacing new map requests confirmation")
	if editor._discard_pending:
		editor._discard_dialog.confirmed.emit()
		editor._discard_dialog.hide()
