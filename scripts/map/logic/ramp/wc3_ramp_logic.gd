class_name Wc3RampLogic
extends RefCounted

## 斜坡逻辑：条带笔刷写 FLAG_RAMP；拓扑见 collect_placements（重建中）。
## 条带几何是本文件私有实现；对外只有 paint / peek_spine / PaintResult。

const AXIS_V := Wc3RampKinds.AXIS_V
const AXIS_H := Wc3RampKinds.AXIS_H
const STRIP_FACE := Wc3RampKinds.STRIP_FACE
const STRIP_SLOPE := Wc3RampKinds.STRIP_SLOPE

## 一次刷坡结果（自测 / 状态栏）。悬停请用 peek_spine_at。
class PaintResult extends RefCounted:
	var ok: bool = false
	var changed: bool = false
	var message: String = ""
	var axis: String = ""
	var sx: int = 0
	var sy: int = 0

	static func fail(msg: String) -> PaintResult:
		var r := PaintResult.new()
		r.message = msg
		return r

	static func ok_result(changed: bool, msg: String, axis: String, sx: int, sy: int) -> PaintResult:
		var r := PaintResult.new()
		r.ok = true
		r.changed = changed
		r.message = msg
		r.axis = axis
		r.sx = sx
		r.sy = sy
		return r


## 内部条带（无 class_name，不进 Data 层）。
class _Strip extends RefCounted:
	var ok: bool = false
	var message: String = ""
	var kind: String = ""
	var axis: String = ""
	var sx: int = 0
	var sy: int = 0
	var ramp_left: bool = true
	var ramp_bottom: bool = true
	var mid_l: int = 0
	var mid_r: int = 0

	static func fail(msg: String = "", code: String = "") -> _Strip:
		var s := _Strip.new()
		s.message = msg
		s.kind = code
		return s

	static func make_vertical(
		sx: int, sy: int, kind: String, ramp_left: bool, mid_l: int, mid_r: int
	) -> _Strip:
		var s := _Strip.new()
		s.ok = true
		s.axis = Wc3RampKinds.AXIS_V
		s.sx = sx
		s.sy = sy
		s.kind = kind
		s.ramp_left = ramp_left
		s.mid_l = mid_l
		s.mid_r = mid_r
		return s

	static func make_horizontal(
		sx: int, sy: int, kind: String, ramp_bottom: bool, mid_b: int, mid_t: int
	) -> _Strip:
		var s := _Strip.new()
		s.ok = true
		s.axis = Wc3RampKinds.AXIS_H
		s.sx = sx
		s.sy = sy
		s.kind = kind
		s.ramp_bottom = ramp_bottom
		s.mid_l = mid_b
		s.mid_r = mid_t
		return s

	func duplicate_spec() -> _Strip:
		var s := _Strip.new()
		s.ok = ok
		s.message = message
		s.kind = kind
		s.axis = axis
		s.sx = sx
		s.sy = sy
		s.ramp_left = ramp_left
		s.ramp_bottom = ramp_bottom
		s.mid_l = mid_l
		s.mid_r = mid_r
		return s

	func spine_vertices() -> Array[Vector2i]:
		var out: Array[Vector2i] = []
		if not ok:
			return out
		if axis == Wc3RampKinds.AXIS_V:
			var col: int = sx if ramp_left else sx + 1
			for yy in range(sy, sy + 3):
				out.append(Vector2i(col, yy))
		elif axis == Wc3RampKinds.AXIS_H:
			var row: int = sy if ramp_bottom else sy + 1
			for xx in range(sx, sx + 3):
				out.append(Vector2i(xx, row))
		return out


var heightfield: Wc3Heightfield = null
var cliff: Wc3CliffLogic = null
var last_message: String = ""
var _reject_message: String = ""


func bind(hf: Wc3Heightfield, cliff_logic: Wc3CliffLogic = null) -> Wc3RampLogic:
	heightfield = hf
	cliff = cliff_logic
	return self


func paint_at(ix: int, iy: int) -> bool:
	var r: PaintResult = try_paint_at(ix, iy)
	last_message = r.message
	return r.changed


