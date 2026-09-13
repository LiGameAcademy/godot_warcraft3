extends SceneTree
const Doc := preload("res://editor/scripts/map_document.gd")
const MapFile := preload("res://editor/scripts/map_file.gd")
var failed := 0
var fixture := "res://tmp/editor-import-" + str(Time.get_ticks_usec())


func _initialize() -> void:
	call_deferred("_run")


func check(condition: bool, message: String) -> void:
	if not condition:
		failed += 1
		push_error(message)


func _run() -> void:
	var doc = Doc.new()
	for slug in ["echoisles", "losttemple", "gnollwood", "terenasstand", "turtlerock", "twistedmeadows"]:
		var err: int = doc.load_from_map_dir("res://assets/map-parsed/" + slug)
		check(err == OK, slug + ": " + doc.last_file_error)
		if err == OK:
			print("  imported %s units=%d doodads=%d warnings=%s" % [slug, doc.units.count(), doc.doodads.count(), doc.import_warnings])
			check(MapFile.validate(doc.file_data()).is_empty(), slug + " remains saveable")
			check(doc.import_warnings.size() == (1 if slug == "terenasstand" else 0), slug + " missing pathing disclosed")
	# Isolated fixtures: never edit installed source maps.
	doc.create_blank(9)
	doc.add_unit(doc.make_unit_entry("hpea", 0, 0))
	var data: Dictionary = doc.file_data()
	var files := {"terrain": "terrain-heightfield.json", "units": "units.json", "doodads": "doodads.json", "info": "info.json"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(fixture))
	for key in files:
		_write(files[key], data[key])
	check(doc.load_from_map_dir(fixture) == OK and doc.import_warnings.size() == 1, "missing optional pathing explicitly warned")
	var warning_path := fixture.path_join("warnings.wc3map.json")
	check(doc.save_json(warning_path) == OK, "save import warnings")
	var warning_doc = Doc.new()
	check(warning_doc.load_json(warning_path) == OK and warning_doc.import_warnings.size() == 1, "import warnings survive save/reopen")
	doc.mark_dirty()
	var before: String = JSON.stringify(doc.file_data())
	var before_dir: String = doc.map_dir
	for key in files:
		_write(files[key], [])
		check(doc.load_from_map_dir(fixture) != OK, "reject corrupted " + files[key])
		check(doc.is_dirty() and doc.map_dir == before_dir and JSON.stringify(doc.file_data()) == before, "retain dirty map on " + files[key])
		_write(files[key], data[key])
	var units_path := ProjectSettings.globalize_path(fixture.path_join("units.json"))
	DirAccess.rename_absolute(units_path, units_path + ".held")
	check(doc.load_from_map_dir(fixture) != OK, "missing units rejected rather than discarded")
	check(JSON.stringify(doc.file_data()) == before and doc.is_dirty(), "missing units keeps map")
	DirAccess.rename_absolute(units_path + ".held", units_path)
	_write("pathing.json", {"width": "invalid"})
	check(doc.load_from_map_dir(fixture) != OK, "present but corrupt pathing rejected")
	check(JSON.stringify(doc.file_data()) == before and doc.is_dirty(), "bad pathing keeps map")
	print("selftest_editor_map_import: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	quit(0 if failed == 0 else 1)


func _write(name: String, value: Variant) -> void:
	var file := FileAccess.open(fixture.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(value))
	file.close()
