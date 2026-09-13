extends SceneTree
## 斜坡 Present 计划 API 烟雾：dig / entrance / CliffBuilder 可消费 Collect。
## godot --headless --path . -s res://tests/unit/selftest_ramp_present.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_completed_outer_corners()
	_test_dig_and_entrance_plans()
	_test_footprint_both_tiles_dug()
	_test_entrance_height_boost()
	_test_l_recess_entrance()
	_test_l_recess_not_fake_diagonal()
	_test_outer_corner_l_arm_undig()
	_test_widen_keeps_footprint_dug()
	_test_l_corner_clifftrans()
	_test_no_clifftrans_keeps_ground()
	_test_builder_from_ramp_placements()
	_test_vertical_ramp_footprint()
	_test_hide_cliff_piece_by_slice()
	_test_filter_cliff_placements()
	if failed == 0:
		print("selftest_ramp_present: PASS")
		quit(0)
	else:
		push_error("selftest_ramp_present: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_dig_and_entrance_plans() -> void:
	var path := "res://assets/map-parsed/losttemple/terrain-heightfield.json"
	if not FileAccess.file_exists(path):
		print("  dig_entrance SKIP (no map)")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var raw: Variant = JSON.parse_string(f.get_as_text())
	var hf := Wc3Heightfield.from_dict(raw as Dictionary, false)
	var cat := Wc3CliffCatalog.new()
	cat.load_default()
	var ramp: Wc3RampCollectResult = Wc3RampLogic.collect_placements(hf, {}, cat)
	var dig: PackedByteArray = Wc3RampLogic.plan_dig_mask(hf, ramp)
	var entrances: Array[Vector2i] = Wc3RampLogic.plan_entrance_tiles(hf, ramp)
	if dig.is_empty():
		_fail("dig mask empty")
		return
	var dig_n := 0
	for i in range(dig.size()):
		if dig[i] != 0:
			dig_n += 1
	if dig_n <= 0:
		_fail("dig mask all zero on Lost Temple")
		return
	# 入口格在 dig 中必须为 0（已排除 footprint/romp 坡身）
	var map_w: int = hf.width - 1
	for t in entrances:
		var i: int = t.y * map_w + t.x
		if i >= 0 and i < dig.size() and dig[i] != 0:
			_fail("entrance still dug @%s" % str(t))
			return
	# footprint 必须挖开（即使用 is_entrance 为真也不能 undig）
	for p in ramp.placements:
		if p == null or not p.has_glb:
			continue
		for t2 in Wc3RampCollect.placement_footprint_tiles(p):
			var di: int = t2.y * map_w + t2.x
			if di < 0 or di >= dig.size() or dig[di] == 0:
				_fail("Lost Temple footprint not dug %s" % str(t2))
				return
	print(
		"  dig_entrance OK dig=%d entrances=%d placements=%d"
		% [dig_n, entrances.size(), ramp.non_phantom_count()]
	)


func _test_footprint_both_tiles_dug() -> void:
	# CliffTrans 占 2 格：崖格 + 探出格；dig 必须两格都挖（探出格无 cliff，只靠 romp/footprint）
	const MapDocumentScript = preload("res://editor/scripts/map_document.gd")
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 16,
		"height": 16,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var hf: Wc3Heightfield = doc.heightfield
	var w: int = hf.width
	for y in range(hf.height):
		for x in range(w):
			hf.layer_heights[y * w + x] = 3 if y <= 8 else 2
			hf.heights[y * w + x] = float(int(hf.layer_heights[y * w + x]) - 2) * 128.0
	doc._rebind_logic()
	if not bool(doc.try_paint_ramp_at(5, 8, 0, 1).get("changed", false)):
		_fail("footprint dig paint fail")
		return
	if not bool(doc.try_paint_ramp_at(6, 8, 0, 1).get("changed", false)):
		_fail("footprint dig widen fail")
		return
	var cat := Wc3CliffCatalog.new()
	cat.load_default()
	var ramp: Wc3RampCollectResult = Wc3RampLogic.collect_placements(hf, {}, cat)
	if ramp.placements.is_empty():
		_fail("footprint dig no placements")
		return
	var dig: PackedByteArray = Wc3RampLogic.plan_dig_mask(hf, ramp)
	var map_w: int = w - 1
	for p in ramp.placements:
		var fp: Array[Vector2i] = Wc3RampCollect.placement_footprint_tiles(p)
		if fp.size() != 2:
			_fail("footprint expect 2 tiles got %d tag=%s" % [fp.size(), p.tag])
			return
		for t in fp:
			var di: int = t.y * map_w + t.x
			if di < 0 or di >= dig.size() or dig[di] == 0:
				_fail(
					"footprint tile %s not dug tag=%s axis=%s (CliffTrans 两格都应挖)"
					% [str(t), p.tag, p.axis]
				)
				return
			var is_c: bool = Wc3CliffLogic.is_cliff_tile(hf.layer_heights, w, t.x, t.y)
			# 至少有一格是探出格（非 cliff）——否则测不到 romp dig
			pass
		var has_protrusion := false
		for t2 in fp:
			if not Wc3CliffLogic.is_cliff_tile(hf.layer_heights, w, t2.x, t2.y):
				has_protrusion = true
		if not has_protrusion:
			_fail("expected a non-cliff protrusion tile in footprint")
			return
	print("  footprint_both_dug OK placements=%d" % ramp.placements.size())


func _test_entrance_height_boost() -> void:
	# 手工入口：四角 FLAG_RAMP + 层差；低侧两角应 boost。
	const MapDocumentScript = preload("res://editor/scripts/map_document.gd")
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 8,
		"height": 8,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var hf: Wc3Heightfield = doc.heightfield
	var w: int = hf.width
	var ix := 3
	var iy := 3
	# bl/br=2（低）, tl/tr=3（高）— 非对角平坦
	for dy in range(2):
		for dx in range(2):
			var i: int = (iy + dy) * w + (ix + dx)
			hf.layer_heights[i] = 3 if dy == 1 else 2
			hf.flags_packed[i] = int(hf.flags_packed[i]) | Wc3Coords.FLAG_RAMP
	var boost: PackedByteArray = Wc3RampLogic.plan_entrance_height_boost(hf)
	if boost.is_empty() or boost.size() != w * hf.height:
		_fail("boost size mismatch")
		return
	var i00: int = iy * w + ix
	if boost[i00] == 0 or boost[i00 + 1] == 0:
		_fail("boost low corners missing")
		return
	if boost[i00 + w] != 0 or boost[i00 + w + 1] != 0:
		_fail("boost high corners should stay 0")
		return
	# 非入口格不应全图乱标
	var n := 0
	for i in range(boost.size()):
		if boost[i] != 0:
			n += 1
	if n != 2:
		_fail("boost expect 2 corners got %d" % n)
		return
	print("  entrance_boost OK low=%d,%d" % [i00, i00 + 1])


func _test_l_recess_entrance() -> void:
	# L 高台内角 + 两臂 + L 补心：三高一低格应作入口（undig + 低角 +0.5），形成凹陷坡。
	const MapDocumentScript = preload("res://editor/scripts/map_document.gd")
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 20,
		"height": 20,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var hf: Wc3Heightfield = doc.heightfield
	var w: int = hf.width
	for y in range(hf.height):
		for x in range(w):
			var hi: bool = (x <= 12 and y <= 10) or (x <= 10 and y <= 14)
			hf.layer_heights[y * w + x] = 3 if hi else 2
			hf.heights[y * w + x] = float(int(hf.layer_heights[y * w + x]) - 2) * 128.0
	doc._rebind_logic()
	if not bool(doc.try_paint_ramp_at(11, 10, 0, 1).get("changed", false)):
		_fail("l_recess paint down fail")
		return
	if not bool(doc.try_paint_ramp_at(10, 11, 1, 0).get("changed", false)):
		_fail("l_recess paint right fail")
		return
	_assert_source_cells(hf, "_test_l_recess_entrance")


func _test_l_recess_not_fake_diagonal() -> void:
	# L 凹槽 2×2 四格全部 undig+藏崖；只 boost 凹陷低角 1 个（不把三兄弟抬成伪对角）
	const MapDocumentScript = preload("res://editor/scripts/map_document.gd")
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 20,
		"height": 20,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var hf: Wc3Heightfield = doc.heightfield
	var w: int = hf.width
	for y in range(hf.height):
		for x in range(w):
			var hi: bool = (x <= 12 and y <= 10) or (x <= 10 and y <= 14)
			hf.layer_heights[y * w + x] = 3 if hi else 2
			hf.heights[y * w + x] = float(int(hf.layer_heights[y * w + x]) - 2) * 128.0
	doc._rebind_logic()
	if not bool(doc.try_paint_ramp_at(11, 10, 0, 1).get("changed", false)):
		_fail("l2x2 paint down fail")
		return
	if not bool(doc.try_paint_ramp_at(10, 11, 1, 0).get("changed", false)):
		_fail("l2x2 paint right fail")
		return
	_assert_source_cells(hf, "_test_l_recess_not_fake_diagonal")


func _test_outer_corner_l_arm_undig() -> void:
	# 小高台 + L 臂旗落在邻边（外角格自身 nr=0）→ 外角碗 undig/清 dig/藏崖
	# 回归用户场景：entrances=0 导致藏崖灰缝
	const MapDocumentScript = preload("res://editor/scripts/map_document.gd")
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 32,
		"height": 32,
		"main_tileset": "L",
		"ground_tilesets": ["Ldrt"],
		"cliff_tilesets": ["CLdi"],
		"cliff_level": 2,
	})
	# 抬高 3×3 顶点 → 高台
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			doc.paint_cliff_corner(15 + dx, 16 + dy, "3", 0, -1)
	doc._rebind_logic()
	var hf: Wc3Heightfield = doc.heightfield
	var w: int = hf.width
	# 西臂 + 南臂 + 东侧 L 邻边旗（不落在 SE 外角格本身）
	for p in [
		Vector2i(15, 13), Vector2i(15, 14), Vector2i(15, 15),
		Vector2i(12, 16), Vector2i(13, 16), Vector2i(14, 16),
		Vector2i(16, 15), Vector2i(16, 16), Vector2i(17, 16),
	]:
		hf.flags_packed[p.y * w + p.x] = int(hf.flags_packed[p.y * w + p.x]) | Wc3Coords.FLAG_RAMP
	_assert_source_cells(hf, "_test_outer_corner_l_arm_undig")


