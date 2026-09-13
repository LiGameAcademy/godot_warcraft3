extends SceneTree
const Document := preload("res://editor/scripts/map_document.gd")
const MapFile := preload("res://editor/scripts/map_file.gd")
var failures := 0
var directory := "res://tmp/editor-map-file-" + str(Time.get_ticks_usec())


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)


func _run() -> void:
	var doc = Document.new()
	doc.create_blank(9)
	doc.paint_corner(2, 2, 1)
	doc.heightfield.heights[20] = 32.5
	doc.info["name"] = "保存往返测试"
	doc.add_unit(doc.make_unit_entry("hpea", 32, -48, 2, 75))
	doc.add_unit(doc.make_unit_entry("htow", -128, 128, 0, 180))
	doc.add_doodad(doc.make_doodad_entry("LTlt", 96, 96, 1, 45, 1.25))
	doc.pathing = Wc3PathingMap.from_dict({"formatVersion": 0, "width": 2, "height": 2,
		"cellSize": 32, "origin": {"x": -512, "y": -512}, "cells": [2, 4, 8, 0]})
	var path := directory.path_join("roundtrip.wc3map.json")
	check(doc.save_json(path) == OK, "save: " + doc.last_file_error)
	check(not doc.is_dirty(), "saved document should be clean")
	var reopened = Document.new()
	check(reopened.load_json(path) == OK, "load: " + reopened.last_file_error)
	check(_json(reopened.heightfield.to_dict()) == _json(doc.heightfield.to_dict()), "all terrain arrays roundtrip")
	check(_json(reopened.units_as_dict()) == _json(doc.units_as_dict()), "unit ID/position/angle/properties roundtrip")
	check(_json(reopened.doodads_as_dict()) == _json(doc.doodads_as_dict()), "doodad roundtrip")
	check(_json(reopened.info) == _json(doc.info), "map info roundtrip")
	check(_json(reopened.pathing.to_dict()) == _json(doc.pathing.to_dict()), "pathing roundtrip")
	# Replacement is exercised against an existing destination, including on Windows.
	reopened.info.name = "第二次保存"
	reopened.mark_dirty()
	check(reopened.save_json() == OK, "overwrite saved path")
	check(MapFile.read(path).data.info.name == "第二次保存", "overwrite persisted")
	# Failed writes must preserve both the target bytes and dirty state.
	var bytes := FileAccess.get_file_as_bytes(path)
	reopened.mark_dirty()
	check(reopened.save_json(path.path_join("cannot-write.json")) != OK, "write below a file should fail")
	check(reopened.is_dirty() and reopened.file_path == path, "failed save keeps dirty/path")
	check(FileAccess.get_file_as_bytes(path) == bytes, "failed save keeps valid file")
	# Unknown fields survive load, edits, deletion of a different object, and resave.
	var opaque: Dictionary = MapFile.read(path).data
	opaque["extension"] = {"custom": [1, "保留"]}
	opaque.terrain["customTerrain"] = true
	opaque.units.units[1]["customObject"] = {"value": 42}
	check(MapFile.write(path, opaque) == OK, "write extended map")
	check(reopened.load_json(path) == OK, "load extended map")
	reopened.remove_unit(0)
	check(reopened.save_json() == OK, "save after removing other object")
	var retained: Dictionary = MapFile.read(path).data
	check(_json(retained.extension) == _json(opaque.extension) and retained.terrain.customTerrain, "unknown root/terrain fields retained")
	check(retained.units.units[0].get("customObject", {}).get("value") == 42, "unknown object field follows creation number")
	# Malformed/future documents must not replace a live dirty document.
	var stable := _json(reopened.file_data())
	reopened.mark_dirty()
	var invalid := directory.path_join("invalid.wc3map.json")
	for kind in ["json", "version", "array", "position", "duplicate", "pathing"]:
		var bad: Dictionary = opaque.duplicate(true)
		match kind:
			"version": bad.version = 999
			"array": bad.terrain.heights = [0]
			"position": bad.units.units[0].position = "broken"
			"duplicate": bad.units.units[1].creationNumber = bad.units.units[0].creationNumber
			"pathing": bad.pathing.cellsBase64 = ""
		var file := FileAccess.open(invalid, FileAccess.WRITE)
		file.store_string("{" if kind == "json" else _json(bad))
		file.close()
		check(reopened.load_json(invalid) != OK, "reject " + kind)
		check(_json(reopened.file_data()) == stable and reopened.is_dirty(), "preserve live document on " + kind)
	# Saving an imported document must not touch its source sidecars.
	var source := directory.path_join("source")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(source))
	var source_units := source.path_join("units.json")
	var sentinel := FileAccess.open(source_units, FileAccess.WRITE)
	sentinel.store_string("source must remain unchanged")
	sentinel.close()
	doc.map_dir = source
	check(doc.save_json(directory.path_join("imported.wc3map.json")) == OK, "save imported document")
	check(FileAccess.get_file_as_string(source_units) == "source must remain unchanged", "source units unchanged")
	check(not FileAccess.file_exists(source.path_join("doodads.json")), "no source doodad writes")
	var added: int = reopened.add_unit(reopened.make_unit_entry("hpea", 0, 0))
	check(reopened.get_unit(added).creationNumber > retained.units.units[0].creationNumber, "allocation resumes above loaded IDs")
	print("selftest_editor_map_file: %s (%d failures); fixtures: %s" % ["PASS" if failures == 0 else "FAIL", failures, directory])
	quit(0 if failures == 0 else 1)


func _json(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)))
