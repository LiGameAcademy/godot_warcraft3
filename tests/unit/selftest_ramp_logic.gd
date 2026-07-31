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
	_test_expand_straight_to_l()
	_test_intent_not_opposite()
	_test_low_side_mouse_pref_not_far_side()
	_test_allow_opposite_face_ramp()
	_test_l_then_complete_with_center()
	_test_single_axis_keeps_straight_second_arm()
	_test_dual_arms_se_plus_l_fill()
	_test_fresh_corner_diagonal()
	_test_far_empty_still_paintable()
	_test_cliff_change_clears_nearby_ramp()
	_test_cliff_raise2_keeps_far_ramp()
	_test_bend_low_side_not_auto_diagonal()
	_test_l_corner_from_low_side_correct_origin()
	_test_l_then_dual_axis_expands_to_diagonal()
	_test_soften_dirs()
	_test_check_column_gate()
	_test_check_diagonal_box_gate()
	_test_side_is_l_arm()
	_test_ramp_cols_opposite()
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


func _test_expand_straight_to_l() -> void:
	# 外角先单列，再双轴 → L（第二臂 + 中心），绝不是 3×3 对角
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
		_fail("expand_l: first straight fail %s" % str(r1))
		return
	var r2: Dictionary = doc.try_paint_ramp_at(3, 3, 1, 1)
	if not bool(r2.get("ok", false)):
		_fail("expand_l: second plan fail %s" % str(r2))
		return
	if str(r2.get("variant", "")) != "l":
		_fail("expand_l: expect l got %s marks=%s" % [str(r2.get("variant")), str(r2.get("marked"))])
		return
	# 两臂 + 中心；远角 (5,5) 不应被 3×3 铺上
	if not (
		_flag_ramp(doc, 3, 3)
		and _flag_ramp(doc, 4, 3)
		and _flag_ramp(doc, 5, 3)
		and _flag_ramp(doc, 3, 4)
		and _flag_ramp(doc, 3, 5)
		and _flag_ramp(doc, 4, 4)
	):
		_fail("expand_l missing L arms/center")
		return
	if _flag_ramp(doc, 5, 5):
		_fail("expand_l must not fill far diagonal cell (5,5)")
		return
	print("  expand_straight_to_l OK n=%d" % (r2.get("marked", []) as Array).size())


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


func _test_allow_opposite_face_ramp() -> void:
	# 细高台脊（两侧皆低）。对齐经典 WE：先 +Y 再 -Y 应都能落旗。
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
	if not bool(r2.get("ok", false)) or not bool(r2.get("changed", false)):
		_fail("opposite_face expect allow -Y after +Y: %s" % str(r2))
		return
	if not (_flag_ramp(doc, 5, 4) and _flag_ramp(doc, 5, 3)):
		_fail("opposite_face missing -Y side marks")
		return
	if not (_flag_ramp(doc, 5, 6) and _flag_ramp(doc, 5, 7)):
		_fail("opposite_face missing +Y side marks")
		return
	print("  allow_opposite_face_ramp OK")


func _test_l_then_complete_with_center() -> void:
	# 外角先竖臂再横/双轴 → L：补横臂 + 中心，不铺远角 3×3
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
		_fail("l_complete setup vertical fail: %s" % str(r1))
		return
	var r2: Dictionary = doc.try_paint_ramp_at(4, 4, 1, 1)
	if not bool(r2.get("ok", false)) or not bool(r2.get("changed", false)):
		_fail("l_complete second stroke fail: %s" % str(r2))
		return
	if str(r2.get("variant", "")) != "l":
		_fail("l_complete expect l got %s" % str(r2.get("variant")))
		return
	if not (
		_flag_ramp(doc, 4, 4)
		and _flag_ramp(doc, 4, 5)
		and _flag_ramp(doc, 4, 6)
		and _flag_ramp(doc, 5, 4)
		and _flag_ramp(doc, 6, 4)
		and _flag_ramp(doc, 5, 5)
	):
		_fail("l_complete missing L arms/center")
		return
	if _flag_ramp(doc, 6, 6):
		_fail("l_complete must not fill far cell (6,6)")
		return
	print("  l_then_complete_with_center OK n=%d" % (r2.get("marked", []) as Array).size())