func _test_widen_keeps_footprint_dug() -> void:
	# 回归：先单列再邻列加宽 → 入口判定变真，但原 CliffTrans footprint 仍必须挖开
	const MapDocumentScript = preload("res://editor/scripts/map_document.gd")
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 16,
		"height": 16,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var hf: Wc3Heightfield = doc.heightfield
	var w: int = hf.width
	for y in range(hf.height):
		for x in range(w):
			hf.layer_heights[y * w + x] = 3 if x <= 6 else 2
			hf.heights[y * w + x] = float(int(hf.layer_heights[y * w + x]) - 2) * 128.0
	doc._rebind_logic()
	if not bool(doc.try_paint_ramp_at(6, 5, 1, 0).get("changed", false)):
		_fail("widen_fp first paint fail")
		return
	var cat := Wc3CliffCatalog.new()
	cat.load_default()
	var ramp1: Wc3RampCollectResult = Wc3RampLogic.collect_placements(hf, {}, cat)
	if ramp1.placements.is_empty():
		_fail("widen_fp no placement after first")
		return
	var fp0: Array[Vector2i] = Wc3RampCollect.placement_footprint_tiles(ramp1.placements[0])
	if not bool(doc.try_paint_ramp_at(6, 6, 1, 0).get("changed", false)):
		_fail("widen_fp second paint fail")
		return
	var ramp2: Wc3RampCollectResult = Wc3RampLogic.collect_placements(hf, {}, cat)
	var dig: PackedByteArray = Wc3RampLogic.plan_dig_mask(hf, ramp2)
	var entrances: Array[Vector2i] = Wc3RampLogic.plan_entrance_tiles(hf, ramp2)
	var map_w: int = w - 1
	for t in fp0:
		var di: int = t.y * map_w + t.x
		if dig[di] == 0:
			_fail("widen_fp original footprint undug after widen %s" % str(t))
			return
		for e in entrances:
			if e == t:
				_fail("widen_fp footprint listed as entrance undig %s" % str(t))
				return
	print(
		"  widen_keeps_footprint_dug OK fp=%s entrances=%d placements=%d"
		% [str(fp0), entrances.size(), ramp2.placements.size()]
	)


