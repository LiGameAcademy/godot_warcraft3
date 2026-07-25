extends SceneTree
## 斜坡数据层契约：Placement / Collect / Strip / Topology 强类型。
## godot --headless -s res://tests/unit/selftest_ramp_data.gd


func _init() -> void:
	var failed := 0
	failed += _test_placement_make()
	failed += _test_collect_empty()
	failed += _test_strip_spine()
	failed += _test_paint_and_search()
	failed += _test_topology_ramp_embed()
	failed += _test_vertex_has_ramp()
	if failed == 0:
		print("selftest_ramp_data: PASS")
		quit(0)
	else:
		push_error("selftest_ramp_data: FAIL (%d)" % failed)
		quit(1)


func _test_placement_make() -> int:
	var p := Wc3RampPlacement.make(
		3, 4, "AAHL", 2, 0, "CliffTrans", 0, Wc3RampKinds.AXIS_V, true, true
	)
	if p.ix != 3 or p.iy != 4 or p.tag != "AAHL":
		push_error("placement fields")
		return 1
	if p.model_dir != "CliffTrans" or p.topology != Wc3RampKinds.TOPO_STRAIGHT:
		push_error("placement defaults")
		return 1
	return 0


func _test_collect_empty() -> int:
	var r := Wc3RampCollectResult.empty_for_size(5, 4)
	if r.romp.size() != 20:
		push_error("romp size %d" % r.romp.size())
		return 1
	if r.romp[0] != Wc3RampKinds.ROMP_NONE:
		push_error("romp fill")
		return 1
	var stub: Wc3RampCollectResult = Wc3CliffLogic.collect_ramp_placements(
		{
			"tilepointWidth": 3,
			"tilepointHeight": 3,
			"layerHeights": [2, 2, 2, 2, 2, 2, 2, 2, 2],
			"heights": [0, 0, 0, 0, 0, 0, 0, 0, 0],
			"flagsPacked": [0, 0, 0, 0, 0, 0, 0, 0, 0],
		}
	)
	if stub.placements.size() != 0 or stub.romp.size() != 9:
		push_error("logic stub collect")
		return 1
	return 0


func _test_strip_spine() -> int:
	var s := Wc3RampStripSpec.make_vertical(1, 2, Wc3RampKinds.STRIP_FACE, true, 2, 3)
	var verts := s.spine_vertices()
	if verts.size() != 3 or verts[0] != Vector2i(1, 2) or verts[2] != Vector2i(1, 4):
		push_error("vertical spine %s" % str(verts))
		return 1
	var h := Wc3RampStripSpec.make_horizontal(0, 1, Wc3RampKinds.STRIP_SLOPE, false, 2, 2)
	var hv := h.spine_vertices()
	if hv.size() != 3 or hv[0] != Vector2i(0, 2):
		push_error("horizontal spine top %s" % str(hv))
		return 1
	var dup := s.duplicate_spec()
	dup.ramp_left = false
	if s.ramp_left == false:
		push_error("duplicate mutated source")
		return 1
	return 0


func _test_paint_and_search() -> int:
	var strip := Wc3RampStripSpec.make_horizontal(0, 1, Wc3RampKinds.STRIP_SLOPE, false, 2, 2)
	var r := Wc3RampPaintResult.success(true, "ok", strip)
	if not r.ok or not r.changed or r.strip.axis != Wc3RampKinds.AXIS_H:
		push_error("paint result")
		return 1
	var none := Wc3RampStripSearchResult.none("x")
	if none.has_strip() or none.reject_message != "x":
		push_error("search none")
		return 1
	var found := Wc3RampStripSearchResult.found(strip)
	if not found.has_strip():
		push_error("search found")
		return 1
	return 0


func _test_topology_ramp_embed() -> int:
	var topo := Wc3CliffTopologyResult.new()
	var collect := Wc3RampCollectResult.empty_for_size(2, 2)
	var p := Wc3RampPlacement.make(0, 0, "AHHL", 2, 0, "CliffTrans")
	collect.placements.append(p)
	collect.romp[0] = Wc3RampKinds.ROMP_SINGLE
	topo.ramp = collect
	if topo.ensure_ramp().placements[0].tag != "AHHL":
		push_error("topo embed")
		return 1
	var ctx := MapBuildContext.new()
	ctx.ramp = topo.ramp
	if ctx.ramp.placements[0].tag != "AHHL":
		push_error("ctx ramp cache")
		return 1
	return 0


func _test_vertex_has_ramp() -> int:
	var hf := Wc3Heightfield.from_dict(
		{
			"tilepointWidth": 2,
			"tilepointHeight": 2,
			"layerHeights": [2, 2, 2, 2],
			"heights": [0.0, 0.0, 0.0, 0.0],
			"flagsPacked": [0, Wc3Coords.FLAG_RAMP, 0, 0],
			"waterHeights": [0.0, 0.0, 0.0, 0.0],
			"groundTextures": [0, 0, 0, 0],
			"groundVariations": [0, 0, 0, 0],
			"cliffTextures": [0, 0, 0, 0],
			"cliffVariations": [0, 0, 0, 0],
		},
		false
	)
	var v := hf.vertex_at(1, 0)
	if v == null or not v.has_ramp:
		push_error("has_ramp read")
		return 1
	v.has_ramp = false
	if (int(hf.flags_packed[1]) & Wc3Coords.FLAG_RAMP) != 0:
		push_error("has_ramp clear")
		return 1
	return 0
