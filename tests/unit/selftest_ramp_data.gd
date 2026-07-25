extends SceneTree
## 斜坡数据层契约：Placement / CollectResult / StripSpec / Topology 强类型。
## godot --headless -s res://tests/unit/selftest_ramp_data.gd


func _init() -> void:
	var failed := 0
	failed += _test_placement_make()
	failed += _test_collect_empty()
	failed += _test_strip_roundtrip()
	failed += _test_paint_result_dict()
	failed += _test_topology_types()
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
	if r.placement_count() != 0 or r.non_phantom_count() != 0:
		push_error("empty counts")
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


func _test_strip_roundtrip() -> int:
	var s := Wc3RampStripSpec.make_vertical(1, 2, Wc3RampKinds.STRIP_FACE, true, 2, 3)
	var d := s.to_dict()
	var back := Wc3RampStripSpec.from_dict(d)
	if not back.ok or back.sx != 1 or back.sy != 2 or back.axis != Wc3RampKinds.AXIS_V:
		push_error("strip roundtrip")
		return 1
	var bad := Wc3RampStripSpec.from_dict({"ok": false, "message": "x", "code": "corner"})
	if bad.ok or bad.message != "x":
		push_error("strip fail parse")
		return 1
	return 0


func _test_paint_result_dict() -> int:
	var strip := Wc3RampStripSpec.make_horizontal(0, 1, Wc3RampKinds.STRIP_SLOPE, false, 2, 2)
	var r := Wc3RampPaintResult.success(true, "ok", strip)
	var d := r.to_dict()
	if not bool(d.get("ok")) or not bool(d.get("changed")):
		push_error("paint dict flags")
		return 1
	if str(d.get("axis")) != Wc3RampKinds.AXIS_H or int(d.get("sx")) != 0:
		push_error("paint dict strip")
		return 1
	return 0


func _test_topology_types() -> int:
	var topo := Wc3CliffTopologyResult.new()
	var p := Wc3RampPlacement.make(0, 0, "AHHL", 2, 0, "CliffTrans")
	topo.ramp_placements.append(p)
	topo.romp = PackedByteArray([Wc3RampKinds.ROMP_SINGLE])
	if topo.ramp_placements.size() != 1:
		push_error("topo typed array")
		return 1
	var ctx := MapBuildContext.new()
	ctx.cliff_ramp_placements = topo.ramp_placements
	if ctx.cliff_ramp_placements[0].tag != "AHHL":
		push_error("ctx typed cache")
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
