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
	var skipped_phantom := 0
	for p in placements:
		if bool(p.get("phantom", false)):
			skipped_phantom += 1
			continue
		# wide_core / side_ridge 仅服务甲板采样与侧脊，不按单条四角验收
		if bool(p.get("wide_core", false)) or bool(p.get("side_ridge", false)):
			continue
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
		# 采样时排除 wide_core，只验本条平面（避免宽坡核心抢采样导致越界）
		var local_only: Array = []
		for q in placements:
			if bool(q.get("wide_core", false)):
				continue
			local_only.append(q)
		var mid = Wc3CliffTiles.sample_ramp_plane_height(heights, local_only, tp_w, tp_h, mx, my)
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
		# 宽坡外扩/邻条抢采样时允许少量数值误差
		var pad := 1.0
		if mid < lo - pad or mid > hi + pad:
			fail += 1
			print("FAIL mid=%.1f not in [%.1f,%.1f] @ %d,%d %s" % [mid, lo, hi, ix, iy, axis])
		else:
			ok += 1

	# 甲板开：全部 romp 不挖洞；关：仅 ROMP_SIDE 挖洞，SINGLE/WIDE 不挖
	var gap_romp := 0
	var romp_n := 0
	var wide_n := 0
	var wide_gap := 0
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			var kind := Wc3CliffTiles.romp_kind_at(romp, tp_w, ix, iy)
			if kind == Wc3CliffTiles.ROMP_NONE:
				continue
			romp_n += 1
			var g := Wc3CliffTiles.should_leave_gap(
				meta["layer_heights"], meta["flags"], tp_w, tp_h, ix, iy, romp
			)
			if kind == Wc3CliffTiles.ROMP_WIDE:
				wide_n += 1
				if g:
					wide_gap += 1
			elif kind == Wc3CliffTiles.ROMP_SIDE and g:
				gap_romp += 1
			elif g and kind != Wc3CliffTiles.ROMP_SIDE:
				gap_romp += 1  # unexpected

	var gap_ok := wide_gap == 0 and (
		gap_romp == 0
		if Wc3CliffTiles.RAMP_SURFACE_DECK_ENABLED
		else true
	)
	print(
		"selftest_ramp_deck: map=%s placements=%d mid_ok=%d mid_fail=%d phantom_skip=%d single_gap=%d wide=%d/%d deck=%s"
		% [
			path.get_file(),
			placements.size(),
			ok,
			fail,
			skipped_phantom,
			gap_romp,
			wide_n - wide_gap,
			wide_n,
			str(Wc3CliffTiles.RAMP_SURFACE_DECK_ENABLED),
		]
	)
	quit(0 if fail == 0 and gap_ok else 1)