func _test_l_corner_clifftrans() -> void:
	# 双臂 L 转角：中格被另一臂污染时仍应匹配 LABH/BALH（凹陷坡身）
	const MapDocumentScript = preload("res://editor/scripts/map_document.gd")
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 20,
		"height": 20,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var hf: Wc3Heightfield = doc.heightfield
	var w: int = hf.width
	for y in range(hf.height):
		for x in range(w):
			var hi: bool = (x <= 12 and y <= 10) or (x <= 10 and y <= 14)
			hf.layer_heights[y * w + x] = 3 if hi else 2
			hf.heights[y * w + x] = float(int(hf.layer_heights[y * w + x]) - 2) * 128.0
	doc._rebind_logic()
	if not bool(doc.try_paint_ramp_at(11, 10, 0, 1).get("changed", false)):
		_fail("l_corner_ct paint down fail")
		return
	if not bool(doc.try_paint_ramp_at(10, 11, 1, 0).get("changed", false)):
		_fail("l_corner_ct paint right fail")
		return
	_assert_source_cells(hf, "_test_l_corner_clifftrans")


func _test_no_clifftrans_keeps_ground() -> void:
	# 无 CliffTrans：L 碗 2×2 四格 undig；凹槽 hide；dig=0
	const MapDocumentScript = preload("res://editor/scripts/map_document.gd")
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 20,
		"height": 20,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var hf: Wc3Heightfield = doc.heightfield
	var w: int = hf.width
	for y in range(hf.height):
		for x in range(w):
			var hi: bool = (x <= 12 and y <= 10) or (x <= 10 and y <= 14)
			hf.layer_heights[y * w + x] = 3 if hi else 2
			hf.heights[y * w + x] = float(int(hf.layer_heights[y * w + x]) - 2) * 128.0
	doc._rebind_logic()
	if not bool(doc.try_paint_ramp_at(11, 10, 0, 1).get("changed", false)):
		_fail("no_ct paint down fail")
		return
	if not bool(doc.try_paint_ramp_at(10, 11, 1, 0).get("changed", false)):
		_fail("no_ct paint right fail")
		return
	_assert_source_cells(hf, "_test_no_clifftrans_keeps_ground")


