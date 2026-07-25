extends SceneTree
## Ground 表现管线：Catalog 贴图数组 + TerrainLayer 组网。
## godot --headless -s res://tests/unit/selftest_ground_mesh.gd


func _init() -> void:
	var failed := 0
	failed += _test_build_blank_ground()
	if failed == 0:
		print("selftest_ground_mesh: PASS")
		quit(0)
	else:
		push_error("selftest_ground_mesh: FAIL (%d)" % failed)
		quit(1)


func _test_build_blank_ground() -> int:
	var doc_script: GDScript = load("res://editor/scripts/map_document.gd") as GDScript
	var doc = doc_script.new()
	doc.create_blank(5)
	var tiles := Wc3TerrainTileCatalog.new()
	tiles.load_default()
	var hf: Wc3Heightfield = doc.heightfield
	var ground_tilesets: Array = hf.ground_tilesets
	var extended := Wc3GroundTileCatalog.build_extended_flags(ground_tilesets, tiles)
	if extended.size() != ground_tilesets.size():
		push_error("extended size mismatch")
		return 1

	var mat: ShaderMaterial = load("res://assets/materials/wc3_ground_material.tres") as ShaderMaterial
	var layer := MapTerrainLayer.new()
	layer.ground_material = mat
	var ground := HeightfieldMesh.new()
	ground.name = "Ground"
	layer.add_child(ground)
	layer._ground = ground

	var gap_count: int = layer._build_ground_mesh(hf, extended, PackedByteArray())
	if ground.mesh == null or ground.mesh.get_surface_count() < 1:
		push_error("ground mesh empty")
		return 1
	var tex := Wc3GroundTileCatalog.build_texture_array(ground_tilesets, tiles)
	if tex == null or tex.get_layers() < 1:
		push_error("texture array failed")
		return 1
	print(
		"  ground mesh OK surfaces=%d layers=%d gaps=%d"
		% [ground.mesh.get_surface_count(), tex.get_layers(), gap_count]
	)
	layer.free()
	return 0
