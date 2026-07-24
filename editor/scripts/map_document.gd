extends RefCounted
## 可编辑地图文档：内存中的 terrain-heightfield（与 map-parsed JSON 同形）。
## （不用 class_name；编辑器通过 preload 引用）

signal changed
signal dirty_changed(is_dirty: bool)

const DEFAULT_MAP_DIR := "res://assets/map-parsed/losttemple"
const BLANK_TILEPOINTS := 33 ## → 32×32 格
const DEFAULT_TILESET := "I"
const DEFAULT_TILESET_NAME := "Icecrown"
const DEFAULT_GROUND := ["Idrt", "Idtr", "Idki", "Ibkb", "Irbk", "Itbk", "Iice", "Ibsq", "Isnw"]
const DEFAULT_CLIFF := ["CIsn", "CIrb"]
## layerHeight=2 时 groundHeightRaw=0x2000 → 高度 0
const FLAT_HEIGHT := 0.0
const FLAT_LAYER := 2
const LAYER_MIN := 0
const LAYER_MAX := 14
## 悬崖层差上限（WE / 官方模型仅 A/B/C）：
## 1) 正交相邻顶点最多差 2；2) 同一地表格四角 max−min 也不得超过 2
## （仅约束正交时，对角可差 3 → 出现 D 级相对高、叠片碎柱）。
## 再升高则把较低点抬到 high-2（叠蛋糕外扩）；再降低则把较高点压到 low+2。
const MAX_CLIFF_ADJ_DELTA := 2
## 悬崖层差 1 → WC3 高度 128（与 W3E / create_from_options 一致）
const LAYER_HEIGHT_STEP := 128.0

enum CliffPropagate {
	RAISE_LOWER = 0, ## 升：抬低邻
	LOWER_HIGHER = 1, ## 降：压高邻
	BOTH = 2,
}
const WATER_SHALLOW_EXTRA := 48.0
const WATER_DEEP_EXTRA := 128.0
const FLAG_WATER := Wc3Coords.FLAG_WATER
const FLAG_RAMP := Wc3Coords.FLAG_RAMP

var hf: Dictionary = {}
var info: Dictionary = {}
var map_dir: String = ""
var source_name: String = ""
var brush_tile_index: int = 0
var brush_cliff_type: int = 0
var _dirty: bool = false
## cliffTilesets 下标 → groundTilesets 下标（CliffTypes.groundTile）；-1=未解析
var _cliff_ground_cache: PackedInt32Array = PackedInt32Array()
## 最近一次斜坡笔刷结果（供状态栏 / 自测）
var last_ramp_message: String = ""


func is_dirty() -> bool:
	return _dirty


func mark_dirty() -> void:
	if _dirty:
		changed.emit()
		return
	_dirty = true
	dirty_changed.emit(true)
	changed.emit()


func clear_dirty() -> void:
	if not _dirty:
		return
	_dirty = false
	dirty_changed.emit(false)


func is_empty() -> bool:
	return hf.is_empty() or int(hf.get("tilepointWidth", 0)) < 2


func tilepoint_size() -> Vector2i:
	return Vector2i(int(hf.get("tilepointWidth", 0)), int(hf.get("tilepointHeight", 0)))


func map_size() -> Vector2i:
	var tp: Vector2i = tilepoint_size()
	return Vector2i(maxi(tp.x - 1, 0), maxi(tp.y - 1, 0))


func center_offset() -> Vector2:
	var co: Dictionary = hf.get("centerOffset", {})
	return Vector2(float(co.get("x", 0.0)), float(co.get("y", 0.0)))


func tile_size() -> float:
	return float(hf.get("tileSize", Wc3Coords.TILE_SIZE))


func ground_tilesets() -> Array:
	return hf.get("groundTilesets", []) as Array


func cliff_tilesets() -> Array:
	return hf.get("cliffTilesets", []) as Array


func ensure_brush_index_valid() -> void:
	var n: int = ground_tilesets().size()
	if n <= 0:
		brush_tile_index = 0
		return
	brush_tile_index = clampi(brush_tile_index, 0, n - 1)


func ensure_cliff_type_valid() -> void:
	var n: int = cliff_tilesets().size()
	if n <= 0:
		brush_cliff_type = 0
		return
	brush_cliff_type = clampi(brush_cliff_type, 0, n - 1)


