class_name Wc3TileVertex
extends RefCounted
## 瓦片顶点（tilepoint）视图：指向 Wc3Heightfield 某一 index，读写即改 SoA。
## WC3 网格改动的基本单位；不要脱离 Heightfield 长期缓存大量实例。

## 所属高度场
var heightfield: Wc3Heightfield
## 瓦片点索引
var ix: int = 0
## 瓦片点索引
var iy: int = 0
## 瓦片点索引
var index: int = 0

var height: float:
	get:
		return float(heightfield.heights[index])
	set(v):
		heightfield.heights[index] = v


var layer: int:
	get:
		return int(heightfield.layer_heights[index])
	set(v):
		heightfield.layer_heights[index] = v


var water_height: float:
	get:
		if index >= heightfield.water_heights.size():
			return height
		return float(heightfield.water_heights[index])
	set(v):
		if index >= heightfield.water_heights.size():
			return
		heightfield.water_heights[index] = v


var flags: int:
	get:
		return int(heightfield.flags_packed[index])
	set(v):
		heightfield.flags_packed[index] = v


var ground_tex: int:
	get:
		return int(heightfield.ground_textures[index]) if index < heightfield.ground_textures.size() else 0
	set(v):
		if index < heightfield.ground_textures.size():
			heightfield.ground_textures[index] = v


var ground_var: int:
	get:
		return (
			int(heightfield.ground_variations[index])
			if index < heightfield.ground_variations.size()
			else 0
		)
	set(v):
		if index < heightfield.ground_variations.size():
			heightfield.ground_variations[index] = v


var cliff_tex: int:
	get:
		return int(heightfield.cliff_textures[index]) if index < heightfield.cliff_textures.size() else 0
	set(v):
		if index < heightfield.cliff_textures.size():
			heightfield.cliff_textures[index] = v


var cliff_var: int:
	get:
		return (
			int(heightfield.cliff_variations[index])
			if index < heightfield.cliff_variations.size()
			else 0
		)
	set(v):
		if index < heightfield.cliff_variations.size():
			heightfield.cliff_variations[index] = v


var has_water: bool:
	get:
		return (flags & Wc3Coords.FLAG_WATER) != 0
	set(v):
		if v:
			flags = flags | Wc3Coords.FLAG_WATER
		else:
			flags = flags & ~Wc3Coords.FLAG_WATER


var has_ramp: bool:
	get:
		return (flags & Wc3Coords.FLAG_RAMP) != 0
	set(v):
		if v:
			flags = (flags | Wc3Coords.FLAG_RAMP) & ~Wc3Coords.FLAG_WATER
		else:
			flags = flags & ~Wc3Coords.FLAG_RAMP


func wc3_xy() -> Vector2:
	return Wc3Coords.tilepoint_wc3(
		ix, iy, heightfield.center_offset, heightfield.tile_size
	)


func godot_position() -> Vector3:
	var xy := wc3_xy()
	return Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, height)


static func create(hf: Wc3Heightfield, p_ix: int, p_iy: int) -> Wc3TileVertex:
	var v := Wc3TileVertex.new()
	v.heightfield = hf
	v.ix = p_ix
	v.iy = p_iy
	v.index = hf.index_at(p_ix, p_iy)
	return v

func is_valid() -> bool:
	return (
		heightfield != null
		and heightfield.in_bounds(ix, iy)
		and index == heightfield.index_at(ix, iy)
	)