func _test_single_axis_keeps_straight_second_arm() -> void:
	# 外角已有竖臂，再单轴横意图 → L（横臂±中心），不是 diagonal
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
		_fail("second_arm setup vertical fail: %s" % str(r1))
		return
	var r2: Dictionary = doc.try_paint_ramp_at(4, 4, 1, 0)
	if not bool(r2.get("ok", false)) or not bool(r2.get("changed", false)):
		_fail("second_arm single-axis horizontal fail: %s" % str(r2))
		return
	if str(r2.get("variant", "")) == "diagonal":
		_fail("second_arm must not be diagonal")
		return
	if str(r2.get("variant", "")) != "l":
		_fail("second_arm expect l got %s" % str(r2.get("variant")))
		return
	if not (_flag_ramp(doc, 5, 4) and _flag_ramp(doc, 6, 4)):
		_fail("second_arm missing horizontal marks")
		return
	if _flag_ramp(doc, 6, 6):
		_fail("second_arm should not fill far diagonal cell (6,6)")
		return
	print("  single_axis_keeps_straight_second_arm OK n=%d" % (r2.get("marked", []) as Array).size())


func _test_fresh_corner_diagonal() -> void:
	# 空外角一次双轴 → 才是真正的 diagonal 3×3
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
	var r: Dictionary = doc.try_paint_ramp_at(4, 4, 1, 1)
	if not bool(r.get("changed", false)):
		_fail("fresh_diag fail: %s" % str(r))
		return
	if str(r.get("variant", "")) != "diagonal":
		_fail("fresh_diag expect diagonal got %s" % str(r.get("variant")))
		return
	var n: int = (r.get("marked", []) as Array).size()
	if n < 9:
		_fail("fresh_diag expect 9 marks got %d" % n)
		return
	if not _flag_ramp(doc, 6, 6):
		_fail("fresh_diag missing far cell (6,6)")
		return
	print("  fresh_corner_diagonal OK n=%d" % n)


func _test_dual_arms_se_plus_l_fill() -> void:
	# WE：先下后上，再刷右下对角 → 右下整块 3×3；右上不升对角，只 L 补心一点
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 14,
		"height": 14,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			doc.heightfield.layer_heights[y * w + x] = 3 if (x == 6 and y == 6) else 2
	doc._rebind_logic()
	var r_down: Dictionary = doc.try_paint_ramp_at(6, 6, 0, 1)
	if not bool(r_down.get("changed", false)):
		_fail("l_fill setup down fail: %s" % str(r_down))
		return
	var r_up: Dictionary = doc.try_paint_ramp_at(6, 6, 0, -1)
	if not bool(r_up.get("changed", false)):
		_fail("l_fill setup up fail: %s" % str(r_up))
		return
	# 已有上下臂后再右下意图 → L（横臂 + 凹口中心），不是 3×3 对角
	var r_se: Dictionary = doc.try_paint_ramp_at(6, 6, 1, 1)
	if not bool(r_se.get("ok", false)) or not bool(r_se.get("changed", false)):
		_fail("l_fill SE fail: %s" % str(r_se))
		return
	if str(r_se.get("variant", "")) != "l":
		_fail("l_fill expect l got %s" % str(r_se.get("variant")))
		return
	# 横臂 + SE/NE 中心；远角不应被铺
	if not (
		_flag_ramp(doc, 7, 6)
		and _flag_ramp(doc, 8, 6)
		and _flag_ramp(doc, 7, 7)
		and _flag_ramp(doc, 7, 5)
	):
		_fail("l_fill missing H arm or L centers")
		return
	if _flag_ramp(doc, 8, 8) or _flag_ramp(doc, 8, 4) or _flag_ramp(doc, 8, 5):
		_fail("l_fill should NOT fill far 3×3 cells")
		return
	print("  dual_arms_se_plus_l_fill OK")


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