func layer_at(ix: int, iy: int) -> int:
	if is_empty():
		return FLAT_LAYER
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return FLAT_LAYER
	var layers: Array = hf.get("layerHeights", []) as Array
	var i: int = iy * tp_w + ix
	if i < 0 or i >= layers.size():
		return FLAT_LAYER
	return clampi(int(layers[i]), LAYER_MIN, LAYER_MAX)


func brush_tile_id() -> String:
	ensure_brush_index_valid()
	var gs: Array = ground_tilesets()
	if brush_tile_index < 0 or brush_tile_index >= gs.size():
		return ""
	return str(gs[brush_tile_index])


func load_from_map_dir(path: String = DEFAULT_MAP_DIR) -> Error:
	var hf_path: String = path.path_join("terrain-heightfield.json")
	if not FileAccess.file_exists(hf_path):
		push_error("MapDocument: 缺少 %s" % hf_path)
		return ERR_FILE_NOT_FOUND
	var f: FileAccess = FileAccess.open(hf_path, FileAccess.READ)
	if f == null:
		return ERR_CANT_OPEN
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return ERR_PARSE_ERROR
	hf = parsed
	info = {}
	var info_path: String = path.path_join("info.json")
	if FileAccess.file_exists(info_path):
		var fi: FileAccess = FileAccess.open(info_path, FileAccess.READ)
		if fi:
			var ip: Variant = JSON.parse_string(fi.get_as_text())
			if typeof(ip) == TYPE_DICTIONARY:
				info = ip
	map_dir = path
	source_name = path.get_file()
	_dirty = false
	_cliff_ground_cache = PackedInt32Array()
	ensure_brush_index_valid()
	dirty_changed.emit(false)
	changed.emit()
	return OK


func create_blank(
	tilepoints: int = BLANK_TILEPOINTS,
	main_tileset: String = DEFAULT_TILESET
) -> void:
	create_from_options({
		"width": tilepoints - 1,
		"height": tilepoints - 1,
		"main_tileset": main_tileset,
		"main_tileset_name": DEFAULT_TILESET_NAME if main_tileset == "I" else main_tileset,
		"ground_tilesets": DEFAULT_GROUND.duplicate(),
		"cliff_tilesets": DEFAULT_CLIFF.duplicate(),
		"default_tile_index": 0,
		"cliff_level": FLAT_LAYER,
		"water_mode": 0,
		"random_height": false,
	})


## options: width/height(格), main_tileset, ground_tilesets, cliff_tilesets,
## default_tile_index, cliff_level, water_mode(0无/1浅/2深), random_height
func create_from_options(options: Dictionary) -> void:
	var map_w: int = maxi(int(options.get("width", 64)), 2)
	var map_h: int = maxi(int(options.get("height", 64)), 2)
	var tp_w: int = map_w + 1
	var tp_h: int = map_h + 1
	var n: int = tp_w * tp_h
	var half_x: float = float(map_w) * Wc3Coords.TILE_SIZE * 0.5
	var half_y: float = float(map_h) * Wc3Coords.TILE_SIZE * 0.5
	var main_ts: String = str(options.get("main_tileset", DEFAULT_TILESET))
	var ts_name: String = str(options.get("main_tileset_name", main_ts))
	var ground: Array = options.get("ground_tilesets", DEFAULT_GROUND.duplicate()) as Array
	var cliffs: Array = options.get("cliff_tilesets", DEFAULT_CLIFF.duplicate()) as Array
	if ground.is_empty():
		ground = DEFAULT_GROUND.duplicate()
	if cliffs.is_empty():
		cliffs = DEFAULT_CLIFF.duplicate()
	_cliff_ground_cache = PackedInt32Array()
	var tile_index: int = clampi(int(options.get("default_tile_index", 0)), 0, ground.size() - 1)
	var cliff_level: int = clampi(int(options.get("cliff_level", FLAT_LAYER)), 0, 14)
	var water_mode: int = clampi(int(options.get("water_mode", 0)), 0, 2)
	var random_h: bool = bool(options.get("random_height", false))
	var base_h: float = float(cliff_level - 2) * 128.0
	var water_extra: float = 0.0
	if water_mode == 1:
		water_extra = 48.0
	elif water_mode == 2:
		water_extra = 128.0

	var heights: Array = []
	var water_h: Array = []
	var ground_tex: Array = []
	var ground_var: Array = []
	var cliff_var: Array = []
	var cliff_tex: Array = []
	var layers: Array = []
	var flags: Array = []
	heights.resize(n)
	water_h.resize(n)
	ground_tex.resize(n)
	ground_var.resize(n)
	cliff_var.resize(n)
	cliff_tex.resize(n)
	layers.resize(n)
	flags.resize(n)

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in range(n):
		var h: float = base_h
		if random_h:
			h += rng.randf_range(-40.0, 40.0)
		heights[i] = h
		water_h[i] = h + water_extra if water_mode > 0 else h
		ground_tex[i] = tile_index
		ground_var[i] = Wc3TerrainAutotile.random_ground_variation(rng)
		cliff_var[i] = 0
		cliff_tex[i] = 0
		layers[i] = cliff_level
		flags[i] = FLAG_WATER if water_mode > 0 else 0

	hf = {
		"tilepointWidth": tp_w,
		"tilepointHeight": tp_h,
		"mapWidth": map_w,
		"mapHeight": map_h,
		"centerOffset": {"x": -half_x, "y": -half_y},
		"mainTileset": main_ts,
		"mainTilesetName": ts_name,
		"groundTilesets": ground,
		"cliffTilesets": cliffs,
		"tileSize": int(Wc3Coords.TILE_SIZE),
		"heights": heights,
		"groundTextures": ground_tex,
		"groundVariations": ground_var,
		"cliffVariations": cliff_var,
		"cliffTextures": cliff_tex,
		"layerHeights": layers,
		"waterHeights": water_h,
		"flagsPacked": flags,
	}
	info = {"name": "Untitled", "flags": {}}
	map_dir = ""
	source_name = "untitled"
	brush_tile_index = tile_index
	_dirty = true
	dirty_changed.emit(true)
	changed.emit()


