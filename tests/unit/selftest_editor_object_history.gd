extends SceneTree
const Doc := preload("res://documents/map_document.gd")
const Units := preload("res://documents/commands/unit_edit_command.gd")
const Doodads := preload("res://documents/commands/doodad_edit_command.gd")
var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failed += 1
		push_error(message)


func _run() -> void:
	for kind in ["unit", "doodad"]:
		var doc = Doc.new()
		doc.create_blank(9)
		var history := EditorCommandHistory.new()
		history.bind_document(doc)
		var command = Units if kind == "unit" else Doodads
		var entries: Array = []
		for index in range(3):
			var entry: Dictionary = doc.make_unit_entry("hpea", index * 32, 0) if kind == "unit" else doc.make_doodad_entry("LTlt", index * 32, 0)
			var placed: int = doc.call("add_" + kind, entry)
			entries.append(doc.call("get_" + kind, placed))
		history.record(command.make_add(entries))
		var initial := _state(doc, kind)
		var edited: Dictionary = entries[1].duplicate(true)
		edited.position.x = 123.5
		edited.position.y = -87.25
		edited.angle = deg_to_rad(33)
		edited.angleDegrees = 33
		edited.scale = {"x": 1.25, "y": 1.5, "z": 0.75}
		if kind == "unit":
			edited.owner = 3
			edited.hitPoints = 75
			edited.heroLevel = 4
		else:
			edited.life = 70
		check(doc.call("update_" + kind + "_by_creation_number", edited.creationNumber, edited), kind + " modify")
		history.record(command.make_modify([entries[1]], [edited]))
		var modified := _state(doc, kind)
		var removed: Dictionary = doc.call("remove_" + kind + "_by_creation_number", entries[0].creationNumber)
		history.record(command.make_remove([removed]))
		var deleted := _state(doc, kind)
		for cycle in range(10):
			history.undo()
			check(_state(doc, kind) == modified, "%s restore deletion %d" % [kind, cycle])
			history.undo()
			check(_state(doc, kind) == initial, "%s restore transform/properties %d" % [kind, cycle])
			history.undo()
			check(_state(doc, kind) == "[]", "%s undo placements %d" % [kind, cycle])
			history.redo()
			check(_state(doc, kind) == initial, "%s redo placements without duplicate IDs %d" % [kind, cycle])
			history.redo()
			check(_state(doc, kind) == modified, "%s redo properties %d" % [kind, cycle])
			history.redo()
			check(_state(doc, kind) == deleted, "%s redo deletion %d" % [kind, cycle])
		history.undo()
		var fresh: Dictionary = doc.make_unit_entry("htow", 256, 0) if kind == "unit" else doc.make_doodad_entry("LTlt", 256, 0)
		var fresh_index: int = doc.call("add_" + kind, fresh)
		history.record(command.make_add([doc.call("get_" + kind, fresh_index)]))
		check(not history.can_redo(), kind + " new edit discards stale redo branch")
	print("selftest_editor_object_history: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	quit(0 if failed == 0 else 1)


func _state(doc, kind: String) -> String:
	var entries: Array = doc.unit_entries() if kind == "unit" else doc.doodad_entries()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.creationNumber < b.creationNumber)
	return JSON.stringify(entries)
