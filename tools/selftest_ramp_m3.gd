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
	failed += _case_adjacent_ground_not_warped()
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
	var tp_w: int = int(meta["width"])
	var tp_h: int = int(meta["height"])
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			var i00 := iy * tp_w + ix
			if i00 >= romp.size() or romp[i00] == 0:
				continue
			romp_n += 1
			if Wc3CliffTiles.should_leave_gap(
				meta["layer_heights"], meta["flags"], tp_w, tp_h, ix, iy, romp
			):
				gap_n += 1
	if romp_n < 2:
		push_error("expected romp>=2, got %d" % romp_n)
		return 1
	if gap_n != romp_n:
		push_error("deck-off: all romp should gap, gap=%d romp=%d" % [gap_n, romp_n])
		return 1

	var built: Dictionary = Wc3TerrainAutotile.build_ground_mesh(
		doc.hf, PackedByteArray(), tiles, meta, romp, placements
	)
	if int(built.get("ramp_deck_count", -1)) != 0:
		push_error("deck-off: ramp_deck_count should be 0, got %d" % int(built.get("ramp_deck_count", -1)))
		return 1

	var cliffs: Dictionary = Wc3CliffBuilder.collect_instances(doc.hf, tiles, meta, ramp_data)
	var placed_ramps: int = int(cliffs.get("placed_ramps", 0))
	if placed_ramps < 1:
		push_error("expected CliffTrans placed>=1, got %d missing=%s" % [
			placed_ramps, str(cliffs.get("missing", 0))
		])
		return 1
	# romp 格不应再放直崖；侧脊幻影格也须标 romp（否则 CliffTrans 下叠直崖接缝）
	var phantom_romp_miss := 0
	for p in placements:
		if not bool(p.get("phantom", false)):
			continue
		var pix: int = int(p.get("ix", 0))
		var piy: int = int(p.get("iy", 0))
		if str(p.get("axis", "")) == "v":
			if Wc3CliffTiles.romp_kind_at(romp, tp_w, pix, piy) == 0:
				phantom_romp_miss += 1
			if Wc3CliffTiles.romp_kind_at(romp, tp_w, pix, piy + 1) == 0:
				phantom_romp_miss += 1
		else:
			if Wc3CliffTiles.romp_kind_at(romp, tp_w, pix, piy) == 0:
				phantom_romp_miss += 1
			if Wc3CliffTiles.romp_kind_at(romp, tp_w, pix + 1, piy) == 0:
				phantom_romp_miss += 1
	if phantom_romp_miss > 0:
		push_error("phantom side-ridge cells must be in romp (suppress Cliffs), miss=%d" % phantom_romp_miss)
		return 1
	print("OK CliffTrans=%d romp_gap=%d deck=0 phantoms_in_romp" % [placed_ramps, gap_n])
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
	if wide_cells < 4:
		push_error("expected wide continuous cells >=4, got %d" % wide_cells)
		return 1
	var cliffs: Dictionary = Wc3CliffBuilder.collect_instances(doc.hf, tiles, meta, ramp_data)
	# 宽坡：外侧幻影 CliffTrans（侧脊）；主条不放
	var placed_ramps: int = int(cliffs.get("placed_ramps", 0))
	if placed_ramps < 1:
		push_error("wide ramp should place outer side CliffTrans, got %d" % placed_ramps)
		return 1
	var built: Dictionary = Wc3TerrainAutotile.build_ground_mesh(
		doc.hf, PackedByteArray(), tiles, meta, romp, placements
	)
	if int(built.get("ramp_deck_count", 0)) < 4:
		push_error("width-2 should deck >=4, got %d" % int(built.get("ramp_deck_count", 0)))
		return 1
	print("OK width-2 deck=%d wide_cells=%d side_clifftrans=%d" % [
		int(built.get("ramp_deck_count", 0)), wide_cells, placed_ramps
	])
	return 0
