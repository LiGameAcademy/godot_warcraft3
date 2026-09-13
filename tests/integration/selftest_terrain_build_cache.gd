extends Node
const MapScene := preload("res://scenes/map/map_root.tscn")
const Document := preload("res://editor/scripts/map_document.gd")
var failed := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failed += 1
		push_error(message)


func _ready() -> void:
	_check_append_cases()
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
	var reference = preload("res://tests/integration/terrain_reference_builder.gd").new()
	reference._ground = preload("res://tests/integration/terrain_reference_mesh.gd").new()
	var hf: Wc3Heightfield = doc.heightfield
	for scenario in range(3):
		for i in range(hf.heights.size()):
			hf.heights[i] = float((i * 31 + scenario * 7) % 96)
			hf.ground_textures[i] = (i + scenario) % 2
			hf.ground_variations[i] = (i * 3) % 18
			hf.layer_heights[i] = 2 + (1 if scenario > 0 and i % 5 == 0 else 0)
		var gaps := PackedByteArray()
		gaps.resize(64)
		if scenario > 0:
			gaps[15] = 1
			gaps[27] = 1
		terrain._entrance_h_boost.resize(81)
		terrain._entrance_h_boost.fill(0)
		terrain._last_romp.resize(81)
		terrain._last_romp.fill(0)
		if scenario == 2:
			terrain._entrance_h_boost[40] = 1
			terrain._last_romp[41] = 1
		terrain._last_hf = hf
		reference._last_hf = hf
		reference._entrance_h_boost = terrain._entrance_h_boost.duplicate()
		reference._last_romp = terrain._last_romp.duplicate()
		var count: int = terrain._build_ground_mesh(hf, terrain._last_extended, gaps, terrain._last_cliff_to_ground)
		var expected_count: int = reference._build_ground_mesh(hf, terrain._last_extended, gaps, terrain._last_cliff_to_ground)
		check(count == expected_count, "gap count matches reference")
		var actual: Array = ground.mesh.surface_get_arrays(0)
		var expected: Array = reference._ground.mesh.surface_get_arrays(0)
		for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_INDEX]:
			check(actual[channel] == expected[channel], "scenario %d channel %d matches original builder" % [scenario, channel])
	reference._ground.free()
	reference.free()
	print("selftest_terrain_build_cache: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	get_tree().quit(0 if failed == 0 else 1)


func _check_append_cases() -> void:
	for with_custom in [false, true]:
		for variant in range(4):
			var actual := HeightfieldMesh.new()
			var expected = preload("res://tests/integration/terrain_reference_mesh.gd").new()
			var points := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 1, 1), Vector3(1, 2, 1)])
			if variant == 3:
				points.fill(Vector3.ZERO)
			var custom0 := PackedFloat32Array()
			var custom1 := PackedFloat32Array()
			if variant == 1:
				custom0 = PackedFloat32Array([1, 2, 3, 4])
				custom1 = PackedFloat32Array([5, 6, 7, 8])
			elif variant == 2:
				custom0 = PackedFloat32Array([1, 2])
				custom1 = PackedFloat32Array([5, 6, 7, 8, 9])
			var uvs := PackedVector2Array()
			if variant > 0:
				uvs = PackedVector2Array([Vector2(0.1, 0.2), Vector2(0.3, 0.4), Vector2(0.5, 0.6), Vector2(0.7, 0.8), Vector2(0.9, 1), Vector2(1.1, 1.2)])
			actual.begin_build(with_custom)
			expected.begin_build(with_custom)
			actual.add_quad(points, custom0, custom1, uvs)
			expected.add_quad(points, custom0, custom1, uvs)
			actual.commit_build()
			expected.commit_build()
			var a: Array = actual.mesh.surface_get_arrays(0)
			var b: Array = expected.mesh.surface_get_arrays(0)
			for channel in range(Mesh.ARRAY_MAX):
				check(a[channel] == b[channel], "append custom=%s variant=%d channel=%d" % [with_custom, variant, channel])
			actual.free()
			expected.free()
