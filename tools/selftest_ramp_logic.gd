extends SceneTree
## 逻辑层自测：条带写 FLAG_RAMP 的形状（不测 CliffTrans）。
## 用法：godot --headless -s res://tools/selftest_ramp_logic.gd


const DocScript := preload("res://editor/scripts/map_document.gd")


func _init() -> void:
	var failed := 0
	failed += _test_vertical_single()
	failed += _test_horizontal_single()
	failed += _test_vertical_wide()
	failed += _test_u_gap_not_auto_fill()
	if failed == 0:
		print("selftest_ramp_logic: PASS")
		quit(0)
	else:
		push_error("selftest_ramp_logic: FAIL (%d)" % failed)
		quit(1)


func _make_doc(tp_w: int, tp_h: int, layers: Array):
	var doc = DocScript.new()
	var n := tp_w * tp_h
	var heights: Array = []
	var water: Array = []
	var flags: Array = []
	var gtex: Array = []
	var gvar: Array = []
	var ctex: Array = []
	var cvar: Array = []
	heights.resize(n)
	water.resize(n)
	flags.resize(n)
	gtex.resize(n)
	gvar.resize(n)
	ctex.resize(n)
	cvar.resize(n)
	for i in range(n):
		heights[i] = float(int(layers[i]) - 2) * 128.0
		water[i] = heights[i]
		flags[i] = 0
		gtex[i] = 0
		gvar[i] = 0
		ctex[i] = 0
		cvar[i] = 0
	doc.hf = {
		"tilepointWidth": tp_w,
		"tilepointHeight": tp_h,
		"layerHeights": layers,
		"heights": heights,
		"waterHeights": water,
		"flagsPacked": flags,
		"groundTextures": gtex,
		"groundVariations": gvar,
		"cliffTextures": ctex,
		"cliffVariations": cvar,
		"groundTilesets": ["Ldrt"],
		"cliffTilesets": ["CLdi"],
	}
	return doc


func _flag_col(doc, col: int, y0: int) -> String:
	var tp_w: int = int(doc.hf["tilepointWidth"])
	var flags: Array = doc.hf["flagsPacked"]
	var s := ""
	for yy in range(y0, y0 + 3):
		var i := yy * tp_w + col
		s += "1" if (int(flags[i]) & Wc3Coords.FLAG_RAMP) != 0 else "0"
	return s


func _flag_row(doc, x0: int, row: int) -> String:
	var tp_w: int = int(doc.hf["tilepointWidth"])
	var flags: Array = doc.hf["flagsPacked"]
	var s := ""
	for xx in range(x0, x0 + 3):
		var i := row * tp_w + xx
		s += "1" if (int(flags[i]) & Wc3Coords.FLAG_RAMP) != 0 else "0"
	return s


## 南北走向崖 → 竖脊一列 111。
func _test_vertical_single() -> int:
	var tp_w := 4
	var tp_h := 5
	var layers: Array = []
	layers.resize(tp_w * tp_h)
	for iy in range(tp_h):
		for ix in range(tp_w):
			layers[iy * tp_w + ix] = 2 if ix <= 1 else 3
	var doc = _make_doc(tp_w, tp_h, layers)
	var r: Dictionary = doc.try_paint_ramp_at(1, 2)
	if not bool(r.get("ok", false)):
		push_error("vertical_single: reject %s" % str(r.get("message", "")))
		return 1
	if str(r.get("axis", "")) != "v":
		push_error("vertical_single: want axis=v got %s" % str(r))
		return 1
	var sy: int = int(r.get("sy", 0))
	var left := _flag_col(doc, 1, sy)
	var right := _flag_col(doc, 2, sy)
	var ok := (left == "111" and right == "000") or (left == "000" and right == "111")
	if not ok:
		push_error("vertical_single: flags L=%s R=%s sy=%d" % [left, right, sy])
		return 1
	print("  vertical_single OK L=%s R=%s sy=%d" % [left, right, sy])
	return 0