func try_paint_at(ix: int, iy: int) -> PaintResult:
	if heightfield == null or not heightfield.is_valid():
		return PaintResult.fail("地图为空")
	if cliff == null:
		return PaintResult.fail("缺少 CliffLogic")
	var tp_w: int = heightfield.width
	var tp_h: int = heightfield.height
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return PaintResult.fail("顶点越界")
	var layers: Array = heightfield.layer_heights
	var heights: Array = heightfield.heights
	var water_h: Array = heightfield.water_heights
	var flags: Array = heightfield.flags_packed
	if layers.is_empty() or flags.is_empty():
		return PaintResult.fail("缺少层高/旗数据")
	_reject_message = "附近没有层差为 1 的直线崖边"
	var best: _Strip = _find_best_ramp_strip(ix, iy, layers, tp_w, tp_h)
	if best == null or not best.ok:
		return PaintResult.fail(_reject_message)
	var strip: _Strip = _resolve_ramp_strip_flags(best, flags, tp_w, ix, iy)
	var did_change := _apply_ramp_strip(strip, layers, heights, water_h, flags, tp_w)
	if did_change:
		return PaintResult.ok_result(
			true,
			"已刷斜坡 %s@(%d,%d)" % [strip.axis, strip.sx, strip.sy],
			strip.axis,
			strip.sx,
			strip.sy
		)
	return PaintResult.ok_result(false, "斜坡已存在", strip.axis, strip.sx, strip.sy)


## 悬停：将落 FLAG 的脊线顶点；无效返回空。
func peek_spine_at(ix: int, iy: int) -> Array[Vector2i]:
	var empty: Array[Vector2i] = []
	if heightfield == null or not heightfield.is_valid():
		return empty
	var tp_w: int = heightfield.width
	var tp_h: int = heightfield.height
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return empty
	var layers: Array = heightfield.layer_heights
	var flags: Array = heightfield.flags_packed
	var best: _Strip = _find_best_ramp_strip(ix, iy, layers, tp_w, tp_h)
	if best == null or not best.ok:
		return empty
	return _resolve_ramp_strip_flags(best, flags, tp_w, ix, iy).spine_vertices()


## 拓扑选型（重建前空壳）。
static func collect_placements(
	hf: Dictionary, meta: Dictionary = {}, _cliff_catalog: Wc3CliffCatalog = null
) -> Wc3RampCollectResult:
	if meta.is_empty():
		meta = Wc3Heightfield.build_meta_from_dict(hf)
	return Wc3RampCollectResult.empty_for_size(
		int(meta.get("width", 0)), int(meta.get("height", 0))
	)


func _resolve_ramp_strip_flags(
	spec: _Strip, flags: Array, tp_w: int, cursor_ix: int = -1, cursor_iy: int = -1
) -> _Strip:
	var out: _Strip = spec.duplicate_spec()
	if out.axis == AXIS_V:
		out.ramp_left = _choose_vertical_ramp_left(
			out.sx, out.sy, flags, tp_w, out.ramp_left, cursor_ix
		)
	elif out.axis == AXIS_H:
		out.ramp_bottom = _choose_horizontal_ramp_bottom(
			out.sx, out.sy, flags, tp_w, out.ramp_bottom, cursor_iy
		)
	return out


func _find_best_ramp_strip(
	ix: int, iy: int, layers: Array, tp_w: int, tp_h: int
) -> _Strip:
	var flags: Array = heightfield.flags_packed if heightfield != null else []
	var best: _Strip = null
	var best_score := Vector4(999999.0, 999999.0, 999999.0, 999999.0)
	var nearest_reject := "附近没有层差为 1 的直线崖边"
	for sy in range(iy - 2, iy + 1):
		for sx in range(ix - 1, ix + 1):
			var av: _Strip = _analyze_vertical_ramp_strip(sx, sy, layers, flags, tp_w, tp_h)
			if av.ok:
				var score := _ramp_strip_score(av, ix, iy, flags, tp_w)
				if _ramp_score_better(score, best_score):
					best_score = score
					best = av
			elif not av.kind.is_empty():
				nearest_reject = av.message if not av.message.is_empty() else nearest_reject
	for sy2 in range(iy - 1, iy + 1):
		for sx2 in range(ix - 2, ix + 1):
			var ah: _Strip = _analyze_horizontal_ramp_strip(
				sx2, sy2, layers, flags, tp_w, tp_h
			)
			if ah.ok:
				var score_h := _ramp_strip_score(ah, ix, iy, flags, tp_w)
				if _ramp_score_better(score_h, best_score):
					best_score = score_h
					best = ah
			elif not ah.kind.is_empty():
				nearest_reject = ah.message if not ah.message.is_empty() else nearest_reject
	if best == null or not best.ok:
		_reject_message = nearest_reject
		return null
	return best


