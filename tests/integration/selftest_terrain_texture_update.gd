extends Node
const MapScene := preload("res://packages/map/scenes/map/map_root.tscn")
const Document := preload("res://documents/map_document.gd")
var failed := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failed += 1
		push_error(message)


func _ready() -> void:
	var doc = Document.new()
	doc.create_from_options({"width": 8, "height": 8, "main_tileset": "L",
		"ground_tilesets": ["Ldrt", "Lgrs"], "cliff_tilesets": ["CLdi", "CLgr"]})
	var map: MapLoader = MapScene.instantiate()
	map.auto_load_on_ready = false
	map.place_units = false
	map.place_doodads = false
	map.show_pathing_debug_grid = false
	map.status_path = NodePath("")
	add_child(map)
	await get_tree().process_frame
	await map.reload_from_hf(doc.as_build_dict(), doc.info, "res://")
	var ground: HeightfieldMesh = map.get_node("Terrain/Ground")
	var original_mesh := ground.mesh
	var old: Array = ground.mesh.surface_get_arrays(0)
	var edits: Array = [0, 8, 40, 72, 80, 30]
	for index in edits:
		doc.paint_corner(int(index) % 9, int(index) / 9, 1)
	check(map.update_ground_textures(doc.heightfield, edits), "incremental texture update accepted")
	check(ground.mesh == original_mesh, "mesh identity retained")
	await get_tree().process_frame
	var partial: Array = ground.mesh.surface_get_arrays(0)
	check(partial[Mesh.ARRAY_VERTEX] == old[Mesh.ARRAY_VERTEX], "vertices unchanged")
	check(partial[Mesh.ARRAY_NORMAL] == old[Mesh.ARRAY_NORMAL], "normals unchanged")
	check(partial[Mesh.ARRAY_INDEX] == old[Mesh.ARRAY_INDEX], "indices unchanged")
	map.rebuild_terrain_only(doc.as_build_dict(), doc.info)
	var complete: Array = ground.mesh.surface_get_arrays(0)
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_INDEX]:
		check(partial[channel] == complete[channel], "full rebuild matches channel %d" % channel)
	# Repeat across reused caches and move the texture back (undo equivalent).
	for index in edits:
		doc.paint_corner(int(index) % 9, int(index) / 9, 0)
	check(map.update_ground_textures(doc.heightfield, edits), "second update accepted")
	await get_tree().process_frame
	var reversed: Array = ground.mesh.surface_get_arrays(0)
	map.rebuild_terrain_only(doc.as_build_dict(), doc.info)
	var reference: Array = ground.mesh.surface_get_arrays(0)
	check(reversed[Mesh.ARRAY_CUSTOM0] == reference[Mesh.ARRAY_CUSTOM0], "reverse texture update matches rebuild")
	check(reversed[Mesh.ARRAY_CUSTOM1] == reference[Mesh.ARRAY_CUSTOM1], "reverse variation update matches rebuild")
	map.get_node("Terrain")._extra_dig = PackedByteArray([1])
	check(not map.update_ground_textures(doc.heightfield, edits), "slope dig falls back to full rebuild")
	print("selftest_terrain_texture_update: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	get_tree().quit(0 if failed == 0 else 1)
