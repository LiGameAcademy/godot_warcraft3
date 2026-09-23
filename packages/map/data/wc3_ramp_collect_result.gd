class_name Wc3RampCollectResult
extends RefCounted

## Logic.collect_placements 输出：placements + romp（运行时，不进 JSON）。

## romp 字节：0=无过渡，1=本角属已匹配 CliffTrans
const ROMP_NONE := 0
const ROMP_TRANS := 1

var placements: Array[Wc3RampPlacement] = []
## tilepoint 同形；字节见 ROMP_*
var romp: PackedByteArray = PackedByteArray()


static func empty_for_size(tp_w: int, tp_h: int) -> Wc3RampCollectResult:
	var r := Wc3RampCollectResult.new()
	r.romp.resize(maxi(tp_w * tp_h, 0))
	r.romp.fill(ROMP_NONE)
	return r


func non_phantom_count() -> int:
	var n := 0
	for p in placements:
		if p != null and p.has_glb:
			n += 1
	return n
