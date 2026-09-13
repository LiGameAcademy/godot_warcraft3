extends Node
const EditorScene := preload("res://editor/scenes/editor_main.tscn")
var failed := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failed += 1
		push_error(message)


func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(1))


func _run() -> void:
	var scene := EditorScene.instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var palette = editor._tool_palettes[0]
	var doc = editor.get_document()
	# Use actual palette button signals, then the same stroke interface as InputRouter.
	palette._texture_check.set_pressed_no_signal(false)
	palette._on_texture_toggled(false)
	for i in range(5):
		palette._height_buttons[i].pressed.emit()
		check(editor.brush.apply_height and editor.brush.height_tool == i, "height tool button %d connected" % i)
	palette._height_raise.pressed.emit()
	var camera: Camera3D = editor.camera_rig.get_camera()
	var screen := camera.unproject_position(Vector3.ZERO)
	var before: Array = doc.heightfield.heights.duplicate()
	editor.brush.stroke_press(screen)
	editor.brush.stroke_release()
	await get_tree().process_frame
	var after: Array = doc.heightfield.heights.duplicate()
	check(after != before, "height-only mouse stroke modifies terrain")
	check(editor.get_history().can_undo(), "height stroke recorded")
	editor._undo()
	check(doc.heightfield.heights == before, "editor undo restores ground heights")
	editor._redo()
	check(doc.heightfield.heights == after, "editor redo restores raised terrain")
	check(editor.map_root.get_heightfield_dict().heights == after, "rendered map receives sculpted heightfield")
	var path := "res://tmp/editor-height-acceptance.wc3map.json"
	check(doc.save_json(path) == OK, "save sculpted map")
	var restored = preload("res://editor/scripts/map_document.gd").new()
	check(restored.load_json(path) == OK and restored.heightfield.heights == after, "sculpted heights survive reopen")
	print("selftest_editor_height: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	get_tree().quit(0 if failed == 0 else 1)
