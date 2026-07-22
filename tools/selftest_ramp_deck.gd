extends SceneTree
## 快速自测：斜坡甲板中点高度应落在两端之间（A→B 平面）。


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var path := "res://assets/map-parsed/losttemple/terrain-heightfield.json"
	if not FileAccess.file_exists(path):
		path = "res://assets/map-parsed/icecrown/terrain-heightfield.json"
	if not FileAccess.file_exists(path):
		push_error("selftest_ramp_deck: 找不到 heightfield")
		quit(1)
		return

	var f := FileAccess.open(path, FileAccess.READ)
	var hf: Dictionary = JSON.parse_string(f.get_as_text())
	var meta := HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var tiles := Wc3TerrainTiles.new()
	tiles.load_default()
	var tp_w: int = meta["width"]
	var tp_h: int = meta["height"]
	var heights: Array = Wc3CliffTiles.apply_ramp_entrance_heights(
		meta["heights"], meta["layer_heights"], meta["flags"], tp_w, tp_h
	)
	var ramp_data: Dictionary = Wc3CliffTiles.collect_ramp_placements(hf, meta, tiles)
	var placements: Array = ramp_data["placements"]
	var romp: PackedByteArray = ramp_data["romp"]

	var ok := 0
	var fail := 0
	for p in placements:
		var ix: int = int(p["ix"])
		var iy: int = int(p["iy"])
		var axis := str(p.get("axis", "v"))
		var mx: float
		var my: float
		if axis == "v":
			mx = float(ix) + 0.5
			my = float(iy) + 1.0
		else:
			mx = float(ix) + 1.0
			my = float(iy) + 0.5
		var mid = Wc3CliffTiles.sample_ramp_plane_height(heights, placements, tp_w, tp_h, mx, my)
		if is_nan(mid):
			fail += 1
			continue
		# 中点应落在条带四角高度的 min..max 内
		var corners: Array[float] = []
		if axis == "v":
			corners = [
				float(heights[iy * tp_w + ix]),
				float(heights[iy * tp_w + ix + 1]),
				float(heights[(iy + 2) * tp_w + ix]),
				float(heights[(iy + 2) * tp_w + ix + 1]),
			]
		else:
			corners = [
				float(heights[iy * tp_w + ix]),
				float(heights[(iy + 1) * tp_w + ix]),
				float(heights[iy * tp_w + ix + 2]),
				float(heights[(iy + 1) * tp_w + ix + 2]),
			]
		var lo := corners[0]
		var hi := corners[0]
		for c in corners:
			lo = minf(lo, c)
			hi = maxf(hi, c)
		if mid < lo - 0.01 or mid > hi + 0.01:
			fail += 1
			print("FAIL mid=%.1f not in [%.1f,%.1f] @ %d,%d %s" % [mid, lo, hi, ix, iy, axis])
		else:
			ok += 1

	# romp 不应再挖洞
	var gap_romp := 0
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			var i00 := iy * tp_w + ix
			if i00 < romp.size() and romp[i00] != 0:
				if Wc3CliffTiles.should_leave_gap(
					meta["layer_heights"], meta["flags"], tp_w, tp_h, ix, iy, romp
				):
					gap_romp += 1

	print(
		"selftest_ramp_deck: map=%s placements=%d mid_ok=%d mid_fail=%d romp_still_gap=%d"
		% [path.get_file(), placements.size(), ok, fail, gap_romp]
	)
	quit(0 if fail == 0 and gap_romp == 0 else 1)