func _test_cliff_change_clears_nearby_ramp() -> void:
	# 本笔刷点相关坡臂清掉；远处另一段坡必须保留；平行邻列在未改层时也必须保留。
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
			doc.heightfield.layer_heights[y * w + x] = 3 if y <= 2 else 2
	doc._rebind_logic()
	var near: Dictionary = doc.try_paint_ramp_at(3, 2, 0, 1)
	var parallel: Dictionary = doc.try_paint_ramp_at(5, 2, 0, 1)
	var far: Dictionary = doc.try_paint_ramp_at(10, 2, 0, 1)
	if (
		not bool(near.get("changed", false))
		or not bool(parallel.get("changed", false))
		or not bool(far.get("changed", false))
	):
		_fail(
			"cliff_clear setup paint fail near=%s par=%s far=%s"
			% [str(near), str(parallel), str(far)]
		)
		return
	# +1 抬高坡原点（tool 3）；不应方阵扫掉 x=5 邻列
	if not doc.paint_cliff_corner(3, 2, "3"):
		_fail("cliff_clear raise failed")
		return
	if _flag_ramp(doc, 3, 2) or _flag_ramp(doc, 3, 3) or _flag_ramp(doc, 3, 4):
		_fail("cliff_clear leftover near FLAG_RAMP after raise")
		return
	if not (_flag_ramp(doc, 5, 2) and _flag_ramp(doc, 5, 3) and _flag_ramp(doc, 5, 4)):
		_fail("cliff_clear wiped parallel column (square expand too wide)")
		return
	if not (_flag_ramp(doc, 10, 2) and _flag_ramp(doc, 10, 3) and _flag_ramp(doc, 10, 4)):
		_fail("cliff_clear wiped far ramp (AABB too wide)")
		return
	print("  cliff_change_clears_nearby_ramp OK")


func _test_cliff_raise2_keeps_far_ramp() -> void:
	# tool 4（+2）蛋糕传播面大，仍不得方阵误清远处坡
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 20,
		"height": 14,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			doc.heightfield.layer_heights[y * w + x] = 2
	# 左侧小高台 + 右侧另一段崖缘坡
	for y in range(0, 4):
		for x in range(0, 5):
			doc.heightfield.layer_heights[y * w + x] = 3
	for y in range(0, 4):
		for x in range(12, 16):
			doc.heightfield.layer_heights[y * w + x] = 3
	doc._rebind_logic()
	if not bool(doc.try_paint_ramp_at(4, 3, 0, 1).get("changed", false)):
		_fail("raise2 setup near ramp fail")
		return
	if not bool(doc.try_paint_ramp_at(14, 3, 0, 1).get("changed", false)):
		_fail("raise2 setup far ramp fail")
		return
	if not doc.paint_cliff_corner(2, 2, "4"):
		_fail("raise2 +2 paint failed")
		return
	if not (_flag_ramp(doc, 14, 3) and _flag_ramp(doc, 14, 4) and _flag_ramp(doc, 14, 5)):
		_fail("raise2 wiped far ramp during cake propagate")
		return
	print("  cliff_raise2_keeps_far_ramp OK")