## 东西走向崖 → 横脊一行 111。
func _test_horizontal_single() -> int:
	var tp_w := 5
	var tp_h := 4
	var layers: Array = []
	layers.resize(tp_w * tp_h)
	for iy in range(tp_h):
		for ix in range(tp_w):
			layers[iy * tp_w + ix] = 2 if iy <= 1 else 3
	var doc = _make_doc(tp_w, tp_h, layers)
	var r: Dictionary = doc.try_paint_ramp_at(2, 1)
	if not bool(r.get("ok", false)):
		push_error("horizontal_single: reject %s" % str(r.get("message", "")))
		return 1
	if str(r.get("axis", "")) != "h":
		push_error("horizontal_single: want axis=h got %s" % str(r))
		return 1
	var sx: int = int(r.get("sx", 0))
	var bot := _flag_row(doc, sx, 1)
	var top := _flag_row(doc, sx, 2)
	var ok := (bot == "111" and top == "000") or (bot == "000" and top == "111")
	if not ok:
		push_error("horizontal_single: flags B=%s T=%s sx=%d" % [bot, top, sx])
		return 1
	print("  horizontal_single OK B=%s T=%s sx=%d" % [bot, top, sx])
	return 0


## 邻列再刷 → 两列皆 111（宽坡）。
func _test_vertical_wide() -> int:
	var tp_w := 5
	var tp_h := 5
	var layers: Array = []
	layers.resize(tp_w * tp_h)
	for iy in range(tp_h):
		for ix in range(tp_w):
			layers[iy * tp_w + ix] = 2 if ix <= 1 else 3
	var doc = _make_doc(tp_w, tp_h, layers)
	var r1: Dictionary = doc.try_paint_ramp_at(1, 2)
	if not bool(r1.get("changed", false)) or str(r1.get("axis", "")) != "v":
		push_error("vertical_wide: first paint failed %s" % str(r1))
		return 1
	var sy: int = int(r1.get("sy", 0))
	var left1 := _flag_col(doc, 1, sy)
	var next_x := 2 if left1 == "111" else 1
	var r2: Dictionary = doc.try_paint_ramp_at(next_x, 2)
	if not bool(r2.get("ok", false)):
		push_error("vertical_wide: second paint reject %s" % str(r2.get("message", "")))
		return 1
	var left := _flag_col(doc, 1, sy)
	var right := _flag_col(doc, 2, sy)
	if left != "111" or right != "111":
		push_error("vertical_wide: want 111|111 got %s|%s (first L=%s)" % [left, right, left1])
		return 1
	print("  vertical_wide OK 111|111")
	return 0


## 已有 111|000|111 时，点在已完整脊上不应把中间自动填满。
func _test_u_gap_not_auto_fill() -> int:
	var tp_w := 6
	var tp_h := 5
	var layers: Array = []
	layers.resize(tp_w * tp_h)
	for iy in range(tp_h):
		for ix in range(tp_w):
			layers[iy * tp_w + ix] = 2 if ix <= 1 else 3
	var doc = _make_doc(tp_w, tp_h, layers)
	var flags: Array = doc.hf["flagsPacked"]
	for yy in range(1, 4):
		flags[yy * tp_w + 1] = Wc3Coords.FLAG_RAMP
		flags[yy * tp_w + 3] = Wc3Coords.FLAG_RAMP
	var r: Dictionary = doc.try_paint_ramp_at(1, 2)
	if not bool(r.get("ok", false)):
		push_error("u_gap: unexpected reject %s" % str(r.get("message", "")))
		return 1
	var c1 := _flag_col(doc, 1, 1)
	var c2 := _flag_col(doc, 2, 1)
	var c3 := _flag_col(doc, 3, 1)
	if c2 == "111":
		push_error("u_gap: middle filled %s|%s|%s" % [c1, c2, c3])
		return 1
	if c1 != "111" or c3 != "111":
		push_error("u_gap: spines lost %s|%s|%s" % [c1, c2, c3])
		return 1
	print("  u_gap OK %s|%s|%s" % [c1, c2, c3])
	return 0
