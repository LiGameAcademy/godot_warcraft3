class_name Wc3RampPaintResult
extends RefCounted

## 斜坡笔刷一次尝试的结果。

var ok: bool = false
var changed: bool = false
var message: String = ""
var strip: Wc3RampStripSpec = null


static func fail(p_message: String) -> Wc3RampPaintResult:
	var r := Wc3RampPaintResult.new()
	r.ok = false
	r.changed = false
	r.message = p_message
	return r


static func success(p_changed: bool, p_message: String, p_strip: Wc3RampStripSpec) -> Wc3RampPaintResult:
	var r := Wc3RampPaintResult.new()
	r.ok = true
	r.changed = p_changed
	r.message = p_message
	r.strip = p_strip
	return r
