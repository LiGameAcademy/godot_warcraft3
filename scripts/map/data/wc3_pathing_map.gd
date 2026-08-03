class_name Wc3PathingMap
extends RefCounted
## WPM 寻路面：每格 32 WC3 单位（地形格 1/4）。
## flags 位与 war3map.wpm 一致。


const FLAG_NO_WALK := 0x02
const FLAG_NO_FLY := 0x04
const FLAG_NO_BUILD := 0x08
const FLAG_BLIGHT := 0x20
const FLAG_NO_WATER := 0x40 ## 1 = 干燥；0 = 水面相关
const FLAG_UNKNOWN := 0x80

const CELLS_PER_TILE := 4

var format_version: int = 0
var width: int = 0 ## pathing cells
var height: int = 0
var cell_size: float = Wc3Coords.PATHING_CELL
var cells: PackedByteArray = PackedByteArray()
## 与 heightfield 对齐的世界原点（左下角 tilepoint）
var origin_wc3: Vector2 = Vector2.ZERO


func is_valid() -> bool:
	return width > 0 and height > 0 and cells.size() >= width * height


func clear() -> void:
	format_version = 0
	width = 0
	height = 0
	cells = PackedByteArray()
	origin_wc3 = Vector2.ZERO


static func from_dict(d: Dictionary) -> Wc3PathingMap:
	var m := Wc3PathingMap.new()
	if d.is_empty():
		return m
	m.format_version = int(d.get("formatVersion", 0))
	m.width = int(d.get("width", 0))
	m.height = int(d.get("height", 0))
	m.cell_size = float(d.get("cellSize", Wc3Coords.PATHING_CELL))
	var o: Variant = d.get("origin", null)
	if typeof(o) == TYPE_DICTIONARY:
		m.origin_wc3 = Vector2(float(o.get("x", 0.0)), float(o.get("y", 0.0)))
	var b64 := str(d.get("cellsBase64", ""))
	if not b64.is_empty():
		m.cells = Marshalls.base64_to_raw(b64)
	elif d.has("cells") and d["cells"] is Array:
		var arr: Array = d["cells"]
		m.cells.resize(arr.size())
		for i in range(arr.size()):
			m.cells[i] = int(arr[i]) & 0xFF
	return m


func to_dict() -> Dictionary:
	return {
		"formatVersion": format_version,
		"width": width,
		"height": height,
		"cellSize": cell_size,
		"origin": {"x": origin_wc3.x, "y": origin_wc3.y},
		"cellsBase64": Marshalls.raw_to_base64(cells),
	}


