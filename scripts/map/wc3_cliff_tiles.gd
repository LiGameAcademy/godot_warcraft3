class_name Wc3CliffTiles
extends RefCounted
## 悬崖 / 斜坡 Tile 判定（与地面挖洞、后续悬崖模型共用）。
##
## 规则对齐经典客户端 / mdx-m3-viewer：
## - 四角 layerHeight 不完全相同 → 悬崖格（含多数斜坡落差）
## - 任一角带 ramp 标志 → 斜坡相关格（确保坡道位置也留缝）


const FLAG_RAMP := 4 # flagsPacked bit2


## 四角 layer 是否不一致（悬崖格）。
static func is_cliff_tile(layer_heights: Array, width: int, ix: int, iy: int) -> bool:
	if layer_heights.is_empty():
		return false
	var i00 := iy * width + ix
	var i10 := i00 + 1
	var i01 := i00 + width
	var i11 := i01 + 1
	if i11 >= layer_heights.size():
		return false
	var a := int(layer_heights[i00])
	var b := int(layer_heights[i10])
	var c := int(layer_heights[i01])
	var d := int(layer_heights[i11])
	return a != b or a != c or a != d


## 四角是否有任一 ramp 标志。
static func is_ramp_tile(flags: Array, width: int, ix: int, iy: int) -> bool:
	if flags.is_empty():
		return false
	var i00 := iy * width + ix
	var i10 := i00 + 1
	var i01 := i00 + width
	var i11 := i01 + 1
	if i11 >= flags.size():
		return false
	return (
		(int(flags[i00]) & FLAG_RAMP) != 0
		or (int(flags[i10]) & FLAG_RAMP) != 0
		or (int(flags[i01]) & FLAG_RAMP) != 0
		or (int(flags[i11]) & FLAG_RAMP) != 0
	)


## 地面高度图应挖空（留给悬崖 / 斜坡模型）。
static func should_leave_gap(
	layer_heights: Array,
	flags: Array,
	width: int,
	ix: int,
	iy: int
) -> bool:
	return is_cliff_tile(layer_heights, width, ix, iy) or is_ramp_tile(flags, width, ix, iy)


## 统计整张图应挖空的 Tile 数。返回 { gaps, cliffs, ramps, tiles }。
static func count_gaps(hf: Dictionary) -> Dictionary:
	var meta := HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var width: int = meta["width"]
	var height: int = meta["height"]
	var layers: Array = meta["layer_heights"]
	var flags: Array = meta["flags"]
	var cliffs := 0
	var ramps := 0
	var gaps := 0
	var tiles := (width - 1) * (height - 1)
	for iy in range(height - 1):
		for ix in range(width - 1):
			var cliff := is_cliff_tile(layers, width, ix, iy)
			var ramp := is_ramp_tile(flags, width, ix, iy)
			if cliff:
				cliffs += 1
			if ramp:
				ramps += 1
			if cliff or ramp:
				gaps += 1
	return {"gaps": gaps, "cliffs": cliffs, "ramps": ramps, "tiles": tiles}
