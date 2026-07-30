extends SceneTree
## 验证：paint_corner 写入后，Ground mesh CUSTOM0 含新 tileset 下标。
## godot --headless -s res://tests/unit/selftest_paint_ground_rebuild.gd


const DocScript := preload("res://editor/scripts/map_document.gd")


func _init() -> void:
	var failed := 0
	failed += _test_paint_then_rebuild()
	if failed == 0:
		print("selftest_paint_ground_rebuild: PASS")
		quit(0)
	else:
		push_error("selftest_paint_ground_rebuild: FAIL (%d)" % failed)
		quit(1)


func _test_paint_then_rebuild() -> int:
	var doc = DocScript.new()
	doc.create_blank(5)
	var tiles := Wc3TerrainTileCatalog.new()
	tiles.load_default()

	var ix := 2
	var iy := 2
	var i: int = doc.heightfield.index_at(ix, iy)
	var before: int = int(doc.heightfield.ground_textures[i])
	var target: int = 1 if before != 1 else 2
	if target >= doc.heightfield.ground_tilesets.size():
		target = 0 if before != 0 else 1

	if not doc.paint_corner(ix, iy, target):
		push_error("paint_corner returned false")
		return 1
	var after: int = int(doc.heightfield.ground_textures[i])
	if after != target:
		push_error("data not written before=%d after=%d want=%d" % [before, after, target])
		return 1

	# 模拟「先崖后地」：cliff sync 不应盖住最终纹理（本测只验 mesh）
	var layer := MapTerrainLayer.new()
	layer.ground_material = load("res://assets/materials/wc3_ground_material.tres") as ShaderMaterial
	var ground := HeightfieldMesh.new()
	ground.name = "Ground"
	layer.add_child(ground)
	layer._ground = ground

	var ctx = (load("res://scripts/map/presentation/map_build_context.gd") as GDScript).create(
		"res://",
		doc.as_build_dict(),
		{},
		tiles,
		null,
		null
	)
	layer.build(ctx)
	if ground.mesh == null or ground.mesh.get_surface_count() < 1:
		push_error("mesh empty after build")
		layer.free()
		return 1

	# 含该顶点的四格应把 target 放进 CUSTOM0
	var arrays: Array = ground.mesh.surface_get_arrays(0)
	var custom0: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var found := false
	var j := 0
	while j + 3 < custom0.size():
		for k in range(4):
			if is_equal_approx(custom0[j + k], float(target)):
				found = true
				break
		if found:
			break
		j += 4
	if not found:
		push_error("CUSTOM0 missing painted tex=%d (custom0 size=%d)" % [target, custom0.size()])
		layer.free()
		return 1

	print("  paint→rebuild OK tex %d→%d custom0 hit" % [before, target])
	layer.free()
	return 0