## 评分越小越好：
## ①已完整刷过的条带重罚（避免卡在「斜坡已存在」、跳过邻条）
## ②光标须在条带上
## ③优先「紧贴已有同向斜坡」——宽2；避免崖沿横 face 抢走邻接竖条
## ④靠近将落 FLAG 的脊线列/行
## ⑤face 略优于 slope
func _ramp_strip_score(
	spec: _Strip, ix: int, iy: int, flags: Array, tp_w: int
) -> Vector4:
	var resolved: _Strip = _resolve_ramp_strip_flags(spec, flags, tp_w, ix, iy)
	var sx: int = resolved.sx
	var sy: int = resolved.sy
	var axis := resolved.axis
	var already := 0.0
	if _ramp_strip_already_applied(resolved, flags, tp_w):
		var on_spine := false
		if axis == AXIS_V:
			var ramp_col: int = sx if resolved.ramp_left else sx + 1
			on_spine = ix == ramp_col and iy >= sy and iy <= sy + 2
		else:
			var ramp_row: int = sy if resolved.ramp_bottom else sy + 1
			on_spine = iy == ramp_row and ix >= sx and ix <= sx + 2
		already = 0.0 if on_spine else 1.0
	var on_strip := 0.0
	var flag_focus := 0.0
	if axis == AXIS_V:
		if ix < sx or ix > sx + 1 or iy < sy or iy > sy + 2:
			on_strip = 1.0
		var ramp_col2: int = sx if resolved.ramp_left else sx + 1
		var dx := float(ix) - float(ramp_col2)
		var dy := float(iy) - (float(sy) + 1.0)
		flag_focus = dx * dx + dy * dy
	else:
		if ix < sx or ix > sx + 2 or iy < sy or iy > sy + 1:
			on_strip = 1.0
		var ramp_row2: int = sy if resolved.ramp_bottom else sy + 1
		var dxh := float(ix) - (float(sx) + 1.0)
		var dyh := float(iy) - float(ramp_row2)
		flag_focus = dxh * dxh + dyh * dyh
	var neighbor_gap := _ramp_neighbor_gap(resolved, flags, tp_w)
	var extends_pen := 1.0
	if neighbor_gap <= 1.01:
		if axis == AXIS_V:
			var ramp_col: int = sx if resolved.ramp_left else sx + 1
			var touches_existing := (
				(ramp_col > 0 and _vert_col_all(flags, tp_w, ramp_col - 1, sy, true))
				or _vert_col_all(flags, tp_w, ramp_col + 1, sy, true)
			)
			if touches_existing and ix == ramp_col:
				extends_pen = 0.0
		else:
			var ramp_row: int = sy if resolved.ramp_bottom else sy + 1
			var touches_h := (
				(ramp_row > 0 and _horiz_row_all(flags, tp_w, sx, ramp_row - 1, true))
				or _horiz_row_all(flags, tp_w, sx, ramp_row + 1, true)
			)
			if touches_h and iy == ramp_row:
				extends_pen = 0.0
	if axis == AXIS_V and ix > 0:
		if (
			not _vert_col_all(flags, tp_w, ix, sy, true)
			and _vert_col_all(flags, tp_w, ix - 1, sy, true)
			and _vert_col_all(flags, tp_w, ix + 1, sy, true)
			and (ix == sx or ix == sx + 1)
		):
			var fill_left := ix == sx
			if resolved.ramp_left == fill_left:
				already = 0.0
				on_strip = 0.0
				extends_pen = 0.0
				flag_focus = 0.0
	elif axis == AXIS_H and iy > 0:
		if (
			not _horiz_row_all(flags, tp_w, sx, iy, true)
			and _horiz_row_all(flags, tp_w, sx, iy - 1, true)
			and _horiz_row_all(flags, tp_w, sx, iy + 1, true)
			and (iy == sy or iy == sy + 1)
		):
			var fill_bottom := iy == sy
			if resolved.ramp_bottom == fill_bottom:
				already = 0.0
				on_strip = 0.0
				extends_pen = 0.0
				flag_focus = 0.0
	var kind_pen := 0.0 if spec.kind == STRIP_FACE else 0.02
	if spec.kind == STRIP_FACE:
		if axis == AXIS_V:
			var high_col: int = sx + 1 if resolved.ramp_left else sx
			if ix == high_col:
				flag_focus = maxf(0.0, flag_focus - 1.0)
		else:
			var high_row: int = sy + 1 if resolved.ramp_bottom else sy
			if iy == high_row:
				flag_focus = maxf(0.0, flag_focus - 1.0)
	return Vector4(already, on_strip, extends_pen, flag_focus + kind_pen)


