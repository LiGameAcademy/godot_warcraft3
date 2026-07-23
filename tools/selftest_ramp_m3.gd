extends SceneTree
## M3：单脊 CliffTrans 收口；甲板关闭时 romp 挖洞、邻面高度不变、放置斜坡模。
##
## 运行：
##   godot --headless --path . -s res://tools/selftest_ramp_m3.gd


const DocScript := preload("res://editor/scripts/map_document.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _case_single_spine_clifftrans_no_deck()
	failed += _case_ramp_foot_gets_ground_mesh()
	failed += _case_adjacent_ground_not_warped()
	failed += _case_width3_crest_foot_decked()
	if failed > 0:
		push_error("selftest_ramp_m3 FAILED cases=%d" % failed)
		quit(1)
		return
	print("selftest_ramp_m3 OK")
	quit(0)


func _new_doc() -> Object:
	var doc = DocScript.new()
	doc.create_from_options({
		"width": 32,
		"height": 32,
		"main_tileset": "L",
		"main_tileset_name": "Lordaeron Summer",
		"ground_tilesets": ["Ldrt", "Lgrs"],
		"cliff_tilesets": ["CLdi", "CLgr"],
		"cliff_level": 2,
	})
	return doc


func _set_layer_rect(doc, x0: int, y0: int, x1: int, y1: int, layer: int) -> void:
	var layers: Array = doc.hf["layerHeights"]
	var heights: Array = doc.hf["heights"]
	var water: Array = doc.hf["waterHeights"]
	var tp_w: int = int(doc.hf["tilepointWidth"])
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var i: int = y * tp_w + x
			var old: int = int(layers[i])
			layers[i] = layer
			heights[i] = float(heights[i]) + float(layer - old) * 128.0
			if i < water.size():
				water[i] = float(water[i]) + float(layer - old) * 128.0


func _case_single_spine_clifftrans_no_deck() -> int:
	print("=== case: single spine → CliffTrans + romp gap, no deck ===")
	if Wc3CliffTiles.RAMP_SURFACE_DECK_ENABLED:
		push_error("M3 expects RAMP_SURFACE_DECK_ENABLED=false")
		return 1
	var doc = _new_doc()
	_set_layer_rect(doc, 8, 11, 12, 11, 3)
	var r: Dictionary = doc.try_paint_ramp_at(10, 10)
	if not bool(r.get("ok", false)):
		push_error("paint failed: %s" % str(r))
		return 1

	var tiles := Wc3TerrainTiles.new()
	tiles.load_default()
	var meta := HeightfieldMeshBuilder.read_heightfield_meta(doc.hf)
	var ramp_data: Dictionary = Wc3CliffTiles.collect_ramp_placements(doc.hf, meta, tiles)
	var romp: PackedByteArray = ramp_data.get("romp", PackedByteArray())
	var placements: Array = ramp_data.get("placements", []) as Array

	var romp_n := 0
	var gap_n := 0
	var floor_n := 0
	var tp_w: int = int(meta["width"])
	var tp_h: int = int(meta["height"])
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			var i00 := iy * tp_w + ix
			if i00 >= romp.size() or romp[i00] == 0:
				continue
			romp_n += 1
			var g := Wc3CliffTiles.should_leave_gap(
				meta["layer_heights"], meta["flags"], tp_w, tp_h, ix, iy, romp
			)
			if g:
				gap_n += 1
			else:
				floor_n += 1
	if romp_n < 2:
		push_error("expected romp>=2, got %d" % romp_n)
		return 1
	# 条带底格铺地板；上格挖洞给 CliffTrans
	if floor_n < 1:
		push_error("strip floor cells should not gap, floor=%d" % floor_n)
		return 1
	if gap_n < 1:
		push_error("strip upper cells should still gap, gap=%d" % gap_n)
		return 1

	var built: Dictionary = Wc3TerrainAutotile.build_ground_mesh(
		doc.hf, PackedByteArray(), tiles, meta, romp, placements
	)
	# 底格会出地面（非 ramp_deck 计数也可，只要不挖洞）
	var cliffs: Dictionary = Wc3CliffBuilder.collect_instances(doc.hf, tiles, meta, ramp_data)
	var placed_ramps: int = int(cliffs.get("placed_ramps", 0))
	# 单脊必须主条+幻影两侧都有 CliffTrans（缺一侧即开天窗）
	if placed_ramps < 2:
		push_error("single-spine needs CliffTrans on BOTH sides, got %d missing=%s" % [
			placed_ramps, str(cliffs.get("missing", 0))
		])
		return 1
	var phantom_n := 0
	var main_n := 0
	for p in placements:
		if str(p.get("axis", "")) != "v" and str(p.get("axis", "")) != "h":
			continue
		if bool(p.get("wide_core", false)):
			continue
		if bool(p.get("phantom", false)):
			phantom_n += 1
		else:
			main_n += 1
	if phantom_n < 1 or main_n < 1:
		push_error("single-spine needs main+phantom pair, main=%d phantom=%d" % [main_n, phantom_n])
		return 1
	# 背后顶格：非 romp，留给直崖 Cliffs
	var sx0: int = int(r.get("sx", 10))
	var sy0: int = int(r.get("sy", 9))
	var crest_k := Wc3CliffTiles.romp_kind_at(romp, tp_w, sx0, sy0 + 2)
	if crest_k != Wc3CliffTiles.ROMP_NONE:
		push_error("crest must be free for Cliffs, romp=%d" % crest_k)
		return 1
	print("OK CliffTrans=%d floor=%d gap=%d crest_free" % [placed_ramps, floor_n, gap_n])
	return 0


## 斜坡脚底：条带底格 + 外侧一格不挖洞；背后顶格仍挖洞给 Cliffs。
func _case_ramp_foot_gets_ground_mesh() -> int:
	print("=== case: ramp foot strip-floor + outside → ground mesh ===")
	var doc = _new_doc()
	_set_layer_rect(doc, 8, 11, 16, 11, 3)
	var r0: Dictionary = doc.try_paint_ramp_at(10, 10)
	var r1: Dictionary = doc.try_paint_ramp_at(11, 10)
	if not bool(r0.get("ok", false)) or not bool(r1.get("ok", false)):
		push_error("paint failed")
		return 1
	var sx0: int = int(r0.get("sx", 10))
	var sy0: int = int(r0.get("sy", 9))
	var tiles := Wc3TerrainTiles.new()
	tiles.load_default()
	var meta := HeightfieldMeshBuilder.read_heightfield_meta(doc.hf)
	var ramp_data: Dictionary = Wc3CliffTiles.collect_ramp_placements(doc.hf, meta, tiles)
	var romp: PackedByteArray = ramp_data.get("romp", PackedByteArray())
	var tp_w: int = int(meta["width"])
	# 宽2：侧脊底格 SIDE 必须铺地（红框缝就是它）
	var side_floor_ix := sx0 + 1
	if Wc3CliffTiles.romp_kind_at(romp, tp_w, side_floor_ix, sy0) == Wc3CliffTiles.ROMP_SIDE:
		if Wc3CliffTiles.should_leave_gap(
			meta["layer_heights"], meta["flags"], tp_w, int(meta["height"]), side_floor_ix, sy0, romp
		):
			push_error("SIDE strip floor @%d,%d must not gap" % [side_floor_ix, sy0])
			return 1
	# 侧脊上格仍挖洞
	if Wc3CliffTiles.romp_kind_at(romp, tp_w, side_floor_ix, sy0 + 1) == Wc3CliffTiles.ROMP_SIDE:
		if not Wc3CliffTiles.should_leave_gap(
			meta["layer_heights"], meta["flags"], tp_w, int(meta["height"]), side_floor_ix, sy0 + 1, romp
		):
			push_error("SIDE upper @%d,%d must still gap for CliffTrans" % [side_floor_ix, sy0 + 1])
			return 1
	# 外侧脚底
	if sy0 > 0:
		var foot_iy := sy0 - 1
		if not Wc3CliffTiles.is_ramp_foot_cell(romp, tp_w, sx0, foot_iy):
			push_error("expected outside foot @%d,%d" % [sx0, foot_iy])
			return 1
		if Wc3CliffTiles.should_leave_gap(
			meta["layer_heights"], meta["flags"], tp_w, int(meta["height"]), sx0, foot_iy, romp
		):
			push_error("outside foot must not gap")
			return 1
	print("OK strip-floor + outside foot meshed, upper SIDE still gapped")
	return 0


func _case_adjacent_ground_not_warped() -> int:
	print("=== case: adjacent L|R → width-2 deck, not two U CliffTrans ===")
	var doc = _new_doc()
	_set_layer_rect(doc, 8, 11, 16, 11, 3)
	var r0: Dictionary = doc.try_paint_ramp_at(10, 10)
	var r1: Dictionary = doc.try_paint_ramp_at(11, 10)
	if not bool(r0.get("ok", false)) or not bool(r1.get("ok", false)):
		push_error("adjacent paint failed")
		return 1
	var tiles := Wc3TerrainTiles.new()
	tiles.load_default()
	var meta := HeightfieldMeshBuilder.read_heightfield_meta(doc.hf)
	var ramp_data: Dictionary = Wc3CliffTiles.collect_ramp_placements(doc.hf, meta, tiles)
	var romp: PackedByteArray = ramp_data.get("romp", PackedByteArray())
	var placements: Array = ramp_data.get("placements", []) as Array
	var wide_cells := 0
	var tp_w: int = int(meta["width"])
	for iy in range(int(meta["height"]) - 1):
		for ix in range(tp_w - 1):
			if Wc3CliffTiles.romp_kind_at(romp, tp_w, ix, iy) == Wc3CliffTiles.ROMP_WIDE:
				wide_cells += 1
				if Wc3CliffTiles.should_leave_gap(
					meta["layer_heights"], meta["flags"], tp_w, int(meta["height"]), ix, iy, romp
				):
					push_error("wide cell must not gap @%d,%d" % [ix, iy])
					return 1
	if wide_cells < 2:
		push_error("expected wide continuous cells >=2, got %d" % wide_cells)
		return 1
	var cliffs: Dictionary = Wc3CliffBuilder.collect_instances(doc.hf, tiles, meta, ramp_data)
	# 宽坡：外侧侧脊 CliffTrans
	var placed_ramps: int = int(cliffs.get("placed_ramps", 0))
	if placed_ramps < 1:
		push_error("wide ramp should place outer side CliffTrans, got %d" % placed_ramps)
		return 1
	var built: Dictionary = Wc3TerrainAutotile.build_ground_mesh(
		doc.hf, PackedByteArray(), tiles, meta, romp, placements
	)
	if int(built.get("ramp_deck_count", 0)) < 2:
		push_error("width-2 should deck >=2, got %d" % int(built.get("ramp_deck_count", 0)))
		return 1
	# 中间点应落在坡面（wide_core），不能凹到 R5 min
	var heights: Array = Wc3CliffTiles.apply_ramp_entrance_heights(
		meta["heights"], meta["layer_heights"], meta["flags"], tp_w, int(meta["height"])
	)
	var sx0: int = int(r0.get("sx", 10))
	var sy0: int = int(r0.get("sy", 9))
	var mid_h: float = Wc3CliffTiles.sample_ramp_plane_height(
		heights, placements, tp_w, int(meta["height"]), float(sx0), float(sy0 + 1)
	)
	var lo_h: float = float(heights[sy0 * tp_w + sx0])
	var hi_h: float = float(heights[(sy0 + 2) * tp_w + sx0])
	if is_nan(mid_h):
		push_error("wide mid vertex must sample ramp plane")
		return 1
	var expected_mid := lerpf(lo_h, hi_h, 0.5)
	if absf(mid_h - expected_mid) > 1.0:
		push_error("mid dipped/wrong: mid=%s expected~%s" % [str(mid_h), str(expected_mid)])
		return 1
	# 背部/顶格不得标 WIDE（否则铺地形跳过 Cliffs → 天窗/多余网格）
	var crest_kind := Wc3CliffTiles.romp_kind_at(romp, tp_w, sx0, sy0 + 2)
	if crest_kind == Wc3CliffTiles.ROMP_WIDE:
		push_error("crest must not be WIDE (back should be cliff models)")
		return 1
	# 侧脊上格仍须挖洞；底格铺地板（不要要求底格也 gap）
	var side_kind := Wc3CliffTiles.romp_kind_at(romp, tp_w, sx0 + 1, sy0)
	if side_kind != Wc3CliffTiles.ROMP_SIDE:
		push_error("side ridge cell must be SIDE, got %d" % side_kind)
		return 1
	var side_upper := Wc3CliffTiles.romp_kind_at(romp, tp_w, sx0 + 1, sy0 + 1)
	if side_upper == Wc3CliffTiles.ROMP_SIDE:
		if not Wc3CliffTiles.should_leave_gap(
			meta["layer_heights"], meta["flags"], tp_w, int(meta["height"]), sx0 + 1, sy0 + 1, romp
		):
			push_error("side ridge upper must gap for CliffTrans")
			return 1
	if Wc3CliffTiles.should_leave_gap(
		meta["layer_heights"], meta["flags"], tp_w, int(meta["height"]), sx0 + 1, sy0, romp
	):
		push_error("side ridge floor must not gap (dirt at foot)")
		return 1
	print("OK width-2 deck=%d wide_cells=%d side_clifftrans=%d mid_ok" % [
		int(built.get("ramp_deck_count", 0)), wide_cells, placed_ramps
	])
	return 0


## 三列宽坡：内部甲板；侧脊 SINGLE；顶/底不铺地形（背部留给 Cliffs）。
func _case_width3_crest_foot_decked() -> int:
	print("=== case: width-3 internal deck, sides SINGLE, crest not WIDE ===")
	var doc = _new_doc()
	_set_layer_rect(doc, 8, 11, 16, 11, 3)
	var r0: Dictionary = doc.try_paint_ramp_at(10, 10)
	var r1: Dictionary = doc.try_paint_ramp_at(11, 10)
	var r2: Dictionary = doc.try_paint_ramp_at(12, 10)
	if not (bool(r0.get("ok", false)) and bool(r1.get("ok", false)) and bool(r2.get("ok", false))):
		push_error("width-3 paint failed")
		return 1
	var sx0: int = int(r0.get("sx", 10))
	var sy0: int = int(r0.get("sy", 9))
	var tiles := Wc3TerrainTiles.new()
	tiles.load_default()
	var meta := HeightfieldMeshBuilder.read_heightfield_meta(doc.hf)
	var ramp_data: Dictionary = Wc3CliffTiles.collect_ramp_placements(doc.hf, meta, tiles)
	var romp: PackedByteArray = ramp_data.get("romp", PackedByteArray())
	var tp_w: int = int(meta["width"])
	# 内部两格 WIDE
	for dx in [0, 1]:
		var k := Wc3CliffTiles.romp_kind_at(romp, tp_w, sx0 + dx, sy0)
		if k != Wc3CliffTiles.ROMP_WIDE:
			push_error("width-3 internal must be WIDE @%d,%d kind=%d" % [sx0 + dx, sy0, k])
			return 1
	# 侧脊 SIDE
	for side_x in [sx0 - 1, sx0 + 2]:
		if side_x < 0:
			continue
		var sk := Wc3CliffTiles.romp_kind_at(romp, tp_w, side_x, sy0)
		if sk == Wc3CliffTiles.ROMP_WIDE or sk == Wc3CliffTiles.ROMP_SINGLE:
			push_error("side must be SIDE not deck @%d,%d kind=%d" % [side_x, sy0, sk])
			return 1
	var right_side := Wc3CliffTiles.romp_kind_at(romp, tp_w, sx0 + 2, sy0)
	if right_side != Wc3CliffTiles.ROMP_SIDE:
		push_error("right side ridge must be SIDE, got %d" % right_side)
		return 1
	# 顶格禁止 WIDE
	for dx2 in [0, 1, 2]:
		var ck := Wc3CliffTiles.romp_kind_at(romp, tp_w, sx0 + dx2, sy0 + 2)
		if ck == Wc3CliffTiles.ROMP_WIDE:
			push_error("crest must not be WIDE @%d,%d" % [sx0 + dx2, sy0 + 2])
			return 1
	var built: Dictionary = Wc3TerrainAutotile.build_ground_mesh(
		doc.hf, PackedByteArray(), tiles, meta, romp, ramp_data.get("placements", [])
	)
	# 仅内部条带甲板（约 2 列 × 2 深 = 4），不应把顶/底算进去
	var deck_n: int = int(built.get("ramp_deck_count", 0))
	if deck_n < 4:
		push_error("width-3 internal deck expected >=4, got %d" % deck_n)
		return 1
	if deck_n > 8:
		push_error("width-3 deck too many (crest/foot leaked?): %d" % deck_n)
		return 1
	print("OK width-3 internal deck=%d sides SINGLE crest clean" % deck_n)
	return 0
