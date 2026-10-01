extends Node
const Document := preload("res://documents/map_document.gd")
class DirectionBrush extends "res://tools/terrain_brush.gd":
	var direction := Vector2i(0, 1)
	func _pick_vertex(_pos: Vector2) -> Vector2i:
		return Vector2i(8, 8)
	func _ramp_dirs_from_mouse(_vert: Vector2i, _pos: Vector2) -> Vector2i:
		return direction
	func _main_window_mouse_local() -> Vector2:
		return Vector2.ZERO

var failed := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failed += 1
		push_error(message)
func _ready() -> void:
	var doc = Document.new()
	doc.create_from_options({"width": 16, "height": 16, "main_tileset": "L", "ground_tilesets": ["Ldrt", "Lgrs"], "cliff_tilesets": ["CLdi", "CLgr"]})
	var hf: Wc3Heightfield = doc.heightfield
	for y in range(hf.height):
		for x in range(hf.width):
			var i := y * hf.width + x
			hf.layer_heights[i] = 3 if x <= 8 and y <= 8 else 2
			hf.heights[i] = (hf.layer_heights[i] - 2) * 128.0
	hf.cliff_textures.fill(1)
	doc._rebind_logic()
	var original_textures: Array = hf.cliff_textures.duplicate()
	var before: Array = hf.flags_packed.duplicate()
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(5, 7, 7)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var history := EditorCommandHistory.new()
	history.bind_document(doc)
	var brush := DirectionBrush.new()
	add_child(brush)
	brush.set_process(false)
	brush.setup(doc, camera, get_viewport().world_3d, history)
	brush.apply_texture = false
	brush.set_cliff_settings(true, "Ramp", 0)
	brush.stroke_press(Vector2.ZERO)
	var first: Array = hf.flags_packed.duplicate()
	check(first != before, "first ramp arm drawn")
	brush.direction = Vector2i(1, 0)
	brush.stroke_drag(Vector2.ZERO)
	var second: Array = hf.flags_packed.duplicate()
	check(second != first, "direction change at same vertex draws second arm")
	check(brush._hover_ramp_dirs == Vector2i(1, 0), "hover direction refreshes within same vertex")
	brush.stroke_drag(Vector2.ZERO)
	check(hf.flags_packed == second, "identical sample remains idempotent")
	check(hf.cliff_textures == original_textures, "ramp painting preserves grass cliffs despite dirt palette")
	brush.stroke_release()
	check(history.undo_stack.size() == 1, "continuous L stroke creates one command")
	history.undo()
	check(hf.flags_packed == before, "undo restores all flags")
	check(hf.cliff_textures == original_textures, "undo preserves cliff textures")
	history.redo()
	check(hf.flags_packed == second, "redo restores full L stroke")
	check(hf.cliff_textures == original_textures, "redo preserves cliff textures")
	check(doc.save_json("res://tmp/ramp-brush-direction.wc3map.json") == OK, "save ramp map")
	var restored = Document.new()
	check(restored.load_json("res://tmp/ramp-brush-direction.wc3map.json") == OK, "reopen ramp map")
	check(PackedInt32Array(restored.heightfield.flags_packed) == PackedInt32Array(second), "reopen retains ramp flags")
	check(PackedInt32Array(restored.heightfield.cliff_textures) == PackedInt32Array(original_textures), "save/reopen preserves cliff textures")
	brush.queue_free()
	var map: MapLoader = preload("res://packages/map/scenes/map/map_root.tscn").instantiate()
	map.auto_load_on_ready = false
	map.place_units = false
	map.place_doodads = false
	map.status_path = NodePath("")
	add_child(map)
	await get_tree().process_frame
	await map.reload_from_hf(doc.as_build_dict(), doc.info, "res://")
	map.set_view_grid_level(0)
	map.set_show_ramp_debug(false)
	var ramps: MapRampLayer = map.get_node("Ramps")
	check(ramps.last_placement_count > 0, "L ramp collects original transition models")
	check(ramps.get_child_count() == ramps.last_placement_count, "all transition models mount")
	var terrain: MapTerrainLayer = map.get_node("Terrain")
	check(terrain._cell_first_vertex[8 * 16 + 8] >= 0, "completed outer corner retains ground between transition models")
	for i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tmp/ramp-brush-direction.png")
	print("selftest_ramp_brush_direction: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	get_tree().quit(0 if failed == 0 else 1)
