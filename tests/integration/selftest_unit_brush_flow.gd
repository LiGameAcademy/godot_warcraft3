extends Node
var failed := 0


func check(value: bool, message: String) -> void:
	if not value:
		failed += 1
		push_error(message)


func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(1))


func _run() -> void:
	var scene = preload("res://editor/scenes/editor_main.tscn").instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var doc = editor.get_document()
	var brush = editor.unit_brush
	var camera: Camera3D = editor.camera_rig.get_camera()
	var palette = editor._tool_palettes[0]
	palette.unit_selected.emit("hpea", editor.map_root.get_id_catalog().lookup("hpea"), 0)
	check(brush.enabled and brush.type_id == "hpea", "palette activates unit brush")
	var center := camera.unproject_position(Vector3.ZERO)
	brush.stroke_press(center)
	brush.stroke_release()
	check(doc.units.count() == 1, "screen stroke places one unit")
	if doc.units.count() != 1:
		get_tree().quit(1)
		return
	var placed: Dictionary = doc.get_unit(0).duplicate(true)
	var cn: int = placed.creationNumber
	brush.clear_palette()
	var origin := camera.unproject_position(brush._wc3_to_world(Vector2(placed.position.x, placed.position.y)))
	var destination := origin + Vector2(65, 25)
	brush.stroke_press(origin)
	check(brush.get_selected_creation_number() == cn, "screen picking selects placed unit")
	brush.stroke_drag(destination)
	check(doc.get_unit(0).position != placed.position, "drag moves unit")
	brush.stroke_drag(origin)
	brush.stroke_release()
	var returned: Dictionary = doc.get_unit(0)
	check(absf(returned.position.x - placed.position.x) < 0.01 and absf(returned.position.y - placed.position.y) < 0.01, "drag back restores original location")
	check(editor.get_history().undo_stack.size() == 1, "return-to-origin drag creates no move command")
	brush.stroke_press(origin)
	brush.stroke_drag(destination)
	brush.stroke_release()
	var moved: Dictionary = doc.get_unit(0).duplicate(true)
	check(moved.position != placed.position, "released drag persists destination")
	editor._undo()
	check(doc.get_unit(0) == placed, "undo move restores complete entry")
	editor._redo()
	check(doc.get_unit(0) == moved, "redo move restores complete entry")
	brush.select_creation_number(cn)
	var rotate := InputEventKey.new()
	rotate.keycode = KEY_R
	rotate.pressed = true
	check(brush.handle_key(rotate), "rotation shortcut handled")
	check(doc.get_unit(0).angleDegrees != moved.angleDegrees, "rotation changes selected unit")
	editor._undo()
	check(doc.get_unit(0) == moved, "rotation undo exact")
	var moved_screen := camera.unproject_position(brush._wc3_to_world(Vector2(moved.position.x, moved.position.y)))
	brush.handle_double_click(moved_screen)
	check(editor._unit_props_dialog != null and editor._unit_props_dialog.visible, "double click opens selected unit properties")
	editor._unit_props_dialog._cancel_btn.pressed.emit()
	var delete := InputEventKey.new()
	delete.keycode = KEY_DELETE
	delete.pressed = true
	check(brush.handle_key(delete) and doc.units.count() == 0, "delete removes selected unit")
	editor._undo()
	check(doc.units.count() == 1 and doc.get_unit(0) == moved, "undo deletion restores same instance")
	for kind in ["unit", "doodad"]:
		var active = brush if kind == "unit" else editor.doodad_brush
		if kind == "doodad":
			palette.doodad_selected.emit("LTlt", editor.map_root.get_id_catalog().lookup("LTlt"))
			active.stroke_press(center)
			active.stroke_release()
			check(doc.doodads.count() == 1, "tree screen stroke places one object")
			active.clear_palette()
		var initial: Dictionary = doc.call("get_" + kind, 0).duplicate(true)
		var at := camera.unproject_position(active._wc3_to_world(Vector2(initial.position.x, initial.position.y)))
		editor.get_history().clear()
		active.stroke_press(at)
		active.stroke_drag(at + Vector2(90, 30))
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		check(active.handle_key(escape), kind + " Escape ends selection")
		check(editor.get_history().undo_stack.size() == 1, kind + " interrupted movement remains undoable")
		active.stroke_release()
		check(editor.get_history().undo_stack.size() == 1, kind + " later release does not duplicate command")
		editor._undo()
		check(doc.call("get_" + kind, 0) == initial, kind + " undo interrupted movement restores entry")
		active.stroke_press(at)
		active.stroke_drag(at + Vector2(90, 30))
		check(active.handle_key(delete), kind + " delete during drag handled")
		editor._undo()
		editor._undo()
		check(doc.call("get_" + kind, 0) == initial, kind + " undo deletion then movement restores starting state")
	print("selftest_unit_brush_flow: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	get_tree().quit(0 if failed == 0 else 1)
