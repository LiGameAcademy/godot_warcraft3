class_name Wc3RampStripSearchResult
extends RefCounted

## 在光标附近搜索最佳条带的结果。

var strip: Wc3RampStripSpec = null
var reject_message: String = "附近没有层差为 1 的直线崖边"


static func none(p_reject: String = "附近没有层差为 1 的直线崖边") -> Wc3RampStripSearchResult:
	var r := Wc3RampStripSearchResult.new()
	r.strip = null
	r.reject_message = p_reject
	return r


static func found(p_strip: Wc3RampStripSpec) -> Wc3RampStripSearchResult:
	var r := Wc3RampStripSearchResult.new()
	r.strip = p_strip
	r.reject_message = ""
	return r


func has_strip() -> bool:
	return strip != null and strip.ok
