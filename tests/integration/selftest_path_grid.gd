extends SceneTree
## 斜坡中点高度 = 两端均值（A→B 平面）。M1 前 placements 为空则 SKIP。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := "res://assets/map-parsed/losttemple/terrain-heightfield.json"
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing heightfield")
		quit(1)
		return
	var hf: Variant = JSON.parse_string(f.get_as_text())
	var meta: Dictionary = Wc3Heightfield.build_meta_from_dict(hf as Dictionary)
	var ramp_data: Wc3RampCollectResult = Wc3CliffLogic.collect_ramp_placements(
		hf as Dictionary, meta
	)
	if ramp_data.placements.is_empty():
		print("selftest_path_grid: SKIP (ramp placements empty until Dispatcher M1)")
		quit(0)
		return
	var heights: Array = Wc3CliffLogic.apply_ramp_entrance_heights(
		meta["heights"],
		meta["layer_heights"],
		meta["flags"],
		int(meta["width"]),
		int(meta["height"])
	)
	var tp_w: int = int(meta["width"])
	var tp_h: int = int(meta["height"])
	var p: Wc3RampPlacement = ramp_data.placements[0]
	var ix: int = p.ix
	var iy: int = p.iy
	var axis := p.axis
	var lo: float
	var hi: float
	var mid: float
	if axis == Wc3RampKinds.AXIS_V:
		lo = (
			float(heights[iy * tp_w + ix]) + float(heights[iy * tp_w + ix + 1])
		) * 0.5
		hi = (
			float(heights[(iy + 2) * tp_w + ix]) + float(heights[(iy + 2) * tp_w + ix + 1])
		) * 0.5
		mid = Wc3CliffLogic.sample_ramp_plane_height(
			heights, ramp_data.placements, tp_w, tp_h, float(ix) + 0.5, float(iy) + 1.0
		)
	else:
		lo = (
			float(heights[iy * tp_w + ix]) + float(heights[(iy + 1) * tp_w + ix])
		) * 0.5
		hi = (
			float(heights[iy * tp_w + ix + 2]) + float(heights[(iy + 1) * tp_w + ix + 2])
		) * 0.5
		mid = Wc3CliffLogic.sample_ramp_plane_height(
			heights, ramp_data.placements, tp_w, tp_h, float(ix) + 1.0, float(iy) + 0.5
		)
	var expect := (lo + hi) * 0.5
	if is_nan(mid) or absf(mid - expect) > 1.0:
		push_error("mid=%.1f expect=%.1f" % [mid, expect])
		quit(1)
		return
	print(
		"selftest ramp plane: n=%d axis=%s mid=%.1f ok"
		% [ramp_data.placements.size(), axis, mid]
	)
	quit(0)
