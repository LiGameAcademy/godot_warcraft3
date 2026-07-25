class_name Wc3RampStripSpec
extends RefCounted

## 斜坡笔刷条带规格（落 FLAG_RAMP 的几何描述）。
## 竖轴 mid_l/mid_r = 左列/右列中间层高；横轴 mid_l/mid_r = 底行/顶行中间层高。

var ok: bool = false
var message: String = ""
## face | slope；失败时也可暂存 reject code（flat/delta/corner/carve）
var kind: String = ""
## Wc3RampKinds.AXIS_V | AXIS_H
var axis: String = ""
var sx: int = 0
var sy: int = 0
var ramp_left: bool = true
var ramp_bottom: bool = true
var mid_l: int = 0
var mid_r: int = 0


static func fail(p_message: String = "", p_code: String = "") -> Wc3RampStripSpec:
	var s := Wc3RampStripSpec.new()
	s.ok = false
	s.message = p_message
	s.kind = p_code
	return s


static func make_vertical(
	p_sx: int,
	p_sy: int,
	p_kind: String,
	p_ramp_left: bool,
	p_mid_l: int,
	p_mid_r: int
) -> Wc3RampStripSpec:
	var s := Wc3RampStripSpec.new()
	s.ok = true
	s.axis = Wc3RampKinds.AXIS_V
	s.sx = p_sx
	s.sy = p_sy
	s.kind = p_kind
	s.ramp_left = p_ramp_left
	s.mid_l = p_mid_l
	s.mid_r = p_mid_r
	return s


static func make_horizontal(
	p_sx: int,
	p_sy: int,
	p_kind: String,
	p_ramp_bottom: bool,
	p_mid_bottom: int,
	p_mid_top: int
) -> Wc3RampStripSpec:
	var s := Wc3RampStripSpec.new()
	s.ok = true
	s.axis = Wc3RampKinds.AXIS_H
	s.sx = p_sx
	s.sy = p_sy
	s.kind = p_kind
	s.ramp_bottom = p_ramp_bottom
	s.mid_l = p_mid_bottom
	s.mid_r = p_mid_top
	return s


func duplicate_spec() -> Wc3RampStripSpec:
	var s := Wc3RampStripSpec.new()
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


## 将落 FLAG_RAMP 的 3 个 tilepoint（蓝菱形 / 悬停预览）。
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