func _count_ones(mask: PackedByteArray) -> int:
	var n := 0
	for i in range(mask.size()):
		if mask[i] != 0:
			n += 1
	return n


func _test_builder_from_ramp_placements() -> void:
	var path := "res://assets/map-parsed/losttemple/terrain-heightfield.json"
	if not FileAccess.file_exists(path):
		print("  builder SKIP (no map)")
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var raw: Variant = JSON.parse_string(f.get_as_text())
	var hf := Wc3Heightfield.from_dict(raw as Dictionary, false)
	var cat := Wc3CliffCatalog.new()
	cat.load_default()
	var ramp: Wc3RampCollectResult = Wc3RampLogic.collect_placements(hf, {}, cat)
	var built: Wc3CliffBuildResult = Wc3CliffBuilder.build_from_ramp_placements(
		ramp.placements, cat, hf.center_offset, hf.tile_size
	)
	if built.placed_cliffs <= 0 or built.groups.is_empty():
		_fail("CliffBuilder placed 0 from ramp placements")
		return
	if built.groups[0].tiles.size() != built.groups[0].transforms.size():
		_fail("Group tiles/transforms length mismatch")
		return
	# 解旋 Basis：直崖是均匀缩放，CliffTrans 第三列为 (-s,0,0)
	var xf: Transform3D = built.groups[0].transforms[0]
	var s: float = Wc3Coords.WORLD_SCALE
	if not xf.basis.x.is_equal_approx(Vector3(0.0, 0.0, s)):
		_fail("trans basis.x expect (0,0,s) got %s" % str(xf.basis.x))
		return
	if not xf.basis.z.is_equal_approx(Vector3(-s, 0.0, 0.0)):
		_fail("trans basis.z expect (-s,0,0) got %s" % str(xf.basis.z))
		return
	print(
		"  builder OK placed=%d groups=%d missing=%d"
		% [built.placed_cliffs, built.groups.size(), built.missing]
	)