func _ramp_strip_already_applied(spec: _Strip, flags: Array, tp_w: int) -> bool:
	if spec.axis == AXIS_V:
		return (
			_vert_col_all(flags, tp_w, spec.sx, spec.sy, spec.ramp_left)
			and _vert_col_all(flags, tp_w, spec.sx + 1, spec.sy, not spec.ramp_left)
		)
	if spec.axis == AXIS_H:
		return (
			_horiz_row_all(flags, tp_w, spec.sx, spec.sy, spec.ramp_bottom)
			and _horiz_row_all(flags, tp_w, spec.sx, spec.sy + 1, not spec.ramp_bottom)
		)
	return false


## 到最近已有脊列/行的距离；邻列差=1 → WE 宽 2。
func _ramp_neighbor_gap(spec: _Strip, flags: Array, tp_w: int) -> float:
	var sx: int = spec.sx
	var sy: int = spec.sy
	var best_gap := 100.0
	if spec.axis == AXIS_V:
		for dcol in [-1, 1]:
			var ncol: int = sx + dcol
			if ncol < 0:
				continue
			if _vert_col_all(flags, tp_w, ncol, sy, true):
				best_gap = minf(best_gap, 1.0)
			var left_ok := (
				_vert_col_all(flags, tp_w, ncol, sy, true)
				and _vert_col_all(flags, tp_w, ncol + 1, sy, false)
			)
			var right_ok := (
				_vert_col_all(flags, tp_w, ncol, sy, false)
				and _vert_col_all(flags, tp_w, ncol + 1, sy, true)
			)
			if left_ok or right_ok:
				best_gap = minf(best_gap, float(absi(dcol)))
	else:
		for drow in [-1, 1]:
			var nrow: int = sy + drow
			if nrow < 0:
				continue
			if _horiz_row_all(flags, tp_w, sx, nrow, true):
				best_gap = minf(best_gap, 1.0)
	return best_gap


static func _ramp_score_better(score: Vector4, best: Vector4) -> bool:
	if score.x < best.x - 0.0001:
		return true
	if score.x > best.x + 0.0001:
		return false
	if score.y < best.y - 0.0001:
		return true
	if score.y > best.y + 0.0001:
		return false
	if score.z < best.z - 0.0001:
		return true
	if score.z > best.z + 0.0001:
		return false
	return score.w < best.w - 0.0001


