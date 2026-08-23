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
var cells: PackedByteArray = PackedByteArray() ## 静态（WPM / 地形合成）
## 动态：建筑/装饰 pathTex blit（OR 进查询与 overlay）
var cells_dynamic: PackedByteArray = PackedByteArray()
## 与 heightfield 对齐的世界原点（左下角 tilepoint）
var origin_wc3: Vector2 = Vector2.ZERO


func is_valid() -> bool:
	return width > 0 and height > 0 and cells.size() >= width * height


func clear() -> void:
	format_version = 0
	width = 0
	height = 0
	cells = PackedByteArray()
	cells_dynamic = PackedByteArray()
	origin_wc3 = Vector2.ZERO


func _ensure_dynamic() -> void:
	var n: int = width * height
	if n <= 0:
		return
	if cells_dynamic.size() != n:
		cells_dynamic.resize(n)
		cells_dynamic.fill(0)


func clear_dynamic() -> void:
	_ensure_dynamic()
	if cells_dynamic.size() > 0:
		cells_dynamic.fill(0)


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
	var text := RuntimeAssets.read_utf8_text(disk)
	if text.is_empty():
		return null
	var parsed: Variant = RuntimeAssets.parse_json_text(text)
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
	var f: int = int(cells[i])
	if i < cells_dynamic.size():
		f |= int(cells_dynamic[i])
	return f


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
			var tile_x: int = int(float(cx) / float(CELLS_PER_TILE))
			var tile_y: int = int(float(cy) / float(CELLS_PER_TILE))
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
	var top_right: int = int(hf.layer_heights[hf.index_at(tile_x + 1, tile_y + 1)])
	var mn: int = mini(mini(bl, br), mini(tl, top_right))
	var mx: int = maxi(maxi(bl, br), maxi(tl, top_right))
	return mx > mn


## 确保 origin 与当前 heightfield 对齐（pathing.json 可能未写 origin）。
func sync_origin_from_heightfield(hf: Wc3Heightfield) -> void:
	if hf == null or not hf.is_valid():
		return
	origin_wc3 = hf.center_offset
	if width <= 0 and hf.map_width > 0:
		width = hf.map_width * CELLS_PER_TILE
		height = hf.map_height * CELLS_PER_TILE


## 将 PathTextures 图居中 blit 到动态层（对齐 HiveWE：地形格坐标 ×4，90° 步进）。
## tile_x/y = (wc3 - origin) / 128；rotation_deg 取最近 90°。
func blit_pathing_image(tile_x: float, tile_y: float, rotation_deg: int, img: Image) -> void:
	if img == null or not is_valid():
		return
	_ensure_dynamic()
	var tw: int = img.get_width()
	var th: int = img.get_height()
	if tw <= 0 or th <= 0:
		return
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var rot: int = ((rotation_deg % 360) + 360) % 360
	rot = int(round(float(rot) / 90.0)) * 90 % 360
	var div_w: int = th if (rot % 180) != 0 else tw
	var div_h: int = tw if (rot % 180) != 0 else th
	var thresh := 250.0 / 255.0
	for j in range(th):
		for i in range(tw):
			var x: int = i
			var y: int = j
			match rot:
				90:
					x = th - 1 - j
					y = i
				180:
					x = tw - 1 - i
					y = th - 1 - j
				270:
					x = j
					y = tw - 1 - i
			# 与 HiveWE 一致：底行优先采样（其 TGA 数据经 SOIL 后按 (h-1-j) 读）
			var c: Color = img.get_pixel(i, th - 1 - j)
			var bytes: int = 0
			if c.r > thresh:
				bytes |= FLAG_NO_WALK
			if c.g > thresh:
				bytes |= FLAG_NO_FLY
			if c.b > thresh:
				bytes |= FLAG_NO_BUILD
			if bytes == 0:
				continue
			var xx: int = int(floor(tile_x * float(CELLS_PER_TILE))) + x - (div_w >> 1)
			var yy: int = int(floor(tile_y * float(CELLS_PER_TILE))) + y - (div_h >> 1)
			if xx < 0 or yy < 0 or xx >= width or yy >= height:
				continue
			var di: int = yy * width + xx
			cells_dynamic[di] = int(cells_dynamic[di]) | bytes