func _test_vertical_ramp_footprint() -> void:
	# 垂直坡 TAG 的 mesh 在解旋后应沿 map-Y 拉长（Godot -Z），而非 map-X
	const MapDocumentScript = preload("res://editor/scripts/map_document.gd")
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 12,
		"height": 12,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			doc.heightfield.layer_heights[y * w + x] = 3 if y <= 4 else 2
	doc._rebind_logic()
	if not bool(doc.try_paint_ramp_at(5, 4, 0, 1).get("changed", false)):
		_fail("vertical footprint paint fail")
		return
	var cat := Wc3CliffCatalog.new()
	cat.load_default()
	var ramp: Wc3RampCollectResult = Wc3RampLogic.collect_placements(doc.heightfield, {}, cat)
	if ramp.placements.is_empty():
		_fail("vertical footprint no placements")
		return
	var p: Wc3RampPlacement = ramp.placements[0]
	var glb: String = cat.resolve_glb(p.model_dir, p.tag, p.variation)
	var cache := MapModelCache.new()
	var mesh: Mesh = cache.mesh_from_glb(glb)
	if mesh == null:
		_fail("vertical footprint mesh null %s" % p.tag)
		return
	var xf: Transform3D = Wc3CliffBuilder.instance_transform_trans(
		p.ix, p.iy, p.base_layer, doc.heightfield.center_offset, doc.heightfield.tile_size
	)
	var local: AABB = mesh.get_aabb()
	var mn := Vector3(INF, INF, INF)
	var mx := Vector3(-INF, -INF, -INF)
	for dx in [0.0, 1.0]:
		for dy in [0.0, 1.0]:
			for dz in [0.0, 1.0]:
				var world_pt: Vector3 = xf * (local.position + local.size * Vector3(dx, dy, dz))
				mn = mn.min(world_pt)
				mx = mx.max(world_pt)
	var span_x: float = mx.x - mn.x
	var span_z: float = mx.z - mn.z
	# 解旋后：原 mesh X=256 → 世界 |Z|≈2.56；原 mesh Z=128 → 世界 |X|≈1.28
	if span_z < span_x * 1.2:
		_fail(
			"vertical footprint wrong orient tag=%s span_x=%.2f span_z=%.2f (expect Z>X)"
			% [p.tag, span_x, span_z]
		)
		return
	print("  vertical_footprint OK tag=%s span_x=%.2f span_z=%.2f" % [p.tag, span_x, span_z])


