class_name EditorVertexSnapshot
extends RefCounted

## 单 tilepoint 全量快照，供笔划命令 undo/redo。


var index: int = -1
var height: float = 0.0
var layer: int = 0
var water_height: float = 0.0
var flags: int = 0
var ground_tex: int = 0
var ground_var: int = 0
var cliff_tex: int = 0
var cliff_var: int = 0


static func capture(hf: Wc3Heightfield, ix: int, iy: int) -> EditorVertexSnapshot:
	if hf == null or not hf.in_bounds(ix, iy):
		return null
	var i: int = hf.index_at(ix, iy)
	var s := EditorVertexSnapshot.new()
	s.index = i
	s.height = float(hf.heights[i]) if i < hf.heights.size() else 0.0
	s.layer = int(hf.layer_heights[i]) if i < hf.layer_heights.size() else 0
	s.water_height = (
		float(hf.water_heights[i]) if i < hf.water_heights.size() else s.height
	)
	s.flags = int(hf.flags_packed[i]) if i < hf.flags_packed.size() else 0
	s.ground_tex = int(hf.ground_textures[i]) if i < hf.ground_textures.size() else 0
	s.ground_var = (
		int(hf.ground_variations[i]) if i < hf.ground_variations.size() else 0
	)
	s.cliff_tex = int(hf.cliff_textures[i]) if i < hf.cliff_textures.size() else 0
	s.cliff_var = (
		int(hf.cliff_variations[i]) if i < hf.cliff_variations.size() else 0
	)
	return s


func apply(hf: Wc3Heightfield) -> void:
	if hf == null or index < 0:
		return
	var i := index
	if i < hf.heights.size():
		hf.heights[i] = height
	if i < hf.layer_heights.size():
		hf.layer_heights[i] = layer
	if i < hf.water_heights.size():
		hf.water_heights[i] = water_height
	if i < hf.flags_packed.size():
		hf.flags_packed[i] = flags
	if i < hf.ground_textures.size():
		hf.ground_textures[i] = ground_tex
	if i < hf.ground_variations.size():
		hf.ground_variations[i] = ground_var
	if i < hf.cliff_textures.size():
		hf.cliff_textures[i] = cliff_tex
	if i < hf.cliff_variations.size():
		hf.cliff_variations[i] = cliff_var


func equals_snap(other: EditorVertexSnapshot) -> bool:
	if other == null or index != other.index:
		return false
	return (
		is_equal_approx(height, other.height)
		and layer == other.layer
		and is_equal_approx(water_height, other.water_height)
		and flags == other.flags
		and ground_tex == other.ground_tex
		and ground_var == other.ground_var
		and cliff_tex == other.cliff_tex
		and cliff_var == other.cliff_var
	)
