extends SceneTree
## HiveWE 对齐落旗自测。
## godot --headless --path . -s res://tests/unit/selftest_ramp_logic.gd

const MapDocumentScript = preload("res://editor/scripts/map_document.gd")

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_h_slope()
	_test_v_slope()
	_test_low_side_intent()
	_test_adjacent_widen()
	_test_diagonal()
	_test_idempotent()
	_test_soften_dirs()
	_test_corner_intent_from_low()
	_test_wall_low_stays_single()
	_test_expand_straight_to_diagonal()
	_test_intent_not_opposite()
	_test_low_side_mouse_pref_not_far_side()
	_test_forbid_opposite_face_ramp()
	_test_l_then_diagonal_half_side()
	_test_single_axis_promotes_to_diagonal()
	_test_far_empty_still_paintable()
	if failed == 0:
		print("selftest_ramp_logic: PASS")
		quit(0)
	else:
		push_error("selftest_ramp_logic: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _make_doc_cliff_edge_h() -> RefCounted:
	# 层：x<=2 高=3；其余低=2 → 点 (2,y) 朝 +X 刷坡
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 8,
		"height": 8,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			var i: int = y * w + x
			doc.heightfield.layer_heights[i] = 3 if x <= 2 else 2
	doc._rebind_logic()
	return doc


func _make_doc_cliff_edge_v() -> RefCounted:
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 8,
		"height": 8,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			var i: int = y * w + x
			doc.heightfield.layer_heights[i] = 3 if y <= 2 else 2
	doc._rebind_logic()
	return doc


func _flag_ramp(doc, x: int, y: int) -> bool:
	var w: int = doc.heightfield.width
	return (int(doc.heightfield.flags_packed[y * w + x]) & Wc3Coords.FLAG_RAMP) != 0


func _test_h_slope() -> void:
	var doc = _make_doc_cliff_edge_h()
	# 高台侧 (2,1)，方向朝低侧 +X… 实际上 x<=2 高，应点 (2,y) 朝 +X
	# 修正：高在左侧，点 (2,1) horizontal=+1
	var r: Dictionary = doc.try_paint_ramp_at(2, 1, 1, 0)
	if not bool(r.get("ok", false)) or not bool(r.get("changed", false)):
		_fail("h_slope expect ok+changed: %s" % str(r))
		return
	var marked: Array = r.get("marked", [])
	if marked.size() < 3:
		_fail("h_slope marked<%d: %s" % [marked.size(), str(marked)])
		return
	if not (_flag_ramp(doc, 2, 1) and _flag_ramp(doc, 3, 1) and _flag_ramp(doc, 4, 1)):
		_fail("h_slope flags missing along +X")
		return
	print("  h_slope OK marked=%s" % str(marked))


func _test_v_slope() -> void:
	var doc = _make_doc_cliff_edge_v()
	var r: Dictionary = doc.try_paint_ramp_at(1, 2, 0, 1)
	if not bool(r.get("ok", false)) or not bool(r.get("changed", false)):
		_fail("v_slope expect ok+changed: %s" % str(r))
		return
	if not (_flag_ramp(doc, 1, 2) and _flag_ramp(doc, 1, 3) and _flag_ramp(doc, 1, 4)):
		_fail("v_slope flags missing along +Y")
		return
	print("  v_slope OK")


func _test_low_side_intent() -> void:
	var doc = _make_doc_cliff_edge_h()
	# 点在低侧 (4,1)：意图解析到高角 (2,1) 朝 +X 落 3 点
	var r: Dictionary = doc.try_paint_ramp_at(4, 1, 1, 0)
	if not bool(r.get("ok", false)) or not bool(r.get("changed", false)):
		_fail("low_side_intent expect ok+changed: %s" % str(r))
		return
	if int(r.get("sx", -1)) != 2 or int(r.get("sy", -1)) != 1:
		_fail("low_side_intent origin expect (2,1) got (%s,%s)" % [str(r.get("sx")), str(r.get("sy"))])
		return
	if not (_flag_ramp(doc, 2, 1) and _flag_ramp(doc, 3, 1) and _flag_ramp(doc, 4, 1)):
		_fail("low_side_intent flags missing along +X")
		return
	print("  low_side_intent OK origin=(%d,%d)" % [int(r.get("sx")), int(r.get("sy"))])


func _test_soften_dirs() -> void:
	var s: Vector2i = Wc3RampPaint.soften_dirs(1.0, 0.3)
	if s != Vector2i(1, 0):
		_fail("soften expect +X only got %s" % str(s))
		return
	var d: Vector2i = Wc3RampPaint.soften_dirs(1.0, 1.0)
	if d != Vector2i(1, 1):
		_fail("soften expect diagonal got %s" % str(d))
		return
	print("  soften_dirs OK")


func _test_corner_intent_from_low() -> void:
	# 外角高台；点在低侧右下，应解析到 (3,3) 对角坡
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 10,
		"height": 10,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			doc.heightfield.layer_heights[y * w + x] = 3 if (x <= 3 and y <= 3) else 2
	doc._rebind_logic()
	var r: Dictionary = doc.try_paint_ramp_at(5, 5, 1, 1)
	if not bool(r.get("ok", false)) or not bool(r.get("changed", false)):
		_fail("corner_intent expect ok: %s" % str(r))
		return
	if int(r.get("sx", -1)) != 3 or int(r.get("sy", -1)) != 3:
		_fail(
			"corner_intent origin expect (3,3) got (%s,%s)"
			% [str(r.get("sx")), str(r.get("sy"))]
		)
		return
	var n: int = (r.get("marked", []) as Array).size()
	if n < 9:
		_fail("corner_intent expect diagonal 9 got %d" % n)
		return
	print("  corner_intent_from_low OK n=%d" % n)


func _test_adjacent_widen() -> void:
	var doc = _make_doc_cliff_edge_h()
	var r1: Dictionary = doc.try_paint_ramp_at(2, 2, 1, 0)
	var r2: Dictionary = doc.try_paint_ramp_at(2, 3, 1, 0)
	if not bool(r1.get("changed", false)) or not bool(r2.get("changed", false)):
		_fail("adjacent_widen: %s / %s" % [str(r1), str(r2)])
		return
	if not (_flag_ramp(doc, 2, 2) and _flag_ramp(doc, 2, 3)):
		_fail("adjacent_widen missing neighbor columns")
		return
	print("  adjacent_widen OK")


func _test_diagonal() -> void:
	# 外角：高台在 x<=3 且 y<=3
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 10,
		"height": 10,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			doc.heightfield.layer_heights[y * w + x] = 3 if (x <= 3 and y <= 3) else 2
	doc._rebind_logic()
	var r: Dictionary = doc.try_paint_ramp_at(3, 3, 1, 1)
	if not bool(r.get("ok", false)):
		_fail("diagonal plan fail: %s" % str(r))
		return
	var n: int = (r.get("marked", []) as Array).size()
	# 对角合法 → 最多 9；否则至少单轴 3
	if n < 3:
		_fail("diagonal marked too few: %d" % n)
		return
	print("  diagonal OK n=%d variant=%s" % [n, str(r.get("variant", ""))])


func _test_idempotent() -> void:
	var doc = _make_doc_cliff_edge_h()
	doc.try_paint_ramp_at(2, 1, 1, 0)
	var r2: Dictionary = doc.try_paint_ramp_at(2, 1, 1, 0)
	if bool(r2.get("changed", false)):
		_fail("idempotent second paint should not change")
		return
	print("  idempotent OK changed=false")


func _test_wall_low_stays_single() -> void:
	# 直墙 + 低侧点击 + 单轴 pref → 必须仍是 3 点单列，不能扩成多列/对角
	var doc = _make_doc_cliff_edge_h()
	var r: Dictionary = doc.try_paint_ramp_at(3, 4, 1, 0)
	if not bool(r.get("changed", false)):
		_fail("wall_low_single expect changed: %s" % str(r))
		return
	var marked: Array = r.get("marked", [])
	if marked.size() != 3:
		_fail("wall_low_single expect 3 marks got %d %s" % [marked.size(), str(marked)])
		return
	if str(r.get("variant", "")) != "straight":
		_fail("wall_low_single expect straight got %s" % str(r.get("variant")))
		return
	var ys: Dictionary = {}
	for v in marked:
		ys[(v as Vector2i).y] = true
	if ys.size() != 1:
		_fail("wall_low_single expect single row got ys=%s" % str(ys.keys()))
		return
	print("  wall_low_stays_single OK")


func _test_expand_straight_to_diagonal() -> void:
	# 外角先单列，再双轴应能扩成对角（HiveWE：对角不过对向轴禁贴）
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 10,
		"height": 10,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			doc.heightfield.layer_heights[y * w + x] = 3 if (x <= 3 and y <= 3) else 2
	doc._rebind_logic()
	var r1: Dictionary = doc.try_paint_ramp_at(3, 3, 1, 0)
	if not bool(r1.get("changed", false)):
		_fail("expand: first straight fail %s" % str(r1))
		return
	var r2: Dictionary = doc.try_paint_ramp_at(3, 3, 1, 1)
	if not bool(r2.get("ok", false)):
		_fail("expand: diagonal plan fail %s" % str(r2))
		return
	if str(r2.get("variant", "")) != "diagonal":
		_fail("expand: expect diagonal got %s marks=%s" % [str(r2.get("variant")), str(r2.get("marked"))])
		return
	var n: int = (r2.get("marked", []) as Array).size()
	if n < 9 and not bool(r2.get("changed", false)):
		# 若旗已部分存在，changed 可能 false，但 variant 应为 diagonal 且至少覆盖对角
		pass
	if n < 5:
		_fail("expand: too few marks %d" % n)
		return
	print("  expand_straight_to_diagonal OK n=%d changed=%s" % [n, str(r2.get("changed"))])


func _test_intent_not_opposite() -> void:
	# 先在外角刷错对角；再在直墙另一侧低点刷单列，原点必须在墙边朝向点击，不能跑到对侧外角
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
	# 高台：x<=4 的竖条（直墙在 x=4|5）
	for y in range(doc.heightfield.height):
		for x in range(w):
			doc.heightfield.layer_heights[y * w + x] = 3 if x <= 4 else 2
	doc._rebind_logic()
	# 对侧/远端外角污染
	doc.try_paint_ramp_at(4, 1, 1, 1)
	var r: Dictionary = doc.try_paint_ramp_at(6, 6, 1, 0)
	if not bool(r.get("changed", false)):
		_fail("intent_not_opposite expect paint: %s" % str(r))
		return
	var sx: int = int(r.get("sx", -1))
	var sy: int = int(r.get("sy", -1))
	if sx != 4 or sy != 6:
		_fail("intent_not_opposite expect origin (4,6) got (%d,%d)" % [sx, sy])
		return
	if str(r.get("variant", "")) != "straight":
		_fail("intent_not_opposite expect straight got %s" % str(r.get("variant")))
		return
	print("  intent_not_opposite OK origin=(%d,%d)" % [sx, sy])


func _test_low_side_mouse_pref_not_far_side() -> void:
	# 截图回归：点在崖脚低地，鼠标偏好朝向高台内侧；必须朝点击落旗，不能刷到高台对侧。
	# 高台 y<=4；点击 (5,6)（距崖边 2）；pref=(0,-1) 指向高台深处。
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
	var r: Dictionary = doc.try_paint_ramp_at(5, 6, 0, -1)
	if not bool(r.get("ok", false)) or not bool(r.get("changed", false)):
		_fail("low_side_pref expect ok: %s" % str(r))
		return
	var sx: int = int(r.get("sx", -1))
	var sy: int = int(r.get("sy", -1))
	# 原点应在崖边朝向点击（y=4），坡向 +Y
	if sy != 4:
		_fail("low_side_pref expect origin on rim y=4 got (%d,%d)" % [sx, sy])
		return
	if not (_flag_ramp(doc, sx, 4) and _flag_ramp(doc, sx, 5) and _flag_ramp(doc, sx, 6)):
		_fail("low_side_pref expect marks toward click along +Y from rim")
		return
	# 对侧（高台深处 / 远离点击）不应落旗
	if _flag_ramp(doc, sx, 2) or _flag_ramp(doc, sx, 3):
		_fail("low_side_pref must not mark far side of plateau")
		return
	print("  low_side_mouse_pref_not_far_side OK origin=(%d,%d)" % [sx, sy])


func _test_forbid_opposite_face_ramp() -> void:
	# 截图1：细高台脊（两侧皆低）。先朝 +Y 落坡，再朝 -Y 必须拒绝（对侧无模）。
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
			# 仅 y==5 为高脊
			doc.heightfield.layer_heights[y * w + x] = 3 if y == 5 else 2
	doc._rebind_logic()
	var r1: Dictionary = doc.try_paint_ramp_at(5, 5, 0, 1)
	if not bool(r1.get("changed", false)):
		_fail("opposite_face setup +Y fail: %s" % str(r1))
		return
	var r2: Dictionary = doc.try_paint_ramp_at(5, 5, 0, -1)
	if bool(r2.get("ok", false)) and bool(r2.get("changed", false)):
		_fail("opposite_face must reject -Y after +Y: %s" % str(r2))
		return
	if _flag_ramp(doc, 5, 4) or _flag_ramp(doc, 5, 3):
		_fail("opposite_face must not mark -Y side")
		return
	print("  forbid_opposite_face_ramp OK")


func _test_l_then_diagonal_half_side() -> void:
	# 截图2：外角先竖臂再横/对角，应能扩成半侧对角，不被侧翼禁贴误伤。
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
			doc.heightfield.layer_heights[y * w + x] = 3 if (x <= 4 and y <= 4) else 2
	doc._rebind_logic()
	var r1: Dictionary = doc.try_paint_ramp_at(4, 4, 0, 1)
	if not bool(r1.get("changed", false)):
		_fail("half_side setup vertical fail: %s" % str(r1))
		return
	# 第二笔：对角意图，应扩成 diagonal 并补上横臂/箱内点
	var r2: Dictionary = doc.try_paint_ramp_at(4, 4, 1, 1)
	if not bool(r2.get("ok", false)) or not bool(r2.get("changed", false)):
		_fail("half_side diagonal expand fail: %s" % str(r2))
		return
	if str(r2.get("variant", "")) != "diagonal":
		_fail("half_side expect diagonal got %s" % str(r2.get("variant")))
		return
	# 半侧：原点 + 竖臂 + 横臂方向上应有旗
	if not (
		_flag_ramp(doc, 4, 4)
		and _flag_ramp(doc, 4, 5)
		and _flag_ramp(doc, 4, 6)
		and _flag_ramp(doc, 5, 4)
		and _flag_ramp(doc, 6, 4)
	):
		_fail("half_side missing L/box arms after expand")
		return
	print("  l_then_diagonal_half_side OK n=%d" % (r2.get("marked", []) as Array).size())


func _test_single_axis_promotes_to_diagonal() -> void:
	# 截图：外角已有竖臂，再只传单轴横意图 → 应自动升为对角半侧
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
			doc.heightfield.layer_heights[y * w + x] = 3 if (x <= 4 and y <= 4) else 2
	doc._rebind_logic()
	var r1: Dictionary = doc.try_paint_ramp_at(4, 4, 0, 1)
	if not bool(r1.get("changed", false)):
		_fail("promote setup vertical fail: %s" % str(r1))
		return
	# 仅 hx=1（不传 hy）——旧逻辑会落第二条单侧；新逻辑应升对角
	var r2: Dictionary = doc.try_paint_ramp_at(4, 4, 1, 0)
	if not bool(r2.get("ok", false)) or not bool(r2.get("changed", false)):
		_fail("promote single→diagonal fail: %s" % str(r2))
		return
	if str(r2.get("variant", "")) != "diagonal":
		_fail("promote expect diagonal got %s" % str(r2.get("variant")))
		return
	if not (_flag_ramp(doc, 5, 4) and _flag_ramp(doc, 6, 4) and _flag_ramp(doc, 5, 5)):
		_fail("promote missing diagonal box fills")
		return
	print("  single_axis_promotes_to_diagonal OK n=%d" % (r2.get("marked", []) as Array).size())


func _test_far_empty_still_paintable() -> void:
	# 截图3：崖缘一侧已有坡时，远处另一段空崖仍可落直坡。
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 16,
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
	var r1: Dictionary = doc.try_paint_ramp_at(3, 4, 0, 1)
	if not bool(r1.get("changed", false)):
		_fail("far_empty setup fail: %s" % str(r1))
		return
	var r2: Dictionary = doc.try_paint_ramp_at(10, 4, 0, 1)
	if not bool(r2.get("ok", false)) or not bool(r2.get("changed", false)):
		_fail("far_empty should still paint: %s" % str(r2))
		return
	if not (_flag_ramp(doc, 10, 4) and _flag_ramp(doc, 10, 5) and _flag_ramp(doc, 10, 6)):
		_fail("far_empty marks missing")
		return
	print("  far_empty_still_paintable OK")