func _test_hide_cliff_piece_by_slice() -> void:
	# 不依赖 Paint（Paint 只认层差 1）；手工摆一层高崖 + 一条 footprint 坡。
	# 跨度 4 → 两块叠段 base=2 / base=4；坡 base=2 → 只藏下层。
	const MapDocumentScript = preload("res://editor/scripts/map_document.gd")
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 12,
		"height": 12,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			doc.heightfield.layer_heights[y * w + x] = 6 if y <= 4 else 2
	doc._rebind_logic()

	var cliff_ix := 5
	var cliff_iy := 4
	var slices: Array = Wc3CliffLogic.cliff_slices_at(
		doc.heightfield.layer_heights, w, cliff_ix, cliff_iy
	)
	if slices.size() < 2:
		_fail("hide_slice expect >=2 slices got %d @(%d,%d)" % [slices.size(), cliff_ix, cliff_iy])
		return
	var low_base: int = int(slices[0].get("base_layer", -1))
	var high_base: int = int(slices[1].get("base_layer", -1))
	if low_base >= high_base:
		_fail("hide_slice base order %d >= %d" % [low_base, high_base])
		return

	var ramp := Wc3RampCollectResult.empty_for_size(w, doc.heightfield.height)
	ramp.placements.append(
		Wc3RampPlacement.make(
			cliff_ix, cliff_iy, "ALHB", low_base, 0, "CliffTrans", Wc3RampPlacement.AXIS_V, 0, true
		)
	)

	ramp.romp[cliff_iy * w + cliff_ix] = 1
	ramp.romp[(cliff_iy + 1) * w + cliff_ix] = 1
	var hide_low: bool = Wc3RampLogic.should_hide_cliff_piece(
		cliff_ix, cliff_iy, low_base, doc.heightfield, ramp
	)
	var hide_high: bool = Wc3RampLogic.should_hide_cliff_piece(
		cliff_ix, cliff_iy, high_base, doc.heightfield, ramp
	)
	if not hide_low:
		_fail("hide_slice low base=%d should hide" % low_base)
		return
	if not hide_high:
		_fail("romp replaces the cliff tile at every slice, as HiveWE does")
		return
	# footprint 第二格 (ix, iy+1) 同规则
	if not Wc3RampLogic.should_hide_cliff_piece(
		cliff_ix, cliff_iy + 1, low_base, doc.heightfield, ramp
	):
		_fail("hide_slice footprint second tile low should hide")
		return
	if Wc3RampLogic.should_hide_cliff_piece(1, 1, low_base, doc.heightfield, ramp):
		_fail("hide_slice far tile must not hide")
		return
	print("  hide_slice OK low=%d hide high=%d hide" % [low_base, high_base])


func _test_filter_cliff_placements() -> void:
	# filter 后：下层 placement 消失、上层保留（挂模前跳过，非零缩放）
	const MapDocumentScript = preload("res://editor/scripts/map_document.gd")
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 12,
		"height": 12,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			doc.heightfield.layer_heights[y * w + x] = 6 if y <= 4 else 2
	doc._rebind_logic()

	var cliff_ix := 5
	var cliff_iy := 4
	var slices: Array = Wc3CliffLogic.cliff_slices_at(
		doc.heightfield.layer_heights, w, cliff_ix, cliff_iy
	)
	if slices.size() < 2:
		_fail("filter expect >=2 slices")
		return
	var low_base: int = int(slices[0].get("base_layer", -1))
	var high_base: int = int(slices[1].get("base_layer", -1))

	var raw: Array[Wc3CliffPlacement] = []
	raw.append(Wc3CliffPlacement.make(cliff_ix, cliff_iy, "CAAC", low_base, 0, "Cliffs", 0))
	raw.append(Wc3CliffPlacement.make(cliff_ix, cliff_iy, "CAAC", high_base, 0, "Cliffs", 0))
	raw.append(Wc3CliffPlacement.make(1, 1, "AACA", low_base, 0, "Cliffs", 0))

	var ramp := Wc3RampCollectResult.empty_for_size(w, doc.heightfield.height)
	ramp.placements.append(
		Wc3RampPlacement.make(
			cliff_ix, cliff_iy, "ALHB", low_base, 0, "CliffTrans", Wc3RampPlacement.AXIS_V, 0, true
		)
	)

	ramp.romp[cliff_iy * w + cliff_ix] = 1
	ramp.romp[(cliff_iy + 1) * w + cliff_ix] = 1
	var filtered: Array[Wc3CliffPlacement] = Wc3RampLogic.filter_cliff_placements(
		raw, doc.heightfield, ramp
	)
	if filtered.size() != 1 or filtered[0].ix != 1 or filtered[0].iy != 1:
		_fail("romp must replace both cliff slices while retaining the distant cliff")
	print("  filter_placements checked cell-level replacement")


