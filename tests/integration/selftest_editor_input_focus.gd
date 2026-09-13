extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(1))
func _run() -> void:
	var scene = preload("res://editor/scenes/editor_main.tscn").instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var router = editor.input_router
	get_window().grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	check(get_window().has_focus(), "main window has focus for baseline")
	key(KEY_W, true)
	check(router._keyboard_move_dir() != Vector3.ZERO, "W moves camera when viewport focused")
	key(KEY_CTRL, true)
	check(router._keyboard_move_dir() == Vector3.ZERO, "modifier shortcuts do not pan")
	key(KEY_CTRL, false)
	var field := LineEdit.new()
	field.position = Vector2(350, 90)
	field.size = Vector2(160, 30)
	get_tree().root.add_child(field)
	field.grab_focus()
	key(KEY_W, true)
	check(Input.is_key_pressed(KEY_W), "text-field check uses a pressed W key")
	check(router._keyboard_move_dir() == Vector3.ZERO, "typing in main-window text field does not pan")
	field.release_focus()
	var dialog := ConfirmationDialog.new()
	get_tree().root.add_child(dialog)
	dialog.popup_centered(Vector2i(320, 180))
	dialog.grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	check(dialog.has_focus(), "native modal window owns focus")
	key(KEY_W, true)
	check(Input.is_key_pressed(KEY_W), "modal check uses a pressed W key")
	check(router._keyboard_move_dir() == Vector3.ZERO, "typing in modal window does not pan background")
	key(KEY_W, false)
	dialog.hide()
	dialog.queue_free()
	field.queue_free()
	get_window().grab_focus()
	await get_tree().process_frame
	await get_tree().process_frame
	key(KEY_W, true)
	check(router._keyboard_move_dir() != Vector3.ZERO, "camera input resumes after returning focus")
	key(KEY_W, false)
	print("selftest_editor_input_focus: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
