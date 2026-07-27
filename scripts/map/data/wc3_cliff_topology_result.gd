class_name Wc3CliffTopologyResult
extends RefCounted

## Logic 一次拓扑扫描的只读输出；Present / Context 只赋值消费，不重算。

var placements: Array[Wc3CliffPlacement] = []
var gap_mask: PackedByteArray = PackedByteArray() ## 地表格 (w-1)*(h-1)；1=挖洞（仅直崖）
var gap_stats: Dictionary = {}
