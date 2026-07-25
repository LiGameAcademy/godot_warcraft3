class_name Wc3RampStripSpec
extends RefCounted

## 斜坡笔刷条带规格（逻辑层落 FLAG_RAMP 的几何描述）。
## 对应 Document peek / try_paint 曾用的 Dictionary；迁 RampLogic 时以此为契约。

var ok: bool = false
var message: String = ""
## face | slope | 空（见 Wc3RampKinds.STRIP_*）
var kind: String = ""
## "v" | "h"
var axis: String = ""
## 条带锚点（竖：左下格角；横：底左格角）
var sx: int = 0
var sy: int = 0
var ramp_left: bool = true
var ramp_bottom: bool = true
## 条带中间两侧层高（apply 时抬/压用）
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
	p_mid_l: int,
	p_mid_r: int
) -> Wc3RampStripSpec:
	var s := Wc3RampStripSpec.new()
	s.ok = true
	s.axis = Wc3RampKinds.AXIS_H
	s.sx = p_sx
	s.sy = p_sy
	s.kind = p_kind
	s.ramp_bottom = p_ramp_bottom
	s.mid_l = p_mid_l
	s.mid_r = p_mid_r
	return s


## 过渡：从旧 Dictionary 规格构造（Document 迁出前）。
## analyze 失败带 ok:false；peek 成功规格常无 ok 键但有 axis。
static func from_dict(d: Dictionary) -> Wc3RampStripSpec:
	if d.is_empty():
		return fail()
	if d.has("ok") and not bool(d["ok"]):
		return fail(str(d.get("message", "")), str(d.get("code", "")))
	var axis := str(d.get("axis", ""))
	if axis.is_empty():
		return fail(str(d.get("message", "")))
	var s := Wc3RampStripSpec.new()
	s.ok = true
	s.axis = axis
	s.sx = int(d.get("sx", 0))
	s.sy = int(d.get("sy", 0))
	s.kind = str(d.get("kind", ""))
	s.ramp_left = bool(d.get("ramp_left", true))
	s.ramp_bottom = bool(d.get("ramp_bottom", true))
	s.mid_l = int(d.get("mid_l", 0))
	s.mid_r = int(d.get("mid_r", 0))
	s.message = str(d.get("message", ""))
	return s


func to_dict() -> Dictionary:
	return {
		"ok": ok,
		"message": message,
		"kind": kind,
		"axis": axis,
		"sx": sx,
		"sy": sy,
		"ramp_left": ramp_left,
		"ramp_bottom": ramp_bottom,
		"mid_l": mid_l,
		"mid_r": mid_r,
	}
