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


func same_saved_value(a: Variant, b: Variant) -> bool:
	# JSON parses integers as floats and serializes floating angles to finite precision.
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a) - float(b)) <= 0.000000001 * maxf(1.0, absf(float(a)))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not same_saved_value(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not same_saved_value(a[i], b[i]):
				return false
		return true
	return a == b


func _run() -> void:
	var scene := EditorScene.instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var doc = editor.get_document()
	var entry: Dictionary = doc.make_unit_entry("hpea", 0, 0)
	entry.owner = 14
	entry.targetAcquisition = 743.25
	entry.hitPoints = 100
	entry.manaPoints = 17
	entry.angle = 0.123456789
	entry.angleDegrees = rad_to_deg(entry.angle)
	var index: int = doc.add_unit(entry)
	entry = doc.get_unit(index).duplicate(true)
	var history = editor.get_history()
	# Exercise the brush signal, editor handler, real dialog widgets and OK/Cancel buttons.
	editor.unit_brush.properties_requested.emit(int(entry.creationNumber))
	var dialog = editor._unit_props_dialog
	check(dialog.visible, "brush opens property window")
	check(dialog._owner_opt.get_item_metadata(dialog._owner_opt.selected) == 14, "neutral owner shown correctly")
	check(dialog._acq_custom.button_pressed, "custom acquisition represented explicitly")
	dialog._ok_btn.pressed.emit()
	check(doc.get_unit(index) == entry, "unchanged OK preserves exact imported values")
	check(not history.can_undo(), "unchanged OK creates no command")
	dialog.open_for_entry(entry)
	dialog._hp_spin.value = 65
	dialog._cancel_btn.pressed.emit()
	check(doc.get_unit(index) == entry and not history.can_undo(), "cancel leaves document and history unchanged")
	dialog.open_for_entry(entry)
	dialog._hp_spin.value = 65
	dialog._acq_spin.value = 850
	dialog._ok_btn.pressed.emit()
	var edited: Dictionary = doc.get_unit(index).duplicate(true)
	check(edited.hitPoints == 65 and edited.targetAcquisition == 850, "edited fields reach document")
	var expected := entry.duplicate(true)
	expected.hitPoints = 65
	expected.targetAcquisition = 850.0
	check(edited == expected, "editing HP and range preserves unrelated values")
	check(history.undo_stack.size() == 1, "one confirmation records one command")
	editor._undo()
	check(doc.get_unit(index) == entry, "editor undo restores original properties")
	editor._redo()
	check(doc.get_unit(index) == edited, "editor redo restores edited properties")
	var path := "res://tmp/unit-properties-acceptance.wc3map.json"
	check(doc.save_json(path) == OK, "save edited properties")
	var restored = preload("res://editor/scripts/map_document.gd").new()
	check(restored.load_json(path) == OK and same_saved_value(restored.get_unit(index), edited), "properties survive save and reopen")
	for owner in [12, 13, 14, 15]:
		var probe := entry.duplicate(true)
		probe.owner = owner
		probe.targetAcquisition = -1.0
		probe.hitPoints = -1.0
		probe.manaPoints = -1.0
		dialog.open_for_entry(probe)
		check(dialog._collect_entry() == probe, "neutral %d and default sentinels preserved" % owner)
		dialog._cancel_btn.pressed.emit()
	if "--capture-properties" in OS.get_cmdline_user_args():
		dialog.open_for_entry(edited)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		check(dialog._ok_btn.get_global_rect().end.y <= dialog.size.y and dialog._cancel_btn.get_global_rect().end.y <= dialog.size.y, "confirmation buttons stay inside window")
		check(dialog.get_texture().get_image().save_png("res://tmp/unit-properties.png") == OK, "capture properties window")
	print("selftest_unit_properties: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	get_tree().quit(0 if failed == 0 else 1)
