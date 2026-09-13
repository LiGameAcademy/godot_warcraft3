extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
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
	var palette = editor._tool_palettes[0]
	var camera: Camera3D = editor.camera_rig.get_camera()
	var catalog: Wc3IdCatalog = editor.map_root.get_id_catalog()
	# Actual palette signals and screen-coordinate brush interfaces.
	for spec in [["hpea", -384, -256], ["htow", 384, 256]]:
		check(not catalog.converted_glb_path(spec[0], 0).is_empty(), "original unit model resolves")
		palette.unit_selected.emit(spec[0], catalog.lookup(spec[0]), 0)
		editor.unit_brush.set_random_rotation(false)
		var p := Wc3Coords.wc3_xy_to_godot(spec[1], spec[2], 0)
		editor.unit_brush.stroke_press(camera.unproject_position(p))
		editor.unit_brush.stroke_release()
	for spec in [["LTlt", -384, 384], ["LRrk", 384, -384]]:
		check(not catalog.converted_glb_path(spec[0], 0).is_empty(), "original doodad model resolves")
		palette.doodad_selected.emit(spec[0], catalog.lookup(spec[0]))
		editor.doodad_brush.set_place_random(false, false, false, false)
		var p := Wc3Coords.wc3_xy_to_godot(spec[1], spec[2], 0)
		editor.doodad_brush.stroke_press(camera.unproject_position(p))
		editor.doodad_brush.stroke_release()
	check(doc.units.count() == 2 and doc.doodads.count() == 2, "all four categories placed")
	# Edit peasant properties through the same window used by double-click.
	editor._on_unit_properties_requested(int(doc.get_unit(0).creationNumber))
	editor._unit_props_dialog._hp_spin.value = 75
	editor._unit_props_dialog._ok_btn.pressed.emit()
	# Terrain stamp in an open area of the map, with height and second texture.
	editor._brush_mode = "terrain"
	editor._sync_active_brush()
	palette._height_raise.pressed.emit()
	editor.brush.apply_texture = true
	doc.brush_tile_index = 4 # Original Lgrs grass, visually distinct from Ldrt.
	editor.brush.set_brush_settings(5, 0)
	var ground_point := camera.unproject_position(Wc3Coords.wc3_xy_to_godot(-768, -768, 0))
	for stamp in range(8):
		editor.brush.stroke_press(ground_point)
		editor.brush.stroke_release()
	check(doc.heightfield.heights.max() > 0, "height stamp applied")
	check(4 in doc.heightfield.ground_textures, "second terrain texture applied")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://examples/editor"))
	var path := "res://examples/editor/acceptance.wc3map.json"
	check(doc.save_json(path) == OK, "save acceptance map")
	check(doc.load_json(path) == OK, "reopen acceptance map")
	check(doc.units.count() == 2 and doc.doodads.count() == 2 and doc.get_unit(0).hitPoints == 75, "all categories and property survive reopen")
	editor._show_map_preview()
	var preview = editor._preview
	if not preview.built:
		await preview.preview_built
	check(preview.map.get_unit_layer().last_placeholder == 0 and preview.map.get_doodad_layer().last_placeholder == 0, "all four categories use original models")
	check(preview.map.find_unit_node(1) != null and preview.map.find_unit_node(2) != null, "preview has unit and building")
	check(preview.map.find_doodad_node(1) != null and preview.map.find_doodad_node(2) != null, "preview has tree and rock")
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() != "headless":
		preview.get_texture().get_image().save_png("res://examples/editor/acceptance-preview.png")
	preview.close_requested.emit()
	await preview.tree_exited
	print("selftest_editor_acceptance_sample: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
