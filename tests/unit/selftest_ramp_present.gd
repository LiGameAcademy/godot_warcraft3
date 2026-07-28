extends SceneTree
## 斜坡 Present 计划 API 烟雾：dig / entrance / CliffBuilder 可消费 Collect。
## godot --headless --path . -s res://tests/unit/selftest_ramp_present.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_dig_and_entrance_plans()
	_test_entrance_height_boost()
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
	var entrances: Array[Vector2i] = Wc3RampLogic.plan_entrance_tiles(hf)
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
	# 入口格在 dig 中必须为 0
	var map_w: int = hf.width - 1
	for t in entrances:
		var i: int = t.y * map_w + t.x
		if i >= 0 and i < dig.size() and dig[i] != 0:
			_fail("entrance still dug @%s" % str(t))
			return
	print(
		"  dig_entrance OK dig=%d entrances=%d placements=%d"
		% [dig_n, entrances.size(), ramp.non_phantom_count()]
	)


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

	var hide_low: bool = Wc3RampLogic.should_hide_cliff_piece(
		cliff_ix, cliff_iy, low_base, doc.heightfield, ramp
	)
	var hide_high: bool = Wc3RampLogic.should_hide_cliff_piece(
		cliff_ix, cliff_iy, high_base, doc.heightfield, ramp
	)
	if not hide_low:
		_fail("hide_slice low base=%d should hide" % low_base)
		return
	if hide_high:
		_fail("hide_slice high base=%d must stay" % high_base)
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
	print("  hide_slice OK low=%d hide high=%d stay" % [low_base, high_base])


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

	var filtered: Array[Wc3CliffPlacement] = Wc3RampLogic.filter_cliff_placements(
		raw, doc.heightfield, ramp
	)
	if filtered.size() != 2:
		_fail("filter expect 2 kept got %d" % filtered.size())
		return
	var bases: Dictionary = {}
	for p in filtered:
		bases[p.base_layer] = true
		if p.ix == cliff_ix and p.iy == cliff_iy and p.base_layer == low_base:
			_fail("filter still has low slice")
			return
	if not bases.has(high_base):
		_fail("filter dropped high slice")
		return
	if not bases.has(low_base):
		# far tile (1,1) may keep low_base — OK
		pass
	var far_ok := false
	for p in filtered:
		if p.ix == 1 and p.iy == 1:
			far_ok = true
	if not far_ok:
		_fail("filter dropped far tile")
		return
	print("  filter_placements OK kept=%d" % filtered.size())
