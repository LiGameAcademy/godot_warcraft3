extends SceneTree
## 斜坡 Present 计划 API 烟雾：dig / entrance / CliffBuilder 可消费 Collect。
## godot --headless --path . -s res://tests/unit/selftest_ramp_present.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_dig_and_entrance_plans()
	_test_builder_from_ramp_placements()
	_test_vertical_ramp_footprint()
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
