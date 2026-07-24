class_name Wc3Heightfield
extends RefCounted

## 对应 map-parsed/*/terrain-heightfield.json（SoA 平行数组）。
## 单顶点请用 vertex_at() → Wc3TileVertex，不要手写 hf["heights"][i]。


var width: int = 0								## 瓦片点宽度
var height: int = 0								## 瓦片点高度
var map_width: int = 0							## 地图宽度
var map_height: int = 0							## 地图宽度
var tile_size: float = Wc3Coords.TILE_SIZE		## 瓦片大小
var center_offset: Vector2 = Vector2.ZERO		## 中心偏移
var main_tileset: String = ""					## 主地形纹理集
var main_tileset_name: String = ""				## 主地形纹理集名称	
var ground_tilesets: Array = []					## 地面纹理集列表
var cliff_tilesets: Array = []					## 悬崖纹理集列表

## 平行数组，长度恒为 width * height（JSON 同形，元素为 Variant 数字）。
var heights: Array = []
var layer_heights: Array = []
var water_heights: Array = []
var flags_packed: Array = []
var ground_textures: Array = []
var ground_variations: Array = []
var cliff_textures: Array = []
var cliff_variations: Array = []


func tilepoint_count() -> int:
	return width * height


func is_valid() -> bool:
	var n := tilepoint_count()
	return (
		width > 0
		and height > 0
		and heights.size() == n
		and layer_heights.size() == n
		and flags_packed.size() == n
	)


func index_at(ix: int, iy: int) -> int:
	return iy * width + ix


func in_bounds(ix: int, iy: int) -> bool:
	return ix >= 0 and iy >= 0 and ix < width and iy < height


## 按需创建顶点视图（非缓存；调用方短生命周期持有即可）。
func vertex_at(ix: int, iy: int) -> Wc3TileVertex:
	if not in_bounds(ix, iy):
		return null
	return Wc3TileVertex.create(self, ix, iy)


func vertex_at_index(index: int) -> Wc3TileVertex:
	if index < 0 or index >= tilepoint_count():
		return null
	var ix: int = index % width
	var iy: int = int(index / width)
	return Wc3TileVertex.create(self, ix, iy)


## [param duplicate_arrays] true：拷贝平行数组（安全默认）；false：共享引用（编辑器重建 / 视图包装）。
static func from_dict(d: Dictionary, duplicate_arrays: bool = true) -> Wc3Heightfield:
	var hf := Wc3Heightfield.new()
	hf.width = int(d.get("tilepointWidth", 0))
	hf.height = int(d.get("tilepointHeight", 0))
	hf.map_width = int(d.get("mapWidth", maxi(hf.width - 1, 0)))
	hf.map_height = int(d.get("mapHeight", maxi(hf.height - 1, 0)))
	hf.tile_size = float(d.get("tileSize", Wc3Coords.TILE_SIZE))
	var co: Dictionary = d.get("centerOffset", {}) as Dictionary
	hf.center_offset = Vector2(float(co.get("x", 0.0)), float(co.get("y", 0.0)))
	hf.main_tileset = str(d.get("mainTileset", ""))
	hf.main_tileset_name = str(d.get("mainTilesetName", ""))
	hf.ground_tilesets = _arr(d.get("groundTilesets", []), duplicate_arrays)
	hf.cliff_tilesets = _arr(d.get("cliffTilesets", []), duplicate_arrays)
	hf.heights = _arr(d.get("heights", []), duplicate_arrays)
	hf.layer_heights = _arr(d.get("layerHeights", []), duplicate_arrays)
	hf.water_heights = _arr(d.get("waterHeights", []), duplicate_arrays)
	hf.flags_packed = _arr(d.get("flagsPacked", []), duplicate_arrays)
	hf.ground_textures = _arr(d.get("groundTextures", []), duplicate_arrays)
	hf.ground_variations = _arr(d.get("groundVariations", []), duplicate_arrays)
	hf.cliff_textures = _arr(d.get("cliffTextures", []), duplicate_arrays)
	hf.cliff_variations = _arr(d.get("cliffVariations", []), duplicate_arrays)
	# 缺水高时与地面齐平，避免空数组
	if hf.water_heights.is_empty() and not hf.heights.is_empty():
		hf.water_heights = hf.heights.duplicate()
	return hf


