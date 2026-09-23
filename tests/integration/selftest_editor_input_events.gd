extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func send(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func click_at(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	event.pressed = pressed
	send(event)
func key(code: Key, ctrl: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.ctrl_pressed = ctrl
	event.pressed = true
	send(event)
	event = event.duplicate()
	event.pressed = false
	send(event)
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
	editor._tool_palettes[0].unit_selected.emit("hpea", editor.map_root.get_id_catalog().lookup("hpea"), 0)
	for window in editor._tool_palettes:
		window.hide()
	editor._inspect_window.hide()
	get_window().grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	var camera: Camera3D = editor.camera_rig.get_camera()
	var origin := camera.unproject_position(Vector3.ZERO)
	click_at(origin, true)
	click_at(origin, false)
	check(doc.units.count() == 1, "injected mouse click reaches placement tool")
	if doc.units.count() != 1:
		get_tree().quit(1)
		return
	key(KEY_ESCAPE)
	check(editor.unit_brush.type_id.is_empty(), "Escape cancels placement through input router")
	var before: Dictionary = doc.get_unit(0).duplicate(true)
	origin = camera.unproject_position(editor.unit_brush._wc3_to_world(Vector2(before.position.x, before.position.y)))
	click_at(origin, true)
	var motion := InputEventMouseMotion.new()
	motion.position = origin + Vector2(70, 30)
	motion.global_position = motion.position
	motion.relative = Vector2(70, 30)
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	send(motion)
	click_at(motion.position, false)
	var moved: Dictionary = doc.get_unit(0).duplicate(true)
	check(moved.position != before.position, "injected drag moves selected unit")
	key(KEY_R)
	check(not is_equal_approx(doc.get_unit(0).angleDegrees, moved.angleDegrees), "R rotates via unhandled input")
	key(KEY_Z, true)
	check(doc.get_unit(0) == moved, "Ctrl+Z undoes rotation once")
	key(KEY_DELETE)
	check(doc.units.count() == 0, "Delete removes selection via input router")
	key(KEY_Z, true)
	check(doc.units.count() == 1 and doc.get_unit(0) == moved, "Ctrl+Z restores deleted instance")
	key(KEY_Z, true)
	check(doc.get_unit(0) == before, "Ctrl+Z restores pre-drag position")
	key(KEY_Y, true)
	check(doc.get_unit(0) == moved, "Ctrl+Y reapplies drag")
	# Undo while the mouse is still held must finish and undo this movement.
	motion = motion.duplicate()
	origin = camera.unproject_position(editor.unit_brush._wc3_to_world(Vector2(moved.position.x, moved.position.y)))
	click_at(origin, true)
	motion.position = origin + Vector2(60, 20)
	motion.global_position = motion.position
	motion.relative = Vector2(60, 20)
	send(motion)
	check(doc.get_unit(0).position != moved.position, "second drag is active")
	key(KEY_Z, true)
	check(doc.get_unit(0) == moved, "undo during held drag restores its starting state")
	var history_count: int = editor.get_history().undo_stack.size()
	click_at(motion.position, false)
	check(editor.get_history().undo_stack.size() == history_count, "mouse release after undo adds no stale command")
	print("selftest_editor_input_events: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