## 竖 1×2：直线崖边（列等高且列差=1）或沿坡（行两端差=1、中间=min）。
func _analyze_vertical_ramp_strip(
	sx: int, sy: int, layers: Array, flags: Array, tp_w: int, tp_h: int
) -> _Strip:
	if sx < 0 or sy < 0 or sx + 1 >= tp_w or sy + 2 >= tp_h:
		return _Strip.fail()
	var bl := int(layers[sy * tp_w + sx])
	var br := int(layers[sy * tp_w + sx + 1])
	var tl := int(layers[(sy + 1) * tp_w + sx])
	var tr_c := int(layers[(sy + 1) * tp_w + sx + 1])
	var ttl := int(layers[(sy + 2) * tp_w + sx])
	var ttr := int(layers[(sy + 2) * tp_w + sx + 1])

	if bl == ttl and br == ttr:
		var d: int = absi(bl - br)
		if d == 0:
			return _Strip.fail("无崖边（两侧同高）", "flat")
		if d != 1:
			return _Strip.fail("层差必须为 1（当前 %d）" % d, "delta")
		return _Strip.make_vertical(
			sx, sy, STRIP_FACE, bl < br, bl, br
		)

	if bl == br and ttl == ttr:
		if not _ramp_flags_near_vertical_strip(flags, tp_w, sx, sy):
			return _Strip.fail()
		var ds: int = absi(bl - ttl)
		if ds == 0:
			return _Strip.fail()
		if ds != 1:
			return _Strip.fail("层差必须为 1（当前 %d）" % ds, "delta")
		var mid := mini(bl, ttl)
		var hi := maxi(bl, ttl)
		if tl == hi and tr_c == hi:
			return _Strip.fail("高台侧会削切台面，请从低处入口刷斜坡", "carve")
		return _Strip.make_vertical(
			sx, sy, STRIP_SLOPE, true, mid, mid
		)

	if absi(bl - br) >= 1 or absi(ttl - ttr) >= 1 or absi(bl - ttl) >= 1 or absi(br - ttr) >= 1:
		if bl != ttl or br != ttr:
			return _Strip.fail("角柱/碎折边，不能刷斜坡", "corner")
	return _Strip.fail()


## 横 2×1：直线崖边（行等高且行差=1）或沿坡（列两端差=1、中间=min）。
func _analyze_horizontal_ramp_strip(
	sx: int, sy: int, layers: Array, flags: Array, tp_w: int, tp_h: int
) -> _Strip:
	if sx < 0 or sy < 0 or sx + 2 >= tp_w or sy + 1 >= tp_h:
		return _Strip.fail()
	var bl := int(layers[sy * tp_w + sx])
	var br := int(layers[sy * tp_w + sx + 1])
	var brr := int(layers[sy * tp_w + sx + 2])
	var tl := int(layers[(sy + 1) * tp_w + sx])
	var tr_c := int(layers[(sy + 1) * tp_w + sx + 1])
	var trr := int(layers[(sy + 1) * tp_w + sx + 2])

	if bl == br and br == brr and tl == tr_c and tr_c == trr:
		var d: int = absi(bl - tl)
		if d == 0:
			return _Strip.fail("无崖边（两侧同高）", "flat")
		if d != 1:
			return _Strip.fail("层差必须为 1（当前 %d）" % d, "delta")
		return _Strip.make_horizontal(
			sx, sy, STRIP_FACE, bl < tl, bl, tl
		)

	if bl == tl and brr == trr:
		if not _ramp_flags_near_horizontal_strip(flags, tp_w, sx, sy):
			return _Strip.fail()
		var ds: int = absi(bl - brr)
		if ds == 0:
			return _Strip.fail()
		if ds != 1:
			return _Strip.fail("层差必须为 1（当前 %d）" % ds, "delta")
		var mid := mini(bl, brr)
		var hi := maxi(bl, brr)
		if br == hi and tr_c == hi:
			return _Strip.fail("高台侧会削切台面，请从低处入口刷斜坡", "carve")
		return _Strip.make_horizontal(
			sx, sy, STRIP_SLOPE, true, mid, mid
		)

	if absi(bl - tl) >= 1 or absi(brr - trr) >= 1 or absi(bl - brr) >= 1:
		if not (bl == br and br == brr and tl == tr_c and tr_c == trr):
			return _Strip.fail("角柱/碎折边，不能刷斜坡", "corner")
	return _Strip.fail()