static func _arr(v: Variant, duplicate_arrays: bool) -> Array:
	var a: Array = v as Array if typeof(v) == TYPE_ARRAY else []
	return a.duplicate() if duplicate_arrays else a


## 与 JSON 同形的 Dictionary；平行数组为共享引用（供笔刷 / Loader 兼容路径）。
func as_dict_view() -> Dictionary:
	return {
		"tilepointWidth": width,
		"tilepointHeight": height,
		"mapWidth": map_width,
		"mapHeight": map_height,
		"centerOffset": {"x": center_offset.x, "y": center_offset.y},
		"mainTileset": main_tileset,
		"mainTilesetName": main_tileset_name,
		"groundTilesets": ground_tilesets,
		"cliffTilesets": cliff_tilesets,
		"tileSize": tile_size,
		"heights": heights,
		"groundTextures": ground_textures,
		"groundVariations": ground_variations,
		"cliffVariations": cliff_variations,
		"cliffTextures": cliff_textures,
		"layerHeights": layer_heights,
		"waterHeights": water_heights,
		"flagsPacked": flags_packed,
	}


## 构建器用 meta（与历史 read_heightfield_meta 同形）；数组共享引用。
func to_build_meta() -> Dictionary:
	return {
		"width": width,
		"height": height,
		"tile_size": tile_size,
		"center": center_offset,
		"heights": heights,
		"water_heights": water_heights,
		"ground_textures": ground_textures,
		"ground_variations": ground_variations,
		"cliff_textures": cliff_textures,
		"cliff_variations": cliff_variations,
		"layer_heights": layer_heights,
		"flags": flags_packed,
		"ground_tilesets": ground_tilesets,
		"cliff_tilesets": cliff_tilesets,
		"main_tileset": main_tileset,
	}


## Dictionary 边界适配（不经第二份权威拷贝造 meta）。
static func build_meta_from_dict(hf: Dictionary) -> Dictionary:
	return from_dict(hf, false).to_build_meta()


func to_dict() -> Dictionary:
	return {
		"tilepointWidth": width,
		"tilepointHeight": height,
		"mapWidth": map_width,
		"mapHeight": map_height,
		"centerOffset": {"x": center_offset.x, "y": center_offset.y},
		"mainTileset": main_tileset,
		"mainTilesetName": main_tileset_name,
		"groundTilesets": ground_tilesets.duplicate(),
		"cliffTilesets": cliff_tilesets.duplicate(),
		"tileSize": tile_size,
		"heights": heights.duplicate(),
		"groundTextures": ground_textures.duplicate(),
		"groundVariations": ground_variations.duplicate(),
		"cliffVariations": cliff_variations.duplicate(),
		"cliffTextures": cliff_textures.duplicate(),
		"layerHeights": layer_heights.duplicate(),
		"waterHeights": water_heights.duplicate(),
		"flagsPacked": flags_packed.duplicate(),
	}


static func load_json_path(res_or_abs: String) -> Wc3Heightfield:
	var abs := RuntimeAssets.project_abs(res_or_abs)
	if not FileAccess.file_exists(abs):
		push_error("Wc3Heightfield: 文件不存在 %s" % abs)
		return null
	var f := FileAccess.open(abs, FileAccess.READ)
	if f == null:
		push_error("Wc3Heightfield: 无法打开 %s" % abs)
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Wc3Heightfield: JSON 根不是对象 %s" % abs)
		return null
	return from_dict(parsed as Dictionary)
