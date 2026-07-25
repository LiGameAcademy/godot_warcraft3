extends SceneTree
## 自测：斜坡中点高度 = 两端均值（A→B 平面）。


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
	var ramp_data: Dictionary = Wc3CliffLogic.collect_ramp_placements(hf as Dictionary, meta)
	var placements: Array = ramp_data.get("placements", []) as Array
	if placements.is_empty():
		push_error("no placements")
		quit(1)
		return
	var heights: Array = Wc3CliffLogic.apply_ramp_entrance_heights(
		meta["heights"], meta["layer_heights"], meta["flags"],
		int(meta["width"]), int(meta["height"])
	)
	var tp_w: int = int(meta["width"])
	var tp_h: int = int(meta["height"])
	var p: Dictionary = placements[0]
	var ix: int = int(p["ix"])
	var iy: int = int(p["iy"])
	var axis := str(p.get("axis", "v"))
	var lo: float
	var hi: float
	var mid: float
	if axis == "v":
		lo = (
			float(heights[iy * tp_w + ix]) + float(heights[iy * tp_w + ix + 1])
		) * 0.5
		hi = (
			float(heights[(iy + 2) * tp_w + ix]) + float(heights[(iy + 2) * tp_w + ix + 1])
		) * 0.5
		mid = Wc3CliffLogic.sample_ramp_plane_height(
			heights, placements, tp_w, tp_h, float(ix) + 0.5, float(iy) + 1.0
		)
	else:
		lo = (
			float(heights[iy * tp_w + ix]) + float(heights[(iy + 1) * tp_w + ix])
		) * 0.5
		hi = (
			float(heights[iy * tp_w + ix + 2]) + float(heights[(iy + 1) * tp_w + ix + 2])
		) * 0.5
		mid = Wc3CliffLogic.sample_ramp_plane_height(
			heights, placements, tp_w, tp_h, float(ix) + 1.0, float(iy) + 0.5
		)
	var expect := (lo + hi) * 0.5
	if is_nan(mid) or absf(mid - expect) > 1.0:
		push_error("mid=%.1f expect=%.1f" % [mid, expect])
		quit(1)
		return
	print("selftest ramp plane: n=%d axis=%s mid=%.1f ok" % [placements.size(), axis, mid])
	quit(0)