func _test_bend_low_side_not_auto_diagonal() -> void:
	# 日志回归：脊线先落竖坡、端头再落横坡，转角低侧再点 → 必须仍 straight，不得 diagonal×6
	# （旧逻辑低侧 plan 会单轴升对角，Collect placed 下降并挖出灰洞）
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 16,
		"height": 16,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			# 细脊 y==5、x=2..5（对齐「只抬一排崖角」）
			doc.heightfield.layer_heights[y * w + x] = 3 if (y == 5 and x >= 2 and x <= 5) else 2
	doc._rebind_logic()
	# 1) 北侧低点 → 竖坡朝南落到脊上
	var r1: Dictionary = doc.try_paint_ramp_at(3, 4, 0, 1)
	if not bool(r1.get("changed", false)):
		_fail("bend setup vertical fail: %s" % str(r1))
		return
	if str(r1.get("variant", "")) != "straight":
		_fail("bend setup1 expect straight got %s" % str(r1.get("variant")))
		return
	# 2) 东侧低点 → 端头横坡（与竖臂在 (5,5) 垂直）
	var r2: Dictionary = doc.try_paint_ramp_at(6, 5, -1, 0)
	if not bool(r2.get("changed", false)):
		_fail("bend setup horizontal fail: %s" % str(r2))
		return
	if str(r2.get("variant", "")) != "straight":
		_fail("bend setup2 expect straight got %s" % str(r2.get("variant")))
		return
	var cat := Wc3CliffCatalog.new()
	cat.load_default()
	var before: Wc3RampCollectResult = Wc3RampLogic.collect_placements(doc.heightfield, {}, cat)
	var n_before: int = before.placements.size()
	# 3) 南侧转角低点：旧 bug 升 diagonal×6；现应 straight 单列
	var r3: Dictionary = doc.try_paint_ramp_at(5, 6, 0, 1)
	if not bool(r3.get("ok", false)) or not bool(r3.get("changed", false)):
		_fail("bend low-side paint fail: %s" % str(r3))
		return
	if str(r3.get("variant", "")) == "diagonal":
		_fail(
			"bend must not auto-diagonal from low side marks=%s"
			% str(r3.get("marked"))
		)
		return
	var marked: Array = r3.get("marked", [])
	if marked.size() > 3:
		_fail("bend expect ≤3 new marks got %d %s" % [marked.size(), str(marked)])
		return
	var after: Wc3RampCollectResult = Wc3RampLogic.collect_placements(doc.heightfield, {}, cat)
	if after.placements.size() < n_before:
		_fail(
			"bend Collect placements dropped %d→%d"
			% [n_before, after.placements.size()]
		)
		return
	print(
		"  bend_low_side_not_auto_diagonal OK variant=%s marks=%d placed=%d→%d"
		% [str(r3.get("variant")), marked.size(), n_before, after.placements.size()]
	)


func _test_l_corner_from_low_side_correct_origin() -> void:
	# 日志回归：崖缘 (32..34,31) → 北向直坡 @(33,31) → 东向直坡 @(34,31)
	# → 在 (34,32) 补 L：原点必须是 (34,31)，南臂+中心 (35,32)；
	# 不得落到 (33,31) 再往南/西乱标（截图 X 点）。
	var doc = MapDocumentScript.new()
	doc.create_from_options({
		"width": 48,
		"height": 48,
		"main_tileset": "I",
		"ground_tilesets": ["Idrt"],
		"cliff_tilesets": ["CIsn"],
		"cliff_level": 2,
	})
	var w: int = doc.heightfield.width
	for y in range(doc.heightfield.height):
		for x in range(w):
			doc.heightfield.layer_heights[y * w + x] = 2
	for x in range(32, 35):
		doc.heightfield.layer_heights[31 * w + x] = 3
	doc._rebind_logic()
	var r1: Dictionary = doc.try_paint_ramp_at(33, 30, 0, 1)
	if not bool(r1.get("changed", false)):
		_fail("l_corner setup N fail: %s" % str(r1))
		return
	var r2: Dictionary = doc.try_paint_ramp_at(35, 31, -1, 0)
	if not bool(r2.get("changed", false)):
		_fail("l_corner setup E fail: %s" % str(r2))
		return
	var sx2: int = int(r2.get("sx", -1))
	var sy2: int = int(r2.get("sy", -1))
	if sx2 != 34 or sy2 != 31:
		_fail("l_corner setup E expect origin (34,31) got (%d,%d)" % [sx2, sy2])
		return
	var r3: Dictionary = doc.try_paint_ramp_at(34, 32, 0, 1)
	if not bool(r3.get("ok", false)) or not bool(r3.get("changed", false)):
		_fail("l_corner low-side L fail: %s" % str(r3))
		return
	var sx: int = int(r3.get("sx", -1))
	var sy: int = int(r3.get("sy", -1))
	if sx != 34 or sy != 31:
		_fail("l_corner expect origin (34,31) got (%d,%d) variant=%s marks=%s"
			% [sx, sy, str(r3.get("variant")), str(r3.get("marked"))])
		return
	if str(r3.get("variant", "")) != "l":
		_fail("l_corner expect variant=l got %s" % str(r3.get("variant")))
		return
	# 应有：南臂 + L 中心
	if not (
		_flag_ramp(doc, 34, 32)
		and _flag_ramp(doc, 34, 33)
		and _flag_ramp(doc, 35, 32)
	):
		_fail("l_corner missing S arm / center (35,32)")
		return
	# 不应：从错误原点 (33,31) 往南乱标
	if _flag_ramp(doc, 33, 32) or _flag_ramp(doc, 33, 33):
		_fail("l_corner must not mark wrong S column from (33,31)")
		return
	print(
		"  l_corner_from_low_side_correct_origin OK marks=%s"
		% str(r3.get("marked"))
	)


