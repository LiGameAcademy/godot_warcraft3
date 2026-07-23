extends SceneTree
## M2 宽坡甲板：双脊 romp 不挖洞、共享边高度连续、地面 mesh 含甲板格。
##
## 运行：
##   godot --headless --path . -s res://tools/selftest_ramp_m2.gd


const DocScript := preload("res://editor/scripts/map_document.gd")
const EPS := 0.05


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _case_wide_deck_continuity()
	failed += _case_single_spine_not_wide_mesh()
	if failed > 0:
		push_error("selftest_ramp_m2 FAILED cases=%d" % failed)
		quit(1)
		return
	print("selftest_ramp_m2 OK")
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


func _case_wide_deck_continuity() -> int:
	print("=== case: wide L|R deck continuity / gap policy ===")
	var doc = _new_doc()
	_set_layer_rect(doc, 8, 11, 16, 11, 3)
	var r0: Dictionary = doc.try_paint_ramp_at(10, 10)
	var r1: Dictionary = doc.try_paint_ramp_at(11, 10)
	if not bool(r0.get("ok", false)) or not bool(r1.get("ok", false)):
		push_error("paint failed: %s / %s" % [str(r0), str(r1)])
		return 1

	var meta := HeightfieldMeshBuilder.read_heightfield_meta(doc.hf)
	var tp_w: int = int(meta["width"])
	var tp_h: int = int(meta["height"])
	var heights: Array = Wc3CliffTiles.apply_ramp_entrance_heights(
		meta["heights"], meta["layer_heights"], meta["flags"], tp_w, tp_h
	)
	var ramp_data: Dictionary = Wc3CliffTiles.collect_ramp_placements(doc.hf, meta)
	var placements: Array = ramp_data.get("placements", []) as Array
	var romp: PackedByteArray = ramp_data.get("romp", PackedByteArray())

	var wide_n := 0
	for p in placements:
		if bool(p.get("wide", false)) and not bool(p.get("phantom", false)):
			wide_n += 1
	if wide_n < 2:
		push_error("expected >=2 wide placements, got %d" % wide_n)
		return 1

	var romp_cells := 0
	var gap_n := 0
	var nan_bad := 0
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			var i00 := iy * tp_w + ix
			if i00 >= romp.size() or romp[i00] == 0:
				continue
			romp_cells += 1
			if Wc3CliffTiles.should_leave_gap(
				meta["layer_heights"], meta["flags"], tp_w, tp_h, ix, iy, romp
			):
				gap_n += 1
			# 仅主条/宽坡格需要坡面采样；侧脊幻影格无甲板平面
			if Wc3CliffTiles.romp_kind_at(romp, tp_w, ix, iy) == Wc3CliffTiles.ROMP_SINGLE:
				var is_phantom_only := true
				for p in placements:
					if bool(p.get("phantom", false)):
						continue
					var pix: int = int(p.get("ix", 0))
					var piy: int = int(p.get("iy", 0))
					if str(p.get("axis", "")) == "v":
						if pix == ix and (piy == iy or piy + 1 == iy):
							is_phantom_only = false
							break
					else:
						if piy == iy and (pix == ix or pix + 1 == ix):
							is_phantom_only = false
							break
				if is_phantom_only:
					continue
			for c in [[ix, iy], [ix + 1, iy], [ix, iy + 1], [ix + 1, iy + 1]]:
				var rh: float = Wc3CliffTiles.sample_ramp_plane_height(
					heights, placements, tp_w, tp_h, float(c[0]), float(c[1])
				)
				if is_nan(rh):
					nan_bad += 1

	if romp_cells < 4:
		push_error("wide romp cells expected >=4, got %d" % romp_cells)
		return 1
	if nan_bad != 0:
		push_error("romp corners missing plane sample: %d" % nan_bad)
		return 1

	var use_deck := Wc3CliffTiles.RAMP_SURFACE_DECK_ENABLED
	var wide_cells := 0
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			if Wc3CliffTiles.romp_kind_at(romp, tp_w, ix, iy) == Wc3CliffTiles.ROMP_WIDE:
				wide_cells += 1
	if use_deck:
		if gap_n != 0:
			push_error("deck-on: romp must not gap, got %d" % gap_n)
			return 1
	else:
		# 关全局甲板时：宽坡不挖洞；SINGLE/SIDE 挖洞
		var ridge_gap := 0
		var wide_gap := 0
		for iy in range(tp_h - 1):
			for ix in range(tp_w - 1):
				var k := Wc3CliffTiles.romp_kind_at(romp, tp_w, ix, iy)
				if k == Wc3CliffTiles.ROMP_NONE:
					continue
				var g := Wc3CliffTiles.should_leave_gap(
					meta["layer_heights"], meta["flags"], tp_w, tp_h, ix, iy, romp
				)
				if k == Wc3CliffTiles.ROMP_WIDE and g:
					wide_gap += 1
				if (k == Wc3CliffTiles.ROMP_SINGLE or k == Wc3CliffTiles.ROMP_SIDE) and g:
					ridge_gap += 1
		if wide_cells < 2:
			push_error("adjacent should produce wide romp cells, got %d" % wide_cells)
			return 1
		if wide_gap != 0:
			push_error("wide cells must not gap (continuous width-2), got %d" % wide_gap)
			return 1
		if ridge_gap < 1:
			push_error("outer side-ridge should gap, got ridge_gap=%d" % ridge_gap)
			return 1

	var tiles := Wc3TerrainTiles.new()
	tiles.load_default()
	var built: Dictionary = Wc3TerrainAutotile.build_ground_mesh(
		doc.hf, PackedByteArray(), tiles, meta, romp, placements
	)
	var deck: int = int(built.get("ramp_deck_count", 0))
	var expect_deck := romp_cells if use_deck else wide_cells
	if deck != expect_deck:
		push_error("mesh ramp_deck_count=%d expected %d" % [deck, expect_deck])
		return 1
	if built.get("mesh", null) == null:
		push_error("ground mesh missing")
		return 1

	print("OK wide romp=%d wide_cells=%d deck=%d gaps=%d" % [romp_cells, wide_cells, deck, gap_n])
	return 0


