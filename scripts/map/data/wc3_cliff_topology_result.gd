class_name Wc3CliffTopologyResult
extends RefCounted

## Logic 一次拓扑扫描的只读输出；Present / Context 只赋值消费，不重算。

var placements: Array[Wc3CliffPlacement] = []
var gap_mask: PackedByteArray = PackedByteArray() ## 地表格 (w-1)*(h-1)；1=挖洞
## 斜坡选型结果（placements + romp）；空壳时仍非 null
var ramp: Wc3RampCollectResult = null
var gap_stats: Dictionary = {}


func ensure_ramp() -> Wc3RampCollectResult:
	if ramp == null:
		ramp = Wc3RampCollectResult.new()
	return ramp