## 竖条带沿坡门禁：邻列（或本列）已有完整竖脊 111。
func _ramp_flags_near_vertical_strip(flags: Array, tp_w: int, sx: int, sy: int) -> bool:
	for xx in range(sx - 1, sx + 3):
		if xx < 0:
			continue
		if _vert_col_all(flags, tp_w, xx, sy, true):
			return true
	return false


## 横条带沿坡门禁：邻行（或本行）已有完整横脊 111。
func _ramp_flags_near_horizontal_strip(flags: Array, tp_w: int, sx: int, sy: int) -> bool:
	for yy in range(sy - 1, sy + 3):
		if yy < 0:
			continue
		if _horiz_row_all(flags, tp_w, sx, yy, true):
			return true
	return false


func _has_ramp_at(flags: Array, tp_w: int, ix: int, iy: int) -> bool:
	if ix < 0 or iy < 0:
		return false
	var i: int = iy * tp_w + ix
	if i < 0 or i >= flags.size():
		return false
	return (int(flags[i]) & Wc3Coords.FLAG_RAMP) != 0


func _apply_ramp_strip(
	spec: _Strip,
	layers: Array,
	heights: Array,
	water_h: Array,
	flags: Array,
	tp_w: int
) -> bool:
	var sx: int = spec.sx
	var sy: int = spec.sy
	var did_change := false
	if spec.axis == AXIS_V:
		var i_tl: int = (sy + 1) * tp_w + sx
		var i_tr: int = i_tl + 1
		if cliff.set_layer(i_tl, layers, heights, water_h, spec.mid_l):
			did_change = true
		if cliff.set_layer(i_tr, layers, heights, water_h, spec.mid_r):
			did_change = true
		var ramp_left: bool = spec.ramp_left
		for yy in range(sy, sy + 3):
			if ramp_left:
				if _set_ramp_flag(flags, yy * tp_w + sx, true):
					did_change = true
			else:
				if _set_ramp_flag(flags, yy * tp_w + sx + 1, true):
					did_change = true
		if ramp_left:
			if not _vert_col_all(flags, tp_w, sx + 1, sy, true):
				for yy2 in range(sy, sy + 3):
					if _set_ramp_flag(flags, yy2 * tp_w + sx + 1, false):
						did_change = true
		else:
			if not _vert_col_all(flags, tp_w, sx, sy, true):
				for yy3 in range(sy, sy + 3):
					if _set_ramp_flag(flags, yy3 * tp_w + sx, false):
						did_change = true
	elif spec.axis == AXIS_H:
		var mid_b: int = spec.mid_l
		var mid_t: int = spec.mid_r
		var i_br: int = sy * tp_w + sx + 1
		var i_tr2: int = (sy + 1) * tp_w + sx + 1
		if cliff.set_layer(i_br, layers, heights, water_h, mid_b):
			did_change = true
		if cliff.set_layer(i_tr2, layers, heights, water_h, mid_t):
			did_change = true
		var ramp_bottom: bool = spec.ramp_bottom
		for xx in range(sx, sx + 3):
			if ramp_bottom:
				if _set_ramp_flag(flags, sy * tp_w + xx, true):
					did_change = true
			else:
				if _set_ramp_flag(flags, (sy + 1) * tp_w + xx, true):
					did_change = true
		if ramp_bottom:
			if not _horiz_row_all(flags, tp_w, sx, sy + 1, true):
				for xx2 in range(sx, sx + 3):
					if _set_ramp_flag(flags, (sy + 1) * tp_w + xx2, false):
						did_change = true
		else:
			if not _horiz_row_all(flags, tp_w, sx, sy, true):
				for xx3 in range(sx, sx + 3):
					if _set_ramp_flag(flags, sy * tp_w + xx3, false):
						did_change = true
	return did_change