func _test_l_then_dual_axis_expands_to_diagonal() -> void:
	# L 完成后双轴应能升满 3×3（先前 had_arm 误杀 allow_d）
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
	if not bool(doc.try_paint_ramp_at(4, 4, 0, 1).get("changed", false)):
		_fail("l2d setup V fail")
		return
	if not bool(doc.try_paint_ramp_at(4, 4, 1, 0).get("changed", false)):
		_fail("l2d setup H/L fail")
		return
	# 此时应为 L（含中心），远角 (6,6) 尚无
	if _flag_ramp(doc, 6, 6):
		_fail("l2d setup should not already have far cell")
		return
	var r: Dictionary = doc.try_paint_ramp_at(4, 4, 1, 1)
	if not bool(r.get("ok", false)) or not bool(r.get("changed", false)):
		_fail("l2d dual-axis expand fail: %s" % str(r))
		return
	if str(r.get("variant", "")) != "diagonal":
		_fail("l2d expect diagonal got %s marks=%s" % [str(r.get("variant")), str(r.get("marked"))])
		return
	if not _flag_ramp(doc, 6, 6):
		_fail("l2d missing far diagonal cell (6,6)")
		return
	print("  l_then_dual_axis_expands_to_diagonal OK n=%d" % (r.get("marked", []) as Array).size())


## ============================================================
## 内部路径测试（覆盖 Wc3RampPaint 私有函数）
## ============================================================

func _test_soften_dirs() -> void:
	var s: Vector2i = Wc3RampPaint.soften_dirs(1.0, 0.3)
	if s != Vector2i(1, 0):
		_fail("soften_dirs hx-dominant expect +X only got %s" % str(s))
		return
	var d: Vector2i = Wc3RampPaint.soften_dirs(1.0, 1.0)
	if d != Vector2i(1, 1):
		_fail("soften_dirs equal expect diagonal got %s" % str(d))
		return
	var v: Vector2i = Wc3RampPaint.soften_dirs(0.3, 1.0)
	if v != Vector2i(0, 1):
		_fail("soften_dirs hy-dominant expect +Y only got %s" % str(v))
		return
	var n: Vector2i = Wc3RampPaint.soften_dirs(0.0, 0.0)
	if n != Vector2i(0, 0):
		_fail("soften_dirs zero expect (0,0) got %s" % str(n))
		return
	var neg: Vector2i = Wc3RampPaint.soften_dirs(-0.5, 0.1)
	if neg != Vector2i(-1, 0):
		_fail("soften_dirs negative hx expect (-1,0) got %s" % str(neg))
		return
	print("  soften_dirs OK")