## 将整格四角写成当前笔刷地表索引。tx/ty 为地形格（非 tilepoint）。
func paint_tile(tx: int, ty: int, tex_index: int = -1) -> bool:
	if is_empty():
		return false
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	var map_w: int = tp_w - 1
	var map_h: int = tp_h - 1
	if tx < 0 or ty < 0 or tx >= map_w or ty >= map_h:
		return false
	var changed_any: bool = false
	for c in [
		Vector2i(tx, ty),
		Vector2i(tx + 1, ty),
		Vector2i(tx, ty + 1),
		Vector2i(tx + 1, ty + 1),
	]:
		if paint_corner(c.x, c.y, tex_index):
			changed_any = true
	return changed_any


## 写单个中级栅格顶点（tilepoint）的地表索引。对齐 WE / HiveWE 角点笔刷。
func paint_corner(ix: int, iy: int, tex_index: int = -1) -> bool:
	if is_empty():
		return false
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return false
	var idx: int = tex_index if tex_index >= 0 else brush_tile_index
	var gs: Array = hf["groundTilesets"]
	if idx < 0 or idx >= gs.size():
		return false
	var ground: Array = hf["groundTextures"]
	var ground_var: Array = hf["groundVariations"]
	var i: int = iy * tp_w + ix
	if i < 0 or i >= ground.size():
		return false
	var changed_any: bool = false
	if int(ground[i]) != idx:
		ground[i] = idx
		changed_any = true
	if i < ground_var.size():
		ground_var[i] = Wc3TerrainAutotile.random_ground_variation()
		changed_any = true
	if changed_any:
		mark_dirty()
	return changed_any


