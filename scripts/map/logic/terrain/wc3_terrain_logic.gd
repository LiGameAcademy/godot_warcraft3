class_name Wc3TerrainLogic
extends RefCounted

## 高度图 / 地表逻辑层：只改 Wc3Heightfield，不建 Mesh、不查资产路径。
## 脏矩形供表现层局部重建（现阶段可先全量，接口已预留）。


const LAYER_MIN := 0
const LAYER_MAX := 14
const FLAT_LAYER := 2

var heightfield: Wc3Heightfield = null
## 脏区（含边界）；_dirty_valid=false 表示无脏
var dirty_min: Vector2i = Vector2i.ZERO
var dirty_max: Vector2i = Vector2i.ZERO
var _dirty_valid: bool = false


func bind(hf: Wc3Heightfield) -> Wc3TerrainLogic:
	heightfield = hf
	clear_dirty()
	return self


func is_bound() -> bool:
	return heightfield != null and heightfield.width >= 2


func clear_dirty() -> void:
	_dirty_valid = false
	dirty_min = Vector2i.ZERO
	dirty_max = Vector2i.ZERO


func has_dirty() -> bool:
	return _dirty_valid


## 取出并清空脏矩形（tilepoint 坐标，闭区间 → Rect2i position/size）。
func take_dirty_rect() -> Rect2i:
	if not _dirty_valid:
		return Rect2i()
	var r := Rect2i(dirty_min, dirty_max - dirty_min + Vector2i.ONE)
	clear_dirty()
	return r


func _mark_dirty(ix: int, iy: int) -> void:
	if not _dirty_valid:
		dirty_min = Vector2i(ix, iy)
		dirty_max = Vector2i(ix, iy)
		_dirty_valid = true
		return
	dirty_min.x = mini(dirty_min.x, ix)
	dirty_min.y = mini(dirty_min.y, iy)
	dirty_max.x = maxi(dirty_max.x, ix)
	dirty_max.y = maxi(dirty_max.y, iy)


func vertex_at(ix: int, iy: int) -> Wc3TileVertex:
	if not is_bound():
		return null
	return heightfield.vertex_at(ix, iy)


func layer_at(ix: int, iy: int) -> int:
	if not is_bound() or not heightfield.in_bounds(ix, iy):
		return FLAT_LAYER
	var i: int = heightfield.index_at(ix, iy)
	return clampi(int(heightfield.layer_heights[i]), LAYER_MIN, LAYER_MAX)


func height_at(ix: int, iy: int) -> float:
	if not is_bound() or not heightfield.in_bounds(ix, iy):
		return 0.0
	return float(heightfield.heights[heightfield.index_at(ix, iy)])


## 正交四邻层高（越界为 FLAT_LAYER）。顺序：左、右、下、上。
func neighbor_layers(ix: int, iy: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(4)
	out[0] = layer_at(ix - 1, iy)
	out[1] = layer_at(ix + 1, iy)
	out[2] = layer_at(ix, iy - 1)
	out[3] = layer_at(ix, iy + 1)
	return out


## 写地表索引；可选随机 groundVariation（对齐笔刷）。
func set_ground_tex(ix: int, iy: int, tex_index: int, randomize_var: bool = true) -> bool:
	if not is_bound() or not heightfield.in_bounds(ix, iy):
		return false
	var gs: Array = heightfield.ground_tilesets
	if tex_index < 0 or tex_index >= gs.size():
		return false
	var i: int = heightfield.index_at(ix, iy)
	var changed := false
	if int(heightfield.ground_textures[i]) != tex_index:
		heightfield.ground_textures[i] = tex_index
		changed = true
	if randomize_var and i < heightfield.ground_variations.size():
		heightfield.ground_variations[i] = Wc3TerrainAutotile.random_ground_variation()
		changed = true
	if changed:
		_mark_dirty(ix, iy)
	return changed


func set_height(ix: int, iy: int, h: float) -> bool:
	if not is_bound() or not heightfield.in_bounds(ix, iy):
		return false
	var i: int = heightfield.index_at(ix, iy)
	if is_equal_approx(float(heightfield.heights[i]), h):
		return false
	heightfield.heights[i] = h
	_mark_dirty(ix, iy)
	return true


## 单 tilepoint 地表（与 MapDocument.paint_corner 同语义）。
func paint_corner(ix: int, iy: int, tex_index: int) -> bool:
	return set_ground_tex(ix, iy, tex_index, true)


## 地表格四角地表。
func paint_tile(tx: int, ty: int, tex_index: int) -> bool:
	if not is_bound():
		return false
	var map_w: int = heightfield.map_width
	var map_h: int = heightfield.map_height
	if tx < 0 or ty < 0 or tx >= map_w or ty >= map_h:
		return false
	var changed_any := false
	for c in [
		Vector2i(tx, ty),
		Vector2i(tx + 1, ty),
		Vector2i(tx, ty + 1),
		Vector2i(tx + 1, ty + 1),
	]:
		if paint_corner(c.x, c.y, tex_index):
			changed_any = true
	return changed_any


func sample_height_at_tile(tx: int, ty: int) -> float:
	if not is_bound():
		return 0.0
	var sum := 0.0
	var n := 0
	for c in [
		Vector2i(tx, ty),
		Vector2i(tx + 1, ty),
		Vector2i(tx, ty + 1),
		Vector2i(tx + 1, ty + 1),
	]:
		if heightfield.in_bounds(c.x, c.y):
			sum += height_at(c.x, c.y)
			n += 1
	return sum / float(n) if n > 0 else 0.0
