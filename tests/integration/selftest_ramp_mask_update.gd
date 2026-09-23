extends Node
const MapScene := preload("res://addons/rts_map/scenes/map/map_root.tscn")
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
	var terrain: MapTerrainLayer = map.get_node("Terrain")
	var initial_mesh := ground.mesh
	var initial: Array = ground.mesh.surface_get_arrays(0)
	var empty_cells := PackedByteArray()
	empty_cells.resize(64)
	var empty_points := PackedByteArray()
	empty_points.resize(81)
	terrain.apply_ramp_dig(empty_cells, [], empty_points, empty_points)
	check(ground.mesh == initial_mesh, "zero ramp masks retain mesh")
	var dig := empty_cells.duplicate()
	dig[27] = 1
	terrain.apply_ramp_dig(dig, [], empty_points, empty_points)
	check(ground.mesh != initial_mesh, "new hole rebuilds ground")
	check(ground.mesh.surface_get_array_len(0) == initial[Mesh.ARRAY_VERTEX].size() - 6, "one cell removed")
	var dug_mesh := ground.mesh
	terrain.apply_ramp_dig(dig.duplicate(), [], empty_points, empty_points)
	check(ground.mesh == dug_mesh, "identical dig mask retains mesh")
	terrain.apply_ramp_dig(empty_cells, [], empty_points, empty_points)
	var restored: Array = ground.mesh.surface_get_arrays(0)
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_INDEX, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1]:
		check(initial[channel] == restored[channel], "clearing masks restores channel %d" % channel)
	var boost := empty_points.duplicate()
	boost[40] = 1
	terrain.apply_ramp_dig(empty_cells, [], boost, empty_points)
	check(ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] != initial[Mesh.ARRAY_VERTEX], "height boost still rebuilds geometry")
	terrain.apply_ramp_dig(empty_cells, [], empty_points, empty_points)
	check(ground.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == initial[Mesh.ARRAY_VERTEX], "clearing boost restores geometry")
	# Empty-ramp optimization must remove old geometry and masks, not merely return.
	terrain.apply_ramp_dig(dig, [], boost, empty_points)
	var ramps: MapRampLayer = map.get_node("Ramps")
	var stale := Node3D.new()
	ramps.add_child(stale)
	var ctx := MapBuildContext.create("res://", doc.as_build_dict(), doc.info, map.get_tiles(), map.get_id_catalog(), map._cache, map.get_cliff_catalog())
	ramps.build(ctx)
	check(ramps.get_child_count() == 0, "no-ramp build clears previous models")
	check(ramps.last_dig_count == 0 and ramps.last_boost_count == 0, "no-ramp build clears counters")
	var cleared: Array = ground.mesh.surface_get_arrays(0)
	for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_INDEX, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1]:
		check(cleared[channel] == initial[channel], "no-ramp build clears old masks channel %d" % channel)
	var empty_mesh := ground.mesh
	ramps.build(ctx)
	check(ground.mesh == empty_mesh, "repeated empty ramp build retains ground")
	var debug := MapRampDebugLayer.new()
	add_child(debug)
	# JSON stores numeric flags as floats, unlike freshly created documents.
	for i in range(ctx.heightfield.flags_packed.size()):
		ctx.heightfield.flags_packed[i] = float(ctx.heightfield.flags_packed[i])
	debug.build(ctx)
	check(debug.last_count == 0 and debug.get_child_count() == 0, "empty ramp debug emits no geometry")
	ctx.heightfield.flags_packed[40] = float(int(ctx.heightfield.flags_packed[40]) | Wc3Coords.FLAG_RAMP)
	debug.build(ctx)
	check(debug.last_count == 1 and debug.get_child_count() == 1, "ramp flag still emits marker")
	var marker := debug.get_child(0)
	var marker_vertices: PackedVector3Array = marker.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(marker_vertices.size() == 6, "marker retains two triangles")
	ctx.heightfield.flags_packed[40] = float(int(ctx.heightfield.flags_packed[40]) & ~Wc3Coords.FLAG_RAMP)
	debug.build(ctx)
	await get_tree().process_frame
	check(debug.last_count == 0 and debug.get_child_count() == 0, "removing last flag clears previous marker")
	check(not is_instance_valid(marker), "old debug marker is freed")
	print("selftest_ramp_mask_update: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	get_tree().quit(0 if failed == 0 else 1)