## 悬崖笔刷：按 WorldEditData 工具 id 改 layerHeights / heights / 水 / 斜坡 / 悬崖类型。
## tool_id: "0".."4"（降两/降一/整平/升一/升两）| "ShallowWater" | "DeepWater" | "Ramp"
## level_layer: 整平目标层；<0 时用当前顶点层（无效果）。
func paint_cliff_corner(
	ix: int,
	iy: int,
	tool_id: String,
	cliff_type_idx: int = -1,
	level_layer: int = -1
) -> bool:
	if is_empty():
		return false
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	if ix < 0 or iy < 0 or ix >= tp_w or iy >= tp_h:
		return false
	var i: int = iy * tp_w + ix
	var layers: Array = hf.get("layerHeights", []) as Array
	var heights: Array = hf.get("heights", []) as Array
	var water_h: Array = hf.get("waterHeights", []) as Array
	var flags: Array = hf.get("flagsPacked", []) as Array
	var cliff_tex: Array = hf.get("cliffTextures", []) as Array
	var cliff_var: Array = hf.get("cliffVariations", []) as Array
	if i < 0 or i >= layers.size() or i >= heights.size() or i >= flags.size():
		return false

	var ctype: int = cliff_type_idx if cliff_type_idx >= 0 else brush_cliff_type
	var cts: Array = cliff_tilesets()
	if not cts.is_empty():
		ctype = clampi(ctype, 0, cts.size() - 1)

	var changed_any := false
	var propagate := -1
	var touched: Array = [] ## Vector2i：层高被改动的顶点，用于同步 cliff/ground 贴图
	match tool_id:
		"0":
			if _apply_layer_delta(i, layers, heights, water_h, -2):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = CliffPropagate.LOWER_HIGHER
		"1":
			if _apply_layer_delta(i, layers, heights, water_h, -1):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = CliffPropagate.LOWER_HIGHER
		"2":
			var target: int = level_layer if level_layer >= 0 else int(layers[i])
			if _set_layer(i, layers, heights, water_h, target):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = CliffPropagate.BOTH
		"3":
			if _apply_layer_delta(i, layers, heights, water_h, 1):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = CliffPropagate.RAISE_LOWER
		"4":
			if _apply_layer_delta(i, layers, heights, water_h, 2):
				changed_any = true
				touched.append(Vector2i(ix, iy))
			propagate = CliffPropagate.RAISE_LOWER
		"ShallowWater":
			changed_any = _paint_water(i, heights, water_h, flags, WATER_SHALLOW_EXTRA) or changed_any
		"DeepWater":
			changed_any = _paint_water(i, heights, water_h, flags, WATER_DEEP_EXTRA) or changed_any
		"Ramp":
			# feature/ramp-rebuild：斜坡已清空
			return paint_ramp_at(ix, iy)
		_:
			return false

	if changed_any and propagate >= 0:
		var raised: Array = _propagate_cliff_adjacency(
			ix, iy, tp_w, tp_h, layers, heights, water_h, propagate
		)
		if not raised.is_empty():
			changed_any = true
			touched.append_array(raised)

	# 策略 B（异种崖折中）：
	# - 本笔种子角 ∪「至少含一个种子角的直崖格」四角 → 强制当前 ctype + groundTile（接触即同化）
	# - 不按 AABB 扫无关旧崖（远处隔离）；接触旧异种崖是「转换类型」，不是远程删除
	# - 蛋糕外扩仍可能改层高而抹平旧形（与 WE 一致）
	# 只写笔刷 2×2 时，外扩崖格 i00 仍是默认泥土崖 → _corner_texture 会强制 Ldrt 硬边。
	var ground_tex: Array = hf.get("groundTextures", []) as Array
	var ground_var: Array = hf.get("groundVariations", []) as Array
	var gti: int = _ground_index_for_cliff_type(ctype)
	if (not cts.is_empty() or gti >= 0) and (
		propagate >= 0 or tool_id in ["0", "1", "2", "3", "4"]
	):
		if _sync_cliff_corner_textures(
			ix, iy, tp_w, tp_h, layers, cliff_tex, cliff_var, ground_tex, ground_var, ctype, gti, touched
		):
			changed_any = true

	if changed_any:
		mark_dirty()
	return changed_any


## 斜坡笔刷（feature/ramp-rebuild：已清空，待逐步重做）。
func paint_ramp_at(ix: int, iy: int) -> bool:
	var r: Dictionary = try_paint_ramp_at(ix, iy)
	last_ramp_message = str(r.get("message", ""))
	return bool(r.get("ok", false))


func try_paint_ramp_at(_ix: int, _iy: int) -> Dictionary:
	return {"ok": false, "message": "斜坡逻辑已清空，等待重建"}


func peek_ramp_strip_at(_ix: int, _iy: int) -> Dictionary:
	return {}


