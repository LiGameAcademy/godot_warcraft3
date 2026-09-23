extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(1))
func _run() -> void:
	var scene = preload("res://scenes/editor_main.tscn").instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var doc = editor.get_document()
	var brush = editor.doodad_brush
	editor._tool_palettes[0].doodad_selected.emit("LTlt", editor.map_root.get_id_catalog().lookup("LTlt"))
	var camera: Camera3D = editor.camera_rig.get_camera()
	var screen := camera.unproject_position(Vector3.ZERO)
	brush.stroke_press(screen)
	brush.stroke_release()
	brush.clear_palette()
	var before: Dictionary = doc.get_doodad(0).duplicate(true)
	screen = camera.unproject_position(brush._wc3_to_world(Vector2(before.position.x, before.position.y)))
	brush.handle_double_click(screen)
	var dialog = editor._doodad_props_dialog
	check(dialog != null and dialog.visible, "double click opens doodad properties")
	var count: int = editor.get_history().undo_stack.size()
	dialog.confirmed.emit()
	dialog.hide()
	check(doc.get_doodad(0) == before and editor.get_history().undo_stack.size() == count, "unchanged confirmation preserves data and history")
	brush.handle_double_click(screen)
	dialog._fields.x.value = 1.5
	dialog._fields.z.value = 2.0
	dialog._fields.life.value = 63
	dialog._fields.angle.value = 37
	var model: Node3D = editor.map_root.find_doodad_node(int(before.creationNumber))
	dialog.confirmed.emit()
	dialog.hide()
	var after: Dictionary = doc.get_doodad(0).duplicate(true)
	check(after.scale.x == 1.5 and after.scale.z == 2.0 and after.life == 63 and is_equal_approx(after.angleDegrees, 37.0), "edited values reach document")
	check(editor.map_root.find_doodad_node(int(before.creationNumber)) == model, "properties preserve model instance")
	check(is_equal_approx(model.scale.y / model.scale.x, 2.0 / 1.5), "WC3 vertical scale maps to Godot Y")
	editor._undo()
	check(doc.get_doodad(0) == before, "undo restores complete entry")
	editor._redo()
	check(doc.get_doodad(0) == after, "redo restores edited entry")
	var path := "res://tmp/doodad-properties.wc3map.json"
	check(doc.save_json(path) == OK, "save properties")
	var loaded = preload("res://documents/map_document.gd").new()
	check(loaded.load_json(path) == OK, "reopen properties")
	check(loaded.get_doodad(0).scale == after.scale and loaded.get_doodad(0).life == 63, "scale and life survive reopen")
	brush.handle_double_click(screen)
	dialog._fields.life.value = 12
	dialog.canceled.emit()
	dialog.hide()
	check(doc.get_doodad(0) == after, "cancel preserves previous properties")
	if "--capture" in OS.get_cmdline_user_args():
		brush.handle_double_click(screen)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		dialog.get_texture().get_image().save_png("res://tmp/doodad-properties.png")
	print("selftest_doodad_properties: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
