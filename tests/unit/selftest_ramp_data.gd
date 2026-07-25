extends SceneTree
## 斜坡数据层：Placement / Collect / Kinds（笔刷 DTO 已并入 Logic）。
## godot --headless -s res://tests/unit/selftest_ramp_data.gd


func _init() -> void:
	var failed := 0
	failed += _test_placement_make()
	failed += _test_collect_empty()
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
	if r.romp.size() != 20 or r.romp[0] != Wc3RampKinds.ROMP_NONE:
		push_error("romp empty")
		return 1
	var stub: Wc3RampCollectResult = Wc3RampLogic.collect_placements(
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


func _test_topology_ramp_embed() -> int:
	var topo := Wc3CliffTopologyResult.new()
	var collect := Wc3RampCollectResult.empty_for_size(2, 2)
	collect.placements.append(Wc3RampPlacement.make(0, 0, "AHHL", 2, 0, "CliffTrans"))
	collect.romp[0] = Wc3RampKinds.ROMP_SINGLE
	topo.ramp = collect
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