## 策略 B：同步与落笔/层高变更相关的直崖格四角（cliffTextures + groundTile）。
## 种子 = touched ∪ 落笔 2×2；再并入「至少含一个种子角」的直崖格之四角（整格同化，避免混角）。
## 禁止用 AABB 扫区域内所有直崖（会误改邻近另一座未触及的悬崖）。
func _sync_cliff_corner_textures(
	ix: int,
	iy: int,
	tp_w: int,
	tp_h: int,
	layers: Array,
	cliff_tex: Array,
	cliff_var: Array,
	ground_tex: Array,
	ground_var: Array,
	ctype: int,
	gti: int,
	touched: Array
) -> bool:
	var seed: Dictionary = {}
	for p in touched:
		seed[Vector2i(int(p.x), int(p.y))] = true
	# 落笔点邻域（整平未改层时仍要刷类型/地表）
	for oy in range(-1, 1):
		for ox in range(-1, 1):
			seed[Vector2i(ix + ox, iy + oy)] = true

	var corner_pts: Dictionary = {}
	for key in seed.keys():
		var p: Vector2i = key
		corner_pts[p] = true
		# 以该角为顶点的最多 4 个地表格：若是直崖则并入其四角
		for oy in range(-1, 1):
			for ox in range(-1, 1):
				var tx: int = p.x + ox
				var ty: int = p.y + oy
				if tx < 0 or ty < 0 or tx >= tp_w - 1 or ty >= tp_h - 1:
					continue
				if not Wc3CliffTiles.is_cliff_tile(layers, tp_w, tx, ty):
					continue
				for cy in range(0, 2):
					for cx in range(0, 2):
						corner_pts[Vector2i(tx + cx, ty + cy)] = true

	var any := false
	for key2 in corner_pts.keys():
		var q: Vector2i = key2
		if q.x < 0 or q.y < 0 or q.x >= tp_w or q.y >= tp_h:
			continue
		var ci: int = q.y * tp_w + q.x
		if ctype >= 0 and ci < cliff_tex.size():
			var prev_tex: int = int(cliff_tex[ci])
			if prev_tex != ctype:
				cliff_tex[ci] = ctype
				any = true
			# 类型变化时随机变体；同类型但变体为 0 时写 1..max 避免整墙同模
			if ci < cliff_var.size():
				if prev_tex != ctype:
					cliff_var[ci] = (randi() % 3) + 1
					any = true
				elif int(cliff_var[ci]) == 0:
					cliff_var[ci] = (absi(ci * 2654435761) % 3) + 1
					any = true
		if gti >= 0 and ci < ground_tex.size() and int(ground_tex[ci]) != gti:
			ground_tex[ci] = gti
			any = true
			if ci < ground_var.size():
				ground_var[ci] = Wc3TerrainAutotile.random_ground_variation()
	return any


func _apply_layer_delta(
	i: int, layers: Array, heights: Array, water_h: Array, delta: int
) -> bool:
	return _set_layer(i, layers, heights, water_h, int(layers[i]) + delta)


## 返回 cliffTilesets[ctype] 对应的 groundTilesets 下标；找不到则 -1。
func _ground_index_for_cliff_type(ctype: int) -> int:
	var cts: Array = cliff_tilesets()
	var gs: Array = ground_tilesets()
	if ctype < 0 or ctype >= cts.size() or gs.is_empty():
		return -1
	if _cliff_ground_cache.size() != cts.size():
		_cliff_ground_cache = PackedInt32Array()
		_cliff_ground_cache.resize(cts.size())
		_cliff_ground_cache.fill(-2) # -2=未缓存
	if _cliff_ground_cache[ctype] != -2:
		return _cliff_ground_cache[ctype]
	var tiles := Wc3TerrainTiles.new()
	tiles.load_default()
	var ground_id := tiles.ground_tile_for_cliff_id(str(cts[ctype]))
	var found := -1
	if not ground_id.is_empty():
		for gi in range(gs.size()):
			if str(gs[gi]) == ground_id:
				found = gi
				break
	_cliff_ground_cache[ctype] = found
	return found