func _case_single_spine_not_wide_mesh() -> int:
	print("=== case: single spine thin romp (2 cells) ===")
	var doc = _new_doc()
	_set_layer_rect(doc, 8, 11, 12, 11, 3)
	var r: Dictionary = doc.try_paint_ramp_at(10, 10)
	if not bool(r.get("ok", false)):
		push_error("single paint failed: %s" % str(r))
		return 1
	var meta := HeightfieldMeshBuilder.read_heightfield_meta(doc.hf)
	var ramp_data: Dictionary = Wc3CliffTiles.collect_ramp_placements(doc.hf, meta)
	var romp: PackedByteArray = ramp_data.get("romp", PackedByteArray())
	var romp_n := 0
	for b in romp:
		if int(b) != 0:
			romp_n += 1
	if romp_n != 4:
		push_error("single spine romp should be 4 (primary+phantom), got %d" % romp_n)
		return 1
	for p in ramp_data.get("placements", []):
		if bool(p.get("wide", false)) and not bool(p.get("phantom", false)):
			push_error("single spine must not mark wide")
			return 1
	var tiles := Wc3TerrainTiles.new()
	tiles.load_default()
	var built: Dictionary = Wc3TerrainAutotile.build_ground_mesh(
		doc.hf, PackedByteArray(), tiles, meta, romp, ramp_data.get("placements", [])
	)
	var expect_deck := 0
	if Wc3CliffTiles.RAMP_SURFACE_DECK_ENABLED:
		expect_deck = 4
	if int(built.get("ramp_deck_count", 0)) != expect_deck:
		push_error(
			"single deck count should be %d, got %d"
			% [expect_deck, int(built.get("ramp_deck_count", 0))]
		)
		return 1
	print("OK single thin romp=%d deck=%d" % [romp_n, expect_deck])
	return 0
