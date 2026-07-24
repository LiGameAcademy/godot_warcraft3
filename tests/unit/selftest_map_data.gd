extends SceneTree
## 地图数据模型自测：Lost Temple heightfield + 顶点视图。
## godot --headless -s res://tests/unit/selftest_map_data.gd


func _init() -> void:
	var failed := 0
	failed += _test_load_losttemple()
	failed += _test_vertex_writeback()
	if failed == 0:
		print("selftest_map_data: PASS")
		quit(0)
	else:
		push_error("selftest_map_data: FAIL (%d)" % failed)
		quit(1)


func _test_load_losttemple() -> int:
	var m := Wc3ParsedMap.load_dir("res://assets/map-parsed/losttemple")
	if m == null or m.heightfield == null:
		push_error("load_dir failed")
		return 1
	var hf := m.heightfield
	if hf.width != 161 or hf.height != 161:
		push_error("size want 161 got %d,%d" % [hf.width, hf.height])
		return 1
	if not hf.is_valid():
		push_error("heightfield invalid")
		return 1
	var v0 := hf.vertex_at(0, 0)
	if v0 == null:
		push_error("vertex_at 0,0 null")
		return 1
	var h0: float = float(hf.heights[0])
	if absf(v0.height - h0) > 0.001:
		push_error("height mismatch %s vs %s" % [v0.height, h0])
		return 1
	print("  load OK slug=%s verts=%d h00=%s" % [m.slug, hf.tilepoint_count(), v0.height])
	return 0


func _test_vertex_writeback() -> int:
	var hf := Wc3Heightfield.load_json_path(
		"res://assets/map-parsed/losttemple/terrain-heightfield.json"
	)
	if hf == null:
		push_error("reload hf failed")
		return 1
	var v := hf.vertex_at(10, 10)
	var old_layer: int = v.layer
	var old_flags: int = v.flags
	v.layer = mini(old_layer + 1, 14)
	v.has_ramp = true
	if int(hf.layer_heights[v.index]) != v.layer:
		push_error("layer not written back")
		return 1
	if (int(hf.flags_packed[v.index]) & 4) == 0:
		push_error("ramp flag not set")
		return 1
	if v.has_water:
		push_error("water should clear when ramp set")
		return 1
	var d: Dictionary = hf.to_dict()
	if int(d["layerHeights"][v.index]) != v.layer:
		push_error("to_dict layer mismatch")
		return 1
	var view: Dictionary = hf.as_dict_view()
	if not is_same(view["heights"], hf.heights):
		push_error("as_dict_view must share heights array")
		return 1
	var meta: Dictionary = hf.to_build_meta()
	if int(meta["width"]) != hf.width or not is_same(meta["layer_heights"], hf.layer_heights):
		push_error("to_build_meta mismatch")
		return 1
	print(
		"  writeback OK idx=%d layer %d→%d flags %d→%d"
		% [v.index, old_layer, v.layer, old_flags, v.flags]
	)
	return 0