## WE：相邻顶点层差不得超过 2，且每个地表格四角跨度 ≤2。
## 升崖：过低点抬到 high−2（蛋糕外扩）；降崖：过高点压到 low+2。BFS 扩散。
## 返回本次被改层高的顶点列表。
func _propagate_cliff_adjacency(
	ix: int,
	iy: int,
	tp_w: int,
	tp_h: int,
	layers: Array,
	heights: Array,
	water_h: Array,
	mode: int
) -> Array:
	var queue: Array = [Vector2i(ix, iy)]
	var changed_pts: Array = []
	var guard := 0
	var guard_max: int = tp_w * tp_h * 16
	var dirs: Array = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]
	while not queue.is_empty() and guard < guard_max:
		guard += 1
		var p: Vector2i = queue.pop_front()
		var i: int = p.y * tp_w + p.x
		if i < 0 or i >= layers.size():
			continue
		var lv: int = int(layers[i])
		for d in dirs:
			var nx: int = p.x + int(d.x)
			var ny: int = p.y + int(d.y)
			if nx < 0 or ny < 0 or nx >= tp_w or ny >= tp_h:
				continue
			var ni: int = ny * tp_w + nx
			if ni < 0 or ni >= layers.size():
				continue
			var ln: int = int(layers[ni])
			var did := false
			if mode != CliffPropagate.LOWER_HIGHER and lv > ln + MAX_CLIFF_ADJ_DELTA:
				did = _set_layer(ni, layers, heights, water_h, lv - MAX_CLIFF_ADJ_DELTA)
			elif mode != CliffPropagate.RAISE_LOWER and ln > lv + MAX_CLIFF_ADJ_DELTA:
				did = _set_layer(ni, layers, heights, water_h, lv + MAX_CLIFF_ADJ_DELTA)
			if did:
				var np := Vector2i(nx, ny)
				changed_pts.append(np)
				queue.append(np)
		# 以本顶点为角的最多 4 个地表格：强制四角 max−min ≤ 2（补上对角约束）
		_enforce_tile_spans_at(
			p.x, p.y, tp_w, tp_h, layers, heights, water_h, mode, queue, changed_pts
		)
	return changed_pts


## 检查以 (vx,vy) 为角的地表格；若跨度 >2 则按 mode 抬低/压高角点，变更入队。
func _enforce_tile_spans_at(
	vx: int,
	vy: int,
	tp_w: int,
	tp_h: int,
	layers: Array,
	heights: Array,
	water_h: Array,
	mode: int,
	queue: Array,
	changed_pts: Array
) -> void:
	for oy in range(-1, 1):
		for ox in range(-1, 1):
			var tx: int = vx + ox
			var ty: int = vy + oy
			if tx < 0 or ty < 0 or tx >= tp_w - 1 or ty >= tp_h - 1:
				continue
			var i00: int = ty * tp_w + tx
			var i10: int = i00 + 1
			var i01: int = i00 + tp_w
			var i11: int = i01 + 1
			var c0: int = int(layers[i00])
			var c1: int = int(layers[i10])
			var c2: int = int(layers[i01])
			var c3: int = int(layers[i11])
			var lo: int = mini(mini(c0, c1), mini(c2, c3))
			var hi: int = maxi(maxi(c0, c1), maxi(c2, c3))
			if hi - lo <= MAX_CLIFF_ADJ_DELTA:
				continue
			var corners: Array = [
				Vector2i(tx, ty),
				Vector2i(tx + 1, ty),
				Vector2i(tx, ty + 1),
				Vector2i(tx + 1, ty + 1),
			]
			var floor_l: int = hi - MAX_CLIFF_ADJ_DELTA
			var ceil_l: int = lo + MAX_CLIFF_ADJ_DELTA
			for c in corners:
				var ci: int = int(c.y) * tp_w + int(c.x)
				var lv: int = int(layers[ci])
				var did := false
				if mode != CliffPropagate.LOWER_HIGHER and lv < floor_l:
					did = _set_layer(ci, layers, heights, water_h, floor_l)
				elif mode != CliffPropagate.RAISE_LOWER and lv > ceil_l:
					did = _set_layer(ci, layers, heights, water_h, ceil_l)
				if did:
					changed_pts.append(c)
					queue.append(c)


func _set_layer(
	i: int, layers: Array, heights: Array, water_h: Array, new_layer: int
) -> bool:
	var clamped: int = clampi(new_layer, LAYER_MIN, LAYER_MAX)
	var old_layer: int = int(layers[i])
	if clamped == old_layer:
		return false
	var dh: float = float(clamped - old_layer) * LAYER_HEIGHT_STEP
	layers[i] = clamped
	heights[i] = float(heights[i]) + dh
	if i < water_h.size():
		water_h[i] = float(water_h[i]) + dh
	return true


