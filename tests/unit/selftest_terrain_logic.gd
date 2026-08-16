extends SceneTree
## 高度图逻辑层自测。
## godot --headless -s res://tests/unit/selftest_terrain_logic.gd


func _init() -> void:
	var failed := 0
	failed += _test_ground_and_dirty()
	failed += _test_height_and_neighbors()
	if failed == 0:
		print("selftest_terrain_logic: PASS")
		quit(0)
	else:
		push_error("selftest_terrain_logic: FAIL (%d)" % failed)
		quit(1)


func _make_blank() -> Wc3Heightfield:
	var doc_script: GDScript = load("res://editor/scripts/map_document.gd") as GDScript
	var doc = doc_script.new()
	doc.create_blank(5)
	return doc.heightfield


func _test_ground_and_dirty() -> int:
	var hf := _make_blank()
	var logic := Wc3TerrainLogic.new()
	logic.bind(hf)
	if not logic.set_ground_tex(1, 1, 1):
		push_error("set_ground_tex failed")
		return 1
	if int(hf.ground_textures[logic.heightfield.index_at(1, 1)]) != 1:
		push_error("ground tex not written")
		return 1
	if not logic.has_dirty():
		push_error("expected dirty after paint")
		return 1
	var r: Rect2i = logic.take_dirty_rect()
	if r.position != Vector2i(1, 1) or r.size != Vector2i.ONE:
		push_error("dirty rect want (1,1)1x1 got %s" % r)
		return 1
	if logic.has_dirty():
		push_error("dirty should clear after take")
		return 1
	if not logic.paint_tile(1, 1, 0):
		push_error("paint_tile failed")
		return 1
	r = logic.take_dirty_rect()
	if r.size.x < 2 or r.size.y < 2:
		push_error("paint_tile dirty too small %s" % r)
		return 1
	print("  ground+dirty OK")
	return 0


func _test_height_and_neighbors() -> int:
	var hf := _make_blank()
	var logic := Wc3TerrainLogic.new()
	logic.bind(hf)
	if not logic.set_height(2, 2, 64.0):
		push_error("set_height failed")
		return 1
	if absf(logic.height_at(2, 2) - 64.0) > 0.01:
		push_error("height_at mismatch")
		return 1
	# 中心抬高一层邻域仍为默认 FLAT
	var n: PackedInt32Array = logic.neighbor_layers(2, 2)
	if n.size() != 4:
		push_error("neighbor size")
		return 1
	for i in range(4):
		if int(n[i]) != Wc3TerrainLogic.FLAT_LAYER:
			push_error("neighbor layer %d want flat got %d" % [i, n[i]])
			return 1
	var v := logic.vertex_at(2, 2)
	if v == null or absf(v.height - 64.0) > 0.01:
		push_error("vertex_at height")
		return 1
	print("  height+neighbors OK")
	return 0