## 西/东邻已是脊时：仅当本条左列/右列是「紧邻续刷」才同向延伸。
## 隔列点击（中间空列）保持 prefer，以便刷出独立 U 凹（111|000|111）。
## 左右皆脊且本左列空：填 U 凹中间 → 连续宽坡（须先于「右脊已存在」分支）。
## cursor_ix：光标列；一侧已满脊时点对侧 → 续宽刷对侧。
func _choose_vertical_ramp_left(
	sx: int, sy: int, flags: Array, tp_w: int, prefer_left: bool, cursor_ix: int = -1
) -> bool:
	var left_full := _vert_col_all(flags, tp_w, sx, sy, true)
	var right_full := _vert_col_all(flags, tp_w, sx + 1, sy, true)
	var left_empty := _vert_col_all(flags, tp_w, sx, sy, false)
	var right_empty := _vert_col_all(flags, tp_w, sx + 1, sy, false)
	# 同条带续宽：左脊已满、点右列 → 刷右；右脊已满、点左列 → 刷左
	if left_full and right_empty and cursor_ix == sx + 1:
		return false
	if right_full and left_empty and cursor_ix == sx:
		return true
	if left_full and right_empty:
		return true
	# U 凹中间：左列空、左右邻列皆脊 → 填左列（不可走「右脊已在」返回 false）
	if (
		sx > 0
		and not left_full
		and _vert_col_all(flags, tp_w, sx - 1, sy, true)
		and right_full
	):
		return true
	if right_full and left_empty:
		return false
	# 西邻已是脊且本左列尚未成脊 → 续宽（111|111）
	if sx > 0 and _vert_col_all(flags, tp_w, sx - 1, sy, true) and not left_full:
		return true
	# 东邻已是脊且本左列空 → 向西续宽（填左列）
	if right_full and not left_full:
		return true
	return prefer_left


func _choose_horizontal_ramp_bottom(
	sx: int, sy: int, flags: Array, tp_w: int, prefer_bottom: bool, cursor_iy: int = -1
) -> bool:
	var bot_full := _horiz_row_all(flags, tp_w, sx, sy, true)
	var top_full := _horiz_row_all(flags, tp_w, sx, sy + 1, true)
	var bot_empty := _horiz_row_all(flags, tp_w, sx, sy, false)
	var top_empty := _horiz_row_all(flags, tp_w, sx, sy + 1, false)
	if bot_full and top_empty and cursor_iy == sy + 1:
		return false
	if top_full and bot_empty and cursor_iy == sy:
		return true
	if bot_full and top_empty:
		return true
	if (
		sy > 0
		and not bot_full
		and _horiz_row_all(flags, tp_w, sx, sy - 1, true)
		and top_full
	):
		return true
	if top_full and bot_empty:
		return false
	if sy > 0 and _horiz_row_all(flags, tp_w, sx, sy - 1, true) and not bot_full:
		return true
	if top_full and not bot_full:
		return true
	return prefer_bottom


func _vert_col_all(flags: Array, tp_w: int, ix: int, sy: int, want_ramp: bool) -> bool:
	for yy in range(sy, sy + 3):
		var i: int = yy * tp_w + ix
		if i < 0 or i >= flags.size():
			return false
		var is_r: bool = (int(flags[i]) & Wc3Coords.FLAG_RAMP) != 0
		if is_r != want_ramp:
			return false
	return true


func _horiz_row_all(flags: Array, tp_w: int, sx: int, iy: int, want_ramp: bool) -> bool:
	for xx in range(sx, sx + 3):
		var i: int = iy * tp_w + xx
		if i < 0 or i >= flags.size():
			return false
		var is_r: bool = (int(flags[i]) & Wc3Coords.FLAG_RAMP) != 0
		if is_r != want_ramp:
			return false
	return true


func _set_ramp_flag(flags: Array, i: int, want_ramp: bool) -> bool:
	if i < 0 or i >= flags.size():
		return false
	var fl: int = int(flags[i])
	var nf: int = (fl | Wc3Coords.FLAG_RAMP) if want_ramp else (fl & ~Wc3Coords.FLAG_RAMP)
	# 斜坡与水面互斥（与 CliffLogic.paint_water 对称）
	if want_ramp:
		nf = nf & ~Wc3Coords.FLAG_WATER
	if nf == fl:
		return false
	flags[i] = nf
	return true


