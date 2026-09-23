extends Node
const EditorScene := preload("res://scenes/editor_main.tscn")
var failed := 0


func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(45).timeout.connect(func():
		push_error("editor preview integration timed out")
		get_tree().quit(1)
	)


func check(value: bool, label: String) -> void:
	if not value:
		failed += 1
		push_error(label)


func _run() -> void:
	var scene := EditorScene.instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var doc = editor.get_document()
	doc.add_unit(doc.make_unit_entry("hpea", 0, 0, 1, 90))
	doc.add_unit(doc.make_unit_entry("htow", 256, 256, 0, 180))
	doc.add_doodad(doc.make_doodad_entry("LTlt", -128, 128))
	var ground: HeightfieldMesh = editor.map_root.get_node("Terrain/Ground")
	var mesh_before := ground.mesh
	var recorder := PaintStrokeRecorder.new()
	recorder.begin(doc)
	recorder.capture_before_at(4, 4)
	doc.paint_corner(4, 4, 1)
	recorder.capture_after_at(4, 4)
	editor.get_history().record(recorder.finish("Texture integration"))
	editor.brush._texture_vertices[doc.heightfield.index_at(4, 4)] = true
	editor._on_brush_rebuild()
	check(ground.mesh == mesh_before, "brush callback updates texture without replacing mesh")
	_check_minimap(editor, "paint")
	editor._undo()
	check(int(doc.heightfield.ground_textures[doc.heightfield.index_at(4, 4)]) == 0, "editor undo restores texture")
	check(ground.mesh == mesh_before, "texture undo uses local update")
	_check_minimap(editor, "undo")
	editor._redo()
	check(int(doc.heightfield.ground_textures[doc.heightfield.index_at(4, 4)]) == 1, "editor redo restores texture")
	check(ground.mesh == mesh_before, "texture redo uses local update")
	_check_minimap(editor, "redo")
	var before: String = JSON.stringify(doc.file_data())
	# Cancel guards the actual new-map callback, including its history/document state.
	editor._on_new_map_confirmed({"width": 32, "height": 32})
	await get_tree().process_frame
	check(editor._discard_pending, "dirty map must prompt before new")
	editor._discard_dialog.canceled.emit()
	editor._discard_dialog.hide()
	await get_tree().process_frame
	check(JSON.stringify(doc.file_data()) == before, "cancel preserves edited map")
	editor._on_menu_action(&"file_test_map")
	var preview = editor._preview
	check(preview != null, "test-map menu creates preview")
	if not preview.built:
		await preview.preview_built
	check(preview.map.get_world_3d() != editor.map_root.get_world_3d(), "preview has isolated world")
	check(JSON.stringify(preview.snapshot) == before, "preview uses unsaved current data")
	check(preview.map.find_unit_node(1) != null, "preview presents placed peasant")
	check(preview.map.find_unit_node(2) != null, "preview presents placed building")
	check(preview.map.find_doodad_node(1) != null, "preview presents placed tree")
	check(preview.map.get_unit_layer().last_placeholder == 0, "units use original models, not placeholders")
	check(preview.map.get_doodad_layer().last_placeholder == 0, "tree uses original model, not placeholder")
	check(_has_summer_texture(preview.map.find_doodad_node(1)), "LTlt uses SLK summer texture")
	check(JSON.stringify(preview.map.get_heightfield_dict()) == JSON.stringify(doc.as_build_dict()), "rendered terrain uses edited heightfield")
	check(editor.brush.process_mode == Node.PROCESS_MODE_DISABLED, "background brush disabled")
	if "--capture-preview" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var capture: Image = preview.get_texture().get_image()
		check(capture != null and not capture.is_empty(), "preview image exists")
		if capture != null:
			check(capture.save_png("res://tmp/editor-preview.png") == OK, "save preview capture")
	preview.snapshot.info.name = "preview-only change"
	preview._close()
	await get_tree().process_frame
	await get_tree().process_frame
	check(JSON.stringify(doc.file_data()) == before and doc.is_dirty(), "return preserves document and dirty flag")
	check(editor.brush.process_mode != Node.PROCESS_MODE_DISABLED, "return restores brush")
	# Closing while loading defers deletion until the pending build finishes.
	editor._show_map_preview()
	var closing = editor._preview
	closing._close()
	if not closing.built:
		await closing.preview_built
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(closing), "closed loading preview is freed")
	check(editor.brush.process_mode != Node.PROCESS_MODE_DISABLED, "early close restores brush")
	print("selftest_editor_preview: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	scene.queue_free()
	await get_tree().process_frame
	get_tree().quit(0 if failed == 0 else 1)


func _has_summer_texture(node: Node) -> bool:
	if node is MeshInstance3D and node.mesh != null:
		for index in range(node.mesh.get_surface_count()):
			var mat: Material = node.get_active_material(index)
			if mat != null and mat.get_meta("wc3_replacement_path", "") == "ReplaceableTextures/LordaeronTree/LordaeronSummerTree.png":
				return true
	for child in node.get_children():
		if _has_summer_texture(child):
			return true
	return false


func _check_minimap(editor, stage: String) -> void:
	var window = editor._inspect_window
	var partial: PackedByteArray = window.get_minimap_image().get_data()
	window.refresh_minimap_live(editor.get_document().heightfield,
		editor.map_root.get_tiles(), editor.map_root.get_cliff_catalog())
	check(partial == window.get_minimap_image().get_data(), stage + " minimap equals full redraw")
