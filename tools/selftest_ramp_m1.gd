extends SceneTree
## M1 斜坡笔刷回归：合格直边可刷、角柱拒绝、层差≠1 拒绝、蓝菱形计数。
##
## ## 自动化
## - 南北走向直崖（列差 1）→ 竖条带写旗成功；_vertical_ramp_tag 非空
## - 东西走向直崖（行差 1）→ 横条带写旗成功
## - 角柱（2×2 抬高）→ 拒绝 corner
## - 层差 2 的直边 → 拒绝 delta
## - 平地 → 拒绝
## - FLAG_RAMP 顶点数与条带一致（竖 3 / 横 3）
##
## ## 手工验收（编辑器）
## 见本文件末尾注释，或 docs/RAMP.md §M1。
##
## 运行：
##   godot --headless --path . -s res://tools/selftest_ramp_m1.gd


const DocScript := preload("res://editor/scripts/map_document.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var failed := 0
	failed += _case_vertical_face_ok()
	failed += _case_horizontal_face_ok()
	failed += _case_adjacent_strips_lr_pattern()
	failed += _case_second_ridge_picks_adjacent_not_skip()
	failed += _case_skip_column_makes_separate_u()
	failed += _case_fill_u_middle_makes_width3()
	failed += _case_reject_high_side_carve()
	failed += _case_reject_delta2()
	failed += _case_reject_corner_pillar()
	failed += _case_reject_flat()
	failed += _case_fix_middle_height()
	failed += _case_u_recess_picks_near_face()

	if failed > 0:
		push_error("selftest_ramp_m1 FAILED cases=%d" % failed)
		quit(1)
		return
	print("selftest_ramp_m1 OK")
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


func _flag_ramp(doc, ix: int, iy: int) -> bool:
	var flags: Array = doc.hf["flagsPacked"]
	var tp_w: int = int(doc.hf["tilepointWidth"])
	return (int(flags[iy * tp_w + ix]) & Wc3Coords.FLAG_RAMP) != 0


func _count_ramp_flags(doc) -> int:
	var flags: Array = doc.hf["flagsPacked"]
	var n := 0
	for f in flags:
		if (int(f) & Wc3Coords.FLAG_RAMP) != 0:
			n += 1
	return n


func _case_vertical_face_ok() -> int:
	print("=== case: N-S cliff → horizontal slope strip OK ===")
	var doc = _new_doc()
	# 西低东高、南北走向直崖：通行向为东西 → 应选横条 slope（非竖 face）
	_set_layer_rect(doc, 11, 8, 11, 12, 3)
	var r: Dictionary = doc.try_paint_ramp_at(10, 10)
	if not bool(r.get("ok", false)) or not bool(r.get("changed", false)):
		push_error("N-S cliff should paint: %s" % str(r))
		return 1
	if str(r.get("axis", "")) != "h":
		push_error("expected axis=h (slope) got %s" % str(r.get("axis", "")))
		return 1
	var sx: int = int(r.get("sx", -1))
	var sy: int = int(r.get("sy", -1))
	var layers: Array = doc.hf["layerHeights"]
	var flags: Array = doc.hf["flagsPacked"]
	var tp_w: int = int(doc.hf["tilepointWidth"])
	var tag: String = Wc3CliffTiles._horizontal_ramp_tag(layers, flags, tp_w, sx, sy)
	if tag.is_empty():
		push_error("horizontal tag empty after paint at (%d,%d)" % [sx, sy])
		return 1
	var ramp_data: Dictionary = Wc3CliffTiles.collect_ramp_placements(doc.hf)
	var romp: PackedByteArray = ramp_data.get("romp", PackedByteArray())
	var romp_n := 0
	for b in romp:
		if int(b) != 0:
			romp_n += 1
	# 单脊线：主条 2 格 + 侧脊幻影 2 格 = 4（幻影也标 romp，避免叠直崖接缝）
	if romp_n != 4:
		push_error("single-spine romp should be 4 (primary+phantom), got %d" % romp_n)
		return 1
	var wide_n := 0
	for p in ramp_data.get("placements", []):
		if bool(p.get("wide", false)):
			wide_n += 1
	if wide_n != 0:
		push_error("single-spine must not be wide, got %d" % wide_n)
		return 1
	# 全部应为 ROMP_SINGLE（挖洞），不能升宽坡甲板
	var tp_h: int = int(doc.hf["tilepointHeight"])
	for iy in range(tp_h - 1):
		for ix in range(tp_w - 1):
			var k: int = Wc3CliffTiles.romp_kind_at(romp, tp_w, ix, iy)
			if k == Wc3CliffTiles.ROMP_WIDE:
				push_error("single-spine must not have ROMP_WIDE @%d,%d" % [ix, iy])
				return 1
	if _count_ramp_flags(doc) != 3:
		push_error("strip should set exactly 3 ramp corners, got %d" % _count_ramp_flags(doc))
		return 1
	print("OK N-S→h slope tag=%s romp=%d" % [tag, romp_n])
	return 0


func _case_horizontal_face_ok() -> int:
	print("=== case: E-W cliff → vertical slope strip OK ===")
	var doc = _new_doc()
	# 南低北高、东西走向直崖：通行向为南北 → 应选竖条 slope
	_set_layer_rect(doc, 8, 11, 12, 11, 3)
	var r: Dictionary = doc.try_paint_ramp_at(10, 10)
	if not bool(r.get("ok", false)) or not bool(r.get("changed", false)):
		push_error("E-W cliff should paint: %s" % str(r))
		return 1
	if str(r.get("axis", "")) != "v":
		push_error("expected axis=v (slope) got %s" % str(r.get("axis", "")))
		return 1
	var sx: int = int(r.get("sx", -1))
	var sy: int = int(r.get("sy", -1))
	var layers: Array = doc.hf["layerHeights"]
	var flags: Array = doc.hf["flagsPacked"]
	var tp_w: int = int(doc.hf["tilepointWidth"])
	var tag: String = Wc3CliffTiles._vertical_ramp_tag(layers, flags, tp_w, sx, sy)
	if tag.is_empty():
		push_error("vertical tag empty after paint")
		return 1
	var ramp_data: Dictionary = Wc3CliffTiles.collect_ramp_placements(doc.hf)
	if (ramp_data.get("placements", []) as Array).is_empty():
		push_error("placements should exist for deck/romp")
		return 1
	if _count_ramp_flags(doc) != 3:
		push_error("strip should set exactly 3 ramp corners, got %d" % _count_ramp_flags(doc))
		return 1
	print("OK E-W→v slope tag=%s" % tag)
	return 0


func _case_adjacent_strips_lr_pattern() -> int:
	print("=== case: adjacent spines → 111|111 (WE width-2) ===")
	var doc = _new_doc()
	_set_layer_rect(doc, 8, 11, 16, 11, 3)
	var r0: Dictionary = doc.try_paint_ramp_at(10, 10)
	var r1: Dictionary = doc.try_paint_ramp_at(11, 10)
	if not bool(r0.get("ok", false)) or not bool(r1.get("changed", false)):
		push_error("both paints should change: %s / %s" % [str(r0), str(r1)])
		return 1
	var flags: Array = doc.hf["flagsPacked"]
	var tp_w: int = int(doc.hf["tilepointWidth"])
	var sy0: int = int(r0.get("sy", -1))
	var sx0: int = int(r0.get("sx", -1))
	# WE 宽2：相邻两列都有菱形
	var c0 := 0
	var c1 := 0
	var c2 := 0
	for yy in range(sy0, sy0 + 3):
		if (int(flags[yy * tp_w + sx0]) & DocScript.FLAG_RAMP) != 0:
			c0 += 1
		if (int(flags[yy * tp_w + sx0 + 1]) & DocScript.FLAG_RAMP) != 0:
			c1 += 1
		if (int(flags[yy * tp_w + sx0 + 2]) & DocScript.FLAG_RAMP) != 0:
			c2 += 1
	if c0 != 3 or c1 != 3 or c2 != 0:
		push_error("expected adjacent 111|111|000, got %d|%d|%d" % [c0, c1, c2])
		return 1
	var ramp_data: Dictionary = Wc3CliffTiles.collect_ramp_placements(doc.hf)
	var romp: PackedByteArray = ramp_data.get("romp", PackedByteArray())
	var romp_n := 0
	var wide_cells := 0
	for iy in range(int(doc.hf["tilepointHeight"]) - 1):
		for ix in range(tp_w - 1):
			var k: int = Wc3CliffTiles.romp_kind_at(romp, tp_w, ix, iy)
			if k != 0:
				romp_n += 1
			if k == Wc3CliffTiles.ROMP_WIDE:
				wide_cells += 1
	if wide_cells < 2:
		push_error("width-2 should have wide romp cells, got %d (romp=%d)" % [wide_cells, romp_n])
		return 1
	# 外侧侧脊格应为 SINGLE（挖洞），不得标 WIDE
	# 第一脊 L 在 sx0，邻脊在 sx0+1 → 内部 WIDE 在 sx0；外侧条约在 sx0+1
	var outer_k: int = Wc3CliffTiles.romp_kind_at(romp, tp_w, sx0 + 1, sy0)
	if outer_k == Wc3CliffTiles.ROMP_WIDE and c2 == 0:
		push_error("outer side-ridge cell must not be ROMP_WIDE")
		return 1
	print("OK adjacent 111|111 wide_cells=%d romp=%d" % [wide_cells, romp_n])
	return 0


## 点在已有脊的邻列（鼠标旁一格）应落相邻菱形，而非隔列 111|000|111。
func _case_second_ridge_picks_adjacent_not_skip() -> int:
	print("=== case: click adjacent col → width-2 diamonds side-by-side ===")
	var doc = _new_doc()
	_set_layer_rect(doc, 8, 11, 16, 11, 3)
	var r0: Dictionary = doc.try_paint_ramp_at(10, 10)
	if not bool(r0.get("changed", false)):
		push_error("first paint failed: %s" % str(r0))
		return 1
	var sx0: int = int(r0.get("sx", -1))
	var sy0: int = int(r0.get("sy", 0))
	# 邻列 = 第一脊旁一格（clear 侧），不是隔一列
	var r1: Dictionary = doc.try_paint_ramp_at(sx0 + 1, 10)
	if not bool(r1.get("changed", false)):
		push_error("adjacent paint should change, got %s" % str(r1))
		return 1
	var flags: Array = doc.hf["flagsPacked"]
	var tp_w: int = int(doc.hf["tilepointWidth"])
	var mid_ramp := 0
	var next_ramp := 0
	for yy in range(sy0, sy0 + 3):
		if (int(flags[yy * tp_w + sx0 + 1]) & DocScript.FLAG_RAMP) != 0:
			mid_ramp += 1
		if (int(flags[yy * tp_w + sx0 + 2]) & DocScript.FLAG_RAMP) != 0:
			next_ramp += 1
	if mid_ramp != 3:
		push_error("adjacent col should be full ramp (WE width-2), got %d" % mid_ramp)
		return 1
	if next_ramp != 0:
		push_error("must not skip to col+2 (width-3 pattern), got %d flags there" % next_ramp)
		return 1
	print("OK adjacent col ramp, no skip to +2")
	return 0


## 跳过中间列点第三列 → 独立 U 凹（111|000|111），不得自动填满中间成连续宽坡。
func _case_skip_column_makes_separate_u() -> int:
	print("=== case: skip middle col → separate U (not fill continuous) ===")
	var doc = _new_doc()
	_set_layer_rect(doc, 8, 11, 16, 11, 3)
	var r0: Dictionary = doc.try_paint_ramp_at(10, 10)
	if not bool(r0.get("changed", false)):
		push_error("first paint failed: %s" % str(r0))
		return 1
	var sx0: int = int(r0.get("sx", -1))
	var sy0: int = int(r0.get("sy", 0))
	# 隔一列点击（第三列菱形位）
	var r1: Dictionary = doc.try_paint_ramp_at(sx0 + 2, 10)
	if not bool(r1.get("changed", false)):
		push_error("skip-col paint should change, got %s" % str(r1))
		return 1
	var flags: Array = doc.hf["flagsPacked"]
	var tp_w: int = int(doc.hf["tilepointWidth"])
	var c0 := 0
	var c1 := 0
	var c2 := 0
	for yy in range(sy0, sy0 + 3):
		if (int(flags[yy * tp_w + sx0]) & DocScript.FLAG_RAMP) != 0:
			c0 += 1
		if (int(flags[yy * tp_w + sx0 + 1]) & DocScript.FLAG_RAMP) != 0:
			c1 += 1
		if (int(flags[yy * tp_w + sx0 + 2]) & DocScript.FLAG_RAMP) != 0:
			c2 += 1
	if c0 != 3 or c1 != 0 or c2 != 3:
		push_error("expected 111|000|111 separate U, got %d|%d|%d" % [c0, c1, c2])
		return 1
	print("OK skip-col → separate U 111|000|111")
	return 0


## U 凹中间列补刷 → 三列连续 111|111|111（9 菱形），不得改成横 face 清旗。
func _case_fill_u_middle_makes_width3() -> int:
	print("=== case: fill U middle → width-3 continuous ===")
	var doc = _new_doc()
	_set_layer_rect(doc, 8, 11, 16, 11, 3)
	var r0: Dictionary = doc.try_paint_ramp_at(10, 10)
	if not bool(r0.get("changed", false)):
		push_error("first paint failed")
		return 1
	var sx0: int = int(r0.get("sx", -1))
	var sy0: int = int(r0.get("sy", 0))
	var r1: Dictionary = doc.try_paint_ramp_at(sx0 + 2, 10)
	if not bool(r1.get("changed", false)):
		push_error("skip-col paint failed")
		return 1
	var r2: Dictionary = doc.try_paint_ramp_at(sx0 + 1, 10)
	if not bool(r2.get("changed", false)):
		push_error("fill-middle should change, got %s" % str(r2))
		return 1
	if str(r2.get("axis", "")) != "v":
		push_error("fill-middle must stay vertical, got axis=%s" % str(r2.get("axis", "")))
		return 1
	var flags: Array = doc.hf["flagsPacked"]
	var tp_w: int = int(doc.hf["tilepointWidth"])
	var counts := [0, 0, 0]
	for col in range(3):
		for yy in range(sy0, sy0 + 3):
			if (int(flags[yy * tp_w + sx0 + col]) & DocScript.FLAG_RAMP) != 0:
				counts[col] += 1
	if counts[0] != 3 or counts[1] != 3 or counts[2] != 3:
		push_error("expected 111|111|111 (9 diamonds), got %d|%d|%d" % [counts[0], counts[1], counts[2]])
		return 1
	print("OK fill-U-middle → 111|111|111")
	return 0


func _case_reject_high_side_carve() -> int:
	print("=== case: high-side paint must not carve plateau ===")
	var doc = _new_doc()
	# 东西崖：y=11 抬高；先从南侧低处刷坡
	_set_layer_rect(doc, 8, 11, 14, 14, 3)
	var r0: Dictionary = doc.try_paint_ramp_at(10, 10)
	if not bool(r0.get("changed", false)):
		push_error("low-side paint should work: %s" % str(r0))
		return 1
	var layers_before: Array = (doc.hf["layerHeights"] as Array).duplicate()
	# 再在高台顶点刷：应拒绝削切，且不得改层高
	var r1: Dictionary = doc.try_paint_ramp_at(10, 12)
	if bool(r1.get("ok", false)) and bool(r1.get("changed", false)):
		push_error("high-side should not carve/change: %s" % str(r1))
		return 1
	var layers_after: Array = doc.hf["layerHeights"]
	for i in range(layers_before.size()):
		if int(layers_before[i]) != int(layers_after[i]):
			push_error("high-side paint must not modify layers at i=%d" % i)
			return 1
	# 原坡仍有效
	var sx: int = int(r0.get("sx", -1))
	var sy: int = int(r0.get("sy", -1))
	var tag: String = Wc3CliffTiles._vertical_ramp_tag(
		layers_after, doc.hf["flagsPacked"], int(doc.hf["tilepointWidth"]), sx, sy
	)
	if tag.is_empty():
		push_error("original ramp tag broken after high-side attempt")
		return 1
	print("OK reject carve (msg=%s) original tag=%s" % [str(r1.get("message", "")), tag])
	return 0


func _case_reject_delta2() -> int:
	print("=== case: delta=2 straight edge → reject ===")
	var doc = _new_doc()
	_set_layer_rect(doc, 11, 8, 11, 12, 4) # 层差 2
	var r: Dictionary = doc.try_paint_ramp_at(10, 10)
	if bool(r.get("ok", false)):
		push_error("delta2 should reject, got %s" % str(r))
		return 1
	var msg: String = str(r.get("message", ""))
	if msg.find("1") < 0 and msg.find("层差") < 0:
		push_error("delta2 message should mention 层差: %s" % msg)
		return 1
	print("OK reject delta2: %s" % msg)
	return 0


func _case_reject_corner_pillar() -> int:
	print("=== case: single raised pillar → reject ===")
	var doc = _new_doc()
	# 单点抬高 → 无直线崖边
	_set_layer_rect(doc, 10, 10, 10, 10, 3)
	var r: Dictionary = doc.try_paint_ramp_at(10, 10)
	if bool(r.get("ok", false)):
		push_error("pillar should reject, got %s" % str(r))
		return 1
	print("OK reject pillar: %s" % str(r.get("message", "")))
	return 0


func _case_reject_flat() -> int:
	print("=== case: flat ground → reject ===")
	var doc = _new_doc()
	var r: Dictionary = doc.try_paint_ramp_at(16, 16)
	if bool(r.get("ok", false)):
		push_error("flat should reject")
		return 1
	print("OK reject flat: %s" % str(r.get("message", "")))
	return 0


func _case_fix_middle_height() -> int:
	print("=== case: R5 fix middle height ===")
	var doc = _new_doc()
	_set_layer_rect(doc, 11, 8, 11, 12, 3)
	var layers: Array = doc.hf["layerHeights"]
	var heights: Array = doc.hf["heights"]
	var tp_w: int = int(doc.hf["tilepointWidth"])
	var i_mid: int = 10 * tp_w + 10
	var old: int = int(layers[i_mid])
	layers[i_mid] = 4
	heights[i_mid] = float(heights[i_mid]) + float(4 - old) * 128.0
	var r: Dictionary = doc.try_paint_ramp_at(10, 10)
	if not bool(r.get("changed", false)):
		push_error("should fix middle and paint: %s" % str(r))
		return 1
	var sx: int = int(r.get("sx", 0))
	var sy: int = int(r.get("sy", 0))
	var mid_l: int = int(layers[(sy + 1) * tp_w + sx])
	var end_l: int = int(layers[sy * tp_w + sx])
	if mid_l != end_l:
		push_error("R5: mid_l=%d should equal end_l=%d" % [mid_l, end_l])
		return 1
	print("OK R5 middle fixed to %d" % mid_l)
	return 0


func _case_u_recess_picks_near_face() -> int:
	print("=== case: U recess — click bottom face not stolen by side slope ===")
	var doc = _new_doc()
	# 三面高台围成 U 形凹槽（开口朝南）
	_set_layer_rect(doc, 8, 12, 16, 16, 3) # 北壁+台
	_set_layer_rect(doc, 8, 8, 10, 12, 3) # 西壁
	_set_layer_rect(doc, 14, 8, 16, 12, 3) # 东壁
	# 先在东壁刷一条竖坡（对应截图「斜坡1」）
	var r1: Dictionary = doc.try_paint_ramp_at(14, 10)
	if not bool(r1.get("ok", false)):
		push_error("east wall ramp1 should paint: %s" % str(r1))
		return 1
	if str(r1.get("axis", "")) != "v":
		push_error("ramp1 expected axis=v, got %s" % str(r1.get("axis", "")))
		return 1
	# 再点凹槽北缘中点：应选横条（东西崖），不能被东壁竖坡抢走
	var r2: Dictionary = doc.try_paint_ramp_at(12, 12)
	if not bool(r2.get("ok", false)):
		push_error("north lip should paint: %s" % str(r2))
		return 1
	if str(r2.get("axis", "")) != "h":
		push_error(
			"north lip should be horizontal strip, got axis=%s sx=%s sy=%s (stolen by side?)"
			% [str(r2.get("axis", "")), str(r2.get("sx", "")), str(r2.get("sy", ""))]
		)
		return 1
	# 条带应覆盖点击附近，而非东壁 sx≈13/14
	var sx2: int = int(r2.get("sx", -1))
	if sx2 < 10 or sx2 > 12:
		push_error("north lip strip sx=%d should be near click x=12" % sx2)
		return 1
	print("OK U recess r2=h@(%d,%d) after r1=v" % [sx2, int(r2.get("sy", 0))])
	return 0


# ---------------------------------------------------------------------------
# 手工验收清单（编辑器）
# 1. 新建空白图 → 用升崖「3」沿南北方向刷一条直墙（两顶点同边、整段层差 1）
# 2. 选悬崖工具「斜坡」→ 在直崖边上按下并拖动：状态栏出现「已刷斜坡…」
# 3. 可见蓝菱形落在 RAMP 顶点上（低侧一列/行）；中级栅格仍在
# 4. 拖到台角/碎折处：状态栏「角柱/碎折边…」或「附近没有…」，不新增菱形
# 5. 用升崖把同一边抬成层差 2 后再刷斜坡：应提示层差必须为 1
# 6. 仍不放置 CliffTrans → M3 已放置；甲板由 RAMP_SURFACE_DECK_ENABLED 控制
# ---------------------------------------------------------------------------