func _test_check_column_gate() -> void:
	## 构造：原点高=3，沿 +X 三点低=2，边界和层高都满足，无侧邻干扰
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
			doc.heightfield.layer_heights[y * w + x] = 3 if x <= 1 else 2
	doc._rebind_logic()
	## 原点 (1,3)：高=3，后两步 (2,3)(3,3)：低=2，侧邻无高
	var ok: bool = doc.try_paint_ramp_at(1, 3, 1, 0).get("changed", false)
	if not ok:
		_fail("check_column_gate: valid column should pass")
		return
	## 破坏后两步层高：中间变高 → 门禁应拒
	doc.heightfield.layer_heights[3 * w + 2] = 3
	doc._rebind_logic()
	var blocked: bool = doc.try_paint_ramp_at(1, 3, 1, 0).get("changed", false)
	if blocked:
		_fail("check_column_gate: column with wrong layer should be blocked")
		return
	print("  check_column_gate OK")


func _test_check_diagonal_box_gate() -> void:
	## 外角：高台 x<=3 且 y<=3；原点 (3,3) 高=3，对角 3×3 八个邻点全低=2
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
	## 验证对角 3×3 成功（原点 (3,3)，双轴都指向低侧）
	var r: Dictionary = doc.try_paint_ramp_at(3, 3, 1, 1)
	if not bool(r.get("ok", false)):
		_fail("check_diagonal_box: valid 3x3 should pass: %s" % str(r))
		return
	if (r.get("marked", []) as Array).size() < 9:
		_fail("check_diagonal_box: valid 3x3 should mark 9 points got %d" % (r.get("marked", []) as Array).size())
		return
	## 破坏一个邻点层高 → 对角应被拒
	doc.heightfield.layer_heights[4 * w + 4] = 3
	doc._rebind_logic()
	var blocked: Dictionary = doc.try_paint_ramp_at(3, 3, 1, 1)
	if bool(blocked.get("changed", false)):
		_fail("check_diagonal_box: broken box should be blocked")
		return
	print("  check_diagonal_box_gate OK")


func _test_side_is_l_arm() -> void:
	## 构造 L：原点 (3,3) 已有 +Y 竖臂；侧邻 (2,3) 应被识别为 L 的一肢
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
	## 先刷竖臂 (3,3) → +Y
	doc.try_paint_ramp_at(3, 3, 0, 1)
	## 再刷水平臂 (3,3) → +X（允许侧邻有旗，因为构成 L）
	var r: Dictionary = doc.try_paint_ramp_at(3, 3, 1, 0)
	if not bool(r.get("ok", false)):
		_fail("side_is_l_arm: L second arm should pass: %s" % str(r))
		return
	if str(r.get("variant", "")) != "l":
		_fail("side_is_l_arm: expect l got %s" % str(r.get("variant")))
		return
	print("  side_is_l_arm OK")


func _test_ramp_cols_opposite() -> void:
	## 严格相反：A=[1,1,1] B=[0,0,0] → true
	if not Wc3RampCollect._ramp_cols_opposite(1, 1, 1, 0, 0, 0):
		_fail("_ramp_cols_opposite strict opposite should be true")
		return
	## 放宽 A 污染：A=[1,1,1] B=[0,1,0] → true（中格被染）
	if not Wc3RampCollect._ramp_cols_opposite(1, 1, 1, 0, 1, 0):
		_fail("_ramp_cols_opposite A-polluted should be true")
		return
	## 放宽 B 污染：A=[0,1,0] B=[0,0,0] → true（中格被染）
	if not Wc3RampCollect._ramp_cols_opposite(0, 1, 0, 0, 0, 0):
		_fail("_ramp_cols_opposite B-polluted should be true")
		return
	## 非法：双向各污染 A=[0,1,0] B=[1,0,1] → false（无法判断 base）
	if Wc3RampCollect._ramp_cols_opposite(0, 1, 0, 1, 0, 1):
		_fail("_ramp_cols_opposite double-polluted should be false")
		return
	## 非法：同相 A=[1,1,1] B=[1,1,1] → false
	if Wc3RampCollect._ramp_cols_opposite(1, 1, 1, 1, 1, 1):
		_fail("_ramp_cols_opposite same-phase should be false")
		return
	print("  ramp_cols_opposite OK")