func _test_completed_outer_corners() -> void:
	for dx in [-1, 1]:
		for dy in [-1, 1]:
			var doc = preload("res://editor/scripts/map_document.gd").new()
			doc.create_from_options({"width": 16, "height": 16, "main_tileset": "L", "ground_tilesets": ["Ldrt"], "cliff_tilesets": ["CLdi"]})
			var hf: Wc3Heightfield = doc.heightfield
			for y in range(hf.height):
				for x in range(hf.width):
					hf.layer_heights[y * hf.width + x] = 3 if (x - 8) * dx <= 0 and (y - 8) * dy <= 0 else 2
			doc._rebind_logic()
			doc.try_paint_ramp_at(8, 8, dx, 0)
			doc.try_paint_ramp_at(8, 8, 0, dy)
			var cat := Wc3CliffCatalog.new()
			cat.load_default()
			var ramp := Wc3RampLogic.collect_placements(hf, {}, cat)
			var entrances := Wc3RampLogic.plan_entrance_tiles(hf, ramp)
			var corner := Vector2i(8 if dx > 0 else 7, 8 if dy > 0 else 7)
			var covered := entrances.has(corner)
			for placement in ramp.placements:
				for tile in Wc3RampCollect.placement_footprint_tiles(placement):
					if tile == corner:
						covered = true
					if entrances.has(tile):
						_fail("outer corner ground must not cover CT footprint %s" % tile)
			if not covered:
				_fail("completed outer corner must have ground or CT coverage %s" % corner)
	print("  completed_outer_corners checked four orientations")

func _assert_source_cells(hf: Wc3Heightfield, label: String) -> void:
	var ramp := Wc3RampLogic.collect_placements(hf)
	var entries := Wc3RampLogic.plan_entrance_tiles(hf, ramp)
	var boosts := Wc3RampLogic.plan_entrance_height_boost(hf, ramp)
	var expected_boost := PackedByteArray()
	expected_boost.resize(hf.width * hf.height)
	for y in range(hf.height - 1):
		for x in range(hf.width - 1):
			var ids := [y * hf.width + x, y * hf.width + x + 1, (y + 1) * hf.width + x, (y + 1) * hf.width + x + 1]
			var all_flags := true
			var levels: Array[int] = []
			for i in ids:
				all_flags = all_flags and (int(hf.flags_packed[i]) & Wc3Coords.FLAG_RAMP) != 0
				levels.append(int(hf.layer_heights[i]))
			var entrance := all_flags and not (levels[0] == levels[3] and levels[1] == levels[2])
			if entries.has(Vector2i(x, y)) != entrance:
				_fail(label + " ground differs from source entrance")
			if entrance:
				for k in range(4):
					if levels[k] == levels.min():
						expected_boost[ids[k]] = 1
			var hide := entrance or ramp.romp[ids[0]] != 0
			if Wc3RampLogic.should_hide_cliff_piece(x, y, 2, hf, ramp) != hide:
				_fail(label + " cliff visibility differs from source")
	if boosts != expected_boost:
		_fail(label + " heights differ from source")
	print("  " + label + " checked source ground/height/cliff consistency")