func _paint_water(
	i: int, heights: Array, water_h: Array, flags: Array, water_extra: float
) -> bool:
	var did := false
	var fl: int = int(flags[i])
	var nf: int = (fl | FLAG_WATER) & ~FLAG_RAMP
	if nf != fl:
		flags[i] = nf
		did = true
	var target_w: float = float(heights[i]) + water_extra
	if i < water_h.size() and not is_equal_approx(float(water_h[i]), target_w):
		water_h[i] = target_w
		did = true
	return did


func sample_height_at_tile(tx: int, ty: int) -> float:
	if is_empty():
		return 0.0
	var tp_w: int = int(hf["tilepointWidth"])
	var heights: Array = hf["heights"]
	var sum: float = 0.0
	var n: int = 0
	for c in [
		ty * tp_w + tx,
		ty * tp_w + tx + 1,
		(ty + 1) * tp_w + tx,
		(ty + 1) * tp_w + tx + 1,
	]:
		if c >= 0 and c < heights.size():
			sum += float(heights[c])
			n += 1
	return sum / float(n) if n > 0 else 0.0


func world_godot_to_tile(godot_pos: Vector3) -> Vector2i:
	var ws: float = Wc3Coords.WORLD_SCALE
	var center: Vector2 = center_offset()
	var ts: float = tile_size()
	var wc3_x: float = godot_pos.x / ws
	var wc3_y: float = -godot_pos.z / ws
	var tx: int = int(floor((wc3_x - center.x) / ts))
	var ty: int = int(floor((wc3_y - center.y) / ts))
	return Vector2i(tx, ty)


## 吸附到最近的中级栅格顶点（tilepoint），对齐经典 WE。
func world_godot_to_tilepoint(godot_pos: Vector3) -> Vector2i:
	var ws: float = Wc3Coords.WORLD_SCALE
	var center: Vector2 = center_offset()
	var ts: float = tile_size()
	if ts <= 0.0:
		return Vector2i.ZERO
	var wc3_x: float = godot_pos.x / ws
	var wc3_y: float = -godot_pos.z / ws
	var ix: int = int(round((wc3_x - center.x) / ts))
	var iy: int = int(round((wc3_y - center.y) / ts))
	return Vector2i(ix, iy)


## 双线性采样高度（tilepoint 连续坐标）。
func sample_height_at_xy(fx: float, fy: float) -> float:
	if is_empty():
		return 0.0
	var tp_w: int = int(hf["tilepointWidth"])
	var tp_h: int = int(hf["tilepointHeight"])
	var heights: Array = hf["heights"]
	var x0: int = int(floor(fx))
	var y0: int = int(floor(fy))
	var x1: int = x0 + 1
	var y1: int = y0 + 1
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)

	var h00 := _corner_height_clamped(x0, y0, tp_w, tp_h, heights)
	var h10 := _corner_height_clamped(x1, y0, tp_w, tp_h, heights)
	var h01 := _corner_height_clamped(x0, y1, tp_w, tp_h, heights)
	var h11 := _corner_height_clamped(x1, y1, tp_w, tp_h, heights)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), ty)


func _corner_height_clamped(ix: int, iy: int, tp_w: int, tp_h: int, heights: Array) -> float:
	var cx: int = clampi(ix, 0, tp_w - 1)
	var cy: int = clampi(iy, 0, tp_h - 1)
	var i: int = cy * tp_w + cx
	if i < 0 or i >= heights.size():
		return 0.0
	return float(heights[i])


func save_json(path: String = "") -> Error:
	if is_empty():
		return ERR_INVALID_DATA
	var out_path: String = path
	if out_path.is_empty():
		var dir: String = "user://editor_maps"
		var abs_dir: String = ProjectSettings.globalize_path(dir)
		DirAccess.make_dir_recursive_absolute(abs_dir)
		var stamp: String = Time.get_datetime_string_from_system().replace(":", "-")
		out_path = dir.path_join("%s_%s.json" % [source_name if not source_name.is_empty() else "map", stamp])
	else:
		var parent: String = out_path.get_base_dir()
		if not parent.is_empty():
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(parent))
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("MapDocument: cannot write %s (err=%s)" % [out_path, FileAccess.get_open_error()])
		return ERR_CANT_CREATE
	f.store_string(JSON.stringify(hf, "\t"))
	clear_dirty()
	print("MapDocument: saved %s" % out_path)
	return OK
