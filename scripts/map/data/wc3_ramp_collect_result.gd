class_name Wc3RampCollectResult
extends RefCounted

## Logic.collect_ramp_placements 的结构化输出（替代 {"placements","romp"} Dictionary）。

var placements: Array[Wc3RampPlacement] = []
## 与 tilepoint 网格同形（width*height）；字节见 Wc3RampKinds.ROMP_*
var romp: PackedByteArray = PackedByteArray()


static func empty_for_size(tp_w: int, tp_h: int) -> Wc3RampCollectResult:
	var r := Wc3RampCollectResult.new()
	r.romp.resize(maxi(tp_w * tp_h, 0))
	r.romp.fill(Wc3RampKinds.ROMP_NONE)
	return r


func placement_count() -> int:
	return placements.size()


func non_phantom_count() -> int:
	var n := 0
	for p in placements:
		if p != null and not p.phantom:
			n += 1
	return n