static func load_json_path(res_or_abs: String) -> Wc3PathingMap:
	var disk := RuntimeAssets.project_abs(res_or_abs) if res_or_abs.begins_with("res://") else res_or_abs
	if not FileAccess.file_exists(disk):
		return null
	var f := FileAccess.open(disk, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var m := from_dict(parsed as Dictionary)
	return m if m.is_valid() else null


func flag_at(px: int, py: int) -> int:
	if px < 0 or py < 0 or px >= width or py >= height:
		return FLAG_NO_WALK | FLAG_NO_FLY | FLAG_NO_BUILD | FLAG_UNKNOWN
	var i: int = py * width + px
	if i < 0 or i >= cells.size():
		return FLAG_NO_WALK | FLAG_NO_BUILD
	return int(cells[i])


func can_walk_cell(px: int, py: int) -> bool:
	return (flag_at(px, py) & FLAG_NO_WALK) == 0


func can_build_cell(px: int, py: int) -> bool:
	return (flag_at(px, py) & FLAG_NO_BUILD) == 0


## WC3 世界坐标 → 寻路格索引（左下为 origin）。
func world_to_cell(wc3_x: float, wc3_y: float) -> Vector2i:
	var lx: float = (wc3_x - origin_wc3.x) / cell_size
	var ly: float = (wc3_y - origin_wc3.y) / cell_size
	return Vector2i(int(floor(lx)), int(floor(ly)))


func cell_center_wc3(px: int, py: int) -> Vector2:
	return Vector2(
		origin_wc3.x + (float(px) + 0.5) * cell_size,
		origin_wc3.y + (float(py) + 0.5) * cell_size
	)


## 以世界点为中心、footprint 寻路格尺寸，检查是否全部可建造。
func can_build_footprint(wc3_x: float, wc3_y: float, cells_w: int, cells_h: int) -> bool:
	if cells_w <= 0 or cells_h <= 0:
		return can_build_at(wc3_x, wc3_y)
	var half_w := float(cells_w) * 0.5
	var half_h := float(cells_h) * 0.5
	var min_c := world_to_cell(wc3_x - half_w * cell_size, wc3_y - half_h * cell_size)
	for dy in range(cells_h):
		for dx in range(cells_w):
			if not can_build_cell(min_c.x + dx, min_c.y + dy):
				return false
	return true


func can_walk_at(wc3_x: float, wc3_y: float) -> bool:
	var c := world_to_cell(wc3_x, wc3_y)
	return can_walk_cell(c.x, c.y)


func can_build_at(wc3_x: float, wc3_y: float) -> bool:
	var c := world_to_cell(wc3_x, wc3_y)
	return can_build_cell(c.x, c.y)


## 从 heightfield + Terrain.slk 合成静态寻路面（无 WPM 时的回退）。
static func synthesize_from_heightfield(
	hf: Wc3Heightfield,
	tiles: Wc3TerrainTileCatalog
) -> Wc3PathingMap:
	var m := Wc3PathingMap.new()
	if hf == null or not hf.is_valid():
		return m
	var map_w: int = hf.map_width
	var map_h: int = hf.map_height
	m.width = map_w * CELLS_PER_TILE
	m.height = map_h * CELLS_PER_TILE
	m.cell_size = Wc3Coords.PATHING_CELL
	m.origin_wc3 = hf.center_offset
	m.cells.resize(m.width * m.height)
	var ground: Array = hf.ground_tilesets
	for cy in range(m.height):
		for cx in range(m.width):
			var tile_x: int = cx / CELLS_PER_TILE
			var tile_y: int = cy / CELLS_PER_TILE
			var flags: int = FLAG_NO_WATER
			# 用地形格左下角顶点属性
			var tpi: int = hf.index_at(tile_x, tile_y) if hf.in_bounds(tile_x, tile_y) else -1
			if tpi < 0:
				flags = FLAG_NO_WALK | FLAG_NO_FLY | FLAG_NO_BUILD | FLAG_UNKNOWN
				m.cells[cy * m.width + cx] = flags
				continue
			var tp_flags: int = int(hf.flags_packed[tpi])
			if (tp_flags & (Wc3Coords.FLAG_BOUNDARY | Wc3Coords.FLAG_MAP_EDGE)) != 0:
				flags = FLAG_NO_WALK | FLAG_NO_FLY | FLAG_NO_BUILD | FLAG_UNKNOWN
				m.cells[cy * m.width + cx] = flags
				continue
			var gidx: int = int(hf.ground_textures[tpi])
			var tile_id := ""
			if gidx >= 0 and gidx < ground.size():
				tile_id = str(ground[gidx])
			var walkable := true
			var buildable := true
			if tiles != null and not tile_id.is_empty():
				buildable = tiles.is_buildable(tile_id)
				walkable = tiles.is_walkable(tile_id)
			var has_water: bool = (tp_flags & Wc3Coords.FLAG_WATER) != 0
			if has_water:
				flags = FLAG_NO_WALK | FLAG_NO_BUILD # 深水近似；浅水 WE 常仅 no-build
				# 若水面高度接近地面则视为浅水：仅不可建造
				var gh: float = float(hf.heights[tpi])
				var wh: float = float(hf.water_heights[tpi]) if tpi < hf.water_heights.size() else gh
				if wh - gh < Wc3CliffLogic.LAYER_HEIGHT_STEP * 0.35:
					flags = FLAG_NO_BUILD
			else:
				if not walkable:
					flags |= FLAG_NO_WALK
				if not buildable:
					flags |= FLAG_NO_BUILD
			# 悬崖格：层差 → 不可走/建
			if _is_cliff_cell(hf, tile_x, tile_y):
				flags |= FLAG_NO_WALK | FLAG_NO_BUILD | FLAG_NO_FLY
			if (tp_flags & Wc3Coords.FLAG_BLIGHT) != 0:
				flags |= FLAG_BLIGHT
			m.cells[cy * m.width + cx] = flags & 0xFF
	return m


static func _is_cliff_cell(hf: Wc3Heightfield, tile_x: int, tile_y: int) -> bool:
	if not hf.in_bounds(tile_x, tile_y) or not hf.in_bounds(tile_x + 1, tile_y + 1):
		return false
	var bl: int = int(hf.layer_heights[hf.index_at(tile_x, tile_y)])
	var br: int = int(hf.layer_heights[hf.index_at(tile_x + 1, tile_y)])
	var tl: int = int(hf.layer_heights[hf.index_at(tile_x, tile_y + 1)])
	var tr: int = int(hf.layer_heights[hf.index_at(tile_x + 1, tile_y + 1)])
	var mn: int = mini(mini(bl, br), mini(tl, tr))
	var mx: int = maxi(maxi(bl, br), maxi(tl, tr))
	return mx > mn


## 确保 origin 与当前 heightfield 对齐（pathing.json 可能未写 origin）。
func sync_origin_from_heightfield(hf: Wc3Heightfield) -> void:
	if hf == null or not hf.is_valid():
		return
	origin_wc3 = hf.center_offset
	if width <= 0 and hf.map_width > 0:
		width = hf.map_width * CELLS_PER_TILE
		height = hf.map_height * CELLS_PER_TILE