func blit_pathing_at_world(wc3_x: float, wc3_y: float, angle_deg: float, img: Image) -> void:
	var tile_x: float = (wc3_x - origin_wc3.x) / Wc3Coords.TILE_SIZE
	var tile_y: float = (wc3_y - origin_wc3.y) / Wc3Coords.TILE_SIZE
	# 对齐 HiveWE doodad：degrees(angle)+90
	var rot: int = int(round(angle_deg)) + 90
	blit_pathing_image(tile_x, tile_y, rot, img)


## 扫单位/装饰列表，按 Catalog.path_tex blit 动态脚印（建筑、中立建筑、阻挡物等）。
## 返回成功 blit 条数。
##
## 跳过 Start Location（sloc）：地图里常有多个出生点，游戏只占其中一个；
## sloc 的 path_tex 是编辑器占位脚印，不应写入运行时寻路（否则空出生点也会锁死主城栅格）。
func apply_entity_pathing(entries: Array, catalog: Wc3IdCatalog) -> int:
	clear_dynamic()
	if not is_valid() or catalog == null:
		return 0
	var n := 0
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var type_id := str(d.get("typeId", d.get("id", "")))
		if type_id.is_empty():
			continue
		if type_id == "sloc":
			continue
		var info: Dictionary = catalog.lookup(type_id)
		if bool(info.get("is_start_location", false)):
			continue
		var path_tex := str(info.get("path_tex", ""))
		if not Wc3PathingTextures.is_valid_path_tex(path_tex):
			continue
		var img := Wc3PathingTextures.load_image(path_tex)
		var pos: Variant = d.get("position", {})
		var wx := 0.0
		var wy := 0.0
		if typeof(pos) == TYPE_DICTIONARY:
			wx = float(pos.get("x", 0.0))
			wy = float(pos.get("y", 0.0))
		elif pos is Vector3:
			wx = (pos as Vector3).x
			wy = (pos as Vector3).y
		elif pos is Vector2:
			wx = (pos as Vector2).x
			wy = (pos as Vector2).y
		var ang := float(d.get("angle", d.get("facing", 4.71238898)))
		# JSON 存弧度（≈±2π）；若已是度数（如编辑器笔刷）则原样
		var ang_deg := rad_to_deg(ang) if absf(ang) <= TAU + 0.5 else ang
		if img != null:
			blit_pathing_at_world(wx, wy, ang_deg, img)
			n += 1
		else:
			# TGA 缺失时仍按文件名 WxH 画实心脚印，避免「建筑已放叠层不更新」
			var cells: Vector2i = Wc3IdCatalog.parse_path_tex_cells(path_tex)
			if cells.x > 0 and cells.y > 0:
				blit_solid_footprint_at_world(
					wx, wy, cells.x, cells.y, FLAG_NO_WALK | FLAG_NO_BUILD
				)
				n += 1
	return n


## 无 pathTex 图时：以世界点为中心填实心脚印（寻路格）。
func blit_solid_footprint_at_world(
	wc3_x: float,
	wc3_y: float,
	cells_w: int,
	cells_h: int,
	flags: int
) -> void:
	if not is_valid() or cells_w <= 0 or cells_h <= 0:
		return
	_ensure_dynamic()
	var half_w := float(cells_w) * 0.5
	var half_h := float(cells_h) * 0.5
	var min_c := world_to_cell(wc3_x - half_w * cell_size, wc3_y - half_h * cell_size)
	var f: int = flags & 0xFF
	for dy in range(cells_h):
		for dx in range(cells_w):
			var xx: int = min_c.x + dx
			var yy: int = min_c.y + dy
			if xx < 0 or yy < 0 or xx >= width or yy >= height:
				continue
			var di: int = yy * width + xx
			cells_dynamic[di] = int(cells_dynamic[di]) | f
